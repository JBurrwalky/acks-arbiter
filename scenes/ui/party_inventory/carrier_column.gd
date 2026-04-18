# CarrierColumn — renders one carrier (PC, henchman, creature, vehicle, cache)
# in the Party Inventory Overlay.
#
# Dependencies:
#   - CampaignRepository (autoload): reads inventory, character, creature, vehicle data
#   - PartyWallet (autoload): gold display for PCs
#   - EventBus (autoload): inventory_updated, creature_inventory_updated, vehicle_changed
#   - Currency (preloaded): coin detection for filter
#   - EquipmentCatalog (passed via setup): item metadata
#
# No class_name — scene-instantiated via carrier_column.tscn.

extends VBoxContainer

const Currency := preload("res://engine/subsystems/commerce/currency.gd")
const GoldDisplayScene := preload("res://scenes/ui/components/gold_display.tscn")
const EncumbranceBarScene := preload("res://scenes/ui/components/encumbrance_bar.tscn")

signal transfer_requested(source: Dictionary, target: Dictionary)
signal item_context_menu_requested(item_id: String, carrier_type: String,
		carrier_id: String, position: Vector2)
signal gold_display_clicked(character_id: String)
signal prefs_clicked(character_id: String)
signal pick_up_all_clicked(cache_id: String)

enum Variant { PC, HENCHMAN, CREATURE, VEHICLE, CACHE }

const COLUMN_WIDTH := 200
const FILTER_ALL := ""
const FILTER_COINS := "coins"
const FILTER_WEAPONS := "weapons"
const FILTER_ARMOR := "armor"
const FILTER_AMMUNITION := "ammunition"
const FILTER_CONSUMABLES := "consumables"
const FILTER_LIGHT := "light"
const FILTER_POTIONS := "potions"
const FILTER_SCROLLS := "scrolls"
const FILTER_MAGIC := "magic"
const FILTER_CONTAINERS := "containers"
const FILTER_TACK := "tack"
const FILTER_TOOLS := "tools"


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _variant: int = Variant.PC
var _carrier_type: String = "character"
var _carrier_id: String = ""
var _carrier_data = null  # TrainedCreatureData | Dictionary (vehicle/cache)
var _is_active: bool = false
var _items: Array = []
var _validator = null  # PartyInventoryTransferValidator — set by overlay
var _catalog = null  # EquipmentCatalog — set by overlay
var _current_filter: String = ""
var _current_search: String = ""

# UI references
var _header_label: Label
var _subtitle_label: Label
var _gold_display = null
var _encumbrance_bar = null
var _items_container: VBoxContainer
var _prefs_button: Button = null
var _pickup_all_button: Button = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size.x = COLUMN_WIDTH
	size_flags_horizontal = Control.SIZE_FILL
	add_theme_constant_override("separation", 4)


# ---------------------------------------------------------------------------
# Public API — Setup
# ---------------------------------------------------------------------------

## Sets the validator and catalog from the overlay.
func set_services(validator, catalog) -> void:
	_validator = validator
	_catalog = catalog


## Populates the column for a PC or henchman.
func setup_character(character_id: String, is_active: bool = false,
		character_type: String = "pc") -> void:
	_carrier_type = "character"
	_carrier_id = character_id
	_is_active = is_active
	_variant = Variant.PC if character_type == "pc" else Variant.HENCHMAN
	_build_ui()
	refresh()


## Populates for a trained creature.
func setup_creature(creature_id: String, creature_data = null) -> void:
	_carrier_type = "creature"
	_carrier_id = creature_id
	_variant = Variant.CREATURE
	_carrier_data = creature_data
	_build_ui()
	refresh()


## Populates for a draft vehicle.
func setup_vehicle(vehicle_id: String, vehicle_data: Dictionary = {}) -> void:
	_carrier_type = "vehicle"
	_carrier_id = vehicle_id
	_variant = Variant.VEHICLE
	_carrier_data = vehicle_data
	_build_ui()
	refresh()


