extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Inventory tab — γ.2 migration target. Hosts the cross-carrier party
## inventory grid (Carriers sub-tab) per gdd-inventory-tab.md §4. Replaces
## PartyInventoryOverlay; the carrier column scenes and 5 sub-modals are
## reused unchanged.
##
## Sub-tabs:
##   - Carriers (always visible) — the carrier-column grid + filter / search /
##     footer + Rebalance Load button.
##   - Loot (deferred to follow-up) — gdd-inventory-tab.md §8 specifies a new
##     Loot sub-tab structure that does not yet exist as code. γ.2 keeps the
##     existing combat_ended → LootDistributionModal flow intact; the modal
##     opens on top of the notebook (CanvasLayer at layer 50). Adding the
##     §8 sub-tab is its own scope.
##
## Visibility / pause: the notebook owns these. The page exists across the
## session and refreshes from EventBus signals.
##
## Modal parenting: the page hosts a private CanvasLayer at layer 100 so
## PanelContainer / PopupMenu sub-modals render above the notebook (layer 35)
## but below the system modal range (100-199 per gdd-ui-architecture.md §2.3).
## LootDistributionModal already wraps itself in a CanvasLayer at layer 50;
## it is parented to the scene root the same way the overlay did it.

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

const MODAL_LAYER := 100

const _SCHEDULER_PAUSE_REASON := "party_inventory_open"  # legacy reason kept for compatibility


# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------

var _validator = null  # PartyInventoryTransferValidator
var _catalog = null  # EquipmentCatalog
var _monster_registry: MonsterRegistry = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _columns: Array = []
var _dungeon_controller = null
var _carrier_positions: Dictionary = {}  # carrier_id -> Vector3i
var _adjacent_carrier_ids: Array = []
var _adjacency_refresh_queued: bool = false


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

var _filter_dropdown: OptionButton = null
var _search_field: LineEdit = null
var _scroll_container: ScrollContainer = null
var _columns_container: HBoxContainer = null
var _footer_label: Label = null
var _rebalance_btn: Button = null

var _modal_layer: CanvasLayer = null

# Sub-modals (lazily created)
var _prefs_modal = null
var _drop_dialog = null
var _gold_modal = null
var _context_menu = null
var _loot_modal = null


# ---------------------------------------------------------------------------
# Lifecycle (overrides notebook_tab_page._build_content)
# ---------------------------------------------------------------------------

func _build_content() -> void:
	_init_services()
	_build_ui()
	_connect_signals()
	# Initial population happens once a session is active. If we're built
	# before a campaign loads (e.g., from a test harness), columns stay empty
	# until active_party_changed fires.
	if GameState.is_in_session():
		_load_columns()
		_update_adjacency_view()
		_update_footer()


func _init_services() -> void:
	_catalog = EquipCatalogScript.new()
	_validator = ValidatorScript.new(_catalog)
	_monster_registry = MonsterRegistry.new()


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	# --- Header row ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header)

	var title := Label.new()
	title.text = "PARTY INVENTORY"
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)

	_filter_dropdown = OptionButton.new()
	_filter_dropdown.add_theme_font_size_override("font_size", 12)
	for pair in FILTER_LABELS:
		_filter_dropdown.add_item(pair[1])
	_filter_dropdown.item_selected.connect(_apply_filter)
	header.add_child(_filter_dropdown)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search..."
	_search_field.custom_minimum_size.x = 150
	_search_field.add_theme_font_size_override("font_size", 12)
	_search_field.text_changed.connect(_on_search_changed)
	header.add_child(_search_field)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	root_vbox.add_child(HSeparator.new())

	# --- Carrier columns ---
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(_scroll_container)

	_columns_container = HBoxContainer.new()
	_columns_container.add_theme_constant_override("separation", 8)
	_columns_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_columns_container)

	root_vbox.add_child(HSeparator.new())

	# --- Footer ---
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root_vbox.add_child(footer)

	_footer_label = Label.new()
	_footer_label.add_theme_font_size_override("font_size", 13)
	_footer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_footer_label)

	_rebalance_btn = Button.new()
	_rebalance_btn.text = "Rebalance Load"
	_rebalance_btn.add_theme_font_size_override("font_size", 12)
	_rebalance_btn.tooltip_text = "Equalize encumbrance across PCs/henchmen who can reach each other."
	_rebalance_btn.pressed.connect(_on_rebalance_pressed)
	footer.add_child(_rebalance_btn)

	# Modal layer hosts PanelContainer / PopupMenu sub-modals above the
	# notebook. LootDistributionModal carries its own CanvasLayer and parents
	# itself to the scene root.
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = MODAL_LAYER
	add_child(_modal_layer)


