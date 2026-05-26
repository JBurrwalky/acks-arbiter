-- Migration 122: domain lifecycle state — Phase 11B authority on whether a
-- domain is mechanically alive per docs/phase-11-plan.md §11B and
-- gdd-domain-tab.md §13.3.
--
-- `lifecycle_state` is the canonical authority. The monthly tick skips
-- domains whose state is 'abandoned' or 'lost_to_foreign' (their audit
-- history is preserved in domain_departure_log per migration 121, but no
-- further resolution runs). 'ruined_stronghold' and 'succession_pending'
-- (Phase 11C) continue to tick with reduced functionality.
--
-- States:
--   active                — normal operation; monthly tick resolves
--   ruined_stronghold     — shp = 0; grace period until rebuild or auto-abandon
--   succession_pending    — Phase 11C: ruler died, 1-month grace
--   abandoned             — terminal; player voluntarily abandoned or grace lapsed
--   lost_to_foreign       — terminal; conquered by an extra-campaign realm
--
-- ruined_stronghold_grace_until_day is set to calendar_day + 30 when
-- mark_stronghold_collapsed fires; restore_from_ruin clears it. Phase 11C
-- adds a separate succession_pending_until_day in migration 123.
--
-- Backfill: every existing row gets lifecycle_state='active' (the default)
-- and lifecycle_state_changed_day = max(established_calendar_day, 0). No
-- production data hits this — pre-migration domains are dev fixtures.

ALTER TABLE domains ADD COLUMN lifecycle_state TEXT NOT NULL DEFAULT 'active'
    CHECK(lifecycle_state IN ('active', 'ruined_stronghold', 'succession_pending', 'abandoned', 'lost_to_foreign'));

ALTER TABLE domains ADD COLUMN lifecycle_state_changed_day INTEGER NOT NULL DEFAULT 0;

ALTER TABLE domains ADD COLUMN ruined_stronghold_grace_until_day INTEGER NOT NULL DEFAULT 0;

-- Backfill the changed-day for existing rows from established_calendar_day.
-- Rows whose established_calendar_day is 0 (legacy fixtures) get 0 — harmless
-- since lifecycle_state is already 'active' and tick_lifecycle_state ignores
-- grace columns when state == 'active'.
UPDATE domains SET lifecycle_state_changed_day = established_calendar_day
    WHERE lifecycle_state_changed_day = 0 AND established_calendar_day > 0;

CREATE INDEX IF NOT EXISTS idx_domains_lifecycle_state
    ON domains(campaign_id, lifecycle_state);
