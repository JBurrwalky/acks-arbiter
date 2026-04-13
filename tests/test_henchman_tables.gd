extends "res://tests/test_suite_base.gd"

## Phase G-2: Sacred henchman lookup tables from rules/acore_equipment.xml and
## rules/ax_henchmen_recruitment_expanded.xml.


func run_all_tests() -> void:
	test_class_rarity_lookup()
	test_monthly_wage_table()
	test_max_henchmen_calc()
	test_search_cost_spec()
	test_level_from_roll()
	test_hiring_reaction_table()
	test_loyalty_result_table()
	test_weekly_allotment_sacred()
	test_rarity_availability()
	if not has_failures():
		print("HenchmanTables: all tests passed.")


func test_class_rarity_lookup() -> void:
	check(HenchmanTables.get_class_rarity("fighter") == HenchmanTables.RARITY_COMMON,
		"fighter = common")
	check(HenchmanTables.get_class_rarity("thief") == HenchmanTables.RARITY_COMMON,
		"thief = common")
	check(HenchmanTables.get_class_rarity("mage") == HenchmanTables.RARITY_UNCOMMON,
		"mage = uncommon")
	check(HenchmanTables.get_class_rarity("cleric") == HenchmanTables.RARITY_UNCOMMON,
		"cleric = uncommon")
	check(HenchmanTables.get_class_rarity("bladedancer") == HenchmanTables.RARITY_RARE,
		"bladedancer = rare")
	check(HenchmanTables.get_class_rarity("paladin") == HenchmanTables.RARITY_VERY_RARE,
		"paladin = very_rare")
	check(HenchmanTables.get_class_rarity("elven_enchanter") == HenchmanTables.RARITY_LEGENDARY,
		"elven_enchanter = legendary")


func test_monthly_wage_table() -> void:
	check(HenchmanTables.monthly_wage(0) == 12, "level 0 = 12gp")
	check(HenchmanTables.monthly_wage(1) == 25, "level 1 = 25gp")
	check(HenchmanTables.monthly_wage(4) == 200, "level 4 = 200gp")
	check(HenchmanTables.monthly_wage(9) == 7250, "level 9 = 7250gp")
	check(HenchmanTables.monthly_wage(14) == 350000, "level 14 = 350000gp")


func test_max_henchmen_calc() -> void:
	# CHA 3 → mod -3, no Leadership
	check(HenchmanTables.max_henchmen(-3, 0) == 1, "CHA 3 = 1 (min 1)")
	# CHA 9-12 → mod 0, no Leadership
	check(HenchmanTables.max_henchmen(0, 0) == 4, "CHA avg = 4")
	# CHA 18 → mod +3, no Leadership
	check(HenchmanTables.max_henchmen(3, 0) == 7, "CHA 18 = 7")
	# CHA 18 + Leadership
	check(HenchmanTables.max_henchmen(3, 1) == 8, "CHA 18 + Leadership = 8")
	# CHA 16 + Leadership x2
	check(HenchmanTables.max_henchmen(2, 2) == 8, "CHA 16 + Leadership x2 = 8")


func test_search_cost_spec() -> void:
	var s1 := HenchmanTables.search_cost_spec(1)
	check(s1["dice_count"] == 1 and s1["dice_sides"] == 6 and s1["modifier"] == 15,
		"class I: 1d6+15")
	var s6 := HenchmanTables.search_cost_spec(6)
	check(s6["dice_count"] == 1 and s6["dice_sides"] == 3 and s6["modifier"] == 0,
		"class VI: 1d3")


func test_level_from_roll() -> void:
	check(HenchmanTables.level_from_roll(1) == 1, "roll 1 = level 1")
	check(HenchmanTables.level_from_roll(10) == 1, "roll 10 = level 1")
	check(HenchmanTables.level_from_roll(11) == 2, "roll 11 = level 2")
	check(HenchmanTables.level_from_roll(16) == 2, "roll 16 = level 2")
	check(HenchmanTables.level_from_roll(17) == 3, "roll 17 = level 3")
	check(HenchmanTables.level_from_roll(18) == 3, "roll 18 = level 3")
	check(HenchmanTables.level_from_roll(19) == 4, "roll 19 = level 4")
	check(HenchmanTables.level_from_roll(20) == 4, "roll 20 = level 4")
	# Class VI penalty: roll 12 - 2 = 10 → level 1
	check(HenchmanTables.level_from_roll(12, 6) == 1, "class VI roll 12 = level 1")
	# Class VI: roll 20 - 2 = 18 → level 3
	check(HenchmanTables.level_from_roll(20, 6) == 3, "class VI roll 20 = level 3")


