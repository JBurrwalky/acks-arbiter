class_name OrgMembershipService
extends RefCounted

## Membership / ranks / standing / services (gdd-faction-framework.md §8.1/§8.2/
## §8.5 — FF-2.1). One mechanic, no invented rolls: loyalty is the henchman
## loyalty modifier (loyalty_mod), resolved at trigger events by the existing
## henchman-loyalty machinery — this service only STORES it. standing is the
## merit ledger (dues/jobs/offenses); rank advancement gates on class level (the
## ACKS level-title spine — a L2 thief cannot be an Underboss) plus standing.
##
## All static; writes through CampaignRepository.ff_upsert_membership and emits
## faction_membership_changed(character_id, faction_id, status).

## PROJECT CALL rank gating: minimum class level for a rank index, and minimum
## standing. A L2 thief cannot be an Underboss (rank 2 needs L6).
const RANK_MIN_LEVEL: Array = [1, 3, 6, 9, 12]
const RANK_MIN_STANDING: Array = [0, 10, 30, 60, 100]
## Standing thresholds for enforcement-by-events (§8.2).
const SUSPEND_STANDING: int = -50
const EXPEL_STANDING: int = -100


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Petition to join (§8.1): writes a status='petitioner' row (rank 0). The
## caller resolves the reaction gate; this records the accepted petition.
static func join(faction_id: String, npc_id: String, day: int,
		is_secret: bool = false) -> Dictionary:
	if faction_id.is_empty() or npc_id.is_empty():
		return {"ok": false, "reason": "empty_id"}
	CampaignRepository.ff_upsert_membership(faction_id, npc_id, {
		"status": "petitioner", "rank": 0, "joined_day": day,
		"is_secret": is_secret, "role": "member",
	})
	_emit(npc_id, faction_id, "petitioner")
	return {"ok": true, "status": "petitioner"}


## Petitioner -> member (initiation job complete, §8.1).
static func confirm_member(faction_id: String, npc_id: String) -> Dictionary:
	var m: Dictionary = CampaignRepository.ff_get_membership(faction_id, npc_id)
	if m.is_empty():
		return {"ok": false, "reason": "not_found"}
	CampaignRepository.ff_upsert_membership(faction_id, npc_id, {"status": "member"})
	_emit(npc_id, faction_id, "member")
	return {"ok": true, "status": "member"}


## Attempt a rank change (§8.2). Gated on class level + standing for PROMOTIONS;
## demotions always allowed. Returns {ok, reason, rank}.
static func set_rank(faction_id: String, npc_id: String, new_rank: int) -> Dictionary:
	var m: Dictionary = CampaignRepository.ff_get_membership(faction_id, npc_id)
	if m.is_empty():
		return {"ok": false, "reason": "not_found"}
	if String(m.get("status", "")) != "member":
		return {"ok": false, "reason": "not_active_member"}
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	var type: String = String(faction.get("faction_type", ""))
	var capped: int = clampi(new_rank, 0, OrgTypeCatalog.max_rank(type))
	var current_rank: int = int(m.get("rank", 0))
	if capped > current_rank:
		var level: int = _character_level(npc_id)
		if level < _rank_min_level(capped):
			return {"ok": false, "reason": "level_too_low", "need_level": _rank_min_level(capped)}
		if int(m.get("standing", 0)) < _rank_min_standing(capped):
			return {"ok": false, "reason": "standing_too_low",
				"need_standing": _rank_min_standing(capped)}
	CampaignRepository.ff_upsert_membership(faction_id, npc_id, {"rank": capped})
	return {"ok": true, "rank": capped}


