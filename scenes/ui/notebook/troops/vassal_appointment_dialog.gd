extends ConfirmationDialog

## Phase 8 — Vassal appointment dialog.
##
## Configurable for either a henchman vassal (auto-detected via
## `characters.character_type='henchman'`) or a non-henchman vassal (used by
## a future Phase 9+ realm-AI flow).
##
## For non-henchman vassals, automatically computes base loyalty modifier via
## TradeRangeResolver per RAW §non_henchman_vassals L392-397:
##   in trade range  → -2
##   outside range   → -4
##
## Public API:
##   configure_for_henchman(henchman_character_id: String) -> void
##   vassal_appointed (signal): emits the new vassal_assignment.id
##   appointment_cancelled (signal)
##
## NOTE: in v1 the liege is auto-selected as the active PC (NotebookState's
## active party leader). Multi-PC support / employer override is a follow-up.

signal vassal_appointed(assignment_id: String)
signal appointment_cancelled()

var _vassal_character_id: String = ""
var _liege_character_id: String = ""
var _is_henchman_vassal: bool = true
var _info_label: Label = null
var _loyalty_label: Label = null


func _ready() -> void:
	title = "Appoint vassal"
	get_ok_button().text = "Confirm"
	get_cancel_button().text = "Cancel"
	min_size = Vector2(420, 240)
	confirmed_signal_connect_ready()
	canceled.connect(_on_cancelled)


func confirmed_signal_connect_ready() -> void:
	# `confirmed` (the godot signal on ConfirmationDialog) is distinct from
	# our custom `confirmed(assignment_id)` signal. Connect the godot one
	# to a handler that does the work + emits ours.
	get_ok_button().pressed.connect(_on_confirm_pressed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func configure_for_henchman(henchman_character_id: String) -> void:
	_vassal_character_id = henchman_character_id
	_is_henchman_vassal = true
	_liege_character_id = _resolve_active_liege()
	_build_body()


# ---------------------------------------------------------------------------
# Body
# ---------------------------------------------------------------------------

func _build_body() -> void:
	# Replace any previously-built body.
	for child in get_children():
		if child is Label or child is VBoxContainer:
			child.queue_free()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)
	# 2026-05-19 bucket-B item #65: multi-PC liege selector. When the active
	# party has more than one PC, surface a dropdown so the user picks which
	# PC takes the vassalage. Default selection is whichever PC was returned
	# by _resolve_active_liege (the first one).
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	var pcs: Array = CampaignRepository.list_party_characters(pid) if not pid.is_empty() else []
	if pcs.size() > 1:
		var liege_row := HBoxContainer.new()
		liege_row.add_theme_constant_override("separation", 6)
		var liege_lbl := Label.new()
		liege_lbl.text = "Liege:"
		liege_lbl.custom_minimum_size = Vector2(60, 0)
		liege_row.add_child(liege_lbl)
		var liege_dd := OptionButton.new()
		liege_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var default_idx: int = 0
		for i in pcs.size():
			var pc: Dictionary = pcs[i]
			var pc_id: String = String(pc.get("id", ""))
			var pc_name: String = String(pc.get("name", pc_id.substr(0, 8)))
			liege_dd.add_item(pc_name, i)
			liege_dd.set_item_metadata(i, pc_id)
			if pc_id == _liege_character_id:
				default_idx = i
		liege_dd.select(default_idx)
		liege_dd.item_selected.connect(func(idx: int) -> void:
			var meta: Variant = liege_dd.get_item_metadata(idx)
			_liege_character_id = String(meta) if meta != null else ""
			if _info_label != null:
				_info_label.text = _info_text()
			if _loyalty_label != null:
				_loyalty_label.text = "Base loyalty modifier: %+d" % _compute_base_loyalty_modifier()
		)
		liege_row.add_child(liege_dd)
		vbox.add_child(liege_row)
	_info_label = Label.new()
	_info_label.text = _info_text()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(_info_label)
	_loyalty_label = Label.new()
	_loyalty_label.text = "Base loyalty modifier: %+d" % _compute_base_loyalty_modifier()
	_loyalty_label.modulate = Color(0.85, 0.85, 0.95)
	vbox.add_child(_loyalty_label)


