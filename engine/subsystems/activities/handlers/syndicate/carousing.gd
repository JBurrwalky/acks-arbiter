class_name CarousingHijinkHandler
extends RefCounted

## perform_hijink dispatch for hijink_kind='carousing'.
##
## RAW §carousing acore-campaign-hijinks.xml:130-150:
##   * Eligibility: any class, including 0-level.
##   * Throw: Hear Noise.
##   * Payout: 3d12 × 5gp per perpetrator level (= 15-180 gp/level).
##   * Plannable: NO — not in plannable list per ax_campaign_play.xml L1232.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var hijink_id := String(state.get("hijink_assignment_id", state.get("hijink_id", "")))
	if hijink_id.is_empty():
		return {"summary": "carousing failed: hijink_assignment_id missing"}
	var rng: RandomNumberGenerator = state.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var current_day: int = int(state.get("calendar_day", Timekeeping.get_total_days()))
	return HijinkCommon.resolve(
		hijink_id,
		state,
		Callable(CarousingHijinkHandler, "_compute_yield"),
		rng,
		current_day,
	)


static func _compute_yield(
		perpetrator_level: int,
		rng: RandomNumberGenerator,
		_params: Dictionary,
		_character_id: String,
) -> Dictionary:
	# 3d12 × 5 gp × level → × 5 × 100 cp = × 500 cp per level.
	var level_factor: int = max(1, perpetrator_level)
	var three_d12: int = (
		rng.randi_range(1, 12)
		+ rng.randi_range(1, 12)
		+ rng.randi_range(1, 12)
	)
	var payout_cp: int = three_d12 * 500 * level_factor
	return {
		"cp_yield": payout_cp,
		"detail": "rumor worth 3d12(=%d)x5gp/level = %s" % [
			three_d12, Currency.format_cost(payout_cp),
		],
	}
