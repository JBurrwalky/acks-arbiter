extends ConfirmationDialog

## 5-step army formation wizard per gdd-army-warfare.md §3.1.
##
## v1 SCOPE: streamlined single-form layout (the GDD's "wizard" is presented
## as a single confirm dialog with grouped sections; future polish session
## may split into a multi-step Wizard control). Validates via
## ArmyComposer.compose() on Confirm.
##
## Officer-eligibility v1 simplification per the UI session plan: officer
## candidates are restricted to existing PCs + henchmen + appointable
## followers. Hireable mercenary officers (per gdd-army-warfare.md §3.3) are
## deferred until the settlement officer-market is wired.
##
## Public API:
##   set_owner_character(character_id: String)
##   popup_centered(...)  # inherited
##
## Signals:
##   army_formed(army_id: String)
##   cancelled()


signal army_formed(army_id: String)
signal cancelled()

const _SCROLL_HEIGHT := 360

var _owner_character_id: String = ""

var _name_edit: LineEdit = null
var _scale_option: OptionButton = null
var _stance_option: OptionButton = null
var _unit_check_boxes: Array = []  # Array[CheckBox]
var _unit_id_by_checkbox: Dictionary = {}
var _dc_option: OptionButton = null
var _henchman_options: Array = []  # candidate division-commander characters


