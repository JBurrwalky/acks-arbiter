extends Node2D

## Standalone combat map renderer for wilderness encounters.
##
## Draws ground, features, grid, fog, and highlights on its own Node2D,
## with an EntityLayer child for CombatantTokens and a Camera2D.
## Adapted from DungeonMapRenderer but self-contained for use in the
## standalone CombatScreen.
##
## Provides the same highlight/selection interface that CombatUIController
## expects via duck-typed map_callbacks.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PAN_SPEED := 200.0
const EDGE_MARGIN := 40.0


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal cell_clicked(pos: Vector2i)
signal entity_clicked(entity_id: String)
signal right_click_cancel()
signal cell_right_clicked(cell_pos: Vector2i, screen_pos: Vector2)


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

var _entity_layer: Node2D = null
var _camera: Camera2D = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _map: TacticalMapData = null
var _tokens: Dictionary = {}  # entity_id -> CombatantToken
var _highlight_layers: Array = []
var _target_rings: Array[String] = []
var _active_entity_id: String = ""
var _token_scene: PackedScene = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Initialize the renderer with a tactical map and combat roster.
func setup(tactical_map: TacticalMapData, roster) -> void:
	_map = tactical_map

	# Create child nodes
	_entity_layer = Node2D.new()
	_entity_layer.name = "EntityLayer"
	add_child(_entity_layer)

	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	add_child(_camera)

	# Populate tokens from roster
	if roster != null:
		_populate_tokens(roster)

	# Center camera
	_center_camera()


func _populate_tokens(roster) -> void:
	if _token_scene == null:
		_token_scene = load("res://scenes/ui/components/combatant_token.tscn")

	for c in roster.get_all():
		var side_val: int = c.side
		var letter: String = c.display_name.substr(0, 1).to_upper()
		var class_id: String = ""
		var token_variant: String = ""
		if c.is_character and c._character != null:
			class_id = c._character.character_class
			token_variant = c._character.token_variant

		var token: Node2D = _token_scene.instantiate()
		token.setup(c.id, c.display_name, side_val, letter)
		var atlas: Texture2D = _lookup_atlas_for_class(class_id, token_variant)
		if atlas != null:
			token.set_sprite_atlas(atlas)
		_entity_layer.add_child(token)
		_tokens[c.id] = token

		# Position token on grid
		if c.grid_position != Vector2i(-1, -1):
			var screen_pos := IsometricGrid.cell_to_screen(c.grid_position.x, c.grid_position.y)
			token.update_position(screen_pos)


# ---------------------------------------------------------------------------
# Highlight API (matches DungeonMapRenderer interface)
# ---------------------------------------------------------------------------

func set_combat_mode(enabled: bool) -> void:
	pass  # Always in combat mode


func highlight_cells(cells: Array[Vector2i], color: Color) -> void:
	_highlight_layers.append({"cells": cells, "color": color})
	queue_redraw()


func highlight_entity_tokens(entity_ids: Array[String]) -> void:
	_target_rings = entity_ids.duplicate()
	for eid in entity_ids:
		if _tokens.has(eid):
			_tokens[eid].is_selected = true
	queue_redraw()


func clear_highlights() -> void:
	_highlight_layers.clear()
	for eid in _target_rings:
		if _tokens.has(eid):
			_tokens[eid].is_selected = false
	_target_rings.clear()
	queue_redraw()


func set_active_token(entity_id: String) -> void:
	if not _active_entity_id.is_empty() and _tokens.has(_active_entity_id):
		_tokens[_active_entity_id].is_active = false
	_active_entity_id = entity_id
	if not entity_id.is_empty() and _tokens.has(entity_id):
		_tokens[entity_id].is_active = true


func move_token(entity_id: String, to_cell: Vector2i) -> void:
	if _tokens.has(entity_id):
		var screen_pos := IsometricGrid.cell_to_screen(to_cell.x, to_cell.y)
		_tokens[entity_id].update_position(screen_pos)


func set_token_facing(entity_id: String, facing: Vector2i) -> void:
	if _tokens.has(entity_id):
		_tokens[entity_id].set_facing(facing)


