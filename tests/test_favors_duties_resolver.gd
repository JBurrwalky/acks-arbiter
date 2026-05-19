extends "res://tests/test_suite_base.gd"

## Phase 8 — FavorsDutiesResolver tests.
## Per acore_axioms_strongholds_and_domains.xml §favors_and_duties L352-372.

class FakeDice:
	extends RefCounted
	var fixed_d20: int = 0
	var fixed_d6: int = 0
	func roll(count: int, sides: int) -> int:
		if count == 1 and sides == 20:
			return fixed_d20
		if count == 1 and sides == 6:
			return fixed_d6
		# 2d6 fallback for HenchmanLoyaltyResolver.
		if count == 2 and sides == 6:
			return 7
		return 1

var _campaign_id: String = ""
var _liege_id: String = ""
var _liege_domain_id: String = ""
var _vassal_id: String = ""
var _vassal_domain_id: String = ""
var _assignment_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_classify_roll_table_dispatch()
	test_roll_monthly_construction_creates_duty()
	test_roll_monthly_gift_transfers_treasury()
	test_roll_monthly_loan_credits_lord_treasury()
	test_roll_monthly_revoke_clears_most_recent()
	test_safe_duty_threshold_henchman_one_free()
	test_safe_duty_threshold_non_henchman_no_free()
	test_cumulative_loyalty_penalty_on_excess_duties()
	if not has_failures():
		print("FavorsDutiesResolver: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FavorsDutiesTest", "World")
	_liege_id = _make_character("Liege")
	_vassal_id = _make_character("Vassal")
	_liege_domain_id = _make_domain("Liege Realm", _liege_id, 800, 200, 5000)
	_vassal_domain_id = _make_domain("Vassal Realm", _vassal_id, 300, 50, 2000)
	_assignment_id = VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": _vassal_id, "vassal_domain_id": _vassal_domain_id,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
		"base_loyalty_modifier": 0,
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


func _make_domain(name: String, owner: String, peasant_families: int, urban_families: int, treasury_cp: int) -> String:
	var id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": name, "owner_character_id": owner,
	})
	CampaignRepository.update_domain_monthly_state(id, {
		"peasant_families": peasant_families,
		"urban_families": urban_families,
		"treasury_cp": treasury_cp,
	})
	return id


func test_classify_roll_table_dispatch() -> void:
	# Spot-check key boundaries per RAW table.
	check(String(FavorsDutiesResolver.classify_roll(1)["result_key"]) == "construction", "1 → construction")
	check(String(FavorsDutiesResolver.classify_roll(2)["result_key"]) == "scutage", "2 → scutage")
	check(String(FavorsDutiesResolver.classify_roll(3)["result_key"]) == "call_to_council", "3 → call_to_council")
	check(String(FavorsDutiesResolver.classify_roll(8)["result_key"]) == "loan", "8 → loan")
	check(String(FavorsDutiesResolver.classify_roll(9)["result_key"]) == "revoke", "9 → revoke")
	check(String(FavorsDutiesResolver.classify_roll(12)["result_key"]) == "revoke", "12 → revoke")
	check(String(FavorsDutiesResolver.classify_roll(13)["result_key"]) == "charter_of_monopoly", "13 → monopoly")
	check(String(FavorsDutiesResolver.classify_roll(15)["result_key"]) == "gift", "15 → gift")
	check(String(FavorsDutiesResolver.classify_roll(19)["result_key"]) == "troops", "19 → troops")
	check(String(FavorsDutiesResolver.classify_roll(20)["result_key"]) == "grant_of_land", "20 → grant_of_land")
	# Kind:
	check(String(FavorsDutiesResolver.classify_roll(2)["kind"]) == "duty", "scutage is a duty")
	check(String(FavorsDutiesResolver.classify_roll(15)["kind"]) == "favor", "gift is a favor")
	check(bool(FavorsDutiesResolver.classify_roll(15)["is_one_time"]), "gift is one-time")
	check(not bool(FavorsDutiesResolver.classify_roll(13)["is_one_time"]), "monopoly is ongoing")


func test_roll_monthly_construction_creates_duty() -> void:
	var dice := FakeDice.new()
	dice.fixed_d20 = 1  # construction
	var result := FavorsDutiesResolver.roll_monthly(_assignment_id, 100, dice)
	check(bool(result["success"]), "roll_monthly succeeds")
	check(String(result["result_key"]) == "construction", "construction result")
	check(String(result["kind"]) == "duty", "kind=duty")
	check(int(result.get("magnitude", 0)) == 0, "magnitude 0 for now (no domain hexes set in test)")
	# Verify obligation persisted.
	var obligations: Array = VassalObligationsRepository.list_active_duties_for_assignment(_assignment_id)
	var found_construction: bool = false
	for o in obligations:
		if String(o.get("type", "")) == "construction":
			found_construction = true
			break
	check(found_construction, "construction obligation persisted")


