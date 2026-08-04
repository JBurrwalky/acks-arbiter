-- Migration 214: extend RAW Unit Loyalty from tribal warriors to every troop
-- source type. Migration 212 deliberately made the carryover columns
-- source_type-agnostic so this step would be additive; these are the two
-- pieces of per-unit state 212 could not have known it needed, plus one new
-- departure-log event type.
--
-- ---------------------------------------------------------------------------
-- (a) troop_units.is_religious_fanatic
-- ---------------------------------------------------------------------------
--
-- RAW rules/daw_armies_recruitment.xml:481 — "Cleric and bladedancer followers
-- are religious fanatics." :483 — "Religious fanatics do not make loyalty
-- rolls for calamities, but still make morale rolls in battle." That is an
-- exemption from the ROLL, not a modifier to it, so it has to be answerable
-- from the troop_units row at the moment a calamity fires.
--
-- Why a column and not a derived test: the tempting proxy is
-- `source_type='follower' AND monthly_cost_cp = 0`, since FollowerArrivalResolver
-- writes cost 0 exactly when the class table says `wages_required: false`. But
-- `data/followers/per_class_tables.json` sets `wages_required: false` for the
-- MAGE table too, and mages are not religious fanatics (:481 names two classes).
-- The proxy is correct today only because the mage table happens to have no
-- `soldier_attractor` and therefore mints no troop rows at all — an accident of
-- the data file, one attractor away from silently exempting the wrong units.
-- The column records the RAW fact directly.
--
-- Backfill: for units minted BEFORE this migration the class table is no longer
-- recoverable from the row, so the one-time heuristic above is used — and it is
-- exact for existing data precisely because the mage table mints nothing. From
-- here on the flag is set explicitly at mint time by FollowerArrivalResolver.
--
-- ---------------------------------------------------------------------------
-- (b) troop_units.campaigning_since_calendar_day
-- ---------------------------------------------------------------------------
--
-- RAW rules/daw_armies_recruitment.xml:459 — "Militia also treat each season of
-- continuous campaigning as a calamity." A militia-only calamity that no other
-- source type suffers, and the only one that depends on ELAPSED time rather
-- than an event, so it needs an anchor.
--
-- 0 means "not currently campaigning". The anchor is set, cleared and advanced
-- entirely inside the monthly domain tick (DomainHandlers._tick_unit_loyalty)
-- by looking at `assignment_kind`, so no army/muster path has to remember to
-- maintain it — the same live-derivation principle as conventions §132's levy
-- penalty. The cost is that a stretch of campaigning is only ever noticed on a
-- tick boundary, which is conservative (it can under-count by up to a month,
-- never over-count).
--
-- ---------------------------------------------------------------------------
-- (c) domain_departure_log event_type 'troop_unit_loyalty_failed'
-- ---------------------------------------------------------------------------
--
-- The migration-129 type `tribal_warriors_loyalty_failed` says what it means.
-- Logging a departing mercenary company under it would make the chronicle
-- assert something false, which conventions §131 forbids for exactly this
-- table. Tribal warriors keep their existing type; the other five source types
-- get this one. Only ONE new type: a mutiny that fields a hostile force is the
-- same event as the departure that caused it, so it rides in the same line's
-- summary and `fielded_army_id` metadata rather than emitting a second row.
--
-- SQLite cannot ALTER a CHECK constraint in place, so (c) uses the
-- legacy_alter_table rebuild pattern from migrations 117 / 119 / 125-129.
-- (a) and (b) are clean ADD COLUMNs.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- (a) + (b): additive columns on troop_units.
-- ---------------------------------------------------------------------------

ALTER TABLE troop_units ADD COLUMN is_religious_fanatic INTEGER NOT NULL DEFAULT 0
    CHECK(is_religious_fanatic IN (0, 1));

ALTER TABLE troop_units ADD COLUMN campaigning_since_calendar_day INTEGER NOT NULL DEFAULT 0
    CHECK(campaigning_since_calendar_day >= 0);

-- One-time backfill of the pre-existing faithful followers (see the header:
-- exact for existing data because the only other wages_required=false class
-- table mints no troop rows).
UPDATE troop_units
   SET is_religious_fanatic = 1
 WHERE source_type = 'follower'
   AND monthly_cost_cp = 0
   AND monthly_wage_cp > 0;

-- Partial index: the loyalty path asks "is this unit exempt?" per roll, and
-- religious fanatics are the rare case.
CREATE INDEX IF NOT EXISTS idx_troop_units_religious_fanatic
    ON troop_units(assigned_domain_id) WHERE is_religious_fanatic = 1;

-- ---------------------------------------------------------------------------
-- (c) Rebuild domain_departure_log — extend the event_type CHECK.
-- ---------------------------------------------------------------------------

ALTER TABLE domain_departure_log RENAME TO domain_departure_log_old;

CREATE TABLE domain_departure_log (
    id                       TEXT    PRIMARY KEY,
    campaign_id              TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                TEXT    NOT NULL,
    calendar_day             INTEGER NOT NULL,
    event_type               TEXT    NOT NULL
        CHECK(event_type IN (
            'established',
            'classification_advanced',
            'classification_regressed',
            'territory_lost',
            'stronghold_lost',
            'defeat',
            'pillaged',
            'ruler_changed',
            'ruler_died',
            'succession_started',
            'succession_resolved',
            'succession_lapsed',
            'vassal_lost',
            'vassal_promoted',
            'religion_converted',
            'monster_settled',
            'calamity',
            'morale_tier_dropped',
            'conquered',
            'abandoned',
            'restored',
            -- Migration 129 (Phase 11D.5) tribal-warrior event types
            -- per gdd-tribal-warriors.md §4.1.
            'tribal_warriors_levied',
            'tribal_warriors_stood_down',
            'tribal_warriors_released_for_population_loss',
            'tribal_warriors_morale_check_triggered',
            'tribal_warriors_loyalty_failed',
            'tribal_warriors_called_to_arms',
            -- Migration 214: Unit Loyalty departures for the non-tribal source
            -- types (mercenary / conscript / militia / follower / slave_soldier
            -- / vassal) per daw_armies_recruitment.xml:353 / :458 / :477.
            'troop_unit_loyalty_failed'
        )),
    summary                  TEXT    NOT NULL DEFAULT '',
    full_details_json        TEXT    NOT NULL DEFAULT '{}',
    related_ledger_entry_ids TEXT    NOT NULL DEFAULT '[]',
    related_encounter_ids    TEXT    NOT NULL DEFAULT '[]',
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO domain_departure_log (
    id, campaign_id, domain_id, calendar_day, event_type,
    summary, full_details_json, related_ledger_entry_ids,
    related_encounter_ids, created_at
)
SELECT
    id, campaign_id, domain_id, calendar_day, event_type,
    summary, full_details_json, related_ledger_entry_ids,
    related_encounter_ids, created_at
FROM domain_departure_log_old;

DROP TABLE domain_departure_log_old;

CREATE INDEX IF NOT EXISTS idx_domain_departure_log_domain_calendar
    ON domain_departure_log(domain_id, calendar_day DESC);
CREATE INDEX IF NOT EXISTS idx_domain_departure_log_campaign_calendar
    ON domain_departure_log(campaign_id, calendar_day DESC);

COMMIT;

PRAGMA foreign_keys = ON;
PRAGMA legacy_alter_table = OFF;
