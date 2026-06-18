class_name RegionPainter
extends RefCounted

## Region painting Phase 1 — geometric detection (gdd-region-painting.md §4).
## Runs after Layer 2 (depends only on terrain) and produces UNNAMED region
## records: continents, terrain clusters (with sub-splits + anomalies),
## coastal/landform features, and hydronyms. Naming is Phase 2 (Stage 6).
##
## All detectors are deterministic flood-fills/scans in canonical hex order
## (r ASC, q ASC). Region ids are deterministic sequence ids ("reg_0001") in
## detector order. Significance (§3.3) is computed with the context term = 0;
## Stage 6 re-scores it once cultures and history exist.
##
## Floors per §4.6 (Dense default; Sparse doubles them and drops anomalies
## and sub-splits).

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

# §4.1 continent thresholds (coarse).
const CONTINENT_MIN := 100
const MAJOR_ISLE_MIN := 20

# §4.2 terrain clusters.
const CLUSTER_FLOOR := 2
# A flat-band clear cluster counts as a basin (low + enclosed) rather than open
# plains when at least this fraction of its land-ring is higher ground (§4.2 /
# §5.1 "low + vale/plain").
const BASIN_ENCLOSURE_FRACTION := 0.6
const SUB_SPLIT_THRESHOLD := 12
const SUB_SPLIT_MIN_PART := 4
const SUB_SPLIT_MAX_DEPTH := 2
const ANOMALY_MAX_PATCH := 4
const ANOMALY_RING_DOMINANCE := 5
const ANOMALY_KEEP_DIVISOR := 150

# §4.6 coastal/landform floors.
const PENINSULA_MIN_LAND := 4
const NECK_MAX_WIDTH := 2
const ISTHMUS_MIN_MASS := 6
const STRAIT_MIN_MASS := 6
const BAY_MIN := 2
const GULF_MIN := 6
const ARCHIPELAGO_MIN_ISLANDS := 3
const ARCHIPELAGO_SPACING := 2

# §4.6 hydronym floors.
const RIVER_MIN_EDGES := 3
const RIVER_SYSTEM_MIN_SOURCES := 3  # trunk + ≥2 tributaries
const SEA_MIN := 8
const OCEAN_MIN := 80
const LAKELAND_MIN_LAKES := 3
const LAKELAND_SPACING := 2


## Detect all Phase-1 regions from ctx (hex_grid, river_edges, width, height,
## params). Returns rows per SettingRepository.REGION_COLUMNS; also stores
## them in ctx["regions"].
static func run_phase1(ctx: Dictionary) -> Array:
	var grid: Dictionary = ctx["hex_grid"]
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var params: SettingParameters = ctx["params"]
	var sparse: bool = params.naming_density == "sparse"
	var floor_mult := 2 if sparse else 1

	var state := {
		"grid": grid, "width": width, "height": height,
		"sparse": sparse, "floor_mult": floor_mult,
		"regions": [],     # working region dicts
		"next_seq": 1,
		"river_edge_set": {},
	}
	# The river-seam splitter (§4.2) needs the edge set before clusters run.
	for row in ctx["river_edges"]:
		state["river_edge_set"]["%d,%d,%d"
				% [int(row["hex_q"]), int(row["hex_r"]), int(row["edge"])]] = true

	var land_components := _detect_continents(state)
	_detect_terrain_clusters(state)
	if not sparse:
		_detect_anomalies(state)
	_detect_coastal_features(state, land_components)
	_detect_hydronyms(state, ctx["river_edges"])
	_assign_continent_parents(state, land_components)
	_compute_significance(state)
	_compute_overlaps(state)

	var rows: Array = []
	for region in state["regions"]:
		rows.append(_to_row(region))
	ctx["regions"] = rows
	return rows


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

static func _new_region(state: Dictionary, layer: String, subtype: String,
		hexes: Array) -> Dictionary:
	var sorted_hexes := hexes.duplicate()
	sorted_hexes.sort_custom(_hex_sort)
	var region := {
		"id": "reg_%04d" % int(state["next_seq"]),
		"layer": layer,
		"subtype": subtype,
		"hexes": sorted_hexes,
		"parent_id": "",
		"overlaps": [],
		"significance": 0.0,
		"prominence": 0.5,
	}
	state["next_seq"] = int(state["next_seq"]) + 1
	state["regions"].append(region)
	return region


