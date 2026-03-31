extends CanvasLayer

## OverridePanel — dev-mode interface for direct game state manipulation.
##
## Opened/closed with Ctrl+Alt+O (action: override_panel_toggle).
## Shows a one-time-per-session warning on first open.
## Each tab section drives a specific category of OverrideManager calls.
##
## Node structure expected (set up in override_panel.tscn):
##   OverridePanel (CanvasLayer, layer=128)
##   └── PanelContainer
##       ├── VBoxContainer
##       │   ├── TitleBar (HBoxContainer)
##       │   │   ├── Label ("⚠ OVERRIDE MODE")
##       │   │   └── CloseButton (Button, text="✕")
##       │   └── TabContainer
##       │       ├── CharactersTab (VBoxContainer, name="Characters")
##       │       ├── InventoryTab (VBoxContainer, name="Inventory")
##       │       ├── WorldTab (VBoxContainer, name="World")
##       │       ├── SpawningTab (VBoxContainer, name="Spawning")
##       │       ├── DiceTab (VBoxContainer, name="Dice")
##       │       ├── SnapshotsTab (VBoxContainer, name="Snapshots")
##       │       └── LogTab (VBoxContainer, name="Log")
##   └── WarningDialog (AcceptDialog)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _override_manager: OverrideManager = null
var _warning_shown_this_session := false
var _selected_character_id := ""
var _selected_map_id := ""
var _selected_hex := Vector2i.ZERO
var _hex_controller: HexMapController = null

# Cached panel nodes — assigned in _ready()
var _panel: PanelContainer
var _tab_container: TabContainer
var _warning_dialog: AcceptDialog

# Per-tab node refs (Characters tab)
var _char_list: ItemList
var _char_stat_field: OptionButton
var _char_stat_value: SpinBox
var _char_stat_apply_btn: Button
var _char_xp_delta: SpinBox
var _char_xp_apply_btn: Button
var _char_condition_name: LineEdit
var _char_condition_apply_btn: Button
var _char_condition_remove_btn: Button
var _char_dead_toggle: CheckButton

# Per-tab node refs (Inventory tab)
var _inv_char_list: ItemList
var _inv_item_list: ItemList
var _inv_item_key: LineEdit
var _inv_item_name: LineEdit
var _inv_qty: SpinBox
var _inv_enc: SpinBox
var _inv_slot: OptionButton
var _inv_add_btn: Button
var _inv_remove_btn: Button
var _inv_gold_delta: SpinBox
var _inv_gold_apply_btn: Button

# Per-tab node refs (World tab)
var _world_hex_q: SpinBox
var _world_hex_r: SpinBox
var _world_terrain_field: OptionButton
var _world_terrain_value_opt: OptionButton
var _world_terrain_apply_btn: Button
var _world_fog_reveal_btn: Button
var _world_fog_hide_btn: Button
var _world_fog_reveal_hex_btn: Button
var _world_fog_hex_state: OptionButton
var _world_fog_hex_apply_btn: Button
var _world_settlement_name: LineEdit
var _world_settlement_place_btn: Button
var _world_dungeon_name: LineEdit
var _world_dungeon_place_btn: Button

# Per-tab node refs (Spawning tab)
var _spawn_monster_key: LineEdit
var _spawn_count: SpinBox
var _spawn_disposition: OptionButton
var _spawn_hex_q: SpinBox
var _spawn_hex_r: SpinBox
var _spawn_btn: Button

# Per-tab node refs (Dice tab)
var _dice_roll_type: OptionButton
var _dice_value: SpinBox
var _dice_queue_btn: Button
var _dice_queue_list: ItemList
var _dice_clear_all_btn: Button
var _dice_export_btn: Button

# Per-tab node refs (Snapshots tab)
var _snap_label: LineEdit
var _snap_save_btn: Button
var _snap_list: ItemList
var _snap_restore_btn: Button
var _snap_delete_btn: Button
var _snap_confirm_dialog: ConfirmationDialog

# Per-tab node refs (Log tab)
var _log_list: ItemList
var _log_refresh_btn: Button

# Per-tab node refs (Testing tab)
var _test_char_create_btn: Button
var _test_dice_btn: Button
var _test_hint_label: Label

# Dice roll types — must match OverrideManager vocabulary
const ROLL_TYPES := [
	"encounter_check",
	"player_surprise_check",
	"monster_surprise_check",
	"initiative",
	"attack_throw",
	"damage_roll",
	"saving_throw_petrification",
	"saving_throw_poison",
	"saving_throw_blast",
	"saving_throw_wands",
	"saving_throw_spells",
	"morale_check",
	"reaction_roll",
	"thief_skill_throw",
	"proficiency_throw",
	"domain_event_roll",
	"hijink_roll",
	"mortal_wound_roll",
	"tampering_with_mortality",
]

