extends "res://tests/test_suite_base.gd"

## Stage 1 of the setting-generation pipeline: Layers 1-2 (geography +
## climate). Characterization per the handoff §9.4 — assert the KINDS of
## outcomes of the setting-gen §15 worked example (Medium map, seed 42),
## not exact hexes. Unit tests pin the Köppen cascade, biome mapping,
## elevation bands, and the land-value table.

const VALID_ELEVATIONS := ["flat", "hills", "mountains"]
const VALID_BIOMES := ["clear", "woods", "jungle", "swamp", "desert"]
const VALID_SUBTYPES := [
	"", "forest_dense", "forest_taiga", "mountains_volcanic",
	"mountains_glacial", "clear_tundra", "clear_savanna", "clear_grassland",
	"clear_steppe", "clear_scrub", "desert_badlands",
]
const VALID_WATER := ["", "ocean", "lake"]

var _cid: String = ""


func run_all_tests() -> void:
	test_worked_example_seed42_medium()
	test_generated_grid_is_rectangle()
	test_terrain_enums_valid()
	test_climate_fields_sane()
	test_river_edges_valid()
	test_land_values_in_raw_range()
	test_koppen_classification_unit()
	test_biome_mapping_unit()
	test_elevation_tag_bands()
	test_land_value_table_unit()
	test_large_map_performance()
	print("SettingStage1Tests: all tests passed (%d checks)" % test_count())


func _generated_hexes() -> Array:
	if _cid.is_empty():
		_cid = CampaignRepository.create_campaign("Stage1 Worked Example", "w")
		var ok := SettingGenerator.new().generate(_cid, 42, SettingParameters.new())
		check(ok, "generate() failed for the worked example")
	return SettingRepository.list_hexes(_cid)


# --- Worked example (setting-gen §15: Medium, seed 42) -----------------------

func test_worked_example_seed42_medium() -> void:
	var hexes := _generated_hexes()
	check(hexes.size() == 25 * 20, "expected 500 hexes, got %d" % hexes.size())
	var land := 0
	var counts := {"flat": 0, "hills": 0, "mountains": 0}
	var biomes := {}
	for hex in hexes:
		if str(hex.water) == "":
			land += 1
			counts[str(hex.elevation)] = int(counts.get(str(hex.elevation), 0)) + 1
			biomes[str(hex.biome)] = true
	var land_fraction := float(land) / hexes.size()
	check(land_fraction > 0.3 and land_fraction < 0.9,
		"land fraction out of character: %.2f (worked example ~0.6)" % land_fraction)
	check(counts["flat"] > 0, "no flat land generated")
	check(counts["hills"] > 0, "no hills generated")
	check(counts["mountains"] > 0, "no mountains generated")
	check(counts["flat"] > counts["mountains"],
		"mountains should be rarer than flat land (elevation curve)")
	check(biomes.size() >= 2, "expected at least 2 land biomes, got %s" % str(biomes.keys()))
	var rivers := SettingRepository.list_river_edges(_cid)
	check(rivers.size() > 0, "no river edges generated (worked example has a major river)")


func test_generated_grid_is_rectangle() -> void:
	# The generator lays hexes on an OFFSET-rectangle so they render as a clean
	# rectangle (not the old axial parallelogram): every stored axial key must map
	# through the even-q transform onto a unique (col,row) tiling 25x20.
	var hexes := _generated_hexes()
	var offsets := {}
	for hex in hexes:
		var off := WorldGrid.axial_to_offset(Vector2i(int(hex.q), int(hex.r)))
		check(off.x >= 0 and off.x < 25 and off.y >= 0 and off.y < 20,
			"hex (%s,%s) renders outside the 25x20 rectangle at %s" % [hex.q, hex.r, str(off)])
		offsets[off] = true
	check(offsets.size() == 25 * 20,
		"the 500 hexes should tile the 25x20 rectangle exactly, got %d distinct offsets" % offsets.size())


