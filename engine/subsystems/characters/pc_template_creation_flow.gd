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


func _init(p_template_repo: ClassTemplateRepository = null,
		p_proficiency_registry: ProficiencyRegistry = null,
		p_catalog: EquipmentCatalog = null) -> void:
	_template_repo = p_template_repo if p_template_repo != null else ClassTemplateRepository.new()
	_proficiency_registry = p_proficiency_registry if p_proficiency_registry != null else ProficiencyRegistry.new()
	_catalog = p_catalog if p_catalog != null else EquipmentCatalog.new()


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
func choose_path_b(class_id: String, template_id: String, int_score: int) -> Dictionary:
	var template: ClassTemplate = _template_repo.get_template(template_id)
	if template == null or template.class_id != class_id:
		return {"ok": false, "error": "template '%s' is not a %s template" % [template_id, class_id]}
	var plan := TemplateIntAdjuster.compute_adjustment(class_id, int_score)
	var equip := ClassedNpcBuilder.equipment_records(template, _catalog)
	return {
		"ok": true, "path": "B",
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
##   }
## Any INT-bonus slots the player left unfilled are auto-filled (engine default),
## so the result always has exactly the right proficiency count.
func finalize_proficiencies(template: ClassTemplate, int_score: int,
		choices: Dictionary = {}) -> Array:
	var plan := TemplateIntAdjuster.compute_adjustment(template.class_id, int_score)
	var kept := TemplateIntAdjuster.cull_proficiencies(
		template.proficiencies, plan, String(choices.get("cull_key", "")))
	var records := ClassedNpcBuilder.proficiency_records(kept)

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
