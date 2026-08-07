class_name SpyingHijinkHandler
extends RefCounted

## perform_hijink dispatch for hijink_kind='spying'.
##
## RAW §spying acore-campaign-hijinks.xml:174-193:
##   * Eligibility: assassins, elven nightblades, thieves.
##   * Throw: Hide in Shadows.
##   * Payout: 2d12 × 100gp per perpetrator level (= 200-2400 gp/level).
##   * Plannable: NO.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var hijink_id := StringUtils.s(state.get("hijink_assignment_id"), StringUtils.s(state.get("hijink_id")))
	if hijink_id.is_empty():
		return {"summary": "spying failed: hijink_assignment_id missing"}
	var rng: RandomNumberGenerator = state.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var current_day: int = int(state.get("calendar_day", Timekeeping.get_total_days()))
	return HijinkCommon.resolve(
		hijink_id,
		state,
		Callable(SpyingHijinkHandler, "_compute_yield"),
		rng,
		current_day,
	)


static func _compute_yield(
		perpetrator_level: int,
		rng: RandomNumberGenerator,
		_params: Dictionary,
		_character_id: String,
) -> Dictionary:
	# 2d12 × 100 gp × level → × 100 × 100 cp = × 10_000 cp per level.
	var level_factor: int = max(1, perpetrator_level)
	var two_d12: int = rng.randi_range(1, 12) + rng.randi_range(1, 12)
	var payout_cp: int = two_d12 * 10_000 * level_factor
	return {
		"cp_yield": payout_cp,
		"detail": "secret worth 2d12(=%d)x100gp/level = %s" % [
			two_d12, Currency.format_cost(payout_cp),
		],
	}
