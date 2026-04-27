extends "res://tests/test_suite_base.gd"

## B1 — Wilderness combat map sizing + ACKS encounter-distance spawn placement.
## Verifies the static helpers extracted from CombatState._place_combatants_on_grid.


class FakeDice:
	extends RefCounted
	var fixed: int = 1
	func _init(value: int = 1) -> void:
		fixed = value
	func roll_digital(_sides: int, _count: int = 1, _mod: int = 0,
			_label: String = "") -> RollResult:
		var rr := RollResult.new()
		rr.modified_total = fixed
		return rr


func run_all_tests() -> void:
	test_open_field_is_100x100()
	test_encounter_distance_spec_per_terrain()
	test_max_offset_clamps_to_map_edge()
	test_roll_encounter_distance_cells_plains_clamped()
	test_roll_encounter_distance_cells_jungle_short()
	if not has_failures():
		print("CombatStateSpawn: all tests passed.")


func test_open_field_is_100x100() -> void:
	# B1 acceptance: wilderness battle map size matches GDD §3 (500'×500').
	var vmap := VoxelMapData.generate_open_field(100, 100)
	check(vmap.cell_count() == 10000,
		"100×100 field should have 10000 cells, got %d" % vmap.cell_count())
	check(vmap.has_cell(Vector3i(99, 99, 0)),
		"corner cell (99,99,0) should exist on a 100×100 map")
	check(not vmap.has_cell(Vector3i(100, 0, 0)),
		"cell at x=100 should not exist on a 100×100 map")


func test_encounter_distance_spec_per_terrain() -> void:
	# acore_adventures_and_encounters.xml §encounter_distance_table.
	check(CombatState._encounter_distance_spec("clear") == [5, 20, 10],
		"clear terrain should be 5d20×10 yards (Plains)")
	check(CombatState._encounter_distance_spec("woods") == [5, 8, 1],
		"woods should be 5d8 yards (Forest, Light)")
	check(CombatState._encounter_distance_spec("jungle") == [5, 4, 1],
		"jungle should be 5d4 yards (Forest, Heavy)")
	check(CombatState._encounter_distance_spec("swamp") == [8, 10, 1],
		"swamp should be 8d10 yards (Marsh)")
	check(CombatState._encounter_distance_spec("mountains") == [4, 6, 10],
		"mountains should be 4d6×10 yards")
	check(CombatState._encounter_distance_spec("desert") == [4, 6, 10],
		"desert should be 4d6×10 yards")
	# Unknown / fallback should default to Plains so ranged combat has room.
	check(CombatState._encounter_distance_spec("ocean") == [5, 20, 10],
		"unrecognised terrain falls back to Plains 5d20×10")


func test_max_offset_clamps_to_map_edge() -> void:
	var vmap := VoxelMapData.generate_open_field(100, 100)
	var entry := vmap.entry_pos
	var max_off: int = CombatState._max_offset_from_entry(entry, vmap)
	# Entry on a 100×100 open field is at (2, 50, 0) per generate_open_field.
	# So max_off should leave room for a 1-cell margin: 100 - 2 - 1 = 97 → -1 = 96.
	check(max_off >= 90,
		"max_offset on 100-wide map should be >=90, got %d" % max_off)
	check(max_off < 100,
		"max_offset must stay inside the map, got %d" % max_off)


func test_roll_encounter_distance_cells_plains_clamped() -> void:
	# Force a max-roll: 5 dice × 20 sides × 10 yards = 1000 yards = 600 cells.
	# Caller will clamp to map. Helper itself returns the raw cell distance.
	var dice := FakeDice.new(20)  # each d20 roll = 20
	var cells: int = CombatState._roll_encounter_distance_cells("clear", dice)
	# 5×20 = 100 dice total, ×10 = 1000 yards, ×0.6 = 600 cells.
	check(cells == 600,
		"plains max roll should be 600 cells, got %d" % cells)


func test_roll_encounter_distance_cells_jungle_short() -> void:
	var dice := FakeDice.new(2)  # each d4 = 2
	var cells: int = CombatState._roll_encounter_distance_cells("jungle", dice)
	# 5×2 = 10 yards, ×0.6 = 6 cells.
	check(cells == 6,
		"jungle 5d4 (each=2) should yield 6 cells, got %d" % cells)
