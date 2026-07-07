class_name RulerActionScorer
extends RefCounted

## The deterministic utility scorer for NPC ruler actions — gdd-ruler-ai.md §6,
## formalizing gdd-npc-personality.md §8.5:
##
##   utility(a) = base_value(a)
##              x relevant_weight(a, disposition)     # the §5 governing weight
##              x PRODUCT situational_modifier_i(a)   # the §6.2 tables
##
## `hold` has no governing weight (§5.2 "—"): its utility is the flat
## base_value floor, unmodified — the anti-thrash baseline every real action
## must beat.
##
## Determinism: no dice inside scoring. Tie-breaking uses a CALLER-SUPPLIED
## per-(ruler, month) seeded RNG (gdd-ruler-ai.md §6.1) applied over a
## canonical pre-sort, so reruns are identical. All §6.2 numbers are PROJECT
## CALL and tunable.
##
## The §7 crisis-response bias arrives as ctx["crisis_biases"]
## (RulerCrisisResponder.posture_biases) and multiplies into the situational
## product — including hold's otherwise-unmodified flat floor (§7.1 cautious
## hoarding).

# --- §6.2 morale-tier modifier table (rows by tier band, columns by action) ---
# Bands: Loyal+ (morale >= +1) / Apathetic (0) / Demoralized-Turbulent (-1,-2)
# / Defiant-Rebellious (<= -3).
const _MORALE_TABLE := {
	"administer_domain":  [1.0, 1.2, 1.5, 1.8],
	"raise_garrison":     [0.8, 1.0, 1.4, 1.7],
	"decree_tax":         [0.7, 1.0, 1.4, 1.6],  # the §6.2 "decree(lower tax)" column
	"repress_population": [0.2, 0.5, 1.0, 1.5],
	"oversee_investment": [1.3, 1.0, 0.6, 0.3],
}

# --- §6.2 treasury-state modifiers ---
## Actions that spend treasury directly (PROJECT CALL: the two treasury-
## deducting actions; levies pay monthly wages, not lump sums).
const _SPENDY_ACTIONS := ["oversee_investment", "manage_stronghold"]
const _POOR_BUFFER_MONTHS := 2.0
const _RICH_BUFFER_MONTHS := 6.0
const _POOR_SPENDY_MOD := 0.4
const _POOR_TAX_DECREE_MOD := 1.5
const _RICH_INVESTMENT_MOD := 1.4

# --- §6.2 garrison / stronghold / threat modifiers ---
const _UNDER_GARRISON_MOD := 2.0
const _STRONGHOLD_BELOW_MIN_MOD := 2.0
const _STRONGHOLD_RUINED_MOD := 3.0
## §6.2 says defensive x1.5-2.5; 2.0 is the PROJECT CALL midpoint until the
## Phase-3 crisis responder modulates it by posture.
const _THREAT_DEFENSIVE_MOD := 2.0
const _THREAT_ECONOMIC_MOD := 0.5
const _DEFENSIVE_ACTIONS := ["defensive_resistance", "call_to_arms", "withstand_siege"]
## The §5.1 economic actions the §6.2 threat row halves ("economic/investment
## actions x0.5"): administer_domain, oversee_investment, and the tax decree
## (handled separately via its table key).
const _THREAT_HALVED_ACTIONS := ["administer_domain", "oversee_investment"]

## Realm-scale thresholds for acting on more than one candidate per month
## (§6.1 step 4 "top-2..3 for large realms"; PROJECT CALL).
const _SCALE_2_DOMAINS := 3
const _SCALE_2_FAMILIES := 2500
const _SCALE_3_DOMAINS := 6
const _SCALE_3_FAMILIES := 10000


