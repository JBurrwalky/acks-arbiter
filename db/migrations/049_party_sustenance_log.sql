-- Migration 049: Party sustenance daily log (Wilderness closure Phase 3)
--
-- Append-only audit log of daily food/water consumption + HP loss applied to
-- a party. Powers the Notebook Party-tab "last 7 days" status panel and any
-- future analytics that want to surface "your party has been losing 1 hp/day
-- for 4 days" without re-deriving from current counters.
--
-- The runtime sustenance counters (exhaustion_days / starvation_days /
-- dehydration_days / ration_units / water_units) live on `party_state`
-- (migration 047). This table records the per-day effect that produced the
-- current counter values so the player can scroll a history.
--
-- Per acore_adventures_and_encounters.xml §rations_and_foraging:
--   * food: 2 days grace, then 1 hp/day, no natural healing during deficit
--   * water: 1 day → 1d4 hp + 1d4/day, healing lost when first die rolled
--
-- Phase 3 inserts a row each day-tick. Phase 3.5 may add an index on
-- (party_id, day_index DESC) when a multi-day query becomes load-bearing.

CREATE TABLE IF NOT EXISTS party_sustenance_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    party_id TEXT NOT NULL REFERENCES parties(id),
    day_index INTEGER NOT NULL,
    food_consumed INTEGER NOT NULL DEFAULT 0,
    water_consumed INTEGER NOT NULL DEFAULT 0,
    food_foraged INTEGER NOT NULL DEFAULT 0,
    water_foraged INTEGER NOT NULL DEFAULT 0,
    hp_lost INTEGER NOT NULL DEFAULT 0,
    starvation_days_after INTEGER NOT NULL DEFAULT 0,
    dehydration_days_after INTEGER NOT NULL DEFAULT 0,
    exhaustion_days_after INTEGER NOT NULL DEFAULT 0,
    notes TEXT NOT NULL DEFAULT '',
    logged_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_party_sustenance_log_party_day
    ON party_sustenance_log (party_id, day_index DESC);
