class_name ResignationLadder
extends RefCounted

## Faction FF-3.e — the resignation ladder (gdd-faction-framework.md §5.9), A+B+C.
## A Resignation loyalty result (3-5, §5.3) opens a lawful-exit ladder tracked in
## realm_petitions (§4.8). "Release" never means independence — it re-parents
## WITHIN the realm. Leaving the realm entirely is only the rebellion track (§5.7)
## or exile (path C).
##
## Ladder, not menu: an NPC tries A before C unless disposition says otherwise
## (high self_interest + wealth motivation skips to C; high societal_orthodoxy
## exhausts A then B). This service exposes each rung as its own resolver so the
## realm-politics step + player-as-vassal path can drive them; choose_rung()
## encodes the ladder ordering for NPC vassals.
##
## Path A — Petition the liege (release/transfer): the liege resolves grant /
##          buy-off (a Favors & Duties office grant, +1 loyalty per RAW) / refuse.
## Path B — Appeal the sovereign (appeal; THE FF-3 addition): the sovereign
##          adjudicates by loyalty record + culture/alignment affinity + power +
##          disposition. Siding-with-vassal re-parents to crown AND grieves the
##          intermediate liege against both; siding-with-liege deepens grievance.
## Path C — Abdicate into exile: domain reverts to the liege; the ex-vassal
##          becomes a landless Tier-A NPC (inert-but-present).

const RUNG_A := "petition_liege"
const RUNG_B := "appeal_sovereign"
const RUNG_C := "abdicate_exile"


# ---------------------------------------------------------------------------
# Ladder selection (NPC)
# ---------------------------------------------------------------------------

## Which rung an NPC vassal attempts, given its disposition + realm structure.
## High self_interest (>=8) + power/wealth motivation → skip to C. Otherwise A
## first; B only exists in 3+-tier realms after an A refusal (the caller escalates).
static func choose_rung(vassal_character_id: String) -> String:
	var disp: StrategicDisposition = RulerDispositionRepository.get_disposition(vassal_character_id)
	if disp != null and disp.self_interest >= 8 \
			and disp.motivation_primary in ["power", "wealth"]:
		return RUNG_C
	return RUNG_A


# ---------------------------------------------------------------------------
# Path A — Petition the liege
# ---------------------------------------------------------------------------

## File a release (re-parent to the liege's liege) or transfer (to a named liege)
## petition. Idempotent-ish: a vassal with an open petition against the same liege
## does not double-file. Returns the petition id, or "".
static func file_petition(campaign_id: String, petitioner_domain_id: String,
		liege_domain_id: String, kind: String, day: int, terms: Dictionary = {}) -> String:
	if kind not in ["release", "transfer"]:
		push_error("ResignationLadder.file_petition: kind must be release/transfer")
		return ""
	for existing in CampaignRepository.ff_list_open_petitions_for_petitioner(petitioner_domain_id):
		if String((existing as Dictionary).get("liege_domain_id", "")) == liege_domain_id:
			return String((existing as Dictionary).get("id", ""))
	var petition_id: String = CampaignRepository.ff_upsert_petition({
		"campaign_id": campaign_id,
		"petitioner_domain_id": petitioner_domain_id,
		"liege_domain_id": liege_domain_id,
		"kind": kind,
		"status": "filed",
		"filed_day": day,
		"terms": JSON.stringify(terms),
	})
	return petition_id


