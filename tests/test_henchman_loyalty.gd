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
