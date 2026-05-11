-- Migration 073: Army supply state (Phase 6A — weighted-line supply geometry)
--
-- Per gdd-army-warfare.md §2.4 and daw_campaigning_armies.xml §supply L226-374.
-- One row per army (1:1) holds the recomputed weekly supply cost, current
-- stockpile, supply-line status, and the per-domain requisition cooldowns.
--
-- supply_line_status enum:
--   in_supply                    — base assigned, stockpile ≥ cost, weighted ≤ 16, no enemy on path
--   out_of_supply_blocked        — path passes through enemy hex (§blocked_supply L298-302)
--   out_of_supply_overextended   — weighted length > 16 hexes / 96 miles (§overextended_supply L303-306)
--   out_of_supply_no_base        — no supply_base_stronghold_id OR base value < weekly cost
--   simplified                   — using simplified-supply rule (§simplified_supply L371-374)
--
-- weekly_supply_cost_gp: recomputed by supply_calculator.gd whenever
-- composition changes per §supply_cost L233-241 (60gp infantry / 240gp cavalry
-- per company-sized unit, scaled by unit-scale, ×2 if no quartermaster, ×4 if
-- carnivorous).
--
-- supply_line_weighted_hexes: weighted path length per the rules table at
-- §overextended_supply.weighted_length_rules L307-320 (barren ×4, jungle ×2,
-- hills/woods ×1.5, road ×0.25, settled ×0.33, navigable waterway ×0).
--
-- requisition_cooldowns_json: keyed by domain_id, value = last requisitioned
-- calendar_day_index. The 6-month cooldown per RAW §requisition_rules L327-330
-- is enforced by the requisition handler reading this map.
--
-- partial_supply_priority_json: ordered Array[String] of troop_unit_ids
-- specifying which units the army leader feeds first when partially supplied
-- per §lack_of_supply.partial_supply_allocation L364-368.

CREATE TABLE IF NOT EXISTS army_supply_state (
    army_id                       TEXT    PRIMARY KEY REFERENCES armies(id),
    supply_base_stronghold_id     TEXT    REFERENCES strongholds(id),
    supply_line_status            TEXT    NOT NULL DEFAULT 'out_of_supply_no_base'
        CHECK(supply_line_status IN (
            'in_supply',
            'out_of_supply_blocked',
            'out_of_supply_overextended',
            'out_of_supply_no_base',
            'simplified'
        )),
    weekly_supply_cost_gp         INTEGER NOT NULL DEFAULT 0,
    current_stockpile_gp          INTEGER NOT NULL DEFAULT 0,
    supply_line_weighted_hexes    INTEGER NOT NULL DEFAULT 0,
    last_supply_check_calendar_day INTEGER NOT NULL DEFAULT 0,
    consecutive_unsupplied_weeks  INTEGER NOT NULL DEFAULT 0,
    requisition_cooldowns_json    TEXT    NOT NULL DEFAULT '{}',
    partial_supply_priority_json  TEXT    NOT NULL DEFAULT '[]',
    created_at                    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_army_supply_state_status
    ON army_supply_state(supply_line_status);
