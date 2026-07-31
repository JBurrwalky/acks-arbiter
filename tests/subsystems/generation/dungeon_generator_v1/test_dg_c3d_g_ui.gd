extends "res://tests/test_suite_base.gd"

## DG-C3D.G UI coverage: the StairwellData label helpers behind the minimap
## stairwell glyphs + hover tooltips (and the main-view stair tooltip), and the
## placeholder feature meshes (steps / spiral / ramp / parapet). The visual
## rendering itself is verified in-engine; these lock the pure logic that the
## in-engine widgets consume.


func run_all_tests() -> void:
	test_stairwell_covers_and_labels()
	test_generic_and_connector_feature_helpers()
	test_placeholder_meshes_built_for_each_feature()
	if not has_failures():
		print("DgC3dGUi: all tests passed.")


func test_stairwell_covers_and_labels() -> void:
	# A straight run joining ACKS Level 2 (physically upper) and Level 3 (deeper,
	# physically lower). bottom_cell on the lower band (z -2), top_cell on the
	# upper band (z 0).
	var sw := StairwellData.new()
	sw.type = StairwellData.TYPE_STRAIGHT
	sw.lower_band = 3
	sw.upper_band = 2
	sw.bottom_cell = Vector3i(5, 5, -2)
	sw.top_cell = Vector3i(5, 8, 0)
	sw.run_cells = [Vector3i(5, 6, -2), Vector3i(5, 7, -1)]

	check(sw.covers_cell(Vector3i(5, 5, -2)), "covers the bottom landing")
	check(sw.covers_cell(Vector3i(5, 8, 0)), "covers the top landing")
	check(sw.covers_cell(Vector3i(5, 6, -2)), "covers a run cell")
	check(not sw.covers_cell(Vector3i(9, 9, 0)), "does not cover an unrelated cell")

	# Standing on the upper (top) band -> descend to the lower band's level.
	check(sw.label_at(0) == "Stairs down to Level 3",
		"top-band label descends to Level 3, got '%s'" % sw.label_at(0))
	# Standing on the lower band -> ascend to the upper band's level.
	check(sw.label_at(-2) == "Stairs up to Level 2",
		"bottom-band label ascends to Level 2, got '%s'" % sw.label_at(-2))

	# label_for_cell resolves against a list; "" when none covers the cell.
	check(StairwellData.label_for_cell([sw], Vector3i(5, 8, 0)) == "Stairs down to Level 3",
		"label_for_cell resolves the covering stairwell")
	check(StairwellData.label_for_cell([sw], Vector3i(9, 9, 0)) == "",
		"label_for_cell returns '' for an uncovered cell")

	# Type prefixes + the entrance special case.
	var spiral := StairwellData.new()
	spiral.type = StairwellData.TYPE_SPIRAL
	spiral.lower_band = 2
	spiral.upper_band = 1
	spiral.bottom_cell = Vector3i(1, 1, -2)
	spiral.top_cell = Vector3i(1, 1, 0)
	check(spiral.label_at(-2) == "Spiral stair up to Level 1",
		"spiral prefix + ascent, got '%s'" % spiral.label_at(-2))

	var entrance := StairwellData.new()
	entrance.is_entrance = true
	check(entrance.label_at(0) == "Dungeon entrance",
		"the surface entrance labels as the dungeon entrance")


func test_generic_and_connector_feature_helpers() -> void:
	check(StairwellData.generic_label_for_feature("stairs_spiral") == "Spiral stair", "spiral generic")
	check(StairwellData.generic_label_for_feature("stairs_up_N") == "Stairs up", "up generic")
	check(StairwellData.generic_label_for_feature("stairs_down_SW") == "Stairs down", "down generic")
	check(StairwellData.generic_label_for_feature("ramp_E") == "Ramp", "ramp generic")
	check(StairwellData.generic_label_for_feature("open") == "", "non-connector -> no label")

	check(StairwellData.is_connector_feature("stairs_up_N"), "stairs is a connector")
	check(StairwellData.is_connector_feature("stairs_spiral"), "spiral is a connector")
	check(StairwellData.is_connector_feature("ramp_W"), "ramp is a connector")
	check(not StairwellData.is_connector_feature("open"), "open is not a connector")
	check(not StairwellData.is_connector_feature("wall_stone"), "wall is not a connector")


## Every composed connector feature (and the balcony parapet) must produce
## placeholder geometry. Ramps and parapets previously rendered NOTHING — these
## assertions guard that regression.
func test_placeholder_meshes_built_for_each_feature() -> void:
	check(_feature_child_count(_map_with_feature("stairs_up_N")) > 0, "stepped-stair placeholder is built")
	check(_feature_child_count(_map_with_feature("stairs_spiral")) > 0, "spiral placeholder is built")
	check(_feature_child_count(_map_with_feature("ramp_E")) > 0, "ramp placeholder is built (was invisible)")
	check(_feature_child_count(_parapet_map()) > 0, "parapet rail is built (was unrendered)")
	# A plain floor with no features produces no feature meshes.
	check(_feature_child_count(_map_with_feature("open")) == 0, "a plain open cell builds no feature mesh")


func _map_with_feature(feature: String) -> VoxelMapData:
	var m := VoxelMapData.new()
	var c := VoxelCell.new()
	c.col = 5
	c.row = 5
	c.level = 0
	c.solidity = "air"
	c.feature = feature
	c.floor_type = "stone" if feature == "open" else "stone"
	m.set_cell(Vector3i(5, 5, 0), c)
	return m


func _parapet_map() -> VoxelMapData:
	var m := VoxelMapData.new()
	var rail := VoxelCell.new()
	rail.col = 5
	rail.row = 5
	rail.level = 0
	rail.solidity = "air"
	rail.feature = "open"
	rail.floor_type = "wood"
	rail.cover_value = 1
	m.set_cell(Vector3i(5, 5, 0), rail)
	var voidc := VoxelCell.new()
	voidc.col = 5
	voidc.row = 6
	voidc.level = 0
	voidc.solidity = "air"
	voidc.feature = "air_open"
	voidc.floor_type = "none"
	m.set_cell(Vector3i(5, 6, 0), voidc)
	return m


func _feature_child_count(m: VoxelMapData) -> int:
	var node: Node3D = TacticalGrid3D.build_features_voxel(m, 0)
	var n: int = node.get_child_count()
	node.free()
	return n
