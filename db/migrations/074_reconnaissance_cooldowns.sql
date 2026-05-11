-- Migration 074: Reconnaissance cooldowns (Phase 6A — recon rate-limiting)
--
-- Per gdd-army-warfare.md §4.9.6: the engine rate-limits reconnaissance to
-- at most one roll per opposing-army-pair per game-day, anchored to the
-- most recent recon-roll timestamp on that pair. RAW
-- daw_campaigning_armies.xml §reconnaissance.frequency L380-398 fires recon
-- "after each army completes movement" — in RAW that's once per game-week
-- (one move per week assumed). In Arbiter an army may complete several
-- travel_leg arrivals per game-day if marching at high speed; without the
-- cap the engine would generate dozens of recon rolls per opposing-army-pair
-- per day.
--
-- The (observer_army_id, observed_army_id) pair is directional — A observing
-- B is independent of B observing A. Both directions roll independently with
-- their own cooldown rows.
--
-- last_result is the textual recon-result tier per the table at
-- §reconnaissance.results_of_reconnaissance L512-576 (e.g., "marginal_success",
-- "major_failure"). Stored for after-the-fact UI display.

CREATE TABLE IF NOT EXISTS reconnaissance_cooldowns (
    observer_army_id        TEXT    NOT NULL REFERENCES armies(id),
    observed_army_id        TEXT    NOT NULL REFERENCES armies(id),
    last_roll_calendar_day  INTEGER NOT NULL DEFAULT 0,
    last_result             TEXT    NOT NULL DEFAULT '',
    PRIMARY KEY (observer_army_id, observed_army_id)
);

CREATE INDEX IF NOT EXISTS idx_recon_cooldowns_observer
    ON reconnaissance_cooldowns(observer_army_id);
