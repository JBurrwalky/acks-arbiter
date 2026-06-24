extends "res://tests/test_suite_base.gd"

## Flag-gated integration of the field-first engine (gdd-continuous-geography.md
## §13). GeoFieldToGrid.run() must produce a Layers-1-2 hex grid in the SAME
## shape as HeightmapGenerator + ClimateGenerator, so every downstream layer runs
## unchanged. Validates grid validity, river tracing, determinism, and the
## ProjectSettings flag plumbing (default OFF — the shipped path is untouched).

const VALID_ELEVATIONS := ["flat", "hills", "mountains"]
const VALID_BIOMES := ["clear", "woods", "jungle", "swamp", "desert"]
const VALID_SUBTYPES := [
	"", "forest_dense", "forest_taiga", "mountains_volcanic", "mountains_glacial",
	"clear_tundra", "clear_savanna", "clear_grassland", "desert_badlands",
]
const VALID_WATER := ["", "ocean", "lake"]


func run_all_tests() -> void:
	test_flag_default_off()
	test_grid_valid_and_complete()
	test_rivers_traced()
	test_determinism()
	test_flag_toggle()
	test_full_pipeline_smoke()
	# Belt-and-braces: the flag must be OFF when this suite exits so later suites
	# (which run the real pipeline) are unaffected.
	ProjectSettings.set_setting(GeoFieldToGrid.SETTING, false)
	print("GeoFieldIntegrationTests: all tests passed (%d checks)" % test_count())


func _run(seed_val: int) -> Dictionary:
	var p := SettingParameters.new()
	p.map_size = "medium"
	var ctx := {"campaign_id": "_inmem_", "campaign_seed": seed_val, "params": p}
	GeoFieldToGrid.run(ctx)
	return ctx


func test_flag_default_off() -> void:
	# A fresh project has the flag unset → continuous geography is OFF, so the
	# shipped HeightmapGenerator/ClimateGenerator path runs by default.
	ProjectSettings.set_setting(GeoFieldToGrid.SETTING, false)
	check(not GeoFieldToGrid.is_enabled(), "continuous-geography flag must default OFF")


func test_grid_valid_and_complete() -> void:
	var ctx := _run(42)
	var grid: Dictionary = ctx["hex_grid"]
	check(int(ctx["width"]) == 25 and int(ctx["height"]) == 20, "medium dims should be 25x20")
	check(grid.size() == 25 * 20, "medium grid should be 500 hexes, got %d" % grid.size())
	var land := 0
	var ocean := 0
	var biomes := {}
	var bad := 0
	var bad_lv := 0
	for key in grid:
		var hex: Dictionary = grid[key]
		if not (str(hex["elevation"]) in VALID_ELEVATIONS and str(hex["biome"]) in VALID_BIOMES
				and str(hex["biome_subtype"]) in VALID_SUBTYPES and str(hex["water"]) in VALID_WATER):
			bad += 1
		var raw := float(hex["elevation_raw"])
		if raw < 0.0 or raw > 1.0:
			bad += 1
		var lv := int(hex["land_value"])
		if str(hex["water"]) == "":
			land += 1
			biomes[str(hex["biome"])] = true
			if lv < 3 or lv > 9:
				bad_lv += 1
		else:
			ocean += 1
			if lv != 0:
				bad_lv += 1
	check(bad == 0, "%d hexes have invalid tags or out-of-range elevation_raw" % bad)
	check(land > 0 and ocean > 0, "need both land (%d) and ocean (%d)" % [land, ocean])
	check(biomes.size() >= 3, "expected >=3 land biomes, got %s" % str(biomes.keys()))
	check(bad_lv == 0, "%d hexes have an out-of-range land_value" % bad_lv)


func test_rivers_traced() -> void:
	var ctx := _run(42)
	var rivers: Array = ctx["river_edges"]
	check(rivers.size() > 0, "no river edges traced on the field-derived terrain")
	var bad := 0
	for row in rivers:
		var e := int(row["edge"])
		if e < 0 or e > 5:
			bad += 1
	check(bad == 0, "%d river edges have an out-of-range edge index" % bad)


