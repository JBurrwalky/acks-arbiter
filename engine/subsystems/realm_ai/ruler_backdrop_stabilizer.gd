class_name RulerBackdropStabilizer
extends RefCounted

## The §8.4 backdrop auto-stabilize pass (gdd-ruler-ai.md; approved by
## Jedidiah 2026-06-28: backdrop realms hold steady off-camera rather than
## decay). Backdrop NPC domains take NO planner decisions — this is the cheap,
## deterministic substitute the monthly tick applies to their morale roll:
##
##   1. Garrison treated as funded to the territory minimum FOR THE ROLL —
##      the -1/gp-short penalty (acore_axioms_strongholds_and_domains.xml:486)
##      does not accrue off-camera (the dominant neglect-spiral driver).
##      Actual expenses/ledger are untouched.
##   2. Routine administration assumed: +1 to the monthly morale roll
##      (:486-502) so current morale gravitates toward base via the 6-8
##      "shift toward base" band.
##   3. Neglect morale floor: off-camera current morale does not fall below
##      Apathetic (0) from neglect alone. A domain already below 0 when it
##      left camera keeps its damage (the floor is min(prior, 0)) but cannot
##      deepen it while backdrop — PROJECT CALL interpreting §8.4. Player-
##      caused effects (pillage -4, occupation -1/mo) apply in full when the
##      Phase-8/10 columns land; today neither exists in the data model, so
##      there is nothing to exempt yet.
##   4. No discretionary activity — enforced by the caller (backdrop rulers
##      are simply not in the planner's active set).
##
## All statics are PURE (dict in, dict out) so the §8.4 mechanics unit-test
## without a DomainHandlers instance; domain_handlers wires them via the
## resolution_options() flags on _resolve_domain_month.

const OPT_ASSUME_GARRISON_FUNDED := "assume_garrison_funded"
const OPT_ASSUME_ADMINISTERED := "assume_administered"
const OPT_NEGLECT_MORALE_FLOOR := "neglect_morale_floor"

## §8.4 item 2's grant is EXACTLY the +1 monthly morale-roll modifier
## (acore_axioms_strongholds_and_domains.xml:486-502) — NOT the administer
## action's +5% domain-XP bonus. That is why the assumption is an opts flag
## consumed at the event-modifier sum, never the
## administer_domain_completed_this_month dict flag (_save_domain reads that
## flag for the XP bonus before resetting it, so faking it would leak
## phantom XP to every backdrop domain).
const ADMINISTER_MORALE_BONUS := 1


## The opts dict domain_handlers passes to _resolve_domain_month for a
## backdrop NPC domain.
static func resolution_options() -> Dictionary:
	return {
		OPT_ASSUME_GARRISON_FUNDED: true,
		OPT_ASSUME_ADMINISTERED: true,
		OPT_NEGLECT_MORALE_FLOOR: true,
	}


## §8.4 item 1: a garrison summary with the under-funding morale penalty
## suppressed (a duplicated dict; the original is untouched so expense math
## still uses real numbers).
static func adjust_garrison_summary(garrison: Dictionary) -> Dictionary:
	var adjusted: Dictionary = garrison.duplicate()
	adjusted["gp_below_minimum_per_family"] = 0
	adjusted["cp_below_minimum_per_family"] = 0
	return adjusted


## §8.4 item 3: apply the neglect floor to a resolve_current_morale result.
## Floor = min(prior current morale, 0): off-camera morale never falls below
## Apathetic FROM NEGLECT ALONE, and pre-existing damage is preserved but not
## deepened. The floor binds ONLY when the roll's event modifiers are
## non-negative — with the garrison shortfall suppressed and administration
## assumed, any remaining NEGATIVE modifier is a substantive cause (an active
## challenger's pillaging, a settled lair, punitive tax rates), which §8.4
## says applies in full ("drama stays player-driven" covers damage effects,
## not random low rolls). Known bound (PROJECT CALL): the assumed-administer
## +1 is inside the sum, so it can offset EXACTLY ONE point of substantive
## penalty (e.g. a 3gp tax rate's -1 nets to 0 and still floors) — larger
## damage (challenger -4, heavier taxes) always bypasses the floor. Returns
## a duplicated result dict with current_morale / morale_change adjusted
## (and a marker for observability).
static func apply_neglect_floor(morale_result: Dictionary, prior_morale: int,
		event_modifiers_sum: int) -> Dictionary:
	if event_modifiers_sum < 0:
		return morale_result
	var floor_morale: int = mini(prior_morale, 0)
	var current: int = int(morale_result.get("current_morale", 0))
	if current >= floor_morale:
		return morale_result
	var adjusted: Dictionary = morale_result.duplicate()
	adjusted["current_morale"] = floor_morale
	adjusted["morale_change"] = floor_morale - prior_morale
	adjusted["neglect_floor_applied"] = true
	return adjusted