## Populates for a location cache.
func setup_cache(cache_id: String, cache_data: Dictionary = {}) -> void:
	_carrier_type = "cache"
	_carrier_id = cache_id
	_variant = Variant.CACHE
	_carrier_data = cache_data
	_build_ui()
	refresh()


## Refresh all item rows / capacity display. Called after any transfer.
func refresh() -> void:
	_load_items()
	_render_items()
	_update_encumbrance()
	_update_gold()


## Filter display by category.
func set_filter(filter_key: String) -> void:
	_current_filter = filter_key
	_apply_visibility()


## Filter by search text.
func set_search(query: String) -> void:
	_current_search = query.to_lower()
	_apply_visibility()


## Returns carrier info dict for the overlay's transfer dispatch.
func get_carrier_info() -> Dictionary:
	return {
		"carrier_type": _carrier_type,
		"carrier_id": _carrier_id,
		"data": _carrier_data,
	}


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Clear previous UI
	for child in get_children():
		child.queue_free()

	# Panel background
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.08, 0.85)
	style.border_color = Color(0.46, 0.33, 0.19, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	if _is_active:
		style.border_color = Color(0.8, 0.65, 0.2, 0.9)
		style.border_width_top = 2
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	# Header
	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 14)
	_header_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_header_label)

	# Subtitle
	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_subtitle_label)

	# Encumbrance bar (not for caches)
	if _variant != Variant.CACHE:
		_encumbrance_bar = EncumbranceBarScene.instantiate()
		_encumbrance_bar.custom_minimum_size.y = 16
		vbox.add_child(_encumbrance_bar)

	# Gold display (PC and henchman only)
	if _variant == Variant.PC or _variant == Variant.HENCHMAN:
		var gold_row := HBoxContainer.new()
		_gold_display = GoldDisplayScene.instantiate()
		gold_row.add_child(_gold_display)
		if _variant == Variant.PC:
			_gold_display.mouse_filter = Control.MOUSE_FILTER_STOP
			_gold_display.gui_input.connect(_on_gold_gui_input)
		vbox.add_child(gold_row)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Items container
	_items_container = VBoxContainer.new()
	_items_container.add_theme_constant_override("separation", 1)
	vbox.add_child(_items_container)

	# Prefs button (PC/henchman only)
	if _variant == Variant.PC or _variant == Variant.HENCHMAN:
		var sep2 := HSeparator.new()
		vbox.add_child(sep2)
		_prefs_button = Button.new()
		_prefs_button.text = "Preferences"
		_prefs_button.add_theme_font_size_override("font_size", 11)
		_prefs_button.pressed.connect(_on_prefs_pressed)
		vbox.add_child(_prefs_button)

	# Pick up all button (cache only)
	if _variant == Variant.CACHE:
		var sep3 := HSeparator.new()
		vbox.add_child(sep3)
		_pickup_all_button = Button.new()
		_pickup_all_button.text = "Pick Up All"
		_pickup_all_button.add_theme_font_size_override("font_size", 11)
		_pickup_all_button.pressed.connect(_on_pickup_all_pressed)
		vbox.add_child(_pickup_all_button)

	_update_header()


