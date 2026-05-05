extends "res://tests/test_suite_base.gd"

## End-to-end starvation simulation (Wilderness closure Phase 3).
##
## Drives the SustenanceResolver through a 7-day no-food / no-water run and
## verifies the cumulative HP curve matches `acore_adventures_and_encounters.xml`
## §rations_and_foraging exactly:
##   Day 1: starvation 1, dehydration 1 → 1d4 HP loss (water only — food in grace)
##   Day 2: starvation 2, dehydration 2 → 1d4
##   Day 3: starvation 3 (past grace), dehydration 3 → 1 + 1d4
##   Day 4-7: 1 + 1d4 each
##
## With dehydration die forced to 2, expected losses per character per day:
##   Day 1: 0 + 2 = 2
##   Day 2: 0 + 2 = 2
##   Day 3: 1 + 2 = 3
##   Day 4: 1 + 2 = 3
##   Day 5: 1 + 2 = 3
##   Day 6: 1 + 2 = 3
##   Day 7: 1 + 2 = 3
## Cumulative for 1 character: 2+2+3+3+3+3+3 = 19 hp lost.


class _FixedDice:
	extends RefCounted
	var _value: int = 2
	func _init(v: int = 2) -> void:
		_value = v
	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		var total := 0
		r.individual_results = []
		for _i in range(count):
			r.individual_results.append(_value)
			total += _value
		r.raw_total = total
		r.modified_total = total + modifier
		return r


func run_all_tests() -> void:
	test_seven_day_no_supplies()
	test_recovery_after_starvation()
	if not has_failures():
		print("WildernessLoopStarvation: all tests passed.")


func _make_party(member_count: int) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_phase3_loop_party"
	pd.character_data = []
	for i in range(member_count):
		var cd := CharacterData.new()
		cd.id = "pc_%d" % i
		cd.hp_max = 30
		cd.hp_current = 30
		pd.character_data.append(cd)
	return pd


func test_seven_day_no_supplies() -> void:
	# Single-character party for clean math. Dice forced to 2 (1d4=2).
	# Expected per-char cumulative HP loss after 7 days:
	#   Day 1: 0 + 2 = 2  (cum 2)
	#   Day 2: 0 + 2 = 2  (cum 4)
	#   Day 3: 1 + 2 = 3  (cum 7)
	#   Day 4: 1 + 2 = 3  (cum 10)
	#   Day 5: 1 + 2 = 3  (cum 13)
	#   Day 6: 1 + 2 = 3  (cum 16)
	#   Day 7: 1 + 2 = 3  (cum 19)
	var party := _make_party(1)
	party.ration_units = 0
	party.water_units = 0
	var dice := _FixedDice.new(2)
	var expected_cumulative := [2, 4, 7, 10, 13, 16, 19]
	var actual_cumulative := []
	var running_total := 0
	for day in range(7):
		var r := SustenanceResolver.apply_daily(party, dice)
		running_total += int(r.get("total_hp_lost", 0))
		actual_cumulative.append(running_total)
	for i in range(7):
		check(actual_cumulative[i] == expected_cumulative[i],
			"day %d cumulative HP loss: expected %d, got %d" %
			[i + 1, expected_cumulative[i], actual_cumulative[i]])
	# Final state
	check(party.starvation_days == 7, "starvation_days=7")
	check(party.dehydration_days == 7, "dehydration_days=7")
	check(SustenanceResolver.is_natural_healing_blocked(party),
		"natural healing blocked on day 7")


func test_recovery_after_starvation() -> void:
	# 4 days of no food, then full rations on day 5 → starvation_days resets to 0,
	# natural healing unblocked on day 5.
	var party := _make_party(2)
	party.ration_units = 0
	party.water_units = 4  # plenty of water — isolate food behavior
	var dice := _FixedDice.new(2)
	for _i in range(4):
		SustenanceResolver.apply_daily(party, dice)
		party.water_units = 4  # refill so dehydration doesn't confound
	check(party.starvation_days == 4, "fixture: starvation_days=4")
	check(SustenanceResolver.is_natural_healing_blocked(party),
		"fixture: healing blocked while starving")
	# Day 5: full rations.
	party.ration_units = 2
	var r := SustenanceResolver.apply_daily(party, dice)
	check(party.starvation_days == 0, "starvation cleared on first day with food")
	check(r.get("total_hp_lost", -1) == 0, "no HP loss on recovery day")
	check(not SustenanceResolver.is_natural_healing_blocked(party),
		"healing unblocked when fed and watered")
	check("starvation_recovery" in r.get("thresholds_crossed", []),
		"recovery threshold emitted")
