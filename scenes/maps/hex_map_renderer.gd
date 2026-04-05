extends Node2D

## Renders a HexMapData onto TileMapLayer nodes.
##
## Scene tree expected:
##   HexMap (Node2D, this script)
##   ├── TerrainLayer (TileMapLayer)
##   ├── FogLayer (TileMapLayer)
##   ├── EntityLayer (Node2D)
##   │   └── PartyToken (Polygon2D)
##   ├── Camera2D
##   └── HexHUD (CanvasLayer, layer=10)
##       └── TooltipPanel (PanelContainer)
##           └── TooltipLabel (Label)
##
## Call setup(controller) after adding to the scene tree.
## The renderer connects to controller signals and reacts to state changes.
##
## Coordinate note: game logic uses axial (q,r); TileMapLayer uses Godot map
## coords. Use HexMapController.axial_to_godot_map() for all conversions.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Flat-top hex with circumradius R = 32:
#   Width  (tip-to-tip)  = 2R = 64
#   Height (flat-to-flat) = R*sqrt(3) ≈ 55.4 → 56
const TERRAIN_TILE_SIZE := Vector2i(64, 56)
const TERRAIN_ATLAS_COLS := 17

# Atlas column index for each biome at flat elevation (add 5 for hills, 10 for mountains)
const BIOME_COL := {
	"clear": 0, "woods": 1, "jungle": 2, "swamp": 3, "desert": 4
}
const OCEAN_COL := 15

# Fog tile atlas: 2 columns × 1 row
const FOG_TILE_SIZE := Vector2i(64, 56)
const FOG_SOURCE_ID := 0
const FOG_HIDDEN_ATLAS := Vector2i(0, 0)
const FOG_EXPLORED_ATLAS := Vector2i(1, 0)

# Camera panning
const PAN_SPEED := 200.0
const EDGE_MARGIN := 40.0


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _terrain_layer: TileMapLayer = $TerrainLayer
@onready var _fog_layer: TileMapLayer = $FogLayer
@onready var _entity_layer: Node2D = $EntityLayer
@onready var _party_token: Polygon2D = $EntityLayer/PartyToken
@onready var _camera: Camera2D = $Camera2D
@onready var _tooltip_panel: PanelContainer = $HexHUD/TooltipPanel
@onready var _tooltip_label: Label = $HexHUD/TooltipPanel/TooltipLabel


# ---------------------------------------------------------------------------
# Vars
# ---------------------------------------------------------------------------

var _controller: HexMapController
var _map_data: HexMapData

## Tracks Label nodes placed for dungeon entrance markers (cleaned up on reload).
var _dungeon_markers: Array = []

## "Enter Dungeon" button shown when party is on a dungeon entrance hex.
var _enter_dungeon_btn: Button
## Active transition cell selection dialog (CanvasLayer), or null.
var _tc_dialog: CanvasLayer


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal hex_clicked(coord: Vector2i)
signal dungeon_entry_requested(entrance: Dictionary, spawn_cell: Vector2i)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_terrain_layer.tile_set = _create_terrain_tileset()
	_fog_layer.tile_set = _create_fog_tileset()

	# Party token: small flat-top hexagon (start angle 0 = vertex at right).
	var r := 14.0
	var points: PackedVector2Array = []
	for i in range(6):
		var angle_rad := deg_to_rad(60.0 * i)
		points.append(Vector2(r * cos(angle_rad), r * sin(angle_rad)))
	_party_token.polygon = points
	_party_token.color = Color(1.0, 0.9, 0.1)  # yellow

	# "Enter Dungeon" button — child of HexHUD (CanvasLayer) so it stays on screen.
	_enter_dungeon_btn = Button.new()
	_enter_dungeon_btn.text = "Enter Dungeon"
	_enter_dungeon_btn.visible = false
	_enter_dungeon_btn.pressed.connect(_on_enter_dungeon_pressed)
	$HexHUD.add_child(_enter_dungeon_btn)


