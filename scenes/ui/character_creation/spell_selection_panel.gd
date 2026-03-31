class_name SpellSelectionPanel
extends VBoxContainer

## Step 6 — Starting Spell Selection.
##
## Flow by tradition:
##   Arcane (mage, elf_spellsword, elven_enchanter): player picks 1 judge-selected
##     level-1 spell; each INT bonus point rolls 1d12 on the arcane index.
##   Divine with level-1 slots (priestess, witch): grants are auto-generated from
##     the divine repertoire engine. Shown for confirmation; no player input needed.
##   Divine with no level-1 slots (cleric, bladedancer, shaman, etc.):
##     Shows "You will receive divine spells at 2nd level." Auto-completes.
##   Warlock (incomplete spell data): shows a notice, auto-completes.
##
## This panel is SKIPPED ENTIRELY for non-casters (handled by the flow controller).


var _state: Dictionary = {}
var _class_registry: ClassRegistry
var _spell_registry: SpellRegistry
var _repertoire_engine: RepertoireEngine

# Arcane selection state
var _arcane_spell_list: Array[String] = []    # all level-1 spells available
var _judge_selected_key: String = ""
var _bonus_roll_results: Array = []           # roll indices from INT bonus
var _rolling: bool = false

# UI refs
var _main_content: VBoxContainer
var _roll_bonus_btn: Button
var _confirm_btn: Button
var _status_label: Label


func setup(state: Dictionary, class_registry: ClassRegistry,
		spell_registry: SpellRegistry, repertoire_engine: RepertoireEngine) -> void:
	_state = state
	_class_registry = class_registry
	_spell_registry = spell_registry
	_repertoire_engine = repertoire_engine
	if get_child_count() == 0:
		_build_ui()
	_initialize_panel()


func is_complete() -> bool:
	return _state.has("spells")


# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------

func _initialize_panel() -> void:
	for child in _main_content.get_children():
		child.queue_free()

	var class_id: String = _state.get("class_id", "")
	var tradition := _spell_registry.get_class_tradition(class_id, _class_registry)
	var slots := _class_registry.get_spell_slots(class_id, 1)
	var has_l1_slots := not slots.is_empty() and int(slots[0]) > 0

	if tradition == "arcane":
		_setup_arcane(class_id, has_l1_slots)
	elif tradition == "divine":
		_setup_divine(class_id, has_l1_slots)
	else:
		# Warlock or unknown — show notice and auto-complete
		_setup_notice("Spell progression data for this class is pending. No starting spells.")
		if not _state.has("spells"):
			_state["spells"] = []


# ---------------------------------------------------------------------------
# Arcane setup
# ---------------------------------------------------------------------------

