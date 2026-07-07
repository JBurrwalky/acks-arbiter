class_name PlayerVassalService
extends RefCounted

## Faction FF-3.e — the player-as-vassal mirror (gdd-faction-framework.md §5.8).
## A PC (or party member) who swears fealty gets a faction_memberships row
## (role='vassal') in the liege's realm-mirror faction, receives the monthly d20
## Favors & Duties roll from the NPC liege (the SAME RAW table via
## FavorsDutiesResolver), and answers demands THROUGH PLAY rather than a loyalty
## roll — refusal writes grievance and may trigger revocation/outlawry through the
## liege's realm-politics step. Rebellion plots may solicit a player-vassal; the
## player's join / decline / inform writes the same faction_plot_members rows an
## NPC roll would.
##
## This is per-character (each party member joins individually — the drama engine
## for divided loyalties, §8.4). No LLM; the solicitation SURFACES as content
## (dialogue/quest), and this service records the player's chosen answer.

## Swear a PC/party-member as a vassal of an NPC liege. Requires a real
## vassal_assignments row (the mechanical vassal edge) so the RAW Favors & Duties
## + loyalty machinery treats the player exactly like an NPC vassal; ADDITIONALLY
## writes the faction_memberships mirror row (role='vassal') in the liege realm's
## mirror faction so the faction layer sees the membership. Returns the membership
## success + the assignment id.
static func swear_fealty(campaign_id: String, pc_character_id: String,
		liege_character_id: String, vassal_domain_id: String, day: int,
		is_henchman: bool = false) -> Dictionary:
	if campaign_id == "" or pc_character_id == "" or liege_character_id == "":
		return {"ok": false, "error": "missing_ids"}
	# 1. The mechanical vassal edge (RAW loyalty/favors machinery).
	var assn_id: String = VassalRepository.create_assignment({
		"campaign_id": campaign_id,
		"liege_character_id": liege_character_id,
		"vassal_character_id": pc_character_id,
		"vassal_domain_id": vassal_domain_id,
		"assigned_calendar_day": day,
		"status": "active",
		"is_henchman_vassal": is_henchman,
		# Non-henchman vassal base −2 per RAW (§2.2); henchman base 0.
		"base_loyalty_modifier": 0 if is_henchman else -2,
	})
	# 2. The faction-layer mirror membership (role='vassal') in the liege realm.
	var liege_realm: Dictionary = RealmRepository.get_realm_for_character(liege_character_id)
	var liege_mirror: String = FactionRegistry.ensure_realm_mirror(
		campaign_id, String(liege_realm.get("id", "")))
	var member_ok: bool = false
	if liege_mirror != "":
		member_ok = CampaignRepository.ff_upsert_membership(liege_mirror, pc_character_id, {
			"role": "vassal", "status": "member", "joined_day": day,
		})
	return {"ok": assn_id != "" and member_ok, "vassal_assignment_id": assn_id,
		"liege_mirror_faction_id": liege_mirror}


## The monthly d20 Favors & Duties roll from the NPC liege to a player-vassal —
## the SAME RAW table an NPC vassal gets (§5.8). Reuses FavorsDutiesResolver
## unchanged; the player answers the resulting demand through play. Returns the
## favors-and-duties outcome dict. [param dice] is the shared roll seam.
static func monthly_favors_and_duties(vassal_assignment_id: String, calendar_day: int,
		dice = null, scheduler = null) -> Dictionary:
	return FavorsDutiesResolver.roll_monthly(vassal_assignment_id, calendar_day, dice, scheduler)


## The player refuses a favors-and-duties demand (answered through play, §5.8):
## writes a grievance the liege holds toward the player-vassal's realm mirror and
## bumps the edge toward under-compliance. May trigger revocation/outlawry on the
## liege's next realm-politics step (the grievance feeds that scoring). Returns
## {ok, grievance_written}.
static func refuse_demand(campaign_id: String, pc_character_id: String,
		liege_character_id: String, day: int) -> Dictionary:
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(pc_character_id)
	if not assn.is_empty():
		VassalRepository.db_set_compliance(String(assn.get("id", "")),
			VassalLoyaltyResolver.BEHAVIOR_UNDER)
	# Grievance: the liege remembers the refusal (liege = observer, player = subject).
	var pc_mirror: String = _party_or_pc_mirror(campaign_id, pc_character_id)
	var liege_realm: Dictionary = RealmRepository.get_realm_for_character(liege_character_id)
	var liege_mirror: String = FactionRegistry.ensure_realm_mirror(
		campaign_id, String(liege_realm.get("id", "")))
	var wrote: bool = false
	if liege_mirror != "" and pc_mirror != "":
		FactionEventLedger.record(campaign_id, day, pc_mirror, liege_mirror, "persecution",
			-2, JSON.stringify({"source": "player_vassal_refusal"}))
		wrote = true
	return {"ok": true, "grievance_written": wrote}


## A rebellion plot solicits the player-vassal; the player's answer writes the same
## faction_plot_members row an NPC roll would (§5.8). [param answer] is one of:
##   "join"   → commitment='committed'
##   "decline"→ no member row (silent decline)
##   "inform" → the player informs the liege → the plot is exposed (like the NPC
##              12+ informant outcome, §7.4)
## Returns {ok, answer, plot_status}.
static func answer_solicitation(plot_id: String, pc_character_id: String, answer: String,
		liege_character_id: String, day: int) -> Dictionary:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty():
		return {"ok": false, "error": "plot_missing"}
	var campaign_id: String = String(plot.get("campaign_id", ""))
	var pc_mirror: String = _party_or_pc_mirror(campaign_id, pc_character_id)
	match answer:
		"join":
			if pc_mirror != "":
				CampaignRepository.ff_upsert_plot_member(plot_id, pc_mirror, "committed", day)
		"decline":
			pass   # silent decline — no member row
		"inform":
			# Player informs the liege → expose the plot (the NPC 12+ path, §7.4).
			RebelCoalition.expose(plot_id, liege_character_id, day, "player_informant")
		_:
			return {"ok": false, "error": "bad_answer"}
	var updated: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	return {"ok": true, "answer": answer, "plot_status": String(updated.get("status", ""))}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## The mirror faction a player-vassal's plot membership rides. A PC who has founded
## a realm has a realm mirror; absent one, fall back to the PC's own realm mirror
## (through the character), or "" when the PC holds no realm. (Party-scope faction
## rows are a §8.4 concept; v1 uses the PC's realm mirror.)
static func _party_or_pc_mirror(campaign_id: String, pc_character_id: String) -> String:
	var realm: Dictionary = RealmRepository.get_realm_for_character(pc_character_id)
	var realm_id: String = String(realm.get("id", ""))
	if realm_id == "":
		return ""
	return FactionRegistry.ensure_realm_mirror(campaign_id, realm_id)
