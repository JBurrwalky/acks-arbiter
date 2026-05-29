class_name CSTabActiveProjects
extends VBoxContainer

## Active Projects tab — Domain Phase 3 (gdd-character-tab.md §3.8).
##
## Read-only listing of every Ongoing-frequency activity the character
## currently has in progress, regardless of where it was launched from.
## Per-project card shows progress (ticks / required / absence / tolerance),
## status banding (ON TRACK / AMBER / RED), and Inspect-math + Abandon buttons.
##
## Subscribes to:
##   * EventBus.activity_launched
##   * EventBus.activity_tick_earned
##   * EventBus.activity_completed
##   * EventBus.activity_forfeited
##
## Empty state surfaces brief help text per §3.8.3.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _character_id: String = ""
var _content_holder: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_subscribe_signals()


func _exit_tree() -> void:
	_unsubscribe_signals()


# ---------------------------------------------------------------------------
# Public API (matches the cs_tab_*.display(bundle, registries) signature)
# ---------------------------------------------------------------------------

func display(bundle: CharacterBundle, _registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	if bundle == null or bundle.character == null:
		_add_text("No character data.")
		return

	_character_id = bundle.character.id

	var heading := Label.new()
	heading.text = "Active Projects"
	heading.add_theme_font_size_override("font_size", 16)
	add_child(heading)

	var hint := Label.new()
	hint.text = "Ongoing activities currently in progress. Travel away from a project's required " \
		+ "location consumes its tick-tolerance per gdd-domain-tab.md §15.1."
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	add_child(HSeparator.new())

	_content_holder = VBoxContainer.new()
	_content_holder.add_theme_constant_override("separation", 8)
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content_holder)

	_render_projects()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render_projects() -> void:
	if _content_holder == null:
		return
	for child in _content_holder.get_children():
		child.queue_free()
	if _character_id.is_empty():
		return

	var rows: Array = CampaignRepository.list_active_activity_states_for_character(_character_id)
	var ongoing: Array = []
	for row: Dictionary in rows:
		if str(row.get("frequency_type", "")) == "ongoing":
			ongoing.append(row)

	if ongoing.is_empty():
		var empty := Label.new()
		empty.text = "No ongoing projects. Activities launched from the Domain tab " \
			+ "(Decrees & Remote Orders), settlement panels, or stronghold UI will appear here."
		empty.modulate = Color(0.6, 0.6, 0.6)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content_holder.add_child(empty)
		return

	for row: Dictionary in ongoing:
		_content_holder.add_child(_make_project_card(row))


func _make_project_card(row: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)

	var def_id: String = str(row.get("activity_def_id", ""))
	var ticks: int = int(row.get("ticks_accumulated", 0))
	var required: int = int(row.get("ticks_required", 1))
	var absence: int = int(row.get("absence_accumulated", 0))
	var tolerance: int = ticks - absence
	var location_kind: String = str(row.get("location_kind", "anywhere"))
	var location_ref: String = str(row.get("location_ref", ""))

	var top := HBoxContainer.new()
	inner.add_child(top)
	var name_label := Label.new()
	name_label.text = _humanize(def_id)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var loc_label := Label.new()
	if location_kind == "anywhere":
		loc_label.text = "anywhere"
	else:
		loc_label.text = "%s: %s" % [location_kind, location_ref]
	loc_label.modulate = Color(0.7, 0.7, 0.7)
	top.add_child(loc_label)

	var progress := Label.new()
	progress.text = "Progress: %d / %d ticks · Absence: %d days · Tolerance: %d days" % [
		ticks, required, absence, tolerance,
	]
	inner.add_child(progress)

	var status_label := Label.new()
	var status: String = _classify_status(ticks, absence)
	status_label.text = "Status: %s" % status
	status_label.modulate = _color_for_status(status)
	inner.add_child(status_label)

	var btn_row := HBoxContainer.new()
	inner.add_child(btn_row)
	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect math"
	inspect_btn.pressed.connect(_on_inspect_pressed.bind(row))
	btn_row.add_child(inspect_btn)
	var abandon_btn := Button.new()
	abandon_btn.text = "Abandon project"
	abandon_btn.pressed.connect(_on_abandon_pressed.bind(str(row.get("id", ""))))
	btn_row.add_child(abandon_btn)

	return panel


