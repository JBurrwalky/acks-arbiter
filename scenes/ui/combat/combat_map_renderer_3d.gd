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
## Generated terrain maps are a 70-cell diamond — they need a much longer
## zoom-out leash than the old small open field to frame the whole battlefield.
const ZOOM_MAX_TERRAIN := 64.0
const ZOOM_STEP := 1.0
const HIT_RADIUS_SCREEN := 20.0

## Pre-computed isometric camera basis vectors for rotation_degrees (-35.264, 0, 0).
const CAM_RIGHT := Vector3(1.0, 0.0, 0.0)
const CAM_UP := Vector3(0.0, 0.8165, -0.5774)
const CAM_BACKWARD := Vector3(0.0, 0.5774, 0.8165)


# ---------------------------------------------------------------------------
# Signals (identical to 2D combat_map_renderer.gd)
# ---------------------------------------------------------------------------

signal cell_clicked(pos: Vector3i)
signal entity_clicked(entity_id: String)
signal cell_right_clicked(cell_pos: Vector3i, screen_pos: Vector2)


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

var _voxel_map: VoxelMapData = null
var _tokens: Dictionary = {}         # entity_id -> CombatantToken3D | CharacterToken3D
var _highlight_layers: Array = []
var _target_rings: Array[String] = []
var _active_entity_id: String = ""
var _token_scene: PackedScene = null
var _character_token_scene: PackedScene = null
## Cached world-space map bounds over ALL levels (computed once in setup —
## _clamp_camera_to_map runs every pan frame and must not rescan 15k cells).
var _map_min_corner := Vector3.INF
var _map_max_corner := -Vector3.INF
var _zoom_max: float = ZOOM_MAX

const CharacterModelRegistryScript := preload("res://scenes/ui/components/character_model_registry.gd")


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Initialize the renderer with a voxel battle map and combat roster.
func setup(voxel_map: VoxelMapData, roster) -> void:
	_voxel_map = voxel_map

	# Create child node structure. LevelGroups mirrors the dungeon renderer's
	# per-level grouping; combat is single-level today (Level_0 only), but the
	# structure leaves room for future multi-level combat to drop in.
	# TODO: wire VisibilityManager once multi-level combat lands.
	_grid_meshes = Node3D.new()
	_grid_meshes.name = "LevelGroups"
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

	# Cache world bounds across all levels for camera framing/clamping.
	_compute_map_bounds()
	if _voxel_map != null and _voxel_map.natural_slopes:
		_zoom_max = ZOOM_MAX_TERRAIN

	# Build terrain
	_build_terrain()

	# Populate tokens from roster
	if roster != null:
		_populate_tokens(roster)

	# Center camera
	_center_camera()


func _populate_tokens(roster) -> void:
	for c in roster.get_all():
		var side_val: int = c.side
		var letter: String = c.display_name.substr(0, 1).to_upper()
		var class_id: String = ""
		var token_variant: String = ""
		var sex: String = "male"
		if c.is_character and c._character != null:
			class_id = c._character.character_class
			token_variant = c._character.token_variant
			sex = c._character.sex

		var token: Node3D = _instantiate_token(
			c.id, c.display_name, side_val, letter, class_id, token_variant, sex)
		_entity_layer.add_child(token)
		_tokens[c.id] = token

		# Position token on grid — snap, don't animate, on initial placement.
		# Guard both unplaced sentinels: (-1,-1,0) legacy and (-1,-1,-1) from
		# VoxelMapData.get_entity_pos.
		if c.grid_position.x >= 0 and c.grid_position.y >= 0:
			var world_pos := VoxelGrid.cell_to_world(
				c.grid_position.x, c.grid_position.y, c.grid_position.z)
			token.position = world_pos

		# Swarms: render the diffuse ENVELOPING area (translucent, HD-scaled),
		# NOT a solid multi-cell body — the swarm still MOVES as a 1x1 anchor.
		# Checked before is_multi_cell because a swarm's footprint is 1x1.
		if token.has_method("set_swarm_area") and c.is_swarm():
			token.set_swarm_area(c.get_swarm_area_local())
			token.set_facing(c.facing)
			if c.grid_position.x >= 0 and c.grid_position.y >= 0:
				token.apply_grid_footprint(c.grid_position)
		# Multi-cell creatures: stretch the placeholder to its footprint and
		# straddle its cells. Single-cell tokens are untouched (fast path).
		elif token.has_method("set_creature_size") and c.is_multi_cell():
			token.set_creature_size(
				c.get_footprint_local(),
				CreatureSize.height_scale(c.get_size_category()))
			token.set_facing(c.facing)
			if c.grid_position.x >= 0 and c.grid_position.y >= 0:
				token.apply_grid_footprint(c.grid_position)


