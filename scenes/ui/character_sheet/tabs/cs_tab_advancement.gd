class_name CSTabAdvancement
extends VBoxContainer

## Advancement tab — XP, level progress, prime requisite adjustments, aging, level-up UI.

# Held between begin and finalize for the interactive level-up flow.
var _pending_level_up_result: Dictionary = {}
var _bundle: CharacterBundle
var _registries: Dictionary

# UI nodes for the inline level-up panel (created lazily).
var _level_up_panel: VBoxContainer
var _proficiency_picker: LevelUpProficiencyPicker
var _level_up_choices: Dictionary = {}  # { "proficiencies": [], "spells": [] }


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	_pending_level_up_result = {}
	_level_up_panel = null
	_proficiency_picker = null
	_level_up_choices = {"proficiencies": [], "spells": []}
	_bundle = bundle
	_registries = registries

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	var class_registry: ClassRegistry = registries.get("class_registry")

	# -----------------------------------------------------------------------
	# Level & XP section
	# -----------------------------------------------------------------------
	_add_section_header("Level & XP")

	_add_row("Class:", character.character_class.replace("_", " ").capitalize())
	_add_row("Level:", "%d / %d" % [character.level, character.max_level])
	_add_row("Title:", character.title)
	_add_row("Hit Die:", character.hit_die_type)

	add_child(HSeparator.new())

	var current_xp := character.xp
	var xp_for_next := character.xp_for_next_level

	_add_row("Current XP:", _format_xp(current_xp))
	_add_row("XP for Next Level:", _format_xp(xp_for_next) if character.level < character.max_level else "Max level reached")

	if character.level < character.max_level and xp_for_next > 0:
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

	# Prime requisite XP adjustment.
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

	# -----------------------------------------------------------------------
	# Level-up availability
	# -----------------------------------------------------------------------
	var engine := _make_level_up_engine()
	var eligible := engine.can_level_up(character)
	if eligible and character.level > 0:
		add_child(HSeparator.new())
		_add_level_up_available_ui(character, engine, class_registry)

	# -----------------------------------------------------------------------
	# Aging section
	# -----------------------------------------------------------------------
	add_child(HSeparator.new())
	_add_section_header("Aging")

	if character.current_age > 0:
		var aging_system := AgingSystem.new()
		_add_row("Current Age:", "%d years" % character.current_age)
		_add_row("Age Category:", character.age_category.capitalize().replace("_", " "))
		_add_row("Race:", character.race.capitalize())

		var next_cat_age := aging_system.get_next_category_age(character.race, character.age_category)
		if next_cat_age > 0:
			var years_until := next_cat_age - character.current_age
			if years_until > 0:
				_add_row("Next Category:", "In %d year%s" % [years_until, "s" if years_until != 1 else ""])
			else:
				_add_row("Next Category:", "Imminent")
		else:
			if character.race == "elf":
				_add_row("Next Category:", "Elves do not age past Adult")
			else:
				_add_row("Next Category:", "—")
	else:
		_add_text("  Age not yet set for this character.")

	# Reserve XP stub.
	add_child(HSeparator.new())
	_add_section_header("Reserve XP")
	_add_stub("Reserve XP fund — not yet implemented")


# ---------------------------------------------------------------------------
# Level-Up Available UI (inline)
# ---------------------------------------------------------------------------

func _add_level_up_available_ui(character: CharacterData, engine: LevelUpEngine,
		_class_registry: ClassRegistry) -> void:
	var avail_lbl := Label.new()
	avail_lbl.text = "  Level Up Available!"
	avail_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
	avail_lbl.add_theme_font_size_override("font_size", 13)
	add_child(avail_lbl)

	var level_up_btn := Button.new()
	level_up_btn.text = "Level Up"
	level_up_btn.custom_minimum_size = Vector2(120, 0)
	level_up_btn.pressed.connect(_on_level_up_pressed.bind(character, engine))
	add_child(level_up_btn)

	# Placeholder for the inline level-up panel (built dynamically on press).
	_level_up_panel = VBoxContainer.new()
	_level_up_panel.add_theme_constant_override("separation", 6)
	add_child(_level_up_panel)


func _on_level_up_pressed(character: CharacterData, engine: LevelUpEngine) -> void:
	# Clear any previous level-up panel content.
	if _level_up_panel == null:
		return
	for child in _level_up_panel.get_children():
		child.queue_free()
	_proficiency_picker = null
	_level_up_choices = {"proficiencies": [], "spells": []}

	var result := engine.begin_interactive_level_up(character)
	if result.is_empty():
		return
	if result.get("requires_class_selection", false):
		var lbl := Label.new()
		lbl.text = "  This character requires class selection to advance. (Henchman graduation — not yet implemented.)"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_level_up_panel.add_child(lbl)
		return

	_pending_level_up_result = result
	_build_level_up_summary(result, character, engine)


