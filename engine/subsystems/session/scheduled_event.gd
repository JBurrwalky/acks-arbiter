class_name ScheduledEvent
extends RefCounted

## A single event scheduled for future resolution by the EventScheduler.
##
## Events are keyed to an absolute game-time timestamp (elapsed rounds from
## Timekeeping). The scheduler pops events in fire_time order, resolving
## ties by priority (lower first), then owner_id (alphabetical).
##
## Priority tiers (per GDD §2.3):
##   0  — Environmental / world (weather, dawn/dusk, season)
##  10  — Scheduled checks (wandering monster rolls, encounter checks)
##  20  — Entity arrivals and completions (travel, search, construction)
##  30  — Triggered consequences (combat start, trap trigger, domain event)


# ---------------------------------------------------------------------------
# Priority tier constants
# ---------------------------------------------------------------------------

const PRIORITY_ENVIRONMENTAL := 0
const PRIORITY_SCHEDULED_CHECK := 10
const PRIORITY_ARRIVAL := 20
const PRIORITY_CONSEQUENCE := 30


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Unique identifier for this event (hex string from CampaignRepository.generate_id).
var event_id: String = ""

## Absolute game time in elapsed rounds when this event fires.
var fire_time: int = 0

## Registered event type string (e.g. "travel_leg", "dungeon_encounter_check").
var event_type: String = ""

## Entity that owns this event (party_id, character_id, domain_id, etc.).
var owner_id: String = ""

## Event-specific payload data.
var data: Dictionary = {}

## Tiebreaker for events at the same fire_time. Lower resolves first.
var priority: int = PRIORITY_ARRIVAL

## Lazily marked true on cancellation (soft delete from queue).
var cancelled: bool = false


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

static func create(
	p_fire_time: int,
	p_event_type: String,
	p_owner_id: String,
	p_data: Dictionary = {},
	p_priority: int = PRIORITY_ARRIVAL
) -> ScheduledEvent:
	var e := ScheduledEvent.new()
	e.event_id = CampaignRepository.generate_id()
	e.fire_time = p_fire_time
	e.event_type = p_event_type
	e.owner_id = p_owner_id
	e.data = p_data
	e.priority = p_priority
	return e


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"fire_time": fire_time,
		"event_type": event_type,
		"owner_id": owner_id,
		"data": data,
		"priority": priority,
		"cancelled": cancelled,
	}


static func from_dict(d: Dictionary) -> ScheduledEvent:
	var e := ScheduledEvent.new()
	e.event_id = d.get("event_id", "")
	e.fire_time = int(d.get("fire_time", 0))
	e.event_type = d.get("event_type", "")
	e.owner_id = d.get("owner_id", "")
	e.data = d.get("data", {})
	e.priority = int(d.get("priority", PRIORITY_ARRIVAL))
	e.cancelled = d.get("cancelled", false)
	return e


# ---------------------------------------------------------------------------
# Comparison (for sorting)
# ---------------------------------------------------------------------------

## Returns true if this event should resolve before [param other].
func is_before(other: ScheduledEvent) -> bool:
	if fire_time != other.fire_time:
		return fire_time < other.fire_time
	if priority != other.priority:
		return priority < other.priority
	return owner_id < other.owner_id
