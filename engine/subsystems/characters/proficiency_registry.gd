class_name ProficiencyRegistry
extends RefCounted

## Loads proficiency definitions from data/proficiencies/proficiency_catalog.json
## and the general proficiency list from data/proficiencies/general_proficiency_list.json.
## Provides catalog lookup, rank/selection metadata, effect access, and level scaling.
## Does NOT contain game logic — only data access.
##
## Pass a SpecializationRegistry instance to enable registry-backed specialization lookups.

const CATALOG_PATH := "res://data/proficiencies/proficiency_catalog.json"
const GENERAL_LIST_PATH := "res://data/proficiencies/general_proficiency_list.json"

var _proficiencies: Dictionary = {}        # proficiency_key -> Dictionary
var _general_list: Array[String] = []      # ordered general proficiency keys
var _spec_registry: SpecializationRegistry  # may be null — only set when registry is wired in


func _init(spec_registry: SpecializationRegistry = null) -> void:
	_spec_registry = spec_registry
	_load_catalog()
	_load_general_list()


func _load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("ProficiencyRegistry: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ProficiencyRegistry: JSON parse error in %s: %s" % [CATALOG_PATH, json.get_error_message()])
		return
	var data: Dictionary = json.data
	for entry in data.get("proficiencies", []):
		var key: String = entry.get("proficiency_key", "")
		if key.is_empty():
			push_error("ProficiencyRegistry: Entry missing proficiency_key")
			continue
		_proficiencies[key] = entry
	print("ProficiencyRegistry: Loaded %d proficiency definitions" % _proficiencies.size())


