-- Migration 093: Magical Research block (Domain Phase 10B.1a).
--
-- Tables backing the arcane-caster + Lightblessed Wonderworker surface
-- (Mage / Warlock / Witch / Elven Courtier / Elven Enchanter / Elven
-- Spellsword / Elven Nightblade / Darkblood Ruinguard / Lightblessed
-- Wonderworker, plus Faith-stack casters with full spell_research per
-- Q11). RAW citations to acore-campaign-general-and-magic-research.xml
-- §research_throw + §library + §workshop, ax_campaign_play.xml
-- §magical_research category, and acore-campaign-hijinks.xml §sanctum.
--
-- Q15 (wave-split, 2026-05-11): 10B.1a ships schema + repo + UI shell
-- only; activity handlers ship in 10B.1b/c/d/e/f/g.
-- Q16 (research_magic UI, 2026-05-11): block exposes separate launcher
-- cards per target type (spell/item/construct/monster) but the backend
-- `research_magic` activity row stays unified.
-- Q20 (aspirant promotion, 2026-05-11): SCRAPS the prior 1d6/month-for-
-- 6-months attrition mechanic. New rule: every aspirant rolls a single
-- d20 + ability_mod throw at joined_calendar_day + 120 (4 months ~=
-- average 1d6 months); 14+ promotes to 1st level of intended_class,
-- <14 departs. Applies UNIVERSALLY to all sanctum aspirants (standard
-- Mage + Lightblessed).
-- Q22 (library/workshop construction, 2026-05-11): libraries/workshops
-- are sub-structures of existing strongholds (sanctum / tower
-- archetypes). They reference strongholds.id; no separate construction
-- activity needed. Sub-structure expansion (Keeps, Curtain Walls, etc.)
-- is a future stronghold-system task.
-- Q25 (apprentice/aspirant data model, 2026-05-11): NEW `followers`
-- table replaces the prior "characters with character_type='henchman'"
-- pattern for bard recruits + aspirants + class-attracted followers.
-- Per Jedidiah: followers are "almost-henchmen but not quite the same
-- thing — they gain XP as henchmen if brought on adventures, must be
-- given treasure shares like henchmen if brought on adventures, but
-- not if left behind at the stronghold. If henchman slots are
-- available they may be promoted to henchman without a hiring reaction
-- roll."
--
-- Q25a (retro migration, 2026-05-11): Phase 10A.3's solicit_followers
-- handler is rewritten in the same wave to insert into `followers`
-- instead of `characters`. No data move required (no campaigns have
-- bard-recruit rows yet at the time of this migration).


