extends "res://tests/test_suite_base.gd"

## Unit tests for migration 130 river-edge data model (GDD §3.6).
##
## Coverage:
##   * HexRiverEdgeData.canonicalize_edge for adjacent / non-adjacent pairs.
##   * HexRiverEdgeData.flip_to_canonical inverts owner + flow direction.
##   * CampaignRepository.save_hex_river_edge canonicalizes non-canonical input.
##   * Two-sided get_river_edges_for_hex returns the same edge from either side.
##   * Bulk get_river_edges_for_map, fast hex_has_river predicate.
##   * Cross-map isolation: edges on map A do not appear in map B's queries.
##   * Round-trip via save_hex_map / load_hex_map populates river_edges and
##     stamps has_river_cached on both endpoint terrains.
##   * JSON loader auto-flips non-canonical input.


const TEST_CAMPAIGN := "test_rivers_campaign"
const MAP_A := "test_rivers_map_a"
const MAP_B := "test_rivers_map_b"


func run_all_tests() -> void:
	test_canonicalize_returns_canonical_owner()
	test_canonicalize_rejects_non_adjacent()
	test_canonicalize_handles_both_directions()
	test_flip_to_canonical_inverts_owner_and_flow()
	test_is_canonical_predicate()
	test_save_canonicalizes_non_canonical_input()
	test_two_sided_lookup_owner_side()
	test_two_sided_lookup_neighbor_side()
	test_hex_has_river_both_sides()
	test_get_river_edges_for_map_bulk()
	test_cross_map_isolation()
	test_round_trip_through_hex_map_data()
	test_elevation_raw_and_subtype_round_trip()
	test_loader_auto_flips_non_canonical_json()
	test_loader_drops_non_adjacent_warning_ok()
	test_terrain_has_river_cached_on_load()

	_cleanup()
	if not has_failures():
		print("HexRiverEdges: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_campaign() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Rivers Test"])


func _make_minimal_map(map_id: String) -> HexMapData:
	var m := HexMapData.new()
	m.id = map_id
	m.name = "Rivers Test %s" % map_id
	m.scale = HexMapData.MapScale.REGIONAL_6MI
	# Generate a small patch so any (q, r) used below is a valid cell.
	for q in range(-2, 3):
		for r in range(-2, 3):
			var t := HexTerrainData.new()
			t.elevation = "flat"
			t.biome = "clear"
			t.water = ""
			t.civilization = "wilderness"
			t.has_city = false
			t.original_biome = ""
			m.hexes[Vector2i(q, r)] = t
	return m


func _cleanup() -> void:
	for m in [MAP_A, MAP_B]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM hex_river_edges WHERE map_id = ?", [m])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM hex_overlays WHERE map_id = ?", [m])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM hex_cells WHERE map_id = ?", [m])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM hex_maps WHERE id = ?", [m])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


# ---------------------------------------------------------------------------
# canonicalize_edge / flip / is_canonical
# ---------------------------------------------------------------------------

func test_canonicalize_returns_canonical_owner() -> void:
	# Edge from (0, 0) S (edge=3) to (0, 1). (0, 0) is lex-lower so it owns.
	var info := HexRiverEdgeData.canonicalize_edge(0, 0, 0, 1)
	check(info.get("adjacent", false), "should be adjacent")
	check(info["hex_q"] == 0 and info["hex_r"] == 0,
		"owner should be (0, 0); got (%d, %d)" % [int(info["hex_q"]), int(info["hex_r"])])
	check(int(info["edge"]) == 3, "edge should be S (3); got %d" % int(info["edge"]))
	print("  canonicalize_returns_canonical_owner: OK")


