extends "res://tests/test_suite_base.gd"

## Session P4 — Cloudkill Drift + Insect Plague Round-Tick.
##
## Builds on P1 (combatant grid_position read for cloud-inclusion + plague
## swarm cells) and P3 (Insect Plague swarms now sit on the roster). Tests:
##   - Cloud advances 4 cells/round in the away-from-caster direction
##   - area_cells recompute covers the 30-ft-diameter sphere
##   - Combatants entering / leaving drifted cells take / stop taking damage
##   - Plague swarm attacks creatures in its swarm_cell
##   - <3 HD creature in swarm auto-flees (frightened, no save)
##   - ≥3 HD creature gets normal attack roll
##   - Caster damage flips control_state to stationary
##   - Stationary state persists once flipped
##   - Multiple swarms attack independently


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
	var hit_dice: int = 2
	var conditions: Array[String] = []
	var grid_position: Vector3i = Vector3i.ZERO
	var damaged_since_declaration: bool = false
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func is_alive() -> bool: return hp_current > 0
	func get_hit_dice() -> int: return hit_dice
	func get_effective_ac() -> int: return 0
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
	test_cloudkill_drifts_away_from_caster()
	test_cloudkill_area_cells_30ft_sphere()
	test_combatant_entering_drifted_cell_takes_damage()
	test_combatant_outside_drifted_cells_no_damage()
	test_insect_plague_attacks_creature_in_swarm_cell()
	test_insect_plague_low_hd_auto_drive_off()
	test_insect_plague_high_hd_normal_attack_roll()
	test_insect_plague_caster_damage_flips_to_stationary()
	test_insect_plague_stationary_persists_once_flipped()
	test_insect_plague_multiple_swarms_attack_independently()
	if not has_failures():
		print("SessionP4CloudsSwarms: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_caster(id: String, cell: Vector3i) -> _MockCombatant:
	var c := _MockCombatant.new()
	c.id = id; c.hp_max = 20; c.hp_current = 20; c.hit_dice = 9
	c.grid_position = cell
	return c


func _make_cloud_effect(caster_id: String, origin: Vector3i) -> Dictionary:
	var cloud_profile: Dictionary = {
		"cloud_id": "cloudkill:%s" % caster_id,
		"caster_id": caster_id,
		"caster_level": 9,
		"diameter_feet": 30,
		"origin_cell": origin,
		"drift_direction": "away_from_caster",
		"drift_feet_per_round": 20,
		"damage_per_round": 1,
		"damage_type": "poison",
		"hd_threshold_for_death_save": 5,
	}
	return {
		"effect_id": "fx_cloud", "spell_key": "cloudkill",
		"caster_id": caster_id, "target_ids": [], "effect_type": "area",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "turns", "duration_remaining": 6,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"cloud_profile": cloud_profile},
		"created_at_round": 0,
	}


func _make_plague_effect(caster_id: String, swarm_cells: Array) -> Dictionary:
	var swarms: Array = []
	for i in range(swarm_cells.size()):
		swarms.append({
			"swarm_id": "swarm_%s_%d" % [caster_id, i],
			"swarm_index": i,
			"swarm_cell": swarm_cells[i],
			"swarm_hd": 4,
			"area_feet": 30,
		})
	var profile: Dictionary = {
		"plague_id": "insect_plague:%s" % caster_id,
		"caster_id": caster_id, "caster_level": 9,
		"swarms": swarms,
		"control_state": "controlled",
		"auto_drive_off_hd_threshold": 3,
		"swarm_attack_throw": 7,
		"attack_damage_dice": "1d4",
	}
	return {
		"effect_id": "fx_plague", "spell_key": "insect_plague",
		"caster_id": caster_id, "target_ids": [], "effect_type": "area",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "days", "duration_remaining": 1,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"plague_profile": profile},
		"created_at_round": 0,
	}


# ---------------------------------------------------------------------------
# Cloudkill drift
# ---------------------------------------------------------------------------

func test_cloudkill_drifts_away_from_caster() -> void:
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 5, 0))
	# Origin one cell east of caster — cloud should drift further east.
	var effect := _make_cloud_effect("caster_p4", Vector3i(1, 5, 0))
	tracker.add_effect(effect)
	var roster := _MockRoster.new()
	roster.combatants = [caster]
	hooks.on_round_end(1, roster)
	var stored: Dictionary = tracker.get_effect("fx_cloud")
	var cp: Dictionary = stored.get("metadata", {}).get("cloud_profile", {})
	check(cp.get("current_centroid_cell") == Vector3i(5, 5, 0),
		"cloud advances 4 cells east per round (1 + 4 = 5), got %s" %
			str(cp.get("current_centroid_cell")))


