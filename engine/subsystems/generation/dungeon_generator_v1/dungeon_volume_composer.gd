class_name DungeonVolumeComposer
extends RefCounted

## DG-C3D.D — Vertical composition.
##
## The new heart of the contiguous 3D dungeon pipeline (gdd-dungeon-contiguous-3d.md
## §8 stage C). Takes the per-band 2D layouts (already carrying the vertical
## plan's reserved circulation / atrium rooms — DG-C3D.C) plus the whole-dungeon
## VerticalPlan (DG-C3D.B) and produces ONE contiguous VoxelMapData, the logical
## StairwellData connectors, the RoomZone stocking units, and updated RoomData.
##
## Steps, in order (§8 C1-C5):
##   C1. Stamp every band's rasterized cells into one VoxelMapData at its
##       walk/headroom voxel levels; solid-fill uncarved subterranean space;
##       cap the topmost band with a solid slab (§5.2 / C1).
##   C2. Carve connectors per §6 (straight / switchback / spiral / ramp): stepped
##       cells with direction suffixes, under-step solid fill, shaft/floor
##       openings, mid-landings, spiral shafts. Emit a StairwellData per
##       connector. NO door cells inside any run; every run traversable both
##       directions (§10.3 — composer emits, DG-C3D.E asserts).
##   C3. Carve atriums per §7: upper-band interior floor_type=none void,
##       balcony ring slabs, parapet cover_value, optional internal grand stair,
##       graceful degradation to a plain double-height hall when connectivity
##       fails (logged).
##   C4. Zone assignment: flood-fill walkable regions per (room, band) at the
##       band's WALK level -> RoomZone records + zone_index stamped on cells.
##       Disconnected same-band galleries get distinct zones.
##   C5. Floor-integrity pass: every walkable band-k+1 cell above open band-k
##       space has a floor unless its column is a registered opening; every
##       registered opening has none. Violations ABORT (never ship an undeclared
##       hole).
##
## PARALLEL PATH — this stage is NOT yet called by DungeonGeneratorV1.generate()
## (that stays legacy until the DG-C3D.F cutover). Its output is parked on the
## DungeonGeneratorResultV1 dormant slots (composed_volume / stairwells) so B-E
## tests can inspect it without changing the public result contract.
##
## RNG: composition introduces NO new random stream. Every geometric choice is
## derived deterministically from the VerticalPlan (which already consumed its
## own namespaced stream in DG-C3D.B, conventions §118). generation_seed is
## carried through only for the volume's reproducibility stamp.


# ---------------------------------------------------------------------------
# Geometry constants
# ---------------------------------------------------------------------------

## Voxel levels a band spans above its walk level (the headroom cell).
const HEADROOM_OFFSET: int = 1

## Global room-id stride per band slot: global_id = band_slot * STRIDE + local_id.
## Room ids are per-band-local out of the layout generator; the composed volume
## needs dungeon-unique ids (§9.1). 1000 dwarfs any per-band room count (Large
## targets 40).
const ROOM_ID_STRIDE: int = 1000

## Parapet cover value stamped on balcony edge cells overlooking a void (§7.1).
const PARAPET_COVER: int = 1

## Wall/rock feature emitted for solid fill (the renderer treats "wall_stone" as
## impassable solid stone — the same mapping the retired 2D serializer used).
const SOLID_FEATURE: String = "wall_stone"


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

## Everything the composition stage emits. DG-C3D.F assigns volume ->
## result.composed_volume and stairwells -> result.stairwells; rooms/zones feed
## the per-zone stocker.
class ComposeResult:
	extends RefCounted
	var ok: bool = true
	var error: String = ""
	var warnings: Array[String] = []
	var volume: VoxelMapData = null
	var stairwells: Array[StairwellData] = []
	var zones: Array[RoomZone] = []
	var rooms: Array[DungeonRoomData] = []
	## Door records for the composed-volume validator / key-lever placer
	## (DG-C3D.E): the VoxelCell carries door_state/type but NOT door_material,
	## so the material (bashable vs key-needing) and the dungeon-unique connected
	## room ids travel here. Entries: {cell: Vector3i, type, is_secret,
	## material, band, connects: Array[int]}.
	var doors: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Compose one contiguous volume from the vertical [param plan] and the per-band
