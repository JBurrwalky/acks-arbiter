class_name HexMapController
extends Node

## Manages hex map game logic: party movement, fog of war, and hex math.
##
## Dependencies:
##   EventBus (autoload): emits hex_entered(hex_id) on party movement
##   GameState (autoload): reads current exploration context
##
## Signals emitted to EventBus:
##   EventBus.hex_entered — fires when party enters a new hex
##
## Signals emitted locally (connect renderer to these):
##   map_loaded(map_id)           — a map was loaded and ready to render
##   hex_first_revealed(coord)    — a HIDDEN hex became VISIBLE for the first time
##   visibility_updated()         — fog state changed; renderer should refresh fog layer
##   party_moved(from, to)        — party changed hex position


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal map_loaded(map_id: String)
signal hex_first_revealed(coord: Vector2i)
signal visibility_updated()
signal party_moved(from_hex: Vector2i, to_hex: Vector2i)
signal hex_terrain_updated(coord: Vector2i)
signal hex_overlay_updated(coord: Vector2i)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _map_data: HexMapData

## Number of EXTRA hex rings (beyond the default 1) revealed around the
## party each time visibility is updated. Default 0 → base radius 1 (center
## + immediate neighbors). Set via `set_party_visibility_bonus_hexes` by
## the party-equipment refresher; consumers don't read this field directly.
##
## Wired 2026-06-03 for Eyes of the Eagle V2 (Jedidiah ruling): the item's
## flag carries `metadata.extra_hex_visibility: 1`, and the static helper
## `compute_party_visibility_bonus(party_characters)` maxes across all party
## members (multi-wearer doesn't stack — RAW semantics: people don't see
## further if other people are also looking). The session-side refresh
## trigger (subscribe to inventory_updated + active_party_changed) is a
## documented V1 follow-up; this controller-side mechanic is live so the
## bonus takes effect on map load / movement once a caller sets it.
var _party_visibility_bonus_hexes: int = 0


# ---------------------------------------------------------------------------
# Static hex math
# ---------------------------------------------------------------------------

# Axial coordinate system for flat-top hexes.
# Neighbors of (q, r): (q+1,r), (q-1,r), (q+1,r-1), (q-1,r+1), (q,r-1), (q,r+1)
# Distance: (abs(dq) + abs(dq+dr) + abs(dr)) / 2
#
# Axial → Godot TileMapLayer map coords for TILE_LAYOUT_FLAT (flat-top, even-q offset):
#   col = q
#   row = r + (q - (q & 1)) / 2
# Odd-q alternative if even-q doesn't match Godot's behavior:
#   row = r + (q + (q & 1)) / 2

## Returns the 6 axial neighbors of a flat-top hex at (q, r).
static func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var q := coord.x
	var r := coord.y
	return [
		Vector2i(q + 1, r),
		Vector2i(q - 1, r),
		Vector2i(q + 1, r - 1),
		Vector2i(q - 1, r + 1),
		Vector2i(q, r - 1),
		Vector2i(q, r + 1),
	]


## Returns the axial grid distance between two hexes.
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (abs(dq) + abs(dq + dr) + abs(dr)) / 2


static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return hex_distance(a, b) == 1


## Returns all hexes exactly [param radius] steps from [param center].
## Radius 0 returns only the center hex.
static func get_hex_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]

	var results: Array[Vector2i] = []

	# 6 directions for flat-top hex ring walk:
	# Going around: SW, S, SE, NE, N, NW (standard traversal)
	# Direction vectors for ring traversal:
	#   (0,1), (-1,1), (-1,0), (0,-1), (1,-1), (1,0)
	# Start at center + (radius, -radius), then walk directions × radius steps each
	var directions: Array[Vector2i] = [
		Vector2i(0, 1),
		Vector2i(-1, 1),
		Vector2i(-1, 0),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(1, 0),
	]

	var current := center + Vector2i(radius, -radius)
	for i in range(6):
		for _step in range(radius):
			results.append(current)
			current += directions[i]

	return results


## Converts axial (q, r) to Godot TileMapLayer map coords.
## Uses even-q offset for TILE_LAYOUT_FLAT (flat-top hexes).
static func axial_to_godot_map(axial: Vector2i) -> Vector2i:
	# Even-q offset conversion for flat-top hex (TILE_LAYOUT_FLAT)
	var q := axial.x
	var r := axial.y
	return Vector2i(q, r + (q - (q & 1)) / 2)


