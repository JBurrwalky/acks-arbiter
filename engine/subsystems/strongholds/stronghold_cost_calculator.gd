class_name StrongholdCostCalculator
extends RefCounted

## Compute the total cost, daily construction rate, and engineer requirement
## for a stronghold commission per `acore_stronghold_construction_costs.pdf`
## p.126-127:
##   * Base build rate: 1 day per 500 gp of base cost (i.e., 500 gp/day).
##   * Speed tier 150 (pay +50% extra cost): -25% time → effective 666 gp/day.
##   * Speed tier 200 (pay +100% extra cost): -50% time → 1000 gp/day (cap).
##   * Engineer requirement: ceil(gp_committed / 100,000) engineers @ 250 gp/month each.
##   * Class cost reduction: cleric / bladedancer halve the structure cost
##     (PDF p.126 "Strongholds by Class" table).
##   * Magic assistance per `daw_equipment_and_construction.xml` §magic_assistance
##     L801-819: Move Earth, Transmute Rock to Mud (+50%), Wall of Stone (+250
##     gp instant), stacking multiplicatively.
##
## Class location restrictions (dwarven must be underground, elf spellsword
## non-human/dwarven, explorer borderlands/wilderness only) are enforced by
## `validate_class_location` and surfaced as Array[String] error codes.

const BASE_DAILY_RATE_GP := 500
const SPEED_TIER_TIME_MULTIPLIER := {
	100: 100,  # base: no premium, 1 day per 500 gp
	150: 75,   # +50% cost → -25% time
	200: 50,   # +100% cost → -50% time (cap)
}
const ENGINEER_GP_PER_ENGINEER := 100000
const ENGINEER_MONTHLY_WAGE_CP := 25000  # RAW 250 gp/month per engineer
const ACCESSORY_AT_CONSTRUCTION_DISCOUNT_PCT := 25


## Returns Dictionary with keys:
##   base_structure_cost: int                  — sum of structures (PDF p.126)
##   accessory_cost: int                       — sum × 25% upgrade discount (PDF p.127 footnote)
##   class_cost_reduction_pct: int             — 0 or 50 (cleric / bladedancer)
##   discounted_base_cost: int                 — class-discounted (base + accessories)
##   speed_tier_pct: int                       — 100 / 150 / 200
##   speed_premium_gp: int                     — extra paid for speed tier
##   gp_committed: int                         — discounted_base + speed_premium
##   daily_construction_rate_gp: int           — gp credited per day at this tier
##   magic_rate_modifier_pct: int              — 100 / 150 / 200
##   engineers_required: int                   — ceil(gp_committed / 100,000); minimum 1
##   engineer_monthly_wage_cp: int             — engineers × 250
##   estimated_duration_days: int              — ceil(gp_committed / daily_rate)
static func calculate_total_cost(
	archetype_preset: Dictionary,
	structures: Array,             # Array[Dictionary] — rows from structure_catalog.json
	accessories: Array,            # Array[Dictionary] — accessory entries
	speed_tier_pct: int,
	magic_rate_modifier_pct: int = 100
) -> Dictionary:
	var base_structure_cost: int = 0
	for s: Dictionary in structures:
		base_structure_cost += int(s.get("gp_cost", 0))

	var accessory_total: int = 0
	for a: Dictionary in accessories:
		accessory_total += int(a.get("gp_cost", 0))
	# Per PDF p.127 footnote: at construction time, accessories are 25% of base cost.
	var accessory_cost: int = XPAwardCalculator.bankers_round(
		float(accessory_total) * float(ACCESSORY_AT_CONSTRUCTION_DISCOUNT_PCT) / 100.0)

	var class_cost_reduction_pct: int = int(archetype_preset.get("class_cost_reduction_pct", 0))
	var combined_base: int = base_structure_cost + accessory_cost
	var discounted_base_cost: int = combined_base
	if class_cost_reduction_pct > 0:
		discounted_base_cost = XPAwardCalculator.bankers_round(
			float(combined_base) * float(100 - class_cost_reduction_pct) / 100.0)

	var clamped_speed_tier: int = speed_tier_pct
	if not SPEED_TIER_TIME_MULTIPLIER.has(clamped_speed_tier):
		clamped_speed_tier = 100  # fall back to base
	var speed_premium_gp: int = XPAwardCalculator.bankers_round(
		float(discounted_base_cost) * float(clamped_speed_tier - 100) / 100.0)
	var gp_committed: int = discounted_base_cost + speed_premium_gp

	# Daily rate: base_rate × speed_tier × magic_modifier / 10000 (since speed
	# and magic are both percentages on top of base).
	# Speed tier 100 → 500/day; 150 → 666/day; 200 → 1000/day.
	# Magic 150 → ×1.5 on top; magic 200 → ×2 on top (cap is unspecified by RAW;
	# we let the cost calc express whatever the player builds, then the daily
	# tick respects it).
	var daily_construction_rate_gp: int = XPAwardCalculator.bankers_round(
		float(BASE_DAILY_RATE_GP) * (10000.0 / float(SPEED_TIER_TIME_MULTIPLIER[clamped_speed_tier])) / 100.0
		* float(magic_rate_modifier_pct) / 100.0)
	# Equivalent simpler form: 500 × (100 / time_multiplier) × magic_mult / 100.

	var engineers_required: int = maxi(1, int(ceil(float(gp_committed) / float(ENGINEER_GP_PER_ENGINEER))))
	var engineer_monthly_wage_cp: int = engineers_required * ENGINEER_MONTHLY_WAGE_CP

	var estimated_duration_days: int = 0
	if daily_construction_rate_gp > 0:
		estimated_duration_days = int(ceil(float(gp_committed) / float(daily_construction_rate_gp)))

	return {
		"base_structure_cost": base_structure_cost,
		"accessory_cost": accessory_cost,
		"class_cost_reduction_pct": class_cost_reduction_pct,
		"discounted_base_cost": discounted_base_cost,
		"speed_tier_pct": clamped_speed_tier,
		"speed_premium_gp": speed_premium_gp,
		"gp_committed": gp_committed,
		"daily_construction_rate_gp": daily_construction_rate_gp,
		"magic_rate_modifier_pct": magic_rate_modifier_pct,
		"engineers_required": engineers_required,
		"engineer_monthly_wage_cp": engineer_monthly_wage_cp,
		"estimated_duration_days": estimated_duration_days,
	}