func _connect_signals() -> void:
	EventBus.wallet_changed.connect(_on_refresh_needed.unbind(1))
	EventBus.inventory_updated.connect(_on_refresh_needed.unbind(1))
	EventBus.creature_inventory_updated.connect(_on_refresh_needed.unbind(1))
	EventBus.vehicle_changed.connect(_on_refresh_needed.unbind(2))
	EventBus.cache_created.connect(_on_refresh_needed.unbind(3))
	EventBus.cache_picked_up.connect(_on_refresh_needed.unbind(3))
	EventBus.cache_dropped.connect(_on_refresh_needed.unbind(3))
	EventBus.cache_decayed.connect(_on_refresh_needed.unbind(2))
	EventBus.cache_raided.connect(_on_refresh_needed.unbind(3))
	EventBus.combat_ended.connect(_on_combat_ended_loot)
	EventBus.active_party_changed.connect(_on_active_party_changed)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _on_refresh_needed() -> void:
	_refresh_all_columns()
	_update_adjacency_view()
	_update_footer()


func _on_active_party_changed(_prev: String, _new: String) -> void:
	_load_columns()
	_update_adjacency_view()
	_update_footer()


# ---------------------------------------------------------------------------
# Column management
# ---------------------------------------------------------------------------

func _load_columns() -> void:
	_clear_columns()

	var party_id: String = _resolve_party_id()
	if party_id.is_empty():
		return
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

	# 3. Trained creatures
	for c_row in CampaignRepository.get_trained_creatures_for_party(party_id):
		var creature := TrainedCreatureData.from_db(c_row)
		creature.inventory = CampaignRepository.get_creature_inventory(creature.id)
		creature.monster_data = _monster_registry.get_monster(creature.species_id)
		var col := _add_column()
		col.setup_creature(creature.id, creature)

	# 4. Vehicles
	for v_row in CampaignRepository.get_draft_vehicles_for_party(party_id):
		var hitched_json: String = str(v_row.get("hitched_creatures", "[]"))
		var hitched_ids: Variant = JSON.parse_string(hitched_json)
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
	var item_id: String = str(source.get("item_id", ""))
	var item_data: Dictionary = _find_item_data(item_id, source)
	if item_data.is_empty():
		_show_toast("Transfer failed — item not found")
		return

	var ctx := _build_context()
	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item_data)
	if not result.ok:
		_show_toast(result.reason)
		return

	if target.get("carrier_type") == "cache" and str(target.get("carrier_id", "")).is_empty():
		_handle_drop_to_ground(item_id, source)
		return

	var success := _execute_transfer(item_id, source, target)
	if success:
		if not result.warnings.is_empty():
			_show_toast(result.warnings[0])
		_emit_update_signals(source, target)
		_refresh_all_columns()
		_update_footer()
	else:
		_show_toast("Transfer failed — check log")


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
			push_error("InventoryTabPage: unsupported transfer %s -> %s" % [src_type, tgt_type])
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
	var src_id: String = str(source.get("carrier_id", ""))
	var controller = _resolve_dungeon_controller()

	var dungeon_id: String = ""
	var cell := Vector3i(-1, -1, -1)
	if controller != null:
		dungeon_id = controller.get_dungeon_id()
		cell = controller.get_entity_pos_3d(src_id)

	if cell == Vector3i(-1, -1, -1) or dungeon_id.is_empty():
		var parsed := LocationCacheManager.parse_dungeon_cell_key(
				GameState.current_location_key)
		if not parsed.is_empty():
			dungeon_id = parsed.get("dungeon_id", dungeon_id)
			cell = parsed.get("cell", cell)

	if dungeon_id.is_empty() or cell == Vector3i(-1, -1, -1):
		_show_toast("Cannot resolve drop location")
		return

	var cache_id := LocationCacheManager.create_dungeon_loose_cache(dungeon_id, cell)
	if cache_id.is_empty():
		_show_toast("Failed to create cache")
		return

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
	var pid := _resolve_party_id()
	var party_gp := PartyWallet.get_party_total_gp_float(pid)
	var rations := _count_rations()
	_footer_label.text = "Party Total: %.2f GP  |  Rations: %d days" % [party_gp, rations]


