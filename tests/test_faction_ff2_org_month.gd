extends "res://tests/test_suite_base.gd"

## Faction FF-2.2 (gdd-faction-framework.md §6.5/§6.6) — the org month: the
## ¼-wages ledger (banker's rounding), syndicate/merchant passthrough (no
## double-resolve), the affordability gate, the negative-treasury RAW
## consequences, the FF-4 line (undermine_rival/declare_stance inert), and the
## faction_action_taken emit through process_campaign_month. NOT executed by this
## build session — registered for the central suite.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_quarter_wages_bankers_rounding()
	test_syndicate_passthrough_no_accrual()
	test_unpaid_faithful_contribute_zero()
	test_affordability_gate_blocks_unaffordable()
	test_broke_org_still_scores_free_actions()
	test_ff4_stubs_never_selected()
	test_hold_is_a_candidate_floor()
	test_negative_treasury_departures_and_survive()
	test_process_campaign_month_emits_action()
	if not has_failures():
		print("FactionFF2OrgMonth: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF2 OrgMonth Test", "World")


# ---------------------------------------------------------------------------

func test_quarter_wages_bankers_rounding() -> void:
	# 40 abstract members priced through the RAW pyramid; net = ¼ Σ wages.
	var faction := {"id": "", "faction_type": "mage_guild",
		"member_count_abstract": 40, "treasury_gp": 0}
	var expected: int = MathUtils.bankers_round(0.25 * OrgTypeCatalog.abstract_wage_sum_gp(40))
	var res: Dictionary = FactionLedgerResolver.resolve_month(faction, 0)
	check(not bool(res.get("passthrough", true)), "mage_guild uses the ¼-wages regime")
	check(int(res.get("quarter_net_gp", -1)) == expected,
		"¼-wages net (banker's rounding) = %d, got %d" % [expected, int(res.get("quarter_net_gp", -1))])
	check(int(res.get("treasury_after", -1)) == expected, "treasury accrues the net")


func test_syndicate_passthrough_no_accrual() -> void:
	for t in ["syndicate", "merchant_guild"]:
		var faction := {"id": "", "faction_type": t,
			"member_count_abstract": 40, "treasury_gp": 500}
		var res: Dictionary = FactionLedgerResolver.resolve_month(faction, 0)
		check(bool(res.get("passthrough", false)), "%s income is passthrough" % t)
		check(int(res.get("quarter_net_gp", -1)) == 0, "%s accrues nothing here" % t)
		check(int(res.get("treasury_after", -1)) == 500, "%s treasury unchanged" % t)


func test_unpaid_faithful_contribute_zero() -> void:
	# holy_order abstract members are the unpaid faithful → 0 wage sum, 0 net.
	var faction := {"id": "", "faction_type": "holy_order",
		"member_count_abstract": 50, "treasury_gp": 0}
	var res: Dictionary = FactionLedgerResolver.resolve_month(faction, 0)
	check(int(res.get("quarter_net_gp", -1)) == 0,
		"unpaid faithful contribute 0 to the ¼-wages sum")


func test_affordability_gate_blocks_unaffordable() -> void:
	# A temple with an empty treasury and no expected net cannot proselytize
	# (cost 1000) — the affordability gate drops it from the candidate set.
	var faction := {"id": "f_gate", "faction_type": "temple",
		"member_count_abstract": 10, "treasury_gp": 0,
		"goal_primary": "grow_membership", "goal_secondary": "gain_influence",
		"volatility": 1.0}
	var cands: Array = FactionAI._score_candidates(faction, false, 0, 1)
	check(not _has_action(cands, "proselytize"),
		"unaffordable proselytize is gated out")
	check(_has_action(cands, "hold"), "hold remains as the anti-thrash floor")


func test_ff4_stubs_never_selected() -> void:
	var faction := {"id": "f_ff4", "faction_type": "syndicate",
		"member_count_abstract": 20, "treasury_gp": 5000,
		"goal_primary": "suppress_rival", "goal_secondary": "accumulate_wealth",
		"volatility": 2.0}
	var cands: Array = FactionAI._score_candidates(faction, false, 5000, 1)
	check(not _has_action(cands, "undermine_rival"), "undermine_rival is an inert FF-4 stub")
	check(not _has_action(cands, "declare_stance"), "declare_stance is an inert FF-4 stub")


