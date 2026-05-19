class_name DomainMoraleResolver
extends RefCounted

## Domain morale resolver per `acore_axioms_strongholds_and_domains.xml` §morale
## L412-609. Computes both base morale (the deterministic floor) and current
## morale (a 2d6 monthly drift around the base, modified by event log).
##
## Dice are injected: `resolve_current_morale` takes the rolled 2d6 value as
## a parameter so the handler / tests own the RNG. This keeps the resolver
## a pure deterministic function for unit testing.


# Income bands for the personal_authority table (§personal_authority L433).
# Each entry is the inclusive maximum CP of monthly domain income for that band
# (RAW values × 100). An income greater than the last value falls into the
# final (highest) band.
const _INCOME_BAND_MAX_CP := [
	2500, 7500, 15000, 30000, 65000, 125000, 250000, 500000,
	1200000, 1800000, 4000000, 6000000, 15000000, 42500000,
]
# 15th band has no upper bound; index = _INCOME_BAND_MAX_CP.size().

# Personal-authority modifier per (level row, income-band column).
# Rows 0..14 cover level 0 (commoner) through level 14. Levels above 14 clamp
# to row 14 — the highest published row in `acore_axioms` §personal_authority L433-449.
const _PERSONAL_AUTHORITY := [
	[ 0, -1, -2, -3, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4],
	[ 1,  0, -1, -2, -3, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4],
	[ 2,  1,  0, -1, -2, -3, -4, -4, -4, -4, -4, -4, -4, -4, -4],
	[ 3,  2,  1,  0, -1, -2, -3, -4, -4, -4, -4, -4, -4, -4, -4],
	[ 4,  3,  2,  1,  0, -1, -2, -3, -4, -4, -4, -4, -4, -4, -4],
	[ 4,  4,  3,  2,  1,  0, -1, -2, -3, -4, -4, -4, -4, -4, -4],
	[ 4,  4,  4,  3,  2,  1,  0, -1, -2, -3, -4, -4, -4, -4, -4],
	[ 4,  4,  4,  4,  3,  2,  1,  0, -1, -2, -3, -4, -4, -4, -4],
	[ 4,  4,  4,  4,  4,  3,  2,  1,  0, -1, -2, -3, -4, -4, -4],
	[ 4,  4,  4,  4,  4,  4,  3,  2,  1,  0, -1, -2, -3, -4, -4],
	[ 4,  4,  4,  4,  4,  4,  4,  3,  2,  1,  0, -1, -2, -3, -4],
	[ 4,  4,  4,  4,  4,  4,  4,  4,  3,  2,  1,  0, -1, -2, -3],
	[ 4,  4,  4,  4,  4,  4,  4,  4,  4,  3,  2,  1,  0, -1, -2],
	[ 4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  3,  2,  1,  0, -1],
	[ 4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  3,  2,  1,  0],
]

# Morale-tier labels by current morale score, per §effects_of_morale L538-549.
const TIER_REBELLIOUS  := "Rebellious"
const TIER_DEFIANT     := "Defiant"
const TIER_TURBULENT   := "Turbulent"
const TIER_DEMORALIZED := "Demoralized"
const TIER_APATHETIC   := "Apathetic"
const TIER_LOYAL       := "Loyal"
const TIER_DEDICATED   := "Dedicated"
const TIER_STEADFAST   := "Steadfast"
const TIER_STALWART    := "Stalwart"

const CURRENT_MORALE_MIN := -4
const CURRENT_MORALE_MAX := 4


## Compute base morale per §base_morale_score L412-471.
## [param ruler] keys (all optional, default to neutral):
##   cha_modifier: int                     — Charisma adjustment of the ruler.
##   level: int                            — class level for personal_authority lookup.
##   has_leadership_proficiency: bool      — +1 morale.
##   alignment: String                     — "lawful", "neutral", or "chaotic".
##
## [param additional_troops_morale_bonus] is the +0/+1/+2 bonus the caller has
## already resolved against the additional-troops table per
## `acore_axioms` §additional_troops L461-464. Caller computes via
## GarrisonExpenditureCalculator.morale_incentive_bonus.
static func resolve_base_morale(
	domain: Dictionary,
	ruler: Dictionary,
	monthly_revenue_cp: int,
	stronghold_value_cp: int,
	stronghold_minimum_cp: int,
	additional_troops_morale_bonus: int
) -> int:
	var base: int = 0
	base += int(ruler.get("cha_modifier", 0))
	if bool(ruler.get("has_leadership_proficiency", false)):
		base += 1
	base += _personal_authority_modifier(int(ruler.get("level", 1)), monthly_revenue_cp)

	# Insufficient-stronghold tiered penalty per §insufficient_stronghold L452-456.
	# Tier boundaries: ½ minimum and ¼ minimum. At or above minimum: no penalty.
	if stronghold_minimum_cp > 0 and stronghold_value_cp < stronghold_minimum_cp:
		var half: int = stronghold_minimum_cp / 2
		var quarter: int = stronghold_minimum_cp / 4
		if stronghold_value_cp >= half:
			base -= 1
		elif stronghold_value_cp >= quarter:
			base -= 2
		else:
			base -= 3

	# Classification penalty per §classification_modifiers L457-460.
	var territory: String = String(domain.get("territory_type", "wilderness"))
	if territory == "borderlands":
		base -= 1
	elif territory == "wilderness":
		base -= 2

	# Additional-troops bonus per §additional_troops L461-464. Caller pre-
	# resolves the tier via GarrisonExpenditureCalculator.morale_incentive_bonus.
	base += additional_troops_morale_bonus

	# Alignment match per §alignment_and_religion L466-471.
	var ruler_align: String = String(ruler.get("alignment", "neutral"))
	var domain_align: String = String(domain.get("alignment", "neutral"))
	if ruler_align != domain_align:
		var lc_pair := (ruler_align == "lawful" and domain_align == "chaotic") \
			or (ruler_align == "chaotic" and domain_align == "lawful")
		if lc_pair:
			base -= 2
		else:
			base -= 1

	# Consecrate Ruler buff propagation (Phase 10A.2 / bucket-B Phase 2 long-tail):
	# active consecrate_ruler_buff on this domain contributes its base_morale_bonus
	# (+1 success / -1 natural-1 curse) to base morale. Wired 2026-05-19.
	base += _consecrate_ruler_base_morale_bonus(domain.get("id", ""))

	return base


