-- Migration 012: Add uses_remaining column for consumable tracking.
-- -1 = not a consumable (default), positive = remaining uses/turns.
-- Used for torch burn time, lantern oil, scrolls, potions, wands, etc.
ALTER TABLE inventory_items ADD COLUMN uses_remaining INTEGER NOT NULL DEFAULT -1;
