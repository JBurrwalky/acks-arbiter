-- Migration 201: Dungeon Faction Generation (Wave 3 Track D).
-- gdd-dungeon-factions.md §7 output records. Dungeon-CONTENT tables (like
-- monster_groups / dungeon_rooms): keyed on dungeon_id TEXT (there is no
-- `dungeons` table — the dungeon id is carried in dungeon_entrances.dungeon_data
-- JSON), so NO FK on dungeon_id and NO campaign_id column. They are purged
-- dungeon-scoped in CampaignRepository._campaign_scope_entries() (the
-- dungeon_scoped block), NOT via _SCOPE_DIRECT_CAMPAIGN.
--
-- Room references (lair/core/patrol/frontier/contested) ride as JSON int arrays
-- of DungeonRoomData.id, matching the in-memory DungeonFaction record. Runtime
-- state (current_population, members_on_patrol, alert_state, morale) mutates
-- during play and round-trips through savegame (conventions §79 — the DB is the
-- save).
--
-- FF-5 EXTENSIBILITY (gdd-faction-framework.md §9): a later migration will ADD
-- `parent_faction_id` + `allegiance_kind` columns to dungeon_factions. The
-- record's from_row()/to_row() use Dictionary.get with defaults so that additive
-- change needs no rewrite of existing rows. Do NOT add them here.

-- --- §7.1 Faction Record ---
CREATE TABLE IF NOT EXISTS dungeon_factions (
    id                        TEXT    PRIMARY KEY,
    dungeon_id                TEXT    NOT NULL,
    dungeon_level             INTEGER NOT NULL DEFAULT 1,
    name                      TEXT    NOT NULL DEFAULT '',
    species                   TEXT    NOT NULL DEFAULT '',
    secondary_species         TEXT    NOT NULL DEFAULT '[]',   -- JSON string array
    alignment                 TEXT    NOT NULL DEFAULT 'neutral'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    faction_type              TEXT    NOT NULL DEFAULT 'tribal',
    leader_npc_id             TEXT    NOT NULL DEFAULT '',
    leader_room_id            INTEGER NOT NULL DEFAULT -1,
    leader_hd                 REAL    NOT NULL DEFAULT 0,
    starting_population       INTEGER NOT NULL DEFAULT 0,
    current_population        INTEGER NOT NULL DEFAULT 0,
    patrol_size               TEXT    NOT NULL DEFAULT '1d4',
    members_on_patrol         INTEGER NOT NULL DEFAULT 0,
    lair_room_ids             TEXT    NOT NULL DEFAULT '[]',    -- JSON int array
    core_room_ids             TEXT    NOT NULL DEFAULT '[]',    -- JSON int array
    patrol_room_ids           TEXT    NOT NULL DEFAULT '[]',    -- JSON int array
    frontier_room_ids         TEXT    NOT NULL DEFAULT '[]',    -- JSON int array
    alert_state               TEXT    NOT NULL DEFAULT 'unaware'
        CHECK(alert_state IN ('unaware', 'cautious', 'alerted', 'mobilized')),
    default_reaction_modifier INTEGER NOT NULL DEFAULT 0,
    personality_weight_biases TEXT    NOT NULL DEFAULT '{}',    -- JSON twelve-axis dict
    morale_modifier           INTEGER NOT NULL DEFAULT 0,
    population_loss_percent    REAL    NOT NULL DEFAULT 0,
    created_at                TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_dungeon_factions_dungeon
    ON dungeon_factions(dungeon_id);

-- --- §7.3 Faction Relationship Record ---
-- One row per unordered pair. For 'vassal', faction_a is the MASTER.
CREATE TABLE IF NOT EXISTS dungeon_faction_relationships (
    id                 TEXT PRIMARY KEY,
    dungeon_id         TEXT NOT NULL,
    faction_a_id       TEXT NOT NULL,
    faction_b_id       TEXT NOT NULL,
    relationship       TEXT NOT NULL DEFAULT 'neutral'
        CHECK(relationship IN ('allied', 'neutral', 'rival', 'hostile', 'vassal', 'unaware')),
    contested_room_ids TEXT NOT NULL DEFAULT '[]',              -- JSON int array
    notes              TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_dungeon_faction_rel_dungeon
    ON dungeon_faction_relationships(dungeon_id);
CREATE INDEX IF NOT EXISTS idx_dungeon_faction_rel_pair
    ON dungeon_faction_relationships(faction_a_id, faction_b_id);

-- --- §7.2 Solitary Threat Record ---
CREATE TABLE IF NOT EXISTS dungeon_solitary_threats (
    id               TEXT    PRIMARY KEY,
    dungeon_id       TEXT    NOT NULL,
    dungeon_level    INTEGER NOT NULL DEFAULT 1,
    room_id          INTEGER NOT NULL DEFAULT -1,
    monster_type     TEXT    NOT NULL DEFAULT '',
    hd               REAL    NOT NULL DEFAULT 0,
    alignment        TEXT    NOT NULL DEFAULT 'neutral',
    territory_radius INTEGER NOT NULL DEFAULT 1,
    tribute_from     TEXT    NOT NULL DEFAULT '[]',              -- JSON string array of faction ids
    notes            TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_dungeon_solitary_threats_dungeon
    ON dungeon_solitary_threats(dungeon_id);
