extends CanvasLayer

## Dev tooling (Jedidiah 2026-06-23): the "Get Hex Info" modal — a scrollable dump of EVERY
## stored datum for a 6-mile play hex, built from HexInfoAssembler. Code-built (no .tscn),
## news up fresh per right-click, queue_free()s on close. Layer 130: above the HUD (80),
## below notifications (150) / pause (160) / scene-transition (200, the full-screen occluder).
##
## Usage:
##   var m = preload(".../hex_info_modal.gd").new()
##   m.setup("Hex Info — (q, r)", HexInfoAssembler.assemble(cid, map_id, q, r))
##   get_tree().root.add_child(m)

var _header: String = ""
var _sections: Array = []


## Set the content BEFORE add_child (add_child triggers _ready → _build).
func setup(header: String, sections: Array) -> void:
	_header = header
	_sections = sections


func _ready() -> void:
	layer = 130
	_build()


const _LABEL_COLOR := Color(0.30, 0.22, 0.12, 1.0)   # dark enough to read on the panel bg
const _VALUE_COLOR := Color(0.08, 0.05, 0.02, 1.0)   # near-black for headers + values


func _build() -> void:
	# Light dimming backdrop — clicking off the panel closes the modal. Kept subtle (a dev
	# panel, not a blocking dialog) so the map stays legible behind it.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.25)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.16
	panel.anchor_right = 0.84
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.93
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	# OPAQUE, bright, flat vellum bg (the framed-window chrome uses an aged-parchment texture
	# with draw_center=false — too dark/busy for a dense data dump). High text contrast wins.
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.93, 0.88, 0.78, 1.0)
	pstyle.set_border_width_all(2)
	pstyle.border_color = Color(0.36, 0.26, 0.15, 1.0)
	pstyle.set_corner_radius_all(8)
	pstyle.content_margin_left = 18.0
	pstyle.content_margin_right = 18.0
	pstyle.content_margin_top = 12.0
	pstyle.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", pstyle)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Title bar (header + close X).
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = _header
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _VALUE_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)
	var x_btn := Button.new()
	x_btn.text = "✕"
	x_btn.pressed.connect(_close)
	title_bar.add_child(x_btn)

	vbox.add_child(HSeparator.new())

	# Scrollable body.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	scroll.add_child(body)

	for sec in _sections:
		var sec_label := Label.new()
		sec_label.text = "▸ " + str((sec as Dictionary).get("title", "?"))
		sec_label.add_theme_font_size_override("font_size", 15)
		sec_label.add_theme_color_override("font_color", _VALUE_COLOR)
		body.add_child(_spacer(7))
		body.add_child(sec_label)
		for row in (sec as Dictionary).get("rows", []):
			var rh := HBoxContainer.new()
			rh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rh.add_theme_constant_override("separation", 10)
			var lbl := Label.new()
			lbl.text = str((row as Dictionary).get("label", ""))
			lbl.custom_minimum_size = Vector2(210, 0)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			lbl.add_theme_color_override("font_color", _LABEL_COLOR)
			rh.add_child(lbl)
			var val := Label.new()
			val.text = str((row as Dictionary).get("value", ""))
			val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			val.add_theme_color_override("font_color", _VALUE_COLOR)
			rh.add_child(val)
			body.add_child(rh)

	vbox.add_child(HSeparator.new())
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close)
	vbox.add_child(close_btn)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	queue_free()
