extends "res://tests/test_suite_base.gd"

## VolcanismPainter (24-mile geological-feature pass) + RegionZoomIn's 6-mile vent
## placement. The painter marks whole mountain RANGES (and lone peaks, at a higher
## rate) volcanic on the world substrate; the zoom reads the stamp and randomizes
## which mountain children erupt into active vents. Volcanic wins over glacial.
##
## Pure logic — no DB. The 24-mile stamp runs on a real field-derived grid; the
## 6-mile vent decisions are tested through RegionZoomIn's static helpers.


func run_all_tests() -> void:
	test_components_split_ranges_from_lone_peaks()
	test_stamp_determinism()
	test_stamp_only_on_mountains()
	test_whole_range_stamped()
	test_some_volcanic_across_seeds()
	test_volcanic_wins_over_glacial_at_24mi()
	test_is_lone_volcano_neighbor_test()
	test_vent_rate_bounds()
	test_vent_determinism_and_glacial_override()
	print("VolcanismTests: all tests passed (%d checks)" % test_count())


# --- 24-mile stamp ----------------------------------------------------------

func test_components_split_ranges_from_lone_peaks() -> void:
	# A 3-hex connected mountain mass = one range; an isolated peak = a lone peak.
	var grid := {}
	# Range: (0,0)-(1,0)-(2,0) contiguous along a row (offset cols 0,1,2 / row 0).
	for col in [0, 1, 2]:
		grid[WorldGrid.offset_to_axial(col, 0)] = _mtn()
	# Lone peak far away at (5,5), surrounded by flat.
	grid[WorldGrid.offset_to_axial(5, 5)] = _mtn()
	# Everything else flat clear (fill an 8x8 so neighbors resolve).
	for row in range(8):
		for col in range(8):
			var k := WorldGrid.offset_to_axial(col, row)
			if not grid.has(k):
				grid[k] = _flat()
	var comps := VolcanismPainter._mountain_components(grid, 8, 8)
	check(comps.size() == 2, "expected 2 mountain components, got %d" % comps.size())
	var sizes := [comps[0].size(), comps[1].size()]
	sizes.sort()
	check(sizes == [1, 3], "expected sizes [1,3] (lone + range), got %s" % str(sizes))


func test_stamp_determinism() -> void:
	var a := _painted_grid(42)
	var b := _painted_grid(42)
	check(_volcanic_set(a) == _volcanic_set(b), "same seed produced a different volcanic stamp")


func test_stamp_only_on_mountains() -> void:
	var grid := _painted_grid(7)
	var bad := 0
	for key in grid:
		if str(grid[key]["biome_subtype"]) == "mountains_volcanic" \
				and str(grid[key]["elevation"]) != "mountains":
			bad += 1
	check(bad == 0, "%d volcanic hexes are not mountains" % bad)


func test_whole_range_stamped() -> void:
	# Every mountain component is volcanic-homogeneous: all hexes volcanic or none.
	# (The painter stamps the whole RANGE, never a partial slice.)
	var grid := _painted_grid(7)
	var split := 0
	for comp in VolcanismPainter._mountain_components(grid, 25, 20):
		var volcanic := 0
		for h in comp:
			if str(grid[h]["biome_subtype"]) == "mountains_volcanic":
				volcanic += 1
		if volcanic != 0 and volcanic != comp.size():
			split += 1
	check(split == 0, "%d ranges were only partially stamped volcanic" % split)


func test_some_volcanic_across_seeds() -> void:
	# Over several medium maps, at least one volcanic range appears (~20% of ranges).
	var total := 0
	for seed in [1, 2, 3, 4, 5, 6]:
		var ctx := _medium_ctx(seed)
		VolcanismPainter.paint(ctx)
		total += int(ctx["volcanic_hex_count"])
	check(total > 0, "no volcanic mountains produced across 6 seeds")


