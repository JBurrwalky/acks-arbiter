class_name PcTemplateCreationFlow
extends RefCounted

## Headless model of the PC-creation template choice point (gdd-class-templates.md
## §4). A console / debug-menu driver calls these methods; the visual UI is
## deferred (gdd §4.2 / §9.3). The flow assumes class + ability scores are already
## chosen (the earlier creation-wizard steps); it drives Step 8 of the procedure:
##
##   1. roll_wealth_and_options() — roll 3d6 -> STARTING_GP (roll x 10) and
##      TEMPLATE_CAP (roll); list the Path B templates at or below the cap (§4.1).
##   2. choose_path_a() — keep the gold and shop / select proficiencies the normal
##      way (the wizard's existing flow); the roll is consumed by gold OR template,
##      never both (§4.1).
##   3. choose_path_b() — take a template at or below the cap; apply it + the §8 INT
##      adjustments; return the §4.2.1 proficiency-editor state and the loadout.
##   4. finalize_proficiencies() — apply the player's editor choices (cull override,
##      extra general picks), auto-filling any remaining INT-bonus slots.
##
## Reuses ClassedNpcBuilder's static record converters and TemplateIntAdjuster so
## PC and NPC template application stay identical (gdd §4.2.1 "the same editor
## logic is invoked headlessly by the NPC builder"). RefCounted, no autoload.

var _template_repo: ClassTemplateRepository
var _proficiency_registry: ProficiencyRegistry
var _catalog: EquipmentCatalog
var _class_registry: ClassRegistry
## Lazily built on first arcane repertoire request (avoids the SpellRegistry load
## for mundane PCs). See build_repertoire().
var _spell_repertoire: TemplateSpellRepertoire = null


func _init(p_template_repo: ClassTemplateRepository = null,
		p_proficiency_registry: ProficiencyRegistry = null,
		p_catalog: EquipmentCatalog = null,
		p_class_registry: ClassRegistry = null) -> void:
	_template_repo = p_template_repo if p_template_repo != null else ClassTemplateRepository.new()
	_proficiency_registry = p_proficiency_registry if p_proficiency_registry != null else ProficiencyRegistry.new()
	_catalog = p_catalog if p_catalog != null else EquipmentCatalog.new()
	_class_registry = p_class_registry if p_class_registry != null else ClassRegistry.new()


# ---------------------------------------------------------------------------
# §4.1 choice point
# ---------------------------------------------------------------------------

## Roll the wealth die and present both paths. [param forced_roll] (3..18) pins the
## roll for deterministic flows; otherwise 3d6 is rolled. Returns:
##   {roll, starting_gp, template_cap, path_b_templates: [ClassTemplate]}
func roll_wealth_and_options(class_id: String, forced_roll: int = 0) -> Dictionary:
	var roll: int = forced_roll
	if roll < 3 or roll > 18:
		roll = DiceSystem.roll_digital(6, 3, 0, "pc_starting_wealth").modified_total
	return {
		"roll": roll,
		"starting_gp": roll * 10,
		"template_cap": roll,
		"path_b_templates": _template_repo.get_templates_for_class_at_or_below_roll(class_id, roll),
	}


## Path A — keep the gold. Proficiency selection (normal class allotment + INT
## bonus generals) and equipment shopping are the existing creation-wizard flow;
## this just hands back the starting funds (no template). The roll is consumed
## here, not by a template (§4.1).
func choose_path_a(roll: int) -> Dictionary:
	return {
		"ok": true, "path": "A",
		"starting_gp": roll * 10,
		"starting_money_cp": roll * 1000,
	}


# ---------------------------------------------------------------------------
# §4 Path B + §4.2.1 editor
# ---------------------------------------------------------------------------

