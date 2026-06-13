class_name BeastmanDistributionLoader
extends RefCounted

## Loads the build-time-extracted beastman geographic distribution
## (data/setting_generation/beastman_distribution.json from
## tools/extract_setting_generation_data.py — RAW source
## ax_domains_of_chaos.xml §beastman_geographic_distribution_by_clan +
## §beastman_demographics, per docs/coding_conventions.md §7.4).
##
## Runtime systems consume the extracted JSON, never the XML. Cached per
## process.

const DATA_PATH := "res://data/setting_generation/beastman_distribution.json"

static var _cache: Dictionary = {}
static var _loaded: bool = false


## { clanholds_by_terrain: {...}, clanhold_demographics: {...} }.
static func load_data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		push_error("BeastmanDistributionLoader: cannot read %s" % DATA_PATH)
		_cache = {}
		return _cache
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BeastmanDistributionLoader: %s is not a JSON object" % DATA_PATH)
		_cache = {}
		return _cache
	_cache = parsed
	return _cache


static func clear_cache() -> void:
	_cache = {}
	_loaded = false
