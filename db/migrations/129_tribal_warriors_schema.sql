-- Migration 129: tribal warriors schema per gdd-tribal-warriors.md §4.1
-- and Phase 11D.5 of docs/phase-11-plan.md.
--
-- Three changes:
--   (a) Full rebuild of `troop_units` — extends `source_type` CHECK with
--       'tribal_warrior'; adds `months_without_qualifying_spoils` INTEGER
--       column (the 3-month-spoils morale-trigger counter per RAW
--       ax_domains_of_chaos.xml:456).
--   (b) Extends `domain_departure_log` event_type CHECK with the six
--       new tribal-warrior event types per GDD §4.1.
--   (c) Adds `domains.available_tribal_warriors` INTEGER column. Seeded
--       to `peasant_families` for clanhold-style rows; 0 for civilized.
--       Maintained by the levy/stand-down/casualty/population-change paths
--       per GDD §3.
--
-- SQLite cannot ALTER a CHECK constraint in place, so the troop_units
-- and domain_departure_log changes use the legacy_alter_table rebuild
-- pattern from migrations 117 / 119 / 125 / 126 / 127 / 128. The
-- domains addition is a clean ADD COLUMN.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- (a) Rebuild troop_units — extend source_type CHECK + add
--     months_without_qualifying_spoils column.
-- ---------------------------------------------------------------------------

ALTER TABLE troop_units RENAME TO troop_units_old;

