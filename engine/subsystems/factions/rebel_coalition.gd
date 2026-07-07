class_name RebelCoalition
extends RefCounted

## Faction FF-3.d — rebel coalitions (gdd-faction-framework.md §5.7) + the plot-
## secrecy countdown (§7.4's PLOT half only; the org-side AllegianceEvaluator is
## FF-4). Rebellion is the terminal state of the loyalty machinery, not a random
## event: SEED → SOUND OUT → READY → LAUNCH → RESOLVE on faction_plots /
## faction_plot_members.
##
## The FF-3/FF-4 boundary (handoff §0): FF-3 builds ONLY the secret loyalty rolls
## that recruit coalition members and the plot-secrecy countdown. It does NOT
## build AllegianceEvaluator.evaluate (third-party org side-picking) — that needs
## FF-2's orgs.
##
## Determinism: every solicitation / power check takes an explicit day + the
## shared `dice` seam; the rebel realm-mirror is minted via RealmRegistry +
## FactionRegistry.ensure_realm_mirror (the FF-1 pattern). No wall-clock.

## §7.4 plot secrecy base + adjustments.
const SECRECY_BASE := 10
const SECRECY_SOLICIT_LOOSE_TALK := -1   # 9-11 solicitation outcome
const SECRECY_SPY_FIND := -2
const SECRECY_RUMOR_EMITTED := -1

## §5.7 READY power check (extraction-resistance formula pattern).
const READY_THRESHOLD_ANCHOR := 0.60
const READY_EXPANSION_COEFF := 0.15
const READY_AGGRESSIVE_COEFF := 0.10
const READY_LIEGE_ALLIANCE_COEFF := 0.15

## §5.7 momentum: −1 secret loyalty roll per 2 committed coalition members.
const MOMENTUM_PER_N_COMMITTED := 2

## §5.7 LAUNCH: forced launch after this many months at 'ready'.
const READY_MONTHS_TO_FORCE := 6
const DAYS_PER_MONTH := 28


# ---------------------------------------------------------------------------
# SEED
# ---------------------------------------------------------------------------

## §5.7 SEED: open a rebellion plot with the vassal as instigator against the
## liege realm. Fires on a Hostility (2−) loyalty result or a refused Resignation
## (the caller decides which trigger applies). Idempotent — returns the existing
## active plot id if the instigator already runs one. secrecy starts at
## SECRECY_BASE + the instigator leader's self_interest adjustment (§7.4).
## Returns the plot id, or "".
static func seed_rebellion(campaign_id: String, instigator_faction_id: String,
		liege_realm_id: String, instigator_leader_id: String, day: int) -> String:
	if campaign_id == "" or instigator_faction_id == "":
		return ""
	var existing: Dictionary = CampaignRepository.ff_get_active_plot_by_instigator(
		instigator_faction_id, "rebellion")
	if not existing.is_empty():
		return String(existing.get("id", ""))
	var liege_mirror: String = ""
	if liege_realm_id != "":
		liege_mirror = FactionRegistry.ensure_realm_mirror(campaign_id, liege_realm_id)
	var secrecy: int = SECRECY_BASE + _self_interest_secrecy_adj(instigator_leader_id)
	var plot_id: String = CampaignRepository.ff_upsert_plot({
		"campaign_id": campaign_id,
		"kind": "rebellion",
		"instigator_faction_id": instigator_faction_id,
		"target_faction_id": liege_mirror,
		"secrecy": secrecy,
		"launch_condition": JSON.stringify({"kind": "power_ratio_or_trigger"}),
		"status": "brewing",
		"ready_since_day": 0,
	})
	# The instigator is itself a committed member from the outset.
	if plot_id != "":
		CampaignRepository.ff_upsert_plot_member(plot_id, instigator_faction_id, "committed", day)
		_emit_status(plot_id, "brewing", instigator_faction_id)
	return plot_id


