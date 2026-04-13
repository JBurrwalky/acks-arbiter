class_name LightSourceTracker
extends RefCounted

## Tracks the party's active light source in dungeons.
##
## Manages light type, radius, and remaining duration. Emits notifications
## at warning thresholds (5 turns, 2 turns, expired).
##
## Light sources (ACKS Core):
##   Torch:           30' radius, 6 turns (1 hour)
##   Lantern:         30' radius, 24 turns (4 hours)
##   Continual Light: 30' radius, permanent
##   Infravision:     60' radius, permanent (racial ability)
##   None:            0' radius (darkness)

const LIGHT_SOURCES := {
	"torch": {"radius_feet": 30, "duration_turns": 6, "name": "Torch"},
	"lantern": {"radius_feet": 30, "duration_turns": 24, "name": "Lantern"},
	"continual_light": {"radius_feet": 30, "duration_turns": -1, "name": "Continual Light"},
	"infravision": {"radius_feet": 60, "duration_turns": -1, "name": "Infravision"},
}

const WARNING_THRESHOLDS := [5, 2, 0]

var source_type: String = ""
var radius_feet: int = 0
var remaining_turns: int = 0
var carrier_id: String = ""
var _warned_at: Dictionary = {}  # threshold -> bool


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func activate(light_type: String, p_carrier_id: String = "") -> void:
	if not LIGHT_SOURCES.has(light_type):
		push_error("LightSourceTracker.activate: unknown light type '%s'" % light_type)
		return

	var info: Dictionary = LIGHT_SOURCES[light_type]
	source_type = light_type
	radius_feet = info["radius_feet"]
	remaining_turns = info["duration_turns"]
	carrier_id = p_carrier_id
	_warned_at.clear()


func deactivate() -> void:
	source_type = ""
	radius_feet = 0
	remaining_turns = 0
	carrier_id = ""
	_warned_at.clear()


func is_active() -> bool:
	return not source_type.is_empty()


func is_permanent() -> bool:
	return remaining_turns < 0


func get_radius_cells(cell_size_feet: float = 5.0) -> int:
	## Convert light radius in feet to grid cells.
	if radius_feet <= 0:
		return 0
	return int(float(radius_feet) / cell_size_feet)


func get_display_name() -> String:
	if source_type.is_empty():
		return ""
	return LIGHT_SOURCES.get(source_type, {}).get("name", source_type)


# ---------------------------------------------------------------------------
# Turn tick (called each dungeon turn)
# ---------------------------------------------------------------------------

func tick() -> void:
	## Advance one turn. Checks for warnings and expiration.
	## Should be called once per dungeon turn (10 minutes).
	if not is_active():
		return
	if is_permanent():
		return

	remaining_turns -= 1

	# Check warning thresholds.
	for threshold in WARNING_THRESHOLDS:
		if remaining_turns == threshold and not _warned_at.has(threshold):
			_warned_at[threshold] = true
			_emit_warning(threshold)

	# Expire.
	if remaining_turns <= 0:
		_expire()


# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------

func _emit_warning(turns_left: int) -> void:
	var name_str := get_display_name()
	match turns_left:
		5:
			EventBus.notification_requested.emit({
				"type": "info",
				"category": "light",
				"title": "%s flickering" % name_str,
				"body": "About 50 minutes of light remaining.",
				"duration": 5.0,
			})
		2:
			EventBus.notification_requested.emit({
				"type": "warning",
				"category": "light",
				"title": "%s fading" % name_str,
				"body": "Only 20 minutes of light remaining!",
				"duration": 6.0,
			})
		0:
			EventBus.notification_requested.emit({
				"type": "danger",
				"category": "light",
				"title": "Light source expired!",
				"body": "Your %s has gone out. The party is in darkness." % name_str.to_lower(),
				"duration": 0.0,  # Persist until dismissed.
			})


func _expire() -> void:
	source_type = ""
	radius_feet = 0
	remaining_turns = 0


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"source_type": source_type,
		"radius_feet": radius_feet,
		"remaining_turns": remaining_turns,
		"carrier_id": carrier_id,
	}


func from_dict(data: Dictionary) -> void:
	source_type = data.get("source_type", "")
	radius_feet = data.get("radius_feet", 0)
	remaining_turns = data.get("remaining_turns", 0)
	carrier_id = data.get("carrier_id", "")
	_warned_at.clear()
