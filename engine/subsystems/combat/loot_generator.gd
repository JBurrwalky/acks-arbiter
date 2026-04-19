class_name LootGenerator
extends RefCounted

# LootGenerator — builds a coin loot payload from defeated monsters' treasure types.
#
# v1: coins only. Gems, jewelry, and magic items deferred to a future pass.
#
# Dependencies:
#   - DiceSystem (autoload): percentage checks and coin dice rolls
#   - Currency: denomination conversion for GP value computation
#
# Design note:
#   Pure computation — no side effects. Instantiated locally by CombatController
#   in _emit_combat_ended(). The caller decides whether loot should be generated
#   (e.g., wilderness victory only).
#
# Source: rules/acore_treasure_and_magic_items_rules.xml §treasure_type_table
# Coin columns are in thousands (e.g., "80% 2d20" copper = 80% chance, 2d20 × 1000 cp).

const Currency := preload("res://engine/subsystems/commerce/currency.gd")


# ---------------------------------------------------------------------------
# Treasure type table — coins only
# ---------------------------------------------------------------------------
# Each entry: {copper, silver, electrum, gold, platinum}
# Each coin column is either null (no coins of that type) or
# {chance_pct: int, dice_expr: String} where the dice result × 1000 = coin count.

const TREASURE_TYPE_TABLE := {
	"A": {
		"copper": null,
		"silver": {"chance_pct": 30, "dice_expr": "1d4"},
		"electrum": null,
		"gold": null,
		"platinum": null,
	},
	"B": {
		"copper": null,
		"silver": {"chance_pct": 80, "dice_expr": "1d6"},
		"electrum": null,
		"gold": null,
		"platinum": null,
	},
	"C": {
		"copper": null,
		"silver": null,
		"electrum": {"chance_pct": 15, "dice_expr": "1d4"},
		"gold": null,
		"platinum": null,
	},
	"D": {
		"copper": null,
		"silver": {"chance_pct": 80, "dice_expr": "1d6"},
		"electrum": {"chance_pct": 20, "dice_expr": "1d4"},
		"gold": null,
		"platinum": null,
	},
	"E": {
		"copper": {"chance_pct": 80, "dice_expr": "2d20"},
		"silver": {"chance_pct": 7, "dice_expr": "3d6"},
		"electrum": null,
		"gold": null,
		"platinum": null,
	},
	"F": {
		"copper": null,
		"silver": {"chance_pct": 30, "dice_expr": "1d4"},
		"electrum": null,
		"gold": {"chance_pct": 15, "dice_expr": "1d4"},
		"platinum": null,
	},
	"G": {
		"copper": {"chance_pct": 70, "dice_expr": "2d20"},
		"silver": {"chance_pct": 70, "dice_expr": "3d6"},
		"electrum": {"chance_pct": 50, "dice_expr": "1d4"},
		"gold": null,
		"platinum": null,
	},
	"H": {
		"copper": null,
		"silver": {"chance_pct": 25, "dice_expr": "1d6"},
		"electrum": {"chance_pct": 70, "dice_expr": "1d6"},
		"gold": null,
		"platinum": null,
	},
	"I": {
		"copper": null,
		"silver": {"chance_pct": 25, "dice_expr": "1d4"},
		"electrum": null,
		"gold": {"chance_pct": 25, "dice_expr": "1d6"},
		"platinum": null,
	},
	"J": {
		"copper": {"chance_pct": 50, "dice_expr": "3d6"},
		"silver": {"chance_pct": 70, "dice_expr": "2d20"},
		"electrum": {"chance_pct": 70, "dice_expr": "1d8"},
		"gold": null,
		"platinum": null,
	},
	"K": {
		"copper": null,
		"silver": null,
		"electrum": {"chance_pct": 30, "dice_expr": "1d4"},
		"gold": {"chance_pct": 25, "dice_expr": "1d6"},
		"platinum": null,
	},
	"L": {
		"copper": {"chance_pct": 40, "dice_expr": "3d6"},
		"silver": {"chance_pct": 60, "dice_expr": "2d10"},
		"electrum": {"chance_pct": 75, "dice_expr": "3d6"},
		"gold": null,
		"platinum": null,
	},
	"M": {
		"copper": null,
		"silver": null,
		"electrum": {"chance_pct": 25, "dice_expr": "1d4"},
		"gold": null,
		"platinum": {"chance_pct": 15, "dice_expr": "1d4"},
	},
	"N": {
		"copper": null,
		"silver": {"chance_pct": 60, "dice_expr": "1d8"},
		"electrum": {"chance_pct": 60, "dice_expr": "2d4"},
		"gold": {"chance_pct": 80, "dice_expr": "1d6"},
		"platinum": null,
	},
	"O": {
		"copper": {"chance_pct": 30, "dice_expr": "3d6"},
		"silver": {"chance_pct": 50, "dice_expr": "3d6"},
		"electrum": {"chance_pct": 60, "dice_expr": "3d6"},
		"gold": {"chance_pct": 60, "dice_expr": "2d6"},
		"platinum": null,
	},
	"P": {
		"copper": null,
		"silver": null,
		"electrum": null,
		"gold": {"chance_pct": 30, "dice_expr": "1d4"},
		"platinum": {"chance_pct": 30, "dice_expr": "1d4"},
	},
	"Q": {
		"copper": null,
		"silver": null,
		"electrum": {"chance_pct": 50, "dice_expr": "1d8"},
		"gold": {"chance_pct": 80, "dice_expr": "2d6"},
		"platinum": {"chance_pct": 40, "dice_expr": "1d4"},
	},
	"R": {
		"copper": null,
		"silver": null,
		"electrum": {"chance_pct": 50, "dice_expr": "1d6"},
		"gold": {"chance_pct": 60, "dice_expr": "1d6"},
		"platinum": {"chance_pct": 80, "dice_expr": "1d8"},
	},
}

