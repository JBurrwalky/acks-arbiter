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
const ZOOM_MIN := 1.0      # 100% — no zoom out beyond default
const ZOOM_MAX := 2.5      # 250%
const ZOOM_STEP := 0.1     # 10% additive per tick


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _entity_layer: Node2D = $EntityLayer
@onready var _camera: Camera2D = $Camera2D
@onready var _tooltip_panel = $DungeonHUD/TooltipPanel
@onready var _tooltip_label = $DungeonHUD/TooltipPanel/TooltipLabel
@onready var _context_menu_layer = $DungeonHUD/ContextMenuLayer


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _controller: DungeonMapController
var _map: TacticalMapData
var _dungeon_id: String = ""

## CombatantToken nodes indexed by entity_id.
var _tokens: Dictionary = {}

## Highlighted cells for combat move/range overlays.
## Array of {cells: Array[Vector2i], color: Color}
var _highlight_layers: Array = []

## Entity IDs currently showing a combat target ring.
var _target_rings: Array[String] = []

## Entity ID of the currently active combatant (bright glow).
var _active_entity_id: String = ""

## When true, left-clicks check for token proximity before emitting cell_clicked.
var _combat_mode: bool = false

## Loaded lazily on first token creation to avoid parse-time dependency.
var _token_scene: PackedScene = null

## Currently selected entity IDs (exploration mode selection).
var _selected_entity_ids: Array[String] = []

## Reference to the order overlay child (set in _ready if present).
var _order_overlay: Node2D = null

var _zoom_level: float = 1.0

## Middle-mouse drag state for camera panning.
var _middle_dragging: bool = false
var _middle_drag_start: Vector2 = Vector2.ZERO

## Drag-select (rubber-band) state.
var _drag_selecting: bool = false
var _drag_select_start: Vector2 = Vector2.ZERO  # screen-space
var _drag_select_end: Vector2 = Vector2.ZERO
const DRAG_SELECT_THRESHOLD := 5.0  # pixels before drag-select activates

## Token animation speed (pixels per second for smooth movement).
const TOKEN_MOVE_DURATION := 0.15  # seconds per cell hop

## Double-click detection for control group recall.
var _last_number_key: int = -1
var _last_number_key_time: float = 0.0
const DOUBLE_TAP_THRESHOLD := 0.3


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal cell_clicked(pos: Vector2i)
signal exit_requested()
signal entity_clicked(entity_id: String)
signal entity_selected(entity_id: String)
signal entity_deselected(entity_id: String)
signal selection_cleared()
signal context_menu_requested(cell_pos: Vector2i, screen_pos: Vector2)
signal control_group_select_requested(entity_id: String)
signal control_group_assign_requested(group_number: int, entity_ids: Array)
signal control_group_recall_requested(group_number: int)
signal minimap_toggle_requested()


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
	controller.entity_moved.connect(_on_entity_moved)
	controller.door_state_changed.connect(_on_door_state_changed)
	controller.level_changed.connect(_on_level_changed)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false
	# Find order overlay child if present in scene tree
	_order_overlay = get_node_or_null("OrderOverlayLayer")


func _process(delta: float) -> void:
	if _camera == null or _map == null:
		return

	var pan_dir := Vector2.ZERO

	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		pan_dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		pan_dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		pan_dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
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
		_camera.position += pan_dir.normalized() * PAN_SPEED * delta / _zoom_level


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
	_zoom_level = 1.0
	if _camera != null:
		_camera.zoom = Vector2(1.0, 1.0)
	_refresh_all()
	_center_camera_on_party()


func _on_fog_updated() -> void:
	_map = _controller.get_map()
	queue_redraw()


func _on_party_moved(_from: Vector2i, _to: Vector2i) -> void:
	_update_entity_tokens()
	queue_redraw()


