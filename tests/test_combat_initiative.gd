extends "res://tests/test_suite_base.gd"

## Unit tests for InitiativeResolver.


func run_all_tests() -> void:
	test_single_combatant_returns_one_entry()
	test_higher_roll_goes_first()
	test_dex_modifier_added()
	test_ties_grouped_simultaneously()
	test_dead_combatants_skipped()
	test_stable_tiebreak_by_id()
	test_empty_combatant_list()
	if not has_failures():
		print("InitiativeResolver: all tests passed.")


func test_single_combatant_returns_one_entry() -> void:
	var resolver := InitiativeResolver.new(null)
	var combatant := _make_fighter("fighter_1")
	var result := resolver.resolve([combatant])
	check(result.size() == 1, "single combatant should produce 1 entry")
	check(result[0]["combatant_id"] == "fighter_1", "should be fighter_1")


func test_higher_roll_goes_first() -> void:
	# With null DiceSystem, all rolls = 3. Use modifier difference.
	var resolver := InitiativeResolver.new(null)
	var fast := _make_fighter("fast", 16)  # DEX 16 = +2 modifier
	var slow := _make_fighter("slow", 8)   # DEX 8 = -1 modifier
	var result := resolver.resolve([slow, fast])
	check(result[0]["combatant_id"] == "fast",
		"higher total (roll+DEX) should go first, got %s" % result[0]["combatant_id"])
	check(result[1]["combatant_id"] == "slow", "slower should go second")


func test_dex_modifier_added() -> void:
	var resolver := InitiativeResolver.new(null)
	var combatant := _make_fighter("dex_test", 16)  # DEX 16 = +2
	var result := resolver.resolve([combatant])
	check(result[0]["modifier"] == 2,
		"DEX 16 should give +2 modifier, got %d" % result[0]["modifier"])
	check(result[0]["total"] == 3 + 2,
		"total should be roll(3) + mod(2) = 5, got %d" % result[0]["total"])


func test_ties_grouped_simultaneously() -> void:
	var resolver := InitiativeResolver.new(null)
	# Both have same DEX, so same total
	var a := _make_fighter("alpha", 10)
	var b := _make_fighter("beta", 10)
	var order := resolver.resolve([a, b])
	var groups := resolver.group_simultaneous(order)
	check(groups.size() == 1,
		"equal totals should form 1 group, got %d" % groups.size())
	check(groups[0].size() == 2,
		"group should contain 2 combatants, got %d" % groups[0].size())


func test_dead_combatants_skipped() -> void:
	var resolver := InitiativeResolver.new(null)
	var alive := _make_fighter("alive_one")
	var dead := _make_fighter("dead_one")
	dead._character.hp_current = 0
	var result := resolver.resolve([alive, dead])
	check(result.size() == 1, "dead combatant should be skipped")
	check(result[0]["combatant_id"] == "alive_one", "only alive should appear")


func test_stable_tiebreak_by_id() -> void:
	var resolver := InitiativeResolver.new(null)
	var a := _make_fighter("aaa", 10)
	var b := _make_fighter("zzz", 10)
	var result := resolver.resolve([b, a])
	# Same total — stable tiebreak by lower ID first
	check(result[0]["combatant_id"] == "aaa",
		"alphabetically lower ID should tiebreak first, got %s" % result[0]["combatant_id"])


func test_empty_combatant_list() -> void:
	var resolver := InitiativeResolver.new(null)
	var empty_arr: Array[Combatant] = []
	var result := resolver.resolve(empty_arr)
	check(result.is_empty(), "empty input should produce empty output")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_fighter(id: String, dex: int = 10) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.dexterity = dex
	cd.hp_current = 10
	cd.hp_max = 10
	return Combatant.from_character(cd)
