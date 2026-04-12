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


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal cell_clicked(pos: Vector2i)
signal door_interact_requested(pos: Vector2i)
signal exit_requested()
signal entity_clicked(entity_id: String)
signal entity_selected(entity_id: String)
signal entity_deselected(entity_id: String)
signal end_turn_requested()


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
	# Find order overlay child if present in scene tree
	_order_overlay = get_node_or_null("OrderOverlayLayer")


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
	_center_camera_on_party()
	_update_exit_button()


func _on_fog_updated() -> void:
	_map = _controller.get_map()
	queue_redraw()


func _on_party_moved(_from: Vector2i, _to: Vector2i) -> void:
	_update_entity_tokens()
	_update_exit_button()
	queue_redraw()


func _on_door_state_changed(_pos: Vector2i, _old: String, _new: String) -> void:
	queue_redraw()


func _on_level_changed(_from_level: int, _to_level: int) -> void:
	_map = _controller.get_map()
	_refresh_all()
	_center_camera_on_party()
	_update_exit_button()


func _on_exit_button_pressed() -> void:
	exit_requested.emit()


## Enables or disables the exit button based on transition cell position.
func _update_exit_button() -> void:
	if _exit_button == null or _controller == null:
		return
	var on_exit: bool = _controller.is_on_transition_cell()
	_exit_button.disabled = not on_exit
	_exit_button.text = "Exit Dungeon" if on_exit else "Move to an exit to leave"


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
				if detected:
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
				if ds != "open":
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
	if not (event is InputEventMouseButton) or not event.pressed:
		return

	var local_pos := get_local_mouse_position()
	var cell_pos := IsometricGrid.screen_to_cell(local_pos)

	if event.button_index == MOUSE_BUTTON_LEFT:
		# In combat mode, check if click is near a token first.
		if _combat_mode:
			var hit_eid := _entity_id_near_screen_pos(local_pos)
			if not hit_eid.is_empty():
				entity_clicked.emit(hit_eid)
				get_viewport().set_input_as_handled()
				return
		else:
			# Exploration mode: check for entity selection
			var hit_eid := _entity_id_near_screen_pos(local_pos)
			if not hit_eid.is_empty():
				var additive := Input.is_key_pressed(KEY_SHIFT)
				select_entity(hit_eid, additive)
				get_viewport().set_input_as_handled()
				return
		if _map != null and _map.has_cell(cell_pos):
			cell_clicked.emit(cell_pos)
			get_viewport().set_input_as_handled()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if _map != null and _map.is_door(cell_pos):
			door_interact_requested.emit(cell_pos)
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
