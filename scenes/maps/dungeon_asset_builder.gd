class_name DungeonAssetBuilder
extends RefCounted

## Asset-based per-level geometry builder — the Quaternius-kit counterpart to
## TacticalGrid3D's code-generated build_*_voxel statics. Instantiates `.glb`
## scenes via a DungeonAssetRegistry and places them on the voxel diamond grid
## using edge-resolved walls (WallEdgeResolver / Strategy A).
##
## Output mirrors TacticalGrid3D.build_level_group: a "Level_%d" Node3D with
## named children FloorSlabs / Walls / Doors / Features, so the renderer's
## _apply_level_visibility (parses the level number off the node name) and the
## level-group plumbing work unchanged. See
## generation/gdd-dungeon-asset-integration-plan.md §5, §7.
##
## GEOMETRY (VoxelGrid diamond layout, see voxel_grid.gd):
##   cell_to_world(col,row,level) = ((col-row)*0.5, level*1.0, (col+row)*0.5)
##   - Cells are 0.707 apart (the col/row axes are the world 45° diagonals).
##   - WALLS: uniform kit_scale (0.5) -> 1.0 long x 1.0 tall = one cell edge,
##     one full level. Placed at the edge midpoint (0.25 diagonal from cell
##     center), rotated ±45° to lie along the diamond edge. The 1.0 length
##     slightly overhangs the 0.707 edge, which fills corners (GDD §3.1).
##   - FLOORS: scale kit_scale/√2 (~0.354) + 45° Y rotation, so the square
##     Quaternius tile becomes a diamond that tessellates the cell grid.
##
## NOTE: scene/ scripts are NOT loaded by the headless test suite, so verify
## this file with `--check-only -s` after edits (see project memory).


## PackedScene cache, keyed by res:// path. Shared across builds.
static var _scene_cache: Dictionary = {}

## Flat-matte environment cel shader (gdd-art-direction.md §7).
const _ENV_SHADER_PATH := "res://engine/shaders/cel_environment.gdshader"
## Loaded shader, lazily cached.
static var _env_shader: Shader = null
## cel_environment ShaderMaterials keyed by source albedo color ("r,g,b"), so the
## whole dungeon shares ~one material per distinct Quaternius palette color.
static var _env_material_cache: Dictionary = {}

## Per-edge placement geometry: world half-delta from cell center to the edge
## midpoint, plus the Y rotation that lays a wall along that edge. Keyed by
## WallEdgeResolver.EdgeDir.
const _EDGE_GEOM: Dictionary = {
	WallEdgeResolver.EdgeDir.N: {"half_delta": Vector3(0.25, 0.0, -0.25), "rot_y": -45.0},
	WallEdgeResolver.EdgeDir.S: {"half_delta": Vector3(-0.25, 0.0, 0.25), "rot_y": -45.0},
	WallEdgeResolver.EdgeDir.E: {"half_delta": Vector3(0.25, 0.0, 0.25), "rot_y": 45.0},
	WallEdgeResolver.EdgeDir.W: {"half_delta": Vector3(-0.25, 0.0, -0.25), "rot_y": 45.0},
}


# ---------------------------------------------------------------------------
# Level group assembly
# ---------------------------------------------------------------------------

## Build a complete asset-based level group for [param level]. Mirrors
## TacticalGrid3D.build_level_group's node structure.
static func build_level_group(
		map: VoxelMapData, level: int, registry: DungeonAssetRegistry) -> Node3D:
	var group := Node3D.new()
	group.name = "Level_%d" % level
	group.add_child(build_floors(map, level, registry))
	group.add_child(build_walls(map, level, registry))
	group.add_child(build_doors(map, level, registry))
	group.add_child(build_features(map, level, registry))
	# Apply the matte env shader to the kit geometry only — BEFORE the overlays
	# below, which carry their own (fog/grid/label) materials and must not be
	# converted.
	if registry.use_cel_environment:
		_apply_environment_materials(group)
	# Kit-agnostic overlays reused verbatim from the code-generated builder: these
	# are not asset geometry (fog of war, grid lines, door/lever icon labels, exit
	# markers), so the asset path shares them rather than reimplementing. Their
	# node names (FogOverlay/GridLines/FeatureLabels/TransitionMarkers) match what
	# set_level_group_tint and _apply_level_visibility expect.
	group.add_child(TacticalGrid3D.build_feature_labels_voxel(map, level))
	group.add_child(TacticalGrid3D.build_grid_lines_voxel(map, level))
	group.add_child(TacticalGrid3D.build_fog_overlay_voxel(map, level))
	group.add_child(TacticalGrid3D.build_transition_markers_voxel(map, level))
	return group