const CHARACTER_STAT_FIELDS := [
	"strength", "intelligence", "wisdom", "dexterity", "constitution", "charisma",
	"hp_max", "hp_current", "armor_class", "attack_throw", "level", "xp",
	"loyalty_score", "wage_gp_per_month",
]

const TERRAIN_FIELDS := ["elevation", "biome", "water", "civilization", "has_city"]

const TERRAIN_VALUE_OPTIONS := {
	"elevation":    ["flat", "hills", "mountains"],
	"biome":        ["clear", "woods", "jungle", "swamp", "desert"],
	"water":        ["none", "river", "ocean"],
	"civilization": ["civilized", "borderlands", "wilderness"],
	"has_city":     ["0", "1"],
}

const INVENTORY_SLOTS := ["pack", "hands_main", "hands_off", "body", "head", "belt", "mount"]

const DISPOSITIONS := ["hostile", "cautious", "neutral", "friendly"]

const FOG_STATES := ["hidden", "explored", "visible"]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 128
	visible = false
	_build_ui()
	_connect_signals()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("override_panel_toggle"):
		_toggle()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API (called by Main to inject dependencies)
# ---------------------------------------------------------------------------

func setup(override_manager: OverrideManager, hex_controller: HexMapController) -> void:
	_override_manager = override_manager
	_hex_controller = hex_controller
	if _hex_controller != null and _hex_controller.get_map() != null:
		_selected_map_id = _hex_controller.get_map().id


# ---------------------------------------------------------------------------
# Toggle and warning
# ---------------------------------------------------------------------------

func _toggle() -> void:
	if not visible:
		_open()
	else:
		visible = false


func _open() -> void:
	if not _warning_shown_this_session:
		_warning_dialog.popup_centered()
		# visible is set to true after warning is dismissed (see _on_warning_confirmed)
	else:
		visible = true
		_refresh_active_tab()


func _on_warning_confirmed() -> void:
	_warning_shown_this_session = true
	visible = true
	_refresh_active_tab()


# ---------------------------------------------------------------------------
# Tab refresh
# ---------------------------------------------------------------------------

func _refresh_active_tab() -> void:
	match _tab_container.current_tab:
		0: _refresh_characters_tab()
		1: _refresh_inventory_tab()
		2: pass  # World tab is driven by user input, no auto-refresh needed
		3: pass  # Spawning tab is form-based
		4: _refresh_dice_tab()
		5: _refresh_snapshots_tab()
		6: _refresh_log_tab()
		7: pass  # Testing tab is button-only, no refresh needed


func _on_tab_changed(_idx: int) -> void:
	_refresh_active_tab()


# ---------------------------------------------------------------------------
# Characters tab
# ---------------------------------------------------------------------------

func _refresh_characters_tab() -> void:
	_char_list.clear()
	if GameState.party_id.is_empty():
		_char_list.add_item("(No active party)")
		return
	var members := CampaignRepository.list_party_characters(GameState.party_id)
	for m in members:
		_char_list.add_item("%s — %s L%d" % [
			m.get("name", "?"),
			m.get("character_class", "?"),
			m.get("level", 1)
		])
		_char_list.set_item_metadata(_char_list.item_count - 1, m.get("id", ""))


func _on_char_selected(idx: int) -> void:
	_selected_character_id = _char_list.get_item_metadata(idx)


func _on_char_stat_apply() -> void:
	if _selected_character_id.is_empty():
		return
	var field: String = CHARACTER_STAT_FIELDS[_char_stat_field.selected]
	var value: int = int(_char_stat_value.value)
	_override_manager.override_character_stat(_selected_character_id, field, value)


func _on_char_xp_apply() -> void:
	if _selected_character_id.is_empty():
		return
	_override_manager.override_character_xp(_selected_character_id, int(_char_xp_delta.value))


func _on_char_condition_apply() -> void:
	if _selected_character_id.is_empty() or _char_condition_name.text.is_empty():
		return
	_override_manager.override_character_condition(_selected_character_id, _char_condition_name.text, true)


func _on_char_condition_remove() -> void:
	if _selected_character_id.is_empty() or _char_condition_name.text.is_empty():
		return
	_override_manager.override_character_condition(_selected_character_id, _char_condition_name.text, false)


