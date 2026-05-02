# LootDistributionModal — presents loot from combat/containers for distribution.
#
# Dependencies:
#   - CampaignRepository (autoload): list_xp_eligible_entities, add_coins_cp
#   - GameState (autoload): active_party_id / party_id
#   - PartyWallet (autoload): deposit_to_character
#   - EventBus (autoload): notification_requested
#   - LootAutoDistributor (local instance): item auto-distribution
#   - GoldShareModal (lazily created child): gold share weight editing
#   - Currency (preloaded): coins_to_cp, format_cost, format_wealth
#   - EquipmentCatalog (local instance): item metadata for auto-distributor
#
# No class_name — lazily instantiated by InventoryTabPage.
#
# Design note:
#   v1 is coins-only. The item queue will be empty after combat because monsters
#   have no inventory drops. The item distribution UI is scaffolded for future
#   container loot and commission overflow. Gold is distributed via manual
#   per-character deposit (bypassing PartyWallet.deposit_to_party_by_shares
#   which filters out henchmen).

extends CanvasLayer

const Currency := preload("res://engine/subsystems/commerce/currency.gd")
const EquipCatalogScript := preload("res://engine/subsystems/characters/equipment_catalog.gd")
const GoldShareModalScript := preload("res://scenes/ui/party_inventory/gold_share_modal.gd")
const LootGenerator := preload("res://engine/subsystems/combat/loot_generator.gd")

## Emitted after the player applies loot distribution.
## cache_id: the source cache (empty for combat loot). cache_cell: voxel cell
## position for has_ground_items cleanup (Vector3i(-1,-1,-1) for non-cache sources).
signal distribution_completed(cache_id: String, cache_cell: Vector3i)

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _panel: PanelContainer
var _is_built: bool = false

# Loot payload
var _coins: Dictionary = {}        # {coins_cp, coins_sp, coins_ep, coins_gp, coins_pp}
var _items: Array = []             # Array of item dicts (empty in v1)
var _encounter_title: String = ""

# Gold share state
var _gold_shares: Dictionary = {}  # {char_id: float_weight} — empty = even split
var _gold_share_modal = null       # GoldShareModal (lazily created)

# Cache source state (set when opened from a dungeon cache; empty for combat loot)
var _cache_id: String = ""
var _cache_cell: Vector3i = Vector3i(-1, -1, -1)
var _item_pickers: Array = []  # per-item {item: Dictionary, picker: OptionButton}

# UI references
var _title_label: Label
var _gold_summary_label: Label
var _share_preview_label: Label
var _items_container: VBoxContainer
var _items_empty_label: Label
var _apply_btn: Button


func _ready() -> void:
	layer = 52
	visible = false


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Opens the modal with loot data from combat or container.
## coins: {coins_cp, coins_sp, coins_ep, coins_gp, coins_pp}
## items: Array of item dicts (empty in v1 for combat loot)
## title: Display title for the encounter
func open(title: String, coins: Dictionary, items: Array = []) -> void:
	_encounter_title = title
	_coins = coins.duplicate()
	_items = items.duplicate()
	_gold_shares.clear()
	_cache_id = ""
	_cache_cell = Vector3i(-1, -1, -1)

	if not _is_built:
		_build_ui()

	_update_display()
	visible = true