# ---------------------------------------------------------------------------
# Status banding per §3.8.2
# ---------------------------------------------------------------------------

static func _classify_status(ticks: int, absence: int) -> String:
	if absence == 0:
		return "ON TRACK"
	if absence <= ticks - 1:
		return "AMBER"
	return "RED"


static func _color_for_status(status: String) -> Color:
	match status:
		"ON TRACK": return Color(0.5, 0.9, 0.5)
		"AMBER":    return Color(0.9, 0.8, 0.4)
		"RED":      return Color(0.9, 0.4, 0.4)
		_:          return Color(1, 1, 1)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_inspect_pressed(row: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "%s — Inspect math" % _humanize(str(row.get("activity_def_id", "")))
	var body := "Activity: %s\nFrequency: %s\nTicks: %d / %d\nAbsence: %d\nLocation: %s (%s)\nStarted day: %d" % [
		row.get("activity_def_id", "?"),
		row.get("frequency_type", "?"),
		int(row.get("ticks_accumulated", 0)),
		int(row.get("ticks_required", 1)),
		int(row.get("absence_accumulated", 0)),
		row.get("location_kind", "anywhere"),
		row.get("location_ref", ""),
		int(row.get("started_calendar_day", 0)),
	]
	dialog.dialog_text = body
	add_child(dialog)
	dialog.popup_centered()


func _on_abandon_pressed(activity_state_id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Abandon this project? Progress will be forfeit."
	dialog.confirmed.connect(_perform_abandon.bind(activity_state_id, dialog))
	add_child(dialog)
	dialog.popup_centered()


func _perform_abandon(activity_state_id: String, dialog: ConfirmationDialog) -> void:
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner == null:
		return
	var executor: ActivityTimeCostExecutor = session_runner.get_activity_executor() \
		if session_runner.has_method("get_activity_executor") else null
	var scheduler: EventScheduler = session_runner.get_scheduler() \
		if session_runner.has_method("get_scheduler") else null
	if executor != null:
		executor.abandon(activity_state_id, "player_cancel", scheduler)
	if dialog != null:
		dialog.queue_free()


# ---------------------------------------------------------------------------
# Live refresh
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.activity_launched.is_connected(_on_activity_event):
		EventBus.activity_launched.connect(_on_activity_event)
	if not EventBus.activity_tick_earned.is_connected(_on_activity_tick_event):
		EventBus.activity_tick_earned.connect(_on_activity_tick_event)
	if not EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.connect(_on_activity_completed)
	if not EventBus.activity_forfeited.is_connected(_on_activity_forfeited):
		EventBus.activity_forfeited.connect(_on_activity_forfeited)


func _unsubscribe_signals() -> void:
	if EventBus.activity_launched.is_connected(_on_activity_event):
		EventBus.activity_launched.disconnect(_on_activity_event)
	if EventBus.activity_tick_earned.is_connected(_on_activity_tick_event):
		EventBus.activity_tick_earned.disconnect(_on_activity_tick_event)
	if EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.disconnect(_on_activity_completed)
	if EventBus.activity_forfeited.is_connected(_on_activity_forfeited):
		EventBus.activity_forfeited.disconnect(_on_activity_forfeited)


func _on_activity_event(_state_id: String, character_id: String, _def_id: String) -> void:
	if character_id == _character_id:
		_render_projects()


func _on_activity_tick_event(_state_id: String, character_id: String, _ticks: int) -> void:
	if character_id == _character_id:
		_render_projects()


func _on_activity_completed(_state_id: String, character_id: String, _outcome: Dictionary) -> void:
	if character_id == _character_id:
		_render_projects()


func _on_activity_forfeited(_state_id: String, character_id: String, _reason: String) -> void:
	if character_id == _character_id:
		_render_projects()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = Color(0.7, 0.7, 0.7)
	add_child(lbl)


static func _humanize(activity_def_id: String) -> String:
	var parts := activity_def_id.split("_")
	var out: Array[String] = []
	for p: String in parts:
		out.append(p.capitalize())
	return " ".join(out)
