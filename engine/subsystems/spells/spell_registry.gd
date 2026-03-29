class_name SpellRegistry
extends RefCounted

## Loads spell definitions from data/spells/spell_catalog.json and
## data/spells/spell_list_indices.json.
## Provides spell lookup and class-aware availability queries.

const CATALOG_PATH := "res://data/spells/spell_catalog.json"
const INDICES_PATH := "res://data/spells/spell_list_indices.json"

var _spells: Dictionary = {}      # spell_key -> Dictionary
var _list_indices: Dictionary = {}  # "arcane" -> { "1": [...], ... }


func _init() -> void:
	_load_catalog()
	_load_indices()


func _load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("SpellRegistry: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SpellRegistry: JSON parse error in catalog: %s" % json.get_error_message())
		return
	var entries: Array = json.data
	for entry in entries:
		var key: String = entry.get("spell_key", "")
		if key.is_empty():
			push_error("SpellRegistry: Entry missing spell_key: %s" % str(entry))
			continue
		_spells[key] = entry
	print("SpellRegistry: Loaded %d spell definitions" % _spells.size())


func _load_indices() -> void:
	var file := FileAccess.open(INDICES_PATH, FileAccess.READ)
	if file == null:
		push_error("SpellRegistry: Cannot open %s" % INDICES_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SpellRegistry: JSON parse error in indices: %s" % json.get_error_message())
		return
	_list_indices = json.data
	print("SpellRegistry: Loaded spell list indices")


# ---------------------------------------------------------------------------
# Spell lookup
# ---------------------------------------------------------------------------

func get_spell(spell_key: String) -> Dictionary:
	if not _spells.has(spell_key):
		push_error("SpellRegistry.get_spell: unknown spell_key '%s'" % spell_key)
		return {}
	return _spells[spell_key]


func has_spell(spell_key: String) -> bool:
	return _spells.has(spell_key)


func get_spell_count() -> int:
	return _spells.size()


func get_all_spell_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _spells.keys():
		keys.append(k)
	keys.sort()
	return keys


func is_reversible(spell_key: String) -> bool:
	return _spells.get(spell_key, {}).get("is_reversible", false)


func get_reverse_key(spell_key: String) -> String:
	return _spells.get(spell_key, {}).get("reverse_key", "")


# ---------------------------------------------------------------------------
# Indexed list access
# ---------------------------------------------------------------------------

func get_spells_for_list(list_id: String, level: int) -> Array[String]:
	## list_id: "arcane", "divine_cleric", "divine_bladedancer"
	## Returns the ordered array of spell_keys for that list and level.
	if not _list_indices.has(list_id):
		push_error("SpellRegistry.get_spells_for_list: unknown list_id '%s'" % list_id)
		return []
	var level_map: Dictionary = _list_indices[list_id]
	var key := str(level)
	if not level_map.has(key):
		return []
	var result: Array[String] = []
	for s in level_map[key]:
		result.append(s)
	return result


func get_arcane_index_spell(level: int, index: int) -> String:
	## Returns spell_key at 1-based index on the arcane list for the given level.
	## Used for d12 starting repertoire rolls. index must be 1..12.
	var list := get_spells_for_list("arcane", level)
	if list.is_empty():
		push_error("SpellRegistry.get_arcane_index_spell: no arcane list for level %d" % level)
		return ""
	var i := index - 1  # convert 1-based to 0-based
	if i < 0 or i >= list.size():
		push_error("SpellRegistry.get_arcane_index_spell: index %d out of range for level %d" % [index, level])
		return ""
	return list[i]


# ---------------------------------------------------------------------------
# Class-aware queries
# ---------------------------------------------------------------------------

func get_class_tradition(class_id: String, class_registry: ClassRegistry) -> String:
	## Returns "arcane", "divine", or "" by reading the class's casting power.
	var power := class_registry.get_casting_power(class_id)
	return power.get("tradition", "")


func get_class_spell_list_id(class_id: String, class_registry: ClassRegistry) -> String:
	## Returns "arcane", "divine_cleric", "divine_bladedancer", or "".
	var power := class_registry.get_casting_power(class_id)
	return power.get("spell_list", "")


func get_available_spells_for_class(class_id: String, spell_level: int, class_registry: ClassRegistry) -> Array[String]:
	## All spell_keys available to a class at a given spell level.
	## Base list spells + class-restricted bonus spells (for divine classes).
	var list_id := get_class_spell_list_id(class_id, class_registry)
	if list_id.is_empty():
		return []

	# Start from the indexed list
	var result: Array[String] = get_spells_for_list(list_id, spell_level)

	# For divine classes, add any catalog spells restricted to this class_id
	var tradition := get_class_tradition(class_id, class_registry)
	if tradition == "divine":
		for spell_key in _spells.keys():
			var entry: Dictionary = _spells[spell_key]
			for classification in entry.get("classifications", []):
				if classification.get("tradition", "") != "divine":
					continue
				if classification.get("level", 0) != spell_level:
					continue
				var restricted_to: Array = classification.get("restricted_to", [])
				if restricted_to.is_empty():
					continue
				if class_id in restricted_to and spell_key not in result:
					result.append(spell_key)

	return result
