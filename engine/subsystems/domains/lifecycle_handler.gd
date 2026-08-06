class_name LifecycleHandler
extends RefCounted

## Domain lifecycle state machine per docs/phase-11-plan.md §11B and
## gdd-domain-tab.md §13.3 (lifecycle status surfaces).
##
## The `domains.lifecycle_state` column (migration 122) is the canonical
## authority on whether a domain is mechanically alive. Resolvers and UI
## surfaces read this column; this module is the ONLY place that writes it.
##
## States:
##   active                — normal operation; monthly tick resolves
##   ruined_stronghold     — shp=0; grace until rebuild or auto-abandon
##   succession_pending    — Phase 11C: ruler died, 1-month grace
##   abandoned             — terminal; voluntary or grace lapsed
##   lost_to_foreign       — terminal; conquered by extra-campaign realm
##
## Public API (all static):
##   record_establishment(campaign_id, domain_id, calendar_day, method, founder_id) -> bool
##   conquer_domain(domain_id, calendar_day, conqueror_kind, conqueror_id,
##                  pillage_summary) -> bool
##   abandon_domain(domain_id, calendar_day, reason,
##                  liquidate_to_character_id) -> bool
##   mark_stronghold_collapsed(domain_id, stronghold_id, calendar_day) -> bool
##   restore_from_ruin(domain_id, stronghold_id, calendar_day) -> bool
##   tick_lifecycle_state(domain_data, calendar_day) -> Dictionary
##
## Every state mutation: writes the domains row (via
## `CampaignRepository.update_domain_lifecycle_state` for the lifecycle
## columns; also reassigns owner / releases hexes / liquidates treasury as
## the transition demands), writes a `domain_departure_log` entry via
## `DepartureLogRecorder`, emits the appropriate EventBus signal.

## Phase 11B's `CONQUEROR_PLAYER` / `CONQUEROR_SAME_CAMPAIGN_NPC` /
## `CONQUEROR_FOREIGN_REALM` constants were deleted in 11D-prereq.0b
## alongside the conquest-taxonomy revision. The 3-outcome `OUTCOME_*`
## constants below are the canonical dispatch.

const REASON_VOLUNTARY := "voluntary"
const REASON_RULER_BANKRUPT := "ruler_bankrupt"
const REASON_STRONGHOLD_COLLAPSED := "stronghold_collapsed"
const REASON_NO_HEIR := "no_heir"
const VALID_ABANDON_REASONS := [
	REASON_VOLUNTARY,
	REASON_RULER_BANKRUPT,
	REASON_STRONGHOLD_COLLAPSED,
	REASON_NO_HEIR,
]

const STATE_ACTIVE := "active"
const STATE_RUINED_STRONGHOLD := "ruined_stronghold"
const STATE_SUCCESSION_PENDING := "succession_pending"
const STATE_ABANDONED := "abandoned"
## Migration 125 renamed 'lost_to_foreign' → 'salted_to_ruin' per the
## 11D-prereq.0b conquest-taxonomy revision; STATE_LOST_TO_FOREIGN deleted.
const STATE_SALTED_TO_RUIN := "salted_to_ruin"

## 11D-prereq.0b conquest outcomes (mirrors RealmRepository.OUTCOME_*).
const OUTCOME_OCCUPIED := "occupied"
const OUTCOME_LOOTED_LOCAL_SUCCESSION := "looted_local_succession"
const OUTCOME_SALTED_TO_RUIN := "salted_to_ruin"
const VALID_CONQUEST_OUTCOMES := [
	OUTCOME_OCCUPIED,
	OUTCOME_LOOTED_LOCAL_SUCCESSION,
	OUTCOME_SALTED_TO_RUIN,
]

## Ruined-stronghold grace period in days. RAW is silent on the exact
## window; the project picks 1 game-month per gdd-domain-tab.md §13.3
## ("if not rebuilt within 1 game-month, abandonment fires automatically").
const RUINED_GRACE_DAYS := 30


