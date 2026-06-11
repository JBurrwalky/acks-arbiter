extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Specialists tab (gdd-specialists.md §7, dual-path 2026-06-11).
##
## Two sections on one scrolling page:
##   * Retained — specialists traveling with the active party (kind, name,
##     wage, hired-from, unpaid-months badge, Dismiss).
##   * Commissions — in-settlement services (service, settlement, subject,
##     status, Collect — enabled only while the active party is in the
##     commission's origin settlement).
##
## Status header aggregates retained count + monthly wages + open
## commissions. Empty state explains both paths and points at settlement
## guilds. Engine layer: SpecialistHireManager (retain) +
## SpecialistCommissionManager (commission), both landed.

const SUBSTATE_TAB_ID := "specialists"

# Notebook page is light parchment — dark ink per conventions §6.10.
const HEADING_COLOR := Color(0.09, 0.06, 0.03, 1.0)
const BODY_COLOR := Color(0.09, 0.06, 0.03, 1.0)
const DIM_COLOR := Color(0.34, 0.27, 0.19, 1.0)
const READY_COLOR := Color(0.16, 0.42, 0.16, 1.0)
const WARN_COLOR := Color(0.55, 0.25, 0.12, 1.0)

var _status_label: Label = null
var _retained_holder: VBoxContainer = null
var _commissions_holder: VBoxContainer = null
var _commission_manager: SpecialistCommissionManager = null


func _build_content() -> void:
	_commission_manager = SpecialistCommissionManager.new(CampaignRepository, EventBus)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", HEADING_COLOR)
	root.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	content.add_child(_section_header("Retained — traveling with the party"))
	_retained_holder = VBoxContainer.new()
	_retained_holder.add_theme_constant_override("separation", 4)
	content.add_child(_retained_holder)

	content.add_child(_section_header("Commissions — work underway in settlements"))
	_commissions_holder = VBoxContainer.new()
	_commissions_holder.add_theme_constant_override("separation", 4)
	content.add_child(_commissions_holder)

	_connect_signals()
	_refresh()


func _connect_signals() -> void:
	EventBus.specialist_hired.connect(_on_specialist_event)
	EventBus.specialist_dismissed.connect(_on_specialist_event)
	EventBus.specialist_wages_processed.connect(_on_specialist_event)
	EventBus.specialist_commissioned.connect(_on_specialist_event)
	EventBus.specialist_commission_collected.connect(_on_specialist_event)
	EventBus.active_party_changed.connect(_on_active_party_changed)


func _on_specialist_event(_party_id: String, _data: Dictionary) -> void:
	_refresh()


func _on_active_party_changed(_prev: String, _next: String) -> void:
	_refresh()


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var campaign_id: String = GameState.campaign_id
	var party_id: String = GameState.active_party_id
	for child in _retained_holder.get_children():
		child.queue_free()
	for child in _commissions_holder.get_children():
		child.queue_free()

	if campaign_id.is_empty() or party_id.is_empty():
		_status_label.text = "No active party."
		return

	var retained: Array = CampaignRepository.list_active_specialists(campaign_id, party_id)
	var commissions: Array = CampaignRepository.list_specialist_commissions(campaign_id, party_id)
	var now: int = Timekeeping.get_party_time(party_id)

	var wages_cp: int = 0
	for row: Dictionary in retained:
		wages_cp += int(row.get("monthly_wage_cp", 0))
	var open_commissions: int = 0
	var ready_commissions: int = 0
	for row: Dictionary in commissions:
		if int(row.get("collected", 0)) == 1:
			continue
		open_commissions += 1
		if SpecialistCommissionManager.is_ready(row, now):
			ready_commissions += 1

	_status_label.text = "%d retained  ·  Monthly wages: %s  ·  %d commission%s open%s" % [
		retained.size(),
		Currency.format_cost(wages_cp),
		open_commissions,
		"" if open_commissions == 1 else "s",
		(" (%d ready)" % ready_commissions) if ready_commissions > 0 else "",
	]

	if retained.is_empty():
		_retained_holder.add_child(_dim_label(
			"No retained specialists. Hire scouts or sages at a settlement guild — they travel with the party and assist in the field."))
	for row: Dictionary in retained:
		_retained_holder.add_child(_build_retained_row(row))

	if commissions.is_empty():
		_commissions_holder.add_child(_dim_label(
			"No commissions. Sages and alchemists at settlement guilds take work to order — pay up front, return when it's done."))
	for row: Dictionary in commissions:
		_commissions_holder.add_child(_build_commission_row(row, now))


# ---------------------------------------------------------------------------
# Retained rows
# ---------------------------------------------------------------------------

