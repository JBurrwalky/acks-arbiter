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

## Status
var is_dead: bool = false
var is_active: bool = true

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
	# Boolean DB fields are stored as INTEGER (0/1) — convert on read
	c.is_dead = data.get("is_dead", 0) == 1
	c.is_active = data.get("is_active", 1) == 1
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
		"is_dead": 1 if is_dead else 0,
		"is_active": 1 if is_active else 0,
		"employer_id": employer_id,
		"loyalty_score": loyalty_score,
		"wage_gp_per_month": wage_gp_per_month,
	}
