class_name SiegeReductionResolver
extends RefCounted

## Reduction sub-resolver per rules/daw_sieges.xml §reduction L195-463.
##
## Covers:
##   - Bombardment (artillery → daily shp damage; ammunition costs)
##   - Artillery duels (1d6/2d6 hit rolls)
##   - Magic (spell → flat or hp/5 shp damage)
##   - Hijinks: arson (4d6×10 shp/level; ÷10 if stone)
##              subversion (1 breach, must be exploited same day)
##   - Stronghold repair (overnight; wood 5 shp/cp/100, stone 1 shp/cp/100;
##                        cumulative cap = 50% of damage_dealt_total)
##
## Siege-mining lives in siege_mining_resolver.gd (separate module due to size).
##
## Deltas are applied via SiegeRepository.update + SiegeRepository.append_action;
## breach_count is recomputed from damage_dealt_total each tick by the main
## SiegeResolver (this module just updates totals and lets the main resolver
## reconcile breach_count via UnitCapacityCalculator.breach_count_from_damage).

const _ARTILLERY_TABLE_PATH := "res://data/siege/artillery_table.json"
static var _artillery_table: Dictionary = {}

# RAW §magic.reduction_by_magic L342-385
const MAGIC_DAMAGE_TABLE := {
	"cone_of_cold":          {"hp_to_shp_divisor": 5,    "flat_shp": 0,    "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": false, "shp_per_turn": 0},
	"disintegrate":          {"hp_to_shp_divisor": 0,    "flat_shp": 125,  "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": false, "shp_per_turn": 0},
	"fireball":              {"hp_to_shp_divisor": 5,    "flat_shp": 0,    "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": false, "shp_per_turn": 0},
	"flame_strike":          {"hp_to_shp_divisor": 5,    "flat_shp": 0,    "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": false, "shp_per_turn": 0},
	"horn_of_blasting":      {"hp_to_shp_divisor": 0,    "flat_shp": 125,  "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": false, "shp_per_turn": 0},
	"lightning_bolt":        {"hp_to_shp_divisor": 5,    "flat_shp": 0,    "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": false, "shp_per_turn": 0},
	"move_earth":            {"hp_to_shp_divisor": 0,    "flat_shp": 0,    "blocked_on_solid_rock_unless_rock_to_mud": true,  "halves_recover_on_dispel": false, "shp_per_turn": 1500},
	"searing_wind":          {"hp_to_shp_divisor": 5,    "flat_shp": 0,    "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": false, "shp_per_turn": 0},
	"transmute_rock_to_mud": {"hp_to_shp_divisor": 0,    "flat_shp": 625,  "blocked_on_solid_rock_unless_rock_to_mud": false, "halves_recover_on_dispel": true,  "shp_per_turn": 0},
}

# RAW §stronghold_repair L455-462
const REPAIR_SHP_PER_GP_WOOD: int = 5            # L458 (5 shp / 1 gp = 5 shp / 100 cp)
const REPAIR_SHP_PER_GP_STONE: int = 1           # L459
const REPAIR_CAP_FRACTION: float = 0.5           # L460: half of damage taken during siege

# RAW §arson L432-435
const ARSON_BASE_SHP_MULTIPLIER: int = 10        # L433: 4d6 × 10 shp per class level
const ARSON_STONE_DIVISOR: int = 10              # L435: damage ÷ 10 if stone


# ---------------------------------------------------------------------------
# Bombardment
# ---------------------------------------------------------------------------

