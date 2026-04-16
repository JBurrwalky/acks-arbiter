class_name SettlementPanel
extends PanelContainer

## Settlement exploration panel — the primary interaction surface for city play.
##
## Shows a PoI list organized by district, travel controls (speed, route, trouble
## toggles), a travel indicator with progress/ETA, and a party status strip.
## Replaces the interactive settlement map as the main navigation UI.
##
## Attached to the session HUD CanvasLayer, occupying the right ~40% of screen.

# ---------------------------------------------------------------------------
# Signals — consumed by SettlementExploreState
# ---------------------------------------------------------------------------

signal poi_clicked(poi: Dictionary)
signal travel_cancelled()
signal speed_toggled(mode: String)          ## "commuting" or "meandering"
signal route_toggled(use_alleys: bool)
signal trouble_toggled(active: bool)
signal exit_requested()
signal activity_selected(activity_type: String, poi: Dictionary)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _map_data: SettlementMapData = null
var _party_node_id: int = -1
var _current_poi: Dictionary = {}
var _speed_mode: String = "commuting"
var _use_alleys: bool = false
var _looking_for_trouble: bool = false
var _party_size: int = 1
var _discovered_poi_ids: Array[String] = []

# UI nodes
var _header_label: Label
var _time_label: Label
var _poi_list: VBoxContainer
var _poi_scroll: ScrollContainer
var _travel_indicator: VBoxContainer
var _travel_progress: ProgressBar
var _travel_eta: Label
var _travel_cancel_btn: Button
var _nav_result_label: Label
var _speed_btn: Button
var _route_btn: Button
var _trouble_btn: Button
var _activity_area: VBoxContainer
var _status_strip: HBoxContainer


func _ready() -> void:
	_build_ui()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by SettlementExploreState after instantiation.
func setup(
	map_data: SettlementMapData,
	party_node_id: int,
	party_size: int,
	discovered_poi_ids: Array[String],
) -> void:
	_map_data = map_data
	_party_node_id = party_node_id
	_party_size = party_size
	_discovered_poi_ids = discovered_poi_ids
	_current_poi = map_data.get_poi_at_node(party_node_id)
	_update_header()
	_rebuild_poi_list()
	_update_travel_indicator(false)


# ---------------------------------------------------------------------------
# Public updates (called by state when events resolve)
# ---------------------------------------------------------------------------

## Updates the party's position and refreshes the PoI list distances.
func update_party_position(node_id: int) -> void:
	_party_node_id = node_id
	_current_poi = _map_data.get_poi_at_node(node_id) if _map_data != null else {}
	_rebuild_poi_list()
	_update_travel_indicator(false)


## Shows the travel indicator with progress info.
func show_travel_progress(block_count: int, total_rounds: int, blocks_remaining: int, eta_rounds: int) -> void:
	_update_travel_indicator(true, block_count, blocks_remaining, eta_rounds)


## Hides the travel indicator (travel complete or cancelled).
func hide_travel_progress() -> void:
	_update_travel_indicator(false)


## Shows a navigation throw result in the travel indicator.
func show_nav_result(result: Dictionary) -> void:
	if _nav_result_label == null:
		return
	if result.get("exempt", false):
		_nav_result_label.text = "Navigation: Known route"
	elif result.get("succeeded", false):
		_nav_result_label.text = "Navigation: %d + %d = %d (success)" % [
			result.get("roll", 0), result.get("modifier", 0), result.get("modified_total", 0)]
	else:
		_nav_result_label.text = "Navigation: %d + %d = %d (LOST!)" % [
			result.get("roll", 0), result.get("modifier", 0), result.get("modified_total", 0)]
		_nav_result_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))


## Updates discovered POI list and refreshes the display.
func update_discovered_pois(ids: Array[String]) -> void:
	_discovered_poi_ids = ids
	_rebuild_poi_list()


## Returns the activity area container for embedding sub-panels (shop, hiring).
func get_activity_area() -> VBoxContainer:
	return _activity_area


## Returns the current speed mode.
func get_speed_mode() -> String:
	return _speed_mode


## Returns whether alleys are enabled.
func get_use_alleys() -> bool:
	return _use_alleys


