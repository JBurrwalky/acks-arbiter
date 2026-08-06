class_name FamiliarFormRegistry
extends RefCounted

## Loads familiar form definitions from data/familiars/familiar_form_catalog.json.
##
## Two kinds of entries:
##   - **Canon forms** carry a `monster_id` reference into monster_catalog.json
##     (`bat` → `bat_ordinary`, `hawk` → `hawk_ordinary`). Their stat block is
##     resolved at lookup via the supplied MonsterRegistry.
##   - **Project-authored forms** carry an inline `stat_block` (cat, rat,
##     snake_small, toad, weasel). Their stat block lives in the form catalog.
##
## Familiars do NOT use the form's printed HD or save_as — those are derived
## from the master per gdd-familiars.md §3.3. The registry only surfaces what
## the form contributes mechanically: AC, movement, attack routines, and
## special abilities.
##
## Pattern matches MonsterRegistry / SpellRegistry / ClassRegistry / ProficiencyRegistry.

const CATALOG_PATH := "res://data/familiars/familiar_form_catalog.json"

var _forms: Dictionary = {}                    # form_key → entry Dictionary
var _form_keys_in_order: Array[String] = []    # preserves catalog order for UI listings
var _monster_registry: MonsterRegistry          # resolves canon `monster_id` refs


func _init(monster_registry: MonsterRegistry = null) -> void:
	# Optional injection — tests pass a stub or pre-built MonsterRegistry; runtime
	# callers either supply the shared one or let us instantiate.
	if monster_registry == null:
		_monster_registry = MonsterRegistry.new()
	else:
		_monster_registry = monster_registry
	_load_catalog()


func _load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("FamiliarFormRegistry: Cannot open %s" % CATALOG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("FamiliarFormRegistry: JSON parse error: %s" % json.get_error_message())
		return
	var entries: Array = json.data
	for entry in entries:
		var key: String = entry.get("form_key", "")
		if key.is_empty():
			push_error("FamiliarFormRegistry: Entry missing form_key: %s" % str(entry))
			continue
		_forms[key] = entry
		_form_keys_in_order.append(key)
	print("FamiliarFormRegistry: Loaded %d familiar forms" % _forms.size())


# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

func has_form(form_key: String) -> bool:
	return _forms.has(form_key)


func get_form(form_key: String) -> Dictionary:
	if not _forms.has(form_key):
		push_error("FamiliarFormRegistry: Unknown form '%s'" % form_key)
		return {}
	return _forms[form_key]


func get_all_form_keys() -> Array[String]:
	return _form_keys_in_order.duplicate()


func get_form_count() -> int:
	return _forms.size()


# ---------------------------------------------------------------------------
# Display metadata
# ---------------------------------------------------------------------------

func get_display_name(form_key: String) -> String:
	var entry := get_form(form_key)
	return str(entry.get("display_name", form_key.capitalize()))


func get_summary(form_key: String) -> String:
	var entry := get_form(form_key)
	return str(entry.get("summary", ""))


## Returns the cosmetic species variants the player may pick for this form.
## A variant is a pure narrative skin — mechanics are identical across them.
## Forms with a single variant return a one-element array (e.g. `["Bat"]`).
func get_cosmetic_variants(form_key: String) -> Array[String]:
	var entry := get_form(form_key)
	var raw: Array = entry.get("cosmetic_variants", [])
	var result: Array[String] = []
	for v in raw:
		result.append(String(v))
	return result


func is_project_authored(form_key: String) -> bool:
	var entry := get_form(form_key)
	return bool(entry.get("is_project_authored", false))


# ---------------------------------------------------------------------------
# Stat block resolution
# ---------------------------------------------------------------------------

## Returns the resolved stat block for a form. For canon forms, looks up the
## referenced `monster_id` in MonsterRegistry; for project-authored forms,
## returns the inline `stat_block` field. Caller treats the result as the
## authoritative source for AC, movement, attack_routines, and special_abilities.
func get_form_stats(form_key: String) -> Dictionary:
	var entry := get_form(form_key)
	if entry.is_empty():
		return {}
	# Project-authored: stat block inline.
	if entry.has("stat_block"):
		return entry["stat_block"]
	# Canon: resolve monster_id via MonsterRegistry.
	var monster_id: String = str(entry.get("monster_id", ""))
	if monster_id.is_empty():
		push_error("FamiliarFormRegistry: form '%s' has neither stat_block nor monster_id" % form_key)
		return {}
	if _monster_registry == null or not _monster_registry.has_monster(monster_id):
		push_error("FamiliarFormRegistry: form '%s' references unknown monster '%s'" % [form_key, monster_id])
		return {}
	# Reference into the process-shared monster catalog (static since
	# 2026-08-06) — callers must treat it (and its nested dicts/arrays) as
	# read-only; duplicate(true) before any write.
	return _monster_registry.get_monster(monster_id)


# ---------------------------------------------------------------------------
# Convenience: form-derived stats the picker UI surfaces
# ---------------------------------------------------------------------------

func get_armor_class(form_key: String) -> int:
	return int(get_form_stats(form_key).get("armor_class", 9))


func get_movement(form_key: String) -> Dictionary:
	var stats := get_form_stats(form_key)
	var mv = stats.get("movement", {})
	return mv if mv is Dictionary else {}


func get_attack_routines(form_key: String) -> Array:
	var stats := get_form_stats(form_key)
	var arr = stats.get("attack_routines", [])
	return arr if arr is Array else []


func get_special_abilities(form_key: String) -> Array:
	var stats := get_form_stats(form_key)
	var arr = stats.get("special_abilities", [])
	return arr if arr is Array else []
