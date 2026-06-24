extends "res://tests/test_suite_base.gd"

## Unit tests for PoliticalMapView's region-label math (continent / sea / ocean names on the
## 24-mile World Map tab). Preloading the scene script also FORCES a parse-load of it — the
## headless suite never loads scene/UI scripts on its own, so this is the parse safety net.
##  - set_regions filters to the three big-feature subtypes, named only
##  - 24-mile axial hexes JSON → map-pixel member centres (via _center_of)
##  - region layout: centroid + near-horizontal axis + a size scaled to the region
##  - OBB-SAT overlap (the declutter primitive)

const PoliticalMapView := preload("res://scenes/ui/campaign_creation/political_map_view.gd")


func _view() -> Control:
	# A bare instance with a known layout (skips _draw, which is where _R/_margin are set).
	var v: Control = PoliticalMapView.new()
	v._R = 10.0
	v._margin = 8.0
	v._ensure_label_font()
	return v


func run_all_tests() -> void:
	test_set_regions_filters_to_named_big_features()
	test_member_px_projects_axial_hexes()
	test_region_layout_sizes_and_orients()
	test_region_layout_empty_is_blank()
	test_box_overlap_sat()
	if not has_failures():
		print("PoliticalMapViewLabels: all tests passed.")


func test_set_regions_filters_to_named_big_features() -> void:
	var v := _view()
	v.set_regions([
		{"subtype": "continent", "name_primary": "Aethelmark", "hexes": "[[0,0]]"},
		{"subtype": "ocean", "name_primary": "The Sundering Deep", "hexes": "[[9,9]]"},
		{"subtype": "sea", "name_primary": "  ", "hexes": "[[2,2]]"},          # unnamed → dropped
		{"subtype": "terrain_cluster", "name_primary": "Gloomwood", "hexes": "[[3,3]]"},  # wrong subtype
		{"subtype": "island", "name_primary": "Skerry", "hexes": "[[4,4]]"},   # not a labelled subtype
	])
	check(v._regions.size() == 2, "only NAMED continent/ocean/sea kept (%d, want 2)" % v._regions.size())
	var kept := {}
	for r in v._regions:
		kept[str(r["subtype"])] = true
	check(kept.has("continent") and kept.has("ocean"), "the two kept are the continent + ocean")
	v.free()


func test_member_px_projects_axial_hexes() -> void:
	var v := _view()
	var pts: PackedVector2Array = v._region_member_px({"hexes": "[[0,0],[1,0],[2,0]]"})
	check(pts.size() == 3, "three axial hexes → three pixel centres (%d)" % pts.size())
	# Distinct columns map to distinct x (1.5R apart).
	check(abs(pts[1].x - pts[0].x - 1.5 * 10.0) < 0.01, "adjacent columns are 1.5R apart in x")
	check(v._region_member_px({"hexes": "not json"}).is_empty(), "malformed hexes JSON → no members")
	v.free()


func test_region_layout_sizes_and_orients() -> void:
	var v := _view()
	# A long EAST-WEST screen run: keep the offset row constant (row = r + (q-(q&1))/2 = 0 ⇒
	# r = -floor(q/2)) so the hexes form a horizontal line on screen, not the down-right diagonal
	# a constant-r axial run produces. The label then runs near-horizontal and sizes UP from the
	# region's length (a big feature gets a big name).
	var hexes := "["
	for q in range(10):
		var r := -int(q / 2)
		hexes += ("," if q > 0 else "") + "[%d,%d]" % [q, r]
	hexes += "]"
	var lay: Dictionary = v._region_layout({"name_primary": "Aethelmark", "hexes": hexes})
	check(not lay.is_empty(), "a non-empty region yields a layout")
	check(str(lay.get("text", "")) == "Aethelmark", "the name is carried into the layout")
	check(abs(float(lay.get("angle", 9.0))) < 0.25, "an east-west region labels near-horizontal (angle %.3f)" % float(lay.get("angle", 9.0)))
	var fs := int(lay.get("max_fs", 0))
	check(fs > v._LABEL_MIN_FONT and fs <= v._LABEL_MAX_FONT, "font scales up from the region extent, within clamp (%d)" % fs)
	v.free()


func test_region_layout_empty_is_blank() -> void:
	var v := _view()
	check(v._region_layout({"name_primary": "X", "hexes": "[]"}).is_empty(), "an empty region → no layout")
	v.free()


func test_box_overlap_sat() -> void:
	var v := _view()
	var a := {"c": Vector2(0, 0), "half": Vector2(100, 20), "angle": 0.0}
	var b_over := {"c": Vector2(40, 0), "half": Vector2(100, 20), "angle": 0.0}
	var b_far := {"c": Vector2(500, 500), "half": Vector2(100, 20), "angle": 0.0}
	check(v._box_overlap(a, b_over), "overlapping label boxes are detected")
	check(not v._box_overlap(a, b_far), "well-separated boxes do not collide")
	var b_rot := {"c": Vector2(0, 0), "half": Vector2(100, 20), "angle": PI / 2.0}
	check(v._box_overlap(a, b_rot), "crossed thin boxes overlap at the centre")
	v.free()
