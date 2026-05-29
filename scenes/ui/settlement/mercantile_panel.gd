extends CanvasLayer

## Mercantile Panel — Phase 10B.2 Wave 2 (Trade block).
##
## Per gdd-phase-10b-2-trade-block.md §2.4 + §3.5 + §3.6 + coding conventions
## §52 (conditional-section modal pickers). Single picker handles all 5
## mercantile activity kinds via conditional sections:
##   * buy_merchandise (Wave 2 — REAL section)
##   * sell_merchandise (Wave 2 — REAL section)
##   * persuade_merchants (Wave 3 — placeholder section)
##   * solicit_merchants (Wave 3 — placeholder section)
##   * locate_merchandise (Wave 3 — placeholder section)
##   * accept_shipping_contract (Wave 4 — placeholder section)
##
## Modal style matches research_project_picker — CanvasLayer with backdrop +
## centered PanelContainer + footer Cancel/Launch + live preview + validation.
##
## Usage:
##   var picker = preload("res://scenes/ui/settlement/mercantile_panel.gd").new()
##   add_child(picker)
##   picker.setup(activity_id, settlement_id, party_id, character_id)
##   picker.launch_requested.connect(...)
##   picker.cancelled.connect(...)
##
## Emitted signals:
##   launch_requested(activity_def_id: String, params: Dictionary,
##                    location_kind: String, location_ref: String)
##   cancelled
##
## The picker queue_frees itself before emitting the terminal signal so the
## caller can safely open a follow-up modal in the handler.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal launch_requested(activity_def_id: String, params: Dictionary, location_kind: String, location_ref: String)
signal cancelled


# ---------------------------------------------------------------------------
# Display titles per kind
# ---------------------------------------------------------------------------

const ACTIVITY_TITLES: Dictionary = {
	"buy_merchandise":          "Buy Merchandise",
	"sell_merchandise":         "Sell Merchandise",
	"persuade_merchants":       "Persuade Merchants",
	"solicit_merchants":        "Solicit Merchants (3 weeks)",
	"locate_merchandise":       "Locate Merchandise",
	"accept_shipping_contract": "Accept Shipping Contract",
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _kind: String = ""
var _settlement_id: String = ""
var _party_id: String = ""
var _character_id: String = ""

# UI nodes
var _root_panel: PanelContainer = null
var _header_label: Label = null
var _character_selector: OptionButton = null
var _body_vbox: VBoxContainer = null
var _preview_label: Label = null
var _validation_label: Label = null
var _launch_btn: Button = null
var _cancel_btn: Button = null

# Cached field references per section.
var _fields: Dictionary = {}
# Cached metadata for dropdowns (parallel arrays keyed by index → dict).
var _merchant_index: Array = []
var _cargo_index: Array = []
var _carrier_index: Array = []
var _party_members: Array = []
# Phase 10B.2 Wave 3 — persuade / locate use merchandise-type dropdowns.
var _merchandise_index: Array = []
# Phase 10B.2 Wave 4 — shipping section's offers list (Array of offer dicts).
var _offer_index: Array = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 56
	visible = false
	_build_chrome()


func setup(activity_id: String, settlement_id: String, party_id: String, character_id: String) -> void:
	_kind = activity_id
	_settlement_id = settlement_id
	_party_id = party_id
	_character_id = character_id
	_load_party_members()
	visible = true
	_build_body()
	_refresh_preview()


# ---------------------------------------------------------------------------
# Chrome (backdrop + frame + footer)
# ---------------------------------------------------------------------------

func _build_chrome() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(620, 540)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.97)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.5, 1)
	_root_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_root_panel.add_child(outer)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 18)
	outer.add_child(_header_label)

	# Active character selector row.
	var char_row := HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 8)
	outer.add_child(char_row)
	var char_lbl := Label.new()
	char_lbl.text = "Active character:"
	char_row.add_child(char_lbl)
	_character_selector = OptionButton.new()
	_character_selector.custom_minimum_size.x = 220
	_character_selector.item_selected.connect(_on_character_selected)
	char_row.add_child(_character_selector)

	outer.add_child(HSeparator.new())

	# Body — section-specific UI populated by _build_body().
	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 6)
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_body_vbox)

	outer.add_child(HSeparator.new())

	# Live preview.
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(_preview_label)

	# Validation row.
	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.modulate = Color(1, 0.7, 0.5, 1)
	_validation_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(_validation_label)

	# Footer.
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(footer)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	footer.add_child(_cancel_btn)
	_launch_btn = Button.new()
	_launch_btn.text = "Launch"
	_launch_btn.pressed.connect(_on_launch_pressed)
	footer.add_child(_launch_btn)


# ---------------------------------------------------------------------------
# Body — section dispatch
# ---------------------------------------------------------------------------

func _build_body() -> void:
	if _header_label != null:
		_header_label.text = ACTIVITY_TITLES.get(_kind, _kind)

	for child in _body_vbox.get_children():
		_body_vbox.remove_child(child)
		child.queue_free()
	_fields.clear()
	_merchant_index = []
	_cargo_index = []
	_carrier_index = []
	_merchandise_index = []
	_offer_index = []

	_populate_character_selector()

	match _kind:
		"buy_merchandise":
			_build_buy_section(_body_vbox)
		"sell_merchandise":
			_build_sell_section(_body_vbox)
		"persuade_merchants":
			_build_persuade_section(_body_vbox)
		"solicit_merchants":
			_build_solicit_section(_body_vbox)
		"locate_merchandise":
			_build_locate_section(_body_vbox)
		"accept_shipping_contract":
			_build_shipping_contracts_section(_body_vbox)
		_:
			var lbl := Label.new()
			lbl.text = "Unknown mercantile activity: " + _kind
			_body_vbox.add_child(lbl)


# ---------------------------------------------------------------------------
# Active character selector
# ---------------------------------------------------------------------------

