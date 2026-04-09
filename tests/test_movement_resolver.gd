extends "res://tests/test_suite_base.gd"

## Unit tests for MovementResolver: pathfinding, distance, adjacency, LOS, charge.


func run_all_tests() -> void:
	test_no_grid_returns_defaults()
	test_distance_cells_adjacent()
	test_distance_cells_far()
	test_is_adjacent_true()
	test_is_adjacent_false()
	test_is_engaged_with_enemy()
	test_is_engaged_no_enemy()
	test_find_path_open_grid()
	test_find_path_with_wall()
	test_find_path_unreachable()
	test_can_reach_within_budget()
	test_can_reach_over_budget()
	test_move_along_path()
	test_los_clear()
	test_los_blocked()
	test_charge_valid()
	test_charge_too_close()
	test_charge_blocked()
	if not has_failures():
		print("MovementResolver: all tests passed.")


# ---------------------------------------------------------------------------
# No-grid fallback
# ---------------------------------------------------------------------------

func test_no_grid_returns_defaults() -> void:
	var roster := CombatRoster.new()
	var resolver: MovementResolver = MovementResolver.new(null, roster)
	check(not resolver.has_grid(), "no grid should return false")
	var c := _make_monster_combatant("m1", 5, 5)
	check(resolver.get_distance_cells(c, c) == -1, "distance should be -1 without grid")
	check(resolver.get_distance_ft(c, c) == -1, "distance_ft should be -1 without grid")


# ---------------------------------------------------------------------------
# Distance and adjacency
# ---------------------------------------------------------------------------

func test_distance_cells_adjacent() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(3, 3))
	env.resolver.set_grid_position(env.monster, Vector2i(4, 3))
	check(env.resolver.get_distance_cells(env.pc, env.monster) == 1,
		"adjacent cells should be distance 1")


func test_distance_cells_far() -> void:
	var env := _make_grid_env(20, 20)
	env.resolver.set_grid_position(env.pc, Vector2i(0, 0))
	env.resolver.set_grid_position(env.monster, Vector2i(7, 5))
	check(env.resolver.get_distance_cells(env.pc, env.monster) == 7,
		"Chebyshev distance should be max(7,5) = 7")


func test_is_adjacent_true() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(5, 5))
	env.resolver.set_grid_position(env.monster, Vector2i(5, 6))
	check(env.resolver.is_adjacent(env.pc, env.monster),
		"one cell apart should be adjacent")


func test_is_adjacent_false() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(2, 2))
	env.resolver.set_grid_position(env.monster, Vector2i(5, 5))
	check(not env.resolver.is_adjacent(env.pc, env.monster),
		"3 cells apart should not be adjacent")


func test_is_engaged_with_enemy() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(5, 5))
	env.resolver.set_grid_position(env.monster, Vector2i(5, 6))
	check(env.resolver.is_engaged(env.pc),
		"PC should be engaged when monster is adjacent")


func test_is_engaged_no_enemy() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(0, 0))
	env.resolver.set_grid_position(env.monster, Vector2i(8, 8))
	check(not env.resolver.is_engaged(env.pc),
		"PC should not be engaged when monster is far away")


# ---------------------------------------------------------------------------
# Pathfinding
# ---------------------------------------------------------------------------

func test_find_path_open_grid() -> void:
	var env := _make_grid_env(10, 10)
	var path: Array[Vector2i] = env.resolver.find_path(Vector2i(0, 0), Vector2i(3, 0))
	check(not path.is_empty(), "path should exist on open grid")
	check(path[0] == Vector2i(0, 0), "path should start at origin")
	check(path[-1] == Vector2i(3, 0), "path should end at goal")
	check(path.size() <= 5, "path should be short on open grid")


func test_find_path_with_wall() -> void:
	var env := _make_grid_env(10, 10)
	# Place a wall across the middle
	for row in range(10):
		if row != 5:  # Leave a gap at row 5
			env.map.set_cell_field(Vector2i(5, row), "terrain_feature", "wall_stone")
			env.map.set_cell_field(Vector2i(5, row), "passable", false)
			env.map.set_cell_field(Vector2i(5, row), "blocks_los", true)
	var path: Array[Vector2i] = env.resolver.find_path(Vector2i(3, 3), Vector2i(7, 3))
	check(not path.is_empty(), "should find path through gap")
	check(path[-1] == Vector2i(7, 3), "should reach goal through gap")


func test_find_path_unreachable() -> void:
	var env := _make_grid_env(10, 10)
	# Completely wall off column 5
	for row in range(10):
		env.map.set_cell_field(Vector2i(5, row), "terrain_feature", "wall_stone")
		env.map.set_cell_field(Vector2i(5, row), "passable", false)
	var path: Array[Vector2i] = env.resolver.find_path(Vector2i(3, 3), Vector2i(7, 3))
	check(path.is_empty(), "path should be empty when fully blocked")


func test_can_reach_within_budget() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(0, 0))
	check(env.resolver.can_reach(env.pc, Vector2i(3, 0), 5),
		"should be reachable within 5 cells")


