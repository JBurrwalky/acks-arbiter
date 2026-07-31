class_name BattleMapValidator
extends RefCounted

## Reachability analysis for generated battle maps
## (gdd-combat-map-generation.md §7.5). Pure analysis — the generator owns all
## map mutation (corridor carving, ramp notching); this class only answers
## "what can a ground walker reach?" using the project's single movement
## predicate (MovementRules.is_ground_step_open), so the guarantee it validates
## is exactly the rule combat pathfinding runs on: no climbing throws, no
## damaging falls, no deep water on any spawn-relevant route.


## Returns true when [param pos] is a standable walker surface: an air cell
## with support (dry ground, a bridge deck, or wadeable shallow water). Deep
## water and lava (liquid) are not standable.
static func is_standable_surface(map: VoxelMapData, pos: Vector3i) -> bool:
	if not map.has_cell(pos):
		return false
	var cell := map.get_cell(pos)
	if cell.solidity != "air":
		return false
	if not cell.is_passable_by_walker():
		return false
	return FallingResolver.has_support(map, pos)


## Flood-fills the walkable surface graph and returns:
##   surfaces:   Array[Vector3i] — every standable surface cell
##   components: Array[Array[Vector3i]] — connected components, LARGEST FIRST
##   cell_component: Dictionary[Vector3i -> int] — component index per cell
## Edges are legal ground steps (MovementRules.is_ground_step_open): same-level
## or ±1 natural-slope moves onto supported air. Each column contributes its
## surface cell only (surface_level_at), which is the walker-relevant graph.
static func analyze(map: VoxelMapData) -> Dictionary:
	# Precompute each column's surface once (Vector2i -> Vector3i) — the flood
	# fill touches every cell's 8 neighbors and per-neighbor column scans via
	# surface_level_at would dominate the runtime.
	var column_surface: Dictionary = {}
	var surfaces: Array[Vector3i] = []
	var surface_set: Dictionary = {}
	for pos: Vector3i in map.get_all_positions():
		var cell := map.get_cell(pos)
		if cell.solidity != "air":
			continue
		var col2 := Vector2i(pos.x, pos.y)
		if not column_surface.has(col2):
			column_surface[col2] = map.surface_level_at(pos.x, pos.y)
		# Only the column's surface cell participates (skip bridge-shadowed
		# water cells etc. — surface_level_at picks the topmost).
		if int(column_surface[col2]) != pos.z:
			continue
		if not is_standable_surface(map, pos):
			continue
		surfaces.append(pos)
		surface_set[pos] = true

	var cell_component: Dictionary = {}
	var raw_components: Array = []
	for start: Vector3i in surfaces:
		if cell_component.has(start):
			continue
		var comp_index: int = raw_components.size()
		var comp: Array[Vector3i] = []
		var queue: Array[Vector3i] = [start]
		cell_component[start] = comp_index
		while not queue.is_empty():
			var current: Vector3i = queue.pop_front()
			comp.append(current)
			for offset: Vector2i in VoxelGrid.DIRECTION_OFFSETS:
				var ncol2 := Vector2i(current.x + offset.x, current.y + offset.y)
				if not column_surface.has(ncol2):
					continue
				var npos := Vector3i(ncol2.x, ncol2.y, int(column_surface[ncol2]))
				if cell_component.has(npos) or not surface_set.has(npos):
					continue
				if not MovementRules.is_ground_step_open(map, current, npos):
					continue
				cell_component[npos] = comp_index
				queue.append(npos)
		raw_components.append(comp)

	# Sort components largest-first and remap indices to the sorted order.
	raw_components.sort_custom(func(a, b): return a.size() > b.size())
	var remapped: Dictionary = {}
	for i in range(raw_components.size()):
		for c: Vector3i in raw_components[i]:
			remapped[c] = i

	return {
		"surfaces": surfaces,
		"components": raw_components,
		"cell_component": remapped,
	}


## Stamps each surface cell's component index (largest component = 0) into
## VoxelCell.zone_index — the battle-map reading of that field
## (gdd-combat-map-generation.md §9.1). Downstream AI answers "can A ground-walk
## to B?" by comparing zone_index values.
static func stamp_zone_indices(map: VoxelMapData, analysis: Dictionary) -> void:
	var cell_component: Dictionary = analysis["cell_component"]
	for pos: Vector3i in cell_component:
		map.get_cell(pos).zone_index = cell_component[pos]
