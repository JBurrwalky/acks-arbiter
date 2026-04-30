class_name CreatureFamily
extends RefCounted

## Resolves a Combatant to a coarse "family" string used by Kin-Slaying,
## Goblin-Slaying, and any future race-targeted proficiencies.
##
## Source of truth, in priority order:
## - Player characters: CharacterData.race ("human", "elf", "dwarf", "halfling",
##   "gnome", "nobiran", ...).
## - Monsters: data/monsters/monster_catalog.json `sub_types` array first,
##   then `monster_types`. The first recognized tag wins.
##
## Returns "" if no family can be resolved (un-cataloged monster, missing tag).
## Calling code should treat "" as "no bonus applies" — the data-first pattern
## means new monsters become bonus-eligible by adding the right tag, not by
## editing this file.

const KIN_FAMILIES: Array = [
	"human", "elf", "dwarf", "halfling", "gnome", "nobiran",
]

const GOBLINOID_FAMILIES: Array = [
	"goblinoid",
	"giantkin",  # ogres, hill giants, stone giants — true giants tagged as giantkin
	"giant_humanoid",  # ogres in current catalog use this monster_type
]


static func family_for(combatant) -> String:
	if combatant == null:
		return ""
	if combatant.is_character:
		if combatant._character == null:
			return ""
		return String(combatant._character.race).to_lower()
	# Monster: prefer sub_types, fall back to monster_types
	var monster: Dictionary = combatant._monster_data
	for tag in monster.get("sub_types", []):
		var s := String(tag).to_lower()
		if not s.is_empty():
			return s
	for tag in monster.get("monster_types", []):
		var s := String(tag).to_lower()
		if not s.is_empty():
			return s
	return ""


static func is_kin(combatant) -> bool:
	return family_for(combatant) in KIN_FAMILIES


static func is_goblinoid(combatant) -> bool:
	## Returns true if the combatant's family matches any of the Goblin-Slaying
	## targets (kobolds, goblins, orcs, gnolls, hobgoblins, bugbears, ogres,
	## trolls, giants — anything tagged as goblinoid or giantkin in catalog).
	var family := family_for(combatant)
	if family in GOBLINOID_FAMILIES:
		return true
	# Some monsters carry both goblinoid and giant_humanoid tags; family_for
	# returns the first hit. Check sub_types directly as a backstop.
	if combatant != null and not combatant.is_character:
		for tag in combatant._monster_data.get("sub_types", []):
			if String(tag).to_lower() == "goblinoid":
				return true
	return false