func test_volcanic_wins_over_glacial_at_24mi() -> void:
	# A cold mountain mass tagged glacial, forced volcanic, must end up volcanic.
	var grid := {}
	for col in [0, 1]:
		var h := _mtn()
		h["biome_subtype"] = "mountains_glacial"
		grid[WorldGrid.offset_to_axial(col, 0)] = h
	for row in range(4):
		for col in range(4):
			var k := WorldGrid.offset_to_axial(col, row)
			if not grid.has(k):
				grid[k] = _flat()
	# Find a seed whose range roll fires (deterministic search — no RNG order issue).
	var fired := false
	for seed in range(200):
		var g := _deep_copy(grid)
		var ctx := {"hex_grid": g, "width": 4, "height": 4, "campaign_seed": seed}
		VolcanismPainter.paint(ctx)
		if int(ctx["volcanic_hex_count"]) > 0:
			fired = true
			for col in [0, 1]:
				var k := WorldGrid.offset_to_axial(col, 0)
				check(str(g[k]["biome_subtype"]) == "mountains_volcanic",
					"glacial mountain not overridden to volcanic")
			break
	check(fired, "no seed in 0..199 made this 2-hex range volcanic")


# --- 6-mile vents (RegionZoomIn static helpers) -----------------------------

func test_is_lone_volcano_neighbor_test() -> void:
	# A volcanic parent with a volcanic neighbor is part of a range (not lone).
	var vp := {}
	vp["3,3"] = true
	vp["4,2"] = true  # axial neighbor of (3,3) via offset (1,-1)
	check(not RegionZoomIn._is_lone_volcano(3, 3, vp), "range hex misread as lone")
	# A volcanic parent with no volcanic neighbor is a lone peak.
	var lone := {}
	lone["10,10"] = true
	check(RegionZoomIn._is_lone_volcano(10, 10, lone), "isolated peak misread as range")


func test_vent_rate_bounds() -> void:
	# Rate 1.0 always vents; rate 0.0 never vents (keeps the field subtype).
	var child := Vector2i(2, 3)
	check(RegionZoomIn._volcanic_vent_subtype("", 1.0, 99, child) == "mountains_volcanic",
		"vent rate 1.0 should always erupt")
	check(RegionZoomIn._volcanic_vent_subtype("", 0.0, 99, child) == "",
		"vent rate 0.0 should keep the base subtype")


func test_vent_determinism_and_glacial_override() -> void:
	var child := Vector2i(7, 11)
	var a := RegionZoomIn._volcanic_vent_subtype("mountains_glacial", 1.0, 5, child)
	var b := RegionZoomIn._volcanic_vent_subtype("mountains_glacial", 1.0, 5, child)
	check(a == b, "vent decision not deterministic for the same child/seed")
	check(a == "mountains_volcanic", "an active vent must win over glacial (lava melts ice)")
	# Same child, different seed → an independent stream (just must stay valid).
	var c := RegionZoomIn._volcanic_vent_subtype("mountains_glacial", 0.0, 6, child)
	check(c == "mountains_glacial", "non-vent keeps the field subtype")


# --- helpers ----------------------------------------------------------------

func _mtn() -> Dictionary:
	return {"water": "", "elevation": "mountains", "biome": "clear", "biome_subtype": ""}


func _flat() -> Dictionary:
	return {"water": "", "elevation": "flat", "biome": "clear", "biome_subtype": ""}


func _medium_ctx(seed: int) -> Dictionary:
	var p := SettingParameters.new()
	p.map_size = "medium"
	var ctx := {"params": p, "campaign_seed": seed}
	GeoFieldToGrid.run(ctx)
	return ctx


func _painted_grid(seed: int) -> Dictionary:
	var ctx := _medium_ctx(seed)
	VolcanismPainter.paint(ctx)
	return ctx["hex_grid"]


func _volcanic_set(grid: Dictionary) -> Dictionary:
	var s := {}
	for key in grid:
		if str(grid[key]["biome_subtype"]) == "mountains_volcanic":
			s[key] = true
	return s


func _deep_copy(grid: Dictionary) -> Dictionary:
	var out := {}
	for key in grid:
		out[key] = grid[key].duplicate()
	return out
