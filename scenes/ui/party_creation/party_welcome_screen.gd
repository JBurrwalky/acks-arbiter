extends CanvasLayer

## Party Welcome Screen — shown after creating a new campaign.
##
## Displays a welcome message with the world name and offers
## "Create Party" / "Cancel" buttons.
##
## No class_name — UI scripts do not export class names per coding conventions.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal create_party_pressed
signal premade_party_pressed
signal cancel_pressed


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _world_name: String = ""


# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _title_label: Label
var _subtitle_label: Label


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	hide()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(world_name: String) -> void:
	_world_name = world_name
	if _title_label == null:
		_build_ui()
	_title_label.text = "Welcome to %s" % world_name
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

	# Centered panel (600 wide x 280 tall)
	var panel_frame := PanelContainer.new()
	panel_frame.anchor_left = 0.5
	panel_frame.anchor_top = 0.5
	panel_frame.anchor_right = 0.5
	panel_frame.anchor_bottom = 0.5
	panel_frame.offset_left = -300.0
	panel_frame.offset_top = -140.0
	panel_frame.offset_right = 300.0
	panel_frame.offset_bottom = 140.0
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
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_margin.add_child(vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "Welcome"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_title_label)

	# Subtitle
	_subtitle_label = Label.new()
	_subtitle_label.text = "Create a new party to begin your quest."
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_subtitle_label)

	vbox.add_child(HSeparator.new())

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var create_btn := Button.new()
	create_btn.text = "Create Party"
	create_btn.custom_minimum_size = Vector2(140, 36)
	create_btn.pressed.connect(func(): create_party_pressed.emit())
	btn_row.add_child(create_btn)

	var premade_btn := Button.new()
	premade_btn.text = "Use Premade Party"
	premade_btn.custom_minimum_size = Vector2(180, 36)
	premade_btn.pressed.connect(func(): premade_party_pressed.emit())
	btn_row.add_child(premade_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 36)
	cancel_btn.pressed.connect(func(): cancel_pressed.emit())
	btn_row.add_child(cancel_btn)
