extends VBoxContainer

## Magical Research block UI (Phase 10B.1a — shell). Renders the arcane /
## Lightblessed Wonderworker surface inside the Class-Specific sub-tab for
## any entity whose ClassBucketResolver returns "magical_research" as one of
## its buckets.
##
## Layout sections (top to bottom):
##   1. Header banner — current Magic Research Throw target reference + INT
##      modifier + Magical Engineering proficiency rank (read-only summary).
##   2. Library status card — list of libraries owned by the character.
##   3. Workshop status card — list of workshops.
##   4. In-progress projects card — magic_research_projects with status='in_progress'.
##   5. Apprentices & Aspirants card — followers with source_kind in
##      {aspirant, class_follower (mage flavor)} for this owner. Shows
##      promotion timers per Q20 [RESOLVED 2026-05-11] (universal 4-month
##      timer to single d20 + ability_mod throw, 14+ promotes to 1st level).
##   6. Activity launchers — 8 cards (per Q16 [RESOLVED 2026-05-11]: separate
##      launcher card per target type for research_magic; rewrite/replace/
##      scribe_spell and manage_assistant as their own cards). All disabled
##      in 10B.1a; each becomes live as its wave's handler lands per the
##      phase-10-plan wave-split.
##
## Per gdd-domain-tab.md §12.4 (Magical Research block UI) + §12.7
## (Lightblessed dual-list polish — for that class, the research-target picker
## allows arcane OR cleric divine spell list per Q2 / roadmap RESOLVED).
##
## Wave-by-wave wiring plan (kept here for reference; remove as each wave
## lands):
##   10B.1b — enable launch buttons on: research_spell, rewrite_spell,
##            replace_spell, scribe_spell.
##   10B.1c — enable launch buttons on: research_magic_item, manage_assistant.
##   10B.1d — apprentices/aspirants card becomes interactive (manual
##            promotion roll override + history).
##   10B.1e — enable launch button on: research_construct.
##   10B.1f — enable launch button on: research_monster (per Q19 scope).
##   10B.1g — Lightblessed dual-list filter on research_spell + dungeon-
##            under-tower hook display.
##   10B.1h — full UI polish per gdd-domain-tab.md §12.4 / §12.7.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Launcher card identifiers. Each maps to a target wave for the disabled-
## state tooltip. Per Q16 the four research_magic project_kind variants are
## surfaced as separate cards but share the unified research_magic backend
## activity row.
##
## handler_ready: true means the activity handler is implemented (so the
## backend can resolve completions invoked via direct executor.launch);
## false means the wave that ships the handler hasn't landed yet.
##
## launcher_ready: true means the UI launcher (picker dialog) is wired so
## clicking the Launch button starts the activity end-to-end. 10B.1h
## (UI polish pass) flips 7 of the 8 launchers to launcher_ready=true and
## wires research_project_picker.gd as the modal. manage_assistant stays
## disabled per Q27 [RESOLVED 2026-05-11] (its handler is a stub until a
## later polish wave lands parallel-item-creation orchestration).
const LAUNCHER_CARDS: Array[Dictionary] = [
	{"id": "research_spell",      "label": "Research New Spell",  "wave": "10B.1b", "handler_ready": true,  "launcher_ready": true},
	{"id": "research_magic_item", "label": "Research Magic Item", "wave": "10B.1c", "handler_ready": true,  "launcher_ready": true},
	{"id": "research_construct",  "label": "Create Construct",    "wave": "10B.1e", "handler_ready": true,  "launcher_ready": true},
	{"id": "research_monster",    "label": "Cross-Breed Monster", "wave": "10B.1f", "handler_ready": true,  "launcher_ready": true},
	{"id": "rewrite_spell",       "label": "Rewrite Spell",       "wave": "10B.1b", "handler_ready": true,  "launcher_ready": true},
	{"id": "replace_spell",       "label": "Replace Spell",       "wave": "10B.1b", "handler_ready": true,  "launcher_ready": true},
	{"id": "scribe_spell",        "label": "Scribe Spell",        "wave": "10B.1b", "handler_ready": true,  "launcher_ready": true},
	{"id": "manage_assistant",    "label": "Manage Assistant",    "wave": "10B.1c", "handler_ready": true,  "launcher_ready": false},
]


const ResearchProjectPicker = preload("res://scenes/ui/notebook/domain/blocks/research_project_picker.gd")


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _character_id: String = ""
var _domain_id: String = ""
var _party_id: String = ""

var _header_card: VBoxContainer = null
var _libraries_card: VBoxContainer = null
var _workshops_card: VBoxContainer = null
var _laboratories_card: VBoxContainer = null
var _projects_card: VBoxContainer = null
var _followers_card: VBoxContainer = null
var _activities_card: VBoxContainer = null

