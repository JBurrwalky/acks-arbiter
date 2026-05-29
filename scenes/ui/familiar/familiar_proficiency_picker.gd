class_name FamiliarProficiencyPicker
extends VBoxContainer

## Familiar-specific proficiency picker.
##
## Per gdd-familiars.md §3.4.1 (revised), a familiar picks its own proficiencies
## under the same slot-split + stacking rules the master uses:
##
##   - Two separate budgets: class slots and general slots, matching the
##     master's `proficiency_progression` allocation.
##   - Class slots are spent on the master's class proficiency list.
##   - General slots are spent on the general proficiency list.
##   - Picks are independent of master's actual selections (eligibility comes
##     from the master's *class*, not master's *picks*).
##   - Same per-proficiency stacking rules apply: a non-spec `stacking` proc
##     (Alchemy / Engineering / etc.) can be picked multiple times in the
##     same slot_type to advance rank, capped at `max_rank`. A `specialization`
##     proc can be picked multiple times for different specialization variants
##     (Knowledge:history vs Knowledge:nature) — each instance is a separate
##     pick. A `unique` proc can be picked once per slot_type.
##
## State Dict shape (mutated in-place):
##
##   {
##     "class_slot_budget":    int,             # slots available for class list
##     "general_slot_budget":  int,             # slots available for general list
##     "master_class_id":      String,          # for class proficiency list lookup
##     "proficiencies_chosen": Array[Dictionary],  # picks (see below)
##   }
##
## Each entry in `proficiencies_chosen` mirrors `character_proficiencies` shape:
##
##   { "proficiency_key": String, "slot_type": String, "rank": int,
##     "selections_count": int, "specialization": String }
##
## TabBar switches between Class and General eligible lists; the picked list on
## the right shows all picks with slot_type indicators.

signal picker_changed

const SLOT_TYPE_CLASS := "class"
const SLOT_TYPE_GENERAL := "general"


var _state: Dictionary = {}
var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry

# Eligible lists per slot_type (sorted by display name).
var _class_prof_list: Array[String] = []
var _general_prof_list: Array[String] = []

# Slot-uses counters, recomputed from `proficiencies_chosen` in `_restore_slots_used`.
var _class_slots_used: int = 0
var _general_slots_used: int = 0

# UI refs
var _budget_label: Label
var _tab_bar: TabBar     # 0 = Class, 1 = General
var _eligible_list_vbox: VBoxContainer
var _picked_list_vbox: VBoxContainer
var _eligible_buttons: Dictionary = {}   # proficiency_key → Button (for the active tab only)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(state: Dictionary,
		class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	_state = state
	_class_registry = class_registry
	_proficiency_registry = proficiency_registry
	_state["class_slot_budget"] = int(_state.get("class_slot_budget", 0))
	_state["general_slot_budget"] = int(_state.get("general_slot_budget", 0))
	_state["master_class_id"] = String(_state.get("master_class_id", ""))
	if not _state.has("proficiencies_chosen") or not (_state["proficiencies_chosen"] is Array):
		_state["proficiencies_chosen"] = []
	_build_prof_lists()
	_restore_slots_used()
	if get_child_count() == 0:
		_build_ui()
	_refresh_all()


func is_complete() -> bool:
	if _class_slots_used < int(_state.get("class_slot_budget", 0)):
		return false
	if _general_slots_used < int(_state.get("general_slot_budget", 0)):
		return false
	# Specialization-rule picks must carry a chosen specialization.
	for p in _state.get("proficiencies_chosen", []):
		if not (p is Dictionary):
			continue
		var key: String = String(p.get("proficiency_key", ""))
		if key.is_empty():
			return false
		if _proficiency_registry.is_specialization(key) and String(p.get("specialization", "")).is_empty():
			return false
	return true


## Backward-compat union of class + general for callers that don't care about
## the split (used by tests asserting "X is eligible at all").
func get_eligible_keys() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for k in _class_prof_list:
		if not seen.has(k):
			seen[k] = true
			result.append(k)
	for k in _general_prof_list:
		if not seen.has(k):
			seen[k] = true
			result.append(k)
	return result


func get_eligible_class_keys() -> Array[String]:
	return _class_prof_list.duplicate()


func get_eligible_general_keys() -> Array[String]:
	return _general_prof_list.duplicate()


# ---------------------------------------------------------------------------
# Eligible list computation
# ---------------------------------------------------------------------------

func _build_prof_lists() -> void:
	_class_prof_list.clear()
	_general_prof_list.clear()
	if _proficiency_registry == null or _class_registry == null:
		return
	var master_class_id: String = String(_state.get("master_class_id", ""))
	if not master_class_id.is_empty():
		for k in _class_registry.get_proficiency_list(master_class_id):
			if _proficiency_registry.has_proficiency(k):
				_class_prof_list.append(k)
	for k in _proficiency_registry.get_general_proficiency_list():
		if _proficiency_registry.has_proficiency(k):
			_general_prof_list.append(k)
	_class_prof_list.sort_custom(func(a, b): return _display_name(a) < _display_name(b))
	_general_prof_list.sort_custom(func(a, b): return _display_name(a) < _display_name(b))


