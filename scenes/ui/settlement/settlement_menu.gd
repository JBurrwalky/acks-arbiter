class_name SettlementMenu
extends PanelContainer

## Settlement exploration menu — pure menu overlay over the world view.
##
## V2 surface (gdd-settlement-exploration-ui.md v2 §2-3). Right ~40% of
## viewport, layer 10. World remains visible behind; auto-pause is owned by
## SettlementExploreState (this menu does not pause/resume the scheduler
## itself, only emits signals).
##
## No travel-progress bar, no commute/meander toggle, no streets/alleys
## toggle, no Looking-for-Trouble toggle. PoI list is fully visible (no
## hidden/discovered gating).

# ---------------------------------------------------------------------------
# Signals — consumed by SettlementExploreState
# ---------------------------------------------------------------------------

signal poi_clicked(poi: Dictionary)
signal close_requested()


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _settlement: SettlementMapData = null
var _current_poi_id: String = ""

# UI nodes (built in _ready / _build_ui)
var _header_label: Label
var _location_label: Label
var _close_button: Button
var _district_list: VBoxContainer
var _district_scroll: ScrollContainer
var _status_strip: HBoxContainer


func _ready() -> void:
	_build_ui()


# ---------------------------------------------------------------------------
# Setup / public API
# ---------------------------------------------------------------------------

## Called by SettlementExploreState after instantiation. Subsequent calls
## fully rehydrate the menu (per coding_conventions.md §13.3 reusable-panel-
## setup convention).
func setup(settlement: SettlementMapData, current_poi_id: String) -> void:
	_settlement = settlement
	_current_poi_id = current_poi_id
	_refresh_header()
	_rebuild_district_list()


## Updates the party's current PoI without rebuilding the entire UI; called
## when the SettlementContext changes (travel arrival).
func update_current_poi(poi_id: String) -> void:
	_current_poi_id = poi_id
	_refresh_header()
	_rebuild_district_list()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	custom_minimum_size = Vector2(440, 720)
	anchor_left = 0.6
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0

	# Apply shared vellum chrome (per coding_conventions.md §13.5). The text
	# theme installed here also covers Button-family controls used by the PoI
	# rows and district-section toggles.
	UiSurfaceStyles.apply_framed_window_chrome(self)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# --- Header row ---
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	root.add_child(header_row)

	var header_box := VBoxContainer.new()
	header_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_box)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 22)
	header_box.add_child(_header_label)

	_location_label = Label.new()
	_location_label.add_theme_font_size_override("font_size", 14)
	header_box.add_child(_location_label)

	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.tooltip_text = "Close menu (scheduler stays paused)"
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_button.pressed.connect(_on_close_pressed)
	header_row.add_child(_close_button)

	# --- District list (scrollable) ---
	_district_scroll = ScrollContainer.new()
	_district_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_district_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_district_scroll)

	_district_list = VBoxContainer.new()
	_district_list.add_theme_constant_override("separation", 4)
	_district_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_district_scroll.add_child(_district_list)

	# --- Party status strip (placeholder; future PartyStatusStrip component) ---
	_status_strip = HBoxContainer.new()
	_status_strip.add_theme_constant_override("separation", 8)
	_status_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_status_strip)


func _refresh_header() -> void:
	if _settlement == null:
		_header_label.text = ""
		_location_label.text = ""
		return
	_header_label.text = "%s (Class %s)" % [_settlement.name, _market_class_roman(_settlement.market_class)]

	var current_district := _current_district()
	var current_poi := _current_poi()
	var dist_name: String = current_district.get("name", "—") if not current_district.is_empty() else "—"
	var poi_name: String = current_poi.get("name", "—") if not current_poi.is_empty() else "—"
	_location_label.text = "%s — %s" % [dist_name, poi_name]


func _rebuild_district_list() -> void:
	for child in _district_list.get_children():
		child.queue_free()

	if _settlement == null:
		return

	var current_district_id: String = _current_district().get("id", "")

	for district in _settlement.districts:
		var section := _build_district_section(district, district.get("id", "") == current_district_id)
		_district_list.add_child(section)


func _build_district_section(district: Dictionary, expanded: bool) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)

	# Section header (collapsible toggle)
	var header_btn := Button.new()
	var glyph: String = "▼" if expanded else "▶"
	header_btn.text = "%s  %s" % [glyph, district.get("name", "?")]
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.flat = true
	header_btn.add_theme_font_size_override("font_size", 16)
	section.add_child(header_btn)

	# PoI list container
	var poi_box := VBoxContainer.new()
	poi_box.visible = expanded
	poi_box.add_theme_constant_override("separation", 2)
	section.add_child(poi_box)

	header_btn.pressed.connect(func():
		poi_box.visible = not poi_box.visible
		header_btn.text = "%s  %s" % ["▼" if poi_box.visible else "▶", district.get("name", "?")])

	for poi in district.get("pois", []):
		poi_box.add_child(_build_poi_row(poi))

	return section


func _build_poi_row(poi: Dictionary) -> Control:
	var row := Button.new()
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.tooltip_text = poi.get("type", "") + (" — entry/exit" if poi.get("is_entry_exit", false) else "")

	var marker: String = "★ " if poi.get("id", "") == _current_poi_id else "  "
	var travel_tag: String = _travel_cost_label(poi)
	var icon: String = _icon_for_type(poi.get("type", ""))

	row.text = "%s%s  %s   [%s]" % [marker, icon, poi.get("name", "?"), travel_tag]

	row.pressed.connect(func(): poi_clicked.emit(poi))
	return row


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _current_poi() -> Dictionary:
	if _settlement == null or _current_poi_id.is_empty():
		return {}
	return _settlement.get_poi(_current_poi_id)


func _current_district() -> Dictionary:
	var poi := _current_poi()
	if poi.is_empty() or _settlement == null:
		return {}
	return _settlement.get_district(poi.get("district_id", ""))


func _travel_cost_label(poi: Dictionary) -> String:
	if poi.get("id", "") == _current_poi_id:
		return "here"
	if _settlement == null:
		return ""
	if _settlement.same_district(_current_poi_id, poi.get("id", "")):
		return "10 min"
	return "1 hr"


func _icon_for_type(poi_type: String) -> String:
	# Glyph fallbacks until the icon registry lands.
	match poi_type:
		"tavern", "inn":
			return "🍺"
		"temple":
			return "✚"
		"shrine":
			return "✦"
		"shop":
			return "⚒"
		"market", "town_square":
			return "★"
		"guild_hall":
			return "⚜"
		"lord_keep":
			return "♚"
		"garrison":
			return "⚔"
		"gate":
			return "▣"
		"npc_residence":
			return "🏠"
		"undercity_entrance":
			return "▼"
		"bridge":
			return "═"
		"road_junction":
			return "✕"
		_:
			return "•"


func _market_class_roman(mc: int) -> String:
	match mc:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
		6: return "VI"
		_: return str(mc)


func _on_close_pressed() -> void:
	close_requested.emit()


# ---------------------------------------------------------------------------
# Input — Esc dismisses the menu (per gdd-ui-architecture.md §5.1)
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_requested.emit()
		accept_event()
