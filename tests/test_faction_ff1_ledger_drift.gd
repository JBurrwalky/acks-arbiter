extends "res://tests/test_suite_base.gd"

## Faction Framework FF-1.3 (gdd-faction-framework.md §4.5, §5.6, §8.3, §11.7) —
## the event ledger + grievance recompute, the realm_relations drift writer, and
## §8.3 reputation propagation. NOT executed by this build session; registered
## for the central run.
##
## Covers: ledger append + decayed grievance recompute (banker's rounding),
## betrayal permanence, one-band-per-cluster conquest drift (no double-move same
## month), vassal-revolt drift, quiet-decay to structural default (and stop),
## and awareness-gated half/inverted-half reputation propagation.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_ledger_grievance_decayed_sum()
	test_betrayal_permanent_contribution()
	test_conquest_drift_one_band_per_cluster()
	test_second_conquest_same_month_no_double_move()
	test_vassal_revolt_drift()
	test_quiet_decay_to_default_and_stop()
	test_reputation_propagation_weights_and_gate()
	if not has_failures():
		print("FactionFF1LedgerDrift: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF1 Ledger Test", "World")
	DefaultStanceEvaluator.reset_matrix_cache()


func _org(name: String, ftype: String, align: String, settlement: String = "",
		realm_id: String = "") -> String:
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = name
	f.faction_type = ftype
	f.alignment = align
	f.scope = "organization"
	f.seat_settlement_id = settlement
	f.realm_id = realm_id
	return CampaignRepository.create_faction(f)


func _character(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, cname])
	return id


func _realm(rname: String, head: String, align: String) -> String:
	return RealmRepository.create_realm({
		"campaign_id": _campaign_id, "name": rname, "head_character_id": head,
		"alignment": align, "realm_kind": "tracked",
	})


func _domain_for(rname: String, head: String, realm_id: String) -> String:
	var did: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": rname, "owner_character_id": head,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET realm_id = ? WHERE id = ?", [realm_id, did])
	return did


func test_ledger_grievance_decayed_sum() -> void:
	var actor := _org("Actor", "syndicate", "chaotic")
	var target := _org("Target", "temple", "lawful")
	# Two expiring deeds; recompute the target→actor grievance at the deed day
	# (full magnitude) — sum = -4 + -2 = -6.
	FactionEventLedger.record(_campaign_id, 100, actor, target, "member_killed", -4)
	FactionEventLedger.record(_campaign_id, 100, actor, target, "op_discovered", -2)
	var g := FactionEventLedger.recompute_grievance(target, actor, 100)
	check(g == -6, "grievance = sum of full magnitudes at deed day, got %s" % g)
	# Halfway to expiry (60 months = 1680 days; midpoint day 940) the linear
	# decay halves each contribution → banker's-rounded -3.
	var g_mid := FactionEventLedger.recompute_grievance(target, actor, 100 + 840)
	check(g_mid == -3, "grievance decays linearly to -3 at midpoint, got %s" % g_mid)


func test_betrayal_permanent_contribution() -> void:
	var actor := _org("Betrayer", "mage_guild", "neutral")
	var target := _org("Betrayed", "mercenary_company", "neutral")
	FactionEventLedger.record(_campaign_id, 10, actor, target, "betrayal_executed", -10)
	# Far in the future — a betrayal never decays.
	var g := FactionEventLedger.recompute_grievance(target, actor, 10 + 100000)
	check(g == -10, "betrayal_executed contributes -10 permanently, got %s" % g)


func test_conquest_drift_one_band_per_cluster() -> void:
	var atk_head := _character("Attacker Sov")
	var def_head := _character("Defender Sov")
	var atk_realm := _realm("Attacker Realm", atk_head, "chaotic")
	var def_realm := _realm("Defender Realm", def_head, "lawful")
	FactionRegistry.ensure_realm_mirror(_campaign_id, atk_realm)
	FactionRegistry.ensure_realm_mirror(_campaign_id, def_realm)
	var def_domain := _domain_for("Defender Domain", def_head, def_realm)
	# Baseline neutral. One conquest → one band hostile-ward (neutral→unfriendly).
	var moved := RealmRelationsDrift.apply_conquest_drift(
		_campaign_id, def_domain, atk_head, "occupied", 500)
	check(moved, "conquest drift applied")
	var disp := RealmRepository.get_relation(atk_realm, def_realm)
	check(disp == "unfriendly", "neutral→unfriendly one band, got %s" % disp)


func test_second_conquest_same_month_no_double_move() -> void:
	var atk_head := _character("Atk2")
	var def_head := _character("Def2")
	var atk_realm := _realm("Atk2 Realm", atk_head, "chaotic")
	var def_realm := _realm("Def2 Realm", def_head, "lawful")
	FactionRegistry.ensure_realm_mirror(_campaign_id, atk_realm)
	FactionRegistry.ensure_realm_mirror(_campaign_id, def_realm)
	var def_domain := _domain_for("Def2 Domain", def_head, def_realm)
	# Two conquests in the SAME calendar month: (500-1)/28 == (502-1)/28 == 17.
	# Only the FIRST moves a band (one band per event cluster, §5.6).
	RealmRelationsDrift.apply_conquest_drift(_campaign_id, def_domain, atk_head, "occupied", 500)
	var second := RealmRelationsDrift.apply_conquest_drift(_campaign_id, def_domain, atk_head, "salted_to_ruin", 502)
	check(not second, "second event same month does not drift again")
	var disp := RealmRepository.get_relation(atk_realm, def_realm)
	check(disp == "unfriendly", "still only one band moved this month, got %s" % disp)


