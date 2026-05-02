-- Migration 044: Familiars (Familiar proficiency entity)
--
-- A familiar is a magical animal companion bonded to a single master (PC).
-- Its body (form_key) determines AC, movement, attacks, and special abilities;
-- its derived stats (HD progression, max HP, INT, attack-as / save-as,
-- damage bonus, proficiency count) are derived from the master and cached
-- here, refreshed on master level-up or attribute change.
--
-- HD progression (per project decision documented in gdd-familiars.md §3.3):
--
--   Master L1 → 0.5 HD             attacks/saves as Normal Man (NM/0)
--   Master L2 → 1 HD               attacks/saves as Fighter L1, +1 damage
--   Master L3 → 1 HD + 2 hp        attacks/saves as Fighter L1
--   Master L4 → 2 HD               attacks/saves as Fighter L2, +2 damage
--   Master L5 → 2 HD + 2 hp        attacks/saves as Fighter L2
--   Master L6 → 3 HD               attacks/saves as Fighter L3, +3 damage
--   ...etc — each odd master level (≥3) adds a +2 hp modifier without
--   bumping the integer HD or the fighter level it attacks/saves as.
--
-- Per ACKS Core (rules/acore_proficiencies_rules_and_catalog.xml:688-700) and
-- generation/gdd-familiars.md.
--
-- The unique partial index enforces "one living familiar per master." Dead
-- familiars are kept (post-mortem and to gate the replacement-on-level-up
-- rule via bonded_at_master_level).

CREATE TABLE IF NOT EXISTS familiars (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    master_character_id TEXT NOT NULL REFERENCES characters(id),
    form_key TEXT NOT NULL,
    cosmetic_species TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    hp_current INTEGER NOT NULL DEFAULT 1,
    hp_max_cached INTEGER NOT NULL DEFAULT 1,
    -- HD progression (derived from master level)
    hd_dice INTEGER NOT NULL DEFAULT 0,             -- integer HD count (0 means ½ HD)
    hd_modifier_hp INTEGER NOT NULL DEFAULT 0,      -- +N hp modifier on odd master levels ≥3
    is_half_hd INTEGER NOT NULL DEFAULT 1 CHECK(is_half_hd IN (0, 1)),  -- only true at master L1
    -- Attack / save progression (derived from master level via HD)
    attack_save_class TEXT NOT NULL DEFAULT 'NM' CHECK(attack_save_class IN ('NM', 'fighter')),
    attack_save_level INTEGER NOT NULL DEFAULT 0,
    damage_bonus INTEGER NOT NULL DEFAULT 0,
    -- Master-mirrored stats
    int_cached INTEGER NOT NULL DEFAULT 10,
    proficiency_count_cached INTEGER NOT NULL DEFAULT 0,
    proficiencies_chosen TEXT NOT NULL DEFAULT '[]',
    -- Lifecycle
    is_alive INTEGER NOT NULL DEFAULT 1 CHECK(is_alive IN (0, 1)),
    bonded_at_master_level INTEGER NOT NULL DEFAULT 1,
    death_save_pending INTEGER NOT NULL DEFAULT 0 CHECK(death_save_pending IN (0, 1)),
    -- Position
    position_voxel_x INTEGER NOT NULL DEFAULT 0,
    position_voxel_y INTEGER NOT NULL DEFAULT 0,
    position_voxel_z INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_familiars_master
    ON familiars(master_character_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_familiars_living_per_master
    ON familiars(master_character_id) WHERE is_alive = 1;
