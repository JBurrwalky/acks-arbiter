class_name DomainRevenueCalculator
extends RefCounted

## Monthly revenue resolver per `acore_axioms_strongholds_and_domains.xml`
## §domain_revenue (L183-205) and §peasants_and_followers L108-109.
##
## Sources (RAW):
##   * Land     — each hex's 3d3 land value (3-9 gp), plus any land_improvement_level
##                level (0-3, +1 gp/family each), paid per peasant family in
##                that hex (§domain_revenue.land L191-193).
##   * Services — 4 gp per peasant family flat (§services L195) = 400 cp.
##   * Taxes    — `domains.tax_rate_cp_per_family` per peasant family (RAW default 2gp = 200cp).
##                Raising taxes harms morale; lowering improves it (§taxes L197-201).
##   * Tribute  — passed in by the caller; the tribute calculator (Phase 6) owns the math.
##
## 2026-05-15 currency-precision pass: all amounts are cp (1 gp = 100 cp).
## RAW values originally stated in gp are × 100 in this calculator.
##
## Income gate (RAW): if stronghold_value < classification_minimum, the domain
## generates NO income and does NOT grow until sufficiency is reached
## (§peasants_and_followers L108-109). Garrison expense still applies — that is
## handled in `DomainExpenseCalculator`, not here.
##
## Phase 11D.2 — Clanhold-style land halving (`ax_domains_of_chaos.xml`
## §exceptions_from_clanholds L79): *"Once population exceeds 125 peasant
## families per 6-mile hex, excess peasant families provide only half normal
## land revenue."* When `domains.domain_style == 'clanhold'`, the per-hex land
## revenue is computed as
##   floor(min(families_in_hex, 125) × land_value_cp) +
##   floor(max(0, families_in_hex - 125) × land_value_cp / 2)
## per hex. The halving applies regardless of alignment — it is a style-driven
## mechanic per gdd-domain-style-and-alignment.md §2.

const SERVICES_CP_PER_FAMILY := 400  # RAW: 4 gp per family
const CLANHOLD_LAND_HALVING_THRESHOLD_PER_HEX := 125  # RAW L79: families/hex over this halve revenue


## Returns a Dictionary with keys:
##   total: int                — sum of all revenue subcategories in cp (0 if income gate is closed)
##   service: int              — services revenue in cp
##   tax: int                  — tax revenue in cp (using domain.tax_rate_cp_per_family)
##   land: int                 — sum across hexes in cp
##   tribute_in: int           — passed through from caller in cp
##   income_gate_active: bool  — true when stronghold value < classification minimum
## [param levied_peasants] is the number of peasants currently under arms —
## militia plus excess-levy tribal warriors, from
## `LevyPenaltyCalculator.levied_peasants_for_domain`. RAW
## `daw_armies_recruitment.xml:429`: "For each peasant levied, domain revenue is
## reduced by one family." They still exist (`peasant_families` is unchanged);
## they are just carrying spears instead of working the land, so they drop out
## of the revenue-bearing count for service, tax AND land alike — ":429" says
## "domain revenue", not one stream of it.
##
## Defaults to 0 so callers that predate the levy-penalty model (tests, the
## scenario runners) are unaffected.
static func calculate_monthly_revenue(
	domain: Dictionary,
	hexes: Array,
	stronghold_value_cp: int,
	stronghold_minimum_cp: int,
	tribute_in_cp: int = 0,
	levied_peasants: int = 0
) -> Dictionary:
	var all_families: int = int(domain.get("peasant_families", 0))
	var revenue_family_loss: int = LevyPenaltyCalculator.revenue_family_reduction(
		levied_peasants, all_families)
	var peasants: int = all_families - revenue_family_loss

	# RAW income gate (§peasants_and_followers L108-109): no revenue, no growth
	# until the stronghold is sufficient. Garrison still owed (handled in
	# expense calculator).
	if stronghold_value_cp < stronghold_minimum_cp:
		return {
			"total": 0,
			"service": 0,
			"tax": 0,
			"land": 0,
			"tribute_in": 0,
			"income_gate_active": true,
			# Same keys as the normal path so consumers need not branch. The
			# levy penalty is moot here — there is no revenue to reduce — but
			# the count is still true and the morale penalty still applies.
			"levied_peasants": levied_peasants,
			"revenue_families_lost_to_levy": revenue_family_loss,
		}

	var tax_rate_cp: int = int(domain.get("tax_rate_cp_per_family", 200))
	var service_revenue: int = peasants * SERVICES_CP_PER_FAMILY
	var tax_revenue: int = peasants * tax_rate_cp

	# Land revenue per hex: peasant families in this hex × (land_value + improvement) gp,
	# scaled to cp (× 100). land_value and land_improvement_level (a level 0-3,
	# NOT a cp magnitude — the suffix is legacy) both contribute as gp/family.
	# Phase 0 has no per-hex peasant-family allocation, so we assume the domain's
	# total peasant_families is distributed evenly across its hexes. When Phase 1+
	# adds per-hex allocation, we can switch to reading hex.peasant_families
	# directly.
	#
	# Phase 11D.2: clanhold-style domains halve land revenue from families above
	# the 125/hex threshold per RAW L79.
	var is_clanhold: bool = String(domain.get("domain_style", "civilized")) == "clanhold"
	var land_revenue: int = 0
	if hexes.size() > 0:
		var families_per_hex: float = float(peasants) / float(hexes.size())
		for hex: Dictionary in hexes:
			var per_fam_cp: int = (int(hex.get("land_value", 5)) + int(hex.get("land_improvement_level", 0))) * 100
			var hex_cp: float
			if is_clanhold and families_per_hex > float(CLANHOLD_LAND_HALVING_THRESHOLD_PER_HEX):
				# Full-rate portion: first 125 families/hex.
				var full_rate: float = float(CLANHOLD_LAND_HALVING_THRESHOLD_PER_HEX) * float(per_fam_cp)
				# Halved portion: families beyond 125 contribute per_fam_cp/2.
				# Banker's-round the half-rate at the per-hex level to honor the
				# project-wide "round half to even" convention.
				var excess_families: float = families_per_hex - float(CLANHOLD_LAND_HALVING_THRESHOLD_PER_HEX)
				var half_rate: float = excess_families * float(per_fam_cp) / 2.0
				hex_cp = full_rate + half_rate
			else:
				hex_cp = families_per_hex * float(per_fam_cp)
			# Banker's round: families_per_hex is fractional; the per-hex slice
			# rounds via the canonical XPAwardCalculator.bankers_round to keep
			# the project's "no exceptions" rounding rule.
			land_revenue += XPAwardCalculator.bankers_round(hex_cp)

	var total: int = service_revenue + tax_revenue + land_revenue + tribute_in_cp
	return {
		"total": total,
		"service": service_revenue,
		"tax": tax_revenue,
		"land": land_revenue,
		"tribute_in": tribute_in_cp,
		"income_gate_active": false,
		# Surfaced so the Treasury sub-tab and the ledger can explain a shortfall
		# that has no expense line behind it — the families simply stopped
		# earning. 0 whenever nothing is levied.
		"levied_peasants": levied_peasants,
		"revenue_families_lost_to_levy": revenue_family_loss,
	}