-- magic_research_projects: in-progress research projects.
--
-- project_kind discriminates the target (RAW collapses all four into
-- the single `research_magic` activity per ax_campaign_play.xml
-- §research_magic L732-792, but the cost / time / completion semantics
-- diverge by target).
--   * spell      — research a new arcane spell. target_spell_key /
--                  target_spell_level set. On completion: insert row
--                  into character_repertoire (mage) or character_
--                  spellbook (other).
--   * magic_item — research a potion, scroll, or permanent magic item.
--                  target_item_kind set. On completion: insert row into
--                  inventory_items.
--   * construct  — research a permanent construct (skeleton, zombie,
--                  animated object, golem). target_item_kind names the
--                  construct type. On completion: insert row into
--                  followers OR a new construct registry (TBD 10B.1e).
--   * monster    — cross-breeding / monster-from-scratch (deferred per
--                  Q19 to 10B.1f or v1.1).
--
-- Cost / time: per acore-campaign-general-and-magic-research.xml the
-- caster commits gp_committed at the start; days_total is computed
-- from formula at launch and frozen on the row; days_completed advances
-- monthly during the domain tick.
--
-- target_value: the research-throw target the caster must meet on
-- completion (computed at launch from caster_level + spell_level +
-- magical_engineering_rank per RAW table).
--
-- library_id / workshop_id: nullable — research can proceed without an
-- on-site library/workshop but at a penalty / level cap.
CREATE TABLE IF NOT EXISTS magic_research_projects (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    character_id                TEXT    NOT NULL REFERENCES characters(id),
    project_kind                TEXT    NOT NULL DEFAULT 'spell'
        CHECK(project_kind IN ('spell', 'magic_item', 'construct', 'monster')),
    target_spell_key            TEXT    NOT NULL DEFAULT '',
    target_spell_level          INTEGER NOT NULL DEFAULT 0,
    target_item_kind            TEXT    NOT NULL DEFAULT '',
    gp_committed                INTEGER NOT NULL DEFAULT 0
        CHECK(gp_committed >= 0),
    days_total                  INTEGER NOT NULL DEFAULT 0
        CHECK(days_total >= 0),
    days_completed              INTEGER NOT NULL DEFAULT 0
        CHECK(days_completed >= 0),
    target_value                INTEGER NOT NULL DEFAULT 18
        CHECK(target_value BETWEEN 3 AND 30),
    library_id                  TEXT REFERENCES libraries(id),
    workshop_id                 TEXT REFERENCES workshops(id),
    status                      TEXT    NOT NULL DEFAULT 'in_progress'
        CHECK(status IN ('in_progress', 'completed', 'abandoned', 'failed')),
    started_calendar_day        INTEGER NOT NULL DEFAULT 0,
    completed_calendar_day      INTEGER,
    params_json                 TEXT    NOT NULL DEFAULT '{}',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_magic_research_projects_character
    ON magic_research_projects (character_id);
CREATE INDEX IF NOT EXISTS idx_magic_research_projects_status
    ON magic_research_projects (status);


-- libraries: physical research libraries (sub-structure of a sanctum
-- or other stronghold archetype). Reused via stronghold_id FK; the
-- structure_kind discriminates which sub-structure within the stronghold.
--
-- gp_invested governs max_spell_level_supported and
-- magic_research_throw_bonus per RAW tables in
-- acore-campaign-general-and-magic-research.xml §library_value_levels
-- (e.g., a 50,000 gp library supports up to level 6 spells and grants
-- a +1 bonus to research throws). The actual lookup is in the resolver
-- (TBD 10B.1b); the row just records the gp_invested for query.
--
-- max_spell_level_supported / magic_research_throw_bonus are denormalized
-- onto the row at construction completion so queries don't repeatedly
-- recompute the lookup. They are recomputed if gp_invested changes
-- (e.g., the caster expands the library).
CREATE TABLE IF NOT EXISTS libraries (
    id                                TEXT    PRIMARY KEY,
    campaign_id                       TEXT    NOT NULL REFERENCES campaigns(id),
    owner_character_id                TEXT    NOT NULL REFERENCES characters(id),
    stronghold_id                     TEXT REFERENCES strongholds(id),
    structure_kind                    TEXT    NOT NULL DEFAULT 'sanctum_library'
        CHECK(structure_kind IN (
            'sanctum_library', 'tower_library', 'tower_workshop_library', 'other'
        )),
    gp_invested                       INTEGER NOT NULL DEFAULT 0
        CHECK(gp_invested >= 0),
    max_spell_level_supported         INTEGER NOT NULL DEFAULT 1
        CHECK(max_spell_level_supported BETWEEN 1 AND 9),
    magic_research_throw_bonus        INTEGER NOT NULL DEFAULT 0
        CHECK(magic_research_throw_bonus BETWEEN 0 AND 4),
    status                            TEXT    NOT NULL DEFAULT 'operational'
        CHECK(status IN ('building', 'operational', 'damaged', 'destroyed')),
    created_calendar_day              INTEGER NOT NULL DEFAULT 0,
    created_at                        TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                        TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_libraries_owner       ON libraries (owner_character_id);
CREATE INDEX IF NOT EXISTS idx_libraries_stronghold  ON libraries (stronghold_id);
CREATE INDEX IF NOT EXISTS idx_libraries_status      ON libraries (status);


-- workshops: physical research workshops (sub-structure of a tower or
-- other stronghold archetype). Schema parallels libraries; the bonus
-- applies to item-creation throws specifically (RAW: workshops boost
-- enchanting throws; libraries boost spell-research throws).
CREATE TABLE IF NOT EXISTS workshops (
    id                                TEXT    PRIMARY KEY,
    campaign_id                       TEXT    NOT NULL REFERENCES campaigns(id),
    owner_character_id                TEXT    NOT NULL REFERENCES characters(id),
    stronghold_id                     TEXT REFERENCES strongholds(id),
    structure_kind                    TEXT    NOT NULL DEFAULT 'tower_workshop'
        CHECK(structure_kind IN (
            'tower_workshop', 'sanctum_workshop', 'other'
        )),
    gp_invested                       INTEGER NOT NULL DEFAULT 0
        CHECK(gp_invested >= 0),
    max_item_value_supported_gp       INTEGER NOT NULL DEFAULT 0
        CHECK(max_item_value_supported_gp >= 0),
    magic_research_throw_bonus        INTEGER NOT NULL DEFAULT 0
        CHECK(magic_research_throw_bonus BETWEEN 0 AND 4),
    status                            TEXT    NOT NULL DEFAULT 'operational'
        CHECK(status IN ('building', 'operational', 'damaged', 'destroyed')),
    created_calendar_day              INTEGER NOT NULL DEFAULT 0,
    created_at                        TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                        TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_workshops_owner       ON workshops (owner_character_id);
CREATE INDEX IF NOT EXISTS idx_workshops_stronghold  ON workshops (stronghold_id);
CREATE INDEX IF NOT EXISTS idx_workshops_status      ON workshops (status);


-- followers: a NEW persistent class of NPC — distinct from characters
-- (henchmen / PCs / generic NPCs) AND from troop_units (mass-bookkept
-- hirelings). Per Q25 [RESOLVED 2026-05-11]:
--
--   "Almost-henchmen but not quite the same thing — they gain XP as
--   henchmen if brought on adventures, must be given treasure shares
--   like henchmen if brought on adventures, but not if left behind at
--   the stronghold. If henchman slots are available they may be
--   promoted to henchman without a hiring reaction roll."
--
-- The table encompasses:
--   * Mage / cleric / witch / warlock / elven_enchanter aspirants
--     (source_kind='aspirant', level=0, intended_class set)
--   * 1st-3rd-level same-class followers (most human classes attract
--     these to their stronghold; source_kind='class_follower')
--   * 1st-level same-race NPCs (elven/dwarven non-spellcasting classes;
--     source_kind='race_follower')
--   * Bard's 1d6 1st-3rd level bard applicants from Solicit Followers
--     (source_kind='bardic_recruit'; replaces the prior Phase 10A.3
--     pattern of inserting these into characters)
--   * Future: venturer_apprentice (10B.2), syndicate_member (10B.3)
--
-- Lifecycle for aspirants (per Q20 [RESOLVED 2026-05-11]):
--   1. Created at sanctum founding with source_kind='aspirant',
--      character_class='normal_man', level=0, intended_class set
--      (e.g., 'mage' or 'cleric' for Lightblessed 50/50 split).
--   2. promotion_eligible_day = joined_calendar_day + 120 (4 months).
--   3. On promotion_eligible_day: roll d20 + INT mod (mage intent) or
--      d20 + WIS mod (cleric intent). 14+ → status='present',
--      character_class=intended_class, level=1. <14 → status=
--      'failed_promotion', departed_day=now.
--
-- Lifecycle for non-aspirants (class_follower / race_follower /
-- bardic_recruit / etc.):
--   * Created already-classed at level 1-3 (rolled at arrival).
--   * status='present' on creation.
--   * Player may promote_follower_to_henchman if henchman slots
--     available → creates a characters row with character_type=
--     'henchman', persistence_tier='named'; updates this row to
--     status='promoted_to_henchman' with promoted_to_henchman_id
--     pointing at the new characters.id.
--
-- The XP / treasure-share rules ("as henchman when on adventure, not
-- when at stronghold") are enforced by the adventure / loot resolvers
-- consulting `followers` rows joined to the active party. v1 ships
-- the table; the consumer wiring is a later wave's polish.
CREATE TABLE IF NOT EXISTS followers (
    id                        TEXT    PRIMARY KEY,
    campaign_id               TEXT    NOT NULL REFERENCES campaigns(id),
    owner_character_id        TEXT    NOT NULL REFERENCES characters(id),
    stronghold_id             TEXT REFERENCES strongholds(id),
    source_kind               TEXT    NOT NULL DEFAULT 'generic'
        CHECK(source_kind IN (
            'aspirant',           -- 0-level pre-promotion sanctum aspirant
            'class_follower',     -- 1+-level same-class follower (most human classes)
            'race_follower',      -- 1+-level same-race NPC (elf/dwarf non-casters)
            'bardic_recruit',     -- Bard L9 solicit_followers 1d6 bard applicants
            'venturer_apprentice', -- 10B.2: Venturer guildhouse apprentices
            'syndicate_member',   -- 10B.3 (provisional)
            'generic'             -- fallback
        )),
    intended_class            TEXT    NOT NULL DEFAULT ''
        CHECK(intended_class IN (
            '', 'mage', 'cleric', 'witch', 'warlock', 'elven_enchanter'
        )),
    name                      TEXT    NOT NULL,
    race                      TEXT    NOT NULL DEFAULT 'human',
    character_class           TEXT    NOT NULL DEFAULT 'normal_man',
    combat_progression        TEXT    NOT NULL DEFAULT 'fighter'
        CHECK(combat_progression IN ('fighter', 'cleric', 'thief', 'mage')),
    level                     INTEGER NOT NULL DEFAULT 0
        CHECK(level >= 0),
    xp                        INTEGER NOT NULL DEFAULT 0
        CHECK(xp >= 0),
    alignment                 TEXT    NOT NULL DEFAULT 'neutral'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    strength                  INTEGER NOT NULL DEFAULT 10,
    intelligence              INTEGER NOT NULL DEFAULT 10,
    wisdom                    INTEGER NOT NULL DEFAULT 10,
    dexterity                 INTEGER NOT NULL DEFAULT 10,
    constitution              INTEGER NOT NULL DEFAULT 10,
    charisma                  INTEGER NOT NULL DEFAULT 10,
    hp_max                    INTEGER NOT NULL DEFAULT 1,
    hp_current                INTEGER NOT NULL DEFAULT 1,
    status                    TEXT    NOT NULL DEFAULT 'present'
        CHECK(status IN (
            'aspirant_in_training',  -- pre-promotion 0-level aspirant
            'present',               -- at stronghold, available
            'on_adventure',          -- with party (treasure-share eligible)
            'departed',              -- left voluntarily
            'promoted_to_henchman',  -- transitioned to characters row
            'failed_promotion'       -- aspirant rolled <14 at month 4
        )),
    joined_calendar_day       INTEGER NOT NULL DEFAULT 0,
    promotion_eligible_day    INTEGER,    -- aspirants: joined + 120
    departed_day              INTEGER,
    promoted_to_henchman_id   TEXT REFERENCES characters(id),
    notes                     TEXT    NOT NULL DEFAULT '',
    params_json               TEXT    NOT NULL DEFAULT '{}',
    created_at                TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_followers_owner       ON followers (owner_character_id);
CREATE INDEX IF NOT EXISTS idx_followers_stronghold  ON followers (stronghold_id);
CREATE INDEX IF NOT EXISTS idx_followers_status      ON followers (status);
CREATE INDEX IF NOT EXISTS idx_followers_source_kind ON followers (source_kind);
CREATE INDEX IF NOT EXISTS idx_followers_promotion_day
    ON followers (promotion_eligible_day, status)
    WHERE status = 'aspirant_in_training';
