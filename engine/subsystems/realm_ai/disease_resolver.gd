class_name DiseaseResolver
extends RefCounted

## Disease vagary loop per RAW daw_vagaries.xml §disease L294-365.
##
## Public API:
##   apply_disease_to_army(army_id, calendar_day, dice, scheduler) -> Dictionary
##     Rolls 1d100 for disease type, then per-active-unit save vs Death.
##     Failed units are flagged is_diseased=1 with recovery_calendar_day set.
##     Schedules a `disease_recovery_check` event for each diseased unit.
##
##   resolve_disease_recovery(troop_unit_id, calendar_day) -> Dictionary
##     End-of-duration: unit either recovers or dies.
##     died = (failed_by >= death_threshold) OR (natural_roll == 1)
##
##   tick_weekly_cures(army_id, calendar_day) -> Array
##     Aggregate cure capacity across attached PCs/henchmen + officers.
##     Heals ranked by Healing proficiency (physicker=rank 2, chirugeon=rank 3)
##     and divine spellcaster level. Carries fractional remainder forward on
##     armies.payload_json["disease_cure_remainder"].
##
##   is_unit_combat_capable(troop_unit_id) -> bool
##     Returns false if the unit is is_diseased=1. Field-battle resolver and
##     supply-cost calculations should consult this.
##
##   compute_cure_capacity_per_week(army_id) -> float
##     Pure helper — returns fractional units curable per week from the army's
##     attached PCs, henchmen, and officers.
##
## Per O-9C-3: saves are made by the engine but death-threshold + recovery day
## are NOT shown in the normal player UI. Only the "Diseased" status label
## appears on the unit row. The Inspect-math debug affordance reveals all.

const DISEASE_TABLE_PATH := "res://data/vagaries/disease_type_table.json"
static var _disease_table: Dictionary = {}

# RAW L307-310 cure rates expressed as units cured per source per week.
const CURE_RATE_DIVINE_L9: float = 1.0     # 1 caster cures 1 unit/week
const CURE_RATE_DIVINE_L7_8: float = 0.5   # 2 casters cure 1 unit/week
const CURE_RATE_DIVINE_L6: float = 1.0 / 3.0   # 3 casters cure 1 unit/week
const CURE_RATE_CHIRUGEON: float = 1.0 / 3.0   # Healing rank 3 ≡ chirugeon
const CURE_RATE_PHYSICKER: float = 1.0 / 9.0   # Healing rank 2 ≡ physicker
# Healing rank 1 ("healer") has NO mass-army cure capability per RAW omission.

# Save target fallback. Phase 9C polish (migration 090) added per-troop
# save_vs_death column with tier-based defaults (untrained=16/average=14/veteran=12).
# DiseaseResolver reads troop_units.save_vs_death; the constant is the
# safety fallback when the column read returns 0 (shouldn't happen post-migration
# since DEFAULT is 14, but guards against any malformed row).
const FALLBACK_SAVE_VS_DEATH_TARGET: int = 14

# Divine-caster classes that cure mass-army disease per RAW (any class with
# clerical spell access at the listed levels).
const DIVINE_CASTER_CLASSES: Array = [
	"cleric", "bladedancer", "paladin", "priestess",
	"craftpriest", "lightblessed", "wonderworker"
]


# ---------------------------------------------------------------------------
# Public API: apply_disease
# ---------------------------------------------------------------------------