## Tick a single day of bombardment from all besieger artillery.
## Returns: {total_damage_dealt, ammo_cost_cp, per_piece_breakdown}
## Also persists damage_dealt_total += total_damage_dealt and appends a
## 'bombardment' action row.
##
## v1: defender artillery does not bombard back as a separate tick — defender
## artillery is consumed during artillery duels (run separately via
## run_artillery_duel) and during the assault step.
static func tick_bombardment(siege_id: String, day: int, dice_roller: Callable = Callable()) -> Dictionary:
	_ensure_table_loaded()
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"total_damage_dealt": 0, "ammo_cost_cp": 0, "per_piece_breakdown": []}
	var material: String = String(siege.get("material", "stone"))
	var pieces: Array = SiegeRepository.list_artillery(siege_id, "besieger")
	var equipment_catalog: Dictionary = _artillery_table.get("equipment", {})
	var total_damage: int = 0
	var total_ammo_cost: int = 0
	var breakdown: Array = []
	for piece in pieces:
		var equipment_type: String = String(piece.get("equipment_type", ""))
		var count: int = int(piece.get("count", 0))
		if count <= 0 or equipment_type.is_empty():
			continue
		var entry: Dictionary = equipment_catalog.get(equipment_type, {})
		if entry.is_empty():
			continue
		var per_piece_damage: int = 0
		if material == "wood":
			var v: Variant = entry.get("daily_damage_vs_wood", null)
			if v != null:
				per_piece_damage = int(v)
		else:
			var v2: Variant = entry.get("daily_damage_vs_stone", null)
			if v2 != null:
				per_piece_damage = int(v2)
		if per_piece_damage <= 0:
			continue
		var ammo_per_piece: int = int(entry.get("daily_ammo_cost_cp", 0))
		var damage: int = per_piece_damage * count
		var ammo: int = ammo_per_piece * count
		total_damage += damage
		total_ammo_cost += ammo
		breakdown.append({
			"equipment_type": equipment_type,
			"count": count,
			"per_piece_damage": per_piece_damage,
			"total_damage": damage,
			"ammo_cost_cp": ammo,
		})
	if total_damage > 0:
		var new_dealt: int = int(siege.get("damage_dealt_total", 0)) + total_damage
		var new_shp: int = maxi(0, int(siege.get("starting_shp", 0)) - new_dealt + int(siege.get("damage_repaired_total", 0)))
		var new_breaches: int = UnitCapacityCalculator.breach_count_from_damage(new_dealt)
		var prev_breaches: int = int(siege.get("breach_count", 0))
		SiegeRepository.update(siege_id, {
			"damage_dealt_total": new_dealt,
			"current_shp": new_shp,
			"breach_count": new_breaches,
		})
		SiegeRepository.append_action(siege_id, day, "besieger", "bombardment",
			{"shp_damage_dealt": total_damage, "breaches_added": new_breaches - prev_breaches},
			{"breakdown": breakdown, "ammo_cost_cp": total_ammo_cost,
			 "shp_after": new_shp, "damage_dealt_total_after": new_dealt}
		)
		if new_breaches > prev_breaches and EventBus.has_signal("siege_breach_created"):
			EventBus.emit_signal("siege_breach_created", siege_id, new_breaches, "bombardment")
	return {
		"total_damage_dealt": total_damage,
		"ammo_cost_cp": total_ammo_cost,
		"per_piece_breakdown": breakdown,
	}


# ---------------------------------------------------------------------------
# Artillery duel
# ---------------------------------------------------------------------------

## Run one round of an artillery duel per RAW §artillery_duels L222-248.
##
## Per the 14-step procedure:
##   1. Each side rolls 1d6/ballista, 1d6/catapult, 2d6/trebuchet.
##   2. Besieger hits on 6.
##   3. Defender hits on 5-6 (5 misses if besieger has cover).
##   4. Heavy trebuchet requires 2 hits to destroy.
##   5. Hits target artillery within range (lower-range pieces hit by higher-range).
##   6. Apply hits simultaneously.
##   7. Withdraw decision: lower-strategic-ability decides first.
##
## Returns: {besieger_hits, defender_hits, besieger_destroyed, defender_destroyed,
##           per_die_rolls}
##
## v1 simplification: range cascade is implemented as "any artillery hit is
## consumed by any opposing piece"; per-piece range targeting is deferred until
## artillery has explicit position state. Defender-cover flag is read from
## sieges.payload_json["besieger_has_cover_for_artillery"] (default false).
## Hits are applied via SiegeRepository.mark_destroyed (count -= hit) within
## this function; partial-destruction of a multi-piece group is supported.
static func run_artillery_duel(siege_id: String, day: int, dice_roller: Callable = Callable()) -> Dictionary:
	_ensure_table_loaded()
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {}
	var equipment_catalog: Dictionary = _artillery_table.get("equipment", {})
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	var besieger_has_cover: bool = bool(payload.get("besieger_has_cover_for_artillery", false))

	var besieger_pieces: Array = SiegeRepository.list_artillery(siege_id, "besieger")
	var defender_pieces: Array = SiegeRepository.list_artillery(siege_id, "defender")

	var besieger_dice: Array = _roll_duel_dice(besieger_pieces, equipment_catalog, dice_roller)
	var defender_dice: Array = _roll_duel_dice(defender_pieces, equipment_catalog, dice_roller)

	# Count hits.
	var besieger_hits: int = 0
	for d in besieger_dice:
		if int(d) >= 6:  # besieger hits on 6
			besieger_hits += 1
	var defender_hits: int = 0
	for d in defender_dice:
		var v: int = int(d)
		if v >= 6:
			defender_hits += 1
		elif v == 5 and not besieger_has_cover:
			defender_hits += 1

	# Apply hits to opposing pieces. Heavy trebuchets need 2 hits each.
	var besieger_destroyed: Array = _apply_duel_hits(siege_id, defender_pieces, defender_hits, equipment_catalog)
	var defender_destroyed: Array = _apply_duel_hits(siege_id, besieger_pieces, besieger_hits, equipment_catalog)

	SiegeRepository.append_action(siege_id, day, "besieger", "artillery_duel",
		{},
		{
			"besieger_dice": besieger_dice,
			"defender_dice": defender_dice,
			"besieger_hits": besieger_hits,
			"defender_hits": defender_hits,
			"besieger_destroyed_artillery_ids": besieger_destroyed,
			"defender_destroyed_artillery_ids": defender_destroyed,
			"besieger_has_cover": besieger_has_cover,
		}
	)
	return {
		"besieger_hits": besieger_hits,
		"defender_hits": defender_hits,
		"besieger_destroyed": besieger_destroyed,
		"defender_destroyed": defender_destroyed,
		"per_die_rolls": {"besieger": besieger_dice, "defender": defender_dice},
	}


