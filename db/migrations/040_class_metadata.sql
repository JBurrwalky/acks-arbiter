-- Migration 040: per-character class_metadata JSON column.
--
-- Holds class-specific sub-selections that don't fit a generic schema:
--   barbarian: {"regional_origin": "jutland" | "skysostan" | "ivory_kingdoms"}
--   witch:     {"witch_tradition": "sylvan" | "voudon" | ...}
--   voudon:    {"witch_tradition": "voudon", "voudon_craft_choice": "<spec_id>"}
--
-- Used by ClassEquipRestrictionValidator to resolve the barbarian
-- `determined_by_regional_origin` weapon-permission sentinel for saved
-- characters. Existing rows default to '{}' — barbarian characters from before
-- this migration fall through the validator's permissive fallback (no
-- regression vs. prior behavior).

ALTER TABLE characters ADD COLUMN class_metadata TEXT NOT NULL DEFAULT '{}';
