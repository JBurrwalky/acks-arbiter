extends "res://tests/test_suite_base.gd"

## Unit tests for TradeRouteDetector — road / water BFS pathfinding,
## range-of-trade gating, and trade_routes cache persistence per Prereq.2b.
##
## Per generation/gdd-settlement-economy.md §5.8.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_road_path_direct_adjacent()
	test_road_path_extended_chain()
	test_road_path_no_path()
	test_road_path_requires_road_on_settlement_hex()
	test_water_path_river_chain()
	test_water_path_ocean_adjacency()
	test_range_constraint_binds_smaller_market()
	test_range_constraint_water_range_exceeds_road()
	test_mixed_path_returns_shorter_distance()
	test_pair_canonical_ordering()
	test_detection_persists_rows()
	test_is_within_mutual_range()

	if not has_failures():
		print("TradeRouteDetector: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("TradeRouteDetectorTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "TRDMap"]
	)


func _next_id() -> String:
	_suffix += 1
	return "trd_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_settlement(q: int, r: int, market_class: int = 3, name: String = "Town") -> String:
	var id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [id, _campaign_id, _map_id, q, r, name, market_class])
	return id


func _make_hex(q: int, r: int, biome: String = "clear", water: String = "") -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_cells
			(map_id, q, r, biome, biome_subtype, elevation, water)
		VALUES (?, ?, ?, ?, '', 'flat', ?)
	""", [_map_id, q, r, biome, water])


func _add_road(q: int, r: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges)
		VALUES (?, ?, ?, 'road', '[]')
	""", [_map_id, q, r])