## The liege resolves a filed A-petition on their realm-politics step. Scored by
## disposition + the vassal's value + relationship: grant / buy_off / refuse.
## Returns {resolution, petition_id, score}. Grant re-parents (v1: re-points the
## petitioner domain's liege chain to the named/upper liege); buy_off grants a
## Favors & Duties office (RAW +1 loyalty); refuse leaves the petition open to
## escalate to B.
static func resolve_petition_as_liege(petition_id: String, day: int) -> Dictionary:
	var petition: Dictionary = CampaignRepository.ff_get_petition(petition_id)
	if petition.is_empty() or String(petition.get("status", "")) not in ["filed", "escalated"]:
		return {"ok": false, "error": "petition_not_open"}
	var petitioner_domain_id: String = String(petition.get("petitioner_domain_id", ""))
	var liege_domain_id: String = String(petition.get("liege_domain_id", ""))
	var kind: String = String(petition.get("kind", "release"))
	var campaign_id: String = String(petition.get("campaign_id", ""))

	var liege_owner: String = _owner_of_domain(liege_domain_id)
	var vassal_owner: String = _owner_of_domain(petitioner_domain_id)
	var score: int = _grant_score(liege_owner, vassal_owner, day)

	# A 2-tier realm's sovereign can rarely grant 'release' (it would be
	# independence) — force buy-off/refuse there (§5.9).
	var is_release_at_2tier: bool = kind == "release" and _liege_is_sovereign(liege_domain_id)

	var resolution: String
	if score >= 3 and not is_release_at_2tier:
		resolution = "granted"
		_execute_reparent(petition, kind)
	elif score >= 0:
		resolution = "bought_off"
		_grant_office_buyoff(vassal_owner, liege_owner, day)
	else:
		resolution = "refused"
		_record_refusal_grievance(campaign_id, vassal_owner, liege_owner, day)

	CampaignRepository.ff_upsert_petition({
		"id": petition_id, "campaign_id": campaign_id,
		"petitioner_domain_id": petitioner_domain_id,
		"liege_domain_id": liege_domain_id, "kind": kind,
		"status": resolution, "filed_day": int(petition.get("filed_day", 0)),
		"resolved_day": day, "terms": String(petition.get("terms", "{}")),
	})
	if EventBus.has_signal("realm_petition_resolved"):
		EventBus.emit_signal("realm_petition_resolved", petition_id, kind, resolution)
	return {"ok": true, "resolution": resolution, "petition_id": petition_id, "score": score}


# ---------------------------------------------------------------------------
# Path B — Appeal the sovereign (THE FF-3 addition)
# ---------------------------------------------------------------------------

## Escalate a refused A-petition to an appeal (only in 3+-tier realms). Files a new
## kind='appeal' petition naming the sovereign's domain as adjudicator liege and
## marks the original refused petition escalated. Returns the appeal petition id.
static func escalate_to_appeal(campaign_id: String, refused_petition_id: String, day: int) -> String:
	var refused: Dictionary = CampaignRepository.ff_get_petition(refused_petition_id)
	if refused.is_empty():
		return ""
	var petitioner_domain_id: String = String(refused.get("petitioner_domain_id", ""))
	var intermediate_liege_domain_id: String = String(refused.get("liege_domain_id", ""))
	var sovereign_domain_id: String = _sovereign_domain_for(intermediate_liege_domain_id)
	# 2-tier realm: the intermediate liege IS the sovereign — no one to appeal to.
	if sovereign_domain_id == "" or sovereign_domain_id == intermediate_liege_domain_id:
		return ""
	# Mark the refused A-petition escalated.
	CampaignRepository.ff_upsert_petition({
		"id": refused_petition_id, "campaign_id": campaign_id,
		"petitioner_domain_id": petitioner_domain_id,
		"liege_domain_id": intermediate_liege_domain_id, "kind": String(refused.get("kind", "release")),
		"status": "escalated", "filed_day": int(refused.get("filed_day", 0)),
		"resolved_day": day, "terms": String(refused.get("terms", "{}")),
	})
	return CampaignRepository.ff_upsert_petition({
		"campaign_id": campaign_id,
		"petitioner_domain_id": petitioner_domain_id,
		"liege_domain_id": sovereign_domain_id,
		"kind": "appeal",
		"status": "filed",
		"filed_day": day,
		"terms": JSON.stringify({"intermediate_liege_domain_id": intermediate_liege_domain_id}),
	})


