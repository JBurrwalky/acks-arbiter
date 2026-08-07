class_name AssassinatingHijinkHandler
extends RefCounted

## perform_hijink dispatch for hijink_kind='assassinating'.
##
## RAW §assassinating acore-campaign-hijinks.xml:102-128:
##   * Eligibility: assassins and elven nightblades only.
##   * Throw: Hide in Shadows.
##   * Penalty: -1 to throw per level the perpetrator is BELOW the victim.
##   * Payout (for-hire): 1,000gp per level of victim to boss (= 100,000cp/level).
##   * Payout (personal reasons): 0gp.
##   * 0-level victim counts as 1/2 level → 500gp (= 50,000cp).
##
## Params:
##   target_id (optional): characters.id of the victim (suspended NPC).
##   victim_level (required-ish): the victim's level. If target_id is supplied
##     and resolves to a real character, the victim_level is read from that
##     row; otherwise the explicit param is used.
##   for_hire (optional, default true): if false, no bounty per RAW L114.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var hijink_id := StringUtils.s(state.get("hijink_assignment_id"), StringUtils.s(state.get("hijink_id")))
	if hijink_id.is_empty():
		return {"summary": "assassinating failed: hijink_assignment_id missing"}
	var rng: RandomNumberGenerator = state.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var current_day: int = int(state.get("calendar_day", Timekeeping.get_total_days()))
	return HijinkCommon.resolve(
		hijink_id,
		state,
		Callable(AssassinatingHijinkHandler, "_compute_yield"),
		rng,
		current_day,
	)


static func _compute_yield(
		_perpetrator_level: int,
		_rng: RandomNumberGenerator,
		params: Dictionary,
		_character_id: String,
) -> Dictionary:
	var for_hire: bool = bool(params.get("for_hire", true))
	if not for_hire:
		return {"cp_yield": 0, "detail": "assassination for personal reasons — no bounty per RAW L114"}

	var victim_level: int = int(params.get("victim_level", 1))
	var target_id := String(params.get("target_id", ""))
	if not target_id.is_empty():
		if CampaignRepository.db.query_with_bindings(
			"SELECT level FROM characters WHERE id = ?", [target_id]
		):
			if not CampaignRepository.db.query_result.is_empty():
				victim_level = int(CampaignRepository.db.query_result[0].get("level", victim_level))

	# 0-level victims yield 500gp = 50_000cp; otherwise 1000gp × level.
	var payout_cp: int = 0
	if victim_level <= 0:
		payout_cp = 50_000
	else:
		payout_cp = 100_000 * victim_level

	return {
		"cp_yield": payout_cp,
		"detail": "for-hire bounty on victim level %d = %s" % [
			victim_level, Currency.format_cost(payout_cp),
		],
	}
