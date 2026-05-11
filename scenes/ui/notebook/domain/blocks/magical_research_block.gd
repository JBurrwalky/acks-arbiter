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
const LAUNCHER_CARDS: Array[Dictionary] = [
	{"id": "research_spell",      "label": "Research New Spell",      "wave": "10B.1b"},
	{"id": "research_magic_item", "label": "Research Magic Item",     "wave": "10B.1c"},
	{"id": "research_construct",  "label": "Create Construct",        "wave": "10B.1e"},
	{"id": "research_monster",    "label": "Create Monster",          "wave": "10B.1f"},
	{"id": "rewrite_spell",       "label": "Rewrite Spell",           "wave": "10B.1b"},
	{"id": "replace_spell",       "label": "Replace Spell",           "wave": "10B.1b"},
	{"id": "scribe_spell",        "label": "Scribe Spell",            "wave": "10B.1b"},
	{"id": "manage_assistant",    "label": "Manage Assistant",        "wave": "10B.1c"},
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _character_id: String = ""
var _domain_id: String = ""
var _party_id: String = ""

var _header_card: VBoxContainer = null
var _libraries_card: VBoxContainer = null
var _workshops_card: VBoxContainer = null
var _projects_card: VBoxContainer = null
var _followers_card: VBoxContainer = null
var _activities_card: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

	_header_card = _make_card("Magic Research Throw — Status")
	_libraries_card = _make_card("Libraries")
	_workshops_card = _make_card("Workshops")
	_projects_card = _make_card("Research Projects")
	_followers_card = _make_card("Apprentices & Aspirants")
	_activities_card = _make_card("Magical Research Activities")

	_build_activity_launchers()
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
	_render_header()
	_render_libraries()
	_render_workshops()
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
		ll.text = "Lightblessed dual-list: research targets may be drawn from EITHER the arcane spell list OR the cleric divine spell list (filter wiring lands in 10B.1g)."
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
		line.text = "%s · %d gp invested · supports up to level %d spells · +%d to research throws · %s" % [
			String(row.get("structure_kind", "library")).replace("_", " ").capitalize(),
			int(row.get("gp_invested", 0)),
			int(row.get("max_spell_level_supported", 1)),
			int(row.get("magic_research_throw_bonus", 0)),
			String(row.get("status", "?")),
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
		line.text = "%s · %d gp invested · supports items up to %d gp value · +%d to enchanting throws · %s" % [
			String(row.get("structure_kind", "workshop")).replace("_", " ").capitalize(),
			int(row.get("gp_invested", 0)),
			int(row.get("max_item_value_supported_gp", 0)),
			int(row.get("magic_research_throw_bonus", 0)),
			String(row.get("status", "?")),
		]
		_workshops_card.add_child(line)


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
		var kind: String = String(row.get("project_kind", "?"))
		var target: String = String(row.get("target_spell_key", ""))
		if target.is_empty():
			target = String(row.get("target_item_kind", ""))
		var days_done: int = int(row.get("days_completed", 0))
		var days_total: int = int(row.get("days_total", 0))
		line.text = "%s · %s · %d/%d days · %d gp committed" % [
			kind.capitalize(),
			target if not target.is_empty() else "(no target)",
			days_done, days_total,
			int(row.get("gp_committed", 0)),
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
	for entry in LAUNCHER_CARDS:
		var card_id: String = entry["id"]
		var label: String = entry["label"]
		var wave: String = entry["wave"]

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
		phase_label.text = "ships in %s" % wave
		hbox.add_child(phase_label)

		var launch_btn := Button.new()
		launch_btn.text = "Launch"
		launch_btn.disabled = true
		launch_btn.tooltip_text = "Activity handler lands in wave %s." % wave
		hbox.add_child(launch_btn)

		_activities_card.add_child(row)


func _refresh_activity_cards() -> void:
	# Phase 10B.1a: all launchers permanently disabled. When each wave's handler
	# lands, this function will dispatch enable/disable based on the registered
	# handler set + eligibility (caster level, library availability, etc.).
	pass


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


func _on_workshop_changed(_workshop_id: String, owner_id: String, _gp: int) -> void:
	if owner_id == _character_id:
		_render_workshops()


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