## Inverse of axial_to_godot_map — converts Godot map coords back to axial.
static func godot_map_to_axial(map: Vector2i) -> Vector2i:
	var col := map.x
	var row := map.y
	return Vector2i(col, row - (col - (col & 1)) / 2)


# ---------------------------------------------------------------------------
# Game logic methods
# ---------------------------------------------------------------------------

## Loads a map, initialises all fog to HIDDEN, then reveals the starting position.
func load_map(map_data: HexMapData) -> void:
	_map_data = map_data
	# Start with every hex hidden before applying line-of-sight from spawn.
	for coord in map_data.hexes.keys():
		map_data.fog[coord] = HexMapData.FogState.HIDDEN
	_update_visibility(map_data.party_hex)
	map_loaded.emit(map_data.id)


func get_map() -> HexMapData:
	return _map_data


## Updates a single terrain field on a hex in-memory and emits hex_terrain_updated.
## Called by OverrideManager after writing the change to the DB.
func update_hex_terrain(coord: Vector2i, field: String, new_value) -> void:
	if _map_data == null:
		return
	var terrain: HexTerrainData = _map_data.get_hex(coord)
	if terrain == null:
		return
	match field:
		"elevation":      terrain.elevation = new_value
		"biome":          terrain.biome = new_value
		"water":          terrain.water = new_value
		"civilization":   terrain.civilization = new_value
		"has_city":       terrain.has_city = str(new_value) in ["1", "true", "True"]
		"original_biome": terrain.original_biome = new_value
		"overlay":
			if new_value is HexOverlayData:
				terrain.overlay = new_value
			hex_overlay_updated.emit(coord)
			return
	hex_terrain_updated.emit(coord)


## Returns true if the party can legally move to [param target] this turn.
##
## Note: this checks only single-step adjacency. For multi-hex right-click
## travel, use [method find_path] instead — the wilderness context menu does
## not gate Move Here on adjacency.
func can_move_to(target: Vector2i) -> bool:
	return (
		_map_data != null
		and _map_data.is_valid_coord(target)
		and is_adjacent(_map_data.party_hex, target)
		and can_cross_river_edge(_map_data.party_hex, target)
	)


## Returns true if the party may cross the edge between two adjacent hexes.
##
## A river edge whose `crossing` is "none" blocks land movement — until the boat
## system exists, rivers may only be crossed where a bridge, ford, or ferry is
## declared on the edge, OR where a road bridges the river ("roads imply
## crossings" — Jedidiah ruling 2026-06-08; GDD §3.6.5). Returns true when the
## two hexes are not adjacent, when no river runs along their shared edge, or
## when no map is loaded. River edges are stored canonically (lex-lower hex owns
## the entry), so this checks the edge in both orientations.
func can_cross_river_edge(from_hex: Vector2i, to_hex: Vector2i) -> bool:
	if _map_data == null:
		return true
	for edge_data in _map_data.river_edges:
		var owner := Vector2i(edge_data.hex_q, edge_data.hex_r)
		var neighbor: Vector2i = owner + HexRiverEdgeData.neighbor_offset(edge_data.edge)
		if (owner == from_hex and neighbor == to_hex) \
				or (owner == to_hex and neighbor == from_hex):
			if edge_data.crossing != HexRiverEdgeData.CROSSING_NONE:
				return true
			# Roads imply a crossing: a road that bridges this edge makes it
			# passable even without an authored crossing.
			return _edge_has_road(owner, edge_data.edge)
	return true


## Returns true if a road runs across the edge `edge` of `owner_coord` — i.e.
## the owning hex has that edge in its road overlay, or the neighbour across it
## has the opposite edge. A road touching a river edge from either side is taken
## to bridge it ("roads imply crossings").
func _edge_has_road(owner_coord: Vector2i, edge: int) -> bool:
	if _map_data == null:
		return false
	var owner_terrain: HexTerrainData = _map_data.get_hex(owner_coord)
	if owner_terrain != null and owner_terrain.overlay != null \
			and edge in owner_terrain.overlay.road_edges:
		return true
	var neighbor_coord: Vector2i = owner_coord + HexRiverEdgeData.neighbor_offset(edge)
	var neighbor_terrain: HexTerrainData = _map_data.get_hex(neighbor_coord)
	var opp: int = HexOverlayData.opposite_edge(edge)
	if neighbor_terrain != null and neighbor_terrain.overlay != null \
			and opp in neighbor_terrain.overlay.road_edges:
		return true
	return false