# Maps coin column name → outcome dict key.
const _COIN_KEY_MAP := {
	"copper": "coins_cp",
	"silver": "coins_sp",
	"electrum": "coins_ep",
	"gold": "coins_gp",
	"platinum": "coins_pp",
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Generates a coin loot payload from an array of raw treasure_type strings.
## Each string is parsed to extract the letter (e.g., "E (per warband)" → "E").
## Returns {coins_cp, coins_sp, coins_ep, coins_gp, coins_pp} with aggregated totals.
## Returns an empty dict if no valid treasure types are provided.
func generate_from_treasure_types(types: Array) -> Dictionary:
	var result := {
		"coins_cp": 0,
		"coins_sp": 0,
		"coins_ep": 0,
		"coins_gp": 0,
		"coins_pp": 0,
	}

	var any_valid := false
	for raw_type in types:
		var letter := _parse_treasure_letter(str(raw_type))
		if letter.is_empty():
			continue
		if not TREASURE_TYPE_TABLE.has(letter):
			push_warning("LootGenerator: unknown treasure type letter '%s' from '%s'" % [letter, raw_type])
			continue

		any_valid = true
		var type_entry: Dictionary = TREASURE_TYPE_TABLE[letter]
		for coin_column in _COIN_KEY_MAP:
			var column_def = type_entry.get(coin_column)
			if column_def == null:
				continue
			var coins := _roll_coin_column(
				column_def["chance_pct"],
				column_def["dice_expr"])
			result[_COIN_KEY_MAP[coin_column]] += coins

	if not any_valid:
		return {}

	return result


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Extracts the treasure type letter from a raw string.
## "E (per warband)" → "E", "G" → "G", "None" → "", "" → "".
func _parse_treasure_letter(raw: String) -> String:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty() or trimmed == "None":
		return ""
	# First character is the type letter (A–R).
	var letter := trimmed[0].to_upper()
	if letter < "A" or letter > "R":
		return ""
	return letter


## Rolls a single coin column.
## Returns the number of coins (dice result × 1000), or 0 if the percentage check fails.
func _roll_coin_column(chance_pct: int, dice_expr: String) -> int:
	# Percentage check: roll d100, succeed if ≤ chance_pct.
	var pct_roll: int = DiceSystem.roll_digital(100, 1, 0, "treasure_chance").modified_total
	if pct_roll > chance_pct:
		return 0

	# Roll the dice expression and multiply by 1000 (table is in thousands of coins).
	var coin_roll: int = DiceSystem.roll_expression(dice_expr, "treasure_coins").modified_total
	return coin_roll * 1000


# ---------------------------------------------------------------------------
# Treasure XP valuation
# ---------------------------------------------------------------------------

## Returns the GP value of a coins dictionary for XP purposes.
## ACKS RAW (acore_treasure_and_magic_items_rules.xml): 1 XP per 1 GP of
## coins, gems, jewelry, or special treasure recovered on adventures.
## Equipment is excluded — only sold equipment counts (future feature).
## v1: coins-only, so this is a straight denomination conversion.
static func compute_treasure_gp_value(coins: Dictionary) -> int:
	var total_cp := Currency.coins_to_cp(coins)
	return total_cp / 100  # Integer division; 100 cp = 1 gp
