class_name HiringPanel
extends PanelContainer

## Phase G-2: Minimal henchman hiring UI, shown when the party enters a
## tavern or inn POI. Displays available henchmen (after search fee is paid),
## allows interview (reaction roll), and finalize hire.
##
## This panel is instantiated by SettlementExploreState and pushed as a
## modal overlay. It does NOT use LLM — Tier 0 template text only.

signal closed
signal hire_completed(character_id: String)

var _lifecycle: HenchmanLifecycleManager
var _pool_id: String = ""
var _settlement_id: String = ""
var _market_class: int = 6
var _current_week: int = 1
var _search_cost: int = 0
var _search_paid: bool = false
var _employer_id: String = ""
var _employer_cha_mod: int = 0
var _party_id: String = ""

# UI children (created in _ready)
var _title_label: Label
var _cost_label: Label
var _pay_button: Button
var _candidate_list: VBoxContainer
var _close_button: Button
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_update_view()


func setup(lifecycle: HenchmanLifecycleManager, pool_id: String,
		settlement_id: String, market_class: int, search_cost: int,
		current_week: int, employer_id: String, cha_mod: int,
		party_id: String) -> void:
	_lifecycle = lifecycle
	_pool_id = pool_id
	_settlement_id = settlement_id
	_market_class = market_class
	_search_cost = search_cost
	_current_week = current_week
	_employer_id = employer_id
	_employer_cha_mod = cha_mod
	_party_id = party_id
	if is_inside_tree():
		_update_view()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "Tavern — Henchman Hiring"
	vbox.add_child(_title_label)

	_cost_label = Label.new()
	vbox.add_child(_cost_label)

	_pay_button = Button.new()
	_pay_button.text = "Pay Search Fee"
	_pay_button.pressed.connect(_on_pay_pressed)
	vbox.add_child(_pay_button)

	_status_label = Label.new()
	vbox.add_child(_status_label)

	_candidate_list = VBoxContainer.new()
	vbox.add_child(_candidate_list)

	_close_button = Button.new()
	_close_button.text = "Leave"
	_close_button.pressed.connect(func(): closed.emit())
	vbox.add_child(_close_button)


func _update_view() -> void:
	if _cost_label == null:
		return
	_cost_label.text = "Search fee: %dgp (Market Class %s)" % [
		_search_cost, _roman(_market_class)]
	_pay_button.visible = not _search_paid
	_status_label.text = "" if _search_paid else "Pay the search fee to see available henchmen."

	for child in _candidate_list.get_children():
		child.queue_free()

	if not _search_paid or _lifecycle == null:
		return

	var candidates: Array = _lifecycle.get_available_this_week(_pool_id, _current_week)
	if candidates.is_empty():
		_status_label.text = "No henchmen available this week."
		return

	_status_label.text = "Week %d — %d candidates available:" % [_current_week, candidates.size()]
	for c in candidates:
		_add_candidate_row(c)


func _add_candidate_row(candidate: Dictionary) -> void:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s — %s Lv%d — %dgp/mo" % [
		candidate.get("name", "Unknown"),
		candidate.get("class_id", "?"),
		int(candidate.get("level", 1)),
		HenchmanTables.monthly_wage(int(candidate.get("level", 1))),
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)

	var interview_btn := Button.new()
	interview_btn.text = "Interview"
	var char_id: String = candidate.get("character_id", "")
	interview_btn.pressed.connect(_on_interview.bind(char_id, hbox))
	hbox.add_child(interview_btn)

	_candidate_list.add_child(hbox)


func _on_pay_pressed() -> void:
	_search_paid = true
	_pay_button.visible = false
	_update_view()


func _on_interview(character_id: String, row: HBoxContainer) -> void:
	if _lifecycle == null:
		return
	var result := _lifecycle.attempt_hire(_employer_cha_mod, 0)
	var outcome: String = result.get("outcome", "refuse")

	# Clear old buttons and show result.
	for child in row.get_children():
		if child is Button:
			child.queue_free()

	var result_label := Label.new()
	match outcome:
		HenchmanTables.HIRE_REFUSE_SLANDER:
			result_label.text = " — Insulted! (future rolls -1)"
		HenchmanTables.HIRE_REFUSE:
			result_label.text = " — Declined."
		HenchmanTables.HIRE_TRY_AGAIN:
			result_label.text = " — Wants better terms."
		HenchmanTables.HIRE_ACCEPT, HenchmanTables.HIRE_ACCEPT_ELAN:
			result_label.text = " — Accepted!" if outcome == HenchmanTables.HIRE_ACCEPT \
				else " — Enthusiastically accepted! (+1 morale)"
			var hire_btn := Button.new()
			hire_btn.text = "Finalize Hire"
			hire_btn.pressed.connect(_on_finalize.bind(
				character_id, result.get("morale_bonus", 0)))
			row.add_child(hire_btn)

	row.add_child(result_label)


func _on_finalize(character_id: String, morale_bonus: int) -> void:
	if _lifecycle == null:
		return
	var morale_base := HenchmanLoyaltyResolver.base_morale(_employer_cha_mod, false)
	_lifecycle.finalize_hire(character_id, _employer_id, _party_id,
		morale_base, morale_bonus, _settlement_id, 1, 1)
	_lifecycle._repo.mark_pool_member_hired(_pool_id, character_id)
	hire_completed.emit(character_id)
	_update_view()


func _roman(mc: int) -> String:
	match mc:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
		6: return "VI"
	return str(mc)
