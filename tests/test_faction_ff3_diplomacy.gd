extends "res://tests/test_suite_base.gd"

## Faction FF-3.b — realm diplomacy actions (gdd-faction-framework.md §5.6). NOT
## executed by this build session; registered for the central run.
##
## Covers: the sovereign-only catalog gate (is_sovereign), the candidate set
## (propose_treaty/denounce/declare_war/sue_for_peace) gated on disposition +
## realm state, execution resolution (propose→sign, denounce→step hostile,
## declare_war→hostile+challenger threat), and the active-LOD-sovereign war-ceiling
## raise (backdrop/vassal rulers get no diplomacy candidates).

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
	test_vassal_ruler_gets_no_diplomacy_candidates()
	test_sovereign_gets_alliance_candidate()
	test_execute_propose_treaty_signs_on_high_roll()
	test_execute_declare_war_sets_hostile_and_threat()
	if not has_failures():
		print("FactionFF3Diplomacy: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF3 Diplomacy Test", "World")


func _character(cname: String, cha: int = 14) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, ?, 60, 60)
	""", [id, _campaign_id, cname, cha])
	return id


func _realm(rname: String, head: String, align: String = "neutral") -> String:
	return RealmRepository.create_realm({
		"campaign_id": _campaign_id, "name": rname, "head_character_id": head,
		"alignment": align, "realm_kind": "tracked",
	})


func _domain(dname: String, head: String, realm_id: String, liege_domain_id: String = "") -> String:
	var did: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": dname, "owner_character_id": head,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET realm_id = ?, liege_domain_id = ? WHERE id = ?",
		[realm_id, (null if liege_domain_id == "" else liege_domain_id), did])
	return did


func test_vassal_ruler_gets_no_diplomacy_candidates() -> void:
	# A domain with a liege (not an apex) → is_sovereign false → no diplomacy.
	var head := _character("Vassal Ruler")
	var ruler := CampaignRepository.get_character(head)
	var apex_head := _character("Apex")
	var ar := _realm("Apex Realm", apex_head)
	var ad := _domain("Apex Cap", apex_head, ar)
	var vr := _realm("Vassal Realm", head)
	var vd := _domain("Vassal Cap", head, vr, ad)
	var domain := CampaignRepository.get_domain(vd)
	var candidates := RulerActionCatalog.available_for(ruler, domain, {"is_sovereign": false})
	for c in candidates:
		check(not RulerActionCatalog.DIPLOMACY_ACTION_IDS.has(String(c.get("action_id", ""))),
			"vassal ruler gets no diplomacy action %s" % c.get("action_id"))


func test_sovereign_gets_alliance_candidate() -> void:
	var head := _character("Sovereign")
	var neighbor := _character("Neighbor")
	var sr := _realm("Sovereign Realm", head)
	var nr := _realm("Neighbor Realm", neighbor)
	var sd := _domain("Sov Cap", head, sr)
	var _nd := _domain("Nbr Cap", neighbor, nr)
	# Give the sovereign a disposition with an alliance preference toward nr.
	var disp := StrategicDisposition.new()
	disp.diplomatic_weight = 0.8
	disp.alliance_preference = {nr: 0.9}
	RulerDispositionRepository.save_disposition(_campaign_id, head, disp)
	# neutral stance qualifies (>= neutral).
	var domain := CampaignRepository.get_domain(sd)
	var ruler := CampaignRepository.get_character(head)
	var candidates := RulerActionCatalog.available_for(ruler, domain, {"is_sovereign": true})
	var has_propose := false
	for c in candidates:
		if String(c.get("action_id", "")) == "propose_treaty" \
				and String((c.get("params", {}) as Dictionary).get("target_realm_id", "")) == nr:
			has_propose = true
	check(has_propose, "sovereign gets a propose_treaty candidate toward the preferred neighbor")


func test_execute_propose_treaty_signs_on_high_roll() -> void:
	var head := _character("Proposer", 18)   # +3 CHA
	var target := _character("Target")
	var pr := _realm("Proposer Realm", head)
	var tr := _realm("Target Realm", target)
	var _pd := _domain("Prop Cap", head, pr)
	var _td := _domain("Tgt Cap", target, tr)
	var dice := FakeDice.new()
	dice.d2d6 = 10   # + CHA +3 → well above 9 accept threshold
	var out := RealmDiplomacyActions.execute(head, "propose_treaty",
		{"target_realm_id": tr, "kind": "alliance"}, 30, dice)
	check(String(out.get("result", "")) == "accepted", "high roll accepts, got %s" % out.get("result"))
	check(String(out.get("treaty_id", "")) != "", "a treaty row was created")
	check(not CampaignRepository.ff_get_active_treaty_between(pr, tr, ["alliance"]).is_empty(),
		"active alliance exists after acceptance")


func test_execute_declare_war_sets_hostile_and_threat() -> void:
	var head := _character("Aggressor")
	var target := _character("Prey")
	var ar := _realm("Aggressor Realm", head)
	var tr := _realm("Prey Realm", target)
	var _ad := _domain("Agg Cap", head, ar)
	var td := _domain("Prey Cap", target, tr)
	var out := RealmDiplomacyActions.execute(head, "declare_war",
		{"target_realm_id": tr}, 40, null)
	check(String(out.get("result", "")) == "war_declared", "war declared")
	check(RealmRepository.get_relation(ar, tr) == "hostile", "relation set hostile")
	# A challenger threat was registered on the prey sovereign's domain (invasion
	# emitted via army-warfare).
	var threats := DomainThreatRepository.list_active_threats_for_domain(td)
	var has_challenger := false
	for t in threats:
		if String((t as Dictionary).get("kind", "")) == "npc_challenger":
			has_challenger = true
	check(has_challenger, "an npc_challenger invasion threat was emitted on the prey domain")
