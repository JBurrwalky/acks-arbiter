-- Migration 060: Strongholds (Domain Phase 1)
--
-- Per `acore_axioms_strongholds_and_domains.xml` §strongholds L83-99 and
-- `acore_stronghold_construction_costs.pdf` p.126 (Strongholds by Class +
-- Stronghold Structure Costs tables). Phase 1 ships only the SUMMARY-level
-- data model needed to unblock:
--   * Phase 0's sufficiency calc (`stronghold_repository.get_stronghold_value_for_domain`
--     replaces the `_stub_stronghold_value` placeholder)
--   * Phase 4's Stronghold sub-tab UI
--   * Phase 5's L9+ follower wave arrival (50% / 100% completion thresholds)
--
-- The voxel-grid layout system from `gdd-stronghold-construction.md` §9.1
-- (per-cell building / accessory placement, interior auto-generation) is
-- DEFERRED to a future phase that ships the visual editor / siege renderer.
-- Schema below leaves room for it without committing to the layout columns.
--
-- The roadmap text references migrations 055-057 for Phase 1; Phase 0 used
-- 055-059, so Phase 1 shifts to 060-062 monotonically.

CREATE TABLE IF NOT EXISTS strongholds (
    id                       TEXT    PRIMARY KEY,
    -- NULL until a domain is established at this hex (a stronghold can be
    -- built on unsecured land, then a domain established around it).
    domain_id                TEXT REFERENCES domains(id),
    owner_character_id       TEXT REFERENCES characters(id),
    -- 6 archetypes: fortress (fighter / cleric / bladedancer / paladin),
    -- sanctum (mage / Lightblessed Wonderworker), hideout (assassin / thief /
    -- elf nightblade / venturer trading post), fastness (elf spellsword),
    -- vault (dwarven craftpriest / vaultguard), clanhold (chaotic per
    -- ax_domains_of_chaos.xml).
    archetype                TEXT    NOT NULL DEFAULT 'fortress'
        CHECK(archetype IN ('fortress', 'sanctum', 'hideout', 'fastness', 'vault', 'clanhold')),
    -- Power_id linking to data/powers/power_catalog.json and
    -- data/strongholds/archetype_presets.json. Examples: stronghold_castle,
    -- stronghold_church, stronghold_temple, stronghold_sanctum, etc.
    archetype_power_id       TEXT    NOT NULL DEFAULT '',
    -- Primary structure for catalog reference (the dominant building);
    -- secondary structures are summarized in stronghold_accessories or in
    -- a future per-structure breakdown table.
    structure_type           TEXT    NOT NULL DEFAULT 'keep',
    -- Final cost in gp. This is the value that drives sufficiency
    -- (acore_axioms §minimum_stronghold_value L88-94: 15k civilized,
    -- 22.5k borderlands, 32k wilderness per 6-mile hex).
    gp_value                 INTEGER NOT NULL DEFAULT 0,
    -- Siege HP from daw_equipment_and_construction.xml §structures (consumed
    -- by Phase 8 sieges). Recorded at construction; current_shp damage tracking
    -- is a Phase 8 concern.
    shp                      INTEGER NOT NULL DEFAULT 0,
    ac                       INTEGER NOT NULL DEFAULT 6,
    garrison_capacity        INTEGER NOT NULL DEFAULT 0,  -- units, per daw catalog
    -- Denormalized cache of (gp_progressed / gp_committed * 100); set by
    -- commission_pipeline.advance_commissions on each daily tick crossing
    -- 50% or 100% milestones. Reads of in-progress strongholds compute live
    -- progress directly from the commission row.
    completion_pct           INTEGER NOT NULL DEFAULT 0
        CHECK(completion_pct BETWEEN 0 AND 100),
    -- Display-only flag per [RESOLVED 2026-05-06] in domain-roadmap-corrected.md:
    -- conforming-vs-non-conforming has no mechanical effect (followers, garrison,
    -- morale, activities all gate on stronghold gp-value sufficiency only).
    -- Computed by ClaimingResolver.is_archetype_conforming_to_class for UI use.
    is_conforming_to_class   INTEGER NOT NULL DEFAULT 1
        CHECK(is_conforming_to_class IN (0, 1)),
    is_claimed               INTEGER NOT NULL DEFAULT 0
        CHECK(is_claimed IN (0, 1)),
    claimed_from_source      TEXT    NOT NULL DEFAULT ''
        CHECK(claimed_from_source IN ('', 'dungeon', 'ruin', 'conquest', 'inheritance', 'purchase', 'grant')),
    location_map_id          TEXT REFERENCES hex_maps(id),
    location_hex_q           INTEGER,
    location_hex_r           INTEGER,
    -- High-level state. Granular pause reasons (paused_engineers, paused_funds,
    -- paused_user) live on stronghold_commissions.status — strongholds.status
    -- collapses them all to 'paused' for sub-tab display.
    status                   TEXT    NOT NULL DEFAULT 'in_progress'
        CHECK(status IN ('in_progress', 'completed', 'paused', 'destroyed', 'claimed')),
    created_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_strongholds_domain_id
    ON strongholds (domain_id);

CREATE INDEX IF NOT EXISTS idx_strongholds_owner
    ON strongholds (owner_character_id);

CREATE INDEX IF NOT EXISTS idx_strongholds_hex
    ON strongholds (location_map_id, location_hex_q, location_hex_r);