## The sovereign adjudicates an appeal by loyalty record toward the crown +
## culture/alignment affinity + power + disposition. Siding with the vassal
## re-parents him to the crown AND grieves the INTERMEDIATE liege against both
## crown and ex-vassal (appeals split courts, §5.9). Siding with the liege deepens
## the vassal's grievance (→ path C or, at loyalty 2−, rebellion). Returns
## {ok, sided_with, petition_id, score}.
static func adjudicate_appeal(petition_id: String, day: int) -> Dictionary:
	var petition: Dictionary = CampaignRepository.ff_get_petition(petition_id)
	if petition.is_empty() or String(petition.get("kind", "")) != "appeal" \
			or String(petition.get("status", "")) not in ["filed", "escalated"]:
		return {"ok": false, "error": "appeal_not_open"}
	var campaign_id: String = String(petition.get("campaign_id", ""))
	var petitioner_domain_id: String = String(petition.get("petitioner_domain_id", ""))
	var sovereign_domain_id: String = String(petition.get("liege_domain_id", ""))
	var terms: Dictionary = _parse_terms(String(petition.get("terms", "{}")))
	var intermediate_liege_domain_id: String = String(terms.get("intermediate_liege_domain_id", ""))

	var sovereign_owner: String = _owner_of_domain(sovereign_domain_id)
	var vassal_owner: String = _owner_of_domain(petitioner_domain_id)
	var intermediate_owner: String = _owner_of_domain(intermediate_liege_domain_id)
	var score: int = _appeal_score(sovereign_owner, vassal_owner, intermediate_owner, day)

	var sided_with: String
	if score >= 1:
		sided_with = "vassal"
		# Re-parent the petitioner to the crown.
		_reparent_domain_to(petitioner_domain_id, sovereign_domain_id)
		# Grieve the intermediate liege against BOTH crown and ex-vassal.
		_grieve_pair(campaign_id, intermediate_owner, sovereign_owner, day, -3)
		_grieve_pair(campaign_id, intermediate_owner, vassal_owner, day, -3)
	else:
		sided_with = "liege"
		# Deepen the vassal's grievance toward BOTH crown and intermediate liege.
		_grieve_pair(campaign_id, vassal_owner, sovereign_owner, day, -3)
		_grieve_pair(campaign_id, vassal_owner, intermediate_owner, day, -2)

	CampaignRepository.ff_upsert_petition({
		"id": petition_id, "campaign_id": campaign_id,
		"petitioner_domain_id": petitioner_domain_id,
		"liege_domain_id": sovereign_domain_id, "kind": "appeal",
		"status": ("granted" if sided_with == "vassal" else "refused"),
		"filed_day": int(petition.get("filed_day", 0)),
		"resolved_day": day, "terms": String(petition.get("terms", "{}")),
	})
	if EventBus.has_signal("realm_petition_resolved"):
		EventBus.emit_signal("realm_petition_resolved", petition_id, "appeal",
			"granted" if sided_with == "vassal" else "refused")
	return {"ok": true, "sided_with": sided_with, "petition_id": petition_id, "score": score}


# ---------------------------------------------------------------------------
# Path C — Abdicate into exile
# ---------------------------------------------------------------------------

## The vassal abdicates: the domain reverts to the liege (existing NPC-appointment
## machinery holds it directly until a successor is seated), and the ex-vassal
## becomes a landless Tier-A NPC with a treasury + retinue (inert-but-present until
## gdd-npc-agency lands). v1: revert the domain's owner to the liege and mark the
## vassal_assignment departed; record the ex-ruler as landless (character keeps its
## row, loses domain ownership). Returns {ok, ex_ruler_id, reverted_domain_id}.
static func abdicate_into_exile(campaign_id: String, vassal_character_id: String,
		liege_character_id: String, day: int) -> Dictionary:
	var domain: Dictionary = _personal_domain_for_character(vassal_character_id)
	if domain.is_empty():
		return {"ok": false, "error": "no_domain"}
	var domain_id: String = String(domain.get("id", ""))
	# Domain reverts to the liege (holds it directly at administration penalty).
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET owner_character_id = ? WHERE id = ?",
		[liege_character_id if liege_character_id != "" else null, domain_id])
	# Mark the vassal assignment departed.
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(vassal_character_id)
	if not assn.is_empty():
		VassalRepository.update_status(String(assn.get("id", "")), "departed", day)
	if EventBus.has_signal("realm_petition_resolved"):
		# A synthetic petition-close event so the exile surfaces in logs like the
		# other rungs (no petition row is required for the floor path).
		EventBus.emit_signal("realm_petition_resolved", "", "abdicate", "exiled")
	return {"ok": true, "ex_ruler_id": vassal_character_id, "reverted_domain_id": domain_id}


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

