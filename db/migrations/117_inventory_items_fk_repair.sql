-- Migration 117: rebuild `inventory_items` to repair the stale FK reference
-- to `trained_creatures_old`, AND repair the same class of damage on
-- `location_caches.container_item_id` (caused by a transient
-- inventory_items_old rename in an earlier in-flight version of this
-- migration; the rebuild here makes the fix self-contained).
--
-- Root cause: SQLite's `PRAGMA legacy_alter_table = OFF` mode (modern; the
-- godot-sqlite default) makes `ALTER TABLE … RENAME TO …` automatically
-- update FK references in OTHER tables that point at the renamed table.
--
-- Migration 035 renamed trained_creatures → trained_creatures_old as part of
-- its rebuild pattern. SQLite auto-updated inventory_items.creature_id from
-- REFERENCES trained_creatures(id) to REFERENCES trained_creatures_old(id).
-- Migration 035 then DROPPED trained_creatures_old, leaving the FK pointing
-- at a now-nonexistent table. With foreign_keys enforcement on, every
-- inventory_items INSERT fails with "no such table: main.trained_creatures_old".
--
-- The fix: rebuild inventory_items with the CORRECT FK reference. To avoid
-- the same auto-update bug propagating to OTHER tables that reference
-- inventory_items (e.g., location_caches.container_item_id), we set
-- `legacy_alter_table = ON` for the duration of the rename. That keeps
-- those other FK references pointing at "inventory_items" — and when we
-- recreate inventory_items immediately after the rename, those FKs resolve
-- correctly to the new table.
--
-- We ALSO rebuild location_caches in the same transaction to repair any
-- damage already caused by a transient rename (e.g., if a previous
-- in-flight version of this migration ran without legacy_alter_table=ON).
-- This makes the migration idempotent: on a fresh DB the rebuild is a
-- pure no-op for the FK shape but corrects any drift that may have
-- accumulated. The `INSERT … SELECT` preserves every existing row.
--
-- Pattern follows Migrations 011 / 013 / 014 / 035 with the added
-- legacy_alter_table guard.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- Rebuild inventory_items with REFERENCES trained_creatures(id) on creature_id.
-- ---------------------------------------------------------------------------
ALTER TABLE inventory_items RENAME TO inventory_items_old;

CREATE TABLE inventory_items (
    id                  TEXT    PRIMARY KEY,
    character_id        TEXT    NOT NULL REFERENCES characters(id),
    item_key            TEXT    NOT NULL,
    name                TEXT    NOT NULL,
    quantity            INTEGER NOT NULL DEFAULT 1,
    encumbrance_units   INTEGER NOT NULL DEFAULT 0,
    slot                TEXT    NOT NULL DEFAULT 'pack'
        CHECK(slot IN (
            'hands_main', 'hands_off',
            'body', 'head', 'belt', 'feet', 'hands_worn', 'cloak',
            'accessory_1', 'accessory_2', 'accessory_3', 'accessory_4', 'accessory_5',
            'pack', 'mount'
        )),
    is_equipped         INTEGER NOT NULL DEFAULT 0 CHECK(is_equipped IN (0, 1)),
    notes               TEXT    NOT NULL DEFAULT '',
    item_category       TEXT    NOT NULL DEFAULT 'gear',
    is_magical          INTEGER NOT NULL DEFAULT 0,
    magical_bonus       INTEGER NOT NULL DEFAULT 0,
    weapon_damage       TEXT    NOT NULL DEFAULT '',
    armor_ac_bonus      INTEGER NOT NULL DEFAULT 0,
    is_heavy            INTEGER NOT NULL DEFAULT 0,
    damage_type         TEXT    NOT NULL DEFAULT 'physical',
    material            TEXT    NOT NULL DEFAULT '',
    container_id        TEXT    NOT NULL DEFAULT '',
    uses_remaining      INTEGER NOT NULL DEFAULT -1,
    party_id            TEXT REFERENCES parties(id) DEFAULT NULL,
    creature_id         TEXT REFERENCES trained_creatures(id) DEFAULT NULL,
    vehicle_id          TEXT REFERENCES draft_vehicles(id) DEFAULT NULL,
    location_cache_id   TEXT REFERENCES location_caches(id) ON DELETE CASCADE DEFAULT NULL
);

INSERT INTO inventory_items (
    id, character_id, item_key, name, quantity, encumbrance_units,
    slot, is_equipped, notes, item_category, is_magical, magical_bonus,
    weapon_damage, armor_ac_bonus, is_heavy, damage_type, material,
    container_id, uses_remaining, party_id, creature_id, vehicle_id,
    location_cache_id
)
SELECT
    id, character_id, item_key, name, quantity, encumbrance_units,
    slot, is_equipped, notes, item_category, is_magical, magical_bonus,
    weapon_damage, armor_ac_bonus, is_heavy, damage_type, material,
    container_id, uses_remaining, party_id, creature_id, vehicle_id,
    location_cache_id
FROM inventory_items_old;

DROP TABLE inventory_items_old;


-- ---------------------------------------------------------------------------
-- Rebuild location_caches with REFERENCES inventory_items(id) on
-- container_item_id. Self-heals any earlier in-flight Migration-117 damage
-- where this FK got auto-rewritten to inventory_items_old.
-- ---------------------------------------------------------------------------
ALTER TABLE location_caches RENAME TO location_caches_old;

CREATE TABLE location_caches (
    id                      TEXT    PRIMARY KEY,
    campaign_id             TEXT    NOT NULL REFERENCES campaigns(id),
    location_type           TEXT    NOT NULL
        CHECK(location_type IN ('hex', 'dungeon_cell', 'settlement_node')),
    location_key            TEXT    NOT NULL,
    cache_variant           TEXT    NOT NULL
        CHECK(cache_variant IN ('loose', 'locked_container', 'hidden_wilderness')),
    container_item_id       TEXT REFERENCES inventory_items(id) ON DELETE SET NULL,
    is_persistent           INTEGER NOT NULL DEFAULT 0,
    decay_check_day         INTEGER DEFAULT NULL,
    created_at_day          INTEGER NOT NULL,
    raid_monthly_modifier   INTEGER NOT NULL DEFAULT 0
);

INSERT INTO location_caches (
    id, campaign_id, location_type, location_key, cache_variant,
    container_item_id, is_persistent, decay_check_day, created_at_day,
    raid_monthly_modifier
)
SELECT
    id, campaign_id, location_type, location_key, cache_variant,
    container_item_id, is_persistent, decay_check_day, created_at_day,
    raid_monthly_modifier
FROM location_caches_old;

DROP TABLE location_caches_old;

COMMIT;

PRAGMA legacy_alter_table = OFF;
PRAGMA foreign_keys = ON;
