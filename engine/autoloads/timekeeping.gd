extends Node

## Timekeeping — global in-game clock at all time granularities.
##
## No class_name — autoload scripts must not use class_name.
## Reference as: Timekeeping.get_date(), Timekeeping.advance_rounds(6)
##
## ── Calendar ─────────────────────────────────────────────────────────────────
##   Custom 13-month calendar, 28 days per month = 364 days/year (no leap year).
##   Standard sub-day units: 7-day weeks, 24-hour days, 60-minute hours,
##   60-second minutes, 10-second rounds (6 rounds per minute).
##
## ── Granularities (from smallest to largest) ─────────────────────────────────
##   Round  = 10 seconds   (combat, fine dungeon actions)           [ACKS core rule]
##   Minute = 6 rounds     (spell durations, short timed actions)
##   Turn   = 60 rounds    (dungeon exploration = 10 minutes)       [ACKS core rule]
##   Hour   = 360 rounds   (wilderness travel, camp watches)
##   Day    = 8640 rounds  (downtime, domain management)
##
## ── Passive clock ─────────────────────────────────────────────────────────────
##   The clock NEVER ticks autonomously. Advance it by calling advance_*() methods.
##   The session runner owns advance calls; Timekeeping just tracks the result.
##
## ── Single shared timeline (Jedidiah rulings 2026-06-11/12) ─────────────────
##   There is ONE world clock; all parties live on it. get_total_rounds() is
##   the canonical "now" for every consumer, including event fire_time math.
##   Per-party clocks were removed (the per-party API and the party_clocks
##   table are gone). There is no order-lock either: a new order supersedes a
##   party's in-progress travel/activity (the order surfaces cancel its
##   pending events via cancel_all_for_owner before scheduling replacements).
##
## ── Persistence ──────────────────────────────────────────────────────────────
##   Debounced (2026-06-12; was eager-per-advance): advance_* calls mark the
##   clock dirty; flush() writes campaign_clock at SessionRunner's choke points
##   (scheduler pause, day boundary, save_session) atomically with the event
##   queue. The in-memory clock is authoritative between flushes.
##   All writes no-op if no campaign is loaded (_campaign_id empty) or DB not ready.
##
## Registered as autoload "Timekeeping" in project.godot.


# ---------------------------------------------------------------------------
# Calendar constants (ACKS core rules + custom 13/28 calendar)
# ---------------------------------------------------------------------------

## 1 round = 10 seconds (ACKS Adventures §time_and_movement).
const ROUNDS_PER_MINUTE := 6

## 1 turn = 10 minutes = 60 rounds (ACKS Adventures §time_and_movement).
const ROUNDS_PER_TURN := 60

## 1 hour = 6 turns = 360 rounds.
const ROUNDS_PER_HOUR := 360

## 1 day = 24 hours = 8,640 rounds.
const ROUNDS_PER_DAY := 8640

## Custom calendar: 28 days per month (13 × 28 = 364 days/year, no leap year).
const DAYS_PER_MONTH := 28

## Custom calendar: 13 months per year.
const MONTHS_PER_YEAR := 13

## Custom calendar: 364 days per year (13 × 28). Never changes — no leap year.
const DAYS_PER_YEAR := 364

## 0-indexed day_in_year values (total_days % DAYS_PER_YEAR) for season starts.
## Used internally by _emit_boundary_signals for season_changed detection.
## Spring=0, Summer=91, Autumn=182, Winter=273.
const _SEASON_STARTS: Array = [0, 91, 182, 273]

## Season names indexed to match _SEASON_STARTS.
const _SEASON_NAMES: Array = ["spring", "summer", "autumn", "winter"]


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after every advance call (global clock only).
## [param rounds_elapsed] is the number of rounds just advanced.
signal round_advanced(rounds_elapsed: int)

## Emitted when one or more turn (10-minute) boundaries are crossed.
signal turn_advanced(turns_elapsed: int)

## Emitted when one or more hour boundaries are crossed.
signal hour_advanced(hours_elapsed: int)

## Emitted once per calendar day boundary crossed, even during multi-day advances.
## [param new_day] / [param new_month] / [param new_year] describe the day entered.
signal day_changed(new_day: int, new_month: int, new_year: int)

## Emitted once per calendar month boundary crossed.
signal month_changed(new_month: int, new_year: int)