func _on_char_dead_toggled(pressed: bool) -> void:
	if _selected_character_id.is_empty():
		return
	_override_manager.override_character_status(_selected_character_id, pressed)


# ---------------------------------------------------------------------------
# Inventory tab
# ---------------------------------------------------------------------------

func _refresh_inventory_tab() -> void:
	_inv_char_list.clear()
	if GameState.party_id.is_empty():
		return
	var members := CampaignRepository.list_party_characters(GameState.party_id)
	for m in members:
		_inv_char_list.add_item(m.get("name", "?"))
		_inv_char_list.set_item_metadata(_inv_char_list.item_count - 1, m.get("id", ""))


func _on_inv_char_selected(idx: int) -> void:
	_selected_character_id = _inv_char_list.get_item_metadata(idx)
	_refresh_inv_item_list()


func _refresh_inv_item_list() -> void:
	_inv_item_list.clear()
	if _selected_character_id.is_empty():
		return
	var items := CampaignRepository.get_inventory_items(_selected_character_id)
	for item in items:
		_inv_item_list.add_item("%s x%d (%s)" % [
			item.get("name", "?"),
			item.get("quantity", 1),
			item.get("slot", "pack")
		])
		_inv_item_list.set_item_metadata(_inv_item_list.item_count - 1, item.get("id", ""))


func _on_inv_add() -> void:
	if _selected_character_id.is_empty():
		return
	_override_manager.override_add_item(
		_selected_character_id,
		_inv_item_key.text,
		_inv_item_name.text,
		int(_inv_qty.value),
		int(_inv_enc.value),
		INVENTORY_SLOTS[_inv_slot.selected]
	)
	_refresh_inv_item_list()


func _on_inv_remove() -> void:
	var selected := _inv_item_list.get_selected_items()
	if selected.is_empty():
		return
	var item_id: String = _inv_item_list.get_item_metadata(selected[0])
	_override_manager.override_remove_item(item_id)
	_refresh_inv_item_list()


func _on_inv_gold_apply() -> void:
	if _selected_character_id.is_empty():
		return
	_override_manager.override_adjust_gold(_selected_character_id, int(_inv_gold_delta.value))
	_refresh_inv_item_list()


# ---------------------------------------------------------------------------
# World tab
# ---------------------------------------------------------------------------

func _on_world_terrain_apply() -> void:
	if _selected_map_id.is_empty():
		return
	var coord := Vector2i(int(_world_hex_q.value), int(_world_hex_r.value))
	var field: String = TERRAIN_FIELDS[_world_terrain_field.selected]
	var opts: Array = TERRAIN_VALUE_OPTIONS.get(field, [""])
	var raw: String = opts[_world_terrain_value_opt.selected] if _world_terrain_value_opt.selected >= 0 else ""
	var value
	if field == "has_city":
		value = int(raw)
	elif field == "water" and raw == "none":
		value = ""
	else:
		value = raw
	_override_manager.override_hex_terrain(_selected_map_id, coord, field, value, _hex_controller)


func _on_world_terrain_field_changed(idx: int) -> void:
	var field: String = TERRAIN_FIELDS[idx]
	var opts: Array = TERRAIN_VALUE_OPTIONS.get(field, [])
	_world_terrain_value_opt.clear()
	for opt in opts:
		_world_terrain_value_opt.add_item(opt)


func _on_world_fog_reveal_all() -> void:
	if _selected_map_id.is_empty():
		return
	_override_manager.override_fog_reveal_all(_selected_map_id, _hex_controller)


func _on_world_fog_reveal_selected() -> void:
	if _selected_map_id.is_empty():
		return
	var coord := Vector2i(int(_world_hex_q.value), int(_world_hex_r.value))
	_override_manager.override_fog_set_hex(_selected_map_id, coord, "visible", _hex_controller)


func _on_world_fog_hide_all() -> void:
	if _selected_map_id.is_empty():
		return
	_override_manager.override_fog_hide_all(_selected_map_id, _hex_controller)


func _on_world_fog_hex_apply() -> void:
	if _selected_map_id.is_empty():
		return
	var coord := Vector2i(int(_world_hex_q.value), int(_world_hex_r.value))
	_override_manager.override_fog_set_hex(
		_selected_map_id, coord,
		FOG_STATES[_world_fog_hex_state.selected],
		_hex_controller
	)


func _on_world_settlement_place() -> void:
	if _selected_map_id.is_empty() or _world_settlement_name.text.is_empty():
		return
	var coord := Vector2i(int(_world_hex_q.value), int(_world_hex_r.value))
	_override_manager.override_place_settlement(_selected_map_id, coord, _world_settlement_name.text)


