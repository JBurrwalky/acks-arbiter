extends CanvasLayer

## Character Sheet Overlay (O-02)
##
## Persistent in-game overlay for viewing Characters, Animals, Vehicles,
## Henchmen, and Mercenaries. Left sidebar has category buttons + entity list.
## Right side swaps between content panels per category.
##
## Toggle with F7 (character_sheet_toggle input action). Right-anchored panel,
## non-modal — the game world remains visible and interactive behind it.

# ---------------------------------------------------------------------------
# Registries
# ---------------------------------------------------------------------------

var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry
var _spell_registry: SpellRegistry
var _power_registry: PowerRegistry
var _spec_registry: SpecializationRegistry
var _monster_registry: MonsterRegistry
var _equipment_catalog: EquipmentCatalog

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _active_category: String = "characters"
var _bundle: CharacterBundle = null
var _displayed_character_id: String = ""
var _displayed_entity_id: String = ""
var _party_ids: Array = []
var _creature_ids: Array = []
var _vehicle_ids: Array = []
var _henchman_ids: Array = []

# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _panel: PanelContainer
var _title_label: Label
var _entity_list: ItemList

# Content panels (visibility-toggled)
var _content_area: Control
var _tab_container: TabContainer
var _creature_tab_container: TabContainer
var _vehicle_scroll: ScrollContainer
var _henchmen_panel: CSPlaceholderPanel
var _mercenaries_panel: CSPlaceholderPanel

# ---------------------------------------------------------------------------
# Character tabs
# ---------------------------------------------------------------------------

var _tab_biography: CSTabBiography
var _tab_attributes: CSTabAttributes
var _tab_combat: CSTabCombat
var _tab_equipment: CSTabEquipment
var _tab_proficiencies: CSTabProficiencies
var _tab_spells: CSTabSpells
var _tab_advancement: CSTabAdvancement
var _tab_effects: CSTabEffects
var _tab_retainers: CSTabRetainers

# ---------------------------------------------------------------------------
# Creature tabs
# ---------------------------------------------------------------------------

var _tab_creature_stats: CSTabCreatureStats
var _tab_creature_inventory: CSTabCreatureInventory

# ---------------------------------------------------------------------------
# Vehicle panel
# ---------------------------------------------------------------------------

var _vehicle_panel: CSVehicleDetailPanel


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 48
	visible = false
	_init_registries()
	_build_ui()
	_connect_signals()


func _init_registries() -> void:
	_spec_registry = SpecializationRegistry.new()
	_class_registry = ClassRegistry.new()
	_proficiency_registry = ProficiencyRegistry.new(_spec_registry)
	_spell_registry = SpellRegistry.new()
	_power_registry = PowerRegistry.new()
	_monster_registry = MonsterRegistry.new()
	_equipment_catalog = EquipmentCatalog.new()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.34
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 12)
	root_margin.add_theme_constant_override("margin_right", 12)
	root_margin.add_theme_constant_override("margin_top", 12)
	root_margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 4)
	root_margin.add_child(root_vbox)

	# -- Title bar --
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = "Character Sheet"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 14)
	title_row.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.flat = true
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)

	root_vbox.add_child(HSeparator.new())

	# -- Body: sidebar + content area --
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root_vbox.add_child(body)

	# --- Sidebar ---
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(130, 0)
	sidebar.add_theme_constant_override("separation", 2)
	body.add_child(sidebar)

	var roster_header := Label.new()
	roster_header.text = "Roster"
	roster_header.add_theme_font_size_override("font_size", 11)
	sidebar.add_child(roster_header)

	# Category buttons
	var btn_group := ButtonGroup.new()
	var categories := [
		["Characters", "characters"],
		["Henchmen", "henchmen"],
		["Animals", "animals"],
		["Vehicles", "vehicles"],
		["Mercenaries", "mercenaries"],
	]
	var cat_vbox := VBoxContainer.new()
	cat_vbox.add_theme_constant_override("separation", 1)
	sidebar.add_child(cat_vbox)

	for i in range(categories.size()):
		var cat_def: Array = categories[i]
		var btn := Button.new()
		btn.text = cat_def[0]
		btn.toggle_mode = true
		btn.button_group = btn_group
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 10)
		if i == 0:
			btn.button_pressed = true
		btn.toggled.connect(_on_category_toggled.bind(cat_def[1]))
		cat_vbox.add_child(btn)

	sidebar.add_child(HSeparator.new())

	# Entity list
	_entity_list = ItemList.new()
	_entity_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entity_list.item_selected.connect(_on_entity_selected)
	sidebar.add_child(_entity_list)

	body.add_child(VSeparator.new())

	# --- Content area ---
	_content_area = Control.new()
	_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content_area)

	# Character tabs
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_area.add_child(_tab_container)
	_build_character_tabs()
	_tab_container.tab_changed.connect(_on_tab_changed)

	# Creature tabs
	_creature_tab_container = TabContainer.new()
	_creature_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creature_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_creature_tab_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_creature_tab_container.visible = false
	_content_area.add_child(_creature_tab_container)
	_build_creature_tabs()

	# Vehicle panel
	_vehicle_scroll = ScrollContainer.new()
	_vehicle_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vehicle_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vehicle_scroll.visible = false
	_content_area.add_child(_vehicle_scroll)
	_vehicle_panel = CSVehicleDetailPanel.new()
	_vehicle_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_scroll.add_child(_vehicle_panel)

	# Henchmen placeholder
	_henchmen_panel = CSPlaceholderPanel.new("Henchmen management coming soon.")
	_henchmen_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_henchmen_panel.visible = false
	_content_area.add_child(_henchmen_panel)

	# Mercenaries placeholder
	_mercenaries_panel = CSPlaceholderPanel.new("Mercenaries management coming soon.")
	_mercenaries_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mercenaries_panel.visible = false
	_content_area.add_child(_mercenaries_panel)


