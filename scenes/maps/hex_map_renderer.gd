extends Node2D

## Renders a HexMapData onto TileMapLayer nodes.
##
## Scene tree expected:
##   HexMap (Node2D, this script)
##   ├── TerrainLayer (TileMapLayer)
##   ├── FogLayer (TileMapLayer)
##   ├── EntityLayer (Node2D)
##   │   └── PartyToken (Sprite2D — texture bound by HeraldryRenderer)
##   ├── HeraldryHolder (Node2D, invisible — hosts SubViewports for heraldry rendering)
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

# Flat-top hex with circumradius R = 41.5:
#   Width  (tip-to-tip)  = 2R ≈ 83.1 → 83
#   Height (flat-to-flat) = R*sqrt(3) ≈ 71.9 → 72
const TERRAIN_TILE_SIZE := Vector2i(83, 72)
const TERRAIN_ATLAS_COLS := 17

# Atlas column index for each biome at flat elevation (add 5 for hills, 10 for mountains)
const BIOME_COL := {
	"clear": 0, "woods": 1, "jungle": 2, "swamp": 3, "desert": 4
}
const OCEAN_COL := 15

# Fog tile atlas: 2 columns × 1 row
const FOG_TILE_SIZE := Vector2i(83, 72)
const FOG_SOURCE_ID := 0
const FOG_HIDDEN_ATLAS := Vector2i(0, 0)
const FOG_EXPLORED_ATLAS := Vector2i(1, 0)

# Overlay rendering
const OVERLAY_LINE_WIDTH := 8.0
const RIVER_COLOR := Color(0.235, 0.471, 0.784)
const ROAD_COLOR := Color(0.545, 0.353, 0.169)

# Camera panning
const PAN_SPEED := 200.0
const EDGE_MARGIN := 40.0
const ZOOM_MIN := 1.0      # 100% — no zoom out beyond default
const ZOOM_MAX := 2.5      # 250%
const ZOOM_STEP := 0.1     # 10% additive per tick


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _terrain_layer: TileMapLayer = $TerrainLayer
@onready var _fog_layer: TileMapLayer = $FogLayer
@onready var _entity_layer: Node2D = $EntityLayer
@onready var _party_token: Sprite2D = $EntityLayer/PartyToken
@onready var _heraldry_holder: Node2D = $HeraldryHolder
@onready var _camera: Camera2D = $Camera2D
@onready var _tooltip_panel: PanelContainer = $HexHUD/TooltipPanel
@onready var _tooltip_label: Label = $HexHUD/TooltipPanel/TooltipLabel


# ---------------------------------------------------------------------------
# Vars
# ---------------------------------------------------------------------------

var _controller: HexMapController
var _map_data: HexMapData
var _zoom_level: float = 1.0

## Node2D child that draws river/road overlay lines via _draw().
var _overlay_layer: Node2D

## Tracks Label nodes placed for dungeon entrance markers (cleaned up on reload).
var _dungeon_markers: Array = []

## "Enter Dungeon" button shown when party is on a dungeon entrance hex.
var _enter_dungeon_btn: Button
## Active transition cell selection dialog (CanvasLayer), or null.
var _tc_dialog: CanvasLayer

## "Enter Settlement" button shown when party is on a settlement entrance hex.
var _enter_settlement_btn: Button
## Active gate selection dialog (CanvasLayer), or null.
var _gate_dialog: CanvasLayer

## Cached settlement entrances: Vector2i(hex_q, hex_r) → entrance dict.
var _settlement_entrance_cache: Dictionary = {}

## Multi-party token management: party_id → Sprite2D
var _party_tokens: Dictionary = {}

## party_id → HeraldryRenderer that drives the token's texture.
## Includes the primary party as well as split parties; one renderer per token.
var _heraldry_renderers: Dictionary = {}

## Token dimensions in pixels (applied as Sprite2D texture render target size).
const HERALDRY_TOKEN_PX := 64

## Axial coord → party_id. Rebuilt alongside tokens; consulted on left-click to
## decide whether the click lands on a party token (active-party selection) or
## on empty ground (no-op).
var _party_hex_index: Dictionary = {}

