extends Node3D

## 3D isometric dungeon map renderer.
##
## No class_name — this is a scene script, not a reusable type.
##
## Implements the ManagedScene duck-typed interface (enter/exit/save_state/restore_state)
## for integration with NavigationStack.
##
## Replaces the 2D dungeon_map_renderer.gd with identical signals and public
## API so that DungeonExploreState, DungeonCombatOverlay, and other consumers
## can use it as a drop-in replacement.
##
## All rendering uses Godot 3D primitives: MultiMeshInstance3D for floors,
## MeshInstance3D for walls/doors, CombatantToken3D for entity tokens,
## and Label3D for feature icons.
##
## Call setup(controller) before entering the scene tree.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PAN_SPEED := 8.0           ## World units per second for camera pan
const EDGE_MARGIN := 40.0        ## Pixels from viewport edge to trigger pan
const ZOOM_MIN := 4.0            ## Minimum orthographic size (zoomed in)
const ZOOM_MAX := 30.0           ## Maximum orthographic size (zoomed out)
const ZOOM_STEP := 1.0           ## Orthographic size change per scroll tick
const DRAG_SELECT_THRESHOLD := 5.0  ## Pixels before drag-select activates
const TOKEN_MOVE_DURATION := 0.15   ## Fallback seconds per cell hop (legacy/combat)
const DOUBLE_TAP_THRESHOLD := 0.3   ## Seconds for double-tap detection
const HIT_RADIUS_SCREEN := 20.0    ## Screen pixels for entity hit detection

## Per-level albedo tints per GDD §16.2. FULL_COLOR on the focus level,
## DIM_COLOR on explored levels below focus (0.6× brightness). The tint is
## multiplied into each mesh's stored base_color by
## [method TacticalGrid3D.set_level_group_tint].
const DIM_COLOR := Color(0.6, 0.6, 0.6, 1.0)
const FULL_COLOR := Color.WHITE

## Alpha applied to enemy-token body material on explored non-focus levels
## (party tokens stay at full opacity so the player never loses them).
const NON_FOCUS_ENEMY_ALPHA := 0.5

## Pre-computed isometric camera basis vectors for rotation_degrees (-35.264, 0, 0).
## Diamond layout is baked into cell_to_world(), so no Y rotation needed.
## Camera right (+X local in world space):
const CAM_RIGHT := Vector3(1.0, 0.0, 0.0)
## Camera up (+Y local in world space):
const CAM_UP := Vector3(0.0, 0.8165, -0.5774)
## Camera backward (+Z local in world space = direction behind camera):
const CAM_BACKWARD := Vector3(0.0, 0.5774, 0.8165)


# ---------------------------------------------------------------------------
# Node references (set in _ready from scene tree)
# ---------------------------------------------------------------------------

@onready var _grid_meshes: Node3D = $GridMeshes
@onready var _fog_layer: Node3D = $FogLayer
@onready var _highlight_layer: Node3D = $HighlightLayer
@onready var _entity_layer: Node3D = $EntityLayer
@onready var _camera: Camera3D = $Camera3D
@onready var _tooltip_panel = $DungeonHUD/TooltipPanel
@onready var _tooltip_label = $DungeonHUD/TooltipPanel/TooltipLabel
@onready var _context_menu_layer = $DungeonHUD/ContextMenuLayer


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _controller: DungeonMapController
var _voxel_map: VoxelMapData = null
var _visibility_manager: VisibilityManager = null  # Voxel path
var _level_strip_widget: Node = null                # Session 8 HUD
var _offscreen_indicators: Node = null              # Session 8 HUD
var _dungeon_id: String = ""

## CombatantToken3D nodes indexed by entity_id.
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

## Loaded lazily on first token creation.
var _token_scene: PackedScene = null
var _character_token_scene: PackedScene = null

const CharacterModelRegistryScript := preload("res://scenes/ui/components/character_model_registry.gd")

## Currently selected entity IDs (exploration mode selection).
var _selected_entity_ids: Array[String] = []

## Reference to the order overlay child (set in _ready if present).
var _order_overlay: Node3D = null

## Wall mesh instances keyed by cell position for camera-occluding fade.
## { Vector2i -> MeshInstance3D }
var _wall_meshes: Dictionary = {}
## Set of wall cell positions currently faded (to restore on next frame).
var _faded_walls: Dictionary = {}

## Middle-mouse drag state for camera panning.
var _middle_dragging: bool = false
var _middle_drag_start: Vector2 = Vector2.ZERO

## Drag-select (rubber-band) state — tracked in screen space.
var _drag_selecting: bool = false
var _drag_select_start: Vector2 = Vector2.ZERO
var _drag_select_end: Vector2 = Vector2.ZERO

## Drag-select visual rectangle (CanvasLayer overlay).
var _drag_rect: ColorRect = null

## Movement animation queues per entity (legacy path, used for combat/Max speed).
## { entity_id: Array[Vector3] } — queued world positions to tween through.
var _move_queues: Dictionary = {}
## Entities currently mid-tween (waiting for tween to finish before next step).
var _tweening: Dictionary = {}  # { entity_id: true }

## Continuous movement animations (renderer-driven, used for exploration movement).
## { entity_id: { "path": Array[Vector3i], "path_index": int, "cells_per_round": float } }
## Path elements are Vector3i voxel cells. Legacy 2D paths ride through as Vector2i
## until the legacy renderer path is deleted in D.2.
var _active_movements: Dictionary = {}
## Current clock speed (mirrors SchedulerLoop speed via EventBus signal).
var _clock_speed: int = 0  # SchedulerLoop.SPEED_PAUSED

## Double-click detection for control group recall.
var _last_number_key: int = -1
var _last_number_key_time: float = 0.0


# ---------------------------------------------------------------------------
# Signals (identical to 2D dungeon_map_renderer.gd)
# ---------------------------------------------------------------------------

signal cell_clicked(pos: Vector2i)
signal exit_requested()
signal entity_clicked(entity_id: String)
signal entity_selected(entity_id: String)
signal entity_deselected(entity_id: String)
signal selection_cleared()
signal context_menu_requested(cell_pos: Vector2i, screen_pos: Vector2)
signal cell_right_clicked(cell_pos: Vector2i, screen_pos: Vector2)
signal control_group_select_requested(entity_id: String)
signal control_group_assign_requested(group_number: int, entity_ids: Array)
signal control_group_recall_requested(group_number: int)
signal minimap_toggle_requested()

