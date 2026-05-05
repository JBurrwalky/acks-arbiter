extends "res://tests/test_suite_base.gd"

## Unit tests for SurveyingResolver (Wilderness closure Phase 4).
##
## SACRED tests against `le_wilderness_lair_rules.xml` §land_surveying:
##   * Base target 18+, +4 cumulative per successful prior search.
##   * Success → reveal correct lair count.
##   * Natural-1 → false reading (estimate is non-truthful).
##   * Other failure → no estimate produced (inconclusive).
##   * Eligibility: surveyor must have Land Surveying proficiency.


# ---------------------------------------------------------------------------
# Fake DiceSystem — programmable per roll_type
# ---------------------------------------------------------------------------

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
		r.natural_one = (base == 1 and sides == 20 and count == 1)
		r.natural_max = (base == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_no_surveyor_in_party_returns_ineligible()
	test_first_attempt_target_is_18()
	test_target_drops_by_4_per_prior_search()
	test_success_reveals_actual_count()
	test_failure_inconclusive_no_estimate()
	test_natural_one_returns_false_reading()
	test_estimate_clamped_at_zero()
	if not has_failures():
		print("SurveyingResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(member_count: int, with_surveyor: bool = true) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_phase4_sr"
	pd.character_data = []
	for i in range(member_count):
		var cd := CharacterData.new()
		cd.id = "pc_%d" % i
		cd.name = "PC %d" % i
		cd.hp_max = 10
		cd.hp_current = 10
		if with_surveyor and i == 0:
			cd.proficiencies = [{"proficiency_key": "land_surveying", "rank": 1}]
		pd.character_data.append(cd)
	return pd


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_no_surveyor_in_party_returns_ineligible() -> void:
	var party := _make_party(3, false)
	var dice := _ScriptedDice.new()
	var r := SurveyingResolver.assess(party, 0, 5, dice)
	check(not bool(r["eligible"]), "no Land Surveying → ineligible")
	check(int(r["estimate"]) == -1, "no estimate when ineligible")


func test_first_attempt_target_is_18() -> void:
	# RAW: "The base target value is 18+."
	var party := _make_party(2)
	var dice := _ScriptedDice.new()
	dice.scripts = {"land_surveying": [17]}
	var r := SurveyingResolver.assess(party, 0, 4, dice)
	check(int(r["target"]) == 18, "first attempt target is 18+")
	check(not bool(r["succeeded"]), "17 < 18")


func test_target_drops_by_4_per_prior_search() -> void:
	# RAW: "Apply a cumulative +4 bonus for each successful search the party
	# has conducted in that hex up to that point." (Modeled here as a
	# target-reduction equivalent: target = 18 - 4 * prior_searches.)
	var party := _make_party(2)
	var dice := _ScriptedDice.new()
	dice.scripts = {"land_surveying": [10]}
	# After 2 successful searches: target = 18 - 8 = 10. 10 >= 10 → success.
	var r := SurveyingResolver.assess(party, 2, 7, dice)
	check(int(r["target"]) == 10, "target = 18 - 4*2 = 10")
	check(bool(r["succeeded"]), "10 >= 10 with two-search bonus")


func test_success_reveals_actual_count() -> void:
	var party := _make_party(2)
	var dice := _ScriptedDice.new()
	dice.scripts = {"land_surveying": [20]}
	var r := SurveyingResolver.assess(party, 0, 6, dice)
	check(bool(r["succeeded"]), "20 >= 18")
	check(int(r["estimate"]) == 6, "success reveals actual count = 6")
	check(bool(r["estimate_correct"]), "marked correct")


func test_failure_inconclusive_no_estimate() -> void:
	# RAW: "On any other failure, the character does not yet have enough
	# information to make or revise an assessment."
	var party := _make_party(2)
	var dice := _ScriptedDice.new()
	dice.scripts = {"land_surveying": [10]}  # not a 1, but below target 18
	var r := SurveyingResolver.assess(party, 0, 5, dice)
	check(not bool(r["succeeded"]), "10 < 18")
	check(not bool(r["natural_one"]), "not a natural 1")
	check(int(r["estimate"]) == -1, "no estimate produced")


func test_natural_one_returns_false_reading() -> void:
	# RAW: "If the throw fails with an unmodified 1, the character makes an
	# incorrect assessment, and the Judge rolls or chooses a false number
	# to reveal."
	var party := _make_party(2)
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"land_surveying": [1],
		"land_surveying_false": [3],   # 1d4 step
		"land_surveying_false_sign": [1],  # negative direction
	}
	var r := SurveyingResolver.assess(party, 0, 5, dice)
	check(bool(r["natural_one"]), "natural 1 detected")
	check(int(r["estimate"]) == 2, "actual 5 - 3 = 2 false reading")
	check(not bool(r["estimate_correct"]), "marked incorrect")


func test_estimate_clamped_at_zero() -> void:
	var party := _make_party(2)
	var dice := _ScriptedDice.new()
	dice.scripts = {
		"land_surveying": [1],
		"land_surveying_false": [4],
		"land_surveying_false_sign": [1],  # negative
	}
	# Actual = 1, step = -4 → clamp to 0 (can't have negative lairs).
	var r := SurveyingResolver.assess(party, 0, 1, dice)
	check(int(r["estimate"]) == 0, "false reading clamped to 0")
