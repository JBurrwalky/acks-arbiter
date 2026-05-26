-- Migration 124: Realm substrate — Phase 11D-prereq.0a per
-- docs/phase-11-plan.md §11D-prereq.0a.
--
-- A "realm" in ACKS is the political unit rooted at a domain whose
-- liege_domain_id is NULL. Pre-substrate, realms had no row representation
-- of their own — they were implicit in the apex domain. This migration
-- gives realms an explicit row + cached domain->realm pointer + a
-- relations table supporting six-band diplomatic dispositions.
--
-- Concrete additions:
--   1. `realms` table — one row per realm. Tracked realms have a
--      head_character_id pointing at the apex domain's owner; foreign
--      realms (flavor-backdrop entities for off-map conquerors) carry
--      realm_kind='foreign' and may have a NULL head.
--   2. `realm_relations` table — pair-symmetric diplomatic-disposition
--      cache. Repository enforces canonical pair ordering (realm_a_id <
--      realm_b_id lexicographically) so each pair has at most one row.
--   3. `domains.realm_id` — cached pointer to the realm a domain belongs
--      to. Avoids the 64-hop apex walk in `RealmGraph.apex_for_domain`
--      on hot paths; falls back to the walk when null.
--
-- Backfill: every existing apex domain (liege_domain_id IS NULL) gets a
-- tracked realm row. Then realm_id is propagated down the liege chain
-- via iterative UPDATE — bounded loop covering up to 8 levels deep, which
-- is comfortably more than the canonical Emperor->King->Prince->Duke->
-- Count->Marquis->Baron->personal chain (max 8 levels).
--
-- No DROPs. Backwards-compatible: rows without a realm_id (created before
-- the migration ran or via legacy test paths) fall back to the apex walk.

CREATE TABLE IF NOT EXISTS realms (
    id                       TEXT    PRIMARY KEY,
    campaign_id              TEXT    NOT NULL REFERENCES campaigns(id),
    name                     TEXT    NOT NULL,
    head_character_id        TEXT    REFERENCES characters(id),
    -- Realm-level alignment: may be NULL for mixed-alignment realms.
    alignment                TEXT
        CHECK(alignment IS NULL OR alignment IN ('lawful', 'neutral', 'chaotic')),
    dominant_religion        TEXT    NOT NULL DEFAULT '',
    -- Cultural identifier (placeholder until the culture system ships).
    -- Free-form text for now; future migration constrains to a culture catalog.
    culture                  TEXT    NOT NULL DEFAULT '',
    -- 'tracked' realms are in-simulation; 'foreign' realms are flavor-backdrop
    -- (off-map cultures whose armies may invade but who don't tick their own
    -- domains). 11D-prereq.0b's instantiate_realm_for_off_map_force creates
    -- these on demand.
    realm_kind               TEXT    NOT NULL DEFAULT 'tracked'
        CHECK(realm_kind IN ('tracked', 'foreign')),
    created_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_realms_campaign
    ON realms(campaign_id);
CREATE INDEX IF NOT EXISTS idx_realms_head_character
    ON realms(head_character_id);

-- Pair-symmetric relations. The repository enforces canonical ordering
-- (realm_a_id < realm_b_id lexicographically) so each pair has at most one
-- row. The disposition values map to the 2d6-reaction-table bands used
-- throughout ACKS — repository sets are project-designed events
-- (treaty signed, war declared, embargo lifted), not RAW dice rolls.
CREATE TABLE IF NOT EXISTS realm_relations (
    id                       TEXT    PRIMARY KEY,
    campaign_id              TEXT    NOT NULL REFERENCES campaigns(id),
    realm_a_id               TEXT    NOT NULL REFERENCES realms(id),
    realm_b_id               TEXT    NOT NULL REFERENCES realms(id),
    disposition              TEXT    NOT NULL DEFAULT 'neutral'
        CHECK(disposition IN ('hostile', 'unfriendly', 'neutral', 'cordial', 'friendly', 'allied')),
    last_changed_day         INTEGER NOT NULL DEFAULT 0,
    created_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_realm_relations_pair
    ON realm_relations(realm_a_id, realm_b_id);

-- Cached realm pointer on domains. Null means "compute via apex walk"
-- (RealmGraph.apex_for_domain). The repository writes this cache on
-- domain creation + on liege_domain_id changes.
ALTER TABLE domains ADD COLUMN realm_id TEXT REFERENCES realms(id);
CREATE INDEX IF NOT EXISTS idx_domains_realm
    ON domains(realm_id);

-- ---------------------------------------------------------------------------
-- Backfill: one tracked realm per apex domain; propagate realm_id down.
-- ---------------------------------------------------------------------------

-- Step 1: insert a `realms` row for every apex domain. The realm id is
-- 'realm_<apex_domain_id>' so the deterministic mapping is reversible.
INSERT OR IGNORE INTO realms (id, campaign_id, name, head_character_id, alignment, dominant_religion, culture, realm_kind)
SELECT
    'realm_' || id,
    campaign_id,
    COALESCE(NULLIF(name, ''), 'Unnamed') || ' Realm',
    owner_character_id,
    alignment,
    religion,
    '',
    'tracked'
FROM domains
WHERE liege_domain_id IS NULL;

-- Step 2: apex domains get their realm_id directly.
UPDATE domains
SET realm_id = 'realm_' || id
WHERE liege_domain_id IS NULL AND realm_id IS NULL;

-- Step 3: propagate realm_id down the liege chain. Each iteration covers
-- one level of depth. Eight iterations covers up to 8 levels of vassalage,
-- which is more than the canonical Emperor->King->...->personal chain.
UPDATE domains SET realm_id = (
    SELECT parent.realm_id FROM domains AS parent WHERE parent.id = domains.liege_domain_id
) WHERE realm_id IS NULL AND liege_domain_id IS NOT NULL;
UPDATE domains SET realm_id = (
    SELECT parent.realm_id FROM domains AS parent WHERE parent.id = domains.liege_domain_id
) WHERE realm_id IS NULL AND liege_domain_id IS NOT NULL;
UPDATE domains SET realm_id = (
    SELECT parent.realm_id FROM domains AS parent WHERE parent.id = domains.liege_domain_id
) WHERE realm_id IS NULL AND liege_domain_id IS NOT NULL;
UPDATE domains SET realm_id = (
    SELECT parent.realm_id FROM domains AS parent WHERE parent.id = domains.liege_domain_id
) WHERE realm_id IS NULL AND liege_domain_id IS NOT NULL;
UPDATE domains SET realm_id = (
    SELECT parent.realm_id FROM domains AS parent WHERE parent.id = domains.liege_domain_id
) WHERE realm_id IS NULL AND liege_domain_id IS NOT NULL;
UPDATE domains SET realm_id = (
    SELECT parent.realm_id FROM domains AS parent WHERE parent.id = domains.liege_domain_id
) WHERE realm_id IS NULL AND liege_domain_id IS NOT NULL;
UPDATE domains SET realm_id = (
    SELECT parent.realm_id FROM domains AS parent WHERE parent.id = domains.liege_domain_id
) WHERE realm_id IS NULL AND liege_domain_id IS NOT NULL;
