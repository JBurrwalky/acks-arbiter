class_name FormationManager
extends RefCounted

## Manages party formation layout for dungeon exploration.
##
## Reads PartyData.members formation grid (5 wide × 12 deep) and provides:
## - Preset template application (auto-sorts by AC desc, HP desc tiebreak)
## - Mapping formation grid to dungeon cells relative to a leader position
## - Collapse logic when corridors are too narrow for the full formation
## - Group-move computation to maintain formation during movement
##
## Presets:
##   Column — single file (1 wide)
##   DoubleColumn — pairs (2 wide)
##   Line — side by side (N wide, 1 deep)
##   DoubleLine — N wide, 2 deep
##   Wedge — V-shape


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PRESET_COLUMN := "column"
const PRESET_DOUBLE_COLUMN := "double_column"
const PRESET_LINE := "line"
const PRESET_DOUBLE_LINE := "double_line"
const PRESET_WEDGE := "wedge"

## All available presets in UI display order.
const PRESETS := [PRESET_COLUMN, PRESET_DOUBLE_COLUMN, PRESET_LINE, PRESET_DOUBLE_LINE, PRESET_WEDGE]


# ---------------------------------------------------------------------------
# Preset application
# ---------------------------------------------------------------------------

## Apply a formation preset, sorting members by AC desc then HP desc.
## Updates formation_col/formation_row on each PartyData member entry.
func apply_preset(
		template_name: String,
		party_data: PartyData,
		character_data_list: Array) -> void:
	if party_data == null or character_data_list.is_empty():
		return

	# Build sortable list: {character_id, ac, hp}
	var sortable: Array = []
	for cd in character_data_list:
		if cd.is_dead or not cd.is_active:
			continue
		sortable.append({
			"character_id": cd.id,
			"ac": cd.get_effective_ac(),
			"hp": cd.hp_max,
		})

	# Sort by AC descending, HP descending as tiebreak
	sortable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["ac"] != b["ac"]:
			return a["ac"] > b["ac"]
		return a["hp"] > b["hp"]
	)

	var count := sortable.size()
	if count == 0:
		return

	# Generate positions based on template
	var positions: Array = []  # Array of {col, row}
	match template_name:
		PRESET_COLUMN:
			positions = _layout_column(count)
		PRESET_DOUBLE_COLUMN:
			positions = _layout_double_column(count)
		PRESET_LINE:
			positions = _layout_line(count)
		PRESET_DOUBLE_LINE:
			positions = _layout_double_line(count)
		PRESET_WEDGE:
			positions = _layout_wedge(count)
		_:
			positions = _layout_column(count)

	# Assign positions to sorted members
	for i in range(count):
		var cid: String = sortable[i]["character_id"]
		var pos: Dictionary = positions[i] if i < positions.size() else {"col": 0, "row": i}
		party_data.set_formation_pos(cid, pos["col"], pos["row"])


# ---------------------------------------------------------------------------
# Dungeon cell mapping (voxel)
# ---------------------------------------------------------------------------

## Maps the formation grid to voxel cells relative to [param leader_pos] on
## the leader's level. Returns {character_id: Vector3i} for each placed member.
##
## Collapse chain: full formation → double column → single column → stack on
## leader. Applies preset changes to party_data during collapse then restores
## the original formation grid before returning, so the caller's preset choice
## survives.
##
## Group movement is single-level: followers stay on [param leader_pos].z.
func compute_dungeon_positions_3d(
		leader_pos: Vector3i,
		party_data: PartyData,
		vmap: VoxelMapData) -> Dictionary:
	if party_data == null or vmap == null:
		return {}
	var marching := party_data.get_marching_order()
	if marching.is_empty():
		return {}

	# Attempt full formation placement.
	var result := _place_formation_3d(leader_pos, party_data, vmap, marching)
	if result.size() == marching.size():
		return result

	# Back up the active formation so we can restore after collapse.
	var backup := _backup_formation(party_data, marching)

	# Collapse to double column.
	apply_preset(PRESET_DOUBLE_COLUMN, party_data, _get_active_characters(party_data))
	result = _place_formation_3d(leader_pos, party_data, vmap, marching)
	if result.size() == marching.size():
		_restore_formation(party_data, backup)
		return result

	# Collapse to single column.
	apply_preset(PRESET_COLUMN, party_data, _get_active_characters(party_data))
	result = _place_formation_3d(leader_pos, party_data, vmap, marching)

	# Anyone still unplaced stacks on the leader's cell.
	for cid in marching:
		if not result.has(cid):
			result[cid] = leader_pos

	_restore_formation(party_data, backup)
	return result


## Compute move orders for all members when the leader moves to [param leader_target].
## Maintains formation offsets. Returns an Array of {entity_id, target_pos: Vector3i}.
func compute_group_move_3d(
		leader_target: Vector3i,
		party_data: PartyData,
		vmap: VoxelMapData) -> Array:
	var positions := compute_dungeon_positions_3d(leader_target, party_data, vmap)
	var result: Array = []
	for cid in positions:
		result.append({"entity_id": cid, "target_pos": positions[cid]})
	return result


# ---------------------------------------------------------------------------
# Formation placement (voxel) — private
# ---------------------------------------------------------------------------

