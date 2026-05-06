extends "res://tests/test_suite_base.gd"

## Session P2 — Wall Path-Crossing Damage.
##
## Validates SpellCombatHooks._tick_wall consumer for the four wall spells.
## Each test sets up an active_effect with a wall_profile and a combatant
## whose cells_traversed_this_round (P1) intersects the wall segments, then
## fires on_round_end and checks the damage outcome.

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


class _MockCombatant extends RefCounted:
	var id: String = ""
	var hp_max: int = 6
	var hp_current: int = 6
	var hit_dice: int = 5
	var creature_types: Array = []
	var conditions: Array[String] = []
	var cells_traversed_this_round: Array[Vector3i] = []
	var previous_grid_position: Vector3i = Vector3i(-1, -1, 0)
	var grid_position: Vector3i = Vector3i(0, 0, 0)
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func is_alive() -> bool: return hp_current > 0
	func get_hit_dice() -> int: return hit_dice
	func apply_damage(amt: int, _t: String = "", _src: String = "") -> Dictionary:
		hp_current = max(0, hp_current - amt)
		return {"hp_damage": amt, "new_hp": hp_current, "is_downed": hp_current <= 0}


class _MockRoster extends RefCounted:
	var combatants: Array = []
	func get_alive() -> Array:
		return combatants.filter(func(c): return c.is_alive())
	func get_by_id(id: String):
		for c in combatants:
			if c.id == id: return c
		return null


func run_all_tests() -> void:
	test_wall_of_fire_high_hd_takes_damage()
	test_wall_of_fire_low_hd_no_damage()
	test_wall_of_fire_undead_double_damage()
	test_wall_of_fire_cold_using_double_damage()
	test_wall_of_ice_break_through_damage()
	test_wall_of_ice_fire_using_double_damage()
	test_wall_of_stone_no_damage()
	test_wall_of_iron_no_damage()
	test_multiple_combatants_each_take_damage()
	test_double_cell_cross_double_damage()
	test_no_traversal_no_damage()
	test_pre_existing_cell_one_time_crosser()
	if not has_failures():
		print("SessionP2Walls: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_wall_effect(spell_key: String, segments: Array, extras: Dictionary = {}) -> Dictionary:
	var profile: Dictionary = {
		"wall_id": "wall_test:caster",
		"wall_segments": segments,
		"damage_dice": "1d6",
		"damage_type": "fire" if spell_key == "wall_of_fire" else "cold",
		"min_hd_to_pass": 5,
		"double_damage_creature_types": [],
	}
	profile.merge(extras, true)
	return {
		"effect_id": "fx_%s" % spell_key,
		"spell_key": spell_key,
		"caster_id": "caster",
		"target_ids": [],
		"effect_type": "area",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "turns", "duration_remaining": 2,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"wall_profile": profile},
		"created_at_round": 0,
	}


func _make_hooks_with_wall(effect: Dictionary, dice = null) -> SpellCombatHooks:
	var tracker := ActiveEffectTracker.new()
	tracker.add_effect(effect)
	return SpellCombatHooks.new(tracker, dice)


# ---------------------------------------------------------------------------
# Wall of Fire
# ---------------------------------------------------------------------------

func test_wall_of_fire_high_hd_takes_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 3
	var segments: Array = [Vector3i(5, 5, 0)]
	var effect := _make_wall_effect("wall_of_fire", segments,
		{"min_hd_to_pass": 5, "double_damage_creature_types": ["undead", "cold_using"]})
	var hooks := _make_hooks_with_wall(effect, dice)
	var goblin := _MockCombatant.new()
	goblin.id = "g_fire"; goblin.hp_max = 8; goblin.hp_current = 8; goblin.hit_dice = 5
	goblin.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [goblin]
	hooks.on_round_end(1, roster)
	check(goblin.hp_current == 5,
		"5HD goblin takes 3 fire damage, hp 8 → 5, got %d" % goblin.hp_current)