func _add_river(q: int, r: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges)
		VALUES (?, ?, ?, 'river', '[]')
	""", [_map_id, q, r])


# ---------------------------------------------------------------------------
# Pathfinding tests
# ---------------------------------------------------------------------------

func test_road_path_direct_adjacent() -> void:
	# Two settlements on adjacent hexes both road-bearing.
	_make_hex(100, 0)
	_make_hex(101, 0)
	_add_road(100, 0)
	_add_road(101, 0)
	var a: String = _make_settlement(100, 0, 3, "RoadAdjA")
	var b: String = _make_settlement(101, 0, 3, "RoadAdjB")
	check(TradeRouteDetector.compute_road_distance(a, b) == 1,
		"road distance for adjacent road hexes should be 1")


func test_road_path_extended_chain() -> void:
	# Road chain of 6 hexes: (200,0)..(205,0)
	for q in range(200, 206):
		_make_hex(q, 0)
		_add_road(q, 0)
	var a: String = _make_settlement(200, 0, 3, "RoadChainA")
	var b: String = _make_settlement(205, 0, 3, "RoadChainB")
	check(TradeRouteDetector.compute_road_distance(a, b) == 5,
		"road chain length 5 (6 hexes inclusive) should report distance 5, got %d" % TradeRouteDetector.compute_road_distance(a, b))


func test_road_path_no_path() -> void:
	# Two isolated road hexes with no connecting road.
	_make_hex(300, 0)
	_make_hex(310, 0)
	_add_road(300, 0)
	_add_road(310, 0)
	var a: String = _make_settlement(300, 0, 3, "RoadNoPathA")
	var b: String = _make_settlement(310, 0, 3, "RoadNoPathB")
	check(TradeRouteDetector.compute_road_distance(a, b) == -1,
		"isolated road hexes with no connecting chain → no path (-1)")


func test_road_path_requires_road_on_settlement_hex() -> void:
	# Settlement A is on a road hex; B is on a non-road hex. No path.
	_make_hex(400, 0)
	_make_hex(401, 0)
	_add_road(400, 0)
	# 401 has NO road overlay.
	var a: String = _make_settlement(400, 0, 3, "RoadOnA")
	var b: String = _make_settlement(401, 0, 3, "RoadOffB")
	check(TradeRouteDetector.compute_road_distance(a, b) == -1,
		"settlement not on a road hex cannot use the road graph")


func test_water_path_river_chain() -> void:
	# Riverine settlements connected via river overlays.
	for q in range(500, 504):
		_make_hex(q, 0)
		_add_river(q, 0)
	var a: String = _make_settlement(500, 0, 3, "RiverA")
	var b: String = _make_settlement(503, 0, 3, "RiverB")
	check(TradeRouteDetector.compute_water_distance(a, b) == 3,
		"river chain (q=500..503) → distance 3, got %d" % TradeRouteDetector.compute_water_distance(a, b))


func test_water_path_ocean_adjacency() -> void:
	# Two land settlements adjacent to a chain of ocean hexes.
	# Settlement A at (600,0); ocean hexes (601,0)-(604,0); Settlement B at (605,0).
	_make_hex(600, 0)
	for q in range(601, 605):
		_make_hex(q, 0, "clear", "ocean")
	_make_hex(605, 0)
	var a: String = _make_settlement(600, 0, 3, "OceanCoastA")
	var b: String = _make_settlement(605, 0, 3, "OceanCoastB")
	# Entry node for A: (601, 0) [ocean neighbor]. Entry node for B: (604, 0).
	# BFS from (601,0) to (604,0) is distance 3.
	check(TradeRouteDetector.compute_water_distance(a, b) == 3,
		"ocean-coast settlements should pathfind via adjacent ocean hexes; expected 3, got %d" % TradeRouteDetector.compute_water_distance(a, b))


# ---------------------------------------------------------------------------
# Range gating
# ---------------------------------------------------------------------------

func test_range_constraint_binds_smaller_market() -> void:
	# 10-hex road between a Class III and a Class V.
	# Class III road range = 18; Class V road range = 8. Binding = 8.
	# Distance 10 > 8 → invalid.
	check(not TradeRouteDetector.is_within_mutual_range(3, 5, 10, "road"),
		"Class III + Class V at 10-hex road distance: V's 8-hex range binds → invalid")
	# Same pair at 8-hex road distance: V's range = 8, so 8 <= 8 → valid.
	check(TradeRouteDetector.is_within_mutual_range(3, 5, 8, "road"),
		"Class III + Class V at 8-hex road distance: within V's range → valid")
	# Class III + Class III at 10 hexes: both 18, so 10 <= 18 → valid.
	check(TradeRouteDetector.is_within_mutual_range(3, 3, 10, "road"),
		"Class III + Class III at 10-hex road distance: within range → valid")


func test_range_constraint_water_range_exceeds_road() -> void:
	# Class V settlements 14 hexes apart via water (water range = 16) → valid.
	# But same distance via road (road range = 8) → invalid.
	check(TradeRouteDetector.is_within_mutual_range(5, 5, 14, "water"),
		"Class V + Class V at 14-hex water distance: within 16-hex water range → valid")
	check(not TradeRouteDetector.is_within_mutual_range(5, 5, 14, "road"),
		"same pair at 14-hex road distance: exceeds 8-hex road range → invalid")


# ---------------------------------------------------------------------------
# Mixed path
# ---------------------------------------------------------------------------

func test_mixed_path_returns_shorter_distance() -> void:
	# Two settlements connected by BOTH a short road and a long river.
	# Road: (700,0)-(701,0). River: (700,0)-(700,1)-(701,1)-(701,0).
	# Road distance = 1; River distance = 3.
	# Expected: detection_persists_rows should record path_kind='mixed' and distance=1.
	_make_hex(700, 0)
	_make_hex(701, 0)
	_make_hex(700, 1)
	_make_hex(701, 1)
	_add_road(700, 0)
	_add_road(701, 0)
	_add_river(700, 0)
	_add_river(700, 1)
	_add_river(701, 1)
	_add_river(701, 0)
	var a: String = _make_settlement(700, 0, 3, "MixedA")
	var b: String = _make_settlement(701, 0, 3, "MixedB")
	check(TradeRouteDetector.compute_road_distance(a, b) == 1,
		"road distance should be 1 for mixed-path fixture")
	check(TradeRouteDetector.compute_water_distance(a, b) <= 1,
		"water distance ≤ 1 since rivers on both endpoint hexes count as direct adjacency")
	# Detect the route — path_kind should be 'mixed' (both valid).
	var routes: Array = TradeRouteDetector.detect_routes_for_settlement(a)
	check(routes.size() >= 1, "detect_routes_for_settlement should return at least one row")
	var mixed_route: Dictionary = {}
	for r in routes:
		if str((r as Dictionary).get("settlement_b_id", "")) == b or str((r as Dictionary).get("settlement_a_id", "")) == b:
			mixed_route = r
			break
	check(not mixed_route.is_empty(), "should have detected a route to MixedB")
	check(str(mixed_route.get("path_kind", "")) == "mixed",
		"both road + water valid → path_kind='mixed', got %s" % str(mixed_route.get("path_kind", "")))


# ---------------------------------------------------------------------------
# Persistence + canonical pair ordering
# ---------------------------------------------------------------------------

func test_pair_canonical_ordering() -> void:
	# Detection called from EITHER side of a pair should yield exactly one
	# canonical row with settlement_a_id < settlement_b_id.
	_make_hex(800, 0)
	_make_hex(801, 0)
	_add_road(800, 0)
	_add_road(801, 0)
	var s1: String = _make_settlement(800, 0, 3, "CanonA")
	var s2: String = _make_settlement(801, 0, 3, "CanonB")
	TradeRouteDetector.detect_routes_for_settlement(s1)
	TradeRouteDetector.detect_routes_for_settlement(s2)
	# Count active rows for the pair.
	CampaignRepository.db.query_with_bindings("""
		SELECT settlement_a_id, settlement_b_id, COUNT(*) AS n FROM trade_routes
		WHERE invalidated = 0 AND
			((settlement_a_id = ? AND settlement_b_id = ?)
			 OR (settlement_a_id = ? AND settlement_b_id = ?))
		GROUP BY settlement_a_id, settlement_b_id
	""", [s1, s2, s2, s1])
	check(CampaignRepository.db.query_result.size() == 1,
		"detection from both sides should yield exactly one canonical row, got %d" % CampaignRepository.db.query_result.size())
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var a_id: String = str(row.get("settlement_a_id", ""))
	var b_id: String = str(row.get("settlement_b_id", ""))
	check(a_id < b_id, "canonical ordering: settlement_a_id (%s) < settlement_b_id (%s)" % [a_id, b_id])


func test_detection_persists_rows() -> void:
	# Verify detect_routes_for_settlement writes rows with the expected columns.
	_make_hex(900, 0)
	_make_hex(901, 0)
	_add_road(900, 0)
	_add_road(901, 0)
	var s1: String = _make_settlement(900, 0, 4, "PersistA")
	var s2: String = _make_settlement(901, 0, 4, "PersistB")
	var inserted: Array = TradeRouteDetector.detect_routes_for_settlement(s1)
	check(inserted.size() == 1,
		"detection should return 1 row for the single counterpart, got %d" % inserted.size())
	if inserted.size() >= 1:
		var route: Dictionary = inserted[0]
		check(str(route.get("path_kind", "")) == "road", "single-road fixture → path_kind='road'")
		check(int(route.get("distance_hexes", -1)) == 1, "adjacent road hexes → distance 1")
		check(int(route.get("invalidated", 1)) == 0, "new row should have invalidated=0")
	# DB row should match.
	CampaignRepository.db.query_with_bindings(
		"SELECT path_kind, distance_hexes FROM trade_routes WHERE invalidated = 0 AND settlement_a_id = ? AND settlement_b_id = ?",
		[mini_s(s1, s2), maxi_s(s1, s2)]
	)
	check(not CampaignRepository.db.query_result.is_empty(),
		"DB should have the inserted row")


func test_is_within_mutual_range() -> void:
	# Smoke-test the RAW table by spot-checking each market class at its
	# own road range boundary.
	for c in [1, 2, 3, 4, 5, 6]:
		var road: int = int((TradeRouteDetector.RANGE_OF_TRADE[c] as Dictionary).get("road", 0))
		check(TradeRouteDetector.is_within_mutual_range(c, c, road, "road"),
			"class %d at its road range (%d) should be within" % [c, road])
		check(not TradeRouteDetector.is_within_mutual_range(c, c, road + 1, "road"),
			"class %d at road range + 1 should be out of range" % c)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

func mini_s(a: String, b: String) -> String:
	return a if a < b else b


func maxi_s(a: String, b: String) -> String:
	return a if a > b else b
