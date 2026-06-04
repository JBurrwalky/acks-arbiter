class_name TemplateIntAdjuster
extends RefCounted

## INT adjustment pipeline for class templates (gdd-class-templates.md §8).
##
## Templates assume an INT-12-or-less baseline (§2). For MUNDANE classes, INT 13+
## grants extra GENERAL proficiencies equal to the ACKS INT modifier. ARCANE
## templates additionally assume INT 13-15 (a bonus proficiency + bonus spell are
## baked in, §8.2), so:
##   INT <= 12  -> cull the arcane_bonus proficiency (the position-3 entry) AND
##                drop the italicized bonus spell;
##   INT 13-15  -> as written;
##   INT 16-17  -> add 1 general proficiency + 1 randomly-rolled spell;
##   INT 18     -> add 2 general proficiencies + 2 randomly-rolled spells.
##
## Pure §8 logic. The random extra-spell rolls are the spell-repertoire picker's
## job (§10 step 11) — this surfaces the COUNT, it does not roll them. Filling the
## extra general slots is the caller's policy: the player picks in the §4.2.1
## editor, the engine auto-picks for NPCs (pick_extra_general_keys).
##
## RAW NOTE: gdd §8.1's `floor((INT-11)/2)` formula is INCORRECT (it yields 2 at
## INT 15 and 3 at INT 17); the explicit table in §8.1 — which equals the ACKS INT
## ability modifier floored at 0 (acore_proficiencies_rules_and_catalog.xml:1066) —
## is authoritative, and that is what compute_adjustment() implements.

## Arcane spellcaster classes whose templates bake in the INT-13-15 bonus
## (gdd §2, §8.2). Mirrors the importer's ARCANE_CLASSES.
const ARCANE_CLASSES := [
	"mage", "warlock", "elven_enchanter", "elven_spellsword",
	"lightblessed_wonderworker",
]


static func is_arcane_class(class_id: String) -> bool:
	return class_id in ARCANE_CLASSES


## The §8 adjustment plan for a (class, INT) pair. Pure data:
##   {
##     is_arcane: bool,
##     extra_general_proficiencies: int,   # general slots to ADD
##     cull_arcane_bonus: bool,            # arcane + INT <= 12: drop the position-3 prof
##     drop_bonus_spell: bool,             # arcane + INT <= 12: drop the 2nd listed spell
##     extra_spells_to_roll: int,          # arcane: 16-17 -> 1, 18 -> 2 (rolled by §10 step 11)
##   }
static func compute_adjustment(class_id: String, int_score: int) -> Dictionary:
	var arcane := is_arcane_class(class_id)
	var plan := {
		"is_arcane": arcane,
		"extra_general_proficiencies": 0,
		"cull_arcane_bonus": false,
		"drop_bonus_spell": false,
		"extra_spells_to_roll": 0,
	}
	if arcane:
		if int_score <= 12:
			plan["cull_arcane_bonus"] = true
			plan["drop_bonus_spell"] = true
		elif int_score <= 15:
			pass  # template as written (the baked-in INT-13-15 bonus stands)
		elif int_score <= 17:
			plan["extra_general_proficiencies"] = 1
			plan["extra_spells_to_roll"] = 1
		else:  # 18+
			plan["extra_general_proficiencies"] = 2
			plan["extra_spells_to_roll"] = 2
	else:
		plan["extra_general_proficiencies"] = maxi(0, CharacterData.ability_modifier(int_score))
	return plan


## Apply the §8.2 cull to a template's proficiency list. At arcane INT <= 12 the
## default culls the arcane_bonus (position-3) proficiency; a non-empty
## [param override_cull_key] instead culls the first GENERAL proficiency with that
## key (the §4.2.1 player override), falling back to the arcane_bonus if the key
## matches nothing. Returns a new Array[TemplateProficiency]; does NOT add the
## extra general slots (that is slot-filling, the caller's policy).
static func cull_proficiencies(proficiencies: Array, plan: Dictionary,
		override_cull_key: String = "") -> Array:
	if not bool(plan.get("cull_arcane_bonus", false)):
		return proficiencies.duplicate()
	var kept: Array = []
	var culled := false
	for p: TemplateProficiency in proficiencies:
		var is_target: bool
		if override_cull_key != "":
			is_target = (not culled) and p.proficiency_kind == "general" \
				and p.proficiency_key == override_cull_key
		else:
			is_target = (not culled) and p.proficiency_kind == "arcane_bonus"
		if is_target:
			culled = true
			continue
		kept.append(p)
	if not culled:
		# override key matched no general — fall back to culling the arcane_bonus.
		for i in range(kept.size()):
			if (kept[i] as TemplateProficiency).proficiency_kind == "arcane_bonus":
				kept.remove_at(i)
				break
	return kept


## The adjusted spell info for [param template] under [param plan]. starting_spells
## are unchanged; the italicized bonus_spell is dropped at arcane INT <= 12;
## extra_spells_to_roll (0/1/2) is surfaced for the spell-repertoire picker.
static func adjust_spells(template: ClassTemplate, plan: Dictionary) -> Dictionary:
	return {
		"starting_spells": template.starting_spells.duplicate(),
		"bonus_spell": "" if bool(plan.get("drop_bonus_spell", false)) else template.bonus_spell,
		"extra_spells_to_roll": int(plan.get("extra_spells_to_roll", 0)),
	}


## Engine-policy picker for the extra general proficiencies an NPC gains (PCs pick
## their own in the §4.2.1 editor). Returns up to [param count] general keys from
## [param general_list], excluding [param exclude_keys] and "adventuring", chosen
## at random via DiceSystem. Returns fewer than [param count] only if the pool is
## exhausted.
static func pick_extra_general_keys(count: int, exclude_keys: Array,
		general_list: Array, rng_label: String = "template_int_extra") -> Array:
	var picked: Array = []
	if count <= 0:
		return picked
	var pool: Array = []
	for k in general_list:
		var key := String(k)
		if key != "adventuring" and key not in exclude_keys:
			pool.append(key)
	for _i in count:
		if pool.is_empty():
			break
		var idx := DiceSystem.roll_digital(pool.size(), 1, -1, rng_label).modified_total
		idx = clampi(idx, 0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked
