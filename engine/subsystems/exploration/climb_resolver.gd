class_name ClimbResolver
extends RefCounted

## SHEER_SURFACE_CLIMB — reusable sheer-surface climb resolution (cliffs now, dungeon
## walls later). See gdd-cliffs-canyons.md §5. This is PURE logic: the caller supplies
## already-loaded climbers (CharacterData) and the party's POOLED gear counts, so the
## resolver stays decoupled from travel/DB concerns and is fully unit-testable headless.
##
## Two responsibilities:
##   1. The party GATE (evaluate_gate) — can the party attempt this cliff at all?
##      Needs a Mountaineering holder + the per-climber gear (§2a house rule). Returns a
##      shortfall list when gear is short. Mercenaries present → refuse (not modeled yet).
##   2. The per-climber RESOLUTION (resolve_climb) — Climb-Walls throws per 100' against
##      the climber's thief-level target; on a failure, a fall of (½ the attempted segment
##      + distance already climbed), 1d6 per 10' fallen (acore_core_classes.xml:1447-1450).
##
## The resolver only COMPUTES outcomes (deterministic). Applying fall damage / persisting
## HP / narrating is the caller's job (engine-first, narrate retroactively).

# ---------------------------------------------------------------------------
# Canonical gear requirement keys (what evaluate_gate's required/pooled dicts use).
# The travel-integration layer maps catalog item_keys onto these buckets:
#   GEAR_ROPE           <- rope_50ft  (count of 50' ropes)
#   GEAR_SPIKES         <- iron_spikes_12 quantity × 12  (INDIVIDUAL spikes)
#   GEAR_HAMMER         <- hammer_small + warhammer  (iron-spike drivers; a MALLET drives
#                          wooden stakes only and does NOT count — base_equipment.json:100)
#   GEAR_GRAPPLE        <- grappling_hook
# ---------------------------------------------------------------------------
const GEAR_ROPE := "rope_50ft"
const GEAR_SPIKES := "iron_spikes"
const GEAR_HAMMER := "hammer"
const GEAR_GRAPPLE := "grappling_hook"

# Per-climber requirement: 1 rope, ceil(height/50) spikes, 1 hammer, +1 grappling hook
# unless a party member has Climbing or is a Thief (§2a).
const FEET_PER_SPIKE := 50
const FEET_PER_THROW := 100
const FEET_PER_FALL_DIE := 10

# Proficiency keys + combat progression (proficiency_catalog.json:646/2401, CharacterData).
const PROF_MOUNTAINEERING := "mountaineering"
const PROF_CLIMBING := "climbing"
const PROGRESSION_THIEF := "thief"

# Gate outcome reasons.
const REASON_OK := "ok"
const REASON_NO_CLIMBERS := "no_climbers"
const REASON_NO_MOUNTAINEERING := "no_mountaineering"
const REASON_MERCENARIES := "mercenaries_present"
const REASON_INSUFFICIENT_GEAR := "insufficient_gear"

# climb_walls thief target-by-level, lazily loaded from data/classes/thief.json (single
# source of truth — the SACRED progression table). Roll-high: 1d20 >= target.
const THIEF_CLASS_PATH := "res://data/classes/thief.json"
const CLIMB_POWER_ID := "climb_walls"
static var _climb_targets: Dictionary = {}


# ---------------------------------------------------------------------------
# Gear math (pure, static)
# ---------------------------------------------------------------------------

## True unless some climber has the Climbing proficiency or is a Thief — in which case the
## party can improvise anchors and the grappling hook is not required (§2a).
static func grapple_required(climbers: Array) -> bool:
	for c in climbers:
		if c == null:
			continue
		if c.has_proficiency(PROF_CLIMBING) or str(c.combat_progression) == PROGRESSION_THIEF:
			return false
	return true


## Per-climber × N-climber gear requirement (individual spikes), keyed by GEAR_* (§2a).
static func required_gear(n_climbers: int, height_ft: int, grapple_needed: bool) -> Dictionary:
	# ceil() here is RAW-style discretisation (one stake per started 50' / one throw per
	# started 100'), NOT a rounded average — so ceili, not banker's (conventions §12 / §3.3).
	var spikes_per_climber: int = ceili(float(max(0, height_ft)) / float(FEET_PER_SPIKE))
	return {
		GEAR_ROPE: n_climbers,
		GEAR_SPIKES: n_climbers * spikes_per_climber,
		GEAR_HAMMER: n_climbers,
		GEAR_GRAPPLE: n_climbers if grapple_needed else 0,
	}


## Evaluate whether the party may ATTEMPT the climb. [param climbers]: Array[CharacterData]
## (PCs + henchmen making the climb). [param pooled_gear]: {GEAR_* : int} pooled across the
## party (spikes already in INDIVIDUAL units). [param has_mercenaries]: refuse if true.
## Returns {allowed, reason, n_climbers, required, shortfall, grapple_needed}.
static func evaluate_gate(climbers: Array, pooled_gear: Dictionary, height_ft: int,
		has_mercenaries: bool) -> Dictionary:
	if has_mercenaries:
		return {"allowed": false, "reason": REASON_MERCENARIES, "n_climbers": climbers.size(),
			"required": {}, "shortfall": {}}
	if climbers.is_empty():
		return {"allowed": false, "reason": REASON_NO_CLIMBERS, "n_climbers": 0,
			"required": {}, "shortfall": {}}
	var has_mountaineering := false
	for c in climbers:
		if c != null and c.has_proficiency(PROF_MOUNTAINEERING):
			has_mountaineering = true
			break
	if not has_mountaineering:
		# No list — the party simply cannot take a cliff without Mountaineering; route around.
		return {"allowed": false, "reason": REASON_NO_MOUNTAINEERING, "n_climbers": climbers.size(),
			"required": {}, "shortfall": {}}
	var grapple_needed := grapple_required(climbers)
	var required := required_gear(climbers.size(), height_ft, grapple_needed)
	var shortfall: Dictionary = {}
	for key in required:
		var need: int = int(required[key])
		var have: int = int(pooled_gear.get(key, 0))
		if have < need:
			shortfall[key] = need - have
	if not shortfall.is_empty():
		return {"allowed": false, "reason": REASON_INSUFFICIENT_GEAR, "n_climbers": climbers.size(),
			"required": required, "shortfall": shortfall, "grapple_needed": grapple_needed}
	return {"allowed": true, "reason": REASON_OK, "n_climbers": climbers.size(),
		"required": required, "shortfall": {}, "grapple_needed": grapple_needed}


## Format a player-facing shortfall line in Jedidiah's order/style, e.g.
## "Not enough gear — you require: grappling hooks: 2, iron spikes: 4, hammers: 1, 50' rope: 1".
static func shortfall_message(shortfall: Dictionary) -> String:
	var order := [GEAR_GRAPPLE, GEAR_SPIKES, GEAR_HAMMER, GEAR_ROPE]
	var labels := {
		GEAR_GRAPPLE: "grappling hooks",
		GEAR_SPIKES: "iron spikes",
		GEAR_HAMMER: "hammers",
		GEAR_ROPE: "50' rope",
	}
	var parts: Array[String] = []
	for key in order:
		if shortfall.has(key) and int(shortfall[key]) > 0:
			parts.append("%s: %d" % [labels[key], int(shortfall[key])])
	if parts.is_empty():
		return ""
	return "Not enough gear — you require: " + ", ".join(parts)


# ---------------------------------------------------------------------------
# Climb resolution math (pure, static)
# ---------------------------------------------------------------------------

## Climb-Walls target (roll-high) for an effective thief level, clamped 1..14, from the
## SACRED thief progression in data/classes/thief.json. Returns 99 (impossible) if the
## table can't be read — never silently "auto-succeeds".
static func climb_target(level: int) -> int:
	var lvl: int = clampi(level, 1, 14)
	var table := _climb_target_table()
	return int(table.get(lvl, 99))


## Number of Climb-Walls throws for a height (one per started 100' — acore:1447).
static func throw_count(height_ft: int) -> int:
	return maxi(1, ceili(float(max(0, height_ft)) / float(FEET_PER_THROW)))


