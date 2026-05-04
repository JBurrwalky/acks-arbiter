extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Party tab — γ.3 migration target. Hosts:
##   - Party Status header (composition counts, encumbrance, gold, location,
##     speed) — always visible above the sub-tab strip per gdd-party-tab.md §4.
##   - Composition sub-tab — roster + add / split / merge / transfer flows
##     ported from PartyManagementOverlay's Members tab.
##   - Travel sub-tab — daily / total / days remaining headline format with
##     math-breakdown tooltips per §6.3.
##   - Formation sub-tab — Wilderness 6×12 + Dungeon 2×12 grids with
##     entity-eligibility filtering per §7.
##
## Per-tab substate (NotebookState.per_tab_substate["party"]):
##   {
##     "active_subtab": "composition" | "travel" | "formation",
##     "formation_active_grid": "wilderness" | "dungeon",
##   }


const PartySplitDialogScript := preload("res://scenes/ui/notebook/party/party_split_dialog.gd")
const FormationGridCellScript := preload("res://scenes/ui/notebook/party/formation_grid_cell.gd")
const FormationUnplacedListScript := preload("res://scenes/ui/notebook/party/formation_unplaced_list.gd")

const SUBSTATE_TAB_ID := "party"

const SUBTAB_COMPOSITION := "composition"
const SUBTAB_TRAVEL := "travel"
const SUBTAB_FORMATION := "formation"

const SUBTAB_LABELS := {
	SUBTAB_COMPOSITION: "Composition",
	SUBTAB_TRAVEL:      "Travel",
	SUBTAB_FORMATION:   "Formation",
}

const SUBTAB_ORDER := [SUBTAB_COMPOSITION, SUBTAB_TRAVEL, SUBTAB_FORMATION]

# Travel-tab consumption constants per gdd-party-tab.md §6.3.1.
const FOOD_PER_HUMANOID_PER_DAY := 1.0 / 6.0
const WATER_PER_HUMANOID_PER_DAY := 5.0 / 6.0
const ANIMAL_FALLBACK_NORMAL_LOAD := 40  # heavy horse / mule reference value


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _party: PartyData = null
var _colocated_parties: Array = []
var _split_dialog: CanvasLayer = null
var _modal_layer: CanvasLayer = null

var _active_subtab: String = SUBTAB_COMPOSITION
var _formation_active_grid: String = PartyData.GRID_WILDERNESS

# Composition grid placement state.
var _selected_unplaced_id: String = ""
var _wilderness_grid_cells: Array = []   # [row][col] -> Button
var _dungeon_grid_cells: Array = []      # [row][col] -> Button


# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

# Header
var _header_name_label: Label = null
var _header_composition_label: Label = null
var _header_encumbrance_label: Label = null
var _header_gold_label: Label = null
var _header_location_label: Label = null
var _header_speed_label: Label = null
var _open_inventory_btn: Button = null
var _camp_btn: Button = null

# Sub-tab strip
var _subtab_buttons: Dictionary = {}  # id -> Button
var _content_holder: VBoxContainer = null
var _subtab_pages: Dictionary = {}  # id -> Control (lazy)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _build_content() -> void:
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 100
	add_child(_modal_layer)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	_build_header(root_vbox)
	_build_subtab_strip(root_vbox)

	_content_holder = VBoxContainer.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_content_holder)

	_connect_signals()
	_restore_substate()
	if GameState.is_in_session():
		_load_party()


func _connect_signals() -> void:
	EventBus.party_member_joined.connect(_on_party_changed)
	EventBus.party_member_left.connect(_on_party_changed)
	EventBus.formation_changed.connect(_on_party_event_refresh)
	EventBus.inventory_updated.connect(_on_inventory_change)
	EventBus.party_split.connect(_on_party_lifecycle_changed)
	EventBus.party_merged.connect(_on_party_lifecycle_changed)
	EventBus.active_party_changed.connect(_on_active_party_event)
	EventBus.wallet_changed.connect(_on_wallet_changed)


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _build_header(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# Action row (party name + Open Inventory + Camp).
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	vbox.add_child(action_row)

	_header_name_label = Label.new()
	_header_name_label.add_theme_font_size_override("font_size", 14)
	_header_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_header_name_label)

	_open_inventory_btn = Button.new()
	_open_inventory_btn.text = "Open Inventory"
	_open_inventory_btn.add_theme_font_size_override("font_size", 11)
	_open_inventory_btn.pressed.connect(_on_open_inventory_pressed)
	action_row.add_child(_open_inventory_btn)

	_camp_btn = Button.new()
	_camp_btn.text = "Camp"
	_camp_btn.add_theme_font_size_override("font_size", 11)
	_camp_btn.pressed.connect(_on_camp_pressed)
	action_row.add_child(_camp_btn)

	# Composition counts.
	_header_composition_label = Label.new()
	_header_composition_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_header_composition_label)

	# Encumbrance + gold (one row, two halves).
	var enc_row := HBoxContainer.new()
	enc_row.add_theme_constant_override("separation", 12)
	vbox.add_child(enc_row)

	_header_encumbrance_label = Label.new()
	_header_encumbrance_label.add_theme_font_size_override("font_size", 11)
	_header_encumbrance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enc_row.add_child(_header_encumbrance_label)

	_header_gold_label = Label.new()
	_header_gold_label.add_theme_font_size_override("font_size", 11)
	enc_row.add_child(_header_gold_label)

	# Location + speed.
	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", 12)
	vbox.add_child(loc_row)

	_header_location_label = Label.new()
	_header_location_label.add_theme_font_size_override("font_size", 11)
	_header_location_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_row.add_child(_header_location_label)

	_header_speed_label = Label.new()
	_header_speed_label.add_theme_font_size_override("font_size", 11)
	loc_row.add_child(_header_speed_label)


