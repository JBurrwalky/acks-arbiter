class_name LevelElevationRoller
extends RefCounted

## Pure-function implementation of `gdd-urban-growth-stocking.md` §5.2.2
## within-band level elevation (v1.14).
##
## When a settlement is mid-way through its population sub-band (e.g. a
## Class IV town at 932 of 625-1249 families = ~50% band progress), the
## L3+ NPCs stocked at emergence get a chance of being elevated by 1+
## levels to reflect the settlement's near-readiness for the next sub-band.
##
## Procedure (per GDD §5.2.2):
##   total_boost = 0
##   for tier in [1, 2, 3, 4, ...]:
##     chance = band_progress × 0.5^tier
##     if rng.randf() < chance:
##       total_boost += 1
##     else:
##       break  # first failed roll stops the chain
##   NPC.level += total_boost
##
## Notes:
##   * band_progress is clamped to [0.0, 1.0] before use.
##   * The chain stops at the first failed roll — recursive halving makes
##     each successive tier exponentially less likely.
##   * Hard cap at `_MAX_TIER` (10) to guarantee termination even under
##     pathological RNG.
##   * At band_progress=1.0 the expected boost is ~1 level (per the GDD
##     §5.2.2.2 design rationale — the series converges to band_progress).

const _MAX_TIER: int = 10


## Apply the §5.2.2 elevation chain to a base level. Returns the new level
## (>= base_level always; equal when band_progress==0 or all rolls fail).
static func apply_elevation(
	base_level: int,
	band_progress: float,
	rng: RandomNumberGenerator,
) -> int:
	if base_level <= 0:
		return base_level
	var p: float = clampf(band_progress, 0.0, 1.0)
	if p <= 0.0:
		return base_level
	var total_boost: int = 0
	for tier in range(1, _MAX_TIER + 1):
		var chance: float = p * pow(0.5, tier)
		if rng.randf() < chance:
			total_boost += 1
		else:
			break
	return base_level + total_boost


## Compute band_progress from urban_families and the sub-band's min/max.
## Equivalent to `clampf((urban_families - band_min) / (band_max - band_min), 0.0, 1.0)`.
## Returns 0.0 if the band is degenerate (max <= min).
static func band_progress(
	urban_families: int,
	band_min: int,
	band_max: int,
) -> float:
	if band_max <= band_min:
		return 0.0
	var raw: float = float(urban_families - band_min) / float(band_max - band_min)
	return clampf(raw, 0.0, 1.0)
