extends "res://tests/test_suite_base.gd"

## GeoRiverMapper — corner-graph drainage → HexRiverEdgeData hex-edge rivers
## (gdd-continuous-geography.md §5/§8). Validates a valid, deterministic, and RICH
## river network: aggregating the field's fragmented 6-mile drainage (measured max
## Strahler ≈ 2) onto the coarser hex-corner graph must build trunk rivers (widths
## beyond 'stream') that discharge to the sea.
##
## Runs through GeoFieldToGrid.run() (autoloads available under the test runner, so
## WorldGrid/HexMapController resolve — unlike the bare --script visualizer).

const VALID_WIDTH := ["stream", "creek", "river", "major_river"]
const VALID_NAV := ["none", "small_craft", "river_craft", "large_craft"]
const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


func run_all_tests() -> void:
	test_edges_valid_and_present()
	test_determinism()
	test_richness_and_trunks()
	test_rivers_reach_outlets()
	print("GeoRiverMapperTests: all tests passed (%d checks)" % test_count())


func _ctx(size: String, seed_val: int) -> Dictionary:
	var p := SettingParameters.new()
	p.map_size = size
	var ctx := {"params": p, "campaign_seed": seed_val}
	GeoFieldToGrid.run(ctx)
	return ctx


func test_edges_valid_and_present() -> void:
	var ctx := _ctx("medium", 42)
	var edges: Array = ctx["river_edges"]
	var grid: Dictionary = ctx["hex_grid"]
	check(edges.size() > 0, "no river edges produced")
	var bad := 0
	for e in edges:
		var owner := Vector2i(int(e["hex_q"]), int(e["hex_r"]))
		var ei := int(e["edge"])
		if ei < 0 or ei > 5 or not grid.has(owner):
			bad += 1
		elif not (str(e["width_category"]) in VALID_WIDTH and str(e["navigability"]) in VALID_NAV):
			bad += 1
	check(bad == 0, "%d river edges invalid (edge/owner/width/nav)" % bad)


func test_determinism() -> void:
	var a: Array = _ctx("medium", 7)["river_edges"]
	var b: Array = _ctx("medium", 7)["river_edges"]
	check(a.size() == b.size(), "edge count differs same-seed (%d vs %d)" % [a.size(), b.size()])
	var mism := 0
	for i in range(mini(a.size(), b.size())):
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		if int(x["hex_q"]) != int(y["hex_q"]) or int(x["hex_r"]) != int(y["hex_r"]) \
				or int(x["edge"]) != int(y["edge"]) or str(x["width_category"]) != str(y["width_category"]) \
				or int(x["flow_clockwise"]) != int(y["flow_clockwise"]):
			mism += 1
	check(mism == 0, "%d river edges differ between same-seed runs" % mism)


func test_richness_and_trunks() -> void:
	var counts := {"stream": 0, "creek": 0, "river": 0, "major_river": 0}
	for seed_val in [42, 101, 202]:
		var edges: Array = _ctx("large", seed_val)["river_edges"]
		for e in edges:
			var wc := str(e["width_category"])
			counts[wc] = int(counts.get(wc, 0)) + 1
	print("  GeoRiverMapper width totals (large, 3 seeds): %s" % str(counts))
	var non_stream: int = int(counts["creek"]) + int(counts["river"]) + int(counts["major_river"])
	check(non_stream > 0, "no rivers wider than 'stream' — corner aggregation built no trunks")


func test_rivers_reach_outlets() -> void:
	# A river mouth edge's own two hexes are always LAND (a channel corner is
	# non-ocean; the sea is the downstream corner's THIRD hex). So a river reaches
	# the sea iff some river edge's hexes are within one ring of an ocean hex (or
	# the map edge). Topologically guaranteed by the corner Priority-Flood; this
	# asserts it survives into the emitted edges.
	var ctx := _ctx("large", 101)
	var edges: Array = ctx["river_edges"]
	var grid: Dictionary = ctx["hex_grid"]
	var mouths := 0
	for e in edges:
		var owner := Vector2i(int(e["hex_q"]), int(e["hex_r"]))
		var nbr: Vector2i = owner + _OFF[int(e["edge"])]
		if _touches_outlet(owner, grid) or _touches_outlet(nbr, grid):
			mouths += 1
	check(mouths > 0, "no river reaches an ocean outlet / map edge")


## True if hex (or any of its 6 neighbours) is ocean / off the map.
func _touches_outlet(hex: Vector2i, grid: Dictionary) -> bool:
	if not grid.has(hex):
		return true
	for off in _OFF:
		var nb: Vector2i = hex + off
		if not grid.has(nb) or str(grid[nb]["water"]) == "ocean":
			return true
	return false
