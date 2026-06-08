class_name ClassTemplatePanel
extends VBoxContainer

## Step 5 — Wealth & Class Template (gdd-class-templates.md §4, §4.2, §4.2.1; §10 step 12).
##
## The PC-creation choice point. After the wealth die is rolled (3d6 → ×10 gp OR a
## template cap), the player takes one of two paths (§4.1 — the roll is consumed by
## ONE of them, never both):
##
##   Path A — keep the gold: write starting_gold_cp and continue the normal flow
##            (the later EQUIPMENT step opens pre-funded; PROFICIENCIES / SPELLS run).
##   Path B — take a template at or below the rolled band: the template supplies
##            proficiencies (editable here via the §4.2.1 editor), equipment, spells,
##            origin/tradition, and loose coin. The downstream steps it covers are
##            skipped by the wizard (CharacterCreationScreen skip predicates).
##
## All game logic lives in PcTemplateCreationFlow; this panel only renders its dict
## outputs and feeds the player's choices back into creation_state. Built
## programmatically per coding_conventions §13.2; no editor-authored layout.

var _state: Dictionary = {}
var _flow: PcTemplateCreationFlow
var _template_repo: ClassTemplateRepository
var _catalog: EquipmentCatalog

# Derived from creation_state at setup().
var _class_id: String = ""
var _int_score: int = 10

# Phase-1 fork state.
var _wealth_roll: int = 0
var _path_b_templates: Array = []          # [ClassTemplate]

# Phase-2 editor state (Path B).
var _selected_template: ClassTemplate = null
var _editor_state: Dictionary = {}
var _swap_opts: Dictionary = {}
var _committed: bool = false

# UI refs — Phase 1
var _roll_btn: Button
var _roll_label: RichTextLabel
var _fork_box: VBoxContainer
var _path_a_btn: Button
var _cards_scroll: ScrollContainer
var _cards_box: VBoxContainer
var _status_label: Label

# UI refs — Phase 2 editor
var _editor_box: VBoxContainer
var _editor_body: VBoxContainer
var _preview_label: RichTextLabel
var _validation_label: Label
var _confirm_btn: Button

# Editor widgets (rebuilt per template selection)
var _class_swap_option: OptionButton = null
var _class_swap_warn: Label = null
var _cull_option: OptionButton = null
var _general_swap_rows: Array = []          # [{from_key: String, option: OptionButton}]
var _extra_options: Array = []              # [OptionButton]


# ---------------------------------------------------------------------------
# Panel contract
# ---------------------------------------------------------------------------

func setup(state: Dictionary, template_repo: ClassTemplateRepository,
		proficiency_registry: ProficiencyRegistry, catalog: EquipmentCatalog,
		class_registry: ClassRegistry) -> void:
	_state = state
	_flow = PcTemplateCreationFlow.new(template_repo, proficiency_registry,
		catalog, class_registry)
	_template_repo = template_repo
	_catalog = catalog
	_class_id = String(_state.get("class_id", ""))
	_int_score = _resolve_int_score()
	if get_child_count() == 0:
		_build_ui()
	_restore_from_state()


func is_complete() -> bool:
	## A path must be committed: Path A chosen, or a Path B template confirmed.
	return _committed


# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

func _resolve_int_score() -> int:
	## Final INT (post ability-trade). The CharacterData is generated at HP_ROLL,
	## which precedes this step, so character.intelligence is authoritative.
	var character: CharacterData = _state.get("character")
	if character != null:
		return character.intelligence
	var effective: Dictionary = _state.get("traded_scores", {})
	if effective.is_empty():
		effective = _state.get("scores", {})
	return int(effective.get("INT", 10))


