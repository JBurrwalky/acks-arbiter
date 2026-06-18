class_name HeightmapGenerator
extends RefCounted

## Layer 1 — physical geography (gdd-setting-generation.md §4): FastNoiseLite
## heightmap with continental shaping + directional ridge bias (§14 — no
## tectonics), elevation curve, ocean/coastline, and hydrology (the river
## graph is a first-class output — region painting and the sim both consume
## it; edges per gdd-terrain-system.md §3.6).
##
## Works on the orchestrator ctx: fills ctx.hex_grid (Vector2i -> working hex
## dict) and ctx.river_edges (rows per SettingRepository.RIVER_EDGE_COLUMNS).
## Persistence happens in the orchestrator after Layer 2 completes the rows.
##
## Determinism: all noise seeds derive from WorldGenRng; iteration is r-major
## (the canonical hex order); no Dictionary-order iteration anywhere.

const HEX_MILES := 24.0
# sqrt(3)/2 — axial-to-cartesian row spacing factor.
const _ROW_FACTOR := 0.8660254037844386

# Elevation-tag bands on the shaped 0-1 heightmap (setting-gen §4.1 step 10).
const HILLS_THRESHOLD := 0.55
const MOUNTAINS_THRESHOLD := 0.75

# Continental shaping (§4.2) per land_mass_style.
const _CONTINENT_INFLUENCE := {"continental": 0.5, "archipelago": 0.2, "pangaea": 0.7}

# Directional ridge bias (§14: linear mountain ranges without tectonics).
const RIDGE_WEIGHT := 0.22
const RIDGE_ANISOTROPY := 3.5  # across-ridge compression — elongates crests

# River-source elevation threshold per river_density (§4.4).
const _SOURCE_THRESHOLD := {"low": 0.85, "medium": 0.75, "high": 0.65}

# width_category by accumulated source count: each tributary junction steps
# the category (§4.4: stream → creek → river → major_river).
const _WIDTH_BY_LOG2 := ["stream", "creek", "river", "major_river"]
const _NAV_BY_WIDTH := {
	"stream": "none", "creek": "small_craft",
	"river": "river_craft", "major_river": "large_craft",
}

# Axial neighbor offsets, edge 0=N .. 5=NW (HexRiverEdgeData convention).
const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


static func run(ctx: Dictionary) -> bool:
	var params: SettingParameters = ctx["params"]
	var campaign_seed: int = ctx["campaign_seed"]
	var dims := params.map_dimensions()
	ctx["width"] = dims.x
	ctx["height"] = dims.y

	var shaped := _build_heightmap(campaign_seed, params, dims)
	var grid := {}
	for row in range(dims.y):
		for col in range(dims.x):
			var key := WorldGrid.offset_to_axial(col, row)
			var elev: float = shaped[key]
			grid[key] = {
				"elevation_raw": elev,
				"elevation": _elevation_tag(elev),
				"water": "ocean" if elev < params.sea_level else "",
				# Layer-2 fields, defaulted; ClimateGenerator fills them.
				"temperature": 0.0,
				"precipitation": 0.0,
				"effective_latitude": 0.0,
				"koppen": "",
				"biome": "clear",
				"biome_subtype": "",
				"original_biome": "",
				# Layer-4+ fields at start state.
				"culture_weights": "{}",
				"alignment_weights": "{}",
				"population_band": 0,
				"territory_class": "wilderness",
				"owner_polity_id": "",
				"land_value": 0,
			}
	ctx["hex_grid"] = grid
	ctx["river_edges"] = _trace_rivers(campaign_seed, params, dims, grid)
	return true


# ---------------------------------------------------------------------------
# Heightmap (§4.1-§4.3)
# ---------------------------------------------------------------------------

## Cartesian hex-center embedding (miles): equidistant 24-mile neighbor
## spacing for isotropic noise sampling and distance falloff.
static func _hex_center(q: int, r: int) -> Vector2:
	return Vector2(HEX_MILES * (q + r * 0.5), HEX_MILES * r * _ROW_FACTOR)