func test_can_reach_over_budget() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(0, 0))
	check(not env.resolver.can_reach(env.pc, Vector2i(8, 0), 3),
		"should not be reachable with only 3 cells budget")


func test_move_along_path() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(0, 0))
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var moved: int = env.resolver.move_along_path(env.pc, path, 2)
	check(moved == 2, "should move 2 cells, got %d" % moved)
	check(env.resolver.get_grid_position(env.pc) == Vector2i(2, 0),
		"should be at (2,0) after moving 2 cells")


# ---------------------------------------------------------------------------
# Line of sight
# ---------------------------------------------------------------------------

func test_los_clear() -> void:
	var env := _make_grid_env(10, 10)
	check(env.resolver.has_line_of_sight(Vector2i(0, 0), Vector2i(5, 5)),
		"LOS should be clear on open grid")


func test_los_blocked() -> void:
	var env := _make_grid_env(10, 10)
	env.map.set_cell_field(Vector2i(3, 3), "terrain_feature", "wall_stone")
	env.map.set_cell_field(Vector2i(3, 3), "blocks_los", true)
	check(not env.resolver.has_line_of_sight(Vector2i(0, 0), Vector2i(5, 5)),
		"LOS should be blocked by wall at (3,3)")


# ---------------------------------------------------------------------------
# Charge validation
# ---------------------------------------------------------------------------

func test_charge_valid() -> void:
	var env := _make_grid_env(20, 20)
	env.resolver.set_grid_position(env.pc, Vector2i(0, 0))
	env.resolver.set_grid_position(env.monster, Vector2i(6, 0))
	var result: Dictionary = env.resolver.validate_charge(env.pc, env.monster)
	check(result["valid"] == true,
		"charge should be valid: 6 cells apart, clear path. Reason: %s" % result.get("reason", ""))


func test_charge_too_close() -> void:
	var env := _make_grid_env(10, 10)
	env.resolver.set_grid_position(env.pc, Vector2i(3, 3))
	env.resolver.set_grid_position(env.monster, Vector2i(5, 3))
	var result: Dictionary = env.resolver.validate_charge(env.pc, env.monster)
	check(result["valid"] == false,
		"charge should be invalid when only 2 cells apart")
	check("too close" in result.get("reason", ""),
		"reason should mention too close")


func test_charge_blocked() -> void:
	var env := _make_grid_env(20, 20)
	env.resolver.set_grid_position(env.pc, Vector2i(0, 0))
	env.resolver.set_grid_position(env.monster, Vector2i(8, 0))
	# Block a vertical strip that the charge line cannot route around
	for row in range(-2, 3):
		var wall_pos := Vector2i(4, row)
		if env.map.has_cell(wall_pos):
			env.map.set_cell_field(wall_pos, "terrain_feature", "wall_stone")
			env.map.set_cell_field(wall_pos, "passable", false)
	var result: Dictionary = env.resolver.validate_charge(env.pc, env.monster)
	check(result["valid"] == false,
		"charge should be invalid when path is blocked")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_grid_env(w: int, h: int) -> Dictionary:
	## Create a test environment: open grid, roster with 1 PC and 1 monster, resolver.
	var map := _make_open_map(w, h)
	var roster := CombatRoster.new()
	var pc := _make_pc_combatant("pc_1", 10, 3)
	var monster := _make_monster_combatant("m_1", 8, 3)
	roster.add_combatant(pc)
	roster.add_combatant(monster)
	roster.enemy_count_at_start = 1
	var resolver: MovementResolver = MovementResolver.new(map, roster)
	return {"map": map, "roster": roster, "pc": pc, "monster": monster, "resolver": resolver}


func _make_open_map(w: int, h: int) -> TacticalMapData:
	## Create a fully open TacticalMapData grid.
	var map := TacticalMapData.new()
	map.grid_width = w
	map.grid_height = h
	map.entry_pos = Vector2i(0, 0)
	var cells_array: Array = []
	for col in range(w):
		for row in range(h):
			cells_array.append({
				"col": col, "row": row,
				"terrain_feature": "open",
				"elevation": 0,
			})
	var data := {
		"grid_width": w, "grid_height": h,
		"entry_col": 0, "entry_row": 0,
		"cells": cells_array,
	}
	return TacticalMapData.from_dict(data)


func _make_pc_combatant(id: String, hp: int, ac: int) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.hp_max = hp
	cd.hp_current = hp
	cd.armor_class = ac
	cd.attack_throw = 10
	cd.combat_progression = "fighter"
	cd.level = 3
	cd.strength = 12
	cd.dexterity = 10
	cd.constitution = 10
	cd.intelligence = 10
	cd.wisdom = 10
	cd.charisma = 10
	cd.base_movement = 120
	return Combatant.from_character(cd)


func _make_monster_combatant(id: String, hp: int, ac: int) -> Combatant:
	var data := {
		"name": "Test Monster",
		"hit_dice": {"base": 2, "modifier": 0},
		"armor_class": ac,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "claw", "count": 1, "damage": "1d6", "to_hit_modifier": 0}]}],
		"save_as": {"class": "F", "level": 2},
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"combat_behavior": {},
	}
	return Combatant.from_monster(data, hp, id, "test_group")