func _count_rations() -> int:
	## Real food-days the party can eat = (foraged surplus + carried rations, in
	## person-days) ÷ humanoid count. Replaces the old item-count that reported a
	## 1-week ration block as "1 day" (gdd-rations-foodstuffs.md BUG, Phase 1).
	var pid: String = _resolve_party_id()
	if pid.is_empty():
		return 0
	var party_data: PartyData = CampaignRepository.load_party_data(pid)
	if party_data == null:
		return 0
	party_data.character_data = []
	for c in CampaignRepository.list_party_characters(pid):
		party_data.character_data.append(CharacterData.from_dict(c))
	var service := ProvisionsService.new(CampaignRepository, _catalog)
	var food_person_days: int = party_data.ration_units + service.carried_food_days(party_data)
	var humanoids: int = ProvisionsLedger.humanoid_count(party_data)
	if humanoids <= 0:
		return food_person_days
	@warning_ignore("integer_division")
	var days: int = food_person_days / humanoids
	return days


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


func _open_drop_dialog(item_id: String, source: Dictionary) -> void:
	_ensure_drop_dialog()
	_drop_dialog.open_for_item(item_id, source)


# ---------------------------------------------------------------------------
# Modal lazy creation — sub-modals parent to _modal_layer (CanvasLayer 100);
# LootDistributionModal carries its own CanvasLayer at layer 50 and parents
# to scene root.
# ---------------------------------------------------------------------------

func _ensure_prefs_modal() -> void:
	if _prefs_modal != null:
		return
	var script = load("res://scenes/ui/party_inventory/character_preferences_modal.gd")
	if script == null:
		push_error("InventoryTabPage: could not load character_preferences_modal.gd")
		return
	_prefs_modal = script.new()
	_prefs_modal.preferences_saved.connect(func(_cid, _tags): _refresh_all_columns())
	_modal_layer.add_child(_prefs_modal)


func _ensure_drop_dialog() -> void:
	if _drop_dialog != null:
		return
	var script = load("res://scenes/ui/party_inventory/drop_item_dialog.gd")
	if script == null:
		push_error("InventoryTabPage: could not load drop_item_dialog.gd")
		return
	_drop_dialog = script.new()
	_drop_dialog.drop_confirmed.connect(_on_drop_confirmed)
	_modal_layer.add_child(_drop_dialog)


func _ensure_gold_modal() -> void:
	if _gold_modal != null:
		return
	var script = load("res://scenes/ui/party_inventory/transfer_gold_modal.gd")
	if script == null:
		push_error("InventoryTabPage: could not load transfer_gold_modal.gd")
		return
	_gold_modal = script.new()
	_gold_modal.gold_transferred.connect(func(_s, _t, _a):
		_refresh_all_columns()
		_update_footer()
	)
	_modal_layer.add_child(_gold_modal)


func _ensure_context_menu() -> void:
	if _context_menu != null:
		return
	var script = load("res://scenes/ui/party_inventory/item_context_menu.gd")
	if script == null:
		push_error("InventoryTabPage: could not load item_context_menu.gd")
		return
	_context_menu = script.new()
	_context_menu.send_to_requested.connect(_on_context_send_to)
	_context_menu.drop_requested.connect(_on_context_drop)
	_context_menu.transfer_gold_requested.connect(func(item):
		var char_id: String = str(item.get("character_id", ""))
		if not char_id.is_empty():
			_on_gold_display_clicked(char_id)
	)
	_context_menu.equip_rejected.connect(func(reason: String):
		_show_toast(reason)
	)
	_modal_layer.add_child(_context_menu)


func _ensure_loot_modal() -> void:
	if _loot_modal != null:
		return
	var script = load("res://scenes/ui/party_inventory/loot_distribution_modal.gd")
	if script == null:
		push_error("InventoryTabPage: could not load loot_distribution_modal.gd")
		return
	_loot_modal = script.new()
	_loot_modal.distribution_completed.connect(func(_cache_id: String, _cache_cell: Vector3i):
		_refresh_all_columns()
		_update_footer()
	)
	# LootDistributionModal already wraps a CanvasLayer at layer 50; parent
	# to scene root so it does not get torn down with the page.
	get_tree().root.add_child(_loot_modal)


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
		cache_id = LocationCacheManager.hide_and_memorize_wilderness_cache(hex_qr, _resolve_party_id())
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

