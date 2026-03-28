class_name PowerRegistry
extends RefCounted

## Loads the power catalog from data/powers/power_catalog.json.
## Provides metadata lookup by power_id.
## Does NOT contain game logic — only data access.

const CATALOG_PATH := "res://data/powers/power_catalog.json"

var _powers: Dictionary = {}  # power_id -> Dictionary


func _init() -> void:
	_load_catalog()


func _load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("PowerRegistry: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("PowerRegistry: JSON parse error in %s: %s" % [CATALOG_PATH, json.get_error_message()])
		return
	var data: Dictionary = json.data
	for power in data.get("powers", []):
		var pid: String = power.get("power_id", "")
		if pid.is_empty():
			push_error("PowerRegistry: Power entry missing power_id")
			continue
		_powers[pid] = power
	print("PowerRegistry: Loaded %d power definitions" % _powers.size())


func get_power(power_id: String) -> Dictionary:
	if not _powers.has(power_id):
		push_error("PowerRegistry.get_power: unknown power_id '%s'" % power_id)
		return {}
	return _powers[power_id]


func has_power(power_id: String) -> bool:
	return _powers.has(power_id)


func get_powers_by_type(power_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for power in _powers.values():
		if power.get("power_type", "") == power_type:
			result.append(power)
	return result


func get_all_power_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _powers.keys():
		ids.append(key)
	return ids


func get_power_count() -> int:
	return _powers.size()