## Opens the modal from a dungeon location cache. Loads items from the DB,
## separates coins from non-coin items, and presents them for distribution.
func open_from_cache(cache_id: String, cell: Vector3i = Vector3i(-1, -1, -1)) -> void:
	_cache_id = cache_id
	_cache_cell = cell

	var items: Array = CampaignRepository.list_items_in_cache(cache_id)
	var coins := {}
	var non_coin_items: Array = []

	for item in items:
		var item_key: String = item.get("item_key", "")
		if Currency.is_coin(item_key):
			coins[item_key] = coins.get(item_key, 0) + int(item.get("quantity", 0))
		else:
			non_coin_items.append(item)

	open("Loot", coins, non_coin_items)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_is_built = true

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 0.1
	_panel.anchor_bottom = 0.9
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.08, 0.95)
	style.border_color = Color(0.46, 0.33, 0.19, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	# Title row with close button
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = "LOOT FOUND"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(_on_close_pressed)
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	# Gold summary
	var gold_header := Label.new()
	gold_header.text = "Gold"
	gold_header.add_theme_font_size_override("font_size", 14)
	gold_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.6))
	vbox.add_child(gold_header)

	_gold_summary_label = Label.new()
	_gold_summary_label.text = ""
	_gold_summary_label.add_theme_font_size_override("font_size", 12)
	_gold_summary_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	_gold_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_gold_summary_label)

	# Share preview
	_share_preview_label = Label.new()
	_share_preview_label.text = ""
	_share_preview_label.add_theme_font_size_override("font_size", 11)
	_share_preview_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	_share_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_share_preview_label)

	vbox.add_child(HSeparator.new())

	# Items section
	var items_header := Label.new()
	items_header.text = "Items"
	items_header.add_theme_font_size_override("font_size", 14)
	items_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.6))
	vbox.add_child(items_header)

	var items_scroll := ScrollContainer.new()
	items_scroll.custom_minimum_size.y = 180
	items_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(items_scroll)

	_items_container = VBoxContainer.new()
	_items_container.add_theme_constant_override("separation", 4)
	_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_scroll.add_child(_items_container)

	_items_empty_label = Label.new()
	_items_empty_label.text = "No items to distribute."
	_items_empty_label.add_theme_font_size_override("font_size", 11)
	_items_empty_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	_items_container.add_child(_items_empty_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	vbox.add_child(HSeparator.new())

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var edit_shares_btn := Button.new()
	edit_shares_btn.text = "Edit Gold Shares"
	edit_shares_btn.add_theme_font_size_override("font_size", 12)
	edit_shares_btn.pressed.connect(_on_edit_gold_shares)
	btn_row.add_child(edit_shares_btn)

	var drop_btn := Button.new()
	drop_btn.text = "Drop All"
	drop_btn.add_theme_font_size_override("font_size", 12)
	drop_btn.pressed.connect(_on_drop_all)
	btn_row.add_child(drop_btn)

	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_spacer)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(cancel_btn)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.add_theme_font_size_override("font_size", 12)
	_apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(_apply_btn)


# ---------------------------------------------------------------------------
# Display update
# ---------------------------------------------------------------------------

func _update_display() -> void:
	if not _is_built:
		return

	# Title
	if _encounter_title.is_empty():
		_title_label.text = "LOOT FOUND"
	else:
		_title_label.text = "LOOT FOUND — %s" % _encounter_title

	# Gold summary
	var total_cp := Currency.coins_to_cp(_coins)
	if total_cp > 0:
		var wealth_str := Currency.format_wealth(_coins)
		var gp_equiv := total_cp / 100.0
		_gold_summary_label.text = "%s (%.2f GP equivalent)" % [wealth_str, gp_equiv]
	else:
		_gold_summary_label.text = "No coins found."

	# Share preview
	_update_share_preview()

	# Items — build one row per item with a participant OptionButton.
	_rebuild_item_rows()

	# Enable/disable apply based on whether there's anything to distribute.
	_apply_btn.disabled = (total_cp <= 0 and _items.is_empty())


## Builds the per-item picker rows. Participants are party members whose
## Vector3i position is within Chebyshev <= 1 of _cache_cell. Falls back to the
## full party roster when positions can't be resolved (e.g. combat loot that
## was opened with no cache_cell).
func _rebuild_item_rows() -> void:
	if _items_container == null:
		return
	for child in _items_container.get_children():
		child.queue_free()
	_item_pickers.clear()

	if _items.is_empty():
		_items_empty_label = Label.new()
		_items_empty_label.text = "No items to distribute."
		_items_empty_label.add_theme_font_size_override("font_size", 11)
		_items_empty_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
		_items_container.add_child(_items_empty_label)
		return

	var participants := _compute_participants()
	if participants.is_empty():
		var warn := Label.new()
		warn.text = "No party members in range of this cache."
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
		_items_container.add_child(warn)
		_apply_btn.disabled = true
		return

	for item in _items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_items_container.add_child(row)

		var qty: int = item.get("quantity", 1)
		var name: String = str(item.get("name", item.get("item_key", "?")))
		var label := Label.new()
		label.text = ("%dx %s" % [qty, name]) if qty > 1 else name
		label.add_theme_font_size_override("font_size", 11)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var picker := OptionButton.new()
		picker.add_theme_font_size_override("font_size", 11)
		for i in participants.size():
			var p: Dictionary = participants[i]
			var suffix := " (H)" if p.get("is_henchman", false) else ""
			picker.add_item("%s%s" % [p.get("name", "Unknown"), suffix], i)
			picker.set_item_metadata(i, str(p.get("id", "")))
		row.add_child(picker)

		_item_pickers.append({"item": item, "picker": picker})


