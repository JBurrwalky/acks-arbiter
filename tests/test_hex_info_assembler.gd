extends "res://tests/test_suite_base.gd"

## Unit tests for HexInfoAssembler (the "Get Hex Info" dev modal's data layer).
##  1. Pure helpers: the 6-mile→24-mile parent coordinate bridge, JSON hex membership,
##     weight formatting, market-class roman numerals.
##  2. Smoke: assemble() on a minimal fixture campaign returns ordered sections without
##     crashing, surfaces the "lair budget not yet rolled" branch, and skips the setting
##     layer for a non-generated campaign.

const _CID := "hex_info_test_campaign"
const _MAP := "hex_info_test_map"


func run_all_tests() -> void:
	test_parent_axial_bridge()
	test_json_has_hex()
	test_fmt_weights()
	test_roman()
	_setup_db()
	test_assemble_smoke()
	_teardown_db()
	if not has_failures():
		print("HexInfoAssembler: all tests passed.")


func test_parent_axial_bridge() -> void:
	# A 24-mile parent at offset (1,0) owns 16 six-mile children at offsets
	# (4..7, 0..3). Every one of those children must resolve back to parent (1,0).
	var parent_axial := WorldGrid.offset_to_axial(1, 0)
	var all_ok := true
	for lx in range(4):
		for ly in range(4):
			var child := WorldGrid.offset_to_axial(1 * 4 + lx, 0 * 4 + ly)
			if HexInfoAssembler._parent_axial(child.x, child.y) != parent_axial:
				all_ok = false
	check(all_ok, "all 16 six-mile children of parent offset (1,0) resolve back to it")
	# Negative-row guard (floor-div must be used, not int truncation).
	var pneg := WorldGrid.offset_to_axial(0, -1)   # negative offset row
	var cneg := WorldGrid.offset_to_axial(0, -1 * 4)
	check(HexInfoAssembler._parent_axial(cneg.x, cneg.y) == pneg,
		"a negative-row child floor-divides to the right parent")


func test_json_has_hex() -> void:
	check(HexInfoAssembler._json_has_hex("[[3,4],[5,6]]", 5, 6), "membership finds [5,6]")
	check(not HexInfoAssembler._json_has_hex("[[3,4],[5,6]]", 5, 7), "membership rejects absent hex")
	check(not HexInfoAssembler._json_has_hex("[]", 0, 0), "empty array → no membership")
	check(not HexInfoAssembler._json_has_hex("not json", 0, 0), "malformed JSON → no crash, no membership")


func test_fmt_weights() -> void:
	var s := HexInfoAssembler._fmt_weights('{"khemt":0.6,"valdor":0.4}')
	check(s.contains("khemt 60%") and s.contains("valdor 40%"), "weights render as k NN%% pairs (%s)" % s)
	check(HexInfoAssembler._fmt_weights("{}").contains("uninhabited"), "empty weights → uninhabited note")


func test_roman() -> void:
	check(HexInfoAssembler._roman(1) == "I" and HexInfoAssembler._roman(6) == "VI", "market class → roman")
	check(HexInfoAssembler._roman(9) == "9", "out-of-range falls back to the integer")


func test_assemble_smoke() -> void:
	var sections: Array = HexInfoAssembler.assemble(_CID, _MAP, 5, 5)
	check(sections.size() >= 8, "assemble returns the full section set (%d)" % sections.size())
	# Section ordering: terrain first.
	check(sections.size() > 0 and str((sections[0] as Dictionary).get("title", "")).contains("Terrain"),
		"first section is Coordinates / Terrain")
	# Every section is well-formed {title, rows[]}.
	var well_formed := true
	var found_lair_unrolled := false
	var found_setting_na := false
	for sec in sections:
		if not (sec is Dictionary and (sec as Dictionary).has("title") and (sec as Dictionary).has("rows")):
			well_formed = false
			continue
		for row in (sec as Dictionary)["rows"]:
			var v := str((row as Dictionary).get("value", ""))
			if v.contains("NOT YET ROLLED"):
				found_lair_unrolled = true
			if v.contains("fixture campaign"):
				found_setting_na = true
	check(well_formed, "every section is {title, rows[]}")
	check(found_lair_unrolled, "lair budget shows NOT YET ROLLED for an un-rolled hex (lazy, not zero)")
	check(found_setting_na, "fixture campaign (no setting_parameters) skips the setting layer with an n/a")


# ---------------------------------------------------------------------------
func _setup_db() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)", [_CID, "Hex Info Test"])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, ?)",
		[_MAP, _CID, "Test Map", "regional_6mi"])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_cells (map_id, q, r, elevation, biome, water, civilization) VALUES (?, ?, ?, 'flat', 'clear', '', 'wilderness')",
		[_MAP, 5, 5])


func _teardown_db() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("DELETE FROM hex_cells WHERE map_id = ?", [_MAP])
	db.query_with_bindings("DELETE FROM hex_maps WHERE id = ?", [_MAP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [_CID])
