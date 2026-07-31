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
#   Gold is distributed via manual per-character deposit (bypassing
#   PartyWallet.deposit_to_party_by_shares which filters out henchmen).
#
#   Item distribution (loot policy — "never silently discard loot"):
#     On open the modal auto-distributes the queued items via LootAutoDistributor
#     and pre-selects each item's recipient picker. Items the distributor can
#     place (crossing an encumbrance band if it must — a band is a soft cap, not
#     a hard limit) are assigned; items that exceed EVERY carrier's raw hard-cap
#     capacity come back `unassigned` (reason "over_capacity"). Those are NEVER
#     silently dropped: the modal raises a visible alert naming them and why, and
#     offers a "Make Room" flow (the player drops other carried gear of their
#     choosing to free capacity, then distribution re-runs so the new loot fits).
#     If the player declines, the loot stays explicitly on the ground / in the
#     source cache with a clear message — never gone, never forced onto the new
#     loot, never over-filling a carrier past its hard cap without the player's
#     say-so.

extends CanvasLayer

const Currency := preload("res://engine/subsystems/commerce/currency.gd")
const EquipCatalogScript := preload("res://engine/subsystems/characters/equipment_catalog.gd")
const GoldShareModalScript := preload("res://scenes/ui/party_inventory/gold_share_modal.gd")
const LootGenerator := preload("res://engine/subsystems/combat/loot_generator.gd")
const LootDistributorScript := preload("res://engine/subsystems/inventory/loot_auto_distributor.gd")

## Sentinel option added to every item picker so the player can explicitly leave
## an item on the ground. Its metadata is the empty string, which the apply loop
## already treats as "do not transfer" (item stays in the cache).
const GROUND_META := ""

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
var _items: Array = []             # Array of non-coin item dicts to distribute
var _encounter_title: String = ""

# Gold share state
var _gold_shares: Dictionary = {}  # {char_id: float_weight} — empty = even split
var _gold_share_modal = null       # GoldShareModal (lazily created)

# Cache source state (set when opened from a dungeon cache; empty for combat loot)
var _cache_id: String = ""
var _cache_cell: Vector3i = Vector3i(-1, -1, -1)
var _item_pickers: Array = []  # per-item {item: Dictionary, picker: OptionButton, label: Label}

# Auto-distribute / loot-policy state
var _catalog = null           # EquipmentCatalog (lazily created)
var _distributor = null       # LootAutoDistributor (lazily created)
var _participants: Array = [] # cached recipient list for the current open()
# item_key/index of loot the last auto-distribute could not place → reason string.
var _unassigned_reasons: Dictionary = {}  # row_index:int -> reason:String

# UI references
var _title_label: Label
var _gold_summary_label: Label
var _share_preview_label: Label
var _items_container: VBoxContainer
var _items_empty_label: Label
var _alert_label: RichTextLabel
var _make_room_btn: Button
var _apply_btn: Button

