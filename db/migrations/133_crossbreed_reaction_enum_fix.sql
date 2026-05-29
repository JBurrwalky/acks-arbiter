-- Migration 133: correct the `crossbreed_instances.initial_reaction` CHECK
-- constraint to match the RAW ACKS Monster Reaction table.
--
-- Root cause of the test_phase_10b1f regression:
--   Migration 096 wrote the reaction enum as
--     ('hostile', 'unfriendly', 'neutral', 'friendly', 'helpful')
--   misreading the RAW table's "12+  Friendly, helpful" row — "helpful" is the
--   DESCRIPTOR of the Friendly tier, not a separate tier — and it DROPPED the
--   real 9-11 tier "indifferent".
--
--   RAW: rules/acore_adventures_and_encounters.xml:936-958 — Monster Reaction
--   table tiers are exactly:
--     2-    Hostile
--     3-5   Unfriendly
--     6-8   Neutral
--     9-11  Indifferent
--     12+   Friendly
--   (The crossbreed control rule, acore-campaign-general-and-magic-research.xml
--   :479-483, says the Judge "makes a reaction roll" — i.e. this same table.)
--
--   MagicalResearchCrossbreed.roll_initial_reaction() correctly returns
--   "indifferent" for an adjusted 2d6 of 9-11 (the RAW-faithful tier, and the
--   project-wide disposition vocabulary used by attitude.gd, encounter_data.gd,
--   reputation migration 025, etc.). With the auto-roll added 2026-05-19, ~25%
--   of crossbreed crafts roll "indifferent" and the INSERT failed the bad CHECK,
--   so create_crossbreed_instance returned "" intermittently.
--
-- Fix: rebuild crossbreed_instances with the RAW-correct enum
--   ('hostile', 'unfriendly', 'neutral', 'indifferent', 'friendly').
-- Any pre-existing row that used the deprecated 'helpful' value is migrated to
-- its RAW tier 'friendly' during the copy (non-destructive).
--
-- Nothing references crossbreed_instances via FK (it is a leaf table), so the
-- rebuild is a simple rename/create/copy/drop. Pattern follows Migrations
-- 011 / 013 / 014 / 035 / 117; legacy_alter_table guard included for parity
-- with 117 (harmless here since there are no inbound FK references).

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

ALTER TABLE crossbreed_instances RENAME TO crossbreed_instances_old;

CREATE TABLE crossbreed_instances (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    species_id                  TEXT    NOT NULL REFERENCES crossbreed_species(id),
    creator_character_id        TEXT    NOT NULL REFERENCES characters(id),
    owner_character_id          TEXT REFERENCES characters(id),
    name                        TEXT    NOT NULL,
    hp_max                      INTEGER NOT NULL DEFAULT 1
        CHECK(hp_max >= 1),
    hp_current                  INTEGER NOT NULL DEFAULT 1,
    location_kind               TEXT    NOT NULL DEFAULT 'stronghold'
        CHECK(location_kind IN ('stronghold', 'with_owner', 'wilderness_hex', 'dungeon_room', 'laboratory', 'other')),
    location_ref                TEXT    NOT NULL DEFAULT '',
    laboratory_id               TEXT REFERENCES laboratories(id),
    -- Reaction at birth per RAW L479-483 -> general Monster Reaction table
    -- (acore_adventures_and_encounters.xml:936-958). NULL = not yet resolved.
    initial_reaction            TEXT
        CHECK(initial_reaction IS NULL OR initial_reaction IN ('hostile', 'unfriendly', 'neutral', 'indifferent', 'friendly')),
    status                      TEXT    NOT NULL DEFAULT 'alive'
        CHECK(status IN ('alive', 'escaped', 'killed', 'controlled')),
    gp_cost_total               INTEGER NOT NULL DEFAULT 0,
    days_to_create              INTEGER NOT NULL DEFAULT 0,
    created_calendar_day        INTEGER NOT NULL DEFAULT 0,
    killed_calendar_day         INTEGER,
    notes                       TEXT    NOT NULL DEFAULT '',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO crossbreed_instances (
    id, campaign_id, species_id, creator_character_id, owner_character_id,
    name, hp_max, hp_current, location_kind, location_ref, laboratory_id,
    initial_reaction, status, gp_cost_total, days_to_create,
    created_calendar_day, killed_calendar_day, notes, created_at, updated_at
)
SELECT
    id, campaign_id, species_id, creator_character_id, owner_character_id,
    name, hp_max, hp_current, location_kind, location_ref, laboratory_id,
    CASE WHEN initial_reaction = 'helpful' THEN 'friendly' ELSE initial_reaction END,
    status, gp_cost_total, days_to_create,
    created_calendar_day, killed_calendar_day, notes, created_at, updated_at
FROM crossbreed_instances_old;

DROP TABLE crossbreed_instances_old;

CREATE INDEX IF NOT EXISTS idx_crossbreed_instances_creator
    ON crossbreed_instances (creator_character_id);
CREATE INDEX IF NOT EXISTS idx_crossbreed_instances_species
    ON crossbreed_instances (species_id);
CREATE INDEX IF NOT EXISTS idx_crossbreed_instances_status
    ON crossbreed_instances (status);

COMMIT;

PRAGMA legacy_alter_table = OFF;
PRAGMA foreign_keys = ON;
