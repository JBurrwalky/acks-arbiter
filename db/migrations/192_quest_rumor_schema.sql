-- Migration 192: Quest & Rumor system (Session Q-1) — full §12 data model.
-- generation/gdd-quest-rumor-system.md §12 (table column lists normative).
--
-- Seed layer (setting-gen DB; frozen after Layer-8 lock except prose):
--   setting_quests, setting_rumors — mirrors the setting_poi_seeds/
--   setting_ruin_seeds convention: generation-assigned TEXT id
--   ("quest_NNNN"/"rum_NNNN"), PRIMARY KEY (campaign_id, id), no FK on id.
--
-- Runtime layer (campaign DB):
--   quests, quest_rewards, domain_grants, rumors, rumor_settlement_pool —
--   CampaignRepository.generate_id() hex-string ids, TEXT PRIMARY KEY.
--
-- FK note (Q-1 build-time verification, per docs/handoff-quest-rumor-build.md
-- §3 override): factions(id) already exists in db/schema.sql (pre-Wave-0;
-- Faction FF-1 only ALTERs it) — quests.questgiver_faction_id FKs factions(id)
-- directly, no nullable-no-FK workaround needed.
--
-- Determinism: all "mechanical" columns on setting_quests/setting_rumors are
-- canonical for SettingDatasetHasher (§10.3/O-Q10); *_placeholder columns are
-- prose, excluded — mirrors the setting_narrative treatment. See
-- SettingDatasetHasher.QUEST_COLUMNS / RUMOR_COLUMNS wiring in
-- setting_dataset_hasher.gd and setting_repository.gd.

