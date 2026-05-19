-- Migration 107: party_visit_state (Phase 10B.2 — Trade block, Wave 1).
--
-- Per generation/gdd-phase-10b-2-trade-block.md §9.3 + §17.4.
--
-- Per-visit state for entry-toll first-fire tracking + stabling computation
-- at departure. One row per (party_id, settlement_id) while the party is at
-- the settlement detail view.
--
-- Lifecycle:
--   INSERT OR IGNORE on VisitStateManager.on_party_entered_settlement
--     (re-entry without departure is a no-op).
--   DELETE on VisitStateManager.on_party_departed_settlement.
--
-- Fields:
--   * entry_calendar_day — for days_at_settlement math at departure
--     (stabling + moorage = max(1, current - entry)).
--   * entry_toll_paid_flag (0/1) — whether the toll has been charged this
--     visit. Mercantile handlers consult this to decide whether to charge
--     toll on the current transaction (toll fires exactly once per visit).
--   * entry_toll_paid_gp — the actual gp charged (0 for domain owners).
--   * active_character_at_entry — who paid the toll + whose domain-owner
--     status applies for toll/stabling/moorage exemption.
--
-- Composite PRIMARY KEY (party_id, settlement_id): no separate id UUID
-- needed; the natural composite key is sufficient and avoids UUID churn.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS party_visit_state (
    party_id                        TEXT    NOT NULL REFERENCES parties(id),
    settlement_id                   TEXT    NOT NULL REFERENCES settlement_entrances(id),
    entry_calendar_day              INTEGER NOT NULL DEFAULT 0,
    entry_toll_paid_flag            INTEGER NOT NULL DEFAULT 0
        CHECK(entry_toll_paid_flag IN (0, 1)),
    entry_toll_paid_gp              INTEGER NOT NULL DEFAULT 0,
    active_character_at_entry       TEXT    REFERENCES characters(id),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (party_id, settlement_id)
);

COMMIT;
