-- Migration 154: Drop party_clocks (single-shared-timeline ruling 2026-06-11).
--
-- Jedidiah ruled (docs/handoff_multi_party_time.md §8) that the game runs on
-- ONE shared world timeline: the per-party clock mechanism is removed outright
-- and campaign_clock is the sole clock record. Under the old invariant the
-- global clock always equalled the leading party's clock, so dropping the
-- per-party rows loses no information the new model uses. "This party is
-- busy" is now the per-party order-lock, derived from the party's pending
-- scheduled_events rows (already persisted).

DROP TABLE IF EXISTS party_clocks;
