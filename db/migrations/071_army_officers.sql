-- Migration 071: Army officers (Phase 6A — three-tier hierarchy)
--
-- Per gdd-army-warfare.md §2.2 and daw_armies_recruitment.xml §officers
-- L751-789. The hierarchy is exactly three ranks:
--   army_leader        — exactly one per army; equals armies.command_character_id
--   division_commander — one per division; reports to army_leader
--   lieutenant         — optional, one per unit; reports to a division_commander
--
-- Leadership / Strategic / Morale Modifier per RAW formulas in
-- gdd-army-warfare.md §3.3. Stored (not computed-on-read) so the field-battle
-- resolver runs deterministically against a snapshot. Recompute is triggered
-- by character mutation (level up, retraining, magical effect) — handled by
-- the army_repository on character-change events.
--
-- derivation_source controls how the three abilities were derived:
--   pc                   — full RAW formula on PC
--   henchman             — full RAW formula on henchman character row
--   mercenary_officer    — fixed table per daw_armies_recruitment.xml §mercenary_officer_characteristics L993-1006
--   monster              — HD-driven formula per §officer_characteristics L763-789 (monster column)
--   named_npc            — derived from rolled stats (vagary-generated)
--
-- monthly_wage_gp is non-zero only for mercenary_officer (and named_npc
-- generated as mercenary). PC/henchman/follower officers earn nothing as
-- officers per RAW (their wage is via henchman bonus / class).
--
-- removed_day is set to the game-day on which the officer left the army;
-- past officers are kept for audit (the army's officer log surfaces them).

CREATE TABLE IF NOT EXISTS army_officers (
    id                       TEXT    PRIMARY KEY,
    army_id                  TEXT    NOT NULL REFERENCES armies(id),
    character_id             TEXT    NOT NULL REFERENCES characters(id),
    rank                     TEXT    NOT NULL
        CHECK(rank IN ('army_leader', 'division_commander', 'lieutenant', 'former_commander')),
    parent_officer_id        TEXT    REFERENCES army_officers(id),
    leadership_ability       INTEGER NOT NULL DEFAULT 4,
    strategic_ability        INTEGER NOT NULL DEFAULT 0,
    morale_modifier          INTEGER NOT NULL DEFAULT 0,
    derivation_source        TEXT    NOT NULL DEFAULT 'pc'
        CHECK(derivation_source IN (
            'pc', 'henchman', 'mercenary_officer', 'monster', 'named_npc'
        )),
    monthly_wage_gp          INTEGER NOT NULL DEFAULT 0,
    appointed_calendar_day   INTEGER NOT NULL DEFAULT 0,
    removed_calendar_day     INTEGER NOT NULL DEFAULT 0,
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_army_officers_army
    ON army_officers(army_id);
CREATE INDEX IF NOT EXISTS idx_army_officers_character
    ON army_officers(character_id);
CREATE INDEX IF NOT EXISTS idx_army_officers_parent
    ON army_officers(parent_officer_id);

-- Active-officers view filter (no SQLite partial-unique-index for "exactly
-- one army_leader per army with removed_calendar_day = 0" — enforced in
-- application code via army_validator instead).