func _build_character_tabs() -> void:
	_tab_biography = CSTabBiography.new()
	_tab_attributes = CSTabAttributes.new()
	_tab_combat = CSTabCombat.new()
	_tab_equipment = CSTabEquipment.new()
	_tab_retainers = CSTabRetainers.new()
	_tab_proficiencies = CSTabProficiencies.new()
	_tab_spells = CSTabSpells.new()
	_tab_advancement = CSTabAdvancement.new()
	_tab_effects = CSTabEffects.new()

	var defs: Array = [
		["Biography",     _tab_biography],
		["Attributes",    _tab_attributes],
		["Combat",        _tab_combat],
		["Equipment",     _tab_equipment],
		["Retainers",     _tab_retainers],
		["Proficiencies", _tab_proficiencies],
		["Spells",        _tab_spells],
		["Advancement",   _tab_advancement],
		["Effects",       _tab_effects],
	]
	for def in defs:
		var scroll := ScrollContainer.new()
		scroll.name = def[0]
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var tab: VBoxContainer = def[1]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(tab)
		_tab_container.add_child(scroll)


func _build_creature_tabs() -> void:
	_tab_creature_stats = CSTabCreatureStats.new()
	_tab_creature_inventory = CSTabCreatureInventory.new()

	var defs: Array = [
		["Stats",     _tab_creature_stats],
		["Inventory", _tab_creature_inventory],
	]
	for def in defs:
		var scroll := ScrollContainer.new()
		scroll.name = def[0]
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var tab: VBoxContainer = def[1]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(tab)
		_creature_tab_container.add_child(scroll)


