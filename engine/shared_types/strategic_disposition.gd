class_name StrategicDisposition
extends RefCounted

## The ruler-AI handoff struct per gdd-npc-personality.md §8.2 — the strategic
## layer derived from an NPC ruler's NpcPersonality + alignment. Produced by
## StrategicDispositionBuilder (gdd-ruler-ai.md §4); consumed by the future
## planner (gdd-ruler-ai.md §6), which may read either the eight summary
## weights or the raw axis snapshot for finer per-action utility.
##
## Persisted one row per NPC ruler in `ruler_dispositions` (migration 181,
## keyed by character_id) via RulerDispositionRepository. Regenerable from
## characters.personality + characters.alignment, so the table is a cache of
## this derivation, not independent ground truth.
##
## The five expressive-only axes are deliberately absent: they never inform
## strategic behavior (§8.2).

## Valid crisis_response categories (§8.4).
const CRISIS_RESPONSES: Array[String] = [
	"aggressive", "defensive", "diplomatic", "cautious",
]

## The eight ruler-action weight keys, in canonical (§8.2 declaration) order.
const WEIGHT_KEYS: Array[String] = [
	"expansion_weight", "fortification_weight", "economic_weight",
	"military_weight", "diplomatic_weight", "religious_weight",
	"research_weight", "oppression_weight",
]

# From Motivation (primary and secondary, weighted 0.7 / 0.3 in the formulas).
var motivation_primary: String = ""
var motivation_secondary: String = ""

# Snapshot of the seven strategically-active axes (1-10 integers) at build time.
var epistemic_curiosity: int = 5
var societal_orthodoxy: int = 5
var affective_compassion: int = 5
var stress_reactivity: int = 5
var self_interest: int = 5
var in_group_loyalty: int = 5
var mysticism: int = 5

# Derived ruler-action weights (§8.3), each clamped to 0.0-1.0.
var expansion_weight: float = 0.0
var fortification_weight: float = 0.0
var economic_weight: float = 0.0
var military_weight: float = 0.0
var diplomatic_weight: float = 0.0
var religious_weight: float = 0.0
var research_weight: float = 0.0
var oppression_weight: float = 0.0

# Derived crisis response (§8.4): "aggressive" | "defensive" | "diplomatic" | "cautious".
var crisis_response: String = "defensive"

# Relational (§8.3 / gdd-ruler-ai.md §4.3). {realm_id: float}; empty when
# realm relations are absent — the graceful-degradation contract.
var aggression_toward: Dictionary = {}
var alliance_preference: Dictionary = {}


## The eight weights as a {weight_key: float} dict in canonical order.
func weights() -> Dictionary:
	return {
		"expansion_weight": expansion_weight,
		"fortification_weight": fortification_weight,
		"economic_weight": economic_weight,
		"military_weight": military_weight,
		"diplomatic_weight": diplomatic_weight,
		"religious_weight": religious_weight,
		"research_weight": research_weight,
		"oppression_weight": oppression_weight,
	}


## The seven strategic-axis snapshot values as an {axis_key: int} dict.
func axis_snapshot() -> Dictionary:
	return {
		"epistemic_curiosity": epistemic_curiosity,
		"societal_orthodoxy": societal_orthodoxy,
		"affective_compassion": affective_compassion,
		"stress_reactivity": stress_reactivity,
		"self_interest": self_interest,
		"in_group_loyalty": in_group_loyalty,
		"mysticism": mysticism,
	}


## The legacy RulerProfile view (§8.2 / gdd-ruler-ai.md §4.4): exactly the
## eight weights + crisis_response + the two relational dicts.
func to_profile() -> RulerProfile:
	return RulerProfile.from_disposition(self)


static func from_dict(data: Dictionary) -> StrategicDisposition:
	var d := StrategicDisposition.new()
	d.motivation_primary = String(data.get("motivation_primary", ""))
	d.motivation_secondary = String(data.get("motivation_secondary", ""))
	d.epistemic_curiosity = int(data.get("epistemic_curiosity", 5))
	d.societal_orthodoxy = int(data.get("societal_orthodoxy", 5))
	d.affective_compassion = int(data.get("affective_compassion", 5))
	d.stress_reactivity = int(data.get("stress_reactivity", 5))
	d.self_interest = int(data.get("self_interest", 5))
	d.in_group_loyalty = int(data.get("in_group_loyalty", 5))
	d.mysticism = int(data.get("mysticism", 5))
	d.expansion_weight = float(data.get("expansion_weight", 0.0))
	d.fortification_weight = float(data.get("fortification_weight", 0.0))
	d.economic_weight = float(data.get("economic_weight", 0.0))
	d.military_weight = float(data.get("military_weight", 0.0))
	d.diplomatic_weight = float(data.get("diplomatic_weight", 0.0))
	d.religious_weight = float(data.get("religious_weight", 0.0))
	d.research_weight = float(data.get("research_weight", 0.0))
	d.oppression_weight = float(data.get("oppression_weight", 0.0))
	d.crisis_response = String(data.get("crisis_response", "defensive"))
	if not CRISIS_RESPONSES.has(d.crisis_response):
		d.crisis_response = "defensive"
	d.aggression_toward = _coerce_realm_map(data.get("aggression_toward", {}))
	d.alliance_preference = _coerce_realm_map(data.get("alliance_preference", {}))
	return d


func to_dict() -> Dictionary:
	return {
		"motivation_primary": motivation_primary,
		"motivation_secondary": motivation_secondary,
		"epistemic_curiosity": epistemic_curiosity,
		"societal_orthodoxy": societal_orthodoxy,
		"affective_compassion": affective_compassion,
		"stress_reactivity": stress_reactivity,
		"self_interest": self_interest,
		"in_group_loyalty": in_group_loyalty,
		"mysticism": mysticism,
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


## Accepts either a Dictionary (in-memory / to_dict round-trip) or a JSON
## String (the DB row's serialized column) and returns a {realm_id: float}
## dict. Malformed input degrades to {} — never errors.
static func _coerce_realm_map(raw: Variant) -> Dictionary:
	var source: Variant = raw
	if source is String:
		if (source as String).is_empty():
			return {}
		source = JSON.parse_string(source)
	if not (source is Dictionary):
		return {}
	var out: Dictionary = {}
	for k in (source as Dictionary).keys():
		var v: Variant = (source as Dictionary)[k]
		if v is float or v is int:
			out[String(k)] = float(v)
	return out
