-- Migration 001: Initial schema
-- Creates all Tier 1 tables: campaigns, characters, parties, party_members,
-- character_conditions, character_proficiencies, inventory_items, character_spells,
-- hex_maps, hex_cells, domains.

CREATE TABLE IF NOT EXISTS campaigns (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    world_name TEXT NOT NULL DEFAULT '',
    calendar_day INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1))
);

CREATE TABLE IF NOT EXISTS characters (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    name TEXT NOT NULL,
    character_type TEXT NOT NULL DEFAULT 'pc'
        CHECK(character_type IN ('pc', 'henchman', 'npc')),
    persistence_tier TEXT NOT NULL DEFAULT 'full'
        CHECK(persistence_tier IN ('full', 'named', 'transient')),
    race TEXT NOT NULL DEFAULT 'human',
    character_class TEXT NOT NULL DEFAULT 'fighter',
    level INTEGER NOT NULL DEFAULT 1,
    xp INTEGER NOT NULL DEFAULT 0,
    -- Four ACKS 1e combat progression types. "crusader" is ACKS II only.
    combat_progression TEXT NOT NULL DEFAULT 'fighter'
        CHECK(combat_progression IN ('fighter', 'cleric', 'thief', 'mage')),
    strength INTEGER NOT NULL DEFAULT 10,
    intelligence INTEGER NOT NULL DEFAULT 10,
    wisdom INTEGER NOT NULL DEFAULT 10,
    dexterity INTEGER NOT NULL DEFAULT 10,
    constitution INTEGER NOT NULL DEFAULT 10,
    charisma INTEGER NOT NULL DEFAULT 10,
    hp_max INTEGER NOT NULL DEFAULT 1,
    hp_current INTEGER NOT NULL DEFAULT 1,
    armor_class INTEGER NOT NULL DEFAULT 0,
    attack_throw INTEGER NOT NULL DEFAULT 10,
    is_dead INTEGER NOT NULL DEFAULT 0 CHECK(is_dead IN (0, 1)),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    employer_id TEXT REFERENCES characters(id),
    loyalty_score INTEGER,
    wage_gp_per_month INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS parties (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    name TEXT NOT NULL DEFAULT 'The Party',
    current_map_id TEXT,
    current_hex_q INTEGER,
    current_hex_r INTEGER,
    current_location_type TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(current_location_type IN ('wilderness', 'dungeon', 'settlement', 'sea')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS party_members (
    party_id TEXT NOT NULL REFERENCES parties(id),
    character_id TEXT NOT NULL REFERENCES characters(id),
    formation_slot TEXT NOT NULL DEFAULT 'middle'
        CHECK(formation_slot IN ('point', 'front', 'middle', 'rear')),
    joined_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (party_id, character_id)
);

CREATE TABLE IF NOT EXISTS character_conditions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id TEXT NOT NULL REFERENCES characters(id),
    condition_name TEXT NOT NULL,
    applied_at_round INTEGER,
    expires_at_round INTEGER,
    source_id TEXT
);

CREATE TABLE IF NOT EXISTS character_proficiencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id TEXT NOT NULL REFERENCES characters(id),
    proficiency_key TEXT NOT NULL,
    rank INTEGER NOT NULL DEFAULT 1,
    slot_type TEXT NOT NULL DEFAULT 'general'
        CHECK(slot_type IN ('class', 'general'))
);

-- encumbrance_sixths: weight in 1/6-stone units (1 stone = 6 units = ~10 lbs)
-- Examples: dagger=1, sword=6, plate armour=30, heavy warhorse=120
CREATE TABLE IF NOT EXISTS inventory_items (
    id TEXT PRIMARY KEY,
    character_id TEXT NOT NULL REFERENCES characters(id),
    item_key TEXT NOT NULL,
    name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    encumbrance_sixths INTEGER NOT NULL DEFAULT 0,
    slot TEXT NOT NULL DEFAULT 'pack'
        CHECK(slot IN ('hands_main', 'hands_off', 'body', 'head', 'belt', 'pack', 'mount')),
    is_equipped INTEGER NOT NULL DEFAULT 0 CHECK(is_equipped IN (0, 1)),
    notes TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS character_spells (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id TEXT NOT NULL REFERENCES characters(id),
    spell_key TEXT NOT NULL,
    spell_level INTEGER NOT NULL,
    is_memorized INTEGER NOT NULL DEFAULT 0 CHECK(is_memorized IN (0, 1)),
    is_in_repertoire INTEGER NOT NULL DEFAULT 1 CHECK(is_in_repertoire IN (0, 1)),
    memorized_slots INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS hex_maps (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    name TEXT NOT NULL,
    scale TEXT NOT NULL CHECK(scale IN ('campaign_24mi', 'regional_6mi', 'local_15mi')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- fog_state is per-campaign (scoped through hex_maps.campaign_id)
CREATE TABLE IF NOT EXISTS hex_cells (
    map_id TEXT NOT NULL REFERENCES hex_maps(id),
    q INTEGER NOT NULL,
    r INTEGER NOT NULL,
    elevation TEXT NOT NULL DEFAULT 'flat'
        CHECK(elevation IN ('flat', 'hills', 'mountains')),
    biome TEXT NOT NULL DEFAULT 'clear'
        CHECK(biome IN ('clear', 'woods', 'jungle', 'swamp', 'desert')),
    water TEXT NOT NULL DEFAULT ''
        CHECK(water IN ('', 'river', 'ocean')),
    civilization TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(civilization IN ('civilized', 'borderlands', 'wilderness')),
    has_city INTEGER NOT NULL DEFAULT 0 CHECK(has_city IN (0, 1)),
    original_biome TEXT NOT NULL DEFAULT '',
    fog_state TEXT NOT NULL DEFAULT 'hidden'
        CHECK(fog_state IN ('hidden', 'explored', 'visible')),
    PRIMARY KEY (map_id, q, r)
);

CREATE TABLE IF NOT EXISTS domains (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    name TEXT NOT NULL,
    owner_character_id TEXT REFERENCES characters(id),
    location_map_id TEXT REFERENCES hex_maps(id),
    location_hex_q INTEGER,
    location_hex_r INTEGER,
    -- Three ACKS territory classifications only
    territory_type TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(territory_type IN ('civilized', 'borderlands', 'wilderness')),
    urban_families INTEGER NOT NULL DEFAULT 0,
    peasant_families INTEGER NOT NULL DEFAULT 0,
    morale INTEGER NOT NULL DEFAULT 0,
    garrison_troops INTEGER NOT NULL DEFAULT 0,
    revenue_gp INTEGER NOT NULL DEFAULT 0,
    expenses_gp INTEGER NOT NULL DEFAULT 0,
    net_income_gp INTEGER NOT NULL DEFAULT 0,
    domain_xp_this_month INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
