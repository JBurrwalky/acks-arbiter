class_name Currency
extends RefCounted

## Currency denomination constants and utility methods for ACKS coin system.
##
## All five ACKS 1e coin denominations, with values expressed in copper pieces (cp).
## Exchange rates (ACKS 1e Core p.36):
##   1 pp = 5 gp  = 50 sp  = 500 cp
##   1 gp = 10 sp = 100 cp
##   1 ep = 5 sp  = 50 cp
##   1 sp = 10 cp
##
## Encumbrance: all coin types weigh 1 enc unit per coin (1000 coins = 1 stone).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Ordered highest → lowest by cp_value for change-making and display.
## Keys use plural "coins_" prefix to match existing DB data and premade party JSON.
const DENOMINATIONS := [
	{"key": "coins_pp", "name": "Platinum Pieces", "cp_value": 500, "abbr": "pp"},
	{"key": "coins_gp", "name": "Gold Pieces",     "cp_value": 100, "abbr": "gp"},
	{"key": "coins_ep", "name": "Electrum Pieces", "cp_value": 50,  "abbr": "ep"},
	{"key": "coins_sp", "name": "Silver Pieces",    "cp_value": 10,  "abbr": "sp"},
	{"key": "coins_cp", "name": "Copper Pieces",    "cp_value": 1,   "abbr": "cp"},
]

const COIN_KEYS := ["coins_pp", "coins_gp", "coins_ep", "coins_sp", "coins_cp"]

## Encumbrance per coin in 1/1000-stone units.
const ENC_PER_COIN := 1

## Inventory item_category for all coin types.
const COIN_ITEM_CATEGORY := "treasure"


# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

## Returns the denomination dict for a given item_key, or empty dict if not a coin.
static func get_denomination(coin_key: String) -> Dictionary:
	for d in DENOMINATIONS:
		if d["key"] == coin_key:
			return d
	return {}


## Returns true if the given item_key is a coin denomination.
static func is_coin(item_key: String) -> bool:
	return coin_key_to_cp_value(item_key) > 0


## Returns the copper-piece value of one coin of the given type, or 0 if invalid.
static func coin_key_to_cp_value(coin_key: String) -> int:
	for d in DENOMINATIONS:
		if d["key"] == coin_key:
			return d["cp_value"]
	return 0


## Returns the display name for a coin key, or "" if invalid.
static func coin_key_to_name(coin_key: String) -> String:
	for d in DENOMINATIONS:
		if d["key"] == coin_key:
			return d["name"]
	return ""


# ---------------------------------------------------------------------------
# Wealth calculation
# ---------------------------------------------------------------------------

## Converts a coins dictionary ({coin_pp: qty, coin_gp: qty, ...}) to total copper value.
static func coins_to_cp(coins: Dictionary) -> int:
	var total := 0
	for d in DENOMINATIONS:
		total += coins.get(d["key"], 0) * d["cp_value"]
	return total


## Distributes a copper amount into denominations, highest-first.
## Returns a dictionary with coin keys mapped to quantities.
## Only includes denominations with qty > 0.
static func cp_to_coins(amount_cp: int) -> Dictionary:
	var result := {}
	var remaining := amount_cp
	for d in DENOMINATIONS:
		var qty: int = remaining / d["cp_value"]
		if qty > 0:
			result[d["key"]] = qty
			remaining -= qty * d["cp_value"]
	return result


# ---------------------------------------------------------------------------
# Change-making (for deductions)
# ---------------------------------------------------------------------------

