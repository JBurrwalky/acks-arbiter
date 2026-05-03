-- Migration 041: drop the legacy `known_city_routes` table.
--
-- Introduced by migration 030 to support the urban Navigation throw exemption
-- system in the prior settlement exploration UI design (gdd-settlement-exploration-ui.md
-- v1 §3.3.4). The 2026-05-02 v2 rewrite of that GDD removed the urban Navigation
-- throw entirely (ACKS Navigation rules are wilderness-only per
-- acore_proficiencies_rules_and_catalog.xml:872). With the consumer gone, the
-- table is orphaned.
--
-- The sibling `visited_pois` table (also migration 030) is retained — its role
-- shifts from "discovery visibility gating" (no longer used; v2 shows all PoIs
-- on entry) to "narrative tracking" (quests/dialogue can ask "has the party
-- ever been to this PoI?").

DROP TABLE IF EXISTS known_city_routes;
