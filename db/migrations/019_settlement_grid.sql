-- Migration 019: Settlement entrances + party settlement position.
--
-- Parallels dungeon_entrances + party dungeon position from migration 017.
-- Settlement layout (blocks, street graph, POIs) stored as JSON in settlement_data.
-- Party position is a street graph node ID, not grid coordinates.

CREATE TABLE IF NOT EXISTS settlement_entrances (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    map_id TEXT NOT NULL REFERENCES hex_maps(id),
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    name TEXT NOT NULL DEFAULT 'Unknown Settlement',
    market_class INTEGER NOT NULL DEFAULT 6,
    settlement_data TEXT NOT NULL DEFAULT ''
);

-- Party position when inside a settlement.
-- settlement_id '' means party is not in a settlement.
-- settlement_node_id is a street graph node ID (-1 = not positioned).
ALTER TABLE parties ADD COLUMN settlement_id TEXT NOT NULL DEFAULT '';
ALTER TABLE parties ADD COLUMN settlement_node_id INTEGER NOT NULL DEFAULT -1;
