# PartyInventoryOverlay — primary UI for cross-carrier inventory management
#
# Dependencies:
#   - GameState (autoload): campaign_id, party_id, active_character_id, current_location_key
#   - PartyWallet (autoload): gold aggregation, contributors filter
#   - LocationCacheManager (autoload): cache queries and drop/pickup
#   - CampaignRepository (autoload): DB access for transfers
#   - EventBus (autoload): wallet_changed, cache_created, cache_decayed, cache_raided,
#       inventory_updated, creature_inventory_updated, vehicle_changed — trigger refresh
#   - PartyInventoryTransferValidator (local instance): drop validation
#
# Design note:
#   The overlay is the transfer coordinator: carrier columns emit transfer_requested
#   signals, the overlay validates via PartyInventoryTransferValidator and executes
#   via CampaignRepository. Columns never call CampaignRepository directly.
#
# No class_name — scene-instantiated via party_inventory_overlay.tscn.

extends CanvasLayer

const ValidatorScript := preload("res://engine/subsystems/inventory/party_inventory_transfer_validator.gd")
const EquipCatalogScript := preload("res://engine/subsystems/characters/equipment_catalog.gd")
const CarrierColumnScene := preload("res://scenes/ui/party_inventory/carrier_column.tscn")
const Currency := preload("res://engine/subsystems/commerce/currency.gd")

const FILTER_LABELS := [
	["", "All"],
	["coins", "Coins"],
	["weapons", "Weapons"],
	["armor", "Armor"],
	["ammunition", "Ammunition"],
	["consumables", "Consumables"],
	["light", "Light Sources"],
	["potions", "Potions"],
	["scrolls", "Scrolls"],
	["magic", "Magic Items"],
	["containers", "Containers"],
	["tack", "Tack & Barding"],
	["tools", "Tools & Gear"],
]


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _validator = null  # PartyInventoryTransferValidator
var _catalog = null  # EquipmentCatalog
var _monster_registry = null  # MonsterRegistry

var _columns: Array = []
var _is_visible: bool = false

# UI references
var _panel: PanelContainer
var _filter_dropdown: OptionButton
var _search_field: LineEdit
var _scroll_container: ScrollContainer
var _columns_container: HBoxContainer
var _footer_label: Label
var _auto_distribute_btn: Button
var _close_btn: Button

# Modals (lazily created)
var _prefs_modal = null
var _drop_dialog = null
var _gold_modal = null
var _context_menu = null
var _loot_modal = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 50
	visible = false
	_init_services()
	_build_ui()
	_connect_signals()


func _init_services() -> void:
	_catalog = EquipCatalogScript.new()
	_validator = ValidatorScript.new(_catalog)
	_monster_registry = MonsterRegistry.new()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("party_inventory_toggle"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func toggle() -> void:
	if _is_visible:
		close()
	else:
		open()


func open(filter_key: String = "") -> void:
	if not GameState.is_in_session():
		return
	# Close character sheet if open (both are right-anchored side panels).
	var char_sheet = get_parent().get_node_or_null("CharacterSheetOverlay")
	if char_sheet and char_sheet.visible:
		char_sheet._close()
	_is_visible = true
	visible = true
	_load_columns()
	_update_footer()
	if not filter_key.is_empty():
		for i in range(FILTER_LABELS.size()):
			if FILTER_LABELS[i][0] == filter_key:
				_filter_dropdown.selected = i
				_apply_filter(i)
				break


func close() -> void:
	_is_visible = false
	visible = false


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

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

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(root_vbox)

	# --- Header row ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header)

	var title := Label.new()
	title.text = "PARTY INVENTORY"
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)

	# Filter dropdown
	_filter_dropdown = OptionButton.new()
	_filter_dropdown.add_theme_font_size_override("font_size", 12)
	for pair in FILTER_LABELS:
		_filter_dropdown.add_item(pair[1])
	_filter_dropdown.item_selected.connect(_apply_filter)
	header.add_child(_filter_dropdown)

	# Search field
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search..."
	_search_field.custom_minimum_size.x = 150
	_search_field.add_theme_font_size_override("font_size", 12)
	_search_field.text_changed.connect(_on_search_changed)
	header.add_child(_search_field)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Close button
	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.add_theme_font_size_override("font_size", 14)
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)

	# --- Separator ---
	root_vbox.add_child(HSeparator.new())

	# --- Scroll container for columns ---
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(_scroll_container)

	_columns_container = HBoxContainer.new()
	_columns_container.add_theme_constant_override("separation", 8)
	_columns_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_columns_container)

	# --- Separator ---
	root_vbox.add_child(HSeparator.new())

	# --- Footer ---
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root_vbox.add_child(footer)

	_footer_label = Label.new()
	_footer_label.add_theme_font_size_override("font_size", 13)
	_footer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_footer_label)

	_auto_distribute_btn = Button.new()
	_auto_distribute_btn.text = "Auto-distribute"
	_auto_distribute_btn.add_theme_font_size_override("font_size", 12)
	_auto_distribute_btn.pressed.connect(_on_auto_distribute_pressed)
	footer.add_child(_auto_distribute_btn)


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.wallet_changed.connect(_on_refresh_needed.unbind(1))
	EventBus.inventory_updated.connect(_on_refresh_needed.unbind(1))
	EventBus.creature_inventory_updated.connect(_on_refresh_needed.unbind(1))
	EventBus.vehicle_changed.connect(_on_refresh_needed.unbind(2))
	EventBus.cache_created.connect(_on_refresh_needed.unbind(3))
	EventBus.cache_picked_up.connect(_on_refresh_needed.unbind(3))
	EventBus.active_party_changed.connect(_on_active_party_changed)
	EventBus.cache_dropped.connect(_on_refresh_needed.unbind(3))
	EventBus.cache_decayed.connect(_on_refresh_needed.unbind(2))
	EventBus.cache_raided.connect(_on_refresh_needed.unbind(3))
	EventBus.combat_ended.connect(_on_combat_ended_loot)


