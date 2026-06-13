extends "res://tests/test_suite_base.gd"

## Stage 2 of the setting-generation pipeline: region painting Phase 1
## (geometric detection, gdd-region-painting.md §4). Characterization per
## the §10 worked example — expected FEATURE CLASSES on a generated map —
## plus the §3 data-model invariants (membership, nesting, overlaps,
## significance bounds, detection floors).

const VALID_LAYERS := [
	"continent", "coastal_landform", "terrain_cluster", "hydronym",
	"road", "historical_cultural",
]

var _cid: String = ""
var _regions: Array = []
var _by_id: Dictionary = {}


func run_all_tests() -> void:
	_generate()
	test_expected_feature_classes()
	test_region_record_invariants()
	test_membership_hexes_on_map()
	test_continents_cover_land()
	test_cluster_floors_respected()
	test_subsplit_parts_nest_inside_parent()
	test_overlaps_are_symmetric_and_not_nested()
	test_significance_bounds()
	test_determinism_same_seed_same_regions()
	print("SettingStage2Tests: all tests passed (%d checks)" % test_count())


func _generate() -> void:
	_cid = CampaignRepository.create_campaign("Stage2 Regions", "w")
	var ok := SettingGenerator.new().generate(_cid, 42, SettingParameters.new())
	check(ok, "generate() failed")
	_regions = SettingRepository.list_regions(_cid)
	for region in _regions:
		_by_id[str(region.id)] = region


# --- Worked example (region-painting §10): expected feature classes ----------

func test_expected_feature_classes() -> void:
	check(_regions.size() > 0, "no regions detected at all")
	var layers := {}
	var subtypes := {}
	for region in _regions:
		layers[str(region.layer)] = int(layers.get(str(region.layer), 0)) + 1
		subtypes[str(region.subtype)] = int(subtypes.get(str(region.subtype), 0)) + 1
	# A Medium map with ~60% land must yield at least one landmass region and
	# at least one open-water hydronym; terrain clusters always exist on a
	# map with 2+ biomes (Stage 1 guarantees that).
	check(layers.has("continent") or subtypes.has("island"),
		"no landmass regions (continent/major_isle/island) detected")
	check(layers.has("terrain_cluster"), "no terrain clusters detected")
	check(layers.has("hydronym"), "no hydronyms detected")
	var has_open_water := subtypes.has("ocean") or subtypes.has("sea")
	check(has_open_water, "no ocean/sea region on a ~40%-water map")


func test_region_record_invariants() -> void:
	var seen_ids := {}
	for region in _regions:
		var id := str(region.id)
		check(not seen_ids.has(id), "duplicate region id %s" % id)
		seen_ids[id] = true
		check(str(region.layer) in VALID_LAYERS, "bad layer '%s'" % region.layer)
		check(str(region.scale) == "campaign_24mi", "coarse pass must emit campaign_24mi")
		check(str(region.name_primary) == "", "Phase 1 regions must be unnamed")
		var hexes: Array = JSON.parse_string(str(region.hexes))
		check(hexes is Array and hexes.size() > 0, "region %s has no hexes" % id)
		var parent := str(region.parent_id)
		if parent != "":
			check(_by_id.has(parent), "region %s parent %s missing" % [id, parent])


func test_membership_hexes_on_map() -> void:
	for region in _regions:
		var hexes: Array = JSON.parse_string(str(region.hexes))
		for pair in hexes:
			var q := int(pair[0])
			var r := int(pair[1])
			check(q >= 0 and q < 25 and r >= 0 and r < 20,
				"region %s hex (%d,%d) off-map" % [region.id, q, r])


func test_continents_cover_land() -> void:
	# Every land hex belongs to exactly one landmass region (continent,
	# major_isle, or island) — the §4.1 flood-fill partitions land.
	var landmass_membership := {}
	for region in _regions:
		var is_landmass: bool = str(region.layer) == "continent" \
				or str(region.subtype) == "island"
		if not is_landmass:
			continue
		for pair in JSON.parse_string(str(region.hexes)):
			var key := Vector2i(int(pair[0]), int(pair[1]))
			check(not landmass_membership.has(key),
				"hex %s in two landmass regions" % key)
			landmass_membership[key] = true
	for hex in SettingRepository.list_hexes(_cid):
		var key := Vector2i(int(hex.q), int(hex.r))
		if str(hex.water) == "":
			check(landmass_membership.has(key),
				"land hex %s not in any landmass region" % key)
		else:
			check(not landmass_membership.has(key),
				"water hex %s inside a landmass region" % key)


