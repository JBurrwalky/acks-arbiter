class_name DividedLoyaltyDetector
extends RefCounted

## Divided loyalties — the party problem (gdd-faction-framework.md §8.4 — FF-4). The
## engine detects a loyalty CONFLICT when:
##   (a) two party members hold memberships in factions with mutual stance
##       <= unfriendly;
##   (b) any member's faction enters an active conflict on the OPPOSITE side of
##       another member's faction; or
##   (c) one member's obligation targets another member's faction.
##
## Detection emits `party_loyalty_conflict_detected(members, factions, cause)` and
## surfaces as CONTENT, never a UI modal (§8.4): the orgs act like the jealous
## institutions they are — conflicting job offers, loyalty demands, pointed dialogue.
## Resolution is always by player action; double agents are discovered via the same
## §7.4 secrecy machinery. Conflicts persist (party_loyalty_conflicts, migration 198)
## so a re-scan does NOT re-emit an already-known conflict (dedup on a deterministic
## signature). Deterministic — no RNG, explicit game `day`.

const CAUSE_MUTUAL_HOSTILE: String = "mutual_hostile_memberships"
const CAUSE_OPPOSITE_CONFLICT: String = "opposite_conflict_sides"
const CAUSE_OBLIGATION_TARGETS: String = "obligation_targets_faction"

## A membership at or below this band, held by BOTH factions toward each other,
## is a divided-loyalty trigger (§8.4 condition a).
const HOSTILE_BAND_MAX_INDEX: int = 1   # "unfriendly" (0=hostile, 1=unfriendly)

## Non-terminal membership statuses that bind a character to a faction.
const ACTIVE_MEMBERSHIP_STATUSES: Array = ["petitioner", "member", "suspended"]


## Detect divided-loyalty conflicts among [param party_member_ids]. [param context]
## may carry:
##   active_conflicts = [{conflict_id, side_a_mirror, side_b_mirror}]   (condition b)
##   obligations      = [{member_id, source_faction_id, target_faction_id}] (condition c)
## Persists new conflicts, emits the signal once per new conflict, and returns the
## full list of CURRENT conflict descriptors (new + already-known) for surfacing.
static func detect(campaign_id: String, party_member_ids: Array, day: int,
		context: Dictionary = {}) -> Array:
	var found: Array = []
	var by_member: Dictionary = {}
	for mid in party_member_ids:
		by_member[String(mid)] = _member_factions(String(mid))

	var members: Array = by_member.keys()
	members.sort()   # deterministic pair ordering

	# (a) + (b): scan member pairs.
	for i in members.size():
		for j in range(i + 1, members.size()):
			var m_a: String = String(members[i])
			var m_b: String = String(members[j])
			for fa in by_member[m_a]:
				for fb in by_member[m_b]:
					if String(fa) == String(fb):
						continue
					var hostile: Dictionary = _mutual_hostile(String(fa), String(fb), day)
					if bool(hostile.get("hostile", false)):
						found.append(_make(campaign_id, CAUSE_MUTUAL_HOSTILE, m_a, m_b,
							String(fa), String(fb), "", day,
							{"band_ab": hostile.get("band_ab"), "band_ba": hostile.get("band_ba")}))
					var conf: Dictionary = _opposite_sides(
						String(fa), String(fb), context, day)
					if bool(conf.get("opposite", false)):
						found.append(_make(campaign_id, CAUSE_OPPOSITE_CONFLICT, m_a, m_b,
							String(fa), String(fb), String(conf.get("conflict_id", "")), day,
							{"side_a": conf.get("side_a"), "side_b": conf.get("side_b")}))

	# (c): an explicit obligation whose target is another member's faction.
	for ob in context.get("obligations", []):
		var obligation: Dictionary = ob
		var owner: String = String(obligation.get("member_id", ""))
		var target_f: String = String(obligation.get("target_faction_id", ""))
		var source_f: String = String(obligation.get("source_faction_id", ""))
		if owner == "" or target_f == "":
			continue
		for other in members:
			if String(other) == owner:
				continue
			if by_member[String(other)].has(target_f):
				found.append(_make(campaign_id, CAUSE_OBLIGATION_TARGETS, owner, String(other),
					source_f, target_f, "", day, {"obligation": obligation}))

	# Persist + emit only for NEW conflicts (dedup on signature).
	var current: Array = []
	var seen_signatures: Dictionary = {}
	for descriptor in found:
		var d: Dictionary = descriptor
		var sig: String = String(d.get("signature", ""))
		# Two member pairs can manifest the SAME conflict (e.g. two members in faction X
		# vs one member in hostile faction Y produce the pairs (X1,Y1) and (X2,Y1), which
		# share the signature X|Y). Return each distinct conflict ONCE so the caller
		# doesn't render/mint it twice (review #7). The DB dedup already collapses the
		# persisted row + signal; this collapses the returned list to match.
		#
		# Granularity is per-SIGNATURE (cause + faction-pair + conflict_ref) — deliberately
		# owner-agnostic, matching the signature-keyed persistence. For an obligation
		# conflict this means two members owing the same source faction against the same
		# target surface as one entry; per-owner surfacing would require the owner in the
		# signature (a design decision for Jedidiah, not a bug).
		if seen_signatures.has(sig):
			continue
		seen_signatures[sig] = true
		var existing: Dictionary = CampaignRepository.ff_get_party_conflict_by_signature(
			campaign_id, sig)
		if existing.is_empty():
			CampaignRepository.ff_upsert_party_conflict(d)
			_emit(d)
			PoliticalAudit.record("party_loyalty_conflict", {
				"caller": "divided_loyalty_detector", "cause": d.get("cause"),
				"faction_a": d.get("faction_a_id"), "faction_b": d.get("faction_b_id"),
				"day": day, "signature": d.get("signature"),
			})
			PoliticalAudit.bump_counter("party_loyalty_conflicts")
			d["is_new"] = true
		else:
			d["is_new"] = false
			d["status"] = existing.get("status", "detected")
		d["content"] = _content_for(d)
		current.append(d)
	return current