## Returns true if [param coord] is a hex the party may traverse.
## v1 rule: hex must exist in the map and not be a deep-water (ocean/lake)
## hex. Terrain-based cost multipliers are a future concern.
func is_hex_passable(coord: Vector2i) -> bool:
	if _map_data == null or not _map_data.is_valid_coord(coord):
		return false
	var terrain: HexTerrainData = _map_data.get_hex(coord)
	if terrain == null:
		return true
	# Deep water blocks land travel until boats exist.
	return terrain.water != HexTerrainData.WATER_OCEAN \
		and terrain.water != HexTerrainData.WATER_LAKE


## A* pathfinding from [param from_hex] to [param to_hex] over passable hexes.
## Returns the full path including the start and end hexes, or an empty array
## when no path exists. When [param from_hex] equals [param to_hex] the result
## is a single-element array `[from_hex]`.
##
## Uses hex-distance as the admissible heuristic. Uniform unit cost per step
## (terrain-based cost multipliers are a future concern). Fog state does not
## restrict pathfinding — intermediate hexes may be HIDDEN, since the journey
## will reveal them as it progresses. The start and goal must each pass
## [method is_hex_passable]; an unreachable goal returns [].
func find_path(from_hex: Vector2i, to_hex: Vector2i) -> Array[Vector2i]:
	if _map_data == null:
		return []
	if from_hex == to_hex:
		var single: Array[Vector2i] = [from_hex]
		return single
	if not is_hex_passable(from_hex) or not is_hex_passable(to_hex):
		return []

	# Open set keyed by coord → f-score (heuristic + g). We pop the lowest-f
	# entry each iteration. Map sizes are small enough that a linear scan is
	# acceptable; replace with a priority queue if profiling demands.
	var open_set: Dictionary = {from_hex: hex_distance(from_hex, to_hex)}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from_hex: 0}

	while not open_set.is_empty():
		var current: Vector2i = _pop_lowest_f(open_set)
		if current == to_hex:
			return _reconstruct_path(came_from, current)
		var current_g: int = g_score[current]
		for n in get_neighbors(current):
			# Allow the goal to be the only "blocked" cell we'd ever want to
			# walk into — but is_hex_passable already approved the goal above.
			if not is_hex_passable(n):
				continue
			# Rivers without a bridge/ford/ferry block the step between two
			# adjacent hexes (no boats yet — GDD §3.6.5). Pathfinding routes
			# around them, threading through declared crossings.
			if not can_cross_river_edge(current, n):
				continue
			var tentative: int = current_g + 1
			if not g_score.has(n) or tentative < int(g_score[n]):
				came_from[n] = current
				g_score[n] = tentative
				open_set[n] = tentative + hex_distance(n, to_hex)

	return []


## Removes and returns the coord with the lowest f-score from [param open_set].
static func _pop_lowest_f(open_set: Dictionary) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_f: int = 0x7fffffff
	var first := true
	for k in open_set.keys():
		var f: int = int(open_set[k])
		if first or f < best_f:
			best = k
			best_f = f
			first = false
	open_set.erase(best)
	return best


