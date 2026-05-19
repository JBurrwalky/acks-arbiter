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
var _selected_entity_kind := "character"  # "character" or "creature"
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
var _spawn_monster_key: OptionButton
var _spawn_count: SpinBox
var _spawn_disposition: OptionButton
var _spawn_hex_q: SpinBox
var _spawn_hex_r: SpinBox
var _spawn_btn: Button
var _spawn_status: Label
var _monster_registry: MonsterRegistry = null

# Per-tab node refs (Spawning tab — cache section)
var _cache_variant_dropdown: OptionButton
var _cache_inputs_container: VBoxContainer
var _cache_create_button: Button
var _cache_status_label: Label
var _cache_input_widgets: Dictionary = {}

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

# Per-tab node refs (Timekeeping tab)
var _time_clock_label: Label
var _time_years_spin: SpinBox
var _time_months_spin: SpinBox
var _time_days_spin: SpinBox
var _time_hours_spin: SpinBox
var _time_minutes_spin: SpinBox
var _time_turns_spin: SpinBox
var _time_rounds_spin: SpinBox

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
	"loyalty_score", "wage_cp_per_month",
]

const TERRAIN_FIELDS := ["elevation", "biome", "water", "civilization", "has_city"]

const TERRAIN_VALUE_OPTIONS := {
	"elevation":    ["flat", "hills", "mountains"],
	"biome":        ["clear", "woods", "jungle", "swamp", "desert"],
	"water":        ["none", "ocean", "lake"],
	"civilization": ["civilized", "borderlands", "wilderness"],
	"has_city":     ["0", "1"],
}

const INVENTORY_SLOTS := ["pack", "hands_main", "hands_off", "body", "head", "belt", "mount"]

const DISPOSITIONS := ["hostile", "unfriendly", "neutral", "indifferent", "friendly"]

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
		8: _refresh_timekeeping_tab()


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
		var ctype: String = m.get("character_type", "pc")
		var label_suffix := ""
		match ctype:
			"henchman": label_suffix = "Hireling"
			"npc":      label_suffix = "NPC"
			_:          label_suffix = m.get("character_class", "?")
		_char_list.add_item("%s — %s L%d" % [
			m.get("name", "?"),
			label_suffix,
			m.get("level", 1)
		])
		_char_list.set_item_metadata(_char_list.item_count - 1, {
			"kind": "character",
			"id": m.get("id", ""),
		})

	var creatures := CampaignRepository.get_trained_creatures_for_party(GameState.party_id)
	for c in creatures:
		_char_list.add_item("%s — Animal (%s)" % [
			c.get("name", "?"),
			c.get("species_id", "?"),
		])
		_char_list.set_item_metadata(_char_list.item_count - 1, {
			"kind": "creature",
			"id": c.get("id", ""),
		})


func _on_char_selected(idx: int) -> void:
	var meta = _char_list.get_item_metadata(idx)
	if meta is Dictionary:
		_selected_character_id = meta.get("id", "")
		_selected_entity_kind = meta.get("kind", "character")
	else:
		_selected_character_id = str(meta)
		_selected_entity_kind = "character"


func _on_char_stat_apply() -> void:
	if _selected_character_id.is_empty():
		return
	var field: String = CHARACTER_STAT_FIELDS[_char_stat_field.selected]
	var value: int = int(_char_stat_value.value)
	if _selected_entity_kind == "creature":
		if field not in OverrideManager.TRAINED_CREATURE_STAT_FIELDS:
			push_warning("OverridePanel: field '%s' not settable on trained creatures (only %s)" % [
				field, OverrideManager.TRAINED_CREATURE_STAT_FIELDS
			])
			return
		_override_manager.override_trained_creature_stat(_selected_character_id, field, value)
	else:
		_override_manager.override_character_stat(_selected_character_id, field, value)


func _on_char_xp_apply() -> void:
	if _selected_character_id.is_empty() or _selected_entity_kind != "character":
		return
	_override_manager.override_character_xp(_selected_character_id, int(_char_xp_delta.value))


func _on_char_condition_apply() -> void:
	if _selected_character_id.is_empty() or _selected_entity_kind != "character" or _char_condition_name.text.is_empty():
		return
	_override_manager.override_character_condition(_selected_character_id, _char_condition_name.text, true)


func _on_char_condition_remove() -> void:
	if _selected_character_id.is_empty() or _selected_entity_kind != "character" or _char_condition_name.text.is_empty():
		return
	_override_manager.override_character_condition(_selected_character_id, _char_condition_name.text, false)


