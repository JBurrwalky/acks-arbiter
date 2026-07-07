class_name RewardValuator
extends RefCounted

## Pure, unit-testable quest-reward math. Session Q-1.
## generation/gdd-quest-rumor-system.md §8 (formulas), §13.1 (bands).
##
## No I/O, no DB access. Every public entry point is `static` and takes an
## explicit `RandomNumberGenerator` where a roll is needed (project
## determinism convention — see docs/coding_conventions.md §3.9 pure-class
## pattern and e.g. commerce/market_price_resolver.gd::roll_4d4).
##
## Banker's rounding (XPAwardCalculator.bankers_round) on every value that
## rounds. All multipliers/bands are PROJECT CALL, tunable (§14).

# ---------------------------------------------------------------------------
# §8.1 — reward-multiplier bands (treasure-bearing threats)
# ---------------------------------------------------------------------------

const REWARD_MULTIPLIER_BY_THREAT: Dictionary = {
	"monster_lair": 0.50,
	"dungeon": 0.25,
	"brigand": 0.75,
}

## Creature bounties (lone monsters, little/no treasure) pay a MULTIPLE of
## monster XP instead of a percentage of treasure (§8.1/§13.1, Jedidiah
## 2026-07-07) so a treasure-less bounty never collapses to ~0.
const CREATURE_BOUNTY_XP_MULTIPLIER: float = 2.0

## §8.1 variance: final = base * (0.90 + rand(0, 0.20))  -- +/-10%.
const VARIANCE_MIN: float = 0.90
const VARIANCE_MAX: float = 1.10

## §8.1 sanity bounds.
const MIN_GOLD_REWARD: int = 25
const MAX_GOLD_REWARD: int = 25000

## §8.1 party-level daily rate for time-based quest types.
const PARTY_LEVEL_GP_RATE_PER_LEVEL: float = 25.0
const ESCORT_DELIVERY_MULTIPLIER: float = 0.50
const RECONNAISSANCE_MULTIPLIER: float = 0.25

## §8.5 recovery item valuation band (by questgiver Motivation, §8.3).
const RECOVERY_MIN_MULTIPLIER: float = 0.25
const RECOVERY_MAX_MULTIPLIER: float = 0.75
const RECOVERY_MAGIC_ITEM_MULTIPLIER: float = 0.50

## §8.3 Motivation tone nudge — desperate givers pay high, calculating givers
## pay low, within +/-20% of the base multiplier.
const MOTIVATION_TONE_MAX_NUDGE: float = 0.20
const DESPERATE_MOTIVATIONS: Array = ["security", "faith"]
const CALCULATING_MOTIVATIONS: Array = ["power", "wealth"]

## §8.6 affordability clamp.
const RULER_ANNUAL_DISCRETIONARY_FRACTION: float = 0.10

## §8.1 rounding buckets: nearest 25 gp under 500, nearest 100 gp at/above 500.
const ROUND_BUCKET_SMALL: int = 25
const ROUND_BUCKET_LARGE: int = 100
const ROUND_BUCKET_THRESHOLD: int = 500

## §12 ACore acore_treasure_and_magic_items_rules.xml:56-87 — the RAW
## treasure_type_table's "category_and_average_value" column (average GP
## value per lettered treasure type, A-R). Used to pre-estimate a threat's
## expected on-site treasure at generation time (§8.1) without rolling.
const TREASURE_TYPE_AVG_GP: Dictionary = {
	"A": 275, "B": 500, "C": 700, "D": 1000, "E": 1250, "F": 1500,
	"G": 2000, "H": 2500, "I": 3250, "J": 4000, "K": 5000, "L": 6000,
	"M": 8000, "N": 9000, "O": 12000, "P": 17000, "Q": 22000, "R": 45000,
}


# ---------------------------------------------------------------------------
# §8.1 — treasure-bearing threats (lair / dungeon / brigand)
# ---------------------------------------------------------------------------

## Pre-estimate a threat's expected on-site treasure from its ACKS treasure
## types (average-roll valuation, no dice) — §8.1. `treasure_type_letters`
## is the set of lettered treasure types the threat's monsters/lair carry
## (e.g. a lair entry's `treasure_type` field, "E" or "E, Q").
static func estimate_treasure_value(treasure_type_letters: Array) -> int:
	var total := 0
	for letter in treasure_type_letters:
		var key := String(letter).strip_edges().to_upper()
		if TREASURE_TYPE_AVG_GP.has(key):
			total += TREASURE_TYPE_AVG_GP[key]
	return total


