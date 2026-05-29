extends VBoxContainer

## Bardic Patronage block UI (Phase 10A.3 — Bard-only Class-Specific surface).
##
## Per gdd-domain-tab.md §12.6 (rewritten 2026-05-11 per Q14). Surfaces the
## two Bard-specific class powers from acore_campaign_classes.xml:
##   - hireling_inspiration L5+ (passive Chronicles of Battle aura)
##   - hall L9+ (Solicit Followers active recruitment)
##
## Bards CAN train troops if they take Manual of Arms — that surfaces in the
## Garrison sub-tab (§8.2), NOT here.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CHRONICLES_AURA_LEVEL_MIN := 5
const SOLICIT_FOLLOWERS_LEVEL_MIN := 9


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _character_id: String = ""
var _domain_id: String = ""
var _party_id: String = ""

var _aura_card: VBoxContainer = null
var _solicit_card: VBoxContainer = null
var _history_card: VBoxContainer = null
var _note_card: VBoxContainer = null

var _solicit_launch_btn: Button = null
var _solicit_status_label: Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_aura_card = _make_card("Chronicles of Battle aura")
	_solicit_card = _make_card("Solicit Followers")
	_history_card = _make_card("Recruitment history")
	_note_card = _make_card("About Bardic Patronage")
	_render_note_once()
	_subscribe_signals()


func _exit_tree() -> void:
	_unsubscribe_signals()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func bind(character_id: String, domain_id: String, party_id: String = "") -> void:
	_character_id = character_id
	_domain_id = domain_id
	_party_id = party_id
	_refresh_all()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_render_aura()
	_render_solicit()
	_render_history()


func _render_note_once() -> void:
	_clear_card_body(_note_card)
	var note := Label.new()
	note.text = (
		"Bardic Patronage shows the two Bard-specific class-power activities: "
		+ "Chronicles of Battle aura (passive) and Solicit Followers (active). "
		+ "Bards who take the Manual of Arms proficiency can train troops via "
		+ "the Garrison sub-tab — that is a proficiency-gated activity, not "
		+ "a class one."
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.7)
	_note_card.add_child(note)


func _render_aura() -> void:
	_clear_card_body(_aura_card)
	if _character_id.is_empty():
		_aura_card.add_child(_dim_label("No active Bard."))
		return
	var character := _get_character(_character_id)
	var level: int = int(character.get("level", 1))
	if level < CHRONICLES_AURA_LEVEL_MIN:
		var locked := Label.new()
		locked.text = "Chronicles of Battle unlocks at Bard L%d (currently L%d)." % [
			CHRONICLES_AURA_LEVEL_MIN, level,
		]
		locked.modulate = Color(1, 1, 1, 0.6)
		locked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_aura_card.add_child(locked)
		return
	var description := Label.new()
	description.text = (
		"Passive: hirelings and mercenaries you have hired gain +1 morale "
		+ "when you are present in the same hex/army. Stacks with Charisma "
		+ "and other morale modifiers (RAW: acore_campaign_classes.xml "
		+ "§hireling_inspiration L569-575)."
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aura_card.add_child(description)


func _render_solicit() -> void:
	_clear_card_body(_solicit_card)
	if _character_id.is_empty():
		_solicit_card.add_child(_dim_label("No active Bard."))
		return
	var character := _get_character(_character_id)
	var level: int = int(character.get("level", 1))

	var description := Label.new()
	description.text = (
		"Solicit Followers (Ongoing, 1-3 weeks). On completion: 1d4+1 × 10 "
		+ "0-level mercenaries + 1d6 1st-3rd-level bard applicants come to "
		+ "apply for jobs and training at your hall. RAW: §hall L577-584."
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_solicit_card.add_child(description)

	# Launcher row.
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_solicit_status_label = Label.new()
	_solicit_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_solicit_status_label.modulate = Color(1, 1, 1, 0.7)
	hbox.add_child(_solicit_status_label)
	_solicit_launch_btn = Button.new()
	_solicit_launch_btn.text = "Launch Solicit Followers"
	_solicit_launch_btn.pressed.connect(_on_solicit_pressed)
	hbox.add_child(_solicit_launch_btn)
	_solicit_card.add_child(hbox)

	if level < SOLICIT_FOLLOWERS_LEVEL_MIN:
		_solicit_status_label.text = "Locked: requires Bard L%d (currently L%d)" % [
			SOLICIT_FOLLOWERS_LEVEL_MIN, level,
		]
		_solicit_launch_btn.disabled = true
	else:
		_solicit_status_label.text = "Ready (1-3 weeks at the bardic hall)"
		_solicit_launch_btn.disabled = false


func _render_history() -> void:
	_clear_card_body(_history_card)
	if _domain_id.is_empty():
		_history_card.add_child(_dim_label("No recruitment history yet."))
		return
	# Query recent bardic_recruitment ledger entries.
	var entries := CampaignRepository.list_ledger_entries(_domain_id)
	var bardic_entries: Array = []
	for entry: Dictionary in entries:
		if str(entry.get("subcategory", "")) == "bardic_recruitment":
			bardic_entries.append(entry)
	if bardic_entries.is_empty():
		_history_card.add_child(_dim_label("No solicitations yet."))
		return
	# Show most recent 5.
	bardic_entries.sort_custom(func(a, b): return int(a.get("calendar_day", 0)) > int(b.get("calendar_day", 0)))
	for i in range(min(5, bardic_entries.size())):
		var e: Dictionary = bardic_entries[i]
		var row := Label.new()
		row.text = "Day %d: %s" % [
			int(e.get("calendar_day", 0)),
			String(e.get("description", "(no description)")),
		]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_history_card.add_child(row)


# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

func _on_solicit_pressed() -> void:
	if _character_id.is_empty():
		return
	var executor := _get_activity_executor()
	if executor == null:
		push_warning("BardicPatronage: no executor available")
		return
	var scheduler := _get_scheduler()
	if scheduler == null:
		return
	var result := executor.launch(
		_character_id, "solicit_followers",
		"at_bardic_hall", _domain_id,
		{"wage_offered_gp": 0},
		scheduler, _party_id)
	if not bool(result.get("success", false)):
		push_warning("BardicPatronage: launch failed (%s)" % result.get("error", ""))


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.bard_followers_solicited.is_connected(_on_solicited):
		EventBus.bard_followers_solicited.connect(_on_solicited)


func _unsubscribe_signals() -> void:
	if EventBus.bard_followers_solicited.is_connected(_on_solicited):
		EventBus.bard_followers_solicited.disconnect(_on_solicited)


func _on_solicited(character_id: String, _mercs: int, _bards: int) -> void:
	if character_id == _character_id:
		_render_history()


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
	return vbox


func _clear_card_body(card: VBoxContainer) -> void:
	if card == null:
		return
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
