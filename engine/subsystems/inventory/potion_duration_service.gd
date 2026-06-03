class_name PotionDurationService
extends RefCounted

## Per-potion temp-duration mechanic for the four temp-effect potions:
##   - Potion of Heroism             (ACKS Core p.215+, 1 day duration, fighter-only)
##   - Potion of Super-Heroism       (ACKS Core p.215+, 1 day, fighter-only, bigger table)
##   - Potion of Giant Strength      (ACKS Core p.215+, 3 turn duration, no class gate)
##   - Potion of Invulnerability     (ACKS Core p.215+, 1d6+6 turns, once-per-week or inverts)
##
## RAW (ACKS Core 2026-06-03, Jedidiah-supplied from p.215+):
##
## Giant Strength: "The imbiber of this potion temporarily becomes as strong
##   as a hill giant. The wearer attacks as an 8 HD monster or as his own
##   class and level, whichever is better, and the character inflicts double
##   normal damage with his attacks. The character also can throw rocks at
##   opponents to a distance of 200' for 3d6 points of damage and gains a
##   +16 bonus to force open doors. The strength bonuses of this potion may
##   not be combined with any other magical effects that influence strength,
##   but it does stack with the character's normal bonus or penalty from
##   Strength — a weak character who drinks this potion has the strength of
##   a weak giant, while a very strong character would gain the strength of
##   a very strong giant!"
##   Spell duration (Giant Strength spell): 3 turns.
##
## Heroism: "Only an assassin, dwarven vaultguard, elven spellsword, explorer,
##   or fighter may use this potion. Extra levels and their accompanied
##   benefits to combat are temporarily granted to the imbiber, determined by
##   his experience level as shown in this table. Note that extra hit points
##   granted due to the level increase are subtracted first when the character
##   is wounded."
##   Level table:  0 → 4, 1-3 → 3, 4-7 → 2, 8-10 → 1, 11+ → 0
##   Duration: 1 day (per Tampering with Mortality references, ACKS Core).
##   Project gate (Jedidiah ruling 2026-06-03): gate on
##   `combat_progression == "fighter"` rather than class_id whitelist, so all
##   fighter-progression classes (Fighter, Barbarian, Paladin, Ruinguard,
##   Vaultguard, Spellsword, Explorer, Anti-Paladin, Dwarven Fury, Elven
##   Ranger, etc.) qualify without per-class name maintenance. Future
##   fighter-progression classes auto-qualify.
##
## Super-Heroism: "Only assassins, dwarven vaultguards, elven spellswords,
##   explorers, and fighters may use this potion. Extra levels and their
##   accompanied benefits to combat are temporarily granted to the imbiber,
##   determined by his or her experience level as shown in the table below.
##   In all other respects this potion is identical to heroism."
##   Level table:  0 → 6, 1-3 → 5, 4-7 → 4, 8-10 → 3, 11-12 → 2
##   RAW silent for level 13+; V1 project ruling = 0 (conservative).
##
## Invulnerability: "An invulnerability potion gives the drinker a bonus of
##   +2 to all saving throws and Armor Class. However, if a potion of
##   invulnerability is quaffed more than once per week, the potion has the
##   opposite effect, causing a penalty of -2 to saving throws and Armor
##   Class!"
##   Duration: 1d6+6 turns (potion default per ACore general rules).
##
## Default potion rules (apply to all four):
##   ACore line 223: "Default duration is 1d6+6 turns unless a specific
##   potion says otherwise."
##   ACore line 224: "If a character drinks a second potion while one is
##   active, the character is sickened and cannot act for 3 turns; neither
##   potion has any other effect."
##
## ── Architecture ────────────────────────────────────────────────────────────
## Routes through ActiveEffectTracker for the duration tick + cleanup hook.
## Each potion stamps a tracker effect with `dispatch_cleanup_on_tick: true`
## so the standard cleanup callback (CastingResolver._on_tracker_removed_effect
## → _unwind_effect_state) sweeps applied modifiers/flags/temp_hp on
## turn/day-boundary expiry. The standard EffectTicker (wired by SessionRunner
## subscribes to Timekeeping signals) handles tick propagation.
##
## State:
##   - Modifiers applied via source_id "potion_temporary:<item_id>" so they
##     can be swept by the cleanup callback.
##   - "has_active_potion" EntityFlag on the drinker with metadata
##     {item_id, item_key, effect_id, expires_at_turn, expires_at_day,
##     effect_kind, applied_temp_hp, applied_modifier_keys}. This flag is
##     the gate for the second-potion sickened check.
##   - "is_sickened_by_potion" EntityFlag stamped when a second potion is
##     attempted while the first is active. 3-turn duration.
##   - "last_invulnerability_quaff_day" EntityFlag tracks the most-recent
##     Invulnerability quaff for the weekly inversion check. Not duration-
##     bounded (persistent across the campaign).
##
## Class restriction (Heroism family) implemented via `is_eligible_class`
## helper. Gate point: MagicItemActivator._resolve_direct_potion_effect's
## "temp_combat_levels" branch calls apply_combat_level_boost which refuses
## with refused_reason "class_restricted" when combat_progression isn't
## "fighter". Per Jedidiah 2026-06-03.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SOURCE_PREFIX := "potion_temporary:"
const SICKENED_SOURCE_PREFIX := "potion_temporary_sickened:"
const INVULNERABILITY_TRACKER_SOURCE := "potion_invulnerability_tracker"

