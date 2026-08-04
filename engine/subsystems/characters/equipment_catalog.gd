class_name EquipmentCatalog
extends RefCounted

## EquipmentCatalog — loads equipment JSON files and provides query/filter methods.
## Used by the equipment shop panel during character creation.
## NOT an autoload — instantiate as needed: var catalog := EquipmentCatalog.new()
##
## Sources loaded:
##   base_equipment.json  — weapons, armor, shields, ammo, gear, clothing (~130 items)
##   transport.json       — mounts, draft animals, vehicles, tack, barding, livestock (35 items)
##   provisions_services.json — foodstuffs only (provisions array, item_category == "foodstuff")
##
## Excluded: poisons.json, siege_weapons.json, maritime.json

const BASE_PATH := "res://data/equipment/base_equipment.json"
const TRANSPORT_PATH := "res://data/equipment/transport.json"
const PROVISIONS_PATH := "res://data/equipment/provisions_services.json"

var _items: Dictionary = {}           # item_key -> Dictionary
var _by_category: Dictionary = {}     # category_string -> Array[String] of item_keys
var _load_errors: Array[String] = []  # any errors encountered during load


func _init() -> void:
	_load_base_equipment()
	_load_transport()
	_load_provisions()


# ---------------------------------------------------------------------------
# Public query methods
# ---------------------------------------------------------------------------

func get_item(item_key: String) -> Dictionary:
	return _items.get(item_key, {})


func has_item(item_key: String) -> bool:
	return _items.has(item_key)


func is_container(item_key: String) -> bool:
	return int(get_item(item_key).get("container_capacity_units", 0)) > 0


func get_container_capacity_units(item_key: String) -> int:
	return int(get_item(item_key).get("container_capacity_units", 0))


func get_items_by_category(category: String) -> Array[Dictionary]:
	var keys: Array = _by_category.get(category, [])
	var result: Array[Dictionary] = []
	for k in keys:
		result.append(_items[k])
	return result


func get_all_categories() -> Array[String]:
	var cats: Array[String] = []
	for k in _by_category.keys():
		cats.append(k as String)
	cats.sort()
	return cats


func get_item_count() -> int:
	return _items.size()


func get_all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _items.values():
		result.append(item)
	return result


func search_items(query: String) -> Array[Dictionary]:
	## Case-insensitive name substring match.
	var q := query.to_lower()
	var result: Array[Dictionary] = []
	for item in _items.values():
		if (item.get("name", "") as String).to_lower().contains(q):
			result.append(item)
	return result


func get_load_errors() -> Array[String]:
	return _load_errors.duplicate()


# ---------------------------------------------------------------------------
# Static cost formatting
# ---------------------------------------------------------------------------
#
# `EquipmentCatalog.format_cost` was DELETED on 2026-07-31. It was a second,
# divergent money formatter — identical to `Currency.format_cost` except that it
# joined denominations with a space ("15gp 5sp") where Currency uses a comma
# ("15gp, 5sp"). Two formatters means two display conventions, two places to
# change, and an ambiguous `git grep format_cost` for anyone auditing the display
# boundary. Conventions §127: `Currency.format_cost(value_cp)` is the ONLY money
# formatter. Call it directly at the display site.


# ---------------------------------------------------------------------------
# Private loading methods
# ---------------------------------------------------------------------------

func _load_base_equipment() -> void:
	var file := FileAccess.open(BASE_PATH, FileAccess.READ)
	if file == null:
		_load_errors.append("EquipmentCatalog: cannot open %s" % BASE_PATH)
		push_error("EquipmentCatalog: cannot open %s" % BASE_PATH)
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_load_errors.append("EquipmentCatalog: JSON parse error in %s: %s" % [BASE_PATH, json.get_error_message()])
		push_error("EquipmentCatalog: JSON parse error in %s" % BASE_PATH)
		return

	var data: Dictionary = json.data
	var items: Array = data.get("equipment", [])
	for item in items:
		_register_item(item)


func _load_transport() -> void:
	var file := FileAccess.open(TRANSPORT_PATH, FileAccess.READ)
	if file == null:
		_load_errors.append("EquipmentCatalog: cannot open %s" % TRANSPORT_PATH)
		push_error("EquipmentCatalog: cannot open %s" % TRANSPORT_PATH)
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_load_errors.append("EquipmentCatalog: JSON parse error in %s" % TRANSPORT_PATH)
		push_error("EquipmentCatalog: JSON parse error in %s" % TRANSPORT_PATH)
		return

	var data: Dictionary = json.data
	var items: Array = data.get("transport", [])
	for item in items:
		_register_item(item)


func _load_provisions() -> void:
	## Loads only the "provisions" array (foodstuffs). Skips lodging and hireling wages.
	var file := FileAccess.open(PROVISIONS_PATH, FileAccess.READ)
	if file == null:
		_load_errors.append("EquipmentCatalog: cannot open %s" % PROVISIONS_PATH)
		push_error("EquipmentCatalog: cannot open %s" % PROVISIONS_PATH)
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_load_errors.append("EquipmentCatalog: JSON parse error in %s" % PROVISIONS_PATH)
		push_error("EquipmentCatalog: JSON parse error in %s" % PROVISIONS_PATH)
		return

	var data: Dictionary = json.data
	var provisions: Array = data.get("provisions", [])
	for item in provisions:
		# Only load foodstuffs — skip any non-foodstuff entries
		if item.get("item_category", "") == "foodstuff":
			# Foodstuffs don't have encumbrance/is_heavy fields — add defaults
			var normalized: Dictionary = item.duplicate()
			if not normalized.has("encumbrance_units"):
				normalized["encumbrance_units"] = 167  # nominal: foodstuffs weigh ~1/6 stone each
			if not normalized.has("is_heavy"):
				normalized["is_heavy"] = false
			_register_item(normalized)


func _register_item(item: Dictionary) -> void:
	var key: String = item.get("item_key", "")
	if key.is_empty():
		_load_errors.append("EquipmentCatalog: item missing item_key, skipping")
		return
	_items[key] = item
	var cat: String = item.get("item_category", "gear")
	if not _by_category.has(cat):
		_by_category[cat] = []
	_by_category[cat].append(key)
