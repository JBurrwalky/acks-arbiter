-- Migration 216 (R-7a): domain XP double-award guard.
--
-- R-7a wires domain income through to `characters.xp` for the first time
-- (`XPAwardCalculator.calculate_domain_xp_cp` -> `XpAwardService.award`). The
-- monthly tick is the only production caller and fires once per month, but a
-- replayed save, a re-entered tick, or a test driving the handler twice would
-- otherwise pay a ruler twice for the same month — and unlike the domain
-- columns, which are absolute overwrites, an XP award is CUMULATIVE and cannot
-- be undone by re-running.
--
-- `DomainHandlers._save_domain` stamps this in the same UPDATE that records
-- `domain_xp_this_month`, so the guard and the record commit together.
--
-- -1 (not 0) is the default: day 0 is a legitimate calendar day, so a 0 default
-- would silently suppress the very first award of a campaign started on day 0.

ALTER TABLE domains
    ADD COLUMN domain_xp_awarded_through_day INTEGER NOT NULL DEFAULT -1;
