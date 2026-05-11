-- Migration 092: hex biome subtypes
--
-- Adds an optional `biome_subtype` column to `hex_cells` so a hex can carry
-- a refinement of its parent biome (e.g. woods+forest_dense, mountains+
-- mountains_volcanic, desert+desert_badlands). Empty string means "use
-- parent biome behavior" — the default for every existing hex, so this
-- migration is non-destructive.
--
-- Subtype compatibility constraints (which subtype is allowed with which
-- biome/elevation) are enforced in GDScript (HexTerrainData.is_valid),
-- not at the SQL layer, because the matrix is too involved for a single
-- CHECK constraint and the validation logic already lives in the data
-- class.
--
-- See gdd-terrain-system.md §3.4 for the full subtype specification.

ALTER TABLE hex_cells ADD COLUMN biome_subtype TEXT NOT NULL DEFAULT ''
    CHECK(biome_subtype IN (
        '',
        'forest_dense',
        'forest_taiga',
        'mountains_volcanic',
        'mountains_glacial',
        'clear_tundra',
        'clear_savanna',
        'clear_grassland',
        'desert_badlands'
    ));
