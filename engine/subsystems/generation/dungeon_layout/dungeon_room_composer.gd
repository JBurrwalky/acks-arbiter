class_name DungeonRoomComposer
extends RefCounted

## Plans a dungeon layout as geometric primitives — rooms, corridor centerlines,
## doors, stairs — per `generation/gdd-dungeon-layout.md` §4-§9 (rev 2026-05-27).
##
## The composer is the planning layer. It mutates no cells — the actual cell
## grid is built later by DungeonLayoutRasterizer (§10.1). This separation
## keeps the algorithm easy to reason about: each phase manipulates typed
## geometric primitives (Rect2i, Vector2i, ordered arrays) rather than
## bitmask cells, and the output is small and inspectable.
##
## Pipeline (matching layout GDD §4.1 steps 2-7):
##   1. Scatter rooms (§6.1) — collision-checked, allows wall-sharing
##   2. Build connection graph (§7.2) — MST + loop-frequency loops
##   3. Route corridors (§7.3) — L-shape and S-shape axis-aligned routes
##   4. Plan doors (§8.1) — at corridor-to-room transitions + adjacent-room
##                          wall cells
##   5. Plan stairs (§9.1) — preferred in rooms; avoid the entrance room
##   6. Assign room purposes (§6.3) — weighted pick from theme.purpose_weights
##
## All randomness flows through a single RandomNumberGenerator parameter so
## generation is reproducible per seed.


# ---------------------------------------------------------------------------
# Inner data types
# ---------------------------------------------------------------------------

## A planned room. Rect2i bounds = the room's interior (no wall band included).
class RoomPlan extends RefCounted:
	var id: int = -1
	var bounds: Rect2i = Rect2i()
	var original_purpose: String = ""
	## True if this room exists solely as a stair antechamber (DG-V1.B-edits
	## anchor support per §9.3.2). DG-V1.B-base never sets this.
	var is_anchor_room: bool = false

	func center() -> Vector2i:
		return Vector2i(
			bounds.position.x + bounds.size.x / 2,
			bounds.position.y + bounds.size.y / 2,
		)


## A planned corridor as an ordered list of centerline cells.
class CorridorPlan extends RefCounted:
	var centerline: Array[Vector2i] = []
	var width: int = 1  # DG-V1.B-base: always 1; 2-wide is a follow-up
	var room_id_a: int = -1
	var room_id_b: int = -1


## A planned door cell.
class DoorPlan extends RefCounted:
	var position: Vector2i = Vector2i.ZERO
	var type: String = DungeonDoorData.TYPE_UNLOCKED
	## room ids on either side. -1 represents the corridor pseudo-room
	## (used when a door connects a room to a corridor segment).
	var room_id_a: int = -1
	var room_id_b: int = -1
	## Overlay per §8.1 step 5 — true if the door appears as a wall until
	## detected. Composer sets this when the weighted roll returns the
	## ROLL_CATEGORY_SECRET key; rasterizer reads it for cell-feature choice.
	var is_secret: bool = false
	## Populated by the §8.3 material rule in _apply_door_materials.
	## MATERIAL_NONE ("") for arches; MATERIAL_METAL for portcullises;
	## MATERIAL_WOOD_STANDARD / METAL / STONE per the tier-scaled roll otherwise.
	var door_material: String = ""


## A planned stair cell.
class StairPlan extends RefCounted:
	var position: Vector2i = Vector2i.ZERO
	var direction: String = DungeonStairData.DIRECTION_DOWN


# ---------------------------------------------------------------------------
# Public state — populated by compose()
# ---------------------------------------------------------------------------

var grid_width: int = 0
var grid_height: int = 0

var rooms: Array = []         # Array[RoomPlan]
var corridors: Array = []     # Array[CorridorPlan]
var doors: Array = []         # Array[DoorPlan]
var stairs: Array = []        # Array[StairPlan]
var connection_edges: Array = []  # Array of Vector2i(room_id_a, room_id_b)


# ---------------------------------------------------------------------------
# Internal scratch state
# ---------------------------------------------------------------------------

## Occupancy index: cell position → room id. Cells inside any RoomPlan map to
## that room's id; other cells are absent from the dict. Updated during
## scatter_rooms; read during corridor routing to detect "would this cell
## cross a third room?".
var _occupancy: Dictionary = {}

