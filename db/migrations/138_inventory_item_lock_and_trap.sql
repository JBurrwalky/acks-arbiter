-- Migration 138: container-item runtime state for cell-based treasure containers.
--
-- chest / barrel / sack hoards materialize into a backing inventory_items row
-- that IS the container (Jedidiah 2026-05-29 ruling; see
-- generation/gdd-treasure-item-backing.md §15). The container's lock + trap
-- flags need to live on its inventory row so the per-cell interaction layer
-- (Commit 4 of the arc) can gate opening on Pick Lock / trap fire without
-- re-reading the source treasure_hoards row (which gets is_looted = 1 once
-- materialization completes).
--
-- Inherits the migration 137 design: the placement service's trap-fallback
-- guardrail emits is_locked = 1 + is_trapped = 0 until the traps system
-- ships; this column matches that semantic so the materializer can copy the
-- hoard's flags forward verbatim.
--
-- Non-destructive single-column ADD COLUMNs (the migration 012 / 134 / 135 /
-- 136 / 137 pattern). SQLite stamps the defaults onto every existing row in
-- place — no backfill required; all existing mundane items end up
-- is_locked = 0 / is_trapped = 0, the correct semantics for non-containers.
ALTER TABLE inventory_items ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0
    CHECK(is_locked IN (0, 1));
ALTER TABLE inventory_items ADD COLUMN is_trapped INTEGER NOT NULL DEFAULT 0
    CHECK(is_trapped IN (0, 1));