func test_canonicalize_handles_both_directions() -> void:
	# Calling with arguments swapped should yield the same canonical owner.
	var info_a := HexRiverEdgeData.canonicalize_edge(1, 1, 0, 1)
	var info_b := HexRiverEdgeData.canonicalize_edge(0, 1, 1, 1)
	check(info_a.get("adjacent", false), "swapped a should be adjacent")
	check(info_b.get("adjacent", false), "swapped b should be adjacent")
	check(info_a["hex_q"] == info_b["hex_q"] and info_a["hex_r"] == info_b["hex_r"],
		"owner identical regardless of argument order")
	check(int(info_a["edge"]) == int(info_b["edge"]),
		"edge index identical regardless of argument order")
	print("  canonicalize_handles_both_directions: OK")


func test_canonicalize_rejects_non_adjacent() -> void:
	var info := HexRiverEdgeData.canonicalize_edge(0, 0, 3, 3)
	check(not info.get("adjacent", false),
		"non-adjacent pair should return adjacent=false")
	print("  canonicalize_rejects_non_adjacent: OK")


func test_flip_to_canonical_inverts_owner_and_flow() -> void:
	# Start with non-canonical: hex (0, 1) edge 0 (N) → neighbor (0, 0). Since
	# (0, 0) < (0, 1) the canonical owner is (0, 0) on edge 3.
	var e := HexRiverEdgeData.new()
	e.hex_q = 0
	e.hex_r = 1
	e.edge = 0
	e.flow_clockwise = true
	check(not e.is_canonical(), "starts non-canonical")
	e.flip_to_canonical()
	check(e.hex_q == 0 and e.hex_r == 0, "flipped owner should be (0, 0)")
	check(e.edge == 3, "flipped edge should be 3 (S)")
	check(e.flow_clockwise == false, "flow direction should flip")
	check(e.is_canonical(), "should be canonical after flip")
	print("  flip_to_canonical_inverts_owner_and_flow: OK")


func test_is_canonical_predicate() -> void:
	var ok := HexRiverEdgeData.new()
	ok.hex_q = 0; ok.hex_r = 0; ok.edge = 3   # → neighbor (0, 1), (0, 0) is lower
	check(ok.is_canonical(), "(0,0) edge 3 should be canonical")
	var bad := HexRiverEdgeData.new()
	bad.hex_q = 0; bad.hex_r = 1; bad.edge = 0  # → neighbor (0, 0), (0, 0) is lower
	check(not bad.is_canonical(), "(0,1) edge 0 should be non-canonical")
	print("  is_canonical_predicate: OK")


# ---------------------------------------------------------------------------
# Repository persistence
# ---------------------------------------------------------------------------

func test_save_canonicalizes_non_canonical_input() -> void:
	_setup_campaign()
	check(CampaignRepository.save_hex_map(_make_minimal_map(MAP_A), TEST_CAMPAIGN),
		"map should save")
	var non_canonical := HexRiverEdgeData.new()
	non_canonical.hex_q = 0
	non_canonical.hex_r = 1
	non_canonical.edge = 0  # N — neighbor is (0, 0), canonical owner
	non_canonical.flow_clockwise = true
	non_canonical.navigability = HexRiverEdgeData.NAV_RIVER_CRAFT
	non_canonical.crossing = HexRiverEdgeData.CROSSING_NONE
	check(CampaignRepository.save_hex_river_edge(MAP_A, non_canonical),
		"save should accept non-canonical row")
	# The row should be stored at the canonical owner (0, 0) edge 3.
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM hex_river_edges WHERE map_id = ?", [MAP_A]):
		check(false, "select failed")
		return
	check(CampaignRepository.db.query_result.size() == 1,
		"expected 1 row; got %d" % CampaignRepository.db.query_result.size())
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(int(row["hex_q"]) == 0 and int(row["hex_r"]) == 0,
		"row owner should be (0,0); got (%d,%d)" % [int(row["hex_q"]), int(row["hex_r"])])
	check(int(row["edge"]) == 3, "row edge should be 3; got %d" % int(row["edge"]))
	check(int(row["flow_clockwise"]) == 0,
		"flow_clockwise should be inverted (0); got %d" % int(row["flow_clockwise"]))
	_cleanup()
	print("  save_canonicalizes_non_canonical_input: OK")


