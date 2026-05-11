extends "res://tests/test_suite_base.gd"

## End-to-end test for FieldBattleResolver silent path. Runs a complete
## NPC-vs-NPC battle and verifies it terminates with a valid outcome and
## the appropriate state mutations.


var _campaign_id: String = ""


func _max_roller(_count: int, sides: int) -> int:
	return sides


func _high_roller(_count: int, sides: int) -> int:
	return sides - 1


func run_all_tests() -> void:
	_setup()
	test_silent_battle_terminates_with_outcome()
	test_battle_log_contains_canonical_events()
	test_field_battle_state_persists_for_save_load()
	if not has_failures():
		print("FieldBattleResolver: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FieldBattle Test", "World")


func _make_npc(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _build_basic_army(name: String, owner_id: String, br_per_unit: float, unit_count: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": name,
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "marching", "unit_scale": "company",
	})
	var leader_id: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": owner_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(unit_count):
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Inf",
			"count": 60, "starting_count": 60,
			"battle_rating": br_per_unit,
			"morale": 0,
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader_id, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_silent_battle_terminates_with_outcome() -> void:
	var attacker_owner := _make_npc("Atta")
	var defender_owner := _make_npc("Defe")
	var attacker := _build_basic_army("Attacker", attacker_owner, 2.0, 5)  # BR 10
	var defender := _build_basic_army("Defender", defender_owner, 1.0, 3)  # BR 3 — outmatched
	# Deterministic roller: always returns max-value rolls so attacks
	# usually hit and the battle resolves predictably.
	var roller := func(_c, sides): return sides
	var battle_id := FieldBattleResolver.start_battle(
		attacker, defender, "clear_or_grass", "calm", 100, false, roller, 12345
	)
	check(not battle_id.is_empty(), "battle started")
	var outcome := FieldBattleResolver.resolve_silently(battle_id, roller)
	check(not outcome.is_empty(), "battle ended with outcome; got '%s'" % outcome)
	# Confirm the field_battles row is in concluded phase.
	var battle := BattleRepository.get_battle(battle_id)
	check(String(battle.get("current_phase", "")) == "concluded", "phase = concluded")
	check(String(battle.get("outcome", "")) == outcome, "outcome stored")


func test_battle_log_contains_canonical_events() -> void:
	var attacker_owner := _make_npc("Att2")
	var defender_owner := _make_npc("Def2")
	var attacker := _build_basic_army("Att2", attacker_owner, 1.5, 3)
	var defender := _build_basic_army("Def2", defender_owner, 1.5, 3)
	var roller := func(_c, sides): return sides - 1
	var battle_id := FieldBattleResolver.start_battle(
		attacker, defender, "hills", "calm", 100, false, roller, 99
	)
	FieldBattleResolver.resolve_silently(battle_id, roller)
	var log_entries := BattleRepository.list_log_for_battle(battle_id)
	# Confirm canonical events fired at least once.
	var event_types: Array = []
	for entry in log_entries:
		event_types.append(String(entry.get("event_type", "")))
	check(event_types.has("battle_started"), "battle_started logged")
	check(event_types.has("surprise_resolved"), "surprise_resolved logged")
	check(event_types.has("terrain_advantage_resolved"), "terrain_advantage_resolved logged")
	check(event_types.has("units_deployed"), "units_deployed logged")
	check(event_types.has("phase_started"), "phase_started logged")
	check(event_types.has("attack_throws_rolled"), "attack_throws_rolled logged")
	check(event_types.has("phase_ended"), "phase_ended logged")
	# Sequence numbers are monotonic.
	for i in range(1, log_entries.size()):
		var prev := int(log_entries[i - 1].get("sequence_number", 0))
		var curr := int(log_entries[i].get("sequence_number", 0))
		check(curr > prev, "sequence increases (entry %d > %d)" % [curr, prev])


func test_field_battle_state_persists_for_save_load() -> void:
	var attacker_owner := _make_npc("Att3")
	var defender_owner := _make_npc("Def3")
	var attacker := _build_basic_army("Att3", attacker_owner, 1.5, 3)
	var defender := _build_basic_army("Def3", defender_owner, 1.5, 3)
	var battle_id := FieldBattleResolver.start_battle(
		attacker, defender, "clear_or_grass", "calm", 100, true,
		func(_c, _s): return 1, 7
	)
	check(not battle_id.is_empty(), "battle started")
	# get_battle_state returns the full reconstruction tuple.
	var state := FieldBattleResolver.get_battle_state(battle_id)
	check(state.has("battle"), "state has battle row")
	check(state.has("unit_states"), "state has unit_states")
	check(state.has("log"), "state has log")
	var states_arr: Array = state.get("unit_states", [])
	# 3 attacker units + 3 defender units = 6 total.
	check(states_arr.size() == 6, "6 unit states; got %d" % states_arr.size())
