extends CanvasLayer

## Party Management Overlay (E-1)
##
## Panel for managing party composition, formation grid, and viewing travel
## speed information. Toggle with Ctrl+Alt+P (party_management_toggle input
## action). Left-anchored panel, non-modal.
##
## The formation grid is 5 columns × 12 rows. Row 0 is the front of the
## formation (top of the grid). Marching order is derived from grid placement
## (front-to-back, left-to-right). Unplaced members are listed below the grid.
##
## Data loaded from CampaignRepository; auto-refreshes on relevant EventBus signals.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_COLS := PartyData.GRID_COLS   # 5
const GRID_ROWS := PartyData.GRID_ROWS   # 12

const CELL_SIZE := Vector2(56, 28)
const CELL_MARGIN := 2

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _party: PartyData = null
var _available_characters: Array = []  ## characters in campaign not in party
var _selected_unplaced_id: String = ""  ## character_id selected from unplaced list
var _split_dialog: CanvasLayer = null   ## modal split party dialog

# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _panel: PanelContainer
var _title_label: Label
var _tab_container: TabContainer

# Members tab
var _members_vbox: VBoxContainer
var _active_party_dropdown: OptionButton
var _split_btn: Button
var _merge_dropdown: OptionButton

# Formation tab
var _grid_container: Control       ## holds the formation grid cells
var _grid_cells: Array = []        ## 2D array [row][col] of Button references
var _unplaced_list: ItemList       ## characters not on grid
var _unplaced_ids: Array = []      ## parallel array of character_ids

# Travel tab
var _travel_info_vbox: VBoxContainer

# Status bar
var _status_label: Label


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 46
	visible = false
	_build_ui()
	_connect_signals()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("party_management_toggle"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		_close()
	else:
		open()


func open() -> void:
	if not GameState.is_in_session():
		return
	visible = true
	_load_party()


func _close() -> void:
	_save_state()
	visible = false


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.42
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
	_title_label.text = "Party Management"
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

	# -- Status bar --
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	root_vbox.add_child(_status_label)

	# -- Tab container --
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_tab_container)

	_build_members_tab()
	_build_formation_tab()
	_build_travel_tab()


func _build_members_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Members"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(outer_vbox)

	# -- Active Party selector row --
	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(party_row)

	var party_lbl := Label.new()
	party_lbl.text = "Active Party:"
	party_lbl.add_theme_font_size_override("font_size", 11)
	party_row.add_child(party_lbl)

	_active_party_dropdown = OptionButton.new()
	_active_party_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_party_dropdown.item_selected.connect(_on_active_party_selected)
	party_row.add_child(_active_party_dropdown)

	# -- Party Actions row --
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	outer_vbox.add_child(actions_row)

	_split_btn = Button.new()
	_split_btn.text = "Split Party"
	_split_btn.pressed.connect(_on_split_pressed)
	actions_row.add_child(_split_btn)

	_merge_dropdown = OptionButton.new()
	_merge_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merge_dropdown.item_selected.connect(_on_merge_selected)
	actions_row.add_child(_merge_dropdown)

	outer_vbox.add_child(HSeparator.new())

	# -- Members list --
	_members_vbox = VBoxContainer.new()
	_members_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_members_vbox)

	_tab_container.add_child(scroll)


