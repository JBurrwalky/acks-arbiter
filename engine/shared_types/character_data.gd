class_name CharacterData
extends RefCounted

## Canonical in-memory representation of a character (PC, henchman, or NPC).
## Mirrors the `characters` table schema; used as the cross-subsystem contract.
## Tier A (full) characters have all fields populated.
## Tier B (named) characters have simplified stats.
## Tier C (transient) characters are not persisted.

## Identity
var id: String = ""
var campaign_id: String = ""
var name: String = ""
var character_type: String = "pc"          # "pc" | "henchman" | "npc"
var persistence_tier: String = "full"      # "full" | "named" | "transient"

## Background
var race: String = "human"
var character_class: String = "fighter"
var level: int = 1
var xp: int = 0

## Combat progression — four ACKS types only.
## "crusader" is ACKS II only and is NOT valid in this project.
var combat_progression: String = "fighter"  # "fighter" | "cleric" | "thief" | "mage"

## Ability scores (3–18)
var strength: int = 10
var intelligence: int = 10
var wisdom: int = 10
var dexterity: int = 10
var constitution: int = 10
var charisma: int = 10

## Derived combat stats (cached; recalculated by character subsystem on level-up)
var hp_max: int = 1
var hp_current: int = 1
var armor_class: int = 0       # ascending AC (0 = unarmored baseline)
var attack_throw: int = 10     # d20 roll needed to hit AC 0

## Saving throws (target numbers — lower is better; set from class progression tables)
var save_petrification: int = 15
var save_poison_death: int = 14
var save_blast_breath: int = 16
var save_staffs_wands: int = 16
var save_spells: int = 17

## Movement (exploration rate in feet per turn, adjusted by encumbrance)
var base_movement: int = 120

## Class metadata (cached from class registry; updated on level-up)
var hit_die_type: String = "1d8"
var max_level: int = 14
var xp_for_next_level: int = 2000
var xp_adjustment_percent: int = 0   # -10, -5, 0, +5, +10
var title: String = ""               # current level title from class table

## Identity (expanded)
var alignment: String = "neutral"    # "lawful" | "neutral" | "chaotic"
var sex: String = "male"             # "male" | "female"
var portrait_id: String = ""         # filename stem: "portrait_fighter_01" (no extension)
var token_variant: String = ""       # variant key for combat token sprite atlas (e.g., "default", "scarred")

## Aging (stub — aging system built in Phase C-3)
var current_age: int = 0
var age_category: String = "adult"

## Languages — JSON-encoded Array[String] of language IDs
var languages: String = "[]"

## Personality — JSON-encoded Dictionary (populated by NPC personality system, Tier 2)
var personality: String = "{}"

## Class-specific sub-selections — JSON-encoded Dictionary.
## Keys vary by class:
##   barbarian: "regional_origin"  — one of barbarian.json regional_origins keys
##   witch:     "witch_tradition"  — one of witch.json traditions
##   voudon:    "witch_tradition" + "voudon_craft_choice"
## Used by ClassEquipRestrictionValidator for the barbarian
## `determined_by_regional_origin` weapon-permission sentinel.
var class_metadata: String = "{}"

## Status
var is_dead: bool = false
var is_active: bool = true
var is_incapacitated: bool = false

## Henchman fields (empty/"" for PCs and NPCs)
var employer_id: String = ""
var loyalty_score: int = 0
var wage_cp_per_month: int = 0

## Runtime-only spell/effect state — NOT persisted; rebuilt from active_effects on load.
var modifiers: ModifierContainer = ModifierContainer.new()
var flags: EntityFlags = EntityFlags.new()
var damage_resistances: DamageResistance = DamageResistance.new()
var temp_hp: int = 0
var mirror_images: int = 0

## Proficiency records — loaded from character_proficiencies table after from_dict().
## Array of Dictionaries with keys: proficiency_key, rank, slot_type, selections_count, specialization.
## NOT in from_dict/to_dict — loaded separately via CampaignRepository.get_character_proficiencies().
var proficiencies: Array = []

