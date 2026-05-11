extends "res://tests/test_suite_base.gd"

## Phase 8 polish tests:
##   Item 1: Office bonus propagation (+1 to vassal's loyalty roll if liege
##           holds active office)
##   Item 2: Loan repayment monthly chance per CHA% (RAW L365)
##   Item 3: Construction auto-expenditure (RAW L361)
##   Item 4: favors_duties_card UI smoke test

const FavorsDutiesCardScript := preload("res://scenes/ui/notebook/domain/favors_duties_card.gd")

class FakeDice:
	extends RefCounted
	var fixed_d20: int = 0
	var fixed_d6: int = 0
	var fixed_d100: int = 50
	var fixed_2d6: int = 7
	func roll(count: int, sides: int) -> int:
		if count == 1 and sides == 20:
			return fixed_d20
		if count == 1 and sides == 6:
			return fixed_d6
		if count == 1 and sides == 100:
			return fixed_d100
		if count == 2 and sides == 6:
			return fixed_2d6
		return 1

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_office_bonus_when_liege_has_office_favor()
	test_office_bonus_zero_when_no_office()
	test_office_bonus_zero_for_unaligned_character()
	test_loan_repayment_succeeds_when_roll_under_cha()
	test_loan_repayment_fails_when_roll_over_cha()
	test_construction_expenditure_increments_running_total()
	test_construction_expenditure_completes_at_target()
	test_favors_duties_card_renders_active_obligations()
	test_favors_duties_card_renders_empty_state()
	if not has_failures():
		print("Phase8Polish: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Phase8Polish", "World")


