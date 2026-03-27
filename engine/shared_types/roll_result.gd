class_name RollResult
extends RefCounted

## The result of a single resolved dice roll.
##
## Produced by DiceSystem for every roll (digital, player-prompted, or overridden).
## Passed between systems, emitted via EventBus.dice_rolled, and logged to dice_rolls DB.
##
## modifier is stored here for reference but is applied by DiceSystem before this object
## is returned. Callers always read modified_total as the final result to use.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Action vocabulary roll type. e.g. "attack_throw", "damage_roll", "saving_throw_poison".
## Empty string for unnamed utility rolls.
var roll_type: String = ""

## Number of faces on each die. Valid values: 3, 4, 6, 8, 10, 12, 20, 100.
var sides: int = 6

## Number of dice rolled.
var count: int = 1

## Flat additive modifier applied by the app. Not included in raw_total.
var modifier: int = 0

## Individual die results before modifier. Length == count for digital rolls.
## For player-entered and overridden results: length == 1 (the entered/forced total).
var individual_results: Array[int] = []

## Sum of individual_results (no modifier).
var raw_total: int = 0

## raw_total + modifier. This is the value subsystems should act on.
var modified_total: int = 0

## True if this roll was forced by a queued GameState.dice_overrides entry.
var was_overridden: bool = false

## True if the player typed this result manually (physical dice entry).
## False for digital rolls and for "Roll Dice" button rolls in the DicePrompt.
var was_player_entered: bool = false

## True only for single-die d20 rolls that came up exactly 1.
## Signals potential auto-fail in attack throws, proficiency throws, etc.
## Always false for multi-die rolls (2d6, 3d6, etc.).
var natural_one: bool = false

## True only for single-die d20 rolls that came up exactly 20.
## Signals potential auto-success in attack throws, etc.
## Always false for multi-die rolls.
var natural_max: bool = false

## Human-readable description passed to player_roll() for UI display.
var description: String = ""


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

## Returns a plain Dictionary suitable for EventBus signal payloads and DB logging.
func to_dict() -> Dictionary:
	return {
		"roll_type":          roll_type,
		"sides":              sides,
		"count":              count,
		"modifier":           modifier,
		"individual_results": individual_results,
		"raw_total":          raw_total,
		"modified_total":     modified_total,
		"was_overridden":     was_overridden,
		"was_player_entered": was_player_entered,
		"natural_one":        natural_one,
		"natural_max":        natural_max,
		"description":        description,
	}
