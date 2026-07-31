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
	tex = _ensure_mipmaps(tex)
	_texture_cache[path] = tex
	return tex


## Guarantee the texture carries a mip chain, rebuilding it as an ImageTexture
## if not. The .import files are gitignored ("auto-regenerated from source"),
## and Godot's detect-3d auto-mipmap pass only fires for textures referenced by
## *saved* material resources — never for the StandardMaterial3D instances this
## class builds in code. Without mipmaps, the detailed floor/wall textures
## undersample at the zoomed-out isometric view and read as screen-door speckle.
## When the import already supplies mipmaps this is a cheap no-op.
static func _ensure_mipmaps(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.has_mipmaps():
		return tex
	if img.is_compressed():
		if img.decompress() != OK:
			return tex  # Can't add mipmaps to an undecodable format; leave as-is.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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
		# Mipmap + anisotropic filtering so minified/grazing-angle surfaces
		# don't undersample into speckle (see floor builder note).
		mat.texture_filter = \
			BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_color = Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


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



# ===========================================================================
# VOXEL BUILDERS — consume VoxelMapData per GDD §17.3
# ===========================================================================

# ---------------------------------------------------------------------------
# Cube mesh (cached) — 1×1×1 cube for wall voxels
# ---------------------------------------------------------------------------

static var _cube_mesh: ArrayMesh = null


## Returns a cached 1×1×1 cube mesh for wall/solid voxel rendering.
## Centered at origin. Rotated 45° around Y to align with the diamond grid.
static func get_cube_mesh() -> ArrayMesh:
	if _cube_mesh != null:
		return _cube_mesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Half-extents for a 1×1×1 cube
	var h := 0.35  # Slightly smaller than 0.5 to leave visible gaps between cubes

	# Rotated 45° around Y to align with diamond grid
	var cos45 := 0.7071
	var sin45 := 0.7071

	# 8 vertices of the rotated cube
	var verts: Array[Vector3] = []
	for y_sign in [-1.0, 1.0]:
		for x_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var lx: float = x_sign * h
				var lz: float = z_sign * h
				# Rotate around Y by 45°
				var rx: float = lx * cos45 - lz * sin45
				var rz: float = lx * sin45 + lz * cos45
				verts.append(Vector3(rx, y_sign * 0.5, rz))

	# Vertex indices: bottom face (y=-0.5) = 0-3, top face (y=+0.5) = 4-7
	# After rotation, order is: (-h,-h), (-h,+h), (+h,-h), (+h,+h) per face
	var faces: Array = [
		# Top face (y+)
		[4, 5, 7, 4, 7, 6],
		# Bottom face (y-)
		[0, 3, 1, 0, 2, 3],
		# Front face
		[1, 3, 7, 1, 7, 5],
		# Back face
		[0, 4, 6, 0, 6, 2],
		# Right face
		[2, 6, 7, 2, 7, 3],
		# Left face
		[0, 1, 5, 0, 5, 4],
	]

	var normals: Array[Vector3] = [
		Vector3.UP, Vector3.DOWN,
		Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(45)).normalized(),
		Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(45)).normalized(),
		Vector3(1, 0, 0).rotated(Vector3.UP, deg_to_rad(45)).normalized(),
		Vector3(-1, 0, 0).rotated(Vector3.UP, deg_to_rad(45)).normalized(),
	]

	for face_idx in range(faces.size()):
		var face: Array = faces[face_idx]
		var normal: Vector3 = normals[face_idx]
		st.set_normal(normal)
		for vi in face:
			st.add_vertex(verts[vi])

	_cube_mesh = st.commit()
	return _cube_mesh


# ---------------------------------------------------------------------------
# Voxel color functions
# ---------------------------------------------------------------------------

## Floor color for voxel cells based on floor_type.
static func floor_color_for_voxel(floor_type: String, feature: String = "") -> Color:
	# Stair/door tinting
	if feature.begins_with("stairs"):
		return Color(0.9, 0.9, 0.85)  # light stone
	if feature == "ladder":
		return Color(0.55, 0.45, 0.35)  # wood brown

	match floor_type:
		"stone":
			return Color(0.831, 0.722, 0.588)   # tan/beige
		"wood":
			return Color(0.6, 0.45, 0.3)        # warm brown
		"grate":
			return Color(0.5, 0.5, 0.55)        # dark grey-blue
		"pit_cover":
			return Color(0.4, 0.35, 0.25)       # dark brown
		"trap_door":
			return Color(0.5, 0.4, 0.3)         # medium brown
		"rubble":
			return Color(0.55, 0.5, 0.45)       # grey-brown
		"ice":
			return Color(0.75, 0.85, 0.95)      # pale blue
		"grass":
			return Color(0.45, 0.55, 0.35)      # grass green
		"dirt":
			return Color(0.55, 0.45, 0.3)       # brown
		"sand":
			return Color(0.82, 0.74, 0.52)      # pale sand
		"mud":
			return Color(0.42, 0.36, 0.26)      # dark wet brown
		"snow":
			return Color(0.92, 0.93, 0.96)      # white
		"gravel":
			return Color(0.58, 0.56, 0.52)      # scree grey
		"water":
			return Color(0.16, 0.30, 0.38)      # streambed (water plane on top)
		"lava_rock":
			return Color(0.24, 0.20, 0.20)      # basalt
		_:
			return Color(0.831, 0.722, 0.588)    # default tan


## Wall color for voxel cells based on feature type.
static func wall_color_for_voxel(feature: String) -> Color:
	match feature:
		"wall_stone", "rock":
			return Color(0.50, 0.50, 0.50).darkened(0.15)
		"wall_wood":
			return Color(0.55, 0.45, 0.35).darkened(0.15)
		"pillar":
			return Color(0.55, 0.55, 0.50).darkened(0.1)
		"earth":
			return Color(0.46, 0.38, 0.28)      # terrain column soil/rock
		_:
			return Color(0.45, 0.45, 0.45)