func _connect_signals() -> void:
	# Character signals
	EventBus.hp_changed.connect(_on_hp_changed)
	EventBus.inventory_updated.connect(_on_inventory_updated)
	EventBus.condition_changed.connect(_on_condition_changed)
	EventBus.xp_awarded.connect(_on_xp_awarded)
	EventBus.character_leveled_up.connect(_on_character_leveled_up)
	EventBus.proficiency_changed.connect(_on_proficiency_changed)
	EventBus.active_effect_expired.connect(_on_active_effect_expired)
	EventBus.spell_effect_applied.connect(_on_spell_effect_applied)
	EventBus.spell_effect_removed.connect(_on_spell_effect_removed)
	EventBus.override_applied.connect(_on_override_applied)
	EventBus.character_sheet_requested.connect(open)
	EventBus.loyalty_changed.connect(_on_loyalty_changed)
	EventBus.age_category_changed.connect(_on_age_category_changed)
	# Creature signals
	EventBus.creature_hp_changed.connect(_on_creature_hp_changed)
	EventBus.creature_inventory_updated.connect(_on_creature_inventory_updated)
	EventBus.creature_added.connect(_on_creature_list_changed)
	EventBus.creature_removed.connect(_on_creature_list_changed)
	EventBus.creature_died.connect(_on_creature_died)
	# Vehicle signals
	EventBus.vehicle_changed.connect(_on_vehicle_list_changed)
	EventBus.vehicle_hitch_changed.connect(_on_vehicle_hitch_changed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(character_id: String = "") -> void:
	visible = true
	_load_entity_list(_active_category)
	if _active_category == "characters":
		if character_id.is_empty() and not _party_ids.is_empty():
			character_id = _party_ids[0]
		if not character_id.is_empty():
			_select_character(character_id)
	else:
		_auto_select_first_entity()


func toggle() -> void:
	if visible:
		_close()
	else:
		open()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("character_sheet_toggle"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Category switching
# ---------------------------------------------------------------------------

func _on_category_toggled(pressed: bool, category: String) -> void:
	if not pressed:
		return
	if category == _active_category:
		return
	_abort_pending_advancement_if_needed()
	_active_category = category
	_swap_content(category)
	_load_entity_list(category)
	_auto_select_first_entity()


func _swap_content(category: String) -> void:
	_tab_container.visible = (category == "characters")
	_creature_tab_container.visible = (category == "animals")
	_vehicle_scroll.visible = (category == "vehicles")
	_henchmen_panel.visible = (category == "henchmen")
	_mercenaries_panel.visible = (category == "mercenaries")


func _load_entity_list(category: String) -> void:
	_entity_list.clear()

	match category:
		"characters":
			_party_ids.clear()
			var members := CampaignRepository.list_party_characters(GameState.party_id)
			for row in members:
				var character := CharacterData.from_dict(row)
				_party_ids.append(character.id)
				_entity_list.add_item(_character_item_label(character))

		"animals":
			_creature_ids.clear()
			var creatures := CampaignRepository.get_trained_creatures_for_party(GameState.party_id)
			for row in creatures:
				var creature := TrainedCreatureData.from_db(row)
				creature.monster_data = _monster_registry.get_monster(creature.species_id)
				_creature_ids.append(creature.id)
				var species_name: String = creature.monster_data.get("name", creature.species_id)
				var display_name := creature.name if not creature.name.is_empty() else species_name
				_entity_list.add_item(display_name)

		"vehicles":
			_vehicle_ids.clear()
			var vehicles := CampaignRepository.get_draft_vehicles_for_party(GameState.party_id)
			for v in vehicles:
				_vehicle_ids.append(str(v.get("id", "")))
				var vname: String = str(v.get("name", ""))
				if vname.is_empty():
					vname = str(v.get("item_key", "vehicle"))
				_entity_list.add_item(vname)

		"henchmen":
			_henchman_ids.clear()
			# Aggregate henchmen from all PCs.
			var seen := {}
			var members2 := CampaignRepository.list_party_characters(GameState.party_id)
			for row in members2:
				var pc_id: String = str(row.get("id", ""))
				var henchmen := CampaignRepository.get_henchmen_for_employer(pc_id)
				for h in henchmen:
					var hid: String = str(h.get("id", ""))
					if hid not in seen:
						seen[hid] = true
						_henchman_ids.append(hid)
						var hname: String = str(h.get("name", "(unnamed)"))
						_entity_list.add_item(hname)
			if _henchman_ids.is_empty():
				_entity_list.add_item("(none)")

		"mercenaries":
			_entity_list.add_item("(none)")


func _auto_select_first_entity() -> void:
	match _active_category:
		"characters":
			if not _party_ids.is_empty():
				_entity_list.select(0)
				_select_character(_party_ids[0])
			else:
				_title_label.text = "No Characters"
		"animals":
			if not _creature_ids.is_empty():
				_entity_list.select(0)
				_select_creature(_creature_ids[0])
			else:
				_title_label.text = "No Animals"
				_tab_creature_stats.display(null, _make_registries_dict())
				_tab_creature_inventory.display(null, _make_registries_dict())
		"vehicles":
			if not _vehicle_ids.is_empty():
				_entity_list.select(0)
				_select_vehicle(_vehicle_ids[0])
			else:
				_title_label.text = "No Vehicles"
				_vehicle_panel.display({}, _make_registries_dict())
		"henchmen":
			_title_label.text = "Henchmen"
		"mercenaries":
			_title_label.text = "Mercenaries"


func _on_entity_selected(index: int) -> void:
	if index < 0:
		return
	match _active_category:
		"characters":
			if index < _party_ids.size():
				_select_character(_party_ids[index])
		"animals":
			if index < _creature_ids.size():
				_select_creature(_creature_ids[index])
		"vehicles":
			if index < _vehicle_ids.size():
				_select_vehicle(_vehicle_ids[index])


# ---------------------------------------------------------------------------
# Character data loading (existing)
# ---------------------------------------------------------------------------

func _select_character(character_id: String) -> void:
	_abort_pending_advancement_if_needed()
	_displayed_character_id = character_id
	_bundle = _load_character(character_id)
	if _bundle.character != null:
		_title_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	else:
		_title_label.text = "Character Sheet"
	_refresh_all_character_tabs()
	var idx := _party_ids.find(character_id)
	if idx >= 0:
		_entity_list.select(idx)


func _load_character(character_id: String) -> CharacterBundle:
	var bundle := CharacterBundle.new()
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		push_error("CharacterSheetOverlay: character not found — id=%s" % character_id)
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


func _refresh_all_character_tabs() -> void:
	if _bundle == null:
		return
	var reg := _make_registries_dict()
	_tab_biography.display(_bundle, reg)
	_tab_attributes.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)
	_tab_equipment.display(_bundle, reg)
	_tab_retainers.display(_bundle, reg)
	_tab_proficiencies.display(_bundle, reg)
	_tab_spells.display(_bundle, reg)
	_tab_advancement.display(_bundle, reg)
	_tab_effects.display(_bundle, reg)


# ---------------------------------------------------------------------------
# Creature data loading
# ---------------------------------------------------------------------------

func _select_creature(creature_id: String) -> void:
	_displayed_entity_id = creature_id
	var creature := _load_creature(creature_id)
	if creature != null:
		var display_name: String = creature.name if not creature.name.is_empty() else str(creature.monster_data.get("name", "Unknown"))
		_title_label.text = display_name
	else:
		_title_label.text = "Unknown Creature"
	var reg := _make_registries_dict()
	# Load party characters for handler tier display.
	var party_chars: Array = []
	for row in CampaignRepository.list_party_characters(GameState.party_id):
		var cd := CharacterData.from_dict(row)
		cd.proficiencies = CampaignRepository.get_character_proficiencies(cd.id)
		party_chars.append(cd)
	reg["party_characters"] = party_chars
	_tab_creature_stats.display(creature, reg)
	_tab_creature_inventory.display(creature, reg)
	var idx := _creature_ids.find(creature_id)
	if idx >= 0:
		_entity_list.select(idx)


func _load_creature(creature_id: String) -> TrainedCreatureData:
	var row := CampaignRepository.get_trained_creature(creature_id)
	if row.is_empty():
		return null
	var creature := TrainedCreatureData.from_db(row)
	creature.monster_data = _monster_registry.get_monster(creature.species_id)
	creature.inventory = []
	for inv_row in CampaignRepository.get_creature_inventory(creature_id):
		creature.inventory.append(InventoryItem.from_dict(inv_row))
	return creature


# ---------------------------------------------------------------------------
# Vehicle data loading
# ---------------------------------------------------------------------------

func _select_vehicle(vehicle_id: String) -> void:
	_displayed_entity_id = vehicle_id
	var bundle := _load_vehicle_bundle(vehicle_id)
	var vehicle: Dictionary = bundle.get("vehicle", {})
	var vname: String = str(vehicle.get("name", ""))
	_title_label.text = vname if not vname.is_empty() else "Vehicle"
	_vehicle_panel.display(bundle, _make_registries_dict())
	var idx := _vehicle_ids.find(vehicle_id)
	if idx >= 0:
		_entity_list.select(idx)


func _load_vehicle_bundle(vehicle_id: String) -> Dictionary:
	var vehicle := CampaignRepository.get_draft_vehicle(vehicle_id)
	if vehicle.is_empty():
		return {"vehicle": {}, "items": [], "hitched_creatures": [], "all_creatures": [], "all_vehicles": []}
	var items := CampaignRepository.get_items_in_vehicle(vehicle_id)

	var hitched_json: String = str(vehicle.get("hitched_creatures", "[]"))
	var hitched_ids = JSON.parse_string(hitched_json)
	var hitched_creatures: Array = []
	if hitched_ids is Array:
		for cid in hitched_ids:
			var c := _load_creature(str(cid))
			if c != null:
				hitched_creatures.append(c)

	# All party creatures for the eligible dropdown.
	var all_creatures: Array = []
	for row in CampaignRepository.get_trained_creatures_for_party(GameState.party_id):
		var c := TrainedCreatureData.from_db(row)
		c.monster_data = _monster_registry.get_monster(c.species_id)
		var inv_rows := CampaignRepository.get_creature_inventory(c.id)
		c.inventory = []
		for inv_row in inv_rows:
			c.inventory.append(InventoryItem.from_dict(inv_row))
		all_creatures.append(c)

	var all_vehicles := CampaignRepository.get_draft_vehicles_for_party(GameState.party_id)

	return {
		"vehicle": vehicle,
		"items": items,
		"hitched_creatures": hitched_creatures,
		"all_creatures": all_creatures,
		"all_vehicles": all_vehicles,
	}


# ---------------------------------------------------------------------------
# Character EventBus handlers
# ---------------------------------------------------------------------------

func _on_hp_changed(character_id: String, _old: int, _new: int) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		return
	_bundle.character = CharacterData.from_dict(row)
	_bundle.character.proficiencies = _bundle.proficiencies
	var reg := _make_registries_dict()
	_tab_biography.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)
	_title_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	_refresh_entity_list_item(character_id)


