class_name ProficiencySelectionPanel
extends VBoxContainer

## Step 5 — Proficiency Selection.
##
## Slot allocation at level 1:
##   - 1 class proficiency slot (first level in proficiency_progression.class)
##   - 1 general proficiency slot (first level in proficiency_progression.general)
##   - max(0, INT modifier) bonus general slots (optional per ACKS rules)
##   - "Adventuring" added automatically as a free general proficiency
##
## Ranked proficiencies: selecting a key you already own advances its rank.
## Specialization proficiencies: a sub-dropdown asks which specialization.


var _state: Dictionary = {}
var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry

# Slot tracking
var _class_slots_total: int = 0
var _general_slots_total: int = 0
var _class_slots_used: int = 0
var _general_slots_used: int = 0   # Adventuring not counted against this

# Available lists
var _class_prof_list: Array[String] = []
var _general_prof_list: Array[String] = []

# UI refs
var _slot_label: Label
var _tab_bar: TabBar
var _list_container: VBoxContainer   # holds the active tab's item rows
var _selected_panel: VBoxContainer   # right-side selected profs
var _status_label: Label
var _spec_popup_container: VBoxContainer  # holds spec selector when needed

# Pending state for specialization selection
var _pending_prof_key: String = ""
var _pending_slot_type: String = ""


func setup(state: Dictionary, class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	_state = state
	_class_registry = class_registry
	_proficiency_registry = proficiency_registry
	if get_child_count() == 0:
		_build_ui()
	_compute_slots()
	_build_prof_lists()
	_restore_from_state()
	_refresh_all()


func is_complete() -> bool:
	## Class slot must be filled (except classes with no class proficiency list).
	if _class_slots_total == 0:
		return true
	for p in _state.get("proficiencies", []):
		if p.get("slot_type", "") == "class":
			return true
	return false


# ---------------------------------------------------------------------------
# Slot computation
# ---------------------------------------------------------------------------

func _compute_slots() -> void:
	var class_id: String = _state.get("class_id", "")
	var cls := _class_registry.get_class_def(class_id)
	var prog: Dictionary = cls.get("proficiency_progression", {})

	var class_levels: Array = prog.get("class", [])
	_class_slots_total = 0
	for lvl in class_levels:
		if int(lvl) <= 1:
			_class_slots_total += 1

	var general_levels: Array = prog.get("general", [])
	_general_slots_total = 0
	for lvl in general_levels:
		if int(lvl) <= 1:
			_general_slots_total += 1

	# Bonus general slots from INT modifier (minimum 0)
	var effective: Dictionary = _state.get("traded_scores", {})
	if effective.is_empty():
		effective = _state.get("scores", {})
	var int_score: int = int(effective.get("INT", 10))
	var int_mod := CharacterData.ability_modifier(int_score)
	if int_mod > 0:
		_general_slots_total += int_mod


func _build_prof_lists() -> void:
	var class_id: String = _state.get("class_id", "")
	var cls := _class_registry.get_class_def(class_id)
	var raw_class_list: Array = cls.get("class_proficiency_list", [])
	_class_prof_list.clear()
	for k in raw_class_list:
		_class_prof_list.append(k as String)
	_class_prof_list.sort()

	var raw_general := _proficiency_registry.get_general_proficiency_list()
	_general_prof_list.clear()
	for k in raw_general:
		if k != "adventuring":  # auto-added
			_general_prof_list.append(k as String)
	_general_prof_list.sort()


func _restore_from_state() -> void:
	_class_slots_used = 0
	_general_slots_used = 0
	for p in _state.get("proficiencies", []):
		var slot_type: String = p.get("slot_type", "")
		if slot_type == "class":
			_class_slots_used += 1
		elif slot_type == "general" and p.get("proficiency_key", "") != "adventuring":
			_general_slots_used += 1


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	_slot_label = Label.new()
	_slot_label.text = ""
	add_child(_slot_label)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# --- Left: tab bar + list ---
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

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_container)

	# Specialization sub-selector (hidden by default)
	_spec_popup_container = VBoxContainer.new()
	_spec_popup_container.visible = false
	left_vbox.add_child(_spec_popup_container)

	# --- Right: selected proficiencies ---
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.45
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_vbox)

	var sel_header := Label.new()
	sel_header.text = "Selected Proficiencies:"
	right_vbox.add_child(sel_header)

	var sel_scroll := ScrollContainer.new()
	sel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(sel_scroll)

	_selected_panel = VBoxContainer.new()
	_selected_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_scroll.add_child(_selected_panel)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_slot_label()
	_refresh_list()
	_refresh_selected()


func _refresh_slot_label() -> void:
	var class_remaining := _class_slots_total - _class_slots_used
	var general_remaining := _general_slots_total - _general_slots_used
	_slot_label.text = "Class slots: %d/%d  |  General slots: %d/%d  (Adventuring: free)" % [
		_class_slots_used, _class_slots_total,
		_general_slots_used, _general_slots_total]
	if class_remaining > 0:
		_slot_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		_slot_label.remove_theme_color_override("font_color")


