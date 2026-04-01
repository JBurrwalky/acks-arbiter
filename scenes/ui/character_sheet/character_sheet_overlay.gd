extends CanvasLayer

## Character Sheet Overlay (O-02)
##
## Persistent in-game character sheet accessible at any point in the game loop.
## Toggle with F7 (character_sheet_toggle input action). Right-anchored panel,
## non-modal — the game world remains visible and interactive behind it.
##
## Data is loaded from the database via CampaignRepository and auto-refreshes
## when relevant EventBus signals fire.

# ---------------------------------------------------------------------------
# Registries
# ---------------------------------------------------------------------------

var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry
var _spell_registry: SpellRegistry
var _power_registry: PowerRegistry
var _spec_registry: SpecializationRegistry

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _bundle: CharacterBundle = null
var _displayed_character_id: String = ""
var _party_ids: Array = []          ## character IDs in party list order

# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _panel: PanelContainer
var _char_name_label: Label
var _party_list: ItemList
var _tab_container: TabContainer

# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

var _tab_biography: CSTabBiography
var _tab_attributes: CSTabAttributes
var _tab_combat: CSTabCombat
var _tab_equipment: CSTabEquipment
var _tab_proficiencies: CSTabProficiencies
var _tab_spells: CSTabSpells
var _tab_advancement: CSTabAdvancement
var _tab_effects: CSTabEffects


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


func _build_ui() -> void:
	## Build the full panel hierarchy programmatically.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.34   ## right 66% of the viewport
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(root_vbox)

	# -- Title bar --
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(title_row)

	_char_name_label = Label.new()
	_char_name_label.text = "Character Sheet"
	_char_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_name_label.add_theme_font_size_override("font_size", 14)
	title_row.add_child(_char_name_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.flat = true
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)

	root_vbox.add_child(HSeparator.new())

	# -- Body: party selector sidebar + tab area --
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root_vbox.add_child(body)

	# Party selector sidebar
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(120, 0)
	sidebar.add_theme_constant_override("separation", 2)
	body.add_child(sidebar)

	var party_header := Label.new()
	party_header.text = "Party"
	party_header.add_theme_font_size_override("font_size", 11)
	sidebar.add_child(party_header)

	_party_list = ItemList.new()
	_party_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_party_list.item_selected.connect(_on_party_item_selected)
	sidebar.add_child(_party_list)

	body.add_child(VSeparator.new())

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_tab_container)

	_build_tabs()


func _build_tabs() -> void:
	## Instantiate all tab classes, wrap each in a ScrollContainer.
	_tab_biography = CSTabBiography.new()
	_tab_attributes = CSTabAttributes.new()
	_tab_combat = CSTabCombat.new()
	_tab_equipment = CSTabEquipment.new()
	_tab_proficiencies = CSTabProficiencies.new()
	_tab_spells = CSTabSpells.new()
	_tab_advancement = CSTabAdvancement.new()
	_tab_effects = CSTabEffects.new()

	var defs: Array = [
		["Biography",     _tab_biography],
		["Attributes",    _tab_attributes],
		["Combat",        _tab_combat],
		["Equipment",     _tab_equipment],
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


func _connect_signals() -> void:
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


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(character_id: String = "") -> void:
	## Show the overlay, reload the party list, and display the given character.
	## If character_id is empty, defaults to the first party member.
	visible = true
	_load_party_list()
	if character_id.is_empty() and not _party_ids.is_empty():
		character_id = _party_ids[0]
	if not character_id.is_empty():
		_select_character(character_id)


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
# Data loading
# ---------------------------------------------------------------------------

func _load_party_list() -> void:
	## Populate the sidebar ItemList with current party members.
	_party_list.clear()
	_party_ids.clear()
	var members := CampaignRepository.list_party_characters(GameState.party_id)
	for row in members:
		var character := CharacterData.from_dict(row)
		_party_ids.append(character.id)
		_party_list.add_item(_party_item_label(character))


func _party_item_label(character: CharacterData) -> String:
	var n := character.name if not character.name.is_empty() else "(unnamed)"
	return "%s\n%s %d\nHP %d/%d" % [n, character.character_class.capitalize(), character.level, character.hp_current, character.hp_max]


func _select_character(character_id: String) -> void:
	## Load and display the given character; sync sidebar highlight.
	_displayed_character_id = character_id
	_bundle = _load_character(character_id)
	if _bundle.character != null:
		_char_name_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	else:
		_char_name_label.text = "Character Sheet"
	_refresh_all_tabs()
	var idx := _party_ids.find(character_id)
	if idx >= 0:
		_party_list.select(idx)


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
	bundle.powers = CampaignRepository.get_character_powers(character_id)
	bundle.conditions = CampaignRepository.get_conditions(character_id)
	bundle.active_effects = CampaignRepository.get_active_effects_on_target(character_id, GameState.campaign_id)
	## Populate character.proficiencies so has_proficiency() etc. work.
	bundle.character.proficiencies = bundle.proficiencies
	return bundle


func _refresh_all_tabs() -> void:
	if _bundle == null:
		return
	var reg := _make_registries_dict()
	_tab_biography.display(_bundle, reg)
	_tab_attributes.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)
	_tab_equipment.display(_bundle, reg)
	_tab_proficiencies.display(_bundle, reg)
	_tab_spells.display(_bundle, reg)
	_tab_advancement.display(_bundle, reg)
	_tab_effects.display(_bundle, reg)


