class_name TradeRouteDetector
extends RefCounted

## Trade-route detector — finds road and water paths between pairs of settlements
## and persists valid routes to the `trade_routes` cache table.
##
## Per generation/gdd-settlement-economy.md §5.1 + §5.5. RAW criteria
## (acore-setting-construction-rules.xml:358-365): a connecting road/trail or
## navigable waterway AND both markets must lie within each other's
## range_of_trade.
##
## Pathfinding is BFS over (map_id, q, r) keyed graphs:
##   * Road graph — hexes with hex_overlays.overlay_type='road'.
##   * Water graph — hexes where water in {'ocean','lake'} OR any
##     hex_river_edges row touches the hex (migration 130 / GDD §3.6).
##     Settlements enter via §3.3 water-source adjacency.
##
## All static; no instance state. No EventBus listener wiring in this
## library — the detector is invoked by the region resolver / campaign-load
## path; topology-trigger wiring lands when the relevant events ship.


# ---------------------------------------------------------------------------
# §5.1.1 range_of_trade table (RAW acore-setting-construction-rules.xml:264-278)
# ---------------------------------------------------------------------------

const RANGE_OF_TRADE := {
	1: {"road": 28, "water": 80},
	2: {"road": 24, "water": 60},
	3: {"road": 18, "water": 40},
	4: {"road": 12, "water": 20},
	5: {"road": 8,  "water": 16},
	6: {"road": 4,  "water": 8},
}

const _MAX_ROAD_RANGE := 28
const _MAX_WATER_RANGE := 80

const _NO_PATH := -1


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Detects all valid trade routes between [param settlement_id] and every
## other settlement in the same campaign. Invalidates any existing routes
## for this settlement (sets invalidated=1) before writing the new set.
## Returns the array of newly-inserted trade_routes rows.
static func detect_routes_for_settlement(settlement_id: String) -> Array:
	if settlement_id.is_empty():
		return []
	var s_row: Dictionary = _read_settlement(settlement_id)
	if s_row.is_empty():
		return []
	var campaign_id: String = str(s_row.get("campaign_id", ""))
	if campaign_id.is_empty():
		return []
	# Invalidate existing routes for this settlement.
	CampaignRepository.db.query_with_bindings("""
		UPDATE trade_routes SET invalidated = 1
		WHERE settlement_a_id = ? OR settlement_b_id = ?
	""", [settlement_id, settlement_id])

	# Gather candidate counterparts (every other settlement in the campaign).
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id FROM settlement_entrances WHERE campaign_id = ? AND id != ?",
			[campaign_id, settlement_id]):
		return []
	var counterparts: Array = CampaignRepository.db.query_result.duplicate()

	var inserted: Array = []
	for cp in counterparts:
		var counterpart_id: String = str((cp as Dictionary).get("id", ""))
		if counterpart_id.is_empty():
			continue
		var route: Dictionary = _detect_route_between(settlement_id, counterpart_id)
		if route.is_empty():
			continue
		inserted.append(route)
	return inserted


## Detects all trade routes in the campaign via an O(N²) sweep. Used at
## campaign-load when the trade_routes cache is empty. Returns count of
## routes inserted.
static func detect_routes_for_campaign(campaign_id: String) -> int:
	if campaign_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id FROM settlement_entrances WHERE campaign_id = ? ORDER BY id ASC",
			[campaign_id]):
		return 0
	var settlement_ids: Array = []
	for row in CampaignRepository.db.query_result:
		settlement_ids.append(str((row as Dictionary).get("id", "")))
	# Wipe the existing cache for this campaign so we start fresh.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM trade_routes WHERE campaign_id = ?", [campaign_id])
	var count: int = 0
	for i in range(settlement_ids.size()):
		for j in range(i + 1, settlement_ids.size()):
			var a_id: String = settlement_ids[i]
			var b_id: String = settlement_ids[j]
			var route: Dictionary = _detect_route_between(a_id, b_id)
			if not route.is_empty():
				count += 1
	return count


## Returns shortest road-graph distance in hexes between the two settlements,
## or -1 if no path exists. Both settlements must be ON road-overlay hexes
## (§5.1.1 — settlements participate in the road graph by membership, not
## adjacency).
static func compute_road_distance(settlement_a_id: String, settlement_b_id: String) -> int:
	var a: Dictionary = _read_settlement(settlement_a_id)
	var b: Dictionary = _read_settlement(settlement_b_id)
	if a.is_empty() or b.is_empty():
		return _NO_PATH
	if str(a.get("map_id", "")) != str(b.get("map_id", "")):
		return _NO_PATH
	var map_id: String = str(a.get("map_id", ""))
	var a_coord := Vector2i(int(a.get("hex_q", 0)), int(a.get("hex_r", 0)))
	var b_coord := Vector2i(int(b.get("hex_q", 0)), int(b.get("hex_r", 0)))
	# Both endpoints must be on road overlays.
	if not _is_road_hex(map_id, a_coord.x, a_coord.y):
		return _NO_PATH
	if not _is_road_hex(map_id, b_coord.x, b_coord.y):
		return _NO_PATH
	return _bfs_distance(map_id, [a_coord], [b_coord], "road", _MAX_ROAD_RANGE)


