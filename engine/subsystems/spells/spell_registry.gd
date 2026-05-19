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

	# Generate synthetic entries for reversed spell forms so get_spell()
	# works with keys like "detect_good" (reverse of "detect_evil").
	var reverse_count := 0
	for base_key in _spells.keys().duplicate():
		var base: Dictionary = _spells[base_key]
		if not base.get("is_reversible", false):
			continue
		var rev_key: String = base.get("reverse_key", "")
		var rev_name: String = base.get("reverse_name", "")
		if rev_key.is_empty() or rev_name.is_empty():
			continue
		if _spells.has(rev_key):
			continue  # already a real entry
		var rev_entry := base.duplicate(true)
		rev_entry["spell_key"] = rev_key
		rev_entry["spell_name"] = rev_name
		rev_entry["is_reversed_form"] = true
		rev_entry["base_spell_key"] = base_key
		rev_entry["is_reversible"] = false
		rev_entry["reverse_key"] = ""
		rev_entry["reverse_name"] = ""
		_spells[rev_key] = rev_entry
		reverse_count += 1

	print("SpellRegistry: Loaded %d spell definitions (%d reversed forms)" % [_spells.size(), reverse_count])


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


func get_divine_spells_not_on_class_list(class_id: String, class_registry: ClassRegistry) -> Dictionary:
	## Returns {spell_level(int): Array[String]} — all non-reversed-form divine spell keys
	## NOT available to the given class, sorted by spell name within each level.
	## If the class has no divine spell list, returns ALL divine spells (non-reversed).

	# Collect reverse-form keys to exclude from picker (they're auto-added at save time).
	var reverse_keys: Dictionary = {}
	for spell_key in _spells.keys():
		var entry: Dictionary = _spells[spell_key]
		if entry.get("is_reversible", false):
			var rv: String = entry.get("reverse_key", "")
			if not rv.is_empty():
				reverse_keys[rv] = true

	# Build the set of spell keys available to this class across all levels.
	var available_keys: Dictionary = {}
	var list_id := get_class_spell_list_id(class_id, class_registry)
	if not list_id.is_empty():
		for level in range(1, 7):
			for k in get_available_spells_for_class(class_id, level, class_registry):
				available_keys[k as String] = true

	# Collect divine spells not on the class list, grouped by level.
	var result: Dictionary = {}
	for spell_key in _spells.keys():
		var key_str := spell_key as String
		if reverse_keys.has(key_str) or available_keys.has(key_str):
			continue
		var entry: Dictionary = _spells[key_str]
		for classification in entry.get("classifications", []):
			if classification.get("tradition", "") == "divine":
				var level := int(classification.get("level", 1))
				if not result.has(level):
					result[level] = []
				(result[level] as Array).append(key_str)
				break

	# Sort each level's spells by display name.
	for level in result.keys():
		var arr: Array = result[level]
		arr.sort_custom(func(a: String, b: String) -> bool:
			var na: String = (_spells.get(a, {}) as Dictionary).get("spell_name", a)
			var nb: String = (_spells.get(b, {}) as Dictionary).get("spell_name", b)
			return na < nb)

	return result


func get_available_spells_for_class(class_id: String, spell_level: int, class_registry: ClassRegistry) -> Array[String]:
	## All spell_keys available to a class at a given spell level.
	## Base list spells + class-restricted bonus spells (for divine classes).
	##
	## 2026-05-19 bucket-B item #117: walks ALL casting powers (plural) for
	## dual-tradition classes (e.g., Lightblessed Wonderworker has both
	## arcane_casting and divine_casting). Previously consumed only the first
	## casting power, causing dual-tradition classes to silently miss their
	## second spell list.
	var result: Array[String] = []
	var traditions_seen: Dictionary = {}
	var casting_powers: Array = class_registry.get_casting_powers(class_id)
	if casting_powers.is_empty():
		# Backwards-compat path: single-tradition classes fall through the
		# original list_id resolution if get_casting_powers returns empty.
		var list_id := get_class_spell_list_id(class_id, class_registry)
		if not list_id.is_empty():
			result = get_spells_for_list(list_id, spell_level)
	else:
		for power in casting_powers:
			var list_id_p: String = String(power.get("spell_list", ""))
			if list_id_p.is_empty():
				continue
			for key in get_spells_for_list(list_id_p, spell_level):
				if key not in result:
					result.append(key)
			var tradition: String = String(power.get("tradition", ""))
			if not tradition.is_empty():
				traditions_seen[tradition] = true

	# Add catalog spells restricted to this class_id, scoped to traditions
	# the class actually casts in. Dual-tradition classes pick up restricted_to
	# overlays for BOTH traditions; single-tradition classes only their own.
	for spell_key in _spells.keys():
		var entry: Dictionary = _spells[spell_key]
		for classification in entry.get("classifications", []):
			var c_tradition: String = String(classification.get("tradition", ""))
			if not traditions_seen.get(c_tradition, false):
				continue
			if classification.get("level", 0) != spell_level:
				continue
			var restricted_to: Array = classification.get("restricted_to", [])
			if restricted_to.is_empty():
				continue
			if class_id in restricted_to and spell_key not in result:
				result.append(spell_key)

	return result