## [param band_layouts] (one DungeonLayout per band, any order; matched to bands
## by level_number). [param master_seed] stamps the volume for reproducibility;
## [param dungeon_id] names it. Returns a ComposeResult whose `ok` is false with
## a populated `error` when a floor-integrity violation is detected (never ship a
## hole nobody declared — §8 C5).
static func compose(
		plan: VerticalPlan,
		band_layouts: Array[DungeonLayout],
		master_seed: int,
		dungeon_id: String = "") -> ComposeResult:
	var result := ComposeResult.new()
	if plan == null:
		result.ok = false
		result.error = "DungeonVolumeComposer: null vertical plan."
		push_error(result.error)
		return result

	# Map floor_index -> layout and assign a 0-based band slot (plan order).
	var layout_by_floor: Dictionary = {}
	for layout in band_layouts:
		layout_by_floor[layout.level_number] = layout
	var slot_by_floor: Dictionary = {}
	for i in range(plan.bands.size()):
		slot_by_floor[plan.bands[i].floor_index] = i

	# Every planned band must have a layout (connectors need both ends).
	for band in plan.bands:
		if not layout_by_floor.has(band.floor_index):
			result.ok = false
			result.error = "DungeonVolumeComposer: no layout supplied for band floor_index %d." % band.floor_index
			push_error(result.error)
			return result

	var volume := VoxelMapData.new()
	volume.id = dungeon_id
	volume.name = dungeon_id
	volume.generation_seed = master_seed
	if not band_layouts.is_empty():
		volume.theme = band_layouts[0].dungeon_type
	result.volume = volume

	# Registered floor openings: Vector3i(col,row,level) at an upper band walk
	# level that MUST be floor_type "none" (stair shafts, atrium voids). The
	# floor-integrity pass (C5) checks against this set.
	var openings: Dictionary = {}

	# ---- C1: stamp every band -------------------------------------------------
	for band in plan.bands:
		var layout: DungeonLayout = layout_by_floor[band.floor_index]
		var slot: int = slot_by_floor[band.floor_index]
		_stamp_band(volume, layout, band.walk_level, slot, result.rooms, result.doors)

	_cap_top(volume, plan)

	# ---- C2: carve connectors -------------------------------------------------
	for connector in plan.connectors:
		var stairwell := _carve_connector(volume, connector, plan, slot_by_floor, layout_by_floor, openings)
		if stairwell != null:
			result.stairwells.append(stairwell)

	# ---- C3: carve atriums ----------------------------------------------------
	for atrium in plan.atriums:
		_carve_atrium(volume, atrium, plan, slot_by_floor, layout_by_floor, result, openings)

	# ---- C4: zone assignment --------------------------------------------------
	_assign_zones(volume, plan, slot_by_floor, result)

	# ---- C5: floor-integrity pass ---------------------------------------------
	var integrity := _check_floor_integrity(volume, plan, openings)
	if not integrity.is_empty():
		result.ok = false
		result.error = integrity
		push_error("DungeonVolumeComposer: floor-integrity violation — " + integrity)
		return result

	# Entrance + transition cell.
	for layout in band_layouts:
		if layout.is_entrance_floor and layout.entrance != Vector2i(-1, -1):
			var e_walk: int = plan.band_for_floor(layout.level_number).walk_level
			volume.entry_pos = Vector3i(layout.entrance.x, layout.entrance.y, e_walk)
			if volume.entry_pos not in volume.transition_cells:
				volume.transition_cells.append(volume.entry_pos)
				volume.transition_cell_labels[volume.entry_pos] = "Entrance"
			break

	return result


# ---------------------------------------------------------------------------
# C1 — band stamping
# ---------------------------------------------------------------------------

## Stamp one band's 2D layout into the volume at its walk + headroom levels,
## remapping the band's local room ids to dungeon-unique ids, and append the
## band's updated DungeonRoomData to [param out_rooms].
static func _stamp_band(
		volume: VoxelMapData,
		layout: DungeonLayout,
		walk: int,
		slot: int,
		out_rooms: Array[DungeonRoomData],
		out_doors: Array[Dictionary]) -> void:
	var headroom: int = walk + HEADROOM_OFFSET
	for x in range(layout.grid_width):
		for y in range(layout.grid_height):
			var cell: DungeonCellData = layout.cells[x][y]
			var global_room: int = _global_room_id(slot, cell.room_id)
			_stamp_column(volume, x, y, walk, headroom, cell, global_room)

	# Door overlays onto the walk-level cells (§8.1 door model, cell-based) + a
	# door record for the composed-volume validator / placer (DG-C3D.E): the
	# VoxelCell carries state/type but not material or the dungeon-unique
	# connected rooms, so those travel on the record.
	for d in layout.doors:
		var door: DungeonDoorData = d
		if door.position.x < 0 or door.position.y < 0:
			continue
		if door.position.x >= layout.grid_width or door.position.y >= layout.grid_height:
			continue
		var door_cell := Vector3i(door.position.x, door.position.y, walk)
		var wc: VoxelCell = volume.get_cell(door_cell)
		_apply_door(wc, door)
		volume.set_cell(wc.pos, wc)
		var connects_global: Array[int] = []
		for local_id in door.connects:
			connects_global.append(_global_room_id(slot, local_id))
		out_doors.append({
			"cell": door_cell,
			"type": door.type,
			"is_secret": door.is_secret,
			"material": door.door_material,
			"band": layout.level_number,
			"connects": connects_global,
		})

	# Updated RoomData (band / kind / global id). Zones are filled in C4.
	for r in layout.rooms:
		var room: DungeonRoomData = r
		var rd := DungeonRoomData.new()
		rd.id = _global_room_id(slot, room.id)
		rd.band = layout.level_number
		rd.kind = room.kind
		rd.original_purpose = room.original_purpose
		rd.current_purpose = room.current_purpose
		rd.bounds = room.bounds
		rd.center = room.center
		rd.area_sqft = room.area_sqft
		for c in room.cells:
			rd.cells.append(c)
		out_rooms.append(rd)


