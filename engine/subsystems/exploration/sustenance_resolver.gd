class_name SustenanceResolver
extends RefCounted

## Daily food / water / exhaustion accounting for a wilderness party
## (Wilderness closure Phase 3).
##
## Pure logic — no DB writes, no signal emission. The caller (the
## wilderness_day_tick handler) feeds in the party's pre-tick state, gets
## back the post-tick deltas, and is responsible for persistence + signals.
## This shape keeps the resolver fully unit-testable in isolation.
##
## Authority: SACRED — `acore_adventures_and_encounters.xml`
## §rations_and_foraging.daily_consumption / .lack_of_food / .lack_of_water.
##
##   Daily consumption: 1 stone per character (2 lb food + 1 gallon water).
##   Lack of food:
##     * First two days: no effect.
##     * After two days: lose 1 hp/day, cannot heal naturally (magic still works).
##     * Recovery: one day of full rations restores natural healing; lost hp
##       then recovers at the normal rate.
##   Lack of water:
##     * After one day: lose 1d4 hp; +1d4/day thereafter.
##     * Healing ability is lost when the first die of damage is rolled.
##
## v1 unit cadence: ration_units / water_units count person-day equivalents.
## A 4-character party consumes 4 ration_units + 4 water_units per day-tick.


# ---------------------------------------------------------------------------
# Constants — sacred from acore_adventures_and_encounters.xml
# ---------------------------------------------------------------------------

## Days without food before HP loss starts (acore §lack_of_food.no_significant_effect).
const FOOD_GRACE_DAYS := 2

## HP lost per day past the food-grace window.
const FOOD_DAILY_HP_LOSS := 1

