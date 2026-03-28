extends Node

## Timekeeping — global in-game clock at all time granularities.
##
## No class_name — autoload scripts must not use class_name.
## Reference as: Timekeeping.get_date(), Timekeeping.advance_rounds(6)
##
## ── Calendar ─────────────────────────────────────────────────────────────────
##   Custom 13-month calendar, 28 days per month = 364 days/year (no leap year).
##   Standard sub-day units: 7-day weeks, 24-hour days, 60-minute hours,
##   60-second minutes, 6-second rounds (10 rounds per minute).
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
## ── Multi-party ──────────────────────────────────────────────────────────────
##   _elapsed_rounds always equals the leading party's time.
##   Boundary signals fire against the global clock only.
##   Use register_party / advance_party_* / sync_parties for split-party play.
##
## ── Persistence ──────────────────────────────────────────────────────────────
##   Eager save: every advance_* call writes to campaign_clock / party_clocks.
##   No-ops if no campaign is loaded (_campaign_id is empty) or DB is not ready.
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

## Emitted when one or more minute boundaries are crossed.
## [param minutes_elapsed] is the total number of minute boundaries crossed.
signal minute_advanced(minutes_elapsed: int)

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

## Party clock registry: party_id (String) → elapsed_rounds (int).
## _elapsed_rounds always equals max(values) when parties are registered.
var _party_clocks: Dictionary = {}

## Campaign ID stored after load_state(). Used for eager saves after advances.
## Empty when no campaign is loaded — saves are no-ops in that case.
var _campaign_id: String = ""


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Reset internal state when the session ends (player returns to main menu).
	GameState.session_ended.connect(_on_session_ended)


func _on_session_ended() -> void:
	_elapsed_rounds = 0
	_dawn_hour = 6
	_dusk_hour = 20
	_party_clocks.clear()
	_campaign_id = ""


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
	_emit_boundary_signals(old, _elapsed_rounds)
	_auto_save()


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
# Multi-Party Time Tracking
# ---------------------------------------------------------------------------

## Register [param party_id] for independent time tracking.
## Initialises the party's clock to the current global time.
## No-op if the party is already registered.
func register_party(party_id: String) -> void:
	if _party_clocks.has(party_id):
		return
	_party_clocks[party_id] = _elapsed_rounds
	_save_party_clock(party_id)


## Unregister [param party_id] and discard its clock.
func unregister_party(party_id: String) -> void:
	_party_clocks.erase(party_id)
	_delete_party_clock(party_id)


## Returns the elapsed rounds for [param party_id].
## Falls back to the global clock and logs an error if the party is unknown.
func get_party_time(party_id: String) -> int:
	if not _party_clocks.has(party_id):
		push_error("Timekeeping.get_party_time: unknown party '%s'" % party_id)
		return _elapsed_rounds
	return _party_clocks[party_id]


## Advance [param party_id]'s clock by [param n] rounds.
## If this party becomes the furthest-ahead party, the global clock advances
## accordingly and boundary signals fire.
func advance_party_rounds(party_id: String, n: int) -> void:
	assert(n >= 0, "Timekeeping.advance_party_rounds: n must be >= 0")
	if not _party_clocks.has(party_id):
		push_error("Timekeeping.advance_party_rounds: unknown party '%s'" % party_id)
		return
	_party_clocks[party_id] += n
	_sync_global_to_leader()
	_save_party_clock(party_id)


## Advance [param party_id]'s clock by [param n] minutes.
func advance_party_minutes(party_id: String, n: int) -> void:
	advance_party_rounds(party_id, n * ROUNDS_PER_MINUTE)


## Advance [param party_id]'s clock by [param n] turns.
func advance_party_turns(party_id: String, n: int) -> void:
	advance_party_rounds(party_id, n * ROUNDS_PER_TURN)


## Advance [param party_id]'s clock by [param n] hours.
func advance_party_hours(party_id: String, n: int) -> void:
	advance_party_rounds(party_id, n * ROUNDS_PER_HOUR)


## Advance all lagging parties to match the leading party's time.
## Call at end-of-day reconciliation (session runner responsibility).
func sync_parties() -> void:
	for party_id in _party_clocks:
		_party_clocks[party_id] = _elapsed_rounds
	_save_all_party_clocks()