func _refresh_header() -> void:
	if _party == null:
		_header_name_label.text = "No Party"
		_header_composition_label.text = ""
		_header_encumbrance_label.text = ""
		_header_gold_label.text = ""
		_header_location_label.text = ""
		_header_speed_label.text = ""
		return
	_header_name_label.text = _party.name

	# Composition counts — collapse zero categories per §4.3.
	var pc_count := 0
	var hench_count := 0
	for cd: CharacterData in _party.character_data:
		if cd.character_type == "henchman":
			hench_count += 1
		else:
			pc_count += 1
	var animal_count: int = _party.creature_data.size()
	var vehicle_count: int = _party.vehicle_data.size()
	# Mercenary units land in Phase H+; show 0 for now.
	var merc_count := 0
	var parts: Array = []
	if pc_count > 0:
		parts.append("%d PC%s" % [pc_count, "" if pc_count == 1 else "s"])
	if hench_count > 0:
		parts.append("%d Henchm%s" % [hench_count, "an" if hench_count == 1 else "en"])
	if animal_count > 0:
		parts.append("%d Animal%s" % [animal_count, "" if animal_count == 1 else "s"])
	if vehicle_count > 0:
		parts.append("%d Vehicle%s" % [vehicle_count, "" if vehicle_count == 1 else "s"])
	if merc_count > 0:
		parts.append("%d Mercenary Unit%s" % [merc_count, "" if merc_count == 1 else "s"])
	_header_composition_label.text = " · ".join(parts) if not parts.is_empty() else "No members"

	# Encumbrance band — slowest member's effective movement maps to a band.
	# v1 simplification: report slowest movement and the slowest member's name.
	var slowest_speed: int = _party.get_slowest_movement()
	var slowest_name: String = _slowest_member_name()
	if slowest_name.is_empty():
		_header_encumbrance_label.text = "Encumbrance: —"
	else:
		_header_encumbrance_label.text = "Slowest: %s @ %d'/turn" % [slowest_name, slowest_speed]

	# Total gold — sum of party characters' wealth.
	var total_cp := 0
	for cd: CharacterData in _party.character_data:
		if cd.character_type != "pc":
			continue
		total_cp += CampaignRepository.get_character_wealth_cp(cd.id)
	_header_gold_label.text = "Total gold: %.2f gp" % (total_cp / 100.0)

	# Location.
	var loc_text: String = ""
	match _party.current_location_type:
		"settlement":
			loc_text = "Settlement"
		"dungeon":
			loc_text = "Dungeon"
		"sea":
			loc_text = "Sea (%d, %d)" % [_party.current_hex_q, _party.current_hex_r]
		_:
			loc_text = "Hex %d, %d" % [_party.current_hex_q, _party.current_hex_r]
	_header_location_label.text = loc_text

	# Speed.
	_header_speed_label.text = "%d'/turn" % slowest_speed


func _slowest_member_name() -> String:
	if _party == null:
		return ""
	var slowest_speed := 999
	var slowest: String = ""
	for cd: CharacterData in _party.character_data:
		var spd: int = cd.get_effective_movement()
		if spd < slowest_speed:
			slowest_speed = spd
			slowest = cd.name
	for creature: TrainedCreatureData in _party.creature_data:
		var spd: int = creature.get_effective_movement()
		if spd < slowest_speed:
			slowest_speed = spd
			slowest = creature.name if not creature.name.is_empty() else creature.species_id.capitalize()
	if not _party.vehicle_data.is_empty() and PartyData.VEHICLE_SPEED < slowest_speed:
		slowest_speed = PartyData.VEHICLE_SPEED
		slowest = "Vehicle"
	return slowest


# ---------------------------------------------------------------------------
# Sub-tab strip
# ---------------------------------------------------------------------------

func _build_subtab_strip(parent: VBoxContainer) -> void:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	parent.add_child(strip)
	for sid in SUBTAB_ORDER:
		var btn := Button.new()
		btn.text = SUBTAB_LABELS[sid]
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_subtab_pressed.bind(sid))
		strip.add_child(btn)
		_subtab_buttons[sid] = btn


func _activate_subtab(sid: String) -> void:
	if not SUBTAB_LABELS.has(sid):
		return
	_active_subtab = sid
	for id in _subtab_buttons.keys():
		(_subtab_buttons[id] as Button).button_pressed = (id == sid)
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
	var page: Control = _ensure_subtab_page(sid)
	_content_holder.add_child(page)
	if sid == SUBTAB_FORMATION:
		_refresh_formation_grids()
	elif sid == SUBTAB_TRAVEL:
		_refresh_travel_subtab()
	else:
		_refresh_composition_subtab()


func _ensure_subtab_page(sid: String) -> Control:
	if _subtab_pages.has(sid):
		return _subtab_pages[sid]
	var page: Control = null
	match sid:
		SUBTAB_COMPOSITION:
			page = _build_composition_page()
		SUBTAB_TRAVEL:
			page = _build_travel_page()
		SUBTAB_FORMATION:
			page = _build_formation_page()
	if page == null:
		page = Control.new()
	_subtab_pages[sid] = page
	return page


func _on_subtab_pressed(sid: String) -> void:
	if sid == _active_subtab:
		# Force the highlight back on; toggle-off on re-click is suppressed.
		(_subtab_buttons[sid] as Button).button_pressed = true
		return
	_activate_subtab(sid)
	_persist_substate()


# ---------------------------------------------------------------------------
# Composition sub-tab
# ---------------------------------------------------------------------------

var _composition_members_vbox: VBoxContainer = null
var _composition_active_party_dropdown: OptionButton = null
var _composition_split_btn: Button = null
var _composition_merge_dropdown: OptionButton = null

func _build_composition_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# Active party dropdown.
	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 4)
	vbox.add_child(party_row)
	var party_lbl := Label.new()
	party_lbl.text = "Active Party:"
	party_lbl.add_theme_font_size_override("font_size", 11)
	party_row.add_child(party_lbl)
	_composition_active_party_dropdown = OptionButton.new()
	_composition_active_party_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composition_active_party_dropdown.item_selected.connect(_on_active_party_selected)
	party_row.add_child(_composition_active_party_dropdown)

	# Split / merge actions.
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	vbox.add_child(actions_row)
	_composition_split_btn = Button.new()
	_composition_split_btn.text = "Split Party"
	_composition_split_btn.pressed.connect(_on_split_pressed)
	actions_row.add_child(_composition_split_btn)
	_composition_merge_dropdown = OptionButton.new()
	_composition_merge_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composition_merge_dropdown.item_selected.connect(_on_merge_selected)
	actions_row.add_child(_composition_merge_dropdown)

	vbox.add_child(HSeparator.new())

	_composition_members_vbox = VBoxContainer.new()
	_composition_members_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_composition_members_vbox)

	return scroll


func _refresh_composition_subtab() -> void:
	if _composition_members_vbox == null:
		return
	_refresh_composition_party_dropdown()
	_refresh_composition_merge_dropdown()
	_refresh_composition_members()


