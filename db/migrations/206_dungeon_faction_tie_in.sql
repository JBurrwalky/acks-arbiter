-- Migration 206: Dungeon Faction Tie-In columns (Wave 3 Track B / FF-5).
-- gdd-faction-framework.md §9.1 — the additive link between a dungeon-internal
-- DungeonFaction and the strategic factions registry. Two columns, ADDED (not a
-- rewrite of migration 201, which is intentionally left untouched):
--
--   parent_faction_id — a `factions` id (realm mirror, org, or gang) this band
--                       answers to / pays / was exiled from. NULL = unlinked
--                       (allegiance_kind 'none'); an unlinked dungeon plays
--                       exactly as pre-FF-5 (§9.4, strictly additive).
--   allegiance_kind   — 'detachment' | 'tributary' | 'exile' | 'none'. Only
--                       'detachment' bands draw accountable replenishment from
--                       the parent (§9.3); 'none' is the pre-FF-5 default.
--
-- Nullable parent_faction_id round-trips as "" on the GDScript side (the record's
-- from_row/to_row use Dictionary.get with defaults, so this ADD needs no data
-- backfill — existing rows read the DEFAULTs). dungeon_factions is dungeon-CONTENT
-- (keyed on dungeon_id, no campaign_id) — purged dungeon-scoped, not campaign-direct.

ALTER TABLE dungeon_factions ADD COLUMN parent_faction_id TEXT;
ALTER TABLE dungeon_factions ADD COLUMN allegiance_kind TEXT NOT NULL DEFAULT 'none';