func _restore_from_state() -> void:
	## Rehydrate after back-navigation AND across characters (§13.3 — setup() is a
	## full UI rehydration, never a delta: the screen reuses ONE panel instance for
	## every PC, so recompute disabled state + clear cached templates from scratch).
	_wealth_roll = int(_state.get("wealth_roll", 0))
	_selected_template = null
	_editor_state = {}
	_committed = false
	_path_b_templates = []
	_clear_editor_widgets()
	_editor_box.visible = false
	_status_label.text = ""
	# The roll button is only ever transiently disabled while the dice prompt is
	# open (_on_roll_wealth); a fresh setup must always re-enable it. Without this,
	# a prior character's successful roll left it disabled-but-hidden, so the next
	# character saw it visible-but-greyed.
	_roll_btn.disabled = false

	if _wealth_roll <= 0:
		# Not yet rolled — fresh entry.
		_roll_btn.visible = true
		_roll_label.text = ""
		_fork_box.visible = false
		return

	# Already rolled (returning to this step) — re-show the fork.
	_roll_btn.visible = false
	_show_roll_summary()
	_build_cards()
	_fork_box.visible = true

	var path: String = String(_state.get("template_path", ""))
	if path == "A":
		_committed = true
		_status_label.text = "Kept the gold — click Next to shop, or pick a template below."
	elif path == "B":
		_committed = true
		var tid: String = String(_state.get("template_id", ""))
		var t: ClassTemplate = _template_repo.get_template(tid)
		if t != null:
			_open_editor_for(t)
			_status_label.text = "Template saved — click Next to continue, or adjust and re-confirm."


# ---------------------------------------------------------------------------
# Phase 1 — wealth roll + fork
# ---------------------------------------------------------------------------

func _on_roll_wealth() -> void:
	if _wealth_roll > 0:
		return
	_roll_btn.disabled = true
	var result = await DiceSystem.player_roll(6, 3, 0, "starting_gold",
		"Roll Starting Wealth (3d6 × 10gp)")
	var roll: int = int(result.modified_total)
	if roll <= 0:
		# Cancelled — allow another attempt.
		_roll_btn.disabled = false
		return
	_wealth_roll = roll
	_state["wealth_roll"] = roll
	_roll_btn.visible = false
	_show_roll_summary()
	_build_cards()
	_fork_box.visible = true


func _show_roll_summary() -> void:
	var gp: int = _wealth_roll * 10
	if _path_b_templates.is_empty():
		_path_b_templates = _query_templates()
	if _path_b_templates.is_empty():
		_roll_label.text = "You rolled %d → %d gp starting wealth." % [_wealth_roll, gp]
	else:
		_roll_label.text = "You rolled %d → %d gp [b]or[/b] any template up to band %d." % [
			_wealth_roll, gp, _wealth_roll]


func _build_cards() -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	_path_b_templates = _query_templates()
	if _path_b_templates.is_empty():
		var none := Label.new()
		none.text = "No templates available for this class at this roll. Keep the gold."
		_cards_box.add_child(none)
		return
	for t: ClassTemplate in _path_b_templates:
		_cards_box.add_child(_make_template_card(t))


func _make_template_card(t: ClassTemplate) -> PanelContainer:
	var card := PanelContainer.new()
	UiSurfaceStyles.apply_textured_panel(card)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	card.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)

	var title := Label.new()
	title.text = t.display_label if t.display_label != "" else t.template_id
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	if t.tradition != "":
		var trad := Label.new()
		trad.text = "Tradition: %s" % t.tradition.capitalize()
		box.add_child(trad)

	var profs := Label.new()
	profs.text = "Proficiencies: " + _proficiency_summary(t)
	profs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(profs)

	var equip := Label.new()
	equip.text = "Equipment: " + _equipment_summary(t)
	equip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(equip)

	if TemplateIntAdjuster.is_arcane_class(t.class_id) and not t.starting_spells.is_empty():
		var spells := Label.new()
		spells.text = "Spells: " + _spell_summary(t)
		spells.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(spells)

	var coin := Label.new()
	coin.text = "Starting coin: %d gp" % t.starting_gp
	box.add_child(coin)

	var pick := Button.new()
	pick.text = "Take this template"
	pick.pressed.connect(_on_card_selected.bind(t))
	box.add_child(pick)
	return card


func _proficiency_summary(t: ClassTemplate) -> String:
	var parts: Array = []
	for p: TemplateProficiency in t.proficiencies:
		parts.append("%s %s" % [p.name, _kind_tag(p.proficiency_kind)])
	return ", ".join(parts)


