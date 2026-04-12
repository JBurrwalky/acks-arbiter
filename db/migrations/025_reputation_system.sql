-- Migration 025: Reputation system (Phase G-1)
--
-- Adds factions, faction_memberships, reputation_entries, social_groups.
-- Adds parent_domain_id and barred_party_ids to settlement_entrances.
-- Adds ruler_npc_id to domains.
--
-- Reputation is party-wide. Score is canonical (-100..+100); tier is denormalized
-- for fast reaction-roll lookup. Cascade (settlement <- domain <- ruler) is
-- computed at query time, not stored.

CREATE TABLE IF NOT EXISTS factions (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    name TEXT NOT NULL,
    alignment TEXT NOT NULL DEFAULT 'neutral'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    faction_type TEXT NOT NULL DEFAULT 'tribal',
    home_domain_id TEXT REFERENCES domains(id),
    leader_npc_id TEXT REFERENCES characters(id),
    parent_faction_id TEXT REFERENCES factions(id),
    description TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_factions_campaign ON factions(campaign_id);

CREATE TABLE IF NOT EXISTS faction_memberships (
    faction_id TEXT NOT NULL REFERENCES factions(id),
    npc_id TEXT NOT NULL REFERENCES characters(id),
    role TEXT NOT NULL DEFAULT 'member',
    PRIMARY KEY (faction_id, npc_id)
);

CREATE INDEX IF NOT EXISTS idx_faction_memberships_npc ON faction_memberships(npc_id);

CREATE TABLE IF NOT EXISTS reputation_entries (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    party_id TEXT NOT NULL REFERENCES parties(id),
    scope_type TEXT NOT NULL
        CHECK(scope_type IN ('faction','settlement','domain','tier_a_npc','tier_b_npc','social_group')),
    scope_id TEXT NOT NULL,
    score INTEGER NOT NULL DEFAULT 0,
    tier TEXT NOT NULL DEFAULT 'neutral'
        CHECK(tier IN ('hostile','unfriendly','neutral','indifferent','friendly')),
    last_reason TEXT NOT NULL DEFAULT '',
    last_updated TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(campaign_id, party_id, scope_type, scope_id)
);

CREATE INDEX IF NOT EXISTS idx_reputation_party_scope
    ON reputation_entries(party_id, scope_type, scope_id);

CREATE TABLE IF NOT EXISTS social_groups (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    name TEXT NOT NULL,
    group_type TEXT NOT NULL DEFAULT 'guild',
    description TEXT NOT NULL DEFAULT ''
);

ALTER TABLE settlement_entrances ADD COLUMN parent_domain_id TEXT
    REFERENCES domains(id) DEFAULT NULL;

ALTER TABLE settlement_entrances ADD COLUMN barred_party_ids TEXT
    NOT NULL DEFAULT '[]';

ALTER TABLE domains ADD COLUMN ruler_npc_id TEXT
    REFERENCES characters(id) DEFAULT NULL;
