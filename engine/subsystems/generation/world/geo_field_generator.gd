class_name GeoFieldGenerator
extends RefCounted

## Layer-1 of the field-first world generator (gdd-continuous-geography.md §4-5,
## §9 pipeline; approved 2026-06-24). Produces a continuous [GeoField]: a square
## base raster (4 cells / 24-mile hex) carrying simulated height + a real
## hydrology chain:
##
##   build height (noise stack) → thermal erosion → sea-level mask →
##   Priority-Flood depression fill → D8 flow direction → flow accumulation →
##   channel extraction + Strahler order → channel incision.
##
## ADDITIVE / not yet wired into the live pipeline (GDD §13 build order): built
## and tested alongside `heightmap_generator.gd`; it will replace the hex-native
## generator and feed `tag_for_footprint` + the 3D renderer's RAW_FIELD in later
## steps. The current pipeline + its determinism hash are untouched.
##
## Determinism (coding_conventions §80): all randomness via [WorldGenRng]; every
## ordering uses an explicit total-order tie-break by cell index; PackedArrays,
## index-order iteration only — no Dictionary-order draws.

# --- Noise recipe (ported from heightmap_generator.gd, sampled in mile-space) ---
const _CONTINENT_INFLUENCE := {"continental": 0.5, "archipelago": 0.2, "pangaea": 0.7}
const RIDGE_WEIGHT := 0.22
const RIDGE_ANISOTROPY := 3.5

# --- Hydrology tuning ---
## Slight downhill gradient added during depression fill so flow routing never
## ties on a flat filled basin (Priority-Flood +ε variant, Barnes 2014).
const FILL_EPSILON := 0.00001
## A non-ocean cell whose fill raised it at least this far is flagged a lake.
const LAKE_FILL_THRESHOLD := 0.003
## Thermal-erosion talus threshold (max stable neighbour height delta) + passes.
const TALUS := 0.04
const THERMAL_PASSES := 4
const THERMAL_RATE := 0.5
## Flow-accumulation threshold (channel iff accum >= this) per river_density.
const _FAT_BY_DENSITY := {"low": 600.0, "medium": 300.0, "high": 150.0}
## Channel incision: a channel cell is lowered by INCISION_SCALE * ln(accum).
const INCISION_SCALE := 0.012

const _SQRT2 := 1.4142135623730951


static func generate(campaign_seed: int, params) -> GeoField:
	var hex_dims: Vector2i = params.map_dimensions()
	var field := GeoField.new()
	field.allocate(hex_dims.x * GeoField.SUBDIV_PER_24MI, hex_dims.y * GeoField.SUBDIV_PER_24MI)

	_build_height(field, campaign_seed, params)
	_thermal_erosion(field)
	_apply_sea_level(field, params)
	_priority_flood(field)
	_flow_directions(field)
	_flow_accumulation(field)
	var fat := _fat(params)
	_strahler_order(field, fat)
	_incise_channels(field, fat)
	return field


static func _fat(params) -> float:
	return float(_FAT_BY_DENSITY.get(params.river_density, 300.0))


# ---------------------------------------------------------------------------
# Height (noise stack → normalized + curved 0-1 surface)
# ---------------------------------------------------------------------------

