class_name UnstockPoiDecreeHandler
extends RefCounted

## Stage H of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §7.2 / §13.8 (v1.14).
##
## Inverse of StockPoiDecreeHandler — releases a player-stocked character
## from a POI, reverting it to its baseline placeholder (or to "abandoned"
## state if no baseline exists per Q-UGS-4).
##
## Side effects:
##   * `settlement_pois.stocked_character_id = NULL`.
##   * Emits `poi_unstocked(poi_id, prior_character_id)`.


## Static entry. `params` requires:
##   * `poi_id` — POI to unstock.
##
## Returns `{success, error_code, poi_id, prior_character_id}`.
## error_code values: "" / "no_poi" / "not_stocked" / "internal_error".
static func try_unstock(params: Dictionary) -> Dictionary:
	var poi_id: String = String(params.get("poi_id", ""))
	if poi_id.is_empty():
		return _fail("internal_error", "", "")

	# 1. Look up the POI + current stocked character.
	var poi: Dictionary = _get_poi(poi_id)
	if poi.is_empty():
		return _fail("no_poi", poi_id, "")

	var stocked_v: Variant = poi.get("stocked_character_id", null)
	var prior_character_id: String = ""
	if stocked_v != null:
		prior_character_id = String(stocked_v)
	if prior_character_id.is_empty():
		return _fail("not_stocked", poi_id, "")

	# 2. Clear the binding.
	if not CampaignRepository.set_settlement_poi_stocked_character(poi_id, ""):
		return _fail("internal_error", poi_id, prior_character_id)

	# 3. Emit signal so subscribers (UI, registry-cache consumers) update.
	EventBus.poi_unstocked.emit(poi_id, prior_character_id)

	return {
		"success": true,
		"error_code": "",
		"poi_id": poi_id,
		"prior_character_id": prior_character_id,
	}


static func _get_poi(poi_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM settlement_pois WHERE id = ?", [poi_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _fail(
	error_code: String,
	poi_id: String,
	prior_character_id: String,
) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"poi_id": poi_id,
		"prior_character_id": prior_character_id,
	}
