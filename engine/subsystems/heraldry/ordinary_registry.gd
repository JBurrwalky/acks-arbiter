class_name OrdinaryRegistry
extends RefCounted

## Code-defined registry of ordinaries (overlay shapes drawn over the field).
## All geometry in normalized shield coordinates: (0,0) top-left, (1,1) bottom-right.
##
## render_type:
##   "filled" — polygons filled with tincture_ordinary (cross, chevron, chief).
##   "border" — stroked outline inset by border_inset_ratio (bordure).

const ORDINARIES := {
	"cross": {
		"display_name": "Cross",
		"render_type": "filled",
		"polygons": [
			[Vector2(0.4, 0.0), Vector2(0.6, 0.0), Vector2(0.6, 1.0), Vector2(0.4, 1.0)],
			[Vector2(0.0, 0.4), Vector2(1.0, 0.4), Vector2(1.0, 0.6), Vector2(0.0, 0.6)],
		],
	},
	"chevron": {
		"display_name": "Chevron",
		"render_type": "filled",
		"polygons": [
			[
				Vector2(0.0, 0.85),
				Vector2(0.5, 0.35),
				Vector2(1.0, 0.85),
				Vector2(1.0, 1.0),
				Vector2(0.5, 0.5),
				Vector2(0.0, 1.0),
			],
		],
	},
	"chief": {
		"display_name": "Chief",
		"render_type": "filled",
		"polygons": [
			[Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.28), Vector2(0.0, 0.28)],
		],
	},
	"bordure": {
		"display_name": "Bordure",
		"render_type": "border",
		"border_inset_ratio": 0.08,
		"polygons": [],
	},
}


static func get_ordinary(ordinary_id: String) -> Dictionary:
	return ORDINARIES.get(ordinary_id, {})


static func has_ordinary(ordinary_id: String) -> bool:
	return ORDINARIES.has(ordinary_id)


static func get_all_ordinary_ids() -> Array[String]:
	var out: Array[String] = []
	for k in ORDINARIES.keys():
		out.append(k)
	return out


static func get_all_ordinaries() -> Array:
	var out: Array = []
	for k in ORDINARIES.keys():
		var entry: Dictionary = ORDINARIES[k].duplicate(true)
		entry["ordinary_id"] = k
		out.append(entry)
	return out


static func ordinary_count() -> int:
	return ORDINARIES.size()
