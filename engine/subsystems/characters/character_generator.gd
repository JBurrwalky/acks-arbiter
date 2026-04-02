class_name CharacterGenerator
extends RefCounted

## Unified character generation engine for PCs, NPCs, and henchmen.
## Follows the ACKS 1e character creation procedure exactly.
## All randomness flows through DiceSystem for roll transparency.

var class_registry: ClassRegistry
var power_registry: PowerRegistry
var proficiency_registry: ProficiencyRegistry


func _init(p_class_registry: ClassRegistry, p_power_registry: PowerRegistry,
		p_proficiency_registry: ProficiencyRegistry = null) -> void:
	class_registry = p_class_registry
	power_registry = p_power_registry
	proficiency_registry = p_proficiency_registry


# ---------------------------------------------------------------------------
# Ability Score Generation
# ---------------------------------------------------------------------------

const ABILITY_ORDER: Array[String] = ["STR", "INT", "WIS", "DEX", "CON", "CHA"]

func roll_ability_scores() -> Dictionary:
	## Rolls 3d6 in order for each ability score.
	## Returns { "scores": { "STR": int, ... }, "roll_results": Array }
	var scores: Dictionary = {}
	var roll_results: Array = []
	for ability in ABILITY_ORDER:
		var result: RollResult = DiceSystem.roll_digital(6, 3, 0, "ability_score_%s" % ability)
		scores[ability] = result.modified_total
		roll_results.append(result)
	return {"scores": scores, "roll_results": roll_results}


func get_eligible_classes(scores: Dictionary, race: String) -> Array[String]:
	## Returns class_ids the character qualifies for.
	return class_registry.get_eligible_classes(scores, race)


# ---------------------------------------------------------------------------
# Ability Score Trading (ACKS rules)
# ---------------------------------------------------------------------------

func apply_ability_trade(scores: Dictionary, class_id: String,
		source_ability: String, target_ability: String, points: int) -> Dictionary:
	## Trade ability points: 2 from source raises 1 in target (a prime requisite).
	## Validates all ACKS constraints. Returns updated scores or empty dict on failure.
	##
	## Rules (ACKS RAW — acore_basics_and_characters.xml ability_trade_rule):
	## - Target must be a prime requisite of the chosen class
	## - Source cannot be a prime requisite of the chosen class
	## - No score can drop below 9 after the trade
	## - Points must be positive and even (2:1 ratio)
	## CON and CHA are NOT specially restricted — any non-prime-requisite ability
	## can be sacrificed (to minimum 9). E.g., a Fighter can lower CHA.
	if points <= 0 or points % 2 != 0:
		push_error("CharacterGenerator.apply_ability_trade: points must be positive even number")
		return {}

	var cls := class_registry.get_class_def(class_id)
	if cls.is_empty():
		return {}

	var primes: Array = cls.get("prime_requisites", [])
	if target_ability not in primes:
		push_error("CharacterGenerator.apply_ability_trade: target '%s' is not a prime requisite" % target_ability)
		return {}
	if source_ability in primes:
		push_error("CharacterGenerator.apply_ability_trade: cannot lower prime requisite '%s'" % source_ability)
		return {}

	var new_scores := scores.duplicate()
	var source_new: int = int(new_scores[source_ability]) - points
	@warning_ignore("integer_division")
	var target_gain: int = points / 2
	var target_new: int = int(new_scores[target_ability]) + target_gain

	if source_new < 9:
		push_error("CharacterGenerator.apply_ability_trade: would reduce %s below 9" % source_ability)
		return {}
	if target_new > 18:
		target_new = 18

	new_scores[source_ability] = source_new
	new_scores[target_ability] = target_new
	return new_scores


# ---------------------------------------------------------------------------
# PC Generation
# ---------------------------------------------------------------------------

