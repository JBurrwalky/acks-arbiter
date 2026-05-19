-- Migration 108: rename party_visit_state.entry_toll_paid_gp → entry_toll_paid_cp.
--
-- Per the 2026-05-15 currency-precision rule: cp is the project's base
-- currency. The 107 migration created the column as `*_gp` but the column
-- has only ever been written via mark_entry_toll_paid, which now passes the
-- cp-denominated toll value. Existing values in this column are gp (×100
-- under-counted relative to the new semantics); we rename only — there is
-- no in-place data correction because the column is per-active-visit state
-- that gets DELETE'd on departure, and any DB upgraded mid-visit will see
-- the stale row's gp value flipped to a cp interpretation on read. The
-- worst-case impact is one stale visit row that under-states a toll by 100×;
-- VisitStateManager.on_party_departed_settlement clears these rows on the
-- next departure.

BEGIN TRANSACTION;

ALTER TABLE party_visit_state RENAME COLUMN entry_toll_paid_gp TO entry_toll_paid_cp;

COMMIT;
