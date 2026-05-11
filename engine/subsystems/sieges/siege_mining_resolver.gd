class_name SiegeMiningResolver
extends RefCounted

## Siege mining and countermining per rules/daw_sieges.xml §siege_mining L388-421.
##
## Each siege-mine is an independent construction project (RAW L394: 1,000 gp =
## 100,000 cp). Workers limited to 100 per mine (RAW L396). Construction rate
## is 20 cu.ft. per 1gp per day (RAW L400). When complete + ignited, deals
## 6d6×100 shp damage; petards add 100 × petard.damage (RAW L397-398).
##
## Weekly loyalty roll on workers (RAW L404 + L414); unmodified 2 = mining
## accident → mine destroyed, all workers killed, engineer save vs Blast or
## also dies (L405-408). Same applies to countermines.
##
## Defender countermines reduce a target mine's daily rate (RAW L415).
## Each day, defender may make a reconnaissance roll to detect undetected
## besieger mines (RAW L410).
##
## Limits (RAW L417-420):
##   - Solid rock → no mining (unless transmute_rock_to_mud is used first;
##     v1: a payload_json["mining_blocked_solid_rock"]=true on sieges blocks all).
##   - Surrounded by water or 10' moat → mining "virtually impossible";
##     payload_json["mining_blocked_moat"]=true.
##
## Public API:
##   start_mine(siege_id, side, supervising_engineer_id, workers, petard_damage,
##              calendar_day) -> mine_id
##   tick_construction(siege_id, day) -> Array  (per-mine progress)
##   detonate_mine(mine_id, day, dice_roller) -> Dictionary
##   weekly_loyalty_rolls(siege_id, day, dice_roller) -> Array  (mining accidents)
##   defender_reconnaissance_roll(siege_id, day, dice_roller) -> Array  (newly-detected mines)

const MINE_BASE_COST_CP: int = 100_000               # RAW L394: 1,000 gp × 100
const MINE_TUNNEL_CUBIC_FEET: int = 20_000           # RAW L399
const TUNNEL_FEET_PER_GP_PER_DAY: int = 20           # RAW L400
const MAX_WORKERS_PER_MINE: int = 100                # RAW L396
const MINING_ACCIDENT_LOYALTY_TARGET: int = 2        # RAW L405, L414 (unmodified 2)
const MINE_BASE_DAMAGE_DICE: int = 6                 # RAW L397: 6d6 × 100
const MINE_BASE_DAMAGE_SIDES: int = 6
const MINE_BASE_DAMAGE_MULTIPLIER: int = 100
const PETARD_DAMAGE_MULTIPLIER: int = 100            # RAW L398


## Start a siege-mine or countermine.
## construction_rate_cp_per_day = workers × 100 cp/day (since 1 gp/day = 100 cp/day,
## and the worker-engineer combo's rate is 1 gp per day per worker per RAW L400).
##
## ★ Strict reading of L400: "20 cubic feet of tunnel per 1gp per day."
##   Not per-worker; per-1gp-of-cost. v1 implementation follows the GDD's
##   established convention (1 worker ≈ 1gp/day) used in commission_pipeline.
static func start_mine(
	siege_id: String,
	side: String,
	supervising_engineer_id: String,
	workers: int,
	petard_damage: int = 0,
	calendar_day: int = 0,
	countermine_target_id: String = ""
) -> String:
	if siege_id.is_empty():
		return ""
	if side != "besieger" and side != "defender":
		return ""
	# Check siege-level blocks for besieger mines.
	if side == "besieger":
		var siege: Dictionary = SiegeRepository.get_siege(siege_id)
		if siege.is_empty():
			return ""
		var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
		if bool(payload.get("mining_blocked_solid_rock", false)):
			push_error("SiegeMiningResolver: cannot start besieger mine on solid_rock stronghold (use transmute_rock_to_mud first)")
			return ""
		if bool(payload.get("mining_blocked_moat", false)):
			push_error("SiegeMiningResolver: cannot start besieger mine on moat-surrounded stronghold")
			return ""
	var clamped_workers: int = clampi(workers, 1, MAX_WORKERS_PER_MINE)
	# v1: 1 worker = 1 gp/day = 100 cp/day construction rate. Rate scales linearly with workers.
	var rate_cp_per_day: int = clamped_workers * 100
	return SiegeRepository.create_mine({
		"siege_id": siege_id,
		"side": side,
		"supervising_engineer_id": supervising_engineer_id,
		"workers_assigned": clamped_workers,
		"cubic_feet_total": MINE_TUNNEL_CUBIC_FEET,
		"construction_rate_cp_per_day": rate_cp_per_day,
		"petard_damage": maxi(0, petard_damage),
		"countermine_target_id": countermine_target_id,
		"started_calendar_day": calendar_day,
	})


