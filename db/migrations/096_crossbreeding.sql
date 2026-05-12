-- Migration 096: Cross-breeding (Domain Phase 10B.1f).
--
-- Per acore-campaign-general-and-magic-research.xml §crossbreeds L417-484.
-- Per Q19 [RESOLVED 2026-05-11]: v1 scope is CROSS-BREEDING only.
-- Monster-from-scratch (the full 19-step procedure in
-- rules/le_monster_creation.xml) is deferred to v1.1. The monster_types
-- taxonomy from le_monster_creation.xml is borrowed as a gap-filler — every
-- crossbreed is `fantastic` plus optionally progenitor-derived types per
-- RAW L458-459.
--
-- Three new tables mirror the construct pattern (10B.1e):
--   * laboratories — physical crossbreeding lab. Parallel to
--     libraries / workshops but for cross-breeding specifically.
--   * crossbreed_species — the species template (HD, AC, attacks, damage,
--     special abilities, alignment, types). Reusable: once the caster has
--     designed a particular crossbreed species, future creates can spawn
--     more instances of that species (future polish: cost-efficient repeat
--     creation; v1 currently always pays the full cost).
--   * crossbreed_instances — actual creatures in the world. FK to
--     crossbreed_species.
--
-- v1 simplification: design + create combined into one research_magic
-- [monster] project. The handler creates BOTH a crossbreed_species row
-- (deduped against existing matching species) AND a crossbreed_instances
-- row on success.