func _restore_slots_used() -> void:
	_class_slots_used = 0
	_general_slots_used = 0
	for p in _state.get("proficiencies_chosen", []):
		if not (p is Dictionary):
			continue
		var slot_type: String = String(p.get("slot_type", ""))
		var sel: int = int(p.get("selections_count", 1))
		if slot_type == SLOT_TYPE_CLASS:
			_class_slots_used += sel
		elif slot_type == SLOT_TYPE_GENERAL:
			_general_slots_used += sel


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	_budget_label = Label.new()
	_budget_label.add_theme_font_size_override("font_size", 14)
	add_child(_budget_label)

	add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# Left: TabBar (Class / General) + eligible list
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 0.55
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_vbox)

	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Class")
	_tab_bar.add_tab("General")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	left_vbox.add_child(_tab_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	_eligible_list_vbox = VBoxContainer.new()
	_eligible_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_eligible_list_vbox)

	# Right: picked list
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
	var class_total: int = int(_state.get("class_slot_budget", 0))
	var general_total: int = int(_state.get("general_slot_budget", 0))
	if class_total <= 0 and general_total <= 0:
		_budget_label.text = "Familiar Proficiencies — no slots (your master has no proficiency selections)."
	else:
		_budget_label.text = "Familiar Proficiencies — Class: %d / %d, General: %d / %d" % [
			_class_slots_used, class_total,
			_general_slots_used, general_total,
		]


func _active_slot_type() -> String:
	if _tab_bar == null:
		return SLOT_TYPE_CLASS
	return SLOT_TYPE_CLASS if _tab_bar.current_tab == 0 else SLOT_TYPE_GENERAL


func _active_eligible_list() -> Array[String]:
	if _active_slot_type() == SLOT_TYPE_CLASS:
		return _class_prof_list
	return _general_prof_list


func _slots_full(slot_type: String) -> bool:
	if slot_type == SLOT_TYPE_CLASS:
		return _class_slots_used >= int(_state.get("class_slot_budget", 0))
	return _general_slots_used >= int(_state.get("general_slot_budget", 0))


func _render_eligible_list() -> void:
	for child in _eligible_list_vbox.get_children():
		child.queue_free()
	_eligible_buttons.clear()

	var slot_type: String = _active_slot_type()
	var keys: Array[String] = _active_eligible_list()
	var slots_full: bool = _slots_full(slot_type)

	for key in keys:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var entry: Dictionary = _proficiency_registry.get_proficiency(key)
		btn.tooltip_text = str(entry.get("description", ""))
		btn.text = _format_eligible_label(key, slot_type)
		btn.disabled = _is_eligible_disabled(key, slot_type, slots_full)
		btn.pressed.connect(_on_eligible_pressed.bind(key, slot_type))
		_eligible_list_vbox.add_child(btn)
		_eligible_buttons[key] = btn

	if keys.is_empty():
		var lbl := Label.new()
		lbl.text = "(No eligible %s proficiencies — master class not set?)" % slot_type
		lbl.modulate = Color(1, 1, 1, 0.6)
		_eligible_list_vbox.add_child(lbl)


func _format_eligible_label(key: String, slot_type: String) -> String:
	var name: String = _display_name(key)
	var sel_rule: String = _proficiency_registry.get_selection_rule(key)
	var existing_idx: int = _find_existing_pick(key, slot_type)
	if existing_idx == -1:
		# Not yet picked.
		return name
	var existing: Dictionary = _state["proficiencies_chosen"][existing_idx]
	if sel_rule == "stacking":
		var current_rank: int = int(existing.get("rank", 1))
		var max_rank: int = _proficiency_registry.get_max_rank(key)
		if current_rank >= max_rank:
			return "%s (Rank %d — max)" % [name, current_rank]
		return "%s (Rank %d → %d)" % [name, current_rank, current_rank + 1]
	if sel_rule == "specialization":
		var picked_count: int = _count_picks_of_key(key, slot_type)
		var max_sel: int = _proficiency_registry.get_max_selections(key)
		# `max_selections == 0` means unlimited (Knowledge / Craft / Profession).
		if max_sel == 0:
			return "%s (Picked %d — add another)" % [name, picked_count]
		if max_sel > 1:
			return "%s (Picked %d/%d — add another)" % [name, picked_count, max_sel]
		return "%s (Picked)" % name
	# unique
	return "%s (Picked)" % name


