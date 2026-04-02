class_name XPAwardCalculator
extends RefCounted

## XP Award Calculator for ACKS 1e.
## Source: acore_adventures_and_encounters.xml (monster XP, shares, advancement cap)
##         acore-campaign-hijinks.xml (domain/mercantile/construction XP thresholds)
##
## Covers: monster XP, treasure XP, party share distribution, prime req adjustments,
## 1-level advancement cap, and domain/mercantile/hijink XP.

var _class_registry: ClassRegistry


func _init(p_class_registry: ClassRegistry) -> void:
	_class_registry = p_class_registry


# ---------------------------------------------------------------------------
# Banker's Rounding
# ---------------------------------------------------------------------------

static func bankers_round(value: float) -> int:
	## Round half to even (Banker's rounding). Required everywhere in ACKS Arbiter.
	## NOTE: GDScript's roundi() rounds half AWAY from zero — that is NOT Banker's rounding.
	var floored := int(floor(value))
	var frac := value - float(floored)
	# Use a small epsilon to handle floating-point representation issues near 0.5.
	if absf(frac - 0.5) < 0.000001:
		# Exactly half — round to even.
		if floored % 2 == 0:
			return floored
		else:
			return floored + 1
	return roundi(value)


# ---------------------------------------------------------------------------
# Monster XP Table
# ---------------------------------------------------------------------------
## Source: acore_adventures_and_encounters.xml lines 617-651.
## Format: { "hd_key": [base_xp, bonus_xp_per_special_ability] }
## HD keys: "<1", "1", "1+", "2", "2+", ..., "21"
## For HD 22+: base and bonus each increase by 250 per HD above 21.

const MONSTER_XP_TABLE: Dictionary = {
	"<1": [5,    1   ],
	"1":  [10,   3   ],
	"1+": [15,   6   ],
	"2":  [20,   9   ],
	"2+": [35,   12  ],
	"3":  [50,   15  ],
	"3+": [65,   35  ],
	"4":  [80,   55  ],
	"4+": [140,  75  ],
	"5":  [200,  150 ],
	"5+": [260,  200 ],
	"6":  [320,  250 ],
	"6+": [380,  300 ],
	"7":  [440,  350 ],
	"7+": [500,  400 ],
	"8":  [600,  500 ],
	"9":  [700,  600 ],
	"10": [850,  700 ],
	"11": [1000, 800 ],
	"12": [1200, 900 ],
	"13": [1400, 1000],
	"14": [1600, 1100],
	"15": [1800, 1200],
	"16": [2000, 1300],
	"17": [2200, 1400],
	"18": [2400, 1500],
	"19": [2600, 1600],
	"20": [2800, 1800],
	"21": [3000, 2000],
}

## GP threshold by character level for domain/mercantile/hijinks XP.
## Source: acore-campaign-hijinks.xml lines 1063-1077.
const GP_THRESHOLD_TABLE: Dictionary = {
	0:  25,
	1:  25,    2:  75,     3:  150,    4:  300,
	5:  650,   6:  1250,   7:  2500,   8:  5000,
	9:  12000, 10: 18000,  11: 40000,  12: 60000,
	13: 150000, 14: 425000,
}


# ---------------------------------------------------------------------------
# Monster XP Calculation
# ---------------------------------------------------------------------------

static func calculate_monster_xp(hd_key: String, special_abilities: int) -> int:
	## Calculate the XP value of a single defeated monster.
	## hd_key: e.g., "1", "3+", "5", "<1". Use "" for unknown (returns 0).
	## special_abilities: count of asterisks on the stat block.
	if hd_key.is_empty():
		return 0
	if MONSTER_XP_TABLE.has(hd_key):
		var row: Array = MONSTER_XP_TABLE[hd_key]
		return int(row[0]) + int(row[1]) * special_abilities
	# HD 22+ handling: each HD above 21 adds 250 to base and bonus.
	# Parse the hd_key to see if it's a plain integer > 21.
	if hd_key.is_valid_int():
		var hd := int(hd_key)
		if hd >= 22:
			return _calculate_high_hd_xp(hd, special_abilities)
	push_error("XPAwardCalculator.calculate_monster_xp: unknown hd_key '%s'" % hd_key)
	return 0


static func _calculate_high_hd_xp(hd: int, special_abilities: int) -> int:
	## HD 22+ formula: base = 3000 + 250*(hd-21), bonus = 2000 + 250*(hd-21).
	var steps := hd - 21
	var base := 3000 + 250 * steps
	var bonus := 2000 + 250 * steps
	return base + bonus * special_abilities


static func calculate_encounter_monster_xp(monsters: Array) -> int:
	## Calculate total monster XP for an array of defeated monsters.
	## Each entry: { "hd_key": String, "special_abilities": int, "count": int }
	var total := 0
	for entry in monsters:
		var hd_key: String = entry.get("hd_key", "")
		var abilities: int = int(entry.get("special_abilities", 0))
		var count: int = int(entry.get("count", 1))
		total += calculate_monster_xp(hd_key, abilities) * count
	return total


# ---------------------------------------------------------------------------
# Party Share Distribution
# ---------------------------------------------------------------------------