## Stamp one grid column (walk + headroom voxel cells) from a DungeonCellData.
static func _stamp_column(
		volume: VoxelMapData,
		col: int,
		row: int,
		walk: int,
		headroom: int,
		cell: DungeonCellData,
		global_room: int) -> void:
	var wc := VoxelCell.new()
	wc.col = col
	wc.row = row
	wc.level = walk
	var hc := VoxelCell.new()
	hc.col = col
	hc.row = row
	hc.level = headroom

	match cell.terrain_feature:
		DungeonCellData.FEATURE_OPEN, \
		DungeonCellData.FEATURE_DOOR, \
		DungeonCellData.FEATURE_DOOR_LOCKED, \
		DungeonCellData.FEATURE_DOOR_SECRET, \
		DungeonCellData.FEATURE_PORTCULLIS, \
		DungeonCellData.FEATURE_STAIRS_UP, \
		DungeonCellData.FEATURE_STAIRS_DOWN:
			# Open / door / legacy-stair cells become plain floor; the door
			# overlay pass refines door cells, and real stairs come from the
			# vertical plan (legacy layout stairs are ignored in this path).
			wc.solidity = "air"
			wc.feature = "open"
			wc.floor_type = "stone"
			wc.room_id = global_room
			wc.is_corridor = cell.is_corridor
			# Headroom: mid-room airspace.
			hc.solidity = "air"
			hc.feature = "open"
			hc.floor_type = "none"
		DungeonCellData.FEATURE_WALL_WOOD:
			_make_solid(wc, "wall_wood")
			_make_solid(hc, "wall_wood")
		_:
			# FEATURE_WALL_STONE, FEATURE_ROCK, and any unknown -> solid stone.
			_make_solid(wc, SOLID_FEATURE)
			_make_solid(hc, SOLID_FEATURE)

	volume.set_cell(wc.pos, wc)
	volume.set_cell(hc.pos, hc)


static func _make_solid(cell: VoxelCell, feature: String) -> void:
	cell.solidity = "solid"
	cell.feature = feature
	cell.floor_type = "none"
	cell.room_id = -1


## Overlay door state/type onto a walk-level cell (mirrors the legacy
## serializer's door overlay). The cell stays air/open floor; door_state governs
## passability.
static func _apply_door(cell: VoxelCell, door: DungeonDoorData) -> void:
	match door.type:
		DungeonDoorData.TYPE_ARCH:
			cell.door_state = "open"
			cell.door_type = "arch"
		DungeonDoorData.TYPE_UNLOCKED:
			cell.door_state = "closed"
			cell.door_type = "unlocked"
		DungeonDoorData.TYPE_LOCKED:
			cell.door_state = "locked"
			cell.door_type = "locked"
		DungeonDoorData.TYPE_TRAPPED:
			cell.door_state = "closed"
			cell.door_type = "trapped"
		DungeonDoorData.TYPE_PORTCULLIS:
			cell.door_state = "closed"
			cell.door_type = "portcullis"
		_:
			cell.door_state = "closed"
			cell.door_type = "unlocked"
	if door.is_secret:
		cell.door_type = "secret"
		cell.door_state = "closed"
		cell.door_detected = false


## Cap the topmost band with a solid slab so subterranean space above the
## shallowest floor is honest rock, not open sentinel air (§5.2 / §8 C1).
static func _cap_top(volume: VoxelMapData, plan: VerticalPlan) -> void:
	if plan.bands.is_empty():
		return
	var top_walk: int = plan.bands[0].walk_level
	var grid: Vector2i = plan.grid_size
	for band in plan.bands:
		top_walk = maxi(top_walk, band.walk_level)
	var cap_level: int = top_walk + HEADROOM_OFFSET + 1
	for x in range(grid.x):
		for y in range(grid.y):
			var cell := VoxelCell.new()
			_make_solid(cell, SOLID_FEATURE)
			volume.set_cell(Vector3i(x, y, cap_level), cell)


# ---------------------------------------------------------------------------
# C2 — connector carving
# ---------------------------------------------------------------------------

## Carve one planned connector's real geometry into the volume and return its
## StairwellData. WL = lower band walk; WU = WL + 2 (adjacent bands).
static func _carve_connector(
		volume: VoxelMapData,
		connector: VerticalPlan.ConnectorPlan,
		plan: VerticalPlan,
		slot_by_floor: Dictionary,
		layout_by_floor: Dictionary,
		openings: Dictionary) -> StairwellData:
	var lower_band: VerticalPlan.BandPlan = plan.band_for_floor(connector.lower_band)
	if lower_band == null:
		return null
	var wl: int = lower_band.walk_level
	var wu: int = wl + 2

	var sw := StairwellData.new()
	sw.stairwell_id = "%s_%d_%d_%d_%d" % [
		connector.type, connector.lower_band, connector.upper_band,
		connector.footprint.position.x, connector.footprint.position.y]
	sw.type = connector.type
	sw.lower_band = connector.lower_band
	sw.upper_band = connector.upper_band
	sw.width = connector.width
	# Cells on the lower band's two levels belong to the lower circulation room;
	# the upper landing belongs to the upper circulation room (so zoning + band
	# honesty stay per-band). StairwellData.room_id records the lower (owning) one.
	var lower_room: int = _connector_room_id(connector.footprint, connector.lower_band, slot_by_floor, layout_by_floor)
	var upper_room: int = _connector_room_id(connector.footprint, connector.upper_band, slot_by_floor, layout_by_floor)
	sw.room_id = lower_room

	match connector.type:
		StairwellData.TYPE_SPIRAL:
			_carve_spiral(volume, connector, wl, wu, sw, lower_room, upper_room)
		StairwellData.TYPE_SWITCHBACK:
			_carve_switchback(volume, connector, wl, wu, sw, lower_room, upper_room, openings)
		_:  # straight | ramp
			_carve_straight(volume, connector, wl, wu, sw, lower_room, upper_room, openings)
	return sw


