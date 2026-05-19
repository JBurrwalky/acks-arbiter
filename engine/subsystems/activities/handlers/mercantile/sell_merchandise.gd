class_name SellMerchandiseHandler
extends RefCounted

## sell_merchandise handler — Phase 10B.2 Wave 2 (Trade block).
##
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §3.3 +
## acore-campaign-hijinks.xml §market_arbitrage step 4 (L617-763).
##
## Pipeline (success path):
##   1. Validate cargo + merchant (type must match) + party + loads_to_sell.
##   2. Resolve active character + domain-owner status.
##   3. Compute entry-toll first-fire via BuySellCommon.
##   4. Compute gross sale price (MarketPriceResolver with monopolist favor +1).
##   5. Compute labor + customs (customs zero for domain owner per §8.8).
##   6. Net proceeds = gross - toll - labor - customs.
##      If net >= 0: credit active character. If net < 0: try to debit shortfall
##      from party wallet; fail transaction if wallet can't cover.
##   7. Mutate cargo: full-sell → CargoHoldRepository.delete_sold;
##      partial-sell → CargoHoldRepository.partial_sell (§13.2).
##   8. Build receipt; emit merchandise_sold; return.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var settlement_id: String = String(state.get("location_ref", ""))
	if character_id.is_empty() or settlement_id.is_empty():
		return {"summary": "sell_merchandise: missing character_id or location_ref", "success": false}

	var params: Dictionary = _parse_params(state)
	var merchant_id: String = String(params.get("merchant_id", ""))
	var cargo_hold_id: String = String(params.get("cargo_hold_id", ""))
	var loads_to_sell: int = int(params.get("loads_to_sell", 0))

	# 1. Validate cargo + merchant.
	var cargo: Dictionary = CargoHoldRepository.get_cargo_hold(cargo_hold_id)
	if cargo.is_empty():
		return {"summary": "sell_merchandise: cargo not found", "success": false}
	var merchandise_type: String = String(cargo.get("merchandise_type", ""))
	var current_loads: int = int(cargo.get("loads_count", 0))
	if loads_to_sell <= 0:
		return {"summary": "sell_merchandise: loads_to_sell must be positive", "success": false}
	if loads_to_sell > current_loads:
		return {"summary": "sell_merchandise: requested %d > %d available loads" % [
				loads_to_sell, current_loads],
				"success": false}

	var merchant: Dictionary = MerchantPoolRepository.get_merchant(merchant_id)
	if merchant.is_empty():
		return {"summary": "sell_merchandise: merchant not found", "success": false}
	if String(merchant.get("status", "")) != "active":
		return {"summary": "sell_merchandise: merchant inactive", "success": false}
	if String(merchant.get("merchandise_type", "")) != merchandise_type:
		return {"summary": "sell_merchandise: merchant deals in '%s', not '%s'" % [
				String(merchant.get("merchandise_type", "")), merchandise_type],
				"success": false}

	# 2. Party + domain-owner status.
	var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
	if party_id.is_empty():
		return {"summary": "sell_merchandise: no party for active character", "success": false}
	if not VisitStateManager.has_active_visit(party_id, settlement_id):
		VisitStateManager.on_party_entered_settlement(
			party_id, settlement_id, character_id, Timekeeping.get_total_days())
	var is_domain_owner: bool = MarketFeesCalculator.is_domain_owner_in_own_market(
		character_id, settlement_id)

	# 3. Entry toll first-fire (selling → minimum 1 gp/load floor per RAW L649).
	#    Returns cp.
	var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
	var toll_charge_cp: int = BuySellCommon.charge_entry_toll_if_first_visit(
		party_id, settlement_id, true, loads_to_sell, rng)

	# 4. Price + monopolist favor. Price resolver returns cp/load (exact).
	var monopolist_favor: int = MonopolyRegistry.favor_for_sell(
		character_id, settlement_id, merchandise_type)
	var price_result: Dictionary = MarketPriceResolver.compute_market_price(
		merchandise_type, settlement_id, monopolist_favor, 0, rng,
		Timekeeping.get_total_days())
	var cp_per_load: int = int(price_result.get("cp_per_load", 0))
	var gross_sale_cp: int = cp_per_load * loads_to_sell

	# 5. Labor + customs (cp-native).
	var load_weight: int = MerchandiseRegistry.load_weight_stone(merchandise_type)
	var labor_fee_cp: int = MarketFeesCalculator.labor_fee_cp(load_weight * loads_to_sell)
	var customs_cp: int = MarketFeesCalculator.customs_duty_cp(
		gross_sale_cp, settlement_id, is_domain_owner)

	# 6. Net proceeds (cp). Toll was already debited in step 3 and isn't
	# subtracted again here (per-visit charge, not per-transaction).
	var net_proceeds_cp: int = gross_sale_cp - labor_fee_cp - customs_cp
	if net_proceeds_cp > 0:
		CampaignRepository.add_coins_cp(character_id, net_proceeds_cp)
	elif net_proceeds_cp < 0:
		var pay_result: Dictionary = PartyWallet.pay(-net_proceeds_cp, party_id, character_id)
		if not bool(pay_result.get("ok", false)):
			return {
				"summary": "sell_merchandise: fees exceed proceeds; party cannot cover %s shortfall" %
					Currency.format_cost(-net_proceeds_cp),
				"success": false,
			}

	# 7. Cargo mutation (full or partial). Repository takes cp throughout.
	var ok: bool = false
	if loads_to_sell == current_loads:
		ok = CargoHoldRepository.delete_sold(cargo_hold_id, gross_sale_cp)
	else:
		ok = CargoHoldRepository.partial_sell(cargo_hold_id, loads_to_sell, gross_sale_cp)
	if not ok:
		# Defensive — partial_sell / delete_sold rarely fail. If they do, the
		# wallet credit/debit above has already landed; the cargo row remains.
		# Surface the inconsistency via summary (player can audit via inventory).
		return {"summary": "sell_merchandise: cargo mutation failed (cargo retained, wallet adjusted)",
				"success": false}

	# 8. Build receipt + emit + return.
	var receipt: Dictionary = BuySellCommon.build_sell_receipt(
		merchandise_type, loads_to_sell, cp_per_load, gross_sale_cp,
		toll_charge_cp, labor_fee_cp, customs_cp, monopolist_favor, is_domain_owner)
	EventBus.merchandise_sold.emit(
		cargo_hold_id, settlement_id, merchandise_type, loads_to_sell, net_proceeds_cp)
	return {
		"summary": "Sold %d × %s @ %s/load (net %s; gross %s, labor %s, customs %s, toll %s)" % [
			loads_to_sell, merchandise_type, Currency.format_cost(cp_per_load),
			Currency.format_cost(net_proceeds_cp), Currency.format_cost(gross_sale_cp),
			Currency.format_cost(labor_fee_cp), Currency.format_cost(customs_cp),
			Currency.format_cost(toll_charge_cp)],
		"success": true,
		"receipt": receipt,
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}
