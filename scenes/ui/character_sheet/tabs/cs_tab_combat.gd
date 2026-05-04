class_name CSTabCombat
extends VBoxContainer

## Combat tab — HP, AC breakdown, attack throws, movement, cleave, initiative.
##
## AC configurations are computed from equipped inventory items + DEX modifier.
## Attack-vs-AC table uses ACKS descending AC convention:
##   attack_throw field = d20 roll needed to hit AC 0.
##   To hit AC N: need (attack_throw - N)+.


func display(bundle: CharacterBundle, _registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	# -- Hit Points --
	_add_section_header("Hit Points")
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	add_child(hp_row)
	var hp_key := Label.new()
	hp_key.text = "HP:"
	hp_key.custom_minimum_size = Vector2(120, 0)
	hp_row.add_child(hp_key)
	var hp_val := Label.new()
	hp_val.text = StatReadout.format_hp(character.hp_current, character.hp_max)
	if character.hp_max > 0:
		hp_val.add_theme_color_override(
			"font_color",
			StatReadout.hp_color_for(character.hp_current, character.hp_max))
	hp_row.add_child(hp_val)
	if character.temp_hp > 0:
		_add_row("Temp HP:", "+%d" % character.temp_hp)

	add_child(HSeparator.new())

	# -- Armor Class --
	_add_section_header("Armor Class")

	var dex_mod := CharacterData.ability_modifier(character.dexterity)

	## Decompose equipped armor and shield from inventory
	var armor_bonus := 0
	var armor_mag := 0
	var armor_name := ""
	var shield_bonus := 0
	var shield_mag := 0
	var shield_name := ""

	for item_dict in bundle.inventory:
		var equipped: bool = bool(int(item_dict.get("is_equipped", 0)))
		if not equipped:
			continue
		var cat: String = item_dict.get("item_category", "")
		var ac_bonus: int = int(item_dict.get("armor_ac_bonus", 0))
		var mag: int = int(item_dict.get("magical_bonus", 0))
		var iname: String = item_dict.get("name", item_dict.get("item_key", ""))
		if cat == "armor":
			armor_bonus = ac_bonus
			armor_mag = mag
			armor_name = iname
		elif cat == "shield":
			shield_bonus = ac_bonus if ac_bonus > 0 else 1
			shield_mag = mag
			shield_name = iname

	## Show effective AC first (authoritative from character data + modifiers)
	var eff_ac := character.get_effective_ac()
	_add_row("Current AC:", "%d  (effective)" % eff_ac)

	## Three configurations
	var ac_with_shield := armor_bonus + armor_mag + shield_bonus + shield_mag + dex_mod
	var ac_no_shield   := armor_bonus + armor_mag + dex_mod
	var ac_unarmored   := dex_mod

	if not armor_name.is_empty():
		_add_row("Armor + Shield:" if not shield_name.is_empty() else "Armored:", "%d+" % ac_with_shield if not shield_name.is_empty() else "%d+" % ac_no_shield)
		if not shield_name.is_empty():
			_add_row("Armor, no Shield:", "%d+" % ac_no_shield)
		_add_row("Unarmored:", "%d+" % ac_unarmored)
	else:
		_add_row("Unarmored:", "%d+" % ac_unarmored)
		if not shield_name.is_empty():
			_add_row("Shield only:", "%d+" % (shield_bonus + shield_mag + dex_mod))

	## AC component breakdown
	if not armor_name.is_empty():
		_add_row("  Armor:", "%s  (+%d%s)" % [armor_name, armor_bonus, " +%d mag" % armor_mag if armor_mag > 0 else ""])
	if not shield_name.is_empty():
		_add_row("  Shield:", "%s  (+%d%s)" % [shield_name, shield_bonus, " +%d mag" % shield_mag if shield_mag > 0 else ""])
	var dex_str := "+%d" % dex_mod if dex_mod >= 0 else str(dex_mod)
	_add_row("  DEX modifier:", dex_str)

	add_child(HSeparator.new())

	# -- Attack Throw --
	_add_section_header("Attack")

	var base_at := character.attack_throw
	var eff_at  := character.get_effective_attack_throw()
	_add_row("Attack Throw:", "%d+" % eff_at + ("  (base %d+)" % base_at if eff_at != base_at else ""))

	## Attack vs AC table
	## ACKS rule: d20 roll needed = attack_throw + AC (ascending AC).
	## AT 10+ vs AC 0 → need 10. AT 10+ vs AC 5 → need 15. AT 4+ vs AC 4 → need 8.
	var table_lbl := Label.new()
	table_lbl.text = "To-Hit by AC (d20 needed):"
	table_lbl.add_theme_font_size_override("font_size", 11)
	add_child(table_lbl)

	var grid := GridContainer.new()
	grid.columns = 14
	grid.add_theme_constant_override("h_separation", 6)
	add_child(grid)

	## Header row: AC values 0–9 and -1 to -3
	for ac in range(0, 10):
		var hdr := Label.new()
		hdr.text = "AC%d" % ac
		hdr.add_theme_font_size_override("font_size", 10)
		hdr.custom_minimum_size = Vector2(30, 0)
		grid.add_child(hdr)
	for ac in range(-1, -5, -1):
		var hdr := Label.new()
		hdr.text = "AC%d" % ac
		hdr.add_theme_font_size_override("font_size", 10)
		hdr.custom_minimum_size = Vector2(34, 0)
		grid.add_child(hdr)

	## Roll-needed row: needed = attack_throw + AC, clamped 2–20
	for ac in range(0, 10):
		var needed := clampi(eff_at + ac, 2, 20)
		var cell := Label.new()
		cell.text = "%d+" % needed
		cell.add_theme_font_size_override("font_size", 10)
		cell.custom_minimum_size = Vector2(30, 0)
		grid.add_child(cell)
	for ac in range(-1, -5, -1):
		var needed := clampi(eff_at + ac, 2, 20)
		var cell := Label.new()
		cell.text = "%d+" % needed
		cell.add_theme_font_size_override("font_size", 10)
		cell.custom_minimum_size = Vector2(34, 0)
		grid.add_child(cell)

	add_child(HSeparator.new())

	# -- Initiative --
	_add_section_header("Initiative & Movement")

	var init_mod := dex_mod  ## ACKS: DEX modifier applies to initiative
	var init_str := "+%d" % init_mod if init_mod >= 0 else str(init_mod)
	_add_row("Initiative Modifier:", init_str)

	## Cleave count
	var cleave_count := 0
	match character.combat_progression:
		"fighter":
			cleave_count = character.level
		"cleric":
			cleave_count = 0  ## Clerics do not cleave per ACKS 1e
		"thief", "mage":
			cleave_count = 0
	_add_row("Cleave Count:", str(cleave_count) if cleave_count > 0 else "None")

	add_child(HSeparator.new())

	# -- Movement --
	_add_section_header("Movement")

	var enc := EncumbranceCalculator.calculate_encumbrance(bundle.inventory)
	var total_stone: float = enc.get("total_stone", 0.0)
	var explore: int = enc.get("exploration_speed", 120)
	var combat_spd: int = int(explore / 3)
	var running_spd: int = explore

	_add_row("Encumbrance:", "%.1f stone" % total_stone)
	_add_row("Exploration:", "%d' / turn" % explore)
	_add_row("Combat:", "%d' / round" % combat_spd)
	_add_row("Running:", "%d' / round" % running_spd)

	var eff_move := character.get_effective_movement()
	if eff_move != explore:
		_add_row("Effective Exploration:", "%d' / turn  (modified)" % eff_move)

	add_child(HSeparator.new())

	# -- Hit Die --
	_add_row("Hit Die:", character.hit_die_type)


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)


func _add_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(160, 0)
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(val)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
