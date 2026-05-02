class_name FamiliarAcquisitionPanel
extends VBoxContainer

## Stage 3c — character-creation step that bonds a familiar.
##
## Composes Stage 3a's `FamiliarPicker` (form / cosmetic variant / name) above
## Stage 3b's `FamiliarProficiencyPicker` (the familiar's own proficiency
## selections). Auto-derives:
##   - `master_class_id` from `creation_state["class_id"]`
##   - `proficiency_budget` from sum of `selections_count` across the master's
##     `creation_state["proficiencies"]` array (master's actual slot uses).
##
## Surfaces only when the player picked the Familiar proficiency upstream.
## The orchestrator's `_next_valid_step` / `_prev_valid_step` skip this step
## when no `proficiency_key == "familiar"` entry exists in
## `creation_state["proficiencies"]`.
##
## State Dict — picks live under `creation_state["familiar"]`:
##   {
##     "form_key":              String,
##     "cosmetic_species":      String,
##     "name":                  String,
##     "proficiencies_chosen":  Array[Dictionary],
##   }
##
## `is_complete()` is true when both sub-pickers are complete.
##
## Persistence: `_finalize_character()` reads `creation_state["familiar"]` after
## the master row is written and calls `CampaignRepository.create_familiar(...)`
## with the master's id as the FK.


var _state: Dictionary = {}
var _familiar_state: Dictionary = {}
var _form_registry: FamiliarFormRegistry
var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry

# UI sub-panels
var _form_picker: FamiliarPicker
var _proficiency_picker: FamiliarProficiencyPicker
var _summary_label: Label


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(state: Dictionary,
		form_registry: FamiliarFormRegistry,
		class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	_state = state
	_form_registry = form_registry
	_class_registry = class_registry
	_proficiency_registry = proficiency_registry

	# Pull or initialize the familiar sub-state.
	if not _state.has("familiar") or not (_state["familiar"] is Dictionary):
		_state["familiar"] = {}
	_familiar_state = _state["familiar"]
	_familiar_state["form_key"] = String(_familiar_state.get("form_key", ""))
	_familiar_state["cosmetic_species"] = String(_familiar_state.get("cosmetic_species", ""))
	_familiar_state["name"] = String(_familiar_state.get("name", ""))
	if not _familiar_state.has("proficiencies_chosen") or not (_familiar_state["proficiencies_chosen"] is Array):
		_familiar_state["proficiencies_chosen"] = []

	# Compute the proficiency budget from the master's actual slot uses.
	# Each entry in master's proficiencies array carries selections_count; sum
	# them to get the total slots used. The familiar's budget matches.
	var master_class_id: String = String(_state.get("class_id", ""))
	var budget: int = _compute_master_proficiency_count(_state.get("proficiencies", []))

	# Sub-state Dict shape consumed by FamiliarProficiencyPicker.
	# It mutates `proficiencies_chosen` in-place — same Array we expose to the
	# finalize step via `_state["familiar"]["proficiencies_chosen"]`.
	var prof_picker_state := {
		"proficiency_budget": budget,
		"master_class_id": master_class_id,
		"proficiencies_chosen": _familiar_state["proficiencies_chosen"],
	}

	if get_child_count() == 0:
		_build_ui()

	_form_picker.setup(_familiar_state, _form_registry)
	_proficiency_picker.setup(prof_picker_state, _class_registry, _proficiency_registry)
	_render_summary(master_class_id, budget)


func is_complete() -> bool:
	if _form_picker == null or _proficiency_picker == null:
		return false
	return _form_picker.is_complete() and _proficiency_picker.is_complete()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 12)

	# Header summary (master class + budget readout).
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 14)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary_label)

	add_child(HSeparator.new())

	# Form picker — top section.
	_form_picker = FamiliarPicker.new()
	_form_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form_picker.size_flags_stretch_ratio = 0.55
	add_child(_form_picker)

	add_child(HSeparator.new())

	# Proficiency picker — bottom section.
	_proficiency_picker = FamiliarProficiencyPicker.new()
	_proficiency_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_proficiency_picker.size_flags_stretch_ratio = 0.45
	add_child(_proficiency_picker)


func _render_summary(master_class_id: String, budget: int) -> void:
	var class_name_lbl: String = master_class_id.capitalize() if not master_class_id.is_empty() else "?"
	var prof_word := "proficiencies" if budget != 1 else "proficiency"
	_summary_label.text = (
		"Bond a familiar — your magical animal companion. "
		+ "It takes the body of a real animal (its AC, movement, attacks, and special abilities) but its "
		+ "HD, HP, INT, save category, and proficiency count derive from you (see gdd-familiars.md §3.3). "
		+ "Pick %d %s for it from your %s class list and the general list — its picks are independent of yours."
	) % [budget, prof_word, class_name_lbl]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Sums `selections_count` across the master's proficiencies array. Each entry
## represents one slot use (rank-stacking entries advance their selections_count
## as the player picks the same proficiency multiple times).
static func compute_master_proficiency_count(proficiencies: Array) -> int:
	var total: int = 0
	for p in proficiencies:
		if p is Dictionary:
			total += int(p.get("selections_count", 1))
	return total


# Instance alias used by setup() for slightly cleaner readability.
func _compute_master_proficiency_count(proficiencies: Array) -> int:
	return FamiliarAcquisitionPanel.compute_master_proficiency_count(proficiencies)
