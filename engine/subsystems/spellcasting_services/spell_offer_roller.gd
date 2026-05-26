class_name SpellOfferRoller
extends RefCounted

## Stage G of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §8.5 / §13.7 (v1.14).
##
## Pure-function implementation of the RAW Spell Availability by Market
## table at `acore_equipment.xml:979-991`. Encodes the dice expressions
## that determine how many castings of each (tradition, spell_level) are
## available per settlement per day, plus the per-casting unit cost.
##
## Used by SpellOfferRepository at the first POI visit each calendar day
## to seed the settlement-wide offer pool, which is then split across
## the settlement's matching POIs (religious_sites for divine,
## mages_guild_halls for arcane) per §8.5.2.

# ---------------------------------------------------------------------------
# RAW Spell Availability by Market table (acore_equipment.xml:979-991).
# Dice expressions encoded as Dictionary {count, faces, mult, sub}:
#   roll = (NdM_total * mult) - sub   where N=count, M=faces
#
# Examples:
#   "1d6"     → {count: 1, faces: 6, mult: 1, sub: 0}
#   "2d6×10"  → {count: 2, faces: 6, mult: 10, sub: 0}
#   "1d2-1"   → {count: 1, faces: 2, mult: 1, sub: 1}  (yields 0 or 1)
#   "2d3×100" → {count: 2, faces: 3, mult: 100, sub: 0}
#
# Empty dice ({count: 0}) means "unavailable" (RAW dash).
# Market class is keyed 1..6 (Class I largest, Class VI smallest).
# ---------------------------------------------------------------------------

