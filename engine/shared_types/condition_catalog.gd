class_name ConditionCatalog
extends RefCounted

## Loads and provides access to the condition catalog.
##
## Conditions are enumerated mechanical states extracted from ax_conditions_catalog.xml.
## Each condition has structured data for prevents_attacking, prevents_casting,
## prevents_movement, ac_modifier, attack_modifier, is_helpless, is_vulnerable, etc.
##
## Usage: var catalog := ConditionCatalog.new()
##        var data := catalog.get_condition("paralyzed")

const _CATALOG_PATH := "res://data/conditions/condition_catalog.json"

var _conditions: Dictionary = {}  # condition_key -> Dictionary


func _init() -> void:
	_load()


func _load() -> void:
	var file := FileAccess.open(_CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("ConditionCatalog: could not open %s" % _CATALOG_PATH)
		return
	var json_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Array:
		push_error("ConditionCatalog: failed to parse catalog JSON")
		return
	for entry in parsed:
		if entry is Dictionary and entry.has("condition_key"):
			_conditions[entry["condition_key"]] = entry


func get_condition(condition_key: String) -> Dictionary:
	## Returns the full data dictionary for a condition, or {} if not found.
	return _conditions.get(condition_key, {})


func has_condition(condition_key: String) -> bool:
	return _conditions.has(condition_key)


func get_all_condition_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _conditions.keys():
		keys.append(k)
	return keys


func prevents_action(condition_key: String, action: String) -> bool:
	## Returns true if the condition prevents the given action.
	## Valid actions: "attacking", "casting", "movement", "speech", "running", "charging"
	var c := get_condition(condition_key)
	if c.is_empty():
		return false
	match action:
		"attacking":
			return c.get("prevents_attacking", false)
		"casting":
			return c.get("prevents_casting", false)
		"movement":
			return c.get("prevents_movement", false)
		"speech":
			return c.get("prevents_speech", false)
		"running":
			return c.get("prevents_running", false)
		"charging":
			return c.get("prevents_charging", false)
	return false


func get_ac_modifier(condition_key: String) -> int:
	return get_condition(condition_key).get("ac_modifier", 0)


func get_attack_modifier(condition_key: String) -> int:
	return get_condition(condition_key).get("attack_modifier", 0)


func is_helpless(condition_key: String) -> bool:
	return get_condition(condition_key).get("is_helpless", false)


func is_vulnerable(condition_key: String) -> bool:
	return get_condition(condition_key).get("is_vulnerable", false)


func grants_auto_hit_melee(condition_key: String) -> bool:
	return get_condition(condition_key).get("grants_auto_hit_melee", false)


func grants_immunity_to_fear(condition_key: String) -> bool:
	## True if this condition makes its host immune to fear-tagged saves
	## (berserk_rage, berserkergang_rage, barbarian_savagery). Spells that
	## apply the `frightened` condition or fire an `is_fear_save: true` save
	## auto-succeed against creatures with any active fear-immunity condition.
	return get_condition(condition_key).get("immune_to_fear", false)


func get_attacker_bonus_vs(condition_key: String, attack_type: String = "ranged") -> int:
	## Returns the to-hit bonus attackers receive against this condition.
	## attack_type: "melee" or "ranged" (default).
	var c := get_condition(condition_key)
	if c.is_empty():
		return 0
	if attack_type == "melee":
		return c.get("attacker_bonus_vs_this_melee", 0)
	return c.get("attacker_bonus_vs_this", 0)
