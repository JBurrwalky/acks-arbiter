class_name RulerProfile
extends RefCounted

## The legacy ruler weight-vector view per gdd-npc-personality.md §8.2 and
## gdd-ruler-ai.md §4.4: exactly the eight derived weights + crisis_response +
## the two relational dicts, computed from a StrategicDisposition for systems
## that only want the weight vector (no axis snapshot, no motivations).
##
## This is a VIEW — it carries no data of its own and is never persisted
## separately; rebuild it from the disposition (`disposition.to_profile()` or
## `RulerProfile.from_disposition(d)`) whenever needed.

var expansion_weight: float = 0.0
var fortification_weight: float = 0.0
var economic_weight: float = 0.0
var military_weight: float = 0.0
var diplomatic_weight: float = 0.0
var religious_weight: float = 0.0
var research_weight: float = 0.0
var oppression_weight: float = 0.0

var crisis_response: String = "defensive"

var aggression_toward: Dictionary = {}
var alliance_preference: Dictionary = {}


static func from_disposition(d: StrategicDisposition) -> RulerProfile:
	var p := RulerProfile.new()
	if d == null:
		return p
	p.expansion_weight = d.expansion_weight
	p.fortification_weight = d.fortification_weight
	p.economic_weight = d.economic_weight
	p.military_weight = d.military_weight
	p.diplomatic_weight = d.diplomatic_weight
	p.religious_weight = d.religious_weight
	p.research_weight = d.research_weight
	p.oppression_weight = d.oppression_weight
	p.crisis_response = d.crisis_response
	p.aggression_toward = d.aggression_toward.duplicate()
	p.alliance_preference = d.alliance_preference.duplicate()
	return p


func to_dict() -> Dictionary:
	return {
		"expansion_weight": expansion_weight,
		"fortification_weight": fortification_weight,
		"economic_weight": economic_weight,
		"military_weight": military_weight,
		"diplomatic_weight": diplomatic_weight,
		"religious_weight": religious_weight,
		"research_weight": research_weight,
		"oppression_weight": oppression_weight,
		"crisis_response": crisis_response,
		"aggression_toward": aggression_toward.duplicate(),
		"alliance_preference": alliance_preference.duplicate(),
	}