func _on_inventory_updated(character_id: String) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	_bundle.inventory = CampaignRepository.get_inventory_items(character_id)
	var reg := _make_registries_dict()
	_tab_equipment.display(_bundle, reg)
	_tab_retainers.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_condition_changed(character_id: String, _change: Dictionary) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	_bundle.conditions = CampaignRepository.get_conditions(character_id)
	_tab_effects.display(_bundle, _make_registries_dict())


func _on_xp_awarded(character_id: String, _amount: int) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		return
	_bundle.character = CharacterData.from_dict(row)
	_bundle.character.proficiencies = _bundle.proficiencies
	_tab_advancement.display(_bundle, _make_registries_dict())


func _on_character_leveled_up(character_id: String, _new_level: int) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	_bundle = _load_character(character_id)
	_title_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	_refresh_all_character_tabs()
	_refresh_entity_list_item(character_id)


func _on_proficiency_changed(character_id: String, _change: Dictionary) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	_bundle.proficiencies = CampaignRepository.get_character_proficiencies(character_id)
	_bundle.character.proficiencies = _bundle.proficiencies
	_tab_proficiencies.display(_bundle, _make_registries_dict())


func _on_active_effect_expired(character_id: String, _effect_id: String) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	_bundle.active_effects = CampaignRepository.get_active_effects_on_target(character_id, GameState.campaign_id)
	var reg := _make_registries_dict()
	_tab_effects.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_spell_effect_applied(_effect_id: String, _spell_key: String, target_ids: Array) -> void:
	if _active_category != "characters" or not visible or _displayed_character_id not in target_ids:
		return
	_bundle.active_effects = CampaignRepository.get_active_effects_on_target(_displayed_character_id, GameState.campaign_id)
	var reg := _make_registries_dict()
	_tab_effects.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_spell_effect_removed(_effect_id: String, _spell_key: String) -> void:
	if _active_category != "characters" or not visible or _displayed_character_id.is_empty():
		return
	_bundle.active_effects = CampaignRepository.get_active_effects_on_target(_displayed_character_id, GameState.campaign_id)
	var reg := _make_registries_dict()
	_tab_effects.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_override_applied(_type: String, target_id: String, _field: String) -> void:
	if _active_category != "characters" or target_id != _displayed_character_id or not visible:
		return
	_bundle = _load_character(target_id)
	_title_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	_refresh_all_character_tabs()
	_refresh_entity_list_item(target_id)


