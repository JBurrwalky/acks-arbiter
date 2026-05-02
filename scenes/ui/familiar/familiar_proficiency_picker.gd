class_name FamiliarProficiencyPicker
extends VBoxContainer

## Stage 3b — Familiar-specific proficiency picker.
##
## Per gdd-familiars.md §3.4.1, a familiar picks its own proficiencies:
##   - Same total count as the master's general + class slots (the budget).
##   - Drawn from the union of (a) the general proficiency list and (b) the
##     master's class proficiency list.
##   - Picks are INDEPENDENT of master's actual selections.
##   - Same per-proficiency stacking rules apply (max_rank, max_selections,
##     selection_rule from data/proficiencies/proficiency_catalog.json).
##
## Pure-code panel matching the project's character-creation panel idiom; no
## `.tscn` needed. Instantiate with `FamiliarProficiencyPicker.new()` and call
## `setup(state, class_registry, proficiency_registry)`.
##
## State Dictionary shape (mutated in-place):
##   {
##     "proficiency_budget":    int,             # slots available
##     "master_class_id":       String,          # for class proficiency list lookup
##     "proficiencies_chosen":  Array[Dictionary],  # picks (see below)
##   }
##
## Each entry in `proficiencies_chosen` is a Dictionary:
##   { "proficiency_key": String, "specialization": String }
##
## Stage 3b scope: each eligible proficiency can be picked at most once
## (rank 1). Specialization proficiencies (e.g. Knowledge, Craft, Profession,
## Fighting Style) ARE supported via an inline OptionButton on the picked-list
## row. Stacking proficiencies (e.g. Alchemy, Engineering — `selection_rule
## == "stacking"`) appear in the eligible list and can be picked once at
## rank 1; multi-pick rank-advancement of the same proficiency on a familiar
## is a follow-up polish item per the user's "unique proficiency picks" rule.

signal picker_changed

const SELECTED_PROF_TEXT_COLOR := Color(1.0, 0.85, 0.3, 1.0)


var _state: Dictionary = {}
var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry

# Computed once at setup
var _eligible_prof_keys: Array[String] = []   # union of (general) + (master's class), deduped, sorted by display name