## Global id of the circulation room occupying [param footprint] on
## [param band_floor], or -1 when no matching room is found.
static func _connector_room_id(
		footprint: Rect2i,
		band_floor: int,
		slot_by_floor: Dictionary,
		layout_by_floor: Dictionary) -> int:
	if not layout_by_floor.has(band_floor):
		return -1
	var layout: DungeonLayout = layout_by_floor[band_floor]
	var slot: int = slot_by_floor[band_floor]
	for r in layout.rooms:
		var room: DungeonRoomData = r
		if room.kind == DungeonRoomData.KIND_CIRCULATION and room.bounds == footprint:
			return _global_room_id(slot, room.id)
	return -1


## §6.1 straight run (§6.4 ramp — identical geometry, ramp_ feature). The run
## axis is the footprint's length-4 axis; both lanes carry the pattern. The run
## rises within the LOWER band (two stepped cells) and punches an open shaft
## through the upper floor — the upper footprint is open shaft except the top
## landing, so no isolated pocket forms and a flyer can rise the stairwell.
##
##   idx0 L  (WL floor)       bottom landing;   idx0 (WU) shaft void
##   idx1 A  (WL stair up)    lower step;        idx1 (WU) shaft void
##   idx2 B  (WL+1 stair up)  upper step;  under-B (WL) solid;  idx2 (WU) shaft void
##   idx3 T  (WU floor)       top landing;  under-T (WL, WL+1) solid
static func _carve_straight(
		volume: VoxelMapData,
		connector: VerticalPlan.ConnectorPlan,
		wl: int,
		wu: int,
		sw: StairwellData,
		lower_room: int,
		upper_room: int,
		openings: Dictionary) -> void:
	var rect: Rect2i = connector.footprint
	var is_ramp: bool = connector.type == StairwellData.TYPE_RAMP
	var step_floor: String = "dirt" if is_ramp else "stone"
	# Run axis = length-4 axis; lane axis = width-2 axis.
	var along_x: bool = rect.size.x >= rect.size.y
	var run: Vector2i = Vector2i(1, 0) if along_x else Vector2i(0, 1)
	var lane: Vector2i = Vector2i(0, 1) if along_x else Vector2i(1, 0)
	var run_len: int = rect.size.x if along_x else rect.size.y
	var lane_count: int = rect.size.y if along_x else rect.size.x
	var suffix: String = _suffix_for_delta(run)
	sw.run_cells.clear()

	for l in range(lane_count):
		var base: Vector2i = rect.position + lane * l
		var c0: Vector2i = base + run * 0
		var c1: Vector2i = base + run * 1
		var c2: Vector2i = base + run * 2
		var c3: Vector2i = base + run * mini(3, run_len - 1)
		var feat: String = ("ramp_" + suffix) if is_ramp else ("stairs_up_" + suffix)

		# idx0 L — bottom landing; open shaft above.
		_set_floor(volume, Vector3i(c0.x, c0.y, wl), "open", "stone", lower_room)
		_set_void(volume, Vector3i(c0.x, c0.y, wu), upper_room)
		openings[Vector3i(c0.x, c0.y, wu)] = true
		# idx1 A — lower step; open shaft above.
		_set_floor(volume, Vector3i(c1.x, c1.y, wl), feat, step_floor, lower_room)
		_set_void(volume, Vector3i(c1.x, c1.y, wu), upper_room)
		openings[Vector3i(c1.x, c1.y, wu)] = true
		# idx2 B — upper step at WL+1; under-B solid; shaft above at WU.
		_set_floor(volume, Vector3i(c2.x, c2.y, wl + 1), feat, step_floor, lower_room)
		_set_solid(volume, Vector3i(c2.x, c2.y, wl))
		_set_void(volume, Vector3i(c2.x, c2.y, wu), upper_room)
		openings[Vector3i(c2.x, c2.y, wu)] = true
		# idx3 T — top landing at WU; under-T solid on both lower levels.
		_set_floor(volume, Vector3i(c3.x, c3.y, wu), "open", "stone", upper_room)
		_set_solid(volume, Vector3i(c3.x, c3.y, wl))
		_set_solid(volume, Vector3i(c3.x, c3.y, wl + 1))

		sw.run_cells.append(Vector3i(c1.x, c1.y, wl))
		sw.run_cells.append(Vector3i(c2.x, c2.y, wl + 1))
		if l == 0:
			sw.bottom_cell = Vector3i(c0.x, c0.y, wl)
			sw.top_cell = Vector3i(c3.x, c3.y, wu)


