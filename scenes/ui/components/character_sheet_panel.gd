class_name CharacterSheetPanel
extends PanelContainer

## CharacterSheetPanel — reusable read-only character summary.
##
## Accepts the creation_state Dictionary from CharacterCreationScreen and renders
## a full character sheet. Used in Step 9 (Finalize) and can be reused elsewhere.
##
## Call display(state) to render. Clears and rebuilds every call.

const PORTRAIT_DISPLAY_SIZE := Vector2(512, 512)


var _class_registry: ClassRegistry
var _scroll: ScrollContainer
var _content: VBoxContainer


func _ready() -> void:
	UiSurfaceStyles.apply_textured_panel(self)
	_build_skeleton()


func setup_registry(class_registry: ClassRegistry) -> void:
	_class_registry = class_registry


func display(state: Dictionary) -> void:
	## Render the full character sheet from creation_state.
	for child in _content.get_children():
		child.queue_free()

	var character: CharacterData = state.get("character")
	if character == null:
		_add_text("No character data yet.")
		return

	var class_id: String = state.get("class_id", character.character_class)
	var cls: Dictionary = {}
	if _class_registry != null:
		cls = _class_registry.get_class_def(class_id)

	_render_portrait(state)
	_render_identity(character, cls, state)
	_render_ability_scores(character)
	_render_combat(character)
	_render_saving_throws(character)
	_render_proficiencies(state)
	_render_languages(character, state)
	_render_spells(state)
	_render_equipment(state)


# ---------------------------------------------------------------------------
# Skeleton
# ---------------------------------------------------------------------------

func _build_skeleton() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)


# ---------------------------------------------------------------------------
# Section renderers
# ---------------------------------------------------------------------------

func _render_portrait(state: Dictionary) -> void:
	var portrait_id: String = state.get("portrait_id", "")
	if portrait_id.is_empty():
		return

	var texture: Texture2D = _load_portrait(portrait_id)
	if texture == null:
		return

	var img_rect := TextureRect.new()
	img_rect.texture = texture
	# Ignore the portrait's native imported size so 1024x1024 source art
	# renders inside the intended UI frame instead of expanding the layout.
	img_rect.custom_minimum_size = PORTRAIT_DISPLAY_SIZE
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	img_rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_content.add_child(img_rect)


func _load_portrait(portrait_id: String) -> Texture2D:
	## Try user://portraits/ first, then res://assets/portraits/.
	var user_path := "user://portraits/%s.png" % portrait_id
	if FileAccess.file_exists(user_path):
		var img := Image.load_from_file(user_path)
		if img != null:
			return ImageTexture.create_from_image(img)
	var res_path := "res://assets/portraits/%s.png" % portrait_id
	if ResourceLoader.exists(res_path):
		return load(res_path) as Texture2D
	return null


func _render_identity(character: CharacterData, cls: Dictionary, state: Dictionary) -> void:
	_add_section_header("Identity")

	var class_name_str: String = cls.get("class_name", character.character_class)
	if _class_registry != null:
		class_name_str = _class_registry.get_class_display_name(
			state.get("class_id", character.character_class),
			character.sex
		)
	_add_row("Name:", character.name if not character.name.is_empty() else "(unnamed)")
	_add_row("Class:", "%s (Level %d)" % [class_name_str, character.level])
	_add_row("Race:", character.race.capitalize())
	_add_row("Title:", character.title)
	_add_row("Alignment:", character.alignment.capitalize())
	_add_row("Hit Points:", "%d" % character.hp_max)
	_add_row("XP Adjustment:", "%+d%%" % character.xp_adjustment_percent)


func _render_ability_scores(character: CharacterData) -> void:
	_add_section_header("Ability Scores")

	var abilities: Array = [
		["STR", character.strength],
		["INT", character.intelligence],
		["WIS", character.wisdom],
		["DEX", character.dexterity],
		["CON", character.constitution],
		["CHA", character.charisma],
	]
	for entry in abilities:
		var ability: String = entry[0]
		var score: int = entry[1]
		var mod := CharacterData.ability_modifier(score)
		var mod_str := ("+%d" % mod) if mod >= 0 else str(mod)
		_add_row(ability + ":", "%d  (%s)" % [score, mod_str])


