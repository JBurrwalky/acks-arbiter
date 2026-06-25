# GDD: Continuous Geography — Field-First World Generation

**Document type:** Game Design Document (project-designed, modifiable)
**Authority:** PROJECT-DESIGNED — world-generation architecture and algorithms. Subordinate to `acks_arbiter_design_brief_v11.md`. The terrain *taxonomy* this produces is owned by [`gdd-terrain-system.md`](gdd-terrain-system.md) and is unchanged; this GDD changes *how* that taxonomy is produced.
**Status:** Draft v0.2 — design + directives, no code. **APPROVED 2026-06-24 (Jedidiah)** — all §13 decisions ratified: amend the three GDDs (banners added to [`gdd-setting-generation.md`](gdd-setting-generation.md) §4–§5, [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) §6, [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) §4); **4×4** base resolution; **store** the raster; **thermal + channel-incision** erosion only; **world-gen-refactor-first** build order. Ready to implement on a feature branch.
**Depends on ACKS rules:** None new. The output taxonomy (3 elevation bands, 5 biomes + 8 subtypes, 3 territory classes, ocean/lake, rivers-as-edges) is RAW-grounded in [`gdd-terrain-system.md`](gdd-terrain-system.md); this GDD adds no new ACKS interpretation.
**Depends on project GDDs:** [`gdd-terrain-system.md`](gdd-terrain-system.md) (the taxonomy the field is normalized into); [`gdd-setting-generation.md`](gdd-setting-generation.md) (Layer-1/2 geography+climate this refactors); [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) + [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) (the 6-mile derivation whose stochastic deviation-budget model this replaces with field-sampling); [`gdd-setting-runtime-materialization.md`](gdd-setting-runtime-materialization.md) (M0–M4 consumer of the per-hex tags); [`gdd-wilderness-hex-3d.md`](gdd-wilderness-hex-3d.md) (the 3D renderer that consumes the continuous field via `RAW_FIELD`).
**Implementing files:** none yet. Refactor targets: `engine/subsystems/generation/world/heightmap_generator.gd`, `climate_generator.gd`, `region_zoom_in.gd`; new `field_sampler.gd`.
**Modifiable by Claude Code:** Yes — all algorithms, resolutions, thresholds, and the field representation are engineering decisions. The decision to retire the deviation-budget inheritance model (§3, §12) and the storage strategy (§10) are project-direction; recommendations are flagged in §13.
**Last updated:** 2026-06-24

---

## 1. Purpose and Scope

Generate world geography as a **continuous, non-hexagonal field** — elevation, hydrology, and climate simulated over cartesian (mile) space at sub-hex resolution — and then lay the hex grid on top as a **sampling/aggregation overlay** that normalizes a patch of the field into one hex's categorical tags. The field is the source of truth; the 24-mile, 6-mile, and 1.5-mile hex views are three aggregations of the *same* field at different cell sizes.

This replaces the current **hex-native** generation, where `HeightmapGenerator` and `ClimateGenerator` take a single FastNoiseLite sample *per 24-mile hex center* (`heightmap_generator.gd:92-95, 147-165`; `climate_generator.gd`), so geography literally does not exist between or below 24-mile hexes. That model forces the 6-mile zoom-in to *invent* sub-hex variation stochastically (`region_zoom_in.gd` flat-copies `elevation_raw` and perturbs tags under deviation budgets per [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) §6), and it cannot support real watershed, orographic rainfall, or a smooth 3D heightmap.

**Why now:** the [`gdd-setting-runtime-materialization.md`](gdd-setting-runtime-materialization.md) ruling makes the **6-mile map the play surface**, and [`gdd-wilderness-hex-3d.md`](gdd-wilderness-hex-3d.md) wants a continuous 6-mile height. A continuous field is the correct substrate for both: the 24-mile map is a coarse aggregation for the strategic screen; the 6-mile play window is a finer aggregation of the identical field — no re-derivation, no drift, and the 3D renderer reads the real surface.

