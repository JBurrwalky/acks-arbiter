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

# Gradient-aware bands. The elevation TAG is driven by local RELIEF (GeoField.slope
# = max-neighbour Δheight, raw 0-1 units), NOT absolute height: a prominent steep
# peak reads as mountains, a flat-topped high PLATEAU reads as flat (walkable
# ground). ACKS keeps only 3 elevation tags; plateau vs plains, basin, mesa etc. are
# a region-painting concern that reads the preserved elevation_raw, not the tag.
# Calibrated to the field's land-relief distribution (tools/geo_slope_stats.gd):
# p50≈0.056, p74≈0.085, p88≈0.111 -> ~12% mountains / ~26% hills / ~62% flat.
const MTN_SLOPE := 0.111      # steep crest -> mountains (~top 12% of land relief)
const HILL_SLOPE := 0.072     # rolling -> hills (next ~26%)


## Height-only tag (legacy / fallback for callers without a relief signal).
static func _elevation_tag(elev: float) -> String:
	if elev >= MOUNTAINS_THRESHOLD:
		return "mountains"
	if elev >= HILLS_THRESHOLD:
		return "hills"
	return "flat"


## Gradient-aware tag: local relief -> flat | hills | mountains. [param height] is
## the absolute 0-1 elevation; it is intentionally NOT used for the tag (a high flat
## plateau must stay "flat") — it rides through elevation_raw for region painting.
static func elevation_tag_for(height: float, slope: float) -> String:
	if slope >= MTN_SLOPE:
		return "mountains"
	if slope >= HILL_SLOPE:
		return "hills"
	return "flat"
