extends CanvasLayer

## Party Roster Screen — shown between character creation rounds during new campaign setup.
##
## Displays the current party members with portraits, stats, and a counter.
## Provides Add Character / Delete Character / Begin Adventure buttons.
##
## No class_name — UI scripts do not export class names per coding conventions.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# MAX_PARTY_SIZE moved to GameState.MAX_PARTY_SIZE per gdd-ui-architecture.md §8.

const PortraitTextures := preload("res://engine/subsystems/assets/portrait_textures.gd")

const PORTRAIT_SIZE := Vector2(64, 64)
const ROW_BG_COLOR := Color(0.94, 0.89, 0.78, 0.42)
const ROW_BG_SELECTED_COLOR := Color(0.82, 0.72, 0.55, 0.65)
const ROW_BORDER_COLOR := Color(0.44, 0.31, 0.18, 0.88)

const ABILITY_KEYS: Array[String] = ["STR", "INT", "WIS", "DEX", "CON", "CHA"]
const ABILITY_FIELDS: Array[String] = [
	"strength", "intelligence", "wisdom", "dexterity", "constitution", "charisma"
]


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal add_character_pressed
signal delete_character_pressed(character_id: String)
signal begin_adventure_pressed


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _campaign_id: String = ""
var _party_id: String = ""
var _characters: Array = []  # Array of character Dictionaries from DB
var _selected_character_id: String = ""


# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _counter_label: Label
var _list_container: VBoxContainer
var _scroll: ScrollContainer
var _add_btn: Button
var _delete_btn: Button
var _begin_btn: Button
var _row_panels: Dictionary = {}  # character_id -> PanelContainer


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	hide()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(campaign_id: String, party_id: String) -> void:
	_campaign_id = campaign_id
	_party_id = party_id
	_selected_character_id = ""
	if _counter_label == null:
		_build_ui()
	refresh()
	show()


func close() -> void:
	hide()


func refresh() -> void:
	_characters = CampaignRepository.list_party_characters(_party_id)
	_rebuild_roster()
	_update_buttons()


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

	# Centered panel (700 wide x 520 tall)
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

	var title := Label.new()
	title.text = "Party Roster"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

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

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_margin.add_child(_scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list_container)

	vbox.add_child(HSeparator.new())

	# --- Button row ---
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_add_btn = Button.new()
	_add_btn.text = "Add Character"
	_add_btn.custom_minimum_size = Vector2(140, 36)
	_add_btn.pressed.connect(func(): add_character_pressed.emit())
	btn_row.add_child(_add_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete Character"
	_delete_btn.custom_minimum_size = Vector2(150, 36)
	_delete_btn.disabled = true
	_delete_btn.pressed.connect(_on_delete_pressed)
	btn_row.add_child(_delete_btn)

	_begin_btn = Button.new()
	_begin_btn.text = "Begin Adventure"
	_begin_btn.custom_minimum_size = Vector2(150, 36)
	_begin_btn.disabled = true
	_begin_btn.pressed.connect(func(): begin_adventure_pressed.emit())
	btn_row.add_child(_begin_btn)


# ---------------------------------------------------------------------------
# Roster rendering
# ---------------------------------------------------------------------------

func _rebuild_roster() -> void:
	# Clear existing rows
	for child in _list_container.get_children():
		child.queue_free()
	_row_panels.clear()

	_counter_label.text = "Party Members: %d/%d" % [_characters.size(), GameState.MAX_PARTY_SIZE]

	if _characters.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No party members yet. Add a character to get started."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 14)
		_list_container.add_child(empty_label)
		return

	for c in _characters:
		var row := _make_character_row(c)
		_list_container.add_child(row)
		_row_panels[c.get("id", "")] = row


func _make_character_row(c: Dictionary) -> PanelContainer:
	var char_id: String = c.get("id", "")
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _make_row_style(false))
	row_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Make row clickable for selection
	row_panel.gui_input.connect(_on_row_input.bind(char_id, row_panel))

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
	portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	var char_name: String = c.get("name", "(unnamed)")
	name_label.text = char_name
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
# Row selection
# ---------------------------------------------------------------------------

func _on_row_input(event: InputEvent, char_id: String, _panel: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_character(char_id)


func _select_character(char_id: String) -> void:
	# Toggle selection
	if _selected_character_id == char_id:
		_selected_character_id = ""
	else:
		_selected_character_id = char_id

	# Update row highlights
	for id in _row_panels:
		var panel: PanelContainer = _row_panels[id]
		panel.add_theme_stylebox_override("panel", _make_row_style(id == _selected_character_id))

	_update_buttons()


# ---------------------------------------------------------------------------
# Button state
# ---------------------------------------------------------------------------

func _update_buttons() -> void:
	var count: int = _characters.size()
	_add_btn.disabled = (count >= GameState.MAX_PARTY_SIZE)
	_delete_btn.disabled = _selected_character_id.is_empty()
	_begin_btn.disabled = (count < 1)


func _on_delete_pressed() -> void:
	if _selected_character_id.is_empty():
		return
	delete_character_pressed.emit(_selected_character_id)


# ---------------------------------------------------------------------------
# Portrait loading (same pattern as character_sheet_panel.gd)
# ---------------------------------------------------------------------------

func _load_portrait(portrait_id: String) -> Texture2D:
	# Shared loader: downscaled + mipmapped so the 64px thumbnail doesn't alias.
	return PortraitTextures.resolve(portrait_id)


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


func _make_row_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG_SELECTED_COLOR if selected else ROW_BG_COLOR
	style.border_color = ROW_BORDER_COLOR
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	return style