func _refresh_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	var active_tab := _tab_bar.current_tab
	var prof_list: Array[String] = _class_prof_list if active_tab == 0 else _general_prof_list
	var slot_type := "class" if active_tab == 0 else "general"
	var slots_remaining := (_class_slots_total - _class_slots_used) if active_tab == 0 \
		else (_general_slots_total - _general_slots_used)

	if prof_list.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No proficiencies available." if active_tab == 0 else "No general proficiencies."
		_list_container.add_child(empty_lbl)
		return

	for prof_key in prof_list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_list_container.add_child(row)

		var def := _proficiency_registry.get_proficiency(prof_key)
		var display_name: String = def.get("proficiency_name", prof_key.replace("_", " ").capitalize())
		var desc: String = (def.get("description", "") as String).left(80)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_vbox)

		var name_lbl := Label.new()
		name_lbl.text = display_name
		info_vbox.add_child(name_lbl)

		if not desc.is_empty():
			var desc_lbl := Label.new()
			desc_lbl.text = desc + ("…" if desc.length() >= 80 else "")
			desc_lbl.add_theme_font_size_override("font_size", 11)
			desc_lbl.modulate = Color(0.75, 0.75, 0.75, 1.0)
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info_vbox.add_child(desc_lbl)

		# Rank indicator (if already selected)
		var current_rank := _get_current_rank(prof_key, slot_type)
		var max_rank := _proficiency_registry.get_max_rank(prof_key)

		var add_btn := Button.new()
		add_btn.custom_minimum_size = Vector2(70, 0)

		if current_rank > 0 and current_rank < max_rank:
			add_btn.text = "Rank %d→%d" % [current_rank, current_rank + 1]
		elif current_rank >= max_rank and max_rank > 1:
			add_btn.text = "Max Rank"
			add_btn.disabled = true
		elif current_rank > 0 and max_rank == 1 and not _proficiency_registry.is_specialization(prof_key):
			add_btn.text = "Taken"
			add_btn.disabled = true
		else:
			add_btn.text = "Select"

		if slots_remaining <= 0 and (current_rank == 0 or current_rank >= max_rank):
			add_btn.disabled = true
			add_btn.tooltip_text = "No slots remaining."

		add_btn.pressed.connect(_on_add_proficiency.bind(prof_key, slot_type))
		row.add_child(add_btn)

		_list_container.add_child(HSeparator.new())


func _refresh_selected() -> void:
	for child in _selected_panel.get_children():
		child.queue_free()

	# Always show Adventuring as first entry
	var adv_row := _make_selected_row("Adventuring", "general", 1, "", false)
	_selected_panel.add_child(adv_row)

	for p in _state.get("proficiencies", []):
		var key: String = p.get("proficiency_key", "")
		if key == "adventuring":
			continue
		var slot_type: String = p.get("slot_type", "general")
		var rank: int = int(p.get("rank", 1))
		var spec: String = p.get("specialization", "")
		var row := _make_selected_row(key, slot_type, rank, spec, true)
		_selected_panel.add_child(row)