const REMOVED_LANGUAGE_IDS := {
	"alignment_lawful": true,
	"alignment_chaotic": true,
}


## Persistence tier helpers

func is_transient() -> bool:
	return persistence_tier == "transient"


func is_named() -> bool:
	return persistence_tier == "named"


func is_full() -> bool:
	return persistence_tier == "full"


func can_promote_to(target_tier: String) -> bool:
	## Returns true only for legal one-step upward promotions.
	## transient → named, named → full. No skipping tiers.
	match persistence_tier:
		"transient": return target_tier == "named"
		"named":     return target_tier == "full"
		_:           return false


func can_demote_to(target_tier: String) -> bool:
	## Returns true only for legal one-step downward demotions.
	## full → named, named → transient. No skipping tiers.
	match persistence_tier:
		"full":   return target_tier == "named"
		"named":  return target_tier == "transient"
		_:        return false


## class_metadata flag helpers — class_metadata is a JSON-encoded dict of
## class-specific selections (regional_origin, witch_tradition, etc.) AND
## a few transient lifecycle flags (e.g., "is_post_normal_man" for the
## post-NM advancement track). The helpers parse/stringify on each call so
## callers don't need to do JSON arithmetic.

func has_class_metadata_flag(key: String) -> bool:
	if class_metadata.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(class_metadata)
	if not (parsed is Dictionary):
		return false
	return bool((parsed as Dictionary).get(key, false))


func set_class_metadata_flag(key: String, value: bool) -> void:
	var dict: Dictionary = {}
	if not class_metadata.is_empty():
		var parsed: Variant = JSON.parse_string(class_metadata)
		if parsed is Dictionary:
			dict = parsed
	dict[key] = value
	class_metadata = JSON.stringify(dict)


## Proficiency query methods

func has_proficiency(proficiency_key: String) -> bool:
	for p in proficiencies:
		if p.get("proficiency_key", "") == proficiency_key:
			return true
	return false


func get_proficiency_rank(proficiency_key: String) -> int:
	## Returns the aggregated rank across all slot types for this proficiency key.
	var total := 0
	for p in proficiencies:
		if p.get("proficiency_key", "") == proficiency_key:
			total += int(p.get("rank", 1))
	return total


func get_proficiency_selections(proficiency_key: String) -> int:
	## Returns the aggregated selections_count across all slot types.
	var total := 0
	for p in proficiencies:
		if p.get("proficiency_key", "") == proficiency_key:
			total += int(p.get("selections_count", 1))
	return total


func get_proficiency_specialization(proficiency_key: String) -> String:
	for p in proficiencies:
		if p.get("proficiency_key", "") == proficiency_key:
			return p.get("specialization", "")
	return ""


func get_proficiencies_by_slot(slot_type: String) -> Array:
	var result: Array = []
	for p in proficiencies:
		if p.get("slot_type", "") == slot_type:
			result.append(p)
	return result


func get_total_proficiency_rank(proficiency_key: String, specialization: String = "") -> int:
	## Returns summed rank across all slot types for the given key + specialization.
	var total := 0
	for p in proficiencies:
		if p.get("proficiency_key", "") == proficiency_key \
				and p.get("specialization", "") == specialization:
			total += int(p.get("rank", 1))
	return total


func get_aggregated_proficiencies() -> Array:
	## Convenience instance method — aggregates this character's proficiencies.
	return CharacterData.aggregate_proficiencies(proficiencies)


static func aggregate_proficiencies(raw: Array) -> Array:
	## Groups raw proficiency rows by (proficiency_key, specialization) and sums
	## rank and selections_count. Returns an array of aggregated dicts with keys:
	##   proficiency_key, specialization, rank, selections_count, slot_types, source_rows
	## slot_type becomes provenance metadata, not part of identity.
	var grouped := {}  # key: "prof_key:spec" -> aggregated dict
	for row in raw:
		var key: String = row.get("proficiency_key", "")
		var spec: String = row.get("specialization", "")
		var group_key := key + ":" + spec
		if not grouped.has(group_key):
			grouped[group_key] = {
				"proficiency_key": key,
				"specialization": spec,
				"rank": 0,
				"selections_count": 0,
				"slot_types": [],
				"source_rows": [],
			}
		var entry: Dictionary = grouped[group_key]
		entry["rank"] += int(row.get("rank", 1))
		entry["selections_count"] += int(row.get("selections_count", 1))
		var slot: String = row.get("slot_type", "general")
		if slot not in entry["slot_types"]:
			entry["slot_types"].append(slot)
		entry["source_rows"].append(row)
	return grouped.values()


