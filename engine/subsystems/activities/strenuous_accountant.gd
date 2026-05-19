class_name StrenuousAccountant
extends RefCounted

## Background tracker for the strenuous-day / overtime rules per
## ax_campaign_play.xml §effort_rules L166-172 and §overtime_rules L173-186.
##
## Each strenuous activity day increments the streak counter on
## character_activity_state. Once the streak exceeds 6, a cumulative −1 per
## day penalty applies to attack throws, damage rolls, and proficiency throws
## until the character takes a Rest day.
##
## The accountant denormalizes the penalty into
## character_activity_state.attack_throw_penalty so the combat hot path can
## read it cheaply via get_attack_throw_penalty().
##
## Subscribes to:
##   * EventBus.activity_completed     — singular/restricted strenuous
##   * EventBus.activity_tick_earned   — ongoing strenuous (one per day)
##   * Timekeeping.day_changed         — auto-reset on rest days (no activity)


# ---------------------------------------------------------------------------
# Constants — RAW per ax_campaign_play §effort_rules / §overtime_rules
# ---------------------------------------------------------------------------

const STRENUOUS_GRACE_DAYS := 6


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null
var _catalog: ActivityCatalog
var _last_known_day: int = 0
## Records which characters earned a strenuous bump on the current calendar day,
## so we don't double-count multiple Singular strenuous activities on one day.
var _strenuous_today: Dictionary = {}  # { character_id: calendar_day }


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _init(runner, catalog: ActivityCatalog) -> void:
	_runner = runner
	_catalog = catalog


# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

func subscribe() -> void:
	if not EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.connect(_on_activity_completed)
	if not EventBus.activity_tick_earned.is_connected(_on_activity_tick_earned):
		EventBus.activity_tick_earned.connect(_on_activity_tick_earned)
	if not Timekeeping.day_changed.is_connected(_on_day_changed):
		Timekeeping.day_changed.connect(_on_day_changed)


func unsubscribe() -> void:
	if EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.disconnect(_on_activity_completed)
	if EventBus.activity_tick_earned.is_connected(_on_activity_tick_earned):
		EventBus.activity_tick_earned.disconnect(_on_activity_tick_earned)
	if Timekeeping.day_changed.is_connected(_on_day_changed):
		Timekeeping.day_changed.disconnect(_on_day_changed)


# ---------------------------------------------------------------------------
# Public read API (used by combat / proficiency throw resolvers)
# ---------------------------------------------------------------------------

## Returns the cumulative −N penalty currently applied to attack/damage/
## proficiency throws for [param character_id]. Zero if no row or under the
## 6-day grace window. Static so combat / proficiency resolvers can read the
## denormalized value without holding a StrenuousAccountant instance.
##
## Per §effort_rules L168: cumulative −1 per day past the 6-day limit applies
## to attack throws, damage rolls, AND proficiency throws; penalties remit
## at −1 per day of rest per §overtime_rules L181. The column is named
## `attack_throw_penalty` for historical reasons (the combat hot path was
## wired first) but it is the unified strenuous penalty — `get_proficiency_throw_penalty`
## below is a self-documenting alias for proficiency-resolver call sites.
static func get_attack_throw_penalty(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	var row: Dictionary = CampaignRepository.get_character_activity_state(character_id)
	if row.is_empty():
		return 0
	return int(row.get("attack_throw_penalty", 0))


## Self-documenting alias for proficiency-throw call sites per RAW
## §effort_rules L168. Returns the same value as `get_attack_throw_penalty`
## because RAW lumps attack throws, damage rolls, and proficiency throws
## under a single cumulative −N counter. Keeping it as an alias (rather
## than a separate persisted field) avoids any risk of the two counters
## drifting from each other — the strenuous-day bump and the rest-day
## remission update one column that all three call-site categories read.
static func get_proficiency_throw_penalty(character_id: String) -> int:
	return get_attack_throw_penalty(character_id)


## Reset the streak (and clear the penalty) when a character rests as the
## day's major activity. Idempotent within a single day.
func register_rest_day(character_id: String, calendar_day: int) -> void:
	if character_id.is_empty():
		return
	var row: Dictionary = CampaignRepository.get_character_activity_state(character_id)
	var current_streak: int = int(row.get("strenuous_days_in_streak", 0))
	var current_penalty: int = int(row.get("attack_throw_penalty", 0))
	# Per §overtime_rules L181: penalties remit at -1 per day of rest. Streak
	# can reset more aggressively to keep the model simple — once you rest,
	# the streak counter resets to zero and penalty drops by 1 per rest day.
	CampaignRepository.upsert_character_activity_state(character_id, {
		"strenuous_days_in_streak": 0,
		"last_rest_day": calendar_day,
		"attack_throw_penalty": maxi(0, current_penalty - 1),
		"last_updated_calendar_day": calendar_day,
	})


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_activity_completed(
	_activity_state_id: String,
	character_id: String,
	outcome: Dictionary
) -> void:
	if character_id.is_empty():
		return
	var def_id: String = String(outcome.get("activity_def_id", ""))
	if def_id.is_empty():
		return
	if _is_strenuous(def_id):
		_bump_strenuous(character_id)


func _on_activity_tick_earned(
	_activity_state_id: String,
	character_id: String,
	_ticks_accumulated: int
) -> void:
	if character_id.is_empty():
		return
	# We need the activity_def_id; look up from the activity_state row.
	# The signal doesn't carry it because Active Projects sub-tab doesn't need
	# it for rendering.
	var rows: Array = CampaignRepository.list_active_activity_states_for_character(character_id)
	for row: Dictionary in rows:
		var def_id: String = String(row.get("activity_def_id", ""))
		if not _is_strenuous(def_id):
			continue
		_bump_strenuous(character_id)
		return  # only one bump per day


func _on_day_changed(_new_day: int, _new_month: int, _new_year: int) -> void:
	# Auto-reset the per-day dedupe tracker on day rollover.
	_last_known_day = _calendar_day()
	_strenuous_today.clear()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _is_strenuous(activity_def_id: String) -> bool:
	if _catalog == null:
		return false
	var def: Dictionary = _catalog.get_definition(activity_def_id)
	if def.is_empty():
		return false
	return bool(def.get("strenuous", false))


func _bump_strenuous(character_id: String) -> void:
	var today: int = _calendar_day()
	if _strenuous_today.get(character_id, -1) == today:
		return  # already counted today
	_strenuous_today[character_id] = today

	var row: Dictionary = CampaignRepository.get_character_activity_state(character_id)
	var streak: int = int(row.get("strenuous_days_in_streak", 0)) + 1
	var penalty: int = 0
	if streak > STRENUOUS_GRACE_DAYS:
		# Cumulative -1 per day past the grace window per §effort_rules L168.
		penalty = streak - STRENUOUS_GRACE_DAYS
	CampaignRepository.upsert_character_activity_state(character_id, {
		"strenuous_days_in_streak": streak,
		"attack_throw_penalty": penalty,
		"last_updated_calendar_day": today,
	})


func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
