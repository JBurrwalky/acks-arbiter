-- Migration 010: Add container_id to inventory_items for ACKS container tracking.
--
-- Items stored inside a container (backpack, sack, pouch) have container_id set to
-- the inventory_items.id of the container item itself.
-- Empty string = item is not inside a container (carried loose or equipped directly).

ALTER TABLE inventory_items ADD COLUMN container_id TEXT NOT NULL DEFAULT '';