func _on_loyalty_changed(_henchman_id: String, _old: int, _new: int) -> void:
	if _active_category != "characters" or not visible or _displayed_character_id.is_empty():
		return
	_bundle.henchmen = CampaignRepository.get_henchmen_for_employer(_displayed_character_id)
	_tab_retainers.display(_bundle, _make_registries_dict())


func _on_age_category_changed(character_id: String, _old_cat: String, _new_cat: String) -> void:
	if _active_category != "characters" or character_id != _displayed_character_id or not visible:
		return
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		return
	_bundle.character = CharacterData.from_dict(row)
	_bundle.character.proficiencies = _bundle.proficiencies
	var reg := _make_registries_dict()
	_tab_biography.display(_bundle, reg)
	_tab_advancement.display(_bundle, reg)


# ---------------------------------------------------------------------------
# Creature EventBus handlers
# ---------------------------------------------------------------------------

func _on_creature_hp_changed(creature_id: String, _old: int, _new: int) -> void:
	if _active_category != "animals" or creature_id != _displayed_entity_id or not visible:
		return
	_select_creature(creature_id)


func _on_creature_inventory_updated(creature_id: String) -> void:
	if not visible:
		return
	if _active_category == "animals" and creature_id == _displayed_entity_id:
		_select_creature(creature_id)
	# Vehicle panel may also need refresh if a creature's saddle changed.
	if _active_category == "vehicles" and not _displayed_entity_id.is_empty():
		_select_vehicle(_displayed_entity_id)


