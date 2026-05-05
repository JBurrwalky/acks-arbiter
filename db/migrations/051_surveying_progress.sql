-- Migration 051: Survey progress per (party, hex) (Wilderness closure Phase 4).
-- Per le_wilderness_lair_rules.xml §land_surveying — Land Surveying assessment
-- target is 18+ base, +4 cumulative per successful hex search the party has
-- conducted in the same hex.
--
-- The row is created on first search or first survey assessment in the hex,
-- and persists for the rest of the campaign. `last_estimate` holds the most
-- recent successful Land Surveying assessment (-1 = never assessed).
-- `last_estimate_correct` tracks whether that estimate was true (1) or
-- a false reading from a natural-1 (0).

CREATE TABLE IF NOT EXISTS survey_progress (
    campaign_id            TEXT    NOT NULL REFERENCES campaigns(id),
    map_id                 TEXT    NOT NULL REFERENCES hex_maps(id),
    party_id               TEXT    NOT NULL REFERENCES parties(id),
    hex_q                  INTEGER NOT NULL,
    hex_r                  INTEGER NOT NULL,
    successful_searches    INTEGER NOT NULL DEFAULT 0,
    last_search_round      INTEGER NOT NULL DEFAULT -1,
    last_estimate          INTEGER NOT NULL DEFAULT -1,
    last_estimate_correct  INTEGER NOT NULL DEFAULT 1
        CHECK(last_estimate_correct IN (0, 1)),
    PRIMARY KEY (campaign_id, map_id, party_id, hex_q, hex_r)
);
