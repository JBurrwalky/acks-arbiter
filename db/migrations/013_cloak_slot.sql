-- Migration 013: Add 'cloak' slot to inventory_items CHECK constraint.
-- SQLite does not support ALTER COLUMN, so we rebuild the table.
-- This rebuild includes uses_remaining (migration 012).

PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

ALTER TABLE inventory_items RENAME TO inventory_items_old;

CREATE TABLE inventory_items (
    id TEXT PRIMARY KEY,
    character_id TEXT NOT NULL REFERENCES characters(id),
    item_key TEXT NOT NULL,
    name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    encumbrance_sixths INTEGER NOT NULL DEFAULT 0,
    slot TEXT NOT NULL DEFAULT 'pack'
        CHECK(slot IN (
            'hands_main', 'hands_off',
            'body', 'head', 'belt', 'feet', 'hands_worn', 'cloak',
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
    uses_remaining INTEGER NOT NULL DEFAULT -1
);

INSERT INTO inventory_items SELECT * FROM inventory_items_old;

DROP TABLE inventory_items_old;

COMMIT;

PRAGMA foreign_keys = ON;
