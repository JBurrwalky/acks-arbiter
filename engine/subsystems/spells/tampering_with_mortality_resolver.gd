class_name TamperingWithMortalityResolver
extends RefCounted

## Tampering with Mortality (Axioms ch.6) — applies the d20+d6 modifiers,
## resolves the condition_table outcome, and renders the alignment-specific
## side-effect entry. Called by `restore_life_and_limb_resolver` after the
## base d20+d6 are rolled; the resolver records the structured outcome on
## the per_target dictionary so the character_subsystem consumer can
## persist results + schedule bed rest.
##
## ACKS RAW anchor: rules/ax_mortal_wounds_and_tampering.xml:385-690.
##
## V1 wiring (this resolver):
##   - Modifier computation: life_span (from age_category), spellcaster_power
##     (+1 per 2 caster levels), state_of_body (-10 if death_cause indicates
##     instantly killed via lost_head/cremated/disintegrated; capped at -10),
##     state_of_soul (WIS modifier + -1 per day dead + -1 per
##     side_effects_already_suffered).
##   - condition_table lookup → spell_fails | restored_at_great_cost |
##     restored_with_lingering_effects | restoration_intense | body_made_whole
##     | health_restored | instantly_recovered, plus bed_rest_days.
##   - alignment_table lookup (Lawful / Neutral / Chaotic) → side-effect text.
##
## V1 simplifications (each is a documented follow-up):
##   - "temple of the spellcaster's god" +2 bonus to spellcaster_power not
##     applied (no temple-location infrastructure today; the bonus is
##     +2/temple). Resolver still computes the +caster_level/2 piece.
##   - Wound-row state_of_body tracking (per limb / per spine severing /
##     per hand-foot-ear-eye-tongue-genitalia) not enumerated; V1 only
##     stamps -10 when death_cause is in the instant-kill set.
##   - side_effects_already_suffered not yet persisted across casts; V1
##     accepts an injected count via resolver_args for testing.
##   - Bed-rest scheduling lives in Timekeeping; this resolver only
##     records the bed_rest_days outcome.
##   - The side-effect tables are abridged to the d20 ranges that the
##     condition_table can actually produce (-6 or less through 26+).


const _CONDITION_TABLE: Array = [
	# Each entry: { lo, hi, condition, bed_rest_days }
	# bed_rest_days = "14+1d20" is recorded as a String for the consumer.
	{"lo": -1000, "hi":  -6, "condition": "spell_fails",                  "bed_rest_days": 0},
	{"lo":    -5, "hi":   0, "condition": "spell_fails",                  "bed_rest_days": 0},
	{"lo":     1, "hi":   5, "condition": "restored_at_great_cost",       "bed_rest_days": 30},
	{"lo":     6, "hi":  10, "condition": "restored_with_lingering_effects", "bed_rest_days": "14+1d20"},
	{"lo":    11, "hi":  15, "condition": "restoration_intense",          "bed_rest_days": 14},
	{"lo":    16, "hi":  20, "condition": "body_made_whole",              "bed_rest_days": 14},
	{"lo":    21, "hi":  25, "condition": "health_restored",              "bed_rest_days": 7},
	{"lo":    26, "hi":1000, "condition": "instantly_recovered",          "bed_rest_days": 0},
]


# Age-category → life-span modifier (RAW: +2 youthful, 0 adult, -5 middle aged,
# -10 old, -20 ancient). Our internal category is "youth" not "youthful".
const _LIFE_SPAN_MODIFIERS: Dictionary = {
	"youth": 2,
	"youthful": 2,  # alias for parity with RAW text
	"adult": 0,
	"middle_aged": -5,
	"old": -10,
	"ancient": -20,
}


# Death causes that count as "instantly killed" for state_of_body purposes.
# Per RAW: "instantly killed" includes death by disease or poison, being
# slain while helpless, or rolling instantly killed on the Mortal Wounds
# table. V1 treats lost_head + cremated + disintegrated as -10 (the body
# is destroyed); other deaths default to 0.
const _INSTANT_KILL_DEATH_CAUSES: Array = [
	"lost_head", "cremated", "disintegrated",
]


