-- Migration 081: market_class_modifiers — Phase 9A market-class temporary
-- shifts driven by Vagaries-of-Recruitment commerce_disrupted/commerce_improves
-- (replacing the Phase 7 signal-only stub) and Vagaries-of-War war_profiteers
-- (RAW L210: artillery / armor / mounts / supplies / weapons cost +10%
-- cumulative for 1d4 seasons).
--
-- Each row records a TIME-LIMITED additive modifier applied to a settlement's
-- effective market_class. The settlement's effective class is derived as:
--
--   effective_class = base_class + SUM(active modifier deltas)
--
-- where "active" means status='active' AND expires_calendar_day > now.
-- Negative deltas (commerce_disrupted) lower effective class; positive
-- (commerce_improves) raise it. Cumulative on each repeat per RAW.
--
-- The "war_profiteers" effect modulates supply prices (not market class) so
-- it stores `price_multiplier_pct` (e.g. 110 = +10%) and `affected_categories`
-- (CSV of artillery/armor/mounts/supplies/weapons).

CREATE TABLE IF NOT EXISTS market_class_modifiers (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_entrance_id      TEXT    REFERENCES settlement_entrances(id),
    -- Source: which subsystem applied this modifier
    source_kind                 TEXT    NOT NULL DEFAULT 'unknown'
        CHECK(source_kind IN (
            'unknown',
            'vagary_recruitment_commerce_disrupted',
            'vagary_recruitment_commerce_improves',
            'vagary_war_war_profiteers',
            'manual'
        )),
    -- Market-class delta (negative = market shrunk; positive = market grew).
    -- For war_profiteers, this is 0 and the price_multiplier_pct fields apply.
    delta                       INTEGER NOT NULL DEFAULT 0,
    -- War-profiteers: percent multiplier on the listed categories (110 = +10%).
    price_multiplier_pct        INTEGER NOT NULL DEFAULT 100,
    affected_categories         TEXT    NOT NULL DEFAULT '',  -- CSV
    issued_calendar_day         INTEGER NOT NULL DEFAULT 0,
    expires_calendar_day        INTEGER NOT NULL DEFAULT 0,
    status                      TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'expired', 'revoked')),
    payload_json                TEXT    NOT NULL DEFAULT '{}',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_market_class_modifiers_settlement
    ON market_class_modifiers(settlement_entrance_id, status);

CREATE INDEX IF NOT EXISTS idx_market_class_modifiers_campaign
    ON market_class_modifiers(campaign_id, status);

CREATE INDEX IF NOT EXISTS idx_market_class_modifiers_expiry
    ON market_class_modifiers(expires_calendar_day, status)
    WHERE status = 'active';
