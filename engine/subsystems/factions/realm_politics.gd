class_name RealmPolitics
extends RefCounted

## Faction FF-3.c — the realm-politics step (gdd-faction-framework.md §5.4). Runs
## INSIDE a sovereign's monthly turn (RulerAI.process_campaign_month), NOT as a
## separate tick pass — vassals act only through loyalty/compliance, which keeps
## cost linear. For a sovereign ruler each month it:
##   1. evaluates standing treaties (renewal on succession/grievance, expiry),
##   2. resolves received diplomacy proposals + adjudicates appeals to the crown,
##   3. resolves A-petitions filed against the sovereign as liege,
##   4. processes plot intelligence (informant reports → counter-plot Favors &
##      Duties moves: revoke a plotter's grant, demand hostage duty, pre-emptive
##      tribute relief — arrest out of v1 scope),
##   5. advances any rebellion the sovereign's OWN vassals are brewing against
##      them (SOUND OUT one candidate, READY check, LAUNCH on trigger).
##
## Diplomacy ACTION selection/execution itself rides the ruler-AI planner (the
## catalog offers the candidates, the scorer ranks, RulerAI dispatches via
## RealmDiplomacyActions.execute) — this step handles the REACTIVE realm politics
## (treaties/petitions/plots) that isn't a scored planner action.
##
## Determinism: seeded per-(ruler, month) RNG for any roll; no wall-clock.

## Run the realm-politics step for one sovereign. [param ruler_id] is the sovereign
## character; [param calendar_day] the tick day; [param dice] the shared roll seam
## (a FakeDice in tests; a runtime DiceSystem or null in production). Returns a
## report dict of what happened (for the ruler turn report + Seam-A narration).
static func process_sovereign(ruler_id: String, calendar_day: int, dice = null) -> Dictionary:
	var report: Dictionary = {
		"ruler_id": ruler_id,
		"treaties_renewed": 0, "treaties_expired": 0,
		"petitions_resolved": [], "appeals_adjudicated": [],
		"plots_advanced": [], "counter_plots": [],
	}
	var realm: Dictionary = RealmRepository.get_realm_for_character(ruler_id)
	var realm_id: String = String(realm.get("id", ""))
	var campaign_id: String = String(realm.get("campaign_id", ""))
	if realm_id == "" or campaign_id == "":
		return report

	_process_treaties(realm_id, calendar_day, dice, report)
	_process_petitions(ruler_id, calendar_day, report)
	_process_appeals(ruler_id, calendar_day, report)
	_process_own_vassal_plots(campaign_id, ruler_id, calendar_day, dice, report)
	return report


# ---------------------------------------------------------------------------
# 1. Standing treaties (renewal / expiry)
# ---------------------------------------------------------------------------

## Re-check the sovereign's active treaties. A fixed-term treaty past its expiry
## rolls renewal; an indefinite treaty is left to event-driven renewal (succession
## / grievance) which the caller fires — here we only handle expiry.
static func _process_treaties(realm_id: String, day: int, dice, report: Dictionary) -> void:
	for treaty_v in CampaignRepository.ff_list_active_treaties_for_realm(realm_id):
		var treaty: Dictionary = treaty_v
		var duration_v: Variant = treaty.get("duration_months")
		if duration_v == null or int(duration_v) <= 0:
			continue   # indefinite — event-driven, not expiry-driven
		var signed: int = int(treaty.get("signed_day", 0))
		var expiry_day: int = signed + int(duration_v) * TreatyResolver.DAYS_PER_MONTH
		if day < expiry_day:
			continue
		var res: Dictionary = TreatyResolver.renew_treaty(String(treaty.get("id", "")), day, dice)
		if bool(res.get("kept", false)):
			report["treaties_renewed"] = int(report["treaties_renewed"]) + 1
		else:
			report["treaties_expired"] = int(report["treaties_expired"]) + 1


# ---------------------------------------------------------------------------
# 2/3. Petitions + appeals filed against this sovereign
# ---------------------------------------------------------------------------

static func _process_petitions(ruler_id: String, day: int, report: Dictionary) -> void:
	for domain in _domains_owned_by(ruler_id):
		for petition in CampaignRepository.ff_list_open_petitions_for_liege(String(domain.get("id", ""))):
			if String((petition as Dictionary).get("kind", "")) == "appeal":
				continue   # appeals handled in _process_appeals
			var res: Dictionary = ResignationLadder.resolve_petition_as_liege(
				String((petition as Dictionary).get("id", "")), day)
			(report["petitions_resolved"] as Array).append(res)


