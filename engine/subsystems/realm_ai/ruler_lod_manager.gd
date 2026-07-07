class_name RulerLodManager
extends RefCounted

## Regional-LOD activation for NPC rulers — gdd-ruler-ai.md §8.1/§8.2.
##
## ACTIVE SET = NPC rulers that are BOTH:
##   (a) already materialized to persistence_tier == 'full' — the hard
##       materialization-safety gate: the window/buffer NEVER promotes a
##       'named'/abstract ruler (§8.1); the existing promote-on-visit path
##       owns tier promotion, and a full ruler auto-qualifies once in band;
##   (b) ruler of a personal domain located ON the campaign's 6-mile play map
##       (hex_maps scale 'regional_6mi'). Per §8.1 the regional map IS the
##       play window, and the rolling frontier grows the map itself — so
##       "window + 10-hex buffer" reduces to map membership today: located
##       domains only exist on the region map, and abstract (NULL-location)
##       domains are Backdrop by definition. The buffer becomes a real ring
##       check only if located-off-window domains ever exist (documented for
##       that future).
##   plus (c) any extra ruler ids the caller supplies (rulers party to a
##       player-relevant conflict, §8.1 — the conflict hook lands with the
##       army-warfare wiring).
##
## FIXTURE FALLBACK (PROJECT CALL): a campaign with NO regional_6mi map
## (hand-authored fixtures like Avalon predate materialization) keeps the
## Phase-2 provisional behavior — every full-tier NPC ruler is active — so
## fixture campaigns don't silently lose their planners.
##
## sync() diffs against a per-campaign cache and emits
## ruler_activated_for_lod / ruler_deactivated_for_lod on transitions;
## promotion lazily ensures the disposition (§8.2) and demotion cancels the
## ruler's scheduled ruler_strategic_turn events (defensive — v1 never seeds
## them, §3.4). Tiers persist to ruler_ai_state (§10): a cold in-memory cache
## hydrates from the persisted 'active' tiers so a loaded session resumes
## quietly instead of re-firing promotion signals (save/load reconciliation,
## §8.2), and a ruler that leaves the WINDOW GEOMETRY gets the §8.2 demotion
## grace — it keeps planning for DEMOTION_GRACE_DAYS (stamped in
## demotion_pending_day) before actually demoting, and re-entry during grace
## clears the stamp with no signals. Grace requires a calendar_day and applies
## only to still-ELIGIBLE rulers: eligibility loss (death, tier loss, terminal
## domain) demotes immediately — grace never keeps a dead or de-tiered ruler
## planning.

const STRATEGIC_TURN_EVENT := "ruler_strategic_turn"

## §8.2 "after a grace window (e.g., 1 month)" — PROJECT CALL: 30 days.
const DEMOTION_GRACE_DAYS := 30

## {campaign_id: {ruler_id: true}} — last synced active set (session-local).
static var _last_active: Dictionary = {}


## Compute the current active set (no signals, no cache mutation).
static func active_set(campaign_id: String, extra_ruler_ids: Array = []) -> Array:
	if campaign_id.is_empty():
		return []
	var region_map_id: String = _region_map_id(campaign_id)
	var rows: Array = []
	if region_map_id.is_empty():
		# Fixture fallback: no play window exists — every full-tier NPC ruler
		# plans (the Phase-2 provisional behavior).
		rows = _query_full_tier_rulers(campaign_id, "")
	else:
		rows = _query_full_tier_rulers(campaign_id, region_map_id)
	var out: Array = []
	var seen: Dictionary = {}
	for row in rows:
		var rid: String = String((row as Dictionary).get("id", ""))
		if not rid.is_empty() and not seen.has(rid):
			seen[rid] = true
			out.append(rid)
	for extra_v in extra_ruler_ids:
		var extra: String = String(extra_v)
		# The conflict hook widens the set but NEVER bypasses the tier gate
		# (nor the campaign boundary).
		if not extra.is_empty() and not seen.has(extra) \
				and _is_full_tier_npc(extra, campaign_id):
			seen[extra] = true
			out.append(extra)
	return out


