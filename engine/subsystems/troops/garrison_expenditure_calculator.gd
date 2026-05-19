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
##
## Chaotic domains add **+2 gp to garrison cost** per `ax_domains_of_chaos.xml`
## §exceptions_from_clanholds L86 — the calculator surfaces an additive offset
## that the morale resolver consumes when the domain is chaotic.
##
## 2026-05-16 wiring + cp pass: this calculator is now consumed by the domain
## monthly tick (`domain_handlers._resolve_one_domain`); previously it was UI-
## only. All money fields are cp (1 gp = 100 cp).

const CHAOTIC_GARRISON_OFFSET_CP_PER_FAMILY := 200  # RAW 2 gp per family
const UNIVERSAL_GARRISON_MIN_CP_PER_FAMILY := 200   # RAW 2 gp per family


## Aggregate the garrison spend for [param domain_id] and return the
## breakdown the morale resolver, monthly-tick handler, and Garrison sub-tab
## consume.
##
## Returned dictionary keys:
##   total_paid_cp:                    int — sum of monthly_cost_cp for paid units
##   unpaid_value_cp:                  int — sum of monthly_wage_cp for unpaid units
##                                            (faithful followers, trained militia
##                                            count by gp value per §garrison L229-230)
##   total_value_cp:                   int — total_paid_cp + unpaid_value_cp
##   peasant_families:                 int — domains.peasant_families
##   minimum_cp_per_family:            int — universal minimum + chaotic offset
##   minimum_total_cp:                 int — minimum_cp_per_family × peasant_families
##   cp_per_family_value:              int — total_value_cp / max(1, peasant_families)
##   meets_minimum:                    bool — total_value_cp >= minimum_total_cp
##   cp_below_minimum_per_family:      int — max(0, minimum_cp_per_family - cp_per_family_value)
##   gp_below_minimum_per_family:      int — cp_below_minimum_per_family / 100, ceil
##                                            (RAW morale-modifier granularity is per-gp/family)
##   morale_incentive_bonus:           int — 0/1/2 per §additional_troops table
##   wilderness_under_4gp:             bool — true when classification=wilderness
##                                            and cp_per_family_value < 400
##   chaotic_offset_per_family_cp:     int — 200 for chaotic, 0 otherwise
##   classification:                   String — domain classification (lowercased)
static func compute(domain_id: String) -> Dictionary:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return _empty_result()
	return compute_from_domain(domain)