func _refresh_composition_party_dropdown() -> void:
	_composition_active_party_dropdown.clear()
	if not GameState.is_in_session():
		return
	var all_parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	var active_id := _resolve_party_id()
	var select_idx := 0
	for i in range(all_parties.size()):
		var p: Dictionary = all_parties[i]
		_composition_active_party_dropdown.add_item(p.name, i)
		_composition_active_party_dropdown.set_item_metadata(i, p.id)
		if p.id == active_id:
			select_idx = i
	if _composition_active_party_dropdown.item_count > 0:
		_composition_active_party_dropdown.select(select_idx)


func _refresh_composition_merge_dropdown() -> void:
	_composition_merge_dropdown.clear()
	_composition_merge_dropdown.add_item("Merge With...", 0)
	_composition_merge_dropdown.set_item_disabled(0, true)
	if _party == null or not GameState.is_in_session():
		_composition_merge_dropdown.disabled = true
		_composition_merge_dropdown.tooltip_text = "No parties at this hex."
		return
	var all_parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	var count := 0
	for p in all_parties:
		if p.id == _party.id:
			continue
		if p.current_map_id == _party.current_map_id \
				and p.current_hex_q == _party.current_hex_q \
				and p.current_hex_r == _party.current_hex_r:
			var idx: int = _composition_merge_dropdown.item_count
			_composition_merge_dropdown.add_item(p.name, idx)
			_composition_merge_dropdown.set_item_metadata(idx, p.id)
			count += 1
	if count == 0:
		_composition_merge_dropdown.disabled = true
		_composition_merge_dropdown.tooltip_text = "No parties at this hex."
	else:
		_composition_merge_dropdown.disabled = false
		_composition_merge_dropdown.tooltip_text = ""


func _refresh_composition_members() -> void:
	for child in _composition_members_vbox.get_children():
		child.queue_free()
	if _party == null:
		return

	var header := Label.new()
	header.text = "Current Members"
	header.add_theme_font_size_override("font_size", 12)
	_composition_members_vbox.add_child(header)

	var all_parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	_colocated_parties = []
	for p in all_parties:
		if p.id == _party.id:
			continue
		if p.current_map_id == _party.current_map_id \
				and p.current_hex_q == _party.current_hex_q \
				and p.current_hex_r == _party.current_hex_r:
			_colocated_parties.append(p)

	var is_solo: bool = _party.character_data.size() <= 1
	for cd: CharacterData in _party.character_data:
		_composition_members_vbox.add_child(_make_member_row(cd, is_solo))

	_composition_members_vbox.add_child(HSeparator.new())

	var avail_header := Label.new()
	avail_header.text = "Available Characters"
	avail_header.add_theme_font_size_override("font_size", 12)
	_composition_members_vbox.add_child(avail_header)

	var available := CampaignRepository.list_unpartied_characters(GameState.campaign_id)
	if available.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No available characters."
		none_lbl.add_theme_font_size_override("font_size", 10)
		none_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		_composition_members_vbox.add_child(none_lbl)
	else:
		for char_row: Dictionary in available:
			_composition_members_vbox.add_child(_make_available_row(char_row))


func _make_member_row(cd: CharacterData, is_solo: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_btn := LinkButton.new()
	name_btn.text = "%s (L%d %s)" % [cd.name, cd.level, cd.character_class.capitalize()]
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.add_theme_font_size_override("font_size", 11)
	name_btn.pressed.connect(_on_member_name_clicked.bind(cd.id))
	row.add_child(name_btn)

	# Wilderness pos for compactness.
	var pos := _party.get_formation_pos(cd.id)
	var pos_text: String = "Unplaced" if pos.x == PartyData.UNASSIGNED \
			else "R%d C%d" % [pos.y + 1, pos.x + 1]
	var pos_lbl := Label.new()
	pos_lbl.text = pos_text
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	pos_lbl.custom_minimum_size = Vector2(64, 0)
	row.add_child(pos_lbl)

	var transfer_dd := OptionButton.new()
	transfer_dd.custom_minimum_size = Vector2(110, 0)
	transfer_dd.add_item("Transfer to...", 0)
	transfer_dd.set_item_disabled(0, true)
	if _colocated_parties.is_empty() or is_solo:
		transfer_dd.disabled = true
		if is_solo:
			transfer_dd.tooltip_text = "Cannot transfer last member of a party"
		else:
			transfer_dd.tooltip_text = "No other parties at this location"
	else:
		for i in _colocated_parties.size():
			var idx: int = i + 1
			transfer_dd.add_item(_colocated_parties[i].name, idx)
			transfer_dd.set_item_metadata(idx, _colocated_parties[i].id)
		transfer_dd.item_selected.connect(_on_transfer_member.bind(cd.id))
	row.add_child(transfer_dd)

	return row


func _make_available_row(char_row: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_lbl := Label.new()
	var cname: String = char_row.get("name", "Unknown")
	var clevel: int = char_row.get("level", 1)
	var cclass: String = char_row.get("character_class", "fighter")
	name_lbl.text = "%s (L%d %s)" % [cname, clevel, cclass.capitalize()]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(name_lbl)
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.custom_minimum_size = Vector2(60, 0)
	add_btn.pressed.connect(_on_add_member.bind(char_row.get("id", "")))
	row.add_child(add_btn)
	return row


# ---------------------------------------------------------------------------
# Travel sub-tab
# ---------------------------------------------------------------------------

var _travel_info_vbox: VBoxContainer = null
var _rations_label: Label = null
var _water_label: Label = null
var _fodder_label: Label = null

func _build_travel_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_travel_info_vbox = VBoxContainer.new()
	_travel_info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_travel_info_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_travel_info_vbox)
	return scroll


func _refresh_travel_subtab() -> void:
	if _travel_info_vbox == null:
		return
	for child in _travel_info_vbox.get_children():
		child.queue_free()
	if _party == null:
		return

	# Movement speeds section per gdd-party-tab.md §6.2.
	var speeds_header := Label.new()
	speeds_header.text = "Movement Speeds"
	speeds_header.add_theme_font_size_override("font_size", 12)
	_travel_info_vbox.add_child(speeds_header)

	_add_info_row("Base (slowest)", "%d'/turn" % _party.get_slowest_movement())
	for terrain in ["clear", "woods", "hills", "desert", "mountains", "swamp", "jungle"]:
		var spd: Dictionary = TravelSpeedCalculator.calculate_party_speed(_party, terrain)
		_add_info_row(terrain.capitalize(), "%.0f mi/day" % spd["miles_per_day"])

	_travel_info_vbox.add_child(HSeparator.new())

	# Rations / water / fodder section per §6.3.
	var rations_header := Label.new()
	rations_header.text = "Rations, Water, Fodder"
	rations_header.add_theme_font_size_override("font_size", 12)
	_travel_info_vbox.add_child(rations_header)

	var consumption := _compute_daily_consumption()
	var on_hand := _compute_on_hand_totals()

	_rations_label = _add_resource_row("Rations", consumption["food"],
			on_hand["food"], "Food (humanoid PCs + henchmen) — see tooltip for math.",
			_food_tooltip(consumption["food"], on_hand["food"]))
	_water_label = _add_resource_row("Water", consumption["water"],
			on_hand["water"], "Water (humanoids + animals) — see tooltip for math.",
			_water_tooltip(consumption["water"], on_hand["water"]))
	_fodder_label = _add_resource_row("Fodder", consumption["fodder"],
			on_hand["fodder"], "Fodder (animals) — see tooltip for math.",
			_fodder_tooltip(consumption["fodder"], on_hand["fodder"]))

	_travel_info_vbox.add_child(HSeparator.new())

	# Active proficiencies.
	var profs_header := Label.new()
	profs_header.text = "Travel-Relevant Proficiencies"
	profs_header.add_theme_font_size_override("font_size", 12)
	_travel_info_vbox.add_child(profs_header)
	if _party.any_member_has_proficiency("navigation"):
		_add_info_row("Navigation", "+4 to avoid getting lost")
	else:
		_add_info_row("Navigation", "No navigator (base chances)")
	if _party.any_member_has_proficiency("endurance"):
		_add_info_row("Endurance", "No mandatory rest; extended forced march")

	_travel_info_vbox.add_child(HSeparator.new())

	# Quick actions per §6.5.
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 8)
	_travel_info_vbox.add_child(actions_row)
	var forage_btn := Button.new()
	forage_btn.text = "Forage"
	forage_btn.tooltip_text = "Search for food in the current hex per acore_adventures_and_encounters.xml §foraging."
	forage_btn.pressed.connect(_on_forage_pressed)
	actions_row.add_child(forage_btn)
	var hunt_btn := Button.new()
	hunt_btn.text = "Hunt"
	hunt_btn.tooltip_text = "Hunt for food and game in the current hex."
	hunt_btn.pressed.connect(_on_hunt_pressed)
	actions_row.add_child(hunt_btn)