func _build_formation_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Formation"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# Direction label
	var front_lbl := Label.new()
	front_lbl.text = "FRONT"
	front_lbl.add_theme_font_size_override("font_size", 9)
	front_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	front_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(front_lbl)

	# Grid
	_grid_container = Control.new()
	var grid_width: float = GRID_COLS * (CELL_SIZE.x + CELL_MARGIN)
	var grid_height: float = GRID_ROWS * (CELL_SIZE.y + CELL_MARGIN)
	_grid_container.custom_minimum_size = Vector2(grid_width, grid_height)
	vbox.add_child(_grid_container)

	_grid_cells = []
	for row in range(GRID_ROWS):
		var row_arr: Array = []
		for col in range(GRID_COLS):
			var cell := Button.new()
			cell.custom_minimum_size = CELL_SIZE
			cell.position = Vector2(
				col * (CELL_SIZE.x + CELL_MARGIN),
				row * (CELL_SIZE.y + CELL_MARGIN),
			)
			cell.size = CELL_SIZE
			cell.add_theme_font_size_override("font_size", 8)
			cell.clip_text = true
			cell.pressed.connect(_on_grid_cell_pressed.bind(col, row))
			_grid_container.add_child(cell)
			row_arr.append(cell)
		_grid_cells.append(row_arr)

	var rear_lbl := Label.new()
	rear_lbl.text = "REAR"
	rear_lbl.add_theme_font_size_override("font_size", 9)
	rear_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	rear_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rear_lbl)

	vbox.add_child(HSeparator.new())

	# Hint
	var hint := Label.new()
	hint.text = "Select an unplaced character, then click a grid cell to place them. Click an occupied cell to remove."
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	# Unplaced characters list
	var unplaced_header := Label.new()
	unplaced_header.text = "Unplaced Members"
	unplaced_header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(unplaced_header)

	_unplaced_list = ItemList.new()
	_unplaced_list.custom_minimum_size = Vector2(0, 100)
	_unplaced_list.item_selected.connect(_on_unplaced_selected)
	vbox.add_child(_unplaced_list)

	_tab_container.add_child(scroll)


func _build_travel_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Travel"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_travel_info_vbox = VBoxContainer.new()
	_travel_info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_travel_info_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_travel_info_vbox)
	_tab_container.add_child(scroll)


# ---------------------------------------------------------------------------
# Data Loading
# ---------------------------------------------------------------------------

func _load_party() -> void:
	# Use active_party_id for multi-party support
	var pid := GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	if pid.is_empty():
		_party = null
		_refresh_all()
		return

	_party = CampaignRepository.load_party_data(pid)
	if _party == null:
		_refresh_all()
		return

	# Populate character_data from DB
	_party.character_data = []
	var char_rows: Array = CampaignRepository.list_party_characters(pid)
	for row: Dictionary in char_rows:
		_party.character_data.append(CharacterData.from_dict(row))

	# Populate shared inventory
	var inv_rows: Array = CampaignRepository.get_party_inventory(pid)
	_party.shared_inventory = []
	for row: Dictionary in inv_rows:
		_party.shared_inventory.append(InventoryItem.from_dict(row))

	# Populate creature_data
	_party.creature_data = []
	var creature_rows := CampaignRepository.get_trained_creatures_for_party(pid)
	for row: Dictionary in creature_rows:
		_party.creature_data.append(TrainedCreatureData.from_db(row))

	# Populate vehicle_data
	_party.vehicle_data = CampaignRepository.get_draft_vehicles_for_party(pid)

	# Load available characters (in campaign but not in this party)
	_load_available_characters()

	_selected_unplaced_id = ""
	_refresh_all()


func _load_available_characters() -> void:
	_available_characters = []
	if _party == null:
		return
	# Only show characters not in ANY party (not just this one).
	_available_characters = CampaignRepository.list_unpartied_characters(GameState.campaign_id)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_title()
	_refresh_party_dropdown()
	_refresh_merge_dropdown()
	_refresh_members()
	_refresh_formation_grid()
	_refresh_travel_info()


func _refresh_title() -> void:
	if _party != null:
		_title_label.text = _party.name
		var placed_count: int = _party.get_placed_members().size()
		_status_label.text = "%d member%s (%d placed)" % [
			_party.members.size(),
			"" if _party.members.size() == 1 else "s",
			placed_count,
		]
	else:
		_title_label.text = "No Party"
		_status_label.text = ""


