extends Node2D

## Top-down settlement map renderer: irregular polygon blocks, street graph,
## POI markers, building labels, and party token.
##
## No class_name — this is a scene script, not a reusable type.
##
## Implements the ManagedScene duck-typed interface (enter/exit/save_state/restore_state)
## for integration with NavigationStack.
##
## PANNING: No Camera2D. The SettlementMap Node2D's position is set to
## viewport center on load so that draw-space (0,0) appears at screen center.
## Panning modifies self.position directly. CanvasLayer children (HUD) are
## unaffected since they use screen-space coordinates.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal node_clicked(node_id: int)
signal exit_requested()


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PAN_SPEED := 200.0
const EDGE_MARGIN := 40.0
const ZOOM_STEP := 1.15
const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0
const NODE_HIT_RADIUS := 28.0
const VIEW_PADDING := 100.0
const PARTY_TOKEN_RADIUS := 18.0
const ADJ_HIGHLIGHT_RADIUS := 14.0
const POI_MARKER_RADIUS := 8.0
const BLOCK_OUTLINE_WIDTH := 1.5
const BACKGROUND_COLOR := Color(0.76, 0.71, 0.63)

const STREET_WIDTH := {
	"main_road": 6.0,
	"secondary": 4.0,
	"minor": 2.5,
	"alley": 0.0,
}

const DISTRICT_COLORS := {
	"market":          Color(0.82, 0.75, 0.58),
	"residential":     Color(0.78, 0.72, 0.64),
	"craftsmen":       Color(0.72, 0.65, 0.55),
	"castle":          Color(0.65, 0.62, 0.58),
	"temple":          Color(0.85, 0.82, 0.75),
	"docks":           Color(0.65, 0.70, 0.75),
	"thieves_quarter": Color(0.58, 0.55, 0.52),
	"outskirts":       Color(0.72, 0.75, 0.62),
	"plaza":           Color(0.85, 0.80, 0.70),
}
const DEFAULT_BLOCK_COLOR := Color(0.75, 0.70, 0.62)

const STREET_COLOR_MAIN := Color(0.35, 0.28, 0.18)
const STREET_COLOR_SECONDARY := Color(0.45, 0.38, 0.28)
const STREET_COLOR_MINOR := Color(0.55, 0.48, 0.38)

const POI_COLORS := {
	"tavern":    Color(0.85, 0.55, 0.20),
	"temple":    Color(0.90, 0.88, 0.80),
	"shop":      Color(0.80, 0.70, 0.30),
	"guild":     Color(0.40, 0.55, 0.75),
	"barracks":  Color(0.75, 0.30, 0.30),
}
const DEFAULT_POI_COLOR := Color(0.65, 0.60, 0.55)

const INTERSECTION_NODE_RADIUS := 5.0
const INTERSECTION_NODE_COLOR := Color(0.50, 0.42, 0.32)
const GATE_NODE_RADIUS := 7.0
const GATE_NODE_COLOR := Color(0.60, 0.45, 0.25)
const GATE_NODE_OUTLINE_COLOR := Color(0.35, 0.25, 0.15)

const PARTY_TOKEN_COLOR := Color(1.0, 0.9, 0.1)
const ADJ_HIGHLIGHT_COLOR := Color(0.2, 0.8, 0.2, 0.7)
const ADJ_HIGHLIGHT_RING_COLOR := Color(0.1, 1.0, 0.1, 0.9)
const WALL_COLOR := Color(0.50, 0.48, 0.45)
const WALL_WIDTH := 3.0
const TOWER_RADIUS := 4.0
const WATER_COLOR := Color(0.35, 0.55, 0.75, 0.7)
const WATER_WIDTH := 6.0
const BLOCK_OUTLINE_COLOR := Color(0.40, 0.35, 0.28, 0.5)
const LABEL_COLOR := Color(0.25, 0.20, 0.15)
const LABEL_SHADOW_COLOR := Color(1.0, 1.0, 1.0, 0.5)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _controller: SettlementMapController
var _map: SettlementMapData
var _settlement_id: String = ""