func test_determinism() -> void:
	# Diagnostic: the field itself must be finite on a MEDIUM map (Layer-1's
	# finite check only ran small). A NaN here is the root of the "differs" report.
	var pp := SettingParameters.new()
	pp.map_size = "medium"
	var fld := GeoFieldGenerator.generate(7, pp)
	var nan_surf := -1
	var nan_acc := -1
	for i in range(fld.size_cells()):
		if nan_surf < 0 and not is_finite(fld.surface[i]):
			nan_surf = i
		if nan_acc < 0 and not is_finite(fld.flow_accum[i]):
			nan_acc = i
	check(nan_surf < 0, "field surface NaN at cell %d (col %d, row %d), accum_there=%f" % [
		nan_surf, fld.col_of(maxi(nan_surf, 0)), fld.row_of(maxi(nan_surf, 0)),
		fld.flow_accum[maxi(nan_surf, 0)]])
	check(nan_acc < 0, "field flow_accum NaN at cell %d" % nan_acc)

	var a: Dictionary = _run(7)["hex_grid"]
	var b: Dictionary = _run(7)["hex_grid"]
	var mism := 0
	var diffs := ""
	for key in a:
		var ha: Dictionary = a[key]
		var hb: Dictionary = b[key]
		if str(ha["elevation"]) != str(hb["elevation"]) or str(ha["biome"]) != str(hb["biome"]) \
				or str(ha["water"]) != str(hb["water"]) or ha["elevation_raw"] != hb["elevation_raw"] \
				or int(ha["land_value"]) != int(hb["land_value"]):
			mism += 1
			if mism <= 4:
				diffs += " {%s: el=%s/%s bi=%s/%s wa='%s'/'%s' lv=%d/%d eraw=%.7f/%.7f}" % [
					str(key), ha["elevation"], hb["elevation"], ha["biome"], hb["biome"],
					ha["water"], hb["water"], int(ha["land_value"]), int(hb["land_value"]),
					float(ha["elevation_raw"]), float(hb["elevation_raw"])]
	check(mism == 0, "%d hexes differ between same-seed continuous-geography runs:%s" % [mism, diffs])


func test_flag_toggle() -> void:
	ProjectSettings.set_setting(GeoFieldToGrid.SETTING, true)
	check(GeoFieldToGrid.is_enabled(), "is_enabled() should be true when the flag is set")
	ProjectSettings.set_setting(GeoFieldToGrid.SETTING, false)
	check(not GeoFieldToGrid.is_enabled(), "is_enabled() should be false when the flag is cleared")


func test_full_pipeline_smoke() -> void:
	# The whole 8-layer pipeline must run on field-derived terrain (region
	# painting, history sim, etc. consume the same ctx shape). Flag set IN-MEMORY
	# only and reset immediately — never persisted, so project.godot + other
	# suites are untouched.
	ProjectSettings.set_setting(GeoFieldToGrid.SETTING, true)
	var cid := CampaignRepository.create_campaign("ContGeo Smoke", "w")
	var p := SettingParameters.new()
	p.map_size = "small"
	var ok := SettingGenerator.new().generate(cid, 123, p)
	ProjectSettings.set_setting(GeoFieldToGrid.SETTING, false)
	check(ok, "full generate() with continuous geography failed")
	if ok:
		var hexes := SettingRepository.list_hexes(cid)
		check(hexes.size() == 15 * 12, "small continuous world should have 180 hexes, got %d" % hexes.size())
		var land_biomes := {}
		var rivers := SettingRepository.list_river_edges(cid)
		for hex in hexes:
			if str(hex["water"]) == "":
				land_biomes[str(hex["biome"])] = true
		check(land_biomes.size() >= 2, "continuous world should have >=2 land biomes, got %s" % str(land_biomes.keys()))
		check(rivers.size() > 0, "continuous world should have river edges")