# ---------------------------------------------------------------------------
# Establishment
# ---------------------------------------------------------------------------

## Phase 11B: chronicle a domain establishment to the departure log. Called
## from `EstablishDomainFlow.establish_domain` AFTER the row inserts but
## BEFORE its existing `domain_established` signal — so any listener that
## scrolls back to the founding entry already sees a log row.
static func record_establishment(
	campaign_id: String,
	domain_id: String,
	calendar_day: int,
	method: String,
	founder_id: String,
) -> bool:
	if campaign_id.is_empty() or domain_id.is_empty():
		return false
	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"established",
		"Domain established via %s" % method,
		{"founder_id": founder_id, "method": method})
	return true


# ---------------------------------------------------------------------------
# Conquest (Phase 11D-prereq.0b — three-outcome taxonomy)
# ---------------------------------------------------------------------------

## A domain has been taken by force. Three outcomes from the defender's POV:
##
##   OUTCOME_OCCUPIED — domain row persists; hexes + population preserved
##     (minus pillage); ownership reassigns to `new_owner_id`. The new owner
##     may be an existing tracked NPC, a PC, or (when the attacker is off-map)
##     the head NPC of a realm just instantiated by
##     `RealmRepository.instantiate_realm_for_off_map_force(...)` — at this
##     layer all three look the same. Vassals cascade to 'departed'.
##   OUTCOME_LOOTED_LOCAL_SUCCESSION — attacker took treasury + left; the
##     siege bridge has already called `RealmRepository.spawn_local_succession_npc`
##     to mint a local heir and `new_owner_id` is that heir's character_id.
##     Hexes + reduced population preserved.
##   OUTCOME_SALTED_TO_RUIN — terminal. Hexes release, treasury forfeit,
##     stronghold collapses to ruin per DaW salt-the-earth pillage rules.
##     Vassals cascade. Domain row stays for audit.
##
## Pillage is applied via `RealmRepository.apply_pillage(domain_id, severity)`
## for all three outcomes. The resolver decides severity:
##   * OUTCOME_OCCUPIED → severity 0 (no-op).
##   * OUTCOME_LOOTED_LOCAL_SUCCESSION → severity 1 (light).
##   * OUTCOME_SALTED_TO_RUIN → severity 2 (heavy) before terminal transition.
static func conquer_domain(
	domain_id: String,
	calendar_day: int,
	outcome: String,
	new_owner_id: String,
	pillage_severity: int,
	summary: Dictionary = {},
) -> bool:
	if domain_id.is_empty():
		push_error("LifecycleHandler.conquer_domain: domain_id is required")
		return false
	if not VALID_CONQUEST_OUTCOMES.has(outcome):
		push_error("LifecycleHandler.conquer_domain: invalid outcome '%s'" % outcome)
		return false
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		push_error("LifecycleHandler.conquer_domain: domain not found: %s" % domain_id)
		return false
	var campaign_id: String = String(domain.get("campaign_id", ""))
	var prior_owner: String = String(domain.get("owner_character_id", ""))

	# --- VALIDATION GATE ---------------------------------------------------
	# EVERY reason this call can be refused is checked HERE, before the first
	# side effect. Until 2026-07-31 `apply_pillage` and `_cascade_vassals` ran
	# first and the outcome-specific checks below could then return false — so a
	# REFUSED conquest still pillaged the domain and still marked every one of
	# the prior owner's vassals 'departed'. The domain survived with its realm
	# destroyed. See docs/domain-acquisition-audit-2026-07-28.md
	# (`refused-conquest-corrupts-vassal-state`).
	#
	# Invariant to preserve: conquer_domain either returns false having changed
	# NOTHING, or returns true having applied every effect.
	if outcome == OUTCOME_OCCUPIED or outcome == OUTCOME_LOOTED_LOCAL_SUCCESSION:
		if new_owner_id.is_empty():
			push_error(
				"LifecycleHandler.conquer_domain: %s requires new_owner_id%s" % [
					outcome,
					" (caller must spawn_local_succession_npc first)" \
						if outcome == OUTCOME_LOOTED_LOCAL_SUCCESSION else ""])
			return false
	# Phase 11D.4 defense-in-depth per gdd-domain-style-and-alignment.md §9.1:
	# the eligibility matrix (§7) blocks lawful/neutral conquerors from
	# beastman-populated targets. The siege bridge in
	# DomainHandlers._on_siege_concluded SHOULD consult the matrix before
	# reaching here, but tests + direct programmatic calls don't always go
	# through the canonical pipeline. We re-check at this boundary and refuse.
	#
	# OUTCOME_LOOTED_LOCAL_SUCCESSION is exempt: the local NPC was just spawned
	# by RealmRepository.spawn_local_succession_npc to match the domain, so it
	# inherently inherits the domain's population kind.
	if outcome == OUTCOME_OCCUPIED and not _conquest_eligible(domain, new_owner_id):
		push_error(
			"LifecycleHandler.conquer_domain: OUTCOME_OCCUPIED blocked — "
			+ "lawful/neutral conqueror cannot rule beastman-populated "
			+ "domain (gdd-domain-style-and-alignment.md §7.4 + §9.1)")
		return false
	# --- END VALIDATION GATE; every path below commits ---------------------

	# Apply pillage damage (no-op for severity 0).
	var pillage_result: Dictionary = RealmRepository.apply_pillage(
		domain_id, pillage_severity)

	# The domain's own oath upward ends on every outcome — its overlord has lost it.
	_detach_upward_edge(domain_id, calendar_day)

	match outcome:
		OUTCOME_OCCUPIED:
			CampaignRepository.reassign_domain_owner(domain_id, new_owner_id)
			# Lifecycle stays 'active' — the row continues to tick.
		OUTCOME_LOOTED_LOCAL_SUCCESSION:
			CampaignRepository.reassign_domain_owner(domain_id, new_owner_id)
		OUTCOME_SALTED_TO_RUIN:
			# Terminal: release hexes + set state. Treasury already zeroed by
			# apply_pillage (severity 2 includes full treasury loot).
			CampaignRepository.update_domain_lifecycle_state(
				domain_id, STATE_SALTED_TO_RUIN, calendar_day, 0)
			CampaignRepository.release_domain_hexes(domain_id)

	# R-5 (DOWNWARD): the fiefs held OF this domain. A domain salted to ruin has no
	# lord left to swear to, so those oaths simply end; a domain that survives under
	# a new owner gives each sub-vassal a loyalty roll against the man who took his
	# lord's place, at RAW's alignment modifiers plus the ruling's -2 for conquest.
	#
	# ORDER MATTERS. This runs BEFORE `domain_conquered` is emitted, so the
	# sub-vassals are already re-pointed (or gone) by the time
	# `VassalLoyaltyTriggers._on_domain_conquered` fires the PRIOR owner's "my lord
	# lost a stronghold" roll over his remaining vassals. Without that ordering the
	# same vassal would roll twice for one conquest.
	var sub_vassal_reports: Array = []
	if outcome == OUTCOME_SALTED_TO_RUIN:
		_detach_downward_edges(domain_id, calendar_day)
	else:
		sub_vassal_reports = SubVassalLoyalty.roll_for_transfer(
			domain_id, prior_owner, new_owner_id,
			SubVassalLoyalty.ACQ_CONQUEST, calendar_day)

	# Departure-log entry. Summary carries the outcome + new owner + pillage
	# result so future readers can reconstruct what happened end-to-end.
	var log_payload: Dictionary = {
		"outcome": outcome,
		"new_owner_id": new_owner_id,
		"prior_owner_id": prior_owner,
		"pillage_severity": pillage_severity,
		"pillage_result": pillage_result,
		"sub_vassal_transfers": sub_vassal_reports,
	}
	for k in summary.keys():
		log_payload[k] = summary[k]
	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"conquered",
		_summary_text_for_outcome(outcome, new_owner_id),
		log_payload)
	# Signal payload changed at 0b: (domain_id, outcome, new_owner_id) per
	# the polymorphic-new-owner-id pattern documented in coding_conventions §61.
	EventBus.domain_conquered.emit(domain_id, outcome, new_owner_id, prior_owner)
	return true