## Maps launcher_id -> Button instance so _refresh_activity_cards can
## re-enable/disable based on current caster state (e.g. workshop missing).
var _launcher_buttons: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

	# 2026-05-19 bucket-B item #13: launch-result banner mirroring SyndicateBlock.
	_launch_result_label = Label.new()
	_launch_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_launch_result_label.visible = false
	add_child(_launch_result_label)

	_header_card = _make_card("Magic Research Throw — Status")
	_libraries_card = _make_card("Libraries")
	_workshops_card = _make_card("Workshops")
	_laboratories_card = _make_card("Laboratories")
	_projects_card = _make_card("Research Projects")
	_followers_card = _make_card("Apprentices & Aspirants")
	_activities_card = _make_card("Magical Research Activities")

	_build_activity_launchers()
	_subscribe_signals()


# 2026-05-19 bucket-B item #13: launch-result banner state + helper.
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
	_render_header()
	_render_libraries()
	_render_workshops()
	_render_laboratories()
	_render_projects()
	_render_followers()
	_refresh_activity_cards()


func _render_header() -> void:
	_clear_card_body(_header_card)
	if _character_id.is_empty():
		_header_card.add_child(_dim_label("No active caster."))
		return
	var character := _get_character(_character_id)
	if character.is_empty():
		_header_card.add_child(_dim_label("Caster not found."))
		return
	var int_score: int = int(character.get("intelligence", 10))
	var int_mod: int = _ability_mod(int_score)
	var level: int = int(character.get("level", 1))
	var class_id: String = String(character.get("character_class", ""))

	var line := Label.new()
	line.text = "%s · L%d · INT %d (%+d) · research throw mods land in 10B.1b" % [
		class_id.capitalize(), level, int_score, int_mod,
	]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header_card.add_child(line)

	# Lightblessed-specific dual-list flavor note (Q9 / Q2). The Lightblessed
	# Wonderworker is the only class whose research-target picker offers BOTH
	# arcane and cleric divine spell lists. The filter wiring is 10B.1g; the
	# header note flags the future capability so users see why their picker
	# differs.
	if class_id == "lightblessed_wonderworker":
		var ll := Label.new()
		ll.modulate = Color(1, 1, 1, 0.7)
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ll.text = "Lightblessed dual-list: research targets may be drawn from EITHER the arcane spell list OR the cleric divine spell list (filter wired in 10B.1g)."
		_header_card.add_child(ll)


func _render_libraries() -> void:
	_clear_card_body(_libraries_card)
	if _character_id.is_empty():
		_libraries_card.add_child(_dim_label("—"))
		return
	var rows: Array = CampaignRepository.list_libraries_for_owner(_character_id)
	if rows.is_empty():
		_libraries_card.add_child(_dim_label("No libraries built. Libraries are sub-structures of sanctums / towers; build via the stronghold-construction system."))
		return
	for row: Dictionary in rows:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "%s · %s invested · supports up to level %d spells · +%d to research throws · %s" % [
			str(row.get("structure_kind", "library")).replace("_", " ").capitalize(),
			Currency.format_cost(int(row.get("cp_invested", 0))),
			int(row.get("max_spell_level_supported", 1)),
			int(row.get("magic_research_throw_bonus", 0)),
			str(row.get("status", "?")),
		]
		_libraries_card.add_child(line)


func _render_workshops() -> void:
	_clear_card_body(_workshops_card)
	if _character_id.is_empty():
		_workshops_card.add_child(_dim_label("—"))
		return
	var rows: Array = CampaignRepository.list_workshops_for_owner(_character_id)
	if rows.is_empty():
		_workshops_card.add_child(_dim_label("No workshops built. Workshops are sub-structures of towers / sanctums; build via the stronghold-construction system."))
		return
	for row: Dictionary in rows:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "%s · %s invested · supports items up to %s value · +%d to enchanting throws · %s" % [
			str(row.get("structure_kind", "workshop")).replace("_", " ").capitalize(),
			Currency.format_cost(int(row.get("cp_invested", 0))),
			Currency.format_cost(int(row.get("max_item_value_supported_cp", 0))),
			int(row.get("magic_research_throw_bonus", 0)),
			str(row.get("status", "?")),
		]
		_workshops_card.add_child(line)


