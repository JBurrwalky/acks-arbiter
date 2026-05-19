extends VBoxContainer

## Battle log viewer per gdd-army-warfare.md §7.4.
## Reads battle_log entries for a battle_id and renders them with
## Inspect-math tooltips: each row's payload_json is shown on hover as a
## structured breakdown (every modifier, every die roll, every cascade).
##
## Standalone scene — can be opened from the field_battle_panel's "Inspect"
## button or as a post-battle replay surface from the unified log.
##
## Public API:
##   display(battle_id: String)


const _ENTRY_SEPARATION := 2

var _battle_id: String = ""
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _header_label: Label = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	_header_label = Label.new()
	_header_label.text = "Battle Log"
	_header_label.add_theme_font_size_override("font_size", 16)
	add_child(_header_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", _ENTRY_SEPARATION)
	_scroll.add_child(_list)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(battle_id: String) -> void:
	_battle_id = battle_id
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _battle_id.is_empty():
		return
	var battle: Dictionary = BattleRepository.get_battle(_battle_id)
	if battle.is_empty():
		_header_label.text = "Battle Log — (battle not found)"
		return
	_header_label.text = "Battle Log — %s vs %s @ (%d, %d) — outcome: %s" % [
		_army_name(String(battle.get("attacker_army_id", ""))),
		_army_name(String(battle.get("defender_army_id", ""))),
		int(battle.get("hex_q", 0)),
		int(battle.get("hex_r", 0)),
		String(battle.get("outcome", "in progress")),
	]
	var entries: Array = BattleRepository.list_log_for_battle(_battle_id)
	for entry in entries:
		_list.add_child(_build_entry_row(entry))


# ---------------------------------------------------------------------------
# Entry rendering
# ---------------------------------------------------------------------------

func _build_entry_row(entry: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var seq := Label.new()
	seq.text = "[%d]" % int(entry.get("sequence_number", 0))
	seq.modulate = Color(0.6, 0.6, 0.6)
	seq.custom_minimum_size = Vector2(40, 0)
	hbox.add_child(seq)

	var phase := Label.new()
	phase.text = "T%d %s" % [int(entry.get("turn_number", 0)), String(entry.get("phase", ""))]
	phase.custom_minimum_size = Vector2(110, 0)
	phase.modulate = Color(0.8, 0.8, 0.8)
	hbox.add_child(phase)

	var event_label := Label.new()
	event_label.text = String(entry.get("event_type", ""))
	event_label.custom_minimum_size = Vector2(220, 0)
	event_label.modulate = _event_color(String(entry.get("event_type", "")))
	hbox.add_child(event_label)

	var math_btn := Button.new()
	math_btn.text = "Inspect math"
	math_btn.tooltip_text = _format_payload(String(entry.get("payload_json", "{}")))
	math_btn.flat = true
	math_btn.pressed.connect(_on_inspect_pressed.bind(String(entry.get("payload_json", "{}"))))
	hbox.add_child(math_btn)

	return hbox


func _format_payload(payload_json: String) -> String:
	## Per gdd-army-warfare.md §7.4 Inspect-math affordance: render the
	## payload in human-readable form. v1: pretty-print the JSON.
	var parsed: Variant = JSON.parse_string(payload_json)
	if parsed is Dictionary:
		var lines: Array = []
		for k in parsed:
			var v: Variant = parsed[k]
			var v_str: String = ""
			if v == null:
				v_str = "null"
			elif v is Dictionary or v is Array:
				v_str = JSON.stringify(v)
			else:
				v_str = str(v)
			lines.append("%s: %s" % [str(k), v_str])
		return "\n".join(lines)
	return payload_json


func _event_color(event_type: String) -> Color:
	if event_type == "battle_started" or event_type == "battle_ended":
		return Color(1.0, 0.85, 0.2)
	if event_type == "unit_destroyed":
		return Color(0.9, 0.4, 0.4)
	if event_type == "heroic_foray_declared" or event_type == "heroic_foray_resolved":
		return Color(0.6, 0.85, 1.0)
	if event_type == "morale_check_started" or event_type == "unit_morale_rolled":
		return Color(1.0, 0.6, 0.4)
	return Color(1, 1, 1)


# ---------------------------------------------------------------------------
# Inspect-math popup (2026-05-19 bucket-B item #44: print() replaced with an
# AcceptDialog showing the formatted payload).
# ---------------------------------------------------------------------------

func _on_inspect_pressed(payload_json: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Inspect math"
	dialog.dialog_text = _format_payload(payload_json)
	dialog.size = Vector2(520, 360)
	add_child(dialog)
	dialog.popup_centered()
	# Free the dialog when it closes so we don't accumulate orphaned popups
	# across repeated inspect-clicks.
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _army_name(army_id: String) -> String:
	if army_id.is_empty():
		return "?"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM armies WHERE id = ?", [army_id]):
		return "?"
	if CampaignRepository.db.query_result.is_empty():
		return "?"
	return String(CampaignRepository.db.query_result[0].get("name", "?"))
