-- Migration 009: Add sex field to characters
-- Biological sex (male/female) for narrative generation and any sex-specific rules.
ALTER TABLE characters ADD COLUMN sex TEXT NOT NULL DEFAULT 'male'
    CHECK(sex IN ('male', 'female'));
