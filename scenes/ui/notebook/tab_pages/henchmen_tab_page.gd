extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Henchmen tab — H.1 first pass per gdd-henchmen-tab.md v1.3.
##
## Replaces the β empty-state stub with two sub-tabs: Roster (master table of
## all currently-active henchmen across the active party) and Departure Log
## (chronological history of every henchman who has left service).
##
## In scope (H.1):
##   - Status header (count + monthly wages aggregate)
##   - Roster sub-tab with portrait / name / class+level / patron / morale /
##     loyalty band / wage / share / status columns
##   - Departure Log sub-tab with portrait / name / departure date / reason
##   - Empty-state when zero henchmen across all PCs
##   - Click portrait/name → cross-activate Character tab
##   - Right-click row → context menu (View character / Dismiss / Promote
##     greyed)
##   - Per-tab substate persistence: active sub-tab id only (sort/filter
##     persistence deferred)
##
## Out of scope (deferred to follow-ups):
##   - Hire button (depends on Settlement Hiring sub-flow)
##   - Adjust Treatment modal (treasure share + bonus)
##   - Promote to Full Member full lifecycle (only the greyed button is here)
##   - Loyalty trend sparkline
##   - Per-tab sort/filter persistence
##   - Animal HD-equivalent wage breakdown (uses level-based wage as proxy
##     until Beast Friendship integration lands)
##   - Re-recruitment from log
##
## Engine layer (HenchmanLifecycleManager / HenchmanLoyaltyResolver /
## HenchmanAvailability / HenchmanTables) is already wired and tested via
## migration 027; this tab is pure UI integration.


const PortraitWithBadgeScript := preload("res://scenes/ui/components/portrait_with_badge.gd")
const DismissHenchmanDialogScript := preload("res://scenes/ui/dialogs/dismiss_henchman_dialog.gd")

# Tab id for NotebookState substate persistence. Local name (parent class
# already declares a `TAB_ID` constant; subclasses must use a distinct name).
const SUBSTATE_TAB_ID := "henchmen"

const SUBTAB_ROSTER := "roster"
const SUBTAB_DEPARTURE_LOG := "departure_log"
const SUBTAB_DEFAULT := SUBTAB_ROSTER

const SUBTAB_FONT_SIZE := 12
const ACTIVE_SUBTAB_COLOR := Color(0.92, 0.86, 0.74, 1.0)
const INACTIVE_SUBTAB_COLOR := Color(0.55, 0.50, 0.42, 1.0)

const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DIM_COLOR := Color(0.55, 0.50, 0.42, 1.0)

# Per acore_equipment.xml §loyalty_results — 5-band ACKS scale.
const LOYALTY_BAND_LABELS := {
	"hostility":   "Hostility",
	"resignation": "Resignation",
	"grudging":    "Grudging Loyalty",
	"loyal":       "Loyalty",
	"fanatic":     "Fanatic Loyalty",
}

const LOYALTY_BAND_COLORS := {
	"hostility":   Color(0.85, 0.30, 0.25, 1.0),
	"resignation": Color(0.85, 0.55, 0.30, 1.0),
	"grudging":    Color(0.85, 0.78, 0.30, 1.0),
	"loyal":       Color(0.55, 0.80, 0.55, 1.0),
	"fanatic":     Color(0.50, 0.85, 0.85, 1.0),
}

const DEPARTURE_REASON_LABELS := {
	"hostility":   "Hostile Departure",
	"resignation": "Resigned",
	"grudging":    "Grudging Departure",
	"dismissed":   "Dismissed",
	"killed":      "KIA",
	"promoted":    "Promoted to Full Member",
	"retired":     "Retired",
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _status_header: Control = null
var _status_summary_label: Label = null
var _status_payday_label: Label = null

var _subtab_strip: HBoxContainer = null
var _subtab_buttons: Dictionary = {}  # subtab id -> Button

var _content_holder: Control = null
var _roster_view: Control = null
var _departure_view: Control = null

var _empty_state: Control = null

var _active_subtab: String = SUBTAB_DEFAULT


# ---------------------------------------------------------------------------
# Lifecycle (overrides notebook_tab_page._build_content)
# ---------------------------------------------------------------------------

func _build_content() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_status_header = _build_status_header()
	vbox.add_child(_status_header)

	_subtab_strip = _build_subtab_strip()
	vbox.add_child(_subtab_strip)

	_content_holder = Control.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_holder)

	_connect_signals()
	_restore_substate()
	_refresh()