## Combat ground color for open field cells.
static func combat_ground_color_voxel(floor_type: String, _feature: String = "") -> Color:
	match floor_type:
		"grass":
			return Color(0.45, 0.55, 0.35)
		"stone":
			return Color(0.5, 0.5, 0.5)
		"dirt":
			return Color(0.55, 0.45, 0.3)
		"sand", "mud", "snow", "gravel", "water", "lava_rock":
			return floor_color_for_voxel(floor_type)
		_:
			return Color(0.4, 0.5, 0.35)


# ---------------------------------------------------------------------------
# Per-level floor builder (voxel)
# ---------------------------------------------------------------------------

## Build a MultiMeshInstance3D for floor slabs on a given level.
## Selects cells with floor_type != "none" on that level.
static func build_floor_multimesh_voxel(
		map: VoxelMapData, level: int, color_func: Callable) -> MultiMeshInstance3D:
	var floor_cells: Array = []
	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.floor_type != "none":
			floor_cells.append(cell)

	if floor_cells.is_empty():
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "FloorSlabs"
		return mmi

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = get_diamond_mesh()
	mm.instance_count = floor_cells.size()

	for i in range(floor_cells.size()):
		var cell: VoxelCell = floor_cells[i]
		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)

		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, color_func.call(cell.floor_type, cell.feature))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color.WHITE
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.vertex_color_use_as_albedo = true
	floor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var floor_tex := _load_texture(FLOOR_TEXTURE_PATH)
	if floor_tex != null:
		floor_mat.albedo_texture = floor_tex
		floor_mat.uv1_scale = Vector3(FLOOR_UV_SCALE, FLOOR_UV_SCALE, FLOOR_UV_SCALE)
		# Floors are viewed at a grazing isometric angle and minified heavily
		# when zoomed out. Anisotropic mipmap filtering kills the texel-
		# undersampling speckle that otherwise looks like screen-door dither.
		floor_mat.texture_filter = \
			BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mmi.material_override = floor_mat
	mmi.name = "FloorSlabs"
	mmi.set_meta("base_color", Color.WHITE)
	return mmi


# ---------------------------------------------------------------------------
# Per-level wall builder (voxel — MultiMesh cubes)
# ---------------------------------------------------------------------------

## Build a MultiMeshInstance3D for wall/solid voxel cells on a given level.
## Each solid cell becomes a 1×1×1 cube instance.
static func build_walls_voxel(map: VoxelMapData, level: int) -> MultiMeshInstance3D:
	var wall_cells: Array = []
	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.solidity == "solid":
			# Battle-map terrain mass and catalog obstacles have their own
			# builders (build_terrain_columns_voxel / build_obstacles_voxel).
			if cell.feature == "earth" or BattleMapObstacleCatalog.is_solid_obstacle(cell.feature):
				continue
			wall_cells.append(cell)

	if wall_cells.is_empty():
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Walls"
		return mmi

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = get_cube_mesh()
	mm.instance_count = wall_cells.size()

	for i in range(wall_cells.size()):
		var cell: VoxelCell = wall_cells[i]
		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)
		# Center cube vertically: floor at level*1.0, center at level*1.0 + 0.5
		world_pos.y += 0.5

		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, wall_color_for_voxel(cell.feature))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color.WHITE
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.vertex_color_use_as_albedo = true
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall_tex := _load_texture(WALL_TEXTURE_PATH)
	if wall_tex != null:
		wall_mat.albedo_texture = wall_tex
		wall_mat.uv1_scale = Vector3(WALL_UV_SCALE, WALL_UV_SCALE, WALL_UV_SCALE)
	mmi.material_override = wall_mat
	mmi.name = "Walls"
	mmi.set_meta("base_color", Color.WHITE)
	return mmi


# ---------------------------------------------------------------------------
# Per-level wall builder (voxel — individual MeshInstance3D for focus level)
# ---------------------------------------------------------------------------

## Build individual wall MeshInstance3D nodes for the focus level.
## Allows per-wall occlusion fade (camera-blocking transparency).
static func build_walls_voxel_individual(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Walls"

	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.solidity != "solid":
			continue
		if cell.feature == "earth" or BattleMapObstacleCatalog.is_solid_obstacle(cell.feature):
			continue

		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)
		world_pos.y += 0.5

		var box := BoxMesh.new()
		box.size = Vector3(CELL_SIZE * 0.7, CELL_SIZE, CELL_SIZE * 0.7)

		var color := wall_color_for_voxel(cell.feature)
		var mat := _make_textured_material(WALL_TEXTURE_PATH, WALL_UV_SCALE)
		mat.albedo_color = color.lightened(0.3)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = box
		mesh_inst.material_override = mat
		mesh_inst.position = world_pos
		mesh_inst.rotation_degrees.y = 45.0
		mesh_inst.set_meta("cell_pos", Vector3i(cell.col, cell.row, level))
		mesh_inst.set_meta("base_color", color)
		parent.add_child(mesh_inst)

	return parent


# ---------------------------------------------------------------------------
# Per-level door builder (voxel)
# ---------------------------------------------------------------------------