func test_cloudkill_area_cells_30ft_sphere() -> void:
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	var effect := _make_cloud_effect("caster_p4", Vector3i(1, 0, 0))
	tracker.add_effect(effect)
	var roster := _MockRoster.new()
	roster.combatants = [caster]
	hooks.on_round_end(1, roster)
	var stored: Dictionary = tracker.get_effect("fx_cloud")
	var cp: Dictionary = stored.get("metadata", {}).get("cloud_profile", {})
	var area: Array = cp.get("area_cells", [])
	# 30 ft diameter / 5 ft cell / 2 = 3-cell radius — 7×7×7 = 343 cells.
	check(area.size() == 343,
		"area_cells covers 30ft sphere (7^3 cells), got %d" % area.size())
	# Centroid (5, 0, 0) should be in area.
	check(Vector3i(5, 0, 0) in area, "centroid in area_cells")
	check(Vector3i(2, 0, 0) in area, "western edge of sphere in area")
	check(Vector3i(8, 0, 0) in area, "eastern edge of sphere in area")


func test_combatant_entering_drifted_cell_takes_damage() -> void:
	var dice := _FakeDice.new()
	dice.fixed["spell_save_cloudkill"] = 20  # auto-pass save
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	var effect := _make_cloud_effect("caster_p4", Vector3i(1, 0, 0))
	tracker.add_effect(effect)
	# Victim sits at (5, 0, 0) — the new centroid after one drift step.
	var ogre := _MockCombatant.new()
	ogre.id = "ogre_drift"; ogre.hp_max = 20; ogre.hp_current = 20; ogre.hit_dice = 6
	ogre.grid_position = Vector3i(5, 0, 0)
	var roster := _MockRoster.new()
	roster.combatants = [caster, ogre]
	hooks.on_round_end(1, roster)
	check(ogre.hp_current == 19,
		"ogre in drifted cloud takes 1 poison, hp 20 → 19, got %d" % ogre.hp_current)


func test_combatant_outside_drifted_cells_no_damage() -> void:
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	var effect := _make_cloud_effect("caster_p4", Vector3i(1, 0, 0))
	tracker.add_effect(effect)
	# Far victim: way outside the 3-cell-radius sphere around (5,0,0).
	var bystander := _MockCombatant.new()
	bystander.id = "bystander"; bystander.hp_max = 20; bystander.hp_current = 20
	bystander.hit_dice = 6
	bystander.grid_position = Vector3i(20, 20, 0)
	var roster := _MockRoster.new()
	roster.combatants = [caster, bystander]
	hooks.on_round_end(1, roster)
	check(bystander.hp_current == 20,
		"bystander outside cloud takes no damage, got %d" % bystander.hp_current)


# ---------------------------------------------------------------------------
# Insect Plague
# ---------------------------------------------------------------------------

func test_insect_plague_attacks_creature_in_swarm_cell() -> void:
	var dice := _FakeDice.new()
	dice.fixed["insect_plague_attack"] = 20  # auto-hit
	dice.fixed["insect_plague_damage"] = 3
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	var effect := _make_plague_effect("caster_p4", [Vector3i(10, 10, 0)])
	tracker.add_effect(effect)
	var ogre := _MockCombatant.new()
	ogre.id = "ogre_swarm"; ogre.hp_max = 20; ogre.hp_current = 20; ogre.hit_dice = 5
	ogre.grid_position = Vector3i(10, 10, 0)
	var roster := _MockRoster.new()
	roster.combatants = [caster, ogre]
	hooks.on_round_end(1, roster)
	check(ogre.hp_current == 17,
		"ogre in swarm cell takes 3 swarm damage, hp 20 → 17, got %d" %
			ogre.hp_current)


