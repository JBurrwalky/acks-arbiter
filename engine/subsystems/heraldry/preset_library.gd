class_name PresetLibrary
extends RefCounted

## Loads starter heraldry presets from data/heraldry/presets.json.
## Used by the editor's "Reset to preset" dropdown and by the session-load
## backfill that auto-assigns a shield to parties that predate the migration.

const CATALOG_PATH := "res://data/heraldry/presets.json"

var _presets: Dictionary = {}     # preset_id -> entry Dictionary
var _order: Array[String] = []    # iteration order


func _init() -> void:
	_load()


func _load() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("PresetLibrary: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("PresetLibrary: JSON parse error: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	for entry_var in data.get("presets", []):
		var entry: Dictionary = entry_var
		var key: String = entry.get("preset_id", "")
		if key.is_empty():
			push_error("PresetLibrary: entry missing preset_id")
			continue
		if not entry.has("descriptor") or not (entry["descriptor"] is Dictionary):
			push_error("PresetLibrary: preset %s missing descriptor dict" % key)
			continue
		_presets[key] = entry
		_order.append(key)
	print("PresetLibrary: Loaded %d presets" % _presets.size())


func get_preset(preset_id: String) -> Dictionary:
	return _presets.get(preset_id, {})


func has_preset(preset_id: String) -> bool:
	return _presets.has(preset_id)


func get_all_preset_ids() -> Array[String]:
	return _order.duplicate()


func get_all_presets() -> Array:
	var out: Array = []
	for id in _order:
		out.append(_presets[id])
	return out


func preset_count() -> int:
	return _presets.size()


## Returns a random preset's raw entry, or empty dict if no presets loaded.
func get_random_preset() -> Dictionary:
	if _order.is_empty():
		return {}
	return _presets[_order[randi() % _order.size()]]


## Convenience: builds a HeraldryDescriptor from a random preset.
## heraldry_id is left empty — the caller assigns one before saving.
func get_random_preset_descriptor() -> HeraldryDescriptor:
	var preset := get_random_preset()
	if preset.is_empty():
		return HeraldryDescriptor.new()
	return HeraldryDescriptor.from_dict(preset.get("descriptor", {}))


## Convenience: builds a HeraldryDescriptor from a specific preset.
## heraldry_id is left empty — the caller assigns one before saving.
func get_preset_descriptor(preset_id: String) -> HeraldryDescriptor:
	var preset := get_preset(preset_id)
	if preset.is_empty():
		return HeraldryDescriptor.new()
	return HeraldryDescriptor.from_dict(preset.get("descriptor", {}))
