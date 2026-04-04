class_name LevelUpProficiencyPicker
extends VBoxContainer

## Inline proficiency picker for the PC level-up flow.
##
## Works from a snapshot of the character's current proficiencies plus the
## number of new class/general slots granted by the pending level-up.
## The picker returns the full final proficiency list so level-up persistence
## can save an exact post-choice state.

signal selection_state_changed

var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry

var _class_id: String = ""
var _base_proficiencies: Array = []
var _working_proficiencies: Array = []

var _class_slots_total: int = 0
var _general_slots_total: int = 0
var _class_slots_used: int = 0
var _general_slots_used: int = 0

var _class_prof_list: Array[String] = []
var _general_prof_list: Array[String] = []

var _slot_label: Label
var _tab_bar: TabBar
var _list_container: VBoxContainer
var _pending_panel: VBoxContainer
var _status_label: Label
var _spec_popup_frame: PanelContainer
var _spec_popup_container: VBoxContainer

var _pending_prof_key: String = ""
var _pending_slot_type: String = ""

var _apostasy_selected_keys: Dictionary = {}  # spell_key -> true, during picker session
var _apostasy_spells: Array = []              # confirmed spell dicts for this level-up


func setup(class_id: String, base_proficiencies: Array, class_slots: int,
		general_slots: int, class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	_class_id = class_id
	_class_registry = class_registry
	_proficiency_registry = proficiency_registry
	_base_proficiencies = _duplicate_proficiencies(base_proficiencies)
	_working_proficiencies = _duplicate_proficiencies(base_proficiencies)
	_class_slots_total = maxi(0, class_slots)
	_general_slots_total = maxi(0, general_slots)

	if get_child_count() == 0:
		_build_ui()

	_build_prof_lists()
	_recalculate_slot_usage()
	_refresh_all()


func is_complete() -> bool:
	return _class_slots_used >= _class_slots_total and _general_slots_used >= _general_slots_total


func get_final_proficiencies() -> Array:
	return _duplicate_proficiencies(_working_proficiencies)


func _build_prof_lists() -> void:
	_class_prof_list.clear()
	_general_prof_list.clear()

	var cls := _class_registry.get_class_def(_class_id)
	var raw_class_list: Array = cls.get("class_proficiency_list", [])
	for key in raw_class_list:
		_class_prof_list.append(key as String)
	_class_prof_list.sort()

	var raw_general := _proficiency_registry.get_general_proficiency_list()
	for key in raw_general:
		if key != "adventuring":
			_general_prof_list.append(key as String)
	_general_prof_list.sort()


func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	_slot_label = Label.new()
	add_child(_slot_label)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

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

	_spec_popup_frame = PanelContainer.new()
	UiSurfaceStyles.apply_framed_window_chrome(_spec_popup_frame)
	_spec_popup_frame.visible = false
	left_vbox.add_child(_spec_popup_frame)

	var spec_margin := MarginContainer.new()
	spec_margin.add_theme_constant_override("margin_left", 10)
	spec_margin.add_theme_constant_override("margin_right", 10)
	spec_margin.add_theme_constant_override("margin_top", 10)
	spec_margin.add_theme_constant_override("margin_bottom", 10)
	_spec_popup_frame.add_child(spec_margin)

	_spec_popup_container = VBoxContainer.new()
	_spec_popup_container.add_theme_constant_override("separation", 8)
	spec_margin.add_child(_spec_popup_container)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.45
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_vbox)

	var pending_header := Label.new()
	pending_header.text = "Pending Choices:"
	right_vbox.add_child(pending_header)

	var pending_scroll := ScrollContainer.new()
	pending_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(pending_scroll)

	_pending_panel = VBoxContainer.new()
	_pending_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pending_scroll.add_child(_pending_panel)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)


func _refresh_all() -> void:
	_refresh_slot_label()
	_refresh_list()
	_refresh_pending()


func _refresh_slot_label() -> void:
	_slot_label.text = "Class slots: %d/%d  |  General slots: %d/%d" % [
		_class_slots_used,
		_class_slots_total,
		_general_slots_used,
		_general_slots_total,
	]
	if is_complete():
		_slot_label.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	else:
		_slot_label.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)