## Renderer-driven movement animation callbacks.
## Emitted when a continuous movement tween crosses a cell boundary.
## In voxel mode, cell is a Vector3i; in legacy 2D mode, Vector2i.
## Kept as untyped Variant so both path types can ride through until D.2 flag removal.
signal movement_cell_reached(entity_id: String, cell)
## Emitted when the full movement path animation completes.
signal movement_path_complete(entity_id: String)


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
	# Renderer-driven movement animation relay signals.
	controller.movement_animation_requested.connect(start_movement_animation)
	controller.movement_animation_cancelled.connect(cancel_movement_animation)
	# Clock speed changes control tween speed_scale.
	EventBus.scheduler_speed_changed.connect(_on_clock_speed_changed)

	# Set up VisibilityManager for per-level focus + opacity.
	_voxel_map = controller.get_voxel_map()
	_visibility_manager = VisibilityManager.new()
	add_child(_visibility_manager)
	_visibility_manager.focus_level_changed.connect(_on_focus_level_changed)
	if _voxel_map != null:
		_visibility_manager.update_explored_levels(_voxel_map)
		_visibility_manager.focus_level = controller.get_current_level()

	# Session 8 HUD widgets + auto-focus/portrait-click wiring.
	_setup_hud_widgets()
	if not EventBus.dungeon_auto_focus_requested.is_connected(_on_dungeon_auto_focus_requested):
		EventBus.dungeon_auto_focus_requested.connect(_on_dungeon_auto_focus_requested)
	if not EventBus.party_portrait_clicked.is_connected(_on_party_portrait_clicked):
		EventBus.party_portrait_clicked.connect(_on_party_portrait_clicked)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false
	_order_overlay = get_node_or_null("OrderOverlayLayer")

	# Configure camera for isometric view.
	# The diamond layout is already baked into cell_to_world() coordinates,
	# so Y rotation must be 0 — only X tilt is needed.
	if _camera != null:
		_camera.rotation_degrees = Vector3(-35.264, 0.0, 0.0)
		_camera.position = Vector3(0.0, 15.0, 10.0)

	# Configure directional light
	var light := get_node_or_null("DirectionalLight3D")
	if light != null:
		light.rotation_degrees = Vector3(-60.0, -30.0, 0.0)

	# Add WorldEnvironment for background color and ambient light
	var world_env := TacticalGrid3D.create_environment()
	add_child(world_env)

	# Create drag-select rectangle overlay (2D on CanvasLayer)
	_drag_rect = ColorRect.new()
	_drag_rect.visible = false
	_drag_rect.color = Color(0.2, 0.6, 1.0, 0.15)
	_drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud := get_node_or_null("DungeonHUD")
	if hud != null:
		hud.add_child(_drag_rect)


func _process(delta: float) -> void:
	if _camera == null or _voxel_map == null:
		return

	# WASD camera pan (no mouse-to-edge scrolling)
	var screen_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		screen_dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		screen_dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		screen_dir.y += 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		screen_dir.y -= 1.0

	if screen_dir != Vector2.ZERO:
		screen_dir = screen_dir.normalized()
		var world_dir := CAM_RIGHT * screen_dir.x + CAM_UP * screen_dir.y
		var speed_scale := _camera.size / 12.0
		_camera.position += world_dir * PAN_SPEED * speed_scale * delta

	# Update drag-select rectangle visual
	if _drag_selecting and _drag_rect != null:
		_drag_rect.visible = true
		var rect_pos := Vector2(
			minf(_drag_select_start.x, _drag_select_end.x),
			minf(_drag_select_start.y, _drag_select_end.y)
		)
		var rect_size := Vector2(
			absf(_drag_select_end.x - _drag_select_start.x),
			absf(_drag_select_end.y - _drag_select_start.y)
		)
		_drag_rect.position = rect_pos
		_drag_rect.size = rect_size

	# Fade walls that occlude party tokens from the camera's viewpoint
	_update_wall_occlusion()


# ---------------------------------------------------------------------------
# ManagedScene interface
# ---------------------------------------------------------------------------

func enter(params: Dictionary = {}) -> void:
	_dungeon_id = params.get("dungeon_id", _dungeon_id)
	_refresh_all()
	_center_camera_on_party()


func exit() -> void:
	cancel_all_movement_animations()
	if EventBus.scheduler_speed_changed.is_connected(_on_clock_speed_changed):
		EventBus.scheduler_speed_changed.disconnect(_on_clock_speed_changed)


func save_state() -> Dictionary:
	return {"dungeon_id": _dungeon_id}


func restore_state(data: Dictionary) -> void:
	_dungeon_id = data.get("dungeon_id", _dungeon_id)


# ---------------------------------------------------------------------------
# Signal handlers (from DungeonMapController)
# ---------------------------------------------------------------------------

func _on_map_loaded(_id: String) -> void:
	_voxel_map = _controller.get_voxel_map()
	if _visibility_manager != null and _voxel_map != null:
		_visibility_manager.update_explored_levels(_voxel_map)
		_visibility_manager.focus_level = _controller.get_current_level()
	if _camera != null:
		_camera.size = 12.0
	_refresh_all()
	_refresh_visibility_party_positions()
	_center_camera_on_party()


func _on_fog_updated() -> void:
	_voxel_map = _controller.get_voxel_map()
	if _visibility_manager != null and _voxel_map != null:
		_visibility_manager.update_explored_levels(_voxel_map)
	# Rebuild level groups to reflect fog changes
	_rebuild_grid_voxel()
	if _level_strip_widget != null and _level_strip_widget.has_method("refresh"):
		_level_strip_widget.refresh()


func _on_party_moved(_from, _to) -> void:
	# Signal is untyped to carry Vector2i (legacy) or Vector3i (voxel).
	_update_entity_tokens()
	_refresh_visibility_party_positions()


func _on_entity_moved(entity_id: String, _from_pos, to_pos) -> void:
	# If this entity has an active continuous animation, ignore — the renderer
	# is already driving its visual position via start_movement_animation().
	if _active_movements.has(entity_id):
		_refresh_visibility_party_positions_if_party(entity_id)
		return
	if not _tokens.has(entity_id):
		return

	_refresh_visibility_party_positions_if_party(entity_id)

	var pos: Vector3i = to_pos if to_pos is Vector3i else Vector3i(to_pos.x, to_pos.y, _controller.get_current_level())
	var target_world: Vector3 = VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
	target_world.y += 0.2

	# At MAX speed, snap instantly (no tween).
	if _clock_speed == SchedulerLoop.SPEED_MAX:
		_tokens[entity_id].update_position(target_world)
		return

	# Legacy path: queue and tween (used for combat moves and fallback).
	if not _move_queues.has(entity_id):
		_move_queues[entity_id] = []
	_move_queues[entity_id].append(target_world)

	if not _tweening.has(entity_id):
		_process_move_queue(entity_id)


