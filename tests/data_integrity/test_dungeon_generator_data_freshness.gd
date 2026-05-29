extends "res://tests/test_suite_base.gd"

## Data-integrity test for data/dungeon_generator/*.json.
##
## Per coding_conventions.md §7.4.4 every extracted dataset MUST be covered
## by a freshness test that:
##   1. re-runs the extraction script into a temp directory
##   2. diffs each freshly-extracted JSON against the committed copy
##   3. fails if any difference exists
##
## We satisfy this by shelling out to the extraction script's own --check mode,
## which performs the diff in Python (single source of truth, no GDScript
## re-implementation of the extraction). The script also validates that every
## random_monsters_by_level cell tokenises cleanly into
## {monster_name, number_appearing_dice}, per the DG-V1.A build plan.
##
## Plus targeted sanity tests on the on-disk JSON: required files present,
## every file carries the §7.4.2-mandatory `_source` field, and structural
## consistency (`columns` length == row dict keys).

const SCRIPT_REL_PATH := "res://tools/extract_dungeon_generator_data.py"
const DATA_DIR_REL_PATH := "res://data/dungeon_generator"

const EXPECTED_FILES: Array[String] = [
	"dungeon_stocking.json",
	"unprotected_treasure.json",
	"dungeon_wandering_monster_level.json",
	"wandering_monster_table_guidelines.json",
	"random_monsters_by_level.json",
	"npc_class.json",
	"npc_alignment.json",
	"npc_level.json",
	"npc_treasure_type_by_level.json",
	"treasure_type_table.json",
	"gem_values.json",
	"jewelry_values.json",
]


func run_all_tests() -> void:
	test_all_expected_files_exist()
	test_each_file_has_source_field()
	test_each_file_columns_match_row_keys()
	test_extraction_script_check_mode_passes()
	if not has_failures():
		print("DungeonGeneratorDataFreshness: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_all_expected_files_exist() -> void:
	for filename in EXPECTED_FILES:
		var path := "%s/%s" % [DATA_DIR_REL_PATH, filename]
		check(FileAccess.file_exists(path),
			"Expected data file missing: %s. Run `python tools/extract_dungeon_generator_data.py`."
				% path)


func test_each_file_has_source_field() -> void:
	for filename in EXPECTED_FILES:
		var payload: Variant = _load_json(filename)
		if payload == null:
			continue  # absent-file failure already reported by test_all_expected_files_exist
		check(payload is Dictionary and (payload as Dictionary).has("_source"),
			"%s is missing the `_source` field required by coding_conventions §7.4.2." % filename)
		if payload is Dictionary and (payload as Dictionary).has("_source"):
			var src: String = str((payload as Dictionary)["_source"])
			check(src.begins_with("rules/"),
				"%s `_source` does not cite a `rules/...` XML path (got %s)." % [filename, src])


func test_each_file_columns_match_row_keys() -> void:
	for filename in EXPECTED_FILES:
		var payload: Variant = _load_json(filename)
		if payload == null or not (payload is Dictionary):
			continue
		var payload_dict: Dictionary = payload
		var columns: Array = payload_dict.get("columns", [])
		var rows: Array = payload_dict.get("rows", [])
		check(columns.size() > 0, "%s has no columns." % filename)
		check(rows.size() > 0, "%s has no rows." % filename)
		for i in rows.size():
			var row: Variant = rows[i]
			if not (row is Dictionary):
				check(false, "%s row %d is not a Dictionary." % [filename, i])
				continue
			var row_dict: Dictionary = row
			check(row_dict.size() == columns.size(),
				"%s row %d has %d keys but columns expects %d."
					% [filename, i, row_dict.size(), columns.size()])
			for col in columns:
				check(row_dict.has(col),
					"%s row %d missing column %s." % [filename, i, col])


func test_extraction_script_check_mode_passes() -> void:
	# Locate the Python interpreter. We try POSIX `python3` first then `python`
	# (Windows). On Windows 11 both resolve via WindowsApps shims.
	var python_path: String = _find_python()
	if python_path.is_empty():
		check(false,
			"No Python interpreter found on PATH. The data-freshness gate "
			+ "cannot run; install Python 3 or expose `python` / `python3`.")
		return

	var script_path: String = ProjectSettings.globalize_path(SCRIPT_REL_PATH)
	check(FileAccess.file_exists(SCRIPT_REL_PATH),
		"Extraction script missing at %s." % SCRIPT_REL_PATH)
	if not FileAccess.file_exists(SCRIPT_REL_PATH):
		return

	var output: Array = []
	var exit_code: int = OS.execute(python_path, [script_path, "--check"], output, true)
	var combined: String = "\n".join(output)
	var fail_msg: String = (
		"extract_dungeon_generator_data.py --check failed (exit %d).\n"
		+ "Fix: run `python tools/extract_dungeon_generator_data.py` and "
		+ "commit the regenerated JSON.\nScript output:\n%s"
	) % [exit_code, combined]
	check(exit_code == 0, fail_msg)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _load_json(filename: String) -> Variant:
	var path: String = "%s/%s" % [DATA_DIR_REL_PATH, filename]
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "Could not open %s for reading." % path)
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		check(false, "Could not parse %s as JSON." % path)
	return parsed


func _find_python() -> String:
	# Probe a small set of interpreter names. Each probe uses OS.execute with
	# the canonical name; if the OS returns -1, that name is not on PATH.
	for candidate in ["python3", "python"]:
		var output: Array = []
		var rc: int = OS.execute(candidate, ["--version"], output, true)
		if rc >= 0:
			return candidate
	return ""