# ---------------------------------------------------------------------------
# SOUND OUT
# ---------------------------------------------------------------------------

## §5.7 SOUND OUT: solicit ONE candidate co-vassal of the liege (lowest current
## loyalty first; only border/culture/alignment-affinity candidates). The
## solicited vassal makes a SECRET loyalty roll toward the LIEGE with the §5.2
## modifiers + momentum (−1 per 2 committed). Outcomes:
##   2−   → committed
##   3-5  → sympathetic
##   6-8  → silent decline
##   9-11 → decline + secrecy −1 (loose talk)
##   12+  → INFORMS the liege → plot exposed
## Returns a report dict {ok, solicited_faction_id, outcome, commitment, secrecy}.
static func sound_out(plot_id: String, liege_character_id: String, day: int, dice = null) -> Dictionary:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty() or String(plot.get("status", "")) not in ["brewing", "recruiting"]:
		return {"ok": false, "error": "plot_not_recruitable"}
	var campaign_id: String = String(plot.get("campaign_id", ""))
	var candidate: Dictionary = _next_candidate(plot_id, liege_character_id)
	if candidate.is_empty():
		return {"ok": false, "error": "no_candidate"}
	var assn: Dictionary = candidate
	var candidate_faction_id: String = _realm_mirror_for_character(
		campaign_id, String(assn.get("vassal_character_id", "")))

	# Momentum: −1 per 2 committed members already in the coalition.
	var committed_count: int = CampaignRepository.ff_list_plot_members(plot_id, ["committed"]).size()
	@warning_ignore("integer_division")
	var momentum: int = -(committed_count / MOMENTUM_PER_N_COMMITTED)

	# The SECRET loyalty roll toward the liege (full §5.2 stack + momentum).
	var roll: Dictionary = VassalLoyaltyResolver.roll_for_trigger(
		assn, "rebel_solicitation", day, dice, {"momentum": momentum})
	var outcome: String = String(roll.get("outcome", ""))

	var status: String = String(plot.get("status", "brewing"))
	if status == "brewing":
		status = "recruiting"
	var secrecy: int = int(plot.get("secrecy", SECRECY_BASE))
	var commitment: String = ""
	var informed: bool = false
	match outcome:
		HenchmanTables.LOYALTY_HOSTILITY:   # 2− → committed
			commitment = "committed"
			CampaignRepository.ff_upsert_plot_member(plot_id, candidate_faction_id, "committed", day)
		HenchmanTables.LOYALTY_RESIGNATION:  # 3-5 → sympathetic
			commitment = "sympathetic"
			CampaignRepository.ff_upsert_plot_member(plot_id, candidate_faction_id, "sympathetic", day)
		HenchmanTables.LOYALTY_GRUDGING:     # 6-8 → silent decline
			commitment = "declined"
		HenchmanTables.LOYALTY_LOYAL:        # 9-11 → decline + secrecy −1
			commitment = "declined"
			secrecy += SECRECY_SOLICIT_LOOSE_TALK
		HenchmanTables.LOYALTY_FANATIC:      # 12+ → informs the liege
			commitment = "informed"
			informed = true

	# Track the solicited candidate so it is never re-solicited for THIS plot
	# (§5.7 solicits ONE candidate per step; a decliner drops out of the pool).
	# Committed/sympathetic candidates are already excluded as plot_members; this
	# additionally excludes silent/loose-talk decliners, which have no member row.
	var launch_cond: Dictionary = _parse_json(String(plot.get("launch_condition", "{}")))
	var solicited: Array = launch_cond.get("solicited", [])
	if not solicited.has(candidate_faction_id):
		solicited.append(candidate_faction_id)
	launch_cond["solicited"] = solicited

	# Persist the (possibly reduced) secrecy + advanced status + solicited list.
	CampaignRepository.ff_upsert_plot({
		"id": plot_id, "campaign_id": campaign_id, "kind": "rebellion",
		"instigator_faction_id": String(plot.get("instigator_faction_id", "")),
		"target_faction_id": String(plot.get("target_faction_id", "")),
		"secrecy": maxi(secrecy, 0),
		"launch_condition": JSON.stringify(launch_cond),
		"status": status,
		"ready_since_day": int(plot.get("ready_since_day", 0)),
	})
	if status != String(plot.get("status", "")):
		_emit_status(plot_id, status, String(plot.get("instigator_faction_id", "")))

	# Exposure paths: an informant (12+) OR secrecy hitting 0.
	if informed:
		expose(plot_id, liege_character_id, day, "informant")
	elif secrecy <= 0:
		expose(plot_id, liege_character_id, day, "secrecy_zero")

	return {"ok": true, "solicited_faction_id": candidate_faction_id, "outcome": outcome,
		"commitment": commitment, "secrecy": maxi(secrecy, 0), "informed": informed,
		"roll": roll}


# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

## §5.7 READY: coalition power check (extraction-resistance formula pattern).
##   rebel_br  = Σ committed members' federated BR (+ instigator)
##   liege_br  = liege personal + loyal-vassal (loyalty >= 9) federation;
##               6-8 grudging vassals contribute 0
##   threshold = 0.60 − 0.15×instigator expansion − 0.10×(aggressive) + 0.15×(liege allied)
## Sets status='ready' + ready_since_day when rebel_br >= threshold × liege_br.
## Returns {ready, rebel_br, liege_br, threshold, threshold_br}.
static func check_ready(plot_id: String, liege_character_id: String, day: int) -> Dictionary:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty() or String(plot.get("status", "")) not in ["brewing", "recruiting"]:
		return {"ready": false, "error": "plot_not_pending"}
	var campaign_id: String = String(plot.get("campaign_id", ""))
	var instigator_faction_id: String = String(plot.get("instigator_faction_id", ""))

	var rebel_br: float = 0.0
	for m in CampaignRepository.ff_list_plot_members(plot_id, ["committed"]):
		rebel_br += _federated_br_for_faction(String((m as Dictionary).get("faction_id", "")))

	var liege_br: float = _liege_loyal_federation_br(liege_character_id, day)

	var disp: StrategicDisposition = _disposition_for_faction(instigator_faction_id)
	var threshold: float = READY_THRESHOLD_ANCHOR
	if disp != null:
		threshold -= READY_EXPANSION_COEFF * disp.expansion_weight
		if disp.crisis_response == "aggressive":
			threshold -= READY_AGGRESSIVE_COEFF
	if _liege_has_alliance(campaign_id, liege_character_id):
		threshold += READY_LIEGE_ALLIANCE_COEFF
	threshold = clampf(threshold, 0.05, 1.5)

	var threshold_br: float = threshold * liege_br
	var ready: bool = rebel_br >= threshold_br and rebel_br > 0.0
	if ready:
		CampaignRepository.ff_upsert_plot({
			"id": plot_id, "campaign_id": campaign_id, "kind": "rebellion",
			"instigator_faction_id": instigator_faction_id,
			"target_faction_id": String(plot.get("target_faction_id", "")),
			"secrecy": int(plot.get("secrecy", SECRECY_BASE)),
			"launch_condition": String(plot.get("launch_condition", "{}")),
			"status": "ready",
			"ready_since_day": day,
		})
		_emit_status(plot_id, "ready", instigator_faction_id)
	return {"ready": ready, "rebel_br": rebel_br, "liege_br": liege_br,
		"threshold": threshold, "threshold_br": threshold_br}


# ---------------------------------------------------------------------------
# LAUNCH
# ---------------------------------------------------------------------------

