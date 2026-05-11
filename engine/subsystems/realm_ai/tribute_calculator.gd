class_name TributeCalculator
extends RefCounted

## Per acore_axioms_strongholds_and_domains.xml §tribute L286-351 +
## §tribute_inefficiency L398-409.
##
## Computes the gold-piece tribute that flows monthly from a vassal to its
## liege based on realm size. The base value comes from the precise optional
## formula `tribute_base_gp = round(18 × realm_families^0.6)` per
## §precise_optional_formula L299, which is consistent with the lookup table
## §tribute_by_realm_families L300-350 within rounding.
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
##   compute_tribute_base_gp(realm_families) -> int
##     Returns 18 × realm_families^0.6 with banker's rounding.
##   efficiency_factor(direct_vassal_count) -> float
##     Returns the RAW table fraction (1.0, 0.66, 0.50, 0.33, 0.20, 0.10,
##     0.05, 0.01).
##   compute_tribute_received_gp(realm_families, direct_vassal_count) -> int
##     base × efficiency, banker's rounded.
##   describe(realm_families, direct_vassal_count) -> Dictionary
##     {base_gp, efficiency_factor, efficiency_pct, efficiency_band_label,
##      received_gp}
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

static func compute_tribute_base_gp(realm_families: int) -> int:
	if realm_families <= 0:
		return 0
	# Precise optional formula: 18 × families^0.6, banker's rounded.
	var raw: float = 18.0 * pow(float(realm_families), 0.6)
	return _bankers_round(raw)


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


static func compute_tribute_received_gp(realm_families: int, direct_vassal_count: int) -> int:
	var base: int = compute_tribute_base_gp(realm_families)
	if base <= 0:
		return 0
	var factor: float = efficiency_factor(direct_vassal_count)
	return _bankers_round(float(base) * factor)


static func describe(realm_families: int, direct_vassal_count: int) -> Dictionary:
	var base: int = compute_tribute_base_gp(realm_families)
	var factor: float = efficiency_factor(direct_vassal_count)
	var received: int = _bankers_round(float(base) * factor)
	return {
		"base_gp": base,
		"efficiency_factor": factor,
		"efficiency_pct": int(round(factor * 100.0)),
		"efficiency_band_label": efficiency_band_label(direct_vassal_count),
		"received_gp": received,
		"realm_families": realm_families,
		"direct_vassal_count": direct_vassal_count,
	}


# ---------------------------------------------------------------------------
# Banker's rounding (round half to even) — per CLAUDE.md core principle
# ---------------------------------------------------------------------------

static func _bankers_round(value: float) -> int:
	if not is_finite(value):
		return 0
	var floor_v: int = int(floor(value))
	var frac: float = value - float(floor_v)
	# Tolerance for floating-point .5 detection.
	var EPS: float = 1e-9
	if absf(frac - 0.5) < EPS:
		# Round to even.
		if floor_v % 2 == 0:
			return floor_v
		else:
			return floor_v + 1
	if frac < 0.5:
		return floor_v
	return floor_v + 1
