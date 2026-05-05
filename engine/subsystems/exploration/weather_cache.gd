class_name WeatherCache
extends RefCounted

## DB-backed weather state cache (Wilderness closure Phase 2).
##
## Stores rows in `weather_states` (migration 048). Reads are by composite
## key (campaign_id, hex_q, hex_r, julian_day, year); a miss triggers
## WeatherGenerator.generate() and stores the result.
##
## The cache is the source of truth once a hex × day weather has been
## presented to the player — even if the generator would now produce a
## different result (e.g., the biome changed via deforestation), the cached
## row supersedes. This preserves narrative continuity.
##
## Methods are static — no instance state. Callers pass the campaign_id and
## anything else they have. Queries go through the global CampaignRepository
## autoload's `db` handle.


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Read the cached weather for [param campaign_id] / [param hex_q] /
## [param hex_r] / [param julian_day] / [param year]. Returns the
## WeatherStateData on hit, or null on miss.
static func get_cached(
	campaign_id: String,
	hex_q: int,
	hex_r: int,
	julian_day: int,
	year: int = 1,
) -> WeatherStateData:
	if CampaignRepository.db == null or campaign_id.is_empty():
		return null
	var ok: bool = CampaignRepository.db.query_with_bindings("""
		SELECT * FROM weather_states
		WHERE campaign_id = ? AND hex_q = ? AND hex_r = ?
		  AND julian_day = ? AND year = ?
	""", [campaign_id, hex_q, hex_r, julian_day, year])
	if not ok or CampaignRepository.db.query_result.is_empty():
		return null
	return WeatherStateData.from_dict(CampaignRepository.db.query_result[0])


## Read on miss → generate and store. Returns the WeatherStateData; never
## null when [param terrain] and inputs are valid.
##
## [param terrain] is required on the miss path so the generator can pick
## the DaW row. Cache hits ignore terrain entirely (the cached row already
## reflects the inputs at the time of generation).
static func get_or_generate(
	campaign_id: String,
	hex_q: int,
	hex_r: int,
	terrain: HexTerrainData,
	julian_day: int,
	year: int = 1,
	hemisphere: String = "north",
) -> WeatherStateData:
	var hit: WeatherStateData = get_cached(campaign_id, hex_q, hex_r, julian_day, year)
	if hit != null:
		return hit
	if terrain == null:
		return null
	var fresh: WeatherStateData = WeatherGenerator.generate(
		campaign_id, hex_q, hex_r, terrain, julian_day, year, hemisphere)
	store(campaign_id, fresh)
	return fresh


## Persist a generated WeatherStateData. INSERT OR REPLACE — re-storing the
## same key overwrites (used by Control Weather override in a future phase).
static func store(campaign_id: String, weather: WeatherStateData) -> bool:
	if CampaignRepository.db == null or campaign_id.is_empty() or weather == null:
		return false
	return CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO weather_states
			(campaign_id, hex_q, hex_r, julian_day, year,
			 temperature_band, atmosphere,
			 precipitation_level, precipitation_type,
			 wind_level, visibility_multiplier, produces_mud,
			 generated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
	""", [
		campaign_id,
		weather.hex_q, weather.hex_r,
		weather.julian_day, weather.year,
		weather.temperature_band, weather.atmosphere,
		weather.precipitation_level, weather.precipitation_type,
		weather.wind_level, weather.visibility_multiplier,
		int(weather.produces_mud),
	])


## Drop all cached rows for [param campaign_id]. Test fixture cleanup.
static func clear_for_campaign(campaign_id: String) -> bool:
	if CampaignRepository.db == null or campaign_id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings(
		"DELETE FROM weather_states WHERE campaign_id = ?", [campaign_id])
