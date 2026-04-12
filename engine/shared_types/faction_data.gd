class_name FactionData
extends RefCounted

## A faction in the campaign world. Phase G-1 schema.
##
## Factions group NPCs (members) and may be tied to a home domain. Reputation
## with a faction propagates to its members during reaction rolls (see
## ReputationSystem.build_reaction_modifiers).

const TYPES: Array = [
	"tribal", "military", "cult", "pack", "coalition",
	"undead_horde", "noble_house", "guild", "religious_order",
]

const ALIGNMENTS: Array = ["lawful", "neutral", "chaotic"]

var id: String = ""
var campaign_id: String = ""
var name: String = ""
var alignment: String = "neutral"
var faction_type: String = "tribal"
var home_domain_id: String = ""
var leader_npc_id: String = ""
var parent_faction_id: String = ""
var description: String = ""


static func from_dict(data: Dictionary) -> FactionData:
	var f := FactionData.new()
	f.id = data.get("id", "")
	f.campaign_id = data.get("campaign_id", "")
	f.name = data.get("name", "")
	f.alignment = data.get("alignment", "neutral")
	f.faction_type = data.get("faction_type", "tribal")
	f.home_domain_id = data.get("home_domain_id", "") if data.get("home_domain_id") != null else ""
	f.leader_npc_id = data.get("leader_npc_id", "") if data.get("leader_npc_id") != null else ""
	f.parent_faction_id = data.get("parent_faction_id", "") if data.get("parent_faction_id") != null else ""
	f.description = data.get("description", "")
	return f


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"name": name,
		"alignment": alignment,
		"faction_type": faction_type,
		"home_domain_id": home_domain_id,
		"leader_npc_id": leader_npc_id,
		"parent_faction_id": parent_faction_id,
		"description": description,
	}