func _refresh_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	var active_tab := _tab_bar.current_tab
	var prof_list: Array[String] = _class_prof_list if active_tab == 0 else _general_prof_list
	var slot_type := "class" if active_tab == 0 else "general"
	var slots_remaining := _remaining_slots(slot_type)

	if prof_list.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No proficiencies available for this slot type."
		_list_container.add_child(empty_lbl)
		return

	for prof_key in prof_list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_list_container.add_child(row)

		var def := _proficiency_registry.get_proficiency(prof_key)
		var display_name: String = def.get("proficiency_name", prof_key.replace("_", " ").capitalize())
		var embedded_spec := _proficiency_registry.get_specialization_from_compound_key(prof_key)
		if not embedded_spec.is_empty():
			var base_key := _proficiency_registry.resolve_key(prof_key)
			var spec_display := _proficiency_registry.get_specialization_display_name(base_key, embedded_spec)
			display_name += " (%s)" % spec_display
		var desc: String = (def.get("description", "") as String).left(80)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_vbox)

		var name_lbl := Label.new()
		name_lbl.text = display_name
		info_vbox.add_child(name_lbl)

		if not desc.is_empty():
			var desc_lbl := Label.new()
			desc_lbl.text = desc + ("..." if desc.length() >= 80 else "")
			desc_lbl.add_theme_font_size_override("font_size", 11)
			desc_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info_vbox.add_child(desc_lbl)

		var add_btn := Button.new()
		add_btn.custom_minimum_size = Vector2(90, 0)

		if not embedded_spec.is_empty():
			var base_key := _proficiency_registry.resolve_key(prof_key)
			var current_rank := _get_current_rank(base_key, slot_type, embedded_spec)
			var max_rank := _proficiency_registry.get_max_rank(base_key)
			if current_rank > 0 and current_rank < max_rank:
				add_btn.text = "Rank %d->%d" % [current_rank, current_rank + 1]
			elif current_rank >= max_rank:
				add_btn.text = "Max Rank" if max_rank > 1 else "Taken"
				add_btn.disabled = true
			else:
				add_btn.text = "Select"
			if slots_remaining <= 0 and not (current_rank > 0 and current_rank < max_rank):
				add_btn.disabled = true
			add_btn.pressed.connect(_on_add_proficiency.bind(prof_key, slot_type))
		elif _proficiency_registry.is_specialization(prof_key):
			add_btn.text = "Choose"
			if slots_remaining <= 0:
				add_btn.disabled = true
				add_btn.tooltip_text = "No %s slots remaining." % slot_type
			add_btn.pressed.connect(_on_add_proficiency.bind(prof_key, slot_type))
		else:
			var current_rank := _get_current_rank(prof_key, slot_type, "")
			var max_rank := _proficiency_registry.get_max_rank(prof_key)
			if current_rank > 0 and current_rank < max_rank:
				add_btn.text = "Rank %d->%d" % [current_rank, current_rank + 1]
			elif current_rank >= max_rank:
				add_btn.text = "Max Rank" if max_rank > 1 else "Taken"
				add_btn.disabled = true
			else:
				add_btn.text = "Select"
			if slots_remaining <= 0 and not (current_rank > 0 and current_rank < max_rank):
				add_btn.disabled = true
				add_btn.tooltip_text = "No %s slots remaining." % slot_type
			add_btn.pressed.connect(_on_add_proficiency.bind(prof_key, slot_type))

		row.add_child(add_btn)
		_list_container.add_child(HSeparator.new())


func _refresh_pending() -> void:
	for child in _pending_panel.get_children():
		child.queue_free()

	var pending_rows := _get_pending_rows()
	if pending_rows.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No proficiency selections made yet."
		_pending_panel.add_child(empty_lbl)
		return

	for row_data in pending_rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_pending_panel.add_child(row)

		var lbl := Label.new()
		lbl.text = row_data.get("label", "")
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var undo_btn := Button.new()
		undo_btn.text = "Undo"
		undo_btn.pressed.connect(_on_undo_pending.bind(
			row_data.get("proficiency_key", ""),
			row_data.get("slot_type", ""),
			row_data.get("specialization", "")
		))
		row.add_child(undo_btn)


