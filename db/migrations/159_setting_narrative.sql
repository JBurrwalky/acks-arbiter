-- Migration 159: setting_narrative (Layer 7 §10 narrative cache).
--
-- Layer 7 EXPLAINS what the generator already built — it never changes a
-- mechanical fact. Each row is one cached narrative block: a deterministic
-- template by default (is_fallback=1), upgradeable in place to LLM-authored
-- prose (is_fallback=0) when a provider is configured. Written only by the
-- generator (NarrativeGenerator), frozen by the Layer-8 lock like the rest of
-- the setting_* tables. id = "<kind>" for singletons (timeline/brief) or
-- "<kind>:<subject_id>" for per-entity blocks.
CREATE TABLE IF NOT EXISTS setting_narrative (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    kind TEXT NOT NULL DEFAULT 'brief' CHECK(kind IN (
        'timeline', 'brief', 'realm', 'culture', 'religion',
        'dungeon', 'poi', 'quest', 'rumor', 'region')),
    subject_id TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    is_fallback INTEGER NOT NULL DEFAULT 1 CHECK(is_fallback IN (0, 1)),
    PRIMARY KEY (campaign_id, id)
);
