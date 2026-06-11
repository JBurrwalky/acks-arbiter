-- Migration 148: parties.settlement_node_id is a string POI id, not an int node.
--
-- Migration 019 added it as `INTEGER NOT NULL DEFAULT -1` for the OLD settlement
-- "street graph node" model. That model was replaced — `SettlementMapController`
-- is a string-POI context (`get_current_poi_id() -> String`,
-- `set_current_poi(poi_id: String)`, POI ids like "p1"/"gate1") — but the COLUMN
-- type was never reconciled. Everything else already treats it as a string:
--   * `PartyData.settlement_node_id` is `String` ("" = current POI id / no POI),
--   * the writers `update_party_settlement_position(..., node_id: String)` /
--     `clear_party_settlement_position` store a POI id / '',
--   * the savegame loader (`session_load_state`) passes it as `entry_poi_id` (String).
-- Only the column declaration + its INTEGER `-1` default were stale, and a fresh
-- party's `-1` default crashed `PartyData.from_db` (a `-> String` reading int -1).
-- Realign the column to TEXT DEFAULT '' ('' = not in a settlement / no POI).
--
-- SQLite 3.35+ supports ALTER TABLE ADD/DROP/RENAME COLUMN (3.51 bundled; cf.
-- migration 097 DROP COLUMN, 108-111 RENAME COLUMN). settlement_node_id carries no
-- index, FK, trigger, or generated column, so the single-column rebuild is safe.
-- Preserve any string POI already stored; normalise the stale INTEGER default to ''.
ALTER TABLE parties ADD COLUMN settlement_node_id_txt TEXT NOT NULL DEFAULT '';

UPDATE parties SET settlement_node_id_txt =
    CASE WHEN typeof(settlement_node_id) = 'text' THEN settlement_node_id ELSE '' END;

ALTER TABLE parties DROP COLUMN settlement_node_id;

ALTER TABLE parties RENAME COLUMN settlement_node_id_txt TO settlement_node_id;