## Adjust the merit ledger; auto-suspend / auto-expel on thresholds (§8.2). A
## suspension/expulsion emits the status change (and is the caller's cue to write
## a reputation grievance).
static func adjust_standing(faction_id: String, npc_id: String, delta: int,
		_reason: String = "") -> Dictionary:
	var m: Dictionary = CampaignRepository.ff_get_membership(faction_id, npc_id)
	if m.is_empty():
		return {"ok": false, "reason": "not_found"}
	var new_standing: int = int(m.get("standing", 0)) + delta
	var status: String = String(m.get("status", "member"))
	var fields: Dictionary = {"standing": new_standing}
	if new_standing <= EXPEL_STANDING and status != "expelled":
		fields["status"] = "expelled"
		status = "expelled"
	elif new_standing <= SUSPEND_STANDING and status == "member":
		fields["status"] = "suspended"
		status = "suspended"
	CampaignRepository.ff_upsert_membership(faction_id, npc_id, fields)
	if fields.has("status"):
		_emit(npc_id, faction_id, status)
	return {"ok": true, "standing": new_standing, "status": status}


## Voluntary departure / expulsion / suspension (§8.2). Writes the terminal
## status and emits. The ledger grievance/reputation write is the caller's.
static func leave(faction_id: String, npc_id: String) -> Dictionary:
	return _terminal(faction_id, npc_id, "left")


static func expel(faction_id: String, npc_id: String) -> Dictionary:
	return _terminal(faction_id, npc_id, "expelled")


static func suspend(faction_id: String, npc_id: String) -> Dictionary:
	return _terminal(faction_id, npc_id, "suspended")


static func _terminal(faction_id: String, npc_id: String, status: String) -> Dictionary:
	var m: Dictionary = CampaignRepository.ff_get_membership(faction_id, npc_id)
	if m.is_empty():
		return {"ok": false, "reason": "not_found"}
	CampaignRepository.ff_upsert_membership(faction_id, npc_id, {"status": status})
	_emit(npc_id, faction_id, status)
	return {"ok": true, "status": status}


# ---------------------------------------------------------------------------
# Queries + service eligibility (§8.5)
# ---------------------------------------------------------------------------

static func is_member(character_id: String, faction_id: String) -> bool:
	var m: Dictionary = CampaignRepository.ff_get_membership(faction_id, character_id)
	return not m.is_empty() and String(m.get("status", "")) == "member"


## §8.5 service gate: is_member && rank >= service.min_rank. The actual service
## resolution lives in its own subsystem; this is only the eligibility check.
static func can_access_service(character_id: String, faction_id: String,
		service_id: String) -> bool:
	var m: Dictionary = CampaignRepository.ff_get_membership(faction_id, character_id)
	if m.is_empty() or String(m.get("status", "")) != "member":
		return false
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	var min_rank: int = OrgTypeCatalog.service_min_rank(
		String(faction.get("faction_type", "")), service_id)
	if min_rank < 0:
		return false
	return int(m.get("rank", 0)) >= min_rank


## Every service id this character can currently access at the faction.
static func services_available(character_id: String, faction_id: String) -> Array:
	var out: Array = []
	# Read the membership + faction ONCE (both are loop-invariant); can_access_service
	# would re-fetch each of them per service (an N+1). The per-service min-rank check
	# is an in-memory catalog lookup.
	var m: Dictionary = CampaignRepository.ff_get_membership(faction_id, character_id)
	if m.is_empty() or String(m.get("status", "")) != "member":
		return out
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	var type: String = String(faction.get("faction_type", ""))
	var rank: int = int(m.get("rank", 0))
	for s in OrgTypeCatalog.services(type):
		var sid: String = String((s as Dictionary).get("id", ""))
		var min_rank: int = OrgTypeCatalog.service_min_rank(type, sid)
		if min_rank >= 0 and rank >= min_rank:
			out.append(sid)
	return out


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _rank_min_level(rank: int) -> int:
	return int(RANK_MIN_LEVEL[clampi(rank, 0, RANK_MIN_LEVEL.size() - 1)])


static func _rank_min_standing(rank: int) -> int:
	return int(RANK_MIN_STANDING[clampi(rank, 0, RANK_MIN_STANDING.size() - 1)])


static func _character_level(npc_id: String) -> int:
	var ch: Dictionary = CampaignRepository.get_character(npc_id)
	return int(ch.get("level", 1)) if not ch.is_empty() else 1


static func _emit(character_id: String, faction_id: String, status: String) -> void:
	if EventBus.has_signal("faction_membership_changed"):
		EventBus.faction_membership_changed.emit(character_id, faction_id, status)
