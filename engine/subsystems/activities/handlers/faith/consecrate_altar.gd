class_name ConsecrateAltarHandler
extends RefCounted

## consecrate_altar handler (Phase 10A.2 — Faith block).
##
## Ongoing major activity. Per ax_campaign_play.xml §consecrate_altar L408-421:
##   - 1 day per 500 gp of altar (duration_formula handled by the executor via
##     ticks_required = ceil(gp_invested / 500); see activity_time_cost_executor).
##   - Aura size = 100 sq ft per 100 gp spent.
##   - Lawful → "pinnacle of good"; chaotic → "sinkhole of evil".
##   - Divine power may be spent in lieu of gp if a humbler-looking altar is
##     desired (per RAW L419) — the player can elect to substitute DP for gp
##     via the `dp_substituted_cp` param at launch. The aura still scales on
##     gp_invested + dp_substituted_cp (RAW treats them equivalently for aura).
##   - Aura persists until dispelled or the altar is physically broken and
##     blessed.
##
## State.params_json shape:
##   {
##     "gp_invested":       <int>    # gp spent on the altar (launcher gp input)
##     "dp_substituted_cp": <int>    # optional; DP substituted for gp (cp-native)
##     "alignment":         "lawful" | "neutral" | "chaotic"  # default: caster's alignment
##     "location_kind":     "stronghold" | "settlement_poi" | "wilderness_hex" | "dungeon_room"
##     "location_ref":      <String>  # id of the location
##   }
##
## At launch:
##   - The launching UI debits gp from the domain treasury OR character coin
##     and DP from character_divine_power.
##   - INSERTs a `consecrated_altars` row with status='in_progress',
##     completion_pct=0, aura_size_sq_ft=0.
##
## At completion (on_complete here):
##   - UPDATE the consecrated_altars row to status='completed',
##     completion_pct=100, aura_size_sq_ft = (cp_invested + dp_substituted_cp) ÷ 100.
##   - Emit altar_consecrated signal with cp_invested = total contribution in cp.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "consecrate_altar: no character_id"}

	var params := _parse_params(state)
	# Launcher captures gp; × 100 to cp at the boundary.
	var cp_invested: int = int(params.get("gp_invested", 0)) * 100
	var dp_substituted_cp: int = int(params.get("dp_substituted_cp", 0))
	if cp_invested + dp_substituted_cp <= 0:
		return {"summary": "consecrate_altar: no value invested"}

	# Look up the in-progress altar row created at launch. v1: the caller
	# stashed the altar id in params at launch. If absent, create the row now
	# (defensive fallback so the test path can exercise on_complete without
	# building the full launch flow).
	var altar_id: String = String(params.get("altar_id", ""))
	var alignment: String = String(params.get("alignment", "lawful"))
	var location_kind: String = String(params.get("location_kind", "stronghold"))
	var location_ref: String = String(params.get("location_ref", ""))

	var total_cp_value: int = cp_invested + dp_substituted_cp
	# Aura size: 100 sq ft per 100 gp per RAW L418 = 1 sq ft per gp = total_cp / 100.
	var aura_size: int = total_cp_value / 100

	if altar_id.is_empty():
		altar_id = CampaignRepository.create_consecrated_altar({
			"character_id": character_id,
			"location_kind": location_kind,
			"location_ref": location_ref,
			"cp_invested": cp_invested,
			"dp_substituted_cp": dp_substituted_cp,
			"alignment": alignment,
			"aura_size_sq_ft": aura_size,
			"completion_pct": 100,
			"status": "completed",
			"started_calendar_day": int(state.get("started_calendar_day", 0)),
			"completed_calendar_day": _calendar_day(),
		})
	else:
		CampaignRepository.update_consecrated_altar(altar_id, {
			"status": "completed",
			"completion_pct": 100,
			"aura_size_sq_ft": aura_size,
			"completed_calendar_day": _calendar_day(),
		})

	EventBus.altar_consecrated.emit(altar_id, character_id, total_cp_value)

	return {
		"summary": "Altar consecrated: %s value, %d sq ft aura (%s)" % [
			Currency.format_cost(total_cp_value), aura_size, alignment
		],
		"presentation": {
			"type": "toast",
			"text": "Altar consecrated (%s, %d sq ft aura)" % [alignment, aura_size],
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


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
