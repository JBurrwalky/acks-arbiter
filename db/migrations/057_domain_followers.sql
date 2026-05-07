-- Migration 057: Domain followers (Domain Phase 0 — schema only)
--
-- Per `acore_axioms_strongholds_and_domains.xml`:
--   * §peasants_and_followers / §followers_arrival L111-116 — when a PC
--     reaches level 9+ AND has a stronghold meeting the per-hex minimum, they
--     attract class-specific followers in three waves: ceil(N×0.5) at half-
--     built, ceil(N×0.25) at completion, remainder during the first month
--     after completion.
--   * §before_ninth_level L117-123 — pre-9 PCs do not attract followers (only
--     mercenaries via investment).
--
-- This table is the destination roster of a domain's standing followers
-- once they arrive. Phase 5 ships `follower_arrival_resolver.gd` which
-- writes rows here; Phase 0 only declares the schema so later phases plug in.

CREATE TABLE IF NOT EXISTS domain_followers (
    id                TEXT    PRIMARY KEY,
    domain_id         TEXT    NOT NULL REFERENCES domains(id),
    follower_class    TEXT    NOT NULL,
    count             INTEGER NOT NULL DEFAULT 0,
    equipped_kit_id   TEXT,
    arrival_phase     TEXT    NOT NULL DEFAULT 'pending'
        CHECK(arrival_phase IN ('pending', 'half_built', 'completed', 'post_completion')),
    morale_modifier   INTEGER NOT NULL DEFAULT 0,
    created_at        TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_domain_followers_domain_id
    ON domain_followers (domain_id);
