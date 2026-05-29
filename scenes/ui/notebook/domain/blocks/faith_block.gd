extends VBoxContainer

## Faith block UI (Phase 10A.2). Renders the divine-caster surface inside the
## Class-Specific sub-tab for any entity whose ClassBucketResolver returns
## "faith" as one of its buckets.
##
## Layout sections (top to bottom):
##   1. Congregants card — current count + projected next-month growth from
##      pending_growth_gp.
##   2. Divine Power card — current DP balance + this-week extraction status.
##   3. Consecrated Altars card — list of in-progress / completed altars.
##   4. Active Buffs card — surfaces any active consecrate_ruler buff window.
##   5. Activity launchers — 8 cards (one per divine activity from
##      data/activities/divine_category.json).
##
## Per gdd-domain-tab.md §12.2. Listens to congregants_changed /
## divine_power_changed / altar_consecrated / consecrate_*_resolved /
## missionary_dispatch_recorded signals to refresh on relevant changes.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DIVINE_ACTIVITY_IDS: Array[String] = [
	"dispatch_missionaries",
	"cast_charitable_spells",
	"consecrate_altar",
	"consecrate_fields",
	"consecrate_ruler",
	"extract_divine_power",
	"perform_blood_sacrifice",
	"perform_ceremonial_sacrifice",
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _character_id: String = ""
var _domain_id: String = ""
var _party_id: String = ""

var _congregants_card: VBoxContainer = null
var _dp_card: VBoxContainer = null
var _altars_card: VBoxContainer = null
var _buffs_card: VBoxContainer = null
var _activities_card: VBoxContainer = null

## activity_def_id → { launch_btn, status_label, definition }
var _activity_cards: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

	# 2026-05-19 bucket-B item #13: launch-result banner mirroring the
	# SyndicateBlock pattern. Sits above all cards; success notices
	# auto-dismiss after 4s, failures persist until next press or rebind.
	_launch_result_label = Label.new()
	_launch_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_launch_result_label.visible = false
	add_child(_launch_result_label)

	# _make_card already attaches the panel to self and returns the inner vbox
	# for body-content access. Do NOT call add_child(_*_card) again.
	_congregants_card = _make_card("Congregants")
	_dp_card = _make_card("Divine Power")
	_altars_card = _make_card("Consecrated Altars")
	_buffs_card = _make_card("Active Divine Effects")
	_activities_card = _make_card("Divine Activities")

	_build_activity_launchers()
	_subscribe_signals()


# 2026-05-19 bucket-B item #13: launch-result banner state + helpers.
var _launch_result_label: Label = null
const BANNER_AUTO_DISMISS_SECS := 4.0

func _show_launch_result(activity_label: String, result: Dictionary) -> void:
	if _launch_result_label == null:
		return
	var ok: bool = bool(result.get("success", false))
	var text: String
	if ok:
		text = "%s launched." % activity_label
		_launch_result_label.modulate = Color(0.55, 0.85, 0.55)
	else:
		var err: String = str(result.get("error", "unknown error"))
		text = "%s failed: %s" % [activity_label, err]
		_launch_result_label.modulate = Color(0.95, 0.55, 0.45)
	_launch_result_label.text = text
	_launch_result_label.visible = true
	if ok:
		var tree := get_tree()
		if tree != null:
			var timer := tree.create_timer(BANNER_AUTO_DISMISS_SECS)
			timer.timeout.connect(func() -> void:
				if _launch_result_label != null and _launch_result_label.text == text:
					_launch_result_label.text = ""
					_launch_result_label.visible = false
			)


func _exit_tree() -> void:
	_unsubscribe_signals()


# ---------------------------------------------------------------------------
# Public API — called by the Class-Specific sub-tab dispatcher
# ---------------------------------------------------------------------------

## Bind this block to a particular character (the divine caster) and domain
## (their ruled domain, if any). Re-renders all sections.
func bind(character_id: String, domain_id: String, party_id: String = "") -> void:
	_character_id = character_id
	_domain_id = domain_id
	_party_id = party_id
	_refresh_all()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_render_congregants()
	_render_divine_power()
	_render_altars()
	_render_buffs()
	_refresh_activity_cards()


