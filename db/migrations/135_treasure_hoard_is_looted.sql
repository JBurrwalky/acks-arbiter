-- Migration 135: runtime loot-consumption flag for treasure hoards.
-- 0 = not yet looted (default); 1 = the party has claimed this hoard.
-- Lets the dungeon loot flow (TreasureLootService.claim_room_hoards) avoid
-- handing out the same room's treasure twice across visits.
-- Non-destructive single-column ADD COLUMN (pattern of migrations 012 / 134).
ALTER TABLE treasure_hoards ADD COLUMN is_looted INTEGER NOT NULL DEFAULT 0;
