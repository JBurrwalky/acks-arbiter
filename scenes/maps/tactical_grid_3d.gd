class_name TacticalGrid3D
extends RefCounted

## Shared 3D tactical grid infrastructure for dungeon and combat renderers.
##
## Provides coordinate conversion between cell grid (col, row) and 3D world
## space, mesh building for floor/wall/fog/highlight/grid-line rendering,
## and camera/lighting helpers.
##
## The 3D coordinate system:
##   x = (col - row) * HALF_CELL        (diamond layout on XZ plane)
##   z = (col + row) * HALF_CELL
##   y = elevation * ELEVATION_SCALE     (Godot Y-up)
##
## Camera: orthographic at true isometric angle (-35.264° X, -45° Y).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CELL_SIZE := 1.0            ## World units per cell edge
const HALF_CELL := 0.5            ## Half cell for diamond offset
const ELEVATION_SCALE := 0.5      ## World units per elevation unit (2.5 ft)
const WALL_HEIGHT := 1.4          ## Reduced 30% from 2.0 for better visibility
const FLOOR_THICKNESS := 0.05     ## Thin floor slab
const GRID_LINE_Y := 0.01         ## Slight Y offset for grid lines above floor
const FOG_Y := 0.02               ## Y offset for fog overlay
const HIGHLIGHT_Y := 0.03         ## Y offset for highlight overlay

## Texture paths for walls, floors, and doors.
const WALL_TEXTURE_PATH := "res://assets/walls/stone_brick_dark_01.png"
const FLOOR_TEXTURE_PATH := "res://assets/floors/slate_tile_light.png"
const DOOR_TEXTURE_PATH := "res://assets/walls/wood_oak_weathered.png"

## UV tiling scale — how many times the texture repeats per world unit.
const WALL_UV_SCALE := 2.0
const FLOOR_UV_SCALE := 2.0


# ---------------------------------------------------------------------------
# Coordinate conversion
# ---------------------------------------------------------------------------

## Convert grid (col, row) with optional elevation to a 3D world position.
static func cell_to_world(col: int, row: int, elevation: int = 0) -> Vector3:
	return Vector3(
		float(col - row) * HALF_CELL,
		float(elevation) * ELEVATION_SCALE,
		float(col + row) * HALF_CELL
	)


## Convert a 3D world position (on the XZ plane) back to the nearest grid cell.
## Ignores the Y component.
static func world_to_cell(world_pos: Vector3) -> Vector2i:
	var col := roundf((world_pos.x / HALF_CELL + world_pos.z / HALF_CELL) / 2.0)
	var row := roundf((world_pos.z / HALF_CELL - world_pos.x / HALF_CELL) / 2.0)
	return Vector2i(int(col), int(row))


