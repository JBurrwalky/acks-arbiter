-- Migration 094: Magic item enchanting (Domain Phase 10B.1c).
--
-- Adds the `crafted_magic_items` table — a runtime-mutable catalog of magic
-- items created via the research_magic activity with project_kind='magic_item'.
-- Per Jedidiah constraint 2026-05-11 ("item enchanting needs to be able to
-- create new items to the item catalog without populating the same item to
-- shops"), this table is intentionally separate from the static
-- `data/equipment/*.json` catalog consumed by `ShopInventoryGenerator`. Shops
-- will NEVER see crafted items because they pull from the JSON catalog only.
--
-- The crafted_magic_items row IS the formula: per RAW
-- acore-campaign-general-and-magic-research.xml §formulas_and_samples L151
-- "A spellcaster automatically has a formula for any magic item he has
-- previously created." Future formula-found-as-treasure entries get their
-- own crafted_magic_items rows with the new owner as creator_character_id;
-- this duplicates template data slightly but keeps queries simple and matches
-- the "every owner has their own copy of the formula" mental model.
--
-- inventory_items rows for crafted instances use item_key='crafted:<id>' to
-- link back here. The instance row carries denormalized magical_bonus +
-- weapon_damage + armor_ac_bonus for fast queries; full effect details live
-- here.
--
-- Cost / time / target value follow RAW §magic_item_creation_table L185-215
-- and §create_magic_item L127-141. The effect_kind enum maps 1:1 to the RAW
-- table rows. weapon_plus_N / armor_plus_N entries use a separate cost
-- ladder per RAW L202-207.
--
-- Reuses 10B.1a infrastructure: magic_research_projects row (status flows
-- through in_progress → completed/failed); workshops (the FK is added on
-- the project row, not here). This table only stores the FINAL crafted
-- artifact metadata.


CREATE TABLE IF NOT EXISTS crafted_magic_items (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    -- The character who originally crafted this template. RAW: the creator
    -- automatically knows this formula. Other characters wanting to create
    -- the same item from this formula get a new crafted_magic_items row
    -- (with their character_id as creator_character_id).
    creator_character_id            TEXT    NOT NULL REFERENCES characters(id),
    name                            TEXT    NOT NULL,
    item_category                   TEXT    NOT NULL DEFAULT 'wondrous'
        CHECK(item_category IN (
            'weapon', 'armor', 'shield',
            'scroll', 'potion',
            'wand', 'rod', 'staff', 'ring', 'wondrous'
        )),
    -- For weapon_plus_N / armor_plus_N enchantments, the base item key from
    -- data/equipment/*.json (e.g. 'sword', 'plate_armor'). Empty for items
    -- without a mundane base (scrolls, potions, rings, etc.).
    base_item_key                   TEXT    NOT NULL DEFAULT '',
    effect_kind                     TEXT    NOT NULL DEFAULT 'one_use'
        CHECK(effect_kind IN (
            'one_use',
            'charged',
            'permanent_unlimited',
            'permanent_per_turn',
            'permanent_per_3_turns',
            'permanent_per_hour',
            'permanent_3_per_day',
            'permanent_per_day',
            'permanent_per_week',
            'weapon_plus_1', 'weapon_plus_2', 'weapon_plus_3',
            'armor_plus_1',  'armor_plus_2',  'armor_plus_3'
        )),
    primary_spell_key               TEXT    NOT NULL DEFAULT '',
    primary_spell_level             INTEGER NOT NULL DEFAULT 0
        CHECK(primary_spell_level >= 0),
    -- Multiple spell effects on a single item (RAW L136 "If multiple effects
    -- are enchanted, roll separately for each effect"). v1 stores them as a
    -- JSON array of spell_keys for documentation; mechanically v1 only
    -- supports single-effect items.
    spell_keys_json                 TEXT    NOT NULL DEFAULT '[]',
    charges_max                     INTEGER,    -- NULL for non-charged items
    charges_remaining               INTEGER,    -- NULL for non-charged items
    magical_bonus                   INTEGER NOT NULL DEFAULT 0
        CHECK(magical_bonus >= 0 AND magical_bonus <= 3),
    weapon_damage                   TEXT    NOT NULL DEFAULT '',
    armor_ac_bonus                  INTEGER NOT NULL DEFAULT 0,
    encumbrance_units               INTEGER NOT NULL DEFAULT 100,
    -- Cost breakdown. base = the RAW table cost; precious_materials = optional
    -- gem/precious-metal additions (RAW L160-163, +1 throw per 10,000gp,
    -- max equal to base_cost); special_components_xp = required XP value of
    -- monster organs/blood (RAW L165-172, in addition to base cost).
    gp_cost_base                    INTEGER NOT NULL DEFAULT 0
        CHECK(gp_cost_base >= 0),
    gp_cost_precious_materials      INTEGER NOT NULL DEFAULT 0
        CHECK(gp_cost_precious_materials >= 0),
    special_components_xp           INTEGER NOT NULL DEFAULT 0
        CHECK(special_components_xp >= 0),
    days_to_create                  INTEGER NOT NULL DEFAULT 0
        CHECK(days_to_create >= 0),
    -- Did the creator use a pre-existing formula (-50% cost/time per RAW
    -- L155)? Tracked for audit; the cost/time fields above already reflect
    -- the reduction.
    used_formula                    INTEGER NOT NULL DEFAULT 0
        CHECK(used_formula IN (0, 1)),
    workshop_id                     TEXT REFERENCES workshops(id),
    notes                           TEXT    NOT NULL DEFAULT '',
    created_calendar_day            INTEGER NOT NULL DEFAULT 0,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_crafted_magic_items_creator
    ON crafted_magic_items (creator_character_id);
CREATE INDEX IF NOT EXISTS idx_crafted_magic_items_category
    ON crafted_magic_items (item_category);
CREATE INDEX IF NOT EXISTS idx_crafted_magic_items_effect_kind
    ON crafted_magic_items (effect_kind);
