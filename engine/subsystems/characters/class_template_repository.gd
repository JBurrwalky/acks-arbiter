class_name ClassTemplateRepository
extends RefCounted

## Loads the imported class-template catalog (data/templates/class_templates.json,
## produced from rules/pc_class_templates.md by tools/import_class_templates.py)
## into typed [ClassTemplate] resources. Consumed by PC creation (Path B template
## choice) and the NPC builder (gdd-class-templates.md §4, §7).
##
## NOT an autoload — instantiate as needed and cache the instance, mirroring
## EquipmentCatalog / MagicItemCatalog / MonsterRegistry. class_name is permitted
## because this is a plain RefCounted service, not an autoload (the CLAUDE.md
## "no class_name in autoloads" constraint applies only to autoload scripts).

const TEMPLATES_PATH := "res://data/templates/class_templates.json"

var _by_id: Dictionary = {}        ## template_id -> ClassTemplate
var _by_class: Dictionary = {}     ## class_id -> Array[ClassTemplate] (band-ascending)
var _class_meta: Dictionary = {}   ## class_id -> {type_of_equivalences, notes}
var _loaded: bool = false
var _load_error: String = ""


func _init() -> void:
	_load()


func is_loaded() -> bool:
	return _loaded


func get_load_error() -> String:
	return _load_error


## A single template by id (e.g. "fighter_15_16"), or null if unknown.
func get_template(template_id: String) -> ClassTemplate:
	return _by_id.get(template_id, null)


## All 8 templates for a class, ascending by 3d6 band. Empty if the class is
## unknown (e.g. the four out-of-scope classes the importer skips).
func get_templates_for_class(class_id: String) -> Array[ClassTemplate]:
	var out: Array[ClassTemplate] = []
	out.assign(_by_class.get(class_id, []))
	return out


## Path B eligibility query (gdd §4.1): every template of [param class_id] whose
## band low bound is <= [param roll]. fighter@3 -> 1 template; fighter@14 -> 6;
## fighter@18 -> 8.
func get_templates_for_class_at_or_below_roll(
		class_id: String, roll: int) -> Array[ClassTemplate]:
	var out: Array[ClassTemplate] = []
	for t in _by_class.get(class_id, []):
		if t.eligible_at_roll(roll):
			out.append(t)
	return out


## NPC template selection (gdd §7.2): the single template of [param class_id]
## whose band CONTAINS [param roll] (low <= roll <= high), or null. This is the
## "roll on the table, use whatever band it lands on" query — distinct from the
## Path B at-or-below query used for PC creation.
func get_template_for_class_at_roll(class_id: String, roll: int) -> ClassTemplate:
	for t in _by_class.get(class_id, []):
		if t.roll_band_low <= roll and roll <= t.roll_band_high:
			return t
	return null


## Sorted list of class_ids that have templates.
func get_class_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_by_class.keys())
	ids.sort()
	return ids


func template_count() -> int:
	return _by_id.size()


## Class-level footnote metadata: {type_of_equivalences: [...], notes: "..."}.
func get_class_meta(class_id: String) -> Dictionary:
	return _class_meta.get(class_id, {})


func _load() -> void:
	var f := FileAccess.open(TEMPLATES_PATH, FileAccess.READ)
	if f == null:
		_load_error = "ClassTemplateRepository: cannot open %s" % TEMPLATES_PATH
		push_error(_load_error)
		return
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		_load_error = "ClassTemplateRepository: JSON parse error in %s: %s" % [
			TEMPLATES_PATH, json.get_error_message()]
		push_error(_load_error)
		return

	var data: Dictionary = json.data
	_class_meta = data.get("class_meta", {})
	for raw in data.get("templates", []):
		if not (raw is Dictionary):
			continue
		var t := ClassTemplate.from_dict(raw)
		_by_id[t.template_id] = t
		if not _by_class.has(t.class_id):
			_by_class[t.class_id] = []
		_by_class[t.class_id].append(t)

	# Guarantee band-ascending order per class regardless of source ordering.
	for class_id in _by_class:
		(_by_class[class_id] as Array).sort_custom(
			func(a: ClassTemplate, b: ClassTemplate) -> bool:
				return a.roll_band_low < b.roll_band_low)

	_loaded = true