func test_wall_of_fire_low_hd_no_damage() -> void:
	# <5 HD impenetrable per RAW; movement-block enforcement is deferred but
	# the damage path is gated by min_hd_to_pass so no damage applies.
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 4
	var effect := _make_wall_effect("wall_of_fire", [Vector3i(5, 5, 0)],
		{"min_hd_to_pass": 5, "double_damage_creature_types": []})
	var hooks := _make_hooks_with_wall(effect, dice)
	var goblin := _MockCombatant.new()
	goblin.id = "g_low"; goblin.hp_max = 6; goblin.hp_current = 6; goblin.hit_dice = 3
	goblin.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [goblin]
	hooks.on_round_end(1, roster)
	check(goblin.hp_current == 6,
		"3HD goblin (impenetrable) takes no damage, got hp %d" % goblin.hp_current)


func test_wall_of_fire_undead_double_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 2
	var effect := _make_wall_effect("wall_of_fire", [Vector3i(5, 5, 0)],
		{"min_hd_to_pass": 5, "double_damage_creature_types": ["undead", "cold_using"]})
	var hooks := _make_hooks_with_wall(effect, dice)
	var ghoul := _MockCombatant.new()
	ghoul.id = "g_undead"; ghoul.hp_max = 16; ghoul.hp_current = 16; ghoul.hit_dice = 5
	ghoul.creature_types = ["undead"]
	ghoul.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [ghoul]
	hooks.on_round_end(1, roster)
	check(ghoul.hp_current == 12,
		"undead takes 2*2=4 fire damage, hp 16 → 12, got %d" % ghoul.hp_current)


func test_wall_of_fire_cold_using_double_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 3
	var effect := _make_wall_effect("wall_of_fire", [Vector3i(5, 5, 0)],
		{"min_hd_to_pass": 5, "double_damage_creature_types": ["undead", "cold_using"]})
	var hooks := _make_hooks_with_wall(effect, dice)
	var ice_troll := _MockCombatant.new()
	ice_troll.id = "g_cold"; ice_troll.hp_max = 30; ice_troll.hp_current = 30; ice_troll.hit_dice = 6
	ice_troll.creature_types = ["cold_using"]
	ice_troll.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [ice_troll]
	hooks.on_round_end(1, roster)
	check(ice_troll.hp_current == 24,
		"cold-using crosser takes 2*3=6 fire damage, hp 30 → 24, got %d" %
			ice_troll.hp_current)


# ---------------------------------------------------------------------------
# Wall of Ice
# ---------------------------------------------------------------------------

func test_wall_of_ice_break_through_damage() -> void:
	# Wall of Ice's damage_trigger=break_through; for P2 we treat any cell-cross
	# as a break attempt.
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 4
	var profile_extra: Dictionary = {
		"min_hd_to_break": 5, "min_hd_to_pass": 5,
		"damage_trigger": "break_through",
		"double_damage_creature_types": ["fire_using", "hot_accustomed"],
	}
	var effect := _make_wall_effect("wall_of_ice", [Vector3i(5, 5, 0)], profile_extra)
	var hooks := _make_hooks_with_wall(effect, dice)
	var ogre := _MockCombatant.new()
	ogre.id = "g_ogre"; ogre.hp_max = 25; ogre.hp_current = 25; ogre.hit_dice = 5
	ogre.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [ogre]
	hooks.on_round_end(1, roster)
	check(ogre.hp_current == 21,
		"ogre breaks through wall of ice for 4 cold, hp 25 → 21, got %d" % ogre.hp_current)


func test_wall_of_ice_fire_using_double_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 2
	var profile_extra: Dictionary = {
		"min_hd_to_pass": 5,
		"double_damage_creature_types": ["fire_using"],
	}
	var effect := _make_wall_effect("wall_of_ice", [Vector3i(5, 5, 0)], profile_extra)
	var hooks := _make_hooks_with_wall(effect, dice)
	var efreet := _MockCombatant.new()
	efreet.id = "g_efreet"; efreet.hp_max = 30; efreet.hp_current = 30; efreet.hit_dice = 8
	efreet.creature_types = ["fire_using"]
	efreet.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [efreet]
	hooks.on_round_end(1, roster)
	check(efreet.hp_current == 26,
		"fire-using crosser takes 2*2=4 cold, hp 30 → 26, got %d" % efreet.hp_current)


# ---------------------------------------------------------------------------
# Walls of stone / iron — no per-round damage
# ---------------------------------------------------------------------------

func test_wall_of_stone_no_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 6
	var effect := _make_wall_effect("wall_of_stone", [Vector3i(5, 5, 0)])
	var hooks := _make_hooks_with_wall(effect, dice)
	var c := _MockCombatant.new()
	c.id = "g_stone"; c.hp_max = 10; c.hp_current = 10; c.hit_dice = 5
	c.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [c]
	hooks.on_round_end(1, roster)
	check(c.hp_current == 10, "wall of stone deals no per-round damage")