func _render_congregants() -> void:
	_clear_card_body(_congregants_card)
	if _character_id.is_empty():
		_congregants_card.add_child(_dim_label("No active divine caster."))
		return
	var row: Dictionary = CampaignRepository.get_congregants(_character_id)
	if row.is_empty():
		_congregants_card.add_child(_dim_label("No congregation yet. Dispatch missionaries or cast charitable spells to attract congregants."))
		return
	var count: int = int(row.get("count", 0))
	var pending_cp: int = int(row.get("monthly_growth_pending_cp", 0))
	var line := Label.new()
	line.text = "%d congregants · %s accumulated for next-month growth (1d10 + CHA mod per 1,000 gp)" \
		% [count, Currency.format_cost(pending_cp)]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_congregants_card.add_child(line)


func _render_divine_power() -> void:
	_clear_card_body(_dp_card)
	if _character_id.is_empty():
		_dp_card.add_child(_dim_label("—"))
		return
	var row: Dictionary = CampaignRepository.get_character_divine_power(_character_id)
	var balance: int = int(row.get("divine_power_cp", 0))
	var last_extraction: int = int(row.get("last_extraction_calendar_day", 0))
	var balance_label := Label.new()
	balance_label.text = "Divine Power balance: %s" % Currency.format_cost(balance)
	_dp_card.add_child(balance_label)
	if last_extraction > 0:
		var since := Label.new()
		since.modulate = Color(1, 1, 1, 0.7)
		since.text = "Last extraction: calendar day %d (weekly cooldown — extract again in 7 days)" % last_extraction
		_dp_card.add_child(since)


func _render_altars() -> void:
	_clear_card_body(_altars_card)
	if _character_id.is_empty():
		_altars_card.add_child(_dim_label("—"))
		return
	var rows: Array = CampaignRepository.list_consecrated_altars_for_character(_character_id)
	if rows.is_empty():
		_altars_card.add_child(_dim_label("No altars consecrated yet. Use Consecrate Altar to dedicate a sacred site."))
		return
	for row: Dictionary in rows:
		var sub_panel := PanelContainer.new()
		sub_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sub_vbox := VBoxContainer.new()
		sub_panel.add_child(sub_vbox)
		var title := Label.new()
		title.text = "%s altar · %s invested · %d sq ft aura · %s" % [
			str(row.get("alignment", "?")).capitalize(),
			Currency.format_cost(int(row.get("cp_invested", 0)) + int(row.get("dp_substituted_cp", 0))),
			int(row.get("aura_size_sq_ft", 0)),
			str(row.get("status", "?")),
		]
		title.add_theme_font_size_override("font_size", 14)
		sub_vbox.add_child(title)
		var loc := Label.new()
		loc.modulate = Color(1, 1, 1, 0.7)
		loc.text = "Location: %s (%s)" % [
			str(row.get("location_kind", "?")),
			str(row.get("location_ref", "—")),
		]
		sub_vbox.add_child(loc)
		_altars_card.add_child(sub_panel)


func _render_buffs() -> void:
	_clear_card_body(_buffs_card)
	if _domain_id.is_empty():
		_buffs_card.add_child(_dim_label("No domain — no continuous divine effects active."))
		return
	var calendar_day: int = _calendar_day()
	var active: Array = CampaignRepository.list_active_divine_effects(_domain_id, calendar_day)
	if active.is_empty():
		_buffs_card.add_child(_dim_label("No active divine effects."))
		return
	for row: Dictionary in active:
		var kind: String = str(row.get("effect_kind", ""))
		var expires_at: int = int(row.get("expires_at_calendar_day", 0))
		var days_remaining: int = max(0, expires_at - calendar_day)
		var label := Label.new()
		label.text = "%s · expires in ~%d days (day %d)" % [
			_humanize_kind(kind), days_remaining, expires_at,
		]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_buffs_card.add_child(label)


# ---------------------------------------------------------------------------
# Activity launchers
# ---------------------------------------------------------------------------

func _build_activity_launchers() -> void:
	for id in DIVINE_ACTIVITY_IDS:
		var def: Dictionary = _get_definition(id)
		if def.is_empty():
			continue
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hbox)

		var name_label := Label.new()
		name_label.text = _humanize(id)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(name_label)

		var status_label := Label.new()
		status_label.modulate = Color(1, 1, 1, 0.7)
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(status_label)

		var launch_btn := Button.new()
		launch_btn.text = "Launch"
		launch_btn.pressed.connect(_on_launch_pressed.bind(id))
		hbox.add_child(launch_btn)

		_activities_card.add_child(row)
		_activity_cards[id] = {
			"definition": def,
			"status_label": status_label,
			"launch_btn": launch_btn,
		}