func _add_info_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 10)
	row.add_child(val)
	_travel_info_vbox.add_child(row)


func _add_resource_row(label_text: String, daily: float, total: float,
		tooltip: String, math_tooltip: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.tooltip_text = tooltip
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)
	var val := Label.new()
	var days_remaining := -1
	if daily > 0.001:
		days_remaining = int(floor(total / daily))
	var days_str := "—" if days_remaining < 0 else str(days_remaining)
	val.text = "%.2f / %.2f (%s days)" % [daily, total, days_str]
	val.add_theme_font_size_override("font_size", 11)
	val.tooltip_text = math_tooltip
	row.add_child(val)
	_travel_info_vbox.add_child(row)
	return val


func _compute_daily_consumption() -> Dictionary:
	var humanoid_count: int = 0
	for cd: CharacterData in _party.character_data:
		# PC and humanoid henchman both consume; mercenaries excluded
		# (independent contractors per §6.3.1).
		if cd.character_type == "pc" or cd.character_type == "henchman":
			humanoid_count += 1
	var food := humanoid_count * FOOD_PER_HUMANOID_PER_DAY
	var water_humans := humanoid_count * WATER_PER_HUMANOID_PER_DAY
	var water_animals := 0.0
	var fodder := 0.0
	for creature: TrainedCreatureData in _party.creature_data:
		var load_stone: float = float(_creature_normal_load(creature))
		fodder += load_stone / 10.0
		water_animals += load_stone / 5.0
	return {
		"food":   food,
		"water":  water_humans + water_animals,
		"fodder": fodder,
	}


func _compute_on_hand_totals() -> Dictionary:
	var food := 0.0
	var water := 0.0
	var fodder := 0.0
	for cd: CharacterData in _party.character_data:
		var items: Array = CampaignRepository.get_inventory_items(cd.id)
		var t := _accumulate_resource_items(items)
		food += t["food"]
		water += t["water"]
		fodder += t["fodder"]
	for creature: TrainedCreatureData in _party.creature_data:
		var items: Array = CampaignRepository.get_creature_inventory(creature.id)
		var t := _accumulate_resource_items(items)
		food += t["food"]
		water += t["water"]
		fodder += t["fodder"]
	for v in _party.vehicle_data:
		var items: Array = CampaignRepository.get_items_in_vehicle(str(v.get("id", "")))
		var t := _accumulate_resource_items(items)
		food += t["food"]
		water += t["water"]
		fodder += t["fodder"]
	return {"food": food, "water": water, "fodder": fodder}


func _accumulate_resource_items(items: Array) -> Dictionary:
	## H.3 — prefer the catalog's `consumable_kind` + `consumable_person_days`
	## tags (added per item in base_equipment.json + provisions_services.json).
	## Falls back to the prior prefix-match heuristic for items that don't
	## yet carry the tags so legacy data continues to count correctly.
	var food := 0.0
	var water := 0.0
	var fodder := 0.0
	var catalog: EquipmentCatalog = _ensure_equipment_catalog()
	for item in items:
		var key: String = ""
		var qty: int = 1
		if item is Dictionary:
			key = str(item.get("item_key", ""))
			qty = int(item.get("quantity", 1))
		elif item is InventoryItem:
			key = item.item_key
			qty = item.quantity
		if key.is_empty():
			continue
		var entry: Dictionary = catalog.get_item(key) if catalog != null else {}
		var kind: String = str(entry.get("consumable_kind", ""))
		if not kind.is_empty():
			var per_days: float = float(entry.get("consumable_person_days", 1))
			match kind:
				"food":
					food += qty * per_days * FOOD_PER_HUMANOID_PER_DAY
				"water":
					water += qty * per_days
				"fodder":
					fodder += qty * per_days
			continue
		# Fallback heuristic for catalog entries that haven't been tagged yet.
		if key.begins_with("rations_") or key == "iron_rations" or key == "standard_rations":
			food += qty * 7.0 * FOOD_PER_HUMANOID_PER_DAY
		elif key.begins_with("waterskin"):
			water += qty * 1.0
		elif key.begins_with("fodder_"):
			fodder += qty * 1.0
	return {"food": food, "water": water, "fodder": fodder}