## Returns the party_id of the furthest-ahead party, or "" if no parties are registered.
func get_leading_party() -> String:
	var max_time := -1
	var leader   := ""
	for party_id in _party_clocks:
		if _party_clocks[party_id] > max_time:
			max_time = _party_clocks[party_id]
			leader   = party_id
	return leader


## Returns the absolute round difference between two parties (always non-negative).
func get_time_gap(party_a: String, party_b: String) -> int:
	return abs(get_party_time(party_a) - get_party_time(party_b))


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Persist the global clock and all party clocks to the database.
## Can be called explicitly; also called automatically after every advance.
func save_state(campaign_id: String) -> void:
	if CampaignRepository.db == null:
		return
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO campaign_clock (campaign_id, elapsed_rounds, dawn_hour, dusk_hour)
		VALUES (?, ?, ?, ?)
	""", [campaign_id, _elapsed_rounds, _dawn_hour, _dusk_hour])
	for party_id in _party_clocks:
		CampaignRepository.db.query_with_bindings("""
			INSERT OR REPLACE INTO party_clocks (campaign_id, party_id, elapsed_rounds)
			VALUES (?, ?, ?)
		""", [campaign_id, party_id, _party_clocks[party_id]])


## Restore the clock state from the database for [param campaign_id].
## Stores the campaign_id internally to enable eager saves after future advances.
func load_state(campaign_id: String) -> void:
	_campaign_id = campaign_id
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

	# Restore party clocks
	_party_clocks.clear()
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM party_clocks WHERE campaign_id = ?", [campaign_id]
	)
	for row in CampaignRepository.db.query_result:
		_party_clocks[row["party_id"] as String] = row["elapsed_rounds"] as int


# ---------------------------------------------------------------------------
# Private — Boundary signal emission
# ---------------------------------------------------------------------------

## Emit all boundary signals for the transition from [param old_elapsed]
## to [param new_elapsed] (both in rounds). Called internally after every advance.
func _emit_boundary_signals(old_elapsed: int, new_elapsed: int) -> void:
	# Round: always fired; carries the delta.
	round_advanced.emit(new_elapsed - old_elapsed)

	# Minute boundaries
	var old_minutes := old_elapsed / ROUNDS_PER_MINUTE
	var new_minutes := new_elapsed / ROUNDS_PER_MINUTE
	if new_minutes > old_minutes:
		minute_advanced.emit(new_minutes - old_minutes)

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


## Update the global clock to match the furthest-ahead party.
## Emits boundary signals if the global clock is advanced.
func _sync_global_to_leader() -> void:
	var max_time := _elapsed_rounds
	for party_id in _party_clocks:
		if _party_clocks[party_id] > max_time:
			max_time = _party_clocks[party_id]
	if max_time > _elapsed_rounds:
		var old := _elapsed_rounds
		_elapsed_rounds = max_time
		_emit_boundary_signals(old, _elapsed_rounds)
		_auto_save()


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


# ---------------------------------------------------------------------------
# Private — Persistence helpers
# ---------------------------------------------------------------------------

## Write current global clock to DB if a campaign is loaded.
func _auto_save() -> void:
	if not _campaign_id.is_empty():
		save_state(_campaign_id)


## Upsert a single party clock row.
func _save_party_clock(party_id: String) -> void:
	if _campaign_id.is_empty() or CampaignRepository.db == null:
		return
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO party_clocks (campaign_id, party_id, elapsed_rounds)
		VALUES (?, ?, ?)
	""", [_campaign_id, party_id, _party_clocks.get(party_id, 0)])


## Delete a party clock row (called on unregister).
func _delete_party_clock(party_id: String) -> void:
	if _campaign_id.is_empty() or CampaignRepository.db == null:
		return
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_clocks WHERE campaign_id = ? AND party_id = ?",
		[_campaign_id, party_id]
	)


## Upsert all registered party clocks (called by sync_parties).
func _save_all_party_clocks() -> void:
	if _campaign_id.is_empty() or CampaignRepository.db == null:
		return
	for party_id in _party_clocks:
		_save_party_clock(party_id)