func _on_refresh_needed() -> void:
	if not _is_visible:
		return
	_refresh_all_columns()
	_update_footer()


func _on_active_party_changed(_prev: String, _new: String) -> void:
	if _is_visible:
		_load_columns()
		_update_footer()


# ---------------------------------------------------------------------------
# Column management
# ---------------------------------------------------------------------------

func _load_columns() -> void:
	_clear_columns()

	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id
	var active_id: String = GameState.active_character_id

	# 1. PCs (active first)
	var all_chars: Array = CampaignRepository.list_party_characters(party_id)
	var pcs: Array = []
	var henchmen: Array = []
	for c in all_chars:
		var ctype: String = str(c.get("character_type", "pc"))
		if ctype == "pc":
			pcs.append(c)
		elif ctype == "henchman":
			henchmen.append(c)

	# Sort PCs: active first
	pcs.sort_custom(func(a, b):
		var a_id: String = str(a.get("id", ""))
		var b_id: String = str(b.get("id", ""))
		if a_id == active_id:
			return true
		if b_id == active_id:
			return false
		return false
	)

	for pc in pcs:
		var col := _add_column()
		col.setup_character(str(pc.get("id", "")),
				str(pc.get("id", "")) == active_id, "pc")

	# 2. Henchmen
	for h in henchmen:
		var col := _add_column()
		col.setup_character(str(h.get("id", "")), false, "henchman")

	# 3. Creatures
	var creatures: Array = CampaignRepository.get_trained_creatures_for_party(party_id)
	for c_row in creatures:
		var creature := TrainedCreatureData.from_db(c_row)
		creature.inventory = CampaignRepository.get_creature_inventory(creature.id)
		creature.monster_data = _monster_registry.get_monster(creature.species_id)
		var col := _add_column()
		col.setup_creature(creature.id, creature)

	# 4. Vehicles — enrich with parsed hitched creature data for the validator
	var vehicles: Array = CampaignRepository.get_draft_vehicles_for_party(party_id)
	for v_row in vehicles:
		var hitched_json: String = str(v_row.get("hitched_creatures", "[]"))
		var hitched_ids = JSON.parse_string(hitched_json)
		var hitched_creatures_data: Array = []
		if hitched_ids is Array:
			for cid in hitched_ids:
				var c_row := CampaignRepository.get_trained_creature(str(cid))
				if not c_row.is_empty():
					var c := TrainedCreatureData.from_db(c_row)
					c.monster_data = _monster_registry.get_monster(c.species_id)
					hitched_creatures_data.append(c)
		v_row["hitched_creatures_data"] = hitched_creatures_data
		var col := _add_column()
		col.setup_vehicle(str(v_row.get("id", "")), v_row)

	# 5. Cache at current location
	var cache: Dictionary = LocationCacheManager.get_cache_at_location(
			GameState.current_location_key)
	if not cache.is_empty():
		var col := _add_column()
		col.setup_cache(str(cache.get("id", "")), cache)


