class_name RulerDeathHandler
extends RefCounted

## Domain succession state machine per docs/phase-11-plan.md §11C and
## gdd-domain-tab.md §16.5.
##
## When a ruler dies, every active domain they own enters
## `lifecycle_state='succession_pending'` for SUCCESSION_GRACE_DAYS days.
## During the grace the player may designate an heir from the eligible
## candidate list. On manual confirm OR grace expiry, the succession resolves:
##   - Independent domain + designated heir → transfer ownership.
##   - Independent domain + no heir at grace → abandonment via LifecycleHandler.
##   - Vassal domain + designated heir → transfer ownership.
##   - Vassal domain + no heir at grace → reverts to overlord (v1 default per
##     gdd-domain-tab.md §9; placeholder for the eventual Dynasties bloodline
##     model per memory/project_dynasties_succession.md).
##
## Non-henchman heirs (NPC-generator-populated candidates) inherit at
## base_loyalty_modifier = -2 per `acore_axioms` §non_henchman_vassals
## L392-397. This is applied via the existing vassal_assignments row when
## the heir is brought in as a vassal of an overlord; for independent-domain
## heirs the modifier is recorded on a future vassal_assignment row if/when
## the heir later swears fealty.
##
## Public API (all static):
##   handle_ruler_death(deceased_character_id, calendar_day) -> Array
##       Returns the list of domain_ids transitioned. Emits ruler_died +
##       succession_started per domain.
##   designate_heir(domain_id, heir_character_id, heir_kind) -> bool
##   resolve_succession(domain_id, calendar_day) -> Dictionary
##       { resolved: bool, new_owner_id: String, heir_kind: String,
##         reverted_to_overlord: bool, abandoned: bool }
##   tick_succession_grace(domain_data, calendar_day) -> Dictionary
##       { auto_resolved: bool, lapsed: bool }
##   eligible_heirs_for(domain_id) -> Array
##       Each entry: { character_id, name, kind, level, character_class }

const GRACE_DAYS := 30

const KIND_PC := "pc"
const KIND_HENCHMAN := "henchman"
const KIND_NON_HENCHMAN := "non_henchman"
const VALID_HEIR_KINDS := [KIND_PC, KIND_HENCHMAN, KIND_NON_HENCHMAN]

## Non-henchman vassal base loyalty modifier per `acore_axioms` §non_henchman_vassals.
const NON_HENCHMAN_LOYALTY_MODIFIER := -2


# ---------------------------------------------------------------------------
# Ruler death
# ---------------------------------------------------------------------------

## Phase 11C: a ruler died. Sweep every domain they own and place each in
## succession_pending state. Returns the list of transitioned domain_ids.
##
## This is the entry point for the `character_died` signal bridge in
## `DomainHandlers`. Idempotent: if a domain is already in a terminal state
## (abandoned / lost_to_foreign) it's skipped.
static func handle_ruler_death(
	deceased_character_id: String,
	calendar_day: int,
) -> Array:
	if deceased_character_id.is_empty():
		return []
	var domains: Array = CampaignRepository.list_domains_owned_by(
		deceased_character_id, false)
	if domains.is_empty():
		return []
	var affected: Array = []
	var grace_until: int = calendar_day + GRACE_DAYS
	for domain: Dictionary in domains:
		var domain_id: String = String(domain.get("id", ""))
		if domain_id.is_empty():
			continue
		var current_state: String = String(domain.get(
			"lifecycle_state", LifecycleHandler.STATE_ACTIVE))
		# Skip domains that are already in a terminal state. A ruined-stronghold
		# domain is allowed to transition to succession_pending (a stronghold
		# could be ruined right when the ruler dies); the ruined-grace stays
		# parallel.
		if current_state == LifecycleHandler.STATE_ABANDONED \
			or current_state == LifecycleHandler.STATE_SALTED_TO_RUIN:
			continue
		CampaignRepository.update_domain_succession_state(
			domain_id,
			LifecycleHandler.STATE_SUCCESSION_PENDING,
			grace_until,
			"",
			"",
			calendar_day)
		var campaign_id: String = String(domain.get("campaign_id", ""))
		DepartureLogRecorder.record(
			campaign_id, domain_id, calendar_day,
			"ruler_died",
			"Ruler %s died; succession-pending until day %d" % [
				deceased_character_id, grace_until],
			{
				"deceased_character_id": deceased_character_id,
				"grace_until_day": grace_until,
			})
		EventBus.succession_started.emit(domain_id, deceased_character_id, grace_until)
		affected.append(domain_id)
	if not affected.is_empty():
		EventBus.ruler_died.emit(deceased_character_id, affected)
	return affected


