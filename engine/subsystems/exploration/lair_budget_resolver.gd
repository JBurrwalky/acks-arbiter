class_name LairBudgetResolver
extends RefCounted

## Per-hex lair budget roll (gdd-lair-discovery.md §3.1).
##
## Pure logic — no DB writes, no signal emission. HexLairState owns the
## lazy-roll-and-persist orchestration; this resolver owns the RAW table.
##
## Authority — SACRED:
##   `le_wilderness_lair_rules.xml` §securing_land.tables.lairs_per_hex L34-78
##     (terrain × hex-classification dice table)
##   `le_wilderness_lair_rules.xml` §securing_land.lair_generation_procedure L81-87
##     step 1 "Cross-reference terrain type and hex classification ... and roll"
##     step 2 "Treat any result less than 0 as 0."
##     step 3 "If the table entry is '-', no random lairs are present."
##
## PROJECT-DESIGNED:
##   * Terrain-row mapping from HexTerrainData tags. The RAW table names six
##     terrain rows; hexes carry orthogonal elevation/biome/subtype tags. The
##     mapping cascade below mirrors HexTerrainData.movement_cost_category()
##     precedence (mountains > swamp > jungle > dense forest > woods > hills >
##     badlands > desert > clear) so the budget row always agrees with the
##     hex's dominant terrain as used elsewhere in the engine.
##   * Full-hex water (ocean/lake) has no RAW row → no random lairs.
##
## All randomness flows through the injected `dice` (DiceSystem-like) so tests
## can pin outcomes via GameState.dice_overrides ("lair_budget").


# ---------------------------------------------------------------------------
# Constants — sacred from le_wilderness_lair_rules.xml §lairs_per_hex L42-77
# ---------------------------------------------------------------------------

const ROLL_TYPE := "lair_budget"

## Dice expressions per row × classification. Each cell is
## {n: count, d: sides, mod: modifier}, or null for "-" (no random lairs).
const LAIRS_PER_HEX := {
	"clear_grass": {
		"wilderness":  {"n": 1, "d": 2, "mod": 0},
		"borderlands": null,
		"civilized":   null,
	},
	"scrub_hills": {
		"wilderness":  {"n": 1, "d": 4, "mod": 0},
		"borderlands": {"n": 1, "d": 3, "mod": -2},
		"civilized":   null,
	},
	"barren_desert": {
		"wilderness":  {"n": 1, "d": 6, "mod": 0},
		"borderlands": {"n": 1, "d": 2, "mod": -1},
		"civilized":   null,
	},
	"mountains_woods": {
		"wilderness":  {"n": 2, "d": 4, "mod": 0},
		"borderlands": {"n": 1, "d": 4, "mod": -2},
		"civilized":   {"n": 1, "d": 6, "mod": -5},
	},
	"swamp": {
		"wilderness":  {"n": 2, "d": 4, "mod": 1},
		"borderlands": {"n": 1, "d": 3, "mod": -1},
		"civilized":   {"n": 1, "d": 4, "mod": -3},
	},
	"jungle": {
		"wilderness":  {"n": 2, "d": 8, "mod": 0},
		"borderlands": {"n": 1, "d": 2, "mod": 0},
		"civilized":   {"n": 1, "d": 3, "mod": -2},
	},
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Maps a hex's terrain tags onto a lairs_per_hex row key, or "" when the
## terrain hosts no random lairs (full-hex water). Cascade order mirrors
## HexTerrainData.movement_cost_category().
static func terrain_row_key(terrain: HexTerrainData) -> String:
	if terrain == null:
		return ""
	if terrain.water == HexTerrainData.WATER_OCEAN \
			or terrain.water == HexTerrainData.WATER_LAKE:
		return ""

	# Subtype overrides, mirroring the movement cascade's special cases.
	match terrain.biome_subtype:
		HexTerrainData.SUBTYPE_FOREST_DENSE, HexTerrainData.SUBTYPE_FOREST_TAIGA:
			return "mountains_woods"
		HexTerrainData.SUBTYPE_DESERT_BADLANDS:
			if terrain.elevation == HexTerrainData.ELEVATION_MOUNTAINS:
				return "mountains_woods"
			return "barren_desert"
		# "clear_scrub" has no named constant on HexTerrainData (schema-only
		# vocabulary); the literal matches hex_cells.biome_subtype.
		"clear_scrub":
			if terrain.elevation == HexTerrainData.ELEVATION_MOUNTAINS:
				return "mountains_woods"
			return "scrub_hills"

	if terrain.elevation == HexTerrainData.ELEVATION_MOUNTAINS:
		return "mountains_woods"
	if terrain.biome == HexTerrainData.BIOME_SWAMP:
		return "swamp"
	if terrain.biome == HexTerrainData.BIOME_JUNGLE:
		return "jungle"
	if terrain.biome == HexTerrainData.BIOME_WOODS:
		return "mountains_woods"
	if terrain.elevation == HexTerrainData.ELEVATION_HILLS:
		return "scrub_hills"
	if terrain.biome == HexTerrainData.BIOME_DESERT:
		return "barren_desert"
	return "clear_grass"


## Returns the dice expression for [param terrain]'s row × classification, or
## an empty Dictionary when the cell is "-" / the terrain has no row.
static func budget_dice_for(terrain: HexTerrainData) -> Dictionary:
	var row_key := terrain_row_key(terrain)
	if row_key.is_empty() or not LAIRS_PER_HEX.has(row_key):
		return {}
	var row: Dictionary = LAIRS_PER_HEX[row_key]
	var civ: String = terrain.civilization if terrain != null else "wilderness"
	if not row.has(civ):
		civ = HexTerrainData.TERRITORY_WILDERNESS
	var cell: Variant = row.get(civ)
	if cell == null:
		return {}
	return cell


## Rolls the hex's lair budget per the RAW table. Clamps to >= 0 (RAW step 2);
## "-" cells return 0 without consuming a roll (RAW step 3).
##
## Returns Dictionary:
##   row_key: String        — lairs_per_hex row used ("" when waterlocked)
##   civilization: String   — classification column used
##   budget: int            — clamped result
##   rolled: bool           — false when the cell was "-" (no dice consumed)
static func roll_budget(terrain: HexTerrainData, dice) -> Dictionary:
	var row_key := terrain_row_key(terrain)
	var civ: String = terrain.civilization if terrain != null \
		else HexTerrainData.TERRITORY_WILDERNESS
	var expr := budget_dice_for(terrain)
	if expr.is_empty():
		return {"row_key": row_key, "civilization": civ, "budget": 0, "rolled": false}
	var roll: RollResult = dice.roll_digital(
		int(expr["d"]), int(expr["n"]), int(expr["mod"]), ROLL_TYPE)
	return {
		"row_key": row_key,
		"civilization": civ,
		# RAW step 2: "Treat any result less than 0 as 0."
		"budget": maxi(0, roll.modified_total),
		"rolled": true,
	}
