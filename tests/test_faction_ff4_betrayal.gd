extends "res://tests/test_suite_base.gd"

## Faction FF-4 — feign -> betrayal execution (gdd-faction-framework.md §7.3). Covers
## the betrayal-condition enum + parameterization, the pure condition_matches
## predicate for every kind, and the end-to-end flip: a field-battle loss fires the
## armed condition -> stance swap + one free +4 covert op + a betrayal_executed ledger
## entry that NEVER expires. NOT executed by this build session.

class FixedDice:
	extends RefCounted
	var d20: int = 20
	func roll(count: int, sides: int) -> int:
		if count == 1 and sides == 20:
			return d20
		return count   # deterministic filler for any 2d12 etc.

var _cid: String = ""
var _betrayals: int = 0


func run_all_tests() -> void:
	_setup()
	test_generate_condition_default_and_hint()
	test_condition_matches_each_kind()
	test_no_fire_on_unrelated_event()
	test_betrayal_fires_on_field_battle_loss()
	test_betrayal_ledger_never_expires()
	if not has_failures():
		print("FactionFF4Betrayal: all tests passed.")


func _setup() -> void:
	randomize()
	_cid = CampaignRepository.create_campaign("FF4 Betrayal", "World")


# ---------------------------------------------------------------------------
# Pure-predicate tests (no DB)
# ---------------------------------------------------------------------------

func test_generate_condition_default_and_hint() -> void:
	var faction := {"id": "f1", "faction_type": "mage_guild"}
	var def := BetrayalResolver.generate_condition(faction, "seatM", "prefM", {"conflict_id": "c1"})
	check(String(def.get("kind", "")) == BetrayalResolver.COND_SIDE_LOSES_FIELD_BATTLE,
		"default condition is side_loses_field_battle")
	check(String(def.get("professed_mirror", "")) == "seatM", "records professed mirror")
	check(String(def.get("true_mirror", "")) == "prefM", "records true mirror")

	var hinted := BetrayalResolver.generate_condition(faction, "seatM", "prefM",
		{"conflict_id": "c1", "betrayal_hint": BetrayalResolver.COND_PATRON_PAYMENT_MISSED,
		 "patron_grace_months": 3})
	check(String(hinted.get("kind", "")) == BetrayalResolver.COND_PATRON_PAYMENT_MISSED,
		"hint steers the condition kind")
	check(int((hinted.get("params", {}) as Dictionary).get("n_months", 0)) == 3, "patron grace months carried")


func test_condition_matches_each_kind() -> void:
	# side_loses_field_battle
	var c1 := {"kind": BetrayalResolver.COND_SIDE_LOSES_FIELD_BATTLE,
		"params": {"side_mirror": "S", "side_realm_id": "R"}}
	check(BetrayalResolver.condition_matches(c1, "field_battle_resolved", {"loser_realm_id": "R"}),
		"matches a battle loss by realm id")
	check(not BetrayalResolver.condition_matches(c1, "field_battle_resolved", {"loser_realm_id": "OTHER"}),
		"does not match a different loser")
	check(not BetrayalResolver.condition_matches(c1, "siege_begun", {"besieged_realm_id": "R"}),
		"wrong event kind does not match")
	# siege_of_seat_begins
	var c2 := {"kind": BetrayalResolver.COND_SIEGE_OF_SEAT_BEGINS, "params": {"side_realm_id": "R"}}
	check(BetrayalResolver.condition_matches(c2, "siege_begun", {"besieged_realm_id": "R"}), "siege matches")
	# patron_payment_missed(n)
	var c3 := {"kind": BetrayalResolver.COND_PATRON_PAYMENT_MISSED, "params": {"side_mirror": "P", "n_months": 2}}
	check(BetrayalResolver.condition_matches(c3, "patron_payment_missed", {"patron_mirror": "P", "months_missed": 2}),
		"payment missed at threshold matches")
	check(not BetrayalResolver.condition_matches(c3, "patron_payment_missed", {"patron_mirror": "P", "months_missed": 1}),
		"below threshold does not match")
	# power_ratio_crosses(x)
	var c4 := {"kind": BetrayalResolver.COND_POWER_RATIO_CROSSES, "params": {"x": 0.4}}
	check(BetrayalResolver.condition_matches(c4, "power_ratio_update", {"ratio": 0.35}), "ratio below x matches")
	check(not BetrayalResolver.condition_matches(c4, "power_ratio_update", {"ratio": 0.5}), "ratio above x does not")
	# rival_org_declares_for(side)
	var c5 := {"kind": BetrayalResolver.COND_RIVAL_ORG_DECLARES_FOR, "params": {"declared_side_mirror": "X"}}
	check(BetrayalResolver.condition_matches(c5, "rival_org_declared", {"declared_side_mirror": "X"}), "rival declaration matches")
	# evidence_of_persecution_plan
	var c6 := {"kind": BetrayalResolver.COND_EVIDENCE_OF_PERSECUTION_PLAN, "params": {"side_mirror": "P"}}
	check(BetrayalResolver.condition_matches(c6, "persecution_plan_evidence", {"planner_mirror": "P"}),
		"persecution evidence matches")


# ---------------------------------------------------------------------------
# End-to-end firing
# ---------------------------------------------------------------------------