func generate_pc(class_id: String, scores: Dictionary,
		campaign_id: String) -> CharacterData:
	## Generate a level-1 PC with the given class and ability scores.
	## Does NOT select proficiencies or equipment (UI flow handles those).
	## Returns a fully populated CharacterData ready for persistence.
	var cls := class_registry.get_class_def(class_id)
	if cls.is_empty():
		push_error("CharacterGenerator.generate_pc: unknown class '%s'" % class_id)
		return null

	var character := CharacterData.new()
	character.id = CampaignRepository.generate_id()
	character.campaign_id = campaign_id
	character.character_type = "pc"
	character.persistence_tier = "full"

	# Class and race
	character.race = cls.get("race", "human")
	character.character_class = class_id
	character.combat_progression = cls.get("combat_progression", "fighter")
	character.hit_die_type = cls.get("hit_die", "1d8")
	character.max_level = cls.get("max_level", 14)

	# Ability scores
	character.strength = int(scores.get("STR", 10))
	character.intelligence = int(scores.get("INT", 10))
	character.wisdom = int(scores.get("WIS", 10))
	character.dexterity = int(scores.get("DEX", 10))
	character.constitution = int(scores.get("CON", 10))
	character.charisma = int(scores.get("CHA", 10))

	# Level and XP
	character.level = 1
	character.xp = 0
	var primes: Array = cls.get("prime_requisites", [])
	var prime_scores: Array = []
	for pr in primes:
		prime_scores.append(int(scores.get(pr, 10)))
	character.xp_adjustment_percent = AbilityUtils.get_xp_adjustment(prime_scores)
	character.xp_for_next_level = class_registry.get_xp_for_level(class_id, 2)

	# HP: hit die + CON modifier, minimum 1
	var con_mod := CharacterData.ability_modifier(character.constitution)
	character.hp_max = _roll_hp(cls.get("hit_die", "1d8"), 1, con_mod)
	character.hp_current = character.hp_max

	# Combat stats
	_derive_combat_stats(character, cls)

	# Title
	character.title = class_registry.get_level_title(class_id, 1)

	# Starting gold: 3d6 x 10 gp (rolled but not spent — equipment UI handles purchasing)
	var _gold_result := DiceSystem.roll_digital(6, 3, 0, "starting_gold")
	# Gold is tracked via inventory/equipment system, not a character field.
	# The UI flow will use this result to set starting funds.

	# Alignment defaults to neutral; player selects in UI
	character.alignment = "neutral"

	# Starting age (rolled from class-specific formula; player can view in Finalize step)
	var _aging_system := AgingSystem.new()
	character.current_age = _aging_system.roll_starting_age(class_id)
	character.age_category = _aging_system.get_age_category(character.race, character.current_age)

	return character


# ---------------------------------------------------------------------------
# NPC / Henchman Generation
# ---------------------------------------------------------------------------

func generate_npc(class_id: String, level: int, campaign_id: String,
		tier: String = "named", character_type: String = "npc") -> CharacterData:
	## Generate a complete NPC at the given level.
	## Auto-rolls abilities, HP, derives all stats, auto-selects proficiencies.
	var cls := class_registry.get_class_def(class_id)
	if cls.is_empty():
		push_error("CharacterGenerator.generate_npc: unknown class '%s'" % class_id)
		return null

	# Clamp level to class maximum
	var max_lvl: int = cls.get("max_level", 14)
	level = clampi(level, 1, max_lvl)

	var character := CharacterData.new()
	character.id = CampaignRepository.generate_id()
	character.campaign_id = campaign_id
	character.character_type = character_type
	character.persistence_tier = tier

	# Class and race
	character.race = cls.get("race", "human")
	character.character_class = class_id
	character.combat_progression = cls.get("combat_progression", "fighter")
	character.hit_die_type = cls.get("hit_die", "1d8")
	character.max_level = max_lvl

	# Roll ability scores
	var ability_data := roll_ability_scores()
	var scores: Dictionary = ability_data.scores
	character.strength = int(scores.STR)
	character.intelligence = int(scores.INT)
	character.wisdom = int(scores.WIS)
	character.dexterity = int(scores.DEX)
	character.constitution = int(scores.CON)
	character.charisma = int(scores.CHA)

	# Level and XP
	character.level = level
	character.xp = class_registry.get_xp_for_level(class_id, level)
	var primes: Array = cls.get("prime_requisites", [])
	var prime_scores: Array = []
	for pr in primes:
		prime_scores.append(int(scores.get(pr, 10)))
	character.xp_adjustment_percent = AbilityUtils.get_xp_adjustment(prime_scores)
	if level < max_lvl:
		character.xp_for_next_level = class_registry.get_xp_for_level(class_id, level + 1)
	else:
		character.xp_for_next_level = 0

	# HP for all hit dice at this level
	var con_mod := CharacterData.ability_modifier(character.constitution)
	character.hp_max = _roll_hp(cls.get("hit_die", "1d8"), level, con_mod,
		class_registry.get_max_hd_count(class_id),
		class_registry.get_hp_after_max_hd(class_id))
	character.hp_current = character.hp_max

	# Combat stats
	_derive_combat_stats(character, cls)

	# Title
	character.title = class_registry.get_level_title(class_id, level)

	# Alignment: random for named/full NPCs; transients default to neutral (no roll needed)
	if tier != "transient":
		var alignment_roll := DiceSystem.roll_digital(6, 1, 0, "npc_alignment")
		if alignment_roll.modified_total <= 2:
			character.alignment = "chaotic"
		elif alignment_roll.modified_total <= 4:
			character.alignment = "neutral"
		else:
			character.alignment = "lawful"

	# Name placeholder — transients get a minimal label; named/full get an ID-tagged name
	if tier == "transient":
		character.name = "%s L%d" % [cls.get("class_name", "Unknown"), level]
	else:
		character.name = "%s %s L%d" % [cls.get("class_name", "Unknown"), character.id.left(4), level]

	# Starting age: roll base, then add a rough estimate for levels gained (1 year/level after L1).
	var _aging_system := AgingSystem.new()
	var base_age := _aging_system.roll_starting_age(class_id)
	var age_bonus := maxi(0, level - 1)
	character.current_age = base_age + age_bonus
	character.age_category = _aging_system.get_age_category(character.race, character.current_age)
	# Apply cumulative ability adjustments if starting category is beyond adult.
	if character.age_category != "adult" and character.age_category != "youth":
		_aging_system.apply_cumulative_adjustments(character, character.age_category)

	return character


