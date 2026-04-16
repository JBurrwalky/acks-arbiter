class_name GameLog
extends RefCounted

## GameLog — session-wide structured record of all game events.
##
## Stores entries from every subsystem (exploration, combat, character, etc.)
## as Dictionaries with category, type, summary, and raw signal data.
## Provides query, filter, and export methods for the GameLogPanel UI.
##
## In-memory only; cleared on session end. Export to JSON/TXT on demand.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## All valid entry categories.
const CATEGORIES := [
	"combat", "exploration", "character", "inventory", "party", "henchman",
	"magic", "domain", "scheduler", "session", "time", "dice", "reputation",
	"creature", "override", "narration",
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _entries: Array = []
var _next_id: int = 0


# ---------------------------------------------------------------------------
# Write API
# ---------------------------------------------------------------------------

func add_entry(
		category: String,
		type: String,
		summary: String,
		actor_id: String = "",
		target_id: String = "",
		data: Dictionary = {}) -> Dictionary:
	## Append a new log entry. Returns the created entry dictionary.
	var game_time: int = 0
	var tk := _get_timekeeping()
	if tk != null:
		# Timekeeping._elapsed_rounds is the canonical clock.
		# No public getter exists, but GDScript field access works.
		game_time = tk._elapsed_rounds

	var entry := {
		"id":        _next_id,
		"timestamp": Time.get_ticks_msec(),
		"game_time": game_time,
		"category":  category,
		"type":      type,
		"summary":   summary,
		"actor_id":  actor_id,
		"target_id": target_id,
		"data":      data,
	}
	_entries.append(entry)
	_next_id += 1
	return entry


# ---------------------------------------------------------------------------
# Read API
# ---------------------------------------------------------------------------

func get_all_entries() -> Array:
	return _entries.duplicate()


func get_entries_by_category(category: String) -> Array:
	var result: Array = []
	for entry in _entries:
		if entry["category"] == category:
			result.append(entry)
	return result


func get_entries_by_type(type: String) -> Array:
	var result: Array = []
	for entry in _entries:
		if entry["type"] == type:
			result.append(entry)
	return result


func get_entries_for_entity(entity_id: String) -> Array:
	var result: Array = []
	for entry in _entries:
		if entry["actor_id"] == entity_id or entry["target_id"] == entity_id:
			result.append(entry)
	return result


func get_entries_in_time_range(from_game_time: int, to_game_time: int) -> Array:
	var result: Array = []
	for entry in _entries:
		var gt: int = entry["game_time"]
		if gt >= from_game_time and gt <= to_game_time:
			result.append(entry)
	return result


func get_recent(count: int) -> Array:
	if count >= _entries.size():
		return _entries.duplicate()
	return _entries.slice(_entries.size() - count)


func entry_count() -> int:
	return _entries.size()


# ---------------------------------------------------------------------------
# Export API
# ---------------------------------------------------------------------------

func to_json_string() -> String:
	## Returns all entries as a JSON string with game_time_formatted added.
	var export_entries: Array = []
	for entry in _entries:
		var copy: Dictionary = entry.duplicate()
		copy["game_time_formatted"] = _format_game_time(entry["game_time"])
		export_entries.append(copy)
	return JSON.stringify(export_entries, "\t")


func to_text_string() -> String:
	## Returns a human-readable text log, one line per entry.
	var lines: PackedStringArray = PackedStringArray()
	for entry in _entries:
		var time_str := _format_game_time(entry["game_time"])
		lines.append("[%s] %s" % [time_str, entry["summary"]])
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func clear() -> void:
	_entries.clear()
	_next_id = 0


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _format_game_time(elapsed_rounds: int) -> String:
	## Converts elapsed rounds into a human-readable date/time string.
	## Uses the same calendar constants as Timekeeping.
	const ROUNDS_PER_MINUTE := 6
	const ROUNDS_PER_HOUR := 360
	const ROUNDS_PER_DAY := 8640
	const DAYS_PER_MONTH := 28
	const MONTHS_PER_YEAR := 13

	var total_days := elapsed_rounds / ROUNDS_PER_DAY
	var hour := (elapsed_rounds % ROUNDS_PER_DAY) / ROUNDS_PER_HOUR
	var minute := (elapsed_rounds % ROUNDS_PER_HOUR) / ROUNDS_PER_MINUTE

	var year := (total_days / (DAYS_PER_MONTH * MONTHS_PER_YEAR)) + 1
	var day_of_year := total_days % (DAYS_PER_MONTH * MONTHS_PER_YEAR)
	var month := (day_of_year / DAYS_PER_MONTH) + 1
	var day := (day_of_year % DAYS_PER_MONTH) + 1

	return "Y%d M%d D%d %02d:%02d" % [year, month, day, hour, minute]


static func _get_timekeeping() -> Node:
	## Safely access the Timekeeping autoload.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if not tree.root.has_node("Timekeeping"):
		return null
	return tree.root.get_node("Timekeeping")
