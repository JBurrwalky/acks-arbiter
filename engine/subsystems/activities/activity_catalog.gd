class_name ActivityCatalog
extends RefCounted

## Registry of RAW activity definitions loaded from data/activities/*.json.
##
## Loads once at construction; provides lookups by id, category, location, and
## remote-capability. The catalog is data-only — execution semantics live in
## ActivityTimeCostExecutor and the per-activity handlers.
##
## See:
##   - data/activities/domain_category.json (Phase 3)
##   - rules/ax_campaign_play.xml §domain L502-729
##   - gdd-realtime-scheduler.md §4.8 (activity execution model)
##   - gdd-domain-tab.md §11 (Decrees & Remote Orders sub-tab)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTIVITIES_RES_PATH := "res://data/activities/"

## Per gdd-domain-tab.md §11.1 — the small set of activities surfaced in the
## Domain tab's Decrees & Remote Orders sub-tab. All other activities launch
## from their location surfaces.
const REMOTE_CAPABLE_DOMAIN_IDS: Array = [
	"administer_domain",
	"issue_decree",
	"manage_henchmen",
	"conscript_troops",
	"levy_militia",
	"solicit_mercenaries",
	"call_to_arms",
	"oversee_investment",
]


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

## { activity_id (String) : definition (Dictionary) }
var _by_id: Dictionary = {}

## { category (String) : Array[String] of ids }
var _by_category: Dictionary = {}


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _init() -> void:
	_load_all()


## Reload all catalog files. Useful for tests that swap fixtures in.
func reload() -> void:
	_by_id.clear()
	_by_category.clear()
	_load_all()


# ---------------------------------------------------------------------------
# Public lookups
# ---------------------------------------------------------------------------

## Returns the definition Dict for [param activity_def_id], or empty Dict if
## not found.
func get_definition(activity_def_id: String) -> Dictionary:
	return _by_id.get(activity_def_id, {})


## Returns true if the catalog knows about [param activity_def_id].
func has_definition(activity_def_id: String) -> bool:
	return _by_id.has(activity_def_id)


## Returns all activity ids in [param category] (e.g. "domain", "magical").
func list_by_category(category: String) -> Array:
	return (_by_category.get(category, []) as Array).duplicate()


## Returns all activity ids whose location_kind matches [param location_kind].
func list_by_location_kind(location_kind: String) -> Array:
	var result: Array = []
	for id: String in _by_id:
		if String(_by_id[id].get("location_kind", "anywhere")) == location_kind:
			result.append(id)
	return result


## Returns the canonical 8-activity set surfaced on Decrees & Remote Orders
## per gdd-domain-tab.md §11.1.
func get_remote_capable_ids() -> Array:
	return REMOTE_CAPABLE_DOMAIN_IDS.duplicate()


## All known activity ids across all categories. Order is insertion order.
func all_ids() -> Array:
	return _by_id.keys()


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

func _load_all() -> void:
	var dir := DirAccess.open(ACTIVITIES_RES_PATH)
	if dir == null:
		push_error("ActivityCatalog: cannot open %s" % ACTIVITIES_RES_PATH)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			_load_file(ACTIVITIES_RES_PATH + fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _load_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ActivityCatalog: empty file %s" % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("ActivityCatalog: malformed JSON %s" % path)
		return
	var activities: Variant = (parsed as Dictionary).get("activities", [])
	if not (activities is Array):
		return
	for entry: Variant in activities:
		if not (entry is Dictionary):
			continue
		var def: Dictionary = entry as Dictionary
		var id: String = String(def.get("id", ""))
		if id.is_empty():
			continue
		_by_id[id] = def
		var category: String = String(def.get("category", "uncategorized"))
		if not _by_category.has(category):
			_by_category[category] = []
		(_by_category[category] as Array).append(id)
