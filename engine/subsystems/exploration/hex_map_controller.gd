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


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _map_data: HexMapData


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
	hex_terrain_updated.emit(coord)


## Returns true if the party can legally move to [param target] this turn.
func can_move_to(target: Vector2i) -> bool:
	return (
		_map_data != null
		and _map_data.is_valid_coord(target)
		and is_adjacent(_map_data.party_hex, target)
	)


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

## Demotes previously VISIBLE hexes to EXPLORED, then marks the center and
## all adjacent in-bounds hexes as VISIBLE. Emits hex_first_revealed for
## any hex transitioning out of HIDDEN for the first time.
func _update_visibility(new_center: Vector2i) -> void:
	# Step 1: demote all currently visible hexes — they are no longer in sight range.
	for coord in _map_data.fog.keys():
		if _map_data.fog[coord] == HexMapData.FogState.VISIBLE:
			_map_data.fog[coord] = HexMapData.FogState.EXPLORED

	# Step 2: reveal center + immediate neighbors (1-hex sight radius).
	var visible_set: Array[Vector2i] = [new_center]
	visible_set.append_array(get_neighbors(new_center))

	for coord in visible_set:
		if _map_data.is_valid_coord(coord):
			var was_hidden := _map_data.get_fog_state(coord) == HexMapData.FogState.HIDDEN
			_map_data.set_fog_state(coord, HexMapData.FogState.VISIBLE)
			if was_hidden:
				hex_first_revealed.emit(coord)

	visibility_updated.emit()
