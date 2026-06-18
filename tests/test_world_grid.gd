extends "res://tests/test_suite_base.gd"

## Unit tests for WorldGrid — the offset-rectangle <-> axial geometry the setting
## generator lays worlds on so they render as rectangles, not parallelograms.


func run_all_tests() -> void:
	test_offset_axial_roundtrip()
	test_offset_to_axial_matches_hex_map_controller()
	test_enumerate_size_is_w_times_h()
	test_enumerate_keys_unique()
	test_enumerate_renders_as_rectangle()
	test_enumerate_sorted_canonical()
	test_enumerate_row_zero_is_top()
	test_adjacency_preserved_within_grid()
	if not has_failures():
		print("WorldGrid: all tests passed.")


func test_offset_axial_roundtrip() -> void:
	for row in range(0, 20):
		for col in range(0, 25):
			var key := WorldGrid.offset_to_axial(col, row)
			var back := WorldGrid.axial_to_offset(key)
			check(back == Vector2i(col, row),
				"offset (%d,%d) -> axial %s -> offset %s should round-trip" % [col, row, str(key), str(back)])


func test_offset_to_axial_matches_hex_map_controller() -> void:
	# Single source of truth: WorldGrid MUST use the same even-q transform the
	# renderers use, or generated worlds would shear differently than they render.
	for row in range(0, 8):
		for col in range(0, 8):
			var via_grid := WorldGrid.offset_to_axial(col, row)
			var via_ctrl := HexMapController.godot_map_to_axial(Vector2i(col, row))
			check(via_grid == via_ctrl, "WorldGrid.offset_to_axial must equal HexMapController.godot_map_to_axial at (%d,%d)" % [col, row])


func test_enumerate_size_is_w_times_h() -> void:
	var cells := WorldGrid.enumerate(25, 20)
	check(cells.size() == 25 * 20, "enumerate(25,20) should yield 500 cells, got %d" % cells.size())


func test_enumerate_keys_unique() -> void:
	var cells := WorldGrid.enumerate(15, 12)
	var seen := {}
	for c in cells:
		var k: Vector2i = c["key"]
		check(not seen.has(k), "duplicate axial key %s in enumerate" % str(k))
		seen[k] = true


func test_enumerate_renders_as_rectangle() -> void:
	# THE rectangle proof: every enumerated axial key, pushed through the even-q
	# render transform, must land on a clean col in [0,W) x row in [0,H).
	var w := 15
	var h := 12
	var cells := WorldGrid.enumerate(w, h)
	var offsets := {}
	for c in cells:
		var off := HexMapController.axial_to_godot_map(c["key"])
		check(off == Vector2i(c["col"], c["row"]),
			"axial %s should render at offset (%d,%d), got %s" % [str(c["key"]), c["col"], c["row"], str(off)])
		check(off.x >= 0 and off.x < w and off.y >= 0 and off.y < h,
			"rendered offset %s out of the WxH rectangle" % str(off))
		offsets[off] = true
	check(offsets.size() == w * h, "the rendered offsets should exactly tile the WxH rectangle (got %d of %d)" % [offsets.size(), w * h])


func test_enumerate_sorted_canonical() -> void:
	# Must match SettingRepository.list_hexes order (r ASC, q ASC) so the replay
	# RLE encoder stays aligned with the decoder.
	var cells := WorldGrid.enumerate(10, 8)
	for i in range(1, cells.size()):
		var prev: Vector2i = cells[i - 1]["key"]
		var cur: Vector2i = cells[i]["key"]
		check(WorldGrid.canonical_less(prev, cur),
			"enumerate must be sorted canonical (r ASC, q ASC): %s !< %s" % [str(prev), str(cur)])


func test_enumerate_row_zero_is_top() -> void:
	# Offset row 0 must render on visual row 0 (latitude is derived from `row`).
	var cells := WorldGrid.enumerate(9, 9)
	for c in cells:
		if c["row"] == 0:
			check(HexMapController.axial_to_godot_map(c["key"]).y == 0, "row-0 cells must render on visual row 0")


func test_adjacency_preserved_within_grid() -> void:
	# A deep-interior cell must have all 6 axial neighbours present in the grid and
	# each at hex-distance 1 (faithful axial adjacency under the relabel).
	var cells := WorldGrid.enumerate(12, 10)
	var by_key := {}
	for c in cells:
		by_key[c["key"]] = true
	var center := WorldGrid.offset_to_axial(6, 5)
	var count := 0
	for n in HexMapController.get_neighbors(center):
		check(HexMapController.hex_distance(center, n) == 1, "neighbour %s must be hex-distance 1 from %s" % [str(n), str(center)])
		if by_key.has(n):
			count += 1
	check(count == 6, "a deep-interior cell should have all 6 axial neighbours present, got %d" % count)