## Tick construction for all active mines.
## Per RAW L400: 20 cubic feet per 1gp per day. So daily progress in cu.ft. =
## (construction_rate_cp_per_day / 100) × 20 = construction_rate_cp_per_day / 5.
##
## Countermine penalty: each defender countermine reduces its target besieger
## mine's daily progress by the countermine's own daily progress (RAW L415).
##
## Returns: array of {mine_id, side, cubic_feet_progressed, cubic_feet_completed,
##                    cubic_feet_total, is_completed_now, penalized_by_countermines}
static func tick_construction(siege_id: String, day: int) -> Array:
	var mines: Array = SiegeRepository.list_active_mines(siege_id)
	if mines.is_empty():
		return []
	# Build penalty map: target_mine_id → total countermine progress this tick.
	var penalty_map: Dictionary = {}
	for m in mines:
		if String(m.get("side", "")) != "defender":
			continue
		var target_id: String = String(m.get("countermine_target_id", ""))
		if target_id.is_empty():
			continue
		var rate: int = int(m.get("construction_rate_cp_per_day", 0))
		var cu_ft: int = rate / 5  # per RAW L400
		penalty_map[target_id] = int(penalty_map.get(target_id, 0)) + cu_ft
	var results: Array = []
	for m in mines:
		var mine_id: String = String(m.get("id", ""))
		var rate: int = int(m.get("construction_rate_cp_per_day", 0))
		@warning_ignore("integer_division")
		var base_progress_cu_ft: int = rate / 5
		var penalty: int = int(penalty_map.get(mine_id, 0)) if String(m.get("side", "")) == "besieger" else 0
		var net_progress: int = maxi(0, base_progress_cu_ft - penalty)
		var current_completed: int = int(m.get("cubic_feet_completed", 0))
		var total: int = int(m.get("cubic_feet_total", MINE_TUNNEL_CUBIC_FEET))
		var new_completed: int = mini(total, current_completed + net_progress)
		var is_completed_now: bool = (current_completed < total) and (new_completed >= total)
		SiegeRepository.update_mine(mine_id, {
			"cubic_feet_completed": new_completed,
			"is_completed": is_completed_now or bool(int(m.get("is_completed", 0))),
		})
		var action_type: String = "siege_mining_progress" if String(m.get("side", "")) == "besieger" else "countermining_progress"
		SiegeRepository.append_action(siege_id, day, String(m.get("side", "")), action_type,
			{},
			{"mine_id": mine_id, "base_progress_cu_ft": base_progress_cu_ft,
			 "countermine_penalty_cu_ft": penalty, "net_progress_cu_ft": net_progress,
			 "completed_after": new_completed, "is_completed_now": is_completed_now}
		)
		results.append({
			"mine_id": mine_id,
			"side": m.get("side", ""),
			"cubic_feet_progressed": net_progress,
			"cubic_feet_completed": new_completed,
			"cubic_feet_total": total,
			"is_completed_now": is_completed_now,
			"penalized_by_countermines": penalty > 0,
		})
	return results


## Detonate a completed siege-mine. RAW L397-398: 6d6 × 100 shp; +100 × petard.
## Updates the parent siege's damage_dealt_total + breach_count.
static func detonate_mine(mine_id: String, day: int, dice_roller: Callable = Callable()) -> Dictionary:
	var mine: Dictionary = SiegeRepository.get_mine(mine_id)
	if mine.is_empty():
		return {"shp_damage_dealt": 0, "reason": "mine_not_found"}
	if int(mine.get("is_destroyed_by_accident", 0)) == 1:
		return {"shp_damage_dealt": 0, "reason": "mine_destroyed"}
	if int(mine.get("is_completed", 0)) == 0:
		return {"shp_damage_dealt": 0, "reason": "mine_incomplete"}
	if int(mine.get("detonated_calendar_day", 0)) > 0:
		return {"shp_damage_dealt": 0, "reason": "already_detonated"}
	var dice_total: int = _roll_dice(dice_roller, MINE_BASE_DAMAGE_DICE, MINE_BASE_DAMAGE_SIDES)
	var raw_damage: int = dice_total * MINE_BASE_DAMAGE_MULTIPLIER
	var petard_damage: int = int(mine.get("petard_damage", 0)) * PETARD_DAMAGE_MULTIPLIER
	var total_damage: int = raw_damage + petard_damage
	var siege_id: String = String(mine.get("siege_id", ""))
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"shp_damage_dealt": 0, "reason": "siege_not_found"}
	var new_dealt: int = int(siege.get("damage_dealt_total", 0)) + total_damage
	var new_shp: int = maxi(0, int(siege.get("starting_shp", 0)) - new_dealt + int(siege.get("damage_repaired_total", 0)))
	var new_breaches: int = UnitCapacityCalculator.breach_count_from_damage(new_dealt)
	var prev_breaches: int = int(siege.get("breach_count", 0))
	SiegeRepository.update(siege_id, {
		"damage_dealt_total": new_dealt, "current_shp": new_shp, "breach_count": new_breaches,
	})
	SiegeRepository.update_mine(mine_id, {"detonated_calendar_day": day})
	SiegeRepository.append_action(siege_id, day, String(mine.get("side", "besieger")),
		"siege_mining_detonation",
		{"shp_damage_dealt": total_damage, "breaches_added": new_breaches - prev_breaches},
		{"mine_id": mine_id, "dice_total": dice_total, "raw_damage": raw_damage,
		 "petard_damage": petard_damage, "shp_after": new_shp}
	)
	if new_breaches > prev_breaches and EventBus.has_signal("siege_breach_created"):
		EventBus.emit_signal("siege_breach_created", siege_id, new_breaches, "mining")
	return {"shp_damage_dealt": total_damage, "dice_total": dice_total,
	        "petard_damage_added": petard_damage, "new_breach_count": new_breaches}


