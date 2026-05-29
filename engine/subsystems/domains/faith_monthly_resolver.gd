class_name FaithMonthlyResolver
extends RefCounted

## FaithMonthlyResolver (Phase 10A.2 — Faith block monthly integration).
##
## Static helpers called from `domain_handlers.gd` `_resolve_domain_month`
## once per monthly tick per domain. Handles:
##
##   1. Pre-resolve effects (applied BEFORE revenue/morale calculation):
##      * consecrate_fields_land_value: +1 / -1 gp/family land value this month
##        (per ax_campaign_play.xml §consecrate_fields L435-436)
##      * consecrate_ruler_buff:        +1 / -1 base morale + vassal loyalty
##                                       (per §consecrate_ruler L450-457)
##
##   2. Post-resolve effects (applied AFTER all other monthly events):
##      * congregant growth: 1d10 + Cha mod per 1,000 gp of pending_growth_gp
##        (per ax_campaign_play.xml §congregant_growth L20-22)
##      * congregant upkeep: 1 gp/congregant/month; unpaid → 1d10 depart per
##        1,000 gp unpaid (per §end_of_month L109-112)
##
##   3. State sweep: expire stale `pending_divine_effects` rows (status flips
##      from 'applied' → 'expired' when expires_at_calendar_day passes).
##
## Tested separately from the rest of the monthly tick via test_faith_*.gd.


# ---------------------------------------------------------------------------
# Pre-resolve: modifiers to be applied BEFORE revenue/morale calculation.
# Returned as a dict consumed by domain_handlers.gd.
# ---------------------------------------------------------------------------

## Returns a dict of faith-driven modifiers to apply during this monthly tick:
##   {
##     "consecrate_fields_bonus_per_family": int,  # +1 / -1 / 0
##     "consecrate_fields_fired_effect_ids": Array[String],  # rows to mark 'applied'
##     "consecrate_ruler_base_morale_bonus": int,  # +1 / -1 / 0 if active buff/curse
##     "consecrate_ruler_vassal_loyalty_bonus": int,
##     "consecrate_ruler_vagary_pick": String,     # "best_of_two" | "worst_of_two" | ""
##     "consecrate_ruler_active_effect_id": String,  # the active row id, if any
##   }
##
## After calling this and applying the bonuses, the caller MUST call
## `apply_pending_consecrate_fields(effect_ids)` to flip the fired rows to
## 'applied' status so they don't fire again next month.
static func compute_pre_resolve_modifiers(
	domain_id: String,
	calendar_day: int,
) -> Dictionary:
	var result: Dictionary = {
		"consecrate_fields_bonus_per_family": 0,
		"consecrate_fields_fired_effect_ids": [] as Array[String],
		"consecrate_ruler_base_morale_bonus": 0,
		"consecrate_ruler_vassal_loyalty_bonus": 0,
		"consecrate_ruler_vagary_pick": "",
		"consecrate_ruler_active_effect_id": "",
	}
	if domain_id.is_empty():
		return result

	# consecrate_fields: one-shot pending effects whose applies_at_calendar_day
	# has come due. Sum their per-family bonuses (multiple consecrations in a
	# month stack additively per RAW phrasing).
	var pending_fields: Array = CampaignRepository.list_pending_divine_effects_due(
		domain_id, calendar_day, "consecrate_fields_land_value")
	for row: Dictionary in pending_fields:
		var payload := _parse_payload(row)
		var delta: int = int(payload.get("delta_gp_per_family", 0))
		result["consecrate_fields_bonus_per_family"] = int(result["consecrate_fields_bonus_per_family"]) + delta
		(result["consecrate_fields_fired_effect_ids"] as Array).append(str(row.get("id", "")))

	# consecrate_ruler: continuous-active effect with an expiration window. v1
	# allows at most one active buff per domain at a time (per RAW yearly
	# cooldown on the activity). If multiple rows exist, use the most recent.
	var active_ruler: Array = CampaignRepository.list_active_divine_effects(
		domain_id, calendar_day, "consecrate_ruler_buff")
	if not active_ruler.is_empty():
		# Pick the most recently issued.
		var most_recent: Dictionary = active_ruler[0]
		for row: Dictionary in active_ruler:
			if int(row.get("issued_calendar_day", 0)) > int(most_recent.get("issued_calendar_day", 0)):
				most_recent = row
		var payload := _parse_payload(most_recent)
		result["consecrate_ruler_base_morale_bonus"] = int(payload.get("base_morale_bonus", 0))
		result["consecrate_ruler_vassal_loyalty_bonus"] = int(payload.get("vassal_loyalty_bonus", 0))
		result["consecrate_ruler_vagary_pick"] = String(payload.get("vagary_roll_pick", ""))
		result["consecrate_ruler_active_effect_id"] = String(most_recent.get("id", ""))

	return result


