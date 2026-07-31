extends "res://tests/test_suite_base.gd"

## Faction FF-4 CAPSTONE — the Orso worked example, org-allegiance layer
## (gdd-faction-framework.md §7.5), plus the §11.7 determinism harness. This is the
## golden integration test the §12 test plan mandates:
##   - the mages' guild FEIGNS (public: Orso; true: Pelagius; betrayal:
##     side_loses_field_battle(Orso));
##   - the Temple of Tulras (Fanatic-tier) declares for the King OPENLY and its Orso
##     chapter goes underground — it NEVER feigns;
##   - the Grey Rat syndicate sides with Orso OPENLY (no feign gate needed);
##   - the day Orso's host breaks on the field, the guild's prepared op fires
##     (betrayal executed);
##   - replaying an evaluation reproduces a byte-identical audit stream.
## NOT executed by this build session.

class FixedDice:
	extends RefCounted
	var d20: int = 20
	func roll(count: int, sides: int) -> int:
		if count == 1 and sides == 20:
			return d20
		return count * sides

var _cid: String = ""


func run_all_tests() -> void:
	_setup()
	test_orso_org_allegiance_three_ways()
	test_determinism_byte_identical_audit()
	if not has_failures():
		print("FactionFF4OrsoCapstone: all tests passed.")


func _setup() -> void:
	randomize()
	_cid = CampaignRepository.create_campaign("FF4 Orso Capstone", "World")


# ---------------------------------------------------------------------------
# The three-way Orso allegiance
# ---------------------------------------------------------------------------

func _world() -> Dictionary:
	var orso := _char("Orso", "neutral")
	var pel := _char("Pelagius", "lawful")
	var orso_realm := _realm("Duchy of Orso", orso, "neutral")
	var pel_realm := _realm("Kingdom of Pelagius", pel, "lawful")
	var orso_dom := _domain("Orso Seat", orso, orso_realm)
	_domain("Pelagius Crown", pel, pel_realm)
	var orso_mirror := FactionRegistry.ensure_realm_mirror(_cid, orso_realm)
	var pel_mirror := FactionRegistry.ensure_realm_mirror(_cid, pel_realm)
	return {
		"orso_dom": orso_dom, "orso_mirror": orso_mirror, "pel_mirror": pel_mirror,
		"orso_realm": orso_realm, "pel_realm": pel_realm,
		"conflict": {"conflict_id": "rebellion:orso", "kind": "rebellion",
			"side_a_mirror": orso_mirror, "side_b_mirror": pel_mirror,
			"side_a_realm_id": orso_realm, "side_b_realm_id": pel_realm,
			"legitimate_side": pel_mirror, "instigator_side": orso_mirror}}


func _t(vals: Dictionary) -> Dictionary:
	var base := {"default": 0, "grievance": 0, "patronage": 0, "ties": 0,
		"exposure": 0, "winner": 0, "type_bias": 0}
	for k in vals.keys():
		base[k] = vals[k]
	return base