# Lazy catalog cache — instantiated on first call so the tab works during
# tests that don't populate a full scene tree.
var _equipment_catalog: EquipmentCatalog = null


func _ensure_equipment_catalog() -> EquipmentCatalog:
	if _equipment_catalog == null:
		_equipment_catalog = EquipmentCatalog.new()
	return _equipment_catalog


func _creature_normal_load(creature: TrainedCreatureData) -> int:
	if creature.monster_data is Dictionary:
		var nl: int = int(creature.monster_data.get("normal_load", 0))
		if nl > 0:
			return nl
	return ANIMAL_FALLBACK_NORMAL_LOAD


func _food_tooltip(daily: float, total: float) -> String:
	var humanoid_count := 0
	for cd: CharacterData in _party.character_data:
		if cd.character_type == "pc" or cd.character_type == "henchman":
			humanoid_count += 1
	var days_remaining := -1
	if daily > 0.001:
		days_remaining = int(floor(total / daily))
	var lines: Array = [
		"Daily food (humanoids only):",
		"  %d humanoid × 1/6 stone = %.2f stone/day" % [humanoid_count, daily],
		"",
		"On hand: %.2f stone" % total,
		"Days remaining: %s" % ("—" if days_remaining < 0 else str(days_remaining)),
	]
	return "\n".join(lines)


func _water_tooltip(daily: float, total: float) -> String:
	var humanoid_count := 0
	for cd: CharacterData in _party.character_data:
		if cd.character_type == "pc" or cd.character_type == "henchman":
			humanoid_count += 1
	var animal_count: int = _party.creature_data.size()
	var days_remaining := -1
	if daily > 0.001:
		days_remaining = int(floor(total / daily))
	var lines: Array = [
		"Daily water:",
		"  %d humanoid × 5/6 stone (drinking) = %.2f stone" % [humanoid_count, humanoid_count * WATER_PER_HUMANOID_PER_DAY],
		"  %d animal × normal_load/5 stone = %.2f stone" % [animal_count, daily - humanoid_count * WATER_PER_HUMANOID_PER_DAY],
		"  Total: %.2f stone/day" % daily,
		"",
		"On hand: %.2f stone" % total,
		"Days remaining: %s" % ("—" if days_remaining < 0 else str(days_remaining)),
	]
	return "\n".join(lines)


func _fodder_tooltip(daily: float, total: float) -> String:
	var lines: Array = ["Daily fodder (animals):"]
	for creature: TrainedCreatureData in _party.creature_data:
		var nl: int = _creature_normal_load(creature)
		var per_day: float = nl / 10.0
		var name: String = creature.name if not creature.name.is_empty() else creature.species_id.capitalize()
		lines.append("  %s (normal_load %d): %d/10 = %.2f stone/day" % [name, nl, nl, per_day])
	lines.append("  Total: %.2f stone/day" % daily)
	lines.append("")
	lines.append("On hand: %.2f stone" % total)
	var days_remaining := -1
	if daily > 0.001:
		days_remaining = int(floor(total / daily))
	lines.append("Days remaining: %s" % ("—" if days_remaining < 0 else str(days_remaining)))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Formation sub-tab
# ---------------------------------------------------------------------------

const CELL_SIZE := Vector2(56, 28)
const CELL_MARGIN := 2

var _formation_view_btns: Dictionary = {}  # grid_id -> Button
var _formation_grid_root: Control = null
var _wilderness_grid_holder: Control = null
var _dungeon_grid_holder: Control = null
var _wilderness_unplaced_list: ItemList = null
var _wilderness_unplaced_ids: Array = []
var _dungeon_unplaced_list: ItemList = null
var _dungeon_unplaced_ids: Array = []
var _ineligible_label: Label = null

func _build_formation_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# Toggle row.
	var toggle_row := HBoxContainer.new()
	toggle_row.add_theme_constant_override("separation", 4)
	vbox.add_child(toggle_row)
	for grid_id in [PartyData.GRID_WILDERNESS, PartyData.GRID_DUNGEON]:
		var btn := Button.new()
		btn.text = "Wilderness Grid (6×12)" if grid_id == PartyData.GRID_WILDERNESS \
				else "Dungeon Grid (2×12)"
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_formation_view_toggle.bind(grid_id))
		toggle_row.add_child(btn)
		_formation_view_btns[grid_id] = btn

	# FRONT label.
	var front_lbl := Label.new()
	front_lbl.text = "FRONT (direction of travel)"
	front_lbl.add_theme_font_size_override("font_size", 9)
	front_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	front_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(front_lbl)

	# Grid root (only one grid visible at a time).
	_formation_grid_root = Control.new()
	_formation_grid_root.custom_minimum_size = Vector2(
		PartyData.WILDERNESS_COLS * (CELL_SIZE.x + CELL_MARGIN),
		PartyData.WILDERNESS_ROWS * (CELL_SIZE.y + CELL_MARGIN))
	vbox.add_child(_formation_grid_root)

	_wilderness_grid_holder = Control.new()
	_wilderness_grid_holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_formation_grid_root.add_child(_wilderness_grid_holder)
	_wilderness_grid_cells = _build_grid(_wilderness_grid_holder,
			PartyData.WILDERNESS_COLS, PartyData.WILDERNESS_ROWS,
			PartyData.GRID_WILDERNESS)

	_dungeon_grid_holder = Control.new()
	_dungeon_grid_holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_formation_grid_root.add_child(_dungeon_grid_holder)
	_dungeon_grid_cells = _build_grid(_dungeon_grid_holder,
			PartyData.DUNGEON_COLS, PartyData.DUNGEON_ROWS,
			PartyData.GRID_DUNGEON)

	# REAR label.
	var rear_lbl := Label.new()
	rear_lbl.text = "REAR"
	rear_lbl.add_theme_font_size_override("font_size", 9)
	rear_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	rear_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rear_lbl)

	vbox.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Drag a character from the unplaced list onto a grid cell to place, or drag between cells to relocate. Click an occupied cell to remove. (Click-to-select then click-to-place still works.)"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	# Unplaced lists — one per grid, only the active grid's list shows.
	var unplaced_header := Label.new()
	unplaced_header.text = "Unplaced (eligible)"
	unplaced_header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(unplaced_header)

	# H.3 — drag-source-aware ItemList subclasses; click-to-select behavior
	# is preserved.
	_wilderness_unplaced_list = FormationUnplacedListScript.new()
	_wilderness_unplaced_list.grid_id = PartyData.GRID_WILDERNESS
	_wilderness_unplaced_list.custom_minimum_size = Vector2(0, 100)
	_wilderness_unplaced_list.item_selected.connect(_on_unplaced_selected.bind(PartyData.GRID_WILDERNESS))
	vbox.add_child(_wilderness_unplaced_list)

	_dungeon_unplaced_list = FormationUnplacedListScript.new()
	_dungeon_unplaced_list.grid_id = PartyData.GRID_DUNGEON
	_dungeon_unplaced_list.custom_minimum_size = Vector2(0, 100)
	_dungeon_unplaced_list.item_selected.connect(_on_unplaced_selected.bind(PartyData.GRID_DUNGEON))
	vbox.add_child(_dungeon_unplaced_list)

	_ineligible_label = Label.new()
	_ineligible_label.add_theme_font_size_override("font_size", 9)
	_ineligible_label.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	_ineligible_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_ineligible_label)

	return scroll