func _load_party_members() -> void:
	_party_members = []
	if _party_id.is_empty():
		return
	var members: Array = CampaignRepository.get_party_members(_party_id)
	for m in members:
		var cid: String = String((m as Dictionary).get("character_id", ""))
		if cid.is_empty():
			continue
		var row: Dictionary = CampaignRepository.get_character(cid)
		if not row.is_empty():
			_party_members.append(row)


func _populate_character_selector() -> void:
	if _character_selector == null:
		return
	_character_selector.clear()
	var selected_idx: int = 0
	for i in _party_members.size():
		var row: Dictionary = _party_members[i]
		_character_selector.add_item(str(row.get("name", "Unknown")), i)
		if str(row.get("id", "")) == _character_id:
			selected_idx = i
	if _party_members.size() > 0:
		_character_selector.select(selected_idx)
		_character_id = String(_party_members[selected_idx].get("id", ""))


func _on_character_selected(idx: int) -> void:
	if idx < 0 or idx >= _party_members.size():
		return
	_character_id = String(_party_members[idx].get("id", ""))
	_refresh_preview()


# ---------------------------------------------------------------------------
# Section: buy_merchandise (§3.5)
# ---------------------------------------------------------------------------

func _build_buy_section(parent: VBoxContainer) -> void:
	var current_day: int = Timekeeping.get_total_days()

	# Merchant dropdown.
	var merchant_dd := OptionButton.new()
	_merchant_index = MerchantPoolRepository.list_visible_merchants(_settlement_id, current_day)
	if _merchant_index.is_empty():
		merchant_dd.add_item("(no visible merchants — try Solicit Merchants)")
		merchant_dd.disabled = true
	else:
		for i in _merchant_index.size():
			var m: Dictionary = _merchant_index[i]
			var label: String = "%s — %d loads (%s)" % [
				String(m.get("merchandise_type", "?")),
				int(m.get("loads_available", 0)),
				String(m.get("id", "")).substr(0, 6),
			]
			merchant_dd.add_item(label, i)
	parent.add_child(_form_row("Merchant:", merchant_dd))

	# Loads SpinBox.
	var loads_sp := SpinBox.new()
	loads_sp.min_value = 1
	loads_sp.max_value = 999
	loads_sp.value = 1
	parent.add_child(_form_row("Loads:", loads_sp))

	# Carrier dropdown — party draft_vehicles + ships.
	var carrier_dd := OptionButton.new()
	_populate_carrier_dropdown(carrier_dd)
	parent.add_child(_form_row("Carrier:", carrier_dd))

	_fields = {
		"merchant_dd": merchant_dd,
		"loads_sp": loads_sp,
		"carrier_dd": carrier_dd,
	}

	merchant_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	loads_sp.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	carrier_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())


# ---------------------------------------------------------------------------
# Section: sell_merchandise (§3.6)
# ---------------------------------------------------------------------------

func _build_sell_section(parent: VBoxContainer) -> void:
	var current_day: int = Timekeeping.get_total_days()

	# Cargo dropdown — party's active-carrier cargo only.
	var cargo_dd := OptionButton.new()
	_cargo_index = CargoHoldRepository.list_for_party_active_carriers(_party_id)
	if _cargo_index.is_empty():
		cargo_dd.add_item("(no cargo to sell)")
		cargo_dd.disabled = true
	else:
		for i in _cargo_index.size():
			var c: Dictionary = _cargo_index[i]
			var cp_per_load_acquired: int = int(c.get("market_value_at_acquisition_cp", 0)) / maxi(1, int(c.get("loads_count", 1)))
			var label: String = "%s × %d (acquired @ %s/load)" % [
				String(c.get("merchandise_type", "?")),
				int(c.get("loads_count", 0)),
				Currency.format_cost(cp_per_load_acquired),
			]
			cargo_dd.add_item(label, i)
	parent.add_child(_form_row("Cargo:", cargo_dd))

	# Merchant dropdown — filtered by selected cargo's merchandise_type.
	# Populated initially based on the first cargo entry, re-populated when
	# cargo selection changes.
	var merchant_dd := OptionButton.new()
	parent.add_child(_form_row("Merchant:", merchant_dd))

	# Loads-to-sell SpinBox — defaults to selected cargo's loads_count.
	var loads_sp := SpinBox.new()
	loads_sp.min_value = 1
	loads_sp.max_value = 999
	loads_sp.value = 1
	parent.add_child(_form_row("Loads to sell:", loads_sp))

	_fields = {
		"cargo_dd": cargo_dd,
		"merchant_dd": merchant_dd,
		"loads_sp": loads_sp,
	}

	# Initial population of merchant dropdown based on the first cargo entry.
	_repopulate_sell_merchant_dropdown(current_day)
	_sync_sell_loads_to_cargo()

	cargo_dd.item_selected.connect(func(_i: int) -> void:
		_repopulate_sell_merchant_dropdown(current_day)
		_sync_sell_loads_to_cargo()
		_refresh_preview())
	merchant_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	loads_sp.value_changed.connect(func(_v: float) -> void: _refresh_preview())


func _repopulate_sell_merchant_dropdown(current_day: int) -> void:
	var cargo_dd: OptionButton = _fields.get("cargo_dd", null)
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	if cargo_dd == null or merchant_dd == null:
		return
	merchant_dd.clear()
	_merchant_index = []
	if _cargo_index.is_empty() or cargo_dd.disabled:
		merchant_dd.add_item("(select cargo first)")
		merchant_dd.disabled = true
		return
	var idx: int = cargo_dd.get_selected_id()
	if idx < 0 or idx >= _cargo_index.size():
		idx = 0
	var cargo: Dictionary = _cargo_index[idx]
	var merch_type: String = String(cargo.get("merchandise_type", ""))
	_merchant_index = MerchantPoolRepository.list_visible_merchants_for_merchandise(
		_settlement_id, merch_type, current_day)
	if _merchant_index.is_empty():
		merchant_dd.add_item("(no matching merchants — try Locate Merchandise)")
		merchant_dd.disabled = true
		return
	merchant_dd.disabled = false
	for i in _merchant_index.size():
		var m: Dictionary = _merchant_index[i]
		var label: String = "%s — buys %d loads (%s)" % [
			String(m.get("merchandise_type", "?")),
			int(m.get("loads_available", 0)),
			String(m.get("id", "")).substr(0, 6),
		]
		merchant_dd.add_item(label, i)


