-- Migration 080: domain_threats — Phase 9A active-threat tracking.
--
-- Per docs/domain-roadmap-corrected.md Phase 9 + ax_domain_level_encounters.xml
-- + acore_axioms_strongholds_and_domains.xml §bandits L611-630 + §effects_of_morale L538-609.
--
-- A "threat" is any active hostile / lingering / pillaging force in a domain
-- whose presence affects revenue, morale, or requires player action. Kinds:
--
--   "encounter"       — wandering monster incursion per ax_domain_level_encounters
--                       (hostile/unfriendly reaction; lingering/migrating)
--   "bandit_swarm"    — bandits per acore_axioms §bandits (morale -2 or worse)
--   "npc_challenger"  — challenger emerged from bandits per L559/569/577
--   "settled_lair"    — monsters lingered and settled in a domain dungeon
--                       (per §domain_encounter_generation.lingering_or_migrating)
--
-- status:
--   "active"     — present and applying its effects
--   "defeated"   — destroyed by garrison/PC action
--   "negotiated" — driven off / peace bought / mercenary-hired
--   "departed"   — migrated out (timed exit for migrating monsters)
--
-- linked_army_id is set if the threat materializes as an `armies` row
-- (bandit swarms are armies; encounters with army-style BR are too). Phase 9B
-- siege machinery uses this column to look up the besieging force.

CREATE TABLE IF NOT EXISTS domain_threats (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                   TEXT    NOT NULL REFERENCES domains(id),
    kind                        TEXT    NOT NULL
        CHECK(kind IN ('encounter', 'bandit_swarm', 'npc_challenger', 'settled_lair')),
    status                      TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'defeated', 'negotiated', 'departed')),
    -- Encounter-specific fields (NULL for non-encounter kinds)
    creature_key                TEXT    NOT NULL DEFAULT '',
    creature_count              INTEGER NOT NULL DEFAULT 0,
    platoon_br                  REAL    NOT NULL DEFAULT 0.0,
    is_lair                     INTEGER NOT NULL DEFAULT 0
        CHECK(is_lair IN (0, 1)),
    is_lingering                INTEGER NOT NULL DEFAULT 0
        CHECK(is_lingering IN (0, 1)),
    reaction                    TEXT    NOT NULL DEFAULT ''
        CHECK(reaction IN ('', 'hostile', 'unfriendly', 'neutral', 'mercantilist', 'friendly')),
    -- Bandit-specific fields
    bandit_count                INTEGER NOT NULL DEFAULT 0,
    -- NPC challenger-specific fields
    challenger_character_id     TEXT    REFERENCES characters(id),
    challenger_level            INTEGER NOT NULL DEFAULT 0,
    -- Lifecycle / linkage
    linked_army_id              TEXT    REFERENCES armies(id),
    linked_hex_q                INTEGER,
    linked_hex_r                INTEGER,
    morale_penalty              INTEGER NOT NULL DEFAULT 0,
    spawned_calendar_day        INTEGER NOT NULL DEFAULT 0,
    resolved_calendar_day       INTEGER NOT NULL DEFAULT 0,
    payload_json                TEXT    NOT NULL DEFAULT '{}',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_domain_threats_domain
    ON domain_threats(domain_id);

CREATE INDEX IF NOT EXISTS idx_domain_threats_status
    ON domain_threats(status, domain_id);

CREATE INDEX IF NOT EXISTS idx_domain_threats_linked_army
    ON domain_threats(linked_army_id) WHERE linked_army_id IS NOT NULL;

-- Partial unique: at most one active bandit_swarm and at most one active
-- npc_challenger per domain. Multiple encounters may co-exist (different
-- creatures hitting from different directions).
CREATE UNIQUE INDEX IF NOT EXISTS idx_domain_threats_unique_active_bandit_swarm
    ON domain_threats(domain_id) WHERE kind = 'bandit_swarm' AND status = 'active';

CREATE UNIQUE INDEX IF NOT EXISTS idx_domain_threats_unique_active_challenger
    ON domain_threats(domain_id) WHERE kind = 'npc_challenger' AND status = 'active';