func _resolve_party_id() -> String:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	return pid


func _build_context() -> Dictionary:
	return {
		"location_key":        GameState.current_location_key,
		"is_in_combat":        GameState.current_state == GameState.State.COMBAT,
		"active_character_id": GameState.active_character_id,
		"carrier_positions":   _carrier_positions,
	}


# ---------------------------------------------------------------------------
# Adjacency-filtered view (dungeon dimming)
# ---------------------------------------------------------------------------

func _resolve_dungeon_controller() -> Node:
	if _dungeon_controller != null and is_instance_valid(_dungeon_controller):
		return _dungeon_controller
	if GameState.exploration_context != GameState.ExplorationContext.DUNGEON:
		return null
	var root := get_tree().get_root()
	_dungeon_controller = root.find_child("DungeonMapController", true, false)
	if _dungeon_controller != null:
		if _dungeon_controller.has_signal("party_moved") \
				and not _dungeon_controller.party_moved.is_connected(_on_any_party_moved):
			_dungeon_controller.party_moved.connect(_on_any_party_moved)
		if _dungeon_controller.has_signal("entity_moved") \
				and not _dungeon_controller.entity_moved.is_connected(_on_any_entity_moved):
			_dungeon_controller.entity_moved.connect(_on_any_entity_moved)
	return _dungeon_controller


func _compute_carrier_positions() -> Dictionary:
	var result: Dictionary = {}
	var controller = _resolve_dungeon_controller()
	if controller == null:
		return result

	for col in _columns:
		var info: Dictionary = col.get_carrier_info()
		var ctype: String = str(info.get("carrier_type", ""))
		var cid: String = str(info.get("carrier_id", ""))
		if cid.is_empty():
			continue
		match ctype:
			"character":
				var pos: Vector3i = controller.get_entity_pos_3d(cid)
				if pos != Vector3i(-1, -1, -1):
					result[cid] = pos
			"creature", "vehicle":
				var data = info.get("data")
				var owner_id: String = ""
				if data is TrainedCreatureData:
					owner_id = data.handler_id
				elif data is Dictionary:
					owner_id = str(data.get("handler_id", ""))
				if owner_id.is_empty():
					owner_id = GameState.active_character_id
				if result.has(owner_id):
					result[cid] = result[owner_id]
				else:
					var owner_pos: Vector3i = controller.get_entity_pos_3d(owner_id)
					if owner_pos != Vector3i(-1, -1, -1):
						result[cid] = owner_pos
			"cache":
				var cache_data = info.get("data")
				var loc_key: String = ""
				if cache_data is Dictionary:
					loc_key = str(cache_data.get("location_key", ""))
				var parsed := LocationCacheManager.parse_dungeon_cell_key(loc_key)
				if not parsed.is_empty():
					result[cid] = parsed["cell"]
	return result


func _update_adjacency_view() -> void:
	var anchor_id: String = GameState.active_character_id
	_carrier_positions = _compute_carrier_positions()

	for col in _columns:
		col.set_carrier_positions(_carrier_positions)

	if _carrier_positions.is_empty() or anchor_id.is_empty():
		_adjacent_carrier_ids = []
		for col in _columns:
			col.set_interaction_enabled(true)
		return

	_adjacent_carrier_ids = ValidatorScript.collect_adjacent_carrier_ids(
			anchor_id, _carrier_positions)

	for col in _columns:
		var info: Dictionary = col.get_carrier_info()
		var cid: String = str(info.get("carrier_id", ""))
		var ctype: String = str(info.get("carrier_type", ""))
		if cid == anchor_id:
			col.set_interaction_enabled(true)
			continue
		if cid in _adjacent_carrier_ids:
			col.set_interaction_enabled(true)
		else:
			var reason := "Not adjacent to active character"
			if ctype == "cache":
				reason = "Cache is not adjacent"
			col.set_interaction_enabled(false, reason)


func _queue_adjacency_refresh() -> void:
	if _adjacency_refresh_queued:
		return
	_adjacency_refresh_queued = true
	call_deferred("_flush_adjacency_refresh")


func _flush_adjacency_refresh() -> void:
	_adjacency_refresh_queued = false
	_update_adjacency_view()