# ---------------------------------------------------------------------------
# Magic
# ---------------------------------------------------------------------------

## Apply magic-based reduction. RAW §magic L328-386.
##   spell: a key from MAGIC_DAMAGE_TABLE.
##   hp_damage: caster's hp damage roll for hp/5 spells; ignored for flat or shp_per_turn.
##   turns: for move_earth, # of turns of action.
##
## Per RAW §move_earth L336-340: cannot directly affect worked stone unless
## transmute_rock_to_mud is used first. Caller is responsible for sequencing.
##
## Returns: {shp_damage_dealt, blocked, reason}
static func apply_magic(siege_id: String, spell: String, day: int, hp_damage: int = 0, turns: int = 1) -> Dictionary:
	if not MAGIC_DAMAGE_TABLE.has(spell):
		return {"shp_damage_dealt": 0, "blocked": true, "reason": "unknown_spell"}
	var entry: Dictionary = MAGIC_DAMAGE_TABLE[spell]
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"shp_damage_dealt": 0, "blocked": true, "reason": "siege_not_found"}
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	var on_solid_rock: bool = bool(payload.get("on_solid_rock", false))
	var rock_to_mud_applied: bool = bool(payload.get("rock_to_mud_applied_today", false))
	if bool(entry.get("blocked_on_solid_rock_unless_rock_to_mud", false)) and on_solid_rock and not rock_to_mud_applied:
		return {"shp_damage_dealt": 0, "blocked": true, "reason": "solid_rock_no_rock_to_mud"}
	# Compute damage.
	var shp_damage: int = 0
	if int(entry.get("flat_shp", 0)) > 0:
		shp_damage = int(entry.get("flat_shp"))
	elif int(entry.get("hp_to_shp_divisor", 0)) > 0:
		shp_damage = hp_damage / int(entry.get("hp_to_shp_divisor"))
	elif int(entry.get("shp_per_turn", 0)) > 0:
		shp_damage = int(entry.get("shp_per_turn")) * maxi(1, turns)
	if shp_damage <= 0:
		return {"shp_damage_dealt": 0, "blocked": false, "reason": "no_effect"}
	# Apply.
	var new_dealt: int = int(siege.get("damage_dealt_total", 0)) + shp_damage
	var new_shp: int = maxi(0, int(siege.get("starting_shp", 0)) - new_dealt + int(siege.get("damage_repaired_total", 0)))
	var new_breaches: int = UnitCapacityCalculator.breach_count_from_damage(new_dealt)
	var prev_breaches: int = int(siege.get("breach_count", 0))
	# transmute_rock_to_mud sets the same-day flag for follow-up move_earth.
	if spell == "transmute_rock_to_mud":
		payload["rock_to_mud_applied_today"] = true
		SiegeRepository.update(siege_id, {
			"damage_dealt_total": new_dealt, "current_shp": new_shp,
			"breach_count": new_breaches, "payload_json": JSON.stringify(payload),
		})
	else:
		SiegeRepository.update(siege_id, {
			"damage_dealt_total": new_dealt, "current_shp": new_shp,
			"breach_count": new_breaches,
		})
	SiegeRepository.append_action(siege_id, day, "besieger", "magic_reduction",
		{"shp_damage_dealt": shp_damage, "breaches_added": new_breaches - prev_breaches},
		{"spell": spell, "hp_damage": hp_damage, "turns": turns,
		 "halves_recover_on_dispel": entry.get("halves_recover_on_dispel", false)}
	)
	if new_breaches > prev_breaches and EventBus.has_signal("siege_breach_created"):
		EventBus.emit_signal("siege_breach_created", siege_id, new_breaches, "magic")
	return {"shp_damage_dealt": shp_damage, "blocked": false, "reason": ""}


