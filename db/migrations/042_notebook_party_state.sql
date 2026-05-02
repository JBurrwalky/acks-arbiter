-- Migration 042: per-party Management Notebook state.
--
-- The NotebookState autoload (engine/autoloads/notebook_state.gd) owns
-- per-party {last_active_tab, last_active_entity_id, per_tab_substate}. State
-- is in-memory during the session; persisted here on session end and on
-- party-switch transitions so the player returns to the same tab + entity
-- when reopening the notebook for that party. See gdd-management-notebook.md
-- §4 (state persistence) and gdd-ui-architecture.md §3.7 / §3.9.
--
-- One row per party. Tab id is one of the eight notebook tabs:
--   character / inventory / party / henchmen / troops / domain / journal / quests
--
-- per_tab_substate is opaque JSON owned by the notebook (sub-tab indices,
-- scroll positions, dropdown selections). Phase β writes/reads it as opaque;
-- per-tab GDDs in Phase γ define its schema for their tab.

CREATE TABLE notebook_state (
    party_id              TEXT PRIMARY KEY,
    last_active_tab       TEXT NOT NULL DEFAULT 'character',
    last_active_entity_id TEXT NOT NULL DEFAULT '',
    per_tab_substate      TEXT NOT NULL DEFAULT '{}',
    updated_at            TEXT NOT NULL DEFAULT ''
);
