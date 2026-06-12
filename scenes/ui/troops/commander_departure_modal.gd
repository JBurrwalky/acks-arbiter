extends ConfirmationDialog

## Commander-departure enforcement modal per gdd-army-warfare.md §3.6.
##
## Surface: when a PC commander attempts to physically separate from their
## army (party split, leaving the hex independently, etc.), this modal blocks
## the action with three options:
##   1. Appoint a successor (officer-pool selector)
##   2. Disband the army
##   3. Cancel the departure
##
## Public API:
##   set_army(army_id: String, departing_character_id: String)
##   popup_centered(...)
##
## Signals:
##   successor_appointed(army_id: String, new_commander_id: String)
##   army_disbanded(army_id: String)
##   cancelled()


signal successor_appointed(army_id: String, new_commander_id: String)
signal army_disbanded_emitted(army_id: String)
signal cancelled()

var _army_id: String = ""
var _departing_character_id: String = ""

var _successor_option: OptionButton = null
var _successor_candidates: Array = []
var _appoint_btn: Button = null
var _disband_btn: Button = null
var _cancel_btn: Button = null


func _ready() -> void:
	title = "Commander Departure"
	# We supply our own three buttons — hide default ok/cancel.
	get_ok_button().visible = false
	get_cancel_button().visible = false
	canceled.connect(_on_cancelled)
	_build_content()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_army(army_id: String, departing_character_id: String) -> void:
	_army_id = army_id
	_departing_character_id = departing_character_id
	if is_inside_tree():
		_populate_successors()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_content() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)

	var explanation := Label.new()
	explanation.text = (
		"You are leaving your army. Per RAW (gdd-army-warfare.md §3.6), an " +
		"army cannot be left without a present commander. Choose:"
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(explanation)

	# Option 1: appoint a successor.
	var s_box := VBoxContainer.new()
	var s_header := Label.new()
	s_header.text = "Appoint successor (in-army officer or hireable mercenary officer)"
	s_box.add_child(s_header)
	_successor_option = OptionButton.new()
	s_box.add_child(_successor_option)
	_appoint_btn = Button.new()
	_appoint_btn.text = "Appoint Successor"
	_appoint_btn.pressed.connect(_on_appoint_pressed)
	s_box.add_child(_appoint_btn)
	root.add_child(s_box)

	# Option 2: disband.
	_disband_btn = Button.new()
	_disband_btn.text = "Disband Army"
	_disband_btn.pressed.connect(_on_disband_pressed)
	root.add_child(_disband_btn)

	# Option 3: cancel.
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel Departure"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	root.add_child(_cancel_btn)

	add_child(root)


func _populate_successors() -> void:
	if _successor_option == null:
		return
	_successor_option.clear()
	_successor_candidates.clear()
	# Per §3.6: candidates = qualifying in-army officers (excl. the departing
	# PC). v1 simplification: list all in-army officers other than the
	# departing character. The qualification check (level / HD per scale) is
	# done at appoint-time via ArmyValidator.
	var officers: Array = ArmyRepository.list_officers_for_army(_army_id)
	for officer in officers:
		var char_id: String = String(officer.get("character_id", ""))
		if char_id == _departing_character_id:
			continue
		_successor_candidates.append(officer)
		_successor_option.add_item("%s (%s)" % [
			_character_name(char_id),
			String(officer.get("rank", "")).replace("_", " "),
		])
	if _successor_candidates.is_empty():
		_successor_option.add_item("(no qualifying successor)")
		_appoint_btn.disabled = true
		_appoint_btn.tooltip_text = (
			"No qualifying successor in this army. Appoint requires an " +
			"in-army officer (or hireable mercenary officer at the army's " +
			"hex; mercenary-officer market is wired in a future session)."
		)
	else:
		_appoint_btn.disabled = false


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

func _on_appoint_pressed() -> void:
	if _successor_candidates.is_empty():
		return
	var idx: int = _successor_option.selected
	if idx < 0 or idx >= _successor_candidates.size():
		return
	var officer: Dictionary = _successor_candidates[idx]
	var new_commander_id: String = String(officer.get("character_id", ""))
	# Swap armies.command_character_id; mark the departing PC's officer row
	# as removed; create or update the successor's officer row to rank=army_leader.
	ArmyRepository.update_army(_army_id, {"command_character_id": new_commander_id})
	# Mark the departing officer row as former_commander.
	for o in ArmyRepository.list_officers_for_army(_army_id):
		if String(o.get("character_id", "")) == _departing_character_id:
			ArmyRepository.update_officer(String(o.get("id", "")), {
				"rank": "former_commander",
				"removed_calendar_day": _calendar_day(),
			})
			break
	# Promote the successor.
	ArmyRepository.update_officer(String(officer.get("id", "")), {"rank": "army_leader"})
	successor_appointed.emit(_army_id, new_commander_id)
	hide()


func _on_disband_pressed() -> void:
	var result: Dictionary = ArmyDisbander.disband(_army_id, "departure_no_successor", _calendar_day())
	if bool(result.get("success", false)):
		army_disbanded_emitted.emit(_army_id)
	hide()


func _on_cancel_pressed() -> void:
	cancelled.emit()
	hide()


func _on_cancelled() -> void:
	cancelled.emit()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "?"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [character_id]):
		return "?"
	if CampaignRepository.db.query_result.is_empty():
		return "?"
	return String(CampaignRepository.db.query_result[0].get("name", "?"))


func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
