class_name AgingSystem
extends RefCounted

## Aging system for ACKS 1e.
## Source: acore_aging_poisons_high-level-start_optional_rules.xml + pc_aging_tables.xml
##
## Handles starting age rolling, age category determination, ability score adjustments
## on category transitions, and death-from-old-age save triggers.

const TABLES_PATH := "res://data/aging_tables.json"

## Canonical order for iterating category transitions.
const CATEGORY_ORDER: Array[String] = ["youth", "adult", "middle_aged", "old", "ancient"]

## Map from ClassRegistry/JSON prime requisite abbreviations to CharacterData field names.
const ABILITY_SHORT_TO_LONG: Dictionary = {
	"STR": "strength",
	"INT": "intelligence",
	"WIS": "wisdom",
	"DEX": "dexterity",
	"CON": "constitution",
	"CHA": "charisma",
}

var _tables: Dictionary = {}
var _loaded: bool = false


func _init() -> void:
	_load_tables()


func _load_tables() -> void:
	var file := FileAccess.open(TABLES_PATH, FileAccess.READ)
	if file == null:
		push_error("AgingSystem: cannot open '%s'" % TABLES_PATH)
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("AgingSystem: failed to parse '%s'" % TABLES_PATH)
		return
	_tables = parsed as Dictionary
	_loaded = true


# ---------------------------------------------------------------------------
# Starting Age
# ---------------------------------------------------------------------------

func get_starting_age_expression(class_id: String) -> String:
	## Returns the dice expression for a class's starting age (e.g., "15+1d8").
	## Falls back to "17+1d6" (generic adult adventurer) if class not found.
	if not _loaded:
		return "17+1d6"
	var by_class: Dictionary = _tables.get("starting_age_by_class", {})
	return by_class.get(class_id, "17+1d6")


func roll_starting_age(class_id: String) -> int:
	## Rolls and returns the starting age for a character of the given class.
	## Parses the formula (e.g., "15+1d8") and calls DiceSystem.roll_expression().
	var expr := get_starting_age_expression(class_id)
	# roll_expression handles "XdY" but not "BASE+XdY" — parse manually.
	# Formula format: "<base>+<dice_expr>" or just "<base>"
	var result := _evaluate_age_expression(expr)
	return result


func _evaluate_age_expression(expr: String) -> int:
	## Parses "BASE+XdY" or "BASE" and returns a rolled total.
	## Examples: "15+1d8" -> 15 + roll(1d8), "17+3d6" -> 17 + roll(3d6)
	var plus_pos := expr.find("+")
	if plus_pos == -1:
		# No dice component — just a fixed base.
		if expr.is_valid_int():
			return int(expr)
		push_error("AgingSystem._evaluate_age_expression: cannot parse '%s'" % expr)
		return 17
	var base_str := expr.left(plus_pos)
	var dice_str := expr.substr(plus_pos + 1)
	var base := int(base_str) if base_str.is_valid_int() else 0
	var roll_result: RollResult = DiceSystem.roll_expression(dice_str, "starting_age")
	return base + roll_result.modified_total


# ---------------------------------------------------------------------------
# Age Category
# ---------------------------------------------------------------------------

func get_age_category(race: String, age: int) -> String:
	## Returns the age category string for the given race and age.
	## Returns "adult" as a safe default if race is unknown or age is out of range.
	if not _loaded:
		return "adult"
	var race_key := race.to_lower()
	var categories: Dictionary = _tables.get("age_categories_by_race", {}).get(race_key, {})
	if categories.is_empty():
		# Unknown race — use human thresholds as fallback.
		categories = _tables.get("age_categories_by_race", {}).get("human", {})

	# Walk CATEGORY_ORDER so we find the highest applicable category.
	var result := "adult"
	for cat in CATEGORY_ORDER:
		if not categories.has(cat):
			continue
		var range_arr: Array = categories[cat]
		if range_arr.size() < 2:
			continue
		if age >= int(range_arr[0]) and age <= int(range_arr[1]):
			return cat
		# If beyond this category's max and no later category matched yet, use this.
		if age > int(range_arr[1]):
			result = cat

	return result


func get_next_category_age(race: String, current_category: String) -> int:
	## Returns the minimum age at which the character transitions to the next category.
	## Returns -1 if there is no next category (max category or elf adult-cap).
	if not _loaded:
		return -1
	var race_key := race.to_lower()
	var categories: Dictionary = _tables.get("age_categories_by_race", {}).get(race_key, {})
	if categories.is_empty():
		categories = _tables.get("age_categories_by_race", {}).get("human", {})

	var current_idx := CATEGORY_ORDER.find(current_category)
	if current_idx == -1:
		return -1
	for i in range(current_idx + 1, CATEGORY_ORDER.size()):
		var next_cat: String = CATEGORY_ORDER[i]
		if categories.has(next_cat):
			var range_arr: Array = categories[next_cat]
			if range_arr.size() >= 1:
				return int(range_arr[0])
	return -1


