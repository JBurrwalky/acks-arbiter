class_name FieldDivisionRegistry
extends RefCounted

## Code-defined registry of field divisions. Each division supplies the
## polygons for the SECONDARY tincture region in normalized shield
## coordinates: (0,0) = top-left, (1,1) = bottom-right of the shield's
## bounding box. The renderer fills the entire shield with tincture_primary
## first, then paints secondary_polygons over it with tincture_secondary.

const DIVISIONS := {
	"plain": {
		"display_name": "Plain",
		"secondary_polygons": [],
	},
	"per_pale": {
		"display_name": "Per Pale",
		"secondary_polygons": [
			[Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.5, 1.0)],
		],
	},
	"per_fess": {
		"display_name": "Per Fess",
		"secondary_polygons": [
			[Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(1.0, 1.0), Vector2(0.0, 1.0)],
		],
	},
	"per_bend": {
		"display_name": "Per Bend",
		"secondary_polygons": [
			[Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0)],
		],
	},
	"quarterly": {
		"display_name": "Quarterly",
		"secondary_polygons": [
			[Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.5), Vector2(0.5, 0.5)],
			[Vector2(0.0, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 1.0), Vector2(0.0, 1.0)],
		],
	},
	"per_saltire": {
		"display_name": "Per Saltire",
		"secondary_polygons": [
			[Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(0.0, 1.0)],
			[Vector2(1.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 1.0)],
		],
	},
}


static func get_division(division_id: String) -> Dictionary:
	return DIVISIONS.get(division_id, {})


static func has_division(division_id: String) -> bool:
	return DIVISIONS.has(division_id)


static func get_all_division_ids() -> Array[String]:
	var out: Array[String] = []
	for k in DIVISIONS.keys():
		out.append(k)
	return out


static func get_all_divisions() -> Array:
	## Returns entries with division_id stamped into each dict for UI consumption.
	var out: Array = []
	for k in DIVISIONS.keys():
		var entry: Dictionary = DIVISIONS[k].duplicate(true)
		entry["division_id"] = k
		out.append(entry)
	return out


static func division_count() -> int:
	return DIVISIONS.size()
