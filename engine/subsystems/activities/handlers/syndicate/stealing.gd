class_name StealingHijinkHandler
extends RefCounted

## perform_hijink dispatch for hijink_kind='stealing'.
##
## RAW §stealing acore-campaign-hijinks.xml:195-216:
##   * Eligibility: thieves only (extended to elven_nightblades).
##   * Throw: Pick Pockets.
##   * Loads: 2 per perpetrator level.
##   * Payout: 60% of market value of stolen merchandise to boss.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var hijink_id := StringUtils.s(state.get("hijink_assignment_id"), StringUtils.s(state.get("hijink_id")))
	if hijink_id.is_empty():
		return {"summary": "stealing failed: hijink_assignment_id missing"}
	var rng: RandomNumberGenerator = state.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var current_day: int = int(state.get("calendar_day", Timekeeping.get_total_days()))
	return HijinkCommon.resolve(
		hijink_id,
		state,
		Callable(StealingHijinkHandler, "_compute_yield"),
		rng,
		current_day,
	)


static func _compute_yield(
		perpetrator_level: int,
		rng: RandomNumberGenerator,
		params: Dictionary,
		_character_id: String,
) -> Dictionary:
	var loads_count: int = max(0, perpetrator_level) * 2
	if loads_count <= 0:
		return {"cp_yield": 0, "detail": "0-level thief — no loads stolen"}

	var merchandise_type := String(params.get("merchandise_type", ""))
	if merchandise_type.is_empty():
		var picked: Dictionary = MerchandiseRegistry.random_common(rng)
		merchandise_type = String(picked.get("merchandise_type", ""))
	if merchandise_type.is_empty():
		return {"cp_yield": 0, "detail": "no merchandise type available"}

	var settlement_id := _resolve_settlement_id(params)
	if settlement_id.is_empty():
		return {"cp_yield": 0, "detail": "no settlement context for market price"}

	var price: Dictionary = MarketPriceResolver.compute_market_price(
		merchandise_type, settlement_id, 0, 0, rng
	)
	var cp_per_load: int = int(price.get("cp_per_load", 0))
	var total_market_value_cp: int = cp_per_load * loads_count
	# RAW: 60% to boss.
	var payout_cp: int = XPAwardCalculator.bankers_round(float(total_market_value_cp) * 0.60)
	return {
		"cp_yield": payout_cp,
		"detail": "%d loads of %s @ %s/load = %s market value, 60%% boss share" % [
			loads_count, merchandise_type,
			Currency.format_cost(cp_per_load),
			Currency.format_cost(total_market_value_cp),
		],
	}


static func _resolve_settlement_id(params: Dictionary) -> String:
	var sid := String(params.get("settlement_id", ""))
	if not sid.is_empty():
		return sid
	var hijink_id := StringUtils.s(params.get("hijink_assignment_id"), StringUtils.s(params.get("hijink_id")))
	if not hijink_id.is_empty():
		var hijink := SyndicateRepository.get_hijink(hijink_id)
		var syndicate_id := String(hijink.get("syndicate_id", ""))
		if not syndicate_id.is_empty():
			var syndicate := SyndicateRepository.get_syndicate(syndicate_id)
			return StringUtils.s(syndicate.get("base_settlement_entrance_id"))
	return ""


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