## Offset applied to ALL settlement coordinates so content center = local (0,0).
var _offset: Vector2 = Vector2.ZERO
## Uniform scale factor so the map fits within the viewport with padding.
var _map_scale: float = 1.0
## User zoom multiplier (scroll wheel), applied on top of _map_scale.
var _zoom: float = 1.0

@onready var _tooltip_panel = $SettlementHUD/TooltipPanel
@onready var _tooltip_label = $SettlementHUD/TooltipPanel/TooltipLabel
@onready var _exit_button = $SettlementHUD/ExitButton


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Wire this renderer to a SettlementMapController.
## Called BEFORE the scene enters the tree (@onready vars are still null).
func setup(controller: SettlementMapController) -> void:
	_controller = controller
	_controller.map_loaded.connect(_on_map_loaded)
	_controller.party_moved.connect(_on_party_moved)

	if _controller.get_map() != null:
		_map = _controller.get_map()
		_settlement_id = _controller.get_settlement_id()


func _ready() -> void:
	if _exit_button != null:
		_exit_button.pressed.connect(func(): exit_requested.emit())
		_exit_button.disabled = true
		_exit_button.text = "Move to a gate to leave"
	if _tooltip_panel != null:
		_tooltip_panel.visible = false

	if _map != null:
		_init_view()


func _on_map_loaded(_sid: String) -> void:
	_map = _controller.get_map()
	_settlement_id = _sid
	_init_view()
	_update_exit_button()


func _on_party_moved(_from: int, _to: int) -> void:
	queue_redraw()
	_update_exit_button()


## Enables or disables the exit button based on gate position.
func _update_exit_button() -> void:
	if _exit_button == null or _controller == null:
		return
	var on_gate: bool = _controller.is_on_gate()
	_exit_button.disabled = not on_gate
	_exit_button.text = "Exit Settlement" if on_gate else "Move to a gate to leave"


## Compute offset, scale, and center the view on the party token.
func _init_view() -> void:
	_compute_offset()
	_compute_scale()
	_apply_zoom_and_center()
	queue_redraw()


## Applies the current _map_scale * _zoom and centers view on the party.
func _apply_zoom_and_center() -> void:
	var effective := _map_scale * _zoom
	self.scale = Vector2(effective, effective)

	var vp_size := get_viewport().get_visible_rect().size
	var party_draw_pos := Vector2.ZERO
	if _controller != null:
		party_draw_pos = _to_draw(_controller.get_party_position())

	self.position = vp_size * 0.5 - party_draw_pos * effective


# ---------------------------------------------------------------------------
# ManagedScene interface
# ---------------------------------------------------------------------------

