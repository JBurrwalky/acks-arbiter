class_name PersuadeMerchantsHandler
extends RefCounted

## persuade_merchants handler — Phase 10B.2 Wave 3 (Trade block).
##
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §4 +
## acore-campaign-hijinks.xml §market_arbitrage step 3 (L707-716).
##
## Reaction roll: 2d6 + CHA mod + 5-proficiency suite (Bribery / Diplomacy /
## Intimidation / Mystic Aura / Seduction) + signed demand modifier + monopolist
## +3. Thresholds: 9 (Common) / 12 (Precious).
##
## Outcomes (per §4.6 + §4.7):
##   * Success: UPDATE merchant_pool.merchandise_type → target type.
##     Emit merchant_persuaded.
##   * Failure (transactional, promoted_npc_id IS NULL): DELETE the row per
##     RAW L715 "permanently lost." Emit merchant_persuasion_failed with
##     outcome="deleted".
##   * Failure (promoted, promoted_npc_id IS NOT NULL): UPDATE refused_at_calendar_day
##     to current day. The NPC survives but refuses this cohort per §0.1.1.
##     Emit merchant_persuasion_failed with outcome="refused_cohort".
##
## state.params_json shape:
##   { merchant_id, target_merchandise_type, direction: "buy" | "sell" }
##
## Also charges entry-toll first-fire per §1.2 — persuade is one of the
## activities that triggers the toll on entering the market.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var settlement_id: String = String(state.get("location_ref", ""))
	if character_id.is_empty() or settlement_id.is_empty():
		return {"summary": "persuade_merchants: missing character_id or location_ref", "success": false}

	var params: Dictionary = _parse_params(state)
	var merchant_id: String = String(params.get("merchant_id", ""))
	var target_merch_type: String = String(params.get("target_merchandise_type", ""))
	var direction: String = String(params.get("direction", "buy"))

	# 1. Validate merchant + target type.
	if target_merch_type.is_empty():
		return {"summary": "persuade_merchants: target_merchandise_type required", "success": false}
	if not (direction in ["buy", "sell"]):
		return {"summary": "persuade_merchants: invalid direction '%s'" % direction, "success": false}
	var merchant: Dictionary = MerchantPoolRepository.get_merchant(merchant_id)
	if merchant.is_empty():
		return {"summary": "persuade_merchants: merchant not found", "success": false}
	if String(merchant.get("status", "")) != "active":
		return {"summary": "persuade_merchants: merchant inactive", "success": false}
	var old_type: String = String(merchant.get("merchandise_type", ""))
	if old_type == target_merch_type:
		return {"summary": "persuade_merchants: merchant already deals in %s" % target_merch_type,
				"success": false}

	# 2. Resolve party + ensure visit row + charge entry toll first-fire.
	var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
	if party_id.is_empty():
		return {"summary": "persuade_merchants: no party for active character", "success": false}
	if not VisitStateManager.has_active_visit(party_id, settlement_id):
		VisitStateManager.on_party_entered_settlement(
			party_id, settlement_id, character_id, Timekeeping.get_total_days())
	var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
	var toll_charge_cp: int = BuySellCommon.charge_entry_toll_if_first_visit(
		party_id, settlement_id, false, 0, rng)

	# 3. Compute reaction-roll modifiers.
	var character: Dictionary = CampaignRepository.get_character(character_id)
	var cha_mod: int = CharacterData.ability_modifier(int(character.get("charisma", 10)))
	var prof_mods: int = 0
	for prof_key in ["bribery", "diplomacy", "intimidation", "mystic_aura", "seduction"]:
		prof_mods += CampaignRepository.get_character_proficiency_rank(character_id, prof_key, "")
	var demand_mod: int = DemandModifierGenerator.get_demand_modifier(
		settlement_id, target_merch_type)
	# Per RAW L711-712: +demand for SELL (we're seeking buyers — high local demand
	# helps); -demand for BUY (seeking sellers — high local demand means
	# merchants hoard).
	var signed_demand: int = demand_mod if direction == "sell" else -demand_mod
	var monopolist_bonus: int = 3 if MonopolyRegistry.has_monopoly(
		character_id, settlement_id, target_merch_type) else 0
	var threshold: int = 12 if MerchandiseRegistry.is_precious(target_merch_type) else 9

	# 4. Roll. Deterministic per (character, merchant) for replay safety.
	var persuade_rng: RandomNumberGenerator = _persuade_rng(character_id, merchant_id)
	var roll_2d6: int = persuade_rng.randi_range(1, 6) + persuade_rng.randi_range(1, 6)
	var modifier_total: int = cha_mod + prof_mods + signed_demand + monopolist_bonus
	var total: int = roll_2d6 + modifier_total
	var success: bool = total >= threshold

	# 5. Apply outcome.
	var outcome_label: String = "success"
	if success:
		CampaignRepository.db.query_with_bindings(
			"UPDATE merchant_pool SET merchandise_type = ? WHERE id = ?",
			[target_merch_type, merchant_id])
		EventBus.merchant_persuaded.emit(
			merchant_id, settlement_id, old_type, target_merch_type)
	else:
		# §0.1.1 + §4.7 fork: DELETE transactional / refused-cohort promoted.
		var promoted_var: Variant = merchant.get("promoted_npc_id", null)
		var is_promoted: bool = (promoted_var != null and not str(promoted_var).is_empty())
		if is_promoted:
			CampaignRepository.db.query_with_bindings(
				"UPDATE merchant_pool SET refused_at_calendar_day = ? WHERE id = ?",
				[Timekeeping.get_total_days(), merchant_id])
			outcome_label = "refused_cohort"
			EventBus.merchant_persuasion_failed.emit(
				merchant_id, settlement_id, target_merch_type, "refused_cohort")
		else:
			CampaignRepository.db.query_with_bindings(
				"DELETE FROM merchant_pool WHERE id = ?", [merchant_id])
			outcome_label = "deleted"
			EventBus.merchant_persuasion_failed.emit(
				merchant_id, settlement_id, target_merch_type, "deleted")

	return {
		"summary": "persuade_merchants: roll %d + mods %d = %d vs %d → %s" % [
			roll_2d6, modifier_total, total, threshold,
			"success" if success else "failure (%s)" % outcome_label],
		"success": success,
		"roll_breakdown": {
			"roll_2d6": roll_2d6,
			"cha_mod": cha_mod,
			"proficiency_mods": prof_mods,
			"signed_demand_modifier": signed_demand,
			"monopolist_bonus": monopolist_bonus,
			"total": total,
			"threshold": threshold,
			"outcome": outcome_label if not success else "success",
		},
		"entry_toll_cp": toll_charge_cp,
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


## Deterministic per (character, merchant). Same character + same merchant
## always produces the same persuade roll — replay-safe.
static func _persuade_rng(character_id: String, merchant_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|persuade" % [character_id, merchant_id])
	return rng
