class_name ShopPanel
extends PanelContainer

## Settlement shop panel: buy, sell, commission, and pick up equipment.
##
## Instantiated by SettlementExploreState when the party enters a shop POI.
## Displays available inventory filtered by market class, allows buy/sell
## transactions at full catalog price, and manages commissions.

signal closed

var _service: ShopService = null
var _runner = null  # SessionRunner
var _shop_data: Dictionary = {}
var _inventory: Array = []
var _party_members: Array = []
var _selected_character_id: String = ""
var _current_tab: int = 0  # 0=Buy, 1=Sell, 2=Commission, 3=Pending

# UI nodes
var _title_label: Label
var _wealth_label: Label
var _enc_label: Label
var _char_selector: OptionButton
var _tab_bar: TabBar
var _item_list: VBoxContainer
var _scroll: ScrollContainer
var _close_button: Button
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_update_view()


func setup(shop_data: Dictionary, runner, service: ShopService) -> void:
	_shop_data = shop_data
	_runner = runner
	_service = service
	_inventory = shop_data.get("inventory", [])
	# Load party members for character selector.
	if runner != null:
		var party_id: String = runner.get_party_id()
		var members := CampaignRepository.get_party_members(party_id)
		_party_members = []
		for m in members:
			var char_id: String = m.get("character_id", "")
			var char_row := CampaignRepository.get_character(char_id)
			if not char_row.is_empty():
				_party_members.append(char_row)
		if not _party_members.is_empty():
			_selected_character_id = _party_members[0].get("id", "")


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# When embedded in a parent layout (e.g. SettlementPanel activity area),
	# let the parent control sizing. Otherwise center as a modal.
	if get_parent() is VBoxContainer or get_parent() is HBoxContainer:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 350)
	else:
		# Anchor all four corners at viewport center, then push the offsets
		# out symmetrically so the rect is centered (700×500 around midpoint).
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 0.5
		anchor_bottom = 0.5
		offset_left = -350
		offset_right = 350
		offset_top = -250
		offset_bottom = 250
		custom_minimum_size = Vector2(700, 500)
		# Vellum chrome to match SettlementMenu and other modals
		# (per docs/coding_conventions.md §13.5).
		UiSurfaceStyles.apply_framed_window_chrome(self)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header row: title + character selector.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Shop"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_char_selector = OptionButton.new()
	_char_selector.custom_minimum_size.x = 180
	_char_selector.item_selected.connect(_on_character_selected)
	header.add_child(_char_selector)

	# Wealth and encumbrance row.
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 24)
	vbox.add_child(info_row)

	_wealth_label = Label.new()
	_wealth_label.text = "Wealth: 0cp"
	info_row.add_child(_wealth_label)

	_enc_label = Label.new()
	_enc_label.text = "Enc: 0 stone"
	info_row.add_child(_enc_label)

	# Tab bar: Buy / Sell / Commission / Pending
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Buy")
	_tab_bar.add_tab("Sell")
	_tab_bar.add_tab("Commission")
	_tab_bar.add_tab("Pending Orders")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tab_bar)

	# Scrollable item list.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y = 300
	vbox.add_child(_scroll)

	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_item_list)

	# Status label.
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	# Close button.
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(footer)

	_close_button = Button.new()
	_close_button.text = "Leave Shop"
	_close_button.pressed.connect(func(): closed.emit())
	footer.add_child(_close_button)


# ---------------------------------------------------------------------------
# View updates
# ---------------------------------------------------------------------------

func _update_view() -> void:
	_update_title()
	_update_character_selector()
	_update_wealth_display()
	_update_item_list()


func _update_title() -> void:
	if _title_label == null:
		return
	var poi: Dictionary = _shop_data.get("poi", {})
	var poi_name: String = poi.get("name", "Shop")
	var market_class: int = _shop_data.get("market_class", 6)
	_title_label.text = "%s — Market Class %s" % [poi_name, _roman_numeral(market_class)]


func _update_character_selector() -> void:
	if _char_selector == null:
		return
	_char_selector.clear()
	for i in _party_members.size():
		var name: String = _party_members[i].get("name", "Unknown")
		_char_selector.add_item(name, i)
		if _party_members[i].get("id", "") == _selected_character_id:
			_char_selector.select(i)