func test_hiring_reaction_table() -> void:
	check(HenchmanTables.hiring_reaction(2) == HenchmanTables.HIRE_REFUSE_SLANDER, "2 = slander")
	check(HenchmanTables.hiring_reaction(1) == HenchmanTables.HIRE_REFUSE_SLANDER, "1 = slander")
	check(HenchmanTables.hiring_reaction(3) == HenchmanTables.HIRE_REFUSE, "3 = refuse")
	check(HenchmanTables.hiring_reaction(5) == HenchmanTables.HIRE_REFUSE, "5 = refuse")
	check(HenchmanTables.hiring_reaction(6) == HenchmanTables.HIRE_TRY_AGAIN, "6 = try_again")
	check(HenchmanTables.hiring_reaction(8) == HenchmanTables.HIRE_TRY_AGAIN, "8 = try_again")
	check(HenchmanTables.hiring_reaction(9) == HenchmanTables.HIRE_ACCEPT, "9 = accept")
	check(HenchmanTables.hiring_reaction(11) == HenchmanTables.HIRE_ACCEPT, "11 = accept")
	check(HenchmanTables.hiring_reaction(12) == HenchmanTables.HIRE_ACCEPT_ELAN, "12 = elan")
	check(HenchmanTables.hiring_reaction(15) == HenchmanTables.HIRE_ACCEPT_ELAN, "15 = elan")


func test_loyalty_result_table() -> void:
	check(HenchmanTables.loyalty_result(2) == HenchmanTables.LOYALTY_HOSTILITY, "2 = hostility")
	check(HenchmanTables.loyalty_result(0) == HenchmanTables.LOYALTY_HOSTILITY, "0 = hostility")
	check(HenchmanTables.loyalty_result(3) == HenchmanTables.LOYALTY_RESIGNATION, "3 = resignation")
	check(HenchmanTables.loyalty_result(5) == HenchmanTables.LOYALTY_RESIGNATION, "5 = resignation")
	check(HenchmanTables.loyalty_result(6) == HenchmanTables.LOYALTY_GRUDGING, "6 = grudging")
	check(HenchmanTables.loyalty_result(8) == HenchmanTables.LOYALTY_GRUDGING, "8 = grudging")
	check(HenchmanTables.loyalty_result(9) == HenchmanTables.LOYALTY_LOYAL, "9 = loyal")
	check(HenchmanTables.loyalty_result(11) == HenchmanTables.LOYALTY_LOYAL, "11 = loyal")
	check(HenchmanTables.loyalty_result(12) == HenchmanTables.LOYALTY_FANATIC, "12 = fanatic")


func test_weekly_allotment_sacred() -> void:
	# Sacred: week1 = ceil(total/2), week2 = max(1, floor(total/4)), week3 = remainder.
	var a7 := HenchmanTables.weekly_allotment(7)
	check(a7[0] == 4, "total 7: week1 = 4 (ceil 3.5)")
	check(a7[1] == 1, "total 7: week2 = 1 (max(1, floor 1.75))")
	check(a7[2] == 2, "total 7: week3 = 2 (remainder)")
	var a1 := HenchmanTables.weekly_allotment(1)
	check(a1[0] == 1, "total 1: week1 = 1")
	check(a1[1] == 0, "total 1: week2 = 0 (1 - 1 = 0)")
	check(a1[2] == 0, "total 1: week3 = 0")
	var a10 := HenchmanTables.weekly_allotment(10)
	check(a10[0] == 5, "total 10: week1 = 5")
	check(a10[1] == 2, "total 10: week2 = 2")
	check(a10[2] == 3, "total 10: week3 = 3")
	var a0 := HenchmanTables.weekly_allotment(0)
	check(a0[0] == 0 and a0[1] == 0 and a0[2] == 0, "total 0: all zeros")
	var a2 := HenchmanTables.weekly_allotment(2)
	check(a2[0] == 1, "total 2: week1 = 1")
	check(a2[1] == 1, "total 2: week2 = 1 (max(1, 0))")
	check(a2[2] == 0, "total 2: week3 = 0")


func test_rarity_availability() -> void:
	# Common in class I: 20 guaranteed.
	var ci := HenchmanTables.rarity_availability(HenchmanTables.RARITY_COMMON, 1)
	check(ci["count"] == 20 and ci["percent"] == 100, "common I = 20 guaranteed")
	# Uncommon in class V: unavailable.
	var uv := HenchmanTables.rarity_availability(HenchmanTables.RARITY_UNCOMMON, 5)
	check(uv["count"] == -1 and uv["percent"] == 0, "uncommon V = unavailable")
	# Rare in class II: 1 at 5%.
	var rii := HenchmanTables.rarity_availability(HenchmanTables.RARITY_RARE, 2)
	check(rii["count"] == 1 and rii["percent"] == 5, "rare II = 1 at 5%%")
	# Legendary in class I: 1 at 1%.
	var li := HenchmanTables.rarity_availability(HenchmanTables.RARITY_LEGENDARY, 1)
	check(li["count"] == 1 and li["percent"] == 1, "legendary I = 1 at 1%%")
	# Legendary in class II: unavailable.
	var lii := HenchmanTables.rarity_availability(HenchmanTables.RARITY_LEGENDARY, 2)
	check(lii["count"] == -1 and lii["percent"] == 0, "legendary II = unavailable")