func test_vassal_revolt_drift() -> void:
	var v_head := _character("Vassal Sov")
	var l_head := _character("Liege Sov")
	var v_realm := _realm("Vassal Realm", v_head, "neutral")
	var l_realm := _realm("Liege Realm", l_head, "lawful")
	FactionRegistry.ensure_realm_mirror(_campaign_id, v_realm)
	FactionRegistry.ensure_realm_mirror(_campaign_id, l_realm)
	var moved := RealmRelationsDrift.apply_revolt_drift(_campaign_id, v_realm, l_realm, 900)
	check(moved, "revolt drift applied")
	check(RealmRepository.get_relation(v_realm, l_realm) == "unfriendly",
		"revolt drifts one band hostile-ward")


func test_quiet_decay_to_default_and_stop() -> void:
	var a_head := _character("Decay Sov A")
	var b_head := _character("Decay Sov B")
	# One lawful, one neutral realm → alignment one-step (0) + no religion/culture
	# → structural default score 0 → band NEUTRAL (the decay target).
	var ra := _realm("Decay Realm A", a_head, "lawful")
	var rb := _realm("Decay Realm B", b_head, "neutral")
	FactionRegistry.ensure_realm_mirror(_campaign_id, ra)
	FactionRegistry.ensure_realm_mirror(_campaign_id, rb)
	# Force to hostile at day 0. Structural default for this pair is neutral, so
	# decay walks hostile → unfriendly → neutral and STOPS at neutral.
	RealmRepository.set_relation(ra, rb, "hostile", 0)
	var day12 := 12 * 28
	var d1 := RealmRelationsDrift.process_campaign_month(_campaign_id, day12)
	check(d1 >= 1, "at least one pair decayed after 12 quiet months")
	check(RealmRepository.get_relation(ra, rb) == "unfriendly", "hostile→unfriendly one band")
	# Another 12 quiet months → neutral (the default), and it STOPS there.
	RealmRelationsDrift.process_campaign_month(_campaign_id, day12 * 2)
	check(RealmRepository.get_relation(ra, rb) == "neutral", "unfriendly→neutral (default)")
	RealmRelationsDrift.process_campaign_month(_campaign_id, day12 * 3)
	check(RealmRepository.get_relation(ra, rb) == "neutral", "decay stops at the default")


func test_reputation_propagation_weights_and_gate() -> void:
	var party := CampaignRepository.create_party(_campaign_id, "Test Party")
	var rep := ReputationSystem.new(CampaignRepository, _campaign_id, party)
	# Target org, a friendly ally sharing the settlement (aware), a hostile
	# counterparty sharing the settlement (aware), and a distant org with NO
	# awareness (should NOT receive an echo).
	var target := _org("Target Org", "temple", "lawful", "cyfaraun")
	var ally := _org("Ally Org", "holy_order", "lawful", "cyfaraun")
	var enemy := _org("Enemy Org", "syndicate", "chaotic", "cyfaraun")
	var distant := _org("Distant Org", "temple", "lawful", "faraway")
	# Instantiate the stances so band lookups are deterministic.
	FactionStanceService.instantiate_stance(_campaign_id, ally, target, "friendly", "t")
	FactionStanceService.instantiate_stance(_campaign_id, enemy, target, "hostile", "t")
	FactionStanceService.instantiate_stance(_campaign_id, distant, target, "friendly", "t")
	# A +8 deed toward the target. Half weight = +4 to friendly-aware,
	# inverted-half = -4 to hostile-aware, nothing to the distant (no awareness
	# via settlement/realm — but it HAS an instantiated row, so it IS aware).
	rep.apply_faction_deed(target, 8, "aided the temple")
	check(rep.get_score(ReputationEntry.SCOPE_FACTION, target) == 8, "target full weight +8")
	check(rep.get_score(ReputationEntry.SCOPE_FACTION, ally) == 4, "ally half weight +4")
	check(rep.get_score(ReputationEntry.SCOPE_FACTION, enemy) == -4, "enemy inverted-half -4")
	# The distant org holds an instantiated friendly stance row → that row IS an
	# awareness channel per §8.3, so it receives +4 (awareness via stance row,
	# NOT global telepathy).
	check(rep.get_score(ReputationEntry.SCOPE_FACTION, distant) == 4,
		"distant-but-stance-linked org aware via its instantiated row")


func _party_score(rep, fid: String) -> int:
	return rep.get_score(ReputationEntry.SCOPE_FACTION, fid)