## Raycast from a screen position through the camera onto the Y=0 plane,
## then convert to grid cell coordinates.
static func screen_to_cell(camera: Camera3D, screen_pos: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	# Intersect with Y=0 plane
	if absf(direction.y) < 0.0001:
		return Vector2i(-1, -1)  # Ray parallel to ground
	var t := -origin.y / direction.y
	var hit := origin + direction * t
	return world_to_cell(hit)


## Raycast from a screen position through the camera onto a given Y plane.
## Returns the world position of the hit point, or Vector3.ZERO if parallel.
static func screen_to_world_on_plane(camera: Camera3D, screen_pos: Vector2, plane_y: float = 0.0) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return Vector3.ZERO
	var t := (plane_y - origin.y) / direction.y
	return origin + direction * t


# ---------------------------------------------------------------------------
# Material cache
# ---------------------------------------------------------------------------

## Cached materials by key string. Shared across all renderers.
static var _material_cache: Dictionary = {}

## Cached textures by path.
static var _texture_cache: Dictionary = {}


static func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	_texture_cache[path] = tex
	return tex


static func _get_material(key: String, color: Color, unshaded: bool = true) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[key] = mat
	return mat


## Create a textured material with UV tiling. Each wall/floor gets its own
## instance so it can be faded independently.
static func _make_textured_material(tex_path: String, uv_scale: float, tiled: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := _load_texture(tex_path)
	if tex != null:
		mat.albedo_texture = tex
		if tiled:
			mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.albedo_color = Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Get the floor material color for a terrain feature.
static func floor_color_for(terrain_feature: String, cell: Dictionary = {}) -> Color:
	match terrain_feature:
		"open", "stairs_up", "stairs_down":
			return Color(0.831, 0.722, 0.588)   # tan/beige floor
		"wall_stone", "rock":
			return Color(0.50, 0.50, 0.50)      # mid grey
		"wall_wood":
			return Color(0.55, 0.45, 0.35)      # grey-brown
		"portcullis":
			return Color(0.4, 0.3, 0.2)         # dark brown
		"door", "door_locked":
			return Color(0.545, 0.271, 0.075)   # brown
		"door_secret":
			var detected: bool = cell.get("door_detected", true)
			if detected:
				return Color(0.545, 0.271, 0.075)
			else:
				return Color(0.35, 0.35, 0.35)  # dark grey (dev aid)
		_:
			return Color(0.3, 0.3, 0.3)


## Get the ground color for wilderness/combat terrain features.
static func combat_ground_color(terrain_feature: String, _cell: Dictionary = {}) -> Color:
	match terrain_feature:
		"open":
			return Color(0.45, 0.55, 0.35)   # grass/field
		"tree", "forest":
			return Color(0.2, 0.4, 0.2)
		"rock", "boulder":
			return Color(0.5, 0.5, 0.5)
		"water":
			return Color(0.2, 0.3, 0.6)
		"road":
			return Color(0.55, 0.5, 0.4)
		_:
			return Color(0.4, 0.5, 0.35)


# ---------------------------------------------------------------------------
# Diamond mesh (cached)
# ---------------------------------------------------------------------------

## Cached diamond-shaped flat mesh on XZ plane.
static var _diamond_mesh: ArrayMesh = null


## Get a flat diamond mesh centered at origin on the XZ plane.
## The diamond represents one cell: 4 vertices forming a diamond shape.
static func get_diamond_mesh() -> ArrayMesh:
	# Rebuild if cached mesh lacks UVs (from a previous version)
	if _diamond_mesh != null and _diamond_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV:
		return _diamond_mesh
	_diamond_mesh = null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Diamond corners on XZ plane (same layout as 2D isometric diamond)
	var top   := Vector3(0.0, 0.0, -HALF_CELL)     # -Z = "up" on screen
	var right := Vector3(HALF_CELL, 0.0, 0.0)       # +X = "right" on screen
	var bottom := Vector3(0.0, 0.0, HALF_CELL)      # +Z = "down" on screen
	var left  := Vector3(-HALF_CELL, 0.0, 0.0)      # -X = "left" on screen

	# UV coordinates mapped to diamond corners so textures render correctly.
	# Maps the diamond to a square region of the texture.
	var uv_top    := Vector2(0.5, 0.0)
	var uv_right  := Vector2(1.0, 0.5)
	var uv_bottom := Vector2(0.5, 1.0)
	var uv_left   := Vector2(0.0, 0.5)

	st.set_normal(Vector3.UP)

	# Triangle 1: top, right, bottom
	st.set_uv(uv_top)
	st.add_vertex(top)
	st.set_uv(uv_right)
	st.add_vertex(right)
	st.set_uv(uv_bottom)
	st.add_vertex(bottom)

	# Triangle 2: top, bottom, left
	st.set_uv(uv_top)
	st.add_vertex(top)
	st.set_uv(uv_bottom)
	st.add_vertex(bottom)
	st.set_uv(uv_left)
	st.add_vertex(left)

	_diamond_mesh = st.commit()
	return _diamond_mesh


# ---------------------------------------------------------------------------
# Mesh builders
# ---------------------------------------------------------------------------

## Build a MultiMeshInstance3D for all floor cells (non-wall, non-void).
## Each instance is a diamond mesh positioned and colored by terrain.
## [param color_func]: Callable(terrain_feature: String, cell: Dictionary) -> Color
static func build_floor_multimesh(map: TacticalMapData, color_func: Callable) -> MultiMeshInstance3D:
	var cells := map._cells
	if cells.is_empty():
		return MultiMeshInstance3D.new()

	# Collect floor cells (everything that isn't a tall wall)
	var floor_cells: Array = []
	for pos in cells.keys():
		var cell: Dictionary = cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		# Walls get separate tall meshes; everything else is a floor diamond
		if tf not in ["wall_stone", "wall_wood", "rock"]:
			floor_cells.append({"pos": pos, "cell": cell, "tf": tf})

	if floor_cells.is_empty():
		return MultiMeshInstance3D.new()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = get_diamond_mesh()
	mm.instance_count = floor_cells.size()

	for i in range(floor_cells.size()):
		var entry: Dictionary = floor_cells[i]
		var pos: Vector2i = entry["pos"]
		var cell: Dictionary = entry["cell"]
		var tf: String = entry["tf"]
		var elevation: int = cell.get("elevation", 0)
		var world_pos := cell_to_world(pos.x, pos.y, elevation)

		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, color_func.call(tf, cell))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Floor texture tiled across cells; per-instance color tints the texture.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color.WHITE
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.vertex_color_use_as_albedo = true
	floor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var floor_tex := _load_texture(FLOOR_TEXTURE_PATH)
	if floor_tex != null:
		floor_mat.albedo_texture = floor_tex
		floor_mat.uv1_scale = Vector3(FLOOR_UV_SCALE, FLOOR_UV_SCALE, FLOOR_UV_SCALE)
	mmi.material_override = floor_mat
	return mmi


## Build wall meshes as individual MeshInstance3D nodes under a parent Node3D.
## Walls are tall boxes rising from their cell position.
static func build_walls(map: TacticalMapData) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Walls"
	var cells := map._cells

	for pos in cells.keys():
		var cell: Dictionary = cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		if tf not in ["wall_stone", "wall_wood", "rock"]:
			continue

		var elevation: int = cell.get("elevation", 0)
		var world_pos := cell_to_world(pos.x, pos.y, elevation)

		# Wall is a tall box centered on the cell, half underground
		var box := BoxMesh.new()
		box.size = Vector3(CELL_SIZE * 0.7, WALL_HEIGHT, CELL_SIZE * 0.7)

		var mat_key := "wall_" + tf
		var color: Color = floor_color_for(tf, cell)
		# Make walls slightly darker for depth
		color = color.darkened(0.15)

		# Each wall gets its own material instance so it can be faded independently.
		var mat := _make_textured_material(WALL_TEXTURE_PATH, WALL_UV_SCALE)
		# Tint the texture with the terrain color for variety
		mat.albedo_color = color.lightened(0.3)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = box
		mesh_inst.material_override = mat
		mesh_inst.position = world_pos + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
		# Rotate 45° to align box with the diamond grid
		mesh_inst.rotation_degrees.y = 45.0
		mesh_inst.set_meta("cell_pos", pos)
		mesh_inst.set_meta("base_color", color)
		parent.add_child(mesh_inst)

	return parent


## Build door meshes as thin boxes. Returns a Node3D parent.
## Doors are thin slabs that can be open (rotated 90°) or closed.
static func build_doors(map: TacticalMapData) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Doors"
	var cells := map._cells

	for pos in cells.keys():
		var cell: Dictionary = cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		if tf not in ["door", "door_locked", "door_secret", "portcullis"]:
			continue

		var door_state: String = cell.get("door_state", "closed")
		var door_type: String = cell.get("door_type", "")
		var detected: bool = cell.get("door_detected", true)
		var elevation: int = cell.get("elevation", 0)
		var world_pos := cell_to_world(pos.x, pos.y, elevation)

		# Don't render destroyed or undetected secret doors.
		if door_state == "destroyed":
			continue
		if tf == "door_secret" and not detected:
			continue

		# Compute orientation from adjacent passages.
		var closed_rotation: float = _compute_door_orientation(pos, map)

		if tf == "portcullis":
			# Portcullis: vertical bars (thin box)
			var box := BoxMesh.new()
			box.size = Vector3(CELL_SIZE * 0.6, WALL_HEIGHT * 0.8, 0.05)
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = box
			mesh_inst.material_override = _get_material("portcullis", Color(0.6, 0.6, 0.6), true)
			mesh_inst.position = world_pos + Vector3(0.0, WALL_HEIGHT * 0.4, 0.0)
			mesh_inst.rotation_degrees.y = closed_rotation
			if door_state == "open":
				mesh_inst.position.y += WALL_HEIGHT * 0.6  # Raised
			mesh_inst.set_meta("cell_pos", pos)
			mesh_inst.set_meta("door_type", tf)
			parent.add_child(mesh_inst)
		else:
			# Regular door: thin slab
			var box := BoxMesh.new()
			box.size = Vector3(CELL_SIZE * 0.6, WALL_HEIGHT * 0.7, 0.08)

			var color: Color
			match door_type:
				"locked", "trapped":
					color = Color(0.6, 0.3, 0.1)
				"secret":
					color = Color(0.5, 0.5, 0.5)
				"iron":
					color = Color(0.4, 0.4, 0.5)
				_:
					color = Color(0.545, 0.271, 0.075)  # brown

			if door_state == "locked" or door_state == "stuck":
				color = color.darkened(0.2)

			# Wood doors use stretched door texture; iron/secret use flat color
			var mat: StandardMaterial3D
			if door_type not in ["iron", "secret"]:
				mat = _make_textured_material(DOOR_TEXTURE_PATH, 1.0, false)
			else:
				mat = StandardMaterial3D.new()
				mat.albedo_color = color
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED

			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = box
			mesh_inst.material_override = mat
			mesh_inst.position = world_pos + Vector3(0.0, WALL_HEIGHT * 0.35, 0.0)

			# Orient perpendicular to passage when closed, +90° when open.
			if door_state == "open":
				mesh_inst.rotation_degrees.y = closed_rotation + 90.0
			else:
				mesh_inst.rotation_degrees.y = closed_rotation

			mesh_inst.set_meta("cell_pos", pos)
			mesh_inst.set_meta("door_type", tf)
			parent.add_child(mesh_inst)

	return parent


## Determine the Y rotation (degrees) for a door at [param pos] so it is
## perpendicular to the passage it blocks when closed.
## Grid E/W passage → -45°, Grid N/S passage → +45°, ambiguous → +45° fallback.
static func _compute_door_orientation(pos: Vector2i, map: TacticalMapData) -> float:
	var east := Vector2i(pos.x + 1, pos.y)
	var west := Vector2i(pos.x - 1, pos.y)
	var north := Vector2i(pos.x, pos.y - 1)
	var south := Vector2i(pos.x, pos.y + 1)

	var ew_passage: bool = _is_passage_neighbor(east, map) and _is_passage_neighbor(west, map)
	var ns_passage: bool = _is_passage_neighbor(north, map) and _is_passage_neighbor(south, map)

	if ew_passage and not ns_passage:
		return -45.0  # Perpendicular to grid-E/W (world diagonal (1,0,1))
	elif ns_passage and not ew_passage:
		return 45.0   # Perpendicular to grid-N/S (world diagonal (1,0,-1))
	else:
		return 45.0   # Ambiguous — default


## Returns true if [param pos] is a passable floor/stair cell (not a wall or door).
static func _is_passage_neighbor(pos: Vector2i, map: TacticalMapData) -> bool:
	if not map._cells.has(pos):
		return false
	var tf: String = map._cells[pos].get("terrain_feature", "")
	return tf in ["open", "stairs_up", "stairs_down"]


## Build stair meshes (ramped boxes). Returns a Node3D parent.
static func build_stairs(map: TacticalMapData) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Stairs"
	var cells := map._cells

	for pos in cells.keys():
		var cell: Dictionary = cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		if tf not in ["stairs_up", "stairs_down"]:
			continue

		var elevation: int = cell.get("elevation", 0)
		var world_pos := cell_to_world(pos.x, pos.y, elevation)

		# Ramp box tilted on X axis
		var box := BoxMesh.new()
		box.size = Vector3(CELL_SIZE * 0.5, 0.1, CELL_SIZE * 0.6)

		var color := Color(0.9, 0.9, 0.85)  # light stone
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = box
		mesh_inst.material_override = _get_material("stairs", color, true)
		mesh_inst.position = world_pos + Vector3(0.0, 0.2, 0.0)

		# Align with diamond grid and tilt to suggest slope direction
		mesh_inst.rotation_degrees.y = 45.0
		if tf == "stairs_up":
			mesh_inst.rotation_degrees.x = -20.0
		else:
			mesh_inst.rotation_degrees.x = 20.0

		# Arrow label above
		var label := Label3D.new()
		label.text = "▲" if tf == "stairs_up" else "▼"
		label.font_size = 32
		label.modulate = Color.WHITE
		label.position = world_pos + Vector3(0.0, 0.5, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.no_depth_test = true
		parent.add_child(mesh_inst)
		parent.add_child(label)

	return parent


## Build grid line outlines for all cells. Uses ImmediateMesh for line primitives.
static func build_grid_lines(map: TacticalMapData) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var cells := map._cells

	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	for pos in cells.keys():
		var cell: Dictionary = cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		if tf in ["wall_stone", "wall_wood", "rock"]:
			continue  # No grid lines on wall cells

		var elevation: int = cell.get("elevation", 0)
		var center := cell_to_world(pos.x, pos.y, elevation)
		var y := center.y + GRID_LINE_Y

		# Diamond corners
		var top    := Vector3(center.x, y, center.z - HALF_CELL)
		var right  := Vector3(center.x + HALF_CELL, y, center.z)
		var bottom := Vector3(center.x, y, center.z + HALF_CELL)
		var left   := Vector3(center.x - HALF_CELL, y, center.z)

		# 4 edges as line segments
		im.surface_add_vertex(top)
		im.surface_add_vertex(right)
		im.surface_add_vertex(right)
		im.surface_add_vertex(bottom)
		im.surface_add_vertex(bottom)
		im.surface_add_vertex(left)
		im.surface_add_vertex(left)
		im.surface_add_vertex(top)

	im.surface_end()

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = im
	mesh_inst.material_override = _get_material("grid_lines", Color(0.0, 0.0, 0.0, 0.5), true)
	mesh_inst.name = "GridLines"
	return mesh_inst


## Build a fog overlay MultiMeshInstance3D. HIDDEN = opaque black, EXPLORED = semi-transparent.
## VISIBLE cells are not rendered. Pass the map for cell positions and fog states.
static func build_fog_overlay(map: TacticalMapData) -> MultiMeshInstance3D:
	var fog_cells: Array = []
	for pos in map._cells.keys():
		var fog_state := map.get_fog(pos)
		if fog_state == TacticalMapData.FogState.VISIBLE:
			continue
		var cell: Dictionary = map._cells[pos]
		var elevation: int = cell.get("elevation", 0)
		fog_cells.append({"pos": pos, "elevation": elevation, "state": fog_state})

	if fog_cells.is_empty():
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "FogOverlay"
		return mmi

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = get_diamond_mesh()
	mm.instance_count = fog_cells.size()

	for i in range(fog_cells.size()):
		var entry: Dictionary = fog_cells[i]
		var pos: Vector2i = entry["pos"]
		var elev: int = entry["elevation"]
		var world_pos := cell_to_world(pos.x, pos.y, elev)
		world_pos.y += FOG_Y  # Slightly above floor

		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)

		if entry["state"] == TacticalMapData.FogState.HIDDEN:
			mm.set_instance_color(i, Color(0.0, 0.0, 0.0, 1.0))
		else:  # EXPLORED
			mm.set_instance_color(i, Color(0.0, 0.0, 0.0, 0.45))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Fog needs vertex_color_use_as_albedo for per-instance black/alpha colors,
	# plus TRANSPARENCY_ALPHA for EXPLORED cells.
	var fog_mat := StandardMaterial3D.new()
	fog_mat.albedo_color = Color.WHITE
	fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_mat.vertex_color_use_as_albedo = true
	fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Render on top of floor without depth-fighting
	fog_mat.render_priority = 1
	fog_mat.no_depth_test = true
	mmi.material_override = fog_mat
	mmi.name = "FogOverlay"
	return mmi


## Build a highlight overlay for a set of cells with a given color.
## Returns a MultiMeshInstance3D positioned at HIGHLIGHT_Y above floor.
static func build_highlight_overlay(cells: Array[Vector2i], color: Color, map: TacticalMapData = null) -> MultiMeshInstance3D:
	if cells.is_empty():
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Highlight"
		return mmi

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = get_diamond_mesh()
	mm.instance_count = cells.size()

	for i in range(cells.size()):
		var pos: Vector2i = cells[i]
		var elev := 0
		if map != null:
			var cell := map.get_cell(pos)
			elev = cell.get("elevation", 0)
		var world_pos := cell_to_world(pos.x, pos.y, elev)
		world_pos.y += HIGHLIGHT_Y

		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, color)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Highlights use per-instance alpha for semi-transparent colored overlays.
	var hl_mat := StandardMaterial3D.new()
	hl_mat.albedo_color = Color.WHITE
	hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hl_mat.vertex_color_use_as_albedo = true
	hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hl_mat.render_priority = 2
	hl_mat.no_depth_test = true
	mmi.material_override = hl_mat
	mmi.name = "Highlight"
	return mmi


