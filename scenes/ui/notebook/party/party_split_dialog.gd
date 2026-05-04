extends CanvasLayer

## PartySplitDialog — extracted from PartyManagementOverlay during γ.3 so the
## Party tab can host the same split flow without bringing the deleted
## overlay forward. Self-contained CanvasLayer at layer 50; emits
## `split_completed(new_party_id)` so the caller can refresh.
##
## Construction:
##   var dialog := PartySplitDialog.new(party_data)
##   parent.add_child(dialog)
##   dialog.split_completed.connect(_on_split_done)
##
## The dialog frees itself on Cancel or successful Create.


signal split_completed(new_party_id: String)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _party: PartyData = null
var _checkboxes: Array = []           # CharacterData CheckBox entries
var _creature_checkboxes: Array = []
var _vehicle_checkboxes: Array = []
var _name_edit: LineEdit = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _init(party: PartyData) -> void:
	_party = party
	layer = 50


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.25
	panel.anchor_top = 0.15
	panel.anchor_right = 0.75
	panel.anchor_bottom = 0.85
	UiSurfaceStyles.apply_framed_window_chrome(panel)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	var title_lbl := Label.new()
	title_lbl.text = "Split Party"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_row.add_child(title_lbl)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var inst_lbl := Label.new()
	inst_lbl.text = "Select characters to move to the new party:"
	inst_lbl.add_theme_font_size_override("font_size", 11)
	inst_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(inst_lbl)

	var check_scroll := ScrollContainer.new()
	check_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(check_scroll)

	var check_vbox := VBoxContainer.new()
	check_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_scroll.add_child(check_vbox)

	for cd: CharacterData in _party.character_data:
		var cb := CheckBox.new()
		cb.text = "%s (L%d %s)" % [cd.name, cd.level, cd.character_class.capitalize()]
		cb.set_meta("character_id", cd.id)
		check_vbox.add_child(cb)
		_checkboxes.append(cb)

	if not _party.creature_data.is_empty():
		check_vbox.add_child(HSeparator.new())
		var creature_header := Label.new()
		creature_header.text = "Creatures:"
		creature_header.add_theme_font_size_override("font_size", 11)
		check_vbox.add_child(creature_header)
		for creature: TrainedCreatureData in _party.creature_data:
			var cb := CheckBox.new()
			var display_name: String = creature.name if not creature.name.is_empty() else creature.species_id.capitalize()
			var handler_text := ""
			if not creature.handler_id.is_empty():
				var handler_char := CampaignRepository.get_character(creature.handler_id)
				handler_text = " (handler: %s)" % str(handler_char.get("name", "unknown"))
			cb.text = "%s%s" % [display_name, handler_text]
			cb.set_meta("creature_id", creature.id)
			cb.set_meta("handler_id", creature.handler_id)
			check_vbox.add_child(cb)
			_creature_checkboxes.append(cb)

	if not _party.vehicle_data.is_empty():
		check_vbox.add_child(HSeparator.new())
		var vehicle_header := Label.new()
		vehicle_header.text = "Vehicles:"
		vehicle_header.add_theme_font_size_override("font_size", 11)
		check_vbox.add_child(vehicle_header)
		for v: Dictionary in _party.vehicle_data:
			var cb := CheckBox.new()
			var vname: String = str(v.get("name", ""))
			if vname.is_empty():
				vname = str(v.get("item_key", "vehicle")).capitalize()
			var hitch_text := ""
			var h_json: String = str(v.get("hitched_creatures", "[]"))
			var h_ids: Variant = JSON.parse_string(h_json)
			if h_ids is Array and not h_ids.is_empty():
				hitch_text = " (hitched: %d creature%s)" % [h_ids.size(), "" if h_ids.size() == 1 else "s"]
			cb.text = "%s%s" % [vname, hitch_text]
			cb.set_meta("vehicle_id", str(v.get("id", "")))
			check_vbox.add_child(cb)
			_vehicle_checkboxes.append(cb)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	vbox.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "New party name:"
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_row.add_child(name_lbl)
	_name_edit = LineEdit.new()
	_name_edit.text = "%s (Detachment)" % _party.name
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)

	var warn_lbl := Label.new()
	warn_lbl.text = "At least 1 character must remain in the original party."
	warn_lbl.add_theme_font_size_override("font_size", 9)
	warn_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
	vbox.add_child(warn_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_close)
	btn_row.add_child(cancel_btn)

	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.pressed.connect(_on_confirm)
	btn_row.add_child(create_btn)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _close() -> void:
	queue_free()


func _on_confirm() -> void:
	var selected_ids: Array = []
	for cb: CheckBox in _checkboxes:
		if cb.button_pressed:
			selected_ids.append(cb.get_meta("character_id"))

	if selected_ids.is_empty():
		_warn("No Characters Selected", "The new party must have at least one character.")
		return

	if selected_ids.size() >= _party.character_data.size():
		_warn("Cannot Empty Party", "At least 1 character must remain in the original party.")
		return

	var selected_creature_ids: Array = []
	for cb: CheckBox in _creature_checkboxes:
		if cb.button_pressed:
			selected_creature_ids.append(cb.get_meta("creature_id"))

	var selected_vehicle_ids: Array = []
	for cb: CheckBox in _vehicle_checkboxes:
		if cb.button_pressed:
			selected_vehicle_ids.append(cb.get_meta("vehicle_id"))

	var handler_reassignments := {}
	var handler_warnings: Array = []
	for creature: TrainedCreatureData in _party.creature_data:
		if creature.handler_id.is_empty():
			continue
		var creature_moving: bool = selected_creature_ids.has(creature.id)
		var handler_moving: bool = selected_ids.has(creature.handler_id)
		if creature_moving != handler_moving:
			handler_reassignments[creature.id] = ""
			var cname: String = creature.name if not creature.name.is_empty() else creature.species_id.capitalize()
			handler_warnings.append(cname)

	var split_context := {}
	if not handler_reassignments.is_empty():
		split_context["handler_reassignments"] = handler_reassignments

	var new_name: String = _name_edit.text.strip_edges()
	if new_name.is_empty():
		new_name = "%s (Detachment)" % _party.name

	var new_id := CampaignRepository.split_party(
		_party.id, new_name, selected_ids,
		selected_creature_ids, selected_vehicle_ids, split_context)
	if new_id.is_empty():
		EventBus.notification_requested.emit({
			"type": "danger",
			"category": "system",
			"title": "Split Failed",
			"body": "Could not split the party. Check the error log.",
		})
		return

	var parts: Array = []
	parts.append("%d character%s" % [selected_ids.size(),
		"" if selected_ids.size() == 1 else "s"])
	if not selected_creature_ids.is_empty():
		parts.append("%d creature%s" % [selected_creature_ids.size(),
			"" if selected_creature_ids.size() == 1 else "s"])
	if not selected_vehicle_ids.is_empty():
		parts.append("%d vehicle%s" % [selected_vehicle_ids.size(),
			"" if selected_vehicle_ids.size() == 1 else "s"])
	var body_text := "%s created with %s." % [new_name, ", ".join(parts)]
	if not handler_warnings.is_empty():
		body_text += " Handler cleared for: %s." % ", ".join(handler_warnings)
	EventBus.notification_requested.emit({
		"type": "success",
		"category": "system",
		"title": "Party Split",
		"body": body_text,
	})
	split_completed.emit(new_id)
	queue_free()


func _warn(title: String, body: String) -> void:
	EventBus.notification_requested.emit({
		"type": "warning",
		"category": "system",
		"title": title,
		"body": body,
	})
