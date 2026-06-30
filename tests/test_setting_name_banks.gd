extends "res://tests/test_suite_base.gd"

## Stage 5: the static name banks (data/name_banks/*.json) assembled by
## tools/build_name_banks.py from the conlang kits (gdd-naming-conventions.md
## §13, handoff §6 Stage 5). Validates that every culture's bank loads through
## NameBankLoader with the guaranteed core categories, that the loader
## accessors work for both the civ and beastman shapes, that inheritance is
## recorded, and (the freshness gate) that the committed banks match a fresh
## build — the diff lives in the Python tool's --check mode, never re-derived
## here (data-freshness pattern, coding_conventions.md §7.4.4).

const SCRIPT_REL_PATH := "res://tools/build_name_banks.py"
const BANKS_DIR := "res://data/name_banks/"
const MIN_CORE := 10
# 11 human BASE kits + 55 first-order HYBRID kits (all 11C2 base pairs) + 6 demihuman
# + 10 beastman banks assembled by build_name_banks.py (gdd-culture-emergence-and-
# territory.md §3.5). 40 legacy single-culture member kits were retired 2026-06-29 (the
# bases + runtime hybrids supersede them; the old roster was never seeded). The freshness
# gate (test_build_tool_check_mode_passes) is the real authority on the set; this count is
# a coarse tripwire for accidental add/drop.
const EXPECTED_BANK_COUNT := 82


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	test_all_banks_load_with_core_categories()
	test_loader_accessors_civ()
	test_loader_accessors_beastman()
	test_inheritance_recorded()
	test_endonym_only()
	test_manifest_excluded_from_load()
	test_build_tool_check_mode_passes()
	if not has_failures():
		print("SettingNameBanksTests: all tests passed (%d checks)" % test_count())


func test_all_banks_load_with_core_categories() -> void:
	var banks := NameBankLoader.load_all()
	check(banks.size() == EXPECTED_BANK_COUNT,
		"expected %d banks, loaded %d" % [EXPECTED_BANK_COUNT, banks.size()])
	for cid in banks:
		var bank: Dictionary = banks[cid]
		check(str(bank.get("culture_id", "")) == cid,
			"%s: culture_id mismatch" % cid)
		var cats := NameBankLoader.categories(bank)
		check(not cats.is_empty(), "%s: no categories" % cid)
		for core in NameBankLoader.CORE_CATEGORIES:
			var pool := NameBankLoader.names(bank, core)
			check(pool.size() >= MIN_CORE,
				"%s: core category '%s' has %d (< %d)" % [cid, core, pool.size(), MIN_CORE])
			# de-dup invariant (case-insensitive) over every core pool
			var seen := {}
			var dupe := false
			for n in pool:
				var key := str(n).to_lower()
				if seen.has(key):
					dupe = true
				seen[key] = true
			check(not dupe, "%s: category '%s' has duplicates" % [cid, core])


func test_loader_accessors_civ() -> void:
	var bank := NameBankLoader.bank_for("quirium")
	check(not bank.is_empty(), "quirium bank should load")
	check(NameBankLoader.race(bank) == "human", "quirium race should be human")
	check(NameBankLoader.government(bank) == "feudal", "quirium government feudal")
	check(NameBankLoader.names(bank, "personal_male").has("Marcus"),
		"quirium personal_male should include the seed 'Marcus'")
	check(NameBankLoader.ruler_title(bank, "empire") == "Imperator",
		"quirium empire ruler should be the approved foreign term Imperator")
	check(NameBankLoader.domain_title(bank, "kingdom") == "Kingdom",
		"quirium kingdom domain displays as the English 'Kingdom'")
	check(not NameBankLoader.religion(bank).is_empty(), "quirium carries religion block")


func test_loader_accessors_beastman() -> void:
	var bank := NameBankLoader.bank_for("orc")
	check(not bank.is_empty(), "orc bank should load")
	check(NameBankLoader.race(bank) == "beastman", "orc race should be beastman")
	# beastman tiers carry a ruler but no domain (scope-only ladder)
	check(NameBankLoader.ruler_title(bank, "barony") != "",
		"orc barony should carry a ruler title")
	check(NameBankLoader.domain_title(bank, "barony") == "",
		"orc tiers are scope-only (no domain title)")
	# beastmen have no ship/tavern pools (not seafarers/tavern-keepers)
	check(NameBankLoader.names(bank, "ship").is_empty(),
		"beastman bank should carry no ship pool")
	check(NameBankLoader.ids_by_race("beastman").size() == 10,
		"there should be 10 beastman banks")


func test_inheritance_recorded() -> void:
	var quirium := NameBankLoader.bank_for("quirium")
	check(NameBankLoader.family(quirium) == ["classical"],
		"quirium inherits the single classical family")
	var aryamark := NameBankLoader.bank_for("aryamark")
	check(NameBankLoader.family(aryamark).size() == 2,
		"a hybrid (aryamark) is a cross-family blend of two bases")


func test_endonym_only() -> void:
	# gdd-naming-conventions.md §14: NO exonym fields anywhere (endonym-only).
	for cid in NameBankLoader.load_all():
		var bank: Dictionary = NameBankLoader.load_all()[cid]
		check(not JSON.stringify(bank).to_lower().contains("exonym"),
			"%s: bank carries an exonym field (endonym-only rule)" % cid)


func test_manifest_excluded_from_load() -> void:
	# _manifest.json exists on disk but is the index, not a bank.
	check(FileAccess.file_exists(BANKS_DIR + "_manifest.json"),
		"_manifest.json should exist")
	check(not NameBankLoader.load_all().has("_manifest"),
		"the manifest must not be loaded as a culture bank")


func test_build_tool_check_mode_passes() -> void:
	var python_path := _find_python()
	if python_path.is_empty():
		check(false, "No Python interpreter on PATH; the name-bank freshness gate cannot run.")
		return
	check(FileAccess.file_exists(SCRIPT_REL_PATH), "build tool missing at %s" % SCRIPT_REL_PATH)
	if not FileAccess.file_exists(SCRIPT_REL_PATH):
		return
	var script_path := ProjectSettings.globalize_path(SCRIPT_REL_PATH)
	var output: Array = []
	var exit_code := OS.execute(python_path, [script_path, "--check"], output, true)
	var combined := "\n".join(output)
	check(exit_code == 0,
		("build_name_banks.py --check failed (exit %d).\n"
		+ "Fix: run `python tools/build_name_banks.py` and commit the regenerated "
		+ "banks.\nOutput:\n%s") % [exit_code, combined])


# --- Helpers ----------------------------------------------------------------

func _find_python() -> String:
	for candidate in ["python3", "python"]:
		var output: Array = []
		var rc := OS.execute(candidate, ["--version"], output, true)
		if rc >= 0:
			return candidate
	return ""