func _connect_signals() -> void:
	# Live-refresh: any change to henchman set / loyalty / wages refreshes both
	# sub-tabs cheaply (the table rebuilds are inexpensive at typical roster
	# sizes). The Notebook itself pauses the world while open, so refresh
	# storms during gameplay are not a concern.
	EventBus.henchman_hired.connect(_on_henchman_event)
	EventBus.henchman_departed.connect(_on_henchman_event)
	EventBus.henchman_loyalty_checked.connect(_on_henchman_loyalty_checked)
	EventBus.loyalty_changed.connect(_on_henchman_loyalty_int)
	EventBus.wages_processed.connect(_on_wages_processed)
	EventBus.active_party_changed.connect(_on_active_party_changed)
	# H.2 — Notes badge refreshes when journal contents change.
	EventBus.journal_changed.connect(_on_journal_changed)


# ---------------------------------------------------------------------------
# Status header
# ---------------------------------------------------------------------------

func _build_status_header() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.08, 0.55)
	style.border_color = Color(0.46, 0.33, 0.19, 0.45)
	style.border_width_bottom = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	_status_summary_label = Label.new()
	_status_summary_label.add_theme_font_size_override("font_size", 13)
	_status_summary_label.add_theme_color_override("font_color", HEADING_COLOR)
	v.add_child(_status_summary_label)

	_status_payday_label = Label.new()
	_status_payday_label.add_theme_font_size_override("font_size", 11)
	_status_payday_label.add_theme_color_override("font_color", DIM_COLOR)
	v.add_child(_status_payday_label)

	return panel


func _refresh_status_header(active: Array) -> void:
	var humanoid := 0
	var animal := 0
	var monthly_wages_gp := 0
	for row in active:
		var ctype: String = str(row.get("character_type", "henchman"))
		if ctype == "henchman":
			# Heuristic: until creature_data integration on character rows lands,
			# a henchman with a non-empty class_id is humanoid; otherwise
			# treated as an animal henchman.
			var class_id: String = str(row.get("class_id", ""))
			if class_id.is_empty():
				animal += 1
			else:
				humanoid += 1
		monthly_wages_gp += int(row.get("wage_gp_per_month", 0))

	var total: int = humanoid + animal
	if total == 0:
		_status_summary_label.text = "No henchmen in service"
		_status_payday_label.text = "Capacity calculation lands when CHA-based caps wire"
		return
	# Pluralization: "henchman" / "henchmen" — irregular plural; not -s suffix.
	var noun: String = "henchman" if total == 1 else "henchmen"
	_status_summary_label.text = "%d %s (%d humanoid · %d animal)  ·  Monthly wages: %d gp" % [
		total, noun, humanoid, animal, monthly_wages_gp,
	]
	_status_payday_label.text = "Wages auto-deduct on payday per acore_equipment.xml §monthly_fee_table"


# ---------------------------------------------------------------------------
# Sub-tab strip
# ---------------------------------------------------------------------------

func _build_subtab_strip() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	_subtab_buttons.clear()
	for sub in [SUBTAB_ROSTER, SUBTAB_DEPARTURE_LOG]:
		var btn := Button.new()
		btn.text = _subtab_label(sub)
		btn.flat = true
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", SUBTAB_FONT_SIZE)
		btn.pressed.connect(_on_subtab_pressed.bind(sub))
		hbox.add_child(btn)
		_subtab_buttons[sub] = btn
	return hbox


func _subtab_label(subtab: String) -> String:
	match subtab:
		SUBTAB_ROSTER:         return "Roster"
		SUBTAB_DEPARTURE_LOG:  return "Departure Log"
	return subtab


func _on_subtab_pressed(subtab: String) -> void:
	if subtab == _active_subtab:
		(_subtab_buttons[subtab] as Button).button_pressed = true
		return
	_active_subtab = subtab
	_persist_substate()
	_refresh_subtab_highlight()
	_swap_content()


