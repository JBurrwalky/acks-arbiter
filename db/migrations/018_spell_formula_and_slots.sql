-- Migration 018: Arcane spell formula tracking + daily expended slot tracking

-- Arcane casters only: spells for which the character possesses the formula.
-- character_spells tracks the active repertoire; this tracks what has been acquired.
-- Allows "knows formula but not in current repertoire" (e.g., capacity exceeded).
CREATE TABLE IF NOT EXISTS character_spell_formulas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id TEXT NOT NULL REFERENCES characters(id),
    spell_key TEXT NOT NULL,
    spell_level INTEGER NOT NULL,
    UNIQUE(character_id, spell_key)
);

-- Tracks spell slots expended today per spell level per character.
-- Cleared on rest (8 hours + 1 hour prayer/study).
-- Replaces the per-spell is_memorized proxy on character_spells.
CREATE TABLE IF NOT EXISTS character_spell_slots_expended (
    character_id TEXT NOT NULL REFERENCES characters(id),
    spell_level INTEGER NOT NULL,
    expended INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (character_id, spell_level)
);

-- Migrate existing arcane casters' character_spells rows to the formula table.
-- Arcane classes in ACKS 1e: mage, elven_spellsword, elven_nightblade.
INSERT OR IGNORE INTO character_spell_formulas (character_id, spell_key, spell_level)
SELECT cs.character_id, cs.spell_key, cs.spell_level
FROM character_spells cs
JOIN characters c ON cs.character_id = c.id
WHERE c.character_class IN ('mage', 'elven_spellsword', 'elven_nightblade');

INSERT INTO schema_migrations (version) VALUES (18);