func _setup_arcane(class_id: String, has_l1_slots: bool) -> void:
	if not has_l1_slots:
		_setup_notice("This class gains spell slots at a higher level. No starting spells.")
		if not _state.has("spells"):
			_state["spells"] = []
		return

	_arcane_spell_list = []
	for k in _spell_registry.get_available_spells_for_class(class_id, 1, _class_registry):
		_arcane_spell_list.append(k as String)

	# Restore prior selection if returning to this step
	if _state.has("spells") and not (_state.get("spells") as Array).is_empty():
		var existing: Array = _state.get("spells", [])
		if not existing.is_empty():
			_judge_selected_key = existing[0].get("spell_key", "")

	var header := Label.new()
	header.text = "Choose your judge-selected starting spell (1st level):"
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_content.add_child(header)

	# Spell chooser
	var opt := OptionButton.new()
	opt.name = "SpellOptionButton"
	for spell_key in _arcane_spell_list:
		var def := _spell_registry.get_spell(spell_key)
		var display: String = def.get("name", spell_key.replace("_", " ").capitalize())
		opt.add_item(display)
		opt.set_item_metadata(opt.item_count - 1, spell_key)
	if not _judge_selected_key.is_empty():
		for i in range(opt.item_count):
			if opt.get_item_metadata(i) == _judge_selected_key:
				opt.select(i)
				break
	opt.item_selected.connect(_on_spell_selected)
	_main_content.add_child(opt)

	# INT bonus description
	var effective: Dictionary = _state.get("traded_scores", {})
	if effective.is_empty():
		effective = _state.get("scores", {})
	var int_score: int = int(effective.get("INT", 10))
	var int_mod := CharacterData.ability_modifier(int_score)
	var bonus_rolls := maxi(int_mod, 0)

	if bonus_rolls > 0:
		var bonus_lbl := Label.new()
		bonus_lbl.text = "Your INT modifier (%+d) grants %d additional spell roll%s." % [
			int_mod, bonus_rolls, "s" if bonus_rolls > 1 else ""]
		_main_content.add_child(bonus_lbl)

		_roll_bonus_btn = Button.new()
		_roll_bonus_btn.text = "Roll Bonus Spell%s" % ("s" if bonus_rolls > 1 else "")
		_roll_bonus_btn.pressed.connect(_on_roll_bonus_pressed.bind(class_id, bonus_rolls))
		_main_content.add_child(_roll_bonus_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_content.add_child(_status_label)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Spell Selection"
	_confirm_btn.pressed.connect(_on_confirm_arcane.bind(class_id, bonus_rolls))
	_main_content.add_child(_confirm_btn)

	# Show existing results if returning
	if _state.has("spells"):
		_show_final_repertoire()


func _on_spell_selected(index: int) -> void:
	var opt := _main_content.get_node_or_null("SpellOptionButton") as OptionButton
	if opt == null:
		return
	_judge_selected_key = opt.get_item_metadata(index) as String
	# Clear confirmed spells since selection changed
	_state.erase("spells")
	_bonus_roll_results.clear()
	_remove_results_display()


func _on_roll_bonus_pressed(class_id: String, bonus_rolls: int) -> void:
	if _rolling:
		return

	# Ensure a judge spell is selected first
	var opt := _main_content.get_node_or_null("SpellOptionButton") as OptionButton
	if opt != null and opt.item_count > 0 and _judge_selected_key.is_empty():
		_judge_selected_key = opt.get_item_metadata(opt.selected) as String

	_rolling = true
	if _roll_bonus_btn != null:
		_roll_bonus_btn.disabled = true

	_bonus_roll_results.clear()
	for i in range(bonus_rolls):
		var result: RollResult = await DiceSystem.player_roll(12, 1, 0,
			"starting_spell",
			"Roll Bonus Spell %d of %d (1d12)" % [i + 1, bonus_rolls])
		_bonus_roll_results.append(result.modified_total)

	_rolling = false
	if _roll_bonus_btn != null:
		_roll_bonus_btn.disabled = false

	# Show intermediate results before confirm
	_remove_results_display()
	if not _bonus_roll_results.is_empty():
		var rolls_lbl := Label.new()
		rolls_lbl.name = "RollResults"
		var idx_strs: Array = []
		for r in _bonus_roll_results:
			idx_strs.append(str(r))
		rolls_lbl.text = "Rolled: %s  — click Confirm to finalize." % ", ".join(idx_strs)
		_main_content.add_child(rolls_lbl)


func _on_confirm_arcane(class_id: String, bonus_rolls: int) -> void:
	# Ensure judge spell selected
	var opt := _main_content.get_node_or_null("SpellOptionButton") as OptionButton
	if opt != null and opt.item_count > 0 and _judge_selected_key.is_empty():
		_judge_selected_key = opt.get_item_metadata(opt.selected) as String

	if _judge_selected_key.is_empty():
		if _status_label != null:
			_status_label.text = "Please select a starting spell."
		return

	# Build repertoire using the engine (digital rolls for already-rolled bonus)
	# If bonus rolls were done, we use them as overrides.
	var override_queue: Array = _bonus_roll_results.duplicate()
	var spells: Array = []
	var known: Dictionary = {}

	# Add judge-selected spell
	if _spell_registry.has_spell(_judge_selected_key):
		var entry := _spell_registry.get_spell(_judge_selected_key)
		spells.append({
			"spell_key": _judge_selected_key,
			"spell_level": 1,
			"is_in_repertoire": true,
			"is_memorized": false,
			"memorized_slots": 0,
		})
		known[_judge_selected_key] = true

	# Add bonus roll spells
	for idx in override_queue:
		var spell_key := _spell_registry.get_arcane_index_spell(1, idx)
		if spell_key.is_empty() or known.has(spell_key):
			continue
		if not _spell_registry.has_spell(spell_key):
			continue
		spells.append({
			"spell_key": spell_key,
			"spell_level": 1,
			"is_in_repertoire": true,
			"is_memorized": false,
			"memorized_slots": 0,
		})
		known[spell_key] = true

	_state["spells"] = spells
	_show_final_repertoire()


func _remove_results_display() -> void:
	var existing := _main_content.get_node_or_null("RollResults")
	if existing != null:
		existing.queue_free()
	var existing2 := _main_content.get_node_or_null("FinalRepertoire")
	if existing2 != null:
		existing2.queue_free()


func _show_final_repertoire() -> void:
	_remove_results_display()
	var spells: Array = _state.get("spells", [])
	var vbox := VBoxContainer.new()
	vbox.name = "FinalRepertoire"
	var lbl := Label.new()
	lbl.text = "Starting Repertoire:"
	vbox.add_child(lbl)
	for s in spells:
		var key: String = s.get("spell_key", "")
		var def := _spell_registry.get_spell(key)
		var display: String = def.get("name", key.replace("_", " ").capitalize())
		var entry_lbl := Label.new()
		entry_lbl.text = "  • %s" % display
		vbox.add_child(entry_lbl)
	_main_content.add_child(vbox)


# ---------------------------------------------------------------------------
# Divine setup
# ---------------------------------------------------------------------------

func _setup_divine(class_id: String, has_l1_slots: bool) -> void:
	if not has_l1_slots:
		var cls := _class_registry.get_class_def(class_id)
		var cls_name: String = cls.get("class_name", class_id.capitalize())
		_setup_notice("%s does not receive divine spells until 2nd level." % cls_name)
		if not _state.has("spells"):
			_state["spells"] = []
		return

	# Auto-generate divine starting repertoire
	var result := _repertoire_engine.generate_divine_starting_repertoire(class_id, 1)
	var spells: Array = result.get("spells", [])
	if not _state.has("spells"):
		_state["spells"] = spells

	var header := Label.new()
	header.text = "Your deity grants the following 1st-level spells:"
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_content.add_child(header)

	var granted: Array = _state.get("spells", spells)
	if granted.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(No spells found — check spell data.)"
		_main_content.add_child(empty_lbl)
	else:
		for s in granted:
			var key: String = s.get("spell_key", "")
			var def := _spell_registry.get_spell(key)
			var display: String = def.get("name", key.replace("_", " ").capitalize())
			var lbl := Label.new()
			lbl.text = "  • %s" % display
			_main_content.add_child(lbl)

	var info := Label.new()
	info.text = "Divine casters know all spells for each level they can cast."
	info.modulate = Color(0.7, 0.9, 0.7, 1.0)
	_main_content.add_child(info)


# ---------------------------------------------------------------------------
# Notice (auto-complete, no player input)
# ---------------------------------------------------------------------------

func _setup_notice(message: String) -> void:
	var lbl := Label.new()
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_content.add_child(lbl)


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 10)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_main_content = VBoxContainer.new()
	_main_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_main_content)