## §8.1 base_reward for a treasure-bearing threat_type (monster_lair, dungeon,
## brigand): estimated_threat_treasure * reward_multiplier.
static func base_reward_treasure_bearing(threat_type: String,
		estimated_threat_treasure: int) -> float:
	var multiplier: float = REWARD_MULTIPLIER_BY_THREAT.get(threat_type, 0.0)
	return float(estimated_threat_treasure) * multiplier


## §8.1 base_reward for a creature_bounty: (sum monster XP at the site) * 2.0.
static func base_reward_creature_bounty(total_monster_xp: int) -> float:
	return float(total_monster_xp) * CREATURE_BOUNTY_XP_MULTIPLIER


## §8.1 party-level daily rate: average_party_level * 25 gp/day.
static func party_level_gp_rate(average_party_level: int) -> float:
	return float(average_party_level) * PARTY_LEVEL_GP_RATE_PER_LEVEL


## §8.1 escort/delivery reward: rate * travel_days * 0.50.
static func base_reward_escort_or_delivery(average_party_level: int, travel_days: int) -> float:
	return party_level_gp_rate(average_party_level) * float(travel_days) * ESCORT_DELIVERY_MULTIPLIER


## §8.1 reconnaissance reward: rate * travel_days * 0.25.
static func base_reward_reconnaissance(average_party_level: int, travel_days: int) -> float:
	return party_level_gp_rate(average_party_level) * float(travel_days) * RECONNAISSANCE_MULTIPLIER


# ---------------------------------------------------------------------------
# §8.5 — recovery item valuation
# ---------------------------------------------------------------------------

## §8.5 recovery_reward = item_gp_value * (0.25 to 0.75), picked by
## questgiver Motivation tone (§8.3) — pass motivation_fraction in
## [RECOVERY_MIN_MULTIPLIER, RECOVERY_MAX_MULTIPLIER] (caller resolves the
## Motivation-driven position in the band; this stays a pure multiply).
static func recovery_reward(item_gp_value: int, motivation_fraction: float) -> float:
	var clamped := clampf(motivation_fraction, RECOVERY_MIN_MULTIPLIER, RECOVERY_MAX_MULTIPLIER)
	return float(item_gp_value) * clamped


## §8.5 magic item recovery: item_sale_value * 0.50 (fair vs. finding a buyer).
static func recovery_reward_magic_item(item_sale_value: int) -> float:
	return float(item_sale_value) * RECOVERY_MAGIC_ITEM_MULTIPLIER


# ---------------------------------------------------------------------------
# §8.3 — Motivation tone nudge
# ---------------------------------------------------------------------------

## §8.3: nudge a base reward by up to +/-20% based on questgiver Motivation.
## Desperate givers (security/faith) pay toward the high end; calculating
## givers (power/wealth) pay toward the low end; any other motivation is
## unnudged (nudge_fraction=0.0 mid-band).
static func apply_motivation_tone(base: float, motivation: String,
		nudge_fraction: float = 1.0) -> float:
	var clamped_fraction := clampf(nudge_fraction, 0.0, 1.0)
	if DESPERATE_MOTIVATIONS.has(motivation):
		return base * (1.0 + MOTIVATION_TONE_MAX_NUDGE * clamped_fraction)
	if CALCULATING_MOTIVATIONS.has(motivation):
		return base * (1.0 - MOTIVATION_TONE_MAX_NUDGE * clamped_fraction)
	return base


# ---------------------------------------------------------------------------
# §8.1 — variance, rounding, sanity bounds
# ---------------------------------------------------------------------------

## §8.1: final = base * (0.90 + rand(0, 0.20)). rng must be seeded by the
## caller for determinism (WorldGenRng.stream at setting-gen; the campaign's
## seeded stream at runtime).
static func apply_variance(base: float, rng: RandomNumberGenerator) -> float:
	var factor: float = VARIANCE_MIN + rng.randf() * (VARIANCE_MAX - VARIANCE_MIN)
	return base * factor


## §8.1 rounding: nearest 25 gp under 500, nearest 100 gp at/above 500.
## Uses banker's rounding (round-half-to-even) at the bucket boundary.
static func round_to_bucket(value: float) -> int:
	var bucket: int = ROUND_BUCKET_SMALL if value < ROUND_BUCKET_THRESHOLD else ROUND_BUCKET_LARGE
	var units: float = value / float(bucket)
	return XPAwardCalculator.bankers_round(units) * bucket


