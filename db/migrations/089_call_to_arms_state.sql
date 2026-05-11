-- Migration 089: Phase 9C call-to-arms muster state.
--
-- Per RAW daw_armies_recruitment.xml §vassal_troops L656-702.
--
-- magnitude_pct on vassal_obligations:
--   50  = RAW minimum half garrison (default)
--   100 = full garrison (counts as 2 duties per RAW L660 — provokes Henchman
--         Morale roll unless offset by a boon)
--   Other percentages allowed for partial-magnitude variants (rounded to
--   nearest duty count via banker's rounding in the favors_duties dispatcher).
--
-- call_to_arms_state row tracks the lifecycle of a single call:
--   - obligation_id    → the vassal_obligations row that issued the call
--   - lord_army_id     → the army receiving the called troops (created by
--                        CallToArmsHandler.issue_call)
--   - period_unit      → 'week' / 'month' / 'season' (from RAW table by title)
--   - target_total_units → number of troop_units to be transferred
--   - units_arrived_*_tranche → tally per RAW L675-677
--                                (½ ceil first, ¼ floor min 1 second, remainder third)
--   - is_completed     → 1 once the third tranche fully arrives

ALTER TABLE vassal_obligations ADD COLUMN magnitude_pct INTEGER NOT NULL DEFAULT 50;

CREATE TABLE IF NOT EXISTS call_to_arms_state (
    id                          TEXT    PRIMARY KEY,
    obligation_id               TEXT    NOT NULL REFERENCES vassal_obligations(id),
    lord_army_id                TEXT    NOT NULL REFERENCES armies(id),
    vassal_character_id         TEXT    NOT NULL REFERENCES characters(id),
    issued_calendar_day         INTEGER NOT NULL,
    period_unit                 TEXT    NOT NULL DEFAULT 'week'
        CHECK(period_unit IN ('week', 'month', 'season')),
    period_days                 INTEGER NOT NULL DEFAULT 7,
    target_total_units          INTEGER NOT NULL DEFAULT 0,
    units_arrived_first_tranche  INTEGER NOT NULL DEFAULT 0,
    units_arrived_second_tranche INTEGER NOT NULL DEFAULT 0,
    units_arrived_third_tranche  INTEGER NOT NULL DEFAULT 0,
    is_completed                INTEGER NOT NULL DEFAULT 0
        CHECK(is_completed IN (0, 1)),
    revoked_calendar_day        INTEGER NOT NULL DEFAULT 0,
    payload_json                TEXT    NOT NULL DEFAULT '{}',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_call_to_arms_state_obligation
    ON call_to_arms_state(obligation_id);
CREATE INDEX IF NOT EXISTS idx_call_to_arms_state_lord_army
    ON call_to_arms_state(lord_army_id);
CREATE INDEX IF NOT EXISTS idx_call_to_arms_state_vassal
    ON call_to_arms_state(vassal_character_id);

-- One active (non-revoked) call_to_arms per obligation. Multiple historical
-- rows allowed if the same obligation is later re-issued.
CREATE UNIQUE INDEX IF NOT EXISTS idx_call_to_arms_state_unique_active
    ON call_to_arms_state(obligation_id) WHERE revoked_calendar_day = 0;
