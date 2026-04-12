-- Migration 026: Token variant (character sprite atlas selection)
--
-- Adds a single column `token_variant` to the characters table for storing
-- which sprite atlas variant a character uses for their combat token.
--
-- The value is a string key like "default" or "scarred" that the
-- TokenAtlasRegistry uses to look up the actual PNG atlas via the lookup
-- key `<class_id>/<variant>`. Empty string falls back to "default".
--
-- This is the ONLY migration needed for the variant system. Adding new
-- sprite atlases later requires no further migrations — just drop a PNG
-- into assets/tokens/ and add an entry to TokenAtlasRegistry._ATLAS_PATHS.

ALTER TABLE characters ADD COLUMN token_variant TEXT NOT NULL DEFAULT '';
