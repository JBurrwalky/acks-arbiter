class_name GeoFieldGenerator
extends RefCounted

## Layer-1 of the field-first world generator (gdd-continuous-geography.md §4-5,
## §9 pipeline; approved 2026-06-24, height rework 2026-06-24). Produces a
## continuous [GeoField]: a square base raster (4 cells / 24-mile hex) carrying
## simulated height + a real hydrology chain:
##
##   continental mask → rank land/ocean split → orogenic belt locator →
##   amplitude-gated ridged-multifractal → compose base → morphological coast
##   cleanup → quantile-anchored hypsometry remap → crest-preserving thermal
##   erosion → sea-level mask → Priority-Flood depression fill → D8 flow
##   direction → flow accumulation → channel extraction + Strahler → incision.
##
## HEIGHT METHOD (rework): the old smooth-FBM + pow(exponent) recipe produced an
## 85% / 13% / 1.3% flat/hills/mountains blob with no ranges and fragmented coasts.
## The rework (judge-panel synthesis): (1) domain-warped continental mask is the
## sole land/ocean decider; a rank threshold pins ocean fraction per land_mass_style.
## (2) Ranges come from an amplitude-GATED ridged-multifractal (weight = running
## signal × RIDGE_GATE makes ridgelines CONNECT into spines, not fracture into
## domes), confined to orogenic belts located by a coast-distance transform so
## ranges run inland. (3) A unified quantile-anchored piecewise remap pins the land
## distribution's own percentiles to the fixed 0.55 / 0.75 elevation-tag thresholds,
## so the land split is exactly ~60/28/12 for every seed/size, monotone (D8-safe),
## and self-calibrating. (4) Morphological cleanup removes micro-islands / fills
## pinhole inland seas per style for the continental↔archipelago look.
##
## ADDITIVE / not yet wired into the live pipeline (GDD §13 build order). The
## current hex-native pipeline + its determinism hash are untouched.
##
## Determinism (coding_conventions §80): all randomness via [WorldGenRng] with
## distinct labels; PackedArrays + index-order iteration; built-in numeric sort
## (value-only reads) or explicit total-order tie-breaks; BFS frontiers seeded in
## index order with the fixed D8 neighbour order — no Dictionary-order draws.

# --- Continental mask + cohesion (per land_mass_style) ---
const CONT_FREQ := 0.0016
## Per-style mask frequency: archipelago samples the continent field FINER, so the
## land breaks into many small islands; pangaea samples it COARSER, so a single
## supercontinent dominates. (Lowering land fraction alone only shrinks one
## continent — the frequency is what fragments vs. consolidates the LANDFORM.)
const _CONT_FREQ_MULT := {"continental": 1.0, "archipelago": 3.0, "pangaea": 0.6}
const WARP_FREQ := 0.0009
const WARP_AMP := 140.0
const EDGE_INNER := 0.55
const _EDGE_PULL := {"continental": 0.22, "archipelago": 0.10, "pangaea": 0.32}
## Target land fraction by style → ocean fraction ≈ 1 − this. continental ≈ 40%
## ocean (the default look). Pinned exactly by the rank threshold before cleanup.
const _TARGET_LAND_FRAC := {"continental": 0.60, "archipelago": 0.40, "pangaea": 0.80}
## Keeps params.sea_level live now that style drives ocean fraction: a higher sea
## level shaves the land target. land_target −= (sea_level − 0.30) × this.
const SEA_LEVEL_LAND_SENS := 0.8
## Morphological cleanup sizes (cells): land components below MIN_LAND sink to
## ocean; fully-enclosed ocean pockets below MIN_OCEAN fill to land. archipelago
## keeps small specks; continental/pangaea consolidate.
const _MIN_LAND_CELLS := {"continental": 64, "archipelago": 3, "pangaea": 120}
const _MIN_OCEAN_CELLS := {"continental": 40, "archipelago": 4, "pangaea": 64}

# --- Orogenic belt locator (where ranges run) ---
const BELT_INNER_MI := 30.0   # ranges start this far inland off the beach
const BELT_PEAK_MI := 120.0   # full belt weight by this inland distance
const BELT_CORE := 0.6
const BELT_GRAD := 6.0         # continental-margin (mask-gradient) contribution
const BELT_LO := 0.35
const BELT_HI := 0.85

