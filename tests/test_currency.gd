extends "res://tests/test_suite_base.gd"

## Unit tests for the Currency class (denomination constants, math, formatting,
## change-making logic). Run via test_runner.tscn.


func run_all_tests() -> void:
	test_denomination_count()
	test_coin_key_to_cp_value()
	test_is_coin()
	test_coins_to_cp_all_denominations()
	test_coins_to_cp_empty()
	test_cp_to_coins_exact_pp()
	test_cp_to_coins_mixed()
	test_cp_to_coins_small()
	test_format_cost_gp()
	test_format_cost_mixed()
	test_format_cost_zero()
	test_format_cost_with_ep_pp()
	test_format_wealth_mixed()
	test_format_wealth_empty()
	test_deduction_exact_amount()
	test_deduction_smallest_first()
	test_deduction_makes_change()
	test_deduction_insufficient_funds()
	test_deduction_all_platinum()
	test_deduction_from_gp_needs_change()
	if not has_failures():
		print("Currency: all tests passed.")


# ---------------------------------------------------------------------------
# Denomination constants
# ---------------------------------------------------------------------------

func test_denomination_count() -> void:
	check(Currency.DENOMINATIONS.size() == 5, "expected 5 denominations, got %d" % Currency.DENOMINATIONS.size())
	check(Currency.COIN_KEYS.size() == 5, "expected 5 coin keys")
	print("  denomination_count: OK")


func test_coin_key_to_cp_value() -> void:
	check(Currency.coin_key_to_cp_value("coins_pp") == 1000, "pp should be 1000cp")
	check(Currency.coin_key_to_cp_value("coins_ep") == 500, "ep should be 500cp")
	check(Currency.coin_key_to_cp_value("coins_gp") == 100, "gp should be 100cp")
	check(Currency.coin_key_to_cp_value("coins_sp") == 10, "sp should be 10cp")
	check(Currency.coin_key_to_cp_value("coins_cp") == 1, "cp should be 1cp")
	check(Currency.coin_key_to_cp_value("coin_bogus") == 0, "unknown coin should be 0")
	print("  coin_key_to_cp_value: OK")


func test_is_coin() -> void:
	check(Currency.is_coin("coins_gp"), "coins_gp should be a coin")
	check(Currency.is_coin("coins_pp"), "coins_pp should be a coin")
	check(not Currency.is_coin("sword"), "sword should not be a coin")
	check(not Currency.is_coin(""), "empty string should not be a coin")
	print("  is_coin: OK")


# ---------------------------------------------------------------------------
# Wealth calculation
# ---------------------------------------------------------------------------

func test_coins_to_cp_all_denominations() -> void:
	var coins := {"coins_pp": 2, "coins_ep": 1, "coins_gp": 3, "coins_sp": 5, "coins_cp": 7}
	# 2*1000 + 1*500 + 3*100 + 5*10 + 7 = 2000 + 500 + 300 + 50 + 7 = 2857
	var total := Currency.coins_to_cp(coins)
	check(total == 2857, "expected 2857cp, got %d" % total)
	print("  coins_to_cp_all: OK")


func test_coins_to_cp_empty() -> void:
	var total := Currency.coins_to_cp({})
	check(total == 0, "empty coins should be 0cp, got %d" % total)
	print("  coins_to_cp_empty: OK")


func test_cp_to_coins_exact_pp() -> void:
	var coins := Currency.cp_to_coins(1000)
	check(coins.get("coins_pp", 0) == 1, "1000cp should be 1pp")
	check(coins.get("coins_gp", 0) == 0, "no gp remainder")
	print("  cp_to_coins_exact_pp: OK")


func test_cp_to_coins_mixed() -> void:
	# 2857cp = 2pp + 1ep + 3gp + 5sp + 7cp
	var coins := Currency.cp_to_coins(2857)
	check(coins.get("coins_pp", 0) == 2, "expected 2pp, got %d" % coins.get("coins_pp", 0))
	check(coins.get("coins_ep", 0) == 1, "expected 1ep, got %d" % coins.get("coins_ep", 0))
	check(coins.get("coins_gp", 0) == 3, "expected 3gp, got %d" % coins.get("coins_gp", 0))
	check(coins.get("coins_sp", 0) == 5, "expected 5sp, got %d" % coins.get("coins_sp", 0))
	check(coins.get("coins_cp", 0) == 7, "expected 7cp, got %d" % coins.get("coins_cp", 0))
	print("  cp_to_coins_mixed: OK")


func test_cp_to_coins_small() -> void:
	var coins := Currency.cp_to_coins(3)
	check(coins.get("coins_cp", 0) == 3, "3cp should yield 3 copper")
	check(not coins.has("coins_gp"), "no gold for 3cp")
	print("  cp_to_coins_small: OK")


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

func test_format_cost_gp() -> void:
	check(Currency.format_cost(1000) == "10gp", "1000cp should format as 10gp, got '%s'" % Currency.format_cost(1000))
	print("  format_cost_gp: OK")


func test_format_cost_mixed() -> void:
	# 1557cp = 1pp 5ep... wait, format_cost breaks down by denomination.
	# 1557cp = 1pp (1000) + 557 remaining. 557/500 = 1ep + 57 remaining. 57/100 = 0gp. 57/10 = 5sp + 7cp.
	check(Currency.format_cost(1557) == "1pp 1ep 5sp 7cp",
		"1557cp format_cost: got '%s'" % Currency.format_cost(1557))
	print("  format_cost_mixed: OK")


