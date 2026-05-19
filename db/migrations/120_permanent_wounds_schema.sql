-- Migration 120: character_permanent_wounds table.
--
-- Persists structured permanent-wound records on characters, sourced from
-- BOTH the Crime & Punishment resolver (corporal punishments per
-- acore-campaign-hijinks.xml §retribution_by_crime L325-401) AND the Mortal
-- Wounds system (ax_mortal_wounds_and_tampering.xml). Per Phase 10B.3 item
-- #6, these wounds now feed a WoundEffectAggregator that propagates the
-- mechanical effects (RAW-explicit modifiers + capability blocks) into
-- combat, social, spellcasting, and proficiency-throw resolvers.
--
-- Schema:
--   id                     PK
--   character_id           FK → characters(id)
--   wound_kind             Canonical ID (see WoundEffectAggregator.WOUND_EFFECTS).
--                          Examples: "ear_cut_off", "maimed_tongue",
--                          "one_hand_amputated", "both_hands_amputated",
--                          "branded", "whipped_scarred", "stocks_lost_teeth",
--                          "mw_bludgeoning_d6_<N>_bracket_<B>", etc.
--   source                 Provenance: "corporal_punishment:<punishment_kind>"
--                          or "mortal_wounds:<damage_type>" or "manual".
--   applied_calendar_day   When applied (absolute calendar day).
--   notes                  Free-form RAW description (e.g., the MW table cell
--                          text) for the UI tooltip.
--
-- Stacking policy: rows are append-only — multiple convictions of the same
-- punishment kind insert separate rows so the WoundEffectAggregator can sum
-- with a per-modifier-category cap (reaction modifier capped at -10 per
-- Phase 10B.3 #6 design decision).

CREATE TABLE IF NOT EXISTS character_permanent_wounds (
    id                   TEXT PRIMARY KEY,
    character_id         TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    wound_kind           TEXT NOT NULL,
    source               TEXT NOT NULL DEFAULT '',
    applied_calendar_day INTEGER NOT NULL DEFAULT 0,
    notes                TEXT NOT NULL DEFAULT '',
    created_at           TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_character_permanent_wounds_character
    ON character_permanent_wounds(character_id);