const _DICE_TABLE: Dictionary = {
	"divine": {
		1: {
			# Divine 1st: cost 10gp
			1: {"count": 2, "faces": 3, "mult": 100, "sub": 0},  # Class I: 2d3×100
			2: {"count": 4, "faces": 4, "mult": 10,  "sub": 0},  # Class II: 4d4×10
			3: {"count": 5, "faces": 10, "mult": 1,  "sub": 0},  # Class III: 5d10
			4: {"count": 4, "faces": 6,  "mult": 1,  "sub": 0},  # Class IV: 4d6
			5: {"count": 2, "faces": 6,  "mult": 1,  "sub": 0},  # Class V: 2d6
			6: {"count": 1, "faces": 6,  "mult": 1,  "sub": 0},  # Class VI: 1d6
		},
		2: {
			# Divine 2nd: cost 40gp
			1: {"count": 8, "faces": 10, "mult": 1, "sub": 0},  # Class I: 8d10
			2: {"count": 4, "faces": 6,  "mult": 1, "sub": 0},  # Class II: 4d6
			3: {"count": 2, "faces": 6,  "mult": 1, "sub": 0},  # Class III: 2d6
			4: {"count": 2, "faces": 3,  "mult": 1, "sub": 0},  # Class IV: 2d3
			5: {"count": 1, "faces": 3,  "mult": 1, "sub": 0},  # Class V: 1d3
			6: {"count": 1, "faces": 2,  "mult": 1, "sub": 0},  # Class VI: 1d2
		},
		3: {
			# Divine 3rd: cost 150gp
			1: {"count": 2, "faces": 6,  "mult": 1, "sub": 0},  # Class I: 2d6
			2: {"count": 2, "faces": 3,  "mult": 1, "sub": 0},  # Class II: 2d3
			3: {"count": 2, "faces": 3,  "mult": 1, "sub": 0},  # Class III: 2d3
			4: {"count": 1, "faces": 2,  "mult": 1, "sub": 0},  # Class IV: 1d2
			5: {"count": 1, "faces": 2,  "mult": 1, "sub": 1},  # Class V: 1d2-1
			6: {"count": 0, "faces": 0,  "mult": 0, "sub": 0},  # Class VI: —
		},
		4: {
			# Divine 4th: cost 325gp
			1: {"count": 2, "faces": 6,  "mult": 1, "sub": 0},  # Class I: 2d6
			2: {"count": 2, "faces": 3,  "mult": 1, "sub": 0},  # Class II: 2d3
			3: {"count": 2, "faces": 3,  "mult": 1, "sub": 0},  # Class III: 2d3
			4: {"count": 1, "faces": 2,  "mult": 1, "sub": 0},  # Class IV: 1d2
			5: {"count": 1, "faces": 2,  "mult": 1, "sub": 1},  # Class V: 1d2-1
			6: {"count": 0, "faces": 0,  "mult": 0, "sub": 0},  # Class VI: —
		},
		5: {
			# Divine 5th: cost 500gp
			1: {"count": 1, "faces": 6,  "mult": 1, "sub": 0},  # Class I: 1d6
			2: {"count": 1, "faces": 4,  "mult": 1, "sub": 0},  # Class II: 1d4
			3: {"count": 1, "faces": 4,  "mult": 1, "sub": 0},  # Class III: 1d4
			4: {"count": 1, "faces": 2,  "mult": 1, "sub": 1},  # Class IV: 1d2-1
			5: {"count": 0, "faces": 0,  "mult": 0, "sub": 0},  # Class V: —
			6: {"count": 0, "faces": 0,  "mult": 0, "sub": 0},  # Class VI: —
		},
	},
	"arcane": {
		1: {
			# Arcane 1st: cost 5gp
			1: {"count": 2, "faces": 4, "mult": 100, "sub": 0},  # Class I: 2d4×100
			2: {"count": 2, "faces": 10, "mult": 10, "sub": 0},  # Class II: 2d10×10
			3: {"count": 2, "faces": 4,  "mult": 10, "sub": 0},  # Class III: 2d4×10
			4: {"count": 3, "faces": 10, "mult": 1,  "sub": 0},  # Class IV: 3d10
			5: {"count": 2, "faces": 6,  "mult": 1,  "sub": 0},  # Class V: 2d6
			6: {"count": 1, "faces": 4,  "mult": 1,  "sub": 0},  # Class VI: 1d4
		},
		2: {
			# Arcane 2nd: cost 20gp
			1: {"count": 2, "faces": 6, "mult": 10, "sub": 0},  # Class I: 2d6×10
			2: {"count": 6, "faces": 6, "mult": 1,  "sub": 0},  # Class II: 6d6
			3: {"count": 2, "faces": 6, "mult": 1,  "sub": 0},  # Class III: 2d6
			4: {"count": 2, "faces": 4, "mult": 1,  "sub": 0},  # Class IV: 2d4
			5: {"count": 1, "faces": 4, "mult": 1,  "sub": 0},  # Class V: 1d4
			6: {"count": 1, "faces": 2, "mult": 1,  "sub": 0},  # Class VI: 1d2
		},
		3: {
			# Arcane 3rd: cost 75gp
			1: {"count": 4, "faces": 6, "mult": 1, "sub": 0},  # Class I: 4d6
			2: {"count": 2, "faces": 6, "mult": 1, "sub": 0},  # Class II: 2d6
			3: {"count": 2, "faces": 3, "mult": 1, "sub": 0},  # Class III: 2d3
			4: {"count": 1, "faces": 4, "mult": 1, "sub": 0},  # Class IV: 1d4
			5: {"count": 1, "faces": 2, "mult": 1, "sub": 0},  # Class V: 1d2
			6: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class VI: —
		},
		4: {
			# Arcane 4th: cost 325gp
			1: {"count": 2, "faces": 4, "mult": 1, "sub": 0},  # Class I: 2d4
			2: {"count": 2, "faces": 3, "mult": 1, "sub": 0},  # Class II: 2d3
			3: {"count": 1, "faces": 4, "mult": 1, "sub": 0},  # Class III: 1d4
			4: {"count": 1, "faces": 2, "mult": 1, "sub": 0},  # Class IV: 1d2
			5: {"count": 1, "faces": 2, "mult": 1, "sub": 1},  # Class V: 1d2-1
			6: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class VI: —
		},
		5: {
			# Arcane 5th: cost 1,250gp
			1: {"count": 1, "faces": 4, "mult": 1, "sub": 0},  # Class I: 1d4
			2: {"count": 1, "faces": 4, "mult": 1, "sub": 0},  # Class II: 1d4
			3: {"count": 1, "faces": 2, "mult": 1, "sub": 0},  # Class III: 1d2
			4: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class IV: —
			5: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class V: —
			6: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class VI: —
		},
		6: {
			# Arcane 6th: cost 4,500gp
			1: {"count": 1, "faces": 3, "mult": 1, "sub": 0},  # Class I: 1d3
			2: {"count": 1, "faces": 3, "mult": 1, "sub": 0},  # Class II: 1d3
			3: {"count": 1, "faces": 2, "mult": 1, "sub": 1},  # Class III: 1d2-1
			4: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class IV: —
			5: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class V: —
			6: {"count": 0, "faces": 0, "mult": 0, "sub": 0},  # Class VI: —
		},
	},
}

