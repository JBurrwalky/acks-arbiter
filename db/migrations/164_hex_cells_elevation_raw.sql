-- Migration 164: persist raw continuous elevation (≈0..1) on runtime hex cells.
-- The categorical `elevation` (flat/hills/mountains) suffices for 2D play, but the
-- future 2D→3D wilderness renderer (gdd-wilderness-hex-3d.md) needs the raw
-- heightmap value. SettingMaterializer copies it from setting_hexes.elevation_raw
-- (24-mile world map); 6-mile zoom-in synthesizes per-child values later.
-- 0.0 default = legacy / unknown (existing fixture maps).
ALTER TABLE hex_cells ADD COLUMN elevation_raw REAL NOT NULL DEFAULT 0.0;
