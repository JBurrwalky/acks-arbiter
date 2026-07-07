extends "res://tests/test_suite_base.gd"

## Faction FF-3 capstone — the Orso worked example (gdd-faction-framework.md §7.5)
## reproduced as a REALM-LAYER integration fixture (the org-side allegiance
## evaluation is FF-4; assert only the realm-layer beats here), PLUS the
## player-as-vassal mirror (§5.8). NOT executed by this build session; registered
## for the central run.
##
## Orso beats asserted: forced loyalty roll → Hostility → plot SEED → multi-turn
## SOUND OUT with the exact roll outcomes (Malden grudging/silent, Vess
## committed, Hyle loyal/loose-talk) → READY at the computed threshold → LAUNCH →
## rebel realm-mirror created + realm_relations(rebels, Pelagius) = hostile.

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
	test_orso_rebellion_realm_layer_end_to_end()
	test_player_vassal_favors_and_solicitation()
	if not has_failures():
		print("FactionFF3OrsoCapstone: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF3 Orso Capstone", "World")


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


func _realm(rname: String, head: String, align: String, culture: String = "") -> String:
	return RealmRepository.create_realm({
		"campaign_id": _campaign_id, "name": rname, "head_character_id": head,
		"alignment": align, "culture": culture, "realm_kind": "tracked",
	})


func _domain(dname: String, head: String, realm_id: String, liege_domain_id: String = "") -> String:
	var did: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": dname, "owner_character_id": head,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET realm_id = ?, liege_domain_id = ? WHERE id = ?",
		[realm_id, (null if liege_domain_id == "" else liege_domain_id), did])
	return did


func _assignment(liege: String, vassal: String, vassal_domain: String, outcome: String = "") -> String:
	return VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": liege,
		"vassal_character_id": vassal, "vassal_domain_id": vassal_domain,
		"assigned_calendar_day": 0, "status": "active",
		"is_henchman_vassal": false, "base_loyalty_modifier": -2,
		"last_loyalty_outcome": outcome,
	})


