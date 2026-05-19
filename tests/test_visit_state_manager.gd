extends "res://tests/test_suite_base.gd"

## Unit tests for VisitStateManager — Phase 10B.2 Wave 1.
##
## Per generation/gdd-phase-10b-2-trade-block.md §9 + §18.1.
##
## Notes:
##   * Shipping-offer roll + clear are stubbed in Wave 1 (Wave 4 wires them);
##     these tests don't assert on offer state.
##   * Tests use direct DB inserts for parties/settlements to keep fixtures
##     compact. trade_fixtures.gd helpers can be used elsewhere; here we
##     stay close to the raw substrate for clarity.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_on_party_entered_inserts_row()
	test_on_party_entered_idempotent_on_reentry()
	test_on_party_entered_emits_signal()
	test_has_paid_entry_toll_default_false()
	test_mark_entry_toll_paid_flips_flag()
	test_mark_entry_toll_no_op_without_row()
	test_active_character_for_visit_returns_seeded_value()
	test_on_party_departed_computes_stabling_for_wagon()
	test_on_party_departed_zero_when_no_visit_row()
	test_on_party_departed_emits_signal_with_days_at_settlement()
	test_on_party_departed_clears_visit_row()
	test_on_party_departed_domain_owner_exempt_zeros_stabling()
	test_visit_fees_unpaid_emits_on_shortfall()
	test_days_at_settlement_floors_at_one()

	# Phase 10B.2 follow-up (2026-05-14) — loose-mount stabling enumeration.
	test_loose_riding_horse_charges_stabling()
	test_loose_warhorse_charges_premium_rate()
	test_loose_mule_charges_stabling()
	test_hitched_creature_not_double_counted_with_vehicle()
	test_non_stabled_species_dont_charge()
	test_dead_creatures_excluded()
	test_other_party_creatures_excluded()
	test_mixed_loose_and_hitched_correctly_partitioned()

	if not has_failures():
		print("VisitStateManager: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("VisitStateManagerTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "VSMMap"])


func _next_id(tag: String = "vsm") -> String:
	_suffix += 1
	return "%s_%d_%d" % [tag, Time.get_ticks_msec(), _suffix]


func _make_character() -> String:
	var cid: String = _next_id("char")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, ?, 'pc')
	""", [cid, _campaign_id, "PC_" + cid])
	return cid


func _make_party_with_pc(starting_wealth_cp: int = 1_000_000) -> Dictionary:
	var pc_id: String = _make_character()
	var party_id: String = _next_id("party")
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, _campaign_id, "Party_" + party_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[party_id, pc_id])
	if starting_wealth_cp > 0:
		CampaignRepository.add_coins_cp(pc_id, starting_wealth_cp)
	return {"party_id": party_id, "pc_id": pc_id}


func _make_settlement(market_class: int = 3, parent_domain_id: Variant = null) -> String:
	var sid: String = _next_id("set")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class, parent_domain_id)
		VALUES (?, ?, ?, ?, 0, ?, ?, ?)
	""", [sid, _campaign_id, _map_id, _suffix, "Settlement_" + sid, market_class, parent_domain_id])
	return sid