# ---------------------------------------------------------------------------
# EventBus handlers
# ---------------------------------------------------------------------------

func _on_hp_changed(character_id: String, _old: int, _new: int) -> void:
	if character_id != _displayed_character_id or not visible:
		return
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		return
	_bundle.character = CharacterData.from_dict(row)
	_bundle.character.proficiencies = _bundle.proficiencies
	var reg := _make_registries_dict()
	_tab_biography.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)
	_char_name_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	_refresh_party_list_item(character_id)


func _on_inventory_updated(character_id: String) -> void:
	if character_id != _displayed_character_id or not visible:
		return
	_bundle.inventory = CampaignRepository.get_inventory_items(character_id)
	var reg := _make_registries_dict()
	_tab_equipment.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_condition_changed(character_id: String, _change: Dictionary) -> void:
	if character_id != _displayed_character_id or not visible:
		return
	_bundle.conditions = CampaignRepository.get_conditions(character_id)
	_tab_effects.display(_bundle, _make_registries_dict())


func _on_xp_awarded(character_id: String, _amount: int) -> void:
	if character_id != _displayed_character_id or not visible:
		return
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		return
	_bundle.character = CharacterData.from_dict(row)
	_bundle.character.proficiencies = _bundle.proficiencies
	_tab_advancement.display(_bundle, _make_registries_dict())


func _on_character_leveled_up(character_id: String, _new_level: int) -> void:
	if character_id != _displayed_character_id or not visible:
		return
	_bundle = _load_character(character_id)
	_char_name_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	_refresh_all_tabs()
	_refresh_party_list_item(character_id)


func _on_proficiency_changed(character_id: String, _change: Dictionary) -> void:
	if character_id != _displayed_character_id or not visible:
		return
	_bundle.proficiencies = CampaignRepository.get_character_proficiencies(character_id)
	_bundle.character.proficiencies = _bundle.proficiencies
	_tab_proficiencies.display(_bundle, _make_registries_dict())


func _on_active_effect_expired(character_id: String, _effect_id: String) -> void:
	if character_id != _displayed_character_id or not visible:
		return
	_bundle.active_effects = CampaignRepository.get_active_effects_on_target(character_id, GameState.campaign_id)
	var reg := _make_registries_dict()
	_tab_effects.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_spell_effect_applied(_effect_id: String, _spell_key: String, target_ids: Array) -> void:
	if not visible or _displayed_character_id not in target_ids:
		return
	_bundle.active_effects = CampaignRepository.get_active_effects_on_target(_displayed_character_id, GameState.campaign_id)
	var reg := _make_registries_dict()
	_tab_effects.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_spell_effect_removed(_effect_id: String, _spell_key: String) -> void:
	## No character_id in this signal — reload for the displayed character unconditionally.
	if not visible or _displayed_character_id.is_empty():
		return
	_bundle.active_effects = CampaignRepository.get_active_effects_on_target(_displayed_character_id, GameState.campaign_id)
	var reg := _make_registries_dict()
	_tab_effects.display(_bundle, reg)
	_tab_combat.display(_bundle, reg)


func _on_override_applied(_type: String, target_id: String, _field: String) -> void:
	if target_id != _displayed_character_id or not visible:
		return
	_bundle = _load_character(target_id)
	_char_name_label.text = _bundle.character.name if not _bundle.character.name.is_empty() else "(unnamed)"
	_refresh_all_tabs()
	_refresh_party_list_item(target_id)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _close() -> void:
	visible = false


func _on_party_item_selected(index: int) -> void:
	if index < 0 or index >= _party_ids.size():
		return
	_select_character(_party_ids[index])


func _make_registries_dict() -> Dictionary:
	return {
		"class_registry":       _class_registry,
		"proficiency_registry": _proficiency_registry,
		"spell_registry":       _spell_registry,
		"power_registry":       _power_registry,
		"spec_registry":        _spec_registry,
	}


func _refresh_party_list_item(character_id: String) -> void:
	var idx := _party_ids.find(character_id)
	if idx < 0 or _bundle == null or _bundle.character == null:
		return
	_party_list.set_item_text(idx, _party_item_label(_bundle.character))