## Effective value getters — all downstream systems use these, never raw fields.

func get_effective_ac() -> int:
	return modifiers.get_effective_value("armor_class", armor_class)


func get_effective_ac_vs(attack_type: String) -> int:
	## Directional AC accessor for spells that distinguish missile vs melee
	## (Shield: AC 2 vs missiles, AC 4 vs melee). attack_type: "missiles" or
	## "melee". Falls back to plain `armor_class` when no directional modifier
	## is set, then layers the directional modifier on top of the omnidirectional
	## one. The directional modifier uses `set_floor` semantics for Shield.
	var base_ac: int = get_effective_ac()
	var key := ""
	match attack_type:
		"missiles", "missile", "ranged":
			key = "armor_class_vs_missiles"
		"melee":
			key = "armor_class_vs_melee"
		_:
			return base_ac
	if not modifiers.has_modifier_for_stat(key):
		return base_ac
	# `set_floor` semantics: take whichever is higher between base and the
	# directional override. ModifierStack.calculate handles this when given
	# the base_ac as the floor candidate.
	return modifiers.get_effective_value(key, base_ac)


func get_effective_attack_throw() -> int:
	return modifiers.get_effective_value("attack_throw", attack_throw)


func get_effective_save(save_key: String) -> int:
	## save_key: one of the five canonical ACKS save categories OR a tagged-save
	## modifier-only axis. The five categories have base values rolled at
	## character creation. Tagged-save axes (save_vs_*) have base 0 and exist
	## only as modifier slots; the resolver consults them on top of the rolled
	## category save when the spell's save_spec carries the matching tag
	## (is_fear_save / damage_type / attacker_alignment).
	##
	## Five canonical categories:  save_petrification, save_poison_death,
	##                             save_blast_breath, save_staffs_wands, save_spells
	## Tagged-save axes (modifier-only, base 0):
	##   save_vs_fear      — Bless / Bane (Session 2.9.1)
	##   save_vs_fire      — Resist Fire (Session 7)
	##   save_vs_cold      — Resist Cold (Session 5)
	##   save_vs_electricity — future Resist Electricity
	##   save_vs_chaotic   — Protection from Evil / Sustained (Sessions 5, 8)
	##   save_vs_lawful    — Protection from Good / Sustained (reverse forms)
	var base_value: int
	match save_key:
		"save_petrification": base_value = save_petrification
		"save_poison_death":  base_value = save_poison_death
		"save_blast_breath":  base_value = save_blast_breath
		"save_staffs_wands":  base_value = save_staffs_wands
		"save_spells":        base_value = save_spells
		"save_vs_fear", "save_vs_fire", "save_vs_cold", "save_vs_electricity", \
		"save_vs_chaotic", "save_vs_lawful":
			base_value = 0  # modifier-only axes
		_:
			push_error("CharacterData.get_effective_save: unknown save_key '%s'" % save_key)
			return 20
	return modifiers.get_effective_value(save_key, base_value)


func get_effective_movement() -> int:
	return modifiers.get_effective_value("movement_rate", base_movement)


func get_effective_ability_score(ability: String) -> int:
	## ability: "strength" | "intelligence" | "wisdom" | "dexterity" | "constitution" | "charisma"
	var base_value: int
	match ability:
		"strength":     base_value = strength
		"intelligence": base_value = intelligence
		"wisdom":       base_value = wisdom
		"dexterity":    base_value = dexterity
		"constitution": base_value = constitution
		"charisma":     base_value = charisma
		_:
			push_error("CharacterData.get_effective_ability_score: unknown ability '%s'" % ability)
			return 10
	return modifiers.get_effective_value(ability, base_value)


