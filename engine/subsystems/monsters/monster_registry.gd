class_name MonsterRegistry
extends RefCounted

## Loads monster definitions from data/monsters/monster_catalog.json.
## Provides monster lookup by ID, terrain-based queries, and type filtering.
## Follows the same pattern as SpellRegistry / ClassRegistry / ProficiencyRegistry.

const CATALOG_PATH := "res://data/monsters/monster_catalog.json"

## Parsed ONCE per process and shared by every MonsterRegistry instance
## (2026-08-06; the SheetRegistries / DragonVariantResolver static-cache
## precedent, conventions §42/§141). Before this, every `MonsterRegistry.new()`
## re-parsed the 750 KB catalog — 216 times per test run, ~0.6-1.0 GB
## retained across never-freed holders. CONTRACT: dictionaries handed out
## by get_monster()/get_hit_dice() are references INTO this shared catalog.
## Consumers must never write into them (every call site audited read-only
## 2026-08-06) — `duplicate(true)` first if you need a mutable copy.
static var _shared_monsters: Dictionary = {}

var _monsters: Dictionary = {}  # alias of _shared_monsters after _init


func _init() -> void:
	_load_catalog()


func _load_catalog() -> void:
	if not _shared_monsters.is_empty():
		_monsters = _shared_monsters
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("MonsterRegistry: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("MonsterRegistry: JSON parse error: %s" % json.get_error_message())
		return
	var parsed: Dictionary = {}
	var entries: Array = json.data
	for entry in entries:
		var id: String = entry.get("id", "")
		if id.is_empty():
			push_error("MonsterRegistry: Entry missing id: %s" % str(entry))
			continue
		parsed[id] = entry
	_shared_monsters = parsed
	_monsters = _shared_monsters
	print("MonsterRegistry: Loaded %d monster definitions" % _monsters.size())


# --- Core lookup ---

func get_monster(monster_id: String) -> Dictionary:
	if not _monsters.has(monster_id):
		push_error("MonsterRegistry: Unknown monster '%s'" % monster_id)
		return {}
	return _monsters[monster_id]


func has_monster(monster_id: String) -> bool:
	return _monsters.has(monster_id)


func get_monster_count() -> int:
	return _monsters.size()


func get_all_monster_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _monsters.keys():
		ids.append(key)
	ids.sort()
	return ids


# --- Terrain query ---

func get_monsters_for_terrain(terrain_key: String) -> Array[String]:
	## Returns all monster IDs whose terrain_affinity includes the given
	## encounter table key (e.g. "woods", "ocean", "mountains_hills").
	var result: Array[String] = []
	for id in _monsters:
		var affinity: Array = _monsters[id].get("terrain_affinity", [])
		if terrain_key in affinity:
			result.append(id)
	result.sort()
	return result


# --- Type query ---

func get_monsters_by_type(monster_type: String) -> Array[String]:
	## Returns all monster IDs whose monster_types includes the given type
	## (e.g. "beastman", "animal", "undead").
	var result: Array[String] = []
	for id in _monsters:
		var types: Array = _monsters[id].get("monster_types", [])
		if monster_type in types:
			result.append(id)
	result.sort()
	return result


func get_monsters_by_sub_type(sub_type: String) -> Array[String]:
	## Returns all monster IDs whose sub_types includes the given sub-type
	## (e.g. "goblinoid", "lycanthrope").
	var result: Array[String] = []
	for id in _monsters:
		var subs: Array = _monsters[id].get("sub_types", [])
		if sub_type in subs:
			result.append(id)
	result.sort()
	return result


# --- Convenience accessors ---

func get_hit_dice(monster_id: String) -> Dictionary:
	## Returns the hit_dice object for a monster.
	var monster := get_monster(monster_id)
	return monster.get("hit_dice", {})


func get_xp_value(monster_id: String) -> int:
	## Returns the XP value for defeating this monster.
	var monster := get_monster(monster_id)
	return int(monster.get("xp", 0))


func get_armor_class(monster_id: String) -> int:
	## Returns the armor class for a monster.
	var monster := get_monster(monster_id)
	return int(monster.get("armor_class", 0))


func get_morale(monster_id: String) -> int:
	## Returns the base morale modifier for a monster.
	var monster := get_monster(monster_id)
	return int(monster.get("morale", 0))
