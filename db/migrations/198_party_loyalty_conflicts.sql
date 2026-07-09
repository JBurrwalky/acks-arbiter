-- Migration 198: Faction Framework FF-4 — party divided-loyalty conflicts
-- (gdd-faction-framework.md §8.4). The genuine FF-4 schema gap: the allegiance
-- feign/betrayal machinery reuses existing columns (faction_stances.true_stance /
-- betrayal_condition, migration 189) and the audit trail is a file, but the
-- divided-loyalty DETECTOR needs to PERSIST a detected conflict so a monthly re-scan
-- does not re-emit an already-known one (dedup on a deterministic `signature`) and so
-- resolution + double-agent status have a home. Campaign-scoped LEAF table; nothing
-- FKs into it. Registered in CampaignRepository._SCOPE_DIRECT_CAMPAIGN + the purge
-- cascade. Non-destructive (CREATE IF NOT EXISTS).
CREATE TABLE IF NOT EXISTS party_loyalty_conflicts (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    cause TEXT NOT NULL
        CHECK(cause IN ('mutual_hostile_memberships', 'opposite_conflict_sides',
                        'obligation_targets_faction')),
    signature TEXT NOT NULL,
    member_a_id TEXT NOT NULL,
    member_b_id TEXT,
    faction_a_id TEXT NOT NULL,
    faction_b_id TEXT NOT NULL,
    conflict_ref TEXT,
    status TEXT NOT NULL DEFAULT 'detected'
        CHECK(status IN ('detected', 'surfaced', 'resolved', 'double_agent')),
    detected_day INTEGER NOT NULL DEFAULT 0,
    resolved_day INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(campaign_id, signature)
);
CREATE INDEX IF NOT EXISTS idx_party_loyalty_conflicts_campaign
    ON party_loyalty_conflicts(campaign_id);