## Recompute the active set, emit promotion/demotion signals for transitions
## since the last sync, lazily ensure dispositions for promoted rulers, and
## cancel any per-ruler strategic-turn events for demoted ones. Tiers persist
## to ruler_ai_state; with a real [param calendar_day] (>= 0), a geometry exit
## by a still-eligible ruler starts the §8.2 grace window instead of demoting
## (the returned "active" then includes grace holdovers, who keep planning).
## calendar_day = -1 keeps the immediate-demotion behavior (fixture callers).
## Returns {active: Array, promoted: Array, demoted: Array}.
static func sync(campaign_id: String, scheduler = null,
		extra_ruler_ids: Array = [], calendar_day: int = -1) -> Dictionary:
	var geometric: Array = active_set(campaign_id, extra_ruler_ids)
	var in_geometry: Dictionary = {}
	for rid_v in geometric:
		in_geometry[String(rid_v)] = true
	# Save/load reconciliation (§8.2): a cold cache hydrates from the
	# persisted tiers so a loaded session resumes quietly.
	var prior: Dictionary
	if _last_active.has(campaign_id):
		prior = _last_active[campaign_id]
	else:
		prior = {}
		for rid_v in RulerAiStateRepository.active_ruler_ids(campaign_id):
			prior[String(rid_v)] = true
	var now: Dictionary = {}
	var promoted: Array = []
	var demoted: Array = []

	for rid_v in geometric:
		var rid: String = String(rid_v)
		now[rid] = true
		if not prior.has(rid):
			promoted.append(rid)
			# §8.2: build the disposition on promotion if not cached.
			if not RulerDispositionRepository.has_disposition(rid):
				StrategicDispositionBuilder.build_and_persist_for_character(rid)
			RulerAiStateRepository.upsert(campaign_id, rid,
				{"lod_tier": "active", "demotion_pending_day": null})
			EventBus.ruler_activated_for_lod.emit(rid)
		else:
			# Re-entered (or never left) the window: clear any grace stamp
			# quietly — the ruler never actually demoted.
			var state: Dictionary = RulerAiStateRepository.get_state(rid)
			if state.get("demotion_pending_day", null) != null:
				RulerAiStateRepository.upsert(campaign_id, rid,
					{"demotion_pending_day": null})
	for rid_v in prior:
		var rid: String = String(rid_v)
		if in_geometry.has(rid):
			continue
		# Left the §8.1 band. Grace applies only to GEOMETRY exits by a
		# still-eligible ruler (the player moved away); eligibility loss —
		# death, tier loss, OR a terminal domain lifecycle — demotes
		# immediately.
		if calendar_day >= 0 and _is_full_tier_npc(rid, campaign_id) \
				and _has_plannable_domain(rid, campaign_id):
			var state: Dictionary = RulerAiStateRepository.get_state(rid)
			var pending_day: Variant = state.get("demotion_pending_day", null)
			if pending_day == null:
				RulerAiStateRepository.upsert(campaign_id, rid,
					{"demotion_pending_day": calendar_day})
				now[rid] = true
				continue
			if calendar_day - int(pending_day) < DEMOTION_GRACE_DAYS:
				now[rid] = true
				continue
		demoted.append(rid)
		RulerAiStateRepository.upsert(campaign_id, rid,
			{"lod_tier": "backdrop", "demotion_pending_day": null})
		if scheduler != null and scheduler.has_method("cancel_all_for_owner"):
			scheduler.cancel_all_for_owner(rid, STRATEGIC_TURN_EVENT)
		EventBus.ruler_deactivated_for_lod.emit(rid)

	_last_active[campaign_id] = now
	var active: Array = []
	for rid_v in geometric:
		active.append(String(rid_v))
	for rid_v in now:
		var rid: String = String(rid_v)
		if not in_geometry.has(rid):
			active.append(rid)  # §8.2 grace holdovers keep planning
	return {"active": active, "promoted": promoted, "demoted": demoted}


## Drop the session-local sync cache (tests / session teardown).
static func clear_cache() -> void:
	_last_active.clear()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _region_map_id(campaign_id: String) -> String:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM hex_maps WHERE campaign_id = ? AND scale = 'regional_6mi' LIMIT 1",
		[campaign_id]
	) or CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


## Full-tier, living, non-pc/non-henchman rulers owning a non-terminal
## domain; when [param region_map_id] is non-empty, the domain must be
## LOCATED on that map (the §8.1 window).
static func _query_full_tier_rulers(campaign_id: String, region_map_id: String) -> Array:
	var location_clause: String = ""
	var binds: Array = [campaign_id, campaign_id]
	if not region_map_id.is_empty():
		location_clause = " AND d.location_map_id = ?"
		binds.append(region_map_id)
	if not CampaignRepository.db.query_with_bindings("""
		SELECT DISTINCT c.id, c.created_at FROM characters c
		JOIN domains d ON d.owner_character_id = c.id AND d.campaign_id = ?
		WHERE c.campaign_id = ?
		  AND c.character_type NOT IN ('pc', 'henchman')
		  AND c.persistence_tier = 'full'
		  AND c.is_dead = 0
		  AND d.lifecycle_state NOT IN ('abandoned', 'salted_to_ruin', 'succession_pending')
	""" + location_clause + """
		ORDER BY c.created_at, c.id
	""", binds):
		return []
	return CampaignRepository.db.query_result.duplicate()


## The domain half of grace eligibility: the ruler still owns a domain in a
## plannable lifecycle (the same filter _query_full_tier_rulers applies, minus
## the location clause — location is exactly what the grace window forgives).
static func _has_plannable_domain(character_id: String, campaign_id: String) -> bool:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM domains
		WHERE owner_character_id = ? AND campaign_id = ?
		  AND lifecycle_state NOT IN ('abandoned', 'salted_to_ruin', 'succession_pending')
		LIMIT 1
	""", [character_id, campaign_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


static func _is_full_tier_npc(character_id: String, campaign_id: String) -> bool:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM characters
		WHERE id = ? AND campaign_id = ?
		  AND character_type NOT IN ('pc', 'henchman')
		  AND persistence_tier = 'full' AND is_dead = 0
	""", [character_id, campaign_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()
