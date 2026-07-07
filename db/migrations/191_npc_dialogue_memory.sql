-- Migration 191: NPC Dialogue & Interaction — memory data model (Phase 1 "The Spine").
--
-- generation/gdd-npc-dialogue.md §8.1 (the exact SQL these tables mirror) + §15 data model.
-- Lands the FULL approved three-table memory model in one pass (the project's
-- "land the whole approved data model in one pass" precedent, FF-1.0 / Q-1), even though
-- npc_issues (Track 2 of the two-track model, §6.5) is not consumed until dialogue Phase 3 —
-- shipping the schema now avoids a churn migration later and keeps the purge cascade complete.
--
--   npc_relationships — Layer 1, the mechanical spine: one row per NPC x party, holds attitude
--                       (7-state, the diplomatic 5 + intimidation's fearful/cowed variants),
--                       the Track-1 (relationship-tone) influence ladder counter, favor ledger,
--                       first/last interaction days, and JSON role tags.
--   npc_memories      — Layer 2, episodic color: one row per remembered event, kind-tagged, with a
--                       human-readable summary + JSON facts + importance for top-K recall (§8.3).
--   npc_issues        — Layer 3 / Track 2: one row per outstanding-or-resolved extraordinary ask,
--                       with a per-issue influence ladder counter and negotiated terms (§6.5).
--
-- All three are LEAF tables scoped directly by campaign_id (registered in
-- CampaignRepository._SCOPE_DIRECT_CAMPAIGN under the "Dialogue subsystem (Phase 1)" block).
-- Non-destructive: pure CREATE IF NOT EXISTS, no rebuilds, nothing references these via FK yet.

BEGIN TRANSACTION;

-- Layer 1 — relationship spine (one row per NPC x party).
CREATE TABLE IF NOT EXISTS npc_relationships (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL,
    npc_id TEXT NOT NULL,
    party_id TEXT NOT NULL,
    attitude TEXT NOT NULL DEFAULT 'neutral'
        CHECK(attitude IN ('hostile','unfriendly','neutral','indifferent','friendly','fearful','cowed')),
    is_intimidated INTEGER NOT NULL DEFAULT 0,
    influence_attempt_count INTEGER NOT NULL DEFAULT 0,       -- Track 1 (tone) ladder counter only
    next_attempt_available_at INTEGER NOT NULL DEFAULT 0,     -- absolute rounds, tone-track
    favors_owed_to_party INTEGER NOT NULL DEFAULT 0,
    favors_owed_by_party INTEGER NOT NULL DEFAULT 0,
    first_met_day INTEGER,
    last_interaction_day INTEGER,
    role_tags TEXT NOT NULL DEFAULT '[]',      -- JSON: "employer","quest_giver","rival","victim"...
    UNIQUE(campaign_id, npc_id, party_id)
);

-- Layer 2 — episodic memories (the color).
CREATE TABLE IF NOT EXISTS npc_memories (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL,
    npc_id TEXT NOT NULL,
    party_id TEXT,
    kind TEXT NOT NULL CHECK(kind IN
        ('conversation','event','promise','debt','grudge','gift','deception_by_npc','deception_suffered')),
    summary TEXT NOT NULL,                     -- 1-3 sentences, human-readable
    facts TEXT NOT NULL DEFAULT '[]',          -- JSON tags: [{"promised":"escort to Karn"},{"lied_about":"tomb location"}]
    attitude_after TEXT,
    importance INTEGER NOT NULL DEFAULT 1,      -- 1..5
    created_day INTEGER NOT NULL,
    last_recalled_day INTEGER,
    source_session_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_npc_memories_recall
    ON npc_memories(campaign_id, npc_id, importance DESC, created_day DESC);

-- Layer 3 — per-issue reactions (Track 2 of the two-track model, §6.5;
-- one row per outstanding or resolved ask). Not consumed until Phase 3, landed now.
CREATE TABLE IF NOT EXISTS npc_issues (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL,
    npc_id TEXT NOT NULL,
    party_id TEXT NOT NULL,
    issue_key TEXT NOT NULL,               -- e.g. "request_action:perform_hijink:spying", "parley:withdraw_army"
    status TEXT NOT NULL DEFAULT 'open'
        CHECK(status IN ('open','granted','refused','withdrawn','expired')),
    last_result TEXT,                      -- refused|negotiable|accepted|accepted_enthusiastic
    attempt_count INTEGER NOT NULL DEFAULT 0,                 -- per-issue ladder counter (§6.3)
    next_attempt_available_at INTEGER NOT NULL DEFAULT 0,     -- absolute rounds
    terms TEXT NOT NULL DEFAULT '{}',      -- JSON: negotiated package (payment, favors, conditions)
    offense_fired INTEGER NOT NULL DEFAULT 0,                 -- §6.6 trigger already applied (once per issue)
    created_day INTEGER NOT NULL,
    resolved_day INTEGER,
    UNIQUE(campaign_id, npc_id, party_id, issue_key)
);

COMMIT;
