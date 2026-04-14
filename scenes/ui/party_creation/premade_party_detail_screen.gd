extends CanvasLayer

## Premade Party Detail Screen — shows the characters in a selected premade party.
##
## Displays a read-only roster view with portraits, names, classes, and ability
## scores. Provides Confirm / Go Back buttons.
##
## No class_name — UI scripts do not export class names per coding conventions.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PORTRAIT_SIZE := Vector2(64, 64)
const ROW_BG_COLOR := Color(0.94, 0.89, 0.78, 0.42)
const ROW_BORDER_COLOR := Color(0.44, 0.31, 0.18, 0.88)

const ABILITY_KEYS: Array[String] = ["STR", "INT", "WIS", "DEX", "CON", "CHA"]
const ABILITY_FIELDS: Array[String] = [
	"strength", "intelligence", "wisdom", "dexterity", "constitution", "charisma"
]


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal confirm_pressed
signal back_pressed


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _party_data: Dictionary = {}


# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _title_label: Label
var _counter_label: Label
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

func open(party_data: Dictionary) -> void:
	_party_data = party_data
	if _title_label == null:
		_build_ui()
	_title_label.text = party_data.get("party_name", "Premade Party")
	var chars: Array = party_data.get("characters", [])
	_counter_label.text = "Party Members: %d/6" % chars.size()
	_rebuild_roster(chars)
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

	# Centered panel (700 wide x 520 tall — matches PartyRosterScreen)
	var panel_frame := PanelContainer.new()
	panel_frame.anchor_left = 0.5
	panel_frame.anchor_top = 0.5
	panel_frame.anchor_right = 0.5
	panel_frame.anchor_bottom = 0.5
	panel_frame.offset_left = -350.0
	panel_frame.offset_top = -260.0
	panel_frame.offset_right = 350.0
	panel_frame.offset_bottom = 260.0
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
	panel_margin.add_theme_constant_override("margin_left", 18)
	panel_margin.add_theme_constant_override("margin_right", 18)
	panel_margin.add_theme_constant_override("margin_top", 18)
	panel_margin.add_theme_constant_override("margin_bottom", 18)
	panel_inner.add_child(panel_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel_margin.add_child(vbox)

	# --- Header row ---
	var header := HBoxContainer.new()
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Premade Party"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_counter_label = Label.new()
	_counter_label.text = "Party Members: 0/6"
	_counter_label.add_theme_font_size_override("font_size", 16)
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_counter_label)

	vbox.add_child(HSeparator.new())

	# --- Character list area ---
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
	_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_container)

	vbox.add_child(HSeparator.new())

	# --- Button row ---
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm Selection"
	confirm_btn.custom_minimum_size = Vector2(160, 36)
	confirm_btn.pressed.connect(func(): confirm_pressed.emit())
	btn_row.add_child(confirm_btn)

	var back_btn := Button.new()
	back_btn.text = "Go Back"
	back_btn.custom_minimum_size = Vector2(140, 36)
	back_btn.pressed.connect(func(): back_pressed.emit())
	btn_row.add_child(back_btn)


# ---------------------------------------------------------------------------
# Roster rendering
# ---------------------------------------------------------------------------

func _rebuild_roster(chars: Array) -> void:
	for child in _list_container.get_children():
		child.queue_free()

	if chars.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No characters in this party."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 14)
		_list_container.add_child(empty_label)
		return

	for entry in chars:
		var c: Dictionary = entry.get("character", {})
		var row := _make_character_row(c)
		_list_container.add_child(row)


func _make_character_row(c: Dictionary) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _make_row_style())
	row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 8)
	row_margin.add_theme_constant_override("margin_right", 8)
	row_margin.add_theme_constant_override("margin_top", 6)
	row_margin.add_theme_constant_override("margin_bottom", 6)
	row_panel.add_child(row_margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_margin.add_child(hbox)

	# Portrait thumbnail (64x64)
	var portrait_rect := TextureRect.new()
	portrait_rect.custom_minimum_size = PORTRAIT_SIZE
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_id: String = c.get("portrait_id", "")
	if not portrait_id.is_empty():
		var tex := _load_portrait(portrait_id)
		if tex != null:
			portrait_rect.texture = tex
	hbox.add_child(portrait_rect)

	# Info column: name + class
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = c.get("name", "(unnamed)")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(name_label)

	var class_label := Label.new()
	var char_class: String = c.get("character_class", "")
	var level: int = c.get("level", 1)
	class_label.text = "Lvl %d %s" % [level, char_class.capitalize()]
	class_label.add_theme_font_size_override("font_size", 13)
	class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(class_label)

	# Attributes
	var attr_hbox := HBoxContainer.new()
	attr_hbox.add_theme_constant_override("separation", 8)
	attr_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(attr_hbox)

	for i in ABILITY_KEYS.size():
		var attr_vbox := VBoxContainer.new()
		attr_vbox.add_theme_constant_override("separation", 0)
		attr_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		attr_hbox.add_child(attr_vbox)

		var key_lbl := Label.new()
		key_lbl.text = ABILITY_KEYS[i]
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		attr_vbox.add_child(key_lbl)

		var val_lbl := Label.new()
		val_lbl.text = str(c.get(ABILITY_FIELDS[i], 0))
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		attr_vbox.add_child(val_lbl)

	return row_panel


# ---------------------------------------------------------------------------
# Portrait loading (same pattern as party_roster_screen.gd)
# ---------------------------------------------------------------------------

func _load_portrait(portrait_id: String) -> Texture2D:
	var user_path := "user://portraits/%s.png" % portrait_id
	if FileAccess.file_exists(user_path):
		var img := Image.load_from_file(user_path)
		if img != null:
			return ImageTexture.create_from_image(img)
	var res_path := "res://assets/portraits/%s.png" % portrait_id
	if ResourceLoader.exists(res_path):
		return load(res_path) as Texture2D
	return null


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