func _refresh_subtab_highlight() -> void:
	for sub in _subtab_buttons.keys():
		var btn: Button = _subtab_buttons[sub]
		var active: bool = (sub == _active_subtab)
		btn.button_pressed = active
		btn.add_theme_color_override("font_color",
			ACTIVE_SUBTAB_COLOR if active else INACTIVE_SUBTAB_COLOR)


# ---------------------------------------------------------------------------
# Refresh + content swap
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _content_holder == null:
		return
	var party_id: String = GameState.active_party_id
	var campaign_id: String = GameState.campaign_id
	var active: Array = []
	if not party_id.is_empty():
		active = CampaignRepository.list_party_henchmen(party_id)
	var departed: Array = []
	if not campaign_id.is_empty():
		departed = CampaignRepository.list_departed_henchmen(campaign_id)

	_refresh_status_header(active)

	# Empty-state when both lists are empty — surface the prior empty-state
	# page (acquisition guidance) and skip building tables.
	if active.is_empty() and departed.is_empty():
		_show_empty_state()
		return
	_clear_empty_state()
	_refresh_subtab_highlight()
	_rebuild_views(active, departed)
	_swap_content()


func _rebuild_views(active: Array, departed: Array) -> void:
	if _roster_view != null and is_instance_valid(_roster_view):
		_roster_view.queue_free()
	if _departure_view != null and is_instance_valid(_departure_view):
		_departure_view.queue_free()
	_roster_view = _build_roster_view(active)
	_departure_view = _build_departure_view(departed)


func _swap_content() -> void:
	if _content_holder == null:
		return
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
	var view: Control = _roster_view if _active_subtab == SUBTAB_ROSTER else _departure_view
	if view == null:
		return
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content_holder.add_child(view)


func _show_empty_state() -> void:
	# Hide sub-tabs + status header detail when there's nothing to show.
	if _subtab_strip != null:
		_subtab_strip.visible = false
	if _empty_state != null and is_instance_valid(_empty_state):
		return
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
	_empty_state = _add_empty_state(
		"No Henchmen Yet",
		"Henchmen are loyal NPC followers who accompany a PC for a share of " +
		"treasure and XP. To recruit one, post the offer at an inn or similar " +
		"establishment in a settlement. The settlement's market class limits " +
		"how many candidates appear; each then makes a reaction roll modified " +
		"by your Charisma. See [i]acore_equipment.xml[/i] §henchmen.",
		[{"text": "Find an inn (Settlement Panel)", "id": "open_settlement"}])
	# The base-class _add_empty_state adds it to `self`; reparent into the
	# content holder so the status header stays visible above.
	if _empty_state != null:
		_empty_state.reparent(_content_holder)


func _clear_empty_state() -> void:
	if _subtab_strip != null:
		_subtab_strip.visible = true
	if _empty_state != null and is_instance_valid(_empty_state):
		_empty_state.queue_free()
		_empty_state = null


# ---------------------------------------------------------------------------
# Roster sub-tab
# ---------------------------------------------------------------------------

