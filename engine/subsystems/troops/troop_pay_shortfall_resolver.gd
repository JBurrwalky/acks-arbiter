class_name TroopPayShortfallResolver
extends RefCounted

## Decides WHICH troop units went unpaid this month when a domain could not
## cover its whole wage bill — the money half of the RAW "going without pay for
## a month" calamity (`rules/ax_domains_of_chaos.xml:455`,
## `rules/daw_armies_recruitment.xml:98`). The loyalty roll itself belongs to
## `UnitLoyaltyResolver`; this class never rolls anything.
##
## ── Why this exists at all ──────────────────────────────────────────────────
##
## The project pays troops **in aggregate**. Wages are summed into
## `GarrisonExpenditureCalculator` / `DomainExpenseCalculator` and settled as
## one number against the domain treasury; no unit is ever individually paid,
## and there is no arrears column anywhere. So nothing in the data model can
## say "unit X went unpaid" — which is exactly what the RAW calamity needs.
##
## Per Jedidiah (2026-08-01) the answer is NOT to build per-unit arrears
## tracking. Pay stays aggregate; when the aggregate falls short, this resolver
## designates the unpaid units **ex post facto** from the shortfall. Nothing on
## the payment path changes, and no migration is needed.
##
## ── The designation rule ────────────────────────────────────────────────────
##
## Cheapest-first (lowest `troop_units.monthly_wage_cp`), accumulating until the
## designated wages cover the shortfall. In fiction: a ruler who cannot make
## payroll protects the units they paid most dearly for and tells the cheap
## levies to wait. Mechanically it is the harshest reading — covering a given
## shortfall with the cheapest units puts the LARGEST number of units in front
## of a loyalty roll — which is the right default for a rule whose whole point
## is that stiffing your soldiers is dangerous.
##
## **`monthly_wage_cp` is the whole unit's monthly wage, not per soldier.**
## Every mint site multiplies before storing (`levy_tribal_warriors.gd:166`,
## `conscript_troops.gd:77`), so a 120-strong unit at 5 gp/soldier stores
## 60,000 cp. "Cheapest" therefore means the cheapest UNIT, which is what the
## ruler is actually choosing between. Do not confuse it with `monthly_cost_cp`,
## the denormalized wage + specialist + 4 × weekly supply figure the garrison
## calculator sums — supply is not pay, and RAW's calamity is about pay.
##
## ── The player-override seam ────────────────────────────────────────────────
##
## `resolve_for_domain` takes an optional `designator` Callable with the
## signature `(shortfall_cp: int, units: Array) -> Array` returning unit ids.
## NPC-owned domains never supply one and always get cheapest-first (Jedidiah:
## no player input on NPC domains). When the player-facing "choose who goes
## unpaid" option is built, it passes its own Callable at the DomainHandlers
## call site — one argument, no restructuring. A designation that does not
## cover the shortfall is topped up cheapest-first rather than rejected, so a
## partial player choice degrades to the default instead of silently under-
## designating (see `_apply_designator`).
##
## ── What is in the wage bill ────────────────────────────────────────────────
##
## Every ACTIVE unit assigned to the domain with both `monthly_wage_cp > 0` and
## `monthly_cost_cp > 0`, regardless of `assignment_kind`. Two deliberate
## choices there:
##
## * **Not garrison-only.** `GarrisonExpenditureCalculator` filters to
##   `assignment_kind = 'garrison'` because it computes the RAW garrison
##   *morale threshold*, not the payroll. Levied tribal warriors are minted
##   `assignment_kind = 'available'` (`levy_tribal_warriors.gd:187`) and
##   `ExtractionResistanceRouter` flips garrison units to `on_campaign` and
##   back for the length of a muster. Filtering on it would make this rule a
##   no-op for the only source type that can currently roll, and would make the
##   calamity flicker on and off with musters. (Written while tribal warriors
##   were the only source type that rolled; the filter would now break the rule
##   for every campaigning unit rather than just for them.)
##
## * **`monthly_cost_cp > 0` is the "actually on the payroll" test.** Units at
##   cost 0 are the RAW by-value-only cases the garrison calculator already
##   separates out — faithful cleric/bladedancer followers (who per
##   `daw_armies_recruitment.xml:481` do not make calamity loyalty rolls at all)
##   and trained militia counted toward garrison expense without money changing
##   hands (`acore_axioms` §garrison L229-230). There is no pay for them to go
##   without.
##
## The bill spans ALL source types, because who a ruler can afford is a question
## about the whole roster: a clanhold with one tribal unit and twenty mercenaries
## should weigh all twenty-one. That separation paid off on 2026-08-03 when the
## roll was extended from tribal warriors to every source type RAW grants it to
## — the change landed entirely in `DomainHandlers._tick_unit_loyalty` and
## `UnitLoyaltyResolver`, and this class did not move at all.

