class_name HeightmapGenerator
extends RefCounted

## Shared elevation-tag utility. The legacy hex-native Layer-1 generation (noise
## heightmap + continental shaping + vertex-walk river tracing) was RETIRED
## 2026-06-25 — continuous-geography (GeoFieldGenerator / GeoFieldToGrid) is the
## only world-gen. What survives here is the elevation-band threshold + classifier
## that the field-first engine (GeoFieldSampler, GeoClimateGenerator) and tests reuse.
## (Class name kept to avoid churn at the ~8 call sites; it is now a util, not a
## generator — a rename is a future cleanup.)

# Elevation-tag bands on the shaped 0-1 heightmap (gdd-terrain-system.md §8).
const HILLS_THRESHOLD := 0.55
const MOUNTAINS_THRESHOLD := 0.75

# Terrain-aware bands. The elevation TAG combines THREE signals, not absolute
# height alone (which made a flat-topped high plateau read as mountains):
#   * slope      — GeoField.slope, immediate relief (max-neighbour Δheight).
#   * prominence — GeoField.prominence, rise above the local valley floor (~18mi).
#   * height     — absolute 0-1 elevation, used ONLY as a gate on mountains.
# Rule (gdd ruling 2026-06-26):
#   mountains = high enough (height ≥ MTN_HEIGHT_GATE) AND (steep OR prominent)
#   hills     = steep-ish (slope) — NO height gate; foothills run low
#   flat      = everything else (plains if low, plateau if high — region painting
#               reads elevation_raw to tell those apart; not a mechanical tag).
# The gate sits at raw 0.72 ≈ 1,300 m above the lowland plains (climate lapse
# anchor: (0.72−0.55)/0.45 × 3,500 m). A steep-but-low coastal ridge therefore
# reads as hills, not mountains. Prominence participates ONLY in the mountains
# rule (catching a smooth-but-towering massif slope misses, and — via the same
# medium-scale window — staying low on a bump that merely sits on a high plateau);
# it is deliberately NOT a hills signal, because median land prominence is ~0.09,
# so any hills-prominence gate floods half the map. Calibrated by geo_slope_stats:
# resulting split (large map, 3 seeds) ≈ 59% flat / 30% hills / 11% mountains.
const MTN_HEIGHT_GATE := 0.72  # below this, terrain is never "mountains"
const MTN_SLOPE := 0.111       # steep crest -> mountains (with the height gate)
const HILL_SLOPE := 0.072      # rolling -> hills
const MTN_PROM := 0.150        # smooth-but-towering massif -> mountains (with gate)


## Height-only tag (legacy / fallback for callers without relief signals).
static func _elevation_tag(elev: float) -> String:
	if elev >= MOUNTAINS_THRESHOLD:
		return "mountains"
	if elev >= HILLS_THRESHOLD:
		return "hills"
	return "flat"


## Terrain-aware tag: combine height-gate + slope + prominence -> flat | hills |
## mountains. [param height] gates mountains only; [param slope] and [param
## prominence] are the two relief signals (immediate and medium-scale).
static func elevation_tag_for(height: float, slope: float, prominence: float) -> String:
	if height >= MTN_HEIGHT_GATE and (slope >= MTN_SLOPE or prominence >= MTN_PROM):
		return "mountains"
	if slope >= HILL_SLOPE:
		return "hills"
	return "flat"
