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

# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _panel: PanelContainer
var _title_label: Label
var _tab_container: TabContainer

# Members tab
var _members_vbox: VBoxContainer

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

	_members_vbox = VBoxContainer.new()
	_members_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_members_vbox)
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
	if GameState.party_id.is_empty():
		_party = null
		_refresh_all()
		return

	_party = CampaignRepository.load_party_data(GameState.party_id)
	if _party == null:
		_refresh_all()
		return

	# Populate character_data from DB
	_party.character_data = []
	var char_rows: Array = CampaignRepository.list_party_characters(GameState.party_id)
	for row: Dictionary in char_rows:
		_party.character_data.append(CharacterData.from_dict(row))

	# Populate shared inventory
	var inv_rows: Array = CampaignRepository.get_party_inventory(GameState.party_id)
	_party.shared_inventory = []
	for row: Dictionary in inv_rows:
		_party.shared_inventory.append(InventoryItem.from_dict(row))

	# Load available characters (in campaign but not in this party)
	_load_available_characters()

	_selected_unplaced_id = ""
	_refresh_all()


func _load_available_characters() -> void:
	_available_characters = []
	if _party == null:
		return
	var all_chars: Array = CampaignRepository.list_characters(GameState.campaign_id)
	for row: Dictionary in all_chars:
		var cid: String = row.get("id", "")
		if not _party.has_member(cid) and row.get("is_active", 1) == 1 \
				and not bool(row.get("is_dead", 0)):
			_available_characters.append(row)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_title()
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

	for cd: CharacterData in _party.character_data:
		var row := _make_member_row(cd)
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


func _make_member_row(cd: CharacterData) -> HBoxContainer:
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
# Signal Handlers
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.party_member_joined.connect(_on_party_changed)
	EventBus.party_member_left.connect(_on_party_changed)
	EventBus.formation_changed.connect(_on_party_event_refresh)
	EventBus.inventory_updated.connect(_on_inventory_change)


func _on_party_changed(_party_id: String, _character_id: String) -> void:
	if visible:
		_load_party()


func _on_party_event_refresh(_party_id: String) -> void:
	if visible:
		_load_party()


func _on_inventory_change(_character_id: String) -> void:
	if visible:
		_refresh_travel_info()


func _on_add_member(character_id: String) -> void:
	if _party == null:
		return
	CampaignRepository.add_party_member(_party.id, character_id)
	EventBus.party_member_joined.emit(_party.id, character_id)


func _on_remove_member(character_id: String) -> void:
	if _party == null:
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