## §5.7 LAUNCH: on 'ready' + a trigger (liege loses a battle / succession / tribute
## hike / 6 months ready) or FORCED when secrecy hit 0 (via expose). Committed
## members' domains flip to a NEW rebel realm-mirror faction;
## realm_relations(rebels, liege) = hostile; war proceeds via army-warfare. The
## rebel realm is minted through RealmRepository.create_realm + ensure_realm_mirror
## (the FF-1 pattern). Returns {ok, rebel_realm_id, rebel_faction_id, flipped}.
static func launch(plot_id: String, liege_character_id: String, day: int,
		trigger: String = "manual") -> Dictionary:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty() or String(plot.get("status", "")) not in ["ready", "exposed"]:
		return {"ok": false, "error": "plot_not_launchable"}
	var campaign_id: String = String(plot.get("campaign_id", ""))
	var instigator_faction_id: String = String(plot.get("instigator_faction_id", ""))

	var liege_realm: Dictionary = RealmRepository.get_realm_for_character(liege_character_id)
	var liege_realm_id: String = String(liege_realm.get("id", ""))

	# Mint the rebel realm headed by the instigator's leader. Faction columns can
	# be SQL NULL (realm-mirror rows don't set every field), so coerce through _s()
	# — String(null) is an invalid constructor call in GDScript. alignment must be
	# one of the realms CHECK values ('lawful'/'neutral'/'chaotic'); default neutral.
	var instigator_faction: Dictionary = CampaignRepository.get_faction(instigator_faction_id)
	var rebel_head: String = _s(instigator_faction.get("leader_npc_id"), "")
	var rebel_realm_id: String = RealmRepository.create_realm({
		"campaign_id": campaign_id,
		"name": "Rebel Coalition of %s" % _s(instigator_faction.get("name"), "the Vassals"),
		"head_character_id": rebel_head,
		"alignment": _s(instigator_faction.get("alignment"), "neutral"),
		"dominant_religion": _s(instigator_faction.get("religion_id"), ""),
		"culture": _s(instigator_faction.get("culture_id"), ""),
		"realm_kind": "tracked",
	})
	var rebel_faction_id: String = FactionRegistry.ensure_realm_mirror(campaign_id, rebel_realm_id)

	# Flip each committed member's domains to the rebel realm (re-point domains.realm_id
	# for the member's owned domains; the realms-titles re-parenting path owns the
	# liege-chain surgery — v1 records the intent + re-points the realm cache).
	var flipped: int = 0
	for m in CampaignRepository.ff_list_plot_members(plot_id, ["committed"]):
		var member_faction: Dictionary = CampaignRepository.get_faction(
			String((m as Dictionary).get("faction_id", "")))
		var member_head: String = _s(member_faction.get("leader_npc_id"), "")
		if member_head == "":
			continue
		if _repoint_domains_to_realm(member_head, rebel_realm_id):
			flipped += 1

	# realm_relations(rebels, liege) = hostile.
	if liege_realm_id != "" and rebel_realm_id != liege_realm_id:
		RealmRepository.set_relation(rebel_realm_id, liege_realm_id, "hostile", day)

	CampaignRepository.ff_upsert_plot({
		"id": plot_id, "campaign_id": campaign_id, "kind": "rebellion",
		"instigator_faction_id": instigator_faction_id,
		"target_faction_id": String(plot.get("target_faction_id", "")),
		"secrecy": 0,
		"launch_condition": String(plot.get("launch_condition", "{}")),
		"status": "launched",
		"ready_since_day": int(plot.get("ready_since_day", 0)),
	})
	_emit_status(plot_id, "launched", instigator_faction_id)
	if EventBus.has_signal("rebellion_launched"):
		EventBus.emit_signal("rebellion_launched", plot_id, rebel_realm_id, liege_realm_id)
	return {"ok": true, "rebel_realm_id": rebel_realm_id, "rebel_faction_id": rebel_faction_id,
		"flipped": flipped, "trigger": trigger}