**Out of scope:** the hex *taxonomy* (owned by `gdd-terrain-system.md`); the 3D rendering of the field (owned by `gdd-wilderness-hex-3d.md`); political/cultural history simulation (Layers 3–8, unchanged); 1.5-mile insets (the same `tag_for_footprint` applies when they're built).

---

## 2. ACKS Constraints

No new RAW. The field must **normalize into** the existing taxonomy without adding or renaming categories:

- **Elevation bands `flat`/`hills`/`mountains`** from height thresholds (`hills ≥ 0.55`, `mountains ≥ 0.75` of normalized height; `gdd-terrain-system.md` §8, current `heightmap_generator.gd:22-23`).
- **Biomes `clear`/`woods`/`jungle`/`swamp`/`desert`** + the **eight subtypes** (`gdd-terrain-system.md` §3.4).
- **Water `ocean`/`lake`**, full-hex; **rivers are hex *edges*** (`HexRiverEdgeData`) with `navigability` + `crossing`.
- **Three territory classes** (Civilized/Borderlands/Wilderness) — assigned by the political layers, not geography; unchanged.
- **Banker's rounding** for any game-number quantization; the field's continuous math (noise, flow, climate) is visual/intermediate and produces no game numbers until normalized into a tag.
- **Determinism:** everything seeded from `campaign_seed` via `WorldGenRng.derive_seed`/`stream` (existing doctrine); validated by `SettingDatasetHasher`.

---

## 3. The core inversion (and what it retires)

**Principle:** geography is generated as a continuous field over mile-space; the hex grid is an overlay sampled from it. One function, applied at every scale:

```
tag_for_footprint(field, footprint, scale) -> HexTags     # §8
```

A 24-mile hex calls it over a large footprint; each of its sixteen 6-mile children calls the *same* function over a smaller footprint of the *same* field. Cross-scale consistency is therefore **structural, not enforced**: a 6-mile hex in the valley of a "mountains" 24-mile parent comes out "hills" because that is the *truth of the field at finer resolution* — not a budgeted "deviation."

**This retires the stochastic inheritance machinery.** [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) §6.3–§6.6 and [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) §4 exist *only because* there was no field underneath a hex — they had to fabricate plausible sub-hex variation under deviation budgets (elevation ≤10% of children deviate, biome ≤25%, coherence smoothing) and feather ecotones by hand. With a real field, the variation is *read*, not invented; `region_zoom_in.gd`'s `_children_for_parent` collapses from "flat-copy parent + budgeted perturbation" to "sample the field at each child's location + normalize." The **uniformity↔noise dial** becomes a single physically-meaningful parameter: the **detail-octave amplitude** (§4). See §12 for the precise amend list (needs sign-off).

---

## 4. Field representation — coarse base raster + on-demand detail

**Recommendation: a stored coarse base raster bearing the global simulation, plus on-demand multi-octave detail noise added analytically at any resolution.** Not a fine stored raster (too big); not pure on-demand noise (can't do hydrology).

| Strategy | Verdict |
|---|---|
| Single fine raster (e.g. 8×8 samples/24-mi hex) | ✗ `huge` → millions of cells for 6-mile-faithful detail; storage + GDScript loops blow the budget |
| Pure on-demand noise from `(x,y,seed)` | ✗ infinite resolution but **hydrology is impossible** — flow accumulation/erosion/depression-fill are global neighbor-coupled passes that need a materialized grid |
| **Coarse base raster + analytic detail (PICK)** | ✓ global sim on a tractable grid; fine detail free at any scale; bounded storage |

**Base resolution: 4×4 samples per 24-mile hex = a 6-mile cell grid.** This aligns the simulation grid exactly with the 6-mile play scale (each 6-mile hex ≈ one base sample), which is elegant and convenient. Worst-case cell counts:

| Preset | 24-mi hexes | Base cells (×16) |
|---|---|---|
| small | 180 | 2,880 |
| medium | 500 | 8,000 |
| large | 1,200 | 19,200 |
| huge | 2,700 | **43,200** |

43k cells is the worst case for the global passes — comfortably tractable in GDScript for O(n)/O(n log n) work (§11). Per cell the base raster stores `height`, `temperature`, `precipitation`, `flow_accumulation`, `flow_dir`, `water_flag` — ~6 `PackedFloat32Array`/`PackedInt32Array` channels ≈ ~1 MB.

**Detail synthesis (continuity below 6 miles).** For any query `(x,y)` at any scale:
```
H(x,y) = bilerp(base_height, x, y)                                   # smooth simulated coarse field
       + detail_amplitude(slope, elevation) * fbm(x*f_d, y*f_d, seed_detail)   # analytic high-freq octaves
```
Detail is pure deterministic noise (no storage, evaluable at 1.5-mile or finer) **modulated by the coarse field** — mountains get more rugosity, lake floors none — so synthesized detail respects the simulated geography. **All three scales read the same `H(x,y)`**, integrated over different footprints. This is the "amplify a low-res physically-simulated base with noise" technique; it is what keeps 24/6/1.5 consistent.

**Keep `WorldGenRng.derive_seed(seed, channel)`** — it already gives per-channel deterministic seeds. The structural change: `_build_heightmap` stops returning `Dictionary[Vector2i→float]` keyed by hex and returns a `PackedFloat32Array` raster in `(col,row)` base-cell space plus a `sample(x,y)` accessor (the new `field_sampler.gd`).

---

## 5. Hydrology / watershed — the main sophistication win

Run the full chain **on the base raster only** (≤43k cells), in this exact DEM-analysis order. This replaces the current greedy vertex-walk river tracer (`heightmap_generator.gd:186-269`), which uses no drainage area and a `log2(source_count)` width heuristic (`:32-41`), and the `_lowest_land_hex` depression heuristic (`:260-267`).

```
1. Thermal erosion ×3-5   — talus relaxation; O(n)/pass; rounds noise spikes, cleans ridgelines
2. Sea-level threshold     — ocean mask (existing sea_level param, setting_parameters.gd:24)
3. Priority-Flood (+ε)     — depression fill + watershed labels in ONE O(n log n) pass
4. D8 flow direction       — steepest of 8 downhill; O(n)
5. Flow accumulation        — descending-height push; O(n); = discharge proxy
6. Channel extraction       — flow_acc > FAT threshold (tune to river_density param)
7. Strahler order           — channel size proxy → width + navigability buckets
8. Channel incision carve   — lower channel cells by ~log(flow_acc); O(n); rivers sit in valleys
```

- **Depression fill — Priority-Flood, NOT Planchon-Darboux** (Barnes et al. 2014): O(n log n) single priority-queue pass from the edges inward, and it **labels watersheds in the same pass** (free). The `+ε` epsilon-gradient variant gives "fill + slight slope" so flow routing has no flat ties. ~43k·log(43k) ≈ 700k heap ops — milliseconds.
- **Flow direction — D8, not D-infinity.** D-infinity's smoother dispersion is invisible once rivers are snapped to hex edges; D8 is correct here and cheaper. Keep the base raster **square** for the hydrology math; hexagonalize only at the §8 tagging step.
- **Lakes — Priority-Flood's interior (non-edge-reaching) filled depressions ARE the lakes.** Principled; subsumes the current `_lowest_land_hex` heuristic.
- **River width + navigability — from Strahler order**, replacing `log2(source_count)`. Strahler is monotone down the trunk, giving the "tributaries join → river widens" property the current per-edge accumulation only approximates. Map to existing buckets:
  | Strahler | width_category | navigability |
  |---|---|---|
  | 1 | stream | none |
  | 2–3 | creek | small_craft |
  | 4–5 | river | river_craft |
  | 6+ | major_river | large_craft |

**Erosion discipline (the cost trap):** **skip hydraulic droplet erosion** (≈`5·N²` droplets, walks of tens of steps — a GPU workload, and sub-hex detail is invisible at hex granularity). Do **3–5 cheap thermal-erosion passes** (step 1) plus the **channel-incision carve** (step 8) — the latter delivers the gameplay/visual payoff of erosion (rivers in valleys that later guide roads/settlement) at ~1/1000th the cost. If true erosion is ever wanted, gate it behind a flag and run it only on a *region* at 6-mile zoom-in (small N → quadratic is fine locally), never globally.

---

## 5.5 Height-field construction — implemented method (rework 2026-06-24)

The first build's height recipe (smooth FBM + radial falloff + a weak ridge term + `pow(norm, exponent)`) produced a flat-dominated blob: measured **85.3% flat / 13.5% hills / 1.3% mountains**, no connected ranges (highs were rounded domes), and fragmented coasts. The rework (judge-panel synthesis of three independent designs) replaces `_build_height` with this pipeline, all on the square base raster, all deterministic (§80):

```
1. Continental mask     — domain-warped FBM (cmask01), the SOLE land/ocean decider;
                          frequency scaled per land_mass_style; edge-bias toward ocean
2. Rank land threshold  — sort cmask, cut at TARGET_LAND_FRAC[style] rank → EXACT ocean
                          fraction (sea_level nudges the target so the param stays live)
3. Orogenic belt locator— 8-conn coast-distance BFS + mask-gradient → belt[i], HIGH inland
                          where ranges belong (ranges run inland, not on sea-cliffs)
4. Gated ridged-multifractal — manual octave loop; weight = running_signal·RIDGE_GATE.
                          The gate makes ridgelines CONNECT into spines; anisotropic
                          rotated frame → linear cordillera. Normalized by field max.
5. Compose base         — LAND_GAIN·cmask + RIDGE_GAIN·belt·ridge + FOOTHILL·belt·… + DETAIL
                          (ranges confined to belts; foothills ring crests; signed detail)
6. Morphological cleanup— connected-component pass: sink land comps < MIN_LAND[style],
                          fill enclosed ocean pockets < MIN_OCEAN[style]  (the look dial)
7. Quantile hypsometry  — monotone piecewise-linear transfer pinning the land
                          distribution's OWN percentiles to the fixed 0.55 / 0.75 tags
                          → exactly ~60/28/12 of land for every seed/size, D8-safe
8. Crest-preserving thermal erosion — one gentle talus pass that SKIPS crests (≥0.74)
```

**Why these mechanisms.** (4) The amplitude **gate** is the one thing that makes ridges connect into ranges instead of fracturing into domes/gravel. (7) The quantile remap is the proven precip trick applied to height: pinning the land percentiles to the tag thresholds **guarantees** the split and is monotone, so D8 flow ordering survives — and it doubles as a safety net (12% of land is always mountains, so ranges exist even on small maps where belts are narrow). (6) Morphological cleanup is the explicit, controllable fragmentation dial.

**Parameter wiring.** `mountain_frequency` now routes through the hypsometry anchors (`low {0.66,0.92}` / `medium {0.60,0.88}` / `high {0.52,0.82}`) — `elevation_exponent()` is no longer consumed. `sea_level` nudges the land target (keeps it live). `land_mass_style` drives **three knobs together** — mask frequency `_CONT_FREQ_MULT` (continental 1.0 / archipelago 3.0 / pangaea 0.6), `_TARGET_LAND_FRAC` (0.60 / 0.40 / 0.80), and cleanup sizes — so continental = one cohesive continent, archipelago = scattered islands, pangaea = supercontinent. The frequency (not just the land fraction) is what fragments vs. consolidates the landform; lowering land fraction alone only shrinks one continent.

**Calibration outcomes (verified).** Land split lands at **59.8% / 27.8% / 12.4%** (target 60/28/12); ranges read as connected cordillera with foothills; lake speckle controlled via `LAKE_FILL_THRESHOLD 0.008` + the low-octave-dominant ridge (`RIDGE_HFALL 0.52`, 4 octaves) that stopped the shattered-crest tarns; the three styles are visibly distinct at large scale. Determinism, large-map performance (<8000 ms), and channel formation all green; full suite 471/16 = branch baseline, net-zero new failures. The visual calibration rig is `tools/render_geo_field.gd` (latitude / seed / style contact sheets + grayscale / band / hillshade diagnostics) and `tools/geo_climate_stats.gd`.

**Open follow-ups:** belt placement constants (`BELT_INNER_MI`/`BELT_PEAK_MI`/`BELT_GRAD`) remain the most visual-iteration-sensitive knobs.

---

## 5.6 Rivers → hex edges — corner-graph drainage (`GeoRiverMapper`, 2026-06-24)

The renderer draws rivers as **along-edge** segments (corner→corner on the hex boundary; `hex_map_renderer._draw_river_edge`) — the ACKS river-as-edge convention with bridge/ford/ferry crossings. The field's hydrology, by contrast, is **cell-center D8 flow**, and measured shallow: max Strahler ≈ 2, no large trunks (the continent drains through many medium basins). So mapping the 6-mile cell network straight onto hex edges is both a lossy center→edge conversion *and* trunk-poor.

**Solution: rerun drainage on the hex-CORNER graph** (the dual honeycomb), corner elevations being the mean of the 3 touching hexes' `elevation_raw`. `GeoRiverMapper.map_rivers(params, dims, grid)`: enumerate corners → corner Priority-Flood(+ε) from ocean/edge outlets → steepest-descent flow → flow accumulation → channel extraction (`FAT` per `river_density`) → emit canonical `HexRiverEdgeData`. Two payoffs: (a) the corner graph **is** the along-edge representation, so no lossy conversion; (b) aggregating onto the coarser graph **merges sub-basins into trunks** — creeks and rivers emerge that the 6-mile network never had.

**Width from discharge, not Strahler.** Even on the corner graph Strahler caps at ~3, so the GDD's Strahler→width table never reaches `river`. Width is instead bucketed from **corner flow-accumulation** as multiples of `FAT` (`creek ≥2.5×`, `river ≥5×`, `major_river ≥12×`) — discharge has real dynamic range up the trunk, so the biggest drainage reads as a major river even at Strahler 3, and river size scales with drainage area (a large continent gets a major trunk; a small one tops out at `river`). **Scale-agnostic:** the same function serves the 24-mile world map and a future materialized 6-mile region (both grids sampled from the one field → cross-scale-consistent rivers). Verified (large, 3 seeds): ~140–170 edges/map, full stream→creek→river→(major) hierarchy, rivers reach outlets, deterministic; replaces the interim `HeightmapGenerator._trace_rivers` greedy vertex-walk in `geo_field_to_grid.gd`. Calibration rig: `tools/river_probe.tscn`.

---

## 6. Climate — upgrade precipitation to an orographic sweep

The current `ClimateGenerator` is already above-average (quadratic latitude curve with calibration, elevation lapse above a ceiling, a BFS rain-shadow, coastal-moisture BFS). The wins: run it **per base cell** (climate varies *within* a 24-mile hex), add **continentality**, and replace the noise-multiplier precipitation with a **swept moisture-transport** pass that makes rain shadow *emerge* instead of being a separate heuristic.

**Temperature** — keep the model, add continentality, evaluate per cell:
```
T = T_equator − k_lat·lat²            # keep existing quadratic curve
  − lapse·max(elev − ceiling, 0)       # keep existing above-ceiling lapse
  + continentality(dist_to_ocean)      # NEW — reuse the existing ocean-distance BFS
  + low_freq_anomaly_noise             # keep existing ±2°C
```

**Precipitation — single-pass orographic wind sweep** (highest-value upgrade, cheap + deterministic):
1. Prevailing wind from one seeded draw (reuse the ridge-orientation pattern; default W→E).
2. Sweep the base raster **in wind order** (cells sorted by projection onto the wind axis, ties by the orthogonal axis — a fixed geometric order, not hash-map order):
   - over **water**: `moisture += evaporation(temperature)`, clamped;
   - over **land**: `uplift = positive elevation gradient along wind`; `rain = moisture·(base + orographic_coef·max(uplift,0))`; deposit as this cell's precip; `moisture −= rain`.
   Windward slopes drain the parcel → leeward cells get a depleted parcel → **rain shadow emerges** from the same pass. The separate `_rain_shadow` heuristic is no longer needed.
3. 2–3 box/Gaussian blur passes to kill 1-D streaking; keep a low-amplitude noise overlay so iso-precip lines aren't unnaturally smooth.
4. **Rank-normalize the swept rain to a uniform [0,1] over land, then reshape with `ARIDITY_GAMMA`** (calibration 2026-06-24). The raw sweep is pathologically right-skewed — a mass of low flat-land rain plus rare high windward-mountain spikes — so a plain min-max normalize crushes nearly all land below the arid Köppen threshold and the whole continent classifies as desert. Ranking preserves the sweep's wet→dry *ordering* (windward wet, leeward / deep-interior dry, rain shadow intact) while guaranteeing a balanced, latitude-independent wet/dry split that's self-calibrating across seeds and map sizes. `ARIDITY_GAMMA` (default `0.82`, `<1` wetter / `>1` drier) is the single world-character dial and never touches the Köppen thresholds. Verified per-band land-biome split (3-seed mean): jungle peaks in the tropics, woods dominate the temperate belt, taiga+tundra ≈ 83 % of polar land, desert a steady ~13–15 % minority wherever the sweep leaves land dry.

All O(n) (the rank sort is O(n log n)). Moisture/humidity is just the carried parcel state — store final precip; no separate channel unless biome rules want it.

**Deferred climate-sophistication item:** the aridity cutoff is currently a *fixed* normalized precip (`ARID_THRESHOLD 0.18`), so desert holds the same ~15 % at every latitude. A more faithful model makes the Köppen `B` threshold rise with temperature (hot subtropics need more rain to escape aridity → more desert there, less at the poles). That edits the **shared** `_classify_koppen` (the live hex pipeline consumes it too), so it's bundled into the climate/terrain sophistication pass, not the precip calibration.

---

## 7. Biome classification — keep Köppen, run per-cell

**Keep the existing Köppen cascade** (`_classify_koppen` → `_assign_biome`) — do NOT switch to raw Whittaker. Köppen captures seasonality regimes (monsoon `Am`, Mediterranean `Cs`) Whittaker's flat temp×precip lookup can't, and the project's thresholds are already calibrated to land on namesake biomes. The change is *where* and *how*:

- **Classify per base cell** (or per sub-sample at zoom-in), so `Cfb`/`Dfc` boundaries fall on real isotherms inside a hex, not on hex-center quantization.
- **Subtypes drop out of Köppen sub-codes** as today (`Dfc→forest_taiga`, `ET→clear_tundra`, `Aw→clear_savanna`, `EF+mountains→mountains_glacial`) — keep that mapping.
- **`mountains_volcanic` + `desert_badlands` are geology overlays, not climate** — assign from relief/erosion proxies (volcanic: seeded sparse at high-relief ridge intersections; badlands: high-relief + arid + high erosion), layered after the Köppen biome.
- **Swamp becomes a better predicate:** low gradient + high `flow_accumulation` + wet (flat, waterlogged cells) — keyed off real flow now, not river-edge membership.
- **Water:** a cell/hex is `ocean`/`lake` by the §5 masks.

---

## 8. Hex normalization — the load-bearing contract

The whole refactor hinges on one idempotent, hierarchically-consistent function:

```
tag_for_footprint(field, footprint_polygon, scale) -> HexTags
```

It samples the field at a **fixed sub-lattice** inside the footprint (e.g. always 4×4 sub-samples per 6-mile hex on a 1.5-mile lattice — positions a pure function of the footprint, never random), classifies each sample, and reduces:

- **Elevation band:** median height → band, with a **"mountains if >25% of the footprint is mountain-height" override** (a hex with a peak should read as mountains even if most of it is valley — matches ACKS terrain intent and player expectation). Also store the continuous **area-mean height** as `elevation_raw` — now an honest footprint mean, not a center point-sample.
- **Biome:** area-weighted **plurality** + store the **runner-up biome and its fraction** (this is what lets a finer zoom-in faithfully reintroduce a minority biome — the "jungle oasis in desert near rivers" idea — *from the field*, not from a stochastic budget).
- **Water:** coastal-biased plurality (water wins if ≥ ~35% so coastlines/ports land correctly).
- **Subtype:** from the dominant biome's samples.

**Cross-scale guarantee:** subdividing a 24-mile hex calls the *same* function over each child's smaller footprint of the *same* field. Aggregating the sixteen 6-mile tags reproduces (within the dominance rule) the 24-mile tag — reduction is idempotent by construction. The repo's `check_domain_cross_scale_consistency` can be *strengthened* from fuzzy tolerance to exact field-reduction equality.

---

## 9. Pipeline ordering

```
LAYER 1 — GEOGRAPHY (continuous square base raster @ 6-mile cell = 4×4 / 24-mi hex)
  1. fbm height + continental shape + ridge anisotropy   (existing noise recipe, on the raster)
  2. thermal erosion ×3-5
  3. sea-level threshold → ocean mask
  4. Priority-Flood depression fill (+ε)                 → filled height + lake labels
  5. D8 flow direction
  6. flow accumulation                                   → discharge proxy
  7. channel extraction (FAT) + Strahler order           → river network, width, navigability
  8. channel incision carve                              → valleys

LAYER 2 — CLIMATE (on the filled/incised raster)
  9. temperature (lat² + lapse + continentality + anomaly)
  10. precipitation orographic wind sweep + blur         → emergent rain shadow
  11. Köppen classify per cell → biome + subtype
  12. swamp pass (low gradient + high flow_acc + wet)
  13. volcanic / badlands overlays (geology proxies)
  → STORE base raster (all channels) + channel network in SQLite as BLOB

LAYER 3 — HEX NORMALIZATION (tag_for_footprint — one function, every scale)
  14. 24-mile tags: area-weighted reduction per hex footprint   (precompute, store)
  15. 6-mile / 1.5-mile tags: SAME function, finer footprints   (lazy at region zoom-in)
      + detail-octave texture for sub-cell variation
```

Layers 1–2 run once on ≤43k cells and persist; Layer 3 is a pure idempotent reduction callable at any scale.

---

## 10. Data model

- **New `setting_field_raster`** (or a BLOB per channel keyed by `campaign_id` — far cheaper than 43k rows): store `PackedFloat32Array.to_byte_array()` for each base channel + the channel network/Strahler. ~6 MB worst case. Validate against `(seed, params)` via `SettingDatasetHasher` on load; regenerate if the version changed. Detail octaves are **never stored** — regenerated on demand.
- **`setting_hexes` / `hex_cells`** unchanged in *shape*; `elevation_raw` **changes meaning** from "center point-sample" to "area-mean of the footprint over the field." Existing consumers (land value, the 3D renderer's `RAW_FIELD`) keep working and get *more faithful* values.
- **`region_zoom_in.gd`** stops flat-copying the parent `elevation_raw` (`:212, :307`); each 6-mile child instead gets `tag_for_footprint` over its own footprint, populating a *real* per-child `elevation_raw` and tags. (This is the single change that turns the 3D renderer's 16-hex plateaus into a true surface.)
- **Store the base raster vs regenerate:** store it (erosion + flood are iterative/non-trivially-reproducible and you don't want to re-run on every load; 6 MB is nothing). Keep detail lazy.

---

## 11. Determinism + performance budget (GDScript, world scale)

Worst case (43,200 base cells): ~1.5M scalar cell-ops total across all global passes — well under a second of arithmetic. The real cost is GDScript loop/dictionary overhead, mitigated by:

1. **`PackedFloat32Array`/`PackedInt32Array` indexed by `row*width+col` — never `Dictionary[Vector2i]`.** The current `grid` is a `Dictionary` keyed by `Vector2i`; for per-cell hot loops that's the biggest avoidable cost (~5–10× slower iterate + serialize). This is the most important implementation note.
2. **Global passes on the square base raster only; never at hex resolution.** Hexagonalize (`tag_for_footprint`) only when producing tags for a map being rendered.
3. **Lazy detail + lazy fine tags.** 24-mile tags + base raster precomputed and stored at world-gen; 6-mile/1.5-mile tags + detail synthesized per chunk at region zoom-in — dovetails with `gdd-region-zoom-in.md`'s "persist all, render near" chunking.

**Determinism rules** (mostly already followed): per-channel `derive_seed`; per-cell stochastic rolls via position-keyed streams (so iteration order never affects results); Priority-Flood heap ties broken by cell index; flow-accumulation summation in fixed sorted-by-height order. `SettingDatasetHasher` surfaces any cross-platform drift.

| Pass | Complexity | Worst ops |
|---|---|---|
| fbm height (6 oct) | O(n) | ~260k |
| thermal erosion ×4 | O(n)/pass | ~170k |
| Priority-Flood | O(n log n) | ~700k heap |
| D8 + accumulation | O(n) | ~90k |
| Strahler + incision | O(channel)+O(n) | « n + 43k |
| temperature | O(n) | 43k |
| precip sweep + 3 blur | O(n)×4 | ~170k |
| Köppen + biome | O(n) | 43k |
| **total global precompute** | — | **~1.5M (one-time)** |

---

## 12. What this amends/supersedes (needs sign-off)

These are Layer-2 PROJECT-DESIGNED docs (modifiable), but the changes are architectural — **flag for Jedidiah before editing them**:

- **`gdd-setting-generation.md` §4–§5:** Layer-1 geography becomes the raster + hydrology producer; Layer-2 climate gets the orographic sweep + per-cell classification. The §4.4 vertex-walk hydrology is replaced by §5 here.
- **`gdd-hex-subdivision.md` §6 + `gdd-region-zoom-in.md` §4:** the **stochastic deviation-budget inheritance is replaced by field-sampling** (§3, §8). Most of §6.3–§6.6 (deviation budgets, coherence smoothing, the flat-copy MVP, the coastline sub-pass open question) collapse into "call `tag_for_footprint`." This is a *simplification*, not just a swap — worth raising explicitly.
- **Code:** `heightmap_generator.gd` (raster + hydrology; `_trace_rivers` → D8/accumulation/Strahler), `climate_generator.gd` (precip sweep; per-cell classify), `region_zoom_in.gd` (`_children_for_parent` → field-sample), new `field_sampler.gd` (`sample(x,y)` + `tag_for_footprint`).
- **`gdd-wilderness-hex-3d.md`:** its central open problem ("no continuous 6-mile height") is *solved* — `RAW_FIELD` becomes its default height source (that GDD §4.4 already anticipates this).

---

## 13. Decisions (RESOLVED 2026-06-24) + Open Build Items

**All ratified by Jedidiah 2026-06-24.** The first five bullets are decided (kept as rationale); the rest are open *build-time* items.

- **[APPROVED] Amend the three GDDs (§12).** Banners added to `gdd-hex-subdivision.md` §6, `gdd-region-zoom-in.md` §4, `gdd-setting-generation.md` §4–§5 marking the deviation-budget inheritance superseded by field-sampling.
- **[APPROVED] Base resolution 4×4 / 24-mi hex** (= 6-mile cell; aligns the sim grid to the play scale). Detail octaves cover sub-6-mile relief; 8×8 rejected (4× cell count, huge → 173k).
- **[APPROVED] Store the base raster** (~6 MB BLOB; erosion is iterative). Open build detail: new `setting_field_raster` table vs a channel-keyed BLOB column — decide at implementation (BLOB-per-channel recommended).
- **[APPROVED] Erosion = thermal + channel-incision only;** no global hydraulic droplet erosion (flagged *local* erosion at zoom-in stays a future option).
- **[APPROVED] Build order:** Layer-1/2 raster + hydrology + climate → `field_sampler` + `tag_for_footprint` → rewire `region_zoom_in` → (then) the 3D renderer onto `RAW_FIELD`. The world-gen refactor pays off for the 2D maps + sim *before* any 3D work.
- **[VALIDATION] Golden tests.** The existing setting-gen suites + `SettingDatasetHasher` must be re-baselined; add a cross-scale idempotence test (aggregating 6-mile tags reproduces the 24-mile tag) and a determinism test (same seed → identical raster hash).
- **[SCOPE] Coastlines.** A continuous field gives sub-hex coastlines for free at zoom-in (resolves the `gdd-hex-subdivision.md` §6.6 coastline open question), but the *water-geometry* rendering (beaches, the water mesh) stays in `gdd-wilderness-hex-3d.md` §8.4.
- **None blocking on ACKS rules.** Output taxonomy is unchanged (§2).

---

## 14. Sources

DEM/terrain algorithms grounding the pipeline (validated 2026-06-24):
- Barnes et al., *Priority-Flood: An Optimal Depression-Filling and Watershed-Labeling Algorithm* (arXiv:1511.04463) — O(n log n) fill + watershed.
- Standard DEM order: fill → D8 → flow-accumulation → FAT threshold → delineate (Xie 2022, *Water Resources Research*; ISPRS IJGI 10(3):186 on FAT tuning).
- Strahler stream order ↔ mean river width (GRASS `r.stream.order`; empirical width relationship).
- Nick McDonald, *Procedural Weather Patterns* — wind-vector moisture transport + orographic precipitation + neighbor-blur.
- Amit Patel (Red Blob), *Polygonal Map Generation* / mapgen2; Azgaar's Fantasy Map Generator — field-first, precipitation→rivers→biome flux.
- Köppen climate classification (vegetation-designed; preferred over flat Whittaker here); AutoBiomes (discretized Whittaker) for the lookup-table alternative.
- Hydraulic (droplet) erosion cost (~`5·N²` droplets, GPU workload) — why it's skipped globally (arXiv:2210.14496; holzman.dev erosion writeup).
