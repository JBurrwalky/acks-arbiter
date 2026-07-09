class_name DungeonFactionInput
extends RefCounted

## The complete input to DungeonFactionGenerator.generate()
## (`gdd-dungeon-factions.md` §3–§4). A room graph (nodes = rooms, edges =
## passages) annotated with stocked monster placements. Deterministic: iteration
## order over `rooms` and each room's neighbor/placement lists is preserved
## insertion order, so a given input + seed replays byte-identically.
##
## Build it with the fluent helpers (add_room / connect / place) — they keep the
## adjacency symmetric and the lookup index in sync — or via
## DungeonFactionInputBuilder.from_layout() for real DG-V1 output.


var dungeon_id: String = ""
var default_level: int = 1                          ## level assigned to add_room() calls without one

var rooms: Array[DungeonFactionRoomInput] = []
var _room_index: Dictionary = {}                    ## { room_id: int -> DungeonFactionRoomInput }


# ---------------------------------------------------------------------------
# Construction helpers
# ---------------------------------------------------------------------------

## Add (or fetch) a room node. Returns the room so callers can chain placements.
func add_room(room_id: int, level: int = -1) -> DungeonFactionRoomInput:
	if _room_index.has(room_id):
		return _room_index[room_id]
	var r := DungeonFactionRoomInput.new()
	r.id = room_id
	r.level = level if level >= 0 else default_level
	rooms.append(r)
	_room_index[room_id] = r
	return r


func get_room(room_id: int) -> DungeonFactionRoomInput:
	return _room_index.get(room_id, null)


func has_room(room_id: int) -> bool:
	return _room_index.has(room_id)


## Add a symmetric edge between two rooms (both must already exist). Adds one
## DungeonFactionEdge to each endpoint's neighbor list. Idempotent per direction
## (a repeated connect() with the same neighbor overwrites the edge kind/width).
func connect_rooms(a: int, b: int, kind: String = DungeonFactionEdge.KIND_OPEN, width_ft: int = 10) -> void:
	_add_directed_edge(a, b, kind, width_ft)
	_add_directed_edge(b, a, kind, width_ft)


func _add_directed_edge(from_id: int, to_id: int, kind: String, width_ft: int) -> void:
	var r: DungeonFactionRoomInput = _room_index.get(from_id, null)
	if r == null:
		return
	for e in r.neighbors:
		if e.to_room_id == to_id:
			e.kind = kind
			e.width_ft = width_ft
			return
	var edge := DungeonFactionEdge.new()
	edge.to_room_id = to_id
	edge.kind = kind
	edge.width_ft = width_ft
	r.neighbors.append(edge)


## Append a monster placement to a room. Returns the placement so the caller can
## set extra fields (intelligence, leader, controller). The room must exist.
func place(room_id: int, species: String, number: int, opts: Dictionary = {}) -> DungeonFactionMonsterPlacement:
	var r: DungeonFactionRoomInput = _room_index.get(room_id, null)
	if r == null:
		return null
	var p := DungeonFactionMonsterPlacement.new()
	p.room_id = room_id
	p.species = species
	p.number = number
	# Coerce monster_types into a typed Array[String] regardless of how the
	# caller supplied it (an untyped literal cannot be assigned to Array[String]).
	var mt: Array[String] = []
	var mt_raw: Variant = opts.get("monster_types", [])
	if mt_raw is Array:
		for x in mt_raw:
			mt.append(String(x))
	p.monster_types = mt
	p.is_lair = bool(opts.get("is_lair", false))
	p.intelligence = String(opts.get("intelligence", DungeonFactionMonsterPlacement.INT_LOW))
	p.alignment = String(opts.get("alignment", "neutral"))
	p.hd = float(opts.get("hd", 1.0))
	p.morale = int(opts.get("morale", 0))
	p.has_special_abilities = bool(opts.get("has_special_abilities", false))
	p.is_leader = bool(opts.get("is_leader", false))
	p.leader_title = String(opts.get("leader_title", ""))
	p.leader_hd = float(opts.get("leader_hd", 0.0))
	p.controlled_by_species = String(opts.get("controlled_by_species", ""))
	p.patrol_dice = String(opts.get("patrol_dice", ""))
	r.placements.append(p)
	return p


# ---------------------------------------------------------------------------
# Queries used by the generator
# ---------------------------------------------------------------------------

## All placements across all rooms, in room-insertion then placement order.
func all_placements() -> Array[DungeonFactionMonsterPlacement]:
	var out: Array[DungeonFactionMonsterPlacement] = []
	for r in rooms:
		for p in r.placements:
			out.append(p)
	return out


## Distinct dungeon levels present, ascending.
func levels() -> Array[int]:
	var seen: Array[int] = []
	for r in rooms:
		if not seen.has(r.level):
			seen.append(r.level)
	seen.sort()
	return seen


## Sorted list of room ids (deterministic traversal seed order).
func sorted_room_ids() -> Array[int]:
	var ids: Array[int] = []
	for r in rooms:
		ids.append(r.id)
	ids.sort()
	return ids
