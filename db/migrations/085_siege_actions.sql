-- Migration 085: siege_actions — Phase 9B per-action ledger.
--
-- Source of truth for the UI's per-day siege history. Every bombardment day,
-- artillery duel, mining tick, repair, hijink, supplies tick, assault turn,
-- sally, and surrender posts a row here.
--
-- payload_json carries the full modifier breakdown for the Inspect-math
-- affordance per gdd-army-warfare.md §6.11 / O-A-8.
--
-- related_battle_id links to field_battles for assault_turn / sally rows so
-- the UI can deep-link from a siege action into the battle log.
--
-- subversion_breach_expired (added per RAW L450 + 2026-05-09 confirmation):
-- breaches created by subversion must be exploited with an assault on the same
-- calendar_day; otherwise the breach decrements at the next daily tick. The
-- daily-tick reaper writes a 'subversion_breach_expired' action when a pending
-- breach times out.

CREATE TABLE IF NOT EXISTS siege_actions (
    id                  TEXT    PRIMARY KEY,
    siege_id            TEXT    NOT NULL REFERENCES sieges(id),
    calendar_day        INTEGER NOT NULL,
    actor_side          TEXT    NOT NULL
        CHECK(actor_side IN ('besieger', 'defender')),
    action_type         TEXT    NOT NULL
        CHECK(action_type IN (
            'bombardment',
            'artillery_duel',
            'siege_mining_progress',
            'siege_mining_detonation',
            'countermining_progress',
            'magic_reduction',
            'arson',
            'subversion',
            'subversion_breach_expired',
            'smuggling',
            'sabotage',
            'repair',
            'sally',
            'surrender_offer',
            'surrender_accepted',
            'assault_turn',
            'circumvallation_progress',
            'supplies_consumed',
            'starvation_penalty',
            'mining_accident',
            'blockade_completed'
        )),
    shp_damage_dealt    INTEGER NOT NULL DEFAULT 0,
    shp_repaired        INTEGER NOT NULL DEFAULT 0,
    breaches_added      INTEGER NOT NULL DEFAULT 0,
    supplies_delta_cp   INTEGER NOT NULL DEFAULT 0,
    related_battle_id   TEXT    REFERENCES field_battles(id),
    payload_json        TEXT    NOT NULL DEFAULT '{}',
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_siege_actions_siege
    ON siege_actions(siege_id, calendar_day);
CREATE INDEX IF NOT EXISTS idx_siege_actions_type
    ON siege_actions(siege_id, action_type);
