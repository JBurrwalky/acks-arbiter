class_name SessionStatusBar
extends CanvasLayer

## Persistent bottom status bar showing party state at a glance.
##
## Widgets: party indicator | location | time | day budget | adventure pool |
##          party member chips | movement mode | light source
##
## Hidden during MAIN_MENU and CHARACTER_CREATION states.
## Visible during EXPLORATION, COMBAT, DOWNTIME, DOMAIN.

const BAR_HEIGHT := 48
const CHIP_SIZE := 36
const HP_BAR_HEIGHT := 4
const FONT_SIZE := 12
const SMALL_FONT := 10
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const HP_GREEN := Color(0.25, 0.65, 0.25, 1.0)
const HP_YELLOW := Color(0.80, 0.70, 0.15, 1.0)
const HP_RED := Color(0.75, 0.20, 0.15, 1.0)
const BG_COLOR := Color(0.08, 0.06, 0.04, 0.95)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)

var _bar: PanelContainer = null
var _party_label: Label = null
var _location_label: Label = null
var _time_label: Label = null
var _day_budget_container: HBoxContainer = null
var _adventure_pool_label: Label = null
var _member_chips: HBoxContainer = null
var _movement_label: Label = null
var _light_label: Label = null

# Cached state for updates.
var _party_members: Array = []


func _ready() -> void:
	layer = 80
	_build_ui()
	_connect_signals()
	_update_visibility()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -BAR_HEIGHT
	_bar.offset_bottom = 0

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_top = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_bar.add_theme_stylebox_override("panel", style)
	add_child(_bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_child(hbox)

	# Party indicator.
	_party_label = _make_label("Party", LABEL_COLOR, FONT_SIZE)
	_party_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(_party_label)

	hbox.add_child(_vsep())

	# Location.
	_location_label = _make_label("--", LABEL_COLOR, FONT_SIZE)
	_location_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(_location_label)

	hbox.add_child(_vsep())

	# Time.
	_time_label = _make_label("Day 1", LABEL_COLOR, FONT_SIZE)
	_time_label.custom_minimum_size = Vector2(110, 0)
	hbox.add_child(_time_label)

	hbox.add_child(_vsep())

	# Day budget (8 slots placeholder).
	_day_budget_container = HBoxContainer.new()
	_day_budget_container.add_theme_constant_override("separation", 2)
	for i in range(8):
		var slot := ColorRect.new()
		slot.custom_minimum_size = Vector2(12, 16)
		slot.color = Color(0.25, 0.22, 0.18, 0.6)
		_day_budget_container.add_child(slot)
	hbox.add_child(_day_budget_container)

	hbox.add_child(_vsep())

	# Adventure pool.
	_adventure_pool_label = _make_label("XP: 0 | GP: 0", DIM_COLOR, SMALL_FONT)
	_adventure_pool_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(_adventure_pool_label)

	hbox.add_child(_vsep())

	# Party member chips.
	_member_chips = HBoxContainer.new()
	_member_chips.add_theme_constant_override("separation", 4)
	_member_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_member_chips)

	hbox.add_child(_vsep())

	# Movement mode.
	_movement_label = _make_label("Walk", DIM_COLOR, SMALL_FONT)
	hbox.add_child(_movement_label)

	hbox.add_child(_vsep())

	# Light source.
	_light_label = _make_label("", DIM_COLOR, SMALL_FONT)
	hbox.add_child(_light_label)


func _make_label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 1)
	sep.add_theme_color_override("separator", Color(0.35, 0.30, 0.22, 0.5))
	return sep


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	GameState.state_changed.connect(_on_state_changed)
	EventBus.hex_entered.connect(_on_hex_entered)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.settlement_entered.connect(_on_settlement_entered)
	EventBus.hp_changed.connect(_on_hp_changed)
	EventBus.condition_changed.connect(_on_condition_changed)
	Timekeeping.round_advanced.connect(_on_time_advanced)


func _on_state_changed(_from: int, _to: int) -> void:
	_update_visibility()