## Animate the next queued movement step for [param entity_id].
## Chains tweens: each tween completion triggers the next step.
func _process_move_queue(entity_id: String) -> void:
	if not _move_queues.has(entity_id) or _move_queues[entity_id].is_empty():
		_move_queues.erase(entity_id)
		_tweening.erase(entity_id)
		return

	if not _tokens.has(entity_id):
		_move_queues.erase(entity_id)
		_tweening.erase(entity_id)
		return

	var token: Node3D = _tokens[entity_id]
	var target_world: Vector3 = _move_queues[entity_id].pop_front()
	_tweening[entity_id] = true

	# Kill any stale tween on this token.
	if token.has_meta("move_tween"):
		var old_tween: Tween = token.get_meta("move_tween")
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()

	var tween: Tween = create_tween()
	tween.tween_property(token, "position", target_world, TOKEN_MOVE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(_on_move_tween_finished.bind(entity_id))
	token.set_meta("move_tween", tween)


## Called when a single cell-hop tween finishes — process the next queued step.
func _on_move_tween_finished(entity_id: String) -> void:
	_process_move_queue(entity_id)


# ---------------------------------------------------------------------------
# Continuous movement animation (renderer-driven exploration movement)
# ---------------------------------------------------------------------------

## Begin a continuous animation along [param path] for [param entity_id].
## The renderer pre-computes per-cell tween durations from [param cells_per_round]
## and the current clock speed, and starts animating immediately.
## Each cell boundary crossing emits [signal movement_cell_reached] so the
## mechanical layer can update the entity's tactical position.
func start_movement_animation(
		entity_id: String, path: Array, cells_per_round_val: float) -> void:
	# Kill any existing animation (old order being replaced).
	_kill_entity_tween(entity_id)
	_move_queues.erase(entity_id)
	_tweening.erase(entity_id)

	if path.is_empty() or not _tokens.has(entity_id):
		return

	# At MAX speed, don't animate — the scheduler tick handles positions.
	if _clock_speed == SchedulerLoop.SPEED_MAX:
		return

	_active_movements[entity_id] = {
		"path": path.duplicate(),
		"path_index": 0,
		"cells_per_round": cells_per_round_val,
	}

	_advance_movement_animation(entity_id)


## Start the tween for the next cell in the continuous movement path.
func _advance_movement_animation(entity_id: String) -> void:
	if not _active_movements.has(entity_id):
		return
	var movement: Dictionary = _active_movements[entity_id]
	var path: Array = movement["path"]
	var idx: int = movement["path_index"]

	if idx >= path.size():
		# Reached end of path — signal completion.
		_active_movements.erase(entity_id)
		_tweening.erase(entity_id)
		movement_path_complete.emit(entity_id)
		return

	if not _tokens.has(entity_id):
		_active_movements.erase(entity_id)
		_tweening.erase(entity_id)
		return

	var next_cell: Vector3i = path[idx]
	# Voxel path: level is encoded in z, world Y comes from VoxelGrid.
	var target_world := VoxelGrid.cell_to_world(next_cell.x, next_cell.y, next_cell.z)

	var token: Node3D = _tokens[entity_id]
	_tweening[entity_id] = true

	_kill_entity_tween(entity_id)

	# Base duration: real seconds per cell at 1x speed, timescale 1.0.
	var cpr: float = movement["cells_per_round"]
	var base_duration: float = SchedulerLoop.SECONDS_PER_ROUND / maxf(cpr, 0.01)

	var tween: Tween = create_tween()
	tween.tween_property(token, "position", target_world, base_duration)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)

	# Scale playback speed to match the game clock speed.
	var speed_scale: float = _compute_speed_scale()
	tween.set_speed_scale(speed_scale)

	tween.finished.connect(
		_on_continuous_move_finished.bind(entity_id, next_cell))
	token.set_meta("move_tween", tween)


## Called when one cell-hop of a continuous movement finishes.
## Emits [signal movement_cell_reached] for the mechanical update, then
## continues to the next segment (or signals path completion).
## reached_cell is Vector3i in voxel mode, Vector2i in legacy 2D mode.
func _on_continuous_move_finished(entity_id: String, reached_cell) -> void:
	_tweening.erase(entity_id)

	if not _active_movements.has(entity_id):
		return

	# Notify the mechanical layer (DungeonExploreState → DungeonHandlers).
	# This may result in cancel_movement_animation() being called synchronously
	# if the cell is impassable, which clears _active_movements for this entity.
	movement_cell_reached.emit(entity_id, reached_cell)

	# If the signal handler cancelled the animation, stop here.
	if not _active_movements.has(entity_id):
		return

	var movement: Dictionary = _active_movements[entity_id]
	movement["path_index"] += 1
	_advance_movement_animation(entity_id)


## Cancel a continuous movement animation and snap the token to its current
## mechanical position on the tactical map.
func cancel_movement_animation(entity_id: String) -> void:
	_active_movements.erase(entity_id)
	_kill_entity_tween(entity_id)
	_tweening.erase(entity_id)
	_move_queues.erase(entity_id)
	_snap_to_mechanical_position(entity_id)


## Cancel all active continuous movement animations.
func cancel_all_movement_animations() -> void:
	var ids: Array = _active_movements.keys().duplicate()
	for entity_id in ids:
		cancel_movement_animation(entity_id)


## Compute the tween speed_scale from the current clock speed.
## Returns 0.0 when paused (tween freezes), positive for normal play.
func _compute_speed_scale() -> float:
	if _clock_speed <= 0:
		return 0.0  # paused or MAX (MAX should not create tweens)
	return float(_clock_speed) * SchedulerLoop.TIMESCALE_DUNGEON


## Handle clock speed changes — update tween playback speed or cancel for MAX.
func _on_clock_speed_changed(new_speed: int) -> void:
	_clock_speed = new_speed

	if new_speed == SchedulerLoop.SPEED_MAX:
		# MAX speed: renderer yields to scheduler. Kill all continuous animations.
		cancel_all_movement_animations()
		return

	var new_scale: float = _compute_speed_scale()
	# Update speed_scale on all active continuous movement tweens.
	for entity_id in _active_movements:
		if not _tokens.has(entity_id):
			continue
		var token: Node3D = _tokens[entity_id]
		if token.has_meta("move_tween"):
			var tween: Tween = token.get_meta("move_tween")
			if tween != null and tween.is_valid():
				tween.set_speed_scale(new_scale)


## Kill the tween on a token (if any).
func _kill_entity_tween(entity_id: String) -> void:
	if not _tokens.has(entity_id):
		return
	var token: Node3D = _tokens[entity_id]
	if token.has_meta("move_tween"):
		var old_tween: Tween = token.get_meta("move_tween")
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
		token.remove_meta("move_tween")


## Snap a token to its current mechanical position on the voxel map.
func _snap_to_mechanical_position(entity_id: String) -> void:
	if not _tokens.has(entity_id) or _controller == null:
		return
	var vmap := _controller.get_voxel_map()
	if vmap == null:
		return
	var pos: Vector3i = vmap.get_entity_pos(entity_id)
	if pos == Vector3i(-1, -1, -1):
		return
	_tokens[entity_id].update_position(
		VoxelGrid.cell_to_world(pos.x, pos.y, pos.z))