func _add_column() -> Node:
	var col := CarrierColumnScene.instantiate()
	col.set_services(_validator, _catalog)
	col.transfer_requested.connect(_on_column_transfer_requested)
	col.item_context_menu_requested.connect(_on_item_context_menu)
	col.gold_display_clicked.connect(_on_gold_display_clicked)
	col.prefs_clicked.connect(_on_prefs_clicked)
	col.pick_up_all_clicked.connect(_on_pick_up_all)
	_columns_container.add_child(col)
	_columns.append(col)
	return col


func _clear_columns() -> void:
	for col in _columns:
		col.queue_free()
	_columns.clear()


func _refresh_all_columns() -> void:
	for col in _columns:
		col.refresh()


# ---------------------------------------------------------------------------
# Transfer execution
# ---------------------------------------------------------------------------

func _on_column_transfer_requested(source: Dictionary, target: Dictionary) -> void:
	# Re-validate (column validated on hover, but re-check on drop)
	var item_id: String = str(source.get("item_id", ""))
	# Look up the item data for full validation
	var item_data: Dictionary = _find_item_data(item_id, source)
	if item_data.is_empty():
		_show_toast("Transfer failed \u2014 item not found")
		return

	var ctx := _build_context()
	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item_data)
	if not result.ok:
		_show_toast(result.reason)
		return

	# Check if this is a drop to cache area and no cache exists
	if target.get("carrier_type") == "cache" and str(target.get("carrier_id", "")).is_empty():
		_handle_drop_to_ground(item_id, source)
		return

	var success := _execute_transfer(item_id, source, target)
	if success:
		if not result.warnings.is_empty():
			_show_toast(result.warnings[0])
		# Emit appropriate update signals
		_emit_update_signals(source, target)
		_refresh_all_columns()
		_update_footer()
	else:
		_show_toast("Transfer failed \u2014 check log")


func _execute_transfer(item_id: String, source: Dictionary, target: Dictionary) -> bool:
	var src_type: String = str(source.get("carrier_type", ""))
	var tgt_type: String = str(target.get("carrier_type", ""))
	var tgt_id: String = str(target.get("carrier_id", ""))
	var src_id: String = str(source.get("carrier_id", ""))

	match [src_type, tgt_type]:
		["character", "character"]:
			return CampaignRepository.transfer_item_to_character(item_id, tgt_id)
		["character", "creature"]:
			return CampaignRepository.transfer_item_to_creature(item_id, tgt_id)
		["character", "vehicle"]:
			return CampaignRepository.transfer_item_to_vehicle(item_id, tgt_id)
		["character", "cache"]:
			return LocationCacheManager.drop_item_to_cache(item_id, tgt_id, src_id)
		["creature", "character"]:
			return CampaignRepository.transfer_item_from_creature_to_character(item_id, tgt_id)
		["creature", "creature"]:
			# Intermediate hop: creature -> active character -> target creature
			var active := GameState.active_character_id
			if not CampaignRepository.transfer_item_from_creature_to_character(item_id, active):
				return false
			return CampaignRepository.transfer_item_to_creature(item_id, tgt_id)
		["creature", "vehicle"]:
			var active := GameState.active_character_id
			if not CampaignRepository.transfer_item_from_creature_to_character(item_id, active):
				return false
			return CampaignRepository.transfer_item_to_vehicle(item_id, tgt_id)
		["creature", "cache"]:
			return LocationCacheManager.drop_item_to_cache(item_id, tgt_id, src_id)
		["vehicle", "character"]:
			return CampaignRepository.transfer_item_from_vehicle_to_character(item_id, tgt_id)
		["vehicle", "creature"]:
			var active := GameState.active_character_id
			if not CampaignRepository.transfer_item_from_vehicle_to_character(item_id, active):
				return false
			return CampaignRepository.transfer_item_to_creature(item_id, tgt_id)
		["vehicle", "vehicle"]:
			var active := GameState.active_character_id
			if not CampaignRepository.transfer_item_from_vehicle_to_character(item_id, active):
				return false
			return CampaignRepository.transfer_item_to_vehicle(item_id, tgt_id)
		["vehicle", "cache"]:
			return LocationCacheManager.drop_item_to_cache(item_id, tgt_id, src_id)
		["cache", "character"]:
			return LocationCacheManager.pick_up_item(item_id, tgt_id, "character")
		["cache", "creature"]:
			return LocationCacheManager.pick_up_item(item_id, tgt_id, "creature")
		["cache", "vehicle"]:
			return LocationCacheManager.pick_up_item(item_id, tgt_id, "vehicle")
		_:
			push_error("PartyInventoryOverlay: unsupported transfer %s -> %s" % [src_type, tgt_type])
			return false


