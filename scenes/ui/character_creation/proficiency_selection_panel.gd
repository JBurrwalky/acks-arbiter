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
var _spec_popup_frame: PanelContainer
var _spec_popup_container: VBoxContainer  # holds spec selector when needed

# Pending state for specialization selection
var _pending_prof_key: String = ""
var _pending_slot_type: String = ""

# Apostasy spell picker tracking (temp state during picker session)
var _apostasy_selected_keys: Dictionary = {}  # spell_key -> true


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
		var selections: int = int(p.get("selections_count", 1))
		if slot_type == "class":
			_class_slots_used += selections
		elif slot_type == "general" and p.get("proficiency_key", "") != "adventuring":
			_general_slots_used += selections


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
		_slot_label.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
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
		# Compound keys (e.g., "knowledge_history") show the locked specialization in the name.
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
			desc_lbl.text = desc + ("…" if desc.length() >= 80 else "")
			desc_lbl.add_theme_font_size_override("font_size", 11)
			desc_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info_vbox.add_child(desc_lbl)

		# Rank indicator (if already selected)
		var current_rank := _get_current_rank(prof_key, slot_type)
		var max_rank := _proficiency_registry.get_max_rank(prof_key)
		var sel_rule := _proficiency_registry.get_selection_rule(prof_key)

		var add_btn := Button.new()
		add_btn.custom_minimum_size = Vector2(70, 0)

		if sel_rule == "stacking":
			var max_sel := _proficiency_registry.get_max_selections(prof_key)
			if current_rank >= max_sel:
				add_btn.text = "Max Rank"
				add_btn.disabled = true
			elif current_rank > 0:
				add_btn.text = "Rank %d→%d" % [current_rank, current_rank + 1]
			else:
				add_btn.text = "Select"
		elif current_rank > 0 and current_rank < max_rank:
			add_btn.text = "Rank %d→%d" % [current_rank, current_rank + 1]
		elif current_rank >= max_rank and max_rank > 1:
			add_btn.text = "Max Rank"
			add_btn.disabled = true
		elif current_rank > 0 and max_rank == 1 and not _proficiency_registry.is_specialization(prof_key):
			add_btn.text = "Taken"
			add_btn.disabled = true
		else:
			add_btn.text = "Select"

		var at_limit: bool
		if sel_rule == "stacking":
			at_limit = current_rank >= _proficiency_registry.get_max_selections(prof_key)
		else:
			at_limit = current_rank >= max_rank
		if slots_remaining <= 0 and (current_rank == 0 or at_limit):
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

	# Show bonus proficiencies (origin/tradition grants) — non-removable
	for bp in _state.get("bonus_proficiencies", []):
		var key: String = bp.get("proficiency_key", "")
		var spec: String = bp.get("specialization", "")
		var rank: int = int(bp.get("rank", 1))
		var row := _make_selected_row(key, "bonus", rank, spec, false)
		_selected_panel.add_child(row)

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
		var spec_display := _proficiency_registry.get_specialization_display_name(key, spec)
		display_name += " (%s)" % spec_display
	if rank > 1:
		display_name += " (Rank %d)" % rank
	var slot_tag: String
	match slot_type:
		"class": slot_tag = "[C]"
		"general": slot_tag = "[G]"
		"bonus": slot_tag = "[FREE]"
		_: slot_tag = "[?]"

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

func _get_current_rank(prof_key: String, _slot_type: String) -> int:
	## Returns aggregated rank across ALL slot types for this proficiency key,
	## including any bonus proficiencies granted by origin/tradition.
	var total := 0
	for p in _state.get("proficiencies", []):
		if p.get("proficiency_key", "") == prof_key:
			total += int(p.get("rank", 1))
	for bp in _state.get("bonus_proficiencies", []):
		if bp.get("proficiency_key", "") == prof_key:
			total += int(bp.get("rank", 1))
	return total


func _get_slot_specific_rank(prof_key: String, slot_type: String) -> int:
	## Returns rank for this proficiency key within a specific slot type only.
	for p in _state.get("proficiencies", []):
		if p.get("proficiency_key", "") == prof_key and p.get("slot_type", "") == slot_type:
			return int(p.get("rank", 1))
	return 0


func _on_tab_changed(_tab: int) -> void:
	_spec_popup_frame.visible = false
	_pending_prof_key = ""
	_refresh_list()


