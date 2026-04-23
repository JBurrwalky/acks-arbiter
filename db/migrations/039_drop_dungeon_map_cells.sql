-- Migration 039: drop the legacy `dungeon_map_cells` table.
--
-- Migration 036 forward-migrated door_state / fog_state from `dungeon_map_cells`
-- into the voxel-native `voxel_map_cells` table. After the 12b cleanup sweep
-- deleted TacticalMapData and the @deprecated CampaignRepository methods
-- (save_dungeon_cell_states, load_dungeon_cell_states, update_dungeon_cell),
-- no code path reads or writes `dungeon_map_cells`. The table is orphaned.

DROP TABLE IF EXISTS dungeon_map_cells;
