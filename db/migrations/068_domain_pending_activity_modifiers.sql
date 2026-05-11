-- Migration 068: Domain pending activity modifiers (Domain Phase 3)
--
-- Two transient columns set by activity handlers and consumed (then reset)
-- by the monthly-tick handler. Allows real-effect activity completion without
-- the Phase 0 monthly-tick code reading from a queue table.
--
--   * administer_domain_completed_this_month — set by the administer_domain
--     handler on completion of the month's required ticks. Phase 0's morale
--     resolver adds +1 to event_modifiers_sum and the monthly tick adds +5%
--     to domain_xp_this_month per acore_axioms §administration L499. The
--     monthly tick resets this to 0 after applying.
--
--   * pending_investment_gp — set by the oversee_investment handler on
--     completion. The next monthly tick reads this into the growth resolver
--     (Phase 0 currently hardcodes investment_gp=0) per
--     acore_axioms §investments L132-135, then resets to 0.

ALTER TABLE domains
    ADD COLUMN administer_domain_completed_this_month INTEGER NOT NULL DEFAULT 0
        CHECK(administer_domain_completed_this_month IN (0, 1));

ALTER TABLE domains
    ADD COLUMN pending_investment_gp INTEGER NOT NULL DEFAULT 0;
