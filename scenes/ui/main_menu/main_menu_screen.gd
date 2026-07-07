class_name MainMenuScreen
extends CanvasLayer

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


const SETTINGS_PATH := "user://settings.cfg"
const LLM_WIZARD_SCENE := "res://scenes/ui/settings/llm_setup_wizard.tscn"


func _ready() -> void:
	layer = 50
	_build_ui()
	# --- Live LLM L-2: first-run "narration can be AI-enhanced" banner (§12.4). ---
	_maybe_show_llm_first_run_banner()


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
	# Background.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.06, 0.04, 1.0)
	add_child(bg)

	# Center panel.
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
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


# ---------------------------------------------------------------------------
# Live LLM L-2: first-run banner (gdd-live-llm-integration.md §12.4)
# ---------------------------------------------------------------------------

## Shows a one-time, dismissible banner when settings.cfg has NO [llm] section
## (a fresh install predating any LLM configuration). Choosing to set up pushes
## the wizard; dismissing (either button) writes an [llm] section with
## offline_mode=false / provider="" so the banner never repeats.
func _maybe_show_llm_first_run_banner() -> void:
	if _llm_section_present():
		return

	var banner := PanelContainer.new()
	banner.name = "LlmFirstRunBanner"
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 12
	banner.offset_left = 12
	banner.offset_right = -12
	UiSurfaceStyles.apply_framed_window_chrome(banner)
	add_child(banner)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var msg := Label.new()
	msg.text = "Narration can be AI-enhanced — set up a provider in Settings."
	msg.add_theme_font_size_override("font_size", 13)
	msg.add_theme_color_override("font_color", HEADING_COLOR)
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(msg)

	var setup_btn := Button.new()
	setup_btn.text = "Set up"
	setup_btn.add_theme_font_size_override("font_size", 13)
	setup_btn.pressed.connect(func():
		_dismiss_llm_banner(banner)
		if NavigationStack.instance != null:
			NavigationStack.instance.push(LLM_WIZARD_SCENE)
	)
	row.add_child(setup_btn)

	var dismiss_btn := Button.new()
	dismiss_btn.text = "Dismiss"
	dismiss_btn.add_theme_font_size_override("font_size", 13)
	dismiss_btn.pressed.connect(func(): _dismiss_llm_banner(banner))
	row.add_child(dismiss_btn)


func _dismiss_llm_banner(banner: Node) -> void:
	# Write an [llm] section so the banner never repeats. offline_mode=false /
	# provider="" is the documented "not-yet-configured but seen" marker (§12.4).
	# GameState.save_settings() persists the current LLMManager.settings (which
	# already defaults to provider="" / offline_mode=false on a fresh install),
	# so a plain save is enough to materialize the [llm] section on disk.
	GameState.save_settings()
	if is_instance_valid(banner):
		banner.queue_free()


## True if user://settings.cfg exists AND already has an [llm] section.
func _llm_section_present() -> bool:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return false
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return false
	return config.has_section("llm")


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", HEADING_COLOR)
	btn.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	btn.pressed.connect(callback)
	parent.add_child(btn)