## Returns participants: array of {id, name, is_henchman} for party members
## whose current voxel position is within Chebyshev <= 1 of _cache_cell.
## When positions aren't available (wilderness combat loot, cache_cell=sentinel,
## or no dungeon controller in the scene), returns the full party as a fallback.
func _compute_participants() -> Array:
	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id
	var all_chars: Array = CampaignRepository.list_party_characters(party_id)

	# Fallback path: no cell filter.
	if _cache_cell == Vector3i(-1, -1, -1):
		return _chars_to_participants(all_chars)

	var controller = get_tree().get_root().find_child("DungeonMapController", true, false)
	if controller == null:
		return _chars_to_participants(all_chars)

	var filtered: Array = []
	for c in all_chars:
		var cid: String = str(c.get("id", ""))
		var pos: Vector3i = controller.get_entity_pos_3d(cid)
		if pos == Vector3i(-1, -1, -1):
			continue
		if VoxelGrid.chebyshev_distance(pos, _cache_cell) <= 1:
			filtered.append(c)
	return _chars_to_participants(filtered)


func _chars_to_participants(chars: Array) -> Array:
	var result: Array = []
	for c in chars:
		result.append({
			"id": str(c.get("id", "")),
			"name": str(c.get("name", "Unknown")),
			"is_henchman": str(c.get("character_type", "pc")) == "henchman",
		})
	return result


func _update_share_preview() -> void:
	var total_cp := Currency.coins_to_cp(_coins)
	if total_cp <= 0:
		_share_preview_label.text = ""
		return

	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id

	# Build effective shares: custom weights or default even split.
	var effective_shares: Dictionary
	if not _gold_shares.is_empty():
		effective_shares = _gold_shares
	else:
		effective_shares = _build_default_shares(party_id)

	if effective_shares.is_empty():
		_share_preview_label.text = "No eligible recipients in party."
		return

	var computed := GoldShareModalScript.compute_shares(total_cp, effective_shares)
	if computed.is_empty():
		_share_preview_label.text = "No eligible recipients."
		return

	# Build preview text.
	var lines: Array = []
	var share_mode := "custom shares" if not _gold_shares.is_empty() else "even split"
	lines.append("Distribution (%s):" % share_mode)
	for char_id in computed:
		var char_data := CampaignRepository.get_character(char_id)
		var char_name: String = str(char_data.get("name", "Unknown"))
		var char_type: String = str(char_data.get("character_type", "pc"))
		var suffix := " (H)" if char_type == "henchman" else ""
		var amount_cp: int = computed[char_id]
		lines.append("  %s%s: %s" % [char_name, suffix, Currency.format_cost(amount_cp)])
	_share_preview_label.text = "\n".join(lines)


## Builds default share weights: PCs = 1.0, henchmen = 0.5.
func _build_default_shares(party_id: String) -> Dictionary:
	var entities: Array = CampaignRepository.list_xp_eligible_entities(party_id)
	var shares := {}
	for e in entities:
		var char_id: String = str(e.get("id", ""))
		var char_type: String = str(e.get("character_type", "pc"))
		shares[char_id] = 1.0 if char_type == "pc" else 0.5
	return shares


# ---------------------------------------------------------------------------
# Gold share modal
# ---------------------------------------------------------------------------

func _on_edit_gold_shares() -> void:
	var total_cp := Currency.coins_to_cp(_coins)
	if total_cp <= 0:
		EventBus.notification_requested.emit({
			"message": "No coins to distribute.",
			"type": "info",
		})
		return

	_ensure_gold_share_modal()
	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id
	_gold_share_modal.open(total_cp, party_id)


func _ensure_gold_share_modal() -> void:
	if _gold_share_modal != null:
		return
	_gold_share_modal = GoldShareModalScript.new()
	_gold_share_modal.shares_confirmed.connect(_on_shares_confirmed)
	_gold_share_modal.cancelled.connect(func(): pass)  # No action needed on cancel
	add_child(_gold_share_modal)


func _on_shares_confirmed(shares: Dictionary) -> void:
	_gold_shares = shares.duplicate()
	_update_share_preview()


# ---------------------------------------------------------------------------
# Apply distribution
# ---------------------------------------------------------------------------

