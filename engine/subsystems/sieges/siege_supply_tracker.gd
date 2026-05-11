class_name SiegeSupplyTracker
extends RefCounted

## Stored-supplies tracker for besieged strongholds per
## rules/daw_sieges.xml §effects_of_blockade L116-136.
##
## All economic state in cp per project convention (PartyWallet, deduct_cost_cp).
## RAW gp values × 100:
##   600 gp/UC default = 60_000 cp/UC
##   3,000 gp/UC cap   = 300_000 cp/UC
##   600 gp/UC/week prep = 60_000 cp/UC/week
##
## Daily consumption derivation: RAW L124 says default 600 gp/UC = 10 weeks at
## full garrison. 60_000 cp / 70 days ≈ 857 cp/UC/day (banker's rounded).
## Drift is ~10 cp / week / UC, well below display precision.
##
## Public API:
##   compute_default_stored_supplies_cp(unit_capacity) -> int
##   accrue_prep_supplies_cp(unit_capacity, weeks_of_warning) -> int
##   compute_daily_consumption_cp(unit_capacity, garrison_units_present) -> int
##   tick_consumption(siege_id, day) -> Dictionary
##   apply_starvation_penalties(siege_id, day) -> Dictionary
##   weekly_starvation_calamity(siege_id, day, dice) -> Array  (loyalty rolls)

# RAW §effects_of_blockade.stored_supplies L122-129
const DEFAULT_STORED_CP_PER_UC: int = 60_000          # L123: 600 gp/UC × 100 cp/gp
const MAX_STORED_CP_PER_UC: int = 300_000             # L127: 3,000 gp/UC × 100
const PREP_SUPPLY_CP_PER_UC_PER_WEEK: int = 60_000    # L126: +600 gp/UC/week × 100

# Derived: daily consumption rate per UC per garrison-unit-present.
# 60_000 cp / 70 days = 857.142... → banker's round → 857 cp/UC/day at full garrison.
# At full garrison the original "10 weeks" cadence is preserved.
const DAILY_CONSUMPTION_CP_PER_UC_AT_FULL_GARRISON: int = 857

# RAW §effects_of_blockade.loss_of_supplies L130-136
const HP_LOSS_PER_DAY_UNSUPPLIED: int = 1             # L131
const STARVATION_ATK_DMG_PENALTY_PER_WEEK: int = -1   # L132 cumulative


## RAW L122-123: default stored supplies = 600 gp per point of unit capacity.
static func compute_default_stored_supplies_cp(unit_capacity: int) -> int:
	if unit_capacity <= 0:
		return 0
	return unit_capacity * DEFAULT_STORED_CP_PER_UC


## RAW L126-127: if not blockaded immediately, supplies increase 600 gp/UC/week
## of preparation. Capped at 3,000 gp/UC (= 1 year per L128).
static func accrue_prep_supplies_cp(unit_capacity: int, weeks_of_warning: int) -> int:
	if unit_capacity <= 0:
		return 0
	if weeks_of_warning <= 0:
		return compute_default_stored_supplies_cp(unit_capacity)
	var accrued: int = compute_default_stored_supplies_cp(unit_capacity) \
		+ unit_capacity * PREP_SUPPLY_CP_PER_UC_PER_WEEK * weeks_of_warning
	var cap: int = unit_capacity * MAX_STORED_CP_PER_UC
	return mini(accrued, cap)


## Compute daily consumption in cp.
## RAW L124: "default amount is enough for 10 weeks if the stronghold is
## garrisoned at full capacity." → consumption per UC at full garrison
## = DEFAULT_STORED / 70 = 857 cp/UC/day.
##
## Partial garrison: scale linearly. Garrison present > UC clamps to UC.
## (RAW caps assault and defense at UC per §siege_mechanics L40.)
static func compute_daily_consumption_cp(unit_capacity: int, garrison_units_present: int) -> int:
	if unit_capacity <= 0 or garrison_units_present <= 0:
		return 0
	var effective_garrison: int = mini(garrison_units_present, unit_capacity)
	# Pro-rate by (effective_garrison / unit_capacity), then × full-UC daily cost.
	# Full-UC daily cost = unit_capacity × DAILY_CONSUMPTION_CP_PER_UC_AT_FULL_GARRISON.
	# Combined: effective_garrison × DAILY_CONSUMPTION_CP_PER_UC_AT_FULL_GARRISON.
	return effective_garrison * DAILY_CONSUMPTION_CP_PER_UC_AT_FULL_GARRISON


