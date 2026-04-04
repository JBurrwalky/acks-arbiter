class_name RepertoireEngine
extends RefCounted

## Calculates starting spell repertoires for arcane and divine casters.
## Enforces ACKS 1e rules:
##   Arcane: d12 per indexed list level, capacity = slots + INT modifier (>=0)
##   Divine: full spell list for all castable levels, both forms of reversible spells
## All randomness routes through DiceSystem for roll transparency and test overrides.

var spell_registry: SpellRegistry
var class_registry: ClassRegistry


func _init(p_spell_registry: SpellRegistry, p_class_registry: ClassRegistry) -> void:
	spell_registry = p_spell_registry
	class_registry = p_class_registry


# ---------------------------------------------------------------------------
# Tradition detection
# ---------------------------------------------------------------------------

func get_casting_tradition(class_id: String) -> String:
	## Returns "arcane", "divine", or "" for non-casters.
	return spell_registry.get_class_tradition(class_id, class_registry)


# ---------------------------------------------------------------------------
# Arcane capacity
# ---------------------------------------------------------------------------

func get_arcane_repertoire_capacity(class_id: String, character_level: int, intelligence: int) -> Array[int]:
	## Returns max spells per spell level as an array indexed 0 = level 1, etc.
	## Capacity = spell_slots + max(0, INT modifier) for levels with slots > 0.
	var int_bonus := maxi(CharacterData.ability_modifier(intelligence), 0)
	var slots_array := class_registry.get_spell_slots(class_id, character_level)
	if slots_array.is_empty():
		return []
	var capacity: Array[int] = []
	for slots in slots_array:
		var s := int(slots)
		if s > 0:
			capacity.append(s + int_bonus)
		else:
			capacity.append(0)
	return capacity


# ---------------------------------------------------------------------------
# Arcane starting repertoire
# ---------------------------------------------------------------------------

func generate_arcane_starting_repertoire(class_id: String, intelligence: int,
		judge_selected_spell: String = "") -> Dictionary:
	## Generates the starting repertoire for an arcane caster (1st level).
	## Procedure (ACKS core, acore_spellcaster_rules.xml):
	##   1. One judge-selected 1st-level spell (or auto-first if empty).
	##   2. For each point of INT modifier (>=0): roll 1d12 on the arcane level 1 list.
	##   3. Duplicates do NOT reroll — character simply gets fewer spells.
	var int_mod := CharacterData.ability_modifier(intelligence)
	var bonus_rolls := maxi(int_mod, 0)

	var spells: Array[Dictionary] = []
	var roll_results: Array = []
	var known_keys: Dictionary = {}  # spell_key -> true (dedup set)

	# Step 1: judge-selected spell
	var judge_spell := judge_selected_spell
	if judge_spell.is_empty():
		# Auto-select: first spell on the arcane level 1 list
		var level1_list := spell_registry.get_spells_for_list("arcane", 1)
		if not level1_list.is_empty():
			judge_spell = level1_list[0]

	if not judge_spell.is_empty() and spell_registry.has_spell(judge_spell):
		var entry := spell_registry.get_spell(judge_spell)
		var level := _get_spell_level_for_tradition(entry, "arcane")
		spells.append({
			"spell_key": judge_spell,
			"spell_level": level,
			"is_in_repertoire": true,
			"is_memorized": false,
			"memorized_slots": 0,
		})
		known_keys[judge_spell] = true

	# Step 2: bonus rolls from INT modifier
	for _i in range(bonus_rolls):
		var roll := DiceSystem.roll_digital(12, 1, 0, "starting_spell")
		var index := roll.modified_total
		roll_results.append(index)
		var spell_key := spell_registry.get_arcane_index_spell(1, index)
		if spell_key.is_empty():
			continue
		if known_keys.has(spell_key):
			continue  # duplicate: ACKS rules say no reroll, just fewer spells
		if not spell_registry.has_spell(spell_key):
			continue
		known_keys[spell_key] = true
		var entry := spell_registry.get_spell(spell_key)
		spells.append({
			"spell_key": spell_key,
			"spell_level": _get_spell_level_for_tradition(entry, "arcane"),
			"is_in_repertoire": true,
			"is_memorized": false,
			"memorized_slots": 0,
		})

	return {
		"tradition": "arcane",
		"spells": spells,
		"roll_results": roll_results,
	}