func _sync_sell_loads_to_cargo() -> void:
	var cargo_dd: OptionButton = _fields.get("cargo_dd", null)
	var loads_sp: SpinBox = _fields.get("loads_sp", null)
	if cargo_dd == null or loads_sp == null or _cargo_index.is_empty():
		return
	var idx: int = cargo_dd.get_selected_id()
	if idx < 0 or idx >= _cargo_index.size():
		idx = 0
	var max_loads: int = int((_cargo_index[idx] as Dictionary).get("loads_count", 1))
	loads_sp.max_value = max_loads
	loads_sp.value = max_loads  # Default to "sell all"


# ---------------------------------------------------------------------------
# Section: persuade_merchants (Wave 3 — §4.10)
# ---------------------------------------------------------------------------

func _build_persuade_section(parent: VBoxContainer) -> void:
	var current_day: int = Timekeeping.get_total_days()

	# Merchant dropdown — visible merchants at this settlement.
	var merchant_dd := OptionButton.new()
	_merchant_index = MerchantPoolRepository.list_visible_merchants(_settlement_id, current_day)
	if _merchant_index.is_empty():
		merchant_dd.add_item("(no visible merchants — try Solicit Merchants)")
		merchant_dd.disabled = true
	else:
		for i in _merchant_index.size():
			var m: Dictionary = _merchant_index[i]
			merchant_dd.add_item("%s — currently deals in %s (%s)" % [
				String(m.get("id", "")).substr(0, 6),
				String(m.get("merchandise_type", "?")),
				String(m.get("status", "active")),
			], i)
	parent.add_child(_form_row("Merchant:", merchant_dd))

	# Target merchandise dropdown — all 31 types.
	var merch_dd := _build_merchandise_dropdown()
	parent.add_child(_form_row("Target type:", merch_dd))

	# Direction radio buttons.
	var dir_row := HBoxContainer.new()
	dir_row.add_theme_constant_override("separation", 8)
	var dir_lbl := Label.new()
	dir_lbl.text = "Direction:"
	dir_lbl.custom_minimum_size.x = 140
	dir_row.add_child(dir_lbl)
	var buy_btn := CheckBox.new()
	buy_btn.text = "Buy from them (seeking sellers)"
	buy_btn.button_group = ButtonGroup.new()
	buy_btn.button_pressed = true
	dir_row.add_child(buy_btn)
	var sell_btn := CheckBox.new()
	sell_btn.text = "Sell to them (seeking buyers)"
	sell_btn.button_group = buy_btn.button_group
	dir_row.add_child(sell_btn)
	parent.add_child(dir_row)

	# Warning callout.
	var warn := Label.new()
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.modulate = Color(1, 0.7, 0.5, 1)
	warn.text = "Failure permanently loses this merchant from the cohort (RAW)."
	parent.add_child(warn)

	_fields = {
		"merchant_dd": merchant_dd,
		"target_merch_dd": merch_dd,
		"dir_buy_btn": buy_btn,
		"dir_sell_btn": sell_btn,
	}

	merchant_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	merch_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	buy_btn.toggled.connect(func(_pressed: bool) -> void: _refresh_preview())
	sell_btn.toggled.connect(func(_pressed: bool) -> void: _refresh_preview())


# ---------------------------------------------------------------------------
# Section: solicit_merchants (Wave 3 — §5.8)
# ---------------------------------------------------------------------------

func _build_solicit_section(parent: VBoxContainer) -> void:
	var current_day: int = Timekeeping.get_total_days()
	var invisible_count: int = MerchantPoolRepository.list_invisible_merchants(
		_settlement_id, current_day).size()

	# Schedule preview (read-only).
	var schedule_lbl := Label.new()
	schedule_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	schedule_lbl.add_theme_font_size_override("font_size", 12)
	var first_half: int = int(ceil(float(invisible_count) / 2.0))
	var second_quarter: int = maxi(int(floor(float(invisible_count) / 4.0)), 1)
	if first_half + second_quarter > invisible_count:
		second_quarter = invisible_count - first_half
	if second_quarter < 0:
		second_quarter = 0
	var remainder: int = maxi(0, invisible_count - first_half - second_quarter)
	if invisible_count == 0:
		schedule_lbl.text = "Pool fully revealed — solicit will reject (already_revealed)."
	else:
		schedule_lbl.text = (
			"You will solicit the market for 3 weeks (1 hour each day).\n\n"
			+ "Today: %d invisible merchants will be revealed on this schedule:\n" % invisible_count
			+ "  - Day +7 (1 week): %d merchants\n" % first_half
			+ "  - Day +14 (2 weeks): %d merchants\n" % second_quarter
			+ "  - Day +21 (3 weeks): %d merchants\n\n" % remainder
			+ "If you depart the market early, the unfired reveals will roll back."
		)
	parent.add_child(schedule_lbl)

	_fields = {
		"invisible_count": invisible_count,
	}


# ---------------------------------------------------------------------------
# Section: locate_merchandise (Wave 3 — §6.3)
# ---------------------------------------------------------------------------

func _build_locate_section(parent: VBoxContainer) -> void:
	# Merchandise type dropdown — all 31 types.
	var merch_dd := _build_merchandise_dropdown()
	parent.add_child(_form_row("Merchandise type:", merch_dd))

	_fields = {
		"merch_dd": merch_dd,
	}
	merch_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())


# ---------------------------------------------------------------------------
# Section: accept_shipping_contract (Wave 4 — §7.8)
# ---------------------------------------------------------------------------