const SICKENED_DURATION_TURNS: int = 3

# Per-RAW spell durations (override the 1d6+6 default).
const GIANT_STRENGTH_DURATION_TURNS: int = 3
const HEROISM_DURATION_DAYS: int = 1

# Invulnerability uses the potion default duration; V1 picks a deterministic
# midpoint (1d6+6 expected value ≈ 9-10 turns). Tests can override via
# DiceSystem.fixed["potion_invulnerability_duration"].
const INVULNERABILITY_DURATION_TURNS_DEFAULT: int = 10
const INVULNERABILITY_WEEK_DAYS: int = 7
const INVULNERABILITY_BONUS: int = 2
const INVULNERABILITY_PENALTY: int = -2

# Giant Strength attack-throw target value (8-HD-monster value per the
# Girdle pattern — see worn_magic_effect_resolver.GIRDLE_OF_GIANT_STRENGTH_ATTACK_THROW).
const GIANT_STRENGTH_ATTACK_THROW_CEILING: int = 3

# Hit-die averages used for Heroism temp_hp computation. Banker's rounding
# isn't relevant here because all dice have integer mean values when stored
# as halves rounded toward the middle: d4→2 (mean 2.5), d6→3 (mean 3.5),
# d8→4 (mean 4.5), d10→5 (mean 5.5), d12→6 (mean 6.5). V1 uses the floor of
# the mean — RAW Heroism says "extra hit points granted" without specifying
# rolled vs averaged; deterministic floor keeps tests stable.
const HIT_DIE_AVERAGE: Dictionary = {
	"1d4": 2, "1d6": 3, "1d8": 4, "1d10": 5, "1d12": 6,
}

# Heroism level → levels-granted table per ACKS Core p.215+.
const HEROISM_TABLE: Array = [
	{"min": 0, "max": 0, "granted": 4},
	{"min": 1, "max": 3, "granted": 3},
	{"min": 4, "max": 7, "granted": 2},
	{"min": 8, "max": 10, "granted": 1},
	{"min": 11, "max": 999, "granted": 0},
]

const SUPER_HEROISM_TABLE: Array = [
	{"min": 0, "max": 0, "granted": 6},
	{"min": 1, "max": 3, "granted": 5},
	{"min": 4, "max": 7, "granted": 4},
	{"min": 8, "max": 10, "granted": 3},
	{"min": 11, "max": 12, "granted": 2},
	{"min": 13, "max": 999, "granted": 0},  # RAW silent above 12; conservative 0
]

const FIGHTER_COMBAT_PROGRESSION := "fighter"

# Save category list (canonical ACKS 5).
const SAVE_KEYS: Array = [
	"save_petrification", "save_poison_death", "save_blast_breath",
	"save_staffs_wands", "save_spells",
]


# ---------------------------------------------------------------------------
# Public predicates
# ---------------------------------------------------------------------------

## True if drinker already has any temp-duration potion active.
static func has_active_potion(drinker: CharacterData) -> bool:
	if drinker == null or drinker.flags == null:
		return false
	return drinker.flags.has_flag("has_active_potion")


