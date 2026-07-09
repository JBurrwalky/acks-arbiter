class_name DungeonFactionInputBuilder
extends RefCounted

## Adapter: DungeonLayout (DG-V1 stocking output) → DungeonFactionInput
## (`gdd-dungeon-factions.md` §11 integration). Reads the floor's rooms, stocked
## monster_groups, doors, and corridor connectivity, enriches each placement with
## monster-catalog traits (MonsterFactionTraits), and derives the room-adjacency
## graph with edge kinds for chokepoint detection.
##
## This is the real integration seam (the golden test drives the generator with a
## hand-authored input instead, so this is not exercised there). Single-floor;
## §10 multi-level composition is left to the caller (add rooms from several
## floors + KIND_STAIRS edges — the generator is level-aware). Deterministic:
## rooms/groups/doors iterate in layout order and corridor components are keyed
## by their smallest cell.
##
## V1 limitations (documented): controller linkage (skeletons←necromancer, tamed
## beasts) is not inferred here — DG-V1 stocking does not yet emit that relation,
## so uncontrolled unintelligent groups are (correctly, §2.1) excluded from
## factions. Corridor narrow-width detection is not attempted; a room-to-corridor
## door already reads as a chokepoint.


## Build a single-floor faction input. [param dungeon_id] scopes the output ids.
static func from_layout(layout: DungeonLayout, dungeon_id: String) -> DungeonFactionInput:
	var input := DungeonFactionInput.new()
	input.dungeon_id = dungeon_id
	input.default_level = layout.level_number

	# --- Rooms --------------------------------------------------------------
	for room in layout.rooms:
		var r: DungeonFactionRoomInput = input.add_room(room.id, layout.level_number)
		r.original_purpose = room.original_purpose

	# --- Placements from stocked monster groups -----------------------------
	for group in layout.monster_groups:
		_add_group_placements(input, group)

	# --- Adjacency ----------------------------------------------------------
	_build_adjacency(input, layout)
	return input


# ---------------------------------------------------------------------------
# Placements
# ---------------------------------------------------------------------------

static func _add_group_placements(input: DungeonFactionInput, group: MonsterGroupData) -> void:
	if not input.has_room(group.room_id):
		return
	# Primary stocked monster.
	_place_one(input, group.room_id, group.monster_name, group.number_appearing,
		group.is_lair, group.alignment, group.morale, true)
	# Associated creatures share the room (e.g. leaders / attendant beasts).
	for assoc in group.associated_creatures:
		if not (assoc is Dictionary):
			continue
		var a: Dictionary = assoc
		_place_one(input, group.room_id, String(a.get("name", "")),
			int(a.get("number_appearing", 0)), false, group.alignment, group.morale, false)


static func _place_one(input: DungeonFactionInput, room_id: int, monster_name: String,
		number: int, is_lair: bool, group_alignment: String, group_morale: int,
		is_primary: bool) -> void:
	if monster_name == "" or number <= 0:
		return
	var traits: Dictionary = MonsterFactionTraits.traits_for(monster_name)
	var opts: Dictionary = {
		"number": number,
		"is_lair": is_lair,
		"morale": group_morale,
	}
	if traits.is_empty():
		# Unknown monster: conservative low-intelligence default so it can still
		# form a faction if organized, but carries no special-ability flag.
		opts["intelligence"] = DungeonFactionMonsterPlacement.INT_LOW
		opts["alignment"] = group_alignment if group_alignment != "" else "neutral"
		opts["hd"] = 1.0
		opts["monster_types"] = [] as Array[String]
	else:
		opts["intelligence"] = String(traits.get("intelligence", DungeonFactionMonsterPlacement.INT_LOW))
		opts["alignment"] = String(traits.get("alignment", group_alignment if group_alignment != "" else "neutral"))
		opts["hd"] = float(traits.get("hd", 1.0))
		opts["monster_types"] = traits.get("monster_types", [] as Array[String])
		opts["has_special_abilities"] = bool(traits.get("has_special_abilities", false))
	# The lair-room primary placement is treated as the group's leader anchor.
	if is_primary and is_lair:
		opts["is_leader"] = true
		opts["leader_hd"] = float(opts.get("hd", 1.0))
	var species: String = _species_id(monster_name, traits)
	input.place(room_id, species, number, opts)


static func _species_id(monster_name: String, traits: Dictionary) -> String:
	var id: String = String(traits.get("id", ""))
	if id != "":
		return id
	return monster_name.to_lower().replace(" ", "_")


# ---------------------------------------------------------------------------
# Adjacency (direct room-room doors + shared-corridor components)
# ---------------------------------------------------------------------------

