class_name ShieldShapeRegistry
extends RefCounted

## Loads shield-shape definitions from data/heraldry/shield_shapes.json.
## Each entry contains display_name, mask_path, outline_path.

const CATALOG_PATH := "res://data/heraldry/shield_shapes.json"

var _shapes: Dictionary = {}     # shape_id -> entry Dictionary
var _order: Array[String] = []   # iteration order (matches JSON file)


func _init() -> void:
	_load()


func _load() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("ShieldShapeRegistry: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ShieldShapeRegistry: JSON parse error: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	for entry_var in data.get("shapes", []):
		var entry: Dictionary = entry_var
		var key: String = entry.get("shape_id", "")
		if key.is_empty():
			push_error("ShieldShapeRegistry: entry missing shape_id")
			continue
		_shapes[key] = entry
		_order.append(key)
	print("ShieldShapeRegistry: Loaded %d shield shapes" % _shapes.size())


func get_shape(shape_id: String) -> Dictionary:
	return _shapes.get(shape_id, {})


func has_shape(shape_id: String) -> bool:
	return _shapes.has(shape_id)


func get_all_shape_ids() -> Array[String]:
	return _order.duplicate()


func get_all_shapes() -> Array:
	var out: Array = []
	for id in _order:
		out.append(_shapes[id])
	return out


func get_shape_count() -> int:
	return _shapes.size()