## Emitted once per calendar year boundary crossed.
signal year_changed(new_year: int)

## Emitted each time the clock crosses into the dawn hour (default 06:00).
signal dawn()

## Emitted each time the clock crosses into the dusk hour (default 20:00).
signal dusk()

## Emitted when the clock crosses into a new season.
## Fires within the same advance call as the triggering day_changed signal.
## [param new_season] is one of: "spring", "summer", "autumn", "winter".
signal season_changed(new_season: String)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Canonical clock: total rounds elapsed since campaign start.
## Year 1, Month 1, Day 1, Hour 0, Minute 0, Round 0 = 0 rounds.
var _elapsed_rounds: int = 0

## Dawn hour (0–23). Configurable per campaign. Default 6 = 06:00.
## Daylight: hour >= _dawn_hour and hour < _dusk_hour.
var _dawn_hour: int = 6

## Dusk hour (0–23). Configurable per campaign. Default 20 = 20:00.
var _dusk_hour: int = 20

## Campaign ID stored after load_state(). Used by flush()/_auto_save().
## Empty when no campaign is loaded — saves are no-ops in that case.
var _campaign_id: String = ""

## True when the in-memory clock has advances not yet written to campaign_clock.
## Set by advance_rounds; cleared by flush()/save_state()/load_state().
var _dirty: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Load persisted clock state when a campaign session begins.
	GameState.session_started.connect(_on_session_started)
	# Reset internal state when the session ends (player returns to main menu).
	GameState.session_ended.connect(_on_session_ended)
	# Campaign-wide aging advances on each calendar year boundary.
	year_changed.connect(_on_year_changed)


func _on_session_started(campaign_id: String) -> void:
	load_state(campaign_id)


func _on_session_ended() -> void:
	_elapsed_rounds = 0
	_dawn_hour = 6
	_dusk_hour = 20
	_campaign_id = ""
	_dirty = false


func _on_year_changed(_new_year: int) -> void:
	_age_campaign_characters_one_year()


# ---------------------------------------------------------------------------
# Query API — Absolute Time
# ---------------------------------------------------------------------------

## Returns the current in-game date and time as a Dictionary.
## Keys: year (1+), month (1–13), day (1–28), hour (0–23), minute (0–59), round (0–5).
func get_date() -> Dictionary:
	var total_days := _elapsed_rounds / ROUNDS_PER_DAY
	var date      := _date_from_total_days(total_days)
	var hour      := (_elapsed_rounds % ROUNDS_PER_DAY) / ROUNDS_PER_HOUR
	var minute    := (_elapsed_rounds % ROUNDS_PER_HOUR) / ROUNDS_PER_MINUTE
	var rnd       := _elapsed_rounds % ROUNDS_PER_MINUTE
	return {
		"year":   date["year"],
		"month":  date["month"],
		"day":    date["day"],
		"hour":   hour,
		"minute": minute,
		"round":  rnd,
	}


## Set the dawn and dusk hours for the current campaign day cycle.
## Called by the seasons/weather system when seasonal variation changes sunrise/sunset.
## Defaults (dawn=6, dusk=20) apply when no external system has overridden them,
## ensuring is_daylight() works correctly during testing before those systems exist.
## Persists to campaign_clock immediately so the new hours survive a reload.
func set_day_cycle(dawn_hour: int, dusk_hour: int) -> void:
	assert(dawn_hour >= 0 and dawn_hour <= 23,
		"Timekeeping.set_day_cycle: dawn_hour must be 0–23")
	assert(dusk_hour >= 0 and dusk_hour <= 23,
		"Timekeeping.set_day_cycle: dusk_hour must be 0–23")
	_dawn_hour = dawn_hour
	_dusk_hour = dusk_hour
	_auto_save()


## Returns the current dawn hour (0–23). Default 6.
func get_dawn_hour() -> int:
	return _dawn_hour


## Returns the current dusk hour (0–23). Default 20.
func get_dusk_hour() -> int:
	return _dusk_hour


## Total rounds elapsed since campaign start. The canonical "now" — use this
## for event fire_time computation, gating, ETA display, and persistence
## timestamps. (Single shared timeline; see header.)
func get_total_rounds() -> int:
	return _elapsed_rounds


