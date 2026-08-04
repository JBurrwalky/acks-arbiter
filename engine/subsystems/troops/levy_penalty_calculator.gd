class_name LevyPenaltyCalculator
extends RefCounted

## Standing domain penalties for peasants levied into military service.
##
## RAW: rules/daw_armies_recruitment.xml:428-432 (§militia):
##   :428 — "Up to 2 additional peasants per 10 families may be levied."
##   :429 — "For each peasant levied, domain revenue is reduced by one family."
##   :430 — "Levying 1 or fewer militia per 10 families reduces domain morale
##          by 1; levying 2 per 10 families reduces domain morale by 2."
##   :431 — "These penalties remain until the militia is sent home."
##   :432 — "If militia are killed, the loss of domain morale and family
##          revenue is permanent."
##
## ── Who this applies to ─────────────────────────────────────────────────────
##
## Two populations, one rule. Both are peasants pulled off the land:
##
## 1. **Militia** (`source_type='militia'`). The RAW case. These penalties were
##    flagged as an unimplemented Layer-1 gap in `docs/coding_conventions.md`
##    §100 on 2026-07-04 — only the permanent-on-death loss had been built, so
##    a militia levy was free until someone died. Closed here (Jedidiah,
##    2026-08-03).
##
## 2. **Excess tribal warriors** (`source_type='tribal_warrior'` AND
##    `is_excess_levy=1`). A clanhold chieftain may levy 1 warrior per family
##    for free (`ax_domains_of_chaos.xml:398`); `:399` says "any additional
##    levies are treated as militia", which per Jedidiah (2026-08-03) means the
##    militia LIMITS and PENALTIES attach to the excess — not that the excess
##    becomes militia-statted troops. They stay tribal warriors, trained and
##    equipped per tribal custom (`:408`), which is exactly what makes a
##    clanhold dangerous: 1.2 warriors/family of real troops against a standard
##    domain's 0.3/family of conscripts and militia.
##
## Note `ax_domains_of_chaos.xml:36` ("Clanhold chieftains cannot conscript
## peasants or levy militia") still stands — a clanhold cannot raise militia
## UNITS. The excess levy is not militia; it borrows militia's cost.
##
## ── Why the cap is invented, and why it matches RAW anyway ──────────────────
##
## RAW puts no explicit ceiling on the tribal excess, but the economics are
## degenerate without one: each excess warrior costs one family's revenue, so
## at 2 warriors/family a domain earns nothing while still owing expenses, and
## the morale collapse drives families out (taking their warriors with them)
## into rebellion. Jedidiah capped the excess at the standard domain's militia
## allowance — 2 per 10 families — which turns out to be literally RAW's :428
## militia cap. So the "invented" cap is the same number RAW already uses for
## the population this rule is borrowed from. Dial down if play proves it
## strong; the constant below is the single knob.


## RAW :428 — the standing cap on levied peasants, per 10 families. Integer
## division mirrors `LevyMilitiaHandler`'s existing `(peasants / 10) * 2` so
## the two levy paths cannot disagree about the ceiling.
const MAX_LEVIED_PER_10_FAMILIES := 2

## RAW :430 — the two morale bands.
const MORALE_PENALTY_LIGHT := -1
const MORALE_PENALTY_HEAVY := -2
const HEAVY_DENSITY_PER_10 := 2


## The standing cap on levied peasants for a domain of [param peasant_families].
## This is the ceiling for militia AND, separately, for the tribal excess levy —
## each population gets its own allowance, because a clanhold cannot raise
## militia at all (`ax_domains_of_chaos.xml:36`) and a civilized domain has no
## tribal warriors.
static func levy_cap_for_families(peasant_families: int) -> int:
	if peasant_families <= 0:
		return 0
	return (peasant_families / 10) * MAX_LEVIED_PER_10_FAMILIES


## RAW :430 — morale penalty for [param levied] peasants under arms out of
## [param peasant_families]. Density is per 10 families: at or above 2 per 10
## it is -2, any lesser non-zero levy is -1.
##
## The `>= 2 per 10` boundary (rather than `> 1`) mirrors the density test
## `ArmyCasualtyResolver._apply_militia_population_loss` already uses for the
## permanent-on-death version of this same penalty (conventions §100), so the
## temporary and permanent forms agree about where the band changes.
static func morale_penalty(levied: int, peasant_families: int) -> int:
	if levied <= 0:
		return 0
	if peasant_families <= 0:
		return MORALE_PENALTY_HEAVY
	if levied * 10 >= peasant_families * HEAVY_DENSITY_PER_10:
		return MORALE_PENALTY_HEAVY
	return MORALE_PENALTY_LIGHT


## RAW :429 — "For each peasant levied, domain revenue is reduced by one
## family." Returns the number of families to subtract from the revenue-bearing
## population, floored so a domain can never owe more families than it has.
##
## This does NOT touch `domains.peasant_families`: the population is still
## there, it is just under arms instead of working the land. Permanent loss is
## a separate mechanic that fires on death (:432, conventions §100).
static func revenue_family_reduction(levied: int, peasant_families: int) -> int:
	if levied <= 0 or peasant_families <= 0:
		return 0
	return mini(levied, peasant_families)


## Count of peasants currently under arms for [param domain_id] — active
## militia plus active excess-levy tribal warriors. This is the basis for both
## penalties above.
##
## Reads live `troop_units` rows rather than a stored counter so that any path
## which removes a unit (stand-down, battle death, loyalty departure) relieves
## the penalty automatically, which is what :431 "until the militia is sent
## home" requires.
static func levied_peasants_for_domain(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(count), 0) AS total
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND status = 'active'
		  AND (source_type = 'militia'
		       OR (source_type = 'tribal_warrior' AND is_excess_levy = 1))
	""", [domain_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


## Convenience: both penalties for a domain in one read.
## Returns {levied, revenue_family_reduction, morale_penalty}.
static func penalties_for_domain(domain_id: String, peasant_families: int) -> Dictionary:
	var levied: int = levied_peasants_for_domain(domain_id)
	return {
		"levied": levied,
		"revenue_family_reduction": revenue_family_reduction(levied, peasant_families),
		"morale_penalty": morale_penalty(levied, peasant_families),
	}
