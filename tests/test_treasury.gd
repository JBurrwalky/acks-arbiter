extends "res://tests/test_suite_base.gd"

## Unit tests for DomainTreasury — Phase 2 acceptance gate.
##
## Covers the [RESOLVED 2026-05-06] treasury-access rule matrix:
##   (a) domain-level uses (deposit/withdraw with category=expense) are free
##   (b) personal-wallet transfers gate on stronghold presence
##   (c) inter-stronghold transfers go through the route signal
## Plus the [RAW PATCH] Land Improvement investment line at 25,000 gp/+1
## per `acore_axioms` §land_improvement L207-215.


var _campaign_id: String = ""
var _domain_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_initial_balance_is_zero()
	test_deposit_writes_ledger_and_emits_signal()
	test_withdraw_decrements_balance()
	test_withdraw_insufficient_funds()
	test_withdraw_zero_amount_rejected()
	test_withdraw_to_personal_blocked_when_no_strongholds()
	test_deposit_from_personal_blocked_when_no_strongholds()
	test_invest_land_improvement_succeeds()
	test_invest_land_improvement_insufficient_funds()
	test_invest_land_improvement_caps_at_plus_three()
	test_invest_land_improvement_caps_at_land_value_nine()
	test_invest_land_improvement_invalid_hex()
	test_set_auto_pay_policy_persists()
	test_get_auto_pay_policies_default_empty()
	test_inter_stronghold_transfer_emits_route()
	if not has_failures():
		print("DomainTreasury: all tests passed.")


# ----- Setup -----

func _setup_campaign() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Domain Treasury", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Treasury Test Domain",
		"territory_type": "borderlands",
	})
	check(not _domain_id.is_empty(), "domain created")


func _make_fresh_domain(name: String) -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": name,
		"territory_type": "borderlands",
	})


# ----- Direct deposit / withdraw -----

func test_initial_balance_is_zero() -> void:
	var d := _make_fresh_domain("Initial Balance")
	check(DomainTreasury.get_balance(d) == 0,
		"initial balance = 0, got %d" % DomainTreasury.get_balance(d))


func test_deposit_writes_ledger_and_emits_signal() -> void:
	var d := _make_fresh_domain("Deposit Test")
	var fired: Array = []
	var listener := func(did: String, old_gp: int, new_gp: int):
		if did == d:
			fired.append([old_gp, new_gp])
	EventBus.domain_treasury_changed.connect(listener)
	var result := DomainTreasury.deposit(d, 500, 1, "revenue", "test", "test deposit")
	EventBus.domain_treasury_changed.disconnect(listener)
	check(result["ok"], "deposit ok")
	check(result["new_balance"] == 500, "new_balance = 500, got %d" % result["new_balance"])
	check(fired.size() == 1, "signal fired once, got %d" % fired.size())
	check(int(fired[0][0]) == 0 and int(fired[0][1]) == 500,
		"signal payload [0, 500], got %s" % str(fired[0]))
	# Ledger entry written.
	var entries := CampaignRepository.list_ledger_entries(d)
	check(entries.size() == 1, "1 ledger entry, got %d" % entries.size())
	check(int(entries[0]["cp_amount"]) == 500, "ledger cp_amount = 500")


func test_withdraw_decrements_balance() -> void:
	var d := _make_fresh_domain("Withdraw Test")
	DomainTreasury.deposit(d, 1000, 1)
	var result := DomainTreasury.withdraw(d, 300, 2, "expense", "test", "test withdraw")
	check(result["ok"], "withdraw ok")
	check(result["new_balance"] == 700, "balance = 700, got %d" % result["new_balance"])


func test_withdraw_insufficient_funds() -> void:
	var d := _make_fresh_domain("Insufficient Funds")
	DomainTreasury.deposit(d, 100, 1)
	var result := DomainTreasury.withdraw(d, 500, 2)
	check(not result["ok"], "withdraw blocked")
	check(String(result["reason"]) == DomainTreasury.REASON_INSUFFICIENT_FUNDS,
		"reason = insufficient_funds, got %s" % result["reason"])
	check(result["new_balance"] == 100, "balance unchanged at 100")


