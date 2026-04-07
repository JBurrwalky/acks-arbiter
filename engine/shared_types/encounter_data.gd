class_name EncounterData
extends RefCounted

## Universal encounter group descriptor per design brief §12.3.
## One schema regardless of content origin (generated, hand-authored, module).

var encounter_id: String = ""
var monster_group: String = ""      # monster_catalog.json "id" (e.g. "goblin", "troll"); use MonsterRegistry.get_monster() for stat block
var number: int = 0                 # number of creatures
var reaction_roll: int = 7          # 2d6 initial reaction roll
var behavioral_disposition: String = "neutral"
	# "hostile" | "cautious" | "neutral" | "friendly"
var reaction_modifier: int = 0
var faction_id: String = ""         # "" if no faction
var behavioral_notes: String = ""
var preferred_tactics: String = ""
var knowledge: Dictionary = {}      # what this group knows
var hex_id: String = ""             # "q,r" format of where encounter occurred


static func from_dict(data: Dictionary) -> EncounterData:
	var e := EncounterData.new()
	e.encounter_id = data.get("encounter_id", "")
	e.monster_group = data.get("monster_group", "")
	e.number = data.get("number", 0)
	e.reaction_roll = data.get("reaction_roll", 7)
	e.behavioral_disposition = data.get("behavioral_disposition", "neutral")
	e.reaction_modifier = data.get("reaction_modifier", 0)
	e.faction_id = data.get("faction_id", "")
	e.behavioral_notes = data.get("behavioral_notes", "")
	e.preferred_tactics = data.get("preferred_tactics", "")
	e.knowledge = data.get("knowledge", {})
	e.hex_id = data.get("hex_id", "")
	return e
