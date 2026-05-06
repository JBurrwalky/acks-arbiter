extends "res://tests/test_suite_base.gd"

## Session P3 — Spawn-Roster Integration.
##
## Validates SpawnRosterIntegrator builds Combatants from spawn_profiles and
## adds them to the live combat roster. Each spell's persisted active_effect
## metadata key is read by the matching _spawn_* handler:
##   animate_dead         → metadata.animate_dead_spawn_profile
##   sticks_to_snakes     → metadata.sticks_to_snakes_spawn_profile
##   conjure_elemental    → metadata.conjure_elemental_spawn_profile
##   invisible_stalker    → metadata.invisible_stalker_spawn_profile
##   insect_plague        → metadata.plague_profile


func run_all_tests() -> void:
	test_animate_dead_spawns_undead_on_party_side()
	test_sticks_to_snakes_spawns_mix_of_snake_types()
	test_conjure_elemental_single_party_spawn()
	test_invisible_stalker_spawn_marks_invisible()
	test_insect_plague_spawns_four_swarms()
	test_spawned_ids_recorded_on_effect_metadata()
	test_duplicate_id_rejected_by_roster()
	test_signal_subscribe_unsubscribe_cleanly()
	test_spawned_combatants_placed_on_grid()
	test_hp_rolled_per_stat_block()
	test_side_defaults_party_for_spawn_spells()
	test_empty_spawn_profile_no_error()
	if not has_failures():
		print("SessionP3SpawnRoster: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_environment() -> Dictionary:
	var roster := CombatRoster.new()
	var voxel_map: VoxelMapData = VoxelMapData.generate_open_field(20, 20)
	var movement_resolver := MovementResolver.new(roster)
	movement_resolver.set_voxel_map(voxel_map)
	var tracker := ActiveEffectTracker.new()
	var registry := MonsterRegistry.new()
	# Register a caster combatant so origin_cell lookups succeed.
	var caster_data: Dictionary = registry.get_monster("goblin")
	if caster_data.is_empty():
		caster_data = {
			"name": "Caster", "hit_dice": {"base": 1}, "armor_class": 0,
			"attack_routines": [], "save_as": {"class": "M", "level": 5},
			"morale": 0, "xp": 0,
			"movement": {"land": {"exploration": 60, "combat": 20}},
			"morale_modifiers": [], "special_abilities": [],
			"immunities": [], "resistances": [], "vulnerabilities": [],
			"combat_behavior": {},
		}
	var caster := Combatant.from_monster(caster_data, 8, "caster_p3", "caster")
	caster.side = Combatant.Side.PARTY
	roster.add_combatant(caster)
	movement_resolver.set_grid_position_3d(caster, Vector3i(10, 10, 0))
	var integrator := SpawnRosterIntegrator.new(
		roster, movement_resolver, tracker, registry, null)
	return {
		"roster": roster, "voxel_map": voxel_map,
		"movement_resolver": movement_resolver,
		"tracker": tracker, "registry": registry,
		"integrator": integrator, "caster": caster,
	}


func _build_animate_dead_effect(caster_id: String) -> Dictionary:
	var profile: Dictionary = {
		"caster_id": caster_id,
		"caster_level": 5,
		"hd_budget": 10,
		"hd_spent": 5,
		"animated": [
			{"undead_id": "z1", "undead_template": "zombie", "hd_cost": 2, "caster_id": caster_id},
			{"undead_id": "z2", "undead_template": "zombie", "hd_cost": 2, "caster_id": caster_id},
			{"undead_id": "s1", "undead_template": "skeleton", "hd_cost": 1, "caster_id": caster_id},
		],
	}
	return {
		"effect_id": "fx_animate_dead",
		"spell_key": "animate_dead",
		"caster_id": caster_id,
		"target_ids": [],
		"effect_type": "entity",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "permanent", "duration_remaining": -1,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"animate_dead_spawn_profile": profile},
		"created_at_round": 0,
	}


# ---------------------------------------------------------------------------
# Animate Dead
# ---------------------------------------------------------------------------

func test_animate_dead_spawns_undead_on_party_side() -> void:
	var env := _make_environment()
	var effect := _build_animate_dead_effect("caster_p3")
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "animate_dead")
	check(spawned.size() == 3, "3 undead animated, got %d" % spawned.size())
	for cid in spawned:
		var c: Combatant = env.roster.get_by_id(cid)
		check(c != null, "spawned combatant '%s' on roster" % cid)
		if c != null:
			check(c.side == Combatant.Side.PARTY,
				"animated undead on PARTY side, got %d" % c.side)


# ---------------------------------------------------------------------------
# Sticks to Snakes
# ---------------------------------------------------------------------------

