class_name NpcSyndicateMonthlyResolver
extends RefCounted

## Per-month NPC syndicate fast-path resolver (Phase 10B.3 Q8).
##
## RAW source: rules/acore-campaign-hijinks.xml §managing_a_criminal_guild
## §monthly_hijink_income L501-525.
##
## When the syndicate has no PC participation in a given month (or for any
## L1-8 NPC member; per RAW L522 "Hijinks by 9th level or higher characters
## should always be rolled individually"), this resolver substitutes a flat
## per-member-level monthly cp table for the full per-hijink simulation.
##
## RAW L523: "The table already factors in wages, attorneys, bribes, fines,
## and healing for syndicate members who get caught." — meaning the resolver
## emits ONLY the boss treasury deposit; it does NOT write caught_perpetrators
## rows, does NOT debit wages, and does NOT trigger Crime & Punishment.


# RAW L506-517: gp per syndicate member per month, by member level. L9+ is
# always rolled individually per RAW L522 — entries above L8 are absent.
const MONTHLY_HIJINK_INCOME_GP_BY_LEVEL := {
	0: 1,
	1: 5,
	2: 30,
	3: 200,
	4: 425,
	5: 650,
	6: 835,
	7: 1500,
	8: 2000,
}

# RAW henchman monthly wages (data/equipment/provisions_services.json
# `henchman_monthly_gp`, from the ACKS hireling tables). Used for the EXPENSE
# side of the syndicate month (Thief→Syndicate refactor): a syndicate's
# followers "must be paid" (RAW ax_thief_skill_update.xml:51). L1-8 wages are
# already netted into MONTHLY_HIJINK_INCOME_GP_BY_LEVEL (RAW L523 — the income
# table "already factors in wages, attorneys, bribes, fines, and healing"), so
# charging them again here would DOUBLE-COUNT. Only L9+ members — who are NOT in
# the net income table (they roll hijinks individually per RAW L522) — are paid
# from this table.
const HENCHMAN_MONTHLY_WAGE_GP_BY_LEVEL := {
	9: 7250,
	10: 12000,
	11: 32000,
	12: 50000,
	13: 135000,
	14: 350000,
}


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

## Processes one syndicate's monthly fast-path income. Iterates members
## with level 0-8 and status='active', sums the per-level gp from the table,
## converts × 100 to cp, deposits to the boss's wallet. Returns a summary
## dict.
##
## NPC-only routing is the caller's responsibility — the convention is that
## PC syndicates use the per-hijink resolvers via the activity catalog,
## and only when no PC is named on a syndicate row do we drop down to this
## fast path. Mixed syndicates (PC + NPC) can still call this for the NPC
## subset by passing only NPC member ids to a future scope-limited variant;
## v1 processes all L1-8 active members regardless.
##
## L9+ members are SKIPPED here per RAW L522 (logged in the summary). Their
## hijinks must be resolved individually via the per-hijink handlers.
static func process_syndicate_month(syndicate_id: String) -> Dictionary:
	var syndicate := SyndicateRepository.get_syndicate(syndicate_id)
	if syndicate.is_empty():
		return {"summary": "NPC monthly resolver: syndicate not found", "total_cp": 0}
	var boss_id := String(syndicate.get("boss_character_id", ""))
	if boss_id.is_empty():
		return {"summary": "NPC monthly resolver: syndicate has no boss", "total_cp": 0}

	var members: Array = SyndicateRepository.list_members(syndicate_id, true)
	var total_cp: int = 0
	var upkeep_cp: int = 0
	var by_level: Dictionary = {}
	var skipped_l9_plus: int = 0
	for member: Dictionary in members:
		var level: int = int(member.get("level", 0))
		if level >= 9:
			# L9+ earn via individually-rolled hijinks (NOT the net income table,
			# per RAW L522), so they are not auto-paid income here — but they
			# still "must be paid" wages (RAW ax_thief_skill_update.xml:51). This
			# is the only wage charged on the fast path; L1-8 wages are already
			# netted into the income table (RAW L523).
			skipped_l9_plus += 1
			upkeep_cp += int(HENCHMAN_MONTHLY_WAGE_GP_BY_LEVEL.get(level, 0)) * 100
			continue
		var gp_per_member: int = int(MONTHLY_HIJINK_INCOME_GP_BY_LEVEL.get(level, 0))
		if gp_per_member <= 0:
			continue
		var cp_per_member: int = gp_per_member * 100
		total_cp += cp_per_member
		by_level[level] = int(by_level.get(level, 0)) + 1

	# Income first (net L1-8), then the L9+ wage upkeep. Net effect on the boss's
	# PERSONAL wallet = +income - L9+ wages. If the boss can't cover wages,
	# pay_from_character returns ok=false (no partial deduct); v1 records that and
	# the morale/desertion fallout is a documented follow-up.
	if total_cp > 0:
		PartyWallet.deposit_to_character(boss_id, total_cp)
	var upkeep_paid := true
	if upkeep_cp > 0:
		upkeep_paid = bool(PartyWallet.pay_from_character(boss_id, upkeep_cp).get("ok", false))

	return {
		"summary": "Monthly syndicate: +%s income, -%s L9+ wages" % [
			Currency.format_cost(total_cp), Currency.format_cost(upkeep_cp)],
		"syndicate_id": syndicate_id,
		"boss_character_id": boss_id,
		"total_cp": total_cp,
		"upkeep_cp": upkeep_cp,
		"upkeep_paid": upkeep_paid,
		"member_counts_by_level": by_level,
		"skipped_l9_plus_members": skipped_l9_plus,
	}


## Convenience: process every NPC-only syndicate in the named campaign.
## Returns an array of per-syndicate summary dicts.
static func process_campaign_month(campaign_id: String) -> Array:
	var out: Array = []
	for syndicate: Dictionary in SyndicateRepository.list_syndicates_for_campaign(campaign_id):
		var sid := String(syndicate.get("id", ""))
		out.append(process_syndicate_month(sid))
	return out


## Pure-function helper for tests: given a member-level list, return the
## total monthly cp without any side effects. RAW table lookup only.
static func compute_monthly_total_cp(member_levels: Array) -> int:
	var total: int = 0
	for lvl_v in member_levels:
		var lvl: int = int(lvl_v)
		if lvl >= 9 or lvl < 0:
			continue
		total += int(MONTHLY_HIJINK_INCOME_GP_BY_LEVEL.get(lvl, 0)) * 100
	return total


## Pure-function helper for tests: total monthly UPKEEP cp for a member-level
## list. Wages are charged ONLY for L9+ members — L1-8 wages are already netted
## into the income table (RAW L523), so charging them here would double-count.
## No side effects.
static func compute_monthly_upkeep_cp(member_levels: Array) -> int:
	var total: int = 0
	for lvl_v in member_levels:
		var lvl: int = int(lvl_v)
		if lvl < 9:
			continue
		total += int(HENCHMAN_MONTHLY_WAGE_GP_BY_LEVEL.get(lvl, 0)) * 100
	return total