func _on_world_dungeon_place() -> void:
	if _selected_map_id.is_empty() or _world_dungeon_name.text.is_empty():
		return
	var coord := Vector2i(int(_world_hex_q.value), int(_world_hex_r.value))
	_override_manager.override_place_dungeon(_selected_map_id, coord, _world_dungeon_name.text)


# ---------------------------------------------------------------------------
# Spawning tab
# ---------------------------------------------------------------------------

func _on_spawn() -> void:
	if _selected_map_id.is_empty() or _spawn_monster_key.text.is_empty():
		return
	var coord := Vector2i(int(_spawn_hex_q.value), int(_spawn_hex_r.value))
	_override_manager.override_spawn_encounter(
		_selected_map_id, coord,
		_spawn_monster_key.text,
		int(_spawn_count.value),
		DISPOSITIONS[_spawn_disposition.selected]
	)


# ---------------------------------------------------------------------------
# Dice tab
# ---------------------------------------------------------------------------

func _refresh_dice_tab() -> void:
	_dice_queue_list.clear()
	for roll_type in GameState.dice_overrides.keys():
		var val: int = GameState.dice_overrides[roll_type]
		_dice_queue_list.add_item("%s = %d" % [roll_type, val])
		_dice_queue_list.set_item_metadata(_dice_queue_list.item_count - 1, roll_type)


func _on_dice_queue() -> void:
	var roll_type: String = ROLL_TYPES[_dice_roll_type.selected]
	var value: int = int(_dice_value.value)
	_override_manager.queue_dice_override(roll_type, value)
	_refresh_dice_tab()


func _on_dice_clear_selected() -> void:
	var selected := _dice_queue_list.get_selected_items()
	if selected.is_empty():
		return
	var roll_type: String = _dice_queue_list.get_item_metadata(selected[0])
	_override_manager.clear_dice_override(roll_type)
	_refresh_dice_tab()


func _on_dice_clear_all() -> void:
	_override_manager.clear_all_dice_overrides()
	_refresh_dice_tab()


func _on_dice_export_log() -> void:
	var path: String = DiceSystem.export_roll_log()
	if path.is_empty():
		push_error("OverridePanel: dice log export failed")
	else:
		print("OverridePanel: roll log exported to %s" % path)


# ---------------------------------------------------------------------------
# Snapshots tab
# ---------------------------------------------------------------------------

func _refresh_snapshots_tab() -> void:
	_snap_list.clear()
	var snaps := _override_manager.list_session_snapshots()
	for s in snaps:
		_snap_list.add_item("%s — %s" % [s.get("label", "?"), s.get("created_at", "")])
		_snap_list.set_item_metadata(_snap_list.item_count - 1, s.get("id", ""))


func _on_snap_save() -> void:
	var label: String = _snap_label.text.strip_edges()
	if label.is_empty():
		label = "Snapshot %s" % Time.get_datetime_string_from_system()
	_override_manager.save_session_snapshot(label)
	_snap_label.text = ""
	_refresh_snapshots_tab()


func _on_snap_restore() -> void:
	var selected := _snap_list.get_selected_items()
	if selected.is_empty():
		return
	_snap_confirm_dialog.dialog_text = "Restore this snapshot? This will overwrite all current game state for this campaign."
	_snap_confirm_dialog.popup_centered()


func _on_snap_restore_confirmed() -> void:
	var selected := _snap_list.get_selected_items()
	if selected.is_empty():
		return
	var snap_id: String = _snap_list.get_item_metadata(selected[0])
	_override_manager.restore_session_snapshot(snap_id)
	_refresh_snapshots_tab()


func _on_snap_delete() -> void:
	var selected := _snap_list.get_selected_items()
	if selected.is_empty():
		return
	var snap_id: String = _snap_list.get_item_metadata(selected[0])
	CampaignRepository.delete_snapshot(snap_id)
	_refresh_snapshots_tab()


# ---------------------------------------------------------------------------
# Log tab
# ---------------------------------------------------------------------------