static func _build_adjacency(input: DungeonFactionInput, layout: DungeonLayout) -> void:
	# 1) Direct room-to-room doors.
	for door in layout.doors:
		if door.connects.size() >= 2 and door.connects[0] >= 0 and door.connects[1] >= 0:
			var kind: String = _door_edge_kind(door)
			input.connect_rooms(door.connects[0], door.connects[1], kind)

	# 2) Corridor-mediated adjacency: rooms whose doors open into the same
	#    corridor component are connected; edge kind = more-restrictive of the
	#    two doors' kinds.
	var comp_of_cell: Dictionary = _corridor_components(layout)
	var rooms_per_comp: Dictionary = {}          # comp_id -> { room_id: door_kind }
	for door in layout.doors:
		if door.connects.size() < 1:
			continue
		var room_side: int = -1
		for c in door.connects:
			if c >= 0:
				room_side = c
				break
		if room_side < 0:
			continue
		var comp_id: int = _corridor_comp_adjacent_to(layout, comp_of_cell, door.position)
		if comp_id < 0:
			continue
		if not rooms_per_comp.has(comp_id):
			rooms_per_comp[comp_id] = {}
		var kind2: String = _door_edge_kind(door)
		# Keep the more restrictive access kind if a room has several doors here.
		var prev: String = String(rooms_per_comp[comp_id].get(room_side, DungeonFactionEdge.KIND_OPEN))
		rooms_per_comp[comp_id][room_side] = _more_restrictive(prev, kind2)

	for comp_id in rooms_per_comp.keys():
		var members: Dictionary = rooms_per_comp[comp_id]
		var ids: Array = members.keys()
		ids.sort()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a: int = ids[i]
				var b: int = ids[j]
				var edge_kind: String = _more_restrictive(String(members[a]), String(members[b]))
				input.connect_rooms(a, b, edge_kind)


## Flood-fill corridor cells into components. Returns { "x,y": comp_id }.
static func _corridor_components(layout: DungeonLayout) -> Dictionary:
	var comp_of: Dictionary = {}
	var next_id: int = 0
	for x in layout.grid_width:
		for y in layout.grid_height:
			var cell: DungeonCellData = layout.get_cell(x, y)
			if cell == null or not cell.is_corridor or not cell.passable:
				continue
			var key: String = "%d,%d" % [x, y]
			if comp_of.has(key):
				continue
			_flood_corridor(layout, x, y, next_id, comp_of)
			next_id += 1
	return comp_of


static func _flood_corridor(layout: DungeonLayout, sx: int, sy: int, comp_id: int,
		comp_of: Dictionary) -> void:
	var stack: Array = [[sx, sy]]
	while not stack.is_empty():
		var p: Array = stack.pop_back()
		var x: int = p[0]
		var y: int = p[1]
		var key: String = "%d,%d" % [x, y]
		if comp_of.has(key):
			continue
		var cell: DungeonCellData = layout.get_cell(x, y)
		if cell == null or not cell.is_corridor or not cell.passable:
			continue
		comp_of[key] = comp_id
		stack.append([x + 1, y])
		stack.append([x - 1, y])
		stack.append([x, y + 1])
		stack.append([x, y - 1])


## The corridor component id 4-adjacent to a door cell, or -1 if none.
static func _corridor_comp_adjacent_to(layout: DungeonLayout, comp_of: Dictionary,
		pos: Vector2i) -> int:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var key: String = "%d,%d" % [pos.x + d.x, pos.y + d.y]
		if comp_of.has(key):
			return int(comp_of[key])
	return -1


# ---------------------------------------------------------------------------
# Door → edge-kind mapping
# ---------------------------------------------------------------------------

static func _door_edge_kind(door: DungeonDoorData) -> String:
	if door.is_secret:
		return DungeonFactionEdge.KIND_SECRET
	match door.type:
		DungeonDoorData.TYPE_ARCH:
			return DungeonFactionEdge.KIND_OPEN
		DungeonDoorData.TYPE_LOCKED:
			return DungeonFactionEdge.KIND_LOCKED
		_:
			# unlocked / trapped / portcullis: an openable chokepoint.
			return DungeonFactionEdge.KIND_DOOR


const _RESTRICT_RANK: Dictionary = {
	DungeonFactionEdge.KIND_OPEN: 0,
	DungeonFactionEdge.KIND_NARROW: 1,
	DungeonFactionEdge.KIND_STAIRS: 1,
	DungeonFactionEdge.KIND_DOOR: 2,
	DungeonFactionEdge.KIND_LOCKED: 3,
	DungeonFactionEdge.KIND_BARRED: 3,
	DungeonFactionEdge.KIND_STUCK: 3,
	DungeonFactionEdge.KIND_SECRET: 4,
}


static func _more_restrictive(a: String, b: String) -> String:
	var ra: int = int(_RESTRICT_RANK.get(a, 2))
	var rb: int = int(_RESTRICT_RANK.get(b, 2))
	return a if ra >= rb else b