## Mark a persisted conflict resolved (player did the job / refused / quit).
static func resolve(campaign_id: String, signature: String, resolution: String, day: int) -> Dictionary:
	var existing: Dictionary = CampaignRepository.ff_get_party_conflict_by_signature(campaign_id, signature)
	if existing.is_empty():
		return {"ok": false, "error": "no_conflict"}
	var status: String = "double_agent" if resolution == "double_agent" else "resolved"
	existing["status"] = status
	existing["resolved_day"] = day
	CampaignRepository.ff_upsert_party_conflict(existing)
	return {"ok": true, "status": status}


# ---------------------------------------------------------------------------
# Condition checks
# ---------------------------------------------------------------------------

## (a) Both factions hold each other at <= unfriendly.
static func _mutual_hostile(fa: String, fb: String, day: int) -> Dictionary:
	var band_ab: String = String(FactionStanceService.get_stance(fa, fb, day).get("public_stance", "neutral"))
	var band_ba: String = String(FactionStanceService.get_stance(fb, fa, day).get("public_stance", "neutral"))
	var hostile: bool = _band_index(band_ab) <= HOSTILE_BAND_MAX_INDEX \
		and _band_index(band_ba) <= HOSTILE_BAND_MAX_INDEX
	return {"hostile": hostile, "band_ab": band_ab, "band_ba": band_ba}


## (b) The two factions sit on opposite sides of a supplied active conflict.
static func _opposite_sides(fa: String, fb: String, context: Dictionary, day: int) -> Dictionary:
	for c in context.get("active_conflicts", []):
		var conf: Dictionary = c
		var side_a: String = String(conf.get("side_a_mirror", ""))
		var side_b: String = String(conf.get("side_b_mirror", ""))
		if side_a == "" or side_b == "":
			continue
		var a_leans_a: bool = _leans_toward(fa, side_a, side_b, day)
		var b_leans_b: bool = _leans_toward(fb, side_b, side_a, day)
		var a_leans_b: bool = _leans_toward(fa, side_b, side_a, day)
		var b_leans_a: bool = _leans_toward(fb, side_a, side_b, day)
		if (a_leans_a and b_leans_b) or (a_leans_b and b_leans_a):
			return {"opposite": true, "conflict_id": conf.get("conflict_id", ""),
				"side_a": side_a, "side_b": side_b}
	return {"opposite": false}