## Smooth-move a single entity token from one cell to another.
func _on_entity_moved(entity_id: String, _from_pos: Vector2i, to_pos: Vector2i) -> void:
	if not _tokens.has(entity_id):
		return
	var token: Node2D = _tokens[entity_id]
	var target_screen := IsometricGrid.cell_to_screen(to_pos.x, to_pos.y)

	# Kill any existing tween on this token.
	if token.has_meta("move_tween"):
		var old_tween: Tween = token.get_meta("move_tween")
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()

	# Create a smooth slide tween.
	var tween: Tween = create_tween()
	tween.tween_property(token, "position", target_screen, TOKEN_MOVE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	token.set_meta("move_tween", tween)

	queue_redraw()


func _on_door_state_changed(_pos: Vector2i, _old: String, _new: String) -> void:
	queue_redraw()


func _on_level_changed(_from_level: int, _to_level: int) -> void:
	_map = _controller.get_map()
	_zoom_level = 1.0
	if _camera != null:
		_camera.zoom = Vector2(1.0, 1.0)
	_refresh_all()
	_center_camera_on_party()


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
	_draw_highlights()
	_draw_drag_select_rect()


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
				if ds == "destroyed":
					pass  # No icon — floor shows through as open passage.
				elif dt == "arch":
					# Arch: always open, draw "A" label for visual identification
					draw_string(font, screen_pos + Vector2(-4.0, 4.0), "A",
						HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1.0, 1.0, 0.8))
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
					elif ds == "stuck":
						draw_string(font, screen_pos + Vector2(-4.0, 4.0), "K",
							HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.ORANGE_RED)

			"door_secret":
				var detected: bool = cell.get("door_detected", true)
				var ds: String = cell.get("door_state", "closed")
				if ds == "destroyed":
					pass  # No icon — floor shows through.
				elif detected:
					if ds == "open":
						draw_arc(screen_pos, hw * 0.4, 0.0, TAU, 16, Color.WHITE, 2.0)
					else:
						draw_string(font, screen_pos + Vector2(-4.0, 4.0), "?",
							HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
				else:
					# Dev aid: undetected secret shows bright "S" on dark grey
					draw_string(font, screen_pos + Vector2(-5.0, 5.0), "S",
						HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1.0, 0.9, 0.2))

			"portcullis":
				var ds: String = cell.get("door_state", "closed")
				if ds == "destroyed":
					pass  # No icon — floor shows through.
				elif ds != "open":
					# Vertical bars across the diamond
					for i in range(3):
						var t := (float(i) + 1.0) / 4.0
						var bx := lerpf(-hw * 0.7, hw * 0.7, t)
						draw_line(screen_pos + Vector2(bx, -hh * 0.6),
							screen_pos + Vector2(bx, hh * 0.6), Color(0.8, 0.8, 0.8), 2.0)
					# Label for clarity
					draw_string(font, screen_pos + Vector2(-4.0, 4.0), "P",
						HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.YELLOW)

	# Transition cell markers (green "E" + diamond outline)
	if _map != null:
		for tc_pos in _map.transition_cells:
			if _map.get_fog(tc_pos) == TacticalMapData.FogState.HIDDEN:
				continue
			var tc_screen := IsometricGrid.cell_to_screen(tc_pos.x, tc_pos.y)
			var tc_hw := float(IsometricGrid.HALF_W) * 0.6
			var tc_hh := float(IsometricGrid.HALF_H) * 0.6
			var tc_pts := PackedVector2Array([
				tc_screen + Vector2(0.0, -tc_hh),
				tc_screen + Vector2(tc_hw, 0.0),
				tc_screen + Vector2(0.0, tc_hh),
				tc_screen + Vector2(-tc_hw, 0.0),
				tc_screen + Vector2(0.0, -tc_hh),
			])
			draw_polyline(tc_pts, Color.GREEN, 2.0)
			draw_string(font, tc_screen + Vector2(-4.0, 4.0), "E",
				HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.GREEN)


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


func _draw_highlights() -> void:
	## Draw combat overlay layers (reachable cells, attack ranges, etc.)
	for layer in _highlight_layers:
		var color: Color = layer.get("color", Color(1.0, 1.0, 0.0, 0.25))
		for pos: Vector2i in layer.get("cells", []):
			var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
			var pts := _diamond_points(screen_pos)
			draw_colored_polygon(pts, color)
			draw_polyline(
				PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(color.r, color.g, color.b, minf(color.a * 2.0, 1.0)),
				1.5, true)


