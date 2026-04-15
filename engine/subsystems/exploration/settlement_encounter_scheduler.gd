class_name SettlementEncounterScheduler
extends RefCounted

## Schedules urban encounter check events during city travel.
##
## Per gdd-settlement-exploration-ui.md §6.2, encounter checks are TIME-BASED
## (not per-block). Frequency depends on time of day and route type:
##
##   | Context                     | Interval        |
##   |-----------------------------|-----------------|
##   | Streets by day              | Every 6 turns   |
##   | Streets by night            | Every 3 turns   |
##   | Alleys by day               | Every 3 turns   |
##   | Alleys by night             | Every 1 turn    |
##
## Encounter fires on: 6+ on 1d6 (normal) or 5+ on 1d6 (Looking for Trouble).
##
## For mixed routes (some street segments + some alley segments), the most
## frequent applicable interval is used for the entire travel duration.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Encounter check intervals in rounds.
const INTERVAL_STREETS_DAY := 360     ## 6 turns × 60 rounds
const INTERVAL_STREETS_NIGHT := 180   ## 3 turns × 60 rounds
const INTERVAL_ALLEYS_DAY := 180      ## 3 turns × 60 rounds
const INTERVAL_ALLEYS_NIGHT := 60     ## 1 turn × 60 rounds

## Encounter thresholds on 1d6.
const THRESHOLD_NORMAL := 6           ## Encounter on 6+
const THRESHOLD_TROUBLE := 5          ## Encounter on 5+ (Looking for Trouble)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Schedules encounter check events during a city travel segment.
##
## Parameters:
##   scheduler: EventScheduler to schedule events on
##   party_id: party that owns these events
##   start_time: round when travel begins
##   travel_rounds: total travel duration in rounds
##   has_alleys: whether the route includes any alley-type edges
##   is_night: whether it's currently nighttime
##   looking_for_trouble: whether the Looking for Trouble toggle is active
##   settlement_id: for encounter table lookup
##   district_id: for district-specific encounter modifiers
##
## Returns: Array of event IDs (for cancellation if travel is interrupted).
static func schedule_encounter_checks(
	scheduler: EventScheduler,
	party_id: String,
	start_time: int,
	travel_rounds: int,
	has_alleys: bool,
	is_night: bool,
	looking_for_trouble: bool,
	settlement_id: String = "",
	district_id: String = "",
) -> Array[String]:
	var interval := _get_interval(has_alleys, is_night)
	var threshold := THRESHOLD_TROUBLE if looking_for_trouble else THRESHOLD_NORMAL

	var event_ids: Array[String] = []
	var check_time: int = start_time + interval

	while check_time <= start_time + travel_rounds:
		var event_id := scheduler.schedule_at(
			check_time,
			"city_encounter_check",
			party_id,
			{
				"threshold": threshold,
				"is_night": is_night,
				"has_alleys": has_alleys,
				"settlement_id": settlement_id,
				"district_id": district_id,
				"looking_for_trouble": looking_for_trouble,
			},
			ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
		)
		event_ids.append(event_id)
		check_time += interval

	return event_ids


## Returns the applicable encounter check interval in rounds.
## Uses the most frequent (shortest) interval that applies.
static func _get_interval(has_alleys: bool, is_night: bool) -> int:
	if has_alleys and is_night:
		return INTERVAL_ALLEYS_NIGHT
	elif has_alleys or is_night:
		# Alleys by day OR streets by night: both are 3-turn intervals.
		if has_alleys:
			return INTERVAL_ALLEYS_DAY
		else:
			return INTERVAL_STREETS_NIGHT
	else:
		return INTERVAL_STREETS_DAY


## Returns the encounter check interval for a given context (for display in UI).
static func get_interval_for_context(has_alleys: bool, is_night: bool) -> int:
	return _get_interval(has_alleys, is_night)
