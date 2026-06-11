-- Migration 152: Lair lazy placement (gdd-lair-discovery.md redesign 2026-05-27).
--
-- The v1 lair model (eager placement + lazy discovery via a `discovered` flag)
-- is replaced by strict-RAW lazy placement: lairs do not exist until a
-- wandering-encounter substitution or a successful dedicated search places
-- them via the Lair Generator, capped per hex by the RAW lairs_per_hex budget
-- (le_wilderness_lair_rules.xml §securing_land L34-87).
--
-- Two changes:
--   1. New `hex_lair_state` table — per-hex lazy lair bookkeeping (budget,
--      placed count, unrevealed-types FIFO queue, surveyed total). The GDD's
--      §8 map nominally puts these columns on the hex table, but
--      CampaignRepository.save_hex_map() INSERT-OR-REPLACEs every hex_cells
--      row on each fog save (every travel leg), which would clobber
--      handler-written lair state. A keyed side-table (same key shape as
--      survey_progress, minus party_id) is the safe equivalent.
--   2. Rebuild `lairs` — placement IS discovery in the new model, so the
--      `discovered` flag (and its partial index) is dropped per the handoff
--      spec; `discovered_via` becomes `placed_via` with the new vocabulary;
--      `cleared_at_round` (NULL = uncleared) drives the §7 Build Stronghold
--      gate; treasure/seed columns carry the Lair Generator stub's record.
--      Existing rows are preserved (placed_via='legacy') — discovered=0 rows
--      become visible placed lairs rather than being deleted (non-destructive
--      rule; production saves predating this migration have no lairs rows,
--      they were only ever created by test fixtures).
--
-- No other table holds a FOREIGN KEY into `lairs`, so the rebuild needs no
-- legacy_alter_table guard (coding_conventions §6.5 applies only when child
-- FKs reference the rebuilt table).

-- 1. Per-hex lazy lair state -------------------------------------------------

CREATE TABLE IF NOT EXISTS hex_lair_state (
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    map_id                      TEXT    NOT NULL REFERENCES hex_maps(id),
    hex_q                       INTEGER NOT NULL,
    hex_r                       INTEGER NOT NULL,
    -- NULL = budget not yet rolled (lazy; rolled on first need per §3.1).
    lair_budget                 INTEGER,
    lair_budget_rolled_at_round INTEGER,
    lairs_placed_count          INTEGER NOT NULL DEFAULT 0,
    -- JSON array of creature_ids (FIFO queue), hidden from the player.
    unrevealed_lair_types       TEXT    NOT NULL DEFAULT '[]',
    -- Player-displayed total. Equals lair_budget after a true Survey reading,
    -- or the false value after an unmodified-1 reading. NULL = never surveyed.
    surveyed_total              INTEGER,
    PRIMARY KEY (campaign_id, map_id, hex_q, hex_r)
);

-- 2. Rebuild lairs ------------------------------------------------------------

DROP INDEX IF EXISTS idx_lairs_undiscovered;
DROP INDEX IF EXISTS idx_lairs_hex;

CREATE TABLE lairs_new (
    lair_id            TEXT    PRIMARY KEY,
    campaign_id        TEXT    NOT NULL REFERENCES campaigns(id),
    map_id             TEXT    NOT NULL REFERENCES hex_maps(id),
    hex_q              INTEGER NOT NULL,
    hex_r              INTEGER NOT NULL,
    monster_group      TEXT    NOT NULL DEFAULT '',
    monster_count      INTEGER NOT NULL DEFAULT 0,
    placed_via         TEXT    NOT NULL DEFAULT ''
        CHECK(placed_via IN ('', 'wandering_substitution', 'search', 'legacy')),
    created_at_round   INTEGER NOT NULL DEFAULT 0,
    -- NULL = uncleared. Set by mark_lair_cleared; gates Build Stronghold (§7).
    cleared_at_round   INTEGER,
    -- Lair Generator stub fields (gdd-lair-discovery.md §3.3). The treasure
    -- hoard is NOT rolled by the stub — treasure_type carries the catalog's
    -- letter spec for the future Lair Generator; hoard JSON stays '{}'.
    treasure_type      TEXT    NOT NULL DEFAULT '',
    treasure_hoard_json TEXT   NOT NULL DEFAULT '{}',
    lair_layout_seed   INTEGER NOT NULL DEFAULT 0
);

INSERT INTO lairs_new
    (lair_id, campaign_id, map_id, hex_q, hex_r,
     monster_group, monster_count, placed_via, created_at_round,
     cleared_at_round, treasure_type, treasure_hoard_json, lair_layout_seed)
SELECT
    lair_id, campaign_id, map_id, hex_q, hex_r,
    monster_group, monster_count, 'legacy', discovered_at_round,
    NULL, '', '{}', 0
FROM lairs;

DROP TABLE lairs;

ALTER TABLE lairs_new RENAME TO lairs;

CREATE INDEX IF NOT EXISTS idx_lairs_hex
    ON lairs(campaign_id, map_id, hex_q, hex_r);