## Build door meshes for a given level from VoxelMapData.
static func build_doors_voxel(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Doors"

	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.door_state.is_empty():
			continue
		if cell.door_state == "destroyed":
			continue
		if cell.door_type == "secret" and not cell.door_detected:
			continue

		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)
		var pos := Vector3i(cell.col, cell.row, level)
		var closed_rotation: float = _compute_door_orientation_voxel(pos, map)

		if cell.door_type == "portcullis":
			var box := BoxMesh.new()
			box.size = Vector3(CELL_SIZE * 0.6, CELL_SIZE * 0.8, 0.05)
			var portcullis_color := Color(0.6, 0.6, 0.6)
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = box
			var portcullis_mat := StandardMaterial3D.new()
			portcullis_mat.albedo_color = portcullis_color
			portcullis_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			portcullis_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_inst.material_override = portcullis_mat
			mesh_inst.position = world_pos + Vector3(0.0, CELL_SIZE * 0.4, 0.0)
			mesh_inst.rotation_degrees.y = closed_rotation
			if cell.door_state == "open":
				mesh_inst.position.y += CELL_SIZE * 0.6
			mesh_inst.set_meta("cell_pos", pos)
			mesh_inst.set_meta("door_type", cell.door_type)
			mesh_inst.set_meta("base_color", portcullis_color)
			parent.add_child(mesh_inst)
		else:
			var box := BoxMesh.new()
			box.size = Vector3(CELL_SIZE * 0.6, CELL_SIZE * 0.7, 0.08)

			var color: Color
			match cell.door_type:
				"locked", "trapped":
					color = Color(0.6, 0.3, 0.1)
				"secret":
					color = Color(0.5, 0.5, 0.5)
				_:
					color = Color(0.545, 0.271, 0.075)

			if cell.door_state == "locked" or cell.door_state == "stuck":
				color = color.darkened(0.2)

			var mat: StandardMaterial3D
			if cell.door_type not in ["secret"]:
				mat = _make_textured_material(DOOR_TEXTURE_PATH, 1.0, false)
			else:
				mat = StandardMaterial3D.new()
				mat.albedo_color = color
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED

			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = box
			mesh_inst.material_override = mat
			mesh_inst.position = world_pos + Vector3(0.0, CELL_SIZE * 0.35, 0.0)

			if cell.door_state == "open":
				mesh_inst.rotation_degrees.y = closed_rotation + 90.0
			else:
				mesh_inst.rotation_degrees.y = closed_rotation

			mesh_inst.set_meta("cell_pos", pos)
			mesh_inst.set_meta("door_type", cell.door_type)
			mesh_inst.set_meta("base_color", mat.albedo_color)
			parent.add_child(mesh_inst)

	return parent


## Door orientation for voxel maps. Uses VoxelGrid 2D neighbors.
## A door spans ACROSS the corridor (perpendicular to the flanking walls), not
## along it. In the diamond layout the col/row axes are the world 45° diagonals:
##   - EW corridor (air E & W) -> door lies on the N-S diagonal -> +45°
##   - NS corridor (air N & S), or ambiguous -> door lies on the E-W diagonal -> -45°
## (Fixed 2026-06-13: previously returned the wall-edge angle, leaving doors lying
## along the corridor — 90° off. Mirrors DungeonAssetBuilder._door_rotation.)
static func _compute_door_orientation_voxel(pos: Vector3i, map: VoxelMapData) -> float:
	var east := Vector3i(pos.x + 1, pos.y, pos.z)
	var west := Vector3i(pos.x - 1, pos.y, pos.z)
	var north := Vector3i(pos.x, pos.y - 1, pos.z)
	var south := Vector3i(pos.x, pos.y + 1, pos.z)

	var ew_passage: bool = _is_passage_neighbor_voxel(east, map) and _is_passage_neighbor_voxel(west, map)
	var ns_passage: bool = _is_passage_neighbor_voxel(north, map) and _is_passage_neighbor_voxel(south, map)

	if ew_passage and not ns_passage:
		return 45.0
	elif ns_passage and not ew_passage:
		return -45.0
	else:
		return -45.0


static func _is_passage_neighbor_voxel(pos: Vector3i, map: VoxelMapData) -> bool:
	if not map.has_cell(pos):
		return false
	var cell: VoxelCell = map.get_cell(pos)
	return cell.solidity == "air" and cell.door_state.is_empty() and cell.feature in ["open", "ladder"]


# ---------------------------------------------------------------------------
# Per-level feature builder (voxel — stairs, ramps, ladders)
# ---------------------------------------------------------------------------

## Build feature meshes (stairs, spiral, ramps, ladders, parapets) for a given
## level. DG-C3D.G placeholder primitives: stepped stairs, a helical spiral, an
## inclined ramp, and a balcony parapet rail (cover_value > 0) — simple boxes
## flagged to gdd-dungeon-asset-integration-plan.md for real meshes. The
## renderer architecture is unchanged (these live in the per-level Features
## Node3D, so the tint/fade/fog machinery already covers them; every mesh sets a
## "base_color" meta so set_level_group_tint can dim it below focus).
static func build_features_voxel(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Features"

	const STAIR_COLOR := Color(0.9, 0.9, 0.85)
	const RAMP_COLOR := Color(0.75, 0.62, 0.45)
	const PARAPET_COLOR := Color(0.62, 0.6, 0.66)

	for cell: VoxelCell in map.get_cells_at_level(level):
		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)

		# Spiral is checked BEFORE the generic stairs branch — its feature has no
		# compass suffix, so the generic path would mis-rotate it.
		if cell.feature == "stairs_spiral":
			_build_spiral_placeholder(parent, world_pos, STAIR_COLOR)

		elif cell.feature.begins_with("stairs_"):
			_build_stepped_placeholder(parent, world_pos, cell.feature, STAIR_COLOR)

		elif cell.feature.begins_with("ramp_"):
			_build_ramp_placeholder(parent, world_pos, cell.feature, RAMP_COLOR)

		elif cell.feature == "ladder":
			# Ladder: vertical thin box
			var box := BoxMesh.new()
			box.size = Vector3(0.15, CELL_SIZE * 0.8, 0.08)
			var ladder_color := Color(0.55, 0.45, 0.35)
			var ladder_mat := StandardMaterial3D.new()
			ladder_mat.albedo_color = ladder_color
			ladder_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ladder_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = box
			mesh_inst.material_override = ladder_mat
			mesh_inst.set_meta("base_color", ladder_color)
			mesh_inst.position = world_pos + Vector3(0.0, 0.4, 0.0)
			mesh_inst.rotation_degrees.y = 45.0
			parent.add_child(mesh_inst)

		elif cell.feature == "lever":
			var label := Label3D.new()
			label.text = "⚙"
			label.font_size = 20
			label.modulate = Color(0.8, 0.7, 0.4)
			label.position = world_pos + Vector3(0.0, 0.15, 0.0)
			label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			label.no_depth_test = true
			parent.add_child(label)

		# Parapet rail on a balcony-edge cell (cover_value > 0), on the side(s)
		# facing the atrium void. Independent of the feature branch above — the
		# balcony floor cell's feature is "open".
		if cell.cover_value > 0 and cell.floor_type != "none":
			_build_parapet_placeholder(parent, world_pos, map, cell, level, PARAPET_COLOR)

	return parent


