extends "res://tests/test_suite_base.gd"

## Continuous-geography 6-mile materialization (RegionZoomIn._children_from_field):
## each 6-mile child reads ONE field base cell, so a 24-mile parent expands into 16
## children with REAL sub-hex terrain variation — not 16 flat-copied plateau tiles.
## Validates: 16 valid children per parent, genuine intra-parent variation (the whole
## point), and determinism. Pure logic (a generated field + the method) — no DB.

const VALID_ELEV := ["flat", "hills", "mountains"]
const VALID_WATER := ["", "ocean", "lake"]


func run_all_tests() -> void:
	test_children_count_and_validity()
	test_intra_parent_variation()
	test_determinism()
	test_full_materialize_with_field()
	print("RegionFieldMaterializationTests: all tests passed (%d checks)" % test_count())


# End-to-end: generate → lock → materialize, and confirm build_start_region's
# field-mode path runs and persists 6-mile rivers + varied terrain to the region
# map (the wiring the unit tests above don't exercise). Continuous-geography is the
# only world-gen path, so no flag plumbing.
func test_full_materialize_with_field() -> void:
	var cid := CampaignRepository.create_campaign("FieldMat", "Testaria")
	var p := SettingParameters.new()
	p.map_size = "medium"
	p.history_length = "short"
	var ok := SettingGenerator.new().generate(cid, 2024, p)
	if not ok:
		check(false, "field-mode generate() failed")
		return
	SettingRepository.lock_setting(cid, "deadbeefcafe")
	var res: Dictionary = SettingMaterializer.new().materialize(cid)
	check(bool(res.get("ok", false)), "field-mode materialize ok (errors: %s)" % str(res.get("errors", [])))
	var rid := str(res.get("region_map_id", ""))
	check(rid != "", "region map produced")
	if rid == "":
		return
	var db = CampaignRepository.db
	db.query_with_bindings("SELECT COUNT(*) AS n FROM hex_river_edges WHERE map_id = ?", [rid])
	var n_rivers := int(db.query_result[0].get("n", 0))
	print("  field-mode region: %d six-mile river edges" % n_rivers)
	check(n_rivers > 0, "field-mode materialization persisted no 6-mile river edges")


func _field(seed_val: int) -> GeoField:
	var p := SettingParameters.new()
	p.map_size = "medium"
	var f := GeoFieldGenerator.generate(seed_val, p)
	GeoClimateGenerator.apply(f, seed_val, p)
	return f


# A land parent (24-mile hex) whose 4×4 field block is mostly land — scanned in
# offset order for determinism.
func _a_land_parent(f: GeoField, dims: Vector2i) -> Vector2i:
	for row in range(dims.y):
		for col in range(dims.x):
			var land := 0
			for cy in range(row * 4, row * 4 + 4):
				for cx in range(col * 4, col * 4 + 4):
					if f.water[f.idx(cx, cy)] == GeoField.WATER_NONE:
						land += 1
			if land >= 12:
				return WorldGrid.offset_to_axial(col, row)
	return WorldGrid.offset_to_axial(dims.x / 2, dims.y / 2)


func test_children_count_and_validity() -> void:
	var f := _field(42)
	var dims := Vector2i(25, 20)  # medium
	var rzi := RegionZoomIn.new()
	var parent := {"civilization": "wilderness", "original_biome": ""}
	var pv := _a_land_parent(f, dims)
	var kids: Array = rzi._children_from_field(f, pv.x, pv.y, parent)
	check(kids.size() == 16, "a parent must expand into 16 children, got %d" % kids.size())
	var bad := 0
	for k in kids:
		if not (str(k["elevation"]) in VALID_ELEV and str(k["water"]) in VALID_WATER):
			bad += 1
		var raw := float(k["elevation_raw"])
		if raw < 0.0 or raw > 1.0:
			bad += 1
		if str(k["civilization"]) != "wilderness":
			bad += 1  # politics inherited from the parent
	check(bad == 0, "%d children have invalid tags / uninherited civ" % bad)


func test_intra_parent_variation() -> void:
	# The whole point: field-sampled children VARY within a parent (flat-copy would
	# make all 16 identical). Measure across many land parents; most should vary.
	var f := _field(42)
	var dims := Vector2i(25, 20)
	var rzi := RegionZoomIn.new()
	var parent := {"civilization": "wilderness", "original_biome": ""}
	var varied := 0
	var sampled := 0
	for row in range(dims.y):
		for col in range(dims.x):
			var pv := WorldGrid.offset_to_axial(col, row)
			var kids: Array = rzi._children_from_field(f, pv.x, pv.y, parent)
			# land-only parents (skip all-ocean: no terrain variation expected)
			var land_kids := 0
			var lo := INF
			var hi := -INF
			var biomes := {}
			for k in kids:
				if str(k["water"]) == "":
					land_kids += 1
					lo = minf(lo, float(k["elevation_raw"]))
					hi = maxf(hi, float(k["elevation_raw"]))
					biomes[str(k["biome"])] = true
			if land_kids < 8:
				continue
			sampled += 1
			if (hi - lo) > 0.01 or biomes.size() >= 2:
				varied += 1
	check(sampled > 0, "no land parents sampled")
	# Real terrain: the large majority of land parents carry sub-hex variation.
	check(float(varied) / float(sampled) >= 0.6,
		"only %d/%d land parents vary — field sampling is acting flat" % [varied, sampled])


func test_determinism() -> void:
	var a := _field(7)
	var b := _field(7)
	var dims := Vector2i(25, 20)
	var rzi := RegionZoomIn.new()
	var parent := {"civilization": "wilderness", "original_biome": ""}
	var pv := _a_land_parent(a, dims)
	var ka: Array = rzi._children_from_field(a, pv.x, pv.y, parent)
	var kb: Array = rzi._children_from_field(b, pv.x, pv.y, parent)
	var mism := 0
	for i in range(mini(ka.size(), kb.size())):
		if str(ka[i]["elevation"]) != str(kb[i]["elevation"]) \
				or str(ka[i]["biome"]) != str(kb[i]["biome"]) \
				or float(ka[i]["elevation_raw"]) != float(kb[i]["elevation_raw"]):
			mism += 1
	check(mism == 0, "%d children differ between same-seed fields" % mism)