func test_orso_org_allegiance_three_ways() -> void:
	var w := _world()
	var orso_m: String = w["orso_mirror"]
	var pel_m: String = w["pel_mirror"]
	var conflict: Dictionary = w["conflict"]

	# --- The mages' guild: seat in Orso, self-interested leader, structural pull to
	#     the likely winner Pelagius -> FEIGN. ---
	var guild := _org("Arcane Tower", "mage_guild", w["orso_dom"], "neutral", "")
	var guild_ctx := {"leader_self_interest": 8,
		"terms": {orso_m: _t({}), pel_m: _t({"winner": 4})}}
	var guild_res := AllegianceEvaluator.evaluate(guild, orso_m, pel_m, conflict, 100, guild_ctx)
	check(String(guild_res.get("decision", "")) == "feign", "the guild FEIGNS, got %s" % guild_res.get("decision"))
	check(String(guild_res.get("professed_side_mirror", "")) == orso_m, "guild publicly professes Orso")
	check(String((guild_res["betrayal_condition"] as Dictionary).get("kind", "")) ==
		BetrayalResolver.COND_SIDE_LOSES_FIELD_BATTLE, "guild arms side_loses_field_battle")
	AllegianceEvaluator.apply_decision(_cid, guild_res, 100)

	# --- Temple of Tulras: Fanatic-tier (consecrated to Pelagius) -> declares OPENLY
	#     for the King and its Orso chapter goes underground. ---
	var tulras := _org("Temple of Tulras", "temple", w["orso_dom"], "lawful", "spread_doctrine")
	var tulras_ctx := {"terms": {orso_m: _t({}), pel_m: _t({"ties": 4})}}
	var tulras_res := AllegianceEvaluator.evaluate(tulras, orso_m, pel_m, conflict, 100, tulras_ctx)
	check(String(tulras_res.get("decision", "")) == "open_defiant", "Tulras declares openly (never feigns)")
	check(not bool((tulras_res["feign_gate"] as Dictionary).get("eligible", true)), "Tulras is feign-INELIGIBLE (Fanatic)")
	check(String(tulras_res.get("professed_side_mirror", "")) == pel_m, "Tulras declares for the King openly")
	AllegianceEvaluator.apply_decision(_cid, tulras_res, 100)
	check(String(CampaignRepository.get_faction(String(tulras.get("id", ""))).get("status", "")) == "underground",
		"Tulras' Orso chapter goes underground")

	# --- The Grey Rats: back whoever promises less law (Orso), openly, no gate needed. ---
	var rats := _org("Grey Rats", "syndicate", w["orso_dom"], "chaotic", "")
	var rats_ctx := {"terms": {orso_m: _t({"default": 5, "type_bias": 1}), pel_m: _t({})}}
	var rats_res := AllegianceEvaluator.evaluate(rats, orso_m, pel_m, conflict, 100, rats_ctx)
	check(String(rats_res.get("decision", "")) == "open", "the Grey Rats side openly, got %s" % rats_res.get("decision"))
	check(String(rats_res.get("professed_side_mirror", "")) == orso_m, "the Grey Rats side with Orso")
	check((rats_res["betrayal_condition"] as Dictionary).is_empty(), "open support arms no betrayal")


# ---------------------------------------------------------------------------
# §11.7 determinism harness
# ---------------------------------------------------------------------------
# NOTE: the single-guild "betrays on battle loss" case was removed here — it is
# strictly subsumed by test_faction_ff4_betrayal.gd::test_betrayal_fires_on_
# field_battle_loss (same fixture + assertions, plus the betrayal signal,
# true_stance clear, and condition-spend checks this capstone lacked).

func test_determinism_byte_identical_audit() -> void:
	var was_on: bool = bool(ProjectSettings.get_setting(PoliticalAudit.SETTING_FLAG, false))
	ProjectSettings.set_setting(PoliticalAudit.SETTING_FLAG, true)
	var w := _world()
	var orso_m: String = w["orso_mirror"]
	var pel_m: String = w["pel_mirror"]
	var guild := _org("Replay Guild", "mage_guild", w["orso_dom"], "neutral", "")
	var ctx := {"leader_self_interest": 8, "terms": {orso_m: _t({}), pel_m: _t({"winner": 4})}}

	# Run the SAME evaluation twice (no side effects but the audit trace); the streams
	# must be byte-identical (deterministic — no wall-clock, no un-seeded RNG).
	PoliticalAudit.clear()
	AllegianceEvaluator.evaluate(guild, orso_m, pel_m, w["conflict"], 100, ctx)
	var stream_1: String = JSON.stringify(PoliticalAudit.read_all())
	PoliticalAudit.clear()
	AllegianceEvaluator.evaluate(guild, orso_m, pel_m, w["conflict"], 100, ctx)
	var stream_2: String = JSON.stringify(PoliticalAudit.read_all())

	check(stream_1 == stream_2, "replaying a seed reproduces a byte-identical audit stream")
	check(stream_1.length() > 0, "the audit stream is non-empty when the flag is on")

	PoliticalAudit.clear()
	ProjectSettings.set_setting(PoliticalAudit.SETTING_FLAG, was_on)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _char(cname: String, align: String = "neutral") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 12, ?, 50, 50)
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


func _org(oname: String, otype: String, home_domain: String, align: String, goal: String) -> Dictionary:
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
