extends "res://tests/test_suite_base.gd"

## Phase G-2: Loyalty resolver tests — morale calculation, loyalty checks,
## hiring reaction rolls.


class FakeDice:
	extends RefCounted
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


func run_all_tests() -> void:
	test_base_morale_calculation()
	test_loyalty_modifier_assembly()
	test_loyalty_roll_outcomes()
	test_loyalty_departure_flags()
	test_hiring_reaction_outcomes()
	test_hiring_elan_morale_bonus()
	# Prereq.7 (§11.2) — extra_modifiers extension
	test_extra_modifiers_default_is_noop()
	test_extra_modifiers_single_entry()
	test_extra_modifiers_multiple_entries_sum()
	test_extra_modifier_breakdown_in_return_dict()
	if not has_failures():
		print("HenchmanLoyaltyResolver: all tests passed.")


func test_base_morale_calculation() -> void:
	# CHA 16 → mod +2, no Command
	check(HenchmanLoyaltyResolver.base_morale(2, false) == 2, "CHA 16 base = +2")
	# CHA 18 → mod +3, with Command +2
	check(HenchmanLoyaltyResolver.base_morale(3, true) == 5, "CHA 18 + Command = +5")
	# CHA 6 → mod -1
	check(HenchmanLoyaltyResolver.base_morale(-1, false) == -1, "CHA 6 base = -1")
	# CHA 9 → mod 0, with Command
	check(HenchmanLoyaltyResolver.base_morale(0, true) == 2, "CHA avg + Command = +2")


func test_loyalty_modifier_assembly() -> void:
	# Base morale 3, not grudging, not fanatic
	check(HenchmanLoyaltyResolver.loyalty_modifier(3, false, false) == 3, "plain 3")
	# Base morale 3, grudging
	check(HenchmanLoyaltyResolver.loyalty_modifier(3, true, false) == 2, "grudging 3-1=2")
	# Base morale 3, fanatic
	check(HenchmanLoyaltyResolver.loyalty_modifier(3, false, true) == 5, "fanatic 3+2=5")
	# Both (shouldn't happen but test)
	check(HenchmanLoyaltyResolver.loyalty_modifier(3, true, true) == 4, "grudging+fanatic 3-1+2=4")


func test_loyalty_roll_outcomes() -> void:
	var dice := FakeDice.new()
	# Roll 7, morale 0 → total 7 → grudging
	dice.fixed_total = 7
	var r := HenchmanLoyaltyResolver.resolve_loyalty_check(0, false, false, dice)
	check(r["outcome"] == HenchmanTables.LOYALTY_GRUDGING, "7+0 = grudging")
	check(not r["departs"], "grudging does not depart")

	# Roll 7, morale 4 → total 11 → loyal
	var r2 := HenchmanLoyaltyResolver.resolve_loyalty_check(4, false, false, dice)
	check(r2["outcome"] == HenchmanTables.LOYALTY_LOYAL, "7+4 = loyal")
	check(r2["clear_grudging"], "loyal clears grudging")

	# Roll 7, morale 5 → total 12 → fanatic
	var r3 := HenchmanLoyaltyResolver.resolve_loyalty_check(5, false, false, dice)
	check(r3["outcome"] == HenchmanTables.LOYALTY_FANATIC, "7+5 = fanatic")
	check(r3["set_fanatic"], "fanatic sets flag")

	# Roll 2, morale 0 → total 2 → hostility
	dice.fixed_total = 2
	var r4 := HenchmanLoyaltyResolver.resolve_loyalty_check(0, false, false, dice)
	check(r4["outcome"] == HenchmanTables.LOYALTY_HOSTILITY, "2+0 = hostility")
	check(r4["departs"], "hostility departs")

	# Roll 3, morale 0 → total 3 → resignation
	dice.fixed_total = 3
	var r5 := HenchmanLoyaltyResolver.resolve_loyalty_check(0, false, false, dice)
	check(r5["outcome"] == HenchmanTables.LOYALTY_RESIGNATION, "3+0 = resignation")
	check(r5["departs"], "resignation departs")


func test_loyalty_departure_flags() -> void:
	var dice := FakeDice.new()
	# Grudging henchman gets -1: roll 7, morale 0, grudging → total 6 → still grudging
	dice.fixed_total = 7
	var r := HenchmanLoyaltyResolver.resolve_loyalty_check(0, true, false, dice)
	check(r["total"] == 6, "grudging penalty applied: 7 + (0-1) = 6")
	check(r["outcome"] == HenchmanTables.LOYALTY_GRUDGING, "still grudging")

	# Fanatic gets +2: roll 7, morale 0, fanatic → total 9 → loyal
	var r2 := HenchmanLoyaltyResolver.resolve_loyalty_check(0, false, true, dice)
	check(r2["total"] == 9, "fanatic bonus applied: 7 + (0+2) = 9")
	check(r2["outcome"] == HenchmanTables.LOYALTY_LOYAL, "fanatic stays loyal")


