extends "res://tests/test_suite_base.gd"

## Tests heroic-foray declarations being consumed by continue_battle().
## Phase 6B closing piece — exercises the foray simulation placeholder
## (HeroicForayResolver.simulate_foray_silently) via the interactive
## resolver path.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_no_forays_battle_proceeds_normally()
	test_attacker_foray_logs_declared_and_resolved_events()
	test_foray_with_zero_stake_is_skipped()
	if not has_failures():
		print("ContinueBattleWithForays: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("ForayContinue Test", "World")


func _make_pc(name: String, level: int = 9) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', ?,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, name, level])
	return id


func _build_army(name: String, owner_id: String, br: float, count: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": name,
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "marching", "unit_scale": "company",
		"map_id": CampaignRepository.generate_id(),
		"hex_q": 0, "hex_r": 0,
	})
	var leader: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": owner_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(count):
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": br, "morale": 0,
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_no_forays_battle_proceeds_normally() -> void:
	var atk_pc := _make_pc("Hero1")
	var def_pc := _make_pc("Hero2")
	var atk := _build_army("AtkA", atk_pc, 1.5, 3)
	var def := _build_army("DefA", def_pc, 1.5, 3)
	var battle_id := FieldBattleResolver.start_battle(
		atk, def, "clear_or_grass", "calm", 100, true,
		func(_c, sides): return sides
	)
	# Continue with no forays — phase should advance.
	var result := FieldBattleResolver.continue_battle(battle_id, {
		"attacker_choice": "hold", "defender_choice": "hold",
	}, func(_c, sides): return sides)
	check(bool(result.get("phase_completed", false)), "phase completed without forays")


func test_attacker_foray_logs_declared_and_resolved_events() -> void:
	var atk_pc := _make_pc("ForayHero")
	var def_pc := _make_pc("Defender")
	var atk := _build_army("AtkB", atk_pc, 1.5, 3)
	var def := _build_army("DefB", def_pc, 1.5, 3)
	var battle_id := FieldBattleResolver.start_battle(
		atk, def, "clear_or_grass", "calm", 100, true,
		func(_c, sides): return sides
	)
	var decision := {
		"attacker_forays": [{"hero_id": atk_pc, "br_staked": 2.0}],
		"attacker_choice": "hold", "defender_choice": "hold",
	}
	FieldBattleResolver.continue_battle(battle_id, decision,
		func(_c, sides): return sides)
	var entries := BattleRepository.list_log_for_battle(battle_id)
	var has_declared := false
	var has_resolved := false
	for e in entries:
		var et := String(e.get("event_type", ""))
		if et == "heroic_foray_declared":
			has_declared = true
		elif et == "heroic_foray_resolved":
			has_resolved = true
	check(has_declared, "heroic_foray_declared logged")
	check(has_resolved, "heroic_foray_resolved logged")


func test_foray_with_zero_stake_is_skipped() -> void:
	var atk_pc := _make_pc("ZeroStaker")
	var def_pc := _make_pc("Def2")
	var atk := _build_army("AtkC", atk_pc, 1.5, 3)
	var def := _build_army("DefC", def_pc, 1.5, 3)
	var battle_id := FieldBattleResolver.start_battle(
		atk, def, "clear_or_grass", "calm", 100, true,
		func(_c, sides): return sides
	)
	var decision := {
		"attacker_forays": [{"hero_id": atk_pc, "br_staked": 0.0}],
		"attacker_choice": "hold", "defender_choice": "hold",
	}
	FieldBattleResolver.continue_battle(battle_id, decision,
		func(_c, sides): return sides)
	var entries := BattleRepository.list_log_for_battle(battle_id)
	var foray_count := 0
	for e in entries:
		if String(e.get("event_type", "")) == "heroic_foray_declared":
			foray_count += 1
	check(foray_count == 0, "zero-stake foray skipped; got %d declarations" % foray_count)