## Apply a disease vagary to an entire army. RAW §disease L294-313.
##
## Phase 9C polish: also schedules the per-army `disease_cure_weekly_tick`
## event on first infection if a scheduler is provided AND any unit was sickened.
## The tick runs the cure pipeline weekly and reschedules itself until no
## diseased units remain.
##
## Returns:
##   {
##     disease_type: String,
##     duration_days: int,
##     units_diseased: int,
##     units_safe: int,
##     unit_outcomes: Array of {unit_id, save_target, save_roll, save_natural,
##                              save_bonus, failed_by, became_diseased,
##                              duration_days, recovery_day},
##   }
static func apply_disease_to_army(army_id: String, calendar_day: int, dice = null, scheduler = null) -> Dictionary:
	_ensure_disease_table_loaded()
	var result: Dictionary = {
		"disease_type": "",
		"duration_days": 0,
		"units_diseased": 0,
		"units_safe": 0,
		"unit_outcomes": [],
	}
	if army_id.is_empty():
		return result
	# 1. Roll 1d100 for disease type.
	var d100: int = _roll_dice(dice, 1, 100)
	var disease_entry: Dictionary = _lookup_disease_by_d100(d100)
	if disease_entry.is_empty():
		return result
	result.disease_type = String(disease_entry.get("type", ""))
	# 2. Compute duration (use the disease's own dice for RAW-faithful per-army duration).
	var duration_days: int = _compute_duration_days(disease_entry, dice)
	result.duration_days = duration_days
	# 3. For each active, non-diseased, non-departed unit in the army:
	var units: Array = _list_active_units_for_army(army_id)
	var save_bonus: int = int(disease_entry.get("save_bonus", 0))
	var death_threshold: int = int(disease_entry.get("death_if_failed_by", 999))
	for unit in units:
		var unit_id: String = String(unit.get("id", ""))
		if unit_id.is_empty():
			continue
		# Phase 9C polish (migration 090): per-troop save target.
		var save_target: int = int(unit.get("save_vs_death", 0))
		if save_target <= 0:
			save_target = FALLBACK_SAVE_VS_DEATH_TARGET
		var roll_d20: int = _roll_dice(dice, 1, 20)
		var save_value: int = roll_d20 + save_bonus
		var failed: bool = save_value < save_target
		var failed_by: int = maxi(0, save_target - save_value)
		var outcome: Dictionary = {
			"unit_id": unit_id,
			"save_target": save_target,
			"save_roll": save_value,
			"save_natural": roll_d20,
			"save_bonus": save_bonus,
			"failed_by": failed_by,
			"became_diseased": failed,
			"duration_days": 0,
			"recovery_day": 0,
			"death_threshold": death_threshold,
		}
		if failed:
			var recovery_day: int = calendar_day + duration_days
			# Persist disease state on the troop_units row.
			CampaignRepository.db.query_with_bindings("""
				UPDATE troop_units
				SET is_diseased = 1,
				    disease_type = ?,
				    disease_recovery_calendar_day = ?,
				    disease_save_failed_by = ?,
				    disease_natural_roll = ?
				WHERE id = ?
			""", [result.disease_type, recovery_day, failed_by, roll_d20, unit_id])
			outcome["duration_days"] = duration_days
			outcome["recovery_day"] = recovery_day
			# Schedule the recovery-check event.
			if scheduler != null:
				scheduler.schedule_at(
					recovery_day,
					"disease_recovery_check",
					unit_id,
					{"unit_id": unit_id},
					ScheduledEvent.PRIORITY_CONSEQUENCE
				)
			result.units_diseased += 1
			if EventBus.has_signal("unit_diseased"):
				EventBus.emit_signal("unit_diseased", unit_id, result.disease_type, recovery_day)
		else:
			result.units_safe += 1
		result.unit_outcomes.append(outcome)
	# Phase 9C polish: schedule the weekly cure tick on first infection.
	# The tick reschedules itself until no diseased units remain in the army.
	if scheduler != null and int(result.get("units_diseased", 0)) > 0:
		_schedule_cure_tick_if_absent(army_id, calendar_day, scheduler)
	return result


