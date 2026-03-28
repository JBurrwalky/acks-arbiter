-- Migration 005: Expand character model for full unified character system.
-- Adds saving throws, movement, class metadata, alignment, aging,
-- languages, personality stub, and incapacitated flag to characters.
-- Adds combat-relevant fields to inventory_items.
-- Creates character_powers table for modular power system.

-- Characters table: saving throws
ALTER TABLE characters ADD COLUMN save_petrification INTEGER NOT NULL DEFAULT 15;
ALTER TABLE characters ADD COLUMN save_poison_death INTEGER NOT NULL DEFAULT 14;
ALTER TABLE characters ADD COLUMN save_blast_breath INTEGER NOT NULL DEFAULT 16;
ALTER TABLE characters ADD COLUMN save_staffs_wands INTEGER NOT NULL DEFAULT 16;
ALTER TABLE characters ADD COLUMN save_spells INTEGER NOT NULL DEFAULT 17;

-- Characters table: movement
ALTER TABLE characters ADD COLUMN base_movement INTEGER NOT NULL DEFAULT 120;

-- Characters table: class metadata
ALTER TABLE characters ADD COLUMN hit_die_type TEXT NOT NULL DEFAULT '1d8';
ALTER TABLE characters ADD COLUMN max_level INTEGER NOT NULL DEFAULT 14;
ALTER TABLE characters ADD COLUMN xp_for_next_level INTEGER NOT NULL DEFAULT 2000;
ALTER TABLE characters ADD COLUMN xp_adjustment_percent INTEGER NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN title TEXT NOT NULL DEFAULT '';

-- Characters table: identity expansion
ALTER TABLE characters ADD COLUMN alignment TEXT NOT NULL DEFAULT 'neutral';

-- Characters table: aging
ALTER TABLE characters ADD COLUMN current_age INTEGER NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN age_category TEXT NOT NULL DEFAULT 'adult';

-- Characters table: languages and personality (JSON-encoded)
ALTER TABLE characters ADD COLUMN languages TEXT NOT NULL DEFAULT '[]';
ALTER TABLE characters ADD COLUMN personality TEXT NOT NULL DEFAULT '{}';

-- Characters table: dynamic state expansion
ALTER TABLE characters ADD COLUMN is_incapacitated INTEGER NOT NULL DEFAULT 0;

-- Inventory items: combat-relevant fields
ALTER TABLE inventory_items ADD COLUMN item_category TEXT NOT NULL DEFAULT 'gear';
ALTER TABLE inventory_items ADD COLUMN is_magical INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inventory_items ADD COLUMN magical_bonus INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inventory_items ADD COLUMN weapon_damage TEXT NOT NULL DEFAULT '';
ALTER TABLE inventory_items ADD COLUMN armor_ac_bonus INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inventory_items ADD COLUMN is_heavy INTEGER NOT NULL DEFAULT 0;

-- Character powers: modular power system.
-- Powers are stamped from class data at character generation.
-- Runtime systems query this table to check "does character X have power Y?"
-- Each row is one power assigned to one character, with class-specific progression.
CREATE TABLE IF NOT EXISTS character_powers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id TEXT NOT NULL REFERENCES characters(id),
    power_id TEXT NOT NULL,
    unlock_level INTEGER NOT NULL DEFAULT 1,
    conditions TEXT NOT NULL DEFAULT '[]',
    progression_data TEXT NOT NULL DEFAULT '{}',
    is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1))
);