func _build_roster_view(rows: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var grid := GridContainer.new()
	# 9 columns: portrait, name, class+level, patron, morale, loyalty, wage,
	# share, notes-badge (last; H.2 cross-surfacing per gdd-journal-tab.md §6.4).
	grid.columns = 9
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	# Header row.
	for header in ["", "Name", "Class / Level", "Patron PC", "Morale", "Loyalty", "Wage", "Share", "Notes"]:
		var lbl := Label.new()
		lbl.text = header
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", DIM_COLOR)
		grid.add_child(lbl)

	# Single JournalRepository instance reused across rows for note-count
	# lookups. Repository is RefCounted; lifetime is the build-roster call.
	var journal_repo := JournalRepository.new(CampaignRepository)
	var party_id: String = GameState.active_party_id
	for row in rows:
		_append_roster_row(grid, row, journal_repo, party_id)
	return scroll


func _append_roster_row(grid: GridContainer, row: Dictionary,
		journal_repo: JournalRepository, party_id: String) -> void:
	var character_id: String = str(row.get("id", ""))
	var name: String = str(row.get("name", "(unnamed)"))
	var class_id: String = str(row.get("class_id", ""))
	var level: int = int(row.get("level", 0))
	var patron: String = str(row.get("patron_name", "")) if row.has("patron_name") else ""
	var morale: int = int(row.get("morale_score", 0))
	var grudging: bool = int(row.get("is_grudging", 0)) == 1
	var fanatic: bool = int(row.get("is_fanatic", 0)) == 1
	var wage: int = int(row.get("wage_gp_per_month", 0))
	var share: int = int(row.get("treasure_share_percent", 15))

	# Portrait — clickable, cross-activates Character tab.
	var portrait := PortraitWithBadgeScript.new()
	portrait.set_portrait_size(Vector2(40, 40))
	portrait.set_entity_id(character_id)
	portrait.set_tooltip(name)
	if level > 0:
		portrait.set_badge("L%d" % level)
	portrait.portrait_clicked.connect(_on_entity_clicked)
	grid.add_child(portrait)

	# Name — clickable, cross-activates Character tab.
	var name_btn := _link_button(name, character_id)
	grid.add_child(name_btn)

	# Class & level — animals (no class_id) render as creature row; humanoids
	# show "<Class> <Level>".
	var class_label := Label.new()
	class_label.text = ("Animal henchman" if class_id.is_empty() else
		"%s %d" % [class_id.capitalize(), level])
	class_label.add_theme_color_override("font_color", BODY_COLOR)
	class_label.add_theme_font_size_override("font_size", 12)
	grid.add_child(class_label)

	# Patron PC — clickable when known; cross-activates Character tab to PC.
	var patron_employer_id: String = str(row.get("employer_id", ""))
	if not patron.is_empty() and not patron_employer_id.is_empty():
		grid.add_child(_link_button(patron, patron_employer_id))
	else:
		var dim := Label.new()
		dim.text = "—"
		dim.add_theme_color_override("font_color", DIM_COLOR)
		dim.add_theme_font_size_override("font_size", 12)
		grid.add_child(dim)

	# Morale score (signed).
	var morale_label := Label.new()
	morale_label.text = "%+d" % morale if morale != 0 else "0"
	morale_label.add_theme_color_override("font_color", BODY_COLOR)
	morale_label.add_theme_font_size_override("font_size", 12)
	grid.add_child(morale_label)

	# Loyalty band — derived from morale_score against the loyalty table per
	# acore_equipment.xml §loyalty_results, with grudging/fanatic flags as
	# overrides per HenchmanLifecycleManager.trigger_loyalty_check semantics.
	grid.add_child(_loyalty_label(morale, grudging, fanatic))

	# Wage per month.
	var wage_label := Label.new()
	wage_label.text = "%d gp" % wage if wage > 0 else "—"
	wage_label.add_theme_color_override("font_color", BODY_COLOR)
	wage_label.add_theme_font_size_override("font_size", 12)
	grid.add_child(wage_label)

	# Treasure share.
	var share_label := Label.new()
	share_label.text = "%d%%" % share if not class_id.is_empty() else "—"
	share_label.add_theme_color_override("font_color", BODY_COLOR)
	share_label.add_theme_font_size_override("font_size", 12)
	grid.add_child(share_label)

	# Notes badge — H.2 cross-surfacing per gdd-journal-tab.md §6.4. Shows the
	# count of notes attached to this henchman; click jumps to the Journal tab
	# Notes sub-tab. The badge is dim when zero (no draw) so empty rows don't
	# add visual noise.
	var notes_count: int = 0
	if not party_id.is_empty():
		notes_count = journal_repo.count_notes_for_entity(party_id, character_id)
	if notes_count > 0:
		var notes_btn := Button.new()
		notes_btn.text = "📝 %d" % notes_count
		notes_btn.flat = true
		notes_btn.add_theme_font_size_override("font_size", 11)
		notes_btn.add_theme_color_override("font_color", HEADING_COLOR)
		notes_btn.tooltip_text = "View notes about this henchman"
		# Bind the henchman id so the click can pre-filter the Notes sub-tab
		# to this entity (H.2 polish item 1c).
		notes_btn.pressed.connect(_on_notes_badge_clicked.bind(character_id))
		grid.add_child(notes_btn)
	else:
		var dim := Label.new()
		dim.text = "—"
		dim.add_theme_color_override("font_color", DIM_COLOR)
		dim.add_theme_font_size_override("font_size", 12)
		grid.add_child(dim)

	# Right-click context menu — install on the Name button (the row's main
	# textual handle); a future polish pass can extend to whole-row gui_input.
	name_btn.gui_input.connect(_on_row_gui_input.bind(character_id, false))


func _on_notes_badge_clicked(entity_id: String) -> void:
	# Open the Journal tab AND request the Notes sub-tab pre-filter to this
	# henchman. The Journal page consumes the filter signal and switches its
	# active sub-tab + applies the filter chip (H.2 polish item 1c).
	EventBus.notebook_open_requested.emit("journal")
	EventBus.notebook_journal_notes_filter_requested.emit(entity_id)


func _loyalty_label(morale: int, grudging: bool, fanatic: bool) -> Label:
	var band: String = HenchmanTables.loyalty_result(morale)
	if fanatic:
		band = "fanatic"
	elif grudging and band != "hostility" and band != "resignation":
		band = "grudging"
	var label := Label.new()
	label.text = LOYALTY_BAND_LABELS.get(band, band.capitalize())
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color",
		LOYALTY_BAND_COLORS.get(band, BODY_COLOR))
	return label


