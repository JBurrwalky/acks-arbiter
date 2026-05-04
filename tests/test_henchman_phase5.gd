extends "res://tests/test_suite_base.gd"

## Phase 5 of the henchman closure plan: tests for the lifecycle handlers
## and resolvers (calamity wiring, unpaid-wages → loyalty check,
## treasure-share adjustment, pay-back-wages).
##
## All tests use FakeRepo + FakeWallet — no DB. The flakiness pattern that
## affects DB-backed suites doesn't touch this one.


# ---------------------------------------------------------------------------
# FakeRepo + FakeWallet — captures all DB-side mutations without real SQLite
# ---------------------------------------------------------------------------

class FakeRepo:
	extends RefCounted

	var characters: Dictionary = {}
	var states: Dictionary = {}
	var coin_added_cp: Dictionary = {}
	var party_member_remove_calls: Array = []
	var loyalty_check_calls: Array = []  # captures (character_id, trigger)
	var loyalty_check_result_outcome: String = "loyal"  # what trigger_loyalty_check should report

	var db: FakeDB = FakeDB.new()

	class FakeDB:
		extends RefCounted
		var query_result: Array = []
		var captured_sql: Array = []
		var captured_bindings: Array = []
		func query_with_bindings(sql: String, bindings: Array) -> bool:
			captured_sql.append(sql)
			captured_bindings.append(bindings)
			# For SELECT party_id queries, return a default party.
			if sql.contains("SELECT party_id FROM party_members"):
				query_result = [{"party_id": "party1"}]
			else:
				query_result = []
			return true

	func get_character(id: String) -> Dictionary:
		return characters.get(id, {})

	func get_henchman_state(character_id: String) -> Dictionary:
		return states.get(character_id, {})

	func upsert_henchman_state(character_id: String, state: Dictionary) -> bool:
		states[character_id] = state.duplicate()
		return true

	func add_coins_cp(character_id: String, amount: int) -> void:
		coin_added_cp[character_id] = int(coin_added_cp.get(character_id, 0)) + amount

	func remove_party_member(party_id: String, character_id: String) -> bool:
		party_member_remove_calls.append([party_id, character_id])
		return true


class FakeWallet:
	extends RefCounted
	var paid_cp: int = 0
	var allow_pay: bool = true
	func pay(cost_cp: int, _party_id: String, _employer_id: String) -> Dictionary:
		if not allow_pay:
			return {"ok": false, "message": "insufficient funds"}
		paid_cp += cost_cp
		return {"ok": true}


class FakeLifecycle:
	extends HenchmanLifecycleManager
	var fake_wallet: FakeWallet
	var trigger_calls: Array = []
	func _get_party_wallet():
		return fake_wallet
	func trigger_loyalty_check(character_id: String, trigger: String, _dice = null) -> Dictionary:
		# Capture the call without doing the actual roll.
		trigger_calls.append([character_id, trigger])
		return {"result": "loyal", "roll": 9, "modifier": 0, "total": 9}


func run_all_tests() -> void:
	test_unpaid_wages_triggers_loyalty_check_at_two_months()
	test_unpaid_wages_does_not_trigger_at_one_month()
	test_pay_back_wages_resets_unpaid_months()
	test_pay_back_wages_no_owed_returns_zero()
	test_pay_back_wages_insufficient_funds_returns_false()
	test_adjust_treatment_updates_share()
	test_adjust_treatment_bonus_stamps_plus_one_morale()
	test_adjust_treatment_clamps_share()
	test_adjust_treatment_insufficient_funds_returns_false()
	if not has_failures():
		print("HenchmanPhase5: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_lifecycle(unpaid_months: int = 0,
		monthly_wage: int = 25,
		morale: int = 0,
		share: int = 15,
		allow_pay: bool = true) -> FakeLifecycle:
	var repo := FakeRepo.new()
	repo.characters["h1"] = {
		"id": "h1",
		"name": "Test Henchman",
		"character_type": "henchman",
		"employer_id": "patron1",
		"wage_gp_per_month": monthly_wage,
	}
	repo.states["h1"] = {
		"morale_score": morale,
		"treasure_share_percent": share,
		"unpaid_months": unpaid_months,
		"is_grudging": 0,
		"is_fanatic": 0,
	}
	var lifecycle := FakeLifecycle.new(repo, null, null)
	var wallet := FakeWallet.new()
	wallet.allow_pay = allow_pay
	lifecycle.fake_wallet = wallet
	return lifecycle


# ---------------------------------------------------------------------------
# Unpaid wages → loyalty check
# ---------------------------------------------------------------------------

func test_unpaid_wages_triggers_loyalty_check_at_two_months() -> void:
	# Start with unpaid_months=1, increment → 2 → loyalty check fires.
	var lifecycle := _make_lifecycle(1, 25)
	lifecycle._increment_unpaid_months("h1")
	check(lifecycle.trigger_calls.size() == 1,
		"loyalty check should fire once when unpaid_months reaches 2")
	check(lifecycle.trigger_calls[0][0] == "h1",
		"loyalty check should target the henchman")
	check(lifecycle.trigger_calls[0][1] == "unpaid_wages",
		"loyalty check trigger should be 'unpaid_wages', got %s" % lifecycle.trigger_calls[0][1])