## Cells occupied by corridor centerlines. Updated during route_corridors;
## read during route_corridors so subsequent corridors can join an existing
## corridor instead of replicating its cells.
var _corridor_cells: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Plan a full dungeon layout. Caller supplies grid size, target room count,
## room size range, theme, stair counts, floor tier, and optional stair
## anchors (per layout GDD §9.3). After compose() returns, the `rooms`,
## `corridors`, `doors`, `stairs` arrays are populated and ready for the
## rasterizer.
##
## [param required_stair_positions] entries are Dictionaries with keys
## `position: Vector2i` and `direction: String` ("up" or "down") per
## layout GDD §9.3.1. Each anchor is reserved as the center of a 3×3
## antechamber RoomPlan BEFORE scatter (§9.3.2 step 1); the anchor cell
## itself becomes the stair (§9.3.2 step 5).
##
## [param floor_tier] (1-6) drives the §8.3 door material rule. Default 1.
##
## Returns the number of rooms successfully placed (INCLUDING anchor
## antechambers). Returns -1 if anchor validation fails (OOB anchor, duplicate
## anchors, anchors with conflicting directions at the same position).
func compose(
	p_grid_width: int,
	p_grid_height: int,
	target_room_count: int,
	room_size_range: Vector2i,
	theme: DungeonTheme,
	stairs_up_count: int,
	stairs_down_count: int,
	rng: RandomNumberGenerator,
	floor_tier: int = 1,
	required_stair_positions: Array = [],
) -> int:
	grid_width = p_grid_width
	grid_height = p_grid_height
	rooms = []
	corridors = []
	doors = []
	stairs = []
	connection_edges = []
	_occupancy = {}
	_corridor_cells = {}

	# §9.3.2 step 1 — reserve anchor antechambers before scatter.
	if not _validate_stair_anchors(required_stair_positions):
		push_error("DungeonRoomComposer: invalid required_stair_positions; aborting.")
		return -1
	_pre_place_anchor_rooms(required_stair_positions)

	# §9.3.2 step 2 — scatter remaining rooms.
	_scatter_rooms(target_room_count, room_size_range, rng)
	if rooms.is_empty():
		push_warning("DungeonRoomComposer: no rooms placed; grid too small for size range.")
		return 0

	# §9.3.2 steps 3-4 — connection graph + corridor routing + doors.
	_build_connection_graph(theme, rng)
	_route_all_corridors(theme, rng)
	_plan_doors(theme, rng)

	# §8.3 — per-door material rule + tier-scaled portcullis override.
	# Runs AFTER _plan_doors so it sees finalized types + is_secret overlays.
	_apply_door_materials(floor_tier, rng)

	# §9.3.2 step 5 — free-placement stairs fill in non-anchored slots.
	# Anchor stairs are already in `stairs` from _pre_place_anchor_rooms.
	_plan_stairs(stairs_up_count, stairs_down_count, rng)

	_assign_room_purposes(theme, rng)

	# §9.3.3 safety net — if any anchor antechamber ended up without a
	# corridor/door connection to the rest of the dungeon, force a direct carve.
	_ensure_anchor_connectivity()
	return rooms.size()


# ---------------------------------------------------------------------------
# §9.3 Stair anchors
# ---------------------------------------------------------------------------

const _ANCHOR_ANTECHAMBER_SIZE := 3  # 3×3 RoomPlan around each anchor

# A free-placed DOWN stair becomes the next floor's up-stair anchor, whose 3×3
# antechamber must fit inside the 1-cell wall border (see _validate_stair_anchors:
# the anchor must satisfy pos in [2, grid-3]). So any free-placed stair is kept in
# that same interior band; otherwise the next floor would be "ungenerable".
# Value = _ANCHOR_ANTECHAMBER_SIZE/2 (=1, the antechamber half-width) + 1 (the wall border).
const _ANCHOR_INTERIOR_MARGIN := 2


## Validate anchor entries per layout GDD §9.3.3:
##   - Each entry must have a `position: Vector2i` and `direction: String`.
##   - direction must be "up" or "down".
##   - position must be in bounds AND its 3×3 antechamber must fit in bounds
##     with a 1-cell margin from the grid edge (so the wall band fits too).
##   - No two anchors may share the same position with different directions.
##
## Returns true if all anchors are valid.
func _validate_stair_anchors(anchors: Array) -> bool:
	var seen_positions: Dictionary = {}
	for entry in anchors:
		if not (entry is Dictionary):
			push_error("DungeonRoomComposer: anchor entry is not a Dictionary: %s" % entry)
			return false
		var dict: Dictionary = entry
		if not dict.has("position") or not dict.has("direction"):
			push_error("DungeonRoomComposer: anchor missing position or direction: %s" % dict)
			return false
		var pos: Vector2i = dict["position"]
		var dir: String = dict["direction"]
		if not (dir == DungeonStairData.DIRECTION_UP or dir == DungeonStairData.DIRECTION_DOWN):
			push_error("DungeonRoomComposer: anchor direction must be 'up' or 'down', got '%s'." % dir)
			return false
		# Check antechamber fits in grid with 1-cell margin from edge.
		var half: int = _ANCHOR_ANTECHAMBER_SIZE / 2
		if pos.x - half < 1 or pos.x + half > grid_width - 2:
			push_error("DungeonRoomComposer: anchor %s antechamber would not fit horizontally in %dx%d grid." % [pos, grid_width, grid_height])
			return false
		if pos.y - half < 1 or pos.y + half > grid_height - 2:
			push_error("DungeonRoomComposer: anchor %s antechamber would not fit vertically in %dx%d grid." % [pos, grid_width, grid_height])
			return false
		if seen_positions.has(pos):
			var prev_dir: String = seen_positions[pos]
			if prev_dir != dir:
				push_error("DungeonRoomComposer: two anchors at position %s with conflicting directions ('%s' vs '%s')." % [pos, prev_dir, dir])
				return false
			# Same position + same direction = harmless duplicate; allow.
		seen_positions[pos] = dir
	return true


