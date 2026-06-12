class_name SpecialistHirePanel
extends PanelContainer

## Dual-path specialist hiring surface (gdd-specialists.md §6.2), opened from
## the settlement guild PoI's "Hire Specialists" activity. Per hireable kind:
##   * Retain — hire into the active party at the RAW monthly wage (billed in
##     arrears on the month tick, §3.5).
##   * Commission — buy a service: paid up front via PartyWallet, completes
##     at a calendar round, collected later in this settlement (Notebook
##     Specialists tab).
## Kinds owned by other subsystems render as informational rows (§4).
##
## Availability follows §6.1: deterministic monthly roll per (settlement,
## kind, month), minus engagements already made here this month.

signal closed

const HEADING_COLOR := Color(0.95, 0.92, 0.84, 1.0)
const BODY_COLOR := Color(0.88, 0.85, 0.78, 1.0)
const DIM_COLOR := Color(0.62, 0.58, 0.52, 1.0)

var _campaign_id: String = ""
var _party_id: String = ""
var _settlement_id: String = ""
var _market_class: int = 6
var _payer_character_id: String = ""

var _hire_manager: SpecialistHireManager = null
var _commission_manager: SpecialistCommissionManager = null

var _status_label: Label = null
var _kind_rows: VBoxContainer = null
## kind -> subject LineEdit (kinds with needs_subject services).
var _subject_edits: Dictionary = {}


func setup(
	campaign_id: String,
	party_id: String,
	settlement_id: String,
	market_class: int,
	payer_character_id: String,
) -> void:
	_campaign_id = campaign_id
	_party_id = party_id
	_settlement_id = settlement_id
	_market_class = market_class
	_payer_character_id = payer_character_id
	_hire_manager = SpecialistHireManager.new(CampaignRepository, EventBus)
	_commission_manager = SpecialistCommissionManager.new(CampaignRepository, EventBus)
	_build_ui()
	_refresh_rows()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	custom_minimum_size = Vector2(520, 420)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Specialists — Hire & Commission"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", HEADING_COLOR)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Retained specialists travel with the party (monthly wage). " \
		+ "Commissioned work is paid up front and collected here when complete."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	root.add_child(scroll)
	_kind_rows = VBoxContainer.new()
	_kind_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_kind_rows)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", BODY_COLOR)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): closed.emit())
	root.add_child(close_btn)


func _refresh_rows() -> void:
	for child in _kind_rows.get_children():
		child.queue_free()
	_subject_edits.clear()

	for kind in SpecialistCatalog.list_kinds():
		_kind_rows.add_child(_build_kind_block(kind))

	# §4: kinds owned by other subsystems — informational only.
	var owned_header := Label.new()
	owned_header.text = "Engaged elsewhere:"
	owned_header.add_theme_font_size_override("font_size", 11)
	owned_header.add_theme_color_override("font_color", DIM_COLOR)
	_kind_rows.add_child(owned_header)
	for info in SpecialistCatalog.OWNED_BY_INFO:
		var row := Label.new()
		row.text = "  %s — %s" % [str(info.get("label", "")), str(info.get("surface", ""))]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", DIM_COLOR)
		_kind_rows.add_child(row)


func _build_kind_block(kind: String) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)

	var available: int = _net_availability(kind)
	var def: Dictionary = SpecialistCatalog.get_definition(kind)

	var name_label := Label.new()
	name_label.text = "%s — %s/month   ·   %s" % [
		SpecialistCatalog.display_name(kind),
		Currency.format_cost(SpecialistCatalog.monthly_wage_cp(kind)),
		("%d available this month" % available) if available > 0 else "none available this month",
	]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", HEADING_COLOR)
	block.add_child(name_label)

	var notes := Label.new()
	notes.text = SpecialistCatalog.notes(kind)
	notes.add_theme_font_size_override("font_size", 11)
	notes.add_theme_color_override("font_color", DIM_COLOR)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(notes)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	block.add_child(buttons)

	if SpecialistCatalog.can_retain(kind):
		var retain_btn := Button.new()
		retain_btn.text = "Retain (travels with party)"
		retain_btn.disabled = available <= 0
		retain_btn.pressed.connect(_on_retain_pressed.bind(kind))
		buttons.add_child(retain_btn)

	var needs_subject := false
	for svc in SpecialistCatalog.services(kind):
		if bool(svc.get("needs_subject", false)):
			needs_subject = true
		var svc_btn := Button.new()
		var cost_cp: int = _commission_manager.service_cost_cp(kind, str(svc.get("id", "")))
		svc_btn.text = "%s — %s" % [str(svc.get("label", "")), Currency.format_cost(cost_cp)]
		svc_btn.disabled = available <= 0
		svc_btn.pressed.connect(_on_service_pressed.bind(kind, str(svc.get("id", ""))))
		buttons.add_child(svc_btn)

	if needs_subject:
		var subject_row := HBoxContainer.new()
		var subject_label := Label.new()
		subject_label.text = "Subject:"
		subject_label.add_theme_font_size_override("font_size", 11)
		subject_label.add_theme_color_override("font_color", BODY_COLOR)
		subject_row.add_child(subject_label)
		var edit := LineEdit.new()
		edit.placeholder_text = "Topic or question for the %s" % SpecialistCatalog.display_name(kind).to_lower()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		subject_row.add_child(edit)
		_subject_edits[kind] = edit
		block.add_child(subject_row)

	# Defensive: dual-path kinds with neither flag shouldn't exist; def kept
	# for future per-kind extras.
	if def.is_empty():
		block.visible = false
	return block


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_retain_pressed(kind: String) -> void:
	var now: int = Timekeeping.get_total_rounds()
	var sid: String = _hire_manager.hire(
		_campaign_id, _party_id, _settlement_id, kind, "", now)
	if sid.is_empty():
		_status_label.text = "Hiring failed."
		return
	_status_label.text = "%s retained — wages bill monthly." % SpecialistCatalog.display_name(kind)
	_refresh_rows()


func _on_service_pressed(kind: String, service_id: String) -> void:
	var subject: String = ""
	if _subject_edits.has(kind):
		subject = (_subject_edits[kind] as LineEdit).text
	var now: int = Timekeeping.get_total_rounds()
	var result: Dictionary = _commission_manager.commission(
		_campaign_id, _party_id, _settlement_id, kind, service_id,
		subject, _payer_character_id, now)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("message", "Commission failed."))
		return
	var svc: Dictionary = SpecialistCatalog.get_service(kind, service_id)
	_status_label.text = "Commissioned: %s. Return in %d day(s) to collect." % [
		str(svc.get("label", service_id)), int(svc.get("duration_days", 0))]
	_refresh_rows()


# ---------------------------------------------------------------------------
# Availability (§6.1)
# ---------------------------------------------------------------------------

const ROUNDS_PER_MONTH := Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY


func _net_availability(kind: String) -> int:
	var now: int = Timekeeping.get_total_rounds()
	@warning_ignore("integer_division")
	var month_index: int = now / ROUNDS_PER_MONTH
	var month_start: int = month_index * ROUNDS_PER_MONTH
	var gross: int = SpecialistCatalog.monthly_availability(
		kind, _market_class, _campaign_id, _settlement_id, month_index)
	var used: int = CampaignRepository.count_specialist_engagements_this_month(
		_campaign_id, _settlement_id, kind, month_start, month_start + ROUNDS_PER_MONTH)
	return maxi(0, gross - used)
