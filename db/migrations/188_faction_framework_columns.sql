-- Migration 188: Faction Framework FF-1.0 — additive columns on the existing
-- `factions` and `faction_memberships` tables (gdd-faction-framework.md §4.1,
-- §4.4; the ENTIRE §4 data model approved by Jedidiah 2026-07-05/07-06). The
-- new tables land in migration 189; this file is ALTER-only.
--
-- SQLite `ALTER TABLE ADD COLUMN` cannot add UNIQUE/PK/foreign-key constraints
-- or CHECK constraints that reference other columns, but a single-column CHECK
-- on a literal enum rides an ADD COLUMN fine — so scope/status CHECKs are here.
-- The `factions` id-space stays the single registry across all three scopes
-- (§3.1); realm-mirror rows set scope='realm' + realm_id (populated in FF-1.1).
--
-- Non-destructive: every column carries a DEFAULT so existing rows populate
-- without rewrite. faction_type stays a bare TEXT (no CHECK) so the org/warband
-- vocabulary (§4.1: temple, syndicate, mercenary_company, realm, …) extends the
-- existing dungeon values without a migration each time — the repository write
-- path validates the vocabulary instead.

-- --- Faction Framework FF-1 (§4.1: factions extend) ---
ALTER TABLE factions ADD COLUMN scope TEXT NOT NULL DEFAULT 'organization'
    CHECK(scope IN ('realm', 'organization', 'warband'));
ALTER TABLE factions ADD COLUMN realm_id TEXT REFERENCES realms(id);
ALTER TABLE factions ADD COLUMN religion_id TEXT;
ALTER TABLE factions ADD COLUMN culture_id TEXT;
ALTER TABLE factions ADD COLUMN seat_poi_id TEXT;
ALTER TABLE factions ADD COLUMN seat_settlement_id TEXT;
ALTER TABLE factions ADD COLUMN treasury_gp INTEGER NOT NULL DEFAULT 0;
ALTER TABLE factions ADD COLUMN member_count_abstract INTEGER NOT NULL DEFAULT 0;
ALTER TABLE factions ADD COLUMN power_rating INTEGER NOT NULL DEFAULT 0;
ALTER TABLE factions ADD COLUMN goal_primary TEXT;
ALTER TABLE factions ADD COLUMN goal_secondary TEXT;
ALTER TABLE factions ADD COLUMN volatility REAL NOT NULL DEFAULT 1.0;
ALTER TABLE factions ADD COLUMN is_player_founded INTEGER NOT NULL DEFAULT 0;
ALTER TABLE factions ADD COLUMN status TEXT NOT NULL DEFAULT 'active'
    CHECK(status IN ('active', 'underground', 'disbanded', 'destroyed', 'absorbed'));
ALTER TABLE factions ADD COLUMN personality_weight_biases TEXT;

CREATE INDEX IF NOT EXISTS idx_factions_scope
    ON factions(campaign_id, scope);
CREATE INDEX IF NOT EXISTS idx_factions_realm
    ON factions(realm_id);

-- --- Faction Framework FF-1 (§4.4: faction_memberships extend) ---
-- role (existing) keeps its named-post use ('leader', 'officer', …); these add
-- rank-ladder index, henchman-loyalty-style modifier (a MODIFIER, not a score),
-- merit ledger, secrecy flag, join stamp, and lifecycle status.
ALTER TABLE faction_memberships ADD COLUMN rank INTEGER NOT NULL DEFAULT 0;
ALTER TABLE faction_memberships ADD COLUMN loyalty_mod INTEGER NOT NULL DEFAULT 0;
ALTER TABLE faction_memberships ADD COLUMN standing INTEGER NOT NULL DEFAULT 0;
ALTER TABLE faction_memberships ADD COLUMN is_secret INTEGER NOT NULL DEFAULT 0;
ALTER TABLE faction_memberships ADD COLUMN joined_day INTEGER NOT NULL DEFAULT 0;
ALTER TABLE faction_memberships ADD COLUMN status TEXT NOT NULL DEFAULT 'member'
    CHECK(status IN ('petitioner', 'member', 'suspended', 'expelled', 'left', 'deceased'));