## Pre-place each anchor's 3×3 antechamber RoomPlan and plant a StairPlan at
## the anchor cell. Run BEFORE _scatter_rooms so the antechambers are visible
## to the room collision check (other rooms can't overlap them).
func _pre_place_anchor_rooms(anchors: Array) -> void:
	for entry in anchors:
		var dict: Dictionary = entry
		var pos: Vector2i = dict["position"]
		var dir: String = dict["direction"]
		var half: int = _ANCHOR_ANTECHAMBER_SIZE / 2
		var bounds := Rect2i(
			pos.x - half, pos.y - half,
			_ANCHOR_ANTECHAMBER_SIZE, _ANCHOR_ANTECHAMBER_SIZE,
		)
		# Skip if a previous anchor's antechamber already covers this cell
		# (duplicate-direction case from _validate_stair_anchors).
		if _occupancy.has(pos):
			continue
		var room := RoomPlan.new()
		room.id = rooms.size()
		room.bounds = bounds
		room.is_anchor_room = true
		rooms.append(room)
		_stamp_room_occupancy(room)
		# Plant the stair at the anchor cell now. Free-placement stairs added
		# later in _plan_stairs only fill in slots beyond these anchors.
		var stair := StairPlan.new()
		stair.position = pos
		stair.direction = dir
		stairs.append(stair)


## §9.3.3 safety net — if any anchor antechamber has no door connecting it
## to the rest of the network after door planning, force-carve a direct
## corridor from the anchor's centroid to the nearest already-passable cell.
func _ensure_anchor_connectivity() -> void:
	for r in rooms:
		var room: RoomPlan = r
		if not room.is_anchor_room:
			continue
		# Does the antechamber have at least one door?
		var has_door: bool = false
		for d in doors:
			var door: DoorPlan = d
			if door.room_id_a == room.id or door.room_id_b == room.id:
				has_door = true
				break
		if has_door:
			continue
		# No door — force-carve a corridor from the antechamber centroid to
		# the nearest non-this-room reachable cell. Walk outward in each
		# cardinal direction until we hit a corridor or another room; carve
		# the cells along the way and install a door at the antechamber edge.
		_force_carve_from_anchor(room)


func _force_carve_from_anchor(room: RoomPlan) -> void:
	var best_path: Array[Vector2i] = []
	var best_perim: Vector2i = Vector2i(-1, -1)
	var best_outward: Vector2i = Vector2i.ZERO
	var best_target_room_id: int = -1
	var best_len: int = 9999
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	]
	# Each side of the antechamber: try walking outward until we hit something.
	for side in [
		[Vector2i(0, -1), room.bounds.position.y - 1, "top"],
		[Vector2i(0, 1), room.bounds.position.y + room.bounds.size.y, "bottom"],
		[Vector2i(-1, 0), room.bounds.position.x - 1, "left"],
		[Vector2i(1, 0), room.bounds.position.x + room.bounds.size.x, "right"],
	]:
		var dir: Vector2i = side[0]
		var fixed: int = side[1]
		var is_horizontal: bool = (dir.x == 0)
		var span_start: int
		var span_end: int
		if is_horizontal:
			span_start = room.bounds.position.x
			span_end = room.bounds.position.x + room.bounds.size.x - 1
		else:
			span_start = room.bounds.position.y
			span_end = room.bounds.position.y + room.bounds.size.y - 1
		for v in range(span_start, span_end + 1):
			var perim: Vector2i = (Vector2i(v, fixed) if is_horizontal else Vector2i(fixed, v))
			var path: Array[Vector2i] = []
			var cur: Vector2i = perim + dir
			var steps: int = 0
			while cur.x >= 0 and cur.x < grid_width and cur.y >= 0 and cur.y < grid_height and steps < maxi(grid_width, grid_height):
				if _corridor_cells.has(cur):
					if path.size() < best_len:
						best_path = path.duplicate()
						best_perim = perim
						best_outward = dir
						best_target_room_id = -1  # corridor connection
						best_len = path.size()
					break
				var oid: int = _occupancy.get(cur, -1)
				if oid >= 0 and oid != room.id:
					if path.size() < best_len:
						best_path = path.duplicate()
						best_perim = perim
						best_outward = dir
						best_target_room_id = oid
						best_len = path.size()
					break
				path.append(cur)
				cur += dir
				steps += 1
	if best_perim == Vector2i(-1, -1):
		push_warning("DungeonRoomComposer: anchor room %d has no reachable target for safety-net carve." % room.id)
		return
	# Carve the path as a CorridorPlan; install a door at the antechamber edge.
	var corridor := CorridorPlan.new()
	corridor.centerline = [best_perim]
	for c in best_path:
		corridor.centerline.append(c)
		_corridor_cells[c] = true
	corridor.width = 1
	corridor.room_id_a = room.id
	corridor.room_id_b = best_target_room_id
	corridors.append(corridor)
	# Install a generic unlocked wooden door at the antechamber's perimeter cell.
	# This door is added AFTER _apply_door_materials runs, so it sets its own
	# material explicitly rather than relying on the §8.3 pass.
	var door := DoorPlan.new()
	door.position = best_perim
	door.type = DungeonDoorData.TYPE_UNLOCKED
	door.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD
	door.room_id_a = room.id
	door.room_id_b = best_target_room_id
	doors.append(door)


