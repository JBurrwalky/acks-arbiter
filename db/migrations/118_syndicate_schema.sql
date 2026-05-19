-- Migration 118: Syndicate (Hijinks) schema (Phase 10B.3).
--
-- Five new tables backing the Syndicate block per docs/phase-10-plan.md
-- §"Phase 10B.3 — Syndicate block":
--   * syndicates              — boss + hideout + base of operations + size cap
--   * syndicate_members       — bulk membership (named + unnamed)
--   * hijink_assignments      — one row per assigned/active/resolved hijink
--   * caught_perpetrators     — characters awaiting trial / serving punishment
--   * lay_low_state           — RAW 2d8+3-day lay-low timer per character
--
-- RAW sources:
--   * rules/acore-campaign-hijinks.xml §hideouts L1-46         (hideout size/cost)
--   * rules/acore-campaign-hijinks.xml §hijinks L48-237        (per-hijink resolution)
--   * rules/acore-campaign-hijinks.xml §getting_caught L240-410 (crime & punishment)
--   * rules/acore-campaign-hijinks.xml §managing_a_guild L480-525 (monthly NPC fast-path)
--   * rules/ax_campaign_play.xml §syndicate L1127-1252         (activity catalog)
--
-- Money convention: every money column is cp (Tier 1/2 currency unification —
-- see build_log.md 2026-05-18 Tier 1 / Tier 2 sessions). RAW gp values are
-- multiplied by 100 in any seed / launcher / handler boundary.
--
-- FK note: there is no `settlements` table in this schema (the Mercantile
-- prereq exposed `settlement_entrances` instead). `base_settlement_entrance_id`
-- references that table for the per-hideout "urban base of operations" per
-- RAW §hideouts L14 ("The nearby urban settlement becomes the syndicate's
-- base of operations.").
--
-- This migration is pure CREATE TABLE IF NOT EXISTS — no RENAME, so the
-- `PRAGMA legacy_alter_table = ON` guard from Migration 117 is not required
-- here. The migration is idempotent against a fresh DB.

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- syndicates: one row per syndicate (PC-led or NPC-led).
--
-- syndicate_size_max is derived from the hideout's hideout_size_and_cost row
-- (RAW §hideouts L30-45). Application logic populates it at hideout-build
-- completion; we don't compute it here in SQL.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS syndicates (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    boss_character_id               TEXT    NOT NULL REFERENCES characters(id),
    hideout_stronghold_id           TEXT    REFERENCES strongholds(id),
    base_settlement_entrance_id     TEXT    REFERENCES settlement_entrances(id),
    syndicate_size_max              INTEGER NOT NULL DEFAULT 0,
    current_size                    INTEGER NOT NULL DEFAULT 0,
    status                          TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'disbanded', 'seized')),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_syndicates_campaign
    ON syndicates(campaign_id);
CREATE INDEX IF NOT EXISTS idx_syndicates_boss
    ON syndicates(boss_character_id);
CREATE INDEX IF NOT EXISTS idx_syndicates_hideout
    ON syndicates(hideout_stronghold_id);


-- ---------------------------------------------------------------------------
-- syndicate_members: most members are unnamed bulk per RAW; named members
-- (henchmen, PCs) get a character_id_if_named pointer.
--
-- follower_kind tracks RAW's eligibility classes (thief / assassin /
-- nightblade / ruffian / other). hijink_eligible distinguishes thieves+
-- (eligible) from carousing-only members.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS syndicate_members (
    id                              TEXT    PRIMARY KEY,
    syndicate_id                    TEXT    NOT NULL REFERENCES syndicates(id),
    character_id_if_named           TEXT    REFERENCES characters(id),
    level                           INTEGER NOT NULL DEFAULT 1,
    follower_kind                   TEXT    NOT NULL DEFAULT 'thief'
        CHECK(follower_kind IN (
            'thief', 'assassin', 'elven_nightblade', 'ruffian', 'other'
        )),
    status                          TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN (
            'active', 'laying_low', 'jailed', 'dead', 'departed'
        )),
    hijink_eligible                 INTEGER NOT NULL DEFAULT 1
        CHECK(hijink_eligible IN (0, 1)),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_syndicate_members_syndicate
    ON syndicate_members(syndicate_id);
CREATE INDEX IF NOT EXISTS idx_syndicate_members_status
    ON syndicate_members(syndicate_id, status);
CREATE INDEX IF NOT EXISTS idx_syndicate_members_character
    ON syndicate_members(character_id_if_named);