func _is_eligible_disabled(key: String, slot_type: String, slots_full: bool) -> bool:
	var sel_rule: String = _proficiency_registry.get_selection_rule(key)
	var existing_idx: int = _find_existing_pick(key, slot_type)
	if existing_idx == -1:
		# Not picked yet — only blocked when budget is full.
		return slots_full
	var existing: Dictionary = _state["proficiencies_chosen"][existing_idx]
	if sel_rule == "stacking":
		var max_rank: int = _proficiency_registry.get_max_rank(key)
		if int(existing.get("rank", 1)) >= max_rank:
			return true   # already at max rank
		return slots_full
	if sel_rule == "specialization":
		var max_sel: int = _proficiency_registry.get_max_selections(key)
		# `max_selections == 0` means unlimited; never disable on count alone.
		if max_sel > 0 and _count_picks_of_key(key, slot_type) >= max_sel:
			return true
		return slots_full
	# unique — already picked, no further selections
	return true


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
	var slot_type: String = String(pick.get("slot_type", ""))
	var sel_rule: String = _proficiency_registry.get_selection_rule(key)
	var rank: int = int(pick.get("rank", 1))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Slot-type chip + name
	var chip := Label.new()
	chip.text = "[C]" if slot_type == SLOT_TYPE_CLASS else "[G]"
	chip.modulate = Color(1, 1, 1, 0.7)
	row.add_child(chip)

	var name_lbl := Label.new()
	var label_text: String = _display_name(key)
	if sel_rule == "stacking" and rank > 1:
		label_text += " (Rank %d)" % rank
	name_lbl.text = label_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	# Specialization dropdown (only for spec procs).
	if _proficiency_registry.is_specialization(key):
		var dropdown := OptionButton.new()
		dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var specs: Array = _proficiency_registry.get_available_specializations(key)
		dropdown.add_item("(choose…)", -1)
		var current_spec: String = String(pick.get("specialization", ""))
		var current_index_in_dropdown: int = -1
		# Filter out specs already chosen on other instances of this key in
		# the same slot_type — duplicates of the same spec aren't allowed.
		var taken: Dictionary = _spec_picks_for_key(key, slot_type, index)
		for sid in specs:
			var sid_str: String = String(sid)
			if taken.has(sid_str):
				continue
			var label: String = _proficiency_registry.get_specialization_display_name(key, sid_str)
			dropdown.add_item(label)
			if sid_str == current_spec:
				current_index_in_dropdown = dropdown.item_count - 1
		if current_index_in_dropdown >= 0:
			dropdown.select(current_index_in_dropdown)
		else:
			dropdown.select(0)
		dropdown.item_selected.connect(_on_spec_selected.bind(index, specs))
		row.add_child(dropdown)

	# Remove button (or rank-down button for stacked picks)
	if sel_rule == "stacking" and rank > 1:
		var down_btn := Button.new()
		down_btn.text = "Rank-"
		down_btn.tooltip_text = "Reduce rank by 1"
		down_btn.pressed.connect(_on_rank_down_pressed.bind(index))
		row.add_child(down_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_on_remove_pressed.bind(index))
	row.add_child(remove_btn)

	return row


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

func _on_tab_changed(_idx: int) -> void:
	_render_eligible_list()


func _on_eligible_pressed(key: String, slot_type: String) -> void:
	if _slots_full(slot_type):
		return
	var sel_rule: String = _proficiency_registry.get_selection_rule(key)
	var existing_idx: int = _find_existing_pick(key, slot_type)

	if existing_idx == -1:
		_append_pick(key, slot_type, 1, 1, "")
	elif sel_rule == "stacking":
		var existing: Dictionary = _state["proficiencies_chosen"][existing_idx]
		var current_rank: int = int(existing.get("rank", 1))
		var max_rank: int = _proficiency_registry.get_max_rank(key)
		if current_rank >= max_rank:
			return
		existing["rank"] = current_rank + 1
		existing["selections_count"] = int(existing.get("selections_count", 1)) + 1
		_inc_used(slot_type, 1)
	elif sel_rule == "specialization":
		var max_sel: int = _proficiency_registry.get_max_selections(key)
		# `max_selections == 0` means unlimited.
		if max_sel > 0 and _count_picks_of_key(key, slot_type) >= max_sel:
			return
		_append_pick(key, slot_type, 1, 1, "")
	else:
		# unique — already picked, no-op
		return

	_refresh_all()
	picker_changed.emit()


func _on_remove_pressed(index: int) -> void:
	var picks: Array = _state.get("proficiencies_chosen", [])
	if index < 0 or index >= picks.size():
		return
	var pick: Dictionary = picks[index]
	var slot_type: String = String(pick.get("slot_type", ""))
	var sel: int = int(pick.get("selections_count", 1))
	picks.remove_at(index)
	_dec_used(slot_type, sel)
	_refresh_all()
	picker_changed.emit()