## Phase 9C polish 2026-05-09: reconcile cure ticks on session load.
##
## Queries every army that has at least one is_diseased=1 unit, and seeds a
## `disease_cure_weekly_tick` event on the scheduler if none is pending.
## Called once at session_runner boot to recover from mid-disease save/loads
## (the tick events live only in the in-memory scheduler queue, while
## is_diseased state lives in the DB).
##
## Returns: {armies_reconciled: int, ticks_scheduled: int}.
static func reconcile_cure_ticks_on_session_load(scheduler, calendar_day: int) -> Dictionary:
	var result: Dictionary = {"armies_reconciled": 0, "ticks_scheduled": 0}
	if scheduler == null:
		return result
	# Find every army_id with at least one diseased unit currently assigned.
	if not CampaignRepository.db.query("""
		SELECT DISTINCT aua.army_id
		FROM army_unit_assignments aua
		JOIN troop_units tu ON tu.id = aua.troop_unit_id
		WHERE aua.released_calendar_day = 0
		      AND tu.status = 'active'
		      AND tu.is_diseased = 1
	"""):
		return result
	for row in CampaignRepository.db.query_result:
		var army_id: String = String(row.get("army_id", ""))
		if army_id.is_empty():
			continue
		result.armies_reconciled += 1
		# Idempotent: _schedule_cure_tick_if_absent checks get_events_for_owner first.
		var pending_before: int = scheduler.get_events_for_owner(army_id).size()
		_schedule_cure_tick_if_absent(army_id, calendar_day, scheduler)
		var pending_after: int = scheduler.get_events_for_owner(army_id).size()
		if pending_after > pending_before:
			result.ticks_scheduled += 1
	return result


## Schedule a disease_cure_weekly_tick for an army if one isn't already pending.
## Called from apply_disease_to_army on first infection. The tick handler
## reschedules itself weekly until no diseased units remain.
static func _schedule_cure_tick_if_absent(army_id: String, calendar_day: int, scheduler) -> void:
	if scheduler == null or army_id.is_empty():
		return
	# Check if a cure tick is already pending for this army.
	if scheduler.has_method("get_events_for_owner"):
		for ev in scheduler.get_events_for_owner(army_id):
			if ev != null and not ev.cancelled and String(ev.event_type) == "disease_cure_weekly_tick":
				return
	scheduler.schedule_at(
		calendar_day + 7,
		"disease_cure_weekly_tick",
		army_id,
		{"army_id": army_id},
		ScheduledEvent.PRIORITY_CONSEQUENCE
	)


# ---------------------------------------------------------------------------
# Public API: resolve_disease_recovery
# ---------------------------------------------------------------------------

## End-of-duration save resolution. RAW L301-302:
##   "recovers unless it failed by the disease's listed death threshold or
##    failed on a natural 1."
##
## Returns:
##   {recovered: bool, died: bool, unit_id: String, disease_type: String,
##    failed_by: int, death_threshold: int, natural_roll: int}
static func resolve_disease_recovery(troop_unit_id: String, calendar_day: int) -> Dictionary:
	_ensure_disease_table_loaded()
	var result: Dictionary = {
		"recovered": false, "died": false,
		"unit_id": troop_unit_id, "disease_type": "",
		"failed_by": 0, "death_threshold": 0, "natural_roll": 0,
	}
	if troop_unit_id.is_empty():
		return result
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]
	):
		return result
	if CampaignRepository.db.query_result.is_empty():
		return result
	var unit: Dictionary = CampaignRepository.db.query_result[0]
	if int(unit.get("is_diseased", 0)) == 0:
		return result  # already cured / recovered
	var disease_type: String = String(unit.get("disease_type", ""))
	var failed_by: int = int(unit.get("disease_save_failed_by", 0))
	var natural_roll: int = int(unit.get("disease_natural_roll", 0))
	var entry: Dictionary = _lookup_disease_by_type(disease_type)
	var death_threshold: int = int(entry.get("death_if_failed_by", 999))
	# RAW L301-302: died = (failed_by >= death_threshold) OR (natural_roll == 1)
	var died: bool = (failed_by >= death_threshold) or (natural_roll == 1)
	result.disease_type = disease_type
	result.failed_by = failed_by
	result.death_threshold = death_threshold
	result.natural_roll = natural_roll
	if died:
		# Unit dies — set status='departed'.
		CampaignRepository.db.query_with_bindings("""
			UPDATE troop_units
			SET status = 'departed',
			    is_diseased = 0,
			    departure_kind = 'died_of_disease',
			    departure_calendar_day = ?
			WHERE id = ?
		""", [calendar_day, troop_unit_id])
		result.died = true
		if EventBus.has_signal("unit_died_of_disease"):
			EventBus.emit_signal("unit_died_of_disease", troop_unit_id)
	else:
		# Unit recovers — clear all disease state.
		CampaignRepository.db.query_with_bindings("""
			UPDATE troop_units
			SET is_diseased = 0,
			    disease_type = '',
			    disease_recovery_calendar_day = 0,
			    disease_save_failed_by = 0,
			    disease_natural_roll = 0
			WHERE id = ?
		""", [troop_unit_id])
		result.recovered = true
		if EventBus.has_signal("unit_recovered_from_disease"):
			EventBus.emit_signal("unit_recovered_from_disease", troop_unit_id)
	return result