func _refresh_log_tab() -> void:
	_log_list.clear()
	if GameState.campaign_id.is_empty():
		return
	CampaignRepository.db.query_with_bindings("""
		SELECT override_type, target_id, field_changed, old_value, new_value, applied_at
		FROM override_log
		WHERE campaign_id = ?
		ORDER BY id DESC
		LIMIT 200
	""", [GameState.campaign_id])
	for row in CampaignRepository.db.query_result:
		var entry := "[%s] %s → %s.%s: %s → %s" % [
			row.get("applied_at", ""),
			row.get("override_type", ""),
			row.get("target_id", ""),
			row.get("field_changed", ""),
			row.get("old_value", ""),
			row.get("new_value", ""),
		]
		_log_list.add_item(entry)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Warning dialog
	_warning_dialog = AcceptDialog.new()
	_warning_dialog.title = "Override Mode"
	_warning_dialog.dialog_text = (
		"WARNING: Override mode allows direct modification of game state.\n\n" +
		"Actions taken here may have unintended consequences and may break saves.\n\n" +
		"Use this for development, testing, or correcting LLM errors only.\n\n" +
		"I understand — this may break saves."
	)
	_warning_dialog.ok_button_text = "I Understand"
	_warning_dialog.confirmed.connect(_on_warning_confirmed)
	add_child(_warning_dialog)

	# Restore confirmation dialog
	_snap_confirm_dialog = ConfirmationDialog.new()
	_snap_confirm_dialog.title = "Confirm Restore"
	_snap_confirm_dialog.confirmed.connect(_on_snap_restore_confirmed)
	add_child(_snap_confirm_dialog)

	# Root panel
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(500, 640)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.position = Vector2(-520, -660)
	add_child(_panel)

	var root_vbox := VBoxContainer.new()
	_panel.add_child(root_vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	root_vbox.add_child(title_bar)

	var title_label := Label.new()
	title_label.text = "⚠ OVERRIDE MODE"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(close_btn)

	# Tab container — connect tab_changed AFTER all tabs are built to prevent
	# _refresh_*_tab() from firing before the widget refs are assigned.
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_tab_container)

	_build_characters_tab()
	_build_inventory_tab()
	_build_world_tab()
	_build_spawning_tab()
	_build_dice_tab()
	_build_snapshots_tab()
	_build_log_tab()
	_build_testing_tab()

	_tab_container.tab_changed.connect(_on_tab_changed)


func _build_characters_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Characters"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Select Character"))
	_char_list = ItemList.new()
	_char_list.custom_minimum_size = Vector2(0, 80)
	_char_list.item_selected.connect(_on_char_selected)
	tab.add_child(_char_list)

	tab.add_child(_section_label("Stat Override"))
	var stat_row := HBoxContainer.new()
	tab.add_child(stat_row)
	_char_stat_field = OptionButton.new()
	for f in CHARACTER_STAT_FIELDS:
		_char_stat_field.add_item(f)
	_char_stat_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_row.add_child(_char_stat_field)
	_char_stat_value = SpinBox.new()
	_char_stat_value.min_value = -9999
	_char_stat_value.max_value = 99999
	stat_row.add_child(_char_stat_value)
	_char_stat_apply_btn = Button.new()
	_char_stat_apply_btn.text = "Set"
	_char_stat_apply_btn.pressed.connect(_on_char_stat_apply)
	stat_row.add_child(_char_stat_apply_btn)

	tab.add_child(_section_label("XP Adjustment"))
	var xp_row := HBoxContainer.new()
	tab.add_child(xp_row)
	_char_xp_delta = SpinBox.new()
	_char_xp_delta.min_value = -999999
	_char_xp_delta.max_value = 999999
	_char_xp_delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_row.add_child(_char_xp_delta)
	_char_xp_apply_btn = Button.new()
	_char_xp_apply_btn.text = "Apply ±XP"
	_char_xp_apply_btn.pressed.connect(_on_char_xp_apply)
	xp_row.add_child(_char_xp_apply_btn)

	tab.add_child(_section_label("Conditions"))
	_char_condition_name = LineEdit.new()
	_char_condition_name.placeholder_text = "condition name (e.g. paralysed)"
	tab.add_child(_char_condition_name)
	var cond_row := HBoxContainer.new()
	tab.add_child(cond_row)
	_char_condition_apply_btn = Button.new()
	_char_condition_apply_btn.text = "Apply"
	_char_condition_apply_btn.pressed.connect(_on_char_condition_apply)
	cond_row.add_child(_char_condition_apply_btn)
	_char_condition_remove_btn = Button.new()
	_char_condition_remove_btn.text = "Remove"
	_char_condition_remove_btn.pressed.connect(_on_char_condition_remove)
	cond_row.add_child(_char_condition_remove_btn)

	tab.add_child(_section_label("Status"))
	var dead_row := HBoxContainer.new()
	tab.add_child(dead_row)
	dead_row.add_child(_label("Mark as dead:"))
	_char_dead_toggle = CheckButton.new()
	_char_dead_toggle.toggled.connect(_on_char_dead_toggled)
	dead_row.add_child(_char_dead_toggle)


