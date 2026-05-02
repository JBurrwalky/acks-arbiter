extends Control

## Non-interactive city overview widget — a minimap-style schematic of the
## settlement showing district blocks, streets, walls, POI markers, and
## character pins.
##
## No class_name — instantiated by SettlementExploreState only.
## Per gdd-settlement-exploration-ui.md §9: ~300x300px, non-interactive
## background (no click-to-navigate), but character pins are interactive.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WIDGET_SIZE := Vector2(280, 280)
const PADDING := 12.0

const DISTRICT_COLORS := {
	"market":          Color(0.82, 0.75, 0.58),
	"residential":     Color(0.78, 0.72, 0.64),
	"craftsmen":       Color(0.72, 0.65, 0.55),
	"castle":          Color(0.65, 0.62, 0.58),
	"temple":          Color(0.85, 0.82, 0.75),
	"docks":           Color(0.65, 0.70, 0.75),
	"thieves_quarter": Color(0.58, 0.55, 0.52),
	"outskirts":       Color(0.72, 0.75, 0.62),
	"plaza":           Color(0.85, 0.80, 0.70),
}
const DEFAULT_BLOCK_COLOR := Color(0.75, 0.70, 0.62)

const STREET_COLORS := {
	"main_road": Color(0.35, 0.28, 0.18),
	"secondary": Color(0.45, 0.38, 0.28),
	"minor":     Color(0.55, 0.48, 0.38),
	"alley":     Color(0.60, 0.55, 0.48),
}
const STREET_WIDTHS := {
	"main_road": 2.5,
	"secondary": 1.5,
	"minor":     1.0,
	"alley":     0.0,
}

const POI_MARKER_RADIUS := 4.0
const POI_COLORS := {
	"tavern":    Color(0.85, 0.55, 0.20),
	"temple":    Color(0.90, 0.88, 0.80),
	"shop":      Color(0.80, 0.70, 0.30),
	"guild":     Color(0.40, 0.55, 0.75),
	"gate":      Color(0.60, 0.45, 0.25),
}
const DEFAULT_POI_COLOR := Color(0.65, 0.60, 0.55)

const WALL_COLOR := Color(0.50, 0.48, 0.45)
const WALL_WIDTH := 2.0

const PARTY_PIN_RADIUS := 6.0
const PARTY_PIN_COLOR := Color(1.0, 0.9, 0.1)
const PARTY_PIN_OUTLINE := Color(0.2, 0.15, 0.05)

# H.3 (item 2) — per-character pins. Render at the character's node_id with
# a small radial offset by index so multiple characters at the same node
# don't fully overlap. Click → emits `character_pin_clicked(character_id)`
# which the host (SettlementExploreState) routes to
# `EventBus.notebook_active_entity_requested`.
const CHARACTER_PIN_RADIUS := 4.0
const CHARACTER_PIN_OUTLINE := Color(0.10, 0.08, 0.04, 1.0)
# Color cycle for per-character pins so multiple PCs at the same node render
# distinguishably. A future polish pass can derive these from each PC's
# portrait dominant color.
const CHARACTER_PIN_COLORS := [
	Color(0.30, 0.65, 0.95),  # blue
	Color(0.85, 0.30, 0.60),  # magenta
	Color(0.55, 0.85, 0.40),  # green
	Color(0.95, 0.55, 0.30),  # orange
	Color(0.75, 0.55, 0.95),  # purple
	Color(0.95, 0.85, 0.30),  # gold
]
# How far each character pin is offset from the host node center, per index.
const CHARACTER_PIN_RADIAL_OFFSET := 9.0


## Emitted when the player clicks within the radius of a character pin. The
## host (SettlementExploreState) consumes this and forwards to the global
## active-entity flow.
signal character_pin_clicked(character_id: String)

const BG_COLOR := Color(0.15, 0.14, 0.12, 0.85)
const BORDER_COLOR := Color(0.4, 0.35, 0.28)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _map_data: SettlementMapData = null
var _party_node_id: int = -1
var _discovered_poi_ids: Array[String] = []
var _transform_scale: float = 1.0
var _transform_offset: Vector2 = Vector2.ZERO

