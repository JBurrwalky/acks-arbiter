-- Migration 086: siege_artillery — Phase 9B artillery and siege equipment
-- held by each siege (per side).
--
-- One row per (siege, side, equipment_type). count >= 1 represents how many
-- pieces of that type the side has at the siege; is_destroyed flags pieces
-- destroyed in artillery duels (RAW §artillery_duels L222-248) without
-- removing the row (preserves the audit trail).
--
-- equipment_type keys come from data/siege/artillery_table.json (RAW L251-324
-- bombardment table + RAW L540-673 BR table merged into a single catalog file).
-- Examples: medium_ballista, heavy_ballista, light_catapult, medium_catapult,
-- heavy_catapult, light_trebuchet, medium_trebuchet, heavy_trebuchet,
-- battering_ram_20, hoist, movable_gallery, movable_mantlet, ram_catcher,
-- screw_20, siege_hook, siege_tower_standard, siege_tower_large, siege_tower_huge,
-- cauldron, light_repeating_ballista.
--
-- This table feeds three subsystems:
--   1. siege_reduction_resolver.tick_bombardment (daily damage)
--   2. siege_reduction_resolver.run_artillery_duel (1d6/2d6 rolls)
--   3. siege_assault_resolver / field_battle_resolver (assault BR contribution
--      via siege_equipment_resolver.compute_assault_units_from_equipment)

CREATE TABLE IF NOT EXISTS siege_artillery (
    id              TEXT    PRIMARY KEY,
    siege_id        TEXT    NOT NULL REFERENCES sieges(id),
    side            TEXT    NOT NULL
        CHECK(side IN ('besieger', 'defender')),
    equipment_type  TEXT    NOT NULL,
    count           INTEGER NOT NULL DEFAULT 1,
    is_destroyed    INTEGER NOT NULL DEFAULT 0
        CHECK(is_destroyed IN (0, 1)),
    notes           TEXT    NOT NULL DEFAULT '',
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_siege_artillery_siege
    ON siege_artillery(siege_id, side);
