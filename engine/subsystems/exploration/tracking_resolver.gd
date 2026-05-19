class_name TrackingResolver
extends RefCounted

## Wilderness tracking (Wilderness closure Phase 5).
##
## Pure logic — no DB writes, no signal emission. Caller owns the
## tracking_sessions row; this resolver answers "did the throw succeed
## given these inputs?"
##
## Authority — SACRED:
##   `acore_proficiencies_rules_and_catalog.xml` Tracking entry:
##     base_throw: 11+ on 1d20
##     +2 tracking 2-4 creatures
##     +4 tracking 4-8 creatures
##     +6 tracking 8-16 creatures
##     +8 tracking 17 or more creatures
##     +4 soft or muddy ground
##     -8 hard or rocky ground
##     -4 bad lighting
##     -1 per 12 hours of good weather since the trail was made
##     -4 per hour of rain or snow since the trail was made
##     "Characters move at half speed while tracking."
##
## NOTE on overlap with `le_wilderness_lair_rules.xml` §searching_for_lairs.tracking:
## The lair-search +4 Tracking bonus is a different application of the
## proficiency (group-level lair detection). Phase 4 ships that bonus inside
## LairSearchResolver. Phase 5 covers the per-trail Tracking-the-trail use,
## which is the proficiency's primary application.


# ---------------------------------------------------------------------------
# Constants — sacred from acore_proficiencies_rules_and_catalog.xml
# ---------------------------------------------------------------------------

const BASE_THROW := 11
const PROFICIENCY_KEY := "tracking"

const GOOD_WEATHER_DECAY_PER_12H := -1
const RAIN_OR_SNOW_DECAY_PER_HOUR := -4

const HOURS_PER_GOOD_WEATHER_TICK := 12

# Group-size bonus thresholds: returns 0 / +2 / +4 / +6 / +8.
const _GROUP_BONUSES := [
	[1,  0],   # solo
	[3,  2],   # 2-4 creatures
	[7,  4],   # 4-8 creatures (RAW reads "4-8" as inclusive overlap; we use 4-7)
	[15, 6],   # 8-16 (we use 8-15)
	[16, 8],   # 17+
]


# ---------------------------------------------------------------------------
# Public API — accumulating weather decay
# ---------------------------------------------------------------------------

## Compute the decay points to apply to a tracking session for the elapsed
## period. RAW: -1 per 12hr good weather, -4 per hour rain/snow.
## [param hours_elapsed] is the length of the period (clipped to >= 0).
## [param weather] is the period-average weather (atmosphere only matters).
## Returns a (negative or zero) integer to subtract from the throw modifier.
##
## Banker's rounding on 12-hour granularity: an 11-hour calm period adds 0;
## a 13-hour calm period adds -1.
static func compute_weather_decay(hours_elapsed: float, weather: WeatherStateData) -> int:
	if hours_elapsed <= 0.0:
		return 0
	if weather != null and (
			weather.atmosphere == WeatherStateData.ATMO_RAINY
			or weather.atmosphere == WeatherStateData.ATMO_SNOWY):
		# Round hours up to whole hours since RAW penalises "per hour" of rain
		# (any portion counts).
		return RAIN_OR_SNOW_DECAY_PER_HOUR * int(ceil(hours_elapsed))
	# Calm/windy → "good weather" — applies once per full 12-hour block.
	@warning_ignore("integer_division")
	var blocks: int = int(hours_elapsed) / HOURS_PER_GOOD_WEATHER_TICK
	return GOOD_WEATHER_DECAY_PER_12H * blocks


# ---------------------------------------------------------------------------
# Public API — single tracking throw
# ---------------------------------------------------------------------------

## Resolve one tracking throw on behalf of [param tracker] following a trail
## of [param target_size] creatures across [param ground_kind] terrain
## under [param lighting]. The accumulated [param weather_decay] is applied
## as a flat (already negative) modifier — the caller maintains it across
## throws via `compute_weather_decay`.
##
## [param ground_kind] is one of "soft", "hard", "normal" (default).
## [param lighting] is one of "good", "bad" (default "good").
## [param optional_specialist_bonus] — Phase 6 hook (Pathfinder specialist
## per `SpecialistCatalog`). Phase 5 always passed 0; Phase 6 wires the
## value via `SpecialistBonusResolver.bonus_for(...)` at the call site.
##
## Returns Dictionary:
##   tracker_id: String
##   roll: int                   — 1d20 result
##   group_bonus: int
##   ground_modifier: int
##   lighting_modifier: int
##   weather_decay: int          — pass-through of caller's input (negative)
##   specialist_bonus: int       — pass-through (additive)
##   total: int                  — roll + bonuses + modifiers + decay + specialist
##   target: int                 — 11
##   succeeded: bool
##   notes: String
static func attempt(
	tracker: CharacterData,
	target_size: int,
	ground_kind: String,
	lighting: String,
	weather_decay: int,
	dice,
	optional_specialist_bonus: int = 0,
) -> Dictionary:
	if tracker == null or not tracker.has_proficiency(PROFICIENCY_KEY):
		return _empty_result()

	var group_bonus: int = _group_size_bonus(target_size)
	var ground_mod: int = _ground_modifier(ground_kind)
	var lighting_mod: int = _lighting_modifier(lighting)
	# RAW §effort_rules L168: strenuous penalty applies to proficiency throws.
	# Tracking is a Tracking proficiency throw per ACore.
	var strenuous_penalty: int = StrenuousAccountant.get_proficiency_throw_penalty(tracker.id)

	var roll: RollResult = dice.roll_digital(20, 1, 0, "tracking")
	var total: int = (roll.modified_total + group_bonus + ground_mod
		+ lighting_mod + weather_decay + optional_specialist_bonus
		- strenuous_penalty)
	var succeeded: bool = total >= BASE_THROW

	var note := "Tracking succeeded." if succeeded else "Lost the trail."

	return {
		"tracker_id": tracker.id,
		"roll": roll.modified_total,
		"group_bonus": group_bonus,
		"ground_modifier": ground_mod,
		"lighting_modifier": lighting_mod,
		"weather_decay": weather_decay,
		"specialist_bonus": optional_specialist_bonus,
		"strenuous_penalty": strenuous_penalty,
		"total": total,
		"target": BASE_THROW,
		"succeeded": succeeded,
		"notes": note,
	}


## Pick the best tracker in [param party] (first member with Tracking).
## Returns null when no member is proficient.
static func pick_tracker(party: PartyData) -> CharacterData:
	if party == null:
		return null
	for cd: CharacterData in party.character_data:
		if cd != null and cd.has_proficiency(PROFICIENCY_KEY):
			return cd
	return null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _group_size_bonus(target_size: int) -> int:
	for entry in _GROUP_BONUSES:
		var max_for_band: int = int(entry[0])
		var bonus: int = int(entry[1])
		if target_size <= max_for_band:
			return bonus
	return 8  # 17+ falls through


static func _ground_modifier(ground_kind: String) -> int:
	match ground_kind:
		"soft": return 4
		"hard": return -8
		_:       return 0


static func _lighting_modifier(lighting: String) -> int:
	if lighting == "bad":
		return -4
	return 0


static func _empty_result() -> Dictionary:
	return {
		"tracker_id": "",
		"roll": 0,
		"group_bonus": 0,
		"ground_modifier": 0,
		"lighting_modifier": 0,
		"weather_decay": 0,
		"specialist_bonus": 0,
		"total": 0,
		"target": BASE_THROW,
		"succeeded": false,
		"notes": "no Tracking proficiency",
	}