func _update_header() -> void:
	match _variant:
		Variant.PC, Variant.HENCHMAN:
			var char_data := CampaignRepository.get_character(_carrier_id)
			_header_label.text = str(char_data.get("name", "Unknown"))
			var cls: String = str(char_data.get("character_class", ""))
			var lvl: int = int(char_data.get("level", 1))
			_subtitle_label.text = "%s Lv%d" % [cls.capitalize(), lvl]
			if _variant == Variant.HENCHMAN:
				_subtitle_label.text += " (Henchman)"
		Variant.CREATURE:
			if _carrier_data != null:
				_header_label.text = _carrier_data.name if _carrier_data.name else "Creature"
				_subtitle_label.text = _carrier_data.species_id.capitalize()
			else:
				_header_label.text = "Creature"
				_subtitle_label.text = ""
		Variant.VEHICLE:
			if _carrier_data is Dictionary:
				_header_label.text = str(_carrier_data.get("name", "Vehicle"))
				_subtitle_label.text = str(_carrier_data.get("item_key", "")).capitalize()
			else:
				_header_label.text = "Vehicle"
				_subtitle_label.text = ""
		Variant.CACHE:
			if _carrier_data is Dictionary:
				var variant_str: String = str(_carrier_data.get("cache_variant", "loose"))
				match variant_str:
					"loose":
						_header_label.text = "Ground (loose)"
						var decay_day = _carrier_data.get("decay_check_day")
						if decay_day != null:
							var days_left: int = int(decay_day) - Timekeeping.get_total_days()
							_subtitle_label.text = "Decays in %d days" % max(days_left, 0)
						else:
							_subtitle_label.text = ""
					"locked_container":
						_header_label.text = "Locked Container"
						_subtitle_label.text = "Permanent"
					"hidden_wilderness":
						_header_label.text = "Hidden Stash"
						var mod: int = int(_carrier_data.get("raid_monthly_modifier", 0))
						_subtitle_label.text = "Raid risk: %d%%/mo" % mod
					_:
						_header_label.text = "Cache"
						_subtitle_label.text = ""
			else:
				_header_label.text = "Cache"
				_subtitle_label.text = ""


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

func _load_items() -> void:
	_items.clear()
	match _variant:
		Variant.PC, Variant.HENCHMAN:
			_items = CampaignRepository.get_inventory_items(_carrier_id)
		Variant.CREATURE:
			_items = CampaignRepository.get_creature_inventory(_carrier_id)
		Variant.VEHICLE:
			_items = CampaignRepository.get_items_in_vehicle(_carrier_id)
		Variant.CACHE:
			_items = LocationCacheManager.get_items_in_cache(_carrier_id)


func _update_encumbrance() -> void:
	if _encumbrance_bar == null:
		return
	match _variant:
		Variant.PC, Variant.HENCHMAN:
			_encumbrance_bar.setup_character(_carrier_id)
		Variant.CREATURE:
			_encumbrance_bar.setup_creature(_carrier_id)
		Variant.VEHICLE:
			_encumbrance_bar.setup_vehicle(_carrier_id)


func _update_gold() -> void:
	if _gold_display == null:
		return
	_gold_display.set_source("character", _carrier_id)


# ---------------------------------------------------------------------------
# Item rendering
# ---------------------------------------------------------------------------

func _render_items() -> void:
	# Clear existing item rows
	for child in _items_container.get_children():
		child.queue_free()

	if _items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(empty)"
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_items_container.add_child(empty_label)
		return

	# Group items by section
	var equipped_items: Array = []
	var container_items: Dictionary = {}  # container_id -> Array of items
	var tack_items: Array = []
	var loose_items: Array = []

	for item in _items:
		var item_dict: Dictionary = _normalize_item(item)
		var equipped: bool = _is_equipped(item_dict)
		var container_id: String = str(item_dict.get("container_id", ""))

		if _variant == Variant.CACHE:
			loose_items.append(item_dict)
		elif _variant == Variant.CREATURE:
			var cat: String = str(item_dict.get("item_category", ""))
			var key: String = str(item_dict.get("item_key", ""))
			if equipped and (cat == "barding" or key.begins_with("saddle_") or key == "saddlebags" or key == "caparison"):
				tack_items.append(item_dict)
			elif not container_id.is_empty():
				if not container_items.has(container_id):
					container_items[container_id] = []
				container_items[container_id].append(item_dict)
			else:
				loose_items.append(item_dict)
		elif equipped:
			equipped_items.append(item_dict)
		elif not container_id.is_empty():
			if not container_items.has(container_id):
				container_items[container_id] = []
			container_items[container_id].append(item_dict)
		else:
			loose_items.append(item_dict)

	# Render sections
	if _variant == Variant.CREATURE and not tack_items.is_empty():
		_add_section_header("TACK")
		for it in tack_items:
			_add_item_row(it)

	if not equipped_items.is_empty() and _variant != Variant.CREATURE:
		_add_section_header("EQUIPPED")
		for it in equipped_items:
			_add_item_row(it)

	if not container_items.is_empty():
		_add_section_header("CONTAINERS")
		for c_id in container_items:
			# Find the container item itself to get its name
			var c_name: String = c_id
			for it in _items:
				var d := _normalize_item(it)
				if str(d.get("id", "")) == c_id:
					c_name = str(d.get("name", c_id))
					break
			var c_label := Label.new()
			c_label.text = "  \u25B8 %s" % c_name
			c_label.add_theme_font_size_override("font_size", 11)
			c_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.5))
			_items_container.add_child(c_label)
			for it in container_items[c_id]:
				_add_item_row(it, true)

	var cargo_label := "CARGO" if _variant in [Variant.CREATURE, Variant.VEHICLE] else "LOOSE"
	if not loose_items.is_empty():
		if _variant != Variant.CACHE:
			_add_section_header(cargo_label)
		for it in loose_items:
			_add_item_row(it)


