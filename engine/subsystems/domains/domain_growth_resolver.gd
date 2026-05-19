class_name DomainGrowthResolver
extends RefCounted

## Domain population growth resolver per:
##   * `acore_axioms_strongholds_and_domains.xml` §domain_growth.monthly_change L126-131
##     and §investments L132-135 and §active_adventuring_growth L137-149
##   * `ax_campaign_play.xml` §random_growth L15-17
##   * §effects_of_morale L538-609 for morale-tier population modifiers
##
## Dice are injected via a Callable so the handler / tests own the RNG. The
## roller has signature `(faces: int, count: int, exploding: bool) -> int` and
## must return the SUM of `count` rolls of `d_faces`. Exploding-on-max means
## any die rolling its maximum face explodes (re-roll and add). Pass an empty
## Callable to use the project DiceSystem.

const _ACTIVE_ADVENTURING_BANDS := [
	# {min_population, dice_count, dice_faces}
	{"min_pop": 0,   "count": 5, "faces": 20},  # 1-100 → +5d20
	{"min_pop": 101, "count": 5, "faces": 10},  # 101-200 → +5d10
	{"min_pop": 201, "count": 4, "faces": 10},  # 201-300 → +4d10
	{"min_pop": 301, "count": 3, "faces": 10},  # 301-400 → +3d10
	{"min_pop": 401, "count": 2, "faces": 10},  # 401-500 → +2d10
	{"min_pop": 501, "count": 1, "faces": 10},  # 500+ → +1d10
]

# Morale tier → families per 1,000 modifier (count of 1d10s; sign indicates
# gain or loss). Per §effects_of_morale L538-609.
const _MORALE_TIER_GROWTH_DICE := {
	"Rebellious":  -4,  # also halts random growth — handled in resolve_growth
	"Defiant":     -3,
	"Turbulent":   -2,
	"Demoralized": -1,
	"Apathetic":    0,
	"Loyal":        1,
	"Dedicated":    2,
	"Steadfast":    3,
	"Stalwart":     4,
}


## Returns a Dictionary with keys:
##   net_change: int                  — total population delta (signed)
##   random_increase: int             — per-1000-families exploding 1d10 (gain)
##   random_decrease: int             — per-1000-families exploding 1d10 (loss)
##   active_adventuring_bonus: int    — table-by-population
##   investment_bonus: int            — 1d10 per 1,000 gp invested (capped)
##   morale_tier_modifier: int        — signed Nd10 per 1,000 families
##   growth_halted_by_morale: bool    — true at Rebellious morale
##   income_gate_active: bool         — echoed from caller
static func resolve_growth(
	domain: Dictionary,
	monthly_revenue_cp: int,
	investment_gp: int,
	morale_tier: String,
	is_active_adventuring: bool,
	income_gate_active: bool,
	dice_roller: Callable = Callable()
) -> Dictionary:
	var population: int = int(domain.get("peasant_families", 0)) \
		+ int(domain.get("urban_families", 0))
	var roller: Callable
	if dice_roller.is_valid():
		roller = dice_roller
	else:
		# Fallback: real DiceSystem via a lambda (Callable(static_method) is
		# unreliable across GDScript versions; the lambda always wraps cleanly).
		roller = func(faces: int, count: int, exploding: bool) -> int:
			return _dice_system_default(faces, count, exploding)

	var random_increase: int = 0
	var random_decrease: int = 0
	var active_adventuring_bonus: int = 0
	var investment_bonus: int = 0
	var morale_tier_modifier: int = 0
	var growth_halted := (morale_tier == DomainMoraleResolver.TIER_REBELLIOUS)

	# Income gate: no random growth, no morale-driven change. Active-adventuring
	# and investment still apply (RAW reads adventuring as independent of
	# stronghold sufficiency — the ruler's exploits attract families regardless,
	# and investments specifically target attracting peasants per L121).
	var random_growth_active: bool = (not income_gate_active) and (not growth_halted)

	if random_growth_active and population > 0:
		# Per §domain_growth.monthly_change L126-131: roll once per 1,000 families,
		# rounded up. Each "roll" is a single exploding 1d10.
		var groups: int = int(ceil(float(population) / 1000.0))
		random_increase = roller.call(10, groups, true)
		random_decrease = roller.call(10, groups, true)

	if is_active_adventuring:
		var band: Dictionary = _active_adventuring_band(population)
		active_adventuring_bonus = roller.call(int(band["faces"]), int(band["count"]), false)

	if investment_gp > 0:
		# Investment cap per §investments L132-135: max monthly investment is
		# the domain's monthly revenue or 1,000 gp, whichever is greater.
		var cap: int = maxi(monthly_revenue_cp, 1000)
		var allowed_gp: int = mini(investment_gp, cap)
		var investment_units: int = allowed_gp / 1000  # one 1d10 per full 1,000 gp
		if investment_units > 0:
			investment_bonus = roller.call(10, investment_units, false)

	if (not income_gate_active) and population > 0 and _MORALE_TIER_GROWTH_DICE.has(morale_tier):
		var dice_count: int = _MORALE_TIER_GROWTH_DICE[morale_tier]
		var groups2: int = int(ceil(float(population) / 1000.0))
		if dice_count != 0:
			var sign_mul: int = 1 if dice_count > 0 else -1
			var rolled: int = roller.call(10, abs(dice_count) * groups2, false)
			morale_tier_modifier = sign_mul * rolled

	var net: int = random_increase - random_decrease + active_adventuring_bonus \
		+ investment_bonus + morale_tier_modifier

	return {
		"net_change": net,
		"random_increase": random_increase,
		"random_decrease": random_decrease,
		"active_adventuring_bonus": active_adventuring_bonus,
		"investment_bonus": investment_bonus,
		"morale_tier_modifier": morale_tier_modifier,
		"growth_halted_by_morale": growth_halted,
		"income_gate_active": income_gate_active,
	}


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _active_adventuring_band(population: int) -> Dictionary:
	var match_band: Dictionary = _ACTIVE_ADVENTURING_BANDS[0]
	for band: Dictionary in _ACTIVE_ADVENTURING_BANDS:
		if population >= int(band["min_pop"]):
			match_band = band
		else:
			break
	return match_band


# Default dice roller used when no Callable is supplied. Sums `count` rolls of
# `d_faces`; on exploding=true, any die rolling its max face explodes (re-roll
# and add).
static func _dice_system_default(faces: int, count: int, exploding: bool) -> int:
	if count <= 0 or faces <= 0:
		return 0
	var total: int = 0
	for _i in range(count):
		var rolled: RollResult = DiceSystem.roll_digital(faces, 1, 0, "domain_growth")
		var value: int = rolled.modified_total
		total += value
		if exploding and value == faces:
			# Explode: keep rolling 1d_faces while we land on max.
			var explode_value: int = value
			while explode_value == faces:
				var explode_roll: RollResult = DiceSystem.roll_digital(faces, 1, 0, "domain_growth_explode")
				explode_value = explode_roll.modified_total
				total += explode_value
	return total