## Returns shortest water-graph distance in hexes between the two settlements,
## or -1 if no path exists. Settlements enter via §3.3 water-source adjacency.
static func compute_water_distance(settlement_a_id: String, settlement_b_id: String) -> int:
	var a: Dictionary = _read_settlement(settlement_a_id)
	var b: Dictionary = _read_settlement(settlement_b_id)
	if a.is_empty() or b.is_empty():
		return _NO_PATH
	if str(a.get("map_id", "")) != str(b.get("map_id", "")):
		return _NO_PATH
	var map_id: String = str(a.get("map_id", ""))
	var a_entries: Array = _water_entry_nodes(map_id, a)
	var b_entries: Array = _water_entry_nodes(map_id, b)
	if a_entries.is_empty() or b_entries.is_empty():
		return _NO_PATH
	return _bfs_distance(map_id, a_entries, b_entries, "water", _MAX_WATER_RANGE)


## Returns true if `distance` is within the smaller of the two markets'
## ranges for [param kind] ('road' or 'water'). Per §5.1.1, both markets
## must lie within each other's range, so the binding constraint is
## min(a_range, b_range).
static func is_within_mutual_range(a_market_class: int, b_market_class: int, distance: int, kind: String) -> bool:
	if distance < 0:
		return false
	var a_range: int = _range_for(a_market_class, kind)
	var b_range: int = _range_for(b_market_class, kind)
	return distance <= mini(a_range, b_range)


# ---------------------------------------------------------------------------
# Internals — detection
# ---------------------------------------------------------------------------

## Detects whether a single (a, b) pair forms a valid trade route. If yes,
## inserts a canonical-ordered row into `trade_routes` and returns the row
## dict; if no, returns {}.
static func _detect_route_between(a_id: String, b_id: String) -> Dictionary:
	# Canonicalize: a_id < b_id for the row's (a, b) ordering.
	var pair_a: String = a_id
	var pair_b: String = b_id
	if pair_a > pair_b:
		var tmp: String = pair_a
		pair_a = pair_b
		pair_b = tmp

	var a_row: Dictionary = _read_settlement(pair_a)
	var b_row: Dictionary = _read_settlement(pair_b)
	if a_row.is_empty() or b_row.is_empty():
		return {}
	var a_class: int = int(a_row.get("market_class", 6))
	var b_class: int = int(b_row.get("market_class", 6))

	var road_distance: int = compute_road_distance(pair_a, pair_b)
	var water_distance: int = compute_water_distance(pair_a, pair_b)

	var road_valid: bool = road_distance >= 0 and is_within_mutual_range(a_class, b_class, road_distance, "road")
	var water_valid: bool = water_distance >= 0 and is_within_mutual_range(a_class, b_class, water_distance, "water")

	if not road_valid and not water_valid:
		return {}

	# Determine canonical path_kind + distance.
	var path_kind: String = ""
	var distance: int = -1
	if road_valid and water_valid:
		path_kind = "mixed"
		distance = mini(road_distance, water_distance)
	elif road_valid:
		path_kind = "road"
		distance = road_distance
	else:
		path_kind = "water"
		distance = water_distance

	# Upsert row. If an invalidated row exists for the pair, reset it; else insert.
	var calendar_day: int = _current_calendar_day()
	var route_id: String = _route_id_for(pair_a, pair_b)
	if route_id.is_empty():
		route_id = CampaignRepository.generate_id()
		if not CampaignRepository.db.query_with_bindings("""
			INSERT INTO trade_routes
				(id, campaign_id, settlement_a_id, settlement_b_id,
				 path_kind, distance_hexes, discovered_at_calendar_day, invalidated)
			VALUES (?, ?, ?, ?, ?, ?, ?, 0)
		""", [route_id, str(a_row.get("campaign_id", "")), pair_a, pair_b,
			  path_kind, distance, calendar_day]):
			push_error("TradeRouteDetector: INSERT failed for pair (%s, %s)" % [pair_a, pair_b])
			return {}
	else:
		CampaignRepository.db.query_with_bindings("""
			UPDATE trade_routes SET
				path_kind = ?, distance_hexes = ?,
				discovered_at_calendar_day = ?, invalidated = 0
			WHERE id = ?
		""", [path_kind, distance, calendar_day, route_id])

	return {
		"id": route_id,
		"campaign_id": str(a_row.get("campaign_id", "")),
		"settlement_a_id": pair_a,
		"settlement_b_id": pair_b,
		"path_kind": path_kind,
		"distance_hexes": distance,
		"discovered_at_calendar_day": calendar_day,
		"invalidated": 0,
	}