## Flag convenience methods

func is_flying() -> bool:
	return flags.has_flag("can_fly")


func is_invisible() -> bool:
	return flags.has_flag("is_invisible") or flags.has_flag("is_improved_invisible")


## Combat methods

func apply_damage(amount: int, damage_type: String = "physical") -> Dictionary:
	## Applies damage through the full pipeline: resistance -> temp HP -> HP.
	## Returns { "resisted": int, "temp_hp_absorbed": int, "hp_damage": int,
	##           "new_hp": int, "is_downed": bool }
	var after_resistance := damage_resistances.apply_to_damage(amount, damage_type)
	var resisted := amount - after_resistance
	var temp_absorbed := mini(temp_hp, after_resistance)
	temp_hp -= temp_absorbed
	var hp_damage := after_resistance - temp_absorbed
	hp_current = maxi(0, hp_current - hp_damage)
	return {
		"resisted": resisted,
		"temp_hp_absorbed": temp_absorbed,
		"hp_damage": hp_damage,
		"new_hp": hp_current,
		"is_downed": hp_current <= 0,
	}


func apply_healing(amount: int) -> int:
	## Heals up to hp_max. Returns the actual amount healed.
	var old_hp := hp_current
	hp_current = mini(hp_current + amount, hp_max)
	return hp_current - old_hp



static func ability_modifier(score: int) -> int:
	# ACKS ability modifier table (ACore). Not a linear formula — lookup only.
	match score:
		3: return -3
		4, 5: return -2
		6, 7, 8: return -1
		9, 10, 11, 12: return 0
		13, 14, 15: return 1
		16, 17: return 2
		18: return 3
	return 0


static func sanitize_language_ids(raw_ids: Array) -> Array:
	## Removes deprecated alignment-language IDs and duplicate/empty entries.
	var sanitized: Array = []
	var seen: Dictionary = {}
	for raw_id in raw_ids:
		if not (raw_id is String):
			continue
		var language_id := (raw_id as String).strip_edges()
		if language_id.is_empty() or REMOVED_LANGUAGE_IDS.has(language_id) or seen.has(language_id):
			continue
		seen[language_id] = true
		sanitized.append(language_id)
	return sanitized


static func parse_languages_json(raw_languages: Variant) -> Array:
	## Returns a sanitized Array[String] from a stored JSON string or an Array input.
	if raw_languages is Array:
		return sanitize_language_ids(raw_languages)
	if raw_languages is String:
		var raw_str := raw_languages as String
		if raw_str.is_empty():
			return []
		var parsed = JSON.parse_string(raw_str)
		if parsed is Array:
			return sanitize_language_ids(parsed)
	return []


static func sanitize_languages_json(raw_languages: Variant) -> String:
	return JSON.stringify(parse_languages_json(raw_languages))


static func get_default_languages_for_race(race: String) -> Array:
	## Returns the standard starting spoken languages for the given race.
	var default_languages: Array = ["common"]
	match race:
		"elf":
			default_languages.append_array(["elvish", "gnoll", "hobgoblin", "orc"])
		"dwarf":
			default_languages.append_array(["dwarvish", "goblin", "gnome", "kobold"])
		"gnome":
			default_languages.append("gnomish")
		"halfling":
			default_languages.append("halfling")
	return sanitize_language_ids(default_languages)