# ---------------------------------------------------------------------------
# Public API: cure pipeline
# ---------------------------------------------------------------------------

## Compute the army's per-week cure capacity in fractional units.
## RAW L307-310 + Phase 9C O-9C-4 confirmation:
##   1 cure / 1 L9+ divine caster
##   1 cure / 2 L7-8 divine casters
##   1 cure / 3 L6 divine casters OR 3 chirugeons (Healing rank 3)
##   1 cure / 9 physickers (Healing rank 2)
##   Healers (Healing rank 1) — no mass-army cure capability.
static func compute_cure_capacity_per_week(army_id: String) -> float:
	if army_id.is_empty():
		return 0.0
	var characters: Array = _list_attached_characters(army_id)
	var total: float = 0.0
	for c in characters:
		var cls: String = String(c.get("character_class", "")).to_lower()
		var level: int = int(c.get("level", 0))
		var char_id: String = String(c.get("id", ""))
		# Divine spellcaster contribution.
		if DIVINE_CASTER_CLASSES.has(cls):
			if level >= 9:
				total += CURE_RATE_DIVINE_L9
			elif level >= 7:
				total += CURE_RATE_DIVINE_L7_8
			elif level >= 6:
				total += CURE_RATE_DIVINE_L6
		# Healing proficiency contribution (independent of class).
		var healing_rank: int = _get_healing_rank(char_id)
		if healing_rank >= 3:
			total += CURE_RATE_CHIRUGEON
		elif healing_rank >= 2:
			total += CURE_RATE_PHYSICKER
		# Rank 1 ("healer") contributes nothing per RAW omission.
	return total


## Tick the weekly cure pipeline. Called from a weekly tick driver.
## Cures floor(capacity + carry) units this week; carries the fractional remainder
## to next week via armies.payload_json["disease_cure_remainder"].
##
## Phase 9C polish: returns `should_reschedule` so the handler knows whether to
## queue another disease_cure_weekly_tick. Stops when no diseased units remain.
##
## Returns: {cure_capacity_this_week, cured_count, units_cured: Array of unit_ids,
##           remainder_after, diseased_units_remaining, should_reschedule}
static func tick_weekly_cures(army_id: String, calendar_day: int) -> Dictionary:
	var result: Dictionary = {
		"cure_capacity_this_week": 0.0,
		"cured_count": 0,
		"units_cured": [],
		"remainder_after": 0.0,
		"diseased_units_remaining": 0,
		"should_reschedule": false,
	}
	if army_id.is_empty():
		return result
	var capacity: float = compute_cure_capacity_per_week(army_id)
	var carry: float = _read_cure_remainder(army_id)
	var total_capacity: float = capacity + carry
	var units_to_cure: int = int(floor(total_capacity))
	result.cure_capacity_this_week = capacity
	if units_to_cure <= 0:
		# Save the carry for next week.
		_write_cure_remainder(army_id, total_capacity)
		result.remainder_after = total_capacity
		# Reschedule only if there are still diseased units to potentially cure.
		var remaining_check: Array = _list_diseased_units_for_army(army_id)
		result.diseased_units_remaining = remaining_check.size()
		result.should_reschedule = remaining_check.size() > 0
		return result
	# Cure units in oldest-first order (units that have been sick longest
	# get priority — small fairness heuristic).
	var diseased_units: Array = _list_diseased_units_for_army(army_id)
	for unit in diseased_units:
		if units_to_cure <= 0:
			break
		var unit_id: String = String(unit.get("id", ""))
		# Force the unit to the recovered branch by clearing failed_by (so the
		# end-of-duration check passes safely) and resolve immediately.
		CampaignRepository.db.query_with_bindings("""
			UPDATE troop_units
			SET disease_save_failed_by = 0,
			    disease_natural_roll = 20
			WHERE id = ?
		""", [unit_id])
		var rr: Dictionary = resolve_disease_recovery(unit_id, calendar_day)
		if bool(rr.get("recovered", false)):
			result.units_cured.append(unit_id)
			units_to_cure -= 1
	result.cured_count = result.units_cured.size()
	var remainder_after: float = total_capacity - float(result.cured_count)
	_write_cure_remainder(army_id, remainder_after)
	result.remainder_after = remainder_after
	# Reschedule only if there are still diseased units in the army.
	var remaining_after: Array = _list_diseased_units_for_army(army_id)
	result.diseased_units_remaining = remaining_after.size()
	result.should_reschedule = remaining_after.size() > 0
	return result