# Make-room sub-panel (lazily built child overlay)
var _make_room_panel: PanelContainer = null
var _make_room_list: VBoxContainer = null
var _make_room_hint: Label = null
var _make_room_checks: Array = []  # per-row {item_id, carrier_id, checkbox}
var _ground_confirm: ConfirmationDialog = null


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
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
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
	vbox.add_child(gold_header)

	_gold_summary_label = Label.new()
	_gold_summary_label.text = ""
	_gold_summary_label.add_theme_font_size_override("font_size", 12)
	_gold_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_gold_summary_label)

	# Share preview
	_share_preview_label = Label.new()
	_share_preview_label.text = ""
	_share_preview_label.add_theme_font_size_override("font_size", 11)
	_share_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_share_preview_label)

	vbox.add_child(HSeparator.new())

	# Items section
	var items_header := Label.new()
	items_header.text = "Items"
	items_header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(items_header)

	# Over-capacity alert (hidden unless auto-distribute reports unassigned loot).
	_alert_label = RichTextLabel.new()
	_alert_label.bbcode_enabled = true
	_alert_label.fit_content = true
	_alert_label.scroll_active = false
	_alert_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_label.add_theme_font_size_override("normal_font_size", 12)
	_alert_label.add_theme_color_override("default_color",
		UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
	_alert_label.visible = false
	vbox.add_child(_alert_label)

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

	var auto_btn := Button.new()
	auto_btn.text = "Auto-Distribute"
	auto_btn.add_theme_font_size_override("font_size", 12)
	auto_btn.pressed.connect(_on_auto_distribute_pressed)
	btn_row.add_child(auto_btn)

	_make_room_btn = Button.new()
	_make_room_btn.text = "Make Room…"
	_make_room_btn.add_theme_font_size_override("font_size", 12)
	_make_room_btn.visible = false
	_make_room_btn.pressed.connect(_on_make_room_pressed)
	btn_row.add_child(_make_room_btn)

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
	# Reset per-open loot-policy state; _run_auto_distribute() repopulates it, and
	# the early-return branches below leave the alert hidden.
	_unassigned_reasons.clear()
	if _alert_label != null:
		_alert_label.visible = false
	if _make_room_btn != null:
		_make_room_btn.visible = false

	if _items.is_empty():
		_items_empty_label = Label.new()
		_items_empty_label.text = "No items to distribute."
		_items_empty_label.add_theme_font_size_override("font_size", 11)
		_items_container.add_child(_items_empty_label)
		return

	var participants := _compute_participants()
	_participants = participants
	if participants.is_empty():
		var warn := Label.new()
		warn.text = "No party members in range of this cache."
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color",
			UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
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
		# Explicit "leave on ground" choice (metadata "" → apply skips transfer).
		picker.add_item("— Leave on ground —", participants.size())
		picker.set_item_metadata(participants.size(), GROUND_META)
		row.add_child(picker)

		_item_pickers.append({"item": item, "picker": picker, "label": label})

	# Auto-distribute immediately so the recipient pickers reflect a sane plan and
	# any over-capacity loot is surfaced the moment the modal opens.
	_run_auto_distribute()


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


# ---------------------------------------------------------------------------
# Auto-distribute + loot policy ("never silently discard loot")
# ---------------------------------------------------------------------------

func _ensure_services() -> void:
	if _catalog == null:
		_catalog = EquipCatalogScript.new()
	if _distributor == null:
		_distributor = LootDistributorScript.new(_catalog)


## Runs the auto-distributor over the queued items, pre-selects each item's
## recipient picker from the plan, and surfaces any loot that no carrier can hold
## under its raw hard cap. Called on open and after a make-room pass.
func _run_auto_distribute() -> void:
	_unassigned_reasons.clear()
	if _item_pickers.is_empty() or _participants.is_empty():
		_update_alert()
		return

	_ensure_services()
	var carriers := _build_carriers(_participants)

	# Tag each item with its picker-row index so we can map moves/unassigned back
	# to the exact row (distribute() duplicates items but preserves extra keys).
	var indexed_items: Array = []
	for i in _item_pickers.size():
		var it: Dictionary = _item_pickers[i]["item"].duplicate()
		it["_row_index"] = i
		indexed_items.append(it)

	var plan: Dictionary = _distributor.distribute(indexed_items, carriers)

	# row_index -> assigned carrier_id
	var assign: Dictionary = {}
	for mv in plan.get("moves", []):
		var it: Dictionary = mv.get("item", {})
		assign[int(it.get("_row_index", -1))] = str(mv.get("to_carrier", ""))
	# row_index -> unassigned reason
	for ua in plan.get("unassigned", []):
		_unassigned_reasons[int(ua.get("_row_index", -1))] = str(ua.get("unassigned_reason", ""))

	# Apply the plan to the pickers and flag unplaceable rows.
	for i in _item_pickers.size():
		var entry: Dictionary = _item_pickers[i]
		var picker: OptionButton = entry["picker"]
		var label: Label = entry["label"]
		if assign.has(i):
			_select_picker_by_meta(picker, assign[i])
			label.remove_theme_color_override("font_color")
		else:
			# Unplaceable (over capacity) or coin — leave on ground and highlight.
			_select_picker_by_meta(picker, GROUND_META)
			label.add_theme_color_override("font_color",
				UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)

	_update_alert()


## Builds LootAutoDistributor carrier dicts from the recipient participants,
## reading live encumbrance, strength, and preference tags from the DB.
func _build_carriers(participants: Array) -> Array:
	var carriers: Array = []
	for p in participants:
		var cid: String = str(p.get("id", ""))
		if cid.is_empty():
			continue
		var char_row: Dictionary = CampaignRepository.get_character(cid)
		carriers.append({
			"carrier_id":        cid,
			"carrier_type":      "henchman" if p.get("is_henchman", false) else "pc",
			"current_enc_units": _carried_enc_units(cid),
			"max_enc_units":     20000,
			"preferences":       CampaignRepository.get_character_preferences(cid),
			"equipped_weapons":  [],
			"strength":          int(char_row.get("strength", 10)),
		})
	return carriers


## Sums the encumbrance units currently carried by a character (non-coin items,
## equipped or not — equipped gear still counts against capacity).
func _carried_enc_units(character_id: String) -> int:
	var total: int = 0
	for raw in CampaignRepository.get_inventory_items(character_id):
		if Currency.is_coin(str(raw.get("item_key", ""))):
			continue
		total += int(raw.get("encumbrance_units", 0)) * int(raw.get("quantity", 1))
	return total


## Selects the picker option whose stored metadata equals target_meta.
func _select_picker_by_meta(picker: OptionButton, target_meta: String) -> void:
	for idx in picker.item_count:
		if str(picker.get_item_metadata(idx)) == target_meta:
			picker.select(idx)
			return


## Refreshes the over-capacity alert banner and Make-Room button from the current
## _unassigned_reasons map. Coin exclusions are ignored here (the modal separates
## coins out before distribution, so any unassigned coin is not a loot loss).
func _update_alert() -> void:
	var lines: Array = []
	for i in _item_pickers.size():
		if not _unassigned_reasons.has(i):
			continue
		var reason: String = str(_unassigned_reasons[i])
		if reason == "coin_excluded":
			continue
		var item: Dictionary = _item_pickers[i]["item"]
		var qty: int = item.get("quantity", 1)
		var nm: String = str(item.get("name", item.get("item_key", "?")))
		var label := ("%dx %s" % [qty, nm]) if qty > 1 else nm
		lines.append("  • %s — %s" % [label,
			LootDistributorScript.describe_unassigned_reason(reason)])

	if lines.is_empty():
		if _alert_label != null:
			_alert_label.visible = false
		if _make_room_btn != null:
			_make_room_btn.visible = false
		return

	var header := "[b]⚠ %d loot item%s can't be carried[/b] — %s.\nDrop other gear to make room, or they stay on the ground here (never lost silently)." % [
		lines.size(), "s" if lines.size() != 1 else "",
		"no one has enough carrying capacity"]
	_alert_label.text = header + "\n" + "\n".join(lines)
	_alert_label.visible = true
	_make_room_btn.visible = true


func _on_auto_distribute_pressed() -> void:
	_run_auto_distribute()


# ---------------------------------------------------------------------------
# Make Room — drop carried gear to free capacity, then re-distribute
# ---------------------------------------------------------------------------

func _on_make_room_pressed() -> void:
	_ensure_make_room_panel()
	_populate_make_room_list()
	_make_room_panel.visible = true


func _ensure_make_room_panel() -> void:
	if _make_room_panel != null:
		return
	_make_room_panel = PanelContainer.new()
	_make_room_panel.anchor_left = 0.22
	_make_room_panel.anchor_right = 0.78
	_make_room_panel.anchor_top = 0.15
	_make_room_panel.anchor_bottom = 0.85
	_make_room_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UiSurfaceStyles.apply_framed_window_chrome(_make_room_panel)
	add_child(_make_room_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_make_room_panel.add_child(vb)

	var title := Label.new()
	title.text = "MAKE ROOM"
	title.add_theme_font_size_override("font_size", 15)
	vb.add_child(title)

	_make_room_hint = Label.new()
	_make_room_hint.add_theme_font_size_override("font_size", 11)
	_make_room_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_make_room_hint)

	vb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 240
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	_make_room_list = VBoxContainer.new()
	_make_room_list.add_theme_constant_override("separation", 2)
	_make_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_make_room_list)

	vb.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(row)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.pressed.connect(func(): _make_room_panel.visible = false)
	row.add_child(cancel)

	var confirm := Button.new()
	confirm.text = "Drop Selected & Retry"
	confirm.add_theme_font_size_override("font_size", 12)
	confirm.pressed.connect(_on_make_room_confirm)
	row.add_child(confirm)