# UI refs
var _budget_label: Label
var _eligible_list_vbox: VBoxContainer
var _picked_list_vbox: VBoxContainer
var _eligible_buttons: Dictionary = {}   # proficiency_key → Button


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(state: Dictionary,
		class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	_state = state
	_class_registry = class_registry
	_proficiency_registry = proficiency_registry
	# Defensive defaults
	_state["proficiency_budget"] = int(_state.get("proficiency_budget", 0))
	_state["master_class_id"] = String(_state.get("master_class_id", ""))
	if not _state.has("proficiencies_chosen") or not (_state["proficiencies_chosen"] is Array):
		_state["proficiencies_chosen"] = []
	_compute_eligible_list()
	if get_child_count() == 0:
		_build_ui()
	_refresh_all()


func is_complete() -> bool:
	# Budget zero (master with no proficiency selections at all): trivially complete.
	if int(_state.get("proficiency_budget", 0)) <= 0:
		return true
	# Otherwise: must have filled the full budget AND every specialization-rule
	# pick must carry a non-empty `specialization`.
	var picks: Array = _state.get("proficiencies_chosen", [])
	if picks.size() != int(_state["proficiency_budget"]):
		return false
	for p in picks:
		var key: String = String(p.get("proficiency_key", ""))
		if key.is_empty():
			return false
		if _proficiency_registry.is_specialization(key) and String(p.get("specialization", "")).is_empty():
			return false
	return true


## Returns the eligible proficiency keys (union of general + master's class
## list, deduplicated, with stacking proficiencies and unknown keys filtered
## out). Exposed for tests + integration callers.
func get_eligible_keys() -> Array[String]:
	return _eligible_prof_keys.duplicate()


# ---------------------------------------------------------------------------
# Eligible list computation
# ---------------------------------------------------------------------------

func _compute_eligible_list() -> void:
	_eligible_prof_keys.clear()
	if _proficiency_registry == null or _class_registry == null:
		return
	var seen: Dictionary = {}

	# General proficiencies
	for k in _proficiency_registry.get_general_proficiency_list():
		_consider_eligible(k, seen)

	# Master's class proficiency list
	var master_class_id: String = String(_state.get("master_class_id", ""))
	if not master_class_id.is_empty():
		for k in _class_registry.get_proficiency_list(master_class_id):
			_consider_eligible(k, seen)

	# Sort alphabetically by display name for predictable UI ordering.
	_eligible_prof_keys.sort_custom(func(a, b):
		return _display_name(a) < _display_name(b))


func _consider_eligible(key: String, seen: Dictionary) -> void:
	if seen.has(key):
		return
	if not _proficiency_registry.has_proficiency(key):
		# Skip keys that aren't in the catalog (e.g. stub class entries).
		return
	# Stage 3b: stacking proficiencies (Alchemy, Engineering, etc.) ARE
	# eligible — they can be picked once at rank 1. Multi-pick rank
	# advancement of the same proficiency on a familiar is a follow-up.
	seen[key] = true
	_eligible_prof_keys.append(key)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	# Header: budget readout
	_budget_label = Label.new()
	_budget_label.add_theme_font_size_override("font_size", 14)
	add_child(_budget_label)

	add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# Left: eligible list (scrollable)
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.55
	hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_panel.add_child(left_vbox)

	var available_header := Label.new()
	available_header.text = "Available"
	available_header.add_theme_font_size_override("font_size", 13)
	left_vbox.add_child(available_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	_eligible_list_vbox = VBoxContainer.new()
	_eligible_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_eligible_list_vbox)

	# Right: picked list (with remove buttons + spec dropdowns)
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.45
	hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_panel.add_child(right_vbox)

	var picked_header := Label.new()
	picked_header.text = "Picked"
	picked_header.add_theme_font_size_override("font_size", 13)
	right_vbox.add_child(picked_header)

	var picked_scroll := ScrollContainer.new()
	picked_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(picked_scroll)

	_picked_list_vbox = VBoxContainer.new()
	_picked_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picked_scroll.add_child(_picked_list_vbox)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_render_budget_label()
	_render_eligible_list()
	_render_picked_list()


func _render_budget_label() -> void:
	var budget: int = int(_state.get("proficiency_budget", 0))
	var picks_count: int = (_state.get("proficiencies_chosen", []) as Array).size()
	if budget <= 0:
		_budget_label.text = "Familiar Proficiencies — no slots (your master has no proficiencies)."
	else:
		_budget_label.text = "Familiar Proficiencies — %d / %d picked" % [picks_count, budget]


func _render_eligible_list() -> void:
	for child in _eligible_list_vbox.get_children():
		child.queue_free()
	_eligible_buttons.clear()

	var picked_keys: Dictionary = _picked_keys_set()
	var budget: int = int(_state.get("proficiency_budget", 0))
	var picks_count: int = (_state.get("proficiencies_chosen", []) as Array).size()
	var budget_full: bool = picks_count >= budget

	for key in _eligible_prof_keys:
		var btn := Button.new()
		btn.text = _display_name(key)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Tooltip shows the catalog description for hover detail.
		var entry: Dictionary = _proficiency_registry.get_proficiency(key)
		btn.tooltip_text = String(entry.get("description", ""))
		# Disable when already picked (uniqueness — Stage 3b doesn't support stacking)
		# OR when the budget is full.
		var is_picked := picked_keys.has(key)
		btn.disabled = is_picked or budget_full or budget <= 0
		btn.pressed.connect(_on_eligible_pressed.bind(key))
		_eligible_list_vbox.add_child(btn)
		_eligible_buttons[key] = btn

	if _eligible_prof_keys.is_empty():
		var lbl := Label.new()
		lbl.text = "(No eligible proficiencies — master class not set?)"
		lbl.modulate = Color(1, 1, 1, 0.6)
		_eligible_list_vbox.add_child(lbl)


func _render_picked_list() -> void:
	for child in _picked_list_vbox.get_children():
		child.queue_free()

	var picks: Array = _state.get("proficiencies_chosen", [])
	if picks.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(No proficiencies picked yet.)"
		empty_lbl.modulate = Color(1, 1, 1, 0.6)
		_picked_list_vbox.add_child(empty_lbl)
		return

	for i in range(picks.size()):
		_picked_list_vbox.add_child(_build_picked_row(i, picks[i]))


func _build_picked_row(index: int, pick: Dictionary) -> Control:
	var key: String = String(pick.get("proficiency_key", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = _display_name(key)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	# Specialization dropdown if applicable
	if _proficiency_registry.is_specialization(key):
		var dropdown := OptionButton.new()
		dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var specs: Array = _proficiency_registry.get_available_specializations(key)
		dropdown.add_item("(choose…)", -1)
		var current_spec: String = String(pick.get("specialization", ""))
		var current_index_in_dropdown := -1
		for sid in specs:
			var sid_str: String = String(sid)
			var label: String = _proficiency_registry.get_specialization_display_name(key, sid_str)
			dropdown.add_item(label)
			# The (choose…) item occupies index 0 with id -1; specs start at index 1.
			# Track which dropdown index matches the current pick's specialization.
			if sid_str == current_spec:
				current_index_in_dropdown = dropdown.item_count - 1
		if current_index_in_dropdown >= 0:
			dropdown.select(current_index_in_dropdown)
		else:
			dropdown.select(0)
		dropdown.item_selected.connect(_on_spec_selected.bind(index, specs))
		row.add_child(dropdown)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_on_remove_pressed.bind(index))
	row.add_child(remove_btn)

	return row


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

func _on_eligible_pressed(key: String) -> void:
	var picks: Array = _state["proficiencies_chosen"]
	if picks.size() >= int(_state.get("proficiency_budget", 0)):
		return  # budget full
	if _picked_keys_set().has(key):
		return  # already picked (Stage 3b: no stacking)
	picks.append({
		"proficiency_key": key,
		"specialization": "",
	})
	_refresh_all()
	picker_changed.emit()


func _on_remove_pressed(index: int) -> void:
	var picks: Array = _state["proficiencies_chosen"]
	if index < 0 or index >= picks.size():
		return
	picks.remove_at(index)
	_refresh_all()
	picker_changed.emit()


func _on_spec_selected(item_idx: int, picked_row_index: int, specs: Array) -> void:
	# Signature follows Godot 4's signal binding rule: signal args first
	# (`item_idx` from `OptionButton.item_selected(int)`), then bound args
	# (`picked_row_index`, `specs`) we attached via `.bind(...)`.
	# Dropdown layout: index 0 is the "(choose…)" sentinel; spec items live at
	# indices 1..n where n = specs.size().
	var picks: Array = _state["proficiencies_chosen"]
	if picked_row_index < 0 or picked_row_index >= picks.size():
		return
	if item_idx <= 0:
		picks[picked_row_index]["specialization"] = ""
	else:
		var spec_idx: int = item_idx - 1
		if spec_idx >= 0 and spec_idx < specs.size():
			picks[picked_row_index]["specialization"] = String(specs[spec_idx])
	_render_budget_label()
	picker_changed.emit()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _picked_keys_set() -> Dictionary:
	var s: Dictionary = {}
	for p in (_state.get("proficiencies_chosen", []) as Array):
		s[String(p.get("proficiency_key", ""))] = true
	return s


func _display_name(prof_key: String) -> String:
	var entry: Dictionary = _proficiency_registry.get_proficiency(prof_key)
	return String(entry.get("proficiency_name", prof_key.capitalize()))
