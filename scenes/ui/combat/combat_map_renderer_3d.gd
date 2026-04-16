extends Node3D

## 3D standalone combat map renderer for wilderness encounters.
##
## No class_name — this is a scene script, not a reusable type.
##
## Replaces the 2D combat_map_renderer.gd with identical signals and public
## API so that CombatScreen, CombatUIController, and other consumers can
## use it as a drop-in replacement.
##
## Simpler than the dungeon renderer: no fog, no doors, no exploration
## selection, no control groups. Just terrain-colored floor cells, entity
## tokens, highlights, and input.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PAN_SPEED := 8.0
const EDGE_MARGIN := 40.0
const ZOOM_MIN := 4.0
const ZOOM_MAX := 30.0
const ZOOM_STEP := 1.0
const HIT_RADIUS_SCREEN := 20.0

## Pre-computed isometric camera basis vectors for rotation_degrees (-35.264, 0, 0).
const CAM_RIGHT := Vector3(1.0, 0.0, 0.0)
const CAM_UP := Vector3(0.0, 0.8165, -0.5774)
const CAM_BACKWARD := Vector3(0.0, 0.5774, 0.8165)


# ---------------------------------------------------------------------------
# Signals (identical to 2D combat_map_renderer.gd)
# ---------------------------------------------------------------------------

signal cell_clicked(pos: Vector2i)
signal entity_clicked(entity_id: String)
signal right_click_cancel()
signal cell_right_clicked(cell_pos: Vector2i, screen_pos: Vector2)


# ---------------------------------------------------------------------------
# Internal nodes (created in setup)
# ---------------------------------------------------------------------------

var _grid_meshes: Node3D = null
var _entity_layer: Node3D = null
var _highlight_layer: Node3D = null
var _camera: Camera3D = null
var _light: DirectionalLight3D = null
var _env: WorldEnvironment = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _map: TacticalMapData = null
var _tokens: Dictionary = {}         # entity_id -> CombatantToken3D
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

	# Create child node structure
	_grid_meshes = Node3D.new()
	_grid_meshes.name = "GridMeshes"
	add_child(_grid_meshes)

	_highlight_layer = Node3D.new()
	_highlight_layer.name = "HighlightLayer"
	add_child(_highlight_layer)

	_entity_layer = Node3D.new()
	_entity_layer.name = "EntityLayer"
	add_child(_entity_layer)

	# Camera
	_camera = TacticalGrid3D.create_isometric_camera()
	add_child(_camera)

	# Lighting
	_light = TacticalGrid3D.create_directional_light()
	add_child(_light)

	_env = TacticalGrid3D.create_environment()
	add_child(_env)

	# Build terrain
	_build_terrain()

	# Populate tokens from roster
	if roster != null:
		_populate_tokens(roster)

	# Center camera
	_center_camera()


func _populate_tokens(roster) -> void:
	if _token_scene == null:
		_token_scene = load("res://scenes/ui/components/combatant_token_3d.tscn")

	for c in roster.get_all():
		var side_val: int = c.side
		var letter: String = c.display_name.substr(0, 1).to_upper()
		var class_id: String = ""
		var token_variant: String = ""
		if c.is_character and c._character != null:
			class_id = c._character.character_class
			token_variant = c._character.token_variant

		var token: Node3D = _token_scene.instantiate()
		token.setup(c.id, c.display_name, side_val, letter)
		var atlas: Texture2D = _lookup_atlas_for_class(class_id, token_variant)
		if atlas != null:
			token.set_sprite_atlas(atlas)
		_entity_layer.add_child(token)
		_tokens[c.id] = token

		# Position token on grid
		if c.grid_position != Vector2i(-1, -1):
			var world_pos := TacticalGrid3D.cell_to_world(c.grid_position.x, c.grid_position.y)
			token.update_position(world_pos)


func _build_terrain() -> void:
	if _map == null:
		return

	# Floor cells — use combat ground colors
	var floor_mmi := TacticalGrid3D.build_floor_multimesh(_map, Callable(TacticalGrid3D, "combat_ground_color"))
	floor_mmi.name = "FloorCells"
	_grid_meshes.add_child(floor_mmi)

	# Grid lines
	var grid_lines := TacticalGrid3D.build_grid_lines(_map)
	_grid_meshes.add_child(grid_lines)


