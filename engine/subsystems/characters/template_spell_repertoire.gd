class_name TemplateSpellRepertoire
extends RefCounted

## Wires an arcane class template's starting spells into a character's spell
## repertoire (gdd-class-templates.md §7.5.1, §8.2; §10 step 11). Bridges the
## CURATED template spells with the GENERIC RepertoireEngine growth so the same
## path serves an L1 template caster and a higher-level NPC rival.
##
## For an arcane caster (mage / warlock / elven_enchanter / elven_spellsword /
## lightblessed_wonderworker):
##   1. The template's starting_spells + bonus_spell (already INT-adjusted by the
##      caller — bonus_spell is "" at INT <= 12) resolve to spell_keys.
##   2. At L1: the §8.2 INT extras (extra_spells_to_roll: 1 at INT 16-17, 2 at 18)
##      are rolled on the arcane L1 list (no reroll on a duplicate — ACKS gives
##      fewer spells, not a reroll).
##   3. At level > 1: the repertoire is grown to the class's level-N capacity
##      (RepertoireEngine.get_arcane_repertoire_capacity) — this fill SUBSUMES the
##      L1 INT extras (capacity already folds in the INT modifier), so they are not
##      double-counted.
##
## Returns character_spells row records ({spell_key, spell_level, is_in_repertoire,
## is_memorized, memorized_slots}) ready for CampaignRepository.save_character_spells.
## Non-arcane classes return an empty repertoire (divine casters get their full list
## elsewhere via RepertoireEngine.generate_divine_starting_repertoire). RefCounted,
## no autoload; deps injectable (mirrors RepertoireEngine).

var _spell_registry: SpellRegistry
var _class_registry: ClassRegistry
var _repertoire_engine: RepertoireEngine


func _init(p_spell_registry: SpellRegistry = null,
		p_class_registry: ClassRegistry = null,
		p_repertoire_engine: RepertoireEngine = null) -> void:
	_spell_registry = p_spell_registry if p_spell_registry != null else SpellRegistry.new()
	_class_registry = p_class_registry if p_class_registry != null else ClassRegistry.new()
	if p_repertoire_engine != null:
		_repertoire_engine = p_repertoire_engine
	else:
		_repertoire_engine = RepertoireEngine.new(_spell_registry, _class_registry)


## A template spell NAME (the importer stores lowercase prose, e.g. "magic missile",
## "darkness") -> a runtime spell_key ("magic_missile"). Apostrophes are dropped.
## "darkness" resolves at runtime as the synthetic reverse form of Light. Pure.
static func name_to_key(spell_name: String) -> String:
	return spell_name.strip_edges().to_lower().replace("'", "").replace(" ", "_")


func is_arcane(class_id: String) -> bool:
	return TemplateIntAdjuster.is_arcane_class(class_id)


## Build the full repertoire records for an arcane caster. Returns:
##   {
##     spells:     [character_spells row],   # the whole repertoire
##     resolved:   [spell_key],              # template spells that resolved
##     unresolved: [spell_name],             # template spells that did NOT resolve
##     rolled:     [spell_key],              # L1 §8.2 INT-extra rolls that landed
##     grown:      [spell_key],              # level>1 capacity-fill additions
##   }
## [param starting_spells] / [param bonus_spell] / [param extra_spells_to_roll] are
## the INT-adjusted values from TemplateIntAdjuster.adjust_spells (the caller drops
## the bonus spell at INT <= 12). [param rng_label] tags the spell rolls. Non-arcane
## classes return an empty result.
func build_repertoire(class_id: String, level: int, intelligence: int,
		starting_spells: Array, bonus_spell: String,
		extra_spells_to_roll: int, rng_label: String = "template_repertoire") -> Dictionary:
	var result := {"spells": [], "resolved": [], "unresolved": [],
		"rolled": [], "grown": []}
	if not is_arcane(class_id):
		return result

	var known := {}  # spell_key -> true (dedup across template + rolled + grown)

	# 1. Template spells (starting + the INT-kept bonus spell).
	var template_names: Array = starting_spells.duplicate()
	if bonus_spell.strip_edges() != "":
		template_names.append(bonus_spell)
	for raw_name in template_names:
		var name := String(raw_name)
		var key := name_to_key(name)
		if _spell_registry.has_spell(key):
			if not known.has(key):
				known[key] = true
				result["spells"].append(_row(key))
				result["resolved"].append(key)
		else:
			result["unresolved"].append(name)

	if level <= 1:
		# 2. §8.2 INT-extra rolls (1 at INT 16-17, 2 at 18) on the arcane L1 list.
		for _i in maxi(0, extra_spells_to_roll):
			var key := _roll_on_level(1, known, rng_label)
			if key != "":
				known[key] = true
				result["spells"].append(_row(key))
				result["rolled"].append(key)
	else:
		# 3. Grow to the class's level-N capacity (RepertoireEngine). The fill folds
		# in the INT modifier, so the L1 INT extras are NOT separately rolled here.
		var capacity := _repertoire_engine.get_arcane_repertoire_capacity(
			class_id, level, intelligence)
		for spell_level in range(1, capacity.size() + 1):
			var cap := int(capacity[spell_level - 1])
			var have := _count_at_level(result["spells"], spell_level)
			var needed := cap - have
			var attempts := 0
			var max_attempts := needed * 4 + 8  # bounded; dedup may exhaust early
			while needed > 0 and attempts < max_attempts:
				attempts += 1
				var key := _roll_on_level(spell_level, known, "%s_l%d" % [rng_label, spell_level])
				if key == "":
					continue
				known[key] = true
				result["spells"].append(_row(key))
				result["grown"].append(key)
				needed -= 1
	return result


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Roll once on the arcane list for [param spell_level] and return a NEW (not in
## [param known], catalog-valid) spell_key, or "" on a duplicate / empty list.
## Uses a 1-based index roll matching RepertoireEngine's d12 convention; an
## out-of-range index (shorter list) clamps in range.
func _roll_on_level(spell_level: int, known: Dictionary, label: String) -> String:
	var list := _spell_registry.get_spells_for_list("arcane", spell_level)
	if list.is_empty():
		return ""
	var roll := DiceSystem.roll_digital(list.size(), 1, 0, label).modified_total  # 1..size
	var idx := clampi(roll - 1, 0, list.size() - 1)
	var key := String(list[idx])
	if known.has(key) or not _spell_registry.has_spell(key):
		return ""
	return key


func _row(spell_key: String) -> Dictionary:
	return {
		"spell_key": spell_key,
		"spell_level": _arcane_level(spell_key),
		"is_in_repertoire": true,
		"is_memorized": false,
		"memorized_slots": 0,
	}


## The arcane-tradition level of a spell (default 1 if unclassified).
func _arcane_level(spell_key: String) -> int:
	var entry := _spell_registry.get_spell(spell_key)
	for classification in entry.get("classifications", []):
		if String(classification.get("tradition", "")) == "arcane":
			return int(classification.get("level", 1))
	return 1


static func _count_at_level(rows: Array, spell_level: int) -> int:
	var n := 0
	for r: Dictionary in rows:
		if int(r.get("spell_level", 0)) == spell_level:
			n += 1
	return n
