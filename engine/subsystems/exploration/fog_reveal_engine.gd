class_name FogRevealEngine
extends RefCounted

## Computes the set of cells that are currently lit on a voxel dungeon map,
## given each party member's position and visibility radius (light source +
## darkvision). Replaces the room-scoped reveal that the dungeon controller
## used pre-batch-3 — fog now follows light + LOS instead of room
## membership.
##
## See gdd-dungeon-map-ui.md §10 / §10.x for the visibility-state contract:
##   - "visible"   — currently lit AND in line of sight of a light source
##   - "explored"  — was visible at some past moment but no longer lit
##   - "hidden"    — never lit
##
## Pure logic, all-static. No globals, no signals. Callers feed in a
## VoxelMapData and a `{entity_id: {pos, radius}}` map; the engine returns
## a set (Dictionary[Vector3i -> true]) of currently lit cells. The dungeon
## controller is responsible for translating that into fog-state writes.


## Returns a Dictionary keyed by Vector3i (set semantics) of cells that any
## party member currently illuminates. Each member contributes their own
## cell unconditionally — even with no light source, the player can see their
## own portraits in the world (v1 pitch-darkness simplification per the
## smoke-test plan).
##
## [param members]: Dictionary[entity_id: String, value: Dictionary] where
##   value carries:
##     - "pos": Vector3i      — the member's grid position
##     - "radius": int        — light + darkvision in cells (Chebyshev)
##
## Members with pos == Vector3i(-1,-1,-1) are skipped (off-map).
static func compute_visible_cells(
		map: VoxelMapData,
		members: Dictionary) -> Dictionary:
	var lit: Dictionary = {}
	if map == null:
		return lit

	for entity_id in members.keys():
		var entry: Dictionary = members[entity_id]
		var pos: Vector3i = entry.get("pos", Vector3i(-1, -1, -1))
		if pos == Vector3i(-1, -1, -1):
			continue

		# Always reveal the member's own cell — even in pitch darkness the
		# player needs to see their own piece on the board.
		if map.has_cell(pos):
			lit[pos] = true

		var radius: int = int(entry.get("radius", 0))
		if radius <= 0:
			continue

		# Chebyshev box around `pos`, LOS-checked. Same level only — vertical
		# light leaks through stairs are out of scope for v1.
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if dx == 0 and dy == 0:
					continue
				var target := Vector3i(pos.x + dx, pos.y + dy, pos.z)
				if not map.has_cell(target):
					continue
				if VoxelLOS.has_los(map, pos, target):
					lit[target] = true

	return lit