## §8.1 sanity bounds: clamp to [MIN_GOLD_REWARD, MAX_GOLD_REWARD].
static func clamp_gold_bounds(value: int) -> int:
	return clampi(value, MIN_GOLD_REWARD, MAX_GOLD_REWARD)


# ---------------------------------------------------------------------------
# §8.6 — affordability clamp (RAW-bounded)
# ---------------------------------------------------------------------------

enum GiverKind { RULER, PERSONAL, FACTION, ONE_TIME }

## §8.6: clamp a proposed gold reward to what the giver can actually afford.
## - RULER: <= 10% of (monthly_domain_income * 12), a year's discretionary spend.
## - PERSONAL: <= the questgiver's personal-wealth band (personal_wealth_cap).
## - FACTION: <= the org treasury's headroom (treasury_headroom_gp).
## - ONE_TIME (domain grants, political favors): no income cap — returns
##   proposed_gold unchanged (the caller should not route those reward forms
##   here in the first place; included for completeness/documentation).
## Returns the clamped gold value; `exceeded` is true when the clamp fired
## (caller substitutes a political favor / future promise per §8.6).
static func clamp_affordability(proposed_gold: int, giver_kind: int,
		monthly_domain_income: int = 0, personal_wealth_cap: int = 0,
		treasury_headroom_gp: int = 0) -> Dictionary:
	var cap: int
	match giver_kind:
		GiverKind.RULER:
			cap = XPAwardCalculator.bankers_round(
				float(monthly_domain_income) * 12.0 * RULER_ANNUAL_DISCRETIONARY_FRACTION)
		GiverKind.PERSONAL:
			cap = personal_wealth_cap
		GiverKind.FACTION:
			cap = treasury_headroom_gp
		GiverKind.ONE_TIME:
			return {"gold": proposed_gold, "exceeded": false}
		_:
			cap = proposed_gold
	if proposed_gold <= cap:
		return {"gold": proposed_gold, "exceeded": false}
	return {"gold": cap, "exceeded": true}


# ---------------------------------------------------------------------------
# §8.2 — reward XP (ruled: XP = total_gp_value on disbursement)
# ---------------------------------------------------------------------------

## §8.2: reward XP equals the reward's total_gp_value, EXCEPT domain grants
## (reward_type == "domain") are XP-exempt (a domain grants its own passive
## XP through domain play; counting its gp-equivalent would double-count,
## §8.8). Honors a per-quest xp_eligible override when explicitly false.
static func reward_xp(total_gp_value: int, reward_type: String, xp_eligible: bool = true) -> int:
	if reward_type == "domain":
		return 0
	if not xp_eligible:
		return 0
	return total_gp_value


# ---------------------------------------------------------------------------
# §8.8 — domain-grant valuation (display only; never XP)
# ---------------------------------------------------------------------------

## §8.8: domain_gp_equivalent = stronghold_value + (estimated_families *
## monthly_income_per_family * 12). Display/sort only — never disbursed as
## gold, never counted as reward XP (see reward_xp() above).
static func domain_gp_equivalent(stronghold_value: int, estimated_families: int,
		monthly_income_per_family: float) -> int:
	var families_income := float(estimated_families) * monthly_income_per_family * 12.0
	return XPAwardCalculator.bankers_round(float(stronghold_value) + families_income)


# ---------------------------------------------------------------------------
# §8.4 — political favor GP-equivalent band (Appendix B.1)
# ---------------------------------------------------------------------------

const POLITICAL_FAVOR_MIN_GP: int = 1000
const POLITICAL_FAVOR_MAX_GP: int = 5000

## §8.4/Appendix B.1: political favors are display/sort-only GP-equivalents
## in the 1,000-5,000 gp band, positioned by giver tier_fraction in [0,1]
## (0 = lowest tier giver, 1 = highest).
static func political_favor_gp_equivalent(tier_fraction: float) -> int:
	var clamped := clampf(tier_fraction, 0.0, 1.0)
	var value: float = POLITICAL_FAVOR_MIN_GP + \
		(POLITICAL_FAVOR_MAX_GP - POLITICAL_FAVOR_MIN_GP) * clamped
	return round_to_bucket(value)
