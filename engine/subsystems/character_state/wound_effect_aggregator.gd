class_name WoundEffectAggregator
extends RefCounted

## Aggregates the mechanical effects of a character's permanent wounds.
##
## Wound rows come from two sources:
##   1. Crime & Punishment resolver — corporal punishments per
##      acore-campaign-hijinks.xml §retribution_by_crime L325-401.
##   2. Mortal Wounds resolver — wound rolls from ax_mortal_wounds_and_tampering.xml
##      that produce permanent effects.
##
## Each canonical `wound_kind` maps to a Dictionary of effect components.
## `compute(character_id)` reads all wound rows for the character, sums the
## numeric modifiers (capped per the Phase 10B.3 #6 design — reaction modifier
## capped at -10 sanity bound), and OR's the boolean blocks (e.g., cannot_speak).
##
## Wound-kind catalog (v1):
##
## From Crime & Punishment (RAW L342-398):
##   ear_cut_off           — reaction -1, hear_noise -1, surprise -1
##   maimed_tongue         — cannot_speak, cannot_cast_spells,
##                           cannot_use_magic_items, speech_proficiency -4
##   one_hand_amputated    — cannot_dual_wield, cannot_use_two_handed_weapons
##                           (RAW maps to "maimed_hand" punishment_kind and
##                            MW bludgeoning/critically_wounded d6=4)
##   both_hands_amputated  — cannot_climb, cannot_use_weapons, cannot_use_items,
##                           cannot_open_locks, cannot_remove_traps
##   branded               — reaction -2
##   whipped_scarred       — reaction -2 (from whipped save-vs-Death failure)
##   stocks_lost_teeth     — reaction -2 (from stocks save-vs-Death failure;
##                           narrative tooth loss handled in notes)
##
## From Mortal Wounds (critically_wounded bracket = d20 11-15, what
## C&P tortured-fail rolls on per the bludgeoning column):
##   mw_blud_facial_scar              — narrative (no mechanical effect)
##   mw_blud_one_leg_broken           — movement -30, dex_ac_penalty 1/3
##   mw_blud_one_knee_damaged         — carry_capacity_stone -6, cannot_force_march
##   (mw_blud_one_hand_amputated maps to canonical one_hand_amputated kind)
##   mw_blud_partly_deaf              — hear_noise -2, surprise -2, initiative -1
##   mw_blud_teeth_knocked_out        — reaction -2 (with opposite sex / upper-class
##                                      NPCs per RAW; v1 applies generic -2)
##
## ADDITIONAL effects from in-combat MW outcomes (broader catalog — encoded
## across damage types for the critically_wounded bracket only). The
## non-critically-wounded brackets are recorded as wound rows for narrative
## continuity but their structured-effect lookup is deferred to a follow-up
## pass (Phase 10B.3 #6 deferred slice).


## Per-wound effect lookup. Missing fields default to zero / false at aggregate time.
const WOUND_EFFECTS: Dictionary = {
	# ---- Corporal punishment (RAW L342-398) ----
	"ear_cut_off": {
		"reaction_modifier": -1,
		"hear_noise_modifier": -1,
		"surprise_modifier": -1,
	},
	"maimed_tongue": {
		"cannot_speak": true,
		"cannot_cast_spells": true,
		"cannot_use_magic_items": true,
		"speech_proficiency_modifier": -4,
	},
	"one_hand_amputated": {
		"cannot_dual_wield": true,
		"cannot_use_two_handed_weapons": true,
	},
	"both_hands_amputated": {
		"cannot_climb": true,
		"cannot_use_weapons": true,
		"cannot_use_items": true,
		"cannot_open_locks": true,
		"cannot_remove_traps": true,
	},
	"branded": {
		"reaction_modifier": -2,
	},
	"whipped_scarred": {
		"reaction_modifier": -2,
	},
	"stocks_lost_teeth": {
		"reaction_modifier": -2,
	},

	# ---- Mortal Wounds — critically_wounded bracket (d20 11-15), bludgeoning column
	# ---- (the slice that C&P tortured-fail rolls on per RAW). ----
	"mw_blud_facial_scar": {},  # narrative-only
	"mw_blud_one_leg_broken": {
		"movement_penalty_feet": 30,
		# DEX penalty for AC is 1/3 — encoded as a unit-share that the
		# aggregator sums. 3 = full DEX nullified. Multiple 1/3 stack.
		"dex_ac_third_share": 1,
	},
	"mw_blud_one_knee_damaged": {
		"carry_capacity_stone_penalty": 6,
		"cannot_force_march": true,
	},
	"mw_blud_partly_deaf": {
		"hear_noise_modifier": -2,
		"surprise_modifier": -2,
		"initiative_modifier": -1,
	},
	"mw_blud_teeth_knocked_out": {
		"reaction_modifier": -2,
	},
}


## Sanity cap on accumulated reaction-modifier penalties per
## Phase 10B.3 #6 design (multiple convictions can stack, but a -50 reaction
## modifier is a degenerate game state — clamp at -10).
const REACTION_MODIFIER_CAP := 10


