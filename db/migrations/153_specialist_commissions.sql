-- Migration 153: Specialist commissions + sage kind (gdd-specialists.md v2.0,
-- dual-path ruling 2026-06-11).
--
-- 1. New `specialist_commissions` table — the COMMISSION path: a service
--    bought at a settlement guild, completing at a known calendar round,
--    collected later in that settlement. Deliverable is generic: a report
--    (text) or an item (item_key granted to inventory on collection). The
--    result is fixed at commission time (deterministic collection).
-- 2. Rebuild `specialists` to widen the kind CHECK with 'sage' (retainable
--    per the dual-path table; alchemist is commission-only and needs no
--    specialists rows). No other table FKs into specialists, so the rebuild
--    needs no legacy_alter_table guard (conventions §6.5).

CREATE TABLE IF NOT EXISTS specialist_commissions (
    commission_id         TEXT    PRIMARY KEY,
    campaign_id           TEXT    NOT NULL REFERENCES campaigns(id),
    party_id              TEXT    NOT NULL REFERENCES parties(id),
    settlement_id         TEXT    NOT NULL,
    kind                  TEXT    NOT NULL,
    service_id            TEXT    NOT NULL,
    service_label         TEXT    NOT NULL DEFAULT '',
    subject               TEXT    NOT NULL DEFAULT '',
    cost_cp               INTEGER NOT NULL DEFAULT 0,
    commissioned_at_round INTEGER NOT NULL DEFAULT 0,
    completes_at_round    INTEGER NOT NULL DEFAULT 0,
    result_kind           TEXT    NOT NULL DEFAULT 'report'
        CHECK(result_kind IN ('report', 'item')),
    result_payload        TEXT    NOT NULL DEFAULT '',
    collected             INTEGER NOT NULL DEFAULT 0 CHECK(collected IN (0, 1)),
    collected_at_round    INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_specialist_commissions_party
    ON specialist_commissions(campaign_id, party_id, collected);

-- 2. Widen specialists.kind CHECK ------------------------------------------

CREATE TABLE specialists_new (
    specialist_id        TEXT    PRIMARY KEY,
    campaign_id          TEXT    NOT NULL REFERENCES campaigns(id),
    party_id             TEXT    NOT NULL REFERENCES parties(id),
    kind                 TEXT    NOT NULL DEFAULT 'pathfinder'
        CHECK(kind IN ('pathfinder', 'land_surveyor', 'sage')),
    name                 TEXT    NOT NULL DEFAULT '',
    settlement_id        TEXT    NOT NULL DEFAULT '',
    hired_at_round       INTEGER NOT NULL DEFAULT 0,
    monthly_wage_cp      INTEGER NOT NULL DEFAULT 2500,
    last_paid_round      INTEGER NOT NULL DEFAULT -1,
    unpaid_months        INTEGER NOT NULL DEFAULT 0,
    closed               INTEGER NOT NULL DEFAULT 0 CHECK(closed IN (0, 1)),
    closed_reason        TEXT    NOT NULL DEFAULT ''
        CHECK(closed_reason IN ('', 'dismissed', 'unpaid', 'departed'))
);

INSERT INTO specialists_new SELECT * FROM specialists;

DROP INDEX IF EXISTS idx_specialists_party;
DROP TABLE specialists;
ALTER TABLE specialists_new RENAME TO specialists;

CREATE INDEX IF NOT EXISTS idx_specialists_party
    ON specialists(campaign_id, party_id, closed);
