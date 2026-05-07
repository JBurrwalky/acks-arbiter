-- Migration 058: Ledger entries (Domain Phase 0)
--
-- Append-only record of every revenue / expense / tribute / investment line
-- that touches a domain treasury. The Phase 0 monthly-tick handler writes
-- one row per nonzero subcategory; the future Phase 2 Treasury sub-tab and
-- Phase 10 Departure Log read from this table to render the running ledger.
--
-- Categories (RAW-grouped):
--   * revenue     — service / tax / land / trade / tithes_in
--   * expense     — garrison / liturgy / maintenance / tithe / repression
--   * tribute_in  — vassal-paid tribute (per §tribute_inefficiency L398-409)
--   * tribute_out — tribute owed to a liege
--   * investment  — agricultural / land_improvement / commissioning / charity
--   * other       — escape hatch for one-off events (raid losses, gifts)
--
-- `subcategory` is a free-text key (e.g., "service", "tax", "garrison",
-- "liturgy", "land_improvement_25kgp"); enforce category-vs-subcategory
-- consistency in code, not at the schema level (the matrix is too large for
-- a CHECK constraint and grows with later phases).
--
-- Indexes:
--   * (domain_id) for "show this domain's history"
--   * (calendar_day) for "what happened on day N across all domains"

CREATE TABLE IF NOT EXISTS ledger_entries (
    id              TEXT    PRIMARY KEY,
    domain_id       TEXT    NOT NULL REFERENCES domains(id),
    calendar_day    INTEGER NOT NULL,
    category        TEXT    NOT NULL
        CHECK(category IN ('revenue', 'expense', 'tribute_in', 'tribute_out', 'investment', 'other')),
    subcategory     TEXT    NOT NULL,
    gp_amount       INTEGER NOT NULL,
    description     TEXT    NOT NULL DEFAULT '',
    source_event_id TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ledger_entries_domain_id
    ON ledger_entries (domain_id);

CREATE INDEX IF NOT EXISTS idx_ledger_entries_calendar_day
    ON ledger_entries (calendar_day);
