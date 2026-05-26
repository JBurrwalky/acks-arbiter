-- Migration 127: introduce orthogonal `domain_style` column on `domains` and
-- drop the deprecated `is_chaotic_domain` flag per gdd-domain-style-and-alignment.md
-- §6 + Q-DSA-3 resolution.
--
-- Per docs/phase-11-plan.md §11D.1 (revised 2026-05-21):
--   - Add `domain_style TEXT NOT NULL DEFAULT 'civilized'
--           CHECK(domain_style IN ('civilized', 'clanhold'))`.
--   - Backfill `domain_style` from `is_chaotic_domain` + `establishment_method`:
--       CASE WHEN is_chaotic_domain = 1
--                 OR establishment_method IN ('clanhold_annex', 'recruit_chieftain')
--            THEN 'clanhold' ELSE 'civilized' END.
--   - DROP `is_chaotic_domain` entirely. Per the GDD: no production data + no
--     back-compat requirement, so the cleaner schema wins. Any GDScript still
--     reading `is_chaotic_domain` will fail at SQL execution (column-not-found)
--     and surface the missed callsite at test time.
--   - The orthogonal `alignment` column already exists from Phase 0 (line 583
--     of schema.sql; CHECK lawful/neutral/chaotic) — this migration leaves it
--     alone. The two-axis model (style × alignment) is now complete.
--
-- SQLite cannot DROP a column with a CHECK constraint nor ADD a column with a
-- CHECK that references other columns, so this migration rebuilds the `domains`
-- table. Follows the legacy_alter_table pattern from migration 117 / 119 / 125.
--
-- All other CHECK constraints and column definitions are preserved verbatim
-- from migration 125's rebuild (the post-salted_to_ruin shape).

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

ALTER TABLE domains RENAME TO domains_old;