# ---------------------------------------------------------------------------
# Departure Log sub-tab
# ---------------------------------------------------------------------------

func _build_departure_view(rows: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	if rows.is_empty():
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", 60)
		v.add_child(pad)
		var lbl := Label.new()
		lbl.text = "No henchmen have left service yet."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", DIM_COLOR)
		v.add_child(lbl)
		scroll.add_child(v)
		return scroll

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	for row in rows:
		vbox.add_child(_build_departure_row(row))
	return vbox


func _build_departure_row(row: Dictionary) -> Control:
	var character_id: String = str(row.get("id", ""))
	var name: String = str(row.get("name", "(unnamed)"))
	var class_id: String = str(row.get("class_id", ""))
	var level: int = int(row.get("level", 0))
	var reason_key: String = str(row.get("departure_reason", ""))
	var reason: String = DEPARTURE_REASON_LABELS.get(reason_key, reason_key.capitalize())
	var date: String = str(row.get("updated_at", ""))

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.46, 0.33, 0.19, 0.45)
	style.border_width_left = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var portrait := PortraitWithBadgeScript.new()
	portrait.set_portrait_size(Vector2(40, 40))
	portrait.set_entity_id(character_id)
	portrait.set_tooltip(name)
	portrait.portrait_clicked.connect(_on_entity_clicked)
	hbox.add_child(portrait)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	hbox.add_child(v)

	var name_btn := _link_button(name, character_id)
	v.add_child(name_btn)

	var class_text: String = ("Animal henchman" if class_id.is_empty() else
		"%s %d" % [class_id.capitalize(), level])
	var detail_label := Label.new()
	detail_label.text = "%s · Departed: %s" % [class_text, reason]
	detail_label.add_theme_font_size_override("font_size", 12)
	detail_label.add_theme_color_override("font_color", BODY_COLOR)
	v.add_child(detail_label)

	if not date.is_empty():
		var date_label := Label.new()
		date_label.text = date
		date_label.add_theme_font_size_override("font_size", 10)
		date_label.add_theme_color_override("font_color", DIM_COLOR)
		v.add_child(date_label)

	return panel


# ---------------------------------------------------------------------------
# Cross-tab activation + context menu
# ---------------------------------------------------------------------------

