class_name SpellEffectRegistry
extends RefCounted

## Loads and provides access to spell effect hook data from data/spells/spell_effects.json.
##
## Separate from SpellRegistry (which holds catalog metadata: name, level, range, summary).
## This registry holds the mechanical hook data: modifiers, flags, conditions, damage, healing.
##
## Usage:
##   var reg := SpellEffectRegistry.new()
##   var data := reg.get_effect_data("protection_from_evil")
##   var mods := reg.get_modifiers_for_spell("protection_from_evil")

const _EFFECTS_PATH := "res://data/spells/spell_effects.json"

var _effects: Dictionary = {}  # spell_key -> Dictionary


func _init() -> void:
	_load()


func _load() -> void:
	var file := FileAccess.open(_EFFECTS_PATH, FileAccess.READ)
	if file == null:
		push_error("SpellEffectRegistry: could not open %s" % _EFFECTS_PATH)
		return
	var json_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		push_error("SpellEffectRegistry: failed to parse spell_effects.json")
		return
	for key in parsed.keys():
		if key.begins_with("_"):
			continue  # skip _comment and other metadata keys
		_effects[key] = parsed[key]


func get_effect_data(spell_key: String) -> Dictionary:
	## Returns the full effect data Dictionary for spell_key, or {} if not found.
	return _effects.get(spell_key, {})


func has_effect_data(spell_key: String) -> bool:
	return _effects.has(spell_key)


func get_all_spell_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _effects.keys():
		keys.append(k)
	return keys


func get_modifiers_for_spell(spell_key: String) -> Array[Dictionary]:
	## Returns the modifiers array for spell_key, typed as Array[Dictionary].
	var data := get_effect_data(spell_key)
	if data.is_empty():
		return []
	var raw: Array = data.get("modifiers", [])
	var result: Array[Dictionary] = []
	for m in raw:
		if m is Dictionary:
			result.append(m)
	return result


func get_flags_for_spell(spell_key: String) -> Array[String]:
	## Returns the flags array for spell_key.
	var data := get_effect_data(spell_key)
	if data.is_empty():
		return []
	var raw: Array = data.get("flags", [])
	var result: Array[String] = []
	for f in raw:
		if f is String:
			result.append(f)
	return result


func get_conditions_for_spell(spell_key: String) -> Array[String]:
	## Returns the conditions array for spell_key.
	var data := get_effect_data(spell_key)
	if data.is_empty():
		return []
	var raw: Array = data.get("conditions", [])
	var result: Array[String] = []
	for c in raw:
		if c is String:
			result.append(c)
	return result


func get_damage_resistances_for_spell(spell_key: String) -> Array[Dictionary]:
	## Returns the damage_resistances array for spell_key, or [].
	var data := get_effect_data(spell_key)
	if data.is_empty():
		return []
	var raw: Array = data.get("damage_resistances", [])
	var result: Array[Dictionary] = []
	for r in raw:
		if r is Dictionary:
			result.append(r)
	return result


func get_effect_type(spell_key: String) -> String:
	return get_effect_data(spell_key).get("effect_type", "")


func get_duration_type(spell_key: String) -> String:
	return get_effect_data(spell_key).get("duration_type", "")


func is_instant(spell_key: String) -> bool:
	return get_effect_type(spell_key) == "instant"


func requires_concentration(spell_key: String) -> bool:
	return get_effect_data(spell_key).get("requires_concentration", false)