func _build_shipping_contracts_section(parent: VBoxContainer) -> void:
	_offer_index = ShippingContractOfferRoller.list_offers(_party_id, _settlement_id)
	if _offer_index.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.text = "No shipping contracts available at this market right now. (Class V/VI markets may roll zero offers.)"
		parent.add_child(empty_lbl)
		_fields = {}
		return

	# Offer dropdown — one entry per offer with summary text.
	var offer_dd := OptionButton.new()
	for i in _offer_index.size():
		var o: Dictionary = _offer_index[i]
		var loads: int = int(o.get("loads_count", 0))
		var merch: String = String(o.get("merchandise_type", "mixed_cargo"))
		var dest: String = String(o.get("destination_settlement_id", "")).substr(0, 8)
		var miles: int = int(o.get("distance_miles", 0))
		var mode: String = String(o.get("route_mode", "road"))
		var fee_cp: int = int(o.get("fee_cp", 0))
		var deadline: int = int(o.get("deadline_calendar_day", 0))
		offer_dd.add_item("%d × %s → %s (%d mi %s, %s, deadline day %d)" % [
			loads, merch, dest, miles, mode, Currency.format_cost(fee_cp), deadline], i)
	parent.add_child(_form_row("Offer:", offer_dd))

	# Carrier dropdown — initially populated based on the first offer's route_mode.
	var carrier_dd := OptionButton.new()
	parent.add_child(_form_row("Carrier:", carrier_dd))

	_fields = {
		"offer_dd": offer_dd,
		"carrier_dd": carrier_dd,
	}

	_repopulate_shipping_carrier_dropdown()
	offer_dd.item_selected.connect(func(_i: int) -> void:
		_repopulate_shipping_carrier_dropdown()
		_refresh_preview())
	carrier_dd.item_selected.connect(func(_i: int) -> void: _refresh_preview())


func _repopulate_shipping_carrier_dropdown() -> void:
	var offer_dd: OptionButton = _fields.get("offer_dd", null)
	var carrier_dd: OptionButton = _fields.get("carrier_dd", null)
	if offer_dd == null or carrier_dd == null or _offer_index.is_empty():
		return
	carrier_dd.clear()
	_carrier_index = []
	var oidx: int = offer_dd.get_selected_id()
	if oidx < 0 or oidx >= _offer_index.size():
		oidx = 0
	var offer: Dictionary = _offer_index[oidx]
	var route_mode: String = String(offer.get("route_mode", "road"))
	var required_kind: String = "draft_vehicle" if route_mode == "road" else "ship"
	# Read the matching carrier list from the DB.
	if required_kind == "draft_vehicle":
		if CampaignRepository.db.query_with_bindings("""
			SELECT id, name FROM draft_vehicles
			WHERE party_id = ? AND is_destroyed = 0
			ORDER BY name ASC
		""", [_party_id]):
			for row in CampaignRepository.db.query_result:
				_carrier_index.append({
					"id": String((row as Dictionary).get("id", "")),
					"kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
					"name": String((row as Dictionary).get("name", "Wagon")),
				})
	else:
		if CampaignRepository.db.query_with_bindings("""
			SELECT id, name FROM ships
			WHERE party_id = ? AND is_destroyed = 0
			ORDER BY name ASC
		""", [_party_id]):
			for row in CampaignRepository.db.query_result:
				_carrier_index.append({
					"id": String((row as Dictionary).get("id", "")),
					"kind": CargoHoldRepository.CARRIER_SHIP,
					"name": String((row as Dictionary).get("name", "Ship")),
				})
	if _carrier_index.is_empty():
		carrier_dd.add_item("(no %s available)" % required_kind)
		carrier_dd.disabled = true
		return
	carrier_dd.disabled = false
	for i in _carrier_index.size():
		var c: Dictionary = _carrier_index[i]
		carrier_dd.add_item("%s (%s)" % [String(c.get("name", "?")), String(c.get("kind", ""))], i)


# ---------------------------------------------------------------------------
# Shared helper: merchandise dropdown (used by persuade + locate)
# ---------------------------------------------------------------------------

func _build_merchandise_dropdown() -> OptionButton:
	var dd := OptionButton.new()
	_merchandise_index = MerchandiseRegistry.all_merchandise()
	for i in _merchandise_index.size():
		var entry: Dictionary = _merchandise_index[i]
		var key: String = str(entry.get("merchandise_type", ""))
		if key.is_empty():
			continue
		var bucket: String = "Precious" if bool(entry.get("precious", false)) else "Common"
		# JSON column is base_price_cp; format_cost denominates.
		var base_price_cp: int = int(entry.get("base_price_cp", 0))
		var label: String = "%s (%s, %s base)" % [
			key.capitalize().replace("_", " "), bucket,
			Currency.format_cost(base_price_cp)]
		dd.add_item(label, i)
	return dd


# ---------------------------------------------------------------------------
# Carrier dropdown helper (buy section)
# ---------------------------------------------------------------------------

func _populate_carrier_dropdown(dd: OptionButton) -> void:
	dd.clear()
	_carrier_index = []
	# Draft vehicles.
	if CampaignRepository.db.query_with_bindings("""
		SELECT id, name, item_key FROM draft_vehicles
		WHERE party_id = ? AND is_destroyed = 0
		ORDER BY name ASC
	""", [_party_id]):
		for row in CampaignRepository.db.query_result:
			var r: Dictionary = row
			_carrier_index.append({
				"id": String(r.get("id", "")),
				"kind": CargoHoldRepository.CARRIER_DRAFT_VEHICLE,
				"name": String(r.get("name", "Wagon")),
			})
	# Ships.
	if CampaignRepository.db.query_with_bindings("""
		SELECT id, name FROM ships
		WHERE party_id = ? AND is_destroyed = 0
		ORDER BY name ASC
	""", [_party_id]):
		for row in CampaignRepository.db.query_result:
			var r: Dictionary = row
			_carrier_index.append({
				"id": String(r.get("id", "")),
				"kind": CargoHoldRepository.CARRIER_SHIP,
				"name": String(r.get("name", "Ship")),
			})
	if _carrier_index.is_empty():
		dd.add_item("(no carriers available)")
		dd.disabled = true
		return
	dd.disabled = false
	for i in _carrier_index.size():
		var c: Dictionary = _carrier_index[i]
		dd.add_item("%s (%s)" % [String(c.get("name", "?")), String(c.get("kind", ""))], i)


