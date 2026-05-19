class_name HenchmanTables
extends RefCounted

## Phase G-2: Sacred lookup tables from rules/acore_equipment.xml and
## rules/ax_henchmen_recruitment_expanded.xml. Pure data — no DB, no dice.

# ---------------------------------------------------------------------------
# Class rarity (ax_henchmen_recruitment_expanded.xml)
# ---------------------------------------------------------------------------

const RARITY_COMMON := "common"
const RARITY_UNCOMMON := "uncommon"
const RARITY_RARE := "rare"
const RARITY_VERY_RARE := "very_rare"
const RARITY_LEGENDARY := "legendary"

const ALL_RARITIES: Array = [
	RARITY_COMMON, RARITY_UNCOMMON, RARITY_RARE, RARITY_VERY_RARE, RARITY_LEGENDARY,
]

const CLASS_RARITY: Dictionary = {
	"fighter": RARITY_COMMON,
	"thief": RARITY_COMMON,
	"assassin": RARITY_UNCOMMON,
	"cleric": RARITY_UNCOMMON,
	"explorer": RARITY_UNCOMMON,
	"mage": RARITY_UNCOMMON,
	"venturer": RARITY_UNCOMMON,
	"barbarian": RARITY_RARE,
	"bard": RARITY_RARE,
	"bladedancer": RARITY_RARE,
	"priestess": RARITY_RARE,
	"shaman": RARITY_RARE,
	"warlock": RARITY_RARE,
	"witch": RARITY_RARE,
	"anti_paladin": RARITY_VERY_RARE,
	"dwarven_craftpriest": RARITY_VERY_RARE,
	"dwarven_delver": RARITY_VERY_RARE,
	"dwarven_vaultguard": RARITY_VERY_RARE,
	"elven_nightblade": RARITY_VERY_RARE,
	"elven_ranger": RARITY_VERY_RARE,
	"elven_spellsword": RARITY_VERY_RARE,
	"gnomish_trickster": RARITY_VERY_RARE,
	"mystic": RARITY_VERY_RARE,
	"paladin": RARITY_VERY_RARE,
	"dwarven_fury": RARITY_LEGENDARY,
	"dwarven_machinist": RARITY_LEGENDARY,
	"elven_courtier": RARITY_LEGENDARY,
	"elven_enchanter": RARITY_LEGENDARY,
	"lightblessed_wonderworker": RARITY_LEGENDARY,
	"thrassian_gladiator": RARITY_LEGENDARY,
	"darkblood_ruinguard": RARITY_LEGENDARY,
}


static func get_class_rarity(class_id: String) -> String:
	return CLASS_RARITY.get(class_id, RARITY_UNCOMMON)


# ---------------------------------------------------------------------------
# Rarity × market class availability (ax_henchmen_recruitment_expanded.xml)
# Each entry: { "count": int, "percent": int (100 = guaranteed) }
# count = guaranteed number available; percent = chance of at least 1.
# ---------------------------------------------------------------------------

## Returns {count, percent} for a rarity/market_class combo.
## count -1 and percent 0 means unavailable.
static func rarity_availability(rarity: String, market_class: int) -> Dictionary:
	match rarity:
		RARITY_COMMON:
			match market_class:
				1: return {"count": 20, "percent": 100}
				2: return {"count": 2, "percent": 100}
				3: return {"count": 1, "percent": 100}
				4: return {"count": 1, "percent": 50}
				5: return {"count": 1, "percent": 30}
				6: return {"count": 1, "percent": 15}
		RARITY_UNCOMMON:
			match market_class:
				1: return {"count": 2, "percent": 100}
				2: return {"count": 1, "percent": 20}
				3: return {"count": 1, "percent": 2}
				4: return {"count": 1, "percent": 1}
		RARITY_RARE:
			match market_class:
				1: return {"count": 1, "percent": 60}
				2: return {"count": 1, "percent": 5}
				3: return {"count": 1, "percent": 1}
		RARITY_VERY_RARE:
			match market_class:
				1: return {"count": 1, "percent": 10}
				2: return {"count": 1, "percent": 1}
		RARITY_LEGENDARY:
			match market_class:
				1: return {"count": 1, "percent": 1}
	return {"count": -1, "percent": 0}