## Tick a single day of supply consumption for an active blockade.
## Returns:
##   {
##     supplies_remaining: int,             # cp, after consumption
##     consumed_today: int,                  # cp consumed this tick
##     became_unsupplied_today: bool,       # ran out for the first time
##     hp_loss_per_troop: int,              # 0 if still supplied; HP_LOSS_PER_DAY_UNSUPPLIED otherwise
##     loyalty_roll_required: bool,         # true on each calendar week boundary while unsupplied
##     weeks_unsupplied_now: int,
##     starvation_penalty_stacks_now: int,
##   }
static func tick_consumption(siege_id: String, day: int) -> Dictionary:
	var result: Dictionary = {
		"supplies_remaining": 0,
		"consumed_today": 0,
		"became_unsupplied_today": false,
		"hp_loss_per_troop": 0,
		"loyalty_roll_required": false,
		"weeks_unsupplied_now": 0,
		"starvation_penalty_stacks_now": 0,
	}
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty() or int(siege.get("is_blockaded", 0)) == 0:
		return result

	var unit_capacity: int = int(siege.get("unit_capacity", 0))
	# v1: garrison_units_present approximates as min(unit_capacity, defending army units).
	# Phase 9C will tighten via a real garrison count once Call to Arms troop creation lands.
	var garrison: int = _count_defending_units(siege)
	var consume_cp: int = compute_daily_consumption_cp(unit_capacity, garrison)
	var stored: int = int(siege.get("stored_supplies_cp", 0))
	var was_unsupplied: bool = stored <= 0
	var new_stored: int = maxi(0, stored - consume_cp)
	var actually_consumed: int = stored - new_stored

	var weeks_unsupplied: int = int(siege.get("weeks_unsupplied", 0))
	var penalty_stacks: int = int(siege.get("starvation_penalty_stacks", 0))
	var became_unsupplied_today: bool = false
	var hp_loss: int = 0
	var loyalty_roll_required: bool = false

	if new_stored <= 0:
		hp_loss = HP_LOSS_PER_DAY_UNSUPPLIED
		if not was_unsupplied:
			became_unsupplied_today = true
			# Reset week counter if we were previously supplied.
			weeks_unsupplied = 0
			# Track first-day-unsupplied on the siege payload for week-boundary math.
			_stamp_first_unsupplied_day(siege_id, day)
		# Each week unsupplied → loyalty roll + cumulative -1 atk/dmg per RAW L132-134.
		var first_unsupplied_day: int = _read_first_unsupplied_day(siege_id)
		if first_unsupplied_day > 0:
			var days_unsupplied: int = day - first_unsupplied_day + 1
			var weeks: int = (days_unsupplied + 6) / 7  # ceil
			if weeks > weeks_unsupplied:
				weeks_unsupplied = weeks
				penalty_stacks = weeks  # cumulative per week
				loyalty_roll_required = true

	# Persist updates.
	SiegeRepository.update(siege_id, {
		"stored_supplies_cp": new_stored,
		"weeks_unsupplied": weeks_unsupplied,
		"starvation_penalty_stacks": penalty_stacks,
	})
	# Ledger row.
	SiegeRepository.append_action(
		siege_id, day, "defender", "supplies_consumed",
		{"supplies_delta_cp": -actually_consumed},
		{
			"stored_before_cp": stored,
			"stored_after_cp": new_stored,
			"unit_capacity": unit_capacity,
			"garrison_present": garrison,
		}
	)
	if loyalty_roll_required:
		SiegeRepository.append_action(
			siege_id, day, "defender", "starvation_penalty",
			{},
			{
				"weeks_unsupplied": weeks_unsupplied,
				"penalty_stacks": penalty_stacks,
				"hp_loss_per_troop": hp_loss,
			}
		)

	result.supplies_remaining = new_stored
	result.consumed_today = actually_consumed
	result.became_unsupplied_today = became_unsupplied_today
	result.hp_loss_per_troop = hp_loss
	result.loyalty_roll_required = loyalty_roll_required
	result.weeks_unsupplied_now = weeks_unsupplied
	result.starvation_penalty_stacks_now = penalty_stacks
	return result


## Apply per-troop starvation HP loss. Called by tick_consumption result handler
## in the main resolver. Garrison-tier HP-tracking will be wired by the resolver;
## this helper exists for unit testing the formula in isolation.
static func compute_total_garrison_hp_loss(unit_capacity: int, garrison_units_present: int, hp_loss_per_troop: int, troops_per_unit: int = 120) -> int:
	if hp_loss_per_troop <= 0:
		return 0
	var effective: int = mini(garrison_units_present, unit_capacity)
	return effective * troops_per_unit * hp_loss_per_troop


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _count_defending_units(siege: Dictionary) -> int:
	## v1: return min(unit_capacity, defender army's active troop_unit count).
	## If no defending army, fall back to unit_capacity (RAW L123 default-supply
	## cadence assumes full garrison).
	var unit_capacity: int = int(siege.get("unit_capacity", 0))
	var defending_army_id: String = String(siege.get("defending_army_id", ""))
	if defending_army_id.is_empty():
		return unit_capacity
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM army_unit_assignments
		WHERE army_id = ? AND released_calendar_day = 0
	""", [defending_army_id]):
		return unit_capacity
	if CampaignRepository.db.query_result.is_empty():
		return unit_capacity
	var assigned: int = int(CampaignRepository.db.query_result[0].get("n", unit_capacity))
	return mini(assigned, unit_capacity) if assigned > 0 else unit_capacity


static func _stamp_first_unsupplied_day(siege_id: String, day: int) -> void:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	if not payload.has("first_unsupplied_day"):
		payload["first_unsupplied_day"] = day
		SiegeRepository.update(siege_id, {"payload_json": JSON.stringify(payload)})


static func _read_first_unsupplied_day(siege_id: String) -> int:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return 0
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	return int(payload.get("first_unsupplied_day", 0))


static func _parse_payload(json_str: String) -> Dictionary:
	if json_str.is_empty() or json_str == "{}":
		return {}
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}