# ---------------------------------------------------------------------------
# Floors
# ---------------------------------------------------------------------------

## One floor tile per floored air cell. Scaled + rotated to tessellate the
## diamond grid.
static func build_floors(
		map: VoxelMapData, level: int, registry: DungeonAssetRegistry) -> Node3D:
	var parent := Node3D.new()
	parent.name = "FloorSlabs"
	var floor_scale: float = registry.kit_scale / sqrt(2.0)

	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.solidity != "air" or cell.floor_type == "none":
			continue
		var path := registry.floor_scene_for(cell.floor_type, cell.feature)
		var inst := _instance(path)
		if inst == null:
			continue
		inst.position = VoxelGrid.cell_to_world(cell.col, cell.row, level)
		inst.rotation_degrees = Vector3(0.0, 45.0, 0.0)
		inst.scale = Vector3(floor_scale, registry.kit_scale, floor_scale)
		inst.set_meta("cell_pos", Vector3i(cell.col, cell.row, level))
		parent.add_child(inst)

	return parent


# ---------------------------------------------------------------------------
# Walls (edge-resolved)
# ---------------------------------------------------------------------------

## One wall per floored-air-cell edge whose neighbor is solid.
static func build_walls(
		map: VoxelMapData, level: int, registry: DungeonAssetRegistry) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Walls"
	var s: float = registry.kit_scale

	for edge: Dictionary in WallEdgeResolver.resolve_level(map, level):
		var air_cell: Vector3i = edge["air_cell"]
		var edge_dir: int = edge["edge_dir"]
		var solid_pos: Vector3i = edge["neighbor_solid"]

		var solid_feature: String = map.get_cell(solid_pos).feature
		var path := registry.wall_scene_for(solid_feature)
		var inst := _instance(path)
		if inst == null:
			continue

		var geom: Dictionary = _EDGE_GEOM[edge_dir]
		var base := VoxelGrid.cell_to_world(air_cell.x, air_cell.y, level)
		inst.position = base + (geom["half_delta"] as Vector3)
		inst.rotation_degrees = Vector3(0.0, geom["rot_y"], 0.0)
		inst.scale = Vector3(s, s, s)
		# Fade/index metadata (consumed by the camera-occlusion pass, Increment 3).
		inst.set_meta("wall_air_cell", air_cell)
		inst.set_meta("wall_solid_cell", solid_pos)
		inst.set_meta("edge_dir", edge_dir)
		parent.add_child(inst)

	return parent


# ---------------------------------------------------------------------------
# Doors
# ---------------------------------------------------------------------------

## One door per cell with a door (skipping destroyed and undetected-secret).
static func build_doors(
		map: VoxelMapData, level: int, registry: DungeonAssetRegistry) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Doors"
	var s: float = registry.kit_scale

	for cell: VoxelCell in map.get_cells_at_level(level):
		if cell.door_state.is_empty() or cell.door_state == "destroyed":
			continue
		if cell.door_type == "secret" and not cell.door_detected:
			continue

		var path := registry.door_scene_for(cell.door_type)
		var inst := _instance(path)
		if inst == null:
			continue

		var pos := Vector3i(cell.col, cell.row, level)
		inst.position = VoxelGrid.cell_to_world(cell.col, cell.row, level)
		inst.rotation_degrees = Vector3(0.0, _door_rotation(pos, map), 0.0)
		inst.scale = Vector3(s, s, s)

		# Open swing doors: swing each leaf 90° about its hinge. Curtain/single-
		# mesh and placeholder doors have no leaves to swing — left as-is.
		if cell.door_state == "open":
			for leaf in inst.get_children():
				if leaf is Node3D:
					(leaf as Node3D).rotate_y(deg_to_rad(90.0))

		inst.set_meta("cell_pos", pos)
		inst.set_meta("door_type", cell.door_type)
		parent.add_child(inst)

	return parent


# ---------------------------------------------------------------------------
# Features (stairs)
# ---------------------------------------------------------------------------

