class_name SettlementEconomyInputs
extends RefCounted

## Settlement economy inputs — maps the project's schema vocabulary to the
## RAW six-step demand-modifier procedure's inputs.
##
## Per generation/gdd-settlement-economy.md §3. Read-side service used by
## DemandModifierGenerator (§4) to gather every per-settlement input before
## running steps 1-5 of the procedure.
##
## All persistence reads route through CampaignRepository.db; this file owns
## no DB connection of its own.


# ---------------------------------------------------------------------------
# §3.4 climate mapping (biome, biome_subtype) → RAW climate columns
# [NEEDS-TERRAIN-CANON-REWORK] — composite mapping is a v1 calibration;
# the deferred terrain-canon harmonization session may retune.
# ---------------------------------------------------------------------------

const _CLIMATE_MAP := {
	# clear
	"clear|": ["grasslands", "plains"],
	"clear|clear_grassland": ["grasslands"],
	"clear|clear_savanna": ["savanna"],
	"clear|clear_tundra": ["tundra"],
	"clear|clear_steppe": ["steppe"],
	"clear|clear_scrub": ["scrub"],
	"clear|mountains_volcanic": ["grasslands", "plains"],
	"clear|mountains_glacial": ["grasslands", "plains"],
	# woods
	"woods|": ["deciduous_forest"],
	"woods|forest_dense": ["deciduous_forest"],
	"woods|forest_taiga": ["taiga"],
	"woods|mountains_volcanic": ["deciduous_forest"],
	# jungle
	"jungle|": ["rainforest"],
	"jungle|mountains_volcanic": ["rainforest"],
	# swamp — composite; lake_shore water source forced true in resolve_water_sources
	"swamp|": ["scrub"],
	"swamp|mountains_volcanic": ["scrub"],
	# desert
	"desert|": ["desert"],
	"desert|desert_badlands": ["desert"],
	"desert|mountains_volcanic": ["desert"],
	"desert|mountains_glacial": ["desert"],
}

## All 10 RAW climate column names. Used for climate_override validation.
const VALID_CLIMATE_COLUMNS := [
	"rainforest", "savanna", "desert", "steppe", "scrub",
	"grasslands", "deciduous_forest", "taiga", "tundra", "plains",
]


# ---------------------------------------------------------------------------
# Pure-function lookups (§3.2, §3.4, §3.5)
# ---------------------------------------------------------------------------

## Returns one of "0_20_years", "21_100_years", "101_1000_years",
## "1001_2000_years", "2001_plus_years". Boundaries are inclusive
## per GDD §1.2 (age=20 → 0_20, age=21 → 21_100, etc.).
static func age_bucket_for(age_years: int) -> String:
	if age_years <= 20:
		return "0_20_years"
	if age_years <= 100:
		return "21_100_years"
	if age_years <= 1000:
		return "101_1000_years"
	if age_years <= 2000:
		return "1001_2000_years"
	return "2001_plus_years"


## Returns an Array[String] of RAW climate column names. Empty when no
## climate mapping exists for the (biome, biome_subtype) pair (e.g., a
## future biome not yet wired in).
static func climate_columns_for(biome: String, biome_subtype: String) -> Array:
	var key: String = "%s|%s" % [biome, biome_subtype]
	# [NEEDS-TERRAIN-CANON-REWORK]
	return (_CLIMATE_MAP.get(key, []) as Array).duplicate()


## Returns "hills", "mountains", or "" (sentinel — flat = no elevation modifier).
static func elevation_bucket_for(elevation: String) -> String:
	if elevation == "hills":
		return "hills"
	if elevation == "mountains":
		return "mountains"
	return ""


# ---------------------------------------------------------------------------
# Database-backed lookups (§3.3, §3.6, §3.7)
# ---------------------------------------------------------------------------

