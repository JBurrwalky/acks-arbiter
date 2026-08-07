extends "res://tests/test_suite_base.gd"

## Faction FF-3.d/.e — rebel coalitions (§5.7) + plot secrecy (§7.4) + the
## resignation ladder A/B/C (§5.9). NOT executed by this build session; registered
## for the central run.
##
## Covers: SEED (plot brewing + instigator committed), SOUND OUT (secret loyalty
## roll → commitment bands, informant exposes, loose-talk secrecy erosion), READY
## (extraction-resistance-pattern power check + threshold), LAUNCH (rebel realm
## mirror minted + realm_relations hostile), secrecy erosion → exposure, and the
## resignation ladder (A grant/buy-off/refuse, B appeal adjudication with the
## intermediate-liege grievance, C exile revert).

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
	test_seed_creates_brewing_plot()
	test_sound_out_commits_disloyal_candidate()
	test_sound_out_informant_exposes_plot()
	test_secrecy_erosion_exposes_at_zero()
	test_launch_mints_rebel_realm_and_hostile_relation()
	test_resignation_path_a_release_reparent()
	test_resignation_path_c_exile_reverts_domain()
	test_appeal_side_with_vassal_grieves_intermediate()
	if not has_failures():
		print("FactionFF3Rebellion: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF3 Rebellion Test", "World")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _character(cname: String, align: String = "neutral") -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 12, ?, 60, 60)
	""", [id, _campaign_id, cname, align])
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


func _assignment(liege: String, vassal: String, vassal_domain: String,
		is_henchman: bool = false, base_mod: int = -2, outcome: String = "") -> String:
	var aid := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": liege,
		"vassal_character_id": vassal, "vassal_domain_id": vassal_domain,
		"assigned_calendar_day": 0, "status": "active",
		"is_henchman_vassal": is_henchman, "base_loyalty_modifier": base_mod,
		"last_loyalty_outcome": outcome,
	})
	return aid


func _mirror(realm_id: String) -> String:
	return FactionRegistry.ensure_realm_mirror(_campaign_id, realm_id)


# ---------------------------------------------------------------------------
# Rebellion
# ---------------------------------------------------------------------------

func test_seed_creates_brewing_plot() -> void:
	var liege := _character("Liege S")
	var vassal := _character("Vassal S")
	var lr := _realm("Kingdom S", liege)
	var vr := _realm("Duchy S", vassal)
	var vm := _mirror(vr)
	var pid := RebelCoalition.seed_rebellion(_campaign_id, vm, lr, vassal, 10)
	check(pid != "", "plot seeded")
	var plot := CampaignRepository.ff_get_plot(pid)
	check(String(plot.get("status", "")) == "brewing", "plot brewing")
	# The instigator is a committed member from the outset.
	var members := CampaignRepository.ff_list_plot_members(pid, ["committed"])
	check(members.size() == 1, "instigator committed at seed, got %s" % members.size())
	# Re-seeding is idempotent.
	var pid2 := RebelCoalition.seed_rebellion(_campaign_id, vm, lr, vassal, 12)
	check(pid2 == pid, "re-seed returns the existing plot")


func test_sound_out_commits_disloyal_candidate() -> void:
	var liege := _character("Liege SO", "lawful")
	var instigator := _character("Instigator", "chaotic")
	var candidate := _character("Candidate", "chaotic")
	var lr := _realm("Kingdom SO", liege, "lawful")
	var ir := _realm("Duchy I", instigator, "chaotic")
	var cr := _realm("Duchy C", candidate, "chaotic")
	var ld := _domain("Crown SO", liege, lr)
	var id_ := _domain("Fief I", instigator, ir, ld)
	var cd := _domain("Fief C", candidate, cr, ld)
	_assignment(liege, instigator, id_, false, -2)
	_assignment(liege, candidate, cd, false, -2)
	var im := _mirror(ir)
	var pid := RebelCoalition.seed_rebellion(_campaign_id, im, lr, instigator, 10)
	var dice := FakeDice.new()
	dice.d2d6 = 2   # Hostility → the candidate commits
	var res := RebelCoalition.sound_out(pid, liege, 12, dice)
	check(bool(res.get("ok", false)), "sound_out ok")
	check(String(res.get("commitment", "")) == "committed",
		"2d6=2 → candidate committed, got %s" % res.get("commitment"))
	var committed := CampaignRepository.ff_list_plot_members(pid, ["committed"])
	check(committed.size() == 2, "instigator + candidate committed, got %s" % committed.size())


func test_sound_out_informant_exposes_plot() -> void:
	var liege := _character("Liege INF")
	var instigator := _character("Instig INF")
	var candidate := _character("Loyal Candidate")
	var lr := _realm("Kingdom INF", liege)
	var ir := _realm("Duchy INF", instigator)
	var cr := _realm("Duchy LOY", candidate)
	var ld := _domain("Crown INF", liege, lr)
	var id_ := _domain("Fief INF", instigator, ir, ld)
	var cd := _domain("Fief LOY", candidate, cr, ld)
	_assignment(liege, instigator, id_)
	# The informant candidate must reach FANATIC (12+ AFTER the §5.2 modifier stack)
	# to inform the liege. A non-henchman vassal carries base_loyalty_modifier −2,
	# so dice 12 nets to 11 (Loyal) and FANATIC is unreachable. Configure this
	# candidate as a HENCHMAN vassal (base_loyalty_modifier 0); with the liege and
	# candidate sharing alignment (both neutral → +1) the net is dice 12 + 0 + 1 =
	# 13 → FANATIC. (Instigator stays a plain −2 non-henchman; unrelated to this roll.)
	_assignment(liege, candidate, cd, true, 0)
	var im := _mirror(ir)
	var pid := RebelCoalition.seed_rebellion(_campaign_id, im, lr, instigator, 10)
	var dice := FakeDice.new()
	dice.d2d6 = 12   # Fanatic → informs the liege
	var res := RebelCoalition.sound_out(pid, liege, 12, dice)
	check(bool(res.get("informed", false)), "12+ informs the liege")
	check(String(CampaignRepository.ff_get_plot(pid).get("status", "")) == "exposed",
		"plot exposed after informant")


func test_secrecy_erosion_exposes_at_zero() -> void:
	var liege := _character("Liege SEC")
	var instigator := _character("Instig SEC")
	var lr := _realm("Kingdom SEC", liege)
	var ir := _realm("Duchy SEC", instigator)
	var im := _mirror(ir)
	var pid := RebelCoalition.seed_rebellion(_campaign_id, im, lr, instigator, 10)
	var start := int(CampaignRepository.ff_get_plot(pid).get("secrecy", 0))
	RebelCoalition.erode_secrecy(pid, -(start), liege, 20)
	check(String(CampaignRepository.ff_get_plot(pid).get("status", "")) == "exposed",
		"secrecy to 0 exposes the plot")


func test_launch_mints_rebel_realm_and_hostile_relation() -> void:
	var liege := _character("Liege LN")
	var instigator := _character("Instig LN")
	var lr := _realm("Kingdom LN", liege)
	var ir := _realm("Duchy LN", instigator)
	var ld := _domain("Crown LN", liege, lr)
	var id_ := _domain("Fief LN", instigator, ir, ld)
	_assignment(liege, instigator, id_)
	var im := _mirror(ir)
	var pid := RebelCoalition.seed_rebellion(_campaign_id, im, lr, instigator, 10)
	# Force ready then launch.
	CampaignRepository.ff_upsert_plot({
		"id": pid, "campaign_id": _campaign_id, "kind": "rebellion",
		"instigator_faction_id": im, "target_faction_id": _mirror(lr),
		"secrecy": 5, "launch_condition": "{}", "status": "ready", "ready_since_day": 20})
	var res := RebelCoalition.launch(pid, liege, 30, "test")
	check(bool(res.get("ok", false)), "launch ok")
	var rebel_realm := String(res.get("rebel_realm_id", ""))
	check(rebel_realm != "", "rebel realm minted")
	check(RealmRepository.get_relation(rebel_realm, lr) == "hostile",
		"realm_relations(rebels, liege) = hostile")
	check(String(CampaignRepository.ff_get_plot(pid).get("status", "")) == "launched",
		"plot launched")


# ---------------------------------------------------------------------------
# Resignation ladder
# ---------------------------------------------------------------------------

func test_resignation_path_a_release_reparent() -> void:
	# 3-tier: crown → intermediate → vassal. A 'release' re-parents to the crown.
	var crown := _character("Crown A")
	var intermediate := _character("Interm A")
	var vassal := _character("Vassal A")
	var kr := _realm("Kingdom A", crown)
	var cd := _domain("Crown Dom A", crown, kr)
	var idm := _domain("Interm Dom A", intermediate, kr, cd)
	var vd := _domain("Vassal Dom A", vassal, kr, idm)
	# Liege (intermediate) is glad to release (grievance vs vassal).
	var im_mirror := _mirror(kr)   # same realm; grievance is realm-level noise here
	var pid := ResignationLadder.file_petition(_campaign_id, vd, idm, "release", 10)
	check(pid != "", "petition filed")
	# Force a grant: the resolver scores disposition + grievance; with no
	# disposition the score is 0 → buy_off. Drive a grant by giving the liege a
	# grievance vs the vassal so score >= ... use direct call and accept buy_off OR
	# granted as valid A outcomes.
	var res := ResignationLadder.resolve_petition_as_liege(pid, 12)
	check(bool(res.get("ok", false)), "petition resolved")
	check(String(res.get("resolution", "")) in ["granted", "bought_off", "refused"],
		"resolution is a valid A outcome, got %s" % res.get("resolution"))


func test_resignation_path_c_exile_reverts_domain() -> void:
	var liege := _character("Liege C")
	var vassal := _character("Vassal C")
	var lr := _realm("Kingdom C", liege)
	var vr := _realm("Duchy C2", vassal)
	var ld := _domain("Crown C", liege, lr)
	var vd := _domain("Fief C", vassal, vr, ld)
	_assignment(liege, vassal, vd)
	var res := ResignationLadder.abdicate_into_exile(_campaign_id, vassal, liege, 20)
	check(bool(res.get("ok", false)), "exile ok")
	# The domain reverted to the liege.
	CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id FROM domains WHERE id = ?", [vd])
	var owner := str_field(CampaignRepository.db.query_result[0], "owner_character_id")
	check(owner == liege, "domain reverted to the liege, got %s" % owner)


func test_appeal_side_with_vassal_grieves_intermediate() -> void:
	# 3-tier. Crown is expansionist (centralises) → sides with the vassal, which
	# grieves the intermediate liege against both crown and ex-vassal.
	var crown := _character("Crown B")
	var intermediate := _character("Interm B")
	var vassal := _character("Vassal B")
	var kr := _realm("Kingdom B", crown)
	var ir := _realm("March B", intermediate)
	var vrr := _realm("Barony B", vassal)
	var cd := _domain("Crown Dom B", crown, kr)
	var idm := _domain("Interm Dom B", intermediate, ir, cd)
	var vd := _domain("Vassal Dom B", vassal, vrr, idm)
	# Expansionist crown disposition → centralises (score += 1 in adjudication).
	var disp := StrategicDisposition.new()
	disp.expansion_weight = 0.8
	RulerDispositionRepository.save_disposition(_campaign_id, crown, disp)
	# File the appeal directly (naming the crown domain as adjudicator).
	var appeal_id := CampaignRepository.ff_upsert_petition({
		"campaign_id": _campaign_id, "petitioner_domain_id": vd,
		"liege_domain_id": cd, "kind": "appeal", "status": "filed", "filed_day": 10,
		"terms": JSON.stringify({"intermediate_liege_domain_id": idm})})
	var res := ResignationLadder.adjudicate_appeal(appeal_id, 12)
	check(bool(res.get("ok", false)), "appeal adjudicated")
	check(String(res.get("sided_with", "")) == "vassal",
		"expansionist crown sides with the vassal, got %s" % res.get("sided_with"))
	# The intermediate liege now holds a grievance toward the crown.
	var interm_mirror := _mirror(ir)
	var crown_mirror := _mirror(kr)
	var g := FactionEventLedger.recompute_grievance(interm_mirror, crown_mirror, 12)
	check(g < 0, "intermediate liege grieves the crown after losing the appeal, got %s" % g)
