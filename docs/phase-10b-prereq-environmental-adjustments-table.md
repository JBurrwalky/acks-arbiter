# Environmental Adjustments to Demand — Canonical Table

> **Source:** ACKS Core, Environmental Adjustments to Demand table, screenshot provided by Jedidiah 2026-05-11 in resolution of **Q-MERC-1A** (corrupted late-luxury rows in `rules/acore-setting-construction-rules.xml:297-356`).
>
> **Status:** **RESOLVED — XML now authoritative.** The XML rules file was updated 2026-05-11 (Jedidiah explicit approval) with the canonical values from this transcription. `<source_integrity_note>` removed; `<transcription_note>` added documenting the resolution. The column schema was corrected (`tundra_plains` split into `tundra` + `plains`; `extra_climate_or_wrap` removed). Full 31-row merchandise list now encoded.
>
> **This file's continuing role:** audit trail for the resolution + record of `?? Verify`-flagged cells the mercantile session should re-check against the original PDF before committing values to `data/commerce/environmental_adjustments.json`. **If any cell turns out to differ from the PDF, update both this file AND the XML simultaneously.**
>
> **Corrections to the previous XML column schema (now applied):**
> - The XML's `tundra_plains` column was TWO separate columns: `tundra` and `plains`. **Fixed in XML.**
> - The XML's `extra_climate_or_wrap` column was a transcription artifact of the merged `tundra_plains` cell. **Removed from XML.**

---

## Column schema (corrected)

After the `merchandise` label, each row has **20 modifier columns** in this order:

| Group | Columns |
|---|---|
| **Age** (5) | `age_0_20_years`, `age_21_100_years`, `age_101_1000_years`, `age_1001_2000_years`, `age_2001_plus_years` |
| **Water Source** (3) | `sea_coast`, `lake_shore`, `river_bank` |
| **Climate** (10) | `rainforest`, `savanna`, `desert`, `steppe`, `scrub`, `grasslands`, `deciduous_forest`, `taiga`, `tundra`, `plains` |
| **Elevation** (2) | `hills`, `mountains` |

Modifier values are in halves: integers, +½, -½, +1½, -1½ etc. Per RAW step 3, fractions are dropped after all environmental modifiers are summed for a given merchandise type at a given settlement.

---

## Full table (31 merchandise types)

The table below uses the column order in the screenshot. All values are read from the canonical screenshot. Where the XML transcription was corrupted (`(blank)`, `(source wrapped)`, merged cells), this transcription replaces those values with the canonical PDF values.

### Common Merchandise (rows 1-21)