## Stair pieces. Ladders/levers/fountains keep the code-generated geometry for
## now (Quaternius ships none — O-DA-3 defer), so they are not emitted here.
static func build_features(
		map: VoxelMapData, level: int, registry: DungeonAssetRegistry) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Features"
	var s: float = registry.kit_scale

	for cell: VoxelCell in map.get_cells_at_level(level):
		if not cell.feature.begins_with("stairs_"):
			continue
		var inst := _instance(registry.stair_scene())
		if inst == null:
			continue
		inst.position = VoxelGrid.cell_to_world(cell.col, cell.row, level)
		inst.rotation_degrees = Vector3(0.0, _stair_rotation(cell.feature), 0.0)
		inst.scale = Vector3(s, s, s)
		inst.set_meta("cell_pos", Vector3i(cell.col, cell.row, level))
		parent.add_child(inst)

	return parent


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate a cached PackedScene at [param path] as a Node3D, or null if the
## path is empty/unloadable.
static func _instance(path: String) -> Node3D:
	if path.is_empty():
		return null
	var packed: PackedScene = _load_scene(path)
	if packed == null:
		return null
	var node := packed.instantiate()
	return node as Node3D


static func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	if not ResourceLoader.exists(path):
		push_warning("DungeonAssetBuilder: missing asset '%s'" % path)
		_scene_cache[path] = null
		return null
	var packed: PackedScene = load(path)
	_scene_cache[path] = packed
	return packed


## Door Y rotation. A door spans ACROSS the corridor (perpendicular to the
## flanking walls), not along it. In the diamond layout the col/row axes are the
## world 45° diagonals, so:
##   - EW corridor (air E & W) -> door lies on the N-S diagonal -> +45°
##   - NS corridor (air N & S), or ambiguous -> door lies on the E-W diagonal -> -45°
## NOTE: TacticalGrid3D._compute_door_orientation_voxel (the code-generated path)
## returns the OPPOSITE — its doors lie ALONG the corridor (90° off). It shares
## this bug but is out of scope here; flagged for a follow-up fix.
static func _door_rotation(pos: Vector3i, map: VoxelMapData) -> float:
	var ew: bool = _is_passage(Vector3i(pos.x + 1, pos.y, pos.z), map) \
		and _is_passage(Vector3i(pos.x - 1, pos.y, pos.z), map)
	var ns: bool = _is_passage(Vector3i(pos.x, pos.y - 1, pos.z), map) \
		and _is_passage(Vector3i(pos.x, pos.y + 1, pos.z), map)
	if ew and not ns:
		return 45.0
	return -45.0


static func _is_passage(pos: Vector3i, map: VoxelMapData) -> bool:
	if not map.has_cell(pos):
		return false
	var cell: VoxelCell = map.get_cell(pos)
	return cell.solidity == "air" and cell.door_state.is_empty() \
		and cell.feature in ["open", "ladder"]


## Stair Y rotation from the direction suffix ("stairs_up_N" .. "stairs_down_SW").
## Mirrors TacticalGrid3D._stair_direction_rotation.
static func _stair_rotation(feature: String) -> float:
	var parts := feature.split("_")
	if parts.size() < 3:
		return 45.0
	match parts[2]:
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
# Environment cel shader (flat matte, gdd-art-direction.md §7)
# ---------------------------------------------------------------------------

## Replace every surface material under [param root] with a shared
## cel_environment ShaderMaterial that preserves the surface's flat Quaternius
## color via albedo_tint. No-op if the shader is unavailable.
static func _apply_environment_materials(root: Node) -> void:
	var shader := _get_env_shader()
	if shader == null:
		return
	for mesh_inst: MeshInstance3D in _all_mesh_instances(root):
		if mesh_inst.mesh == null:
			continue
		for i in range(mesh_inst.mesh.get_surface_count()):
			var color := Color.WHITE
			var src := mesh_inst.get_active_material(i)
			if src is BaseMaterial3D:
				color = (src as BaseMaterial3D).albedo_color
			mesh_inst.set_surface_override_material(i, _env_material_for(color, shader))


## Shared cel_environment material for a given flat color (cached by color).
static func _env_material_for(color: Color, shader: Shader) -> ShaderMaterial:
	var key := "%.4f,%.4f,%.4f" % [color.r, color.g, color.b]
	if _env_material_cache.has(key):
		return _env_material_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tint", color)
	_env_material_cache[key] = mat
	return mat


static func _get_env_shader() -> Shader:
	if _env_shader == null and ResourceLoader.exists(_ENV_SHADER_PATH):
		_env_shader = load(_ENV_SHADER_PATH)
	return _env_shader


## Recursively collects MeshInstance3D descendants of [param node].
static func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		if child.get_child_count() > 0:
			out.append_array(_all_mesh_instances(child))
	return out
