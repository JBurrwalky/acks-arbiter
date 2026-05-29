-- Migration 131: Camp state + per-day encounter gate on party_state.
--
-- Per gdd-realtime-scheduler.md §4.3 (revised 2026-05-27), the camp's
-- encounter throw fires at camp_setup, gated by a per-party "did anything
-- trigger today?" flag. This migration adds the storage needed to:
--
--   * Track whether a party is currently camping (is_camping) and the camp
--     window's absolute round-times (camp_start_round, camp_end_round) so
--     the wilderness_encounter handler can compute observer state at fire
--     time regardless of which session state the party is in.
--   * Persist the watch schedule (assignments + armed sleepers) as JSON
--     blobs alongside the party_state row, so the camp's data survives the
--     state-scoped CampHandlers lifetime (they're unregistered when CampState
--     exits) and can be read by the globally-registered wilderness_encounter
--     handler.
--   * Track the hybrid-rule gate: last_encounter_trigger_day is the day_index
--     (game-round / ROUNDS_PER_DAY) on which this party most recently had a
--     wilderness encounter triggered (via travel_leg or camp). Cleared
--     implicitly when current_day_index exceeds it. Default -1 = never
--     triggered, allowing the first day's camp/travel checks to fire.
--
-- All fields are additive — no existing data path changes. PartyData.from_db
-- and to_state_dict pick the new fields up in the same migration's CL.

PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

ALTER TABLE party_state ADD COLUMN is_camping INTEGER NOT NULL DEFAULT 0
    CHECK(is_camping IN (0, 1));
ALTER TABLE party_state ADD COLUMN camp_start_round INTEGER NOT NULL DEFAULT -1;
ALTER TABLE party_state ADD COLUMN camp_end_round INTEGER NOT NULL DEFAULT -1;
ALTER TABLE party_state ADD COLUMN camp_watch_assignments_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE party_state ADD COLUMN camp_armed_sleepers_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE party_state ADD COLUMN last_encounter_trigger_day INTEGER NOT NULL DEFAULT -1;

COMMIT;

PRAGMA foreign_keys = ON;
