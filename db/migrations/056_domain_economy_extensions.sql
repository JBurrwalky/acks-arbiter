-- Migration 056: Domain economy extensions (Domain Phase 0)
--
-- Extends the existing `domains` table (created in migration 001) with the
-- columns required by the Phase 0 RAW-correct monthly-tick resolvers and
-- by the realm / vassalage / repression / chaotic-domain rules surfaced in
-- later phases.
--
-- One ALTER TABLE per column (SQLite restriction: only one ADD COLUMN per
-- statement).
--
-- Source citations (file: acore_axioms_strongholds_and_domains.xml unless noted):
--   * religion / alignment / liturgy / tithe — §alignment_and_religion L466-471
--     and §monthly_event_modifiers L488-499.
--   * tax_rate — §domain_revenue (configurable; default 2gp/fam).
--   * tribute_out_owed — §tribute_inefficiency L398-409 (the per-month sum a
--     vassal domain must remit to its liege).
--   * is_chaotic_domain — `ax_domains_of_chaos.xml` §exceptions_from_clanholds.
--   * is_active_adventuring_this_month — §active_adventuring_growth L138-149;
--     written by Phase 2's `active_adventuring_detector.gd`. Phase 0 only
--     declares the column.
--   * classification_progress_families — §classification_advancement L165-175.
--   * liege_domain_id — §realms_and_vassals.
--   * realm_title — §titles_of_nobility L273-285 (default Baron, the lowest
--     entry-level title).
--   * is_repressed_this_month / repression_gp_per_family_this_month — §repression
--     L510-516; militia ineligibility is enforced by the Phase 3 repression
--     activity handler (not at the schema level).
--   * treasury_gp — Phase 2 surfaces it in the Treasury sub-tab; Phase 0 needs
--     it now so ledger_entries (migration 058) can balance against a real
--     domain treasury balance during monthly ticks.

ALTER TABLE domains
    ADD COLUMN religion TEXT NOT NULL DEFAULT '';

ALTER TABLE domains
    ADD COLUMN alignment TEXT NOT NULL DEFAULT 'neutral'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic'));

ALTER TABLE domains
    ADD COLUMN tax_rate_gp_per_family INTEGER NOT NULL DEFAULT 2;

ALTER TABLE domains
    ADD COLUMN liturgy_rate_gp_per_family INTEGER NOT NULL DEFAULT 1;

ALTER TABLE domains
    ADD COLUMN tithe_rate_gp_per_family INTEGER NOT NULL DEFAULT 1;

ALTER TABLE domains
    ADD COLUMN tribute_out_owed INTEGER NOT NULL DEFAULT 0;

ALTER TABLE domains
    ADD COLUMN is_chaotic_domain INTEGER NOT NULL DEFAULT 0
        CHECK(is_chaotic_domain IN (0, 1));

ALTER TABLE domains
    ADD COLUMN is_active_adventuring_this_month INTEGER NOT NULL DEFAULT 0
        CHECK(is_active_adventuring_this_month IN (0, 1));

ALTER TABLE domains
    ADD COLUMN classification_progress_families INTEGER NOT NULL DEFAULT 0;

ALTER TABLE domains
    ADD COLUMN liege_domain_id TEXT REFERENCES domains(id);

ALTER TABLE domains
    ADD COLUMN realm_title TEXT NOT NULL DEFAULT 'Baron';

ALTER TABLE domains
    ADD COLUMN is_repressed_this_month INTEGER NOT NULL DEFAULT 0
        CHECK(is_repressed_this_month IN (0, 1));

ALTER TABLE domains
    ADD COLUMN repression_gp_per_family_this_month INTEGER NOT NULL DEFAULT 0;

ALTER TABLE domains
    ADD COLUMN treasury_gp INTEGER NOT NULL DEFAULT 0;
