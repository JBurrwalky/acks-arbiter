class_name FactionGraph
extends RefCounted

## Deterministic graph traversal toolkit over a DungeonFactionInput room graph
## (`gdd-dungeon-factions.md` §4.2/§4.3, §13.2). All traversals visit neighbors
## in ascending to_room_id order and process sorted source sets, so results are
## byte-identical across runs. Shared by FactionIdentifier (species components,
## awareness) and TerritoryAssigner (multi-source flood-fill, bridge edges).


## Breadth-first distances (in rooms) from a set of source rooms.
## [param blocked_kinds] edge kinds are never traversed.
## [param allowed_rooms] (a { room_id: true } set) restricts which rooms may be
## ENTERED; empty ⇒ all rooms allowed. Sources are always seeded.
## Returns { room_id: int -> distance: int } (source rooms are distance 0).
static func bfs(input: DungeonFactionInput, sources: Array, blocked_kinds: Array,
		allowed_rooms: Dictionary) -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array[int] = []
	var sorted_sources: Array = sources.duplicate()
	sorted_sources.sort()
	for s in sorted_sources:
		if not dist.has(s):
			dist[s] = 0
			queue.append(int(s))
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var room: DungeonFactionRoomInput = input.get_room(cur)
		if room == null:
			continue
		var sorted_edges: Array = _sorted_neighbors(room)
		for e in sorted_edges:
			if blocked_kinds.has(e.kind):
				continue
			var nxt: int = e.to_room_id
			if dist.has(nxt):
				continue
			if not allowed_rooms.is_empty() and not allowed_rooms.has(nxt):
				continue
			dist[nxt] = dist[cur] + 1
			queue.append(nxt)
	return dist


## Connected components over [param allowed_rooms] (a { room_id: true } set),
## never crossing [param blocked_kinds] edges. Returns an Array of Array[int],
## each inner array sorted ascending; the outer array ordered by each component's
## smallest room id.
static func connected_components(input: DungeonFactionInput, allowed_rooms: Dictionary,
		blocked_kinds: Array) -> Array:
	var seen: Dictionary = {}
	var components: Array = []
	var room_ids: Array = allowed_rooms.keys()
	room_ids.sort()
	for rid in room_ids:
		if seen.has(rid):
			continue
		var comp_dist: Dictionary = bfs(input, [rid], blocked_kinds, allowed_rooms)
		var comp: Array[int] = []
		for r in comp_dist.keys():
			seen[r] = true
			comp.append(int(r))
		comp.sort()
		components.append(comp)
	components.sort_custom(func(a, b): return a[0] < b[0])
	return components


## True if ANY room in [param b_rooms] is reachable from [param a_rooms] without
## crossing a strong-boundary edge AND across ≤ [param max_unclaimed] unclaimed
## rooms (§5.2 step 1 awareness). [param claimed] is a { room_id: true } set of
## rooms owned by SOME faction; rooms not in it count as unclaimed along the path.
static func is_aware(input: DungeonFactionInput, a_rooms: Array, b_rooms: Array,
		claimed: Dictionary, max_unclaimed: int) -> bool:
	# BFS where the cost accumulated is the number of unclaimed rooms entered.
	# We do a 0/1-style BFS: entering a claimed room adds 0, unclaimed adds 1.
	var b_set: Dictionary = {}
	for r in b_rooms:
		b_set[int(r)] = true
	var best: Dictionary = {}                 # room_id -> min unclaimed-count to reach
	# 0-1 BFS: entering a CLAIMED room costs 0 (push to the FRONT), an unclaimed room
	# costs 1 (push to the BACK). The deque then pops in nondecreasing unclaimed-count
	# with no per-pop sort — O(V+E) instead of the old O(V^2 log V) resort-per-pop. The
	# min-cost per room (hence the boolean result) is identical to the Dijkstra it
	# replaces; determinism is preserved (neighbors visited in sorted to_room_id order).
	var deque: Array = []                     # entries: [unclaimed_count, room_id]
	var sorted_sources: Array = a_rooms.duplicate()
	sorted_sources.sort()
	for s in sorted_sources:
		best[int(s)] = 0
		deque.append([0, int(s)])
	while not deque.is_empty():
		var top: Array = deque.pop_front()
		var cost: int = top[0]
		var cur: int = top[1]
		if int(best.get(cur, 999999)) < cost:
			continue
		if b_set.has(cur) and cost <= max_unclaimed:
			return true
		var room: DungeonFactionRoomInput = input.get_room(cur)
		if room == null:
			continue
		for e in _sorted_neighbors(room):
			if DungeonFactionEdge.STRONG_BOUNDARY_KINDS.has(e.kind):
				continue
			var nxt: int = e.to_room_id
			var add: int = 0 if claimed.has(nxt) else 1
			var ncost: int = cost + add
			if ncost < int(best.get(nxt, 999999)):
				best[nxt] = ncost
				if add == 0:
					deque.push_front([ncost, nxt])
				else:
					deque.append([ncost, nxt])
	return false


## Bridge edges of the room graph (§4.3.1 / §13.2): edges whose removal
## disconnects the graph. Structural — every edge counts regardless of kind.
## Returns an Array of [a, b] pairs with a < b.
static func bridge_edges(input: DungeonFactionInput) -> Array:
	var bridges: Array = []
	var visited: Dictionary = {}
	var disc: Dictionary = {}
	var low: Dictionary = {}
	var timer: Array[int] = [0]
	var all_ids: Array = input.sorted_room_ids()
	for rid in all_ids:
		if not visited.has(rid):
			_bridge_dfs(input, int(rid), -1, visited, disc, low, timer, bridges)
	return bridges


static func _bridge_dfs(input: DungeonFactionInput, u: int, parent: int,
		visited: Dictionary, disc: Dictionary, low: Dictionary, timer: Array,
		bridges: Array) -> void:
	visited[u] = true
	disc[u] = timer[0]
	low[u] = timer[0]
	timer[0] += 1
	var room: DungeonFactionRoomInput = input.get_room(u)
	if room == null:
		return
	var parent_edge_used: bool = false
	for e in _sorted_neighbors(room):
		var v: int = e.to_room_id
		if not input.has_room(v):
			continue
		if v == parent and not parent_edge_used:
			# Skip the single edge back to parent once (handles multigraph safely).
			parent_edge_used = true
			continue
		if visited.has(v):
			low[u] = min(low[u], disc[v])
		else:
			_bridge_dfs(input, v, u, visited, disc, low, timer, bridges)
			low[u] = min(low[u], low[v])
			if low[v] > disc[u]:
				var a: int = min(u, v)
				var b: int = max(u, v)
				var pair: Array = [a, b]
				if not bridges.has(pair):
					bridges.append(pair)


## Neighbor edges of a room, sorted ascending by to_room_id (determinism).
static func _sorted_neighbors(room: DungeonFactionRoomInput) -> Array:
	var edges: Array = room.neighbors.duplicate()
	edges.sort_custom(func(a, b): return a.to_room_id < b.to_room_id)
	return edges