func _load_general_list() -> void:
	var file := FileAccess.open(GENERAL_LIST_PATH, FileAccess.READ)
	if file == null:
		push_error("ProficiencyRegistry: Cannot open %s" % GENERAL_LIST_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ProficiencyRegistry: JSON parse error in %s: %s" % [GENERAL_LIST_PATH, json.get_error_message()])
		return
	for k in json.data:
		_general_list.append(k)
	print("ProficiencyRegistry: Loaded %d general proficiency keys" % _general_list.size())


# ---------------------------------------------------------------------------
# Compound key resolution
# ---------------------------------------------------------------------------
# Class JSON entries often use compound keys like "combat_trickery_disarm" or
# "fighting_style_missile" where the catalog stores "combat_trickery" / "fighting_style".
# Resolve by stripping the last underscore segment and checking if the prefix is a
# specialization proficiency (selection_rule == "specialization").

func resolve_key(key: String) -> String:
	## Returns the canonical catalog key for a potentially compound key.
	## Handles multi-segment specializations like "combat_trickery_force_back"
	## and "knowledge_political_history" by trying all prefix lengths.
	## Returns "" if the key cannot be resolved.
	if _proficiencies.has(key):
		return key
	# Try progressively shorter prefixes (longest first) to find a specialization base
	var parts := key.split("_")
	for i in range(parts.size() - 1, 0, -1):
		var base := "_".join(parts.slice(0, i))
		if _proficiencies.has(base):
			var entry: Dictionary = _proficiencies[base]
			if entry.get("selection_rule", "") == "specialization":
				return base
	return ""


# Keep private alias for internal callers that haven't been migrated yet.
func _resolve_key(key: String) -> String:
	return resolve_key(key)


func get_specialization_from_compound_key(compound_key: String) -> String:
	## Returns the specialization portion of a compound key, or "" if not compound.
	## Handles multi-segment specializations like "combat_trickery_force_back" -> "force_back".
	if _proficiencies.has(compound_key):
		return ""
	var parts := compound_key.split("_")
	for i in range(parts.size() - 1, 0, -1):
		var base := "_".join(parts.slice(0, i))
		if _proficiencies.has(base) and _proficiencies[base].get("selection_rule", "") == "specialization":
			return "_".join(parts.slice(i))
	return ""


# Keep private alias used by get_effects_for_specialization().
func _get_specialization_from_key(compound_key: String) -> String:
	return get_specialization_from_compound_key(compound_key)


# ---------------------------------------------------------------------------
# Core lookup
# ---------------------------------------------------------------------------

func get_proficiency(key: String) -> Dictionary:
	var resolved := _resolve_key(key)
	if resolved.is_empty():
		push_error("ProficiencyRegistry.get_proficiency: unknown key '%s'" % key)
		return {}
	return _proficiencies[resolved]


func has_proficiency(key: String) -> bool:
	return not _resolve_key(key).is_empty()


func get_all_proficiency_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _proficiencies.keys():
		keys.append(k)
	keys.sort()
	return keys


func get_proficiency_count() -> int:
	return _proficiencies.size()


func get_general_proficiency_list() -> Array[String]:
	return _general_list.duplicate()


func get_proficiencies_by_type(type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _proficiencies.values():
		if entry.get("type", "") == type:
			result.append(entry)
	return result


# ---------------------------------------------------------------------------
# Metadata queries
# ---------------------------------------------------------------------------

func get_max_rank(key: String) -> int:
	var entry := get_proficiency(key)
	return entry.get("max_rank", 1)


func get_max_selections(key: String) -> int:
	var entry := get_proficiency(key)
	return entry.get("max_selections", 1)


func get_selection_rule(key: String) -> String:
	var entry := get_proficiency(key)
	return entry.get("selection_rule", "unique")


func is_specialization(key: String) -> bool:
	return get_selection_rule(key) == "specialization"


func get_available_specializations(prof_key: String) -> Array:
	## Returns the list of available specialization IDs for a proficiency.
	##
	## - Closed-list proficiencies (inline Array in catalog): returns that array as-is.
	## - Registry-backed proficiencies ("registry" sentinel): queries SpecializationRegistry.
	## - Non-specialization proficiencies: returns empty array.
	## - Registry-backed but no SpecializationRegistry wired in: returns empty array.
	var resolved := resolve_key(prof_key)
	if resolved.is_empty():
		return []
	var entry: Dictionary = _proficiencies[resolved]
	if entry.get("selection_rule", "") != "specialization":
		return []
	var specs_raw = entry.get("specializations")
	if specs_raw is Array:
		# Closed-list (e.g., Combat Trickery, Fighting Style, Elementalism)
		return specs_raw
	if specs_raw == "registry" and _spec_registry != null:
		return _spec_registry.get_specialization_ids(resolved)
	return []


func get_specialization_display_name(prof_key: String, spec_id: String) -> String:
	## Returns a human-readable display name for a specialization.
	## Delegates to SpecializationRegistry when available; falls back to titlecasing the ID.
	var resolved := resolve_key(prof_key)
	if not resolved.is_empty() and _spec_registry != null:
		var name := _spec_registry.get_specialization_display_name(resolved, spec_id)
		if not name.is_empty():
			return name
	return spec_id.replace("_", " ").capitalize()


# ---------------------------------------------------------------------------
# Effects access
# ---------------------------------------------------------------------------

func get_effects_for_rank(key: String, rank: int) -> Dictionary:
	## For non-ranked proficiencies (max_rank == 1 or no effects_by_rank),
	## returns the top-level "effects" dict.
	## For ranked proficiencies, returns effects_by_rank[str(rank)].
	var entry := get_proficiency(key)
	if entry.is_empty():
		return {}
	if entry.has("effects_by_rank"):
		return entry["effects_by_rank"].get(str(rank), {})
	return entry.get("effects", {})


func get_effects_for_specialization(key: String, spec: String) -> Dictionary:
	## Returns the effects dict for a specialization proficiency given the specialization value.
	## Also handles compound keys like "fighting_style_missile".
	var resolved := _resolve_key(key)
	if resolved.is_empty():
		return {}
	var entry: Dictionary = _proficiencies[resolved]

	# Determine actual specialization: may come from compound key or explicit spec param
	var actual_spec := spec
	if actual_spec.is_empty():
		actual_spec = _get_specialization_from_key(key)
	if actual_spec.is_empty():
		return {}

	if entry.has("effects_by_specialization"):
		return entry["effects_by_specialization"].get(actual_spec, {})
	return {}


# ---------------------------------------------------------------------------
# Level scaling
# ---------------------------------------------------------------------------

func has_level_scaling(key: String) -> bool:
	var entry := get_proficiency(key)
	return entry.get("level_scaling") != null


func get_scaled_bonus(key: String, character_level: int) -> int:
	## Evaluates the level breakpoint table and returns the appropriate bonus.
	## Returns 0 if the proficiency has no level scaling.
	var entry := get_proficiency(key)
	if entry.is_empty():
		return 0
	var scaling: Variant = entry.get("level_scaling", null)
	if scaling == null:
		return 0
	var breakpoints: Array = scaling.get("breakpoints", [])
	if breakpoints.is_empty():
		return 0
	# Walk descending — last breakpoint where min_level <= character_level wins
	var best_bonus: int = 0
	for bp in breakpoints:
		if character_level >= bp.get("min_level", 0):
			best_bonus = bp.get("bonus", 0)
	return best_bonus