func _update_wealth_display() -> void:
	if _wealth_label == null or _selected_character_id.is_empty():
		return
	# Show party wallet total with personal share.
	var party_id: String = _runner.get_party_id() if _runner != null else ""
	if party_id != "":
		var party_total_gp: float = PartyWallet.get_party_total_gp_float(party_id)
		var char_wealth_cp: int = CampaignRepository.get_character_wealth_cp(_selected_character_id)
		_wealth_label.text = "Party: %.2f GP  (Yours: %.2f GP)" % [party_total_gp, char_wealth_cp / 100.0]
	else:
		var coins := CampaignRepository.get_character_coins(_selected_character_id)
		_wealth_label.text = "Wealth: %s" % Currency.format_wealth(coins)

	# Encumbrance.
	var items := CampaignRepository.get_inventory_items(_selected_character_id)
	var total_units := 0
	for item in items:
		total_units += int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	var stone: float = total_units / 1000.0
	_enc_label.text = "Enc: %.1f stone" % stone


func _update_item_list() -> void:
	if _item_list == null:
		return
	# Clear existing rows.
	for child in _item_list.get_children():
		child.queue_free()

	match _current_tab:
		0:
			_populate_buy_tab()
		1:
			_populate_sell_tab()
		2:
			_populate_commission_tab()
		3:
			_populate_pending_tab()


func _populate_buy_tab() -> void:
	if _inventory.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items available at this shop."
		_item_list.add_child(empty_label)
		return

	# Sort by category then name.
	var sorted := _inventory.duplicate()
	sorted.sort_custom(func(a, b):
		var cat_a: String = a.get("item_category", "")
		var cat_b: String = b.get("item_category", "")
		if cat_a != cat_b:
			return cat_a < cat_b
		return a.get("name", "") < b.get("name", "")
	)

	var party_id_buy: String = _runner.get_party_id() if _runner != null else ""
	var wealth_cp: int
	if party_id_buy != "":
		wealth_cp = PartyWallet.get_party_total_cp(party_id_buy)
	else:
		wealth_cp = CampaignRepository.get_character_wealth_cp(_selected_character_id)
	var current_cat := ""

	for item_data in sorted:
		var cat: String = item_data.get("item_category", "gear")
		if cat != current_cat:
			current_cat = cat
			var cat_label := Label.new()
			cat_label.text = "— %s —" % cat.capitalize()
			cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_item_list.add_child(cat_label)

		var qty: int = int(item_data.get("quantity_available", 0))
		if qty <= 0:
			continue

		var row := _create_buy_row(item_data, wealth_cp)
		_item_list.add_child(row)


func _populate_sell_tab() -> void:
	if _service == null or _selected_character_id.is_empty():
		return
	var sellable := _service.get_sellable_items(_selected_character_id)
	if sellable.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items to sell."
		_item_list.add_child(empty_label)
		return

	for item_data in sellable:
		var row := _create_sell_row(item_data)
		_item_list.add_child(row)


func _populate_commission_tab() -> void:
	# Show items that have 0 stock but are in the catalog for this shop.
	var zero_stock: Array[Dictionary] = []
	for item_data in _inventory:
		if int(item_data.get("quantity_available", 0)) <= 0:
			zero_stock.append(item_data)

	# Also include items not generated at all for this shop but in the
	# catalog categories. For now, show only items that were generated
	# with 0 quantity (percentage-chance items that failed the roll).
	if zero_stock.is_empty():
		var empty_label := Label.new()
		empty_label.text = "All items are currently in stock."
		_item_list.add_child(empty_label)
		return

	var party_id_comm: String = _runner.get_party_id() if _runner != null else ""
	var wealth_cp_comm: int
	if party_id_comm != "":
		wealth_cp_comm = PartyWallet.get_party_total_cp(party_id_comm)
	else:
		wealth_cp_comm = CampaignRepository.get_character_wealth_cp(_selected_character_id)
	for item_data in zero_stock:
		var row := _create_commission_row(item_data, wealth_cp_comm)
		_item_list.add_child(row)