static func _route_id_for(pair_a: String, pair_b: String) -> String:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id FROM trade_routes WHERE settlement_a_id = ? AND settlement_b_id = ?",
			[pair_a, pair_b]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return str(CampaignRepository.db.query_result[0].get("id", ""))


# ---------------------------------------------------------------------------
# Internals — pathfinding
# ---------------------------------------------------------------------------

## BFS from any of `sources` to any of `targets` over the graph identified
## by [param graph_kind] ('road' or 'water'). Returns the shortest distance
## in hexes, or _NO_PATH if no path exists within `max_distance` steps.
##
## Sources and targets are arrays of Vector2i hex coords. The BFS frontier
## starts at distance 0 with all source coords; the first time we pop a
## frontier coord that matches a target, we return that distance.
static func _bfs_distance(
		map_id: String,
		sources: Array,
		targets: Array,
		graph_kind: String,
		max_distance: int,
) -> int:
	if sources.is_empty() or targets.is_empty():
		return _NO_PATH
	var target_set: Dictionary = {}
	for t in targets:
		target_set[_coord_key(t as Vector2i)] = true
	# Early termination: source already at target.
	for s in sources:
		if target_set.has(_coord_key(s as Vector2i)):
			return 0
	# Standard BFS with visited set.
	var queue: Array = []
	var visited: Dictionary = {}
	for s in sources:
		queue.append({"coord": s, "dist": 0})
		visited[_coord_key(s as Vector2i)] = true
	while not queue.is_empty():
		var entry: Dictionary = queue.pop_front()
		var coord: Vector2i = entry["coord"]
		var dist: int = int(entry["dist"])
		if dist >= max_distance:
			continue
		for n in HexMapController.get_neighbors(coord):
			var neighbor: Vector2i = n
			var nkey: String = _coord_key(neighbor)
			if visited.has(nkey):
				continue
			if not _hex_in_graph(map_id, neighbor.x, neighbor.y, graph_kind):
				continue
			var new_dist: int = dist + 1
			if target_set.has(nkey):
				return new_dist
			visited[nkey] = true
			queue.append({"coord": neighbor, "dist": new_dist})
	return _NO_PATH


static func _hex_in_graph(map_id: String, q: int, r: int, kind: String) -> bool:
	if kind == "road":
		return _is_road_hex(map_id, q, r)
	if kind == "water":
		return _is_water_hex(map_id, q, r)
	return false


static func _is_road_hex(map_id: String, q: int, r: int) -> bool:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM hex_overlays
		WHERE map_id = ? AND q = ? AND r = ? AND overlay_type = 'road'
		LIMIT 1
	""", [map_id, q, r]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


static func _is_water_hex(map_id: String, q: int, r: int) -> bool:
	# Ocean or lake on the hex itself?
	if CampaignRepository.db.query_with_bindings("""
		SELECT water FROM hex_cells WHERE map_id = ? AND q = ? AND r = ?
	""", [map_id, q, r]):
		if not CampaignRepository.db.query_result.is_empty():
			var water: String = str(CampaignRepository.db.query_result[0].get("water", ""))
			if water == "ocean" or water == "lake":
				return true
	# River edge touching the hex (migration 130)?
	return CampaignRepository.hex_has_river(map_id, q, r)


## Resolves the water-graph entry nodes for a settlement per §5.1.2:
##   * If the settlement's own hex is a water hex, return [that hex].
##   * Else, return every adjacent hex that is a water hex.
## Returns [] if the settlement has no water entry.
static func _water_entry_nodes(map_id: String, settlement_row: Dictionary) -> Array:
	var hex_q: int = int(settlement_row.get("hex_q", 0))
	var hex_r: int = int(settlement_row.get("hex_r", 0))
	var entries: Array = []
	# Settlement's own hex first.
	if _is_water_hex(map_id, hex_q, hex_r):
		entries.append(Vector2i(hex_q, hex_r))
		return entries
	# Adjacent hexes.
	for n in HexMapController.get_neighbors(Vector2i(hex_q, hex_r)):
		var coord: Vector2i = n
		if _is_water_hex(map_id, coord.x, coord.y):
			entries.append(coord)
	return entries


# ---------------------------------------------------------------------------
# Internals — small helpers
# ---------------------------------------------------------------------------

static func _coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


static func _range_for(market_class: int, kind: String) -> int:
	var row: Dictionary = RANGE_OF_TRADE.get(market_class, {})
	if row.is_empty():
		return 0
	return int(row.get(kind, 0))


static func _read_settlement(settlement_id: String) -> Dictionary:
	if settlement_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, campaign_id, map_id, hex_q, hex_r, market_class
		FROM settlement_entrances WHERE id = ?
	""", [settlement_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


static func _current_calendar_day() -> int:
	if not CampaignRepository.db.query("SELECT calendar_day FROM campaigns WHERE is_active = 1 LIMIT 1"):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("calendar_day", 0))
