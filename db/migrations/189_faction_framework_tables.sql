-- Migration 189: Faction Framework FF-1.0 — the new §4 tables
-- (gdd-faction-framework.md §4.2, §4.3, §4.5, §4.6, §4.8, §4.9; ENTIRE §4 data
-- model approved 2026-07-05/07-06). Migration 188 handled the ALTERs. All
-- tables are campaign-scoped and registered in CampaignRepository's purge
-- cascade + savegame scope map (the §4.7 note: no new PoI column — the reused
-- settlement_pois.owner_faction_id / pois.faction_id already exist).
--
-- Band vocabulary note (§4.2 / §3.2): faction_stances uses the Axioms ladder
-- band set (hostile|unfriendly|neutral|indifferent|friendly|allied) verbatim
-- from the §4.2 column spec. The existing realm_relations table keeps its own
-- six-band set (…|cordial|…) — the two are mapped, not merged (authority split
-- §3.1: realm↔realm political state lives ONLY in realm_relations; realm-mirror
-- pairs are forbidden in faction_stances, enforced by the repository write API).

-- --- Faction Framework FF-1 (§4.2: faction_stances) ---
-- One row per INSTANTIATED directed pair (A's view of B). Most pairs stay
-- un-instantiated and resolve through DefaultStanceEvaluator (§7.2) at read.
CREATE TABLE IF NOT EXISTS faction_stances (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    faction_a_id TEXT NOT NULL REFERENCES factions(id),
    faction_b_id TEXT NOT NULL REFERENCES factions(id),
    public_stance TEXT NOT NULL DEFAULT 'neutral'
        CHECK(public_stance IN ('hostile', 'unfriendly', 'neutral', 'indifferent', 'friendly', 'allied')),
    -- NULL = same as public (the common case). Discovery-only (§7.4): never
    -- reaches any UI or LLM payload; only the explicit audit accessor returns it.
    true_stance TEXT
        CHECK(true_stance IS NULL OR true_stance IN ('hostile', 'unfriendly', 'neutral', 'indifferent', 'friendly', 'allied')),
    betrayal_condition TEXT,                          -- JSON trigger (§7.3); only when true_stance differs
    stance_reason TEXT NOT NULL DEFAULT '',           -- last evaluator summary (narration/debug)
    grievance_score INTEGER NOT NULL DEFAULT 0,       -- decayed rolling ledger sum (§4.5)
    last_evaluated_day INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_faction_stances_pair
    ON faction_stances(faction_a_id, faction_b_id);
CREATE INDEX IF NOT EXISTS idx_faction_stances_campaign
    ON faction_stances(campaign_id);

-- --- Faction Framework FF-1 (§4.3: treaties) ---
-- NO 'tribute' kind: per RAW, ongoing tribute IS vassalage (§2.2) and fires on
-- the monthly tick automatically. One-time payments ride terms JSON as
-- 'indemnity_gp'. Schema only in FF-1; the TreatyResolver lands in FF-3.
CREATE TABLE IF NOT EXISTS treaties (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    kind TEXT NOT NULL
        CHECK(kind IN ('alliance', 'defensive_pact', 'non_aggression', 'protectorate', 'trade_pact')),
    realm_a_id TEXT NOT NULL REFERENCES realms(id),
    realm_b_id TEXT NOT NULL REFERENCES realms(id),
    terms TEXT NOT NULL DEFAULT '{}',                 -- JSON: tribute gp/month, duration, casus, exceptions
    signed_day INTEGER NOT NULL DEFAULT 0,
    duration_months INTEGER,                          -- NULL = indefinite (renewal checks apply, §5.5)
    status TEXT NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'expired', 'renewed', 'broken', 'dissolved')),
    broken_by_realm_id TEXT REFERENCES realms(id),
    broken_day INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_treaties_campaign
    ON treaties(campaign_id);
CREATE INDEX IF NOT EXISTS idx_treaties_pair
    ON treaties(realm_a_id, realm_b_id, status);

-- --- Faction Framework FF-1 (§4.5: faction_events — the grievance/favor ledger) ---
-- Append-only ledger of inter-faction deeds; a stance's grievance_score is its
-- decayed rolling sum. Entries age out (default 60 months); 'betrayal_executed'
-- never expires (expires_day NULL). Kinds are an initial vocabulary (§4.5); the
-- repository write path validates against it.
CREATE TABLE IF NOT EXISTS faction_events (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    day INTEGER NOT NULL DEFAULT 0,
    actor_faction_id TEXT NOT NULL REFERENCES factions(id),
    target_faction_id TEXT NOT NULL REFERENCES factions(id),
    kind TEXT NOT NULL,
    magnitude INTEGER NOT NULL DEFAULT 0,
    data TEXT NOT NULL DEFAULT '{}',                  -- JSON detail
    expires_day INTEGER,                              -- NULL = never expires (betrayal_executed)
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_faction_events_campaign
    ON faction_events(campaign_id);
CREATE INDEX IF NOT EXISTS idx_faction_events_pair
    ON faction_events(actor_faction_id, target_faction_id);

-- --- Faction Framework FF-1 (§4.6: faction_plots + members) ---
-- Multi-party hidden intentions. Schema only in FF-1; PlotResolver lands FF-3+.
CREATE TABLE IF NOT EXISTS faction_plots (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    kind TEXT NOT NULL
        CHECK(kind IN ('rebellion', 'defection', 'betrayal', 'coup')),
    instigator_faction_id TEXT NOT NULL REFERENCES factions(id),
    target_faction_id TEXT REFERENCES factions(id),
    secrecy INTEGER NOT NULL DEFAULT 10,              -- countdown resource; ops & leaks erode it (§7.4)
    launch_condition TEXT NOT NULL DEFAULT '{}',      -- JSON (§5.7)
    status TEXT NOT NULL DEFAULT 'brewing'
        CHECK(status IN ('brewing', 'recruiting', 'ready', 'launched', 'exposed', 'abandoned', 'resolved')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_faction_plots_campaign
    ON faction_plots(campaign_id);

CREATE TABLE IF NOT EXISTS faction_plot_members (
    plot_id TEXT NOT NULL REFERENCES faction_plots(id),
    faction_id TEXT NOT NULL REFERENCES factions(id),
    commitment TEXT NOT NULL DEFAULT 'committed'
        CHECK(commitment IN ('committed', 'sympathetic', 'informant')),
    joined_day INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (plot_id, faction_id)
);

-- --- Faction Framework FF-1 (§4.8: realm_petitions) ---
-- Overt vassal requests up the ladder (the Resignation machinery, §5.9). Public
-- court business, no secrecy resource. Schema only in FF-1.
CREATE TABLE IF NOT EXISTS realm_petitions (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    petitioner_domain_id TEXT NOT NULL REFERENCES domains(id),
    liege_domain_id TEXT REFERENCES domains(id),
    kind TEXT NOT NULL
        CHECK(kind IN ('release', 'transfer', 'appeal')),
    status TEXT NOT NULL DEFAULT 'filed'
        CHECK(status IN ('filed', 'granted', 'refused', 'bought_off', 'escalated', 'withdrawn')),
    filed_day INTEGER NOT NULL DEFAULT 0,
    resolved_day INTEGER,
    terms TEXT NOT NULL DEFAULT '{}',                 -- proposed new liege, sweeteners, adjudicator notes
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_realm_petitions_campaign
    ON realm_petitions(campaign_id);

-- --- Faction Framework FF-1 (§4.9: domain_tithe_shares) ---
-- Ruler-set apportionment of a domain's RAW tithe expense among its temple
-- factions (§6.4). Integer points summing to 100 per domain; gp division uses
-- banker's rounding (repository enforces both). Schema only in FF-1.
CREATE TABLE IF NOT EXISTS domain_tithe_shares (
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    domain_id TEXT NOT NULL REFERENCES domains(id),
    faction_id TEXT NOT NULL REFERENCES factions(id),
    share_pct INTEGER NOT NULL DEFAULT 0,             -- points; a domain's rows sum to 100
    set_day INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (domain_id, faction_id)
);
CREATE INDEX IF NOT EXISTS idx_domain_tithe_shares_campaign
    ON domain_tithe_shares(campaign_id);