# ---------------------------------------------------------------------------
# Highlight API (identical to 2D)
# ---------------------------------------------------------------------------

func set_combat_mode(_enabled: bool) -> void:
	pass  # Always in combat mode


func highlight_cells(cells: Array[Vector2i], color: Color) -> void:
	_highlight_layers.append({"cells": cells, "color": color})
	_rebuild_highlights()


func highlight_entity_tokens(entity_ids: Array[String]) -> void:
	_target_rings = entity_ids.duplicate()
	for eid in entity_ids:
		if _tokens.has(eid):
			_tokens[eid].is_selected = true


func clear_highlights() -> void:
	_highlight_layers.clear()
	for eid in _target_rings:
		if _tokens.has(eid):
			_tokens[eid].is_selected = false
	_target_rings.clear()
	_rebuild_highlights()


func set_active_token(entity_id: String) -> void:
	if not _active_entity_id.is_empty() and _tokens.has(_active_entity_id):
		_tokens[_active_entity_id].is_active = false
	_active_entity_id = entity_id
	if not entity_id.is_empty() and _tokens.has(entity_id):
		_tokens[entity_id].is_active = true


func move_token(entity_id: String, to_cell: Vector2i) -> void:
	if _tokens.has(entity_id):
		var world_pos := TacticalGrid3D.cell_to_world(to_cell.x, to_cell.y)
		_tokens[entity_id].update_position(world_pos)


func set_token_facing(entity_id: String, facing: Vector2i) -> void:
	if _tokens.has(entity_id):
		_tokens[entity_id].set_facing(facing)


func get_entity_token(entity_id: String) -> Node3D:
	return _tokens.get(entity_id, null)


func add_entity_token(entity_id: String, display_name: String, side: int, class_letter: String, class_id: String = "", token_variant: String = "") -> Node3D:
	if _tokens.has(entity_id):
		return _tokens[entity_id]
	if _token_scene == null:
		_token_scene = load("res://scenes/ui/components/combatant_token_3d.tscn")
	var token: Node3D = _token_scene.instantiate()
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


func _rebuild_highlights() -> void:
	if _highlight_layer == null:
		return
	for child in _highlight_layer.get_children():
		child.queue_free()
	for layer in _highlight_layers:
		var color: Color = layer.get("color", Color(1.0, 1.0, 0.0, 0.25))
		var cells: Array[Vector2i] = []
		for pos in layer.get("cells", []):
			cells.append(pos)
		var mmi := TacticalGrid3D.build_highlight_overlay(cells, color, _map)
		_highlight_layer.add_child(mmi)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return

	if _camera == null:
		return

	var cell_pos := TacticalGrid3D.screen_to_cell(_camera, event.position)

	if event.button_index == MOUSE_BUTTON_LEFT:
		var hit_eid := _entity_id_near(event.position)
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
	var screen_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		screen_dir.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		screen_dir.x += 1.0
	if Input.is_action_pressed("ui_up"):
		screen_dir.y += 1.0
	if Input.is_action_pressed("ui_down"):
		screen_dir.y -= 1.0
	if screen_dir != Vector2.ZERO:
		screen_dir = screen_dir.normalized()
		var world_dir := CAM_RIGHT * screen_dir.x + CAM_UP * screen_dir.y
		var speed_scale := _camera.size / 12.0
		_camera.position += world_dir * PAN_SPEED * speed_scale * delta


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _entity_id_near(screen_pos: Vector2) -> String:
	if _camera == null:
		return ""
	var best_eid := ""
	var best_dist := HIT_RADIUS_SCREEN
	for eid in _tokens.keys():
		var token: Node3D = _tokens[eid]
		var token_screen := _camera.unproject_position(token.global_position)
		var dist := screen_pos.distance_to(token_screen)
		if dist < best_dist:
			best_dist = dist
			best_eid = eid
	return best_eid


func _center_camera() -> void:
	if _camera == null or _map == null:
		return
	var sum := Vector3.ZERO
	var count := 0
	for pos in _map._cells.keys():
		sum += TacticalGrid3D.cell_to_world(pos.x, pos.y)
		count += 1
	if count > 0:
		var center := sum / float(count)
		# Offset along camera's backward direction to keep geometry in near/far range
		_camera.position = center + CAM_BACKWARD * 50.0