## Path B — take [param template_id] (must belong to [param class_id]). Applies the
## template + §8 INT adjustments and returns the §4.2.1 editor state plus the
## loadout. Eligibility (band <= cap) is the caller's gate. Path B does NOT award
## STARTING_GP — the template's listed wealth IS the starting funds (§4.1).
##
## The returned `template_id` is the value the creation wizard stamps onto the new
## character's `origin_template_id` (gdd §6.4). Path A (choose_path_a) returns no
## `template_id`, so a Path-A character leaves origin_template_id "" (→ DB NULL).
func choose_path_b(class_id: String, template_id: String, int_score: int) -> Dictionary:
	var template: ClassTemplate = _template_repo.get_template(template_id)
	if template == null or template.class_id != class_id:
		return {"ok": false, "error": "template '%s' is not a %s template" % [template_id, class_id]}
	var plan := TemplateIntAdjuster.compute_adjustment(class_id, int_score)
	var equip := ClassedNpcBuilder.equipment_records(template, _catalog)
	return {
		"ok": true, "path": "B",
		# Stamped onto the character's origin_template_id by the wizard (gdd §6.4).
		"template_id": template_id,
		"display_label": template.display_label,
		"tradition": template.tradition,
		"int_score": int_score,
		"int_adjustment": plan,
		"editor": build_editor_state(template, int_score, plan),
		"equipment": equip["equipment"],
		"non_catalog_items": equip["non_catalog"],
		"starting_money_cp": template.starting_money_cp,
		"starting_spells": template.starting_spells.duplicate(),
		"bonus_spell": "" if bool(plan["drop_bonus_spell"]) else template.bonus_spell,
		"extra_spells_to_roll": int(plan["extra_spells_to_roll"]),
		# Class-specific selections this template locks in (gdd §4.4, §9.1; §10
		# step 9) — witch tradition / barbarian region / shaman totem. The creation
		# wizard stamps these onto the new character's class_metadata at finalize.
		"class_metadata_locked": TemplateClassMetadata.derive(template, _class_registry),
	}


## The §4.2.1 proficiency-editor state for a template at the given INT:
##   {
##     class_proficiency: brief,            # locked-by-default (swappable, flagged)
##     class_proficiency_swappable: true,
##     locked_proficiencies: [brief],       # natural / tradition — cannot swap
##     general_proficiencies: [brief],      # freely swappable (incl. the arcane_bonus)
##     cull: {needed, default_key, options} # arcane INT<=12: which general to drop
##     extra_general_slots: int,            # INT-bonus generals the player adds
##     extra_spells_to_roll: int,
##   }
func build_editor_state(template: ClassTemplate, int_score: int,
		plan: Dictionary = {}) -> Dictionary:
	if plan.is_empty():
		plan = TemplateIntAdjuster.compute_adjustment(template.class_id, int_score)
	var class_prof: TemplateProficiency = null
	var locked: Array = []
	var generals: Array = []
	var arcane_bonus: TemplateProficiency = null
	for p: TemplateProficiency in template.proficiencies:
		match p.proficiency_kind:
			"class":
				class_prof = p
			"natural", "tradition":
				locked.append(p)
			"arcane_bonus":
				arcane_bonus = p
			_:
				generals.append(p)
	var cull := {"needed": bool(plan["cull_arcane_bonus"]), "default_key": "", "options": []}
	if cull["needed"]:
		# Default cull = the arcane_bonus; the player may instead cull any general.
		if arcane_bonus != null:
			cull["default_key"] = arcane_bonus.proficiency_key
		for g: TemplateProficiency in generals:
			cull["options"].append(g.proficiency_key)
		if arcane_bonus != null:
			cull["options"].append(arcane_bonus.proficiency_key)
	var swappable_generals: Array = generals.duplicate()
	if arcane_bonus != null:
		swappable_generals.append(arcane_bonus)
	return {
		"class_proficiency": _brief(class_prof),
		"class_proficiency_swappable": true,
		"locked_proficiencies": _briefs(locked),
		"general_proficiencies": _briefs(swappable_generals),
		"cull": cull,
		"extra_general_slots": int(plan["extra_general_proficiencies"]),
		"extra_spells_to_roll": int(plan["extra_spells_to_roll"]),
	}


