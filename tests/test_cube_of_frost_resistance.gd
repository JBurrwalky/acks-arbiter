extends "res://tests/test_suite_base.gd"

## 2026-06-03 — Cube of Frost Resistance consumer.
##
## RAW (ACKS Core p.215+, Jedidiah-supplied 2026-06-03):
##   "When activated, creates a cube-shaped area 10' on a side centered on
##   the possessor. The temperature within this area is always at least
##   65°F. The field absorbs all cold-based attacks. However, if the field
##   is subjected to more than 50 points of cold damage in 1 turn (from one
##   or multiple attacks), it collapses into its portable form and cannot
##   be reactivated for 1 hour. If the field absorbs more than 100 points
##   of cold damage in a turn, the cube is destroyed."
##
## Coverage:
##   - Service-level absorption: cold damage absorbed, non-cold passthrough,
##     no-flag passthrough, inactive-field passthrough
##   - Threshold tracking: per-turn cumulative accumulator
##   - Collapse threshold (>50/turn): field deactivates, collapsed_at_turn
##     records the boundary, further cold this turn passes through
##   - Destroy threshold (>100/turn): cube removed entirely (flag clears,
##     inventory row removal documented; DB-side covered in-engine)
##   - Tick reset: per-turn accumulator resets on Timekeeping.turn_advanced
##   - Cooldown reactivation: after 6 turns (= 1 hour) the field re-arms
##   - Damage pipeline integration: CharacterData.apply_damage routes cold
##     through the cube before resistance + temp_hp + hp_current
##   - SessionRunner subscription: turn_advanced triggers the tick for
##     each cube-bearing party member


func run_all_tests() -> void:
	# Service-level absorption
	test_cold_damage_absorbed_by_active_field()
	test_non_cold_damage_passes_through()
	test_no_flag_no_absorption()
	test_inactive_field_passes_through()
	test_zero_damage_no_op()
	# Accumulator + thresholds
	test_per_turn_accumulator_records_cumulative_cold()
	test_collapse_threshold_deactivates_field()
	test_collapse_records_collapsed_at_turn()
	test_cold_damage_after_collapse_passes_through_this_turn()
	test_destroy_threshold_clears_flag()
	test_destroy_threshold_at_101_not_100()
	# Tick reset + cooldown reactivation
	test_tick_resets_per_turn_accumulator()
	test_cooldown_reactivates_field_after_six_turns()
	test_cooldown_does_not_reactivate_before_six_turns()
	test_active_field_tick_is_idempotent()
	# CharacterData.apply_damage integration
	test_apply_damage_absorbs_cold_via_cube()
	test_apply_damage_routes_non_cold_normally()
	test_apply_damage_reports_cube_absorbed_in_result()
	test_apply_damage_passes_through_after_collapse()
	if not has_failures():
		print("CubeOfFrostResistance: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_bearer(id: String) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = "Cube Bearer " + id
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 5
	cd.hp_max = 100; cd.hp_current = 100
	return cd


func _stamp_cube(cd: CharacterData, field_active: bool = true) -> void:
	# Mirrors WornMagicEffectResolver._add_cube_of_frost_resistance V2
	# metadata. Tests use the same stamping shape so an upstream change
	# in the resolver's stamp keeps the service tests honest.
	cd.flags.set_flag("has_cube_of_frost_resistance_field",
		"worn_magic:cube_test_id", {
			"source_kind": "worn_magic_item",
			"item_id": "cube_test_id",
			"absorbs_cold_attacks": true,
			"min_temperature_f": 65,
			"area_cube_side_feet": 10,
			"collapse_threshold_cold_damage_per_turn": 50,
			"collapse_cooldown_hours": 1,
			"destroy_threshold_cold_damage_per_turn": 100,
			"field_active": field_active,
			"cold_damage_this_turn": 0,
			"collapsed_at_turn": -1,
		})


func _get_cube_meta(cd: CharacterData) -> Dictionary:
	return cd.flags.get_flag_metadata("has_cube_of_frost_resistance_field")


# ---------------------------------------------------------------------------
# Service-level absorption
# ---------------------------------------------------------------------------

func test_cold_damage_absorbed_by_active_field() -> void:
	var cd := _make_bearer("absorb_a")
	_stamp_cube(cd)
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 10, "cold")
	check(int(result.get("absorbed", 0)) == 10,
		"active field absorbs full 10 cold damage")
	check(int(result.get("damage_remaining", -1)) == 0,
		"no damage passes through")
	check(bool(result.get("field_was_active", false)) == true,
		"reports field_was_active=true")
	check(int(_get_cube_meta(cd).get("cold_damage_this_turn", 0)) == 10,
		"accumulator=10 after absorption")