func _info_text() -> String:
	var vassal_name: String = _character_name(_vassal_character_id)
	var liege_name: String = _character_name(_liege_character_id)
	var role: String = "henchman" if _is_henchman_vassal else "non-henchman noble"
	return "Appoint %s as %s vassal of %s.\n\nMonthly tribute will flow per realm size, and Favors & Duties rolls fire each month per RAW §favors_and_duties." % [
		vassal_name, role, liege_name]


# ---------------------------------------------------------------------------
# Loyalty modifier computation
# ---------------------------------------------------------------------------

func _compute_base_loyalty_modifier() -> int:
	if _is_henchman_vassal:
		return 0  # RAW: henchman vassals start at base 0.
	# Non-henchman: lookup vassal_domain + trade range to ruler's largest urban.
	var vassal_dom: Dictionary = _primary_domain_for_character(_vassal_character_id)
	if vassal_dom.is_empty():
		return -2  # No data — be lenient (in-range default).
	return TradeRangeResolver.compute_non_henchman_base_loyalty(
		String(vassal_dom.get("id", "")), _liege_character_id)


# ---------------------------------------------------------------------------
# Confirm / cancel
# ---------------------------------------------------------------------------

func _on_confirm_pressed() -> void:
	if _vassal_character_id.is_empty() or _liege_character_id.is_empty():
		emit_signal("appointment_cancelled")
		return
	# Guard against double-active vassalage (partial unique index would error).
	var existing: Dictionary = VassalRepository.get_active_assignment_for_vassal(_vassal_character_id)
	if not existing.is_empty():
		emit_signal("appointment_cancelled")
		return
	var calendar_day: int = _calendar_day()
	var vassal_dom: Dictionary = _primary_domain_for_character(_vassal_character_id)
	var data := {
		"campaign_id": _resolve_campaign_id(),
		"liege_character_id": _liege_character_id,
		"vassal_character_id": _vassal_character_id,
		"vassal_domain_id": String(vassal_dom.get("id", "")) if not vassal_dom.is_empty() else null,
		"assigned_calendar_day": calendar_day,
		"is_henchman_vassal": _is_henchman_vassal,
		"base_loyalty_modifier": _compute_base_loyalty_modifier(),
	}
	var id: String = VassalRepository.create_assignment(data)
	# Also update the vassal's domain (if any) to point its liege_domain_id at
	# the liege's primary domain — the realm graph apex walk depends on this.
	if not vassal_dom.is_empty():
		var liege_dom: Dictionary = _primary_domain_for_character(_liege_character_id)
		if not liege_dom.is_empty():
			CampaignRepository.db.query_with_bindings(
				"UPDATE domains SET liege_domain_id = ? WHERE id = ?",
				[String(liege_dom.get("id", "")), String(vassal_dom.get("id", ""))]
			)
	emit_signal("vassal_appointed", id)


func _on_cancelled() -> void:
	emit_signal("cancelled")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _resolve_active_liege() -> String:
	# v1: assume the active party's first PC is the liege. Multi-PC override
	# is a follow-up polish item.
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	if pid.is_empty():
		return ""
	var pcs: Array = CampaignRepository.list_party_characters(pid)
	if pcs.is_empty():
		return ""
	return String(pcs[0].get("id", ""))


func _resolve_campaign_id() -> String:
	if not GameState.has_method("get_campaign_id"):
		# Fall back via vassal's character record.
		if not _vassal_character_id.is_empty():
			if CampaignRepository.db.query_with_bindings(
				"SELECT campaign_id FROM characters WHERE id = ?",
				[_vassal_character_id]
			):
				if not CampaignRepository.db.query_result.is_empty():
					return String(CampaignRepository.db.query_result[0].get("campaign_id", ""))
		return ""
	return String(GameState.get_campaign_id())


func _primary_domain_for_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE owner_character_id = ? ORDER BY created_at LIMIT 1",
		[character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "(unknown)"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [character_id]):
		return "(unknown)"
	if CampaignRepository.db.query_result.is_empty():
		return "(unknown)"
	return String(CampaignRepository.db.query_result[0].get("name", "(unknown)"))


func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
