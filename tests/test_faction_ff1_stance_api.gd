extends "res://tests/test_suite_base.gd"

## Faction Framework FF-1.2 (gdd-faction-framework.md §7.2, §3.2, §4.2, §11.7) —
## the default-stance function, the compute-on-read stance API with decay, the
## political_audit JSONL scaffold, and the true_stance isolation invariant.
## NOT executed by this build session; registered for the central run.
##
## Golden tests over the §7.2 matrix: co-aligned same-settlement temples land
## neutral-at-best with the rivalry term in the trace; nemesis temples hostile;
## warband inherits parent; allied never a default; lazy read creates no row;
## decay moves one band once; audit determinism; get_stance never leaks true_stance.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_same_align_same_religion_high()
	test_opposed_alignment_hostile()
	test_co_aligned_same_settlement_temples_rivalry()
	test_nemesis_family_temples_hostile()
	test_warband_inherits_parent()
	test_allied_never_a_default()
	test_lazy_read_creates_no_row()
	test_shift_stance_emits_and_clamps()
	test_decay_moves_one_band_once()
	test_true_stance_isolation()
	test_audit_off_no_io()
	if not has_failures():
		print("FactionFF1StanceApi: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF1 Stance Test", "World")
	DefaultStanceEvaluator.reset_matrix_cache()


func _org(name: String, ftype: String, align: String, religion: String = "",
		culture: String = "", settlement: String = "", scope: String = "organization",
		parent: String = "") -> String:
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = name
	f.faction_type = ftype
	f.alignment = align
	f.religion_id = religion
	f.culture_id = culture
	f.seat_settlement_id = settlement
	f.scope = scope
	f.parent_faction_id = parent
	return CampaignRepository.create_faction(f)


func _eval(a_id: String, b_id: String, ctx: Dictionary = {}) -> Dictionary:
	var fa := CampaignRepository.get_faction(a_id)
	var fb := CampaignRepository.get_faction(b_id)
	if not ctx.has("faction_lookup"):
		ctx["faction_lookup"] = func(fid: String) -> Dictionary:
			return CampaignRepository.get_faction(fid)
	return DefaultStanceEvaluator.evaluate(fa, fb, ctx)


func test_same_align_same_religion_high() -> void:
	# same alignment (+2) + same deity (+2) + same culture (+1) = +5 → friendly.
	var a := _org("Order A", "holy_order", "lawful", "tulras", "brythald")
	var b := _org("Order B", "holy_order", "lawful", "tulras", "brythald")
	var r := _eval(a, b)
	check(int(r.get("score", 0)) == 5, "score 5, got %s" % r.get("score"))
	check(String(r.get("band", "")) == "friendly", "band friendly")


func test_opposed_alignment_hostile() -> void:
	# opposed alignment (-3) + nemesis religion (-3) + alien culture (-1) = -7 → hostile.
	var a := _org("Lawful Church", "temple", "lawful", "tulras", "brythald")
	var b := _org("Chaos Cult", "temple", "chaotic", "morgh", "khan")
	var r := _eval(a, b)
	check(int(r.get("score", 0)) <= DefaultStanceEvaluator.BAND_HOSTILE_MAX, "score ≤ -4")
	check(String(r.get("band", "")) == "hostile", "band hostile")


func test_co_aligned_same_settlement_temples_rivalry() -> void:
	# Two co-aligned but DIFFERENT-deity temples in the SAME settlement: the
	# rivalry term (-1) applies; the pair must be neutral-at-best (NOT friendly).
	var a := _org("Temple of Tulras", "temple", "lawful", "tulras", "brythald", "cyfaraun")
	var b := _org("Temple of Realta", "temple", "lawful", "realta", "brythald", "cyfaraun")
	var r := _eval(a, b, {"same_settlement": true})
	var terms: Dictionary = r.get("terms", {})
	check(int(terms.get("type", 0)) == -1, "rivalry type term -1 present in trace")
	# align same (+2) + religion same family (+1) + culture same (+1) + type (-1) = +3 → indifferent
	# (still not friendly, and never allied).
	check(String(r.get("band", "")) != "friendly", "co-aligned same-settlement temples NOT auto-friendly")
	check(String(r.get("band", "")) != "allied", "never allied by default")


func test_nemesis_family_temples_hostile() -> void:
	var a := _org("Lawful Temple", "temple", "lawful", "tulras", "brythald", "cyfaraun")
	var b := _org("Chaotic Temple", "temple", "chaotic", "morgh", "brythald", "cyfaraun")
	var r := _eval(a, b, {"same_settlement": true})
	check(String(r.get("band", "")) == "hostile", "nemesis-family temples hostile")