func _get_pending_rows() -> Array:
	var rows: Array = []
	for prof_var in _working_proficiencies:
		var prof: Dictionary = prof_var
		var key: String = prof.get("proficiency_key", "")
		var slot_type: String = prof.get("slot_type", "general")
		var spec: String = prof.get("specialization", "")
		var base := _get_base_record(key, slot_type, spec)
		var base_rank := int(base.get("rank", 0))
		var base_selections := int(base.get("selections_count", base_rank))
		var rank := int(prof.get("rank", 1))
		var selections := int(prof.get("selections_count", rank))
		var spent := selections - base_selections
		if spent <= 0:
			continue

		var label := _format_proficiency_label(key, slot_type, spec)
		if base_rank > 0:
			label += " (Rank %d -> %d)" % [base_rank, rank]
		elif rank > 1:
			label += " (Rank %d)" % rank

		rows.append({
			"label": label,
			"proficiency_key": key,
			"slot_type": slot_type,
			"specialization": spec,
		})
	return rows


func _format_proficiency_label(key: String, slot_type: String, spec: String) -> String:
	var def := _proficiency_registry.get_proficiency(key) if _proficiency_registry.has_proficiency(key) else {}
	var display_name: String = def.get("proficiency_name", key.replace("_", " ").capitalize())
	if not spec.is_empty():
		var spec_display := _proficiency_registry.get_specialization_display_name(key, spec)
		display_name += " (%s)" % spec_display
	var slot_tag := "[C]" if slot_type == "class" else "[G]"
	return "%s %s" % [slot_tag, display_name]


func _remaining_slots(slot_type: String) -> int:
	if slot_type == "class":
		return maxi(0, _class_slots_total - _class_slots_used)
	return maxi(0, _general_slots_total - _general_slots_used)


func _get_current_rank(prof_key: String, _slot_type: String, spec: String) -> int:
	## Returns aggregated rank across ALL slot types for this key + specialization.
	var total := 0
	for prof in _working_proficiencies:
		if prof.get("proficiency_key", "") == prof_key \
				and prof.get("specialization", "") == spec:
			total += int(prof.get("rank", 1))
	return total


func _get_slot_specific_rank(prof_key: String, slot_type: String, spec: String) -> int:
	## Returns rank for this key within a specific slot type only.
	var idx := _find_working_index(prof_key, slot_type, spec)
	if idx < 0:
		return 0
	return int(_working_proficiencies[idx].get("rank", 1))


func _find_working_index(prof_key: String, slot_type: String, spec: String) -> int:
	for i in range(_working_proficiencies.size()):
		var prof: Dictionary = _working_proficiencies[i]
		if prof.get("proficiency_key", "") == prof_key \
				and prof.get("slot_type", "") == slot_type \
				and prof.get("specialization", "") == spec:
			return i
	return -1


func _get_base_record(prof_key: String, slot_type: String, spec: String) -> Dictionary:
	for prof_var in _base_proficiencies:
		var prof: Dictionary = prof_var
		if prof.get("proficiency_key", "") == prof_key \
				and prof.get("slot_type", "") == slot_type \
				and prof.get("specialization", "") == spec:
			return prof
	return {}


func _duplicate_proficiencies(source: Array) -> Array:
	var result: Array = []
	for prof_var in source:
		var prof: Dictionary = prof_var
		result.append(prof.duplicate(true))
	return result


func _recalculate_slot_usage() -> void:
	_class_slots_used = 0
	_general_slots_used = 0
	for prof_var in _working_proficiencies:
		var prof: Dictionary = prof_var
		var key: String = prof.get("proficiency_key", "")
		var slot_type: String = prof.get("slot_type", "general")
		var spec: String = prof.get("specialization", "")
		var base := _get_base_record(key, slot_type, spec)
		var base_selections := int(base.get("selections_count", int(base.get("rank", 0))))
		var selections := int(prof.get("selections_count", int(prof.get("rank", 1))))
		var delta := maxi(0, selections - base_selections)
		if slot_type == "class":
			_class_slots_used += delta
		else:
			_general_slots_used += delta


func _on_tab_changed(_tab: int) -> void:
	_spec_popup_frame.visible = false
	_pending_prof_key = ""
	_pending_slot_type = ""
	_refresh_list()


func _on_add_proficiency(prof_key: String, slot_type: String) -> void:
	_status_label.text = ""

	var embedded_spec := _proficiency_registry.get_specialization_from_compound_key(prof_key)
	if not embedded_spec.is_empty():
		var base_key := _proficiency_registry.resolve_key(prof_key)
		_select_or_advance(base_key, slot_type, embedded_spec)
		return

	if _proficiency_registry.is_specialization(prof_key):
		_show_specialization_selector(prof_key, slot_type)
		return

	if prof_key == "apostasy":
		if _remaining_slots(slot_type) <= 0:
			_status_label.text = "No %s slots remaining." % slot_type
			return
		_show_apostasy_selector(slot_type)
		return

	_select_or_advance(prof_key, slot_type, "")