func _build_level_up_summary(result: Dictionary, character: CharacterData,
		engine: LevelUpEngine) -> void:
	if _level_up_panel == null:
		return

	_level_up_panel.add_child(HSeparator.new())
	_add_header_to(_level_up_panel, "Level Up to %d: %s" % [result["new_level"], result["new_title"]])

	_add_row_to(_level_up_panel, "HP Gained:", "+%d (new max: %d)" % [
		result["hp_gained"], result["new_hp_max"]])
	_add_row_to(_level_up_panel, "New Attack Throw:", "%d+" % result["new_attack_throw"])

	var new_saves: Dictionary = result.get("new_saves", {})
	if not new_saves.is_empty():
		_add_row_to(_level_up_panel, "Saves:",
			"Pet %d / Poi %d / Blt %d / Wnd %d / Spl %d" % [
				int(new_saves.get("petrification", 0)),
				int(new_saves.get("poison_death", 0)),
				int(new_saves.get("blast_breath", 0)),
				int(new_saves.get("staffs_wands", 0)),
				int(new_saves.get("spells", 0)),
			])

	# New class powers.
	var new_powers: Array = result.get("new_powers", [])
	if not new_powers.is_empty():
		_add_row_to(_level_up_panel, "New Powers:", ", ".join(new_powers))

	# Spell slot expansion.
	var old_slots: Array = result.get("old_spell_slots", [])
	var new_slots: Array = result.get("new_spell_slots", [])
	if not new_slots.is_empty():
		_add_row_to(_level_up_panel, "Spell Slots:",
			"%s → %s" % [_format_slots(old_slots), _format_slots(new_slots)])

	# Proficiency slots pending.
	var class_slots: int = result.get("new_class_proficiency_slots", 0)
	var general_slots: int = result.get("new_general_proficiency_slots", 0)
	if class_slots + general_slots > 0:
		var slot_text := ""
		if class_slots > 0:
			slot_text += "%d class" % class_slots
		if general_slots > 0:
			if not slot_text.is_empty():
				slot_text += ", "
			slot_text += "%d general" % general_slots
		_add_row_to(_level_up_panel, "New Proficiency Slots:", slot_text)
		var note := Label.new()
		note.text = "  Choose these proficiencies below before confirming the level-up."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
		note.add_theme_font_size_override("font_size", 11)
		_level_up_panel.add_child(note)

		_proficiency_picker = LevelUpProficiencyPicker.new()
		_proficiency_picker.setup(
			character.character_class,
			character.proficiencies,
			class_slots,
			general_slots,
			_registries.get("class_registry"),
			_registries.get("proficiency_registry")
		)
		_level_up_panel.add_child(_proficiency_picker)

	# Confirm button.
	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm Level Up"
	confirm_btn.pressed.connect(_on_confirm_level_up.bind(character, engine))
	_level_up_panel.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_level_up.bind(character))
	_level_up_panel.add_child(cancel_btn)


func _on_confirm_level_up(character: CharacterData, engine: LevelUpEngine) -> void:
	if _pending_level_up_result.is_empty():
		return
	if _proficiency_picker != null:
		if not _proficiency_picker.is_complete():
			var err := Label.new()
			err.text = "  Spend all new proficiency slots before confirming."
			err.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			if _level_up_panel != null:
				_level_up_panel.add_child(err)
			return
		_level_up_choices["all_proficiencies"] = _proficiency_picker.get_final_proficiencies()
	var ok := engine.finalize_interactive_level_up(character, _pending_level_up_result,
		_level_up_choices)
	if not ok:
		var err := Label.new()
		err.text = "  Error: failed to save level-up. Check logs."
		err.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		if _level_up_panel != null:
			_level_up_panel.add_child(err)
		return
	_pending_level_up_result = {}
	# Redisplay tab with fresh bundle (the character in the bundle is now updated in-memory).
	display(_bundle, _registries)


func _on_cancel_level_up(character: CharacterData) -> void:
	# Undo the in-memory stat changes by reloading from DB.
	if _bundle == null:
		return
	var fresh := CampaignRepository.get_character(character.id)
	if fresh != null:
		_bundle.character = CharacterData.from_dict(fresh)
	_pending_level_up_result = {}
	display(_bundle, _registries)


# ---------------------------------------------------------------------------
# Level-Up Engine factory
# ---------------------------------------------------------------------------

func _make_level_up_engine() -> LevelUpEngine:
	var class_registry: ClassRegistry = _registries.get("class_registry", ClassRegistry.new())
	var power_registry: PowerRegistry  = _registries.get("power_registry",  PowerRegistry.new())
	var prof_registry: ProficiencyRegistry = _registries.get("proficiency_registry")
	return LevelUpEngine.new(class_registry, power_registry, prof_registry)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _format_xp(xp: int) -> String:
	var s := str(xp)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result


func _format_slots(slots: Array) -> String:
	if slots.is_empty():
		return "—"
	var parts: Array[String] = []
	for v in slots:
		parts.append(str(int(v)))
	return "/".join(parts)


func _add_stub(label: String) -> void:
	var lbl := Label.new()
	lbl.text = "  \u2022 %s" % label
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	lbl.add_theme_font_size_override("font_size", 11)
	add_child(lbl)


func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)


func _add_header_to(container: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	container.add_child(lbl)


func _add_row(label_text: String, value_text: String) -> void:
	_add_row_to(self, label_text, value_text)


func _add_row_to(container: Control, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	container.add_child(row)
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