## Label reported in the result dict when no custom designator was supplied.
const DESIGNATOR_CHEAPEST_FIRST := "cheapest_first"
const DESIGNATOR_CUSTOM := "custom"
const DESIGNATOR_CUSTOM_TOPPED_UP := "custom_topped_up"


## Resolve this month's unpaid designation for [param domain_id].
##
## [param funds_available_cp] is the money the domain could bring to bear on
## wages this month. `DomainHandlers` passes `treasury_cp + revenue.total` —
## troop pay takes first claim on it. That priority is not invented here:
## `DomainExpenseCalculator.calculate_monthly_expenses` already zeroes liturgy,
## maintenance, tithe, tribute and repression under the income gate while
## keeping the garrison line, so garrison-before-everything is the established
## expense ordering in this codebase, and it is the conservative reading — the
## calamity fires only when the domain genuinely could not pay its soldiers out
## of everything it had.
##
## [param designator] optional `(shortfall_cp: int, units: Array) -> Array`
## override; see the class docstring.
##
## Returns:
##   {domain_id, wage_bill_cp, funds_available_cp, shortfall_cp,
##    unpaid_unit_ids: Array[String], unpaid_wage_cp, considered_unit_ids,
##    designator}
static func resolve_for_domain(domain_id: String, funds_available_cp: int,
		designator: Callable = Callable()) -> Dictionary:
	var units: Array = wage_requiring_units(domain_id)
	var wage_bill: int = 0
	var considered: Array[String] = []
	for u in units:
		wage_bill += int((u as Dictionary).get("monthly_wage_cp", 0))
		considered.append(String((u as Dictionary).get("id", "")))

	# Treasury is unclamped and can carry a deficit forward (see
	# DomainHandlers._save_domain), so a domain deep in the hole brings 0 to
	# payroll rather than a negative amount that would inflate the shortfall
	# past the bill.
	var funds: int = maxi(0, funds_available_cp)
	var shortfall: int = maxi(0, wage_bill - funds)

	var unpaid: Array = []
	var label: String = DESIGNATOR_CHEAPEST_FIRST
	if shortfall > 0:
		var applied: Dictionary = _apply_designator(designator, shortfall, units)
		unpaid = applied["unit_ids"]
		label = String(applied["designator"])

	var unpaid_wage: int = 0
	for u in units:
		if unpaid.has(String((u as Dictionary).get("id", ""))):
			unpaid_wage += int((u as Dictionary).get("monthly_wage_cp", 0))

	return {
		"domain_id": domain_id,
		"wage_bill_cp": wage_bill,
		"funds_available_cp": funds,
		"shortfall_cp": shortfall,
		"unpaid_unit_ids": unpaid,
		"unpaid_wage_cp": unpaid_wage,
		"considered_unit_ids": considered,
		"designator": label,
	}