func _place_formation_3d(
		leader_pos: Vector3i,
		party_data: PartyData,
		vmap: VoxelMapData,
		marching_order: Array) -> Dictionary:
	## Place each marching member at their formation offset from the leader.
	## Returns {character_id: Vector3i} for successfully placed members.
	## Falls back to 8-neighbor search when the exact offset is blocked;
	## returns with the member unplaced if no adjacent alternative exists.
	var result: Dictionary = {}
	var occupied: Array = []

	# Pre-populate with positions of entities already on the map that are NOT
	# in this placement batch — prevents stacking on non-party entities.
	for eid in vmap.entity_positions:
		if eid not in marching_order:
			var epos: Vector3i = vmap.entity_positions[eid]
			if epos not in occupied:
				occupied.append(epos)

	if marching_order.is_empty():
		return result

	var leader_id: String = marching_order[0]
	var leader_form := party_data.get_formation_pos(leader_id)

	for cid in marching_order:
		var form_pos := party_data.get_formation_pos(cid)
		if form_pos.x == PartyData.UNASSIGNED:
			# Unassigned member — stack on leader.
			if leader_pos not in occupied:
				result[cid] = leader_pos
				occupied.append(leader_pos)
			continue

		# Compute voxel cell offset from leader's formation position.
		var offset_x: int = form_pos.x - leader_form.x
		var offset_y: int = form_pos.y - leader_form.y
		var target := Vector3i(leader_pos.x + offset_x, leader_pos.y + offset_y, leader_pos.z)

		if vmap.has_cell(target) and vmap.is_passable(target) and target not in occupied:
			result[cid] = target
			occupied.append(target)
			continue

		# Fallback: try 8 same-level neighbors of the intended offset.
		var placed := false
		for neighbor: Vector3i in VoxelGrid.get_neighbors_2d(target):
			if not vmap.has_cell(neighbor):
				continue
			if not vmap.is_passable(neighbor):
				continue
			if neighbor in occupied:
				continue
			result[cid] = neighbor
			occupied.append(neighbor)
			placed = true
			break
		# If nothing adjacent worked, leave the member unplaced; caller handles
		# the collapse chain.

	return result


func _backup_formation(party_data: PartyData, marching_order: Array) -> Array:
	var backup: Array = []
	for cid in marching_order:
		var pos := party_data.get_formation_pos(cid)
		backup.append({"character_id": cid, "col": pos.x, "row": pos.y})
	return backup


func _restore_formation(party_data: PartyData, backup: Array) -> void:
	for entry in backup:
		party_data.set_formation_pos(entry["character_id"], entry["col"], entry["row"])


func _get_active_characters(party_data: PartyData) -> Array:
	var result: Array = []
	for cd in party_data.character_data:
		if not cd.is_dead and cd.is_active:
			result.append(cd)
	return result


# ---------------------------------------------------------------------------
# Layout generators — return Array of {col, row}
# ---------------------------------------------------------------------------

func _layout_column(count: int) -> Array:
	## Single file: col=0, row 0..N-1
	## Highest AC at front (row 0), lowest in middle
	var positions: Array = []
	for i in range(count):
		positions.append({"col": 0, "row": i})
	return positions


func _layout_double_column(count: int) -> Array:
	## Pairs: row 0 has cols 0-1, row 1 has cols 0-1, etc.
	## Highest AC at front corners
	var positions: Array = []
	var row := 0
	var placed := 0
	while placed < count:
		positions.append({"col": 0, "row": row})
		placed += 1
		if placed < count:
			positions.append({"col": 1, "row": row})
			placed += 1
		row += 1
	return positions


func _layout_line(count: int) -> Array:
	## Side by side: row=0, col 0..N-1
	## Highest AC at edges (col 0 and max), lowest center
	var positions: Array = []
	# Interleave: left edge, right edge, next left, next right, ...
	var left := 0
	var right := count - 1
	var slots: Array = []
	slots.resize(count)
	var idx := 0
	while left <= right:
		slots[left] = idx
		idx += 1
		if left != right:
			slots[right] = idx
			idx += 1
		left += 1
		right -= 1
	# Invert: slots[col] = sort_index → we need sort_index → col
	var col_for_rank: Array = []
	col_for_rank.resize(count)
	for col in range(count):
		col_for_rank[slots[col]] = col
	for i in range(count):
		positions.append({"col": col_for_rank[i], "row": 0})
	return positions


func _layout_double_line(count: int) -> Array:
	## N wide, 2 deep. Front row = highest AC at corners; back row = lowest.
	var front_count := ceili(float(count) / 2.0)
	var back_count := count - front_count
	var positions: Array = []

	# Front row — interleave from edges
	var front := _layout_line(front_count)
	for p in front:
		positions.append({"col": p["col"], "row": 0})

	# Back row — remaining members, center placement
	var back := _layout_line(back_count) if back_count > 0 else []
	for p in back:
		positions.append({"col": p["col"], "row": 1})

	return positions


func _layout_wedge(count: int) -> Array:
	## V-shape: point at front, expanding rearward.
	## Highest AC at point and outer edges, lowest center-rear.
	var positions: Array = []
	if count == 0:
		return positions

	# Point: row 0, col 0
	positions.append({"col": 0, "row": 0})
	if count == 1:
		return positions

	# Expand outward in a V pattern
	var row := 1
	var placed := 1
	while placed < count:
		# Left arm
		positions.append({"col": -row, "row": row})
		placed += 1
		if placed >= count:
			break
		# Right arm
		positions.append({"col": row, "row": row})
		placed += 1
		if placed >= count:
			break
		# Fill between arms at this row if space remains
		for inner_col in range(-row + 1, row):
			if placed >= count:
				break
			positions.append({"col": inner_col, "row": row})
			placed += 1
		row += 1

	return positions
