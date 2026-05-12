-- Migration 097: Settlement economy substrate (Phase 10B prereq, wave Prereq.2a).
--
-- Per generation/gdd-settlement-economy.md §1 / §3 / §4 / §13.
-- Ships sub-steps 1-9 + 12-13 of the consolidated migration plan in §13.0.
-- Sub-steps 10-11 (trade_routes, merchant_pool) land in Prereq.2b / Prereq.4.
-- Sub-steps 14-17 (ships, cargo_holds, shipping_contracts, character_legal_status)
-- land in Prereq.5a-5c / Prereq.6.
--
-- Q-MERC-15 [RESOLVED 2026-05-12, Option A]: urban_families fully relocated
-- from domains to settlement_entrances. Reads (RealmAggregator, etc.) updated
-- to LEFT JOIN settlement_entrances.urban_families aggregate; writes routed
-- through the new CampaignRepository.set_domain_urban_families compat shim.
--
-- The five new settlement_entrances columns (age_years, dominant_race,
-- urban_families, climate_override, economy_inputs_changed_day,
-- customs_duty_rate_pct) plus the hex_cells biome_subtype CHECK extension
-- plus the new settlement_merchandise_demand cache table plus the new
-- campaigns.last_customs_roll_year column are interlocked: the demand
-- generator (§4) reads all of them together. A single migration is the
-- right grain — partial schema would leave the generator unable to run.
--
-- BEGIN/COMMIT wraps the full set so partial failure rolls back. godot-sqlite
-- 4.7 ships SQLite 3.46+ which supports both ALTER TABLE DROP COLUMN (used
-- below for domains.urban_families) and multi-statement BEGIN/COMMIT blocks.

BEGIN TRANSACTION;

-- ===========================================================================
-- Sub-step 1: age_years on settlement_entrances
--   GDD §1.2. Default 500 → 101-1000 years bucket (Jedidiah 2026-05-12).
-- ===========================================================================
ALTER TABLE settlement_entrances ADD COLUMN age_years INTEGER NOT NULL DEFAULT 500;

-- ===========================================================================
-- Sub-step 2: dominant_race on settlement_entrances
--   GDD §1.2. Default 'human' → zero racial adjustment.
-- ===========================================================================
ALTER TABLE settlement_entrances ADD COLUMN dominant_race TEXT NOT NULL DEFAULT 'human';

-- ===========================================================================
-- Sub-step 3: urban_families on settlement_entrances (Q-MERC-15 Option A)
--   GDD §1.2 / §1.3. Default 0 → backfilled in sub-step 5 from domains for
--   any settlement_entrance with a parent_domain_id.
-- ===========================================================================
ALTER TABLE settlement_entrances ADD COLUMN urban_families INTEGER NOT NULL DEFAULT 0;

-- ===========================================================================
-- Sub-step 4: climate_override on settlement_entrances
--   GDD §3.9. Empty default → derive climate from biome+subtype.
-- ===========================================================================
ALTER TABLE settlement_entrances ADD COLUMN climate_override TEXT NOT NULL DEFAULT '';

-- ===========================================================================
-- Sub-step 5: Data-move urban_families from domains → settlement_entrances
--   GDD §1.4. Settlements with parent_domain_id IS NULL stay at 0 (default).
-- ===========================================================================
UPDATE settlement_entrances
SET urban_families = (
    SELECT COALESCE(urban_families, 0)
    FROM domains
    WHERE id = settlement_entrances.parent_domain_id
)
WHERE parent_domain_id IS NOT NULL;

-- ===========================================================================
-- Sub-step 6: Drop urban_families from domains
--   GDD §1.4. SQLite 3.35+ supports ALTER TABLE DROP COLUMN directly; the
--   godot-sqlite 4.7 plugin ships SQLite 3.46+, so this works without a
--   table-rewrite. No indexes / CHECK constraints / FKs reference the
--   column.
-- ===========================================================================
ALTER TABLE domains DROP COLUMN urban_families;

