class_name DungeonEncounterSpawner
extends RefCounted

## Spawns encounter monsters on an existing dungeon TacticalMapData.
##
## ACKS dungeon encounters use 2d6 × 10 feet encounter distance.
## At 5 feet per cell that is 2d6 × 2 cells of Chebyshev distance.
##
## Placement rules (per design brief):
##   1. Roll 2d6 × 2 cells encounter distance.
##   2. Find eligible passable unoccupied cells at exactly that distance
##      (Chebyshev) from the nearest party member.
##   3. If none found, decrement distance by 1 and retry until a cell is found.
##   4. Place the first (lead) monster at the chosen cell.
##   5. Cluster remaining monsters behind the lead — cells that increase
##      Chebyshev distance from the party centroid.
##   6. If behind is insufficient, fill in-front (toward party) to fit all.
##
## Returns an Array[Dictionary] — one entry per monster placed:
##   { combatant_id, monster_data, grid_position }
## The caller (DungeonExploreState) builds the CombatRoster from this array.


const ENCOUNTER_DISTANCE_DICE := 2   ## 2d6 × 2 cells
const ENCOUNTER_DISTANCE_SIDES := 6
const FEET_TO_CELLS := 2             ## 10 ft / 5 ft per cell


## Spawn monsters for [param encounter_data] on [param map].
## [param party_positions]: current cell positions of all party members.
## [param dice_system]: DiceSystem autoload reference (passed to avoid autoload dependency).
## Returns array of placement dicts or empty array on failure.
func spawn_encounter(
		map: TacticalMapData,
		party_positions: Array[Vector2i],
		encounter_data: Dictionary,
		monster_registry,  # MonsterRegistry
		dice_system) -> Array[Dictionary]:

	if map == null or party_positions.is_empty():
		push_error("DungeonEncounterSpawner: no map or party positions")
		return []

	var count: int = encounter_data.get("number", 1)
	var monster_group: String = encounter_data.get("monster_group", "")
	if count <= 0 or monster_group.is_empty():
		return []

	# Roll encounter distance: 2d6 × 2 cells
	var distance_cells: int = _roll_encounter_distance(dice_system)

	# Party centroid for directional clustering
	var centroid := _compute_centroid(party_positions)

	# Find the lead spawn cell — try from rolled distance down to 1
	var lead_cell := _find_lead_cell(map, party_positions, distance_cells)
	if lead_cell == Vector2i(-1, -1):
		push_error("DungeonEncounterSpawner: no valid spawn cell found")
		return []

	# Collect all spawn cells: lead + clusters for remaining monsters
	var spawn_cells: Array[Vector2i] = [lead_cell]
	if count > 1:
		var extras := _cluster_monsters(map, lead_cell, centroid, count - 1)
		spawn_cells.append_array(extras)

	# Fallback: if clustering could not find enough cells, stack on lead cell
	while spawn_cells.size() < count:
		spawn_cells.append(lead_cell)

	# Retrieve monster data from registry
	var monster_data: Dictionary = {}
	if monster_registry != null and monster_registry.has_method("get_monster"):
		monster_data = monster_registry.get_monster(monster_group)
	if monster_data.is_empty():
		# Minimal fallback so combat can still start
		monster_data = {
			"id": monster_group,
			"name": monster_group.capitalize().replace("_", " "),
			"hd": "1",
			"hp_dice": "1d8",
			"ac": 12,
			"movement": 90,
			"attacks": [{"name": "attack", "damage": "1d6", "count": 1}],
		}

	# Build placement records
	var placements: Array[Dictionary] = []
	for i in range(min(count, spawn_cells.size())):
		var base_hp: int = _roll_hp(monster_data.get("hp_dice", "1d8"), dice_system)
		placements.append({
			"combatant_id": "%s_%d" % [monster_group, i + 1],
			"monster_data": monster_data.duplicate(),
			"grid_position": spawn_cells[i],
			"rolled_hp": base_hp,
			"group_id": monster_group,
		})

	return placements


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _roll_encounter_distance(dice_system) -> int:
	## 2d6 × 2 cells (= 2d6 × 10 ft at 5 ft/cell)
	var total := 0
	for _i in range(ENCOUNTER_DISTANCE_DICE):
		if dice_system != null and dice_system.has_method("roll_digital"):
			total += dice_system.roll_digital(ENCOUNTER_DISTANCE_SIDES, 1, 0,
				"dungeon_encounter_distance").modified_total
		else:
			total += randi_range(1, ENCOUNTER_DISTANCE_SIDES)
	return total * FEET_TO_CELLS