func _build_retained_row(row: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	var unpaid: int = int(row.get("unpaid_months", 0))
	name_label.text = "%s (%s)" % [
		str(row.get("name", "")),
		SpecialistCatalog.display_name(str(row.get("kind", ""))),
	]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", BODY_COLOR)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_label)

	var wage_label := Label.new()
	wage_label.text = "%s/mo" % Currency.format_cost(int(row.get("monthly_wage_cp", 0)))
	wage_label.add_theme_font_size_override("font_size", 12)
	wage_label.add_theme_color_override("font_color", BODY_COLOR)
	h.add_child(wage_label)

	var from_label := Label.new()
	from_label.text = "from %s" % str(row.get("settlement_id", "?"))
	from_label.add_theme_font_size_override("font_size", 11)
	from_label.add_theme_color_override("font_color", DIM_COLOR)
	h.add_child(from_label)

	if unpaid > 0:
		var unpaid_label := Label.new()
		unpaid_label.text = "UNPAID ×%d" % unpaid
		unpaid_label.add_theme_font_size_override("font_size", 11)
		unpaid_label.add_theme_color_override("font_color", WARN_COLOR)
		h.add_child(unpaid_label)

	var dismiss_btn := Button.new()
	dismiss_btn.text = "Dismiss"
	dismiss_btn.pressed.connect(
		_on_dismiss_pressed.bind(str(row.get("specialist_id", ""))))
	h.add_child(dismiss_btn)
	return h


func _on_dismiss_pressed(specialist_id: String) -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Dismiss this specialist? They are an at-will hire; no severance is owed."
	confirm.confirmed.connect(func():
		var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
		manager.dismiss(specialist_id, GameState.active_party_id)
	)
	add_child(confirm)
	confirm.popup_centered()


# ---------------------------------------------------------------------------
# Commission rows
# ---------------------------------------------------------------------------

func _build_commission_row(row: Dictionary, now: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)

	var collected: bool = int(row.get("collected", 0)) == 1
	var ready: bool = SpecialistCommissionManager.is_ready(row, now)

	var label := Label.new()
	var subject: String = str(row.get("subject", ""))
	label.text = "%s — %s%s" % [
		str(row.get("service_label", str(row.get("service_id", "")))),
		str(row.get("settlement_id", "?")),
		("  ·  \"%s\"" % subject) if not subject.is_empty() else "",
	]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", DIM_COLOR if collected else BODY_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	if collected:
		status_label.text = "Collected"
		status_label.add_theme_color_override("font_color", DIM_COLOR)
	elif ready:
		status_label.text = "READY"
		status_label.add_theme_color_override("font_color", READY_COLOR)
	else:
		var days_left: int = ceili(
			float(int(row.get("completes_at_round", 0)) - now)
			/ float(Timekeeping.ROUNDS_PER_DAY))
		status_label.text = "ready in %d day%s" % [days_left, "" if days_left == 1 else "s"]
		status_label.add_theme_color_override("font_color", DIM_COLOR)
	h.add_child(status_label)

	if not collected:
		var collect_btn := Button.new()
		collect_btn.text = "Collect"
		var here: bool = _current_settlement_id() == str(row.get("settlement_id", ""))
		collect_btn.disabled = not (ready and here)
		collect_btn.tooltip_text = "" if (ready and here) \
			else ("Not finished yet." if not ready else "Travel to %s to collect." % str(row.get("settlement_id", "")))
		collect_btn.pressed.connect(
			_on_collect_pressed.bind(str(row.get("commission_id", ""))))
		h.add_child(collect_btn)
	return h


func _on_collect_pressed(commission_id: String) -> void:
	var party_id: String = GameState.active_party_id
	var collector: String = _first_party_member_id(party_id)
	var result: Dictionary = _commission_manager.collect(
		commission_id, collector, _current_settlement_id(),
		Timekeeping.get_party_time(party_id))
	if not bool(result.get("ok", false)):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "settlement",
			"title": "Cannot Collect",
			"body": str(result.get("message", "")),
			"duration": 4.0,
		})
		return
	if str(result.get("result_kind", "")) == "report":
		var dialog := AcceptDialog.new()
		dialog.title = str(result.get("service_label", "Report"))
		dialog.dialog_text = str(result.get("result_payload", ""))
		add_child(dialog)
		dialog.popup_centered()
	else:
		EventBus.notification_requested.emit({
			"type": "success",
			"category": "settlement",
			"title": "Commission Collected",
			"body": "The finished work has been added to the party's inventory.",
			"duration": 4.0,
		})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Active party's current settlement id, or "" when not in a settlement.
## GameState.current_location_key format: "settlement:ID" (see game_state.gd).
func _current_settlement_id() -> String:
	var key: String = GameState.current_location_key
	if key.begins_with("settlement:"):
		return key.trim_prefix("settlement:")
	return ""


func _first_party_member_id(party_id: String) -> String:
	var members: Array = CampaignRepository.list_party_characters(party_id)
	if members.is_empty():
		return ""
	return str(members[0].get("id", ""))


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
