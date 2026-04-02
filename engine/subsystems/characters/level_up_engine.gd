class_name LevelUpEngine
extends RefCounted

## Level-Up Engine for ACKS 1e.
## Source: acore_adventures_and_encounters.xml lines 669-680 (advancement procedure).
##
## Orchestrates the full level-up sequence:
##   1. HP roll (hit die + CON mod, min 1; fixed HP past max HD count)
##   2. Attack throw and saving throw updates from ClassRegistry
##   3. Level title update
##   4. xp_for_next_level update
##   5. Proficiency slot detection
##   6. Spell slot expansion detection (casters)
##   7. New class power unlocks
##
## Two paths:
##   apply_level_up_auto()     — NPCs and henchmen; silent, no player choices
##   begin_interactive_level_up() + finalize_interactive_level_up() — PCs
##
## Persistence via CampaignRepository. Signals via EventBus.

var _class_registry: ClassRegistry
var _power_registry: PowerRegistry
var _proficiency_registry: ProficiencyRegistry


func _init(p_class_registry: ClassRegistry, p_power_registry: PowerRegistry,
		p_proficiency_registry: ProficiencyRegistry = null) -> void:
	_class_registry = p_class_registry
	_power_registry = p_power_registry
	_proficiency_registry = p_proficiency_registry


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

func can_level_up(character: CharacterData) -> bool:
	## True if the character has enough XP to advance and is not at max level.
	if character.level >= character.max_level:
		return false
	if character.level == 0:
		# 0th-level: eligible at 100 XP (or 500 XP per henchman GDD).
		# Returning true here; the caller should check requires_class_selection in the result.
		return character.xp >= 100
	return character.xp_for_next_level > 0 and character.xp >= character.xp_for_next_level


# ---------------------------------------------------------------------------
# HP Rolling
# ---------------------------------------------------------------------------

func roll_level_up_hp(character: CharacterData) -> int:
	## Calculate the HP gained for a single new level.
	## New level = character.level + 1 (call this BEFORE incrementing level).
	## Returns the HP delta to ADD to hp_max.
	var new_level := character.level + 1
	var max_hd_count := _class_registry.get_max_hd_count(character.character_class)
	var con_mod := CharacterData.ability_modifier(character.constitution)

	if new_level <= max_hd_count:
		# Roll the hit die for this level.
		var hit_die_str := _class_registry.get_hit_die(character.character_class)
		var sides := _parse_hit_die_sides(hit_die_str)
		var roll: RollResult = DiceSystem.roll_digital(sides, 1, 0,
			"level_up_hp_L%d" % new_level)
		return maxi(roll.modified_total + con_mod, 1)
	else:
		# Fixed HP per level past max HD count — no CON modifier.
		return _class_registry.get_hp_after_max_hd(character.character_class)


func _parse_hit_die_sides(hit_die: String) -> int:
	if "d" in hit_die:
		var parts := hit_die.split("d")
		if parts.size() >= 2 and parts[1].is_valid_int():
			return int(parts[1])
	return 8


# ---------------------------------------------------------------------------
# Auto Level-Up (NPCs / henchmen)
# ---------------------------------------------------------------------------

func apply_level_up_auto(character: CharacterData) -> Dictionary:
	## Perform a complete automatic level-up. Persists all changes to DB.
	## Used for NPCs and henchmen where no player choices are needed.
	## Returns a result dictionary describing what changed.
	if not can_level_up(character):
		push_error("LevelUpEngine.apply_level_up_auto: character '%s' cannot level up (level=%d, xp=%d, next=%d)" % [
			character.id, character.level, character.xp, character.xp_for_next_level])
		return {}

	# Handle 0th-level case.
	if character.level == 0:
		return {"requires_class_selection": true, "character_id": character.id}

	var result := _compute_level_up(character)
	_apply_stat_changes(character, result)

	# Auto-select new proficiency slots.
	var new_class_slots: int = result.get("new_class_proficiency_slots", 0)
	var new_general_slots: int = result.get("new_general_proficiency_slots", 0)
	if (new_class_slots + new_general_slots) > 0:
		var generator := CharacterGenerator.new(_class_registry, _power_registry,
			_proficiency_registry)
		# Load existing proficiencies.
		var existing_profs: Array = CampaignRepository.get_character_proficiencies(character.id)
		# Auto-select only the new slots.
		var new_profs := generator.auto_select_proficiencies(
			character.character_class, character.level)
		# Merge: keep existing, add newly selected ones (avoid duplicates by proficiency_key).
		var merged := existing_profs.duplicate()
		var existing_keys: Dictionary = {}
		for p in existing_profs:
			existing_keys[p.get("proficiency_key", "")] = true
		for p in new_profs:
			if not existing_keys.has(p.get("proficiency_key", "")):
				merged.append(p)
		CampaignRepository.save_character_proficiencies(character.id, merged)

	# Unlock new class powers.
	var new_powers: Array = result.get("new_powers", [])
	if not new_powers.is_empty():
		var existing_powers: Array = CampaignRepository.get_character_powers(character.id)
		var existing_power_ids: Dictionary = {}
		for p in existing_powers:
			existing_power_ids[p.get("power_id", "")] = true
		for power_id in new_powers:
			if not existing_power_ids.has(power_id):
				existing_powers.append({
					"power_id": power_id,
					"unlock_level": character.level,
					"conditions": "[]",
					"progression_data": "{}",
					"is_active": true,
				})
		CampaignRepository.save_character_powers(character.id, existing_powers)

	# Persist stat changes.
	CampaignRepository.update_character_fields(character.id, {
		"level":              character.level,
		"xp_for_next_level":  character.xp_for_next_level,
		"title":              character.title,
		"hp_max":             character.hp_max,
		"hp_current":         character.hp_current,
		"attack_throw":       character.attack_throw,
		"save_petrification": character.save_petrification,
		"save_poison_death":  character.save_poison_death,
		"save_blast_breath":  character.save_blast_breath,
		"save_staffs_wands":  character.save_staffs_wands,
		"save_spells":        character.save_spells,
	})

	EventBus.character_leveled_up.emit(character.id, character.level)
	return result


