-- Migration 035: Enforce party membership mutual exclusivity.
-- 1. Deduplicate party_members rows (keep most recent per character_id).
-- 2. Recreate party_members with UNIQUE(character_id) constraint.
-- 3. Repair orphan trained_creatures (assign party_id from handler or first campaign party).
-- 4. Recreate trained_creatures with party_id NOT NULL.

PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

-- =========================================================================
-- Part 1: party_members — deduplicate then add UNIQUE(character_id)
-- =========================================================================

-- Delete duplicate rows, keeping the one with the latest joined_at per character_id.
-- On ties, keep the row with the smallest rowid (first inserted).
DELETE FROM party_members
WHERE rowid NOT IN (
    SELECT rowid FROM (
        SELECT rowid, ROW_NUMBER() OVER (
            PARTITION BY character_id ORDER BY joined_at DESC, rowid ASC
        ) AS rn
        FROM party_members
    ) WHERE rn = 1
);

-- Recreate with UNIQUE constraint on character_id.
ALTER TABLE party_members RENAME TO party_members_old;

CREATE TABLE party_members (
    party_id TEXT NOT NULL REFERENCES parties(id),
    character_id TEXT NOT NULL REFERENCES characters(id),
    formation_slot TEXT NOT NULL DEFAULT 'middle'
        CHECK(formation_slot IN ('point', 'front', 'middle', 'rear')),
    formation_col INTEGER NOT NULL DEFAULT -1,
    formation_row INTEGER NOT NULL DEFAULT -1,
    joined_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (party_id, character_id),
    UNIQUE (character_id)
);

INSERT INTO party_members
    SELECT * FROM party_members_old;

DROP TABLE party_members_old;

-- =========================================================================
-- Part 2: trained_creatures — repair orphans then enforce NOT NULL party_id
-- =========================================================================

-- Assign orphan creatures to their handler's party.
UPDATE trained_creatures
SET party_id = (
    SELECT pm.party_id FROM party_members pm
    WHERE pm.character_id = trained_creatures.handler_id
    LIMIT 1
)
WHERE (party_id IS NULL OR party_id = '')
  AND handler_id IS NOT NULL
  AND handler_id != ''
  AND EXISTS (
    SELECT 1 FROM party_members pm
    WHERE pm.character_id = trained_creatures.handler_id
  );

-- For remaining orphans, assign to the first party in their campaign.
UPDATE trained_creatures
SET party_id = (
    SELECT p.id FROM parties p
    WHERE p.campaign_id = trained_creatures.campaign_id
    ORDER BY p.created_at ASC, p.id ASC
    LIMIT 1
)
WHERE (party_id IS NULL OR party_id = '')
  AND EXISTS (
    SELECT 1 FROM parties p
    WHERE p.campaign_id = trained_creatures.campaign_id
  );

-- Mark truly unrecoverable creatures (no party in campaign) as dead.
UPDATE trained_creatures
SET is_alive = 0
WHERE party_id IS NULL OR party_id = '';

-- Recreate with NOT NULL constraint on party_id.
ALTER TABLE trained_creatures RENAME TO trained_creatures_old;

CREATE TABLE trained_creatures (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    party_id TEXT NOT NULL REFERENCES parties(id),
    species_id TEXT NOT NULL,
    purchase_item_key TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    role TEXT NOT NULL DEFAULT 'L'
        CHECK(role IN ('M', 'WM', 'G', 'H', 'D', 'L', 'WB')),
    tricks_known TEXT NOT NULL DEFAULT '[]',
    trick_limit INTEGER NOT NULL DEFAULT 5,
    morale INTEGER NOT NULL DEFAULT 0,
    handler_id TEXT REFERENCES characters(id) DEFAULT NULL,
    introduced_handlers TEXT NOT NULL DEFAULT '[]',
    hp_current INTEGER NOT NULL DEFAULT 1,
    hp_max INTEGER NOT NULL DEFAULT 1,
    training_complete INTEGER NOT NULL DEFAULT 1 CHECK(training_complete IN (0, 1)),
    is_alive INTEGER NOT NULL DEFAULT 1 CHECK(is_alive IN (0, 1)),
    formation_col INTEGER NOT NULL DEFAULT -1,
    formation_row INTEGER NOT NULL DEFAULT -1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Only migrate creatures that have a valid party_id after repair.
-- Dead creatures with no party are excluded (they have party_id = '' or NULL).
INSERT INTO trained_creatures
    SELECT * FROM trained_creatures_old
    WHERE party_id IS NOT NULL AND party_id != '';

DROP TABLE trained_creatures_old;

COMMIT;

PRAGMA foreign_keys = ON;
