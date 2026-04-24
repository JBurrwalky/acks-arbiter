class_name CharacterModelRegistry
extends RefCounted

## Central lookup for 3D character placeholder models (GLB).
##
## Maps "<class_id>/<variant>/<sex>" → { path, scale } for player-character
## and henchman tokens in combat / dungeon renderers. Variant keys come from
## the filename stem (`def`, `alt1`, `alt2`, `alt3`). Sex keys are
## "male"/"female". When a (class, variant, sex) has no GLB, callers should
## fall back to the existing cylinder token (CombatantToken3D).
##
## Scale rules (world unit = meter; source GLBs are 1 m tall).
## Final scale = GLOBAL_SCALE × per-class/sex height from the table below.
##   - vaultguard_*, craftpriest_*             → 1.25
##   - spellsword_*, nightblade_*, enchanter_* → 1.70
##   - *_male (generic default)                → 1.85
##   - *_female (generic default)              → 1.75
##
## Tuning knobs:
##   - Rescale ALL placeholders at once  → change GLOBAL_SCALE below.
##   - Rescale one class / sex bucket    → edit the per-class table in get_scale().
##   - Swap a single model's mesh         → drop a new GLB at the same filename and reopen the Godot editor.
##
## Adding more placeholders later: drop files into assets/tokens/characters/
## and extend _FILES below. No database migration needed — token_variant is
## persisted as a plain string on CharacterData.


## Single knob to shrink/grow every model uniformly. Placeholder meshes
## read too large relative to cell size; 0.5 brings them down to roughly
## one cell wide at default class heights.
const GLOBAL_SCALE := 0.5

const BASE_DIR := "res://assets/tokens/characters"

## Explicit file list. Listed rather than scanned so the set is deterministic
## at build time and can be tested without touching the filesystem.
const _FILES: Array[String] = [
	"assassin_alt1_female", "assassin_alt1_male",
	"assassin_def_female", "assassin_def_male",
	"barbarian_alt1_female", "barbarian_alt1_male",
	"barbarian_alt2_male",
	"barbarian_def_female", "barbarian_def_male",
	"bard_def_female", "bard_def_male",
	"bladedancer_alt1_female", "bladedancer_def_female",
	"cleric_alt1_male", "cleric_alt2_male", "cleric_def_male",
	"craftpriest_def_male",
	"enchanter_def_female", "enchanter_def_male",
	"explorer_alt1_male", "explorer_alt2_male", "explorer_def_male",
	"fighter_alt1_male", "fighter_alt2_male", "fighter_alt3_male",
	"fighter_def_female", "fighter_def_male",
	"fury_def_male",
	"mage_def_female", "mage_def_male",
	"nightblade_def_female", "nightblade_def_male",
	"paladin_alt1_male", "paladin_def_male",
	"spellsword_alt1_female", "spellsword_alt1_male",
	"spellsword_def_female", "spellsword_def_male",
	"thief_alt1_male", "thief_alt2_male", "thief_def_male",
	"vaultguard_alt1_male", "vaultguard_def_male",
	"venturer_def_male",
]

## Classes whose models are sub-average height per the design brief.
const _SHORT_CLASSES := ["vaultguard", "craftpriest"]
## Classes whose models are between short and tall.
const _MEDIUM_CLASSES := ["spellsword", "nightblade", "enchanter"]

## ACKS class IDs that use a racial prefix (elf_/elven_/dwarf_/dwarven_) but
## whose placeholder GLBs are filed under the bare class stem. Add new
## entries here whenever a racial variant of an existing class ships without
## its own dedicated model set.
const _CLASS_ALIASES := {
	"elf_spellsword":    "spellsword",
	"elf_nightblade":    "nightblade",
	"elven_enchanter":   "enchanter",
	"dwarf_vaultguard":  "vaultguard",
	"dwarf_craftpriest": "craftpriest",
	"dwarven_fury":      "fury",
}


## Returns true if a GLB exists for the given triple.
## Empty variant defaults to "def".
static func has_model(class_id: String, variant: String, sex: String) -> bool:
	return _stem(_canonical(class_id), variant, sex) in _FILES


## Returns `res://...glb` path for the given triple, or empty string if none.
static func get_model_path(class_id: String, variant: String, sex: String) -> String:
	var stem := _stem(_canonical(class_id), variant, sex)
	if not stem in _FILES:
		return ""
	return "%s/%s.glb" % [BASE_DIR, stem]


## World-unit scale to apply to the imported 1 m GLB for the given class/sex.
## Returns the generic male/female default even if the (class, sex) has no
## model registered — callers that render a model should still pair the
## scale with a has_model() check.
static func get_scale(class_id: String, sex: String) -> float:
	var canonical := _canonical(class_id)
	var base: float = 1.75 if sex == "female" else 1.85
	if canonical in _SHORT_CLASSES:
		base = 1.25
	elif canonical in _MEDIUM_CLASSES:
		base = 1.70
	return base * GLOBAL_SCALE


## Returns the default variant string for (class, sex) if a _def_ model
## exists, else the first available variant. Empty string if nothing matches.
static func get_default_variant(class_id: String, sex: String) -> String:
	if has_model(class_id, "def", sex):
		return "def"
	var variants := get_available_variants(class_id, sex)
	return variants[0] if not variants.is_empty() else ""


## Returns all available variant keys for (class, sex), "def" first then
## alt1/alt2/alt3 in order.
static func get_available_variants(class_id: String, sex: String) -> Array[String]:
	var result: Array[String] = []
	var canonical := _canonical(class_id)
	if canonical.is_empty() or sex.is_empty():
		return result
	var prefix := "%s_" % canonical
	var suffix := "_%s" % sex
	for stem in _FILES:
		if stem.begins_with(prefix) and stem.ends_with(suffix):
			var variant := stem.substr(prefix.length(),
				stem.length() - prefix.length() - suffix.length())
			if not variant.is_empty():
				result.append(variant)
	# def first, then alt1/alt2/alt3 alphabetical
	result.sort()
	if "def" in result:
		result.erase("def")
		result.insert(0, "def")
	return result


## Returns sexes for which the class has at least one model.
static func get_available_sexes(class_id: String) -> Array[String]:
	var result: Array[String] = []
	var canonical := _canonical(class_id)
	if canonical.is_empty():
		return result
	var prefix := "%s_" % canonical
	var saw_male := false
	var saw_female := false
	for stem in _FILES:
		if not stem.begins_with(prefix):
			continue
		if stem.ends_with("_male"):
			saw_male = true
		elif stem.ends_with("_female"):
			saw_female = true
	if saw_male:
		result.append("male")
	if saw_female:
		result.append("female")
	return result


## Returns true if at least one model exists for (class_id, sex), regardless
## of variant. Useful for deciding whether to open the picker panel at all.
static func has_any_model(class_id: String, sex: String) -> bool:
	return not get_available_variants(class_id, sex).is_empty()


## Map an ACKS class_id (e.g., "elf_spellsword") to the filename stem
## ("spellsword"). Returns the input unchanged when no alias is registered,
## so plain IDs like "fighter" pass through.
static func _canonical(class_id: String) -> String:
	return _CLASS_ALIASES.get(class_id, class_id)


static func _stem(canonical_class: String, variant: String, sex: String) -> String:
	var v := variant if not variant.is_empty() else "def"
	return "%s_%s_%s" % [canonical_class, v, sex]
