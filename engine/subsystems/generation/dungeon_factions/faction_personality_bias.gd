class_name FactionPersonalityBias
extends RefCounted

## Twelve-axis faction personality mean-shift (`gdd-dungeon-factions.md` §2.2).
## Applied as the FACTION step of the NPC personality bias stack
## (sample → ability → culture → FACTION → alignment → clamp,
## gdd-npc-personality.md §4.1). Values are mean-shifts in [-2.0, +2.0] on the
## same flat twelve-axis schema as cultural biases.
##
## The generator stamps the derived dict onto each faction's
## `personality_weight_biases`; the NPC personality generator consumes it when
## creating intelligent faction members / leaders. Deterministic (no RNG):
## a pure function of faction_type + alignment.


## The twelve axes (gdd-npc-personality.md §3.2), in canonical order.
const AXES: Array[String] = [
	"epistemic_curiosity", "societal_orthodoxy", "affective_compassion",
	"stress_reactivity", "self_interest", "in_group_loyalty", "mysticism",
	"expressiveness", "civility", "jocularity", "amorousness", "epicureanism",
]


## Return the twelve-axis bias dict for a faction of [param faction_type] with
## [param alignment]. Every axis is present (defaults 0.0). The military / cult /
## tribal profiles reproduce the §2.2 worked examples exactly.
static func for_faction(faction_type: String, alignment: String) -> Dictionary:
	var b: Dictionary = _zero()
	match faction_type:
		DungeonFaction.TYPE_MILITARY:
			# §2.2 military example (disciplined warband).
			b["in_group_loyalty"] = 1.5
			b["stress_reactivity"] = -1.0
			b["societal_orthodoxy"] = 1.0
			b["civility"] = -0.5
		DungeonFaction.TYPE_CULT:
			# §2.2 cult example (necromancer's circle).
			b["mysticism"] = 2.0
			b["in_group_loyalty"] = 1.0
			b["affective_compassion"] = -1.0
			b["self_interest"] = -0.5
		DungeonFaction.TYPE_TRIBAL:
			# §2.2 tribal example (goblin tribe).
			b["in_group_loyalty"] = 1.0
			b["stress_reactivity"] = 1.0
			b["self_interest"] = -1.0
			b["civility"] = -1.0
		DungeonFaction.TYPE_PACK:
			# Pack animals / swarms: cohesive, excitable, low individual civility.
			b["in_group_loyalty"] = 1.0
			b["stress_reactivity"] = 1.0
			b["civility"] = -1.0
			b["epistemic_curiosity"] = -0.5
		DungeonFaction.TYPE_UNDEAD_HORDE:
			# Undead-led horde: obedient, affectless, mystically bound.
			b["in_group_loyalty"] = 1.5
			b["affective_compassion"] = -1.5
			b["stress_reactivity"] = -1.5
			b["mysticism"] = 1.0
			b["expressiveness"] = -1.0
		DungeonFaction.TYPE_COALITION:
			# Mixed opportunistic band: looser bonds, more self-interest.
			b["self_interest"] = -1.0            # toward Opportunistic
			b["societal_orthodoxy"] = -0.5
			b["in_group_loyalty"] = 0.5
			b["civility"] = -0.5
		_:
			pass
	_apply_alignment_shift(b, alignment)
	return b


## Small alignment nudge layered on the type profile (kept modest so the FACTION
## step stays distinct from the later ALIGNMENT step of the stack).
static func _apply_alignment_shift(b: Dictionary, alignment: String) -> void:
	match alignment:
		"lawful":
			b["societal_orthodoxy"] = clampf(float(b["societal_orthodoxy"]) + 0.5, -2.0, 2.0)
			b["civility"] = clampf(float(b["civility"]) + 0.5, -2.0, 2.0)
		"chaotic":
			b["societal_orthodoxy"] = clampf(float(b["societal_orthodoxy"]) - 0.5, -2.0, 2.0)
			b["self_interest"] = clampf(float(b["self_interest"]) - 0.5, -2.0, 2.0)
		_:
			pass


static func _zero() -> Dictionary:
	var d: Dictionary = {}
	for a in AXES:
		d[a] = 0.0
	return d