## Score and sort [param candidates] (RulerActionCatalog shape) for one ruler.
## [param ctx] keys (all optional, degrade to neutral):
##   morale: int                       — current morale (-4..+4)
##   treasury_cp / monthly_expenses_cp — the treasury-buffer inputs
##   garrison_needs_raising: bool      — the shared §5.2 trigger
##   stronghold_below_minimum: bool / stronghold_ruined: bool
##   threat_present: bool
## Returns a NEW array of candidate dicts + `utility`, sorted by utility DESC;
## ties broken by the caller's seeded [param rng] (deterministic per seed).
static func score_candidates(candidates: Array, disposition: StrategicDisposition,
		ctx: Dictionary, rng: RandomNumberGenerator) -> Array:
	var scored: Array = []
	for c in candidates:
		if not (c is Dictionary):
			continue
		var row: Dictionary = (c as Dictionary).duplicate()
		row["utility"] = _utility(row, disposition, ctx)
		scored.append(row)
	# Canonical pre-sort (action_id + decree kind) so the tie-break RNG sees a
	# stable order regardless of catalog emission order.
	scored.sort_custom(func(a, b): return _canonical_key(a) < _canonical_key(b))
	for row in scored:
		row["_tiebreak"] = rng.randf()
	scored.sort_custom(func(a, b):
		if absf(float(a["utility"]) - float(b["utility"])) > 0.000001:
			return float(a["utility"]) > float(b["utility"])
		return float(a["_tiebreak"]) > float(b["_tiebreak"]))
	for row in scored:
		row.erase("_tiebreak")
	return scored


## §6.1 step 4: how many top candidates a ruler acts on this month —
## 1 baseline, 2 for sizeable realms, 3 for large ones (PROJECT CALL bands
## over RealmAggregator.aggregate output).
static func actions_for_scale(aggregate: Dictionary) -> int:
	var domains_ruled: int = int(aggregate.get("domains_ruled", 0))
	var families: int = int(aggregate.get("all_realm_families", 0))
	var n: int = 1
	if domains_ruled >= _SCALE_2_DOMAINS or families >= _SCALE_2_FAMILIES:
		n = 2
	if domains_ruled >= _SCALE_3_DOMAINS or families >= _SCALE_3_FAMILIES:
		n = 3
	return n


