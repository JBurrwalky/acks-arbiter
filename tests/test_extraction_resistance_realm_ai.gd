extends "res://tests/test_suite_base.gd"

## Tests for the Phase 7 Realm-AI federation in ExtractionResistanceHeuristic
## (Day-1 Todo 4 — replaces the v1 50% BR placeholder with vassal-force
## federation per acore_axioms §non_henchman_vassals + §muster_delay).

class FakeDice:
	extends RefCounted
	var fixed_total: int = 12
	func roll(_count: int, _sides: int) -> int:
		return fixed_total

var _campaign_id: String = ""
var _liege_id: String = ""
var _liege_domain_id: String = ""
var _vassal_id: String = ""
var _vassal_domain_id: String = ""
var _attacker_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_evaluate_returns_personal_and_vassal_br_breakdown()
	test_loyal_vassal_contributes_br_to_resistance()
	test_resignation_vassal_marked_revolted_and_excluded()
	if not has_failures():
		print("ExtractionResistanceRealmAI: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Extraction RealmAI", "World")
	_liege_id = _make_character("Liege")
	_vassal_id = _make_character("Vassal")
	_attacker_id = _make_character("Attacker")
	_liege_domain_id = _make_domain("Liege Realm", _liege_id)
	_vassal_domain_id = _make_domain("Vassal Sub-Realm", _vassal_id)
	# Wire vassal_assignment.
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": _vassal_id, "vassal_domain_id": _vassal_domain_id,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
		"base_loyalty_modifier": 4,  # high loyalty so default rolls succeed
	})


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _make_domain(name: String, owner: String) -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": name, "owner_character_id": owner,
	})


func _make_garrison_unit(domain_id: String, owner: String, br: float) -> String:
	var id := TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": owner,
		"source_type": "mercenary", "troop_type": "Heavy Infantry",
		"count": 60, "starting_count": 60, "battle_rating": br,
		"monthly_wage_cp": 600,
	})
	# Garrison-assign and persist.
	CampaignRepository.db.query_with_bindings(
		"UPDATE troop_units SET assigned_domain_id = ?, assignment_kind = 'garrison' WHERE id = ?",
		[domain_id, id]
	)
	return id


func _make_attacker_army(br_per_unit: float, unit_count: int) -> String:
	var id := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Attacker Host",
		"political_owner_id": _attacker_id, "command_character_id": _attacker_id,
		"state": "marching", "formed_calendar_day": 100,
	})
	ArmyRepository.create_supply_state({"army_id": id})
	var leader := ArmyRepository.create_officer({
		"army_id": id, "character_id": _attacker_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(unit_count):
		var unit_id := TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": _attacker_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": br_per_unit,
			"monthly_wage_cp": 600,
		})
		ArmyRepository.create_assignment({
			"army_id": id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return id


func test_evaluate_returns_personal_and_vassal_br_breakdown() -> void:
	# Liege has 1.5 BR garrison; vassal has 1.0 BR garrison; attacker has 4 BR.
	_make_garrison_unit(_liege_domain_id, _liege_id, 1.5)
	_make_garrison_unit(_vassal_domain_id, _vassal_id, 1.0)
	var attacker_id := _make_attacker_army(4.0, 1)

	# Loaded dice — return high enough to ensure loyal outcome.
	# HenchmanLoyaltyResolver expects a node-like with `roll(count, sides)`.
	var dice := FakeDice.new()
	dice.fixed_total = 8  # 8 + base_loyalty_modifier 4 = 12 → loyal

	var result := ExtractionResistanceHeuristic.evaluate(
		_liege_domain_id, attacker_id, 100, dice)
	check(absf(float(result["personal_br"]) - 1.5) < 0.01,
		"personal BR is 1.5; got %s" % result["personal_br"])
	check(absf(float(result["vassal_br"]) - 1.0) < 0.01,
		"vassal BR is 1.0; got %s" % result["vassal_br"])
	check(absf(float(result["available_br"]) - 2.5) < 0.01,
		"federated BR is 2.5; got %s" % result["available_br"])
	check(int(result["vassals_responding"].size()) == 1, "1 responding vassal")


func test_loyal_vassal_contributes_br_to_resistance() -> void:
	var fresh_liege := _make_character("LoyalLiege")
	var fresh_vassal := _make_character("LoyalVassal")
	var ld := _make_domain("LoyalLD", fresh_liege)
	var vd := _make_domain("LoyalVD", fresh_vassal)
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
		"base_loyalty_modifier": 4,
	})
	_make_garrison_unit(ld, fresh_liege, 1.0)
	_make_garrison_unit(vd, fresh_vassal, 2.0)
	var attacker_id := _make_attacker_army(2.5, 1)
	var dice := FakeDice.new()
	dice.fixed_total = 8  # 8 + 4 = 12 → loyal
	var result := ExtractionResistanceHeuristic.evaluate(ld, attacker_id, 200, dice)
	# 1.0 personal + 2.0 vassal = 3.0 vs 1.25 threshold (50% of 2.5) → resists.
	check(bool(result["will_resist"]),
		"federated 3.0 BR meets 50% threshold of 2.5 BR attacker")


func test_resignation_vassal_marked_revolted_and_excluded() -> void:
	var fresh_liege := _make_character("RevoltLiege")
	var fresh_vassal := _make_character("RevoltVassal")
	var ld := _make_domain("RevoltLD", fresh_liege)
	var vd := _make_domain("RevoltVD", fresh_vassal)
	var assn_id := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
		"base_loyalty_modifier": -4,  # very low — resignation likely
	})
	_make_garrison_unit(ld, fresh_liege, 1.0)
	_make_garrison_unit(vd, fresh_vassal, 2.0)
	var attacker_id := _make_attacker_army(2.0, 1)
	# Loaded dice: 2 + (-4) = -2 → hostility.
	var dice := FakeDice.new()
	dice.fixed_total = 2
	var result := ExtractionResistanceHeuristic.evaluate(ld, attacker_id, 300, dice)
	# Vassal should refuse and revolt; the vassal's 2.0 BR should NOT contribute.
	check(absf(float(result["vassal_br"]) - 0.0) < 0.01,
		"vassal_br = 0 because vassal refused; got %s" % result["vassal_br"])
	check(int(result["vassals_refusing"].size()) == 1, "1 refusing vassal")
	# Verify vassal_assignment status flipped to revolted.
	var refreshed := VassalRepository.get_assignment(assn_id)
	check(String(refreshed.get("status", "")) == "revolted",
		"vassal_assignment status = revolted; got %s" % refreshed.get("status", ""))
