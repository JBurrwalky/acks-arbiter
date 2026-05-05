extends "res://tests/test_suite_base.gd"

## Unit tests for HuntingResolver (Wilderness closure Phase 3).
##
## SACRED tests against `acore_adventures_and_encounters.xml`
## §rations_and_foraging.hunting:
##   * "Proficiency throw 14+ on 1d20."
##   * "Success: Food for 2d6 man-sized creatures."
##   * Survival proficiency: +4 to throws (sacred from
##     §rations_and_foraging.survival_proficiency_bonus).


class _ScriptedDice:
	extends RefCounted
	var scripts: Dictionary = {}
	var default_value: int = 1

	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		var base: int = default_value
		if scripts.has(roll_type) and not scripts[roll_type].is_empty():
			base = int(scripts[roll_type].pop_front())
		var total := 0
		r.individual_results = []
		for _i in range(count):
			r.individual_results.append(base)
			total += base
		r.raw_total = total
		r.modified_total = total + modifier
		return r


func run_all_tests() -> void:
	test_hunt_failure_no_units()
	test_hunt_success_2d6_units()
	test_hunt_survival_bonus_easier()
	test_hunter_selection_prefers_survival()
	test_hunter_selection_falls_back_to_first()
	test_empty_party_no_op()
	if not has_failures():
		print("HuntingResolver: all tests passed.")


func _make_member(idx: int, has_survival: bool = false) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "pc_%d" % idx
	cd.name = "PC %d" % idx
	if has_survival:
		cd.proficiencies = [{"proficiency_key": "survival", "rank": 1}]
	return cd


func _make_party(member_count: int, survival_indices: Array = []) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_phase3_hunt_party"
	pd.character_data = []
	for i in range(member_count):
		pd.character_data.append(_make_member(i, i in survival_indices))
	return pd


func test_hunt_failure_no_units() -> void:
	var party := _make_party(2)
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {"hunt": [13]}  # untrained, target 14, fails
	var r := HuntingResolver.attempt(party, dice)
	check(not r.get("succeeded", true), "13 < 14 → fail")
	check(r.get("units_added", -1) == 0, "no units")
	check(party.ration_units == 0, "ration_units unchanged")


func test_hunt_success_2d6_units() -> void:
	var party := _make_party(2)
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {"hunt": [14], "hunt_yield": [3]}
	# 2d6 with each die forced to 3 → total 6
	var r := HuntingResolver.attempt(party, dice)
	check(r.get("succeeded", false), "14 ≥ 14 → success")
	check(r.get("units_added", -1) == 6,
		"2d6 with each die=3 → 6; got %d" % r.get("units_added", -1))
	check(party.ration_units == 6, "ration_units += 6")


func test_hunt_survival_bonus_easier() -> void:
	var party := _make_party(1, [0])
	party.ration_units = 0
	var dice := _ScriptedDice.new()
	dice.scripts = {"hunt": [10], "hunt_yield": [4]}
	# 10 + 4 Survival = 14 → success
	var r := HuntingResolver.attempt(party, dice)
	check(r.get("succeeded", false), "10 + 4 Survival = 14 ≥ 14 → success")
	check(r.get("modifier", -1) == 4, "Survival bonus applied")
	check(r.get("units_added", -1) == 8, "2d6 with die=4 → 8")
	check(party.ration_units == 8, "ration_units += 8")


func test_hunter_selection_prefers_survival() -> void:
	# Members: 0 untrained, 1 has Survival, 2 untrained → hunter is index 1.
	var party := _make_party(3, [1])
	var dice := _ScriptedDice.new()
	dice.scripts = {"hunt": [1]}
	var r := HuntingResolver.attempt(party, dice)
	check(r.get("hunter_id", "") == "pc_1", "hunter is the Survival member")
	check(r.get("has_survival", false), "has_survival flagged")


func test_hunter_selection_falls_back_to_first() -> void:
	# No Survival in party → first member is the hunter.
	var party := _make_party(2)
	var dice := _ScriptedDice.new()
	dice.scripts = {"hunt": [1]}
	var r := HuntingResolver.attempt(party, dice)
	check(r.get("hunter_id", "") == "pc_0", "hunter is first member")
	check(not r.get("has_survival", true), "no Survival flag")


func test_empty_party_no_op() -> void:
	var party := _make_party(0)
	var dice := _ScriptedDice.new()
	var r := HuntingResolver.attempt(party, dice)
	check(r.get("succeeded", true) == false, "no characters → no success")
	check(r.get("units_added", -1) == 0, "no units")
	check(r.get("hunter_id", "x") == "", "no hunter")
