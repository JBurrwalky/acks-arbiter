-- Migration 123: domain succession state — Phase 11C per
-- docs/phase-11-plan.md §11C and gdd-domain-tab.md §16.5.
--
-- When a ruler dies, the domain enters lifecycle_state='succession_pending'
-- (already in the migration 122 enum) for 1 game-month. The player may
-- designate any eligible heir from the realm during the grace; if grace
-- lapses without designation:
--   - Independent domain → automatic abandonment via REASON_NO_HEIR
--   - Vassal domain      → reverts to the overlord (project default per
--                          docs/phase-11-plan.md §11C; placeholder for the
--                          eventual ACKS Dynasties bloodline-heir model
--                          per memory/project_dynasties_succession.md)
--
-- New columns:
--   succession_pending_until_day   — grace expiry day (calendar_day at
--                                    ruler-death + 30). Non-zero only when
--                                    lifecycle_state='succession_pending'.
--   designated_heir_character_id   — the player's heir designation. Empty
--                                    string when no heir designated yet.
--   designated_heir_kind           — 'pc' / 'henchman' / 'non_henchman'.
--                                    Non-henchman heirs inherit at base
--                                    loyalty -2 per `acore_axioms`
--                                    §non_henchman_vassals L392-397.

ALTER TABLE domains ADD COLUMN succession_pending_until_day INTEGER NOT NULL DEFAULT 0;

ALTER TABLE domains ADD COLUMN designated_heir_character_id TEXT NOT NULL DEFAULT '';

ALTER TABLE domains ADD COLUMN designated_heir_kind TEXT NOT NULL DEFAULT ''
    CHECK(designated_heir_kind IN ('', 'pc', 'henchman', 'non_henchman'));