func _draw_drag_select_rect() -> void:
	if not _drag_selecting:
		return
	# Convert screen-space drag rect corners to world-space for drawing.
	var world_start := _screen_to_world(_drag_select_start)
	var world_end := _screen_to_world(_drag_select_end)
	var rect_pos := Vector2(minf(world_start.x, world_end.x), minf(world_start.y, world_end.y))
	var rect_size := Vector2(absf(world_end.x - world_start.x), absf(world_end.y - world_start.y))
	var rect := Rect2(rect_pos, rect_size)
	# Draw filled semi-transparent rectangle.
	draw_rect(rect, Color(0.2, 0.6, 1.0, 0.15))
	# Draw border.
	draw_rect(rect, Color(0.3, 0.7, 1.0, 0.7), false, 1.5)


## Convert a screen-space position to world-space (inverse of _world_to_screen).
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	if _camera == null:
		return screen_pos
	var vp_size := get_viewport().get_visible_rect().size
	var cam_pos := _camera.position
	return (screen_pos - vp_size * 0.5) / _zoom_level + cam_pos


# ---------------------------------------------------------------------------
# Entity tokens
# ---------------------------------------------------------------------------

## Add a CombatantToken for the given entity.
## [param side]: 0 = PARTY (blue), 1 = ENEMY (red), -1 = neutral (yellow).
## [param class_letter]: single letter class code shown in token centre.
## [param class_id]: optional ACKS class_id (e.g. "barbarian"). If a sprite
##   atlas is registered for this class, the token switches to sprite mode.
## [param token_variant]: optional variant key (e.g. "default", "scarred").
##   Falls back to "default" if the specific variant is not registered.
## Safe to call multiple times — returns existing token if already present.
func add_entity_token(
		entity_id: String,
		entity_display_name: String,
		side: int,
		class_letter: String,
		class_id: String = "",
		token_variant: String = "") -> Node2D:
	if _tokens.has(entity_id):
		return _tokens[entity_id]
	if _token_scene == null:
		_token_scene = load("res://scenes/ui/components/combatant_token.tscn")
	if _entity_layer == null:
		push_error("DungeonMapRenderer.add_entity_token: EntityLayer is null — call after scene enters tree")
		return null
	var token: Node2D = _token_scene.instantiate()
	token.setup(entity_id, entity_display_name, side, class_letter)
	# Apply class-specific sprite atlas if one is registered
	var atlas: Texture2D = _lookup_atlas_for_class(class_id, token_variant)
	if atlas != null:
		token.set_sprite_atlas(atlas)
	_entity_layer.add_child(token)
	_tokens[entity_id] = token
	return token


## Lazy-load TokenAtlasRegistry and query it. Avoids parse-time class_name lookup.
static var _atlas_registry_script = null
static func _lookup_atlas_for_class(class_id: String, variant: String = "") -> Texture2D:
	if class_id.is_empty():
		return null
	if _atlas_registry_script == null:
		_atlas_registry_script = load("res://scenes/ui/components/token_atlas_registry.gd")
	if _atlas_registry_script == null:
		return null
	return _atlas_registry_script.get_atlas_for_class(class_id, variant)


## Remove the token for [param entity_id] from the scene.
func remove_entity_token(entity_id: String) -> void:
	if _tokens.has(entity_id):
		if is_instance_valid(_tokens[entity_id]):
			_tokens[entity_id].queue_free()
		_tokens.erase(entity_id)


## Return the token for [param entity_id], or null if not present.
func get_entity_token(entity_id: String) -> Node2D:
	return _tokens.get(entity_id, null)


# ---------------------------------------------------------------------------
# Combat-mode highlight API
# ---------------------------------------------------------------------------

## Enable or disable combat input mode (entity-click detection).
func set_combat_mode(enabled: bool) -> void:
	_combat_mode = enabled


## Highlight a set of cells with [param color] (filled diamond overlay).
## Multiple layers can be stacked; call clear_highlights() to remove all.
func highlight_cells(cells: Array[Vector2i], color: Color) -> void:
	_highlight_layers.append({"cells": cells, "color": color})
	queue_redraw()


## Mark [param entity_ids] with a red target ring.
func highlight_entity_tokens(entity_ids: Array[String]) -> void:
	_target_rings = entity_ids.duplicate()
	for eid in entity_ids:
		if _tokens.has(eid):
			_tokens[eid].is_selected = true
	queue_redraw()


