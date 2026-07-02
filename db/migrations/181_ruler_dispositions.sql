-- Migration 181: ruler_dispositions — the StrategicDisposition strategic layer,
-- one row per NPC ruler (gdd-ruler-ai.md §10, approved by Jedidiah 2026-06-28;
-- struct per gdd-npc-personality.md §8.2). Derived — and regenerable — from
-- characters.personality + characters.alignment via StrategicDispositionBuilder,
-- so a drop-and-rebuild is non-destructive in practice. Kept as its own table
-- (not folded into the personality JSON) to keep the strategic layer queryable.
-- The 7 strategic-axis ints are a SNAPSHOT of the personality axes at build
-- time; the 8 weights are the §8.3 derivation outputs (floats clamped 0-1).
-- aggression_toward / alliance_preference are serialized {realm_id: float}
-- JSON dicts — empty ('{}') when realm relations are absent (gdd-ruler-ai.md
-- §4.3 graceful degradation). motivation_primary/secondary are carried so the
-- row round-trips the full §8.2 struct without re-reading the personality JSON.
CREATE TABLE IF NOT EXISTS ruler_dispositions (
    character_id TEXT PRIMARY KEY REFERENCES characters(id),
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    motivation_primary TEXT NOT NULL DEFAULT '',
    motivation_secondary TEXT NOT NULL DEFAULT '',
    epistemic_curiosity INTEGER NOT NULL DEFAULT 5,
    societal_orthodoxy INTEGER NOT NULL DEFAULT 5,
    affective_compassion INTEGER NOT NULL DEFAULT 5,
    stress_reactivity INTEGER NOT NULL DEFAULT 5,
    self_interest INTEGER NOT NULL DEFAULT 5,
    in_group_loyalty INTEGER NOT NULL DEFAULT 5,
    mysticism INTEGER NOT NULL DEFAULT 5,
    research_weight REAL NOT NULL DEFAULT 0.0,
    religious_weight REAL NOT NULL DEFAULT 0.0,
    economic_weight REAL NOT NULL DEFAULT 0.0,
    military_weight REAL NOT NULL DEFAULT 0.0,
    expansion_weight REAL NOT NULL DEFAULT 0.0,
    fortification_weight REAL NOT NULL DEFAULT 0.0,
    diplomatic_weight REAL NOT NULL DEFAULT 0.0,
    oppression_weight REAL NOT NULL DEFAULT 0.0,
    crisis_response TEXT NOT NULL DEFAULT 'defensive'
        CHECK(crisis_response IN ('aggressive', 'defensive', 'diplomatic', 'cautious')),
    aggression_toward TEXT NOT NULL DEFAULT '{}',
    alliance_preference TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ruler_dispositions_campaign
    ON ruler_dispositions(campaign_id);
