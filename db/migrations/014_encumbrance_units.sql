-- Migration 014: Rename encumbrance_sixths → encumbrance_units and convert values.
-- New unit: 1 encumbrance_unit = 1/1000 stone (was 1/6 stone).
-- Conversion for non-treasure items: ROUND(sixths * 1000.0 / 6.0)
--   e.g. 1 sixth → 167, 6 sixths → 1000, 36 sixths → 6000
-- Conversion for treasure items (coins/gems): always 1 unit per piece.
--   Fixes the old double-count bug: old code stored total stack weight in
--   encumbrance_sixths while the calculator multiplied by quantity again.
-- SQLite does not support ALTER COLUMN, so we rebuild the table.

PRAGMA foreign_keys = OFF;

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

INSERT INTO inventory_items (
    id, character_id, item_key, name, quantity,
    encumbrance_units,
    slot, is_equipped, notes, item_category, is_magical, magical_bonus,
    weapon_damage, armor_ac_bonus, is_heavy, damage_type, material,
    container_id, uses_remaining
)
SELECT
    id, character_id, item_key, name, quantity,
    CASE
        WHEN item_category = 'treasure'
            THEN 1
        ELSE
            CAST(ROUND(encumbrance_sixths * 1000.0 / 6.0) AS INTEGER)
    END AS encumbrance_units,
    slot, is_equipped, notes, item_category, is_magical, magical_bonus,
    weapon_damage, armor_ac_bonus, is_heavy, damage_type, material,
    container_id, uses_remaining
FROM inventory_items_old;

DROP TABLE inventory_items_old;

COMMIT;

PRAGMA foreign_keys = ON;
