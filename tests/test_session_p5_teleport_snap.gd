extends "res://tests/test_suite_base.gd"

## Session P5 — Teleport Runtime Snap-to-Destination.
##
## Validates TeleportRuntimeConsumer: snaps Dimension Door / Teleport
## targets, validates destinations, and applies solid-matter / falling /
## lost outcomes per ACKS RAW. Tests exercise process_target() directly
## with synthetic per_target outcome dicts (matching the shape produced by
## CastingResolver._teleport / teleport_resolver.gd) plus one full signal
## round-trip test through EventBus.teleport_resolved.


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_expression(e: String, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, fixed.get(e, 0)))
		r.raw_total = r.modified_total
		return r
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


# Captures combatant_lost / combatant_downed / combatant_moved emissions
# during a single test. Detached at end of each test.
class _SignalListener extends RefCounted:
	var lost_ids: Array = []
	var downed: Array = []  # [{id, attacker}]
	var moved: Array = []   # [{id, from, to, path}]
	func on_lost(cid: String) -> void:
		lost_ids.append(cid)
	func on_downed(cid: String, attacker: String) -> void:
		downed.append({"id": cid, "attacker": attacker})
	func on_moved(cid: String, f: Vector3i, t: Vector3i, path: Array) -> void:
		moved.append({"id": cid, "from": f, "to": t, "path": path.duplicate()})


func run_all_tests() -> void:
	test_dimension_door_precise_snaps_to_destination()
	test_dimension_door_into_solid_no_movement()
	test_dimension_door_save_skips_movement()
	test_teleport_on_target_snaps()
	test_teleport_off_target_into_solid_instant_kills()
	test_teleport_lost_emits_signal_and_marks_is_lost()
	test_teleport_off_target_above_ground_falling_damage()
	test_combatant_moved_signal_fires_from_teleport_snap()
	test_multiple_targets_each_snap_independently()
	test_signal_round_trip_through_event_bus()
	if not has_failures():
		print("SessionP5TeleportSnap: all tests passed.")


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
	var c := Combatant.from_monster(monster_data, 8, id, "test")
	c.grid_position = pos
	return c


func _make_environment(width: int = 12, height: int = 12) -> Dictionary:
	var roster := CombatRoster.new()
	var voxel_map: VoxelMapData = VoxelMapData.generate_open_field(width, height)
	var movement_resolver := MovementResolver.new(roster)
	movement_resolver.set_voxel_map(voxel_map)
	var dice := _FakeDice.new()
	var consumer := TeleportRuntimeConsumer.new(roster, movement_resolver, voxel_map, dice)
	return {
		"roster": roster, "voxel_map": voxel_map,
		"movement_resolver": movement_resolver, "dice": dice,
		"consumer": consumer,
	}


func _make_solid_cell_at(voxel_map: VoxelMapData, pos: Vector3i) -> void:
	var cell := VoxelCell.new()
	cell.col = pos.x; cell.row = pos.y; cell.level = pos.z
	cell.solidity = "solid"; cell.feature = "wall"; cell.floor_type = "stone"
	voxel_map.set_cell(pos, cell)


func _make_air_pocket_at(voxel_map: VoxelMapData, pos: Vector3i) -> void:
	# Passable air cell with no floor / no solid below — combatant placed
	# here would fall.
	var cell := VoxelCell.new()
	cell.col = pos.x; cell.row = pos.y; cell.level = pos.z
	cell.solidity = "air"; cell.feature = "open"; cell.floor_type = "none"
	voxel_map.set_cell(pos, cell)


# ---------------------------------------------------------------------------
# Dimension Door (precise; fail_on_solid_object=true)
# ---------------------------------------------------------------------------