# ---------------------------------------------------------------------------
# Heir designation
# ---------------------------------------------------------------------------

## Phase 11C: record the player's heir choice. Does NOT resolve succession
## immediately — resolution happens on manual confirm (resolve_succession)
## or at grace expiry (tick_succession_grace). The choice is overwritten
## by subsequent calls; this method is idempotent.
static func designate_heir(
	domain_id: String,
	heir_character_id: String,
	heir_kind: String,
) -> bool:
	if domain_id.is_empty():
		push_error("RulerDeathHandler.designate_heir: domain_id is required")
		return false
	if heir_character_id.is_empty():
		push_error("RulerDeathHandler.designate_heir: heir_character_id is required")
		return false
	if not VALID_HEIR_KINDS.has(heir_kind):
		push_error("RulerDeathHandler.designate_heir: invalid heir_kind '%s'" % heir_kind)
		return false
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		push_error("RulerDeathHandler.designate_heir: domain not found: %s" % domain_id)
		return false
	if String(domain.get("lifecycle_state", "")) != LifecycleHandler.STATE_SUCCESSION_PENDING:
		push_error("RulerDeathHandler.designate_heir: domain not in succession_pending")
		return false
	# Preserve grace columns; just update heir designation.
	if not CampaignRepository.db.query_with_bindings("""
		UPDATE domains
		SET designated_heir_character_id = ?,
		    designated_heir_kind = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [heir_character_id, heir_kind, domain_id]):
		push_error("RulerDeathHandler.designate_heir: SQL failed")
		return false
	EventBus.succession_heir_designated.emit(domain_id, heir_character_id, heir_kind)
	return true


# ---------------------------------------------------------------------------
# Succession resolution
# ---------------------------------------------------------------------------

## Phase 11C: resolve succession NOW. Called manually (player presses Confirm
## Succession) or automatically (tick_succession_grace at grace expiry).
##
## If a heir is designated → transfer ownership. If no heir AND vassal domain
## → revert to overlord. If no heir AND independent domain → fire abandonment
## via LifecycleHandler.abandon_domain(REASON_NO_HEIR).
static func resolve_succession(
	domain_id: String,
	calendar_day: int,
) -> Dictionary:
	if domain_id.is_empty():
		return _empty_resolution()
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		return _empty_resolution()
	if String(domain.get("lifecycle_state", "")) != LifecycleHandler.STATE_SUCCESSION_PENDING:
		return _empty_resolution()
	var heir_id: String = String(domain.get("designated_heir_character_id", ""))
	var heir_kind: String = String(domain.get("designated_heir_kind", ""))
	var campaign_id: String = String(domain.get("campaign_id", ""))
	# Heir designated: transfer ownership.
	if not heir_id.is_empty():
		_apply_heir(domain_id, heir_id, heir_kind, calendar_day)
		DepartureLogRecorder.record(
			campaign_id, domain_id, calendar_day,
			"succession_resolved",
			"Succession resolved: new ruler is %s (%s)" % [heir_id, heir_kind],
			{
				"new_owner_id": heir_id,
				"heir_kind": heir_kind,
				"non_henchman_loyalty_modifier": (
					NON_HENCHMAN_LOYALTY_MODIFIER if heir_kind == KIND_NON_HENCHMAN
					else 0),
			})
		EventBus.succession_resolved.emit(domain_id, heir_id, heir_kind)
		return {
			"resolved": true,
			"new_owner_id": heir_id,
			"heir_kind": heir_kind,
			"reverted_to_overlord": false,
			"abandoned": false,
		}
	# No heir designated.
	var overlord_id: String = _overlord_character_id(domain)
	if not overlord_id.is_empty():
		# Vassal domain reverts to overlord per the v1 default.
		_revert_to_overlord(domain_id, overlord_id, calendar_day)
		DepartureLogRecorder.record(
			campaign_id, domain_id, calendar_day,
			"succession_lapsed",
			"Succession lapsed; domain reverts to overlord %s" % overlord_id,
			{"overlord_id": overlord_id})
		EventBus.succession_lapsed.emit(domain_id)
		return {
			"resolved": true,
			"new_owner_id": overlord_id,
			"heir_kind": "",
			"reverted_to_overlord": true,
			"abandoned": false,
		}
	# Independent domain with no heir at grace lapse → abandonment.
	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"succession_lapsed",
		"Succession lapsed; no heir designated, abandonment fires",
		{})
	EventBus.succession_lapsed.emit(domain_id)
	LifecycleHandler.abandon_domain(
		domain_id, calendar_day,
		LifecycleHandler.REASON_NO_HEIR,
		"")
	return {
		"resolved": true,
		"new_owner_id": "",
		"heir_kind": "",
		"reverted_to_overlord": false,
		"abandoned": true,
	}


# ---------------------------------------------------------------------------
# Monthly-tick grace check
# ---------------------------------------------------------------------------

## Phase 11C: end-of-month succession grace check. Called from
## `DomainHandlers._resolve_domain_month` alongside the existing
## `LifecycleHandler.tick_lifecycle_state` call.
##
## Returns { auto_resolved: bool, lapsed: bool }. auto_resolved=true means the
## grace expired with a designated heir; lapsed=true means the grace expired
## without one (which fires abandonment-or-revert downstream).
static func tick_succession_grace(
	domain_data: Dictionary,
	calendar_day: int,
) -> Dictionary:
	var domain_id: String = String(domain_data.get("id", ""))
	if domain_id.is_empty():
		return {"auto_resolved": false, "lapsed": false}
	var state: String = String(domain_data.get(
		"lifecycle_state", LifecycleHandler.STATE_ACTIVE))
	if state != LifecycleHandler.STATE_SUCCESSION_PENDING:
		return {"auto_resolved": false, "lapsed": false}
	var grace_until: int = int(domain_data.get("succession_pending_until_day", 0))
	if calendar_day < grace_until:
		return {"auto_resolved": false, "lapsed": false}
	var heir_id: String = String(domain_data.get("designated_heir_character_id", ""))
	var result: Dictionary = resolve_succession(domain_id, calendar_day)
	return {
		"auto_resolved": not heir_id.is_empty(),
		"lapsed": heir_id.is_empty(),
	}


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

## Phase 11C: return candidates for the heir-picker UI. Order: PCs in the
## campaign first, then henchmen of any PC, then any non_henchman candidates
## (deferred — generator-populated NPCs land in a future polish).
##
## Excludes: dead characters; the deceased ruler; any character who already
## owns a non-terminal domain (avoid the "one PC inherits everything"
## degenerate state — surface them only if explicitly chosen via override).
static func eligible_heirs_for(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		return []
	var campaign_id: String = String(domain.get("campaign_id", ""))
	if campaign_id.is_empty():
		return []
	var out: Array = []
	# PCs.
	if CampaignRepository.db.query_with_bindings("""
		SELECT id, name, character_class, level, character_type
		FROM characters
		WHERE campaign_id = ? AND character_type = 'pc' AND is_active = 1
		ORDER BY name
	""", [campaign_id]):
		for row: Dictionary in CampaignRepository.db.query_result.duplicate():
			out.append({
				"character_id": str(row.get("id", "")),
				"name": str(row.get("name", "")),
				"kind": KIND_PC,
				"level": int(row.get("level", 0)),
				"character_class": str(row.get("character_class", "")),
			})
	# Henchmen (any employer).
	if CampaignRepository.db.query_with_bindings("""
		SELECT id, name, character_class, level
		FROM characters
		WHERE campaign_id = ? AND character_type = 'henchman' AND is_active = 1
		ORDER BY name
	""", [campaign_id]):
		for row: Dictionary in CampaignRepository.db.query_result.duplicate():
			out.append({
				"character_id": str(row.get("id", "")),
				"name": str(row.get("name", "")),
				"kind": KIND_HENCHMAN,
				"level": int(row.get("level", 0)),
				"character_class": str(row.get("character_class", "")),
			})
	# Non-henchman generator candidates: not yet implemented; future polish.
	return out


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


## Return the overlord PC's character_id if this domain is a vassal of someone
## else, "" otherwise. The realm graph uses `domains.liege_domain_id` →
## overlord domain → overlord's owner_character_id.
static func _overlord_character_id(domain: Dictionary) -> String:
	# §106: `domains.liege_domain_id` is NULLABLE — an unlanded/top-level domain
	# has no liege, and `.get(k, default)` returns the STORED null, so the ""
	# default never protected this. Threw at runtime.
	var liege_domain_id: String = StringUtils.s(domain.get("liege_domain_id"))
	if liege_domain_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id FROM domains WHERE id = ?", [liege_domain_id]
	) or CampaignRepository.db.query_result.is_empty():
		return ""
	# §106: nullable — the liege domain may itself be between rulers.
	return StringUtils.s(CampaignRepository.db.query_result[0].get("owner_character_id"))


## Apply heir designation: transfer ownership, clear succession columns,
## return lifecycle_state to active, and put the dead ruler's sub-vassals to the
## question of whether they will serve his heir.
static func _apply_heir(
	domain_id: String,
	heir_id: String,
	heir_kind: String,
	calendar_day: int,
) -> void:
	# §106: owner_character_id is nullable — StringUtils.s is the null-safe read.
	var prior_owner: String = StringUtils.s(
		CampaignRepository.get_domain(domain_id).get("owner_character_id"))
	CampaignRepository.reassign_domain_owner(domain_id, heir_id)
	CampaignRepository.update_domain_succession_state(
		domain_id,
		LifecycleHandler.STATE_ACTIVE,
		0,
		"",
		"",
		calendar_day)
	# R-5, "any change of liege" (Jedidiah ruling). Succession is a change of lord
	# like any other, and the most common one in a dynastic game. Without this the
	# sub-vassal edges keep naming the DEAD ruler as their liege — invisible while
	# world generation left `vassal_assignments` empty, a stale pointer at a corpse
	# once R-1 filled it.
	#
	# RE-POINT ONLY, NO ROLL. `resolve_succession` emits `succession_resolved`
	# immediately after this, and `VassalLoyaltyTriggers._on_succession_resolved`
	# already fires RAW §5.2's "liege succession" check over the HEIR's active
	# vassals — which, thanks to the re-point above, now includes these. Rolling
	# here too would roll each inherited vassal TWICE for one death, the second roll
	# consuming the one-shot Grudging −1 the first had just written for the NEXT
	# check. (Conquest is different and DOES roll in place: its trigger fires over
	# the PRIOR owner, off whom the vassals have already moved.)
	SubVassalLoyalty.repoint_direct_sub_vassals(domain_id, heir_id, calendar_day)


## Vassal-reverts-to-overlord transition: ownership transfers to the overlord
## directly, the vassal_assignments row that ties the deceased ruler to the
## overlord terminates. Liege chain is preserved on the row but the domain
## itself is now under direct rule. (When Dynasties ships, this fallback will
## be replaced by the bloodline-heir resolver.)
static func _revert_to_overlord(
	domain_id: String,
	overlord_id: String,
	calendar_day: int,
) -> void:
	# Terminate the deceased-ruler vassal_assignment (if any).
	if CampaignRepository.db.query_with_bindings("""
		SELECT id FROM vassal_assignments
		WHERE vassal_domain_id = ? AND status = 'active'
	""", [domain_id]):
		for row: Dictionary in CampaignRepository.db.query_result.duplicate():
			VassalRepository.update_status(
				str(row.get("id", "")), "departed", calendar_day)
	# R-5: the escheated domain's OWN sub-vassals now answer to the overlord — a
	# change of liege, so they roll. Runs before the ownership move so the roll can
	# still see who held the domain; escheat is a lawful succession, not a
	# conquest, so it carries no acquisition penalty.
	var prior_owner: String = StringUtils.s(
		CampaignRepository.get_domain(domain_id).get("owner_character_id"))
	CampaignRepository.reassign_domain_owner(domain_id, overlord_id)
	SubVassalLoyalty.roll_for_transfer(
		domain_id, prior_owner, overlord_id,
		SubVassalLoyalty.ACQ_INHERITANCE, calendar_day)
	# Domain itself: lifecycle back to active; clear liege_domain_id so it's no
	# longer a vassal-domain (direct rule).
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET liege_domain_id = NULL, updated_at = datetime('now') WHERE id = ?",
		[domain_id])
	CampaignRepository.update_domain_succession_state(
		domain_id,
		LifecycleHandler.STATE_ACTIVE,
		0,
		"",
		"",
		calendar_day)


static func _empty_resolution() -> Dictionary:
	return {
		"resolved": false,
		"new_owner_id": "",
		"heir_kind": "",
		"reverted_to_overlord": false,
		"abandoned": false,
	}