func _attach_wagon(party_id: String) -> String:
	var vid: String = _next_id("wagon")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'TestWagon', '[]')
	""", [vid, _campaign_id, party_id])
	return vid


# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

func test_on_party_entered_inserts_row() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 10)
	var row: Dictionary = VisitStateManager.get_visit_row(p["party_id"], s)
	check(not row.is_empty(), "party_visit_state row exists after entry")
	check(int(row.get("entry_calendar_day", 0)) == 10,
		"entry_calendar_day persisted = 10")
	check(str(row.get("active_character_at_entry", "")) == p["pc_id"],
		"active_character_at_entry persisted")
	check(int(row.get("entry_toll_paid_flag", 1)) == 0,
		"entry_toll_paid_flag starts at 0")


func test_on_party_entered_idempotent_on_reentry() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 10)
	# Re-enter with a different calendar day + character — should be no-op.
	var other_pc: String = _make_character()
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, other_pc, 25)
	var row: Dictionary = VisitStateManager.get_visit_row(p["party_id"], s)
	check(int(row.get("entry_calendar_day", -1)) == 10,
		"entry_calendar_day preserves first entry value (10), got %d" % int(row.get("entry_calendar_day", -1)))
	check(str(row.get("active_character_at_entry", "")) == p["pc_id"],
		"active_character_at_entry preserved across re-entry")


func test_on_party_entered_emits_signal() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	var captured := {"emitted": false, "party": "", "set": "", "day": 0}
	var cb: Callable = func(party_id: String, set_id: String, day: int) -> void:
		captured["emitted"] = true
		captured["party"] = party_id
		captured["set"] = set_id
		captured["day"] = day
	EventBus.party_entered_settlement.connect(cb)
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 42)
	EventBus.party_entered_settlement.disconnect(cb)
	check(bool(captured["emitted"]), "party_entered_settlement emits on entry")
	check(int(captured["day"]) == 42, "signal day param = 42")
	check(str(captured["party"]) == p["party_id"] and str(captured["set"]) == s,
		"signal party + settlement match")


# ---------------------------------------------------------------------------
# Toll first-fire bookkeeping
# ---------------------------------------------------------------------------

func test_has_paid_entry_toll_default_false() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	check(not VisitStateManager.has_paid_entry_toll(p["party_id"], s),
		"no visit row → has_paid_entry_toll false")
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 10)
	check(not VisitStateManager.has_paid_entry_toll(p["party_id"], s),
		"freshly entered visit → toll not yet paid")


func test_mark_entry_toll_paid_flips_flag() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 10)
	VisitStateManager.mark_entry_toll_paid(p["party_id"], s, 700)
	check(VisitStateManager.has_paid_entry_toll(p["party_id"], s),
		"has_paid_entry_toll true after mark")
	var row: Dictionary = VisitStateManager.get_visit_row(p["party_id"], s)
	check(int(row.get("entry_toll_paid_cp", -1)) == 700,
		"entry_toll_paid_cp persisted = 700 (= 7 gp)")


func test_mark_entry_toll_no_op_without_row() -> void:
	# Calling mark_entry_toll_paid before on_party_entered should not insert
	# an orphan row (the UPDATE simply finds no match).
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	VisitStateManager.mark_entry_toll_paid(p["party_id"], s, 99)
	check(VisitStateManager.get_visit_row(p["party_id"], s).is_empty(),
		"mark before entry leaves no row")


func test_active_character_for_visit_returns_seeded_value() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	check(VisitStateManager.active_character_for_visit(p["party_id"], s).is_empty(),
		"active_character_for_visit returns '' with no row")
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	check(VisitStateManager.active_character_for_visit(p["party_id"], s) == p["pc_id"],
		"active_character_for_visit returns seeded pc_id")


# ---------------------------------------------------------------------------
# Departure
# ---------------------------------------------------------------------------

func test_on_party_departed_computes_stabling_for_wagon() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	var _wagon_id: String = _attach_wagon(p["party_id"])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 10)
	# Stay 3 days. Wagon at 200 cp/day × 3 = 600 cp (= 6 gp).
	var result: Dictionary = VisitStateManager.on_party_departed_settlement(p["party_id"], s, 13)
	check(int(result.get("stabling_cp", 0)) == 600,
		"wagon × 3 days = 600 cp stabling, got %d" % int(result.get("stabling_cp", 0)))
	check(int(result.get("days_at_settlement", 0)) == 3,
		"days_at_settlement = 3 (entry 10, exit 13)")
	check(int(result.get("moorage_cp", -1)) == 0, "no ships → moorage_cp 0")
	check(int(result.get("unpaid_cp", -1)) == 0, "PC has wallet to cover 600 cp")


func test_on_party_departed_zero_when_no_visit_row() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	var result: Dictionary = VisitStateManager.on_party_departed_settlement(p["party_id"], s, 10)
	check(int(result.get("stabling_cp", -1)) == 0, "no visit row → 0 stabling")
	check(int(result.get("days_at_settlement", -1)) == 0, "no visit row → 0 days")


func test_on_party_departed_emits_signal_with_days_at_settlement() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	_attach_wagon(p["party_id"])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var captured := {"emitted": false, "stabling": -1, "days": -1}
	var cb: Callable = func(_party_id: String, _set_id: String, stabling: int, _moorage: int, days: int) -> void:
		captured["emitted"] = true
		captured["stabling"] = stabling
		captured["days"] = days
	EventBus.party_departed_settlement.connect(cb)
	VisitStateManager.on_party_departed_settlement(p["party_id"], s, 5)
	EventBus.party_departed_settlement.disconnect(cb)
	check(bool(captured["emitted"]), "party_departed_settlement emits")
	check(int(captured["days"]) == 5, "signal days_at_settlement = 5")
	check(int(captured["stabling"]) == 1000,
		"signal stabling_cp = 200 cp/day × 5 days = 1000 cp (= 10 gp)")


func test_on_party_departed_clears_visit_row() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	check(VisitStateManager.has_active_visit(p["party_id"], s),
		"visit active before departure")
	VisitStateManager.on_party_departed_settlement(p["party_id"], s, 1)
	check(not VisitStateManager.has_active_visit(p["party_id"], s),
		"visit row cleared on departure")


func test_on_party_departed_domain_owner_exempt_zeros_stabling() -> void:
	var p: Dictionary = _make_party_with_pc()
	# Make the PC the owner of the settlement's parent domain.
	var domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "OwnedDomain",
		"owner_character_id": p["pc_id"],
	})
	var s: String = _make_settlement(3, domain_id)
	_attach_wagon(p["party_id"])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var result: Dictionary = VisitStateManager.on_party_departed_settlement(p["party_id"], s, 3)
	check(int(result.get("stabling_cp", -1)) == 0,
		"PC owns parent domain → stabling exempt (0 cp)")


func test_visit_fees_unpaid_emits_on_shortfall() -> void:
	# Party with NO wealth — wagon stabling will exceed wallet.
	var p: Dictionary = _make_party_with_pc(0)
	var s: String = _make_settlement()
	_attach_wagon(p["party_id"])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var captured := {"emitted": false, "owed": -1}
	var cb: Callable = func(_party_id: String, _set_id: String, owed: int) -> void:
		captured["emitted"] = true
		captured["owed"] = owed
	EventBus.visit_fees_unpaid.connect(cb)
	var result: Dictionary = VisitStateManager.on_party_departed_settlement(p["party_id"], s, 3)
	EventBus.visit_fees_unpaid.disconnect(cb)
	check(bool(captured["emitted"]), "visit_fees_unpaid emits on shortfall")
	check(int(captured["owed"]) == 600, "owed_cp = 200 × 3 = 600 cp (= 6 gp)")
	check(int(result.get("unpaid_cp", 0)) == 600, "result reports unpaid_cp = 600")


func test_days_at_settlement_floors_at_one() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	_attach_wagon(p["party_id"])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 100)
	# Same-day departure (current_day == entry_day): expect floor at 1 day.
	var result: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 100)
	check(int(result.get("days_at_settlement", -1)) == 1,
		"same-day entry/exit floors at 1 day, got %d" % int(result.get("days_at_settlement", -1)))
	check(int(result.get("stabling_cp", -1)) == 200,
		"1 day × 200 cp wagon stabling = 200 cp (= 2 gp)")


# ---------------------------------------------------------------------------
# Phase 10B.2 follow-up (2026-05-14) — loose-mount stabling enumeration.
# Covers the [NEEDS-LOOSE-MOUNT-STABLING-PASS] flag closed by Phase 10B.2
# Wave 6's follow-up pass. Enumerates loose trained_creatures (NOT hitched
# to any party vehicle) alongside the existing vehicle enumeration.
# ---------------------------------------------------------------------------

func _insert_trained_creature(
		party_id: String, species_id: String, role: String = "M"
) -> String:
	var cid: String = _next_id("creature")
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO trained_creatures
			(id, campaign_id, party_id, species_id, role, is_alive)
		VALUES (?, ?, ?, ?, ?, 1)
	""", [cid, _campaign_id, party_id, species_id, role])
	return cid


