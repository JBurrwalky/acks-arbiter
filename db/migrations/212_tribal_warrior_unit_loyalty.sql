-- Migration 212: per-unit Unit Loyalty carryover state on troop_units.
-- gdd-tribal-warriors.md §7.4; RAW rules/daw_armies_recruitment.xml:93-109 +
-- the Unit Loyalty table at :265-275.
--
-- RAW gives the Unit Loyalty roll two pieces of state that must survive
-- between rolls:
--
--   * Fanatic loyalty — "all future loyalty rolls are at +1" (:107). Sticky
--     once earned, so it needs a persisted flag rather than a per-roll value.
--   * Grudging loyalty — "if rolled on two consecutive morale rolls they
--     leave service" (:105). Needs a consecutive-run counter, not a boolean
--     'last roll was grudging', so the run length is auditable after the
--     fact and a test can assert the reset actually happened.
--
-- NOTE these are NOT the same semantics as henchman loyalty
-- (henchman_state.is_fanatic / is_grudging, and the vassal_assignments
-- loyalty_is_fanatic / loyalty_grudging_pending pair from migration 193).
-- Henchman loyalty gives fanatic +2 and grudging a one-shot -1 on the next
-- roll; DaW Unit Loyalty gives fanatic +1 and makes two consecutive grudging
-- results a departure. The two ladders share the same five 2d6 bands by
-- coincidence of design, not by being the same table. Do not consolidate them.
--
-- Additive only. Both columns default to 0, which is the correct state for
-- every unit minted before this migration: no fanatic bonus, no grudging run.
-- Applies to all source_types (mercenaries, conscripts, militia and followers
-- all make Unit Loyalty rolls per :353, :458 and :477) even though only
-- tribal warriors have a caller today.

ALTER TABLE troop_units ADD COLUMN loyalty_is_fanatic INTEGER NOT NULL DEFAULT 0
    CHECK(loyalty_is_fanatic IN (0, 1));

ALTER TABLE troop_units ADD COLUMN loyalty_consecutive_grudging INTEGER NOT NULL DEFAULT 0
    CHECK(loyalty_consecutive_grudging >= 0);
