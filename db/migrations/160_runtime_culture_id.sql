-- Migration 160: culture_id on the runtime domain + settlement tables — the
-- setting→runtime handoff bridge for NPC personality generation.
--
-- The NPC personality generator biases on culture. It reads a CultureCatalogLoader
-- key (the SAME vocabulary as setting_polities.culture_id, e.g. 'abydosian') off
-- the runtime row it already loads. '' = unknown, and the generator zero-shifts
-- culture on empty — so existing campaigns are unaffected.
--
-- get_domain() / get_settlement_entrance() use SELECT * / d.*, so these columns
-- flow into their result dicts automatically — no getter change needed.
--
-- POPULATION is performed by the setting→runtime materialization (NOT YET BUILT):
-- when surviving setting_polities / setting_settlements become runtime domains /
-- settlement_entrances, a settlement gets culture_id from its
-- setting_settlements.polity_id → setting_polities.culture_id, and a domain from
-- its controlling polity. Until that handoff exists these stay '' (safe).
ALTER TABLE domains ADD COLUMN culture_id TEXT NOT NULL DEFAULT '';
ALTER TABLE settlement_entrances ADD COLUMN culture_id TEXT NOT NULL DEFAULT '';