## §5.7 launch-trigger check: given a 'ready' plot, decide whether a launch trigger
## has fired (6 months ready, or a caller-supplied event trigger). Returns the
## trigger name to launch on, or "" to keep waiting.
static func launch_trigger_ready(plot_id: String, day: int, event_trigger: String = "") -> String:
	if event_trigger != "":
		return event_trigger
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty() or String(plot.get("status", "")) != "ready":
		return ""
	var ready_since: int = int(plot.get("ready_since_day", 0))
	if ready_since > 0 and day - ready_since >= READY_MONTHS_TO_FORCE * DAYS_PER_MONTH:
		return "ready_timeout"
	return ""


# ---------------------------------------------------------------------------
# RESOLVE
# ---------------------------------------------------------------------------

## §5.7 RESOLVE: mark the plot resolved and write ledger entries for every
## participant + the liege observer. [param rebel_won] drives which DaW-style
## outcome the caller applies (victory re-parents chains; defeat applies conquest
## at the liege's discretion — that domain surgery is the realms-titles / army-
## warfare path, invoked by the caller). This method only closes the plot +
## records the deed memory. Returns {ok, participants}.
static func resolve(plot_id: String, rebel_won: bool, day: int) -> Dictionary:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty():
		return {"ok": false, "error": "plot_missing"}
	var campaign_id: String = String(plot.get("campaign_id", ""))
	var instigator: String = String(plot.get("instigator_faction_id", ""))
	var liege_mirror: String = String(plot.get("target_faction_id", ""))
	var participants: Array = []
	for m in CampaignRepository.ff_list_plot_members(plot_id):
		var fid: String = String((m as Dictionary).get("faction_id", ""))
		participants.append(fid)
		# Every participant remembers the rebellion against the liege (a grievance
		# regardless of outcome — betrayal_executed never forgotten).
		if liege_mirror != "" and fid != liege_mirror:
			FactionEventLedger.record(campaign_id, day, fid, liege_mirror,
				"betrayal_executed", -5 if rebel_won else -3,
				JSON.stringify({"plot_id": plot_id, "rebel_won": rebel_won}))
	CampaignRepository.ff_upsert_plot({
		"id": plot_id, "campaign_id": campaign_id, "kind": "rebellion",
		"instigator_faction_id": instigator,
		"target_faction_id": liege_mirror,
		"secrecy": 0,
		"launch_condition": String(plot.get("launch_condition", "{}")),
		"status": "resolved",
		"ready_since_day": int(plot.get("ready_since_day", 0)),
	})
	_emit_status(plot_id, "resolved", instigator)
	return {"ok": true, "participants": participants, "rebel_won": rebel_won}


# ---------------------------------------------------------------------------
# Secrecy / exposure (§7.4)
# ---------------------------------------------------------------------------

## §7.4 secrecy erosion: apply a delta (e.g. −1 rumor, −1 covert op, −2 spy-find)
## to the plot's secrecy; expose at 0. Returns the new secrecy value.
static func erode_secrecy(plot_id: String, delta: int, liege_character_id: String, day: int) -> int:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty() or String(plot.get("status", "")) in ["launched", "exposed", "abandoned", "resolved"]:
		return int(plot.get("secrecy", 0))
	var secrecy: int = maxi(int(plot.get("secrecy", SECRECY_BASE)) + delta, 0)
	CampaignRepository.ff_upsert_plot({
		"id": plot_id, "campaign_id": String(plot.get("campaign_id", "")), "kind": "rebellion",
		"instigator_faction_id": String(plot.get("instigator_faction_id", "")),
		"target_faction_id": String(plot.get("target_faction_id", "")),
		"secrecy": secrecy,
		"launch_condition": String(plot.get("launch_condition", "{}")),
		"status": String(plot.get("status", "")),
		"ready_since_day": int(plot.get("ready_since_day", 0)),
	})
	if secrecy <= 0:
		expose(plot_id, liege_character_id, day, "secrecy_zero")
	return secrecy


