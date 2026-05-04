# CharacterPreferencesModal — "Prefers to carry" tag editor for PCs and henchmen.
#
# Dependencies:
#   - CampaignRepository (autoload): get/save character preferences
#
# No class_name — lazily instantiated by InventoryTabPage.

extends PanelContainer

signal preferences_saved(character_id: String, tags: Array)

const PREF_TAGS := [
	["torch_bearer", "Torch-bearer"],
	["rations_keeper", "Rations-keeper"],
	["scroll_keeper", "Scroll-keeper"],
	["gold_purse", "Gold-purse"],
	["rope_bearer", "Rope-bearer"],
	["magic_item_keeper", "Magic-item keeper"],
	["ammunition_porter", "Ammunition-porter"],
	["healing_kit_keeper", "Healing-kit keeper"],
]

var _character_id: String = ""
var _checkboxes: Dictionary = {}  # tag_key -> CheckBox
var _char_name_label: Label
var _is_built: bool = false


func _ready() -> void:
	visible = false
	_build_ui()


func open(character_id: String) -> void:
	_character_id = character_id
	if not _is_built:
		_build_ui()

	# Update title
	var char_data := CampaignRepository.get_character(character_id)
	_char_name_label.text = "Preferences: %s" % str(char_data.get("name", "Unknown"))

	# Load current tags
	var current_tags: Array = CampaignRepository.get_character_preferences(character_id)
	for tag_def in PREF_TAGS:
		if _checkboxes.has(tag_def[0]):
			_checkboxes[tag_def[0]].button_pressed = tag_def[0] in current_tags

	visible = true


func _build_ui() -> void:
	_is_built = true

	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(320, 340)
	size = Vector2(320, 340)

	# Position centered
	anchor_left = 0.35
	anchor_right = 0.65
	anchor_top = 0.2
	anchor_bottom = 0.8

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.08, 0.95)
	style.border_color = Color(0.46, 0.33, 0.19, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Title
	_char_name_label = Label.new()
	_char_name_label.text = "Preferences"
	_char_name_label.add_theme_font_size_override("font_size", 15)
	_char_name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_char_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_char_name_label)

	vbox.add_child(HSeparator.new())

	# Description
	var desc := Label.new()
	desc.text = "Select item categories this character prefers to carry.\nUsed by Auto-distribute."
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	# Checkboxes
	for tag_def in PREF_TAGS:
		var cb := CheckBox.new()
		cb.text = tag_def[1]
		cb.add_theme_font_size_override("font_size", 12)
		_checkboxes[tag_def[0]] = cb
		vbox.add_child(cb)

	vbox.add_child(HSeparator.new())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.pressed.connect(func(): visible = false)
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.add_theme_font_size_override("font_size", 12)
	save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(save_btn)


func _on_save_pressed() -> void:
	var selected: Array = []
	for tag_def in PREF_TAGS:
		if _checkboxes.has(tag_def[0]) and _checkboxes[tag_def[0]].button_pressed:
			selected.append(tag_def[0])
	CampaignRepository.save_character_preferences(_character_id, selected)
	preferences_saved.emit(_character_id, selected)
	visible = false