const _UNIT_COST_GP: Dictionary = {
	"divine": {1: 10, 2: 40, 3: 150, 4: 325, 5: 500},
	"arcane": {1: 5, 2: 20, 3: 75, 4: 325, 5: 1250, 6: 4500},
}

const _MAX_SPELL_LEVEL: Dictionary = {
	"divine": 5,
	"arcane": 6,
}


## Roll the RAW dice for one (tradition, spell_level) row at a given
## market class. Returns the count of castings available today; 0 if the
## RAW table cell is "—" (unavailable).
static func roll_offer_count(
	tradition: String,
	spell_level: int,
	market_class: int,
	rng: RandomNumberGenerator,
) -> int:
	if not _DICE_TABLE.has(tradition):
		return 0
	if not _DICE_TABLE[tradition].has(spell_level):
		return 0
	if not _DICE_TABLE[tradition][spell_level].has(market_class):
		return 0
	var spec: Dictionary = _DICE_TABLE[tradition][spell_level][market_class]
	var count: int = int(spec.get("count", 0))
	var faces: int = int(spec.get("faces", 0))
	var mult: int = int(spec.get("mult", 1))
	var sub: int = int(spec.get("sub", 0))
	if count <= 0 or faces <= 0:
		return 0
	var sum: int = 0
	for _i in range(count):
		sum += rng.randi_range(1, faces)
	var result: int = (sum * mult) - sub
	return maxi(0, result)


## Roll every (tradition, spell_level) row for a market class. Returns a
## Dictionary keyed by tradition → Dictionary keyed by spell_level → count.
## Empty / 0 rows are omitted from the result for cleanliness.
static func roll_all_offers_for_market_class(
	market_class: int,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var result: Dictionary = {}
	for tradition in ["divine", "arcane"]:
		var per_level: Dictionary = {}
		var max_level: int = int(_MAX_SPELL_LEVEL.get(tradition, 0))
		for level in range(1, max_level + 1):
			var count: int = roll_offer_count(tradition, level, market_class, rng)
			if count > 0:
				per_level[level] = count
		if not per_level.is_empty():
			result[tradition] = per_level
	return result


## Per-casting unit cost in gp for a (tradition, spell_level). RAW value
## per `acore_equipment.xml:980-990`; no buyer-side modifiers in v1
## (Q-UGS-56 flags whether ruler-domain discounts should be added later).
static func unit_cost_gp(tradition: String, spell_level: int) -> int:
	if not _UNIT_COST_GP.has(tradition):
		return 0
	return int(_UNIT_COST_GP[tradition].get(spell_level, 0))


## True iff the (tradition, spell_level) pair is in the RAW Spell
## Availability table. Mirrors `SpellOffer.is_valid_level_for_tradition`.
static func has_offer_row(tradition: String, spell_level: int) -> bool:
	if not _UNIT_COST_GP.has(tradition):
		return false
	return _UNIT_COST_GP[tradition].has(spell_level)


## Highest spell level the RAW table covers for a tradition (5 for divine,
## 6 for arcane). Spell-system spells of higher levels are unavailable for
## casual hire in v1 (Q-UGS-54).
static func max_spell_level_for(tradition: String) -> int:
	return int(_MAX_SPELL_LEVEL.get(tradition, 0))