## Walks [param came_from] backwards from [param goal] to assemble the path.
static func _reconstruct_path(came_from: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var current: Vector2i = goal
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path


## Attempts to move the party to [param target]. Returns false on failure.
func move_party(target: Vector2i) -> bool:
	if not can_move_to(target):
		push_error("HexMapController.move_party: cannot move to %s from %s" % [str(target), str(_map_data.party_hex if _map_data else "null")])
		return false

	var from := _map_data.party_hex
	_map_data.party_hex = target
	_update_visibility(target)
	party_moved.emit(from, target)
	EventBus.hex_entered.emit("%d,%d" % [target.x, target.y])
	return true


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Reveals [param center] and its adjacent in-bounds hexes as VISIBLE WITHOUT
## demoting other currently-VISIBLE hexes. Use this when a non-active party
## moves so the active party's vicinity stays visible. Fog accumulates across
## parties (a slight inaccuracy compared to "only currently-visible-from-some-
## party is VISIBLE", but acceptable in v1).
func reveal_around(center: Vector2i) -> void:
	if _map_data == null:
		return
	var visible_set: Array[Vector2i] = [center]
	visible_set.append_array(get_neighbors(center))
	for coord in visible_set:
		if _map_data.is_valid_coord(coord):
			var was_hidden := _map_data.get_fog_state(coord) == HexMapData.FogState.HIDDEN
			_map_data.set_fog_state(coord, HexMapData.FogState.VISIBLE)
			if was_hidden:
				hex_first_revealed.emit(coord)
	visibility_updated.emit()


## Demotes previously VISIBLE hexes to EXPLORED, then marks the center and
## all hexes within `1 + _party_visibility_bonus_hexes` rings as VISIBLE.
## Emits hex_first_revealed for any hex transitioning out of HIDDEN for the
## first time. Default sight radius is 1 (center + immediate neighbors).
## Each party visibility bonus point adds one more ring (e.g. Eyes of the
## Eagle V2 = +1 → radius 2 = center + 6 neighbors + 12 next-ring hexes).
func _update_visibility(new_center: Vector2i) -> void:
	# Step 1: demote all currently visible hexes — they are no longer in sight range.
	for coord in _map_data.fog.keys():
		if _map_data.fog[coord] == HexMapData.FogState.VISIBLE:
			_map_data.fog[coord] = HexMapData.FogState.EXPLORED

	# Step 2: reveal center + rings 1..(1 + bonus).
	# Base radius is 1 (immediate neighbors). Each bonus hex extends one more ring.
	var visible_set: Array[Vector2i] = [new_center]
	var max_ring: int = 1 + max(0, _party_visibility_bonus_hexes)
	for ring_radius in range(1, max_ring + 1):
		visible_set.append_array(get_hex_ring(new_center, ring_radius))

	for coord in visible_set:
		if _map_data.is_valid_coord(coord):
			var was_hidden := _map_data.get_fog_state(coord) == HexMapData.FogState.HIDDEN
			_map_data.set_fog_state(coord, HexMapData.FogState.VISIBLE)
			if was_hidden:
				hex_first_revealed.emit(coord)

	visibility_updated.emit()


# ---------------------------------------------------------------------------
# Party visibility bonus (Eyes of the Eagle V2 + future visibility items)
# ---------------------------------------------------------------------------

## Sets the party's visibility bonus (extra hex rings beyond the default 1)
## and, if a map is loaded, immediately re-runs `_update_visibility` from the
## current party hex so the renderer picks up the new sight radius.
##
## Called by the party-equipment refresher (session-side wire-up) whenever
## a party member equips/unequips an item that affects visibility, or when
## party membership changes. Multiple call sites are valid — the setter is
## idempotent for equal values.
##
## V1 wire-up callers: none yet (controller-side mechanic is live + tested;
## session-side trigger is a documented follow-up).
func set_party_visibility_bonus_hexes(n: int) -> void:
	var clamped: int = max(0, n)
	if clamped == _party_visibility_bonus_hexes:
		return
	_party_visibility_bonus_hexes = clamped
	if _map_data != null:
		_update_visibility(_map_data.party_hex)


## Returns the currently-set party visibility bonus. Primarily used by
## tests; runtime consumers go through `_update_visibility` indirectly.
func get_party_visibility_bonus_hexes() -> int:
	return _party_visibility_bonus_hexes


## Sums (actually maxes — see below) the visibility bonus contributed by
## each character in [param party_characters]. Multi-source semantics:
## the bonus DOES NOT STACK across multiple wearers — RAW intent is that
## people don't see further just because their companions are also looking.
## Two party members each wearing Eyes of the Eagle yield bonus 1, not 2.
## Future items that DO stack can land via a per-item is_stacking flag on
## the metadata; V1 takes the max for simplicity.
##
## Reads `metadata.extra_hex_visibility` from any `has_eyes_of_the_eagle`
## flag entry on each character. Forward-looking: other future visibility
## flags (e.g. has_telescope, has_crystal_ball_with_clairvoyance) can be
## added to the same scan loop as they land.
##
## [param party_characters] Array of CharacterData (or duck-typed objects
## exposing `.flags`). Null members are skipped.
static func compute_party_visibility_bonus(party_characters: Array) -> int:
	var bonus: int = 0
	for member in party_characters:
		if member == null:
			continue
		var member_flags = null
		if member is CharacterData:
			member_flags = member.flags
		elif "flags" in member:
			member_flags = member.flags
		if member_flags == null:
			continue
		# Eyes of the Eagle V2 — read max extra_hex_visibility across all
		# source entries of this flag (a single character could in principle
		# wear two paired items; max keeps the bonus stable at 1).
		if member_flags.has_flag("has_eyes_of_the_eagle"):
			for entry in member_flags.get_flag_source_entries("has_eyes_of_the_eagle"):
				var meta: Dictionary = entry.get("metadata", {})
				var member_bonus: int = int(meta.get("extra_hex_visibility", 0))
				if member_bonus > bonus:
					bonus = member_bonus
	return bonus
