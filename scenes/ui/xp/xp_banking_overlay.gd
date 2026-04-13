class_name XPBankingOverlay
extends CanvasLayer

## XP banking overlay — shown on settlement entry.
##
## Displays the adventure pool (accumulated XP + GP since last banking),
## divides XP among party members with prime requisite adjustments,
## and shows per-character XP awards.

signal banking_completed

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const ACCENT_COLOR := Color(0.85, 0.75, 0.25, 1.0)

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _content: VBoxContainer = null


func _ready() -> void:
	layer = 105
	_build_chrome()
	_hide()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_banking(xp_pool: int, gp_pool: int, party_members: Array) -> void:
	_rebuild_content(xp_pool, gp_pool, party_members)
	_show()


# ---------------------------------------------------------------------------
# Chrome
# ---------------------------------------------------------------------------

func _build_chrome() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(500, 350)
	_panel.offset_left = -250
	_panel.offset_right = 250
	_panel.offset_top = -175
	_panel.offset_bottom = 175
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

func _rebuild_content(xp_pool: int, gp_pool: int, party_members: Array) -> void:
	if _content:
		_content.queue_free()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	margin.add_child(_content)

	_content.add_child(_heading("Adventure Pool Banking"))

	# Pool totals.
	var pool_text := "Monster XP: %d    Treasure GP: %d" % [xp_pool, gp_pool]
	_content.add_child(_accent_body(pool_text))

	# Per-character division.
	var member_count := party_members.size()
	if member_count == 0:
		_content.add_child(_body("No party members to receive XP."))
	else:
		var total_xp := xp_pool + gp_pool  # GP counts as XP in ACKS.
		# Banker's rounding for division.
		var base_share := _bankers_round(float(total_xp) / float(member_count))

		_content.add_child(_body("Base share per character: %d XP" % base_share))

		var sep := HSeparator.new()
		sep.add_theme_color_override("separator", UiSurfaceStyles.FRAME_BORDER_COLOR)
		_content.add_child(sep)

		# Grid of character awards.
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 4)
		_content.add_child(grid)

		# Headers.
		grid.add_child(_dim_label("Character"))
		grid.add_child(_dim_label("Modifier"))
		grid.add_child(_dim_label("XP Awarded"))

		for member in party_members:
			var name_str: String = member.get("name", "Unknown")
			var prime_req_mod: float = member.get("prime_req_xp_modifier", 0.0)
			var modified_share := _bankers_round(float(base_share) * (1.0 + prime_req_mod))

			var mod_text := ""
			if prime_req_mod > 0:
				mod_text = "+%d%%" % int(prime_req_mod * 100)
			elif prime_req_mod < 0:
				mod_text = "%d%%" % int(prime_req_mod * 100)
			else:
				mod_text = "--"

			grid.add_child(_body(name_str))
			grid.add_child(_body(mod_text))
			grid.add_child(_accent_body(str(modified_share)))

	# Continue button.
	var btn := Button.new()
	btn.text = "Continue"
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(120, 36)
	btn.pressed.connect(func():
		_hide()
		banking_completed.emit()
	)
	_content.add_child(btn)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _show() -> void:
	_backdrop.visible = true
	_panel.visible = true

func _hide() -> void:
	_backdrop.visible = false
	_panel.visible = false

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", BODY_COLOR)
	return label

func _accent_body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM_COLOR)
	return label

## Banker's rounding (round half to even).
func _bankers_round(value: float) -> int:
	var floored := int(value)
	var remainder := value - float(floored)
	if absf(remainder - 0.5) < 0.0001:
		# Exactly half — round to even.
		if floored % 2 == 0:
			return floored
		else:
			return floored + 1
	return int(roundf(value))
