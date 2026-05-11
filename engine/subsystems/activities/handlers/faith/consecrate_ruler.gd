class_name ConsecrateRulerHandler
extends RefCounted

## consecrate_ruler handler (Phase 10A.2 — Faith block).
##
## Restricted major activity (yearly cooldown). Per ax_campaign_play.xml
## §consecrate_ruler L441-458:
##   - May not be performed more than once per year
##     (restricted_period_rounds = 3,144,960).
##   - Requires divine spellcaster level 9+ who is the spiritual advisor of
##     a domain ruler.
##   - Procedure:
##     1. Expend DP equal to the ruler's monthly domain revenue.
##     2. Make a magic research throw.
##     3. On success: for the next 12 game months, ruler gets +1 base morale,
##        +1 vassal loyalty rolls, and best-of-two vagary rolls.
##     4. On unmodified 1: ruler suffers -1 base morale, -1 vassal loyalty,
##        worst-of-two vagary rolls. (RAW also notes "exceptionally impious"
##        rulers awry on 1-3 at Judge's discretion; v1 sticks with strict 1.)
##
## State.params_json shape:
##   {
##     "ruler_character_id": <String>  # defaults to launcher's character_id
##   }
##
## v1 supports self-consecration (a divine-caster L9+ ruler consecrates
## themselves) AND advisor consecration (a divine-caster L9+ henchman
## consecrates their patron PC who rules a domain). Spiritual-advisor
## relationship modeling defers to "any character whose advisor field points
## to the launcher" — v1 simplification: if `ruler_character_id` is set and
## differs from launcher, treat the launcher as that ruler's advisor.


const BUFF_DURATION_MONTHS := 12


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var caster_character_id: String = String(state.get("character_id", ""))
	if caster_character_id.is_empty():
		return {"summary": "consecrate_ruler: no caster character_id"}

	var caster := _get_character_full(caster_character_id)
	if caster.is_empty():
		return {"summary": "consecrate_ruler: caster not found"}
	if int(caster.get("level", 0)) < 9:
		return {"summary": "consecrate_ruler failed: caster must be level 9+"}

	var params := _parse_params(state)
	var ruler_character_id: String = String(params.get("ruler_character_id", caster_character_id))
	var domain_id: String = _resolve_domain_for_ruler(ruler_character_id)
	if domain_id.is_empty():
		return {"summary": "consecrate_ruler failed: target character does not rule a domain"}
	var domain := _get_domain(domain_id)
	var monthly_revenue: int = int(domain.get("revenue_gp", 0))
	if monthly_revenue <= 0:
		return {"summary": "consecrate_ruler failed: domain has zero monthly revenue (cannot compute DP cost)"}

	# Step 1: expend DP equal to ruler's monthly revenue.
	if not CampaignRepository.spend_divine_power(caster_character_id, monthly_revenue):
		return {"summary": "consecrate_ruler failed: insufficient divine power (needed %d)" % monthly_revenue}
	var new_dp_balance: int = CampaignRepository.get_divine_power_gp(caster_character_id)
	EventBus.divine_power_changed.emit(caster_character_id, new_dp_balance, -monthly_revenue)

	# Step 2: magic research throw (WIS-modified for divine activity).
	var caster_level: int = int(caster.get("level", 9))
	var wis_mod: int = MagicResearchThrowUtil.wis_mod_for_character(caster)
	var throw_result: Dictionary = MagicResearchThrowUtil.make_throw(
		caster_level, wis_mod, 0, "consecrate_ruler_throw")

	# Steps 3 / 4: enqueue 12-month buff (success) or 12-month curse (natural 1).
	var success: bool = bool(throw_result.get("success", false))
	var natural_one: bool = bool(throw_result.get("natural_one", false))
	var now := _calendar_day()
	var expires_at: int = now + BUFF_DURATION_MONTHS * Timekeeping.DAYS_PER_MONTH
	var payload: Dictionary = {}

	if success:
		payload = {
			"base_morale_bonus":   1,
			"vassal_loyalty_bonus": 1,
			"vagary_roll_pick":   "best_of_two",
		}
	elif natural_one:
		payload = {
			"base_morale_bonus":   -1,
			"vassal_loyalty_bonus": -1,
			"vagary_roll_pick":   "worst_of_two",
		}
	# Ordinary failure (not natural 1): no buff or curse; DP still consumed.

	if not payload.is_empty():
		CampaignRepository.create_pending_divine_effect({
			"domain_id": domain_id,
			"character_id": caster_character_id,
			"effect_kind": "consecrate_ruler_buff",
			"effect_payload_json": JSON.stringify(payload),
			"issued_calendar_day": now,
			"applies_at_calendar_day": now,    # active immediately
			"expires_at_calendar_day": expires_at,
			"status": "applied",  # continuous-active effect; not pending-to-fire
		})

	EventBus.consecrate_ruler_resolved.emit(domain_id, ruler_character_id, success, expires_at)

	var summary := "Consecrate Ruler: rolled %d + %d = %d vs %d → %s · -%d DP" % [
		int(throw_result.get("raw_roll", 0)),
		int(throw_result.get("ability_modifier", 0)),
		int(throw_result.get("modified_total", 0)),
		int(throw_result.get("target", 0)),
		"success (12-month buff)" if success else (
			"awry on natural 1 (12-month curse)" if natural_one else "failure (no effect)"
		),
		monthly_revenue,
	]
	return {
		"summary": summary,
		"presentation": {
			"type": "toast",
			"text": "Ruler consecrated" if success else (
				"Consecration went awry" if natural_one else "Consecration failed"
			),
		},
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


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