func _kind_tag(kind: String) -> String:
	match kind:
		"class": return "[C]"
		"natural": return "[N]"
		"tradition": return "[T]"
		"arcane_bonus": return "[A]"
		_: return "[G]"


func _equipment_summary(t: ClassTemplate) -> String:
	var equip := ClassedNpcBuilder.equipment_records(t, _catalog)
	var parts: Array = []
	for item in equip.get("equipment", []):
		var qty: int = int(item.get("quantity", 1))
		var nm: String = String(item.get("name", item.get("item_key", "?")))
		parts.append(nm if qty <= 1 else "%s ×%d" % [nm, qty])
	for nc in equip.get("non_catalog", []):
		var label := _non_catalog_label(nc)
		if label != "":
			parts.append(label)
	return ", ".join(parts) if not parts.is_empty() else "(none)"


func _spell_summary(t: ClassTemplate) -> String:
	var parts: Array = t.starting_spells.duplicate()
	if t.bonus_spell != "":
		parts.append("%s (bonus)" % t.bonus_spell)
	return ", ".join(parts)


func _on_path_a() -> void:
	# §4.1 — the rolled wealth becomes starting gold; no template.
	_state["template_path"] = "A"
	_state["template_id"] = ""
	_state["origin_template_id"] = ""
	_state["template_class_metadata"] = {}
	var cp: int = _wealth_roll * 10 * 100   # gp → cp
	_state["starting_gold_cp"] = cp
	_state["gold_remaining_cp"] = cp
	# Clear any Path-B prefills (in case the player switched paths).
	_clear_path_b_prefills()
	_editor_box.visible = false
	_committed = true
	_status_label.text = "Kept %d gp — click Next to shop." % (_wealth_roll * 10)


# ---------------------------------------------------------------------------
# Phase 2 — §4.2.1 full proficiency editor (Path B)
# ---------------------------------------------------------------------------

func _on_card_selected(t: ClassTemplate) -> void:
	_open_editor_for(t)
	_status_label.text = ""


func _open_editor_for(t: ClassTemplate) -> void:
	var result := _flow.choose_path_b(_class_id, t.template_id, _int_score)
	if not bool(result.get("ok", false)):
		_status_label.text = "Could not load template: %s" % String(result.get("error", "?"))
		return
	_selected_template = t
	_editor_state = result.get("editor", {})
	_swap_opts = _flow.swap_options(t)
	_build_editor(result)
	_editor_box.visible = true
	_refresh_preview()