func _add_section_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	_items_container.add_child(label)


func _add_item_row(item_dict: Dictionary, indented: bool = false) -> void:
	var row := _ItemRow.new()
	row.item_data = item_dict
	row.carrier_type = _carrier_type
	row.carrier_id = _carrier_id
	row.indented = indented
	row.column = self
	_items_container.add_child(row)


# ---------------------------------------------------------------------------
# Drag and drop
# ---------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if _validator == null:
		return false
	var target := {
		"carrier_type": _carrier_type,
		"carrier_id": _carrier_id,
		"slot": "",
		"data": _carrier_data,
	}
	var ctx := _build_context()
	# We need the item data — it should be in the drag data
	var item: Dictionary = data.get("item_data", {})
	var source := {
		"carrier_type": data.get("carrier_type", ""),
		"carrier_id": data.get("carrier_id", ""),
		"item_id": data.get("item_id", ""),
		"quantity": data.get("quantity", 1),
	}
	var result: Dictionary = _validator.validate_transfer(source, target, ctx, item)
	return result.ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var source := {
		"carrier_type": data.get("carrier_type", ""),
		"carrier_id": data.get("carrier_id", ""),
		"item_id": data.get("item_id", ""),
		"quantity": data.get("quantity", 1),
	}
	var target := {
		"carrier_type": _carrier_type,
		"carrier_id": _carrier_id,
		"slot": "",
		"data": _carrier_data,
	}
	transfer_requested.emit(source, target)


func _build_context() -> Dictionary:
	return {
		"location_key": GameState.current_location_key,
		"is_in_combat": GameState.current_state == GameState.State.COMBAT,
		"active_character_id": GameState.active_character_id,
	}


# ---------------------------------------------------------------------------
# Filter / search
# ---------------------------------------------------------------------------

func _apply_visibility() -> void:
	for child in _items_container.get_children():
		if child is _ItemRow:
			var visible_by_filter := _item_matches_filter(child.item_data)
			var visible_by_search := _item_matches_search(child.item_data)
			if visible_by_filter and visible_by_search:
				child.modulate.a = 1.0
			else:
				child.modulate.a = 0.3