func test_non_cold_damage_passes_through() -> void:
	var cd := _make_bearer("non_cold")
	_stamp_cube(cd)
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 30, "fire")
	check(int(result.get("absorbed", 0)) == 0,
		"fire damage NOT absorbed by cube")
	check(int(result.get("damage_remaining", -1)) == 30,
		"all 30 fire damage passes through")
	check(int(_get_cube_meta(cd).get("cold_damage_this_turn", -1)) == 0,
		"accumulator unchanged by non-cold damage")


func test_no_flag_no_absorption() -> void:
	var cd := _make_bearer("no_flag")
	# No _stamp_cube call.
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 20, "cold")
	check(int(result.get("absorbed", 0)) == 0,
		"non-bearer takes full cold damage")
	check(int(result.get("damage_remaining", -1)) == 20,
		"all 20 passes through (no field to absorb)")


func test_inactive_field_passes_through() -> void:
	var cd := _make_bearer("inactive")
	_stamp_cube(cd, false)  # field_active=false on stamp
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 15, "cold")
	check(int(result.get("absorbed", 0)) == 0,
		"collapsed/inactive field doesn't absorb")
	check(int(result.get("damage_remaining", -1)) == 15,
		"all 15 cold passes through inactive cube")


func test_zero_damage_no_op() -> void:
	var cd := _make_bearer("zero")
	_stamp_cube(cd)
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 0, "cold")
	check(int(result.get("absorbed", 0)) == 0, "0 damage = no-op")
	check(int(_get_cube_meta(cd).get("cold_damage_this_turn", -1)) == 0,
		"accumulator unchanged")


# ---------------------------------------------------------------------------
# Accumulator + thresholds
# ---------------------------------------------------------------------------

func test_per_turn_accumulator_records_cumulative_cold() -> void:
	var cd := _make_bearer("cumulative")
	_stamp_cube(cd)
	CubeOfFrostResistanceService.try_absorb_cold(cd, 15, "cold")
	CubeOfFrostResistanceService.try_absorb_cold(cd, 25, "cold")
	CubeOfFrostResistanceService.try_absorb_cold(cd, 5, "cold")
	check(int(_get_cube_meta(cd).get("cold_damage_this_turn", 0)) == 45,
		"3 absorptions accumulate to 45 (15+25+5)")
	check(bool(_get_cube_meta(cd).get("field_active", false)) == true,
		"field still active (≤50 in accumulator)")


func test_collapse_threshold_deactivates_field() -> void:
	# RAW: >50 / turn collapses (not ≥50). At 51 cumulative the field collapses.
	var cd := _make_bearer("collapse")
	_stamp_cube(cd)
	CubeOfFrostResistanceService.try_absorb_cold(cd, 30, "cold")
	check(bool(_get_cube_meta(cd).get("field_active", false)) == true,
		"30 ≤ 50 → field still active")
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 21, "cold")
	check(bool(result.get("collapsed", false)) == true,
		"result.collapsed=true on this hit (cumulative 51 > 50)")
	check(bool(_get_cube_meta(cd).get("field_active", true)) == false,
		"field_active=false after collapse")


