-- Migration 033: Character preference tags for auto-distribute and UI hints
-- Part of the Party Inventory system (gdd-party-inventory.md §6.4).

CREATE TABLE IF NOT EXISTS character_preferences (
    character_id TEXT NOT NULL PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    preferred_tags TEXT NOT NULL DEFAULT '[]'
);