## Returns whether Looking for Trouble is active.
func get_looking_for_trouble() -> bool:
	return _looking_for_trouble


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Panel occupies right 40% of screen.
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	anchor_left = 0.6
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.9
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.11, 0.10, 0.92)
	bg.border_width_left = 2
	bg.border_color = Color(0.4, 0.35, 0.28)
	add_theme_stylebox_override("panel", bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	# --- Header ---
	_header_label = Label.new()
	_header_label.text = "Settlement"
	_header_label.add_theme_font_size_override("font_size", 18)
	_header_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	root_vbox.add_child(_header_label)

	_time_label = Label.new()
	_time_label.text = ""
	_time_label.add_theme_font_size_override("font_size", 12)
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	root_vbox.add_child(_time_label)

	# --- Toggle bar ---
	var toggle_bar := HBoxContainer.new()
	toggle_bar.add_theme_constant_override("separation", 6)
	root_vbox.add_child(toggle_bar)

	_speed_btn = Button.new()
	_speed_btn.text = "Commuting"
	_speed_btn.tooltip_text = "Toggle between Commuting (fast, nav checks) and Meandering (slow, safe, discovers POIs)"
	_speed_btn.pressed.connect(_on_speed_toggled)
	toggle_bar.add_child(_speed_btn)

	_route_btn = Button.new()
	_route_btn.text = "Streets Only"
	_route_btn.tooltip_text = "Toggle whether to use alley shortcuts (faster but more dangerous)"
	_route_btn.pressed.connect(_on_route_toggled)
	toggle_bar.add_child(_route_btn)

	_trouble_btn = Button.new()
	_trouble_btn.text = "Trouble: Off"
	_trouble_btn.tooltip_text = "Looking for Trouble: encounters on 5+ instead of 6+"
	_trouble_btn.pressed.connect(_on_trouble_toggled)
	toggle_bar.add_child(_trouble_btn)

	# --- Separator ---
	root_vbox.add_child(HSeparator.new())

	# --- Travel indicator (hidden when not traveling) ---
	_travel_indicator = VBoxContainer.new()
	_travel_indicator.add_theme_constant_override("separation", 4)
	_travel_indicator.visible = false
	root_vbox.add_child(_travel_indicator)

	var travel_header := Label.new()
	travel_header.text = "Traveling..."
	travel_header.add_theme_font_size_override("font_size", 14)
	travel_header.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	_travel_indicator.add_child(travel_header)

	_travel_progress = ProgressBar.new()
	_travel_progress.min_value = 0
	_travel_progress.max_value = 100
	_travel_progress.value = 0
	_travel_progress.custom_minimum_size.y = 16
	_travel_indicator.add_child(_travel_progress)

	_travel_eta = Label.new()
	_travel_eta.text = ""
	_travel_eta.add_theme_font_size_override("font_size", 12)
	_travel_indicator.add_child(_travel_eta)

	_nav_result_label = Label.new()
	_nav_result_label.text = ""
	_nav_result_label.add_theme_font_size_override("font_size", 11)
	_nav_result_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6))
	_travel_indicator.add_child(_nav_result_label)

	_travel_cancel_btn = Button.new()
	_travel_cancel_btn.text = "Cancel Travel"
	_travel_cancel_btn.pressed.connect(_on_cancel_travel)
	_travel_indicator.add_child(_travel_cancel_btn)

	var travel_sep := HSeparator.new()
	_travel_indicator.add_child(travel_sep)

	# --- PoI list (scrollable) ---
	_poi_scroll = ScrollContainer.new()
	_poi_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_poi_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(_poi_scroll)

	_poi_list = VBoxContainer.new()
	_poi_list.add_theme_constant_override("separation", 2)
	_poi_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_poi_scroll.add_child(_poi_list)

	# --- Activity area (populated when at a PoI) ---
	root_vbox.add_child(HSeparator.new())

	_activity_area = VBoxContainer.new()
	_activity_area.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_activity_area)

	# --- Party status strip (bottom) ---
	root_vbox.add_child(HSeparator.new())

	_status_strip = HBoxContainer.new()
	_status_strip.add_theme_constant_override("separation", 8)
	root_vbox.add_child(_status_strip)


# ---------------------------------------------------------------------------
# PoI list construction
# ---------------------------------------------------------------------------

func _rebuild_poi_list() -> void:
	if _poi_list == null or _map_data == null:
		return

	# Clear existing entries.
	for child in _poi_list.get_children():
		child.queue_free()

	# Calculate distances from current position to all POIs.
	var distances := SettlementTravelCalculator.calculate_all_poi_distances(
		_map_data, _party_node_id, not _use_alleys, _party_size)

	# Group POIs by district.
	var district_pois: Dictionary = {}  # district_id → Array[Dictionary]
	for poi in _map_data.pois:
		var dist_id: String = poi.get("district_id", "unknown")
		if not district_pois.has(dist_id):
			district_pois[dist_id] = []
		district_pois[dist_id].append(poi)

	# Build collapsible district sections.
	for district in _map_data.districts:
		var dist_id: String = district.get("id", "")
		var dist_name: String = district.get("name", dist_id)
		var pois_in_dist: Array = district_pois.get(dist_id, [])
		if pois_in_dist.is_empty():
			continue

		_add_district_section(dist_name, pois_in_dist, distances)