func enter(_params: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func save_state() -> Dictionary:
	return {"settlement_id": _settlement_id}


func restore_state(data: Dictionary) -> void:
	_settlement_id = data.get("settlement_id", _settlement_id)


# ---------------------------------------------------------------------------
# Offset computation
# ---------------------------------------------------------------------------

## Computes _offset so that the center of all content maps to (0, 0).
func _compute_offset() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for node in _map.street_graph.get("nodes", []):
		var p: Vector2 = node.get("position", Vector2.ZERO)
		min_pos = Vector2(minf(min_pos.x, p.x), minf(min_pos.y, p.y))
		max_pos = Vector2(maxf(max_pos.x, p.x), maxf(max_pos.y, p.y))
	for block in _map.blocks:
		for pt in block.get("polygon", []):
			min_pos = Vector2(minf(min_pos.x, pt.x), minf(min_pos.y, pt.y))
			max_pos = Vector2(maxf(max_pos.x, pt.x), maxf(max_pos.y, pt.y))
	if min_pos.x == INF:
		_offset = Vector2.ZERO
		return
	_offset = -((min_pos + max_pos) * 0.5)


## Computes a uniform scale factor so the map fits within the viewport with padding.
func _compute_scale() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var available := vp_size - Vector2(VIEW_PADDING * 2.0, VIEW_PADDING * 2.0)
	if available.x <= 0.0 or available.y <= 0.0:
		_map_scale = 1.0
		return

	# After _compute_offset, content spans symmetrically around (0,0).
	# Compute the full content span from offset-adjusted coordinates.
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for node in _map.street_graph.get("nodes", []):
		var p: Vector2 = _to_draw(node.get("position", Vector2.ZERO))
		min_pos = Vector2(minf(min_pos.x, p.x), minf(min_pos.y, p.y))
		max_pos = Vector2(maxf(max_pos.x, p.x), maxf(max_pos.y, p.y))
	for block in _map.blocks:
		for pt in block.get("polygon", []):
			var dp: Vector2 = _to_draw(pt)
			min_pos = Vector2(minf(min_pos.x, dp.x), minf(min_pos.y, dp.y))
			max_pos = Vector2(maxf(max_pos.x, dp.x), maxf(max_pos.y, dp.y))

	var content_size := max_pos - min_pos
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		_map_scale = 1.0
		return

	var scale_x := available.x / content_size.x
	var scale_y := available.y / content_size.y
	_map_scale = minf(scale_x, scale_y)
	_map_scale = minf(_map_scale, 1.0)  # Never zoom in beyond 1:1


## Converts a settlement data position to draw-space (with offset applied).
func _to_draw(pos: Vector2) -> Vector2:
	return pos + _offset


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _map == null:
		return
	_draw_background()
	_draw_water()
	_draw_blocks()
	_draw_district_labels()
	_draw_walls()
	_draw_streets()
	_draw_street_nodes()
	_draw_poi_markers()
	_draw_poi_labels()
	_draw_adjacent_highlights()
	_draw_party_token()


func _draw_background() -> void:
	var b: Rect2 = _map.bounds
	var pad := 150.0
	var bg_rect := Rect2(
		_to_draw(b.position) - Vector2(pad, pad),
		b.size + Vector2(pad * 2.0, pad * 2.0)
	)
	draw_rect(bg_rect, BACKGROUND_COLOR)


func _draw_water() -> void:
	if _map.water_features.is_empty():
		return
	var river: Array = _map.water_features.get("river_path", [])
	if river.size() >= 2:
		var pts := PackedVector2Array()
		for pt in river:
			pts.append(_to_draw(pt))
		draw_polyline(pts, WATER_COLOR, WATER_WIDTH, true)
	var coast: Array = _map.water_features.get("coastline", [])
	if coast.size() >= 2:
		var pts := PackedVector2Array()
		for pt in coast:
			pts.append(_to_draw(pt))
		draw_polyline(pts, WATER_COLOR, WATER_WIDTH + 2.0, true)


func _draw_blocks() -> void:
	for block in _map.blocks:
		var poly: Array = block.get("polygon", [])
		if poly.size() < 3:
			continue
		var pts := PackedVector2Array()
		for pt in poly:
			pts.append(_to_draw(pt))

		var dist: Dictionary = _map.get_district_for_block(block.get("id", -1))
		var dist_type: String = dist.get("type", "residential")
		var block_type: String = block.get("block_type", "")
		var fill_color: Color
		if block_type == "plaza":
			fill_color = DISTRICT_COLORS.get("plaza", DEFAULT_BLOCK_COLOR)
		else:
			fill_color = DISTRICT_COLORS.get(dist_type, DEFAULT_BLOCK_COLOR)
		draw_colored_polygon(pts, fill_color)

		var closed := PackedVector2Array(pts)
		closed.append(pts[0])
		draw_polyline(closed, BLOCK_OUTLINE_COLOR, BLOCK_OUTLINE_WIDTH, true)


func _draw_walls() -> void:
	if _map.walls.is_empty():
		return
	var path: Array = _map.walls.get("path", [])
	if path.size() >= 2:
		var pts := PackedVector2Array()
		for pt in path:
			pts.append(_to_draw(pt))
		pts.append(_to_draw(path[0]))
		draw_polyline(pts, WALL_COLOR, WALL_WIDTH, true)
	var towers: Array = _map.walls.get("towers", [])
	for tower_pos in towers:
		draw_circle(_to_draw(tower_pos), TOWER_RADIUS, WALL_COLOR)


func _draw_streets() -> void:
	for edge in _map.street_graph.get("edges", []):
		var edge_type: String = edge.get("type", "minor")
		var width: float = STREET_WIDTH.get(edge_type, 1.0)
		if width <= 0.0:
			continue

		var node_a: Dictionary = _map.get_node_by_id(edge.get("node_a", -1))
		var node_b: Dictionary = _map.get_node_by_id(edge.get("node_b", -1))
		if node_a.is_empty() or node_b.is_empty():
			continue

		var pos_a: Vector2 = _to_draw(node_a.get("position", Vector2.ZERO))
		var pos_b: Vector2 = _to_draw(node_b.get("position", Vector2.ZERO))

		var color: Color
		match edge_type:
			"main_road": color = STREET_COLOR_MAIN
			"secondary": color = STREET_COLOR_SECONDARY
			_:           color = STREET_COLOR_MINOR

		draw_line(pos_a, pos_b, color, width, true)


func _draw_street_nodes() -> void:
	for node in _map.street_graph.get("nodes", []):
		var node_type: String = node.get("type", "intersection")
		var pos: Vector2 = _to_draw(node.get("position", Vector2.ZERO))

		if node_type == "poi":
			continue  # POI nodes are drawn by _draw_poi_markers
		elif node_type == "gate":
			draw_circle(pos, GATE_NODE_RADIUS + 1.0, GATE_NODE_OUTLINE_COLOR)
			draw_circle(pos, GATE_NODE_RADIUS, GATE_NODE_COLOR)
		else:
			draw_circle(pos, INTERSECTION_NODE_RADIUS, INTERSECTION_NODE_COLOR)


func _draw_poi_markers() -> void:
	for poi in _map.pois:
		for nid in poi.get("street_node_ids", []):
			var node: Dictionary = _map.get_node_by_id(nid)
			if node.is_empty():
				continue
			var pos: Vector2 = _to_draw(node.get("position", Vector2.ZERO))
			var poi_type: String = poi.get("type", "")
			var color: Color = POI_COLORS.get(poi_type, DEFAULT_POI_COLOR)
			draw_circle(pos, POI_MARKER_RADIUS + 1.0, Color(0.2, 0.18, 0.15))
			draw_circle(pos, POI_MARKER_RADIUS, color)


func _draw_district_labels() -> void:
	var font := ThemeDB.fallback_font
	var district_font_size := 22
	for dist in _map.districts:
		var dist_name: String = dist.get("name", "")
		if dist_name.is_empty():
			continue
		var centroid := _to_draw(_compute_district_centroid(dist))
		var text_width := font.get_string_size(dist_name, HORIZONTAL_ALIGNMENT_LEFT, -1, district_font_size).x
		var label_pos := centroid + Vector2(-text_width * 0.5, 0.0)
		draw_string(font, label_pos, dist_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, district_font_size,
			Color(0.45, 0.40, 0.30, 0.25))


func _draw_poi_labels() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 14

	for poi in _map.pois:
		var label_text: String = poi.get("label", poi.get("name", ""))
		if label_text.is_empty():
			continue
		var node_ids: Array = poi.get("street_node_ids", [])
		if node_ids.is_empty():
			continue
		var node: Dictionary = _map.get_node_by_id(node_ids[0])
		if node.is_empty():
			continue
		var pos: Vector2 = _to_draw(node.get("position", Vector2.ZERO))
		var text_width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_pos := pos + Vector2(-text_width * 0.5, -18.0)
		draw_string(font, label_pos + Vector2(1, 1), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_SHADOW_COLOR)
		draw_string(font, label_pos, label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


func _draw_adjacent_highlights() -> void:
	if _controller == null:
		return
	for nid in _controller.get_adjacent_nodes():
		var node: Dictionary = _map.get_node_by_id(nid)
		if node.is_empty():
			continue
		var pos: Vector2 = _to_draw(node.get("position", Vector2.ZERO))
		draw_circle(pos, ADJ_HIGHLIGHT_RADIUS, ADJ_HIGHLIGHT_COLOR)
		draw_arc(pos, ADJ_HIGHLIGHT_RADIUS, 0.0, TAU, 24, ADJ_HIGHLIGHT_RING_COLOR, 2.0)


func _draw_party_token() -> void:
	if _controller == null:
		return
	var raw_pos: Vector2 = _controller.get_party_position()
	var pos: Vector2 = _to_draw(raw_pos)
	draw_circle(pos, PARTY_TOKEN_RADIUS + 1.5, Color(0.2, 0.15, 0.05))
	draw_circle(pos, PARTY_TOKEN_RADIUS, PARTY_TOKEN_COLOR)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _map == null:
		return

	var pan_dir := Vector2.ZERO

	if Input.is_action_pressed("ui_left"):
		pan_dir.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		pan_dir.x += 1.0
	if Input.is_action_pressed("ui_up"):
		pan_dir.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		pan_dir.y += 1.0

	var vp_size := get_viewport().get_visible_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	if mouse_pos.x >= 0.0 and mouse_pos.x <= vp_size.x and \
	   mouse_pos.y >= 0.0 and mouse_pos.y <= vp_size.y:
		if mouse_pos.x < EDGE_MARGIN:
			pan_dir.x -= 1.0
		elif mouse_pos.x > vp_size.x - EDGE_MARGIN:
			pan_dir.x += 1.0
		if mouse_pos.y < EDGE_MARGIN:
			pan_dir.y -= 1.0
		elif mouse_pos.y > vp_size.y - EDGE_MARGIN:
			pan_dir.y += 1.0

	if pan_dir != Vector2.ZERO:
		# Negative: moving Node2D left makes content scroll right
		self.position -= pan_dir.normalized() * PAN_SPEED * delta


func _unhandled_input(event: InputEvent) -> void:
	if _map == null:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var world_pos := _screen_to_world(event.position)
			var closest_node_id := _find_closest_node(world_pos)
			if closest_node_id >= 0:
				node_clicked.emit(closest_node_id)

		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)

	elif event is InputEventMouseMotion:
		_update_tooltip(event.position)


# ---------------------------------------------------------------------------
# Tooltip
# ---------------------------------------------------------------------------

func _update_tooltip(viewport_pos: Vector2) -> void:
	if _tooltip_panel == null or _tooltip_label == null or _map == null:
		return

	var world_pos := _screen_to_world(viewport_pos)
	var closest_node_id := _find_closest_node(world_pos)

	if closest_node_id >= 0:
		var poi: Dictionary = _map.get_poi_at_node(closest_node_id)
		if not poi.is_empty():
			_tooltip_label.text = "%s\n%s" % [
				poi.get("name", ""),
				poi.get("type", "").capitalize(),
			]
			_tooltip_panel.visible = true
			_tooltip_panel.position = viewport_pos + Vector2(16.0, 16.0)
			return

	_tooltip_panel.visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Zoom in/out centered on [param screen_pos]. Adjusts _zoom and repositions
## so the point under the cursor stays fixed on screen.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old_zoom := _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN / _map_scale, ZOOM_MAX / _map_scale)
	if _zoom == old_zoom:
		return

	var old_eff := _map_scale * old_zoom
	var new_eff := _map_scale * _zoom

	# Keep the world point under the cursor stationary:
	# screen_pos = self.position + world_pt * old_eff
	# screen_pos = new_position + world_pt * new_eff
	# => new_position = screen_pos - (screen_pos - self.position) * (new_eff / old_eff)
	self.position = screen_pos - (screen_pos - self.position) * (new_eff / old_eff)
	self.scale = Vector2(new_eff, new_eff)
	queue_redraw()


func _screen_to_world(viewport_pos: Vector2) -> Vector2:
	# Full transform: local → global (Node2D pos+scale) → canvas → viewport.
	# Invert the full chain to go from viewport coords back to local draw-space.
	var full_transform := get_canvas_transform() * get_global_transform()
	return full_transform.affine_inverse() * viewport_pos


func _find_closest_node(world_pos: Vector2) -> int:
	if _map == null:
		return -1
	var best_id := -1
	var best_dist := NODE_HIT_RADIUS * NODE_HIT_RADIUS
	for node in _map.street_graph.get("nodes", []):
		var pos: Vector2 = _to_draw(node.get("position", Vector2.ZERO))
		var d := world_pos.distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best_id = node.get("id", -1)
	return best_id


func _compute_district_centroid(dist: Dictionary) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for bid in dist.get("block_ids", []):
		var block: Dictionary = _map.get_block_by_id(bid)
		for pt in block.get("polygon", []):
			total += pt
			count += 1
	if count == 0:
		return Vector2.ZERO
	return total / float(count)