# --- Amplitude-gated ridged-multifractal (the connected-range engine) ---
## Energy is concentrated in the low octaves (RIDGE_HFALL ≈ 0.5, Musgrave) so
## ridgelines are broad + coherent; a few high octaves add flank texture without
## shattering the crest into gravel (which also spawned excessive tarns).
const RIDGE_FREQ_BASE := 0.0018
const RIDGE_OCTAVES := 4
const RIDGE_LACUNARITY := 2.0
const RIDGE_HFALL := 0.52      # per-octave amplitude falloff (low-octave dominant)
const RIDGE_GATE := 0.8        # running-signal gate → ridges connect into spines
const RIDGE_ANISO := 3.2       # across-strike compression → linear cordillera

# --- Base composition gains ---
const LAND_GAIN := 0.55        # broad coast→interior rise from the mask
const RIDGE_GAIN := 0.55       # range height (× belt × ridge)
const FOOTHILL_GAIN := 0.10    # hills ringing the crests
const DETAIL_FREQ := 0.010
const DETAIL_GAIN := 0.06      # signed sub-band texture so the field isn't blobby

# --- Hypsometry quantile anchors (land split) by mountain_frequency ---
## (flat_frac, flat+hill_frac): the land percentiles pinned to the 0.55 / 0.75
## elevation-tag thresholds. medium = 60% flat / 28% hills / 12% mountains.
const _HYPSO_ANCHORS := {
	"low": Vector2(0.66, 0.92),
	"medium": Vector2(0.60, 0.88),
	"high": Vector2(0.52, 0.82),
}
## Output knots = HeightmapGenerator tag thresholds (UNCHANGED, not redefined here).
const HILLS_OUT := 0.55
const MTN_OUT := 0.75
## Land floor above sea level so gentle erosion never flips coast back to ocean.
const LAND_PAD := 0.03

# --- Hydrology tuning ---
## Slight downhill gradient added during depression fill so flow routing never
## ties on a flat filled basin (Priority-Flood +ε variant, Barnes 2014).
const FILL_EPSILON := 0.00001
## A non-ocean cell whose fill raised it at least this far is flagged a lake.
## Raised from 0.003 so only substantial basins become lakes — the sharper ridged
## relief otherwise flagged every shallow inter-ridge pit as a tarn (lake speckle).
const LAKE_FILL_THRESHOLD := 0.008
## Crest-preserving thermal erosion: one gentle talus-relaxation pass that skips
## mountain crests (≥ MOUNTAIN_PRESERVE) so cordillera don't round back into domes.
const TALUS := 0.07
const THERMAL_PASSES := 1
const THERMAL_RATE := 0.35
const MOUNTAIN_PRESERVE := 0.74
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
# Height: continental mask → belts → gated ridges → compose → cleanup →
#         quantile-anchored hypsometry remap → field.surface (continuous 0-1)
# ---------------------------------------------------------------------------