func _populate_make_room_list() -> void:
	for child in _make_room_list.get_children():
		child.queue_free()
	_make_room_checks.clear()

	var stuck: Array = []
	for i in _item_pickers.size():
		if _unassigned_reasons.has(i) and str(_unassigned_reasons[i]) != "coin_excluded":
			var it: Dictionary = _item_pickers[i]["item"]
			var q: int = it.get("quantity", 1)
			var nm: String = str(it.get("name", it.get("item_key", "?")))
			stuck.append(("%dx %s" % [q, nm]) if q > 1 else nm)
	_make_room_hint.text = "Can't carry: %s.\nCheck carried gear to drop on the ground here, then retry." % ", ".join(stuck)

	# One checkbox per non-coin, non-equipped carried item across the recipients.
	var any := false
	for p in _participants:
		var cid: String = str(p.get("id", ""))
		var owner: String = str(p.get("name", "Unknown"))
		for raw in CampaignRepository.get_inventory_items(cid):
			var key: String = str(raw.get("item_key", ""))
			if Currency.is_coin(key):
				continue
			var is_eq = raw.get("is_equipped", false)
			var eq_bool: bool = is_eq if is_eq is bool else int(is_eq) == 1
			if eq_bool:
				continue
			any = true
			var cb := CheckBox.new()
			var q: int = int(raw.get("quantity", 1))
			var nm: String = str(raw.get("name", key))
			var enc: int = int(raw.get("encumbrance_units", 0)) * q
			cb.text = "%s%s  —  %s  (%.1f st)" % [
				("%dx " % q) if q > 1 else "", nm, owner, enc / 1000.0]
			cb.add_theme_font_size_override("font_size", 11)
			_make_room_list.add_child(cb)
			_make_room_checks.append({
				"item_id": str(raw.get("id", "")),
				"carrier_id": cid,
				"checkbox": cb,
			})
	if not any:
		var none := Label.new()
		none.text = "No droppable gear — the party is only carrying equipped items."
		none.add_theme_font_size_override("font_size", 11)
		_make_room_list.add_child(none)


