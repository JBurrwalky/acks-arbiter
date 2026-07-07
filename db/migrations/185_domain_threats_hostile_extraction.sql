-- Migration 185: add 'hostile_extraction' to the domain_threats.kind CHECK enum.
--
-- docs/handoff-army-warfare-seams.md §5 (step 4) — the player-facing "resist or concede"
-- surface for when an NPC army requisitions/loots the PLAYER's domain. Phase C left this as a
-- notification-only guard (no persistent row, no resist-choice) pending a Jedidiah decision;
-- approved 2026-07-06. An NPC extraction against a player-owned domain now creates a PERSISTENT
-- threat row (idempotent per domain+raider army) so the player can Resist (materialise the
-- garrison levy → field battle) or Concede (allow the yield) from the threats sub-tab, instead
-- of the extraction silently succeeding or silently blocking.
--
-- SQLite cannot ALTER a CHECK constraint in place, so this rebuilds domain_threats with the
-- extended enum (the rename/create/copy/drop pattern of migrations 011/013/014/035/117/133).
-- domain_threats is a LEAF table — nothing references it via FK (verified against db/schema.sql
-- 2026-07-06) — so the rebuild is safe. All existing rows copy through unchanged (non-destructive).
--
-- Kinds after this migration:
--   encounter / bandit_swarm / npc_challenger / settled_lair / hostile_extraction
--
-- New partial-unique index enforces the idempotency the surface relies on: at most one ACTIVE
-- hostile_extraction row per (domain, raider army). (The router also checks in code; the index
-- is the DB backstop, mirroring the bandit_swarm / npc_challenger unique-active constraints.)

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

ALTER TABLE domain_threats RENAME TO domain_threats_old;

CREATE TABLE domain_threats (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                   TEXT    NOT NULL REFERENCES domains(id),
    kind                        TEXT    NOT NULL
        CHECK(kind IN ('encounter', 'bandit_swarm', 'npc_challenger', 'settled_lair', 'hostile_extraction')),
    status                      TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'defeated', 'negotiated', 'departed')),
    creature_key                TEXT    NOT NULL DEFAULT '',
    creature_count              INTEGER NOT NULL DEFAULT 0,
    platoon_br                  REAL    NOT NULL DEFAULT 0.0,
    is_lair                     INTEGER NOT NULL DEFAULT 0
        CHECK(is_lair IN (0, 1)),
    is_lingering                INTEGER NOT NULL DEFAULT 0
        CHECK(is_lingering IN (0, 1)),
    reaction                    TEXT    NOT NULL DEFAULT ''
        CHECK(reaction IN ('', 'hostile', 'unfriendly', 'neutral', 'mercantilist', 'friendly')),
    bandit_count                INTEGER NOT NULL DEFAULT 0,
    challenger_character_id     TEXT    REFERENCES characters(id),
    challenger_level            INTEGER NOT NULL DEFAULT 0,
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

INSERT INTO domain_threats (
    id, campaign_id, domain_id, kind, status,
    creature_key, creature_count, platoon_br, is_lair, is_lingering,
    reaction, bandit_count, challenger_character_id, challenger_level,
    linked_army_id, linked_hex_q, linked_hex_r,
    morale_penalty, spawned_calendar_day, resolved_calendar_day, payload_json,
    created_at, updated_at
)
SELECT
    id, campaign_id, domain_id, kind, status,
    creature_key, creature_count, platoon_br, is_lair, is_lingering,
    reaction, bandit_count, challenger_character_id, challenger_level,
    linked_army_id, linked_hex_q, linked_hex_r,
    morale_penalty, spawned_calendar_day, resolved_calendar_day, payload_json,
    created_at, updated_at
FROM domain_threats_old;

DROP TABLE domain_threats_old;

CREATE INDEX IF NOT EXISTS idx_domain_threats_domain ON domain_threats(domain_id);
CREATE INDEX IF NOT EXISTS idx_domain_threats_status ON domain_threats(status, domain_id);
CREATE INDEX IF NOT EXISTS idx_domain_threats_linked_army
    ON domain_threats(linked_army_id) WHERE linked_army_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_domain_threats_unique_active_bandit_swarm
    ON domain_threats(domain_id) WHERE kind = 'bandit_swarm' AND status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS idx_domain_threats_unique_active_challenger
    ON domain_threats(domain_id) WHERE kind = 'npc_challenger' AND status = 'active';
-- New: at most one active hostile_extraction per (domain, raider army).
CREATE UNIQUE INDEX IF NOT EXISTS idx_domain_threats_unique_active_hostile_extraction
    ON domain_threats(domain_id, linked_army_id) WHERE kind = 'hostile_extraction' AND status = 'active';

COMMIT;

PRAGMA legacy_alter_table = OFF;
PRAGMA foreign_keys = ON;
