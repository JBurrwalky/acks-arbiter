class_name OrgTypeCatalog
extends RefCounted

## Data-defined organization-type catalog (gdd-faction-framework.md §6.1/§6.3/
## §8.2/§8.5 — FF-2.1). Loads data/factions/org_types.json once and exposes the
## per-type presence gating, income model, size tier, join criteria, rank ladder
## (§8.2), and service menu (§8.5). ALSO the single source for the two economic
## constants the org month (§6.6) prices through: the Henchman Monthly Fee wage
## table by class level and the RAW criminal-guild level-mix pyramid used to
## price member_count_abstract.
##
## All static; no RNG, no wall-clock. The wage table mirrors
## NpcSyndicateMonthlyResolver's L9+ table + data/equipment/provisions_services.json
## L0-8 (kept in one place here so the ¼-wages ledger has a single source).

const TYPES_PATH: String = "res://data/factions/org_types.json"

## Henchman Monthly Fee by class level, gp/month (gdd-faction-framework.md §6.6;
## rules/acore_henchmen_monthly_fee_table.xml:20-36).
const WAGE_GP_BY_LEVEL: Dictionary = {
	0: 12, 1: 25, 2: 50, 3: 100, 4: 200, 5: 400, 6: 800, 7: 1600,
	8: 3000, 9: 7250, 10: 12000, 11: 32000, 12: 50000, 13: 135000, 14: 350000,
}

## RAW criminal-guild level pyramid mix used to price member_count_abstract
## (§6.6; rules/acore-setting-construction-rules.xml:523-561). L3+ priced at L3.
## Weights sum to 1.0; the pre-computed average wage per abstract member is the
## dot product with WAGE_GP_BY_LEVEL: 0.45*12 + 0.35*25 + 0.125*50 + 0.075*100.
const LEVEL_MIX: Array = [
	{"level": 0, "weight": 0.45},
	{"level": 1, "weight": 0.35},
	{"level": 2, "weight": 0.125},
	{"level": 3, "weight": 0.075},
]

static var _data: Dictionary = {}
static var _loaded: bool = false


## The full type-def Dictionary for [param type], or {} if unknown.
static func type_def(type: String) -> Dictionary:
	var types: Dictionary = _load().get("types", {})
	var d: Variant = types.get(type, null)
	return d if d is Dictionary else {}


## Every known org-type key (sorted for determinism).
static func all_types() -> Array:
	var keys: Array = (_load().get("types", {}) as Dictionary).keys()
	keys.sort()
	return keys


static func is_known_type(type: String) -> bool:
	return not type_def(type).is_empty()


static func income_model(type: String) -> String:
	return String(type_def(type).get("income_model", "quarter_wages"))


## True when the type's treasury is resolved by an external RAW resolver
## (NpcSyndicateMonthlyResolver / VentureMonthlyResolver) and the FactionAI
## ledger must PASS THROUGH — no ¼-wages accrual, no re-resolve (§6.6).
static func is_passthrough_income(type: String) -> bool:
	return income_model(type) == "syndicate_passthrough"


static func size_tier(type: String) -> int:
	return int(type_def(type).get("size_tier", 2))


static func presence_class_threshold(type: String) -> int:
	return int(type_def(type).get("presence_class_threshold", 6))


static func roll_threshold(type: String) -> int:
	return int(type_def(type).get("roll_threshold", 4))


static func default_goal_primary(type: String) -> String:
	return String(type_def(type).get("default_goal_primary", "accumulate_wealth"))


static func default_goal_secondary(type: String) -> String:
	return String(type_def(type).get("default_goal_secondary", ""))


static func join_class_families(type: String) -> Array:
	var d: Variant = type_def(type).get("join_class_families", [])
	return (d as Array).duplicate() if d is Array else []


# ---------------------------------------------------------------------------
# Ranks (§8.2) + services (§8.5)
# ---------------------------------------------------------------------------

static func rank_titles(type: String) -> Array:
	var d: Variant = type_def(type).get("ranks", [])
	return (d as Array).duplicate() if d is Array else []


## The ladder title for a 0-based rank index (clamped to the ladder ends).
static func rank_title(type: String, rank_index: int) -> String:
	var titles: Array = rank_titles(type)
	if titles.is_empty():
		return "Member"
	var idx: int = clampi(rank_index, 0, titles.size() - 1)
	return String(titles[idx])


static func max_rank(type: String) -> int:
	var titles: Array = rank_titles(type)
	return maxi(0, titles.size() - 1)


static func services(type: String) -> Array:
	var d: Variant = type_def(type).get("services", [])
	return (d as Array).duplicate() if d is Array else []


## Minimum rank required for a service id, or -1 if the type has no such service.
static func service_min_rank(type: String, service_id: String) -> int:
	for s in services(type):
		if s is Dictionary and String((s as Dictionary).get("id", "")) == service_id:
			return int((s as Dictionary).get("min_rank", 0))
	return -1


# ---------------------------------------------------------------------------
# The §6.6 wage economics (single source for the ¼-wages ledger)
# ---------------------------------------------------------------------------

## gp/month wage for a class level (0 for out-of-range levels).
static func wage_gp_for_level(level: int) -> int:
	return int(WAGE_GP_BY_LEVEL.get(level, 0))


## The pre-computed average monthly wage of ONE abstract member, priced through
## the RAW criminal-guild level-mix pyramid (§6.6). Pure function of the
## constants above — ~27.9 gp.
static func avg_abstract_wage_gp() -> float:
	var total: float = 0.0
	for entry in LEVEL_MIX:
		total += float((entry as Dictionary).get("weight", 0.0)) \
			* float(wage_gp_for_level(int((entry as Dictionary).get("level", 0))))
	return total


## Σ(monthly wages) for [param count] abstract members priced through the mix.
static func abstract_wage_sum_gp(count: int) -> float:
	return float(maxi(0, count)) * avg_abstract_wage_gp()


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

static func _load() -> Dictionary:
	if _loaded:
		return _data
	_loaded = true
	_data = {}
	var text: String = FileAccess.get_file_as_string(TYPES_PATH)
	if text.is_empty():
		push_error("OrgTypeCatalog: cannot read %s" % TYPES_PATH)
		return _data
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("OrgTypeCatalog: %s is not a JSON object" % TYPES_PATH)
	return _data


## Test/regen hook — drop the cached data.
static func clear_cache() -> void:
	_data = {}
	_loaded = false