func _emit_update_signals(source: Dictionary, target: Dictionary) -> void:
	var src_type: String = str(source.get("carrier_type", ""))
	var tgt_type: String = str(target.get("carrier_type", ""))
	var src_id: String = str(source.get("carrier_id", ""))
	var tgt_id: String = str(target.get("carrier_id", ""))

	if src_type == "character":
		EventBus.inventory_updated.emit(src_id)
	elif src_type == "creature":
		EventBus.creature_inventory_updated.emit(src_id)

	if tgt_type == "character":
		EventBus.inventory_updated.emit(tgt_id)
	elif tgt_type == "creature":
		EventBus.creature_inventory_updated.emit(tgt_id)


# ---------------------------------------------------------------------------
# Drop-to-ground flow
# ---------------------------------------------------------------------------

func _handle_drop_to_ground(item_id: String, source: Dictionary) -> void:
	var location_key: String = GameState.current_location_key

	if location_key.begins_with("hex:"):
		_open_drop_dialog(item_id, source)
	elif location_key.begins_with("dungeon:"):
		_execute_dungeon_drop(item_id, source)
	elif location_key.begins_with("settlement:"):
		_execute_settlement_drop(item_id, source)
	else:
		_show_toast("Cannot drop items in this location")


func _execute_dungeon_drop(item_id: String, source: Dictionary) -> void:
	var loc_key: String = GameState.current_location_key
	# Parse dungeon:ID:cell:X,Y or dungeon:ID:level:N
	var parts := loc_key.split(":")
	var dungeon_id := parts[1] if parts.size() > 1 else ""
	var cell_xy := Vector2i(0, 0)
	if parts.size() >= 5 and parts[2] == "cell":
		var coords: PackedStringArray = parts[3].split(",") if parts.size() > 3 else PackedStringArray()
		if coords.size() >= 2:
			cell_xy = Vector2i(int(coords[0]), int(coords[1]))

	var cache_id := LocationCacheManager.create_dungeon_loose_cache(dungeon_id, cell_xy)
	if cache_id.is_empty():
		_show_toast("Failed to create cache")
		return

	var src_id: String = str(source.get("carrier_id", ""))
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, src_id)
	_emit_update_signals(source, {})
	_load_columns()
	_update_footer()


func _execute_settlement_drop(item_id: String, source: Dictionary) -> void:
	var loc_key: String = GameState.current_location_key
	var parts := loc_key.split(":")
	var settlement_id := parts[1] if parts.size() > 1 else ""
	var poi_id := parts[2] if parts.size() > 2 else "ground"

	var cache_id := LocationCacheManager.create_settlement_cache(settlement_id, poi_id)
	if cache_id.is_empty():
		_show_toast("Failed to create cache")
		return

	var src_id: String = str(source.get("carrier_id", ""))
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, src_id)
	_emit_update_signals(source, {})
	_load_columns()
	_update_footer()


# ---------------------------------------------------------------------------
# Filter / search
# ---------------------------------------------------------------------------

func _apply_filter(index: int) -> void:
	var filter_key: String = FILTER_LABELS[index][0] if index < FILTER_LABELS.size() else ""
	for col in _columns:
		col.set_filter(filter_key)


func _on_search_changed(new_text: String) -> void:
	for col in _columns:
		col.set_search(new_text)


# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------

func _update_footer() -> void:
	if _footer_label == null:
		return
	var pid := GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	var party_gp := PartyWallet.get_party_total_gp_float(pid)
	var rations := _count_rations()
	_footer_label.text = "Party Total: %.2f GP  |  Rations: %d days" % [party_gp, rations]


