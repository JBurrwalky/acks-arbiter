class_name MonsterFactionTraits
extends RefCounted

## Monster-catalog trait lookup for faction generation. MonsterGroupData carries
## name / number / lair / alignment / morale but NOT the intelligence rating,
## monster_types, per-creature HD, or organization data the faction identifier
## needs (`gdd-dungeon-factions.md` §3). This loads data/monsters/monster_catalog.json
## and exposes those traits keyed by catalog id and by (lower-cased) name.
##
## Read-only, cached at first use. Deterministic (pure data lookup).


const _CATALOG_PATH := "res://data/monsters/monster_catalog.json"

static var _by_id: Dictionary = {}
static var _by_name: Dictionary = {}
static var _loaded: bool = false


## { "id","intelligence","monster_types","alignment","hd","morale",
##   "is_undead","has_special_abilities","patrol_dice" } for the given monster
## name or id, or an empty Dictionary if unknown.
static func traits_for(name_or_id: String) -> Dictionary:
	_ensure_loaded()
	var key: String = name_or_id.to_lower()
	if _by_id.has(key):
		return _by_id[key]
	if _by_name.has(key):
		return _by_name[key]
	return {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_CATALOG_PATH):
		push_warning("MonsterFactionTraits: catalog not found at %s" % _CATALOG_PATH)
		return
	var text: String = FileAccess.get_file_as_string(_CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_warning("MonsterFactionTraits: catalog is not a JSON array.")
		return
	for entry in parsed:
		if not (entry is Dictionary):
			continue
		var t: Dictionary = _extract(entry)
		var id_key: String = String(entry.get("id", "")).to_lower()
		var name_key: String = String(entry.get("name", "")).to_lower()
		if id_key != "":
			_by_id[id_key] = t
		if name_key != "":
			_by_name[name_key] = t


static func _extract(entry: Dictionary) -> Dictionary:
	var types: Array[String] = []
	# .get()'s default only applies to a MISSING key — a present null / non-array
	# value would make `for mt in (null as Array)` crash mid-load, aborting the parse
	# AFTER _loaded=true and leaving traits_for() empty forever (review #10).
	var raw_types: Variant = entry.get("monster_types", [])
	if raw_types is Array:
		for mt in (raw_types as Array):
			types.append(String(mt))
	var hit_dice: Dictionary = entry.get("hit_dice", {}) if entry.get("hit_dice") is Dictionary else {}
	# Numeric fields go through _num so a non-scalar catalog value (e.g. "morale": {})
	# defaults instead of crashing int()/float() mid-load — the same failure mode the
	# monster_types guard above targets (review #10 follow-up).
	var base: float = _num(hit_dice.get("base"), 1.0)
	var stars: int = int(_num(hit_dice.get("special_ability_stars"), 0.0))
	var special: bool = stars > 0
	var abilities: Variant = entry.get("special_abilities", null)
	if abilities is Array and not (abilities as Array).is_empty():
		special = true
	return {
		"id": String(entry.get("id", "")),
		"intelligence": String(entry.get("intelligence", "low")).to_lower(),
		"monster_types": types,
		"alignment": String(entry.get("alignment", "neutral")).to_lower(),
		"hd": base,
		"morale": int(_num(entry.get("morale"), 0.0)),
		"is_undead": types.has("undead"),
		"has_special_abilities": special,
	}


## Numeric coercion that never crashes on a non-scalar catalog value: int()/float()
## of a Dictionary/Array throws. Accepts int/float and numeric strings; anything else
## (Dictionary/Array/null/non-numeric string) -> [param default_value].
static func _num(v: Variant, default_value: float = 0.0) -> float:
	if v is int or v is float:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return (v as String).to_float()
	return default_value
