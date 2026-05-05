class_name DeclarationOverlay
extends PanelContainer

## Modal overlay at combat round start for PC action declarations.
##
## Lists all alive PCs with per-PC dropdown for:
## - No Declaration (default)
## - Fighting Withdrawal
## - Full Retreat
## - Set Against Charge
## - Cast Spell  (Session 2 — opens SpellPickerPanel inline)
##
## Cast Spell is mutually exclusive with the three defensive movement options
## (`acore_spellcaster_rules` line 31: "A spellcaster may take no other
## actions in the same round the caster intends to cast"). The dropdown
## ALWAYS shows Cast Spell; greys it out with a tooltip when the caster has
## no spell slots, is silenced/gagged/hand-bound, or is not a caster.
##
## When Cast Spell is picked, the overlay opens SpellPickerPanel; on commit,
## the declaration record stores `{combatant_id, declaration_type: "cast_spell",
## spell_choice: SpellChoice}`.
##
## Emits declarations_complete when the player confirms all declarations.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player clicks Confirm. Array of declaration records.
## Each record: {combatant_id, declaration_type, spell_choice (only for cast_spell)}.
## declaration_type values: "" | "fighting_withdrawal" | "full_retreat"
##                          | "set_against_charge" | "cast_spell"
signal declarations_complete(declarations: Array)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DECLARATION_OPTIONS := [
	{"id": "", "label": "None"},
	{"id": "fighting_withdrawal", "label": "Fighting Withdrawal"},
	{"id": "full_retreat", "label": "Full Retreat"},
	{"id": "set_against_charge", "label": "Set vs Charge"},
	{"id": "cast_spell", "label": "Cast Spell..."},
]

## Path to the SpellPickerPanel scene, instantiated on demand when a PC's
## Cast Spell option is picked.
const SPELL_PICKER_SCENE := preload("res://scenes/ui/spells/spell_picker_panel.tscn")
const DISJUNCTIVE_MODAL_SCENE := preload("res://scenes/ui/spells/disjunctive_branch_modal.tscn")


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Array of {combatant_id, display_name} for alive PCs.
var _pc_list: Array = []

## {combatant_id -> selected declaration_type string}
var _declarations: Dictionary = {}

## {combatant_id -> SpellChoice} when declaration_type == "cast_spell"
var _spell_choices: Dictionary = {}

## Optional dependency injection — set by CombatController before set_pc_list.
## Required for the Cast Spell flow; if unset, Cast Spell is disabled.
var _spell_registry: SpellRegistry = null
var _effect_registry: SpellEffectRegistry = null
var _campaign_repo = null

