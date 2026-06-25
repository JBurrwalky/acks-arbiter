class_name GeoRiverMapper
extends RefCounted

## Maps a hex grid's terrain into HexRiverEdgeData hex-edge rivers by running
## drainage on the hex-CORNER graph (the dual honeycomb). Rivers run ALONG hex
## boundaries (corner→corner), matching hex_map_renderer._draw_river_edge and the
## ACKS river-as-edge convention (crossings = bridge/ford/ferry on the edge).
##
## WHY corner-graph drainage, not the field's 6-mile cell network: the cell network
## is fragmented (measured max Strahler ≈ 2, no large trunks). Aggregating onto the
## coarser hex-corner graph merges sub-basins into proper trunk rivers (Strahler
## climbs), and the corner graph IS the along-edge representation the renderer draws
## — no lossy center-flow→edge conversion. Replaces the interim greedy vertex-walk
## (HeightmapGenerator._trace_rivers), which used no drainage area (fake log2 width)
## and a local-peak source heuristic.
##
## SCALE-AGNOSTIC: consumes any hex grid (the 24-mile world map OR a materialized
## 6-mile region) carrying elevation_raw + water. So both scales' rivers come from
## ONE algorithm on grids sampled from the same field → cross-scale consistency
## (gdd-continuous-geography.md §8).
##
## Pipeline (the DEM hydrology chain, on corners): enumerate corners → corner
## elevation (mean of the 3 touching hexes) → Priority-Flood(+ε) from ocean/edge
## outlets → steepest-descent flow direction → flow accumulation → channel
## extraction (FAT per river_density) + Strahler → emit canonical edges, width +
## navigability by Strahler order.
##
## Determinism (coding_conventions §80): corners enumerated in hex offset (col,row)
## order; the heap and both sorts carry a total-order tie-break by corner index; no
## Dictionary-order draws.

const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]
const FILL_EPSILON := 0.00001
## Channel iff corner accumulation ≥ this, per river_density. Corner-scale (each
## corner ≈ one 24-mile triple-junction), so far smaller than the 6-mile cell FAT.
const _FAT_BY_DENSITY := {"low": 22.0, "medium": 13.0, "high": 7.0}
## width_category → navigability (gdd-terrain-system §3.6.4 / continuous-geography §5).
const _NAV_BY_WIDTH := {
	"stream": "none", "creek": "small_craft",
	"river": "river_craft", "major_river": "large_craft",
}
## Diagnostic only (calibration of the width thresholds): the max corner discharge
## of the most recent map_rivers() call. Not part of the output / determinism.
static var debug_max_accum := 0.0


