extends "res://tests/test_suite_base.gd"

## Layout-navigability tests per `gdd-dungeon-layout.md` §10.2 / V1 GDD §9.1.
##
## Generates many seeded Wizard's Dungeons across all 4 sizes and verifies
## that EVERY detected room is reachable from a stair (with all doors treated
## as passable). This catches the "isolated room" regression — a room
## generated without any sill that connects to a corridor.
##
## The check uses the same algorithm as `DungeonLayoutGenerator._check_layout_navigability`
## so a failure here corresponds 1:1 to a generation that would log a warning
## in production.


const _NAVIGABILITY_SEEDS: Array[int] = [
	1, 2, 3, 5, 8, 13, 21, 34, 55, 89,  # Fibonacci — arbitrary but reproducible
	100, 200, 300, 400, 500,
	1000, 1234, 5678, 9999,
]


func run_all_tests() -> void:
	test_lair_navigability_across_seeds()
	test_small_navigability_across_seeds()
	test_medium_navigability_across_seeds()
	# Large is expensive; spot-check a few seeds only.
	test_large_navigability_spot_check()
	if not has_failures():
		print("DungeonLayoutNavigability: all tests passed.")


# ---------------------------------------------------------------------------
# Per-size sweeps
# ---------------------------------------------------------------------------

func test_lair_navigability_across_seeds() -> void:
	_sweep_seeds("lair", _NAVIGABILITY_SEEDS)


func test_small_navigability_across_seeds() -> void:
	_sweep_seeds("small", _NAVIGABILITY_SEEDS)


func test_medium_navigability_across_seeds() -> void:
	_sweep_seeds("medium", _NAVIGABILITY_SEEDS)


func test_large_navigability_spot_check() -> void:
	# Just 3 seeds for large — generation is slower and the algorithm is
	# the same as medium, so additional coverage gives diminishing returns.
	_sweep_seeds("large", [1, 100, 9999])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _sweep_seeds(size: String, seeds: Array) -> void:
	for seed in seeds:
		var layout: DungeonLayout = _generate(size, seed)
		check(layout != null, "%s/seed=%d: generation returned null" % [size, seed])
		if layout == null:
			continue
		check(layout.rooms.size() > 0,
			"%s/seed=%d: 0 rooms detected" % [size, seed])
		if layout.rooms.is_empty():
			continue
		var unreachable: Array[int] = _unreachable_rooms(layout)
		check(unreachable.is_empty(),
			"%s/seed=%d: %d rooms unreachable: %s"
				% [size, seed, unreachable.size(), str(unreachable)])


func _generate(size: String, seed: int) -> DungeonLayout:
	var req := DungeonLayoutRequest.new()
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = size
	req.level_number = 1
	req.seed = seed
	req.stairs_up = 1
	req.stairs_down = 1
	req.is_entrance_floor = true
	return DungeonLayoutGenerator.generate(req)


## BFS from any stair across passable + door cells. Returns the IDs of any
## rooms NOT reached.
func _unreachable_rooms(layout: DungeonLayout) -> Array[int]:
	var unreachable: Array[int] = []
	# Start from a stair (or fall back to the first room cell if no stairs).
	var start: Vector2i = Vector2i(-1, -1)
	if not layout.stairs.is_empty():
		start = layout.stairs[0].position
	elif not layout.rooms.is_empty():
		start = layout.rooms[0].cells[0]
	if start.x < 0:
		# Truly degenerate — every room counts as unreachable.
		for r in layout.rooms:
			unreachable.append(r.id)
		return unreachable
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dir in dirs:
			var n: Vector2i = cur + dir
			if visited.has(n):
				continue
			if n.x < 0 or n.y < 0 or n.x >= layout.grid_width or n.y >= layout.grid_height:
				continue
			var cd: DungeonCellData = layout.cells[n.x][n.y]
			if cd == null:
				continue
			# Treat doors as passable for structural navigability.
			if not cd.passable and not cd.is_door():
				continue
			visited[n] = true
			queue.append(n)
	for room in layout.rooms:
		var any_reached: bool = false
		for c in room.cells:
			if visited.has(c):
				any_reached = true
				break
		if not any_reached:
			unreachable.append(room.id)
	return unreachable
