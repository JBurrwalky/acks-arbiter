class_name ChargeRegistry
extends RefCounted

## Loads charge definitions from data/heraldry/charges.json.
## Each entry contains charge_id, display_name, image_path, tags, source_attribution.

const CATALOG_PATH := "res://data/heraldry/charges.json"

var _charges: Dictionary = {}         # charge_id -> entry Dictionary
var _order: Array[String] = []        # iteration order (matches JSON file)
var _by_tag: Dictionary = {}          # tag -> Array[charge_id]
var _all_tags: Array[String] = []     # sorted unique tags


func _init() -> void:
	_load()


func _load() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("ChargeRegistry: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ChargeRegistry: JSON parse error: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	var tag_set: Dictionary = {}
	for entry_var in data.get("charges", []):
		var entry: Dictionary = entry_var
		var key: String = entry.get("charge_id", "")
		if key.is_empty():
			push_error("ChargeRegistry: entry missing charge_id")
			continue
		_charges[key] = entry
		_order.append(key)
		for tag_var in entry.get("tags", []):
			var tag: String = str(tag_var)
			if tag.is_empty():
				continue
			tag_set[tag] = true
			if not _by_tag.has(tag):
				_by_tag[tag] = []
			_by_tag[tag].append(key)
	_all_tags = []
	for t in tag_set.keys():
		_all_tags.append(t)
	_all_tags.sort()
	print("ChargeRegistry: Loaded %d charges, %d tags" % [_charges.size(), _all_tags.size()])


func get_charge(charge_id: String) -> Dictionary:
	return _charges.get(charge_id, {})


func has_charge(charge_id: String) -> bool:
	return _charges.has(charge_id)


func get_all_charges() -> Array:
	var out: Array = []
	for id in _order:
		out.append(_charges[id])
	return out


func get_all_charge_ids() -> Array[String]:
	return _order.duplicate()


func get_charges_by_tag(tag: String) -> Array:
	var ids: Array = _by_tag.get(tag, [])
	var out: Array = []
	for id in ids:
		out.append(_charges[id])
	return out


func get_all_tags() -> Array[String]:
	return _all_tags.duplicate()


func get_charge_count() -> int:
	return _charges.size()


func search_by_name(substring: String) -> Array:
	## Case-insensitive substring match on display_name. Used by the charge
	## picker's text-search box (v1 ships with empty tags so search is the
	## primary discovery affordance).
	var needle := substring.to_lower().strip_edges()
	if needle.is_empty():
		return get_all_charges()
	var out: Array = []
	for id in _order:
		var entry: Dictionary = _charges[id]
		var name: String = str(entry.get("display_name", "")).to_lower()
		if name.find(needle) != -1:
			out.append(entry)
	return out
