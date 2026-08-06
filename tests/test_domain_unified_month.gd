extends "res://tests/test_suite_base.gd"
## D-12 Phase B — the RAW monthly math computed over the CHARACTER'S DOMAIN.
##
## Phase A built the union; this suite proves the monthly tick actually uses it.
## Four properties, each of which was an exploit or a live defect before:
##
##   * ONE morale roll per character, mirrored to every parcel. Rolling per
##     parcel gave a lord several independent chances at the drift bands.
##   * Personal authority (RAW's oversize mechanic, `acore_axioms`
##     §personal_authority L430-449) keys on his TOTAL income. Per parcel, a lord
##     who split a rich domain into three poor ones got three lookups in a mild
##     band — a morale BONUS for holding land in pieces.
##   * Tribute is charged ONCE. `_compute_tribute_out_for_vassal_domain` always
##     aggregated the whole realm, but ran once per liege-bearing parcel, so a
##     lord with two lieges owed his entire realm's tribute twice.
##   * Stronghold sufficiency is judged on the combined value against the
##     combined minimum, which is what RAW says and what makes non-contiguity
##     bite (§noncontiguous_domains L95-98).
##
## Every test that runs a tick gets its OWN campaign: `_handle_monthly_tick`
## resolves every domain in the campaign, so shared fixtures would cross-talk.

const CIVILIZED_MIN_CP := 1_500_000   # RAW 15,000 gp/hex
const WILDERNESS_MIN_CP := 3_200_000  # RAW 32,000 gp/hex


func run_all_tests() -> void:
	test_one_morale_roll_is_mirrored_to_every_parcel()
	test_personal_authority_uses_the_summed_income()
	test_a_single_parcel_ruler_is_unaffected()
	test_tribute_is_charged_once_per_character()
	test_sufficiency_is_judged_on_the_whole_holding()
	test_worst_classification_drives_the_morale_penalty()
	test_administering_any_parcel_lifts_the_whole_domain()
	test_garrison_ratio_is_taken_over_the_union()
	test_a_levy_is_diluted_by_the_whole_population()
	test_every_reader_gets_the_same_sufficiency_answer()

	if not has_failures():
		print("DomainUnifiedMonth: all tests passed (%d checks)." % test_count())


## Minimal SessionRunner stand-in — DomainHandlers only ever calls
## get_campaign_id() (its one other _runner use is has_method-guarded).
class FakeRunner:
	var campaign_id: String
	func _init(cid: String) -> void:
		campaign_id = cid
	func get_campaign_id() -> String:
		return campaign_id


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_campaign(tag: String) -> String:
	return CampaignRepository.create_campaign("D12B %s" % tag, "World")


func _make_ruler(camp: String, tag: String, opts: Dictionary = {}) -> String:
	return CampaignRepository.create_character({
		"campaign_id": camp,
		"name": "Lord %s" % tag,
		"character_type": "npc",
		"character_class": "fighter",
		"level": int(opts.get("level", 5)),
		"xp": 0,
		"xp_for_next_level": 999_999,
		"cha": 10,
		"alignment": "neutral",
		# RulerLodManager.sync lazily builds a disposition for any ruler it
		# promotes, and that needs a personality to read.
		"personality": NpcPersonality.new().to_json(),
	})


func _make_parcel(camp: String, tag: String, owner: String,
		opts: Dictionary = {}) -> String:
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": camp,
		"name": "Parcel %s" % tag,
		"owner_character_id": owner,
		"territory_type": String(opts.get("territory_type", "civilized")),
	})
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET peasant_families = ?, morale = ?, treasury_cp = ?,
			alignment = 'neutral' WHERE id = ?
	""", [
		int(opts.get("peasants", 100)), int(opts.get("morale", 0)),
		int(opts.get("treasury_cp", 100_000_000)), domain_id,
	])
	if int(opts.get("stronghold_cp", 0)) > 0:
		_give_stronghold(domain_id, owner, int(opts["stronghold_cp"]))
	return domain_id


func _give_stronghold(domain_id: String, owner: String, cp_value: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, domain_id, owner_character_id, cp_value, status)
		VALUES (?, ?, ?, ?, 'completed')
	""", [CampaignRepository.generate_id(), domain_id, owner, cp_value])