func test_cluster_floors_respected() -> void:
	for region in _regions:
		var hexes: Array = JSON.parse_string(str(region.hexes))
		match str(region.subtype):
			"range", "forest", "desert", "plains", "swamp":
				check(hexes.size() >= 2,
					"cluster %s below the 2-hex floor" % region.id)
			"anomaly":
				check(hexes.size() >= 1 and hexes.size() <= 4,
					"anomaly %s outside 1-4 hexes" % region.id)
			"continent":
				check(hexes.size() >= 100, "continent %s below 100 hexes" % region.id)
			"major_isle":
				check(hexes.size() >= 20 and hexes.size() < 100,
					"major_isle %s outside 20-99" % region.id)
			"ocean":
				check(hexes.size() >= 80, "ocean %s below 80 hexes" % region.id)
			"sea":
				check(hexes.size() >= 8, "sea %s below 8 hexes" % region.id)
			"peninsula":
				check(hexes.size() >= 4, "peninsula %s below 4 land hexes" % region.id)


func test_subsplit_parts_nest_inside_parent() -> void:
	for region in _regions:
		if not str(region.subtype).ends_with("_part"):
			continue
		var parent: Dictionary = _by_id.get(str(region.parent_id), {})
		check(not parent.is_empty(), "sub-split part %s has no parent" % region.id)
		if parent.is_empty():
			continue
		var parent_hexes := {}
		for pair in JSON.parse_string(str(parent.hexes)):
			parent_hexes[Vector2i(int(pair[0]), int(pair[1]))] = true
		var part_hexes: Array = JSON.parse_string(str(region.hexes))
		check(part_hexes.size() >= 4, "sub-split part %s below 4 hexes" % region.id)
		for pair in part_hexes:
			check(parent_hexes.has(Vector2i(int(pair[0]), int(pair[1]))),
				"part %s hex outside its parent %s" % [region.id, parent.id])


func test_overlaps_are_symmetric_and_not_nested() -> void:
	for region in _regions:
		var overlaps: Array = JSON.parse_string(str(region.overlaps))
		for other_id in overlaps:
			check(str(other_id) != str(region.id), "region %s overlaps itself" % region.id)
			var other: Dictionary = _by_id.get(str(other_id), {})
			check(not other.is_empty(),
				"region %s overlap target %s missing" % [region.id, other_id])
			if other.is_empty():
				continue
			var back: Array = JSON.parse_string(str(other.overlaps))
			check(str(region.id) in back,
				"overlap not symmetric: %s -> %s" % [region.id, other_id])
			check(str(other.parent_id) != str(region.id)
					and str(region.parent_id) != str(other_id),
				"directly nested regions listed as overlaps: %s / %s"
					% [region.id, other_id])


func test_significance_bounds() -> void:
	for region in _regions:
		var sig := float(region.significance)
		check(sig >= 0.0 and sig <= 1.0, "significance out of 0-1: %f" % sig)
	# With the context term 0, the §3.3 weights cap Phase-1 significance at
	# 0.45 + 0.35 = 0.80.
	for region in _regions:
		check(float(region.significance) <= 0.801,
			"Phase-1 significance exceeds 0.45+0.35 cap: %s = %f"
				% [region.id, float(region.significance)])


func test_determinism_same_seed_same_regions() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage2 Regions B", "w")
	check(SettingGenerator.new().generate(cid2, 42, SettingParameters.new()),
		"second generate() failed")
	var subs_a := SettingDatasetHasher.compute_sub_hashes(_cid)
	var subs_b := SettingDatasetHasher.compute_sub_hashes(cid2)
	check(subs_a["setting_regions"] == subs_b["setting_regions"],
		"region detection is not deterministic for the same seed")
