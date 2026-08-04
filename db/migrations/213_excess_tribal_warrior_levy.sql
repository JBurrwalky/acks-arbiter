-- Migration 213: mark tribal-warrior units levied BEYOND the free 1-per-family
-- allotment, so the standing militia-style domain penalties can be scoped to
-- exactly those warriors.
--
-- RAW rules/ax_domains_of_chaos.xml:398-399 — "Up to 1 tribal warrior per
-- tribal family may be levied without reducing domain morale or domain
-- revenue. Any additional levies are treated as militia."
--
-- Per Jedidiah (2026-08-03), "treated as militia" attaches the militia LIMITS
-- and PENALTIES (daw_armies_recruitment.xml:428-432) to the excess, not militia
-- STATS -- the excess warriors remain tribal warriors, trained and equipped per
-- tribal custom (:408). So they cannot simply be minted as source_type
-- 'militia'; they need a flag.
--
-- Why a per-unit flag and not a counter on `domains`:
--   * The penalty basis must be what is CURRENTLY under arms (:431 "these
--     penalties remain until the militia is sent home"), so it has to shrink
--     automatically when a unit is stood down, destroyed in battle, or departs
--     on a failed loyalty roll. A live SUM over troop_units does that for free;
--     a domain-level counter would need every one of those paths to remember to
--     decrement it.
--   * LevyTribalWarriorsHandler mints free and excess warriors into SEPARATE
--     rows, so a row is wholly one or the other and the flag is never partial.
--
-- Additive only; 0 is correct for every unit minted before this migration
-- (nothing could previously be levied past the free allotment -- the handler
-- capped at available_tribal_warriors and refused the remainder).

ALTER TABLE troop_units ADD COLUMN is_excess_levy INTEGER NOT NULL DEFAULT 0
    CHECK(is_excess_levy IN (0, 1));

-- Partial index: the penalty query filters on this flag alongside source_type
-- and status, and excess-levy rows are the rare case.
CREATE INDEX IF NOT EXISTS idx_troop_units_excess_levy
    ON troop_units(assigned_domain_id) WHERE is_excess_levy = 1;