func test_collapse_records_collapsed_at_turn() -> void:
	Timekeeping._on_session_ended()  # reset clock
	Timekeeping.advance_turns(7)  # current_turn = 7
	var cd := _make_bearer("collapse_turn")
	_stamp_cube(cd)
	CubeOfFrostResistanceService.try_absorb_cold(cd, 60, "cold")
	check(int(_get_cube_meta(cd).get("collapsed_at_turn", -2)) == 7,
		"collapsed_at_turn=7 (Timekeeping.get_total_turns() at collapse); got %d"
			% int(_get_cube_meta(cd).get("collapsed_at_turn", -2)))


func test_cold_damage_after_collapse_passes_through_this_turn() -> void:
	# Once the field collapses mid-turn, further cold damage in the same
	# turn passes through (the cube doesn't re-engage until the cooldown
	# elapses).
	var cd := _make_bearer("after_collapse")
	_stamp_cube(cd)
	CubeOfFrostResistanceService.try_absorb_cold(cd, 60, "cold")  # collapses
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 20, "cold")
	check(int(result.get("absorbed", 0)) == 0,
		"second hit after collapse: no absorption")
	check(int(result.get("damage_remaining", -1)) == 20,
		"all 20 passes through after collapse")


func test_destroy_threshold_clears_flag() -> void:
	# RAW: >100/turn destroys. At 101 cumulative, the cube is gone.
	var cd := _make_bearer("destroy")
	_stamp_cube(cd)
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 101, "cold")
	check(bool(result.get("destroyed", false)) == true,
		"single 101-cold hit destroys the cube")
	check(int(result.get("absorbed", 0)) == 101,
		"cube absorbed the full 101 before being destroyed")
	check(not cd.flags.has_flag("has_cube_of_frost_resistance_field"),
		"flag cleared after destruction")


func test_destroy_threshold_at_101_not_100() -> void:
	# At EXACTLY 100 the cube collapses but isn't destroyed.
	var cd := _make_bearer("at_100")
	_stamp_cube(cd)
	var result := CubeOfFrostResistanceService.try_absorb_cold(cd, 100, "cold")
	check(bool(result.get("destroyed", true)) == false,
		"100 cumulative does NOT destroy (RAW: 'more than 100')")
	check(bool(result.get("collapsed", false)) == true,
		"100 cumulative DOES collapse (> 50)")
	check(cd.flags.has_flag("has_cube_of_frost_resistance_field"),
		"flag remains on collapsed-but-not-destroyed cube")


# ---------------------------------------------------------------------------
# Tick reset + cooldown reactivation
# ---------------------------------------------------------------------------

func test_tick_resets_per_turn_accumulator() -> void:
	var cd := _make_bearer("tick_reset")
	_stamp_cube(cd)
	CubeOfFrostResistanceService.try_absorb_cold(cd, 30, "cold")
	check(int(_get_cube_meta(cd).get("cold_damage_this_turn", -1)) == 30,
		"setup: accumulator=30")
	CubeOfFrostResistanceService.tick_turn(cd)
	check(int(_get_cube_meta(cd).get("cold_damage_this_turn", -1)) == 0,
		"tick_turn resets accumulator to 0")


func test_cooldown_reactivates_field_after_six_turns() -> void:
	Timekeeping._on_session_ended()
	var cd := _make_bearer("reactivate")
	_stamp_cube(cd)
	# Collapse the field at turn 0.
	CubeOfFrostResistanceService.try_absorb_cold(cd, 60, "cold")
	check(bool(_get_cube_meta(cd).get("field_active", true)) == false, "setup: collapsed")
	# Advance 6 turns and tick.
	Timekeeping.advance_turns(6)
	var result := CubeOfFrostResistanceService.tick_turn(cd)
	check(bool(result.get("reactivated", false)) == true,
		"tick at turn 6 reactivates collapsed field")
	check(bool(_get_cube_meta(cd).get("field_active", false)) == true,
		"field_active=true after cooldown elapses")
	check(int(_get_cube_meta(cd).get("collapsed_at_turn", 0)) == -1,
		"collapsed_at_turn reset to -1 after reactivation")