func _build_terrain() -> void:
	if _voxel_map == null:
		return
	if _voxel_map.natural_slopes:
		# Generated wilderness terrain: every level renders (columns, textured
		# floors, obstacle placeholders, water) — outdoor daylight, no fog.
		for level: int in _voxel_map.get_levels():
			_grid_meshes.add_child(
				TacticalGrid3D.build_terrain_level_group(_voxel_map, level))
		return
	# Legacy flat battle map: single Level_0 group.
	var color_func := Callable(TacticalGrid3D, "combat_ground_color_voxel")
	var group := TacticalGrid3D.build_level_group(_voxel_map, 0, color_func, false)
	_grid_meshes.add_child(group)


# ---------------------------------------------------------------------------
# Highlight API (identical to 2D)
# ---------------------------------------------------------------------------

func set_combat_mode(_enabled: bool) -> void:
	pass  # Always in combat mode


func highlight_cells(cells: Array, color: Color) -> void:
	## Accepts Array[Vector3i] for voxel-native cells, or Array[Vector2i] for
	## same-level legacy callers (projected to the active combat level, z=0).
	_highlight_layers.append({"cells": cells, "color": color})
	_rebuild_highlights()


func highlight_entity_tokens(entity_ids: Array[String]) -> void:
	_target_rings = entity_ids.duplicate()
	for eid in entity_ids:
		if _tokens.has(eid):
			_tokens[eid].is_selected = true


func highlight_entity_tokens_with_color(entity_ids: Array[String], color: Color) -> void:
	## Highlights cells occupied by the given entities with the given color.
	## Used for HD-budget band coloring (Session 2.9): green for under-budget,
	## yellow for over-budget, red for over HD cap.
	var cells: Array = []
	for eid in entity_ids:
		if _tokens.has(eid):
			var token: Node3D = _tokens[eid]
			# VoxelGrid.world_to_cell takes a Vector3, not 3 floats.
			var cell := VoxelGrid.world_to_cell(token.position)
			cells.append(cell)
	if not cells.is_empty():
		highlight_cells(cells, color)


func highlight_cells_layered(layers: Array) -> void:
	## Convenience helper: adds multiple {cells, color} highlight layers at once.
	## Used for AoE preview ally-vs-enemy shading (Session 2.9).
	for layer in layers:
		var cells: Array = layer.get("cells", [])
		var color: Color = layer.get("color", Color.WHITE)
		if not cells.is_empty():
			highlight_cells(cells, color)


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


func move_token(entity_id: String, to_cell) -> void:
	if not _tokens.has(entity_id):
		return
	var pos: Vector3i
	if to_cell is Vector3i:
		pos = to_cell
	else:
		# Legacy 2D callers: land on the terrain surface, not the z=0 plane.
		var z: int = 0
		if _voxel_map != null and _voxel_map.natural_slopes:
			z = maxi(0, _voxel_map.surface_level_at(to_cell.x, to_cell.y))
		pos = Vector3i(to_cell.x, to_cell.y, z)
	var token: Node3D = _tokens[entity_id]
	# Multi-cell bodies re-straddle their (possibly rotated) footprint on the new
	# anchor; single-cell tokens use the plain position update.
	if token.has_method("apply_grid_footprint") \
			and not CreatureFootprint.is_single_cell(token.footprint_local):
		token.apply_grid_footprint(pos)
	else:
		var world_pos := VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
		token.update_position(world_pos)


func set_token_facing(entity_id: String, facing: Vector2i) -> void:
	if _tokens.has(entity_id):
		_tokens[entity_id].set_facing(facing)