# ---------------------------------------------------------------------------
# Live preview + validation
# ---------------------------------------------------------------------------

func _refresh_preview() -> void:
	var preview_text: String = ""
	var validation_text: String = _validate_params()
	if _preview_label != null:
		match _kind:
			"buy_merchandise":
				preview_text = _preview_buy()
			"sell_merchandise":
				preview_text = _preview_sell()
			"persuade_merchants":
				preview_text = _preview_persuade()
			"solicit_merchants":
				preview_text = _preview_solicit()
			"locate_merchandise":
				preview_text = _preview_locate()
			"accept_shipping_contract":
				preview_text = _preview_shipping()
			_:
				preview_text = ""
		_preview_label.text = preview_text
	if _validation_label != null:
		_validation_label.text = validation_text
	if _launch_btn != null:
		_launch_btn.disabled = not validation_text.is_empty()


func _preview_buy() -> String:
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var loads_sp: SpinBox = _fields.get("loads_sp", null)
	if merchant_dd == null or loads_sp == null:
		return ""
	var idx: int = merchant_dd.get_selected_id() if not merchant_dd.disabled else -1
	if idx < 0 or idx >= _merchant_index.size():
		return ""
	var merchant: Dictionary = _merchant_index[idx]
	var merchandise_type: String = String(merchant.get("merchandise_type", ""))
	var loads_count: int = int(loads_sp.value)
	var monopolist_favor: int = MonopolyRegistry.favor_for_buy(
		_character_id, _settlement_id, merchandise_type)
	var rng_preview: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_preview.seed = hash("preview|%s|%s" % [_settlement_id, merchandise_type])
	var price: Dictionary = MarketPriceResolver.compute_market_price(
		merchandise_type, _settlement_id, monopolist_favor, 0, rng_preview,
		Timekeeping.get_total_days())
	var cp_per_load: int = int(price.get("cp_per_load", 0))
	var total_cp: int = cp_per_load * loads_count
	var load_weight: int = MerchandiseRegistry.load_weight_stone(merchandise_type)
	var labor_cp: int = MarketFeesCalculator.labor_fee_cp(load_weight * loads_count)
	var lines: PackedStringArray = []
	lines.append("Buy %d × %s @ %s/load = %s" % [
		loads_count, merchandise_type, Currency.format_cost(cp_per_load), Currency.format_cost(total_cp)])
	if not VisitStateManager.has_paid_entry_toll(_party_id, _settlement_id):
		lines.append("Entry toll (first transaction): rolled at launch")
	lines.append("Loading labor: %s" % Currency.format_cost(labor_cp))
	if monopolist_favor == -1:
		lines.append("Monopolist favor: -1 (buy price reduced)")
	lines.append("Estimated total: %s" % Currency.format_cost(total_cp + labor_cp))
	return "\n".join(lines)


func _preview_sell() -> String:
	var cargo_dd: OptionButton = _fields.get("cargo_dd", null)
	var loads_sp: SpinBox = _fields.get("loads_sp", null)
	if cargo_dd == null or loads_sp == null or _cargo_index.is_empty():
		return ""
	var idx: int = cargo_dd.get_selected_id() if not cargo_dd.disabled else -1
	if idx < 0 or idx >= _cargo_index.size():
		return ""
	var cargo: Dictionary = _cargo_index[idx]
	var merchandise_type: String = String(cargo.get("merchandise_type", ""))
	var loads_to_sell: int = int(loads_sp.value)
	var monopolist_favor: int = MonopolyRegistry.favor_for_sell(
		_character_id, _settlement_id, merchandise_type)
	var is_domain_owner: bool = MarketFeesCalculator.is_domain_owner_in_own_market(
		_character_id, _settlement_id)
	var rng_preview: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_preview.seed = hash("preview|%s|%s" % [_settlement_id, merchandise_type])
	var price: Dictionary = MarketPriceResolver.compute_market_price(
		merchandise_type, _settlement_id, monopolist_favor, 0, rng_preview,
		Timekeeping.get_total_days())
	var cp_per_load: int = int(price.get("cp_per_load", 0))
	var gross_cp: int = cp_per_load * loads_to_sell
	var load_weight: int = MerchandiseRegistry.load_weight_stone(merchandise_type)
	var labor_cp: int = MarketFeesCalculator.labor_fee_cp(load_weight * loads_to_sell)
	var customs_cp: int = MarketFeesCalculator.customs_duty_cp(gross_cp, _settlement_id, is_domain_owner)
	var lines: PackedStringArray = []
	lines.append("Sell %d × %s @ %s/load = %s gross" % [
		loads_to_sell, merchandise_type, Currency.format_cost(cp_per_load), Currency.format_cost(gross_cp)])
	if not VisitStateManager.has_paid_entry_toll(_party_id, _settlement_id):
		lines.append("Entry toll (first transaction): rolled at launch")
	lines.append("Unloading labor: %s" % Currency.format_cost(labor_cp))
	if is_domain_owner:
		lines.append("Domain-owner exemption: customs waived")
	else:
		lines.append("Customs duty: %s" % Currency.format_cost(customs_cp))
	if monopolist_favor == 1:
		lines.append("Monopolist favor: +1 (sell price increased)")
	lines.append("Net proceeds: %s" % Currency.format_cost(gross_cp - labor_cp - customs_cp))
	return "\n".join(lines)


func _validate_params() -> String:
	match _kind:
		"buy_merchandise":
			return _validate_buy()
		"sell_merchandise":
			return _validate_sell()
		"persuade_merchants":
			return _validate_persuade()
		"solicit_merchants":
			return _validate_solicit()
		"locate_merchandise":
			return _validate_locate()
		"accept_shipping_contract":
			return _validate_shipping()
		_:
			return "Unknown activity kind: %s" % _kind


