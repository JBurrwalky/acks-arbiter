class_name DomainRevenueCalculator
extends RefCounted

## Monthly revenue resolver per `acore_axioms_strongholds_and_domains.xml`
## §domain_revenue (L183-205) and §peasants_and_followers L108-109.
##
## Sources (RAW):
##   * Land     — each hex's 3d3 land value (3-9 gp), plus any land_improvement_gp,
##                paid per peasant family in that hex (§domain_revenue.land L191-193).
##   * Services — 4 gp per peasant family flat (§services L195).
##   * Taxes    — `domains.tax_rate_gp_per_family` per peasant family (RAW default 2gp).
##                Raising taxes harms morale; lowering improves it (§taxes L197-201).
##   * Tribute  — passed in by the caller; the tribute calculator (Phase 6) owns the math.
##
## Income gate (RAW): if stronghold_value < classification_minimum, the domain
## generates NO income and does NOT grow until sufficiency is reached
## (§peasants_and_followers L108-109). Garrison expense still applies — that is
## handled in `DomainExpenseCalculator`, not here.

const SERVICES_GP_PER_FAMILY := 4


## Returns a Dictionary with keys:
##   total: int                — sum of all revenue subcategories (0 if income gate is closed)
##   service: int              — services revenue
##   tax: int                  — tax revenue (using domain.tax_rate_gp_per_family)
##   land: int                 — sum across hexes
##   tribute_in: int           — passed through from caller
##   income_gate_active: bool  — true when stronghold value < classification minimum
static func calculate_monthly_revenue(
	domain: Dictionary,
	hexes: Array,
	stronghold_value_gp: int,
	stronghold_minimum_gp: int,
	tribute_in: int = 0
) -> Dictionary:
	var peasants: int = int(domain.get("peasant_families", 0))

	# RAW income gate (§peasants_and_followers L108-109): no revenue, no growth
	# until the stronghold is sufficient. Garrison still owed (handled in
	# expense calculator).
	if stronghold_value_gp < stronghold_minimum_gp:
		return {
			"total": 0,
			"service": 0,
			"tax": 0,
			"land": 0,
			"tribute_in": 0,
			"income_gate_active": true,
		}

	var tax_rate: int = int(domain.get("tax_rate_gp_per_family", 2))
	var service_revenue: int = peasants * SERVICES_GP_PER_FAMILY
	var tax_revenue: int = peasants * tax_rate

	# Land revenue per hex: peasant families in this hex × (land_value + improvement).
	# Phase 0 has no per-hex peasant-family allocation, so we assume the domain's
	# total peasant_families is distributed evenly across its hexes. When Phase 1+
	# adds per-hex allocation, we can switch to reading hex.peasant_families
	# directly.
	var land_revenue: int = 0
	if hexes.size() > 0:
		var families_per_hex: float = float(peasants) / float(hexes.size())
		for hex: Dictionary in hexes:
			var per_fam: int = int(hex.get("land_value", 5)) + int(hex.get("land_improvement_gp", 0))
			# Banker's round: families_per_hex is fractional; the per-hex slice
			# rounds via the canonical XPAwardCalculator.bankers_round to keep
			# the project's "no exceptions" rounding rule.
			land_revenue += XPAwardCalculator.bankers_round(families_per_hex * float(per_fam))

	var total: int = service_revenue + tax_revenue + land_revenue + tribute_in
	return {
		"total": total,
		"service": service_revenue,
		"tax": tax_revenue,
		"land": land_revenue,
		"tribute_in": tribute_in,
		"income_gate_active": false,
	}
