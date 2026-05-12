-- Migration 095: Construct creation (Domain Phase 10B.1e).
--
-- Per acore-campaign-general-and-magic-research.xml §constructs L373-415.
--
-- Two tables track the RAW design/create distinction:
--   * construct_designs — the formula / template (HD, AC, attacks, damage,
--     special_abilities_json). One row per unique construct design the
--     caster has researched. RAW: "A successful design creates a formula
--     that can later be used to create the construct" (L400). Reusable —
--     once a design exists for a caster, future create attempts can skip
--     the design step.
--   * construct_instances — actual constructs in the world (one row per
--     body). FK to construct_designs. Tracks current location + status.
--     RAW: "The remains of a destroyed construct may serve as a sample"
--     (L389), so status='destroyed' rows are kept (not deleted) for the
--     sample-from-remains future-polish path.
--
-- v1 10B.1e simplification: a single research_magic[construct] project
-- creates BOTH rows in one transaction — design + create combined. The
-- two-step RAW split (design separately to save on repeat-create cost) is
-- a future polish item. Future polish: add a `use_existing_design_id`
-- param to skip the design step + halve the cost/time.
--
-- Eligibility (enforced in the handler):
--   * Arcane / divine spellcasters L11+ may design + create constructs.
--   * Dwarven craftpriests L9+ may design + create constructs.
--   * Max HD = 2 × caster's class level.


CREATE TABLE IF NOT EXISTS construct_designs (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    creator_character_id        TEXT    NOT NULL REFERENCES characters(id),
    name                        TEXT    NOT NULL,
    -- The construct's intrinsic stats per RAW §constructs §design_rules
    -- L405-414.
    hit_dice                    INTEGER NOT NULL DEFAULT 1
        CHECK(hit_dice >= 1),
    armor_class                 INTEGER NOT NULL DEFAULT 0
        CHECK(armor_class >= 0),
    attacks_per_round           INTEGER NOT NULL DEFAULT 1
        CHECK(attacks_per_round BETWEEN 1 AND 4),
    -- Total max damage per round across all attacks. RAW L411: <= 3 × HD.
    max_damage_per_round        INTEGER NOT NULL DEFAULT 1
        CHECK(max_damage_per_round >= 1),
    -- Damage as a dice expression (e.g. "1d8", "2d6+1"). Free-text for v1.
    damage_expression           TEXT    NOT NULL DEFAULT '1d6',
    -- JSON array of special-ability names. RAW: standard immunity package
    -- (poison/gas/charm/hold/sleep) counts as one ability; each additional
    -- immunity or special attack is one more ability. v1 free-form names.
    special_abilities_json      TEXT    NOT NULL DEFAULT '[]',
    -- Cost in gp at design-time per RAW L395 / L382: 2,000 × HD + 5,000 ×
    -- special_abilities count. Denormalized for fast queries.
    gp_cost_total               INTEGER NOT NULL DEFAULT 0
        CHECK(gp_cost_total >= 0),
    days_to_design              INTEGER NOT NULL DEFAULT 0
        CHECK(days_to_design >= 0),
    -- The library used to design (FK to libraries; nullable for tests /
    -- v1 simplification of combined design+create projects).
    library_id                  TEXT REFERENCES libraries(id),
    designed_calendar_day       INTEGER NOT NULL DEFAULT 0,
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_construct_designs_creator
    ON construct_designs (creator_character_id);
CREATE INDEX IF NOT EXISTS idx_construct_designs_hd
    ON construct_designs (hit_dice);


CREATE TABLE IF NOT EXISTS construct_instances (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    design_id                   TEXT    NOT NULL REFERENCES construct_designs(id),
    -- The character who created (built) this instance. Same as designer
    -- in v1 (combined design+create), but separated in the schema so
    -- future-polish "create from another's formula" path works.
    creator_character_id        TEXT    NOT NULL REFERENCES characters(id),
    -- Optional owner override (e.g., the construct is gifted / sold to
    -- another character). NULL means owner = creator.
    owner_character_id          TEXT REFERENCES characters(id),
    name                        TEXT    NOT NULL,
    hp_max                      INTEGER NOT NULL DEFAULT 1
        CHECK(hp_max >= 1),
    hp_current                  INTEGER NOT NULL DEFAULT 1,
    -- Where the construct currently is. v1 uses the same (kind, ref)
    -- pair convention as consecrated_altars. Active constructs typically
    -- live at the creator's stronghold; under-construction ones are at
    -- the workshop.
    location_kind               TEXT    NOT NULL DEFAULT 'stronghold'
        CHECK(location_kind IN ('stronghold', 'with_owner', 'wilderness_hex', 'dungeon_room', 'other')),
    location_ref                TEXT    NOT NULL DEFAULT '',
    workshop_id                 TEXT REFERENCES workshops(id),
    -- Cost / time on creation (for audit; RAW says cost is the same as
    -- design, so this matches the linked design's gp_cost_total).
    gp_cost_total               INTEGER NOT NULL DEFAULT 0,
    days_to_create              INTEGER NOT NULL DEFAULT 0,
    status                      TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'damaged', 'inactive', 'destroyed')),
    created_calendar_day        INTEGER NOT NULL DEFAULT 0,
    destroyed_calendar_day      INTEGER,
    notes                       TEXT    NOT NULL DEFAULT '',
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_construct_instances_creator
    ON construct_instances (creator_character_id);
CREATE INDEX IF NOT EXISTS idx_construct_instances_design
    ON construct_instances (design_id);
CREATE INDEX IF NOT EXISTS idx_construct_instances_status
    ON construct_instances (status);