func _refresh_members() -> void:
	for child in _members_vbox.get_children():
		child.queue_free()

	if _party == null:
		return

	# Current members
	var header := Label.new()
	header.text = "Current Members"
	header.add_theme_font_size_override("font_size", 12)
	_members_vbox.add_child(header)

	var campaign_party_count: int = CampaignRepository.list_parties_for_campaign(
		GameState.campaign_id).size()
	for cd: CharacterData in _party.character_data:
		var row := _make_member_row(cd, campaign_party_count)
		_members_vbox.add_child(row)

	_members_vbox.add_child(HSeparator.new())

	# Available characters to add
	var avail_header := Label.new()
	avail_header.text = "Available Characters"
	avail_header.add_theme_font_size_override("font_size", 12)
	_members_vbox.add_child(avail_header)

	if _available_characters.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No available characters."
		none_lbl.add_theme_font_size_override("font_size", 10)
		none_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
		_members_vbox.add_child(none_lbl)
	else:
		for char_row: Dictionary in _available_characters:
			var row := _make_available_row(char_row)
			_members_vbox.add_child(row)


func _make_member_row(cd: CharacterData, campaign_party_count: int = 1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = "%s (L%d %s)" % [cd.name, cd.level, cd.character_class.capitalize()]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(name_lbl)

	var pos := _party.get_formation_pos(cd.id)
	var pos_text: String
	if pos.x == PartyData.UNASSIGNED:
		pos_text = "Unplaced"
	else:
		pos_text = "R%d C%d" % [pos.y + 1, pos.x + 1]
	var pos_lbl := Label.new()
	pos_lbl.text = pos_text
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	pos_lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(pos_lbl)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.custom_minimum_size = Vector2(60, 0)
	if campaign_party_count <= 1:
		remove_btn.disabled = true
		remove_btn.tooltip_text = "Cannot remove — only one party exists"
	remove_btn.pressed.connect(_on_remove_member.bind(cd.id))
	row.add_child(remove_btn)

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


func _refresh_formation_grid() -> void:
	if _party == null:
		# Clear all cells
		for row in range(GRID_ROWS):
			for col in range(GRID_COLS):
				_grid_cells[row][col].text = ""
				_grid_cells[row][col].disabled = true
		_unplaced_list.clear()
		_unplaced_ids = []
		return

	# Update grid cells
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var cell: Button = _grid_cells[row][col]
			cell.disabled = false
			var cid: String = _party.get_character_at(col, row)
			if cid.is_empty():
				cell.text = ""
				cell.tooltip_text = "Empty — click to place selected character"
			else:
				var cd: CharacterData = _party.get_member(cid)
				if cd != null:
					# Abbreviate: first name, max 7 chars
					var short_name: String = cd.name.split(" ")[0]
					if short_name.length() > 7:
						short_name = short_name.left(6) + "."
					cell.text = short_name
					cell.tooltip_text = "%s (L%d %s) — click to remove" % [
						cd.name, cd.level, cd.character_class.capitalize()]
				else:
					cell.text = "???"
					cell.tooltip_text = cid

	# Unplaced members list
	_unplaced_list.clear()
	_unplaced_ids = []
	var unplaced: Array = _party.get_unplaced_members()
	for cid: String in unplaced:
		var cd: CharacterData = _party.get_member(cid)
		var label: String = cd.name if cd != null else cid
		_unplaced_list.add_item(label)
		_unplaced_ids.append(cid)

	# Restore selection if still valid
	if not _selected_unplaced_id.is_empty():
		var idx: int = _unplaced_ids.find(_selected_unplaced_id)
		if idx >= 0:
			_unplaced_list.select(idx)
		else:
			_selected_unplaced_id = ""


func _refresh_travel_info() -> void:
	for child in _travel_info_vbox.get_children():
		child.queue_free()

	if _party == null:
		return

	# Base movement
	var slowest: int = _party.get_slowest_movement()
	_add_info_row("Base Movement (slowest)", "%d'/turn" % slowest)

	# Miles per day in clear terrain
	var clear_speed: Dictionary = TravelSpeedCalculator.calculate_party_speed(
		_party, "clear"
	)
	_add_info_row("Clear Terrain", "%.0f mi/day" % clear_speed["miles_per_day"])

	# Show terrain variants
	for terrain in ["woods", "hills", "desert", "mountains", "swamp", "jungle"]:
		var spd: Dictionary = TravelSpeedCalculator.calculate_party_speed(_party, terrain)
		_add_info_row(terrain.capitalize(), "%.0f mi/day" % spd["miles_per_day"])

	_travel_info_vbox.add_child(HSeparator.new())

	# Rest status
	var rest_pen: int = TravelSpeedCalculator.rest_penalty(_party)
	_add_info_row("Days Since Rest", str(_party.days_since_rest))
	if rest_pen > 0:
		var warn := Label.new()
		warn.text = "Fatigue penalty: -%d to attack and damage" % rest_pen
		warn.add_theme_font_size_override("font_size", 10)
		warn.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
		_travel_info_vbox.add_child(warn)

	# Forced march status
	var fm_elig: Dictionary = TravelSpeedCalculator.check_force_march_eligibility(_party)
	_add_info_row("Forced March", "%d/%d days used" % [fm_elig["days_used"], fm_elig["max_days"]])

	# Rations
	_add_info_row("Rations", "%d day%s remaining" % [
		_party.rations_days_remaining,
		"" if _party.rations_days_remaining == 1 else "s",
	])

	_travel_info_vbox.add_child(HSeparator.new())

	# Navigation proficiency
	if _party.any_member_has_proficiency("navigation"):
		_add_info_row("Navigation", "+4 to avoid getting lost")
	else:
		_add_info_row("Navigation", "No navigator (base chances)")

	# Endurance proficiency
	if _party.any_member_has_proficiency("endurance"):
		_add_info_row("Endurance", "No mandatory rest; extended forced march")


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


# ---------------------------------------------------------------------------
# Party Dropdown / Split / Merge
# ---------------------------------------------------------------------------

## Populates the Active Party dropdown with all campaign parties.
func _refresh_party_dropdown() -> void:
	_active_party_dropdown.clear()
	if not GameState.is_in_session():
		return
	var all_parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	var active_id := GameState.active_party_id
	if active_id.is_empty():
		active_id = GameState.party_id
	var select_idx := 0
	for i in range(all_parties.size()):
		var p: Dictionary = all_parties[i]
		_active_party_dropdown.add_item(p.name, i)
		_active_party_dropdown.set_item_metadata(i, p.id)
		if p.id == active_id:
			select_idx = i
	if _active_party_dropdown.item_count > 0:
		_active_party_dropdown.select(select_idx)


## Populates the Merge With dropdown with co-located parties (not the active one).
func _refresh_merge_dropdown() -> void:
	_merge_dropdown.clear()
	_merge_dropdown.add_item("Merge With...", 0)
	_merge_dropdown.set_item_disabled(0, true)
	if _party == null or not GameState.is_in_session():
		_merge_dropdown.disabled = true
		_merge_dropdown.tooltip_text = "No parties at this hex."
		return
	var all_parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	var active_id := _party.id
	var count := 0
	for p in all_parties:
		if p.id == active_id:
			continue
		# Co-location check
		if p.current_map_id == _party.current_map_id \
				and p.current_hex_q == _party.current_hex_q \
				and p.current_hex_r == _party.current_hex_r:
			var idx: int = _merge_dropdown.item_count
			_merge_dropdown.add_item(p.name, idx)
			_merge_dropdown.set_item_metadata(idx, p.id)
			count += 1
	if count == 0:
		_merge_dropdown.disabled = true
		_merge_dropdown.tooltip_text = "No parties at this hex."
	else:
		_merge_dropdown.disabled = false
		_merge_dropdown.tooltip_text = ""


func _on_active_party_selected(index: int) -> void:
	var pid: String = _active_party_dropdown.get_item_metadata(index)
	if pid.is_empty():
		return
	GameState.set_active_party(pid)
	_load_party()


func _on_merge_selected(index: int) -> void:
	if index == 0:
		return  # placeholder item
	var source_id: String = _merge_dropdown.get_item_metadata(index)
	if source_id.is_empty() or _party == null:
		return
	var source := CampaignRepository.get_party(source_id)
	var source_name: String = source.get("name", source_id)
	# Confirm merge
	var ok := CampaignRepository.merge_parties(_party.id, source_id)
	if ok:
		EventBus.notification_requested.emit({
			"type": "success",
			"category": "system",
			"title": "Parties Merged",
			"body": "%s merged into %s." % [source_name, _party.name],
		})
	else:
		EventBus.notification_requested.emit({
			"type": "danger",
			"category": "system",
			"title": "Merge Failed",
			"body": "Could not merge %s." % source_name,
		})
	_load_party()


func _on_split_pressed() -> void:
	if _party == null or _party.character_data.size() < 2:
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Cannot Split",
			"body": "Need at least 2 characters to split the party.",
		})
		return
	_open_split_dialog()


