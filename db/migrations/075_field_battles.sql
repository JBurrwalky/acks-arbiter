-- Migration 075: Field battles (Phase 6B — DaW abstract battle resolver)
--
-- Per gdd-army-warfare.md §2.5 + daw_axioms_pitching_battle.xml §battle_resolution
-- L233-386. One row per active or completed field battle. The combination of
-- this row + battle_unit_states (076) + battle_log (077) is sufficient to
-- reconstruct a paused battle on save/load.
--
-- Renumbered from the GDD's 070 to 075 because Phase 5 took 065-069 and Phase
-- 6A took 070-074.
--
-- IDs are TEXT to match the codebase convention (the GDD's INTEGER PRIMARY KEY
-- AUTOINCREMENT spec is overridden — see Phase 6A part 1 build_log entry).
--
-- battle_phase ∈ {missile, skirmish, melee, aftermath, concluded}. The aftermath
-- phase covers casualty resolution + pursuit + spoils. concluded is terminal.
--
-- starting_bpc / current_bpc per daw_axioms_pitching_battle.xml §battle_preparation
-- .set_battle_phase_countdown L24-101. Heavy rain or snow increases the terrain
-- minimum by 1 — the battle_setup module handles that adjustment at start time.
--
-- attacker_terrain_advantage / defender_terrain_advantage per §assess_terrain_advantage
-- L104-137 (regular | advantageous | highly_advantageous). The two sides may
-- both have advantage if the attacker rolled high enough to OCCUPY advantageous
-- terrain (per the procedure rules).
--
-- attacker_choice / defender_choice ∈ {advance, hold, withdraw}; nullable until
-- both reveal in step 11.
--
-- outcome ∈ {attacker_victory, defender_victory, mutual_withdrawal_draw,
-- attacker_voluntary_withdrawal, defender_voluntary_withdrawal,
-- attacker_annihilation, defender_annihilation}. NULL while battle is active.
--
-- is_player_involved=1 means the EventScheduler auto-pauses at decision points
-- (§6.11 BattleResolver interface). =0 means the battle resolves silently in
-- one tick and the outcome posts to the unified log per §7.6.

CREATE TABLE IF NOT EXISTS field_battles (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    map_id                          TEXT    REFERENCES hex_maps(id),
    hex_q                           INTEGER NOT NULL DEFAULT 0,
    hex_r                           INTEGER NOT NULL DEFAULT 0,

    attacker_army_id                TEXT    NOT NULL REFERENCES armies(id),
    defender_army_id                TEXT    NOT NULL REFERENCES armies(id),

    terrain_type                    TEXT    NOT NULL DEFAULT 'clear_or_grass',
    starting_bpc                    INTEGER NOT NULL DEFAULT 1,
    current_bpc                     INTEGER NOT NULL DEFAULT 1,
    current_phase                   TEXT    NOT NULL DEFAULT 'missile'
        CHECK(current_phase IN ('missile', 'skirmish', 'melee', 'aftermath', 'concluded')),
    battle_turn_number              INTEGER NOT NULL DEFAULT 1,

    attacker_terrain_advantage      TEXT    NOT NULL DEFAULT 'regular'
        CHECK(attacker_terrain_advantage IN ('regular', 'advantageous', 'highly_advantageous')),
    defender_terrain_advantage      TEXT    NOT NULL DEFAULT 'regular'
        CHECK(defender_terrain_advantage IN ('regular', 'advantageous', 'highly_advantageous')),
    attacker_surprised              INTEGER NOT NULL DEFAULT 0
        CHECK(attacker_surprised IN (0, 1)),
    defender_surprised              INTEGER NOT NULL DEFAULT 0
        CHECK(defender_surprised IN (0, 1)),

    attacker_choice                 TEXT    NOT NULL DEFAULT ''
        CHECK(attacker_choice IN ('', 'advance', 'hold', 'withdraw')),
    defender_choice                 TEXT    NOT NULL DEFAULT ''
        CHECK(defender_choice IN ('', 'advance', 'hold', 'withdraw')),

    outcome                         TEXT    NOT NULL DEFAULT ''
        CHECK(outcome IN (
            '', 'attacker_victory', 'defender_victory',
            'mutual_withdrawal_draw',
            'attacker_voluntary_withdrawal', 'defender_voluntary_withdrawal',
            'attacker_annihilation', 'defender_annihilation'
        )),

    started_calendar_day            INTEGER NOT NULL DEFAULT 0,
    ended_calendar_day              INTEGER NOT NULL DEFAULT 0,
    is_player_involved              INTEGER NOT NULL DEFAULT 0
        CHECK(is_player_involved IN (0, 1)),

    weather_condition               TEXT    NOT NULL DEFAULT 'calm',
    rng_seed                        INTEGER NOT NULL DEFAULT 0,

    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_field_battles_campaign
    ON field_battles(campaign_id);
CREATE INDEX IF NOT EXISTS idx_field_battles_active
    ON field_battles(outcome) WHERE outcome = '';
CREATE INDEX IF NOT EXISTS idx_field_battles_attacker
    ON field_battles(attacker_army_id);
CREATE INDEX IF NOT EXISTS idx_field_battles_defender
    ON field_battles(defender_army_id);