func test_sticks_to_snakes_spawns_mix_of_snake_types() -> void:
	var env := _make_environment()
	var profile: Dictionary = {
		"caster_id": "caster_p3", "caster_level": 4,
		"brackets": 1, "snake_count": 3,
		"snakes": [
			{"snake_id": "snake_a", "poisonous": true, "obeys_caster_id": "caster_p3"},
			{"snake_id": "snake_b", "poisonous": false, "obeys_caster_id": "caster_p3"},
			{"snake_id": "snake_c", "poisonous": true, "obeys_caster_id": "caster_p3"},
		],
	}
	var effect: Dictionary = {
		"effect_id": "fx_sticks", "spell_key": "sticks_to_snakes",
		"caster_id": "caster_p3", "target_ids": [], "effect_type": "entity",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "turns", "duration_remaining": 6,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"sticks_to_snakes_spawn_profile": profile},
		"created_at_round": 0,
	}
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "sticks_to_snakes")
	check(spawned.size() == 3, "3 snakes on roster, got %d" % spawned.size())
	# At least one each of the two stat-block templates spawned.
	var has_poisonous := false
	var has_normal := false
	for cid in spawned:
		var c: Combatant = env.roster.get_by_id(cid)
		if c == null:
			continue
		if c.monster_group_id == "snake_poisonous":
			has_poisonous = true
		elif c.monster_group_id == "snake_normal":
			has_normal = true
	check(has_poisonous, "at least one poisonous snake spawned")
	check(has_normal, "at least one normal snake spawned")


# ---------------------------------------------------------------------------
# Conjure Elemental
# ---------------------------------------------------------------------------

func test_conjure_elemental_single_party_spawn() -> void:
	var env := _make_environment()
	var profile: Dictionary = {
		"elemental_id": "elemental_fire:caster_p3",
		"elemental_type": "fire",
		"caster_id": "caster_p3", "caster_level": 9,
		"summon_cell": Vector3i(12, 10, 0),
		"loyalty": "controlled_via_concentration",
	}
	var effect: Dictionary = {
		"effect_id": "fx_elemental", "spell_key": "conjure_elemental",
		"caster_id": "caster_p3", "target_ids": [], "effect_type": "entity",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "concentration", "duration_remaining": -1,
		"requires_concentration": 1, "is_active": 1,
		"metadata": {"conjure_elemental_spawn_profile": profile},
		"created_at_round": 0,
	}
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "conjure_elemental")
	check(spawned.size() == 1, "exactly 1 elemental spawned, got %d" % spawned.size())
	if spawned.size() == 1:
		var c: Combatant = env.roster.get_by_id(spawned[0])
		check(c.side == Combatant.Side.PARTY, "controlled elemental on PARTY side")
		check(c.monster_group_id == "elemental_fire", "monster_group_id = elemental_fire")
		check(c.grid_position == Vector3i(12, 10, 0),
			"placed at summon_cell, got %s" % str(c.grid_position))


# ---------------------------------------------------------------------------
# Invisible Stalker
# ---------------------------------------------------------------------------

func test_invisible_stalker_spawn_marks_invisible() -> void:
	var env := _make_environment()
	var profile: Dictionary = {
		"stalker_id": "stalker:caster_p3",
		"caster_id": "caster_p3", "caster_level": 11,
	}
	var effect: Dictionary = {
		"effect_id": "fx_stalker", "spell_key": "invisible_stalker",
		"caster_id": "caster_p3", "target_ids": [], "effect_type": "entity",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "permanent", "duration_remaining": -1,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"invisible_stalker_spawn_profile": profile},
		"created_at_round": 0,
	}
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "invisible_stalker")
	check(spawned.size() == 1, "1 stalker spawned, got %d" % spawned.size())
	if spawned.size() == 1:
		var c: Combatant = env.roster.get_by_id(spawned[0])
		var flags := c.get_flags()
		check(flags != null and flags.has_flag("is_invisible"),
			"stalker flagged is_invisible")


# ---------------------------------------------------------------------------
# Insect Plague — 4 swarms
# ---------------------------------------------------------------------------

func test_insect_plague_spawns_four_swarms() -> void:
	var env := _make_environment()
	var profile: Dictionary = {
		"plague_id": "insect_plague:caster_p3",
		"caster_id": "caster_p3", "caster_level": 9,
		"swarms": [
			{"swarm_id": "sw_0", "swarm_index": 0, "swarm_cell": Vector3i(15, 10, 0), "swarm_hd": 4, "area_feet": 30},
			{"swarm_id": "sw_1", "swarm_index": 1, "swarm_cell": Vector3i(16, 10, 0), "swarm_hd": 4, "area_feet": 30},
			{"swarm_id": "sw_2", "swarm_index": 2, "swarm_cell": Vector3i(15, 11, 0), "swarm_hd": 4, "area_feet": 30},
			{"swarm_id": "sw_3", "swarm_index": 3, "swarm_cell": Vector3i(16, 11, 0), "swarm_hd": 4, "area_feet": 30},
		],
		"control_state": "controlled",
	}
	var effect: Dictionary = {
		"effect_id": "fx_plague", "spell_key": "insect_plague",
		"caster_id": "caster_p3", "target_ids": [], "effect_type": "entity",
		"applied_modifiers": [], "applied_conditions": [], "applied_flags": [],
		"duration_type": "days", "duration_remaining": 1,
		"requires_concentration": 0, "is_active": 1,
		"metadata": {"plague_profile": profile},
		"created_at_round": 0,
	}
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "insect_plague")
	check(spawned.size() == 4, "4 swarms spawned, got %d" % spawned.size())
	# Each swarm placed at its swarm_cell.
	for i in range(spawned.size()):
		var c: Combatant = env.roster.get_by_id(spawned[i])
		check(c.grid_position == profile.swarms[i].swarm_cell,
			"swarm %d at swarm_cell %s, got %s" %
			[i, str(profile.swarms[i].swarm_cell), str(c.grid_position)])