func _open_split_dialog() -> void:
	if _split_dialog != null:
		return

	_split_dialog = CanvasLayer.new()
	_split_dialog.layer = 50

	var panel := PanelContainer.new()
	panel.anchor_left = 0.25
	panel.anchor_top = 0.15
	panel.anchor_right = 0.75
	panel.anchor_bottom = 0.85
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	UiSurfaceStyles.apply_framed_window_chrome(panel)
	_split_dialog.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	var title_lbl := Label.new()
	title_lbl.text = "Split Party"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_row.add_child(title_lbl)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(_close_split_dialog)
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var inst_lbl := Label.new()
	inst_lbl.text = "Select characters to move to the new party:"
	inst_lbl.add_theme_font_size_override("font_size", 11)
	inst_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(inst_lbl)

	# Character checkboxes
	var check_scroll := ScrollContainer.new()
	check_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(check_scroll)

	var check_vbox := VBoxContainer.new()
	check_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_scroll.add_child(check_vbox)

	var checkboxes: Array = []
	for cd: CharacterData in _party.character_data:
		var cb := CheckBox.new()
		cb.text = "%s (L%d %s)" % [cd.name, cd.level, cd.character_class.capitalize()]
		cb.set_meta("character_id", cd.id)
		check_vbox.add_child(cb)
		checkboxes.append(cb)

	# Creature checkboxes
	var creature_checkboxes: Array = []
	if not _party.creature_data.is_empty():
		check_vbox.add_child(HSeparator.new())
		var creature_header := Label.new()
		creature_header.text = "Creatures:"
		creature_header.add_theme_font_size_override("font_size", 11)
		check_vbox.add_child(creature_header)
		for creature: TrainedCreatureData in _party.creature_data:
			var cb := CheckBox.new()
			var display_name: String = creature.name if not creature.name.is_empty() else creature.species_id.capitalize()
			var handler_text := ""
			if not creature.handler_id.is_empty():
				var handler_char := CampaignRepository.get_character(creature.handler_id)
				handler_text = " (handler: %s)" % str(handler_char.get("name", "unknown"))
			cb.text = "%s%s" % [display_name, handler_text]
			cb.set_meta("creature_id", creature.id)
			cb.set_meta("handler_id", creature.handler_id)
			check_vbox.add_child(cb)
			creature_checkboxes.append(cb)

	# Vehicle checkboxes
	var vehicle_checkboxes: Array = []
	if not _party.vehicle_data.is_empty():
		check_vbox.add_child(HSeparator.new())
		var vehicle_header := Label.new()
		vehicle_header.text = "Vehicles:"
		vehicle_header.add_theme_font_size_override("font_size", 11)
		check_vbox.add_child(vehicle_header)
		for v: Dictionary in _party.vehicle_data:
			var cb := CheckBox.new()
			var vname: String = str(v.get("name", ""))
			if vname.is_empty():
				vname = str(v.get("item_key", "vehicle")).capitalize()
			var hitch_text := ""
			var h_json: String = str(v.get("hitched_creatures", "[]"))
			var h_ids = JSON.parse_string(h_json)
			if h_ids is Array and not h_ids.is_empty():
				hitch_text = " (hitched: %d creature%s)" % [h_ids.size(), "" if h_ids.size() == 1 else "s"]
			cb.text = "%s%s" % [vname, hitch_text]
			cb.set_meta("vehicle_id", str(v.get("id", "")))
			check_vbox.add_child(cb)
			vehicle_checkboxes.append(cb)

	# Name field
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	vbox.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "New party name:"
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_row.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.text = "%s (Detachment)" % _party.name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)

	# Warning
	var warn_lbl := Label.new()
	warn_lbl.text = "At least 1 character must remain in the original party."
	warn_lbl.add_theme_font_size_override("font_size", 9)
	warn_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
	vbox.add_child(warn_lbl)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_close_split_dialog)
	btn_row.add_child(cancel_btn)

	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.pressed.connect(_on_split_confirm.bind(checkboxes, creature_checkboxes, vehicle_checkboxes, name_edit))
	btn_row.add_child(create_btn)

	add_child(_split_dialog)


