class_name CSVehicleDetailPanel
extends VBoxContainer

## Vehicle detail panel — shows draft team, capacity, cargo for a cart/wagon.
## Supports hitching/unhitching creatures with reassignment confirmation.


var _vehicle: Dictionary = {}
var _vehicle_bundle: Dictionary = {}

const VEHICLE_TYPE_LABELS := {
	"cart_small": "Small Cart",
	"cart_large": "Large Cart",
	"wagon": "Wagon",
}


func display(vehicle_bundle: Dictionary, _registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	_vehicle_bundle = vehicle_bundle
	_vehicle = vehicle_bundle.get("vehicle", {})
	if _vehicle.is_empty():
		_add_text("No vehicle selected.")
		return

	var item_key: String = str(_vehicle.get("item_key", ""))
	var type_label: String = VEHICLE_TYPE_LABELS.get(item_key, item_key)

	# --- Title ---
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	add_child(title_row)

	var name_edit := LineEdit.new()
	name_edit.text = str(_vehicle.get("name", ""))
	name_edit.placeholder_text = "Name this vehicle..."
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(_on_name_submitted)
	title_row.add_child(name_edit)

	var type_lbl := Label.new()
	type_lbl.text = type_label
	type_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title_row.add_child(type_lbl)

	add_child(HSeparator.new())

	# --- Draft Team ---
	_add_section_header("Draft Team")

	var hitched_creatures: Array = vehicle_bundle.get("hitched_creatures", [])
	var total_equiv := DraftVehicleService.calculate_team_equivalents(hitched_creatures)
	var max_equiv: float = DraftVehicleService.MAX_TEAM_EQUIV.get(item_key, 2.0)

	if hitched_creatures.is_empty():
		_add_text("  No animals hitched.")
	else:
		for creature in hitched_creatures:
			var creature_data: TrainedCreatureData = creature as TrainedCreatureData
			if creature_data == null:
				continue
			var species_equiv: float = DraftVehicleService.DRAFT_EQUIVALENTS.get(creature_data.species_id, 0.0)
			var cname: String = creature_data.name if not creature_data.name.is_empty() else str(creature_data.monster_data.get("name", "?"))

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			add_child(row)

			var lbl := Label.new()
			lbl.text = "  %s (%.1f equiv)" % [cname, species_equiv]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)

			var unhitch_btn := Button.new()
			unhitch_btn.text = "Unhitch"
			unhitch_btn.flat = true
			unhitch_btn.add_theme_font_size_override("font_size", 10)
			unhitch_btn.pressed.connect(_on_unhitch.bind(creature_data.id))
			row.add_child(unhitch_btn)

	# Status
	var sufficient := DraftVehicleService.is_vehicle_mobile(item_key, total_equiv)
	var status_text := "Draft Team: %.1f / %.1f equiv" % [total_equiv, max_equiv]
	status_text += " — %s" % ("Sufficient" if sufficient else "Insufficient")
	var status_color := Color.GREEN_YELLOW if sufficient else Color.ORANGE_RED
	_add_row_colored("Status", status_text, status_color)

	add_child(HSeparator.new())

	# --- Hitch dropdown ---
	var eligible := _get_eligible_creatures()
	if not eligible.is_empty():
		var hitch_row := HBoxContainer.new()
		hitch_row.add_theme_constant_override("separation", 4)
		add_child(hitch_row)

		var hitch_label := Label.new()
		hitch_label.text = "Hitch:"
		hitch_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		hitch_row.add_child(hitch_label)

		var hitch_option := OptionButton.new()
		hitch_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hitch_option.add_item("-- select animal --", 0)
		for i in range(eligible.size()):
			var entry: Dictionary = eligible[i]
			var label: String = entry.get("label", "?")
			hitch_option.add_item(label, i + 1)
		hitch_option.item_selected.connect(_on_hitch_selected.bind(eligible))
		hitch_row.add_child(hitch_option)

		add_child(HSeparator.new())

	# --- Capacity ---
	_add_section_header("Capacity")

	var items: Array = vehicle_bundle.get("items", [])
	var load_units := DraftVehicleService.calculate_vehicle_load_units(items)
	var load_stone := load_units / 1000.0
	var capacity := DraftVehicleService.get_vehicle_capacity(item_key, total_equiv)

	if capacity.is_empty():
		_add_row("Capacity", "No draft team — vehicle immobile")
	else:
		var cap_normal: int = capacity.get("load_normal", 0)
		var cap_max: int = capacity.get("load_max", 0)
		var cap_text := "%.0f / %d stone (normal), %d stone (max)" % [load_stone, cap_normal, cap_max]
		_add_row("Load", cap_text)
		_add_row("Speed", "%d' / %d' per turn" % [capacity.get("speed_normal", 0), capacity.get("speed_loaded", 0)])

		if load_units > cap_max * 1000:
			var warn := Label.new()
			warn.text = "  WARNING: Vehicle is overloaded!"
			warn.add_theme_color_override("font_color", Color.RED)
			add_child(warn)

	add_child(HSeparator.new())

	# --- Cargo ---
	_add_section_header("Cargo")
	if items.is_empty():
		_add_text("  (empty)")
	else:
		for item in items:
			_render_cargo_row(item)


# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_name_submitted(new_name: String) -> void:
	var vehicle_id: String = str(_vehicle.get("id", ""))
	if vehicle_id.is_empty():
		return
	CampaignRepository.update_draft_vehicle_name(vehicle_id, new_name)
	EventBus.vehicle_changed.emit(GameState.party_id, vehicle_id)


