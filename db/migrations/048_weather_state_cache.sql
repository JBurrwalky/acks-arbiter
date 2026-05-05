-- Migration 048: Weather state cache (Wilderness closure Phase 2)
--
-- Stores generated weather states keyed on (campaign_id, hex_q, hex_r,
-- julian_day, year). Lazy: WeatherCache.get_or_generate() reads first,
-- generates and stores on miss. The cache is the source of truth for any
-- weather already presented to the player; the generator's deterministic
-- output is reproducible but the cache supersedes it (so a future biome
-- change on a hex does not retroactively rewrite past days).
--
-- An index on (campaign_id, julian_day) supports the future Phase 2.5
-- regional-front sweep that walks all stored hexes for a given day to
-- propagate coherent weather. Queries by single-hex-day go through the
-- composite primary key.

CREATE TABLE IF NOT EXISTS weather_states (
    campaign_id TEXT NOT NULL,
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    julian_day INTEGER NOT NULL,
    year INTEGER NOT NULL DEFAULT 1,
    temperature_band INTEGER NOT NULL DEFAULT 3,
    atmosphere TEXT NOT NULL DEFAULT 'calm',
    precipitation_level INTEGER NOT NULL DEFAULT 0,
    precipitation_type TEXT NOT NULL DEFAULT 'none',
    wind_level INTEGER NOT NULL DEFAULT 2,
    visibility_multiplier REAL NOT NULL DEFAULT 1.0,
    produces_mud INTEGER NOT NULL DEFAULT 0 CHECK(produces_mud IN (0, 1)),
    generated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (campaign_id, hex_q, hex_r, julian_day, year)
);

CREATE INDEX IF NOT EXISTS idx_weather_states_campaign_day
    ON weather_states (campaign_id, julian_day);
