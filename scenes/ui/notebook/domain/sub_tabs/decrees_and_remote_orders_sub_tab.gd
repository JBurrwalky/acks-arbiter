extends VBoxContainer

## Decrees & Remote Orders sub-tab — Phase 3.
##
## Surfaces the small set of remote-capable domain activities per
## gdd-domain-tab.md §11.1 (administer_domain, issue_decree, manage_henchmen,
## conscript_troops, levy_militia, solicit_mercenaries, call_to_arms,
## oversee_investment). Each card lets the player launch the activity through
## the ActivityTimeCostExecutor; in-flight Ongoing activities show progress.
##
## Non-remote activities (hire_mercenaries, inspect_troops, train_troops,
## oversee/supervise_construction, military_campaign, repress_population)
## launch from their location-of-execution surfaces — see
## gdd-realtime-scheduler.md §4.8.4.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _domain_id: String = ""
var _domain_data: Dictionary = {}
var _ruler_id: String = ""

## activity_def_id -> Dictionary { card: Control, label: Label, action: Button }
var _cards: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

	var heading := Label.new()
	heading.text = "Decrees & Remote Orders"
	heading.add_theme_font_size_override("font_size", 18)
	add_child(heading)

	var hint := Label.new()
	hint.text = "Activities the ruler may dispatch from anywhere via seneschal / steward / chancellor. " \
		+ "Other activities launch from their location of execution per gdd-realtime-scheduler.md §4.8.4."
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_build_cards()
	_subscribe_signals()


func _exit_tree() -> void:
	_unsubscribe_signals()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_ruler_id = String(domain_data.get("owner_character_id", ""))
	_refresh_all_cards()


# ---------------------------------------------------------------------------
# Card construction
# ---------------------------------------------------------------------------

func _build_cards() -> void:
	var ids: Array = ActivityCatalog.REMOTE_CAPABLE_DOMAIN_IDS
	var catalog := ActivityCatalog.new()
	for id: String in ids:
		var def: Dictionary = catalog.get_definition(id)
		if def.is_empty():
			continue
		var card := _build_card(def)
		_cards[id] = card
		add_child(card["panel"])