# ---------------------------------------------------------------------------
# Repair
# ---------------------------------------------------------------------------

## Defender repair during evening of a siege day per RAW §stronghold_repair L455-462.
##   wood: 5 shp / gp construction rate (5 shp / 100 cp)
##   stone: 1 shp / gp (1 shp / 100 cp)
##   Cap: damage_repaired_total ≤ 0.5 × damage_dealt_total (CONFIRMED 2026-05-09
##   cumulative across the entire siege).
##
## Returns: {shp_repaired, cp_spent_effective, capped, reason}
static func repair_overnight(siege_id: String, day: int, cp_to_spend: int) -> Dictionary:
	if cp_to_spend <= 0:
		return {"shp_repaired": 0, "cp_spent_effective": 0, "capped": false, "reason": "no_budget"}
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"shp_repaired": 0, "cp_spent_effective": 0, "capped": false, "reason": "siege_not_found"}
	var material: String = String(siege.get("material", "stone"))
	var damage_dealt: int = int(siege.get("damage_dealt_total", 0))
	var damage_repaired: int = int(siege.get("damage_repaired_total", 0))
	var max_repair_total: int = int(floor(float(damage_dealt) * REPAIR_CAP_FRACTION))
	var cap_remaining: int = maxi(0, max_repair_total - damage_repaired)
	if cap_remaining <= 0:
		return {"shp_repaired": 0, "cp_spent_effective": 0, "capped": true, "reason": "cap_reached"}
	var shp_per_cp_x100: int = REPAIR_SHP_PER_GP_WOOD if material == "wood" else REPAIR_SHP_PER_GP_STONE
	# shp_per_cp = shp_per_gp / 100.  shp_repaired = cp_to_spend * shp_per_gp / 100.
	@warning_ignore("integer_division")
	var shp_to_repair: int = cp_to_spend * shp_per_cp_x100 / 100
	var capped: bool = false
	if shp_to_repair > cap_remaining:
		shp_to_repair = cap_remaining
		capped = true
	if shp_to_repair <= 0:
		return {"shp_repaired": 0, "cp_spent_effective": 0, "capped": false, "reason": "below_cp_per_shp"}
	var cp_spent_effective: int = (shp_to_repair * 100 + (shp_per_cp_x100 - 1)) / shp_per_cp_x100
	# Apply.
	var new_repaired: int = damage_repaired + shp_to_repair
	var new_shp: int = maxi(0, int(siege.get("starting_shp", 0)) - damage_dealt + new_repaired)
	# Repair does NOT reduce breach_count (per RAW: breach is opened by damage; the
	# defender can repair structural HP but breaches once made remain exploitable
	# until the assault is over). v1 follows the conservative reading: breach_count
	# stays at floor(damage_dealt / 1000); a Phase 9C polish item could refine.
	SiegeRepository.update(siege_id, {
		"damage_repaired_total": new_repaired,
		"current_shp": new_shp,
	})
	SiegeRepository.append_action(siege_id, day, "defender", "repair",
		{"shp_repaired": shp_to_repair},
		{"cp_spent": cp_spent_effective, "material": material,
		 "cap_remaining_after": cap_remaining - shp_to_repair, "capped": capped}
	)
	return {"shp_repaired": shp_to_repair, "cp_spent_effective": cp_spent_effective,
	        "capped": capped, "reason": ""}