## Build the river-edge rows (same dict shape as HeightmapGenerator._trace_rivers /
## SettingRepository.RIVER_EDGE_COLUMNS) for a hex grid. dims = hex (cols, rows).
static func map_rivers(params, dims: Vector2i, grid: Dictionary) -> Array:
	# --- 1. enumerate corners (hex offset order; dedup by canonical key) ---
	var corner_index := {}   # vertex_key → int
	var corners: Array = []   # Array of vertex (Array[Vector2i], the 3 touching hexes)
	for row in range(dims.y):
		for col in range(dims.x):
			var hex := WorldGrid.offset_to_axial(col, row)
			if not grid.has(hex):
				continue
			for c in range(6):
				var v := _corner_vertex(hex, c)
				var key := _vertex_key(v)
				if not corner_index.has(key):
					corner_index[key] = corners.size()
					corners.append(v)
	var n := corners.size()
	if n == 0:
		return []

	# --- 2. corner elevation + ocean/edge outlet flag ---
	var elev := PackedFloat32Array()
	elev.resize(n)
	var is_outlet := PackedByteArray()
	is_outlet.resize(n)
	for i in range(n):
		var v: Array = corners[i]
		var sum := 0.0
		var outlet := false
		for h in v:
			if not grid.has(h):
				outlet = true  # off-map edge: water drains away here
			elif str(grid[h]["water"]) == "ocean":
				outlet = true  # sea outlet; contributes 0 to the mean
			else:
				sum += float(grid[h]["elevation_raw"])
		elev[i] = sum / 3.0
		is_outlet[i] = 1 if outlet else 0

	# --- 3. corner adjacency: [neighbor_idx, shared_hex_a, shared_hex_b] ---
	var adj: Array = []
	adj.resize(n)
	for i in range(n):
		var v: Array = corners[i]
		var lst: Array = []
		for pair in _incident_edges(v):
			var w := _other_endpoint(v, pair)
			var wk := _vertex_key(w)
			if corner_index.has(wk):
				lst.append([int(corner_index[wk]), pair[0], pair[1]])
		adj[i] = lst

	# --- 4. Priority-Flood (+ε) from the outlets inward ---
	var filled := elev.duplicate()
	var closed := PackedByteArray()
	closed.resize(n)
	var heap: Array = []
	for i in range(n):
		if is_outlet[i] == 1:
			closed[i] = 1
			_heap_push(heap, filled[i], i)
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var ch: float = top[0]
		var ci: int = top[1]
		for e in adj[ci]:
			var ni: int = e[0]
			if closed[ni] != 0:
				continue
			closed[ni] = 1
			if filled[ni] <= ch + FILL_EPSILON:
				filled[ni] = ch + FILL_EPSILON
			_heap_push(heap, filled[ni], ni)

	# --- 5. flow direction (steepest descent on the filled corner DEM) ---
	var flow_to := PackedInt32Array()
	flow_to.resize(n)
	var flow_edge: Array = []   # per corner: [a, b] shared hexes of the chosen edge
	flow_edge.resize(n)
	for i in range(n):
		flow_to[i] = -1
		flow_edge[i] = []
		if is_outlet[i] == 1 or closed[i] == 0:
			continue
		var best := -1
		var best_drop := 0.0
		var best_pair: Array = []
		for e in adj[i]:
			var ni: int = e[0]
			var drop := filled[i] - filled[ni]
			if drop > best_drop:
				best_drop = drop
				best = ni
				best_pair = [e[1], e[2]]
		flow_to[i] = best
		flow_edge[i] = best_pair

	# --- 6. flow accumulation (push in descending filled-height order) ---
	var accum := PackedFloat32Array()
	accum.resize(n)
	accum.fill(1.0)
	var order_idx: Array = []
	order_idx.resize(n)
	for i in range(n):
		order_idx[i] = i
	order_idx.sort_custom(func(a, b):
		return filled[a] > filled[b] if filled[a] != filled[b] else a < b)
	for i in order_idx:
		var d: int = flow_to[i]
		if d >= 0:
			accum[d] += accum[i]

	# --- 7. channel extraction + Strahler order ---
	var fat := float(_FAT_BY_DENSITY.get(params.river_density, 13.0))
	var is_ch := PackedByteArray()
	is_ch.resize(n)
	var ch_list: Array = []
	for i in range(n):
		if is_outlet[i] == 0 and accum[i] >= fat:
			is_ch[i] = 1
			ch_list.append(i)
	# Ascending accum is topological (accum grows downstream).
	ch_list.sort_custom(func(a, b):
		return accum[a] < accum[b] if accum[a] != accum[b] else a < b)
	var strahler := PackedInt32Array()
	strahler.resize(n)
	var max_in := PackedInt32Array()
	max_in.resize(n)
	var cnt_at_max := PackedInt32Array()
	cnt_at_max.resize(n)
	for i in ch_list:
		var ordv := 1
		if max_in[i] > 0:
			ordv = max_in[i] + 1 if cnt_at_max[i] >= 2 else max_in[i]
		strahler[i] = ordv
		var d: int = flow_to[i]
		if d < 0 or is_ch[d] == 0:
			continue
		if ordv > max_in[d]:
			max_in[d] = ordv
			cnt_at_max[d] = 1
		elif ordv == max_in[d]:
			cnt_at_max[d] += 1

	# --- 8. emit canonical hex-edge rows (channel corner → its downstream step) ---
	debug_max_accum = 0.0
	for i in ch_list:
		debug_max_accum = maxf(debug_max_accum, accum[i])
	var edges := {}
	var edge_order: Array = []
	for i in ch_list:
		var d: int = flow_to[i]
		if d < 0:
			continue
		var pair: Array = flow_edge[i]
		if pair.is_empty():
			continue
		_emit_edge(pair[0], pair[1], corners[i], corners[d], accum[i], fat, edges, edge_order)
	var rows: Array = []
	for ek in edge_order:
		rows.append(edges[ek]["row"])
	return rows


