extends "res://tests/test_suite_base.gd"

## Unit tests for RegionLabelRenderer's PURE layout math (no scene / no DB):
##  - 24-mile region hex → in-window 6-mile children projection (inverse of the parent bridge)
##  - hex-spacing estimate
##  - region-size + text-length aware font-size formula (worked example)
##  - straight-vs-curved decision: a convex blob → straight; a bent arc → curved


func run_all_tests() -> void:
	test_project_members_round_trips_parent()
	test_hex_spacing()
	test_convex_blob_is_straight_and_sized()
	test_bent_arc_is_curved()
	test_obb_overlap_sat()
	test_empty_window_skips()
	if not has_failures():
		print("RegionLabelRenderer: all tests passed.")


func test_project_members_round_trips_parent() -> void:
	var rl := RegionLabelRenderer.new()
	# A region of one 24-mile hex (5,5): its 16 six-mile children all land in a window
	# containing them, and each child's parent floor-divides back to (5,5).
	var parent := Vector2i(5, 5)
	var poff := WorldGrid.axial_to_offset(parent)
	var window := {}
	for lx in range(4):
		for ly in range(4):
			window[WorldGrid.offset_to_axial(poff.x * 4 + lx, poff.y * 4 + ly)] = true
	var members: Array = rl._project_members("[[5,5]]", window)
	check(members.size() == 16, "one 24-mile parent projects to its 16 in-window children (%d)" % members.size())
	var all_parent_ok := true
	for m in members:
		var moff := WorldGrid.axial_to_offset(m)
		var p := WorldGrid.offset_to_axial(floori(moff.x / 4.0), floori(moff.y / 4.0))
		if p != parent:
			all_parent_ok = false
	check(all_parent_ok, "every projected child floor-divides back to its 24-mile parent")
	# A window with only half the children → only those project.
	var half := {}
	var keys := window.keys()
	for i in range(8):
		half[keys[i]] = true
	check(rl._project_members("[[5,5]]", half).size() == 8, "only in-window children are kept")
	check(rl._project_members("not json", window).is_empty(), "malformed hexes JSON → no members, no crash")


func test_hex_spacing() -> void:
	var rl := RegionLabelRenderer.new()
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(50, 87), Vector2(150, 87)])
	# min adjacent distance is the 100-px horizontal step.
	check(abs(rl._hex_spacing(pts) - 100.0) < 0.5, "hex spacing = min adjacent distance (%f)" % rl._hex_spacing(pts))


func test_convex_blob_is_straight_and_sized() -> void:
	var rl := RegionLabelRenderer.new()
	rl._ensure_font()
	# A 1600 x 600 convex cloud (grid). Long axis ≈ 1600 world px, half-width ≈ 300.
	var pts := PackedVector2Array()
	for col in range(17):
		for row in range(5):
			pts.append(Vector2(col * 100.0, row * 150.0 - 300.0))
	var cand: Dictionary = rl._build_candidate("Gloomwood", "(forest)", pts)   # 9 chars
	check(str(cand.get("mode", "")) == "straight", "a convex blob labels STRAIGHT (mode=%s)" % str(cand.get("mode", "")))
	# size_from_length = 1600/(0.62*9) ≈ 287, size_from_width = 600 → clamp to MAX_FONT 64.
	check(int(cand.get("base_fs", 0)) == 64, "font size clamps to MAX_FONT for a big region + short name (%d)" % int(cand.get("base_fs", 0)))
	# Finalize at base size → straight title + a subtitle line.
	cand["fs"] = cand["base_fs"]
	var pl: Dictionary = rl._finalize(cand)
	check(str(pl.get("sub_text", "")) == "(forest)", "the type subtitle is carried through (%s)" % str(pl.get("sub_text", "")))
	check(int(pl.get("sub_fs", 0)) < int(pl.get("fs", 0)), "the subtitle font is smaller than the title")


func test_bent_arc_is_curved() -> void:
	var rl := RegionLabelRenderer.new()
	rl._ensure_font()
	# A 144° circular arc (radius 400): the straight chord crosses the hollow, off the hexes,
	# so a label spanning it must CURVE to stay on the region.
	var pts := PackedVector2Array()
	for i in range(13):
		var ang := deg_to_rad(float(i) * 12.0)
		pts.append(Vector2(cos(ang), sin(ang)) * 400.0)
	var cand: Dictionary = rl._build_candidate("Aelvanar River", "(river)", pts)   # 14 chars
	check(str(cand.get("mode", "")) == "curved", "a bent arc labels CURVED (mode=%s)" % str(cand.get("mode", "")))
	cand["fs"] = cand["base_fs"]
	var pl: Dictionary = rl._finalize(cand)
	var glyphs: Array = pl.get("glyphs", [])
	check(glyphs.size() == "Aelvanar River".length(), "curved layout places one glyph per character (%d)" % glyphs.size())
	if glyphs.size() > 0:
		check((glyphs[0] as Dictionary).has("origin") and (glyphs[0] as Dictionary).has("angle"),
			"each curved glyph carries an origin + angle")
	check(str(pl.get("sub_text", "")) == "(river)", "curved label also carries its type subtitle")


func test_obb_overlap_sat() -> void:
	# Oriented-bounding-box collision (the overlap declutter): two boxes sharing space overlap;
	# two far apart don't; a rotation that separates them is detected.
	var rl := RegionLabelRenderer.new()
	var a := {"c": Vector2(0, 0), "half": Vector2(100, 20), "angle": 0.0}
	var b_over := {"c": Vector2(40, 0), "half": Vector2(100, 20), "angle": 0.0}
	var b_far := {"c": Vector2(500, 500), "half": Vector2(100, 20), "angle": 0.0}
	check(rl._obb_overlap(a, b_over), "overlapping boxes are detected")
	check(not rl._obb_overlap(a, b_far), "well-separated boxes do not collide")
	# Same centres but one rotated 90° and both thin → still overlap (cross shape).
	var b_rot := {"c": Vector2(0, 0), "half": Vector2(100, 20), "angle": PI / 2.0}
	check(rl._obb_overlap(a, b_rot), "crossed thin boxes overlap at the centre")


func test_empty_window_skips() -> void:
	var rl := RegionLabelRenderer.new()
	# A 24-mile hex whose children are NOT in the window → no members (the common out-of-window case).
	check(rl._project_members("[[99,99]]", {Vector2i(0, 0): true}).is_empty(),
		"a region with no in-window children projects to nothing")