static func _process_appeals(ruler_id: String, day: int, report: Dictionary) -> void:
	for domain in _domains_owned_by(ruler_id):
		for petition in CampaignRepository.ff_list_open_petitions_for_liege(String(domain.get("id", ""))):
			if String((petition as Dictionary).get("kind", "")) != "appeal":
				continue
			var res: Dictionary = ResignationLadder.adjudicate_appeal(
				String((petition as Dictionary).get("id", "")), day)
			(report["appeals_adjudicated"] as Array).append(res)


# ---------------------------------------------------------------------------
# 4/5. Plot intelligence + advancing the sovereign's own-vassal rebellions
# ---------------------------------------------------------------------------

## For every brewing/recruiting/ready rebellion plot targeting THIS sovereign's
## realm mirror: (a) if an informant has exposed enough, run a counter-plot Favors
## & Duties move (revoke a plotter's grant); (b) advance the plot one step (sound
## out → ready check → launch on trigger). This is the sovereign's own-vassal
## rebellion machinery (§5.7), driven from their turn.
static func _process_own_vassal_plots(campaign_id: String, ruler_id: String,
		day: int, dice, report: Dictionary) -> void:
	var my_mirror: String = _realm_mirror_for_character(campaign_id, ruler_id)
	if my_mirror == "":
		return
	for plot_v in CampaignRepository.ff_list_plots_for_campaign(
			campaign_id, ["brewing", "recruiting", "ready", "exposed"]):
		var plot: Dictionary = plot_v
		if String(plot.get("kind", "")) != "rebellion":
			continue
		if String(plot.get("target_faction_id", "")) != my_mirror:
			continue
		var plot_id: String = String(plot.get("id", ""))
		var status: String = String(plot.get("status", ""))

		# 4. Counter-plot: an exposed plot lets the liege revoke a plotter's grant
		# (a Favors & Duties move — arrest is out of v1 scope, §5.4).
		if status == "exposed":
			var counter: Dictionary = _counter_plot(campaign_id, ruler_id, plot_id, day)
			(report["counter_plots"] as Array).append(counter)
			# An exposed-and-ready plot force-launches; an exposed-not-ready one may
			# be abandoned by the instigator (v1: leave it exposed for next month).
			continue

		# 5. Advance: SOUND OUT one candidate, then READY check, then LAUNCH.
		if status in ["brewing", "recruiting"]:
			var sound: Dictionary = RebelCoalition.sound_out(plot_id, ruler_id, day, dice)
			(report["plots_advanced"] as Array).append({"plot_id": plot_id, "sound_out": sound})
			# Re-read: sound_out may have exposed the plot (informant / secrecy 0).
			plot = CampaignRepository.ff_get_plot(plot_id)
			status = String(plot.get("status", ""))
			if status in ["brewing", "recruiting"]:
				RebelCoalition.check_ready(plot_id, ruler_id, day)
		elif status == "ready":
			var trigger: String = RebelCoalition.launch_trigger_ready(plot_id, day)
			if trigger != "":
				var launch: Dictionary = RebelCoalition.launch(plot_id, ruler_id, day, trigger)
				(report["plots_advanced"] as Array).append({"plot_id": plot_id, "launch": launch})


## Counter-plot Favors & Duties move (§5.4): revoke the most-recent grant of a
## committed plotter (a plotter's revoke duty is the RAW lever). v1: for the first
## committed non-instigator member, mark the member's vassal edge under-compliance
## (the visible smoke) — full grant-revocation rides the favors-and-duties path
## which needs the plotter's assignment; recorded as an intent here.
static func _counter_plot(campaign_id: String, ruler_id: String, plot_id: String, day: int) -> Dictionary:
	var revoked: int = 0
	for m in CampaignRepository.ff_list_plot_members(plot_id, ["committed"]):
		var member_faction: Dictionary = CampaignRepository.get_faction(
			String((m as Dictionary).get("faction_id", "")))
		var member_head: String = String(member_faction.get("leader_npc_id", ""))
		if member_head == "":
			continue
		var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(member_head)
		if assn.is_empty() or String(assn.get("liege_character_id", "")) != ruler_id:
			continue
		# Revoke the plotter's most recent favor (the RAW lever), if any.
		var favor: Dictionary = VassalObligationsRepository.most_recent_active(
			String(assn.get("id", "")), "favor")
		if not favor.is_empty():
			VassalObligationsRepository.set_status(String(favor.get("id", "")), "revoked", day)
			revoked += 1
	return {"plot_id": plot_id, "grants_revoked": revoked}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _domains_owned_by(character_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id",
		[character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _realm_mirror_for_character(campaign_id: String, character_id: String) -> String:
	var realm: Dictionary = RealmRepository.get_realm_for_character(character_id)
	var realm_id: String = String(realm.get("id", ""))
	if realm_id == "":
		return ""
	return FactionRegistry.ensure_realm_mirror(campaign_id, realm_id)
