-- Migration 207: Dungeon link conflict-pass log (Wave 3 Track B / FF-5).
-- gdd-faction-framework.md §9.3 "Politics reaches the dungeon" + §11.3 director
-- cap: a linked detachment gets ONE allegiance-engine pass per conflict per
-- dungeon (so a war/rebellion cannot repeatedly churn the same dungeon). This
-- table is the idempotency guard for that cap — one row per (dungeon, conflict)
-- that has already had its pass.
--
-- Dungeon-CONTENT (like dungeon_factions): keyed on dungeon_id, NO campaign_id /
-- NO FK — the dungeon id lives in dungeon_entrances.dungeon_data JSON. Purged
-- dungeon-scoped in CampaignRepository._campaign_scope_entries().

CREATE TABLE IF NOT EXISTS dungeon_link_conflict_passes (
    dungeon_id   TEXT    NOT NULL,
    conflict_id  TEXT    NOT NULL,
    faction_id   TEXT    NOT NULL DEFAULT '',   -- the detachment band that passed
    decision     TEXT    NOT NULL DEFAULT '',   -- the AllegianceEvaluator decision recorded
    passed_day   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (dungeon_id, conflict_id)
);
CREATE INDEX IF NOT EXISTS idx_dungeon_link_conflict_passes_dungeon
    ON dungeon_link_conflict_passes(dungeon_id);