static func _summary_text_for_outcome(outcome: String, new_owner_id: String) -> String:
	match outcome:
		OUTCOME_OCCUPIED:
			return "Domain occupied; new ruler: %s" % new_owner_id
		OUTCOME_LOOTED_LOCAL_SUCCESSION:
			return "Domain looted; local successor %s now rules" % new_owner_id
		OUTCOME_SALTED_TO_RUIN:
			return "Domain salted to ruin"
		_:
			return "Domain conquered (%s)" % outcome


# ---------------------------------------------------------------------------
# Abandonment
# ---------------------------------------------------------------------------

## Phase 11B: a domain has been abandoned.
##
## Reasons:
##   voluntary             — player action; treasury liquidates to
##                           liquidate_to_character_id (the abdicating ruler).
##   ruler_bankrupt        — domain can no longer pay its expenses (project-
##                           designed trigger; not auto-fired yet).
##   stronghold_collapsed  — ruined-stronghold grace lapsed without rebuild.
##                           No liquidation: the ruler has no stronghold to
##                           transfer funds from.
##   no_heir               — Phase 11C: succession grace lapsed without an
##                           heir designation.
##
## In all cases: lifecycle_state -> 'abandoned', hexes released, vassals
## cascade to 'departed'. The departure log records who/why.
static func abandon_domain(
	domain_id: String,
	calendar_day: int,
	reason: String,
	liquidate_to_character_id: String = "",
) -> bool:
	if domain_id.is_empty():
		push_error("LifecycleHandler.abandon_domain: domain_id is required")
		return false
	if not VALID_ABANDON_REASONS.has(reason):
		push_error("LifecycleHandler.abandon_domain: invalid reason '%s'" % reason)
		return false
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		push_error("LifecycleHandler.abandon_domain: domain not found: %s" % domain_id)
		return false
	var campaign_id: String = String(domain.get("campaign_id", ""))
	var prior_owner: String = String(domain.get("owner_character_id", ""))

	# Treasury handling: always zero the domain row's cp on abandon — the
	# domain is gone. If liquidate_to_character_id is named, credit it to
	# that character's coin; otherwise the cp is forfeit (no recipient).
	var liquidated_cp: int = CampaignRepository.get_domain_treasury_cp(domain_id)
	if liquidated_cp > 0:
		CampaignRepository.adjust_domain_treasury(domain_id, -liquidated_cp)
		if not liquidate_to_character_id.is_empty():
			CampaignRepository.add_coins_cp(liquidate_to_character_id, liquidated_cp)
		else:
			liquidated_cp = 0  # report 0 in the log when there's no recipient

	# Cascade vassals + release hexes. An abandoned domain has no successor lord,
	# so both directions simply detach — there is nobody for the sub-vassals to
	# roll loyalty AGAINST (contrast conquest, which hands them a new lord).
	_detach_upward_edge(domain_id, calendar_day)
	_detach_downward_edges(domain_id, calendar_day)
	CampaignRepository.release_domain_hexes(domain_id)
	CampaignRepository.update_domain_lifecycle_state(
		domain_id, STATE_ABANDONED, calendar_day, 0)

	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"abandoned",
		"Abandoned: %s" % reason,
		{
			"reason": reason,
			"prior_owner_id": prior_owner,
			"liquidated_to_character_id": liquidate_to_character_id,
			"liquidated_cp": liquidated_cp,
		})
	EventBus.domain_abandoned.emit(domain_id, reason)
	return true