## Apply the player's editor choices and return the final character_proficiencies
## records. [param choices]:
##   {
##     cull_key: String,             # which general to cull (override; default = arcane_bonus)
##     extra_general_keys: [String], # the player's INT-bonus general picks
##     class_swap_key: String,       # §4.2.1: replace the class proficiency (a meaningful
##                                   #   departure from template intent); "" keeps the
##                                   #   template's. Validated against the class proficiency
##                                   #   list; an invalid / unknown key is ignored.
##     general_swaps: {from_key: to_key}, # §4.2.1: swap a granted general / arcane_bonus
##                                   #   proficiency for another qualified general. natural /
##                                   #   tradition proficiencies are LOCKED (never swapped).
##                                   #   Invalid targets are ignored.
##   }
## Swaps build fresh records rather than mutating the shared (repo-cached)
## TemplateProficiency objects. Any INT-bonus slots the player left unfilled are
## auto-filled (engine default), so the result always has exactly the right count.
## Use swap_options() to populate the editor's dropdowns with valid candidates.
func finalize_proficiencies(template: ClassTemplate, int_score: int,
		choices: Dictionary = {}) -> Array:
	var plan := TemplateIntAdjuster.compute_adjustment(template.class_id, int_score)
	var kept := TemplateIntAdjuster.cull_proficiencies(
		template.proficiencies, plan, String(choices.get("cull_key", "")))

	var class_swap_key := String(choices.get("class_swap_key", ""))
	var general_swaps: Dictionary = choices.get("general_swaps", {})
	var valid_class := _class_proficiency_keys(template.class_id)
	var valid_general := _general_proficiency_keys()

	# Build base records from the (culled) template proficiencies, applying the
	# player's §4.2.1 swaps. Mirrors ClassedNpcBuilder.proficiency_records (skip
	# unresolved keys) but is kind-aware so locked profs are protected and a swap may
	# fill an unresolved class slot the player explicitly re-picked.
	var records: Array = []
	for p: TemplateProficiency in kept:
		match p.proficiency_kind:
			"class":
				if class_swap_key != "" and class_swap_key != p.proficiency_key \
						and class_swap_key in valid_class:
					records.append(_swap_record(class_swap_key, "class"))
				elif p.proficiency_key != "":
					records.append(p.to_record())
			"natural", "tradition":
				if p.proficiency_key != "":
					records.append(p.to_record())  # locked — never swapped
			_:  # general / arcane_bonus — freely swappable
				var to_key := String(general_swaps.get(p.proficiency_key, ""))
				if to_key != "" and to_key != p.proficiency_key and to_key in valid_general:
					records.append(_swap_record(to_key, "general"))
				elif p.proficiency_key != "":
					records.append(p.to_record())

	var want: int = int(plan["extra_general_proficiencies"])
	var chosen: Array = []
	for k in choices.get("extra_general_keys", []):
		if chosen.size() >= want:
			break
		chosen.append(String(k))
	if chosen.size() < want:
		var held: Array = []
		for r: Dictionary in records:
			held.append(String(r["proficiency_key"]))
		held.append_array(chosen)
		chosen.append_array(TemplateIntAdjuster.pick_extra_general_keys(
			want - chosen.size(), held,
			_proficiency_registry.get_general_proficiency_list(), "pc_int_extra"))
	for k in chosen:
		records.append({"proficiency_key": String(k), "rank": 1,
			"slot_type": "general", "selections_count": 1, "specialization": ""})
	return records


# ---------------------------------------------------------------------------
# §7.5.1 / §8.2 arcane spell repertoire (§10 step 11)
# ---------------------------------------------------------------------------

## Build the baseline arcane repertoire a Path B template grants the PC (gdd §7.5.1,
## §8.2), applying the §8 INT adjustment (bonus spell dropped at INT <= 12, extras
## rolled at INT 16+). Mirrors the NPC builder's repertoire path so PC and NPC
## template application stay identical (§4.2.1). The player may then edit their
## spell picks in the (deferred) creation UI; this is the auto-generated starting
## point. Returns the TemplateSpellRepertoire detail dict ({spells, resolved, …}),
## or {} for a non-arcane class / unknown template.
func build_repertoire(class_id: String, template_id: String, int_score: int) -> Dictionary:
	var template: ClassTemplate = _template_repo.get_template(template_id)
	if template == null or template.class_id != class_id:
		return {}
	if not TemplateIntAdjuster.is_arcane_class(class_id):
		return {}
	var plan := TemplateIntAdjuster.compute_adjustment(class_id, int_score)
	var spell_info := TemplateIntAdjuster.adjust_spells(template, plan)
	if _spell_repertoire == null:
		_spell_repertoire = TemplateSpellRepertoire.new(null, _class_registry)
	return _spell_repertoire.build_repertoire(
		class_id, 1, int_score,
		spell_info["starting_spells"], String(spell_info["bonus_spell"]),
		int(spell_info["extra_spells_to_roll"]), "pc_rep_%s" % template_id)


# ---------------------------------------------------------------------------
# §10 step 12 — seed the reused Proficiencies / Spells steps (Path B)
# ---------------------------------------------------------------------------

