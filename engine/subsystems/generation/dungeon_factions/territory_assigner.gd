class_name TerritoryAssigner
extends RefCounted

## Territory assignment (`gdd-dungeon-factions.md` §4). Expands each faction's
## territory outward from its controlled (member) rooms through OPEN passages,
## claiming empty rooms for the nearest faction and stopping AT any chokepoint
## (door / narrow corridor / strong-boundary door) or another faction's rooms.
## Produces the DungeonTerritoryMap and fills each faction's patrol/frontier room
## lists. Deterministic multi-source BFS — no RNG.
##
## Expansion medium: only wide OPEN edges (archways / ≥10' corridors) are
## traversed into empty rooms. Every other passage type is a defensible
## chokepoint the faction claims UP TO but not across (§4.3.2 — "factions
## preferentially claim territory up to these points"). Member/core rooms are
## always controlled regardless of the doors between them (they are occupied).


## Assign territory. Mutates each faction's patrol_room_ids / frontier_room_ids
## and returns the DungeonTerritoryMap. [param factions], [param threats] are the
## identifier output.
static func assign(input: DungeonFactionInput, factions: Array,
		threats: Array) -> DungeonTerritoryMap:
	var tmap := DungeonTerritoryMap.new()

	# --- Index core rooms and threat rooms ----------------------------------
	var core_owner: Dictionary = {}                 # room_id -> faction_id
	for f in factions:
		for r in f.core_room_ids:
			core_owner[r] = f.id
	var threat_room: Dictionary = {}                # room_id -> threat_id
	for t in threats:
		threat_room[t.room_id] = t.id

	# --- Claimable = rooms with no stocked placements (truly empty) ----------
	var claimable: Dictionary = {}
	for room in input.rooms:
		if not room.is_occupied():
			claimable[room.id] = true

	# --- Multi-source BFS from every core room over wide-open edges ----------
	# assigned[room] = { "faction": id, "dist": int }; contested tracked separately.
	var assigned: Dictionary = {}
	var contested: Dictionary = {}                  # room_id -> { faction_id: true }
	var queue: Array = []                           # [dist, room_id, faction_id]

	var sorted_factions: Array = factions.duplicate()
	sorted_factions.sort_custom(func(a, b): return a.id < b.id)
	for f in sorted_factions:
		var seeds: Array = f.core_room_ids.duplicate()
		seeds.sort()
		for r in seeds:
			queue.append([0, int(r), f.id])

	var head: int = 0
	while head < queue.size():
		# Stable order: sort the unread tail by (dist, room, faction) each pass is
		# O(n log n) but n is tiny (<50); guarantees deterministic contest ties.
		_sort_queue_tail(queue, head)
		var entry: Array = queue[head]
		head += 1
		var dist: int = entry[0]
		var cur: int = entry[1]
		var fid: String = entry[2]
		var room: DungeonFactionRoomInput = input.get_room(cur)
		if room == null:
			continue
		for e in _sorted_neighbors(room):
			if not _traversable(e):
				continue
			var n: int = e.to_room_id
			if core_owner.has(n) or threat_room.has(n) or not claimable.has(n):
				continue
			var nd: int = dist + 1
			if not assigned.has(n):
				assigned[n] = {"faction": fid, "dist": nd}
				queue.append([nd, n, fid])
			else:
				var prev: Dictionary = assigned[n]
				if int(prev["dist"]) == nd and String(prev["faction"]) != fid:
					# Equal-distance reach by two factions ⇒ contested (§4.4).
					if not contested.has(n):
						contested[n] = {}
						contested[n][String(prev["faction"])] = true
					contested[n][fid] = true

	# --- Build the territory map + fill faction room lists ------------------
	var faction_by_id: Dictionary = {}
	for f in factions:
		faction_by_id[f.id] = f

	# Core rooms.
	for f in factions:
		for r in f.core_room_ids:
			var e := DungeonTerritoryEntry.new()
			e.status = DungeonTerritoryEntry.STATUS_CORE
			e.controlling_faction_id = f.id
			tmap.set_entry(r, e)

	# Threat zones.
	for t in threats:
		var te := DungeonTerritoryEntry.new()
		te.status = DungeonTerritoryEntry.STATUS_SOLITARY_THREAT
		te.solitary_threat_id = t.id
		tmap.set_entry(t.room_id, te)

	# Contested rooms.
	for rid in contested.keys():
		var ce := DungeonTerritoryEntry.new()
		ce.status = DungeonTerritoryEntry.STATUS_CONTESTED
		var ids: Array[String] = []
		for k in contested[rid].keys():
			ids.append(String(k))
		ids.sort()
		ce.contesting_faction_ids = ids
		tmap.set_entry(rid, ce)

	# Assigned (empty, single-owner) rooms.
	for rid in assigned.keys():
		if contested.has(rid):
			continue
		var fid2: String = String(assigned[rid]["faction"])
		var pe := DungeonTerritoryEntry.new()
		pe.status = DungeonTerritoryEntry.STATUS_PATROL      # frontier decided below
		pe.controlling_faction_id = fid2
		tmap.set_entry(rid, pe)

	# --- Frontier detection + faction room-list population -------------------
	_classify_frontiers(input, factions, faction_by_id, tmap, contested)

	return tmap


