-- Migration 091: Faith block (Domain Phase 10A.2).
--
-- Tables backing the divine-caster surface (Cleric / Bladedancer / Priestess /
-- Shaman / Dwarven Craftpriest / Witch / Lightblessed Wonderworker). RAW
-- citations from ax_campaign_play.xml §divine L380-500 and §end_of_month
-- L109-112.
--
-- Per Q11 [RESOLVED 2026-05-10]: divine casters with full spell_research also
-- get the Magical Research bucket; their research projects use the Phase 10B.1
-- magic_research_projects table (separate from this migration's tables).


-- congregants: per-character congregant count + pending-gp accumulator.
-- The pending-gp accumulator tracks gp committed THIS month (via missionaries,
-- charitable spells, or ceremonial sacrifices) that will roll into next
-- month's growth roll. The growth roll happens in the domain monthly tick
-- (1d10 + Cha mod per 1,000 gp per ax_campaign_play.xml §congregant_growth
-- L20-22), AFTER which pending_growth_pending_gp is reduced by the gp that
-- triggered the rolls.
--
-- Keyed per-character (NOT per-domain) — a wandering divine caster without a
-- domain can still build a congregation in the settlement they minister to.
-- The domain-level ruler-bonus (+0..8 DP per 10 families) is computed by
-- joining congregants → characters → domains WHERE owner_character_id = ?.
CREATE TABLE IF NOT EXISTS congregants (
    character_id                   TEXT    PRIMARY KEY REFERENCES characters(id),
    count                          INTEGER NOT NULL DEFAULT 0
        CHECK(count >= 0),
    monthly_growth_pending_gp      INTEGER NOT NULL DEFAULT 0
        CHECK(monthly_growth_pending_gp >= 0),
    last_resolved_calendar_day     INTEGER NOT NULL DEFAULT 0,
    created_at                     TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                     TEXT    NOT NULL DEFAULT (datetime('now'))
);


-- character_divine_power: per-character divine-power gp balance.
-- Per ax_campaign_play.xml §extract_divine_power L460-473, divine power is
-- generated weekly via extract_divine_power activity (10 gp per 50 congregants
-- + 0..8 gp per 10 families if ruler/spiritual advisor). It is NOT auto-
-- accumulated; the caster must take the activity each week.
-- Per §perform_blood_sacrifice L475-487: chaotic divine casters generate DP
-- equal to creature XP value.
-- Per §consecrate_fields L423-439 + §consecrate_ruler L441-458: DP is spent
-- on consecration activities (2 gp per family for fields; equal to monthly
-- revenue for ruler).
-- Per §consecrate_altar L408-421 rule "Divine power may be spent in lieu of
-- gp if a humbler-looking altar is desired": DP can substitute for gp on
-- altar construction (optional, player toggle).
CREATE TABLE IF NOT EXISTS character_divine_power (
    character_id                  TEXT    PRIMARY KEY REFERENCES characters(id),
    divine_power_gp               INTEGER NOT NULL DEFAULT 0
        CHECK(divine_power_gp >= 0),
    last_extraction_calendar_day  INTEGER NOT NULL DEFAULT 0,
    created_at                    TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                    TEXT    NOT NULL DEFAULT (datetime('now'))
);


-- consecrated_altars: consecration projects (in-progress) + completed altars.
-- Per ax_campaign_play.xml §consecrate_altar L408-421: 1 day per 500 gp of
-- altar value. Aura size = 100 sq ft per 100 gp spent. A chaotic-aligned
-- altar creates a "sinkhole of evil"; lawful creates a "pinnacle of good".
-- Once consecrated, the altar's aura persists until dispelled or the altar
-- is physically broken and blessed.
--
-- location_kind: where the altar is physically situated. v1 supports the
-- four enumerated values; future variants (e.g. on-board-a-ship) can extend
-- the CHECK constraint.
-- location_ref: the id of the location (stronghold_id, settlement_entrance_id,
-- hex coordinates encoded as JSON, dungeon_room_id) per location_kind.
CREATE TABLE IF NOT EXISTS consecrated_altars (
    id                       TEXT    PRIMARY KEY,
    character_id             TEXT    NOT NULL REFERENCES characters(id),
    location_kind            TEXT    NOT NULL DEFAULT 'stronghold'
        CHECK(location_kind IN ('stronghold', 'settlement_poi', 'wilderness_hex', 'dungeon_room')),
    location_ref             TEXT    NOT NULL DEFAULT '',
    gp_invested              INTEGER NOT NULL DEFAULT 0
        CHECK(gp_invested >= 0),
    dp_substituted_gp        INTEGER NOT NULL DEFAULT 0
        CHECK(dp_substituted_gp >= 0),
    alignment                TEXT    NOT NULL DEFAULT 'lawful'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    aura_size_sq_ft          INTEGER NOT NULL DEFAULT 0
        CHECK(aura_size_sq_ft >= 0),
    completion_pct           INTEGER NOT NULL DEFAULT 0
        CHECK(completion_pct BETWEEN 0 AND 100),
    status                   TEXT    NOT NULL DEFAULT 'in_progress'
        CHECK(status IN ('in_progress', 'completed', 'broken_unblessed')),
    started_calendar_day     INTEGER NOT NULL DEFAULT 0,
    completed_calendar_day   INTEGER,
    created_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_consecrated_altars_character ON consecrated_altars(character_id);
CREATE INDEX IF NOT EXISTS idx_consecrated_altars_status    ON consecrated_altars(status);


-- pending_divine_effects: queue of delayed / continuous effects produced by
-- consecrate_fields (one-shot land-value bump fires on next monthly tick) and
-- consecrate_ruler (12-month buff window). Future divine effect kinds can
-- extend the effect_kind CHECK constraint without schema change.
--
-- Lifecycle:
--   * status='pending' AND applies_at_calendar_day <= now → apply the effect,
--     transition to 'applied'.
--   * status='applied' AND expires_at_calendar_day > 0 AND expires_at <= now
--     → transition to 'expired'. (One-shot effects set expires_at = 0 so they
--     stay 'applied' permanently after firing.)
--   * Continuous buffs (consecrate_ruler) are checked each monthly tick: if
--     a row exists with status='applied' AND expires_at > now, apply the
--     buff this month.
--
-- effect_payload_json: per-effect data shape. Examples:
--   consecrate_fields_land_value: {"delta_gp_per_family": +1, "peasant_families": N}
--   consecrate_ruler_buff:        {"base_morale_bonus": 1, "vassal_loyalty_bonus": 1, "double_vagary_rolls": true}
CREATE TABLE IF NOT EXISTS pending_divine_effects (
    id                       TEXT    PRIMARY KEY,
    domain_id                TEXT    REFERENCES domains(id),
    character_id             TEXT    REFERENCES characters(id),
    effect_kind              TEXT    NOT NULL
        CHECK(effect_kind IN (
            'consecrate_fields_land_value',
            'consecrate_ruler_buff'
        )),
    effect_payload_json      TEXT    NOT NULL DEFAULT '{}',
    issued_calendar_day      INTEGER NOT NULL DEFAULT 0,
    applies_at_calendar_day  INTEGER NOT NULL DEFAULT 0,
    expires_at_calendar_day  INTEGER NOT NULL DEFAULT 0,
    status                   TEXT    NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending', 'applied', 'expired', 'cancelled')),
    created_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    CHECK ((domain_id IS NOT NULL) OR (character_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_pending_divine_effects_apply
    ON pending_divine_effects(applies_at_calendar_day, status);
CREATE INDEX IF NOT EXISTS idx_pending_divine_effects_expire
    ON pending_divine_effects(expires_at_calendar_day, status)
    WHERE status = 'applied';
CREATE INDEX IF NOT EXISTS idx_pending_divine_effects_domain
    ON pending_divine_effects(domain_id);
CREATE INDEX IF NOT EXISTS idx_pending_divine_effects_character
    ON pending_divine_effects(character_id);