func _select_or_advance(prof_key: String, slot_type: String, spec: String) -> void:
	var aggregated_rank := _get_current_rank(prof_key, slot_type, spec)
	var max_rank := _proficiency_registry.get_max_rank(prof_key)

	if aggregated_rank >= max_rank and aggregated_rank > 0:
		_status_label.text = "That proficiency is already at its maximum rank."
		return

	if _remaining_slots(slot_type) <= 0:
		_status_label.text = "No %s slots remaining." % slot_type
		return

	# Check if there's an existing row for this specific slot type to advance
	var slot_rank := _get_slot_specific_rank(prof_key, slot_type, spec)
	if slot_rank > 0:
		_advance_rank(prof_key, slot_type, spec)
	else:
		_add_working_record(prof_key, slot_type, spec)


func _show_specialization_selector(prof_key: String, slot_type: String) -> void:
	_pending_prof_key = prof_key
	_pending_slot_type = slot_type

	for child in _spec_popup_container.get_children():
		child.queue_free()

	var def := _proficiency_registry.get_proficiency(prof_key)
	var prof_name: String = def.get("proficiency_name", prof_key)
	var spec_raw = def.get("specializations")

	var lbl := Label.new()
	lbl.text = "Choose %s specialization:" % prof_name
	_spec_popup_container.add_child(lbl)

	if spec_raw is Array and not (spec_raw as Array).is_empty():
		_build_spec_buttons_from_ids(spec_raw as Array, prof_key)
	elif spec_raw == "registry":
		var spec_ids := _proficiency_registry.get_available_specializations(prof_key)
		if spec_ids.is_empty():
			lbl.text = "No specializations available for %s." % prof_name
		else:
			_build_registry_spec_picker(spec_ids, prof_key)
	else:
		lbl.text = "No specializations defined for %s." % prof_name

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func() -> void:
		_spec_popup_frame.visible = false
		_pending_prof_key = ""
		_pending_slot_type = ""
	)
	_spec_popup_container.add_child(cancel_btn)

	_spec_popup_frame.visible = true


func _build_spec_buttons_from_ids(spec_ids: Array, prof_key: String) -> void:
	for spec_var in spec_ids:
		var spec_id := spec_var as String
		var btn := _make_spec_button(prof_key, spec_id)
		_spec_popup_container.add_child(btn)


func _build_registry_spec_picker(spec_ids: Array, prof_key: String) -> void:
	const FILTER_THRESHOLD := 10

	if spec_ids.size() > FILTER_THRESHOLD:
		var filter_edit := LineEdit.new()
		filter_edit.placeholder_text = "Search..."
		filter_edit.custom_minimum_size = Vector2(200, 0)
		_spec_popup_container.add_child(filter_edit)
		filter_edit.text_changed.connect(_on_spec_filter_changed.bind(spec_ids, prof_key))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spec_popup_container.add_child(scroll)

	var button_list := VBoxContainer.new()
	button_list.name = "SpecButtonList"
	button_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(button_list)

	_populate_spec_buttons(button_list, spec_ids, prof_key, "")


func _populate_spec_buttons(container: VBoxContainer, spec_ids: Array,
		prof_key: String, filter: String) -> void:
	for child in container.get_children():
		child.queue_free()

	var filter_lower := filter.to_lower()
	for spec_var in spec_ids:
		var spec_id := spec_var as String
		var display := _proficiency_registry.get_specialization_display_name(prof_key, spec_id)
		if not filter_lower.is_empty() and not display.to_lower().contains(filter_lower):
			continue
		container.add_child(_make_spec_button(prof_key, spec_id))


func _make_spec_button(prof_key: String, spec_id: String) -> Button:
	var display := _proficiency_registry.get_specialization_display_name(prof_key, spec_id)
	var current_rank := _get_current_rank(prof_key, _pending_slot_type, spec_id)
	var max_rank := _proficiency_registry.get_max_rank(prof_key)
	var btn := Button.new()
	if current_rank > 0 and current_rank < max_rank:
		btn.text = "%s (Rank %d->%d)" % [display, current_rank, current_rank + 1]
	elif current_rank >= max_rank and current_rank > 0:
		btn.text = "%s (%s)" % [display, "Max Rank" if max_rank > 1 else "Taken"]
		btn.disabled = true
	else:
		btn.text = display

	if current_rank == 0 and _remaining_slots(_pending_slot_type) <= 0:
		btn.disabled = true

	btn.pressed.connect(_on_specialization_selected.bind(spec_id))
	return btn