func _refresh_activity_cards() -> void:
	for id in _activity_cards.keys():
		var card: Dictionary = _activity_cards[id]
		var status_label: Label = card.get("status_label")
		var launch_btn: Button = card.get("launch_btn")
		var def: Dictionary = card.get("definition", {})

		if _character_id.is_empty():
			status_label.text = "(no caster)"
			launch_btn.disabled = true
			continue

		# Check Restricted cooldown.
		var cooldown_label := ""
		if String(def.get("frequency", "")) == "restricted":
			var executor := _get_activity_executor()
			# Naive cooldown probe — we read directly from the repository.
			var now: int = _scheduler_time()
			var until: int = CampaignRepository.get_restricted_cooldown(_character_id, id)
			if now < until:
				cooldown_label = " · on cooldown"
				launch_btn.disabled = true
			else:
				launch_btn.disabled = false
		else:
			launch_btn.disabled = false

		# Alignment gate for blood/ceremonial sacrifices.
		var alignment_req: String = String(def.get("alignment_restriction", ""))
		if not alignment_req.is_empty():
			var character := _get_character(_character_id)
			if String(character.get("alignment", "neutral")) != alignment_req:
				launch_btn.disabled = true
				cooldown_label += " · requires %s alignment" % alignment_req

		var freq: String = String(def.get("frequency", "singular"))
		status_label.text = "%s · %s%s" % [
			freq.capitalize(),
			String(def.get("activity_level", "?")).capitalize(),
			cooldown_label,
		]


func _on_launch_pressed(activity_def_id: String) -> void:
	var label: String = activity_def_id.replace("_", " ").capitalize()
	if _character_id.is_empty():
		_show_launch_result(label, {"success": false, "error": "no active character"})
		return
	var executor: ActivityTimeCostExecutor = _get_activity_executor()
	if executor == null:
		_show_launch_result(label, {"success": false, "error": "no executor"})
		return
	var scheduler: EventScheduler = _get_scheduler()
	if scheduler == null:
		_show_launch_result(label, {"success": false, "error": "no scheduler"})
		return
	var def: Dictionary = _get_definition(activity_def_id)
	var location_kind: String = String(def.get("location_kind", "anywhere"))
	var location_ref: String = "domain:%s" % _domain_id if not _domain_id.is_empty() else ""
	var params: Dictionary = _default_params_for(activity_def_id)
	var result: Dictionary = executor.launch(
		_character_id, activity_def_id, location_kind, location_ref,
		params, scheduler, _party_id)
	# 2026-05-19 bucket-B item #13: surface success/failure via banner instead
	# of push_warning. Mirrors the SyndicateBlock pattern.
	_show_launch_result(label, result)


## Default params for v1 launch. Full param-collection (gp committed, sacrifice
## targets, etc.) is deferred to a future polish that adds a per-activity launch
## dialog. v1 uses sensible defaults so the activity can be exercised end-to-end.
func _default_params_for(activity_def_id: String) -> Dictionary:
	match activity_def_id:
		"dispatch_missionaries":
			return {"gp_committed": 100}
		"cast_charitable_spells":
			return {"gp_value_total": 50, "spell_keys": []}
		"consecrate_altar":
			return {
				"gp_invested": 1000,
				"alignment": _caster_alignment(),
				"location_kind": "stronghold",
				"location_ref": _domain_id,
			}
		"consecrate_fields":
			return {}
		"consecrate_ruler":
			return {"ruler_character_id": _character_id}
		"extract_divine_power":
			return {}
		"perform_blood_sacrifice":
			return {"sacrifice_target_ids": [], "sacrifice_xp_values": [100]}
		"perform_ceremonial_sacrifice":
			return {"gp_value_total": 50}
		_:
			return {}