func _count_rations() -> int:
	var total := 0
	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id
	var chars: Array = CampaignRepository.list_party_characters(party_id)
	for c in chars:
		var items: Array = CampaignRepository.get_inventory_items(str(c.get("id", "")))
		for item in items:
			var key: String = ""
			var qty: int = 1
			if item is Dictionary:
				key = str(item.get("item_key", ""))
				qty = int(item.get("quantity", 1))
			elif item is InventoryItem:
				key = item.item_key
				qty = item.quantity
			if key.begins_with("rations") or key == "iron_rations" or key == "standard_rations":
				total += qty
	return total


# ---------------------------------------------------------------------------
# Modal handlers
# ---------------------------------------------------------------------------

func _on_gold_display_clicked(character_id: String) -> void:
	_ensure_gold_modal()
	_gold_modal.open_for_character(character_id)


func _on_prefs_clicked(character_id: String) -> void:
	_ensure_prefs_modal()
	_prefs_modal.open(character_id)


func _on_pick_up_all(cache_id: String) -> void:
	var items: Array = LocationCacheManager.get_items_in_cache(cache_id)
	var active_id: String = GameState.active_character_id
	for item in items:
		var item_id: String = ""
		if item is Dictionary:
			item_id = str(item.get("id", ""))
		elif item is InventoryItem:
			item_id = item.id
		if not item_id.is_empty():
			LocationCacheManager.pick_up_item(item_id, active_id, "character")
	EventBus.inventory_updated.emit(active_id)
	_load_columns()
	_update_footer()


func _on_item_context_menu(item_id: String, carrier_type: String,
		carrier_id: String, position: Vector2) -> void:
	_ensure_context_menu()
	var item_data := _find_item_by_id(item_id, carrier_type, carrier_id)
	if item_data.is_empty():
		return
	var valid_targets := _compute_valid_targets(item_data,
			{"carrier_type": carrier_type, "carrier_id": carrier_id})
	_context_menu.show_for_item(item_data, carrier_type, carrier_id,
			valid_targets, position)


func _on_auto_distribute_pressed() -> void:
	var distributor := LootAutoDistributor.new(_catalog)
	var items := _gather_distributable_items()
	var carriers := _gather_carrier_info()
	var plan := distributor.distribute(items, carriers, _build_context())

	if plan.moves.is_empty() and plan.unassigned.is_empty():
		EventBus.notification_requested.emit({
			"message": "Nothing to redistribute.",
			"type": "info",
		})
		return

	_show_distribute_preview(plan)


func _open_drop_dialog(item_id: String, source: Dictionary) -> void:
	_ensure_drop_dialog()
	_drop_dialog.open_for_item(item_id, source)


# ---------------------------------------------------------------------------
# Modal lazy creation
# ---------------------------------------------------------------------------

func _ensure_prefs_modal() -> void:
	if _prefs_modal != null:
		return
	var script = load("res://scenes/ui/party_inventory/character_preferences_modal.gd")
	if script == null:
		push_error("PartyInventoryOverlay: could not load character_preferences_modal.gd")
		return
	_prefs_modal = script.new()
	_prefs_modal.preferences_saved.connect(func(_cid, _tags): _refresh_all_columns())
	add_child(_prefs_modal)


func _ensure_drop_dialog() -> void:
	if _drop_dialog != null:
		return
	var script = load("res://scenes/ui/party_inventory/drop_item_dialog.gd")
	if script == null:
		push_error("PartyInventoryOverlay: could not load drop_item_dialog.gd")
		return
	_drop_dialog = script.new()
	_drop_dialog.drop_confirmed.connect(_on_drop_confirmed)
	add_child(_drop_dialog)


func _ensure_gold_modal() -> void:
	if _gold_modal != null:
		return
	var script = load("res://scenes/ui/party_inventory/transfer_gold_modal.gd")
	if script == null:
		push_error("PartyInventoryOverlay: could not load transfer_gold_modal.gd")
		return
	_gold_modal = script.new()
	_gold_modal.gold_transferred.connect(func(_s, _t, _a):
		_refresh_all_columns()
		_update_footer()
	)
	add_child(_gold_modal)


