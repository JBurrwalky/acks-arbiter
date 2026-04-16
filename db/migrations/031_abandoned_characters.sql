-- Characters left behind in a dungeon (incapacitated/dead, not carried out).
-- They survive 1 game day (1440 rounds) after abandoned_at, then die.
CREATE TABLE IF NOT EXISTS abandoned_characters (
    character_id TEXT NOT NULL,
    dungeon_id   TEXT NOT NULL,
    level_num    INTEGER NOT NULL DEFAULT 1,
    col          INTEGER NOT NULL DEFAULT 0,
    row          INTEGER NOT NULL DEFAULT 0,
    abandoned_at INTEGER NOT NULL DEFAULT 0,
    resolved     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (character_id, dungeon_id)
);