## Returns the base_morale_bonus from an active consecrate_ruler_buff on this
## domain, or 0 when no active buff exists. "Active" = status='applied' AND
## expires_at_calendar_day > current_day.
static func _consecrate_ruler_base_morale_bonus(domain_id: Variant) -> int:
	if domain_id == null:
		return 0
	var did: String = str(domain_id)
	if did.is_empty():
		return 0
	var current_day: int = Timekeeping.get_total_days()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT effect_payload_json FROM pending_divine_effects
		WHERE domain_id = ?
		  AND effect_kind = 'consecrate_ruler_buff'
		  AND status = 'applied'
		  AND expires_at_calendar_day > ?
		ORDER BY applies_at_calendar_day DESC
		LIMIT 1
	""", [did, current_day]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	var raw: String = String(CampaignRepository.db.query_result[0].get("effect_payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return 0
	return int((parsed as Dictionary).get("base_morale_bonus", 0))


## Resolve a single month's current morale per §current_morale_score L473-501.
## [param roll_2d6] is the unmodified 2d6 value (caller injects from DiceSystem
## or a test fixture). Adjusted roll = 2d6 + event_modifiers_sum.
##
## Returns a Dictionary with keys:
##   roll_2d6: int                  — pristine die roll (echoed back)
##   adjusted_roll: int             — roll + modifiers
##   prior_current_morale: int
##   base_morale: int
##   current_morale: int            — capped at [-4, +4] per §domain_morale_results
##                                    and at 0 per §repression L515 if is_repressed.
##   morale_change: int             — current_morale - prior_current_morale
##   capped_by_repression: bool     — true when the cap actually clamped the value
static func resolve_current_morale(
	domain: Dictionary,
	base_morale: int,
	event_modifiers_sum: int,
	repression_bonus: int,
	is_repressed: bool,
	roll_2d6: int
) -> Dictionary:
	var prior: int = int(domain.get("morale", 0))
	var natural := roll_2d6
	var adjusted: int = natural + event_modifiers_sum + repression_bonus

	var new_morale: int = prior

	# Natural-2 / natural-12 always trigger the extreme shifts per L476-477.
	if natural == 2:
		new_morale = prior - 2
	elif natural == 12:
		new_morale = prior + 2
	elif adjusted <= 2:
		new_morale = prior - 2
	elif adjusted <= 5:
		new_morale = prior - 1
	elif adjusted <= 8:
		# Drift one toward base.
		if prior < base_morale:
			new_morale = prior + 1
		elif prior > base_morale:
			new_morale = prior - 1
		# else equal — no change.
	elif adjusted <= 11:
		new_morale = prior + 1
	else:
		new_morale = prior + 2

	# Clamp to [-4, +4] per L479-483.
	new_morale = clampi(new_morale, CURRENT_MORALE_MIN, CURRENT_MORALE_MAX)

	# Repression cap per §repression L515: current morale cannot exceed 0 while
	# repressed.
	var capped_by_repression := false
	if is_repressed and new_morale > 0:
		new_morale = 0
		capped_by_repression = true

	return {
		"roll_2d6": natural,
		"adjusted_roll": adjusted,
		"prior_current_morale": prior,
		"base_morale": base_morale,
		"current_morale": new_morale,
		"morale_change": new_morale - prior,
		"capped_by_repression": capped_by_repression,
	}


## Map a current morale score to its named tier per §effects_of_morale L538-549.
static func morale_tier(current_morale: int) -> String:
	if current_morale <= -4:
		return TIER_REBELLIOUS
	elif current_morale == -3:
		return TIER_DEFIANT
	elif current_morale == -2:
		return TIER_TURBULENT
	elif current_morale == -1:
		return TIER_DEMORALIZED
	elif current_morale == 0:
		return TIER_APATHETIC
	elif current_morale == 1:
		return TIER_LOYAL
	elif current_morale == 2:
		return TIER_DEDICATED
	elif current_morale == 3:
		return TIER_STEADFAST
	else:
		return TIER_STALWART


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _personal_authority_modifier(level: int, monthly_revenue_cp: int) -> int:
	var row: int = clampi(level, 0, _PERSONAL_AUTHORITY.size() - 1)
	var col: int = _income_band_index(monthly_revenue_cp)
	return _PERSONAL_AUTHORITY[row][col]


static func _income_band_index(monthly_revenue_cp: int) -> int:
	# Negative/zero income falls into band 0.
	for i in range(_INCOME_BAND_MAX_CP.size()):
		if monthly_revenue_cp <= _INCOME_BAND_MAX_CP[i]:
			return i
	return _INCOME_BAND_MAX_CP.size()  # the unbounded 15th band