func _process(delta: float) -> void:
	if _camera == null or _map_data == null:
		return

	var pan_dir := Vector2.ZERO

	# Arrow key panning
	if Input.is_action_pressed("ui_left"):
		pan_dir.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		pan_dir.x += 1.0
	if Input.is_action_pressed("ui_up"):
		pan_dir.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		pan_dir.y += 1.0

	# Mouse-to-edge panning (only when window has focus)
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

	# Keep Enter Dungeon button at 10% from top-right edges.
	if _enter_dungeon_btn != null and _enter_dungeon_btn.visible:
		var btn_size := _enter_dungeon_btn.size
		_enter_dungeon_btn.position = Vector2(
			vp_size.x * 0.9 - btn_size.x,
			vp_size.y * 0.1
		)


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Wire this renderer to a HexMapController. Call once after entering the tree.
func setup(controller: HexMapController) -> void:
	_controller = controller
	controller.map_loaded.connect(_on_map_loaded)
	controller.visibility_updated.connect(_on_visibility_updated)
	controller.party_moved.connect(_on_party_moved)
	controller.hex_terrain_updated.connect(_repaint_tile)


## Center the camera on the given axial coord.
func center_on_hex(coord: Vector2i) -> void:
	if _camera == null or _terrain_layer == null:
		return
	var godot_coord := HexMapController.axial_to_godot_map(coord)
	_camera.position = _terrain_layer.map_to_local(godot_coord)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_map_loaded(_map_id: String) -> void:
	_map_data = _controller.get_map()
	_refresh_terrain_layer()
	_refresh_fog_layer()
	_update_party_token_position()
	_compute_camera_limits()
	center_on_hex(_map_data.party_hex)
	_refresh_dungeon_markers()
	_update_enter_dungeon_button()


func _on_visibility_updated() -> void:
	_map_data = _controller.get_map()
	_refresh_fog_layer()


func _on_party_moved(_from_hex: Vector2i, _to_hex: Vector2i) -> void:
	_update_party_token_position()
	_update_enter_dungeon_button()


# ---------------------------------------------------------------------------
# Enter Dungeon button + modal
# ---------------------------------------------------------------------------

## Shows or hides the "Enter <name>" button depending on party hex.
func _update_enter_dungeon_button() -> void:
	if _enter_dungeon_btn == null or _map_data == null:
		return
	var party_hex := _map_data.party_hex
	var entrances := CampaignRepository.get_dungeon_entrances_for_map(_map_data.id)
	for entrance in entrances:
		if entrance.get("hex_q", 999) == party_hex.x and \
		   entrance.get("hex_r", 999) == party_hex.y:
			var dname: String = entrance.get("name", "Dungeon")
			_enter_dungeon_btn.text = "Enter %s" % dname
			_enter_dungeon_btn.visible = true
			_enter_dungeon_btn.set_meta("entrance_data", entrance)
			return
	_enter_dungeon_btn.visible = false


func _on_enter_dungeon_pressed() -> void:
	var entrance: Dictionary = _enter_dungeon_btn.get_meta("entrance_data")
	var dungeon_json: String = entrance.get("dungeon_data", "")
	var dungeon_dict = JSON.parse_string(dungeon_json)
	if dungeon_dict == null:
		return

	var levels: Array = dungeon_dict.get("levels", [])
	if levels.is_empty():
		return
	var level1: Dictionary = levels[0]
	var tc_array: Array = level1.get("transition_cells", [])

	if tc_array.is_empty():
		# No transition cells — fall back to single entry
		var entry := Vector2i(level1.get("entry_col", 0), level1.get("entry_row", 0))
		dungeon_entry_requested.emit(entrance, entry)
		return

	_show_transition_cell_dialog(entrance, tc_array)


## Builds and shows a modal dialog listing transition cells to choose from.
func _show_transition_cell_dialog(entrance: Dictionary, tc_array: Array) -> void:
	# Clean up any existing dialog
	if _tc_dialog != null and is_instance_valid(_tc_dialog):
		_tc_dialog.queue_free()

	_tc_dialog = CanvasLayer.new()
	_tc_dialog.layer = 20  # above HexHUD (10), below DicePrompt (64)

	# Full-screen dimmer
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.0, 0.0, 0.0, 0.5)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tc_dialog.add_child(dimmer)

	# Centered panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(300, 0)
	_tc_dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Title
	var dname: String = entrance.get("name", "Dungeon")
	var title_label := Label.new()
	title_label.text = "Enter %s" % dname
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var subtitle := Label.new()
	subtitle.text = "Select an entry point:"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# One button per transition cell
	for tc in tc_array:
		var col: int = tc.get("col", 0)
		var row: int = tc.get("row", 0)
		var label: String = tc.get("label", "")
		var display: String
		if not label.is_empty():
			display = "%s (%d, %d)" % [label, col, row]
		else:
			display = "Cell (%d, %d)" % [col, row]

		var btn := Button.new()
		btn.text = display
		var cell_pos := Vector2i(col, row)
		btn.pressed.connect(_on_tc_selected.bind(entrance, cell_pos))
		vbox.add_child(btn)

	# "Do not enter" cancel button
	var cancel_btn := Button.new()
	cancel_btn.text = "Do not enter"
	cancel_btn.pressed.connect(_close_tc_dialog)
	vbox.add_child(cancel_btn)

	add_child(_tc_dialog)