## Total calendar days elapsed since campaign start (0 = Day 1, Month 1, Year 1).
func get_total_days() -> int:
	return _elapsed_rounds / ROUNDS_PER_DAY


## Total turns (10 minutes each) elapsed since campaign start.
func get_total_turns() -> int:
	return _elapsed_rounds / ROUNDS_PER_TURN


## Total minutes elapsed since campaign start.
func get_total_minutes() -> int:
	return _elapsed_rounds / ROUNDS_PER_MINUTE


## Current hour of day (0–23).
func get_time_of_day() -> int:
	return (_elapsed_rounds % ROUNDS_PER_DAY) / ROUNDS_PER_HOUR


## True if the current hour is in the daylight window [_dawn_hour, _dusk_hour).
## Default: true for hours 6–19, false for hours 20–5.
func is_daylight() -> bool:
	var hour := get_time_of_day()
	return hour >= _dawn_hour and hour < _dusk_hour


## Current calendar month (1–13).
func get_current_month() -> int:
	return get_date()["month"]


## Current day of month (1–28).
func get_current_day_of_month() -> int:
	return get_date()["day"]


## Current day of week (1–7). Day 1 is the campaign calendar's weekday 1.
## Wraps every 7 days regardless of month/year boundaries.
func get_day_of_week() -> int:
	return (_elapsed_rounds / ROUNDS_PER_DAY) % 7 + 1


## Current day of year (1–364). Resets to 1 at each year boundary.
## Feed this into CalendarSeasons.get_season() / get_climate_season().
func get_day_of_year() -> int:
	return (_elapsed_rounds / ROUNDS_PER_DAY) % DAYS_PER_YEAR + 1


## Canonical 1-based calendar-day serial (== get_total_days() + 1).
## THE day-serial coordinate system for persisted day stamps (conventions §6.8):
## Y1 M1 D1 = 1, Y1 M13 D1 = 337, Y2 M1 D1 = 365. The per-subsystem
## _calendar_day() helpers delegate here (deduplicated 2026-06-12).
func get_calendar_day() -> int:
	return get_total_days() + 1


## Canonical 1-based day serial for an arbitrary date dict ({year, month, day},
## all 1-based — the get_date() shape). Same coordinate system as
## get_calendar_day(); use for dates other than "today" (e.g. ledger stamps
## computed at month boundaries).
func calendar_day_from_date(date: Dictionary) -> int:
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * MONTHS_PER_YEAR + (month - 1)) * DAYS_PER_MONTH + day


## Rounds timestamp for the START (midnight) of calendar-day serial
## [param day_serial]. Use this when converting day-serial bookkeeping into
## EventScheduler fire_times — the queue's time axis is ROUNDS, never days.
## calendar_day_to_rounds(get_calendar_day()) == midnight of the current day.
func calendar_day_to_rounds(day_serial: int) -> int:
	return (day_serial - 1) * ROUNDS_PER_DAY


# ---------------------------------------------------------------------------
# Advance Methods — Global Clock
# ---------------------------------------------------------------------------

## Advance the global clock by [param n] rounds (must be non-negative).
## Emits boundary signals for every granularity boundary crossed.
func advance_rounds(n: int) -> void:
	assert(n >= 0, "Timekeeping.advance_rounds: n must be >= 0")
	if n == 0:
		return
	var old := _elapsed_rounds
	_elapsed_rounds += n
	# Debounced persistence: mark dirty; flush() writes at the choke points
	# (was an eager save_state here — ~30 fsync'd transactions/sec while the
	# wilderness clock ran). NOTE: dirty is set BEFORE the boundary signals so
	# the day-boundary flush listener sees the new time as unsaved.
	_dirty = true
	_emit_boundary_signals(old, _elapsed_rounds)


## Advance by [param n] minutes (n × 6 rounds internally).
func advance_minutes(n: int) -> void:
	advance_rounds(n * ROUNDS_PER_MINUTE)


## Advance by [param n] turns (n × 60 rounds internally, 10 min each).
func advance_turns(n: int) -> void:
	advance_rounds(n * ROUNDS_PER_TURN)


## Advance by [param n] hours (n × 360 rounds internally).
func advance_hours(n: int) -> void:
	advance_rounds(n * ROUNDS_PER_HOUR)