-- laboratories: research-site for cross-breeding. RAW L471: "a special
-- crossbreeding laboratory worth at least the cost of the crossbreed."
-- Mirrors the libraries / workshops shape from 10B.1a/c. Bonus per RAW L476:
-- +1 throw per 10,000gp above the minimum, capped at +3.
CREATE TABLE IF NOT EXISTS laboratories (
    id                                TEXT    PRIMARY KEY,
    campaign_id                       TEXT    NOT NULL REFERENCES campaigns(id),
    owner_character_id                TEXT    NOT NULL REFERENCES characters(id),
    stronghold_id                     TEXT REFERENCES strongholds(id),
    structure_kind                    TEXT    NOT NULL DEFAULT 'crossbreeding_laboratory'
        CHECK(structure_kind IN (
            'crossbreeding_laboratory', 'sanctum_laboratory', 'tower_laboratory', 'other'
        )),
    gp_invested                       INTEGER NOT NULL DEFAULT 0
        CHECK(gp_invested >= 0),
    max_crossbreed_cost_gp            INTEGER NOT NULL DEFAULT 0
        CHECK(max_crossbreed_cost_gp >= 0),
    magic_research_throw_bonus        INTEGER NOT NULL DEFAULT 0
        CHECK(magic_research_throw_bonus BETWEEN 0 AND 4),
    status                            TEXT    NOT NULL DEFAULT 'operational'
        CHECK(status IN ('building', 'operational', 'damaged', 'destroyed')),
    created_calendar_day              INTEGER NOT NULL DEFAULT 0,
    created_at                        TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                        TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_laboratories_owner      ON laboratories (owner_character_id);
CREATE INDEX IF NOT EXISTS idx_laboratories_stronghold ON laboratories (stronghold_id);
CREATE INDEX IF NOT EXISTS idx_laboratories_status     ON laboratories (status);


-- crossbreed_species: the design template. One row per unique crossbreed
-- design. Future polish: spawn extra instances from an existing species
-- without re-paying the design cost (currently v1 charges full cost per
-- create + dedupes the species row).
--
-- Progenitor info is captured as descriptive strings for v1 since we
-- don't yet integrate with a full monster registry. Future polish:
-- progenitor_a_monster_key + progenitor_b_monster_key with MonsterRegistry
-- lookup for stat inheritance.
--
-- types_json: JSON array of monster type strings (per
-- le_monster_creation.xml type taxonomy). RAW: every crossbreed has
-- 'fantastic' plus optionally beastman/enchanted_creature/giant_humanoid/
-- humanoid/ooze/vermin per progenitors.
CREATE TABLE IF NOT EXISTS crossbreed_species (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    creator_character_id        TEXT    NOT NULL REFERENCES characters(id),
    name                        TEXT    NOT NULL,
    progenitor_a_name           TEXT    NOT NULL DEFAULT '',
    progenitor_b_name           TEXT    NOT NULL DEFAULT '',
    progenitor_a_hd             INTEGER NOT NULL DEFAULT 1
        CHECK(progenitor_a_hd >= 1),
    progenitor_b_hd             INTEGER NOT NULL DEFAULT 1
        CHECK(progenitor_b_hd >= 1),
    progenitor_a_alignment      TEXT    NOT NULL DEFAULT 'neutral'
        CHECK(progenitor_a_alignment IN ('lawful', 'neutral', 'chaotic')),
    progenitor_b_alignment      TEXT    NOT NULL DEFAULT 'neutral'
        CHECK(progenitor_b_alignment IN ('lawful', 'neutral', 'chaotic')),
    -- Finalized crossbreed stats (chosen by creator within design rules).
    hit_dice                    INTEGER NOT NULL DEFAULT 1
        CHECK(hit_dice >= 1),
    armor_class                 INTEGER NOT NULL DEFAULT 0
        CHECK(armor_class >= 0),
    attacks_per_round           INTEGER NOT NULL DEFAULT 1
        CHECK(attacks_per_round BETWEEN 1 AND 6),
    max_damage_per_round        INTEGER NOT NULL DEFAULT 1
        CHECK(max_damage_per_round >= 1),
    damage_expression           TEXT    NOT NULL DEFAULT '1d6',
    morale                      INTEGER NOT NULL DEFAULT 0,
    movement_kind               TEXT    NOT NULL DEFAULT 'progenitor_a'
        CHECK(movement_kind IN ('progenitor_a', 'progenitor_b', 'both')),
    special_abilities_json      TEXT    NOT NULL DEFAULT '[]',
    -- Crossbreed's derived alignment per RAW L430-432.
    alignment                   TEXT    NOT NULL DEFAULT 'neutral'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    -- Types per le_monster_creation taxonomy (gap-filler). Always includes
    -- 'fantastic' per RAW L458; may additionally include progenitor types.
    types_json                  TEXT    NOT NULL DEFAULT '["fantastic"]',
    gp_cost_total               INTEGER NOT NULL DEFAULT 0
        CHECK(gp_cost_total >= 0),
    days_to_create              INTEGER NOT NULL DEFAULT 0
        CHECK(days_to_create >= 0),
    laboratory_id               TEXT REFERENCES laboratories(id),
    designed_calendar_day       INTEGER NOT NULL DEFAULT 0,
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_crossbreed_species_creator
    ON crossbreed_species (creator_character_id);
CREATE INDEX IF NOT EXISTS idx_crossbreed_species_hd
    ON crossbreed_species (hit_dice);


-- crossbreed_instances: actual creatures created from a species. FK to
-- crossbreed_species. v1 each instance is one creature; the creator owns
-- it by default.
--
-- Control rules per RAW L479-483:
--   * Newly created crossbreed is NOT automatically under the caster's
--     control.
--   * If the more intelligent progenitor was intelligent AND willingly
--     participated, the crossbreed retains that progenitor's relationship.
--   * Otherwise, the Judge makes a reaction roll. v1: handler captures
--     the initial reaction (friendly/neutral/hostile) as a row column;
--     full reaction-roll resolution is a future polish.
CREATE TABLE IF NOT EXISTS crossbreed_instances (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    species_id                  TEXT    NOT NULL REFERENCES crossbreed_species(id),
    creator_character_id        TEXT    NOT NULL REFERENCES characters(id),
    owner_character_id          TEXT REFERENCES characters(id),
    name                        TEXT    NOT NULL,
    hp_max                      INTEGER NOT NULL DEFAULT 1
        CHECK(hp_max >= 1),
    hp_current                  INTEGER NOT NULL DEFAULT 1,
    location_kind               TEXT    NOT NULL DEFAULT 'stronghold'
        CHECK(location_kind IN ('stronghold', 'with_owner', 'wilderness_hex', 'dungeon_room', 'laboratory', 'other')),
    location_ref                TEXT    NOT NULL DEFAULT '',
    laboratory_id               TEXT REFERENCES laboratories(id),
    -- Reaction at birth per RAW L479-483. NULL = not yet resolved. SQLite
    -- CHECK only fires on explicit false, so NULL passes the IN-list check
    -- without needing to enumerate NULL.
    initial_reaction            TEXT
        CHECK(initial_reaction IS NULL OR initial_reaction IN ('hostile', 'unfriendly', 'neutral', 'friendly', 'helpful')),
    status                      TEXT    NOT NULL DEFAULT 'alive'
        CHECK(status IN ('alive', 'escaped', 'killed', 'controlled')),
    gp_cost_total               INTEGER NOT NULL DEFAULT 0,
    days_to_create              INTEGER NOT NULL DEFAULT 0,
    created_calendar_day        INTEGER NOT NULL DEFAULT 0,
    killed_calendar_day         INTEGER,
    notes                       TEXT    NOT NULL DEFAULT '',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_crossbreed_instances_creator
    ON crossbreed_instances (creator_character_id);
CREATE INDEX IF NOT EXISTS idx_crossbreed_instances_species
    ON crossbreed_instances (species_id);
CREATE INDEX IF NOT EXISTS idx_crossbreed_instances_status
    ON crossbreed_instances (status);
