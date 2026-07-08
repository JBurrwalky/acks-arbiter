class_name FactionLedgerResolver
extends RefCounted

## The organization abstract monthly ledger (gdd-faction-framework.md §6.6 —
## FF-2.2). Resolves ONE org faction's monthly income and returns the mutation
## (the caller — FactionAI — persists the new treasury and applies the negative-
## treasury RAW consequences). Income first, then the caller selects an action
## within means (the ruler planner's post-resolution pattern).
##
## Two income regimes (§6.6):
##  - PASSTHROUGH (syndicate / merchant_guild): treasury already resolved by
##    NpcSyndicateMonthlyResolver / VentureMonthlyResolver — this resolver does
##    NOT re-resolve and does NOT accrue. It only reports the current treasury so
##    the affordability gate has a number.
##  - ¼-WAGES (everything else): monthly net profit = ¼ × Σ(members' monthly
##    wages), banker's rounding, accruing in treasury_gp. Wages come from the
##    Henchman Monthly Fee table (OrgTypeCatalog). member_count_abstract prices
##    through the RAW criminal-guild level-mix pyramid. The faithful of
##    holy_order/knightly_order are UNPAID (§2.5) — their abstract head-count
##    contributes 0 to the wage sum.
##
## Deterministic — pure arithmetic over persisted rows, no RNG.

## Org types whose member_count_abstract are the unpaid faithful (§2.5, §6.6):
## they contribute 0 to the ¼-wages sum. Named leveled members still count.
const UNPAID_ABSTRACT_TYPES: Array = ["holy_order", "knightly_order"]


## Resolve one org faction's month. [param faction] is the raw factions row.
## [param tithe_income_gp] is the temple's apportioned tithe share for the month
## (FF-2.3; 0 for non-temples and for temples with no share). Returns:
##   {
##     faction_id, type, passthrough: bool,
##     wage_sum_gp: float, quarter_net_gp: int, tithe_income_gp: int,
##     total_income_gp: int, treasury_before: int, treasury_after: int,
##     went_negative: bool, months_of_reserve: float,
##   }
## Pure calculation + a single treasury write via update_faction; the caller
## owns the negative-treasury consequences and the action turn.
static func resolve_month(faction: Dictionary, tithe_income_gp: int = 0) -> Dictionary:
	var faction_id: String = String(faction.get("id", ""))
	var type: String = String(faction.get("faction_type", ""))
	var treasury_before: int = int(faction.get("treasury_gp", 0))

	if OrgTypeCatalog.is_passthrough_income(type):
		# §6.6: syndicate/merchant_guild treasuries are resolved elsewhere — do
		# not accrue or re-resolve. Report the current treasury for the gate.
		return {
			"faction_id": faction_id, "type": type, "passthrough": true,
			"wage_sum_gp": 0.0, "quarter_net_gp": 0, "tithe_income_gp": 0,
			"total_income_gp": 0, "treasury_before": treasury_before,
			"treasury_after": treasury_before, "went_negative": treasury_before < 0,
			"months_of_reserve": _months_of_reserve(treasury_before, 0.0),
		}

	var wage_sum_gp: float = _wage_sum_gp(faction)
	var quarter_net_gp: int = MathUtils.bankers_round(0.25 * wage_sum_gp)
	var tithe_gp: int = maxi(0, tithe_income_gp)
	var total_income: int = quarter_net_gp + tithe_gp
	var treasury_after: int = treasury_before + total_income

	return {
		"faction_id": faction_id, "type": type, "passthrough": false,
		"wage_sum_gp": wage_sum_gp, "quarter_net_gp": quarter_net_gp,
		"tithe_income_gp": tithe_gp, "total_income_gp": total_income,
		"treasury_before": treasury_before, "treasury_after": treasury_after,
		"went_negative": treasury_after < 0,
		"months_of_reserve": _months_of_reserve(treasury_after, wage_sum_gp),
	}


## The Σ(monthly wages) for a faction: named (materialized) members priced by
## their real class level + abstract head-count priced through the RAW mix
## (0 for the unpaid faithful of holy/knightly orders).
static func _wage_sum_gp(faction: Dictionary) -> float:
	var faction_id: String = String(faction.get("id", ""))
	var type: String = String(faction.get("faction_type", ""))
	var total: float = 0.0

	# Named/materialized members (leader, officer, any joined PCs/NPCs).
	for m in CampaignRepository.ff_list_members(faction_id):
		var npc_id: String = String((m as Dictionary).get("npc_id", ""))
		if npc_id.is_empty():
			continue
		var status: String = String((m as Dictionary).get("status", "member"))
		if status in ["expelled", "left", "deceased"]:
			continue
		var ch: Dictionary = CampaignRepository.get_character(npc_id)
		if ch.is_empty():
			continue
		total += float(OrgTypeCatalog.wage_gp_for_level(int(ch.get("level", 1))))

	# Abstract rank-and-file (unless they are the unpaid faithful).
	if not UNPAID_ABSTRACT_TYPES.has(type):
		total += OrgTypeCatalog.abstract_wage_sum_gp(int(faction.get("member_count_abstract", 0)))
	return total


## Months of reserve = treasury / monthly expense estimate. Expense estimate is
## the ¾ of wages that the ¼ rule assumes is paid out (the "expenses already
## paid" side of §6.6), or a floor of 1 gp to avoid divide-by-zero. Feeds the
## §6.6 "under 3 months' expenses -> survive" auto-gate.
static func _months_of_reserve(treasury: int, wage_sum_gp: float) -> float:
	var monthly_expense: float = maxf(1.0, 0.75 * wage_sum_gp)
	return float(treasury) / monthly_expense