## HP lost on the first dehydrated day (1d4) and per subsequent day.
const WATER_HP_DIE_SIDES := 4
const WATER_HP_DIE_COUNT := 1


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Apply one day's worth of consumption + penalty math for [param party].
##
## [param party]            — PartyData with character_data populated. The
##                            resolver mutates `ration_units`, `water_units`,
##                            `starvation_days`, `dehydration_days`,
##                            `exhaustion_days`, and `days_since_rest` in
##                            place. HP loss is REPORTED in the result; the
##                            caller applies it via the existing damage path.
## [param dice]             — DiceSystem-like injectable for `roll_digital`.
##                            Tests pass a fake; production passes the autoload.
## [param characters]       — Array[CharacterData] of party members who eat
##                            today. Defaults to party.character_data.
##                            Trained creatures and mounts are NOT counted in
##                            v1 (Phase 3.5 polish).
##
## Returns Dictionary:
##   party_size:                 int    — count of characters consuming today
##   food_consumed:              int    — units drawn from ration_units (≤ party_size)
##   water_consumed:             int    — units drawn from water_units (≤ party_size)
##   food_short:                 int    — party_size − food_consumed (deficit count)
##   water_short:                int    — party_size − water_consumed
##   hp_loss_per_character:      Dictionary — character_id → hp_lost
##   total_hp_lost:              int    — sum of hp_loss_per_character values
##   starvation_days_after:      int    — counter post-tick
##   dehydration_days_after:     int    — counter post-tick
##   exhaustion_days_after:      int    — counter post-tick (Phase 3 v1: not yet
##                                        accumulated by this resolver; reserved
##                                        for forced-march/rest-day integration).
##   thresholds_crossed:         Array[String] — labels for sustenance_threshold_crossed
##                                              ("food_grace_expired", "water_first_loss",
##                                              "starvation_recovery", etc.)
##   notes:                      String — short human-readable summary
static func apply_daily(
	party: PartyData,
	dice,
	characters: Array = [],
) -> Dictionary:
	if party == null:
		return {}
	if characters.is_empty():
		characters = party.character_data

	var party_size: int = characters.size()
	if party_size <= 0:
		return {
			"party_size": 0,
			"food_consumed": 0, "water_consumed": 0,
			"food_short": 0, "water_short": 0,
			"hp_loss_per_character": {},
			"total_hp_lost": 0,
			"starvation_days_after": party.starvation_days,
			"dehydration_days_after": party.dehydration_days,
			"exhaustion_days_after": party.exhaustion_days,
			"thresholds_crossed": [],
			"notes": "no characters present",
		}

	var thresholds: Array[String] = []

	# --- Food consumption -----------------------------------------------------
	var food_consumed: int = mini(party_size, party.ration_units)
	party.ration_units -= food_consumed
	var food_short: int = party_size - food_consumed

	var prev_starvation: int = party.starvation_days
	if food_short > 0:
		party.starvation_days += 1
	else:
		# Recovery: one day of full rations restores natural healing per RAW.
		# We zero the counter, which also clears the no-natural-heal flag
		# (the caller decides whether to re-allow nat heal based on
		# starvation_days==0).
		if prev_starvation > 0:
			thresholds.append("starvation_recovery")
		party.starvation_days = 0

	# Threshold crossing notifications — fire ONCE on the boundary day.
	if prev_starvation < FOOD_GRACE_DAYS and party.starvation_days >= FOOD_GRACE_DAYS:
		thresholds.append("food_grace_expired")
	if prev_starvation == FOOD_GRACE_DAYS and party.starvation_days == FOOD_GRACE_DAYS + 1:
		# day grace+1 is when "lose 1 hp/day" first applies.
		thresholds.append("starvation_first_hp_loss")

	# --- Water consumption ----------------------------------------------------
	var water_consumed: int = mini(party_size, party.water_units)
	party.water_units -= water_consumed
	var water_short: int = party_size - water_consumed

	var prev_dehydration: int = party.dehydration_days
	if water_short > 0:
		party.dehydration_days += 1
	else:
		if prev_dehydration > 0:
			thresholds.append("dehydration_recovery")
		party.dehydration_days = 0

	if prev_dehydration == 0 and party.dehydration_days == 1:
		thresholds.append("water_first_loss")

	# --- HP loss --------------------------------------------------------------
	# Per RAW: starvation deals 1 hp/day after the 2-day grace.
	# Dehydration deals 1d4 hp on the first dehydrated day, then +1d4/day.
	# Both penalties stack (a fully-deprived party loses 1 + 1d4 hp/day).
	var hp_loss_per_character: Dictionary = {}
	var total_hp_lost: int = 0

	var starvation_hp: int = 0
	if party.starvation_days > FOOD_GRACE_DAYS:
		starvation_hp = FOOD_DAILY_HP_LOSS

	for cd: CharacterData in characters:
		var loss: int = 0
		if starvation_hp > 0:
			loss += starvation_hp
		if party.dehydration_days >= 1:
			# Roll 1d4 per dehydrated character per day. RAW says "lose 1d4
			# hit points" (singular), then "+1d4 per day thereafter" — the
			# plain reading is one die per day per character.
			var dehydration_roll: RollResult = dice.roll_digital(
				WATER_HP_DIE_SIDES, WATER_HP_DIE_COUNT, 0, "dehydration_damage")
			loss += dehydration_roll.modified_total
		if loss > 0:
			hp_loss_per_character[cd.id] = loss
			total_hp_lost += loss

	var notes: String = "ate %d/%d, drank %d/%d" % [
		food_consumed, party_size, water_consumed, party_size]

	return {
		"party_size": party_size,
		"food_consumed": food_consumed,
		"water_consumed": water_consumed,
		"food_short": food_short,
		"water_short": water_short,
		"hp_loss_per_character": hp_loss_per_character,
		"total_hp_lost": total_hp_lost,
		"starvation_days_after": party.starvation_days,
		"dehydration_days_after": party.dehydration_days,
		"exhaustion_days_after": party.exhaustion_days,
		"thresholds_crossed": thresholds,
		"notes": notes,
	}


## True if the party is currently barred from natural healing per
## acore §lack_of_food.after_two_days.healing and §lack_of_water.healing_loss.
##
## This is a query helper used by the natural-healing path elsewhere — the
## resolver does NOT itself prevent heals; it only reports the state. RAW:
##   * Food deficit (after grace): "Cannot heal naturally."
##   * Water deficit (any day): "Healing ability is lost when the first die
##     of damage is rolled."
static func is_natural_healing_blocked(party: PartyData) -> bool:
	if party == null:
		return false
	if party.starvation_days > FOOD_GRACE_DAYS:
		return true
	if party.dehydration_days >= 1:
		return true
	return false