## Flips the listed pending_divine_effects rows from 'pending' → 'applied' to
## record that they fired this tick. Called AFTER the caller has incorporated
## the bonus into this month's revenue calculation.
static func apply_pending_consecrate_fields(effect_ids: Array) -> void:
	for raw_id in effect_ids:
		var id: String = String(raw_id)
		if id.is_empty():
			continue
		CampaignRepository.update_pending_divine_effect_status(id, "applied")


# ---------------------------------------------------------------------------
# Post-resolve: congregant growth + upkeep.
# ---------------------------------------------------------------------------

## Resolves congregant growth + upkeep for the ruler-character of this domain.
## Returns a dict with the resolution payload (for ledger writes + signal
## emission). Called AFTER revenue/morale/growth — the domain's own cp
## treasury is debited for upkeep if applicable.
##
## ruler_character_id: domains.owner_character_id for the active domain.
## ruler_cha_mod:      caster's Charisma modifier (used in the growth roll).
## domain_id:          owning domain (used for ledger entries).
##
## Returns:
##   {
##     "growth_rolled":  int,  # families added (positive)
##     "growth_dice":    Array,  # for the unified log
##     "upkeep_paid":    int,   # cp paid
##     "upkeep_unpaid":  int,   # cp owed but not paid
##     "attrition":      int,   # congregants lost from unpaid upkeep
##     "pending_cp_consumed":  int,
##     "pending_cp_remaining": int,
##     "new_count":      int,
##   }
##
## RAW (ax_campaign_play.xml §congregant_growth L20-22, §end_of_month L109-112):
##   * Growth roll: 1d10 + Cha mod per 1,000 gp of pending committed gp.
##   * Upkeep:      1 gp / congregant / month.
##   * Attrition:   1d10 congregants depart per 1,000 gp of unpaid upkeep.
## With the cp standard (1 gp = 100 cp): thresholds become 100,000 cp and
## upkeep is 100 cp/congregant.
const _GROWTH_TRIGGER_CP := 100_000    # RAW 1,000 gp per growth roll
const _ATTRITION_TRIGGER_CP := 100_000  # RAW 1,000 gp unpaid per attrition roll
const _UPKEEP_CP_PER_CONGREGANT := 100  # RAW 1 gp per congregant


