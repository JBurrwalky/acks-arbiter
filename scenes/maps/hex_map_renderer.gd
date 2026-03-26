extends Node2D

## Renders a HexMapData onto TileMapLayer nodes.
##
## Scene tree expected:
##   HexMap (Node2D, this script)
##   ├── TerrainLayer (TileMapLayer)
##   ├── FogLayer (TileMapLayer)
##   └── EntityLayer (Node2D)
##       └── PartyToken (Polygon2D)
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


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _terrain_layer: TileMapLayer = $TerrainLayer
@onready var _fog_layer: TileMapLayer = $FogLayer
@onready var _entity_layer: Node2D = $EntityLayer
@onready var _party_token: Polygon2D = $EntityLayer/PartyToken


# ---------------------------------------------------------------------------
# Vars
# ---------------------------------------------------------------------------

var _controller: HexMapController
var _map_data: HexMapData


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal hex_clicked(coord: Vector2i)


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


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Wire this renderer to a HexMapController. Call once after entering the tree.
func setup(controller: HexMapController) -> void:
	_controller = controller
	controller.map_loaded.connect(_on_map_loaded)
	controller.visibility_updated.connect(_on_visibility_updated)
	controller.party_moved.connect(_on_party_moved)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_map_loaded(_map_id: String) -> void:
	_map_data = _controller.get_map()
	_refresh_terrain_layer()
	_refresh_fog_layer()
	_update_party_token_position()


func _on_visibility_updated() -> void:
	_map_data = _controller.get_map()
	_refresh_fog_layer()


func _on_party_moved(_from_hex: Vector2i, _to_hex: Vector2i) -> void:
	_update_party_token_position()


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


# ---------------------------------------------------------------------------
# Tileset factories
# ---------------------------------------------------------------------------

func _create_terrain_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tileset.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tileset.tile_size = TERRAIN_TILE_SIZE

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

	var texture := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = TERRAIN_TILE_SIZE
	for col_idx in range(TERRAIN_ATLAS_COLS):
		source.create_tile(Vector2i(col_idx, 0))
	tileset.add_source(source)
	return tileset


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