func _on_make_room_confirm() -> void:
	var to_drop: Array = []
	for entry in _make_room_checks:
		if entry["checkbox"].button_pressed:
			to_drop.append(entry)
	if to_drop.is_empty():
		EventBus.notification_requested.emit({
			"message": "Check at least one item to drop, or cancel.",
			"type": "info",
		})
		return

	var cache_id := _ensure_ground_cache()
	if cache_id.is_empty():
		EventBus.notification_requested.emit({
			"message": "Couldn't find a spot to drop items here.",
			"type": "warning",
		})
		return

	var dropped := 0
	for entry in to_drop:
		if LocationCacheManager.drop_item_to_cache(
				str(entry["item_id"]), cache_id, str(entry["carrier_id"])):
			dropped += 1

	EventBus.inventory_updated.emit("")
	_make_room_panel.visible = false

	# Recompute capacity and re-distribute the loot into the freed space.
	_run_auto_distribute()

	var remaining := 0
	for i in _item_pickers.size():
		if _unassigned_reasons.has(i) and str(_unassigned_reasons[i]) != "coin_excluded":
			remaining += 1
	if remaining == 0:
		EventBus.notification_requested.emit({
			"message": "Dropped %d item%s — all loot now fits." % [
				dropped, "s" if dropped != 1 else ""],
			"type": "info",
		})
	else:
		EventBus.notification_requested.emit({
			"message": "Dropped %d item%s — %d loot item%s still won't fit." % [
				dropped, "s" if dropped != 1 else "",
				remaining, "s" if remaining != 1 else ""],
			"type": "warning",
		})