func _on_tc_selected(entrance: Dictionary, cell_pos: Vector2i) -> void:
	_close_tc_dialog()
	dungeon_entry_requested.emit(entrance, cell_pos)


func _close_tc_dialog() -> void:
	if _tc_dialog != null and is_instance_valid(_tc_dialog):
		_tc_dialog.queue_free()
		_tc_dialog = null


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

func _refresh_terrain_layer() -> void:
	_terrain_layer.clear()
	for coord in _map_data.hexes.keys():
		var terrain: HexTerrainData = _map_data.get_hex(coord)
		if terrain == null:
			continue
		var godot_coord := HexMapController.axial_to_godot_map(coord)
		var atlas_col := _terrain_atlas_col(terrain)
		_terrain_layer.set_cell(godot_coord, 0, Vector2i(atlas_col, 0))


func _terrain_atlas_col(terrain: HexTerrainData) -> int:
	if terrain.water == HexTerrainData.WATER_OCEAN or terrain.biome == "ocean":
		return OCEAN_COL
	var elevation_offset: int
	match terrain.elevation:
		HexTerrainData.ELEVATION_FLAT:      elevation_offset = 0
		HexTerrainData.ELEVATION_HILLS:     elevation_offset = 5
		HexTerrainData.ELEVATION_MOUNTAINS: elevation_offset = 10
		_: elevation_offset = 0
	var biome_offset: int = BIOME_COL.get(terrain.biome, 0)
	return elevation_offset + biome_offset


func _refresh_fog_layer() -> void:
	_fog_layer.clear()
	for coord in _map_data.hexes.keys():
		var godot_coord := HexMapController.axial_to_godot_map(coord)
		match _map_data.get_fog_state(coord):
			HexMapData.FogState.HIDDEN:
				_fog_layer.set_cell(godot_coord, FOG_SOURCE_ID, FOG_HIDDEN_ATLAS)
			HexMapData.FogState.EXPLORED:
				_fog_layer.set_cell(godot_coord, FOG_SOURCE_ID, FOG_EXPLORED_ATLAS)
			HexMapData.FogState.VISIBLE:
				pass  # no fog tile — hex is fully visible


func _update_party_token_position() -> void:
	if _map_data == null:
		return
	var godot_coord := HexMapController.axial_to_godot_map(_map_data.party_hex)
	_party_token.position = _terrain_layer.map_to_local(godot_coord)


## Places a "D" label marker on each revealed hex that has a dungeon entrance.
## Clears old markers first. Called after map load and fog update.
func _refresh_dungeon_markers() -> void:
	for m in _dungeon_markers:
		if is_instance_valid(m):
			m.queue_free()
	_dungeon_markers.clear()

	if _map_data == null or _terrain_layer == null:
		return

	var entrances := CampaignRepository.get_dungeon_entrances_for_map(_map_data.id)
	for entrance in entrances:
		var q: int = entrance.get("hex_q", 0)
		var r: int = entrance.get("hex_r", 0)
		var coord := Vector2i(q, r)

		var fog_state := _map_data.get_fog_state(coord)
		if fog_state == HexMapData.FogState.HIDDEN:
			continue

		var godot_coord := HexMapController.axial_to_godot_map(coord)
		var screen_pos := _terrain_layer.map_to_local(godot_coord)

		var lbl := Label.new()
		lbl.text = "D"
		lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		lbl.position = screen_pos - Vector2(8.0, 12.0)
		add_child(lbl)
		_dungeon_markers.append(lbl)


## Repaints a single terrain tile after an in-memory terrain update.
func _repaint_tile(coord: Vector2i) -> void:
	if _map_data == null:
		return
	var terrain: HexTerrainData = _map_data.get_hex(coord)
	if terrain == null:
		return
	var godot_coord := HexMapController.axial_to_godot_map(coord)
	var atlas_col := _terrain_atlas_col(terrain)
	_terrain_layer.set_cell(godot_coord, 0, Vector2i(atlas_col, 0))