## H.3 — per-character positions. character_id -> {node_id: int, name: String,
## tooltip: String}. update_character_positions() rebuilds this; queued screen
## positions cached for hit-testing (`_character_pin_screen_positions`).
var _character_positions: Dictionary = {}
var _character_pin_screen_positions: Dictionary = {}  # character_id -> Vector2


func _ready() -> void:
	custom_minimum_size = WIDGET_SIZE
	size = WIDGET_SIZE
	# H.3 — accept input so character-pin clicks fire. Default was IGNORE
	# (the widget was view-only); MOUSE_FILTER_PASS lets clicks outside any
	# pin pass through to whatever's behind so we don't accidentally swallow
	# settlement panel input.
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(map_data: SettlementMapData, party_node_id: int, discovered_poi_ids: Array[String]) -> void:
	_map_data = map_data
	_party_node_id = party_node_id
	_discovered_poi_ids = discovered_poi_ids
	_compute_transform()
	queue_redraw()


func update_party_position(node_id: int) -> void:
	_party_node_id = node_id
	queue_redraw()


func update_discovered_pois(ids: Array[String]) -> void:
	_discovered_poi_ids = ids
	queue_redraw()


## H.3 (item 2) — per-member pin data. [param positions] is a Dictionary of
## character_id -> {node_id: int, name: String, tooltip: String}. Pass an
## empty dict to clear all pins.
func update_character_positions(positions: Dictionary) -> void:
	_character_positions = positions.duplicate(true)
	queue_redraw()


# ---------------------------------------------------------------------------
# Transform: map coordinates → widget coordinates
# ---------------------------------------------------------------------------

func _compute_transform() -> void:
	if _map_data == null:
		return
	var bounds: Rect2 = _map_data.bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_transform_scale = 1.0
		_transform_offset = Vector2.ZERO
		return

	var available := WIDGET_SIZE - Vector2(PADDING * 2, PADDING * 2)
	var scale_x: float = available.x / bounds.size.x
	var scale_y: float = available.y / bounds.size.y
	_transform_scale = minf(scale_x, scale_y)
	_transform_offset = Vector2(PADDING, PADDING) - bounds.position * _transform_scale
	# Center the content.
	var rendered_size := bounds.size * _transform_scale
	var centering := (available - rendered_size) * 0.5
	_transform_offset += centering


func _to_widget(pos: Vector2) -> Vector2:
	return pos * _transform_scale + _transform_offset


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Background.
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.5)

	if _map_data == null:
		return

	_draw_blocks()
	_draw_walls()
	_draw_streets()
	_draw_pois()
	_draw_party_pin()
	_draw_character_pins()


func _draw_blocks() -> void:
	for block in _map_data.blocks:
		var polygon: Array = block.get("polygon", [])
		if polygon.size() < 3:
			continue

		var district_id: String = block.get("district_id", "")
		var district: Dictionary = _map_data.get_district_by_id(district_id)
		var dist_type: String = district.get("type", "residential")
		var color: Color = DISTRICT_COLORS.get(dist_type, DEFAULT_BLOCK_COLOR)

		var points := PackedVector2Array()
		for pt in polygon:
			points.append(_to_widget(pt))

		if points.size() >= 3:
			draw_colored_polygon(points, color)
			# Outline.
			var outline := PackedVector2Array(points)
			outline.append(points[0])  # Close the polygon.
			draw_polyline(outline, color.darkened(0.3), 1.0)


func _draw_streets() -> void:
	for edge in _map_data.street_graph.get("edges", []):
		var edge_type: String = edge.get("type", "minor")
		var width: float = STREET_WIDTHS.get(edge_type, 0.0)
		if width <= 0.0:
			continue

		var a_id: int = edge.get("node_a", 0)
		var b_id: int = edge.get("node_b", 0)
		var node_a: Dictionary = _map_data.get_node_by_id(a_id)
		var node_b: Dictionary = _map_data.get_node_by_id(b_id)
		if node_a.is_empty() or node_b.is_empty():
			continue

		var pos_a := _to_widget(node_a.get("position", Vector2.ZERO))
		var pos_b := _to_widget(node_b.get("position", Vector2.ZERO))
		var color: Color = STREET_COLORS.get(edge_type, STREET_COLORS["minor"])
		draw_line(pos_a, pos_b, color, width)