func _on_char_dead_toggled(pressed: bool) -> void:
	if _selected_character_id.is_empty() or _selected_entity_kind != "character":
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
	if _selected_map_id.is_empty() or _spawn_monster_key.item_count == 0:
		return
	var monster_id: String = _spawn_monster_key.get_item_text(_spawn_monster_key.selected)
	if monster_id.is_empty():
		return
	var coord := Vector2i(int(_spawn_hex_q.value), int(_spawn_hex_r.value))
	var count := int(_spawn_count.value)
	var disposition: String = DISPOSITIONS[_spawn_disposition.selected]
	_override_manager.override_spawn_encounter(
		_selected_map_id, coord, monster_id, count, disposition
	)
	_spawn_status.text = "Spawned %d x %s (%s) at (%d, %d)" % [
		count, monster_id, disposition, coord.x, coord.y]


# ---------------------------------------------------------------------------
# Cache section (within Spawning tab)
# ---------------------------------------------------------------------------

func _on_cache_variant_changed(index: int) -> void:
	_rebuild_cache_inputs(index)


func _rebuild_cache_inputs(variant_index: int) -> void:
	for child in _cache_inputs_container.get_children():
		child.queue_free()
	_cache_input_widgets.clear()

	match variant_index:
		0, 1:  # Wilderness loose / hidden — need hex Q/R
			var q_row := HBoxContainer.new()
			_cache_inputs_container.add_child(q_row)
			q_row.add_child(_label("Hex Q:"))
			var q_spin := SpinBox.new()
			q_spin.min_value = -999
			q_spin.max_value = 999
			q_row.add_child(q_spin)
			_cache_input_widgets["hex_q"] = q_spin

			var r_row := HBoxContainer.new()
			_cache_inputs_container.add_child(r_row)
			r_row.add_child(_label("Hex R:"))
			var r_spin := SpinBox.new()
			r_spin.min_value = -999
			r_spin.max_value = 999
			r_row.add_child(r_spin)
			_cache_input_widgets["hex_r"] = r_spin

			_try_fill_cache_from_party_hex()

		2:  # Dungeon loose — dungeon_id dropdown + cell col/row
			var dung_row := HBoxContainer.new()
			_cache_inputs_container.add_child(dung_row)
			dung_row.add_child(_label("Dungeon:"))
			var dung_drop := OptionButton.new()
			dung_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dung_row.add_child(dung_drop)
			_cache_input_widgets["dungeon_id"] = dung_drop

			# Populate dungeon dropdown
			if not _selected_map_id.is_empty():
				var entrances := CampaignRepository.get_dungeon_entrances_for_map(_selected_map_id)
				for e in entrances:
					dung_drop.add_item(e.get("name", e.get("id", "?")))
					dung_drop.set_item_metadata(dung_drop.item_count - 1, e.get("id", ""))
			if dung_drop.item_count == 0:
				_cache_status_label.text = "No dungeons placed — place one first via World tab"
				_cache_status_label.modulate = Color(1.0, 0.8, 0.5)
				_cache_create_button.disabled = true
			else:
				_cache_create_button.disabled = false
				_cache_status_label.text = ""

			var col_row := HBoxContainer.new()
			_cache_inputs_container.add_child(col_row)
			col_row.add_child(_label("Cell Col:"))
			var col_spin := SpinBox.new()
			col_spin.min_value = 0
			col_spin.max_value = 100
			col_row.add_child(col_spin)
			_cache_input_widgets["cell_col"] = col_spin

			var row_row := HBoxContainer.new()
			_cache_inputs_container.add_child(row_row)
			row_row.add_child(_label("Cell Row:"))
			var row_spin := SpinBox.new()
			row_spin.min_value = 0
			row_spin.max_value = 100
			row_row.add_child(row_spin)
			_cache_input_widgets["cell_row"] = row_spin

			var level_row := HBoxContainer.new()
			_cache_inputs_container.add_child(level_row)
			level_row.add_child(_label("Cell Level:"))
			var level_spin := SpinBox.new()
			level_spin.min_value = 0
			level_spin.max_value = 20
			level_row.add_child(level_spin)
			_cache_input_widgets["cell_level"] = level_spin

		3:  # Settlement — settlement_id dropdown + poi_id text input
			var sett_row := HBoxContainer.new()
			_cache_inputs_container.add_child(sett_row)
			sett_row.add_child(_label("Settlement:"))
			var sett_drop := OptionButton.new()
			sett_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sett_row.add_child(sett_drop)
			_cache_input_widgets["settlement_id"] = sett_drop

			if not _selected_map_id.is_empty():
				var settlements := CampaignRepository.get_settlement_entrances_for_map(_selected_map_id)
				for s in settlements:
					sett_drop.add_item(s.get("name", s.get("id", "?")))
					sett_drop.set_item_metadata(sett_drop.item_count - 1, s.get("id", ""))
			if sett_drop.item_count == 0:
				_cache_status_label.text = "No settlements placed — place one first via World tab"
				_cache_status_label.modulate = Color(1.0, 0.8, 0.5)
				_cache_create_button.disabled = true
			else:
				_cache_create_button.disabled = false
				_cache_status_label.text = ""

			var poi_row := HBoxContainer.new()
			_cache_inputs_container.add_child(poi_row)
			poi_row.add_child(_label("POI ID:"))
			var poi_input := LineEdit.new()
			poi_input.placeholder_text = "e.g. tavern_01, gate_north"
			poi_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			poi_row.add_child(poi_input)
			_cache_input_widgets["poi_id"] = poi_input

	# Re-enable button for wilderness variants (no dropdown dependency)
	if variant_index in [0, 1]:
		_cache_create_button.disabled = false
		_cache_status_label.text = ""
		_cache_status_label.modulate = Color(0.7, 0.9, 0.7)