## §6.2 switchback stairwell (L / U). Ascend one step (A, east) to a mid-landing
## at WL+1, turn south down column px+2, then ascend the second step (B, west) to
## the upper band. Footprint 3-wide (px..px+2) by h-deep (h = 2 for L, 3 for U).
##
##   L (px,   py,        WL)     bottom landing;  headroom (WL+1) air
##   A (px+1, py,        WL)     stairs_up_E -> M; headroom (WL+1) air
##   M (px+2, py..py+h-1, WL+1)  mid-landing strip; under (WL) solid
##   B (px+2, py+h-1,    WL+1)   stairs_up_W -> T;  shaft above B (WU) void
##   upper footprint (WU)        landing floor except the shaft over B
static func _carve_switchback(
		volume: VoxelMapData,
		connector: VerticalPlan.ConnectorPlan,
		wl: int,
		wu: int,
		sw: StairwellData,
		lower_room: int,
		upper_room: int,
		openings: Dictionary) -> void:
	var rect: Rect2i = connector.footprint
	var px: int = rect.position.x
	var py: int = rect.position.y
	var h: int = rect.size.y
	sw.run_cells.clear()

	# Default the whole footprint solid on both lower levels; carve walkables back.
	for dx in range(rect.size.x):
		for dy in range(h):
			_set_solid(volume, Vector3i(px + dx, py + dy, wl))
			_set_solid(volume, Vector3i(px + dx, py + dy, wl + 1))

	# Lower band walk (WL): bottom landing + lower step, each with air headroom.
	_set_floor(volume, Vector3i(px, py, wl), "open", "stone", lower_room)             # L
	_set_air(volume, Vector3i(px, py, wl + 1), lower_room)
	_set_floor(volume, Vector3i(px + 1, py, wl), "stairs_up_E", "stone", lower_room)  # A
	_set_air(volume, Vector3i(px + 1, py, wl + 1), lower_room)

	# Mid-landing strip at WL+1 down column px+2 (solid supporting mass below it).
	for dy in range(h):
		_set_floor(volume, Vector3i(px + 2, py + dy, wl + 1), "open", "stone", lower_room)
	# Upper step B replaces the last mid-landing cell (turns west, rises).
	var b: Vector3i = Vector3i(px + 2, py + h - 1, wl + 1)
	_set_floor(volume, b, "stairs_up_W", "stone", lower_room)

	# Upper band (WU): entire footprint is landing floor except the shaft above B.
	for dx in range(rect.size.x):
		for dy in range(h):
			_set_floor(volume, Vector3i(px + dx, py + dy, wu), "open", "stone", upper_room)
	var shaft: Vector3i = Vector3i(px + 2, py + h - 1, wu)
	_set_void(volume, shaft, upper_room)
	openings[shaft] = true

	sw.run_cells.append(Vector3i(px + 1, py, wl))         # A
	sw.run_cells.append(b)                                # B
	sw.bottom_cell = Vector3i(px, py, wl)
	sw.top_cell = Vector3i(px + 1, py + h - 1, wu)


## §6.3 spiral shaft. Each footprint column carries stairs_spiral: floor stone at
## each walk level (WL, WU), floor opening (none) at the intervening WL+1. The
## spiral movement clause (DG-C3D.E) permits +-1 level within the column.
static func _carve_spiral(
		volume: VoxelMapData,
		connector: VerticalPlan.ConnectorPlan,
		wl: int,
		wu: int,
		sw: StairwellData,
		lower_room: int,
		upper_room: int) -> void:
	var rect: Rect2i = connector.footprint
	sw.run_cells.clear()
	for dx in range(rect.size.x):
		for dy in range(rect.size.y):
			var col: int = rect.position.x + dx
			var row: int = rect.position.y + dy
			_set_floor(volume, Vector3i(col, row, wl), "stairs_spiral", "stone", lower_room)
			_set_spiral_gap(volume, Vector3i(col, row, wl + 1))
			_set_floor(volume, Vector3i(col, row, wu), "stairs_spiral", "stone", upper_room)
			sw.run_cells.append(Vector3i(col, row, wl))
			sw.run_cells.append(Vector3i(col, row, wl + 1))
			sw.run_cells.append(Vector3i(col, row, wu))
	sw.bottom_cell = Vector3i(rect.position.x, rect.position.y, wl)
	sw.top_cell = Vector3i(rect.position.x, rect.position.y, wu)


# ---------------------------------------------------------------------------
# C3 — atrium carving
# ---------------------------------------------------------------------------