func _close_split_dialog() -> void:
	if _split_dialog != null:
		_split_dialog.queue_free()
		_split_dialog = null


func _on_split_confirm(checkboxes: Array, creature_checkboxes: Array,
		vehicle_checkboxes: Array, name_edit: LineEdit) -> void:
	var selected_ids: Array = []
	for cb: CheckBox in checkboxes:
		if cb.button_pressed:
			selected_ids.append(cb.get_meta("character_id"))

	if selected_ids.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "No Characters Selected",
			"body": "The new party must have at least one character.",
		})
		return

	if selected_ids.size() >= _party.character_data.size():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Cannot Empty Party",
			"body": "At least 1 character must remain in the original party.",
		})
		return

	# Collect creature selections
	var selected_creature_ids: Array = []
	for cb: CheckBox in creature_checkboxes:
		if cb.button_pressed:
			selected_creature_ids.append(cb.get_meta("creature_id"))

	# Collect vehicle selections
	var selected_vehicle_ids: Array = []
	for cb: CheckBox in vehicle_checkboxes:
		if cb.button_pressed:
			selected_vehicle_ids.append(cb.get_meta("vehicle_id"))

	# Build handler reassignment context — auto-clear handler when mismatch
	var handler_reassignments := {}
	var handler_warnings: Array = []
	for creature: TrainedCreatureData in _party.creature_data:
		if creature.handler_id.is_empty():
			continue
		var creature_moving: bool = selected_creature_ids.has(creature.id)
		var handler_moving: bool = selected_ids.has(creature.handler_id)
		if creature_moving != handler_moving:
			# Mismatch — auto-clear handler
			handler_reassignments[creature.id] = ""
			var cname: String = creature.name if not creature.name.is_empty() else creature.species_id.capitalize()
			handler_warnings.append(cname)

	var split_context := {}
	if not handler_reassignments.is_empty():
		split_context["handler_reassignments"] = handler_reassignments

	var new_name: String = name_edit.text.strip_edges()
	if new_name.is_empty():
		new_name = "%s (Detachment)" % _party.name

	var new_id := CampaignRepository.split_party(
		_party.id, new_name, selected_ids,
		selected_creature_ids, selected_vehicle_ids, split_context)
	if new_id.is_empty():
		EventBus.notification_requested.emit({
			"type": "danger",
			"category": "system",
			"title": "Split Failed",
			"body": "Could not split the party. Check the error log.",
		})
	else:
		var parts: Array = []
		parts.append("%d character%s" % [selected_ids.size(),
			"" if selected_ids.size() == 1 else "s"])
		if not selected_creature_ids.is_empty():
			parts.append("%d creature%s" % [selected_creature_ids.size(),
				"" if selected_creature_ids.size() == 1 else "s"])
		if not selected_vehicle_ids.is_empty():
			parts.append("%d vehicle%s" % [selected_vehicle_ids.size(),
				"" if selected_vehicle_ids.size() == 1 else "s"])
		var body_text := "%s created with %s." % [new_name, ", ".join(parts)]
		if not handler_warnings.is_empty():
			body_text += " Handler cleared for: %s." % ", ".join(handler_warnings)
		EventBus.notification_requested.emit({
			"type": "success",
			"category": "system",
			"title": "Party Split",
			"body": body_text,
		})

	_close_split_dialog()
	_load_party()