static func _build_height(field: GeoField, campaign_seed: int, params) -> void:
	var w := field.width
	var h := field.height
	var n := w * h

	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = WorldGenRng.derive_seed(campaign_seed, "geo_height")
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 6
	terrain_noise.frequency = 0.004

	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = WorldGenRng.derive_seed(campaign_seed, "geo_continent")
	shape_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape_noise.fractal_octaves = 3
	shape_noise.frequency = 0.0015

	var ridge_noise := FastNoiseLite.new()
	ridge_noise.seed = WorldGenRng.derive_seed(campaign_seed, "geo_ridge")
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridge_noise.fractal_octaves = 4
	ridge_noise.frequency = 0.002

	var theta: float = WorldGenRng.stream(campaign_seed, "geo_ridge_orientation").randf() * PI
	var cos_t := cos(theta)
	var sin_t := sin(theta)
	var influence: float = _CONTINENT_INFLUENCE.get(params.land_mass_style, 0.5)

	var center := Vector2(float(w) * 0.5, float(h) * 0.5) * GeoField.CELL_MILES
	var max_dist := maxf(center.length(), 1.0)

	var raw := PackedFloat32Array()
	raw.resize(n)
	var raw_min := INF
	var raw_max := -INF
	for row in range(h):
		for col in range(w):
			var pos := Vector2((float(col) + 0.5) * GeoField.CELL_MILES, (float(row) + 0.5) * GeoField.CELL_MILES)
			var terrain := (terrain_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
			var shape := (shape_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
			var falloff := center.distance_to(pos) / max_dist
			var elev := terrain * (1.0 - falloff * influence) + shape * influence
			# §14 directional ridge bias: ridged noise in a rotated, compressed frame.
			var rx := pos.x * cos_t + pos.y * sin_t
			var ry := (-pos.x * sin_t + pos.y * cos_t) * RIDGE_ANISOTROPY
			var ridged := 1.0 - absf(ridge_noise.get_noise_2d(rx, ry))
			elev += RIDGE_WEIGHT * pow(ridged, 3.0)
			var i := row * w + col
			raw[i] = elev
			raw_min = minf(raw_min, elev)
			raw_max = maxf(raw_max, elev)

	var span := maxf(raw_max - raw_min, 0.000001)
	var exponent: float = params.elevation_exponent()
	for i in range(n):
		# Clamp the normalized base to [0,1] before the curve. raw is float32 but
		# raw_min/raw_max are the float64 extrema, so the minimum cell can round
		# just below raw_min → a tiny-negative base → pow(neg, 1.5) = NaN. The
		# clamp also absorbs any FBM excursion past the noise's nominal range.
		field.surface[i] = pow(clampf((raw[i] - raw_min) / span, 0.0, 1.0), exponent)


# ---------------------------------------------------------------------------
# Thermal erosion (talus relaxation; delta-accumulated → order-independent)
# ---------------------------------------------------------------------------

static func _thermal_erosion(field: GeoField) -> void:
	var w := field.width
	var h := field.height
	var n := w * h
	for _pass in range(THERMAL_PASSES):
		var delta := PackedFloat32Array()
		delta.resize(n)  # zero-filled
		for row in range(h):
			for col in range(w):
				var i := row * w + col
				var hi := field.surface[i]
				for d: Vector2i in GeoField.D8:
					var nc := col + d.x
					var nr := row + d.y
					if nc < 0 or nc >= w or nr < 0 or nr >= h:
						continue
					var diff := hi - field.surface[nr * w + nc]
					if diff > TALUS:
						var move := (diff - TALUS) * THERMAL_RATE * 0.5
						delta[i] -= move
						delta[nr * w + nc] += move
		for i in range(n):
			field.surface[i] += delta[i]


# ---------------------------------------------------------------------------
# Sea level
# ---------------------------------------------------------------------------

static func _apply_sea_level(field: GeoField, params) -> void:
	var sea: float = params.sea_level
	for i in range(field.size_cells()):
		field.water[i] = GeoField.WATER_OCEAN if field.surface[i] < sea else GeoField.WATER_NONE


# ---------------------------------------------------------------------------
# Priority-Flood depression fill (+ε) — Barnes/Lehman/Sanders 2014
# ---------------------------------------------------------------------------

static func _priority_flood(field: GeoField) -> void:
	var w := field.width
	var h := field.height
	var n := w * h
	for i in range(n):
		field.filled[i] = field.surface[i]

	var closed := PackedByteArray()
	closed.resize(n)  # 0 = open
	var heap: Array = []  # min-heap of [height, idx, col, row]

	# Seed the open boundary: every map-edge cell + every ocean cell drains out.
	for row in range(h):
		for col in range(w):
			var i := row * w + col
			if col == 0 or row == 0 or col == w - 1 or row == h - 1 or field.water[i] == GeoField.WATER_OCEAN:
				closed[i] = 1
				_heap_push(heap, field.filled[i], i, col, row)

	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var ch: float = top[0]
		var ccol: int = top[2]
		var crow: int = top[3]
		for d: Vector2i in GeoField.D8:
			var nc := ccol + d.x
			var nr := crow + d.y
			if nc < 0 or nc >= w or nr < 0 or nr >= h:
				continue
			var ni := nr * w + nc
			if closed[ni] != 0:
				continue
			closed[ni] = 1
			var nh: float = field.filled[ni]
			if nh <= ch + FILL_EPSILON:
				nh = ch + FILL_EPSILON
				field.filled[ni] = nh
			_heap_push(heap, nh, ni, nc, nr)

	# Lakes = interior cells the fill raised notably above their surface (not ocean).
	for i in range(n):
		if field.water[i] != GeoField.WATER_OCEAN and (field.filled[i] - field.surface[i]) > LAKE_FILL_THRESHOLD:
			field.water[i] = GeoField.WATER_LAKE


# ---------------------------------------------------------------------------
# D8 flow direction (steepest descent on the filled DEM)
# ---------------------------------------------------------------------------

static func _flow_directions(field: GeoField) -> void:
	var w := field.width
	var h := field.height
	for row in range(h):
		for col in range(w):
			var i := row * w + col
			# Ocean + map-edge cells are sinks (water leaves the model there).
			if field.water[i] == GeoField.WATER_OCEAN or col == 0 or row == 0 or col == w - 1 or row == h - 1:
				field.flow_dir[i] = -1
				continue
			var hi := field.filled[i]
			var best_dir := -1
			var best_slope := 0.0
			for di in range(GeoField.D8.size()):
				var d: Vector2i = GeoField.D8[di]
				var ni := (row + d.y) * w + (col + d.x)
				var dist := _SQRT2 if (d.x != 0 and d.y != 0) else 1.0
				var slope := (hi - field.filled[ni]) / dist
				if slope > best_slope:
					best_slope = slope
					best_dir = di
			field.flow_dir[i] = best_dir


# ---------------------------------------------------------------------------
# Flow accumulation (push downstream in descending-height order)
# ---------------------------------------------------------------------------

static func _flow_accumulation(field: GeoField) -> void:
	var n := field.size_cells()
	var w := field.width
	for i in range(n):
		field.flow_accum[i] = 1.0
	# Process cells highest-first so an upstream cell always pushes before its
	# downstream. Total order (tie-break by index) → deterministic.
	var keyed: Array = []
	keyed.resize(n)
	for i in range(n):
		keyed[i] = [field.filled[i], i]
	keyed.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	for entry in keyed:
		var i: int = entry[1]
		var dir: int = field.flow_dir[i]
		if dir < 0:
			continue
		var d: Vector2i = GeoField.D8[dir]
		var ni := i + d.y * w + d.x
		field.flow_accum[ni] += field.flow_accum[i]


# ---------------------------------------------------------------------------
# Channel extraction (FAT threshold) + Strahler stream order
# ---------------------------------------------------------------------------

static func _strahler_order(field: GeoField, fat: float) -> void:
	var n := field.size_cells()
	var w := field.width
	var is_channel := PackedByteArray()
	is_channel.resize(n)
	var chans: Array = []
	for i in range(n):
		if field.water[i] != GeoField.WATER_OCEAN and field.flow_accum[i] >= fat:
			is_channel[i] = 1
			chans.append([field.flow_accum[i], i])
	# Ascending flow_accum is strictly topological (accum increases downstream),
	# so every inflow is processed before the cell it flows into.
	chans.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])

	var max_in := PackedInt32Array()
	max_in.resize(n)
	var cnt_at_max := PackedInt32Array()
	cnt_at_max.resize(n)
	for entry in chans:
		var i: int = entry[1]
		var order := 1
		if max_in[i] > 0:
			order = max_in[i] + 1 if cnt_at_max[i] >= 2 else max_in[i]
		field.strahler[i] = order
		var dir: int = field.flow_dir[i]
		if dir < 0:
			continue
		var d: Vector2i = GeoField.D8[dir]
		var ni := i + d.y * w + d.x
		if ni < 0 or ni >= n or is_channel[ni] == 0:
			continue
		if order > max_in[ni]:
			max_in[ni] = order
			cnt_at_max[ni] = 1
		elif order == max_in[ni]:
			cnt_at_max[ni] += 1


