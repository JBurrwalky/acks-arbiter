-- Migration 076: Battle unit states (Phase 6B — per-unit per-battle state)
--
-- Per gdd-army-warfare.md §2.5 + daw_axioms_pitching_battle.xml §battle_resolution.
-- One row per assigned unit per battle. Tracks the unit's current zone, BR
-- snapshot, hits absorbed this phase, and morale state per
-- §morale_rolls L503-562.
--
-- side ∈ {attacker, defender} — derived from which army's unit this is at
-- battle start. Stored to avoid joins through army_unit_assignments.
--
-- zone ∈ {missile, skirmish, melee, reserve} — current battlefield zone.
-- Updated by redeployment (§battle_resolution step 10) or hit cascade
-- (§battle_resolution step 7).
--
-- status ∈ {engaged, wavering, fleeing, routed, destroyed, rallied} per
-- §morale_rolls.results L540-557:
--   engaged    — default; making attacks normally
--   wavering   — BR halved when attacking next battle turn (morale 6-8)
--   fleeing    — cannot attack next battle turn (morale 3-5)
--   routed     — off battlefield, counts as destroyed (morale 2-)
--   destroyed  — reduced to 0 BR via attack throws
--   rallied    — BR ½× extra when attacking next battle turn (morale 12+)
--
-- br_at_battle_start: snapshot of unit BR at battle setup, including the
-- Strategic-Ability +0.5/+1.0 division bonus and overwhelmed-commander
-- halving per §battle_ratings.strategic_ability L198-201 / .overwhelmed_commanders
-- L202-205. The resolver does NOT re-derive these per phase; the snapshot is
-- canonical for the battle.
--
-- br_current decreases as the unit absorbs hits from §battle_resolution step 6
-- and may transiently be modified by waver/rally state when computing
-- attack throws.
--
-- morale_state_modifier carries the residual morale effect on next-turn
-- attacks (waver -2 in BR; fleeing -5 = no attack).

CREATE TABLE IF NOT EXISTS battle_unit_states (
    id                              TEXT    PRIMARY KEY,
    battle_id                       TEXT    NOT NULL REFERENCES field_battles(id),
    troop_unit_id                   TEXT    NOT NULL REFERENCES troop_units(id),

    side                            TEXT    NOT NULL
        CHECK(side IN ('attacker', 'defender')),
    zone                            TEXT    NOT NULL DEFAULT 'melee'
        CHECK(zone IN ('missile', 'skirmish', 'melee', 'reserve')),
    status                          TEXT    NOT NULL DEFAULT 'engaged'
        CHECK(status IN ('engaged', 'wavering', 'fleeing', 'routed', 'destroyed', 'rallied')),

    br_at_battle_start              REAL    NOT NULL DEFAULT 0.0,
    br_current                      REAL    NOT NULL DEFAULT 0.0,
    hits_absorbed_this_phase        INTEGER NOT NULL DEFAULT 0,
    morale_state_modifier           INTEGER NOT NULL DEFAULT 0,

    parent_officer_id               TEXT    REFERENCES army_officers(id),

    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_battle_unit_states_battle
    ON battle_unit_states(battle_id);
CREATE INDEX IF NOT EXISTS idx_battle_unit_states_side
    ON battle_unit_states(battle_id, side);
CREATE INDEX IF NOT EXISTS idx_battle_unit_states_zone
    ON battle_unit_states(battle_id, side, zone);