## Per RAW §risk_rules L403-408 (also L414 for countermines): each week,
## workers on each mine make a loyalty roll. Unmodified 2 = mining accident.
##
## Returns: array of {mine_id, side, accident, roll, engineer_save_made}.
static func weekly_loyalty_rolls(siege_id: String, day: int, dice_roller: Callable = Callable()) -> Array:
	var mines: Array = SiegeRepository.list_active_mines(siege_id)
	var results: Array = []
	for m in mines:
		var mine_id: String = String(m.get("id", ""))
		var roll: int = _roll_dice(dice_roller, 2, 6)
		var accident: bool = roll == MINING_ACCIDENT_LOYALTY_TARGET
		var engineer_save_made: bool = false
		if accident:
			# Engineer may save vs Blast (RAW L407). v1: simulate with d20 vs target 15
			# (typical mid-level save vs Blast); refine when proficiency_throw integrates.
			var save_roll: int = _roll_dice(dice_roller, 1, 20)
			engineer_save_made = save_roll >= 15
			SiegeRepository.update_mine(mine_id, {"is_destroyed_by_accident": 1})
			SiegeRepository.append_action(siege_id, day, String(m.get("side", "besieger")),
				"mining_accident",
				{},
				{"mine_id": mine_id, "loyalty_roll": roll, "save_vs_blast_roll": save_roll,
				 "engineer_save_made": engineer_save_made,
				 "workers_killed": int(m.get("workers_assigned", 0))}
			)
			if EventBus.has_signal("siege_mining_accident"):
				EventBus.emit_signal("siege_mining_accident", siege_id, mine_id)
		results.append({
			"mine_id": mine_id, "side": m.get("side", ""),
			"accident": accident, "roll": roll,
			"engineer_save_made": engineer_save_made,
		})
	return results


## Defender's daily reconnaissance roll to detect besieger siege-mines.
## RAW L410: each day, defender may make a reconnaissance roll.
##
## v1: simple proficiency_throw vs target 18; replace with engineer's Hide skill
## once proficiency integration is finalized. Each undetected besieger mine
## gets one detection attempt per day.
##
## Returns: array of newly-detected mine ids.
static func defender_reconnaissance_roll(siege_id: String, day: int, dice_roller: Callable = Callable(), recon_target: int = 18) -> Array:
	var mines: Array = SiegeRepository.list_active_mines(siege_id, "besieger")
	var newly_detected: Array = []
	for m in mines:
		if int(m.get("is_detected", 0)) == 1:
			continue
		var roll: int = _roll_dice(dice_roller, 1, 20)
		if roll >= recon_target:
			var mine_id: String = String(m.get("id", ""))
			SiegeRepository.update_mine(mine_id, {
				"is_detected": 1,
				"detected_calendar_day": day,
			})
			newly_detected.append(mine_id)
	return newly_detected


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _parse_payload(json_str: String) -> Dictionary:
	if json_str.is_empty() or json_str == "{}":
		return {}
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}


static func _roll_dice(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller != null and dice_roller.is_valid():
		var v: Variant = dice_roller.call(count, sides)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)
		if typeof(v) == TYPE_DICTIONARY and v.has("total"):
			return int(v["total"])
	if Engine.has_singleton("DiceSystem"):
		var ds = Engine.get_singleton("DiceSystem")
		if ds.has_method("roll"):
			return int(ds.roll(count, sides))
	var total: int = 0
	for _i in range(count):
		total += (randi() % sides) + 1
	return total