func _compute_centroid(positions: Array[Vector2i]) -> Vector2i:
	if positions.is_empty():
		return Vector2i.ZERO
	var sum := Vector2i.ZERO
	for p in positions:
		sum += p
	return Vector2i(sum.x / positions.size(), sum.y / positions.size())


func _find_lead_cell(
		map: TacticalMapData,
		party_positions: Array[Vector2i],
		max_distance: int) -> Vector2i:
	## Try distances from max_distance down to 1 until an eligible cell is found.
	for dist in range(max_distance, 0, -1):
		var candidates := _cells_at_distance(map, party_positions, dist)
		if not candidates.is_empty():
			# Pick a random eligible cell
			return candidates[randi() % candidates.size()]
	return Vector2i(-1, -1)


func _cells_at_distance(
		map: TacticalMapData,
		party_positions: Array[Vector2i],
		distance: int) -> Array[Vector2i]:
	## Returns passable, unoccupied map cells whose Chebyshev distance from
	## the nearest party member equals exactly [param distance].
	var result: Array[Vector2i] = []
	for cell_pos in map._cells.keys():
		if not map.is_passable(cell_pos):
			continue
		if not map.get_entities_at(cell_pos).is_empty():
			continue
		var min_dist := _min_chebyshev(cell_pos, party_positions)
		if min_dist == distance:
			result.append(cell_pos)
	return result


func _min_chebyshev(pos: Vector2i, targets: Array[Vector2i]) -> int:
	var best := 99999
	for t in targets:
		var d := IsometricGrid.chebyshev_distance(pos, t)
		if d < best:
			best = d
	return best


func _cluster_monsters(
		map: TacticalMapData,
		anchor: Vector2i,
		party_centroid: Vector2i,
		count: int) -> Array[Vector2i]:
	## Find [param count] additional cells near [param anchor], preferring cells
	## farther from the party (behind the lead monster).
	var result: Array[Vector2i] = []
	var occupied: Array[Vector2i] = [anchor]
	var radius := 1
	var attempts := 0

	while result.size() < count and attempts < 50:
		attempts += 1
		# Collect candidate cells at increasing BFS radius from anchor
		var candidates: Array[Vector2i] = []
		for pos in map._cells.keys():
			if not map.is_passable(pos):
				continue
			if pos in occupied:
				continue
			if not map.get_entities_at(pos).is_empty():
				continue
			if IsometricGrid.chebyshev_distance(anchor, pos) == radius:
				candidates.append(pos)

		# Sort by descending distance from party centroid (behind = farther)
		candidates.sort_custom(func(a, b):
			return IsometricGrid.chebyshev_distance(a, party_centroid) > \
				   IsometricGrid.chebyshev_distance(b, party_centroid)
		)

		for c in candidates:
			if result.size() >= count:
				break
			result.append(c)
			occupied.append(c)

		radius += 1
		if radius > 12:
			break

	return result


func _roll_hp(hp_dice: String, dice_system) -> int:
	## Parse "NdM" dice notation and roll.
	var parts := hp_dice.split("d")
	if parts.size() != 2:
		return 4  # fallback
	var num := int(parts[0])
	var sides := int(parts[1])
	if num <= 0 or sides <= 0:
		return 4
	var total := 0
	for _i in range(num):
		if dice_system != null and dice_system.has_method("roll_digital"):
			total += dice_system.roll_digital(sides, 1, 0, "monster_hp").modified_total
		else:
			total += randi_range(1, sides)
	return total
