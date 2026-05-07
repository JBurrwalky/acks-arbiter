-- Migration 055: Domain hex land values (Domain Phase 0)
--
-- Per `acore_axioms_strongholds_and_domains.xml`:
--   * §land_value L43-82 — every 6-mile hex of a domain has a base land value
--     of 3-9 gp/family/month, rolled as 3d3 when first surveyed.
--   * §land_improvement L207-215 — investment of 25,000 gp per +1 land value;
--     hard caps: improvement +3 max per hex, final land_value never exceeds 9.
--   * §land_value L43-82 — surveyors (Cartographer / land_surveyor specialist
--     from migration 053) record the survey on the domain's behalf.
--
-- The roadmap text refers to this migration as `050_domain_hex_land_values.sql`
-- but 050 is taken by `050_poi_discovery.sql`; renumbered to 055 so the actual
-- highest migration is monotonic.

CREATE TABLE IF NOT EXISTS domain_hexes (
    id                   TEXT    PRIMARY KEY,
    domain_id            TEXT    NOT NULL REFERENCES domains(id),
    hex_q                INTEGER NOT NULL,
    hex_r                INTEGER NOT NULL,
    land_value           INTEGER NOT NULL DEFAULT 5
        CHECK(land_value BETWEEN 3 AND 9),
    surveyed_by          TEXT REFERENCES characters(id),
    is_littoral          INTEGER NOT NULL DEFAULT 0
        CHECK(is_littoral IN (0, 1)),
    land_improvement_gp  INTEGER NOT NULL DEFAULT 0
        CHECK(land_improvement_gp BETWEEN 0 AND 3),
    created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (domain_id, hex_q, hex_r)
);

CREATE INDEX IF NOT EXISTS idx_domain_hexes_domain_id
    ON domain_hexes (domain_id);
