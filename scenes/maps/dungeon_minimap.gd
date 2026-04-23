extends PanelContainer

## Top-right minimap for voxel dungeon exploration.
##
## Shows a schematic top-down view of the dungeon at the current focus level:
## - Cells in `visible` fog → full color (wall / door / stair / floor)
## - Cells in `explored` fog → dimmed
## - Cells in `hidden` fog → not drawn (panel bg shows through)
## - Party members on the focus level → green pip
##
## Cross-level visualization isn't supported — the minimap follows whatever
## level VisibilityManager is focused on. Click a cell to emit
## `cell_clicked(Vector3i)` with (col, row, focus_level); the host state uses
## that to jump focus / camera.
##
## Toggled with M key.

signal cell_clicked(cell: Vector3i)


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


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _draw_control: Control = null
var _voxel_map: VoxelMapData = null
var _focus_level: int = 0
var _party_positions: Dictionary = {}  # entity_id -> Vector3i
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

## Update the minimap to display [param vmap] at [param focus_level].
## [param party_positions] is a Dictionary of entity_id → Vector3i.
## Only cells on [param focus_level] are drawn; party pips for members on
## other levels are elided.
func update(vmap: VoxelMapData, party_positions: Dictionary, focus_level: int) -> void:
	_voxel_map = vmap
	_party_positions = party_positions
	_focus_level = focus_level
	_compute_offset()
	if _draw_control != null:
		_draw_control.queue_redraw()


## Toggle visibility.
func toggle() -> void:
	visible = not visible


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _compute_offset() -> void:
	## Centers the focus-level bounding box inside the minimap panel.
	if _voxel_map == null:
		_offset = Vector2.ZERO
		return
	var min_col: int = 2147483647
	var max_col: int = -2147483647
	var min_row: int = 2147483647
	var max_row: int = -2147483647
	var any := false
	for pos: Vector3i in _voxel_map.get_all_positions():
		if pos.z != _focus_level:
			continue
		any = true
		if pos.x < min_col:
			min_col = pos.x
		if pos.x > max_col:
			max_col = pos.x
		if pos.y < min_row:
			min_row = pos.y
		if pos.y > max_row:
			max_row = pos.y
	if not any:
		_offset = Vector2.ZERO
		return
	var center_col: float = float(min_col + max_col) * 0.5
	var center_row: float = float(min_row + max_row) * 0.5
	var panel_center := MAP_SIZE * 0.5
	_offset = panel_center - Vector2(center_col * CELL_PX, center_row * CELL_PX)


func _on_draw() -> void:
	if _voxel_map == null or _draw_control == null:
		return

	# Draw cells at the focus level.
	for cell: VoxelCell in _voxel_map.get_cells_at_level(_focus_level):
		if cell.fog_state == "hidden":
			continue

		# Secret doors that haven't been detected render as a wall to match
		# the main renderer's stealth behavior.
		var feature: String = cell.feature
		if feature == "door_secret" and not cell.door_detected:
			feature = "wall"

		var rect := Rect2(
			_offset.x + cell.col * CELL_PX,
			_offset.y + cell.row * CELL_PX,
			CELL_PX, CELL_PX
		)

		var color: Color
		if cell.fog_state == "visible":
			color = _color_for_cell(cell.solidity, feature)
		else:  # "explored"
			color = _dim_color_for_cell(cell.solidity)

		_draw_control.draw_rect(rect, color)

	# Draw party pips for members on the focus level.
	for eid in _party_positions:
		var pos: Vector3i = _party_positions[eid]
		if pos.z != _focus_level:
			continue
		var rect := Rect2(
			_offset.x + pos.x * CELL_PX - 1,
			_offset.y + pos.y * CELL_PX - 1,
			CELL_PX + 2, CELL_PX + 2
		)
		_draw_control.draw_rect(rect, PARTY_COLOR)


func _color_for_cell(solidity: String, feature: String) -> Color:
	if solidity == "solid":
		return WALL_COLOR
	if feature.begins_with("door"):
		return DOOR_COLOR
	if feature.begins_with("stairs_up") or feature.begins_with("stairs_down"):
		return STAIR_COLOR
	return VISIBLE_COLOR


func _dim_color_for_cell(solidity: String) -> Color:
	if solidity == "solid":
		return WALL_COLOR * 0.5
	return EXPLORED_COLOR


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_minimap_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _voxel_map == null:
		return
	var local_pos: Vector2 = mb.position - _offset
	var cell_x: int = int(floor(local_pos.x / CELL_PX))
	var cell_y: int = int(floor(local_pos.y / CELL_PX))
	var cell_3d := Vector3i(cell_x, cell_y, _focus_level)
	if _voxel_map.has_cell(cell_3d):
		cell_clicked.emit(cell_3d)
