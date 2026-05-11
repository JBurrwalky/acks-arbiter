-- Migration 084: sieges — Phase 9B Full DaW siege subsystem (state row).
--
-- Per docs/domain-roadmap-corrected.md Phase 9 §siege bullets L378-407 and
-- rules/daw_sieges.xml.
--
-- One row per active or concluded siege. Partial-unique-active per stronghold
-- (only one siege at a time per stronghold) per RAW §ending_sieges L771-803
-- (the besieger may continue / new siege requires a new dispatcher call).
--
-- resolution_mode:
--   'simplified' — NPC-vs-NPC, runs on a single scheduled `siege_simplified_concluded`
--                  event at started_day + duration_days per RAW §sieges_simplified L813-844
--   'full'       — player-involved, runs daily/weekly tick events per RAW §blockade
--                  + §reduction + §assault L65-499
--
-- current_phase: dominant phase. RAW §methods_of_siege L13-28 says methods may
-- overlap, repeat, or occur in any order — current_phase is for UI dominance only.
--
-- starting_shp / current_shp / damage_dealt_total / damage_repaired_total / breach_count:
--   damage_dealt_total is the cumulative shp damage the besieger has scored.
--   damage_repaired_total is the cumulative shp the defender has repaired.
--   current_shp = starting_shp - damage_dealt_total + damage_repaired_total
--   breach_count = floor(damage_dealt_total / 1000) per RAW §siege_mechanics.breaches L42-46
--   Repair cap (RAW L460): damage_repaired_total ≤ 0.5 * damage_dealt_total
--   (CONFIRMED 2026-05-09 — cumulative across the siege, not per-day).
--
-- stored_supplies_cp / weeks_unsupplied / starvation_penalty_stacks per RAW
-- §effects_of_blockade L116-136. cp not gp per project convention (PartyWallet,
-- deduct_cost_cp). Default 600 gp/UC = 60_000 cp/UC; cap 3,000 gp/UC = 300_000 cp/UC.
--
-- simplified_total_days: -1 stored for "−" (besieger too weak per RAW L819).

CREATE TABLE IF NOT EXISTS sieges (
    id                          TEXT PRIMARY KEY,
    campaign_id                 TEXT NOT NULL REFERENCES campaigns(id),
    stronghold_id               TEXT NOT NULL REFERENCES strongholds(id),
    domain_id                   TEXT REFERENCES domains(id),
    besieging_army_id           TEXT NOT NULL REFERENCES armies(id),
    defending_army_id           TEXT REFERENCES armies(id),
    map_id                      TEXT REFERENCES hex_maps(id),
    hex_q                       INTEGER,
    hex_r                       INTEGER,

    resolution_mode             TEXT    NOT NULL DEFAULT 'simplified'
        CHECK(resolution_mode IN ('simplified', 'full')),
    current_phase               TEXT    NOT NULL DEFAULT 'blockade'
        CHECK(current_phase IN ('blockade', 'reduction', 'assault', 'concluded')),

    starting_shp                INTEGER NOT NULL,
    current_shp                 INTEGER NOT NULL,
    damage_dealt_total          INTEGER NOT NULL DEFAULT 0,
    damage_repaired_total       INTEGER NOT NULL DEFAULT 0,
    breach_count                INTEGER NOT NULL DEFAULT 0,

    unit_capacity               INTEGER NOT NULL,
    material                    TEXT    NOT NULL DEFAULT 'stone'
        CHECK(material IN ('stone', 'wood')),

    is_blockaded                INTEGER NOT NULL DEFAULT 0
        CHECK(is_blockaded IN (0, 1)),
    blockade_method             TEXT    NOT NULL DEFAULT ''
        CHECK(blockade_method IN ('', 'units', 'ships', 'fortifications', 'mixed')),
    circumvallation_feet        INTEGER NOT NULL DEFAULT 0,
    is_circumvallation_complete INTEGER NOT NULL DEFAULT 0
        CHECK(is_circumvallation_complete IN (0, 1)),
    water_facing_pct            INTEGER NOT NULL DEFAULT 0,

    stored_supplies_cp          INTEGER NOT NULL,
    weeks_unsupplied            INTEGER NOT NULL DEFAULT 0,
    starvation_penalty_stacks   INTEGER NOT NULL DEFAULT 0,

    simplified_total_days       INTEGER NOT NULL DEFAULT 0,
    simplified_site_modifier    REAL    NOT NULL DEFAULT 1.0,

    started_calendar_day        INTEGER NOT NULL,
    expected_end_calendar_day   INTEGER NOT NULL DEFAULT 0,
    concluded_calendar_day      INTEGER NOT NULL DEFAULT 0,
    outcome                     TEXT    NOT NULL DEFAULT ''
        CHECK(outcome IN ('', 'captured', 'liberated', 'destroyed', 'surrendered',
                          'departed', 'sallied_won', 'sallied_lost')),

    payload_json                TEXT    NOT NULL DEFAULT '{}',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sieges_stronghold ON sieges(stronghold_id);
CREATE INDEX IF NOT EXISTS idx_sieges_domain     ON sieges(domain_id);
CREATE INDEX IF NOT EXISTS idx_sieges_besieger   ON sieges(besieging_army_id);
CREATE INDEX IF NOT EXISTS idx_sieges_campaign   ON sieges(campaign_id);

-- One active siege per stronghold (RAW does not contemplate concurrent sieges).
CREATE UNIQUE INDEX IF NOT EXISTS idx_sieges_unique_active_per_stronghold
    ON sieges(stronghold_id) WHERE current_phase != 'concluded';