## Carve one atrium: upper-band interior void, balcony ring slabs + parapet,
## optional internal grand stair, graceful degradation to a plain double-height
## hall when the balcony cannot be reached (§7).
static func _carve_atrium(
		volume: VoxelMapData,
		atrium: VerticalPlan.AtriumPlan,
		plan: VerticalPlan,
		slot_by_floor: Dictionary,
		layout_by_floor: Dictionary,
		result: ComposeResult,
		openings: Dictionary) -> void:
	var base_band: VerticalPlan.BandPlan = plan.band_for_floor(atrium.base_band)
	if base_band == null:
		return
	var wb: int = base_band.walk_level          # base (main-floor) walk level
	var wu: int = wb + 2                          # upper band walk level (void/ring)
	var rect: Rect2i = atrium.footprint
	var atrium_room: int = _atrium_room_id(rect, atrium.base_band, slot_by_floor, layout_by_floor)

	# Mark the base room's height + kind on the updated RoomData.
	for rd in result.rooms:
		if rd.id == atrium_room:
			rd.height_levels = 4
			break

	# Decide balcony connectivity (§7.2): internal grand stair, OR an existing
	# upper-band door reaching the ring, else degrade to a plain hall.
	var has_upper_door: bool = _footprint_has_door(rect, atrium.upper_band, layout_by_floor)
	var keep_ring: bool = atrium.internal_stair or has_upper_door

	# Interior (deeper than ring_depth from the edge) is always void; the ring is
	# balcony floor when kept, void when degraded.
	var ring_depth: int = atrium.ring_depth
	for dx in range(rect.size.x):
		for dy in range(rect.size.y):
			var col: int = rect.position.x + dx
			var row: int = rect.position.y + dy
			var edge_dist: int = mini(mini(dx, dy), mini(rect.size.x - 1 - dx, rect.size.y - 1 - dy))
			var is_ring: bool = edge_dist < ring_depth
			if keep_ring and is_ring:
				# Balcony slab at WU; airspace above.
				_set_floor(volume, Vector3i(col, row, wu), "open", "wood", atrium_room)
				_set_air(volume, Vector3i(col, row, wu + 1), atrium_room)
			else:
				# Void: open airspace all the way down to the main floor.
				_set_void_feature(volume, Vector3i(col, row, wu), atrium_room)
				_set_air(volume, Vector3i(col, row, wu + 1), atrium_room)
				openings[Vector3i(col, row, wu)] = true
			# Base-band headroom (WB+1) is open tall airspace.
			_set_air(volume, Vector3i(col, row, wb + 1), atrium_room)

	if keep_ring:
		_apply_parapet(volume, rect, wu)
		if atrium.internal_stair:
			_carve_internal_stair(volume, atrium, wb, wu, atrium_room, result, openings)
	else:
		result.warnings.append(
			"DungeonVolumeComposer: atrium at %s (bands %d/%d) degraded to plain double-height hall (no balcony access)."
			% [str(rect), atrium.base_band, atrium.upper_band])


## Parapet cover on balcony cells adjacent (8-neighbour) to a void cell.
static func _apply_parapet(volume: VoxelMapData, rect: Rect2i, wu: int) -> void:
	for dx in range(rect.size.x):
		for dy in range(rect.size.y):
			var pos := Vector3i(rect.position.x + dx, rect.position.y + dy, wu)
			var cell: VoxelCell = volume.get_cell(pos)
			if cell.floor_type == "none":
				continue  # a void cell, not a balcony
			for nb in VoxelGrid.get_neighbors_2d(pos):
				if not rect.has_point(Vector2i(nb.x, nb.y)):
					continue
				if volume.get_cell(nb).feature == "air_open":
					cell.cover_value = PARAPET_COVER
					break
			volume.set_cell(pos, cell)


## A straight grand stair from the atrium main floor (WB) to the balcony (WU),
## placed against the ring on the +y edge, two lanes wide.
static func _carve_internal_stair(
		volume: VoxelMapData,
		atrium: VerticalPlan.AtriumPlan,
		wb: int,
		wu: int,
		atrium_room: int,
		result: ComposeResult,
		openings: Dictionary) -> void:
	var rect: Rect2i = atrium.footprint
	# A 4-long x 2-wide run rising along -y from the interior up to the top ring
	# row. Anchored one cell in from the +x edge so it stays inside the interior.
	var end_y: int = rect.end.y - 1                 # bottom ring row (top landing on it)
	var start_y: int = end_y - 3
	if start_y < rect.position.y:
		return  # atrium too shallow for an internal stair (5x5 always fits)
	var lane_x: int = rect.position.x + 1
	var run := VerticalPlan.ConnectorPlan.new()
	run.type = StairwellData.TYPE_STRAIGHT
	run.lower_band = atrium.base_band
	run.upper_band = atrium.upper_band
	run.width = 2
	# Footprint 2 wide (x) x 4 long (y) so the run axis is y (ascends south->the
	# bottom ring). Reuse the straight carver; its top landing lands on the ring.
	run.footprint = Rect2i(lane_x, start_y, 2, 4)
	var stub := StairwellData.new()
	stub.room_id = atrium_room
	stub.type = StairwellData.TYPE_STRAIGHT
	stub.lower_band = atrium.base_band
	stub.upper_band = atrium.upper_band
	stub.width = 2
	stub.stairwell_id = "atrium_stair_%d_%d" % [rect.position.x, rect.position.y]
	# Both ends of an internal grand stair belong to the one atrium room.
	_carve_straight(volume, run, wb, wu, stub, atrium_room, atrium_room, openings)
	result.stairwells.append(stub)


# ---------------------------------------------------------------------------
# C4 — zone assignment
# ---------------------------------------------------------------------------