func get_entity_token(entity_id: String) -> Node2D:
	return _tokens.get(entity_id, null)


func add_entity_token(entity_id: String, display_name: String, side: int, class_letter: String, class_id: String = "", token_variant: String = "") -> Node2D:
	if _tokens.has(entity_id):
		return _tokens[entity_id]
	if _token_scene == null:
		_token_scene = load("res://scenes/ui/components/combatant_token.tscn")
	var token: Node2D = _token_scene.instantiate()
	token.setup(entity_id, display_name, side, class_letter)
	var atlas: Texture2D = _lookup_atlas_for_class(class_id, token_variant)
	if atlas != null:
		token.set_sprite_atlas(atlas)
	_entity_layer.add_child(token)
	_tokens[entity_id] = token
	return token


static var _atlas_registry_script = null
static func _lookup_atlas_for_class(class_id: String, variant: String = "") -> Texture2D:
	if class_id.is_empty():
		return null
	if _atlas_registry_script == null:
		_atlas_registry_script = load("res://scenes/ui/components/token_atlas_registry.gd")
	if _atlas_registry_script == null:
		return null
	return _atlas_registry_script.get_atlas_for_class(class_id, variant)


func remove_entity_token(entity_id: String) -> void:
	if _tokens.has(entity_id):
		if is_instance_valid(_tokens[entity_id]):
			_tokens[entity_id].queue_free()
		_tokens.erase(entity_id)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _map == null:
		return
	_draw_ground()
	_draw_grid_lines()
	_draw_highlights()


func _draw_ground() -> void:
	for pos in _map._cells.keys():
		var cell: Dictionary = _map._cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		var color := _ground_color(tf)
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
		var pts := _diamond_points(screen_pos)
		draw_colored_polygon(pts, color)


func _draw_grid_lines() -> void:
	for pos in _map._cells.keys():
		var screen_pos := IsometricGrid.cell_to_screen(pos.x, pos.y)
		var pts := _diamond_points(screen_pos)
		var closed := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(closed, Color(0.0, 0.0, 0.0, 0.4), 1.0, true)


func _draw_highlights() -> void:
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


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return

	var local_pos := get_local_mouse_position()
	var cell_pos := IsometricGrid.screen_to_cell(local_pos)

	if event.button_index == MOUSE_BUTTON_LEFT:
		var hit_eid := _entity_id_near(local_pos)
		if not hit_eid.is_empty():
			entity_clicked.emit(hit_eid)
			get_viewport().set_input_as_handled()
			return
		if _map != null and _map.has_cell(cell_pos):
			cell_clicked.emit(cell_pos)
			get_viewport().set_input_as_handled()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		cell_right_clicked.emit(cell_pos, event.position)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _camera == null:
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
	if pan_dir != Vector2.ZERO:
		_camera.position += pan_dir.normalized() * PAN_SPEED * delta


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _entity_id_near(screen_pos: Vector2) -> String:
	const HIT_RADIUS := 15.0
	var best_eid := ""
	var best_dist := HIT_RADIUS
	for eid in _tokens.keys():
		var token: Node2D = _tokens[eid]
		var dist := screen_pos.distance_to(token.position)
		if dist < best_dist:
			best_dist = dist
			best_eid = eid
	return best_eid


func _center_camera() -> void:
	if _camera == null or _map == null:
		return
	# Center on the midpoint of all cells
	var sum := Vector2.ZERO
	var count := 0
	for pos in _map._cells.keys():
		sum += IsometricGrid.cell_to_screen(pos.x, pos.y)
		count += 1
	if count > 0:
		_camera.position = sum / float(count)


func _ground_color(tf: String) -> Color:
	match tf:
		"open":
			return Color(0.45, 0.55, 0.35)  # grass/field
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


func _diamond_points(screen_pos: Vector2) -> PackedVector2Array:
	var hw := float(IsometricGrid.HALF_W)
	var hh := float(IsometricGrid.HALF_H)
	return PackedVector2Array([
		screen_pos + Vector2(0.0, -hh),
		screen_pos + Vector2(hw, 0.0),
		screen_pos + Vector2(0.0, hh),
		screen_pos + Vector2(-hw, 0.0),
	])
