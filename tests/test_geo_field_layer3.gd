extends "res://tests/test_suite_base.gd"

## Layer-3 of the field-first world generator (gdd-continuous-geography.md §8):
## GeoFieldSampler.tag_for_footprint — the hex-normalization contract. Validated
## on hand-built fields (water coverage, mountain override, biome plurality,
## uniform mean) + CROSS-SCALE consistency (a 24-mile tag reproduces the plurality
## of its sixteen 6-mile tags) + determinism on a real generated field.
##
## ADDITIVE module — not wired into the live pipeline. Pure function of the field.


func run_all_tests() -> void:
	test_water_coverage()
	test_mountain_override_and_plurality()
	test_uniform_field_mean()
	test_cross_scale_biome_consistency()
	test_determinism_real_field()
	test_detail_sample_bounded()
	print("GeoFieldLayer3Tests: all tests passed (%d checks)" % test_count())


# A flat, all-land, all-clear synthetic field for precise control.
func _synthetic(w: int, h: int) -> GeoField:
	var f := GeoField.new()
	f.allocate(w, h)
	for i in range(f.size_cells()):
		f.surface[i] = 0.2
		f.water[i] = GeoField.WATER_NONE
		f.biome[i] = GeoField.BIOME_CLEAR
		f.biome_subtype[i] = GeoField.SUB_NONE
	return f


func test_water_coverage() -> void:
	var f := _synthetic(4, 4)
	for i in range(6):  # 6/16 = 0.375 >= WATER_COVERAGE (0.35) → water hex
		f.water[i] = GeoField.WATER_OCEAN
	var tag := GeoFieldSampler.tag_for_footprint(f, 0.0, 0.0, 4.0, 4)
	check(tag["water"] == "ocean", "6/16 ocean coverage should read as an ocean hex, got '%s'" % tag["water"])
	# Below threshold stays land.
	var f2 := _synthetic(4, 4)
	for i in range(4):  # 4/16 = 0.25 < 0.35
		f2.water[i] = GeoField.WATER_OCEAN
	var tag2 := GeoFieldSampler.tag_for_footprint(f2, 0.0, 0.0, 4.0, 4)
	check(tag2["water"] == "", "4/16 ocean coverage should stay land, got '%s'" % tag2["water"])


func test_mountain_override_and_plurality() -> void:
	var f := _synthetic(4, 4)
	for i in range(5):  # 5/16 = 0.31 >= 0.25 → mountains override (flat is plurality)
		f.surface[i] = 0.85
	for i in range(9):  # 9 woods vs 7 clear
		f.biome[i] = GeoField.BIOME_WOODS
	var tag := GeoFieldSampler.tag_for_footprint(f, 0.0, 0.0, 4.0, 4)
	check(tag["elevation"] == "mountains",
		"5/16 mountain-height land should override to 'mountains', got '%s'" % tag["elevation"])
	check(tag["biome"] == "woods", "9-woods/7-clear footprint should read 'woods', got '%s'" % tag["biome"])
	check(tag["biome_runner_up"] == "clear", "runner-up biome should be 'clear', got '%s'" % tag["biome_runner_up"])


func test_uniform_field_mean() -> void:
	var f := _synthetic(4, 4)
	for i in range(f.size_cells()):
		f.surface[i] = 0.6  # uniform hills-height
	var tag := GeoFieldSampler.tag_for_footprint(f, 0.0, 0.0, 4.0, 4)
	check(absf(float(tag["elevation_raw"]) - 0.6) < 1.0e-4,
		"uniform 0.6 field should give elevation_raw ~0.6, got %f" % tag["elevation_raw"])
	check(tag["elevation"] == "hills", "uniform 0.6 (>=0.55) should read 'hills', got '%s'" % tag["elevation"])


func test_cross_scale_biome_consistency() -> void:
	# A 24-mile tag (4×4 footprint) must reproduce the plurality biome of its
	# sixteen constituent 6-mile tags — they are reductions of the same field.
	var f := _synthetic(4, 4)
	for i in range(5):
		f.surface[i] = 0.85
	for i in range(9):
		f.biome[i] = GeoField.BIOME_WOODS
	var tag24 := GeoFieldSampler.tag_24mile(f, 0, 0)
	var counts := {}
	for cy in range(4):
		for cx in range(4):
			var t6 := GeoFieldSampler.tag_6mile(f, cx, cy)
			counts[t6["biome"]] = int(counts.get(t6["biome"], 0)) + 1
	var dominant := ""
	var dn := -1
	for b in counts:
		if int(counts[b]) > dn:
			dn = int(counts[b])
			dominant = b
	check(dominant == tag24["biome"],
		"6-mile plurality '%s' should match the 24-mile tag '%s'" % [dominant, tag24["biome"]])


func test_determinism_real_field() -> void:
	var p := SettingParameters.new()
	p.map_size = "small"
	var f := GeoFieldGenerator.generate(7, p)
	GeoClimateGenerator.apply(f, 7, p)
	var t_a := GeoFieldSampler.tag_24mile(f, 1, 1)
	var t_b := GeoFieldSampler.tag_24mile(f, 1, 1)
	check(str(t_a) == str(t_b), "tag_for_footprint should be deterministic for the same field/footprint")
	# And it returns the HexTerrainData-shaped keys consumers expect.
	for key in ["elevation", "biome", "biome_subtype", "water", "elevation_raw"]:
		check(t_a.has(key), "tag missing expected key '%s'" % key)


func test_detail_sample_bounded() -> void:
	var p := SettingParameters.new()
	p.map_size = "small"
	var f := GeoFieldGenerator.generate(7, p)
	var detail := GeoFieldSampler.make_detail_noise(7)
	var bad := 0
	for s in range(200):
		var sx := float(s % 55) + 0.37
		var sy := float((s * 13) % 45) + 0.41
		var hd := GeoFieldSampler.sample_height_detailed(f, sx, sy, detail)
		if hd < 0.0 or hd > 1.0 or not is_finite(hd):
			bad += 1
	check(bad == 0, "%d detailed height samples out of [0,1] or non-finite" % bad)
