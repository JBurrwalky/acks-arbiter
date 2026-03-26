class_name EventPayload
extends RefCounted

## Generic payload for game events (domain events, exploration events, etc.).
## Passed via EventBus signals that carry structured event data.

var event_type: String = ""     # "domain_event" | "encounter_triggered" | "character_leveled" etc.
var source_id: String = ""      # entity that caused the event
var target_id: String = ""      # entity affected ("" if none)
var data: Dictionary = {}       # event-type-specific fields
var game_day: int = 0           # campaign calendar day
var game_round: int = 0         # 0 if not in combat


static func from_dict(d: Dictionary) -> EventPayload:
	var e := EventPayload.new()
	e.event_type = d.get("event_type", "")
	e.source_id = d.get("source_id", "")
	e.target_id = d.get("target_id", "")
	e.data = d.get("data", {})
	e.game_day = d.get("game_day", 0)
	e.game_round = d.get("game_round", 0)
	return e