func _item_matches_filter(item: Dictionary) -> bool:
	if _current_filter.is_empty():
		return true
	var cat: String = str(item.get("item_category", ""))
	var key: String = str(item.get("item_key", ""))
	var is_magic: bool = int(item.get("is_magical", 0)) == 1
	match _current_filter:
		FILTER_COINS:
			return Currency.is_coin(key)
		FILTER_WEAPONS:
			return cat == "weapon"
		FILTER_ARMOR:
			return cat in ["armor", "shield"]
		FILTER_AMMUNITION:
			return cat == "ammunition"
		FILTER_CONSUMABLES:
			return cat == "foodstuff" or key.begins_with("rations")
		FILTER_LIGHT:
			return key in ["torch", "lantern", "candle", "oil_flask"]
		FILTER_POTIONS:
			return key.begins_with("potion_")
		FILTER_SCROLLS:
			return key.begins_with("scroll_")
		FILTER_MAGIC:
			return is_magic
		FILTER_CONTAINERS:
			return key in ["backpack", "sack_small", "sack_large", "chest_small",
					"chest_large", "barrel", "saddlebags"]
		FILTER_TACK:
			return cat == "barding" or key.begins_with("saddle_") or key == "caparison"
		FILTER_TOOLS:
			return cat == "gear" and not Currency.is_coin(key)
	return true


func _item_matches_search(item: Dictionary) -> bool:
	if _current_search.is_empty():
		return true
	var item_name: String = str(item.get("name", "")).to_lower()
	return item_name.find(_current_search) >= 0


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_gold_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		gold_display_clicked.emit(_carrier_id)


func _on_prefs_pressed() -> void:
	prefs_clicked.emit(_carrier_id)


func _on_pickup_all_pressed() -> void:
	pick_up_all_clicked.emit(_carrier_id)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _normalize_item(item) -> Dictionary:
	if item is Dictionary:
		return item
	if item is InventoryItem:
		return {
			"id": item.id,
			"item_key": item.item_key,
			"name": item.name,
			"quantity": item.quantity,
			"encumbrance_units": item.encumbrance_units,
			"slot": item.slot,
			"is_equipped": item.is_equipped,
			"item_category": item.item_category,
			"is_magical": item.is_magical,
			"magical_bonus": item.magical_bonus,
			"container_id": item.container_id,
			"character_id": item.character_id,
			"creature_id": item.creature_id,
			"vehicle_id": item.vehicle_id,
			"uses_remaining": item.uses_remaining,
		}
	return {}


func _is_equipped(item: Dictionary) -> bool:
	var val = item.get("is_equipped", false)
	if val is bool:
		return val
	return int(val) == 1


# ---------------------------------------------------------------------------
# _ItemRow — inner class for draggable item rows
# ---------------------------------------------------------------------------

class _ItemRow extends HBoxContainer:
	var item_data: Dictionary = {}
	var carrier_type: String = ""
	var carrier_id: String = ""
	var indented: bool = false
	var column = null  # reference to parent CarrierColumn

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size.y = 18

		var label := Label.new()
		var qty: int = int(item_data.get("quantity", 1))
		var item_name: String = str(item_data.get("name", "???"))
		if indented:
			item_name = "    " + item_name
		if qty > 1:
			label.text = "%s x%d" % [item_name, qty]
		else:
			label.text = item_name
		label.add_theme_font_size_override("font_size", 11)

		# Color based on item type
		var cat: String = str(item_data.get("item_category", ""))
		var is_magic: bool = int(item_data.get("is_magical", 0)) == 1
		if is_magic:
			label.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
		elif cat == "weapon":
			label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.7))
		elif cat in ["armor", "shield"]:
			label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.85))
		else:
			label.add_theme_color_override("font_color", Color(0.82, 0.76, 0.66))

		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(label)


	func _get_drag_data(_at_position: Vector2) -> Variant:
		var data := {
			"carrier_type": carrier_type,
			"carrier_id": carrier_id,
			"item_id": str(item_data.get("id", "")),
			"quantity": int(item_data.get("quantity", 1)),
			"item_data": item_data,
		}
		# Create drag preview
		var preview := Label.new()
		preview.text = str(item_data.get("name", "???"))
		preview.add_theme_font_size_override("font_size", 11)
		preview.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
		set_drag_preview(preview)
		return data


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			if column != null:
				column.item_context_menu_requested.emit(
					str(item_data.get("id", "")),
					carrier_type, carrier_id,
					get_global_mouse_position())