## Flood-fill each room's walkable cells at each band's WALK level into zones,
## stamp VoxelCell.zone_index, and build RoomZone records. Cells at intermediate
## levels (stair steps, mid-landings) are never zoned — that keeps band honesty
## (every zoned cell sits at its band's walk level). Zones on a room's HOME band
## (band == room.band) are emitted first so the main floor always takes
## zone_index 0; off-home zones (atrium balconies) follow.
static func _assign_zones(
		volume: VoxelMapData,
		plan: VerticalPlan,
		slot_by_floor: Dictionary,
		result: ComposeResult) -> void:
	# Collect connected components per (room, band) once.
	var comps: Array = []  # {room_id, band_floor, walk, cells: Array[Vector2i]}
	for band in plan.bands:
		var walk: int = band.walk_level
		var cells_by_room: Dictionary = {}  # room_id -> Array[Vector3i]
		for pos in volume.get_all_positions():
			if pos.z != walk:
				continue
			var cell: VoxelCell = volume.get_cell(pos)
			if cell.room_id < 0:
				continue
			if cell.solidity != "air" or cell.floor_type == "none":
				continue  # not standable (void / wall)
			if not cells_by_room.has(cell.room_id):
				cells_by_room[cell.room_id] = []
			(cells_by_room[cell.room_id] as Array).append(pos)

		for room_id in cells_by_room:
			var cell_set: Dictionary = {}
			for p in cells_by_room[room_id]:
				cell_set[p] = true
			var visited: Dictionary = {}
			for start in cells_by_room[room_id]:
				if visited.has(start):
					continue
				var comp: Array[Vector2i] = []
				var queue: Array[Vector3i] = [start]
				visited[start] = true
				while not queue.is_empty():
					var cur: Vector3i = queue.pop_front()
					comp.append(Vector2i(cur.x, cur.y))
					for nb in VoxelGrid.get_neighbors_2d(cur):
						# 4-neighbour only.
						if absi(nb.x - cur.x) + absi(nb.y - cur.y) != 1:
							continue
						if visited.has(nb) or not cell_set.has(nb):
							continue
						visited[nb] = true
						queue.append(nb)
				comps.append({"room_id": room_id, "band_floor": band.floor_index, "walk": walk, "cells": comp})

	# Emit home-band zones first (main floor -> zone_index 0), then balconies.
	var next_zone: Dictionary = {}
	for home_pass in [true, false]:
		for comp in comps:
			var room: DungeonRoomData = _find_room(result.rooms, comp["room_id"])
			var is_home: bool = room != null and comp["band_floor"] == room.band
			if is_home != home_pass:
				continue
			_emit_zone(volume, result, comp["room_id"], comp["band_floor"], comp["walk"], comp["cells"], next_zone)


## Build a RoomZone for one connected component, stamp zone_index on its cells,
## and attach it to the owning room.
static func _emit_zone(
		volume: VoxelMapData,
		result: ComposeResult,
		room_id: int,
		band_floor: int,
		walk: int,
		comp: Array[Vector2i],
		next_zone: Dictionary) -> void:
	if comp.is_empty():
		return
	var room: DungeonRoomData = _find_room(result.rooms, room_id)
	var zi: int = int(next_zone.get(room_id, 0))
	next_zone[room_id] = zi + 1

	var zone := RoomZone.new()
	zone.room_id = room_id
	zone.zone_index = zi
	zone.band = band_floor
	zone.zone_type = _zone_type_for(room, band_floor, zi)
	for c in comp:
		zone.cells.append(c)
		var cell: VoxelCell = volume.get_cell(Vector3i(c.x, c.y, walk))
		cell.zone_index = zi
		volume.set_cell(cell.pos, cell)
	result.zones.append(zone)
	if room != null:
		room.zones.append(zone)


## Zone type: circulation rooms landing; a room's zone on a band other than its
## own (an atrium balcony) balcony; otherwise main.
static func _zone_type_for(room: DungeonRoomData, band_floor: int, zone_index: int) -> String:
	if room == null:
		return RoomZone.ZONE_TYPE_MAIN
	if room.kind == DungeonRoomData.KIND_CIRCULATION:
		return RoomZone.ZONE_TYPE_LANDING
	if band_floor != room.band:
		return RoomZone.ZONE_TYPE_BALCONY
	return RoomZone.ZONE_TYPE_MAIN


# ---------------------------------------------------------------------------
# C5 — floor-integrity pass
# ---------------------------------------------------------------------------

## For every adjacent band pair (lower walk WL, upper walk WU = WL+2): every
## air cell on the upper walk level that sits above open lower-band space (the
## WL+1 headroom is air) must have a floor UNLESS its column is a registered
## opening; every registered opening at that level must have NO floor. Returns
## "" on success, or a description of the first violation found.
static func _check_floor_integrity(
		volume: VoxelMapData,
		plan: VerticalPlan,
		openings: Dictionary) -> String:
	var grid: Vector2i = plan.grid_size
	# Sort band walk levels ascending; adjacent pairs differ by 2.
	var walks: Array[int] = []
	for band in plan.bands:
		walks.append(band.walk_level)
	walks.sort()
	for i in range(walks.size() - 1):
		var wl: int = walks[i]
		var wu: int = walks[i + 1]
		if wu - wl != 2:
			continue
		for x in range(grid.x):
			for y in range(grid.y):
				var upper: VoxelCell = volume.get_cell(Vector3i(x, y, wu))
				if upper.solidity != "air":
					continue  # solid wall column, no floor needed
				var below: VoxelCell = volume.get_cell(Vector3i(x, y, wl + 1))
				if below.solidity != "air":
					continue  # not above open lower-band space
				var is_opening: bool = openings.has(Vector3i(x, y, wu))
				if is_opening:
					if upper.floor_type != "none":
						return "registered opening (%d,%d,%d) has a floor ('%s')" % [x, y, wu, upper.floor_type]
				else:
					if upper.floor_type == "none":
						return "undeclared hole at (%d,%d,%d) above open band space" % [x, y, wu]
	return ""


