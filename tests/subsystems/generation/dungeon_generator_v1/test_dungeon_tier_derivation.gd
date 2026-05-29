extends "res://tests/test_suite_base.gd"

## Tests for DungeonTierDerivation against the gdd-dungeon-generator-v1.md §6
## worked-examples table.


func run_all_tests() -> void:
	test_worked_examples()
	test_clamp_low_and_high()
	test_clamp_fired_detection()
	if not has_failures():
		print("DungeonTierDerivation: all tests passed.")


## _expect(entrance_tier, floor_count, entrance_floor_index, expected_tiers)
func _expect(et: int, fc: int, efi: int, want: Array) -> void:
	var got: Array[int] = DungeonTierDerivation.tiers_for_dungeon(et, fc, efi)
	check(got == want,
		"et=%d fc=%d efi=%d -> expected %s, got %s" % [et, fc, efi, str(want), str(got)])


func test_worked_examples() -> void:
	# §6 table columns are (floor_count, entrance_floor_index, entrance_tier).
	_expect(1, 1, 1, [1])
	_expect(1, 3, 1, [1, 2, 3])
	_expect(2, 3, 2, [3, 2, 3])
	_expect(1, 5, 1, [1, 2, 3, 4, 5])
	_expect(2, 5, 3, [4, 3, 2, 3, 4])
	_expect(1, 6, 1, [1, 2, 3, 4, 5, 6])
	_expect(3, 6, 1, [3, 4, 5, 6, 6, 6])


func test_clamp_low_and_high() -> void:
	check(DungeonTierDerivation.tier_for_floor(1, 1, 1) == 1, "min tier is 1")
	check(DungeonTierDerivation.tier_for_floor(1, 100, 1) == 6, "far floor clamps to 6")


func test_clamp_fired_detection() -> void:
	check(DungeonTierDerivation.clamp_fired(3, 6, 1), "et=3 fc=6 efi=1 should clamp")
	check(not DungeonTierDerivation.clamp_fired(1, 3, 1), "et=1 fc=3 efi=1 should NOT clamp")