func _on_creature_list_changed(_party_id: String, _creature_id: String) -> void:
	if _active_category != "animals" or not visible:
		return
	_load_entity_list("animals")
	_auto_select_first_entity()


func _on_creature_died(creature_id: String) -> void:
	_on_creature_list_changed("", creature_id)


# ---------------------------------------------------------------------------
# Vehicle EventBus handlers
# ---------------------------------------------------------------------------

func _on_vehicle_list_changed(_party_id: String, _vehicle_id: String) -> void:
	if _active_category != "vehicles" or not visible:
		return
	_load_entity_list("vehicles")
	_auto_select_first_entity()


func _on_vehicle_hitch_changed(vehicle_id: String) -> void:
	if _active_category != "vehicles" or vehicle_id != _displayed_entity_id or not visible:
		return
	_select_vehicle(vehicle_id)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _close() -> void:
	_abort_pending_advancement_if_needed()
	visible = false


func _on_tab_changed(index: int) -> void:
	if index != _get_advancement_tab_index():
		_abort_pending_advancement_if_needed()


func _make_registries_dict() -> Dictionary:
	return {
		"class_registry":       _class_registry,
		"proficiency_registry": _proficiency_registry,
		"spell_registry":       _spell_registry,
		"power_registry":       _power_registry,
		"spec_registry":        _spec_registry,
		"monster_registry":     _monster_registry,
		"equipment_catalog":    _equipment_catalog,
	}


func _character_item_label(character: CharacterData) -> String:
	var n := character.name if not character.name.is_empty() else "(unnamed)"
	var class_display_name := character.character_class.capitalize()
	if _class_registry != null and _class_registry.has_class(character.character_class):
		class_display_name = _class_registry.get_class_display_name(character.character_class, character.sex)
	return "%s\n%s %d\nHP %d/%d" % [n, class_display_name, character.level, character.hp_current, character.hp_max]


func _refresh_entity_list_item(character_id: String) -> void:
	if _active_category != "characters":
		return
	var idx := _party_ids.find(character_id)
	if idx < 0 or _bundle == null or _bundle.character == null:
		return
	_entity_list.set_item_text(idx, _character_item_label(_bundle.character))


func _get_advancement_tab_index() -> int:
	if _tab_container == null:
		return -1
	for i in range(_tab_container.get_tab_count()):
		if _tab_container.get_tab_title(i) == "Advancement":
			return i
	return -1


func _abort_pending_advancement_if_needed() -> void:
	if _tab_advancement == null:
		return
	if _tab_advancement.has_pending_level_up():
		_tab_advancement.abort_pending_level_up()