func _make_selected_row(key: String, slot_type: String, rank: int, spec: String,
		removable: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var def := _proficiency_registry.get_proficiency(key) if _proficiency_registry.has_proficiency(key) else {}
	var display_name: String = def.get("proficiency_name", key.replace("_", " ").capitalize())
	if not spec.is_empty():
		display_name += " [%s]" % spec.replace("_", " ").capitalize()
	if rank > 1:
		display_name += " (Rank %d)" % rank
	var slot_tag := "[C]" if slot_type == "class" else "[G]"

	var lbl := Label.new()
	lbl.text = "%s %s" % [slot_tag, display_name]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	if removable:
		var remove_btn := Button.new()
		remove_btn.text = "✕"
		remove_btn.custom_minimum_size = Vector2(30, 0)
		remove_btn.pressed.connect(_on_remove_proficiency.bind(key, slot_type, spec))
		row.add_child(remove_btn)

	return row


# ---------------------------------------------------------------------------
# Selection logic
# ---------------------------------------------------------------------------

func _get_current_rank(prof_key: String, slot_type: String) -> int:
	for p in _state.get("proficiencies", []):
		if p.get("proficiency_key", "") == prof_key and p.get("slot_type", "") == slot_type:
			return int(p.get("rank", 1))
	return 0


func _on_tab_changed(_tab: int) -> void:
	_spec_popup_container.visible = false
	_pending_prof_key = ""
	_refresh_list()


func _on_add_proficiency(prof_key: String, slot_type: String) -> void:
	_status_label.text = ""

	if _proficiency_registry.is_specialization(prof_key):
		_show_specialization_selector(prof_key, slot_type)
		return

	# Check for rank advancement
	var current_rank := _get_current_rank(prof_key, slot_type)
	var max_rank := _proficiency_registry.get_max_rank(prof_key)

	if current_rank > 0 and current_rank < max_rank:
		# Advance rank
		_advance_rank(prof_key, slot_type)
		return

	# New selection
	if not _can_add_slot(slot_type):
		_status_label.text = "No %s slots remaining." % slot_type
		return

	_add_proficiency_record(prof_key, slot_type, 1, "")


func _show_specialization_selector(prof_key: String, slot_type: String) -> void:
	_pending_prof_key = prof_key
	_pending_slot_type = slot_type

	for child in _spec_popup_container.get_children():
		child.queue_free()

	var def := _proficiency_registry.get_proficiency(prof_key)
	# catalog entries use null when specializations are open-ended (e.g. Riding: any animal type)
	var spec_raw = def.get("specializations")
	var specializations: Array = spec_raw if spec_raw is Array else []

	var prof_name: String = def.get("proficiency_name", prof_key)

	var lbl := Label.new()
	_spec_popup_container.add_child(lbl)

	if specializations.is_empty():
		# Open-ended specialization — let the player name it (e.g. Riding → "horse", "camel")
		lbl.text = "Enter %s specialization:" % prof_name
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		var desc: String = def.get("description", "")
		if not desc.is_empty():
			var desc_lbl := Label.new()
			desc_lbl.text = desc
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_lbl.add_theme_font_size_override("font_size", 11)
			desc_lbl.modulate = Color(0.75, 0.75, 0.75, 1.0)
			_spec_popup_container.add_child(desc_lbl)

		var text_edit := LineEdit.new()
		text_edit.placeholder_text = "e.g. horse, camel, elephant…"
		text_edit.custom_minimum_size = Vector2(200, 0)
		_spec_popup_container.add_child(text_edit)

		var confirm_btn := Button.new()
		confirm_btn.text = "Confirm"
		confirm_btn.pressed.connect(func():
			var entered := text_edit.text.strip_edges().to_lower().replace(" ", "_")
			if not entered.is_empty():
				_on_specialization_selected(entered)
		)
		_spec_popup_container.add_child(confirm_btn)
	else:
		lbl.text = "Choose specialization:"
		for spec in specializations:
			var spec_str: String = (spec as String).replace("_", " ").capitalize()
			var btn := Button.new()
			btn.text = spec_str
			btn.pressed.connect(_on_specialization_selected.bind(spec as String))
			_spec_popup_container.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): _spec_popup_container.visible = false)
	_spec_popup_container.add_child(cancel_btn)

	_spec_popup_container.visible = true


func _on_specialization_selected(spec: String) -> void:
	_spec_popup_container.visible = false
	if not _can_add_slot(_pending_slot_type):
		_status_label.text = "No %s slots remaining." % _pending_slot_type
		return
	_add_proficiency_record(_pending_prof_key, _pending_slot_type, 1, spec)
	_pending_prof_key = ""
	_pending_slot_type = ""


func _can_add_slot(slot_type: String) -> bool:
	if slot_type == "class":
		return _class_slots_used < _class_slots_total
	return _general_slots_used < _general_slots_total


func _add_proficiency_record(key: String, slot_type: String, rank: int, spec: String) -> void:
	var profs: Array = _state.get("proficiencies", [])
	profs.append({
		"proficiency_key": key,
		"rank": rank,
		"slot_type": slot_type,
		"selections_count": 1,
		"specialization": spec,
	})
	_state["proficiencies"] = profs
	if slot_type == "class":
		_class_slots_used += 1
	elif key != "adventuring":
		_general_slots_used += 1
	_refresh_all()


func _advance_rank(prof_key: String, slot_type: String) -> void:
	if not _can_add_slot(slot_type):
		_status_label.text = "No %s slots remaining to advance rank." % slot_type
		return
	var profs: Array = _state.get("proficiencies", [])
	for i in profs.size():
		if profs[i].get("proficiency_key", "") == prof_key and \
				profs[i].get("slot_type", "") == slot_type:
			profs[i]["rank"] = int(profs[i]["rank"]) + 1
			profs[i]["selections_count"] = int(profs[i].get("selections_count", 1)) + 1
			break
	_state["proficiencies"] = profs
	if slot_type == "class":
		_class_slots_used += 1
	else:
		_general_slots_used += 1
	_refresh_all()


func _on_remove_proficiency(key: String, slot_type: String, spec: String) -> void:
	var profs: Array = _state.get("proficiencies", [])
	for i in range(profs.size() - 1, -1, -1):
		var p: Dictionary = profs[i]
		if p.get("proficiency_key", "") == key and \
				p.get("slot_type", "") == slot_type and \
				p.get("specialization", "") == spec:
			var removed_rank: int = int(p.get("rank", 1))
			profs.remove_at(i)
			# Return slots for each rank
			for _r in range(removed_rank):
				if slot_type == "class":
					_class_slots_used = maxi(0, _class_slots_used - 1)
				elif key != "adventuring":
					_general_slots_used = maxi(0, _general_slots_used - 1)
			break
	_state["proficiencies"] = profs
	_refresh_all()
