-- Migration 006: Spell hook infrastructure
-- Adds active_effects table for persistent spell effect tracking.
-- Adds damage_type and material columns to inventory_items.

-- active_effects: persisted active spell effects per campaign.
-- Runtime-only fields (applied_modifiers, applied_flags, applied_conditions) store
-- JSON arrays of { character_id, stat_key/flag_key/condition_key, source_id }
-- so the effect can be cleanly removed from CharacterData on load or expiry.
CREATE TABLE IF NOT EXISTS active_effects (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    spell_key TEXT NOT NULL,
    caster_id TEXT NOT NULL,
    caster_level INTEGER NOT NULL DEFAULT 1,
    target_ids TEXT NOT NULL DEFAULT '[]',           -- JSON Array[String]
    effect_type TEXT NOT NULL DEFAULT 'modifier'
        CHECK(effect_type IN ('modifier', 'flag', 'entity', 'condition', 'instant')),
    applied_modifiers TEXT NOT NULL DEFAULT '[]',    -- JSON Array[Dict]
    applied_conditions TEXT NOT NULL DEFAULT '[]',   -- JSON Array[Dict]
    applied_flags TEXT NOT NULL DEFAULT '[]',        -- JSON Array[Dict]
    duration_type TEXT NOT NULL DEFAULT 'rounds'
        CHECK(duration_type IN ('rounds', 'turns', 'hours', 'days', 'permanent', 'concentration')),
    duration_remaining INTEGER NOT NULL DEFAULT -1,  -- -1 = permanent
    requires_concentration INTEGER NOT NULL DEFAULT 0 CHECK(requires_concentration IN (0, 1)),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    metadata TEXT NOT NULL DEFAULT '{}',             -- JSON Dictionary (spell-specific extras)
    created_at_round INTEGER NOT NULL DEFAULT 0
);

-- Add damage_type and material to inventory_items (migration 006 additions)
ALTER TABLE inventory_items ADD COLUMN damage_type TEXT NOT NULL DEFAULT 'physical';
ALTER TABLE inventory_items ADD COLUMN material TEXT NOT NULL DEFAULT '';
