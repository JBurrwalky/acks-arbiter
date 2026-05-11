-- Migration 072: Army unit assignments (Phase 6A — units-to-armies link)
--
-- Per gdd-army-warfare.md §2.3. Joins troop_units (Phase 5 migration 069)
-- to armies (migration 070), routed under a parent_officer_id. A troop_unit
-- belongs to at most ONE army at any time — enforced via the partial unique
-- index on (troop_unit_id) WHERE released_calendar_day = 0.
--
-- role values come from PROJECT-DESIGNED marching-order columns
-- (gdd-army-warfare.md §2.3); RAW does not require role tracking but the
-- vanguard / main-body / rear-guard formation per
-- daw_campaigning_armies.xml §formation_requirements L91-97 needs it.
--
--   line     — default; participates in the deployed phase per zone eligibility
--   reserve  — begins battle in reserve zone (daw_axioms_pitching_battle.xml §deploy_troops L183-187)
--   baggage  — non-combatant supply train; absorbs hits last
--   scout    — cavalry/flyer used for the army's reconnaissance roll
--
-- release_reason captures the nature of detach for the unit's history log:
--   voluntary | casualty | desertion | disband | transfer
--
-- destination is either 'unaligned_pool' / 'garrison' / a target armies.id
-- (transfer); free-text by spec, validated only at write time in the repository.

CREATE TABLE IF NOT EXISTS army_unit_assignments (
    id                       TEXT    PRIMARY KEY,
    army_id                  TEXT    NOT NULL REFERENCES armies(id),
    troop_unit_id            TEXT    NOT NULL REFERENCES troop_units(id),
    parent_officer_id        TEXT    NOT NULL REFERENCES army_officers(id),
    role                     TEXT    NOT NULL DEFAULT 'line'
        CHECK(role IN ('line', 'reserve', 'baggage', 'scout')),
    assigned_calendar_day    INTEGER NOT NULL DEFAULT 0,
    released_calendar_day    INTEGER NOT NULL DEFAULT 0,
    release_reason           TEXT    NOT NULL DEFAULT ''
        CHECK(release_reason IN (
            '', 'voluntary', 'casualty', 'desertion', 'disband', 'transfer'
        )),
    destination              TEXT    NOT NULL DEFAULT '',
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_army_assignments_army
    ON army_unit_assignments(army_id);
CREATE INDEX IF NOT EXISTS idx_army_assignments_unit
    ON army_unit_assignments(troop_unit_id);
CREATE INDEX IF NOT EXISTS idx_army_assignments_officer
    ON army_unit_assignments(parent_officer_id);

-- A troop_unit may appear in at most one active assignment (released = 0).
-- SQLite supports partial unique indexes per CREATE INDEX docs.
CREATE UNIQUE INDEX IF NOT EXISTS uq_army_assignments_active_unit
    ON army_unit_assignments(troop_unit_id)
    WHERE released_calendar_day = 0;