func _validate_buy() -> String:
	if _character_id.is_empty():
		return "Select an active character."
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var loads_sp: SpinBox = _fields.get("loads_sp", null)
	var carrier_dd: OptionButton = _fields.get("carrier_dd", null)
	if merchant_dd == null or merchant_dd.disabled:
		return "No visible merchants — try Solicit Merchants."
	if carrier_dd == null or carrier_dd.disabled:
		return "No carrier available (you need a draft vehicle or ship)."
	var midx: int = merchant_dd.get_selected_id()
	if midx < 0 or midx >= _merchant_index.size():
		return "Select a merchant."
	var cidx: int = carrier_dd.get_selected_id()
	if cidx < 0 or cidx >= _carrier_index.size():
		return "Select a carrier."
	var merchant: Dictionary = _merchant_index[midx]
	var loads_count: int = int(loads_sp.value) if loads_sp != null else 0
	if loads_count <= 0:
		return "Loads must be positive."
	var max_buyable: int = int(merchant.get("loads_available", 0))
	if MonopolyRegistry.has_monopoly(
			_character_id, _settlement_id, String(merchant.get("merchandise_type", ""))):
		max_buyable *= 2
	if loads_count > max_buyable:
		return "Loads exceed merchant supply (%d)." % max_buyable
	# Capacity check.
	var carrier: Dictionary = _carrier_index[cidx]
	var load_weight: int = MerchandiseRegistry.load_weight_stone(
		String(merchant.get("merchandise_type", "")))
	if not BuySellCommon.carrier_has_capacity(
			String(carrier.get("id", "")), String(carrier.get("kind", "")),
			load_weight * loads_count):
		return "Carrier capacity exceeded."
	return ""


func _validate_sell() -> String:
	if _character_id.is_empty():
		return "Select an active character."
	var cargo_dd: OptionButton = _fields.get("cargo_dd", null)
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var loads_sp: SpinBox = _fields.get("loads_sp", null)
	if cargo_dd == null or cargo_dd.disabled:
		return "No cargo to sell."
	if merchant_dd == null or merchant_dd.disabled:
		return "No matching merchant — try Locate Merchandise."
	var cidx: int = cargo_dd.get_selected_id()
	if cidx < 0 or cidx >= _cargo_index.size():
		return "Select cargo."
	var midx: int = merchant_dd.get_selected_id()
	if midx < 0 or midx >= _merchant_index.size():
		return "Select a merchant."
	var loads_to_sell: int = int(loads_sp.value) if loads_sp != null else 0
	if loads_to_sell <= 0:
		return "Loads must be positive."
	var max_loads: int = int((_cargo_index[cidx] as Dictionary).get("loads_count", 0))
	if loads_to_sell > max_loads:
		return "Loads exceed cargo (%d)." % max_loads
	return ""


# ---------------------------------------------------------------------------
# Param collection — assembles the activity-handler params dict per §1.3
# ---------------------------------------------------------------------------

func _collect_params() -> Dictionary:
	match _kind:
		"buy_merchandise":
			return _collect_buy_params()
		"sell_merchandise":
			return _collect_sell_params()
		"persuade_merchants":
			return _collect_persuade_params()
		"solicit_merchants":
			# Solicit's params are populated by SolicitMerchantsHandler.prepare_launch
			# inside SettlementExploreState's router; picker passes {} here.
			return {}
		"locate_merchandise":
			return _collect_locate_params()
		"accept_shipping_contract":
			return _collect_shipping_params()
		_:
			return {}


func _collect_buy_params() -> Dictionary:
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var loads_sp: SpinBox = _fields.get("loads_sp", null)
	var carrier_dd: OptionButton = _fields.get("carrier_dd", null)
	var midx: int = merchant_dd.get_selected_id() if merchant_dd != null else -1
	var cidx: int = carrier_dd.get_selected_id() if carrier_dd != null else -1
	if midx < 0 or midx >= _merchant_index.size() or cidx < 0 or cidx >= _carrier_index.size():
		return {}
	var merchant: Dictionary = _merchant_index[midx]
	var carrier: Dictionary = _carrier_index[cidx]
	return {
		"merchant_id": String(merchant.get("id", "")),
		"merchandise_type": String(merchant.get("merchandise_type", "")),
		"loads_count": int(loads_sp.value),
		"carrier_id": String(carrier.get("id", "")),
		"carrier_kind": String(carrier.get("kind", "")),
	}


func _collect_sell_params() -> Dictionary:
	var cargo_dd: OptionButton = _fields.get("cargo_dd", null)
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var loads_sp: SpinBox = _fields.get("loads_sp", null)
	var cidx: int = cargo_dd.get_selected_id() if cargo_dd != null else -1
	var midx: int = merchant_dd.get_selected_id() if merchant_dd != null else -1
	if cidx < 0 or cidx >= _cargo_index.size() or midx < 0 or midx >= _merchant_index.size():
		return {}
	var cargo: Dictionary = _cargo_index[cidx]
	var merchant: Dictionary = _merchant_index[midx]
	return {
		"merchant_id": String(merchant.get("id", "")),
		"cargo_hold_id": String(cargo.get("id", "")),
		"loads_to_sell": int(loads_sp.value),
	}


# ---------------------------------------------------------------------------
# Footer button handlers
# ---------------------------------------------------------------------------

func _on_launch_pressed() -> void:
	if _launch_btn != null and _launch_btn.disabled:
		return
	var params: Dictionary = _collect_params()
	if params.is_empty():
		return
	var activity_def_id: String = _kind
	var location_kind: String = "settlement"
	var location_ref: String = _settlement_id
	visible = false
	launch_requested.emit(activity_def_id, params, location_kind, location_ref)
	queue_free()


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()
	queue_free()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _form_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


