-- Migration 053: Specialists subsystem (Wilderness closure Phase 6).
--
-- Specialists are non-adventuring monthly hires per
-- `acore_equipment.xml §specialists` — flat monthly wage, no morale, no
-- advancement, EXEMPT from the henchman cap. Phase 6 ships the wilderness
-- scout types from `le_wilderness_lair_rules.xml §hirelings`:
--   pathfinder      — 1st level explorer with Pathfinder template
--   land_surveyor   — 1st level explorer with Cartographer template
-- Both 25 gp/month. Other specialist kinds (alchemist, sage, etc. from
-- acore_equipment.xml) can be added later by extending the catalog and
-- the `kind` CHECK constraint.
--
-- Note: specialists are stored in their own table — NOT in `characters` —
-- because they have no class progression, no proficiency rows, no inventory,
-- and no party_members linkage. They reuse PartyWallet for wages and emit
-- through the existing `wages_processed` flow alongside henchmen.

CREATE TABLE IF NOT EXISTS specialists (
    specialist_id        TEXT    PRIMARY KEY,
    campaign_id          TEXT    NOT NULL REFERENCES campaigns(id),
    party_id             TEXT    NOT NULL REFERENCES parties(id),
    kind                 TEXT    NOT NULL DEFAULT 'pathfinder'
        CHECK(kind IN ('pathfinder', 'land_surveyor')),
    name                 TEXT    NOT NULL DEFAULT '',
    settlement_id        TEXT    NOT NULL DEFAULT '',
    hired_at_round       INTEGER NOT NULL DEFAULT 0,
    monthly_wage_gp      INTEGER NOT NULL DEFAULT 25,
    last_paid_round      INTEGER NOT NULL DEFAULT -1,
    unpaid_months        INTEGER NOT NULL DEFAULT 0,
    closed               INTEGER NOT NULL DEFAULT 0 CHECK(closed IN (0, 1)),
    closed_reason        TEXT    NOT NULL DEFAULT ''
        CHECK(closed_reason IN ('', 'dismissed', 'unpaid', 'departed'))
);

CREATE INDEX IF NOT EXISTS idx_specialists_party
    ON specialists(campaign_id, party_id, closed);