## An unshaded, double-sided box MeshInstance3D flagged with a "base_color" meta
## (load-bearing for set_level_group_tint's below-focus dimming).
static func _feature_box(size: Vector3, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inst := MeshInstance3D.new()
	inst.mesh = box
	inst.material_override = mat
	inst.set_meta("base_color", color)
	return inst


## Stepped-stair placeholder: three rising treads (grouped + rotated to face the
## suffix compass) plus the ▲/▼ arrow. Reads as steps rather than a flat slab.
static func _build_stepped_placeholder(parent: Node3D, world_pos: Vector3, feature: String, color: Color) -> void:
	var group := Node3D.new()
	group.position = world_pos
	group.rotation_degrees.y = _stair_direction_rotation(feature)
	for i in 3:
		var tread := _feature_box(Vector3(CELL_SIZE * 0.5, 0.08, CELL_SIZE * 0.22), color)
		tread.position = Vector3(0.0, 0.08 + float(i) * 0.13, -0.22 + float(i) * 0.18)
		group.add_child(tread)
	parent.add_child(group)

	var is_up := feature.begins_with("stairs_up")
	var label := Label3D.new()
	label.text = "▲" if is_up else "▼"
	label.font_size = 32
	label.modulate = Color.WHITE
	label.position = world_pos + Vector3(0.0, 0.55, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.no_depth_test = true
	parent.add_child(label)


## Spiral-stair placeholder: a central post + four quarter-treads at 90°
## increments (a rough helix).
static func _build_spiral_placeholder(parent: Node3D, world_pos: Vector3, color: Color) -> void:
	var group := Node3D.new()
	group.position = world_pos
	var post := _feature_box(Vector3(0.12, CELL_SIZE * 0.85, 0.12), color)
	post.position = Vector3(0.0, CELL_SIZE * 0.42, 0.0)
	group.add_child(post)
	for i in 4:
		var tread := _feature_box(Vector3(CELL_SIZE * 0.34, 0.07, 0.14), color)
		tread.position = Vector3(0.0, 0.12 + float(i) * 0.2, 0.0)
		tread.rotation_degrees.y = float(i) * 90.0
		# Offset outward along the tread's local +X so it reads as a fan.
		tread.position += tread.transform.basis.x * (CELL_SIZE * 0.16)
		group.add_child(tread)
	parent.add_child(group)


## Ramp placeholder: a single inclined slab (no risers) facing the suffix.
static func _build_ramp_placeholder(parent: Node3D, world_pos: Vector3, feature: String, color: Color) -> void:
	var inst := _feature_box(Vector3(CELL_SIZE * 0.6, 0.08, CELL_SIZE * 0.9), color)
	inst.position = world_pos + Vector3(0.0, 0.2, 0.0)
	inst.rotation_degrees.y = _stair_direction_rotation(feature)
	inst.rotation_degrees.x = -18.0  # incline
	parent.add_child(inst)


## Parapet placeholder: a low rail on each void-facing edge of a balcony cell.
static func _build_parapet_placeholder(parent: Node3D, world_pos: Vector3, map: VoxelMapData, cell: VoxelCell, level: int, color: Color) -> void:
	# One low rail per 2D neighbour that is an atrium void (feature "air_open").
	for nb in VoxelGrid.get_neighbors_2d(Vector3i(cell.col, cell.row, level)):
		if map.get_cell(nb).feature != "air_open":
			continue
		var rail := _feature_box(Vector3(CELL_SIZE * 0.9, 0.18, 0.08), color)
		# Place the rail on the shared edge, half a cell toward the void, raised.
		var nb_world := VoxelGrid.cell_to_world(nb.x, nb.y, level)
		rail.position = world_pos.lerp(nb_world, 0.5) + Vector3(0.0, 0.24, 0.0)
		# Orient the rail perpendicular to the edge direction.
		var edge := nb_world - world_pos
		rail.rotation_degrees.y = rad_to_deg(atan2(edge.x, edge.z)) + 90.0
		parent.add_child(rail)


## Compute Y rotation for stair direction suffix.
static func _stair_direction_rotation(feature: String) -> float:
	# Extract direction from "stairs_up_N", "stairs_down_SW" etc.
	var parts := feature.split("_")
	if parts.size() < 3:
		return 45.0  # default
	var dir_str: String = parts[2]  # N, NE, E, SE, S, SW, W, NW
	match dir_str:
		"N":  return 45.0
		"NE": return 0.0
		"E":  return -45.0
		"SE": return -90.0
		"S":  return -135.0
		"SW": return 180.0
		"W":  return 135.0
		"NW": return 90.0
		_:    return 45.0


# ---------------------------------------------------------------------------
# Per-level fog overlay (voxel)
# ---------------------------------------------------------------------------

## Build a fog overlay MultiMeshInstance3D for a given level from VoxelMapData.
static func build_fog_overlay_voxel(map: VoxelMapData, level: int) -> MultiMeshInstance3D:
	var fog_cells: Array = []
	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.fog_state == "visible":
			continue
		if cell.floor_type == "none" and cell.solidity != "solid":
			continue  # Skip empty airspace
		fog_cells.append(cell)

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
		var cell: VoxelCell = fog_cells[i]
		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)
		world_pos.y += FOG_Y

		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)

		if cell.fog_state == "hidden":
			mm.set_instance_color(i, Color(0.0, 0.0, 0.0, 1.0))
		else:  # explored
			mm.set_instance_color(i, Color(0.0, 0.0, 0.0, 0.45))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var fog_mat := StandardMaterial3D.new()
	fog_mat.albedo_color = Color.WHITE
	fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_mat.vertex_color_use_as_albedo = true
	fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog_mat.render_priority = 1
	fog_mat.no_depth_test = true
	mmi.material_override = fog_mat
	mmi.name = "FogOverlay"
	return mmi


