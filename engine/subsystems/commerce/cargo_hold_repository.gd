class_name CargoHoldRepository
extends RefCounted

## Cargo holds persistence — one row per cargo acquisition with carrier XOR
## (draft_vehicle_id or ship_id), merchandise + load metadata, and provenance
## (purchased / smuggled / stolen / shipping_contract).
##
## Per generation/gdd-settlement-economy.md §9.4 + §9.8 + §9.10. Inserts are
## typed per acquisition kind so callers can't misuse the source_kind enum.
## load_weight_stone is cached from MerchandiseRegistry at insert time to
## avoid registry lookups on every encumbrance query.


# ---------------------------------------------------------------------------
# Carrier kind enum (caller-supplied to typed inserts)
# ---------------------------------------------------------------------------

const CARRIER_DRAFT_VEHICLE := "draft_vehicle"
const CARRIER_SHIP := "ship"


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

static func list_for_draft_vehicle(draft_vehicle_id: String) -> Array:
	if draft_vehicle_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM cargo_holds WHERE draft_vehicle_id = ? ORDER BY created_at ASC",
			[draft_vehicle_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_for_ship(ship_id: String) -> Array:
	if ship_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM cargo_holds WHERE ship_id = ? ORDER BY created_at ASC",
			[ship_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func get_cargo_hold(cargo_hold_id: String) -> Dictionary:
	if cargo_hold_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM cargo_holds WHERE id = ?", [cargo_hold_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


# ---------------------------------------------------------------------------
# Typed writes — purchased / hijink yield / shipping contract
# ---------------------------------------------------------------------------

## Inserts a purchase row. `market_value_at_acquisition_gp` is the gp PAID
## (the bridge between purchase price and resale price for arbitrage math).
## Emits cargo_loaded on success. Returns new cargo_hold_id, or "" on failure.
static func insert_purchase(
		carrier_id: String,
		carrier_kind: String,
		merchandise_type: String,
		loads_count: int,
		gp_paid: int,
		settlement_id: String,
		current_calendar_day: int,
) -> String:
	return _insert_cargo_row({
		"carrier_id": carrier_id,
		"carrier_kind": carrier_kind,
		"merchandise_type": merchandise_type,
		"loads_count": loads_count,
		"market_value_gp": gp_paid,
		"source_kind": "purchased",
		"settlement_id": settlement_id,
		"calendar_day": current_calendar_day,
	})


## Inserts a smuggling or stealing hijink yield. `market_value_gp` is the
## NOTIONAL gp value at the source market (basis for Phase 10B.3's 12% / 60%
## boss-payout multipliers).
static func insert_hijink_yield(
		carrier_id: String,
		carrier_kind: String,
		merchandise_type: String,
		loads_count: int,
		market_value_gp: int,
		settlement_id: String,
		current_calendar_day: int,
		kind: String,
) -> String:
	if not (kind in ["smuggled", "stolen"]):
		push_error("CargoHoldRepository.insert_hijink_yield: kind must be 'smuggled' or 'stolen', got '%s'" % kind)
		return ""
	return _insert_cargo_row({
		"carrier_id": carrier_id,
		"carrier_kind": carrier_kind,
		"merchandise_type": merchandise_type,
		"loads_count": loads_count,
		"market_value_gp": market_value_gp,
		"source_kind": kind,
		"settlement_id": settlement_id,
		"calendar_day": current_calendar_day,
	})


## Inserts a shipping-contract cargo row. Phase 10B.2 invokes when a party
## accepts a contract from a market's available-contracts list.
static func insert_shipping_contract_load(
		carrier_id: String,
		carrier_kind: String,
		merchandise_type: String,
		loads_count: int,
		contract_id: String,
		settlement_id: String,
		current_calendar_day: int,
) -> String:
	return _insert_cargo_row({
		"carrier_id": carrier_id,
		"carrier_kind": carrier_kind,
		"merchandise_type": merchandise_type,
		"loads_count": loads_count,
		"market_value_gp": 0,
		"source_kind": "shipping_contract",
		"settlement_id": settlement_id,
		"calendar_day": current_calendar_day,
		"contract_id": contract_id,
	})


# ---------------------------------------------------------------------------
# Transfer / split
# ---------------------------------------------------------------------------

## Moves [param loads_count] loads from [param source_cargo_hold_id] to a
## new cargo_holds row on [param target_carrier_id] (with [param target_carrier_kind]).
## If loads_count == source.loads_count, the source row is deleted (full transfer);
## otherwise the source row's loads_count is decremented (partial transfer).
##
## Returns {success, source_remaining, target_cargo_hold_id, error}.
##
## v1 caller responsibility: verify carriers are co-located (port, parking lot,
## etc.) before invoking. The repository performs no co-location check.
static func transfer_loads(
		source_cargo_hold_id: String,
		target_carrier_id: String,
		target_carrier_kind: String,
		loads_count: int,
) -> Dictionary:
	var result := {"success": false, "source_remaining": 0, "target_cargo_hold_id": "", "error": ""}
	if source_cargo_hold_id.is_empty() or target_carrier_id.is_empty() or loads_count <= 0:
		result["error"] = "empty_args_or_zero_loads"
		return result
	var source: Dictionary = get_cargo_hold(source_cargo_hold_id)
	if source.is_empty():
		result["error"] = "source_not_found"
		return result
	var available: int = int(source.get("loads_count", 0))
	if loads_count > available:
		result["error"] = "insufficient_loads"
		return result
	# Insert new row on the target.
	var new_id: String = _insert_cargo_row({
		"carrier_id": target_carrier_id,
		"carrier_kind": target_carrier_kind,
		"merchandise_type": str(source.get("merchandise_type", "")),
		"loads_count": loads_count,
		"market_value_gp": int(source.get("market_value_at_acquisition_gp", 0)),
		"source_kind": str(source.get("source_acquisition_kind", "purchased")),
		"settlement_id": str(source.get("acquired_at_settlement_id", "")),
		"calendar_day": int(source.get("acquired_at_calendar_day", 0)),
	})
	if new_id.is_empty():
		result["error"] = "target_insert_failed"
		return result
	# Update or delete the source.
	if loads_count == available:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM cargo_holds WHERE id = ?", [source_cargo_hold_id])
		result["source_remaining"] = 0
	else:
		var new_source_loads: int = available - loads_count
		CampaignRepository.db.query_with_bindings(
			"UPDATE cargo_holds SET loads_count = ? WHERE id = ?",
			[new_source_loads, source_cargo_hold_id])
		result["source_remaining"] = new_source_loads
	result["success"] = true
	result["target_cargo_hold_id"] = new_id
	return result


# ---------------------------------------------------------------------------
# Delete on sale
# ---------------------------------------------------------------------------

## Deletes the row at sell time. Caller passes [param gp_received] (the
## actual gp credited post-fees) for the cargo_sold signal payload.
static func delete_sold(cargo_hold_id: String, gp_received: int) -> bool:
	if cargo_hold_id.is_empty():
		return false
	var row: Dictionary = get_cargo_hold(cargo_hold_id)
	if row.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"DELETE FROM cargo_holds WHERE id = ?", [cargo_hold_id]):
		return false
	EventBus.cargo_sold.emit(cargo_hold_id, gp_received)
	return true


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _insert_cargo_row(args: Dictionary) -> String:
	var carrier_id: String = str(args.get("carrier_id", ""))
	var carrier_kind: String = str(args.get("carrier_kind", ""))
	if carrier_id.is_empty():
		push_error("CargoHoldRepository: carrier_id required")
		return ""
	if not (carrier_kind in [CARRIER_DRAFT_VEHICLE, CARRIER_SHIP]):
		push_error("CargoHoldRepository: invalid carrier_kind '%s'" % carrier_kind)
		return ""
	var merchandise_type: String = str(args.get("merchandise_type", ""))
	if merchandise_type.is_empty():
		push_error("CargoHoldRepository: merchandise_type required")
		return ""
	var loads_count: int = int(args.get("loads_count", 0))
	if loads_count <= 0:
		push_error("CargoHoldRepository: loads_count must be > 0")
		return ""

	# Resolve campaign_id via the carrier.
	var campaign_id: String = _read_campaign_id(carrier_id, carrier_kind)
	if campaign_id.is_empty():
		push_error("CargoHoldRepository: cannot resolve campaign_id for carrier %s/%s" % [carrier_kind, carrier_id])
		return ""

	# Cache load_weight_stone from the registry (per §9.4 rationale).
	var load_weight: int = MerchandiseRegistry.load_weight_stone(merchandise_type)

	var cargo_id: String = CampaignRepository.generate_id()
	var draft_vehicle_id: Variant = carrier_id if carrier_kind == CARRIER_DRAFT_VEHICLE else null
	var ship_id: Variant = carrier_id if carrier_kind == CARRIER_SHIP else null
	var settlement_id: Variant = args.get("settlement_id", "")
	if str(settlement_id).is_empty():
		settlement_id = null
	var contract_id: Variant = args.get("contract_id", "")
	if str(contract_id).is_empty():
		contract_id = null

	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO cargo_holds
			(id, campaign_id, draft_vehicle_id, ship_id,
			 merchandise_type, loads_count, load_weight_stone,
			 market_value_at_acquisition_gp, source_acquisition_kind,
			 acquired_at_settlement_id, acquired_at_calendar_day,
			 shipping_contract_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		cargo_id, campaign_id, draft_vehicle_id, ship_id,
		merchandise_type, loads_count, load_weight,
		int(args.get("market_value_gp", 0)),
		str(args.get("source_kind", "purchased")),
		settlement_id, int(args.get("calendar_day", 0)),
		contract_id,
	]):
		push_error("CargoHoldRepository: INSERT failed for %s on %s" % [merchandise_type, carrier_id])
		return ""

	EventBus.cargo_loaded.emit(cargo_id, carrier_id, merchandise_type, loads_count)
	return cargo_id


static func _read_campaign_id(carrier_id: String, carrier_kind: String) -> String:
	var table: String = "draft_vehicles" if carrier_kind == CARRIER_DRAFT_VEHICLE else "ships"
	if not CampaignRepository.db.query_with_bindings(
			"SELECT campaign_id FROM %s WHERE id = ?" % table, [carrier_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return str(CampaignRepository.db.query_result[0].get("campaign_id", ""))