## True if drinker is currently sickened by the two-potion rule.
static func is_sickened(drinker: CharacterData) -> bool:
	if drinker == null or drinker.flags == null:
		return false
	return drinker.flags.has_flag("is_sickened_by_potion")


## True if drinker qualifies as a fighter-progression user for Heroism /
## Super-Heroism. Per Jedidiah ruling 2026-06-03: gate on
## `combat_progression == "fighter"` so all fighter-progression classes
## qualify automatically.
static func is_eligible_for_heroism_family(drinker: CharacterData) -> bool:
	if drinker == null:
		return false
	return drinker.combat_progression == FIGHTER_COMBAT_PROGRESSION


# ---------------------------------------------------------------------------
# Level-table lookup (Heroism family)
# ---------------------------------------------------------------------------

static func _lookup_levels_granted(table: Array, drinker_level: int) -> int:
	for row in table:
		if drinker_level >= int(row["min"]) and drinker_level <= int(row["max"]):
			return int(row["granted"])
	return 0


static func levels_granted_for(item_key: String, drinker_level: int) -> int:
	match item_key:
		"potion_of_heroism":
			return _lookup_levels_granted(HEROISM_TABLE, drinker_level)
		"potion_of_super_heroism":
			return _lookup_levels_granted(SUPER_HEROISM_TABLE, drinker_level)
		_:
			return 0


# ---------------------------------------------------------------------------
# Two-potion sickened rule
# ---------------------------------------------------------------------------

## Applies the is_sickened_by_potion flag for SICKENED_DURATION_TURNS,
## registered with the tracker so the standard tick-expire cleanup clears
## the flag automatically.
##
## RAW (ACore general_category_rules.potions line 224):
##   "If a character drinks a second potion while one is active, the
##   character is sickened and cannot act for 3 turns; neither potion has
##   any other effect."
##
## Returns { applied: bool, expires_at_turn: int, sickened_source_id: String,
##           effect_id: String }.
static func apply_sickened(
		drinker: CharacterData,
		new_item_id: String,
		new_item_key: String,
		tracker: ActiveEffectTracker) -> Dictionary:
	if drinker == null or drinker.flags == null:
		return {"applied": false, "expires_at_turn": 0, "sickened_source_id": "", "effect_id": ""}
	var current_turn: int = _safe_get_total_turns()
	var expires_at_turn: int = current_turn + SICKENED_DURATION_TURNS
	var sickened_source_id := "%s%d" % [SICKENED_SOURCE_PREFIX, expires_at_turn]
	var active_meta: Dictionary = drinker.flags.get_flag_metadata("has_active_potion")
	var active_item_id: String = str(active_meta.get("item_id", ""))
	drinker.flags.set_flag("is_sickened_by_potion", sickened_source_id, {
		"expires_at_turn": expires_at_turn,
		"source_item_id": new_item_id,
		"source_item_key": new_item_key,
		"active_potion_item_id": active_item_id,
	})
	# Register a tracker effect so the standard cleanup callback clears the
	# flag at expiry. Effect carries `applied_flags` for the cleanup sweep.
	var effect_id := "potion_sickened_%s_%d" % [drinker.id, current_turn]
	if tracker != null:
		tracker.add_effect({
			"effect_id": effect_id,
			"spell_key": "_potion_sickened",
			"caster_id": drinker.id,
			"caster_level": 1,
			"target_ids": [drinker.id],
			"effect_type": "flag",
			"applied_modifiers": [],
			"applied_flags": [
				{"character_id": drinker.id, "flag_key": "is_sickened_by_potion",
				 "source_id": sickened_source_id},
			],
			"applied_conditions": [],
			"duration_type": "turns",
			"duration_remaining": SICKENED_DURATION_TURNS,
			"requires_concentration": false,
			"dispatch_cleanup_on_tick": true,
			"metadata": {
				"source_item_id": new_item_id,
				"active_potion_item_id": active_item_id,
			},
		})
	return {
		"applied": true,
		"expires_at_turn": expires_at_turn,
		"sickened_source_id": sickened_source_id,
		"effect_id": effect_id,
	}


# ---------------------------------------------------------------------------
# Apply: Heroism / Super-Heroism (temp combat levels)
# ---------------------------------------------------------------------------