## Pure helper for FieldBattleResolver / supply tracker / mining ticks.
static func is_unit_combat_capable(troop_unit_id: String) -> bool:
	if troop_unit_id.is_empty():
		return true
	if not CampaignRepository.db.query_with_bindings(
		"SELECT is_diseased FROM troop_units WHERE id = ?", [troop_unit_id]
	):
		return true
	if CampaignRepository.db.query_result.is_empty():
		return true
	return int(CampaignRepository.db.query_result[0].get("is_diseased", 0)) == 0


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _ensure_disease_table_loaded() -> void:
	if not _disease_table.is_empty():
		return
	if not FileAccess.file_exists(DISEASE_TABLE_PATH):
		push_error("DiseaseResolver: missing %s" % DISEASE_TABLE_PATH)
		_disease_table = {"rows": []}
		return
	var f := FileAccess.open(DISEASE_TABLE_PATH, FileAccess.READ)
	if f == null:
		_disease_table = {"rows": []}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_disease_table = parsed
	else:
		_disease_table = {"rows": []}


static func _lookup_disease_by_d100(d100: int) -> Dictionary:
	_ensure_disease_table_loaded()
	var rows: Array = _disease_table.get("rows", [])
	for row in rows:
		var lo: int = int(row.get("die_min", 0))
		var hi: int = int(row.get("die_max", 0))
		if d100 >= lo and d100 <= hi:
			return row
	return {}


static func _lookup_disease_by_type(disease_type: String) -> Dictionary:
	if disease_type.is_empty():
		return {}
	_ensure_disease_table_loaded()
	var rows: Array = _disease_table.get("rows", [])
	for row in rows:
		if String(row.get("type", "")) == disease_type:
			return row
	return {}


## Compute duration in days from the disease's duration_dice + duration_unit.
## RAW: plague=1d8 days, putrid_fever=2 weeks, spotted_pox=3 weeks,
##      bilious_fever=4 weeks, ague=1d4 weeks, bloody_flux=1 week.
static func _compute_duration_days(entry: Dictionary, dice) -> int:
	var dice_str: String = String(entry.get("duration_dice", "1"))
	var unit: String = String(entry.get("duration_unit", "weeks"))
	var rolled: int = _parse_and_roll_dice(dice_str, dice)
	if unit == "days":
		return rolled
	if unit == "weeks":
		return rolled * 7
	if unit == "months":
		return rolled * 28
	return rolled


static func _parse_and_roll_dice(dice_str: String, dice) -> int:
	## Parse "1d8" / "2" / "1d4" → integer.
	if dice_str.is_empty():
		return 1
	if not dice_str.contains("d"):
		return int(dice_str)
	var parts: PackedStringArray = dice_str.split("d")
	if parts.size() != 2:
		return 1
	var count: int = int(parts[0])
	var sides: int = int(parts[1])
	return _roll_dice(dice, count, sides)