func _update_visibility() -> void:
	var state: int = GameState.current_state
	_bar.visible = state in [
		GameState.State.EXPLORATION,
		GameState.State.COMBAT,
		GameState.State.DOWNTIME,
		GameState.State.DOMAIN,
		GameState.State.PAUSED,
	]


func _on_hex_entered(hex_id: String) -> void:
	_location_label.text = "Hex %s" % hex_id


func _on_room_entered(room_id: String) -> void:
	_location_label.text = "Room %s" % room_id


func _on_settlement_entered(settlement_id: String, _district_id: String) -> void:
	_location_label.text = settlement_id.capitalize()


func _on_hp_changed(_character_id: String, _old_hp: int, _new_hp: int) -> void:
	_refresh_member_chips()


func _on_condition_changed(_character_id: String, _change: Dictionary) -> void:
	_refresh_member_chips()


func _on_time_advanced(_rounds: int) -> void:
	_update_time_display()


# ---------------------------------------------------------------------------
# Update methods
# ---------------------------------------------------------------------------

func update_party(party_name: String, members: Array) -> void:
	_party_label.text = party_name
	_party_members = members
	_refresh_member_chips()


func update_adventure_pool(xp: int, gp: int) -> void:
	_adventure_pool_label.text = "XP: %d | GP: %d" % [xp, gp]


func update_movement_mode(mode: String) -> void:
	_movement_label.text = mode


func update_light_source(source_name: String, turns_remaining: int) -> void:
	if source_name.is_empty():
		_light_label.text = ""
		return
	if turns_remaining < 0:
		_light_label.text = source_name
	else:
		_light_label.text = "%s (%d)" % [source_name, turns_remaining]


func _update_time_display() -> void:
	var day: int = Timekeeping.get_total_days() + 1
	var hour: int = Timekeeping.get_hour_of_day()
	var time_of_day := "Night"
	if hour >= 6 and hour < 12:
		time_of_day = "Morning"
	elif hour >= 12 and hour < 18:
		time_of_day = "Afternoon"
	elif hour >= 18 and hour < 21:
		time_of_day = "Evening"
	_time_label.text = "Day %d, %s" % [day, time_of_day]


func _refresh_member_chips() -> void:
	for child in _member_chips.get_children():
		child.queue_free()

	for member in _party_members:
		var chip := _create_member_chip(member)
		_member_chips.add_child(chip)


func _create_member_chip(member: Dictionary) -> VBoxContainer:
	var chip := VBoxContainer.new()
	chip.custom_minimum_size = Vector2(CHIP_SIZE, CHIP_SIZE)
	chip.add_theme_constant_override("separation", 1)

	# Name label (abbreviated).
	var name_text: String = member.get("name", "?")
	if name_text.length() > 4:
		name_text = name_text.left(4)
	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", LABEL_COLOR)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(name_label)

	# Portrait placeholder (colored circle).
	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(CHIP_SIZE - 4, CHIP_SIZE - 16)
	portrait.color = Color(0.35, 0.30, 0.25, 0.8)
	chip.add_child(portrait)

	# HP bar.
	var hp_current: int = member.get("hp_current", 1)
	var hp_max: int = member.get("hp_max", 1)
	var hp_ratio: float = float(hp_current) / float(maxi(hp_max, 1))

	var hp_bg := ColorRect.new()
	hp_bg.custom_minimum_size = Vector2(CHIP_SIZE - 4, HP_BAR_HEIGHT)
	hp_bg.color = Color(0.15, 0.12, 0.10, 0.8)
	chip.add_child(hp_bg)

	var hp_fill := ColorRect.new()
	hp_fill.custom_minimum_size = Vector2((CHIP_SIZE - 4) * hp_ratio, HP_BAR_HEIGHT)
	if hp_ratio > 0.5:
		hp_fill.color = HP_GREEN
	elif hp_ratio > 0.25:
		hp_fill.color = HP_YELLOW
	else:
		hp_fill.color = HP_RED
	hp_bg.add_child(hp_fill)

	# Click to open character sheet.
	var char_id: String = member.get("id", "")
	if not char_id.is_empty():
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				EventBus.character_sheet_requested.emit(char_id)
		)

	return chip
