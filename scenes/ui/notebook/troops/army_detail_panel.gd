extends VBoxContainer

## Army detail panel (expanded view) per gdd-army-warfare.md §7.1.
## Shows the officer hierarchy, unit roster, supply-state, and a
## state-appropriate action bar (Activate / March / Disband / etc).
##
## Public API:
##   display(army_id: String)


const _SECTION_SPACING := 10

var _army_id: String = ""

var _hierarchy_box: VBoxContainer = null
var _roster_box: VBoxContainer = null
var _supply_box: VBoxContainer = null
var _action_bar: HBoxContainer = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", _SECTION_SPACING)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(army_id: String) -> void:
	_army_id = army_id
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _army_id.is_empty():
		return

	_hierarchy_box = _make_section("Officer Hierarchy")
	add_child(_hierarchy_box)
	_render_hierarchy()

	_roster_box = _make_section("Unit Roster")
	add_child(_roster_box)
	_render_roster()

	_supply_box = _make_section("Supply")
	add_child(_supply_box)
	_render_supply()

	_action_bar = HBoxContainer.new()
	_action_bar.add_theme_constant_override("separation", 8)
	add_child(_action_bar)
	_render_actions()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render_hierarchy() -> void:
	_clear_section(_hierarchy_box)
	var officers: Array = ArmyRepository.list_officers_for_army(_army_id)
	if officers.is_empty():
		_hierarchy_box.add_child(_dim_label("No officers assigned."))
		return
	# Group by rank.
	var by_rank: Dictionary = {"army_leader": [], "division_commander": [], "lieutenant": []}
	for o in officers:
		var rank: String = String(o.get("rank", ""))
		if not by_rank.has(rank):
			by_rank[rank] = []
		by_rank[rank].append(o)
	for rank in ["army_leader", "division_commander", "lieutenant"]:
		var officers_at: Array = by_rank.get(rank, [])
		if officers_at.is_empty():
			continue
		var header := Label.new()
		header.text = rank.replace("_", " ").capitalize()
		header.modulate = Color(0.8, 0.8, 0.8)
		_hierarchy_box.add_child(header)
		for officer in officers_at:
			var line := Label.new()
			line.text = "  • %s — Leadership %d, Strategic %+d, Morale Mod %+d" % [
				_character_name(String(officer.get("character_id", ""))),
				int(officer.get("leadership_ability", 4)),
				int(officer.get("strategic_ability", 0)),
				int(officer.get("morale_modifier", 0)),
			]
			_hierarchy_box.add_child(line)


func _render_roster() -> void:
	_clear_section(_roster_box)
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(_army_id)
	if assignments.is_empty():
		_roster_box.add_child(_dim_label("No units assigned."))
		return
	for assn in assignments:
		var unit: Dictionary = _troop_unit(String(assn.get("troop_unit_id", "")))
		if unit.is_empty():
			continue
		var line := Label.new()
		line.text = "  • %s × %d (BR %.2f) [%s]" % [
			String(unit.get("troop_type", "?")),
			int(unit.get("count", 0)),
			float(unit.get("battle_rating", 0.0)),
			String(assn.get("role", "line")),
		]
		_roster_box.add_child(line)


func _render_supply() -> void:
	_clear_section(_supply_box)
	var supply: Dictionary = ArmyRepository.get_supply_state(_army_id)
	if supply.is_empty():
		_supply_box.add_child(_dim_label("No supply state."))
		return
	var lines := [
		"Status: %s" % String(supply.get("supply_line_status", "—")).replace("_", " "),
		# Stockpile + weekly cost are cp; format_cost denominates.
		"Stockpile: %s" % Currency.format_cost(int(supply.get("current_stockpile_cp", 0))),
		"Weekly cost: %s" % Currency.format_cost(int(supply.get("weekly_supply_cost_cp", 0))),
		"Weighted line: %d hexes" % int(supply.get("supply_line_weighted_hexes", 0)),
		"Consecutive unsupplied weeks: %d" % int(supply.get("consecutive_unsupplied_weeks", 0)),
	]
	for line in lines:
		var label := Label.new()
		label.text = line
		_supply_box.add_child(label)


func _render_actions() -> void:
	for child in _action_bar.get_children():
		_action_bar.remove_child(child)
		child.queue_free()
	var army: Dictionary = ArmyRepository.get_army(_army_id)
	if army.is_empty():
		return
	var state: String = String(army.get("state", "assembling"))
	match state:
		"assembling":
			_add_action_button("Activate", _on_activate)
			_add_action_button("Disband", _on_disband)
		"encamped":
			_add_action_button("March…", _on_march_placeholder)
			_add_action_button("Disband", _on_disband)
		"marching", "battling", "withdrawing", "besieging", "requisitioning", "looting":
			var label := Label.new()
			label.text = "(army is %s — actions unavailable)" % state
			label.modulate = Color(0.7, 0.7, 0.7)
			_action_bar.add_child(label)
		"disbanded":
			var label := Label.new()
			label.text = "(army disbanded)"
			label.modulate = Color(0.6, 0.6, 0.6)
			_action_bar.add_child(label)


func _add_action_button(text: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(handler)
	_action_bar.add_child(btn)


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

func _on_activate() -> void:
	# Transition assembling → encamped.
	ArmyRepository.update_army(_army_id, {"state": "encamped"})
	display(_army_id)


func _on_disband() -> void:
	# v1: voluntary disband immediately. A confirm modal is recommended for
	# Phase 6 polish, but for the engine-side wire-up we rely on the existing
	# ArmyDisbander which logs the per-source release routing.
	var calendar_day: int = _calendar_day()
	var result: Dictionary = ArmyDisbander.disband(_army_id, "voluntary", calendar_day)
	if not bool(result.get("success", false)):
		push_warning("Disband failed: %s" % result.get("errors", []))
	display(_army_id)


func _on_march_placeholder() -> void:
	# v1 stub: marching is normally driven by the right-click on the wilderness
	# hex map (see army_marching_context_menu). The detail panel's March
	# button defers to that flow; clicking here just emits a message until
	# the wilderness UI session lands the destination picker.
	push_warning("March: use the wilderness hex map's right-click context menu to pick a destination.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 14)
	box.add_child(header)
	return box


func _clear_section(box: VBoxContainer) -> void:
	# Remove all but the header (first child).
	while box.get_child_count() > 1:
		var child = box.get_child(box.get_child_count() - 1)
		box.remove_child(child)
		child.queue_free()


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.65, 0.65, 0.65)
	return label


func _character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "?"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [character_id]):
		return "?"
	if CampaignRepository.db.query_result.is_empty():
		return "?"
	return String(CampaignRepository.db.query_result[0].get("name", "?"))


func _troop_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