# ---------------------------------------------------------------------------
# Stronghold collapse + restore
# ---------------------------------------------------------------------------

## Phase 11B: the domain's stronghold has fallen to 0 shp. The domain enters
## the ruined_stronghold grace window (1 game-month). If the stronghold is
## rebuilt before grace expires, `restore_from_ruin` flips state back to
## active; otherwise `tick_lifecycle_state` auto-fires
## `abandon_domain(..., REASON_STRONGHOLD_COLLAPSED)` at the daily boundary
## past the grace day.
static func mark_stronghold_collapsed(
	domain_id: String,
	stronghold_id: String,
	calendar_day: int,
) -> bool:
	if domain_id.is_empty():
		push_error("LifecycleHandler.mark_stronghold_collapsed: domain_id is required")
		return false
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		push_error("LifecycleHandler.mark_stronghold_collapsed: domain not found: %s" % domain_id)
		return false
	# Re-entry is a no-op: if we're already in ruined_stronghold state, don't
	# extend the grace (that would let an attacker keep the domain in limbo by
	# repeatedly destroying its strongholds).
	if String(domain.get("lifecycle_state", STATE_ACTIVE)) == STATE_RUINED_STRONGHOLD:
		return true
	var campaign_id: String = String(domain.get("campaign_id", ""))
	var grace_until: int = calendar_day + RUINED_GRACE_DAYS
	CampaignRepository.update_domain_lifecycle_state(
		domain_id, STATE_RUINED_STRONGHOLD, calendar_day, grace_until)
	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"stronghold_lost",
		"Stronghold collapsed; grace until day %d" % grace_until,
		{"stronghold_id": stronghold_id, "grace_until_day": grace_until})
	EventBus.stronghold_collapsed.emit(domain_id, stronghold_id)
	return true