func _build_editor(path_b: Dictionary) -> void:
	_clear_editor_widgets()
	for child in _editor_body.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "Editing: %s" % String(path_b.get("display_label", _selected_template.template_id))
	header.add_theme_font_size_override("font_size", 16)
	_editor_body.add_child(header)

	# --- Class proficiency (locked by default, swappable — flagged §4.2.1) ---
	var cls_brief: Dictionary = _editor_state.get("class_proficiency", {})
	if not cls_brief.is_empty():
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "Class proficiency:"
		row.add_child(lbl)
		_class_swap_option = OptionButton.new()
		var cur_key: String = String(cls_brief.get("proficiency_key", ""))
		_populate_option(_class_swap_option, _swap_opts.get("class_options", []), cur_key, false)
		_class_swap_option.item_selected.connect(_refresh_preview.unbind(1))
		row.add_child(_class_swap_option)
		_editor_body.add_child(row)
		_class_swap_warn = Label.new()
		_class_swap_warn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.1))
		_class_swap_warn.visible = false
		_class_swap_warn.text = "  ⚠ Departs from the template's intended build."
		_editor_body.add_child(_class_swap_warn)

	# --- Locked proficiencies (natural / tradition — read-only) ---
	for b in _editor_state.get("locked_proficiencies", []):
		var ll := Label.new()
		ll.text = "  • %s (locked)" % String(b.get("name", b.get("proficiency_key", "?")))
		_editor_body.add_child(ll)

	# --- Cull override (arcane INT ≤ 12) ---
	var cull: Dictionary = _editor_state.get("cull", {})
	if bool(cull.get("needed", false)):
		var crow := HBoxContainer.new()
		var clbl := Label.new()
		clbl.text = "Drop one (INT too low for all):"
		crow.add_child(clbl)
		_cull_option = OptionButton.new()
		var opts: Array = cull.get("options", [])
		_populate_option(_cull_option, opts, String(cull.get("default_key", "")), false)
		_cull_option.item_selected.connect(_refresh_preview.unbind(1))
		crow.add_child(_cull_option)
		_editor_body.add_child(crow)

	# --- General proficiencies (each swappable) ---
	_general_swap_rows.clear()
	for b in _editor_state.get("general_proficiencies", []):
		var from_key: String = String(b.get("proficiency_key", ""))
		if from_key == "":
			continue
		var grow := HBoxContainer.new()
		var glbl := Label.new()
		glbl.text = "General:"
		grow.add_child(glbl)
		var opt := OptionButton.new()
		# Options = the current key plus every net-new general option.
		var pool: Array = [from_key]
		for k in _swap_opts.get("general_options", []):
			if k != from_key:
				pool.append(k)
		_populate_option(opt, pool, from_key, false)
		opt.item_selected.connect(_refresh_preview.unbind(1))
		grow.add_child(opt)
		_editor_body.add_child(grow)
		_general_swap_rows.append({"from_key": from_key, "option": opt})

	# --- Extra INT-bonus general picks ---
	_extra_options.clear()
	var extra_slots: int = int(_editor_state.get("extra_general_slots", 0))
	for i in extra_slots:
		var erow := HBoxContainer.new()
		var elbl := Label.new()
		elbl.text = "Bonus general %d:" % (i + 1)
		erow.add_child(elbl)
		var eopt := OptionButton.new()
		_populate_option(eopt, _swap_opts.get("general_options", []), "", true)
		eopt.item_selected.connect(_refresh_preview.unbind(1))
		erow.add_child(eopt)
		_editor_body.add_child(erow)
		_extra_options.append(eopt)

	# --- Read-only loadout / spell review ---
	var review := Label.new()
	review.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var equip_txt := "Equipment: " + _equipment_summary(_selected_template)
	var rcoin := int(path_b.get("starting_money_cp", 0))
	equip_txt += "\nLoose coin: %d gp" % (rcoin / 100)
	if TemplateIntAdjuster.is_arcane_class(_class_id):
		equip_txt += "\nSpells: " + _spell_summary(_selected_template)
		var extra_spells: int = int(_editor_state.get("extra_spells_to_roll", 0))
		if extra_spells > 0:
			equip_txt += " (+%d rolled at INT %d)" % [extra_spells, _int_score]
	review.text = equip_txt
	_editor_body.add_child(HSeparator.new())
	_editor_body.add_child(review)


func _populate_option(opt: OptionButton, keys: Array, selected_key: String,
		with_blank: bool) -> void:
	opt.clear()
	var idx := 0
	if with_blank:
		opt.add_item("— pick —")
		opt.set_item_metadata(idx, "")
		idx += 1
	var sel_idx := 0
	for k in keys:
		var key := String(k)
		opt.add_item(key.capitalize())
		opt.set_item_metadata(idx, key)
		if key == selected_key:
			sel_idx = idx
		idx += 1
	opt.select(sel_idx)


func _refresh_preview() -> void:
	if _selected_template == null:
		return
	# Class-swap departure warning.
	if _class_swap_warn != null and _class_swap_option != null:
		var cur: String = String(_editor_state.get("class_proficiency", {}).get("proficiency_key", ""))
		var chosen: String = String(_class_swap_option.get_selected_metadata())
		_class_swap_warn.visible = (chosen != "" and chosen != cur)

	var choices := _gather_choices()
	var records: Array = _flow.finalize_proficiencies(_selected_template, _int_score, choices)

	# Build the preview text + duplicate detection.
	var keys: Array = []
	var dup := ""
	var names: Array = []
	for r: Dictionary in records:
		var k: String = String(r.get("proficiency_key", ""))
		if k in keys and dup == "":
			dup = k
		keys.append(k)
		var tag: String = "[C]" if String(r.get("slot_type", "")) == "class" else "[G]"
		names.append("%s %s" % [k.capitalize(), tag])
	_preview_label.text = "[b]Resulting proficiencies:[/b] " + ", ".join(names)

	# Validate: no duplicate extra picks / swap collisions.
	var validation := ""
	if dup != "":
		validation = "Duplicate proficiency: %s — change a swap or bonus pick." % dup.capitalize()
	_validation_label.text = validation
	_confirm_btn.disabled = (validation != "")