func test_two_sided_lookup_owner_side() -> void:
	_setup_campaign()
	check(CampaignRepository.save_hex_map(_make_minimal_map(MAP_A), TEST_CAMPAIGN),
		"map should save")
	var e := HexRiverEdgeData.new()
	e.hex_q = 0; e.hex_r = 0; e.edge = 3  # canonical
	check(CampaignRepository.save_hex_river_edge(MAP_A, e),
		"save canonical row")
	var results: Array = CampaignRepository.get_river_edges_for_hex(MAP_A, 0, 0)
	check(results.size() == 1,
		"owner-side query should return 1 row; got %d" % results.size())
	_cleanup()
	print("  two_sided_lookup_owner_side: OK")


func test_two_sided_lookup_neighbor_side() -> void:
	_setup_campaign()
	check(CampaignRepository.save_hex_map(_make_minimal_map(MAP_A), TEST_CAMPAIGN),
		"map should save")
	var e := HexRiverEdgeData.new()
	e.hex_q = 0; e.hex_r = 0; e.edge = 3  # neighbor is (0, 1)
	check(CampaignRepository.save_hex_river_edge(MAP_A, e),
		"save canonical row")
	# Query from the NON-owner side.
	var results: Array = CampaignRepository.get_river_edges_for_hex(MAP_A, 0, 1)
	check(results.size() == 1,
		"neighbor-side query should return 1 row; got %d" % results.size())
	# Querying from a hex that isn't touched should return empty.
	var empty_results: Array = CampaignRepository.get_river_edges_for_hex(MAP_A, 2, 2)
	check(empty_results.is_empty(),
		"untouched hex should have no edges; got %d" % empty_results.size())
	_cleanup()
	print("  two_sided_lookup_neighbor_side: OK")


func test_hex_has_river_both_sides() -> void:
	_setup_campaign()
	check(CampaignRepository.save_hex_map(_make_minimal_map(MAP_A), TEST_CAMPAIGN),
		"map should save")
	var e := HexRiverEdgeData.new()
	e.hex_q = 0; e.hex_r = 0; e.edge = 3
	check(CampaignRepository.save_hex_river_edge(MAP_A, e),
		"save canonical row")
	check(CampaignRepository.hex_has_river(MAP_A, 0, 0), "owner-side hex has river")
	check(CampaignRepository.hex_has_river(MAP_A, 0, 1), "neighbor-side hex has river")
	check(not CampaignRepository.hex_has_river(MAP_A, 2, 2),
		"untouched hex should not have river")
	_cleanup()
	print("  hex_has_river_both_sides: OK")


func test_get_river_edges_for_map_bulk() -> void:
	_setup_campaign()
	check(CampaignRepository.save_hex_map(_make_minimal_map(MAP_A), TEST_CAMPAIGN),
		"map should save")
	for spec in [[0, 0, 3], [-1, 0, 3], [0, -1, 3]]:
		var e := HexRiverEdgeData.new()
		e.hex_q = int(spec[0]); e.hex_r = int(spec[1]); e.edge = int(spec[2])
		check(CampaignRepository.save_hex_river_edge(MAP_A, e),
			"save row (%d,%d,%d)" % [int(spec[0]), int(spec[1]), int(spec[2])])
	var bulk: Array = CampaignRepository.get_river_edges_for_map(MAP_A)
	check(bulk.size() == 3, "bulk fetch should return 3 rows; got %d" % bulk.size())
	_cleanup()
	print("  get_river_edges_for_map_bulk: OK")


func test_cross_map_isolation() -> void:
	_setup_campaign()
	check(CampaignRepository.save_hex_map(_make_minimal_map(MAP_A), TEST_CAMPAIGN),
		"map A should save")
	check(CampaignRepository.save_hex_map(_make_minimal_map(MAP_B), TEST_CAMPAIGN),
		"map B should save")
	var e := HexRiverEdgeData.new()
	e.hex_q = 0; e.hex_r = 0; e.edge = 3
	check(CampaignRepository.save_hex_river_edge(MAP_A, e),
		"save on map A")
	check(CampaignRepository.hex_has_river(MAP_A, 0, 0), "map A hex has river")
	check(not CampaignRepository.hex_has_river(MAP_B, 0, 0),
		"map B hex should NOT have river despite same coords")
	check(CampaignRepository.get_river_edges_for_map(MAP_B).is_empty(),
		"map B bulk fetch should be empty")
	_cleanup()
	print("  cross_map_isolation: OK")