static func resolve_congregants_monthly(
	ruler_character_id: String,
	ruler_cha_mod: int,
	domain_id: String,
	calendar_day: int,
) -> Dictionary:
	var result: Dictionary = {
		"growth_rolled":         0,
		"growth_dice":           [] as Array,
		"upkeep_paid":           0,
		"upkeep_unpaid":         0,
		"attrition":             0,
		"pending_cp_consumed":   0,
		"pending_cp_remaining":  0,
		"new_count":             0,
		"applies":               false,
	}
	if ruler_character_id.is_empty():
		return result

	var row := CampaignRepository.get_congregants(ruler_character_id)
	if row.is_empty():
		return result  # no congregation, nothing to resolve

	result["applies"] = true
	var count: int = int(row.get("count", 0))
	var pending_cp: int = int(row.get("monthly_growth_pending_cp", 0))

	# Step 1: Growth from pending cp. Roll 1d10 + cha_mod per 100,000 cp
	# (= 1,000 gp) per RAW §congregant_growth L20-22.
	if pending_cp >= _GROWTH_TRIGGER_CP:
		var rolls_count: int = int(pending_cp / _GROWTH_TRIGGER_CP)
		var growth_total: int = 0
		var dice_log: Array = []
		for i in range(rolls_count):
			var rr: RollResult = DiceSystem.roll_digital(
				10, 1, ruler_cha_mod, "congregant_growth")
			var amount: int = max(0, rr.modified_total)
			growth_total += amount
			dice_log.append(amount)
		count += growth_total
		var consumed: int = rolls_count * _GROWTH_TRIGGER_CP
		pending_cp -= consumed
		result["growth_rolled"] = growth_total
		result["growth_dice"] = dice_log
		result["pending_cp_consumed"] = consumed
	result["pending_cp_remaining"] = pending_cp

	# Step 2: Upkeep — 100 cp/congregant/month (RAW 1 gp/congregant per
	# §end_of_month L109-110). Debited from the ruler's divine_power first
	# (DP funds church operations per RAW), then from the domain treasury,
	# then unpaid.
	var upkeep_required: int = count * _UPKEEP_CP_PER_CONGREGANT
	var upkeep_paid: int = 0
	var dp_balance: int = CampaignRepository.get_divine_power_cp(ruler_character_id)
	if dp_balance > 0 and upkeep_required > 0:
		var from_dp: int = min(dp_balance, upkeep_required)
		CampaignRepository.spend_divine_power_cp(ruler_character_id, from_dp)
		upkeep_paid += from_dp
		upkeep_required -= from_dp

	# Domain treasury fallback (for ruler-with-domain only).
	if upkeep_required > 0 and not domain_id.is_empty():
		var domain := _get_domain(domain_id)
		var treasury: int = int(domain.get("treasury_cp", 0))
		var from_treasury: int = min(treasury, upkeep_required)
		if from_treasury > 0:
			CampaignRepository.update_domain_monthly_state(domain_id, {
				"treasury_cp": treasury - from_treasury,
			})
			CampaignRepository.add_ledger_entry({
				"domain_id": domain_id,
				"calendar_day": calendar_day,
				"category": "expense",
				"subcategory": "congregant_upkeep",
				"cp_amount": from_treasury,
				"description": "Congregant upkeep: %s (1 gp/congregant)" % Currency.format_cost(from_treasury),
			})
			upkeep_paid += from_treasury
			upkeep_required -= from_treasury

	result["upkeep_paid"] = upkeep_paid
	result["upkeep_unpaid"] = upkeep_required

	# Step 3: Attrition — 1d10 congregants depart per 100,000 cp (= 1,000 gp)
	# unpaid per RAW §end_of_month L110-112.
	if upkeep_required >= _ATTRITION_TRIGGER_CP:
		var attrition_rolls: int = int(upkeep_required / _ATTRITION_TRIGGER_CP)
		var attrition_total: int = 0
		for i in range(attrition_rolls):
			var rr: RollResult = DiceSystem.roll_digital(
				10, 1, 0, "congregant_attrition")
			attrition_total += max(0, rr.modified_total)
		count = max(0, count - attrition_total)
		result["attrition"] = attrition_total

	result["new_count"] = count

	# Persist the updated congregant row.
	CampaignRepository.upsert_congregants(ruler_character_id, {
		"count": count,
		"monthly_growth_pending_cp": pending_cp,
		"last_resolved_calendar_day": calendar_day,
	})

	# Compute the delta for the signal: from prior count.
	var prior_count: int = int(row.get("count", 0))
	var delta: int = count - prior_count
	if delta != 0:
		EventBus.congregants_changed.emit(ruler_character_id, count, delta)

	return result


# ---------------------------------------------------------------------------
# Sweep: expire stale 'applied' effects past their expiration.
# ---------------------------------------------------------------------------

## Called once per monthly tick. Flips any 'applied' rows whose
## expires_at_calendar_day has passed to 'expired'.
static func expire_stale_effects(domain_id: String, calendar_day: int) -> void:
	if domain_id.is_empty():
		return
	CampaignRepository.expire_stale_divine_effects(domain_id, calendar_day)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _parse_payload(row: Dictionary) -> Dictionary:
	var raw: String = str(row.get("effect_payload_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()
