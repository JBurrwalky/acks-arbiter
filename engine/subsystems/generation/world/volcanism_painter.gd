class_name VolcanismPainter
extends RefCounted

## Geological-feature pass — the "volcanic peaks" placement that
## gdd-continuous-geography deferred from v1 (the deferral is recorded in
## culture_seeder._hex_matches_term). Runs as a FOLLOW-ON to region painting,
## inside the culture-seeding layer (SettingGenerator._run_culture_seeding),
## after the terrain + mountain clusters exist and before the seed state is
## persisted.
##
## A whole mountain RANGE is marked volcanic or not (the user's contract: "mark
## the RANGE as volcanic, then randomize which regions are active at the 6-mile
## level"), not scattered individual peaks. A "range" here is a connected
## component of mountain hexes — exactly the unit RegionPainter clusters, so
## this stays consistent with the named ranges. Lone peaks (a single isolated
## mountain hex) get a higher chance, since a stray volcanic cone is a classic
## landmark.
##
## The decision is stamped onto the 24-mile hex as biome_subtype =
## "mountains_volcanic". Volcanic wins over glacial ("lava melts ice"): the
## stamp overrides a pre-existing mountains_glacial subtype. The 6-mile zoom
## (RegionZoomIn) reads this stamp and randomizes which child hexes are ACTIVE
## VENTS — see RegionZoomIn._volcanic_vent_subtype.
##
## Deterministic (coding_conventions §80): every roll draws from its own
## WorldGenRng stream keyed on the component's canonical anchor hex, so
## iteration / flood-fill order never affects the outcome.

const SUBTYPE_VOLCANIC := "mountains_volcanic"

# Pointy-top hex neighbor offsets (axial), canonical order — matches RegionPainter._OFF.
const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

## Fraction of mountain RANGES (connected mountain mass, size >= RANGE_MIN) that
## are volcanic ranges.
const VOLCANIC_RANGE_CHANCE := 0.20
## Fraction of LONE PEAKS (a single isolated mountain hex) that are volcanic —
## higher than a range, per the design (a lone volcanic cone is a landmark).
const VOLCANIC_LONE_CHANCE := 0.50
## A mountain component at/above this size is a "range"; below it is a lone peak.
## Matches RegionPainter.CLUSTER_FLOOR (a 2+-hex mountain mass is a range region).
const RANGE_MIN := 2


## Stamp volcanic mountain ranges + lone peaks onto ctx.hex_grid in place.
## Reads ctx: hex_grid, width, height, campaign_seed. Records the stamped count
## in ctx["volcanic_hex_count"] for logging / tests.
static func paint(ctx: Dictionary) -> void:
	var grid: Dictionary = ctx["hex_grid"]
	var width: int = int(ctx["width"])
	var height: int = int(ctx["height"])
	var campaign_seed := int(ctx["campaign_seed"])

	var stamped := 0
	for comp in _mountain_components(grid, width, height):
		var is_lone: bool = comp.size() < RANGE_MIN
		# Canonical anchor: comp is sorted, so comp[0] is the stable top-left hex —
		# unique per component, independent of flood-fill order.
		var anchor: Vector2i = comp[0]
		var stream_name := "volcanism_lone" if is_lone else "volcanism_range"
		var rng := WorldGenRng.stream(campaign_seed, stream_name, 0,
				"%d,%d" % [anchor.x, anchor.y])
		var chance := VOLCANIC_LONE_CHANCE if is_lone else VOLCANIC_RANGE_CHANCE
		if rng.randf() < chance:
			for h in comp:
				grid[h]["biome_subtype"] = SUBTYPE_VOLCANIC  # volcanic wins over glacial
				stamped += 1
	ctx["volcanic_hex_count"] = stamped


## Connected components of mountain hexes (elevation == "mountains"), scanned in
## canonical offset order (row ASC, col ASC); each component is sorted canonically.
static func _mountain_components(grid: Dictionary, width: int, height: int) -> Array:
	var visited := {}
	var result: Array = []
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			if visited.has(key) or not _is_mountain(grid, key):
				continue
			var component: Array = []
			var queue: Array[Vector2i] = [key]
			visited[key] = true
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_front()
				component.append(cell)
				for off in _OFF:
					var n: Vector2i = cell + off
					if not visited.has(n) and _is_mountain(grid, n):
						visited[n] = true
						queue.append(n)
			component.sort_custom(_hex_sort)
			result.append(component)
	return result


static func _is_mountain(grid: Dictionary, key: Vector2i) -> bool:
	return grid.has(key) and str(grid[key].get("water", "")) == "" \
			and str(grid[key].get("elevation", "")) == "mountains"


static func _hex_sort(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