func _try_fill_cache_from_party_hex() -> void:
	if GameState.party_id.is_empty():
		return
	var party := CampaignRepository.get_party(GameState.party_id)
	if party.is_empty():
		return
	if _cache_input_widgets.has("hex_q"):
		_cache_input_widgets["hex_q"].value = party.get("current_hex_q", 0)
	if _cache_input_widgets.has("hex_r"):
		_cache_input_widgets["hex_r"].value = party.get("current_hex_r", 0)


func _on_cache_create_pressed() -> void:
	if _override_manager == null:
		return
	var variant_idx: int = _cache_variant_dropdown.selected
	var cache_id: String = ""

	match variant_idx:
		0:  # Wilderness loose
			var q: int = int(_cache_input_widgets["hex_q"].value)
			var r: int = int(_cache_input_widgets["hex_r"].value)
			cache_id = _override_manager.override_create_wilderness_loose_cache(q, r)
		1:  # Wilderness hidden
			var q: int = int(_cache_input_widgets["hex_q"].value)
			var r: int = int(_cache_input_widgets["hex_r"].value)
			cache_id = _override_manager.override_create_wilderness_hidden_cache(q, r)
		2:  # Dungeon loose
			var dung_drop: OptionButton = _cache_input_widgets["dungeon_id"]
			if dung_drop.selected < 0:
				return
			var dungeon_id: String = dung_drop.get_item_metadata(dung_drop.selected)
			var col: int = int(_cache_input_widgets["cell_col"].value)
			var row: int = int(_cache_input_widgets["cell_row"].value)
			var level: int = int(_cache_input_widgets["cell_level"].value) if _cache_input_widgets.has("cell_level") else 0
			cache_id = _override_manager.override_create_dungeon_loose_cache(dungeon_id, col, row, level)
		3:  # Settlement
			var sett_drop: OptionButton = _cache_input_widgets["settlement_id"]
			if sett_drop.selected < 0:
				return
			var settlement_id: String = sett_drop.get_item_metadata(sett_drop.selected)
			var poi_id: String = _cache_input_widgets["poi_id"].text.strip_edges()
			if poi_id.is_empty():
				_cache_status_label.text = "POI ID is required"
				_cache_status_label.modulate = Color(1.0, 0.5, 0.5)
				return
			cache_id = _override_manager.override_create_settlement_cache(settlement_id, poi_id)

	if cache_id.is_empty():
		_cache_status_label.text = "Cache creation failed — check console"
		_cache_status_label.modulate = Color(1.0, 0.5, 0.5)
	else:
		_cache_status_label.text = "Created cache %s" % cache_id
		_cache_status_label.modulate = Color(0.7, 0.9, 0.7)


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
	UiSurfaceStyles.apply_framed_window_chrome(_warning_dialog)

	# Restore confirmation dialog
	_snap_confirm_dialog = ConfirmationDialog.new()
	_snap_confirm_dialog.title = "Confirm Restore"
	_snap_confirm_dialog.confirmed.connect(_on_snap_restore_confirmed)
	add_child(_snap_confirm_dialog)
	UiSurfaceStyles.apply_framed_window_chrome(_snap_confirm_dialog)

	# Root panel
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(500, 640)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.position = Vector2(-520, -660)
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 12)
	root_margin.add_theme_constant_override("margin_right", 12)
	root_margin.add_theme_constant_override("margin_top", 12)
	root_margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_margin.add_child(root_vbox)

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
	_build_timekeeping_tab()

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

	tab.add_child(_label("Monster:"))
	_spawn_monster_key = OptionButton.new()
	_populate_monster_dropdown()
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

	_spawn_status = Label.new()
	_spawn_status.text = ""
	tab.add_child(_spawn_status)

	# --- Place Cache section ---
	tab.add_child(HSeparator.new())
	tab.add_child(_section_label("Place Cache"))

	var variant_row := HBoxContainer.new()
	tab.add_child(variant_row)
	variant_row.add_child(_label("Variant:"))
	_cache_variant_dropdown = OptionButton.new()
	_cache_variant_dropdown.add_item("Wilderness — Loose", 0)
	_cache_variant_dropdown.add_item("Wilderness — Hidden", 1)
	_cache_variant_dropdown.add_item("Dungeon — Loose", 2)
	_cache_variant_dropdown.add_item("Settlement — Loose", 3)
	_cache_variant_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cache_variant_dropdown.item_selected.connect(_on_cache_variant_changed)
	variant_row.add_child(_cache_variant_dropdown)

	_cache_inputs_container = VBoxContainer.new()
	tab.add_child(_cache_inputs_container)

	_cache_create_button = Button.new()
	_cache_create_button.text = "Create Cache"
	_cache_create_button.pressed.connect(_on_cache_create_pressed)
	tab.add_child(_cache_create_button)

	_cache_status_label = Label.new()
	_cache_status_label.text = ""
	_cache_status_label.modulate = Color(0.7, 0.9, 0.7)
	tab.add_child(_cache_status_label)

	# Initialize with wilderness loose inputs
	_rebuild_cache_inputs(0)


