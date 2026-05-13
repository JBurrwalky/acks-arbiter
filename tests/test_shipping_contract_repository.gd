extends "res://tests/test_suite_base.gd"

## Unit tests for ShippingContractRepository — accept / deliver / cancel /
## list per Prereq.5c.
##
## Per generation/gdd-settlement-economy.md §9.12.

var _campaign_id: String = ""
var _map_id: String = ""
var _origin_id: String = ""
var _dest_id: String = ""
var _party_id: String = ""
var _pc_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_accept_contract_creates_row()
	test_accept_contract_emits_signal()
	test_mark_in_transit_transitions()
	test_mark_in_transit_rejects_non_accepted()
	test_deliver_on_time_credits_fee_and_deletes_cargo()
	test_deliver_after_deadline_pays_nothing()
	test_deliver_emits_signal_with_correct_payload()
	test_deliver_rejects_terminal_contract()
	test_list_active_for_party()
	test_cancel_sets_status()
	test_cancel_rejects_terminal()
	test_cancel_emits_signal()

	if not has_failures():
		print("ShippingContractRepository: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("ShippingContractRepositoryTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "SCRMap"]
	)
	_origin_id = "%s_origin" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, 0, 0, 'Origin', 3)
	""", [_origin_id, _campaign_id, _map_id])
	_dest_id = "%s_dest" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, 5, 5, 'Destination', 3)
	""", [_dest_id, _campaign_id, _map_id])
	_party_id = "%s_party" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'P')",
		[_party_id, _campaign_id])
	# PC who will receive contract fees.
	_pc_id = "%s_pc" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'PCCarrier', 'pc')
	""", [_pc_id, _campaign_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[_party_id, _pc_id])


func _next_id() -> String:
	_suffix += 1
	return "scr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _accept_default(deadline_day: int = 100, fee: int = 500) -> String:
	return ShippingContractRepository.accept_contract(
		_party_id, _origin_id, _dest_id,
		"silk", 5, fee, deadline_day, 10)


# ---------------------------------------------------------------------------
# Accept
# ---------------------------------------------------------------------------

func test_accept_contract_creates_row() -> void:
	var cid: String = _accept_default()
	check(not cid.is_empty(), "accept_contract returns non-empty id")
	var contract: Dictionary = ShippingContractRepository.get_contract(cid)
	check(str(contract.get("accepted_by_party_id", "")) == _party_id, "party_id set")
	check(str(contract.get("origin_settlement_id", "")) == _origin_id, "origin set")
	check(str(contract.get("destination_settlement_id", "")) == _dest_id, "destination set")
	check(str(contract.get("merchandise_type", "")) == "silk", "merchandise_type set")
	check(int(contract.get("loads_count", 0)) == 5, "loads_count = 5")
	check(int(contract.get("fee_gp", 0)) == 500, "fee_gp = 500")
	check(int(contract.get("deadline_calendar_day", 0)) == 100, "deadline = 100")
	check(str(contract.get("status", "")) == "accepted", "status = 'accepted'")
	check(int(contract.get("accepted_at_calendar_day", 0)) == 10, "accepted_at = 10")


func test_accept_contract_emits_signal() -> void:
	var received := {"emitted": false, "contract_id": "", "party_id": "", "fee": -1}
	var cb: Callable = func(cid: String, pid: String, fee: int) -> void:
		received["emitted"] = true
		received["contract_id"] = cid
		received["party_id"] = pid
		received["fee"] = fee
	EventBus.shipping_contract_accepted.connect(cb)
	var cid: String = _accept_default(50, 750)
	EventBus.shipping_contract_accepted.disconnect(cb)
	check(bool(received["emitted"]), "shipping_contract_accepted fires")
	check(str(received["contract_id"]) == cid, "signal payload contract_id matches")
	check(str(received["party_id"]) == _party_id, "signal payload party_id matches")
	check(int(received["fee"]) == 750, "signal payload fee = 750")


# ---------------------------------------------------------------------------
# mark_in_transit
# ---------------------------------------------------------------------------

func test_mark_in_transit_transitions() -> void:
	var cid: String = _accept_default()
	check(ShippingContractRepository.mark_in_transit(cid), "transition succeeds")
	check(str(ShippingContractRepository.get_contract(cid).get("status", "")) == "in_transit",
		"status = 'in_transit' after transition")


func test_mark_in_transit_rejects_non_accepted() -> void:
	var cid: String = _accept_default()
	ShippingContractRepository.cancel(cid)
	check(not ShippingContractRepository.mark_in_transit(cid),
		"cancelled contract cannot transition to in_transit")


# ---------------------------------------------------------------------------
# Deliver — on time
# ---------------------------------------------------------------------------

func test_deliver_on_time_credits_fee_and_deletes_cargo() -> void:
	# Seed: contract with fee 1000 gp, deadline day 100, delivered on day 50.
	# Spawn the linked cargo_hold row.
	var cid: String = _accept_default(100, 1000)
	# Need a carrier (draft_vehicle) to host the cargo.
	var vid: String = "%s_wagon" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name)
		VALUES (?, ?, ?, 'wagon', 'CarrierWagon')
	""", [vid, _campaign_id, _party_id])
	var cargo_id: String = CargoHoldRepository.insert_shipping_contract_load(
		vid, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 5, cid, _origin_id, 10)
	check(not cargo_id.is_empty(), "cargo_hold linked to contract")
	# Pre-delivery PC wealth.
	var wealth_before: int = CampaignRepository.get_character_wealth_cp(_pc_id)
	var result: Dictionary = ShippingContractRepository.deliver(cid, 50)
	check(bool(result.get("success", false)), "on-time deliver returns success=true")
	check(int(result.get("fee_paid_gp", 0)) == 1000, "fee_paid_gp = 1000")
	check(not bool(result.get("deadline_missed", true)), "deadline_missed = false")
	# Wealth credited by 1000 gp = 100000 cp.
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(_pc_id)
	check(wealth_after - wealth_before == 100000,
		"PC wealth increased by 100000 cp, got delta %d" % (wealth_after - wealth_before))
	# Status updated.
	check(str(ShippingContractRepository.get_contract(cid).get("status", "")) == "delivered",
		"status = 'delivered'")
	# Cargo row deleted.
	check(CargoHoldRepository.get_cargo_hold(cargo_id).is_empty(),
		"linked cargo_hold deleted on delivery")


