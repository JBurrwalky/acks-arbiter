class_name BribeMagistrateHandler
extends RefCounted

## bribe_magistrate handler (Phase 10B.3 UI polish wave).
##
## Singular minor per RAW §bribe_magistrate L1151-1162 + §bribery L279-286.
## Updates `caught_perpetrators.bribe_amount_cp` with the additional bribe
## amount (cp) and debits the briber's wallet.
##
## RAW costs (gp / per bonus tier, × 100 cp):
##   +1 to C&P roll = 5,000 cp (50 gp)
##   +2             = 35,000 cp (350 gp)
##   +3             = 150,000 cp (1500 gp)
##
## Eligibility: requires Bribery proficiency. v1 trusts the UI / launcher to
## have gated; the handler does not re-check the proficiency (a polish pass
## could; see ProficiencyRegistry).
##
## Params:
##   caught_perpetrator_id   — String, REQUIRED.
##   bonus                   — int, 1 / 2 / 3.


const BRIBERY_COST_CP := {
	1:   5_000,   #   50 gp
	2:  35_000,   #  350 gp
	3: 150_000,   # 1500 gp
}


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var caught_id: String = String(params.get("caught_perpetrator_id", ""))
	var bonus: int = int(params.get("bonus", 0))
	var briber_id: String = String(state.get("character_id", ""))

	if caught_id.is_empty() or briber_id.is_empty():
		return {"summary": "bribe_magistrate failed: caught_perpetrator_id and character_id required"}
	if not (bonus in [1, 2, 3]):
		return {"summary": "bribe_magistrate failed: bonus must be 1, 2, or 3"}

	var row := SyndicateRepository.get_caught(caught_id)
	if row.is_empty():
		return {"summary": "bribe_magistrate failed: caught_perpetrators row not found"}
	if row.get("verdict") != null:
		return {"summary": "bribe_magistrate failed: trial already resolved"}

	var cost_cp: int = int(BRIBERY_COST_CP.get(bonus, 0))
	# Debit the briber's wallet. PartyWallet returns {ok, message, ...}.
	var pay: Dictionary = PartyWallet.pay_from_character(briber_id, cost_cp)
	if not bool(pay.get("ok", false)):
		return {
			"summary": "bribe_magistrate failed: insufficient funds (need %s)" % Currency.format_cost(cost_cp),
		}

	# Accumulate bribe into the row. Two bribes (e.g., +1 then +2) sum.
	var existing_cp: int = int(row.get("bribe_amount_cp", 0))
	SyndicateRepository.update_caught(caught_id, {
		"bribe_amount_cp": existing_cp + cost_cp,
	})
	return {
		"summary": "Bribed magistrate for +%d on Crime & Punishment (%s)" % [bonus, Currency.format_cost(cost_cp)],
		"presentation": {"type": "toast", "text": "Bribe paid: +%d on verdict roll" % bonus},
	}


static func _read_params(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("params_json", "")
	if raw == null:
		return {}
	var json_str: String = str(raw)
	if json_str.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}
