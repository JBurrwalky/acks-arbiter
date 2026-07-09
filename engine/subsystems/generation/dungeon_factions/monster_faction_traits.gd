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
	for mt in (entry.get("monster_types", []) as Array):
		types.append(String(mt))
	var hit_dice: Dictionary = entry.get("hit_dice", {}) if entry.get("hit_dice") is Dictionary else {}
	var base: float = float(hit_dice.get("base", 1)) if hit_dice.has("base") else 1.0
	var stars: int = int(hit_dice.get("special_ability_stars", 0)) if hit_dice.has("special_ability_stars") else 0
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
		"morale": int(entry.get("morale", 0)) if entry.get("morale") != null else 0,
		"is_undead": types.has("undead"),
		"has_special_abilities": special,
	}