| # | Merchandise | 0-20 | 21-100 | 101-1k | 1k-2k | 2k+ | Sea | Lake | River | Rain | Sava | Des | Step | Scru | Gras | DeFo | Taig | Tund | Plai | Hill | Mtn |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Grain, vegetables | -1 | -1 | 0 | +2 | +3 | 0 | 0 | -1 | 0 | +½ | +1 | +½ | -½ | -1 | -½ | +½ | +1 | -½ | 0 | +½ |
| 2 | Fish, preserved | +½ | -½ | -½ | -½ | +½ | -1 | -½ | -½ | 0 | +½ | +1 | +½ | 0 | +½ | -½ | 0 | 0 | 0 | +½ | +1 |
| 3 | Wood, common | -1 | -½ | 0 | +1 | +2 | 0 | 0 | 0 | -1 | 0 | +1 | +½ | 0 | +½ | -1 | -1 | +1 | -½ | 0 | +½ |
| 4 | Animals | +½ | -½ | -½ | -½ | +½ | 0 | 0 | -½ | +1 | -½ | +1 | -1 | 0 | -½ | -1 | 0 | +½ | 0 | 0 | +½ |
| 5 | Salt | -1 | -½ | 0 | +½ | +1 | -½ | -½ | -½ | +1 | 0 | -½ | -½ | 0 | 0 | 0 | 0 | 0 | -½ | 0 | 0 |
| 6 | Beer, ale | +½ | -½ | -½ | -½ | 0 | -½ | -½ | -½ | +1 | +1 | +1 | +1 | -½ | 0 | -½ | +1 | +1 | -½ | -½ | -½ |
| 7 | Oil, lamp | +½ | -½ | -½ | -½ | 0 | -½ | 0 | -½ | -½ | 0 | +½ | +½ | -1 | +1 | 0 | -1 | 0 | +½ | -½ | 0 |
| 8 | Textiles | -1 | -½ | 0 | +½ | +1 | 0 | 0 | -½ | +1 | +½ | +1 | +½ | 0 | -½ | -1 | -1 | +½ | -½ | -½ | 0 |
| 9 | Hides, furs | -1 | -½ | 0 | +½ | +1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | -½ | 0 | -½ | -½ | -½ | 0 | 0 |
| 10 | Tea or coffee | -1 | -½ | 0 | +½ | +1 | -½ | 0 | 0 | -1 | -½ | -½ | 0 | 0 | 0 | +½ | +1 | +1 | 0 | -½ | -½ |
| 11 | Metals, common | -1 | -½ | 0 | +½ | +1 | 0 | 0 | 0 | -½ | 0 | 0 | 0 | 0 | 0 | +½ | 0 | -½ | +½ | -½ | -½ |
| 12 | Meats, preserved | +½ | -½ | -½ | -½ | +½ | 0 | 0 | 0 | +1 | 0 | +1 | -1 | 0 | -½ | -1 | 0 | -½ | -½ | 0 | 0 |
| 13 | Cloth | -1 | -½ | 0 | +½ | +1 | 0 | 0 | -1 | -½ | 0 | +½ | 0 | -½ | -½ | -½ | +1 | +1 | -½ | -½ | 0 |
| 14 | Wine, spirits | +½ | -½ | -½ | -½ | 0 | -½ | -½ | -½ | +1 | +1 | +½ | +1 | -1 | +1 | -½ | +½ | +1 | +½ | -½ | -½ |
| 15 | Pottery | +1 | +½ | 0 | -½ | -1 | -½ | -½ | -½ | +1 | +1 | -½ | -½ | -½ | 0 | 0 | 0 | 0 | 0 | -½ | 0 |
| 16 | Tools | +1 | +½ | 0 | -½ | -1 | -½ | -½ | -½ | +1 | +1 | +1 | +1 | -½ | -½ | -½ | +1 | +1 | -½ | -½ | 0 |
| 17 | Armor, weapons | +1 | +½ | 0 | -½ | -1 | -½ | -½ | -½ | +1 | +1 | +1 | +1 | -½ | -½ | -½ | +1 | +1 | -½ | -½ | 0 |
| 18 | Dye & pigments | +1 | +½ | 0 | -½ | -1 | -½ | -½ | -½ | -½ | 0 | -½ | 0 | 0 | 0 | 0 | +1 | +1 | 0 | -½ | 0 |
| 19 | Glassware | +1 | +½ | 0 | -½ | -1 | -½ | -½ | -½ | +1 | +1 | -½ | 0 | -½ | 0 | 0 | +1 | +1 | 0 | -½ | 0 |
| 20 | Mounts | +½ | -½ | -½ | -½ | 0 | 0 | 0 | 0 | +1 | +½ | -½ | -1 | -½ | -1 | 0 | +½ | +1 | -1 | +½ | +1 |
| 21 | Monster parts | -1 | -½ | 0 | +½ | +1 | 0 | 0 | 0 | -½ | -½ | -½ | 0 | 0 | 0 | -½ | 0 | 0 | 0 | 0 | -1 |

### Precious / Rare Merchandise (rows 22-31)

| # | Merchandise | 0-20 | 21-100 | 101-1k | 1k-2k | 2k+ | Sea | Lake | River | Rain | Sava | Des | Step | Scru | Gras | DeFo | Taig | Tund | Plai | Hill | Mtn |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 22 | Wood, rare | -1½ | -½ | 0 | +1 | +2 | 0 | 0 | 0 | -1 | 0 | +1 | +½ | 0 | +½ | -1 | -1 | +1 | -½ | 0 | +½ |
| 23 | Furs, rare | -1 | -½ | 0 | +1 | +2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | -½ | 0 | -½ | -½ | -½ | 0 | 0 |
| 24 | Metals, precious | -1½ | -½ | 0 | +½ | +1½ | 0 | 0 | 0 | -½ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | -½ | -½ |
| 25 | Ivory | -1 | -½ | 0 | +1 | +2 | 0 | 0 | 0 | -1 | -1 | -½ | -½ | -½ | +½ | +½ | +½ | 0 | 0 | +½ | +1 |
| 26 | Spices | +½ | -½ | -½ | -½ | +½ | 0 | 0 | 0 | -1 | -1 | -½ | -½ | -½ | +1 | +1 | +1 | 0 | -½ | +½ | +1 |
| 27 | Porcelain, fine | +1 | +½ | 0 | -½ | -1 | -½ | -½ | -½ | +1 | +1 | -½ | -½ | -½ | 0 | 0 | 0 | 0 | 0 | -½ | 0 |
| 28 | Books, rare | +1 | +½ | 0 | -½ | -1 | -½ | -½ | -½ | +1 | +1 | +1 | +1 | 0 | 0 | -½ | +1 | +1 | 0 | -½ | 0 |
| 29 | Silk | +½ | -½ | -½ | -½ | +1 | 0 | 0 | 0 | -1 | +½ | +½ | +½ | -½ | +1 | -½ | +1 | +1 | -½ | -½ | 0 |
| 30 | Semipr. stones | -1½ | -½ | 0 | +½ | +2 | 0 | 0 | 0 | -½ | 0 | -½ | 0 | -½ | 0 | -½ | 0 | 0 | 0 | -½ | -½ |
| 31 | Gems | -1½ | -½ | 0 | +½ | +2 | 0 | 0 | 0 | -½ | 0 | -½ | 0 | -½ | 0 | -½ | 0 | 0 | 0 | -½ | -½ |

