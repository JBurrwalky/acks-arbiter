-- Migration 143: hideouts table + syndicates.hideout_id (Thief→Syndicate refactor).
--
-- Per the Thief→Syndicate decoupling: the three syndicate classes (thief /
-- assassin / elven nightblade) do NOT run domains. Their late-game vehicle is a
-- syndicate operated from a HIDEOUT planted inside someone else's settlement.
-- RAW `rules/ax_thief_skill_update.xml`:50 — "Hideouts are secret strongholds;
-- do not secure domains or attract families."
--
-- The hideout is its OWN structure, thematically distinct from `strongholds`:
-- it never appears in stronghold/domain UI, never counts toward any domain's
-- sufficiency, and sits in the same-or-adjacent 6-mile hex as its host
-- settlement. The old `syndicates.hideout_stronghold_id` FK to `strongholds`
-- is left in place but VESTIGIAL — never written by the new founding flow;
-- `syndicates.hideout_id` below is the source of truth.
--
-- cp_value: money × 100 (cp), funded at founding to >= the market-class minimum
--   per RAW `hideout_size_and_cost` (Class VI = 5,000 gp ... Class I = 600,000 gp).
-- market_class: snapshot of the host settlement's class (INTEGER 1..6, matching
--   settlement_entrances.market_class; 6 = Class VI smallest, 1 = Class I largest).
-- status: active / abandoned / seized (mirrors the syndicates.status vocabulary).
--
-- Non-destructive: CREATE TABLE IF NOT EXISTS + a single ADD COLUMN, per the
-- migration 118 / 137 / 142 pattern.
CREATE TABLE IF NOT EXISTS hideouts (
    id                           TEXT    PRIMARY KEY,
    campaign_id                  TEXT    NOT NULL REFERENCES campaigns(id),
    syndicate_id                 TEXT    REFERENCES syndicates(id),
    owner_character_id           TEXT    NOT NULL REFERENCES characters(id),
    host_settlement_entrance_id  TEXT    NOT NULL REFERENCES settlement_entrances(id),
    market_class                 INTEGER NOT NULL DEFAULT 6,
    cp_value                     INTEGER NOT NULL DEFAULT 0,
    location_map_id              TEXT    REFERENCES hex_maps(id),
    location_hex_q               INTEGER,
    location_hex_r               INTEGER,
    status                       TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'abandoned', 'seized')),
    created_at                   TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                   TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_hideouts_campaign  ON hideouts(campaign_id);
CREATE INDEX IF NOT EXISTS idx_hideouts_owner     ON hideouts(owner_character_id);
CREATE INDEX IF NOT EXISTS idx_hideouts_syndicate ON hideouts(syndicate_id);

ALTER TABLE syndicates ADD COLUMN hideout_id TEXT REFERENCES hideouts(id);