## Clear all cell highlight layers and target rings.
func clear_highlights() -> void:
	_highlight_layers.clear()
	_target_rings.clear()
	for eid in _tokens.keys():
		_tokens[eid].is_selected = false
	queue_redraw()


## Mark [param entity_id] as the active combatant (bright glow).
func set_active_token(entity_id: String) -> void:
	# Clear previous
	if not _active_entity_id.is_empty() and _tokens.has(_active_entity_id):
		_tokens[_active_entity_id].is_active = false
	_active_entity_id = entity_id
	if not entity_id.is_empty() and _tokens.has(entity_id):
		_tokens[entity_id].is_active = true


## Move a token instantly to a new grid cell.
func move_token(entity_id: String, to_cell: Vector2i) -> void:
	if _tokens.has(entity_id):
		var screen_pos := IsometricGrid.cell_to_screen(to_cell.x, to_cell.y)
		_tokens[entity_id].update_position(screen_pos)


## Update a token's facing direction (rotates the beak).
func set_token_facing(entity_id: String, facing: Vector2i) -> void:
	if _tokens.has(entity_id):
		_tokens[entity_id].set_facing(facing)


## Sync all token positions to the current entity_positions in the map.
func _update_entity_tokens() -> void:
	if _map == null or _entity_layer == null:
		return

	# Remove tokens for entities no longer in the map
	var to_remove: Array = []
	for eid in _tokens.keys():
		if not _map.entity_positions.has(eid):
			to_remove.append(eid)
	for eid in to_remove:
		remove_entity_token(eid)

	# Update positions for all current entities
	for eid in _map.entity_positions.keys():
		var pos: Vector2i = _map.entity_positions[eid]
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
		if _tokens.has(eid):
			_tokens[eid].update_position(screen_pos)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# --- Mouse button events ---
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_handle_left_press(event)
				MOUSE_BUTTON_RIGHT:
					_handle_right_click(event)
				MOUSE_BUTTON_MIDDLE:
					_middle_dragging = true
					_middle_drag_start = event.position
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_UP:
					_apply_zoom(_zoom_level + ZOOM_STEP, event.position)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_DOWN:
					_apply_zoom(_zoom_level - ZOOM_STEP, event.position)
					get_viewport().set_input_as_handled()
		else:
			# Button released.
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_handle_left_release(event)
				MOUSE_BUTTON_MIDDLE:
					_middle_dragging = false

	# --- Mouse motion ---
	elif event is InputEventMouseMotion:
		if _middle_dragging:
			if _camera != null:
				_camera.position -= event.relative / _zoom_level
				get_viewport().set_input_as_handled()
		elif _drag_selecting:
			_drag_select_end = event.position
			queue_redraw()
			get_viewport().set_input_as_handled()

	# --- Key events ---
	elif event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_EQUAL, KEY_KP_ADD:
					_apply_zoom(_zoom_level + ZOOM_STEP)
					get_viewport().set_input_as_handled()
				KEY_MINUS, KEY_KP_SUBTRACT:
					_apply_zoom(_zoom_level - ZOOM_STEP)
					get_viewport().set_input_as_handled()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
					# Ctrl+N: assign current selection to control group N.
					var group_num: int = event.keycode - KEY_0
					control_group_assign_requested.emit(group_num, _selected_entity_ids.duplicate())
					get_viewport().set_input_as_handled()
		elif not event.ctrl_pressed and not event.alt_pressed:
			match event.keycode:
				KEY_HOME:
					_apply_zoom(1.0)
					_center_camera_on_selected()
					get_viewport().set_input_as_handled()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
					# Number key: select control group (double-tap: center camera too).
					var group_num: int = event.keycode - KEY_0
					var now := Time.get_ticks_msec() / 1000.0
					if _last_number_key == group_num and (now - _last_number_key_time) < DOUBLE_TAP_THRESHOLD:
						# Double-tap: select + center.
						_last_number_key = -1
						control_group_recall_requested.emit(group_num)
					else:
						_last_number_key = group_num
						_last_number_key_time = now
						control_group_recall_requested.emit(group_num)
					get_viewport().set_input_as_handled()
				KEY_M:
					minimap_toggle_requested.emit()
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					# Escape clears selection.
					if not _selected_entity_ids.is_empty():
						clear_selection()
						selection_cleared.emit()
						get_viewport().set_input_as_handled()