func _build_inventory_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Inventory"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Select Character"))
	_inv_char_list = ItemList.new()
	_inv_char_list.custom_minimum_size = Vector2(0, 60)
	_inv_char_list.item_selected.connect(_on_inv_char_selected)
	tab.add_child(_inv_char_list)

	tab.add_child(_section_label("Current Items"))
	_inv_item_list = ItemList.new()
	_inv_item_list.custom_minimum_size = Vector2(0, 80)
	tab.add_child(_inv_item_list)
	_inv_remove_btn = Button.new()
	_inv_remove_btn.text = "Remove Selected"
	_inv_remove_btn.pressed.connect(_on_inv_remove)
	tab.add_child(_inv_remove_btn)

	tab.add_child(_section_label("Add Item"))
	_inv_item_key = LineEdit.new()
	_inv_item_key.placeholder_text = "item_key (e.g. sword_normal)"
	tab.add_child(_inv_item_key)
	_inv_item_name = LineEdit.new()
	_inv_item_name.placeholder_text = "Display name"
	tab.add_child(_inv_item_name)
	var add_row := HBoxContainer.new()
	tab.add_child(add_row)
	add_row.add_child(_label("Qty:"))
	_inv_qty = SpinBox.new()
	_inv_qty.min_value = 1
	_inv_qty.max_value = 9999
	_inv_qty.value = 1
	add_row.add_child(_inv_qty)
	add_row.add_child(_label("Enc:"))
	_inv_enc = SpinBox.new()
	_inv_enc.min_value = 0
	_inv_enc.max_value = 999
	add_row.add_child(_inv_enc)
	_inv_slot = OptionButton.new()
	for s in INVENTORY_SLOTS:
		_inv_slot.add_item(s)
	add_row.add_child(_inv_slot)
	_inv_add_btn = Button.new()
	_inv_add_btn.text = "Add"
	_inv_add_btn.pressed.connect(_on_inv_add)
	add_row.add_child(_inv_add_btn)

	tab.add_child(_section_label("Gold Adjustment"))
	var gold_row := HBoxContainer.new()
	tab.add_child(gold_row)
	_inv_gold_delta = SpinBox.new()
	_inv_gold_delta.min_value = -999999
	_inv_gold_delta.max_value = 999999
	_inv_gold_delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(_inv_gold_delta)
	_inv_gold_apply_btn = Button.new()
	_inv_gold_apply_btn.text = "Apply ±GP"
	_inv_gold_apply_btn.pressed.connect(_on_inv_gold_apply)
	gold_row.add_child(_inv_gold_apply_btn)