func _gather_choices() -> Dictionary:
	var choices: Dictionary = {}
	# Class swap.
	if _class_swap_option != null:
		var cur: String = String(_editor_state.get("class_proficiency", {}).get("proficiency_key", ""))
		var chosen: String = String(_class_swap_option.get_selected_metadata())
		if chosen != "" and chosen != cur:
			choices["class_swap_key"] = chosen
	# Cull override.
	if _cull_option != null:
		choices["cull_key"] = String(_cull_option.get_selected_metadata())
	# General swaps.
	var swaps: Dictionary = {}
	for row in _general_swap_rows:
		var from_key: String = String(row["from_key"])
		var to_key: String = String((row["option"] as OptionButton).get_selected_metadata())
		if to_key != "" and to_key != from_key:
			swaps[from_key] = to_key
	if not swaps.is_empty():
		choices["general_swaps"] = swaps
	# Extra-general picks.
	var extras: Array = []
	for opt in _extra_options:
		var k: String = String((opt as OptionButton).get_selected_metadata())
		if k != "":
			extras.append(k)
	if not extras.is_empty():
		choices["extra_general_keys"] = extras
	return choices


func _on_confirm_template() -> void:
	if _selected_template == null:
		return
	var choices := _gather_choices()
	var records: Array = _flow.finalize_proficiencies(_selected_template, _int_score, choices)
	var path_b := _flow.choose_path_b(_class_id, _selected_template.template_id, _int_score)
	if not bool(path_b.get("ok", false)):
		_status_label.text = "Template error: %s" % String(path_b.get("error", "?"))
		return

	_state["template_path"] = "B"
	_state["template_id"] = _selected_template.template_id
	_state["origin_template_id"] = _selected_template.template_id
	_state["proficiencies"] = records
	_state["template_class_metadata"] = path_b.get("class_metadata_locked", {})

	# Loose coin the template grants (§4.1 — template wealth IS the starting funds).
	var coin_cp: int = int(path_b.get("starting_money_cp", 0))
	_state["starting_gold_cp"] = coin_cp
	_state["gold_remaining_cp"] = coin_cp

	# Inventory = the template's catalog equipment. Non-catalog routing below.
	var equip: Array = path_b.get("equipment", [])
	var inventory: Array = []
	for item in equip:
		inventory.append((item as Dictionary).duplicate(true))
	_route_non_catalog(path_b.get("non_catalog_items", []), inventory)
	_state["inventory"] = inventory

	# Arcane repertoire (empty for divine / mundane).
	var rep := _flow.build_repertoire(_class_id, _selected_template.template_id, _int_score)
	_state["spells"] = rep.get("spells", []) if rep is Dictionary else []

	_committed = true
	_status_label.text = "Template applied — click Next to continue."


func _route_non_catalog(entries: Array, inventory: Array) -> void:
	## Path B non-catalog items (gdd §4.2 / §10 step 12 plan §E):
	##   familiar → dropped (the FAMILIAR_ACQUISITION step bonds + persists it; the
	##              template's "familiar" proficiency makes that step appear).
	##   valuable / totem / poison → deferred for v1; logged so nothing is lost
	##              silently (a value-backed-inventory follow-up is tracked).
	var deferred: Array = []
	for nc in entries:
		var meta: Dictionary = (nc as Dictionary).get("metadata", {})
		var companion: String = String(meta.get("companion_kind", ""))
		if companion == "familiar":
			continue  # handled by the familiar bonding step
		var label := _non_catalog_label(nc)
		if label != "":
			deferred.append(label)
	if not deferred.is_empty():
		push_warning("ClassTemplatePanel: non-catalog template items not yet routed to PC (deferred v1): %s"
			% ", ".join(deferred))