# ---------------------------------------------------------------------------
# Level × market class henchman availability (acore_equipment.xml:730-736)
# Each entry: dice expression "{count}d{sides}" or "{count}({percent}%)".
# Returns {"dice_count": int, "dice_sides": int, "percent": int}.
# dice_count > 0 means roll that many dice; percent < 100 means chance of 1.
# ---------------------------------------------------------------------------

## Returns availability spec for a henchman level in a market class.
static func level_availability(level: int, market_class: int) -> Dictionary:
	if level == 0:
		match market_class:
			1: return {"dice_count": 4, "dice_sides": 100, "percent": 100}
			2: return {"dice_count": 5, "dice_sides": 20, "percent": 100}
			3: return {"dice_count": 4, "dice_sides": 8, "percent": 100}
			4: return {"dice_count": 3, "dice_sides": 4, "percent": 100}
			5: return {"dice_count": 1, "dice_sides": 6, "percent": 100}
			6: return {"dice_count": 1, "dice_sides": 2, "percent": 100}
	elif level == 1:
		match market_class:
			1: return {"dice_count": 5, "dice_sides": 10, "percent": 100}
			2: return {"dice_count": 2, "dice_sides": 6, "percent": 100}
			3: return {"dice_count": 1, "dice_sides": 4, "percent": 100}
			4: return {"dice_count": 1, "dice_sides": 2, "percent": 100}
			5: return {"dice_count": 0, "dice_sides": 0, "percent": 65}
			6: return {"dice_count": 0, "dice_sides": 0, "percent": 20}
	elif level == 2:
		match market_class:
			1: return {"dice_count": 3, "dice_sides": 10, "percent": 100}
			2: return {"dice_count": 2, "dice_sides": 4, "percent": 100}
			3: return {"dice_count": 1, "dice_sides": 3, "percent": 100}
			4: return {"dice_count": 1, "dice_sides": 1, "percent": 100}
			5: return {"dice_count": 0, "dice_sides": 0, "percent": 40}
			6: return {"dice_count": 0, "dice_sides": 0, "percent": 15}
	elif level == 3:
		match market_class:
			1: return {"dice_count": 1, "dice_sides": 10, "percent": 100}
			2: return {"dice_count": 1, "dice_sides": 3, "percent": 100}
			3: return {"dice_count": 0, "dice_sides": 0, "percent": 85}
			4: return {"dice_count": 0, "dice_sides": 0, "percent": 33}
			5: return {"dice_count": 0, "dice_sides": 0, "percent": 15}
			6: return {"dice_count": 0, "dice_sides": 0, "percent": 5}
	elif level == 4:
		match market_class:
			1: return {"dice_count": 1, "dice_sides": 6, "percent": 100}
			2: return {"dice_count": 1, "dice_sides": 2, "percent": 100}
			3: return {"dice_count": 0, "dice_sides": 0, "percent": 45}
			4: return {"dice_count": 0, "dice_sides": 0, "percent": 15}
			5: return {"dice_count": 0, "dice_sides": 0, "percent": 5}
	return {"dice_count": 0, "dice_sides": 0, "percent": 0}


# ---------------------------------------------------------------------------
# Level determination (1d20, ax_henchmen_recruitment_expanded.xml)
# ---------------------------------------------------------------------------

## Roll a 1d20 (passed as value) and return the henchman's level.
## Class VI markets apply -2 penalty to the roll.
static func level_from_roll(roll_value: int, market_class: int = 1) -> int:
	var adjusted := roll_value
	if market_class == 6:
		adjusted -= 2
	if adjusted <= 10:
		return 1
	if adjusted <= 16:
		return 2
	if adjusted <= 18:
		return 3
	return 4


# ---------------------------------------------------------------------------
# Monthly wage by level (acore_equipment.xml:778-793) — values in CP
# (RAW gp × 100 per the 2026-05-16 cp pass)
# ---------------------------------------------------------------------------

const MONTHLY_WAGE_CP: Array = [
	1200,        # level 0  — RAW 12 gp
	2500,        # level 1  — RAW 25 gp
	5000,        # level 2  — RAW 50 gp
	10000,       # level 3  — RAW 100 gp
	20000,       # level 4  — RAW 200 gp
	40000,       # level 5  — RAW 400 gp
	80000,       # level 6  — RAW 800 gp
	160000,      # level 7  — RAW 1,600 gp
	300000,      # level 8  — RAW 3,000 gp
	725000,      # level 9  — RAW 7,250 gp
	1200000,     # level 10 — RAW 12,000 gp
	3200000,     # level 11 — RAW 32,000 gp
	5000000,     # level 12 — RAW 50,000 gp
	13500000,    # level 13 — RAW 135,000 gp
	35000000,    # level 14 — RAW 350,000 gp
]


