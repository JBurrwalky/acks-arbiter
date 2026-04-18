# EncumbranceBar — reusable UI widget for ACKS four-band encumbrance display
#
# Dependencies:
#   - CampaignRepository (autoload): reads character data and inventory
#   - EncumbranceCalculator (engine/subsystems/characters/encumbrance_calculator.gd)
#   - CharacterData (engine/shared_types/character_data.gd): ability_modifier()
#   - EventBus (autoload): listens for inventory_updated
#
# Character bands (ACKS RAW):
#   Green:  0-5000 units  (unencumbered, 120'/turn)
#   Yellow: 5001-7000     (lightly encumbered, 90'/turn)
#   Orange: 7001-10000    (heavily encumbered, 60'/turn)
#   Red:    10001-max     (severely encumbered, 30'/turn)
#   Flashing red: over max (max = 20000 + STR_mod * 1000)
#
# Creature/vehicle two-tier:
#   Green:  0 to normal capacity
#   Red:    normal to max capacity
#   Rejected: over max

extends Control

const MODE_CHARACTER := "character"
const MODE_CREATURE := "creature"
const MODE_VEHICLE := "vehicle"

## Band colors.
const COLOR_GREEN := Color(0.30, 0.69, 0.31)    # #4CAF50
const COLOR_YELLOW := Color(1.0, 0.76, 0.03)     # #FFC107
const COLOR_ORANGE := Color(1.0, 0.60, 0.0)      # #FF9800
const COLOR_RED := Color(0.96, 0.26, 0.21)        # #F44336
const COLOR_BG := Color(0.15, 0.15, 0.15, 0.8)
const COLOR_TICK := Color(1.0, 1.0, 1.0, 0.6)

## Character band boundaries (in encumbrance units = 1/1000 stone).
const BAND_LIGHT := 5000
const BAND_HEAVY := 7000
const BAND_SEVERE := 10000
const BASE_MAX := 20000

var _mode: String = MODE_CHARACTER
var _current_load: int = 0
var _max_capacity: int = BASE_MAX
var _normal_capacity: int = 0    # creature/vehicle: normal load threshold
var _band_label: String = ""
var _speed_label: String = ""
var _entity_id: String = ""
var _flash_timer: float = 0.0
var _is_flashing: bool = false

## Minimum bar dimensions.
const BAR_HEIGHT := 16
const MIN_BAR_WIDTH := 120


func _ready() -> void:
	custom_minimum_size = Vector2(MIN_BAR_WIDTH, BAR_HEIGHT + 4)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	EventBus.inventory_updated.connect(_on_inventory_updated)


## Configure for a character — reads inventory and STR for capacity.
func setup_character(character_id: String) -> void:
	_mode = MODE_CHARACTER
	_entity_id = character_id
	_refresh_character()


## Configure for a creature — reads capacity from trained_creature data.
func setup_creature(creature_id: String) -> void:
	_mode = MODE_CREATURE
	_entity_id = creature_id
	_refresh_creature()


## Configure for a vehicle — reads capacity from draft_vehicle data.
func setup_vehicle(vehicle_id: String) -> void:
	_mode = MODE_VEHICLE
	_entity_id = vehicle_id
	_refresh_vehicle()


## Force refresh.
func refresh() -> void:
	match _mode:
		MODE_CHARACTER:
			_refresh_character()
		MODE_CREATURE:
			_refresh_creature()
		MODE_VEHICLE:
			_refresh_vehicle()


func _refresh_character() -> void:
	if _entity_id.is_empty():
		return
	var char_data: Dictionary = CampaignRepository.get_character(_entity_id)
	if char_data.is_empty():
		return

	var strength: int = int(char_data.get("strength", 10))
	var str_mod: int = CharacterData.ability_modifier(strength)
	_max_capacity = BASE_MAX + (str_mod * 1000)

	var items: Array = CampaignRepository.get_inventory_items(_entity_id)
	var enc: Dictionary = EncumbranceCalculator.calculate_encumbrance(items)
	_current_load = enc["total_units"]

	# Determine band.
	if _current_load > _max_capacity:
		_band_label = "Over maximum"
		_speed_label = "0'/turn"
		_is_flashing = true
	elif _current_load > BAND_SEVERE:
		_band_label = "Severely encumbered"
		_speed_label = "30'/turn"
		_is_flashing = false
	elif _current_load > BAND_HEAVY:
		_band_label = "Heavily encumbered"
		_speed_label = "60'/turn"
		_is_flashing = false
	elif _current_load > BAND_LIGHT:
		_band_label = "Lightly encumbered"
		_speed_label = "90'/turn"
		_is_flashing = false
	else:
		_band_label = "Unencumbered"
		_speed_label = "120'/turn"
		_is_flashing = false

	_update_tooltip_character()
	queue_redraw()