## Computes how to deduct a cost (in cp) from a set of held coins.
## Spends smallest denominations first (cp → sp → gp → ep → pp),
## then makes change from the next-larger denomination when needed.
##
## Returns { "success": bool, "new_coins": Dictionary, "message": String }
## On success, new_coins contains the updated coin quantities after deduction.
## On failure (insufficient funds), new_coins is empty.
static func compute_deduction(coins: Dictionary, cost_cp: int) -> Dictionary:
	var total_wealth := coins_to_cp(coins)
	if total_wealth < cost_cp:
		return {
			"success": false,
			"new_coins": {},
			"message": "Insufficient funds: need %s, have %s" % [
				format_cost(cost_cp), format_cost(total_wealth)],
		}

	# Work with a mutable copy, smallest denomination first.
	var working := {}
	for key in COIN_KEYS:
		working[key] = coins.get(key, 0)

	var remaining_cost := cost_cp

	# Pass 1: spend from smallest denominations upward.
	var reversed_denoms := DENOMINATIONS.duplicate()
	reversed_denoms.reverse()
	for d in reversed_denoms:
		if remaining_cost <= 0:
			break
		var key: String = d["key"]
		var cp_val: int = d["cp_value"]
		var have: int = working[key]
		if have <= 0:
			continue
		# How many whole coins of this denomination can we spend?
		var coins_needed: int = remaining_cost / cp_val
		var coins_to_spend: int = mini(coins_needed, have)
		if coins_to_spend > 0:
			working[key] -= coins_to_spend
			remaining_cost -= coins_to_spend * cp_val

	# Pass 2: if remaining_cost > 0, we need to break a larger coin.
	if remaining_cost > 0:
		# Find the smallest denomination that covers the remaining cost
		# and that we actually have.
		for d in reversed_denoms:
			var key: String = d["key"]
			var cp_val: int = d["cp_value"]
			if working[key] > 0 and cp_val >= remaining_cost:
				working[key] -= 1
				var change_cp: int = cp_val - remaining_cost
				remaining_cost = 0
				# Distribute change back into coins (highest-first).
				var change_coins := cp_to_coins(change_cp)
				for ck in change_coins:
					working[ck] = working.get(ck, 0) + change_coins[ck]
				break

	# Safety check — should never happen if total_wealth >= cost_cp.
	if remaining_cost > 0:
		push_error("Currency.compute_deduction: logic error, remaining_cost=%d after deduction" % remaining_cost)
		return {"success": false, "new_coins": {}, "message": "Internal error in change-making"}

	return {"success": true, "new_coins": working, "message": ""}


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

## Formats a copper amount as a cost-display string using only the three
## "abstract value" denominations gp/sp/cp (pp/ep are physical coin types,
## reserved for inventory/treasure/loot displays via `format_wealth`).
##
## Per the 2026-05-18 currency-display rule (user spec):
##   * Use gp/sp/cp only — no pp, no ep.
##   * Skip zero-magnitude denominations.
##   * Comma+space separator between denominations.
##
## Examples:
##   1789  → "17gp, 8sp, 9cp"
##   5000  → "50gp"
##   50_107 → "501gp, 7cp"
##   30    → "3sp"
##   0     → "0cp"
static func format_cost(cost_cp: int) -> String:
	if cost_cp <= 0:
		return "0cp"

	var parts: Array[String] = []
	var remaining := cost_cp
	# Only gp / sp / cp — pp and ep are reserved for `format_wealth` (physical
	# coin display in inventory/treasure/loot views).
	for d in DENOMINATIONS:
		var abbr: String = String(d["abbr"])
		if abbr != "gp" and abbr != "sp" and abbr != "cp":
			continue
		var qty: int = remaining / d["cp_value"]
		if qty > 0:
			parts.append("%d%s" % [qty, abbr])
			remaining -= qty * d["cp_value"]
	return ", ".join(parts)


## Formats a coins dictionary showing actual held quantities per denomination.
## Only shows denominations with qty > 0.
## Example: {"coin_pp": 2, "coin_gp": 3, "coin_sp": 5} → "2pp 3gp 5sp"
static func format_wealth(coins: Dictionary) -> String:
	var parts: Array[String] = []
	for d in DENOMINATIONS:
		var qty: int = coins.get(d["key"], 0)
		if qty > 0:
			parts.append("%d%s" % [qty, d["abbr"]])
	if parts.is_empty():
		return "0cp"
	return " ".join(parts)