static func _build_height(field: GeoField, campaign_seed: int, params) -> void:
	var w := field.width
	var h := field.height
	var n := w * h
	var style: String = params.land_mass_style

	# --- noise streams (distinct labels → independent deterministic fields) ---
	var cont := FastNoiseLite.new()
	cont.seed = WorldGenRng.derive_seed(campaign_seed, "geo_continent")
	cont.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cont.fractal_type = FastNoiseLite.FRACTAL_FBM
	cont.fractal_octaves = 4
	cont.frequency = CONT_FREQ * float(_CONT_FREQ_MULT.get(style, 1.0))
	var warp_x := FastNoiseLite.new()
	warp_x.seed = WorldGenRng.derive_seed(campaign_seed, "geo_warp_x")
	warp_x.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_x.fractal_type = FastNoiseLite.FRACTAL_NONE
	warp_x.frequency = WARP_FREQ
	var warp_y := FastNoiseLite.new()
	warp_y.seed = WorldGenRng.derive_seed(campaign_seed, "geo_warp_y")
	warp_y.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_y.fractal_type = FastNoiseLite.FRACTAL_NONE
	warp_y.frequency = WARP_FREQ
	var ridge := FastNoiseLite.new()
	ridge.seed = WorldGenRng.derive_seed(campaign_seed, "geo_ridge")
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_NONE
	ridge.frequency = 1.0  # manual octave loop scales coords itself
	var detail := FastNoiseLite.new()
	detail.seed = WorldGenRng.derive_seed(campaign_seed, "geo_detail")
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 5
	detail.frequency = DETAIL_FREQ

	var theta: float = WorldGenRng.stream(campaign_seed, "geo_ridge_orientation").randf() * PI
	var cos_t := cos(theta)
	var sin_t := sin(theta)
	var center := Vector2(float(w) * 0.5, float(h) * 0.5) * GeoField.CELL_MILES
	var max_dist := maxf(center.length(), 1.0)
	var edge_pull: float = _EDGE_PULL.get(style, 0.22)

	# --- STEP 1: continental mask (domain-warped FBM + edge bias to ocean) ---
	var cmask := PackedFloat32Array()
	cmask.resize(n)
	for row in range(h):
		for col in range(w):
			var px := (float(col) + 0.5) * GeoField.CELL_MILES
			var py := (float(row) + 0.5) * GeoField.CELL_MILES
			var wx := px + WARP_AMP * warp_x.get_noise_2d(px, py)
			var wy := py + WARP_AMP * warp_y.get_noise_2d(px, py)
			var m := (cont.get_noise_2d(wx, wy) + 1.0) * 0.5
			var dn := Vector2(px, py).distance_to(center) / max_dist
			m *= 1.0 - smoothstep(EDGE_INNER, 1.0, dn) * edge_pull
			cmask[row * w + col] = clampf(m, 0.0, 1.0)

	# --- STEP 2: rank land/ocean split — exact ocean fraction per style ---
	var target_land: float = clampf(
		float(_TARGET_LAND_FRAC.get(style, 0.60)) - (params.sea_level - 0.30) * SEA_LEVEL_LAND_SENS,
		0.2, 0.9)
	var land_cut := _rank_value(cmask, 1.0 - target_land)
	var is_land := PackedByteArray()
	is_land.resize(n)
	for i in range(n):
		is_land[i] = 1 if cmask[i] >= land_cut else 0

	# --- STEP 3: orogenic belt locator (inland coast-distance + margin gradient) ---
	var coast_dist := _coast_distance(is_land, w, h)
	var belt := PackedFloat32Array()
	belt.resize(n)
	for row in range(h):
		for col in range(w):
			var i := row * w + col
			if is_land[i] == 0:
				belt[i] = 0.0
				continue
			var dist_mi := float(coast_dist[i]) * GeoField.CELL_MILES
			var core := smoothstep(BELT_INNER_MI, BELT_PEAK_MI, dist_mi)
			var grad := clampf(BELT_GRAD * _grad_mag(cmask, w, h, col, row), 0.0, 1.0)
			belt[i] = smoothstep(BELT_LO, BELT_HI, clampf(BELT_CORE * core + 0.5 * grad, 0.0, 1.0))

	# --- STEP 4: amplitude-gated ridged-multifractal → ridge_raw (+ max) ---
	var ridge_raw := PackedFloat32Array()
	ridge_raw.resize(n)
	var ridge_max := 0.0
	for row in range(h):
		for col in range(w):
			var px := (float(col) + 0.5) * GeoField.CELL_MILES
			var py := (float(row) + 0.5) * GeoField.CELL_MILES
			var rx := px * cos_t + py * sin_t
			var ry := (-px * sin_t + py * cos_t) * RIDGE_ANISO
			var amp := 1.0
			var freq := RIDGE_FREQ_BASE
			var prev := 1.0
			var acc := 0.0
			for _o in range(RIDGE_OCTAVES):
				var nv := ridge.get_noise_2d(rx * freq, ry * freq)
				var sig := 1.0 - absf(nv)
				sig = sig * sig  # sharpen the crest
				var weight := clampf(prev * RIDGE_GATE, 0.0, 1.0)
				acc += sig * weight * amp
				prev = sig
				amp *= RIDGE_HFALL
				freq *= RIDGE_LACUNARITY
			ridge_raw[row * w + col] = acc
			ridge_max = maxf(ridge_max, acc)
	var ridge_inv := 1.0 / maxf(ridge_max, 0.000001)

	# --- STEP 5: compose base (un-normalized; the remap does the scaling) ---
	var base := PackedFloat32Array()
	base.resize(n)
	for row in range(h):
		for col in range(w):
			var i := row * w + col
			var px := (float(col) + 0.5) * GeoField.CELL_MILES
			var py := (float(row) + 0.5) * GeoField.CELL_MILES
			var r01 := clampf(ridge_raw[i] * ridge_inv, 0.0, 1.0)
			var d := detail.get_noise_2d(px, py)
			base[i] = LAND_GAIN * cmask[i] \
				+ RIDGE_GAIN * belt[i] * r01 \
				+ FOOTHILL_GAIN * belt[i] * smoothstep(0.2, 0.6, r01) \
				+ DETAIL_GAIN * d

	# --- STEP 6: morphological coast cleanup (continental ↔ archipelago look) ---
	_morphological_cleanup(is_land, w, h, style)

	# --- STEP 7: unified quantile-anchored hypsometry remap (the split guarantee) ---
	var anchors: Vector2 = _HYPSO_ANCHORS.get(params.mountain_frequency, Vector2(0.60, 0.88))
	var land_vals := PackedFloat32Array()
	for i in range(n):
		if is_land[i] == 1:
			land_vals.append(base[i])
	var sea: float = params.sea_level
	if land_vals.is_empty():
		# Degenerate (no land survived cleanup) — flat sea floor; tests guarantee land.
		for i in range(n):
			field.surface[i] = clampf(sea * 0.5, 0.0, 1.0)
		return
	land_vals.sort()  # ascending numeric — value-only reads, order-independent
	var m_land := land_vals.size()
	var v0 := land_vals[0]
	var v_hills := land_vals[clampi(int(floor(anchors.x * float(m_land))), 0, m_land - 1)]
	var v_mtn := land_vals[clampi(int(floor(anchors.y * float(m_land))), 0, m_land - 1)]
	var v_top := land_vals[m_land - 1]
	var land_lo := sea + LAND_PAD

	for i in range(n):
		if is_land[i] == 1:
			field.surface[i] = clampf(_piecewise(base[i],
				v0, land_lo, v_hills, HILLS_OUT, v_mtn, MTN_OUT, v_top, 1.0), 0.0, 1.0)
		else:
			# Submarine slope: mask-proportional depth below sea level (continuous
			# downhill toward deep ocean → well-formed coast sinks for Priority-Flood).
			field.surface[i] = clampf(
				minf(sea * cmask[i] / maxf(land_cut, 0.000001), sea - 0.001), 0.0, sea)


