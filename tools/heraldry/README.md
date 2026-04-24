# Heraldry — Content Pipeline

Dev-only tooling for the heraldry builder. Not shipped with the game.

## Shield silhouettes

Shield silhouettes are **code-defined polygons** in `engine/subsystems/heraldry/shield_shape_registry.gd`, not PNG assets. The escutcheon PNGs originally imported from the wikiscraper turned out to be unusable (every mask was a solid opaque white square; every outline was fully transparent — the upstream normalize step produced degenerate files). They were deleted. If per-shape silhouettes proliferate beyond the v1 heater, consider loading polygon data from JSON or adding a small curve editor rather than growing the const dict inline.

## Charge assets

`assets/heraldry/charges/` contains 760 charge PNGs imported pre-normalized
from an external source (Wikimedia-Commons-derived white-silhouette PNGs
with proper alpha channels). The normalization Python script described in
`generation/gdd-heraldry-builder.md` §9 was NOT needed for the initial
import and has not been written. If new SVG charges are added later and
need normalizing, that script becomes worth building.

## build_charges_catalog.py

Regenerates `data/heraldry/charges.json` from the PNG files in
`assets/heraldry/charges/`. Run from the repo root:

    python tools/heraldry/build_charges_catalog.py

Charge IDs are derived from filenames; display names are humanized;
tags are initialized empty. Tagging is a separate content pass — many
of the 760 imported charges are not strictly medieval (e.g. modern
military insignia) and a curator may want to mark some as "off-theme"
or remove them entirely before release.
