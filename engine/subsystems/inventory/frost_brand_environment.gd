class_name FrostBrandEnvironment
extends RefCounted

## Pure-function helper for Frost Brand's environmental glow condition.
##
## RAW (acore_treasure_and_magic_items_rules.xml:276): "Sheds torchlight when
## temperature is below 0 degrees Fahrenheit." V1 simplification per Jedidiah
## 2026-06-01: cold conditions are expressed via terrain + season, since the
## engine doesn't yet model ambient temperature.
##
## Glow rules:
##   - **Always cold (any season except summer)**: the blade glows in the
##     biome subtypes that are perpetually cold — tundra, taiga, glacial
##     mountains.
##   - **Winter only**: the blade glows in temperate terrains that turn
##     cold in winter — grassland, forest (any non-taiga woods), dense
##     forest, and non-volcanic / non-glacial mountains.
##
## When the conditions are met, the wielder's WornMagicEffectResolver-set
## state is augmented with a glow flag (set by the wilderness handler at
## hex_entered / season_changed time). The blade's light is forward-looking
## metadata — actual light-source registration via LightSourceTracker is a
## small follow-up integration once the HUD layer supports multi-source
## priority.


## Returns true when the supplied terrain + season combination meets the
## Frost Brand glow conditions per the V1 rule above.
##
## [param terrain] a HexTerrainData (or null — null returns false).
## [param season] one of "spring" / "summer" / "autumn" / "winter".
static func frost_brand_should_glow(terrain: HexTerrainData, season: String) -> bool:
	if terrain == null:
		return false
	# Always-cold subtypes — glow in any season EXCEPT summer.
	if season != CalendarSeasons.SUMMER:
		if terrain.biome_subtype in [
				HexTerrainData.SUBTYPE_CLEAR_TUNDRA,
				HexTerrainData.SUBTYPE_FOREST_TAIGA,
				HexTerrainData.SUBTYPE_MOUNTAINS_GLACIAL]:
			return true
	# Winter-only subtypes — temperate terrains that turn cold in winter.
	if season == CalendarSeasons.WINTER:
		# Grassland (clear/grassland subtype).
		if terrain.biome_subtype == HexTerrainData.SUBTYPE_CLEAR_GRASSLAND:
			return true
		# Forest — any woods biome OTHER THAN taiga (taiga is covered above
		# by the always-cold rule; we don't double-count it here).
		if terrain.biome == HexTerrainData.BIOME_WOODS \
				and terrain.biome_subtype != HexTerrainData.SUBTYPE_FOREST_TAIGA:
			return true
		# Mountains — any mountain elevation EXCEPT volcanic (always warm
		# enough) and glacial (already covered above as always-cold).
		if terrain.elevation == HexTerrainData.ELEVATION_MOUNTAINS \
				and terrain.biome_subtype != HexTerrainData.SUBTYPE_MOUNTAINS_VOLCANIC \
				and terrain.biome_subtype != HexTerrainData.SUBTYPE_MOUNTAINS_GLACIAL:
			return true
	return false


## Updates the `wielding_glowing_frost_brand` flag on a single character
## based on the supplied terrain + season + the character's inventory.
##
## For each equipped Frost Brand sword (`item_key == "frost_brand"`,
## `is_equipped == 1`, `slot == "hands_main"`):
##   - If `frost_brand_should_glow(terrain, season)` returns true, set
##     the flag with metadata {sword_id, light_radius_cells: 6}.
##   - Otherwise, clear the flag for that sword.
##
## Source_id pattern: `frost_brand_glow:<sword_id>` — keyed per-sword so
## a dual-wielder (or party with multiple Frost Brand bearers) tracks each
## independently. Future HUD light-source consumer reads the flag.
##
## The wilderness handler calls this on hex_entered + season_changed
## signals so the glow state stays current with party movement +
## calendar advances.
static func update_glow_state_for_character(
		character: CharacterData,
		inventory_rows: Array,
		terrain: HexTerrainData,
		season: String) -> void:
	if character == null or character.flags == null:
		return
	var should_glow: bool = frost_brand_should_glow(terrain, season)
	for row in inventory_rows:
		if not (row is Dictionary):
			continue
		var item_key: String = str((row as Dictionary).get("item_key", ""))
		if item_key != "frost_brand":
			continue
		if int((row as Dictionary).get("is_equipped", 0)) != 1:
			continue
		if str((row as Dictionary).get("slot", "")) != "hands_main":
			continue
		var sword_id: String = str((row as Dictionary).get("id", ""))
		if sword_id.is_empty():
			continue
		var source_id: String = "frost_brand_glow:%s" % sword_id
		if should_glow:
			character.flags.set_flag("wielding_glowing_frost_brand", source_id, {
				"sword_id": sword_id,
				"light_radius_cells": 6,  # standard torch radius (30')
				"source_kind": "frost_brand_environment",
			})
		else:
			character.flags.clear_flag("wielding_glowing_frost_brand", source_id)
