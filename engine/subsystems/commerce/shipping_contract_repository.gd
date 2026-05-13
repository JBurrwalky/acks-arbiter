class_name ShippingContractRepository
extends RefCounted

## Shipping contract persistence — tracks contracts the party has ACCEPTED.
## Per generation/gdd-settlement-economy.md §9.7 + §9.9 + §9.10.
##
## Contracts spawn a cargo_holds row on accept with
## `source_acquisition_kind='shipping_contract'` and `shipping_contract_id`
## back-pointing to the contract row. Delivery on time credits `fee_gp` to
## the party wallet and deletes the linked cargo rows; late delivery pays
## nothing in v1 ([NEEDS-LATE-DELIVERY-PENALTY-PASS] for partial-fee with
## reputation penalty).
##
## RefCounted static-function library — no instance state.


# ---------------------------------------------------------------------------
# Accept / lifecycle
# ---------------------------------------------------------------------------

## Inserts a shipping_contracts row with status='accepted'. Returns the
## new contract_id, or "" on failure. Emits `shipping_contract_accepted`.
##
## Phase 10B.2's accept-handler is responsible for the linked cargo_holds
## row (call CargoHoldRepository.insert_shipping_contract_load with the
## returned contract_id).
static func accept_contract(
		party_id: String,
		origin_settlement_id: String,
		destination_settlement_id: String,
		merchandise_type: String,
		loads_count: int,
		fee_gp: int,
		deadline_calendar_day: int,
		current_calendar_day: int,
) -> String:
	if party_id.is_empty() or origin_settlement_id.is_empty() or destination_settlement_id.is_empty():
		return ""
	if merchandise_type.is_empty() or loads_count <= 0:
		return ""
	# Resolve campaign_id via the party.
	if not CampaignRepository.db.query_with_bindings(
			"SELECT campaign_id FROM parties WHERE id = ?", [party_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		push_error("ShippingContractRepository.accept_contract: party '%s' not found" % party_id)
		return ""
	var campaign_id: String = str(CampaignRepository.db.query_result[0].get("campaign_id", ""))
	var contract_id: String = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO shipping_contracts
			(id, campaign_id, accepted_by_party_id,
			 origin_settlement_id, destination_settlement_id,
			 merchandise_type, loads_count, fee_gp,
			 deadline_calendar_day, status, accepted_at_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'accepted', ?)
	""", [
		contract_id, campaign_id, party_id,
		origin_settlement_id, destination_settlement_id,
		merchandise_type, loads_count, fee_gp,
		deadline_calendar_day, current_calendar_day,
	]):
		push_error("ShippingContractRepository.accept_contract: INSERT failed")
		return ""
	EventBus.shipping_contract_accepted.emit(contract_id, party_id, fee_gp)
	return contract_id


## Transitions an 'accepted' contract to 'in_transit' (optional refinement
## marker for UI — explicitly noting the party has departed origin).
## Returns false if the contract is missing or not currently 'accepted'.
static func mark_in_transit(contract_id: String) -> bool:
	if contract_id.is_empty():
		return false
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty():
		return false
	if str(contract.get("status", "")) != "accepted":
		return false
	CampaignRepository.db.query_with_bindings(
		"UPDATE shipping_contracts SET status = 'in_transit' WHERE id = ?",
		[contract_id])
	return true


## Delivers the contract. If [param current_calendar_day] is on or before
## the contract's deadline, credits [fee_gp] to the party wallet (via the
## first PC's coin store), flips status='delivered', and deletes linked
## cargo_holds rows. Otherwise flips status='failed_deadline' and pays
## nothing (v1 per §9.7).
##
## Returns:
##   {success: bool, fee_paid_gp: int, deadline_missed: bool, error: String}
static func deliver(contract_id: String, current_calendar_day: int) -> Dictionary:
	var result := {"success": false, "fee_paid_gp": 0, "deadline_missed": false, "error": ""}
	if contract_id.is_empty():
		result["error"] = "empty_contract_id"
		return result
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty():
		result["error"] = "contract_not_found"
		return result
	var status: String = str(contract.get("status", ""))
	if not (status in ["accepted", "in_transit"]):
		result["error"] = "contract_not_active"
		return result
	var deadline: int = int(contract.get("deadline_calendar_day", 0))
	var fee_gp: int = int(contract.get("fee_gp", 0))
	var party_id: String = str(contract.get("accepted_by_party_id", ""))

	if current_calendar_day > deadline:
		# Late delivery — flip status to failed_deadline. Cargo is still
		# linked; v1 keeps the cargo on the carrier (player may sell elsewhere).
		CampaignRepository.db.query_with_bindings("""
			UPDATE shipping_contracts SET status = 'failed_deadline',
				delivered_at_calendar_day = ? WHERE id = ?
		""", [current_calendar_day, contract_id])
		EventBus.shipping_contract_delivered.emit(contract_id, 0, true)
		result["success"] = true
		result["fee_paid_gp"] = 0
		result["deadline_missed"] = true
		return result

	# On-time delivery — credit fee + delete linked cargo + flip status.
	var credited: bool = _credit_party_fee(party_id, fee_gp)
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM cargo_holds WHERE shipping_contract_id = ?
	""", [contract_id])
	CampaignRepository.db.query_with_bindings("""
		UPDATE shipping_contracts SET status = 'delivered',
			delivered_at_calendar_day = ? WHERE id = ?
	""", [current_calendar_day, contract_id])
	var actual_fee: int = fee_gp if credited else 0
	EventBus.shipping_contract_delivered.emit(contract_id, actual_fee, false)
	result["success"] = true
	result["fee_paid_gp"] = actual_fee
	result["deadline_missed"] = false
	return result


## Cancels an active contract. Sets status='cancelled' if the contract is
## currently 'accepted' or 'in_transit'. Does NOT delete linked cargo —
## the player keeps the goods on whichever carrier is holding them; Phase
## 10B.2 UI can offer "sell at next market" path.
##
## Returns false if missing or already in a terminal state.
static func cancel(contract_id: String) -> bool:
	if contract_id.is_empty():
		return false
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty():
		return false
	var status: String = str(contract.get("status", ""))
	if not (status in ["accepted", "in_transit"]):
		return false
	CampaignRepository.db.query_with_bindings(
		"UPDATE shipping_contracts SET status = 'cancelled' WHERE id = ?",
		[contract_id])
	EventBus.shipping_contract_failed.emit(contract_id, "cancelled")
	return true


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

static func get_contract(contract_id: String) -> Dictionary:
	if contract_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM shipping_contracts WHERE id = ?", [contract_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## Returns contracts in 'accepted' or 'in_transit' status for the party.
## Phase 10B.2's contract-list UI consumes this.
static func list_active_for_party(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM shipping_contracts
		WHERE accepted_by_party_id = ?
			AND status IN ('accepted', 'in_transit')
		ORDER BY deadline_calendar_day ASC
	""", [party_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Credits [fee_gp] to the party's first PC via add_coins_cp (cp = gp * 100).
## Returns true on success, false if no PC exists in the party.
static func _credit_party_fee(party_id: String, fee_gp: int) -> bool:
	if party_id.is_empty() or fee_gp <= 0:
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT c.id FROM party_members pm
		JOIN characters c ON pm.character_id = c.id
		WHERE pm.party_id = ? AND c.character_type = 'pc'
		ORDER BY pm.joined_at ASC LIMIT 1
	""", [party_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var pc_id: String = str(CampaignRepository.db.query_result[0].get("id", ""))
	if pc_id.is_empty():
		return false
	CampaignRepository.add_coins_cp(pc_id, fee_gp * 100)
	return true
