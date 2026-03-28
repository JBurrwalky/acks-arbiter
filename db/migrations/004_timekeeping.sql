-- Migration 004: Timekeeping tables
--
-- Stores the global campaign clock and per-party clocks for multi-party
-- time synchronisation. campaign_clock is deliberately not foreign-keyed
-- to campaigns so it can be seeded and tested independently.
--
-- dawn_hour / dusk_hour are configurable per campaign for seasonal variation.

CREATE TABLE IF NOT EXISTS campaign_clock (
    campaign_id   TEXT    PRIMARY KEY,
    elapsed_rounds INTEGER NOT NULL DEFAULT 0,
    dawn_hour     INTEGER NOT NULL DEFAULT 6,
    dusk_hour     INTEGER NOT NULL DEFAULT 20
);

CREATE TABLE IF NOT EXISTS party_clocks (
    campaign_id   TEXT    NOT NULL,
    party_id      TEXT    NOT NULL,
    elapsed_rounds INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (campaign_id, party_id),
    FOREIGN KEY (campaign_id) REFERENCES campaign_clock(campaign_id)
);
