-- Migration 022: Formation grid coordinates
--
-- Replaces the text-based formation_slot (point/front/middle/rear) with
-- integer grid coordinates for a 5-wide × 12-deep formation grid.
-- Row 0 is the front of the formation; column 0 is leftmost.
-- Unassigned characters use col = -1, row = -1.
--
-- The old formation_slot column is retained for backwards compatibility
-- but is no longer used by the application.

ALTER TABLE party_members ADD COLUMN formation_col INTEGER NOT NULL DEFAULT -1;
ALTER TABLE party_members ADD COLUMN formation_row INTEGER NOT NULL DEFAULT -1;

-- Remove current_mount_type from party_state — mounts are now per-character
-- equipment (mount slot). SQLite cannot drop columns, so we leave it in place
-- but the application ignores it.