# ---------------------------------------------------------------------------
# Hijinks: arson + subversion
# ---------------------------------------------------------------------------

## Attempt arson per RAW §arson L424-437. Damage = 4d6 × 10 shp per class level
## (÷ 10 if stone). Caller decides class_level + roll-pass; this method assumes
## the throw succeeded and applies damage.
static func attempt_arson(siege_id: String, day: int, perpetrator_class_level: int, dice_roller: Callable = Callable(), extra_damage_multiplier: int = 1) -> Dictionary:
	if perpetrator_class_level <= 0:
		return {"shp_damage_dealt": 0, "reason": "invalid_level"}
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"shp_damage_dealt": 0, "reason": "siege_not_found"}
	var material: String = String(siege.get("material", "stone"))
	# 4d6 × 10 per class level; extra_damage_multiplier scales for the L434 +X penalty path.
	var dice_total: int = 0
	for _level in range(perpetrator_class_level * extra_damage_multiplier):
		dice_total += _roll_dice(dice_roller, 4, 6)
	var raw_damage: int = dice_total * ARSON_BASE_SHP_MULTIPLIER
	var damage: int = raw_damage if material == "wood" else int(floor(float(raw_damage) / float(ARSON_STONE_DIVISOR)))
	if damage <= 0:
		return {"shp_damage_dealt": 0, "reason": "rolled_zero"}
	var new_dealt: int = int(siege.get("damage_dealt_total", 0)) + damage
	var new_shp: int = maxi(0, int(siege.get("starting_shp", 0)) - new_dealt + int(siege.get("damage_repaired_total", 0)))
	var new_breaches: int = UnitCapacityCalculator.breach_count_from_damage(new_dealt)
	var prev_breaches: int = int(siege.get("breach_count", 0))
	SiegeRepository.update(siege_id, {
		"damage_dealt_total": new_dealt, "current_shp": new_shp, "breach_count": new_breaches,
	})
	SiegeRepository.append_action(siege_id, day, "besieger", "arson",
		{"shp_damage_dealt": damage, "breaches_added": new_breaches - prev_breaches},
		{"perpetrator_class_level": perpetrator_class_level, "dice_total": dice_total,
		 "raw_damage": raw_damage, "material": material}
	)
	if new_breaches > prev_breaches and EventBus.has_signal("siege_breach_created"):
		EventBus.emit_signal("siege_breach_created", siege_id, new_breaches, "arson")
	return {"shp_damage_dealt": damage, "reason": ""}


## Attempt subversion per RAW §subversion L439-452. Each successful throw creates
## 1 breach. The breach must be exploited with an assault on the SAME calendar_day
## (CONFIRMED 2026-05-09); otherwise it decrements at the next daily tick.
##
## breach_count is incremented and the pending-breach reaper key is stamped on
## sieges.payload_json["pending_subversion_breach_until_day"] = day.
static func attempt_subversion(siege_id: String, day: int, additional_breaches: int = 1) -> Dictionary:
	if additional_breaches <= 0:
		return {"breaches_added": 0, "reason": "no_breaches"}
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"breaches_added": 0, "reason": "siege_not_found"}
	var current_breaches: int = int(siege.get("breach_count", 0))
	var new_breaches: int = current_breaches + additional_breaches
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	payload["pending_subversion_breach_until_day"] = day
	payload["pending_subversion_breach_count"] = additional_breaches
	SiegeRepository.update(siege_id, {
		"breach_count": new_breaches,
		"payload_json": JSON.stringify(payload),
	})
	SiegeRepository.append_action(siege_id, day, "besieger", "subversion",
		{"breaches_added": additional_breaches},
		{"pending_until_day": day, "current_breaches_after": new_breaches}
	)
	if EventBus.has_signal("siege_breach_created"):
		EventBus.emit_signal("siege_breach_created", siege_id, new_breaches, "subversion")
	return {"breaches_added": additional_breaches, "reason": ""}


