class_name MathUtils
extends RefCounted

## Shared numeric helpers. The banker's-rounding helper is the ONE canonical
## round-half-to-even used across ACKS Arbiter (CLAUDE.md core principle;
## docs/coding_conventions.md §3.3). Prior to the Faction Framework FF-1 build
## (2026-07-07) two private copies existed (XpAwardCalculator.bankers_round,
## TreasurePlacementService._bankers_round) and several call sites hand-rolled
## it or leaned on roundi() — which is WRONG (roundi rounds half AWAY from zero).
## New code should call MathUtils.bankers_round; the two legacy copies delegate
## here where practical.


## Round half to even (Banker's rounding). Required everywhere a value rounds in
## ACKS Arbiter, except the rare RAW-mandated round-down/round-up exceptions
## documented in coding_conventions.md §3.3 (cite the RAW rule at the call site
## and use floori()/ceili() there instead).
##
## NOTE: GDScript's roundi() rounds half AWAY from zero — that is NOT banker's
## rounding. Only exact halves (…, -1.5, -0.5, 0.5, 1.5, …) differ; everything
## else matches roundi().
static func bankers_round(value: float) -> int:
	var floored: int = int(floor(value))
	var frac: float = value - float(floored)
	# Small epsilon absorbs float representation error near the exact half.
	if absf(frac - 0.5) < 0.000001:
		# Exactly half — round to the even neighbor.
		if floored % 2 == 0:
			return floored
		return floored + 1
	return roundi(value)