func _build_grid(holder: Control, cols: int, rows: int, grid_id: String) -> Array:
	var grid_width: float = cols * (CELL_SIZE.x + CELL_MARGIN)
	var grid_height: float = rows * (CELL_SIZE.y + CELL_MARGIN)
	holder.custom_minimum_size = Vector2(grid_width, grid_height)
	holder.size = Vector2(grid_width, grid_height)
	var cells: Array = []
	for row in range(rows):
		var row_arr: Array = []
		for col in range(cols):
			# H.3 — FormationGridCell adds drag-drop on top of the existing
			# Button click flow. Cells emit `cell_drop_received` when an
			# unplaced item or another cell's occupant is dropped on them.
			var cell := FormationGridCellScript.new()
			cell.col = col
			cell.row = row
			cell.grid_id = grid_id
			cell.eligibility_check = _formation_drop_eligibility
			cell.custom_minimum_size = CELL_SIZE
			cell.position = Vector2(
				col * (CELL_SIZE.x + CELL_MARGIN),
				row * (CELL_SIZE.y + CELL_MARGIN))
			cell.size = CELL_SIZE
			cell.add_theme_font_size_override("font_size", 8)
			cell.clip_text = true
			cell.pressed.connect(_on_grid_cell_pressed.bind(col, row, grid_id))
			cell.cell_drop_received.connect(_on_formation_drop)
			holder.add_child(cell)
			row_arr.append(cell)
		cells.append(row_arr)
	return cells


# H.3 — drag-drop eligibility predicate passed into every grid cell. Returns
# false when the dragged entity isn't eligible for the destination grid
# (e.g., a horse onto the dungeon grid). For the wilderness grid the only
# constraint is that the entity exists in the unplaced or placed pool.
func _formation_drop_eligibility(entity_id: String, dest_grid: String) -> bool:
	if _party == null or entity_id.is_empty():
		return false
	if dest_grid == PartyData.GRID_DUNGEON:
		# Reuse the same per-creature flag-or-default check as the
		# ineligible-label rendering. PCs / henchmen are always eligible.
		for creature: TrainedCreatureData in _party.creature_data:
			if creature.id == entity_id and creature.monster_data is Dictionary:
				return bool(creature.monster_data.get("dungeon_eligible", true))
	return true


# H.3 — handle a drop into a grid cell. Two paths:
#   - source_col/row == -1 → drag came from the unplaced ItemList; just place.
#   - source_col/row >= 0  → drag came from another cell on the same grid;
#     vacate the source cell and place at the destination.
# A drop on an occupied destination cell currently overwrites the previous
# occupant (the displaced character returns to the unplaced pool); a
# future polish pass could swap occupants instead.
func _on_formation_drop(payload: Dictionary, dest_col: int, dest_row: int) -> void:
	if _party == null:
		return
	var entity_id: String = str(payload.get("character_id", ""))
	if entity_id.is_empty():
		return
	var src_grid: String = str(payload.get("source_grid", ""))
	var src_col: int = int(payload.get("source_col", -1))
	var src_row: int = int(payload.get("source_row", -1))
	if src_col >= 0 and src_row >= 0 and src_grid == _formation_active_grid:
		_party.unplace_character_for(entity_id, src_grid)
	# If the destination is already occupied, the existing occupant is
	# vacated first so set_formation_pos_for can place cleanly.
	var existing: String = _party.get_character_at_for(dest_col, dest_row, _formation_active_grid)
	if not existing.is_empty() and existing != entity_id:
		_party.unplace_character_for(existing, _formation_active_grid)
	_party.set_formation_pos_for(entity_id, dest_col, dest_row, _formation_active_grid)
	EventBus.formation_changed.emit(GameState.active_party_id)
	_selected_unplaced_id = ""
	_refresh_formation_grids()


func _on_formation_view_toggle(grid_id: String) -> void:
	if grid_id == _formation_active_grid:
		(_formation_view_btns[grid_id] as Button).button_pressed = true
		return
	_formation_active_grid = grid_id
	_selected_unplaced_id = ""
	_refresh_formation_grids()
	_persist_substate()


func _refresh_formation_grids() -> void:
	if _formation_grid_root == null:
		return
	# Toggle button highlight + grid visibility.
	for grid_id in _formation_view_btns.keys():
		(_formation_view_btns[grid_id] as Button).button_pressed = (grid_id == _formation_active_grid)
	_wilderness_grid_holder.visible = (_formation_active_grid == PartyData.GRID_WILDERNESS)
	_dungeon_grid_holder.visible = (_formation_active_grid == PartyData.GRID_DUNGEON)
	_wilderness_unplaced_list.visible = (_formation_active_grid == PartyData.GRID_WILDERNESS)
	_dungeon_unplaced_list.visible = (_formation_active_grid == PartyData.GRID_DUNGEON)

	# Grid root size depends on the active grid.
	if _formation_active_grid == PartyData.GRID_WILDERNESS:
		_formation_grid_root.custom_minimum_size = Vector2(
			PartyData.WILDERNESS_COLS * (CELL_SIZE.x + CELL_MARGIN),
			PartyData.WILDERNESS_ROWS * (CELL_SIZE.y + CELL_MARGIN))
	else:
		_formation_grid_root.custom_minimum_size = Vector2(
			PartyData.DUNGEON_COLS * (CELL_SIZE.x + CELL_MARGIN),
			PartyData.DUNGEON_ROWS * (CELL_SIZE.y + CELL_MARGIN))

	if _party == null:
		_clear_grid(_wilderness_grid_cells)
		_clear_grid(_dungeon_grid_cells)
		_wilderness_unplaced_list.clear()
		_wilderness_unplaced_ids = []
		_dungeon_unplaced_list.clear()
		_dungeon_unplaced_ids = []
		_ineligible_label.text = ""
		return

	_paint_grid(_wilderness_grid_cells, PartyData.GRID_WILDERNESS)
	_paint_grid(_dungeon_grid_cells, PartyData.GRID_DUNGEON)
	_refresh_unplaced_lists()
	_refresh_ineligible_label()