## Returns the list of entity IDs with active continuous movement animations.
func get_animating_entity_ids() -> Array:
	return _active_movements.keys()


func _on_door_state_changed(_pos, _old: String, _new: String) -> void:
	# Signal is untyped to carry Vector2i (legacy) or Vector3i (voxel).
	_rebuild_grid()


func _on_level_changed(_from_level: int, to_level: int) -> void:
	_voxel_map = _controller.get_voxel_map()
	if _visibility_manager != null:
		_visibility_manager.update_explored_levels(_voxel_map)
		_visibility_manager.set_focus_level(to_level)
	_refresh_all()
	_center_camera_on_party()


# ---------------------------------------------------------------------------
# Grid rebuilding
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	if _controller != null:
		_voxel_map = _controller.get_voxel_map()
	_rebuild_grid()
	_update_entity_tokens()


func _rebuild_grid() -> void:
	_rebuild_grid_voxel()


## Voxel path: builds per-level groups under _grid_meshes (acting as LevelGroups).
func _rebuild_grid_voxel() -> void:
	if _voxel_map == null or _grid_meshes == null:
		return

	# Remove existing level groups from the tree IMMEDIATELY so newly-added
	# children don't get name collisions (Godot auto-appends "@Node@..." suffixes
	# to duplicates, which breaks _apply_level_visibility's int-parse of the
	# level number and leaves upper levels rendering — the "ceiling returns
	# after a move" symptom). queue_free defers the destructor.
	for child in _grid_meshes.get_children():
		_grid_meshes.remove_child(child)
		child.queue_free()

	_wall_meshes.clear()
	_faded_walls.clear()

	var focus_level: int = _visibility_manager.focus_level if _visibility_manager != null else 0
	var color_func := Callable(TacticalGrid3D, "floor_color_for_voxel")

	for level: int in _voxel_map.get_levels():
		var use_individual := (level == focus_level)
		var group := TacticalGrid3D.build_level_group(
			_voxel_map, level, color_func, use_individual)
		_grid_meshes.add_child(group)

		# Index focus-level individual walls for occlusion fade
		if use_individual:
			var walls_node := group.get_node_or_null("Walls")
			if walls_node != null:
				for child in walls_node.get_children():
					if child is MeshInstance3D and child.has_meta("cell_pos"):
						_wall_meshes[child.get_meta("cell_pos")] = child

	# Apply level visibility (hard-clip)
	_apply_level_visibility()

	# Rebuild highlights
	_rebuild_highlights()

	# Re-evaluate wall occlusion: rebuild cleared _faded_walls and recreated
	# all wall meshes at full opacity. Without this, walls between camera and
	# party stop fading after any fog update (the symptom reported in 7b D.1).
	_update_wall_occlusion()


func _rebuild_fog() -> void:
	# Voxel fog is built per-level inside each level group by _rebuild_grid_voxel().
	pass


func _rebuild_highlights() -> void:
	if _highlight_layer == null:
		return
	for child in _highlight_layer.get_children():
		child.queue_free()

	for layer in _highlight_layers:
		var color: Color = layer.get("color", Color(1.0, 1.0, 0.0, 0.25))
		var cells_3d: Array[Vector3i] = []
		for pos in layer.get("cells", []):
			if pos is Vector3i:
				cells_3d.append(pos)
			elif pos is Vector2i:
				var fl := _visibility_manager.focus_level if _visibility_manager != null else 0
				cells_3d.append(Vector3i(pos.x, pos.y, fl))
		var mmi := TacticalGrid3D.build_highlight_overlay_voxel(cells_3d, color, _voxel_map)
		_highlight_layer.add_child(mmi)


# ---------------------------------------------------------------------------
# Entity tokens
# ---------------------------------------------------------------------------

## Add a token (3D character model if registered, else cylinder) for the entity.
func add_entity_token(
		entity_id: String,
		entity_display_name: String,
		side: int,
		class_letter: String,
		class_id: String = "",
		token_variant: String = "",
		sex: String = "male") -> Node3D:
	if _tokens.has(entity_id):
		return _tokens[entity_id]
	if _entity_layer == null:
		push_error("DungeonMapRenderer3D.add_entity_token: EntityLayer is null")
		return null
	var token := _instantiate_token(
		entity_id, entity_display_name, side, class_letter,
		class_id, token_variant, sex)
	_entity_layer.add_child(token)
	_tokens[entity_id] = token
	return token


func _instantiate_token(entity_id: String, entity_display_name: String, side: int,
		class_letter: String, class_id: String, token_variant: String,
		sex: String) -> Node3D:
	if not class_id.is_empty() and CharacterModelRegistryScript.has_any_model(class_id, sex):
		if _character_token_scene == null:
			_character_token_scene = load("res://scenes/ui/components/character_token_3d.tscn")
		var char_token: Node3D = _character_token_scene.instantiate()
		char_token.setup(entity_id, entity_display_name, side, class_letter,
			class_id, token_variant, sex)
		return char_token
	if _token_scene == null:
		_token_scene = load("res://scenes/ui/components/combatant_token_3d.tscn")
	var token: Node3D = _token_scene.instantiate()
	token.setup(entity_id, entity_display_name, side, class_letter)
	var atlas: Texture2D = _lookup_atlas_for_class(class_id, token_variant)
	if atlas != null:
		token.set_sprite_atlas(atlas)
	return token


## Forwarders for CharacterToken3D procedural animations. No-op when the
## underlying token is the cylinder (which lacks these methods).
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


func get_entity_token(entity_id: String) -> Node3D:
	return _tokens.get(entity_id, null)


## Sync all token positions to the current entity_positions in the map.
func _update_entity_tokens() -> void:
	if _entity_layer == null:
		return
	_update_entity_tokens_voxel()


## Voxel path: sync token positions using VoxelMapData entity positions.
func _update_entity_tokens_voxel() -> void:
	if _voxel_map == null:
		return

	var to_remove: Array = []
	for eid in _tokens.keys():
		if not _voxel_map.entity_positions.has(eid):
			to_remove.append(eid)
	for eid in to_remove:
		remove_entity_token(eid)

	for eid in _voxel_map.entity_positions.keys():
		var pos: Vector3i = _voxel_map.entity_positions[eid]
		var world_pos := VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
		world_pos.y += 0.2  # Token offset above floor per GDD §12.3
		if _tokens.has(eid):
			_tokens[eid].update_position(world_pos)

	# Re-apply per-level token visibility/opacity per GDD §16.2 in case the
	# active focus level has since shifted off this token's level.
	_apply_token_visibility()
	# Re-evaluate wall occlusion: party positions may have moved, and
	# _rebuild_grid_voxel clears _faded_walls, so occlusion needs to re-fade
	# the walls between camera and party.
	_update_wall_occlusion()