static func _hex_sort(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _is_land(grid: Dictionary, key: Vector2i) -> bool:
	return grid.has(key) and grid[key]["water"] == ""


## Connected components over the hexes for which [param predicate] holds,
## scanning in canonical order. Returns Array of Array[Vector2i] (each sorted).
static func _components(state: Dictionary, predicate: Callable) -> Array:
	var grid: Dictionary = state["grid"]
	var visited := {}
	var result: Array = []
	for row in range(int(state["height"])):
		for col in range(int(state["width"])):
			var key := WorldGrid.offset_to_axial(col, row)
			if visited.has(key) or not predicate.call(key):
				continue
			var component: Array = []
			var queue: Array[Vector2i] = [key]
			visited[key] = true
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_front()
				component.append(cell)
				for off in _OFF:
					var n: Vector2i = cell + off
					if grid.has(n) and not visited.has(n) and predicate.call(n):
						visited[n] = true
						queue.append(n)
			component.sort_custom(_hex_sort)
			result.append(component)
	return result


# ---------------------------------------------------------------------------
# §4.1 Continents and landmasses
# ---------------------------------------------------------------------------

## Returns the land components (Array of {hexes, region_id-or-''}) for reuse
## by the coastal detectors.
static func _detect_continents(state: Dictionary) -> Array:
	var grid: Dictionary = state["grid"]
	var components := _components(state, func(key: Vector2i) -> bool:
		return _is_land(grid, key))
	var floor_mult: int = state["floor_mult"]
	var out: Array = []
	for component in components:
		var entry := {"hexes": component, "region_id": "", "is_island": false}
		if component.size() >= CONTINENT_MIN * floor_mult:
			entry["region_id"] = _new_region(state, "continent", "continent", component)["id"]
		elif component.size() >= MAJOR_ISLE_MIN * floor_mult:
			entry["region_id"] = _new_region(state, "continent", "major_isle", component)["id"]
		else:
			entry["is_island"] = true  # handled by §4.3 islands/archipelagos
		out.append(entry)
	return out


# ---------------------------------------------------------------------------
# §4.2 Terrain clusters + sub-split + anomalies
# ---------------------------------------------------------------------------

## Cluster family of a land hex: ranges trump cover (a mountain forest reads
## as range at the coarse scale); remaining hexes cluster by ground cover. A
## flat-band "plains" COMPONENT enclosed by higher ground is promoted to "basin"
## in _detect_terrain_clusters.
##
## NOTE (2026-06-13): plateau detection is DEFERRED. The elevation tag is a
## 3-band roughness/height proxy (mountains/hills/flat) derived from
## elevation_raw magnitude — "hills" means rugged moderate terrain, NOT flat
## high ground. A real plateau is flat ground at high elevation, which needs a
## LOCAL-FLATNESS measure (low elevation_raw variance across the ring) gated on
## high elevation_raw — the raw height is already persisted per hex, so this is
## a future flatness-pass, not a persistence change. Until then clear ground is
## just plains/basin (see gdd-region-painting §4.2 deferral note).
static func _cluster_family(grid: Dictionary, key: Vector2i) -> String:
	if not _is_land(grid, key):
		return ""
	var hex: Dictionary = grid[key]
	if hex["elevation"] == "mountains":
		return "range"
	match hex["biome"]:
		"woods", "jungle":
			return "forest"
		"desert":
			return "desert"
		"swamp":
			return "swamp"
		"clear":
			return "plains"
	return ""


static func _detect_terrain_clusters(state: Dictionary) -> void:
	var grid: Dictionary = state["grid"]
	var floor_mult: int = state["floor_mult"]
	# §4.2 families: range, forest, desert, plains, swamp; basin = an enclosed
	# flat+clear "plains" component, promoted below. (plateau deferred — see
	# _cluster_family.)
	for family in ["range", "forest", "desert", "plains", "swamp"]:
		var components := _components(state, func(key: Vector2i) -> bool:
			return _cluster_family(grid, key) == family)
		for component in components:
			if component.size() < CLUSTER_FLOOR * floor_mult:
				continue
			var subtype: String = family
			if family == "plains" and _is_enclosed_basin(grid, component):
				subtype = "basin"
			var region := _new_region(state, "terrain_cluster", subtype, component)
			if not state["sparse"]:
				_sub_split(state, region, component, 1)


## §4.2 / §5.1: a flat-band clear cluster ringed predominantly by higher ground
## (hills/mountains) is a basin (low + enclosed); an open lowland stays plains.
## Deterministic — the ring is a SET and the fraction is order-independent.
static func _is_enclosed_basin(grid: Dictionary, component: Array) -> bool:
	var in_comp := {}
	for h in component:
		in_comp[h] = true
	var ring := {}
	for h in component:
		for off in _OFF:
			var nb: Vector2i = h + off
			if in_comp.has(nb):
				continue
			if _is_land(grid, nb):
				ring[nb] = true
	if ring.is_empty():
		return false  # touches only water/the map edge — a coastal plain
	var higher := 0
	for nb in ring:
		var e: String = grid[nb]["elevation"]
		if e == "hills" or e == "mountains":
			higher += 1
	return float(higher) / float(ring.size()) >= BASIN_ENCLOSURE_FRACTION


## §4.2 sub-split: clusters > 12 hexes split along natural seams — a river
## crossing the cluster, an elevation step, or a subtype boundary — into
## parts ≥ 4 hexes, recursing to depth 2. Parts nest under the parent.
static func _sub_split(state: Dictionary, parent: Dictionary, hexes: Array,
		depth: int) -> void:
	if depth > SUB_SPLIT_MAX_DEPTH or hexes.size() <= SUB_SPLIT_THRESHOLD:
		return
	var parts := _try_split(state, hexes)
	if parts.is_empty():
		return
	for part in parts:
		var sub := _new_region(state, "terrain_cluster",
				str(parent["subtype"]) + "_part", part)
		sub["parent_id"] = parent["id"]
		_sub_split(state, sub, part, depth + 1)


## First seam that yields ≥ 2 parts all ≥ SUB_SPLIT_MIN_PART, else [].
static func _try_split(state: Dictionary, hexes: Array) -> Array:
	var grid: Dictionary = state["grid"]
	var hex_set := {}
	for h in hexes:
		hex_set[h] = true
	# Seam 1: a river crossing the cluster — cut adjacency across river edges.
	var river_cut: Dictionary = state.get("river_edge_set", {})
	if not river_cut.is_empty():
		var parts := _components_within(hexes, hex_set, func(a: Vector2i, b: Vector2i) -> bool:
			return not _has_river_between(river_cut, a, b))
		if _valid_split(parts):
			return parts
	# Seam 2: elevation step (≥ 1 band difference).
	var parts_e := _components_within(hexes, hex_set, func(a: Vector2i, b: Vector2i) -> bool:
		return grid[a]["elevation"] == grid[b]["elevation"])
	if _valid_split(parts_e):
		return parts_e
	# Seam 3: biome-subtype boundary.
	var parts_s := _components_within(hexes, hex_set, func(a: Vector2i, b: Vector2i) -> bool:
		return grid[a]["biome_subtype"] == grid[b]["biome_subtype"])
	if _valid_split(parts_s):
		return parts_s
	return []


static func _valid_split(parts: Array) -> bool:
	if parts.size() < 2:
		return false
	for part in parts:
		if part.size() < SUB_SPLIT_MIN_PART:
			return false
	return true


## Connected components restricted to [param hexes], where adjacency between
## two member hexes additionally requires [param link] to hold.
static func _components_within(hexes: Array, hex_set: Dictionary, link: Callable) -> Array:
	var visited := {}
	var result: Array = []
	for start in hexes:
		if visited.has(start):
			continue
		var component: Array = []
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			component.append(cell)
			for off in _OFF:
				var n: Vector2i = cell + off
				if hex_set.has(n) and not visited.has(n) and link.call(cell, n):
					visited[n] = true
					queue.append(n)
		component.sort_custom(_hex_sort)
		result.append(component)
	return result


static func _has_river_between(river_edge_set: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	for e in range(6):
		if a + _OFF[e] == b:
			return river_edge_set.has("%d,%d,%d" % [a.x, a.y, e]) \
					or river_edge_set.has("%d,%d,%d" % [b.x, b.y, (e + 3) % 6])
	return false


## §4.2 geological-anomaly detector: 1-4 contiguous hexes whose family
## differs from the dominant family of ≥ 5 of the 6-hex ring, or whose
## elevation differs by ≥ 2 bands from every ring hex. Keep top hexes/150
## by contrast × rarity.
static func _detect_anomalies(state: Dictionary) -> void:
	var grid: Dictionary = state["grid"]
	var width: int = state["width"]
	var height: int = state["height"]
	# Family frequency over land (for the rarity term).
	var family_counts := {}
	var land_total := 0
	for row in range(height):
		for col in range(width):
			var f := _cluster_family(grid, WorldGrid.offset_to_axial(col, row))
			if f != "":
				family_counts[f] = int(family_counts.get(f, 0)) + 1
				land_total += 1
	if land_total == 0:
		return

	var elevation_band := {"flat": 0, "hills": 1, "mountains": 2}
	var seeds: Array = []  # {hex, score}
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			var family := _cluster_family(grid, key)
			if family == "":
				continue
			var ring_families := {}
			var ring_land := 0
			var elev_contrast := true
			var my_band: int = elevation_band[grid[key]["elevation"]]
			for off in _OFF:
				var n: Vector2i = key + off
				var nf := _cluster_family(grid, n)
				if nf == "":
					elev_contrast = false  # ring must be all land for the elevation rule
					continue
				ring_land += 1
				ring_families[nf] = int(ring_families.get(nf, 0)) + 1
				if absi(int(elevation_band[grid[n]["elevation"]]) - my_band) < 2:
					elev_contrast = false
			var dominant := ""
			var dominant_count := 0
			for f in ring_families:
				if int(ring_families[f]) > dominant_count:
					dominant_count = int(ring_families[f])
					dominant = f
			var family_anomaly: bool = dominant != "" and dominant != family \
					and dominant_count >= ANOMALY_RING_DOMINANCE
			if not family_anomaly and not (elev_contrast and ring_land == 6):
				continue
			var contrast := float(dominant_count) / 6.0 if family_anomaly else 1.0
			var rarity := 1.0 - float(family_counts.get(family, 0)) / float(land_total)
			seeds.append({"hex": key, "score": contrast * rarity})

	# Grow seeds into contiguous same-family patches ≤ 4 hexes; keep top N.
	seeds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return float(a["score"]) > float(b["score"])
		return _hex_sort(a["hex"], b["hex"]))
	var keep := maxi(width * height / ANOMALY_KEEP_DIVISOR, 1)
	var claimed := {}
	var made := 0
	for seed in seeds:
		if made >= keep:
			break
		var start: Vector2i = seed["hex"]
		if claimed.has(start):
			continue
		var family := _cluster_family(grid, start)
		var patch: Array = [start]
		claimed[start] = true
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty() and patch.size() < ANOMALY_MAX_PATCH:
			var cell: Vector2i = queue.pop_front()
			for off in _OFF:
				var n: Vector2i = cell + off
				if patch.size() >= ANOMALY_MAX_PATCH:
					break
				if not claimed.has(n) and _cluster_family(grid, n) == family:
					claimed[n] = true
					patch.append(n)
					queue.append(n)
		var region := _new_region(state, "terrain_cluster", "anomaly", patch)
		region["prominence"] = float(seed["score"])
		made += 1


# ---------------------------------------------------------------------------
# §4.3 Coastal and landform features
# ---------------------------------------------------------------------------

static func _detect_coastal_features(state: Dictionary, land_components: Array) -> void:
	_detect_islands_and_archipelagos(state, land_components)
	_detect_capes(state)
	_detect_bays_and_gulfs(state)
	_detect_straits(state, land_components)
	_detect_necks(state, land_components)


static func _detect_islands_and_archipelagos(state: Dictionary, land_components: Array) -> void:
	var islands: Array = []  # {hexes, region}
	for entry in land_components:
		if not entry["is_island"]:
			continue
		var region := _new_region(state, "coastal_landform", "island", entry["hexes"])
		entry["region_id"] = region["id"]
		islands.append({"hexes": entry["hexes"], "region": region})
	if islands.size() < ARCHIPELAGO_MIN_ISLANDS:
		return
	# Cluster islands whose minimum inter-hex distance ≤ ARCHIPELAGO_SPACING.
	var n := islands.size()
	var assigned := {}
	for i in range(n):
		if assigned.has(i):
			continue
		var group: Array[int] = [i]
		assigned[i] = true
		var frontier: Array[int] = [i]
		while not frontier.is_empty():
			var current: int = frontier.pop_front()
			for j in range(n):
				if assigned.has(j):
					continue
				if _island_distance(islands[current]["hexes"], islands[j]["hexes"]) \
						<= ARCHIPELAGO_SPACING:
					assigned[j] = true
					group.append(j)
					frontier.append(j)
		if group.size() >= ARCHIPELAGO_MIN_ISLANDS:
			var all_hexes: Array = []
			for idx in group:
				all_hexes.append_array(islands[idx]["hexes"])
			var arch := _new_region(state, "coastal_landform", "archipelago", all_hexes)
			for idx in group:
				islands[idx]["region"]["parent_id"] = arch["id"]


static func _island_distance(a: Array, b: Array) -> int:
	var best := 9999
	for ha in a:
		for hb in b:
			best = mini(best, _hex_distance(ha, hb))
	return best


static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	# Axial hex distance.
	var dq := b.x - a.x
	var dr := b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func _detect_capes(state: Dictionary) -> void:
	var grid: Dictionary = state["grid"]
	var width: int = state["width"]
	var height: int = state["height"]
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			if not _is_land(grid, key):
				continue
			var water_neighbors := 0
			for off in _OFF:
				var n: Vector2i = key + off
				# Off-map does NOT count — otherwise every map-corner land
				# hex reads as a cape.
				if grid.has(n) and grid[n]["water"] == "ocean":
					water_neighbors += 1
			# A sharp protrusion: nearly surrounded by open water but part of
			# a larger landmass (single-hex islands are §4.3 islands instead).
			if water_neighbors >= 4 and water_neighbors < 6:
				var has_land_link := false
				for off in _OFF:
					if _is_land(grid, key + off):
						has_land_link = true
						break
				if has_land_link:
					_new_region(state, "coastal_landform", "cape", [key])


static func _detect_bays_and_gulfs(state: Dictionary) -> void:
	var grid: Dictionary = state["grid"]
	var floor_mult: int = state["floor_mult"]
	# Concavity candidates: ocean hexes with ≥ 3 land neighbors.
	var components := _components(state, func(key: Vector2i) -> bool:
		if not grid.has(key) or grid[key]["water"] != "ocean":
			return false
		var land_neighbors := 0
		for off in _OFF:
			if _is_land(grid, key + off):
				land_neighbors += 1
		return land_neighbors >= 3)
	for component in components:
		if component.size() >= GULF_MIN * floor_mult:
			_new_region(state, "coastal_landform", "gulf", component)
		elif component.size() >= BAY_MIN * floor_mult:
			_new_region(state, "coastal_landform", "bay", component)


static func _detect_straits(state: Dictionary, land_components: Array) -> void:
	var grid: Dictionary = state["grid"]
	var width: int = state["width"]
	var height: int = state["height"]
	# Map each hex to its land-component index (for masses ≥ STRAIT_MIN_MASS).
	var component_of := {}
	for i in range(land_components.size()):
		if land_components[i]["hexes"].size() < STRAIT_MIN_MASS:
			continue
		for h in land_components[i]["hexes"]:
			component_of[h] = i
	# A strait hex: ocean hex adjacent (within the gap width) to two distinct
	# large masses. Gap ≤ 2: direct adjacency or via one more ocean hex.
	var strait_hexes := {}
	for row in range(height):
		for col in range(width):
			var key := WorldGrid.offset_to_axial(col, row)
			if not grid.has(key) or grid[key]["water"] != "ocean":
				continue
			var masses := {}
			for off in _OFF:
				var n: Vector2i = key + off
				if component_of.has(n):
					masses[component_of[n]] = true
				elif grid.has(n) and grid[n]["water"] == "ocean":
					# One hex farther (gap width 2).
					for off2 in _OFF:
						var n2: Vector2i = n + off2
						if component_of.has(n2):
							masses[component_of[n2]] = true
			if masses.size() >= 2:
				strait_hexes[key] = true
	if strait_hexes.is_empty():
		return
	var components := _components(state, func(key: Vector2i) -> bool:
		return strait_hexes.has(key))
	for component in components:
		_new_region(state, "coastal_landform", "strait", component)


## Peninsulas + isthmuses share the neck computation: a cut of ≤ 2 adjacent
## land hexes whose removal splits a landmass. Smaller side ≥ 4 with the
## larger side dominant → peninsula; both sides ≥ 6 → the cut is an isthmus.
static func _detect_necks(state: Dictionary, land_components: Array) -> void:
	var grid: Dictionary = state["grid"]
	var claimed := {}
	for entry in land_components:
		var hexes: Array = entry["hexes"]
		if hexes.size() < PENINSULA_MIN_LAND + 1:
			continue
		var hex_set := {}
		for h in hexes:
			hex_set[h] = true
		# Candidate cuts: each coastal land hex alone (width 1), then each
		# adjacent coastal pair (width 2), in canonical order.
		var coastal: Array = []
		for h in hexes:
			for off in _OFF:
				var n: Vector2i = h + off
				if not grid.has(n) or grid[n]["water"] != "":
					coastal.append(h)
					break
		var cuts: Array = []
		for h in coastal:
			cuts.append([h])
		for h in coastal:
			for off in _OFF:
				var n: Vector2i = h + off
				if hex_set.has(n) and _hex_sort(h, n) and coastal.has(n):
					cuts.append([h, n])
		for cut in cuts:
			var parts := _split_by_cut(hexes, hex_set, cut)
			if parts.size() < 2:
				continue
			parts.sort_custom(func(a: Array, b: Array) -> bool:
				return a.size() > b.size())
			var larger: Array = parts[0]
			var smaller: Array = parts[parts.size() - 1]
			if smaller.size() >= ISTHMUS_MIN_MASS and larger.size() >= ISTHMUS_MIN_MASS \
					and not _any_claimed(claimed, cut):
				_new_region(state, "coastal_landform", "isthmus", cut.duplicate())
				for h in cut:
					claimed[h] = true
			elif smaller.size() >= PENINSULA_MIN_LAND \
					and larger.size() > smaller.size() * 2 \
					and not _any_claimed(claimed, smaller):
				var peninsula_hexes: Array = smaller.duplicate()
				peninsula_hexes.append_array(cut)
				_new_region(state, "coastal_landform", "peninsula", peninsula_hexes)
				for h in smaller:
					claimed[h] = true


static func _any_claimed(claimed: Dictionary, hexes: Array) -> bool:
	for h in hexes:
		if claimed.has(h):
			return true
	return false


static func _split_by_cut(hexes: Array, hex_set: Dictionary, cut: Array) -> Array:
	var removed := {}
	for h in cut:
		removed[h] = true
	var visited := {}
	var parts: Array = []
	for start in hexes:
		if visited.has(start) or removed.has(start):
			continue
		var part: Array = []
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			part.append(cell)
			for off in _OFF:
				var n: Vector2i = cell + off
				if hex_set.has(n) and not visited.has(n) and not removed.has(n):
					visited[n] = true
					queue.append(n)
		part.sort_custom(_hex_sort)
		parts.append(part)
	return parts


# ---------------------------------------------------------------------------
# §4.4 Hydronyms (geometry)
# ---------------------------------------------------------------------------

static func _detect_hydronyms(state: Dictionary, river_edges: Array) -> void:
	var grid: Dictionary = state["grid"]
	var width: int = state["width"]
	var height: int = state["height"]
	var floor_mult: int = state["floor_mult"]

	# Open-water bodies: oceans (≥ 80, touching the map edge) vs seas
	# (≥ 8, enclosed/marginal).
	var ocean_components := _components(state, func(key: Vector2i) -> bool:
		return grid.has(key) and grid[key]["water"] == "ocean")
	for component in ocean_components:
		var touches_edge := false
		for h in component:
			if h.x == 0 or h.y == 0 or h.x == width - 1 or h.y == height - 1:
				touches_edge = true
				break
		if component.size() >= OCEAN_MIN * floor_mult and touches_edge:
			_new_region(state, "hydronym", "ocean", component)
		elif component.size() >= SEA_MIN * floor_mult:
			_new_region(state, "hydronym", "sea", component)

	# Lakes (any size at this scale) + lakelands (dense clusters).
	var lake_components := _components(state, func(key: Vector2i) -> bool:
		return grid.has(key) and grid[key]["water"] == "lake")
	var lake_regions: Array = []
	for component in lake_components:
		lake_regions.append(_new_region(state, "hydronym", "lake", component))
	if lake_regions.size() >= LAKELAND_MIN_LAKES:
		_cluster_lakelands(state, lake_regions)

	# Rivers: connected chains of river edges (shared touched hexes are a
	# good proxy for shared vertices at this scale).
	_detect_river_systems(state, river_edges)


static func _cluster_lakelands(state: Dictionary, lake_regions: Array) -> void:
	var n := lake_regions.size()
	var assigned := {}
	for i in range(n):
		if assigned.has(i):
			continue
		var group: Array[int] = [i]
		assigned[i] = true
		var frontier: Array[int] = [i]
		while not frontier.is_empty():
			var current: int = frontier.pop_front()
			for j in range(n):
				if assigned.has(j):
					continue
				if _island_distance(lake_regions[current]["hexes"],
						lake_regions[j]["hexes"]) <= LAKELAND_SPACING:
					assigned[j] = true
					group.append(j)
					frontier.append(j)
		if group.size() >= LAKELAND_MIN_LAKES:
			var all_hexes: Array = []
			for idx in group:
				all_hexes.append_array(lake_regions[idx]["hexes"])
			var lakeland := _new_region(state, "hydronym", "lakeland", all_hexes)
			for idx in group:
				lake_regions[idx]["parent_id"] = lakeland["id"]


static func _detect_river_systems(state: Dictionary, river_edges: Array) -> void:
	if river_edges.is_empty():
		return
	# Union edges into systems via shared touched hexes.
	var n := river_edges.size()
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in range(n):
		parent[i] = i
	var by_hex := {}
	for i in range(n):
		var row: Dictionary = river_edges[i]
		var owner := Vector2i(int(row["hex_q"]), int(row["hex_r"]))
		for h in [owner, owner + _OFF[int(row["edge"])]]:
			if by_hex.has(h):
				_union(parent, by_hex[h], i)
			else:
				by_hex[h] = i
	var systems := {}
	var system_order: Array[int] = []
	for i in range(n):
		var root := _find(parent, i)
		if not systems.has(root):
			systems[root] = []
			system_order.append(root)
		systems[root].append(i)
	for root in system_order:
		var members: Array = systems[root]
		if members.size() < RIVER_MIN_EDGES * int(state["floor_mult"]):
			continue
		var hexes := {}
		var source_count := 0
		for i in members:
			var row: Dictionary = river_edges[i]
			var owner := Vector2i(int(row["hex_q"]), int(row["hex_r"]))
			hexes[owner] = true
			hexes[owner + _OFF[int(row["edge"])]] = true
			if str(row["width_category"]) == "stream":
				source_count += 1
		var hex_list: Array = hexes.keys()
		hex_list.sort_custom(_hex_sort)
		var subtype := "river_system" if source_count >= RIVER_SYSTEM_MIN_SOURCES else "river"
		var region := _new_region(state, "hydronym", subtype, hex_list)
		# Rivers reward length (§3.3 prominence: aspect ratio / length).
		region["prominence"] = clampf(float(members.size()) / 20.0, 0.2, 1.0)


static func _find(parent: PackedInt32Array, i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var next := parent[i]
		parent[i] = root
		i = next
	return root


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)


# ---------------------------------------------------------------------------
# Nesting, significance (§3.3, context = 0), overlaps
# ---------------------------------------------------------------------------

static func _assign_continent_parents(state: Dictionary, land_components: Array) -> void:
	var continent_of := {}
	for entry in land_components:
		if entry["is_island"] or str(entry["region_id"]).is_empty():
			continue
		for h in entry["hexes"]:
			continent_of[h] = entry["region_id"]
	for region in state["regions"]:
		if region["layer"] == "continent" or region["layer"] == "hydronym":
			continue
		if str(region["parent_id"]) != "":
			continue
		# Parent = the continent holding the majority of the region's hexes.
		var votes := {}
		for h in region["hexes"]:
			if continent_of.has(h):
				votes[continent_of[h]] = int(votes.get(continent_of[h], 0)) + 1
		var best := ""
		var best_votes := 0
		var vote_keys: Array = votes.keys()
		vote_keys.sort()
		for k in vote_keys:
			if int(votes[k]) > best_votes:
				best_votes = int(votes[k])
				best = k
		if best != "" and best_votes * 2 > region["hexes"].size():
			region["parent_id"] = best


static func _compute_significance(state: Dictionary) -> void:
	# Largest region per layer for the size normalizer.
	var largest := {}
	for region in state["regions"]:
		var layer: String = region["layer"]
		largest[layer] = maxi(int(largest.get(layer, 1)), region["hexes"].size())
	for region in state["regions"]:
		var size_term := 0.0
		var denom: float = log(maxf(float(largest[region["layer"]]), 2.0))
		if region["hexes"].size() > 1:
			size_term = log(float(region["hexes"].size())) / denom
		# Ranges reward peak elevation (§3.3 prominence).
		if region["subtype"] == "range":
			var peak := 0.0
			var grid: Dictionary = state["grid"]
			for h in region["hexes"]:
				peak = maxf(peak, float(grid[h]["elevation_raw"]))
			region["prominence"] = peak
		# context term = 0 until Stage 6 re-scores with cultures/history.
		region["significance"] = clampf(
				0.45 * size_term + 0.35 * float(region["prominence"]), 0.0, 1.0)


static func _compute_overlaps(state: Dictionary) -> void:
	var regions: Array = state["regions"]
	var parent_of := {}
	for region in regions:
		parent_of[str(region["id"])] = str(region["parent_id"])
	var sets: Array = []
	for region in regions:
		var s := {}
		for h in region["hexes"]:
			s[h] = true
		sets.append(s)
	for i in range(regions.size()):
		for j in range(i + 1, regions.size()):
			# Nesting (transitively, either direction) is not an overlap.
			if _is_ancestor(parent_of, str(regions[j]["id"]), str(regions[i]["id"])) \
					or _is_ancestor(parent_of, str(regions[i]["id"]), str(regions[j]["id"])):
				continue
			var intersects := false
			var smaller: Dictionary = sets[i] if sets[i].size() <= sets[j].size() else sets[j]
			var bigger: Dictionary = sets[j] if sets[i].size() <= sets[j].size() else sets[i]
			for h in smaller:
				if bigger.has(h):
					intersects = true
					break
			if intersects:
				regions[i]["overlaps"].append(regions[j]["id"])
				regions[j]["overlaps"].append(regions[i]["id"])


static func _is_ancestor(parent_of: Dictionary, candidate: String, of_region: String) -> bool:
	var current: String = parent_of.get(of_region, "")
	var guard := 0
	while current != "" and guard < 16:
		if current == candidate:
			return true
		current = parent_of.get(current, "")
		guard += 1
	return false


# ---------------------------------------------------------------------------
# Output rows
# ---------------------------------------------------------------------------

static func _to_row(region: Dictionary) -> Dictionary:
	var hex_pairs: Array = []
	for h in region["hexes"]:
		hex_pairs.append([h.x, h.y])
	return {
		"id": region["id"],
		"layer": region["layer"],
		"subtype": region["subtype"],
		"scale": "campaign_24mi",
		"parent_id": region["parent_id"],
		"coarse_parent_region_id": "",
		"hexes": JSON.stringify(hex_pairs),
		"overlaps": JSON.stringify(region["overlaps"]),
		"name_primary": "",
		"name_culture_id": "",
		"name_origin": "",
		"name_alternates": "[]",
		"significance": float(region["significance"]),
		"source_event_id": "",
	}