# ---------------------------------------------------------------------------
# Round-trip via save_hex_map / load_hex_map
# ---------------------------------------------------------------------------

func test_round_trip_through_hex_map_data() -> void:
	_setup_campaign()
	var m := _make_minimal_map(MAP_A)
	var e1 := HexRiverEdgeData.new()
	e1.hex_q = 0; e1.hex_r = 0; e1.edge = 3
	e1.flow_clockwise = true
	e1.navigability = HexRiverEdgeData.NAV_LARGE_CRAFT
	e1.crossing = HexRiverEdgeData.CROSSING_BRIDGE
	m.river_edges.append(e1)
	check(CampaignRepository.save_hex_map(m, TEST_CAMPAIGN),
		"map with river edges should save")
	var loaded := CampaignRepository.load_hex_map(MAP_A)
	check(loaded != null, "map should load")
	check(loaded.river_edges.size() == 1,
		"loaded map should carry 1 river edge; got %d" % loaded.river_edges.size())
	var got: HexRiverEdgeData = loaded.river_edges[0]
	check(got.hex_q == 0 and got.hex_r == 0 and got.edge == 3, "edge identity round-trip")
	check(got.flow_clockwise == true, "flow direction round-trip")
	check(got.navigability == HexRiverEdgeData.NAV_LARGE_CRAFT, "navigability round-trip")
	check(got.crossing == HexRiverEdgeData.CROSSING_BRIDGE, "crossing round-trip")
	_cleanup()
	print("  round_trip_through_hex_map_data: OK")


func test_elevation_raw_and_subtype_round_trip() -> void:
	# Regression (2026-06-26): save_hex_map's INSERT omitted elevation_raw +
	# biome_subtype, so INSERT OR REPLACE reset both to the column default on every
	# save — the in-game Get Hex Info panel then read 0.0 raw elevation even on
	# mountains. Both must survive a full save_hex_map -> load_hex_map round-trip.
	_setup_campaign()
	var m := _make_minimal_map(MAP_A)
	var peak: HexTerrainData = m.hexes[Vector2i(0, 0)]
	peak.elevation = "mountains"
	peak.elevation_raw = 0.873
	peak.biome_subtype = "mountains_volcanic"
	check(CampaignRepository.save_hex_map(m, TEST_CAMPAIGN), "map should save")
	var loaded := CampaignRepository.load_hex_map(MAP_A)
	check(loaded != null, "map should load")
	var rt: HexTerrainData = loaded.get_hex(Vector2i(0, 0))
	check(rt != null, "peak hex should load")
	check(absf(rt.elevation_raw - 0.873) < 1.0e-4,
		"elevation_raw must round-trip; got %f" % rt.elevation_raw)
	check(rt.biome_subtype == "mountains_volcanic",
		"biome_subtype must round-trip; got '%s'" % rt.biome_subtype)
	_cleanup()
	print("  elevation_raw_and_subtype_round_trip: OK")