## Fall distance on a failed throw: half the attempted segment + distance already climbed
## (acore:1448). Banker's-rounds the half-segment (a final segment can be odd).
static func fall_distance(segment_ft: int, climbed_so_far_ft: int) -> int:
	return climbed_so_far_ft + XPAwardCalculator.bankers_round(float(segment_ft) / 2.0)


## Falling-damage dice: 1d6 per 10' fallen (acore:1449), at least 1d6. Banker's-rounds a
## fractional final 10' (RAW doesn't specify; banker's per conventions §12).
static func fall_damage_dice(fall_ft: int) -> int:
	return maxi(1, XPAwardCalculator.bankers_round(float(fall_ft) / float(FEET_PER_FALL_DIE)))


## Resolve ONE climber's attempt at a [param height_ft] cliff. Rolls a Climb-Walls throw per
## 100' segment; on the first failure the climber falls and takes 1d6/10' damage and the
## climb ends. [param roll_fn]: optional Callable(sides:int, count:int) -> int for
## deterministic tests; defaults to DiceSystem. Returns:
##   {success, level, target, climbed_ft, segments, throws:[{roll,target,success,segment}],
##    fell: bool, fall_ft, damage_dice, damage}
## On success `fell` is false and damage 0.
static func resolve_climb(climber: CharacterData, height_ft: int, roll_fn: Callable = Callable()) -> Dictionary:
	var level: int = climber.get_effective_level() if climber != null else 1
	var target: int = climb_target(level)
	var n_throws: int = throw_count(height_ft)
	var throws: Array = []
	var climbed: int = 0
	var remaining: int = max(0, height_ft)
	for i in range(n_throws):
		var seg: int = mini(FEET_PER_THROW, remaining)
		if seg <= 0:
			break
		var die: int = _roll(roll_fn, 20, 1)
		# Roll-high vs target; nat 20 always succeeds, nat 1 always fails (acore:1414-1418).
		var success: bool = (die == 20) or (die != 1 and die >= target)
		throws.append({"roll": die, "target": target, "success": success, "segment": seg})
		if not success:
			var fall_ft: int = fall_distance(seg, climbed)
			var dice: int = fall_damage_dice(fall_ft)
			var damage: int = _roll(roll_fn, 6, dice)
			return {
				"success": false, "level": level, "target": target, "climbed_ft": climbed,
				"segments": n_throws, "throws": throws, "fell": true, "fall_ft": fall_ft,
				"damage_dice": dice, "damage": damage,
			}
		climbed += seg
		remaining -= seg
	return {
		"success": true, "level": level, "target": target, "climbed_ft": climbed,
		"segments": n_throws, "throws": throws, "fell": false, "fall_ft": 0,
		"damage_dice": 0, "damage": 0,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _roll(roll_fn: Callable, sides: int, count: int) -> int:
	if roll_fn.is_valid():
		return int(roll_fn.call(sides, count))
	# Default: DiceSystem digital roll (no modifier); modified_total == raw sum.
	var result: RollResult = DiceSystem.roll_digital(sides, count, 0, "sheer_surface_climb")
	return int(result.modified_total)


## Lazily load + cache the climb_walls target-by-level table from the thief class JSON.
static func _climb_target_table() -> Dictionary:
	if not _climb_targets.is_empty():
		return _climb_targets
	var f := FileAccess.open(THIEF_CLASS_PATH, FileAccess.READ)
	if f == null:
		push_error("ClimbResolver: cannot open %s" % THIEF_CLASS_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("ClimbResolver: %s is not a JSON object" % THIEF_CLASS_PATH)
		return {}
	var powers: Variant = (parsed as Dictionary).get("class_powers", [])
	if not (powers is Array):
		# Tolerate alternate key names for the power list.
		powers = (parsed as Dictionary).get("powers", [])
	for power in powers:
		if power is Dictionary and str(power.get("power_id", "")) == CLIMB_POWER_ID:
			var progression: Variant = power.get("progression", {})
			if progression is Dictionary:
				for level_key in (progression as Dictionary).keys():
					_climb_targets[int(level_key)] = int((progression as Dictionary)[level_key])
			break
	if _climb_targets.is_empty():
		push_error("ClimbResolver: climb_walls progression not found in %s" % THIEF_CLASS_PATH)
	return _climb_targets