func _caster_alignment() -> String:
	var character := _get_character(_character_id)
	return String(character.get("alignment", "lawful"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_card(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title_label)
	add_child(panel)
	# Reparent panel into self via add_child (already in self). Reset to expose
	# the vbox for body appends.
	return vbox


func _clear_card_body(card: VBoxContainer) -> void:
	if card == null:
		return
	# Keep the first child (title); remove subsequent body children.
	var children := card.get_children()
	for i in range(1, children.size()):
		card.remove_child(children[i])
		children[i].queue_free()


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _humanize(activity_def_id: String) -> String:
	return activity_def_id.replace("_", " ").capitalize()


func _humanize_kind(effect_kind: String) -> String:
	match effect_kind:
		"consecrate_ruler_buff":
			return "Consecrate Ruler buff: +1 base morale, +1 vassal loyalty, best-of-two vagary rolls"
		"consecrate_fields_land_value":
			return "Consecrate Fields land-value bonus (next month)"
		_:
			return effect_kind.replace("_", " ").capitalize()


func _get_definition(activity_def_id: String) -> Dictionary:
	# Read from the catalog via a per-block-load JSON pass. We don't have a
	# direct ActivityCatalog handle here, so fall back to file lookup.
	var path := "res://data/activities/divine_category.json"
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var activities: Variant = (parsed as Dictionary).get("activities", [])
	if not (activities is Array):
		return {}
	for entry: Variant in activities:
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == activity_def_id:
			return entry as Dictionary
	return {}


func _get_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day


func _scheduler_time() -> int:
	var scheduler := _get_scheduler()
	if scheduler != null and scheduler.has_method("current_time"):
		return scheduler.current_time()
	return 0


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


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.congregants_changed.is_connected(_on_congregants_changed):
		EventBus.congregants_changed.connect(_on_congregants_changed)
	if not EventBus.divine_power_changed.is_connected(_on_dp_changed):
		EventBus.divine_power_changed.connect(_on_dp_changed)
	if not EventBus.altar_consecrated.is_connected(_on_altar_consecrated):
		EventBus.altar_consecrated.connect(_on_altar_consecrated)
	if not EventBus.consecrate_fields_resolved.is_connected(_on_fields_resolved):
		EventBus.consecrate_fields_resolved.connect(_on_fields_resolved)
	if not EventBus.consecrate_ruler_resolved.is_connected(_on_ruler_resolved):
		EventBus.consecrate_ruler_resolved.connect(_on_ruler_resolved)
	if not EventBus.missionary_dispatch_recorded.is_connected(_on_missionaries):
		EventBus.missionary_dispatch_recorded.connect(_on_missionaries)


func _unsubscribe_signals() -> void:
	if EventBus.congregants_changed.is_connected(_on_congregants_changed):
		EventBus.congregants_changed.disconnect(_on_congregants_changed)
	if EventBus.divine_power_changed.is_connected(_on_dp_changed):
		EventBus.divine_power_changed.disconnect(_on_dp_changed)
	if EventBus.altar_consecrated.is_connected(_on_altar_consecrated):
		EventBus.altar_consecrated.disconnect(_on_altar_consecrated)
	if EventBus.consecrate_fields_resolved.is_connected(_on_fields_resolved):
		EventBus.consecrate_fields_resolved.disconnect(_on_fields_resolved)
	if EventBus.consecrate_ruler_resolved.is_connected(_on_ruler_resolved):
		EventBus.consecrate_ruler_resolved.disconnect(_on_ruler_resolved)
	if EventBus.missionary_dispatch_recorded.is_connected(_on_missionaries):
		EventBus.missionary_dispatch_recorded.disconnect(_on_missionaries)


func _on_congregants_changed(character_id: String, _new_count: int, _delta: int) -> void:
	if character_id == _character_id:
		_render_congregants()
		_refresh_activity_cards()


func _on_dp_changed(character_id: String, _new_total: int, _delta: int) -> void:
	if character_id == _character_id:
		_render_divine_power()
		_refresh_activity_cards()


func _on_altar_consecrated(_altar_id: String, character_id: String, _cp_invested: int) -> void:
	if character_id == _character_id:
		_render_altars()


func _on_fields_resolved(domain_id: String, _success: bool, _delta: int) -> void:
	if domain_id == _domain_id:
		_render_buffs()


func _on_ruler_resolved(domain_id: String, _ruler_id: String, _success: bool, _expires: int) -> void:
	if domain_id == _domain_id:
		_render_buffs()


func _on_missionaries(character_id: String, _gp: int) -> void:
	if character_id == _character_id:
		_render_congregants()