## Forwarders for CharacterToken3D's procedural animations. No-op on the
## cylinder token, which lacks these methods.
func play_token_attack(entity_id: String, target_world_pos: Vector3) -> void:
	var token = _tokens.get(entity_id, null)
	if token != null and token.has_method("play_attack"):
		token.play_attack(target_world_pos)


func play_token_downed(entity_id: String) -> void:
	var token = _tokens.get(entity_id, null)
	if token != null and token.has_method("play_downed"):
		token.play_downed()


func play_token_revive(entity_id: String) -> void:
	var token = _tokens.get(entity_id, null)
	if token != null and token.has_method("play_revive"):
		token.play_revive()


func get_entity_token(entity_id: String) -> Node3D:
	return _tokens.get(entity_id, null)


func add_entity_token(entity_id: String, display_name: String, side: int, class_letter: String, class_id: String = "", token_variant: String = "", sex: String = "male") -> Node3D:
	if _tokens.has(entity_id):
		return _tokens[entity_id]
	var token := _instantiate_token(
		entity_id, display_name, side, class_letter, class_id, token_variant, sex)
	_entity_layer.add_child(token)
	_tokens[entity_id] = token
	return token


func _instantiate_token(entity_id: String, display_name: String, side: int,
		class_letter: String, class_id: String, token_variant: String,
		sex: String) -> Node3D:
	# Use the 3D character model when one exists for the triple; otherwise
	# fall back to the cylinder. has_any_model(class, sex) returns true when
	# at least one variant exists, so unknown variants still resolve to the
	# default model via CharacterToken3D.setup().
	if not class_id.is_empty() and CharacterModelRegistryScript.has_any_model(class_id, sex):
		if _character_token_scene == null:
			_character_token_scene = load("res://scenes/ui/components/character_token_3d.tscn")
		var char_token: Node3D = _character_token_scene.instantiate()
		char_token.setup(entity_id, display_name, side, class_letter,
			class_id, token_variant, sex)
		return char_token
	if _token_scene == null:
		_token_scene = load("res://scenes/ui/components/combatant_token_3d.tscn")
	var token: Node3D = _token_scene.instantiate()
	token.setup(entity_id, display_name, side, class_letter)
	var atlas: Texture2D = _lookup_atlas_for_class(class_id, token_variant)
	if atlas != null:
		token.set_sprite_atlas(atlas)
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
	if _highlight_layer == null or _voxel_map == null:
		return
	for child in _highlight_layer.get_children():
		child.queue_free()

	var terrain: bool = _voxel_map.natural_slopes
	for layer in _highlight_layers:
		var color: Color = layer.get("color", Color(1.0, 1.0, 0.0, 0.25))
		var cells_3d: Array[Vector3i] = []
		for pos in layer.get("cells", []):
			if pos is Vector3i:
				cells_3d.append(pos)
			elif pos is Vector2i:
				# Legacy 2D callers: project onto the terrain surface so the
				# overlay hugs the hillside instead of the buried z=0 plane.
				var z: int = 0
				if terrain:
					z = maxi(0, _voxel_map.surface_level_at(pos.x, pos.y))
				cells_3d.append(Vector3i(pos.x, pos.y, z))
		var mmi := TacticalGrid3D.build_highlight_overlay_voxel(cells_3d, color, _voxel_map)
		_highlight_layer.add_child(mmi)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or _voxel_map == null:
		return

	if event is InputEventMouseButton:
		# Mouse-wheel zoom on the orthographic camera. ZOOM_MIN gives a
		# tactical close-up; ZOOM_MAX shows the full map.
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size - ZOOM_STEP, ZOOM_MIN, _zoom_max)
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + ZOOM_STEP, ZOOM_MIN, _zoom_max)
			get_viewport().set_input_as_handled()
			return
		if not event.pressed:
			return

		var cell_pos_3d := _screen_to_surface_cell(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hit_eid := _entity_id_near(event.position)
			if not hit_eid.is_empty():
				entity_clicked.emit(hit_eid)
				get_viewport().set_input_as_handled()
				return
			if _voxel_map.has_cell(cell_pos_3d):
				cell_clicked.emit(cell_pos_3d)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cell_right_clicked.emit(cell_pos_3d, event.position)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _camera == null or _voxel_map == null:
		return

	# Keyboard pan (WASD + arrow keys, both supported per the prompt — the
	# dungeon HUD uses arrows for similar nav).
	var screen_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		screen_dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		screen_dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		screen_dir.y += 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		screen_dir.y -= 1.0

	# Edge-pan: when the mouse is within EDGE_MARGIN of a viewport edge, push
	# the camera in that direction. Skipped while the mouse is outside the
	# window (Godot returns Vector2(-INF, -INF) in that case).
	var viewport := get_viewport()
	if viewport != null:
		var vp_rect := viewport.get_visible_rect()
		var mouse: Vector2 = viewport.get_mouse_position()
		if vp_rect.has_point(mouse):
			if mouse.x < vp_rect.position.x + EDGE_MARGIN:
				screen_dir.x -= 1.0
			elif mouse.x > vp_rect.end.x - EDGE_MARGIN:
				screen_dir.x += 1.0
			if mouse.y < vp_rect.position.y + EDGE_MARGIN:
				screen_dir.y += 1.0
			elif mouse.y > vp_rect.end.y - EDGE_MARGIN:
				screen_dir.y -= 1.0

	if screen_dir != Vector2.ZERO:
		screen_dir = screen_dir.normalized()
		var world_dir := CAM_RIGHT * screen_dir.x + CAM_UP * screen_dir.y
		var speed_scale := _camera.size / 12.0
		_camera.position += world_dir * PAN_SPEED * speed_scale * delta
		_clamp_camera_to_map()


## Computes the world-space bounds of all stored cells (every level — terrain
## maps have columns well above level 0). Called once from setup().
func _compute_map_bounds() -> void:
	_map_min_corner = Vector3.INF
	_map_max_corner = -Vector3.INF
	if _voxel_map == null:
		return
	for pos in _voxel_map.get_all_positions():
		var w := VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
		_map_min_corner = _map_min_corner.min(w)
		_map_max_corner = _map_max_corner.max(w)


## Keeps the camera target above the voxel-map's bounds so the player cannot
## scroll into empty void. The orthographic camera's anchor is offset along
## CAM_BACKWARD; we clamp the projected XZ origin against the cached extents.
func _clamp_camera_to_map() -> void:
	if _camera == null or _voxel_map == null:
		return
	if _map_min_corner == Vector3.INF:
		return
	var cam_pos := _camera.position
	var anchor := cam_pos - CAM_BACKWARD * 50.0
	anchor.x = clampf(anchor.x, _map_min_corner.x, _map_max_corner.x)
	anchor.z = clampf(anchor.z, _map_min_corner.z, _map_max_corner.z)
	_camera.position = anchor + CAM_BACKWARD * 50.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Resolves a screen click to a map cell. On flat maps this is the legacy
## z=0 plane raycast; on terrain maps the ray is tested against each level
## plane from the top down and the first column whose SURFACE sits at that
## level wins — so clicking a hilltop selects the hilltop, not the ground
## cell hidden underneath it.
func _screen_to_surface_cell(screen_pos: Vector2) -> Vector3i:
	if _voxel_map == null or not _voxel_map.natural_slopes:
		return TacticalGrid3D.screen_to_cell_voxel(_camera, screen_pos, 0)
	var levels: Array[int] = _voxel_map.get_levels()
	for i in range(levels.size() - 1, -1, -1):
		var level: int = levels[i]
		var candidate := TacticalGrid3D.screen_to_cell_voxel(_camera, screen_pos, level)
		if candidate == Vector3i(-1, -1, -1):
			continue
		if _voxel_map.surface_level_at(candidate.x, candidate.y) == level:
			return candidate
	return TacticalGrid3D.screen_to_cell_voxel(_camera, screen_pos, 0)


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
	if _camera == null or _voxel_map == null:
		return
	if _map_min_corner == Vector3.INF:
		return
	# On terrain maps, open on the party entry rather than the map midpoint —
	# the encounter starts there and the full 70-cell diamond doesn't fit at
	# tactical zoom anyway.
	var center: Vector3
	if _voxel_map.natural_slopes:
		var entry := _voxel_map.entry_pos
		center = VoxelGrid.cell_to_world(entry.x, entry.y, entry.z)
	else:
		center = (_map_min_corner + _map_max_corner) * 0.5
	_camera.position = center + CAM_BACKWARD * 50.0