# ---------------------------------------------------------------------------
# Interactive Level-Up (PCs)
# ---------------------------------------------------------------------------

func begin_interactive_level_up(character: CharacterData) -> Dictionary:
	## Perform the automatic parts of a PC level-up, returning a result dict
	## that describes what automated changes occurred and what choices remain.
	##
	## Does NOT persist. Call finalize_interactive_level_up() after player choices.
	##
	## Returns a result dict (see _compute_level_up for structure) plus the
	## mutated character for UI display. The stat changes ARE applied to character
	## in-memory here so the UI can show the new values immediately.
	if not can_level_up(character):
		push_error("LevelUpEngine.begin_interactive_level_up: character '%s' cannot level up" % character.id)
		return {}

	if character.level == 0:
		return {"requires_class_selection": true, "character_id": character.id}

	var result := _compute_level_up(character)
	_apply_stat_changes(character, result)
	return result


func finalize_interactive_level_up(character: CharacterData,
		level_up_result: Dictionary, choices: Dictionary) -> bool:
	## Persist a PC level-up after the player has made proficiency/spell choices.
	##
	## choices: {
	##   "proficiencies": Array[Dictionary],  # new prof records to add
	##   "spells": Array[Dictionary],          # new spell records to add
	## }
	##
	## The character's stat fields (level, hp_max, attack, saves, title) should
	## already be mutated by begin_interactive_level_up().

	# Persist new proficiencies.
	var new_profs: Array = choices.get("proficiencies", [])
	if not new_profs.is_empty():
		var existing_profs: Array = CampaignRepository.get_character_proficiencies(character.id)
		var merged := existing_profs.duplicate()
		var existing_keys: Dictionary = {}
		for p in existing_profs:
			existing_keys[p.get("proficiency_key", "")] = true
		for p in new_profs:
			if not existing_keys.has(p.get("proficiency_key", "")):
				merged.append(p)
		if not CampaignRepository.save_character_proficiencies(character.id, merged):
			push_error("LevelUpEngine.finalize_interactive_level_up: failed to save proficiencies")
			return false

	# Persist new spells.
	var new_spells: Array = choices.get("spells", [])
	for spell in new_spells:
		CampaignRepository.add_character_spell(character.id, spell)

	# Unlock new class powers.
	var new_powers: Array = level_up_result.get("new_powers", [])
	if not new_powers.is_empty():
		var existing_powers: Array = CampaignRepository.get_character_powers(character.id)
		var existing_power_ids: Dictionary = {}
		for p in existing_powers:
			existing_power_ids[p.get("power_id", "")] = true
		for power_id in new_powers:
			if not existing_power_ids.has(power_id):
				existing_powers.append({
					"power_id": power_id,
					"unlock_level": character.level,
					"conditions": "[]",
					"progression_data": "{}",
					"is_active": true,
				})
		CampaignRepository.save_character_powers(character.id, existing_powers)

	# Persist stat changes.
	if not CampaignRepository.update_character_fields(character.id, {
		"level":              character.level,
		"xp_for_next_level":  character.xp_for_next_level,
		"title":              character.title,
		"hp_max":             character.hp_max,
		"hp_current":         character.hp_current,
		"attack_throw":       character.attack_throw,
		"save_petrification": character.save_petrification,
		"save_poison_death":  character.save_poison_death,
		"save_blast_breath":  character.save_blast_breath,
		"save_staffs_wands":  character.save_staffs_wands,
		"save_spells":        character.save_spells,
	}):
		push_error("LevelUpEngine.finalize_interactive_level_up: failed to persist stat changes")
		return false

	EventBus.character_leveled_up.emit(character.id, character.level)
	return true