func _add_district_section(dist_name: String, pois: Array, distances: Dictionary) -> void:
	# District header (collapsible — for now, always expanded).
	var header := Button.new()
	header.text = "▼ %s" % dist_name
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	_poi_list.add_child(header)

	# POI entries.
	for poi in pois:
		_add_poi_entry(poi, distances)


func _add_poi_entry(poi: Dictionary, distances: Dictionary) -> void:
	var poi_id: String = poi.get("id", "")
	var is_discovered: bool = poi_id in _discovered_poi_ids
	var is_obvious: bool = poi.get("importance", "minor") == "major"

	# Show undiscovered POIs as "???".
	if not is_discovered and not is_obvious:
		var hidden := Label.new()
		hidden.text = "    ??? (Unknown location)"
		hidden.add_theme_font_size_override("font_size", 12)
		hidden.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		_poi_list.add_child(hidden)
		return

	var poi_name: String = poi.get("name", "???")
	var poi_type: String = poi.get("type", "")
	var is_current: bool = not _current_poi.is_empty() and _current_poi.get("id", "") == poi_id

	# Build the entry as a clickable button.
	var entry := Button.new()
	entry.flat = true
	entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	entry.add_theme_font_size_override("font_size", 12)

	if is_current:
		entry.text = "    ★ %s (%s) — Here" % [poi_name, poi_type]
		entry.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	else:
		var route: Dictionary = distances.get(poi_id, {})
		var block_count: int = route.get("block_count", 0)
		var commute_turns: int = _rounds_to_turns(route.get("commute_rounds", 0))
		var meander_turns: int = _rounds_to_turns(route.get("meander_rounds", 0))
		var alley_note: String = " (via alleys)" if route.get("has_alleys", false) else ""

		if _speed_mode == "commuting":
			entry.text = "    %s (%s) [%d blk%s — ~%d turns]" % [
				poi_name, poi_type, block_count, alley_note, commute_turns]
		else:
			entry.text = "    %s (%s) [%d blk%s — ~%d turns]" % [
				poi_name, poi_type, block_count, alley_note, meander_turns]
		entry.add_theme_color_override("font_color", Color(0.8, 0.77, 0.68))

	entry.pressed.connect(_on_poi_pressed.bind(poi))
	_poi_list.add_child(entry)


# ---------------------------------------------------------------------------
# Travel indicator
# ---------------------------------------------------------------------------

func _update_travel_indicator(
	traveling: bool,
	block_count: int = 0,
	blocks_remaining: int = 0,
	eta_rounds: int = 0,
) -> void:
	if _travel_indicator == null:
		return
	_travel_indicator.visible = traveling
	if traveling:
		var blocks_done: int = block_count - blocks_remaining
		_travel_progress.max_value = block_count
		_travel_progress.value = blocks_done
		var eta_turns: int = _rounds_to_turns(eta_rounds)
		_travel_eta.text = "%d / %d blocks — ETA ~%d turns" % [blocks_done, block_count, eta_turns]
	_nav_result_label.text = ""
	_nav_result_label.remove_theme_color_override("font_color")


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _update_header() -> void:
	if _header_label == null or _map_data == null:
		return
	_header_label.text = "%s (Market Class %s)" % [_map_data.name, _map_data.market_class]


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_poi_pressed(poi: Dictionary) -> void:
	poi_clicked.emit(poi)


func _on_cancel_travel() -> void:
	travel_cancelled.emit()


func _on_speed_toggled() -> void:
	if _speed_mode == "commuting":
		_speed_mode = "meandering"
		_speed_btn.text = "Meandering"
	else:
		_speed_mode = "commuting"
		_speed_btn.text = "Commuting"
	speed_toggled.emit(_speed_mode)
	_rebuild_poi_list()


func _on_route_toggled() -> void:
	_use_alleys = not _use_alleys
	_route_btn.text = "Use Alleys" if _use_alleys else "Streets Only"
	route_toggled.emit(_use_alleys)
	_rebuild_poi_list()


func _on_trouble_toggled() -> void:
	_looking_for_trouble = not _looking_for_trouble
	_trouble_btn.text = "Trouble: ON" if _looking_for_trouble else "Trouble: Off"
	if _looking_for_trouble:
		_trouble_btn.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	else:
		_trouble_btn.remove_theme_color_override("font_color")
	trouble_toggled.emit(_looking_for_trouble)


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

static func _rounds_to_turns(rounds: int) -> int:
	if rounds <= 0:
		return 0
	return ceili(float(rounds) / Timekeeping.ROUNDS_PER_TURN)