# ---------------------------------------------------------------------------
# §6.1 Room scatter
# ---------------------------------------------------------------------------

func _scatter_rooms(target: int, size_range: Vector2i, rng: RandomNumberGenerator) -> void:
	var attempts_cap: int = target * 5
	for _attempt in attempts_cap:
		if rooms.size() >= target:
			break
		var w: int = rng.randi_range(size_range.x, size_range.y)
		var h: int = rng.randi_range(size_range.x, size_range.y)
		# Leave at least 1 cell of clearance from the grid edge so rooms have
		# room for perimeter walls; corridors need that band to route along too.
		if w + 2 > grid_width or h + 2 > grid_height:
			continue
		var x: int = rng.randi_range(1, grid_width - 1 - w)
		var y: int = rng.randi_range(1, grid_height - 1 - h)
		var rect := Rect2i(x, y, w, h)
		if _room_collides_with_existing(rect):
			continue
		var room := RoomPlan.new()
		room.id = rooms.size()
		room.bounds = rect
		rooms.append(room)
		_stamp_room_occupancy(room)


## A new room collides with an existing room if their bounds (each grown by
## 1 cell to enforce the wall band between rooms) intersect.
##
## A 1-cell separation means rooms share a wall band — a column or row of
## wall cells between them — which is the "adjacent rooms" pattern from
## published ACKS dungeons (e.g. Sakkara Buried Temple rooms 7-8, 12-13).
## The door placer (§8) can punch a door through the wall band where the
## connection graph (§7.2) requests it.
##
## Zero separation (literally touching interiors) is rejected — there is no
## wall band to punch a door through.
func _room_collides_with_existing(rect: Rect2i) -> bool:
	# grow(1) expands the rect by 1 cell on each side; if any existing room's
	# bounds intersect this grown rect, the new room is too close.
	var grown: Rect2i = rect.grow(1)
	for r in rooms:
		var existing: RoomPlan = r
		if grown.intersects(existing.bounds):
			return true
	return false


func _stamp_room_occupancy(room: RoomPlan) -> void:
	var b: Rect2i = room.bounds
	for x in range(b.position.x, b.position.x + b.size.x):
		for y in range(b.position.y, b.position.y + b.size.y):
			_occupancy[Vector2i(x, y)] = room.id


# ---------------------------------------------------------------------------
# §7.2 Connection graph — MST + loops
# ---------------------------------------------------------------------------

