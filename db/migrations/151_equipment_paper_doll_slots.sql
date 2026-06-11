-- Migration 151: Equipment paper-doll slots (gdd-character-tab.md v1.6 §3.4).
--
-- Adds eight new paper-doll slots to the inventory_items.slot CHECK:
--   neck, arms, armor, torso_clothing, legs_clothing, ring_l, ring_r, quiver
-- and REPURPOSES the old unified 'body' slot. Previously 'body' held BOTH a
-- character's clothing AND their armor (mutually exclusive — the bug this GDD
-- fixes). In the new model:
--   * PC body armor      -> slot 'armor'          (coexists with clothing)
--   * PC torso clothing  -> slot 'torso_clothing' (coexists with armor)
--   * creature barding   -> slot 'body'           (RETAINED; CreatureEquipmentService
--                                                   still routes barding to 'body')
-- 'accessory_1'..'accessory_5' are retained in the CHECK for back-compat but are
-- no longer surfaced by the paper-doll UI; equipped holy symbols migrate to the
-- new 'neck' slot and any other equipped accessory is unequipped to the pack.
--
-- SQLite cannot ALTER a CHECK constraint, so we rebuild the table (mirrors
-- migrations 011 / 013 / 117). The CREATE TABLE below is a verbatim copy of the
-- current inventory_items definition in db/schema.sql with the expanded slot
-- CHECK; column order is preserved so `INSERT ... SELECT *` round-trips cleanly.
--
-- `legacy_alter_table = ON` is REQUIRED: in modern SQLite (godot-sqlite default,
-- legacy OFF) `ALTER TABLE … RENAME` auto-rewrites FK references in OTHER tables
-- to point at the renamed table. `location_caches.container_item_id REFERENCES
-- inventory_items(id)` (migration 032) would be rewritten to
-- `inventory_items_old`, which we then DROP — breaking the FK and failing every
-- subsequent location_caches / savegame-restore INSERT. legacy mode keeps that
-- reference pointing at `inventory_items`, which resolves to the new table.
-- (Migrations 011/013 predate the location_caches FK, so they didn't need this;
-- migration 117 documents the same hazard.)

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

ALTER TABLE inventory_items RENAME TO inventory_items_old;

CREATE TABLE inventory_items (
    id TEXT PRIMARY KEY,
    character_id TEXT NOT NULL REFERENCES characters(id),
    item_key TEXT NOT NULL,
    name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    encumbrance_units INTEGER NOT NULL DEFAULT 0,
    slot TEXT NOT NULL DEFAULT 'pack'
        CHECK(slot IN (
            'hands_main', 'hands_off',
            'head', 'neck', 'arms', 'armor',
            'torso_clothing', 'legs_clothing',
            'belt', 'feet', 'hands_worn', 'cloak',
            'ring_l', 'ring_r', 'quiver',
            -- Legacy / creature barding ('body') + legacy accessory slots,
            -- retained so existing rows never violate the constraint.
            'body',
            'accessory_1', 'accessory_2', 'accessory_3', 'accessory_4', 'accessory_5',
            'pack', 'mount'
        )),
    is_equipped INTEGER NOT NULL DEFAULT 0 CHECK(is_equipped IN (0, 1)),
    notes TEXT NOT NULL DEFAULT '',
    item_category TEXT NOT NULL DEFAULT 'gear',
    is_magical INTEGER NOT NULL DEFAULT 0,
    magical_bonus INTEGER NOT NULL DEFAULT 0,
    weapon_damage TEXT NOT NULL DEFAULT '',
    armor_ac_bonus INTEGER NOT NULL DEFAULT 0,
    is_heavy INTEGER NOT NULL DEFAULT 0,
    damage_type TEXT NOT NULL DEFAULT 'physical',
    material TEXT NOT NULL DEFAULT '',
    container_id TEXT NOT NULL DEFAULT '',
    uses_remaining INTEGER NOT NULL DEFAULT -1,
    party_id TEXT REFERENCES parties(id) DEFAULT NULL,
    creature_id TEXT REFERENCES trained_creatures(id) DEFAULT NULL,
    vehicle_id TEXT REFERENCES draft_vehicles(id) DEFAULT NULL,
    location_cache_id TEXT REFERENCES location_caches(id) ON DELETE CASCADE DEFAULT NULL,
    value_cp INTEGER NOT NULL DEFAULT -1,
    is_cursed INTEGER NOT NULL DEFAULT 0 CHECK(is_cursed IN (0, 1)),
    is_locked INTEGER NOT NULL DEFAULT 0 CHECK(is_locked IN (0, 1)),
    is_trapped INTEGER NOT NULL DEFAULT 0 CHECK(is_trapped IN (0, 1)),
    is_extradimensional INTEGER NOT NULL DEFAULT 0 CHECK(is_extradimensional IN (0, 1)),
    devouring_at_turn INTEGER NOT NULL DEFAULT -1,
    capacity_units INTEGER NOT NULL DEFAULT 0,
    consumable_units_remaining INTEGER NOT NULL DEFAULT -1
);

INSERT INTO inventory_items SELECT * FROM inventory_items_old;

DROP TABLE inventory_items_old;

-- ---------------------------------------------------------------------------
-- Data migration: move existing equipped rows off the unified 'body' slot and
-- off the legacy accessory slots into the new paper-doll slots.
-- ---------------------------------------------------------------------------

-- Equipped armor that lived in 'body' -> dedicated 'armor' slot.
-- (Creature barding has item_category 'barding', so it is untouched and stays
-- in 'body', which CreatureEquipmentService still expects.)
UPDATE inventory_items
    SET slot = 'armor'
    WHERE slot = 'body' AND is_equipped = 1 AND item_category = 'armor';

-- Equipped body clothing that lived in 'body' -> 'torso_clothing'.
UPDATE inventory_items
    SET slot = 'torso_clothing'
    WHERE slot = 'body' AND is_equipped = 1 AND item_category = 'clothing';

-- Equipped holy symbols on an accessory slot -> 'neck' (amulet/holy-symbol slot).
UPDATE inventory_items
    SET slot = 'neck'
    WHERE slot LIKE 'accessory_%' AND is_equipped = 1 AND item_key = 'holy_symbol';

-- Any remaining equipped accessory item (tools, etc.) has no paper-doll home;
-- unequip it back to the pack so it stays in inventory and is not orphaned in a
-- slot the UI no longer renders.
UPDATE inventory_items
    SET slot = 'pack', is_equipped = 0
    WHERE slot LIKE 'accessory_%' AND is_equipped = 1;

COMMIT;

PRAGMA legacy_alter_table = OFF;
PRAGMA foreign_keys = ON;
