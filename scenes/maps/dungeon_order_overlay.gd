extends Node2D

## Visual overlay for pending exploration orders on the dungeon map.
##
## Renders ghost trail dots along queued move paths, a ghost token at
## the destination, and directional arrows for non-move orders.
##
## Child of the dungeon map renderer. Call update_overlays() whenever
## the order manager state changes.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DOT_RADIUS := 2.5
const DOT_COLOR := Color(0.8, 0.8, 1.0, 0.4)
const GHOST_COLOR := Color(0.6, 0.6, 0.9, 0.3)
const GHOST_RADIUS := 8.0
const ARROW_COLOR := Color(0.9, 0.8, 0.3, 0.5)
const ARROW_SIZE := 6.0

const ORDER_ICON_COLORS := {
	"move": Color(0.5, 0.7, 1.0, 0.6),
	"search": Color(1.0, 0.9, 0.3, 0.6),
	"listen": Color(0.7, 1.0, 0.7, 0.6),
	"wait": Color(0.6, 0.6, 0.6, 0.5),
	"interact_door": Color(0.9, 0.6, 0.3, 0.6),
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Cached order data for drawing: Array of {order_type, path, target_pos, entity_id}
var _draw_data: Array = []


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the overlay with the current set of pending orders.
## [param orders]: Dictionary from DungeonOrderManager.get_all_orders()
##   { entity_id -> { order_type, target_pos, path } }
func update_overlays(orders: Dictionary) -> void:
	_draw_data.clear()
	for eid in orders:
		var order: Dictionary = orders[eid]
		_draw_data.append({
			"entity_id": eid,
			"order_type": order.get("order_type", ""),
			"target_pos": order.get("target_pos", Vector2i(-1, -1)),
			"path": order.get("path", []),
		})
	queue_redraw()


## Clear all overlay graphics.
func clear_overlays() -> void:
	_draw_data.clear()
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	for entry in _draw_data:
		var order_type: String = entry["order_type"]
		var target_pos: Vector2i = entry["target_pos"]
		var path: Array = entry["path"]

		match order_type:
			"move":
				_draw_move_path(path, target_pos)
			"search", "listen", "wait", "interact_door":
				_draw_order_icon(target_pos, order_type)


func _draw_move_path(path: Array, target_pos: Vector2i) -> void:
	# Draw dots along the path
	for i in range(path.size()):
		var cell: Vector2i = path[i]
		var screen := IsometricGrid.cell_to_screen(cell.x, cell.y)
		# Intermediate waypoints get small dots
		if i < path.size() - 1:
			draw_circle(screen, DOT_RADIUS, DOT_COLOR)
		else:
			# Destination: ghost circle
			draw_circle(screen, GHOST_RADIUS, GHOST_COLOR)
			draw_arc(screen, GHOST_RADIUS, 0.0, TAU, 16,
				Color(GHOST_COLOR.r, GHOST_COLOR.g, GHOST_COLOR.b, 0.6), 1.5)

	# Draw connecting lines between path dots (subtle)
	if path.size() >= 2:
		for i in range(path.size() - 1):
			var from_screen := IsometricGrid.cell_to_screen(path[i].x, path[i].y)
			var to_screen := IsometricGrid.cell_to_screen(path[i + 1].x, path[i + 1].y)
			draw_line(from_screen, to_screen, Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, 0.2), 1.0)


func _draw_order_icon(pos: Vector2i, order_type: String) -> void:
	if pos == Vector2i(-1, -1):
		return
	var screen := IsometricGrid.cell_to_screen(pos.x, pos.y)
	var color: Color = ORDER_ICON_COLORS.get(order_type, ARROW_COLOR)

	match order_type:
		"search":
			# Magnifying glass icon: circle + line
			draw_arc(screen + Vector2(-3, -3), 4.0, 0.0, TAU, 12, color, 1.5)
			draw_line(screen + Vector2(0, 0), screen + Vector2(4, 4), color, 1.5)
		"listen":
			# Ear icon: arc
			draw_arc(screen, 5.0, -PI * 0.6, PI * 0.6, 8, color, 2.0)
			draw_arc(screen, 3.0, -PI * 0.4, PI * 0.4, 6, color, 1.5)
		"wait":
			# Clock icon: circle + hands
			draw_arc(screen, 5.0, 0.0, TAU, 12, color, 1.5)
			draw_line(screen, screen + Vector2(0, -4), color, 1.5)
			draw_line(screen, screen + Vector2(3, 0), color, 1.5)
		"interact_door":
			# Door icon: rectangle
			draw_rect(Rect2(screen + Vector2(-3, -5), Vector2(6, 10)), color, false, 1.5)
			draw_circle(screen + Vector2(2, 0), 1.0, color)
