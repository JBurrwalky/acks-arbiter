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


static func _elevation_tag(elev: float) -> String:
	if elev >= MOUNTAINS_THRESHOLD:
		return "mountains"
	if elev >= HILLS_THRESHOLD:
		return "hills"
	return "flat"
