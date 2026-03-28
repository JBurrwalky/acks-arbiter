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

## Aging (stub — aging system built in Phase C-3)
var current_age: int = 0
var age_category: String = "adult"

## Languages — JSON-encoded Array[String] of language IDs
var languages: String = "[]"

## Personality — JSON-encoded Dictionary (populated by NPC personality system, Tier 2)
var personality: String = "{}"

## Status
var is_dead: bool = false
var is_active: bool = true
var is_incapacitated: bool = false

## Henchman fields (empty/"" for PCs and NPCs)
var employer_id: String = ""
var loyalty_score: int = 0
var wage_gp_per_month: int = 0


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
	c.current_age = data.get("current_age", 0)
	c.age_category = data.get("age_category", "adult")
	c.languages = data.get("languages", "[]")
	c.personality = data.get("personality", "{}")
	# Boolean DB fields are stored as INTEGER (0/1) — convert on read
	c.is_dead = data.get("is_dead", 0) == 1
	c.is_active = data.get("is_active", 1) == 1
	c.is_incapacitated = data.get("is_incapacitated", 0) == 1
	c.employer_id = data.get("employer_id", "")
	c.loyalty_score = data.get("loyalty_score", 0)
	c.wage_gp_per_month = data.get("wage_gp_per_month", 0)
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
		"current_age": current_age,
		"age_category": age_category,
		"languages": languages,
		"personality": personality,
		"is_dead": 1 if is_dead else 0,
		"is_active": 1 if is_active else 0,
		"is_incapacitated": 1 if is_incapacitated else 0,
		"employer_id": employer_id,
		"loyalty_score": loyalty_score,
		"wage_gp_per_month": wage_gp_per_month,
	}