func generate_henchman(class_id: String, level: int, campaign_id: String,
		employer_id: String) -> CharacterData:
	## Generate a henchman — like an NPC but tier=full, type=henchman,
	## with employer tracking and loyalty score.
	var character := generate_npc(class_id, level, campaign_id, "full", "henchman")
	if character == null:
		return null
	character.employer_id = employer_id
	# Base loyalty: 7 + CHA modifier of employer (looked up by caller)
	# For now, set a default base of 7
	character.loyalty_score = 7
	return character


# ---------------------------------------------------------------------------
# Power Stamping
# ---------------------------------------------------------------------------

func stamp_powers(character: CharacterData, class_id: String) -> Array:
	## Creates power records from the class definition for a character.
	## Returns Array of Dictionaries ready for CampaignRepository.save_character_powers().
	var class_powers: Array = class_registry.get_class_powers(class_id)
	var power_records: Array = []
	for cp in class_powers:
		var power_id: String = cp.get("power_id", "")
		if power_id.is_empty():
			continue
		var record := {
			"power_id": power_id,
			"unlock_level": cp.get("unlock_level", 1),
			"conditions": JSON.stringify(cp.get("conditions", [])),
			"progression_data": JSON.stringify(cp.get("progression", {})),
			"is_active": true,
		}
		power_records.append(record)
	return power_records


# ---------------------------------------------------------------------------
# Proficiency Auto-Selection (for NPCs)
# ---------------------------------------------------------------------------

