extends "res://tests/test_suite_base.gd"

## Data-integrity test for data/templates/class_templates.json
## (coding_conventions.md §7.4.4).
##
## Shells out to the importer's own --check mode (which re-imports from
## rules/pc_class_templates.md + the curated override files into memory and diffs
## against the committed JSON), so the diff logic lives in one place — Python —
## and is never re-implemented in GDScript. This catches "edited the source/rules
## but forgot to re-run the importer" and "hand-edited the JSON".
##
## Plus on-disk sanity: the file exists, carries the §7.4.2 _source field citing
## a rules/ path, and holds 216 templates.

const SCRIPT_REL_PATH := "res://tools/import_class_templates.py"
const JSON_REL_PATH := "res://data/templates/class_templates.json"
const WEALTH_SWEEP_REL_PATH := "res://data/templates/wealth_sweep.md"


func run_all_tests() -> void:
	test_file_exists_and_has_source()
	test_template_count()
	test_wealth_sweep_artifact()
	test_import_script_check_mode_passes()
	if not has_failures():
		print("ClassTemplatesDataFreshness: all tests passed.")


func test_wealth_sweep_artifact() -> void:
	# The §10 step 8 wealth-sweep report is emitted alongside class_templates.json;
	# its staleness is gated by `--check` (test_import_script_check_mode_passes).
	check(FileAccess.file_exists(WEALTH_SWEEP_REL_PATH),
		"wealth_sweep.md missing. Run `python tools/import_class_templates.py`.")
	if not FileAccess.file_exists(WEALTH_SWEEP_REL_PATH):
		return
	var f := FileAccess.open(WEALTH_SWEEP_REL_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	check(text.begins_with("# Class Template Wealth Sweep"),
		"wealth_sweep.md has an unexpected header")
	check(text.contains("Flagged deviations"),
		"wealth_sweep.md is missing the flagged-deviations section")


func test_file_exists_and_has_source() -> void:
	check(FileAccess.file_exists(JSON_REL_PATH),
		"class_templates.json missing. Run `python tools/import_class_templates.py`.")
	var payload: Variant = _load_json()
	if payload == null:
		return
	check(payload is Dictionary and (payload as Dictionary).has("_source"),
		"class_templates.json missing `_source` (coding_conventions §7.4.2).")
	if payload is Dictionary and (payload as Dictionary).has("_source"):
		var src: String = str((payload as Dictionary)["_source"])
		check(src.begins_with("rules/"),
			"_source must cite a rules/ path, got %s" % src)


func test_template_count() -> void:
	var payload: Variant = _load_json()
	if not (payload is Dictionary):
		return
	var templates: Array = (payload as Dictionary).get("templates", [])
	check(templates.size() == 216,
		"expected 216 templates in class_templates.json, got %d" % templates.size())


func test_import_script_check_mode_passes() -> void:
	var python_path := _find_python()
	if python_path.is_empty():
		check(false, "No Python interpreter on PATH; the data-freshness gate "
			+ "cannot run. Install Python 3 or expose `python` / `python3`.")
		return
	check(FileAccess.file_exists(SCRIPT_REL_PATH),
		"importer missing at %s" % SCRIPT_REL_PATH)
	if not FileAccess.file_exists(SCRIPT_REL_PATH):
		return
	var script_path := ProjectSettings.globalize_path(SCRIPT_REL_PATH)
	var output: Array = []
	var exit_code := OS.execute(python_path, [script_path, "--check"], output, true)
	var combined: String = "\n".join(output)
	check(exit_code == 0,
		("import_class_templates.py --check failed (exit %d).\nFix: run "
		+ "`python tools/import_class_templates.py` and commit the regenerated "
		+ "data/templates/class_templates.json.\nOutput:\n%s") % [exit_code, combined])


func _load_json() -> Variant:
	if not FileAccess.file_exists(JSON_REL_PATH):
		return null
	var f := FileAccess.open(JSON_REL_PATH, FileAccess.READ)
	if f == null:
		check(false, "could not open class_templates.json for reading")
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		check(false, "could not parse class_templates.json as JSON")
	return parsed


func _find_python() -> String:
	for candidate in ["python3", "python"]:
		var output: Array = []
		var rc := OS.execute(candidate, ["--version"], output, true)
		if rc >= 0:
			return candidate
	return ""