# --- Height helpers ---------------------------------------------------------

## Value of `arr` at the ascending rank `frac` (0..1). Sorts a copy — value-only,
## so the built-in numeric sort is deterministic without an index tie-break.
static func _rank_value(arr: PackedFloat32Array, frac: float) -> float:
	var s := arr.duplicate()
	s.sort()
	return s[clampi(int(floor(frac * float(s.size()))), 0, s.size() - 1)]


## 8-connected multi-source BFS distance (in cells) from the nearest ocean cell.
## Ocean cells = 0; land cells = hops to the coast. Index-order seeding + fixed
## D8 order → deterministic.
static func _coast_distance(is_land: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var n := w * h
	var dist := PackedInt32Array()
	dist.resize(n)
	for i in range(n):
		dist[i] = -1
	var frontier: Array[Vector2i] = []
	for row in range(h):
		for col in range(w):
			if is_land[row * w + col] == 0:
				dist[row * w + col] = 0
				frontier.append(Vector2i(col, row))
	var d := 0
	while not frontier.is_empty():
		d += 1
		var nxt: Array[Vector2i] = []
		for cell in frontier:
			for off: Vector2i in GeoField.D8:
				var nc := cell.x + off.x
				var nr := cell.y + off.y
				if nc < 0 or nc >= w or nr < 0 or nr >= h:
					continue
				var ni := nr * w + nc
				if dist[ni] != -1:
					continue
				dist[ni] = d
				nxt.append(Vector2i(nc, nr))
		frontier = nxt
	return dist


## Central-difference gradient magnitude of a scalar field at (col,row).
static func _grad_mag(arr: PackedFloat32Array, w: int, h: int, col: int, row: int) -> float:
	var xl := arr[row * w + maxi(col - 1, 0)]
	var xr := arr[row * w + mini(col + 1, w - 1)]
	var yt := arr[maxi(row - 1, 0) * w + col]
	var yb := arr[mini(row + 1, h - 1) * w + col]
	var gx := (xr - xl) * 0.5
	var gy := (yb - yt) * 0.5
	return sqrt(gx * gx + gy * gy)


## In-place per-style cleanup: sink land components < MIN_LAND, fill fully-enclosed
## ocean pockets < MIN_OCEAN. Connectivity is fixed, so component membership (hence
## the kept/removed decision) is deterministic regardless of BFS pop order.
static func _morphological_cleanup(is_land: PackedByteArray, w: int, h: int, style: String) -> void:
	var n := w * h
	var min_land: int = int(_MIN_LAND_CELLS.get(style, 64))
	var min_ocean: int = int(_MIN_OCEAN_CELLS.get(style, 40))

	# Pass 1: land components.
	var seen := PackedByteArray()
	seen.resize(n)
	for row in range(h):
		for col in range(w):
			var start := row * w + col
			if is_land[start] != 1 or seen[start] == 1:
				continue
			var comp: Array[int] = []
			var q: Array[Vector2i] = [Vector2i(col, row)]
			seen[start] = 1
			while not q.is_empty():
				var c: Vector2i = q.pop_back()
				comp.append(c.y * w + c.x)
				for off: Vector2i in GeoField.D8:
					var nc := c.x + off.x
					var nr := c.y + off.y
					if nc < 0 or nc >= w or nr < 0 or nr >= h:
						continue
					var ni := nr * w + nc
					if is_land[ni] == 1 and seen[ni] == 0:
						seen[ni] = 1
						q.append(Vector2i(nc, nr))
			if comp.size() < min_land:
				for ci in comp:
					is_land[ci] = 0

	# Pass 2: ocean components — fill landlocked pockets below the size floor.
	seen.fill(0)
	for row in range(h):
		for col in range(w):
			var start := row * w + col
			if is_land[start] != 0 or seen[start] == 1:
				continue
			var comp: Array[int] = []
			var touches_border := false
			var q: Array[Vector2i] = [Vector2i(col, row)]
			seen[start] = 1
			while not q.is_empty():
				var c: Vector2i = q.pop_back()
				comp.append(c.y * w + c.x)
				if c.x == 0 or c.y == 0 or c.x == w - 1 or c.y == h - 1:
					touches_border = true
				for off: Vector2i in GeoField.D8:
					var nc := c.x + off.x
					var nr := c.y + off.y
					if nc < 0 or nc >= w or nr < 0 or nr >= h:
						continue
					var ni := nr * w + nc
					if is_land[ni] == 0 and seen[ni] == 0:
						seen[ni] = 1
						q.append(Vector2i(nc, nr))
			if not touches_border and comp.size() < min_ocean:
				for ci in comp:
					is_land[ci] = 1


## Monotone 4-knot piecewise-linear transfer through
## (x0,y0)-(x1,y1)-(x2,y2)-(x3,y3) with x0<=x1<=x2<=x3.
static func _piecewise(x: float, x0: float, y0: float, x1: float, y1: float,
		x2: float, y2: float, x3: float, y3: float) -> float:
	if x <= x0:
		return y0
	if x < x1:
		return y0 + (y1 - y0) * (x - x0) / maxf(x1 - x0, 0.000001)
	if x < x2:
		return y1 + (y2 - y1) * (x - x1) / maxf(x2 - x1, 0.000001)
	if x < x3:
		return y2 + (y3 - y2) * (x - x2) / maxf(x3 - x2, 0.000001)
	return y3


# ---------------------------------------------------------------------------
# Crest-preserving thermal erosion (talus relaxation; delta-accumulated →
# order-independent). Skips mountain crests so cordillera stay sharp.
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
				if hi >= MOUNTAIN_PRESERVE:
					continue  # never relax a crest cell (it would round into a dome)
				for d: Vector2i in GeoField.D8:
					var nc := col + d.x
					var nr := row + d.y
					if nc < 0 or nc >= w or nr < 0 or nr >= h:
						continue
					var ni := nr * w + nc
					if field.surface[ni] >= MOUNTAIN_PRESERVE:
						continue  # don't pull material off a crest neighbour either
					var diff := hi - field.surface[ni]
					if diff > TALUS:
						var move := (diff - TALUS) * THERMAL_RATE * 0.5
						delta[i] -= move
						delta[ni] += move
		for i in range(n):
			field.surface[i] = clampf(field.surface[i] + delta[i], 0.0, 1.0)


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