func test_insect_plague_low_hd_auto_drive_off() -> void:
	var dice := _FakeDice.new()
	dice.fixed["insect_plague_attack"] = 20
	dice.fixed["insect_plague_damage"] = 4
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	var effect := _make_plague_effect("caster_p4", [Vector3i(10, 10, 0)])
	tracker.add_effect(effect)
	var goblin := _MockCombatant.new()
	goblin.id = "goblin_drive"; goblin.hp_max = 6; goblin.hp_current = 6; goblin.hit_dice = 1
	goblin.grid_position = Vector3i(10, 10, 0)
	var roster := _MockRoster.new()
	roster.combatants = [caster, goblin]
	hooks.on_round_end(1, roster)
	check(goblin.has_condition("frightened"),
		"<3 HD goblin in swarm cell is auto-driven-off (frightened)")
	check(goblin.hp_current == 6,
		"<3 HD auto-drive-off skips the attack roll (no damage), got %d" %
			goblin.hp_current)


func test_insect_plague_high_hd_normal_attack_roll() -> void:
	var dice := _FakeDice.new()
	# Deliberately miss — d20 of 3, +0 mods, target throw 7 → fails.
	dice.fixed["insect_plague_attack"] = 3
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	var effect := _make_plague_effect("caster_p4", [Vector3i(10, 10, 0)])
	tracker.add_effect(effect)
	var ogre := _MockCombatant.new()
	ogre.id = "ogre_miss"; ogre.hp_max = 20; ogre.hp_current = 20; ogre.hit_dice = 5
	ogre.grid_position = Vector3i(10, 10, 0)
	var roster := _MockRoster.new()
	roster.combatants = [caster, ogre]
	hooks.on_round_end(1, roster)
	check(ogre.hp_current == 20,
		">=3 HD creature gets attack roll (here a miss), no damage, got %d" %
			ogre.hp_current)
	check(not ogre.has_condition("frightened"),
		">=3 HD creature is NOT auto-driven-off")


func test_insect_plague_caster_damage_flips_to_stationary() -> void:
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	caster.damaged_since_declaration = true
	var effect := _make_plague_effect("caster_p4", [Vector3i(10, 10, 0)])
	tracker.add_effect(effect)
	var roster := _MockRoster.new()
	roster.combatants = [caster]
	hooks.on_round_end(1, roster)
	var stored: Dictionary = tracker.get_effect("fx_plague")
	var cp: Dictionary = stored.get("metadata", {}).get("plague_profile", {})
	check(cp.get("control_state") == "stationary",
		"caster damage flips control_state to 'stationary', got '%s'" %
			cp.get("control_state"))


func test_insect_plague_stationary_persists_once_flipped() -> void:
	# Once flipped, the state stays — even if caster is no longer flagged.
	var dice := _FakeDice.new()
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	caster.damaged_since_declaration = true
	var effect := _make_plague_effect("caster_p4", [Vector3i(10, 10, 0)])
	tracker.add_effect(effect)
	var roster := _MockRoster.new()
	roster.combatants = [caster]
	hooks.on_round_end(1, roster)
	# Round 2: caster is fine; control_state should remain stationary.
	caster.damaged_since_declaration = false
	hooks.on_round_end(2, roster)
	var stored: Dictionary = tracker.get_effect("fx_plague")
	var cp: Dictionary = stored.get("metadata", {}).get("plague_profile", {})
	check(cp.get("control_state") == "stationary",
		"control_state remains 'stationary' once flipped, got '%s'" %
			cp.get("control_state"))


func test_insect_plague_multiple_swarms_attack_independently() -> void:
	var dice := _FakeDice.new()
	dice.fixed["insect_plague_attack"] = 20
	dice.fixed["insect_plague_damage"] = 2
	var tracker := ActiveEffectTracker.new()
	var hooks := SpellCombatHooks.new(tracker, dice)
	var caster := _make_caster("caster_p4", Vector3i(0, 0, 0))
	var effect := _make_plague_effect("caster_p4",
		[Vector3i(10, 10, 0), Vector3i(11, 10, 0), Vector3i(10, 11, 0), Vector3i(11, 11, 0)])
	tracker.add_effect(effect)
	# One ogre per swarm cell.
	var ogres: Array = []
	for i in range(4):
		var ogre := _MockCombatant.new()
		ogre.id = "ogre_%d" % i; ogre.hp_max = 20; ogre.hp_current = 20; ogre.hit_dice = 5
		var pcell: Vector3i = effect.metadata.plague_profile.swarms[i].swarm_cell
		ogre.grid_position = pcell
		ogres.append(ogre)
	var roster := _MockRoster.new()
	roster.combatants = [caster] + ogres
	hooks.on_round_end(1, roster)
	for o in ogres:
		check(o.hp_current == 18,
			"each ogre takes 2 swarm damage independently, hp 20 → 18, got %d" %
				o.hp_current)