func _ready() -> void:
	title = "Form Army"
	get_ok_button().text = "Confirm"
	get_cancel_button().text = "Cancel"
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_cancelled)
	_build_content()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_owner_character(character_id: String) -> void:
	_owner_character_id = character_id
	if is_inside_tree():
		_populate_options()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_content() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)

	# Step 1: Pick units.
	root.add_child(_section_header("Step 1 — Pick troop units (≥3)"))
	var units_scroll := ScrollContainer.new()
	units_scroll.custom_minimum_size = Vector2(0, _SCROLL_HEIGHT)
	units_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var units_vbox := VBoxContainer.new()
	units_vbox.name = "UnitsList"
	units_scroll.add_child(units_vbox)
	root.add_child(units_scroll)

	# Step 2: Unit scale.
	root.add_child(_section_header("Step 2 — Unit scale"))
	_scale_option = OptionButton.new()
	for scale in ["platoon", "company", "battalion", "brigade"]:
		_scale_option.add_item(scale.capitalize())
	root.add_child(_scale_option)

	# Step 3: Strategic stance.
	root.add_child(_section_header("Step 3 — Strategic stance"))
	_stance_option = OptionButton.new()
	for stance in ["offensive", "defensive", "evasive"]:
		_stance_option.add_item(stance.capitalize())
	_stance_option.selected = 1  # defensive default
	root.add_child(_stance_option)

	# Step 4: Division commander.
	root.add_child(_section_header("Step 4 — Division Commander (optional)"))
	_dc_option = OptionButton.new()
	_dc_option.add_item("(none — leader commands directly)")
	root.add_child(_dc_option)

	# Step 5: Name.
	root.add_child(_section_header("Step 5 — Name"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "(default: <Owner>'s First Host)"
	root.add_child(_name_edit)

	add_child(root)
	_populate_options()


func _populate_options() -> void:
	# Populate the units list.
	var units_vbox: VBoxContainer = get_node_or_null("VBoxContainer/ScrollContainer/UnitsList") as VBoxContainer
	if units_vbox == null:
		# Fallback: walk children to find the named list.
		units_vbox = _find_child_by_name(self, "UnitsList") as VBoxContainer
	if units_vbox == null:
		return
	for child in units_vbox.get_children():
		units_vbox.remove_child(child)
		child.queue_free()
	_unit_check_boxes.clear()
	_unit_id_by_checkbox.clear()

	var eligible: Array = _list_eligible_units()
	if eligible.is_empty():
		var hint := Label.new()
		hint.text = "(no unaligned-and-ungarrisoned troop_units owned by this character)"
		hint.modulate = Color(0.7, 0.7, 0.7)
		units_vbox.add_child(hint)
	else:
		for unit in eligible:
			var cb := CheckBox.new()
			cb.text = "%s × %d (BR %.2f) — %s" % [
				String(unit.get("troop_type", "?")),
				int(unit.get("count", 0)),
				float(unit.get("battle_rating", 0.0)),
				String(unit.get("source_type", "?")),
			]
			units_vbox.add_child(cb)
			_unit_check_boxes.append(cb)
			_unit_id_by_checkbox[cb] = String(unit.get("id", ""))

	# Populate the DC dropdown.
	if _dc_option != null:
		_dc_option.clear()
		_dc_option.add_item("(none — leader commands directly)")
		_henchman_options.clear()
		var henchmen: Array = _list_henchmen()
		for h in henchmen:
			_dc_option.add_item("%s (level %d)" % [String(h.get("name", "?")), int(h.get("level", 0))])
			_henchman_options.append(h)


# ---------------------------------------------------------------------------
# Confirm
# ---------------------------------------------------------------------------

func _on_confirmed() -> void:
	var selected_units: Array = []
	for cb in _unit_check_boxes:
		if cb.button_pressed:
			selected_units.append(String(_unit_id_by_checkbox.get(cb, "")))
	if selected_units.size() < 3:
		push_warning("Form Army: need ≥3 troop_units; got %d" % selected_units.size())
		cancelled.emit()
		return

	var unit_scale: String = ["platoon", "company", "battalion", "brigade"][_scale_option.selected]
	var stance: String = ["offensive", "defensive", "evasive"][_stance_option.selected]

	var dc_character_id: String = ""
	if _dc_option.selected > 0 and _dc_option.selected - 1 < _henchman_options.size():
		dc_character_id = String(_henchman_options[_dc_option.selected - 1].get("id", ""))

	var plan: Dictionary = {
		"campaign_id": _active_campaign_id(),
		"political_owner_id": _owner_character_id,
		"command_character_id": _owner_character_id,
		"unit_scale": unit_scale,
		"strategic_stance": stance,
		"formed_calendar_day": _calendar_day(),
		"leader_derivation": "pc",
		"division_commanders": [],
		"lieutenants": [],
		"units": [],
	}
	if not _name_edit.text.strip_edges().is_empty():
		plan["name"] = _name_edit.text.strip_edges()

	# Wire units under DC if specified, else under leader directly.
	# ArmyComposer expects unit.parent_character_id to resolve to a DC or LT.
	# When no DC is specified, we still need SOMETHING — for v1 we create an
	# implicit DC alias to the leader character (not RAW-strict but lets
	# small armies form without forcing a henchman).
	var parent_for_units: String = dc_character_id
	if not dc_character_id.is_empty():
		plan["division_commanders"] = [{"character_id": dc_character_id, "derivation_source": "henchman"}]
	else:
		# v1 fallback: leader leads the only division. Use leader_id as the
		# character_id of a "self-DC" that ArmyComposer resolves through.
		plan["division_commanders"] = [{"character_id": _owner_character_id, "derivation_source": "pc"}]
		parent_for_units = _owner_character_id

	for uid in selected_units:
		plan["units"].append({"troop_unit_id": uid, "parent_character_id": parent_for_units})

	var result: Dictionary = ArmyComposer.compose(plan)
	if bool(result.get("success", false)):
		army_formed.emit(String(result.get("army_id", "")))
	else:
		push_warning("ArmyComposer rejected plan: %s" % result.get("errors", []))
		cancelled.emit()


func _on_cancelled() -> void:
	cancelled.emit()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(0.85, 0.85, 0.85)
	return label


func _list_eligible_units() -> Array:
	if _owner_character_id.is_empty():
		return []
	var units: Array = TroopUnitRepository.list_active_for_owner(_owner_character_id)
	var eligible: Array = []
	for u in units:
		var unit_id: String = String(u.get("id", ""))
		var assn: Dictionary = ArmyRepository.get_active_assignment_for_unit(unit_id)
		if assn.is_empty():
			eligible.append(u)
	return eligible


func _list_henchmen() -> Array:
	if _owner_character_id.is_empty():
		return []
	# Henchmen are characters with character_type='henchman' and an owning
	# party that includes our PC. v1 simplification: list all henchmen in the
	# PC's campaign (no party-membership filter yet).
	var campaign_id: String = _active_campaign_id()
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, name, level FROM characters
		WHERE campaign_id = ? AND character_type = 'henchman'
		ORDER BY level DESC, name
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


func _active_campaign_id() -> String:
	if _owner_character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT campaign_id FROM characters WHERE id = ?", [_owner_character_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("campaign_id", ""))


func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day


func _find_child_by_name(node: Node, name: String) -> Node:
	for child in node.get_children():
		if String(child.name) == name:
			return child
		var found: Node = _find_child_by_name(child, name)
		if found != null:
			return found
	return null