## Validate per-class location restrictions per `acore_stronghold_construction_costs.pdf`
## p.126 "Strongholds by Class" Special Rules column.
##
## Returns Array[String] of error codes (empty = valid). Codes:
##   "explorer_borderlands_or_wilderness_only"
##   "dwarven_must_be_underground"
##   "dwarven_no_human_or_elven_civilized_or_borderlands"
##   "elf_spellsword_no_human_or_dwarven_civilized_or_borderlands"
##
## [param territory_type] is one of "civilized" / "borderlands" / "wilderness".
## [param ruler_race] is one of "human" / "dwarven" / "elven" (for the
## "no human/elven" / "no human/dwarven" checks — checks the territory's
## predominant race, which Phase 1 derives from `domains.race` if available
## or defaults to the ruler's own race).
## [param is_underground] is true if the location_hex is marked as underground.
static func validate_class_location(
	archetype_power_id: String,
	territory_type: String,
	territory_predominant_race: String,
	is_underground: bool
) -> Array:
	var errors: Array[String] = []
	match archetype_power_id:
		"stronghold_border_fort":
			if territory_type == "civilized":
				errors.append("explorer_borderlands_or_wilderness_only")
		"stronghold_vault":
			if not is_underground:
				errors.append("dwarven_must_be_underground")
			if territory_type != "wilderness" \
					and territory_predominant_race in ["human", "elven"]:
				errors.append("dwarven_no_human_or_elven_civilized_or_borderlands")
		"stronghold_fastness":
			if territory_type != "wilderness" \
					and territory_predominant_race in ["human", "dwarven"]:
				errors.append("elf_spellsword_no_human_or_dwarven_civilized_or_borderlands")
		_:
			pass
	return errors


## Validate that enough engineers are assigned to begin or continue construction.
## Returns true if engineers_assigned >= engineers_required.
static func validate_engineer_requirement(gp_committed: int, engineers_assigned: int) -> bool:
	var required: int = maxi(1, int(ceil(float(gp_committed) / float(ENGINEER_GP_PER_ENGINEER))))
	return engineers_assigned >= required
