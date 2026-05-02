extends Control

## OffscreenPartyIndicators — edge arrows pointing toward focus-level party
## members who are outside the camera viewport.
##
## Attached as a child of the DungeonHUD CanvasLayer, anchored full-rect.
## Reads the renderer's focus-level party tokens each frame and draws an
## arrow clamped to the viewport edge for each one that is off-screen.
##
## See gdd-voxel-tactical-architecture.md §16.4.


const ARROW_LENGTH: float = 18.0
const ARROW_HALF_WIDTH: float = 9.0
const EDGE_MARGIN: float = 30.0
const ARROW_COLOR := Color(0.4, 0.8, 1.0, 0.85)
const ARROW_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.8)


var _camera: Camera3D = null
var _visibility_manager: VisibilityManager = null
var _renderer: Node = null


func _ready() -> void:
	add_to_group("hud_offscreen_party_indicators")  # H.0 — HudVisibilityController hides while notebook is open
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(camera: Camera3D, vis: VisibilityManager, renderer: Node) -> void:
	_camera = camera
	_visibility_manager = vis
	_renderer = renderer


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _camera == null or _visibility_manager == null or _renderer == null:
		return
	if not _renderer.has_method("get_party_focus_tokens"):
		return

	var rect := get_rect()
	var center := rect.get_center()
	var entries: Array = _renderer.get_party_focus_tokens()
	for entry in entries:
		var world_pos: Vector3 = entry["world_pos"]
		var screen_pos: Vector2 = _camera.unproject_position(world_pos)
		var behind: bool = _camera.is_position_behind(world_pos)
		if behind:
			# Reflect through viewport center so the arrow points the right way.
			screen_pos = center * 2.0 - screen_pos

		var on_screen: bool = not behind and rect.has_point(screen_pos)
		if on_screen:
			continue

		var edge_pos := _clamp_to_edge(screen_pos, rect)
		_draw_arrow(edge_pos, center)


func _clamp_to_edge(pos: Vector2, rect: Rect2) -> Vector2:
	var minp := rect.position + Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var maxp := rect.position + rect.size - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	return Vector2(
		clampf(pos.x, minp.x, maxp.x),
		clampf(pos.y, minp.y, maxp.y)
	)


func _draw_arrow(tip: Vector2, center: Vector2) -> void:
	var direction := (tip - center)
	if direction.length_squared() < 0.01:
		return
	direction = direction.normalized()
	var back := -direction * ARROW_LENGTH
	var perp := Vector2(-direction.y, direction.x) * ARROW_HALF_WIDTH
	var p1 := tip
	var p2 := tip + back + perp
	var p3 := tip + back - perp
	draw_colored_polygon([p1, p2, p3], ARROW_COLOR)
	draw_polyline([p1, p2, p3, p1], ARROW_OUTLINE_COLOR, 2.0)