func test_terrain_has_river_cached_on_load() -> void:
	_setup_campaign()
	var m := _make_minimal_map(MAP_A)
	var e := HexRiverEdgeData.new()
	e.hex_q = 0; e.hex_r = 0; e.edge = 3
	m.river_edges.append(e)
	check(CampaignRepository.save_hex_map(m, TEST_CAMPAIGN),
		"map should save")
	var loaded := CampaignRepository.load_hex_map(MAP_A)
	check(loaded != null, "map should load")
	# Both endpoint terrains should have has_river_cached = true.
	var owner_terrain: HexTerrainData = loaded.get_hex(Vector2i(0, 0))
	var neighbor_terrain: HexTerrainData = loaded.get_hex(Vector2i(0, 1))
	check(owner_terrain != null and owner_terrain.has_river(),
		"owner terrain should have has_river() == true")
	check(neighbor_terrain != null and neighbor_terrain.has_river(),
		"neighbor terrain should have has_river() == true")
	var untouched: HexTerrainData = loaded.get_hex(Vector2i(2, 2))
	check(untouched != null and not untouched.has_river(),
		"untouched terrain should have has_river() == false")
	_cleanup()
	print("  terrain_has_river_cached_on_load: OK")


# ---------------------------------------------------------------------------
# JSON loader path
# ---------------------------------------------------------------------------

func test_loader_auto_flips_non_canonical_json() -> void:
	# Author the edge from the non-owner side; loader should auto-flip.
	var json := {
		"id": "json_test_map",
		"name": "JSON Test",
		"scale": "regional_6mi",
		"party_hex": {"q": 0, "r": 0},
		"hexes": [
			{"q": 0, "r": 0, "elevation": "flat", "biome": "clear", "water": "",
			 "civilization": "wilderness", "has_city": false, "original_biome": "", "settlement_ids": []},
			{"q": 0, "r": 1, "elevation": "flat", "biome": "clear", "water": "",
			 "civilization": "wilderness", "has_city": false, "original_biome": "", "settlement_ids": []},
		],
		"river_edges": [
			{
				"hex": [0, 1], "edge": 0,  # N of (0,1) → (0,0). Non-canonical.
				"flow_clockwise": true,
				"navigability": "river_craft",
				"crossing": "none",
			},
		],
	}
	var m: HexMapData = HexMapData.from_dict(json)
	check(m.river_edges.size() == 1, "should have 1 river edge")
	var edge_data: HexRiverEdgeData = m.river_edges[0]
	check(edge_data.hex_q == 0 and edge_data.hex_r == 0,
		"auto-flipped owner should be (0, 0); got (%d, %d)"
		% [edge_data.hex_q, edge_data.hex_r])
	check(edge_data.edge == 3,
		"auto-flipped edge should be 3 (S); got %d" % edge_data.edge)
	# Cached flag on both endpoint terrains.
	var t0: HexTerrainData = m.get_hex(Vector2i(0, 0))
	var t1: HexTerrainData = m.get_hex(Vector2i(0, 1))
	check(t0 != null and t0.has_river(), "owner terrain marked has_river")
	check(t1 != null and t1.has_river(), "neighbor terrain marked has_river")
	print("  loader_auto_flips_non_canonical_json: OK")


func test_loader_drops_non_adjacent_warning_ok() -> void:
	# An edge entry referencing a non-existent hex coordinate just gets stamped
	# with has_river_cached=false on missing terrains; the edge itself still
	# loads. This test verifies that doesn't break the loader.
	var json := {
		"id": "json_drop_map",
		"name": "JSON Drop Test",
		"scale": "regional_6mi",
		"party_hex": {"q": 0, "r": 0},
		"hexes": [
			{"q": 0, "r": 0, "elevation": "flat", "biome": "clear", "water": "",
			 "civilization": "wilderness", "has_city": false, "original_biome": "", "settlement_ids": []},
		],
		"river_edges": [
			{
				"hex": [0, 0], "edge": 3,
				"flow_clockwise": true,
				"navigability": "river_craft",
				"crossing": "none",
			},
		],
	}
	var m: HexMapData = HexMapData.from_dict(json)
	check(m.river_edges.size() == 1, "edge should still load")
	# (0, 0) is the owner; its has_river_cached should be true even though
	# the neighbor cell (0, 1) is not in the map.
	var t0: HexTerrainData = m.get_hex(Vector2i(0, 0))
	check(t0 != null and t0.has_river(), "owner has river even with missing neighbor")
	print("  loader_drops_non_adjacent_warning_ok: OK")