func test_hold_is_a_candidate_floor() -> void:
	var faction := {"id": "f_hold", "faction_type": "mage_guild",
		"member_count_abstract": 5, "treasury_gp": 10,
		"goal_primary": "gain_influence", "volatility": 1.0}
	var cands: Array = FactionAI._score_candidates(faction, false, 10, 1)
	check(_has_action(cands, "hold"), "hold is always a candidate")


func test_broke_org_still_scores_free_actions() -> void:
	# A negative-treasury org must still get its cost-0 candidates (hold /
	# raise_funds / survival moves) — the affordability gate must NOT filter free
	# actions when broke (previously `0 > treasury+income` dropped even hold).
	var faction := {"id": "f_broke_gate", "faction_type": "temple",
		"member_count_abstract": 10, "treasury_gp": -100,
		"goal_primary": "survive", "goal_secondary": "", "volatility": 1.0}
	var cands: Array = FactionAI._score_candidates(faction, true, -100, 1)
	check(not cands.is_empty(), "a broke org still has candidates")
	check(_has_action(cands, "hold"), "hold survives the gate at negative treasury")
	check(_has_action(cands, "raise_funds"), "cost-0 raise_funds survives when broke")
	check(not _has_action(cands, "proselytize"),
		"an unaffordable costed action (proselytize 1000) is still filtered")
	check(not _has_action(cands, "court_patron"),
		"court_patron (cost 100) is filtered at -100 gp")


func test_negative_treasury_departures_and_survive() -> void:
	var fid := "f_broke"
	var f := FactionData.new()
	f.id = fid
	f.campaign_id = _campaign_id
	f.name = "Broke Guild"
	f.faction_type = "mage_guild"
	f.scope = "organization"
	f.member_count_abstract = 30
	f.treasury_gp = -1500
	f.goal_primary = "accumulate_wealth"
	CampaignRepository.create_faction(f)
	var faction: Dictionary = CampaignRepository.get_faction(fid)
	var res: Dictionary = FactionAI._apply_negative_treasury(_campaign_id, faction, 0)
	check(int(res.get("departed", 0)) > 0, "unpaid members depart 1d10/1000gp")
	var after: Dictionary = CampaignRepository.get_faction(fid)
	check(int(after.get("member_count_abstract", 99)) < 30, "roster shrank from departures")
	# The month's forced-survive posture is REPORTED, but the authored goal is NOT
	# permanently overwritten (survive is condition-derived from treasury each month;
	# a single deficit must not erase the org's identity — no restoration path exists).
	check(String(res.get("goal", "")) == "survive", "the month reports a forced-survive posture")
	check(String(after.get("goal_primary", "")) == "accumulate_wealth",
		"the authored goal_primary is PRESERVED, not destroyed by one deficit month")


func test_process_campaign_month_emits_action() -> void:
	# A solvent temple seated in an active settlement takes a turn and emits.
	var did := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Org Month Domain"})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET peasant_families = ?, religion = ? WHERE id = ?",
		[500, "tulras", did])
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = "Active Temple"
	f.faction_type = "temple"
	f.scope = "organization"
	f.religion_id = "tulras"
	f.home_domain_id = did
	f.seat_settlement_id = "sett_active"
	f.member_count_abstract = 40
	f.treasury_gp = 3000
	f.goal_primary = "grow_membership"
	f.goal_secondary = "gain_influence"
	f.status = "active"
	var fid := CampaignRepository.create_faction(f)
	# Seed tithe shares so the temple has a share of the pool.
	TitheApportionment.seed_defaults(_campaign_id, did, "tulras", 0)

	var captured := {"fired": false, "action": "", "faction": ""}
	var cb := func(faction_id: String, action_id: String, _outcome: Dictionary):
		captured["fired"] = true
		captured["action"] = action_id
		captured["faction"] = faction_id
	EventBus.faction_action_taken.connect(cb)
	var reports: Array = FactionAI.process_campaign_month(_campaign_id, 5, ["sett_active"])
	EventBus.faction_action_taken.disconnect(cb)

	check(reports.size() >= 1, "the active temple took a turn")
	check(bool(captured["fired"]), "faction_action_taken fired")
	check(String(captured["faction"]) == fid, "the emitting faction is the active temple")
	check(String(captured["action"]) not in ["undermine_rival", "declare_stance"],
		"the FF-4 stubs are never the chosen action")


func _has_action(cands: Array, action_id: String) -> bool:
	for c in cands:
		if String((c as Dictionary).get("action_id", "")) == action_id:
			return true
	return false
