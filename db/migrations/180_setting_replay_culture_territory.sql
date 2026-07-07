-- Migration 180: watchable history replay — per-frame culture + territory,
-- plus a per-polity culture-seed label.
--
-- The replay previously animated ONLY political ownership (owner_by_hex); the
-- Culture and Territory layers fell back to the present-day map, so a viewer
-- could not watch cultures spread or civ/borderlands/wilderness advance over
-- the ages. These columns store the same RLE-over-canonical-hex-order encoding
-- as owner_by_hex (runs of "value:count" joined by ';', '' = none), captured at
-- each replay cadence tick, so the two static-until-now layers now animate.
--
--   culture_by_hex   — dominant culture_id per hex this epoch ('' = none)
--   territory_by_hex — civilized / borderlands / wilderness per hex this epoch
--
-- seed_label gives every polity a stable, at-a-glance culture-seed identity
-- ("Vallican_01") for the replay tooltip, so realms that never earn a proper
-- name before game-start read as their seed culture rather than a bare pol id.
--
-- Non-destructive ADD COLUMN with '' defaults, so existing campaigns (and the
-- determinism sub-hashes, which key on the *_COLUMNS constants) pick up the new
-- fields automatically.

ALTER TABLE setting_replay_frames ADD COLUMN culture_by_hex TEXT NOT NULL DEFAULT '';
ALTER TABLE setting_replay_frames ADD COLUMN territory_by_hex TEXT NOT NULL DEFAULT '';
ALTER TABLE setting_replay_palette ADD COLUMN seed_label TEXT NOT NULL DEFAULT '';
