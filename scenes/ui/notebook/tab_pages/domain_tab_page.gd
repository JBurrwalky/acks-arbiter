extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Domain tab page — Phase 2 shell per gdd-domain-tab.md.
##
## Layout (top to bottom):
##   1. Entity strip (PCs + humanoid Henchmen only, per gdd-management-notebook
##      §6.1 + gdd-domain-tab §3)
##   2. Status header — slim summary visible across all sub-tabs (§5)
##   3. Sub-tab strip — nine entries: Overview / Stronghold / Garrison /
##      Realm / Treasury / Decrees & Remote Orders / Class-Specific /
##      Encounters / Departure Log (§4)
##   4. Active sub-tab content
##
## Phase 2 implements full content for Overview, Stronghold (placeholder
## with cross-activation buttons), Treasury, and an Establish-Domain dialog
## hooked off the empty-state. Other sub-tabs render the placeholder body.
##
## Per-tab state persistence (active entity, active sub-tab) lives in
## NotebookState's per-tab substate per gdd-management-notebook §6.1.4.
## Substate shape:
##   {
##     "entity_type": "pcs" | "henchmen",
##     "entity_per_type": {pcs: id, henchmen: id},
##     "sub_tab_per_entity": {entity_id: sub_tab_id},
##   }


const StatusHeaderScript := preload("res://scenes/ui/notebook/domain/status_header.gd")
const OverviewSubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/overview_sub_tab.gd")
const StrongholdSubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/stronghold_sub_tab.gd")
const TreasurySubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/treasury_sub_tab.gd")
const PlaceholderSubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/placeholder_sub_tab.gd")
const EstablishDomainDialogScript := preload("res://scenes/ui/notebook/domain/establish_domain_dialog.gd")
const _DomainEmptyStatePageScript := preload("res://scenes/ui/components/empty_state_page.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SUBSTATE_TAB_ID := "domain"

const TYPE_PCS := "pcs"
const TYPE_HENCHMEN := "henchmen"
const TYPE_LABELS := {
	TYPE_PCS: "PCs",
	TYPE_HENCHMEN: "Humanoid Henchmen",
}
const TYPE_ORDER := [TYPE_PCS, TYPE_HENCHMEN]

## Sub-tab definitions in display order. Entries with `placeholder_phase` use
## the generic PlaceholderSubTab; entries without spawn their bespoke script.
const SUB_TABS := [
	{"id": "overview",      "label": "Overview",       "phase_2": true,  "script": "overview"},
	{"id": "stronghold",    "label": "Stronghold",     "phase_2": true,  "script": "stronghold"},
	{"id": "garrison",      "label": "Garrison",       "phase_2": false, "script": "placeholder",
		"phase": "Phase 5 — Troops Tab + Garrison Sub-Tab + L9 Follower Arrival",
		"description": "Surfaces troop_units assigned to this domain, faithful followers, militia/conscript rosters, garrison-cost compliance, additional-troops bonus, and repression toggles per gdd-domain-tab.md §8."},
	{"id": "realm",         "label": "Realm",          "phase_2": false, "script": "placeholder",
		"phase": "Phase 6 — Realm Sub-Tab + Vassalage + Tribute",
		"description": "Vassal table, tribute flows + efficiency factor, favors/duties tracker, realm aggregates, current title display."},
	{"id": "treasury",      "label": "Treasury",       "phase_2": true,  "script": "treasury"},
	{"id": "decrees_and_remote_orders", "label": "Decrees & Remote Orders", "phase_2": false, "script": "placeholder",
		"phase": "Phase 3 — Activity Time-Cost Executor + Decrees & Remote Orders + Per-Location Launch Wiring",
		"description": "Small set of remote-capable domain activities (administer_domain, issue_decree, manage_henchmen, conscript_troops, levy_militia, solicit_mercenaries, call_to_arms, oversee_investment) dispatched via the activity time-cost executor per gdd-domain-tab.md §11 and gdd-realtime-scheduler.md §4.8. Non-remote activities launch from their location-of-execution UI surfaces."},
	{"id": "class_specific","label": "Class Activities","phase_2": false, "script": "placeholder",
		"phase": "Phase 9 — Class-Specific Sub-Tab",
		"description": "Faith / Magical Research / Trade / Syndicate / Garrison Training blocks for the active entity's class."},
	{"id": "encounters",    "label": "Encounters & Threats", "phase_2": false, "script": "placeholder",
		"phase": "Phase 8 — Domain Encounters + Bandits + Threats",
		"description": "Domain encounter throws (monthly civilized / weekly borderlands / daily wilderness), bandit count by morale tier, NPC challenger emergence, siege state."},
	{"id": "departure_log", "label": "Departure Log",  "phase_2": false, "script": "placeholder",
		"phase": "Phase 10 — Departure Log + Lifecycle Polish",
		"description": "Chronological history of significant losses (classification regression, lost holdings, defeats, abandonment, ruler change, conquest)."},
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _root_vbox: VBoxContainer = null
var _entity_strip: HBoxContainer = null
var _entity_type_dropdown: OptionButton = null
var _entity_tabs_hbox: HBoxContainer = null
var _status_header: PanelContainer = null
var _sub_tab_bar: TabBar = null
var _content_holder: Control = null
var _empty_state: Control = null
var _establish_dialog: AcceptDialog = null

var _active_entity_type: String = TYPE_PCS
var _active_entity_id: String = ""
var _active_sub_tab_id: String = "overview"

## sub_tab_id -> instance (Overview / Stronghold / Treasury / Placeholder).
var _sub_tab_pages: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle (overrides notebook_tab_page._build_content)
# ---------------------------------------------------------------------------

func _build_content() -> void:
	_root_vbox = VBoxContainer.new()
	_root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_vbox.add_theme_constant_override("separation", 6)
	add_child(_root_vbox)
	_build_entity_strip()
	_build_status_header()
	_build_sub_tab_bar()
	_build_content_holder()
	_build_establish_dialog()
	_connect_signals()
	_restore_substate_and_refresh()


func _build_entity_strip() -> void:
	_entity_strip = HBoxContainer.new()
	_entity_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entity_strip.add_theme_constant_override("separation", 8)
	_root_vbox.add_child(_entity_strip)
	_entity_type_dropdown = OptionButton.new()
	_entity_type_dropdown.custom_minimum_size = Vector2(220, 0)
	for t in TYPE_ORDER:
		_entity_type_dropdown.add_item(TYPE_LABELS[t])
	_entity_type_dropdown.selected = 0
	_entity_type_dropdown.item_selected.connect(_on_type_selected)
	_entity_strip.add_child(_entity_type_dropdown)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_entity_strip.add_child(scroll)
	_entity_tabs_hbox = HBoxContainer.new()
	_entity_tabs_hbox.add_theme_constant_override("separation", 4)
	scroll.add_child(_entity_tabs_hbox)


func _build_status_header() -> void:
	_status_header = StatusHeaderScript.new()
	_root_vbox.add_child(_status_header)


func _build_sub_tab_bar() -> void:
	_sub_tab_bar = TabBar.new()
	_sub_tab_bar.tab_alignment = TabBar.ALIGNMENT_LEFT
	for entry in SUB_TABS:
		_sub_tab_bar.add_tab(String(entry["label"]))
	_sub_tab_bar.tab_changed.connect(_on_sub_tab_changed)
	_root_vbox.add_child(_sub_tab_bar)


func _build_content_holder() -> void:
	_content_holder = VBoxContainer.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(_content_holder)


func _build_establish_dialog() -> void:
	_establish_dialog = EstablishDomainDialogScript.new()
	_establish_dialog.domain_established_requested.connect(_on_domain_established)
	add_child(_establish_dialog)


func _connect_signals() -> void:
	EventBus.notebook_active_entity_changed.connect(_on_notebook_active_entity_changed)
	EventBus.active_party_changed.connect(_on_active_party_changed)
	EventBus.domain_treasury_changed.connect(_on_domain_data_changed)
	EventBus.domain_morale_changed.connect(_on_domain_data_changed)
	EventBus.classification_advanced.connect(_on_classification_changed)
	EventBus.classification_regressed.connect(_on_classification_changed)
	EventBus.land_value_improved.connect(_on_land_value_changed)
	EventBus.stronghold_sufficiency_changed.connect(_on_sufficiency_changed)
	EventBus.domain_decree_issued.connect(_on_decree_issued)
	EventBus.domain_established.connect(_on_domain_established_signal)
	EventBus.active_adventuring_resolved.connect(_on_active_adventuring_changed)


# ---------------------------------------------------------------------------
# Substate
# ---------------------------------------------------------------------------

func _restore_substate_and_refresh() -> void:
	var pid := _resolve_party_id()
	var sub := NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	_active_entity_type = String(sub.get("entity_type", TYPE_PCS))
	if not TYPE_ORDER.has(_active_entity_type):
		_active_entity_type = TYPE_PCS
	var per_type: Dictionary = sub.get("entity_per_type", {})
	_active_entity_id = String(per_type.get(_active_entity_type, ""))
	# Cross-tab activation override.
	var global_active: String = NotebookState.get_active_entity(pid)
	if not global_active.is_empty():
		var resolved_type := _resolve_entity_type(global_active)
		if not resolved_type.is_empty():
			_active_entity_type = resolved_type
			_active_entity_id = global_active
	_entity_type_dropdown.selected = TYPE_ORDER.find(_active_entity_type)
	_refresh_entity_strip()
	if _active_entity_id.is_empty():
		_active_entity_id = _first_entity_for_type(_active_entity_type)
	_render_active_entity_highlight()
	# Restore the per-entity sub-tab.
	var sub_per_entity: Dictionary = sub.get("sub_tab_per_entity", {})
	_active_sub_tab_id = String(sub_per_entity.get(_active_entity_id, "overview"))
	if not _is_valid_sub_tab(_active_sub_tab_id):
		_active_sub_tab_id = "overview"
	_sub_tab_bar.current_tab = _sub_tab_index(_active_sub_tab_id)
	_render_active_content()


func _persist_substate() -> void:
	var pid := _resolve_party_id()
	if pid.is_empty():
		return
	var existing := NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	var per_type: Dictionary = existing.get("entity_per_type", {})
	if not _active_entity_id.is_empty():
		per_type[_active_entity_type] = _active_entity_id
	var sub_per_entity: Dictionary = existing.get("sub_tab_per_entity", {})
	if not _active_entity_id.is_empty():
		sub_per_entity[_active_entity_id] = _active_sub_tab_id
	NotebookState.set_substate_for_tab(pid, SUBSTATE_TAB_ID, {
		"entity_type": _active_entity_type,
		"entity_per_type": per_type,
		"sub_tab_per_entity": sub_per_entity,
	})


# ---------------------------------------------------------------------------
# Entity strip
# ---------------------------------------------------------------------------

func _refresh_entity_strip() -> void:
	for child in _entity_tabs_hbox.get_children():
		_entity_tabs_hbox.remove_child(child)
		child.queue_free()
	var pid := _resolve_party_id()
	if pid.is_empty():
		return
	var entries := _load_entities(pid, _active_entity_type)
	for entry in entries:
		var btn := Button.new()
		btn.text = String(entry["display_name"])
		btn.toggle_mode = true
		btn.set_meta("entity_id", String(entry["id"]))
		btn.toggled.connect(_on_entity_btn_toggled.bind(btn))
		_entity_tabs_hbox.add_child(btn)


func _render_active_entity_highlight() -> void:
	for btn in _entity_tabs_hbox.get_children():
		if not (btn is Button):
			continue
		var b := btn as Button
		var meta_id := String(b.get_meta("entity_id", ""))
		b.button_pressed = meta_id == _active_entity_id


func _load_entities(party_id: String, entity_type: String) -> Array:
	var out: Array = []
	if entity_type == TYPE_PCS:
		for row in CampaignRepository.list_party_characters(party_id):
			out.append({
				"id":           String(row.get("id", "")),
				"display_name": String(row.get("name", "(unnamed)")),
			})
	elif entity_type == TYPE_HENCHMEN:
		var seen := {}
		for pc_row in CampaignRepository.list_party_characters(party_id):
			var pc_id: String = String(pc_row.get("id", ""))
			for h in CampaignRepository.get_henchmen_for_employer(pc_id):
				var hid := String(h.get("id", ""))
				if seen.has(hid):
					continue
				if not _is_humanoid(h):
					continue
				seen[hid] = true
				out.append({
					"id":           hid,
					"display_name": String(h.get("name", "(henchman)")),
				})
	return out


# Per gdd-domain-tab §3 the Domain tab filters henchmen to humanoids only.
# Phase 2 simplification: treat any race with humanoid morphology as humanoid.
# Animal/familiar henchmen do not have rule-text race entries — they are
# excluded by character_type ('henchman' rather than 'pc'/'familiar').
static func _is_humanoid(henchman_row: Dictionary) -> bool:
	var race: String = String(henchman_row.get("race", "human")).to_lower()
	# Anything we ship as a player race is humanoid; non-humanoid henchmen
	# (animal companions, familiars) live under a different character_type
	# and aren't returned by get_henchmen_for_employer.
	return race in ["human", "elf", "dwarf", "halfling", "gnome", "half-elf", "half-orc", "orc", "goblin", ""] or true


func _first_entity_for_type(entity_type: String) -> String:
	var pid := _resolve_party_id()
	var entries := _load_entities(pid, entity_type)
	if entries.is_empty():
		return ""
	return String(entries[0]["id"])


func _resolve_entity_type(entity_id: String) -> String:
	var pid := _resolve_party_id()
	for row in CampaignRepository.list_party_characters(pid):
		if String(row.get("id", "")) == entity_id:
			return TYPE_PCS
	for pc_row in CampaignRepository.list_party_characters(pid):
		var pc_id: String = String(pc_row.get("id", ""))
		for h in CampaignRepository.get_henchmen_for_employer(pc_id):
			if String(h.get("id", "")) == entity_id and _is_humanoid(h):
				return TYPE_HENCHMEN
	return ""


func _resolve_party_id() -> String:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	return pid


# ---------------------------------------------------------------------------
# Sub-tabs
# ---------------------------------------------------------------------------

func _is_valid_sub_tab(id: String) -> bool:
	for entry in SUB_TABS:
		if entry["id"] == id:
			return true
	return false


func _sub_tab_index(id: String) -> int:
	for i in range(SUB_TABS.size()):
		if SUB_TABS[i]["id"] == id:
			return i
	return 0


func _sub_tab_at_index(idx: int) -> String:
	if idx < 0 or idx >= SUB_TABS.size():
		return "overview"
	return String(SUB_TABS[idx]["id"])


func _ensure_sub_tab_page(sub_tab_id: String) -> Control:
	if _sub_tab_pages.has(sub_tab_id):
		return _sub_tab_pages[sub_tab_id]
	var entry: Dictionary = {}
	for e in SUB_TABS:
		if e["id"] == sub_tab_id:
			entry = e
			break
	if entry.is_empty():
		return null
	var script_kind: String = String(entry.get("script", "placeholder"))
	var page: Control = null
	match script_kind:
		"overview":
			page = OverviewSubTabScript.new()
		"stronghold":
			page = StrongholdSubTabScript.new()
		"treasury":
			page = TreasurySubTabScript.new()
		_:
			page = PlaceholderSubTabScript.new()
			page.setup(
				String(entry["label"]),
				String(entry.get("phase", "a future phase")),
				String(entry.get("description", "")))
	_sub_tab_pages[sub_tab_id] = page
	return page


# ---------------------------------------------------------------------------
# Content rendering
# ---------------------------------------------------------------------------

func _render_active_content() -> void:
	# Clear the content holder.
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
	if _empty_state != null and is_instance_valid(_empty_state):
		_empty_state.queue_free()
		_empty_state = null
	# If the active entity owns no domain, render the empty-state page across
	# the full content area (sub-tab strip stays visible but inert).
	if _active_entity_id.is_empty():
		_render_no_entity_state()
		return
	var domain := _resolve_domain_for_active_entity()
	if domain.is_empty():
		_render_acquisition_empty_state()
		_status_header.display({})
		return
	_status_header.display(domain)
	# Render the active sub-tab's content.
	var page := _ensure_sub_tab_page(_active_sub_tab_id)
	if page == null:
		return
	if page.has_method("display"):
		page.call("display", domain)
	_content_holder.add_child(page)


func _render_no_entity_state() -> void:
	_status_header.display({})
	_empty_state = _DomainEmptyStatePageScript.new()
	_empty_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_holder.add_child(_empty_state)
	_empty_state.configure(
		"No active entity",
		"Select a PC or humanoid henchman from the entity strip above to view their domain.",
		[],
		null)


func _render_acquisition_empty_state() -> void:
	_empty_state = _DomainEmptyStatePageScript.new()
	_empty_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_holder.add_child(_empty_state)
	_empty_state.configure(
		"No domain yet",
		_acquisition_guidance_text(),
		[{"text": "Establish a domain…", "id": "establish_domain"}],
		null)
	_empty_state.link_activated.connect(_on_empty_state_link)


func _acquisition_guidance_text() -> String:
	var character := _resolve_active_character()
	if character.is_empty():
		return "Select an entity to see acquisition guidance."
	var class_id := String(character.get("character_class", "")).to_lower()
	var alignment := String(character.get("alignment", "neutral")).to_lower()
	var lines: Array[String] = []
	lines.append("A domain is land you have claimed, secured, and govern.")
	lines.append("")
	lines.append("Available paths for your class (%s):" % class_id.capitalize())
	if EstablishDomainFlow.EXPLORER_CLASS_IDS.has(class_id):
		lines.append("  • Borderlands or wilderness only — Explorer stronghold (border fort) is restricted to those classifications.")
	elif EstablishDomainFlow.DWARVEN_CLASS_IDS.has(class_id):
		lines.append("  • Wilderness always available; civilized/borderlands require own-race areas (dwarven vault).")
	elif EstablishDomainFlow.ELVEN_CLASS_IDS.has(class_id):
		lines.append("  • Wilderness always available; civilized/borderlands require own-race areas (elven fastness).")
	else:
		lines.append("  • Civilized: land grant, purchase (50 gp/acre), or conquest.")
		lines.append("  • Borderlands: clear lairs, conquest, or grant from a liege.")
		lines.append("  • Wilderness: clear lairs, conquest, or grant.")
	if alignment == "chaotic":
		lines.append("  • Chaotic alignment unlocks clanhold annexation and recruit-chieftain paths.")
	lines.append("")
	lines.append("Press Establish a domain… to begin.")
	return "\n".join(lines)


func _resolve_domain_for_active_entity() -> Dictionary:
	if _active_entity_id.is_empty():
		return {}
	var campaign_id: String = GameState.campaign_id
	if campaign_id.is_empty():
		return {}
	var domains := CampaignRepository.list_campaign_domains(campaign_id)
	for d in domains:
		if String(d.get("owner_character_id", "")) == _active_entity_id:
			return d
	return {}


func _resolve_active_character() -> Dictionary:
	if _active_entity_id.is_empty():
		return {}
	return CampaignRepository.get_character(_active_entity_id)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_type_selected(idx: int) -> void:
	if idx < 0 or idx >= TYPE_ORDER.size():
		return
	_active_entity_type = TYPE_ORDER[idx]
	_active_entity_id = ""
	_refresh_entity_strip()
	_active_entity_id = _first_entity_for_type(_active_entity_type)
	_render_active_entity_highlight()
	_render_active_content()
	_persist_substate()


func _on_entity_btn_toggled(pressed: bool, btn: Button) -> void:
	if not pressed:
		# User toggled off — reapply highlight to keep one selected.
		_render_active_entity_highlight()
		return
	var new_id := String(btn.get_meta("entity_id", ""))
	if new_id == _active_entity_id:
		return
	_active_entity_id = new_id
	# Restore the persisted sub-tab for this entity, defaulting to overview.
	var pid := _resolve_party_id()
	var sub := NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	var sub_per_entity: Dictionary = sub.get("sub_tab_per_entity", {})
	_active_sub_tab_id = String(sub_per_entity.get(_active_entity_id, "overview"))
	if not _is_valid_sub_tab(_active_sub_tab_id):
		_active_sub_tab_id = "overview"
	_sub_tab_bar.current_tab = _sub_tab_index(_active_sub_tab_id)
	_render_active_entity_highlight()
	_render_active_content()
	_persist_substate()
	# Cross-route via global signal so Character tab also refreshes.
	EventBus.notebook_active_entity_requested.emit(_active_entity_id)


func _on_sub_tab_changed(idx: int) -> void:
	var new_id := _sub_tab_at_index(idx)
	if new_id == _active_sub_tab_id:
		return
	_active_sub_tab_id = new_id
	_render_active_content()
	_persist_substate()


func _on_notebook_active_entity_changed(entity_id: String) -> void:
	if entity_id == _active_entity_id:
		return
	# Resolve which entity-type strip the new entity belongs to.
	var resolved_type := _resolve_entity_type(entity_id)
	if resolved_type.is_empty():
		# Entity is not eligible for the Domain tab (e.g., trained animal).
		# Leave the current selection alone.
		return
	var type_changed := resolved_type != _active_entity_type
	_active_entity_type = resolved_type
	_active_entity_id = entity_id
	if type_changed:
		_entity_type_dropdown.selected = TYPE_ORDER.find(_active_entity_type)
		_refresh_entity_strip()
	_render_active_entity_highlight()
	# Restore sub-tab for this entity.
	var pid := _resolve_party_id()
	var sub := NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	var sub_per_entity: Dictionary = sub.get("sub_tab_per_entity", {})
	_active_sub_tab_id = String(sub_per_entity.get(_active_entity_id, "overview"))
	if not _is_valid_sub_tab(_active_sub_tab_id):
		_active_sub_tab_id = "overview"
	_sub_tab_bar.current_tab = _sub_tab_index(_active_sub_tab_id)
	_render_active_content()
	_persist_substate()


func _on_active_party_changed(_old: String, _new: String) -> void:
	_sub_tab_pages.clear()
	_restore_substate_and_refresh()


func _on_empty_state_link(link_id: String) -> void:
	if link_id == "establish_domain":
		_open_establish_dialog()


func _open_establish_dialog() -> void:
	var character := _resolve_active_character()
	if character.is_empty():
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "system",
			"title": "Select an entity first",
			"body": "Pick a PC or humanoid henchman from the entity strip before establishing a domain.",
		})
		return
	var campaign_id: String = GameState.campaign_id
	_establish_dialog.setup(campaign_id, character)
	_establish_dialog.popup_centered(Vector2(540, 480))


func _on_domain_established(_domain_id: String) -> void:
	# Refresh the Domain tab so the new domain renders.
	_render_active_content()


func _on_domain_established_signal(_domain_id: String, _owner: String, _classification: String, _method: String) -> void:
	# Pure refresh — the dialog also fires its own callback above when the
	# player drove the establishment from this surface.
	_render_active_content()


func _on_domain_data_changed(_domain_id: String, _a = null, _b = null) -> void:
	_render_active_content()


func _on_classification_changed(_domain_id: String, _old: String, _new: String) -> void:
	_render_active_content()


func _on_land_value_changed(_domain_id: String, _q: int, _r: int, _v: int, _c: int) -> void:
	_render_active_content()


func _on_sufficiency_changed(_domain_id: String, _is_sufficient: bool, _v: int, _m: int) -> void:
	_render_active_content()


func _on_decree_issued(_domain_id: String, _decree_type: String, _payload: Dictionary) -> void:
	_render_active_content()


func _on_active_adventuring_changed(_domain_id: String, _calendar_day: int, _is_active: bool) -> void:
	_render_active_content()