## Resolves a ground cache to receive dropped/undistributed items. Uses the
## source cache when the modal was opened from one (dungeon/container), else
## creates a loose cache at the party's current wilderness hex so nothing is
## ever destroyed. Returns "" if no location can be resolved.
func _ensure_ground_cache() -> String:
	if not _cache_id.is_empty():
		return _cache_id
	var loc_key: String = GameState.current_location_key
	var parts := loc_key.split(":")
	if parts.size() >= 2 and parts[1].find(",") >= 0:
		var qr := parts[1].split(",")
		var hex := Vector2i(int(qr[0]), int(qr[1]))
		return LocationCacheManager.create_wilderness_loose_cache(hex)
	return ""


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
	# Loot policy: leaving items on the ground is never silent. If any item is set
	# to "leave on ground", require an explicit confirmation before applying.
	var ground_count := _count_ground_items()
	if ground_count > 0:
		_ensure_ground_confirm()
		_ground_confirm.dialog_text = ("%d loot item%s can't be carried and will be left on the ground here (recoverable). Apply anyway?" % [
			ground_count, "s" if ground_count != 1 else ""])
		_ground_confirm.popup_centered()
		return
	_do_apply()


## Number of loot rows the player has chosen to leave on the ground.
func _count_ground_items() -> int:
	var n := 0
	for entry in _item_pickers:
		var picker: OptionButton = entry["picker"]
		if picker.selected < 0:
			continue
		if str(picker.get_item_metadata(picker.selected)) == GROUND_META:
			n += 1
	return n


func _ensure_ground_confirm() -> void:
	if _ground_confirm != null:
		return
	_ground_confirm = ConfirmationDialog.new()
	_ground_confirm.title = "Leave loot on the ground?"
	_ground_confirm.ok_button_text = "Leave on Ground"
	_ground_confirm.confirmed.connect(_do_apply)
	add_child(_ground_confirm)
	UiSurfaceStyles.apply_vellum_text_theme(_ground_confirm)


func _do_apply() -> void:
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
	var left_on_ground := 0
	for entry in _item_pickers:
		var item: Dictionary = entry["item"]
		var picker: OptionButton = entry["picker"]
		if picker.selected < 0:
			continue
		var target_id: String = str(picker.get_item_metadata(picker.selected))
		var existing_id: String = str(item.get("id", ""))
		if target_id == GROUND_META:
			# Explicitly left on the ground — keep it recoverable, never delete it.
			# Cache-sourced loot already sits in _cache_id (nothing to do). Fresh
			# loot with no source cache is materialized into a ground cache so it
			# is not silently discarded.
			if existing_id.is_empty():
				_ground_fresh_item(item)
			left_on_ground += 1
			continue
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
	var msg := "Loot distributed successfully."
	var msg_type := "info"
	if left_on_ground > 0:
		msg = "Loot distributed — %d item%s left on the ground here (no room)." % [
			left_on_ground, "s" if left_on_ground != 1 else ""]
		msg_type = "warning"
	EventBus.notification_requested.emit({"message": msg, "type": msg_type})
	distribution_completed.emit(_cache_id, _cache_cell)


## Writes a fresh (no-DB-id) loot item into a ground cache so a "leave on ground"
## choice never destroys combat/commission loot that has no source cache.
func _ground_fresh_item(item: Dictionary) -> void:
	var cache_id := _ensure_ground_cache()
	if cache_id.is_empty():
		push_warning("LootDistributionModal: no ground cache for undistributed loot '%s' — left in queue." % str(item.get("item_key", "?")))
		return
	var payload: Dictionary = item.duplicate()
	payload.erase("id")
	var new_id: String = CampaignRepository.add_inventory_item(payload)
	if not new_id.is_empty():
		CampaignRepository.transfer_item_to_cache(new_id, cache_id)


# ---------------------------------------------------------------------------
# Drop all / Close
# ---------------------------------------------------------------------------

func _on_drop_all() -> void:
	# Explicit player choice to abandon the loot on the ground. Cache-sourced items
	# already sit in _cache_id (they stay). Fresh loot with no source cache is
	# grounded into a recoverable cache rather than silently deleted.
	for entry in _item_pickers:
		var item: Dictionary = entry["item"]
		if str(item.get("id", "")).is_empty():
			_ground_fresh_item(item)
	visible = false
	EventBus.notification_requested.emit({
		"message": "Loot left on the ground.",
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
