class_name InitiativeStrip
extends PanelContainer

## Vertical initiative order display for combat HUD.
##
## Shows all combatants in initiative order with side indicator, name,
## initiative number, and HP bar. Active combatant is highlighted.
## Dead combatants are greyed out.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const COLOR_PARTY   := Color(0.3, 0.5, 1.0)
const COLOR_ENEMY   := Color(0.9, 0.2, 0.2)
const COLOR_NEUTRAL := Color(0.9, 0.8, 0.2)
const COLOR_DEAD    := Color(0.4, 0.4, 0.4, 0.6)
const COLOR_ACTIVE_BG := Color(1.0, 1.0, 1.0, 0.15)
const COLOR_HP_FULL := Color(0.2, 0.8, 0.2)
const COLOR_HP_HURT := Color(0.8, 0.7, 0.1)
const COLOR_HP_LOW  := Color(0.8, 0.2, 0.2)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Array of {combatant_id, display_name, side, initiative_total, hp_current, hp_max, is_alive}
var _order: Array = []
var _active_id: String = ""
var _entry_nodes: Dictionary = {}  # combatant_id -> HBoxContainer


# ---------------------------------------------------------------------------
# Scene references
# ---------------------------------------------------------------------------

var _scroll: ScrollContainer = null
var _list: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(200, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	add_child(vbox)

	var title := Label.new()
	title.text = "Initiative"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set the full initiative order for the round.
## Each entry: {combatant_id, display_name, side, initiative_total, hp_current, hp_max, is_alive}
func set_initiative_order(order: Array) -> void:
	_order = order
	_rebuild()


## Highlight the active combatant.
func set_active(combatant_id: String) -> void:
	_active_id = combatant_id
	_update_highlights()


## Update HP display for a single combatant.
func update_hp(combatant_id: String, current: int, max_val: int) -> void:
	var node: HBoxContainer = _entry_nodes.get(combatant_id)
	if node == null:
		return
	var bar: ProgressBar = node.get_node_or_null("HPBar")
	if bar != null:
		bar.max_value = max_val
		bar.value = current
		_style_hp_bar(bar, current, max_val)
	var hp_label: Label = node.get_node_or_null("HPLabel")
	if hp_label != null:
		hp_label.text = "%d/%d" % [current, max_val]


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	_entry_nodes.clear()
	for child in _list.get_children():
		child.queue_free()

	for entry in _order:
		var row := _create_entry_row(entry)
		_list.add_child(row)
		_entry_nodes[entry.get("combatant_id", "")] = row

	_update_highlights()


func _create_entry_row(entry: Dictionary) -> HBoxContainer:
	var cid: String = entry.get("combatant_id", "")
	var dname: String = entry.get("display_name", "???")
	var side_val: int = entry.get("side", -1)
	var init_total: int = entry.get("initiative_total", 0)
	var hp_cur: int = entry.get("hp_current", 0)
	var hp_max: int = entry.get("hp_max", 1)
	var alive: bool = entry.get("is_alive", true)

	var row := HBoxContainer.new()
	row.name = cid
	row.custom_minimum_size.y = 28.0
	row.add_theme_constant_override("separation", 4)

	# Side colour indicator
	var side_bar := ColorRect.new()
	side_bar.custom_minimum_size = Vector2(4, 24)
	if not alive:
		side_bar.color = COLOR_DEAD
	elif side_val == 0:  # PARTY
		side_bar.color = COLOR_PARTY
	elif side_val == 1:  # ENEMY
		side_bar.color = COLOR_ENEMY
	else:
		side_bar.color = COLOR_NEUTRAL
	row.add_child(side_bar)

	# Initiative number
	var init_label := Label.new()
	init_label.name = "InitLabel"
	init_label.text = str(init_total)
	init_label.custom_minimum_size.x = 22.0
	init_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	init_label.add_theme_font_size_override("font_size", 11)
	if not alive:
		init_label.add_theme_color_override("font_color", COLOR_DEAD)
	row.add_child(init_label)

	# Name
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = dname
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 11)
	if not alive:
		name_label.add_theme_color_override("font_color", COLOR_DEAD)
	row.add_child(name_label)

	# HP label
	var hp_label := Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = "%d/%d" % [hp_cur, hp_max]
	hp_label.custom_minimum_size.x = 40.0
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.add_theme_font_size_override("font_size", 10)
	if not alive:
		hp_label.add_theme_color_override("font_color", COLOR_DEAD)
	row.add_child(hp_label)

	# HP bar
	var bar := ProgressBar.new()
	bar.name = "HPBar"
	bar.custom_minimum_size = Vector2(50, 10)
	bar.max_value = hp_max
	bar.value = hp_cur
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_hp_bar(bar, hp_cur, hp_max)
	row.add_child(bar)

	return row


func _style_hp_bar(bar: ProgressBar, current: int, max_val: int) -> void:
	var ratio := 0.0 if max_val <= 0 else float(current) / float(max_val)
	var fill_style := StyleBoxFlat.new()
	if ratio > 0.5:
		fill_style.bg_color = COLOR_HP_FULL
	elif ratio > 0.25:
		fill_style.bg_color = COLOR_HP_HURT
	else:
		fill_style.bg_color = COLOR_HP_LOW
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_style)


func _update_highlights() -> void:
	for cid in _entry_nodes:
		var row: HBoxContainer = _entry_nodes[cid]
		if cid == _active_id:
			var bg := StyleBoxFlat.new()
			bg.bg_color = COLOR_ACTIVE_BG
			bg.corner_radius_top_left = 2
			bg.corner_radius_top_right = 2
			bg.corner_radius_bottom_left = 2
			bg.corner_radius_bottom_right = 2
			# HBoxContainer doesn't support panel stylebox — use a Panel sibling approach
			# Instead just modulate the row
			row.modulate = Color(1.2, 1.2, 1.2)
		else:
			row.modulate = Color.WHITE