func test_unpaid_wages_does_not_trigger_at_one_month() -> void:
	# Start with unpaid_months=0, increment → 1 → no check.
	var lifecycle := _make_lifecycle(0, 25)
	lifecycle._increment_unpaid_months("h1")
	check(lifecycle.trigger_calls.is_empty(),
		"loyalty check should NOT fire at 1 unpaid month")


# ---------------------------------------------------------------------------
# Pay back wages
# ---------------------------------------------------------------------------

func test_pay_back_wages_resets_unpaid_months() -> void:
	# 3 months × 25 gp = 75 gp owed.
	var lifecycle := _make_lifecycle(3, 25)
	var result: Dictionary = lifecycle.pay_back_wages("h1")
	check(result.get("ok", false), "pay_back_wages should succeed")
	check(int(result.get("paid_gp", 0)) == 75,
		"paid_gp should be unpaid_months × wage; got %d" % int(result.get("paid_gp", 0)))
	check(lifecycle.fake_wallet.paid_cp == 7500,
		"wallet should be charged 7500 cp; got %d" % lifecycle.fake_wallet.paid_cp)
	# unpaid_months reset.
	var state: Dictionary = lifecycle._repo.get_henchman_state("h1")
	check(int(state.get("unpaid_months", -1)) == 0,
		"unpaid_months should reset to 0")
	# Henchman received the wages.
	check(int(lifecycle._repo.coin_added_cp.get("h1", 0)) == 7500,
		"henchman should receive 7500 cp into purse")


func test_pay_back_wages_no_owed_returns_zero() -> void:
	var lifecycle := _make_lifecycle(0, 25)
	var result: Dictionary = lifecycle.pay_back_wages("h1")
	check(result.get("ok", false), "no-debt pay_back should succeed (no-op)")
	check(int(result.get("paid_gp", 0)) == 0,
		"paid_gp should be 0 when no debt")
	check(lifecycle.fake_wallet.paid_cp == 0,
		"wallet not charged when no debt")


func test_pay_back_wages_insufficient_funds_returns_false() -> void:
	var lifecycle := _make_lifecycle(2, 25, 0, 15, false)
	var result: Dictionary = lifecycle.pay_back_wages("h1")
	check(not result.get("ok", false),
		"pay_back_wages should fail on insufficient funds")
	# unpaid_months should NOT be reset.
	var state: Dictionary = lifecycle._repo.get_henchman_state("h1")
	check(int(state.get("unpaid_months", -1)) == 2,
		"unpaid_months must NOT reset on failure")


# ---------------------------------------------------------------------------
# Adjust treatment
# ---------------------------------------------------------------------------

func test_adjust_treatment_updates_share() -> void:
	var lifecycle := _make_lifecycle(0, 25, 0, 15)
	var result: Dictionary = lifecycle.adjust_treatment("h1", 25, 0)
	check(result.get("ok", false), "adjust_treatment should succeed")
	var state: Dictionary = lifecycle._repo.get_henchman_state("h1")
	check(int(state.get("treasure_share_percent", -1)) == 25,
		"treasure_share_percent should update to 25; got %d" % int(state.get("treasure_share_percent", -1)))
	# No bonus → no morale change.
	check(int(state.get("morale_score", -99)) == 0,
		"morale_score should not change without bonus")


func test_adjust_treatment_bonus_stamps_plus_one_morale() -> void:
	var lifecycle := _make_lifecycle(0, 25, 0, 15)
	lifecycle.adjust_treatment("h1", 20, 50)
	var state: Dictionary = lifecycle._repo.get_henchman_state("h1")
	check(int(state.get("morale_score", -99)) == 1,
		"bonus > 0 should stamp +1 morale; got %d" % int(state.get("morale_score", -99)))
	check(lifecycle.fake_wallet.paid_cp == 5000,
		"wallet should be charged 50 gp = 5000 cp")
	# Henchman receives the bonus into purse.
	check(int(lifecycle._repo.coin_added_cp.get("h1", 0)) == 5000,
		"henchman should receive bonus into purse")


func test_adjust_treatment_clamps_share() -> void:
	var lifecycle := _make_lifecycle(0, 25, 0, 15)
	lifecycle.adjust_treatment("h1", 200, 0)
	var state: Dictionary = lifecycle._repo.get_henchman_state("h1")
	check(int(state.get("treasure_share_percent", -1)) == 100,
		"share over 100 should clamp to 100")
	lifecycle.adjust_treatment("h1", -50, 0)
	state = lifecycle._repo.get_henchman_state("h1")
	check(int(state.get("treasure_share_percent", -1)) == 0,
		"negative share should clamp to 0")


func test_adjust_treatment_insufficient_funds_returns_false() -> void:
	var lifecycle := _make_lifecycle(0, 25, 0, 15, false)
	var result: Dictionary = lifecycle.adjust_treatment("h1", 30, 100)
	check(not result.get("ok", false),
		"insufficient funds should yield false")
	# Share update should NOT have landed (atomic with the bonus payment).
	var state: Dictionary = lifecycle._repo.get_henchman_state("h1")
	check(int(state.get("treasure_share_percent", -1)) == 15,
		"share should remain 15 on bonus-payment failure; got %d" % int(state.get("treasure_share_percent", -1)))
