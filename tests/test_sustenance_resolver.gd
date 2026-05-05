extends "res://tests/test_suite_base.gd"

## Unit tests for SustenanceResolver (Wilderness closure Phase 3).
##
## Verifies the SACRED `acore_adventures_and_encounters.xml`
## §rations_and_foraging curves end-to-end:
##   * Daily consumption: 1 unit food + 1 unit water per character per day.
##   * Food: 2-day grace, then 1 hp/day, no natural healing during deficit.
##   * Water: 1 day → 1d4 hp + 1d4/day, healing lost when first die rolled.
##   * Recovery on first day with full sustenance.


# ---------------------------------------------------------------------------
# Fake DiceSystem — fixed return for 1d4 dehydration rolls.
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _forced_value: int = 1
	func _init(forced: int = 1) -> void:
		_forced_value = forced
	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = []
		var total := 0
		for _i in range(count):
			r.individual_results.append(_forced_value)
			total += _forced_value
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (_forced_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_forced_value == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_calm_full_rations()
	test_food_grace_period_no_hp_loss()
	test_food_first_hp_loss_after_grace()
	test_food_recovery_clears_counter()
	test_water_first_loss_immediate()
	test_water_continued_loss_per_day()
	test_water_recovery_clears_counter()
	test_food_and_water_stack()
	test_zero_party_no_op()
	test_natural_healing_blocked_when_starving()
	test_natural_healing_blocked_when_dehydrated()
	test_threshold_signals_fire_on_grace_boundary()
	test_threshold_signals_fire_on_water_first_loss()
	test_consumption_capped_at_cache()
	if not has_failures():
		print("SustenanceResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(member_count: int, ration_units: int, water_units: int) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_phase3_sust_party"
	pd.name = "Test Party"
	pd.ration_units = ration_units
	pd.water_units = water_units
	pd.character_data = []
	for i in range(member_count):
		var cd := CharacterData.new()
		cd.id = "pc_%d" % i
		cd.name = "PC %d" % i
		cd.hp_max = 10
		cd.hp_current = 10
		pd.character_data.append(cd)
	return pd


# ---------------------------------------------------------------------------
# Tests — food
# ---------------------------------------------------------------------------

func test_calm_full_rations() -> void:
	var party := _make_party(4, 4, 4)
	var dice := _FixedDice.new(2)
	var r := SustenanceResolver.apply_daily(party, dice)
	check(r.get("food_consumed", -1) == 4, "consumed 4/4 rations")
	check(r.get("water_consumed", -1) == 4, "consumed 4/4 water")
	check(party.ration_units == 0, "ration_units drained")
	check(party.water_units == 0, "water_units drained")
	check(party.starvation_days == 0, "no starvation")
	check(party.dehydration_days == 0, "no dehydration")
	check(r.get("total_hp_lost", -1) == 0, "no HP loss on calm day")


func test_food_grace_period_no_hp_loss() -> void:
	# Day 1 with 0 food — counter goes to 1 but no HP loss yet (in grace).
	# Refill water each day so dehydration doesn't confound the food-only check.
	var party := _make_party(3, 0, 3)
	var dice := _FixedDice.new(2)
	var r1 := SustenanceResolver.apply_daily(party, dice)
	check(party.starvation_days == 1, "day 1: starvation_days=1")
	check(r1.get("total_hp_lost", -1) == 0, "day 1: no HP loss (grace)")

	party.water_units = 3  # refill to isolate food behavior
	var r2 := SustenanceResolver.apply_daily(party, dice)
	check(party.starvation_days == 2, "day 2: starvation_days=2")
	check(r2.get("total_hp_lost", -1) == 0,
		"day 2: still no HP loss (last grace day per RAW)")


func test_food_first_hp_loss_after_grace() -> void:
	# Day 3 of no food → HP loss begins per RAW "After two days: lose 1 hp/day".
	# Refill water before each tick so dehydration doesn't confound the food curve.
	var party := _make_party(3, 0, 3)
	var dice := _FixedDice.new(2)
	SustenanceResolver.apply_daily(party, dice)  # day 1
	party.water_units = 3
	SustenanceResolver.apply_daily(party, dice)  # day 2
	party.water_units = 3
	var r := SustenanceResolver.apply_daily(party, dice)  # day 3
	check(party.starvation_days == 3, "day 3: starvation_days=3")
	check(r.get("total_hp_lost", -1) == 3,
		"day 3: 3 chars × 1 hp = 3 hp lost; got %d" % r.get("total_hp_lost", -1))
	# Each char individually
	var per_char: Dictionary = r.get("hp_loss_per_character", {})
	check(per_char.size() == 3, "per-char HP loss recorded for all 3 chars")
	for char_id in per_char:
		check(int(per_char[char_id]) == 1,
			"%s lost 1 hp" % char_id)


func test_food_recovery_clears_counter() -> void:
	var party := _make_party(2, 0, 2)
	var dice := _FixedDice.new(2)
	SustenanceResolver.apply_daily(party, dice)  # day 1
	check(party.starvation_days == 1, "fixture: starvation_days=1")
	# Refill caches, run another day.
	party.ration_units = 2
	party.water_units = 2  # also refill water so dehydration doesn't fire
	var r := SustenanceResolver.apply_daily(party, dice)
	check(party.starvation_days == 0, "starvation cleared on full ration day")
	check(r.get("total_hp_lost", -1) == 0, "no HP loss on recovery day")


# ---------------------------------------------------------------------------
# Tests — water
# ---------------------------------------------------------------------------

func test_water_first_loss_immediate() -> void:
	# RAW: "After one day: lose 1d4 hit points."
	var party := _make_party(3, 3, 0)
	var dice := _FixedDice.new(3)  # 1d4 forced to 3
	var r := SustenanceResolver.apply_daily(party, dice)
	check(party.dehydration_days == 1, "dehydration_days=1 after first dry day")
	# 3 chars × 3 hp dehydration = 9
	check(r.get("total_hp_lost", -1) == 9,
		"day 1 dehydration: 3 chars × 3 hp = 9; got %d" % r.get("total_hp_lost", -1))


func test_water_continued_loss_per_day() -> void:
	var party := _make_party(2, 2, 0)
	var dice := _FixedDice.new(4)  # max 1d4 = 4
	SustenanceResolver.apply_daily(party, dice)
	var r2 := SustenanceResolver.apply_daily(party, dice)
	check(party.dehydration_days == 2, "dehydration_days=2 after 2 dry days")
	check(r2.get("total_hp_lost", -1) == 8,
		"day 2: 2 chars × 4 hp = 8; got %d" % r2.get("total_hp_lost", -1))


func test_water_recovery_clears_counter() -> void:
	var party := _make_party(2, 2, 0)
	var dice := _FixedDice.new(2)
	SustenanceResolver.apply_daily(party, dice)
	check(party.dehydration_days == 1, "fixture")
	party.water_units = 2
	var r := SustenanceResolver.apply_daily(party, dice)
	check(party.dehydration_days == 0, "dehydration cleared on full water day")
	check(r.get("total_hp_lost", -1) == 0, "no HP loss on recovery")


# ---------------------------------------------------------------------------
# Tests — combined
# ---------------------------------------------------------------------------

func test_food_and_water_stack() -> void:
	# 3-day starvation + 1-day dehydration: 1 hp starvation + 1d4 hp dehydration
	# per character. With dice=2: 1 + 2 = 3 hp per character.
	var party := _make_party(2, 0, 0)
	var dice := _FixedDice.new(2)
	SustenanceResolver.apply_daily(party, dice)  # day 1: water deficit, no food deficit penalty
	# After day 1: starvation=1 (grace), dehydration=1 → HP loss = 0 + 2 per char = 4
	# Continue
	SustenanceResolver.apply_daily(party, dice)  # day 2: same pattern
	var r := SustenanceResolver.apply_daily(party, dice)  # day 3: starvation > grace
	check(party.starvation_days == 3, "starvation_days=3")
	check(party.dehydration_days == 3, "dehydration_days=3")
	# Day 3: starvation gives 1 hp + dehydration 2 hp = 3 per char × 2 chars = 6
	check(r.get("total_hp_lost", -1) == 6,
		"day 3 combined: 2 chars × (1 + 2) = 6; got %d" % r.get("total_hp_lost", -1))


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_zero_party_no_op() -> void:
	var party := _make_party(0, 5, 5)
	var dice := _FixedDice.new(2)
	var r := SustenanceResolver.apply_daily(party, dice)
	check(r.get("party_size", -1) == 0, "party_size=0 reported")
	check(r.get("total_hp_lost", -1) == 0, "no HP loss on empty party")
	check(party.ration_units == 5, "no consumption on empty party")


func test_natural_healing_blocked_when_starving() -> void:
	var party := _make_party(2, 0, 2)
	var dice := _FixedDice.new(2)
	SustenanceResolver.apply_daily(party, dice)
	SustenanceResolver.apply_daily(party, dice)
	SustenanceResolver.apply_daily(party, dice)  # day 3 — past grace
	check(SustenanceResolver.is_natural_healing_blocked(party),
		"natural healing blocked when starvation > 2 days")


func test_natural_healing_blocked_when_dehydrated() -> void:
	var party := _make_party(2, 2, 0)
	var dice := _FixedDice.new(2)
	SustenanceResolver.apply_daily(party, dice)
	check(SustenanceResolver.is_natural_healing_blocked(party),
		"natural healing blocked on first dehydration day")


func test_threshold_signals_fire_on_grace_boundary() -> void:
	var party := _make_party(2, 0, 2)
	var dice := _FixedDice.new(2)
	SustenanceResolver.apply_daily(party, dice)
	var r := SustenanceResolver.apply_daily(party, dice)
	check("food_grace_expired" in r.get("thresholds_crossed", []),
		"food_grace_expired emitted when starvation_days reaches grace+0 (2)")


func test_threshold_signals_fire_on_water_first_loss() -> void:
	var party := _make_party(2, 2, 0)
	var dice := _FixedDice.new(2)
	var r := SustenanceResolver.apply_daily(party, dice)
	check("water_first_loss" in r.get("thresholds_crossed", []),
		"water_first_loss emitted on first dehydration day")


func test_consumption_capped_at_cache() -> void:
	# Party of 4, only 2 ration_units. Food consumed should be 2 (not 4).
	var party := _make_party(4, 2, 2)
	var dice := _FixedDice.new(2)
	var r := SustenanceResolver.apply_daily(party, dice)
	check(r.get("food_consumed", -1) == 2, "consumption capped at cache")
	check(r.get("food_short", -1) == 2, "food_short = 4 - 2 = 2")
	check(party.ration_units == 0, "ration_units drained to 0 (not negative)")