func auto_select_proficiencies(class_id: String, level: int) -> Array:
	## Auto-select proficiencies for NPC generation.
	## Returns Array of Dictionaries ready for CampaignRepository.save_character_proficiencies().
	var cls := class_registry.get_class_def(class_id)
	if cls.is_empty():
		return []

	var proficiencies: Array = []
	var class_prof_list: Array = cls.get("class_proficiency_list", [])
	var prof_prog: Dictionary = cls.get("proficiency_progression", {})
	var class_levels: Array = prof_prog.get("class", [1])
	var general_levels: Array = prof_prog.get("general", [1, 5, 9, 13])

	# Count slots earned by this level
	var class_slots := 0
	for lvl in class_levels:
		if int(lvl) <= level:
			class_slots += 1
	var general_slots := 0
	for lvl in general_levels:
		if int(lvl) <= level:
			general_slots += 1

	# Auto-pick: adventuring is automatic (general), then random from class list
	proficiencies.append({
		"proficiency_key": "adventuring",
		"rank": 1,
		"slot_type": "general",
		"selections_count": 1,
		"specialization": "",
	})
	general_slots -= 1  # adventuring took one general slot

	# Fill class proficiency slots randomly
	var available_class := class_prof_list.duplicate()
	for i in range(class_slots):
		if available_class.is_empty():
			break
		var idx := DiceSystem.roll_digital(available_class.size(), 1, -1, "npc_class_prof").modified_total
		idx = clampi(idx, 0, available_class.size() - 1)
		var raw_key: String = available_class[idx]
		available_class.remove_at(idx)
		# Resolve compound keys (e.g., "combat_trickery_disarm") and pick specializations
		var base_key := raw_key
		var spec := ""
		if proficiency_registry != null:
			var embedded := proficiency_registry.get_specialization_from_compound_key(raw_key)
			if not embedded.is_empty():
				base_key = proficiency_registry.resolve_key(raw_key)
				spec = embedded
			elif proficiency_registry.is_specialization(raw_key):
				spec = _pick_random_specialization(raw_key)
		proficiencies.append({
			"proficiency_key": base_key,
			"rank": 1,
			"slot_type": "class",
			"selections_count": 1,
			"specialization": spec,
		})

	# Fill remaining general slots.
	# Use the full general proficiency list from registry when available;
	# fall back to a short hardcoded list for backwards compatibility.
	var general_options: Array
	if proficiency_registry != null:
		general_options = proficiency_registry.get_general_proficiency_list().duplicate()
		general_options.erase("adventuring")  # already added above
	else:
		general_options = ["healing", "survival", "riding", "labor", "craft",
			"knowledge", "language", "endurance", "navigation", "tracking"]
	for i in range(general_slots):
		if general_options.is_empty():
			break
		var idx := DiceSystem.roll_digital(general_options.size(), 1, -1, "npc_general_prof").modified_total
		idx = clampi(idx, 0, general_options.size() - 1)
		var gen_key: String = general_options[idx]
		general_options.remove_at(idx)
		var gen_spec := ""
		if proficiency_registry != null and proficiency_registry.is_specialization(gen_key):
			gen_spec = _pick_random_specialization(gen_key)
		proficiencies.append({
			"proficiency_key": gen_key,
			"rank": 1,
			"slot_type": "general",
			"selections_count": 1,
			"specialization": gen_spec,
		})

	return proficiencies


func _pick_random_specialization(prof_key: String) -> String:
	## Picks a random specialization ID from the registry for the given proficiency key.
	## Returns "" if no registry is available or no specializations are defined.
	if proficiency_registry == null:
		return ""
	var available := proficiency_registry.get_available_specializations(prof_key)
	if available.is_empty():
		return ""
	var idx := DiceSystem.roll_digital(available.size(), 1, -1, "npc_spec").modified_total
	idx = clampi(idx, 0, available.size() - 1)
	return available[idx] as String


# ---------------------------------------------------------------------------
# Internal: HP Rolling
# ---------------------------------------------------------------------------

func _roll_hp(hit_die: String, level: int, con_modifier: int,
		max_hd_count: int = 9, hp_after_max: int = 2) -> int:
	## Roll hit points for a character at the given level.
	## Rolls hit dice up to max_hd_count, then adds fixed HP per level after that.
	## CON modifier applied to each hit die roll (minimum 1 per die).
	## CON modifier does NOT apply to fixed HP after max hit dice.
	var sides := _parse_hit_die_sides(hit_die)
	var total_hp: int = 0

	# Roll hit dice (up to max_hd_count)
	var dice_to_roll := mini(level, max_hd_count)
	for i in range(dice_to_roll):
		var roll := DiceSystem.roll_digital(sides, 1, 0, "hit_points_L%d" % (i + 1))
		var hp_this_die := maxi(roll.modified_total + con_modifier, 1)
		total_hp += hp_this_die

	# Fixed HP for levels beyond max_hd_count
	if level > max_hd_count:
		var extra_levels := level - max_hd_count
		total_hp += extra_levels * hp_after_max

	return total_hp


func _parse_hit_die_sides(hit_die: String) -> int:
	## Parse "1d8" -> 8, "1d6" -> 6, "1d4" -> 4
	if "d" in hit_die:
		var parts := hit_die.split("d")
		if parts.size() >= 2 and parts[1].is_valid_int():
			return int(parts[1])
	return 8  # default to d8


# ---------------------------------------------------------------------------
# Internal: Derive Combat Stats
# ---------------------------------------------------------------------------

func _derive_combat_stats(character: CharacterData, cls: Dictionary) -> void:
	## Sets attack throw and saving throws from class progression tables.
	var class_id: String = cls.get("class_id", "")
	character.attack_throw = class_registry.get_attack_throw(class_id, character.level)
	var saves := class_registry.get_saving_throws(class_id, character.level)
	character.save_petrification = int(saves.get("petrification", 15))
	character.save_poison_death = int(saves.get("poison_death", 14))
	character.save_blast_breath = int(saves.get("blast_breath", 16))
	character.save_staffs_wands = int(saves.get("staffs_wands", 16))
	character.save_spells = int(saves.get("spells", 17))