func _populate_monster_dropdown() -> void:
	_spawn_monster_key.clear()
	if _monster_registry == null:
		_monster_registry = MonsterRegistry.new()
	var ids := _monster_registry.get_all_monster_ids()
	for mid in ids:
		var monster := _monster_registry.get_monster(mid)
		var display_name: String = monster.get("name", mid)
		var variant: String = str(monster.get("variant", "")) if monster.get("variant", null) != null else ""
		if not variant.is_empty():
			display_name = "%s (%s)" % [display_name, variant]
		_spawn_monster_key.add_item(mid)
		_spawn_monster_key.set_item_tooltip(_spawn_monster_key.item_count - 1, display_name)


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
	export_hint.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
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
	_test_hint_label.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
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


func _build_timekeeping_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Timekeeping"
	_tab_container.add_child(tab)

	tab.add_child(_section_label("Current Date & Time"))
	_time_clock_label = Label.new()
	_time_clock_label.text = "(no campaign loaded)"
	_time_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.add_child(_time_clock_label)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_timekeeping_tab)
	tab.add_child(refresh_btn)

	tab.add_child(HSeparator.new())
	tab.add_child(_section_label("Advance Clock"))

	const UNITS := [
		["Years",   "years",   1, 999],
		["Months",  "months",  1, 999],
		["Days",    "days",    1, 9999],
		["Hours",   "hours",   1, 9999],
		["Minutes", "minutes", 1, 9999],
		["Turns",   "turns",   1, 9999],
		["Rounds",  "rounds",  1, 99999],
	]
	var spins := [null, null, null, null, null, null, null]
	for i in UNITS.size():
		var u: Array = UNITS[i]
		var row := HBoxContainer.new()
		tab.add_child(row)
		var lbl := Label.new()
		lbl.text = u[0] + ":"
		lbl.custom_minimum_size = Vector2(60, 0)
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = u[2]
		spin.max_value = u[3]
		spin.value = 1
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spin)
		spins[i] = spin
		var btn := Button.new()
		btn.text = "Advance"
		btn.pressed.connect(_on_time_advance.bind(u[1], spin))
		row.add_child(btn)

	_time_years_spin   = spins[0]
	_time_months_spin  = spins[1]
	_time_days_spin    = spins[2]
	_time_hours_spin   = spins[3]
	_time_minutes_spin = spins[4]
	_time_turns_spin   = spins[5]
	_time_rounds_spin  = spins[6]

	var hint := Label.new()
	hint.text = "Turns = 10 min each.  Rounds = 6 sec each."
	hint.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	hint.add_theme_font_size_override("font_size", 11)
	tab.add_child(hint)


func _refresh_timekeeping_tab() -> void:
	if _time_clock_label == null:
		return
	var d: Dictionary = Timekeeping.get_date()
	_time_clock_label.text = "Year %d, Month %d, Day %d  —  %02d:%02d  (round %d)" % [
		d.get("year", 1), d.get("month", 1), d.get("day", 1),
		d.get("hour", 0), d.get("minute", 0), d.get("round", 0)
	]


func _on_time_advance(unit: String, spin: SpinBox) -> void:
	var n: int = int(spin.value)
	match unit:
		"years":   Timekeeping.advance_days(n * Timekeeping.DAYS_PER_YEAR)
		"months":  Timekeeping.advance_days(n * Timekeeping.DAYS_PER_MONTH)
		"days":    Timekeeping.advance_days(n)
		"hours":   Timekeeping.advance_hours(n)
		"minutes": Timekeeping.advance_minutes(n)
		"turns":   Timekeeping.advance_turns(n)
		"rounds":  Timekeeping.advance_rounds(n)
	_refresh_timekeeping_tab()


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