## Left mouse button pressed — start potential drag-select or immediate click.
func _handle_left_press(event: InputEventMouseButton) -> void:
	var local_pos := get_local_mouse_position()

	# Double-click is always immediate (no drag).
	if event.double_click and not _combat_mode:
		var hit_eid := _entity_id_near_screen_pos(local_pos)
		if not hit_eid.is_empty():
			control_group_select_requested.emit(hit_eid)
			get_viewport().set_input_as_handled()
			return

	# In combat mode, clicks are immediate.
	if _combat_mode:
		var hit_eid := _entity_id_near_screen_pos(local_pos)
		if not hit_eid.is_empty():
			entity_clicked.emit(hit_eid)
			get_viewport().set_input_as_handled()
			return

	# Begin drag-select tracking.
	_drag_selecting = true
	_drag_select_start = event.position
	_drag_select_end = event.position
	get_viewport().set_input_as_handled()


## Left mouse button released — finish drag-select or do normal click.
func _handle_left_release(event: InputEventMouseButton) -> void:
	if not _drag_selecting:
		return
	_drag_selecting = false

	var drag_dist := _drag_select_start.distance_to(event.position)
	if drag_dist > DRAG_SELECT_THRESHOLD:
		# Rubber-band select: find all tokens within the selection rectangle.
		_perform_drag_select(event)
	else:
		# Normal click (no drag).
		_perform_click_select()

	queue_redraw()  # Clear the selection rectangle.


## Perform rubber-band selection on all tokens within the drag rectangle.
func _perform_drag_select(event: InputEventMouseButton) -> void:
	var additive := Input.is_key_pressed(KEY_SHIFT)
	if not additive:
		clear_selection()

	# Build the selection rect in screen space.
	var rect := Rect2(
		Vector2(minf(_drag_select_start.x, event.position.x),
				minf(_drag_select_start.y, event.position.y)),
		Vector2(absf(event.position.x - _drag_select_start.x),
				absf(event.position.y - _drag_select_start.y))
	)

	# Convert token positions to screen space and test containment.
	var any_selected := false
	for eid in _tokens.keys():
		var token: Node2D = _tokens[eid]
		# Token position is in world space — convert to screen space.
		var world_pos: Vector2 = token.position
		var screen_pos: Vector2 = _world_to_screen(world_pos)
		if rect.has_point(screen_pos):
			select_entity(eid, true)
			any_selected = true

	if not any_selected and not additive:
		selection_cleared.emit()


## Single-click select (no drag detected).
func _perform_click_select() -> void:
	var local_pos := get_local_mouse_position()
	var hit_eid := _entity_id_near_screen_pos(local_pos)
	if not hit_eid.is_empty():
		var additive := Input.is_key_pressed(KEY_SHIFT)
		select_entity(hit_eid, additive)
		return

	# Clicked empty space — clear selection.
	var cell_pos := IsometricGrid.screen_to_cell(local_pos)
	if not _selected_entity_ids.is_empty():
		clear_selection()
		selection_cleared.emit()
	if _map != null and _map.has_cell(cell_pos):
		cell_clicked.emit(cell_pos)


## Convert a world-space position to screen-space (viewport coordinates).
func _world_to_screen(world_pos: Vector2) -> Vector2:
	if _camera == null:
		return world_pos
	var vp_size := get_viewport().get_visible_rect().size
	var cam_pos := _camera.position
	return (world_pos - cam_pos) * _zoom_level + vp_size * 0.5


func _handle_right_click(event: InputEventMouseButton) -> void:
	var local_pos := get_local_mouse_position()
	var cell_pos := IsometricGrid.screen_to_cell(local_pos)
	if _map == null:
		return
	# Emit context menu request with both grid and screen position.
	context_menu_requested.emit(cell_pos, event.position)
	get_viewport().set_input_as_handled()


