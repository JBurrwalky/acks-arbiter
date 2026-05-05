-- Migration 054: Concentration mode column for active_effects (Spell System Session 1).
--
-- The spell-system effect DSL (per `gdd-spell-system.md` §4.3) classifies
-- concentration into four modes:
--   none              — fixed/per_level/instantaneous; runs independently of caster actions.
--   continuous_focus  — ends if caster takes any other action (Wizard Eye, Clairvoyance scanning).
--   sustained         — ends if caster is incapacitated, unconscious, dead, or silenced.
--   conditional       — spell-specific end trigger (Charm Person repeat-save cycle, etc.).
--
-- The legacy `requires_concentration` int column stays for backward compatibility
-- (used by ActiveEffectTracker.break_concentration). Convention: when
-- `concentration_mode != 'none'`, `requires_concentration` is set to 1 by the
-- resolver. The old column will be retired in a later session.

ALTER TABLE active_effects
    ADD COLUMN concentration_mode TEXT NOT NULL DEFAULT 'none'
        CHECK(concentration_mode IN ('none', 'continuous_focus', 'sustained', 'conditional'));