## Advance by [param n] days (n × 8640 rounds internally).
func advance_days(n: int) -> void:
	advance_rounds(n * ROUNDS_PER_DAY)


## Advance to the next occurrence of [param target_hour] (0–23).
##
## If the clock is already exactly at that hour (no sub-hour offset), does NOT advance.
## Otherwise, advances to the start of the next occurrence of that hour, which may
## wrap into the following day.
##
## Examples (default dawn = hour 6):
##   From hour 14 → advance_to_hour(6)  → +16 hours (lands on hour 6 next day).
##   From hour 6, minute 0, round 0     → no advance (already exactly there).
##   From hour 6, minute 5              → +23h55m (next day's hour 6).
func advance_to_hour(target_hour: int) -> void:
	assert(target_hour >= 0 and target_hour <= 23,
		"Timekeeping.advance_to_hour: target_hour must be 0–23")
	var current_pos_in_day := _elapsed_rounds % ROUNDS_PER_DAY
	var target_pos_in_day  := target_hour * ROUNDS_PER_HOUR
	if current_pos_in_day == target_pos_in_day:
		return  # Already exactly at this hour with no sub-hour remainder.
	var rounds_to_add: int
	if target_pos_in_day > current_pos_in_day:
		rounds_to_add = target_pos_in_day - current_pos_in_day
	else:
		# Target is earlier in the day — wrap around to next day.
		rounds_to_add = ROUNDS_PER_DAY - current_pos_in_day + target_pos_in_day
	advance_rounds(rounds_to_add)


## Advance to hour 0 (midnight) of the next calendar day.
## If already at hour 0 with no sub-hour offset, advances a full day anyway.
func advance_to_next_day() -> void:
	var current_pos_in_day := _elapsed_rounds % ROUNDS_PER_DAY
	if current_pos_in_day == 0:
		# Already at midnight — advance exactly one full day.
		advance_rounds(ROUNDS_PER_DAY)
	else:
		advance_to_hour(0)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Write the clock to campaign_clock if it has unsaved advances. Called from
## SessionRunner.flush_clock_and_queue() at the persistence choke points
## (scheduler pause, day boundary, save_session) — NOT after every advance.
## Returns true if a write happened.
func flush() -> bool:
	if not _dirty or _campaign_id.is_empty() or CampaignRepository.db == null:
		return false
	save_state(_campaign_id)
	return true