func _on_add_proficiency(prof_key: String, slot_type: String) -> void:
	_status_label.text = ""

	# Compound key check: e.g., "knowledge_history" on Cleric class list.
	# Auto-lock specialization — no picker shown.
	var embedded_spec := _proficiency_registry.get_specialization_from_compound_key(prof_key)
	if not embedded_spec.is_empty():
		var base_key := _proficiency_registry.resolve_key(prof_key)
		var aggregated_rank := _get_current_rank(base_key, slot_type)
		var max_rank := _proficiency_registry.get_max_rank(base_key)
		if aggregated_rank >= max_rank:
			return  # Already at max across all slots
		var slot_rank := _get_slot_specific_rank(base_key, slot_type)
		if slot_rank > 0:
			_advance_rank(base_key, slot_type)
			return
		if not _can_add_slot(slot_type):
			_status_label.text = "No %s slots remaining." % slot_type
			return
		_add_proficiency_record(base_key, slot_type, 1, embedded_spec)
		return

	if _proficiency_registry.is_specialization(prof_key):
		_show_specialization_selector(prof_key, slot_type)
		return

	if prof_key == "apostasy":
		if not _can_add_slot(slot_type):
			_status_label.text = "No %s slots remaining." % slot_type
			return
		_show_apostasy_selector(slot_type)
		return

	# Check aggregated rank across all slot types
	var aggregated_rank := _get_current_rank(prof_key, slot_type)
	var sel_rule := _proficiency_registry.get_selection_rule(prof_key)

	if sel_rule == "stacking":
		var max_sel := _proficiency_registry.get_max_selections(prof_key)
		if aggregated_rank >= max_sel:
			return  # At max selections for stacking proficiency
	else:
		var max_rank := _proficiency_registry.get_max_rank(prof_key)
		if aggregated_rank >= max_rank:
			return  # Already at max rank

	# Check if there's an existing row for this specific slot type to advance
	var slot_rank := _get_slot_specific_rank(prof_key, slot_type)
	if slot_rank > 0:
		_advance_rank(prof_key, slot_type)
		return

	# New selection for this slot type (may be first pick, or prof exists on other slot)
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
	var prof_name: String = def.get("proficiency_name", prof_key)
	var spec_raw = def.get("specializations")

	var lbl := Label.new()
	lbl.text = "Choose %s specialization:" % prof_name
	_spec_popup_container.add_child(lbl)

	if spec_raw is Array and not (spec_raw as Array).is_empty():
		# Branch A: Closed-list (Combat Trickery, Fighting Style, Elementalism, etc.)
		_build_spec_buttons_from_ids(spec_raw as Array, prof_key)
	elif spec_raw == "registry":
		# Branch B: Registry-backed picker (Riding, Animal Training, Knowledge, Craft, etc.)
		var spec_ids := _proficiency_registry.get_available_specializations(prof_key)
		if spec_ids.is_empty():
			lbl.text = "No specializations available for %s." % prof_name
		else:
			_build_registry_spec_picker(spec_ids, prof_key)
	else:
		lbl.text = "No specializations defined for %s." % prof_name

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): _spec_popup_frame.visible = false)
	_spec_popup_container.add_child(cancel_btn)

	_spec_popup_frame.visible = true


func _build_spec_buttons_from_ids(spec_ids: Array, prof_key: String) -> void:
	## Builds one button per specialization for closed-list proficiencies.
	for spec in spec_ids:
		var display := _proficiency_registry.get_specialization_display_name(prof_key, spec as String)
		var btn := Button.new()
		btn.text = display
		btn.pressed.connect(_on_specialization_selected.bind(spec as String))
		_spec_popup_container.add_child(btn)


func _build_registry_spec_picker(spec_ids: Array, prof_key: String) -> void:
	## Builds a scrollable list with optional search filter for registry-backed proficiencies.
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
	for spec_id in spec_ids:
		var display := _proficiency_registry.get_specialization_display_name(prof_key, spec_id as String)
		if not filter_lower.is_empty() and not display.to_lower().contains(filter_lower):
			continue
		var btn := Button.new()
		btn.text = display
		btn.pressed.connect(_on_specialization_selected.bind(spec_id as String))
		container.add_child(btn)


func _on_spec_filter_changed(new_text: String, spec_ids: Array, prof_key: String) -> void:
	for child in _spec_popup_container.get_children():
		if child is ScrollContainer:
			var button_list := child.get_node_or_null("SpecButtonList")
			if button_list:
				_populate_spec_buttons(button_list as VBoxContainer, spec_ids, prof_key, new_text)
			break


func _on_specialization_selected(spec: String) -> void:
	_spec_popup_frame.visible = false
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
			var removed_selections: int = int(p.get("selections_count", 1))
			profs.remove_at(i)
			# Return slots for each selection that consumed a slot
			for _r in range(removed_selections):
				if slot_type == "class":
					_class_slots_used = maxi(0, _class_slots_used - 1)
				elif key != "adventuring":
					_general_slots_used = maxi(0, _general_slots_used - 1)
			break
	_state["proficiencies"] = profs
	if key == "apostasy":
		_apostasy_selected_keys.clear()
		_state.erase("apostasy_spells")
	_refresh_all()


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
	var class_id: String = _state.get("class_id", "")
	var spells_by_level := spell_reg.get_divine_spells_not_on_class_list(class_id, _class_registry)
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
	var class_id: String = _state.get("class_id", "")
	var spells_by_level := spell_reg.get_divine_spells_not_on_class_list(class_id, _class_registry)
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
	_state["apostasy_spells"] = spell_dicts
	_add_proficiency_record("apostasy", _pending_slot_type, 1, "")
	_pending_prof_key = ""
	_pending_slot_type = ""


func _get_divine_spell_level(entry: Dictionary) -> int:
	for classification in entry.get("classifications", []):
		if classification.get("tradition", "") == "divine":
			return int(classification.get("level", 1))
	return 1
