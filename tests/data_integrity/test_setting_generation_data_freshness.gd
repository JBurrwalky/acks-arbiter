extends "res://tests/test_suite_base.gd"

## Data-integrity test for data/setting_generation/beastman_distribution.json
## (coding_conventions.md §7.4.4).
##
## Shells out to the extraction script's own --check mode (the diff lives in
## Python, never re-implemented in GDScript) to catch "edited the rules XML but
## forgot to re-extract" and "hand-edited the JSON". Plus on-disk sanity: the
## file exists, carries the §7.4.2 _source field citing a rules/ path, and the
## d100 race ranges are gap-free and end at 100 for every terrain.

const SCRIPT_REL_PATH := "res://tools/extract_setting_generation_data.py"
const JSON_REL_PATH := "res://data/setting_generation/beastman_distribution.json"


func run_all_tests() -> void:
	test_file_exists_and_has_source()
	test_terrain_columns_present()
	test_d100_ranges_contiguous()
	test_extraction_script_check_mode_passes()
	if not has_failures():
		print("SettingGenerationDataFreshness: all tests passed.")


func test_file_exists_and_has_source() -> void:
	check(FileAccess.file_exists(JSON_REL_PATH),
		"beastman_distribution.json missing. Run `python tools/extract_setting_generation_data.py`.")
	var payload = _load_json()
	if payload == null:
		return
	check(payload is Dictionary, "payload is not a JSON object")
	check(str(payload.get("_source", "")).begins_with("rules/"),
		"missing/invalid _source field (must cite a rules/ path)")
	check(payload.has("clanhold_demographics") and payload.has("clanholds_by_terrain"),
		"payload missing top-level tables")


func test_terrain_columns_present() -> void:
	var payload = _load_json()
	if payload == null:
		return
	var by_terrain: Dictionary = payload.get("clanholds_by_terrain", {})
	for terrain in ["clear_grass", "scrub", "woods", "river", "swamp",
			"hills", "mountains", "barren", "desert", "jungle"]:
		check(by_terrain.has(terrain), "missing terrain column: %s" % terrain)
	var demo: Dictionary = payload.get("clanhold_demographics", {})
	check(demo.size() == 10, "expected 10 beastman races in demographics, got %d" % demo.size())


func test_d100_ranges_contiguous() -> void:
	# Post-patch (the river gnoll 14->13 RAW correction), every terrain's race
	# ranges must be gap-free 1..100.
	var payload = _load_json()
	if payload == null:
		return
	var by_terrain: Dictionary = payload.get("clanholds_by_terrain", {})
	for terrain in by_terrain:
		var ranges: Array = by_terrain[terrain].get("race_d100", [])
		var pairs: Array = []
		for entry in ranges:
			pairs.append([int(entry["lo"]), int(entry["hi"])])
		pairs.sort_custom(func(a, b): return a[0] < b[0])
		var prev_hi := 0
		for p in pairs:
			check(p[0] == prev_hi + 1, "%s d100 gap/overlap at %d-%d" % [terrain, p[0], p[1]])
			prev_hi = p[1]
		check(prev_hi == 100, "%s d100 ranges end at %d, not 100" % [terrain, prev_hi])


func test_extraction_script_check_mode_passes() -> void:
	var python_path := _find_python()
	if python_path.is_empty():
		check(false, "No Python interpreter on PATH; the data-freshness gate cannot run.")
		return
	var script_path := ProjectSettings.globalize_path(SCRIPT_REL_PATH)
	check(FileAccess.file_exists(SCRIPT_REL_PATH), "extraction script missing at %s" % SCRIPT_REL_PATH)
	if not FileAccess.file_exists(SCRIPT_REL_PATH):
		return
	var output: Array = []
	var exit_code := OS.execute(python_path, [script_path, "--check"], output, true)
	var combined := "\n".join(output)
	check(exit_code == 0,
		("extract_setting_generation_data.py --check failed (exit %d).\n"
		+ "Fix: run `python tools/extract_setting_generation_data.py` and commit "
		+ "the regenerated JSON.\nOutput:\n%s") % [exit_code, combined])


# --- Helpers ----------------------------------------------------------------

func _load_json() -> Variant:
	if not FileAccess.file_exists(JSON_REL_PATH):
		return null
	var f := FileAccess.open(JSON_REL_PATH, FileAccess.READ)
	if f == null:
		check(false, "could not open %s" % JSON_REL_PATH)
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _find_python() -> String:
	for candidate in ["python3", "python"]:
		var output: Array = []
		var rc := OS.execute(candidate, ["--version"], output, true)
		if rc >= 0:
			return candidate
	return ""