func _render_laboratories() -> void:
	_clear_card_body(_laboratories_card)
	if _character_id.is_empty():
		_laboratories_card.add_child(_dim_label("—"))
		return
	var rows: Array = CampaignRepository.list_laboratories_for_owner(_character_id)
	if rows.is_empty():
		_laboratories_card.add_child(_dim_label("No laboratories built. Laboratories are required for cross-breeding monsters (RAW L471) and are built as separate workshop-style sub-structures."))
		return
	for row: Dictionary in rows:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "%s · %s invested · supports cross-breeding up to %s cost · +%d to research throws · %s" % [
			str(row.get("structure_kind", "laboratory")).replace("_", " ").capitalize(),
			Currency.format_cost(int(row.get("cp_invested", 0))),
			Currency.format_cost(int(row.get("max_crossbreed_cost_cp", 0))),
			int(row.get("magic_research_throw_bonus", 0)),
			str(row.get("status", "?")),
		]
		_laboratories_card.add_child(line)


func _render_projects() -> void:
	_clear_card_body(_projects_card)
	if _character_id.is_empty():
		_projects_card.add_child(_dim_label("—"))
		return
	var rows: Array = CampaignRepository.list_magic_research_projects_for_character(
		_character_id, "in_progress")
	if rows.is_empty():
		_projects_card.add_child(_dim_label("No research in progress. Launch a project from the activities below (live launchers ship in 10B.1b)."))
		return
	for row: Dictionary in rows:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var kind: String = str(row.get("project_kind", "?"))
		var target: String = str(row.get("target_spell_key", ""))
		if target.is_empty():
			target = str(row.get("target_item_kind", ""))
		var days_done: int = int(row.get("days_completed", 0))
		var days_total: int = int(row.get("days_total", 0))
		line.text = "%s · %s · %d/%d days · %s committed" % [
			kind.capitalize(),
			target if not target.is_empty() else "(no target)",
			days_done, days_total,
			Currency.format_cost(int(row.get("cp_committed", 0))),
		]
		_projects_card.add_child(line)


func _render_followers() -> void:
	_clear_card_body(_followers_card)
	if _character_id.is_empty():
		_followers_card.add_child(_dim_label("—"))
		return
	var aspirants: Array = CampaignRepository.list_followers_by_source_kind(
		_character_id, "aspirant")
	var apprentices: Array = CampaignRepository.list_followers_for_owner(
		_character_id, "present")
	# Filter apprentices to only those who were aspirants (i.e., level >= 1
	# with intended_class set — they were promoted).
	var filtered_apprentices: Array = []
	for f: Dictionary in apprentices:
		if not String(f.get("intended_class", "")).is_empty() and int(f.get("level", 0)) >= 1:
			filtered_apprentices.append(f)

	if aspirants.is_empty() and filtered_apprentices.is_empty():
		_followers_card.add_child(_dim_label("No apprentices or aspirants. Aspirants arrive on sanctum founding; promotion roll fires at month 4 (d20 + ability mod, 14+ promotes)."))
		return

	if not aspirants.is_empty():
		var hdr := Label.new()
		hdr.text = "Aspirants (0-level Normal Men, awaiting promotion throw):"
		hdr.add_theme_font_size_override("font_size", 13)
		_followers_card.add_child(hdr)
		for asp: Dictionary in aspirants:
			var due_day_v = asp.get("promotion_eligible_day")
			var due_str: String = "—" if due_day_v == null else "day %d" % int(due_day_v)
			var line := Label.new()
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.text = "  · %s · intends %s · promotion throw on %s" % [
				String(asp.get("name", "?")),
				String(asp.get("intended_class", "?")).capitalize(),
				due_str,
			]
			_followers_card.add_child(line)

	if not filtered_apprentices.is_empty():
		var hdr2 := Label.new()
		hdr2.text = "Apprentices (promoted 1st-level+):"
		hdr2.add_theme_font_size_override("font_size", 13)
		_followers_card.add_child(hdr2)
		for app: Dictionary in filtered_apprentices:
			var line := Label.new()
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.text = "  · %s · %s L%d" % [
				String(app.get("name", "?")),
				String(app.get("character_class", "?")).capitalize(),
				int(app.get("level", 1)),
			]
			_followers_card.add_child(line)


# ---------------------------------------------------------------------------
# Activity launchers
# ---------------------------------------------------------------------------