func _on_apply() -> void:
	var total_cp := Currency.coins_to_cp(_coins)

	# Distribute gold.
	if total_cp > 0:
		var party_id: String = GameState.active_party_id
		if party_id.is_empty():
			party_id = GameState.party_id

		var effective_shares: Dictionary
		if not _gold_shares.is_empty():
			effective_shares = _gold_shares
		else:
			effective_shares = _build_default_shares(party_id)

		var computed := GoldShareModalScript.compute_shares(total_cp, effective_shares)
		for char_id in computed:
			var amount: int = computed[char_id]
			if amount > 0:
				PartyWallet.deposit_to_character(char_id, amount)

	# Distribute items to selected participants. Items in a cache go through
	# LocationCacheManager.pick_up_item so the cache bookkeeping stays clean.
	# Items without a source cache (combat auto-gen loot, commissions) write a
	# fresh inventory_items row owned by the target.
	for entry in _item_pickers:
		var item: Dictionary = entry["item"]
		var picker: OptionButton = entry["picker"]
		if picker.selected < 0:
			continue
		var target_id: String = str(picker.get_item_metadata(picker.selected))
		if target_id.is_empty():
			continue
		var existing_id: String = str(item.get("id", ""))
		if not existing_id.is_empty() and not _cache_id.is_empty():
			LocationCacheManager.pick_up_item(existing_id, target_id, "character")
		elif not existing_id.is_empty():
			CampaignRepository.transfer_item_to_character(existing_id, target_id)
		else:
			var payload: Dictionary = item.duplicate()
			payload["character_id"] = target_id
			CampaignRepository.add_inventory_item(payload)

	# If opened from a cache, remove distributed coin items from the cache DB.
	if not _cache_id.is_empty():
		var cache_items: Array = CampaignRepository.list_items_in_cache(_cache_id)
		for item in cache_items:
			if Currency.is_coin(item.get("item_key", "")):
				CampaignRepository.remove_inventory_item(item.get("id", ""))

	# Award treasure XP for recovered coins.
	# ACKS RAW: 1 XP per 1 GP of coins, gems, jewelry recovered on adventures.
	# Equipment is excluded. v1: coins-only.
	var treasure_gp := LootGenerator.compute_treasure_gp_value(_coins)
	if treasure_gp > 0:
		_award_treasure_xp(treasure_gp)

	visible = false
	EventBus.notification_requested.emit({
		"message": "Loot distributed successfully.",
		"type": "info",
	})
	distribution_completed.emit(_cache_id, _cache_cell)


# ---------------------------------------------------------------------------
# Drop all / Close
# ---------------------------------------------------------------------------

func _on_drop_all() -> void:
	# Drop all loot — coins are lost, items would go to location cache.
	# For v1 (coins-only), just close without distributing.
	visible = false
	EventBus.notification_requested.emit({
		"message": "Loot dropped on the ground.",
		"type": "warning",
	})
	distribution_completed.emit(_cache_id, _cache_cell)


func _on_close_pressed() -> void:
	var total_cp := Currency.coins_to_cp(_coins)
	if total_cp > 0 or not _items.is_empty():
		# Undistributed loot — warn but allow close.
		# In a future version this could show a confirmation dialog.
		EventBus.notification_requested.emit({
			"message": "Loot not yet distributed. Re-open from combat log to distribute later.",
			"type": "warning",
		})
	visible = false


# ---------------------------------------------------------------------------
# Treasure XP
# ---------------------------------------------------------------------------

## Awards treasure XP to all eligible party members.
## ACKS RAW: 1 XP per 1 GP of recovered coins, gems, jewelry, or special treasure.
## Equipment is excluded until a sell-for-XP system exists.
func _award_treasure_xp(treasure_gp: int) -> void:
	if treasure_gp <= 0:
		return

	var party_id: String = GameState.active_party_id
	if party_id.is_empty():
		party_id = GameState.party_id

	var eligible := CampaignRepository.list_xp_eligible_entities(party_id)
	if eligible.is_empty():
		return

	# Build members array matching XPAwardCalculator format.
	var members: Array = []
	for row in eligible:
		var cid: String = row.get("id", "")
		var char_dict: Dictionary = CampaignRepository.get_character(cid)
		if char_dict.is_empty():
			continue
		var cd: CharacterData = CharacterData.from_dict(char_dict)
		members.append({
			"character_id": cid,
			"is_henchman": cd.character_type == "henchman",
			"xp_adjustment_percent": cd.xp_adjustment_percent,
			"character_data": cd,
		})

	if members.is_empty():
		return

	var class_registry := ClassRegistry.new()
	var calculator := XPAwardCalculator.new(class_registry)
	var xp_results: Array = calculator.award_adventure_xp(0, treasure_gp, members)

	for xp_entry in xp_results:
		var cid: String = xp_entry["character_id"]
		var clamped: int = xp_entry["clamped_share"]
		# Persist XP to database.
		var cd: CharacterData = null
		for m in members:
			if m["character_id"] == cid:
				cd = m["character_data"]
				break
		if cd != null:
			cd.xp = xp_entry["xp_after"]
			CampaignRepository.save_character(cd.to_dict())
		EventBus.xp_awarded.emit(cid, clamped)
		if xp_entry.get("leveled_up", false):
			EventBus.character_leveled_up.emit(cid, (cd.level + 1) if cd != null else 0)