## §7.4 exposure: the liege learns the plot. If it is already 'ready', it force-
## launches; otherwise it collapses (status='exposed', instigator's loyalty state
## decides whether a later launch is possible — v1 leaves it exposed for the
## realm-politics step to force-launch or abandon).
static func expose(plot_id: String, liege_character_id: String, day: int, reason: String) -> Dictionary:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	if plot.is_empty() or String(plot.get("status", "")) in ["launched", "exposed", "abandoned", "resolved"]:
		return {"ok": false, "error": "not_exposable"}
	var was_ready: bool = String(plot.get("status", "")) == "ready"
	CampaignRepository.ff_upsert_plot({
		"id": plot_id, "campaign_id": String(plot.get("campaign_id", "")), "kind": "rebellion",
		"instigator_faction_id": String(plot.get("instigator_faction_id", "")),
		"target_faction_id": String(plot.get("target_faction_id", "")),
		"secrecy": 0,
		"launch_condition": String(plot.get("launch_condition", "{}")),
		"status": "exposed",
		"ready_since_day": int(plot.get("ready_since_day", 0)),
	})
	_emit_status(plot_id, "exposed", String(plot.get("instigator_faction_id", "")))
	# A ready-and-exposed plot force-launches at bad odds (§7.4).
	if was_ready:
		return launch(plot_id, liege_character_id, day, "forced_by_exposure_" + reason)
	return {"ok": true, "exposed": true, "reason": reason, "force_launched": false}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The next solicitation candidate: an active co-vassal of the liege NOT already a
## plot member, lowest current loyalty first, sharing border OR culture/alignment
## affinity with the instigator (§5.7). Returns the vassal_assignment dict, or {}.
static func _next_candidate(plot_id: String, liege_character_id: String) -> Dictionary:
	var plot: Dictionary = CampaignRepository.ff_get_plot(plot_id)
	var campaign_id: String = String(plot.get("campaign_id", ""))
	var member_factions: Dictionary = {}
	for m in CampaignRepository.ff_list_plot_members(plot_id):
		member_factions[String((m as Dictionary).get("faction_id", ""))] = true
	# Exclude candidates already solicited for THIS plot (silent/loose decliners
	# have no member row, but are tracked in launch_condition.solicited).
	var launch_cond: Dictionary = _parse_json(String(plot.get("launch_condition", "{}")))
	for fid in launch_cond.get("solicited", []):
		member_factions[String(fid)] = true
	var candidates: Array = []
	for assn in VassalRepository.list_active_for_liege(liege_character_id):
		var vassal_id: String = String((assn as Dictionary).get("vassal_character_id", ""))
		var faction_id: String = _realm_mirror_for_character(campaign_id, vassal_id)
		if faction_id == "" or member_factions.has(faction_id):
			continue
		candidates.append(assn)
	if candidates.is_empty():
		return {}
	# Lowest current loyalty first (last_loyalty_outcome band index; unknown = high).
	candidates.sort_custom(func(a, b):
		return _loyalty_rank(String(a.get("last_loyalty_outcome", ""))) \
			< _loyalty_rank(String(b.get("last_loyalty_outcome", ""))))
	return candidates[0]


static func _loyalty_rank(outcome: String) -> int:
	match outcome:
		HenchmanTables.LOYALTY_HOSTILITY: return 0
		HenchmanTables.LOYALTY_RESIGNATION: return 1
		HenchmanTables.LOYALTY_GRUDGING: return 2
		HenchmanTables.LOYALTY_LOYAL: return 3
		HenchmanTables.LOYALTY_FANATIC: return 4
	return 5   # never rolled = treat as most loyal (solicit last)


