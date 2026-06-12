class_name SiegeInterventionHandler
extends RefCounted

## Player intervention into ongoing simplified sieges per
## rules/daw_sieges.xml §off_camera_and_intervention_guidance L838-844:
##
##   "If PCs intervene during an ongoing simplified siege, calculate current
##   wall condition and supplies by elapsed time. When the listed duration has
##   fully elapsed, the stronghold has 0 shp. When half the listed duration
##   has elapsed, the stronghold has 50% of its shp remaining. Apply the same
##   proportional logic for other elapsed fractions."
##
## On escalation, the simplified-conclusion event MUST be cancelled (mode flip
## responsibility), then daily/weekly tick events are scheduled for the full
## resolver to consume from this point forward.
##
## Public API:
##   reconstruct_state_at_intervention(siege_id, current_calendar_day) -> Dictionary
##   escalate_to_full(siege_id, current_calendar_day, scheduler) -> bool
##   should_escalate_on_pc_arrival(siege_id, arriving_character_id) -> bool


## Compute the proportional state at intervention. Does NOT mutate the siege row.
## Returns:
##   {
##     elapsed_days: int,
##     total_days: int,
##     fraction_remaining: float,
##     reconstructed_shp: int,
##     reconstructed_breach_count: int,
##     reconstructed_supplies_cp: int,
##   }
static func reconstruct_state_at_intervention(siege_id: String, current_calendar_day: int) -> Dictionary:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {}
	var started: int = int(siege.get("started_calendar_day", 0))
	var total: int = int(siege.get("simplified_total_days", 0))
	var starting_shp: int = int(siege.get("starting_shp", 0))
	var unit_capacity: int = int(siege.get("unit_capacity", 0))
	var elapsed: int = maxi(0, current_calendar_day - started)
	var fraction_remaining: float = 1.0
	if total > 0:
		fraction_remaining = clampf(1.0 - float(elapsed) / float(total), 0.0, 1.0)
	# Reconstruct shp proportionally (banker's rounded to keep tests deterministic).
	var reconstructed_shp: int = XPAwardCalculator.bankers_round(float(starting_shp) * fraction_remaining)
	# Breach count from damage_dealt = starting_shp - reconstructed_shp.
	var reconstructed_damage: int = maxi(0, starting_shp - reconstructed_shp)
	var reconstructed_breaches: int = UnitCapacityCalculator.breach_count_from_damage(reconstructed_damage)
	# Supplies: same proportional logic. The default stored supplies for the
	# stronghold's unit_capacity acts as the "starting" pool; PC-intervention
	# proportional logic applies the same fraction.
	var default_supplies: int = SiegeSupplyTracker.compute_default_stored_supplies_cp(unit_capacity)
	var reconstructed_supplies: int = XPAwardCalculator.bankers_round(float(default_supplies) * fraction_remaining)
	return {
		"elapsed_days": elapsed,
		"total_days": total,
		"fraction_remaining": fraction_remaining,
		"reconstructed_shp": reconstructed_shp,
		"reconstructed_breach_count": reconstructed_breaches,
		"reconstructed_supplies_cp": reconstructed_supplies,
		"reconstructed_damage_dealt": reconstructed_damage,
	}


