extends Node2D

## Isometric dungeon map renderer.
##
## No class_name — this is a scene script, not a reusable type.
##
## Implements the ManagedScene duck-typed interface (enter/exit/save_state/restore_state)
## for integration with NavigationStack.
##
## All rendering is done in a single _draw() call on this Node2D (ground, features,
## grid, fog in draw order). Entity tokens are child Polygon2D nodes in EntityLayer.
##
## Call setup(controller) before entering the scene tree.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PAN_SPEED := 200.0
const EDGE_MARGIN := 40.0


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _entity_layer: Node2D = $EntityLayer
@onready var _camera: Camera2D = $Camera2D
@onready var _tooltip_panel = $DungeonHUD/TooltipPanel
@onready var _tooltip_label = $DungeonHUD/TooltipPanel/TooltipLabel
@onready var _exit_button = $DungeonHUD/ExitButton


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _controller: DungeonMapController
var _map: TacticalMapData
var _dungeon_id: String = ""

## Party token Polygon2D nodes. entity_id → Polygon2D
var _party_tokens: Dictionary = {}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal cell_clicked(pos: Vector2i)
signal door_interact_requested(pos: Vector2i)
signal exit_requested()


# ---------------------------------------------------------------------------
# Setup (call before tree entry)
# ---------------------------------------------------------------------------

## Wire this renderer to a DungeonMapController.
## Must be called before enter() or _ready().
func setup(controller: DungeonMapController) -> void:
	_controller = controller
	controller.map_loaded.connect(_on_map_loaded)
	controller.fog_updated.connect(_on_fog_updated)
	controller.party_moved.connect(_on_party_moved)
	controller.door_state_changed.connect(_on_door_state_changed)
	controller.level_changed.connect(_on_level_changed)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if _exit_button != null:
		_exit_button.pressed.connect(_on_exit_button_pressed)
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


func _process(delta: float) -> void:
	if _camera == null or _map == null:
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
		_camera.position += pan_dir.normalized() * PAN_SPEED * delta


# ---------------------------------------------------------------------------
# ManagedScene interface
# ---------------------------------------------------------------------------

func enter(params: Dictionary = {}) -> void:
	_dungeon_id = params.get("dungeon_id", _dungeon_id)
	_refresh_all()


func exit() -> void:
	# Future: save fog + door states to DB here
	pass


func save_state() -> Dictionary:
	return {"dungeon_id": _dungeon_id}


func restore_state(data: Dictionary) -> void:
	_dungeon_id = data.get("dungeon_id", _dungeon_id)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_map_loaded(_id: String) -> void:
	_map = _controller.get_map()
	_refresh_all()
	_center_camera_on_entry()


func _on_fog_updated() -> void:
	_map = _controller.get_map()
	queue_redraw()


func _on_party_moved(_from: Vector2i, _to: Vector2i) -> void:
	_update_entity_tokens()
	queue_redraw()


func _on_door_state_changed(_pos: Vector2i, _old: String, _new: String) -> void:
	queue_redraw()


func _on_level_changed(_from_level: int, _to_level: int) -> void:
	_map = _controller.get_map()
	_refresh_all()
	_center_camera_on_entry()


func _on_exit_button_pressed() -> void:
	exit_requested.emit()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _map == null:
		return
	_draw_ground()
	_draw_features()
	_draw_grid_lines()
	_draw_fog()


func _draw_ground() -> void:
	for pos in _map._cells.keys():
		var cell: Dictionary = _map._cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		var color: Color = _ground_color_for(tf, cell)
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
		var pts := _diamond_points(screen_pos)
		draw_colored_polygon(pts, color)


