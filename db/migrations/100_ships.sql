-- Migration 100: ships persistence table (Phase 10B prereq, wave Prereq.5a).
--
-- Per generation/gdd-settlement-economy.md §9.2. Ships parallel the existing
-- draft_vehicles table (migration 024) for sea vessels. One row per vessel
-- with per-ship SHP, location, crew composition, and cached monthly
-- operating cost from the maritime.json catalog.
--
-- Cargo capacity (cargo_capacity_stone) is consumed by CargoEncumbranceCalculator
-- (Prereq.5b) which sums cargo_holds.loads_count * load_weight_stone against
-- it. Ships in v1 do NOT carry inventory_items (personal gear stays on
-- character inventories) per GDD §9.5.
--
-- Location tracking: moored at a settlement_entrances row, at sea, or
-- wrecked (preserved for cargo recovery). is_destroyed is the soft-delete
-- flag the API consults to filter active ships.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS ships (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    party_id                        TEXT    REFERENCES parties(id),
    vessel_key                      TEXT    NOT NULL,
    name                            TEXT    NOT NULL DEFAULT 'Unnamed Vessel',
    shp_max                         INTEGER NOT NULL DEFAULT 0,
    shp_current                     INTEGER NOT NULL DEFAULT 0,
    cargo_capacity_stone            INTEGER NOT NULL DEFAULT 0,
    crew_captain                    INTEGER NOT NULL DEFAULT 0,
    crew_sailors                    INTEGER NOT NULL DEFAULT 0,
    crew_rowers                     INTEGER NOT NULL DEFAULT 0,
    crew_marines                    INTEGER NOT NULL DEFAULT 0,
    monthly_operating_cost_gp       INTEGER NOT NULL DEFAULT 0,
    current_location_kind           TEXT    NOT NULL DEFAULT 'moored'
        CHECK(current_location_kind IN ('moored', 'at_sea', 'wrecked')),
    moored_at_settlement_id         TEXT    REFERENCES settlement_entrances(id),
    is_destroyed                    INTEGER NOT NULL DEFAULT 0
        CHECK(is_destroyed IN (0, 1)),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ships_party
    ON ships(party_id, is_destroyed);
CREATE INDEX IF NOT EXISTS idx_ships_campaign
    ON ships(campaign_id, is_destroyed);
CREATE INDEX IF NOT EXISTS idx_ships_moored
    ON ships(moored_at_settlement_id);

COMMIT;
