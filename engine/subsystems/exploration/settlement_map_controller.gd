class_name SettlementMapController
extends Node

## Per-party settlement context: tracks which PoI / district the party is at.
##
## V2 (2026-05-02). The prior controller managed party movement on a street
## graph with AStar2D pathfinding. With the V2 settlement UI ([gdd-settlement-
## exploration-ui.md] §5), travel is fixed-cost between PoI ids; spatial
## position is no longer modeled. This class is now a thin context object.
##
## The class name SettlementMapController is preserved for callsite stability;
## the "_map_" segment is historical. Conceptually this is now SettlementContext.
##
## NOT an autoload. Instantiate dynamically when entering a settlement.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal map_loaded(settlement_id: String)
signal current_poi_changed(poi_id: String)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _settlement_id: String = ""
var _map: SettlementMapData
var _current_poi_id: String = ""


# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

## Loads a settlement from a parsed dictionary and positions the party at
## [param entry_poi_id]. If entry_poi_id is empty, falls back to the first
## entry/exit PoI; if none exist, falls back to the first PoI of the first
## district.
func load_settlement(settlement_dict: Dictionary, entry_poi_id: String = "") -> void:
	_map = SettlementMapData.from_dict(settlement_dict)
	_settlement_id = _map.id

	if not entry_poi_id.is_empty() and not _map.get_poi(entry_poi_id).is_empty():
		_current_poi_id = entry_poi_id
	else:
		_current_poi_id = _pick_default_entry_poi_id()

	map_loaded.emit(_settlement_id)

	var district_id: String = ""
	var current_poi := _map.get_poi(_current_poi_id)
	if not current_poi.is_empty():
		district_id = current_poi.get("district_id", "")
	EventBus.settlement_entered.emit(_settlement_id, district_id)


## Updates the party's current PoI. Emits current_poi_changed if the value
## actually changes and the new id is valid.
func set_current_poi(poi_id: String) -> void:
	if _map == null:
		return
	if poi_id == _current_poi_id:
		return
	if _map.get_poi(poi_id).is_empty():
		push_error("SettlementMapController.set_current_poi: unknown poi_id '%s'" % poi_id)
		return
	_current_poi_id = poi_id
	current_poi_changed.emit(poi_id)


## Returns the party's current PoI dict, or {} if not loaded.
func get_current_poi() -> Dictionary:
	if _map == null:
		return {}
	return _map.get_poi(_current_poi_id)


## Returns the party's current district dict, or {} if not loaded.
func get_current_district() -> Dictionary:
	var poi := get_current_poi()
	if poi.is_empty() or _map == null:
		return {}
	return _map.get_district(poi.get("district_id", ""))


## Returns the current PoI id (empty string if not loaded).
func get_current_poi_id() -> String:
	return _current_poi_id


## Returns the current district id (empty string if not loaded).
func get_current_district_id() -> String:
	var poi := get_current_poi()
	return poi.get("district_id", "")


## Returns the current SettlementMapData, or null if not loaded.
func get_map() -> SettlementMapData:
	return _map


## Returns the current settlement id.
func get_settlement_id() -> String:
	return _settlement_id


## Returns true if the party's current PoI is flagged is_entry_exit.
func is_at_entry_exit() -> bool:
	var poi := get_current_poi()
	return poi.get("is_entry_exit", false)


## Returns true if [param poi_id] shares a district with the current PoI.
func same_district_as_current(poi_id: String) -> bool:
	if _map == null or _current_poi_id.is_empty():
		return false
	return _map.same_district(_current_poi_id, poi_id)


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _pick_default_entry_poi_id() -> String:
	if _map == null:
		return ""
	var entry_pois: Array = _map.get_entry_exit_pois()
	if not entry_pois.is_empty():
		return entry_pois[0].get("id", "")
	if not _map.pois.is_empty():
		return _map.pois[0].get("id", "")
	return ""
