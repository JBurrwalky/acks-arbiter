extends Node

## Throwaway perf probe for the DG-C3D.F.2c fixpoint fix — times the two
## slow-generation offenders (medium 3-floor seed 2001, small 6-floor seed 77).
## Not registered in the test runner; run directly:
##   godot --headless --path . res://tests/tools/dungeon_perf_probe.tscn


func _ready() -> void:
	_probe("medium 3-floor", "medium", 3, 1, 2001)
	_probe("small 6-floor tier-clamp", "small", 6, 3, 77)
	get_tree().quit(0)


func _probe(label: String, size: String, floors: int, tier: int, p_seed: int) -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = tier
	req.floor_count = floors
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = size
	req.seed = p_seed
	req.persist = false
	var t0: int = Time.get_ticks_msec()
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	var elapsed: int = Time.get_ticks_msec() - t0
	print("PROBE %s seed=%d: %d ms, success=%s, floors=%d, stairwells=%d, zones=%d, keys=%d, warnings=%d" % [
		label, p_seed, elapsed, str(result.success), result.floors.size(),
		result.stairwells.size(), result.zones.size(), result.key_items.size(),
		result.warnings.size()])
