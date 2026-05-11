-- Migration 087: siege_mines — Phase 9B siege mining and countermining state.
--
-- Per RAW daw_sieges.xml §siege_mining L388-421.
--
-- side='besieger' for an offensive siege mine; side='defender' for a countermine.
-- Each mine is an independent construction project (RAW L394: 1,000 gp each;
-- L399: 20,000 cubic feet of tunnel; L400: 20 cubic feet per 1gp per day).
-- Project cost in cp per project convention: 100,000 cp base.
--
-- workers_assigned ≤ 100 per RAW L396.
--
-- Weekly loyalty roll on workers (RAW L404 + L414); unmodified 2 = mining
-- accident → mine destroyed, all workers killed, engineer save vs Blast or die.
--
-- Detection: defender may make a daily reconnaissance roll to detect
-- besieger mines (RAW L410); once detected, defender may launch countermines.
--
-- Petards (RAW L398): a petard placed in a mine adds 100 × petard.damage
-- shp on detonation. Item layer doesn't yet exist in v1 — petard_damage is an
-- integer settable via debug action; full item integration deferred to v1.1+.
--
-- Limits (RAW L417-420):
--   - Stronghold built on solid rock cannot be mined.
--   - Stronghold entirely surrounded by water or by ≥10' moat: mining virtually
--     impossible. Both flags live on the strongholds row (added in a future
--     migration when grid-mapped strongholds land); v1 falls back to a
--     payload_json["mining_blocked"] = true on the sieges row, settable by
--     dispatcher heuristics.

CREATE TABLE IF NOT EXISTS siege_mines (
    id                          TEXT    PRIMARY KEY,
    siege_id                    TEXT    NOT NULL REFERENCES sieges(id),
    side                        TEXT    NOT NULL
        CHECK(side IN ('besieger', 'defender')),
    supervising_engineer_id     TEXT    REFERENCES characters(id),
    workers_assigned            INTEGER NOT NULL DEFAULT 0
        CHECK(workers_assigned BETWEEN 0 AND 100),
    cubic_feet_total            INTEGER NOT NULL DEFAULT 20000,
    cubic_feet_completed        INTEGER NOT NULL DEFAULT 0,
    construction_rate_cp_per_day INTEGER NOT NULL DEFAULT 0,
    petard_damage               INTEGER NOT NULL DEFAULT 0,
    is_detected                 INTEGER NOT NULL DEFAULT 0
        CHECK(is_detected IN (0, 1)),
    detected_calendar_day       INTEGER NOT NULL DEFAULT 0,
    is_completed                INTEGER NOT NULL DEFAULT 0
        CHECK(is_completed IN (0, 1)),
    is_destroyed_by_accident    INTEGER NOT NULL DEFAULT 0
        CHECK(is_destroyed_by_accident IN (0, 1)),
    detonated_calendar_day      INTEGER NOT NULL DEFAULT 0,
    countermine_target_id       TEXT    REFERENCES siege_mines(id),
    started_calendar_day        INTEGER NOT NULL DEFAULT 0,
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_siege_mines_siege
    ON siege_mines(siege_id, side);
CREATE INDEX IF NOT EXISTS idx_siege_mines_active
    ON siege_mines(siege_id)
    WHERE is_completed = 0 AND is_destroyed_by_accident = 0;