## Escalate a simplified siege to full DaW rules.
##
## Steps:
##   1. Read the simplified siege.
##   2. Reconstruct current state (shp, supplies, breaches).
##   3. Update the siege row: resolution_mode='full', current_phase='reduction',
##      current_shp/breach_count/stored_supplies_cp set from reconstruction.
##   4. Cancel the simplified single-event (siege_simplified_concluded).
##   5. Schedule siege_daily_tick + siege_weekly_tick events.
##   6. Emit EventBus.siege_escalated.
##
## scheduler: an EventScheduler instance. If null, no events are cancelled or
## scheduled (test mode).
static func escalate_to_full(siege_id: String, current_calendar_day: int, scheduler = null) -> bool:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		push_error("SiegeInterventionHandler.escalate_to_full: siege not found: %s" % siege_id)
		return false
	if String(siege.get("resolution_mode", "")) != "simplified":
		# Already full, no-op.
		return true
	if String(siege.get("current_phase", "")) == "concluded":
		# Already over.
		return false
	var state: Dictionary = reconstruct_state_at_intervention(siege_id, current_calendar_day)
	if state.is_empty():
		return false
	# Update the siege row.
	var ok: bool = SiegeRepository.update(siege_id, {
		"resolution_mode": "full",
		"current_phase": "reduction",
		"current_shp": int(state.get("reconstructed_shp", 0)),
		"breach_count": int(state.get("reconstructed_breach_count", 0)),
		"damage_dealt_total": int(state.get("reconstructed_damage_dealt", 0)),
		"stored_supplies_cp": int(state.get("reconstructed_supplies_cp", 0)),
	})
	if not ok:
		return false
	# Cancel any pending simplified-conclusion events for this siege.
	if scheduler != null:
		scheduler.cancel_all_for_owner(siege_id, "siege_simplified_concluded")
		# Schedule full-mode ticks from tomorrow (fire_time is ROUNDS — the
		# day-serial arithmetic converts via calendar_day_to_rounds).
		scheduler.schedule_at(
			Timekeeping.calendar_day_to_rounds(current_calendar_day + 1),
			"siege_daily_tick",
			siege_id,
			{"siege_id": siege_id},
			ScheduledEvent.PRIORITY_CONSEQUENCE
		)
		scheduler.schedule_at(
			Timekeeping.calendar_day_to_rounds(current_calendar_day + 7),
			"siege_weekly_tick",
			siege_id,
			{"siege_id": siege_id},
			ScheduledEvent.PRIORITY_CONSEQUENCE
		)
	# Append a ledger row for visibility.
	SiegeRepository.append_action(
		siege_id, current_calendar_day, "besieger", "blockade_completed",
		{},
		{"escalation": true, "from_mode": "simplified", "to_mode": "full",
		 "reconstructed_state": state}
	)
	if EventBus.has_signal("siege_escalated"):
		EventBus.emit_signal("siege_escalated", siege_id, "full")
	return true


## Should the siege escalate to full on a given character's arrival in the
## hex of the besieged stronghold? True if:
##   - siege is currently 'simplified'
##   - arriving character is a PC, a PC's henchman, or a PC's named NPC vassal
static func should_escalate_on_pc_arrival(siege_id: String, arriving_character_id: String) -> bool:
	if siege_id.is_empty() or arriving_character_id.is_empty():
		return false
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return false
	if String(siege.get("resolution_mode", "")) != "simplified":
		return false
	if String(siege.get("current_phase", "")) == "concluded":
		return false
	# Walk the character's player-relationship.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_type FROM characters WHERE id = ?", [arriving_character_id]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var ctype: String = String(CampaignRepository.db.query_result[0].get("character_type", ""))
	if ctype == "pc":
		return true
	if ctype == "henchman":
		# Henchman of a PC counts.
		if not CampaignRepository.db.query_with_bindings("""
			SELECT 1 FROM henchman_relationships hr
			JOIN characters c ON c.id = hr.lord_character_id
			WHERE hr.henchman_character_id = ? AND c.character_type = 'pc'
			LIMIT 1
		""", [arriving_character_id]):
			return false
		return not CampaignRepository.db.query_result.is_empty()
	# NPC vassal of a PC ruler — check vassal_assignments.
	if ctype == "npc":
		if not CampaignRepository.db.query_with_bindings("""
			SELECT 1 FROM vassal_assignments va
			JOIN characters c ON c.id = va.liege_character_id
			WHERE va.vassal_character_id = ? AND va.status = 'active'
			      AND c.character_type = 'pc'
			LIMIT 1
		""", [arriving_character_id]):
			return false
		return not CampaignRepository.db.query_result.is_empty()
	return false


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
