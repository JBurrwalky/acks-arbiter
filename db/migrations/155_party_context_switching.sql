-- Migration 155: Party-context switching (Option 1, docs/handoff_party_context_switching.md).
--
-- 1. campaigns.last_active_party_id — which party the player was watching when
--    the session was last saved. The session loader prefers it over the
--    unordered "LIMIT 1" pick so a save made while watching party B (with
--    party A suspended mid-dungeon) reloads watching B. Empty = no preference
--    (loader falls back to the legacy pick).
-- 2. party_state.pending_encounter — a deferred encounter decision for a
--    background party (switch-first flow, handoff §4.4). Serialized with
--    var_to_str (preserves Godot types); '' = none. Written when a background
--    party's journey is interrupted by an encounter; cleared when the player
--    focuses that party and the decision prompt is presented.

ALTER TABLE campaigns ADD COLUMN last_active_party_id TEXT NOT NULL DEFAULT '';
ALTER TABLE party_state ADD COLUMN pending_encounter TEXT NOT NULL DEFAULT '';