## Computes Camera2D limits from the map's pixel bounding box plus 1-tile padding.
func _compute_camera_limits() -> void:
	if _camera == null or _map_data == null:
		return
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for coord in _map_data.hexes.keys():
		var godot_coord := HexMapController.axial_to_godot_map(coord)
		var pixel_pos := _terrain_layer.map_to_local(godot_coord)
		min_pos.x = minf(min_pos.x, pixel_pos.x)
		min_pos.y = minf(min_pos.y, pixel_pos.y)
		max_pos.x = maxf(max_pos.x, pixel_pos.x)
		max_pos.y = maxf(max_pos.y, pixel_pos.y)
	var pad_x := float(TERRAIN_TILE_SIZE.x)
	var pad_y := float(TERRAIN_TILE_SIZE.y)
	_camera.limit_left   = int(min_pos.x - pad_x)
	_camera.limit_right  = int(max_pos.x + pad_x)
	_camera.limit_top    = int(min_pos.y - pad_y)
	_camera.limit_bottom = int(max_pos.y + pad_y)


# ---------------------------------------------------------------------------
# Tooltip
# ---------------------------------------------------------------------------

## Show terrain info near the cursor for EXPLORED/VISIBLE hexes; hide for HIDDEN.
func _update_tooltip(viewport_pos: Vector2) -> void:
	if _map_data == null or _tooltip_panel == null:
		return
	var local_pos := _terrain_layer.get_local_mouse_position()
	var godot_coord := _terrain_layer.local_to_map(local_pos)
	var axial_coord := HexMapController.godot_map_to_axial(godot_coord)
	if not _map_data.is_valid_coord(axial_coord):
		_tooltip_panel.visible = false
		return
	var fog := _map_data.get_fog_state(axial_coord)
	if fog == HexMapData.FogState.HIDDEN:
		_tooltip_panel.visible = false
		return
	var terrain: HexTerrainData = _map_data.get_hex(axial_coord)
	if terrain == null:
		_tooltip_panel.visible = false
		return
	_tooltip_label.text = _terrain_tooltip_text(axial_coord, terrain)
	_tooltip_panel.visible = true
	# Position near cursor; clamp so panel stays on screen
	var vp_size := get_viewport().get_visible_rect().size
	var offset := Vector2(16.0, 16.0)
	# Wait one frame for size to be valid after first show
	var panel_size := _tooltip_panel.size if _tooltip_panel.size != Vector2.ZERO else Vector2(160.0, 130.0)
	var tip_pos := viewport_pos + offset
	tip_pos.x = minf(tip_pos.x, vp_size.x - panel_size.x - 4.0)
	tip_pos.y = minf(tip_pos.y, vp_size.y - panel_size.y - 4.0)
	_tooltip_panel.position = tip_pos


func _terrain_tooltip_text(coord: Vector2i, terrain: HexTerrainData) -> String:
	var water_str := terrain.water if not terrain.water.is_empty() else "none"
	return (
		"Hex (%d, %d)\nElevation: %s\nBiome: %s\nWater: %s\nTerritory: %s\nCity: %s\nFamilies: —\nOwners: —\nCleared: —"
		% [coord.x, coord.y, terrain.elevation, terrain.biome, water_str,
		   terrain.civilization, "yes" if terrain.has_city else "no"]
	)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos := _terrain_layer.get_local_mouse_position()
		var godot_coord := _terrain_layer.local_to_map(local_pos)
		var axial_coord := HexMapController.godot_map_to_axial(godot_coord)
		if _map_data != null and _map_data.is_valid_coord(axial_coord):
			hex_clicked.emit(axial_coord)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_tooltip(event.position)


# ---------------------------------------------------------------------------
# Tileset factories
# ---------------------------------------------------------------------------

func _create_terrain_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tileset.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tileset.tile_size = TERRAIN_TILE_SIZE

	var source := TileSetAtlasSource.new()
	var atlas_path := AssetRegistry.get_asset_path("terrain.atlas")
	if not atlas_path.is_empty() and ResourceLoader.exists(atlas_path):
		source.texture = load(atlas_path)
	else:
		source.texture = _build_terrain_atlas_texture()
	source.texture_region_size = TERRAIN_TILE_SIZE
	for col_idx in range(TERRAIN_ATLAS_COLS):
		source.create_tile(Vector2i(col_idx, 0))
	tileset.add_source(source)
	return tileset