# ---------------------------------------------------------------------------
# Wave 3 — Persuade preview / validate / collect
# ---------------------------------------------------------------------------

func _preview_persuade() -> String:
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var merch_dd: OptionButton = _fields.get("target_merch_dd", null)
	if merchant_dd == null or merch_dd == null:
		return ""
	if merchant_dd.disabled or _merchandise_index.is_empty():
		return ""
	var midx: int = merchant_dd.get_selected_id() if not merchant_dd.disabled else -1
	var tidx: int = merch_dd.get_selected_id()
	if midx < 0 or midx >= _merchant_index.size():
		return ""
	if tidx < 0 or tidx >= _merchandise_index.size():
		return ""
	var merchant: Dictionary = _merchant_index[midx]
	var target_entry: Dictionary = _merchandise_index[tidx]
	var target_type: String = String(target_entry.get("merchandise_type", ""))
	if String(merchant.get("merchandise_type", "")) == target_type:
		return "Merchant already deals in %s. Pick a different target type." % target_type

	var direction: String = "sell" if bool(_fields.get("dir_sell_btn", CheckBox.new()).button_pressed) else "buy"
	var character: Dictionary = CampaignRepository.get_character(_character_id)
	var cha_mod: int = CharacterData.ability_modifier(int(character.get("charisma", 10)))
	var prof_mods: int = 0
	for prof_key in ["bribery", "diplomacy", "intimidation", "mystic_aura", "seduction"]:
		prof_mods += CampaignRepository.get_character_proficiency_rank(_character_id, prof_key, "")
	var demand_mod: int = DemandModifierGenerator.get_demand_modifier(_settlement_id, target_type)
	var signed_demand: int = demand_mod if direction == "sell" else -demand_mod
	var monopolist_bonus: int = 3 if MonopolyRegistry.has_monopoly(
		_character_id, _settlement_id, target_type) else 0
	var threshold: int = 12 if MerchandiseRegistry.is_precious(target_type) else 9
	var avg_total: int = 7 + cha_mod + prof_mods + signed_demand + monopolist_bonus

	var lines: PackedStringArray = []
	lines.append("Reaction roll: 2d6 + CHA(%+d) + Prof(%+d) + Demand(%+d) + Monopolist(%+d)" % [
		cha_mod, prof_mods, signed_demand, monopolist_bonus])
	lines.append("Average total: ~%d vs threshold %d (%s: %s)" % [
		avg_total, threshold,
		"Precious" if MerchandiseRegistry.is_precious(target_type) else "Common",
		target_type])
	var prediction: String = "likely success" if avg_total >= threshold else "likely failure"
	lines.append("Likely outcome: %s" % prediction)
	return "\n".join(lines)


func _validate_persuade() -> String:
	if _character_id.is_empty():
		return "Select an active character."
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var merch_dd: OptionButton = _fields.get("target_merch_dd", null)
	if merchant_dd == null or merchant_dd.disabled:
		return "No visible merchants — try Solicit Merchants."
	if merch_dd == null or _merchandise_index.is_empty():
		return "Select a target merchandise type."
	var midx: int = merchant_dd.get_selected_id()
	var tidx: int = merch_dd.get_selected_id()
	if midx < 0 or midx >= _merchant_index.size():
		return "Select a merchant."
	if tidx < 0 or tidx >= _merchandise_index.size():
		return "Select a target merchandise type."
	var merchant: Dictionary = _merchant_index[midx]
	var target_type: String = String(_merchandise_index[tidx].get("merchandise_type", ""))
	if String(merchant.get("merchandise_type", "")) == target_type:
		return "Merchant already deals in %s — pick a different type." % target_type
	return ""


func _collect_persuade_params() -> Dictionary:
	var merchant_dd: OptionButton = _fields.get("merchant_dd", null)
	var merch_dd: OptionButton = _fields.get("target_merch_dd", null)
	var sell_btn: CheckBox = _fields.get("dir_sell_btn", null)
	var midx: int = merchant_dd.get_selected_id() if merchant_dd != null else -1
	var tidx: int = merch_dd.get_selected_id() if merch_dd != null else -1
	if midx < 0 or midx >= _merchant_index.size() or tidx < 0 or tidx >= _merchandise_index.size():
		return {}
	var direction: String = "sell" if (sell_btn != null and sell_btn.button_pressed) else "buy"
	return {
		"merchant_id": String((_merchant_index[midx] as Dictionary).get("id", "")),
		"target_merchandise_type": String((_merchandise_index[tidx] as Dictionary).get("merchandise_type", "")),
		"direction": direction,
	}


# ---------------------------------------------------------------------------
# Wave 3 — Solicit preview / validate
# ---------------------------------------------------------------------------

func _preview_solicit() -> String:
	var invisible_count: int = int(_fields.get("invisible_count", 0))
	if invisible_count == 0:
		return "Nothing to solicit — pool is fully revealed."
	return ""


func _validate_solicit() -> String:
	if _character_id.is_empty():
		return "Select an active character."
	var invisible_count: int = int(_fields.get("invisible_count", 0))
	if invisible_count == 0:
		return "Pool already fully revealed."
	return ""


# ---------------------------------------------------------------------------
# Wave 3 — Locate preview / validate / collect
# ---------------------------------------------------------------------------