# ---------------------------------------------------------------------------
# Per-level grid lines (voxel)
# ---------------------------------------------------------------------------

## Build grid line outlines for all passable cells at a given level.
static func build_grid_lines_voxel(map: VoxelMapData, level: int) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "GridLines"

	# Collect non-solid cells first to avoid empty surface_end() error.
	var line_cells: Array = []
	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.solidity != "solid":
			line_cells.append(cell)

	if line_cells.is_empty():
		return mesh_inst

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	for cell: VoxelCell in line_cells:
		var center := VoxelGrid.cell_to_world(cell.col, cell.row, level)
		var y := center.y + GRID_LINE_Y

		var top    := Vector3(center.x, y, center.z - HALF_CELL)
		var right  := Vector3(center.x + HALF_CELL, y, center.z)
		var bottom := Vector3(center.x, y, center.z + HALF_CELL)
		var left   := Vector3(center.x - HALF_CELL, y, center.z)

		im.surface_add_vertex(top)
		im.surface_add_vertex(right)
		im.surface_add_vertex(right)
		im.surface_add_vertex(bottom)
		im.surface_add_vertex(bottom)
		im.surface_add_vertex(left)
		im.surface_add_vertex(left)
		im.surface_add_vertex(top)

	im.surface_end()

	mesh_inst.mesh = im
	mesh_inst.material_override = _get_material("grid_lines", Color(0.0, 0.0, 0.0, 0.5), true)
	return mesh_inst


# ---------------------------------------------------------------------------
# Per-level transition markers (voxel)
# ---------------------------------------------------------------------------