func _feign_fixture() -> Dictionary:
	var orso := _char("Orso")
	var pel := _char("Pelagius", "lawful")
	var orso_realm := _realm("Orso", orso, "neutral")
	var pel_realm := _realm("Pelagius", pel, "lawful")
	var orso_dom := _domain("Orso Seat", orso, orso_realm)
	_domain("Crown", pel, pel_realm)
	var orso_mirror := FactionRegistry.ensure_realm_mirror(_cid, orso_realm)
	var pel_mirror := FactionRegistry.ensure_realm_mirror(_cid, pel_realm)
	var guild := _org("Guild", "mage_guild", orso_dom)
	var conflict := {"conflict_id": "reb", "kind": "rebellion",
		"side_a_mirror": orso_mirror, "side_b_mirror": pel_mirror,
		"side_a_realm_id": orso_realm, "side_b_realm_id": pel_realm,
		"legitimate_side": pel_mirror, "instigator_side": orso_mirror}
	var ctx := {"leader_self_interest": 8,
		"terms": {
			orso_mirror: {"default": 0, "grievance": 0, "patronage": 0, "ties": 0, "exposure": 0, "winner": 0, "type_bias": 0},
			pel_mirror: {"default": 0, "grievance": 0, "patronage": 0, "ties": 0, "exposure": 0, "winner": 4, "type_bias": 0}}}
	var res := AllegianceEvaluator.evaluate(guild, orso_mirror, pel_mirror, conflict, 100, ctx)
	AllegianceEvaluator.apply_decision(_cid, res, 100)
	return {"guild": guild, "orso_mirror": orso_mirror, "pel_mirror": pel_mirror, "orso_realm": orso_realm}


func test_no_fire_on_unrelated_event() -> void:
	var fx := _feign_fixture()
	var fired := BetrayalResolver.check_and_fire(_cid, "field_battle_resolved",
		{"loser_realm_id": "SOME_OTHER_REALM"}, 110, FixedDice.new())
	check(fired.is_empty(), "an unrelated battle does not fire the betrayal")
	# Still armed.
	var raw: Dictionary = CampaignRepository.ff_get_stance_row(String(fx["guild"].get("id", "")), fx["orso_mirror"])
	check(str_field(raw, "betrayal_condition") != "", "condition remains armed after a non-match")


func test_betrayal_fires_on_field_battle_loss() -> void:
	var fx := _feign_fixture()
	var guild_id: String = String(fx["guild"].get("id", ""))
	_betrayals = 0
	if EventBus.has_signal("betrayal_executed"):
		EventBus.betrayal_executed.connect(_on_betrayal)
	var fired := BetrayalResolver.check_and_fire(_cid, "field_battle_resolved",
		{"loser_realm_id": fx["orso_realm"]}, 120, FixedDice.new())
	if EventBus.has_signal("betrayal_executed"):
		EventBus.betrayal_executed.disconnect(_on_betrayal)
	check(fired.size() == 1, "the guild's betrayal fires on Orso losing the field, got %d" % fired.size())
	check(_betrayals == 1, "betrayal_executed signal emitted once")
	# The mask drops: openly hostile to the betrayed seat, openly friendly to Pelagius.
	var to_orso: Dictionary = CampaignRepository.ff_get_stance_row(guild_id, fx["orso_mirror"])
	check(String(to_orso.get("public_stance", "")) == "hostile", "now openly hostile to the betrayed Orso")
	check(str_field(to_orso, "true_stance") == "", "the hidden layer is cleared (treachery is realized)")
	check(str_field(to_orso, "betrayal_condition") == "", "the armed condition is spent")
	var to_pel: Dictionary = CampaignRepository.ff_get_stance_row(guild_id, fx["pel_mirror"])
	check(String(to_pel.get("public_stance", "")) == "friendly", "now openly friendly to Pelagius")
	# The prepared free op ran against the betrayed side.
	var betrayal: Dictionary = fired[0]
	check(bool((betrayal.get("op", {}) as Dictionary).has("op")), "a prepared covert op was run on the flip")


func test_betrayal_ledger_never_expires() -> void:
	var fx := _feign_fixture()
	var guild_id: String = String(fx["guild"].get("id", ""))
	BetrayalResolver.check_and_fire(_cid, "field_battle_resolved",
		{"loser_realm_id": fx["orso_realm"]}, 130, FixedDice.new())
	# The betrayal_executed row is live even far in the future (expires_day NULL).
	var far: int = 130 + 100 * 28   # 100 months later
	var rows := CampaignRepository.ff_list_faction_events(guild_id, fx["orso_mirror"], far)
	var found := false
	for r in rows:
		if String((r as Dictionary).get("kind", "")) == "betrayal_executed":
			found = true
			check((r as Dictionary).get("expires_day") == null, "betrayal_executed stored with NULL expiry")
	check(found, "the betrayal is remembered permanently (never expires, §4.5)")


func _on_betrayal(_faction_id: String, _victim_id: String) -> void:
	_betrayals += 1


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _char(cname: String, align: String = "neutral") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 12, ?, 40, 40)
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


func _org(oname: String, otype: String, home_domain: String, align: String = "neutral") -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.alignment = align
	f.home_domain_id = home_domain
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)