func _build_world_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "World"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Target Hex (q, r)"))
	var hex_row := HBoxContainer.new()
	tab.add_child(hex_row)
	hex_row.add_child(_label("q:"))
	_world_hex_q = SpinBox.new()
	_world_hex_q.min_value = -999
	_world_hex_q.max_value = 999
	hex_row.add_child(_world_hex_q)
	hex_row.add_child(_label("r:"))
	_world_hex_r = SpinBox.new()
	_world_hex_r.min_value = -999
	_world_hex_r.max_value = 999
	hex_row.add_child(_world_hex_r)

	tab.add_child(_section_label("Terrain Override"))
	var terrain_row := HBoxContainer.new()
	tab.add_child(terrain_row)
	_world_terrain_field = OptionButton.new()
	for f in TERRAIN_FIELDS:
		_world_terrain_field.add_item(f)
	_world_terrain_field.item_selected.connect(_on_world_terrain_field_changed)
	terrain_row.add_child(_world_terrain_field)
	_world_terrain_value_opt = OptionButton.new()
	_world_terrain_value_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_row.add_child(_world_terrain_value_opt)
	_world_terrain_apply_btn = Button.new()
	_world_terrain_apply_btn.text = "Set"
	_world_terrain_apply_btn.pressed.connect(_on_world_terrain_apply)
	terrain_row.add_child(_world_terrain_apply_btn)
	# Populate value dropdown for initial field selection
	_on_world_terrain_field_changed(0)

	tab.add_child(_section_label("Fog of War"))
	var fog_bulk_row := HBoxContainer.new()
	tab.add_child(fog_bulk_row)
	_world_fog_reveal_btn = Button.new()
	_world_fog_reveal_btn.text = "Reveal All"
	_world_fog_reveal_btn.pressed.connect(_on_world_fog_reveal_all)
	fog_bulk_row.add_child(_world_fog_reveal_btn)
	_world_fog_hide_btn = Button.new()
	_world_fog_hide_btn.text = "Hide All"
	_world_fog_hide_btn.pressed.connect(_on_world_fog_hide_all)
	fog_bulk_row.add_child(_world_fog_hide_btn)
	_world_fog_reveal_hex_btn = Button.new()
	_world_fog_reveal_hex_btn.text = "Reveal Target Hex"
	_world_fog_reveal_hex_btn.pressed.connect(_on_world_fog_reveal_selected)
	fog_bulk_row.add_child(_world_fog_reveal_hex_btn)
	var fog_hex_row := HBoxContainer.new()
	tab.add_child(fog_hex_row)
	fog_hex_row.add_child(_label("Set hex fog:"))
	_world_fog_hex_state = OptionButton.new()
	for s in FOG_STATES:
		_world_fog_hex_state.add_item(s)
	fog_hex_row.add_child(_world_fog_hex_state)
	_world_fog_hex_apply_btn = Button.new()
	_world_fog_hex_apply_btn.text = "Apply"
	_world_fog_hex_apply_btn.pressed.connect(_on_world_fog_hex_apply)
	fog_hex_row.add_child(_world_fog_hex_apply_btn)

	tab.add_child(_section_label("Place Settlement (stub)"))
	_world_settlement_name = LineEdit.new()
	_world_settlement_name.placeholder_text = "Settlement name"
	tab.add_child(_world_settlement_name)
	_world_settlement_place_btn = Button.new()
	_world_settlement_place_btn.text = "Place at Target Hex"
	_world_settlement_place_btn.pressed.connect(_on_world_settlement_place)
	tab.add_child(_world_settlement_place_btn)

	tab.add_child(_section_label("Place Dungeon"))
	_world_dungeon_name = LineEdit.new()
	_world_dungeon_name.placeholder_text = "Dungeon name"
	tab.add_child(_world_dungeon_name)
	_world_dungeon_place_btn = Button.new()
	_world_dungeon_place_btn.text = "Place at Target Hex"
	_world_dungeon_place_btn.pressed.connect(_on_world_dungeon_place)
	tab.add_child(_world_dungeon_place_btn)


func _build_spawning_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Spawning"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Spawn Encounter"))

	tab.add_child(_label("Monster key (e.g. orc, giant_spider):"))
	_spawn_monster_key = LineEdit.new()
	_spawn_monster_key.placeholder_text = "monster_group key"
	tab.add_child(_spawn_monster_key)

	var count_row := HBoxContainer.new()
	tab.add_child(count_row)
	count_row.add_child(_label("Count:"))
	_spawn_count = SpinBox.new()
	_spawn_count.min_value = 1
	_spawn_count.max_value = 999
	_spawn_count.value = 1
	count_row.add_child(_spawn_count)

	var disp_row := HBoxContainer.new()
	tab.add_child(disp_row)
	disp_row.add_child(_label("Disposition:"))
	_spawn_disposition = OptionButton.new()
	for d in DISPOSITIONS:
		_spawn_disposition.add_item(d)
	_spawn_disposition.selected = 2  # default: neutral
	disp_row.add_child(_spawn_disposition)

	tab.add_child(_section_label("At Hex (q, r)"))
	var hex_row := HBoxContainer.new()
	tab.add_child(hex_row)
	hex_row.add_child(_label("q:"))
	_spawn_hex_q = SpinBox.new()
	_spawn_hex_q.min_value = -999
	_spawn_hex_q.max_value = 999
	hex_row.add_child(_spawn_hex_q)
	hex_row.add_child(_label("r:"))
	_spawn_hex_r = SpinBox.new()
	_spawn_hex_r.min_value = -999
	_spawn_hex_r.max_value = 999
	hex_row.add_child(_spawn_hex_r)

	_spawn_btn = Button.new()
	_spawn_btn.text = "Spawn Encounter"
	_spawn_btn.pressed.connect(_on_spawn)
	tab.add_child(_spawn_btn)


