-- Migration 037: Extend dungeon-cell location_cache keys with voxel level axis.
-- Pre-session-9, dungeon caches were keyed "dungeon:<id>:cell:<col>,<row>".
-- Session 9 extends LocationCacheManager to Vector3i; the key format becomes
-- "dungeon:<id>:cell:<col>,<row>,<level>". Existing rows are backfilled at
-- level 0 because pre-voxel gameplay implicitly treated every dungeon as a
-- single-floor map.
--
-- Idempotent on re-run: the WHERE clause excludes rows already carrying the
-- third comma-separated axis.

BEGIN TRANSACTION;

UPDATE location_caches
SET location_key = location_key || ',0'
WHERE location_type = 'dungeon_cell'
  AND location_key LIKE 'dungeon:%:cell:%,%'
  AND location_key NOT LIKE 'dungeon:%:cell:%,%,%';

COMMIT;