CREATE TABLE domains (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    name TEXT NOT NULL,
    owner_character_id TEXT REFERENCES characters(id),
    location_map_id TEXT REFERENCES hex_maps(id),
    location_hex_q INTEGER,
    location_hex_r INTEGER,
    territory_type TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(territory_type IN ('civilized', 'borderlands', 'wilderness')),
    peasant_families INTEGER NOT NULL DEFAULT 0,
    morale INTEGER NOT NULL DEFAULT 0,
    garrison_troops INTEGER NOT NULL DEFAULT 0,
    revenue_cp INTEGER NOT NULL DEFAULT 0,
    expenses_cp INTEGER NOT NULL DEFAULT 0,
    net_income_cp INTEGER NOT NULL DEFAULT 0,
    domain_xp_this_month INTEGER NOT NULL DEFAULT 0,
    ruler_npc_id TEXT REFERENCES characters(id),
    religion TEXT NOT NULL DEFAULT '',
    alignment TEXT NOT NULL DEFAULT 'neutral'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    tax_rate_cp_per_family INTEGER NOT NULL DEFAULT 200,
    liturgy_rate_cp_per_family INTEGER NOT NULL DEFAULT 100,
    tithe_rate_cp_per_family INTEGER NOT NULL DEFAULT 100,
    tribute_out_owed INTEGER NOT NULL DEFAULT 0,
    -- Migration 127 (Phase 11D.1): `is_chaotic_domain` DROPPED; replaced by
    -- the orthogonal `domain_style` column below + existing `alignment`.
    domain_style TEXT NOT NULL DEFAULT 'civilized'
        CHECK(domain_style IN ('civilized', 'clanhold')),
    is_active_adventuring_this_month INTEGER NOT NULL DEFAULT 0
        CHECK(is_active_adventuring_this_month IN (0, 1)),
    classification_progress_families INTEGER NOT NULL DEFAULT 0,
    liege_domain_id TEXT REFERENCES domains(id),
    realm_title TEXT NOT NULL DEFAULT 'Baron',
    is_repressed_this_month INTEGER NOT NULL DEFAULT 0
        CHECK(is_repressed_this_month IN (0, 1)),
    repression_cp_per_family_this_month INTEGER NOT NULL DEFAULT 0,
    treasury_cp INTEGER NOT NULL DEFAULT 0,
    auto_pay_policies TEXT NOT NULL DEFAULT '{}',
    deferred_maintenance_cp INTEGER NOT NULL DEFAULT 0,
    establishment_method TEXT NOT NULL DEFAULT '',
    established_calendar_day INTEGER NOT NULL DEFAULT 0,
    administer_domain_completed_this_month INTEGER NOT NULL DEFAULT 0
        CHECK(administer_domain_completed_this_month IN (0, 1)),
    pending_investment_cp INTEGER NOT NULL DEFAULT 0,
    lifecycle_state TEXT NOT NULL DEFAULT 'active'
        CHECK(lifecycle_state IN ('active', 'ruined_stronghold', 'succession_pending', 'abandoned', 'salted_to_ruin')),
    lifecycle_state_changed_day INTEGER NOT NULL DEFAULT 0,
    ruined_stronghold_grace_until_day INTEGER NOT NULL DEFAULT 0,
    succession_pending_until_day INTEGER NOT NULL DEFAULT 0,
    designated_heir_character_id TEXT NOT NULL DEFAULT '',
    designated_heir_kind TEXT NOT NULL DEFAULT ''
        CHECK(designated_heir_kind IN ('', 'pc', 'henchman', 'non_henchman')),
    realm_id TEXT REFERENCES realms(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO domains (
    id, campaign_id, name, owner_character_id, location_map_id,
    location_hex_q, location_hex_r, territory_type, peasant_families,
    morale, garrison_troops, revenue_cp, expenses_cp, net_income_cp,
    domain_xp_this_month, ruler_npc_id, religion, alignment,
    tax_rate_cp_per_family, liturgy_rate_cp_per_family,
    tithe_rate_cp_per_family, tribute_out_owed, domain_style,
    is_active_adventuring_this_month, classification_progress_families,
    liege_domain_id, realm_title, is_repressed_this_month,
    repression_cp_per_family_this_month, treasury_cp, auto_pay_policies,
    deferred_maintenance_cp, establishment_method, established_calendar_day,
    administer_domain_completed_this_month, pending_investment_cp,
    lifecycle_state, lifecycle_state_changed_day,
    ruined_stronghold_grace_until_day, succession_pending_until_day,
    designated_heir_character_id, designated_heir_kind, realm_id,
    created_at, updated_at
)
SELECT
    id, campaign_id, name, owner_character_id, location_map_id,
    location_hex_q, location_hex_r, territory_type, peasant_families,
    morale, garrison_troops, revenue_cp, expenses_cp, net_income_cp,
    domain_xp_this_month, ruler_npc_id, religion, alignment,
    tax_rate_cp_per_family, liturgy_rate_cp_per_family,
    tithe_rate_cp_per_family, tribute_out_owed,
    -- Backfill domain_style from the deprecated is_chaotic_domain flag plus
    -- the establishment_method enum. is_chaotic_domain=1 rows are clanhold
    -- (the Phase 0 flag was set for both clanhold-style AND chaotic-method
    -- establishments, conflating the two axes); clanhold_annex /
    -- recruit_chieftain methods also force clanhold style regardless.
    CASE
        WHEN is_chaotic_domain = 1
             OR establishment_method IN ('clanhold_annex', 'recruit_chieftain')
        THEN 'clanhold'
        ELSE 'civilized'
    END,
    is_active_adventuring_this_month, classification_progress_families,
    liege_domain_id, realm_title, is_repressed_this_month,
    repression_cp_per_family_this_month, treasury_cp, auto_pay_policies,
    deferred_maintenance_cp, establishment_method, established_calendar_day,
    administer_domain_completed_this_month, pending_investment_cp,
    lifecycle_state, lifecycle_state_changed_day,
    ruined_stronghold_grace_until_day, succession_pending_until_day,
    designated_heir_character_id, designated_heir_kind, realm_id,
    created_at, updated_at
FROM domains_old;

DROP TABLE domains_old;

-- Recreate indexes from the migration 125 rebuild + add the new style index.
CREATE INDEX IF NOT EXISTS idx_domains_realm
    ON domains(realm_id);
CREATE INDEX IF NOT EXISTS idx_domains_lifecycle_state
    ON domains(campaign_id, lifecycle_state);
CREATE INDEX IF NOT EXISTS idx_domains_style
    ON domains(campaign_id, domain_style);

COMMIT;

PRAGMA foreign_keys = ON;