func _build_dice_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Dice"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Queue Forced Roll"))
	var roll_row := HBoxContainer.new()
	tab.add_child(roll_row)
	_dice_roll_type = OptionButton.new()
	for rt in ROLL_TYPES:
		_dice_roll_type.add_item(rt)
	_dice_roll_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_row.add_child(_dice_roll_type)
	_dice_value = SpinBox.new()
	_dice_value.min_value = 1
	_dice_value.max_value = 99
	_dice_value.value = 1
	roll_row.add_child(_dice_value)
	_dice_queue_btn = Button.new()
	_dice_queue_btn.text = "Queue"
	_dice_queue_btn.pressed.connect(_on_dice_queue)
	roll_row.add_child(_dice_queue_btn)

	tab.add_child(_section_label("Pending Overrides"))
	_dice_queue_list = ItemList.new()
	_dice_queue_list.custom_minimum_size = Vector2(0, 120)
	tab.add_child(_dice_queue_list)

	var dice_btns := HBoxContainer.new()
	tab.add_child(dice_btns)
	var clear_selected_btn := Button.new()
	clear_selected_btn.text = "Cancel Selected"
	clear_selected_btn.pressed.connect(_on_dice_clear_selected)
	dice_btns.add_child(clear_selected_btn)
	_dice_clear_all_btn = Button.new()
	_dice_clear_all_btn.text = "Cancel All"
	_dice_clear_all_btn.pressed.connect(_on_dice_clear_all)
	dice_btns.add_child(_dice_clear_all_btn)

	tab.add_child(_section_label("Roll Log"))
	var export_row := HBoxContainer.new()
	tab.add_child(export_row)
	var export_hint := Label.new()
	export_hint.text = "Export session rolls to user:// as JSON"
	export_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	export_row.add_child(export_hint)
	_dice_export_btn = Button.new()
	_dice_export_btn.text = "Export Log"
	_dice_export_btn.pressed.connect(_on_dice_export_log)
	export_row.add_child(_dice_export_btn)


func _build_snapshots_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Snapshots"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Save Snapshot"))
	_snap_label = LineEdit.new()
	_snap_label.placeholder_text = "Snapshot label (optional)"
	tab.add_child(_snap_label)
	_snap_save_btn = Button.new()
	_snap_save_btn.text = "Save Snapshot"
	_snap_save_btn.pressed.connect(_on_snap_save)
	tab.add_child(_snap_save_btn)

	tab.add_child(_section_label("Saved Snapshots (max 10)"))
	_snap_list = ItemList.new()
	_snap_list.custom_minimum_size = Vector2(0, 150)
	tab.add_child(_snap_list)

	var snap_btns := HBoxContainer.new()
	tab.add_child(snap_btns)
	_snap_restore_btn = Button.new()
	_snap_restore_btn.text = "Restore Selected"
	_snap_restore_btn.pressed.connect(_on_snap_restore)
	snap_btns.add_child(_snap_restore_btn)
	_snap_delete_btn = Button.new()
	_snap_delete_btn.text = "Delete Selected"
	_snap_delete_btn.pressed.connect(_on_snap_delete)
	snap_btns.add_child(_snap_delete_btn)


func _build_log_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Log"
	_tab_container.add_child(tab)

	_log_list = ItemList.new()
	_log_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(_log_list)

	_log_refresh_btn = Button.new()
	_log_refresh_btn.text = "Refresh"
	_log_refresh_btn.pressed.connect(_refresh_log_tab)
	tab.add_child(_log_refresh_btn)


func _build_testing_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Testing"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Screen Launchers"))

	_test_char_create_btn = Button.new()
	_test_char_create_btn.text = "Open Character Creation"
	_test_char_create_btn.pressed.connect(_on_test_char_create_pressed)
	tab.add_child(_test_char_create_btn)

	_test_dice_btn = Button.new()
	_test_dice_btn.text = "Test Dice Prompt  (1d20+2 attack throw)"
	_test_dice_btn.pressed.connect(_on_test_dice_pressed)
	tab.add_child(_test_dice_btn)

	tab.add_child(HSeparator.new())

	_test_hint_label = Label.new()
	_test_hint_label.text = "Hotkeys: F5 = Character Creation    F6 = Dice Prompt"
	_test_hint_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	_test_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(_test_hint_label)


# ---------------------------------------------------------------------------
# Testing tab handlers
# ---------------------------------------------------------------------------

func _on_test_char_create_pressed() -> void:
	EventBus.dev_character_creation_requested.emit()


func _on_test_dice_pressed() -> void:
	EventBus.dev_dice_test_requested.emit({
		"roll_type":   "attack_throw",
		"sides":       20,
		"count":       1,
		"modifier":    2,
		"description": "Test Attack Throw (dev)",
	})


func _connect_signals() -> void:
	EventBus.override_applied.connect(_on_override_applied)


func _on_override_applied(_type: String, _target: String, _field: String) -> void:
	# Auto-refresh the log count in the tab label (not a full refresh — too slow)
	pass  # Full refresh happens on tab switch


# ---------------------------------------------------------------------------
# UI helper factories
# ---------------------------------------------------------------------------

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = "— %s —" % text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


func _label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl
