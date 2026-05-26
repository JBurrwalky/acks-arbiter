class_name SettlementGrowthResolver
extends RefCounted

## Per-settlement growth resolver for the monthly investment subphase per
## `generation/gdd-urban-growth-stocking.md` §6.2 EVALUATE_GROWTH +
## EVALUATE_CLASS (v1.14).
##
## Per Q-UGS-15 this is a SEPARATE resolver — a sibling of
## `DomainGrowthResolver`, NOT a subphase of it. The monthly-tick
## orchestrator calls `process_monthly_tick(settlement_id, investment_cp,
## calendar_day, rng_seed)` for each settlement under a domain AFTER the
## domain growth resolver has run (so the domain's investment_cp has been
## allocated and is available to spend on settlement growth).
##
## Math per §6.2 steps 1-8:
##   1-2. Investment-driven family attraction → urban_families.
##        Civilized: 1d10 per 1,000 gp invested.
##        Clanhold: 1d10 per 2,000 gp invested (Phase 11D.2 per RAW L82-83 +
##        gdd-domain-style-and-alignment.md §2 — value of investment in
##        clanhold-style domains is halved; the cap-tightening that v1 of this
##        resolver applied per xml:32-33 has been REMOVED because the Arbiter
##        project interprets ALL clanholds as receiving the L76-86 exceptions
##        package, which lifts those caps per L80-81).
##   3.   Population growth dice: 2 × (1d10 per full 1000 urban_families,
##        rounded up), exploding 10s. Net delta = increase - decrease.
##   4.   Random growth ±1d10 - 1d10.
##   5.   Cap urban_families at the maximum-population-by-total-investment
##        table per `acore_axioms_strongholds_and_domains.xml:641-648`.
##        Applies to all settlements regardless of style.
##   6.   Dissolution check (urban_families < 75).
##   7.   (Phase 11D.2:) Clanhold-style domains no longer apply the 250 cap
##        or 12.5% peasant-population cap — RAW L80 explicitly lifts these
##        for the chaotic-domain exceptions package that Arbiter applies
##        to all clanholds. The `clanhold_exception` result flag is retained
##        for the caller / UI but is now informational.
##   8.   Re-derive market_class from urban_families per
##        `acore_axioms:658-664`; emit market_class_advanced / regressed
##        if changed.
##
## Dice come from a Callable that returns the SUM of `count` rolls of
## `d_faces`, mirroring DomainGrowthResolver's roller contract. Pass an
## empty Callable to use the project DiceSystem.

# RAW maximum-urban-population-by-total-investment table per
# `acore_axioms_strongholds_and_domains.xml:641-648`. Ordered descending so
# the first row whose investment threshold the settlement meets gives the
# cap. v1 uses banker's rounding nowhere here — the table is a discrete
# step function.
const _MAX_POP_BY_INVESTMENT: Array = [
	{"min_gp": 2500000, "max_pop": 100000},
	{"min_gp": 625000,  "max_pop":  19999},
	{"min_gp": 200000,  "max_pop":   4999},
	{"min_gp": 75000,   "max_pop":   2499},
	{"min_gp": 25000,   "max_pop":    624},
	{"min_gp": 10000,   "max_pop":    249},
]

# Market-class thresholds per RAW `acore_axioms:658-664` cross-referenced
# with `acore-campaign-hijinks.xml:631-638`. Class numbers: 6 (smallest) to
# 1 (largest). Ordered ascending so we walk and find the first class whose
# min_families the settlement meets.
const _MARKET_CLASS_THRESHOLDS: Array = [
	{"class": 6, "min_families":    75},
	{"class": 5, "min_families":   250},
	{"class": 4, "min_families":   625},
	{"class": 3, "min_families":  2500},
	{"class": 2, "min_families":  5000},
	{"class": 1, "min_families": 20000},
]

const DISSOLUTION_THRESHOLD: int = 75
# Phase 11D.2: investment-to-family conversion rate. Civilized = 1d10 per 1,000 gp
# (RAW acore_axioms:653). Clanhold = 1d10 per 2,000 gp (RAW ax_domains_of_chaos:83
# "halved investment value").
const SETTLEMENT_INVESTMENT_GP_PER_ROLL_CIVILIZED: int = 1000
const SETTLEMENT_INVESTMENT_GP_PER_ROLL_CLANHOLD: int = 2000


## Process one month of growth for a single settlement.
##
## Inputs:
##   settlement: Dictionary — must include `id`, `urban_families`,
##     `market_class`, `cumulative_investment_gp`, and optional clanhold
##     hints (see _is_clanhold).
##   parent_domain: Dictionary — must include `domain_style` and
##     `peasant_families` (for clanhold cap math). May be empty if the
##     settlement has no parent_domain_id; clanhold path is then skipped.
##   investment_cp: int — cp allocated to THIS settlement this month (the
##     caller routes domain-level pending_investment_cp to each of its
##     settlements; in v1 with one-settlement-per-domain the routing is
##     trivial).
##   dice_roller: Callable with signature
##     `(faces: int, count: int, exploding: bool) -> int` returning the SUM.
##     Pass an empty Callable to use the project DiceSystem.
##
## Returns a Dictionary with keys (all integers / bools / dicts):
##   urban_families_old, urban_families_new, urban_families_delta,
##   market_class_old, market_class_new,
##   class_advanced (bool), class_regressed (bool),
##   dissolved (bool),
##   investment_gp_consumed,
##   investment_families_added, population_growth_increase,
##   population_growth_decrease, random_growth, cap_truncation,
##   clanhold_exception (bool)
##
## Side effects: NONE in the resolver itself. The caller is responsible
## for persisting urban_families_new, market_class_new, the dissolution
## status flag, and the incremented cumulative_investment_gp. The resolver
## emits no signals — the caller does so based on the returned dict.
static func process_monthly_tick(
	settlement: Dictionary,
	parent_domain: Dictionary,
	investment_cp: int,
	dice_roller: Callable = Callable(),
) -> Dictionary:
	var urban_families_old: int = int(settlement.get("urban_families", 0))
	var market_class_old: int = int(settlement.get("market_class", 6))
	var cumulative_investment_gp: int = int(
		settlement.get("cumulative_investment_gp", 10000))

	var roller: Callable
	if dice_roller.is_valid():
		roller = dice_roller
	else:
		roller = func(faces: int, count: int, exploding: bool) -> int:
			return _dice_system_default(faces, count, exploding)

	var clanhold: bool = _is_clanhold(parent_domain)

	# ------------------------------------------------------------------
	# Steps 1-2 — Investment-driven growth.
	# Phase 11D.2 (per RAW ax_domains_of_chaos L80-83 + L82-83 +
	# gdd-domain-style-and-alignment.md §2):
	#   - Clanhold-style settlements DO grow via investment (RAW L81: "Urban
	#     settlements may be increased in size or market class.").
	#   - Conversion rate is halved: 1d10 per 2,000 gp for clanhold vs 1,000 gp
	#     for civilized (RAW L82-83: "halved investment value"; "2,000gp to
	#     attract 1d10 new families").
	#   - The 250 / 12.5% caps that this resolver previously applied to clanhold
	#     settlements are REMOVED per RAW L80 (the chaotic-domain exceptions
	#     package lifts the base clanhold settlement caps from xml:28-33).
	# ------------------------------------------------------------------
	var investment_gp_consumed: int = 0
	var investment_families_added: int = 0
	if investment_cp > 0:
		var investment_gp: int = investment_cp / 100
		var gp_per_roll: int = (
			SETTLEMENT_INVESTMENT_GP_PER_ROLL_CLANHOLD if clanhold
			else SETTLEMENT_INVESTMENT_GP_PER_ROLL_CIVILIZED
		)
		var roll_groups: int = investment_gp / gp_per_roll
		if roll_groups > 0:
			investment_families_added = roller.call(10, roll_groups, false)
		investment_gp_consumed = investment_gp

	var urban_families: int = urban_families_old + investment_families_added

	# ------------------------------------------------------------------
	# Step 3 — Population growth dice. Per `acore_axioms:650`:
	# 2 × (1d10 per full 1000 urban_families, rounded up), with exploding
	# 10s. The first roll is the increase; the second is the decrease.
	# Applies to clanholds too (natural growth/loss).
	# ------------------------------------------------------------------
	var population_growth_increase: int = 0
	var population_growth_decrease: int = 0
	if urban_families > 0:
		var groups: int = int(ceil(float(urban_families) / 1000.0))
		population_growth_increase = roller.call(10, groups, true)
		population_growth_decrease = roller.call(10, groups, true)
	urban_families += population_growth_increase - population_growth_decrease

	# ------------------------------------------------------------------
	# Step 4 — Random growth per `ax_campaign_play.xml:14`: +1d10 − 1d10.
	# Applies to clanholds too.
	# ------------------------------------------------------------------
	var random_increase: int = roller.call(10, 1, false)
	var random_decrease: int = roller.call(10, 1, false)
	var random_growth: int = random_increase - random_decrease
	urban_families += random_growth

	urban_families = maxi(0, urban_families)

	# ------------------------------------------------------------------
	# Step 5 — Cap at the maximum-population-by-total-investment table.
	# Phase 11D.2: the previous clanhold-specific 250-family + 12.5%-peasant
	# caps were REMOVED — RAW L80 explicitly lifts them for the chaotic-
	# domain exceptions package that Arbiter applies to all clanholds.
	# Only the standard cumulative-investment cap remains, applied uniformly.
	# ------------------------------------------------------------------
	var new_cumulative_investment_gp: int = cumulative_investment_gp + investment_gp_consumed
	var cap_truncation: int = 0
	var pop_cap: int = _max_pop_for_investment(new_cumulative_investment_gp)

	if urban_families > pop_cap:
		cap_truncation = urban_families - pop_cap
		urban_families = pop_cap

	# ------------------------------------------------------------------
	# Step 6 — Dissolution check. RAW `acore_axioms:686-689`: < 75 urban
	# families => settlement dissolves.
	# ------------------------------------------------------------------
	var dissolved: bool = false
	if urban_families < DISSOLUTION_THRESHOLD:
		dissolved = true
		# Per the GDD the dissolution reverts urban_families to peasant
		# families in nearby hexes; we leave that bookkeeping to the
		# orchestrator (it needs the parent domain context). Reset to 0
		# in the result so the caller knows the post-dissolution urban
		# count is zero.
		urban_families = 0

	# ------------------------------------------------------------------
	# Step 8 — Re-derive market_class.
	# ------------------------------------------------------------------
	var market_class_new: int = _market_class_for_families(urban_families)
	if dissolved:
		# Dissolved settlements: class falls back to the default Class VI
		# slot, matching settlement_entrances.market_class default.
		market_class_new = 6
	var class_advanced: bool = market_class_new < market_class_old
	var class_regressed: bool = market_class_new > market_class_old

	return {
		"urban_families_old": urban_families_old,
		"urban_families_new": urban_families,
		"urban_families_delta": urban_families - urban_families_old,
		"market_class_old": market_class_old,
		"market_class_new": market_class_new,
		"class_advanced": class_advanced,
		"class_regressed": class_regressed,
		"dissolved": dissolved,
		"investment_gp_consumed": investment_gp_consumed,
		"investment_families_added": investment_families_added,
		"population_growth_increase": population_growth_increase,
		"population_growth_decrease": population_growth_decrease,
		"random_growth": random_growth,
		"cap_truncation": cap_truncation,
		"clanhold_exception": clanhold,
		"new_cumulative_investment_gp": new_cumulative_investment_gp,
	}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Walks the maximum-population-by-total-investment table descending and
## returns the largest pop cap whose investment threshold the settlement
## has met. Settlements below the founding 10000gp threshold return 249
## (the Class VI minimum) — Stage B treats below-founding settlements as
## already in the Class VI slot rather than rejecting them.
static func _max_pop_for_investment(cumulative_investment_gp: int) -> int:
	for row in _MAX_POP_BY_INVESTMENT:
		if cumulative_investment_gp >= int(row["min_gp"]):
			return int(row["max_pop"])
	# Below the founding threshold — use Class VI floor.
	return 249


## Walks the market-class thresholds and returns the class number matching
## urban_families. Settlements below the founding threshold return Class 6.
static func _market_class_for_families(urban_families: int) -> int:
	var current_class: int = 6
	for row in _MARKET_CLASS_THRESHOLDS:
		if urban_families >= int(row["min_families"]):
			current_class = int(row["class"])
	return current_class


## A clanhold per `gdd-domain-style-and-alignment.md` §4-§6: any domain whose
## `domain_style` column is `'clanhold'`. Migration 127 (Phase 11D.1) dropped
## the `is_chaotic_domain` proxy that previously stood in for this — the new
## `domain_style` column is the canonical style indicator, orthogonal to
## alignment (a domain may be clanhold-style + lawful alignment, etc.).
## Establishment paths via `clanhold_annex` / `recruit_chieftain` force-lock
## domain_style='clanhold' per `establish_domain_flow.gd`.
static func _is_clanhold(parent_domain: Dictionary) -> bool:
	if parent_domain.is_empty():
		return false
	return String(parent_domain.get("domain_style", "civilized")) == "clanhold"


## Default dice roller — sums `count` rolls of `d_faces`; on exploding=true,
## any die landing on its max face explodes (re-roll and add). Mirrors
## `DomainGrowthResolver._dice_system_default`.
static func _dice_system_default(faces: int, count: int, exploding: bool) -> int:
	if count <= 0 or faces <= 0:
		return 0
	var total: int = 0
	for _i in range(count):
		var rolled: RollResult = DiceSystem.roll_digital(faces, 1, 0, "settlement_growth")
		var value: int = rolled.modified_total
		total += value
		if exploding and value == faces:
			var explode_value: int = value
			while explode_value == faces:
				var explode_roll: RollResult = DiceSystem.roll_digital(
					faces, 1, 0, "settlement_growth_explode")
				explode_value = explode_roll.modified_total
				total += explode_value
	return total