func _on_any_entity_moved(_entity_id: String, _from_pos, _to_pos) -> void:
	_queue_adjacency_refresh()


func _on_any_party_moved(_from_pos, _to_pos) -> void:
	_queue_adjacency_refresh()


# ---------------------------------------------------------------------------
# Rebalance Load (gdd-inventory-tab.md §5.6)
# ---------------------------------------------------------------------------

func _on_rebalance_pressed() -> void:
	var in_dungeon: bool = not _carrier_positions.is_empty()
	var anchor_id: String = GameState.active_character_id
	if in_dungeon and anchor_id.is_empty():
		_show_toast("No active character — focus a party member first")
		return

	var cluster_ids: Array = []
	for col in _columns:
		var info: Dictionary = col.get_carrier_info()
		var cid: String = str(info.get("carrier_id", ""))
		var ctype: String = str(info.get("carrier_type", ""))
		if ctype != "character":
			continue
		if in_dungeon:
			if cid == anchor_id or cid in _adjacent_carrier_ids:
				cluster_ids.append(cid)
		else:
			cluster_ids.append(cid)

	if cluster_ids.size() < 2:
		_show_toast("Nobody else in the party to rebalance with" if not in_dungeon
				else "No adjacent party members to rebalance with")
		return

	if anchor_id.is_empty():
		anchor_id = cluster_ids[0]

	var items: Array = []
	var carriers: Array = []
	for cid in cluster_ids:
		var inv: Array = CampaignRepository.get_inventory_items(cid)
		var current_enc: int = 0
		for raw in inv:
			var key: String = str(raw.get("item_key", ""))
			if Currency.is_coin(key):
				continue
			var enc: int = int(raw.get("encumbrance_units", 0)) * int(raw.get("quantity", 1))
			current_enc += enc
			var is_eq = raw.get("is_equipped", false)
			var eq_bool: bool = is_eq if is_eq is bool else int(is_eq) == 1
			if eq_bool:
				continue
			items.append({
				"item_id":           str(raw.get("id", "")),
				"item_key":          key,
				"quantity":          int(raw.get("quantity", 1)),
				"encumbrance_units": int(raw.get("encumbrance_units", 0)),
				"item_category":     str(raw.get("item_category", "")),
				"is_equipped":       false,
				"source_carrier_id": cid,
			})
		var char_row: Dictionary = CampaignRepository.get_character(cid)
		carriers.append({
			"carrier_id":       cid,
			"carrier_type":     "pc" if str(char_row.get("character_type", "pc")) == "pc" else "henchman",
			"current_enc_units": current_enc,
			"max_enc_units":    20000,
			"preferences":      [],
			"equipped_weapons": [],
			"strength":         int(char_row.get("strength", 10)),
		})

	var distributor := LootAutoDistributor.new(_catalog)
	var plan: Dictionary = distributor.redistribute_among_adjacent(items, carriers, anchor_id)
	var moves: Array = plan.get("moves", [])
	if moves.is_empty():
		_show_toast("Nothing to rebalance")
		return

	for move in moves:
		var item: Dictionary = move.get("item", {})
		var item_id: String = str(item.get("item_id", ""))
		var to_cid: String = str(move.get("to_carrier", ""))
		if item_id.is_empty() or to_cid.is_empty():
			continue
		CampaignRepository.transfer_item_to_character(item_id, to_cid)

	EventBus.inventory_updated.emit("")
	_show_toast("Rebalanced %d item%s across %d carriers" % [
			moves.size(), "s" if moves.size() != 1 else "", cluster_ids.size()])


# ---------------------------------------------------------------------------
# Item lookup
# ---------------------------------------------------------------------------

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
			continue
		var target := {
			"carrier_type": info.get("carrier_type", ""),
			"carrier_id":   info.get("carrier_id", ""),
			"slot":         "",
			"data":         info.get("data"),
		}
		var result: Dictionary = _validator.validate_transfer(source, target, ctx, item_data)
		targets.append({
			"carrier_type": info.get("carrier_type", ""),
			"carrier_id":   info.get("carrier_id", ""),
			"label":        col._header_label.text if col._header_label else "Unknown",
			"ok":           result.ok,
			"reason":       result.reason,
			"data":         info.get("data"),
		})
	return targets


func _show_toast(message: String) -> void:
	EventBus.notification_requested.emit({
		"body": message,
		"type": "warning",
	})
