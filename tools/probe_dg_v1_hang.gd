extends SceneTree

## DG-V1 generator hang probe (docs/handoff-dg-v1-generator-hang.md §5.2).
##
## Calls DungeonGeneratorV1.generate across a seed range for a named preset,
## printing per-call elapsed ms to STDERR (printerr survives a kill; piped
## stdout does not). If the process wedges, the last "BEGIN seed=N" line on
## stderr identifies the offending seed.
##
## The generator scripts reference autoload singletons (CampaignRepository),
## which do not exist yet when --script mainloop scripts are compiled — so the
## generator is load()ed at runtime on the first process frame, after the
## autoloads have been added to the tree.
##
## Usage:
##   Godot_console.exe --headless --path . --script res://tools/probe_dg_v1_hang.gd \
##       -- <preset> <seed_from> <seed_to>
##   presets: lair1 | medium3 | six_floor
##
## All runs use persist = false (no DB writes).

var _ran := false
var _deadline_ms: int = 0


func _initialize() -> void:
	# Watchdog: if the probe body errors before quit() (a GDScript runtime error
	# aborts _run_once but NOT the process), the frame loop would spin forever
	# holding the campaign.db handle and poisoning concurrent test runs with
	# "database is locked" — force-quit at a hard deadline instead.
	_deadline_ms = Time.get_ticks_msec() + 15 * 60 * 1000
	process_frame.connect(_watchdog)
	process_frame.connect(_run_once)


func _watchdog() -> void:
	if Time.get_ticks_msec() > _deadline_ms:
		printerr("PROBE WATCHDOG: deadline exceeded (probe body likely errored before quit) — forcing exit.")
		quit(2)


func _run_once() -> void:
	if _ran:
		return
	_ran = true

	var generator: GDScript = load(
		"res://engine/subsystems/generation/dungeon_generator_v1/dungeon_generator_v1.gd")
	var request_script: GDScript = load(
		"res://engine/shared_types/dungeon_generator_request_v1.gd")

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var preset: String = args[0] if args.size() >= 1 else "medium3"
	var seed_from: int = int(args[1]) if args.size() >= 2 else 12345
	var seed_to: int = int(args[2]) if args.size() >= 3 else seed_from

	printerr("PROBE start preset=%s seeds=%d..%d" % [preset, seed_from, seed_to])
	var total_t0: int = Time.get_ticks_msec()

	for s in range(seed_from, seed_to + 1):
		var req = request_script.new()
		req.entrance_floor_index = 1
		req.dungeon_type = "wizards_dungeon"
		req.persist = false
		req.seed = s
		match preset:
			"lair1":
				req.entrance_tier = 1
				req.floor_count = 1
				req.dungeon_size = "lair"
			"six_floor":
				req.entrance_tier = 1
				req.floor_count = 6
				req.dungeon_size = "medium"
			_:
				req.entrance_tier = 1
				req.floor_count = 3
				req.dungeon_size = "medium"

		printerr("PROBE BEGIN seed=%d" % s)
		var t0: int = Time.get_ticks_msec()
		var result = generator.generate(req)
		var dt: int = Time.get_ticks_msec() - t0
		var ok: bool = result != null and result.success
		var err_count: int = 0 if result == null else result.errors.size()
		printerr("PROBE END seed=%d dt_ms=%d success=%s errors=%d fp=%s"
			% [s, dt, str(ok), err_count, _fingerprint(result)])

	printerr("PROBE done total_ms=%d" % (Time.get_ticks_msec() - total_t0))
	quit(0)


## Compact deterministic fingerprint of a result, for same-seed comparison
## across runs. Ids are per-process random, so exclude them — use structural
## counts and positions only.
func _fingerprint(result) -> String:
	if result == null:
		return "null"
	var parts: Array[String] = []
	for layout in result.floors:
		var door_acc: int = 0
		for door in layout.doors:
			door_acc += door.position.x * 31 + door.position.y * 7
			door_acc += 1000 if door.is_secret else 0
		var hoard_gp: int = 0
		for h in layout.treasure_hoards:
			hoard_gp += h.total_gp_value
		parts.append("r%d_d%d_da%d_s%d_g%d" % [
			layout.rooms.size(), layout.doors.size(), door_acc,
			layout.stairs.size(), hoard_gp])
	return "|".join(parts)