## Persist the clock to the database. Explicit-write helper used by flush(),
## set_day_cycle(), and tests; routine advances mark dirty instead (see flush).
func save_state(campaign_id: String) -> void:
	if CampaignRepository.db == null:
		return
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO campaign_clock (campaign_id, elapsed_rounds, dawn_hour, dusk_hour)
		VALUES (?, ?, ?, ?)
	""", [campaign_id, _elapsed_rounds, _dawn_hour, _dusk_hour])
	if campaign_id == _campaign_id:
		_dirty = false


## Restore the clock state from the database for [param campaign_id].
## Stores the campaign_id internally to enable eager saves after future advances.
func load_state(campaign_id: String) -> void:
	_campaign_id = campaign_id
	_dirty = false
	if CampaignRepository.db == null:
		return

	# Restore global clock
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM campaign_clock WHERE campaign_id = ?", [campaign_id]
	)
	if not CampaignRepository.db.query_result.is_empty():
		var row: Dictionary = CampaignRepository.db.query_result[0]
		_elapsed_rounds = row["elapsed_rounds"] as int
		_dawn_hour      = row["dawn_hour"] as int
		_dusk_hour      = row["dusk_hour"] as int


# ---------------------------------------------------------------------------
# Private — Boundary signal emission
# ---------------------------------------------------------------------------

## Emit all boundary signals for the transition from [param old_elapsed]
## to [param new_elapsed] (both in rounds). Called internally after every advance.
func _emit_boundary_signals(old_elapsed: int, new_elapsed: int) -> void:
	# Round: always fired; carries the delta.
	round_advanced.emit(new_elapsed - old_elapsed)

	# (No minute signal: minute_advanced had zero subscribers and was removed
	# 2026-06-12 — effect durations tick on round/turn granularity. Reintroduce
	# only with a real consumer.)

	# Turn boundaries (10 minutes each)
	var old_turns := old_elapsed / ROUNDS_PER_TURN
	var new_turns := new_elapsed / ROUNDS_PER_TURN
	if new_turns > old_turns:
		turn_advanced.emit(new_turns - old_turns)

	# Hour boundaries — also check each for dawn/dusk
	var old_hours_total := old_elapsed / ROUNDS_PER_HOUR
	var new_hours_total := new_elapsed / ROUNDS_PER_HOUR
	if new_hours_total > old_hours_total:
		hour_advanced.emit(new_hours_total - old_hours_total)
		# Iterate each hour boundary to detect dawn/dusk crossings.
		# For very large advances this is bounded by total hours, which is
		# acceptable for single-player game sessions.
		for h in range(old_hours_total + 1, new_hours_total + 1):
			var hour_of_day := h % 24
			if hour_of_day == _dawn_hour:
				dawn.emit()
			elif hour_of_day == _dusk_hour:
				dusk.emit()

	# Day/month/year/season boundaries — emit once per boundary crossed.
	var old_days := old_elapsed / ROUNDS_PER_DAY
	var new_days := new_elapsed / ROUNDS_PER_DAY
	for d in range(old_days + 1, new_days + 1):
		var date := _date_from_total_days(d)
		day_changed.emit(date["day"], date["month"], date["year"])
		# First day of a month → month boundary
		if date["day"] == 1:
			month_changed.emit(date["month"], date["year"])
			# First month of a year → year boundary
			if date["month"] == 1:
				year_changed.emit(date["year"])
		# Season boundaries: Spring starts day_in_year 0, Summer 91, Autumn 182, Winter 273.
		var day_in_year := d % DAYS_PER_YEAR
		var season_idx := _SEASON_STARTS.find(day_in_year)
		if season_idx != -1:
			season_changed.emit(_SEASON_NAMES[season_idx])


# ---------------------------------------------------------------------------
# Private — Calendar math
# ---------------------------------------------------------------------------

## Convert 0-indexed total days to {year, month, day} (all 1-indexed).
## total_days == 0  →  Year 1, Month 1, Day 1.
## total_days == 28 →  Year 1, Month 2, Day 1.
## total_days == 364 → Year 2, Month 1, Day 1.
func _date_from_total_days(total_days: int) -> Dictionary:
	var year       := total_days / DAYS_PER_YEAR + 1
	var day_in_year := total_days % DAYS_PER_YEAR
	var month      := day_in_year / DAYS_PER_MONTH + 1
	var day        := day_in_year % DAYS_PER_MONTH + 1
	return {"year": year, "month": month, "day": day}


## Apply one year of aging to all persistent, living characters in the active campaign.
## Called once for each crossed year boundary, so multi-year advances age stepwise and
## trigger age-category transitions in the correct order.
func _age_campaign_characters_one_year() -> void:
	var active_campaign_id := _campaign_id
	if active_campaign_id.is_empty():
		active_campaign_id = GameState.campaign_id
	if active_campaign_id.is_empty() or CampaignRepository.db == null:
		return

	var aging_system := AgingSystem.new()
	var character_rows := CampaignRepository.list_characters_excluding_tier(
		active_campaign_id, "transient"
	)
	for row in character_rows:
		var character := CharacterData.from_dict(row)
		if character.id.is_empty() or character.is_dead or character.current_age <= 0:
			continue

		var result := aging_system.apply_age_change(character, 1)
		var fields := {
			"current_age": character.current_age,
			"age_category": character.age_category,
		}
		for ability in [
			"strength", "intelligence", "wisdom",
			"dexterity", "constitution", "charisma",
		]:
			if row.get(ability, 0) != character.get(ability):
				fields[ability] = character.get(ability)

		if not CampaignRepository.update_character_fields(character.id, fields):
			push_error("Timekeeping._age_campaign_characters_one_year: failed to persist '%s'" %
				character.id)
			continue

		if result.get("category_changed", false):
			EventBus.age_category_changed.emit(
				character.id,
				result.get("old_category", ""),
				result.get("new_category", "")
			)


# ---------------------------------------------------------------------------
# Private — Persistence helpers
# ---------------------------------------------------------------------------

## Immediate clock write if a campaign is loaded. Used only by rare one-off
## config changes (set_day_cycle); routine advances use _dirty + flush().
func _auto_save() -> void:
	if not _campaign_id.is_empty():
		save_state(_campaign_id)
