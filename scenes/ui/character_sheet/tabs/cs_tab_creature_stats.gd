class_name CSTabCreatureStats
extends VBoxContainer

## Creature stats tab — shows monster stat block, encumbrance, handler info,
## and mount/draft status for a trained creature.


var _creature: TrainedCreatureData = null


func display(creature: TrainedCreatureData, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	_creature = creature
	if creature == null or creature.monster_data.is_empty():
		_add_text("No creature data.")
		return

	# --- Identity ---
	_add_section_header("Identity")

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	add_child(name_row)

	var name_edit := LineEdit.new()
	name_edit.text = creature.name if not creature.name.is_empty() else ""
	name_edit.placeholder_text = "Name this creature..."
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(_on_name_submitted)
	name_row.add_child(name_edit)

	var species_name: String = creature.monster_data.get("name", "Unknown")
	var variant: String = str(creature.monster_data.get("variant", ""))
	var species_label := species_name
	if not variant.is_empty() and variant != "null":
		species_label = "%s (%s)" % [species_name, variant]
	_add_row("Species", species_label)
	_add_row("Role", _format_role(creature.role))

	add_child(HSeparator.new())

	# --- Combat Statistics ---
	_add_section_header("Combat Statistics")

	var base_ac := creature.get_base_armor_class()
	var total_ac := creature.get_armor_class()
	var ac_text := str(total_ac)
	if total_ac != base_ac:
		ac_text = "%d (base %d + %d barding)" % [total_ac, base_ac, total_ac - base_ac]
	_add_row("AC", ac_text)

	var hd: Dictionary = creature.monster_data.get("hit_dice", {})
	var hd_base: int = int(hd.get("base", 1))
	var hd_mod: int = int(hd.get("modifier", 0))
	var hd_text := str(hd_base)
	if hd_mod > 0:
		hd_text += "+%d" % hd_mod
	elif hd_mod < 0:
		hd_text += str(hd_mod)
	_add_row("HD", hd_text)

	# HP with color coding
	var hp_text := "%d / %d" % [creature.hp_current, creature.hp_max]
	var hp_color := Color.WHITE
	if creature.hp_max > 0:
		var ratio := float(creature.hp_current) / float(creature.hp_max)
		if ratio <= 0.0:
			hp_color = Color.RED
		elif ratio < 0.25:
			hp_color = Color.ORANGE_RED
		elif ratio < 0.5:
			hp_color = Color.YELLOW
		else:
			hp_color = Color.GREEN_YELLOW
	_add_row_colored("HP", hp_text, hp_color)

	# Attacks
	var routines: Array = creature.get_attack_routines()
	if not routines.is_empty():
		var atk_parts: Array = []
		for routine in routines:
			for atk in routine.get("attacks", []):
				var count: int = int(atk.get("count", 1))
				var atype: String = str(atk.get("attack_type", "attack"))
				var dmg: String = str(atk.get("damage", "?"))
				if count > 1:
					atk_parts.append("%d %ss (%s)" % [count, atype, dmg])
				else:
					atk_parts.append("%s (%s)" % [atype, dmg])
		_add_row("Attacks", ", ".join(atk_parts))

	# Movement
	var base_mv := creature.get_base_movement()
	var eff_mv := creature.get_effective_movement()
	var mv_text := "%d'" % eff_mv
	if eff_mv != base_mv:
		mv_text = "%d' (base %d', overloaded)" % [eff_mv, base_mv]
	_add_row("Movement", mv_text)

	_add_row("Morale", "%+d" % creature.morale)

	var save_as: Dictionary = creature.get_save_as()
	if not save_as.is_empty():
		_add_row("Save As", "%s %d" % [save_as.get("class", "?"), save_as.get("level", 0)])

	add_child(HSeparator.new())

	# --- Encumbrance ---
	_add_section_header("Encumbrance")
	var load_stone := creature.get_current_load_stone()
	var cap_normal := creature.get_effective_capacity_normal()
	var cap_max := creature.get_effective_capacity_max()
	var enc_text := "%d / %d stone" % [load_stone, cap_normal]
	if cap_max > 0 and cap_max != cap_normal:
		enc_text += " (max %d)" % cap_max
	if creature.is_overloaded():
		enc_text += "  [OVERLOADED]"
	_add_row("Load", enc_text)

	add_child(HSeparator.new())

	# --- Handlers ---
	_add_section_header("Handlers")
	var handler_name := _lookup_character_name(creature.handler_id)
	_add_row("Handler", handler_name if not handler_name.is_empty() else "-- none --")

	# Show handler tiers for all party members.
	var party_chars: Array = registries.get("party_characters", [])
	if not party_chars.is_empty():
		var tiers := HandlerEligibility.get_party_handler_tiers(party_chars, creature)
		for entry in tiers:
			var tier_color := Color.GREEN_YELLOW
			if entry["tier"] == HandlerEligibility.Tier.INTRODUCED:
				tier_color = Color.YELLOW
			elif entry["tier"] == HandlerEligibility.Tier.UNKNOWN:
				tier_color = Color(0.5, 0.5, 0.5)
			_add_row_colored("  " + str(entry["character_name"]), str(entry["tier_label"]), tier_color)
	elif not creature.introduced_handlers.is_empty():
		var intro_names: Array = []
		for cid in creature.introduced_handlers:
			var n := _lookup_character_name(str(cid))
			if not n.is_empty():
				intro_names.append(n)
		if not intro_names.is_empty():
			_add_row("Introduced", ", ".join(intro_names))

	add_child(HSeparator.new())

	# --- Status ---
	_add_section_header("Status")
	if creature.role in ["M", "WM"]:
		_add_row("Mount Type", "War Mount" if creature.role == "WM" else "Riding Mount")
		# Rider lookup deferred — data model for who is riding whom not yet implemented
	if creature.role in ["WB", "D"]:
		var hitched_to := _find_hitched_vehicle(creature.id)
		_add_row("Hitched To", hitched_to if not hitched_to.is_empty() else "-- none --")
	if not creature.is_alive:
		_add_row("Status", "DEAD")

	add_child(HSeparator.new())

	# --- Training ---
	_add_section_header("Training")
	if creature.tricks_known.is_empty():
		_add_row("Tricks", "-- none --")
	else:
		var tricks_text := ", ".join(creature.tricks_known)
		_add_row("Tricks", "%s (%d/%d)" % [tricks_text, creature.tricks_known.size(), creature.trick_limit])


# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_name_submitted(new_name: String) -> void:
	if _creature == null or _creature.id.is_empty():
		return
	CampaignRepository.update_trained_creature(_creature.id, {"name": new_name})
	_creature.name = new_name


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _format_role(role: String) -> String:
	match role:
		"M":  return "Mount"
		"WM": return "War Mount"
		"G":  return "Guard"
		"H":  return "Hunter"
		"D":  return "Drover"
		"L":  return "Livestock"
		"WB": return "Workbeast"
		_:    return role


func _lookup_character_name(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		return "(unknown)"
	return str(row.get("name", "(unnamed)"))


func _find_hitched_vehicle(creature_id: String) -> String:
	var vehicles := CampaignRepository.get_draft_vehicles_for_party(GameState.party_id)
	for v in vehicles:
		var hitched_json: String = str(v.get("hitched_creatures", "[]"))
		var hitched = JSON.parse_string(hitched_json)
		if hitched is Array and creature_id in hitched:
			var vname: String = str(v.get("name", ""))
			return vname if not vname.is_empty() else str(v.get("item_key", "vehicle"))
	return ""


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
