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
	test_format_cost_skips_pp_ep()
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
	check(Currency.coin_key_to_cp_value("coins_pp") == 500, "pp should be 500cp")
	check(Currency.coin_key_to_cp_value("coins_gp") == 100, "gp should be 100cp")
	check(Currency.coin_key_to_cp_value("coins_ep") == 50, "ep should be 50cp")
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
	var coins := {"coins_pp": 2, "coins_gp": 3, "coins_ep": 1, "coins_sp": 5, "coins_cp": 7}
	# 2*500 + 3*100 + 1*50 + 5*10 + 7 = 1000 + 300 + 50 + 50 + 7 = 1407
	var total := Currency.coins_to_cp(coins)
	check(total == 1407, "expected 1407cp, got %d" % total)
	print("  coins_to_cp_all: OK")


func test_coins_to_cp_empty() -> void:
	var total := Currency.coins_to_cp({})
	check(total == 0, "empty coins should be 0cp, got %d" % total)
	print("  coins_to_cp_empty: OK")


func test_cp_to_coins_exact_pp() -> void:
	var coins := Currency.cp_to_coins(500)
	check(coins.get("coins_pp", 0) == 1, "500cp should be 1pp")
	check(coins.get("coins_gp", 0) == 0, "no gp remainder")
	print("  cp_to_coins_exact_pp: OK")


func test_cp_to_coins_mixed() -> void:
	# 667cp = 1pp(500) + 1gp(100) + 1ep(50) + 1sp(10) + 7cp
	var coins := Currency.cp_to_coins(667)
	check(coins.get("coins_pp", 0) == 1, "expected 1pp, got %d" % coins.get("coins_pp", 0))
	check(coins.get("coins_gp", 0) == 1, "expected 1gp, got %d" % coins.get("coins_gp", 0))
	check(coins.get("coins_ep", 0) == 1, "expected 1ep, got %d" % coins.get("coins_ep", 0))
	check(coins.get("coins_sp", 0) == 1, "expected 1sp, got %d" % coins.get("coins_sp", 0))
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
	# 300cp = 3gp.
	check(Currency.format_cost(300) == "3gp", "300cp should format as 3gp, got '%s'" % Currency.format_cost(300))
	# User spec: 5000cp = 50gp.
	check(Currency.format_cost(5000) == "50gp", "5000cp should format as 50gp, got '%s'" % Currency.format_cost(5000))
	print("  format_cost_gp: OK")


func test_format_cost_mixed() -> void:
	# 2026-05-18 cost format: gp/sp/cp only, comma+space separator (per user spec).
	# User spec: 1789 cp → "17gp, 8sp, 9cp".
	check(Currency.format_cost(1789) == "17gp, 8sp, 9cp",
		"1789cp format_cost: got '%s'" % Currency.format_cost(1789))
	# User spec: 50,107 cp → "501gp, 7cp" (no sp because remainder < 10).
	check(Currency.format_cost(50_107) == "501gp, 7cp",
		"50,107cp format_cost: got '%s'" % Currency.format_cost(50_107))
	print("  format_cost_mixed: OK")


func test_format_cost_zero() -> void:
	check(Currency.format_cost(0) == "0cp", "0 should format as 0cp")
	print("  format_cost_zero: OK")


func test_format_cost_skips_pp_ep() -> void:
	# Cost format uses only gp/sp/cp; pp/ep are physical-coin denominations
	# reserved for format_wealth (inventory/treasure/loot displays).
	# 50 cp was "1ep" under the old format; cost format = "5sp".
	check(Currency.format_cost(50) == "5sp",
		"50cp under cost format = 5sp (no ep), got '%s'" % Currency.format_cost(50))
	# 550 cp was "1pp 1ep"; cost format = "5gp, 5sp".
	check(Currency.format_cost(550) == "5gp, 5sp",
		"550cp under cost format = 5gp, 5sp (no pp/ep), got '%s'" % Currency.format_cost(550))
	# User spec: 30 cp = "3sp" (no gp magnitude).
	check(Currency.format_cost(30) == "3sp",
		"30cp = 3sp, got '%s'" % Currency.format_cost(30))
	print("  format_cost_skips_pp_ep: OK")


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
	# 100cp - 3cp = 97cp change = 1ep(50) + 4sp(40) + 7cp
	check(new_coins.get("coins_gp", 0) == 0, "gp should be 0")
	check(new_coins.get("coins_ep", 0) == 1, "ep: expected 1, got %d" % new_coins.get("coins_ep", 0))
	check(new_coins.get("coins_sp", 0) == 4, "sp: expected 4, got %d" % new_coins.get("coins_sp", 0))
	check(new_coins.get("coins_cp", 0) == 7, "cp: expected 7, got %d" % new_coins.get("coins_cp", 0))
	print("  deduction_makes_change: OK")


func test_deduction_insufficient_funds() -> void:
	var coins := {"coins_cp": 5}
	var result := Currency.compute_deduction(coins, 100)
	check(not result["success"], "should fail with insufficient funds")
	check(result["message"].contains("Insufficient"), "message should mention insufficient")
	print("  deduction_insufficient: OK")


func test_deduction_all_platinum() -> void:
	# Have: 4pp (2000cp). Deduct 1553cp.
	var coins := {"coins_pp": 4}
	var result := Currency.compute_deduction(coins, 1553)
	check(result["success"], "should succeed")
	var new_coins: Dictionary = result["new_coins"]
	# 2000 - 1553 = 447cp change = 4gp(400) + 4sp(40) + 7cp
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