func _refresh_creature() -> void:
	if _entity_id.is_empty():
		return
	# Read creature data for capacity.
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM trained_creatures WHERE id = ?", [_entity_id])
	var rows: Array = CampaignRepository.db.query_result
	if rows.is_empty():
		return
	var creature: Dictionary = rows[0]
	_normal_capacity = int(creature.get("carry_capacity_normal", 0))
	_max_capacity = int(creature.get("carry_capacity_max", 0))

	var items: Array = CampaignRepository.get_inventory_items_for_creature(_entity_id) if CampaignRepository.has_method("get_inventory_items_for_creature") else []
	var total_units := 0
	for item in items:
		total_units += EncumbranceCalculator.calculate_item_encumbrance(item)
	_current_load = total_units

	if _current_load > _max_capacity:
		_band_label = "Over maximum"
		_is_flashing = true
	elif _current_load > _normal_capacity:
		_band_label = "Overloaded"
		_is_flashing = false
	else:
		_band_label = "Normal"
		_is_flashing = false

	_update_tooltip_creature()
	queue_redraw()


func _refresh_vehicle() -> void:
	if _entity_id.is_empty():
		return
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM draft_vehicles WHERE id = ?", [_entity_id])
	var rows: Array = CampaignRepository.db.query_result
	if rows.is_empty():
		return
	var vehicle: Dictionary = rows[0]
	_normal_capacity = int(vehicle.get("cargo_capacity_normal", 0))
	_max_capacity = int(vehicle.get("cargo_capacity_max", 0))

	var items: Array = CampaignRepository.get_inventory_items_for_vehicle(_entity_id) if CampaignRepository.has_method("get_inventory_items_for_vehicle") else []
	var total_units := 0
	for item in items:
		total_units += EncumbranceCalculator.calculate_item_encumbrance(item)
	_current_load = total_units

	if _current_load > _max_capacity:
		_band_label = "Over maximum"
		_is_flashing = true
	elif _current_load > _normal_capacity:
		_band_label = "Overloaded"
		_is_flashing = false
	else:
		_band_label = "Normal"
		_is_flashing = false

	_update_tooltip_vehicle()
	queue_redraw()


func _update_tooltip_character() -> void:
	var stone_load: float = _current_load / 1000.0
	var stone_max: float = _max_capacity / 1000.0
	var next_band: int
	if _current_load <= BAND_LIGHT:
		next_band = BAND_LIGHT
	elif _current_load <= BAND_HEAVY:
		next_band = BAND_HEAVY
	elif _current_load <= BAND_SEVERE:
		next_band = BAND_SEVERE
	else:
		next_band = _max_capacity
	var to_next: float = (next_band - _current_load) / 1000.0
	tooltip_text = "Load: %.2f stone / %.2f max (%s — %s)\n%.2f stone to next band" % [
		stone_load, stone_max, _band_label, _speed_label, maxf(to_next, 0.0)]


func _update_tooltip_creature() -> void:
	var stone_load: float = _current_load / 1000.0
	var stone_normal: float = _normal_capacity / 1000.0
	var stone_max: float = _max_capacity / 1000.0
	tooltip_text = "Load: %.1f stone / %.1f normal / %.1f max (%s)" % [
		stone_load, stone_normal, stone_max, _band_label]


func _update_tooltip_vehicle() -> void:
	var stone_load: float = _current_load / 1000.0
	var stone_normal: float = _normal_capacity / 1000.0
	var stone_max: float = _max_capacity / 1000.0
	tooltip_text = "Load: %.1f stone / %.1f normal / %.1f max (%s)" % [
		stone_load, stone_normal, stone_max, _band_label]


