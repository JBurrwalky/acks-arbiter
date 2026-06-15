class_name NameBankLoader
extends RefCounted

## Loads the static per-culture name banks from data/name_banks/*.json
## (gdd-naming-conventions.md §13). These are COMMITTED assets assembled
## offline by tools/build_name_banks.py from the conlang kits (data/conlang/);
## runtime naming (Layer 5 / Stage 6) is pure table lookup over them.
##
## Cached per process: the 65 banks are stable across campaigns. Each bank is
## the parsed dict exactly as on disk:
##   { culture_id, kit_id, tier, race, family, government, alignment_allowed,
##     categories: { personal_male, personal_female, clan_house, epithet,
##                   settlement, feature, [military_unit, dungeon_ruin,
##                   ship, tavern] },
##     titles, religion, patterns, morphology }
##
## _manifest.json (the index) is skipped on load — query it via the tool, not
## here. The build tool's --check mode is the freshness gate
## (tests/test_setting_name_banks.gd), so this loader never re-derives a bank.

const BANKS_DIR := "res://data/name_banks/"
const MANIFEST_FILE := "_manifest.json"

## The categories every bank is guaranteed to carry (build tool's CORE_CATEGORIES).
const CORE_CATEGORIES: Array[String] = [
	"personal_male", "personal_female", "clan_house",
	"epithet", "settlement", "feature",
]

static var _cache: Dictionary = {}
static var _loaded: bool = false


## { culture_id: bank_dict }, loaded once and cached. The manifest is excluded.
static func load_all() -> Dictionary:
	if _loaded:
		return _cache
	_cache = {}
	var dir := DirAccess.open(BANKS_DIR)
	if dir == null:
		push_error("NameBankLoader: cannot open %s" % BANKS_DIR)
		_loaded = true
		return _cache
	var files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json") and fname != MANIFEST_FILE:
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()  # deterministic load order
	for f in files:
		var text := FileAccess.get_file_as_string(BANKS_DIR + f)
		if text.is_empty():
			push_warning("NameBankLoader: empty file %s" % f)
			continue
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("NameBankLoader: %s is not a JSON object" % f)
			continue
		var cid := str(parsed.get("culture_id", ""))
		if cid.is_empty():
			push_error("NameBankLoader: %s missing culture_id" % f)
			continue
		_cache[cid] = parsed
	_loaded = true
	return _cache


## The bank for one culture, or {} if no bank exists.
static func bank_for(culture_id: String) -> Dictionary:
	return load_all().get(culture_id, {})


## Test/regen hook — drop the cache so a re-load re-reads disk.
static func clear_cache() -> void:
	_cache = {}
	_loaded = false


# --- Field accessors --------------------------------------------------------

static func race(bank: Dictionary) -> String:
	return str(bank.get("race", "human"))


static func government(bank: Dictionary) -> String:
	return str(bank.get("government", ""))


static func family(bank: Dictionary) -> Array:
	return bank.get("family", [])


## The whole category map, or {} for a missing/empty bank.
static func categories(bank: Dictionary) -> Dictionary:
	return bank.get("categories", {})


## The name pool for one category (e.g. "personal_male"), or [] if absent.
static func names(bank: Dictionary, category: String) -> Array:
	return categories(bank).get(category, [])


## The full title ladder ({government, tiers, female_forms, honorifics, ...}).
static func titles(bank: Dictionary) -> Dictionary:
	return bank.get("titles", {})


## Ruler title for an ACKS tier name ("barony".."empire"), "" if absent.
static func ruler_title(bank: Dictionary, tier_name: String) -> String:
	var tiers: Dictionary = titles(bank).get("tiers", {})
	var entry = tiers.get(tier_name, {})
	if typeof(entry) == TYPE_DICTIONARY:
		return str(entry.get("ruler", ""))
	return ""


## Domain title for an ACKS tier name (civ cultures), "" for beastman (scope-only).
static func domain_title(bank: Dictionary, tier_name: String) -> String:
	var tiers: Dictionary = titles(bank).get("tiers", {})
	var entry = tiers.get(tier_name, {})
	if typeof(entry) == TYPE_DICTIONARY:
		return str(entry.get("domain", ""))
	return ""


static func religion(bank: Dictionary) -> Dictionary:
	return bank.get("religion", {})


static func patterns(bank: Dictionary) -> Dictionary:
	return bank.get("patterns", {})


static func morphology(bank: Dictionary) -> Dictionary:
	return bank.get("morphology", {})


## All culture_ids of a given race ("human"/"beastman"/"elf"/"dwarf"), sorted.
static func ids_by_race(r: String) -> Array:
	var out: Array = []
	var keys := load_all().keys()
	keys.sort()
	for cid in keys:
		if race(_cache[cid]) == r:
			out.append(cid)
	return out
