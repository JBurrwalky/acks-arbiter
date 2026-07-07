class_name FactionEventLedger
extends RefCounted

## The inter-faction grievance/favor ledger writer (gdd-faction-framework.md
## §4.5 — FF-1.3). Append-only: every inter-faction deed becomes a faction_events
## row; a directed pair's grievance_score on faction_stances is the DECAYED
## ROLLING SUM of its live ledger rows, recomputed on each write.
##
## Expiry (§4.5): each kind ages out (default 60 months from its day);
## 'betrayal_executed' NEVER expires and permanently floors its contribution.
## Deterministic — no RNG, no wall-clock; the caller passes the game `day`.
## Banker's rounding on the decayed-sum recompute (MathUtils.bankers_round).

const DAYS_PER_MONTH: int = 28   # Timekeeping.DAYS_PER_MONTH


## Record one ledger deed and refresh the target pair's grievance_score.
##
## [param actor_faction_id] did something to [param target_faction_id]; the deed
## is remembered on the DIRECTED pair (target's view of actor — the target holds
## the grievance/favor). [param kind] must be in FactionLedgerEntry.KINDS.
## [param magnitude] is the signed weight (positive = favor, negative =
## grievance; PROJECT CALL at the call site). [param data] is a JSON detail
## string. Returns the new ledger row id, or "" on failure.
static func record(campaign_id: String, day: int, actor_faction_id: String,
		target_faction_id: String, kind: String, magnitude: int,
		data: String = "{}") -> String:
	if campaign_id == "" or actor_faction_id == "" or target_faction_id == "":
		push_error("FactionEventLedger.record: empty required id")
		return ""
	if not FactionLedgerEntry.KINDS.has(kind):
		push_error("FactionEventLedger.record: unknown kind '%s'" % kind)
		return ""

	var entry := FactionLedgerEntry.new()
	entry.campaign_id = campaign_id
	entry.day = day
	entry.actor_faction_id = actor_faction_id
	entry.target_faction_id = target_faction_id
	entry.kind = kind
	entry.magnitude = magnitude
	entry.data = data
	# Never-expire kinds pass expires_day 0 (→ SQL NULL); others get the window.
	if FactionLedgerEntry.kind_never_expires(kind):
		entry.expires_day = 0
	else:
		entry.expires_day = day + FactionLedgerEntry.DEFAULT_EXPIRY_MONTHS * DAYS_PER_MONTH

	var id: String = CampaignRepository.ff_append_faction_event(entry)
	if id == "":
		return ""

	# The grievance is held by the TARGET toward the ACTOR (target→actor pair).
	var new_score: int = recompute_grievance(target_faction_id, actor_faction_id, day)
	_persist_grievance(campaign_id, target_faction_id, actor_faction_id, new_score, day)

	PoliticalAudit.record("ledger_record", {
		"caller": "faction_event_ledger",
		"actor": actor_faction_id, "target": target_faction_id,
		"day": day, "kind": kind, "magnitude": magnitude,
		"grievance_after": new_score,
	})
	return id


## The decayed rolling sum of live ledger rows on the directed pair
## (observer→subject: the observer holds the grievance/favor toward the subject).
## Live = expires_day IS NULL (never expires) OR expires_day > as_of_day.
## Each row's contribution linearly decays from full magnitude at its `day` to
## zero at its expiry; never-expire rows contribute full magnitude forever.
## Banker's rounding on the final sum.
static func recompute_grievance(observer_faction_id: String, subject_faction_id: String,
		as_of_day: int) -> int:
	var rows: Array = CampaignRepository.ff_list_faction_events(
		subject_faction_id, observer_faction_id, as_of_day)
	var total: float = 0.0
	for row_v in rows:
		var e := FactionLedgerEntry.from_dict(row_v)
		total += _contribution(e, as_of_day)
	return MathUtils.bankers_round(total)


## A single row's decayed contribution at [param as_of_day]. Never-expire kinds
## contribute their full magnitude permanently (a betrayal is never forgiven,
## §4.5). Expiring rows decay linearly from full at `day` to 0 at `expires_day`;
## rows already past expiry contribute 0 (they are also filtered out upstream).
static func _contribution(entry: FactionLedgerEntry, as_of_day: int) -> float:
	if FactionLedgerEntry.kind_never_expires(entry.kind) or entry.expires_day <= 0:
		return float(entry.magnitude)
	if as_of_day <= entry.day:
		return float(entry.magnitude)
	if as_of_day >= entry.expires_day:
		return 0.0
	var span: float = float(entry.expires_day - entry.day)
	if span <= 0.0:
		return float(entry.magnitude)
	var remaining: float = float(entry.expires_day - as_of_day) / span
	return float(entry.magnitude) * remaining


## Write the recomputed grievance_score onto the instantiated stance row for the
## directed pair, if one exists. A ledger deed does NOT itself instantiate a
## stance (lazy instantiation, §3.2); the score is stored when the pair already
## has a row, and otherwise recomputed on demand by callers. We DO create/refresh
## the row here when a non-zero grievance needs a home, so grievance survives —
## but only for non-realm-mirror pairs (authority split, §3.1: realm↔realm
## grievance rides realm_relations, not faction_stances).
static func _persist_grievance(campaign_id: String, observer_faction_id: String,
		subject_faction_id: String, score: int, day: int) -> void:
	# Never write a realm-mirror↔realm-mirror stance row (§3.1).
	if FactionRegistry.is_realm_mirror(observer_faction_id) \
			and FactionRegistry.is_realm_mirror(subject_faction_id):
		return
	var row: Dictionary = CampaignRepository.ff_get_stance_row(observer_faction_id, subject_faction_id)
	if row.is_empty():
		if score == 0:
			return   # nothing to store; leave the pair un-instantiated
		var stance := FactionStanceData.new()
		stance.campaign_id = campaign_id
		stance.faction_a_id = observer_faction_id
		stance.faction_b_id = subject_faction_id
		# Seed public_stance from the structural default so the row is coherent.
		var effective: Dictionary = FactionStanceService.get_stance(
			observer_faction_id, subject_faction_id, day)
		stance.public_stance = String(effective.get("public_stance", "neutral"))
		stance.grievance_score = score
		stance.last_evaluated_day = day
		CampaignRepository.ff_upsert_stance(stance)
		return
	var existing := FactionStanceData.from_dict(row)
	existing.grievance_score = score
	CampaignRepository.ff_upsert_stance(existing)
