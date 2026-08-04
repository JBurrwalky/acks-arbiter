class_name SupplyCalculator
extends RefCounted

## Computes army weekly supply cost and weighted-supply-line geometry per
## daw_campaigning_armies.xml §supply L226-374; gdd-army-warfare.md §2.4 / §4.4.
##
## The codebase stores per-unit monthly_supply_cp (denormalized at hire time)
## on troop_units.monthly_supply_cp. RAW publishes weekly costs (60 gp / 240 gp
## per company-sized infantry / cavalry); Phase 5 stores the monthly conversion
## (weekly × 4) to match the rest of the pay/expense math. We invert that here
## by dividing by 4 to get weekly. Banker's rounding per CLAUDE.md.
##
## Quartermaster missing → ×2 cost per daw_armies_recruitment.xml §quartermaster
## L887-892. Carnivorous → ×4 per daw_campaigning_armies.xml §supply_cost
## .special_cases L257-263. Hungerless → 0 per §hungerless_troops L265-269.
##
## v1 places quartermaster / carnivorous / hungerless flags on the troop_unit
## row (or its template) keyed by source_type / troop_type. Until Phase 5 adds
## those columns explicitly, we infer from the type strings (carnivorous wolves,
## undead, etc. are out of v1 scope; v1 supports human/demi-human/beastman).
##
## Weighted-line multipliers per §overextended_supply.weighted_length_rules
## L307-320 (RAW; never modify):
##   barren / desert        × 4
##   jungle / mountain / swamp × 2
##   hills / woods          × 1.5
##   road                   × 0.25
##   settled                × 0.33
##   navigable waterway     × 0
##   clear / scrub / plain  × 1
##
## Race modifiers per same RAW: elves treat forest as settled; dwarves treat
## hills/mountain as settled; beastmen treat all terrain as settled. v1
## implements this for the army's predominant race.

const TERRAIN_WEIGHT_BASE := {
	"barren": 4.0,
	"desert": 4.0,
	"jungle": 2.0,
	"mountain": 2.0,
	"mountains": 2.0,
	"swamp": 2.0,
	"hills": 1.5,
	"woods": 1.5,
	"forest": 1.5,
	"road": 0.25,
	"trail": 0.25,
	"settled": 0.33,
	"navigable_waterway": 0.0,
	"river": 0.0,
	"clear": 1.0,
	"scrub": 1.0,
	"plain": 1.0,
	"plains": 1.0,
	"grassland": 1.0,
}

const MAX_WEIGHTED_HEXES := 16
const STATUS_IN_SUPPLY := "in_supply"
const STATUS_BLOCKED := "out_of_supply_blocked"
const STATUS_OVEREXTENDED := "out_of_supply_overextended"
const STATUS_NO_BASE := "out_of_supply_no_base"
const STATUS_SIMPLIFIED := "simplified"


# ---------------------------------------------------------------------------
# Weekly supply cost
# ---------------------------------------------------------------------------

static func compute_weekly_supply_cost_cp(army_id: String) -> int:
	## Sums per-unit weekly supply cost across active assignments. Returns 0
	## for empty armies. Quartermaster / carnivorous / hungerless modifiers
	## are applied per RAW where unit metadata supports them.
	##
	## Cp-native end-to-end (2026-05-16 army wage pass): troop_units.monthly_supply_cp
	## ÷ 4 yields cp/week, modifiers compound on cp, return is cp.
	return int(weekly_supply_cost_breakdown(army_id).get("total_cp", 0))


## The same weekly figure `compute_weekly_supply_cost_cp` returns, itemized by
## unit — what RAW's partial-supply allocation (`daw_campaigning_armies.xml:365`,
## "if an army can feed only some units, its leader chooses which units are
## supplied") needs in order to decide who eats.
##
## Returns `{total_cp: int, units: Array[Dictionary]}`. Each entry is the full
## `troop_units` row plus:
##   * `weekly_supply_cp` — that unit's own cost, banker-rounded to an int so it
##     can be compared against an integer stockpile.
##   * `weekly_supply_cost_exact` — the unrounded float, kept so callers that
##     want to re-derive a subtotal do not compound rounding error.
##
## **`total_cp` is the rounded SUM, not the sum of the rounded parts**, which is
## how the pre-existing single-number API behaved and must keep behaving. The
## two can differ by a cp or so once modifiers produce fractions, so an
## allocator working from the per-unit ints must never infer "there is a
## shortfall" by comparing their sum to the stockpile — `total_cp` is the
## authority on that. `ArmySupplyAllocationResolver` gates on `total_cp` for
## exactly this reason.
static func weekly_supply_cost_breakdown(army_id: String) -> Dictionary:
	var empty: Dictionary = {"total_cp": 0, "units": []}
	if army_id.is_empty():
		return empty
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	if assignments.is_empty():
		return empty

	var total_weekly_cp: float = 0.0
	var units: Array = []
	for assn in assignments:
		var troop_unit: Dictionary = _get_troop_unit(String(assn.get("troop_unit_id", "")))
		if troop_unit.is_empty():
			continue
		var monthly_supply_cp: int = int(troop_unit.get("monthly_supply_cp", 0))
		# RAW publishes per-week. Phase 5 stores monthly = weekly × 4.
		var unit_weekly_cp: float = float(monthly_supply_cp) / 4.0
		# Apply modifiers (v1 scope; flag-based when columns land).
		if _is_hungerless(troop_unit):
			unit_weekly_cp = 0.0
		elif _is_carnivorous(troop_unit):
			unit_weekly_cp *= 4.0
		if not _has_quartermaster(troop_unit):
			unit_weekly_cp *= 2.0
		total_weekly_cp += unit_weekly_cp

		var row: Dictionary = troop_unit.duplicate()
		row["weekly_supply_cp"] = XPAwardCalculator.bankers_round(unit_weekly_cp)
		row["weekly_supply_cost_exact"] = unit_weekly_cp
		units.append(row)

	# Banker-round the cp residue (rare; modifiers can produce fractional cp).
	return {
		"total_cp": XPAwardCalculator.bankers_round(total_weekly_cp),
		"units": units,
	}