## Phase 11B: a ruined-stronghold domain was rebuilt to >= 1 shp before the
## grace lapsed. Returns it to active state.
static func restore_from_ruin(
	domain_id: String,
	stronghold_id: String,
	calendar_day: int,
) -> bool:
	if domain_id.is_empty():
		return false
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		return false
	if String(domain.get("lifecycle_state", STATE_ACTIVE)) != STATE_RUINED_STRONGHOLD:
		# Restore only makes sense when we are currently ruined.
		return false
	var campaign_id: String = String(domain.get("campaign_id", ""))
	CampaignRepository.update_domain_lifecycle_state(
		domain_id, STATE_ACTIVE, calendar_day, 0)
	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"restored",
		"Stronghold rebuilt; domain restored before grace lapse",
		{"stronghold_id": stronghold_id})
	EventBus.stronghold_restored.emit(domain_id, stronghold_id)
	return true


# ---------------------------------------------------------------------------
# Monthly-tick hook
# ---------------------------------------------------------------------------

## Phase 11B: end-of-month lifecycle check. Called from
## `DomainHandlers._resolve_domain_month` after the regular monthly resolution.
## Currently the only grace this checks is the ruined_stronghold window;
## Phase 11C's succession grace lives in its own handler.
##
## Returns a Dictionary summary: { auto_abandoned: bool, reason: String }.
static func tick_lifecycle_state(
	domain_data: Dictionary,
	calendar_day: int,
) -> Dictionary:
	var domain_id: String = String(domain_data.get("id", ""))
	if domain_id.is_empty():
		return {"auto_abandoned": false, "reason": ""}
	var state: String = String(domain_data.get("lifecycle_state", STATE_ACTIVE))
	if state != STATE_RUINED_STRONGHOLD:
		return {"auto_abandoned": false, "reason": ""}
	var grace_until: int = int(domain_data.get("ruined_stronghold_grace_until_day", 0))
	if calendar_day < grace_until:
		return {"auto_abandoned": false, "reason": ""}
	# Grace lapsed. Fire abandonment. Treasury forfeit (no rebuild ⇒ no
	# stronghold to retrieve cp from per the design note in §13.3).
	abandon_domain(domain_id, calendar_day, REASON_STRONGHOLD_COLLAPSED, "")
	return {"auto_abandoned": true, "reason": REASON_STRONGHOLD_COLLAPSED}


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _get_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ?", [domain_id]
	) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