func _make_character(name: String, cha: int = 14) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, ?, 60, 60)
	""", [id, _campaign_id, name, cha])
	return id


func _make_domain(name: String, owner: String, peasant_families: int, treasury_gp: int) -> String:
	var id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": name, "owner_character_id": owner,
	})
	CampaignRepository.update_domain_monthly_state(id, {
		"peasant_families": peasant_families,
		"urban_families": 0,
		"treasury_gp": treasury_gp,
	})
	return id


# ---------------------------------------------------------------------------
# Item 1: Office bonus propagation
# ---------------------------------------------------------------------------

func test_office_bonus_when_liege_has_office_favor() -> void:
	# Setup: Upper-Liege U → Liege L → Vassal V chain.
	# Grant L an "office" favor (from U). Then V's loyalty roll should get +1.
	var u := _make_character("UpperLiege")
	var l := _make_character("Liege")
	var v := _make_character("Vassal")
	# Assignment U→L (so we can attach the office favor to it)
	var u_l_assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": u,
		"vassal_character_id": l, "assigned_calendar_day": 1,
		"is_henchman_vassal": true,
	})
	# Assignment L→V
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": l,
		"vassal_character_id": v, "assigned_calendar_day": 1,
		"is_henchman_vassal": true,
	})
	# Grant L an active "office" favor.
	VassalObligationsRepository.create({
		"vassal_assignment_id": u_l_assn,
		"kind": "favor", "type": "office",
		"issued_calendar_day": 50,
	})
	# V's loyalty roll should get +1 from the office bonus.
	var bonus := FavorsDutiesResolver.office_bonus_for_vassal_roll(v)
	check(bonus == 1, "V's loyalty roll gets +1 because L has active office favor; got %d" % bonus)


func test_office_bonus_zero_when_no_office() -> void:
	# Setup: L → V chain, no office favor anywhere.
	var l := _make_character("LiegeNoOffice")
	var v := _make_character("VassalNoOffice")
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": l,
		"vassal_character_id": v, "assigned_calendar_day": 1,
		"is_henchman_vassal": true,
	})
	var bonus := FavorsDutiesResolver.office_bonus_for_vassal_roll(v)
	check(bonus == 0, "no office anywhere → 0 bonus; got %d" % bonus)


func test_office_bonus_zero_for_unaligned_character() -> void:
	# Character with no vassal assignment as vassal → no bonus to apply.
	var unaligned := _make_character("Unaligned")
	var bonus := FavorsDutiesResolver.office_bonus_for_vassal_roll(unaligned)
	check(bonus == 0, "unaligned character → 0 bonus; got %d" % bonus)


# ---------------------------------------------------------------------------
# Item 2: Loan repayment monthly chance
# ---------------------------------------------------------------------------

func test_loan_repayment_succeeds_when_roll_under_cha() -> void:
	var lord := _make_character("LoanLord", 18)  # CHA 18 → 18% chance
	var vassal := _make_character("LoanVassal")
	var lord_d := _make_domain("LoanLordDom", lord, 100, 1000)
	var vassal_d := _make_domain("LoanVassalDom", vassal, 100, 1000)
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": lord,
		"vassal_character_id": vassal, "vassal_domain_id": vassal_d,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	# Pre-seed an active loan owed to lord (gp_value = 100).
	var loan_id := VassalObligationsRepository.create({
		"vassal_assignment_id": assn,
		"kind": "duty", "type": "loan",
		"gp_value": 100, "issued_calendar_day": 50,
	})
	# Loaded dice: roll 10 ≤ CHA 18 → repaid.
	var dice := FakeDice.new()
	dice.fixed_d100 = 10
	var lord_before: int = int(CampaignRepository.get_domain(lord_d).get("treasury_gp", 0))
	var vassal_before: int = int(CampaignRepository.get_domain(vassal_d).get("treasury_gp", 0))
	var results: Array = FavorsDutiesResolver.roll_monthly_loan_repayments(assn, 100, dice)
	check(results.size() == 1, "1 loan processed; got %d" % results.size())
	check(bool(results[0]["repaid"]), "loan repaid (roll 10 ≤ CHA 18)")
	# Lord paid vassal back 100 gp.
	var lord_after: int = int(CampaignRepository.get_domain(lord_d).get("treasury_gp", 0))
	var vassal_after: int = int(CampaignRepository.get_domain(vassal_d).get("treasury_gp", 0))
	check(lord_after == lord_before - 100, "lord -100; before=%d after=%d" % [lord_before, lord_after])
	check(vassal_after == vassal_before + 100, "vassal +100; before=%d after=%d" % [vassal_before, vassal_after])
	# Loan obligation status is completed.
	var refreshed := VassalObligationsRepository.get_obligation(loan_id)
	check(String(refreshed.get("status", "")) == "completed", "loan status completed")


func test_loan_repayment_fails_when_roll_over_cha() -> void:
	var lord := _make_character("LoanLord2", 12)  # CHA 12
	var vassal := _make_character("LoanVassal2")
	var vd := _make_domain("LV2D", vassal, 100, 500)
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": lord,
		"vassal_character_id": vassal, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	var loan_id := VassalObligationsRepository.create({
		"vassal_assignment_id": assn,
		"kind": "duty", "type": "loan",
		"gp_value": 100, "issued_calendar_day": 50,
	})
	var dice := FakeDice.new()
	dice.fixed_d100 = 50  # 50 > 12 → not repaid
	var results: Array = FavorsDutiesResolver.roll_monthly_loan_repayments(assn, 100, dice)
	check(not bool(results[0]["repaid"]), "loan NOT repaid (roll 50 > CHA 12)")
	var refreshed := VassalObligationsRepository.get_obligation(loan_id)
	check(String(refreshed.get("status", "")) == "active", "loan status still active")


# ---------------------------------------------------------------------------
# Item 3: Construction auto-expenditure
# ---------------------------------------------------------------------------

func test_construction_expenditure_increments_running_total() -> void:
	var lord := _make_character("ConstructLord")
	var vassal := _make_character("ConstructVassal")
	var vd := _make_domain("CVD", vassal, 1000, 10000)  # 1000 families → tribute ~1135gp
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": lord,
		"vassal_character_id": vassal, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	# Construction obligation with target 50000 gp (large enough not to complete in one month)
	var ob_id := VassalObligationsRepository.create({
		"vassal_assignment_id": assn,
		"kind": "duty", "type": "construction",
		"magnitude": 50000, "gp_value": 0, "issued_calendar_day": 50,
	})
	var results: Array = FavorsDutiesResolver.roll_monthly_construction_expenditure(assn, 100)
	check(results.size() == 1, "1 construction processed")
	var monthly: int = int(results[0]["monthly_expenditure"])
	check(monthly > 0, "monthly expenditure > 0; got %d" % monthly)
	check(not bool(results[0]["completed"]), "not yet completed (only first month)")
	# Verify running total persisted.
	var refreshed := VassalObligationsRepository.get_obligation(ob_id)
	check(int(refreshed.get("gp_value", 0)) == monthly, "running gp_value = monthly_expenditure")


func test_construction_expenditure_completes_at_target() -> void:
	var lord := _make_character("ConstructLord2")
	var vassal := _make_character("ConstructVassal2")
	var vd := _make_domain("CVD2", vassal, 1000, 100000)
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": lord,
		"vassal_character_id": vassal, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	# Construction with a tiny target — first month's expenditure exceeds it.
	var ob_id := VassalObligationsRepository.create({
		"vassal_assignment_id": assn,
		"kind": "duty", "type": "construction",
		"magnitude": 100, "gp_value": 0, "issued_calendar_day": 50,
	})
	var results: Array = FavorsDutiesResolver.roll_monthly_construction_expenditure(assn, 100)
	check(bool(results[0]["completed"]), "construction completes when expended >= target")
	var refreshed := VassalObligationsRepository.get_obligation(ob_id)
	check(String(refreshed.get("status", "")) == "completed", "obligation status completed")


# ---------------------------------------------------------------------------
# Item 4: favors_duties_card UI smoke test
# ---------------------------------------------------------------------------

func test_favors_duties_card_renders_active_obligations() -> void:
	var lord := _make_character("CardLord")
	var vassal := _make_character("CardVassal")
	var vd := _make_domain("CardVD", vassal, 100, 500)
	var assn_id := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": lord,
		"vassal_character_id": vassal, "vassal_domain_id": vd,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})
	VassalObligationsRepository.create({
		"vassal_assignment_id": assn_id,
		"kind": "duty", "type": "scutage",
		"magnitude": 100, "issued_calendar_day": 50,
	})
	VassalObligationsRepository.create({
		"vassal_assignment_id": assn_id,
		"kind": "favor", "type": "office",
		"issued_calendar_day": 51,
	})
	var assn := VassalRepository.get_assignment(assn_id)
	var card = FavorsDutiesCardScript.new()
	add_child(card)
	card.display(assn)
	# Header should mention vassal name.
	check(card._header_label.text.contains("CardVassal"), "header includes vassal name; got %s" % card._header_label.text)
	# Active duties has 1 row (scutage); active favors has 1 row (office).
	check(card._duties_list.get_child_count() == 1, "1 duty row; got %d" % card._duties_list.get_child_count())
	check(card._favors_list.get_child_count() == 1, "1 favor row; got %d" % card._favors_list.get_child_count())
	# History has both rows.
	check(card._history_list.get_child_count() == 2, "2 history rows; got %d" % card._history_list.get_child_count())
	card.queue_free()


func test_favors_duties_card_renders_empty_state() -> void:
	var lord := _make_character("EmptyLord")
	var vassal := _make_character("EmptyVassal")
	var assn_id := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": lord,
		"vassal_character_id": vassal, "assigned_calendar_day": 1,
		"is_henchman_vassal": true,
	})
	var assn := VassalRepository.get_assignment(assn_id)
	var card = FavorsDutiesCardScript.new()
	add_child(card)
	card.display(assn)
	# Each empty section shows "(none)" or "(no obligations issued yet)".
	check(card._duties_list.get_child_count() == 1, "1 (none) row in duties")
	check(card._favors_list.get_child_count() == 1, "1 (none) row in favors")
	check(card._history_list.get_child_count() == 1, "1 (no obligations) row in history")
	card.queue_free()
