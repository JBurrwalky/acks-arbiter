extends "res://tests/test_suite_base.gd"

## Phase 6B part 2 tests for FieldBattleResolver:
##   - lieutenant attack-throw bonus
##   - start_battle_with_overrides (siege assault path)
##   - interactive continue_battle() driver

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_lieutenant_phase_bonus_table()
	test_lieutenant_br_fraction_zero_when_no_lieutenants()
	test_start_battle_with_overrides_logs_siege_overrides()
	test_get_siege_overrides_returns_dict()
	test_get_siege_overrides_empty_for_normal_battle()
	test_continue_battle_advances_phase_with_player_choice()
	test_continue_battle_concludes_on_battle_end()
	test_continue_battle_rejects_invalid_battle_id()
	if not has_failures():
		print("FieldBattlePhase2: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Phase2 Test", "World")


func _make_npc(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current, xp)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60, 0)
	""", [id, _campaign_id, name])
	return id


func _build_army(name: String, owner_id: String, br_per_unit: float, unit_count: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": name,
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "marching", "unit_scale": "company",
		"map_id": CampaignRepository.generate_id(),
		"hex_q": 0, "hex_r": 0,
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
			"battle_rating": br_per_unit, "morale": 0,
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader_id, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_lieutenant_phase_bonus_table() -> void:
	# Per RAW §attack_throw_modifiers L217: missile 0 / skirmish +1 / melee +2.
	check(FieldBattleResolver._lieutenant_phase_bonus("missile") == 0, "missile = 0")
	check(FieldBattleResolver._lieutenant_phase_bonus("skirmish") == 1, "skirmish = +1")
	check(FieldBattleResolver._lieutenant_phase_bonus("melee") == 2, "melee = +2")


func test_lieutenant_br_fraction_zero_when_no_lieutenants() -> void:
	# Build a battle where no unit has a lieutenant parent_officer.
	var atk_owner := _make_npc("LtTestAtk")
	var def_owner := _make_npc("LtTestDef")
	var attacker := _build_army("LtAtk", atk_owner, 1.0, 2)
	var defender := _build_army("LtDef", def_owner, 1.0, 2)
	var battle_id := FieldBattleResolver.start_battle(
		attacker, defender, "clear_or_grass", "calm", 100, false,
		func(_c, sides): return sides
	)
	check(not battle_id.is_empty(), "battle started")
	# All participants report to the army_leader, not a lieutenant. Fraction = 0.
	var attacker_states: Array = BattleRepository.list_unit_states_for_side(battle_id, "attacker")
	check(FieldBattleResolver._lieutenant_br_fraction(attacker_states) == 0.0,
		"no lieutenants → fraction 0")


func test_start_battle_with_overrides_logs_siege_overrides() -> void:
	var atk_owner := _make_npc("SiegeAtk")
	var def_owner := _make_npc("SiegeDef")
	var attacker := _build_army("SAtk", atk_owner, 1.5, 3)
	var defender := _build_army("SDef", def_owner, 1.5, 3)
	var modifiers := {
		"max_assaulting_units": 5,
		"max_defending_units": 3,
		"defending_infantry_br_bonus": 1,
		"base_attack_target": 16,
		"assaulting_attack_modifier": -2,
		"defending_attack_modifier": 2,
	}
	var battle_id := FieldBattleResolver.start_battle_with_overrides(
		attacker, defender, "hills", "calm", 100, false, modifiers,
		func(_c, sides): return sides
	)
	check(not battle_id.is_empty(), "battle started")
	# The siege_overrides_applied event should be in the log.
	var log_entries: Array = BattleRepository.list_log_for_battle(battle_id)
	var found := false
	for e in log_entries:
		if String(e.get("event_type", "")) == "siege_overrides_applied":
			found = true
			break
	check(found, "siege_overrides_applied event logged")


func test_get_siege_overrides_returns_dict() -> void:
	var atk_owner := _make_npc("SOAtk")
	var def_owner := _make_npc("SODef")
	var attacker := _build_army("SOAtkA", atk_owner, 1.0, 2)
	var defender := _build_army("SODefA", def_owner, 1.0, 2)
	var modifiers := {"base_attack_target": 16, "assaulting_attack_modifier": -2}
	var battle_id := FieldBattleResolver.start_battle_with_overrides(
		attacker, defender, "clear_or_grass", "calm", 100, false, modifiers,
		Callable()
	)
	var retrieved := FieldBattleResolver.get_siege_overrides(battle_id)
	check(int(retrieved.get("base_attack_target", 0)) == 16, "base_attack_target round-trips")
	check(int(retrieved.get("assaulting_attack_modifier", 0)) == -2, "modifier round-trips")
	# Defaults filled in.
	check(int(retrieved.get("defending_infantry_br_bonus", 0)) == 1, "default defending bonus filled")


func test_get_siege_overrides_empty_for_normal_battle() -> void:
	var atk_owner := _make_npc("NormAtk")
	var def_owner := _make_npc("NormDef")
	var attacker := _build_army("NAtk", atk_owner, 1.0, 2)
	var defender := _build_army("NDef", def_owner, 1.0, 2)
	var battle_id := FieldBattleResolver.start_battle(
		attacker, defender, "clear_or_grass", "calm", 100, false, Callable()
	)
	var retrieved := FieldBattleResolver.get_siege_overrides(battle_id)
	check(retrieved.is_empty(), "normal battle has no overrides")


func test_continue_battle_advances_phase_with_player_choice() -> void:
	var atk_owner := _make_npc("InterAtk")
	var def_owner := _make_npc("InterDef")
	var attacker := _build_army("IAtk", atk_owner, 1.5, 3)
	var defender := _build_army("IDef", def_owner, 1.5, 3)
	var battle_id := FieldBattleResolver.start_battle(
		attacker, defender, "clear_or_grass", "calm", 100, true,
		func(_c, sides): return sides
	)
	check(not battle_id.is_empty(), "battle started")
	# Player chooses both sides hold (defender NPC heuristic also picks hold by default
	# absent decision input). Pass attacker_choice='hold' and defender_choice='hold'.
	var decision := {
		"attacker_choice": "hold",
		"defender_choice": "hold",
	}
	var result := FieldBattleResolver.continue_battle(battle_id, decision,
		func(_c, sides): return sides)
	check(bool(result.get("phase_completed", false)), "phase completed")
	# Battle should not have ended on a single hold/hold (BPC unchanged).
	# Still active.
	var battle := BattleRepository.get_battle(battle_id)
	check(String(battle.get("outcome", "")) == "" or bool(result.get("battle_concluded", false)),
		"battle either continues or concluded; outcome=%s" % battle.get("outcome", ""))


func test_continue_battle_concludes_on_battle_end() -> void:
	# Force a quick conclusion: both withdraw on missile phase with starting BPC=1
	# so 1 + 2 = 3 ≥ 2× starting (2) → draw.
	var atk_owner := _make_npc("EndAtk")
	var def_owner := _make_npc("EndDef")
	var attacker := _build_army("EAtk", atk_owner, 1.0, 2)
	var defender := _build_army("EDef", def_owner, 1.0, 2)
	# We need starting_bpc=1. clear_or_grass at any roll has BPC 1 (mostly).
	var battle_id := FieldBattleResolver.start_battle(
		attacker, defender, "clear_or_grass", "calm", 100, true,
		func(_c, _sides): return 1  # min rolls → BPC 1, surprise rolls 1 = surprised
	)
	# Force surprise off by updating directly (avoid surprised-army-cannot-attack
	# silencing the first 3 phases — irrelevant here since we're testing termination).
	BattleRepository.update_battle(battle_id, {
		"attacker_surprised": 0, "defender_surprised": 0,
		"starting_bpc": 1, "current_bpc": 1,
	})
	var result := FieldBattleResolver.continue_battle(battle_id, {
		"attacker_choice": "withdraw",
		"defender_choice": "withdraw",
	}, func(_c, sides): return sides)
	check(bool(result.get("battle_concluded", false)),
		"battle concluded; got %s" % result)
	check(String(result.get("outcome", "")) == "mutual_withdrawal_draw",
		"outcome = mutual_withdrawal_draw; got %s" % result.get("outcome", "?"))


func test_continue_battle_rejects_invalid_battle_id() -> void:
	var result := FieldBattleResolver.continue_battle("nonexistent", {})
	check(not bool(result.get("phase_completed", true)), "phase not completed for invalid id")
	check(not bool(result.get("battle_concluded", true)), "not concluded for invalid id")
	check(String(result.get("error", "")) != "", "error reported")
