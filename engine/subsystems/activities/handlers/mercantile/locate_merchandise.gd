class_name LocateMerchandiseHandler
extends RefCounted

## locate_merchandise handler — Phase 10B.2 Wave 3 (Trade block).
##
## Singular minor activity, 1 hour of game time. Per
## gdd-phase-10b-2-trade-block.md §6 + substrate
## gdd-settlement-economy.md §7.5.2.
##
## Pipeline:
##   1. Validate merchandise_type param.
##   2. Resolve party + ensure visit row + charge entry-toll first-fire.
##      Locate is one of the activities that triggers the toll on entering
##      the market (per RAW: toll is for entry, not transaction success).
##   3. Delegate to MerchantPoolRepository.process_locate. The substrate
##      returns one of three outcomes per §6.1:
##        a. Visible match → no-op success (player already knew).
##        b. Invisible match → surface ONE (set becomes_visible_calendar_day
##           = current_day). Substrate emits merchant_surfaced_via_locate.
##        c. No match → fail with no_merchant_of_type. Player still spent
##           the 1 hour (game time advances per the activity-system tick
##           accounting).
##   4. Translate substrate outcome to a player-facing summary; return the
##      result dict (success, surfaced_now, merchant_id, entry_toll_cp).
##
## state.params_json shape:
##   { merchandise_type: <one of 31 MerchandiseRegistry types> }


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var settlement_id: String = String(state.get("location_ref", ""))
	if character_id.is_empty() or settlement_id.is_empty():
		return {"summary": "locate_merchandise: missing character_id or location_ref",
				"success": false}

	var params: Dictionary = _parse_params(state)
	var merchandise_type: String = String(params.get("merchandise_type", ""))
	if merchandise_type.is_empty():
		return {"summary": "locate_merchandise: merchandise_type required", "success": false}

	# 1. Party + visit-state + entry-toll first-fire.
	var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
	if party_id.is_empty():
		return {"summary": "locate_merchandise: no party for active character", "success": false}
	if not VisitStateManager.has_active_visit(party_id, settlement_id):
		VisitStateManager.on_party_entered_settlement(
			party_id, settlement_id, character_id, Timekeeping.get_total_days())
	var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
	var toll_charge_cp: int = BuySellCommon.charge_entry_toll_if_first_visit(
		party_id, settlement_id, false, 0, rng)

	# 2. Delegate to substrate.
	var current_day: int = Timekeeping.get_total_days()
	var result: Dictionary = MerchantPoolRepository.process_locate(
		settlement_id, merchandise_type, current_day)

	# 3. Translate outcome to summary.
	var success: bool = bool(result.get("success", false))
	var surfaced_now: bool = bool(result.get("surfaced_now", false))
	var summary_text: String = ""
	if success:
		if surfaced_now:
			summary_text = "Located a %s merchant — they are now visible at the market." % merchandise_type
		else:
			summary_text = "A %s merchant is already visible at the market." % merchandise_type
	else:
		summary_text = "No %s merchant in this market's pool. Try persuading another merchant to deal in %s." % [
			merchandise_type, merchandise_type]

	return {
		"summary": summary_text,
		"success": success,
		"surfaced_now": surfaced_now,
		"merchant_id": String(result.get("merchant_id", "")),
		"entry_toll_cp": toll_charge_cp,
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}