func _preview_locate() -> String:
	var merch_dd: OptionButton = _fields.get("merch_dd", null)
	if merch_dd == null or _merchandise_index.is_empty():
		return ""
	var tidx: int = merch_dd.get_selected_id()
	if tidx < 0 or tidx >= _merchandise_index.size():
		return ""
	var target_type: String = String(_merchandise_index[tidx].get("merchandise_type", ""))
	var current_day: int = Timekeeping.get_total_days()
	var visible_count: int = MerchantPoolRepository.list_visible_merchants_for_merchandise(
		_settlement_id, target_type, current_day).size()
	# Filter the invisible list by target type to predict the outcome.
	var all_invisible: Array = MerchantPoolRepository.list_invisible_merchants(
		_settlement_id, current_day)
	var invisible_matching: int = 0
	for row in all_invisible:
		if String((row as Dictionary).get("merchandise_type", "")) == target_type:
			invisible_matching += 1

	var lines: PackedStringArray = []
	lines.append("Targeting: %s" % target_type)
	lines.append("At this market: %d visible, %d invisible matching" % [
		visible_count, invisible_matching])
	if visible_count > 0:
		lines.append("Outcome estimate: already visible — locating is a no-op success.")
	elif invisible_matching > 0:
		lines.append("Outcome estimate: locating will surface one invisible merchant.")
	else:
		lines.append("Outcome estimate: no merchant of this type — locating will fail. Consider Persuade Merchants instead.")
	lines.append("Game time cost: 1 hour")
	return "\n".join(lines)


func _validate_locate() -> String:
	if _character_id.is_empty():
		return "Select an active character."
	var merch_dd: OptionButton = _fields.get("merch_dd", null)
	if merch_dd == null or _merchandise_index.is_empty():
		return "Select a merchandise type."
	var tidx: int = merch_dd.get_selected_id()
	if tidx < 0 or tidx >= _merchandise_index.size():
		return "Select a merchandise type."
	return ""


func _collect_locate_params() -> Dictionary:
	var merch_dd: OptionButton = _fields.get("merch_dd", null)
	var tidx: int = merch_dd.get_selected_id() if merch_dd != null else -1
	if tidx < 0 or tidx >= _merchandise_index.size():
		return {}
	return {
		"merchandise_type": String((_merchandise_index[tidx] as Dictionary).get("merchandise_type", "")),
	}


# ---------------------------------------------------------------------------
# Wave 4 — Shipping contracts preview / validate / collect
# ---------------------------------------------------------------------------

func _preview_shipping() -> String:
	if _offer_index.is_empty():
		return ""
	var offer_dd: OptionButton = _fields.get("offer_dd", null)
	var carrier_dd: OptionButton = _fields.get("carrier_dd", null)
	if offer_dd == null:
		return ""
	var oidx: int = offer_dd.get_selected_id()
	if oidx < 0 or oidx >= _offer_index.size():
		return ""
	var offer: Dictionary = _offer_index[oidx]
	var loads: int = int(offer.get("loads_count", 0))
	var stone: int = loads * int(offer.get("load_weight_stone", 0))
	var dest: String = String(offer.get("destination_settlement_id", ""))
	var route_mode: String = String(offer.get("route_mode", "road"))
	var miles: int = int(offer.get("distance_miles", 0))
	var fee_cp: int = int(offer.get("fee_cp", 0))
	var deadline: int = int(offer.get("deadline_calendar_day", 0))
	var current_day: int = Timekeeping.get_total_days()
	var days_remaining: int = maxi(0, deadline - current_day)

	var lines: PackedStringArray = []
	lines.append("Contract: %d loads of %s (%d stone)" % [loads, String(offer.get("merchandise_type", "mixed_cargo")), stone])
	lines.append("Destination: %s (%d mi by %s)" % [dest.substr(0, 12), miles, route_mode])
	lines.append("Fee: %s on delivery" % Currency.format_cost(fee_cp))
	lines.append("Deadline: day %d (%d days from now)" % [deadline, days_remaining])
	if carrier_dd != null and not carrier_dd.disabled and not _carrier_index.is_empty():
		var cidx: int = carrier_dd.get_selected_id()
		if cidx >= 0 and cidx < _carrier_index.size():
			var carrier: Dictionary = _carrier_index[cidx]
			lines.append("Loading onto: %s" % String(carrier.get("name", "?")))
	if not VisitStateManager.has_paid_entry_toll(_party_id, _settlement_id):
		lines.append("Entry toll (first transaction): rolled at launch")
	return "\n".join(lines)


func _validate_shipping() -> String:
	if _character_id.is_empty():
		return "Select an active character."
	if _offer_index.is_empty():
		return "No shipping contracts available."
	var offer_dd: OptionButton = _fields.get("offer_dd", null)
	var carrier_dd: OptionButton = _fields.get("carrier_dd", null)
	if offer_dd == null:
		return "Select an offer."
	var oidx: int = offer_dd.get_selected_id()
	if oidx < 0 or oidx >= _offer_index.size():
		return "Select an offer."
	if carrier_dd == null or carrier_dd.disabled:
		var route_mode: String = String((_offer_index[oidx] as Dictionary).get("route_mode", "road"))
		var required: String = "wagon" if route_mode == "road" else "ship"
		return "No %s available for this %s contract." % [required, route_mode]
	var cidx: int = carrier_dd.get_selected_id()
	if cidx < 0 or cidx >= _carrier_index.size():
		return "Select a carrier."
	# Capacity check.
	var offer: Dictionary = _offer_index[oidx]
	var total_stone: int = int(offer.get("loads_count", 0)) * int(offer.get("load_weight_stone", 0))
	var carrier: Dictionary = _carrier_index[cidx]
	if not BuySellCommon.carrier_has_capacity(
			String(carrier.get("id", "")), String(carrier.get("kind", "")), total_stone):
		return "Carrier lacks capacity (%d stone needed)." % total_stone
	return ""


func _collect_shipping_params() -> Dictionary:
	var offer_dd: OptionButton = _fields.get("offer_dd", null)
	var carrier_dd: OptionButton = _fields.get("carrier_dd", null)
	var oidx: int = offer_dd.get_selected_id() if offer_dd != null else -1
	var cidx: int = carrier_dd.get_selected_id() if carrier_dd != null else -1
	if oidx < 0 or oidx >= _offer_index.size() or cidx < 0 or cidx >= _carrier_index.size():
		return {}
	var carrier: Dictionary = _carrier_index[cidx]
	return {
		"offer_id": String((_offer_index[oidx] as Dictionary).get("id", "")),
		"carrier_id": String(carrier.get("id", "")),
		"carrier_kind": String(carrier.get("kind", "")),
	}