func test_terrain_enums_valid() -> void:
	for hex in _generated_hexes():
		check(str(hex.elevation) in VALID_ELEVATIONS, "bad elevation '%s'" % hex.elevation)
		check(str(hex.biome) in VALID_BIOMES, "bad biome '%s'" % hex.biome)
		check(str(hex.biome_subtype) in VALID_SUBTYPES, "bad subtype '%s'" % hex.biome_subtype)
		check(str(hex.water) in VALID_WATER, "bad water '%s'" % hex.water)
		var raw := float(hex.elevation_raw)
		check(raw >= 0.0 and raw <= 1.0, "elevation_raw out of 0-1: %f" % raw)
		if str(hex.water) == "":
			check(str(hex.koppen) != "", "land hex (%s,%s) missing Köppen" % [hex.q, hex.r])


func test_climate_fields_sane() -> void:
	var hexes := _generated_hexes()
	var north_temp := 0.0
	var north_n := 0
	var south_temp := 0.0
	var south_n := 0
	for hex in hexes:
		var lat := float(hex.effective_latitude)
		check(lat >= 35.0 - 0.001 and lat <= 55.0 + 0.001,
			"effective latitude outside temperate preset: %f" % lat)
		var precip := float(hex.precipitation)
		check(precip >= 0.0 and precip <= 1.0, "precipitation out of 0-1: %f" % precip)
		# Sample by VISUAL row (offset-rectangle): row 0 is the map's north edge
		# (higher latitude → colder), row H-1 the south. Axial r is sheared and is
		# no longer the visual row, so derive the row via the even-q transform.
		var vrow := WorldGrid.axial_to_offset(Vector2i(int(hex.q), int(hex.r))).y
		if vrow == 0:
			north_temp += float(hex.temperature)
			north_n += 1
		elif vrow == 19:
			south_temp += float(hex.temperature)
			south_n += 1
	check(north_n > 0 and south_n > 0, "row sampling failed")
	check(north_temp / north_n < south_temp / south_n,
		"north edge should average colder than south edge")


func test_river_edges_valid() -> void:
	var rivers := SettingRepository.list_river_edges(_cid)
	var nav_by_width := {
		"stream": "none", "creek": "small_craft",
		"river": "river_craft", "major_river": "large_craft",
	}
	var offsets := [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
	]
	var seen := {}
	for row in rivers:
		var e := int(row.edge)
		check(e >= 0 and e <= 5, "edge index out of range: %d" % e)
		var owner := Vector2i(int(row.hex_q), int(row.hex_r))
		var neighbor: Vector2i = owner + offsets[e]
		# Canonical ownership (terrain-system §3.6.2): owner is lex-lower (q, r).
		check(owner.x < neighbor.x or (owner.x == neighbor.x and owner.y < neighbor.y),
			"river edge owner not canonical: %s edge %d" % [owner, e])
		# Owner is a valid on-map hex: its OFFSET (col,row) is in [0,25)x[0,20).
		# (Axial r is sheared under the offset-rectangle layout, so check the offset.)
		var owner_off := WorldGrid.axial_to_offset(owner)
		check(owner_off.x >= 0 and owner_off.x < 25 and owner_off.y >= 0 and owner_off.y < 20,
			"river edge owner off-map: %s (offset %s)" % [owner, owner_off])
		check(str(row.navigability) == nav_by_width.get(str(row.width_category), "?"),
			"navigability '%s' inconsistent with width '%s'"
				% [row.navigability, row.width_category])
		var key := "%d,%d,%d" % [owner.x, owner.y, e]
		check(not seen.has(key), "duplicate river edge row: %s" % key)
		seen[key] = true


func test_land_values_in_raw_range() -> void:
	for hex in _generated_hexes():
		var lv := int(hex.land_value)
		if str(hex.water) == "":
			check(lv >= 3 and lv <= 9, "land_value out of RAW 3-9: %d" % lv)
		else:
			check(lv == 0, "water hex should have land_value 0, got %d" % lv)