func test_withdraw_zero_amount_rejected() -> void:
	var d := _make_fresh_domain("Zero Amount")
	DomainTreasury.deposit(d, 1000, 1)
	var result := DomainTreasury.withdraw(d, 0, 2)
	check(not result["ok"], "withdraw 0 rejected")
	check(String(result["reason"]) == DomainTreasury.REASON_AMOUNT_INVALID,
		"reason = amount_invalid")


# ----- Personal-wallet gating -----

func test_withdraw_to_personal_blocked_when_no_strongholds() -> void:
	# Domain has no strongholds — is_character_at_stronghold returns false by
	# spec (no strongholds => no place to be present).
	var d := _make_fresh_domain("No Strongholds")
	DomainTreasury.deposit(d, 5000, 1)
	var fired: Array = []
	var listener := func(did: String, char_id: String, reason: String):
		if did == d:
			fired.append([char_id, reason])
	EventBus.domain_treasury_transfer_blocked.connect(listener)
	var result := DomainTreasury.withdraw_to_personal(d, "char_x", 500, 2)
	EventBus.domain_treasury_transfer_blocked.disconnect(listener)
	check(not result["ok"], "blocked when no strongholds")
	check(String(result["reason"]) == DomainTreasury.REASON_NOT_AT_STRONGHOLD,
		"reason = not_at_stronghold, got %s" % result["reason"])
	check(fired.size() == 1, "blocked signal emitted")


func test_deposit_from_personal_blocked_when_no_strongholds() -> void:
	var d := _make_fresh_domain("No Strongholds Dep")
	var result := DomainTreasury.deposit_from_personal(d, "char_x", 500, 2)
	check(not result["ok"], "blocked when no strongholds")
	check(String(result["reason"]) == DomainTreasury.REASON_NOT_AT_STRONGHOLD,
		"reason = not_at_stronghold")


# ----- Land Improvement -----

func test_invest_land_improvement_succeeds() -> void:
	var d := _make_fresh_domain("Land Improvement OK")
	# Add a hex at land_value=5, no improvement yet.
	CampaignRepository.add_domain_hex({
		"domain_id": d, "hex_q": 0, "hex_r": 0,
		"land_value": 5, "land_improvement_level": 0,
	})
	# Seed 30,000 gp = 3,000,000 cp. Improvement costs 2,500,000 cp; expect
	# 500,000 cp left.
	DomainTreasury.deposit(d, 3_000_000, 1)
	var fired: Array = []
	var listener := func(did: String, q: int, r: int, new_value: int, count: int):
		if did == d:
			fired.append([q, r, new_value, count])
	EventBus.land_value_improved.connect(listener)
	var result := DomainTreasury.invest_land_improvement(d, 0, 0, 2)
	EventBus.land_value_improved.disconnect(listener)
	check(result["ok"], "land improvement ok, reason=%s" % result.get("reason", "?"))
	check(int(result["new_balance"]) == 500_000,
		"3,000,000 - 2,500,000 = 500,000 cp left, got %d" % int(result["new_balance"]))
	check(int(result["new_land_value"]) == 6,
		"land_value 5 -> 6, got %d" % int(result["new_land_value"]))
	check(int(result["new_improvement_count"]) == 1,
		"improvement count 0 -> 1, got %d" % int(result["new_improvement_count"]))
	check(fired.size() == 1, "land_value_improved fired")


func test_invest_land_improvement_insufficient_funds() -> void:
	var d := _make_fresh_domain("LI Insufficient")
	CampaignRepository.add_domain_hex({
		"domain_id": d, "hex_q": 0, "hex_r": 0, "land_value": 5,
	})
	# 1,000,000 cp = 10,000 gp; below the 2,500,000 cp threshold.
	DomainTreasury.deposit(d, 1_000_000, 1)
	var result := DomainTreasury.invest_land_improvement(d, 0, 0, 2)
	check(not result["ok"], "blocked at 1,000,000 cp (10,000 gp)")
	check(String(result["reason"]) == DomainTreasury.REASON_INSUFFICIENT_FUNDS,
		"reason = insufficient_funds")