func _draw_features() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 12

	for pos in _map._cells.keys():
		var cell: Dictionary = _map._cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
		var hw := float(IsometricGrid.HALF_W)
		var hh := float(IsometricGrid.HALF_H)

		match tf:
			"stairs_up":
				# White upward triangle
				var pts := PackedVector2Array([
					screen_pos + Vector2(0.0, -hh * 0.7),
					screen_pos + Vector2(-hw * 0.5, hh * 0.3),
					screen_pos + Vector2(hw * 0.5, hh * 0.3),
				])
				draw_colored_polygon(pts, Color.WHITE)

			"stairs_down":
				# White downward triangle
				var pts := PackedVector2Array([
					screen_pos + Vector2(0.0, hh * 0.7),
					screen_pos + Vector2(-hw * 0.5, -hh * 0.3),
					screen_pos + Vector2(hw * 0.5, -hh * 0.3),
				])
				draw_colored_polygon(pts, Color.WHITE)

			"door", "door_locked":
				var ds: String = cell.get("door_state", "closed")
				var dt: String = cell.get("door_type", "")
				if dt == "arch":
					pass  # arch is always open — brown color is enough
				elif ds == "open":
					draw_arc(screen_pos, hw * 0.4, 0.0, TAU, 16, Color.WHITE, 2.0)
				else:
					# X icon for closed door
					draw_line(screen_pos + Vector2(-hw * 0.4, -hh * 0.5),
						screen_pos + Vector2(hw * 0.4, hh * 0.5), Color.WHITE, 2.0)
					draw_line(screen_pos + Vector2(hw * 0.4, -hh * 0.5),
						screen_pos + Vector2(-hw * 0.4, hh * 0.5), Color.WHITE, 2.0)
					if ds == "locked":
						draw_string(font, screen_pos + Vector2(-4.0, 4.0), "L",
							HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.YELLOW)

			"door_secret":
				var detected: bool = cell.get("door_detected", true)
				var ds: String = cell.get("door_state", "closed")
				if detected:
					if ds == "open":
						draw_arc(screen_pos, hw * 0.4, 0.0, TAU, 16, Color.WHITE, 2.0)
					else:
						draw_string(font, screen_pos + Vector2(-4.0, 4.0), "?",
							HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
				else:
					# Dev aid: undetected secret shows "S"
					draw_string(font, screen_pos + Vector2(-4.0, 4.0), "S",
						HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

			"portcullis":
				var ds: String = cell.get("door_state", "closed")
				if ds != "open":
					# Vertical bars across the diamond
					for i in range(3):
						var t := (float(i) + 1.0) / 4.0
						var bx := lerpf(-hw * 0.7, hw * 0.7, t)
						draw_line(screen_pos + Vector2(bx, -hh * 0.6),
							screen_pos + Vector2(bx, hh * 0.6), Color(0.8, 0.8, 0.8), 2.0)


func _draw_grid_lines() -> void:
	for pos in _map._cells.keys():
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
		var pts := _diamond_points(screen_pos)
		# Close the polyline by repeating the first point
		var closed := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(closed, Color(0.0, 0.0, 0.0, 0.6), 1.0, true)


func _draw_fog() -> void:
	for pos in _map._cells.keys():
		var fog_state := _map.get_fog(pos)
		if fog_state == TacticalMapData.FogState.VISIBLE:
			continue
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
		var pts := _diamond_points(screen_pos)
		var color: Color
		if fog_state == TacticalMapData.FogState.HIDDEN:
			color = Color(0.0, 0.0, 0.0, 1.0)
		else:  # EXPLORED
			color = Color(0.0, 0.0, 0.0, 0.45)
		draw_colored_polygon(pts, color)


# ---------------------------------------------------------------------------
# Entity tokens
# ---------------------------------------------------------------------------

## Creates or updates Polygon2D party tokens in the EntityLayer.
func _update_entity_tokens() -> void:
	if _map == null or _controller == null or _entity_layer == null:
		return

	# Remove tokens for entities no longer in the map
	var to_remove: Array = []
	for eid in _party_tokens.keys():
		if not _map.entity_positions.has(eid):
			to_remove.append(eid)
	for eid in to_remove:
		if is_instance_valid(_party_tokens[eid]):
			_party_tokens[eid].queue_free()
		_party_tokens.erase(eid)

	# Create or update tokens for current entities
	for eid in _map.entity_positions.keys():
		var pos: Vector2i = _map.entity_positions[eid]
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)

		if not _party_tokens.has(eid):
			var token := Polygon2D.new()
			token.color = Color(1.0, 0.9, 0.1)  # yellow
			token.polygon = _small_diamond_polygon()
			_entity_layer.add_child(token)
			_party_tokens[eid] = token

		_party_tokens[eid].position = screen_pos


## Returns a small diamond polygon (centred at origin) for party tokens.
func _small_diamond_polygon() -> PackedVector2Array:
	var hw := 8.0
	var hh := 5.0
	return PackedVector2Array([
		Vector2(0.0, -hh),
		Vector2(hw, 0.0),
		Vector2(0.0, hh),
		Vector2(-hw, 0.0),
	])


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return

	var local_pos := get_local_mouse_position()
	var cell_pos := IsometricGrid.screen_to_cell(local_pos)

	if event.button_index == MOUSE_BUTTON_LEFT:
		if _map != null and _map.has_cell(cell_pos):
			cell_clicked.emit(cell_pos)
			get_viewport().set_input_as_handled()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if _map != null and _map.is_door(cell_pos):
			door_interact_requested.emit(cell_pos)
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Camera helpers
# ---------------------------------------------------------------------------

func _center_camera_on_entry() -> void:
	if _camera == null or _map == null:
		return
	var entry := _map.entry_pos
	_camera.position = IsometricGrid.cell_to_screen(entry.x, entry.y)
	_compute_camera_limits()


func _compute_camera_limits() -> void:
	if _camera == null or _map == null:
		return
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for pos in _map._cells.keys():
		var sp := IsometricGrid.cell_to_screen(pos.x, pos.y)
		min_pos.x = minf(min_pos.x, sp.x)
		min_pos.y = minf(min_pos.y, sp.y)
		max_pos.x = maxf(max_pos.x, sp.x)
		max_pos.y = maxf(max_pos.y, sp.y)
	var pad := Vector2(float(IsometricGrid.CELL_W), float(IsometricGrid.CELL_H))
	_camera.limit_left   = int(min_pos.x - pad.x)
	_camera.limit_right  = int(max_pos.x + pad.x)
	_camera.limit_top    = int(min_pos.y - pad.y)
	_camera.limit_bottom = int(max_pos.y + pad.y)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	if _controller != null:
		_map = _controller.get_map()
	_update_entity_tokens()
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------

## Returns the ground fill color for a terrain_feature.
func _ground_color_for(tf: String, cell: Dictionary) -> Color:
	match tf:
		"open", "stairs_up", "stairs_down":
			return Color(0.831, 0.722, 0.588)  # tan/beige — floor
		"wall_stone", "rock":
			return Color(0.50, 0.50, 0.50)     # mid grey
		"wall_wood":
			return Color(0.55, 0.45, 0.35)     # grey-brown
		"portcullis":
			return Color(0.4, 0.3, 0.2)        # dark brown
		"door", "door_locked":
			return Color(0.545, 0.271, 0.075)  # brown
		"door_secret":
			var detected: bool = cell.get("door_detected", true)
			if detected:
				return Color(0.545, 0.271, 0.075)
			else:
				return Color(0.35, 0.35, 0.35)     # dark grey (dev aid)
		_:
			return Color(0.3, 0.3, 0.3)


## Returns the 4 corners of an isometric diamond centred on [param screen_pos].
func _diamond_points(screen_pos: Vector2) -> PackedVector2Array:
	var hw := float(IsometricGrid.HALF_W)
	var hh := float(IsometricGrid.HALF_H)
	return PackedVector2Array([
		screen_pos + Vector2(0.0, -hh),   # top
		screen_pos + Vector2(hw, 0.0),    # right
		screen_pos + Vector2(0.0, hh),    # bottom
		screen_pos + Vector2(-hw, 0.0),   # left
	])
