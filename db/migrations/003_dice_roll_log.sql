-- Migration 003: Dice roll log
--
-- Per-session dice roll log. Records every roll resolved by DiceSystem.
-- Cleared on session end (EventBus.session_ended). Capped at 200 rows via
-- DiceSystem's auto-prune logic (oldest deleted when limit exceeded).
-- Exported on request via DiceSystem.export_roll_log().

CREATE TABLE IF NOT EXISTS dice_rolls (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    game_day            INTEGER  NOT NULL DEFAULT 0,
    roll_type           TEXT     NOT NULL DEFAULT '',
    sides               INTEGER  NOT NULL,
    count               INTEGER  NOT NULL DEFAULT 1,
    modifier            INTEGER  NOT NULL DEFAULT 0,
    individual_results  TEXT     NOT NULL DEFAULT '[]',  -- JSON array e.g. "[4, 12, 3]"
    raw_total           INTEGER  NOT NULL,
    modified_total      INTEGER  NOT NULL,
    was_overridden      INTEGER  NOT NULL DEFAULT 0,     -- 1 = forced via override queue
    was_player_entered  INTEGER  NOT NULL DEFAULT 0,     -- 1 = player typed result manually
    created_at          DATETIME NOT NULL DEFAULT (datetime('now'))
);
