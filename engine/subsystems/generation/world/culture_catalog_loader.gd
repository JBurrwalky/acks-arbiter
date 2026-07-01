class_name CultureCatalogLoader
extends RefCounted

## Loads the canonical culture records from data/cultures/*.json
## (gdd-culture-catalog.md §3). These are READ-ONLY inputs to the pipeline —
## never written back (per-campaign jitter applies to instances, §6.5).
##
## Cached per process: the 65 records are stable across campaigns. Returns
## records keyed by culture_id, each the parsed {schema_version, mechanical,
## flavor} dict exactly as on disk.

const CULTURES_DIR := "res://data/cultures/"

static var _cache: Dictionary = {}
static var _loaded: bool = false
static var _pair_lookup: Dictionary = {}        # unordered parent-pair key -> hybrid culture_id
static var _pair_lookup_built: bool = false


## { culture_id: record_dict }, loaded once and cached.
static func load_all() -> Dictionary:
	if _loaded:
		return _cache
	_cache = {}
	var dir := DirAccess.open(CULTURES_DIR)
	if dir == null:
		push_error("CultureCatalogLoader: cannot open %s" % CULTURES_DIR)
		_loaded = true
		return _cache
	var files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()  # deterministic load order
	for f in files:
		var text := FileAccess.get_file_as_string(CULTURES_DIR + f)
		if text.is_empty():
			push_warning("CultureCatalogLoader: empty file %s" % f)
			continue
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("CultureCatalogLoader: %s is not a JSON object" % f)
			continue
		var cid := _culture_id_of(parsed)
		if cid.is_empty():
			push_error("CultureCatalogLoader: %s missing identity.culture_id" % f)
			continue
		_cache[cid] = parsed
	_loaded = true
	return _cache


## Test/regen hook — drop the cache so a re-load re-reads disk.
static func clear_cache() -> void:
	_cache = {}
	_loaded = false
	_pair_lookup = {}
	_pair_lookup_built = false


# --- Field accessors (tolerant of the stripped beastman schema, §5.3) -------

static func mechanical(record: Dictionary) -> Dictionary:
	return record.get("mechanical", {})


static func identity(record: Dictionary) -> Dictionary:
	return mechanical(record).get("identity", {})


static func culture_id(record: Dictionary) -> String:
	return str(identity(record).get("culture_id", ""))


static func tier(record: Dictionary) -> String:
	return str(identity(record).get("tier", "human"))


## "base" | "hybrid" | "member" — the base/hybrid culture-emergence model
## (gdd-culture-emergence-and-territory.md §3.1/§3.6). Only the 11 human BASE
## cultures carry culture_class="base"; the 55 first-order hybrids carry "hybrid"
## (seed-excluded, looked up by parent pair on emergence). The seeder restricts
## the human seed pool to bases. Records that omit the field default to "member".
static func culture_class(record: Dictionary) -> String:
	return str(identity(record).get("culture_class", "member"))


## [base_a_id, base_b_id] for a hybrid record (gdd §3.6); [] for base/member.
static func culture_synthesis_parents(record: Dictionary) -> Array:
	return identity(record).get("culture_synthesis_parents", [])


static func race(record: Dictionary) -> String:
	return str(identity(record).get("race", "human"))


static func toponym(record: Dictionary) -> String:
	return str(identity(record).get("toponym", ""))


static func seed_biomes(record: Dictionary) -> Array:
	return mechanical(record).get("terrain", {}).get("seed_biomes", [])


static func coastal_start(record: Dictionary) -> String:
	return str(mechanical(record).get("terrain", {}).get("coastal_start", "E"))


static func alignment_allowed(record: Dictionary) -> Array:
	return mechanical(record).get("alignment", {}).get("allowed", [])


## Explicit prevalence weights ({alignment: float}) or {} for the even-split
## default (§4.2). Keys are canonical-cased as authored (Lawful/Neutral/Chaotic).
static func alignment_weights(record: Dictionary) -> Dictionary:
	return mechanical(record).get("alignment", {}).get("weights", {})


static func phonemic_palette(record: Dictionary) -> String:
	return str(record.get("flavor", {}).get("phonemic_palette", ""))


static func sphere_weights(record: Dictionary) -> Dictionary:
	return mechanical(record).get("rulership", {}).get("sphere_weights", {})


## NPC personality mean-shift biases ({ axis: float }, partial; range -2.0..+2.0)
## per gdd-cultural-religious-generation.md §2.1. Consumed by the NPC personality
## generator (gdd-npc-personality.md §4.1 step 2c). {} when the record omits them.
static func personality_weight_biases(record: Dictionary) -> Dictionary:
	return mechanical(record).get("npc", {}).get("personality_weight_biases", {})


## Convenience: personality biases for a culture by id, or {} when the culture is
## unknown. Loads (and caches) the catalog on first call.
static func biases_for_culture(culture_id: String) -> Dictionary:
	if culture_id.is_empty():
		return {}
	var rec: Variant = load_all().get(culture_id, null)
	if rec is Dictionary:
		return personality_weight_biases(rec)
	return {}


static func ids_by_tier(t: String) -> Array:
	var out: Array = []
	var keys := load_all().keys()
	keys.sort()
	for cid in keys:
		if tier(_cache[cid]) == t:
			out.append(cid)
	return out


static func id_for_beastman_race(r: String) -> String:
	var keys := load_all().keys()
	keys.sort()
	for cid in keys:
		var rec: Dictionary = _cache[cid]
		if tier(rec) == "beastman" and race(rec) == r:
			return cid
	return ""


static func _culture_id_of(record: Dictionary) -> String:
	return str(record.get("mechanical", {}).get("identity", {}).get("culture_id", ""))


# --- Parent-pair -> hybrid lookup (gdd-culture-emergence-and-territory.md §3.6) ---
# Built once by scanning the hybrid catalog records' culture_synthesis_parents;
# no separate definition-table file. The key is order-independent, so
# hybrid_for_parents(a, b) == hybrid_for_parents(b, a).

## The hybrid culture_id for the unordered BASE pair {a, b}, or "" if none is
## defined (or a == b, or either is unknown). First-order only: both inputs must
## be base culture_ids. Loads/caches the catalog on first call.
static func hybrid_for_parents(a: String, b: String) -> String:
	if not _pair_lookup_built:
		_build_pair_lookup()
	return str(_pair_lookup.get(_pair_key(a, b), ""))


static func _pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)


static func _build_pair_lookup() -> void:
	_pair_lookup = {}
	var recs := load_all()
	var keys := recs.keys()
	keys.sort()   # deterministic; a pair maps to at most one hybrid anyway
	for cid in keys:
		var rec: Dictionary = recs[cid]
		if culture_class(rec) != "hybrid":
			continue
		var parents := culture_synthesis_parents(rec)
		if parents.size() == 2:
			_pair_lookup[_pair_key(str(parents[0]), str(parents[1]))] = str(cid)
	_pair_lookup_built = true
