-- Migration 119: Cross-scale hex-map linkage.
--
-- Adds the formal parent/child relationship between hex maps of different
-- scales (campaign_24mi ⊃ regional_6mi ⊃ local_15mi). A regional inset can
-- now declare itself a child of a campaign-scale map, and the two-tier
-- domain hex membership (a single on-camera domain spans both a coarse
-- campaign map and a fine regional inset) is unambiguous.
--
-- Schema changes:
--   * hex_maps gains four nullable parent-linkage columns. NULL parent_map_id
--     marks a top-level map; populated columns mark an inset. The CHECK that
--     the parent must be of a coarser scale is enforced at the repository
--     boundary (CampaignRepository.save_hex_map), not in SQL — SQLite cannot
--     express "scale of the row referenced by parent_map_id is coarser than
--     this row's scale" as a column constraint.
--   * domain_hexes gains a map_id column so a single domain can own hexes on
--     multiple maps at once. The old (domain_id, hex_q, hex_r) UNIQUE
--     constraint is replaced with (domain_id, map_id, hex_q, hex_r).
--
-- No production data yet, so the domain_hexes recreate-and-copy is safe.
-- Legacy rows are backfilled with map_id = the owning domain's
-- location_map_id (the map the domain was created on).
--
-- Migration pattern follows 117_inventory_items_fk_repair: wrap the table
-- recreate in BEGIN/COMMIT with foreign_keys=OFF + legacy_alter_table=ON.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

-- --------------------------------------------------------------------------
-- hex_maps: add parent linkage columns
-- --------------------------------------------------------------------------

ALTER TABLE hex_maps ADD COLUMN parent_map_id TEXT REFERENCES hex_maps(id);
ALTER TABLE hex_maps ADD COLUMN parent_anchor_q INTEGER;
ALTER TABLE hex_maps ADD COLUMN parent_anchor_r INTEGER;
ALTER TABLE hex_maps ADD COLUMN parent_hex_footprint TEXT NOT NULL DEFAULT '[]';

-- --------------------------------------------------------------------------
-- domain_hexes: add map_id column, replace UNIQUE constraint
-- --------------------------------------------------------------------------

ALTER TABLE domain_hexes RENAME TO domain_hexes_old;

-- map_id has NO REFERENCES clause. Legacy callers (pre-migration-119 tests)
-- create domains without a location_map_id and still need to add hexes; the
-- repository's add_domain_hex falls back to '' for these, which is a
-- non-NULL value that satisfies NOT NULL but has no parent row. New
-- cross-scale code is expected to pass real map_ids; the repository's
-- consistency helper ignores rows whose map_id doesn't resolve to a
-- hex_maps row.
CREATE TABLE domain_hexes (
    id                     TEXT    PRIMARY KEY,
    domain_id              TEXT    NOT NULL REFERENCES domains(id),
    map_id                 TEXT    NOT NULL,
    hex_q                  INTEGER NOT NULL,
    hex_r                  INTEGER NOT NULL,
    land_value             INTEGER NOT NULL DEFAULT 5
        CHECK(land_value BETWEEN 3 AND 9),
    surveyed_by            TEXT REFERENCES characters(id),
    is_littoral            INTEGER NOT NULL DEFAULT 0
        CHECK(is_littoral IN (0, 1)),
    land_improvement_level INTEGER NOT NULL DEFAULT 0
        CHECK(land_improvement_level BETWEEN 0 AND 3),
    created_at             TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (domain_id, map_id, hex_q, hex_r)
);

-- Backfill: legacy rows had no map_id; pin them to the owning domain's
-- location_map_id (the map the domain itself was created on). Rows whose
-- domain has a NULL location_map_id get an empty-string map_id sentinel —
-- these rows are detached and the repository write boundary will treat
-- subsequent operations on them as new-style.
INSERT INTO domain_hexes (
    id, domain_id, map_id, hex_q, hex_r, land_value,
    surveyed_by, is_littoral, land_improvement_level, created_at
)
SELECT
    dh.id,
    dh.domain_id,
    COALESCE(d.location_map_id, ''),
    dh.hex_q,
    dh.hex_r,
    dh.land_value,
    dh.surveyed_by,
    dh.is_littoral,
    dh.land_improvement_level,
    dh.created_at
FROM domain_hexes_old dh
LEFT JOIN domains d ON d.id = dh.domain_id;

DROP TABLE domain_hexes_old;

CREATE INDEX IF NOT EXISTS idx_domain_hexes_domain_id
    ON domain_hexes (domain_id);
CREATE INDEX IF NOT EXISTS idx_domain_hexes_map_id
    ON domain_hexes (map_id);

COMMIT;

PRAGMA legacy_alter_table = OFF;
PRAGMA foreign_keys = ON;
