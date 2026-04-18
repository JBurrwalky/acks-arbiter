# PartyWallet — gold aggregation and auto-deduction across PCs in the same party location
#
# Dependencies:
#   - GameState (autoload): reads party_id for default party context
#   - CampaignRepository (autoload): all actual coin storage via existing methods
#   - Currency (engine/subsystems/commerce/currency.gd): denomination math helpers
#   - EventBus (autoload): emits wallet_paid, wallet_deposited, wallet_changed signals
#
# Signals emitted (mirrored to EventBus):
#   - EventBus.wallet_paid(party_id, details)
#   - EventBus.wallet_deposited(party_id, details)
#   - EventBus.wallet_changed(party_id)
#
# Design note:
#   PartyWallet does NOT store gold. Gold lives in inventory_items rows per character.
#   This class is a view-and-aggregation layer over CampaignRepository.get_character_coins()
#   and deduct_cost_cp() / add_coins_cp(). Wallet eligibility is per-location per-party.
#
# Known issue (Session 1):
#   Location filtering is stubbed — all PCs in the party are treated as co-located.
#   Must-fix for Session 2 (LocationCacheManager) to scope by hex/settlement/dungeon level.

extends Node


# ---------------------------------------------------------------------------
# Public API — Aggregation
# ---------------------------------------------------------------------------

## Returns total copper across eligible PC carriers in the party.
func get_party_total_cp(party_id: String) -> int:
	var total := 0
	for char_id in _get_pc_ids(party_id):
		total += CampaignRepository.get_character_wealth_cp(char_id)
	return total


## Returns total as a GP float for display purposes.
## Uses Currency.coins_to_cp() rates — display-only convenience.
func get_party_total_gp_float(party_id: String) -> float:
	return get_party_total_cp(party_id) / 100.0


## Returns aggregated coin breakdown across eligible PCs.
## Keys: coins_pp, coins_gp, coins_ep, coins_sp, coins_cp, total_cp
func get_party_breakdown(party_id: String) -> Dictionary:
	var result := {
		"coins_pp": 0, "coins_gp": 0, "coins_ep": 0,
		"coins_sp": 0, "coins_cp": 0, "total_cp": 0,
	}
	for char_id in _get_pc_ids(party_id):
		var coins: Dictionary = CampaignRepository.get_character_coins(char_id)
		for key in Currency.COIN_KEYS:
			result[key] += coins.get(key, 0)
	result["total_cp"] = Currency.coins_to_cp(result)
	return result


# ---------------------------------------------------------------------------
# Public API — Contributors
# ---------------------------------------------------------------------------

## Returns ordered list of PC character IDs eligible to contribute to a payment.
## Order: active_character_id first, then remaining PCs by party join order.
## Excludes henchmen, mercenaries, creatures, vehicles, and (future) out-of-location PCs.
func get_contributors(party_id: String, active_character_id: String) -> Array:
	var pc_ids := _get_pc_ids(party_id)
	# Move active character to front if present.
	var idx := pc_ids.find(active_character_id)
	if idx > 0:
		pc_ids.remove_at(idx)
		pc_ids.insert(0, active_character_id)
	return pc_ids


# ---------------------------------------------------------------------------
# Public API — Affordability
# ---------------------------------------------------------------------------

## Checks whether the party can afford a cost (in cp).
## Returns {ok: bool, shortfall_cp: int}.
func can_afford(cost_cp: int, party_id: String, active_character_id: String) -> Dictionary:
	var total := 0
	for char_id in get_contributors(party_id, active_character_id):
		total += CampaignRepository.get_character_wealth_cp(char_id)
	var shortfall := maxi(cost_cp - total, 0)
	return {"ok": shortfall == 0, "shortfall_cp": shortfall}


# ---------------------------------------------------------------------------
# Public API — Payment
# ---------------------------------------------------------------------------