static func from_dict(data: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.id = data.get("id", "")
	c.campaign_id = data.get("campaign_id", "")
	c.name = data.get("name", "")
	c.character_type = data.get("character_type", "pc")
	c.persistence_tier = data.get("persistence_tier", "full")
	c.race = data.get("race", "human")
	c.character_class = data.get("character_class", "fighter")
	c.level = data.get("level", 1)
	c.xp = data.get("xp", 0)
	c.combat_progression = data.get("combat_progression", "fighter")
	c.strength = data.get("strength", 10)
	c.intelligence = data.get("intelligence", 10)
	c.wisdom = data.get("wisdom", 10)
	c.dexterity = data.get("dexterity", 10)
	c.constitution = data.get("constitution", 10)
	c.charisma = data.get("charisma", 10)
	c.hp_max = data.get("hp_max", 1)
	c.hp_current = data.get("hp_current", 1)
	c.armor_class = data.get("armor_class", 0)
	c.attack_throw = data.get("attack_throw", 10)
	c.save_petrification = data.get("save_petrification", 15)
	c.save_poison_death = data.get("save_poison_death", 14)
	c.save_blast_breath = data.get("save_blast_breath", 16)
	c.save_staffs_wands = data.get("save_staffs_wands", 16)
	c.save_spells = data.get("save_spells", 17)
	c.base_movement = data.get("base_movement", 120)
	c.hit_die_type = data.get("hit_die_type", "1d8")
	c.max_level = data.get("max_level", 14)
	c.xp_for_next_level = data.get("xp_for_next_level", 2000)
	c.xp_adjustment_percent = data.get("xp_adjustment_percent", 0)
	c.title = data.get("title", "")
	c.alignment = data.get("alignment", "neutral")
	c.sex = data.get("sex", "male")
	c.portrait_id = data.get("portrait_id", "")
	c.token_variant = data.get("token_variant", "")
	c.current_age = data.get("current_age", 0)
	c.age_category = data.get("age_category", "adult")
	c.languages = sanitize_languages_json(data.get("languages", "[]"))
	c.personality = data.get("personality", "{}")
	c.class_metadata = data.get("class_metadata", "{}")
	# Boolean DB fields are stored as INTEGER (0/1) — convert on read
	c.is_dead = data.get("is_dead", 0) == 1
	c.is_active = data.get("is_active", 1) == 1
	c.is_incapacitated = data.get("is_incapacitated", 0) == 1
	var _emp = data.get("employer_id")
	c.employer_id = _emp if _emp != null else ""
	var _loyalty = data.get("loyalty_score")
	c.loyalty_score = int(_loyalty) if _loyalty != null else 0
	var _wage = data.get("wage_cp_per_month")
	c.wage_cp_per_month = int(_wage) if _wage != null else 0
	return c


func to_dict() -> Dictionary:
	# Returns a flat dictionary matching the `characters` DB schema.
	# Booleans become integers (0/1) for SQLite compatibility.
	return {
		"id": id,
		"campaign_id": campaign_id,
		"name": name,
		"character_type": character_type,
		"persistence_tier": persistence_tier,
		"race": race,
		"character_class": character_class,
		"level": level,
		"xp": xp,
		"combat_progression": combat_progression,
		"strength": strength,
		"intelligence": intelligence,
		"wisdom": wisdom,
		"dexterity": dexterity,
		"constitution": constitution,
		"charisma": charisma,
		"hp_max": hp_max,
		"hp_current": hp_current,
		"armor_class": armor_class,
		"attack_throw": attack_throw,
		"save_petrification": save_petrification,
		"save_poison_death": save_poison_death,
		"save_blast_breath": save_blast_breath,
		"save_staffs_wands": save_staffs_wands,
		"save_spells": save_spells,
		"base_movement": base_movement,
		"hit_die_type": hit_die_type,
		"max_level": max_level,
		"xp_for_next_level": xp_for_next_level,
		"xp_adjustment_percent": xp_adjustment_percent,
		"title": title,
		"alignment": alignment,
		"sex": sex,
		"portrait_id": portrait_id,
		"token_variant": token_variant,
		"current_age": current_age,
		"age_category": age_category,
		"languages": sanitize_languages_json(languages),
		"personality": personality,
		"class_metadata": class_metadata,
		"is_dead": 1 if is_dead else 0,
		"is_active": 1 if is_active else 0,
		"is_incapacitated": 1 if is_incapacitated else 0,
		"employer_id": employer_id,
		"loyalty_score": loyalty_score,
		"wage_cp_per_month": wage_cp_per_month,
	}
