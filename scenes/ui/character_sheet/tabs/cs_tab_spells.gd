class_name CSTabSpells
extends VBoxContainer

## Spells tab — spell slots, known spells, memorization status.
## Shows "not a caster" message for non-spellcasting classes.
##
## A Cast button on every active-repertoire row opens the
## OutOfCombatCastFlow on the active scheduler-driven exploration state's HUD
## (Session 3). The button is disabled when the character is mid-combat, when
## no scheduler-driven state is active, or when the caster has no slots
## remaining for the spell's level.

const OutOfCombatCastFlowScript := preload(
	"res://engine/subsystems/spells/out_of_combat_cast_flow.gd")

## target_spec.kind values that resolve cleanly without a click-to-target step
## from the character tab (the tab has no map). Spells with broader target
## specs require the dungeon context menu Cast Spell flow instead — the button
## still opens the picker but a notification will route the player there.
const TAB_AUTO_TARGET_KINDS := [
	"self", "caster_and_radius", "area_from_caster", "touch_creature", "touch_ally",
]


func display(bundle: CharacterBundle, registries: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var character: CharacterData = bundle.character
	if character == null:
		_add_text("No character data.")
		return

	var class_registry: ClassRegistry = registries.get("class_registry")
	var spell_registry: SpellRegistry  = registries.get("spell_registry")

	# Determine if caster
	var casting_power := {}
	if class_registry != null:
		casting_power = class_registry.get_casting_power(character.character_class)

	if casting_power.is_empty():
		_add_text("This character does not cast spells.")
		return

	var tradition: String = casting_power.get("tradition", "arcane")
	_add_section_header("%s Caster" % tradition.capitalize())

	# Spell slots per day
	var slots_by_level: Array = []
	if class_registry != null:
		slots_by_level = class_registry.get_spell_slots(character.character_class, character.level)

	if not slots_by_level.is_empty():
		_add_section_header("Spell Slots Per Day")
		var header_row := HBoxContainer.new()
		header_row.add_theme_constant_override("separation", 4)
		add_child(header_row)
		for i in range(slots_by_level.size()):
			var h := Label.new()
			h.text = "L%d" % (i + 1)
			h.custom_minimum_size = Vector2(32, 0)
			h.add_theme_font_size_override("font_size", 11)
			header_row.add_child(h)

		var slots_row := HBoxContainer.new()
		slots_row.add_theme_constant_override("separation", 4)
		add_child(slots_row)
		for slot_count in slots_by_level:
			var s := Label.new()
			s.text = str(slot_count)
			s.custom_minimum_size = Vector2(32, 0)
			s.add_theme_font_size_override("font_size", 11)
			slots_row.add_child(s)

	add_child(HSeparator.new())

	# Spell repertoire and known formulae display
	if bundle.spells.is_empty():
		_add_text("Spells will be available once you reach casting level.")
		return

	# Build repertoire index for quick lookup.
	var repertoire_keys: Dictionary = {}
	var repertoire_by_level: Dictionary = {}  # int -> Array[Dictionary]
	var max_spell_level := 0
	for spell_dict in bundle.spells:
		var lvl: int = int(spell_dict.get("spell_level", 1))
		if lvl > max_spell_level:
			max_spell_level = lvl
		repertoire_keys[spell_dict.get("spell_key", "")] = true
		if not repertoire_by_level.has(lvl):
			repertoire_by_level[lvl] = []
		repertoire_by_level[lvl].append(spell_dict)

	# Formulas not in active repertoire (arcane only).
	var known_not_active: Array = []
	for formula in bundle.formulas:
		if not repertoire_keys.has(formula.get("spell_key", "")):
			known_not_active.append(formula)

	_add_section_header("Spell Repertoire")

	for lvl in range(1, max_spell_level + 1):
		if not repertoire_by_level.has(lvl):
			continue
		var slots_avail: int = slots_by_level[lvl - 1] if lvl - 1 < slots_by_level.size() else 0
		var expended: int = bundle.expended_slots.get(lvl, 0)

		var level_lbl := Label.new()
		level_lbl.text = "Level %d — %d slots/day (%d expended today)" % [lvl, slots_avail, expended]
		level_lbl.add_theme_font_size_override("font_size", 12)
		add_child(level_lbl)

		for spell_dict in repertoire_by_level[lvl]:
			var spell_key: String = spell_dict.get("spell_key", "")
			var spell_name := spell_key.replace("_", " ").capitalize()
			if spell_registry != null and spell_registry.has_spell(spell_key):
				spell_name = spell_registry.get_spell(spell_key).get("spell_name", spell_name)
			_add_repertoire_row(character, spell_key, spell_name, lvl,
				slots_avail, expended)

	# Arcane casters: show known-but-not-in-active-repertoire spells.
	if not known_not_active.is_empty():
		add_child(HSeparator.new())
		_add_section_header("Spells Known (Not in Active Repertoire)")
		var known_by_level: Dictionary = {}
		for formula in known_not_active:
			var lvl: int = int(formula.get("spell_level", 1))
			if not known_by_level.has(lvl):
				known_by_level[lvl] = []
			known_by_level[lvl].append(formula)
		var known_levels: Array = known_by_level.keys()
		known_levels.sort()
		for lvl in known_levels:
			var level_lbl := Label.new()
			level_lbl.text = "Level %d" % lvl
			level_lbl.add_theme_font_size_override("font_size", 12)
			add_child(level_lbl)
			for formula in known_by_level[lvl]:
				var spell_key: String = formula.get("spell_key", "")
				var spell_name := spell_key.replace("_", " ").capitalize()
				if spell_registry != null and spell_registry.has_spell(spell_key):
					spell_name = spell_registry.get_spell(spell_key).get("spell_name", spell_name)
				var slbl := Label.new()
				slbl.text = "  \u2022 " + spell_name
				slbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				slbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
				add_child(slbl)


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	add_child(lbl)
	add_child(HSeparator.new())


func _add_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)


