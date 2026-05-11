extends Control

## SheetSectionStrip — horizontal sub-tab row inside the Character tab.
## Filters which sections are visible per the active entity type per
## gdd-character-tab.md §2.1.
##
## Section ids (one per existing cs_tab_* / cs_creature_* / vehicle script):
##   biography, attributes, combat, equipment, retainers, proficiencies,
##   spells, advancement, effects, creature_stats, creature_inventory,
##   vehicle_detail
##
## Click → emits section_selected(section_id). The Character tab page swaps
## the corresponding cs_tab_* instance into its content holder.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal section_selected(section_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SECTION_BIOGRAPHY := "biography"
const SECTION_ATTRIBUTES := "attributes"
const SECTION_COMBAT := "combat"
const SECTION_EQUIPMENT := "equipment"
const SECTION_RETAINERS := "retainers"
const SECTION_PROFICIENCIES := "proficiencies"
const SECTION_SPELLS := "spells"
const SECTION_ADVANCEMENT := "advancement"
const SECTION_EFFECTS := "effects"
const SECTION_CREATURE_STATS := "creature_stats"
const SECTION_CREATURE_INVENTORY := "creature_inventory"
const SECTION_VEHICLE_DETAIL := "vehicle_detail"
## Domain Phase 3: Ongoing-frequency activity status per gdd-character-tab.md §3.8.
const SECTION_ACTIVE_PROJECTS := "active_projects"

const SECTION_LABELS := {
	SECTION_BIOGRAPHY:          "Biography",
	SECTION_ATTRIBUTES:         "Attributes",
	SECTION_COMBAT:             "Combat",
	SECTION_EQUIPMENT:          "Equipment",
	SECTION_RETAINERS:          "Retainers",
	SECTION_PROFICIENCIES:      "Proficiencies",
	SECTION_SPELLS:             "Spells",
	SECTION_ADVANCEMENT:        "Advancement",
	SECTION_EFFECTS:            "Effects",
	SECTION_ACTIVE_PROJECTS:    "Active Projects",
	SECTION_CREATURE_STATS:     "Creature Stats",
	SECTION_CREATURE_INVENTORY: "Creature Inventory",
	SECTION_VEHICLE_DETAIL:     "Vehicle Detail",
}

## Sections per entity type, in display order. Aligned with
## gdd-character-tab.md §2.1; γ.1 keeps the existing 9 character tab scripts
## one-to-one (Biography / Attributes / Combat / Equipment / Proficiencies /
## Spells / Retainers / Advancement / Effects) instead of GDD §3.2's
## consolidated "Status" page — that restructuring is a follow-up session.
const SECTIONS_BY_TYPE := {
	"pcs": [
		SECTION_BIOGRAPHY, SECTION_ATTRIBUTES, SECTION_COMBAT,
		SECTION_EQUIPMENT, SECTION_PROFICIENCIES, SECTION_SPELLS,
		SECTION_RETAINERS, SECTION_ADVANCEMENT, SECTION_EFFECTS,
		SECTION_ACTIVE_PROJECTS,
	],
	"henchmen": [
		SECTION_BIOGRAPHY, SECTION_ATTRIBUTES, SECTION_COMBAT,
		SECTION_EQUIPMENT, SECTION_PROFICIENCIES, SECTION_SPELLS,
		SECTION_RETAINERS, SECTION_ADVANCEMENT, SECTION_EFFECTS,
		SECTION_ACTIVE_PROJECTS,
	],
	"merc_officers": [
		SECTION_BIOGRAPHY, SECTION_ATTRIBUTES, SECTION_COMBAT,
		SECTION_EQUIPMENT, SECTION_PROFICIENCIES, SECTION_SPELLS,
		SECTION_ADVANCEMENT, SECTION_EFFECTS,
	],
	"animals": [
		SECTION_CREATURE_STATS, SECTION_CREATURE_INVENTORY,
	],
	"vehicles": [
		SECTION_VEHICLE_DETAIL,
	],
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _hbox: HBoxContainer = null
var _buttons: Dictionary = {}  # section_id -> Button
var _active_section: String = ""


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _hbox != null:
		return
	custom_minimum_size = Vector2(0, 32)
	_hbox = HBoxContainer.new()
	_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hbox.add_theme_constant_override("separation", 2)
	add_child(_hbox)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Rebuild the section row for [param entity_type]. If [param preferred_section]
## is in the visible set, it stays active; otherwise the first section becomes
## active and section_selected is emitted.
func set_entity_type(entity_type: String, preferred_section: String = "") -> void:
	_ensure_built()
	_clear_buttons()
	var sections: Array = SECTIONS_BY_TYPE.get(entity_type, [])
	for sid in sections:
		_add_button(sid)
	var target: String = ""
	if sections.has(preferred_section):
		target = preferred_section
	elif not sections.is_empty():
		target = sections[0]
	if target.is_empty():
		_active_section = ""
		return
	_active_section = target
	_apply_active_highlight()
	section_selected.emit(target)


## Programmatically set the active section without re-emitting.
func set_active_section(section_id: String) -> void:
	_ensure_built()
	if section_id == _active_section:
		return
	if not _buttons.has(section_id):
		return
	_active_section = section_id
	_apply_active_highlight()


func active_section() -> String:
	return _active_section


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _clear_buttons() -> void:
	for sid in _buttons.keys():
		var btn: Button = _buttons[sid]
		if is_instance_valid(btn):
			btn.queue_free()
	_buttons.clear()


func _add_button(section_id: String) -> void:
	var btn := Button.new()
	btn.text = SECTION_LABELS.get(section_id, section_id.capitalize())
	btn.toggle_mode = true
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_on_button_pressed.bind(section_id))
	_hbox.add_child(btn)
	_buttons[section_id] = btn


func _apply_active_highlight() -> void:
	for sid in _buttons.keys():
		var btn: Button = _buttons[sid]
		if is_instance_valid(btn):
			btn.button_pressed = (sid == _active_section)


func _on_button_pressed(section_id: String) -> void:
	# Toggle off attempts re-press the same button. Force it back on so the
	# active section always has a visual highlight.
	if section_id == _active_section:
		_apply_active_highlight()
		return
	_active_section = section_id
	_apply_active_highlight()
	section_selected.emit(section_id)