## Reap any expired pending subversion breaches. Called from SiegeResolver.tick_daily.
## Decrements breach_count and clears the payload key if a pending breach has
## passed its window.
static func reap_expired_subversion_breach(siege_id: String, day: int) -> int:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return 0
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	if not payload.has("pending_subversion_breach_until_day"):
		return 0
	var pending_day: int = int(payload.get("pending_subversion_breach_until_day", 0))
	if pending_day >= day:
		return 0  # still in window
	var pending_count: int = int(payload.get("pending_subversion_breach_count", 0))
	if pending_count <= 0:
		payload.erase("pending_subversion_breach_until_day")
		payload.erase("pending_subversion_breach_count")
		SiegeRepository.update(siege_id, {"payload_json": JSON.stringify(payload)})
		return 0
	var current_breaches: int = int(siege.get("breach_count", 0))
	var new_breaches: int = maxi(0, current_breaches - pending_count)
	payload.erase("pending_subversion_breach_until_day")
	payload.erase("pending_subversion_breach_count")
	SiegeRepository.update(siege_id, {
		"breach_count": new_breaches,
		"payload_json": JSON.stringify(payload),
	})
	SiegeRepository.append_action(siege_id, day, "besieger", "subversion_breach_expired",
		{"breaches_added": -pending_count},
		{"expired_count": pending_count, "current_breaches_after": new_breaches}
	)
	return pending_count


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _ensure_table_loaded() -> void:
	if _artillery_table.is_empty():
		if not FileAccess.file_exists(_ARTILLERY_TABLE_PATH):
			push_error("SiegeReductionResolver: missing %s" % _ARTILLERY_TABLE_PATH)
			return
		var file := FileAccess.open(_ARTILLERY_TABLE_PATH, FileAccess.READ)
		if file == null:
			return
		var text: String = file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_artillery_table = parsed


static func _parse_payload(json_str: String) -> Dictionary:
	if json_str.is_empty() or json_str == "{}":
		return {}
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}


static func _roll_dice(dice_roller: Callable, count: int, sides: int) -> int:
	## Uses the project dice convention: prefer Callable; otherwise DiceSystem.roll(count,sides).
	if dice_roller != null and dice_roller.is_valid():
		var v: Variant = dice_roller.call(count, sides)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)
		if typeof(v) == TYPE_DICTIONARY and v.has("total"):
			return int(v["total"])
	# Fallback to DiceSystem autoload.
	if Engine.has_singleton("DiceSystem"):
		var ds = Engine.get_singleton("DiceSystem")
		if ds.has_method("roll"):
			return int(ds.roll(count, sides))
	# Last-ditch: built-in randomness.
	var total: int = 0
	for _i in range(count):
		total += (randi() % sides) + 1
	return total


static func _roll_duel_dice(pieces: Array, equipment_catalog: Dictionary, dice_roller: Callable) -> Array:
	var rolls: Array = []
	for piece in pieces:
		var equipment_type: String = String(piece.get("equipment_type", ""))
		var count: int = int(piece.get("count", 0))
		if count <= 0 or equipment_type.is_empty():
			continue
		var entry: Dictionary = equipment_catalog.get(equipment_type, {})
		var die_count: int = int(entry.get("duel_die_count", 0))
		var die_sides: int = int(entry.get("duel_die_sides", 0))
		if die_count <= 0 or die_sides <= 0:
			continue
		# Each piece rolls die_count dice (e.g., trebuchet rolls 2d6 per piece).
		for _i in range(count):
			for _j in range(die_count):
				rolls.append(_roll_dice(dice_roller, 1, die_sides))
	return rolls


static func _apply_duel_hits(siege_id: String, target_pieces: Array, hits: int, equipment_catalog: Dictionary) -> Array:
	var destroyed: Array = []
	if hits <= 0 or target_pieces.is_empty():
		return destroyed
	var hits_remaining: int = hits
	# Apply hits in declared order; heavy_trebuchet takes 2 hits each.
	for piece in target_pieces:
		if hits_remaining <= 0:
			break
		var artillery_id: String = String(piece.get("id", ""))
		var equipment_type: String = String(piece.get("equipment_type", ""))
		var count: int = int(piece.get("count", 0))
		if count <= 0:
			continue
		var entry: Dictionary = equipment_catalog.get(equipment_type, {})
		var hits_per_piece: int = maxi(1, int(entry.get("duel_hits_to_destroy", 1)))
		while hits_remaining >= hits_per_piece and count > 0:
			SiegeRepository.mark_destroyed(artillery_id, 1)
			destroyed.append({"artillery_id": artillery_id, "equipment_type": equipment_type})
			count -= 1
			hits_remaining -= hits_per_piece
	return destroyed