func _ensure_context_menu() -> void:
	if _context_menu != null:
		return
	var script = load("res://scenes/ui/party_inventory/item_context_menu.gd")
	if script == null:
		push_error("PartyInventoryOverlay: could not load item_context_menu.gd")
		return
	_context_menu = script.new()
	_context_menu.send_to_requested.connect(_on_context_send_to)
	_context_menu.drop_requested.connect(_on_context_drop)
	_context_menu.transfer_gold_requested.connect(func(item):
		var char_id: String = str(item.get("character_id", ""))
		if not char_id.is_empty():
			_on_gold_display_clicked(char_id)
	)
	add_child(_context_menu)


func _ensure_loot_modal() -> void:
	if _loot_modal != null:
		return
	var script = load("res://scenes/ui/party_inventory/loot_distribution_modal.gd")
	if script == null:
		push_error("PartyInventoryOverlay: could not load loot_distribution_modal.gd")
		return
	_loot_modal = script.new()
	_loot_modal.distribution_completed.connect(func(_cache_id: String, _cache_cell: Vector2i):
		_refresh_all_columns()
		_update_footer()
	)
	# Add as sibling (child of Main, not child of overlay CanvasLayer).
	get_parent().add_child(_loot_modal)


## Handles combat_ended signal — opens loot modal if outcome contains loot.
## Filtering (wilderness-only, victory-only) is done at emission in CombatController.
func _on_combat_ended_loot(_encounter_id: String, outcome: Dictionary) -> void:
	if not outcome.has("loot"):
		return
	var loot: Dictionary = outcome["loot"]
	if loot.is_empty():
		return
	_ensure_loot_modal()
	_loot_modal.open("Combat Victory", loot)


# ---------------------------------------------------------------------------
# Context menu action handlers
# ---------------------------------------------------------------------------

func _on_context_send_to(item_data: Dictionary, source_carrier_type: String,
		source_carrier_id: String, target_carrier: Dictionary) -> void:
	var item_id: String = str(item_data.get("id", ""))
	var source := {
		"carrier_type": source_carrier_type,
		"carrier_id": source_carrier_id,
		"item_id": item_id,
		"quantity": int(item_data.get("quantity", 1)),
	}
	_on_column_transfer_requested(source, target_carrier)


func _on_context_drop(item_data: Dictionary, source_carrier_type: String,
		source_carrier_id: String) -> void:
	var item_id: String = str(item_data.get("id", ""))
	var source := {
		"carrier_type": source_carrier_type,
		"carrier_id": source_carrier_id,
		"item_id": item_id,
		"quantity": int(item_data.get("quantity", 1)),
	}
	_handle_drop_to_ground(item_id, source)


func _on_drop_confirmed(item_id: String, source: Dictionary, mode: String) -> void:
	var loc_key: String = GameState.current_location_key
	var parts := loc_key.split(":")
	if parts.size() < 2:
		_show_toast("Cannot determine location for drop")
		return
	var q := int(parts[1].split(",")[0]) if parts[1].find(",") >= 0 else 0
	var r := int(parts[1].split(",")[1]) if parts[1].find(",") >= 0 else 0
	var hex_qr := Vector2i(q, r)

	var cache_id: String = ""
	if mode == "hidden":
		var drop_pid := GameState.active_party_id
		if drop_pid.is_empty():
			drop_pid = GameState.party_id
		cache_id = LocationCacheManager.hide_and_memorize_wilderness_cache(hex_qr, drop_pid)
	else:
		cache_id = LocationCacheManager.create_wilderness_loose_cache(hex_qr)

	if cache_id.is_empty():
		_show_toast("Failed to create cache")
		return

	var src_id: String = str(source.get("carrier_id", ""))
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, src_id)
	_emit_update_signals(source, {})
	_load_columns()
	_update_footer()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _build_context() -> Dictionary:
	return {
		"location_key": GameState.current_location_key,
		"is_in_combat": GameState.current_state == GameState.State.COMBAT,
		"active_character_id": GameState.active_character_id,
	}


# ---------------------------------------------------------------------------
# Auto-distribute helpers
# ---------------------------------------------------------------------------