func _build_activity_launchers() -> void:
	_launcher_buttons.clear()
	for entry in LAUNCHER_CARDS:
		var launcher_id: String = entry["id"]
		var label: String = entry["label"]
		var wave: String = entry["wave"]
		var handler_ready: bool = bool(entry.get("handler_ready", false))
		var launcher_ready: bool = bool(entry.get("launcher_ready", false))

		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hbox)

		var name_label := Label.new()
		name_label.text = label
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(name_label)

		var phase_label := Label.new()
		phase_label.modulate = Color(1, 1, 1, 0.7)
		if handler_ready and not launcher_ready:
			phase_label.text = "ships in later polish wave"
		elif not handler_ready:
			phase_label.text = "ships in %s" % wave
		else:
			phase_label.text = ""
		hbox.add_child(phase_label)

		var launch_btn := Button.new()
		launch_btn.text = "Launch"
		launch_btn.disabled = not launcher_ready
		if handler_ready and not launcher_ready:
			launch_btn.tooltip_text = "Backend handler implemented; launcher UI not yet wired."
		elif not handler_ready:
			launch_btn.tooltip_text = "Activity handler lands in wave %s." % wave
		else:
			launch_btn.tooltip_text = "Open the %s picker." % label.to_lower()

		if launcher_ready:
			launch_btn.pressed.connect(_on_launcher_pressed.bind(launcher_id))
		hbox.add_child(launch_btn)

		_launcher_buttons[launcher_id] = launch_btn
		_activities_card.add_child(row)


func _refresh_activity_cards() -> void:
	# Per-launcher eligibility gates: disable buttons whose preconditions
	# (caster identity / library presence / formula availability) are not
	# satisfied yet. The picker itself surfaces fine-grained validation; this
	# coarse gate just hides "Launch" when no path forward exists.
	if _character_id.is_empty():
		for btn in _launcher_buttons.values():
			(btn as Button).disabled = true
		return

	var character := _get_character(_character_id)
	var has_research_bucket: bool = false
	if not character.is_empty():
		var buckets: Array[String] = ClassBucketResolver.buckets_for_character(character)
		has_research_bucket = buckets.has("magical_research")

	var has_library: bool = not CampaignRepository.list_libraries_for_owner(_character_id).is_empty()
	var has_workshop: bool = not CampaignRepository.list_workshops_for_owner(_character_id).is_empty()
	var has_laboratory: bool = not CampaignRepository.list_laboratories_for_owner(_character_id).is_empty()

	for entry in LAUNCHER_CARDS:
		var launcher_id: String = entry["id"]
		var btn: Button = _launcher_buttons.get(launcher_id, null)
		if btn == null:
			continue
		var launcher_ready: bool = bool(entry.get("launcher_ready", false))
		if not launcher_ready:
			btn.disabled = true
			continue
		# Common: the character must be in the magical-research bucket.
		var enabled: bool = has_research_bucket
		var tooltip: String = ""
		if not has_research_bucket:
			tooltip = "Caster is not eligible for Magical Research (no caster class power)."
		# Per-launcher infra preconditions:
		match launcher_id:
			"research_spell", "rewrite_spell", "replace_spell", "scribe_spell":
				if enabled and not has_library:
					enabled = false
					tooltip = "A library is required for spell research."
			"research_magic_item":
				if enabled and not (has_library or has_workshop):
					enabled = false
					tooltip = "A library or workshop is required for magic-item research."
			"research_construct":
				if enabled and not has_workshop:
					enabled = false
					tooltip = "A workshop is required for construct creation."
			"research_monster":
				if enabled and not has_laboratory:
					enabled = false
					tooltip = "A laboratory is required for cross-breeding."
		btn.disabled = not enabled
		if not tooltip.is_empty():
			btn.tooltip_text = tooltip


# ---------------------------------------------------------------------------
# Picker wiring
# ---------------------------------------------------------------------------

func _on_launcher_pressed(launcher_id: String) -> void:
	if _character_id.is_empty():
		return
	var picker: CanvasLayer = ResearchProjectPicker.new()
	# Add to the scene tree (top-level overlay) before calling setup so the
	# CanvasLayer is in the tree when it builds.
	var host: Node = get_tree().root if get_tree() != null else self
	host.add_child(picker)
	picker.setup(launcher_id, _character_id, _domain_id, _party_id)
	picker.launch_requested.connect(_on_picker_launch_requested)
	picker.cancelled.connect(_on_picker_cancelled)


func _on_picker_launch_requested(
		activity_def_id: String,
		params: Dictionary,
		location_kind: String,
		location_ref: String) -> void:
	var label: String = activity_def_id.replace("_", " ").capitalize()
	var executor := _get_activity_executor()
	if executor == null:
		_show_launch_result(label, {"success": false, "error": "no executor"})
		return
	var scheduler := _get_scheduler()
	if scheduler == null:
		_show_launch_result(label, {"success": false, "error": "no scheduler"})
		return
	var result := executor.launch(
		_character_id, activity_def_id,
		location_kind, location_ref,
		params, scheduler, _party_id)
	# 2026-05-19 bucket-B item #13: surface success/failure via banner.
	_show_launch_result(label, result)


