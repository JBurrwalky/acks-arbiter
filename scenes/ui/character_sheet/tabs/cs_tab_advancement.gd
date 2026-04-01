class_name CSTabAdvancement
extends VBoxContainer

## Advancement tab — XP, level progress, prime requisite adjustments.


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	var class_registry: ClassRegistry = registries.get("class_registry")

	_add_section_header("Level & XP")

	_add_row("Class:", character.character_class.replace("_", " ").capitalize())
	_add_row("Level:", "%d / %d" % [character.level, character.max_level])
	_add_row("Title:", character.title)
	_add_row("Hit Die:", character.hit_die_type)

	add_child(HSeparator.new())

	# XP values
	var current_xp := character.xp
	var xp_for_next := character.xp_for_next_level

	_add_row("Current XP:", _format_xp(current_xp))
	_add_row("XP for Next Level:", _format_xp(xp_for_next) if character.level < character.max_level else "Max level reached")

	# XP progress bar
	if character.level < character.max_level and xp_for_next > 0:
		## Determine XP at start of current level
		var xp_this_level := 0
		if class_registry != null:
			xp_this_level = class_registry.get_xp_for_level(character.character_class, character.level)

		var bar := ProgressBar.new()
		bar.min_value = xp_this_level
		bar.max_value = xp_for_next
		bar.value = clampi(current_xp, xp_this_level, xp_for_next)
		bar.custom_minimum_size = Vector2(0, 20)
		bar.show_percentage = true
		add_child(bar)

		var remaining := xp_for_next - current_xp
		if remaining > 0:
			_add_row("XP Needed:", _format_xp(remaining))

	add_child(HSeparator.new())

	# Prime requisite XP adjustment
	var xp_adj := character.xp_adjustment_percent
	var adj_color := Color.WHITE
	if xp_adj > 0:
		adj_color = Color(0.2, 0.75, 0.2)
	elif xp_adj < 0:
		adj_color = Color(0.85, 0.35, 0.15)

	var adj_row := HBoxContainer.new()
	adj_row.add_theme_constant_override("separation", 8)
	add_child(adj_row)
	var adj_key := Label.new()
	adj_key.text = "XP Adjustment:"
	adj_key.custom_minimum_size = Vector2(160, 0)
	adj_row.add_child(adj_key)
	var adj_val := Label.new()
	adj_val.text = "%+d%%" % xp_adj
	adj_val.add_theme_color_override("font_color", adj_color)
	adj_row.add_child(adj_val)

	add_child(HSeparator.new())

	# Stubs for systems not yet built
	_add_section_header("Pending Systems")
	_add_stub("Reserve XP")
	_add_stub("Adventure Pool Share")
	_add_stub("Downtime & Carousing XP")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _format_xp(xp: int) -> String:
	## Format XP with comma separator (e.g., 12,000).
	var s := str(xp)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result


func _add_stub(label: String) -> void:
	var lbl := Label.new()
	lbl.text = "  \u2022 %s — not yet implemented" % label
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	lbl.add_theme_font_size_override("font_size", 11)
	add_child(lbl)


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