func test_roll_monthly_gift_transfers_treasury() -> void:
	# Fresh assignment.
	var v := _make_character("GiftVassal")
	var vd := _make_domain("GiftVRealm", v, 100, 0, 500)
	var ld_id := _liege_domain_id
	var ld_before_v: Dictionary = CampaignRepository.get_domain(ld_id)
	var ld_before: int = int(ld_before_v.get("treasury_cp", 0))
	var vd_before_v: Dictionary = CampaignRepository.get_domain(vd)
	var vd_before: int = int(vd_before_v.get("treasury_cp", 0))
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	var dice := FakeDice.new()
	dice.fixed_d20 = 15  # gift
	var result := FavorsDutiesResolver.roll_monthly(assn, 100, dice)
	check(String(result["result_key"]) == "gift", "gift rolled")
	# magnitude = 1gp/family in vassal's realm. v's domain has 100 peasants + 0 urban = 100 families.
	check(int(result["cp_value"]) == 10000, "gift cp_value = 10000 (1gp/family × 100 families × 100cp/gp); got %d" % int(result["cp_value"]))
	# Migration 116 + 111: treasury_cp delta = cp_value = gp_value × 100 = 10000.
	var ld_after_v: Dictionary = CampaignRepository.get_domain(ld_id)
	var ld_after: int = int(ld_after_v.get("treasury_cp", 0))
	var vd_after_v: Dictionary = CampaignRepository.get_domain(vd)
	var vd_after: int = int(vd_after_v.get("treasury_cp", 0))
	check(ld_after == ld_before - 10000, "lord treasury -10000 cp; before=%d after=%d" % [ld_before, ld_after])
	check(vd_after == vd_before + 10000, "vassal treasury +10000 cp; before=%d after=%d" % [vd_before, vd_after])


func test_roll_monthly_loan_credits_lord_treasury() -> void:
	var v := _make_character("LoanVassal")
	var vd := _make_domain("LoanVRealm", v, 200, 0, 1000)
	var ld_before_v: Dictionary = CampaignRepository.get_domain(_liege_domain_id)
	var ld_before: int = int(ld_before_v.get("treasury_cp", 0))
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	var dice := FakeDice.new()
	dice.fixed_d20 = 7  # loan
	var result := FavorsDutiesResolver.roll_monthly(assn, 100, dice)
	check(String(result["result_key"]) == "loan", "loan rolled")
	check(int(result["cp_value"]) == 20000, "loan cp_value = 20000 (1gp/family × 200 families × 100cp/gp); got %d" % int(result["cp_value"]))
	# Migration 116 + 111: treasury_cp delta = cp_value = gp_value × 100 = 20000.
	var ld_after_v: Dictionary = CampaignRepository.get_domain(_liege_domain_id)
	var ld_after: int = int(ld_after_v.get("treasury_cp", 0))
	check(ld_after == ld_before + 20000, "lord treasury +20000 cp; before=%d after=%d" % [ld_before, ld_after])


func test_roll_monthly_revoke_clears_most_recent() -> void:
	# Pre-seed a duty.
	var v := _make_character("RevokeVassal")
	var vd := _make_domain("RevokeVRealm", v, 100, 0, 500)
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	var oid := VassalObligationsRepository.create({
		"vassal_assignment_id": assn, "kind": "duty", "type": "scutage",
		"magnitude": 100, "issued_calendar_day": 50,
	})
	var dice := FakeDice.new()
	dice.fixed_d20 = 10  # revoke
	dice.fixed_d6 = 4    # 2-6 = revoke duty
	var result := FavorsDutiesResolver.roll_monthly(assn, 100, dice)
	check(String(result["result_key"]) == "revoke", "revoke rolled")
	check(String(result["type"]) == "revoke_duty", "revoked a duty (sub-roll 4); got %s" % result["type"])
	var refreshed := VassalObligationsRepository.get_obligation(oid)
	check(String(refreshed.get("status", "")) == "revoked", "scutage status = revoked")


func test_safe_duty_threshold_henchman_one_free() -> void:
	# Henchman with 0 favors: safe_total = 1 (free duty); first duty no penalty.
	var v := _make_character("SafeHenchman")
	var vd := _make_domain("SafeHVR", v, 100, 0, 500)
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	var dice := FakeDice.new()
	dice.fixed_d20 = 2  # scutage
	var result := FavorsDutiesResolver.roll_monthly(assn, 100, dice)
	check(int(result["loyalty_penalty_applied"]) == 0, "first duty no penalty for henchman; got %d" % int(result["loyalty_penalty_applied"]))


func test_safe_duty_threshold_non_henchman_no_free() -> void:
	# Non-henchman with 0 favors: safe_total = 0; first duty triggers penalty.
	var v := _make_character("NonHenchVassal")
	var vd := _make_domain("NonHVR", v, 100, 0, 500)
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v, "vassal_domain_id": vd,
		"assigned_calendar_day": 1,
		"is_henchman_vassal": false,
		"base_loyalty_modifier": 4,  # high so loyalty roll passes
	})
	var dice := FakeDice.new()
	dice.fixed_d20 = 2  # scutage
	var result := FavorsDutiesResolver.roll_monthly(assn, 100, dice)
	check(int(result["loyalty_penalty_applied"]) == -1,
		"first duty triggers -1 penalty for non-henchman; got %d" % int(result["loyalty_penalty_applied"]))


func test_cumulative_loyalty_penalty_on_excess_duties() -> void:
	# Pre-seed 2 active duties for a henchman with 0 favors. Safe_total = 1;
	# a third duty would put them at 3 active — excess_index = 2 → penalty -2.
	var v := _make_character("StackedDuties")
	var vd := _make_domain("StackedVR", v, 100, 0, 500)
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
		"base_loyalty_modifier": 6,  # high so loyalty passes
	})
	VassalObligationsRepository.create({"vassal_assignment_id": assn, "kind": "duty", "type": "scutage", "issued_calendar_day": 50})
	VassalObligationsRepository.create({"vassal_assignment_id": assn, "kind": "duty", "type": "call_to_council", "issued_calendar_day": 51})
	var dice := FakeDice.new()
	dice.fixed_d20 = 7  # loan (third duty)
	var result := FavorsDutiesResolver.roll_monthly(assn, 100, dice)
	# active before = 2; safe_total = 1; prospective = 3; excess = 2; penalty = -2.
	check(int(result["loyalty_penalty_applied"]) == -2,
		"third stacked duty triggers -2 penalty; got %d" % int(result["loyalty_penalty_applied"]))