func _build_card(def: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)

	var top_row := HBoxContainer.new()
	inner.add_child(top_row)
	var name_label := Label.new()
	name_label.text = _humanize(String(def.get("id", "")))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_label)
	var freq_label := Label.new()
	var freq: String = String(def.get("frequency", "singular"))
	var level: String = String(def.get("activity_level", "minor"))
	freq_label.text = "%s · %s" % [level.capitalize(), freq.capitalize()]
	freq_label.modulate = Color(0.6, 0.6, 0.6)
	top_row.add_child(freq_label)

	var status_label := Label.new()
	status_label.text = ""
	inner.add_child(status_label)

	var effect_label := Label.new()
	effect_label.text = "Effect: %s" % String(def.get("effect_summary", ""))
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(effect_label)

	var btn_row := HBoxContainer.new()
	inner.add_child(btn_row)
	var launch_btn := Button.new()
	launch_btn.text = "Launch"
	launch_btn.pressed.connect(_on_launch_pressed.bind(String(def.get("id", ""))))
	btn_row.add_child(launch_btn)
	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect math"
	inspect_btn.pressed.connect(_on_inspect_pressed.bind(String(def.get("id", ""))))
	btn_row.add_child(inspect_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel in-flight"
	cancel_btn.disabled = true
	cancel_btn.pressed.connect(_on_cancel_pressed.bind(String(def.get("id", ""))))
	btn_row.add_child(cancel_btn)

	# Phase 9C polish 2026-05-09: per-card extras for activity-specific params.
	# Currently only call_to_arms surfaces a magnitude_pct slider; extend this
	# pattern as other activities gain per-launch parameters.
	# 2026-05-19 bucket-A item #28: per-activity picker for issue_decree.
	var extras: Dictionary = {}
	if String(def.get("id", "")) == "call_to_arms":
		extras["magnitude_pct_slider"] = _build_magnitude_pct_slider(inner)
	elif String(def.get("id", "")) == "issue_decree":
		extras["decree_picker"] = _build_decree_picker(inner)

	return {
		"panel": panel,
		"def": def,
		"status_label": status_label,
		"launch_btn": launch_btn,
		"cancel_btn": cancel_btn,
		"extras": extras,
	}


## 2026-05-19 bucket-A item #28: per-activity picker for issue_decree.
##
## RAW allowed kinds: tax / liturgy / tithe (numeric rate in gp/family),
## religion_change (text), rename (text), other (free text).
## The picker shows a kind dropdown + a kind-appropriate input (SpinBox for
## the three rate kinds, LineEdit for the three text kinds). The visible
## input swaps when the dropdown selection changes. Returns a dict the
## launcher reads in _params_for.
func _build_decree_picker(inner: VBoxContainer) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	inner.add_child(row)
	var label := Label.new()
	label.text = "Decree:"
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	var kind_dd := OptionButton.new()
	# Order matches IssueDecreeHandler._ALLOWED_DECREE_KINDS plus a friendly
	# label per kind.
	kind_dd.add_item("Tax rate (gp/family)", 0)
	kind_dd.set_item_metadata(0, "tax")
	kind_dd.add_item("Liturgy rate (gp/family)", 1)
	kind_dd.set_item_metadata(1, "liturgy")
	kind_dd.add_item("Tithe rate (gp/family)", 2)
	kind_dd.set_item_metadata(2, "tithe")
	kind_dd.add_item("Religion change", 3)
	kind_dd.set_item_metadata(3, "religion_change")
	kind_dd.add_item("Rename domain", 4)
	kind_dd.set_item_metadata(4, "rename")
	kind_dd.add_item("Other (free text)", 5)
	kind_dd.set_item_metadata(5, "other")
	kind_dd.custom_minimum_size = Vector2(180, 0)
	row.add_child(kind_dd)
	# Numeric input (rates) — 0-10 gp/family per RAW.
	var rate_spin := SpinBox.new()
	rate_spin.min_value = 0
	rate_spin.max_value = 10
	rate_spin.step = 1
	rate_spin.value = 2  # default tax rate
	rate_spin.custom_minimum_size = Vector2(80, 0)
	row.add_child(rate_spin)
	# Text input (religion / rename / other).
	var text_edit := LineEdit.new()
	text_edit.placeholder_text = "value"
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.visible = false
	row.add_child(text_edit)
	# Swap input visibility by kind. Numeric kinds: tax / liturgy / tithe.
	# Text kinds: religion_change / rename / other.
	kind_dd.item_selected.connect(func(idx: int) -> void:
		var meta: Variant = kind_dd.get_item_metadata(idx)
		var k: String = String(meta) if meta != null else ""
		var is_numeric: bool = k in ["tax", "liturgy", "tithe"]
		rate_spin.visible = is_numeric
		text_edit.visible = not is_numeric
	)
	return {"kind_dd": kind_dd, "rate_spin": rate_spin, "text_edit": text_edit}


## Phase 9C polish 2026-05-09: magnitude_pct slider for call_to_arms.
## Range 50-100% (RAW minimum half garrison → full garrison). At 100% the
## obligation counts as 2 duties (per CallToArmsMuster.compute_duty_count).
func _build_magnitude_pct_slider(inner: VBoxContainer) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	inner.add_child(row)
	var label := Label.new()
	label.text = "Magnitude:"
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 50
	slider.max_value = 100
	slider.step = 10
	slider.value = 50
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "50% (1 duty)"
	value_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(value_label)
	# Live update of the value label as the slider moves.
	slider.value_changed.connect(func(v: float) -> void:
		var pct: int = int(v)
		var duties: int = 2 if pct >= 100 else 1
		value_label.text = "%d%% (%d duty%s)" % [pct, duties, "" if duties == 1 else "ies"]
	)
	return slider


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_all_cards() -> void:
	if _ruler_id.is_empty():
		_set_all_cards_empty_state()
		return
	var active: Array = CampaignRepository.list_active_activity_states_for_character(_ruler_id)
	var by_def: Dictionary = {}
	for row: Dictionary in active:
		by_def[str(row.get("activity_def_id", ""))] = row
	for id: String in _cards.keys():
		_refresh_card(id, by_def.get(id, {}))


func _refresh_card(activity_def_id: String, in_flight: Dictionary) -> void:
	var card: Dictionary = _cards.get(activity_def_id, {})
	if card.is_empty():
		return
	var status_label: Label = card["status_label"]
	var launch_btn: Button = card["launch_btn"]
	var cancel_btn: Button = card["cancel_btn"]

	if in_flight.is_empty():
		status_label.text = "Idle"
		launch_btn.disabled = false
		cancel_btn.disabled = true
		return
	var ticks: int = int(in_flight.get("ticks_accumulated", 0))
	var required: int = int(in_flight.get("ticks_required", 1))
	var absence: int = int(in_flight.get("absence_accumulated", 0))
	var tolerance: int = ticks - absence
	status_label.text = "In progress: %d / %d ticks · Absence: %d · Tolerance: %d" % [
		ticks, required, absence, tolerance,
	]
	launch_btn.disabled = true
	cancel_btn.disabled = false


func _set_all_cards_empty_state() -> void:
	for id: String in _cards.keys():
		var card: Dictionary = _cards[id]
		(card["status_label"] as Label).text = "(no ruler resolved)"
		(card["launch_btn"] as Button).disabled = true
		(card["cancel_btn"] as Button).disabled = true


# ---------------------------------------------------------------------------
# Launch / cancel
# ---------------------------------------------------------------------------

func _on_launch_pressed(activity_def_id: String) -> void:
	if _ruler_id.is_empty():
		return
	var executor: ActivityTimeCostExecutor = _get_activity_executor()
	if executor == null:
		push_warning("DecreesAndRemoteOrders: no executor available")
		return
	var scheduler: EventScheduler = _get_scheduler()
	if scheduler == null:
		return
	var params: Dictionary = _params_for(activity_def_id)
	var location_kind: String = String(_get_definition(activity_def_id).get("location_kind", "anywhere"))
	var location_ref: String = "domain:%s" % _domain_id
	var result: Dictionary = executor.launch(
		_ruler_id, activity_def_id, location_kind, location_ref,
		params, scheduler, _get_party_id())
	if not bool(result.get("success", false)):
		push_warning("DecreesAndRemoteOrders: launch failed (%s)" % result.get("error", ""))


func _on_cancel_pressed(activity_def_id: String) -> void:
	var rows: Array = CampaignRepository.list_active_activity_states_for_character(_ruler_id)
	for row: Dictionary in rows:
		if str(row.get("activity_def_id", "")) != activity_def_id:
			continue
		var executor: ActivityTimeCostExecutor = _get_activity_executor()
		if executor == null:
			return
		executor.abandon(str(row.get("id", "")), "player_cancel", _get_scheduler())
		return


func _on_inspect_pressed(activity_def_id: String) -> void:
	var def: Dictionary = _get_definition(activity_def_id)
	var dialog := AcceptDialog.new()
	dialog.title = "%s — RAW math" % _humanize(activity_def_id)
	var body := "Frequency: %s\nActivity level: %s\nDuration formula: %s\nEffect: %s\n\nRAW: %s" % [
		def.get("frequency", "?"),
		def.get("activity_level", "?"),
		def.get("duration_formula", "(none)"),
		def.get("effect_summary", "?"),
		def.get("raw_citation", "?"),
	]
	dialog.dialog_text = body
	add_child(dialog)
	dialog.popup_centered()


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.activity_launched.is_connected(_on_activity_event):
		EventBus.activity_launched.connect(_on_activity_event)
	if not EventBus.activity_tick_earned.is_connected(_on_activity_tick):
		EventBus.activity_tick_earned.connect(_on_activity_tick)
	if not EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.connect(_on_activity_completed)
	if not EventBus.activity_forfeited.is_connected(_on_activity_forfeited):
		EventBus.activity_forfeited.connect(_on_activity_forfeited)


func _unsubscribe_signals() -> void:
	if EventBus.activity_launched.is_connected(_on_activity_event):
		EventBus.activity_launched.disconnect(_on_activity_event)
	if EventBus.activity_tick_earned.is_connected(_on_activity_tick):
		EventBus.activity_tick_earned.disconnect(_on_activity_tick)
	if EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.disconnect(_on_activity_completed)
	if EventBus.activity_forfeited.is_connected(_on_activity_forfeited):
		EventBus.activity_forfeited.disconnect(_on_activity_forfeited)


func _on_activity_event(_state_id: String, character_id: String, _def_id: String) -> void:
	if character_id == _ruler_id:
		_refresh_all_cards()


func _on_activity_tick(_state_id: String, character_id: String, _ticks: int) -> void:
	if character_id == _ruler_id:
		_refresh_all_cards()


func _on_activity_completed(_state_id: String, character_id: String, _outcome: Dictionary) -> void:
	if character_id == _ruler_id:
		_refresh_all_cards()


func _on_activity_forfeited(_state_id: String, character_id: String, _reason: String) -> void:
	if character_id == _ruler_id:
		_refresh_all_cards()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _humanize(activity_def_id: String) -> String:
	var parts := activity_def_id.split("_")
	var out: Array[String] = []
	for p: String in parts:
		out.append(p.capitalize())
	return " ".join(out)


func _params_for(activity_def_id: String) -> Dictionary:
	# Default parameter set; UI sub-flows (e.g. issue_decree) supply richer
	# params via dedicated cards. The Phase 2 Overview sub-tab already exposes
	# the tax/liturgy/tithe steppers — issue_decree from the Decrees sub-tab
	# launches a no-op decree by default so the executor flow can be exercised.
	match activity_def_id:
		"administer_domain":
			var hex_count: int = CampaignRepository.get_domain_hexes(_domain_id).size()
			return {"hex_count": hex_count, "vassal_count": 0, "market_class": 6}
		"oversee_investment":
			return {"gp_committed": 1000, "domain_id": _domain_id}
		"issue_decree":
			# 2026-05-19 bucket-A item #28: read kind + value from the per-card
			# picker (decree_picker extras). Falls back to {kind:'other',
			# value:''} only when the picker isn't built (shouldn't happen).
			var ic_card: Dictionary = _cards.get(activity_def_id, {})
			var picker: Dictionary = ic_card.get("extras", {}).get("decree_picker", {})
			if picker.is_empty():
				return {"domain_id": _domain_id, "decree_kind": "other", "value": ""}
			var kind_dd: OptionButton = picker.get("kind_dd")
			var meta: Variant = kind_dd.get_item_metadata(kind_dd.selected) if kind_dd != null and kind_dd.selected >= 0 else "other"
			var kind: String = String(meta) if meta != null else "other"
			var is_numeric: bool = kind in ["tax", "liturgy", "tithe"]
			var value: Variant
			if is_numeric:
				# rate_spin reads gp/family (RAW-facing units); IssueDecreeHandler
				# expects cp/family (matches tax_rate_cp_per_family et al. and the
				# RulerActionCatalog "VALUE IS CP" contract) — convert at dispatch.
				var spin: SpinBox = picker.get("rate_spin")
				value = int(spin.value) * 100 if spin != null else 0
			else:
				var le: LineEdit = picker.get("text_edit")
				value = le.text if le != null else ""
			return {"domain_id": _domain_id, "decree_kind": kind, "value": value}
		"call_to_arms":
			# Phase 9C polish 2026-05-09: read magnitude_pct from the per-card slider.
			var mag_pct: int = 50
			var card: Dictionary = _cards.get(activity_def_id, {})
			var extras: Dictionary = card.get("extras", {})
			var slider: HSlider = extras.get("magnitude_pct_slider", null)
			if slider != null:
				mag_pct = clampi(int(slider.value), 50, 100)
			return {"domain_id": _domain_id, "magnitude_pct": mag_pct}
		_:
			return {}


func _get_definition(activity_def_id: String) -> Dictionary:
	var card: Dictionary = _cards.get(activity_def_id, {})
	return card.get("def", {})


func _get_activity_executor() -> ActivityTimeCostExecutor:
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner != null and session_runner.has_method("get_activity_executor"):
		return session_runner.get_activity_executor()
	return null


func _get_scheduler() -> EventScheduler:
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner != null and session_runner.has_method("get_scheduler"):
		return session_runner.get_scheduler()
	return null


func _get_party_id() -> String:
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner != null and session_runner.has_method("get_party_id"):
		return session_runner.get_party_id()
	return ""
