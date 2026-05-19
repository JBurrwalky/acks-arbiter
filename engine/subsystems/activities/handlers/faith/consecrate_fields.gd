class_name ConsecrateFieldsHandler
extends RefCounted

## consecrate_fields handler (Phase 10A.2 — Faith block).
##
## Ongoing major activity. Per ax_campaign_play.xml §consecrate_fields L423-439:
##   - Duration: 1 day per 780 peasants (rounded up) — handled by the executor
##     via ticks_required = ceil(peasant_families / 780).
##   - Requires divine spellcaster level 5+.
##   - Procedure:
##     1. Complete the activity time (executor).
##     2. Expend 2 gp DP per family. (Handler: spend_divine_power)
##     3. Make a magic research throw. (Handler: MagicResearchThrowUtil)
##     4. On success → Land Value increases by 1 gp/family next month.
##     5. On unmodified 1 → Land Value decreases by 1 gp/family next month.
##   - Fields may be consecrated repeatedly if DP is available.
##
## Project decision: divine consecration uses WIS-modified magic research throw
## (per the Q13-pattern: divine throws use WIS; arcane throws use INT). RAW
## §general_magic_research_throw L56 says "Intelligence bonus" without
## distinguishing — but divine casters' prime requisite is WIS, so a literal
## INT reading would punish them. Project interpretation: ability_modifier =
## WIS for divine activities, INT for arcane.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "consecrate_fields: no character_id"}

	var character := _get_character_full(character_id)
	if character.is_empty():
		return {"summary": "consecrate_fields: character not found"}

	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		# Per RAW, consecrate_fields is performed in a domain. If the caster
		# isn't a ruler, they could in principle do it for someone else's
		# fields — but v1 requires the caster to be the ruler. Future:
		# accept a target_domain_id param.
		return {"summary": "consecrate_fields: no domain owned by caster"}
	var domain := _get_domain(domain_id)
	var peasant_families: int = int(domain.get("peasant_families", 0))
	if peasant_families <= 0:
		return {"summary": "consecrate_fields: no peasant families to consecrate"}

	# Step 2: Expend 2 gp DP per family (= 200 cp/family under the unified cp standard).
	var dp_cost_cp: int = 200 * peasant_families
	if not CampaignRepository.spend_divine_power_cp(character_id, dp_cost_cp):
		return {"summary": "consecrate_fields failed: insufficient divine power (needed %s)" % Currency.format_cost(dp_cost_cp)}
	var new_dp_balance: int = CampaignRepository.get_divine_power_cp(character_id)
	EventBus.divine_power_changed.emit(character_id, new_dp_balance, -dp_cost_cp)

	# Step 3: magic research throw (WIS-modified).
	var level: int = int(character.get("level", 1))
	var wis_mod: int = MagicResearchThrowUtil.wis_mod_for_character(character)
	var throw_result: Dictionary = MagicResearchThrowUtil.make_throw(
		level, wis_mod, 0, "consecrate_fields_throw")

	# Step 4 / 5: enqueue pending_divine_effect for next monthly tick.
	var delta_per_family: int = 0
	var success: bool = bool(throw_result.get("success", false))
	if success:
		delta_per_family = 1
	elif bool(throw_result.get("natural_one", false)):
		delta_per_family = -1
	# Ordinary failure (not natural 1): no land value change; DP still consumed.

	if delta_per_family != 0:
		var now := _calendar_day()
		var next_monthly_tick: int = _next_monthly_tick_day(now)
		CampaignRepository.create_pending_divine_effect({
			"domain_id": domain_id,
			"character_id": character_id,
			"effect_kind": "consecrate_fields_land_value",
			"effect_payload_json": JSON.stringify({
				"delta_gp_per_family": delta_per_family,
				"peasant_families": peasant_families,
			}),
			"issued_calendar_day": now,
			"applies_at_calendar_day": next_monthly_tick,
			"expires_at_calendar_day": next_monthly_tick + 1,  # one-shot; expires after next tick
			"status": "pending",
		})

	EventBus.consecrate_fields_resolved.emit(domain_id, success, delta_per_family)

	var summary := "Consecrate Fields: rolled %d + %d = %d vs %d → %s" % [
		int(throw_result.get("raw_roll", 0)),
		int(throw_result.get("ability_modifier", 0)),
		int(throw_result.get("modified_total", 0)),
		int(throw_result.get("target", 0)),
		"success" if success else "failure",
	]
	if delta_per_family != 0:
		summary += " (+%d gp/family land value next month)" % delta_per_family if delta_per_family > 0 \
			else " (-1 gp/family land value next month — natural 1!)"
	summary += " · -%s DP" % Currency.format_cost(dp_cost_cp)
	return {
		"summary": summary,
		"presentation": {"type": "toast", "text": "Fields consecrated" if success else "Consecration failed"},
	}


static func _get_character_full(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day


## Returns the calendar_day on which the next monthly tick will fire. Monthly
## tick fires at the start of each game-month (day 1 of next month). This
## implementation computes "first day of month following `from_day`."
static func _next_monthly_tick_day(from_day: int) -> int:
	var days_per_month: int = Timekeeping.DAYS_PER_MONTH
	# Find which month from_day is in (1-indexed), then the next month's day-1.
	var months_elapsed: int = int(from_day / days_per_month)
	# from_day is 1-indexed; convert to 0-indexed for math.
	# from_day=1..28 → months_elapsed=0; from_day=29..56 → months_elapsed=1; etc.
	# Actually use floor((from_day - 1) / days_per_month) for cleaner math:
	var zero_indexed_day: int = max(0, from_day - 1)
	var current_month_index: int = int(zero_indexed_day / days_per_month)
	var next_month_first_day: int = (current_month_index + 1) * days_per_month + 1
	return next_month_first_day
