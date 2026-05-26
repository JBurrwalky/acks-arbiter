-- Migration 130: First-class river edges (rivers-as-edges data model).
--
-- Replaces the cell-attached river overlay (hex_overlays rows with
-- overlay_type='river') with a dedicated hex_river_edges table where each
-- row represents one river edge between two adjacent hexes. Edge ownership
-- is canonical: the lexicographically-lower (q, r) hex owns the entry.
-- See gdd-terrain-system.md §3.6 for the data-model spec.
--
-- The old cell-overlay model conflated "river runs along this edge between
-- two hexes" with "river runs through this cell and exits via this edge,"
-- which made it impossible to express which side of a river a road or
-- settlement sits on within a hex. Promoting rivers to first-class edges
-- resolves the ambiguity.
--
-- Conversion of existing hex_overlays river data is LOSSY by design. The
-- old model recorded edges per cell without flow-vertex direction, so the
-- new flow_clockwise field is defaulted (true) and is expected to be
-- re-authored in test JSON. The legacy `flow_exit` value cannot be
-- preserved in the new model — only the SET of river-bearing edges
-- transfers. Test maps will be hand-corrected in step 6 of the handoff.
--
-- Schema changes:
--   * NEW: hex_river_edges with canonical owner enforced at the repository.
--   * The river-half of hex_overlays is migrated row-by-row, then deleted.
--   * hex_overlays.overlay_type CHECK is narrowed from ('river', 'road') to
--     ('road') only by rebuilding the table; column shape preserved so
--     all existing road read sites continue to work unchanged.
--
-- Migration pattern follows 117_inventory_items_fk_repair / 119: wrap the
-- table rebuild in BEGIN/COMMIT with foreign_keys=OFF + legacy_alter_table=ON.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

-- --------------------------------------------------------------------------
-- 1. Create the new hex_river_edges table.
-- --------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hex_river_edges (
    map_id          TEXT    NOT NULL REFERENCES hex_maps(id),
    hex_q           INTEGER NOT NULL,
    hex_r           INTEGER NOT NULL,
    edge            INTEGER NOT NULL CHECK(edge BETWEEN 0 AND 5),
    flow_clockwise  INTEGER NOT NULL DEFAULT 1 CHECK(flow_clockwise IN (0, 1)),
    navigability    TEXT    NOT NULL DEFAULT 'river_craft'
        CHECK(navigability IN ('none', 'small_craft', 'river_craft', 'large_craft')),
    crossing        TEXT    NOT NULL DEFAULT 'none'
        CHECK(crossing IN ('none', 'bridge', 'ford', 'ferry')),
    PRIMARY KEY (map_id, hex_q, hex_r, edge)
);

CREATE INDEX IF NOT EXISTS idx_hex_river_edges_owner
    ON hex_river_edges(map_id, hex_q, hex_r);

-- --------------------------------------------------------------------------
-- 2. Lossy conversion from hex_overlays(overlay_type='river').
--
-- For each existing river overlay row, we have:
--   (map_id, q, r, edges JSON list of 0..5, flow_exit)
-- For each edge `e` in the cell's edge list, derive the canonical owner
-- of the (this-hex, neighbor-across-e) pair using SQLite arithmetic. Edge
-- numbering (0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW) maps to axial offsets:
--   0:(0,-1)  1:(+1,-1)  2:(+1,0)  3:(0,+1)  4:(-1,+1)  5:(-1,0)
-- Owner is whichever endpoint is lex-smaller (q1<q2 OR (q1=q2 AND r1<r2)).
--
-- Doing this in pure SQL is fiddly because we need to expand the JSON array
-- of edges into rows. SQLite has json_each() which we use; if the runtime
-- json1 extension is missing the migration will fail noisily, which is the
-- correct behavior (godot-sqlite ships with json1).
-- --------------------------------------------------------------------------

INSERT OR IGNORE INTO hex_river_edges (map_id, hex_q, hex_r, edge, flow_clockwise, navigability, crossing)
SELECT
    ov.map_id,
    -- Determine canonical owner q/r per edge.
    CASE WHEN _is_owner_a.is_owner = 1 THEN ov.q ELSE ov.q + _off.dq END AS owner_q,
    CASE WHEN _is_owner_a.is_owner = 1 THEN ov.r ELSE ov.r + _off.dr END AS owner_r,
    -- Edge index relative to owner. If A is owner the edge is the original
    -- edge `e`; if B is owner it is the opposite ((e+3) % 6).
    CASE WHEN _is_owner_a.is_owner = 1 THEN _je.value ELSE ((CAST(_je.value AS INTEGER) + 3) % 6) END AS edge,
    1 AS flow_clockwise,            -- lossy: see header note
    'river_craft' AS navigability,  -- default tier per GDD §3.6.4
    'none' AS crossing
FROM hex_overlays ov
CROSS JOIN json_each(ov.edges) _je
-- Compute neighbor axial offset for this edge.
JOIN (
    SELECT 0 AS edge, 0 AS dq, -1 AS dr UNION ALL
    SELECT 1, 1, -1 UNION ALL
    SELECT 2, 1, 0 UNION ALL
    SELECT 3, 0, 1 UNION ALL
    SELECT 4, -1, 1 UNION ALL
    SELECT 5, -1, 0
) _off ON _off.edge = CAST(_je.value AS INTEGER)
-- Compute whether A (the cell that owned the overlay row) is the canonical
-- owner: A < B lexicographically on (q, r).
JOIN (
    SELECT 1 AS is_owner UNION ALL SELECT 0
) _is_owner_a ON _is_owner_a.is_owner = (
    CASE
        WHEN ov.q < (ov.q + _off.dq) THEN 1
        WHEN ov.q = (ov.q + _off.dq) AND ov.r < (ov.r + _off.dr) THEN 1
        ELSE 0
    END
)
WHERE ov.overlay_type = 'river';

-- --------------------------------------------------------------------------
-- 3. Drop river rows from hex_overlays, narrow the overlay_type CHECK to
--    'road' only. We rebuild the table (SQLite cannot ALTER a CHECK).
-- --------------------------------------------------------------------------

DELETE FROM hex_overlays WHERE overlay_type = 'river';

ALTER TABLE hex_overlays RENAME TO hex_overlays_old;

CREATE TABLE hex_overlays (
    map_id       TEXT NOT NULL,
    q            INTEGER NOT NULL,
    r            INTEGER NOT NULL,
    overlay_type TEXT NOT NULL CHECK(overlay_type IN ('road')),
    edges        TEXT NOT NULL DEFAULT '[]',
    flow_exit    INTEGER NOT NULL DEFAULT -1,
    PRIMARY KEY (map_id, q, r, overlay_type),
    FOREIGN KEY (map_id) REFERENCES hex_maps(id)
);

INSERT INTO hex_overlays (map_id, q, r, overlay_type, edges, flow_exit)
SELECT map_id, q, r, overlay_type, edges, flow_exit
FROM hex_overlays_old
WHERE overlay_type = 'road';

DROP TABLE hex_overlays_old;

COMMIT;

PRAGMA legacy_alter_table = OFF;
PRAGMA foreign_keys = ON;