## Same as [compute] but takes the domain row dict directly. Useful for the
## monthly-tick path that already has the row in hand.
static func compute_from_domain(domain: Dictionary) -> Dictionary:
	if domain.is_empty():
		return _empty_result()
	var domain_id: String = String(domain.get("id", ""))
	# Per db/schema.sql §domains, the classification column is `territory_type`;
	# the project text occasionally calls it "classification" (matching the RAW
	# label) but the SQL column name is territory_type.
	var classification: String = String(domain.get("territory_type", "wilderness")).to_lower()
	var peasants: int = int(domain.get("peasant_families", 0))
	var is_chaotic: bool = bool(domain.get("is_chaotic_domain", false))

	var units: Array = TroopUnitRepository.list_active_for_domain(domain_id) if not domain_id.is_empty() else []
	var total_paid: int = 0
	var unpaid_value: int = 0
	for u in units:
		if not (u is Dictionary):
			continue
		# Garrison-assigned units only contribute toward the garrison cost; the
		# Roster shows on_campaign / available units separately.
		if String(u.get("assignment_kind", "")) != "garrison":
			continue
		var cost: int = int(u.get("monthly_cost_cp", 0))
		if cost > 0:
			total_paid += cost
		else:
			# Unpaid faithful followers / trained militia count by cp value
			# per §garrison L229-230. Use the wage as the by-cp-value figure
			# (supply is RAW-not-counted toward garrison cost).
			unpaid_value += int(u.get("monthly_wage_cp", 0))

	var total_value: int = total_paid + unpaid_value

	var chaotic_offset_per_fam: int = CHAOTIC_GARRISON_OFFSET_CP_PER_FAMILY if is_chaotic else 0
	var minimum_per_family: int = UNIVERSAL_GARRISON_MIN_CP_PER_FAMILY + chaotic_offset_per_fam
	var minimum_total: int = minimum_per_family * peasants

	var cp_per_family: int = (total_value / peasants) if peasants > 0 else 0
	var meets_min: bool = total_value >= minimum_total
	var below_per_family_cp: int = maxi(0, minimum_per_family - cp_per_family)
	# Morale penalty per RAW §monthly_event_modifiers L486: -1 morale per gp/family
	# below the minimum. cp-precision: round-up so any sub-gp shortfall still
	# triggers a 1-point penalty (the player owes a whole gp the moment they
	# fall below).
	var below_per_family_gp_ceil: int = int(ceil(float(below_per_family_cp) / 100.0)) if below_per_family_cp > 0 else 0

	var incentive: int = _morale_incentive_bonus(classification, cp_per_family, UNIVERSAL_GARRISON_MIN_CP_PER_FAMILY)
	# Wilderness "under 4 gp/family" warning per §garrison L233 — 4 gp = 400 cp.
	var wilderness_under_400: bool = classification == "wilderness" and cp_per_family < 400

	return {
		"total_paid_cp": total_paid,
		"unpaid_value_cp": unpaid_value,
		"total_value_cp": total_value,
		"peasant_families": peasants,
		"minimum_cp_per_family": minimum_per_family,
		"minimum_total_cp": minimum_total,
		"cp_per_family_value": cp_per_family,
		"meets_minimum": meets_min,
		"cp_below_minimum_per_family": below_per_family_cp,
		"gp_below_minimum_per_family": below_per_family_gp_ceil,
		"morale_incentive_bonus": incentive,
		"wilderness_under_4gp": wilderness_under_400,
		"chaotic_offset_per_family_cp": chaotic_offset_per_fam,
		"classification": classification,
	}


## Compute the +0/+1/+2 morale incentive band per
## `acore_axioms` §additional_troops L461-464. RAW expresses the thresholds in
## gp/family; cp arithmetic uses 100 cp/family steps.
##
##   Borderlands: +1 at 1 gp/family additional (3 gp/fam total = 300 cp/fam).
##   Wilderness:  +1 at 1 gp/family additional (300 cp/fam total).
##                +2 at 2 gp/family additional (400 cp/fam total).
##   Civilized:   no per §additional_troops bonus.
##
## Computed against the **base 200 cp/family RAW minimum**, since the chaotic
## +200 is a baseline cost, not an incentive.
static func _morale_incentive_bonus(classification: String, cp_per_family: int,
		base_min_cp: int) -> int:
	var additional_cp: int = cp_per_family - base_min_cp
	if additional_cp < 100:  # need at least +1 gp/family above minimum
		return 0
	match classification:
		"borderlands":
			return 1 if additional_cp >= 100 else 0
		"wilderness":
			if additional_cp >= 200:
				return 2
			if additional_cp >= 100:
				return 1
			return 0
		_:
			return 0


static func _empty_result() -> Dictionary:
	return {
		"total_paid_cp": 0,
		"unpaid_value_cp": 0,
		"total_value_cp": 0,
		"peasant_families": 0,
		"minimum_cp_per_family": UNIVERSAL_GARRISON_MIN_CP_PER_FAMILY,
		"minimum_total_cp": 0,
		"cp_per_family_value": 0,
		"meets_minimum": true,
		"cp_below_minimum_per_family": 0,
		"gp_below_minimum_per_family": 0,
		"morale_incentive_bonus": 0,
		"wilderness_under_4gp": false,
		"chaotic_offset_per_family_cp": 0,
		"classification": "",
	}