# ---------------------------------------------------------------------------
# Frontier classification (§4.2 — a room adjacent to a DIFFERENT faction or a
# contested zone is a frontier). Core frontier rooms keep "core" status but join
# frontier_room_ids; empty frontier rooms get "frontier" status.
# ---------------------------------------------------------------------------

static func _classify_frontiers(input: DungeonFactionInput, factions: Array,
		faction_by_id: Dictionary, tmap: DungeonTerritoryMap, contested: Dictionary) -> void:
	# Reset the derived lists in place (they are typed Array[int]; assigning a plain
	# untyped [] is an "Invalid assignment" runtime error that aborts this pass, so
	# the frontier/patrol classification never runs — clear() keeps the element type).
	for f in factions:
		f.patrol_room_ids.clear()
		f.frontier_room_ids.clear()

	# Every controlled room (core + patrol) evaluated for boundary adjacency.
	for rid in tmap.room_assignments.keys():
		var e: DungeonTerritoryEntry = tmap.room_assignments[rid]
		var fid: String = e.controlling_faction_id
		if fid == "":
			continue
		var room: DungeonFactionRoomInput = input.get_room(rid)
		if room == null:
			continue
		var is_frontier: bool = false
		for edge in room.neighbors:
			var n: int = edge.to_room_id
			if contested.has(n):
				is_frontier = true
				break
			var ne: DungeonTerritoryEntry = tmap.room_assignments.get(n, null)
			if ne != null and ne.controlling_faction_id != "" and ne.controlling_faction_id != fid:
				is_frontier = true
				break
		var f: DungeonFaction = faction_by_id[fid]
		if e.status == DungeonTerritoryEntry.STATUS_CORE:
			if is_frontier and not f.frontier_room_ids.has(int(rid)):
				f.frontier_room_ids.append(int(rid))
		else:
			# Empty controlled room: patrol unless frontier.
			if is_frontier:
				e.status = DungeonTerritoryEntry.STATUS_FRONTIER
				if not f.frontier_room_ids.has(int(rid)):
					f.frontier_room_ids.append(int(rid))
			else:
				if not f.patrol_room_ids.has(int(rid)):
					f.patrol_room_ids.append(int(rid))

	for f in factions:
		f.patrol_room_ids.sort()
		f.frontier_room_ids.sort()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Territory expansion crosses ONLY wide open passages; every door / narrow /
## strong-boundary / stair edge is a defensible chokepoint that halts expansion.
static func _traversable(e: DungeonFactionEdge) -> bool:
	return e.kind == DungeonFactionEdge.KIND_OPEN and e.width_ft >= 10


static func _sorted_neighbors(room: DungeonFactionRoomInput) -> Array:
	var edges: Array = room.neighbors.duplicate()
	edges.sort_custom(func(a, b): return a.to_room_id < b.to_room_id)
	return edges


static func _sort_queue_tail(queue: Array, head: int) -> void:
	# Sort only the still-unprocessed tail so BFS pops in (dist, room, faction)
	# order — deterministic contested-tie resolution on tiny graphs.
	if head >= queue.size():
		return
	var tail: Array = queue.slice(head)
	tail.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	for i in tail.size():
		queue[head + i] = tail[i]
