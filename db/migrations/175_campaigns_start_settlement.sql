-- Migration 175: campaigns.start_settlement_id — the setting_settlements id the player
-- chose on the campaign-creation review screen (the Decision-K start-city picker, M3-b;
-- gdd-setting-runtime-materialization §15.4). The materializer centers the 6-mile play
-- window on this city (RegionZoomIn._pick_center) AND SettingMaterializer.start_position
-- spawns the party at its in-window settlement_entrance, so the pick drives both. '' = the
-- player left the default → auto-pick the largest-market city (the pre-picker behavior).
ALTER TABLE campaigns ADD COLUMN start_settlement_id TEXT NOT NULL DEFAULT '';
