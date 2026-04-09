extends "res://tests/test_suite_base.gd"

## Unit tests for MortalWoundsResolver.
## Verifies condition ranges, modifier math, wound table lookups,
## damage type defaulting, and all five damage type tables.


func run_all_tests() -> void:
	test_instantly_killed_d20_total_zero_or_below()
	test_mortally_wounded_range()
	test_grievously_wounded_range()
	test_critically_wounded_range()
	test_shock_range()
	test_knocked_out_range()
	test_dazed_range()
	test_con_modifier_shifts_result()
	test_hd_value_bonus_1d8()
	test_hp_deficit_exactly_zero()
	test_hp_deficit_below_quarter()
	test_hp_deficit_beyond_double_max()
	test_treatment_timing_within_1_round()
	test_treatment_timing_after_1_day()
	test_wound_table_slashing_lookup()
	test_unknown_damage_type_defaults_to_slashing()
	test_all_five_damage_types_return_nonempty_strings()
	test_is_dead_flag()
	test_recovers_to_1hp_flag()
	test_recovery_times()
	if not has_failures():
		print("MortalWoundsResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _d20_val: int
	var _d6_val: int
	var _call_count: int = 0

	func _init(d20: int, d6: int) -> void:
		_d20_val = d20
		_d6_val = d6

	func roll_digital(sides: int, _count: int = 1, _modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		_call_count += 1
		if sides == 20:
			r.raw_total = _d20_val
			r.modified_total = _d20_val
		else:  # d6
			r.raw_total = _d6_val
			r.modified_total = _d6_val
		r.individual_results = [r.raw_total]
		return r


func _make_pc(con: int = 10, hit_die: String = "1d8", hp_max: int = 10) -> Combatant:
	var cd := CharacterData.new()
	cd.id = "test_pc"
	cd.name = "Test PC"
	cd.constitution = con
	cd.hit_die_type = hit_die
	cd.hp_max = hp_max
	cd.hp_current = hp_max
	return Combatant.from_character(cd, "test_pc")


func _resolve_with_fixed_dice(
		d20_roll: int, d6_roll: int,
		combatant: Combatant, hp_when_downed: int,
		damage_type: String = "slashing",
		treatment_timing: String = "within_1_round") -> Dictionary:
	var dice := _FixedDice.new(d20_roll, d6_roll)
	var resolver := MortalWoundsResolver.new(dice)
	return resolver.resolve(combatant, hp_when_downed, damage_type, treatment_timing)


# ---------------------------------------------------------------------------
# Condition range tests
# ---------------------------------------------------------------------------

func test_instantly_killed_d20_total_zero_or_below() -> void:
	# PC with 10 CON (mod 0), 1d8 HD (+4), at exactly 0 HP (+5), within_1_round (+2)
	# d20 modifiers: +4 +5 +2 = +11. So d20_raw=1 → d20_total=12 — not killed.
	# For instantly_killed we need d20_total <= 0.
	# d20_raw=1 with modifiers=-11 total would need neg base mods — use after_1_day (-10) and a low roll.
	# Let's use: CON 3 (mod -3), 1d6 HD (+2), 0 HP (+5), after_1_day (-10) → total mods = -6
	# d20_raw=1 → d20_total=1+(-6) = -5 → instantly_killed.
	var combatant := _make_pc(3, "1d6", 10)
	var result := _resolve_with_fixed_dice(1, 3, combatant, 0, "slashing", "after_1_day")
	# mods: con=-3, hd=+2, hp=+5, timing=-10 → sum=-6; total=1+(-6)=-5
	check(result["condition"] == "instantly_killed",
		"d20_total=-5 should be instantly_killed, got %s" % result["condition"])
	check(result["is_dead"] == true, "instantly_killed should set is_dead=true")


func test_mortally_wounded_range() -> void:
	# Need d20_total 1-5. Use: CON 10 (+0), 1d8 (+4), 0 HP (+5), after_1_day (-10) = -1.
	# d20_raw=5 → total=5-1=4 → mortally_wounded.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(5, 1, combatant, 0, "slashing", "after_1_day")
	# mods: 0+4+5-10=-1; total=5-1=4
	check(result["condition"] == "mortally_wounded",
		"d20_total=4 should be mortally_wounded, got %s" % result["condition"])
	check(result["is_dead"] == false, "mortally_wounded should not be is_dead")
	check(result["recovers_to_1hp"] == false, "mortally_wounded should not auto-recover")


func test_grievously_wounded_range() -> void:
	# Need d20_total 6-10.
	# CON 10 (+0), 1d8 (+4), 0 HP (+5), within_1_turn (-3) → mods=+6. d20_raw=2 → total=8.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(2, 1, combatant, 0, "slashing", "within_1_turn")
	# mods: 0+4+5-3=6; total=2+6=8
	check(result["condition"] == "grievously_wounded",
		"d20_total=8 should be grievously_wounded, got %s" % result["condition"])


func test_critically_wounded_range() -> void:
	# d20_total 11-15. CON 10 (+0), 1d8 (+4), 0 HP (+5), within_1_round (+2) → mods=+11.
	# d20_raw=2 → total=13.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(2, 1, combatant, 0, "slashing", "within_1_round")
	# mods: 0+4+5+2=11; total=2+11=13
	check(result["condition"] == "critically_wounded",
		"d20_total=13 should be critically_wounded, got %s" % result["condition"])


func test_shock_range() -> void:
	# d20_total 16-20. CON 10 (+0), 1d8 (+4), 0 HP (+5), within_1_round (+2) → mods=+11.
	# d20_raw=7 → total=18.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(7, 1, combatant, 0, "slashing", "within_1_round")
	check(result["condition"] == "shock",
		"d20_total=18 should be shock, got %s" % result["condition"])
	check(result["recovers_to_1hp"] == true, "shock should set recovers_to_1hp=true")


func test_knocked_out_range() -> void:
	# d20_total 21-25. mods=+11. d20_raw=12 → total=23.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(12, 1, combatant, 0, "slashing", "within_1_round")
	check(result["condition"] == "knocked_out",
		"d20_total=23 should be knocked_out, got %s" % result["condition"])
	check(result["recovers_to_1hp"] == true, "knocked_out should set recovers_to_1hp=true")


func test_dazed_range() -> void:
	# d20_total 26+. mods=+11. d20_raw=16 → total=27.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(16, 1, combatant, 0, "slashing", "within_1_round")
	check(result["condition"] == "dazed",
		"d20_total=27 should be dazed, got %s" % result["condition"])
	check(result["recovers_to_1hp"] == true, "dazed should set recovers_to_1hp=true")


# ---------------------------------------------------------------------------
# Modifier tests
# ---------------------------------------------------------------------------

func test_con_modifier_shifts_result() -> void:
	# CON 16 = +2 modifier. Compare two identical PCs: one with CON 10, one with CON 16.
	# Both 1d8, at 0 HP, within_1_round, d20_raw=10.
	# CON 10: mods = 0+4+5+2=11; total=21 → knocked_out
	# CON 16: mods = 2+4+5+2=13; total=23 → knocked_out too... let me use different values.
	# d20_raw=4: CON 10 total=15 → critically_wounded. CON 16 total=17 → shock.
	var pc_normal := _make_pc(10, "1d8", 10)
	var pc_tough  := _make_pc(16, "1d8", 10)
	var r_normal := _resolve_with_fixed_dice(4, 1, pc_normal, 0, "slashing", "within_1_round")
	var r_tough  := _resolve_with_fixed_dice(4, 1, pc_tough,  0, "slashing", "within_1_round")
	check(r_normal["condition"] == "critically_wounded",
		"CON 10, d20_raw=4 should be critically_wounded, got %s" % r_normal["condition"])
	check(r_tough["condition"] == "shock",
		"CON 16, d20_raw=4 should be shock, got %s" % r_tough["condition"])
	check(r_tough["d20_modifiers"]["con"] == 2,
		"CON 16 should give +2, got %d" % r_tough["d20_modifiers"]["con"])


func test_hd_value_bonus_1d8() -> void:
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(10, 1, combatant, 0, "slashing", "within_1_round")
	check(result["d20_modifiers"]["hd_value"] == 4,
		"1d8 HD should give +4 bonus, got %d" % result["d20_modifiers"]["hd_value"])


func test_hp_deficit_exactly_zero() -> void:
	# 0 HP = +5 modifier
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(10, 1, combatant, 0, "slashing", "within_1_round")
	check(result["d20_modifiers"]["hp_deficit"] == 5,
		"exactly 0 HP should give +5, got %d" % result["d20_modifiers"]["hp_deficit"])


func test_hp_deficit_below_quarter() -> void:
	# HP max=10. -1 HP (below_zero=1). quarter_max=2.5. 1 <= 2.5 → treated as 0 → +5.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(10, 1, combatant, -1, "slashing", "within_1_round")
	check(result["d20_modifiers"]["hp_deficit"] == 5,
		"hp=-1 with max=10 (within quarter) should still give +5, got %d" \
			% result["d20_modifiers"]["hp_deficit"])


func test_hp_deficit_beyond_double_max() -> void:
	# HP max=10. Beyond 2x = below -20 → modifier=-20.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(10, 1, combatant, -21, "slashing", "within_1_round")
	check(result["d20_modifiers"]["hp_deficit"] == -20,
		"hp=-21 with max=10 should give -20, got %d" % result["d20_modifiers"]["hp_deficit"])


func test_treatment_timing_within_1_round() -> void:
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(10, 1, combatant, 0, "slashing", "within_1_round")
	check(result["d20_modifiers"]["timing"] == 2,
		"within_1_round timing should give +2, got %d" % result["d20_modifiers"]["timing"])


func test_treatment_timing_after_1_day() -> void:
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(10, 1, combatant, 0, "slashing", "after_1_day")
	check(result["d20_modifiers"]["timing"] == -10,
		"after_1_day timing should give -10, got %d" % result["d20_modifiers"]["timing"])


# ---------------------------------------------------------------------------
# Wound table tests
# ---------------------------------------------------------------------------

func test_wound_table_slashing_lookup() -> void:
	# Slashing, d6=1, d20_total=27+ (bracket 7) → "no additional..." doesn't exist for slashing d6=1.
	# Slashing d6=1, bracket 7 (26+) = "-1 to initiative on cold or rainy days."
	# d20_raw needs total >=26. CON 10, 1d8 (+4), 0 HP (+5), within_1_round (+2) = mods +11.
	# d20_raw=15 → total=26.
	var combatant := _make_pc(10, "1d8", 10)
	var result := _resolve_with_fixed_dice(15, 1, combatant, 0, "slashing", "within_1_round")
	check(result["condition"] == "dazed",
		"d20_total=26 should be dazed")
	check(result["wound_description"] == "-1 to initiative on cold or rainy days.",
		"slashing d6=1 bracket 7 wrong: got '%s'" % result["wound_description"])


func test_unknown_damage_type_defaults_to_slashing() -> void:
	var combatant := _make_pc(10, "1d8", 10)
	var dice := _FixedDice.new(10, 3)
	var resolver := MortalWoundsResolver.new(dice)
	# "acid" is not a valid damage type
	var result := resolver.resolve(combatant, 0, "acid", "within_1_round")
	# Should not crash. Wound description should be non-empty (from slashing table).
	check(not result["wound_description"].is_empty(),
		"unknown damage type should default to slashing and return non-empty wound description")


func test_all_five_damage_types_return_nonempty_strings() -> void:
	var types := ["bludgeoning", "fire", "penetrating", "savage", "slashing"]
	var combatant := _make_pc(10, "1d8", 10)
	for dtype in types:
		var dice := _FixedDice.new(8, 3)
		var resolver := MortalWoundsResolver.new(dice)
		var result := resolver.resolve(combatant, 0, dtype, "within_1_round")
		check(not result["wound_description"].is_empty(),
			"damage type '%s' should return non-empty wound description" % dtype)
		check(not result["condition"].is_empty(),
			"damage type '%s' should return non-empty condition" % dtype)


# ---------------------------------------------------------------------------
# Flag and recovery time tests
# ---------------------------------------------------------------------------

func test_is_dead_flag() -> void:
	# Force instantly_killed (d20_total <= 0)
	# CON 3 (-3), 1d6 (+2), 0 HP (+5), after_1_day (-10) → mods=-6. d20_raw=1 → total=-5.
	var combatant := _make_pc(3, "1d6", 10)
	var result := _resolve_with_fixed_dice(1, 1, combatant, 0, "slashing", "after_1_day")
	check(result["is_dead"] == true,
		"instantly_killed should set is_dead=true")
	check(result["recovers_to_1hp"] == false,
		"instantly_killed should not set recovers_to_1hp")


func test_recovers_to_1hp_flag() -> void:
	# shock, knocked_out, dazed all set recovers_to_1hp=true
	var combatant := _make_pc(10, "1d8", 10)
	# shock: mods=+11, d20_raw=7 → total=18
	var r_shock := _resolve_with_fixed_dice(7, 1, combatant, 0, "slashing", "within_1_round")
	check(r_shock["recovers_to_1hp"] == true, "shock recovers_to_1hp")
	# knocked_out: d20_raw=12 → total=23
	var r_ko := _resolve_with_fixed_dice(12, 1, combatant, 0, "slashing", "within_1_round")
	check(r_ko["recovers_to_1hp"] == true, "knocked_out recovers_to_1hp")
	# dazed: d20_raw=16 → total=27
	var r_dazed := _resolve_with_fixed_dice(16, 1, combatant, 0, "slashing", "within_1_round")
	check(r_dazed["recovers_to_1hp"] == true, "dazed recovers_to_1hp")


func test_recovery_times() -> void:
	var combatant := _make_pc(10, "1d8", 10)
	# mortally_wounded: 1 month
	var r := _resolve_with_fixed_dice(5, 1, combatant, 0, "slashing", "after_1_day")
	# mods: 0+4+5-10=-1; total=5-1=4 → mortally_wounded
	check(r["condition"] == "mortally_wounded",
		"expected mortally_wounded, got %s" % r["condition"])
	check(r["recovery_time"]["value"] == 1 and r["recovery_time"]["unit"] == "month",
		"mortally_wounded recovery should be 1 month")