## A faction "leans toward" a side when it IS that side, or its PUBLIC stance toward
## that side is friendlier than toward the rival side (declared allegiance, §7.1).
static func _leans_toward(faction_id: String, side_mirror: String, rival_mirror: String, day: int) -> bool:
	if faction_id == side_mirror:
		return true
	if faction_id == rival_mirror:
		return false
	var to_side: int = _band_index(String(
		FactionStanceService.get_stance(faction_id, side_mirror, day).get("public_stance", "neutral")))
	var to_rival: int = _band_index(String(
		FactionStanceService.get_stance(faction_id, rival_mirror, day).get("public_stance", "neutral")))
	return to_side > to_rival and to_side >= _band_index("friendly")


# ---------------------------------------------------------------------------
# Descriptor + content
# ---------------------------------------------------------------------------

static func _make(campaign_id: String, cause: String, member_a: String, member_b: String,
		faction_a: String, faction_b: String, conflict_ref: String, day: int,
		extra: Dictionary) -> Dictionary:
	var signature: String = _signature(cause, faction_a, faction_b, conflict_ref)
	var d: Dictionary = {
		"campaign_id": campaign_id, "cause": cause,
		"member_a_id": member_a, "member_b_id": member_b,
		"faction_a_id": faction_a, "faction_b_id": faction_b,
		"conflict_ref": conflict_ref, "signature": signature,
		"status": "detected", "detected_day": day,
	}
	for k in extra.keys():
		d[k] = extra[k]
	return d


## Surface the conflict as CONTENT (§8.4): conflicting job offers / loyalty demands,
## never a UI modal. The org turn (post_job) mints the actual quests; this returns
## the content seeds a caller can render or hand to the quest layer.
static func _content_for(d: Dictionary) -> Array:
	match String(d.get("cause", "")):
		CAUSE_MUTUAL_HOSTILE:
			return [
				{"kind": "loyalty_demand", "faction_id": d.get("faction_a_id"), "member_id": d.get("member_a_id")},
				{"kind": "loyalty_demand", "faction_id": d.get("faction_b_id"), "member_id": d.get("member_b_id")},
			]
		CAUSE_OPPOSITE_CONFLICT:
			return [
				{"kind": "conflicting_job_offer", "faction_id": d.get("faction_a_id"), "member_id": d.get("member_a_id")},
				{"kind": "conflicting_job_offer", "faction_id": d.get("faction_b_id"), "member_id": d.get("member_b_id")},
			]
		CAUSE_OBLIGATION_TARGETS:
			return [
				{"kind": "prove_loyalty", "faction_id": d.get("faction_a_id"), "member_id": d.get("member_a_id"),
					"against_faction_id": d.get("faction_b_id")},
			]
		_:
			return []


static func _emit(d: Dictionary) -> void:
	if not EventBus.has_signal("party_loyalty_conflict_detected"):
		return
	EventBus.emit_signal("party_loyalty_conflict_detected",
		[String(d.get("member_a_id", "")), String(d.get("member_b_id", ""))],
		[String(d.get("faction_a_id", "")), String(d.get("faction_b_id", ""))],
		String(d.get("cause", "")))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## The non-terminal faction memberships a character holds (faction ids).
static func _member_factions(npc_id: String) -> Array:
	var out: Array = []
	for m in CampaignRepository.ff_list_memberships_for_character(npc_id):
		var status: String = String((m as Dictionary).get("status", "member"))
		if status in ACTIVE_MEMBERSHIP_STATUSES:
			out.append(String((m as Dictionary).get("faction_id", "")))
	out.sort()
	return out


## Deterministic signature: cause + the unordered faction pair + conflict ref, so a
## re-scan of the same situation dedups to the same row (order-independent).
static func _signature(cause: String, faction_a: String, faction_b: String, conflict_ref: String) -> String:
	var pair: Array = [faction_a, faction_b]
	pair.sort()
	return "%s|%s|%s|%s" % [cause, pair[0], pair[1], conflict_ref]


static func _band_index(band: String) -> int:
	var idx: int = FactionStanceData.BANDS.find(band)
	return idx if idx >= 0 else 2   # default neutral


static func _s(v: Variant, default_value: String = "") -> String:
	return str(v) if v != null else default_value
