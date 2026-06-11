extends SceneTree

## Stage-level timing probe for DG-V1 (companion to probe_dg_v1_hang.gd).
## Mirrors _generate_attempt stage by stage for ONE seed and prints per-stage
## elapsed ms to stderr, so optimization effort lands where the time goes.
##
## Usage:
##   Godot_console.exe --headless --path . --script res://tools/probe_dg_v1_stages.gd \
##       -- <seed> [floors] [size]

var _ran := false
var _deadline_ms: int = 0


func _initialize() -> void:
	# Watchdog: if the probe body errors before quit() (a GDScript runtime error
	# aborts _run_once but NOT the process), the frame loop would spin forever
	# holding the campaign.db handle and poisoning concurrent test runs with
	# "database is locked" — force-quit at a hard deadline instead.
	_deadline_ms = Time.get_ticks_msec() + 5 * 60 * 1000
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

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var master_seed: int = int(args[0]) if args.size() >= 1 else 12345
	var floor_count: int = int(args[1]) if args.size() >= 2 else 3
	var size: String = args[2] if args.size() >= 3 else "medium"

	var loader_script: GDScript = load(
		"res://engine/subsystems/generation/dungeon_generator_v1/loaders/dungeon_data_loader.gd")
	var registry_script: GDScript = load("res://engine/subsystems/monsters/monster_registry.gd")
	var layout_gen: GDScript = load(
		"res://engine/subsystems/generation/dungeon_layout/dungeon_layout_generator.gd")
	var layout_req_script: GDScript = load(
		"res://engine/subsystems/generation/dungeon_layout/dungeon_layout_request.gd")
	var stocker: GDScript = load(
		"res://engine/subsystems/generation/dungeon_generator_v1/stocker.gd")
	var kl_placer: GDScript = load(
		"res://engine/subsystems/generation/dungeon_generator_v1/key_lever_placer.gd")
	var nav: GDScript = load(
		"res://engine/subsystems/generation/dungeon_generator_v1/navigability_validator.gd")
	var acceptance: GDScript = load(
		"res://engine/subsystems/generation/dungeon_generator_v1/acceptance_tests.gd")
	var result_script: GDScript = load("res://engine/shared_types/dungeon_generator_result_v1.gd")

	var t0: int

	t0 = Time.get_ticks_msec()
	var loader = loader_script.new()
	loader.load_all()
	printerr("STAGE loader.load_all dt_ms=%d" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	var registry = registry_script.new()
	printerr("STAGE MonsterRegistry.new dt_ms=%d" % (Time.get_ticks_msec() - t0))

	# ---- floors ----
	var floors: Array[DungeonLayout] = []
	var prev_down: Array = []
	for floor_index in range(1, floor_count + 1):
		var req = layout_req_script.new()
		req.dungeon_type = "wizards_dungeon"
		req.dungeon_size = size
		req.level_number = floor_index
		req.floor_tier = 1
		req.is_entrance_floor = (floor_index == 1)
		req.seed = master_seed + floor_index * 1000003
		req.stairs_down = 1 if floor_index < floor_count else 0
		req.required_stair_positions = []
		for p in prev_down:
			req.required_stair_positions.append({"position": p, "direction": "up"})
		req.stairs_up = 1 if floor_index == 1 else prev_down.size()

		t0 = Time.get_ticks_msec()
		var layout = layout_gen.generate(req)
		printerr("STAGE layout floor=%d dt_ms=%d" % [floor_index, Time.get_ticks_msec() - t0])
		if layout == null:
			printerr("STAGE ABORT floor=%d layout null" % floor_index)
			quit(1)
			return
		layout.dungeon_id = "stage_probe"
		floors.append(layout)
		prev_down = []
		for s in layout.stairs:
			if s.direction == "down":
				prev_down.append(s.position)

	# connects_to_level wiring (cheap, mirrors orchestrator)
	for fi in range(floors.size()):
		for s in floors[fi].stairs:
			if s.direction == "down":
				s.connects_to_level = fi + 2
			elif s.direction == "up" and fi > 0:
				s.connects_to_level = fi

	# ---- one stocking pass ----
	t0 = Time.get_ticks_msec()
	for fi in range(floors.size()):
		var floor_rng := RandomNumberGenerator.new()
		floor_rng.seed = master_seed + (fi + 1) * 7919
		stocker.stock_floor(floors[fi], loader, registry, floor_rng)
	printerr("STAGE stock_all_floors dt_ms=%d" % (Time.get_ticks_msec() - t0))

	# ---- key/lever placement ----
	t0 = Time.get_ticks_msec()
	var kl_rng := RandomNumberGenerator.new()
	kl_rng.seed = master_seed + 104729
	var keys = kl_placer.place(floors, 1, kl_rng)
	printerr("STAGE key_lever_place dt_ms=%d keys=%d" % [Time.get_ticks_msec() - t0, keys.size()])

	t0 = Time.get_ticks_msec()
	kl_placer.finalize_key_placements(keys, floors, loader, kl_rng)
	printerr("STAGE key_finalize dt_ms=%d" % (Time.get_ticks_msec() - t0))

	# ---- solvability ----
	var typed_keys: Array[KeyItemData] = []
	for k in keys:
		typed_keys.append(k)
	t0 = Time.get_ticks_msec()
	var solv: Dictionary = nav.validate_solvability(floors, typed_keys, 1)
	printerr("STAGE solvability dt_ms=%d ok=%s" % [Time.get_ticks_msec() - t0, str(solv["ok"])])

	# ---- acceptance ----
	var result = result_script.new()
	result.floors = floors
	result.key_items = typed_keys
	t0 = Time.get_ticks_msec()
	var report: Dictionary = acceptance.run(result)
	printerr("STAGE acceptance dt_ms=%d hard_pass=%s" % [
		Time.get_ticks_msec() - t0, str(report.get("hard_pass", false))])

	printerr("STAGE done")
	quit(0)
