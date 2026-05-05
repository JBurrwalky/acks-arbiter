-- Migration 047: Party wilderness sustenance state (Wilderness closure Phase 1)
--
-- Adds columns to party_state for the daily wilderness loop:
--   * exhaustion_days, starvation_days, dehydration_days — penalty counters
--     incremented by wilderness_day_tick when the party fails to rest / eat /
--     drink. Reset on full rest (camp_rest_complete).
--   * water_units, ration_units — virtual sustenance counters; ration_units is
--     synced from inventory iron-rations on inventory_changed (Phase 3 wires
--     the sync; Phase 1 only creates the columns).
--   * last_day_tick_round — idempotency guard for the wilderness_day_tick
--     event so re-entering wilderness mode does not double-fire midnight.
--     -1 = never ticked (sentinel); else the absolute round when the last
--     tick fired for this party.
--
-- All values default to 0 (never-deficit) except last_day_tick_round which
-- defaults to -1 (never-ticked) so a fresh party gets its first tick on the
-- next midnight rather than skipping one.
--
-- Sustenance penalty curves and forage/hunt mechanics land in Phase 3
-- (gdd-hunting-foraging.md, sustenance_resolver.gd) per
-- acore_adventures_and_encounters.xml: 2-day food grace then 1 hp/day,
-- 1 day water then 1d4 hp + 1d4/day.

ALTER TABLE party_state ADD COLUMN exhaustion_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE party_state ADD COLUMN starvation_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE party_state ADD COLUMN dehydration_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE party_state ADD COLUMN water_units INTEGER NOT NULL DEFAULT 0;
ALTER TABLE party_state ADD COLUMN ration_units INTEGER NOT NULL DEFAULT 0;
ALTER TABLE party_state ADD COLUMN last_day_tick_round INTEGER NOT NULL DEFAULT -1;