static func _build_heightmap(campaign_seed: int, params: SettingParameters,
		dims: Vector2i) -> Dictionary:
	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = WorldGenRng.derive_seed(campaign_seed, "heightmap")
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 6
	terrain_noise.frequency = 0.004  # ~250-mile features in the mile embedding

	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = WorldGenRng.derive_seed(campaign_seed, "continent_shape")
	shape_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape_noise.fractal_octaves = 3
	shape_noise.frequency = 0.0015

	var ridge_noise := FastNoiseLite.new()
	ridge_noise.seed = WorldGenRng.derive_seed(campaign_seed, "ridge")
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridge_noise.fractal_octaves = 4
	ridge_noise.frequency = 0.002

	# Ridge orientation: one seeded draw per campaign; ranges become linear
	# chains along this axis (anisotropic compression across it).
	var theta: float = WorldGenRng.stream(campaign_seed, "ridge_orientation").randf() * PI
	var cos_t := cos(theta)
	var sin_t := sin(theta)

	var influence: float = _CONTINENT_INFLUENCE.get(params.land_mass_style, 0.5)

	# Map extent in cartesian space for falloff normalization. Computed from the
	# ACTUAL enumerated hex centres (not the axial-rectangle corners) so the
	# continental falloff stays centred under the offset-rectangle layout. The
	# bbox-corner distance is an upper bound on any hex-centre distance, so
	# falloff stays in [0, 1] (no edge hex over-suppressed into spurious ocean).
	var bb_min := Vector2(INF, INF)
	var bb_max := Vector2(-INF, -INF)
	for cell in WorldGrid.enumerate(dims.x, dims.y):
		var ck: Vector2i = cell["key"]
		var cc := _hex_center(ck.x, ck.y)
		bb_min = bb_min.min(cc)
		bb_max = bb_max.max(cc)
	var center := (bb_min + bb_max) * 0.5
	var max_dist := maxf(center.distance_to(bb_min), 0.000001)

	var raw := {}
	var raw_min := INF
	var raw_max := -INF
	for row in range(dims.y):
		for col in range(dims.x):
			var key := WorldGrid.offset_to_axial(col, row)
			var pos := _hex_center(key.x, key.y)
			var terrain := (terrain_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
			var shape := (shape_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
			var falloff := center.distance_to(pos) / max_dist
			# §4.2 blend: falloff suppresses raw terrain toward the edges;
			# the broad shape noise carries the continental outline.
			var elev := terrain * (1.0 - falloff * influence) + shape * influence
			# §14 directional bias: ridged noise (1 - |n|) sampled in a
			# rotated, compressed frame → elongated crest lines.
			var rx := pos.x * cos_t + pos.y * sin_t
			var ry := (-pos.x * sin_t + pos.y * cos_t) * RIDGE_ANISOTROPY
			var ridged := 1.0 - absf(ridge_noise.get_noise_2d(rx, ry))
			elev += RIDGE_WEIGHT * pow(ridged, 3.0)
			raw[key] = elev
			raw_min = minf(raw_min, elev)
			raw_max = maxf(raw_max, elev)

	# Normalize 0-1, then the §4.3 elevation curve.
	var span := maxf(raw_max - raw_min, 0.000001)
	var exponent := params.elevation_exponent()
	var shaped := {}
	for row in range(dims.y):
		for col in range(dims.x):
			var key := WorldGrid.offset_to_axial(col, row)
			shaped[key] = pow((raw[key] - raw_min) / span, exponent)
	return shaped


static func _elevation_tag(elev: float) -> String:
	if elev >= MOUNTAINS_THRESHOLD:
		return "mountains"
	if elev >= HILLS_THRESHOLD:
		return "hills"
	return "flat"


# ---------------------------------------------------------------------------
# Hydrology (§4.4) — vertex-walk river tracing on the hex-corner graph.
# Corner c of hex H = the vertex shared by edges c and (c+1)%6, touching
# hexes H, H+off(c), H+off(c+1) (gdd-terrain-system.md §3.6.3 orientation).
# ---------------------------------------------------------------------------

static func _trace_rivers(campaign_seed: int, params: SettingParameters,
		dims: Vector2i, grid: Dictionary) -> Array:
	var threshold: float = _SOURCE_THRESHOLD.get(params.river_density, 0.75)
	var sources: Array[Vector2i] = []
	for row in range(dims.y):
		for col in range(dims.x):
			var key := WorldGrid.offset_to_axial(col, row)
			var hex: Dictionary = grid[key]
			if hex["water"] == "ocean" or float(hex["elevation_raw"]) < threshold:
				continue
			var is_peak := true
			for off in _OFF:
				var n: Vector2i = key + off
				if grid.has(n) and float(grid[n]["elevation_raw"]) > float(hex["elevation_raw"]):
					is_peak = false
					break
			if is_peak:
				sources.append(key)

	# edge_key "q,r,e" (canonical owner) → {row, flow (source count)}.
	var edges := {}
	var edge_order: Array[String] = []  # insertion order for deterministic output
	for source in sources:
		_trace_one_river(source, dims, grid, edges, edge_order)

	var rows: Array = []
	for ek in edge_order:
		var entry: Dictionary = edges[ek]
		var width: String = _WIDTH_BY_LOG2[clampi(
				int(floor(log(float(entry["flow"])) / log(2.0))), 0, 3)]
		var row: Dictionary = entry["row"]
		row["width_category"] = width
		row["navigability"] = _NAV_BY_WIDTH[width]
		rows.append(row)
	return rows


static func _trace_one_river(source: Vector2i, dims: Vector2i, grid: Dictionary,
		edges: Dictionary, edge_order: Array[String]) -> void:
	# Start at the source hex's lowest corner (water leaves the peak at once).
	var v := _lowest_corner_of(source, grid)
	var visited := {}
	var max_steps := 4 * (dims.x + dims.y)
	for _step in range(max_steps):
		visited[_vertex_key(v)] = true
		# Terminate on reaching open water or the map edge.
		var touching := _vertex_hexes(v)
		var off_map := false
		for h in touching:
			if not grid.has(h):
				off_map = true
			elif grid[h]["water"] != "":
				return
		if off_map:
			return
		# Step to the lowest unvisited adjacent vertex.
		var best_next: Array = []  # vertex (3-hex Array) or empty
		var best_elev := INF
		var best_edge: Array = []
		for inc in _incident_edges(v):
			var other: Array = _other_endpoint(v, inc)
			if visited.has(_vertex_key(other)):
				continue
			var e := _vertex_elevation(other, grid)
			if e < best_elev:
				best_elev = e
				best_next = other
				best_edge = inc
		if best_next.is_empty() or best_elev >= _vertex_elevation(v, grid):
			# Depression: flood the lowest touching land hex into a lake and
			# stop — the lake fills the basin (§4.4); a later river reaching
			# this lake terminates on its water tag.
			var lake := _lowest_land_hex(v, grid)
			if lake != Vector2i(-9999, -9999):
				grid[lake]["water"] = "lake"
			return
		_mark_river_edge(best_edge[0], best_edge[1], v, best_next, edges, edge_order)
		v = best_next


## A vertex is represented as its sorted 3-hex touching set
## (Array[Vector2i], sorted by (r, q)) — canonical by construction.
static func _make_vertex(a: Vector2i, b: Vector2i, c: Vector2i) -> Array:
	var arr: Array[Vector2i] = [a, b, c]
	arr.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		return x.y < y.y or (x.y == y.y and x.x < y.x))
	return arr


static func _vertex_key(v: Array) -> String:
	return "%d,%d|%d,%d|%d,%d" % [v[0].x, v[0].y, v[1].x, v[1].y, v[2].x, v[2].y]


static func _corner_vertex(hex: Vector2i, c: int) -> Array:
	return _make_vertex(hex, hex + _OFF[c], hex + _OFF[(c + 1) % 6])


static func _vertex_hexes(v: Array) -> Array:
	return v


static func _vertex_elevation(v: Array, grid: Dictionary) -> float:
	var total := 0.0
	for h in v:
		if grid.has(h):
			if grid[h]["water"] == "ocean":
				total += 0.0
			else:
				total += float(grid[h]["elevation_raw"])
		# Off-map hexes contribute 0 (ocean-level) — rivers drain off-map.
	return total / 3.0


static func _lowest_corner_of(hex: Vector2i, grid: Dictionary) -> Array:
	var best: Array = []
	var best_elev := INF
	for c in range(6):
		var v := _corner_vertex(hex, c)
		var e := _vertex_elevation(v, grid)
		if e < best_elev:
			best_elev = e
			best = v
	return best


## The 3 hex-pair edges incident to vertex v: each unordered pair of its
## touching hexes that are mutually adjacent (all three pairs are).
static func _incident_edges(v: Array) -> Array:
	return [[v[0], v[1]], [v[0], v[2]], [v[1], v[2]]]


## The other endpoint vertex of hex-pair edge [a, b] from vertex v: the
## third hex flips to the opposite side of the shared edge.
static func _other_endpoint(v: Array, edge_pair: Array) -> Array:
	var a: Vector2i = edge_pair[0]
	var b: Vector2i = edge_pair[1]
	var third := Vector2i.ZERO
	for h in v:
		if h != a and h != b:
			third = h
			break
	# The two endpoint vertices of edge (a, b) are {a, b, third} and
	# {a, b, mirror}: mirror = a + b - third (axial coordinates are affine,
	# and the two flanking corners are point-symmetric about the edge midpoint).
	var mirror := a + b - third
	return _make_vertex(a, b, mirror)


static func _lowest_land_hex(v: Array, grid: Dictionary) -> Vector2i:
	var best := Vector2i(-9999, -9999)
	var best_elev := INF
	for h in v:
		if grid.has(h) and grid[h]["water"] == "":
			var e := float(grid[h]["elevation_raw"])
			if e < best_elev:
				best_elev = e
				best = h
	return best


static func _mark_river_edge(a: Vector2i, b: Vector2i, from_v: Array, to_v: Array,
		edges: Dictionary, edge_order: Array[String]) -> void:
	# Canonical owner per gdd-terrain-system.md §3.6.2: lexicographically
	# lower (q, r) of the two adjacent hexes.
	var owner := a
	var other := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		owner = b
		other = a
	var edge_index := -1
	for e in range(6):
		if owner + _OFF[e] == other:
			edge_index = e
			break
	if edge_index < 0:
		push_error("HeightmapGenerator: non-adjacent river edge pair %s-%s." % [a, b])
		return
	var ek := "%d,%d,%d" % [owner.x, owner.y, edge_index]
	if edges.has(ek):
		edges[ek]["flow"] = int(edges[ek]["flow"]) + 1
		return
	# flow_clockwise (§3.6.3): downstream vertex (to_v) is the corner shared
	# with edge (e+1)%6 — i.e. corner e of the owner — when clockwise.
	var cw_vertex := _corner_vertex(owner, edge_index)
	var flow_clockwise := _vertex_key(to_v) == _vertex_key(cw_vertex)
	edges[ek] = {
		"flow": 1,
		"row": {
			"hex_q": owner.x, "hex_r": owner.y, "edge": edge_index,
			"flow_clockwise": 1 if flow_clockwise else 0,
			"width_category": "stream", "navigability": "none",
			"crossing": "none",
		},
	}
	edge_order.append(ek)
