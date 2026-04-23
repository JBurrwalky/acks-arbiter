# Heraldry — Content Pipeline

Dev-only tooling for the heraldry builder. Not shipped with the game.

## Assets

`assets/heraldry/escutcheons/` and `assets/heraldry/charges/` were imported
pre-normalized from an external source (Wikimedia-Commons-derived SVGs
normalized to white-silhouette PNGs). The two Python normalization scripts
(`normalize_charges.py`, `normalize_escutcheons.py`) described in
`generation/gdd-heraldry-builder.md` §9 were not needed for the initial
import and have not been written. If new SVG charges are added later and
need normalizing, those scripts become worth building.

## build_charges_catalog.py

Regenerates `data/heraldry/charges.json` from the PNG files in
`assets/heraldry/charges/`. Run from the repo root:

    python tools/heraldry/build_charges_catalog.py

Charge IDs are derived from filenames; display names are humanized;
tags are initialized empty. Tagging is a separate content pass — many
of the 760 imported charges are not strictly medieval (e.g. modern
military insignia) and a curator may want to mark some as "off-theme"
or remove them entirely before release.
