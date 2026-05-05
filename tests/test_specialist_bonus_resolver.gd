extends "res://tests/test_suite_base.gd"

## Unit tests for SpecialistBonusResolver (Wilderness closure Phase 6).
##
## Verifies the in-memory `bonus_from_rows` aggregation against fixture
## row sets. The DB-roundtrip path (`bonus_for(...)`) is exercised end-to-end
## in test_specialist_hire_manager.gd.


func run_all_tests() -> void:
	test_empty_rows_returns_zero()
	test_single_pathfinder_lair_search_4()
	test_two_pathfinders_stack_to_8()
	test_pathfinder_does_not_help_surveying()
	test_mixed_specialists_aggregate_per_kind()
	test_unknown_kind_in_row_contributes_zero()
	if not has_failures():
		print("SpecialistBonusResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _row(kind: String) -> Dictionary:
	return {"specialist_id": "test", "kind": kind, "monthly_wage_gp": 25}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_empty_rows_returns_zero() -> void:
	var b := SpecialistBonusResolver.bonus_from_rows(
		[], SpecialistCatalog.KIND_LAIR_SEARCH)
	check(b == 0, "no specialists → 0 bonus")


func test_single_pathfinder_lair_search_4() -> void:
	var b := SpecialistBonusResolver.bonus_from_rows(
		[_row("pathfinder")], SpecialistCatalog.KIND_LAIR_SEARCH)
	check(b == 4, "1 pathfinder → +4 lair_search")


func test_two_pathfinders_stack_to_8() -> void:
	# Phase 6 v1 explicitly STACKS specialist bonuses (RAW doesn't prohibit it).
	var rows := [_row("pathfinder"), _row("pathfinder")]
	var b := SpecialistBonusResolver.bonus_from_rows(
		rows, SpecialistCatalog.KIND_LAIR_SEARCH)
	check(b == 8, "2 pathfinders stack to +8")


func test_pathfinder_does_not_help_surveying() -> void:
	var b := SpecialistBonusResolver.bonus_from_rows(
		[_row("pathfinder")], SpecialistCatalog.KIND_SURVEYING)
	check(b == 0, "pathfinder contributes 0 to surveying")


func test_mixed_specialists_aggregate_per_kind() -> void:
	var rows := [_row("pathfinder"), _row("land_surveyor"), _row("pathfinder")]
	check(SpecialistBonusResolver.bonus_from_rows(
		rows, SpecialistCatalog.KIND_LAIR_SEARCH) == 8,
		"two pathfinders → +8 lair_search; land_surveyor adds 0")
	check(SpecialistBonusResolver.bonus_from_rows(
		rows, SpecialistCatalog.KIND_SURVEYING) == 4,
		"one land_surveyor → +4 surveying")
	check(SpecialistBonusResolver.bonus_from_rows(
		rows, SpecialistCatalog.KIND_TRACKING) == 8,
		"two pathfinders → +8 tracking; land_surveyor adds 0")


func test_unknown_kind_in_row_contributes_zero() -> void:
	# A future migration that adds a new specialist kind shouldn't blow up
	# old game saves that contain unknown rows.
	var rows := [_row("pathfinder"), _row("future_specialist_x")]
	var b := SpecialistBonusResolver.bonus_from_rows(
		rows, SpecialistCatalog.KIND_LAIR_SEARCH)
	check(b == 4, "unknown kind ignored; pathfinder still +4")
