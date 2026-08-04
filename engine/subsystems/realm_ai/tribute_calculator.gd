class_name TributeCalculator
extends RefCounted

## Per acore_axioms_strongholds_and_domains.xml §tribute L286-351 +
## §tribute_inefficiency L398-409.
##
## Computes the tribute that flows monthly from a vassal to its liege based on
## realm size. The base value comes from the precise optional formula
## `tribute_base_gp = round(18 × realm_families^0.6)` per
## §precise_optional_formula L299, which is consistent with the lookup table
## §tribute_by_realm_families L300-350 within rounding.
##
## **UNITS (conventions §127, 2026-07-31):** every value this class returns is
## **copper pieces**. The RAW gp coefficient 18 is converted at the point of
## entry (18 gp → 1800 cp) and the result is banker's-rounded once, at cp
## precision. Callers must NOT multiply by 100 — that double conversion was the
## bug this API replaces. The pre-2026-07-31 `*_gp` entry points are gone; a
## caller still doing `compute_tribute_base_gp(...) * 100` will fail to parse
## rather than silently inflate by 100×.
##
## The amount the liege actually RECEIVES is reduced by a tribute-efficiency
## factor based on the liege's number of direct vassals per
## §tribute_inefficiency L398-409. **`[RAW PATCH RESOLVED 2026-05-06]`**: the
## source XML at L406 reads "17-36 = 50%" leaving an algebraic gap from 37
## through 63 between that band's lower bound and the next band's lower
## bound (64). Per logarithmic-scaling analysis this is treated as a
## digit-transposition typo (3↔6) and read as "17-63 = 50%". Implementation
## encodes this corrected reading; the source XML is unchanged per the
## sacred-rules constraint.
##
## Public API:
##   compute_tribute_base_cp(realm_families) -> int
##     Returns 1800 × realm_families^0.6 cp with banker's rounding.
##   efficiency_factor(direct_vassal_count) -> float
##     Returns the RAW table fraction (1.0, 0.66, 0.50, 0.33, 0.20, 0.10,
##     0.05, 0.01).
##   compute_tribute_received_cp(realm_families, direct_vassal_count) -> int
##     base × efficiency, banker's rounded.
##   describe(realm_families, direct_vassal_count) -> Dictionary
##     {base_cp, efficiency_factor, efficiency_pct, efficiency_band_label,
##      received_cp}
##
## All rounding uses banker's rounding (round half to even) per the project's
## CLAUDE.md core principle.

const _EFFICIENCY_TABLE := [
	{"min":     0, "max":     8, "factor": 1.00, "label": "≤8 vassals"},
	{"min":     9, "max":    16, "factor": 0.66, "label": "9–16 vassals"},
	# RAW PATCH RESOLVED 2026-05-06: source XML L406 reads "17-36"; treated as
	# "17-63" per digit-transposition correction in domain-roadmap-corrected.md.
	{"min":    17, "max":    63, "factor": 0.50, "label": "17–63 vassals"},
	{"min":    64, "max":   216, "factor": 0.33, "label": "64–216 vassals"},
	{"min":   217, "max":  1024, "factor": 0.20, "label": "217–1024 vassals"},
	{"min":  1025, "max":  4095, "factor": 0.10, "label": "1025–4095 vassals"},
	{"min":  4096, "max": 16384, "factor": 0.05, "label": "4096–16384 vassals"},
	{"min": 16385, "max": -1,    "factor": 0.01, "label": "16385+ vassals"},
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## RAW §precise_optional_formula L299: `18gp × realm_families^0.6`. The gp
## coefficient is converted to cp here, at the point of entry (conventions
## §127), so the whole computation lands as an integer number of copper pieces
## with a single banker's rounding at cp precision.
const _TRIBUTE_COEFFICIENT_CP := 1800.0  # RAW 18 gp × 100
const _TRIBUTE_EXPONENT := 0.6


static func compute_tribute_base_cp(realm_families: int) -> int:
	if realm_families <= 0:
		return 0
	var raw: float = _TRIBUTE_COEFFICIENT_CP * pow(float(realm_families), _TRIBUTE_EXPONENT)
	return MathUtils.bankers_round(raw)


static func efficiency_factor(direct_vassal_count: int) -> float:
	var n: int = maxi(0, direct_vassal_count)
	for entry in _EFFICIENCY_TABLE:
		var lo: int = int(entry["min"])
		var hi: int = int(entry["max"])
		if hi == -1:
			# Open-ended top tier.
			if n >= lo:
				return float(entry["factor"])
		else:
			if n >= lo and n <= hi:
				return float(entry["factor"])
	return 1.0  # Fallback for n == 0 / negative.


static func efficiency_band_label(direct_vassal_count: int) -> String:
	var n: int = maxi(0, direct_vassal_count)
	for entry in _EFFICIENCY_TABLE:
		var lo: int = int(entry["min"])
		var hi: int = int(entry["max"])
		if hi == -1:
			if n >= lo:
				return String(entry["label"])
		else:
			if n >= lo and n <= hi:
				return String(entry["label"])
	return "≤8 vassals"


static func compute_tribute_received_cp(realm_families: int, direct_vassal_count: int) -> int:
	var base_cp: int = compute_tribute_base_cp(realm_families)
	if base_cp <= 0:
		return 0
	var factor: float = efficiency_factor(direct_vassal_count)
	return MathUtils.bankers_round(float(base_cp) * factor)


static func describe(realm_families: int, direct_vassal_count: int) -> Dictionary:
	var base_cp: int = compute_tribute_base_cp(realm_families)
	var factor: float = efficiency_factor(direct_vassal_count)
	var received_cp: int = MathUtils.bankers_round(float(base_cp) * factor)
	return {
		"base_cp": base_cp,
		"efficiency_factor": factor,
		"efficiency_pct": int(round(factor * 100.0)),
		"efficiency_band_label": efficiency_band_label(direct_vassal_count),
		"received_cp": received_cp,
		"realm_families": realm_families,
		"direct_vassal_count": direct_vassal_count,
	}


# Banker's rounding routes through MathUtils.bankers_round — the ONE canonical
# round-half-to-even per conventions §116 (this file used the legacy
# XPAwardCalculator delegate until the 2026-07-31 cp pass). Every caller
# pre-guards its inputs (`if realm_families <= 0: return 0`), so the missing
# `is_finite` guard on the shared helper is not reachable from here.
