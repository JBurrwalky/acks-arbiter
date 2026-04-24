class_name ShieldShapeRegistry
extends RefCounted

## Shield shapes are code-defined silhouette polygons in normalized coords
## (0,0) top-left to (1,1) bottom-right. The renderer draws each silhouette
## directly as a Polygon2D fill and a closed Line2D outline.
##
## Seven v1 shapes: heater, kite, round, norman, tower, horsehead, swiss.
## Each polygon winds CCW starting near the top-left and is authored to read
## well at the 64-px hex-map token size while still looking correct at the
## 256-px editor preview size.

# ---------------------------------------------------------------------------
# Polygon silhouettes
# ---------------------------------------------------------------------------

## Classic heater — flat shoulders, tapering to a single point.
const _HEATER_POLYGON: Array = [
	Vector2(0.05, 0.02),
	Vector2(0.95, 0.02),
	Vector2(0.96, 0.35),
	Vector2(0.90, 0.58),
	Vector2(0.78, 0.80),
	Vector2(0.58, 0.94),
	Vector2(0.50, 0.98),
	Vector2(0.42, 0.94),
	Vector2(0.22, 0.80),
	Vector2(0.10, 0.58),
	Vector2(0.04, 0.35),
]

## Kite — Norman-era elongated teardrop with rounded top, sharp lower point.
const _KITE_POLYGON: Array = [
	Vector2(0.32, 0.04),
	Vector2(0.42, 0.01),
	Vector2(0.50, 0.00),
	Vector2(0.58, 0.01),
	Vector2(0.68, 0.04),
	Vector2(0.82, 0.14),
	Vector2(0.93, 0.32),
	Vector2(0.96, 0.50),
	Vector2(0.88, 0.72),
	Vector2(0.70, 0.88),
	Vector2(0.55, 0.97),
	Vector2(0.50, 1.00),
	Vector2(0.45, 0.97),
	Vector2(0.30, 0.88),
	Vector2(0.12, 0.72),
	Vector2(0.04, 0.50),
	Vector2(0.07, 0.32),
	Vector2(0.18, 0.14),
]

## Round — circle approximated with 16 evenly-spaced points.
const _ROUND_POLYGON: Array = [
	Vector2(0.500, 0.020),
	Vector2(0.684, 0.057),
	Vector2(0.839, 0.161),
	Vector2(0.943, 0.316),
	Vector2(0.980, 0.500),
	Vector2(0.943, 0.684),
	Vector2(0.839, 0.839),
	Vector2(0.684, 0.943),
	Vector2(0.500, 0.980),
	Vector2(0.316, 0.943),
	Vector2(0.161, 0.839),
	Vector2(0.057, 0.684),
	Vector2(0.020, 0.500),
	Vector2(0.057, 0.316),
	Vector2(0.161, 0.161),
	Vector2(0.316, 0.057),
]

## Norman — rounded-top shield, between heater and kite in proportion.
const _NORMAN_POLYGON: Array = [
	Vector2(0.25, 0.03),
	Vector2(0.40, 0.00),
	Vector2(0.50, 0.00),
	Vector2(0.60, 0.00),
	Vector2(0.75, 0.03),
	Vector2(0.88, 0.12),
	Vector2(0.95, 0.28),
	Vector2(0.95, 0.52),
	Vector2(0.86, 0.72),
	Vector2(0.66, 0.89),
	Vector2(0.50, 0.98),
	Vector2(0.34, 0.89),
	Vector2(0.14, 0.72),
	Vector2(0.05, 0.52),
	Vector2(0.05, 0.28),
	Vector2(0.12, 0.12),
]

## Tower — tall, square-shouldered shield with rounded corners. Scutum-like.
const _TOWER_POLYGON: Array = [
	Vector2(0.10, 0.03),
	Vector2(0.50, 0.00),
	Vector2(0.90, 0.03),
	Vector2(0.97, 0.10),
	Vector2(0.98, 0.50),
	Vector2(0.97, 0.90),
	Vector2(0.90, 0.97),
	Vector2(0.50, 1.00),
	Vector2(0.10, 0.97),
	Vector2(0.03, 0.90),
	Vector2(0.02, 0.50),
	Vector2(0.03, 0.10),
]

## Horsehead (Italian) — hourglass with pinched neck and rounded lower bowl.
const _HORSEHEAD_POLYGON: Array = [
	Vector2(0.08, 0.02),
	Vector2(0.92, 0.02),
	Vector2(0.96, 0.20),
	Vector2(0.82, 0.36),
	Vector2(0.68, 0.48),
	Vector2(0.68, 0.56),
	Vector2(0.80, 0.68),
	Vector2(0.92, 0.82),
	Vector2(0.82, 0.94),
	Vector2(0.50, 0.99),
	Vector2(0.18, 0.94),
	Vector2(0.08, 0.82),
	Vector2(0.20, 0.68),
	Vector2(0.32, 0.56),
	Vector2(0.32, 0.48),
	Vector2(0.18, 0.36),
	Vector2(0.04, 0.20),
]

## Swiss — heater body with stylized double-lobed top (center dip between peaks).
const _SWISS_POLYGON: Array = [
	Vector2(0.05, 0.05),
	Vector2(0.14, 0.01),
	Vector2(0.22, 0.00),
	Vector2(0.34, 0.06),
	Vector2(0.42, 0.10),
	Vector2(0.50, 0.13),
	Vector2(0.58, 0.10),
	Vector2(0.66, 0.06),
	Vector2(0.78, 0.00),
	Vector2(0.86, 0.01),
	Vector2(0.95, 0.05),
	Vector2(0.96, 0.35),
	Vector2(0.90, 0.58),
	Vector2(0.78, 0.80),
	Vector2(0.58, 0.94),
	Vector2(0.50, 0.98),
	Vector2(0.42, 0.94),
	Vector2(0.22, 0.80),
	Vector2(0.10, 0.58),
	Vector2(0.04, 0.35),
]

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

## Ordered insertion — determines display order in the shape picker.
const SHAPES := {
	"heater":    {"display_name": "Heater",    "polygon": _HEATER_POLYGON},
	"kite":      {"display_name": "Kite",      "polygon": _KITE_POLYGON},
	"round":     {"display_name": "Round",     "polygon": _ROUND_POLYGON},
	"norman":    {"display_name": "Norman",    "polygon": _NORMAN_POLYGON},
	"tower":     {"display_name": "Tower",     "polygon": _TOWER_POLYGON},
	"horsehead": {"display_name": "Horsehead", "polygon": _HORSEHEAD_POLYGON},
	"swiss":     {"display_name": "Swiss",     "polygon": _SWISS_POLYGON},
}


func _init() -> void:
	pass


func get_shape(shape_id: String) -> Dictionary:
	var entry = SHAPES.get(shape_id, null)
	if entry == null:
		return {}
	var result: Dictionary = entry.duplicate(true)
	result["shape_id"] = shape_id
	return result


func has_shape(shape_id: String) -> bool:
	return SHAPES.has(shape_id)


func get_polygon(shape_id: String) -> Array:
	var entry = SHAPES.get(shape_id, null)
	if entry == null:
		return []
	return entry.get("polygon", [])


func get_all_shape_ids() -> Array[String]:
	var out: Array[String] = []
	for k in SHAPES.keys():
		out.append(k)
	return out


func get_all_shapes() -> Array:
	var out: Array = []
	for k in SHAPES.keys():
		out.append(get_shape(k))
	return out


func get_shape_count() -> int:
	return SHAPES.size()