# Side-effect tables per alignment. Each value is a nested dict:
#   alignment_table["lawful"][d6_str][d20_band] = description string
# d6_str is "1".."6"; d20_band is one of:
#   "-6", "-5to0", "1to5", "6to10", "11to15", "16to20", "21to25", "26+"
# These are the RAW outcomes from ax_mortal_wounds_and_tampering.xml.
const _ALIGNMENT_TABLES: Dictionary = {
	"lawful": {
		"1": {
			"-6": "soul illuminated in the light of the Logos; no additional attempts permitted.",
			"-5to0": "spirit dwells in paradise; no additional attempts permitted.",
			"1to5": "returns as incorporeal blue spirit; can see, hear, speak, and cast spells; cannot otherwise interact with world.",
			"6to10": "soul marked; all extraplanar beings target victim; 1 in 6 weekly chance an 8 HD cacodemon is sent to destroy victim.",
			"11to15": "on a natural 1 attack throw, hit an adjacent ally instead.",
			"16to20": "changes sex; -2 reaction with those who knew prior gender unless CHA 13+.",
			"21to25": "ages early; age 1d10 years if human or 5d10 years if demi-human.",
			"26+": "becomes vegetarian only; cannot eat flesh without vomiting.",
		},
		"2": {
			"-6": "surrounded by admiring ghostly figures; no additional attempts permitted.",
			"-5to0": "all additional attempts at -5.",
			"1to5": "sprouts angel wings; CON halved; takes double damage from bludgeoning and falls; gains 30' flight.",
			"6to10": "permanently connected to spiritual plane; all undead sense victim within 60'.",
			"11to15": "connection to Divine lessened; cast 1 fewer Divine spell per level per day; WIS -1d3.",
			"16to20": "ascetic appetite; food tastes like porridge, drink like vinegar; -2 saves vs ingested poison.",
			"21to25": "whispers from beyond; -2 hear noise; -1 initiative and surprise.",
			"26+": "10% XP penalty until next level.",
		},
		"3": {
			"-6": "all additional attempts at -5.",
			"-5to0": "all additional attempts at -3.",
			"1to5": "ages instantly to halfway to racial maximum age.",
			"6to10": "gain body of a Lawful creature from reincarnation table; -4 reaction with normal humans.",
			"11to15": "voice like thunder; cannot whisper; spellcasting is loud.",
			"16to20": "bronze skin, golden eyes, or halo; -2 reaction with Chaotic creatures.",
			"21to25": "10% XP penalty until next level.",
			"26+": "no side effects.",
		},
		"4": {
			"-6": "all additional attempts at -3.",
			"-5to0": "additional attempts permitted at -1.",
			"1to5": "CHA +4 to maximum 18, STR -4 to minimum 3.",
			"6to10": "lose 1 point of Wisdom permanently.",
			"11to15": "bright lights or loud sounds in battle require save vs Paralysis or stunned 1 round.",
			"16to20": "10% XP penalty until next level.",
			"21to25": "gain benefits of Heroism potion for 1 day; all negative side effects removed.",
			"26+": "no side effects.",
		},
		"5": {
			"-6": "deity may allow second attempt, but must perform a quest upon revival.",
			"-5to0": "deity's embrace; additional attempts permitted at -1.",
			"1to5": "lose 1 point of Constitution permanently.",
			"6to10": "hair grows 1 inch by sunset unless shaved twice daily.",
			"11to15": "10% XP penalty until next level.",
			"16to20": "no side effects.",
			"21to25": "recover 1d6 days quicker; all negative side effects removed.",
			"26+": "gain a true or possibly true prophecy from the Judge.",
		},
		"6": {
			"-6": "deity may allow return on a second attempt after a second attempt is permitted.",
			"-5to0": "second attempt permitted.",
			"1to5": "carry permanent marks of faith; -4 reaction with those outside pantheon, +2 with those who share.",
			"6to10": "domestic animals + songbirds react favorably; +4 with them; -4 Move Silently and Hide in Shadows when any are within 30'.",
			"11to15": "no side effects.",
			"16to20": "feel blessed; recover 1d6 days quicker; all negative side effects removed.",
			"21to25": "gain speak with dead once per week; all negative side effects removed.",
			"26+": "gain +2 to class prime requisite; all negative side effects removed.",
		},
	},
	"neutral": {
		"1": {
			"-6": "soul extinguished or spirit wanders in emptiness; no additional attempts permitted.",
			"-5to0": "CON and WIS reduced by 1d4 each.",
			"1to5": "soul marked; all extraplanar beings target victim; 1 in 6 weekly chance an invisible stalker is sent to destroy victim.",
			"6to10": "on a natural 1 attack throw, hit an adjacent ally instead.",
			"11to15": "changes sex; -2 reaction with those who knew prior gender unless CHA 13+.",
			"16to20": "sterile.",
			"21to25": "flavors reverse; ordinary food becomes inedible unless specially prepared.",
			"26+": "no side effects.",
		},
		"2": {
			"-6": "tormenting ghosts or falling into nothingness; no additional attempts, or additional attempts at -5.",
			"-5to0": "blind in full daylight; -4 attack throws, no line of sight for spells, movement 1/4 normal, -2 surprise.",
			"1to5": "daily save vs Spells upon awakening or forget identity for 1d6 days.",
			"6to10": "5% cumulative daily chance of madness; act as under confusion for 1d6 days, then chance resets.",
			"11to15": "bottomless hungers; casual smoking or alcohol use causes full addiction.",
			"16to20": "whispers from beyond; -2 hear noise; -1 initiative and surprise.",
			"21to25": "10% XP penalty until next level.",
			"26+": "no side effects.",
		},
		"3": {
			"-6": "all additional attempts at -5 or -3.",
			"-5to0": "50% shrink as diminution or grow as growth; DEX immediately 3, then rises by 1 per week until normal.",
			"1to5": "gain body of a Neutral creature from reincarnation table; -4 reaction with normal humans.",
			"6to10": "gain alien eye in forehead; may use ESP 3/day; normal people react at -3.",
			"11to15": "gain minor animal trait associated with culture or religion; -2 reaction with those outside that culture.",
			"16to20": "10% XP penalty until next level.",
			"21to25": "no side effects.",
			"26+": "no side effects.",
		},
		"4": {
			"-6": "all additional attempts at -3 or permitted at -1.",
			"-5to0": "permanently forget 1 general proficiency and no longer recognize one random henchman.",
			"1to5": "lose 1 point of Wisdom permanently.",
			"6to10": "whenever resting, sleep for random 2d6+2 hours; cannot be awakened except by damage.",
			"11to15": "10% XP penalty until next level.",
			"16to20": "no side effects.",
			"21to25": "gain Heroism potion benefits for 1 day; all negative side effects removed.",
			"26+": "gain Heroism potion benefits for 1 day; all negative side effects removed.",
		},
		"5": {
			"-6": "additional attempts permitted at -1, or deity may require quest on second attempt.",
			"-5to0": "lose 1 point of Constitution permanently.",
			"1to5": "need only half normal rations, but gain 1d10 lbs immediately and 1d10 lbs per year.",
			"6to10": "10% XP penalty until next level.",
			"11to15": "no side effects.",
			"16to20": "recover 1d6 days quicker; all negative side effects removed.",
			"21to25": "gain a true or possibly true prophecy from the Judge.",
			"26+": "gain a true or possibly true prophecy from the Judge.",
		},
		"6": {
			"-6": "quest required on second attempt, or second attempt permitted.",
			"-5to0": "smell of the wild; -4 reaction with normal humans, but animals treat victim as one of them.",
			"1to5": "small demon or imp becomes familiar as the proficiency, but does not always obey.",
			"6to10": "no side effects.",
			"11to15": "recover 1d6 days quicker; all negative side effects removed.",
			"16to20": "gain speak with dead once per week; all negative side effects removed.",
			"21to25": "gain +2 to class prime requisite; all negative side effects removed.",
			"26+": "gain +2 to class prime requisite; all negative side effects removed.",
		},
	},
	"chaotic": {
		"1": {
			"-6": "soul damned to the Outer Darkness; no additional attempts permitted.",
			"-5to0": "spirit wanders pathways of the dead; or body degenerates into rotting meat; CHA 3, movement halved, no natural healing.",
			"1to5": "soul marked; all extraplanar beings target victim; 1 in 6 weekly chance a lamassu is sent to destroy victim.",
			"6to10": "on a natural 1 attack throw, hit an adjacent ally instead.",
			"11to15": "each time victim attempts to rest, on 1 on 1d6 victim gets no rest, no hp, and no spell recovery.",
			"16to20": "children are monstrous; roll on Magical Mutations or Reincarnation table for each child.",
			"21to25": "all rations must contain meat.",
			"26+": "all rations must contain meat.",
		},
		"2": {
			"-6": "tormenting ghosts or cold darkness; no additional attempts, or additional attempts at -5.",
			"-5to0": "body afflicted with wasting disease; CHA and CON reduced by 1d3 immediately and by another 1 each month.",
			"1to5": "dead flesh no longer satisfies hunger; only living flesh and blood of a struggling sapient creature satiates.",
			"6to10": "cannot stop muttering nonsense; impossible to move silently; spellcasting initiative -1.",
			"11to15": "must drink blood; animal blood suffices but fresh sapient blood is preferred.",
			"16to20": "whispers from beyond; -2 hear noise; -1 initiative and surprise.",
			"21to25": "10% XP penalty until next level.",
			"26+": "10% XP penalty until next level.",
		},
		"3": {
			"-6": "all additional attempts at -5.",
			"-5to0": "one arm becomes hideous tentacle; may attack for 1d8 damage; CHA -3; -4 on fine manipulation.",
			"1to5": "gain body of a Chaotic creature from reincarnation table; -4 reaction with normal humans.",
			"6to10": "mouth enlarges and fangs grow; bite for 1d6 damage; cannot speak intelligibly; can still cast spells.",
			"11to15": "gain disfigurement such as misshapen limbs or strange eyes; -2 reaction with sapient Lawful or Neutral creatures.",
			"16to20": "10% XP penalty until next level.",
			"21to25": "whispers from beyond; -2 hear noise; -2 surprise.",
			"26+": "whispers from beyond; -2 hear noise; -2 surprise.",
		},
		"4": {
			"-6": "all additional attempts at -3.",
			"-5to0": "dark power leaked in during restoration; holy water and turning affect victim as a wight; Destroy results charm victim.",
			"1to5": "lose 1 point of Wisdom permanently.",
			"6to10": "must sleep by day and be active by night; -2 to all throws in sunlight.",
			"11to15": "10% XP penalty until next level.",
			"16to20": "no side effects.",
			"21to25": "gain Heroism potion benefits for 1 day; all negative side effects removed.",
			"26+": "gain Heroism potion benefits for 1 day; all negative side effects removed.",
		},
		"5": {
			"-6": "deity's embrace; additional attempts permitted at -1, or quest required.",
			"-5to0": "lose 1 point of Constitution permanently.",
			"1to5": "long sharp nails; claw attacks for 1d4 damage; -1 on throws involving fine manipulation.",
			"6to10": "10% XP penalty until next level.",
			"11to15": "no side effects.",
			"16to20": "recover 1d6 days quicker; all negative side effects removed.",
			"21to25": "gain a true or possibly true prophecy from the Judge.",
			"26+": "gain a true or possibly true prophecy from the Judge.",
		},
		"6": {
			"-6": "quest required on second attempt, or second attempt permitted.",
			"-5to0": "CHA -4 but gain +2 reaction with unintelligent undead.",
			"1to5": "animals react poorly within 10'; -4 reaction with animals; cannot ride normal mounts.",
			"6to10": "no side effects.",
			"11to15": "no side effects.",
			"16to20": "recover 1d6 days quicker; all negative side effects removed.",
			"21to25": "gain a true or possibly true prophecy from the Judge.",
			"26+": "gain +2 to class prime requisite.",
		},
	},
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolve a Tampering with Mortality roll. Returns a structured outcome.
## [param ctx] is a Dictionary collecting the inputs needed for modifier
## computation. Keys (all optional):
##   d20_raw, d6_raw (the base rolls from restore_life_and_limb_resolver)
##   age_category (from CharacterData; defaults to "adult")
##   caster_level (from CasterContext; defaults to 9)
##   in_caster_god_temple (bool; default false)
##   death_cause (from CharacterData; defaults to "")
##   wisdom (from CharacterData; defaults to 10)
##   days_dead (from resolver; defaults to 0)
##   side_effects_already_suffered (defaults to 0)
##   alignment (from CharacterData; defaults to "neutral")
##
## Returns: {
##   d20_total: int (raw + modifiers),
##   d20_modifiers: { life_span, spellcaster_power, state_of_body, state_of_soul },
##   condition: String (spell_fails/restored_at_great_cost/...),
##   bed_rest: Variant (int days OR String "14+1d20"),
##   alignment_used: String (final alignment column),
##   side_effect: String (RAW outcome text),
## }
static func resolve_tampering(ctx: Dictionary) -> Dictionary:
	var d20_raw: int = int(ctx.get("d20_raw", 10))
	var d6_raw: int = int(ctx.get("d6_raw", 3))
	var modifiers: Dictionary = compute_modifiers(ctx)
	var d20_total: int = d20_raw
	for v in modifiers.values():
		d20_total += int(v)
	var condition_row: Dictionary = lookup_condition(d20_total)
	var alignment: String = String(ctx.get("alignment", "neutral")).to_lower()
	if not _ALIGNMENT_TABLES.has(alignment):
		alignment = "neutral"
	var side_effect: String = lookup_side_effect(alignment, d6_raw, d20_total)
	return {
		"d20_total": d20_total,
		"d20_modifiers": modifiers,
		"condition": condition_row.get("condition", ""),
		"bed_rest": condition_row.get("bed_rest_days", 0),
		"alignment_used": alignment,
		"side_effect": side_effect,
	}


static func compute_modifiers(ctx: Dictionary) -> Dictionary:
	var life_span: int = _LIFE_SPAN_MODIFIERS.get(
		String(ctx.get("age_category", "adult")), 0)
	# Per RAW: +1 per 2 caster levels (i.e. caster_level/2 rounded down).
	# Banker's-rounding requirement applies to .5 cases; floor here is
	# safe because integer division truncates toward zero and the input
	# is non-negative.
	var caster_level: int = int(ctx.get("caster_level", 9))
	var spellcaster_power: int = int(caster_level / 2)
	if bool(ctx.get("in_caster_god_temple", false)):
		spellcaster_power += 2
	# State of body: V1 treats lost_head/cremated/disintegrated as -10
	# (instant kill). Other deaths default to 0. Per RAW the max penalty
	# is -10.
	var state_of_body: int = 0
	var dc: String = String(ctx.get("death_cause", ""))
	if dc in _INSTANT_KILL_DEATH_CAUSES:
		state_of_body = -10
	# State of soul: WIS modifier - days_dead - side_effects_already_suffered.
	var wisdom: int = int(ctx.get("wisdom", 10))
	var wis_mod: int = _wisdom_modifier(wisdom)
	var days_dead: int = int(ctx.get("days_dead", 0))
	var side_effects: int = int(ctx.get("side_effects_already_suffered", 0))
	var state_of_soul: int = wis_mod - days_dead - side_effects
	return {
		"life_span": life_span,
		"spellcaster_power": spellcaster_power,
		"state_of_body": state_of_body,
		"state_of_soul": state_of_soul,
	}


static func lookup_condition(d20_total: int) -> Dictionary:
	for row in _CONDITION_TABLE:
		if d20_total >= int(row["lo"]) and d20_total <= int(row["hi"]):
			return row
	# Fallback (should never hit because table covers -1000..1000).
	return _CONDITION_TABLE[0]


static func lookup_side_effect(alignment: String, d6: int, d20_total: int) -> String:
	var atab: Dictionary = _ALIGNMENT_TABLES.get(alignment.to_lower(), {})
	if atab.is_empty():
		atab = _ALIGNMENT_TABLES["neutral"]
	var d6_clamped: int = clampi(d6, 1, 6)
	var row: Dictionary = atab.get(str(d6_clamped), {})
	var band: String = _d20_band(d20_total)
	return String(row.get(band, ""))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _d20_band(total: int) -> String:
	if total <= -6:
		return "-6"
	if total <= 0:
		return "-5to0"
	if total <= 5:
		return "1to5"
	if total <= 10:
		return "6to10"
	if total <= 15:
		return "11to15"
	if total <= 20:
		return "16to20"
	if total <= 25:
		return "21to25"
	return "26+"


## ACKS WIS modifier (parallel to the standard ability-modifier table).
## 3 → -3, 4-5 → -2, 6-8 → -1, 9-12 → 0, 13-15 → +1, 16-17 → +2, 18+ → +3.
static func _wisdom_modifier(wisdom: int) -> int:
	if wisdom <= 3:
		return -3
	if wisdom <= 5:
		return -2
	if wisdom <= 8:
		return -1
	if wisdom <= 12:
		return 0
	if wisdom <= 15:
		return 1
	if wisdom <= 17:
		return 2
	return 3
