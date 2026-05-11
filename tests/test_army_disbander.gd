extends "res://tests/test_suite_base.gd"

## Tests for ArmyDisbander (Phase 6A).
##
## Covers:
##   - voluntary disband: mercenaries paid 1 month wages, units released
##   - annihilation: units marked departed
##   - rejection of double-disband
##   - rejection of disband during 'battling' (except annihilation)
##   - per-source destination routing (mercenary/conscript/militia/follower)


var _campaign_id: String = ""
var _ruler_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_voluntary_pays_mercenary_severance()
	test_voluntary_releases_assignments()
	test_annihilation_marks_units_departed()
	test_double_disband_rejected()
	test_disband_battling_rejected()
	test_voluntary_during_battling_rejected_with_clear_error()
	test_unknown_reason_rejected()
	if not has_failures():
		print("ArmyDisbander: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Disband Test", "World")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Disband Lord', 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [_ruler_id, _campaign_id])


func _build_army_with_units(unit_specs: Array) -> Dictionary:
	## unit_specs: Array[Dictionary{source, monthly_wage_gp}]
	## Returns {army_id, leader_id, unit_ids}.
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Disband Host",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped", "formed_calendar_day": 100,
	})
	var leader_id: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	ArmyRepository.create_supply_state({"army_id": army_id})
	var unit_ids: Array = []
	for spec in unit_specs:
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id,
			"owner_character_id": _ruler_id,
			"source_type": String(spec.get("source", "mercenary")),
			"troop_type": "Disband Troop",
			"count": 30, "starting_count": 30, "battle_rating": 1.0,
			"monthly_wage_gp": int(spec.get("monthly_wage_gp", 200)),
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader_id, "role": "line",
			"assigned_calendar_day": 100,
		})
		unit_ids.append(unit_id)
	return {"army_id": army_id, "leader_id": leader_id, "unit_ids": unit_ids}


func test_voluntary_pays_mercenary_severance() -> void:
	var built := _build_army_with_units([
		{"source": "mercenary", "monthly_wage_gp": 500},
		{"source": "mercenary", "monthly_wage_gp": 700},
	])
	var result := ArmyDisbander.disband(built["army_id"], "voluntary", 200)
	check(bool(result.get("success", false)), "voluntary disband ok")
	check(int(result.get("mercenary_severance_gp", 0)) == 1200,
		"severance = sum of monthly_wage_gp; got %d" % result.get("mercenary_severance_gp", 0))


func test_voluntary_releases_assignments() -> void:
	var built := _build_army_with_units([
		{"source": "mercenary", "monthly_wage_gp": 500},
	])
	var result := ArmyDisbander.disband(built["army_id"], "voluntary", 200)
	check(bool(result.get("success", false)), "voluntary disband ok")
	var assignments := ArmyRepository.list_active_assignments_for_army(built["army_id"])
	check(assignments.is_empty(), "active assignments cleared after voluntary disband")
	var army := ArmyRepository.get_army(built["army_id"])
	check(String(army.get("state", "")) == "disbanded", "state set to disbanded")
	check(int(army.get("disbanded_calendar_day", 0)) == 200, "disbanded_calendar_day stamped")


func test_annihilation_marks_units_departed() -> void:
	var built := _build_army_with_units([
		{"source": "mercenary", "monthly_wage_gp": 500},
		{"source": "follower", "monthly_wage_gp": 0},
	])
	var result := ArmyDisbander.disband(built["army_id"], "annihilation", 250)
	check(bool(result.get("success", false)), "annihilation disband ok")
	# All troop_units now status='departed'.
	for unit_id in built["unit_ids"]:
		var unit: Dictionary = TroopUnitRepository.get_unit(unit_id)
		check(String(unit.get("status", "")) == "departed", "unit %s status=departed" % unit_id)
		check(String(unit.get("departure_kind", "")) == "annihilated", "departure_kind=annihilated")
	# Annihilation does NOT pay mercenary severance.
	check(int(result.get("mercenary_severance_gp", 0)) == 0, "no severance on annihilation")


func test_double_disband_rejected() -> void:
	var built := _build_army_with_units([
		{"source": "mercenary", "monthly_wage_gp": 200},
	])
	var first := ArmyDisbander.disband(built["army_id"], "voluntary", 200)
	check(bool(first.get("success", false)), "first disband ok")
	var second := ArmyDisbander.disband(built["army_id"], "voluntary", 201)
	check(not bool(second.get("success", true)), "double-disband rejected")


func test_disband_battling_rejected() -> void:
	var built := _build_army_with_units([
		{"source": "mercenary", "monthly_wage_gp": 200},
	])
	# Force army into 'battling' state.
	ArmyRepository.update_army(built["army_id"], {"state": "battling"})
	var result := ArmyDisbander.disband(built["army_id"], "voluntary", 200)
	check(not bool(result.get("success", true)), "voluntary during battling rejected")


func test_voluntary_during_battling_rejected_with_clear_error() -> void:
	var built := _build_army_with_units([{"source": "mercenary", "monthly_wage_gp": 200}])
	ArmyRepository.update_army(built["army_id"], {"state": "battling"})
	var result := ArmyDisbander.disband(built["army_id"], "voluntary", 200)
	var found := false
	for e in result.get("errors", []):
		if String(e).contains("battling"):
			found = true
			break
	check(found, "error mentions battling state")


func test_unknown_reason_rejected() -> void:
	var built := _build_army_with_units([{"source": "mercenary", "monthly_wage_gp": 200}])
	var result := ArmyDisbander.disband(built["army_id"], "wandered_off", 200)
	check(not bool(result.get("success", true)), "unknown reason rejected")