func _build_terrain_atlas_texture() -> ImageTexture:
	# RGBA8 — pixels outside the hex boundary are transparent (alpha = 0)
	var img := Image.create(
		TERRAIN_TILE_SIZE.x * TERRAIN_ATLAS_COLS, TERRAIN_TILE_SIZE.y,
		false, Image.FORMAT_RGBA8
	)

	var colors: Array[Color] = [
		# flat: 0-4
		Color(0.706, 0.824, 0.431),  # clear
		Color(0.133, 0.353, 0.133),  # woods
		Color(0.039, 0.627, 0.235),  # jungle
		Color(0.275, 0.392, 0.235),  # swamp
		Color(0.863, 0.725, 0.392),  # desert
		# hills (×0.83): 5-9
		Color(0.586, 0.684, 0.358),
		Color(0.110, 0.293, 0.110),
		Color(0.032, 0.520, 0.195),
		Color(0.228, 0.326, 0.195),
		Color(0.716, 0.602, 0.326),
		# mountains (×0.67): 10-14
		Color(0.474, 0.553, 0.289),
		Color(0.089, 0.237, 0.089),
		Color(0.026, 0.420, 0.157),
		Color(0.184, 0.263, 0.157),
		Color(0.580, 0.488, 0.263),
		# special: 15-16
		Color(0.118, 0.314, 0.745),  # ocean
		Color(0.235, 0.471, 0.784),  # river marker (unused v1)
	]

	for col_idx in range(TERRAIN_ATLAS_COLS):
		var fill := colors[col_idx]
		_draw_hex_tile(img, col_idx, TERRAIN_TILE_SIZE, fill, fill.darkened(0.35))

	return ImageTexture.create_from_image(img)


func _create_fog_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tileset.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tileset.tile_size = FOG_TILE_SIZE

	var img := Image.create(FOG_TILE_SIZE.x * 2, FOG_TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	# Col 0: opaque black hex (HIDDEN)
	_draw_hex_tile(img, 0, FOG_TILE_SIZE,
		Color(0.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	# Col 1: semi-transparent grey hex (EXPLORED)
	_draw_hex_tile(img, 1, FOG_TILE_SIZE,
		Color(0.15, 0.15, 0.15, 0.65), Color(0.08, 0.08, 0.08, 0.80))

	var texture := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = FOG_TILE_SIZE
	source.create_tile(Vector2i(0, 0))  # HIDDEN
	source.create_tile(Vector2i(1, 0))  # EXPLORED
	tileset.add_source(source)
	return tileset


# ---------------------------------------------------------------------------
# Hex texture helpers
# ---------------------------------------------------------------------------

## Draws one hexagonal tile into [img] at atlas column [col_idx].
## Interior pixels use [fill_color]; edge pixels within [border_inset] use [border_color].
## Pixels outside the hexagon stay transparent (RGBA8 default = 0,0,0,0).
func _draw_hex_tile(img: Image, col_idx: int, tile_size: Vector2i,
		fill_color: Color, border_color: Color, border_inset: float = 1.5) -> void:
	var cx := tile_size.x * 0.5        # 32.0
	var cy := tile_size.y * 0.5        # 28.0
	var r := cx                         # circumradius = half width
	var r_fill := r - border_inset
	var ox := col_idx * tile_size.x    # x offset in atlas image

	for py in range(tile_size.y):
		for px in range(tile_size.x):
			# Use pixel centre (+0.5) for accurate boundary classification
			var dx := float(px) - cx + 0.5
			var dy := float(py) - cy + 0.5
			if _in_flat_top_hex(dx, dy, r):
				if border_inset > 0.0 and not _in_flat_top_hex(dx, dy, r_fill):
					img.set_pixel(ox + px, py, border_color)
				else:
					img.set_pixel(ox + px, py, fill_color)


## Returns true if (dx, dy) from the hex centre is inside a flat-top regular
## hexagon with circumradius [r].
##
## Derivation: a flat-top hex with circumradius R is bounded by:
##   abs(y) <= R * sqrt(3)/2          (top and bottom flat edges)
##   abs(x) + abs(y) / sqrt(3) <= R   (four diagonal edges)
## Constants: sqrt(3)/2 ≈ 0.866025,  1/sqrt(3) ≈ 0.577350
func _in_flat_top_hex(dx: float, dy: float, r: float) -> bool:
	if absf(dy) > r * 0.866025:
		return false
	if absf(dx) + absf(dy) * 0.577350 > r:
		return false
	return true