# ---------------------------------------------------------------------------
# Combat-mode highlight API
# ---------------------------------------------------------------------------

func set_combat_mode(enabled: bool) -> void:
	_combat_mode = enabled


func highlight_cells(cells, color: Color) -> void:
	_highlight_layers.append({"cells": cells, "color": color})
	_rebuild_highlights()


func highlight_entity_tokens(entity_ids: Array[String]) -> void:
	_target_rings = entity_ids.duplicate()
	for eid in entity_ids:
		if _tokens.has(eid):
			_tokens[eid].is_selected = true


func clear_highlights() -> void:
	_highlight_layers.clear()
	_target_rings.clear()
	for eid in _tokens.keys():
		_tokens[eid].is_selected = false
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
	# Clear any pending animation — this is an instant move (combat).
	_active_movements.erase(entity_id)
	_move_queues.erase(entity_id)
	_tweening.erase(entity_id)
	_kill_entity_tween(entity_id)

	var pos: Vector3i = to_cell if to_cell is Vector3i else Vector3i(to_cell.x, to_cell.y, _controller.get_current_level())
	var world_pos := VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
	world_pos.y += 0.2
	_tokens[entity_id].update_position(world_pos)


func set_token_facing(entity_id: String, facing: Vector2i) -> void:
	if _tokens.has(entity_id):
		_tokens[entity_id].set_facing(facing)


# ---------------------------------------------------------------------------
# Exploration selection
# ---------------------------------------------------------------------------

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


func deselect_entity(entity_id: String) -> void:
	_selected_entity_ids.erase(entity_id)
	if _tokens.has(entity_id):
		_tokens[entity_id].is_selected = false
	entity_deselected.emit(entity_id)


func clear_selection() -> void:
	for eid in _selected_entity_ids:
		if _tokens.has(eid):
			_tokens[eid].is_selected = false
	_selected_entity_ids.clear()


func select_all_on_side(side: int) -> void:
	clear_selection()
	for eid in _tokens.keys():
		var token: Node3D = _tokens[eid]
		if token.side == side:
			_selected_entity_ids.append(eid)
			token.is_selected = true


func get_selected_entity_ids() -> Array[String]:
	return _selected_entity_ids.duplicate()


func update_order_overlay(orders: Dictionary) -> void:
	if _order_overlay != null and _order_overlay.has_method("update_overlays"):
		_order_overlay.update_overlays(orders)


func clear_order_overlay() -> void:
	if _order_overlay != null and _order_overlay.has_method("clear_overlays"):
		_order_overlay.clear_overlays()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
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
					_apply_zoom(_camera.size - ZOOM_STEP, event.position)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_DOWN:
					_apply_zoom(_camera.size + ZOOM_STEP, event.position)
					get_viewport().set_input_as_handled()
		else:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_handle_left_release(event)
				MOUSE_BUTTON_MIDDLE:
					_middle_dragging = false

	elif event is InputEventMouseMotion:
		if _middle_dragging:
			# Pan camera by converting screen-space delta to world-space delta
			if _camera != null:
				var world_delta := _screen_delta_to_world(event.relative)
				_camera.position -= world_delta
				get_viewport().set_input_as_handled()
		elif _drag_selecting:
			_drag_select_end = event.position
			get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_EQUAL, KEY_KP_ADD:
					_apply_zoom(_camera.size - ZOOM_STEP)
					get_viewport().set_input_as_handled()
				KEY_MINUS, KEY_KP_SUBTRACT:
					_apply_zoom(_camera.size + ZOOM_STEP)
					get_viewport().set_input_as_handled()
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
					var group_num: int = event.keycode - KEY_0
					control_group_assign_requested.emit(group_num, _selected_entity_ids.duplicate())
					get_viewport().set_input_as_handled()
		elif not event.ctrl_pressed and not event.alt_pressed:
			if event.is_action_pressed("focus_next_party_member"):
				if _visibility_manager != null:
					_visibility_manager.cycle_next_party_member()
				_center_camera_on_selected()
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("recenter_party_leader"):
				if _visibility_manager != null:
					_visibility_manager.jump_to_party_leader()
				_camera.size = 12.0
				_center_camera_on_selected()
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("focus_level_up"):
				if _visibility_manager != null:
					_visibility_manager.set_focus_level(_visibility_manager.focus_level + 2)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("focus_level_down"):
				if _visibility_manager != null:
					_visibility_manager.set_focus_level(_visibility_manager.focus_level - 2)
				get_viewport().set_input_as_handled()
				return
			match event.keycode:
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
					var group_num: int = event.keycode - KEY_0
					var now := Time.get_ticks_msec() / 1000.0
					if _last_number_key == group_num and (now - _last_number_key_time) < DOUBLE_TAP_THRESHOLD:
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
				KEY_F3:
					# Dev aid: print party leader position + stair cells so the
					# user can navigate without an in-world coordinate overlay.
					if _controller != null:
						var leader_pos := _controller.get_party_position_3d()
						var vm := _controller.get_voxel_map()
						var summary := PackedStringArray()
						summary.append("Leader: %s" % str(leader_pos))
						if vm != null:
							summary.append("Focus level: %d" % (_visibility_manager.focus_level if _visibility_manager != null else 0))
							for cell: VoxelCell in vm.get_all_cells():
								if cell.feature.begins_with("stairs_"):
									var target := _controller.get_stair_target(Vector3i(cell.col, cell.row, cell.level))
									summary.append("  %s at (%d,%d,%d) → %s" % [
										cell.feature, cell.col, cell.row, cell.level, str(target)
									])
						print("[F3] ", " | ".join(summary))
						EventBus.notification_requested.emit({
							"type": "info", "category": "environment",
							"title": "Leader: %s (see console for stair list)" % str(leader_pos),
							"duration": 6.0,
						})
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					if not _selected_entity_ids.is_empty():
						clear_selection()
						selection_cleared.emit()
						get_viewport().set_input_as_handled()


func _handle_left_press(event: InputEventMouseButton) -> void:
	# Double-click: select all of same type
	if event.double_click and not _combat_mode:
		var hit_eid := _entity_id_near_screen_pos(event.position)
		if not hit_eid.is_empty():
			control_group_select_requested.emit(hit_eid)
			get_viewport().set_input_as_handled()
			return

	# Combat mode: immediate click — entity or cell
	if _combat_mode:
		var hit_eid := _entity_id_near_screen_pos(event.position)
		if not hit_eid.is_empty():
			entity_clicked.emit(hit_eid)
			get_viewport().set_input_as_handled()
			return
		# No entity hit — emit cell_clicked for movement targets
		var fl := _visibility_manager.focus_level if _visibility_manager != null else 0
		var cell_pos_3d := TacticalGrid3D.screen_to_cell_voxel(_camera, event.position, fl)
		if _voxel_map != null and _voxel_map.has_cell(cell_pos_3d):
			cell_clicked.emit(cell_pos_3d)
			get_viewport().set_input_as_handled()
		return

	# Begin drag-select tracking
	_drag_selecting = true
	_drag_select_start = event.position
	_drag_select_end = event.position
	get_viewport().set_input_as_handled()


