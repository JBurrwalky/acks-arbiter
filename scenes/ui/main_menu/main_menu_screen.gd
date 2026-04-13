class_name MainMenuScreen
extends Control

## Main menu screen — first screen the player sees.
##
## Buttons: New Campaign, Load Campaign, Settings, Quit.
## Pushed as the boot screen by SessionRunner (replaces campaign_select
## as the initial target).

signal new_campaign_requested
signal load_campaign_requested
signal settings_requested
signal quit_requested

const TITLE_COLOR := Color(0.95, 0.88, 0.72, 1.0)
const HEADING_COLOR := Color(0.90, 0.85, 0.75, 1.0)
const BUTTON_WIDTH := 240
const BUTTON_HEIGHT := 44
const BUTTON_SPACING := 14


func _ready() -> void:
	_build_ui()


# ---------------------------------------------------------------------------
# NavigationStack duck-type interface
# ---------------------------------------------------------------------------

func enter(_params: Dictionary = {}) -> void:
	visible = true

func exit() -> void:
	visible = false


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)

	# Background.
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.06, 0.04, 1.0)
	add_child(bg)

	# Center panel.
	var center := VBoxContainer.new()
	center.set_anchors_preset(PRESET_CENTER)
	center.offset_left = -BUTTON_WIDTH / 2
	center.offset_right = BUTTON_WIDTH / 2
	center.offset_top = -200
	center.offset_bottom = 200
	center.add_theme_constant_override("separation", BUTTON_SPACING)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center)

	# Title.
	var title := Label.new()
	title.text = "ACKS ARBITER"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	# Subtitle.
	var subtitle := Label.new()
	subtitle.text = "Adventurer Conqueror King System"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.50, 0.42, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(subtitle)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	center.add_child(spacer)

	# Buttons.
	_add_button(center, "New Campaign", func(): new_campaign_requested.emit())
	_add_button(center, "Load Campaign", func(): load_campaign_requested.emit())
	_add_button(center, "Settings", func(): settings_requested.emit())
	_add_button(center, "Quit", func(): quit_requested.emit())

	# Version label.
	var version := Label.new()
	version.text = "v0.1-alpha"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color(0.35, 0.30, 0.22, 1.0))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(version)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", HEADING_COLOR)
	btn.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	btn.pressed.connect(callback)
	parent.add_child(btn)
