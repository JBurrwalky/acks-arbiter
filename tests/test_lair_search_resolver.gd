extends "res://tests/test_suite_base.gd"

## Unit tests for LairSearchResolver (Wilderness closure Phase 4).
##
## SACRED tests against `le_wilderness_lair_rules.xml` §searching_for_lairs:
##   * Target value table maps daily wilderness movement → 1d20 target.
##   * Tracking proficiency adds +4 on dedicated search throws (not passive).
##   * "Discovers a lair if at least one lair is present" — succeeded throw
##     produces lair_found = true only when undiscovered_lair_count > 0.
##   * Aerial reconnaissance doubles daily movement before the table lookup.
##
## PROJECT-DESIGNED tests:
##   * `optional_specialist_bonus` is additive on search_hour (Phase 6 wires
##     the Pathfinder bonus through this hook).
##
## (The v1 `passive_check` entry point and its tests were removed 2026-06-10
## per gdd-lair-discovery.md §10 — lazy placement has nothing to spot.)


# ---------------------------------------------------------------------------
# Fake DiceSystem — fixed return value
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _value: int = 1
	func _init(v: int = 1) -> void:
		_value = v
	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = []
		var total := 0
		for _i in range(count):
			r.individual_results.append(_value)
			total += _value
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_value == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_target_value_slowest_band()
	test_target_value_mid_band()
	test_target_value_fastest_band()
	test_target_value_aerial_doubles_movement()
	test_search_hour_no_lairs_succeeds_throw_but_no_reveal()
	test_search_hour_with_lairs_succeeds_lair_found()
	test_search_hour_failure_no_reveal()
	test_search_hour_tracking_bonus_applied()
	test_search_hour_specialist_bonus_pass_through()
	if not has_failures():
		print("LairSearchResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(member_count: int, with_tracking: bool = false) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_phase4_lsr"
	pd.character_data = []
	for i in range(member_count):
		var cd := CharacterData.new()
		cd.id = "pc_%d" % i
		cd.name = "PC %d" % i
		cd.hp_max = 10
		cd.hp_current = 10
		if with_tracking and i == 0:
			cd.proficiencies = [{"proficiency_key": "tracking", "rank": 1}]
		pd.character_data.append(cd)
	return pd


# ---------------------------------------------------------------------------
# compute_target_value
# ---------------------------------------------------------------------------

func test_target_value_slowest_band() -> void:
	# RAW: 11 miles or less → 18+
	check(LairSearchResolver.compute_target_value(0) == 18, "0 mi → 18+")
	check(LairSearchResolver.compute_target_value(11) == 18, "11 mi → 18+")
	check(LairSearchResolver.compute_target_value(12) == 17, "12 mi → 17+")


func test_target_value_mid_band() -> void:
	# RAW: 60-71 miles → 13+
	check(LairSearchResolver.compute_target_value(60) == 13, "60 mi → 13+")
	check(LairSearchResolver.compute_target_value(71) == 13, "71 mi → 13+")
	# 72-83 → 12+
	check(LairSearchResolver.compute_target_value(72) == 12, "72 mi → 12+")


func test_target_value_fastest_band() -> void:
	# RAW: 192 miles or more → 2+
	check(LairSearchResolver.compute_target_value(192) == 2, "192 mi → 2+")
	check(LairSearchResolver.compute_target_value(500) == 2, "500 mi → 2+")
	# Just below → 3+
	check(LairSearchResolver.compute_target_value(180) == 3, "180 mi → 3+")
	check(LairSearchResolver.compute_target_value(191) == 3, "191 mi → 3+")


func test_target_value_aerial_doubles_movement() -> void:
	# RAW §aerial_reconnaissance: "double its daily wilderness movement rate."
	# 24 mi ground would be 16+ (24-35 row); aerial doubles to 48 → 14+ row.
	check(LairSearchResolver.compute_target_value(24, false) == 16, "24 mi ground → 16+")
	check(LairSearchResolver.compute_target_value(24, true) == 14, "24 mi aerial = 48 → 14+")


# ---------------------------------------------------------------------------
# search_hour — dedicated throw
# ---------------------------------------------------------------------------

func test_search_hour_no_lairs_succeeds_throw_but_no_reveal() -> void:
	# RAW: "the party discovers a lair if at least one lair is present."
	# Throw can succeed without finding a lair (the hex truly is empty).
	var party := _make_party(2)
	var dice := _FixedDice.new(20)  # auto-success
	var r := LairSearchResolver.search_hour(party, 0, 0, dice)
	check(bool(r["succeeded"]), "rolled 20, target 18 → succeeded")
	check(not bool(r["lair_found"]), "no undiscovered lairs → not found")
	check(int(r["undiscovered_lairs_at_throw"]) == 0, "lair count recorded")


func test_search_hour_with_lairs_succeeds_lair_found() -> void:
	var party := _make_party(2)
	var dice := _FixedDice.new(20)
	var r := LairSearchResolver.search_hour(party, 0, 3, dice)
	check(bool(r["succeeded"]), "succeeded")
	check(bool(r["lair_found"]), "with lairs present, success → lair_found")
	check(int(r["undiscovered_lairs_at_throw"]) == 3, "lair count recorded")


func test_search_hour_failure_no_reveal() -> void:
	var party := _make_party(2)
	var dice := _FixedDice.new(2)  # 2 + 0 = 2, target 18 → fail
	var r := LairSearchResolver.search_hour(party, 0, 5, dice)
	check(not bool(r["succeeded"]), "failed throw")
	check(not bool(r["lair_found"]), "no reveal on failure")


func test_search_hour_tracking_bonus_applied() -> void:
	# RAW: "If any party member has the Tracking proficiency, the party
	# receives a +4 bonus on the lair search roll."
	var party_tracking := _make_party(2, true)
	var party_no_tracking := _make_party(2, false)
	var dice := _FixedDice.new(14)
	# Without tracking: 14 + 0 = 14 < 18 → fail
	var r_no := LairSearchResolver.search_hour(party_no_tracking, 0, 1, dice)
	check(int(r_no["tracking_bonus"]) == 0, "no tracking bonus")
	check(not bool(r_no["succeeded"]), "14 < 18 without tracking")
	# With tracking: 14 + 4 = 18 → success
	var r_yes := LairSearchResolver.search_hour(party_tracking, 0, 1, dice)
	check(int(r_yes["tracking_bonus"]) == 4, "tracking bonus = 4")
	check(bool(r_yes["succeeded"]), "14 + 4 = 18 with tracking")


func test_search_hour_specialist_bonus_pass_through() -> void:
	# Phase 6 hook: Pathfinder bonus. Phase 4 always passes 0.
	var party := _make_party(2)
	var dice := _FixedDice.new(13)
	var r := LairSearchResolver.search_hour(party, 0, 1, dice, 5)
	check(int(r["specialist_bonus"]) == 5, "specialist bonus stored")
	check(int(r["total"]) == 18, "13 + 0 (no tracking) + 5 = 18")
	check(bool(r["succeeded"]), "specialist bonus carries the throw to 18+")


# (passive_check tests removed 2026-06-10 with the entry point itself —
# see the class docs note and gdd-lair-discovery.md §10.)