## RAW: "Extra levels and their accompanied benefits to combat are
## temporarily granted." V1 implementation: query the drinker's class
## attack-throw + save tables at (level + extra_levels), compute the delta
## vs current values, apply as ADD modifiers (negative numbers = improvement).
## Granted temp_hp = extra_levels × hit_die_average (per character's
## class hit_die). RAW says these are "subtracted first when wounded" —
## CharacterData.apply_damage already routes damage through temp_hp first,
## so the standard damage path satisfies the RAW order automatically.
##
## Returns {
##   applied: bool,
##   refused_reason: String,             — "class_restricted" / "no_bonus_at_level" / ""
##   effect_id: String,
##   item_key: String,
##   extra_levels: int,
##   attack_throw_delta: int,
##   save_deltas: Dictionary,
##   temp_hp_granted: int,
##   duration_days: int,
##   expires_at_turn: int,
##   source_id: String,
## }
static func apply_combat_level_boost(
		drinker: CharacterData,
		item_id: String,
		item_key: String,
		class_registry: ClassRegistry,
		tracker: ActiveEffectTracker) -> Dictionary:
	var refused := {
		"applied": false, "refused_reason": "", "effect_id": "",
		"item_key": item_key, "extra_levels": 0,
		"attack_throw_delta": 0, "save_deltas": {}, "temp_hp_granted": 0,
		"duration_days": 0, "expires_at_turn": 0, "source_id": "",
	}
	if drinker == null:
		refused["refused_reason"] = "no_drinker"
		return refused
	if not is_eligible_for_heroism_family(drinker):
		refused["refused_reason"] = "class_restricted"
		return refused
	var extra_levels: int = levels_granted_for(item_key, drinker.level)
	if extra_levels <= 0:
		# RAW: high-level characters get 0 levels. The potion is still
		# consumed (caller removes the bottle), but no effect applies. The
		# `has_active_potion` flag is NOT set (no duration to track), so
		# subsequent potions don't trigger the sickened gate.
		refused["refused_reason"] = "no_bonus_at_level"
		return refused

	# Compute the at-boost combat metrics from the class progression table.
	var class_id: String = drinker.character_class
	var current_attack_throw: int = class_registry.get_attack_throw(class_id, drinker.level)
	var boosted_attack_throw: int = class_registry.get_attack_throw(
		class_id, drinker.level + extra_levels)
	var attack_throw_delta: int = boosted_attack_throw - current_attack_throw
	var current_saves: Dictionary = class_registry.get_saving_throws(class_id, drinker.level)
	var boosted_saves: Dictionary = class_registry.get_saving_throws(
		class_id, drinker.level + extra_levels)
	var save_deltas: Dictionary = {}
	for sk in ["petrification", "poison_death", "blast_breath", "staffs_wands", "spells"]:
		save_deltas[sk] = int(boosted_saves.get(sk, 0)) - int(current_saves.get(sk, 0))

	# Compute temp_hp from hit_die_average × extra_levels.
	var class_def: Dictionary = class_registry.get_class_def(class_id)
	var hit_die: String = str(class_def.get("hit_die", "1d8"))
	var hd_average: int = int(HIT_DIE_AVERAGE.get(hit_die, 4))
	var temp_hp_granted: int = hd_average * extra_levels

	var source_id := "%s%s" % [SOURCE_PREFIX, item_id]
	var current_turn: int = _safe_get_total_turns()
	# Heroism duration = 1 day = 1440 turns (1 turn = 10 min; day = 8640 round
	# = 144 turns ... wait, 60 rounds/turn × 24 hours × 60 min ÷ 10 min/turn
	# = 144 turns). Use days-typed effect so the day_changed signal expires
	# it. Turn count is informational.
	var duration_days: int = HEROISM_DURATION_DAYS
	var expires_at_turn: int = current_turn + (24 * 6) * duration_days  # 144 turns/day

	# Apply attack_throw modifier (delta is negative = improvement → add).
	if attack_throw_delta != 0 and drinker.modifiers != null:
		drinker.modifiers.add_modifier("attack_throw", {
			"source_id": source_id,
			"name": "%s combat levels" % item_key,
			"operation": "add",
			"value": attack_throw_delta,
			"stacking_group": "",
			"priority": 0,
		})

	# Apply save modifiers.
	var applied_modifier_records: Array = []
	if attack_throw_delta != 0:
		applied_modifier_records.append({
			"character_id": drinker.id, "stat_key": "attack_throw", "source_id": source_id,
		})
	if drinker.modifiers != null:
		for sk in ["petrification", "poison_death", "blast_breath", "staffs_wands", "spells"]:
			var delta: int = int(save_deltas.get(sk, 0))
			if delta == 0:
				continue
			var save_stat_key := "save_%s" % sk
			drinker.modifiers.add_modifier(save_stat_key, {
				"source_id": source_id,
				"name": "%s combat levels" % item_key,
				"operation": "add",
				"value": delta,
				"stacking_group": "",
				"priority": 0,
			})
			applied_modifier_records.append({
				"character_id": drinker.id, "stat_key": save_stat_key, "source_id": source_id,
			})

	# Grant temp_hp.
	if temp_hp_granted > 0:
		drinker.temp_hp += temp_hp_granted

	# Set the active-potion flag with full metadata.
	if drinker.flags != null:
		drinker.flags.set_flag("has_active_potion", source_id, {
			"item_id": item_id,
			"item_key": item_key,
			"expires_at_turn": expires_at_turn,
			"effect_kind": "temp_combat_levels",
			"extra_levels": extra_levels,
			"attack_throw_delta": attack_throw_delta,
			"save_deltas": save_deltas.duplicate(true),
			"applied_temp_hp": temp_hp_granted,
		})

	# Register with the tracker.
	var effect_id := "potion_combat_%s_%d" % [item_id, current_turn]
	var spell_key_sentinel: String = ("_potion_super_heroism" if item_key == "potion_of_super_heroism"
		else "_potion_heroism")
	if tracker != null:
		tracker.add_effect({
			"effect_id": effect_id,
			"spell_key": spell_key_sentinel,
			"caster_id": drinker.id,
			"caster_level": drinker.level,
			"target_ids": [drinker.id],
			"effect_type": "modifier",
			"applied_modifiers": applied_modifier_records,
			"applied_flags": [{
				"character_id": drinker.id,
				"flag_key": "has_active_potion",
				"source_id": source_id,
			}],
			"applied_conditions": [],
			"applied_temp_hp": [{
				"character_id": drinker.id,
				"amount": temp_hp_granted,
			}],
			"duration_type": "days",
			"duration_remaining": duration_days,
			"requires_concentration": false,
			"dispatch_cleanup_on_tick": true,
			"metadata": {
				"item_id": item_id,
				"item_key": item_key,
				"extra_levels": extra_levels,
			},
		})
	return {
		"applied": true,
		"refused_reason": "",
		"effect_id": effect_id,
		"item_key": item_key,
		"extra_levels": extra_levels,
		"attack_throw_delta": attack_throw_delta,
		"save_deltas": save_deltas,
		"temp_hp_granted": temp_hp_granted,
		"duration_days": duration_days,
		"expires_at_turn": expires_at_turn,
		"source_id": source_id,
	}


