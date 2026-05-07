class_name DomainExpenseCalculator
extends RefCounted

## Monthly expense resolver per `acore_axioms_strongholds_and_domains.xml`
## §domain_expenses (L216-254).
##
## Source breakdown (gp per peasant family):
##   * Garrison      — 2 gp/family universal minimum (§garrison L218, L226).
##                     The 3 gp (Borderlands) and 4 gp (Wilderness) values from
##                     L233 are MORALE INCENTIVES via §additional_troops L461-464,
##                     not hard expense floors. If the ruler underpays (below 2),
##                     each missing gp/family is also a -1 morale event modifier
##                     per §monthly_event_modifiers L486.
##   * Liturgies     — 1 gp/family (§liturgies L235-238). Adjustable via
##                     `domains.liturgy_rate_gp_per_family`.
##   * Maintenance   — 1 gp/family (§maintenance L239-242). Each gp unpaid
##                     reduces stronghold_value by 1 gp; tracking deferred to
##                     Phase 1 stronghold subsystem.
##   * Tithes        — 1 gp/family (§tithes L243-249). Even cleric/bladedancer
##                     rulers must pay (L248).
##   * Tribute       — owed to a liege per §tribute (Phase 6 surface).
##   * Repression    — gp/family × peasant_families (§repression L510-516).
##                     Militia ineligibility is enforced by the Phase 3 activity
##                     handler, not here.
##
## When `income_gate_active` is true (stronghold < sufficiency), the domain
## still owes its 2 gp/family garrison minimum (per RAW the ruler must always
## pay garrison); liturgy / maintenance / tithe / tribute / repression are
## zeroed because there is no revenue to fund them. This is a deliberate
## simplification — RAW does not say these expenses *literally* go to zero,
## only that the domain "does not generate money." In Phase 0 we assume
## insufficient-stronghold ⇒ ruler defers nonessential spend; the morale
## consequences cascade through the `is_repressed_this_month` and morale
## resolvers as usual.

const GARRISON_MIN_GP_PER_FAMILY := 2


## Returns a Dictionary with keys:
##   total: int
##   garrison: int
##   liturgy: int
##   maintenance: int
##   tithe: int
##   tribute_out: int
##   repression: int
static func calculate_monthly_expenses(
	domain: Dictionary,
	actual_garrison_paid_gp: int,
	income_gate_active: bool
) -> Dictionary:
	var peasants: int = int(domain.get("peasant_families", 0))
	var garrison_min: int = peasants * GARRISON_MIN_GP_PER_FAMILY
	# RAW universal min applies regardless of sufficiency. Ruler may pay more
	# (incentive bonuses applied separately in the morale resolver).
	var garrison: int = maxi(actual_garrison_paid_gp, garrison_min)

	if income_gate_active:
		return {
			"total": garrison,
			"garrison": garrison,
			"liturgy": 0,
			"maintenance": 0,
			"tithe": 0,
			"tribute_out": 0,
			"repression": 0,
		}

	var liturgy_rate: int = int(domain.get("liturgy_rate_gp_per_family", 1))
	var tithe_rate: int = int(domain.get("tithe_rate_gp_per_family", 1))
	var liturgy: int = peasants * liturgy_rate
	var maintenance: int = peasants  # 1 gp/family
	var tithe: int = peasants * tithe_rate
	var tribute_out: int = int(domain.get("tribute_out_owed", 0))
	var repression_rate: int = int(domain.get("repression_gp_per_family_this_month", 0))
	var repression: int = peasants * repression_rate

	var total: int = garrison + liturgy + maintenance + tithe + tribute_out + repression
	return {
		"total": total,
		"garrison": garrison,
		"liturgy": liturgy,
		"maintenance": maintenance,
		"tithe": tithe,
		"tribute_out": tribute_out,
		"repression": repression,
	}