-- ---------------------------------------------------------------------------
-- Seed layer
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS setting_quests (
    id TEXT NOT NULL,                              -- "quest_NNNN"
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    questgiver_npc_id TEXT NOT NULL DEFAULT '',
    questgiver_faction_id TEXT REFERENCES factions(id),
    threat_type TEXT NOT NULL DEFAULT '' CHECK(threat_type IN (
        'monster_lair', 'dungeon', 'brigand', 'creature_bounty', 'recovery',
        'escort', 'delivery', 'domain_conquest', 'reconnaissance', 'faction_goal')),
    threat_source_id TEXT NOT NULL DEFAULT '',
    threat_hex TEXT NOT NULL DEFAULT '',            -- "QQQQRRRR" hex coordinate string
    completion_type TEXT NOT NULL DEFAULT '' CHECK(completion_type IN (
        'clear_dungeon', 'clear_lair', 'kill_target', 'retrieve_item',
        'escort_npc', 'deliver_item', 'hold_territory', 'scout_hex',
        'build_structure', 'faction_goal')),
    completion_target_id TEXT NOT NULL DEFAULT '',
    reward TEXT NOT NULL DEFAULT '{}',              -- JSON (§8 RewardValuator output)
    posting_type TEXT NOT NULL DEFAULT 'posted'
        CHECK(posting_type IN ('personal', 'posted', 'broadcast')),
    posting_range INTEGER NOT NULL DEFAULT 8,
    expires_day INTEGER,                            -- NULL = domain_conquest/persistent
    description_placeholder TEXT NOT NULL DEFAULT '',
    questgiver_dialogue_placeholder TEXT NOT NULL DEFAULT '',
    completion_dialogue_placeholder TEXT NOT NULL DEFAULT '',
    title_placeholder TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

CREATE TABLE IF NOT EXISTS setting_rumors (
    id TEXT NOT NULL,                               -- "rum_NNNN"
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    source_type TEXT NOT NULL DEFAULT '' CHECK(source_type IN (
        'poi', 'dungeon', 'lair', 'political', 'settlement', 'npc',
        'quest', 'historical')),
    source_id TEXT NOT NULL DEFAULT '',
    source_quest_id TEXT REFERENCES setting_quests(id),
    content_hint TEXT NOT NULL DEFAULT '',
    accuracy TEXT NOT NULL DEFAULT 'true' CHECK(accuracy IN (
        'true', 'exaggerated', 'understated', 'misleading', 'false')),
    accuracy_detail TEXT NOT NULL DEFAULT '',
    knowledge_category TEXT NOT NULL DEFAULT 'local' CHECK(knowledge_category IN (
        'local', 'professional', 'political', 'criminal', 'religious',
        'military', 'dungeon', 'personal', 'historical')),
    origin_hex TEXT NOT NULL DEFAULT '',
    settlement_range INTEGER NOT NULL DEFAULT 5,
    min_npc_tier TEXT NOT NULL DEFAULT 'C' CHECK(min_npc_tier IN ('C', 'B', 'A')),
    freshness TEXT NOT NULL DEFAULT 'current' CHECK(freshness IN (
        'persistent', 'current', 'stale')),
    narrated_placeholder TEXT NOT NULL DEFAULT '',
    -- No `reliability` column — accuracy is verification-only (§4.4/O-Q3).
    PRIMARY KEY (campaign_id, id)
);

CREATE INDEX IF NOT EXISTS idx_setting_quests_campaign ON setting_quests(campaign_id);
CREATE INDEX IF NOT EXISTS idx_setting_rumors_campaign ON setting_rumors(campaign_id);
CREATE INDEX IF NOT EXISTS idx_setting_rumors_source_quest ON setting_rumors(source_quest_id);

-- ---------------------------------------------------------------------------
-- Runtime layer
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS quests (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    status TEXT NOT NULL DEFAULT 'available' CHECK(status IN (
        'available', 'accepted', 'completed', 'failed', 'expired', 'abandoned')),
    -- questgiver
    questgiver_id TEXT REFERENCES characters(id),
    questgiver_faction_id TEXT REFERENCES factions(id),
    questgiver_settlement_id TEXT REFERENCES settlement_entrances(id),
    questgiver_motivation TEXT NOT NULL DEFAULT '',
    -- the problem
    threat_type TEXT NOT NULL DEFAULT '' CHECK(threat_type IN (
        'monster_lair', 'dungeon', 'brigand', 'creature_bounty', 'recovery',
        'escort', 'delivery', 'domain_conquest', 'reconnaissance', 'faction_goal')),
    threat_source_id TEXT NOT NULL DEFAULT '',
    threat_hex TEXT NOT NULL DEFAULT '',
    threat_description_hint TEXT NOT NULL DEFAULT '',
    -- completion
    completion_type TEXT NOT NULL DEFAULT '' CHECK(completion_type IN (
        'clear_dungeon', 'clear_lair', 'kill_target', 'retrieve_item',
        'escort_npc', 'deliver_item', 'hold_territory', 'scout_hex',
        'build_structure', 'faction_goal')),
    completion_target_id TEXT NOT NULL DEFAULT '',
    completion_verified_by TEXT NOT NULL DEFAULT 'automatic'
        CHECK(completion_verified_by IN ('questgiver_report', 'automatic', 'witness')),
    is_complete INTEGER NOT NULL DEFAULT 0 CHECK(is_complete IN (0, 1)),
    progress TEXT NOT NULL DEFAULT '{}',            -- JSON, multi-step tracking
    -- narration (LLM/template; *_placeholder value until filled)
    title TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    questgiver_dialogue TEXT NOT NULL DEFAULT '',
    completion_dialogue TEXT NOT NULL DEFAULT '',
    -- distribution
    posting_type TEXT NOT NULL DEFAULT 'posted'
        CHECK(posting_type IN ('personal', 'posted', 'broadcast')),
    posting_range INTEGER NOT NULL DEFAULT 8,
    -- timing
    created_day INTEGER NOT NULL DEFAULT 0,
    expires_day INTEGER,
    accepted_day INTEGER,
    completed_day INTEGER,
    -- party tracking
    accepting_pc_id TEXT REFERENCES characters(id),
    reward_recipient_pc_id TEXT REFERENCES characters(id),
    -- faction bridge (§7.9/§11.2; populated when threat_type/completion_type = 'faction_goal')
    faction_goal_id TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_quests_campaign ON quests(campaign_id);
CREATE INDEX IF NOT EXISTS idx_quests_status ON quests(status);
CREATE INDEX IF NOT EXISTS idx_quests_questgiver_settlement ON quests(questgiver_settlement_id);
CREATE INDEX IF NOT EXISTS idx_quests_threat_hex ON quests(threat_hex);
CREATE INDEX IF NOT EXISTS idx_quests_threat_type ON quests(threat_type);
CREATE INDEX IF NOT EXISTS idx_quests_questgiver_faction ON quests(questgiver_faction_id);

CREATE TABLE IF NOT EXISTS quest_rewards (
    id TEXT PRIMARY KEY,
    quest_id TEXT NOT NULL REFERENCES quests(id),
    reward_type TEXT NOT NULL DEFAULT 'gold'
        CHECK(reward_type IN ('gold', 'item', 'domain', 'political', 'mixed')),
    gold_value INTEGER NOT NULL DEFAULT 0,
    item_id TEXT NOT NULL DEFAULT '',
    item_description TEXT NOT NULL DEFAULT '',
    domain_grant_id TEXT REFERENCES domain_grants(id),
    political_favor TEXT NOT NULL DEFAULT '',
    total_gp_value INTEGER NOT NULL DEFAULT 0,
    xp_eligible INTEGER NOT NULL DEFAULT 1 CHECK(xp_eligible IN (0, 1)),
    variance_applied REAL NOT NULL DEFAULT 0.0
);

CREATE INDEX IF NOT EXISTS idx_quest_rewards_quest ON quest_rewards(quest_id);

CREATE TABLE IF NOT EXISTS domain_grants (
    id TEXT PRIMARY KEY,
    quest_reward_id TEXT NOT NULL REFERENCES quest_rewards(id),
    hex_ids TEXT NOT NULL DEFAULT '[]',              -- JSON array of hex coordinate strings
    territory_class TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(territory_class IN ('civilized', 'borderlands', 'wilderness')),
    estimated_families INTEGER NOT NULL DEFAULT 0,
    stronghold_present INTEGER NOT NULL DEFAULT 0 CHECK(stronghold_present IN (0, 1)),
    stronghold_value INTEGER NOT NULL DEFAULT 0,
    vassal_obligations TEXT NOT NULL DEFAULT '{}',   -- JSON (tribute/Favors-and-Duties terms)
    title_granted TEXT NOT NULL DEFAULT '',
    -- The one assigned owner (§8.8/O-Q14) — no level gate on possession.
    single_owner_pc_id TEXT REFERENCES characters(id)
);

CREATE INDEX IF NOT EXISTS idx_domain_grants_quest_reward ON domain_grants(quest_reward_id);

CREATE TABLE IF NOT EXISTS rumors (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    source_type TEXT NOT NULL DEFAULT '' CHECK(source_type IN (
        'poi', 'dungeon', 'lair', 'political', 'settlement', 'npc',
        'quest', 'historical')),
    source_id TEXT NOT NULL DEFAULT '',
    source_quest_id TEXT REFERENCES quests(id),
    content_hint TEXT NOT NULL DEFAULT '',
    narrated_text TEXT NOT NULL DEFAULT '',
    accuracy TEXT NOT NULL DEFAULT 'true' CHECK(accuracy IN (
        'true', 'exaggerated', 'understated', 'misleading', 'false')),
    accuracy_detail TEXT NOT NULL DEFAULT '',
    knowledge_category TEXT NOT NULL DEFAULT 'local' CHECK(knowledge_category IN (
        'local', 'professional', 'political', 'criminal', 'religious',
        'military', 'dungeon', 'personal', 'historical')),
    origin_hex TEXT NOT NULL DEFAULT '',
    settlement_range INTEGER NOT NULL DEFAULT 5,
    min_npc_tier TEXT NOT NULL DEFAULT 'C' CHECK(min_npc_tier IN ('C', 'B', 'A')),
    freshness TEXT NOT NULL DEFAULT 'current' CHECK(freshness IN (
        'persistent', 'current', 'stale')),
    -- runtime state
    known_to_party INTEGER NOT NULL DEFAULT 0 CHECK(known_to_party IN (0, 1)),
    verified INTEGER NOT NULL DEFAULT 0 CHECK(verified IN (0, 1)),
    first_heard_day INTEGER,
    created_day INTEGER NOT NULL DEFAULT 0,
    expires_day INTEGER
    -- No `reliability` column — accuracy is verification-only (§4.4/O-Q3).
);

CREATE INDEX IF NOT EXISTS idx_rumors_campaign ON rumors(campaign_id);
CREATE INDEX IF NOT EXISTS idx_rumors_source_id ON rumors(source_id);
CREATE INDEX IF NOT EXISTS idx_rumors_origin_hex ON rumors(origin_hex);
CREATE INDEX IF NOT EXISTS idx_rumors_knowledge_category ON rumors(knowledge_category);
CREATE INDEX IF NOT EXISTS idx_rumors_freshness ON rumors(freshness);
CREATE INDEX IF NOT EXISTS idx_rumors_source_quest ON rumors(source_quest_id);

CREATE TABLE IF NOT EXISTS rumor_settlement_pool (
    rumor_id TEXT NOT NULL REFERENCES rumors(id),
    settlement_id TEXT NOT NULL REFERENCES settlement_entrances(id),
    PRIMARY KEY (rumor_id, settlement_id)
);

CREATE INDEX IF NOT EXISTS idx_rumor_settlement_pool_settlement ON rumor_settlement_pool(settlement_id);
