class_name EntityFlags
extends RefCounted

## Boolean state container for a single entity.
##
## Flags are keyed by canonical string constants (see below).
## Multiple sources may set the same flag concurrently. The flag remains
## active until every source has cleared it — this correctly handles the
## case where two separate spells both grant Fly.
##
## Canonical flag keys:
##   Movement:   "can_fly", "can_levitate", "can_water_walk", "can_spider_climb",
##               "can_breathe_water", "is_hasted", "is_slowed"
##   Visibility: "is_invisible", "is_improved_invisible", "is_faerie_fired",
##               "has_spell_infravision"
##   Protection: "protected_from_normal_missiles", "protected_from_normal_weapons",
##               "has_death_ward", "has_anti_magic_shell", "is_nondetectable",
##               "protected_from_enchanted_melee"
##   Form:       "is_gaseous", "is_polymorphed", "is_petrified", "is_temporal_stasis"
##   Social:     "is_charmed", "is_commanded", "is_geased"

# _flags: flag_key -> Array of { source_id, metadata }
var _flags: Dictionary = {}


func set_flag(flag_key: String, source_id: String, metadata: Dictionary = {}) -> void:
	## Adds source_id as a holder of flag_key.
	## If the source already holds this flag, updates its metadata.
	if not _flags.has(flag_key):
		_flags[flag_key] = []
	# Check if source already present
	for entry in _flags[flag_key]:
		if entry["source_id"] == source_id:
			entry["metadata"] = metadata
			return
	_flags[flag_key].append({ "source_id": source_id, "metadata": metadata })


func clear_flag(flag_key: String, source_id: String) -> void:
	## Removes source_id from flag_key. If no sources remain, the flag is cleared.
	if not _flags.has(flag_key):
		return
	_flags[flag_key] = _flags[flag_key].filter(
		func(e): return e["source_id"] != source_id
	)
	if _flags[flag_key].is_empty():
		_flags.erase(flag_key)


func clear_all_from_source(source_id: String) -> void:
	## Removes source_id from every flag it holds.
	var flags_to_erase: Array[String] = []
	for flag_key in _flags.keys():
		_flags[flag_key] = _flags[flag_key].filter(
			func(e): return e["source_id"] != source_id
		)
		if _flags[flag_key].is_empty():
			flags_to_erase.append(flag_key)
	for k in flags_to_erase:
		_flags.erase(k)


func has_flag(flag_key: String) -> bool:
	return _flags.has(flag_key) and not _flags[flag_key].is_empty()


func get_flag_sources(flag_key: String) -> Array[String]:
	if not _flags.has(flag_key):
		return []
	var sources: Array[String] = []
	for entry in _flags[flag_key]:
		sources.append(entry["source_id"])
	return sources


func get_flag_metadata(flag_key: String) -> Dictionary:
	## Returns the metadata for the first (or only) source of flag_key.
	## For multi-source flags, callers should use get_flag_sources() if they need per-source data.
	if not _flags.has(flag_key) or _flags[flag_key].is_empty():
		return {}
	return _flags[flag_key][0].get("metadata", {})


func get_all_flags() -> Array[String]:
	var keys: Array[String] = []
	for k in _flags.keys():
		keys.append(k)
	return keys


func clear() -> void:
	_flags.clear()
