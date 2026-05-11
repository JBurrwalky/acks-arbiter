-- Migration 070: Armies (Phase 6A — DaW Army Warfare composition layer)
--
-- Per gdd-army-warfare.md §2.1 the armies table is the Phase 6A aggregate
-- entity. Each army has one apex commander (command_character_id), one
-- political owner (political_owner_id; PC ruler / NPC liege), zero-or-more
-- officers (army_officers, migration 071), and zero-or-more units
-- (army_unit_assignments, migration 072) drawing from the troop_units
-- pool created by Phase 5 migration 069.
--
-- IDs are TEXT to match the established codebase convention; the GDD's
-- INTEGER PRIMARY KEY AUTOINCREMENT spec is overridden in favor of the
-- TEXT/UUID pattern used everywhere else in the schema.
--
-- state machine: assembling → encamped → {marching|requisitioning|looting|
-- besieging|battling|withdrawing} → encamped → ... → disbanded.
-- See gdd-army-warfare.md §2.1 for the full diagram and per-state
-- definitions; the requisitioning vs. looting split per RAW
-- daw_campaigning_armies.xml §requisition_and_looting L324-347.
--
-- garrison_stronghold_id ties an assembling army to its forming stronghold
-- and is preserved for the lifetime of the army as the default rally point.
-- map_id / hex_q / hex_r are NULL while assembling and populated on activate.
--
-- forced_march_bonus_expires_leg_id holds the active travel_leg id for which
-- the +2 collision-tiebreaker bonus is valid; cleared when the leg fires its
-- arrival event (per gdd-army-warfare.md §4.9.4).
--
-- consecutive_marching_days backs the lazy daily-effect accumulator
-- (gdd-army-warfare.md §4.9.7); incremented per game-day in marching state
-- (×2 for forced-march days), decremented per full game-day encamped.
--
-- daily_penalty_state JSON holds {lack_of_supply_started_day_index,
-- consecutive_marching_days, severe_weather_started_day_index,
-- severe_weather_kind} per the schema in gdd-army-warfare.md §4.9.7.
--
-- last_returned_to_garrison_day_index drives the >30-game-day "out of
-- garrison" eligibility test for vagaries-of-war (§4.9.5).
--
-- rng_seed_stream is the per-army deterministic RNG seed used by the supply
-- tick / vagary roll / collision tiebreaker code so save-load reproduces the
-- same sequence (§4.9.1 determinism rule).

CREATE TABLE IF NOT EXISTS armies (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    name                            TEXT    NOT NULL,
    political_owner_id              TEXT    NOT NULL REFERENCES characters(id),
    command_character_id            TEXT    NOT NULL REFERENCES characters(id),

    state                           TEXT    NOT NULL DEFAULT 'assembling'
        CHECK(state IN (
            'assembling', 'encamped', 'marching',
            'requisitioning', 'looting', 'besieging',
            'battling', 'withdrawing', 'disbanded'
        )),

    map_id                          TEXT    REFERENCES hex_maps(id),
    hex_q                           INTEGER,
    hex_r                           INTEGER,
    garrison_stronghold_id          TEXT    REFERENCES strongholds(id),

    formed_calendar_day             INTEGER NOT NULL DEFAULT 0,
    disbanded_calendar_day          INTEGER NOT NULL DEFAULT 0,

    unit_scale                      TEXT    NOT NULL DEFAULT 'platoon'
        CHECK(unit_scale IN ('platoon', 'company', 'battalion', 'brigade')),
    strategic_stance                TEXT    NOT NULL DEFAULT 'defensive'
        CHECK(strategic_stance IN ('offensive', 'defensive', 'evasive')),

    forced_march_bonus_expires_leg_id TEXT NOT NULL DEFAULT '',
    consecutive_marching_days       INTEGER NOT NULL DEFAULT 0,
    last_returned_to_garrison_day_index INTEGER NOT NULL DEFAULT 0,
    daily_penalty_state             TEXT    NOT NULL DEFAULT '{}',
    rng_seed_stream                 INTEGER NOT NULL DEFAULT 0,

    notes                           TEXT    NOT NULL DEFAULT '',
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_armies_campaign
    ON armies(campaign_id);
CREATE INDEX IF NOT EXISTS idx_armies_owner
    ON armies(political_owner_id);
CREATE INDEX IF NOT EXISTS idx_armies_command
    ON armies(command_character_id);
CREATE INDEX IF NOT EXISTS idx_armies_state
    ON armies(state);
CREATE INDEX IF NOT EXISTS idx_armies_hex
    ON armies(map_id, hex_q, hex_r);
