class_name TreasureHuntingHijinkHandler
extends RefCounted

## perform_hijink dispatch for hijink_kind='treasure_hunting'.
##
## RAW §treasure_hunting acore-campaign-hijinks.xml:218-237:
##   * Eligibility: thieves only (extended to elven_nightblades).
##   * Throw: Find Traps.
##   * Payout: a treasure map to a hoard worth 1d6 × 1,000gp per perpetrator
##     level (= 1,000-6,000 gp/level).
##   * v1 simplification: the map's cp value lands directly in the boss's
##     treasury; the actual hoard-location / hex-distance / hoard-recovery
##     adventure hook is deferred to Phase 10B.3.1 polish. RAW L223-224
##     describes the map placement at 6 miles per 1,000gp of hoard value;
##     wiring that to wilderness-map POIs is a future track.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var hijink_id := String(state.get("hijink_assignment_id", state.get("hijink_id", "")))
	if hijink_id.is_empty():
		return {"summary": "treasure_hunting failed: hijink_assignment_id missing"}
	var rng: RandomNumberGenerator = state.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var current_day: int = int(state.get("calendar_day", Timekeeping.get_total_days()))
	return HijinkCommon.resolve(
		hijink_id,
		state,
		Callable(TreasureHuntingHijinkHandler, "_compute_yield"),
		rng,
		current_day,
	)


static func _compute_yield(
		perpetrator_level: int,
		rng: RandomNumberGenerator,
		_params: Dictionary,
		_character_id: String,
) -> Dictionary:
	# 1d6 × 1000 gp × level → × 100_000 cp per level.
	var level_factor: int = max(1, perpetrator_level)
	var one_d6: int = rng.randi_range(1, 6)
	var payout_cp: int = one_d6 * 100_000 * level_factor
	return {
		"cp_yield": payout_cp,
		"detail": "treasure map worth 1d6(=%d)x1000gp/level = %s" % [
			one_d6, Currency.format_cost(payout_cp),
		],
	}