func _clear_grid(cells: Array) -> void:
	for row in cells:
		for cell: Button in row:
			cell.text = ""
			cell.disabled = true
			cell.tooltip_text = ""


func _paint_grid(cells: Array, grid_id: String) -> void:
	for r in range(cells.size()):
		for c in range(cells[r].size()):
			var cell: Button = cells[r][c]
			cell.disabled = false
			var cid: String = _party.get_character_at_for(c, r, grid_id)
			# H.3 — store the occupant id so FormationGridCell._get_drag_data
			# can return it without re-querying the party. Updated on every
			# repaint so it stays consistent with the rendered cell.
			cell.set_meta("character_id", cid)
			if cid.is_empty():
				cell.text = ""
				cell.tooltip_text = "Empty — click or drag a character to place"
			else:
				var cd: CharacterData = _party.get_member(cid)
				if cd != null:
					var short_name: String = cd.name.split(" ")[0]
					if short_name.length() > 7:
						short_name = short_name.left(6) + "."
					cell.text = short_name
					cell.tooltip_text = "%s (L%d %s) — click to remove or drag to relocate" % [
						cd.name, cd.level, cd.character_class.capitalize()]
				else:
					cell.text = "???"
					cell.tooltip_text = cid


func _refresh_unplaced_lists() -> void:
	_wilderness_unplaced_list.clear()
	_wilderness_unplaced_ids = []
	_dungeon_unplaced_list.clear()
	_dungeon_unplaced_ids = []
	# All party characters are wilderness-eligible (PCs / henchmen). Trained
	# creatures and vehicles are TODO for the unplaced UI in v1 — placement
	# UI for them lands once the per-creature drag-drop redesign is complete
	# (deferred per gdd-party-tab.md §7.6 follow-up).
	for cid in _party.get_unplaced_members_for(PartyData.GRID_WILDERNESS):
		var cd: CharacterData = _party.get_member(cid)
		_wilderness_unplaced_list.add_item(cd.name if cd != null else cid)
		_wilderness_unplaced_ids.append(cid)
	for cid in _party.get_unplaced_members_for(PartyData.GRID_DUNGEON):
		var cd: CharacterData = _party.get_member(cid)
		_dungeon_unplaced_list.add_item(cd.name if cd != null else cid)
		_dungeon_unplaced_ids.append(cid)
	# H.3 — sync the drag-source id maps with the freshly-built lists.
	_wilderness_unplaced_list.id_for_index = _wilderness_unplaced_ids.duplicate()
	_dungeon_unplaced_list.id_for_index = _dungeon_unplaced_ids.duplicate()
	if not _selected_unplaced_id.is_empty():
		var ids: Array = _wilderness_unplaced_ids if _formation_active_grid == PartyData.GRID_WILDERNESS \
				else _dungeon_unplaced_ids
		var idx: int = ids.find(_selected_unplaced_id)
		if idx >= 0:
			(_wilderness_unplaced_list if _formation_active_grid == PartyData.GRID_WILDERNESS
					else _dungeon_unplaced_list).select(idx)
		else:
			_selected_unplaced_id = ""


func _refresh_ineligible_label() -> void:
	if _formation_active_grid == PartyData.GRID_WILDERNESS:
		_ineligible_label.text = ""
		return
	# Dungeon view — list ineligible entities (vehicles, dungeon-ineligible
	# creatures, mercenaries when they exist).
	var ineligible: Array = []
	for v in _party.vehicle_data:
		var vname: String = str(v.get("name", str(v.get("item_key", "vehicle"))))
		ineligible.append("%s (vehicle — wilderness only)" % vname)
	for creature: TrainedCreatureData in _party.creature_data:
		# H.3 — prefer the explicit `dungeon_eligible` catalog flag (added per
		# species in monster_catalog.json for true wilderness-only mounts:
		# horses, camel, mule, ox, cow). Default true when absent so future
		# catalog entries are dungeon-eligible unless they opt out.
		var dungeon_eligible := true
		if creature.monster_data is Dictionary:
			dungeon_eligible = bool(creature.monster_data.get("dungeon_eligible", true))
		if not dungeon_eligible:
			var cname: String = creature.name if not creature.name.is_empty() else creature.species_id.capitalize()
			ineligible.append("%s (creature — dungeon-ineligible)" % cname)
	if ineligible.is_empty():
		_ineligible_label.text = ""
	else:
		_ineligible_label.text = "Ineligible for dungeon: " + ", ".join(ineligible)


func _on_unplaced_selected(index: int, grid_id: String) -> void:
	if grid_id != _formation_active_grid:
		return
	var ids: Array = _wilderness_unplaced_ids if grid_id == PartyData.GRID_WILDERNESS \
			else _dungeon_unplaced_ids
	if index >= 0 and index < ids.size():
		_selected_unplaced_id = ids[index]
	else:
		_selected_unplaced_id = ""


func _on_grid_cell_pressed(col: int, row: int, grid_id: String) -> void:
	if _party == null or grid_id != _formation_active_grid:
		return
	var occupant: String = _party.get_character_at_for(col, row, grid_id)
	if not occupant.is_empty():
		_party.unplace_character_for(occupant, grid_id)
		_persist_grid_position(occupant, PartyData.UNASSIGNED, PartyData.UNASSIGNED, grid_id)
	elif not _selected_unplaced_id.is_empty():
		_party.set_formation_pos_for(_selected_unplaced_id, col, row, grid_id)
		_persist_grid_position(_selected_unplaced_id, col, row, grid_id)
		_selected_unplaced_id = ""
	_refresh_formation_grids()
	EventBus.formation_changed.emit(_party.id)