static func calculate_party_shares(total_xp: int, members: Array) -> Dictionary:
	## Divide total XP among party members. Each PC = 1 full share. Each henchman = 0.5 share.
	## Source: acore_adventures_and_encounters.xml lines 655-662.
	##
	## members: Array[Dictionary], each entry { "character_id": String, "is_henchman": bool }
	## Returns: { character_id: raw_share_int }
	##
	## Shares are calculated as: total_xp / total_shares, then each member gets
	## 1.0 or 0.5 * per_share. Banker's rounding applied to each result.
	if members.is_empty() or total_xp <= 0:
		var result: Dictionary = {}
		for m in members:
			result[m["character_id"]] = 0
		return result

	var total_shares := 0.0
	for m in members:
		total_shares += 0.5 if m.get("is_henchman", false) else 1.0

	if total_shares <= 0.0:
		var result: Dictionary = {}
		for m in members:
			result[m["character_id"]] = 0
		return result

	var per_share := float(total_xp) / total_shares
	var result: Dictionary = {}
	for m in members:
		var multiplier := 0.5 if m.get("is_henchman", false) else 1.0
		result[m["character_id"]] = bankers_round(per_share * multiplier)
	return result


# ---------------------------------------------------------------------------
# Prime Requisite Adjustment
# ---------------------------------------------------------------------------

static func apply_prime_req_adjustment(raw_xp: int, adjustment_percent: int) -> int:
	## Apply the prime requisite XP percentage adjustment.
	## adjustment_percent: -10, -5, 0, +5, or +10.
	## Uses Banker's rounding.
	if adjustment_percent == 0:
		return raw_xp
	return bankers_round(float(raw_xp) * (1.0 + float(adjustment_percent) / 100.0))


# ---------------------------------------------------------------------------
# 1-Level Advancement Cap
# ---------------------------------------------------------------------------

func clamp_to_one_level(character: CharacterData, raw_award: int) -> int:
	## Clamp an XP award so the character cannot gain enough XP to advance two or more levels.
	## Source: acore_adventures_and_encounters.xml lines 697-700.
	##
	## Specifically: after award, character.xp must be strictly less than
	## the XP needed for level+2.
	if _class_registry == null or raw_award <= 0:
		return raw_award
	var current_level := character.level
	var max_level := character.max_level
	# If already at max or one below max, no two-level jump is possible anyway.
	if current_level >= max_level - 1:
		return raw_award
	var two_levels_ahead_xp := _class_registry.get_xp_for_level(
		character.character_class, current_level + 2)
	if two_levels_ahead_xp <= 0:
		return raw_award  # No valid threshold found.
	# character.xp + clamped_award must be < two_levels_ahead_xp
	var max_allowed_award := two_levels_ahead_xp - 1 - character.xp
	return mini(raw_award, max_allowed_award)


# ---------------------------------------------------------------------------
# Full Adventure XP Pipeline
# ---------------------------------------------------------------------------

func award_adventure_xp(monster_xp: int, treasure_xp: int, members: Array) -> Array:
	## Full XP award pipeline for an adventure.
	##
	## members: Array[Dictionary], each entry:
	##   { "character_id": String, "is_henchman": bool,
	##     "xp_adjustment_percent": int, "character_data": CharacterData }
	##
	## Returns Array[Dictionary], one per member:
	##   { "character_id", "raw_share", "adjusted_share", "clamped_share",
	##     "xp_before", "xp_after", "leveled_up" }
	var total_xp := monster_xp + treasure_xp
	var share_inputs: Array = []
	for m in members:
		share_inputs.append({
			"character_id": m["character_id"],
			"is_henchman": m.get("is_henchman", false),
		})

	var raw_shares := calculate_party_shares(total_xp, share_inputs)
	var results: Array = []

	for m in members:
		var cid: String = m["character_id"]
		var raw_share: int = raw_shares.get(cid, 0)
		var adj_pct: int = int(m.get("xp_adjustment_percent", 0))
		var adjusted_share := apply_prime_req_adjustment(raw_share, adj_pct)

		var char_data: CharacterData = m.get("character_data")
		var clamped_share := adjusted_share
		if char_data != null:
			clamped_share = clamp_to_one_level(char_data, adjusted_share)

		var xp_before := char_data.xp if char_data != null else 0
		var xp_after := xp_before + clamped_share
		var leveled_up := false
		if char_data != null and char_data.xp_for_next_level > 0:
			leveled_up = xp_after >= char_data.xp_for_next_level

		results.append({
			"character_id":    cid,
			"raw_share":       raw_share,
			"adjusted_share":  adjusted_share,
			"clamped_share":   clamped_share,
			"xp_before":       xp_before,
			"xp_after":        xp_after,
			"leveled_up":      leveled_up,
		})

	return results


# ---------------------------------------------------------------------------
# Domain / Mercantile / Hijinks XP
# ---------------------------------------------------------------------------

func calculate_domain_xp(income: int, level: int, is_henchman: bool = false) -> int:
	## Calculate domain/mercantile XP for a character.
	## income: monthly GP income above all expenses.
	## level: character's current level (for threshold lookup).
	## is_henchman: henchmen earn 50% of domain XP.
	##
	## Source: acore-campaign-hijinks.xml lines 1014-1091.
	var clamped_level := clampi(level, 0, 14)
	var threshold: int = GP_THRESHOLD_TABLE.get(clamped_level, 25)
	if income <= threshold:
		return 0
	var base_xp := income - threshold
	if is_henchman:
		return bankers_round(float(base_xp) * 0.5)
	return base_xp