## Resolves the three water-source booleans for a settlement.
## Per §3.3: ocean and lake propagate one hex via adjacency; rivers are
## settlement-on-hex only. Swamp biome implies lake_shore regardless of
## actual adjacency (§3.4 composite mapping).
static func resolve_water_sources(settlement_id: String) -> Dictionary:
	var result := {"sea_coast": false, "lake_shore": false, "river_bank": false}
	if settlement_id.is_empty():
		return result
	# Look up the settlement's hex + its parent map.
	if not CampaignRepository.db.query_with_bindings(
			"SELECT map_id, hex_q, hex_r FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return result
	if CampaignRepository.db.query_result.is_empty():
		return result
	var settlement_row: Dictionary = CampaignRepository.db.query_result[0]
	var map_id: String = str(settlement_row.get("map_id", ""))
	var hex_q: int = int(settlement_row.get("hex_q", 0))
	var hex_r: int = int(settlement_row.get("hex_r", 0))
	if map_id.is_empty():
		return result

	# Look up the home hex and its 6 neighbors. Each (map_id, q, r) is a
	# primary-key point lookup, so 7 queries is cheap; row-value IN clauses
	# are non-portable enough that we prefer the simple per-hex form.
	var coords: Array = [Vector2i(hex_q, hex_r)]
	for n in HexMapController.get_neighbors(Vector2i(hex_q, hex_r)):
		coords.append(n)

	var home_biome: String = ""
	for c in coords:
		var coord: Vector2i = c
		if not CampaignRepository.db.query_with_bindings(
				"SELECT biome, water FROM hex_cells WHERE map_id = ? AND q = ? AND r = ?",
				[map_id, int(coord.x), int(coord.y)]):
			continue
		if CampaignRepository.db.query_result.is_empty():
			continue
		var hex_row: Dictionary = CampaignRepository.db.query_result[0]
		var water: String = str(hex_row.get("water", ""))
		var biome: String = str(hex_row.get("biome", ""))
		if coord.x == hex_q and coord.y == hex_r:
			home_biome = biome
		if water == "ocean":
			result["sea_coast"] = true
		elif water == "lake":
			result["lake_shore"] = true

	# Swamp biome implies lake_shore (§3.3 / §3.4 composite mapping).
	if home_biome == "swamp":
		result["lake_shore"] = true

	# River detection — settlement-on-hex only (no adjacency propagation).
	if CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM hex_overlays
		WHERE map_id = ? AND q = ? AND r = ? AND overlay_type = 'river'
		LIMIT 1
	""", [map_id, hex_q, hex_r]):
		if not CampaignRepository.db.query_result.is_empty():
			result["river_bank"] = true

	return result


## Direct read of dominant_race on settlement_entrances. Returns "human"
## (the column default) if the row is missing.
static func resolve_dominant_race(settlement_id: String) -> String:
	if settlement_id.is_empty():
		return "human"
	if not CampaignRepository.db.query_with_bindings(
			"SELECT dominant_race FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return "human"
	if CampaignRepository.db.query_result.is_empty():
		return "human"
	return str(CampaignRepository.db.query_result[0].get("dominant_race", "human"))


## Computes the average land_value across all domain_hexes rows for the
## settlement's parent domain, banker-rounded and clamped to [3, 9].
## Returns 5 (mid-scale fallback) when the settlement has no parent domain.
static func resolve_domain_land_revenue(settlement_id: String) -> int:
	if settlement_id.is_empty():
		return 5
	# Find the parent domain.
	if not CampaignRepository.db.query_with_bindings(
			"SELECT parent_domain_id FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return 5
	if CampaignRepository.db.query_result.is_empty():
		return 5
	var parent_domain_id_var: Variant = CampaignRepository.db.query_result[0].get("parent_domain_id", null)
	if parent_domain_id_var == null:
		return 5
	var parent_domain_id: String = str(parent_domain_id_var)
	if parent_domain_id.is_empty():
		return 5

	# Average land_value across the domain's hexes.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT land_value FROM domain_hexes WHERE domain_id = ?
	""", [parent_domain_id]):
		return 5
	var rows: Array = CampaignRepository.db.query_result.duplicate()
	if rows.is_empty():
		return 5
	var total: float = 0.0
	for row in rows:
		total += float(int((row as Dictionary).get("land_value", 5)))
	var avg: float = total / float(rows.size())
	var rounded: int = XPAwardCalculator.bankers_round(avg)
	return clamp(rounded, 3, 9)