## Returns the entity_id of the token closest to [param screen_pos] within
## ~15 pixels (CombatantToken.RADIUS * 1.5), or "" if none is near enough.
func _entity_id_near_screen_pos(screen_pos: Vector2) -> String:
	const HIT_RADIUS := 15.0  ## CombatantToken.RADIUS (10) * 1.5
	var best_eid := ""
	var best_dist := HIT_RADIUS
	for eid in _tokens.keys():
		var token: Node2D = _tokens[eid]
		var dist := screen_pos.distance_to(token.position)
		if dist < best_dist:
			best_dist = dist
			best_eid = eid
	return best_eid


# ---------------------------------------------------------------------------
# Exploration selection
# ---------------------------------------------------------------------------

## Select an entity (exploration mode). Clears previous selection unless
## [param additive] is true (Shift+click).
func select_entity(entity_id: String, additive: bool = false) -> void:
	if not additive:
		for old_id in _selected_entity_ids:
			if _tokens.has(old_id):
				_tokens[old_id].is_selected = false
		_selected_entity_ids.clear()

	if entity_id not in _selected_entity_ids:
		_selected_entity_ids.append(entity_id)
	if _tokens.has(entity_id):
		_tokens[entity_id].is_selected = true
	entity_selected.emit(entity_id)


## Deselect an entity.
func deselect_entity(entity_id: String) -> void:
	_selected_entity_ids.erase(entity_id)
	if _tokens.has(entity_id):
		_tokens[entity_id].is_selected = false
	entity_deselected.emit(entity_id)


## Clear all exploration selections.
func clear_selection() -> void:
	for eid in _selected_entity_ids:
		if _tokens.has(eid):
			_tokens[eid].is_selected = false
	_selected_entity_ids.clear()


## Select all entities on the given side (0=PARTY).
func select_all_on_side(side: int) -> void:
	clear_selection()
	for eid in _tokens.keys():
		var token: Node2D = _tokens[eid]
		if token.side == side:
			_selected_entity_ids.append(eid)
			token.is_selected = true


## Returns currently selected entity IDs.
func get_selected_entity_ids() -> Array[String]:
	return _selected_entity_ids.duplicate()


## Update the order overlay with current orders.
func update_order_overlay(orders: Dictionary) -> void:
	if _order_overlay != null and _order_overlay.has_method("update_overlays"):
		_order_overlay.update_overlays(orders)


## Clear the order overlay.
func clear_order_overlay() -> void:
	if _order_overlay != null and _order_overlay.has_method("clear_overlays"):
		_order_overlay.clear_overlays()


# ---------------------------------------------------------------------------
# Camera helpers
# ---------------------------------------------------------------------------

func _center_camera_on_party() -> void:
	if _camera == null or _controller == null:
		return
	var pos := _controller.get_party_position()
	_camera.position = IsometricGrid.cell_to_screen(pos.x, pos.y)


## Center camera on the first selected entity, falling back to party position.
func _center_camera_on_selected() -> void:
	if _camera == null:
		return
	if not _selected_entity_ids.is_empty() and _map != null:
		var pos := _map.get_entity_pos(_selected_entity_ids[0])
		if pos != Vector2i(-1, -1):
			_camera.position = IsometricGrid.cell_to_screen(pos.x, pos.y)
			return
	_center_camera_on_party()
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


## Zoom in/out. If [param center_on_screen] is provided (mouse wheel), the
## world point under the cursor stays fixed on screen; otherwise zoom is
## centered on the current camera view.
func _apply_zoom(new_zoom: float, center_on_screen: Vector2 = Vector2(-1, -1)) -> void:
	if _camera == null:
		return
	var old_zoom := _zoom_level
	_zoom_level = clampf(new_zoom, ZOOM_MIN, ZOOM_MAX)
	if _zoom_level == old_zoom:
		return

	if center_on_screen != Vector2(-1, -1):
		var vp_size := get_viewport().get_visible_rect().size
		var screen_center := vp_size * 0.5
		var screen_offset := center_on_screen - screen_center
		var world_point := _camera.position + screen_offset / old_zoom
		_camera.position = world_point - screen_offset / _zoom_level

	_camera.zoom = Vector2(_zoom_level, _zoom_level)


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