## Every active unit on [param domain_id]'s payroll this month, cheapest first.
## Rows carry the full `troop_units` columns a designator needs to choose.
static func wage_requiring_units(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	# ORDER BY makes the default designation deterministic before anyone sorts:
	# equal wages tie-break on id so two units minted in the same levy chunk
	# always designate in the same order across runs.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, source_type, troop_type, race, count,
		       monthly_wage_cp, monthly_cost_cp, assignment_kind
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND status = 'active'
		  AND monthly_wage_cp > 0
		  AND monthly_cost_cp > 0
		ORDER BY monthly_wage_cp ASC, id ASC
	""", [domain_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## The default designation: cheapest unit first until the designated wages
## cover [param shortfall_cp]. Returns unit ids.
##
## Termination is guaranteed by the caller's arithmetic — `shortfall_cp` is
## `wage_bill - funds` clamped at 0, so it can never exceed the sum of the
## wages on offer. A domain that can pay nothing designates every unit.
static func designate_cheapest_first(shortfall_cp: int, units: Array) -> Array:
	var out: Array[String] = []
	if shortfall_cp <= 0:
		return out
	var ordered: Array = units.duplicate()
	ordered.sort_custom(_cheaper_unit_first)
	var covered: int = 0
	for u in ordered:
		if covered >= shortfall_cp:
			break
		var unit_id: String = String((u as Dictionary).get("id", ""))
		if unit_id.is_empty():
			continue
		out.append(unit_id)
		covered += int((u as Dictionary).get("monthly_wage_cp", 0))
	return out


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Run [param designator] (or the cheapest-first default), then validate: drop
## ids that aren't on this domain's payroll, drop duplicates, and top up
## cheapest-first if the picks don't cover the shortfall. Returns
## {unit_ids: Array[String], designator: String}.
static func _apply_designator(designator: Callable, shortfall_cp: int,
		units: Array) -> Dictionary:
	if not designator.is_valid():
		return {
			"unit_ids": _typed_ids(designate_cheapest_first(shortfall_cp, units)),
			"designator": DESIGNATOR_CHEAPEST_FIRST,
		}

	var wage_by_id: Dictionary = {}
	for u in units:
		wage_by_id[String((u as Dictionary).get("id", ""))] = int(
			(u as Dictionary).get("monthly_wage_cp", 0))

	var raw: Variant = designator.call(shortfall_cp, units)
	var picks: Array[String] = []
	var covered: int = 0
	if raw is Array:
		for v in (raw as Array):
			var unit_id: String = String(v)
			if not wage_by_id.has(unit_id):
				push_error("TroopPayShortfallResolver: designator returned '%s', which is not on this domain's payroll" % unit_id)
				continue
			if picks.has(unit_id):
				continue
			picks.append(unit_id)
			covered += int(wage_by_id[unit_id])
	else:
		push_error("TroopPayShortfallResolver: designator returned %s, expected Array of unit ids" % type_string(typeof(raw)))

	if covered >= shortfall_cp:
		return {"unit_ids": picks, "designator": DESIGNATOR_CUSTOM}

	# Under-designation is a real shortfall left unaccounted for, not a
	# preference — the money is gone either way. Keep the caller's picks and
	# make up the difference with the default rather than pretending the
	# remainder was paid.
	var remaining: Array = []
	for u in units:
		if not picks.has(String((u as Dictionary).get("id", ""))):
			remaining.append(u)
	for unit_id in designate_cheapest_first(shortfall_cp - covered, remaining):
		picks.append(String(unit_id))
	return {"unit_ids": picks, "designator": DESIGNATOR_CUSTOM_TOPPED_UP}


static func _cheaper_unit_first(a: Dictionary, b: Dictionary) -> bool:
	var wage_a: int = int(a.get("monthly_wage_cp", 0))
	var wage_b: int = int(b.get("monthly_wage_cp", 0))
	if wage_a != wage_b:
		return wage_a < wage_b
	return String(a.get("id", "")) < String(b.get("id", ""))


static func _typed_ids(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for v in ids:
		out.append(String(v))
	return out
