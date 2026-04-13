class_name CampRestScreen
extends CanvasLayer

## Camp/rest UI screen.
##
## Wilderness: shows watch assignment panel with 3 watch slots, then resolves
## encounters, then shows rest summary.
##
## Town: shows simplified "Rest at Inn" button, then summary.

signal watches_confirmed(assignments: Array, armed_sleepers: Array)
signal rest_completed

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)
const ACCENT_COLOR := Color(0.30, 0.65, 0.30, 1.0)
const SLOT_COLOR := Color(0.18, 0.15, 0.12, 0.8)

var _is_town: bool = false
var _content: VBoxContainer = null
var _phase: String = "assignment"  # "assignment" | "summary"


func _ready() -> void:
	layer = 50


func setup(is_town: bool) -> void:
	_is_town = is_town
	if _is_town:
		_build_town_rest_ui()
	else:
		_build_watch_assignment_ui()


# ---------------------------------------------------------------------------
# Watch Assignment UI (Wilderness)
# ---------------------------------------------------------------------------

func _build_watch_assignment_ui() -> void:
	_clear_content()
	_phase = "assignment"

	var bg := PanelContainer.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	bg.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(_content)

	var title := _heading("Make Camp")
	_content.add_child(title)

	_content.add_child(_body(
		"Assign each party member to one of three watches (4 hours each). "
		+ "Each character sleeps for 8 hours and is awake for 4 hours on their watch."))

	_content.add_child(_body(
		"Clerics and spellcasters automatically use their watch time for study and prayer."))

	# Watch slots (simplified — each is a VBoxContainer with character list).
	var watches_grid := HBoxContainer.new()
	watches_grid.add_theme_constant_override("separation", 16)
	_content.add_child(watches_grid)

	var watch_lists: Array[ItemList] = []
	for watch_idx in range(3):
		var watch_panel := _build_watch_slot(watch_idx, watch_lists)
		watches_grid.add_child(watch_panel)

	# Armed sleeper option.
	_content.add_child(_dim(
		"Characters may choose to sleep in armor. If so, they must pass a rest check "
		+ "or count as not having rested (no HP/spell recovery)."))

	# Buttons.
	var btn_bar := HBoxContainer.new()
	btn_bar.add_theme_constant_override("separation", 12)
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(btn_bar)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(func(): rest_completed.emit())
	btn_bar.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "Begin Rest"
	confirm_btn.add_theme_font_size_override("font_size", 14)
	confirm_btn.pressed.connect(func():
		# Auto-assign: distribute party members evenly across watches.
		var members := _get_party_member_ids()
		var assignments: Array = [[], [], []]
		for i in range(members.size()):
			assignments[i % 3].append(members[i])
		watches_confirmed.emit(assignments, [])
	)
	btn_bar.add_child(confirm_btn)


func _build_watch_slot(watch_idx: int, lists: Array) -> VBoxContainer:
	var slot := VBoxContainer.new()
	slot.custom_minimum_size = Vector2(200, 180)
	slot.add_theme_constant_override("separation", 6)

	var slot_bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_COLOR
	style.border_color = Color(0.35, 0.30, 0.22, 0.8)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	slot_bg.add_theme_stylebox_override("panel", style)
	slot.add_child(slot_bg)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	slot_bg.add_child(inner)

	var label := Label.new()
	label.text = "Watch %d" % (watch_idx + 1)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(label)

	var time_label := Label.new()
	var start_hour := watch_idx * 4
	time_label.text = "Hours %d-%d" % [start_hour, start_hour + 4]
	time_label.add_theme_font_size_override("font_size", 11)
	time_label.add_theme_color_override("font_color", DIM_COLOR)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(time_label)

	var item_list := ItemList.new()
	item_list.custom_minimum_size = Vector2(180, 100)
	item_list.auto_height = true
	inner.add_child(item_list)
	lists.append(item_list)

	return slot


# ---------------------------------------------------------------------------
# Town Rest UI
# ---------------------------------------------------------------------------

func _build_town_rest_ui() -> void:
	_clear_content()

	var bg := PanelContainer.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	bg.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(_content)

	_content.add_child(_heading("Rest in Town"))
	_content.add_child(_body(
		"The party rests for 12 hours. No watches are required in town. "
		+ "All characters recover HP and spell slots."))

	var btn := Button.new()
	btn.text = "Rest (12 hours)"
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(200, 44)
	btn.pressed.connect(func():
		watches_confirmed.emit([], [])
	)
	_content.add_child(btn)


# ---------------------------------------------------------------------------
# Rest Summary
# ---------------------------------------------------------------------------

func show_rest_summary(result: Dictionary) -> void:
	_clear_content()
	_phase = "summary"

	var bg := PanelContainer.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	UiSurfaceStyles.apply_framed_window_chrome(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	bg.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	margin.add_child(_content)

	_content.add_child(_heading("Rest Complete"))

	# Watch encounter summary.
	var watches: Array = result.get("watches", [])
	var encounters := 0
	for w in watches:
		if w.get("encounter", false):
			encounters += 1
	if encounters > 0:
		_content.add_child(_body(
			"Encounters during rest: %d" % encounters))
	else:
		_content.add_child(_body("The night passed uneventfully."))

	# Recovery summary.
	var recovery: Dictionary = result.get("rest_recovery", {})
	if not recovery.is_empty():
		_content.add_child(_heading("Recovery"))
		for char_id in recovery:
			var rec: Dictionary = recovery[char_id]
			var hp: int = rec.get("hp_recovered", 0)
			var spells: bool = rec.get("spells_recovered", false)
			var reason: String = rec.get("reason", "")
			var text := "HP +%d" % hp
			if spells:
				text += ", spells recovered"
			if not reason.is_empty():
				text += " (%s)" % reason
			_content.add_child(_body("  %s: %s" % [char_id.left(12), text]))

	# Rations.
	var rations: int = result.get("rations_consumed", 0)
	_content.add_child(_dim("Rations consumed: %d" % rations))

	# Failed sleepers.
	var failed: Array = result.get("failed_rest_ids", [])
	if not failed.is_empty():
		_content.add_child(_body(
			"Characters who failed to rest in armor: %d" % failed.size()))

	# Continue button.
	var btn := Button.new()
	btn.text = "Continue"
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(140, 38)
	btn.pressed.connect(func(): rest_completed.emit())
	_content.add_child(btn)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear_content() -> void:
	for child in get_children():
		child.queue_free()
	_content = null


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BODY_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _get_party_member_ids() -> Array:
	# Pull party member IDs from the current party.
	if GameState.party_id.is_empty():
		return []
	var members: Array = CampaignRepository.get_party_members(GameState.party_id)
	var ids: Array = []
	for m in members:
		ids.append(m.get("character_id", ""))
	return ids