## UPWARD: this domain's own oath ends — its overlord has lost it.
##
## R-5 split this out of the old `_cascade_vassals`, which handled both directions
## with the same blunt "mark everything departed". The two directions are not
## symmetrical: losing a domain always ends ITS oath upward, but what happens to
## the fiefs held OF it depends on whether anyone is left to hold them of.
##
## Clears BOTH records, per conventions §135. The old code departed the assignment
## and left `domains.liege_domain_id` pointing at the overlord — the two sources of
## truth then disagreed, and because the downward cascade finds vassals THROUGH
## that pointer, the stale edge became permanently unreachable.
static func _detach_upward_edge(domain_id: String, calendar_day: int) -> void:
	if CampaignRepository.db.query_with_bindings("""
		SELECT id FROM vassal_assignments
		WHERE vassal_domain_id = ? AND status = 'active'
	""", [domain_id]):
		for row: Dictionary in CampaignRepository.db.query_result.duplicate():
			VassalRepository.update_status(
				str(row.get("id", "")), "departed", calendar_day)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = NULL, updated_at = datetime('now') WHERE id = ?",
		[domain_id])


## DOWNWARD, when there is no new lord to swear to: the domain is gone (salted to
## ruin, or abandoned), so the fiefs held of it are simply released.
##
## When a domain survives under a NEW owner, do NOT call this — the sub-vassals get
## `SubVassalLoyalty.roll_for_transfer` instead and decide for themselves whether
## to serve him (R-5).
##
## Scoped by the authoritative `liege_domain_id` pointer (R-1), never liege-wide by
## character: before R-1 this was `list_active_for_liege(prior_owner)`, which would
## have dissolved a duke's ENTIRE realm on the loss of one frontier barony.
##
## Assignments with a NULL `vassal_domain_id` are deliberately untouched — those
## are personal oaths with no fief attached, sworn to the ruler rather than to one
## of his domains, so a lord who loses one domain does not lose his household.
static func _detach_downward_edges(domain_id: String, calendar_day: int) -> void:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT va.id AS assignment_id, vd.id AS vassal_domain_id
		FROM vassal_assignments va
		JOIN domains vd ON vd.id = va.vassal_domain_id
		WHERE va.status = 'active' AND vd.liege_domain_id = ?
	""", [domain_id]):
		return
	for row: Dictionary in CampaignRepository.db.query_result.duplicate():
		VassalRepository.update_status(
			str(row.get("assignment_id", "")), "departed", calendar_day)
		CampaignRepository.db.query_with_bindings(
			"UPDATE domains SET liege_domain_id = NULL, updated_at = datetime('now') WHERE id = ?",
			[str(row.get("vassal_domain_id", ""))])



## Phase 11D.4 — eligibility check per gdd-domain-style-and-alignment.md §7.4 + §9.1.
## Returns false when the new owner is a lawful or neutral character AND the
## defender domain is beastman-populated (per §9.7's population-kind inference:
## establishment_method in clanhold_annex / recruit_chieftain). Returns true
## otherwise — including all chaotic-conqueror cases and all non-beastman targets.
##
## Defense-in-depth: the siege bridge should call EstablishDomainFlow's
## eligibility validator before invoking conquer_domain, but tests + direct
## programmatic calls bypass the canonical pipeline. This function repeats
## the check at the conquest boundary so a malformed call cannot install a
## forbidden ruler.
static func _conquest_eligible(domain: Dictionary, new_owner_id: String) -> bool:
	if new_owner_id.is_empty():
		return false
	# Identify whether the defender domain is beastman-populated.
	var method: String = String(domain.get("establishment_method", "")).to_lower()
	var domain_is_beastman: bool = method in ["clanhold_annex", "recruit_chieftain"]
	if not domain_is_beastman:
		return true
	# Beastman target: lawful/neutral conquerors are blocked per §7.4.
	var new_owner: Dictionary = CampaignRepository.get_character(new_owner_id)
	if new_owner.is_empty():
		# Unknown character — fail conservative (block the conquest).
		return false
	var new_owner_alignment: String = String(new_owner.get("alignment", "neutral")).to_lower()
	return new_owner_alignment == "chaotic"