func _render_combat(character: CharacterData) -> void:
	_add_section_header("Combat")

	_add_row("Attack Throw:", "%d+" % character.attack_throw)

	# Base AC: 10 + DEX mod + armor/shield (derived from inventory)
	var dex_mod := CharacterData.ability_modifier(character.dexterity)
	_add_row("Base AC:", "%d  (10 + DEX %+d; add armor)" % [10 + dex_mod, dex_mod])


func _render_saving_throws(character: CharacterData) -> void:
	_add_section_header("Saving Throws")
	_add_row("Petrification / Paralysis:", "%d+" % character.save_petrification)
	_add_row("Poison / Death:", "%d+" % character.save_poison_death)
	_add_row("Blast / Breath:", "%d+" % character.save_blast_breath)
	_add_row("Staffs / Wands:", "%d+" % character.save_staffs_wands)
	_add_row("Spells:", "%d+" % character.save_spells)


func _render_proficiencies(state: Dictionary) -> void:
	var profs: Array = state.get("proficiencies", [])
	if profs.is_empty():
		return
	_add_section_header("Proficiencies")
	for p in profs:
		var key: String = p.get("proficiency_key", "")
		var rank: int = int(p.get("rank", 1))
		var spec: String = p.get("specialization", "")
		var display := key.replace("_", " ").capitalize()
		if rank > 1:
			display += " (Rank %d)" % rank
		if not spec.is_empty():
			display += " [%s]" % spec
		_add_bullet(display)


func _render_languages(character: CharacterData, state: Dictionary) -> void:
	## Show granted languages from the character record (JSON array) or
	## from creation_state["language_bonus_picks"] if still in the wizard.
	##
	## Priority: character.languages JSON field (authoritative after finalize).
	## Fallback: assemble from creation_state for live preview in the wizard.
	var lang_list: Array = []

	var raw: String = character.languages if character != null else "[]"
	if raw != "[]" and not raw.is_empty():
		lang_list = CharacterData.parse_languages_json(raw)

	# During character creation, character.languages may not yet be populated.
	# Assemble a preview from state instead.
	if lang_list.is_empty():
		lang_list = CharacterData.get_default_languages_for_race(character.race) \
			if character != null else ["common"]
		var bonus: Array = state.get("language_bonus_picks", [])
		for pick in bonus:
			var pick_str: String = pick as String
			if not pick_str.is_empty() and pick_str not in lang_list:
				lang_list.append(pick_str)
		lang_list = CharacterData.sanitize_language_ids(lang_list)

	if lang_list.is_empty():
		return

	_add_section_header("Languages")
	for lang_id in lang_list:
		_add_bullet(lang_id.replace("_", " ").capitalize())


func _render_spells(state: Dictionary) -> void:
	var spells: Array = state.get("spells", [])
	if spells.is_empty():
		return
	_add_section_header("Starting Spells")
	for s in spells:
		var key: String = s.get("spell_key", "")
		var level: int = int(s.get("spell_level", 1))
		_add_bullet("%s (Level %d)" % [key.replace("_", " ").capitalize(), level])


func _render_equipment(state: Dictionary) -> void:
	var inventory: Array = state.get("inventory", [])
	if inventory.is_empty():
		return
	_add_section_header("Equipment")

	var enc := EncumbranceCalculator.calculate_encumbrance(inventory)
	_add_row("Encumbrance:", "%.1f stone  (%d'/turn)" % [
		enc.get("total_stone", 0.0), enc.get("exploration_speed", 120)])

	for item in inventory:
		var name_str: String = item.get("name", item.get("item_key", "?"))
		var qty: int = int(item.get("quantity", 1))
		if qty > 1:
			_add_bullet("%s ×%d" % [name_str, qty])
		else:
			_add_bullet(name_str)

	var gold_cp: int = state.get("gold_remaining_cp", 0)
	if gold_cp > 0:
		_add_row("Gold Remaining:", Currency.format_cost(gold_cp))


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	_content.add_child(lbl)
	_content.add_child(HSeparator.new())


func _add_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(160, 0)
	row.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(val)


func _add_bullet(text: String) -> void:
	var lbl := Label.new()
	lbl.text = "  • " + text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(lbl)


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(lbl)