-- ===========================================================================
-- Sub-step 7: Extend hex_cells.biome_subtype CHECK to add clear_steppe + clear_scrub
--   GDD §3.4.1. SQLite has no ALTER COLUMN syntax for modifying a CHECK
--   constraint; table-rewrite is the only path.
-- ===========================================================================
CREATE TABLE hex_cells_new (
    map_id TEXT NOT NULL REFERENCES hex_maps(id),
    q INTEGER NOT NULL,
    r INTEGER NOT NULL,
    elevation TEXT NOT NULL DEFAULT 'flat'
        CHECK(elevation IN ('flat', 'hills', 'mountains')),
    biome TEXT NOT NULL DEFAULT 'clear'
        CHECK(biome IN ('clear', 'woods', 'jungle', 'swamp', 'desert')),
    biome_subtype TEXT NOT NULL DEFAULT ''
        CHECK(biome_subtype IN (
            '',
            'forest_dense', 'forest_taiga',
            'mountains_volcanic', 'mountains_glacial',
            'clear_tundra', 'clear_savanna', 'clear_grassland',
            'clear_steppe', 'clear_scrub',
            'desert_badlands'
        )),
    water TEXT NOT NULL DEFAULT ''
        CHECK(water IN ('', 'ocean', 'lake')),
    civilization TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(civilization IN ('civilized', 'borderlands', 'wilderness')),
    has_city INTEGER NOT NULL DEFAULT 0 CHECK(has_city IN (0, 1)),
    original_biome TEXT NOT NULL DEFAULT '',
    fog_state TEXT NOT NULL DEFAULT 'hidden'
        CHECK(fog_state IN ('hidden', 'explored', 'visible')),
    PRIMARY KEY (map_id, q, r)
);

INSERT INTO hex_cells_new (
    map_id, q, r, elevation, biome, biome_subtype, water,
    civilization, has_city, original_biome, fog_state
)
SELECT
    map_id, q, r, elevation, biome, biome_subtype, water,
    civilization, has_city, original_biome, fog_state
FROM hex_cells;

DROP TABLE hex_cells;
ALTER TABLE hex_cells_new RENAME TO hex_cells;

-- ===========================================================================
-- Sub-step 8: settlement_merchandise_demand cache table
--   GDD §4.7 (PK + base columns) + §6.5 (dice cache columns). The dice
--   columns are added here at table-create time rather than via a follow-up
--   ALTER; the table is new so there's no migration cost to bundling them.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS settlement_merchandise_demand (
    settlement_entrance_id        TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type              TEXT    NOT NULL,
    demand_modifier               INTEGER NOT NULL DEFAULT 0,
    generated_at_calendar_day     INTEGER NOT NULL DEFAULT 0,
    source_kind                   TEXT    NOT NULL DEFAULT 'generated'
        CHECK(source_kind IN ('generated', 'manual')),
    pre_trade_route_shift_value   INTEGER NOT NULL DEFAULT 0,
    -- Prereq.2c (§6.5) — cached 4d4 dice for the monthly drift mechanic.
    dice_4d4_value                INTEGER NOT NULL DEFAULT 0,
    dice_last_rolled_calendar_day INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (settlement_entrance_id, merchandise_type)
);
CREATE INDEX IF NOT EXISTS idx_smd_settlement
    ON settlement_merchandise_demand(settlement_entrance_id);

-- ===========================================================================
-- Sub-step 9: economy_inputs_changed_day on settlement_entrances
--   GDD §4.9. Bumped whenever a regeneration trigger fires; consumed as a
--   seed-derivation salt so the same inputs reproduce demand modifiers.
-- ===========================================================================
ALTER TABLE settlement_entrances
    ADD COLUMN economy_inputs_changed_day INTEGER NOT NULL DEFAULT 0;

-- ===========================================================================
-- Sub-step 12: customs_duty_rate_pct on settlement_entrances
--   GDD §8.4. Default 0 = "not yet rolled"; Prereq.3 ships the annual roll
--   service that backfills values per the (settlement_id, year) seed.
-- ===========================================================================
ALTER TABLE settlement_entrances
    ADD COLUMN customs_duty_rate_pct INTEGER NOT NULL DEFAULT 0;

-- ===========================================================================
-- Sub-step 13: last_customs_roll_year on campaigns
--   GDD §8.4. Default 0 → "no annual roll has happened yet." First year tick
--   in Prereq.3 advances this and triggers a settlement-wide re-roll.
-- ===========================================================================
ALTER TABLE campaigns
    ADD COLUMN last_customs_roll_year INTEGER NOT NULL DEFAULT 0;

-- ===========================================================================
-- Indexes on the new settlement_entrances columns (GDD §1.6)
-- ===========================================================================
CREATE INDEX IF NOT EXISTS idx_settlement_entrances_parent_domain
    ON settlement_entrances(parent_domain_id);
CREATE INDEX IF NOT EXISTS idx_settlement_entrances_dominant_race
    ON settlement_entrances(dominant_race);

COMMIT;
