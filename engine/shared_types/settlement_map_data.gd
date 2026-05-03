class_name SettlementMapData
extends RefCounted

## Settlement logical structure: districts and the PoIs within them.
##
## V2 (2026-05-02) is non-spatial — no street graph, no block polygons, no walls,
## no water features. Travel between PoIs is fixed-cost (1 turn intra-district,
## 1 hour cross-district) per gdd-settlement-exploration-ui.md v2 §5.1; PoIs
## are addressed by id, not by graph node.
##
## This type is NOT an autoload. Instantiate via from_dict() or load_from_file().
## Data format matches gdd-settlement-layout.md v2 §8 (slim SettlementData).
##
## The class name SettlementMapData is preserved (not renamed to SettlementData)
## to keep the file path stable for callers; the "_map_" segment is now historical.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var id: String = ""
var name: String = ""
var market_class: int = 6
var population_families: int = 0
var terrain_context: String = "crossroads"
var generation_seed: int = 0
var culture_id: String = ""

## Districts. Each: {id: String, name: String, type: String,
##   encounter_modifier: String, pois: Array[Dictionary]}
var districts: Array = []

## Flat list of all PoIs across every district (built from districts[].pois on parse).
## Each: {id: String, name: String, type: String, subtype: String,
##   district_id: String, is_entry_exit: bool, importance: String, label: Variant}
var pois: Array = []

## Cross-layer PoI references (undercity / upper-tier) for narrative use.
## Each: {layer: String, poi_id: String, name: String, type: String}
var undercity_pois: Array = []

## Surface ↔ undercity transition records.
var transitions: Array = []


# ---------------------------------------------------------------------------
# Internal lookup tables (built by from_dict)
# ---------------------------------------------------------------------------

var _poi_lookup: Dictionary = {}       ## poi_id (String) → POI dict
var _district_lookup: Dictionary = {}  ## district_id (String) → district dict


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

## Builds a SettlementMapData from a parsed JSON dictionary.
static func from_dict(data: Dictionary) -> SettlementMapData:
	var m := SettlementMapData.new()
	m.id = data.get("id", "")
	m.name = data.get("name", "")
	m.market_class = int(data.get("market_class", 6))
	m.population_families = int(data.get("population_families", 0))
	m.terrain_context = data.get("terrain_context", "crossroads")
	m.generation_seed = int(data.get("generation_seed", 0))
	m.culture_id = data.get("culture_id", "")

	for d in data.get("districts", []):
		var dist: Dictionary = {}
		dist["id"] = d.get("id", "")
		dist["name"] = d.get("name", "")
		dist["type"] = d.get("type", "village_center")
		dist["encounter_modifier"] = d.get("encounter_modifier", "default")

		var dist_pois: Array = []
		for p in d.get("pois", []):
			var poi: Dictionary = {}
			poi["id"] = p.get("id", "")
			poi["name"] = p.get("name", "")
			poi["type"] = p.get("type", "")
			poi["subtype"] = p.get("subtype", "")
			poi["district_id"] = dist["id"]
			poi["is_entry_exit"] = bool(p.get("is_entry_exit", false))
			poi["importance"] = p.get("importance", "minor")
			poi["label"] = p.get("label", null)
			dist_pois.append(poi)
			m.pois.append(poi)
			m._poi_lookup[poi["id"]] = poi

		dist["pois"] = dist_pois
		m.districts.append(dist)
		m._district_lookup[dist["id"]] = dist

	for u in data.get("undercity_pois", []):
		m.undercity_pois.append(u.duplicate())
	for t in data.get("transitions", []):
		m.transitions.append(t.duplicate())

	return m


## Loads from a JSON file at the given path.
static func load_from_file(path: String) -> SettlementMapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SettlementMapData.load_from_file: cannot open '%s'" % path)
		return null
	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		push_error("SettlementMapData.load_from_file: JSON parse failed for '%s'" % path)
		return null
	return from_dict(parsed)


# ---------------------------------------------------------------------------
# Queries — PoIs
# ---------------------------------------------------------------------------

## Returns the POI dict with the given id, or {} if not found.
func get_poi(poi_id: String) -> Dictionary:
	return _poi_lookup.get(poi_id, {})


## Returns all POIs in the given district (in declaration order).
func get_pois_in_district(district_id: String) -> Array:
	var d: Dictionary = _district_lookup.get(district_id, {})
	if d.is_empty():
		return []
	return d.get("pois", [])


## Returns all PoIs flagged is_entry_exit: true.
func get_entry_exit_pois() -> Array:
	var result: Array = []
	for poi in pois:
		if poi.get("is_entry_exit", false):
			result.append(poi)
	return result


# ---------------------------------------------------------------------------
# Queries — Districts
# ---------------------------------------------------------------------------

## Returns the district dict for [param district_id], or {} if not found.
func get_district(district_id: String) -> Dictionary:
	return _district_lookup.get(district_id, {})


## Returns true if the two PoI ids exist and share the same district.
## False if either id is unknown.
func same_district(poi_a_id: String, poi_b_id: String) -> bool:
	var a: Dictionary = _poi_lookup.get(poi_a_id, {})
	var b: Dictionary = _poi_lookup.get(poi_b_id, {})
	if a.is_empty() or b.is_empty():
		return false
	return a.get("district_id", "") == b.get("district_id", "")