func _populate_pending_tab() -> void:
	if _selected_character_id.is_empty():
		return
	var campaign_id: String = _shop_data.get("campaign_id", "")
	var poi_id: String = _shop_data.get("poi", {}).get("id", "")
	var commissions := CampaignRepository.get_commissions(campaign_id, poi_id, _selected_character_id)

	if commissions.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No pending commissions."
		_item_list.add_child(empty_label)
		return

	var current_round: int = 0
	if _runner != null:
		current_round = Timekeeping.get_total_rounds()

	for commission in commissions:
		var row := _create_pending_row(commission, current_round)
		_item_list.add_child(row)


# ---------------------------------------------------------------------------
# Row factories
# ---------------------------------------------------------------------------

func _create_buy_row(item_data: Dictionary, wealth_cp: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = item_data.get("name", "???")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = 200
	row.add_child(name_label)

	var cost_cp: int = int(item_data.get("cost_cp", 0))
	var cost_label := Label.new()
	cost_label.text = Currency.format_cost(cost_cp)
	cost_label.custom_minimum_size.x = 80
	row.add_child(cost_label)

	var enc_units: int = int(item_data.get("encumbrance_units", 0))
	var enc_label := Label.new()
	enc_label.text = "%.1f st" % (enc_units / 1000.0) if enc_units > 0 else "—"
	enc_label.custom_minimum_size.x = 60
	row.add_child(enc_label)

	var qty_label := Label.new()
	qty_label.text = "Qty: %d" % int(item_data.get("quantity_available", 0))
	qty_label.custom_minimum_size.x = 60
	row.add_child(qty_label)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.disabled = wealth_cp < cost_cp
	var item_key: String = item_data.get("item_key", "")
	buy_btn.pressed.connect(_on_buy_pressed.bind(item_key))
	row.add_child(buy_btn)

	return row


func _create_sell_row(item_data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	var qty: int = int(item_data.get("quantity", 1))
	name_label.text = "%s (x%d)" % [item_data.get("name", "???"), qty] if qty > 1 else item_data.get("name", "???")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = 200
	row.add_child(name_label)

	var cost_cp: int = int(item_data.get("cost_cp", 0))
	var cost_label := Label.new()
	cost_label.text = Currency.format_cost(cost_cp)
	cost_label.custom_minimum_size.x = 80
	row.add_child(cost_label)

	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	var item_id: String = item_data.get("item_id", "")
	sell_btn.pressed.connect(_on_sell_pressed.bind(item_id))
	row.add_child(sell_btn)

	return row


func _create_commission_row(item_data: Dictionary, wealth_cp: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = item_data.get("name", "???")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = 200
	row.add_child(name_label)

	var cost_cp: int = int(item_data.get("cost_cp", 0))
	var cost_label := Label.new()
	cost_label.text = Currency.format_cost(cost_cp)
	cost_label.custom_minimum_size.x = 80
	row.add_child(cost_label)

	var order_btn := Button.new()
	order_btn.text = "Commission"
	order_btn.disabled = wealth_cp < cost_cp
	var item_key: String = item_data.get("item_key", "")
	order_btn.pressed.connect(_on_commission_pressed.bind(item_key))
	row.add_child(order_btn)

	return row


func _create_pending_row(commission: Dictionary, current_round: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var item_key: String = commission.get("item_key", "")
	var catalog := EquipmentCatalog.new()
	var catalog_item := catalog.get_item(item_key)
	var item_name: String = catalog_item.get("name", item_key) if not catalog_item.is_empty() else item_key

	var name_label := Label.new()
	var qty: int = int(commission.get("quantity", 1))
	name_label.text = "%s (x%d)" % [item_name, qty] if qty > 1 else item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = 200
	row.add_child(name_label)

	var ready_at: int = int(commission.get("ready_at_round", 0))
	var picked_up: bool = int(commission.get("picked_up", 0)) == 1
	var is_ready: bool = current_round >= ready_at

	var status_label := Label.new()
	if picked_up:
		status_label.text = "Picked up"
	elif is_ready:
		status_label.text = "Ready!"
	else:
		var days_left: int = maxi(1, (ready_at - current_round) / Timekeeping.ROUNDS_PER_DAY)
		status_label.text = "%d day(s) remaining" % days_left
	status_label.custom_minimum_size.x = 120
	row.add_child(status_label)

	if is_ready and not picked_up:
		var pickup_btn := Button.new()
		pickup_btn.text = "Pick Up"
		var commission_id: String = commission.get("id", "")
		pickup_btn.pressed.connect(_on_pickup_pressed.bind(commission_id))
		row.add_child(pickup_btn)

	return row


# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_character_selected(index: int) -> void:
	if index >= 0 and index < _party_members.size():
		_selected_character_id = _party_members[index].get("id", "")
		_update_wealth_display()
		_update_item_list()


func _on_tab_changed(tab_index: int) -> void:
	_current_tab = tab_index
	_update_item_list()


func _on_buy_pressed(item_key: String) -> void:
	if _service == null or _selected_character_id.is_empty():
		return
	var campaign_id: String = _shop_data.get("campaign_id", "")
	var poi_id: String = _shop_data.get("poi", {}).get("id", "")
	var party_id: String = _runner.get_party_id() if _runner != null else ""

	var result := _service.buy_item(_selected_character_id, item_key, 1, poi_id, campaign_id, party_id)
	if result["success"]:
		_status_label.text = "Purchased!"
		# Refresh shop inventory data from DB.
		_refresh_inventory_from_db()
	else:
		_status_label.text = result.get("message", "Purchase failed.")
	_update_wealth_display()
	_update_item_list()


func _on_sell_pressed(item_id: String) -> void:
	if _service == null or _selected_character_id.is_empty():
		return
	var campaign_id: String = _shop_data.get("campaign_id", "")
	var poi_id: String = _shop_data.get("poi", {}).get("id", "")

	var result := _service.sell_item(_selected_character_id, item_id, poi_id, campaign_id)
	if result["success"]:
		_status_label.text = "Sold!"
		_refresh_inventory_from_db()
	else:
		_status_label.text = result.get("message", "Sale failed.")
	_update_wealth_display()
	_update_item_list()


func _on_commission_pressed(item_key: String) -> void:
	if _service == null or _selected_character_id.is_empty() or _runner == null:
		return
	var campaign_id: String = _shop_data.get("campaign_id", "")
	var settlement_id: String = _shop_data.get("settlement_id", "")
	var poi: Dictionary = _shop_data.get("poi", {})
	var scheduler = _runner.get_scheduler()
	var party_id: String = _runner.get_party_id()
	var current_round: int = Timekeeping.get_total_rounds()

	var result := _service.commission_item(
		_selected_character_id, item_key, 1, poi, settlement_id,
		campaign_id, scheduler, party_id, current_round)
	if result["success"]:
		var days: int = maxi(1, (result["ready_at_round"] - current_round) / Timekeeping.ROUNDS_PER_DAY)
		_status_label.text = "Commissioned! Ready in %d day(s)." % days
	else:
		_status_label.text = result.get("message", "Commission failed.")
	_update_wealth_display()
	_update_item_list()


func _on_pickup_pressed(commission_id: String) -> void:
	if _service == null or _selected_character_id.is_empty() or _runner == null:
		return
	var current_round: int = Timekeeping.get_total_rounds()
	var result := _service.pickup_commission(commission_id, _selected_character_id, current_round)
	if result["success"]:
		_status_label.text = "Picked up!"
	else:
		_status_label.text = result.get("message", "Pickup failed.")
	_update_wealth_display()
	_update_item_list()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _refresh_inventory_from_db() -> void:
	var campaign_id: String = _shop_data.get("campaign_id", "")
	var poi_id: String = _shop_data.get("poi", {}).get("id", "")
	var db_rows := CampaignRepository.get_shop_inventory(campaign_id, poi_id)
	var catalog := EquipmentCatalog.new()
	_inventory = []
	for row in db_rows:
		var item_key: String = row.get("item_key", "")
		var catalog_item := catalog.get_item(item_key)
		if catalog_item.is_empty():
			continue
		_inventory.append({
			"item_key": item_key,
			"name": catalog_item.get("name", ""),
			"cost_cp": int(catalog_item.get("cost_cp", 0)),
			"quantity_available": int(row.get("quantity_available", 0)),
			"item_category": catalog_item.get("item_category", ""),
			"encumbrance_units": int(catalog_item.get("encumbrance_units", 0)),
		})


static func _roman_numeral(n: int) -> String:
	match n:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
		6: return "VI"
		_: return str(n)