-- ---------------------------------------------------------------------------
-- hijink_assignments: one row per assigned / planning / active / resolved
-- hijink attempt.
--
-- target_id is overloaded by kind:
--   * assassinating          → characters.id of the victim (or "" for hire-victim)
--   * smuggling / stealing   → merchandise_key (MerchandiseRegistry)
--   * spying / carousing     → "" (boss receives money, no target entity)
--   * treasure_hunting       → "" until the hoard resolver lands; later
--                              treasure_hoard_id (Phase 10B.3.1 polish)
--
-- cp_yield is in cp; RAW gp values are × 100 by the handler.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hijink_assignments (
    id                              TEXT    PRIMARY KEY,
    syndicate_id                    TEXT    NOT NULL REFERENCES syndicates(id),
    syndicate_member_id             TEXT    REFERENCES syndicate_members(id),
    boss_character_id               TEXT    NOT NULL REFERENCES characters(id),
    hideout_id                      TEXT    REFERENCES strongholds(id),
    hijink_kind                     TEXT    NOT NULL
        CHECK(hijink_kind IN (
            'assassinating', 'carousing', 'smuggling',
            'spying', 'stealing', 'treasure_hunting'
        )),
    planning_state                  TEXT    NOT NULL DEFAULT 'unplanned'
        CHECK(planning_state IN (
            'unplanned', 'planning', 'planned', 'in_progress', 'complete'
        )),
    planning_days_required          INTEGER NOT NULL DEFAULT 0,
    planning_days_completed         INTEGER NOT NULL DEFAULT 0,
    status                          TEXT    NOT NULL DEFAULT 'queued'
        CHECK(status IN (
            'queued', 'planning', 'active', 'resolved', 'aborted'
        )),
    started_day                     INTEGER NOT NULL DEFAULT 0,
    completed_day                   INTEGER,
    target_id                       TEXT    NOT NULL DEFAULT '',
    throw_result                    INTEGER,
    cp_yield                        INTEGER NOT NULL DEFAULT 0,
    caught                          INTEGER NOT NULL DEFAULT 0
        CHECK(caught IN (0, 1)),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_hijink_assignments_syndicate
    ON hijink_assignments(syndicate_id);
CREATE INDEX IF NOT EXISTS idx_hijink_assignments_member
    ON hijink_assignments(syndicate_member_id);
CREATE INDEX IF NOT EXISTS idx_hijink_assignments_status
    ON hijink_assignments(syndicate_id, status);


-- ---------------------------------------------------------------------------
-- caught_perpetrators: characters captured during a failed hijink.
--
-- bribe_amount_cp / fine_cp are in cp.
-- verdict / fine_cp / punishment_kind / punishment_resolved are populated
-- when the Crime & Punishment resolver fires (after time_languishing_days
-- elapses, or earlier on a plea per RAW §await_trial L1137).
--
-- prior_crimes_modifier mirrors character_legal_status.prior_crimes_modifier_cache
-- at trial time; we snapshot it so a later post-trial branding doesn't
-- retroactively change a past trial's recorded modifier.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caught_perpetrators (
    id                              TEXT    PRIMARY KEY,
    character_id                    TEXT    NOT NULL REFERENCES characters(id),
    hijink_assignment_id            TEXT    REFERENCES hijink_assignments(id),
    crime_type                      TEXT    NOT NULL,
    time_languishing_days           INTEGER NOT NULL DEFAULT 0,
    attorney_rank                   INTEGER NOT NULL DEFAULT 0,
    bribe_amount_cp                 INTEGER NOT NULL DEFAULT 0,
    interpleader_id                 TEXT    REFERENCES characters(id),
    verdict                         TEXT,
    fine_cp                         INTEGER NOT NULL DEFAULT 0,
    punishment_kind                 TEXT,
    punishment_resolved             INTEGER NOT NULL DEFAULT 0
        CHECK(punishment_resolved IN (0, 1)),
    prior_crimes_modifier           INTEGER NOT NULL DEFAULT 0,
    arrested_day                    INTEGER NOT NULL DEFAULT 0,
    resolved_day                    INTEGER,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_caught_perpetrators_character
    ON caught_perpetrators(character_id);
CREATE INDEX IF NOT EXISTS idx_caught_perpetrators_hijink
    ON caught_perpetrators(hijink_assignment_id);
CREATE INDEX IF NOT EXISTS idx_caught_perpetrators_unresolved
    ON caught_perpetrators(punishment_resolved, resolved_day);


-- ---------------------------------------------------------------------------
-- lay_low_state: RAW §lay_low L1188-1200 — 2d8+3 days. Required after
-- arson / assassination / infiltration / sabotage / smuggling / subversion /
-- stealing per RAW L1195. One row per character; primary key is character_id.
--
-- base_id is a free-form key (typically "stronghold:<id>" or
-- "settlement_entrance:<id>") identifying the base where the character
-- is laying low. RAW L1196 allows the character to operate in other bases
-- meanwhile, so the lock is scoped to the specific base.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lay_low_state (
    character_id                    TEXT    PRIMARY KEY REFERENCES characters(id),
    base_id                         TEXT    NOT NULL,
    started_day                     INTEGER NOT NULL,
    ends_day                        INTEGER NOT NULL,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_lay_low_state_base
    ON lay_low_state(base_id, ends_day);

COMMIT;
