class_name HexTerrainQuery
extends RefCounted

## Phase 9C polish round 5 2026-05-09: shared hex terrain synthesis + query helper.
##
## Background. The `hex_cells` table does NOT have a `terrain_key` column. The
## schema stores terrain across four columns: `biome` ∈ {clear, woods, jungle,
## swamp, desert}, `elevation` ∈ {flat, hills, mountains}, `civilization` ∈
## {civilized, borderlands, wilderness}, `has_city` ∈ {0, 1}. Three subsystems
## (DomainEncounterResolver, army_marcher, battle_dispatcher) all wanted a
## single "terrain_key" abstraction. Pre-Phase-9C-polish, each queried a
## non-existent `terrain_key` column and silently fell back to a hardcoded
## default ("clear" / "clear_or_grass"). This helper centralizes the synthesis
## + query so all three subsystems read the same vocabulary.
##
## Vocabulary (synthesized by `synthesize_terrain_key`):
##   "ocean"     — water='ocean' (overrides everything else; aquatic hex)
##   "lake"      — water='lake' (overrides everything else; aquatic hex)
##   "settled"   — has_city=1 OR (civilization='civilized' AND biome='clear')
##   "mountains" — elevation='mountains' (regardless of biome)
##   "hills"     — elevation='hills' AND biome='clear' (hills + non-clear
##                 biome keeps biome — woods/swamp/jungle/desert)
##   "woods" / "jungle" / "swamp" / "desert" — biome value
##   "clear"     — fallback (biome='clear' on flat ground)
##
## Consumers normalize this vocabulary onto their own:
##   - DomainEncounterResolver: `normalize_terrain_for_affinity` →
##     monster_catalog.terrain_affinity values (clear → clear_grass_scrub,
##     mountains → mountains_hills, settled → inhabited, etc.)
##   - army_marcher.TERRAIN_MULTIPLIERS: keyed by these synthesized values
##     directly (with "settled" newly added; others were already present).
##   - battle_dispatcher: stores the synthesized string verbatim on the
##     battle row's `terrain_type` column for log/display purposes.
##
## Public API:
##   synthesize_terrain_key(biome, elevation, civilization, has_city) -> String
##     Pure function — no DB. Use when you already have the columns in hand
##     (e.g., `_domain_modal_terrain_key` queries them in bulk and synthesizes
##     each row inline).
##
##   query_terrain_key_for_hex(map_id, q, r, fallback) -> String
##     DB-backed — queries `hex_cells` for the (q, r) row [optionally scoped
##     by map_id when provided] and returns `synthesize_terrain_key(...)` of
##     its columns. Returns `fallback` on SQL failure / missing row /
##     empty biome+elevation. Use when you only have hex coords and need a
##     single-hex lookup (army_marcher, battle_dispatcher).


static func synthesize_terrain_key(biome: String, elevation: String,
		civilization: String, has_city: int, water: String = "",
		biome_subtype: String = "") -> String:
	## Priority ordering (highest wins):
	##   1. water='ocean' → 'ocean' (Phase 9C polish round 6 2026-05-09 —
	##      aquatic hexes override land synthesis; required for aquatic-variant
	##      creatures like aquatic hydras to be picked on water terrain).
	##   2. water='lake' → 'lake' (same).
	##   3. biome_subtype is one of the movement-distinguishing subtypes
	##      (forest_dense → 'dense_forest', desert_badlands → 'badlands') —
	##      these get their own keys because TERRAIN_MULTIPLIERS /
	##      NAVIGATION_TARGETS entries exist for them. See
	##      gdd-terrain-system.md §3.4 / HexTerrainData.movement_cost_category().
	##   4. has_city=1 OR (civilization='civilized' AND biome='clear') → 'settled'
	##      (urban/civilized tiles act as inhabited regardless of biome).
	##   5. elevation='mountains' → 'mountains' (terrain dominates over biome).
	##   6. elevation='hills' AND biome='clear' → 'hills'
	##      (hills + non-clear biome keeps biome — woods/swamp/jungle/desert).
	##   7. biome ∈ {woods, jungle, swamp, desert} → that biome.
	##   8. fallback → 'clear'.
	##
	## Non-movement-distinguishing subtypes (taiga, volcanic, glacial, tundra,
	## savanna, grassland) synthesize to their parent biome/elevation key —
	## they affect encounters and creature-type tilt, not movement, so the
	## coarse vocabulary doesn't need to expose them.
	##
	## `water` and `biome_subtype` default to "" so existing callers (pre-
	## water-support / pre-subtype) compile without change.
	var w: String = water.to_lower()
	if w == "ocean":
		return "ocean"
	if w == "lake":
		return "lake"
	var sub: String = biome_subtype.to_lower()
	if sub == "forest_dense":
		return "dense_forest"
	if sub == "desert_badlands":
		return "badlands"
	var b: String = biome.to_lower()
	var el: String = elevation.to_lower()
	var civ: String = civilization.to_lower()
	if has_city == 1 or (civ == "civilized" and b == "clear"):
		return "settled"
	if el == "mountains":
		return "mountains"
	if el == "hills" and b == "clear":
		return "hills"
	if b == "woods" or b == "jungle" or b == "swamp" or b == "desert":
		return b
	return "clear"


static func query_terrain_key_for_hex(map_id: String, q: int, r: int,
		fallback: String = "clear") -> String:
	## DB-backed single-hex lookup. Queries `hex_cells` for (q, r) restricted
	## to map_id when supplied. Returns synthesize_terrain_key(...) of the
	## row's columns, or `fallback` on SQL failure / missing row.
	##
	## Why fallback is a parameter (not a const): pre-refactor, army_marcher
	## defaulted to "clear" (matches TERRAIN_MULTIPLIERS lookup) and
	## battle_dispatcher defaulted to "clear_or_grass" (legacy
	## battle-resolver display string). Both fallbacks are valid for their
	## respective consumers; the refactor preserves both behaviors.
	var sql: String = "SELECT biome, elevation, civilization, has_city, water, biome_subtype FROM hex_cells WHERE q = ? AND r = ?"
	var bindings: Array = [q, r]
	if not map_id.is_empty():
		sql += " AND map_id = ?"
		bindings.append(map_id)
	sql += " LIMIT 1"
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		return fallback
	if CampaignRepository.db.query_result.is_empty():
		return fallback
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var biome: String = str(row.get("biome", ""))
	var elevation: String = str(row.get("elevation", ""))
	var water: String = str(row.get("water", ""))
	if biome.is_empty() and elevation.is_empty() and water.is_empty():
		return fallback
	var civilization: String = str(row.get("civilization", ""))
	var has_city: int = int(row.get("has_city", 0))
	var biome_subtype: String = str(row.get("biome_subtype", ""))
	return synthesize_terrain_key(biome, elevation, civilization, has_city, water, biome_subtype)