# ---------------------------------------------------------------------------
# Cell mutation helpers
# ---------------------------------------------------------------------------

static func _set_floor(volume: VoxelMapData, pos: Vector3i, feature: String, floor_type: String, room_id: int) -> void:
	var cell: VoxelCell = volume.get_cell(pos)
	cell.solidity = "air"
	cell.feature = feature
	cell.floor_type = floor_type
	if room_id >= 0:
		cell.room_id = room_id
	cell.door_state = ""
	cell.door_type = ""
	volume.set_cell(pos, cell)


static func _set_solid(volume: VoxelMapData, pos: Vector3i) -> void:
	var cell: VoxelCell = volume.get_cell(pos)
	_make_solid(cell, SOLID_FEATURE)
	volume.set_cell(pos, cell)


## Shaft opening: an air cell with NO floor (the hole through the upper slab).
static func _set_void(volume: VoxelMapData, pos: Vector3i, room_id: int) -> void:
	var cell: VoxelCell = volume.get_cell(pos)
	cell.solidity = "air"
	cell.feature = "open"
	cell.floor_type = "none"
	if room_id >= 0:
		cell.room_id = room_id
	volume.set_cell(pos, cell)


## Atrium void: air_open (flyers only), no floor.
static func _set_void_feature(volume: VoxelMapData, pos: Vector3i, room_id: int) -> void:
	var cell: VoxelCell = volume.get_cell(pos)
	cell.solidity = "air"
	cell.feature = "air_open"
	cell.floor_type = "none"
	if room_id >= 0:
		cell.room_id = room_id
	volume.set_cell(pos, cell)


## Plain open airspace (no floor), tagged to a room for identity.
static func _set_air(volume: VoxelMapData, pos: Vector3i, room_id: int) -> void:
	var cell: VoxelCell = volume.get_cell(pos)
	cell.solidity = "air"
	cell.feature = "open"
	cell.floor_type = "none"
	if room_id >= 0:
		cell.room_id = room_id
	volume.set_cell(pos, cell)


## Spiral intervening cell: the floor opening between walk levels.
static func _set_spiral_gap(volume: VoxelMapData, pos: Vector3i) -> void:
	var cell: VoxelCell = volume.get_cell(pos)
	cell.solidity = "air"
	cell.feature = "stairs_spiral"
	cell.floor_type = "none"
	volume.set_cell(pos, cell)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

static func _global_room_id(band_slot: int, local_id: int) -> int:
	if local_id < 0:
		return -1
	return band_slot * ROOM_ID_STRIDE + local_id


static func _find_room(rooms: Array[DungeonRoomData], room_id: int) -> DungeonRoomData:
	for r in rooms:
		if r.id == room_id:
			return r
	return null


## Compass suffix for a unit horizontal delta (mirrors MovementResolver).
static func _suffix_for_delta(delta: Vector2i) -> String:
	for i in range(VoxelGrid.DIRECTION_OFFSETS.size()):
		if VoxelGrid.DIRECTION_OFFSETS[i] == delta:
			return VoxelGrid.Direction.keys()[i]
	return "N"


## Global id of the atrium base room occupying [param footprint] on
## [param base_floor], or -1.
static func _atrium_room_id(
		footprint: Rect2i,
		base_floor: int,
		slot_by_floor: Dictionary,
		layout_by_floor: Dictionary) -> int:
	if not layout_by_floor.has(base_floor):
		return -1
	var layout: DungeonLayout = layout_by_floor[base_floor]
	var slot: int = slot_by_floor[base_floor]
	# Prefer an exact-bounds match; fall back to the room covering the centre.
	for r in layout.rooms:
		var room: DungeonRoomData = r
		if room.bounds == footprint:
			return _global_room_id(slot, room.id)
	var centre := Vector2i(
		footprint.position.x + footprint.size.x / 2,
		footprint.position.y + footprint.size.y / 2)
	for r in layout.rooms:
		var room: DungeonRoomData = r
		if room.bounds.has_point(centre):
			return _global_room_id(slot, room.id)
	return -1


## True when the upper band layout has any door cell inside [param footprint]
## (a corridor reaching the balcony ring, §7.2a).
static func _footprint_has_door(
		footprint: Rect2i,
		upper_floor: int,
		layout_by_floor: Dictionary) -> bool:
	if not layout_by_floor.has(upper_floor):
		return false
	var layout: DungeonLayout = layout_by_floor[upper_floor]
	for d in layout.doors:
		var door: DungeonDoorData = d
		if footprint.has_point(door.position):
			return true
	return false