# ---------------------------------------------------------------------------
# Divine starting repertoire
# ---------------------------------------------------------------------------

func generate_divine_starting_repertoire(class_id: String, character_level: int) -> Dictionary:
	## Generates the starting repertoire for a divine caster.
	## Divine casters know ALL spells on their list for each castable level.
	## Reversible spells: both forms are known automatically.
	var slots_array := class_registry.get_spell_slots(class_id, character_level)
	var spells: Array[Dictionary] = []

	if slots_array.is_empty():
		return {"tradition": "divine", "spells": spells}

	var list_id := spell_registry.get_class_spell_list_id(class_id, class_registry)
	if list_id.is_empty():
		return {"tradition": "divine", "spells": spells}

	for level_idx in range(slots_array.size()):
		var spell_level := level_idx + 1
		var slot_count := int(slots_array[level_idx])
		if slot_count == 0:
			continue

		var available := spell_registry.get_available_spells_for_class(class_id, spell_level, class_registry)
		for spell_key in available:
			if not spell_registry.has_spell(spell_key):
				continue
			spells.append({
				"spell_key": spell_key,
				"spell_level": spell_level,
				"is_in_repertoire": true,
				"is_memorized": false,
				"memorized_slots": 0,
			})
			# For reversible divine spells: add the reversed form as a separate entry
			if spell_registry.is_reversible(spell_key):
				var rev_key := spell_registry.get_reverse_key(spell_key)
				if not rev_key.is_empty():
					spells.append({
						"spell_key": rev_key,
						"spell_level": spell_level,
						"is_in_repertoire": true,
						"is_memorized": false,
						"memorized_slots": 0,
					})

	return {"tradition": "divine", "spells": spells}


# ---------------------------------------------------------------------------
# Divine incremental grant (level-up)
# ---------------------------------------------------------------------------

func generate_divine_spells_for_new_levels(class_id: String,
		new_levels: Array) -> Array[Dictionary]:
	## Generates spell records for the given spell levels only.
	## Used at level-up when a divine caster unlocks new spell level(s).
	## new_levels: Array[int] — 1-based spell levels that just became accessible.
	## Returns Array[Dictionary] in character_spells row shape (is_in_repertoire=true).
	## Handles reversible spells: both forms added automatically.
	var spells: Array[Dictionary] = []
	if new_levels.is_empty():
		return spells
	var list_id := spell_registry.get_class_spell_list_id(class_id, class_registry)
	if list_id.is_empty():
		return spells
	for spell_level in new_levels:
		var available := spell_registry.get_available_spells_for_class(
			class_id, spell_level, class_registry)
		for spell_key in available:
			if not spell_registry.has_spell(spell_key):
				continue
			spells.append({
				"spell_key": spell_key,
				"spell_level": spell_level,
				"is_in_repertoire": true,
				"is_memorized": false,
				"memorized_slots": 0,
			})
			if spell_registry.is_reversible(spell_key):
				var rev_key := spell_registry.get_reverse_key(spell_key)
				if not rev_key.is_empty():
					spells.append({
						"spell_key": rev_key,
						"spell_level": spell_level,
						"is_in_repertoire": true,
						"is_memorized": false,
						"memorized_slots": 0,
					})
	return spells


# ---------------------------------------------------------------------------
# Unified entry point
# ---------------------------------------------------------------------------

func generate_starting_repertoire(class_id: String, character_level: int,
		intelligence: int, judge_selected_spell: String = "") -> Dictionary:
	## Detects tradition and delegates to the appropriate method.
	## Returns empty dict for non-casters.
	var tradition := get_casting_tradition(class_id)
	match tradition:
		"arcane":
			return generate_arcane_starting_repertoire(class_id, intelligence, judge_selected_spell)
		"divine":
			return generate_divine_starting_repertoire(class_id, character_level)
		_:
			return {}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_spell_level_for_tradition(entry: Dictionary, tradition: String) -> int:
	## Returns the level of a spell entry for the given tradition.
	for classification in entry.get("classifications", []):
		if classification.get("tradition", "") == tradition:
			return int(classification.get("level", 1))
	return 1
