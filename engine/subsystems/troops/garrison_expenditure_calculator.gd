class_name GarrisonExpenditureCalculator
extends RefCounted

## Aggregates the monthly garrison expenditure for a domain and compares it
## against the RAW thresholds:
##
##   * **2 gp/family universal minimum** per `acore_axioms_strongholds_and_domains.xml`
##     §garrison L218 / L226-227 ("A ruler must spend at least 2gp per peasant
##     family per month on troops"). Falling below this threshold reduces
##     base morale by -1 per gp/family below per §monthly_event_modifiers L486.
##
##   * **Morale-incentive band** per §additional_troops L461-464:
##       Borderlands: +1 base morale at 1gp/family of additional troops
##                    above the 2gp/family minimum (i.e. 3gp/fam total).
##       Wilderness:  +1 base morale at 1gp/family additional (3gp/fam total),
##                    +2 at 2gp/family additional (4gp/fam total).
##
##   * **Wilderness reduction warning** per §garrison L233 — wilderness must
##     maintain at least 4gp/family or base morale is reduced (the
##     classification penalty already covers the baseline). Surfaced as a
##     wilderness_under_threshold flag for UI hint, not a hard expense floor.
##
## Per §garrison L228-231, the following count toward the gp value of garrison
## expense even when not paid:
##   * scutage paid                       — covered by deferred ledger today
##   * faithful followers (cleric/bladedancer) — wages_required=false in template
##   * trained, equipped militia          — source_type='militia', is_trained=1
##   * troops provided by a lord as Favor — covered by Phase 6+ Favors layer
## Phase 5 covers (a) and (b) directly via monthly_cost_gp + the by-gp-value
## column for unpaid faithful/militia; (c)/(d) ride along.
##
## Chaotic domains add **+2 gp to garrison cost** per `ax_domains_of_chaos.xml`
## §exceptions_from_clanholds L86 — the calculator surfaces an additive offset
## that the morale resolver consumes when the domain is chaotic.

const CHAOTIC_GARRISON_OFFSET_GP_PER_FAMILY := 2


## Aggregate the garrison spend for [param domain_id] and return the
## breakdown the morale resolver and Garrison sub-tab consume.
##
## Returned dictionary keys:
##   total_paid_gp:                    int — sum of monthly_cost_gp for paid units
##   unpaid_value_gp:                  int — sum of monthly_wage_gp for unpaid units
##                                            (faithful, militia counted by gp value)
##   total_value_gp:                   int — total_paid_gp + unpaid_value_gp
##   peasant_families:                 int — domains.peasant_families
##   minimum_gp_per_family:            int — 2 (universal minimum)
##   minimum_total_gp:                 int — 2 × peasant_families (+ chaotic offset)
##   gp_per_family_value:              int — total_value_gp / max(1, peasant_families)
##   meets_minimum:                    bool — total_value_gp >= minimum_total_gp
##   gp_below_minimum_per_family:      int — max(0, 2 - gp_per_family_value)
##   morale_incentive_bonus:           int — 0/1/2 per §additional_troops table
##   wilderness_under_4gp:             bool — true when classification=wilderness
##                                            and gp_per_family_value < 4
##   chaotic_offset_per_family:        int — 2 for chaotic, 0 otherwise
##   classification:                   String — domain classification (lowercased)
static func compute(domain_id: String) -> Dictionary:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return _empty_result()
	# Per db/schema.sql §domains, the classification column is `territory_type`;
	# the project text occasionally calls it "classification" (matching the RAW
	# label) but the SQL column name is territory_type.
	var classification: String = String(domain.get("territory_type", "wilderness")).to_lower()
	var peasants: int = int(domain.get("peasant_families", 0))
	var is_chaotic: bool = bool(domain.get("is_chaotic_domain", false))

	var units: Array = TroopUnitRepository.list_active_for_domain(domain_id)
	var total_paid: int = 0
	var unpaid_value: int = 0
	for u in units:
		if not (u is Dictionary):
			continue
		# Garrison-assigned units only contribute toward the garrison cost; the
		# Roster shows on_campaign / available units separately.
		if String(u.get("assignment_kind", "")) != "garrison":
			continue
		var cost: int = int(u.get("monthly_cost_gp", 0))
		if cost > 0:
			total_paid += cost
		else:
			# Unpaid faithful followers / trained militia count by gp value
			# per §garrison L229-230. Use the wage as the by-gp-value figure
			# (supply is RAW-not-counted toward garrison cost).
			unpaid_value += int(u.get("monthly_wage_gp", 0))

	var total_value: int = total_paid + unpaid_value

	var chaotic_offset_per_fam: int = CHAOTIC_GARRISON_OFFSET_GP_PER_FAMILY if is_chaotic else 0
	var minimum_per_family: int = 2 + chaotic_offset_per_fam
	var minimum_total: int = minimum_per_family * peasants

	var gp_per_family: int = (total_value / peasants) if peasants > 0 else 0
	var meets_min: bool = total_value >= minimum_total
	var below_per_family: int = maxi(0, minimum_per_family - gp_per_family)

	var incentive: int = _morale_incentive_bonus(classification, gp_per_family, minimum_per_family)
	var wilderness_under_4: bool = classification == "wilderness" and gp_per_family < 4

	return {
		"total_paid_gp": total_paid,
		"unpaid_value_gp": unpaid_value,
		"total_value_gp": total_value,
		"peasant_families": peasants,
		"minimum_gp_per_family": minimum_per_family,
		"minimum_total_gp": minimum_total,
		"gp_per_family_value": gp_per_family,
		"meets_minimum": meets_min,
		"gp_below_minimum_per_family": below_per_family,
		"morale_incentive_bonus": incentive,
		"wilderness_under_4gp": wilderness_under_4,
		"chaotic_offset_per_family": chaotic_offset_per_fam,
		"classification": classification,
	}


## Compute the +0/+1/+2 morale incentive band per
## `acore_axioms` §additional_troops L461-464.
##
##   Borderlands: +1 at 1gp/family additional troops above 2gp/fam minimum (3gp/fam total).
##                +1 is the cap; further extra spend yields no morale bonus per RAW.
##
##   Wilderness:  +1 at 1gp/family additional (3gp/fam total).
##                +2 at 2gp/family additional (4gp/fam total).
##
##   Civilized:   no per §additional_troops bonus (Civilized has no entry).
##
## [param minimum_per_family] is the chaotic-adjusted minimum (2 or 4 gp/fam)
## but the §additional_troops bonuses are computed against the **base 2 gp/fam
## RAW minimum**, since the chaotic +2 is a baseline cost, not an incentive.
static func _morale_incentive_bonus(classification: String, gp_per_family: int,
		_minimum_per_family: int) -> int:
	var additional: int = gp_per_family - 2
	if additional <= 0:
		return 0
	match classification:
		"borderlands":
			return 1 if additional >= 1 else 0
		"wilderness":
			if additional >= 2:
				return 2
			if additional >= 1:
				return 1
			return 0
		_:
			return 0


static func _empty_result() -> Dictionary:
	return {
		"total_paid_gp": 0,
		"unpaid_value_gp": 0,
		"total_value_gp": 0,
		"peasant_families": 0,
		"minimum_gp_per_family": 2,
		"minimum_total_gp": 0,
		"gp_per_family_value": 0,
		"meets_minimum": true,
		"gp_below_minimum_per_family": 0,
		"morale_incentive_bonus": 0,
		"wilderness_under_4gp": false,
		"chaotic_offset_per_family": 0,
		"classification": "",
	}