var _confirm_btn: Button = null
var _list_container: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(400, 200)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.5)
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	# Title
	var title := Label.new()
	title.text = "Declaration Phase"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Declare movement intentions before initiative is rolled."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(subtitle)

	var sep := HSeparator.new()
	outer.add_child(sep)

	# Scrollable PC list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_container)

	# Confirm button
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_row)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Declarations"
	_confirm_btn.custom_minimum_size = Vector2(180, 36)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(_confirm_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Inject the spell-system registries needed by the Cast Spell flow. Optional;
## without these, the Cast Spell option appears disabled with a tooltip.
func setup_spell_dependencies(
		spell_registry: SpellRegistry,
		effect_registry: SpellEffectRegistry,
		campaign_repo) -> void:
	_spell_registry = spell_registry
	_effect_registry = effect_registry
	_campaign_repo = campaign_repo


## Populate the overlay with alive PCs.
## [param pcs] Array of {combatant_id, display_name, character_data (optional),
##                       is_caster, has_available_slot, can_cast_now,
##                       cast_disabled_reason}
func set_pc_list(pcs: Array) -> void:
	_pc_list = pcs
	_declarations.clear()
	_spell_choices.clear()
	for pc in pcs:
		_declarations[pc.get("combatant_id", "")] = ""
	_rebuild()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	for pc in _pc_list:
		var cid: String = pc.get("combatant_id", "")
		var dname: String = pc.get("display_name", "???")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list_container.add_child(row)

		# PC name
		var name_label := Label.new()
		name_label.text = dname
		name_label.custom_minimum_size.x = 120.0
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		# Option buttons (OptionButton dropdown)
		var is_berserk: bool = bool(pc.get("is_berserk_raging", false))
		var is_caster: bool = bool(pc.get("is_caster", false))
		var can_cast_now: bool = bool(pc.get("can_cast_now", false))
		var cast_disabled_reason: String = String(pc.get("cast_disabled_reason", ""))

		var dropdown := OptionButton.new()
		dropdown.custom_minimum_size.x = 200.0
		for i in range(DECLARATION_OPTIONS.size()):
			var opt: Dictionary = DECLARATION_OPTIONS[i]
			dropdown.add_item(opt["label"])
			# Berserkers cannot declare defensive movement.
			if is_berserk and opt["id"] in ["fighting_withdrawal", "full_retreat"]:
				dropdown.set_item_disabled(i, true)
			# Cast Spell gating: must be a caster, must be able to cast right now,
			# AND the picker dependencies must be wired.
			if opt["id"] == "cast_spell":
				var picker_ready := _spell_registry != null and _effect_registry != null
				if not is_caster:
					dropdown.set_item_disabled(i, true)
					dropdown.set_item_tooltip(i, "Not a caster")
				elif not can_cast_now:
					dropdown.set_item_disabled(i, true)
					dropdown.set_item_tooltip(i, cast_disabled_reason if not cast_disabled_reason.is_empty() else "No spell slots available")
				elif not picker_ready:
					dropdown.set_item_disabled(i, true)
					dropdown.set_item_tooltip(i, "Spell picker not initialized")
		dropdown.selected = 0
		dropdown.item_selected.connect(_on_declaration_changed.bind(cid, pc))
		if is_berserk:
			dropdown.tooltip_text = "Berserk rage — defensive declarations unavailable."
		row.add_child(dropdown)

		# Casting chip: shows the chosen spell when cast_spell is selected.
		var chip := Label.new()
		chip.name = "CastChip_%s" % cid
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
		chip.text = ""
		row.add_child(chip)


func _on_declaration_changed(index: int, combatant_id: String, pc_record: Dictionary) -> void:
	if index < 0 or index >= DECLARATION_OPTIONS.size():
		return
	var decl_id: String = DECLARATION_OPTIONS[index]["id"]
	_declarations[combatant_id] = decl_id
	_spell_choices.erase(combatant_id)
	_set_chip_text(combatant_id, "")
	if decl_id == "cast_spell":
		_open_spell_picker(combatant_id, pc_record)


func _open_spell_picker(combatant_id: String, pc_record: Dictionary) -> void:
	if _spell_registry == null or _effect_registry == null:
		return
	var caster: CharacterData = pc_record.get("character_data", null)
	if caster == null:
		return
	var picker = SPELL_PICKER_SCENE.instantiate()
	add_child(picker)  # add to overlay so its CanvasLayer 56 is in tree
	picker.spell_chosen.connect(_on_spell_chosen.bind(combatant_id))
	picker.cancelled.connect(_on_picker_cancelled.bind(combatant_id))
	picker.setup(caster, {
		"spell_registry": _spell_registry,
		"effect_registry": _effect_registry,
		"campaign_repo": _campaign_repo,
	})


func _on_spell_chosen(choice: SpellChoice, combatant_id: String) -> void:
	# If the spell is disjunctive, open the branch modal. Otherwise commit
	# the choice into the declaration record immediately.
	if _effect_registry != null and _effect_registry.is_disjunctive(choice.spell_key, choice.is_reversed):
		_open_disjunctive_modal(combatant_id, choice)
		return
	_commit_spell_choice(combatant_id, choice)


func _open_disjunctive_modal(combatant_id: String, choice: SpellChoice) -> void:
	var payload := _effect_registry.get_effect_payload(choice.spell_key, choice.is_reversed, -1)
	var ts: Dictionary = payload.get("target_spec", {})
	var options: Array = ts.get("options", [])
	if options.is_empty():
		_commit_spell_choice(combatant_id, choice)
		return
	var modal = DISJUNCTIVE_MODAL_SCENE.instantiate()
	add_child(modal)
	modal.branch_chosen.connect(func(idx: int) -> void:
		choice.chosen_disjunctive_index = idx
		_commit_spell_choice(combatant_id, choice))
	modal.cancelled.connect(func() -> void:
		# Reset declaration on cancel.
		_declarations[combatant_id] = ""
		_spell_choices.erase(combatant_id)
		_set_chip_text(combatant_id, ""))
	var spell_data: Dictionary = _spell_registry.get_spell(choice.spell_key)
	modal.setup(String(spell_data.get("spell_name", choice.spell_key)), options)


func _commit_spell_choice(combatant_id: String, choice: SpellChoice) -> void:
	_spell_choices[combatant_id] = choice
	var spell_data: Dictionary = _spell_registry.get_spell(choice.spell_key) if _spell_registry != null else {}
	var label := String(spell_data.get("spell_name", choice.spell_key))
	if choice.is_reversed:
		label = "%s (reversed)" % String(spell_data.get("reverse_name", label))
	if choice.chosen_disjunctive_index >= 0:
		label += " [branch %d]" % (choice.chosen_disjunctive_index + 1)
	_set_chip_text(combatant_id, "Casting: " + label)


func _on_picker_cancelled(combatant_id: String) -> void:
	# Revert the dropdown to None.
	_declarations[combatant_id] = ""
	_spell_choices.erase(combatant_id)
	_set_chip_text(combatant_id, "")
	# Reset the OptionButton selection visually.
	for child in _list_container.get_children():
		if not (child is HBoxContainer):
			continue
		for grandchild in child.get_children():
			if grandchild is OptionButton:
				# Find the OptionButton attached to this combatant. The chip
				# label below it carries the cid in its name.
				var chip: Label = child.get_node_or_null("CastChip_%s" % combatant_id) as Label
				if chip != null:
					(grandchild as OptionButton).selected = 0
					break


func _set_chip_text(combatant_id: String, text: String) -> void:
	for child in _list_container.get_children():
		var chip: Label = child.get_node_or_null("CastChip_%s" % combatant_id) as Label
		if chip != null:
			chip.text = text
			return


func _on_confirm_pressed() -> void:
	var result: Array = []
	for cid in _declarations:
		var decl_type: String = _declarations[cid]
		if decl_type.is_empty():
			continue
		var record: Dictionary = {"combatant_id": cid, "declaration_type": decl_type}
		if decl_type == "cast_spell" and _spell_choices.has(cid):
			record["spell_choice"] = _spell_choices[cid]
		result.append(record)
	declarations_complete.emit(result)
