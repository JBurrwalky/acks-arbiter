class_name DomainExpenseCalculator
extends RefCounted

## Monthly expense resolver per `acore_axioms_strongholds_and_domains.xml`
## §domain_expenses (L216-254).
##
## Source breakdown (cp per peasant family; RAW originally states gp values):
##   * Garrison      — 2 gp/family universal minimum (§garrison L218, L226)
##                     = 200 cp/family. The 3 gp (Borderlands) and 4 gp
##                     (Wilderness) values from L233 are MORALE INCENTIVES via
##                     §additional_troops L461-464, not hard expense floors.
##                     If the ruler underpays (below 2 gp), each missing
##                     gp/family is also a -1 morale event modifier per
##                     §monthly_event_modifiers L486.
##   * Liturgies     — 1 gp/family = 100 cp/family (§liturgies L235-238).
##                     Adjustable via `domains.liturgy_rate_cp_per_family`.
##   * Maintenance   — 1 gp/family = 100 cp/family (§maintenance L239-242).
##                     Each gp unpaid reduces stronghold_value by 1 gp;
##                     tracking deferred to Phase 1 stronghold subsystem.
##   * Tithes        — 1 gp/family = 100 cp/family (§tithes L243-249).
##                     Even cleric/bladedancer rulers must pay (L248).
##   * Tribute       — owed to a liege per §tribute (Phase 6 surface). cp.
##   * Repression    — cp/family × peasant_families (§repression L510-516).
##                     Militia ineligibility is enforced by the Phase 3 activity
##                     handler, not here.
##
## 2026-05-15 currency-precision pass: all returned amounts are cp.
##
## When `income_gate_active` is true (stronghold < sufficiency), the domain
## still owes its 200 cp/family garrison minimum; liturgy / maintenance / tithe
## / tribute / repression are zeroed because there is no revenue to fund them.
##
## Phase 11D.2 — Clanhold-style garrison cost +2gp (`ax_domains_of_chaos.xml`
## §exceptions_from_clanholds L86): *"Garrison cost is increased by 2gp."*
## When `domains.domain_style == 'clanhold'`, the garrison hard floor becomes
## 4gp/family (400 cp) instead of 2gp/family (200 cp). The same +2gp offset is
## already surfaced by `GarrisonExpenditureCalculator` for the upstream actual-
## paid + morale-incentive computation; this calculator's own clamp must match
## so that the expense ledger reflects the higher floor even when the ruler
## under-pays (RAW says they OWE this much regardless).

const GARRISON_MIN_CP_PER_FAMILY := 200          # RAW: 2 gp per family (civilized)
const CLANHOLD_GARRISON_OFFSET_CP_PER_FAMILY := 200  # RAW L86: +2 gp per family for clanhold
const MAINTENANCE_CP_PER_FAMILY := 100           # RAW: 1 gp per family


## Returns a Dictionary with keys (all cp):
##   total: int
##   garrison: int
##   liturgy: int
##   maintenance: int
##   tithe: int
##   tribute_out: int
##   repression: int
static func calculate_monthly_expenses(
	domain: Dictionary,
	actual_garrison_paid_cp: int,
	income_gate_active: bool
) -> Dictionary:
	var peasants: int = int(domain.get("peasant_families", 0))
	# Phase 11D.2: clanhold-style domains owe an additional 2gp/family per
	# RAW L86. The hard floor shifts from 200 to 400 cp/family; the +2gp is
	# style-driven, not alignment-driven, per gdd-domain-style-and-alignment.md §2.
	var is_clanhold: bool = String(domain.get("domain_style", "civilized")) == "clanhold"
	var per_family_floor: int = GARRISON_MIN_CP_PER_FAMILY + (
		CLANHOLD_GARRISON_OFFSET_CP_PER_FAMILY if is_clanhold else 0
	)
	var garrison_min: int = peasants * per_family_floor
	# RAW universal min applies regardless of sufficiency. Ruler may pay more
	# (incentive bonuses applied separately in the morale resolver).
	var garrison: int = maxi(actual_garrison_paid_cp, garrison_min)

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

	var liturgy_rate: int = int(domain.get("liturgy_rate_cp_per_family", 100))
	var tithe_rate: int = int(domain.get("tithe_rate_cp_per_family", 100))
	var liturgy: int = peasants * liturgy_rate
	var maintenance: int = peasants * MAINTENANCE_CP_PER_FAMILY
	var tithe: int = peasants * tithe_rate
	var tribute_out: int = int(domain.get("tribute_out_owed", 0))
	var repression_rate: int = int(domain.get("repression_cp_per_family_this_month", 0))
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
