extends "res://tests/test_suite_base.gd"

## Faction FF-4 — the Allegiance Engine (gdd-faction-framework.md §7.1-§7.3). Covers
## the support-term stack, the open/lean/neutral/FEIGN decision, the feign eligibility
## gate (self_interest / type / survive; Fanatic-faithful never feign), and the
## discovery-only invariant (true_stance + betrayal_condition never leave the raw row).
## NOT executed by this build session; registered for the central run.

var _cid: String = ""


func run_all_tests() -> void:
	_setup()
	test_seat_exposure_term_is_real()
	test_neutral_when_support_ties()
	test_open_support_when_pref_is_seat()
	test_lean_band()
	test_feign_when_pref_not_seat_and_eligible()
	test_fanatic_faithful_never_feigns_open_defiant()
	test_discovery_only_true_stance_hidden()
	test_malformed_terms_context_does_not_crash()
	if not has_failures():
		print("FactionFF4Allegiance: all tests passed.")


func _setup() -> void:
	randomize()
	_cid = CampaignRepository.create_campaign("FF4 Allegiance", "World")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _char(cname: String, align: String = "neutral") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'mage', 9, 12, 12, 12, 12, 12, 12, ?, 30, 30)
	""", [id, _cid, cname, align])
	return id


func _realm(rname: String, head: String, align: String) -> String:
	return RealmRepository.create_realm({
		"campaign_id": _cid, "name": rname, "head_character_id": head,
		"alignment": align, "realm_kind": "tracked"})


func _domain(dname: String, head: String, realm_id: String) -> String:
	var did: String = CampaignRepository.create_domain({
		"campaign_id": _cid, "name": dname, "owner_character_id": head})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET realm_id = ? WHERE id = ?", [realm_id, did])
	return did


func _mirror(realm_id: String) -> String:
	return FactionRegistry.ensure_realm_mirror(_cid, realm_id)


func _org(oname: String, otype: String, home_domain: String, align: String = "neutral",
		goal: String = "") -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.alignment = align
	f.home_domain_id = home_domain
	f.goal_primary = goal
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)


## A rebellion conflict: rebel realm (Orso) vs liege realm (Pelagius). The org's seat
## is in the REBEL realm — so seat_side = the rebel mirror.
func _scenario() -> Dictionary:
	var orso := _char("Orso", "neutral")
	var pelagius := _char("Pelagius", "lawful")
	var orso_realm := _realm("Duchy of Orso", orso, "neutral")
	var pel_realm := _realm("Kingdom of Pelagius", pelagius, "lawful")
	var orso_dom := _domain("Orso Seat", orso, orso_realm)
	_domain("Pelagius Crown", pelagius, pel_realm)
	var orso_mirror := _mirror(orso_realm)
	var pel_mirror := _mirror(pel_realm)
	var guild := _org("Arcane Tower", "mage_guild", orso_dom, "neutral")
	return {
		"guild": guild, "orso_dom": orso_dom,
		"orso_mirror": orso_mirror, "pel_mirror": pel_mirror,
		"orso_realm": orso_realm, "pel_realm": pel_realm,
		"conflict": {
			"conflict_id": "rebellion:test", "kind": "rebellion",
			"side_a_mirror": orso_mirror, "side_b_mirror": pel_mirror,
			"side_a_realm_id": orso_realm, "side_b_realm_id": pel_realm,
			"legitimate_side": pel_mirror, "instigator_side": orso_mirror},
	}


func _terms(vals: Dictionary) -> Dictionary:
	# Fill a complete term override so total is fully deterministic.
	var base := {"default": 0, "grievance": 0, "patronage": 0, "ties": 0,
		"exposure": 0, "winner": 0, "type_bias": 0}
	for k in vals.keys():
		base[k] = vals[k]
	return base


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_seat_exposure_term_is_real() -> void:
	# WITHOUT overriding exposure, the seat side earns the real +2 exposure term.
	var s := _scenario()
	var res: Dictionary = AllegianceEvaluator.evaluate(
		s["guild"], s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, {})
	check(int((res["terms_a"] as Dictionary).get("exposure", -1)) == AllegianceEvaluator.EXPOSURE_TERM,
		"seat-side (Orso) exposure term is +%d, got %s" % [AllegianceEvaluator.EXPOSURE_TERM, (res["terms_a"] as Dictionary).get("exposure")])
	check(int((res["terms_b"] as Dictionary).get("exposure", -1)) == 0,
		"non-seat side (Pelagius) exposure term is 0")
	check(String(res.get("seat_side_mirror", "")) == s["orso_mirror"], "seat resolved to Orso")


func test_neutral_when_support_ties() -> void:
	var s := _scenario()
	var ctx := {"terms": {s["orso_mirror"]: _terms({}), s["pel_mirror"]: _terms({})}}
	var res: Dictionary = AllegianceEvaluator.evaluate(
		s["guild"], s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, ctx)
	check(String(res.get("decision", "")) == "neutral", "tie -> declared neutrality, got %s" % res.get("decision"))
	check((res["betrayal_condition"] as Dictionary).is_empty(), "neutral carries no betrayal condition")


func test_open_support_when_pref_is_seat() -> void:
	# Orso (the seat) is strongly preferred -> open support, no feign gate needed.
	var s := _scenario()
	var ctx := {"terms": {s["orso_mirror"]: _terms({"default": 5}), s["pel_mirror"]: _terms({})}}
	var res: Dictionary = AllegianceEvaluator.evaluate(
		s["guild"], s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, ctx)
	check(String(res.get("decision", "")) == "open", "margin>=4 toward seat -> open, got %s" % res.get("decision"))
	check(String(res.get("professed_side_mirror", "")) == s["orso_mirror"], "professes Orso openly")
	check(String(res.get("public_a", "")) == "friendly", "public friendly to Orso")
	check(String(res.get("public_b", "")) == "unfriendly", "public unfriendly to Pelagius")


func test_lean_band() -> void:
	var s := _scenario()
	var ctx := {"terms": {s["orso_mirror"]: _terms({"default": 2}), s["pel_mirror"]: _terms({})}}
	var res: Dictionary = AllegianceEvaluator.evaluate(
		s["guild"], s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, ctx)
	check(String(res.get("decision", "")) == "lean", "margin 2..4 toward seat -> lean, got %s" % res.get("decision"))
	check(String(res.get("public_a", "")) == "friendly" and String(res.get("public_b", "")) == "neutral",
		"lean: public friendly to Orso, neutral to Pelagius")


func test_feign_when_pref_not_seat_and_eligible() -> void:
	# Pelagius preferred (non-seat) + a self-interested leader -> FEIGN: profess Orso,
	# truly hold Pelagius, arm side_loses_field_battle(Orso).
	var s := _scenario()
	var ctx := {
		"leader_self_interest": 8,
		"terms": {s["orso_mirror"]: _terms({}), s["pel_mirror"]: _terms({"winner": 4})}}
	var res: Dictionary = AllegianceEvaluator.evaluate(
		s["guild"], s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, ctx)
	check(String(res.get("decision", "")) == "feign", "pref!=seat + eligible -> feign, got %s" % res.get("decision"))
	check(bool((res["feign_gate"] as Dictionary).get("eligible", false)), "feign gate eligible (self_interest 8)")
	check(String(res.get("professed_side_mirror", "")) == s["orso_mirror"], "publicly professes the seat-holder Orso")
	check(String(res.get("public_a", "")) == "friendly", "public friendly to Orso (the mask)")
	check(String(res.get("true_a", "")) == "unfriendly", "true stance to Orso is unfriendly (will betray)")
	check(String(res.get("true_b", "")) == "friendly", "true stance to Pelagius is friendly")
	var cond: Dictionary = res["betrayal_condition"]
	check(String(cond.get("kind", "")) == BetrayalResolver.COND_SIDE_LOSES_FIELD_BATTLE,
		"betrayal condition defaults to side_loses_field_battle, got %s" % cond.get("kind"))
	check(String((cond.get("params", {}) as Dictionary).get("side_mirror", "")) == s["orso_mirror"],
		"betrayal keyed to Orso losing")


func test_fanatic_faithful_never_feigns_open_defiant() -> void:
	# A temple with a zealot goal cannot dissemble: it declares openly for its true
	# preference (Pelagius) and, since the seat-holder is Orso, goes underground.
	var s := _scenario()
	var orso_dom: String = s["orso_dom"]
	var temple := _org("Temple of Tulras", "temple", orso_dom, "lawful", "spread_doctrine")
	var ctx := {"terms": {s["orso_mirror"]: _terms({}), s["pel_mirror"]: _terms({"ties": 4})}}
	var res: Dictionary = AllegianceEvaluator.evaluate(
		temple, s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, ctx)
	check(not bool((res["feign_gate"] as Dictionary).get("eligible", true)),
		"fanatic-faithful temple is feign-INELIGIBLE")
	check(String(res.get("decision", "")) == "open_defiant", "declares openly, got %s" % res.get("decision"))
	check(bool(res.get("underground", false)), "chapter in the enemy seat goes underground")
	AllegianceEvaluator.apply_decision(_cid, res, 100)
	var refreshed: Dictionary = CampaignRepository.get_faction(String(temple.get("id", "")))
	check(String(refreshed.get("status", "")) == "underground", "temple status flipped to underground after apply")


func test_discovery_only_true_stance_hidden() -> void:
	# After a feign is persisted, the RAW row carries true_stance + betrayal_condition,
	# but the PUBLIC stance API (get_stance) never returns them (§7.4).
	var s := _scenario()
	var guild: Dictionary = s["guild"]
	var ctx := {"leader_self_interest": 8,
		"terms": {s["orso_mirror"]: _terms({}), s["pel_mirror"]: _terms({"winner": 4})}}
	var res: Dictionary = AllegianceEvaluator.evaluate(
		guild, s["orso_mirror"], s["pel_mirror"], s["conflict"], 200, ctx)
	AllegianceEvaluator.apply_decision(_cid, res, 200)
	var raw: Dictionary = CampaignRepository.ff_get_stance_row(String(guild.get("id", "")), s["orso_mirror"])
	check(str_field(raw, "true_stance") == "unfriendly", "raw row holds the hidden true_stance")
	check(str_field(raw, "betrayal_condition") != "", "raw row holds the betrayal_condition")
	var public: Dictionary = FactionStanceService.get_stance(
		String(guild.get("id", "")), s["orso_mirror"], 200)
	check(String(public.get("public_stance", "")) == "friendly", "public API returns the FRIENDLY mask")
	check(not public.has("true_stance"), "public API NEVER exposes true_stance")
	check(not public.has("betrayal_condition"), "public API NEVER exposes betrayal_condition")


## Review #11: a caller passing a non-Dictionary `terms` (or a non-Dictionary per-side
## entry) must degrade to defaults, not crash the support-term stack. evaluate() is
## public, so a malformed context (future live-LLM path, save migration) must be safe.
func test_malformed_terms_context_does_not_crash() -> void:
	var s := _scenario()
	# terms is a non-Dictionary (String) — the old `x as Dictionary` yielded null.
	var r1: Dictionary = AllegianceEvaluator.evaluate(
		s["guild"], s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, {"terms": "not a dict"})
	check(String(r1.get("decision", "")) != "", "malformed terms (non-dict) still yields a decision")
	# terms[side] is a non-Dictionary — the old typed assignment raised Invalid assignment.
	var bad_terms := {}
	bad_terms[String(s["orso_mirror"])] = "bogus"
	bad_terms[String(s["pel_mirror"])] = 42
	var r2: Dictionary = AllegianceEvaluator.evaluate(
		s["guild"], s["orso_mirror"], s["pel_mirror"], s["conflict"], 100, {"terms": bad_terms})
	check(String(r2.get("decision", "")) != "", "malformed per-side terms still yields a decision")