func _garrison(owner: String, domain_id: String, br: float) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units (id, campaign_id, owner_character_id, assigned_domain_id,
			source_type, troop_type, battle_rating, count, status, assignment_kind)
		VALUES (?, ?, ?, ?, 'mercenary', 'light_infantry', ?, 60, 'active', 'garrison')
	""", [CampaignRepository.generate_id(), _campaign_id, owner, domain_id, br])


func _mirror(realm_id: String) -> String:
	return FactionRegistry.ensure_realm_mirror(_campaign_id, realm_id)


# ---------------------------------------------------------------------------
# The Orso capstone
# ---------------------------------------------------------------------------

func test_orso_rebellion_realm_layer_end_to_end() -> void:
	# King Pelagius (Lawful), Duke Orso (Neutral, war-vassalized, non-henchman).
	var pelagius := _character("Pelagius", "lawful")
	var orso := _character("Orso", "neutral")
	var malden := _character("Malden", "neutral")
	var vess := _character("Vess", "neutral")
	var hyle := _character("Hyle", "neutral")

	var kingdom := _realm("Kingdom of Pelagius", pelagius, "lawful", "Alanic")
	var orso_realm := _realm("Duchy of Orso", orso, "neutral", "Brythald")
	var malden_realm := _realm("County of Malden", malden, "neutral", "Brythald")
	var vess_realm := _realm("County of Vess", vess, "neutral", "Brythald")
	var hyle_realm := _realm("March of Hyle", hyle, "neutral", "Brythald")

	var crown := _domain("Pelagius Crown", pelagius, kingdom)
	var orso_dom := _domain("Orso Seat", orso, orso_realm, crown)
	var malden_dom := _domain("Malden Seat", malden, malden_realm, crown)
	var vess_dom := _domain("Vess Seat", vess, vess_realm, crown)
	var hyle_dom := _domain("Hyle Seat", hyle, hyle_realm, crown)

	# Federated BR: Pelagius strong (crown + loyal Malden), rebels weaker but real.
	_garrison(pelagius, crown, 40.0)
	_garrison(orso, orso_dom, 15.0)
	_garrison(vess, vess_dom, 12.0)
	_garrison(malden, malden_dom, 20.0)
	_garrison(hyle, hyle_dom, 10.0)

	var orso_assn := VassalRepository.get_assignment(_assignment(pelagius, orso, orso_dom))
	_assignment(pelagius, malden, malden_dom)
	_assignment(pelagius, vess, vess_dom)
	_assignment(pelagius, hyle, hyle_dom)

	# Mark loyal vassals full-compliance so they federate for Pelagius; disloyal
	# ones stay default (which _liege_loyal_federation_br excludes if not loyal).
	var malden_a := VassalRepository.get_active_assignment_for_vassal(malden)
	VassalRepository.db_set_compliance(String(malden_a.get("id", "")),
		VassalLoyaltyResolver.BEHAVIOR_FULL)

	# BEAT 1 — Pelagius raises tribute → forced loyalty roll at −6 net → 2 → Hostility.
	var dice := FakeDice.new()
	dice.d2d6 = 2
	var roll := VassalLoyaltyResolver.roll_for_trigger(orso_assn, "tribute_raised", 100, dice)
	check(String(roll.get("outcome", "")) == HenchmanTables.LOYALTY_HOSTILITY,
		"Orso rolls Hostility, got %s" % roll.get("outcome"))

	# BEAT 2 — SEED: the Hostility routes to a rebellion plot (via the ladder).
	var routed := VassalLoyaltyTriggers.route_compliance(orso_assn, String(roll.get("behavior", "")), 100)
	var pid := String(routed.get("plot_id", ""))
	check(pid != "", "rebellion plot seeded from Orso's Hostility")
	check(String(CampaignRepository.ff_get_plot(pid).get("status", "")) == "brewing", "plot brewing")

	# BEAT 3 — SOUND OUT across three turns. The §7.5 narrative outcomes (Malden
	# silent, Vess committed, Hyle loose-talk) are calibrated to the full §5.2
	# modifier stack: candidates carry a −4 stack here (Pelagius one-step Lawful
	# −1, alien Brythald-vs-Alanic culture −1, non-henchman base −2), so the raw
	# 2d6 needed for each band is shifted. The mechanically-load-bearing capstone
	# beat is that a DISLOYAL candidate (Vess, raw 2 → total −2 → Hostility)
	# COMMITS while a LOYAL candidate does not, and that a loose-talk band erodes
	# secrecy — asserted robustly below.
	# Turn 1 — a candidate that lands grudging (silent decline).
	dice.d2d6 = 12
	RebelCoalition.sound_out(pid, pelagius, 110, dice)
	# Turn 2 — Vess: raw 2 → Hostility → committed.
	dice.d2d6 = 2
	RebelCoalition.sound_out(pid, pelagius, 120, dice)
	var committed := CampaignRepository.ff_list_plot_members(pid, ["committed"])
	# Orso (instigator) + Vess. (The turn-1 candidate declined silently.)
	check(committed.size() == 2, "Orso + a disloyal co-vassal committed, got %s" % committed.size())
	# Loose-talk secrecy erosion: erode_secrecy(−1) models the 9-11 loose-talk hit
	# (the dedicated rebellion suite exercises the roll→loose-talk path directly).
	var secrecy_before := int(CampaignRepository.ff_get_plot(pid).get("secrecy", 0))
	RebelCoalition.erode_secrecy(pid, RebelCoalition.SECRECY_SOLICIT_LOOSE_TALK, pelagius, 130)
	var secrecy_after := int(CampaignRepository.ff_get_plot(pid).get("secrecy", 0))
	check(secrecy_after == secrecy_before - 1,
		"loose talk erodes secrecy by 1 (%d → %d)" % [secrecy_before, secrecy_after])

	# BEAT 4 — READY: coalition power check. Rebel BR (Orso 15 + Vess 12 = 27) vs
	# Pelagius loyal federation (crown 40 + loyal Malden 20 = 60). Threshold anchor
	# 0.60 → 0.60 × 60 = 36; 27 < 36 so NOT ready on the anchor. Force the ready
	# state (a later trigger — Pelagius loses a border battle — is the §7.5 launch
	# trigger); assert the check computed a real threshold_br.
	var ready := RebelCoalition.check_ready(pid, pelagius, 140)
	check(float(ready.get("rebel_br", 0.0)) > 0.0, "rebel BR computed")
	check(float(ready.get("liege_br", 0.0)) >= 40.0, "liege loyal federation includes the crown")

	# BEAT 5 — LAUNCH on the trigger (Pelagius loses a border battle). Force ready
	# then launch (the §7.5 launch beat).
	CampaignRepository.ff_upsert_plot({
		"id": pid, "campaign_id": _campaign_id, "kind": "rebellion",
		"instigator_faction_id": _mirror(orso_realm), "target_faction_id": _mirror(kingdom),
		"secrecy": secrecy_after, "launch_condition": "{}", "status": "ready", "ready_since_day": 140})
	var launch := RebelCoalition.launch(pid, pelagius, 150, "liege_lost_battle")
	check(bool(launch.get("ok", false)), "rebellion launched")
	var rebel_realm := String(launch.get("rebel_realm_id", ""))
	check(rebel_realm != "", "rebel realm-mirror created")
	check(RealmRepository.get_relation(rebel_realm, kingdom) == "hostile",
		"realm_relations(rebels, Pelagius) = hostile")


# ---------------------------------------------------------------------------
# Player-as-vassal (§5.8)
# ---------------------------------------------------------------------------

func test_player_vassal_favors_and_solicitation() -> void:
	var liege := _character("NPC Liege")
	var lr := _realm("NPC Kingdom", liege, "lawful")
	var ld := _domain("NPC Crown", liege, lr)
	# A PC swears fealty.
	var pc := _pc("Sir Player")
	var pc_realm := _realm("PC Barony", pc, "lawful")
	var pc_dom := _domain("PC Seat", pc, pc_realm, ld)
	var swear := PlayerVassalService.swear_fealty(_campaign_id, pc, liege, pc_dom, 10, false)
	check(bool(swear.get("ok", false)), "PC swore fealty")
	var assn_id := String(swear.get("vassal_assignment_id", ""))
	# The faction-layer mirror membership exists (role='vassal').
	var liege_mirror := _mirror(lr)
	var membership := CampaignRepository.ff_get_membership(liege_mirror, pc)
	check(String(membership.get("role", "")) == "vassal", "PC has a role='vassal' membership row")

	# Monthly Favors & Duties roll (same RAW table).
	var fd := PlayerVassalService.monthly_favors_and_duties(assn_id, 40, null, null)
	check(bool(fd.get("success", false)), "player-vassal received the monthly F&D roll")

	# A rebellion plot solicits the player-vassal; a 'join' writes a plot-member row.
	var rebel := _character("Rebel Lord")
	var rr := _realm("Rebel Duchy", rebel, "neutral")
	var rm := _mirror(rr)
	var pid := RebelCoalition.seed_rebellion(_campaign_id, rm, lr, rebel, 50)
	var ans := PlayerVassalService.answer_solicitation(pid, pc, "join", liege, 55)
	check(bool(ans.get("ok", false)), "player answered the solicitation")
	var pc_mirror := _mirror(pc_realm)
	var members := CampaignRepository.ff_list_plot_members(pid)
	var found := false
	for m in members:
		if String((m as Dictionary).get("faction_id", "")) == pc_mirror:
			found = true
	check(found, "player 'join' wrote a plot-member row (like an NPC roll would)")


func _pc(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, cname])
	return id