## Gathers all non-coin, non-equipped items from all carriers for redistribution.
func _gather_distributable_items() -> Array:
	var result: Array = []
	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id

	var all_chars: Array = CampaignRepository.list_party_characters(party_id)
	for c in all_chars:
		var char_id: String = str(c.get("id", ""))
		var char_type: String = str(c.get("character_type", "pc"))
		var items: Array = CampaignRepository.get_inventory_items(char_id)
		for item in items:
			var item_key: String = str(item.get("item_key", ""))
			# Skip coins and equipped items.
			if Currency.is_coin(item_key):
				continue
			if int(item.get("is_equipped", 0)) == 1:
				continue
			var catalog_entry: Dictionary = _catalog.get_item(item_key)
			result.append({
				"item_key": item_key,
				"item_id": str(item.get("id", "")),
				"quantity": int(item.get("quantity", 1)),
				"item_category": str(catalog_entry.get("item_category", item.get("item_category", "gear"))),
				"encumbrance_units": int(catalog_entry.get("encumbrance_units", item.get("encumbrance_units", 0))),
				"source_carrier": {"carrier_type": char_type, "carrier_id": char_id},
			})
	return result


## Builds carrier info dicts for the auto-distributor.
func _gather_carrier_info() -> Array:
	var result: Array = []
	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id

	var all_chars: Array = CampaignRepository.list_party_characters(party_id)
	for c in all_chars:
		var char_id: String = str(c.get("id", ""))
		var char_type: String = str(c.get("character_type", "pc"))
		var strength: int = int(c.get("strength", 10))
		var str_mod: int = CharacterData.ability_modifier(strength)

		# Compute current encumbrance.
		var items: Array = CampaignRepository.get_inventory_items(char_id)
		var enc: Dictionary = EncumbranceCalculator.calculate_encumbrance(items)

		# Collect equipped weapon keys.
		var equipped_weapons: Array = []
		for item in items:
			if int(item.get("is_equipped", 0)) == 1:
				var cat: String = str(item.get("item_category", ""))
				var key: String = str(item.get("item_key", ""))
				if cat == "weapon" or key.contains("bow") or key.contains("sling") or key.contains("crossbow"):
					equipped_weapons.append(key)

		# Load preferences.
		var prefs: Array = CampaignRepository.get_character_preferences(char_id)

		result.append({
			"carrier_id": char_id,
			"carrier_type": char_type,
			"current_enc_units": int(enc["total_units"]),
			"max_enc_units": 20000 + (str_mod * 1000),
			"preferences": prefs,
			"equipped_weapons": equipped_weapons,
			"strength": strength,
		})
	return result


## Shows a text confirmation dialog for a proposed auto-distribute plan.
func _show_distribute_preview(plan: Dictionary) -> void:
	var moves: Array = plan.get("moves", [])
	var unassigned: Array = plan.get("unassigned", [])
	var summary: Dictionary = plan.get("summary", {})

	# Build preview text.
	var lines: Array = []
	lines.append("Auto-distribute plan:")
	lines.append("  %d items to move, %d unassigned" % [
		summary.get("moved", 0), summary.get("unassigned_count", 0)])
	lines.append("")

	if not moves.is_empty():
		lines.append("Proposed moves:")
		# Group moves by target carrier for readability.
		var by_target: Dictionary = {}  # carrier_id -> Array of item descriptions
		for move in moves:
			var target_id: String = str(move.get("to_carrier", ""))
			if not by_target.has(target_id):
				by_target[target_id] = []
			var item: Dictionary = move.get("item", {})
			var qty: int = int(item.get("quantity", 1))
			var key: String = str(item.get("item_key", ""))
			var reason: String = str(move.get("reason", ""))
			by_target[target_id].append("  %dx %s (%s)" % [qty, key, reason])
		for target_id in by_target:
			var char_data := CampaignRepository.get_character(target_id)
			var name: String = str(char_data.get("name", target_id))
			lines.append("  -> %s:" % name)
			for desc in by_target[target_id]:
				lines.append("    %s" % desc)

	if not unassigned.is_empty():
		lines.append("")
		lines.append("Unassigned (no valid carrier):")
		for item in unassigned:
			var qty: int = int(item.get("quantity", 1))
			var key: String = str(item.get("item_key", ""))
			lines.append("  %dx %s" % [qty, key])

	# Use AcceptDialog for simple confirm/cancel.
	var dialog := AcceptDialog.new()
	dialog.title = "Auto-distribute Preview"
	dialog.dialog_text = "\n".join(lines)
	dialog.ok_button_text = "Apply"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func():
		_execute_distribute_plan(plan)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(500, 400))