func _on_rank_down_pressed(index: int) -> void:
	var picks: Array = _state.get("proficiencies_chosen", [])
	if index < 0 or index >= picks.size():
		return
	var pick: Dictionary = picks[index]
	var rank: int = int(pick.get("rank", 1))
	if rank <= 1:
		_on_remove_pressed(index)
		return
	pick["rank"] = rank - 1
	pick["selections_count"] = max(1, int(pick.get("selections_count", 1)) - 1)
	_dec_used(String(pick.get("slot_type", "")), 1)
	_refresh_all()
	picker_changed.emit()


func _on_spec_selected(item_idx: int, picked_row_index: int, specs: Array) -> void:
	# Signal-binding rule (Godot 4): signal args first, then bound args.
	# `item_idx` is the OptionButton's selected index; index 0 is the
	# "(choose…)" sentinel, indices 1..n correspond to specs[0..n-1] *as
	# rendered* (filtered to exclude already-taken variants).
	var picks: Array = _state.get("proficiencies_chosen", [])
	if picked_row_index < 0 or picked_row_index >= picks.size():
		return
	if item_idx <= 0:
		picks[picked_row_index]["specialization"] = ""
	else:
		# Re-derive the visible specs list (specs filtered for taken duplicates,
		# excluding our own row's current specialization). This mirrors the
		# filter in `_build_picked_row`.
		var key: String = String(picks[picked_row_index].get("proficiency_key", ""))
		var slot_type: String = String(picks[picked_row_index].get("slot_type", ""))
		var taken: Dictionary = _spec_picks_for_key(key, slot_type, picked_row_index)
		var visible: Array = []
		for sid in specs:
			var sid_str: String = String(sid)
			if not taken.has(sid_str):
				visible.append(sid_str)
		var spec_idx: int = item_idx - 1
		if spec_idx >= 0 and spec_idx < visible.size():
			picks[picked_row_index]["specialization"] = String(visible[spec_idx])
	_render_picked_list()
	_render_budget_label()
	picker_changed.emit()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _append_pick(key: String, slot_type: String, rank: int, selections: int, spec: String) -> void:
	(_state["proficiencies_chosen"] as Array).append({
		"proficiency_key": key,
		"slot_type": slot_type,
		"rank": rank,
		"selections_count": selections,
		"specialization": spec,
	})
	_inc_used(slot_type, selections)


func _inc_used(slot_type: String, n: int) -> void:
	if slot_type == SLOT_TYPE_CLASS:
		_class_slots_used += n
	elif slot_type == SLOT_TYPE_GENERAL:
		_general_slots_used += n


func _dec_used(slot_type: String, n: int) -> void:
	if slot_type == SLOT_TYPE_CLASS:
		_class_slots_used = max(0, _class_slots_used - n)
	elif slot_type == SLOT_TYPE_GENERAL:
		_general_slots_used = max(0, _general_slots_used - n)


## Returns the index of the first pick matching key + slot_type. For
## specialization-rule procs there can be multiple instances of the same key
## (different specs) — this returns the first one, useful for "is it picked
## at all?" checks. Stacking uses this to find the unique stacking row.
func _find_existing_pick(key: String, slot_type: String) -> int:
	var picks: Array = _state.get("proficiencies_chosen", [])
	for i in range(picks.size()):
		var p: Dictionary = picks[i]
		if String(p.get("proficiency_key", "")) == key and String(p.get("slot_type", "")) == slot_type:
			return i
	return -1


func _count_picks_of_key(key: String, slot_type: String) -> int:
	var n: int = 0
	for p in _state.get("proficiencies_chosen", []):
		if not (p is Dictionary):
			continue
		if String(p.get("proficiency_key", "")) == key and String(p.get("slot_type", "")) == slot_type:
			n += 1
	return n


## Returns a Dictionary set of specialization values already taken for a
## (key, slot_type) — excluding the row at `exclude_index` (so a row's own
## currently-selected spec doesn't filter itself out of its own dropdown).
func _spec_picks_for_key(key: String, slot_type: String, exclude_index: int) -> Dictionary:
	var taken: Dictionary = {}
	var picks: Array = _state.get("proficiencies_chosen", [])
	for i in range(picks.size()):
		if i == exclude_index:
			continue
		var p: Dictionary = picks[i]
		if String(p.get("proficiency_key", "")) != key:
			continue
		if String(p.get("slot_type", "")) != slot_type:
			continue
		var spec: String = String(p.get("specialization", ""))
		if not spec.is_empty():
			taken[spec] = true
	return taken


func _display_name(prof_key: String) -> String:
	var entry: Dictionary = _proficiency_registry.get_proficiency(prof_key)
	return str(entry.get("proficiency_name", prof_key.capitalize()))
