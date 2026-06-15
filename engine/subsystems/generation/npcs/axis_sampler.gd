class_name PersonalityAxisSampler
extends RefCounted

## Samples the twelve dispositional axes per generation/gdd-npc-personality.md
## §4.1 step 2. Pure numeric: a seeded Gaussian draw, then a FIXED-ORDER stack
## of mean-shifts (ability → culture → faction → alignment), then ONE round +
## clamp at the end.
##
## Ordering is load-bearing (§4.1): sample → ability → culture → faction →
## alignment → round/clamp. Intermediate math is float; rounding to int (Banker's,
## per the project-wide round-half-to-even rule) and clamping to [1,10] happen
## exactly once, after all shifts accumulate.
##
## Faction biases are accepted but absent from the data model in this build
## (FactionData carries no personality_weight_biases yet), so callers pass {} and
## the faction term is a no-op until the faction generator ships.
##
## RefCounted with a class_name (NOT an autoload). Stateless — all methods static;
## the caller owns the seeded RandomNumberGenerator.


## Context for sampling. Keys (all optional; absent → that shift is zero):
##   cha_mod, wis_mod, int_mod : int   — ACKS ability modifiers (-3..+3)
##   alignment                 : String — "lawful"|"neutral"|"chaotic" (normalized)
##   culture_biases            : Dictionary — { axis: float } from the culture record
##   faction_biases            : Dictionary — { axis: float } (reserved; pass {})
##
## Returns { axis_key: int } for ALL twelve axes.
static func sample_all(context: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	for axis_key in PersonalityAxes.ALL_AXES:
		out[axis_key] = sample_axis(axis_key, context, rng)
	return out


## Sample exactly the given axis keys (Tier C, §4.2 — three sampled axes).
## Returns { axis_key: int } for only the requested keys.
static func sample_subset(axis_keys: Array, context: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	for axis_key in axis_keys:
		out[String(axis_key)] = sample_axis(String(axis_key), context, rng)
	return out


## Sample one axis: Gaussian base + the full shift stack, rounded and clamped.
static func sample_axis(axis_key: String, context: Dictionary,
		rng: RandomNumberGenerator) -> int:
	var value: float = rng.randfn(PersonalityAxes.SAMPLE_MEAN, PersonalityAxes.SAMPLE_SIGMA)
	value += _ability_shift(axis_key, context)
	value += _culture_shift(axis_key, context)
	value += _faction_shift(axis_key, context)
	value += _alignment_shift(axis_key, context)
	# §4.1 step 2f: round (Banker's, round-half-to-even) and clamp ONCE, here.
	var rounded: int = XPAwardCalculator.bankers_round(value)
	return clampi(rounded, PersonalityAxes.AXIS_MIN, PersonalityAxes.AXIS_MAX)


# ---------------------------------------------------------------------------
# Shift terms (§4.1 step 2b-2e)
# ---------------------------------------------------------------------------

## §2.5 ability-score mean-shift: coefficient × ACKS ability modifier.
static func _ability_shift(axis_key: String, context: Dictionary) -> float:
	var coeffs: Variant = PersonalityAxes.ABILITY_SHIFT_COEFFS.get(axis_key, null)
	if not (coeffs is Dictionary):
		return 0.0
	var shift: float = 0.0
	for ability in (coeffs as Dictionary).keys():
		var mod_key := _mod_key_for(String(ability))
		var mod: int = int(context.get(mod_key, 0))
		shift += float((coeffs as Dictionary)[ability]) * float(mod)
	return shift


## §4.1 step 2c cultural mean-shift, read from the culture record's
## personality_weight_biases ({ axis: float }, range -2.0..+2.0; partial dict).
static func _culture_shift(axis_key: String, context: Dictionary) -> float:
	var biases: Variant = context.get("culture_biases", {})
	if not (biases is Dictionary):
		return 0.0
	return float((biases as Dictionary).get(axis_key, 0.0))


## §4.1 step 2d faction mean-shift (reserved — no faction bias data yet).
static func _faction_shift(axis_key: String, context: Dictionary) -> float:
	var biases: Variant = context.get("faction_biases", {})
	if not (biases is Dictionary):
		return 0.0
	return float((biases as Dictionary).get(axis_key, 0.0))


## §3.4 alignment soft mean-shift (each ≤ ±0.5).
static func _alignment_shift(axis_key: String, context: Dictionary) -> float:
	var table: Variant = PersonalityAxes.ALIGNMENT_SHIFTS.get(axis_key, null)
	if not (table is Dictionary):
		return 0.0
	var alignment := PersonalityAxes.normalize_alignment(String(context.get("alignment", "neutral")))
	return float((table as Dictionary).get(alignment, 0.0))


static func _mod_key_for(ability: String) -> String:
	match ability:
		"charisma": return "cha_mod"
		"wisdom": return "wis_mod"
		"intelligence": return "int_mod"
	return ability
