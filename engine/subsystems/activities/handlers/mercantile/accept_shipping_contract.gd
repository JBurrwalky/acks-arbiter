class_name AcceptShippingContractHandler
extends RefCounted

## accept_shipping_contract handler — Phase 10B.2 Wave 4 (Trade block).
##
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §7.7 + RAW
## acore-campaign-hijinks.xml §passenger_and_cargo_transport (L765-837).
##
## Pipeline:
##   1. Validate offer exists + belongs to active party.
##   2. Validate carrier kind matches route_mode (road → draft_vehicle;
##      water → ship).
##   3. Validate carrier has capacity for total_stone = loads × stone_per_load.
##   4. Charge entry-toll first-fire per §1.2 (accepting a contract enters
##      the market — RAW: toll is for entry, not transaction success).
##   5. Call ShippingContractRepository.accept_contract → inserts the
##      contract row; emits substrate's shipping_contract_accepted signal.
##   6. Call CargoHoldRepository.insert_shipping_contract_load → links
##      cargo row to the contract via shipping_contract_id.
##   7. DELETE the offer row (one-shot — accepting consumes it).
##   8. Emit shipping_offer_accepted with the trio (offer_id, contract_id,
##      cargo_hold_id). Return receipt.
##
## state.params_json shape:
##   { offer_id: String, carrier_id: String, carrier_kind: String }


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var settlement_id: String = String(state.get("location_ref", ""))
	if character_id.is_empty() or settlement_id.is_empty():
		return {"summary": "accept_shipping_contract: missing character_id or location_ref",
				"success": false}

	var params: Dictionary = _parse_params(state)
	var offer_id: String = String(params.get("offer_id", ""))
	var carrier_id: String = String(params.get("carrier_id", ""))
	var carrier_kind: String = String(params.get("carrier_kind", ""))
	if offer_id.is_empty() or carrier_id.is_empty() or carrier_kind.is_empty():
		return {"summary": "accept_shipping_contract: offer_id, carrier_id, carrier_kind required",
				"success": false}

	# 1. Validate offer.
	var offer: Dictionary = ShippingContractOfferRoller.get_offer(offer_id)
	if offer.is_empty():
		return {"summary": "accept_shipping_contract: offer not found (expired or already accepted)",
				"success": false}

	# 2. Party + ownership check + visit-state.
	var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
	if party_id.is_empty():
		return {"summary": "accept_shipping_contract: no party for active character",
				"success": false}
	if String(offer.get("party_id", "")) != party_id:
		return {"summary": "accept_shipping_contract: offer belongs to a different party",
				"success": false}
	if not VisitStateManager.has_active_visit(party_id, settlement_id):
		VisitStateManager.on_party_entered_settlement(
			party_id, settlement_id, character_id, Timekeeping.get_total_days())

	# 3. Carrier-kind matches route_mode.
	var route_mode: String = String(offer.get("route_mode", "road"))
	var required_carrier: String = "draft_vehicle" if route_mode == "road" else "ship"
	if carrier_kind != required_carrier:
		return {"summary": "accept_shipping_contract: %s route requires a %s, not %s" % [
				route_mode, required_carrier, carrier_kind],
				"success": false}

	# 4. Capacity check.
	var loads_count: int = int(offer.get("loads_count", 0))
	var load_weight: int = int(offer.get("load_weight_stone", 0))
	var total_stone: int = loads_count * load_weight
	if not BuySellCommon.carrier_has_capacity(carrier_id, carrier_kind, total_stone):
		return {"summary": "accept_shipping_contract: carrier lacks capacity (%d stone needed)" % total_stone,
				"success": false}

	# 5. Entry toll first-fire (returns cp).
	var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
	var toll_charge_cp: int = BuySellCommon.charge_entry_toll_if_first_visit(
		party_id, settlement_id, false, 0, rng)  # accepting a contract isn't selling

	# 6. Substrate: insert the shipping_contracts row. Fee carried in cp.
	var contract_id: String = ShippingContractRepository.accept_contract(
		party_id,
		String(offer.get("origin_settlement_id", "")),
		String(offer.get("destination_settlement_id", "")),
		String(offer.get("merchandise_type", "mixed_cargo")),
		loads_count,
		int(offer.get("fee_cp", 0)),
		int(offer.get("deadline_calendar_day", 0)),
		Timekeeping.get_total_days())
	if contract_id.is_empty():
		return {"summary": "accept_shipping_contract: substrate accept_contract failed",
				"success": false}

	# 7. Substrate: link the cargo_holds row to the contract.
	var cargo_id: String = CargoHoldRepository.insert_shipping_contract_load(
		carrier_id, carrier_kind,
		String(offer.get("merchandise_type", "mixed_cargo")),
		loads_count,
		contract_id,
		String(offer.get("origin_settlement_id", "")),
		Timekeeping.get_total_days())
	if cargo_id.is_empty():
		# Substrate accept_contract already committed; defensive log + continue.
		push_warning("AcceptShippingContractHandler: contract %s accepted but cargo insert failed" % contract_id)

	# 8. DELETE the offer (one-shot consumption).
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM shipping_contract_offers WHERE id = ?", [offer_id])

	# 9. Emit Phase 10B.2 signal (substrate's shipping_contract_accepted fires
	#    from accept_contract itself).
	EventBus.shipping_offer_accepted.emit(offer_id, contract_id, cargo_id)

	return {
		"summary": "Accepted contract: %d loads of %s to %s by day %d for %s." % [
			loads_count,
			String(offer.get("merchandise_type", "mixed_cargo")),
			String(offer.get("destination_settlement_id", "")),
			int(offer.get("deadline_calendar_day", 0)),
			Currency.format_cost(int(offer.get("fee_cp", 0)))],
		"success": true,
		"contract_id": contract_id,
		"cargo_hold_id": cargo_id,
		"offer_id": offer_id,
		"entry_toll_cp": toll_charge_cp,
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}