func test_warband_inherits_parent() -> void:
	# Parent realm-ish org is hostile toward the target; the warband child
	# inherits that hostility (scale_term).
	var parent := _org("Clanhold", "tribal", "chaotic", "", "khan", "", "organization")
	var target := _org("Lawful Realm Org", "temple", "lawful", "tulras", "brythald")
	var warband := _org("Broken Fang", "pack", "chaotic", "", "khan", "", "warband", parent)
	var parent_r := _eval(parent, target)
	var warband_r := _eval(warband, target)
	check(int(warband_r.get("score", 0)) == int(parent_r.get("score", 0)),
		"warband score inherits parent's exactly")
	var terms: Dictionary = warband_r.get("terms", {})
	check(terms.has("inherited_from_parent"), "trace records parent inheritance")


func test_allied_never_a_default() -> void:
	# The most-friendly possible structural combination still tops out at friendly.
	var a := _org("A", "mercenary_company", "lawful", "tulras", "brythald")
	var b := _org("B", "holy_order", "lawful", "tulras", "brythald")
	var r := _eval(a, b)
	check(String(r.get("band", "")) != "allied", "allied is never a structural default")


func test_lazy_read_creates_no_row() -> void:
	var a := _org("LazyA", "syndicate", "chaotic")
	var b := _org("LazyB", "temple", "lawful", "tulras")
	var stance := FactionStanceService.get_stance(a, b, 100)
	check(stance.get("instantiated", true) == false, "un-instantiated pair reads default")
	check(not stance.has("true_stance"), "default read has no true_stance")
	check(CampaignRepository.ff_get_stance_row(a, b).is_empty(), "no row created by a read")


func test_shift_stance_emits_and_clamps() -> void:
	var a := _org("ShiftA", "mercenary_company", "neutral")
	var b := _org("ShiftB", "mercenary_company", "neutral")
	# Default merc↔merc = 0 type + same align (+2) = neutral/indifferent-ish.
	var band := FactionStanceService.shift_stance(_campaign_id, a, b, -10, "provoked", 100)
	check(band == "hostile", "shift clamps at hostile floor, got %s" % band)
	var band2 := FactionStanceService.shift_stance(_campaign_id, a, b, +100, "reconciled", 100)
	check(band2 == "allied", "shift clamps at allied ceiling, got %s" % band2)
	# A row now exists.
	check(not CampaignRepository.ff_get_stance_row(a, b).is_empty(), "shift instantiates a row")


func test_decay_moves_one_band_once() -> void:
	# Structural default for these two is neutral (alignment one-step 0 + type
	# mercenary 0 + no religion/culture = score 0 → neutral). Instantiate hostile,
	# then read 12 quiet months later → moves ONE band toward neutral (→
	# unfriendly), exactly once. Matches the handoff's §5.6 decay scenario.
	var a := _org("DecayA", "mercenary_company", "lawful")
	var b := _org("DecayB", "mercenary_company", "neutral")
	FactionStanceService.instantiate_stance(_campaign_id, a, b, "hostile", "war", 0)
	var day12 := 12 * 28   # 336 days = 12 game-months
	var stance := FactionStanceService.get_stance(a, b, day12)
	check(String(stance.get("public_stance", "")) == "unfriendly",
		"decayed one band hostile→unfriendly, got %s" % stance.get("public_stance"))
	# Reading again the SAME day does not move further (exactly once per stale read).
	var stance2 := FactionStanceService.get_stance(a, b, day12)
	check(String(stance2.get("public_stance", "")) == "unfriendly", "no second move same day")
	# Persisted.
	var row := CampaignRepository.ff_get_stance_row(a, b)
	check(String(row.get("public_stance", "")) == "unfriendly", "decay persisted")
	check(int(row.get("last_evaluated_day", 0)) == day12, "last_evaluated_day refreshed")


func test_true_stance_isolation() -> void:
	var a := _org("SecretA", "syndicate", "chaotic")
	var b := _org("SecretB", "temple", "lawful")
	var s := FactionStanceData.new()
	s.campaign_id = _campaign_id
	s.faction_a_id = a
	s.faction_b_id = b
	s.public_stance = "friendly"
	s.true_stance = "hostile"
	s.betrayal_condition = "{\"cond\":\"siege_of_seat_begins\"}"
	CampaignRepository.ff_upsert_stance(s)
	# Ordinary read NEVER contains true_stance (§7.4).
	var pub := FactionStanceService.get_stance(a, b, 0)
	check(not pub.has("true_stance"), "get_stance never returns true_stance")
	check(String(pub.get("public_stance", "")) == "friendly", "public band surfaced")
	# The explicit audit accessor DOES expose it (dev-only).
	var full := FactionStanceService.get_stance_full_for_audit(a, b)
	check(String(full.get("true_stance", "")) == "hostile", "audit accessor exposes true_stance")


func test_audit_off_no_io() -> void:
	# With the flag OFF (default), evaluation writes zero records.
	PoliticalAudit.clear()
	check(PoliticalAudit.is_enabled() == false, "audit flag default off")
	var a := _org("AuditA", "temple", "lawful", "tulras")
	var b := _org("AuditB", "temple", "lawful", "tulras")
	FactionStanceService.get_stance(a, b, 100)
	check(PoliticalAudit.read_all().is_empty(), "no JSONL records when flag off")
