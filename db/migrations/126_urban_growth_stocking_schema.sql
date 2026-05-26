-- Migration 126: Urban Growth Stocking schema — Stage A per
-- `generation/gdd-urban-growth-stocking.md` §11 (v1.14).
--
-- Lands the substrate for the urban-growth/POI-emergence system:
--   1. `settlement_pois` table — the new POI inventory per §11.1, with all
--      v1.10/v1.13 column additions (builder_kind + builder_character_id +
--      l1_l2_adherent_count).
--   2. `settlement_poi_spell_offers` table — daily spellcasting service rolls
--      per §11.4a (backs §8.5).
--   3. Two triggers on `consecrated_altars` that maintain the religious_site
--      `tier` denormalized cache per §11.4 (promote shrine → temple on altar
--      completion, demote temple → shrine when no completed altars remain).
--   4. `strongholds.registered_settlement_poi_id` — siting hook for player-
--      built strongholds landing in a settlement hex per §11.4.
--   5. `characters.home_poi_id` — per-character POI affinity per Q-UGS-28.
--   6. `characters.npc_role` — NPC classification enum per Q-UGS-29.
--
-- Project ID convention: all primary keys are TEXT (deviating from the GDD's
-- INTEGER spec) to match the established `characters.id` / `strongholds.id` /
-- `settlement_entrances.id` pattern across the rest of the schema. Foreign
-- keys are TEXT to match.
--
-- Stage B (SettlementGrowthResolver + monthly-tick wiring) ships in this
-- same session but as code only; Stages C–H land in later sessions.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- 1. settlement_pois table per §11.1
-- ---------------------------------------------------------------------------
CREATE TABLE settlement_pois (
    id TEXT PRIMARY KEY,
    settlement_id TEXT NOT NULL REFERENCES settlement_entrances(id) ON DELETE CASCADE,
    type TEXT NOT NULL
        CHECK (type IN (
            'religious_site', 'mercenary_guild_hall', 'mages_guild_hall',
            'named_tavern', 'workshop', 'port'
        )),
    tier TEXT NOT NULL DEFAULT ''
        CHECK (tier IN ('', 'shrine', 'temple')),
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN (
            'emerging', 'active', 'understaffed', 'dormant', 'abandoned'
        )),
    -- v1.10 / Q-UGS-17: split typed columns (replaces v1.0-v1.9 single string
    -- `builder`). emergent vs character builder.
    builder_kind TEXT NOT NULL DEFAULT 'emergent'
        CHECK (builder_kind IN ('emergent', 'character')),
    builder_character_id TEXT REFERENCES characters(id) ON DELETE SET NULL,
    emerged_via TEXT NOT NULL DEFAULT ''
        CHECK (emerged_via IN (
            '', 'class_advancement', 'player_commission', 'stronghold_register',
            'baseline_emergence'
        )),
    established_at_calendar_day INTEGER NOT NULL DEFAULT 0,
    gp_value INTEGER NOT NULL DEFAULT 0,
    -- §5.4 K_local — count of L3+ NPCs anchored to THIS specific POI.
    l3_plus_npc_count INTEGER NOT NULL DEFAULT 0,
    -- v1.10 / Q-UGS-42: count of L1-L2 adherents nominally living here.
    -- These NPCs are NOT persisted as character rows at emergence time;
    -- materialized on-demand per §5.2 on-demand-materialization path.
    l1_l2_adherent_count INTEGER NOT NULL DEFAULT 0
        CHECK (l1_l2_adherent_count >= 0),
    -- Religion attribution (religious_site only; '' sentinel otherwise).
    attached_religion TEXT NOT NULL DEFAULT '',
    -- Specialist attribution (workshop only).
    attached_specialist_kind TEXT NOT NULL DEFAULT '',
    -- Stocking. v1.3 renamed from v1.2's stocked_cleric_character_id per
    -- Q-UGS-3 — column now stocks mage / fighter / specialist too.
    stocked_character_id TEXT REFERENCES characters(id) ON DELETE SET NULL,
    baseline_head_npc_character_id TEXT REFERENCES characters(id) ON DELETE SET NULL,
    -- District affinity hint (per gdd-settlement-stocking.md district types).
    preferred_district_class TEXT NOT NULL DEFAULT '',
    -- Forward-compatibility with Phase 12 factions; v1 always NULL = "realm".
    owner_faction_id TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    -- Table-level CHECKs MUST follow all column definitions in SQLite.
    -- Builder discriminator consistency.
    CHECK (
        (builder_kind = 'emergent' AND builder_character_id IS NULL)
        OR
        (builder_kind = 'character' AND builder_character_id IS NOT NULL)
    ),
    -- Tier-cache invariant.
    CHECK (
        (type = 'religious_site' AND tier IN ('shrine', 'temple'))
        OR (type <> 'religious_site' AND tier = '')
    )
);

CREATE INDEX idx_settlement_pois_settlement
    ON settlement_pois(settlement_id);
CREATE INDEX idx_settlement_pois_type
    ON settlement_pois(type);
CREATE INDEX idx_settlement_pois_religion
    ON settlement_pois(attached_religion)
    WHERE attached_religion <> '';
CREATE INDEX idx_settlement_pois_specialist_kind
    ON settlement_pois(attached_specialist_kind)
    WHERE attached_specialist_kind <> '';
