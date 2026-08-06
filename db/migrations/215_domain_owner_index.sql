-- Migration 215: index domains(owner_character_id).
--
-- Ruling R-1 (docs/handoff-domain-rulings-implementation.md) makes world
-- generation mint a `vassal_assignments` row per realm edge, which turns the
-- realm tree from an empty table into ~1,000 live edges. `RealmAggregator`
-- walks that tree every monthly tick, and the innermost lookup of every node
-- visit is `RealmAggregator._list_owned_domains`:
--
--     SELECT ... FROM domains d WHERE d.owner_character_id = ?
--
-- `domains` carried indexes on realm_id, lifecycle_state and domain_style but
-- none on owner_character_id, so each of those lookups was a full table scan.
-- The monthly tick performs tens of thousands of them (tribute-in, tribute-out
-- and the realm title each aggregate, once per domain), so the scans multiplied
-- into millions of row examinations per game month the moment the edge table
-- filled.
--
-- Non-destructive, per the migrations convention: an index only.
CREATE INDEX IF NOT EXISTS idx_domains_owner
    ON domains(owner_character_id);