func _on_unhitch(creature_id: String) -> void:
	var vehicle_id: String = str(_vehicle.get("id", ""))
	if vehicle_id.is_empty():
		return
	var hitched_json: String = str(_vehicle.get("hitched_creatures", "[]"))
	var hitched = JSON.parse_string(hitched_json)
	if not hitched is Array:
		return
	hitched.erase(creature_id)
	CampaignRepository.update_draft_vehicle_hitch(vehicle_id, JSON.stringify(hitched))
	EventBus.vehicle_hitch_changed.emit(vehicle_id)


func _on_hitch_selected(index: int, eligible: Array) -> void:
	if index <= 0:
		return
	var entry_index := index - 1
	if entry_index >= eligible.size():
		return
	var entry: Dictionary = eligible[entry_index]
	var creature_id: String = entry.get("creature_id", "")
	var already_hitched_to: String = entry.get("already_hitched_to", "")

	if not already_hitched_to.is_empty():
		# Show confirmation dialog for reassignment.
		var old_name: String = entry.get("old_vehicle_name", already_hitched_to)
		var dialog := ConfirmationDialog.new()
		dialog.dialog_text = "Reassign from %s?" % old_name
		dialog.confirmed.connect(_do_hitch.bind(creature_id, already_hitched_to))
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered()
	else:
		_do_hitch(creature_id, "")


func _do_hitch(creature_id: String, unhitch_from_vehicle_id: String) -> void:
	# Unhitch from old vehicle first.
	if not unhitch_from_vehicle_id.is_empty():
		var old_vehicle := CampaignRepository.get_draft_vehicle(unhitch_from_vehicle_id)
		if not old_vehicle.is_empty():
			var old_hitched = JSON.parse_string(str(old_vehicle.get("hitched_creatures", "[]")))
			if old_hitched is Array:
				old_hitched.erase(creature_id)
				CampaignRepository.update_draft_vehicle_hitch(unhitch_from_vehicle_id, JSON.stringify(old_hitched))
				EventBus.vehicle_hitch_changed.emit(unhitch_from_vehicle_id)

	# Hitch to this vehicle.
	var vehicle_id: String = str(_vehicle.get("id", ""))
	var hitched_json: String = str(_vehicle.get("hitched_creatures", "[]"))
	var hitched = JSON.parse_string(hitched_json)
	if not hitched is Array:
		hitched = []
	if creature_id not in hitched:
		hitched.append(creature_id)
	CampaignRepository.update_draft_vehicle_hitch(vehicle_id, JSON.stringify(hitched))
	EventBus.vehicle_hitch_changed.emit(vehicle_id)


# ---------------------------------------------------------------------------
# Eligible creatures for hitching
# ---------------------------------------------------------------------------

func _get_eligible_creatures() -> Array:
	var all_creatures: Array = _vehicle_bundle.get("all_creatures", [])
	var all_vehicles: Array = _vehicle_bundle.get("all_vehicles", [])
	var vehicle_id: String = str(_vehicle.get("id", ""))
	var result: Array = []

	for creature in all_creatures:
		var creature_data: TrainedCreatureData = creature as TrainedCreatureData
		if creature_data == null:
			continue
		if not creature_data.is_alive:
			continue
		if creature_data.get_equipped_saddle_type() != "draft":
			continue

		# Check if already hitched to this vehicle.
		var this_hitched_json: String = str(_vehicle.get("hitched_creatures", "[]"))
		var this_hitched = JSON.parse_string(this_hitched_json)
		if this_hitched is Array and creature_data.id in this_hitched:
			continue

		# Check if hitched elsewhere.
		var already_hitched_to := ""
		var old_vehicle_name := ""
		for v in all_vehicles:
			var vid: String = str(v.get("id", ""))
			if vid == vehicle_id:
				continue
			var h_json: String = str(v.get("hitched_creatures", "[]"))
			var h = JSON.parse_string(h_json)
			if h is Array and creature_data.id in h:
				already_hitched_to = vid
				old_vehicle_name = str(v.get("name", vid))
				break

		var cname: String = creature_data.name if not creature_data.name.is_empty() else str(creature_data.monster_data.get("name", "?"))
		var label: String = cname
		if not already_hitched_to.is_empty():
			label = "* %s (from %s)" % [cname, old_vehicle_name]

		result.append({
			"creature_id": creature_data.id,
			"label": label,
			"already_hitched_to": already_hitched_to,
			"old_vehicle_name": old_vehicle_name,
		})

	return result


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

func _render_cargo_row(item) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var name_str: String = str(item.get("name", "?")) if item is Dictionary else item.name
	var qty: int = int(item.get("quantity", 1)) if item is Dictionary else item.quantity
	if qty > 1:
		name_str = "%s (x%d)" % [name_str, qty]

	var lbl := Label.new()
	lbl.text = "  " + name_str
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var enc: int = int(item.get("encumbrance_units", 0)) if item is Dictionary else item.encumbrance_units
	enc *= qty
	var enc_lbl := Label.new()
	enc_lbl.text = "%.1f st" % (enc / 1000.0)
	enc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(enc_lbl)


func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	add_child(lbl)


func _add_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)


func _add_row_colored(label_text: String, value_text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.add_theme_color_override("font_color", color)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	add_child(lbl)
