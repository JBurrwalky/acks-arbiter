-- Migration 178: per-hex deforestation progress (clearing_progress).
--
-- gdd-culture-emergence-and-territory.md §5.4 / docs/handoff_culture_emergence_build.md
-- Phase 2b: graduated deforestation is a TIMED cost. A forest/jungle hex being
-- developed past its §4 biome cap accrues clearing_progress per tick; on reaching
-- the step threshold the biome steps down (dense forest → forest → clear; jungle →
-- clear) and the counter resets. Natural/elven reforestation (Phase 2c) runs it back.
--
-- Per-hex scalar, 1:1 with the hex row — the natural companion to the existing
-- per-hex deforestation-state column original_biome (coding_conventions §85 / the
-- clearing model). Non-destructive ADD COLUMN with a 0 default, so existing rows
-- (and the determinism hash, which keys on SettingRepository.HEX_COLUMNS) carry the
-- new field automatically.

ALTER TABLE setting_hexes ADD COLUMN clearing_progress INTEGER NOT NULL DEFAULT 0;