CREATE INDEX idx_settlement_pois_tier
    ON settlement_pois(tier)
    WHERE tier <> '';

-- ---------------------------------------------------------------------------
-- 2. settlement_poi_spell_offers table per §11.4a
-- ---------------------------------------------------------------------------
CREATE TABLE settlement_poi_spell_offers (
    id TEXT PRIMARY KEY,
    poi_id TEXT NOT NULL REFERENCES settlement_pois(id) ON DELETE CASCADE,
    calendar_day INTEGER NOT NULL,
    tradition TEXT NOT NULL
        CHECK (tradition IN ('divine', 'arcane')),
    spell_level INTEGER NOT NULL
        CHECK (spell_level BETWEEN 1 AND 6),
    count_initial INTEGER NOT NULL
        CHECK (count_initial >= 0),
    count_remaining INTEGER NOT NULL
        CHECK (count_remaining >= 0 AND count_remaining <= count_initial),
    unit_cost_gp INTEGER NOT NULL
        CHECK (unit_cost_gp >= 0),
    UNIQUE (poi_id, calendar_day, tradition, spell_level)
);

CREATE INDEX idx_settlement_poi_spell_offers_lookup
    ON settlement_poi_spell_offers(poi_id, calendar_day);

-- ---------------------------------------------------------------------------
-- 3. Religious-site tier-cache triggers per §11.4
-- ---------------------------------------------------------------------------
-- Promote shrine → temple when an attached altar transitions to status='completed'.
CREATE TRIGGER trg_consecrated_altars_promote_religious_site
AFTER UPDATE OF status ON consecrated_altars
WHEN NEW.status = 'completed' AND NEW.location_kind = 'settlement_poi'
BEGIN
    UPDATE settlement_pois
    SET tier = 'temple',
        updated_at = datetime('now')
    WHERE id = NEW.location_ref
      AND type = 'religious_site';
END;

-- Promote on INSERT of an already-completed altar (e.g. seeded altars or
-- one-shot completions that skip the in_progress phase).
CREATE TRIGGER trg_consecrated_altars_promote_on_insert
AFTER INSERT ON consecrated_altars
WHEN NEW.status = 'completed' AND NEW.location_kind = 'settlement_poi'
BEGIN
    UPDATE settlement_pois
    SET tier = 'temple',
        updated_at = datetime('now')
    WHERE id = NEW.location_ref
      AND type = 'religious_site';
END;

-- Demote temple → shrine when an altar is broken_unblessed AND no other
-- completed altars remain attached to the same religious_site.
CREATE TRIGGER trg_consecrated_altars_demote_religious_site
AFTER UPDATE OF status ON consecrated_altars
WHEN NEW.status = 'broken_unblessed' AND NEW.location_kind = 'settlement_poi'
BEGIN
    UPDATE settlement_pois
    SET tier = CASE
            WHEN EXISTS (
                SELECT 1 FROM consecrated_altars ca
                WHERE ca.location_kind = 'settlement_poi'
                  AND ca.location_ref = settlement_pois.id
                  AND ca.status = 'completed'
                  AND ca.id <> NEW.id
            ) THEN 'temple'
            ELSE 'shrine'
        END,
        updated_at = datetime('now')
    WHERE id = NEW.location_ref
      AND type = 'religious_site';
END;

-- ---------------------------------------------------------------------------
-- 4. Stronghold registration column per §11.4
-- ---------------------------------------------------------------------------
ALTER TABLE strongholds ADD COLUMN registered_settlement_poi_id TEXT
    REFERENCES settlement_pois(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 4a. settlement_entrances.cumulative_investment_gp (Stage B math support).
-- Per GDD §6.2 step 5 + `acore_axioms_strongholds_and_domains.xml:641-648`,
-- the maximum-urban-population-by-total-investment table caps urban_families
-- per the cumulative urban-investment-gp spent on the settlement. Stage A
-- adds the SoT column; SettlementGrowthResolver increments it each month
-- from the consumed investment_cp. Also seeds the column with a permissive
-- floor (10000gp = Class VI founding minimum) for any existing settlements
-- that pre-date Stage B so the cap doesn't retroactively dissolve them.
-- ---------------------------------------------------------------------------
ALTER TABLE settlement_entrances ADD COLUMN cumulative_investment_gp INTEGER
    NOT NULL DEFAULT 10000;

-- ---------------------------------------------------------------------------
-- 5. characters.home_poi_id per Q-UGS-28
-- ---------------------------------------------------------------------------
ALTER TABLE characters ADD COLUMN home_poi_id TEXT
    REFERENCES settlement_pois(id) ON DELETE SET NULL;

CREATE INDEX idx_characters_home_poi
    ON characters(home_poi_id)
    WHERE home_poi_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 6. characters.npc_role per Q-UGS-29
-- ---------------------------------------------------------------------------
ALTER TABLE characters ADD COLUMN npc_role TEXT NOT NULL DEFAULT 'player'
    CHECK (npc_role IN (
        'player',
        'henchman',
        'specialist',
        'baseline_placeholder',
        'stocked',
        'named_npc',
        'on_demand'
    ));

CREATE INDEX idx_characters_npc_role
    ON characters(npc_role)
    WHERE npc_role <> 'player';

COMMIT;

PRAGMA foreign_keys = ON;