## Liege personal BR + loyal-vassal (loyalty >= 9, i.e. loyal/fanatic) federation;
## grudging (6-8) vassals contribute 0 (they sit it out, §5.7).
static func _liege_loyal_federation_br(liege_character_id: String, _day: int) -> float:
	var total: float = _federated_br_for_character(liege_character_id)
	for assn in VassalRepository.list_active_for_liege(liege_character_id):
		var behavior: String = String((assn as Dictionary).get("compliance_behavior", "full_compliance"))
		# Loyal / fanatic → full contribution; under/resignation/rebellious → 0.
		if behavior in ["full_compliance", "over_compliance"]:
			total += _federated_br_for_character(
				String((assn as Dictionary).get("vassal_character_id", "")))
	return total


static func _liege_has_alliance(campaign_id: String, liege_character_id: String) -> bool:
	var liege_realm: Dictionary = RealmRepository.get_realm_for_character(liege_character_id)
	var realm_id: String = String(liege_realm.get("id", ""))
	if realm_id == "":
		return false
	return not CampaignRepository.ff_list_active_treaties_for_realm(
		realm_id, TreatyResolver.ALLIANCE_KINDS).is_empty()


static func _federated_br_for_faction(faction_id: String) -> float:
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	return _federated_br_for_character(String(faction.get("leader_npc_id", "")))


static func _federated_br_for_character(character_id: String) -> float:
	if character_id == "":
		return 0.0
	var total: float = 0.0
	if CampaignRepository.db.query_with_bindings("""
		SELECT tu.battle_rating FROM troop_units tu
		JOIN domains d ON d.id = tu.assigned_domain_id
		WHERE d.owner_character_id = ? AND tu.status = 'active'
	""", [character_id]):
		for row in CampaignRepository.db.query_result:
			total += float((row as Dictionary).get("battle_rating", 0.0))
	# Instigator/co-vassal with no fielded troops still has notional power — use a
	# floor of 1.0 so a garrison-less test fixture still produces a meaningful ratio.
	return maxf(total, 1.0)


static func _disposition_for_faction(faction_id: String) -> StrategicDisposition:
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	var leader: String = String(faction.get("leader_npc_id", ""))
	if leader == "":
		return null
	return RulerDispositionRepository.get_disposition(leader)


## The realm-mirror faction id for a character's realm (created if needed).
static func _realm_mirror_for_character(campaign_id: String, character_id: String) -> String:
	var realm: Dictionary = RealmRepository.get_realm_for_character(character_id)
	var realm_id: String = String(realm.get("id", ""))
	if realm_id == "":
		return ""
	return FactionRegistry.ensure_realm_mirror(campaign_id, realm_id)


## Re-point every domain the character owns to [param realm_id] (the realm-cache
## flip; full liege-chain surgery belongs to the realms-titles path). Returns true
## if any domain was re-pointed.
static func _repoint_domains_to_realm(character_id: String, realm_id: String) -> bool:
	return CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET realm_id = ?, liege_domain_id = NULL WHERE owner_character_id = ?",
		[realm_id, character_id])


## §7.4 secrecy: instigator leader's self_interest adjustment to the base-10 start.
## Higher self_interest → a more careful conspirator → +1/+2 secrecy (PROJECT CALL).
static func _self_interest_secrecy_adj(leader_id: String) -> int:
	if leader_id == "":
		return 0
	var disp: StrategicDisposition = RulerDispositionRepository.get_disposition(leader_id)
	if disp == null:
		return 0
	if disp.self_interest >= 8:
		return 2
	if disp.self_interest >= 6:
		return 1
	return 0


static func _emit_status(plot_id: String, status: String, instigator_faction_id: String) -> void:
	if EventBus.has_signal("rebellion_plot_updated"):
		EventBus.emit_signal("rebellion_plot_updated", plot_id, status, instigator_faction_id)


static func _parse_json(s: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(s)
	return parsed if parsed is Dictionary else {}


## Null-safe String coercion: SQL-NULL faction/realm columns come back as a Variant
## null, and String(null) is an invalid constructor call in GDScript. Returns the
## default when the value is null (or an unset ""), else the string form.
static func _s(v: Variant, default_value: String = "") -> String:
	if v == null:
		return default_value
	return str(v)