## Build the connection graph. Populates `connection_edges` with Vector2i
## entries (each Vector2i.x = room id A, .y = room id B; A < B for canonical
## ordering). Uses Prim's algorithm for the MST + sampled non-MST edges as
## loops per theme.loop_frequency.
func _build_connection_graph(theme: DungeonTheme, rng: RandomNumberGenerator) -> void:
	connection_edges = []
	var n: int = rooms.size()
	if n < 2:
		return
	# Prim's algorithm: maintain a set of "visited" rooms; repeatedly pick the
	# cheapest edge from a visited to an unvisited room. Edge cost = Manhattan
	# distance between centroids.
	var visited: Dictionary = {}
	visited[0] = true
	var unvisited_count: int = n - 1
	var centroids: Array[Vector2i] = []
	for r in rooms:
		var room: RoomPlan = r
		centroids.append(room.center())
	while unvisited_count > 0:
		var best_cost: int = 999999
		var best_a: int = -1
		var best_b: int = -1
		for a in visited.keys():
			for b in n:
				if visited.has(b):
					continue
				var cost: int = _manhattan(centroids[a], centroids[b])
				if cost < best_cost:
					best_cost = cost
					best_a = a
					best_b = b
		if best_a < 0:
			break  # shouldn't happen for n ≥ 1
		visited[best_b] = true
		unvisited_count -= 1
		connection_edges.append(Vector2i(mini(best_a, best_b), maxi(best_a, best_b)))
	# Now add loop edges per theme.loop_frequency.
	if theme.loop_frequency > 0.0:
		var all_pairs: Array[Vector2i] = []
		for a in n:
			for b in range(a + 1, n):
				var canon: Vector2i = Vector2i(a, b)
				if not connection_edges.has(canon):
					all_pairs.append(canon)
		var loop_count: int = int(round(theme.loop_frequency * float(all_pairs.size())))
		# Fisher-Yates shuffle via the seeded rng.
		for i in range(all_pairs.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Vector2i = all_pairs[i]
			all_pairs[i] = all_pairs[j]
			all_pairs[j] = tmp
		for i in mini(loop_count, all_pairs.size()):
			connection_edges.append(all_pairs[i])


# ---------------------------------------------------------------------------
# §7.3 Corridor routing
# ---------------------------------------------------------------------------

const _STYLE_STRATEGY_ORDER := {
	# Order to try routing strategies. Each strategy is a string id consumed
	# by _route_with_strategy.
	DungeonTheme.CORRIDOR_STRAIGHT: ["L_h_first", "L_v_first"],
	DungeonTheme.CORRIDOR_BENT: ["L_h_first", "L_v_first", "S_h_first", "S_v_first"],
	DungeonTheme.CORRIDOR_LABYRINTH: ["S_h_first", "S_v_first", "L_h_first", "L_v_first"],
}


func _route_all_corridors(theme: DungeonTheme, rng: RandomNumberGenerator) -> void:
	for edge in connection_edges:
		var v: Vector2i = edge
		var room_a: RoomPlan = rooms[v.x]
		var room_b: RoomPlan = rooms[v.y]
		# Adjacent-rooms shortcut: if the two rooms share a wall band, we
		# don't need a corridor — just install a door directly through the
		# shared wall cell. Returns immediately if successful.
		if _try_install_adjacent_door(room_a, room_b, rng):
			continue
		# Otherwise route an axis-aligned corridor between them.
		var corridor: CorridorPlan = _route_corridor(room_a, room_b, theme, rng)
		if corridor != null:
			corridors.append(corridor)
			for c in corridor.centerline:
				_corridor_cells[c] = true


## If rooms A and B are exactly 1 cell apart (sharing a wall band), pick one
## cell on the shared band and install a door there. Returns true on success.
func _try_install_adjacent_door(a: RoomPlan, b: RoomPlan, rng: RandomNumberGenerator) -> bool:
	var candidates: Array[Vector2i] = _shared_wall_cells(a, b)
	if candidates.is_empty():
		return false
	# Pick a random one with the seeded rng.
	var picked: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	var door := DoorPlan.new()
	door.position = picked
	door.room_id_a = a.id
	door.room_id_b = b.id
	# Door type rolled later in _plan_doors when we know the theme weights;
	# stamp a sentinel here and let _plan_doors override.
	door.type = "__pending__"
	doors.append(door)
	return true


## Return the set of wall-band cells shared by adjacent rooms (rooms 1 cell
## apart). Empty array if the rooms aren't adjacent.
func _shared_wall_cells(a: RoomPlan, b: RoomPlan) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	# Two rooms are vertically adjacent if one's right edge + 1 == other's left edge
	# and they overlap in y. Similarly for the other axes.
	var a_left: int = a.bounds.position.x
	var a_right: int = a.bounds.position.x + a.bounds.size.x - 1  # inclusive last cell
	var a_top: int = a.bounds.position.y
	var a_bottom: int = a.bounds.position.y + a.bounds.size.y - 1
	var b_left: int = b.bounds.position.x
	var b_right: int = b.bounds.position.x + b.bounds.size.x - 1
	var b_top: int = b.bounds.position.y
	var b_bottom: int = b.bounds.position.y + b.bounds.size.y - 1
	# Wall band column at x_wall between a and b (a is left, b is right):
	if a_right + 2 == b_left:
		var x_wall: int = a_right + 1
		var y_lo: int = maxi(a_top, b_top)
		var y_hi: int = mini(a_bottom, b_bottom)
		for y in range(y_lo, y_hi + 1):
			out.append(Vector2i(x_wall, y))
	# b is left, a is right:
	if b_right + 2 == a_left:
		var x_wall: int = b_right + 1
		var y_lo: int = maxi(a_top, b_top)
		var y_hi: int = mini(a_bottom, b_bottom)
		for y in range(y_lo, y_hi + 1):
			out.append(Vector2i(x_wall, y))
	# Wall band row at y_wall between a (top) and b (bottom):
	if a_bottom + 2 == b_top:
		var y_wall: int = a_bottom + 1
		var x_lo: int = maxi(a_left, b_left)
		var x_hi: int = mini(a_right, b_right)
		for x in range(x_lo, x_hi + 1):
			out.append(Vector2i(x, y_wall))
	# b is top, a is bottom:
	if b_bottom + 2 == a_top:
		var y_wall: int = b_bottom + 1
		var x_lo: int = maxi(a_left, b_left)
		var x_hi: int = mini(a_right, b_right)
		for x in range(x_lo, x_hi + 1):
			out.append(Vector2i(x, y_wall))
	return out


## Route a corridor between two non-adjacent rooms. Picks start/end perimeter
## cells facing each other, tries strategy paths in order, returns the first
## that doesn't cross a third room — or the best-with-crossings as fallback.
func _route_corridor(a: RoomPlan, b: RoomPlan, theme: DungeonTheme, rng: RandomNumberGenerator) -> CorridorPlan:
	var start: Vector2i = _pick_perimeter_facing(a, b.center())
	var end: Vector2i = _pick_perimeter_facing(b, a.center())
	if start == Vector2i(-1, -1) or end == Vector2i(-1, -1):
		return null
	var strategies: Array = _STYLE_STRATEGY_ORDER.get(theme.corridor_style, ["L_h_first", "L_v_first"])
	var best_path: Array[Vector2i] = []
	var best_crossings: int = 999999
	for sid in strategies:
		var path: Array[Vector2i] = _route_with_strategy(start, end, sid)
		if path.is_empty():
			continue
		var crossings: int = _count_room_crossings(path, a.id, b.id)
		if crossings == 0:
			best_path = path
			break  # ideal — accept immediately
		if crossings < best_crossings:
			best_crossings = crossings
			best_path = path
	if best_path.is_empty():
		return null
	var corridor := CorridorPlan.new()
	corridor.centerline = best_path
	corridor.width = 1  # V1.B-base ships 1-wide; 2-wide is a follow-up
	corridor.room_id_a = a.id
	corridor.room_id_b = b.id
	return corridor


## Pick the cell adjacent to room's outer wall on the side facing target.
## Returns Vector2i(-1, -1) if the room is at the grid edge on the facing side
## (cell would be out of bounds).
func _pick_perimeter_facing(room: RoomPlan, target: Vector2i) -> Vector2i:
	var c: Vector2i = room.center()
	var dx: int = target.x - c.x
	var dy: int = target.y - c.y
	# Pick the dominant axis; if room is offset more in x than y from target,
	# exit from the east/west side; else north/south.
	if absi(dx) >= absi(dy):
		if dx >= 0:
			# Exit east — cell at x = room.right + 1
			var x: int = room.bounds.position.x + room.bounds.size.x
			var y: int = c.y
			if x < grid_width and y >= 0 and y < grid_height:
				return Vector2i(x, y)
		else:
			# Exit west
			var x: int = room.bounds.position.x - 1
			var y: int = c.y
			if x >= 0 and y >= 0 and y < grid_height:
				return Vector2i(x, y)
	else:
		if dy >= 0:
			# Exit south — cell at y = room.bottom + 1
			var x: int = c.x
			var y: int = room.bounds.position.y + room.bounds.size.y
			if y < grid_height and x >= 0 and x < grid_width:
				return Vector2i(x, y)
		else:
			# Exit north
			var x: int = c.x
			var y: int = room.bounds.position.y - 1
			if y >= 0 and x >= 0 and x < grid_width:
				return Vector2i(x, y)
	# All preferred exits OOB — try the orthogonal axes as fallback.
	var fallbacks: Array[Vector2i] = [
		Vector2i(room.bounds.position.x + room.bounds.size.x, c.y),
		Vector2i(room.bounds.position.x - 1, c.y),
		Vector2i(c.x, room.bounds.position.y + room.bounds.size.y),
		Vector2i(c.x, room.bounds.position.y - 1),
	]
	for f in fallbacks:
		if f.x >= 0 and f.x < grid_width and f.y >= 0 and f.y < grid_height:
			return f
	return Vector2i(-1, -1)


## Route an axis-aligned path between two cells using one of the named
## strategies. Returns the cell list (inclusive of start and end), or empty
## if the strategy can't be applied (rare for these straightforward shapes).
func _route_with_strategy(start: Vector2i, end: Vector2i, strategy_id: String) -> Array[Vector2i]:
	match strategy_id:
		"L_h_first":
			return _path_L(start, end, true)
		"L_v_first":
			return _path_L(start, end, false)
		"S_h_first":
			return _path_S(start, end, true)
		"S_v_first":
			return _path_S(start, end, false)
		_:
			return [] as Array[Vector2i]


## L-shaped path: one bend. h_first = true → horizontal then vertical.
func _path_L(start: Vector2i, end: Vector2i, h_first: bool) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	if h_first:
		_walk_horizontal(path, end.x)
		_walk_vertical(path, end.y)
	else:
		_walk_vertical(path, end.y)
		_walk_horizontal(path, end.x)
	return path


## S-shaped path: three segments around a midpoint.
## h_first = true → horizontal-vertical-horizontal zigzag through mid_x.
func _path_S(start: Vector2i, end: Vector2i, h_first: bool) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	if h_first:
		var mid_x: int = (start.x + end.x) / 2
		_walk_horizontal(path, mid_x)
		_walk_vertical(path, end.y)
		_walk_horizontal(path, end.x)
	else:
		var mid_y: int = (start.y + end.y) / 2
		_walk_vertical(path, mid_y)
		_walk_horizontal(path, end.x)
		_walk_vertical(path, end.y)
	return path


## Extend path with cells walking horizontally from the last cell's x to target_x.
func _walk_horizontal(path: Array[Vector2i], target_x: int) -> void:
	if path.is_empty():
		return
	var cur: Vector2i = path[-1]
	var step: int = 1 if target_x > cur.x else -1
	while cur.x != target_x:
		cur = Vector2i(cur.x + step, cur.y)
		path.append(cur)


## Extend path with cells walking vertically from the last cell's y to target_y.
func _walk_vertical(path: Array[Vector2i], target_y: int) -> void:
	if path.is_empty():
		return
	var cur: Vector2i = path[-1]
	var step: int = 1 if target_y > cur.y else -1
	while cur.y != target_y:
		cur = Vector2i(cur.x, cur.y + step)
		path.append(cur)


## Count cells of `path` that land inside a room OTHER than `except_a` or
## `except_b`. Useful for picking the strategy with fewest unintended room
## intrusions.
func _count_room_crossings(path: Array[Vector2i], except_a: int, except_b: int) -> int:
	var n: int = 0
	for c in path:
		var rid: int = _occupancy.get(c, -1)
		if rid < 0:
			continue
		if rid == except_a or rid == except_b:
			continue
		n += 1
	return n


# ---------------------------------------------------------------------------
# §8.1 Door placement
# ---------------------------------------------------------------------------

const _BASELINE_DOOR_WEIGHTS := {
	DungeonDoorData.TYPE_ARCH: 15,
	DungeonDoorData.TYPE_UNLOCKED: 40,
	DungeonDoorData.TYPE_LOCKED: 15,
	DungeonDoorData.TYPE_TRAPPED: 10,
	# "secret" is a roll-category that triggers _resolve_secret_roll;
	# the final door type is then one of {unlocked, locked, trapped} with
	# is_secret=true, per §8.1 step 5.
	DungeonDoorData.ROLL_CATEGORY_SECRET: 10,
	DungeonDoorData.TYPE_PORTCULLIS: 10,
}


# §8.1 step 5 sub-weight roll for "secret" expansion:
# 50% unlocked, 40% locked, 10% trapped.
const _SECRET_UNDERLYING_WEIGHTS := {
	DungeonDoorData.TYPE_UNLOCKED: 50,
	DungeonDoorData.TYPE_LOCKED: 40,
	DungeonDoorData.TYPE_TRAPPED: 10,
}


func _plan_doors(theme: DungeonTheme, rng: RandomNumberGenerator) -> void:
	var weights: Dictionary = theme.door_type_weights
	if weights.is_empty():
		weights = _BASELINE_DOOR_WEIGHTS
	# Fill in types for adjacent-room doors that _try_install_adjacent_door
	# inserted with the "__pending__" sentinel.
	for d in doors:
		var door: DoorPlan = d
		if door.type == "__pending__":
			_assign_door_type(door, weights, rng)
	# Walk each corridor; install a door at the entry cell (first cell adjacent
	# to room A's interior) and exit cell (last cell adjacent to room B's
	# interior). For most corridors, start == entry and end == exit because
	# _pick_perimeter_facing chose cells adjacent to room interiors.
	for c in corridors:
		var corridor: CorridorPlan = c
		if corridor.centerline.is_empty():
			continue
		_install_corridor_door(corridor.centerline[0], corridor.room_id_a, weights, rng)
		_install_corridor_door(corridor.centerline[-1], corridor.room_id_b, weights, rng)


## Install a door at the given corridor cell, connecting it to a room.
## Skips if a door is already at that position (e.g. when two corridors
## happen to enter the same room at the same cell).
func _install_corridor_door(cell: Vector2i, room_id: int, weights: Dictionary, rng: RandomNumberGenerator) -> void:
	for d in doors:
		var existing: DoorPlan = d
		if existing.position == cell:
			return
	var door := DoorPlan.new()
	door.position = cell
	door.room_id_a = room_id
	door.room_id_b = -1  # corridor pseudo-room
	_assign_door_type(door, weights, rng)
	doors.append(door)


## Pick a door type from the weighted roll; if "secret" comes up, expand
## via the §8.1 step-5 sub-weight roll and set is_secret = true. After this
## call, door.type is one of DungeonDoorData.VALID_TYPES (never "secret").
func _assign_door_type(door: DoorPlan, weights: Dictionary, rng: RandomNumberGenerator) -> void:
	var roll_result: String = _weighted_pick(weights, rng)
	if roll_result == DungeonDoorData.ROLL_CATEGORY_SECRET:
		door.type = _weighted_pick(_SECRET_UNDERLYING_WEIGHTS, rng)
		door.is_secret = true
	else:
		door.type = roll_result
		door.is_secret = false


# ---------------------------------------------------------------------------
# §8.3 Door material rule + tier-scaled portcullis override
# ---------------------------------------------------------------------------

## Walk every door and apply the §8.3 material pass per layout GDD §8.3.1:
##
##   1. Skip arches and existing portcullises.
##   2. Skip secret-overlay doors (force door_material = "wood_standard").
##   3. Portcullis-override roll: d100 ≤ 5×tier → type=portcullis, material=metal_bars.
##   4. Material roll: d100 ≤ 5×tier → metal (d6: 1-3 iron, 4-6 stone).
##      Else door_material = "wood_standard".
##
## Mutates each DoorPlan in place. Idempotent for archways and portcullises
## (they short-circuit at step 1).
func _apply_door_materials(floor_tier: int, rng: RandomNumberGenerator) -> void:
	var t: int = clampi(floor_tier, 1, 6)
	var threshold: int = 5 * t  # both rolls use the same threshold per §8.3
	for d in doors:
		var door: DoorPlan = d
		# Step 1: arches and existing portcullises.
		if door.type == DungeonDoorData.TYPE_ARCH:
			door.door_material = DungeonDoorData.MATERIAL_NONE  # open passage
			continue
		if door.type == DungeonDoorData.TYPE_PORTCULLIS:
			door.door_material = DungeonDoorData.MATERIAL_METAL
			continue
		# Step 2: secret-overlay doors.
		if door.is_secret:
			door.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD
			continue
		# Step 3: portcullis-override roll.
		if rng.randi_range(1, 100) <= threshold:
			door.type = DungeonDoorData.TYPE_PORTCULLIS
			door.door_material = DungeonDoorData.MATERIAL_METAL
			# is_secret left as-is (false here; secret doors were skipped in step 2).
			continue
		# Step 4: material roll. d100 ≤ 5×tier → hard material, split d6 between
		# metal (1-3) and stone (4-6); else wood_standard.
		if rng.randi_range(1, 100) <= threshold:
			var d6: int = rng.randi_range(1, 6)
			door.door_material = (DungeonDoorData.MATERIAL_METAL if d6 <= 3
				else DungeonDoorData.MATERIAL_STONE)
		else:
			door.door_material = DungeonDoorData.MATERIAL_WOOD_STANDARD


# ---------------------------------------------------------------------------
# §9.1 Stair placement
# ---------------------------------------------------------------------------

func _plan_stairs(up_count: int, down_count: int, rng: RandomNumberGenerator) -> void:
	if rooms.is_empty():
		return
	# Anchor stairs (placed in _pre_place_anchor_rooms) count toward the
	# requested totals. Subtract them so free-placement only fills the rest.
	var anchored_up: int = 0
	var anchored_down: int = 0
	for s in stairs:
		var st: StairPlan = s
		if st.direction == DungeonStairData.DIRECTION_UP:
			anchored_up += 1
		else:
			anchored_down += 1
	var ups_left: int = maxi(0, up_count - anchored_up)
	var downs_left: int = maxi(0, down_count - anchored_down)
	var total: int = ups_left + downs_left
	if total <= 0:
		return
	# Free-placement stairs go in NON-ANCHOR rooms preferentially — anchor
	# rooms exist solely to host their pre-planted stair; cluttering them
	# with extra stairs muddies the §9.3 anchor semantics.
	var available_rooms: Array[int] = []
	for r in rooms:
		var room: RoomPlan = r
		if room.is_anchor_room:
			continue
		available_rooms.append(room.id)
	# Fall back to anchor rooms if no non-anchor room is available (extreme
	# degenerate case for tiny grids).
	if available_rooms.is_empty():
		for r in rooms:
			available_rooms.append((r as RoomPlan).id)
	# Shuffle.
	for i in range(available_rooms.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = available_rooms[i]
		available_rooms[i] = available_rooms[j]
		available_rooms[j] = tmp
	var placed: int = 0
	for room_id in available_rooms:
		if placed >= total:
			break
		var room: RoomPlan = rooms[room_id]
		# Keep the stair cell in the anchorable interior [margin, grid-1-margin] so
		# a down-stair can anchor the next floor's up-stair antechamber (mode-1 fix).
		var lo_x: int = maxi(room.bounds.position.x, _ANCHOR_INTERIOR_MARGIN)
		var hi_x: int = mini(room.bounds.position.x + room.bounds.size.x - 1, grid_width - 1 - _ANCHOR_INTERIOR_MARGIN)
		var lo_y: int = maxi(room.bounds.position.y, _ANCHOR_INTERIOR_MARGIN)
		var hi_y: int = mini(room.bounds.position.y + room.bounds.size.y - 1, grid_height - 1 - _ANCHOR_INTERIOR_MARGIN)
		if lo_x > hi_x or lo_y > hi_y:
			continue  # room has no anchorable cell — try the next room
		var cx: int = rng.randi_range(lo_x, hi_x)
		var cy: int = rng.randi_range(lo_y, hi_y)
		var stair := StairPlan.new()
		stair.position = Vector2i(cx, cy)
		if ups_left > 0:
			stair.direction = DungeonStairData.DIRECTION_UP
			ups_left -= 1
		elif downs_left > 0:
			stair.direction = DungeonStairData.DIRECTION_DOWN
			downs_left -= 1
		else:
			break
		stairs.append(stair)
		placed += 1


# ---------------------------------------------------------------------------
# §6.3 Original purpose assignment
# ---------------------------------------------------------------------------

func _assign_room_purposes(theme: DungeonTheme, rng: RandomNumberGenerator) -> void:
	if theme.purpose_weights.is_empty():
		return
	var total: int = 0
	for k in theme.purpose_weights:
		total += int(theme.purpose_weights[k])
	if total <= 0:
		return
	for r in rooms:
		var room: RoomPlan = r
		var roll: int = rng.randi_range(1, total)
		var acc: int = 0
		for k in theme.purpose_weights:
			acc += int(theme.purpose_weights[k])
			if roll <= acc:
				room.original_purpose = str(k)
				break


# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total: int = 0
	for k in weights:
		total += int(weights[k])
	if total <= 0:
		return weights.keys()[0] if not weights.is_empty() else ""
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for k in weights:
		acc += int(weights[k])
		if roll <= acc:
			return str(k)
	return str(weights.keys().back())
