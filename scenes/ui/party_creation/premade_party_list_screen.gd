extends CanvasLayer

## Premade Party List Screen — shows available premade parties for selection.
##
## Loads party metadata from the manifest file and displays clickable rows.
## Emits party_selected when the player clicks a party, back_pressed for navigation.
##
## No class_name — UI scripts do not export class names per coding conventions.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal party_selected(party_id: String)
signal back_pressed


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MANIFEST_PATH := "res://data/premade_parties/manifest.json"

const ROW_BG_COLOR := Color(0.94, 0.89, 0.78, 0.42)
const ROW_BG_HOVER_COLOR := Color(0.82, 0.72, 0.55, 0.65)
const ROW_BORDER_COLOR := Color(0.44, 0.31, 0.18, 0.88)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _parties: Array = []  # Array of { id, file, name, description }


# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _list_container: VBoxContainer


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	hide()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open() -> void:
	_load_manifest()
	if _list_container == null:
		_build_ui()
	else:
		_rebuild_list()
	show()


func close() -> void:
	hide()


# ---------------------------------------------------------------------------
# ManagedScene interface (duck-typed)
# ---------------------------------------------------------------------------

func enter(_params: Dictionary = {}) -> void:
	pass


func exit() -> void:
	close()


func save_state() -> Dictionary:
	return {}


func restore_state(_data: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

func _load_manifest() -> void:
	_parties = []
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("PremadePartyListScreen: manifest not found at %s" % MANIFEST_PATH)
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("PremadePartyListScreen: failed to parse manifest JSON")
		return
	var data: Dictionary = json.data
	_parties = data.get("parties", [])


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	UiSurfaceStyles.apply_vellum_text_theme(root)

	# Full-screen vellum background
	var bg := UiSurfaceStyles.make_background_rect()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Centered panel (500 wide x 400 tall)
	var panel_frame := PanelContainer.new()
	panel_frame.anchor_left = 0.5
	panel_frame.anchor_top = 0.5
	panel_frame.anchor_right = 0.5
	panel_frame.anchor_bottom = 0.5
	panel_frame.offset_left = -250.0
	panel_frame.offset_top = -200.0
	panel_frame.offset_right = 250.0
	panel_frame.offset_bottom = 200.0
	panel_frame.add_theme_stylebox_override("panel", UiSurfaceStyles.make_filled_frame_style())
	root.add_child(panel_frame)

	var frame_margin := MarginContainer.new()
	frame_margin.add_theme_constant_override("margin_left", 8)
	frame_margin.add_theme_constant_override("margin_right", 8)
	frame_margin.add_theme_constant_override("margin_top", 8)
	frame_margin.add_theme_constant_override("margin_bottom", 8)
	panel_frame.add_child(frame_margin)

	var panel_inner := PanelContainer.new()
	panel_inner.add_theme_stylebox_override("panel", UiSurfaceStyles.make_vellum_style())
	frame_margin.add_child(panel_inner)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 24)
	panel_margin.add_theme_constant_override("margin_right", 24)
	panel_margin.add_theme_constant_override("margin_top", 24)
	panel_margin.add_theme_constant_override("margin_bottom", 24)
	panel_inner.add_child(panel_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel_margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Select a Premade Party"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# List area
	var list_frame := PanelContainer.new()
	list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_frame.add_theme_stylebox_override("panel", _make_list_inset_style())
	vbox.add_child(list_frame)

	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 4)
	list_margin.add_theme_constant_override("margin_right", 4)
	list_margin.add_theme_constant_override("margin_top", 4)
	list_margin.add_theme_constant_override("margin_bottom", 4)
	list_frame.add_child(list_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_margin.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_container)

	_rebuild_list()

	vbox.add_child(HSeparator.new())

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var back_btn := Button.new()
	back_btn.text = "Go Back"
	back_btn.custom_minimum_size = Vector2(140, 36)
	back_btn.pressed.connect(func(): back_pressed.emit())
	btn_row.add_child(back_btn)


# ---------------------------------------------------------------------------
# List rendering
# ---------------------------------------------------------------------------

func _rebuild_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	if _parties.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No premade parties available."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 14)
		_list_container.add_child(empty_label)
		return

	for party_entry in _parties:
		var row := _make_party_row(party_entry)
		_list_container.add_child(row)


func _make_party_row(entry: Dictionary) -> PanelContainer:
	var pid: String = entry.get("id", "")
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _make_row_style())
	row_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	row_panel.gui_input.connect(_on_row_input.bind(pid))
	row_panel.mouse_entered.connect(func():
		row_panel.add_theme_stylebox_override("panel", _make_row_hover_style())
	)
	row_panel.mouse_exited.connect(func():
		row_panel.add_theme_stylebox_override("panel", _make_row_style())
	)

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 12)
	row_margin.add_theme_constant_override("margin_right", 12)
	row_margin.add_theme_constant_override("margin_top", 10)
	row_margin.add_theme_constant_override("margin_bottom", 10)
	row_panel.add_child(row_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_margin.add_child(vbox)

	var name_label := Label.new()
	name_label.text = entry.get("name", "(unnamed)")
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = entry.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	return row_panel


func _on_row_input(event: InputEvent, pid: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		party_selected.emit(pid)


# ---------------------------------------------------------------------------
# Styles
# ---------------------------------------------------------------------------

func _make_list_inset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.92, 0.82, 0.28)
	style.border_color = Color(0.44, 0.31, 0.18, 0.88)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style


func _make_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG_COLOR
	style.border_color = ROW_BORDER_COLOR
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	return style


func _make_row_hover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG_HOVER_COLOR
	style.border_color = ROW_BORDER_COLOR
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	return style