func test_format_cost_zero() -> void:
	check(Currency.format_cost(0) == "0cp", "0 should format as 0cp")
	print("  format_cost_zero: OK")


func test_format_cost_with_ep_pp() -> void:
	# 500cp = 1ep
	check(Currency.format_cost(500) == "1ep", "500cp = 1ep, got '%s'" % Currency.format_cost(500))
	# 1500cp = 1pp 1ep
	check(Currency.format_cost(1500) == "1pp 1ep", "1500cp = 1pp 1ep, got '%s'" % Currency.format_cost(1500))
	print("  format_cost_with_ep_pp: OK")


func test_format_wealth_mixed() -> void:
	var coins := {"coins_pp": 2, "coins_gp": 3, "coins_sp": 5}
	var result := Currency.format_wealth(coins)
	check(result == "2pp 3gp 5sp", "format_wealth: expected '2pp 3gp 5sp', got '%s'" % result)
	print("  format_wealth_mixed: OK")


func test_format_wealth_empty() -> void:
	check(Currency.format_wealth({}) == "0cp", "empty wealth should show 0cp")
	print("  format_wealth_empty: OK")


# ---------------------------------------------------------------------------
# Change-making (compute_deduction)
# ---------------------------------------------------------------------------

func test_deduction_exact_amount() -> void:
	# Exact: 5gp = 500cp. Have exactly 5gp.
	var coins := {"coins_gp": 5}
	var result := Currency.compute_deduction(coins, 500)
	check(result["success"], "should succeed with exact amount")
	var new_coins: Dictionary = result["new_coins"]
	check(new_coins.get("coins_gp", 0) == 0, "should have 0gp left, got %d" % new_coins.get("coins_gp", 0))
	print("  deduction_exact: OK")


func test_deduction_smallest_first() -> void:
	# Have: 3gp (300cp) + 5sp (50cp) + 10cp = 360cp total.
	# Deduct 15cp. Should spend 10cp + 5cp from sp change.
	var coins := {"coins_gp": 3, "coins_sp": 5, "coins_cp": 10}
	var result := Currency.compute_deduction(coins, 15)
	check(result["success"], "should succeed")
	var new_coins: Dictionary = result["new_coins"]
	# 10cp consumed, then need 5cp more. 5sp available, spend 0.5sp which means
	# spend 1sp (10cp) and get 5cp change.
	# Total: 3gp, 4sp, 5cp
	check(new_coins.get("coins_gp", 0) == 3, "gp unchanged: got %d" % new_coins.get("coins_gp", 0))
	check(new_coins.get("coins_sp", 0) == 4, "sp: expected 4, got %d" % new_coins.get("coins_sp", 0))
	check(new_coins.get("coins_cp", 0) == 5, "cp: expected 5, got %d" % new_coins.get("coins_cp", 0))
	print("  deduction_smallest_first: OK")


func test_deduction_makes_change() -> void:
	# Have: 1gp only (100cp). Deduct 3cp. Should break 1gp into change.
	var coins := {"coins_gp": 1}
	var result := Currency.compute_deduction(coins, 3)
	check(result["success"], "should succeed")
	var new_coins: Dictionary = result["new_coins"]
	# 100cp - 3cp = 97cp change = 0pp 0ep 0gp 9sp 7cp
	check(new_coins.get("coins_gp", 0) == 0, "gp should be 0")
	check(new_coins.get("coins_sp", 0) == 9, "sp: expected 9, got %d" % new_coins.get("coins_sp", 0))
	check(new_coins.get("coins_cp", 0) == 7, "cp: expected 7, got %d" % new_coins.get("coins_cp", 0))
	print("  deduction_makes_change: OK")


func test_deduction_insufficient_funds() -> void:
	var coins := {"coins_cp": 5}
	var result := Currency.compute_deduction(coins, 100)
	check(not result["success"], "should fail with insufficient funds")
	check(result["message"].contains("Insufficient"), "message should mention insufficient")
	print("  deduction_insufficient: OK")


func test_deduction_all_platinum() -> void:
	# Have: 2pp (2000cp). Deduct 1553cp.
	var coins := {"coins_pp": 2}
	var result := Currency.compute_deduction(coins, 1553)
	check(result["success"], "should succeed")
	var new_coins: Dictionary = result["new_coins"]
	# 2000 - 1553 = 447cp change = 0pp 0ep 4gp 4sp 7cp
	var remaining_cp := Currency.coins_to_cp(new_coins)
	check(remaining_cp == 447, "remaining should be 447cp, got %d" % remaining_cp)
	print("  deduction_all_platinum: OK")


func test_deduction_from_gp_needs_change() -> void:
	# Have: 1sp (10cp). Deduct 3cp. Should spend from sp and get change.
	var coins := {"coins_sp": 1}
	var result := Currency.compute_deduction(coins, 3)
	check(result["success"], "should succeed")
	var new_coins: Dictionary = result["new_coins"]
	# 10cp - 3cp = 7cp change
	check(new_coins.get("coins_sp", 0) == 0, "sp should be 0")
	check(new_coins.get("coins_cp", 0) == 7, "cp: expected 7, got %d" % new_coins.get("coins_cp", 0))
	print("  deduction_from_sp_change: OK")
