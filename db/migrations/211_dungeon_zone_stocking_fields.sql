-- Migration 211: per-zone stocking foreign keys — dormant schema (DG-C3D.F.1).
-- gdd-dungeon-contiguous-3d.md §9.2; build plan docs/dungeon-contiguous-3d-build-plan.md
-- sub-phase F ("MonsterGroup.zone_index, KeyItem.placed_in_zone_index populated").
--
-- Additive only, zero behavior change: both columns default to -1 = "no zone"
-- (the pre-contiguous per-room stocking model — the floor-stitched generator
-- never sets them). The DG-C3D.F cutover stocks per zone and populates them.
-- No row backfills: old dungeons regenerate on next access once the generator
-- version bumps at the cutover (contiguous GDD §13 "regenerate, no migration").

-- MonsterGroupData.zone_index — the zone within the room the group stocks.
ALTER TABLE monster_groups ADD COLUMN zone_index INTEGER NOT NULL DEFAULT -1;

-- KeyItemData.placed_in_zone_index — the zone within the room holding the key.
ALTER TABLE key_items ADD COLUMN placed_in_zone_index INTEGER NOT NULL DEFAULT -1;