## A-petition grant score: disposition generosity (affective_compassion) minus the
## vassal's value to the liege (a valuable vassal is harder to release) plus the
## relationship. PROJECT CALL. >= 3 grant, 0..2 buy-off, < 0 refuse.
static func _grant_score(liege_owner: String, vassal_owner: String, day: int) -> int:
	var score: int = 0
	var disp: StrategicDisposition = RulerDispositionRepository.get_disposition(liege_owner)
	if disp != null:
		# Generous / low-orthodoxy lieges release more readily.
		score += 1 if disp.affective_compassion >= 6 else 0
		score -= 1 if disp.societal_orthodoxy >= 7 else 0
		score -= 1 if disp.self_interest >= 7 else 0
	# Relationship: grievance the liege holds toward the vassal (a resented vassal
	# is released more readily; a valued one held).
	var g: int = _grievance(liege_owner, vassal_owner, day)
	if g <= -3:
		score += 1   # glad to be rid of them
	elif g >= 3:
		score -= 1   # values them; holds on
	return score


## Appeal adjudication score: the vassal's loyalty record toward the CROWN +
## culture/alignment affinity with the crown − power of the intermediate liege +
## sovereign disposition. >= 1 → side with vassal. PROJECT CALL.
static func _appeal_score(sovereign_owner: String, vassal_owner: String,
		intermediate_owner: String, day: int) -> int:
	var score: int = 0
	# Culture / alignment affinity of the vassal with the crown.
	var crown: Dictionary = CampaignRepository.get_character(sovereign_owner)
	var vassal: Dictionary = CampaignRepository.get_character(vassal_owner)
	if not crown.is_empty() and not vassal.is_empty():
		if String(crown.get("alignment", "")) == String(vassal.get("alignment", "")):
			score += 1
	# Grievance the crown holds toward the intermediate liege (a troublesome
	# intermediate is undercut in the vassal's favour — the crown centralises).
	var g_int: int = _grievance(sovereign_owner, intermediate_owner, day)
	if g_int <= -3:
		score += 1
	# Grievance the crown holds toward the vassal (a disloyal appellant is denied).
	var g_vas: int = _grievance(sovereign_owner, vassal_owner, day)
	if g_vas <= -3:
		score -= 1
	# Sovereign disposition: an expansionist crown centralises (sides with vassal
	# to break an over-mighty intermediate).
	var disp: StrategicDisposition = RulerDispositionRepository.get_disposition(sovereign_owner)
	if disp != null and disp.expansion_weight >= 0.6:
		score += 1
	return score


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------

## Re-parent the petitioner's domain per the petition kind (release → up to the
## liege's liege; transfer → to the named liege in terms). v1: re-point
## domains.liege_domain_id to the new liege domain (the realms-titles path owns
## full chain surgery; this is the runtime cache flip).
static func _execute_reparent(petition: Dictionary, kind: String) -> void:
	var petitioner_domain_id: String = String(petition.get("petitioner_domain_id", ""))
	var liege_domain_id: String = String(petition.get("liege_domain_id", ""))
	var new_liege_domain_id: String = ""
	if kind == "transfer":
		var terms: Dictionary = _parse_terms(String(petition.get("terms", "{}")))
		new_liege_domain_id = String(terms.get("new_liege_domain_id", ""))
	else:   # release → up to the liege's liege
		new_liege_domain_id = _liege_domain_of(liege_domain_id)
	_reparent_domain_to(petitioner_domain_id, new_liege_domain_id)


static func _reparent_domain_to(domain_id: String, new_liege_domain_id: String) -> void:
	if domain_id == "":
		return
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = ? WHERE id = ?",
		[new_liege_domain_id if new_liege_domain_id != "" else null, domain_id])


## Buy-off: grant the vassal a Favors & Duties office (RAW +1 loyalty, §2.2) —
## improves the loyalty state so the vassal stays. v1: bump the assignment's
## base_loyalty_modifier +1 (the office grant's mechanical effect) as the buy-off.
static func _grant_office_buyoff(vassal_owner: String, _liege_owner: String, day: int) -> void:
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(vassal_owner)
	if assn.is_empty():
		return
	var base: int = int(assn.get("base_loyalty_modifier", 0))
	VassalRepository.update(String(assn.get("id", "")), {"base_loyalty_modifier": base + 1})
	VassalRepository.db_set_compliance(String(assn.get("id", "")),
		VassalLoyaltyResolver.BEHAVIOR_FULL)


