extends Node3D

## 3D visual overlay for pending exploration orders on the dungeon map.
##
## Renders ghost trail dots along queued move paths, ghost spheres at
## destinations, and order icon labels (Label3D) for non-move orders.
##
## Child of the 3D dungeon map renderer. Same API as the 2D version.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DOT_RADIUS := 0.03
const DOT_COLOR := Color(0.8, 0.8, 1.0, 0.4)
const GHOST_COLOR := Color(0.6, 0.6, 0.9, 0.3)
const GHOST_RADIUS := 0.08
const LINE_COLOR := Color(0.8, 0.8, 1.0, 0.2)
const Y_OFFSET := 0.1  ## Slightly above floor

const ORDER_ICONS := {
	"search": "🔍",
	"listen": "👂",
	"wait": "⏳",
	"interact_door": "🚪",
}

const ORDER_ICON_COLORS := {
	"search": Color(1.0, 0.9, 0.3, 0.8),
	"listen": Color(0.7, 1.0, 0.7, 0.8),
	"wait": Color(0.6, 0.6, 0.6, 0.7),
	"interact_door": Color(0.9, 0.6, 0.3, 0.8),
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _draw_data: Array = []


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the overlay with the current set of pending orders.
## [param orders]: Dictionary from DungeonOrderManager.get_all_orders()
##   { entity_id -> { order_type, target_pos, path } }
func update_overlays(orders: Dictionary) -> void:
	_draw_data.clear()
	for eid in orders:
		var order: Dictionary = orders[eid]
		_draw_data.append({
			"entity_id": eid,
			"order_type": order.get("order_type", ""),
			"target_pos": order.get("target_pos", Vector2i(-1, -1)),
			"path": order.get("path", []),
		})
	_rebuild()


## Clear all overlay graphics.
func clear_overlays() -> void:
	_draw_data.clear()
	_clear_children()


# ---------------------------------------------------------------------------
# Rebuild
# ---------------------------------------------------------------------------

func _clear_children() -> void:
	for child in get_children():
		child.queue_free()


func _rebuild() -> void:
	_clear_children()

	for entry in _draw_data:
		var order_type: String = entry["order_type"]
		var target_pos: Vector2i = entry["target_pos"]
		var path: Array = entry["path"]

		match order_type:
			"move":
				_build_move_path(path, target_pos)
			"search", "listen", "wait", "interact_door":
				_build_order_icon(target_pos, order_type)


func _build_move_path(path: Array, _target_pos: Vector2i) -> void:
	if path.is_empty():
		return

	# Dot spheres along path
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = DOT_RADIUS
	sphere_mesh.height = DOT_RADIUS * 2.0
	sphere_mesh.radial_segments = 8
	sphere_mesh.rings = 4

	var dot_mat := StandardMaterial3D.new()
	dot_mat.albedo_color = DOT_COLOR
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var ghost_sphere := SphereMesh.new()
	ghost_sphere.radius = GHOST_RADIUS
	ghost_sphere.height = GHOST_RADIUS * 2.0
	ghost_sphere.radial_segments = 12
	ghost_sphere.rings = 6

	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = GHOST_COLOR
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for i in range(path.size()):
		var cell: Vector2i = path[i]
		var world_pos := TacticalGrid3D.cell_to_world(cell.x, cell.y)
		world_pos.y += Y_OFFSET

		var mesh_inst := MeshInstance3D.new()
		if i < path.size() - 1:
			mesh_inst.mesh = sphere_mesh
			mesh_inst.material_override = dot_mat
		else:
			# Destination: larger ghost sphere
			mesh_inst.mesh = ghost_sphere
			mesh_inst.material_override = ghost_mat
		mesh_inst.position = world_pos
		add_child(mesh_inst)

	# Connecting lines
	if path.size() >= 2:
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(path.size() - 1):
			var from_pos := TacticalGrid3D.cell_to_world(path[i].x, path[i].y)
			var to_pos := TacticalGrid3D.cell_to_world(path[i + 1].x, path[i + 1].y)
			from_pos.y += Y_OFFSET
			to_pos.y += Y_OFFSET
			im.surface_add_vertex(from_pos)
			im.surface_add_vertex(to_pos)
		im.surface_end()

		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = LINE_COLOR
		line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		var line_inst := MeshInstance3D.new()
		line_inst.mesh = im
		line_inst.material_override = line_mat
		add_child(line_inst)


func _build_order_icon(pos: Vector2i, order_type: String) -> void:
	if pos == Vector2i(-1, -1):
		return

	var world_pos := TacticalGrid3D.cell_to_world(pos.x, pos.y)
	world_pos.y += 0.3  # Float above floor

	var icon_text: String = ORDER_ICONS.get(order_type, "?")
	var icon_color: Color = ORDER_ICON_COLORS.get(order_type, Color.WHITE)

	var label := Label3D.new()
	label.text = icon_text
	label.font_size = 28
	label.modulate = icon_color
	label.position = world_pos
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.no_depth_test = true
	add_child(label)