## Build transition cell markers for a given level.
static func build_transition_markers_voxel(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "TransitionMarkers"

	for tc_pos: Vector3i in map.transition_cells:
		if tc_pos.z != level:
			continue
		if map.get_fog(tc_pos) == "hidden":
			continue
		var world_pos := VoxelGrid.cell_to_world(tc_pos.x, tc_pos.y, level)

		var label := Label3D.new()
		label.text = "E"
		label.font_size = 24
		label.modulate = Color.GREEN
		label.position = world_pos + Vector3(0.0, 0.3, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.no_depth_test = true
		parent.add_child(label)

	return parent


# ---------------------------------------------------------------------------
# Per-level feature labels (voxel — door icons)
# ---------------------------------------------------------------------------

## Build door/feature label overlays for a given level.
static func build_feature_labels_voxel(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "FeatureLabels"

	for cell: VoxelCell in map.get_cells_at_level(level):
		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)

		var label_text := ""
		var label_color := Color.WHITE

		if cell.door_state.is_empty():
			if cell.feature == "lever":
				label_text = "⚙"
				label_color = Color(0.8, 0.7, 0.4)
		elif cell.door_state == "destroyed":
			pass
		elif cell.door_type == "portcullis":
			if cell.door_state != "open":
				label_text = "P"
				label_color = Color.YELLOW
		elif cell.door_type == "secret":
			if cell.door_detected:
				if cell.door_state == "open":
					label_text = "○"
				else:
					label_text = "?"
			else:
				label_text = "S"
				label_color = Color(1.0, 0.9, 0.2)
		elif cell.door_type == "arch":
			label_text = "A"
			label_color = Color(1.0, 1.0, 0.8)
		elif cell.door_state == "open":
			label_text = "○"
		elif cell.door_state == "locked":
			label_text = "L"
			label_color = Color.YELLOW
		elif cell.door_state == "stuck":
			label_text = "K"
			label_color = Color.ORANGE_RED
		else:
			label_text = "X"

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
# Highlight overlay (voxel — Vector3i positions)
# ---------------------------------------------------------------------------

## Build a highlight overlay for a set of Vector3i cells.
static func build_highlight_overlay_voxel(
		cells: Array[Vector3i], color: Color,
		_map: VoxelMapData = null) -> MultiMeshInstance3D:
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
		var pos: Vector3i = cells[i]
		var world_pos := VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
		world_pos.y += HIGHLIGHT_Y

		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, color)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
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


# ---------------------------------------------------------------------------
# Level group assembly (voxel)
# ---------------------------------------------------------------------------

## Multiply the albedo_color of every tintable mesh in [param group] by
## [param tint], preserving each mesh's stored base_color.
##
## Per GDD §16.2 per-level visibility table: focus level renders at full
## brightness (tint = Color.WHITE); levels below focus render dimmed
## (tint = DIM_COLOR ≈ Color(0.6, 0.6, 0.6)).
##
## Tints FloorSlabs / Walls / Doors / Features. Skips GridLines, FogOverlay,
## TransitionMarkers, and Label3Ds (labels use .modulate, not albedo; the
## labels left untinted on dimmed levels is an accepted minor limitation).
static func set_level_group_tint(group: Node3D, tint: Color) -> void:
	if group == null:
		return
	for child in group.get_children():
		match child.name:
			"FloorSlabs", "Walls":
				if child is GeometryInstance3D:
					_apply_tint_to_mesh(child, tint)
				else:
					# "Walls" may be a Node3D container (individual-walls path)
					for mesh in child.get_children():
						if mesh is GeometryInstance3D:
							_apply_tint_to_mesh(mesh, tint)
			"Doors", "Features":
				for mesh in child.get_children():
					if mesh is GeometryInstance3D:
						_apply_tint_to_mesh(mesh, tint)
			# Skip GridLines, FogOverlay, TransitionMarkers, FeatureLabels.
			_:
				pass


## Multiply a single mesh's material_override.albedo_color by [param tint],
## using the mesh's stored "base_color" metadata as the source color.
static func _apply_tint_to_mesh(mesh: GeometryInstance3D, tint: Color) -> void:
	var mat := mesh.material_override
	if mat == null or not (mat is StandardMaterial3D):
		return
	var smat: StandardMaterial3D = mat
	var base: Color = mesh.get_meta("base_color", Color.WHITE)
	smat.albedo_color = Color(
		base.r * tint.r,
		base.g * tint.g,
		base.b * tint.b,
		base.a * tint.a,
	)


## Build a complete per-level Node3D containing FloorSlabs, Walls, Doors,
## Features, FeatureLabels, GridLines, FogOverlay, TransitionMarkers.
## Per GDD §17.3 scene tree structure.
## [param use_individual_walls]: true for focus level (enables occlusion fade).
static func build_level_group(
		map: VoxelMapData, level: int, color_func: Callable,
		use_individual_walls: bool = false) -> Node3D:
	var group := Node3D.new()
	group.name = "Level_%d" % level

	# Floor slabs
	group.add_child(build_floor_multimesh_voxel(map, level, color_func))

	# Walls (individual for focus level, MultiMesh otherwise)
	if use_individual_walls:
		group.add_child(build_walls_voxel_individual(map, level))
	else:
		group.add_child(build_walls_voxel(map, level))

	# Doors
	group.add_child(build_doors_voxel(map, level))

	# Features (stairs, ramps, ladders)
	group.add_child(build_features_voxel(map, level))

	# Feature labels (door icons, lever icons)
	group.add_child(build_feature_labels_voxel(map, level))

	# Grid lines
	group.add_child(build_grid_lines_voxel(map, level))

	# Fog overlay
	group.add_child(build_fog_overlay_voxel(map, level))

	# Transition markers
	group.add_child(build_transition_markers_voxel(map, level))

	return group


# ---------------------------------------------------------------------------
# Voxel screen-to-cell
# ---------------------------------------------------------------------------

## Raycast from screen position onto the focus level's Y plane,
## then convert to a Vector3i grid cell.
static func screen_to_cell_voxel(
		camera: Camera3D, screen_pos: Vector2,
		focus_level: int) -> Vector3i:
	var plane_y: float = float(focus_level) * VoxelGrid.CELL_SIZE
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return Vector3i(-1, -1, -1)
	var t := (plane_y - origin.y) / direction.y
	var hit := origin + direction * t
	return VoxelGrid.world_to_cell(hit)


# ===========================================================================
# TERRAIN BATTLE-MAP BUILDERS — generated wilderness maps
# (gdd-combat-map-generation.md §11.2). Placeholder visuals: per-floor-type
# texture painting, terrain-column cubes, color/shape-coded obstacle
# primitives from BattleMapObstacleCatalog (key: docs/tactical-map-obstacle-key.md),
# and water/lava planes reusing the hexmap water look.
# ===========================================================================

## floor_type → texture path for terrain surface painting. Reuses the
## wilderness hexmap texture set as placeholder ground detail.
const TERRAIN_FLOOR_TEXTURES: Dictionary = {
	"grass": "res://assets/floors/grass_green_bright.png",
	"dirt": "res://assets/wilderness_textures/savanna.png",
	"stone": "res://assets/wilderness_textures/mountain.png",
	"sand": "res://assets/wilderness_textures/desert.png",
	"mud": "res://assets/wilderness_textures/swamp.png",
	"snow": "res://assets/wilderness_textures/snow.png",
	"gravel": "res://assets/wilderness_textures/badlands.png",
	"lava_rock": "res://assets/wilderness_textures/volcanic.png",
	"wood": "res://assets/walls/wood_oak_weathered.png",
}

## Terrain-column side texture (exposed earth/rock).
const TERRAIN_COLUMN_TEXTURE := "res://assets/wilderness_textures/mountain.png"

## Water/lava surface plane heights within a cell (cell bottom = level * 1.0).
const WATER_SHALLOW_PLANE_Y := 0.18
const WATER_DEEP_PLANE_Y := 0.65
const LAVA_PLANE_Y := 0.35


## Builds floor slabs for a terrain map level, batched per floor_type so each
## surface gets its own texture ("map texture painting"). Slight per-instance
## tint variation breaks up the tiling.
static func build_terrain_floor_voxel(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "FloorSlabs"

	var by_floor: Dictionary = {}
	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.floor_type == "none" or cell.solidity == "solid":
			continue
		if not by_floor.has(cell.floor_type):
			by_floor[cell.floor_type] = []
		(by_floor[cell.floor_type] as Array).append(cell)

	for floor_type: String in by_floor:
		var cells: Array = by_floor[floor_type]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = get_diamond_mesh()
		mm.instance_count = cells.size()
		for i in range(cells.size()):
			var cell: VoxelCell = cells[i]
			var xform := Transform3D.IDENTITY
			xform.origin = VoxelGrid.cell_to_world(cell.col, cell.row, level)
			mm.set_instance_transform(i, xform)
			# Deterministic per-cell shade variation (no RNG — position hash).
			var shade: float = 0.88 + 0.24 * float((cell.col * 31 + cell.row * 17) % 8) / 8.0
			mm.set_instance_color(i, Color(shade, shade, shade))

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = floor_color_for_voxel(floor_type)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tex_path: String = TERRAIN_FLOOR_TEXTURES.get(floor_type, "")
		if not tex_path.is_empty():
			var tex := _load_texture(tex_path)
			if tex != null:
				mat.albedo_texture = tex
				mat.uv1_scale = Vector3(FLOOR_UV_SCALE, FLOOR_UV_SCALE, FLOOR_UV_SCALE)
				mat.texture_filter = \
					BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mmi.material_override = mat
		mmi.name = "Floor_%s" % floor_type
		mmi.set_meta("base_color", mat.albedo_color)
		parent.add_child(mmi)

	return parent


## Builds the solid terrain mass ("earth" cells) for a level as one MultiMesh
## of soil-toned cubes — the visible flanks of hills, bluffs, and cliff faces.
static func build_terrain_columns_voxel(map: VoxelMapData, level: int) -> MultiMeshInstance3D:
	var earth_cells: Array = []
	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.solidity == "solid" and cell.feature == "earth":
			earth_cells.append(cell)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TerrainColumns"
	if earth_cells.is_empty():
		return mmi

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = get_cube_mesh()
	mm.instance_count = earth_cells.size()
	var base_color := wall_color_for_voxel("earth")
	for i in range(earth_cells.size()):
		var cell: VoxelCell = earth_cells[i]
		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)
		world_pos.y += 0.5
		var xform := Transform3D.IDENTITY
		xform.origin = world_pos
		mm.set_instance_transform(i, xform)
		var shade: float = 0.85 + 0.3 * float((cell.col * 13 + cell.row * 7) % 8) / 8.0
		mm.set_instance_color(i, base_color * Color(shade, shade, shade))

	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex := _load_texture(TERRAIN_COLUMN_TEXTURE)
	if tex != null:
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(WALL_UV_SCALE, WALL_UV_SCALE, WALL_UV_SCALE)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mmi.material_override = mat
	mmi.set_meta("base_color", Color.WHITE)
	return mmi


## Builds water and lava surface planes for a level. The material reuses the
## hexmap river-water look (color/params from hex_map_renderer_3d._river_material)
## per the asset-reuse ruling; the animated river shader can replace this once
## the tactical water pass gets its own art session.
static func build_water_overlay_voxel(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "WaterOverlay"

	var groups: Dictionary = {"water_shallow": [], "water_deep": [], "lava": []}
	for cell: VoxelCell in map.get_cells_at_level(level):
		if groups.has(cell.feature):
			(groups[cell.feature] as Array).append(cell)

	for feature: String in groups:
		var cells: Array = groups[feature]
		if cells.is_empty():
			continue
		var plane_y: float
		match feature:
			"water_shallow": plane_y = WATER_SHALLOW_PLANE_Y
			"water_deep": plane_y = WATER_DEEP_PLANE_Y
			_: plane_y = LAVA_PLANE_Y

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = get_diamond_mesh()
		mm.instance_count = cells.size()
		for i in range(cells.size()):
			var cell: VoxelCell = cells[i]
			var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)
			world_pos.y += plane_y
			var xform := Transform3D.IDENTITY
			xform.origin = world_pos
			mm.set_instance_transform(i, xform)

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _water_surface_material(feature)
		mmi.name = "Water_%s" % feature
		mmi.set_meta("base_color", Color.WHITE)
		parent.add_child(mmi)

	return parent


## Water/lava surface material. Mirrors the hexmap river material parameters
## (hex_map_renderer_3d.gd _river_material: albedo 0.20/0.48/0.74, alpha
## transparency, low roughness, faint emission) so tactical water reads the
## same as overland water.
static func _water_surface_material(feature: String) -> StandardMaterial3D:
	var key := "terrain_water_%s" % feature
	if _material_cache.has(key):
		return _material_cache[key]
	var m := StandardMaterial3D.new()
	var entry: Dictionary = BattleMapObstacleCatalog.OBSTACLES.get(feature, {})
	m.albedo_color = entry.get("color", Color(0.20, 0.48, 0.74, 0.95))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.1
	m.metallic = 0.0
	m.metallic_specular = 0.8
	m.emission_enabled = true
	if feature == "lava":
		m.emission = Color(0.85, 0.30, 0.05)
		m.emission_energy_multiplier = 1.4
	else:
		m.emission = Color(0.05, 0.16, 0.26)
		m.emission_energy_multiplier = 0.5
	_material_cache[key] = m
	return m


## Builds color/shape-coded placeholder meshes for every catalog obstacle on a
## level (docs/tactical-map-obstacle-key.md is the player-facing key). Water
## and lava are handled by build_water_overlay_voxel, not here.
static func build_obstacles_voxel(map: VoxelMapData, level: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Obstacles"

	for cell: VoxelCell in map.get_cells_at_level(level):
		var entry: Dictionary = BattleMapObstacleCatalog.OBSTACLES.get(cell.feature, {})
		if entry.is_empty() or entry.get("shape", "") == "surface":
			continue
		var world_pos := VoxelGrid.cell_to_world(cell.col, cell.row, level)
		var color: Color = entry["color"]
		var shape: String = entry["shape"]
		# Deterministic per-cell jitter (no RNG — position hash).
		var jitter: float = float((cell.col * 41 + cell.row * 23) % 90)
		match shape:
			"canopy":
				var trunk := _feature_box(Vector3(0.12, 0.45, 0.12), Color(0.36, 0.26, 0.16))
				trunk.position = world_pos + Vector3(0.0, 0.22, 0.0)
				parent.add_child(trunk)
				var canopy := _obstacle_sphere(0.34, color)
				canopy.position = world_pos + Vector3(0.0, 0.62, 0.0)
				parent.add_child(canopy)
			"trunk":
				var trunk := _feature_box(Vector3(0.14, 0.8, 0.14), color)
				trunk.position = world_pos + Vector3(0.0, 0.4, 0.0)
				trunk.rotation_degrees.y = jitter
				parent.add_child(trunk)
			"rock":
				var rock := _feature_box(Vector3(0.55, 0.5, 0.5), color)
				rock.position = world_pos + Vector3(0.0, 0.25, 0.0)
				rock.rotation_degrees.y = jitter
				parent.add_child(rock)
			"rock_low":
				for k in range(3):
					var stone := _feature_box(Vector3(0.22, 0.18, 0.2), color)
					var angle: float = jitter + float(k) * 120.0
					stone.position = world_pos + Vector3(
						cos(deg_to_rad(angle)) * 0.16, 0.09 + float(k % 2) * 0.05,
						sin(deg_to_rad(angle)) * 0.16)
					stone.rotation_degrees.y = angle
					parent.add_child(stone)
			"mass":
				var mass := _feature_box(Vector3(CELL_SIZE * 0.8, 0.85, CELL_SIZE * 0.8), color)
				mass.position = world_pos + Vector3(0.0, 0.42, 0.0)
				mass.rotation_degrees.y = 45.0
				parent.add_child(mass)
			"line_low":
				var rail := _feature_box(Vector3(CELL_SIZE * 0.9, 0.28, 0.16), color)
				rail.position = world_pos + Vector3(0.0, 0.14, 0.0)
				rail.rotation_degrees.y = _line_orientation(map, cell, level)
				parent.add_child(rail)
			"line_tall":
				var hedge := _feature_box(Vector3(CELL_SIZE * 0.95, 0.75, 0.32), color)
				hedge.position = world_pos + Vector3(0.0, 0.38, 0.0)
				hedge.rotation_degrees.y = _line_orientation(map, cell, level)
				parent.add_child(hedge)
			"log":
				var log_box := _feature_box(Vector3(CELL_SIZE * 0.85, 0.2, 0.2), color)
				log_box.position = world_pos + Vector3(0.0, 0.1, 0.0)
				log_box.rotation_degrees.y = _line_orientation(map, cell, level)
				parent.add_child(log_box)
			"tuft":
				for k in range(2):
					var tuft := _obstacle_sphere(0.17, color)
					var angle: float = jitter + float(k) * 180.0
					tuft.position = world_pos + Vector3(
						cos(deg_to_rad(angle)) * 0.14, 0.12,
						sin(deg_to_rad(angle)) * 0.14)
					parent.add_child(tuft)

	return parent


## An unshaded sphere MeshInstance3D with "base_color" meta (tint-compatible).
static func _obstacle_sphere(radius: float, color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.7
	sphere.radial_segments = 10
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inst := MeshInstance3D.new()
	inst.mesh = sphere
	inst.material_override = mat
	inst.set_meta("base_color", color)
	return inst


## Orients a linear obstacle (fence/hedgerow/wall/log) along its run: if a 2D
## neighbor carries the same feature, the mesh points at that neighbor's world
## position; isolated segments default to the diamond's 45°.
static func _line_orientation(map: VoxelMapData, cell: VoxelCell, level: int) -> float:
	var here := Vector3i(cell.col, cell.row, level)
	var here_world := VoxelGrid.cell_to_world(cell.col, cell.row, level)
	for nb: Vector3i in VoxelGrid.get_neighbors_2d(here):
		# Linear features on terrain follow the surface, so the neighbor
		# segment may sit one level up/down — match on column feature.
		var nz: int = map.surface_level_at(nb.x, nb.y)
		if nz < 0:
			continue
		if map.get_cell(Vector3i(nb.x, nb.y, nz)).feature == cell.feature:
			var nb_world := VoxelGrid.cell_to_world(nb.x, nb.y, nz)
			var edge := nb_world - here_world
			return rad_to_deg(atan2(edge.x, edge.z)) + 90.0
	return 45.0


## Assembles the complete per-level Node3D for a generated terrain battle map:
## textured floor batches, terrain columns, non-terrain walls (farmstead),
## obstacle placeholders, water/lava planes, and grid lines. No fog/door/
## transition builders — outdoor daylight maps have none of those.
static func build_terrain_level_group(map: VoxelMapData, level: int) -> Node3D:
	var group := Node3D.new()
	group.name = "Level_%d" % level
	group.add_child(build_terrain_floor_voxel(map, level))
	group.add_child(build_terrain_columns_voxel(map, level))
	group.add_child(build_walls_voxel(map, level))
	group.add_child(build_obstacles_voxel(map, level))
	group.add_child(build_water_overlay_voxel(map, level))
	group.add_child(build_grid_lines_voxel(map, level))
	return group


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