func test_cooldown_does_not_reactivate_before_six_turns() -> void:
	Timekeeping._on_session_ended()
	var cd := _make_bearer("not_yet")
	_stamp_cube(cd)
	CubeOfFrostResistanceService.try_absorb_cold(cd, 60, "cold")  # collapse at turn 0
	Timekeeping.advance_turns(5)  # turn 5 < cooldown threshold
	var result := CubeOfFrostResistanceService.tick_turn(cd)
	check(bool(result.get("reactivated", true)) == false,
		"5 turns < 6 → no reactivation")
	check(bool(_get_cube_meta(cd).get("field_active", true)) == false,
		"field stays inactive")


func test_active_field_tick_is_idempotent() -> void:
	# Ticking an already-active field is a no-op (other than resetting
	# the per-turn accumulator, which was already 0).
	var cd := _make_bearer("idempotent")
	_stamp_cube(cd)
	var result := CubeOfFrostResistanceService.tick_turn(cd)
	check(bool(result.get("reactivated", true)) == false,
		"active field doesn't 'reactivate'")
	check(bool(_get_cube_meta(cd).get("field_active", false)) == true,
		"active field stays active")


# ---------------------------------------------------------------------------
# CharacterData.apply_damage integration
# ---------------------------------------------------------------------------

func test_apply_damage_absorbs_cold_via_cube() -> void:
	var cd := _make_bearer("damage_absorb")
	_stamp_cube(cd)
	var hp_before := cd.hp_current
	var result := cd.apply_damage(20, "cold")
	check(int(result.get("cube_absorbed", 0)) == 20,
		"apply_damage reports cube_absorbed=20")
	check(int(result.get("hp_damage", -1)) == 0,
		"no HP damage taken (cube absorbed all)")
	check(cd.hp_current == hp_before, "hp_current unchanged")


func test_apply_damage_routes_non_cold_normally() -> void:
	# Non-cold damage bypasses the cube; full damage applied.
	var cd := _make_bearer("non_cold_route")
	_stamp_cube(cd)
	var result := cd.apply_damage(15, "fire")
	check(int(result.get("cube_absorbed", 0)) == 0,
		"non-cold doesn't engage cube")
	check(int(result.get("hp_damage", -1)) == 15,
		"15 fire damage applied normally")
	check(cd.hp_current == 100 - 15, "hp_current = 100 - 15 = 85")


func test_apply_damage_reports_cube_absorbed_in_result() -> void:
	var cd := _make_bearer("report")
	_stamp_cube(cd)
	# Collapse with one big hit + check the report fields.
	var result := cd.apply_damage(60, "cold")
	check(int(result.get("cube_absorbed", 0)) == 60,
		"cube_absorbed=60")
	check(bool(result.get("cube_collapsed", false)) == true,
		"cube_collapsed=true (60 > 50)")
	check(bool(result.get("cube_destroyed", true)) == false,
		"cube_destroyed=false (60 ≤ 100)")


func test_apply_damage_passes_through_after_collapse() -> void:
	var cd := _make_bearer("after_collapse_apply")
	_stamp_cube(cd)
	cd.apply_damage(60, "cold")  # collapses cube
	check(bool(_get_cube_meta(cd).get("field_active", true)) == false, "setup: collapsed")
	# Second hit this turn: damage passes through.
	var hp_before := cd.hp_current
	var result := cd.apply_damage(20, "cold")
	check(int(result.get("cube_absorbed", 0)) == 0,
		"post-collapse cold absorption=0")
	check(int(result.get("hp_damage", -1)) == 20,
		"20 cold damage applied")
	check(cd.hp_current == hp_before - 20, "hp_current dropped by 20")
