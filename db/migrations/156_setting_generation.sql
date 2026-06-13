-- Migration 156: Setting-generation canonical data (Stage 0 of the
-- pre-game setting-generation pipeline — docs/setting-generation-build-handoff.md).
--
-- These tables hold the permanent campaign world produced by the 8-layer
-- pipeline (generation/gdd-setting-generation.md §3; sim output contract §7.2).
-- They are written ONLY by engine/subsystems/generation/world/* during
-- campaign creation, frozen by the Layer-8 post-approval lock
-- (setting_parameters.is_locked), and read-only for all downstream systems
-- after the lock. They are deliberately separate from the play-time tables
-- (hex_maps / hex_cells / domains / realms): the play layer is materialized
-- FROM this canonical data at the party-creation handoff and may then evolve;
-- the canonical setting never changes.
--
-- Determinism note: all TEXT ids in these tables are DETERMINISTIC,
-- generation-assigned ids (pol_0001, evt_000123_004, ...), never
-- CampaignRepository.generate_id() — the §9.1 determinism hash test compares
-- two generation runs row-for-row, so random ids would break it.

-- Campaign parameters + seed (gdd-setting-generation.md §11.2; the full
-- slider vector is one canonical-JSON blob — same seed + same params_json
-- must reproduce the world bit-identically).
CREATE TABLE IF NOT EXISTS setting_parameters (
    campaign_id TEXT PRIMARY KEY REFERENCES campaigns(id),
    campaign_seed INTEGER NOT NULL,
    params_json TEXT NOT NULL DEFAULT '{}',
    pipeline_version INTEGER NOT NULL DEFAULT 1,
    is_locked INTEGER NOT NULL DEFAULT 0 CHECK(is_locked IN (0, 1)),
    world_hash TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Per-24-mile-hex canonical data: Layer 1-2 terrain/climate plus the Layer-4
-- hex substrate of the sim output contract (§7.2). Enum CHECKs mirror
-- hex_cells / gdd-terrain-system.md §3 exactly.
CREATE TABLE IF NOT EXISTS setting_hexes (
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    q INTEGER NOT NULL,
    r INTEGER NOT NULL,
    -- Layer 1: geography
    elevation_raw REAL NOT NULL DEFAULT 0.0,
    elevation TEXT NOT NULL DEFAULT 'flat'
        CHECK(elevation IN ('flat', 'hills', 'mountains')),
    water TEXT NOT NULL DEFAULT ''
        CHECK(water IN ('', 'ocean', 'lake')),
    -- Layer 2: climate
    temperature REAL NOT NULL DEFAULT 0.0,
    precipitation REAL NOT NULL DEFAULT 0.0,
    effective_latitude REAL NOT NULL DEFAULT 0.0,
    koppen TEXT NOT NULL DEFAULT '',
    biome TEXT NOT NULL DEFAULT 'clear'
        CHECK(biome IN ('clear', 'woods', 'jungle', 'swamp', 'desert')),
    biome_subtype TEXT NOT NULL DEFAULT ''
        CHECK(biome_subtype IN (
            '',
            'forest_dense', 'forest_taiga',
            'mountains_volcanic', 'mountains_glacial',
            'clear_tundra', 'clear_savanna', 'clear_grassland',
            'clear_steppe', 'clear_scrub',
            'desert_badlands'
        )),
    original_biome TEXT NOT NULL DEFAULT '',
    -- Layer 4: sim substrate (history-sim §5; weights are JSON dicts
    -- culture_id/alignment -> float, sum 1.0 within tolerance)
    culture_weights TEXT NOT NULL DEFAULT '{}',
    alignment_weights TEXT NOT NULL DEFAULT '{}',
    population_band INTEGER NOT NULL DEFAULT 0,
    territory_class TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(territory_class IN ('civilized', 'borderlands', 'wilderness')),
    owner_polity_id TEXT NOT NULL DEFAULT '',
    land_value INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (campaign_id, q, r)
);

-- Layer-1 river graph — a first-class output (region painting and the sim
-- both consume it). Same edge model as hex_river_edges
-- (gdd-terrain-system.md §3.6: canonical owner = lexicographically lower
-- (q, r); edge 0=N .. 5=NW), plus the generation-time width category
-- (gdd-setting-generation.md §4.4: each tributary junction steps the width).
CREATE TABLE IF NOT EXISTS setting_river_edges (
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    edge INTEGER NOT NULL CHECK(edge BETWEEN 0 AND 5),
    flow_clockwise INTEGER NOT NULL DEFAULT 0 CHECK(flow_clockwise IN (0, 1)),
    width_category TEXT NOT NULL DEFAULT 'stream'
        CHECK(width_category IN ('stream', 'creek', 'river', 'major_river')),
    navigability TEXT NOT NULL DEFAULT 'none'
        CHECK(navigability IN ('none', 'small_craft', 'river_craft', 'large_craft')),
    crossing TEXT NOT NULL DEFAULT 'none'
        CHECK(crossing IN ('none', 'bridge', 'ford', 'ferry')),
    PRIMARY KEY (campaign_id, hex_q, hex_r, edge)
);

-- Polities — every polity the history sim ever instantiated, surviving and
-- fallen (fell_tick NULL = survives to game-start). Fields per the §7.2
-- contract + history-sim §5. Hex membership is NOT duplicated here: a
-- surviving polity's hexes are setting_hexes rows with owner_polity_id = id;
-- a fallen polity's heartland is in setting_fallen_polities.
CREATE TABLE IF NOT EXISTS setting_polities (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    culture_id TEXT NOT NULL,
    alignment TEXT NOT NULL DEFAULT 'neutral'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    tier_index INTEGER NOT NULL DEFAULT 0 CHECK(tier_index BETWEEN 0 AND 6),
    title TEXT NOT NULL DEFAULT '',
    ruler_class TEXT NOT NULL DEFAULT '',
    ruler_level INTEGER NOT NULL DEFAULT 0,
    ruler_quality TEXT NOT NULL DEFAULT 'average'
        CHECK(ruler_quality IN ('strong', 'average', 'weak')),
    capital_q INTEGER NOT NULL DEFAULT 0,
    capital_r INTEGER NOT NULL DEFAULT 0,
    liege_id TEXT NOT NULL DEFAULT '',
    vassalized_by_war INTEGER NOT NULL DEFAULT 0 CHECK(vassalized_by_war IN (0, 1)),
    founded_tick INTEGER NOT NULL DEFAULT 0,
    fell_tick INTEGER,
    fade_onset_tick INTEGER,
    civ_or_clan_state TEXT NOT NULL DEFAULT 'civ'
        CHECK(civ_or_clan_state IN ('civ', 'clan')),
    garrison_coverage REAL NOT NULL DEFAULT 0.0,
    morale_seed TEXT NOT NULL DEFAULT '[]',
    internal_vassals TEXT NOT NULL DEFAULT '[]',
    name TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

-- Fallen-polity reaches for region painting (§7.2 fallen_polities[]):
-- the heartland hexes a polity held when it fell, plus its toponym root.
CREATE TABLE IF NOT EXISTS setting_fallen_polities (
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    polity_id TEXT NOT NULL,
    toponym_root TEXT NOT NULL DEFAULT '',
    hexes TEXT NOT NULL DEFAULT '[]',
    era_tick INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (campaign_id, polity_id)
);

-- Settlements-by-emergence (§7.2 settlements[]; market_class assigned by
-- Layer 6 reconciliation, name by Layer 5).
CREATE TABLE IF NOT EXISTS setting_settlements (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    polity_id TEXT NOT NULL DEFAULT '',
    urban_families INTEGER NOT NULL DEFAULT 0,
    emergence_tick INTEGER NOT NULL DEFAULT 0,
    is_capital INTEGER NOT NULL DEFAULT 0 CHECK(is_capital IN (0, 1)),
    market_class INTEGER NOT NULL DEFAULT 6 CHECK(market_class BETWEEN 1 AND 6),
    name TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

-- Named non-political regions (gdd-region-painting.md §3.1). hexes is a JSON
-- [[q,r],...] membership list (ordered hex path for layer='road').
CREATE TABLE IF NOT EXISTS setting_regions (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    layer TEXT NOT NULL
        CHECK(layer IN ('continent', 'coastal_landform', 'terrain_cluster',
                        'hydronym', 'road', 'historical_cultural')),
    subtype TEXT NOT NULL DEFAULT '',
    scale TEXT NOT NULL DEFAULT 'campaign_24mi'
        CHECK(scale IN ('campaign_24mi', 'regional_6mi', 'local_15mi')),
    parent_id TEXT NOT NULL DEFAULT '',
    coarse_parent_region_id TEXT NOT NULL DEFAULT '',
    hexes TEXT NOT NULL DEFAULT '[]',
    overlaps TEXT NOT NULL DEFAULT '[]',
    name_primary TEXT NOT NULL DEFAULT '',
    name_culture_id TEXT NOT NULL DEFAULT '',
    name_origin TEXT NOT NULL DEFAULT ''
        CHECK(name_origin IN ('', 'descriptive', 'cultural', 'historical', 'hydronym_derived')),
    name_alternates TEXT NOT NULL DEFAULT '[]',
    significance REAL NOT NULL DEFAULT 0.0,
    source_event_id TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

-- History event log (gdd-history-simulation.md §11.1; type enum verbatim).
CREATE TABLE IF NOT EXISTS setting_events (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    tick INTEGER NOT NULL,
    year_before_start INTEGER NOT NULL DEFAULT 0,
    type TEXT NOT NULL
        CHECK(type IN ('founding', 'expansion', 'war', 'conquest', 'vassalage',
                       'secession', 'pillage', 'schism', 'migration',
                       'collapse_rump', 'collapse_shatter', 'depopulation',
                       'golden_age', 'dynasty_change', 'alignment_drift')),
    polity_ids TEXT NOT NULL DEFAULT '[]',
    culture_ids TEXT NOT NULL DEFAULT '[]',
    hexes TEXT NOT NULL DEFAULT '[]',
    region_hint TEXT NOT NULL DEFAULT '',
    severity REAL NOT NULL DEFAULT 0.0,
    significance REAL NOT NULL DEFAULT 0.0,
    summary_key TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

CREATE INDEX IF NOT EXISTS idx_setting_events_tick
    ON setting_events(campaign_id, tick);

-- Ruin/dungeon seeds with provenance (§7.2 ruin_seeds[];
-- gdd-setting-generation.md §9.3 — provenance-first).
CREATE TABLE IF NOT EXISTS setting_ruin_seeds (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    provenance_culture_id TEXT NOT NULL DEFAULT '',
    provenance_polity_id TEXT NOT NULL DEFAULT '',
    provenance_toponym TEXT NOT NULL DEFAULT '',
    era_tick INTEGER NOT NULL DEFAULT 0,
    event_type TEXT NOT NULL DEFAULT '',
    source_event_id TEXT NOT NULL DEFAULT '',
    size_hint TEXT NOT NULL DEFAULT 'lair'
        CHECK(size_hint IN ('lair', 'small', 'medium', 'large')),
    dungeon_type TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

-- Wilderness POI seeds (gdd-setting-generation.md §9.7; detail shape owned by
-- gdd-poi-generation.md — the type-specific mechanical skeleton and rumor
-- seeds are JSON so Stage 7 can fill them without schema churn).
CREATE TABLE IF NOT EXISTS setting_poi_seeds (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    poi_type TEXT NOT NULL DEFAULT '',
    context TEXT NOT NULL DEFAULT '{}',
    rumor_seeds TEXT NOT NULL DEFAULT '[]',
    name TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

-- History-replay frames (§7.2 replay_frames[]; history-sim §15,
-- REPLAY_CADENCE = 4 ticks). owner_by_hex is run-length encoded over the
-- canonical hex order (r ASC, then q ASC): runs of "polity_id:count" joined
-- by ';' ('' polity_id = unowned). The palette is per-campaign stable so a
-- realm keeps its color across frames (gdd-campaign-creation-ui.md §7).
CREATE TABLE IF NOT EXISTS setting_replay_frames (
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    tick INTEGER NOT NULL,
    owner_by_hex TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, tick)
);

CREATE TABLE IF NOT EXISTS setting_replay_palette (
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    polity_id TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, polity_id)
);