# ---------------------------------------------------------------------------
# Apply: Giant Strength
# ---------------------------------------------------------------------------

## RAW: "attacks as an 8 HD monster or as his own class and level, whichever
## is better." V1 reuses the Girdle pattern — set_ceiling on attack_throw at
## 3 (the 8-HD value). The "double damage / throw rocks / +16 force doors"
## sub-effects are persisted on the has_active_potion flag metadata for the
## future consumer wirings (same status as the Girdle's V1 deferral — see
## worn_magic_effect_resolver.gd:228-233 for the matching deferral notes).
## No class gate (RAW Giant Strength: no class restriction).
##
## Returns the same shape as apply_combat_level_boost.
static func apply_giant_strength(
		drinker: CharacterData,
		item_id: String,
		item_key: String,
		tracker: ActiveEffectTracker) -> Dictionary:
	var refused := {
		"applied": false, "refused_reason": "", "effect_id": "",
		"item_key": item_key, "duration_turns": 0,
		"expires_at_turn": 0, "source_id": "",
	}
	if drinker == null:
		refused["refused_reason"] = "no_drinker"
		return refused

	var source_id := "%s%s" % [SOURCE_PREFIX, item_id]
	var current_turn: int = _safe_get_total_turns()
	var duration_turns: int = GIANT_STRENGTH_DURATION_TURNS
	var expires_at_turn: int = current_turn + duration_turns

	if drinker.modifiers != null:
		drinker.modifiers.add_modifier("attack_throw", {
			"source_id": source_id,
			"name": "Potion of Giant Strength",
			"operation": "set_ceiling",
			"value": GIANT_STRENGTH_ATTACK_THROW_CEILING,
			"stacking_group": "",
			"priority": 0,
		})

	if drinker.flags != null:
		drinker.flags.set_flag("has_active_potion", source_id, {
			"item_id": item_id,
			"item_key": item_key,
			"expires_at_turn": expires_at_turn,
			"effect_kind": "giant_strength",
			"attack_throw_ceiling": GIANT_STRENGTH_ATTACK_THROW_CEILING,
			"damage_multiplier": 2.0,
			"throw_rocks_range_feet": 200,
			"throw_rocks_damage_dice": "3d6",
			"force_doors_bonus": 16,
			"blocks_other_magical_strength": true,
		})

	var effect_id := "potion_giant_strength_%s_%d" % [item_id, current_turn]
	if tracker != null:
		tracker.add_effect({
			"effect_id": effect_id,
			"spell_key": "_potion_giant_strength",
			"caster_id": drinker.id,
			"caster_level": drinker.level,
			"target_ids": [drinker.id],
			"effect_type": "modifier",
			"applied_modifiers": [{
				"character_id": drinker.id,
				"stat_key": "attack_throw",
				"source_id": source_id,
			}],
			"applied_flags": [{
				"character_id": drinker.id,
				"flag_key": "has_active_potion",
				"source_id": source_id,
			}],
			"applied_conditions": [],
			"duration_type": "turns",
			"duration_remaining": duration_turns,
			"requires_concentration": false,
			"dispatch_cleanup_on_tick": true,
			"metadata": {
				"item_id": item_id,
				"item_key": item_key,
			},
		})

	return {
		"applied": true,
		"refused_reason": "",
		"effect_id": effect_id,
		"item_key": item_key,
		"duration_turns": duration_turns,
		"expires_at_turn": expires_at_turn,
		"source_id": source_id,
	}


