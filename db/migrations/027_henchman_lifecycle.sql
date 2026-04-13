-- Migration 027: Henchman lifecycle (Phase G-2)
--
-- Henchman pool per settlement (monthly availability generation),
-- pool members with weekly allotment tracking,
-- extended henchman state beyond the core characters table.

CREATE TABLE IF NOT EXISTS henchman_pools (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    settlement_id TEXT NOT NULL REFERENCES settlement_entrances(id),
    generated_month INTEGER NOT NULL,
    generated_year INTEGER NOT NULL,
    total_available INTEGER NOT NULL DEFAULT 0,
    search_cost_gp INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_henchman_pools_settlement
    ON henchman_pools(settlement_id, generated_month, generated_year);

CREATE TABLE IF NOT EXISTS henchman_pool_members (
    pool_id TEXT NOT NULL REFERENCES henchman_pools(id),
    character_id TEXT NOT NULL REFERENCES characters(id),
    allotment_week INTEGER NOT NULL DEFAULT 1,
    is_hired INTEGER NOT NULL DEFAULT 0 CHECK(is_hired IN (0, 1)),
    PRIMARY KEY (pool_id, character_id)
);

CREATE TABLE IF NOT EXISTS henchman_state (
    character_id TEXT PRIMARY KEY REFERENCES characters(id),
    morale_score INTEGER NOT NULL DEFAULT 0,
    treasure_share_percent INTEGER NOT NULL DEFAULT 15,
    unpaid_months INTEGER NOT NULL DEFAULT 0,
    is_grudging INTEGER NOT NULL DEFAULT 0 CHECK(is_grudging IN (0, 1)),
    is_fanatic INTEGER NOT NULL DEFAULT 0 CHECK(is_fanatic IN (0, 1)),
    hired_month INTEGER NOT NULL DEFAULT 0,
    hired_year INTEGER NOT NULL DEFAULT 0,
    departure_reason TEXT NOT NULL DEFAULT '',
    departure_settlement_id TEXT REFERENCES settlement_entrances(id),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
