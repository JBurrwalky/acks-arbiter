class_name PersonalityReactionModifiers
extends RefCounted

## Maps an NPC's personality (the strategically-active axes + its runtime
## disposition) into situational modifiers for the 2d6 reaction/influencing roll
## (rules/ax_reactions_and_influencing.xml; gdd-npc-personality.md §2, §3.2).
##
## PROJECT CALL. ACKS RAW does not define personality-derived reaction modifiers;
## this is the project's mapping. Two hard constraints from the GDD + RAW keep it
## proportionate and non-distorting:
##   1. Personality INFORMS modifiers — it never replaces the 2d6 roll (§2).
##   2. Magnitudes stay in the RAW ±1/±2 band (RAW reaction terms are mostly
##      ±1/±2; CHA/WIS cap at ±3; only harm/3:1-outnumber reach ±5). Only axes at
##      a deviant extreme (1-3 or 8-10) contribute at all — mid-range NPCs (4-7)
##      add nothing, matching the §9.1 deviation-filter philosophy.
##
## Each contributing axis maps high→positive or high→negative per tone, scaled
## ±2 at the absolute extreme (1/10), ±1 across the rest of the deviant band.
##
## Axis → tone mapping (PROJECT CALL, behavioral rationale):
##   DIPLOMATIC    — affective_compassion (compassionate NPCs are moved by appeals),
##                   epistemic_curiosity (the inquisitive are open to foreigners/new proposals).
##   INTIMIDATION  — stress_reactivity (the volatile are rattled by threats: +),
##                   self_interest (the principled resist coercion: high→−),
##                   in_group_loyalty (a zealot won't betray their own under threat: high→−).
##   SEDUCTION     — self_interest (the opportunistic are more swayable: high→−).
##                   (Amorousness is the natural driver but it is an EXPRESSIVE axis,
##                    which §3.1 keeps mechanically inert; so it is deliberately excluded.)
##
## societal_orthodoxy and mysticism are strategically active but context-specific
## (governance/treaties; clerics/undead) rather than generic first-impression
## drivers, so they are intentionally NOT mapped to the generic reaction roll.
##
## RefCounted with a class_name; all static. Consumed by InteractionResolver via
## context["target_personality"].

## { tone: { axis_key: sign } }  sign +1 = high score helps the interactor's roll;
## -1 = high score hurts it.
const _TONE_AXES: Dictionary = {
	"diplomatic": {
		"affective_compassion": 1,
		"epistemic_curiosity": 1,
	},
	"intimidation": {
		"stress_reactivity": 1,
		"self_interest": -1,
		"in_group_loyalty": -1,
	},
	"seduction": {
		"self_interest": -1,
	},
}


## Returns an Array of {source_id: String, value: int} situational modifiers for
## [param personality] under [param tone]: the per-tone axis modifiers plus the
## disposition modifier. Empty when nothing deviates. InteractionResolver wraps
## each into a ModifierStack entry under the "personality" category.
static func modifiers_for(personality: NpcPersonality, tone: String) -> Array:
	var out: Array = []
	if personality == null:
		return out
	var contrib: Dictionary = _TONE_AXES.get(tone, {})
	for axis_key in contrib:
		var score: int = personality.axis(String(axis_key))
		if not PersonalityAxes.is_deviant(score):
			continue
		var value: int = _scaled(score) * int(contrib[axis_key])
		if value != 0:
			out.append({"source_id": "personality_" + String(axis_key), "value": value})
	var disp: int = disposition_modifier(personality)
	if disp != 0:
		out.append({"source_id": "personality_disposition", "value": disp})
	return out


## The reaction modifier contributed by the NPC's runtime disposition (-5..+5),
## projected to a proportionate ±2 (so a personal grudge/fondness nudges the roll
## without dominating it, and never double-counts the broad ReputationSystem term).
static func disposition_modifier(personality: NpcPersonality) -> int:
	if personality == null:
		return 0
	return clampi(XPAwardCalculator.bankers_round(float(personality.disposition) / 2.0), -2, 2)


## Magnitude for a deviant axis (±2 extreme / ±1 deviant band / 0 mid). Shared
## with henchman loyalty via PersonalityAxes.deviant_magnitude.
static func _scaled(score: int) -> int:
	return PersonalityAxes.deviant_magnitude(score)