# ---------------------------------------------------------------------------
# Repertoire row + Cast button (Session 3)
# ---------------------------------------------------------------------------

func _add_repertoire_row(character: CharacterData, spell_key: String,
		spell_name: String, level: int, slots_avail: int, expended: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = "  • " + spell_name
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var btn := Button.new()
	btn.text = "Cast"
	btn.custom_minimum_size = Vector2(60, 24)

	# Gating: slots remaining + scheduler-driven exploration state active.
	var slots_left: int = maxi(0, slots_avail - expended)
	var runner = _find_session_runner()
	if slots_left <= 0:
		btn.disabled = true
		btn.tooltip_text = "No level %d slots remaining today" % level
	elif runner == null:
		btn.disabled = true
		btn.tooltip_text = "Casting only available during exploration"
	elif not _runner_in_castable_state(runner):
		btn.disabled = true
		btn.tooltip_text = "Casting only available outside combat / menus"
	else:
		btn.tooltip_text = "Cast %s (consumes a level %d slot)" % [spell_name, level]

	btn.pressed.connect(_on_cast_pressed.bind(character, spell_key, level))
	row.add_child(btn)


func _on_cast_pressed(character: CharacterData, spell_key: String, level: int) -> void:
	var runner = _find_session_runner()
	if runner == null:
		return
	var ui_layer: Node = _find_ui_parent()
	if ui_layer == null:
		ui_layer = get_tree().current_scene
	var flow = OutOfCombatCastFlowScript.new(runner)
	flow.set_ui_parent(ui_layer)
	# Pre-build a SpellChoice for this row so we skip the picker — the player
	# already chose the spell via the row's Cast button.
	var choice := SpellChoice.new(spell_key, level, false, -1)
	var effect_reg = runner.get_effect_registry()
	if effect_reg == null or not effect_reg.has_effect(spell_key):
		EventBus.notification_requested.emit({
			"type": "info", "category": "ui",
			"title": "Spell not yet implemented",
			"body": "%s has no resolution path yet." % spell_key,
			"duration": 3.0,
		})
		return
	var payload: Dictionary = effect_reg.get_effect_payload(spell_key, false, -1)
	var target_spec: Dictionary = payload.get("target_spec", {})
	var kind: String = target_spec.get("kind", "")
	if not (kind in TAB_AUTO_TARGET_KINDS):
		EventBus.notification_requested.emit({
			"type": "info", "category": "ui",
			"title": "Targeting required",
			"body": "Cast %s from the dungeon map context menu — click a target first." % spell_key,
			"duration": 3.0,
		})
		return
	# Auto-target descriptor for self / caster_and_radius / area_from_caster.
	# touch_creature / touch_ally short-circuits to the caster as the target —
	# the player can use the dungeon context menu to target a different ally.
	var td := TargetDescriptor.new()
	td.kind = kind
	td.target_ids = [character.id]
	flow.commit_with_descriptor(character, choice, td, {character.id: character})


func _find_session_runner() -> Node:
	var node: Node = self
	while node != null:
		var sibling: Node = node.get_node_or_null("SessionRunner")
		if sibling != null and sibling.has_method("get_casting_resolver"):
			return sibling
		var parent_runner: Node = node.get_parent().get_node_or_null("SessionRunner") \
			if node.get_parent() != null else null
		if parent_runner != null and parent_runner.has_method("get_casting_resolver"):
			return parent_runner
		node = node.get_parent()
	return null


func _find_ui_parent() -> Node:
	# Prefer the active scene's HUD for modal stacking.
	var main: Node = get_tree().current_scene
	if main == null:
		return null
	var hud: Node = main.get_node_or_null("DungeonHUD")
	if hud != null:
		return hud
	return main


func _runner_in_castable_state(runner) -> bool:
	if runner == null or not runner.has_method("get_current_state_key"):
		return false
	return runner.get_current_state_key() in ["wilderness", "dungeon", "settlement", "camp"]
