-- Migration 077: Battle log (Phase 6B — append-only event trace)
--
-- Per gdd-army-warfare.md §2.6. One row per player-visible decision and
-- every die roll generates a log entry. The Inspect-math affordance walks
-- the log forward turn-by-turn and renders each event's payload_json
-- breakdown (every modifier, every die, every cascade).
--
-- The event_type enumeration is open-ended (TEXT) but the build_log /
-- gdd-army-warfare.md §2.6 documents the canonical list:
--   battle_started, surprise_resolved, terrain_advantage_resolved,
--   units_deployed, phase_started, participating_br_totaled,
--   heroic_foray_declared, heroic_foray_resolved, attack_throws_rolled,
--   hits_applied, unit_destroyed, morale_check_started, unit_morale_rolled,
--   redeployment_chosen, advance_hold_withdraw_chosen, bpc_adjusted,
--   phase_ended, battle_ended, pursuit_resolved, casualties_calculated,
--   spoils_calculated, vagary_of_battle_rolled
--
-- sequence_number is monotonic per battle; UNIQUE(battle_id, sequence_number)
-- enforces. Read via ORDER BY sequence_number.
--
-- payload_json carries all the structured detail per event (e.g. attack-throw
-- arrays, modifier breakdowns, cascade transitions). The UI's Inspect-math
-- tooltip renders this in human-readable form.

CREATE TABLE IF NOT EXISTS battle_log (
    id                       TEXT    PRIMARY KEY,
    battle_id                TEXT    NOT NULL REFERENCES field_battles(id),
    sequence_number          INTEGER NOT NULL,
    turn_number              INTEGER NOT NULL DEFAULT 1,
    phase                    TEXT    NOT NULL DEFAULT '',
    bpc_at_event             INTEGER NOT NULL DEFAULT 0,
    event_type               TEXT    NOT NULL,
    side                     TEXT    NOT NULL DEFAULT ''
        CHECK(side IN ('', 'attacker', 'defender')),
    payload_json             TEXT    NOT NULL DEFAULT '{}',
    created_calendar_day     INTEGER NOT NULL DEFAULT 0,
    created_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (battle_id, sequence_number)
);

CREATE INDEX IF NOT EXISTS idx_battle_log_battle
    ON battle_log(battle_id, sequence_number);
CREATE INDEX IF NOT EXISTS idx_battle_log_event_type
    ON battle_log(event_type);