## A stable per-(ruler, month) RNG for tie-breaking (gdd-ruler-ai.md §6.1).
## Mirrors the CommerceMonthlyResolver.seeded_monthly_rng runtime idiom
## (engine hash(); session-local determinism — runtime state is not
## share-seeded, so WorldGenRng's cross-platform FNV stream is not required).
static func monthly_rng(ruler_character_id: String, calendar_day: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ruler_turn|%s|%d" % [ruler_character_id, calendar_day])
	return rng


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _utility(candidate: Dictionary, disposition: StrategicDisposition,
		ctx: Dictionary) -> float:
	var base: float = float(candidate.get("base_value", 0.0))
	var weight_key: String = String(candidate.get("weight_key", ""))
	# hold's "—" weight: flat floor, no weight, no §6.2 situational modifiers —
	# but the §7.1 crisis-posture bias still applies (cautious postures hoard).
	if weight_key.is_empty():
		var hold_biases: Dictionary = ctx.get("crisis_biases", {})
		return base * float(hold_biases.get(String(candidate.get("action_id", "")), 1.0))
	var weight: float = 0.0
	if disposition != null:
		weight = float(disposition.weights().get(weight_key, 0.0))
	# --- Faction FF-3 (§5.6): realm diplomacy actions (propose_treaty / denounce /
	#     issue_ultimatum / declare_war / sue_for_peace) score through this SAME
	#     generic path — weight-gated on diplomatic_weight (or expansion_weight for
	#     declare_war), with a neutral situational product (they carry no §6.2
	#     morale/treasury/garrison row, so _situational_product returns 1.0). A
	#     non-diplomatic ruler's diplomatic_weight is low, so these naturally lose
	#     to domestic actions — no special-case gating needed here; the catalog's
	#     is_sovereign gate is what restricts them to active-LOD sovereigns. The
	#     §7 crisis-bias channel still applies to the crisis_modulated ones
	#     (declare_war / sue_for_peace) via _situational_product's biases block. ---
	return base * weight * _situational_product(candidate, ctx)


static func _situational_product(candidate: Dictionary, ctx: Dictionary) -> float:
	var action_id: String = String(candidate.get("action_id", ""))
	var params: Dictionary = candidate.get("params", {})
	var table_key: String = action_id
	# Tax decrees are DIRECTION-aware: the §6.2 morale column is explicitly
	# "decree(LOWER tax)" (morale repair), while the poor-treasury boost below
	# is the §5.1 raise-for-revenue lever. Classify by the decree's target
	# value vs the domain's current rate.
	var tax_lowering := false
	var tax_raising := false
	if action_id == "issue_decree":
		var kind: String = String(params.get("decree_kind", ""))
		table_key = "decree_tax" if kind == "tax" else ""
		if kind == "tax":
			var target: int = int(params.get("value", 200))
			var current: int = int(ctx.get("current_tax_cp", 200))
			tax_lowering = target < current
			tax_raising = target > current
	var product: float = 1.0

	# Morale tier (§6.2 table; the decree column only for LOWERING decrees).
	if _MORALE_TABLE.has(table_key) \
			and (table_key != "decree_tax" or tax_lowering):
		var band: int = _morale_band(int(ctx.get("morale", 0)))
		product *= float((_MORALE_TABLE[table_key] as Array)[band])

	# Treasury state (§6.2): under a 2-month expense buffer -> spendy actions
	# throttled, tax decree boosted; over 6 months -> investment boosted.
	var expenses: int = maxi(1, int(ctx.get("monthly_expenses_cp", 0)))
	var buffer_months: float = float(int(ctx.get("treasury_cp", 0))) / float(expenses)
	if int(ctx.get("monthly_expenses_cp", 0)) > 0:
		if buffer_months < _POOR_BUFFER_MONTHS:
			if _SPENDY_ACTIONS.has(action_id):
				product *= _POOR_SPENDY_MOD
			# The broke-boost is for RAISING taxes (revenue at a morale cost,
			# §5.1) — never for the lowering/reset decree.
			if table_key == "decree_tax" and tax_raising:
				product *= _POOR_TAX_DECREE_MOD
		elif buffer_months > _RICH_BUFFER_MONTHS and action_id == "oversee_investment":
			product *= _RICH_INVESTMENT_MOD

	# Garrison state (§6.2): actively bleeding morale -> raise_garrison x2.
	if action_id == "raise_garrison" and bool(ctx.get("garrison_needs_raising", false)):
		product *= _UNDER_GARRISON_MOD

	# Stronghold state (§6.2): ruined outranks merely-insufficient.
	if action_id == "manage_stronghold":
		if bool(ctx.get("stronghold_ruined", false)):
			product *= _STRONGHOLD_RUINED_MOD
		elif bool(ctx.get("stronghold_below_minimum", false)):
			product *= _STRONGHOLD_BELOW_MIN_MOD

	# Threat present (§6.2): defensive actions up, economic/investment down
	# (the §5.1 economic set: administer, investment, tax decree).
	if bool(ctx.get("threat_present", false)):
		if _DEFENSIVE_ACTIONS.has(action_id):
			product *= _THREAT_DEFENSIVE_MOD
		elif _THREAT_HALVED_ACTIONS.has(action_id) or table_key == "decree_tax":
			product *= _THREAT_ECONOMIC_MOD

	# §7 crisis-response bias (RulerCrisisResponder.posture_biases): keyed by
	# "issue_decree|<kind>" for decree variants, else by action id. The tax
	# key is the §7.2 LOWER-tax stability lever — direction-gated exactly
	# like the §6.2 morale column (boosting a raise-tax decree would feed the
	# morale spiral the bias exists to bleed).
	var biases: Dictionary = ctx.get("crisis_biases", {})
	if not biases.is_empty():
		var specific: String = action_id
		if action_id == "issue_decree":
			specific = "issue_decree|" + String(params.get("decree_kind", ""))
		var decree_bias_gated: bool = table_key == "decree_tax" and not tax_lowering
		if biases.has(specific) and not decree_bias_gated:
			product *= float(biases[specific])
		elif specific != action_id and biases.has(action_id):
			product *= float(biases[action_id])

	return product


## §6.2 tier bands: Loyal+ / Apathetic / Demoralized-Turbulent / Defiant-Rebellious.
static func _morale_band(morale: int) -> int:
	if morale >= 1:
		return 0
	if morale == 0:
		return 1
	if morale >= -2:
		return 2
	return 3


static func _canonical_key(candidate: Dictionary) -> String:
	var params: Dictionary = candidate.get("params", {})
	var kind: String = String(params.get("decree_kind", ""))
	# The decree VALUE keeps the key total-ordered when two tax decrees
	# (lower + raise) are candidates simultaneously.
	return "%s|%s|%s" % [
		String(candidate.get("action_id", "")), kind, str(params.get("value", "")),
	]
