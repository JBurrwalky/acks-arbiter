class_name HijinkThrowTarget
extends RefCounted

## Computes the proficiency-throw target for a per-hijink resolution
## (Phase 10B.3). RAW context: hijinks roll d20 vs the perpetrator's
## class-power progression target for the relevant thief skill.
##
## DEX / STR / encumbrance modifiers do NOT apply in hijink context per the
## established ThiefSkillResolver `is_hijink=true` convention. Class progression
## tables are the sole input.
##
## This helper avoids the CharacterBundle construction required by the full
## ThiefSkillResolver — handlers operate on character_id strings + Dictionary
## class data, which the JSON-backed ClassRegistry already exposes.
##
## RAW source: rules/acore-campaign-hijinks.xml §hijinks L48-237 + class
## progression in data/classes/<class>.json class_powers[*].progression.


# Per-hijink kind → the class-power id that supplies the throw target.
const HIJINK_TO_POWER_ID := {
	"assassinating":    "hide_in_shadows",
	"carousing":        "hear_noise",
	"smuggling":        "move_silently",
	"spying":           "hide_in_shadows",
	"stealing":         "pick_pockets",
	"treasure_hunting": "find_remove_traps",
}


# Eligibility per RAW (each hijink lists the eligible class set).
# Carousing is open to all (including 0-level); the others restrict to the
# class allowlists in RAW §hijinks <eligibility> nodes.
const HIJINK_ELIGIBLE_CLASSES := {
	"assassinating":    ["assassin", "elven_nightblade"],
	"carousing":        [],  # empty = any class
	"smuggling":        ["thief", "elven_nightblade"],
	"spying":           ["assassin", "elven_nightblade", "thief"],
	"stealing":         ["thief", "elven_nightblade"],
	"treasure_hunting": ["thief", "elven_nightblade"],
}


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

## Returns true if [param class_id] is eligible for [param hijink_kind] per RAW.
## Carousing is universally eligible (returns true for any class).
static func is_eligible(hijink_kind: String, class_id: String) -> bool:
	if not HIJINK_ELIGIBLE_CLASSES.has(hijink_kind):
		return false
	var allow: Array = HIJINK_ELIGIBLE_CLASSES[hijink_kind]
	if allow.is_empty():
		return true
	return class_id in allow


# ---------------------------------------------------------------------------
# Throw target
# ---------------------------------------------------------------------------

## Reads the perpetrator's relevant thief-skill progression target from the
## class JSON. Returns [param fallback] if the class has no progression for
## the relevant power (e.g., a 0-level carouser with no class skills — they
## still get the throw at the base unskilled target of 18+ per RAW).
##
## [param penalty] is added to the d20 roll, NOT to the target — callers
## subtract it from the d20 value before comparing, which is equivalent to
## adding -penalty to the d20 roll. The target stays the RAW class value.
static func get_target(
		hijink_kind: String,
		class_id: String,
		level: int,
		class_registry,
		fallback: int = 18,
) -> int:
	if not HIJINK_TO_POWER_ID.has(hijink_kind):
		return fallback
	var power_id: String = HIJINK_TO_POWER_ID[hijink_kind]
	if class_registry == null:
		return fallback
	var class_def: Dictionary = class_registry.get_class_def(class_id)
	if class_def.is_empty():
		return fallback
	var powers: Array = class_def.get("class_powers", [])
	for power in powers:
		if not (power is Dictionary):
			continue
		if String((power as Dictionary).get("power_id", "")) != power_id:
			continue
		var progression: Dictionary = (power as Dictionary).get("progression", {})
		if progression.is_empty():
			return fallback
		# Levels are stored as string keys per data/classes/*.json.
		var clamped: int = clampi(level, 1, 14)
		var key: String = str(clamped)
		if progression.has(key):
			return int(progression[key])
		return fallback
	return fallback


# ---------------------------------------------------------------------------
# Outcome classification
# ---------------------------------------------------------------------------

## Given the raw d20 roll, the throw target, and an applied penalty
## (e.g., from incomplete planning per RAW §plan_hijink L1229), returns
## a classification dict:
##   { "success": bool, "caught": bool, "margin_of_failure": int }
##
## RAW catch-on-fail per §hijinks: caught if the throw fails by 14+ OR on
## an unmodified 1. The unmodified-1 check uses the raw d20 value, not the
## post-penalty value.
##
## "Lay-low not done" branch (§lay_low L1198): if the perpetrator skipped
## lay-low in this base, caught if fail-by-11+ OR unmodified 1-3. Caller
## passes [param strict_catch=true] to enable.
static func classify_outcome(
		raw_d20: int,
		penalty: int,
		target: int,
		strict_catch: bool = false,
) -> Dictionary:
	var effective_roll: int = raw_d20 - penalty
	var success: bool = effective_roll >= target
	var margin_of_failure: int = max(0, target - effective_roll)
	var catch_threshold_fail_by: int = 11 if strict_catch else 14
	var natural_caught_band: int = 3 if strict_catch else 1
	var caught: bool = false
	if not success:
		if raw_d20 <= natural_caught_band:
			caught = true
		elif margin_of_failure >= catch_threshold_fail_by:
			caught = true
	return {
		"success": success,
		"caught": caught,
		"margin_of_failure": margin_of_failure,
		"effective_roll": effective_roll,
	}
