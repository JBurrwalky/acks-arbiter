-- Migration 030: Settlement route memory and POI discovery tracking
--
-- Supports the menu-driven settlement exploration UI (gdd-settlement-exploration-ui.md).
-- Navigation throw exemptions require knowing which routes the party has traveled
-- and which POIs it has visited. POI discovery controls what appears in the PoI list.

-- Routes the party has successfully traveled (origin POI → destination POI).
-- Used for Navigation throw exemptions (§3.3.4): a previously traveled route
-- means no Navigation throw is required for that specific origin→dest pair.
CREATE TABLE IF NOT EXISTS known_city_routes (
    id                  TEXT    PRIMARY KEY,
    campaign_id         TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_id       TEXT    NOT NULL,
    origin_poi_id       TEXT    NOT NULL,
    destination_poi_id  TEXT    NOT NULL,
    UNIQUE(campaign_id, settlement_id, origin_poi_id, destination_poi_id)
);

CREATE INDEX IF NOT EXISTS idx_known_city_routes_lookup
    ON known_city_routes(campaign_id, settlement_id);

-- POIs the party has visited or discovered. Controls PoI list visibility
-- and the +4 Navigation throw modifier for visited-but-not-routed destinations.
-- discovery_method: "visited" (arrived at POI), "obvious" (auto-discovered on
-- settlement entry), "meander" (discovered while meandering through district),
-- "rumor" (revealed via Gather Information).
CREATE TABLE IF NOT EXISTS visited_pois (
    id                  TEXT    PRIMARY KEY,
    campaign_id         TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_id       TEXT    NOT NULL,
    poi_id              TEXT    NOT NULL,
    discovered_at_round INTEGER NOT NULL DEFAULT 0,
    discovery_method    TEXT    NOT NULL DEFAULT 'visited',
    UNIQUE(campaign_id, settlement_id, poi_id)
);

CREATE INDEX IF NOT EXISTS idx_visited_pois_lookup
    ON visited_pois(campaign_id, settlement_id);
