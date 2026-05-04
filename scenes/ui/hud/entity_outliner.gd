class_name EntityOutliner
extends PanelContainer

## Sidebar panel listing active entities and their scheduled orders.
##
## Shows each party/entity with: name, current activity, ETA, cancel button.
## Listens to EventBus.order_queued / order_cancelled and
## scheduler_event_resolved for live updates.
##
## The outliner is a Paradox-style "world overview" — essential for managing
## concurrent activities across multiple entities.

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const LABEL_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const BG_COLOR := Color(0.10, 0.08, 0.05, 0.92)
const BORDER_COLOR := Color(0.46, 0.33, 0.19, 1.0)
const FONT_SIZE := 11
const HEADING_FONT_SIZE := 13
const PANEL_WIDTH := 220

var _vbox: VBoxContainer = null
var _entity_rows: Dictionary = {}  # { entity_id: HBoxContainer }
var _scheduler_ref: EventScheduler = null


func _ready() -> void:
	add_to_group("hud_entity_outliner")  # H.0 — HudVisibilityController hides while notebook is open
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_left = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)

	# Header
	var header := Label.new()
	header.text = "Orders"
	header.add_theme_font_size_override("font_size", HEADING_FONT_SIZE)
	header.add_theme_color_override("font_color", HEADING_COLOR)
	_vbox.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", BORDER_COLOR)
	_vbox.add_child(sep)

	# Connect signals
	EventBus.order_queued.connect(_on_order_queued)
	EventBus.order_cancelled.connect(_on_order_cancelled)
	EventBus.scheduler_event_resolved.connect(_on_event_resolved)
	EventBus.scheduler_paused.connect(func(_r): _refresh())
	EventBus.scheduler_resumed.connect(func(): _refresh())


## Provide a scheduler reference so the outliner can query pending events.
func set_scheduler(scheduler: EventScheduler) -> void:
	_scheduler_ref = scheduler
	_refresh()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_order_queued(entity_id: String, event_type: String, fire_time: int) -> void:
	_upsert_row(entity_id, event_type, fire_time)


func _on_order_cancelled(entity_id: String, event_type: String) -> void:
	_remove_row(entity_id)
	_refresh()


func _on_event_resolved(event_type: String, _event_data: Dictionary) -> void:
	# An event resolved — refresh to remove completed orders.
	_refresh()


# ---------------------------------------------------------------------------
# Row management
# ---------------------------------------------------------------------------

func _upsert_row(entity_id: String, activity: String, fire_time: int) -> void:
	if _entity_rows.has(entity_id):
		_remove_row(entity_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# Entity name (truncated).
	var name_label := Label.new()
	name_label.text = _short_name(entity_id)
	name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	name_label.add_theme_color_override("font_color", LABEL_COLOR)
	name_label.custom_minimum_size = Vector2(70, 0)
	name_label.clip_text = true
	row.add_child(name_label)

	# Activity description.
	var activity_label := Label.new()
	activity_label.text = _format_activity(activity)
	activity_label.add_theme_font_size_override("font_size", FONT_SIZE)
	activity_label.add_theme_color_override("font_color", DIM_COLOR)
	activity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activity_label.clip_text = true
	row.add_child(activity_label)

	# ETA.
	var eta_label := Label.new()
	eta_label.text = _format_eta(fire_time)
	eta_label.add_theme_font_size_override("font_size", FONT_SIZE)
	eta_label.add_theme_color_override("font_color", DIM_COLOR)
	row.add_child(eta_label)

	_vbox.add_child(row)
	_entity_rows[entity_id] = row


func _remove_row(entity_id: String) -> void:
	if _entity_rows.has(entity_id):
		var row: HBoxContainer = _entity_rows[entity_id]
		if is_instance_valid(row):
			row.queue_free()
		_entity_rows.erase(entity_id)


## Rebuild all rows from the current scheduler state.
func _refresh() -> void:
	# Clear existing rows (except header/separator).
	for eid in _entity_rows.keys():
		_remove_row(eid)

	if _scheduler_ref == null:
		return

	# Group events by owner_id, show the earliest per owner.
	var seen: Dictionary = {}
	for event in _scheduler_ref.get_all_events():
		if seen.has(event.owner_id):
			continue
		seen[event.owner_id] = true
		_upsert_row(event.owner_id, event.event_type, event.fire_time)


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

func _short_name(entity_id: String) -> String:
	# Trim long hex IDs to something readable.
	if entity_id.length() > 12:
		return entity_id.substr(0, 8) + "..."
	return entity_id


func _format_activity(event_type: String) -> String:
	match event_type:
		"travel_leg":                return "Traveling"
		"camp_watch":                return "Watch"
		"camp_rest_complete":        return "Resting"
		"settlement_move":           return "Moving"
		"settlement_activity":       return "Activity"
		"dungeon_movement_tick":     return "Exploring"
		"dungeon_encounter_check":   return "On guard"
		"dungeon_light_tick":        return "Light"
		"dungeon_action_complete":   return "Action"
		"domain_monthly_tick":       return "Domain tick"
		_:                           return event_type.replace("_", " ").capitalize()


func _format_eta(fire_time: int) -> String:
	var current := Timekeeping.get_party_time(GameState.party_id) if not GameState.party_id.is_empty() else 0
	var delta: int = fire_time - current
	if delta <= 0:
		return "now"
	if delta < 60:
		return "%dr" % delta  # rounds
	if delta < 360:
		return "%dt" % (delta / 60)  # turns
	if delta < 8640:
		return "%dh" % (delta / 360)  # hours
	return "%dd" % (delta / 8640)  # days
