extends "res://tests/test_suite_base.gd"

## Tests for ExtractionResistanceHeuristic (Phase 6A v1 placeholder).
##
## Covers the 50% BR threshold rule per O-A-9 resolution / gdd-army-warfare.md
## §4.3.3. The heuristic is a stub that the Realm AI subsystem will replace.


var _campaign_id: String = ""
var _ruler_id: String = ""
var _domain_id: String = ""
var _stronghold_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_no_garrison_does_not_resist()
	test_garrison_below_50pct_does_not_resist()
	test_garrison_at_50pct_resists()
	test_garrison_above_50pct_resists()
	if not has_failures():
		print("ExtractionResistanceHeuristic: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Resistance Test", "World")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Local Lord', 'pc', 'full', 'human', 'fighter', 9,
			12, 12, 12, 12, 12, 12, 60, 60)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Local Domain",
		"territory_type": "borderlands", "owner_character_id": _ruler_id,
	})


func _make_attacker_with_br(total_br: float) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Attacker",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "marching",
	})
	var leader_id: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
		"source_type": "mercenary", "troop_type": "Heavy Inf",
		"count": 60, "starting_count": 60, "battle_rating": total_br,
	})
	ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader_id, "role": "line",
		"assigned_calendar_day": 100,
	})
	return army_id


func _add_garrison_unit(br: float) -> void:
	TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": _ruler_id,
		"assigned_domain_id": _domain_id, "assigned_stronghold_id": null,
		"source_type": "follower", "troop_type": "Garrison Inf",
		"count": 60, "starting_count": 60, "battle_rating": br,
		"assignment_kind": "garrison",
	})


func _wipe_garrisons() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE assigned_domain_id = ? AND assignment_kind = 'garrison'",
		[_domain_id]
	)


func test_no_garrison_does_not_resist() -> void:
	_wipe_garrisons()
	var attacker := _make_attacker_with_br(10.0)
	var result := ExtractionResistanceHeuristic.evaluate(_domain_id, attacker, 100)
	check(not bool(result.get("will_resist", true)), "no garrison → no resistance")
	check(String(result.get("reason", "")) == "no_local_garrison", "reason cited")


func test_garrison_below_50pct_does_not_resist() -> void:
	_wipe_garrisons()
	var attacker := _make_attacker_with_br(10.0)
	_add_garrison_unit(2.0)  # 2 < 5 (50% of 10)
	var result := ExtractionResistanceHeuristic.evaluate(_domain_id, attacker, 100)
	check(not bool(result.get("will_resist", true)), "below 50% → no resist")
	check(String(result.get("reason", "")) == "garrison_below_50pct_threshold", "reason cited")


func test_garrison_at_50pct_resists() -> void:
	_wipe_garrisons()
	var attacker := _make_attacker_with_br(10.0)
	_add_garrison_unit(5.0)  # exactly 50%
	var result := ExtractionResistanceHeuristic.evaluate(_domain_id, attacker, 100)
	check(bool(result.get("will_resist", false)), "at 50% threshold → resist")


func test_garrison_above_50pct_resists() -> void:
	_wipe_garrisons()
	var attacker := _make_attacker_with_br(10.0)
	_add_garrison_unit(7.5)
	var result := ExtractionResistanceHeuristic.evaluate(_domain_id, attacker, 100)
	check(bool(result.get("will_resist", false)), "above 50% → resist")
	check(String(result.get("reason", "")) == "garrison_meets_50pct_threshold", "reason cited")
