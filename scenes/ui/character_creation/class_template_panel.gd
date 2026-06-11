class_name ClassTemplatePanel
extends VBoxContainer

## Step 5 — Wealth & Class Template (gdd-class-templates.md §4, §4.2; §10 step 12).
##
## The PC-creation choice point. After the wealth die is rolled (3d6 → ×10 gp OR a
## template cap), the player takes one of two paths (§4.1 — the roll is consumed by
## ONE of them, never both):
##
##   Path A — keep the gold: write starting_gold_cp and continue the normal flow
##            (the later EQUIPMENT step opens pre-funded; PROFICIENCIES / SPELLS run).
##   Path B — take a template at or below the rolled band: the template SEEDS the
##            character's proficiencies (editable) + locked natural/tradition profs,
##            equipment, loose coin, origin/tradition, and base arcane repertoire,
##            then the wizard flows through the SAME full Proficiencies and Spells
##            pickers (pre-filled) so the player edits with multi-rank, specialization,
##            swaps, and the §8.2 bonus-spell roll (gdd §4.2.1). EQUIPMENT is skipped
##            (the template IS the loadout); CLASS_CUSTOMIZATION is skipped (the
##            template locks origin/tradition).
##
## All game logic lives in PcTemplateCreationFlow; this panel only renders its dict
## outputs and seeds creation_state. Built programmatically per §13.2.

var _state: Dictionary = {}
var _flow: PcTemplateCreationFlow
var _template_repo: ClassTemplateRepository
var _catalog: EquipmentCatalog
var _class_registry: ClassRegistry

var _class_id: String = ""
var _int_score: int = 10
var _wealth_roll: int = 0
var _path_b_templates: Array = []          # [ClassTemplate]
var _committed: bool = false

# UI refs
var _roll_btn: Button
var _roll_label: RichTextLabel
var _fork_box: VBoxContainer
var _path_a_btn: Button
var _cards_scroll: ScrollContainer
var _cards_box: VBoxContainer
var _status_label: Label


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
	_class_registry = class_registry
	_class_id = String(_state.get("class_id", ""))
	_int_score = _resolve_int_score()
	if get_child_count() == 0:
		_build_ui()
	_restore_from_state()


func is_complete() -> bool:
	## A path must be committed: Path A chosen, or a Path B template applied.
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
	## Full rehydration (§13.3) — the screen reuses ONE panel instance per PC, so
	## recompute everything from creation_state (never a delta update).
	_wealth_roll = int(_state.get("wealth_roll", 0))
	_path_b_templates = []
	_committed = false
	_status_label.text = ""
	# The roll button is only transiently disabled during the dice prompt; a fresh
	# setup must always re-enable it (else a prior character left it greyed-out).
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

	# A committed path persists in creation_state; reflect it without RE-seeding
	# (the player may have since edited proficiencies/spells downstream).
	var path: String = String(_state.get("template_path", ""))
	if path == "A":
		_committed = true
		_status_label.text = "Kept the gold — click Next to shop, or pick a template below."
	elif path == "B":
		_committed = true
		var t: ClassTemplate = _template_repo.get_template(String(_state.get("template_id", "")))
		if t != null:
			_status_label.text = "%s%s applied — click Next to customise, or pick again below." % [
				_template_label(t), _origin_suffix(t)]


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
	title.text = _template_label(t) + _origin_suffix(t)
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

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


func _template_label(t: ClassTemplate) -> String:
	return t.display_label if t.display_label != "" else t.template_id


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


func _origin_suffix(t: ClassTemplate) -> String:
	## The IP-stripped background a template locks (gdd §6.6 / §9.1) — barbarian
	## region / witch tradition / shaman totem — shown as a parenthetical after the
	## template title (the display label itself omits it). "" when nothing is locked.
	var meta := TemplateClassMetadata.derive(t, _class_registry)
	if meta.has("regional_origin"):
		return " (%s)" % String(meta["regional_origin"]).capitalize()
	if meta.has("witch_tradition"):
		return " (%s)" % String(meta["witch_tradition"]).capitalize()
	if meta.has("shaman_totem"):
		return " (%s totem)" % String(meta["shaman_totem"]).capitalize()
	return ""


# ---------------------------------------------------------------------------
# Path A — keep the gold (§4.1)
# ---------------------------------------------------------------------------