# --- Unit tests ---------------------------------------------------------------

func test_koppen_classification_unit() -> void:
	check(ClimateGenerator._classify_koppen(-10.0, 0.1, 0.5) == "EF", "polar dry should be EF")
	check(ClimateGenerator._classify_koppen(-10.0, 0.5, 0.5) == "ET", "polar wet should be ET")
	check(ClimateGenerator._classify_koppen(25.0, 0.1, 0.5) == "BWh", "hot arid should be BWh")
	check(ClimateGenerator._classify_koppen(10.0, 0.1, 0.5) == "BWk", "cold arid should be BWk")
	# Temperature-dependent aridity: arid_t(25)≈0.315, steppe band [0.315,0.465). So a
	# hot region is BW (desert) up to higher precip than a cold one — 0.25 is now hot
	# desert (BWh), and BSh needs precip inside the (warmer, higher) steppe band.
	check(ClimateGenerator._classify_koppen(25.0, 0.25, 0.5) == "BWh", "hot dry (0.25) is now BWh")
	check(ClimateGenerator._classify_koppen(25.0, 0.40, 0.5) == "BSh", "hot semiarid (0.40) should be BSh")
	check(ClimateGenerator._classify_koppen(10.0, 0.25, 0.5) != "BWh", "same precip at mild temp is NOT hot desert")
	check(ClimateGenerator._classify_koppen(25.0, 0.8, 0.3) == "Af", "tropical wet should be Af")
	check(ClimateGenerator._classify_koppen(25.0, 0.5, 0.7) == "Am", "tropical seasonal should be Am")
	check(ClimateGenerator._classify_koppen(25.0, 0.5, 0.3) == "Aw", "tropical savanna should be Aw")
	check(ClimateGenerator._classify_koppen(12.0, 0.5, 0.7) == "Csb", "cool summer-dry should be Csb")
	check(ClimateGenerator._classify_koppen(16.0, 0.5, 0.3) == "Cfa", "warm temperate should be Cfa")
	check(ClimateGenerator._classify_koppen(5.0, 0.5, 0.3) == "Dfa", "mild continental should be Dfa")
	check(ClimateGenerator._classify_koppen(0.0, 0.5, 0.3) == "Dfc", "subarctic should be Dfc")


func test_biome_mapping_unit() -> void:
	var hex := _fake_hex("flat", 0.5)
	ClimateGenerator._assign_biome(hex, "ET", 9)
	check(hex["biome"] == "clear" and hex["biome_subtype"] == "clear_tundra",
		"ET should map to clear/clear_tundra")
	hex = _fake_hex("flat", 0.5)
	ClimateGenerator._assign_biome(hex, "Dfc", 9)
	check(hex["biome"] == "woods" and hex["biome_subtype"] == "forest_taiga",
		"Dfc should map to woods/forest_taiga")
	hex = _fake_hex("mountains", 0.5)
	ClimateGenerator._assign_biome(hex, "Af", 9)
	check(hex["biome"] == "woods", "montane jungle should become woods (terrain-system §7.2)")
	hex = _fake_hex("flat", 0.19)
	ClimateGenerator._assign_biome(hex, "BSk", 9)
	check(hex["biome"] == "clear" and hex["biome_subtype"] == "clear_grassland",
		"BSk steppe maps to grassland (the flat-threshold desert fringe is retired)")
	hex = _fake_hex("mountains", 0.1)
	ClimateGenerator._assign_biome(hex, "EF", 9)
	check(hex["biome"] == "desert" and hex["biome_subtype"] == "mountains_glacial",
		"EF mountains should be desert/mountains_glacial")
	hex = _fake_hex("flat", 0.5)
	ClimateGenerator._assign_biome(hex, "Cfb", 8)
	check(hex["biome"] == "woods" and hex["biome_subtype"] == "forest_dense",
		"deep-interior temperate forest should be forest_dense")
	hex = _fake_hex("flat", 0.5)
	ClimateGenerator._assign_biome(hex, "Cfb", 2)
	check(hex["biome"] == "woods" and hex["biome_subtype"] == "",
		"coastal temperate forest should be plain woods")