func _attach_wagon_with_hitched_ids(party_id: String, hitched_ids: Array) -> String:
	# Like _attach_wagon but with a configurable hitched_creatures JSON array
	# (matches the loose-mount filter format).
	var vid: String = _next_id("wagon")
	var hitched_json: String = JSON.stringify(hitched_ids)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles
			(id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, 'wagon', 'HitchedWagon', ?)
	""", [vid, _campaign_id, party_id, hitched_json])
	return vid


func test_loose_riding_horse_charges_stabling() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	# Non-war horse: 5 sp/night = 0.5 gp/day.
	_insert_trained_creature(p["party_id"], "horse_medium", "M")
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 3)
	# 1 riding horse × 50 cp/day × 3 days = 150 cp (= 1.5 gp; whole cp, no rounding).
	check(int(r.get("stabling_cp", -1)) == 150,
		"loose riding horse × 3 days = 150 cp stabling, got %d" % int(r.get("stabling_cp", -1)))


func test_loose_warhorse_charges_premium_rate() -> void:
	# Per RAW, war horses stable at 1 gp/night (twice the riding/draft rate).
	# horse_*_war species map to "warhorse" key, distinct from generic "horse".
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	_insert_trained_creature(p["party_id"], "horse_medium_war", "WM")
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 3)
	# 1 warhorse × 100 cp/day × 3 days = 300 cp (= 3 gp).
	check(int(r.get("stabling_cp", -1)) == 300,
		"loose warhorse × 3 days = 300 cp stabling (premium rate), got %d" % int(r.get("stabling_cp", -1)))


func test_loose_mule_charges_stabling() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	_insert_trained_creature(p["party_id"], "mule", "D")
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 5)
	# 1 mule × 20 cp/day × 5 days = 100 cp (= 1 gp).
	check(int(r.get("stabling_cp", -1)) == 100,
		"loose mule × 5 days = 100 cp stabling, got %d" % int(r.get("stabling_cp", -1)))


func test_hitched_creature_not_double_counted_with_vehicle() -> void:
	# A horse pulling a wagon: wagon's rate (2 gp/day) bundles the team.
	# The loose-mount path must EXCLUDE the hitched creature.
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	var hitched_horse: String = _insert_trained_creature(
		p["party_id"], "horse_heavy", "D")
	_attach_wagon_with_hitched_ids(p["party_id"], [hitched_horse])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 3)
	# Should be wagon only: 200 cp/day × 3 days = 600 cp (= 6 gp). NO horse rate added.
	check(int(r.get("stabling_cp", -1)) == 600,
		"hitched horse + wagon = 600 cp (wagon-only, no double-count), got %d" % int(r.get("stabling_cp", -1)))


func test_non_stabled_species_dont_charge() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	# Non-stabled species per the audit: hawks, dogs, sheep, goats, cows.
	_insert_trained_creature(p["party_id"], "dog_war", "G")
	_insert_trained_creature(p["party_id"], "hawk_ordinary", "H")
	_insert_trained_creature(p["party_id"], "goat", "L")
	_insert_trained_creature(p["party_id"], "sheep", "L")
	_insert_trained_creature(p["party_id"], "cow", "L")
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 5)
	check(int(r.get("stabling_cp", -1)) == 0,
		"non-stabled species (dogs/hawks/livestock) contribute 0 cp, got %d" % int(r.get("stabling_cp", -1)))


func test_dead_creatures_excluded() -> void:
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	# Alive mule + dead horse.
	_insert_trained_creature(p["party_id"], "mule", "D")
	var dead_horse: String = _insert_trained_creature(p["party_id"], "horse_medium", "M")
	CampaignRepository.db.query_with_bindings(
		"UPDATE trained_creatures SET is_alive = 0 WHERE id = ?", [dead_horse])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 5)
	# Only the alive mule × 5 days × 20 cp = 100 cp (= 1 gp).
	check(int(r.get("stabling_cp", -1)) == 100,
		"dead creature excluded; only alive mule charged = 100 cp, got %d" % int(r.get("stabling_cp", -1)))


func test_other_party_creatures_excluded() -> void:
	var p1: Dictionary = _make_party_with_pc()
	var p2: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	_insert_trained_creature(p1["party_id"], "mule", "D")
	_insert_trained_creature(p2["party_id"], "horse_medium", "M")  # other party's
	VisitStateManager.on_party_entered_settlement(p1["party_id"], s, p1["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p1["party_id"], s, 5)
	# Only party 1's mule × 5 × 20 cp = 100 cp. Party 2's horse not charged.
	check(int(r.get("stabling_cp", -1)) == 100,
		"other-party creature excluded; only party_1's mule charged = 100 cp, got %d" % int(r.get("stabling_cp", -1)))


func test_mixed_loose_and_hitched_correctly_partitioned() -> void:
	# Wagon hitched with 2 draft horses + 1 loose warhorse + 1 loose mule.
	# Expected charges:
	#   wagon (bundles hitched team): 2.0 gp/day
	#   1 loose warhorse: 1.0 gp/day (premium rate)
	#   1 loose mule: 0.2 gp/day
	# Total: 3.2 gp/day × 1 day = banker's-rounded 3 gp.
	var p: Dictionary = _make_party_with_pc()
	var s: String = _make_settlement()
	var hitched_h1: String = _insert_trained_creature(p["party_id"], "horse_heavy", "D")
	var hitched_h2: String = _insert_trained_creature(p["party_id"], "horse_heavy", "D")
	_insert_trained_creature(p["party_id"], "horse_medium_war", "WM")  # loose; warhorse rate
	_insert_trained_creature(p["party_id"], "mule", "D")  # loose
	_attach_wagon_with_hitched_ids(p["party_id"], [hitched_h1, hitched_h2])
	VisitStateManager.on_party_entered_settlement(p["party_id"], s, p["pc_id"], 0)
	var r: Dictionary = VisitStateManager.on_party_departed_settlement(
		p["party_id"], s, 1)
	# Exact cp arithmetic — no rounding (rates are whole cp/day per the
	# 2026-05-15 currency-precision rule):
	# wagon 200 + warhorse 100 + mule 20 = 320 cp × 1 day = 320 cp (= 3.2 gp).
	check(int(r.get("stabling_cp", -1)) == 320,
		"mixed loose + hitched (wagon 200 + warhorse 100 + mule 20 = 320 cp), got %d" % int(r.get("stabling_cp", -1)))