func _set_liege(domain_id: String, liege_domain_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = ? WHERE id = ?",
		[liege_domain_id, domain_id])


func _levy_militia(camp: String, owner: String, domain_id: String, count: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units (id, campaign_id, owner_character_id,
			assigned_domain_id, source_type, troop_type, count, status)
		VALUES (?, ?, ?, ?, 'militia', 'light_infantry', ?, 'active')
	""", [CampaignRepository.generate_id(), camp, owner, domain_id, count])


## Run the real monthly tick and return {domain_id: result}.
func _run_tick(camp: String) -> Dictionary:
	var handlers := DomainHandlers.new(FakeRunner.new(camp))
	var ev := ScheduledEvent.new()
	ev.fire_time = Timekeeping.get_total_rounds()
	ev.event_type = "domain_monthly_tick"
	ev.owner_id = "domain_global"
	var tick: Dictionary = handlers._handle_monthly_tick(ev)
	var out: Dictionary = {}
	for r in (tick.get("presentation", {}) as Dictionary).get("domain_results", []):
		out[String((r as Dictionary).get("domain_id", ""))] = r
	return out


## The ruler context the tick built, rebuilt here so a test can reproduce a
## `resolve_base_morale` call exactly.
func _ruler_context(camp: String, domain_id: String) -> Dictionary:
	var handlers := DomainHandlers.new(FakeRunner.new(camp))
	return handlers._build_ruler_context(CampaignRepository.get_domain(domain_id))


# ---------------------------------------------------------------------------
# One roll per character
# ---------------------------------------------------------------------------

func test_one_morale_roll_is_mirrored_to_every_parcel() -> void:
	var camp := _make_campaign("mirror")
	var cid := _make_ruler(camp, "mirror")
	# Deliberately different prior morale: the SEAT is the carrier, so the roll
	# must drift from the seat's prior and the other parcel must simply adopt it.
	var a := _make_parcel(camp, "a", cid,
		{"morale": 2, "stronghold_cp": 2 * CIVILIZED_MIN_CP})
	var b := _make_parcel(camp, "b", cid, {"morale": -2})
	var seat: String = a if a < b else b   # PersonalDomain orders parcels by id

	var res := _run_tick(camp)
	var ra: Dictionary = res.get(a, {})
	var rb: Dictionary = res.get(b, {})
	check(not ra.is_empty() and not rb.is_empty(), "both parcels resolved")

	var pd: Dictionary = ra.get("personal_domain", {})
	check(int(pd.get("parcel_count", 0)) == 2,
		"the tick saw a two-parcel personal domain")
	check(String(pd.get("seat_parcel_id", "")) == seat,
		"the seat is the lowest-id parcel")
	check(String(pd.get("morale_rolled_on_seat", "")) == seat,
		"and the roll was taken on it")

	check(int(ra.get("base_morale", 0)) == int(rb.get("base_morale", 1)),
		"both parcels report the SAME base morale")
	check(int(ra.get("current_morale", 0)) == int(rb.get("current_morale", 1)),
		"and the same current morale")
	check(String(ra.get("morale_tier", "")) == String(rb.get("morale_tier", "x")),
		"and the same tier")
	var roll_a: int = int((ra.get("morale_roll", {}) as Dictionary).get("roll_2d6", -1))
	var roll_b: int = int((rb.get("morale_roll", {}) as Dictionary).get("roll_2d6", -2))
	check(roll_a == roll_b and roll_a > 0,
		"ONE 2d6 was rolled, not one per parcel (got %d and %d)" % [roll_a, roll_b])

	var prior: int = int((ra.get("morale_roll", {}) as Dictionary).get(
		"prior_current_morale", 99))
	var seat_prior: int = 2 if seat == a else -2
	check(prior == seat_prior,
		"the roll drifted from the SEAT's prior morale (got %d, want %d)"
			% [prior, seat_prior])

	# And both rows persist the mirrored value, so every existing reader of
	# `domains.morale` keeps working.
	var stored_a: int = int(CampaignRepository.get_domain(a).get("morale", 99))
	var stored_b: int = int(CampaignRepository.get_domain(b).get("morale", -99))
	check(stored_a == stored_b,
		"the one result was written to every parcel row (%d vs %d)"
			% [stored_a, stored_b])
	check(stored_a == int(ra.get("current_morale", 99)),
		"and it is the value the tick reported")


# ---------------------------------------------------------------------------
# Personal authority — RAW's oversize mechanic
# ---------------------------------------------------------------------------

func test_personal_authority_uses_the_summed_income() -> void:
	var camp := _make_campaign("authority")
	# Level 5 is chosen so the two income bands the fixture straddles give
	# different modifiers: 100 families earn 60,000 cp (band 4 -> +1), the two
	# together earn 120,000 cp (band 5 -> 0).
	var cid := _make_ruler(camp, "authority", {"level": 5})
	# The union's minimum is 2 x the civilized per-hex minimum (no domain_hexes
	# rows, so PersonalDomain's aggregate fallback counts one hex per parcel).
	var a := _make_parcel(camp, "a", cid, {"stronghold_cp": 2 * CIVILIZED_MIN_CP})
	var b := _make_parcel(camp, "b", cid, {})

	var res := _run_tick(camp)
	var ra: Dictionary = res.get(a, {})
	var rb: Dictionary = res.get(b, {})
	var pd: Dictionary = ra.get("personal_domain", {})

	var rev_a: int = int(ra.get("revenue", 0))
	var rev_b: int = int(rb.get("revenue", 0))
	check(rev_a > 0 and rev_b > 0, "both parcels earned (the gate is open)")
	check(int(pd.get("union_revenue_cp", 0)) == rev_a + rev_b,
		"the authority lookup saw the SUM of his parcels (%d, want %d)"
			% [int(pd.get("union_revenue_cp", -1)), rev_a + rev_b])

	# Reproduce the resolver call both ways. Everything but the income is held
	# identical, so any difference is the oversize band and nothing else.
	var seat_id: String = String(pd.get("seat_parcel_id", ""))
	var seat_row: Dictionary = CampaignRepository.get_domain(seat_id)
	var ruler: Dictionary = _ruler_context(camp, seat_id)
	var sv: int = int(pd.get("stronghold_value_cp", 0))
	var sm: int = int(pd.get("stronghold_minimum_cp", 0))
	var union_base: int = DomainMoraleResolver.resolve_base_morale(
		seat_row, ruler, rev_a + rev_b, sv, sm, 0, 0, "civilized")
	var split_base: int = DomainMoraleResolver.resolve_base_morale(
		seat_row, ruler, rev_a, sv, sm, 0, 0, "civilized")
	check(int(ra.get("base_morale", 0)) == union_base,
		"base morale was computed on the union (got %d, want %d)"
			% [int(ra.get("base_morale", -99)), union_base])
	check(split_base > union_base,
		"and splitting the holding WOULD have been worth %d point(s) of morale — "
			% (split_base - union_base)
			+ "that is the exploit D-12 closes")


func test_a_single_parcel_ruler_is_unaffected() -> void:
	var camp := _make_campaign("solo")
	var cid := _make_ruler(camp, "solo", {"level": 5})
	var did := _make_parcel(camp, "solo", cid, {"stronghold_cp": CIVILIZED_MIN_CP})

	var res := _run_tick(camp)
	var r: Dictionary = res.get(did, {})
	var pd: Dictionary = r.get("personal_domain", {})
	check(int(pd.get("parcel_count", 0)) == 1, "one parcel")
	check(int(pd.get("union_revenue_cp", 0)) == int(r.get("revenue", -1)),
		"his union income IS his domain's income")
	check(String(pd.get("seat_parcel_id", "")) == did, "he is his own seat")

	var ruler: Dictionary = _ruler_context(camp, did)
	var expected: int = DomainMoraleResolver.resolve_base_morale(
		CampaignRepository.get_domain(did), ruler, int(r.get("revenue", 0)),
		int(pd.get("stronghold_value_cp", 0)), int(pd.get("stronghold_minimum_cp", 0)),
		0, 0, "civilized")
	check(int(r.get("base_morale", -99)) == expected,
		"D-12 is a no-op for a ruler who holds one parcel (got %d, want %d)"
			% [int(r.get("base_morale", -99)), expected])


# ---------------------------------------------------------------------------
# Tribute — the N-times defect
# ---------------------------------------------------------------------------

func test_tribute_is_charged_once_per_character() -> void:
	var camp := _make_campaign("tribute")
	# Two DIFFERENT lieges. `idx_vassal_assignments_unique_active` forbids two
	# parcels under the same liege, but two under different lieges is exactly the
	# escheat/conquest case D-12 exists for.
	var liege_a := _make_ruler(camp, "liege_a")
	var liege_b := _make_ruler(camp, "liege_b")
	var lord := _make_ruler(camp, "vassal_lord")
	var seat_a := _make_parcel(camp, "liege_a_seat", liege_a, {"peasants": 400})
	var seat_b := _make_parcel(camp, "liege_b_seat", liege_b, {"peasants": 400})
	var p1 := _make_parcel(camp, "v1", lord, {"peasants": 150})
	var p2 := _make_parcel(camp, "v2", lord, {"peasants": 150})
	_set_liege(p1, seat_a)
	_set_liege(p2, seat_b)

	var expected_once: int = TributeCalculator.compute_tribute_base_cp(
		int(RealmAggregator.aggregate(lord).get("all_realm_families", 0)))
	check(expected_once > 0, "the fixture actually owes tribute")

	var res := _run_tick(camp)
	var t1: int = int(CampaignRepository.get_domain(p1).get("tribute_out_owed", -1))
	var t2: int = int(CampaignRepository.get_domain(p2).get("tribute_out_owed", -1))
	check(t1 + t2 == expected_once,
		"the character owes his realm tribute ONCE (got %d + %d = %d, want %d — "
			% [t1, t2, t1 + t2, expected_once]
			+ "%d would be the old per-parcel double charge)" % (2 * expected_once))
	check((t1 == 0) != (t2 == 0),
		"exactly one parcel carries the charge")

	var pd: Dictionary = (res.get(p1, {}) as Dictionary).get("personal_domain", {})
	var seat: String = String(pd.get("tribute_seat_id", ""))
	check(seat == (p1 if p1 < p2 else p2),
		"the tribute seat is his lowest-id liege-bearing parcel")
	check(int(CampaignRepository.get_domain(seat).get("tribute_out_owed", -1))
			== expected_once,
		"and it is the parcel that was charged")


# ---------------------------------------------------------------------------
# Stronghold sufficiency across the holding
# ---------------------------------------------------------------------------

func test_sufficiency_is_judged_on_the_whole_holding() -> void:
	var camp := _make_campaign("sufficiency")
	var rich := _make_ruler(camp, "rich")
	# One keep on parcel A, nothing on B. RAW lets a ruler hold many strongholds
	# in one domain "so long as their combined value secures the land", so the
	# keep secures both — under the old per-parcel gate, B earned nothing.
	var a := _make_parcel(camp, "a", rich, {"stronghold_cp": 2 * CIVILIZED_MIN_CP})
	var b := _make_parcel(camp, "b", rich, {})

	var poor := _make_ruler(camp, "poor")
	# One short of the combined minimum: BOTH of his parcels gate closed.
	var c := _make_parcel(camp, "c", poor,
		{"stronghold_cp": 2 * CIVILIZED_MIN_CP - 1})
	var d := _make_parcel(camp, "d", poor, {})

	var res := _run_tick(camp)
	for id in [a, b]:
		var r: Dictionary = res.get(id, {})
		check(not bool(r.get("income_gate_active", true)),
			"the combined stronghold value secures every parcel")
		check(int(r.get("revenue", 0)) > 0, "so each one earns")
	for id in [c, d]:
		var r: Dictionary = res.get(id, {})
		check(bool(r.get("income_gate_active", false)),
			"one copper short of the COMBINED minimum closes the gate everywhere")
		check(int(r.get("revenue", -1)) == 0, "and nothing is earned")

	var pd: Dictionary = (res.get(a, {}) as Dictionary).get("personal_domain", {})
	check(int(pd.get("stronghold_minimum_cp", 0)) == 2 * CIVILIZED_MIN_CP,
		"the minimum is the sum over his holding, not one parcel's")


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

func test_worst_classification_drives_the_morale_penalty() -> void:
	var camp := _make_campaign("classification")
	var cid := _make_ruler(camp, "frontier", {"level": 9})
	var civ := _make_parcel(camp, "civ", cid, {
		"territory_type": "civilized",
		"stronghold_cp": CIVILIZED_MIN_CP + WILDERNESS_MIN_CP})
	var wild := _make_parcel(camp, "wild", cid, {"territory_type": "wilderness"})

	var res := _run_tick(camp)
	var r: Dictionary = res.get(civ, {})
	var pd: Dictionary = r.get("personal_domain", {})
	check(String(pd.get("worst_classification", "")) == "wilderness",
		"a single wilderness parcel makes the whole domain wilderness for morale")

	var seat_id: String = String(pd.get("seat_parcel_id", ""))
	var seat_row: Dictionary = CampaignRepository.get_domain(seat_id)
	var ruler: Dictionary = _ruler_context(camp, seat_id)
	var rev: int = int(pd.get("union_revenue_cp", 0))
	var sv: int = int(pd.get("stronghold_value_cp", 0))
	var sm: int = int(pd.get("stronghold_minimum_cp", 0))
	var worst: int = DomainMoraleResolver.resolve_base_morale(
		seat_row, ruler, rev, sv, sm, 0, 0, "wilderness")
	var mild: int = DomainMoraleResolver.resolve_base_morale(
		seat_row, ruler, rev, sv, sm, 0, 0, "civilized")
	check(int(r.get("base_morale", -99)) == worst,
		"base morale took the wilderness penalty (got %d, want %d)"
			% [int(r.get("base_morale", -99)), worst])
	check(mild - worst == 2,
		"RAW's wilderness modifier is -2 against civilized's 0")
	check(int(res.get(wild, {}).get("base_morale", -99)) == worst,
		"and both parcels report it, because it is one domain")


# ---------------------------------------------------------------------------
# Event modifiers over the union
# ---------------------------------------------------------------------------

func test_administering_any_parcel_lifts_the_whole_domain() -> void:
	var camp := _make_campaign("administer")
	# Two rulers, identical fixtures. One administers his NON-seat parcel; under
	# the per-parcel model that +1 would have applied only to that parcel's own
	# roll, which is not how administering a domain works.
	var admin := _make_ruler(camp, "administers")
	var a1 := _make_parcel(camp, "a1", admin, {"stronghold_cp": 2 * CIVILIZED_MIN_CP})
	var a2 := _make_parcel(camp, "a2", admin, {})
	var plain := _make_ruler(camp, "delegates")
	var p1 := _make_parcel(camp, "p1", plain, {"stronghold_cp": 2 * CIVILIZED_MIN_CP})
	var _p2 := _make_parcel(camp, "p2", plain, {})

	var non_seat: String = a2 if a1 < a2 else a1
	CampaignRepository.update_domain_monthly_state(
		non_seat, {"administer_domain_completed_this_month": 1})

	var res := _run_tick(camp)
	# adjusted_roll - roll_2d6 is exactly the event-modifier sum (+ repression,
	# which is 0 here), so the two rulers differ by the administration bonus and
	# nothing else.
	var mr_admin: Dictionary = (res.get(a1, {}) as Dictionary).get("morale_roll", {})
	var mr_plain: Dictionary = (res.get(p1, {}) as Dictionary).get("morale_roll", {})
	var mods_admin: int = int(mr_admin.get("adjusted_roll", 0)) \
		- int(mr_admin.get("roll_2d6", 0))
	var mods_plain: int = int(mr_plain.get("adjusted_roll", 0)) \
		- int(mr_plain.get("roll_2d6", 0))
	check(mods_admin - mods_plain == 1,
		"administering ANY parcel is +1 on the character's one roll "
			+ "(got %d vs %d)" % [mods_admin, mods_plain])


func test_garrison_ratio_is_taken_over_the_union() -> void:
	# Pure-function coverage: the combine step is where the RAW gp/family ratio
	# stops being per-parcel. Fixtures mimic GarrisonExpenditureCalculator's own
	# output shape.
	var lavish := {
		"total_paid_cp": 40_000, "unpaid_value_cp": 0, "peasant_families": 100,
		"minimum_total_cp": 20_000,
	}
	var bare := {
		"total_paid_cp": 0, "unpaid_value_cp": 0, "peasant_families": 100,
		"minimum_total_cp": 20_000,
	}
	var combined: Dictionary = GarrisonExpenditureCalculator.combine(
		[lavish, bare], "wilderness")
	check(int(combined.get("cp_per_family_value", -1)) == 200,
		"40,000 cp over 200 families is 200 cp/family, the RAW minimum exactly")
	check(int(combined.get("gp_below_minimum_per_family", -1)) == 0,
		"so no underfunding penalty — the bare parcel is covered by the other")
	check(int(combined.get("morale_incentive_bonus", -1)) == 0,
		"and no incentive bonus either: he is paying the minimum, not above it")
	check(bool(combined.get("meets_minimum", false)),
		"the combined spend meets the combined minimum")

	# A mixed clanhold/civilized holding keeps each parcel's own RAW floor, so
	# the union's per-family minimum is the population-weighted blend.
	var clan := {
		"total_paid_cp": 0, "unpaid_value_cp": 0, "peasant_families": 100,
		"minimum_total_cp": 40_000,  # 4 gp/family per ax_domains_of_chaos L86
	}
	var mixed: Dictionary = GarrisonExpenditureCalculator.combine(
		[bare, clan], "civilized")
	check(int(mixed.get("minimum_cp_per_family", -1)) == 300,
		"200 and 400 cp/family over equal populations blend to 300")
	check(int(mixed.get("gp_below_minimum_per_family", -1)) == 3,
		"paying nothing against a 3 gp/family minimum is -3 morale")

	# Wilderness incentive band still fires when he really does pay above.
	var generous: Dictionary = GarrisonExpenditureCalculator.combine(
		[{"total_paid_cp": 80_000, "unpaid_value_cp": 0, "peasant_families": 100,
		  "minimum_total_cp": 20_000}], "wilderness")
	check(int(generous.get("morale_incentive_bonus", -1)) == 2,
		"4 gp/family in wilderness is the RAW +2 band")

	var empty: Dictionary = GarrisonExpenditureCalculator.combine([], "civilized")
	check(int(empty.get("peasant_families", -1)) == 0
			and int(empty.get("morale_incentive_bonus", -1)) == 0,
		"an empty holding returns the zeroed shape, never a malformed dict")


func test_a_levy_is_diluted_by_the_whole_population() -> void:
	# RAW daw_armies_recruitment.xml:430 is a DENSITY: 2 militia per 10 families
	# is -2, any lesser levy is -1. Under D-12 the denominator is the character's
	# whole population, so 20 militia raised on a 100-family parcel is heavy for
	# that parcel but light for a 200-family domain.
	check(LevyPenaltyCalculator.morale_penalty(20, 100) == -2,
		"20 levied out of 100 families is the heavy band")
	check(LevyPenaltyCalculator.morale_penalty(20, 200) == -1,
		"the same 20 out of 200 is the light band")

	var camp := _make_campaign("levy")
	var cid := _make_ruler(camp, "levier", {"level": 9})
	var a := _make_parcel(camp, "a", cid, {"stronghold_cp": 2 * CIVILIZED_MIN_CP})
	var b := _make_parcel(camp, "b", cid, {})
	_levy_militia(camp, cid, a, 20)

	var res := _run_tick(camp)
	var r: Dictionary = res.get(a, {})
	var pd: Dictionary = r.get("personal_domain", {})
	var seat_id: String = String(pd.get("seat_parcel_id", ""))
	var seat_row: Dictionary = CampaignRepository.get_domain(seat_id)
	var ruler: Dictionary = _ruler_context(camp, seat_id)
	var rev: int = int(pd.get("union_revenue_cp", 0))
	var sv: int = int(pd.get("stronghold_value_cp", 0))
	var sm: int = int(pd.get("stronghold_minimum_cp", 0))
	var light: int = DomainMoraleResolver.resolve_base_morale(
		seat_row, ruler, rev, sv, sm, 0, -1, "civilized")
	var heavy: int = DomainMoraleResolver.resolve_base_morale(
		seat_row, ruler, rev, sv, sm, 0, -2, "civilized")
	check(int(r.get("base_morale", -99)) == light,
		"the levy was rated against his 200 families, not the 100 on that parcel "
			+ "(got %d, want %d; %d would be the per-parcel reading)"
			% [int(r.get("base_morale", -99)), light, heavy])
	check(int(res.get(b, {}).get("base_morale", -99)) == light,
		"and the parcel that raised no militia carries the same penalty — "
			+ "the peasants under arms are his, wherever they came from")


# ---------------------------------------------------------------------------
# One sufficiency answer for every reader
# ---------------------------------------------------------------------------

func test_every_reader_gets_the_same_sufficiency_answer() -> void:
	# The tick, the four Domain sub-tabs, the manage_stronghold activity and the
	# two ruler-AI gates all ask "is his stronghold enough?". Before D-12 they
	# each asked it per parcel; the tick now asks it of the union, so the others
	# must use the same helper or the UI contradicts the income gate it explains
	# and the AI keeps buying keeps for land it has already secured.
	var camp := _make_campaign("sufficiency_readers")
	var cid := _make_ruler(camp, "reader")
	var a := _make_parcel(camp, "a", cid, {"stronghold_cp": 2 * CIVILIZED_MIN_CP})
	var b := _make_parcel(camp, "b", cid, {})

	var from_a: Dictionary = PersonalDomain.sufficiency_for_domain(a)
	var from_b: Dictionary = PersonalDomain.sufficiency_for_domain(b)
	check(from_a == from_b,
		"both parcels report the identical verdict — it is one domain")
	check(int(from_a["minimum_cp"]) == 2 * CIVILIZED_MIN_CP,
		"the minimum is summed over the holding")
	check(int(from_a["value_cp"]) == 2 * CIVILIZED_MIN_CP,
		"and so is the value, wherever the keep physically stands")
	check(bool(from_a["is_sufficient"]) and int(from_a["shortfall_cp"]) == 0,
		"the bare parcel is secured by the other parcel's keep")
	check(int(from_a["parcel_count"]) == 2,
		"and the verdict says how many holdings it covered")

	# The tick must agree with the helper, on the same fixture.
	var res := _run_tick(camp)
	var pd: Dictionary = (res.get(b, {}) as Dictionary).get("personal_domain", {})
	check(int(pd.get("stronghold_minimum_cp", -1)) == int(from_a["minimum_cp"])
			and int(pd.get("stronghold_value_cp", -1)) == int(from_a["value_cp"]),
		"the monthly tick used exactly the figures every other reader will see")

	# A ruler who holds nothing, and a domain id that does not exist, both answer
	# zero rather than inventing a wilderness minimum out of a missing row.
	var nothing: Dictionary = PersonalDomain.sufficiency_for_domain("no_such_domain")
	check(int(nothing["minimum_cp"]) == 0 and int(nothing["value_cp"]) == 0
			and bool(nothing["is_sufficient"]),
		"an unknown domain returns a zeroed verdict, not a fabricated minimum")
	check(int(PersonalDomain.sufficiency_for_domain("")["minimum_cp"]) == 0,
		"and so does an empty id")