## The editable + locked proficiency split a Path B template seeds into the reused
## Proficiencies step (gdd §4.2.1 — the player then edits with the full picker:
## multi-rank, specialization, swaps, and INT-bonus fills). The §8 INT cull (default
## = the arcane_bonus at INT <= 12) is applied here so the seeded count matches the
## picker's slot math (1 class + 1 general + INT-mod generals); INT-bonus extras are
## NOT auto-filled — the player fills those empty slots. Returns:
##   { selected: [record],  # slot_type class/general — creation_state.proficiencies
##     locked:   [record] }  # natural/tradition — creation_state.bonus_proficiencies
func template_base_proficiencies(template: ClassTemplate, int_score: int) -> Dictionary:
	var plan := TemplateIntAdjuster.compute_adjustment(template.class_id, int_score)
	var kept := TemplateIntAdjuster.cull_proficiencies(template.proficiencies, plan, "")
	var selected: Array = []
	var locked: Array = []
	for p: TemplateProficiency in kept:
		if p.proficiency_key == "":
			continue
		if p.is_locked():
			locked.append(p.to_record())  # natural / tradition — non-removable grant
		else:
			selected.append(p.to_record())
	return {"selected": selected, "locked": locked}


## The BASE arcane repertoire a Path B template grants, BEFORE the §8.2 INT extras —
## those are rolled by the player in the reused Spells step (gdd §4.2.1 "rolls the
## bonus spell here"). Same as build_repertoire but with 0 auto-rolled extras, plus
## the extra count for the Spells panel to drive its roll. Returns:
##   { spells: [character_spells row], extra_spells_to_roll: int, arcane: true }
## or {} for a non-arcane / unknown template (the normal divine Spells step handles
## divine Path B casters).
func template_base_repertoire(class_id: String, template_id: String, int_score: int) -> Dictionary:
	var template: ClassTemplate = _template_repo.get_template(template_id)
	if template == null or template.class_id != class_id:
		return {}
	if not TemplateIntAdjuster.is_arcane_class(class_id):
		return {}
	var plan := TemplateIntAdjuster.compute_adjustment(class_id, int_score)
	var spell_info := TemplateIntAdjuster.adjust_spells(template, plan)
	if _spell_repertoire == null:
		_spell_repertoire = TemplateSpellRepertoire.new(null, _class_registry)
	var base := _spell_repertoire.build_repertoire(
		class_id, 1, int_score,
		spell_info["starting_spells"], String(spell_info["bonus_spell"]),
		0, "pc_rep_%s" % template_id)   # 0 → do NOT auto-roll the §8.2 extras
	return {
		"spells": base.get("spells", []),
		"extra_spells_to_roll": int(spell_info["extra_spells_to_roll"]),
		"arcane": true,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _brief(p: TemplateProficiency) -> Dictionary:
	if p == null:
		return {}
	return {
		"name": p.name,
		"proficiency_key": p.proficiency_key,
		"flavor": p.flavor,
		"proficiency_kind": p.proficiency_kind,
		"rank": p.rank,
	}


func _briefs(profs: Array) -> Array:
	var out: Array = []
	for p: TemplateProficiency in profs:
		out.append(_brief(p))
	return out


# ---------------------------------------------------------------------------
# §4.2.1 proficiency-swap support (full editor — §10 step 12)
# ---------------------------------------------------------------------------

## Candidate proficiency keys for the editor's swap dropdowns (gdd §4.2.1):
##   {
##     class_options: [String],   # the class's full class-proficiency list (the editor shows
##                                #   the template's pick as the default selection)
##     general_options: [String], # general keys NOT already granted by the template, so a swap
##                                #   target is always net-new (avoids duplicate proficiency rows)
##   }
func swap_options(template: ClassTemplate) -> Dictionary:
	var held := {}
	for p: TemplateProficiency in template.proficiencies:
		if p.proficiency_key != "":
			held[p.proficiency_key] = true
	var general_options: Array = []
	for k in _general_proficiency_keys():
		if not held.has(k):
			general_options.append(k)
	return {
		"class_options": _class_proficiency_keys(template.class_id),
		"general_options": general_options,
	}


## The class-proficiency key list for [param class_id] (the same source the
## ProficiencySelectionPanel uses for its class tab).
func _class_proficiency_keys(class_id: String) -> Array:
	var out: Array = []
	for k in _class_registry.get_class_def(class_id).get("class_proficiency_list", []):
		out.append(String(k))
	return out


## The general-proficiency key list, excluding the auto-granted "adventuring".
func _general_proficiency_keys() -> Array:
	var out: Array = []
	for k in _proficiency_registry.get_general_proficiency_list():
		if String(k) != "adventuring":
			out.append(String(k))
	return out


## A fresh character_proficiencies record for a swapped proficiency (rank resets to
## 1 — a different proficiency starts at journeyman with no carried specialization).
func _swap_record(key: String, slot_type: String) -> Dictionary:
	return {
		"proficiency_key": key,
		"rank": 1,
		"slot_type": slot_type,
		"selections_count": 1,
		"specialization": "",
	}
