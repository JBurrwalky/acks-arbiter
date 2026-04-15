extends PanelContainer

## Top-right minimap for dungeon exploration.
##
## Shows a schematic top-down view of the dungeon. Visible cells are always shown.
## Explored cells only retained if a party member has the Mapping proficiency
## (+ journal + ink) and the party is in exploration movement mode.
##
## Click on the minimap to jump the main camera to that location.
## Toggle with M key.

signal cell_clicked(cell: Vector2i)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MAP_SIZE := Vector2(180, 180)
const CELL_PX := 4  # Pixels per cell on the minimap.
const PARTY_COLOR := Color(0.2, 0.9, 0.3)
const VISIBLE_COLOR := Color(0.75, 0.7, 0.55)
const EXPLORED_COLOR := Color(0.35, 0.35, 0.4)
const WALL_COLOR := Color(0.5, 0.5, 0.55)
const DOOR_COLOR := Color(0.7, 0.55, 0.35)
const STAIR_COLOR := Color(0.4, 0.7, 0.9)
const BG_COLOR := Color(0.02, 0.02, 0.05)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _draw_control: Control = null
var _map: TacticalMapData = null
var _party_positions: Dictionary = {}  # entity_id -> Vector2i
var _has_mapper: bool = false
var _offset: Vector2 = Vector2.ZERO


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = MAP_SIZE

	# Dark panel style.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.06, 0.9)
	style.border_color = Color(0.35, 0.35, 0.45, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(2)
	add_theme_stylebox_override("panel", style)

	_draw_control = Control.new()
	_draw_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draw_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_draw_control.draw.connect(_on_draw)
	_draw_control.gui_input.connect(_on_minimap_input)
	_draw_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_draw_control)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the minimap with current map state.
## [param map]: TacticalMapData for the current level.
## [param party_positions]: entity_id -> Vector2i positions.
## [param has_mapper]: true if party has a mapper (explored cells retained).
func update(map: TacticalMapData, party_positions: Dictionary, has_mapper: bool) -> void:
	_map = map
	_party_positions = party_positions
	_has_mapper = has_mapper
	_compute_offset()
	_draw_control.queue_redraw()


## Toggle visibility.
func toggle() -> void:
	visible = not visible


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _compute_offset() -> void:
	if _map == null:
		_offset = Vector2.ZERO
		return
	# Center the map in the minimap area.
	var cx := _map.grid_width * CELL_PX * 0.5
	var cy := _map.grid_height * CELL_PX * 0.5
	var panel_center := MAP_SIZE * 0.5
	_offset = panel_center - Vector2(cx, cy)


func _on_draw() -> void:
	if _map == null:
		return

	# Draw cells.
	for pos in _map._cells.keys():
		var fog_state: int = _map.get_fog(pos)

		# Skip hidden cells unless mapper retains them.
		if fog_state == TacticalMapData.FogState.HIDDEN:
			continue
		if fog_state == TacticalMapData.FogState.EXPLORED and not _has_mapper:
			continue

		var cell: Dictionary = _map._cells[pos]
		var tf: String = cell.get("terrain_feature", "open")
		var rect := Rect2(
			_offset.x + pos.x * CELL_PX,
			_offset.y + pos.y * CELL_PX,
			CELL_PX, CELL_PX
		)

		var color: Color
		if fog_state == TacticalMapData.FogState.VISIBLE:
			match tf:
				"wall_stone", "wall_wood", "rock":
					color = WALL_COLOR
				"door", "door_locked", "door_secret", "portcullis":
					color = DOOR_COLOR
				"stairs_up", "stairs_down":
					color = STAIR_COLOR
				_:
					color = VISIBLE_COLOR
		else:
			# Explored (dimmed).
			match tf:
				"wall_stone", "wall_wood", "rock":
					color = WALL_COLOR * 0.5
				_:
					color = EXPLORED_COLOR

		_draw_control.draw_rect(rect, color)

	# Draw party positions.
	for eid in _party_positions:
		var pos: Vector2i = _party_positions[eid]
		var rect := Rect2(
			_offset.x + pos.x * CELL_PX - 1,
			_offset.y + pos.y * CELL_PX - 1,
			CELL_PX + 2, CELL_PX + 2
		)
		_draw_control.draw_rect(rect, PARTY_COLOR)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var local_pos: Vector2 = mb.position - _offset
		var cell_x := int(local_pos.x / CELL_PX)
		var cell_y := int(local_pos.y / CELL_PX)
		var cell_pos := Vector2i(cell_x, cell_y)
		if _map != null and _map.has_cell(cell_pos):
			cell_clicked.emit(cell_pos)
