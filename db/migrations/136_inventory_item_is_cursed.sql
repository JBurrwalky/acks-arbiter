-- Migration 136: Add is_cursed column to inventory_items.
--
-- Mirrors the catalog's `is_cursed` flag on a per-item-instance basis so the
-- equip-state path can enforce the RAW sticky rule:
--   "Cursed items cannot be discarded except by dispel evil or remove curse."
--   (acore_treasure_and_magic_items_rules.xml:235)
-- The owner doesn't know an item is cursed at the UI level (cursed items
-- masquerade as normal magic items), so equipping is unrestricted; only
-- UNEQUIPPING is blocked by CampaignRepository.update_inventory_item_equip_state.
--
-- The associated negative `magical_bonus` term (RAW :234: "A negative value is
-- cursed and applies penalties instead") already flows through the existing
-- attack/AC paths (signed arithmetic), so the math is free; this column is
-- the sticky-equip signal only.
--
-- Follows the single-column ADD COLUMN pattern of migrations 012 / 014 / 134.
-- Non-destructive: SQLite stamps the default (0 = not cursed) onto every
-- existing row in place.
ALTER TABLE inventory_items ADD COLUMN is_cursed INTEGER NOT NULL DEFAULT 0
    CHECK(is_cursed IN (0, 1));
