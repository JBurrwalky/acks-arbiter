-- Migration 170: setting_domains (Realms/Titles refactor Phase 5 — finalization
-- decomposition). The Layer-4 history sim runs at the sovereign + war-vassal scale;
-- this table holds the deterministic FINALIZATION decomposition of each civ polity's
-- OWN territory into the RAW 4-6 vassal hierarchy (acore-setting-construction-rules.xml
-- :90-110 political_divisions_of_realms) down to the 24-mile County floor — one leaf
-- domain per settled hex (req C: each settled hex its own ruler), interior grouping
-- nodes for the Duchy+ tiers between the polity ruler and the county leaves. Every node
-- records a seat hex (req B). Written by HistorySimulator._decompose_all (structure +
-- ruler class/level), named by NameGenerator (ruler_name/realm_name, Layer 5), frozen
-- by the Layer-8 lock like the rest of setting_*. Read by the Review Vassalage tab;
-- runtime seat materialization is deferred to M2b.
--
-- id encoding: leaf domains "dom_<q>_<r>" (unique per hex); interior grouping nodes
-- "idom_<q>_<r>_<depth>" (seat hex + depth disambiguates parent vs child sharing a seat).
-- liege_domain_id = parent domain within the same polity; '' = directly under the
-- polity ruler (setting_polities). polity_id = the owning polity (sovereign or war-vassal;
-- every alive civ polity decomposes its own crownland, so the union accounts for all
-- families). Beastman / clanhold polities are not decomposed (no feudal title ladder).
CREATE TABLE IF NOT EXISTS setting_domains (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    polity_id TEXT NOT NULL,
    liege_domain_id TEXT NOT NULL DEFAULT '',
    tier_index INTEGER NOT NULL DEFAULT 0 CHECK(tier_index BETWEEN 0 AND 6),
    title TEXT NOT NULL DEFAULT '',
    ruler_class TEXT NOT NULL DEFAULT '',
    ruler_level INTEGER NOT NULL DEFAULT 0,
    ruler_name TEXT NOT NULL DEFAULT '',
    realm_name TEXT NOT NULL DEFAULT '',
    seat_q INTEGER NOT NULL DEFAULT 0,
    seat_r INTEGER NOT NULL DEFAULT 0,
    families INTEGER NOT NULL DEFAULT 0,
    hex_count INTEGER NOT NULL DEFAULT 0,
    depth INTEGER NOT NULL DEFAULT 0,
    is_personal_domain INTEGER NOT NULL DEFAULT 0 CHECK(is_personal_domain IN (0, 1)),
    PRIMARY KEY (campaign_id, id)
);

CREATE INDEX IF NOT EXISTS idx_setting_domains_polity
    ON setting_domains(campaign_id, polity_id);