static func monthly_wage(level: int) -> int:
	## Returns the henchman's monthly wage in cp for the given level.
	if level < 0 or level >= MONTHLY_WAGE_CP.size():
		return MONTHLY_WAGE_CP[MONTHLY_WAGE_CP.size() - 1]
	return MONTHLY_WAGE_CP[level]


# ---------------------------------------------------------------------------
# Search cost per week by market class (acore_equipment.xml:655-660)
# Returns {dice_count, dice_sides, modifier} for the gold cost roll.
# ---------------------------------------------------------------------------

static func search_cost_spec(market_class: int) -> Dictionary:
	match market_class:
		1: return {"dice_count": 1, "dice_sides": 6, "modifier": 15}
		2: return {"dice_count": 1, "dice_sides": 10, "modifier": 10}
		3: return {"dice_count": 1, "dice_sides": 8, "modifier": 5}
		4: return {"dice_count": 1, "dice_sides": 6, "modifier": 3}
		5: return {"dice_count": 1, "dice_sides": 6, "modifier": 0}
		6: return {"dice_count": 1, "dice_sides": 3, "modifier": 0}
	return {"dice_count": 1, "dice_sides": 6, "modifier": 0}


# ---------------------------------------------------------------------------
# Max henchmen (acore_equipment.xml:816-820, ax_campaign_play.xml)
# ---------------------------------------------------------------------------

## Max henchmen = 4 + CHA modifier + leadership_rank.
## CHA modifier per the standard ACKS table. leadership_rank = number of
## times the PC has selected Leadership proficiency.
static func max_henchmen(cha_modifier: int, leadership_rank: int = 0) -> int:
	return maxi(1, 4 + cha_modifier + leadership_rank)


# ---------------------------------------------------------------------------
# Hiring reaction table (acore_equipment.xml:677-689)
# ---------------------------------------------------------------------------

const HIRE_REFUSE_SLANDER := "refuse_slander"
const HIRE_REFUSE := "refuse"
const HIRE_TRY_AGAIN := "try_again"
const HIRE_ACCEPT := "accept"
const HIRE_ACCEPT_ELAN := "accept_elan"


static func hiring_reaction(total: int) -> String:
	if total <= 2:
		return HIRE_REFUSE_SLANDER
	if total <= 5:
		return HIRE_REFUSE
	if total <= 8:
		return HIRE_TRY_AGAIN
	if total <= 11:
		return HIRE_ACCEPT
	return HIRE_ACCEPT_ELAN


# ---------------------------------------------------------------------------
# Loyalty table (acore_equipment.xml:796-809)
# ---------------------------------------------------------------------------

const LOYALTY_HOSTILITY := "hostility"
const LOYALTY_RESIGNATION := "resignation"
const LOYALTY_GRUDGING := "grudging"
const LOYALTY_LOYAL := "loyal"
const LOYALTY_FANATIC := "fanatic"


static func loyalty_result(total: int) -> String:
	if total <= 2:
		return LOYALTY_HOSTILITY
	if total <= 5:
		return LOYALTY_RESIGNATION
	if total <= 8:
		return LOYALTY_GRUDGING
	if total <= 11:
		return LOYALTY_LOYAL
	return LOYALTY_FANATIC


# ---------------------------------------------------------------------------
# Weekly allotment (acore_equipment.xml:647-649)
# ---------------------------------------------------------------------------

## Given total available henchmen, returns [week1, week2, week3].
## Sacred: week1 = ceil(total/2), week2 = max(1, floor(total/4)),
## week3 = total - week1 - week2. If total ≤ 0, returns [0,0,0].
static func weekly_allotment(total: int) -> Array:
	if total <= 0:
		return [0, 0, 0]
	var week1: int = ceili(float(total) / 2.0)
	var week2: int = maxi(1, floori(float(total) / 4.0))
	var week3: int = total - week1 - week2
	if week3 < 0:
		week2 = total - week1
		week3 = 0
	return [week1, week2, week3]