func test_dimension_door_precise_snaps_to_destination() -> void:
	var env := _make_environment()
	var c := _make_combatant("dd_target", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	var entry: Dictionary = {
		"applied": true, "saved": false,
		"destination_cell": Vector3i(8, 5, 0),
		"fail_on_solid_object": true,
		"error_profile": "precise",
	}
	var result: Dictionary = env.consumer.process_target("dimension_door", "dd_target", entry)
	check(result.action == "snapped",
		"dimension door precise snaps target, got '%s'" % result.action)
	check(c.grid_position == Vector3i(8, 5, 0),
		"target at destination, got %s" % str(c.grid_position))


func test_dimension_door_into_solid_no_movement() -> void:
	# RAW: "If the destination lies within a solid object, the spell fails
	# automatically." No instant-kill — Dimension Door fails safely.
	var env := _make_environment()
	_make_solid_cell_at(env.voxel_map, Vector3i(8, 5, 0))
	var c := _make_combatant("dd_solid", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	var entry: Dictionary = {
		"applied": true, "saved": false,
		"destination_cell": Vector3i(8, 5, 0),
		"fail_on_solid_object": true,
	}
	var result: Dictionary = env.consumer.process_target("dimension_door", "dd_solid", entry)
	check(result.action == "noop", "dimension door into solid is no-op (spell fails)")
	check(result.get("reason", "") == "solid_matter_fail",
		"failure reason recorded as solid_matter_fail")
	check(c.grid_position == Vector3i(2, 2, 0),
		"target unmoved on solid-matter fail, got %s" % str(c.grid_position))


func test_dimension_door_save_skips_movement() -> void:
	# Unwilling target makes save vs Spells; resolver recorded saved=true.
	var env := _make_environment()
	var c := _make_combatant("dd_saver", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	var entry: Dictionary = {
		"applied": false, "saved": true, "reason": "saved",
		"destination_cell": Vector3i(8, 5, 0),
	}
	var result: Dictionary = env.consumer.process_target("dimension_door", "dd_saver", entry)
	check(result.action == "saved", "saved target → no movement")
	check(c.grid_position == Vector3i(2, 2, 0),
		"saved target stayed at origin, got %s" % str(c.grid_position))


# ---------------------------------------------------------------------------
# Teleport (long-range)
# ---------------------------------------------------------------------------

func test_teleport_on_target_snaps() -> void:
	var env := _make_environment()
	var c := _make_combatant("tp_on", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	var entry: Dictionary = {
		"applied": true, "outcome_kind": "on_target",
		"destination_cell": Vector3i(9, 9, 0),
		"familiarity": "very_familiar",
	}
	var result: Dictionary = env.consumer.process_target("teleport", "tp_on", entry)
	check(result.action == "snapped", "teleport on_target snaps")
	check(c.grid_position == Vector3i(9, 9, 0),
		"on_target lands at destination, got %s" % str(c.grid_position))


func test_teleport_off_target_into_solid_instant_kills() -> void:
	# RAW: off-target into solid matter → instantly killed.
	var env := _make_environment()
	_make_solid_cell_at(env.voxel_map, Vector3i(7, 7, 0))
	var c := _make_combatant("tp_solid", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	var listener := _SignalListener.new()
	EventBus.combatant_downed.connect(listener.on_downed)
	var entry: Dictionary = {
		"applied": true, "outcome_kind": "off_target",
		"destination_cell": Vector3i(7, 7, 0),
	}
	var result: Dictionary = env.consumer.process_target("teleport", "tp_solid", entry)
	check(result.action == "instant_kill",
		"teleport into solid matter → instant kill, got '%s'" % result.action)
	check(c.get_hp_current() == 0, "target hp dropped to 0")
	check(listener.downed.size() == 1, "combatant_downed fired once")
	if EventBus.combatant_downed.is_connected(listener.on_downed):
		EventBus.combatant_downed.disconnect(listener.on_downed)


func test_teleport_lost_emits_signal_and_marks_is_lost() -> void:
	var env := _make_environment()
	var c := _make_combatant("tp_lost", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	var listener := _SignalListener.new()
	EventBus.combatant_lost.connect(listener.on_lost)
	var entry: Dictionary = {
		"applied": false, "outcome_kind": "lost",
		"destination_cell": Vector3i(9, 9, 0),
	}
	var result: Dictionary = env.consumer.process_target("teleport", "tp_lost", entry)
	check(result.action == "lost", "teleport lost → action='lost'")
	check(c.is_lost == true, "target.is_lost set true")
	check(not c.is_alive(), "lost combatant is no longer alive (off the alive-list)")
	check(listener.lost_ids == ["tp_lost"],
		"combatant_lost fired with target id, got %s" % str(listener.lost_ids))
	if EventBus.combatant_lost.is_connected(listener.on_lost):
		EventBus.combatant_lost.disconnect(listener.on_lost)


func test_teleport_off_target_above_ground_falling_damage() -> void:
	var env := _make_environment()
	# Carve out an air pocket at (5, 5, 3) with no floor + nothing solid below.
	# Resolve_fall scans down from there and lands at level -20 (MIN_LEVEL)
	# because no support exists — that's a 23-level fall = 115 ft = 11d6.
	_make_air_pocket_at(env.voxel_map, Vector3i(5, 5, 3))
	var c := _make_combatant("tp_fall", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	env.dice.fixed["fall_damage"] = 25
	var entry: Dictionary = {
		"applied": true, "outcome_kind": "off_target",
		"destination_cell": Vector3i(5, 5, 3),
	}
	var result: Dictionary = env.consumer.process_target("teleport", "tp_fall", entry)
	check(result.action == "snapped",
		"snap occurred even with falling, got '%s'" % result.action)
	check(int(result.get("fall_damage", 0)) == 25,
		"falling damage dice rolled for 25, got %d" % int(result.get("fall_damage", 0)))
	check(c.get_hp_current() == 0,
		"falling damage applied (8 - 25 clamped to 0), got %d" % c.get_hp_current())


# ---------------------------------------------------------------------------
# Cross-cutting
# ---------------------------------------------------------------------------

func test_combatant_moved_signal_fires_from_teleport_snap() -> void:
	# P1 hookup: set_grid_position_3d emits combatant_moved on actual moves.
	var env := _make_environment()
	var c := _make_combatant("tp_move_signal", Vector3i(1, 1, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(1, 1, 0))
	var listener := _SignalListener.new()
	EventBus.combatant_moved.connect(listener.on_moved)
	var entry: Dictionary = {
		"applied": true, "outcome_kind": "on_target",
		"destination_cell": Vector3i(9, 1, 0),
	}
	env.consumer.process_target("teleport", "tp_move_signal", entry)
	# At least one combatant_moved entry with from=(1,1,0) to=(9,1,0).
	var found_snap := false
	for ev in listener.moved:
		if ev["id"] == "tp_move_signal" and ev["to"] == Vector3i(9, 1, 0):
			found_snap = true
			break
	check(found_snap,
		"combatant_moved emitted from teleport snap (P1 hookup), got %d events" %
		listener.moved.size())
	if EventBus.combatant_moved.is_connected(listener.on_moved):
		EventBus.combatant_moved.disconnect(listener.on_moved)


func test_multiple_targets_each_snap_independently() -> void:
	var env := _make_environment(20, 20)
	var a := _make_combatant("multi_a", Vector3i(2, 2, 0))
	var b := _make_combatant("multi_b", Vector3i(3, 2, 0))
	env.roster.add_combatant(a)
	env.roster.add_combatant(b)
	env.movement_resolver.set_grid_position_3d(a, Vector3i(2, 2, 0))
	env.movement_resolver.set_grid_position_3d(b, Vector3i(3, 2, 0))
	var per_target: Dictionary = {
		"multi_a": {"applied": true, "outcome_kind": "on_target", "destination_cell": Vector3i(15, 15, 0)},
		"multi_b": {"applied": true, "outcome_kind": "on_target", "destination_cell": Vector3i(16, 15, 0)},
	}
	env.consumer._on_teleport_resolved("caster_x", "teleport", per_target)
	check(a.grid_position == Vector3i(15, 15, 0), "a snapped to (15,15,0)")
	check(b.grid_position == Vector3i(16, 15, 0), "b snapped to (16,15,0)")


func test_signal_round_trip_through_event_bus() -> void:
	# One end-to-end test: emit teleport_resolved, ensure consumer reacts.
	var env := _make_environment()
	env.consumer.connect_signals()
	var c := _make_combatant("rt_target", Vector3i(2, 2, 0))
	env.roster.add_combatant(c)
	env.movement_resolver.set_grid_position_3d(c, Vector3i(2, 2, 0))
	EventBus.teleport_resolved.emit("caster_rt", "dimension_door", {
		"rt_target": {
			"applied": true, "saved": false,
			"destination_cell": Vector3i(7, 7, 0),
			"fail_on_solid_object": true,
		},
	})
	check(c.grid_position == Vector3i(7, 7, 0),
		"signal-driven snap landed at (7,7,0), got %s" % str(c.grid_position))
	env.consumer.disconnect_signals()