## Deducts cost_cp from eligible contributors in order (active character first).
## Returns {ok, message, total_paid_cp, per_character_deductions}.
## per_character_deductions: {char_id: {coins_pp, coins_gp, coins_ep, coins_sp, coins_cp}}
## representing the coins removed from each contributor.
func pay(cost_cp: int, party_id: String, active_character_id: String) -> Dictionary:
	if cost_cp <= 0:
		return {"ok": true, "message": "", "total_paid_cp": 0, "per_character_deductions": {}}

	var contributors := get_contributors(party_id, active_character_id)

	# Pre-flight affordability check.
	var afford := can_afford(cost_cp, party_id, active_character_id)
	if not afford["ok"]:
		return {
			"ok": false,
			"message": "Insufficient party funds. Short by %.2f GP." % (afford["shortfall_cp"] / 100.0),
			"total_paid_cp": 0,
			"per_character_deductions": {},
		}

	var per_char_deductions := {}
	var remaining_cp := cost_cp

	for char_id in contributors:
		if remaining_cp <= 0:
			break
		var wealth_cp: int = CampaignRepository.get_character_wealth_cp(char_id)
		if wealth_cp <= 0:
			continue
		var pay_this: int = mini(wealth_cp, remaining_cp)

		var before_coins: Dictionary = CampaignRepository.get_character_coins(char_id)
		var result: Dictionary = CampaignRepository.deduct_cost_cp(char_id, pay_this)
		if not result["success"]:
			push_error("PartyWallet: deduct_cost_cp failed mid-payment. Char: %s. Message: %s" % [
				char_id, result.get("message", "")])
			_rollback_payments(per_char_deductions)
			return {
				"ok": false,
				"message": "Payment failed mid-way; rolled back.",
				"total_paid_cp": 0,
				"per_character_deductions": {},
			}
		var after_coins: Dictionary = CampaignRepository.get_character_coins(char_id)
		per_char_deductions[char_id] = _compute_coin_diff(before_coins, after_coins)
		remaining_cp -= pay_this

	# Emit signals after all deductions are complete (avoids inconsistent mid-deduction refreshes).
	EventBus.wallet_paid.emit(party_id, {
		"cost_cp": cost_cp,
		"active_character_id": active_character_id,
		"per_character_deductions": per_char_deductions,
	})
	EventBus.wallet_changed.emit(party_id)

	return {
		"ok": true,
		"message": "",
		"total_paid_cp": cost_cp,
		"per_character_deductions": per_char_deductions,
	}


## Strict single-character deduction. For bribes, personal purchases.
func pay_from_character(character_id: String, cost_cp: int) -> Dictionary:
	if cost_cp <= 0:
		return {"ok": true, "message": "", "total_paid_cp": 0, "per_character_deductions": {}}

	var before_coins: Dictionary = CampaignRepository.get_character_coins(character_id)
	var result: Dictionary = CampaignRepository.deduct_cost_cp(character_id, cost_cp)
	if not result["success"]:
		return {"ok": false, "message": result.get("message", "Insufficient funds"), "total_paid_cp": 0, "per_character_deductions": {}}

	var after_coins: Dictionary = CampaignRepository.get_character_coins(character_id)
	var diff := _compute_coin_diff(before_coins, after_coins)
	var char_data: Dictionary = CampaignRepository.get_character(character_id)
	var p_id: String = _get_party_id_for_character(character_id)

	EventBus.wallet_paid.emit(p_id, {
		"cost_cp": cost_cp,
		"active_character_id": character_id,
		"per_character_deductions": {character_id: diff},
	})
	EventBus.wallet_changed.emit(p_id)

	return {
		"ok": true,
		"message": "",
		"total_paid_cp": cost_cp,
		"per_character_deductions": {character_id: diff},
	}


# ---------------------------------------------------------------------------
# Public API — Deposits
# ---------------------------------------------------------------------------

## Adds gold to a specific character. Thin wrapper over CampaignRepository.add_coins_cp().
func deposit_to_character(character_id: String, amount_cp: int) -> void:
	if amount_cp <= 0:
		return
	CampaignRepository.add_coins_cp(character_id, amount_cp)
	var p_id := _get_party_id_for_character(character_id)
	EventBus.wallet_deposited.emit(p_id, {"amount_cp": amount_cp, "recipients": [character_id]})
	EventBus.wallet_changed.emit(p_id)


## Even-splits an amount across eligible PCs. Banker's rounding.
## Residual copper goes to the poorest PC among recipients.
func deposit_to_party_even_split(party_id: String, amount_cp: int, active_character_id: String) -> Dictionary:
	var contributors := get_contributors(party_id, active_character_id)
	if contributors.is_empty():
		return {"ok": false, "message": "No eligible recipients", "per_character_deposits_cp": {}}
	if amount_cp <= 0:
		return {"ok": true, "message": "", "per_character_deposits_cp": {}}

	var count: int = contributors.size()
	var base_each: int = amount_cp / count
	var residual: int = amount_cp - (base_each * count)

	# Determine poorest PC among recipients (for residual).
	var poorest_id: String = contributors[0]
	var poorest_wealth: int = CampaignRepository.get_character_wealth_cp(poorest_id)
	for char_id in contributors:
		var w: int = CampaignRepository.get_character_wealth_cp(char_id)
		if w < poorest_wealth:
			poorest_wealth = w
			poorest_id = char_id

	var per_char_deposits := {}
	for char_id in contributors:
		var amount_for_this: int = base_each
		if char_id == poorest_id:
			amount_for_this += residual
		if amount_for_this > 0:
			CampaignRepository.add_coins_cp(char_id, amount_for_this)
		per_char_deposits[char_id] = amount_for_this

	EventBus.wallet_deposited.emit(party_id, {
		"amount_cp": amount_cp,
		"recipients": contributors,
	})
	EventBus.wallet_changed.emit(party_id)

	return {"ok": true, "message": "", "per_character_deposits_cp": per_char_deposits}