func test_deliver_after_deadline_pays_nothing() -> void:
	var cid: String = _accept_default(20, 1000)  # deadline day 20
	# Spawn linked cargo.
	var vid: String = "%s_wagon_late" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO draft_vehicles (id, campaign_id, party_id, item_key, name)
		VALUES (?, ?, ?, 'wagon', 'LateWagon')
	""", [vid, _campaign_id, _party_id])
	var cargo_id: String = CargoHoldRepository.insert_shipping_contract_load(
		vid, CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
		"silk", 5, cid, _origin_id, 10)
	var wealth_before: int = CampaignRepository.get_character_wealth_cp(_pc_id)
	var result: Dictionary = ShippingContractRepository.deliver(cid, 50)  # late!
	check(bool(result.get("success", false)), "late delivery still returns success=true (function ran)")
	check(int(result.get("fee_paid_gp", 0)) == 0, "fee_paid_gp = 0 (v1 no partial payment)")
	check(bool(result.get("deadline_missed", false)), "deadline_missed = true")
	# Wealth UNCHANGED.
	var wealth_after: int = CampaignRepository.get_character_wealth_cp(_pc_id)
	check(wealth_after == wealth_before, "PC wealth unchanged on late delivery")
	# Status flipped to 'failed_deadline'.
	check(str(ShippingContractRepository.get_contract(cid).get("status", "")) == "failed_deadline",
		"status = 'failed_deadline'")
	# Cargo NOT deleted on late delivery (player can still sell elsewhere).
	check(not CargoHoldRepository.get_cargo_hold(cargo_id).is_empty(),
		"linked cargo_hold preserved on late delivery (player keeps goods)")


func test_deliver_emits_signal_with_correct_payload() -> void:
	# On-time path: deadline_missed=false, fee_paid_gp = fee.
	var cid: String = _accept_default(100, 600)
	var on_time := {"emitted": false, "fee": -1, "missed": null}
	var cb_ontime: Callable = func(c_id: String, fee: int, missed: bool) -> void:
		if c_id == cid:
			on_time["emitted"] = true
			on_time["fee"] = fee
			on_time["missed"] = missed
	EventBus.shipping_contract_delivered.connect(cb_ontime)
	ShippingContractRepository.deliver(cid, 50)
	EventBus.shipping_contract_delivered.disconnect(cb_ontime)
	check(bool(on_time["emitted"]), "on-time deliver fires signal")
	check(int(on_time["fee"]) == 600, "signal fee = 600")
	check(on_time["missed"] == false, "signal deadline_missed = false")

	# Late path: deadline_missed=true, fee_paid_gp = 0.
	var cid_late: String = _accept_default(20, 600)
	var late := {"emitted": false, "fee": -1, "missed": null}
	var cb_late: Callable = func(c_id: String, fee: int, missed: bool) -> void:
		if c_id == cid_late:
			late["emitted"] = true
			late["fee"] = fee
			late["missed"] = missed
	EventBus.shipping_contract_delivered.connect(cb_late)
	ShippingContractRepository.deliver(cid_late, 50)
	EventBus.shipping_contract_delivered.disconnect(cb_late)
	check(bool(late["emitted"]), "late deliver fires signal too")
	check(int(late["fee"]) == 0, "late signal fee = 0")
	check(late["missed"] == true, "late signal deadline_missed = true")


func test_deliver_rejects_terminal_contract() -> void:
	var cid: String = _accept_default(100, 500)
	ShippingContractRepository.cancel(cid)
	var result: Dictionary = ShippingContractRepository.deliver(cid, 50)
	check(not bool(result.get("success", true)), "deliver on cancelled contract fails")
	check(str(result.get("error", "")) == "contract_not_active",
		"error = 'contract_not_active'")


# ---------------------------------------------------------------------------
# list_active_for_party
# ---------------------------------------------------------------------------

func test_list_active_for_party() -> void:
	# Create a fresh party so we don't pick up other tests' contracts.
	var pid: String = "%s_listparty" % _next_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, 'ListParty')",
		[pid, _campaign_id])
	var c_accepted: String = ShippingContractRepository.accept_contract(
		pid, _origin_id, _dest_id, "salt", 5, 100, 100, 10)
	var c_in_transit: String = ShippingContractRepository.accept_contract(
		pid, _origin_id, _dest_id, "silk", 3, 600, 80, 10)
	ShippingContractRepository.mark_in_transit(c_in_transit)
	var c_delivered: String = ShippingContractRepository.accept_contract(
		pid, _origin_id, _dest_id, "spices", 2, 1600, 60, 10)
	ShippingContractRepository.deliver(c_delivered, 50)
	var c_cancelled: String = ShippingContractRepository.accept_contract(
		pid, _origin_id, _dest_id, "wood_common", 4, 200, 40, 10)
	ShippingContractRepository.cancel(c_cancelled)
	# Active list should be {accepted, in_transit} only.
	var active: Array = ShippingContractRepository.list_active_for_party(pid)
	check(active.size() == 2, "active list has 2 contracts (accepted + in_transit), got %d" % active.size())
	var ids: Dictionary = {}
	for c in active:
		ids[str((c as Dictionary).get("id", ""))] = str((c as Dictionary).get("status", ""))
	check(ids.has(c_accepted) and ids.has(c_in_transit), "active contracts present")
	check(not ids.has(c_delivered), "delivered excluded")
	check(not ids.has(c_cancelled), "cancelled excluded")
	# Sorted by deadline ASC: in_transit (deadline 80) comes before accepted (deadline 100).
	if active.size() == 2:
		check(str((active[0] as Dictionary).get("id", "")) == c_in_transit,
			"earliest deadline first (in_transit at day 80)")


# ---------------------------------------------------------------------------
# cancel
# ---------------------------------------------------------------------------

func test_cancel_sets_status() -> void:
	var cid: String = _accept_default()
	check(ShippingContractRepository.cancel(cid), "cancel returns true")
	check(str(ShippingContractRepository.get_contract(cid).get("status", "")) == "cancelled",
		"status = 'cancelled'")


func test_cancel_rejects_terminal() -> void:
	var cid: String = _accept_default()
	ShippingContractRepository.cancel(cid)
	check(not ShippingContractRepository.cancel(cid),
		"second cancel returns false (already cancelled)")
	# Also: a delivered contract can't be cancelled.
	var cid2: String = _accept_default(100, 500)
	ShippingContractRepository.deliver(cid2, 50)
	check(not ShippingContractRepository.cancel(cid2),
		"cancel on delivered contract returns false")


func test_cancel_emits_signal() -> void:
	var cid: String = _accept_default()
	var received := {"emitted": false, "contract_id": "", "reason": ""}
	var cb: Callable = func(c_id: String, reason: String) -> void:
		if c_id == cid:
			received["emitted"] = true
			received["contract_id"] = c_id
			received["reason"] = reason
	EventBus.shipping_contract_failed.connect(cb)
	ShippingContractRepository.cancel(cid)
	EventBus.shipping_contract_failed.disconnect(cb)
	check(bool(received["emitted"]), "shipping_contract_failed fires on cancel")
	check(str(received["reason"]) == "cancelled", "signal reason = 'cancelled'")
