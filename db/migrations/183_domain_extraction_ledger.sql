-- Migration 183: domain_extraction_ledger — per-domain requisition/loot accounting
-- for army-warfare Phase B (gdd-army-warfare.md §4.3; daw_campaigning_armies.xml
-- §requisition_and_looting L324-347). One row per (campaign, domain) that has ever
-- been extracted. Enforces the CROSS-ARMY, per-domain invariants that the per-army
-- army_supply_state.requisition_cooldowns_json (migration 073, inert) cannot:
--   * Requisition once per domain per 6 months (RAW L327-330) — last_requisition_calendar_day.
--   * Combined 40 (requisition) + 20 (loot) = 60 gp/family extraction ceiling across ALL
--     armies (RAW L338) — cumulative_extracted_gp_per_family, reset each 6-month period
--     (period_anchor_calendar_day is the population-recovery proxy: after 6 months the
--     accounting window reopens and the cumulative zeroes).
--   * 1 family lost per 20 gp looted (RAW L334-336) — families_lost (telemetry; the
--     authoritative peasant count is domains.peasant_families, decremented on loot).
-- Keyed (campaign_id, domain_id); the domain is globally unique but the composite PK
-- matches the "per (campaign, domain)" scope and keeps the campaign-scope predicate a
-- plain equality (for _SCOPE_DIRECT_CAMPAIGN save/load slot-copy + campaign delete).
CREATE TABLE IF NOT EXISTS domain_extraction_ledger (
    campaign_id                        TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                          TEXT    NOT NULL REFERENCES domains(id),
    period_anchor_calendar_day         INTEGER NOT NULL DEFAULT 0,
    last_requisition_calendar_day      INTEGER NOT NULL DEFAULT -1,
    cumulative_extracted_gp_per_family REAL    NOT NULL DEFAULT 0.0,
    families_lost                      INTEGER NOT NULL DEFAULT 0,
    created_at                         TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                         TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (campaign_id, domain_id)
);

CREATE INDEX IF NOT EXISTS idx_domain_extraction_ledger_campaign
    ON domain_extraction_ledger(campaign_id);