func _process(delta: float) -> void:
	if _is_flashing:
		_flash_timer += delta
		if fmod(_flash_timer, 1.0) < 0.5:
			modulate.a = 1.0
		else:
			modulate.a = 0.4
		queue_redraw()
	elif modulate.a != 1.0:
		modulate.a = 1.0


func _draw() -> void:
	var bar_rect := Rect2(0, 2, size.x, BAR_HEIGHT)

	# Background.
	draw_rect(bar_rect, COLOR_BG)

	if _max_capacity <= 0:
		return

	if _mode == MODE_CHARACTER:
		_draw_character_bar(bar_rect)
	else:
		_draw_creature_bar(bar_rect)


func _draw_character_bar(bar_rect: Rect2) -> void:
	var w: float = bar_rect.size.x
	var y: float = bar_rect.position.y
	var h: float = bar_rect.size.y

	# Fill bar up to current load.
	var fill_frac: float = clampf(float(_current_load) / float(_max_capacity), 0.0, 1.0)
	var fill_w: float = w * fill_frac

	if fill_w > 0:
		# Draw colored segments.
		var bands := [
			{"threshold": BAND_LIGHT, "color": COLOR_GREEN},
			{"threshold": BAND_HEAVY, "color": COLOR_YELLOW},
			{"threshold": BAND_SEVERE, "color": COLOR_ORANGE},
			{"threshold": _max_capacity, "color": COLOR_RED},
		]
		var drawn_x := 0.0
		for band in bands:
			var band_end_frac: float = clampf(float(band["threshold"]) / float(_max_capacity), 0.0, 1.0)
			var band_end_x: float = w * band_end_frac
			var segment_end: float = minf(fill_w, band_end_x)
			if segment_end > drawn_x:
				draw_rect(Rect2(bar_rect.position.x + drawn_x, y, segment_end - drawn_x, h), band["color"])
			drawn_x = segment_end
			if drawn_x >= fill_w:
				break

		# Over-max: extra red past the bar (clamped visually).
		if _current_load > _max_capacity:
			draw_rect(Rect2(bar_rect.position.x, y, w, h), COLOR_RED)

	# Tick marks at band boundaries.
	var tick_positions := [BAND_LIGHT, BAND_HEAVY, BAND_SEVERE]
	if _max_capacity != BASE_MAX:
		tick_positions.append(_max_capacity)
	for threshold in tick_positions:
		var frac: float = clampf(float(threshold) / float(_max_capacity), 0.0, 1.0)
		var tx: float = bar_rect.position.x + w * frac
		draw_line(Vector2(tx, y), Vector2(tx, y + h), COLOR_TICK, 1.0)


func _draw_creature_bar(bar_rect: Rect2) -> void:
	var w: float = bar_rect.size.x
	var y: float = bar_rect.position.y
	var h: float = bar_rect.size.y

	if _max_capacity <= 0:
		return

	var fill_frac: float = clampf(float(_current_load) / float(_max_capacity), 0.0, 1.0)
	var fill_w: float = w * fill_frac
	var normal_frac: float = clampf(float(_normal_capacity) / float(_max_capacity), 0.0, 1.0)
	var normal_x: float = w * normal_frac

	if fill_w > 0:
		# Green up to normal, red past normal.
		var green_end: float = minf(fill_w, normal_x)
		if green_end > 0:
			draw_rect(Rect2(bar_rect.position.x, y, green_end, h), COLOR_GREEN)
		if fill_w > normal_x:
			draw_rect(Rect2(bar_rect.position.x + normal_x, y, fill_w - normal_x, h), COLOR_RED)

	# Over-max.
	if _current_load > _max_capacity:
		draw_rect(Rect2(bar_rect.position.x, y, w, h), COLOR_RED)

	# Tick at normal boundary.
	draw_line(Vector2(bar_rect.position.x + normal_x, y),
		Vector2(bar_rect.position.x + normal_x, y + h), COLOR_TICK, 1.0)


func _on_inventory_updated(character_id: String) -> void:
	if _mode == MODE_CHARACTER and character_id == _entity_id:
		_refresh_character()