## Active per-token tween for the click-feedback pulse, keyed by the token node.
## Tracked so a rapid second click cancels the prior pulse before starting a new
## one (prevents stuck scales).
var _pulse_tweens: Dictionary = {}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal hex_clicked(coord: Vector2i)
signal party_token_clicked(party_id: String, coord: Vector2i)
signal hex_context_menu_requested(coord: Vector2i, screen_pos: Vector2)
signal dungeon_entry_requested(entrance: Dictionary, spawn_cell: Vector2i)
signal settlement_entry_requested(entrance: Dictionary, entry_poi_id: String)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_terrain_layer.tile_set = _create_terrain_tileset()
	_fog_layer.tile_set = _create_fog_tileset()

	# Overlay layer draws river/road lines between terrain and fog.
	_overlay_layer = Node2D.new()
	_overlay_layer.name = "OverlayLayer"
	add_child(_overlay_layer)
	move_child(_overlay_layer, _fog_layer.get_index())

	# The primary party token is a Sprite2D in the scene; its texture is bound
	# on first _rebuild_party_tokens() from the party's heraldry descriptor.

	# Connect party lifecycle signals for multi-party token management
	EventBus.party_split.connect(_on_party_split)
	EventBus.party_merged.connect(_on_party_merged)
	EventBus.active_party_changed.connect(_on_active_party_switched)
	# Any party (including non-primary) crossed a hex boundary — re-anchor
	# tokens. The controller's `party_moved` signal only fires for the
	# primary party, so this catches the rest.
	EventBus.party_hex_changed.connect(_on_party_hex_changed)
	EventBus.heraldry_changed.connect(_on_heraldry_changed)

	# "Enter Dungeon" button — child of HexHUD (CanvasLayer) so it stays on screen.
	_enter_dungeon_btn = Button.new()
	_enter_dungeon_btn.text = "Enter Dungeon"
	_enter_dungeon_btn.visible = false
	_enter_dungeon_btn.pressed.connect(_on_enter_dungeon_pressed)
	$HexHUD.add_child(_enter_dungeon_btn)

	# "Enter Settlement" button — child of HexHUD so it stays on screen.
	_enter_settlement_btn = Button.new()
	_enter_settlement_btn.text = "Enter Settlement"
	_enter_settlement_btn.visible = false
	_enter_settlement_btn.pressed.connect(_on_enter_settlement_pressed)
	$HexHUD.add_child(_enter_settlement_btn)


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
		_camera.position += pan_dir.normalized() * PAN_SPEED * delta / _zoom_level

	# Keep Enter Dungeon button at 10% from top-right edges.
	if _enter_dungeon_btn != null and _enter_dungeon_btn.visible:
		var btn_size := _enter_dungeon_btn.size
		_enter_dungeon_btn.position = Vector2(
			vp_size.x * 0.9 - btn_size.x,
			vp_size.y * 0.1
		)

	# Keep Enter Settlement button below the dungeon button.
	if _enter_settlement_btn != null and _enter_settlement_btn.visible:
		var sbtn_size := _enter_settlement_btn.size
		var y_offset: float = vp_size.y * 0.1
		if _enter_dungeon_btn != null and _enter_dungeon_btn.visible:
			y_offset += _enter_dungeon_btn.size.y + 8.0
		_enter_settlement_btn.position = Vector2(
			vp_size.x * 0.9 - sbtn_size.x,
			y_offset
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
	controller.hex_overlay_updated.connect(_on_overlay_updated)


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
	_zoom_level = 1.0
	if _camera != null:
		_camera.zoom = Vector2(1.0, 1.0)
	_refresh_terrain_layer()
	_refresh_overlay_layer()
	_refresh_fog_layer()
	_rebuild_party_tokens()
	_compute_camera_limits()
	center_on_hex(_map_data.party_hex)
	_refresh_dungeon_markers()
	_update_enter_dungeon_button()
	_cache_settlement_entrances()
	_update_enter_settlement_button()


func _on_visibility_updated() -> void:
	_map_data = _controller.get_map()
	_refresh_fog_layer()


func _on_party_moved(_from_hex: Vector2i, _to_hex: Vector2i) -> void:
	_rebuild_party_tokens()
	_update_enter_dungeon_button()
	_update_enter_settlement_button()


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

	# Voxel format: single "cells" array + top-level "entry" + optional
	# "transition_cells". Legacy format: "levels" array with per-level fields.
	var tc_array: Array
	var entry_pos: Vector2i

	if dungeon_dict.has("cells"):
		tc_array = dungeon_dict.get("transition_cells", [])
		var entry_dict: Dictionary = dungeon_dict.get("entry", {})
		entry_pos = Vector2i(
			int(entry_dict.get("col", 0)),
			int(entry_dict.get("row", 0))
		)
	else:
		var levels: Array = dungeon_dict.get("levels", [])
		if levels.is_empty():
			return
		var level1: Dictionary = levels[0]
		tc_array = level1.get("transition_cells", [])
		entry_pos = Vector2i(
			int(level1.get("entry_col", 0)),
			int(level1.get("entry_row", 0))
		)

	if tc_array.is_empty():
		# No transition cells — fall back to single entry point.
		dungeon_entry_requested.emit(entrance, entry_pos)
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
# Enter Settlement button + modal
# ---------------------------------------------------------------------------

## Caches settlement entrances for the current map. Called on map load.
func _cache_settlement_entrances() -> void:
	_settlement_entrance_cache.clear()
	if _map_data == null:
		return
	var entrances := CampaignRepository.get_settlement_entrances_for_map(_map_data.id)
	for entrance in entrances:
		var coord := Vector2i(entrance.get("hex_q", 999), entrance.get("hex_r", 999))
		_settlement_entrance_cache[coord] = entrance


## Shows or hides the "Enter <name>" button depending on party hex.
func _update_enter_settlement_button() -> void:
	if _enter_settlement_btn == null or _map_data == null:
		return
	var party_hex := _map_data.party_hex
	if _settlement_entrance_cache.has(party_hex):
		var entrance: Dictionary = _settlement_entrance_cache[party_hex]
		var sname: String = entrance.get("name", "Settlement")
		_enter_settlement_btn.text = "Enter %s" % sname
		_enter_settlement_btn.visible = true
		_enter_settlement_btn.set_meta("entrance_data", entrance)
		return
	_enter_settlement_btn.visible = false


func _on_enter_settlement_pressed() -> void:
	var entrance: Dictionary = _enter_settlement_btn.get_meta("entrance_data")
	var settlement_json: String = entrance.get("settlement_data", "")
	var settlement_dict = JSON.parse_string(settlement_json)
	if settlement_dict == null:
		return

	# Collect all entry/exit PoIs from the slim settlement format
	# (gdd-settlement-layout.md v2 §6.4). Any PoI in any district may be
	# flagged is_entry_exit; it's not tied to PoI type.
	var entry_pois: Array = []
	for district in settlement_dict.get("districts", []):
		for poi in district.get("pois", []):
			if poi.get("is_entry_exit", false):
				entry_pois.append(poi)

	if entry_pois.is_empty():
		# Fallback: pick the first PoI of the first district so the player
		# can at least enter. (Should not happen with well-formed settlements.)
		var districts: Array = settlement_dict.get("districts", [])
		if districts.is_empty():
			return
		var first_district: Dictionary = districts[0]
		var pois: Array = first_district.get("pois", [])
		if pois.is_empty():
			return
		settlement_entry_requested.emit(entrance, str(pois[0].get("id", "")))
		return

	if entry_pois.size() == 1:
		settlement_entry_requested.emit(entrance, str(entry_pois[0].get("id", "")))
		return

	_show_entry_exit_dialog(entrance, entry_pois)


## Builds and shows a modal dialog listing entry/exit PoIs to choose from.
func _show_entry_exit_dialog(entrance: Dictionary, entry_pois: Array) -> void:
	if _gate_dialog != null and is_instance_valid(_gate_dialog):
		_gate_dialog.queue_free()

	_gate_dialog = CanvasLayer.new()
	_gate_dialog.layer = 20  # above HexHUD (10)

	# Full-screen dimmer
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.0, 0.0, 0.0, 0.5)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gate_dialog.add_child(dimmer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(320, 0)
	_gate_dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var sname: String = entrance.get("name", "Settlement")
	var title_label := Label.new()
	title_label.text = "Enter %s" % sname
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var subtitle := Label.new()
	subtitle.text = "Select an entry point:"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	for poi in entry_pois:
		var poi_id := str(poi.get("id", ""))
		var poi_name := str(poi.get("name", poi_id))
		var district_id := str(poi.get("district_id", ""))
		var label_text := poi_name
		if not district_id.is_empty():
			label_text = "%s (%s)" % [poi_name, district_id]

		var btn := Button.new()
		btn.text = label_text
		btn.pressed.connect(_on_entry_poi_selected.bind(entrance, poi_id))
		vbox.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Do not enter"
	cancel_btn.pressed.connect(_close_gate_dialog)
	vbox.add_child(cancel_btn)

	add_child(_gate_dialog)


func _on_entry_poi_selected(entrance: Dictionary, entry_poi_id: String) -> void:
	_close_gate_dialog()
	settlement_entry_requested.emit(entrance, entry_poi_id)


func _close_gate_dialog() -> void:
	if _gate_dialog != null and is_instance_valid(_gate_dialog):
		_gate_dialog.queue_free()
		_gate_dialog = null


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
	if terrain.water in [HexTerrainData.WATER_OCEAN, HexTerrainData.WATER_LAKE] or terrain.biome == "ocean":
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


## Rebuilds all party tokens from the database. Creates/removes Sprite2D nodes
## and their paired HeraldryRenderer instances as needed. Active party token is
## full-bright at 1.15×; inactive tokens are slightly desaturated at 0.9×.
func _rebuild_party_tokens() -> void:
	if _map_data == null or _terrain_layer == null:
		return

	var active_id := GameState.active_party_id
	if active_id.is_empty():
		active_id = GameState.party_id

	# Query all parties for the campaign
	var all_parties: Array = CampaignRepository.list_parties_for_campaign(GameState.campaign_id)

	# Track which party_ids are still valid
	var valid_ids: Dictionary = {}
	_party_hex_index.clear()

	for p in all_parties:
		var pid: String = p.id
		valid_ids[pid] = true

		var hex_q: int = p.get("current_hex_q", 0) if p.get("current_hex_q") != null else 0
		var hex_r: int = p.get("current_hex_r", 0) if p.get("current_hex_r") != null else 0

		var coord := Vector2i(hex_q, hex_r)
		# Primary party prefers live map data over DB.
		if pid == GameState.party_id and _map_data != null:
			coord = _map_data.party_hex

		var token := _get_or_create_token_for_party(pid)
		var godot_coord := HexMapController.axial_to_godot_map(coord)
		token.position = _terrain_layer.map_to_local(godot_coord)
		_ensure_heraldry_for_party(pid, token)
		_style_token(token, pid == active_id)
		_index_party_hex(coord, pid, active_id)

	# Remove split-party tokens whose parties no longer exist.
	# The scene-defined primary token is never removed; its heraldry renderer
	# is left in place even if the party transiently disappears from DB.
	var stale_ids: Array = []
	for pid in _party_tokens:
		if not valid_ids.has(pid):
			stale_ids.append(pid)
	for pid in stale_ids:
		var token: Sprite2D = _party_tokens[pid]
		if is_instance_valid(token):
			token.queue_free()
		_party_tokens.erase(pid)
		_free_heraldry_renderer(pid)


## Returns the Sprite2D token for [param party_id], creating one if missing.
## The primary party uses the scene-defined _party_token; other parties get
## dynamically-created tokens parented under _entity_layer.
func _get_or_create_token_for_party(party_id: String) -> Sprite2D:
	if party_id == GameState.party_id:
		return _party_token
	if _party_tokens.has(party_id):
		return _party_tokens[party_id]
	var token := _create_party_token_node()
	_entity_layer.add_child(token)
	_party_tokens[party_id] = token
	return token


## Ensures the party has a HeraldryRenderer in _heraldry_renderers and its
## texture is bound to [param token]. Fetches the descriptor from the DB on
## first call; subsequent calls are cheap no-ops unless the descriptor changed.
func _ensure_heraldry_for_party(party_id: String, token: Sprite2D) -> void:
	var renderer: HeraldryRenderer = _heraldry_renderers.get(party_id, null)
	if renderer == null or not is_instance_valid(renderer):
		renderer = HeraldryRenderer.new()
		_heraldry_holder.add_child(renderer)
		_heraldry_renderers[party_id] = renderer
		var descriptor := CampaignRepository.get_heraldry_for_party(party_id)
		if descriptor == null:
			# Shouldn't happen post-backfill, but stay defensive — use an
			# empty descriptor with defaults so the token still renders.
			descriptor = HeraldryDescriptor.new()
		renderer.update_descriptor(descriptor, HERALDRY_TOKEN_PX)
	if token.texture != renderer.get_texture():
		token.texture = renderer.get_texture()


func _free_heraldry_renderer(party_id: String) -> void:
	var renderer: HeraldryRenderer = _heraldry_renderers.get(party_id, null)
	if renderer != null and is_instance_valid(renderer):
		renderer.queue_free()
	_heraldry_renderers.erase(party_id)


## Records a party's hex for left-click lookup. When multiple parties share a
## hex the active party wins the hit test; otherwise the first party written
## is kept (stable across renders).
func _index_party_hex(coord: Vector2i, party_id: String, active_id: String) -> void:
	if not _party_hex_index.has(coord):
		_party_hex_index[coord] = party_id
	elif party_id == active_id:
		_party_hex_index[coord] = party_id


## Creates a new Sprite2D party token node. The texture is bound later by
## _ensure_heraldry_for_party once the paired HeraldryRenderer has rendered.
func _create_party_token_node() -> Sprite2D:
	var token := Sprite2D.new()
	token.centered = true
	return token


## Styles a party token. Active: full-bright, 1.15× scale. Inactive: slightly
## desaturated, 0.9× scale. Lets a mid-flight pulse own the scale if active.
const ACTIVE_SCALE := Vector2(1.15, 1.15)
const INACTIVE_SCALE := Vector2(0.9, 0.9)
const ACTIVE_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const INACTIVE_MODULATE := Color(0.72, 0.72, 0.78, 1.0)


func _style_token(token: Sprite2D, is_active: bool) -> void:
	# Don't fight an in-flight click pulse — leave scale alone if a pulse owns it.
	if not _pulse_tweens.has(token):
		token.scale = ACTIVE_SCALE if is_active else INACTIVE_SCALE
	token.modulate = ACTIVE_MODULATE if is_active else INACTIVE_MODULATE


## Plays a 200ms scale pulse on [param token]. Confirms a click landed even
## when the active party didn't change. Restores the steady-state scale at end.
func _play_click_pulse(token: Sprite2D) -> void:
	if token == null or not is_instance_valid(token):
		return
	# Cancel any prior pulse on this token to avoid stacking tweens.
	if _pulse_tweens.has(token):
		var prev: Tween = _pulse_tweens[token]
		if prev != null and prev.is_valid():
			prev.kill()
		_pulse_tweens.erase(token)
	var base_scale := token.scale
	var pulse_scale := base_scale * 1.15
	var tw := token.create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(token, "scale", pulse_scale, 0.1)
	tw.tween_property(token, "scale", base_scale, 0.1)
	tw.finished.connect(_on_pulse_finished.bind(token, base_scale))
	_pulse_tweens[token] = tw


func _on_pulse_finished(token: Sprite2D, base_scale: Vector2) -> void:
	if _pulse_tweens.has(token):
		_pulse_tweens.erase(token)
	if is_instance_valid(token):
		token.scale = base_scale


## Returns the Sprite2D token node for [param party_id], or null if absent.
## The "primary" party uses the scene-defined _party_token; all other parties
## live in _party_tokens.
func _token_for_party(party_id: String) -> Sprite2D:
	if party_id == GameState.party_id:
		return _party_token
	return _party_tokens.get(party_id, null)


func _on_party_split(_original_id: String, _new_id: String) -> void:
	_rebuild_party_tokens()


func _on_party_merged(_surviving_id: String, _dissolved_id: String) -> void:
	_rebuild_party_tokens()


func _on_active_party_switched(_prev_id: String, _new_id: String) -> void:
	_rebuild_party_tokens()


## A party (primary or non-primary) finished a travel_leg. Rebuild tokens so
## the moving party's polygon snaps to its new hex. Includes the active-
## dungeon-entrance / Enter-Settlement button refresh in case the moved party
## is the active one and is now standing on (or no longer on) an entrance.
func _on_party_hex_changed(_party_id: String, _hex: Vector2i) -> void:
	_rebuild_party_tokens()
	_update_enter_dungeon_button()
	_update_enter_settlement_button()


## Looks up which party owns the changed heraldry and re-renders just that
## token's shield in place. Skips rebuilding all tokens — the change doesn't
## affect other parties, and the Sprite2D.texture reference remains stable.
func _on_heraldry_changed(heraldry_id: String) -> void:
	if GameState.campaign_id.is_empty():
		return
	var all_parties: Array = CampaignRepository.list_parties_for_campaign(GameState.campaign_id)
	for p in all_parties:
		if str(p.get("heraldry_id", "")) != heraldry_id:
			continue
		var pid: String = p.id
		var renderer: HeraldryRenderer = _heraldry_renderers.get(pid, null)
		if renderer == null or not is_instance_valid(renderer):
			# No renderer yet for this party; rebuild will create one on next pass.
			_rebuild_party_tokens()
			return
		var descriptor := CampaignRepository.get_heraldry_for_party(pid)
		if descriptor != null:
			renderer.update_descriptor(descriptor, HERALDRY_TOKEN_PX)
		return


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


## Redraws all river/road overlay lines. Called on map load and overlay updates.
func _refresh_overlay_layer() -> void:
	# Clear existing overlay children
	for child in _overlay_layer.get_children():
		child.queue_free()
	if _map_data == null:
		return
	for coord in _map_data.hexes.keys():
		var terrain: HexTerrainData = _map_data.get_hex(coord)
		if terrain == null or terrain.overlay == null:
			continue
		var godot_coord := HexMapController.axial_to_godot_map(coord)
		var hex_center := _terrain_layer.map_to_local(godot_coord)
		# Draw roads first (under rivers)
		if terrain.overlay.has_road():
			_draw_overlay_lines(hex_center, terrain.overlay.road_edges, ROAD_COLOR)
		if terrain.overlay.has_river():
			_draw_overlay_lines(hex_center, terrain.overlay.river_edges, RIVER_COLOR)


## Draws overlay lines from each connected edge midpoint through the hex center.
func _draw_overlay_lines(hex_center: Vector2, edges: Array[int], color: Color) -> void:
	if edges.size() == 1:
		# Terminating overlay: draw from edge midpoint to hex center
		var edge_pos := hex_center + _edge_midpoint_offset(edges[0])
		var line := Line2D.new()
		line.points = [edge_pos, hex_center]
		line.width = OVERLAY_LINE_WIDTH
		line.default_color = color
		line.antialiased = true
		_overlay_layer.add_child(line)
	else:
		# Multiple edges: draw a line from each edge midpoint to the hex center.
		# This creates a hub-and-spoke pattern through center.
		for edge in edges:
			var edge_pos := hex_center + _edge_midpoint_offset(edge)
			var line := Line2D.new()
			line.points = [edge_pos, hex_center]
			line.width = OVERLAY_LINE_WIDTH
			line.default_color = color
			line.antialiased = true
			_overlay_layer.add_child(line)


## Returns the pixel offset from hex center to the midpoint of the given edge.
## Edge numbering: 0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW (clockwise from North).
## For a flat-top hex with circumradius R (= TERRAIN_TILE_SIZE.x / 2):
##   N/S midpoints:  (0, ±R*√3/2)
##   NE/SW midpoints: (R*3/4, ∓R*√3/4)
##   SE/NW midpoints: (R*3/4, ±R*√3/4)
func _edge_midpoint_offset(edge: int) -> Vector2:
	var r := float(TERRAIN_TILE_SIZE.x) * 0.5  # circumradius
	var h := r * 0.866025  # R * √3/2
	var qr := r * 0.75     # R * 3/4
	var qh := r * 0.433013 # R * √3/4
	match edge:
		0: return Vector2(0.0, -h)       # N
		1: return Vector2(qr, -qh)       # NE
		2: return Vector2(qr, qh)        # SE
		3: return Vector2(0.0, h)        # S
		4: return Vector2(-qr, qh)       # SW
		5: return Vector2(-qr, -qh)      # NW
		_: return Vector2.ZERO


func _on_overlay_updated(_coord: Vector2i) -> void:
	_refresh_overlay_layer()


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
# Tooltip
# ---------------------------------------------------------------------------

## Show terrain info near the cursor for EXPLORED/VISIBLE hexes; hide for HIDDEN.
## Also swaps the system cursor to a pointing-hand when hovering a party token
## so the player knows the token is interactable.
func _update_tooltip(viewport_pos: Vector2) -> void:
	if _map_data == null or _tooltip_panel == null:
		return
	var local_pos := _terrain_layer.get_local_mouse_position()
	var godot_coord := _terrain_layer.local_to_map(local_pos)
	var axial_coord := HexMapController.godot_map_to_axial(godot_coord)
	# Hover cursor over party tokens (interactable). Set every frame so we
	# revert as soon as the cursor leaves the token's hex.
	if _party_hex_index.has(axial_coord):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
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
	var has_settlement := terrain.has_city or _settlement_entrance_cache.has(coord)
	var text := (
		"Hex (%d, %d)\nElevation: %s\nBiome: %s\nWater: %s\nTerritory: %s\nCity: %s"
		% [coord.x, coord.y, terrain.elevation, terrain.biome, water_str,
		   terrain.civilization, "yes" if has_settlement else "no"]
	)
	if terrain.overlay != null:
		if terrain.overlay.has_river():
			var entry_names: Array[String] = []
			for e in terrain.overlay.river_entry_edges():
				entry_names.append(HexOverlayData.edge_name(e))
			var exit_str := HexOverlayData.edge_name(terrain.overlay.river_flow_exit) if terrain.overlay.river_flow_exit >= 0 else "terminus"
			if entry_names.is_empty():
				text += "\nRiver: source -> %s" % exit_str
			else:
				text += "\nRiver: %s -> %s" % [", ".join(entry_names), exit_str]
		if terrain.overlay.has_road():
			var road_names: Array[String] = []
			for e in terrain.overlay.road_edges:
				road_names.append(HexOverlayData.edge_name(e))
			text += "\nRoad: %s" % " - ".join(road_names)
	# Phase 2: weather hover line. Reads WeatherCache for the current
	# campaign day at this hex. Mid-day cache misses on a hex the player
	# hovers but has not yet visited resolve via WeatherCache.get_or_generate
	# (deterministic per (campaign_id, hex, julian_day, year)).
	var weather_line: String = _weather_tooltip_line(coord, terrain)
	if not weather_line.is_empty():
		text += "\nWeather: %s" % weather_line
	# Phase 4: lair / survey hover lines. Show the count of revealed lairs
	# in this hex (independent of party — every player sees them once
	# discovered) and the active party's most recent Land Surveying estimate.
	var lair_line: String = _lair_tooltip_line(coord)
	if not lair_line.is_empty():
		text += "\nLairs: %s" % lair_line
	var estimate_line: String = _survey_estimate_tooltip_line(coord)
	if not estimate_line.is_empty():
		text += "\nSurvey: %s" % estimate_line
	return text


## Phase 4 helper: returns "N revealed" when at least one lair on this hex
## has been discovered, else empty string. Counts only `discovered = 1`
## rows — undiscovered lairs are fog-of-war.
func _lair_tooltip_line(coord: Vector2i) -> String:
	if _map_data == null or _map_data.id.is_empty():
		return ""
	var campaign_id: String = ""
	if typeof(GameState) != TYPE_NIL:
		campaign_id = GameState.campaign_id
	if campaign_id.is_empty():
		return ""
	var rows: Array = CampaignRepository.get_lairs_in_hex(
		campaign_id, _map_data.id, coord.x, coord.y)
	var revealed: int = 0
	for row: Dictionary in rows:
		if int(row.get("discovered", 0)) == 1:
			revealed += 1
	if revealed <= 0:
		return ""
	return "%d revealed" % revealed


## Phase 4 helper: returns a short string describing the active party's
## most recent Land Surveying estimate for this hex. Empty when no estimate
## has ever been made or no active party is present.
func _survey_estimate_tooltip_line(coord: Vector2i) -> String:
	if _map_data == null or _map_data.id.is_empty():
		return ""
	var campaign_id: String = ""
	var party_id: String = ""
	if typeof(GameState) != TYPE_NIL:
		campaign_id = GameState.campaign_id
		party_id = GameState.active_party_id
	if campaign_id.is_empty() or party_id.is_empty():
		return ""
	var row: Dictionary = CampaignRepository.get_survey_progress(
		campaign_id, _map_data.id, party_id, coord.x, coord.y)
	if row.is_empty():
		return ""
	var estimate: int = int(row.get("last_estimate", -1))
	if estimate < 0:
		return ""
	# Show the estimate; never reveal whether it was a false reading from a
	# natural-1 (player only finds out after additional searches).
	return "estimated %d lair(s)" % estimate


## Phase 2 helper: formats the current day's weather for a hex into a short
## hover-line. Returns an empty string when no campaign / repository is
## available (e.g., test fixtures, pre-load state).
func _weather_tooltip_line(coord: Vector2i, terrain: HexTerrainData) -> String:
	if terrain == null:
		return ""
	var campaign_id: String = ""
	if Engine.has_singleton("GameState"):
		campaign_id = GameState.campaign_id
	elif typeof(GameState) != TYPE_NIL:
		campaign_id = GameState.campaign_id
	if campaign_id.is_empty():
		return ""
	var julian_day: int = Timekeeping.get_day_of_year()
	@warning_ignore("integer_division")
	var year: int = (Timekeeping.get_total_days() / Timekeeping.DAYS_PER_YEAR) + 1
	var weather: WeatherStateData = WeatherCache.get_or_generate(
		campaign_id, coord.x, coord.y, terrain, julian_day, year)
	if weather == null:
		return ""
	var line: String = weather.short_label()
	if weather.produces_mud:
		line += " (mud)"
	return line


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var local_pos := _terrain_layer.get_local_mouse_position()
				var godot_coord := _terrain_layer.local_to_map(local_pos)
				var axial_coord := HexMapController.godot_map_to_axial(godot_coord)
				if _map_data != null and _map_data.is_valid_coord(axial_coord):
					# Party-token hits drive active-party selection. Empty hexes
					# are a no-op — movement is issued via the right-click menu.
					if _party_hex_index.has(axial_coord):
						var clicked_pid: String = _party_hex_index[axial_coord]
						# Pulse the clicked token even when the active party
						# does not change — confirms the click landed.
						_play_click_pulse(_token_for_party(clicked_pid))
						party_token_clicked.emit(clicked_pid, axial_coord)
					else:
						hex_clicked.emit(axial_coord)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				var local_pos := _terrain_layer.get_local_mouse_position()
				var godot_coord := _terrain_layer.local_to_map(local_pos)
				var axial_coord := HexMapController.godot_map_to_axial(godot_coord)
				if _map_data != null and _map_data.is_valid_coord(axial_coord):
					hex_context_menu_requested.emit(axial_coord, event.position)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				_apply_zoom(_zoom_level + ZOOM_STEP, event.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom(_zoom_level - ZOOM_STEP, event.position)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		_update_tooltip(event.position)

	elif event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_EQUAL, KEY_KP_ADD:
					_apply_zoom(_zoom_level + ZOOM_STEP)
					get_viewport().set_input_as_handled()
				KEY_MINUS, KEY_KP_SUBTRACT:
					_apply_zoom(_zoom_level - ZOOM_STEP)
					get_viewport().set_input_as_handled()
		elif event.keycode == KEY_HOME:
			_apply_zoom(1.0)
			if _map_data != null:
				center_on_hex(_map_data.party_hex)
			get_viewport().set_input_as_handled()


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
	var cx := tile_size.x * 0.5
	var cy := tile_size.y * 0.5
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