func _on_path_a() -> void:
	_state["template_path"] = "A"
	_state["template_id"] = ""
	_state["origin_template_id"] = ""
	_state["template_class_metadata"] = {}
	var cp: int = _wealth_roll * 10 * 100   # gp → cp
	_state["starting_gold_cp"] = cp
	_state["gold_remaining_cp"] = cp
	# Clear any Path-B seeds (in case the player switched paths). On Path A the later
	# CLASS_CUSTOMIZATION + PROFICIENCIES + SPELLS + EQUIPMENT steps fill these.
	_clear_path_b_prefills()
	_committed = true
	_status_label.text = "Kept %d gp — click Next to continue." % (_wealth_roll * 10)


# ---------------------------------------------------------------------------
# Path B — apply the template and SEED the reused pickers (gdd §4.2.1, §10 step 12)
# ---------------------------------------------------------------------------

func _on_card_selected(t: ClassTemplate) -> void:
	_apply_template(t)


func _apply_template(t: ClassTemplate) -> void:
	var path_b := _flow.choose_path_b(_class_id, t.template_id, _int_score)
	if not bool(path_b.get("ok", false)):
		_status_label.text = "Could not apply template: %s" % String(path_b.get("error", "?"))
		return

	_state["template_path"] = "B"
	_state["template_id"] = t.template_id
	_state["origin_template_id"] = t.template_id

	# Proficiencies: editable (class/general, INT-cull applied) + locked
	# (natural/tradition) → seeded into the reused Proficiencies step, where the
	# player edits with the full picker (multi-rank, specialization, swaps, fills).
	var prof := _flow.template_base_proficiencies(t, _int_score)
	_state["proficiencies"] = prof["selected"]
	_state["bonus_proficiencies"] = prof["locked"]

	# Locked origin/tradition → the metadata merge (finalize) AND the creation_state
	# keys intermediate steps read directly (divine Spells tradition bonus, the
	# equip-restriction validator).
	var meta: Dictionary = path_b.get("class_metadata_locked", {})
	_state["template_class_metadata"] = meta
	_state["barbarian_origin"] = String(meta.get("regional_origin", ""))
	_state["witch_tradition"] = String(meta.get("witch_tradition", ""))

	# Loose coin (§4.1 — the template wealth IS the funds) + equipment loadout.
	var coin_cp: int = int(path_b.get("starting_money_cp", 0))
	_state["starting_gold_cp"] = coin_cp
	_state["gold_remaining_cp"] = coin_cp
	var inventory: Array = []
	for item in path_b.get("equipment", []):
		inventory.append((item as Dictionary).duplicate(true))
	_route_non_catalog(path_b.get("non_catalog_items", []), inventory)
	_state["inventory"] = inventory

	# Arcane BASE repertoire — the §8.2 INT extras are rolled by the player in the
	# reused Spells step. Divine/mundane → empty (the normal Spells step handles
	# divine Path B casters).
	var rep := _flow.template_base_repertoire(_class_id, t.template_id, _int_score)
	if rep.is_empty():
		_state["spells"] = []
		_state["template_extra_spells"] = 0
	else:
		_state["spells"] = rep["spells"]
		_state["template_extra_spells"] = int(rep["extra_spells_to_roll"])

	_committed = true
	var extra: int = int(_state.get("template_extra_spells", 0))
	var tail: String = " and roll bonus spells" if extra > 0 else ""
	_status_label.text = "%s%s applied — click Next to customise proficiencies%s." % [
		_template_label(t), _origin_suffix(t), tail]


func _route_non_catalog(entries: Array, _inventory: Array) -> void:
	## Path B non-catalog items (gdd §4.2 / §10 step 12):
	##   familiar → dropped (the FAMILIAR_ACQUISITION step bonds + persists it; the
	##              template's "familiar" proficiency makes that step appear).
	##   valuable / totem / poison → deferred for v1; logged so nothing is lost
	##              silently (a value-backed-inventory follow-up is tracked).
	var deferred: Array = []
	for nc in entries:
		var meta: Dictionary = (nc as Dictionary).get("metadata", {})
		if String(meta.get("companion_kind", "")) == "familiar":
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
	match String(meta.get("noncatalog_kind", "")):
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
	_state["bonus_proficiencies"] = []
	_state["spells"] = []
	_state["inventory"] = []
	_state["template_class_metadata"] = {}
	_state["template_extra_spells"] = 0
	_state["barbarian_origin"] = ""
	_state["witch_tradition"] = ""


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
	b_lbl.text = "Path B — take a template (you'll customise proficiencies & spells next):"
	b_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fork_box.add_child(b_lbl)

	_cards_scroll = ScrollContainer.new()
	_cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fork_box.add_child(_cards_scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_theme_constant_override("separation", 6)
	_cards_scroll.add_child(_cards_box)

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