func test_elevation_tag_bands() -> void:
	check(HeightmapGenerator._elevation_tag(0.40) == "flat", "0.40 should be flat")
	check(HeightmapGenerator._elevation_tag(0.54) == "flat", "0.54 should be flat")
	check(HeightmapGenerator._elevation_tag(0.55) == "hills", "0.55 should be hills")
	check(HeightmapGenerator._elevation_tag(0.74) == "hills", "0.74 should be hills")
	check(HeightmapGenerator._elevation_tag(0.75) == "mountains", "0.75 should be mountains")
	check(HeightmapGenerator._elevation_tag(1.0) == "mountains", "1.0 should be mountains")


func test_land_value_table_unit() -> void:
	# 1-row fake grid covering each table row (history-sim §7.5.1). Keys are the
	# offset-rectangle axial coords _assign_land_values now enumerates (col 0..5,
	# row 0) — NOT a bare axial-rectangle, which the new layout no longer produces.
	var k0 := WorldGrid.offset_to_axial(0, 0)
	var k1 := WorldGrid.offset_to_axial(1, 0)
	var k2 := WorldGrid.offset_to_axial(2, 0)
	var k3 := WorldGrid.offset_to_axial(3, 0)
	var k4 := WorldGrid.offset_to_axial(4, 0)
	var k5 := WorldGrid.offset_to_axial(5, 0)
	var grid := {
		k0: _land_hex("flat", "desert", ""),
		k1: _land_hex("mountains", "clear", ""),
		k2: _land_hex("flat", "woods", ""),
		k3: _land_hex("hills", "clear", ""),
		k4: _land_hex("flat", "clear", ""),
		k5: _land_hex("flat", "swamp", ""),
	}
	# Col 4 is river-adjacent: plains 6 + 1 = 7.
	ClimateGenerator._assign_land_values(grid, 6, 1, {k4: true})
	check(int(grid[k0]["land_value"]) == 3, "desert should be 3")
	check(int(grid[k1]["land_value"]) == 3, "mountains should be 3")
	check(int(grid[k2]["land_value"]) == 4, "forest should be 4")
	check(int(grid[k3]["land_value"]) == 5, "hills should be 5")
	check(int(grid[k4]["land_value"]) == 7, "river-adjacent plains should be 6+1")
	check(int(grid[k5]["land_value"]) == 3, "swamp should be 3")


func test_large_map_performance() -> void:
	# Measure Layers 1-2 in ISOLATION (the full generate() now also runs culture
	# seeding + the 160-tick history sim, which have their own budgets). Stage 1's
	# exit criterion: the continuous-geography field engine (raster + hydrology +
	# climate + biome + corner-graph rivers) on a Large map in one pass.
	var params := SettingParameters.new()
	params.map_size = "large"
	var ctx := {"campaign_id": "_inmem_", "campaign_seed": 7, "params": params}
	var start := Time.get_ticks_msec()
	GeoFieldToGrid.run(ctx)
	var elapsed := Time.get_ticks_msec() - start
	check(elapsed < 12000, "Layers 1-2 on Large took %d ms (budget 12s)" % elapsed)
	check(ctx["hex_grid"].size() == 40 * 30, "large map should have 1200 hexes")


# --- Helpers ------------------------------------------------------------------

func _fake_hex(elevation: String, precipitation: float) -> Dictionary:
	return {
		"elevation": elevation, "precipitation": precipitation,
		"biome": "clear", "biome_subtype": "", "water": "",
	}


func _land_hex(elevation: String, biome: String, subtype: String) -> Dictionary:
	return {
		"elevation": elevation, "biome": biome, "biome_subtype": subtype,
		"water": "", "land_value": 0,
	}