# ---------------------------------------------------------------------------
# Cross-cutting — spawned_ids recorded, dup id rejected, signal lifecycle
# ---------------------------------------------------------------------------

func test_spawned_ids_recorded_on_effect_metadata() -> void:
	var env := _make_environment()
	var effect := _build_animate_dead_effect("caster_p3")
	env.tracker.add_effect(effect)
	env.integrator.process_effect(effect, "animate_dead")
	var stored: Dictionary = env.tracker.get_effect("fx_animate_dead")
	var meta: Dictionary = stored.get("metadata", {})
	var ids: Array = meta.get("spawned_combatant_ids", [])
	check(ids.size() == 3,
		"spawned_combatant_ids written back to active_effect.metadata, got %d" % ids.size())


func test_duplicate_id_rejected_by_roster() -> void:
	var roster := CombatRoster.new()
	var monster_data := MonsterRegistry.new().get_monster("goblin")
	var first := Combatant.from_monster(monster_data, 6, "dup", "test")
	check(roster.add_combatant(first), "first add succeeds")
	var second := Combatant.from_monster(monster_data, 6, "dup", "test")
	check(not roster.add_combatant(second),
		"duplicate-id add rejected by guard")


func test_signal_subscribe_unsubscribe_cleanly() -> void:
	var env := _make_environment()
	# Idempotent connect.
	env.integrator.connect_signals()
	env.integrator.connect_signals()
	check(EventBus.spell_effect_applied.get_connections().size() >= 1,
		"signal connected at least once")
	env.integrator.disconnect_signals()
	# After disconnect, our integrator's handler should not be registered.
	for conn in EventBus.spell_effect_applied.get_connections():
		var callable: Callable = conn.get("callable", Callable())
		check(callable.get_object() != env.integrator,
			"integrator handler removed after disconnect")
	# Idempotent disconnect.
	env.integrator.disconnect_signals()


# ---------------------------------------------------------------------------
# Placement, HP, side defaults, and empty-profile defense in depth
# ---------------------------------------------------------------------------

func test_spawned_combatants_placed_on_grid() -> void:
	var env := _make_environment()
	var effect := _build_animate_dead_effect("caster_p3")
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "animate_dead")
	# Animate Dead places at caster's origin cell (10, 10, 0).
	for cid in spawned:
		var c: Combatant = env.roster.get_by_id(cid)
		check(c.grid_position == Vector3i(10, 10, 0),
			"%s placed at caster origin cell, got %s" % [cid, str(c.grid_position)])


func test_hp_rolled_per_stat_block() -> void:
	var env := _make_environment()
	var effect := _build_animate_dead_effect("caster_p3")
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "animate_dead")
	# Without dice, default = base*4 + modifier per stat block.
	# Skeleton: 1d8 → 4 hp; Zombie: 2d8 → 8 hp.
	for cid in spawned:
		var c: Combatant = env.roster.get_by_id(cid)
		if c.monster_group_id == "skeleton":
			check(c.get_hp_max() == 4, "skeleton hp_max = 4 (1d8 avg), got %d" % c.get_hp_max())
		elif c.monster_group_id == "zombie":
			check(c.get_hp_max() == 8, "zombie hp_max = 8 (2d8 avg), got %d" % c.get_hp_max())


func test_side_defaults_party_for_spawn_spells() -> void:
	var env := _make_environment()
	var effect := _build_animate_dead_effect("caster_p3")
	env.tracker.add_effect(effect)
	var spawned: Array[String] = env.integrator.process_effect(effect, "animate_dead")
	for cid in spawned:
		var c: Combatant = env.roster.get_by_id(cid)
		check(c.is_pc_side(), "spawn defaults to PARTY side for ally summon")


func test_empty_spawn_profile_no_error() -> void:
	var env := _make_environment()
	var effect: Dictionary = {
		"effect_id": "fx_empty",
		"spell_key": "animate_dead",
		"caster_id": "caster_p3",
		"target_ids": [],
		"metadata": {},
	}
	# No corpses → no rostering, no error.
	var spawned: Array[String] = env.integrator.process_effect(effect, "animate_dead")
	check(spawned.is_empty(), "empty profile yields empty spawn array")
