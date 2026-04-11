class_name HandlerEligibility
extends RefCounted

## Determines a character's handler tier for a trained creature.
##
## Three tiers (from gdd-proficiency-specializations.md §4.3):
##   Tier 1 (Proficient): Has Animal Training with matching specialization.
##   Tier 2 (Introduced):  No proficiency but listed in creature's introduced_handlers.
##   Tier 3 (Unknown):     No relationship — requires reaction roll.
##
## Special cases:
##   - Beast Friendship proficiency: automatic Tier 1 for all ordinary animals.
##   - The creature's handler_id is always Tier 1 (they trained/purchased it).


enum Tier { PROFICIENT = 1, INTRODUCED = 2, UNKNOWN = 3 }

## Maps monster species_id prefixes/exact matches to animal_training specialization IDs.
## This bridges the monster catalog naming to the proficiency specialization registry.
const SPECIES_TO_SPECIALIZATION := {
	# Dogs
	"dog_hunting": "dogs",
	"dog_war": "dogs",
	# Horses (all variants)
	"horse_light": "horses",
	"horse_light_war": "horses",
	"horse_medium": "horses",
	"horse_medium_war": "horses",
	"horse_heavy": "horses",
	"horse_heavy_war": "horses",
	# Hawks
	"hawk_ordinary": "hawks_falcons",
	# Camels
	"camel": "camels",
	# Mules and donkeys
	"mule": "mules",
	"donkey": "mules",
	# Oxen (cattle family — no dedicated specialization, use general)
	"ox": "camels",  # Oxen are draft animals; closest match
	# Wolves
	"wolf": "wolves",
	"dire_wolf": "dire_wolves",
	# Boars
	"boar": "boars",
	"boar_giant": "giant_boars",
	# Large cats
	"cat_mountain_lion": "cats_small",
	"cat_panther": "cats_great",
	"cat_lion": "cats_great",
	"cat_tiger": "cats_great",
	"cat_sabre_tooth": "saber_tooth_cats",
}


## Returns the handler tier for a character attempting to interact with a creature.
static func get_handler_tier(
		character: CharacterData,
		creature: TrainedCreatureData) -> int:
	# The creature's primary handler is always Tier 1.
	if character.id == creature.handler_id:
		return Tier.PROFICIENT

	# Beast Friendship grants Tier 1 for all ordinary animals.
	if character.has_proficiency("beast_friendship"):
		return Tier.PROFICIENT

	# Check Animal Training with matching specialization.
	var required_spec: String = get_required_specialization(creature.species_id)
	if not required_spec.is_empty() and _has_animal_training_for(character, required_spec):
		return Tier.PROFICIENT

	# Check if character is in the creature's introduced_handlers list.
	if character.id in creature.introduced_handlers:
		return Tier.INTRODUCED

	return Tier.UNKNOWN


## Returns the animal_training specialization ID required for a given species.
## Returns "" if no specialization is mapped (exotic/unknown species).
static func get_required_specialization(species_id: String) -> String:
	return SPECIES_TO_SPECIALIZATION.get(species_id, "")


## Returns true if the character has Animal Training with the given specialization.
static func _has_animal_training_for(character: CharacterData, specialization: String) -> bool:
	for p in character.proficiencies:
		if p.get("proficiency_key", "") == "animal_training":
			if p.get("specialization", "") == specialization:
				return true
	return false


## Returns a human-readable description of the handler tier.
static func tier_label(tier: int) -> String:
	match tier:
		Tier.PROFICIENT: return "Proficient Handler"
		Tier.INTRODUCED: return "Introduced"
		Tier.UNKNOWN:    return "Unknown"
		_:               return "Unknown"


## Returns the capacity limits for a given role and tier.
## Returns Dictionary with keys matching the GDD table (§4.3).
static func get_capacity_for_tier(role: String, tier: int) -> Dictionary:
	match tier:
		Tier.PROFICIENT:
			match role:
				"M":  return {"outside_battle": 6, "in_battle": 1, "notes": "1 ridden, others ponied"}
				"WM": return {"outside_battle": 6, "in_battle": 1, "notes": "Rider needs Riding proficiency"}
				"G":  return {"outside_battle": 20, "in_battle": 20, "notes": ""}
				"H":  return {"outside_battle": 6, "in_battle": 6, "notes": ""}
				"D":  return {"outside_battle": 6, "in_battle": 0, "notes": ""}
				"L":  return {"outside_battle": -1, "in_battle": 0, "notes": "Unlimited same social group"}
				"WB": return {"outside_battle": 6, "in_battle": 0, "notes": ""}
		Tier.INTRODUCED:
			match role:
				"M":  return {"outside_battle": 1, "in_battle": 0, "notes": "Lead only; riding = save vs Paralysis each round"}
				"WM": return {"outside_battle": 1, "in_battle": 0, "notes": "Cannot fight from saddle"}
				"G":  return {"outside_battle": 6, "in_battle": 6, "notes": "If taught verbal commands"}
				"H":  return {"outside_battle": 1, "in_battle": 1, "notes": ""}
				"D":  return {"outside_battle": 1, "in_battle": 0, "notes": ""}
				"L":  return {"outside_battle": 1, "in_battle": 0, "notes": ""}
				"WB": return {"outside_battle": 1, "in_battle": 0, "notes": ""}
		Tier.UNKNOWN:
			return {"outside_battle": 0, "in_battle": 0, "notes": "Requires reaction roll (2d6)"}
	return {"outside_battle": 0, "in_battle": 0, "notes": ""}


## Returns all party members and their handler tiers for a given creature.
## Useful for the creature stats tab display.
static func get_party_handler_tiers(
		party_characters: Array,
		creature: TrainedCreatureData) -> Array:
	var result: Array = []
	for cd in party_characters:
		if cd is CharacterData:
			var tier: int = get_handler_tier(cd, creature)
			result.append({
				"character_id": cd.id,
				"character_name": cd.name,
				"tier": tier,
				"tier_label": tier_label(tier),
			})
	return result