# ---------------------------------------------------------------------------
# Signal Handlers
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.party_member_joined.connect(_on_party_changed)
	EventBus.party_member_left.connect(_on_party_changed)
	EventBus.formation_changed.connect(_on_party_event_refresh)
	EventBus.inventory_updated.connect(_on_inventory_change)
	EventBus.party_split.connect(_on_party_lifecycle_changed)
	EventBus.party_merged.connect(_on_party_lifecycle_changed)
	EventBus.active_party_changed.connect(_on_active_party_event)


func _on_party_changed(_party_id: String, _character_id: String) -> void:
	if visible:
		_load_party()


func _on_party_event_refresh(_party_id: String) -> void:
	if visible:
		_load_party()


func _on_inventory_change(_character_id: String) -> void:
	if visible:
		_refresh_travel_info()


func _on_party_lifecycle_changed(_id_a: String, _id_b: String) -> void:
	if visible:
		_load_party()


func _on_active_party_event(_prev_id: String, _new_id: String) -> void:
	if visible:
		_load_party()


func _on_add_member(character_id: String) -> void:
	if _party == null:
		return
	CampaignRepository.add_party_member(_party.id, character_id)
	EventBus.party_member_joined.emit(_party.id, character_id)


func _on_remove_member(character_id: String) -> void:
	if _party == null:
		return
	# Prevent orphaning: only allow removal if other parties exist to receive the character.
	var parties := CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	if parties.size() <= 1:
		push_warning("Cannot remove character from only party — use Split Party instead")
		return
	CampaignRepository.remove_party_member(_party.id, character_id)
	EventBus.party_member_left.emit(_party.id, character_id)


func _on_unplaced_selected(index: int) -> void:
	if index >= 0 and index < _unplaced_ids.size():
		_selected_unplaced_id = _unplaced_ids[index]
	else:
		_selected_unplaced_id = ""


func _on_grid_cell_pressed(col: int, row: int) -> void:
	if _party == null:
		return

	var occupant: String = _party.get_character_at(col, row)
	if not occupant.is_empty():
		# Cell is occupied — remove character from grid (unplace)
		_party.unplace_character(occupant)
		CampaignRepository.update_party_member_formation(_party.id, occupant,
			PartyData.UNASSIGNED, PartyData.UNASSIGNED)
		_refresh_formation_grid()
		EventBus.formation_changed.emit(_party.id)
	elif not _selected_unplaced_id.is_empty():
		# Cell is empty and we have a selected unplaced character — place them
		_party.set_formation_pos(_selected_unplaced_id, col, row)
		CampaignRepository.update_party_member_formation(_party.id,
			_selected_unplaced_id, col, row)
		_selected_unplaced_id = ""
		_refresh_formation_grid()
		EventBus.formation_changed.emit(_party.id)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _save_state() -> void:
	if _party == null:
		return
	CampaignRepository.save_party_state(_party.to_state_dict())
