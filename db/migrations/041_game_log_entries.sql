-- Migration 041: persisted Unified Log entries per party.
--
-- The GameLog autoload (engine/autoloads/game_log.gd) is the single canonical
-- store for game events. It is in-memory during the session; on
-- EventBus.campaign_saved, the most recent PERSIST_LIMIT_PER_PARTY (= 100)
-- entries per party are written here, and on EventBus.campaign_loaded they
-- are read back so players see continuity in the bottom-bar log across
-- save/load. See gdd-unified-log-panel.md §13 (save retention) and
-- gdd-ui-architecture.md §6.1.
--
-- One row per persisted entry. The active in-memory store is unbounded; this
-- table is the trimmed save-game slice. Consumers should NEVER read this
-- table directly — go through GameLog.get_all_entries() / get_entries().
--
-- Schema fields mirror the in-memory entry dictionary documented on
-- EventBus.log_entry_added (party_id / id / timestamp / game_time / category /
-- type / summary / actor_id / target_id / data).

CREATE TABLE game_log_entries (
	row_id      INTEGER PRIMARY KEY AUTOINCREMENT,
	party_id    TEXT NOT NULL DEFAULT '',
	entry_id    INTEGER NOT NULL,
	timestamp   INTEGER NOT NULL DEFAULT 0,
	game_time   INTEGER NOT NULL DEFAULT 0,
	category    TEXT NOT NULL DEFAULT '',
	type        TEXT NOT NULL DEFAULT '',
	summary     TEXT NOT NULL DEFAULT '',
	actor_id    TEXT NOT NULL DEFAULT '',
	target_id   TEXT NOT NULL DEFAULT '',
	data_json   TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_game_log_entries_party
	ON game_log_entries(party_id, entry_id);
