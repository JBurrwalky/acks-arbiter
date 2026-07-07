-- Migration 193: Faction Framework FF-3 — realm diplomacy & rebellion runtime
-- state (gdd-faction-framework.md §5). FF-1 (migrations 188/189) already created
-- every table §5 rides — treaties, faction_plots(+members), realm_petitions,
-- faction_stances, faction_events — with all their runtime columns, and the
-- ruler-AI vassal tables (vassal_assignments: base_loyalty_modifier /
-- last_loyalty_roll_day / last_loyalty_outcome). This migration adds ONLY the
-- two genuinely-new state fields §5 needs beyond what FF-1 landed:
--
--   1. vassal_assignments.compliance_behavior  (§5.3 — the compliance-ladder tag
--      on the liege<->vassal edge). Maps the last loyalty-result band to the
--      vassal-ruler's realm behavior: over/full/under compliance, resignation-
--      seeking (opens the §5.9 petition ladder), or rebellious (seeds a §5.7
--      plot). Muster/tribute resolvers read it for the §5.3 troop scalars.
--
--   2. faction_plots.ready_since_day  (§5.7 LAUNCH — the "6 months ready" trigger
--      needs the day the plot first reached status='ready'). 0 = not-yet-ready.
--
-- Non-destructive: both carry a DEFAULT so existing rows populate without
-- rewrite. compliance_behavior CHECK is a single-column literal enum (rides an
-- ADD COLUMN fine per the FF-1 migration-188 note).

-- --- Faction FF-3: realm diplomacy & rebellion (§5.3 compliance ladder) ---
ALTER TABLE vassal_assignments ADD COLUMN compliance_behavior TEXT NOT NULL DEFAULT 'full_compliance'
    CHECK(compliance_behavior IN (
        'over_compliance', 'full_compliance', 'under_compliance',
        'resignation_seeking', 'rebellious'));

-- --- Faction FF-3: realm diplomacy & rebellion (§5.7 rebel-coalition LAUNCH) ---
ALTER TABLE faction_plots ADD COLUMN ready_since_day INTEGER NOT NULL DEFAULT 0;
