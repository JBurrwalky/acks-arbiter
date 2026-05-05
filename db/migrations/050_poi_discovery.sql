-- Migration 050: POI / Lair discovery (Wilderness closure Phase 4).
-- Per le_wilderness_lair_rules.xml — lairs are dynamic POIs placed during
-- world-gen (or on first lair-encounter substitution), revealed via the
-- abstract search procedure. Wilderness POIs (per gdd-poi-generation.md)
-- are placed eagerly during setting generation and revealed via search.
--
-- Both tables share a "discovered" gating model: rows exist from world-gen
-- onward; the discovered flag flips on a successful resolver hit. The hex
-- map renderer reads `discovered = 1` rows and shows them as named markers.
--
-- map_id is denormalized onto the row so the hex-renderer query stays a
-- single index lookup (no join through campaigns / hex_maps). campaign_id
-- is also denormalized for the same reason and to scope reset / wipe ops.

CREATE TABLE IF NOT EXISTS lairs (
    lair_id              TEXT    PRIMARY KEY,
    campaign_id          TEXT    NOT NULL REFERENCES campaigns(id),
    map_id               TEXT    NOT NULL REFERENCES hex_maps(id),
    hex_q                INTEGER NOT NULL,
    hex_r                INTEGER NOT NULL,
    monster_group        TEXT    NOT NULL DEFAULT '',
    monster_count        INTEGER NOT NULL DEFAULT 0,
    discovered           INTEGER NOT NULL DEFAULT 0 CHECK(discovered IN (0, 1)),
    discovered_at_round  INTEGER NOT NULL DEFAULT 0,
    discovered_via       TEXT    NOT NULL DEFAULT ''
        CHECK(discovered_via IN ('', 'search', 'passive', 'encounter', 'aerial'))
);

CREATE INDEX IF NOT EXISTS idx_lairs_hex
    ON lairs(campaign_id, map_id, hex_q, hex_r);

CREATE INDEX IF NOT EXISTS idx_lairs_undiscovered
    ON lairs(campaign_id, map_id, hex_q, hex_r)
    WHERE discovered = 0;


CREATE TABLE IF NOT EXISTS pois (
    poi_id               TEXT    PRIMARY KEY,
    campaign_id          TEXT    NOT NULL REFERENCES campaigns(id),
    map_id               TEXT    NOT NULL REFERENCES hex_maps(id),
    hex_q                INTEGER NOT NULL,
    hex_r                INTEGER NOT NULL,
    poi_type             TEXT    NOT NULL DEFAULT 'unknown',
    name                 TEXT    NOT NULL DEFAULT '',
    discovered           INTEGER NOT NULL DEFAULT 0 CHECK(discovered IN (0, 1)),
    discovered_at_round  INTEGER NOT NULL DEFAULT 0,
    faction_id           TEXT    NOT NULL DEFAULT '',
    seed                 INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_pois_hex
    ON pois(campaign_id, map_id, hex_q, hex_r);