CREATE TABLE troop_units (
    id                       TEXT    PRIMARY KEY,
    campaign_id              TEXT    NOT NULL REFERENCES campaigns(id),
    owner_character_id       TEXT    NOT NULL REFERENCES characters(id),
    assigned_domain_id       TEXT    REFERENCES domains(id),
    assigned_stronghold_id   TEXT    REFERENCES strongholds(id),
    source_type              TEXT    NOT NULL DEFAULT 'mercenary'
        CHECK(source_type IN (
            'mercenary', 'conscript', 'militia',
            'follower', 'slave_soldier', 'vassal',
            'tribal_warrior'  -- migration 129: Phase 11D.5
        )),
    troop_type               TEXT    NOT NULL,
    race                     TEXT    NOT NULL DEFAULT 'human',
    tier                     TEXT    NOT NULL DEFAULT 'average'
        CHECK(tier IN ('untrained', 'average', 'veteran')),
    starting_count           INTEGER NOT NULL DEFAULT 0,
    count                    INTEGER NOT NULL DEFAULT 0,
    battle_rating            REAL    NOT NULL DEFAULT 0.0,
    monthly_wage_cp          INTEGER NOT NULL DEFAULT 0,
    monthly_supply_cp        INTEGER NOT NULL DEFAULT 0,
    monthly_specialist_cp    INTEGER NOT NULL DEFAULT 0,
    monthly_cost_cp          INTEGER NOT NULL DEFAULT 0,
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
    is_diseased                  INTEGER NOT NULL DEFAULT 0
        CHECK(is_diseased IN (0, 1)),
    disease_type                 TEXT    NOT NULL DEFAULT '',
    disease_recovery_calendar_day INTEGER NOT NULL DEFAULT 0,
    disease_save_failed_by       INTEGER NOT NULL DEFAULT 0,
    disease_natural_roll         INTEGER NOT NULL DEFAULT 0,
    save_vs_death                INTEGER NOT NULL DEFAULT 14,
    -- Migration 129 (Phase 11D.5): 3-month-spoils morale-trigger counter
    -- per RAW ax_domains_of_chaos.xml:456 + gdd-tribal-warriors.md §7.
    -- Incremented on monthly tick if the unit's spoils-share for the month
    -- fell short of its wages; reset to 0 on a qualifying month; the
    -- ReligionConversionResolver-analogous morale-roll trigger fires when
    -- this hits 3. Civilized troop types (mercenary/conscript/etc) leave
    -- this at 0 forever — only tribal_warrior source_type consults it.
    months_without_qualifying_spoils INTEGER NOT NULL DEFAULT 0
        CHECK(months_without_qualifying_spoils >= 0),
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO troop_units (
    id, campaign_id, owner_character_id, assigned_domain_id,
    assigned_stronghold_id, source_type, troop_type, race, tier,
    starting_count, count, battle_rating,
    monthly_wage_cp, monthly_supply_cp, monthly_specialist_cp, monthly_cost_cp,
    morale, is_veteran, is_trained, unit_xp,
    assignment_kind, hire_calendar_day, equipment_kit,
    status, departure_kind, departure_calendar_day,
    is_diseased, disease_type, disease_recovery_calendar_day,
    disease_save_failed_by, disease_natural_roll, save_vs_death,
    months_without_qualifying_spoils,
    created_at
)
SELECT
    id, campaign_id, owner_character_id, assigned_domain_id,
    assigned_stronghold_id, source_type, troop_type, race, tier,
    starting_count, count, battle_rating,
    monthly_wage_cp, monthly_supply_cp, monthly_specialist_cp, monthly_cost_cp,
    morale, is_veteran, is_trained, unit_xp,
    assignment_kind, hire_calendar_day, equipment_kit,
    status, departure_kind, departure_calendar_day,
    is_diseased, disease_type, disease_recovery_calendar_day,
    disease_save_failed_by, disease_natural_roll, save_vs_death,
    0,  -- months_without_qualifying_spoils starts at 0 for all existing units
    created_at
FROM troop_units_old;

DROP TABLE troop_units_old;

CREATE INDEX IF NOT EXISTS idx_troop_units_campaign
    ON troop_units (campaign_id);
CREATE INDEX IF NOT EXISTS idx_troop_units_domain
    ON troop_units (assigned_domain_id);
CREATE INDEX IF NOT EXISTS idx_troop_units_owner
    ON troop_units (owner_character_id);
CREATE INDEX IF NOT EXISTS idx_troop_units_stronghold
    ON troop_units (assigned_stronghold_id);
CREATE INDEX IF NOT EXISTS idx_troop_units_diseased
    ON troop_units(is_diseased) WHERE is_diseased = 1;
CREATE INDEX IF NOT EXISTS idx_troop_units_disease_recovery
    ON troop_units(disease_recovery_calendar_day) WHERE is_diseased = 1;

-- ---------------------------------------------------------------------------
-- (b) Rebuild domain_departure_log — extend event_type CHECK with the six
--     new tribal-warrior event types.
-- ---------------------------------------------------------------------------

ALTER TABLE domain_departure_log RENAME TO domain_departure_log_old;

CREATE TABLE domain_departure_log (
    id                       TEXT    PRIMARY KEY,
    campaign_id              TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                TEXT    NOT NULL,
    calendar_day             INTEGER NOT NULL,
    event_type               TEXT    NOT NULL
        CHECK(event_type IN (
            'established',
            'classification_advanced',
            'classification_regressed',
            'territory_lost',
            'stronghold_lost',
            'defeat',
            'pillaged',
            'ruler_changed',
            'ruler_died',
            'succession_started',
            'succession_resolved',
            'succession_lapsed',
            'vassal_lost',
            'vassal_promoted',
            'religion_converted',
            'monster_settled',
            'calamity',
            'morale_tier_dropped',
            'conquered',
            'abandoned',
            'restored',
            -- Migration 129 (Phase 11D.5) tribal-warrior event types
            -- per gdd-tribal-warriors.md §4.1.
            'tribal_warriors_levied',
            'tribal_warriors_stood_down',
            'tribal_warriors_released_for_population_loss',
            'tribal_warriors_morale_check_triggered',
            'tribal_warriors_loyalty_failed',
            'tribal_warriors_called_to_arms'
        )),
    summary                  TEXT    NOT NULL DEFAULT '',
    full_details_json        TEXT    NOT NULL DEFAULT '{}',
    related_ledger_entry_ids TEXT    NOT NULL DEFAULT '[]',
    related_encounter_ids    TEXT    NOT NULL DEFAULT '[]',
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO domain_departure_log (
    id, campaign_id, domain_id, calendar_day, event_type, summary,
    full_details_json, related_ledger_entry_ids, related_encounter_ids, created_at
)
SELECT
    id, campaign_id, domain_id, calendar_day, event_type, summary,
    full_details_json, related_ledger_entry_ids, related_encounter_ids, created_at
FROM domain_departure_log_old;

DROP TABLE domain_departure_log_old;

CREATE INDEX IF NOT EXISTS idx_domain_departure_log_domain_calendar
    ON domain_departure_log(domain_id, calendar_day DESC);
CREATE INDEX IF NOT EXISTS idx_domain_departure_log_campaign_calendar
    ON domain_departure_log(campaign_id, calendar_day DESC);

-- ---------------------------------------------------------------------------
-- (c) Add domains.available_tribal_warriors per GDD §4.1.
-- Seeded to peasant_families for clanhold-style rows; 0 elsewhere. Civilized
-- rows leave it at 0 forever (the helpers short-circuit when style != clanhold).
-- Maintained by levy / stand-down / casualty / population-growth paths.
-- ---------------------------------------------------------------------------

ALTER TABLE domains ADD COLUMN available_tribal_warriors INTEGER NOT NULL DEFAULT 0;
UPDATE domains
SET available_tribal_warriors = peasant_families
WHERE domain_style = 'clanhold';

COMMIT;

PRAGMA foreign_keys = ON;