func test_wall_of_iron_no_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 6
	var effect := _make_wall_effect("wall_of_iron", [Vector3i(5, 5, 0)])
	var hooks := _make_hooks_with_wall(effect, dice)
	var c := _MockCombatant.new()
	c.id = "g_iron"; c.hp_max = 10; c.hp_current = 10; c.hit_dice = 5
	c.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [c]
	hooks.on_round_end(1, roster)
	check(c.hp_current == 10, "wall of iron deals no per-round damage")


# ---------------------------------------------------------------------------
# Multi-combatant + repeated cell-cross
# ---------------------------------------------------------------------------

func test_multiple_combatants_each_take_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 3
	var effect := _make_wall_effect("wall_of_fire", [Vector3i(5, 5, 0)],
		{"min_hd_to_pass": 5, "double_damage_creature_types": []})
	var hooks := _make_hooks_with_wall(effect, dice)
	var a := _MockCombatant.new()
	a.id = "a"; a.hp_max = 10; a.hp_current = 10; a.hit_dice = 5
	a.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var b := _MockCombatant.new()
	b.id = "b"; b.hp_max = 10; b.hp_current = 10; b.hit_dice = 5
	b.cells_traversed_this_round = [Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [a, b]
	hooks.on_round_end(1, roster)
	check(a.hp_current == 7, "a takes 3 damage")
	check(b.hp_current == 7, "b takes 3 damage independently")


func test_double_cell_cross_double_damage() -> void:
	# A combatant whose traversal log enters a wall segment twice in one round
	# takes the per-cell damage twice.
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 2
	var effect := _make_wall_effect("wall_of_fire", [Vector3i(5, 5, 0)],
		{"min_hd_to_pass": 5, "double_damage_creature_types": []})
	var hooks := _make_hooks_with_wall(effect, dice)
	var c := _MockCombatant.new()
	c.id = "c"; c.hp_max = 10; c.hp_current = 10; c.hit_dice = 5
	# Walked in then back across the same segment.
	c.cells_traversed_this_round = [Vector3i(5, 5, 0), Vector3i(6, 5, 0), Vector3i(5, 5, 0)]
	var roster := _MockRoster.new()
	roster.combatants = [c]
	hooks.on_round_end(1, roster)
	check(c.hp_current == 6,
		"two cell-crosses → 2*2=4 damage, hp 10 → 6, got %d" % c.hp_current)


func test_no_traversal_no_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 5
	var effect := _make_wall_effect("wall_of_fire", [Vector3i(5, 5, 0)],
		{"min_hd_to_pass": 5, "double_damage_creature_types": []})
	var hooks := _make_hooks_with_wall(effect, dice)
	var c := _MockCombatant.new()
	c.id = "c_far"; c.hp_max = 10; c.hp_current = 10; c.hit_dice = 5
	c.cells_traversed_this_round = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]
	c.previous_grid_position = Vector3i(0, 0, 0)
	var roster := _MockRoster.new()
	roster.combatants = [c]
	hooks.on_round_end(1, roster)
	check(c.hp_current == 10,
		"no segment intersection → no damage, got %d" % c.hp_current)


func test_pre_existing_cell_one_time_crosser() -> void:
	# Defense in depth: a combatant standing inside a wall segment at round
	# start with no traversal log gets one-time crosser treatment.
	var dice := _FakeDice.new()
	dice.fixed["wall_crossing_damage"] = 4
	var effect := _make_wall_effect("wall_of_fire", [Vector3i(5, 5, 0)],
		{"min_hd_to_pass": 5, "double_damage_creature_types": []})
	var hooks := _make_hooks_with_wall(effect, dice)
	var c := _MockCombatant.new()
	c.id = "c_inside"; c.hp_max = 10; c.hp_current = 10; c.hit_dice = 5
	c.previous_grid_position = Vector3i(5, 5, 0)
	# No cells_traversed_this_round; no movement this round.
	var roster := _MockRoster.new()
	roster.combatants = [c]
	hooks.on_round_end(1, roster)
	check(c.hp_current == 6,
		"pre-existing-in-segment combatant takes one-time damage, got %d" % c.hp_current)