# ---------------------------------------------------------------------------
# Weighted-line geometry
# ---------------------------------------------------------------------------

static func compute_weighted_path_length(
	path: Array,
	predominant_race: String = "human"
) -> int:
	## path: Array of Dictionaries, each with at least {"terrain": String} and
	## optionally {"is_road": bool, "is_settled": bool, "enemy_present": bool}.
	## Returns weighted hex count rounded up to nearest integer per RAW
	## L307-320 ("every 4 hexes count as 1" / "every 3 hexes count as 1" etc.
	## are weight aggregation rules — fractional weights are summed, then
	## ceil'd at the end to determine "is the line ≤ 16 hexes").
	if path.is_empty():
		return 0
	var weighted_total: float = 0.0
	for hex in path:
		weighted_total += _terrain_weight(hex, predominant_race)
	return int(ceil(weighted_total))


static func evaluate_supply_line_status(
	supply_state: Dictionary,
	weekly_cost_cp: int,
	weighted_hex_count: int,
	path: Array
) -> String:
	## Returns one of STATUS_* per gdd-army-warfare.md §2.4 enum.
	## Order of checks (per RAW + GDD):
	##   1. No base / no path → out_of_supply_no_base
	##   2. Path passes through enemy hex → out_of_supply_blocked
	##   3. Weighted length > 16 → out_of_supply_overextended
	##   4. Otherwise → in_supply
	if supply_state.is_empty():
		return STATUS_NO_BASE
	var base_id: Variant = supply_state.get("supply_base_stronghold_id", null)
	if base_id == null or String(base_id) == "":
		return STATUS_NO_BASE
	for hex in path:
		if bool(hex.get("enemy_present", false)):
			return STATUS_BLOCKED
	if weighted_hex_count > MAX_WEIGHTED_HEXES:
		return STATUS_OVEREXTENDED
	# Stockpile vs cost is consumed by the weekly tick; supply line itself is
	# "intact" if base exists, path is clear, and length is within range.
	# A separate consecutive_unsupplied_weeks counter handles attrition.
	# weekly_cost_cp parameter retained for future simplified-supply rule.
	if weekly_cost_cp < 0:
		return STATUS_NO_BASE  # defensive; never expected
	return STATUS_IN_SUPPLY


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _terrain_weight(hex: Dictionary, predominant_race: String) -> float:
	var terrain: String = String(hex.get("terrain", "clear")).to_lower()
	# Race-based reclassification per RAW L319-320.
	if predominant_race == "beastman":
		# All terrain treated as settled.
		return TERRAIN_WEIGHT_BASE["settled"]
	if predominant_race == "elf" and (terrain == "forest" or terrain == "woods"):
		return TERRAIN_WEIGHT_BASE["settled"]
	if predominant_race == "dwarf" and (
		terrain == "hills" or terrain == "mountain" or terrain == "mountains"
	):
		return TERRAIN_WEIGHT_BASE["settled"]
	# Override flags (road/settled/waterway) take precedence over base terrain.
	if bool(hex.get("is_road", false)):
		return TERRAIN_WEIGHT_BASE["road"]
	if bool(hex.get("is_navigable_waterway", false)):
		return TERRAIN_WEIGHT_BASE["navigable_waterway"]
	if bool(hex.get("is_settled", false)):
		return TERRAIN_WEIGHT_BASE["settled"]
	return float(TERRAIN_WEIGHT_BASE.get(terrain, 1.0))


static func _is_carnivorous(troop_unit: Dictionary) -> bool:
	# Phase 5 troop_units does not yet carry a carnivorous flag. v1 detects
	# from troop_type substrings; ACKS 1e human/demi-human/beastman lines are
	# all non-carnivorous, so this returns false for the v1 supported races.
	var t: String = String(troop_unit.get("troop_type", "")).to_lower()
	return t.contains("wolf") or t.contains("dire") or t.contains("carnivor")


static func _is_hungerless(troop_unit: Dictionary) -> bool:
	# Hungerless = constructs / undead / extraplanar without need for food.
	# v1 does not field these troops; this hook stays for v1.1+ expansion.
	var t: String = String(troop_unit.get("troop_type", "")).to_lower()
	return t.contains("undead") or t.contains("construct")


static func _has_quartermaster(troop_unit: Dictionary) -> bool:
	# Phase 5 stores `monthly_specialist_cp`; a non-zero value means specialist
	# coverage was paid at hire time. Per daw_armies_recruitment.xml §quartermaster,
	# 1 quartermaster per unit is the standard; we treat any specialist spend
	# > 0 as quartermaster-present until Phase 6 introduces a typed specialist
	# roster column on troop_units.
	return int(troop_unit.get("monthly_specialist_cp", 0)) > 0


static func _get_troop_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
