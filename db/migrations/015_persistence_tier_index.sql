-- Migration 015: Index on characters(campaign_id, persistence_tier, is_active)
-- Speeds up list_characters_by_tier() and list_characters_excluding_tier() queries.
-- Safe to apply on existing data; index is created if it does not already exist.

CREATE INDEX IF NOT EXISTS idx_characters_persistence_tier
    ON characters(campaign_id, persistence_tier, is_active);
