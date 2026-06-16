-- Migration 163: campaign_origin marker — distinguishes a GENERATED campaign
-- (materialized from the locked setting_* tables by SettingMaterializer) from a
-- FIXTURE campaign (hand-authored test content via TestContentSeeder). Both paths
-- write the same runtime tables and must NEVER both run for one campaign; this
-- column is the guard. Existing campaigns default to 'fixture' (safe).
-- See gdd-setting-runtime-materialization.md §11 (Decision M).
ALTER TABLE campaigns ADD COLUMN campaign_origin TEXT NOT NULL DEFAULT 'fixture'
    CHECK(campaign_origin IN ('fixture', 'generated'));
