extends "res://tests/test_suite_base.gd"

## Faction FF-4 — the FactionAI stub light-up (gdd-faction-framework.md §6.5/§6.7/§7).
## FF-2 registered undermine_rival and declare_stance as inert ff4_stub handlers
## (goal_relevance 0, deferred_to FF-4). FF-4 LIGHTS THEM UP: real goal-relevance,
## real handlers, availability-gated (a rival must exist / a conflict must expose the
## org). This suite asserts the wiring is live, not deferred. NOT executed this session.

var _cid: String = ""


func run_all_tests() -> void:
	_setup()
	test_stubs_are_no_longer_inert()
	test_undermine_rival_gated_on_a_rival()
	test_undermine_rival_runs_a_covert_op()
	test_declare_stance_gated_on_a_conflict()
	test_declare_stance_runs_the_evaluator()
	if not has_failures():
		print("FactionFF4FactionAI: all tests passed.")


func _setup() -> void:
	randomize()
	_cid = CampaignRepository.create_campaign("FF4 FactionAI", "World")


func test_stubs_are_no_longer_inert() -> void:
	var um: Dictionary = FactionAI.ACTION_DEFS["undermine_rival"]
	var ds: Dictionary = FactionAI.ACTION_DEFS["declare_stance"]
	check(not bool(um.get("ff4_stub", false)) and not bool(ds.get("ff4_stub", false)),
		"the FF-4 stubs no longer carry ff4_stub")
	check(float(um.get("base", 0.0)) > 0.0 and float(ds.get("base", 0.0)) > 0.0,
		"both actions have a real base value")
	check((um.get("advances", []) as Array).has("suppress_rival"),
		"undermine_rival advances the suppress_rival goal (real relevance)")


func test_undermine_rival_gated_on_a_rival() -> void:
	var org := _org("Guild", "mage_guild")
	# No rival yet -> unavailable.
	check(not FactionAI._action_available("undermine_rival", org, "mage_guild"),
		"undermine_rival is unavailable with no rival")
	var rival := _org("Rivals", "syndicate")
	FactionStanceService.instantiate_stance(_cid, String(org.get("id", "")),
		String(rival.get("id", "")), "unfriendly", "", 0)
	# Re-fetch (the row itself is unchanged; availability reads stances live).
	check(FactionAI._action_available("undermine_rival", org, "mage_guild"),
		"undermine_rival becomes available once a rival exists")


func test_undermine_rival_runs_a_covert_op() -> void:
	var org := _org("Schemers", "syndicate")
	var rival := _org_funded("Marks", "merchant_guild", 40, 1000)
	FactionStanceService.instantiate_stance(_cid, String(org.get("id", "")),
		String(rival.get("id", "")), "hostile", "", 0)
	var out := FactionAI._do_undermine_rival(_cid, org, 100)
	check(String(out.get("target_faction_id", "")) == String(rival.get("id", "")),
		"the op targets the org's worst rival")
	check((out.get("op", {}) as Dictionary).has("op"), "a covert op report is attached (no more FF-4 stub)")
	check(not out.has("deferred_to"), "the handler is NOT a deferred stub")


func test_declare_stance_gated_on_a_conflict() -> void:
	var org := _org("Bystanders", "temple")
	check(not FactionAI._action_available("declare_stance", org, "temple"),
		"declare_stance is unavailable with no active conflict exposing the org")


func test_declare_stance_runs_the_evaluator() -> void:
	# Build a launched rebellion whose rebel realm is the org's seat realm.
	var liege := _char("Liege", "lawful")
	var rebel := _char("Rebel", "neutral")
	var liege_realm := _realm("Crown Realm", liege, "lawful")
	var rebel_realm := _realm("Rebel Realm", rebel, "neutral")
	_domain("Crown", liege, liege_realm)
	var rebel_dom := _domain("Rebel Seat", rebel, rebel_realm)
	var liege_mirror := FactionRegistry.ensure_realm_mirror(_cid, liege_realm)
	var rebel_mirror := FactionRegistry.ensure_realm_mirror(_cid, rebel_realm)
	CampaignRepository.ff_upsert_plot({
		"campaign_id": _cid, "kind": "rebellion",
		"instigator_faction_id": rebel_mirror, "target_faction_id": liege_mirror,
		"secrecy": 0, "launch_condition": "{}", "status": "launched", "ready_since_day": 0})
	var org := _org_seated("Rebel Chapel", "temple", rebel_dom)
	# The conflict now exposes the org.
	var conflict := FactionAI._active_conflict_for(org)
	check(not conflict.is_empty(), "a launched rebellion in the seat realm exposes the org")
	check(FactionAI._action_available("declare_stance", org, "temple"),
		"declare_stance is now available")
	var out := FactionAI._do_declare_stance(_cid, org, 100)
	check(bool(out.get("declared", false)), "declare_stance ran the allegiance evaluator")
	check(String(out.get("decision", "")) != "", "a decision was produced, got %s" % out.get("decision"))
	check(not out.has("deferred_to"), "the handler is NOT a deferred stub")


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


func _org(oname: String, otype: String) -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.goal_primary = "suppress_rival"
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)


func _org_funded(oname: String, otype: String, members: int, treasury: int) -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.member_count_abstract = members
	f.treasury_gp = treasury
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)


func _org_seated(oname: String, otype: String, home_domain: String) -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.home_domain_id = home_domain
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)