# ---------------------------------------------------------------------------
# Channel incision (carve valleys along the drainage network)
# ---------------------------------------------------------------------------

static func _incise_channels(field: GeoField, fat: float) -> void:
	for i in range(field.size_cells()):
		if field.water[i] == GeoField.WATER_OCEAN:
			continue
		if field.flow_accum[i] >= fat:
			var cut := INCISION_SCALE * log(field.flow_accum[i])
			field.surface[i] = maxf(0.0, field.surface[i] - cut)


# ---------------------------------------------------------------------------
# Binary min-heap over [height, idx, col, row]; ordered by height then idx.
# ---------------------------------------------------------------------------

static func _heap_push(heap: Array, hgt: float, i: int, col: int, row: int) -> void:
	heap.append([hgt, i, col, row])
	var c := heap.size() - 1
	while c > 0:
		var p := (c - 1) >> 1
		if _heap_less(heap[c], heap[p]):
			var tmp: Array = heap[p]
			heap[p] = heap[c]
			heap[c] = tmp
			c = p
		else:
			break


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var sz := heap.size()
		var c := 0
		while true:
			var l := 2 * c + 1
			var r := 2 * c + 2
			var smallest := c
			if l < sz and _heap_less(heap[l], heap[smallest]):
				smallest = l
			if r < sz and _heap_less(heap[r], heap[smallest]):
				smallest = r
			if smallest == c:
				break
			var tmp: Array = heap[c]
			heap[c] = heap[smallest]
			heap[smallest] = tmp
			c = smallest
	return top


static func _heap_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[1] < b[1]