func _draw_walls() -> void:
	var wall_path: Array = _map_data.walls.get("path", [])
	if wall_path.size() < 2:
		return

	var points := PackedVector2Array()
	for pt in wall_path:
		points.append(_to_widget(pt))

	if points.size() >= 2:
		draw_polyline(points, WALL_COLOR, WALL_WIDTH)

	# Towers.
	for tower_pos in _map_data.walls.get("towers", []):
		draw_circle(_to_widget(tower_pos), 3.0, WALL_COLOR)


func _draw_pois() -> void:
	for poi in _map_data.pois:
		var poi_id: String = poi.get("id", "")
		var is_discovered: bool = poi_id in _discovered_poi_ids
		var is_obvious: bool = poi.get("importance", "minor") == "major" or poi.get("type", "") == "gate"
		if not is_discovered and not is_obvious:
			continue

		var node_ids: Array = poi.get("street_node_ids", [])
		if node_ids.is_empty():
			continue

		var node: Dictionary = _map_data.get_node_by_id(node_ids[0])
		if node.is_empty():
			continue

		var pos := _to_widget(node.get("position", Vector2.ZERO))
		var poi_type: String = poi.get("type", "")
		var color: Color = POI_COLORS.get(poi_type, DEFAULT_POI_COLOR)
		draw_circle(pos, POI_MARKER_RADIUS, color)
		draw_arc(pos, POI_MARKER_RADIUS, 0, TAU, 12, color.darkened(0.3), 1.0)


func _draw_party_pin() -> void:
	if _party_node_id < 0 or _map_data == null:
		return
	var node: Dictionary = _map_data.get_node_by_id(_party_node_id)
	if node.is_empty():
		return

	var pos := _to_widget(node.get("position", Vector2.ZERO))
	draw_circle(pos, PARTY_PIN_RADIUS + 2, PARTY_PIN_OUTLINE)
	draw_circle(pos, PARTY_PIN_RADIUS, PARTY_PIN_COLOR)


# H.3 (item 2) — per-character pins. Renders one small dot per character at
# their assigned node_id, with a small radial offset by index so multiple
# characters at the same node render distinguishably. Hit-test cache
# (_character_pin_screen_positions) is populated here for input handling.
func _draw_character_pins() -> void:
	_character_pin_screen_positions.clear()
	if _map_data == null or _character_positions.is_empty():
		return
	# Group by node_id so we can apply a radial fan when multiple characters
	# share a node.
	var by_node: Dictionary = {}  # node_id -> Array[character_id]
	for cid in _character_positions.keys():
		var info: Dictionary = _character_positions[cid]
		var node_id: int = int(info.get("node_id", -1))
		if node_id < 0:
			continue
		if not by_node.has(node_id):
			by_node[node_id] = []
		by_node[node_id].append(cid)

	var color_index: int = 0
	for node_id in by_node.keys():
		var node: Dictionary = _map_data.get_node_by_id(int(node_id))
		if node.is_empty():
			continue
		var center := _to_widget(node.get("position", Vector2.ZERO))
		var ids: Array = by_node[node_id]
		# Single-occupant node: draw at center; multiple: arc around the
		# host party pin so they're individually clickable.
		for i in range(ids.size()):
			var cid: String = str(ids[i])
			var pos: Vector2 = center
			if ids.size() > 1:
				var theta: float = TAU * float(i) / float(ids.size())
				pos = center + Vector2(cos(theta), sin(theta)) * CHARACTER_PIN_RADIAL_OFFSET
			var color: Color = CHARACTER_PIN_COLORS[color_index % CHARACTER_PIN_COLORS.size()]
			color_index += 1
			draw_circle(pos, CHARACTER_PIN_RADIUS + 1, CHARACTER_PIN_OUTLINE)
			draw_circle(pos, CHARACTER_PIN_RADIUS, color)
			_character_pin_screen_positions[cid] = pos


# H.3 (item 2) — character-pin click detection. Uses the screen-position cache
# populated during _draw. Click outside any pin is a no-op (event passes
# through per MOUSE_FILTER_PASS).
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# Hit-test against the pin screen positions; first hit wins.
	for cid in _character_pin_screen_positions.keys():
		var pin_pos: Vector2 = _character_pin_screen_positions[cid]
		if mb.position.distance_to(pin_pos) <= CHARACTER_PIN_RADIUS + 2:
			character_pin_clicked.emit(str(cid))
			accept_event()
			return