func _on_picker_cancelled() -> void:
	pass


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


## Banker's-rounded ACKS ability modifier (match-table).
func _ability_mod(score: int) -> int:
	if score <= 3:
		return -3
	if score <= 5:
		return -2
	if score <= 8:
		return -1
	if score <= 12:
		return 0
	if score <= 15:
		return 1
	if score <= 17:
		return 2
	return 3


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.magic_research_project_started.is_connected(_on_project_changed):
		EventBus.magic_research_project_started.connect(_on_project_changed)
	if not EventBus.magic_research_project_completed.is_connected(_on_project_completed):
		EventBus.magic_research_project_completed.connect(_on_project_completed)
	if not EventBus.library_built.is_connected(_on_library_changed):
		EventBus.library_built.connect(_on_library_changed)
	if not EventBus.workshop_built.is_connected(_on_workshop_changed):
		EventBus.workshop_built.connect(_on_workshop_changed)
	if not EventBus.laboratory_built.is_connected(_on_laboratory_changed):
		EventBus.laboratory_built.connect(_on_laboratory_changed)
	if not EventBus.follower_joined.is_connected(_on_follower_changed):
		EventBus.follower_joined.connect(_on_follower_changed)
	if not EventBus.follower_departed.is_connected(_on_follower_departed):
		EventBus.follower_departed.connect(_on_follower_departed)
	if not EventBus.aspirant_promoted_to_first_level.is_connected(_on_aspirant_promoted):
		EventBus.aspirant_promoted_to_first_level.connect(_on_aspirant_promoted)
	if not EventBus.follower_promoted_to_henchman.is_connected(_on_follower_to_henchman):
		EventBus.follower_promoted_to_henchman.connect(_on_follower_to_henchman)


func _unsubscribe_signals() -> void:
	if EventBus.magic_research_project_started.is_connected(_on_project_changed):
		EventBus.magic_research_project_started.disconnect(_on_project_changed)
	if EventBus.magic_research_project_completed.is_connected(_on_project_completed):
		EventBus.magic_research_project_completed.disconnect(_on_project_completed)
	if EventBus.library_built.is_connected(_on_library_changed):
		EventBus.library_built.disconnect(_on_library_changed)
	if EventBus.workshop_built.is_connected(_on_workshop_changed):
		EventBus.workshop_built.disconnect(_on_workshop_changed)
	if EventBus.laboratory_built.is_connected(_on_laboratory_changed):
		EventBus.laboratory_built.disconnect(_on_laboratory_changed)
	if EventBus.follower_joined.is_connected(_on_follower_changed):
		EventBus.follower_joined.disconnect(_on_follower_changed)
	if EventBus.follower_departed.is_connected(_on_follower_departed):
		EventBus.follower_departed.disconnect(_on_follower_departed)
	if EventBus.aspirant_promoted_to_first_level.is_connected(_on_aspirant_promoted):
		EventBus.aspirant_promoted_to_first_level.disconnect(_on_aspirant_promoted)
	if EventBus.follower_promoted_to_henchman.is_connected(_on_follower_to_henchman):
		EventBus.follower_promoted_to_henchman.disconnect(_on_follower_to_henchman)


func _on_project_changed(_project_id: String, character_id: String, _kind: String) -> void:
	if character_id == _character_id:
		_render_projects()


func _on_project_completed(_project_id: String, character_id: String, _success: bool) -> void:
	if character_id == _character_id:
		_render_projects()


func _on_library_changed(_library_id: String, owner_id: String, _gp: int) -> void:
	if owner_id == _character_id:
		_render_libraries()
		_render_header()
		_refresh_activity_cards()


func _on_workshop_changed(_workshop_id: String, owner_id: String, _gp: int) -> void:
	if owner_id == _character_id:
		_render_workshops()
		_refresh_activity_cards()


func _on_laboratory_changed(_laboratory_id: String, owner_id: String, _gp: int) -> void:
	if owner_id == _character_id:
		_render_laboratories()
		_refresh_activity_cards()


func _on_follower_changed(_follower_id: String, owner_id: String, _source_kind: String) -> void:
	if owner_id == _character_id:
		_render_followers()


func _on_follower_departed(_follower_id: String, owner_id: String, _reason: String) -> void:
	if owner_id == _character_id:
		_render_followers()


func _on_aspirant_promoted(_follower_id: String, owner_id: String, _new_class: String) -> void:
	if owner_id == _character_id:
		_render_followers()


func _on_follower_to_henchman(_follower_id: String, _new_char_id: String, owner_id: String) -> void:
	if owner_id == _character_id:
		_render_followers()