func test_hiring_reaction_outcomes() -> void:
	var dice := FakeDice.new()
	# Roll 7, CHA mod +2 → total 9 → accept
	dice.fixed_total = 7
	var r := HenchmanLoyaltyResolver.resolve_hiring_reaction(2, 0, dice)
	check(r["outcome"] == HenchmanTables.HIRE_ACCEPT, "7+2 = accept")
	check(r["morale_bonus"] == 0, "accept has no bonus")

	# Roll 10, CHA mod +2 → total 12 → accept with élan
	dice.fixed_total = 10
	var r2 := HenchmanLoyaltyResolver.resolve_hiring_reaction(2, 0, dice)
	check(r2["outcome"] == HenchmanTables.HIRE_ACCEPT_ELAN, "10+2 = elan")

	# Roll 3, CHA mod -1 → total 2 → refuse and slander
	dice.fixed_total = 3
	var r3 := HenchmanLoyaltyResolver.resolve_hiring_reaction(-1, 0, dice)
	check(r3["outcome"] == HenchmanTables.HIRE_REFUSE_SLANDER, "3-1 = slander")


func test_hiring_elan_morale_bonus() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 12
	var r := HenchmanLoyaltyResolver.resolve_hiring_reaction(0, 0, dice)
	check(r["morale_bonus"] == 1, "elan grants +1 morale bonus")


# ---------------------------------------------------------------------------
# Prereq.7 (§11.2) — extra_modifiers extension
# ---------------------------------------------------------------------------

## Regression guard: existing positional-arg callers see identical behavior
## when the new extra_modifiers parameter is omitted (or passed as {}).
func test_extra_modifiers_default_is_noop() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 7
	var without_extra := HenchmanLoyaltyResolver.resolve_loyalty_check(3, false, false, dice)
	var with_empty_extra := HenchmanLoyaltyResolver.resolve_loyalty_check(3, false, false, dice, {})
	check(int(without_extra["modifier"]) == int(with_empty_extra["modifier"]),
		"default {} extras yields same modifier as old signature")
	check(int(without_extra["total"]) == int(with_empty_extra["total"]),
		"default {} extras yields same total")
	check(str(without_extra["outcome"]) == str(with_empty_extra["outcome"]),
		"default {} extras yields same outcome")
	check((without_extra["extra_modifier_breakdown"] as Dictionary).is_empty(),
		"omitted extras → empty breakdown dict in return")


## Single extra source — modifier and total both shift by the dict's value.
func test_extra_modifiers_single_entry() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 7
	# Baseline: morale 3 → modifier 3, total 10 (loyal).
	var baseline := HenchmanLoyaltyResolver.resolve_loyalty_check(3, false, false, dice)
	check(int(baseline["modifier"]) == 3, "baseline modifier = 3")
	check(int(baseline["total"]) == 10, "baseline total = 10")
	# With hijink_overload: -3 → modifier 0, total 7 (grudging).
	var penalized := HenchmanLoyaltyResolver.resolve_loyalty_check(
		3, false, false, dice, {"hijink_overload": -3})
	check(int(penalized["modifier"]) == 0, "modifier reduced by 3 → 0")
	check(int(penalized["total"]) == 7, "total reduced by 3 → 7")
	check(str(penalized["outcome"]) == HenchmanTables.LOYALTY_GRUDGING,
		"outcome shifted to grudging")


## Multiple extras sum together; net contribution is the arithmetic sum.
func test_extra_modifiers_multiple_entries_sum() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 7
	# {"a": -1, "b": +2, "c": -5} sums to -4. Morale 4 → modifier 4 → with sum → 0.
	var r := HenchmanLoyaltyResolver.resolve_loyalty_check(
		4, false, false, dice, {"a": -1, "b": 2, "c": -5})
	check(int(r["modifier"]) == 0, "modifier sum: 4 + (-1+2-5) = 0, got %d" % int(r["modifier"]))
	check(int(r["total"]) == 7, "total = 7 + 0 = 7")


## breakdown dict mirrors input; mutating the returned breakdown doesn't
## affect the caller's input dict (verifies the `.duplicate()` in the resolver).
func test_extra_modifier_breakdown_in_return_dict() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 7
	var input_extras := {"hijink_overload": -3, "underboss_strain": -2}
	var r := HenchmanLoyaltyResolver.resolve_loyalty_check(
		5, false, false, dice, input_extras)
	var breakdown: Dictionary = r["extra_modifier_breakdown"]
	check(int(breakdown.get("hijink_overload", 0)) == -3, "breakdown.hijink_overload = -3")
	check(int(breakdown.get("underboss_strain", 0)) == -2, "breakdown.underboss_strain = -2")
	check(breakdown.size() == 2, "breakdown has 2 entries")
	# Mutate the returned breakdown — input dict unchanged (duplicate semantics).
	breakdown["spurious_key"] = 999
	check(not input_extras.has("spurious_key"),
		"mutating returned breakdown does not affect caller's input dict")