func test_invest_land_improvement_caps_at_plus_three() -> void:
	var d := _make_fresh_domain("LI Cap +3")
	CampaignRepository.add_domain_hex({
		"domain_id": d, "hex_q": 0, "hex_r": 0,
		"land_value": 5, "land_improvement_level": 3,  # already at +3
	})
	DomainTreasury.deposit(d, 3_000_000, 1)
	var result := DomainTreasury.invest_land_improvement(d, 0, 0, 2)
	check(not result["ok"], "blocked at +3 cap")
	check(String(result["reason"]) == DomainTreasury.REASON_LAND_IMPROVEMENT_REJECTED,
		"reason = land_improvement_rejected, got %s" % result["reason"])


func test_invest_land_improvement_caps_at_land_value_nine() -> void:
	var d := _make_fresh_domain("LI Cap LV9")
	# land_value 9 already; +1 would push to 10 which exceeds cap.
	CampaignRepository.add_domain_hex({
		"domain_id": d, "hex_q": 0, "hex_r": 0,
		"land_value": 9, "land_improvement_level": 0,
	})
	DomainTreasury.deposit(d, 3_000_000, 1)
	var result := DomainTreasury.invest_land_improvement(d, 0, 0, 2)
	check(not result["ok"], "blocked at land_value 9 cap")


func test_invest_land_improvement_invalid_hex() -> void:
	var d := _make_fresh_domain("LI Bad Hex")
	DomainTreasury.deposit(d, 3_000_000, 1)
	var result := DomainTreasury.invest_land_improvement(d, 99, 99, 2)
	check(not result["ok"], "blocked when hex not in domain")
	check(String(result["reason"]) == DomainTreasury.REASON_HEX_NOT_FOUND,
		"reason = hex_not_found, got %s" % result["reason"])


# ----- Auto-pay policies -----

func test_set_auto_pay_policy_persists() -> void:
	var d := _make_fresh_domain("Auto-pay Persist")
	var ok := DomainTreasury.set_auto_pay_policy(d, {"garrison": true, "tithe": false})
	check(ok, "set_auto_pay_policy ok")
	var loaded := DomainTreasury.get_auto_pay_policies(d)
	check(bool(loaded.get("garrison", false)), "garrison toggle persisted")
	check(not bool(loaded.get("tithe", true)), "tithe toggle persisted")


func test_get_auto_pay_policies_default_empty() -> void:
	var d := _make_fresh_domain("Auto-pay Default")
	var loaded := DomainTreasury.get_auto_pay_policies(d)
	check(loaded.is_empty(), "default auto_pay_policies = {} for new domain")


# ----- Inter-stronghold route -----

func test_inter_stronghold_transfer_emits_route() -> void:
	var d := _make_fresh_domain("Route Test")
	DomainTreasury.deposit(d, 5000, 1)
	# Create two strongholds (Phase 1 stronghold table has flexible status; we
	# can insert pre-completed ones for the route's purposes).
	var src_id := CampaignRepository.create_stronghold({
		"domain_id": d,
		"archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"structure_type": "keep",
		"cp_value": 2250000,  # Migration 116: 22500 gp × 100.
		"completion_pct": 100,
		"status": "completed",
		"location_map_id": "map_a",
		"location_hex_q": 0,
		"location_hex_r": 0,
	})
	var dst_id := CampaignRepository.create_stronghold({
		"domain_id": d,
		"archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"structure_type": "keep",
		"cp_value": 2250000,  # Migration 116: 22500 gp × 100.
		"completion_pct": 100,
		"status": "completed",
		"location_map_id": "map_a",
		"location_hex_q": 5,
		"location_hex_r": 5,
	})
	check(not src_id.is_empty() and not dst_id.is_empty(),
		"strongholds created")
	var fired: Array = []
	var listener := func(did: String, _src: String, _dst: String, gp: int, _carrier: String):
		if did == d:
			fired.append(gp)
	EventBus.domain_treasury_route_started.connect(listener)
	var result := DomainTreasury.transfer_between_strongholds(
		d, src_id, dst_id, 1500, "char_carrier", 2)
	EventBus.domain_treasury_route_started.disconnect(listener)
	check(result["ok"], "transfer ok, errors=%s" % result.get("reason", "?"))
	check(fired.size() == 1, "route signal fired")
	check(int(fired[0]) == 1500, "route gp = 1500")
	# Source treasury debited immediately (carrier left with the gp).
	check(DomainTreasury.get_balance(d) == 3500,
		"5000 - 1500 = 3500, got %d" % DomainTreasury.get_balance(d))
