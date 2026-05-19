class_name SolicitMerchantsHandler
extends RefCounted

## solicit_merchants handler — Phase 10B.2 Wave 3 (Trade block).
##
## Ongoing 21-day minor activity. Per gdd-phase-10b-2-trade-block.md §5 +
## substrate gdd-settlement-economy.md §7.5.1.
##
## The ActivityHandlerRegistry only exposes on_complete + on_tick hooks (no
## on_started or on_forfeited). To bridge §5's design intent into the existing
## executor:
##
##   * prepare_launch() — called by the UI ROUTER before executor.launch.
##     Runs MerchantPoolRepository.process_solicitation (sets per-merchant
##     becomes_visible_calendar_day) and records started_at_calendar_day in
##     the launch params. Returns {success, params, merchants_revealed, error}.
##     The router only invokes executor.launch on success.
##
##   * on_tick — per-day no-op. The executor's per-day prerequisite check
##     handles forfeiture-on-departure; reveals fire time-driven via the
##     substrate's `becomes_visible_calendar_day <= current_day` query.
##
##   * on_complete — fires after 21 ticks (3 weeks of presence). Emits
##     solicit_merchants_completed. No state cleanup needed — fired reveals
##     are permanent.
##
##   * handle_forfeit() — STATIC method invoked by MercantileForfeitRouter
##     when EventBus.activity_forfeited fires with the activity_state row
##     resolving to a solicit_merchants instance whose status flipped to
##     'forfeited' or 'abandoned'. Rolls back any unfired reveals
##     (becomes_visible_calendar_day > current_day) belonging to THIS solicit
##     instance (attribution via started_at_calendar_day + {7, 14, 21}).
##     Promoted-NPC merchants are skipped per §0.1.1.


# ---------------------------------------------------------------------------
# Launch-side helper (called by UI router BEFORE executor.launch)
# ---------------------------------------------------------------------------

## Prepares the solicit launch. Runs process_solicitation immediately (which
## assigns becomes_visible_calendar_day per substrate §7.5.1's thirds formula)
## and returns the params dict the caller should pass to executor.launch.
##
## Per gdd-phase-10b-2-trade-block.md §5.3. The router pattern compensates
## for the executor lacking an on_started hook.
##
## Returns: { success, params, merchants_revealed, error }
##   * success=false + error="already_revealed" if the invisible pool is empty
##     (PC-owned domain or pre-revealed via locate / a prior solicit).
##   * success=false + error="empty_settlement_id" if settlement_id is empty.
static func prepare_launch(party_id: String, settlement_id: String, character_id: String) -> Dictionary:
	if settlement_id.is_empty():
		return {"success": false, "params": {}, "merchants_revealed": 0,
				"error": "empty_settlement_id"}
	var current_day: int = Timekeeping.get_total_days()
	var sub_result: Dictionary = MerchantPoolRepository.process_solicitation(
		settlement_id, character_id, current_day)
	if not bool(sub_result.get("success", false)):
		return {"success": false, "params": {}, "merchants_revealed": 0,
				"error": String(sub_result.get("error", "unknown"))}
	# Ensure visit row exists for toll first-fire consistency (defensive).
	if not VisitStateManager.has_active_visit(party_id, settlement_id):
		VisitStateManager.on_party_entered_settlement(
			party_id, settlement_id, character_id, current_day)
	return {
		"success": true,
		"params": {
			"started_at_calendar_day": current_day,
			"merchants_revealed": int(sub_result.get("merchants_revealed", 0)),
		},
		"merchants_revealed": int(sub_result.get("merchants_revealed", 0)),
		"error": "",
	}


# ---------------------------------------------------------------------------
# Per-day tick — no-op
# ---------------------------------------------------------------------------

## Per-day fire. The executor's prerequisite check enforces presence; the
## substrate's visibility query handles reveal-firing. The handler has nothing
## to do mid-activity.
static func on_tick(_state: Dictionary, _runner) -> Dictionary:
	return {}


# ---------------------------------------------------------------------------
# Completion — fires after the full 21-day commitment
# ---------------------------------------------------------------------------

static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var settlement_id: String = String(state.get("location_ref", ""))
	var character_id: String = String(state.get("character_id", ""))
	EventBus.solicit_merchants_completed.emit(settlement_id, character_id)
	return {
		"summary": "Solicit completed — full 3-week pool reveal done.",
		"success": true,
	}


# ---------------------------------------------------------------------------
# Forfeit rollback — invoked by MercantileForfeitRouter
# ---------------------------------------------------------------------------

## Rolls back any of THIS solicit instance's unfired reveals (scheduled days
## strictly greater than current_day) to INVISIBLE_SENTINEL. Filters by:
##   * source_kind = 'monthly_refresh' (don't touch manual rows)
##   * promoted_npc_id IS NULL (don't disturb promoted NPCs per §0.1.1)
##   * becomes_visible_calendar_day IN (start_day+7, start_day+14, start_day+21)
##     intersected with reveal days > current_day
##
## Emits solicit_merchants_forfeited(settlement_id, character_id, rolled_back).
##
## [param state] is the activity_state row fetched by the router after the
## forfeit signal fires; status will be 'forfeited' or 'abandoned'. params_json
## carries started_at_calendar_day from prepare_launch.
static func handle_forfeit(state: Dictionary) -> void:
	var settlement_id: String = String(state.get("location_ref", ""))
	var character_id: String = String(state.get("character_id", ""))
	if settlement_id.is_empty():
		return

	var params: Dictionary = _parse_params(state)
	var start_day: int = int(params.get("started_at_calendar_day", 0))
	var current_day: int = Timekeeping.get_total_days()

	# Compile this solicit's unfired reveal days.
	var unfired_reveal_days: Array = []
	for offset in [7, 14, 21]:
		var reveal_day: int = start_day + offset
		if reveal_day > current_day:
			unfired_reveal_days.append(reveal_day)

	var rolled_back: int = 0
	if not unfired_reveal_days.is_empty():
		# Count rows about to be rolled back so the signal payload is accurate.
		var placeholder_list: String = ""
		var ph_parts: PackedStringArray = []
		for _d in unfired_reveal_days:
			ph_parts.append("?")
		placeholder_list = ", ".join(ph_parts)
		var count_sql: String = """
			SELECT COUNT(*) AS n FROM merchant_pool
			WHERE settlement_entrance_id = ?
				AND status = 'active'
				AND source_kind = 'monthly_refresh'
				AND promoted_npc_id IS NULL
				AND becomes_visible_calendar_day IN (%s)
		""" % placeholder_list
		var count_bindings: Array = [settlement_id] + unfired_reveal_days
		if CampaignRepository.db.query_with_bindings(count_sql, count_bindings):
			if not CampaignRepository.db.query_result.is_empty():
				rolled_back = int(CampaignRepository.db.query_result[0].get("n", 0))

		var update_sql: String = """
			UPDATE merchant_pool
			SET becomes_visible_calendar_day = ?
			WHERE settlement_entrance_id = ?
				AND status = 'active'
				AND source_kind = 'monthly_refresh'
				AND promoted_npc_id IS NULL
				AND becomes_visible_calendar_day IN (%s)
		""" % placeholder_list
		var update_bindings: Array = [MerchantPoolRepository.INVISIBLE_SENTINEL, settlement_id] \
			+ unfired_reveal_days
		CampaignRepository.db.query_with_bindings(update_sql, update_bindings)

	EventBus.solicit_merchants_forfeited.emit(settlement_id, character_id, rolled_back)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}