static func _record_refusal_grievance(campaign_id: String, vassal_owner: String,
		liege_owner: String, day: int) -> void:
	_grieve_pair(campaign_id, vassal_owner, liege_owner, day, -3)


## Record a grievance the OBSERVER (first arg) holds toward the SUBJECT (second),
## between their realm mirrors. magnitude negative.
static func _grieve_pair(campaign_id: String, observer_char: String, subject_char: String,
		day: int, magnitude: int) -> void:
	if observer_char == "" or subject_char == "":
		return
	var obs_realm: Dictionary = RealmRepository.get_realm_for_character(observer_char)
	var sub_realm: Dictionary = RealmRepository.get_realm_for_character(subject_char)
	var obs_mirror: String = FactionRegistry.ensure_realm_mirror(campaign_id, String(obs_realm.get("id", "")))
	var sub_mirror: String = FactionRegistry.ensure_realm_mirror(campaign_id, String(sub_realm.get("id", "")))
	if obs_mirror == "" or sub_mirror == "" or obs_mirror == sub_mirror:
		return
	# The observer holds the grievance toward the subject: the subject (actor) did
	# something to the observer (target).
	FactionEventLedger.record(campaign_id, day, sub_mirror, obs_mirror, "persecution",
		magnitude, JSON.stringify({"source": "resignation_ladder"}))


# ---------------------------------------------------------------------------
# Structure helpers
# ---------------------------------------------------------------------------

static func _grievance(observer_char: String, subject_char: String, day: int) -> int:
	if observer_char == "" or subject_char == "":
		return 0
	var obs_realm: Dictionary = RealmRepository.get_realm_for_character(observer_char)
	var sub_realm: Dictionary = RealmRepository.get_realm_for_character(subject_char)
	var campaign_id: String = String(obs_realm.get("campaign_id", sub_realm.get("campaign_id", "")))
	if campaign_id == "":
		return 0
	var obs_mirror: String = FactionRegistry.get_realm_mirror_id(campaign_id, String(obs_realm.get("id", "")))
	var sub_mirror: String = FactionRegistry.get_realm_mirror_id(campaign_id, String(sub_realm.get("id", "")))
	if obs_mirror == "" or sub_mirror == "":
		return 0
	return FactionEventLedger.recompute_grievance(obs_mirror, sub_mirror, day)


static func _owner_of_domain(domain_id: String) -> String:
	if domain_id == "":
		return ""
	if CampaignRepository.db.query_with_bindings(
			"SELECT owner_character_id FROM domains WHERE id = ?", [domain_id]) \
			and not CampaignRepository.db.query_result.is_empty():
		var v: Variant = CampaignRepository.db.query_result[0].get("owner_character_id")
		return String(v) if v != null else ""
	return ""


static func _liege_domain_of(domain_id: String) -> String:
	if domain_id == "":
		return ""
	if CampaignRepository.db.query_with_bindings(
			"SELECT liege_domain_id FROM domains WHERE id = ?", [domain_id]) \
			and not CampaignRepository.db.query_result.is_empty():
		var v: Variant = CampaignRepository.db.query_result[0].get("liege_domain_id")
		return String(v) if v != null else ""
	return ""


## True when the liege domain is a sovereign (apex — no liege of its own).
static func _liege_is_sovereign(liege_domain_id: String) -> bool:
	return _liege_domain_of(liege_domain_id) == ""


## The sovereign (apex) domain above [param domain_id]; "" if the domain IS the apex.
static func _sovereign_domain_for(domain_id: String) -> String:
	var apex: String = RealmGraph.apex_for_domain(domain_id)
	return apex if apex != domain_id else ""


static func _personal_domain_for_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[character_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.get_domain(
		String(CampaignRepository.db.query_result[0].get("id", "")))


static func _parse_terms(terms_json: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(terms_json)
	return parsed if parsed is Dictionary else {}
