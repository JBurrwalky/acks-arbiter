class_name DowntimeScreen
extends CanvasLayer

## Downtime activity hub — grid of activity cards.
##
## Implemented activities (Phase G):
##   - Carousing: Gold → XP + mishap table
##   - Reserve XP: Convert GP to reserve XP
##   - Hijinks: Thief/assassin crime activities
##   - Rest & Recuperate: Extended rest for HP recovery
##
## Placeholder activities (Phase J+):
##   - Hiring (extends existing hiring_panel)
##   - Spell Research
##   - Mercantile Ventures

signal downtime_ended

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const CARD_BG := Color(0.18, 0.15, 0.12, 0.9)
const CARD_HOVER := Color(0.25, 0.22, 0.18, 0.9)
const CARD_DISABLED := Color(0.14, 0.12, 0.10, 0.6)

var _content: VBoxContainer = null
var _activity_panel: VBoxContainer = null  # For sub-activity display


func _ready() -> void:
	layer = 50


func setup() -> void:
	_build_hub_ui()


# ---------------------------------------------------------------------------
# Hub UI
# ---------------------------------------------------------------------------

func _build_hub_ui() -> void:
	_clear()

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	bg.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)

	_content.add_child(_heading("Downtime Activities"))
	_content.add_child(_body("Choose an activity to pursue during your time in the settlement."))

	# Activity grid.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_content.add_child(grid)

	# Active activities.
	_add_activity_card(grid, "Carousing", "Spend gold for XP. Risk mishaps.",
		"~", true, _show_carousing)
	_add_activity_card(grid, "Reserve XP", "Convert gold to reserve XP.",
		"$", true, _show_reserve_xp)
	_add_activity_card(grid, "Hijinks", "Thief/assassin criminal activities.",
		"!", true, _show_hijinks)
	_add_activity_card(grid, "Rest", "Extended rest for HP recovery.",
		"z", true, _show_rest)

	# Placeholder activities.
	_add_activity_card(grid, "Hiring", "Search for henchmen to hire.",
		"&", true, _show_hiring)
	_add_activity_card(grid, "Spell Research", "Research new spells (Phase J).",
		"*", false, Callable())
	_add_activity_card(grid, "Mercantile", "Mercantile ventures (Phase J).",
		"$", false, Callable())

	# End downtime button.
	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(btn_bar)

	var end_btn := Button.new()
	end_btn.text = "End Downtime"
	end_btn.add_theme_font_size_override("font_size", 14)
	end_btn.custom_minimum_size = Vector2(160, 40)
	end_btn.pressed.connect(func(): downtime_ended.emit())
	btn_bar.add_child(end_btn)

	# Activity detail panel (shown when an activity is selected).
	_activity_panel = VBoxContainer.new()
	_activity_panel.add_theme_constant_override("separation", 10)
	_activity_panel.visible = false
	_content.add_child(_activity_panel)


func _add_activity_card(parent: Control, title_text: String, desc: String,
		icon: String, enabled: bool, callback: Callable) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(200, 100)

	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG if enabled else CARD_DISABLED
	style.border_color = Color(0.35, 0.30, 0.22, 0.6)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	vbox.add_child(hdr)

	var icon_label := Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 18)
	icon_label.add_theme_color_override("font_color", HEADING_COLOR if enabled else DIM_COLOR)
	hdr.add_child(icon_label)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HEADING_COLOR if enabled else DIM_COLOR)
	hdr.add_child(title)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", DIM_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	if enabled and callback.is_valid():
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				callback.call()
		)


# ---------------------------------------------------------------------------
# Activity sub-panels
# ---------------------------------------------------------------------------

func _show_activity(title_text: String) -> void:
	_activity_panel.visible = true
	for child in _activity_panel.get_children():
		child.queue_free()
	_activity_panel.add_child(_heading(title_text))

	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.pressed.connect(func(): _activity_panel.visible = false)
	_activity_panel.add_child(back_btn)


func _show_carousing() -> void:
	_show_activity("Carousing")
	_activity_panel.add_child(_body(
		"Spend gold pieces on wine, song, and revelry to earn experience. "
		+ "For every 100 GP spent, earn 100 XP. But beware — the mishap table "
		+ "awaits the unlucky carouser!"))
	_activity_panel.add_child(_dim("Carousing resolution will be implemented in the next phase."))


func _show_reserve_xp() -> void:
	_show_activity("Reserve XP")
	_activity_panel.add_child(_body(
		"Convert gold pieces to reserve experience at a 1:1 ratio. "
		+ "Reserve XP can be used to replace a slain character with one "
		+ "of higher starting level."))
	_activity_panel.add_child(_dim("Reserve XP conversion will be implemented in the next phase."))


func _show_hijinks() -> void:
	_show_activity("Hijinks")
	_activity_panel.add_child(_body(
		"Thieves and assassins can pursue criminal enterprises during downtime. "
		+ "Make a proficiency check — success yields gold, failure risks "
		+ "imprisonment or worse."))
	_activity_panel.add_child(_dim("Hijinks resolution will be implemented in the next phase."))


func _show_rest() -> void:
	_show_activity("Rest & Recuperate")
	_activity_panel.add_child(_body(
		"Extended rest in a settlement. Recover 1 HP per day of complete rest. "
		+ "Bed rest under a healer's care can improve recovery rates."))
	_activity_panel.add_child(_dim("Extended rest will advance time and apply HP recovery."))


func _show_hiring() -> void:
	_show_activity("Hiring")
	_activity_panel.add_child(_body(
		"Search for henchmen to hire. The available pool refreshes monthly "
		+ "based on the settlement's market class."))
	_activity_panel.add_child(_dim("Hiring will open the henchman recruitment panel."))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear() -> void:
	for child in get_children():
		child.queue_free()

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label

func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", BODY_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _dim(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