## Returns the aggregate effect Dictionary for [param character_id]:
##   reaction_modifier            int (negative penalty; clamped to -REACTION_MODIFIER_CAP)
##   hear_noise_modifier          int
##   surprise_modifier            int
##   initiative_modifier          int
##   movement_penalty_feet        int (positive number; subtracted from movement)
##   carry_capacity_stone_penalty int (positive number; subtracted from capacity)
##   dex_ac_third_share           int (in thirds; 3 = full DEX nullified for AC)
##   speech_proficiency_modifier  int (negative; applied to speech-based prof throws)
##   cannot_speak                 bool
##   cannot_cast_spells           bool
##   cannot_use_magic_items       bool
##   cannot_dual_wield            bool
##   cannot_use_two_handed_weapons bool
##   cannot_climb                 bool
##   cannot_use_weapons           bool
##   cannot_use_items             bool
##   cannot_open_locks            bool
##   cannot_remove_traps          bool
##   cannot_force_march           bool
##   wound_count                  int — total wound rows summed (0 = no wounds)
static func compute(character_id: String) -> Dictionary:
	var agg: Dictionary = _empty_aggregate()
	if character_id.is_empty():
		return agg
	var wounds: Array = PermanentWoundsRepository.list_for_character(character_id)
	agg["wound_count"] = wounds.size()
	if wounds.is_empty():
		return agg
	for row: Dictionary in wounds:
		var kind: String = String(row.get("wound_kind", ""))
		var effects: Dictionary = WOUND_EFFECTS.get(kind, {})
		if effects.is_empty():
			continue
		# Sum integer modifiers, OR boolean blocks.
		for key in effects:
			var value = effects[key]
			if typeof(value) == TYPE_BOOL:
				if value:
					agg[key] = true
			elif typeof(value) == TYPE_INT:
				agg[key] = int(agg.get(key, 0)) + value
	# Apply reaction-modifier cap (negative direction only — wounds never
	# improve reaction).
	if int(agg.get("reaction_modifier", 0)) < -REACTION_MODIFIER_CAP:
		agg["reaction_modifier"] = -REACTION_MODIFIER_CAP
	return agg


## Maps a RAW Crime & Punishment `punishment_kind` label to the canonical
## wound_kind(s) it inflicts. Some punishments inflict multiple wounds
## (e.g., "tortured_and_proscribed" rolls on MW tortured AND adds the
## proscribed legal status — proscribed is handled separately via
## CharacterLegalStatusRepository, so only the tortured component is
## returned here).
##
## Returns an Array of {wound_kind, requires_save_vs_death} entries. The
## caller (CrimeAndPunishmentResolver) is responsible for rolling the save
## when `requires_save_vs_death=true` and only inserting the wound on a
## failed save. For "tortured" punishments the caller invokes the Mortal
## Wounds resolver instead (the wound_kind here is a sentinel "ROLL_MW").
static func wound_kinds_for_punishment(punishment_kind: String) -> Array:
	# Strip "_indentured" suffix for matching (RAW L404 indenture is orthogonal
	# to the wound; the wound still applies).
	var base: String = punishment_kind.replace("_indentured", "")
	match base:
		"ear_cut_off":
			return [{"wound_kind": "ear_cut_off", "requires_save_vs_death": false}]
		"maimed_tongue":
			return [{"wound_kind": "maimed_tongue", "requires_save_vs_death": false}]
		"maimed_hand":
			return [{"wound_kind": "one_hand_amputated", "requires_save_vs_death": false}]
		"maimed_both_hands":
			return [{"wound_kind": "both_hands_amputated", "requires_save_vs_death": false}]
		"branded":
			return [{"wound_kind": "branded", "requires_save_vs_death": false}]
		"whipped":
			# RAW: "save vs Death or permanent scarring, -2 reaction rolls".
			return [{"wound_kind": "whipped_scarred", "requires_save_vs_death": true}]
		"stocks":
			# RAW: "save vs Death or lose 1d6 teeth, -2 reaction rolls".
			return [{"wound_kind": "stocks_lost_teeth", "requires_save_vs_death": true}]
		"tortured", "tortured_and_proscribed":
			# RAW: "save vs Death or permanent wound from Mortal Wounds rows 11-15".
			# Sentinel value — caller rolls MW on critically_wounded bracket.
			return [{"wound_kind": "ROLL_MW", "requires_save_vs_death": true,
				"mw_damage_type": "bludgeoning", "mw_bracket_index": 4}]
		"execution", "agonizing_execution", "fate_worse_than_death":
			# Caller marks character is_dead=1 + removes from party. No wound row.
			return [{"wound_kind": "DEATH", "requires_save_vs_death": false}]
		_:
			return []


## Maps a MW resolver outcome (damage_type + d6_index + bracket_index) to the
## canonical wound_kind for the structured catalog. Returns "" if the outcome
## is not yet structurally encoded (v1 covers bludgeoning/critically_wounded
## only; other brackets log a free-text wound row without structured effects).
static func wound_kind_for_mw_outcome(
		damage_type: String,
		d6_value: int,
		bracket_index: int
) -> String:
	if damage_type != "bludgeoning":
		return ""  # v1: only bludgeoning/critically_wounded encoded
	if bracket_index != 4:  # critically_wounded
		return ""
	match d6_value:
		1: return "mw_blud_facial_scar"
		2: return "mw_blud_one_leg_broken"
		3: return "mw_blud_one_knee_damaged"
		4: return "one_hand_amputated"  # shares the canonical hand kind
		5: return "mw_blud_partly_deaf"
		6: return "mw_blud_teeth_knocked_out"
	return ""


static func _empty_aggregate() -> Dictionary:
	return {
		"wound_count": 0,
		"reaction_modifier": 0,
		"hear_noise_modifier": 0,
		"surprise_modifier": 0,
		"initiative_modifier": 0,
		"movement_penalty_feet": 0,
		"carry_capacity_stone_penalty": 0,
		"dex_ac_third_share": 0,
		"speech_proficiency_modifier": 0,
		"cannot_speak": false,
		"cannot_cast_spells": false,
		"cannot_use_magic_items": false,
		"cannot_dual_wield": false,
		"cannot_use_two_handed_weapons": false,
		"cannot_climb": false,
		"cannot_use_weapons": false,
		"cannot_use_items": false,
		"cannot_open_locks": false,
		"cannot_remove_traps": false,
		"cannot_force_march": false,
	}
