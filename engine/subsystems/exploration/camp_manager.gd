class_name CampManager
extends RefCounted

## Camp/rest logic for wilderness and town rest periods.
##
## Wilderness camp: 12-hour rest (3 watches x 4 hours). Encounter checks per
## watch. Sleeping characters are prone, unequipped, and Surprised for round 1
## if encounter occurs during their sleep.
##
## Armed sleeper option: character may sleep in armor. Must pass a d20 throw
## vs (total_encumbrance +/- CON_mod + 1) or count as not having rested.
##
## Town rest: 12 hours, no watches, no encounter checks.
##
## No dungeon resting in V1 — party must return to wilderness.

const WATCH_COUNT := 3
const WATCH_HOURS := 4
const TOTAL_REST_HOURS := 12

## Result dictionary keys for a resolved camp.
## {
##   "watches": Array[Dictionary],  # per-watch results
##   "rest_recovery": Dictionary,   # HP/spell recovery summary
##   "rations_consumed": int,
##   "total_hours": int,
## }


# ---------------------------------------------------------------------------
# Watch assignment validation
# ---------------------------------------------------------------------------

## Validate a watch assignment. Returns "" on success, error message on failure.
## assignments: Array of 3 Arrays, each containing character_ids for that watch.
static func validate_watch_assignment(assignments: Array, party_ids: Array) -> String:
	if assignments.size() != WATCH_COUNT:
		return "Must have exactly %d watches." % WATCH_COUNT

	var assigned_ids: Dictionary = {}
	for watch_index in range(WATCH_COUNT):
		var watch: Array = assignments[watch_index]
		if watch.is_empty():
			return "Watch %d has no assigned characters." % (watch_index + 1)
		for char_id in watch:
			if char_id in assigned_ids:
				return "Character assigned to multiple watches."
			assigned_ids[char_id] = true

	# Every party member must be assigned to exactly one watch.
	for pid in party_ids:
		if not assigned_ids.has(pid):
			return "Not all party members are assigned to a watch."

	return ""


# ---------------------------------------------------------------------------
# Encounter check per watch [DEPRECATED 2026-05-27]
# ---------------------------------------------------------------------------

## DEPRECATED — do not call from new code.
##
## Per gdd-realtime-scheduler.md §4.3 (revised 2026-05-27), a camp receives
## ONE encounter throw at camp_setup (rolled in CampHandlers.schedule_watches
## via the gated hybrid rule), NOT one per watch. The earlier per-watch model
## was a documentation hallucination that ~40% over-shot RAW encounter rates.
##
## This static is retained for now to avoid breaking any test that hasn't
## been audited yet; remove after the test audit (§5 of the migration punch
## list). New code: see `CampHandlers._perform_camp_encounter_throw` and the
## `wilderness_encounter` event in WildernessHandlers.
static func check_watch_encounter(terrain_encounter_chance: float) -> Variant:
	push_warning("CampManager.check_watch_encounter is DEPRECATED. See gdd-realtime-scheduler.md §4.3.")
	var roll := DiceSystem.roll_digital(6, 1, 0, "encounter_check")
	var threshold := int(terrain_encounter_chance * 6.0)
	if threshold < 1:
		threshold = 1
	if roll.raw_total <= threshold:
		return {
			"encounter_roll": roll.raw_total,
			"threshold": threshold,
			"triggered": true,
		}
	return null


# ---------------------------------------------------------------------------
# Armed sleeper check
# ---------------------------------------------------------------------------

## Roll to see if a character can rest while wearing armor.
## d20 >= (encumbrance +/- CON_mod + 1) to succeed.
## Returns true if rested successfully, false if they did NOT rest.
static func armed_sleeper_check(encumbrance_stones: int, con_modifier: int) -> Dictionary:
	var target := encumbrance_stones - con_modifier + 1
	var roll := DiceSystem.roll_digital(20, 1, 0, "armed_sleeper")
	var success := roll.raw_total >= target
	return {
		"roll": roll.raw_total,
		"target": target,
		"success": success,
	}


# ---------------------------------------------------------------------------
# Rest recovery
# ---------------------------------------------------------------------------

## Compute recovery from a full rest period.
## Returns a dictionary of recovery data per character.
## failed_rest_ids: characters who failed armed sleeper checks (no recovery).
static func compute_rest_recovery(party_members: Array,
		failed_rest_ids: Array = []) -> Dictionary:
	var recovery := {}
	for member in party_members:
		var char_id: String = member.get("id", "")
		if char_id in failed_rest_ids:
			recovery[char_id] = {
				"hp_recovered": 0,
				"spells_recovered": false,
				"reason": "Failed to rest in armor.",
			}
			continue

		# HP recovery: 1 HP per day of rest (ACKS Core).
		var hp_current: int = member.get("hp_current", 0)
		var hp_max: int = member.get("hp_max", 0)
		var hp_recovered := mini(1, hp_max - hp_current)  # Clamp to missing HP.

		recovery[char_id] = {
			"hp_recovered": hp_recovered,
			"spells_recovered": true,
			"reason": "",
		}
	return recovery


# ---------------------------------------------------------------------------
# Ration consumption
# ---------------------------------------------------------------------------

## Consume rations for the party. Returns count consumed.
## In v1, this just returns the party size (1 ration per character per day).
static func compute_ration_consumption(party_size: int) -> int:
	return party_size


# ---------------------------------------------------------------------------
# Town rest (simplified)
# ---------------------------------------------------------------------------

## Resolve a town rest — no watches, no encounter checks.
## Returns the same result format as a wilderness camp.
static func resolve_town_rest(party_members: Array) -> Dictionary:
	var recovery := compute_rest_recovery(party_members)
	return {
		"watches": [],
		"rest_recovery": recovery,
		"rations_consumed": party_members.size(),
		"total_hours": TOTAL_REST_HOURS,
		"is_town_rest": true,
	}