# ---------------------------------------------------------------------------
# Aggregator (§3.8)
# ---------------------------------------------------------------------------

## Single entry point that resolves every per-settlement input the
## DemandModifierGenerator needs. Per §3.8.
##
## Returned dict:
##   age_bucket              String  (0_20_years..2001_plus_years)
##   water_sources           Dict    {sea_coast, lake_shore, river_bank} of bool
##   climate_columns         Array   1-2 RAW climate column names (may be empty)
##   climate_override        String  raw column name when overridden; "" otherwise
##   elevation_bucket        String  "hills"/"mountains"/"" (flat sentinel)
##   dominant_race           String  human/dwarf/elf/etc
##   domain_land_revenue     int     3-9, banker-rounded average over domain_hexes
static func resolve_all(settlement_id: String) -> Dictionary:
	var result := {
		"age_bucket": "101_1000_years",
		"water_sources": {"sea_coast": false, "lake_shore": false, "river_bank": false},
		"climate_columns": [],
		"climate_override": "",
		"elevation_bucket": "",
		"dominant_race": "human",
		"domain_land_revenue": 5,
	}
	if settlement_id.is_empty():
		return result
	# Settlement row: age, dominant_race, climate_override, location (for hex lookup).
	if not CampaignRepository.db.query_with_bindings("""
		SELECT age_years, dominant_race, climate_override, map_id, hex_q, hex_r
		FROM settlement_entrances WHERE id = ?
	""", [settlement_id]):
		return result
	if CampaignRepository.db.query_result.is_empty():
		return result
	var settlement_row: Dictionary = CampaignRepository.db.query_result[0]
	result["age_bucket"] = age_bucket_for(int(settlement_row.get("age_years", 500)))
	result["dominant_race"] = str(settlement_row.get("dominant_race", "human"))
	var climate_override: String = str(settlement_row.get("climate_override", ""))
	result["climate_override"] = climate_override

	var map_id: String = str(settlement_row.get("map_id", ""))
	var hex_q: int = int(settlement_row.get("hex_q", 0))
	var hex_r: int = int(settlement_row.get("hex_r", 0))

	# Hex row: biome, biome_subtype, elevation.
	if not map_id.is_empty() and CampaignRepository.db.query_with_bindings("""
		SELECT biome, biome_subtype, elevation FROM hex_cells
		WHERE map_id = ? AND q = ? AND r = ?
	""", [map_id, hex_q, hex_r]):
		if not CampaignRepository.db.query_result.is_empty():
			var hex_row: Dictionary = CampaignRepository.db.query_result[0]
			var biome: String = str(hex_row.get("biome", ""))
			var subtype: String = str(hex_row.get("biome_subtype", ""))
			result["elevation_bucket"] = elevation_bucket_for(str(hex_row.get("elevation", "flat")))
			if climate_override.is_empty():
				result["climate_columns"] = climate_columns_for(biome, subtype)
			else:
				result["climate_columns"] = [climate_override]

	# If climate_override is set but the hex lookup failed, still honor the override.
	if not climate_override.is_empty() and result["climate_columns"].is_empty():
		result["climate_columns"] = [climate_override]

	# Water sources (§3.3).
	result["water_sources"] = resolve_water_sources(settlement_id)

	# Domain land revenue (§3.7).
	result["domain_land_revenue"] = resolve_domain_land_revenue(settlement_id)

	return result


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