func _link_button(text: String, entity_id: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", HEADING_COLOR)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.50, 1.0))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.pressed.connect(_on_entity_clicked.bind(entity_id))
	return btn


func _on_entity_clicked(entity_id: String) -> void:
	if entity_id.is_empty():
		return
	EventBus.notebook_active_entity_requested.emit(entity_id)


const _MENU_VIEW := 0
const _MENU_DISMISS := 1
const _MENU_PROMOTE := 2
const _MENU_ADJUST_TREATMENT := 3
const _MENU_PAY_BACK_WAGES := 4
# Phase 8 — Realm AI / Vassalage menu items (Phase 7 carry-forward).
const _MENU_MANAGE_DOMAIN := 5
const _MENU_APPOINT_VASSAL := 6
const _MENU_REVOKE_VASSALAGE := 7


func _on_row_gui_input(event: InputEvent, entity_id: String, _is_dismissed: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	_show_row_context_menu(entity_id, mb.global_position)


func _show_row_context_menu(entity_id: String, global_pos: Vector2) -> void:
	var menu := PopupMenu.new()
	menu.add_item("View character", _MENU_VIEW)
	menu.add_separator()
	menu.add_item("Adjust treatment…", _MENU_ADJUST_TREATMENT)
	menu.add_item("Pay back wages…", _MENU_PAY_BACK_WAGES)
	# Phase 8 / Realm AI menu items (Phase 7 carry-forward).
	menu.add_separator()
	menu.add_item("Manage domain…", _MENU_MANAGE_DOMAIN)
	var existing_vassalage: Dictionary = VassalRepository.get_active_assignment_for_vassal(entity_id)
	if existing_vassalage.is_empty():
		menu.add_item("Appoint as vassal…", _MENU_APPOINT_VASSAL)
	else:
		menu.add_item("Revoke vassalage…", _MENU_REVOKE_VASSALAGE)
	# Greying: "Manage domain" disabled if henchman owns no domain.
	var owns_domain: bool = _henchman_owns_domain(entity_id)
	if not owns_domain:
		menu.set_item_disabled(menu.get_item_index(_MENU_MANAGE_DOMAIN), true)
	menu.add_separator()
	menu.add_item("Dismiss henchman…", _MENU_DISMISS)
	menu.add_item("Promote to Full Member…", _MENU_PROMOTE)
	# Promote lifecycle deferred per gdd-management-notebook.md §6.5.2;
	# button is greyed in v1.
	menu.set_item_disabled(menu.get_item_index(_MENU_PROMOTE), true)
	# Pay-back-wages: greyed when no back-wages owed.
	var state: Dictionary = CampaignRepository.get_henchman_state(entity_id)
	var unpaid: int = int(state.get("unpaid_months", 0))
	if unpaid <= 0:
		menu.set_item_disabled(menu.get_item_index(_MENU_PAY_BACK_WAGES), true)
	menu.id_pressed.connect(_on_context_menu_pressed.bind(entity_id))
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.position = Vector2i(global_pos)
	menu.popup()


func _on_context_menu_pressed(item_id: int, entity_id: String) -> void:
	match item_id:
		_MENU_VIEW:
			_on_entity_clicked(entity_id)
		_MENU_DISMISS:
			# Phase 4 of the henchman closure plan: open the dedicated
			# dismissal dialog per gdd-henchmen-tab.md §7.2. The dialog
			# captures final wages, parting bonus, and equipment retention,
			# then routes the player's choices through
			# HenchmanLifecycleManager.dismiss_henchman.
			_open_dismiss_dialog(entity_id)
		_MENU_ADJUST_TREATMENT:
			# Phase 5: open the treasure-share + bonus modal.
			_open_adjust_treatment_dialog(entity_id)
		_MENU_PAY_BACK_WAGES:
			# Phase 5: confirm-and-pay flow (binary, reuses ConfirmationPrompt).
			_open_pay_back_wages_prompt(entity_id)
		_MENU_MANAGE_DOMAIN:
			# Phase 8: cross-activate to Domain tab with this henchman as
			# the active entity. EventBus signal already drives the notebook
			# active-entity routing.
			EventBus.notebook_active_entity_requested.emit(entity_id)
			# The domain tab listens to active-entity and switches to it; the
			# notebook's tab routing will land on the right surface.
		_MENU_APPOINT_VASSAL:
			_open_vassal_appointment_dialog(entity_id)
		_MENU_REVOKE_VASSALAGE:
			_revoke_vassalage(entity_id)


func _henchman_owns_domain(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM domains WHERE owner_character_id = ? LIMIT 1", [character_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


# Phase 8: vassal appointment + revocation flow
const VassalAppointmentDialogScript := preload("res://scenes/ui/notebook/troops/vassal_appointment_dialog.gd")


func _open_vassal_appointment_dialog(vassal_character_id: String) -> void:
	var dlg = VassalAppointmentDialogScript.new()
	add_child(dlg)
	dlg.vassal_appointed.connect(_on_vassal_appointed)
	dlg.appointment_cancelled.connect(dlg.queue_free)
	dlg.vassal_appointed.connect(func(_id: String) -> void: dlg.queue_free())
	dlg.configure_for_henchman(vassal_character_id)
	dlg.popup_centered()


func _on_vassal_appointed(_assignment_id: String) -> void:
	# Refresh the henchmen list (badges may change).
	_refresh()


func _revoke_vassalage(vassal_character_id: String) -> void:
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(vassal_character_id)
	if assn.is_empty():
		return
	# v1: simple status flip + loyalty roll. The dismissal dialog flow could
	# be reused for a richer UX in Phase 11 polish; for now we mark the
	# assignment 'departed' (voluntary lord-side revocation) without a
	# loyalty cascade. The vassal becomes a free agent, no penalty to lord.
	VassalRepository.update_status(String(assn.get("id", "")), "departed", 0)
	_refresh()


# ---------------------------------------------------------------------------
# Per-tab substate persistence
# ---------------------------------------------------------------------------

func _restore_substate() -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		return
	var sub: Dictionary = NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	var stored: String = str(sub.get("active_subtab", SUBTAB_DEFAULT))
	if stored == SUBTAB_DEPARTURE_LOG or stored == SUBTAB_ROSTER:
		_active_subtab = stored


func _persist_substate() -> void:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		return
	NotebookState.set_substate_for_tab(pid, SUBSTATE_TAB_ID, {
		"active_subtab": _active_subtab,
	})


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_henchman_event(_character_id: String, _payload: Dictionary) -> void:
	_refresh()


func _on_henchman_loyalty_checked(_character_id: String, _trigger: String, _result: Dictionary) -> void:
	_refresh()


func _on_henchman_loyalty_int(_character_id: String, _old: int, _new: int) -> void:
	_refresh()


func _on_wages_processed(_party_id: String, _summary: Dictionary) -> void:
	_refresh()


func _on_active_party_changed(_previous: String, _new: String) -> void:
	_restore_substate()
	_refresh()


func _on_journal_changed(_kind: String, _party_id: String) -> void:
	# Notes badge counts may have changed for one or more roster rows. The
	# current row construction inlines the count; refreshing the whole tab is
	# cheap at typical roster sizes (≤ 10 henchmen).
	_refresh()


# ---------------------------------------------------------------------------
# Dismissal flow
# ---------------------------------------------------------------------------

func _open_dismiss_dialog(character_id: String) -> void:
	var char_row: Dictionary = CampaignRepository.get_character(character_id)
	if char_row.is_empty():
		return
	var hench_name: String = String(char_row.get("name", "henchman"))
	var monthly_wage: int = int(char_row.get("wage_gp_per_month", 0))
	var state: Dictionary = CampaignRepository.get_henchman_state(character_id)
	var unpaid_months: int = int(state.get("unpaid_months", 0))
	var default_final_wages_gp: int = unpaid_months * monthly_wage

	var party_id: String = ""
	if has_method("get_active_party_id"):
		party_id = call("get_active_party_id")
	# Fallback: look up via party_members.
	if party_id.is_empty():
		var rows: Array = []
		if CampaignRepository.db.query_with_bindings(
				"SELECT party_id FROM party_members WHERE character_id = ? LIMIT 1",
				[character_id]):
			rows = CampaignRepository.db.query_result.duplicate()
		if not rows.is_empty():
			party_id = String(rows[0].get("party_id", ""))

	var dialog := DismissHenchmanDialogScript.new()
	add_child(dialog)
	# Wait one frame so _ready builds the UI before show_dialog mutates it.
	await get_tree().process_frame
	dialog.show_dialog(character_id, "", party_id, hench_name,
		default_final_wages_gp,
		func(opts): _do_dismiss(character_id, opts, dialog),
		func(): dialog.queue_free())


func _do_dismiss(character_id: String, options: Dictionary, dialog: Node) -> void:
	# The notebook tab doesn't own a HenchmanLifecycleManager instance;
	# instantiate one bound to the live CampaignRepository for this call.
	var lifecycle := HenchmanLifecycleManager.new(CampaignRepository, null, null)
	var ok: bool = lifecycle.dismiss_henchman(character_id, options)
	if ok:
		EventBus.notification_requested.emit({
			"type":  "info",
			"title": "Henchman dismissed",
			"body":  "Departure recorded. See the Departure Log sub-tab.",
		})
	else:
		EventBus.notification_requested.emit({
			"type":  "warning",
			"title": "Dismissal failed",
			"body":  "Could not complete the dismissal — check the party wallet for outstanding wages.",
		})
	if dialog != null and dialog.is_inside_tree():
		dialog.queue_free()
	_refresh()


# ---------------------------------------------------------------------------
# Phase 5: Adjust treatment + pay back wages flows
# ---------------------------------------------------------------------------

const AdjustTreatmentDialogScript := preload("res://scenes/ui/dialogs/adjust_treatment_dialog.gd")
const ConfirmationPromptScene := preload("res://scenes/ui/dialogs/confirmation_dialog.tscn")


func _open_adjust_treatment_dialog(character_id: String) -> void:
	var char_row: Dictionary = CampaignRepository.get_character(character_id)
	if char_row.is_empty():
		return
	var name_str: String = String(char_row.get("name", "henchman"))
	var state: Dictionary = CampaignRepository.get_henchman_state(character_id)
	var current_share: int = int(state.get("treasure_share_percent", 15))
	var current_morale: int = int(state.get("morale_score", 0))

	var dialog := AdjustTreatmentDialogScript.new()
	add_child(dialog)
	await get_tree().process_frame
	dialog.show_dialog(character_id, name_str, current_share, current_morale,
		func(opts): _do_adjust_treatment(character_id, opts, dialog),
		func(): dialog.queue_free())


func _do_adjust_treatment(character_id: String, options: Dictionary, dialog: Node) -> void:
	var lifecycle := HenchmanLifecycleManager.new(CampaignRepository, null, null)
	var result: Dictionary = lifecycle.adjust_treatment(character_id,
		int(options.get("treasure_share_percent", 15)),
		int(options.get("bonus_gp", 0)))
	if result.get("ok", false):
		EventBus.notification_requested.emit({
			"type":  "info",
			"category": "henchman",
			"title": "Treatment adjusted",
			"body":  "Treasure share updated. The Henchmen tab will reflect the change.",
		})
	else:
		EventBus.notification_requested.emit({
			"type":  "warning",
			"category": "henchman",
			"title": "Could not adjust treatment",
			"body":  String(result.get("message", "")),
		})
	if dialog != null and dialog.is_inside_tree():
		dialog.queue_free()
	_refresh()


func _open_pay_back_wages_prompt(character_id: String) -> void:
	var char_row: Dictionary = CampaignRepository.get_character(character_id)
	if char_row.is_empty():
		return
	var name_str: String = String(char_row.get("name", "henchman"))
	var monthly_wage: int = int(char_row.get("wage_gp_per_month", 0))
	var state: Dictionary = CampaignRepository.get_henchman_state(character_id)
	var unpaid: int = int(state.get("unpaid_months", 0))
	var owed_gp: int = unpaid * monthly_wage
	if owed_gp <= 0:
		EventBus.notification_requested.emit({
			"type":  "info",
			"category": "henchman",
			"title": "No back-wages owed",
			"body":  "%s has no unpaid wages." % name_str,
		})
		return

	var prompt := ConfirmationPromptScene.instantiate()
	add_child(prompt)
	await get_tree().process_frame
	prompt.show_prompt(
		"Pay back wages?",
		"%s is owed %d gp in unpaid wages (%d month%s × %d gp/mo). The amount will be deducted from the active party's wallet." % [
			name_str, owed_gp, unpaid,
			"" if unpaid == 1 else "s", monthly_wage,
		],
		func(): _do_pay_back_wages(character_id, prompt),
		func(): prompt.queue_free(),
		false)


func _do_pay_back_wages(character_id: String, prompt: Node) -> void:
	var lifecycle := HenchmanLifecycleManager.new(CampaignRepository, null, null)
	var result: Dictionary = lifecycle.pay_back_wages(character_id)
	if result.get("ok", false):
		EventBus.notification_requested.emit({
			"type":  "info",
			"category": "henchman",
			"title": "Wages paid",
			"body":  "Paid %d gp in back-wages." % int(result.get("paid_gp", 0)),
		})
	else:
		EventBus.notification_requested.emit({
			"type":  "warning",
			"category": "henchman",
			"title": "Could not pay back wages",
			"body":  String(result.get("message", "")),
		})
	if prompt != null and prompt.is_inside_tree():
		prompt.queue_free()
	_refresh()
