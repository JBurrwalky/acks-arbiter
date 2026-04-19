extends "res://tests/test_suite_base.gd"

## Unit tests for FallingResolver.
##
## Tests fall distance calculation, damage dice, support checking, spike riders,
## and edge cases. Uses hand-built VoxelMapData fixtures.


func run_all_tests() -> void:
	test_has_support_with_floor()
	test_has_support_solid_below()
	test_has_support_ladder()
	test_no_support_air()
	test_fall_already_supported()
	test_fall_one_level_5ft()
	test_fall_two_levels_10ft()
	test_fall_three_levels_15ft()
	test_fall_four_levels_20ft()
	test_fall_twenty_levels_100ft()
	test_fall_lands_on_intermediate_floor()
	test_fall_lands_on_solid_cell()
	test_fall_through_multiple_air_levels()
	test_fall_spike_pit()
	test_fall_no_spikes()
	test_fall_from_absent_cell()
	if not has_failures():
		print("FallingResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helper: build a simple map with a floor at a given level
# ---------------------------------------------------------------------------

func _make_column_map(floor_level: int, floor_type_val: String = "stone") -> VoxelMapData:
	## Creates a map with a single walkable cell at (5, 5, floor_level).
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.floor_type = floor_type_val
	map.set_cell(Vector3i(5, 5, floor_level), cell)
	return map


func _make_solid_at(map: VoxelMapData, level: int) -> void:
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	cell.feature = "rock"
	map.set_cell(Vector3i(5, 5, level), cell)


# ---------------------------------------------------------------------------
# has_support tests
# ---------------------------------------------------------------------------

func test_has_support_with_floor() -> void:
	var map := _make_column_map(0)
	check(FallingResolver.has_support(map, Vector3i(5, 5, 0)) == true,
		"cell with stone floor should have support")


func test_has_support_solid_below() -> void:
	var map := VoxelMapData.new()
	_make_solid_at(map, 2)
	# Cell at level 3 has no floor but solid below at level 2
	check(FallingResolver.has_support(map, Vector3i(5, 5, 3)) == true,
		"cell above solid should have support")


func test_has_support_ladder() -> void:
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.feature = "ladder"
	map.set_cell(Vector3i(5, 5, 4), cell)
	check(FallingResolver.has_support(map, Vector3i(5, 5, 4)) == true,
		"cell with ladder feature should have support")


func test_no_support_air() -> void:
	var map := VoxelMapData.new()
	check(FallingResolver.has_support(map, Vector3i(5, 5, 5)) == false,
		"empty air cell should not have support")


# ---------------------------------------------------------------------------
# resolve_fall tests
# ---------------------------------------------------------------------------

func test_fall_already_supported() -> void:
	var map := _make_column_map(3)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 3))
	check(result["landing_pos"] == Vector3i(5, 5, 3), "should not fall if supported")
	check(result["distance_feet"] == 0, "distance should be 0")
	check(result["damage_dice"] == 0, "damage should be 0d6")


func test_fall_one_level_5ft() -> void:
	# From level 1, floor at level 0 -> 5ft fall, 0d6
	var map := _make_column_map(0)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 1))
	check(result["landing_pos"] == Vector3i(5, 5, 0), "should land at level 0")
	check(result["distance_feet"] == 5, "should fall 5ft")
	check(result["damage_dice"] == 0, "5ft = 0d6 (floor(5/10)=0)")


func test_fall_two_levels_10ft() -> void:
	var map := _make_column_map(0)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 2))
	check(result["landing_pos"] == Vector3i(5, 5, 0), "should land at level 0")
	check(result["distance_feet"] == 10, "should fall 10ft")
	check(result["damage_dice"] == 1, "10ft = 1d6")


func test_fall_three_levels_15ft() -> void:
	var map := _make_column_map(0)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 3))
	check(result["distance_feet"] == 15, "should fall 15ft")
	check(result["damage_dice"] == 1, "15ft = 1d6 (floor(15/10)=1)")


func test_fall_four_levels_20ft() -> void:
	var map := _make_column_map(0)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 4))
	check(result["distance_feet"] == 20, "should fall 20ft")
	check(result["damage_dice"] == 2, "20ft = 2d6")


func test_fall_twenty_levels_100ft() -> void:
	var map := _make_column_map(0)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 20))
	check(result["distance_feet"] == 100, "should fall 100ft")
	check(result["damage_dice"] == 10, "100ft = 10d6")


func test_fall_lands_on_intermediate_floor() -> void:
	# Floor at level 2, falling from level 4 -> 10ft fall
	var map := _make_column_map(2)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 4))
	check(result["landing_pos"] == Vector3i(5, 5, 2), "should land at level 2")
	check(result["distance_feet"] == 10, "should fall 10ft")
	check(result["damage_dice"] == 1, "10ft = 1d6")


func test_fall_lands_on_solid_cell() -> void:
	# Solid rock at level 1, falling from level 4 -> lands at level 2 (on top of solid)
	var map := VoxelMapData.new()
	_make_solid_at(map, 1)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 4))
	check(result["landing_pos"] == Vector3i(5, 5, 2),
		"should land one level above solid, got %s" % str(result["landing_pos"]))
	check(result["distance_feet"] == 10, "should fall 10ft")


func test_fall_through_multiple_air_levels() -> void:
	# Floor only at level 0, falling from level 8 -> 40ft fall
	var map := _make_column_map(0)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 8))
	check(result["landing_pos"] == Vector3i(5, 5, 0), "should land at level 0")
	check(result["distance_feet"] == 40, "should fall 40ft")
	check(result["damage_dice"] == 4, "40ft = 4d6")


func test_fall_spike_pit() -> void:
	# Floor at level 0 with spikes
	var map := VoxelMapData.new()
	var cell := VoxelCell.new()
	cell.floor_type = "stone"
	cell.feature = "spike_pit"
	map.set_cell(Vector3i(5, 5, 0), cell)

	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 2))
	check(result["spike_dice"] == 1, "spike pit should add 1 spike die")
	check(result["damage_dice"] == 1, "10ft fall = 1d6 base")


func test_fall_no_spikes() -> void:
	var map := _make_column_map(0)
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 2))
	check(result["spike_dice"] == 0, "no spikes = 0 spike dice")


func test_fall_from_absent_cell() -> void:
	# Empty map — absent cells are sentinel air with no floor.
	# Falling from level 5 in an empty map should eventually hit MIN_LEVEL.
	var map := VoxelMapData.new()
	var result := FallingResolver.resolve_fall(map, Vector3i(5, 5, 5))
	check(result["landing_pos"].z == FallingResolver.MIN_LEVEL,
		"should fall to MIN_LEVEL in empty map, got level %d" % result["landing_pos"].z)
	var expected_feet: int = (5 - FallingResolver.MIN_LEVEL) * 5
	check(result["distance_feet"] == expected_feet,
		"distance should be %d, got %d" % [expected_feet, result["distance_feet"]])