## Executes a confirmed auto-distribute plan by transferring items.
func _execute_distribute_plan(plan: Dictionary) -> void:
	var moves: Array = plan.get("moves", [])
	for move in moves:
		var item: Dictionary = move.get("item", {})
		var item_id: String = str(item.get("item_id", ""))
		var to_carrier_id: String = str(move.get("to_carrier", ""))
		var source: Dictionary = item.get("source_carrier", {})
		var from_carrier_id: String = str(source.get("carrier_id", ""))

		if item_id.is_empty() or to_carrier_id.is_empty():
			continue
		# Skip if already on target carrier.
		if from_carrier_id == to_carrier_id:
			continue

		# Transfer via CampaignRepository — update character_id on inventory_items row.
		CampaignRepository.db.query_with_bindings(
			"UPDATE inventory_items SET character_id = ? WHERE id = ?",
			[to_carrier_id, item_id])

	# Emit inventory_updated for all affected characters.
	var affected_ids: Dictionary = {}
	for move in moves:
		var item: Dictionary = move.get("item", {})
		var source: Dictionary = item.get("source_carrier", {})
		affected_ids[str(source.get("carrier_id", ""))] = true
		affected_ids[str(move.get("to_carrier", ""))] = true
	for char_id in affected_ids:
		if not char_id.is_empty():
			EventBus.inventory_updated.emit(char_id)

	_refresh_all_columns()
	_update_footer()

	var moved_count: int = plan.get("summary", {}).get("moved", 0)
	EventBus.notification_requested.emit({
		"message": "%d item(s) redistributed." % moved_count,
		"type": "info",
	})


func _find_item_data(item_id: String, source: Dictionary) -> Dictionary:
	var src_type: String = str(source.get("carrier_type", ""))
	var src_id: String = str(source.get("carrier_id", ""))
	return _find_item_by_id(item_id, src_type, src_id)


func _find_item_by_id(item_id: String, carrier_type: String, carrier_id: String) -> Dictionary:
	var items: Array = []
	match carrier_type:
		"character":
			items = CampaignRepository.get_inventory_items(carrier_id)
		"creature":
			items = CampaignRepository.get_creature_inventory(carrier_id)
		"vehicle":
			items = CampaignRepository.get_items_in_vehicle(carrier_id)
		"cache":
			items = LocationCacheManager.get_items_in_cache(carrier_id)

	for item in items:
		var id_val: String = ""
		if item is Dictionary:
			id_val = str(item.get("id", ""))
		elif item is InventoryItem:
			id_val = item.id
		if id_val == item_id:
			if item is InventoryItem:
				return {
					"id": item.id, "item_key": item.item_key, "name": item.name,
					"quantity": item.quantity, "encumbrance_units": item.encumbrance_units,
					"slot": item.slot, "is_equipped": item.is_equipped,
					"item_category": item.item_category, "is_magical": item.is_magical,
					"character_id": item.character_id, "creature_id": item.creature_id,
					"vehicle_id": item.vehicle_id, "container_id": item.container_id,
				}
			return item
	return {}


func _compute_valid_targets(item_data: Dictionary, source: Dictionary) -> Array:
	var targets: Array = []
	var ctx := _build_context()

	for col in _columns:
		var info: Dictionary = col.get_carrier_info()
		if info.get("carrier_type") == source.get("carrier_type") \
				and info.get("carrier_id") == source.get("carrier_id"):
			continue  # skip self
		var target := {
			"carrier_type": info.get("carrier_type", ""),
			"carrier_id": info.get("carrier_id", ""),
			"slot": "",
			"data": info.get("data"),
		}
		var result: Dictionary = _validator.validate_transfer(source, target, ctx, item_data)
		targets.append({
			"carrier_type": info.get("carrier_type", ""),
			"carrier_id": info.get("carrier_id", ""),
			"label": col._header_label.text if col._header_label else "Unknown",
			"ok": result.ok,
			"reason": result.reason,
			"data": info.get("data"),
		})

	return targets


func _show_toast(message: String) -> void:
	EventBus.notification_requested.emit({
		"message": message,
		"type": "warning",
	})