## Splits by weighted shares. shares = {char_id: float_weight}.
## Weights need not sum to 1 — they are normalized internally.
## Banker's rounding on each share, residual CP to poorest among recipients.
func deposit_to_party_by_shares(party_id: String, amount_cp: int, shares: Dictionary) -> Dictionary:
	if shares.is_empty() or amount_cp <= 0:
		return {"ok": false, "message": "No shares or zero amount", "per_character_deposits_cp": {}}

	# Filter to eligible PCs only (exclude henchmen even if passed in shares dict).
	var pc_ids := _get_pc_ids(party_id)
	var eligible_shares := {}
	for char_id in shares:
		if char_id in pc_ids:
			eligible_shares[char_id] = float(shares[char_id])

	if eligible_shares.is_empty():
		return {"ok": false, "message": "No eligible recipients in shares", "per_character_deposits_cp": {}}

	# Normalize weights.
	var total_weight := 0.0
	for w in eligible_shares.values():
		total_weight += w
	if total_weight <= 0.0:
		return {"ok": false, "message": "Total weight is zero", "per_character_deposits_cp": {}}

	# Compute each share with banker's rounding.
	var per_char_deposits := {}
	var allocated := 0
	var char_ids: Array = eligible_shares.keys()
	for char_id in char_ids:
		var share_cp: int = roundi(amount_cp * (eligible_shares[char_id] / total_weight))
		per_char_deposits[char_id] = share_cp
		allocated += share_cp

	# Assign residual to poorest among recipients.
	var residual: int = amount_cp - allocated
	if residual != 0:
		var poorest_id: String = char_ids[0]
		var poorest_wealth: int = CampaignRepository.get_character_wealth_cp(poorest_id)
		for char_id in char_ids:
			var w: int = CampaignRepository.get_character_wealth_cp(char_id)
			if w < poorest_wealth:
				poorest_wealth = w
				poorest_id = char_id
		per_char_deposits[poorest_id] += residual

	# Deposit.
	var recipients: Array = []
	for char_id in per_char_deposits:
		var amt: int = per_char_deposits[char_id]
		if amt > 0:
			CampaignRepository.add_coins_cp(char_id, amt)
			recipients.append(char_id)

	EventBus.wallet_deposited.emit(party_id, {
		"amount_cp": amount_cp,
		"recipients": recipients,
	})
	EventBus.wallet_changed.emit(party_id)

	return {"ok": true, "message": "", "per_character_deposits_cp": per_char_deposits}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Returns PC IDs for the given party, excluding henchmen and non-PCs.
func _get_pc_ids(party_id: String) -> Array:
	var all_chars: Array = CampaignRepository.list_party_characters(party_id)
	var pc_ids: Array = []
	for c in all_chars:
		if c.get("character_type", "") == "pc":
			pc_ids.append(c["id"])
	return pc_ids


## Returns the party_id for a character by looking up their party_members record.
func _get_party_id_for_character(character_id: String) -> String:
	CampaignRepository.db.query_with_bindings(
		"SELECT party_id FROM party_members WHERE character_id = ? LIMIT 1",
		[character_id])
	var rows: Array = CampaignRepository.db.query_result
	if rows.is_empty():
		return ""
	return rows[0].get("party_id", "")


## Returns per-denomination coin difference (before - after). Positive = coins spent.
func _compute_coin_diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var diff := {}
	for key in Currency.COIN_KEYS:
		var spent: int = before.get(key, 0) - after.get(key, 0)
		if spent != 0:
			diff[key] = spent
	return diff


## Rollback already-paid deductions by re-adding coins to each affected character.
func _rollback_payments(per_char_deductions: Dictionary) -> void:
	for char_id in per_char_deductions:
		var diff: Dictionary = per_char_deductions[char_id]
		for key in diff:
			var amount: int = diff[key]
			if amount > 0:
				CampaignRepository.add_specific_coins(char_id, key, amount)
