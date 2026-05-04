class_name NotificationManager
extends Node

## Manages toast notifications for the player.
##
## Lives as a child of Main (NOT an autoload). Receives requests via
## EventBus.notification_requested and delegates display to NotificationDisplay.
##
## Usage from any subsystem:
##   EventBus.notification_requested.emit({
##       "type": "warning",
##       "category": "light",
##       "title": "Torch flickering",
##       "body": "50 minutes of light remaining.",
##       "duration": 5.0,
##   })

## Maximum visible notifications at once. Excess are queued.
const MAX_VISIBLE := 5

## Default display duration in seconds.
const DEFAULT_DURATION := 4.0

## Category-specific icons (placeholder labels for v1).
const CATEGORY_ICONS := {
	"level_up": "^",
	"light": "*",
	"encumbrance": "#",
	"supply": "~",
	"henchman": "&",
	"quest": "!",
	"combat": "x",
	"system": "i",
}

## Type-specific colors (mapped from UiSurfaceStyles palette).
const TYPE_COLORS := {
	"info": Color(0.20, 0.45, 0.65, 1.0),
	"warning": Color(0.70, 0.55, 0.10, 1.0),
	"danger": Color(0.65, 0.12, 0.08, 1.0),
	"success": Color(0.15, 0.52, 0.20, 1.0),
}

var _display = null  # NotificationDisplay or duck-typed equivalent — set via setup()
var _queue: Array[Dictionary] = []


func _ready() -> void:
	EventBus.notification_requested.connect(_on_notification_requested)
	# Auto-wire common gameplay signals to notifications.
	EventBus.character_leveled_up.connect(_on_character_leveled_up)
	EventBus.henchman_departed.connect(_on_henchman_departed)
	EventBus.loyalty_changed.connect(_on_loyalty_changed)
	# Phase 5: surface loyalty-check outcomes (non-LOYAL) per
	# gdd-ui-architecture.md §6.3 — async outcome surfacing routes through
	# notifications, never a blocking modal.
	EventBus.henchman_loyalty_checked.connect(_on_henchman_loyalty_checked)


func setup(display) -> void:
	_display = display


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Push a notification with validated fields.
func notify(data: Dictionary) -> void:
	var entry := _normalize(data)
	if _display != null and _display.has_method("show_notification"):
		_display.show_notification(entry)
	else:
		_queue.append(entry)


## Flush queued notifications (called by display once ready).
func flush_queue() -> void:
	for entry in _queue:
		if _display != null and _display.has_method("show_notification"):
			_display.show_notification(entry)
	_queue.clear()


## Dismiss all visible notifications matching a category.
func dismiss_category(category: String) -> void:
	if _display != null and _display.has_method("dismiss_category"):
		_display.dismiss_category(category)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_notification_requested(data: Dictionary) -> void:
	notify(data)


func _on_character_leveled_up(character_id: String, new_level: int) -> void:
	var char_data = CampaignRepository.load_character(character_id)
	var name_str: String = char_data.get("name", character_id) if char_data is Dictionary else character_id
	notify({
		"type": "success",
		"category": "level_up",
		"title": "Level Up!",
		"body": "%s has reached level %d." % [name_str, new_level],
		"duration": 6.0,
	})


func _on_henchman_departed(henchman_id: String, departure: Dictionary) -> void:
	var reason: String = departure.get("reason", "unknown")
	notify({
		"type": "warning",
		"category": "henchman",
		"title": "Henchman Departed",
		"body": "A henchman has left the party (%s)." % reason,
		"duration": 5.0,
	})


func _on_loyalty_changed(henchman_id: String, old_score: int, new_score: int) -> void:
	if new_score < old_score and new_score <= -2:
		notify({
			"type": "danger",
			"category": "henchman",
			"title": "Loyalty Critical",
			"body": "A henchman's loyalty has dropped dangerously low.",
			"duration": 5.0,
		})


func _on_henchman_loyalty_checked(henchman_id: String, trigger: String, result: Dictionary) -> void:
	## Surfaces non-LOYAL loyalty-check outcomes as toast notifications.
	## LOYAL / FANATIC outcomes stay silent (the engine state already updates;
	## a positive result doesn't need a player-facing toast).
	## Per acore_equipment.xml §loyalty_results.
	var outcome: String = String(result.get("result", ""))
	if outcome == "" or outcome == "loyal" or outcome == "fanatic":
		return
	var name_str: String = henchman_id
	var char_data = CampaignRepository.load_character(henchman_id)
	if char_data is Dictionary:
		name_str = String((char_data as Dictionary).get("name", henchman_id))
	var trigger_label: String = trigger.replace("_", " ")
	match outcome:
		"hostility":
			notify({
				"type":     "danger",
				"category": "henchman",
				"title":    "Henchman departed (hostility)",
				"body":     "%s left in hostility (%s) — they cannot be re-hired by this character." % [name_str, trigger_label],
				"duration": 7.0,
			})
		"resignation":
			notify({
				"type":     "warning",
				"category": "henchman",
				"title":    "Henchman resigned",
				"body":     "%s resigned (%s). They may be recruited again later." % [name_str, trigger_label],
				"duration": 6.0,
			})
		"grudging":
			notify({
				"type":     "warning",
				"category": "henchman",
				"title":    "Grudging loyalty",
				"body":     "%s stays reluctantly (%s). Improve their treatment before the next check." % [name_str, trigger_label],
				"duration": 6.0,
			})


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _normalize(data: Dictionary) -> Dictionary:
	return {
		"type": data.get("type", "info"),
		"category": data.get("category", "system"),
		"title": data.get("title", ""),
		"body": data.get("body", ""),
		"duration": data.get("duration", DEFAULT_DURATION),
		"action": data.get("action", Callable()),
		"icon": CATEGORY_ICONS.get(data.get("category", "system"), "i"),
		"color": TYPE_COLORS.get(data.get("type", "info"), TYPE_COLORS["info"]),
		"timestamp": Time.get_ticks_msec(),
	}