func _handle_left_release(event: InputEventMouseButton) -> void:
	if not _drag_selecting:
		return
	_drag_selecting = false
	if _drag_rect != null:
		_drag_rect.visible = false

	var drag_dist := _drag_select_start.distance_to(event.position)
	if drag_dist > DRAG_SELECT_THRESHOLD:
		_perform_drag_select(event)
	else:
		_perform_click_select(event)


func _perform_drag_select(event: InputEventMouseButton) -> void:
	var additive := Input.is_key_pressed(KEY_SHIFT)
	if not additive:
		clear_selection()

	var rect := Rect2(
		Vector2(minf(_drag_select_start.x, event.position.x),
				minf(_drag_select_start.y, event.position.y)),
		Vector2(absf(event.position.x - _drag_select_start.x),
				absf(event.position.y - _drag_select_start.y))
	)

	# Test each token's screen-space position against the rectangle
	var any_selected := false
	for eid in _tokens.keys():
		var token: Node3D = _tokens[eid]
		var screen_pos := _camera.unproject_position(token.global_position)
		if rect.has_point(screen_pos):
			select_entity(eid, true)
			any_selected = true

	if not any_selected and not additive:
		selection_cleared.emit()


func _perform_click_select(event: InputEventMouseButton) -> void:
	var hit_eid := _entity_id_near_screen_pos(event.position)
	if not hit_eid.is_empty():
		var additive := Input.is_key_pressed(KEY_SHIFT)
		select_entity(hit_eid, additive)
		return

	# Clicked empty space — clear selection
	if not _selected_entity_ids.is_empty():
		clear_selection()
		selection_cleared.emit()

	var fl := _visibility_manager.focus_level if _visibility_manager != null else 0
	var cell_pos_3d := TacticalGrid3D.screen_to_cell_voxel(_camera, event.position, fl)
	if _voxel_map != null and _voxel_map.has_cell(cell_pos_3d):
		cell_clicked.emit(cell_pos_3d)


func _handle_right_click(event: InputEventMouseButton) -> void:
	if _camera == null or _voxel_map == null:
		return
	var fl := _visibility_manager.focus_level if _visibility_manager != null else 0
	var cell_pos := TacticalGrid3D.screen_to_cell_voxel(_camera, event.position, fl)
	context_menu_requested.emit(cell_pos, event.position)
	cell_right_clicked.emit(cell_pos, event.position)
	get_viewport().set_input_as_handled()


## Returns the entity_id of the token nearest to screen_pos within HIT_RADIUS_SCREEN.
func _entity_id_near_screen_pos(screen_pos: Vector2) -> String:
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


# ---------------------------------------------------------------------------
# Camera helpers
# ---------------------------------------------------------------------------

func _center_camera_on_party() -> void:
	if _camera == null or _controller == null:
		return
	var pos := _controller.get_party_position_3d()
	var world_pos := VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
	_look_at_world_point(world_pos)


func _center_camera_on_selected() -> void:
	if _camera == null:
		return
	if not _selected_entity_ids.is_empty() and _voxel_map != null:
		var pos := _voxel_map.get_entity_pos(_selected_entity_ids[0])
		if pos != Vector3i(-1, -1, -1):
			var world_pos := VoxelGrid.cell_to_world(pos.x, pos.y, pos.z)
			_look_at_world_point(world_pos)
			return
	_center_camera_on_party()


## Position the camera so it looks at [param target] from the isometric angle.
## For orthographic cameras the view direction doesn't change framing, but
## the camera must be positioned so the target is between near and far planes.
func _look_at_world_point(target: Vector3) -> void:
	if _camera == null:
		return
	# Compute the camera's backward direction from known isometric angles
	# rather than reading basis (which may not be updated yet in the same frame).
	# For rotation (-35.264°, -45°, 0°), the local +Z axis in world space is:
	#   x = sin(45°) * cos(35.264°) ≈ 0.5774
	#   y = sin(35.264°)            ≈ 0.5774
	#   z = cos(45°) * cos(35.264°) ≈ 0.5774
	var offset_dist := 50.0
	_camera.position = target + CAM_BACKWARD * offset_dist


func _apply_zoom(new_size: float, _center_on_screen: Vector2 = Vector2(-1, -1)) -> void:
	if _camera == null:
		return
	var old_size := _camera.size
	_camera.size = clampf(new_size, ZOOM_MIN, ZOOM_MAX)
	if _camera.size == old_size:
		return
	# TODO: implement zoom-toward-cursor (project cursor world point,
	# adjust camera position to keep it under cursor after zoom change)


