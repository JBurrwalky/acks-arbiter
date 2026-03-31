-- Migration 008: Add portrait_id to characters table
-- Stores the portrait filename stem (e.g. "portrait_fighter_01") for the character.
-- Portrait resolution: check user://portraits/{id}.png first, then res://assets/portraits/{id}.png.
ALTER TABLE characters ADD COLUMN portrait_id TEXT NOT NULL DEFAULT '';
