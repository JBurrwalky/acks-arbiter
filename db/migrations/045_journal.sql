-- Migration 045: Journal tab schema (Phase H.2)
--
-- Three new tables backing the Journal tab per gdd-journal-tab.md v1.1.
-- All three are per-party scoped (matching the Unified Log per-party model
-- per gdd-unified-log-panel.md §13).
--
-- The Journal tab is almost entirely PROJECT-DESIGNED — ACKS RAW does not
-- specify journal mechanics; this is a UI feature for the digital game.
--
-- v1 ships fully manual; LLM auto-generation (gdd-journal-tab.md §5.4) is
-- additive when the future LLM narration system lands.


-- ---------------------------------------------------------------------------
-- narrative_entries — chronological prose entries telling the campaign story
-- ---------------------------------------------------------------------------
-- Per gdd-journal-tab.md §5.1.

CREATE TABLE IF NOT EXISTS narrative_entries (
    id TEXT PRIMARY KEY,
    party_id TEXT NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
    title TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',          -- markdown-lite (bold / italic / lists / entity-links)
    timestamp_ingame INTEGER NOT NULL DEFAULT 0,    -- Timekeeping rounds tick when entry occurred
    timestamp_realworld INTEGER NOT NULL DEFAULT 0, -- Time.get_unix_time_from_system() at authoring
    source TEXT NOT NULL DEFAULT 'manual'
        CHECK(source IN ('manual', 'llm_generated', 'llm_edited_by_player')),
    significance TEXT NOT NULL DEFAULT 'minor'
        CHECK(significance IN ('minor', 'major', 'milestone')),
    related_unified_log_entry_ids TEXT NOT NULL DEFAULT '[]',  -- JSON array of GameLog entry ids
    related_entity_ids TEXT NOT NULL DEFAULT '[]',             -- JSON array of entity ids referenced
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_narrative_entries_party
    ON narrative_entries(party_id);

CREATE INDEX IF NOT EXISTS idx_narrative_entries_party_ingame
    ON narrative_entries(party_id, timestamp_ingame DESC);


-- ---------------------------------------------------------------------------
-- player_notes — free-form player-authored notes, optionally entity-attached
-- ---------------------------------------------------------------------------
-- Per gdd-journal-tab.md §6.1. The attachment model uses parallel JSON arrays
-- so a single note can attach to multiple entities. Per resolved O-J10, a
-- note whose attached entity is later deleted is preserved with the
-- attachment becoming orphaned (rendered with a deceased-entity badge in UI).

CREATE TABLE IF NOT EXISTS player_notes (
    id TEXT PRIMARY KEY,
    party_id TEXT NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
    title TEXT NOT NULL DEFAULT '',         -- optional; UI auto-generates from body if blank
    body TEXT NOT NULL DEFAULT '',          -- markdown-lite content
    attached_entity_ids TEXT NOT NULL DEFAULT '[]',     -- JSON array of entity ids
    attached_entity_kinds TEXT NOT NULL DEFAULT '[]',   -- parallel JSON array of kinds
    category TEXT NOT NULL DEFAULT '',      -- player-assigned freeform category
    pinned INTEGER NOT NULL DEFAULT 0 CHECK(pinned IN (0, 1)),
    timestamp_ingame INTEGER NOT NULL DEFAULT 0,
    timestamp_realworld INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_player_notes_party
    ON player_notes(party_id);

-- Pinned notes surface first; updated_at descending for the rest.
CREATE INDEX IF NOT EXISTS idx_player_notes_party_pinned
    ON player_notes(party_id, pinned DESC, updated_at DESC);


-- ---------------------------------------------------------------------------
-- journal_bookmarks — pinned references to log / narrative / note targets
-- ---------------------------------------------------------------------------
-- Per gdd-journal-tab.md §7.1. Bookmarks are quick-access anchors for
-- moments the player wants to return to. Per resolved O-J11, a bookmark to
-- a deleted target survives but the "Open source" link is greyed.

CREATE TABLE IF NOT EXISTS journal_bookmarks (
    id TEXT PRIMARY KEY,
    party_id TEXT NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
    target_kind TEXT NOT NULL
        CHECK(target_kind IN ('unified_log_entry', 'narrative_entry', 'note')),
    target_id TEXT NOT NULL,                -- ID of the bookmarked item (foreign-key-shaped, not enforced — kinds vary)
    label TEXT NOT NULL DEFAULT '',         -- player-assigned label (defaults to target excerpt)
    category TEXT NOT NULL DEFAULT '',      -- optional player category
    timestamp_realworld INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_journal_bookmarks_party
    ON journal_bookmarks(party_id);

CREATE INDEX IF NOT EXISTS idx_journal_bookmarks_party_kind
    ON journal_bookmarks(party_id, target_kind);
