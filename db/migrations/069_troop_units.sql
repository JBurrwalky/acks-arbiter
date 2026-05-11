-- Migration 069: Troop units (Domain Phase 5 — Troops Tab + Garrison Sub-Tab)
--
-- Per `daw_armies_recruitment.xml` §army_sources, six troop sources can stand
-- on the field at unit-scale: mercenaries, conscripts, militia, followers,
-- slave_soldiers, vassal_troops. This table is the canonical roster of every
-- mustered unit; the Troops tab roster, Garrison sub-tab, and future Phase 6+
-- army-warfare layer all read from here.
--
-- Per `daw_campaigns_troop_tables_summary.xml` §unit_characteristics_summary,
-- a unit's monthly cost = wage + specialist + 4 × weekly supply. Phase 5
-- captures monthly_cost_gp directly; the components live on the unit template
-- (`data/troops/unit_templates.json`) and are denormalized at hire time so
-- payroll math is a single column read.
--
-- starting_count is captured to support the §morale_and_loyalty 25%-casualties
-- Calamity threshold; current count decrements on each casualty event.
--
-- assignment_kind tracks the §service_limits operational state:
--   garrison        — holding a stronghold (assigned_stronghold_id is set)
--   on_campaign     — participating in a military campaign
--   available       — mustered but unassigned; full pay continues
--
-- status='departed' is the soft-delete flag for the future Departure Log
-- sub-tab (`gdd-troops-tab.md` §9). v1 keeps departed rows in this table so
-- Phase 11 can populate the Log without a schema migration.

CREATE TABLE IF NOT EXISTS troop_units (
    id                       TEXT    PRIMARY KEY,
    campaign_id              TEXT    NOT NULL REFERENCES campaigns(id),
    owner_character_id       TEXT    NOT NULL REFERENCES characters(id),
    assigned_domain_id       TEXT    REFERENCES domains(id),
    assigned_stronghold_id   TEXT    REFERENCES strongholds(id),

    source_type              TEXT    NOT NULL DEFAULT 'mercenary'
        CHECK(source_type IN (
            'mercenary', 'conscript', 'militia',
            'follower', 'slave_soldier', 'vassal'
        )),
    troop_type               TEXT    NOT NULL,
    race                     TEXT    NOT NULL DEFAULT 'human',
    tier                     TEXT    NOT NULL DEFAULT 'average'
        CHECK(tier IN ('untrained', 'average', 'veteran')),

    starting_count           INTEGER NOT NULL DEFAULT 0,
    count                    INTEGER NOT NULL DEFAULT 0,
    battle_rating            REAL    NOT NULL DEFAULT 0.0,
    monthly_wage_gp          INTEGER NOT NULL DEFAULT 0,
    monthly_supply_gp        INTEGER NOT NULL DEFAULT 0,
    monthly_specialist_gp    INTEGER NOT NULL DEFAULT 0,
    monthly_cost_gp          INTEGER NOT NULL DEFAULT 0,
    morale                   INTEGER NOT NULL DEFAULT 0,

    is_veteran               INTEGER NOT NULL DEFAULT 0
        CHECK(is_veteran IN (0, 1)),
    is_trained               INTEGER NOT NULL DEFAULT 1
        CHECK(is_trained IN (0, 1)),

    unit_xp                  INTEGER NOT NULL DEFAULT 0,
    assignment_kind          TEXT    NOT NULL DEFAULT 'available'
        CHECK(assignment_kind IN ('garrison', 'on_campaign', 'available')),
    hire_calendar_day        INTEGER NOT NULL DEFAULT 0,
    equipment_kit            TEXT    NOT NULL DEFAULT '',

    status                   TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'departed')),
    departure_kind           TEXT    NOT NULL DEFAULT '',
    departure_calendar_day   INTEGER NOT NULL DEFAULT 0,

    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_troop_units_campaign
    ON troop_units (campaign_id);
CREATE INDEX IF NOT EXISTS idx_troop_units_domain
    ON troop_units (assigned_domain_id);
CREATE INDEX IF NOT EXISTS idx_troop_units_owner
    ON troop_units (owner_character_id);
CREATE INDEX IF NOT EXISTS idx_troop_units_stronghold
    ON troop_units (assigned_stronghold_id);