## Convert a screen-space delta (pixels) to a world-space displacement on the XZ plane.
## Used for middle-mouse drag panning.
func _screen_delta_to_world(screen_delta: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	# For orthographic camera, 1 pixel = (size / viewport_height) world units
	# But we need to account for the camera's rotation.
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.y < 1.0:
		return Vector3.ZERO
	var world_per_pixel := _camera.size / vp_size.y

	return (CAM_RIGHT * screen_delta.x + CAM_UP * screen_delta.y) * world_per_pixel


# ---------------------------------------------------------------------------
# Voxel level visibility and camera Y control
# ---------------------------------------------------------------------------

## Called when VisibilityManager.focus_level_changed fires.
func _on_focus_level_changed(new_level: int) -> void:
	if _camera == null:
		return
	# Center of the new focus level, plus the standing camera offset
	# (CAM_BACKWARD * 50.0 is the viewing distance baked into the initial rig).
	var base_y: float = float(new_level) * VoxelGrid.CELL_SIZE + (VoxelGrid.CELL_SIZE * 0.5)
	var target_y: float = base_y + CAM_BACKWARD.y * 50.0
	var tween := create_tween()
	tween.tween_property(_camera, "position:y", target_y, 0.25) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Rebuild grid to change which level gets individual walls
	_rebuild_grid_voxel()


## Apply per-level visibility and albedo tint per GDD §16.2 and §16.7:
##   level >  focus + 1 → hidden (hard-clip)
##   level == focus + 1 → walls dithered; floors/doors/features hidden (split)
##   level == focus     → visible, full color
##   level <  focus     → visible, dimmed to 0.6× (if level has content; else hidden)
## Tokens receive matching treatment via [method _apply_token_visibility].
func _apply_level_visibility() -> void:
	if _visibility_manager == null or _grid_meshes == null:
		return
	var focus: int = _visibility_manager.focus_level
	for child in _grid_meshes.get_children():
		if not (child is Node3D) or not child.name.begins_with("Level_"):
			continue
		var level_str: String = child.name.trim_prefix("Level_")
		if not level_str.is_valid_int():
			continue
		var level: int = int(level_str)
		if level == focus + 1:
			child.visible = true
			_apply_focus_plus_one_visibility(child)
		elif level > focus + 1:
			child.visible = false
		elif level == focus:
			child.visible = true
			TacticalGrid3D.set_level_group_tint(child, FULL_COLOR)
			_reset_walls_opaque(child)
		else:  # level < focus
			if _visibility_manager.level_has_content(level):
				child.visible = true
				TacticalGrid3D.set_level_group_tint(child, DIM_COLOR)
				_reset_walls_opaque(child)
			else:
				child.visible = false
	_apply_token_visibility()


## For the focus+1 level: show walls with a screen-door dither, hide everything
## else (floors, doors, features, grid lines, fog, transition markers). Matches
## GDD §16.7 — walls you're about to walk into are visible while the top-down
## silhouette stays readable.
func _apply_focus_plus_one_visibility(level_group: Node3D) -> void:
	for sub in level_group.get_children():
		if sub.name == "Walls":
			sub.visible = true
			_set_walls_dithered(sub, true)
		else:
			sub.visible = false


## Reset the walls in this level group to full-opacity rendering. Called when
## the level is at or below the focus level so walls render normally after
## having been dithered while this level was focus+1.
func _reset_walls_opaque(level_group: Node3D) -> void:
	var walls := level_group.get_node_or_null("Walls")
	if walls == null:
		return
	_set_walls_dithered(walls, false)


## Walks every GeometryInstance3D under [param walls] and either enables the
## screen-door dither material state ([param dithered]=true) or restores the
## opaque state. Uses each mesh's stored "base_color" metadata as the source.
func _set_walls_dithered(walls: Node, dithered: bool) -> void:
	if walls is GeometryInstance3D:
		_apply_mesh_dither(walls, dithered)
	else:
		for mesh in walls.get_children():
			if mesh is GeometryInstance3D:
				_apply_mesh_dither(mesh, dithered)


func _apply_mesh_dither(mesh: GeometryInstance3D, dithered: bool) -> void:
	var mat := mesh.material_override
	if mat == null or not (mat is StandardMaterial3D):
		return
	var smat: StandardMaterial3D = mat
	var base: Color = mesh.get_meta("base_color", Color.WHITE)
	if dithered:
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		smat.albedo_color = Color(base.r, base.g, base.b, 0.35)
	else:
		smat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		smat.albedo_color = base


## Apply per-level visibility and opacity to entity tokens per GDD §16.2.
## Party tokens on non-focus explored levels stay fully opaque so the player
## never loses sight of them. Enemy tokens on non-focus explored levels render
## at NON_FOCUS_ENEMY_ALPHA. Tokens on hidden or above-focus levels are hidden.
func _apply_token_visibility() -> void:
	if _visibility_manager == null or _voxel_map == null:
		return
	var focus: int = _visibility_manager.focus_level
	for eid in _tokens.keys():
		var token: Node3D = _tokens[eid]
		if token == null:
			continue
		var pos: Vector3i = _voxel_map.entity_positions.get(eid, Vector3i(-1, -1, -1))
		if pos == Vector3i(-1, -1, -1):
			continue
		var level: int = pos.z
		if level > focus:
			token.visible = false
		elif level == focus:
			token.visible = true
			_set_token_alpha(token, 1.0)
		else:  # level < focus
			if not _visibility_manager.level_has_content(level):
				token.visible = false
				continue
			token.visible = true
			if token.side == 0:
				_set_token_alpha(token, 1.0)
			else:
				_set_token_alpha(token, NON_FOCUS_ENEMY_ALPHA)


## Set the alpha of a token's mesh material(s), toggling transparency mode
## as needed. CharacterToken3D handles its own GLB walk via set_render_alpha;
## CombatantToken3D (cylinder) has its body at "Body" and is faded directly.
func _set_token_alpha(token: Node3D, alpha: float) -> void:
	if token.has_method("set_render_alpha"):
		token.set_render_alpha(alpha)
		return
	var body: MeshInstance3D = token.get_node_or_null("Body")
	if body == null:
		return
	var mat := body.material_override
	if mat == null or not (mat is StandardMaterial3D):
		return
	var smat: StandardMaterial3D = mat
	var c: Color = smat.albedo_color
	smat.albedo_color = Color(c.r, c.g, c.b, alpha)
	if alpha < 1.0:
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		smat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


# ---------------------------------------------------------------------------
# Wall occlusion fading
# ---------------------------------------------------------------------------

## Fade walls that occlude the party from the camera's viewpoint.
##
## Strategy: project each party token onto the camera's lateral axes (right, up)
## to get a 2D "column" in screen-space. Any wall whose screen-column is within
## a generous radius of any party column AND is closer to the camera (higher
## depth along CAM_BACKWARD) gets faded to alpha 0.1.
##
## The lateral margin grows when zoomed in so nearby walls are caught.
func _update_wall_occlusion() -> void:
	if _wall_meshes.is_empty() or _tokens.is_empty():
		return

	# Gather party token world positions and their depth along the view axis
	var party_data: Array = []  # Array of {pos: Vector3, depth: float, lateral: Vector2}
	for eid in _tokens.keys():
		var token: Node3D = _tokens[eid]
		if token.side == 0:  # PARTY
			var wpos: Vector3 = token.global_position
			party_data.append({
				"pos": wpos,
				"depth": wpos.dot(CAM_BACKWARD),
				"lateral": Vector2(wpos.dot(CAM_RIGHT), wpos.dot(CAM_UP)),
			})

	if party_data.is_empty():
		_restore_all_faded_walls()
		return

	# CAM_BACKWARD points from scene toward camera (+Y, +Z). Higher dot product
	# = closer to the camera. A wall occludes a party member if:
	#   1. The wall is closer to the camera (higher depth) than that member
	#   2. The wall laterally overlaps that member's screen column
	# Check per-token so dispersed parties work correctly.
	var base_margin := 2.0  # world units (widened from 1.5 to catch walls further from party)
	var zoom_scale := 12.0 / maxf(_camera.size, 1.0)
	var lateral_margin: float = base_margin * maxf(zoom_scale, 1.0)

	var walls_to_fade: Dictionary = {}

	for wall_pos in _wall_meshes.keys():
		var wall_mesh: MeshInstance3D = _wall_meshes[wall_pos]
		var wall_world: Vector3 = wall_mesh.global_position
		var wall_depth: float = wall_world.dot(CAM_BACKWARD)
		var wall_lateral := Vector2(wall_world.dot(CAM_RIGHT), wall_world.dot(CAM_UP))

		for pd in party_data:
			# Wall must be closer to camera than THIS specific party member
			var token_depth: float = pd["depth"]
			if wall_depth <= token_depth:
				continue

			# And laterally overlap this member's screen column
			var party_lateral: Vector2 = pd["lateral"]
			if absf(wall_lateral.x - party_lateral.x) <= lateral_margin and \
			   absf(wall_lateral.y - party_lateral.y) <= lateral_margin:
				walls_to_fade[wall_pos] = true
				break

	# Restore walls no longer needing fade
	for faded_pos in _faded_walls.keys():
		if not walls_to_fade.has(faded_pos) and _wall_meshes.has(faded_pos):
			var mesh: MeshInstance3D = _wall_meshes[faded_pos]
			var mat: StandardMaterial3D = mesh.material_override
			if mat != null:
				var base_color: Color = mesh.get_meta("base_color", Color(0.5, 0.5, 0.5))
				mat.albedo_color = base_color
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	_faded_walls = walls_to_fade.duplicate()

	# Apply fade
	for fade_pos in walls_to_fade.keys():
		if not _wall_meshes.has(fade_pos):
			continue
		var mesh: MeshInstance3D = _wall_meshes[fade_pos]
		var mat: StandardMaterial3D = mesh.material_override
		if mat != null:
			var base_color: Color = mesh.get_meta("base_color", Color(0.5, 0.5, 0.5))
			mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.08)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _restore_all_faded_walls() -> void:
	for faded_pos in _faded_walls.keys():
		if _wall_meshes.has(faded_pos):
			var mesh: MeshInstance3D = _wall_meshes[faded_pos]
			var mat: StandardMaterial3D = mesh.material_override
			if mat != null:
				var base_color: Color = mesh.get_meta("base_color", Color(0.5, 0.5, 0.5))
				mat.albedo_color = base_color
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_faded_walls.clear()


