extends "res://tests/test_suite_base.gd"

## Session P1 — Movement Infrastructure Foundation.
##
## Foundation for P2 + P4 + P5. Validates:
##   - Combatant.previous_grid_position + cells_traversed_this_round fields
##   - SpellCombatHooks.on_round_start snapshots positions + clears traversal log
##   - MovementResolver.move_along_path appends entered cells in walk order
##   - MovementResolver.move_along_path emits combatant_moved at end of move
##   - MovementResolver.set_grid_position_3d emits combatant_moved on teleport
##   - No signal emitted on a 0-cell move (no actual position change)


# Lightweight signal capture: connects to EventBus.combatant_moved before each
# test, accumulates emissions, and exposes them for inspection.
class _Listener extends RefCounted:
	var events: Array = []
	func clear() -> void:
		events = []
	func on_combatant_moved(cid: String, from_cell: Vector3i, to_cell: Vector3i, path_cells: Array) -> void:
		events.append({
			"combatant_id": cid, "from": from_cell, "to": to_cell,
			"path": path_cells.duplicate(),
		})


func run_all_tests() -> void:
	test_round_start_snapshots_positions()
	test_round_start_clears_traversal_log()
	test_move_along_path_appends_cells_in_order()
	test_move_along_path_emits_signal_once()
	test_set_grid_position_3d_emits_teleport_signal()
	test_set_grid_position_3d_no_emit_on_noop()
	test_multiple_moves_accumulate_cells()
	test_previous_position_persists_across_movement()
	if not has_failures():
		print("SessionP1Movement: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_combatant(id: String, pos: Vector3i) -> Combatant:
	var monster_data := {
		"name": "Goblin",
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 0,
		"attack_routines": [{"routine_name": "melee", "usage": "default",
			"attacks": [{"attack_type": "natural", "count": 1, "damage": "1d4", "to_hit_modifier": 0, "special_effect": null}]}],
		"save_as": {"class": "F", "level": 1},
		"morale": 0, "xp": 5,
		"movement": {"land": {"exploration": 60, "combat": 20}},
		"morale_modifiers": [], "special_abilities": [],
		"immunities": [], "resistances": [], "vulnerabilities": [],
		"combat_behavior": {},
	}
	var c := Combatant.from_monster(monster_data, 6, id, "test")
	c.grid_position = pos
	return c


func _make_voxel_map_open(w: int = 10, h: int = 10) -> VoxelMapData:
	return VoxelMapData.generate_open_field(w, h)


func _attach_listener() -> _Listener:
	var listener := _Listener.new()
	EventBus.combatant_moved.connect(listener.on_combatant_moved)
	return listener


func _detach_listener(listener: _Listener) -> void:
	if EventBus.combatant_moved.is_connected(listener.on_combatant_moved):
		EventBus.combatant_moved.disconnect(listener.on_combatant_moved)


# ---------------------------------------------------------------------------
# on_round_start — snapshot + clear
# ---------------------------------------------------------------------------

func test_round_start_snapshots_positions() -> void:
	var roster := CombatRoster.new()
	var c1 := _make_combatant("g1", Vector3i(2, 3, 0))
	var c2 := _make_combatant("g2", Vector3i(7, 1, 0))
	roster.add_combatant(c1)
	roster.add_combatant(c2)
	var hooks := SpellCombatHooks.new(null, null)
	hooks.on_round_start(1, roster)
	check(c1.previous_grid_position == Vector3i(2, 3, 0),
		"g1 previous_grid_position snapshotted at round start, got %s" % str(c1.previous_grid_position))
	check(c2.previous_grid_position == Vector3i(7, 1, 0),
		"g2 previous_grid_position snapshotted at round start")


func test_round_start_clears_traversal_log() -> void:
	var roster := CombatRoster.new()
	var c := _make_combatant("g_clear", Vector3i(0, 0, 0))
	c.cells_traversed_this_round = [Vector3i(1, 0, 0), Vector3i(2, 0, 0)]
	roster.add_combatant(c)
	var hooks := SpellCombatHooks.new(null, null)
	hooks.on_round_start(2, roster)
	check(c.cells_traversed_this_round.is_empty(),
		"traversal log cleared at round start, got %d cells" % c.cells_traversed_this_round.size())


# ---------------------------------------------------------------------------
# move_along_path — cells appended + signal
# ---------------------------------------------------------------------------

func test_move_along_path_appends_cells_in_order() -> void:
	var roster := CombatRoster.new()
	var voxel_map := _make_voxel_map_open()
	var c := _make_combatant("g_walk", Vector3i(0, 0, 0))
	roster.add_combatant(c)
	voxel_map.set_entity_pos(c.id, Vector3i(0, 0, 0))
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	# Walk three cells east.
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var moved: int = mr.move_along_path(c, path, 3)
	check(moved == 3, "moved 3 cells, got %d" % moved)
	check(c.cells_traversed_this_round.size() == 3,
		"cells_traversed_this_round has 3 entries, got %d" % c.cells_traversed_this_round.size())
	check(c.cells_traversed_this_round[0] == Vector3i(1, 0, 0),
		"first traversed cell is (1,0,0)")
	check(c.cells_traversed_this_round[2] == Vector3i(3, 0, 0),
		"last traversed cell is (3,0,0)")


func test_move_along_path_emits_signal_once() -> void:
	var roster := CombatRoster.new()
	var voxel_map := _make_voxel_map_open()
	var c := _make_combatant("g_sig", Vector3i(0, 0, 0))
	roster.add_combatant(c)
	voxel_map.set_entity_pos(c.id, Vector3i(0, 0, 0))
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	var listener := _attach_listener()
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	mr.move_along_path(c, path, 2)
	# Drain — signals are emitted synchronously.
	check(listener.events.size() == 1,
		"combatant_moved fired exactly once, got %d" % listener.events.size())
	if listener.events.size() == 1:
		var ev: Dictionary = listener.events[0]
		check(ev["combatant_id"] == "g_sig", "combatant_id matches")
		check(ev["from"] == Vector3i(0, 0, 0),
			"from_cell is start, got %s" % str(ev["from"]))
		check(ev["to"] == Vector3i(2, 0, 0),
			"to_cell is final position, got %s" % str(ev["to"]))
		check(ev["path"].size() == 3,
			"path_cells has 3 entries (start + 2 walked), got %d" % ev["path"].size())
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# set_grid_position_3d — teleport signal
# ---------------------------------------------------------------------------

func test_set_grid_position_3d_emits_teleport_signal() -> void:
	var roster := CombatRoster.new()
	var voxel_map := _make_voxel_map_open()
	var c := _make_combatant("g_tp", Vector3i(0, 0, 0))
	roster.add_combatant(c)
	voxel_map.set_entity_pos(c.id, Vector3i(0, 0, 0))
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	var listener := _attach_listener()
	mr.set_grid_position_3d(c, Vector3i(5, 5, 0))
	check(listener.events.size() == 1,
		"teleport fired one combatant_moved, got %d" % listener.events.size())
	if listener.events.size() == 1:
		var ev: Dictionary = listener.events[0]
		check(ev["from"] == Vector3i(0, 0, 0), "teleport from is origin")
		check(ev["to"] == Vector3i(5, 5, 0), "teleport to is destination")
		check(ev["path"].size() == 1 and ev["path"][0] == Vector3i(5, 5, 0),
			"teleport path is [destination]")
	_detach_listener(listener)


func test_set_grid_position_3d_no_emit_on_noop() -> void:
	var roster := CombatRoster.new()
	var voxel_map := _make_voxel_map_open()
	var c := _make_combatant("g_noop", Vector3i(3, 3, 0))
	roster.add_combatant(c)
	voxel_map.set_entity_pos(c.id, Vector3i(3, 3, 0))
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	var listener := _attach_listener()
	# Set to current position — should be a no-op.
	mr.set_grid_position_3d(c, Vector3i(3, 3, 0))
	check(listener.events.size() == 0,
		"no signal on no-op set_grid_position_3d, got %d" % listener.events.size())
	_detach_listener(listener)


# ---------------------------------------------------------------------------
# Multi-move + previous-position persistence
# ---------------------------------------------------------------------------

func test_multiple_moves_accumulate_cells() -> void:
	var roster := CombatRoster.new()
	var voxel_map := _make_voxel_map_open()
	var c := _make_combatant("g_multi", Vector3i(0, 0, 0))
	roster.add_combatant(c)
	voxel_map.set_entity_pos(c.id, Vector3i(0, 0, 0))
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	# First move.
	mr.move_along_path(c, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], 1)
	# Second move (later in the same round).
	mr.move_along_path(c, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i], 2)
	check(c.cells_traversed_this_round.size() == 3,
		"3 cells accumulated across two moves, got %d" % c.cells_traversed_this_round.size())


func test_previous_position_persists_across_movement() -> void:
	var roster := CombatRoster.new()
	var voxel_map := _make_voxel_map_open()
	var c := _make_combatant("g_prev", Vector3i(2, 2, 0))
	roster.add_combatant(c)
	voxel_map.set_entity_pos(c.id, Vector3i(2, 2, 0))
	var hooks := SpellCombatHooks.new(null, null)
	hooks.on_round_start(1, roster)
	var mr := MovementResolver.new(roster)
	mr.set_voxel_map(voxel_map)
	mr.move_along_path(c, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)] as Array[Vector2i], 2)
	check(c.previous_grid_position == Vector3i(2, 2, 0),
		"previous_grid_position still at start-of-round (2,2,0), got %s" %
			str(c.previous_grid_position))
	check(c.grid_position == Vector3i(4, 2, 0),
		"current grid_position at (4,2,0)")
