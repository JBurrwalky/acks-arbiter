-- Migration 062: Stronghold accessories (Domain Phase 1)
--
-- Per `acore_stronghold_construction_costs.pdf` p.127 "Structure Accessories
-- Costs" table. Accessories are upgrade items (arrow slits, doors, secret
-- doors, floors, shutters, shifting walls, stairs) that can be added to a
-- structure at construction time for 25% of the listed base cost, or after
-- the fact at full cost.
--
-- Phase 1 ships the schema; the catalog of accessory types lives in
-- data/strongholds/structure_catalog.json under the "accessories" section.
-- Phase 4's Stronghold sub-tab will surface the picker; Phase 8 (sieges)
-- consumes shp / status for damage tracking.

CREATE TABLE IF NOT EXISTS stronghold_accessories (
    id              TEXT    PRIMARY KEY,
    stronghold_id   TEXT    NOT NULL REFERENCES strongholds(id),
    -- accessory_type matches an "id" entry in data/strongholds/structure_catalog.json
    -- "accessories" section (e.g., "arrow_slit", "door_iron", "shifting_wall").
    accessory_type  TEXT    NOT NULL,
    gp_value        INTEGER NOT NULL DEFAULT 0,
    status          TEXT    NOT NULL DEFAULT 'planned'
        CHECK(status IN ('planned', 'in_progress', 'completed', 'destroyed')),
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_accessories_stronghold
    ON stronghold_accessories (stronghold_id);
