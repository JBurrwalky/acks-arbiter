class_name SaveLoadPanel
extends CanvasLayer

## Player-facing Save / Load screen (Phase S-3, gdd-savegame-system.md §6.5).
##
## One unified panel — the GM/Player snapshot distinction is retired. Lists the
## campaign's named slots (whole-DB file snapshots), lets the player save a new
## slot, load a slot (restore + re-enter the session at the saved context), or
## delete one. Built programmatically per coding_conventions §13.2. Instantiated
## by the pause menu, which passes the SessionRunner via setup().

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)

var _runner = null
var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _list_vbox: VBoxContainer = null
var _name_edit: LineEdit = null


func setup(runner) -> void:
	_runner = runner


func _ready() -> void:
	layer = 170  # above the pause menu (160)
	_build_ui()
	_refresh_list()


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(520, 500)
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = -250
	_panel.offset_bottom = 250
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Save / Load"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HEADING_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# New-save row: name field + Save button.
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Save name"
	_name_edit.text = _default_save_name()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_edit)
	var save_btn := Button.new()
	save_btn.text = "Save New Slot"
	save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(save_btn)
	vbox.add_child(save_row)

	vbox.add_child(HSeparator.new())

	# Slot list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	vbox.add_child(scroll)
	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_vbox)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close)
	vbox.add_child(close_btn)


func _default_save_name() -> String:
	return "Save %s" % Time.get_datetime_string_from_system(false, true)


func _refresh_list() -> void:
	if _list_vbox == null:
		return
	for c in _list_vbox.get_children():
		c.queue_free()
	var campaign_id: String = GameState.campaign_id
	if campaign_id.is_empty():
		var none := Label.new()
		none.text = "(no active campaign)"
		none.add_theme_color_override("font_color", LABEL_COLOR)
		_list_vbox.add_child(none)
		return
	var slots: Array = CampaignRepository.list_snapshots(campaign_id)
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "(no saved slots yet)"
		empty.add_theme_color_override("font_color", LABEL_COLOR)
		_list_vbox.add_child(empty)
		return
	for s: Dictionary in slots:
		_list_vbox.add_child(_make_slot_row(s))


func _make_slot_row(slot: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := Label.new()
	var loc: String = String(slot.get("location_label", ""))
	var when: String = String(slot.get("created_at", ""))
	var suffix: String = ""
	if not loc.is_empty():
		suffix += "  —  %s" % loc
	if not when.is_empty():
		suffix += "  (%s)" % when
	info.text = "%s%s" % [String(slot.get("label", "Unnamed")), suffix]
	info.add_theme_color_override("font_color", LABEL_COLOR)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(info)

	var sid: String = String(slot.get("id", ""))
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load_pressed.bind(sid))
	row.add_child(load_btn)
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.pressed.connect(_on_delete_pressed.bind(sid))
	row.add_child(del_btn)
	return row


func _on_save_pressed() -> void:
	if _runner == null or not _runner.has_method("save_to_slot"):
		return
	var label: String = _name_edit.text.strip_edges()
	if label.is_empty():
		label = _default_save_name()
	var sid: String = _runner.save_to_slot(label)
	if sid.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning", "category": "system",
			"title": "Save Failed", "duration": 3.0,
		})
		return
	EventBus.notification_requested.emit({
		"type": "success", "category": "system",
		"title": "Saved: %s" % label, "duration": 3.0,
	})
	_name_edit.text = _default_save_name()
	_refresh_list()


func _on_load_pressed(snapshot_id: String) -> void:
	if _runner == null or not _runner.has_method("load_slot"):
		return
	# Loading tears down the current session and re-enters from scratch — close
	# this panel and unpause first so the reloaded session is interactive.
	_close()
	GameState.resume()
	EventBus.scheduler_resumed.emit()
	if not _runner.load_slot(snapshot_id):
		EventBus.notification_requested.emit({
			"type": "error", "category": "system",
			"title": "Load Failed", "duration": 4.0,
		})


func _on_delete_pressed(snapshot_id: String) -> void:
	CampaignRepository.delete_snapshot(snapshot_id)
	_refresh_list()


func _close() -> void:
	queue_free()
