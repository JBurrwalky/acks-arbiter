extends Control

## Screen A: Quick Start (gdd-campaign-creation-ui.md §3). The one physical knob a
## casual player feels — map size — plus the doorway to Advanced. The shared
## SettingParameters is mutated in place (bind_params holds the ref).

signal start_requested
signal customize_requested

const _SIZES := [["small", "Small"], ["medium", "Medium"], ["large", "Large"], ["huge", "Huge"]]

# Hover note per size (each hex spans 24 miles — gdd-setting-generation §4.6).
const _SIZE_TOOLTIPS := {
	"small": "15 × 12 hexes — 180 hexes, ~360 miles across. Fastest to generate.",
	"medium": "25 × 20 hexes — 500 hexes, ~600 miles across. The default.",
	"large": "40 × 30 hexes — 1,200 hexes, ~960 miles across.",
	"huge": "60 × 45 hexes — 2,700 hexes, ~1,440 miles across. Slowest to generate.",
}

var _params: SettingParameters
var _size_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func bind_params(p: SettingParameters) -> void:
	_params = p
	_highlight_size()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.11, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	center.add_child(vb)

	var title := Label.new()
	title.text = "Forge a New World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.7))
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "Choose a map size — history, peoples, and conflicts are simulated for you."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.74, 0.69, 0.6))
	vb.add_child(sub)

	vb.add_child(_spacer(8))

	var sizes := HBoxContainer.new()
	sizes.alignment = BoxContainer.ALIGNMENT_CENTER
	sizes.add_theme_constant_override("separation", 12)
	vb.add_child(sizes)
	for entry in _SIZES:
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(124, 46)
		b.tooltip_text = str(_SIZE_TOOLTIPS.get(entry[0], ""))
		b.pressed.connect(_on_size_pressed.bind(entry[0]))
		sizes.add_child(b)
		_size_buttons[entry[0]] = b
	_highlight_size()

	vb.add_child(_spacer(16))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	vb.add_child(actions)

	var custom := Button.new()
	custom.text = "Customize…"
	custom.custom_minimum_size = Vector2(150, 54)
	custom.pressed.connect(func(): customize_requested.emit())
	actions.add_child(custom)

	var gen := Button.new()
	gen.text = "Generate World  ▸"
	gen.custom_minimum_size = Vector2(200, 54)
	gen.add_theme_font_size_override("font_size", 20)
	gen.pressed.connect(func(): start_requested.emit())
	actions.add_child(gen)


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _on_size_pressed(size: String) -> void:
	set_map_size(size)
	_highlight_size()


func _highlight_size() -> void:
	var current: String = _params.map_size if _params != null else "medium"
	for k in _size_buttons:
		_size_buttons[k].button_pressed = (str(k) == current)


func set_map_size(size: String) -> void:
	if _params != null:
		_params.map_size = size