# ---------------------------------------------------------------------------
# Apply: Invulnerability
# ---------------------------------------------------------------------------

## RAW: "+2 to all saving throws and Armor Class. However, if a potion of
## invulnerability is quaffed more than once per week, the potion has the
## opposite effect, causing a penalty of -2 to saving throws and Armor Class!"
##
## Once-per-week tracking: consult the persistent
## `last_invulnerability_quaff_day` flag. If set and current_day - last_day
## < 7, apply -2 (inverted). Otherwise apply +2.
##
## The tracker (last-quaff-day flag) is ALWAYS updated to the current day on
## quaff — even on inversion — so the next quaff after the inverted effect
## also measures against the most-recent attempt. This matches the RAW
## "more than once per week" phrasing (any quaff within the prior 7 days
## inverts the result).
##
## Returns {
##   applied: bool,
##   refused_reason: String,
##   effect_id: String,
##   item_key: String,
##   inverted: bool,            — true if RAW negative inversion applied
##   ac_delta: int,             — +2 or -2
##   save_delta: int,           — +2 or -2 (same magnitude, applied to all 5 saves)
##   duration_turns: int,
##   expires_at_turn: int,
##   source_id: String,
## }
static func apply_invulnerability(
		drinker: CharacterData,
		item_id: String,
		item_key: String,
		tracker: ActiveEffectTracker,
		duration_override_turns: int = -1) -> Dictionary:
	var refused := {
		"applied": false, "refused_reason": "", "effect_id": "",
		"item_key": item_key, "inverted": false,
		"ac_delta": 0, "save_delta": 0,
		"duration_turns": 0, "expires_at_turn": 0, "source_id": "",
	}
	if drinker == null:
		refused["refused_reason"] = "no_drinker"
		return refused

	var current_day: int = _safe_get_total_days()
	var current_turn: int = _safe_get_total_turns()
	var inverted: bool = false
	if drinker.flags != null and drinker.flags.has_flag("last_invulnerability_quaff_day"):
		var tracker_meta: Dictionary = drinker.flags.get_flag_metadata(
			"last_invulnerability_quaff_day")
		var last_day: int = int(tracker_meta.get("day_number", -INVULNERABILITY_WEEK_DAYS))
		if current_day - last_day < INVULNERABILITY_WEEK_DAYS:
			inverted = true

	var ac_delta: int = INVULNERABILITY_PENALTY if inverted else INVULNERABILITY_BONUS
	var save_delta: int = INVULNERABILITY_PENALTY if inverted else INVULNERABILITY_BONUS
	# AC modifiers are ADDED via the standard modifier path (armor_class
	# operation=add). Saves use a positive delta where "lower = better" in
	# the ACKS save model, so a +2 BONUS is a -2 ADD (subtracts from save
	# target). Likewise the inversion -2 PENALTY adds +2 to save targets.
	var save_modifier_value: int = -save_delta  # ACKS lower-is-better axis

	var duration_turns: int = (duration_override_turns if duration_override_turns > 0
		else INVULNERABILITY_DURATION_TURNS_DEFAULT)
	var expires_at_turn: int = current_turn + duration_turns

	var source_id := "%s%s" % [SOURCE_PREFIX, item_id]

	# Apply armor_class modifier.
	# NB: ACKS armor_class is ASCENDING (higher = better), so +2 AC = add +2.
	# This is OPPOSITE to attack_throw / save axes (where lower = better).
	var applied_modifier_records: Array = []
	if drinker.modifiers != null:
		drinker.modifiers.add_modifier("armor_class", {
			"source_id": source_id,
			"name": "Potion of Invulnerability",
			"operation": "add",
			"value": ac_delta,
			"stacking_group": "",
			"priority": 0,
		})
		applied_modifier_records.append({
			"character_id": drinker.id, "stat_key": "armor_class", "source_id": source_id,
		})
		# Apply per-save modifiers (lower-is-better axis).
		for sk_full in SAVE_KEYS:
			drinker.modifiers.add_modifier(sk_full, {
				"source_id": source_id,
				"name": "Potion of Invulnerability",
				"operation": "add",
				"value": save_modifier_value,
				"stacking_group": "",
				"priority": 0,
			})
			applied_modifier_records.append({
				"character_id": drinker.id, "stat_key": sk_full, "source_id": source_id,
			})

	if drinker.flags != null:
		drinker.flags.set_flag("has_active_potion", source_id, {
			"item_id": item_id,
			"item_key": item_key,
			"expires_at_turn": expires_at_turn,
			"effect_kind": "invulnerability",
			"inverted": inverted,
			"ac_delta": ac_delta,
			"save_delta": save_delta,
		})
		# Always update the weekly tracker to current day. Source_id is
		# constant so the flag is single-source and overwrites prior values.
		drinker.flags.set_flag("last_invulnerability_quaff_day",
			INVULNERABILITY_TRACKER_SOURCE, {
				"day_number": current_day,
				"item_id": item_id,
				"item_key": item_key,
			})

	var effect_id := "potion_invulnerability_%s_%d" % [item_id, current_turn]
	if tracker != null:
		tracker.add_effect({
			"effect_id": effect_id,
			"spell_key": "_potion_invulnerability",
			"caster_id": drinker.id,
			"caster_level": drinker.level,
			"target_ids": [drinker.id],
			"effect_type": "modifier",
			"applied_modifiers": applied_modifier_records,
			"applied_flags": [{
				"character_id": drinker.id,
				"flag_key": "has_active_potion",
				"source_id": source_id,
			}],
			"applied_conditions": [],
			"duration_type": "turns",
			"duration_remaining": duration_turns,
			"requires_concentration": false,
			"dispatch_cleanup_on_tick": true,
			"metadata": {
				"item_id": item_id,
				"item_key": item_key,
				"inverted": inverted,
			},
		})
	return {
		"applied": true,
		"refused_reason": "",
		"effect_id": effect_id,
		"item_key": item_key,
		"inverted": inverted,
		"ac_delta": ac_delta,
		"save_delta": save_delta,
		"duration_turns": duration_turns,
		"expires_at_turn": expires_at_turn,
		"source_id": source_id,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Reads Timekeeping.get_total_turns(). Tests can pre-advance the clock via
## Timekeeping.advance_turns(N) before calling apply_*; outside test_runner
## this is always available because Timekeeping is a registered autoload.
static func _safe_get_total_turns() -> int:
	return Timekeeping.get_total_turns()


## Reads Timekeeping.get_total_days(). See `_safe_get_total_turns`.
static func _safe_get_total_days() -> int:
	return Timekeeping.get_total_days()
