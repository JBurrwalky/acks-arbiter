class_name ArmySupplyAllocationResolver
extends RefCounted

## Decides WHICH units eat when an army's supply stockpile cannot feed the whole
## roster for the week — RAW `rules/daw_campaigning_armies.xml:365-367`:
##
##   :365 "If an army can feed only some units, its leader chooses which units
##         are supplied."
##   :366 "Supplied units suffer no lack-of-supply penalties and do not make the
##         weekly lack-of-supply check."
##   :367 "Unsupplied units suffer an additional -1 penalty on their loyalty
##         rolls because they are visibly being left to starve."
##
## This class only DESIGNATES. It never rolls, never touches the stockpile and
## never writes to the database; `ArmySupplyTracker.run_supply_tick` owns the
## deduction and `UnitLoyaltyResolver.roll_loyalty` owns the roll.
##
## ── Why this mirrors TroopPayShortfallResolver ──────────────────────────────
##
## Same shape of problem as the wage side (conventions §132, 2026-08-02): a bulk
## transaction fell short and RAW asks *which specific units* it failed to
## cover. The answer there was the same as here — do not build per-unit supply
## ledgers to answer a per-unit question. Supply stays one stockpile settled
## against one weekly cost; the designation is derived from the shortfall after
## the fact. No migration, no new columns, no change to how supply is spent.
##
## ── The designation rule: BEST FIRST, not cheapest ──────────────────────────
##
## Highest whole-unit `troop_units.battle_rating` first, ties broken on id.
##
## This is deliberately the OPPOSITE ordering from `TroopPayShortfallResolver`,
## and the reason is that the two resolvers designate opposite sets. The pay
## resolver names the *harmed* set (who goes unpaid) and takes the cheapest
## first, which maximises the number of units harmed. This resolver names the
## *spared* set (who eats), so taking the best first — which are also the
## costliest to feed, RAW puts cavalry at 240 gp/week against infantry's 60
## (`daw_campaigning_armies.xml` §supply_cost) — burns the stockpile fast and
## likewise leaves the largest number of units facing a loyalty roll. Both
## resolvers are therefore the harsh reading, which is the right default for
## rules whose whole point is that failing your soldiers is dangerous.
##
## In fiction it is also the decision a commander actually makes: the
## cataphracts stay fighting fit and the levy tightens its belt. [Jedidiah
## ruling 2026-08-03 — the ordering was surfaced as an open design choice
## against "feed the most mouths" and "best battle rating per cp"; best-first
## was chosen.]
##
## Walk order is priority order, but a unit the remaining stockpile cannot
## afford is SKIPPED rather than ending the walk — a quartermaster with 100 cp
## left, a 240 cp cavalry unit next and a 60 cp infantry unit after it feeds the
## infantry. Stopping at the first unaffordable unit would strand food nobody
## eats, which is neither RAW nor sensible.
##
## ── Partial supply of the last unit ─────────────────────────────────────────
##
## Whatever remains after the walk is spent on the highest-priority unsupplied
## unit, which stays UNSUPPLIED. That is RAW, not a fudge: :360 counts a week in
## which a unit is "partially or completely unsupplied" as a calamity, and :366
## exempts only *supplied* units from the check. So a half-fed unit rolls
## exactly like a starving one. The practical effect is that a shortfall week
## always drains the stockpile to 0, which is also what the all-or-nothing model
## this replaces did.
##
## ── Units that do not eat ───────────────────────────────────────────────────
##
## A unit whose weekly cost is 0 — the hungerless constructs/undead branch of
## `SupplyCalculator._is_hungerless`, per `daw_campaigning_armies.xml`
## §hungerless_troops L265-269 — is ALWAYS supplied and consumes nothing. It
## cannot be starved for want of food it does not need, so it is force-supplied
## even when a custom designator omits it.
##
## ── The player-override seam ────────────────────────────────────────────────
##
## `resolve_for_army` takes an optional `designator` Callable with the signature
## `(stockpile_cp: int, units: Array) -> Array` returning the ids of the units
## the leader chose to FEED. NPC-led armies never supply one and always get
## best-first, matching the pay resolver's rule that NPC domains get no player
## input. When the "choose who eats" screen is built it passes its own Callable
## at the `run_supply_tick` call site; nothing else moves.
##
## The over-designation guard is the mirror image of the pay resolver's. There,
## a designation that UNDER-covered the shortfall was topped up, because the
## constraint was a floor and leaving part of it unassigned would pretend money
## was paid. Here the constraint is a CEILING — the stockpile — so a designation
## that overspends is TRIMMED (lowest battle rating dropped first) rather than
## rejected, because honouring it would conjure food that does not exist.

## Label reported in the result dict when no custom designator was supplied.
const DESIGNATOR_BEST_FIRST := "best_first"
const DESIGNATOR_CUSTOM := "custom"
const DESIGNATOR_CUSTOM_TRIMMED := "custom_trimmed"
## Reported when the stockpile covered the whole weekly cost — no choice to make.
const DESIGNATOR_ALL_SUPPLIED := "all_supplied"


## Resolve this week's supply designation for [param army_id] against
## [param stockpile_cp], the cp on hand before the weekly deduction.
##
## [param designator] optional `(stockpile_cp: int, units: Array) -> Array`
## override returning the ids of units to FEED; see the class docstring.
##
## Returns:
##   {army_id, weekly_cost_cp, stockpile_cp, shortfall_cp,
##    supplied_unit_ids: Array[String], unsupplied_unit_ids: Array[String],
##    partially_supplied_unit_id: String, spent_cp, considered_unit_ids,
##    designator}
static func resolve_for_army(army_id: String, stockpile_cp: int,
		designator: Callable = Callable()) -> Dictionary:
	var breakdown: Dictionary = SupplyCalculator.weekly_supply_cost_breakdown(army_id)
	var units: Array = breakdown.get("units", [])
	var weekly_cost: int = int(breakdown.get("total_cp", 0))
	var considered: Array[String] = []
	for u in units:
		considered.append(String((u as Dictionary).get("id", "")))

	# A negative stockpile is not a thing the supply state can hold, but clamp
	# defensively so a bad row cannot inflate the shortfall past the bill.
	var budget: int = maxi(0, stockpile_cp)
	var shortfall: int = maxi(0, weekly_cost - budget)

	var result: Dictionary = {
		"army_id": army_id,
		"weekly_cost_cp": weekly_cost,
		"stockpile_cp": budget,
		"shortfall_cp": shortfall,
		"supplied_unit_ids": considered.duplicate(),
		"unsupplied_unit_ids": [] as Array[String],
		"partially_supplied_unit_id": "",
		"spent_cp": mini(budget, weekly_cost),
		"considered_unit_ids": considered,
		"designator": DESIGNATOR_ALL_SUPPLIED,
	}
	# No shortfall means no choice to make and RAW never asks the question.
	# Gating on `total_cp` rather than on the sum of the per-unit ints is
	# load-bearing — see the rounding note on
	# `SupplyCalculator.weekly_supply_cost_breakdown`.
	if shortfall <= 0 or units.is_empty():
		return result

	var applied: Dictionary = _apply_designator(designator, budget, units)
	var supplied: Array[String] = applied["unit_ids"]
	var spent: int = int(applied["spent_cp"])

	var unsupplied: Array[String] = []
	for u in _by_best_first(units):
		var unit_id: String = String((u as Dictionary).get("id", ""))
		if unit_id.is_empty() or supplied.has(unit_id):
			continue
		unsupplied.append(unit_id)

	# RAW :360 — a PARTIALLY supplied unit is still unsupplied for the weekly
	# check, so the leftover goes to the best of the starving without sparing
	# it. Ordering above is best-first, so `unsupplied[0]` is that unit.
	var partial_id: String = ""
	if not unsupplied.is_empty() and spent < budget:
		partial_id = unsupplied[0]
		spent = budget

	result["supplied_unit_ids"] = supplied
	result["unsupplied_unit_ids"] = unsupplied
	result["partially_supplied_unit_id"] = partial_id
	result["spent_cp"] = spent
	result["designator"] = String(applied["designator"])
	return result


