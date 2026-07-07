extends "res://tests/test_suite_base.gd"

## Faction FF-3.b — treaties (gdd-faction-framework.md §5.5). NOT executed by this
## build session; registered for the central run.
##
## Covers: sign/floor-relation, is_allied() reads active alliance treaties, breach
## detection, renewal roll (kept/lapsed), reputational contagion on break
## (treaty_broken written to every friendly-toward-victim realm's mirror ledger),
## and the active-effect queries (non_aggression gate, call-to-arms eligibility,
## trade-pact market bonus).

class FakeDice:
	extends RefCounted
	var d2d6: int = 7
	func roll(count: int, sides: int) -> int:
		if count == 2 and sides == 6:
			return d2d6
		return 1

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_sign_floors_relation_and_is_allied()
	test_breach_detection_invasion()
	test_renewal_kept_and_lapsed()
	test_break_contagion_writes_friendly_observer_ledger()
	test_active_effect_queries()
	if not has_failures():
		print("FactionFF3Treaties: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF3 Treaty Test", "World")


func _character(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, cname])
	return id


func _realm(rname: String, head: String, align: String = "neutral") -> String:
	return RealmRepository.create_realm({
		"campaign_id": _campaign_id, "name": rname, "head_character_id": head,
		"alignment": align, "realm_kind": "tracked",
	})


func _apex_domain(dname: String, head: String, realm_id: String) -> String:
	var did: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": dname, "owner_character_id": head,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET realm_id = ? WHERE id = ?", [realm_id, did])
	return did


func test_sign_floors_relation_and_is_allied() -> void:
	var a_head := _character("A-head")
	var b_head := _character("B-head")
	var ra := _realm("Realm A", a_head)
	var rb := _realm("Realm B", b_head)
	var da := _apex_domain("Cap A", a_head, ra)
	var db2 := _apex_domain("Cap B", b_head, rb)
	var tid := TreatyResolver.sign_treaty(_campaign_id, ra, rb, "alliance", 10)
	check(tid != "", "alliance signed")
	check(RealmRepository.get_relation(ra, rb) == "friendly",
		"alliance floors relation to friendly, got %s" % RealmRepository.get_relation(ra, rb))
	# is_allied reads the treaty (apex domain ids → realms → active alliance).
	check(RealmGraph.is_allied(da, db2), "is_allied() true after alliance signed")


func test_breach_detection_invasion() -> void:
	var a_head := _character("C-head")
	var b_head := _character("D-head")
	var ra := _realm("Realm C", a_head)
	var rb := _realm("Realm D", b_head)
	TreatyResolver.sign_treaty(_campaign_id, ra, rb, "non_aggression", 5)
	var breach := TreatyResolver.detect_breach(_campaign_id,
		{"kind": "invasion", "aggressor_realm_id": ra, "target_realm_id": rb})
	check(not breach.is_empty(), "invasion breaches non_aggression")
	check(String(breach.get("breaker_realm_id", "")) == ra, "aggressor is the breaker")


func test_renewal_kept_and_lapsed() -> void:
	var a_head := _character("E-head")
	var b_head := _character("F-head")
	var ra := _realm("Realm E", a_head)
	var rb := _realm("Realm F", b_head)
	var tid := TreatyResolver.sign_treaty(_campaign_id, ra, rb, "trade_pact", 0)
	var dice := FakeDice.new()
	dice.d2d6 = 12   # + band mod → well above keep threshold
	var kept := TreatyResolver.renew_treaty(tid, 100, dice)
	check(bool(kept.get("kept", false)), "high roll keeps the treaty")
	check(String(CampaignRepository.ff_get_treaty(tid).get("status", "")) == "active",
		"kept treaty normalized back to active")
	dice.d2d6 = 2   # low roll → lapse
	var lapsed := TreatyResolver.renew_treaty(tid, 200, dice)
	check(not bool(lapsed.get("kept", false)), "low roll lapses the treaty")
	check(String(CampaignRepository.ff_get_treaty(tid).get("status", "")) == "expired",
		"lapsed treaty is expired")


func test_break_contagion_writes_friendly_observer_ledger() -> void:
	var a_head := _character("G-head")
	var b_head := _character("H-head")
	var c_head := _character("I-head")
	var ra := _realm("Breaker", a_head)
	var rb := _realm("Victim", b_head)
	var rc := _realm("Observer", c_head)
	# Observer realm is friendly toward the victim (an instantiated org→realm-mirror
	# stance isn't a realm↔realm pair, so use a friendly org observer instead).
	var breaker_mirror := FactionRegistry.ensure_realm_mirror(_campaign_id, ra)
	var victim_mirror := FactionRegistry.ensure_realm_mirror(_campaign_id, rb)
	var observer_org := _org("Loyal Guild", "mage_guild")
	FactionStanceService.instantiate_stance(_campaign_id, observer_org, victim_mirror, "friendly", "test", 1)
	var tid := TreatyResolver.sign_treaty(_campaign_id, ra, rb, "alliance", 5)
	TreatyResolver.break_treaty(tid, ra, 20)
	# The direct victim holds a treaty_broken grievance toward the breaker.
	var g_victim := FactionEventLedger.recompute_grievance(victim_mirror, breaker_mirror, 20)
	check(g_victim < 0, "victim holds a grievance vs breaker, got %s" % g_victim)
	# The friendly observer org ALSO holds a treaty_broken grievance (contagion).
	var g_obs := FactionEventLedger.recompute_grievance(observer_org, breaker_mirror, 20)
	check(g_obs < 0, "friendly observer holds contagion grievance vs breaker, got %s" % g_obs)


func test_active_effect_queries() -> void:
	var a_head := _character("J-head")
	var b_head := _character("K-head")
	var ra := _realm("Realm J", a_head)
	var rb := _realm("Realm K", b_head)
	TreatyResolver.sign_treaty(_campaign_id, ra, rb, "defensive_pact", 5)
	check(TreatyResolver.has_non_aggression(ra, rb),
		"defensive_pact subsumes the non-aggression gate")
	check(TreatyResolver.call_to_arms_eligible(ra, rb, true),
		"defensive_pact: call-to-arms eligible when invaded")
	check(not TreatyResolver.call_to_arms_eligible(ra, rb, false),
		"defensive_pact: NOT eligible for offensive call")
	var rt := _realm("Trade X", _character("L-head"))
	var ru := _realm("Trade Y", _character("M-head"))
	TreatyResolver.sign_treaty(_campaign_id, rt, ru, "trade_pact", 5)
	check(TreatyResolver.trade_pact_market_bonus(rt, ru) == 1,
		"trade_pact grants +1 market class")


func _org(name: String, ftype: String) -> String:
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = name
	f.faction_type = ftype
	f.alignment = "neutral"
	f.scope = "organization"
	return CampaignRepository.create_faction(f)