# ---------------------------------------------------------------------------
# Age Change & Category Transitions
# ---------------------------------------------------------------------------

func apply_age_change(character: CharacterData, years: int) -> Dictionary:
	## Apply an age change to a character in-place. Handles category transitions
	## with progressive ability adjustments across each step.
	##
	## Returns a result dictionary:
	##   { "old_age", "new_age", "old_category", "new_category",
	##     "category_changed", "ability_changes", "death_save_required",
	##     "death_save_trigger" }
	var old_age := character.current_age
	var new_age := maxi(0, old_age + years)
	var old_cat := character.age_category
	var new_cat := get_age_category(character.race, new_age)

	character.current_age = new_age
	character.age_category = new_cat

	var ability_changes: Dictionary = {}

	if new_cat != old_cat:
		# Apply progressive adjustments for each intermediate category transition.
		var old_idx := CATEGORY_ORDER.find(old_cat)
		var new_idx := CATEGORY_ORDER.find(new_cat)

		if old_idx == -1:
			old_idx = 1  # default to "adult"
		if new_idx == -1:
			new_idx = 1

		if new_idx > old_idx:
			# Aging forward — apply each step in sequence.
			for i in range(old_idx, new_idx):
				var from_cat: String = CATEGORY_ORDER[i]
				var to_cat: String = CATEGORY_ORDER[i + 1]
				var step_changes := _apply_category_transition(character, from_cat, to_cat)
				for ability in step_changes.keys():
					var current_delta: int = ability_changes.get(ability, 0)
					ability_changes[ability] = current_delta + int(step_changes[ability])

	# Check death-from-age.
	var death_check := check_death_from_age(character)

	return {
		"old_age": old_age,
		"new_age": new_age,
		"old_category": old_cat,
		"new_category": new_cat,
		"category_changed": new_cat != old_cat,
		"ability_changes": ability_changes,
		"death_save_required": death_check.get("required", false),
		"death_save_trigger": death_check.get("trigger", ""),
	}


func apply_cumulative_adjustments(character: CharacterData, target_category: String) -> Dictionary:
	## Apply cumulative aging adjustments for a character generated at an advanced age.
	## Used for NPCs who start older than "adult".
	## Skips the youth->adult bonus (starts from adult baseline).
	## Returns ability_changes dictionary with net deltas applied.
	var ability_changes: Dictionary = {}
	var adult_idx := CATEGORY_ORDER.find("adult")
	var target_idx := CATEGORY_ORDER.find(target_category)
	if target_idx <= adult_idx:
		return ability_changes  # Nothing to apply for youth or adult.

	for i in range(adult_idx, target_idx):
		var from_cat: String = CATEGORY_ORDER[i]
		var to_cat: String = CATEGORY_ORDER[i + 1]
		var step_changes := _apply_category_transition(character, from_cat, to_cat)
		for ability in step_changes.keys():
			var current_delta: int = ability_changes.get(ability, 0)
			ability_changes[ability] = current_delta + int(step_changes[ability])

	return ability_changes


func _apply_category_transition(character: CharacterData, from_cat: String,
		to_cat: String) -> Dictionary:
	## Apply progressive ability adjustments for a single category step.
	## Clamps each ability to the appropriate floor.
	## Returns a dictionary of { "ability_name": delta_applied }.
	var adjustments := _get_transition_adjustments(from_cat, to_cat)
	var applied: Dictionary = {}

	for ability in adjustments.keys():
		var delta: int = int(adjustments[ability])
		var current_val: int = int(character.get(ability))
		var floor_val := _get_ability_floor(character, ability)
		var new_val := clampi(current_val + delta, floor_val, 18)
		var actual_delta := new_val - current_val
		if actual_delta != 0:
			character.set(ability, new_val)
			applied[ability] = actual_delta

	return applied


func _get_transition_adjustments(from_cat: String, to_cat: String) -> Dictionary:
	## Returns the adjustments dictionary for a category step.
	## Key: "youth_to_adult", "adult_to_middle_aged", etc.
	if not _loaded:
		return {}
	var key := "%s_to_%s" % [from_cat, to_cat]
	var all_adjustments: Dictionary = _tables.get("ability_adjustments", {})
	return all_adjustments.get(key, {})


