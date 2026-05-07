-- Migration 061: Stronghold commissions (Domain Phase 1)
--
-- Per `acore_stronghold_construction_costs.pdf` p.126-127 (the canonical source
-- for cost / time rules). Construction takes 1 day per 500 gp of base cost,
-- with two speed tiers: pay +50% extra for 25% time savings, or +100% extra
-- for 50% time savings (hard cap). Plus an engineer requirement: at least
-- 1 engineer at 250 gp/month per 100,000 gp of cost.
--
-- Cleric and bladedancer strongholds (Fortified Church / Temple) have a
-- 50% cost reduction per the PDF p.126 "Strongholds by Class" table; their
-- followers also never check morale (flag stored in archetype_presets.json,
-- consumed by Phase 5).
--
-- Class location restrictions (dwarven must be underground, elf spellsword
-- non-human/dwarven, explorer borderlands/wilderness only) are enforced by
-- StrongholdCostCalculator.validate_class_location at commission start time;
-- the schema does NOT encode these — they're caller-validated.

CREATE TABLE IF NOT EXISTS stronghold_commissions (
    id                          TEXT    PRIMARY KEY,
    stronghold_id               TEXT    NOT NULL REFERENCES strongholds(id),
    -- Total cost the player committed (already includes any class-specific
    -- 50% discount for cleric / bladedancer and any speed-tier premium).
    gp_committed                INTEGER NOT NULL DEFAULT 0,
    -- Resolved per-day construction progress (gp credited per game day).
    -- Base rate = 500 (1 day per 500 gp); speed tier 150 = 666; tier 200 = 1000.
    daily_construction_rate_gp  INTEGER NOT NULL DEFAULT 500,
    -- Speed tier per the PDF: 100 = base; 150 = +50% cost / -25% time;
    -- 200 = +100% cost / -50% time (hard cap).
    speed_tier_pct              INTEGER NOT NULL DEFAULT 100
        CHECK(speed_tier_pct IN (100, 150, 200)),
    -- Engineer requirement: ceil(gp_committed / 100,000); 250 gp/month each.
    engineers_required          INTEGER NOT NULL DEFAULT 1,
    engineers_assigned          INTEGER NOT NULL DEFAULT 1,
    engineer_monthly_wage_gp    INTEGER NOT NULL DEFAULT 250,
    supervisor_character_id     TEXT REFERENCES characters(id),
    -- Magic assistance per `daw_equipment_and_construction.xml` §magic_assistance
    -- L801-819 (Move Earth, Transmute Rock to Mud, Wall of Stone). Stored as
    -- a percentage of the base rate; 100 = no magic, 150 = +50%, 200 = +100%.
    magic_rate_modifier_pct     INTEGER NOT NULL DEFAULT 100,
    materials_strategy          TEXT    NOT NULL DEFAULT 'local'
        CHECK(materials_strategy IN ('local', 'purchased', 'scavenged', 'long_distance')),
    -- Class-specific 50% cost reduction (cleric / bladedancer per the PDF
    -- "Strongholds by Class" table). Stored as a flag for ledger / audit;
    -- the discount is already baked into gp_committed.
    class_cost_reduction_pct    INTEGER NOT NULL DEFAULT 0
        CHECK(class_cost_reduction_pct IN (0, 50)),
    -- Daily-tick state. started/halfway/completion days are absolute
    -- calendar days (matching domain_handlers._calendar_day_from_date);
    -- gp_progressed is mutated daily by commission_pipeline.advance_commissions.
    started_calendar_day        INTEGER NOT NULL,
    expected_halfway_day        INTEGER NOT NULL,
    expected_completion_day     INTEGER NOT NULL,
    gp_progressed               INTEGER NOT NULL DEFAULT 0,
    halfway_signal_fired        INTEGER NOT NULL DEFAULT 0
        CHECK(halfway_signal_fired IN (0, 1)),
    completed_calendar_day      INTEGER,
    -- Granular pause reasons. The strongholds.status column collapses these
    -- to 'paused' for top-level display; the sub-tab UI reads this column
    -- to show WHY a commission is paused.
    status                      TEXT    NOT NULL DEFAULT 'in_progress'
        CHECK(status IN ('in_progress', 'completed', 'paused_engineers', 'paused_funds', 'paused_user', 'cancelled')),
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_commissions_stronghold
    ON stronghold_commissions (stronghold_id);

CREATE INDEX IF NOT EXISTS idx_commissions_status
    ON stronghold_commissions (status);