**?? Verify:** Rows 30 (Semipr. stones) and 31 (Gems) read as identical in my best-effort transcription. Please re-confirm against the screenshot/PDF whether Gems differs from Semipr. stones, or whether they intentionally share the same modifier profile (defensible RAW-wise since both are precious-stone categories with similar economic behavior).

**?? Verify:** Several individual cells where the screenshot resolution made the half-tick hard to read. The mercantile session should re-verify every cell against the screenshot (or PDF) when committing this data to JSON. In particular:
- Row 11 (Metals, common), Plains column: read as `+½` — verify
- Row 18 (Dye & pigments), Rainforest column: read as `-½` — verify
- Row 19 (Glassware), Steppe column: read as `0` — verify
- Row 20 (Mounts), Plains column: read as `-1` — verify
- Row 25-26 (Ivory/Spices), Steppe through Deciduous Forest: re-check the differences between these two rows
- Row 30/31 (Semipr. stones / Gems): full row re-check; suspicious they're identical

---

## Resulting merchandise list (31 entries — full)

This is the canonical merchandise list per RAW. Note that this is LARGER than the XML's transcribed list (which had ~25 entries, with some merged/wrapped). The full count is:

**Common (21):** Grain & vegetables, Fish (preserved), Wood (common), Animals, Salt, Beer & ale, Oil (lamp), Textiles, Hides & furs, Tea or coffee, Metals (common), Meats (preserved), Cloth, Wine & spirits, Pottery, Tools, Armor & weapons, Dye & pigments, Glassware, Mounts, Monster parts.

**Precious / Rare (10):** Wood (rare), Furs (rare), Metals (precious), Ivory, Spices, Porcelain (fine), Books (rare), Silk, Semi-precious stones, Gems.

The dependency doc's ballpark ("ACKS Core lists about 24 common types" and "About 8-12 precious rows") is roughly correct; this confirms 21 common + 10 precious = 31 total.

---

## Encoding notes for `data/commerce/environmental_adjustments.json`

When the mercantile session encodes this table to JSON, use the following schema:

```json
{
  "merchandise_type": "grain_vegetables",
  "display_name": "Grain, vegetables",
  "precious": false,
  "modifiers": {
    "age": {
      "0_20_years": -1.0,
      "21_100_years": -1.0,
      "101_1000_years": 0.0,
      "1001_2000_years": 2.0,
      "2001_plus_years": 3.0
    },
    "water_source": {
      "sea_coast": 0.0,
      "lake_shore": 0.0,
      "river_bank": -1.0
    },
    "climate": {
      "rainforest": 0.0,
      "savanna": 0.5,
      "desert": 1.0,
      "steppe": 0.5,
      "scrub": -0.5,
      "grasslands": -1.0,
      "deciduous_forest": -0.5,
      "taiga": 0.5,
      "tundra": 1.0,
      "plains": -0.5
    },
    "elevation": {
      "hills": 0.0,
      "mountains": 0.5
    }
  }
}
```

**Rationale for half-integer storage as floats:**
- Per RAW step 3, fractions are dropped AFTER summing all environmental modifiers for a given merchandise type. So intermediate values must preserve halves.
- Use `RoundingUtil` (banker's rounding) on the final summed value per CLAUDE.md.

**Merchandise key normalization:**
- `merchandise_type` keys are snake_case versions of the display names: `grain_vegetables`, `fish_preserved`, `wood_common`, `wood_rare`, `metals_common`, `metals_precious`, `semi_precious_stones`, `gems`, etc.
- Cross-check with the canonical Common Merchandise and Precious Merchandise tables in `rules/acore-campaign-hijinks.xml:915` and `:949` to ensure the merchandise-type keys are consistent with the registry.

---

## XML rules-file update — APPLIED 2026-05-11

Per Jedidiah's explicit one-instance approval, the corrupted rows in `rules/acore-setting-construction-rules.xml:297-356` were corrected with the canonical values from this transcription. Changes:

- `<source_integrity_note>` removed; replaced with `<transcription_note>` documenting the resolution.
- `<column>tundra_plains</column>` split into separate `<column>tundra</column>` and `<column>plains</column>`.
- `<column>extra_climate_or_wrap</column>` removed (transcription artifact).
- All 25 wrapped/corrupted rows replaced with 31 canonical rows (21 common + 10 precious).

**Going forward:** the XML is now the canonical source for the table. This document remains as the audit trail and as the verification flag for cells that need PDF re-check. If a future PDF spotcheck reveals an error in any cell, update BOTH files simultaneously.