# ---------------------------------------------------------------------------
# Edge emission (canonical owner + edge index + flow_clockwise + width)
# ---------------------------------------------------------------------------

static func _emit_edge(a: Vector2i, b: Vector2i, from_v: Array, to_v: Array,
		accum_val: float, fat: float, edges: Dictionary, edge_order: Array) -> void:
	# Canonical owner = lexicographically lower (q, r) of the two adjacent hexes.
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
		return
	var ek := "%d,%d,%d" % [owner.x, owner.y, edge_index]
	var width := _width_for_accum(accum_val, fat)
	if edges.has(ek):
		# Already traced from the other corner; keep the larger river.
		if _width_rank(width) > _width_rank(str(edges[ek]["row"]["width_category"])):
			edges[ek]["row"]["width_category"] = width
			edges[ek]["row"]["navigability"] = _NAV_BY_WIDTH[width]
		return
	# flow_clockwise (§3.6.3): downstream vertex is the corner shared with edge
	# (e+1)%6 — i.e. corner `edge_index` of the owner — when clockwise.
	var cw_vertex := _corner_vertex(owner, edge_index)
	var flow_clockwise := _vertex_key(to_v) == _vertex_key(cw_vertex)
	edges[ek] = {
		"row": {
			"hex_q": owner.x, "hex_r": owner.y, "edge": edge_index,
			"flow_clockwise": 1 if flow_clockwise else 0,
			"width_category": width, "navigability": _NAV_BY_WIDTH[width],
			"crossing": "none",
		},
	}
	edge_order.append(ek)


## Discharge (flow accumulation) → width_category, as multiples of the channel
## threshold FAT. Strahler caps at ~3 on the corner graph (the drainage doesn't
## branch deeply), so accumulation — which has a real dynamic range up the trunk —
## drives width: a high-discharge trunk reads as a major river even at Strahler 3.
static func _width_for_accum(accum_val: float, fat: float) -> String:
	if accum_val >= 12.0 * fat:
		return "major_river"
	if accum_val >= 5.0 * fat:
		return "river"
	if accum_val >= 2.5 * fat:
		return "creek"
	return "stream"


static func _width_rank(width: String) -> int:
	match width:
		"major_river":
			return 3
		"river":
			return 2
		"creek":
			return 1
		_:
			return 0


# ---------------------------------------------------------------------------
# Hex-corner graph helpers (the dual honeycomb). A corner = the canonical sorted
# 3-hex touching set; two corners are adjacent iff they share two hexes (the edge
# between those two hexes).
# ---------------------------------------------------------------------------

static func _make_vertex(a: Vector2i, b: Vector2i, c: Vector2i) -> Array:
	var arr: Array[Vector2i] = [a, b, c]
	arr.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		return x.y < y.y or (x.y == y.y and x.x < y.x))
	return arr


static func _vertex_key(v: Array) -> String:
	return "%d,%d|%d,%d|%d,%d" % [v[0].x, v[0].y, v[1].x, v[1].y, v[2].x, v[2].y]


static func _corner_vertex(hex: Vector2i, c: int) -> Array:
	return _make_vertex(hex, hex + _OFF[c], hex + _OFF[(c + 1) % 6])


static func _incident_edges(v: Array) -> Array:
	return [[v[0], v[1]], [v[0], v[2]], [v[1], v[2]]]


## The other endpoint vertex of hex-pair edge [a, b] from vertex v: the third hex
## reflects to the opposite side (mirror = a + b − third; axial coords are affine).
static func _other_endpoint(v: Array, edge_pair: Array) -> Array:
	var a: Vector2i = edge_pair[0]
	var b: Vector2i = edge_pair[1]
	var third := Vector2i.ZERO
	for h in v:
		if h != a and h != b:
			third = h
			break
	var mirror := a + b - third
	return _make_vertex(a, b, mirror)


# ---------------------------------------------------------------------------
# Binary min-heap over [height, idx], ordered by height then idx.
# ---------------------------------------------------------------------------

static func _heap_push(heap: Array, hgt: float, i: int) -> void:
	heap.append([hgt, i])
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