# ---------------------------------------------------------------------------
# Session 8: HUD widgets + auto-focus + portrait click wiring
# ---------------------------------------------------------------------------

## Instances the Level Strip Widget and Off-Screen Party Indicators under the
## DungeonHUD CanvasLayer. No-op if the scenes aren't loadable (test harness).
func _setup_hud_widgets() -> void:
	var hud := get_node_or_null("DungeonHUD")
	if hud == null:
		return

	var strip_scene: PackedScene = load("res://scenes/ui/hud/level_strip_widget.tscn")
	if strip_scene != null:
		_level_strip_widget = strip_scene.instantiate()
		hud.add_child(_level_strip_widget)
		if _level_strip_widget.has_method("setup"):
			_level_strip_widget.setup(_visibility_manager, self, _voxel_map)

	var indicators_scene: PackedScene = load("res://scenes/ui/hud/offscreen_party_indicators.tscn")
	if indicators_scene != null:
		_offscreen_indicators = indicators_scene.instantiate()
		hud.add_child(_offscreen_indicators)
		if _offscreen_indicators.has_method("setup"):
			_offscreen_indicators.setup(_camera, _visibility_manager, self)


## EventBus.dungeon_auto_focus_requested handler — routes auto-focus events
## from scheduler handlers into VisibilityManager.
func _on_dungeon_auto_focus_requested(level: int, reason: String) -> void:
	if _visibility_manager != null:
		_visibility_manager.request_auto_focus(level, reason)


## EventBus.party_portrait_clicked handler — focuses the camera on the clicked
## party member's level and selects their token.
func _on_party_portrait_clicked(entity_id: String) -> void:
	if _voxel_map == null or _visibility_manager == null:
		return
	var pos: Vector3i = _voxel_map.get_entity_pos(entity_id)
	if pos == Vector3i(-1, -1, -1):
		return
	_visibility_manager.set_focus_level(pos.z)
	select_entity(entity_id, false)
	_center_camera_on_selected()


## Returns the VisibilityManager instance (or null before setup()). Public
## accessor for callers that need to query focus level / request auto-focus.
func get_visibility_manager() -> VisibilityManager:
	return _visibility_manager


## Returns a Dictionary {level: enemy_count} for use by the Level Strip Widget.
## An enemy is a token with side != 0 whose entity_id has a known voxel position.
func get_enemy_levels_snapshot() -> Dictionary:
	var counts: Dictionary = {}
	if _voxel_map == null:
		return counts
	for eid in _tokens.keys():
		var token = _tokens[eid]
		if token == null or token.side == 0:
			continue
		var pos: Vector3i = _voxel_map.get_entity_pos(eid)
		if pos == Vector3i(-1, -1, -1):
			continue
		counts[pos.z] = int(counts.get(pos.z, 0)) + 1
	return counts


## Re-reads every side==0 token's voxel position into
## VisibilityManager.party_positions. Called whenever map/entity state shifts
## so the Level Strip Widget and offscreen indicators have fresh data.
func _refresh_visibility_party_positions() -> void:
	if _visibility_manager == null or _voxel_map == null:
		return
	var positions: Array[Vector3i] = []
	var levels_snapshot: Dictionary = {}
	for eid in _tokens.keys():
		var token = _tokens[eid]
		if token == null or token.side != 0:
			continue
		var pos: Vector3i = _voxel_map.get_entity_pos(eid)
		if pos == Vector3i(-1, -1, -1):
			continue
		positions.append(pos)
		levels_snapshot[eid] = pos.z
	_visibility_manager.party_positions = positions
	EventBus.party_member_levels_snapshot.emit(levels_snapshot)
	if _level_strip_widget != null and _level_strip_widget.has_method("refresh"):
		_level_strip_widget.refresh()


## Lightweight refresh hook for `_on_entity_moved`. Only recomputes if the
## moved entity is party-side (side == 0).
func _refresh_visibility_party_positions_if_party(entity_id: String) -> void:
	if not _tokens.has(entity_id):
		return
	var token = _tokens[entity_id]
	if token == null or token.side != 0:
		return
	_refresh_visibility_party_positions()


## Returns an Array of {entity_id, world_pos} for party-side tokens (side == 0)
## on the currently focused level. Consumed by OffscreenPartyIndicators to draw
## viewport-edge arrows.
func get_party_focus_tokens() -> Array:
	var result: Array = []
	if _voxel_map == null or _visibility_manager == null:
		return result
	var focus: int = _visibility_manager.focus_level
	for eid in _tokens.keys():
		var token = _tokens[eid]
		if token == null or token.side != 0:
			continue
		var pos: Vector3i = _voxel_map.get_entity_pos(eid)
		if pos == Vector3i(-1, -1, -1):
			continue
		if pos.z != focus:
			continue
		result.append({
			"entity_id": eid,
			"world_pos": VoxelGrid.cell_to_world(pos.x, pos.y, pos.z),
		})
	return result