static func _list_active_units_for_army(army_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT tu.id, tu.is_diseased, tu.status, tu.save_vs_death, tu.tier
		FROM troop_units tu
		JOIN army_unit_assignments aua ON aua.troop_unit_id = tu.id
		WHERE aua.army_id = ? AND aua.released_calendar_day = 0
		      AND tu.status = 'active' AND tu.is_diseased = 0
	""", [army_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _list_diseased_units_for_army(army_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT tu.id, tu.disease_recovery_calendar_day
		FROM troop_units tu
		JOIN army_unit_assignments aua ON aua.troop_unit_id = tu.id
		WHERE aua.army_id = ? AND aua.released_calendar_day = 0
		      AND tu.is_diseased = 1
		ORDER BY tu.disease_recovery_calendar_day  -- oldest sickness first
	""", [army_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## v1 list of "attached characters" = command character + all officers.
## Phase 9C polish: include attached PCs in the army's hex (party affixed).
static func _list_attached_characters(army_id: String) -> Array:
	var result: Array = []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT command_character_id FROM armies WHERE id = ?
	""", [army_id]):
		return result
	if CampaignRepository.db.query_result.is_empty():
		return result
	var command_id: String = String(CampaignRepository.db.query_result[0].get("command_character_id", ""))
	if not command_id.is_empty():
		var c: Dictionary = _get_character(command_id)
		if not c.is_empty():
			result.append(c)
	# Officers.
	if CampaignRepository.db.query_with_bindings("""
		SELECT character_id FROM army_officers WHERE army_id = ?
	""", [army_id]):
		for row in CampaignRepository.db.query_result:
			var oc: String = String(row.get("character_id", ""))
			if oc.is_empty():
				continue
			var char_data: Dictionary = _get_character(oc)
			if not char_data.is_empty():
				result.append(char_data)
	return result


static func _get_character(char_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, character_class, level FROM characters WHERE id = ?", [char_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


static func _get_healing_rank(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT MAX(rank) AS max_rank FROM character_proficiencies
		WHERE character_id = ? AND proficiency_key = 'healing'
	""", [character_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	var v: Variant = CampaignRepository.db.query_result[0].get("max_rank", 0)
	return 0 if v == null else int(v)


static func _read_cure_remainder(army_id: String) -> float:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT daily_penalty_state FROM armies WHERE id = ?", [army_id]
	):
		return 0.0
	if CampaignRepository.db.query_result.is_empty():
		return 0.0
	var json_str: String = String(CampaignRepository.db.query_result[0].get("daily_penalty_state", "{}"))
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		return 0.0
	var d: Dictionary = parsed
	return float(d.get("disease_cure_remainder", 0.0))


static func _write_cure_remainder(army_id: String, remainder: float) -> void:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT daily_penalty_state FROM armies WHERE id = ?", [army_id]
	):
		return
	if CampaignRepository.db.query_result.is_empty():
		return
	var json_str: String = String(CampaignRepository.db.query_result[0].get("daily_penalty_state", "{}"))
	var parsed: Variant = JSON.parse_string(json_str)
	var d: Dictionary = parsed if (parsed is Dictionary) else {}
	d["disease_cure_remainder"] = remainder
	CampaignRepository.db.query_with_bindings(
		"UPDATE armies SET daily_penalty_state = ? WHERE id = ?",
		[JSON.stringify(d), army_id]
	)


static func _roll_dice(dice, count: int, sides: int) -> int:
	# Accept either a Callable (test convention: Callable(fake, "roll")) or a
	# node-like object with a roll(count, sides) method (production convention).
	if dice is Callable:
		var c: Callable = dice
		if c.is_valid():
			return int(c.call(count, sides))
	elif dice != null:
		# Use is_instance_valid + has_method check for non-Callable objects.
		if typeof(dice) == TYPE_OBJECT and dice.has_method("roll"):
			return int(dice.roll(count, sides))
	if Engine.has_singleton("DiceSystem"):
		var ds = Engine.get_singleton("DiceSystem")
		if ds.has_method("roll"):
			return int(ds.roll(count, sides))
	var total: int = 0
	for _i in range(count):
		total += (randi() % sides) + 1
	return total
