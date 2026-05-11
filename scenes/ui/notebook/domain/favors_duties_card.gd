extends VBoxContainer

## Phase 8 — Per-vassal Favors & Duties card embedded in realm_sub_tab.gd
## per docs/domain-roadmap-corrected.md Phase 8.
##
## Renders:
##   - Header: vassal name + (henchman | non-henchman) badge
##   - Active favors list (each: type, magnitude, issued day, [Revoke] btn)
##   - Active duties list (each: type, magnitude, issued day, [Revoke] btn)
##   - "Recently resolved" history (last 6 obligations of any kind/status)
##
## Public API:
##   display(vassal_assignment_row: Dictionary)


const _MAX_HISTORY := 6

var _assignment: Dictionary = {}

var _header_label: Label = null
var _favors_list: VBoxContainer = null
var _duties_list: VBoxContainer = null
var _history_list: VBoxContainer = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build_header()
	_build_favors_section()
	_build_duties_section()
	_build_history_section()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(vassal_assignment_row: Dictionary) -> void:
	_assignment = vassal_assignment_row
	_render_header()
	_render_favors()
	_render_duties()
	_render_history()


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _build_header() -> void:
	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 14)
	add_child(_header_label)


func _render_header() -> void:
	var vassal_id: String = String(_assignment.get("vassal_character_id", ""))
	var name: String = _character_name(vassal_id)
	var is_henchman: bool = int(_assignment.get("is_henchman_vassal", 1)) == 1
	var badge: String = "henchman" if is_henchman else "non-henchman"
	_header_label.text = "%s   [%s]" % [name, badge]


# ---------------------------------------------------------------------------
# Favors / Duties sections
# ---------------------------------------------------------------------------

func _build_favors_section() -> void:
	var sub_header := Label.new()
	sub_header.text = "Active favors"
	sub_header.modulate = Color(0.8, 0.9, 1.0)
	add_child(sub_header)
	_favors_list = VBoxContainer.new()
	_favors_list.add_theme_constant_override("separation", 4)
	add_child(_favors_list)


func _build_duties_section() -> void:
	var sub_header := Label.new()
	sub_header.text = "Active duties"
	sub_header.modulate = Color(1.0, 0.9, 0.8)
	add_child(sub_header)
	_duties_list = VBoxContainer.new()
	_duties_list.add_theme_constant_override("separation", 4)
	add_child(_duties_list)


func _render_favors() -> void:
	_clear_children(_favors_list)
	var assn_id: String = String(_assignment.get("id", ""))
	if assn_id.is_empty():
		return
	var favors: Array = VassalObligationsRepository.list_active_favors_for_assignment(assn_id)
	if favors.is_empty():
		var empty := Label.new()
		empty.text = "  (none)"
		empty.modulate = Color(0.6, 0.6, 0.6)
		_favors_list.add_child(empty)
		return
	for f in favors:
		_favors_list.add_child(_build_obligation_row(f))


func _render_duties() -> void:
	_clear_children(_duties_list)
	var assn_id: String = String(_assignment.get("id", ""))
	if assn_id.is_empty():
		return
	var duties: Array = VassalObligationsRepository.list_active_duties_for_assignment(assn_id)
	if duties.is_empty():
		var empty := Label.new()
		empty.text = "  (none)"
		empty.modulate = Color(0.6, 0.6, 0.6)
		_duties_list.add_child(empty)
		return
	for d in duties:
		_duties_list.add_child(_build_obligation_row(d))


func _build_obligation_row(obligation: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var type_label := Label.new()
	type_label.text = "  %s" % String(obligation.get("type", "?"))
	type_label.custom_minimum_size = Vector2(180, 0)
	hbox.add_child(type_label)
	var mag_label := Label.new()
	var magnitude: int = int(obligation.get("magnitude", 0))
	if magnitude > 0:
		mag_label.text = "%d gp" % magnitude
	else:
		mag_label.text = "—"
	mag_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(mag_label)
	var day_label := Label.new()
	day_label.text = "Day %d" % int(obligation.get("issued_calendar_day", 0))
	day_label.custom_minimum_size = Vector2(80, 0)
	day_label.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(day_label)
	var revoke_btn := Button.new()
	revoke_btn.text = "Revoke"
	revoke_btn.flat = true
	revoke_btn.pressed.connect(_on_revoke_pressed.bind(String(obligation.get("id", ""))))
	hbox.add_child(revoke_btn)
	return hbox


func _on_revoke_pressed(obligation_id: String) -> void:
	if obligation_id.is_empty():
		return
	var obligation: Dictionary = VassalObligationsRepository.get_obligation(obligation_id)
	if obligation.is_empty():
		return
	VassalObligationsRepository.set_status(obligation_id, "revoked", 0)
	if EventBus.has_signal("obligation_revoked"):
		EventBus.emit_signal("obligation_revoked",
			obligation_id,
			String(obligation.get("kind", "")),
			String(obligation.get("type", "")))
	display(_assignment)  # re-render


# ---------------------------------------------------------------------------
# History section
# ---------------------------------------------------------------------------

func _build_history_section() -> void:
	var sub_header := Label.new()
	sub_header.text = "Recent history"
	sub_header.modulate = Color(0.85, 0.85, 0.85)
	add_child(sub_header)
	_history_list = VBoxContainer.new()
	_history_list.add_theme_constant_override("separation", 2)
	add_child(_history_list)


func _render_history() -> void:
	_clear_children(_history_list)
	var assn_id: String = String(_assignment.get("id", ""))
	if assn_id.is_empty():
		return
	var all: Array = VassalObligationsRepository.list_for_assignment(assn_id)
	if all.is_empty():
		var empty := Label.new()
		empty.text = "  (no obligations issued yet)"
		empty.modulate = Color(0.6, 0.6, 0.6)
		_history_list.add_child(empty)
		return
	var count: int = mini(_MAX_HISTORY, all.size())
	for i in range(count):
		var o: Dictionary = all[i]
		var lbl := Label.new()
		var status: String = String(o.get("status", ""))
		lbl.text = "  Day %d: %s [%s] (%s)" % [
			int(o.get("issued_calendar_day", 0)),
			String(o.get("type", "")),
			String(o.get("kind", "")),
			status,
		]
		match status:
			"revoked":
				lbl.modulate = Color(0.85, 0.6, 0.4)
			"defaulted":
				lbl.modulate = Color(1.0, 0.45, 0.45)
			"completed":
				lbl.modulate = Color(0.7, 0.85, 0.6)
			_:
				lbl.modulate = Color(0.85, 0.85, 0.85)
		_history_list.add_child(lbl)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "(unknown)"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [character_id]):
		return "(unknown)"
	if CampaignRepository.db.query_result.is_empty():
		return "(unknown)"
	return String(CampaignRepository.db.query_result[0].get("name", "(unknown)"))