func _on_spec_filter_changed(new_text: String, spec_ids: Array, prof_key: String) -> void:
	for child in _spec_popup_container.get_children():
		if child is ScrollContainer:
			var button_list := child.get_node_or_null("SpecButtonList")
			if button_list != null:
				_populate_spec_buttons(button_list as VBoxContainer, spec_ids, prof_key, new_text)
			break


func _on_specialization_selected(spec: String) -> void:
	_spec_popup_frame.visible = false
	_select_or_advance(_pending_prof_key, _pending_slot_type, spec)
	_pending_prof_key = ""
	_pending_slot_type = ""


func _add_working_record(prof_key: String, slot_type: String, spec: String) -> void:
	_working_proficiencies.append({
		"proficiency_key": prof_key,
		"rank": 1,
		"slot_type": slot_type,
		"selections_count": 1,
		"specialization": spec,
	})
	_after_working_state_changed()


func _advance_rank(prof_key: String, slot_type: String, spec: String) -> void:
	var idx := _find_working_index(prof_key, slot_type, spec)
	if idx < 0:
		return
	_working_proficiencies[idx]["rank"] = int(_working_proficiencies[idx].get("rank", 1)) + 1
	_working_proficiencies[idx]["selections_count"] = int(
		_working_proficiencies[idx].get("selections_count", 1)
	) + 1
	_after_working_state_changed()


func get_apostasy_spells() -> Array:
	return _apostasy_spells.duplicate()


func _on_undo_pending(prof_key: String, slot_type: String, spec: String) -> void:
	if prof_key == "apostasy":
		_apostasy_spells = []
		_apostasy_selected_keys.clear()
	var idx := _find_working_index(prof_key, slot_type, spec)
	if idx < 0:
		return

	var base := _get_base_record(prof_key, slot_type, spec)
	if base.is_empty():
		_working_proficiencies.remove_at(idx)
	else:
		_working_proficiencies[idx]["rank"] = int(base.get("rank", 1))
		_working_proficiencies[idx]["selections_count"] = int(base.get("selections_count", base.get("rank", 1)))

	_after_working_state_changed()


func _after_working_state_changed() -> void:
	_recalculate_slot_usage()
	_refresh_all()
	selection_state_changed.emit()


# ---------------------------------------------------------------------------
# Apostasy spell picker
# ---------------------------------------------------------------------------

func _show_apostasy_selector(slot_type: String) -> void:
	_pending_prof_key = "apostasy"
	_pending_slot_type = slot_type
	_apostasy_selected_keys.clear()

	for child in _spec_popup_container.get_children():
		child.queue_free()

	var title_lbl := Label.new()
	title_lbl.name = "ApostasyCountLabel"
	title_lbl.text = "Choose 4 Apostasy Spells (0 / 4 selected)"
	title_lbl.add_theme_font_size_override("font_size", 13)
	_spec_popup_container.add_child(title_lbl)

	var note_lbl := Label.new()
	note_lbl.text = "Reversible spells include both forms automatically."
	note_lbl.add_theme_font_size_override("font_size", 11)
	note_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spec_popup_container.add_child(note_lbl)

	var filter_edit := LineEdit.new()
	filter_edit.placeholder_text = "Search spells..."
	filter_edit.text_changed.connect(func(text: String) -> void: _on_apostasy_filter_changed(text))
	_spec_popup_container.add_child(filter_edit)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spec_popup_container.add_child(scroll)

	var spell_list := VBoxContainer.new()
	spell_list.name = "ApostasySpellList"
	spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(spell_list)

	var spell_reg := SpellRegistry.new()
	var spells_by_level := spell_reg.get_divine_spells_not_on_class_list(_class_id, _class_registry)
	_populate_apostasy_spell_list(spell_list, spells_by_level, spell_reg, "")

	var confirm_btn := Button.new()
	confirm_btn.name = "ApostasyConfirmBtn"
	confirm_btn.text = "Confirm (0 / 4)"
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(_on_apostasy_confirmed)
	_spec_popup_container.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func() -> void: _spec_popup_frame.visible = false)
	_spec_popup_container.add_child(cancel_btn)

	_spec_popup_frame.visible = true