func _get_ability_floor(character: CharacterData, ability: String) -> int:
	## Returns the minimum value this ability can be reduced to by aging.
	## Prime requisites for the character's class floor at 9 (class minimum per ACKS).
	## All other abilities floor at 3.
	## Source: acore_aging_poisons_high-level-start_optional_rules.xml lines 126-127.

	# We need ClassRegistry to check prime requisites, but AgingSystem doesn't hold one.
	# To keep AgingSystem self-contained, we accept the class_id string from CharacterData
	# and check a lightweight prime req lookup.
	# The ACKS rule: "cannot reduce below class minimum" (prime reqs have min 9).
	# Non-prime-req abilities floor at 3.

	# Since we don't have ClassRegistry injected, we read it from EventBus / GameState
	# if available — but that creates coupling. Safer approach: store the floor in
	# CharacterData or accept a class_def dict from the caller. However, the plan
	# specifies AgingSystem as the authority. We compromise: floor is always 3 for
	# abilities that have no class prime req, 9 for prime reqs. We detect prime reqs
	# by checking a hardcoded class-prime-req table (avoids ClassRegistry dependency).

	# Hardcoded class prime requisite table (from data/classes/*.json, all 25 classes).
	# Only abilities that are prime reqs for ANY class need the 9 floor.
	# This is an implementation detail — ClassRegistry is ground truth at runtime,
	# but for the floor calculation we just need to know whether THIS character's class
	# uses this ability as a prime req.
	const CLASS_PRIME_REQS: Dictionary = {
		"fighter":         ["STR"],
		"mage":            ["INT"],
		"cleric":          ["WIS"],
		"thief":           ["DEX"],
		"assassin":        ["STR"],
		"bard":            ["DEX"],
		"bladedancer":     ["DEX", "WIS"],
		"explorer":        ["STR", "DEX"],
		"venturer":        ["INT", "CHA"],
		"paladin":         ["STR", "WIS"],
		"anti_paladin":    ["STR", "WIS"],
		"barbarian":       ["STR"],
		"priestess":       ["WIS", "CHA"],
		"shaman":          ["WIS", "CHA"],
		"warlock":         ["INT", "CHA"],
		"witch":           ["INT", "WIS"],
		"dwarf_vaultguard":  ["STR"],
		"dwarf_craftpriest": ["WIS"],
		"dwarven_delver":    ["STR", "INT"],
		"dwarven_fury":      ["STR", "CON"],
		"elf_spellsword":    ["STR", "INT"],
		"elf_nightblade":    ["DEX", "INT"],
		"elven_courtier":    ["INT", "CHA"],
		"elven_enchanter":   ["INT", "WIS"],
		"elven_ranger":      ["STR", "DEX"],
	}
	# Map ability long name to short abbreviation.
	const LONG_TO_SHORT: Dictionary = {
		"strength":     "STR",
		"intelligence": "INT",
		"wisdom":       "WIS",
		"dexterity":    "DEX",
		"constitution": "CON",
		"charisma":     "CHA",
	}
	var short_name: String = LONG_TO_SHORT.get(ability, "")
	var class_primes: Array = CLASS_PRIME_REQS.get(character.character_class, [])
	if short_name in class_primes:
		return 9  # Prime requisite — never drops below class minimum.
	return 3   # All other abilities floor at 3.


# ---------------------------------------------------------------------------
# Death from Old Age
# ---------------------------------------------------------------------------

func check_death_from_age(character: CharacterData) -> Dictionary:
	## Check whether a death-from-old-age save is triggered at the character's current age.
	## Source: acore_aging_poisons_high-level-start_optional_rules.xml lines 130-142.
	##
	## Three triggers:
	##   1. racial_min_old_plus_con: min old age + current CON score
	##   2. racial_min_ancient_plus_con: min ancient age + current CON score
	##   3. max_age_and_beyond: at and after racial max age (annually)
	##
	## Returns { "required": bool, "save_type": String, "trigger": String }
	if not _loaded:
		return {"required": false, "save_type": "", "trigger": ""}

	var race_key := character.race.to_lower()
	var death_data: Variant = _tables.get("death_from_old_age", {}).get(race_key)
	if death_data == null:
		# Race is immortal (elf) or unknown — no death save.
		return {"required": false, "save_type": "", "trigger": ""}

	var categories: Dictionary = _tables.get("age_categories_by_race", {}).get(race_key, {})
	var con_score := character.constitution
	var age := character.current_age

	# Trigger 1: min old age + CON
	if categories.has("old"):
		var old_min: int = int((categories["old"] as Array)[0])
		if age == old_min + con_score:
			return {
				"required": true,
				"save_type": "save_poison_death",
				"trigger": "racial_min_old_plus_con",
			}

	# Trigger 2: min ancient age + CON
	if categories.has("ancient"):
		var ancient_min: int = int((categories["ancient"] as Array)[0])
		if age == ancient_min + con_score:
			return {
				"required": true,
				"save_type": "save_poison_death",
				"trigger": "racial_min_ancient_plus_con",
			}

	# Trigger 3: max age and each year beyond
	var max_age: int = int(death_data.get("max_age", 9999))
	if age >= max_age:
		return {
			"required": true,
			"save_type": "save_poison_death",
			"trigger": "max_age_and_beyond",
		}

	return {"required": false, "save_type": "", "trigger": ""}