# ---------------------------------------------------------------------------
# Core Computation (shared by auto and interactive paths)
# ---------------------------------------------------------------------------

func _compute_level_up(character: CharacterData) -> Dictionary:
	## Compute all level-up changes. Does NOT mutate character yet.
	## Returns a result dict that _apply_stat_changes() can consume.
	var old_level := character.level
	var new_level := old_level + 1
	var class_id := character.character_class

	# HP.
	var hp_gained := roll_level_up_hp(character)
	var new_hp_max := character.hp_max + hp_gained
	var new_hp_current := character.hp_current + hp_gained  # Heal the new HP.

	# Attack throw and saves.
	var new_attack_throw := _class_registry.get_attack_throw(class_id, new_level)
	var new_saves := _class_registry.get_saving_throws(class_id, new_level)

	# Title and next-level XP.
	var new_title := _class_registry.get_level_title(class_id, new_level)
	var max_level := character.max_level
	var new_xp_for_next: int = 0
	if new_level < max_level:
		new_xp_for_next = _class_registry.get_xp_for_level(class_id, new_level + 1)

	# Proficiency slots.
	var prof_slots := _check_new_proficiency_slots(class_id, new_level)

	# Spell slots.
	var old_spell_slots := _class_registry.get_spell_slots(class_id, old_level)
	var new_spell_slots := _class_registry.get_spell_slots(class_id, new_level)

	# New powers.
	var new_powers := _get_new_powers(class_id, new_level)

	return {
		"old_level":                   old_level,
		"new_level":                   new_level,
		"hp_gained":                   hp_gained,
		"new_hp_max":                  new_hp_max,
		"new_hp_current":              new_hp_current,
		"new_attack_throw":            new_attack_throw,
		"new_saves":                   new_saves,
		"new_title":                   new_title,
		"new_xp_for_next_level":       new_xp_for_next,
		"new_class_proficiency_slots": int(prof_slots.get("class", 0)),
		"new_general_proficiency_slots": int(prof_slots.get("general", 0)),
		"old_spell_slots":             old_spell_slots,
		"new_spell_slots":             new_spell_slots,
		"new_powers":                  new_powers,
		"requires_class_selection":    false,
	}


func _apply_stat_changes(character: CharacterData, result: Dictionary) -> void:
	## Apply the computed level-up changes to the CharacterData in-memory.
	character.level           = result["new_level"]
	character.hp_max          = result["new_hp_max"]
	character.hp_current      = result["new_hp_current"]
	character.attack_throw    = result["new_attack_throw"]
	character.title           = result["new_title"]
	character.xp_for_next_level = result["new_xp_for_next_level"]

	var saves: Dictionary = result["new_saves"]
	character.save_petrification = int(saves.get("petrification", character.save_petrification))
	character.save_poison_death  = int(saves.get("poison_death", character.save_poison_death))
	character.save_blast_breath  = int(saves.get("blast_breath", character.save_blast_breath))
	character.save_staffs_wands  = int(saves.get("staffs_wands", character.save_staffs_wands))
	character.save_spells        = int(saves.get("spells", character.save_spells))


# ---------------------------------------------------------------------------
# Proficiency Slot Detection
# ---------------------------------------------------------------------------

func _check_new_proficiency_slots(class_id: String, new_level: int) -> Dictionary:
	## Returns { "class": 0|1, "general": 0|1 } indicating new slots at this level.
	var cls := _class_registry.get_class_def(class_id)
	if cls.is_empty():
		return {"class": 0, "general": 0}
	var prof_prog: Dictionary = cls.get("proficiency_progression", {})
	var class_levels: Array  = prof_prog.get("class", [])
	var general_levels: Array = prof_prog.get("general", [])
	return {
		"class":   1 if new_level in class_levels else 0,
		"general": 1 if new_level in general_levels else 0,
	}


# ---------------------------------------------------------------------------
# Class Power Unlock Detection
# ---------------------------------------------------------------------------

func _get_new_powers(class_id: String, new_level: int) -> Array:
	## Returns Array of power_id strings that unlock at new_level for this class.
	var class_powers: Array = _class_registry.get_class_powers(class_id)
	var result: Array = []
	for cp in class_powers:
		if int(cp.get("unlock_level", 0)) == new_level:
			var pid: String = cp.get("power_id", "")
			if not pid.is_empty():
				result.append(pid)
	return result