func _non_catalog_label(nc: Dictionary) -> String:
	var meta: Dictionary = nc.get("metadata", {})
	var companion: String = String(meta.get("companion_kind", ""))
	if companion == "familiar":
		return "familiar (%s)" % String(meta.get("species", "?"))
	if companion == "totem":
		return "totem (%s)" % String(meta.get("species", "?"))
	var nckind: String = String(meta.get("noncatalog_kind", ""))
	match nckind:
		"valuable": return "valuables (%d gp)" % int(meta.get("value_gp", 0))
		"separate_catalog": return String(meta.get("tag", "item"))
		_: return ""


# ---------------------------------------------------------------------------
# State plumbing
# ---------------------------------------------------------------------------

func _query_templates() -> Array:
	## Path B eligibility (§4.1): every template of this class at or below the roll.
	return _template_repo.get_templates_for_class_at_or_below_roll(_class_id, _wealth_roll)


func _clear_path_b_prefills() -> void:
	_state["proficiencies"] = []
	_state["spells"] = []
	_state["inventory"] = []
	_state["template_class_metadata"] = {}


func _clear_editor_widgets() -> void:
	_class_swap_option = null
	_class_swap_warn = null
	_cull_option = null
	_general_swap_rows = []
	_extra_options = []


# ---------------------------------------------------------------------------
# UI construction (built once)
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	var intro := Label.new()
	intro.text = "Roll your starting wealth, then keep the gold (shop later) or take a class template."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)

	_roll_btn = Button.new()
	_roll_btn.text = "Roll Starting Wealth (3d6 × 10gp)"
	_roll_btn.pressed.connect(_on_roll_wealth)
	add_child(_roll_btn)

	_roll_label = _make_bb_label("")
	add_child(_roll_label)

	# --- Fork (hidden until the roll lands) ---
	_fork_box = VBoxContainer.new()
	_fork_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fork_box.visible = false
	add_child(_fork_box)

	var fork_row := HBoxContainer.new()
	_fork_box.add_child(fork_row)
	var a_lbl := Label.new()
	a_lbl.text = "Path A:"
	fork_row.add_child(a_lbl)
	_path_a_btn = Button.new()
	_path_a_btn.text = "Keep the gold (shop later)"
	_path_a_btn.pressed.connect(_on_path_a)
	fork_row.add_child(_path_a_btn)

	var b_lbl := Label.new()
	b_lbl.text = "Path B — take a template:"
	_fork_box.add_child(b_lbl)

	_cards_scroll = ScrollContainer.new()
	_cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fork_box.add_child(_cards_scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_theme_constant_override("separation", 6)
	_cards_scroll.add_child(_cards_box)

	# --- Editor (hidden until a card is picked) ---
	_editor_box = VBoxContainer.new()
	_editor_box.visible = false
	add_child(_editor_box)
	_editor_box.add_child(HSeparator.new())

	var editor_scroll := ScrollContainer.new()
	editor_scroll.custom_minimum_size = Vector2(0, 220)
	editor_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_box.add_child(editor_scroll)
	_editor_body = VBoxContainer.new()
	_editor_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_scroll.add_child(_editor_body)

	_preview_label = _make_bb_label("")
	_editor_box.add_child(_preview_label)
	_validation_label = Label.new()
	_validation_label.add_theme_color_override("font_color", Color(0.7, 0.15, 0.15))
	_editor_box.add_child(_validation_label)

	var confirm_row := HBoxContainer.new()
	_editor_box.add_child(confirm_row)
	var back_btn := Button.new()
	back_btn.text = "← Back to templates"
	back_btn.pressed.connect(_on_back_to_cards)
	confirm_row.add_child(back_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_row.add_child(sp)
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Template"
	_confirm_btn.pressed.connect(_on_confirm_template)
	confirm_row.add_child(_confirm_btn)

	# --- Status line ---
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)


func _make_bb_label(text: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.text = text
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rt


func _on_back_to_cards() -> void:
	_editor_box.visible = false
	_selected_template = null
	if _committed and String(_state.get("template_path", "")) == "B":
		_committed = false  # re-opening the editor un-commits until re-confirmed
