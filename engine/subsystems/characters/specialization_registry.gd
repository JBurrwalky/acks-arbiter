class_name SpecializationRegistry
extends RefCounted

## Registry for proficiency specialization options.
##
## Loads the base catalog from proficiency_specializations.json and provides
## lookup methods for all consumers (UI, generator, effect resolver).
##
## Three-layer architecture (GDD §2.2):
##   Layer 1: Base catalog — this file (always present)
##   Layer 2: Setting-generated — per-campaign, added at setting creation [FUTURE]
##   Layer 3: Campaign-created — added during play (crossbreeds, etc.) [FUTURE]
##
## At runtime the UI and generator read from this registry only. Campaign layers
## will be composed in via compose_with_campaign_layer() once those systems exist.

const CATALOG_PATH := "res://data/proficiencies/proficiency_specializations.json"

# proficiency_key -> Array[Dictionary]  (each dict has id, display_name, layer, prerequisite_ids, metadata)
var _specializations: Dictionary = {}


func _init() -> void:
	_load_catalog()


func _load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("SpecializationRegistry: cannot open '%s'" % CATALOG_PATH)
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("SpecializationRegistry: JSON parse failed for '%s'" % CATALOG_PATH)
		return
	for prof_key in parsed.keys():
		var entry = parsed[prof_key]
		if entry is Dictionary and entry.has("specializations") and entry["specializations"] is Array:
			_specializations[prof_key] = entry["specializations"]
	print("SpecializationRegistry: Loaded specializations for %d proficiencies" % _specializations.size())


# ---------------------------------------------------------------------------
# Query API
# ---------------------------------------------------------------------------

func has_specializations(proficiency_key: String) -> bool:
	## Returns true if the key exists in the registry with at least one entry.
	return _specializations.has(proficiency_key) and not _specializations[proficiency_key].is_empty()


func get_specializations(proficiency_key: String) -> Array:
	## Returns the full array of specialization dicts for the given proficiency.
	## Each dict has: id, display_name, layer, prerequisite_ids, metadata.
	## Returns empty array if not found.
	return _specializations.get(proficiency_key, [])


func get_specialization_ids(proficiency_key: String) -> Array:
	## Returns just the id strings for all specializations of the given proficiency.
	var result: Array = []
	for entry in _specializations.get(proficiency_key, []):
		result.append(entry.get("id", ""))
	return result


func get_specialization(proficiency_key: String, spec_id: String) -> Dictionary:
	## Returns the full specialization dict for the given proficiency + specialization ID.
	## Returns empty dict if not found.
	for entry in _specializations.get(proficiency_key, []):
		if entry.get("id", "") == spec_id:
			return entry
	return {}


func get_specialization_display_name(proficiency_key: String, spec_id: String) -> String:
	## Returns the display_name for the given specialization.
	## Returns "" if not found (caller should fall back to titlecasing the ID).
	var entry := get_specialization(proficiency_key, spec_id)
	return entry.get("display_name", "")


# ---------------------------------------------------------------------------
# Future extension stubs
# ---------------------------------------------------------------------------

# func compose_with_campaign_layer(campaign_specs: Array) -> void:
#   ## [FUTURE] Merge setting-generated and campaign-created specializations into
#   ## the runtime registry. Called by the session runner after loading a campaign.
#   ## Each entry in campaign_specs: { proficiency_key, id, display_name, layer, prerequisite_ids, metadata }
#   pass
