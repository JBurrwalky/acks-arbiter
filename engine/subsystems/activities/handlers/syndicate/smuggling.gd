class_name SmugglingHijinkHandler
extends RefCounted

## perform_hijink dispatch target for hijink_kind='smuggling'.
##
## RAW §smuggling acore-campaign-hijinks.xml:152-172:
##   * Eligibility: thieves only (extended to elven_nightblades per
##     HijinkThrowTarget allowlist).
##   * Throw: Move Silently.
##   * Loads: 10 per perpetrator level.
##   * Payout: 12% of market value of smuggled merchandise to boss.
##   * Extra loads: -1 to throw per additional 10 loads (optional).
##
## Merchandise type is determined by random roll on the Common Merchandise
## table (RAW L157). Market value comes from MarketPriceResolver against the
## syndicate's base settlement.
##
## Params:
##   merchandise_type (optional): if supplied, use this type instead of rolling.
##   extra_loads_attempted (optional, default 0): pre-applied as -1/×10 throw
##     penalty in the planning_penalty layer if used (v1: not applied; flag for
##     polish).
##   settlement_id (optional): the urban base; if absent, falls back to the
##     syndicate's base_settlement_entrance_id.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var hijink_id := String(state.get("hijink_assignment_id", state.get("hijink_id", "")))
	if hijink_id.is_empty():
		return {"summary": "smuggling failed: hijink_assignment_id missing"}
	var rng: RandomNumberGenerator = state.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var current_day: int = int(state.get("calendar_day", Timekeeping.get_total_days()))
	return HijinkCommon.resolve(
		hijink_id,
		state,
		Callable(SmugglingHijinkHandler, "_compute_yield"),
		rng,
		current_day,
	)


# ---------------------------------------------------------------------------
# Yield computation
# ---------------------------------------------------------------------------

## RAW: 10 loads × perpetrator level × market value × 12% to boss.
## Returns { cp_yield: int, detail: String }.
static func _compute_yield(
		perpetrator_level: int,
		rng: RandomNumberGenerator,
		params: Dictionary,
		character_id: String,
) -> Dictionary:
	var loads_count: int = max(0, perpetrator_level) * 10
	if loads_count <= 0:
		return {"cp_yield": 0, "detail": "0-level smuggler — no loads moved"}

	# Resolve merchandise type. If unspecified, roll on the Common
	# Merchandise table via MerchandiseRegistry.random_common.
	var merchandise_type := String(params.get("merchandise_type", ""))
	if merchandise_type.is_empty():
		var picked: Dictionary = MerchandiseRegistry.random_common(rng)
		merchandise_type = String(picked.get("merchandise_type", ""))
	if merchandise_type.is_empty():
		return {"cp_yield": 0, "detail": "no merchandise type available"}

	# Resolve settlement for market price.
	var settlement_id := _resolve_settlement_id(params, character_id)
	if settlement_id.is_empty():
		return {"cp_yield": 0, "detail": "no settlement context for market price"}

	var price: Dictionary = MarketPriceResolver.compute_market_price(
		merchandise_type, settlement_id, 0, 0, rng
	)
	var cp_per_load: int = int(price.get("cp_per_load", 0))
	var total_market_value_cp: int = cp_per_load * loads_count
	# RAW: 12% to boss. Banker's-round defensively (boss can't be paid in 0.5cp).
	var raw_payout: float = float(total_market_value_cp) * 0.12
	var payout_cp: int = XPAwardCalculator.bankers_round(raw_payout)
	return {
		"cp_yield": payout_cp,
		"detail": "%d loads of %s @ %s/load = %s market value, 12%% boss share" % [
			loads_count, merchandise_type,
			Currency.format_cost(cp_per_load),
			Currency.format_cost(total_market_value_cp),
		],
	}


static func _resolve_settlement_id(params: Dictionary, _character_id: String) -> String:
	var sid := String(params.get("settlement_id", ""))
	if not sid.is_empty():
		return sid
	# Try the hijink row's syndicate → syndicates.base_settlement_entrance_id.
	var hijink_id := String(params.get("hijink_assignment_id", params.get("hijink_id", "")))
	if not hijink_id.is_empty():
		var hijink := SyndicateRepository.get_hijink(hijink_id)
		var syndicate_id := String(hijink.get("syndicate_id", ""))
		if not syndicate_id.is_empty():
			var syndicate := SyndicateRepository.get_syndicate(syndicate_id)
			return String(syndicate.get("base_settlement_entrance_id", ""))
	return ""


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