## The default designation: feed the highest `battle_rating` first, skipping any
## unit the remaining stockpile cannot afford, until the list is exhausted.
## Returns `{unit_ids: Array[String], spent_cp: int}`.
##
## Termination is trivial — one pass over a finite roster — and a stockpile of 0
## feeds only the hungerless.
static func designate_best_first(stockpile_cp: int, units: Array) -> Dictionary:
	var out: Array[String] = []
	var remaining: int = maxi(0, stockpile_cp)
	var spent: int = 0
	for u in _by_best_first(units):
		var unit_id: String = String((u as Dictionary).get("id", ""))
		if unit_id.is_empty():
			continue
		var cost: int = int((u as Dictionary).get("weekly_supply_cp", 0))
		# Hungerless units (cost 0) always eat — see the class docstring.
		if cost <= 0:
			out.append(unit_id)
			continue
		if cost > remaining:
			continue
		out.append(unit_id)
		remaining -= cost
		spent += cost
	return {"unit_ids": out, "spent_cp": spent}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Run [param designator] (or the best-first default), then validate: drop ids
## that aren't on this army's roster, drop duplicates, force-supply the
## hungerless, and trim lowest-battle-rating picks until the bill fits
## [param stockpile_cp]. Returns
## `{unit_ids: Array[String], spent_cp: int, designator: String}`.
static func _apply_designator(designator: Callable, stockpile_cp: int,
		units: Array) -> Dictionary:
	if not designator.is_valid():
		var default_pick: Dictionary = designate_best_first(stockpile_cp, units)
		return {
			"unit_ids": default_pick["unit_ids"],
			"spent_cp": int(default_pick["spent_cp"]),
			"designator": DESIGNATOR_BEST_FIRST,
		}

	var by_id: Dictionary = {}
	for u in units:
		by_id[String((u as Dictionary).get("id", ""))] = u

	var raw: Variant = designator.call(stockpile_cp, units)
	var picks: Array[String] = []
	if raw is Array:
		for v in (raw as Array):
			var unit_id: String = String(v)
			if not by_id.has(unit_id):
				push_error("ArmySupplyAllocationResolver: designator returned '%s', which is not on this army's roster" % unit_id)
				continue
			if picks.has(unit_id):
				continue
			picks.append(unit_id)
	else:
		push_error("ArmySupplyAllocationResolver: designator returned %s, expected Array of unit ids" % type_string(typeof(raw)))

	# Hungerless units cost nothing and cannot starve; a designator that leaves
	# one out did not mean to starve it, it just had no reason to name it.
	for u in units:
		var free_id: String = String((u as Dictionary).get("id", ""))
		if free_id.is_empty() or picks.has(free_id):
			continue
		if int((u as Dictionary).get("weekly_supply_cp", 0)) <= 0:
			picks.append(free_id)

	var spent: int = 0
	for unit_id in picks:
		spent += int((by_id[unit_id] as Dictionary).get("weekly_supply_cp", 0))
	if spent <= stockpile_cp:
		return {
			"unit_ids": picks,
			"spent_cp": spent,
			"designator": DESIGNATOR_CUSTOM,
		}

	# Over-designation would feed units out of a stockpile that cannot cover
	# them. Drop the worst troops the leader picked until the bill fits, keeping
	# their stated priority for everyone above the line.
	var ordered_picks: Array = []
	for unit_id in picks:
		ordered_picks.append(by_id[unit_id])
	ordered_picks = _by_best_first(ordered_picks)
	ordered_picks.reverse()
	for u in ordered_picks:
		if spent <= stockpile_cp:
			break
		var cost: int = int((u as Dictionary).get("weekly_supply_cp", 0))
		if cost <= 0:
			continue
		picks.erase(String((u as Dictionary).get("id", "")))
		spent -= cost
	return {
		"unit_ids": picks,
		"spent_cp": spent,
		"designator": DESIGNATOR_CUSTOM_TRIMMED,
	}


## Roster sorted best-first: highest whole-unit `battle_rating`, ties on id so
## two units minted in the same batch always designate in the same order across
## runs.
static func _by_best_first(units: Array) -> Array:
	var ordered: Array = units.duplicate()
	ordered.sort_custom(_better_unit_first)
	return ordered


static func _better_unit_first(a: Dictionary, b: Dictionary) -> bool:
	var br_a: float = float(a.get("battle_rating", 0.0))
	var br_b: float = float(b.get("battle_rating", 0.0))
	if not is_equal_approx(br_a, br_b):
		return br_a > br_b
	return String(a.get("id", "")) < String(b.get("id", ""))