func _persist_grid_position(character_id: String, col: int, row: int, grid_id: String) -> void:
	if _party == null:
		return
	if grid_id == PartyData.GRID_DUNGEON:
		CampaignRepository.update_party_member_dungeon_formation(_party.id, character_id, col, row)
	else:
		CampaignRepository.update_party_member_formation(_party.id, character_id, col, row)


# ---------------------------------------------------------------------------
# Data load / refresh
# ---------------------------------------------------------------------------

func _load_party() -> void:
	var pid := _resolve_party_id()
	if pid.is_empty():
		_party = null
		_refresh_all()
		return
	_party = CampaignRepository.load_party_data(pid)
	if _party == null:
		_refresh_all()
		return
	_party.character_data = []
	for row in CampaignRepository.list_party_characters(pid):
		_party.character_data.append(CharacterData.from_dict(row))
	_party.shared_inventory = []
	for row in CampaignRepository.get_party_inventory(pid):
		_party.shared_inventory.append(InventoryItem.from_dict(row))
	_party.creature_data = []
	for row in CampaignRepository.get_trained_creatures_for_party(pid):
		_party.creature_data.append(TrainedCreatureData.from_db(row))
	_party.vehicle_data = CampaignRepository.get_draft_vehicles_for_party(pid)
	_selected_unplaced_id = ""
	_refresh_all()


func _refresh_all() -> void:
	_refresh_header()
	if _active_subtab == SUBTAB_COMPOSITION:
		_refresh_composition_subtab()
	elif _active_subtab == SUBTAB_TRAVEL:
		_refresh_travel_subtab()
	elif _active_subtab == SUBTAB_FORMATION:
		_refresh_formation_grids()


# ---------------------------------------------------------------------------
# Substate
# ---------------------------------------------------------------------------

func _restore_substate() -> void:
	var pid := _resolve_party_id()
	var sub: Dictionary = NotebookState.get_substate_for_tab(pid, SUBSTATE_TAB_ID)
	_active_subtab = sub.get("active_subtab", SUBTAB_COMPOSITION)
	_formation_active_grid = sub.get("formation_active_grid", PartyData.GRID_WILDERNESS)
	if not SUBTAB_LABELS.has(_active_subtab):
		_active_subtab = SUBTAB_COMPOSITION
	if _formation_active_grid != PartyData.GRID_WILDERNESS \
			and _formation_active_grid != PartyData.GRID_DUNGEON:
		_formation_active_grid = PartyData.GRID_WILDERNESS
	_activate_subtab(_active_subtab)


func _persist_substate() -> void:
	var pid := _resolve_party_id()
	if pid.is_empty():
		return
	NotebookState.set_substate_for_tab(pid, SUBSTATE_TAB_ID, {
		"active_subtab":         _active_subtab,
		"formation_active_grid": _formation_active_grid,
	})


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

func _resolve_party_id() -> String:
	var pid := GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	return pid


func _on_open_inventory_pressed() -> void:
	EventBus.notebook_open_requested.emit("inventory")


func _on_camp_pressed() -> void:
	EventBus.camp_requested.emit()


func _on_member_name_clicked(character_id: String) -> void:
	EventBus.notebook_active_entity_requested.emit(character_id)


func _on_active_party_selected(index: int) -> void:
	if _composition_active_party_dropdown == null:
		return
	var pid: String = _composition_active_party_dropdown.get_item_metadata(index)
	if pid.is_empty():
		return
	GameState.set_active_party(pid)


func _on_merge_selected(index: int) -> void:
	if index == 0 or _party == null:
		return
	var source_id: String = _composition_merge_dropdown.get_item_metadata(index)
	if source_id.is_empty():
		return
	var source := CampaignRepository.get_party(source_id)
	var source_name: String = source.get("name", source_id)
	var ok := CampaignRepository.merge_parties(_party.id, source_id)
	EventBus.notification_requested.emit({
		"type":     "success" if ok else "danger",
		"category": "system",
		"title":    "Parties Merged" if ok else "Merge Failed",
		"body":     ("%s merged into %s." % [source_name, _party.name]) if ok
				else "Could not merge %s." % source_name,
	})


func _on_split_pressed() -> void:
	if _party == null or _party.character_data.size() < 2:
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Cannot Split",
			"body": "Need at least 2 characters to split the party.",
		})
		return
	if _split_dialog != null and is_instance_valid(_split_dialog):
		return
	_split_dialog = PartySplitDialogScript.new(_party)
	_split_dialog.split_completed.connect(_on_split_completed)
	_modal_layer.add_child(_split_dialog)


func _on_split_completed(_new_party_id: String) -> void:
	_split_dialog = null
	_load_party()


func _on_add_member(character_id: String) -> void:
	if _party == null:
		return
	CampaignRepository.add_party_member(_party.id, character_id)
	EventBus.party_member_joined.emit(_party.id, character_id)


func _on_transfer_member(index: int, character_id: String) -> void:
	if index == 0 or _party == null:
		return
	var party_index: int = index - 1
	if party_index < 0 or party_index >= _colocated_parties.size():
		return
	var target_party_id: String = _colocated_parties[party_index].id
	if _party.character_data.size() <= 1:
		return
	CampaignRepository.add_party_member(target_party_id, character_id)
	EventBus.party_member_left.emit(_party.id, character_id)
	EventBus.party_member_joined.emit(target_party_id, character_id)


func _on_forage_pressed() -> void:
	# γ.3 stub. Phase H+ wires this into the wilderness exploration system.
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "system",
		"title": "Forage",
		"body": "Foraging triggers will land alongside the wilderness exploration system.",
	})


func _on_hunt_pressed() -> void:
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "system",
		"title": "Hunt",
		"body": "Hunting triggers will land alongside the wilderness exploration system.",
	})


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_party_changed(_pid: String, _cid: String) -> void:
	_load_party()


func _on_party_event_refresh(_pid: String) -> void:
	_load_party()


func _on_inventory_change(_cid: String) -> void:
	if _active_subtab == SUBTAB_TRAVEL:
		_refresh_travel_subtab()


func _on_party_lifecycle_changed(_a: String, _b: String) -> void:
	_load_party()


func _on_active_party_event(_prev: String, _new: String) -> void:
	_restore_substate()
	_load_party()


func _on_wallet_changed(_pid: String) -> void:
	_refresh_header()
