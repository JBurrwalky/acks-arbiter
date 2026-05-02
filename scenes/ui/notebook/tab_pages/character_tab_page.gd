extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Character tab — γ.1 migration target. Hosts:
##   - Entity strip (type dropdown + horizontal EntityTab row)
##   - Sheet section sub-tab strip (entity-type-filtered)
##   - Active section's content (cs_tab_*.gd, cs_tab_creature_*.gd, or
##     cs_vehicle_detail_panel.gd)
##
## Per gdd-character-tab.md §2 / gdd-management-notebook.md §3.5 / §6.3.
##
## Cross-tab activation: when EventBus.notebook_active_entity_requested fires
## from another caller (e.g., a SessionStatusBar portrait click in γ.4), the
## Notebook root sets NotebookState's active entity and switches to this tab;
## this page consumes notebook_active_entity_changed to re-render.

const EntityStripScript := preload("res://scenes/ui/notebook/character/entity_strip.gd")
const SheetSectionStripScript := preload("res://scenes/ui/notebook/character/sheet_section_strip.gd")

# Tab id used when persisting per-tab substate via NotebookState.
const SUBSTATE_TAB_ID := "character"

# section_id -> {script: GDScript, kind: "character"|"creature"|"vehicle"}
const SECTION_DEFS := {
	"biography":          {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_biography.gd"),          "kind": "character"},
	"attributes":         {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_attributes.gd"),         "kind": "character"},
	"combat":             {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_combat.gd"),             "kind": "character"},
	"equipment":          {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_equipment.gd"),          "kind": "character"},
	"retainers":          {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_retainers.gd"),          "kind": "character"},
	"proficiencies":      {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_proficiencies.gd"),      "kind": "character"},
	"spells":             {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_spells.gd"),             "kind": "character"},
	"advancement":        {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_advancement.gd"),        "kind": "character"},
	"effects":            {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_effects.gd"),            "kind": "character"},
	"creature_stats":     {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_creature_stats.gd"),     "kind": "creature"},
	"creature_inventory": {"script": preload("res://scenes/ui/character_sheet/tabs/cs_tab_creature_inventory.gd"), "kind": "creature"},
	"vehicle_detail":     {"script": preload("res://scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd"),   "kind": "vehicle"},
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _entity_strip: Control = null
var _section_strip: Control = null
var _content_holder: Control = null
var _content_scroll: ScrollContainer = null

## section_id -> instance (cs_tab_* / cs_tab_creature_* / cs_vehicle_detail_panel)
var _section_pages: Dictionary = {}

## Active state (mirrored to NotebookState's per-tab substate).
var _active_entity_type: String = "pcs"
var _active_entity_id: String = ""
var _active_section_id: String = ""

## Cached display data so signal handlers can refresh without reloading.
var _active_bundle: CharacterBundle = null
var _active_creature: TrainedCreatureData = null
var _active_vehicle_bundle: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle (overrides notebook_tab_page._build_content)
# ---------------------------------------------------------------------------

func _build_content() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_entity_strip = EntityStripScript.new()
	vbox.add_child(_entity_strip)
	_entity_strip.type_changed.connect(_on_type_changed)
	_entity_strip.entity_selected.connect(_on_entity_strip_selected)

	_section_strip = SheetSectionStripScript.new()
	vbox.add_child(_section_strip)
	_section_strip.section_selected.connect(_on_section_selected)

	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_scroll)

	_content_holder = VBoxContainer.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.add_child(_content_holder)

	_connect_signals()
	_restore_substate_and_refresh()


func _connect_signals() -> void:
	# Cross-tab entity switching from anywhere — Notebook root has already set
	# NotebookState; we just re-render.
	EventBus.notebook_active_entity_changed.connect(_on_notebook_active_entity_changed)
	EventBus.notebook_closed.connect(_on_notebook_closed)
	EventBus.active_party_changed.connect(_on_active_party_changed)
	# Live-refresh signals mirroring CharacterSheetOverlay._connect_signals.
	EventBus.hp_changed.connect(_on_character_data_changed)
	EventBus.inventory_updated.connect(_on_character_data_changed)
	EventBus.condition_changed.connect(_on_character_data_changed_dict)
	EventBus.xp_awarded.connect(_on_character_data_changed_int)
	EventBus.character_leveled_up.connect(_on_character_data_changed_int)
	EventBus.proficiency_changed.connect(_on_character_data_changed_dict)
	EventBus.active_effect_expired.connect(_on_character_data_changed)
	EventBus.spell_effect_applied.connect(_on_spell_effect_changed)
	EventBus.spell_effect_removed.connect(_on_spell_effect_removed)
	EventBus.override_applied.connect(_on_override_applied)
	EventBus.loyalty_changed.connect(_on_character_data_changed_int)
	EventBus.age_category_changed.connect(_on_age_category_changed)
	EventBus.creature_hp_changed.connect(_on_creature_changed_int)
	EventBus.creature_inventory_updated.connect(_on_creature_changed)
	EventBus.creature_added.connect(_on_creature_list_changed)
	EventBus.creature_removed.connect(_on_creature_list_changed)
	EventBus.creature_died.connect(_on_creature_changed)
	EventBus.vehicle_changed.connect(_on_vehicle_list_changed)
	EventBus.vehicle_hitch_changed.connect(_on_vehicle_changed)


# ---------------------------------------------------------------------------
# Substate (per-party persistence via NotebookState)
# ---------------------------------------------------------------------------

func _restore_substate_and_refresh() -> void:
	var pid: String = _resolve_party_id()
	var sub: Dictionary = NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	_active_entity_type = sub.get("entity_type", "pcs")
	var per_type: Dictionary = sub.get("entity_per_type", {})
	var preferred_section: String = sub.get("section_id", "")

	# If NotebookState has a globally-active entity (set via cross-tab), prefer
	# that over the per-type memory.
	var global_active: String = NotebookState.get_active_entity(pid)
	_active_entity_id = global_active if not global_active.is_empty() else str(per_type.get(_active_entity_type, ""))

	_entity_strip.set_active_type(_active_entity_type)
	_entity_strip.refresh(pid)
	# If no entity remembered for the active type, fall back to first listed.
	if _active_entity_id.is_empty():
		_active_entity_id = _first_entity_in_strip()
	_entity_strip.set_active_entity(_active_entity_id)

	_section_strip.set_entity_type(_active_entity_type, preferred_section)
	_active_section_id = _section_strip.active_section()
	_render_active_section()


func _persist_substate() -> void:
	var pid: String = _resolve_party_id()
	if pid.is_empty():
		return
	var existing := NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	var per_type: Dictionary = existing.get("entity_per_type", {})
	if not _active_entity_id.is_empty():
		per_type[_active_entity_type] = _active_entity_id
	NotebookState.set_substate_for_tab(pid, TAB_ID, {
		"entity_type": _active_entity_type,
		"entity_per_type": per_type,
		"section_id": _active_section_id,
	})


# ---------------------------------------------------------------------------
# Section rendering
# ---------------------------------------------------------------------------

func _render_active_section() -> void:
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
	if _active_section_id.is_empty():
		return
	if not SECTION_DEFS.has(_active_section_id):
		return
	var page: Node = _ensure_section_page(_active_section_id)
	_content_holder.add_child(page)
	_dispatch_display(page, _active_section_id)


func _ensure_section_page(section_id: String) -> Node:
	if _section_pages.has(section_id) and is_instance_valid(_section_pages[section_id]):
		return _section_pages[section_id]
	var def: Dictionary = SECTION_DEFS[section_id]
	var inst: Node = def["script"].new()
	if inst is Control:
		(inst as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_pages[section_id] = inst
	return inst


func _dispatch_display(page: Node, section_id: String) -> void:
	var def: Dictionary = SECTION_DEFS[section_id]
	var kind: String = def["kind"]
	var reg: Dictionary = SheetRegistries.get_or_create()
	match kind:
		"character":
			if _active_bundle == null:
				_active_bundle = _load_character_bundle(_active_entity_id)
			page.display(_active_bundle, reg)
		"creature":
			if _active_creature == null:
				_active_creature = _load_creature(_active_entity_id)
			# Creature stats sub-tab needs party_characters for handler tier.
			var creature_reg := reg.duplicate()
			creature_reg["party_characters"] = _load_party_characters_for_creature_handlers()
			page.display(_active_creature, creature_reg)
		"vehicle":
			if _active_vehicle_bundle.is_empty():
				_active_vehicle_bundle = _load_vehicle_bundle(_active_entity_id)
			page.display(_active_vehicle_bundle, reg)


# ---------------------------------------------------------------------------
# Entity loading (mirrors CharacterSheetOverlay._load_*)
# ---------------------------------------------------------------------------

func _load_character_bundle(character_id: String) -> CharacterBundle:
	var bundle := CharacterBundle.new()
	if character_id.is_empty():
		return bundle
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		return bundle
	bundle.character = CharacterData.from_dict(row)
	bundle.proficiencies = CampaignRepository.get_character_proficiencies(character_id)
	bundle.inventory = CampaignRepository.get_inventory_items(character_id)
	bundle.spells = CampaignRepository.get_character_spells(character_id)
	bundle.formulas = CampaignRepository.get_character_formulas(character_id)
	bundle.expended_slots = CampaignRepository.get_expended_slots(character_id)
	bundle.powers = CampaignRepository.get_character_powers(character_id)
	bundle.conditions = CampaignRepository.get_conditions(character_id)
	bundle.active_effects = CampaignRepository.get_active_effects_on_target(character_id, GameState.campaign_id)
	bundle.henchmen = CampaignRepository.get_henchmen_for_employer(character_id)
	bundle.character.proficiencies = bundle.proficiencies
	return bundle


func _load_creature(creature_id: String) -> TrainedCreatureData:
	if creature_id.is_empty():
		return null
	var row := CampaignRepository.get_trained_creature(creature_id)
	if row.is_empty():
		return null
	var creature := TrainedCreatureData.from_db(row)
	var monster_registry: MonsterRegistry = SheetRegistries.get_or_create().get("monster_registry")
	if monster_registry != null:
		creature.monster_data = monster_registry.get_monster(creature.species_id)
	creature.inventory = []
	for inv_row in CampaignRepository.get_creature_inventory(creature_id):
		creature.inventory.append(InventoryItem.from_dict(inv_row))
	return creature


func _load_vehicle_bundle(vehicle_id: String) -> Dictionary:
	if vehicle_id.is_empty():
		return {"vehicle": {}, "items": [], "hitched_creatures": [], "all_creatures": [], "all_vehicles": []}
	var vehicle := CampaignRepository.get_draft_vehicle(vehicle_id)
	if vehicle.is_empty():
		return {"vehicle": {}, "items": [], "hitched_creatures": [], "all_creatures": [], "all_vehicles": []}
	var items := CampaignRepository.get_items_in_vehicle(vehicle_id)

	var hitched_json: String = str(vehicle.get("hitched_creatures", "[]"))
	var hitched_ids: Variant = JSON.parse_string(hitched_json)
	var hitched_creatures: Array = []
	if hitched_ids is Array:
		for cid in hitched_ids:
			var c := _load_creature(str(cid))
			if c != null:
				hitched_creatures.append(c)

	var pid: String = _resolve_party_id()
	var all_creatures: Array = []
	for row in CampaignRepository.get_trained_creatures_for_party(pid):
		var c := TrainedCreatureData.from_db(row)
		var monster_registry: MonsterRegistry = SheetRegistries.get_or_create().get("monster_registry")
		if monster_registry != null:
			c.monster_data = monster_registry.get_monster(c.species_id)
		c.inventory = []
		for inv_row in CampaignRepository.get_creature_inventory(c.id):
			c.inventory.append(InventoryItem.from_dict(inv_row))
		all_creatures.append(c)
	var all_vehicles := CampaignRepository.get_draft_vehicles_for_party(pid)
	return {
		"vehicle":           vehicle,
		"items":             items,
		"hitched_creatures": hitched_creatures,
		"all_creatures":     all_creatures,
		"all_vehicles":      all_vehicles,
	}


func _load_party_characters_for_creature_handlers() -> Array:
	var pid: String = _resolve_party_id()
	var out: Array = []
	for row in CampaignRepository.list_party_characters(pid):
		var cd := CharacterData.from_dict(row)
		cd.proficiencies = CampaignRepository.get_character_proficiencies(cd.id)
		out.append(cd)
	return out


func _resolve_party_id() -> String:
	# Mirror CharacterSheetOverlay's pattern: prefer active_party_id, fall
	# back to the legacy single party_id slot for code paths (and tests) that
	# initialize one but not the other.
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	return pid


func _first_entity_in_strip() -> String:
	# Fallback: pick the first id in the active type's repository list. Mirrors
	# CharacterSheetOverlay._auto_select_first_entity().
	var pid: String = _resolve_party_id()
	match _active_entity_type:
		"pcs":
			var members := CampaignRepository.list_party_characters(pid)
			if not members.is_empty():
				return str(members[0].get("id", ""))
		"henchmen":
			for pc_row in CampaignRepository.list_party_characters(pid):
				var hs := CampaignRepository.get_henchmen_for_employer(str(pc_row.get("id", "")))
				if not hs.is_empty():
					return str(hs[0].get("id", ""))
		"animals":
			var creatures := CampaignRepository.get_trained_creatures_for_party(pid)
			if not creatures.is_empty():
				return str(creatures[0].get("id", ""))
		"vehicles":
			var vs := CampaignRepository.get_draft_vehicles_for_party(pid)
			if not vs.is_empty():
				return str(vs[0].get("id", ""))
	return ""


# ---------------------------------------------------------------------------
# Cache invalidation helpers
# ---------------------------------------------------------------------------

func _invalidate_active_caches() -> void:
	_active_bundle = null
	_active_creature = null
	_active_vehicle_bundle = {}


func _refresh_active_section() -> void:
	_invalidate_active_caches()
	_render_active_section()


# ---------------------------------------------------------------------------
# Signal handlers — strip / section
# ---------------------------------------------------------------------------

func _on_type_changed(entity_type: String) -> void:
	_abort_pending_advancement_if_needed()
	_active_entity_type = entity_type
	_active_entity_id = ""
	_invalidate_active_caches()
	# Rebuild entity strip for the new type.
	_entity_strip.refresh(_resolve_party_id())
	_active_entity_id = _first_entity_in_strip()
	_entity_strip.set_active_entity(_active_entity_id)
	# Rebuild section strip; this triggers section_selected → render.
	_section_strip.set_entity_type(_active_entity_type)
	_active_section_id = _section_strip.active_section()
	_render_active_section()
	_persist_substate()


func _on_entity_strip_selected(entity_id: String, _entity_type: String) -> void:
	# Route through the global cross-tab signal; Notebook root will set
	# NotebookState and emit notebook_active_entity_changed, which we consume
	# below to actually re-render.
	EventBus.notebook_active_entity_requested.emit(entity_id)


func _on_section_selected(section_id: String) -> void:
	if section_id == _active_section_id:
		return
	# Switching away from the Advancement sub-tab discards any in-progress
	# preview level-up. Mirrors CharacterSheetOverlay._on_tab_changed.
	if _active_section_id == "advancement":
		_abort_pending_advancement_if_needed()
	_active_section_id = section_id
	_render_active_section()
	_persist_substate()


# ---------------------------------------------------------------------------
# Signal handlers — global
# ---------------------------------------------------------------------------

func _on_notebook_active_entity_changed(entity_id: String) -> void:
	if entity_id == _active_entity_id:
		return
	_abort_pending_advancement_if_needed()
	_active_entity_id = entity_id
	_invalidate_active_caches()
	_entity_strip.set_active_entity(entity_id)
	_render_active_section()
	_persist_substate()


func _on_notebook_closed() -> void:
	# Closing the notebook discards any in-progress level-up preview, mirroring
	# CharacterSheetOverlay._close.
	_abort_pending_advancement_if_needed()


func _on_active_party_changed(_previous: String, _new: String) -> void:
	# Reload everything; substate will be restored from the new party's slot.
	_abort_pending_advancement_if_needed()
	_invalidate_active_caches()
	_section_pages.clear()  # any per-character cached widgets are stale
	_restore_substate_and_refresh()


# ---------------------------------------------------------------------------
# Internal — Advancement abort helper
# ---------------------------------------------------------------------------

func _abort_pending_advancement_if_needed() -> void:
	if not _section_pages.has("advancement"):
		return
	var page: Node = _section_pages["advancement"]
	if page == null or not is_instance_valid(page):
		return
	if page.has_method("has_pending_level_up") and page.has_method("abort_pending_level_up"):
		if page.has_pending_level_up():
			page.abort_pending_level_up()


# ---------------------------------------------------------------------------
# Signal handlers — live data refresh (mirrors CharacterSheetOverlay)
# ---------------------------------------------------------------------------

func _on_character_data_changed(target_id: String, _a = null, _b = null) -> void:
	if _active_entity_type in ["pcs", "henchmen", "merc_officers"] and target_id == _active_entity_id:
		_refresh_active_section()


func _on_character_data_changed_dict(target_id: String, _payload: Dictionary) -> void:
	_on_character_data_changed(target_id)


func _on_character_data_changed_int(target_id: String, _value: int) -> void:
	_on_character_data_changed(target_id)


func _on_spell_effect_changed(_effect_id: String, _spell_key: String, target_ids: Array) -> void:
	if _active_entity_type in ["pcs", "henchmen", "merc_officers"] and _active_entity_id in target_ids:
		_refresh_active_section()


func _on_spell_effect_removed(_effect_id: String, _spell_key: String) -> void:
	if _active_entity_type in ["pcs", "henchmen", "merc_officers"] and not _active_entity_id.is_empty():
		_refresh_active_section()


func _on_override_applied(_type: String, target_id: String, _field: String) -> void:
	_on_character_data_changed(target_id)


func _on_age_category_changed(target_id: String, _old: String, _new: String) -> void:
	_on_character_data_changed(target_id)


func _on_creature_changed_int(creature_id: String, _a: int, _b: int) -> void:
	if _active_entity_type == "animals" and creature_id == _active_entity_id:
		_refresh_active_section()


func _on_creature_changed(creature_id: String) -> void:
	if _active_entity_type == "animals" and creature_id == _active_entity_id:
		_refresh_active_section()
	# Vehicle hitching may also need refresh if a creature's saddle changed.
	if _active_entity_type == "vehicles" and not _active_entity_id.is_empty():
		_refresh_active_section()


func _on_creature_list_changed(_party_id: String, _creature_id: String) -> void:
	if _active_entity_type == "animals":
		_entity_strip.refresh(_resolve_party_id())
		if _active_entity_id.is_empty() or not _entity_exists_in_active_type(_active_entity_id):
			_active_entity_id = _first_entity_in_strip()
			_entity_strip.set_active_entity(_active_entity_id)
		_refresh_active_section()


func _on_vehicle_list_changed(_party_id: String, _vehicle_id: String) -> void:
	if _active_entity_type == "vehicles":
		_entity_strip.refresh(_resolve_party_id())
		if _active_entity_id.is_empty() or not _entity_exists_in_active_type(_active_entity_id):
			_active_entity_id = _first_entity_in_strip()
			_entity_strip.set_active_entity(_active_entity_id)
		_refresh_active_section()


func _on_vehicle_changed(vehicle_id: String) -> void:
	if _active_entity_type == "vehicles" and vehicle_id == _active_entity_id:
		_refresh_active_section()


func _entity_exists_in_active_type(entity_id: String) -> bool:
	var pid: String = _resolve_party_id()
	match _active_entity_type:
		"animals":
			for row in CampaignRepository.get_trained_creatures_for_party(pid):
				if str(row.get("id", "")) == entity_id:
					return true
		"vehicles":
			for v in CampaignRepository.get_draft_vehicles_for_party(pid):
				if str(v.get("id", "")) == entity_id:
					return true
	return false
