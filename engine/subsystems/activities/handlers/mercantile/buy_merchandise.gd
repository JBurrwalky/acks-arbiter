class_name BuyMerchandiseHandler
extends RefCounted

## buy_merchandise handler — Phase 10B.2 Wave 2 (Trade block).
##
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §3.2 +
## acore-campaign-hijinks.xml §market_arbitrage step 4 (L617-763).
##
## Pipeline (success path):
##   1. Validate merchant + cargo + carrier + party context.
##   2. Compute entry-toll first-fire via BuySellCommon (charges or 0-no-op).
##   3. Compute price via MarketPriceResolver (with monopolist favor).
##   4. Compute labor + capacity check + monopolist 2× cap (per §4.11).
##   5. Total cost = purchase + labor (toll already debited in step 2).
##      PartyWallet.pay; insert cargo via CargoHoldRepository.insert_purchase;
##      decrement merchant.loads_available via MerchantPoolRepository.consume_loads.
##   6. Build receipt; emit merchandise_purchased; return.
##
## Failure modes return {success: false, summary: "..."}. The activity-state
## frequency machinery in ActivityTimeCostExecutor treats any "summary" return
## value as completion; the success flag is for the caller to surface a
## warning rather than the executor.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var settlement_id: String = String(state.get("location_ref", ""))
	if character_id.is_empty() or settlement_id.is_empty():
		return {"summary": "buy_merchandise: missing character_id or location_ref", "success": false}

	var params: Dictionary = _parse_params(state)
	var merchant_id: String = String(params.get("merchant_id", ""))
	var merchandise_type: String = String(params.get("merchandise_type", ""))
	var loads_count: int = int(params.get("loads_count", 0))
	var carrier_id: String = String(params.get("carrier_id", ""))
	var carrier_kind: String = String(params.get("carrier_kind", ""))

	# 1. Validate merchant.
	var merchant: Dictionary = MerchantPoolRepository.get_merchant(merchant_id)
	if merchant.is_empty():
		return {"summary": "buy_merchandise: merchant not found", "success": false}
	if String(merchant.get("status", "")) != "active":
		return {"summary": "buy_merchandise: merchant inactive (%s)" % String(merchant.get("status", "")),
				"success": false}
	if String(merchant.get("merchandise_type", "")) != merchandise_type:
		return {"summary": "buy_merchandise: merchant deals in '%s', not '%s'" % [
				String(merchant.get("merchandise_type", "")), merchandise_type],
				"success": false}
	if loads_count <= 0:
		return {"summary": "buy_merchandise: loads_count must be positive", "success": false}

	# RAW L714 monopolist 2× cap: a monopolist active character can transact
	# up to 2 × merchant.loads_available. Per §4.11 cap-doubling interpretation;
	# merchant depletion is still at 1× the actual loads_count.
	var max_buyable: int = int(merchant.get("loads_available", 0))
	if MonopolyRegistry.has_monopoly(character_id, settlement_id, merchandise_type):
		max_buyable *= 2
	if loads_count > max_buyable:
		return {"summary": "buy_merchandise: requested %d > max %d (loads_available)" % [
				loads_count, max_buyable],
				"success": false}

	# 2. Resolve party + ensure visit row exists (caller should have invoked
	#    VisitStateManager.on_party_entered_settlement; defensive).
	var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
	if party_id.is_empty():
		return {"summary": "buy_merchandise: no party for active character", "success": false}
	if not VisitStateManager.has_active_visit(party_id, settlement_id):
		VisitStateManager.on_party_entered_settlement(
			party_id, settlement_id, character_id, Timekeeping.get_total_days())

	# 3. Entry toll first-fire + price + labor. All values in cp.
	var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
	var toll_charge_cp: int = BuySellCommon.charge_entry_toll_if_first_visit(
		party_id, settlement_id, false, 0, rng)
	var monopolist_favor: int = MonopolyRegistry.favor_for_buy(
		character_id, settlement_id, merchandise_type)
	var price_result: Dictionary = MarketPriceResolver.compute_market_price(
		merchandise_type, settlement_id, monopolist_favor, 0, rng,
		Timekeeping.get_total_days())
	var cp_per_load: int = int(price_result.get("cp_per_load", 0))
	if cp_per_load <= 0:
		return {"summary": "buy_merchandise: price resolver returned 0 cp/load — settlement misconfigured?",
				"success": false}
	var total_purchase_cp: int = cp_per_load * loads_count
	var load_weight: int = MerchandiseRegistry.load_weight_stone(merchandise_type)
	var labor_fee_cp: int = MarketFeesCalculator.labor_fee_cp(load_weight * loads_count)

	# 4. Carrier capacity check (post-fees, pre-payment).
	if not BuySellCommon.carrier_has_capacity(carrier_id, carrier_kind, load_weight * loads_count):
		return {"summary": "buy_merchandise: carrier %s capacity exceeded" % carrier_id,
				"success": false}

	# 5. Affordability check + debit (cp-native).
	var total_cost_cp: int = total_purchase_cp + labor_fee_cp  # toll already debited in step 3
	var pay_result: Dictionary = PartyWallet.pay(total_cost_cp, party_id, character_id)
	if not bool(pay_result.get("ok", false)):
		# Per RAW the toll is paid on market entry regardless of transaction
		# completion. The toll stays debited; the transaction itself fails.
		return {
			"summary": "buy_merchandise: insufficient funds (need %s purchase + %s labor)" % [
				Currency.format_cost(total_purchase_cp), Currency.format_cost(labor_fee_cp)],
			"success": false,
		}

	# 6. Cargo + merchant state mutation. Repository takes cp throughout.
	var cargo_id: String = CargoHoldRepository.insert_purchase(
		carrier_id, carrier_kind, merchandise_type, loads_count,
		total_purchase_cp, settlement_id, Timekeeping.get_total_days())
	if cargo_id.is_empty():
		# Refund the buy (defensive — insert_purchase rarely fails).
		CampaignRepository.add_coins_cp(character_id, total_cost_cp)
		return {"summary": "buy_merchandise: cargo insert failed", "success": false}
	MerchantPoolRepository.consume_loads(merchant_id, loads_count)

	# 7. Build receipt + emit + return.
	var receipt: Dictionary = BuySellCommon.build_buy_receipt(
		merchandise_type, loads_count, cp_per_load, total_purchase_cp,
		toll_charge_cp, labor_fee_cp, monopolist_favor)
	EventBus.merchandise_purchased.emit(
		cargo_id, settlement_id, merchandise_type, loads_count, total_cost_cp + toll_charge_cp)
	return {
		"summary": "Bought %d × %s @ %s/load (total %s incl. fees)" % [
			loads_count, merchandise_type, Currency.format_cost(cp_per_load),
			Currency.format_cost(total_cost_cp + toll_charge_cp)],
		"success": true,
		"receipt": receipt,
		"cargo_hold_id": cargo_id,
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}
