-- Migration 063: Domain settings extensions (Domain Phase 2)
--
-- Adds Phase 2 player-facing columns to the existing `domains` table:
--   * auto_pay_policies — JSON dict of monthly-expense auto-pay toggles per
--     gdd-domain-tab.md §10.2 layout 4 ("Auto-pay policies"). Keys are expense
--     subcategories (garrison, maintenance, tithe, tribute, hireling_wages,
--     congregants); values are 0/1. Empty default '{}' means manual.
--   * deferred_maintenance_gp — accumulated unpaid maintenance per
--     `acore_axioms_strongholds_and_domains.xml` §maintenance L218-220
--     ("each gp of unpaid maintenance reduces stronghold value by 1gp").
--     Phase 2 surfaces this in the Treasury sub-tab; Phase 4 wires the
--     stronghold-value reduction.
--   * establishment_method — how the ruler acquired the domain. Per
--     `acore_axioms_strongholds_and_domains.xml` §domain_acquisition and
--     `ax_domains_of_chaos.xml` §establishment + §chaotic_realms.
--     Values: 'grant' / 'purchase' / 'conquest' / 'clear' / 'clanhold_annex' /
--     'recruit_chieftain' / ''. Empty default for pre-existing rows.
--   * established_calendar_day — calendar day on which the domain became
--     player-owned. Used by the Departure Log lifecycle handler (Phase 10)
--     and the Overview "establishment date" line (Phase 2 §6.1).
--
-- One ALTER TABLE per column (SQLite restriction).

ALTER TABLE domains
    ADD COLUMN auto_pay_policies TEXT NOT NULL DEFAULT '{}';

ALTER TABLE domains
    ADD COLUMN deferred_maintenance_gp INTEGER NOT NULL DEFAULT 0;

ALTER TABLE domains
    ADD COLUMN establishment_method TEXT NOT NULL DEFAULT '';

ALTER TABLE domains
    ADD COLUMN established_calendar_day INTEGER NOT NULL DEFAULT 0;