func _populate_apostasy_spell_list(container: VBoxContainer, spells_by_level: Dictionary,
		spell_reg: SpellRegistry, filter: String) -> void:
	for child in container.get_children():
		child.queue_free()

	var filter_lower := filter.to_lower()
	var levels: Array = spells_by_level.keys()
	levels.sort()

	for level in levels:
		var level_spells: Array = spells_by_level[level]
		var header := Label.new()
		header.text = "— Level %d —" % level
		header.add_theme_font_size_override("font_size", 12)
		container.add_child(header)
		var any_visible := false

		for spell_key in level_spells:
			var entry := spell_reg.get_spell(spell_key as String)
			var spell_name: String = entry.get("spell_name",
				(spell_key as String).replace("_", " ").capitalize())
			if not filter_lower.is_empty() and not spell_name.to_lower().contains(filter_lower):
				continue
			any_visible = true

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			container.add_child(row)

			var check := CheckButton.new()
			check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			check.text = spell_name
			if entry.get("is_reversible", false):
				check.text += " (+ reversed form)"
			check.set_pressed_no_signal(_apostasy_selected_keys.has(spell_key as String))
			check.toggled.connect(func(on: bool) -> void:
				_on_apostasy_spell_toggled(check, spell_key as String, on))
			row.add_child(check)

		header.visible = any_visible


func _on_apostasy_spell_toggled(check: CheckButton, spell_key: String, is_on: bool) -> void:
	if is_on:
		if _apostasy_selected_keys.size() >= 4:
			check.set_pressed_no_signal(false)
			return
		_apostasy_selected_keys[spell_key] = true
	else:
		_apostasy_selected_keys.erase(spell_key)
	_update_apostasy_ui()


func _on_apostasy_filter_changed(new_text: String) -> void:
	var spell_list := _spec_popup_container.get_node_or_null("ApostasySpellList") as VBoxContainer
	if spell_list == null:
		return
	var spell_reg := SpellRegistry.new()
	var spells_by_level := spell_reg.get_divine_spells_not_on_class_list(_class_id, _class_registry)
	_populate_apostasy_spell_list(spell_list, spells_by_level, spell_reg, new_text)


func _update_apostasy_ui() -> void:
	var count := _apostasy_selected_keys.size()
	var title_lbl := _spec_popup_container.get_node_or_null("ApostasyCountLabel") as Label
	if title_lbl != null:
		title_lbl.text = "Choose 4 Apostasy Spells (%d / 4 selected)" % count
	var confirm_btn := _spec_popup_container.get_node_or_null("ApostasyConfirmBtn") as Button
	if confirm_btn != null:
		confirm_btn.text = "Confirm (%d / 4)" % count
		confirm_btn.disabled = count != 4


func _on_apostasy_confirmed() -> void:
	_spec_popup_frame.visible = false
	var spell_reg := SpellRegistry.new()
	var spell_dicts: Array = []
	for spell_key in _apostasy_selected_keys.keys():
		var key_str := spell_key as String
		if not spell_reg.has_spell(key_str):
			continue
		var entry := spell_reg.get_spell(key_str)
		var spell_level := _get_divine_spell_level(entry)
		spell_dicts.append({
			"spell_key": key_str,
			"spell_level": spell_level,
			"is_in_repertoire": true,
			"is_memorized": false,
			"memorized_slots": 0,
		})
		if spell_reg.is_reversible(key_str):
			var rev_key := spell_reg.get_reverse_key(key_str)
			if not rev_key.is_empty() and spell_reg.has_spell(rev_key):
				spell_dicts.append({
					"spell_key": rev_key,
					"spell_level": spell_level,
					"is_in_repertoire": true,
					"is_memorized": false,
					"memorized_slots": 0,
				})
	_apostasy_selected_keys.clear()
	_apostasy_spells = spell_dicts
	_add_working_record("apostasy", _pending_slot_type, "")
	_pending_prof_key = ""
	_pending_slot_type = ""


func _get_divine_spell_level(entry: Dictionary) -> int:
	for classification in entry.get("classifications", []):
		if classification.get("tradition", "") == "divine":
			return int(classification.get("level", 1))
	return 1