## Build transition cell markers (green diamond outlines + "E" label).
static func build_transition_markers(map: TacticalMapData) -> Node3D:
	var parent := Node3D.new()
	parent.name = "TransitionMarkers"

	for tc_pos in map.transition_cells:
		if map.get_fog(tc_pos) == TacticalMapData.FogState.HIDDEN:
			continue
		var cell := map.get_cell(tc_pos)
		var elev: int = cell.get("elevation", 0)
		var world_pos := cell_to_world(tc_pos.x, tc_pos.y, elev)

		# Green "E" label floating above cell
		var label := Label3D.new()
		label.text = "E"
		label.font_size = 24
		label.modulate = Color.GREEN
		label.position = world_pos + Vector3(0.0, 0.3, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.no_depth_test = true
		parent.add_child(label)

	return parent


## Build feature labels (door icons, etc.) as Label3D nodes above cell surfaces.
static func build_feature_labels(map: TacticalMapData) -> Node3D:
	var parent := Node3D.new()
	parent.name = "FeatureLabels"
	var cells := map._cells

	for pos in cells.keys():
		var cell: Dictionary = cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		var door_state: String = cell.get("door_state", "closed")
		var door_type: String = cell.get("door_type", "")
		var detected: bool = cell.get("door_detected", true)
		var elevation: int = cell.get("elevation", 0)
		var world_pos := cell_to_world(pos.x, pos.y, elevation)

		var label_text := ""
		var label_color := Color.WHITE

		match tf:
			"door", "door_locked":
				if door_state == "destroyed":
					pass  # No label for destroyed doors.
				elif door_type == "arch":
					label_text = "A"
					label_color = Color(1.0, 1.0, 0.8)
				elif door_state == "open":
					label_text = "○"
				elif door_state == "locked":
					label_text = "L"
					label_color = Color.YELLOW
				elif door_state == "stuck":
					label_text = "K"
					label_color = Color.ORANGE_RED
				else:
					label_text = "X"

			"door_secret":
				if door_state == "destroyed":
					pass
				elif detected:
					if door_state == "open":
						label_text = "○"
					else:
						label_text = "?"
				else:
					label_text = "S"
					label_color = Color(1.0, 0.9, 0.2)

			"portcullis":
				if door_state == "destroyed":
					pass
				elif door_state != "open":
					label_text = "P"
					label_color = Color.YELLOW

			"lever":
				label_text = "⚙"
				label_color = Color(0.8, 0.7, 0.4)

		if label_text.is_empty():
			continue

		var label := Label3D.new()
		label.text = label_text
		label.font_size = 20
		label.modulate = label_color
		label.position = world_pos + Vector3(0.0, 0.15, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.no_depth_test = true
		parent.add_child(label)

	return parent


# ---------------------------------------------------------------------------
# Camera + Lighting setup
# ---------------------------------------------------------------------------

## Create and return a Camera3D configured for orthographic isometric view.
static func create_isometric_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 12.0
	cam.near = 0.1
	cam.far = 200.0
	# Isometric tilt only — diamond layout is baked into cell_to_world() coords.
	cam.rotation_degrees = Vector3(-35.264, 0.0, 0.0)
	cam.position = Vector3(0.0, 15.0, 10.0)
	return cam


## Create a DirectionalLight3D for the isometric view.
static func create_directional_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-60.0, -30.0, 0.0)
	light.light_energy = 0.6
	light.shadow_enabled = false
	return light


## Create a WorldEnvironment with ambient light.
static func create_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	return world_env
