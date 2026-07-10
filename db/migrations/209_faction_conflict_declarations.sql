-- Migration 209: organization allegiance-declaration ledger (idempotency guard).
-- Review fix (Wave 3 FF-4, gdd-faction-framework.md §7.3). FactionAI.declare_stance
-- had NO once-per-conflict guard: an org exposed to a launched rebellion re-ran
-- AllegianceEvaluator.evaluate + apply_decision EVERY monthly batch — re-emitting
-- allegiance_declared and re-arming the betrayal condition each month, and (after a
-- betrayal fired) re-feigning + re-arming the SAME condition so one betrayal could
-- fire repeatedly. This ledger records the one allegiance decision an org makes per
-- conflict (mirrors the dungeon path's dungeon_link_conflict_passes, migration 207).
-- Campaign-scoped (registered in CampaignRepository._SCOPE_DIRECT_CAMPAIGN).

CREATE TABLE IF NOT EXISTS faction_conflict_declarations (
    campaign_id   TEXT    NOT NULL,
    faction_id    TEXT    NOT NULL,
    conflict_id   TEXT    NOT NULL,
    decision      TEXT    NOT NULL DEFAULT '',   -- the AllegianceEvaluator decision recorded
    declared_day  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (faction_id, conflict_id)
);
CREATE INDEX IF NOT EXISTS idx_faction_conflict_declarations_campaign
    ON faction_conflict_declarations(campaign_id);
