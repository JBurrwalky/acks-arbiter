class_name HireAttorneyHandler
extends RefCounted

## hire_attorney handler (Phase 10B.3 UI polish wave).
##
## Singular minor per RAW §hire_attorney L1164-1173 + §attorney L269-277.
## Sets `caught_perpetrators.attorney_rank` to the hired rank (1, 2, or 3)
## and debits the hiring character's wallet.
##
## RAW costs:
##   rank 1 =  25 gp =   2,500 cp
##   rank 2 =  50 gp =   5,000 cp
##   rank 3 = 100 gp =  10,000 cp
##
## Per RAW L1171: may be hired for self OR for another caught perpetrator.
## v1 trusts the launcher to bind the correct briber+target pair.
##
## Params:
##   caught_perpetrator_id   — String, REQUIRED.
##   rank                    — int, 1 / 2 / 3.


const ATTORNEY_COST_CP := {
	1:  2_500,   #  25 gp
	2:  5_000,   #  50 gp
	3: 10_000,   # 100 gp
}


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var params: Dictionary = _read_params(state)
	var caught_id: String = String(params.get("caught_perpetrator_id", ""))
	var rank: int = int(params.get("rank", 0))
	var payer_id: String = String(state.get("character_id", ""))

	if caught_id.is_empty() or payer_id.is_empty():
		return {"summary": "hire_attorney failed: caught_perpetrator_id and character_id required"}
	if not (rank in [1, 2, 3]):
		return {"summary": "hire_attorney failed: rank must be 1, 2, or 3"}

	var row := SyndicateRepository.get_caught(caught_id)
	if row.is_empty():
		return {"summary": "hire_attorney failed: caught_perpetrators row not found"}
	if row.get("verdict") != null:
		return {"summary": "hire_attorney failed: trial already resolved"}

	# RAW: attorney_rank is set, not accumulated. Hiring a higher-rank attorney
	# replaces the lower. Hiring a lower one over a higher is a downgrade —
	# v1 accepts the new value (the player presumably wants the action) but
	# refunds nothing.
	var cost_cp: int = int(ATTORNEY_COST_CP.get(rank, 0))
	# PartyWallet returns {ok, message, ...}.
	var pay: Dictionary = PartyWallet.pay_from_character(payer_id, cost_cp)
	if not bool(pay.get("ok", false)):
		return {
			"summary": "hire_attorney failed: insufficient funds (need %s)" % Currency.format_cost(cost_cp),
		}

	SyndicateRepository.update_caught(caught_id, {"attorney_rank": rank})
	return {
		"summary": "Hired attorney rank %d (%s) for caught perpetrator" % [rank, Currency.format_cost(cost_cp)],
		"presentation": {"type": "toast", "text": "Attorney rank %d hired" % rank},
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
