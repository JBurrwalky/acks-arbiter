# Build Plan — Contiguous 3D Dungeon Generation (DG-C3D)

> **Authority:** Implements [`generation/gdd-dungeon-contiguous-3d.md`](../generation/gdd-dungeon-contiguous-3d.md) (Draft v0.2 — schema approved, fog ruled room-agnostic, all four companion edits applied 2026-07-06). Companion-edited GDDs: [`gdd-dungeon-layout.md`](../generation/gdd-dungeon-layout.md) (§9/§11/§14 supersessions), [`gdd-dungeon-generator-v1.md`](../generation/gdd-dungeon-generator-v1.md) (v1.2 banners), [`gdd-voxel-tactical-architecture.md`](../generation/gdd-voxel-tactical-architecture.md) (v1.2 — `stairs_spiral`, fog §15.2), [`gdd-dungeon-map-ui.md`](../generation/gdd-dungeon-map-ui.md) (v2.1 — §4.2.2 stairs-as-movement).
>
> **Status (2026-07-06, drafted):** Not started. Sub-phases A → G are sequential; the new pipeline is built as a parallel internal path and cut over in one session (DG-C3D.F). Update per-sub-phase Status fields as work lands. Do NOT renumber sub-phase ids — they are stable identifiers for `build_log.md`.
>
> **What this replaces:** the floor-stitched model — independent per-floor 2D layouts, same-(col,row) stair anchors, `stair_target_*` teleport overlays, per-floor BFS with teleport edges. After DG-C3D a dungeon is one contiguous `VoxelMapData` volume: story bands at real elevations (deeper = negative levels), carved stair geometry (straight / switchback / spiral / ramp), multi-story atrium rooms with balcony zones, and per-zone stocking. Design rationale: contiguous GDD §1/§3.

## Wave split

| Sub-phase | Scope | Recommended model | Status |
|---|---|---|---|
| **DG-C3D.A** | Shared types + schema, dormant: `RoomZone`, `StairwellData`, RoomData additions (`band`, `kind`, `height_levels`, `level_offset`, `zones`), `VoxelCell.zone_index`, migration (additive column + 2 tables + `dungeon_rooms` columns), generator-version stamp + regenerate-on-load plumbing. Zero behavior change. | Sonnet | **DONE 2026-07-10** (migration 210; suite 545/16 net-zero; branch `dungeon-refactor`) |
| **DG-C3D.B** | Vertical plan: band math (walk levels, direction), connector count/type selection, atrium promotion, footprint reservation with collision. Pure seeded logic + tests. | Sonnet (Opus review if reservation collision gets subtle) | **DONE 2026-07-10** (`vertical_plan.gd`; suite 546/16 net-zero; review 4 findings fixed — canonical dungeon_type keys) |
| **DG-C3D.C** | Per-band layout reservations: the layout generator accepts pre-placed reservation rooms (circulation rooms, atrium base, upper-band blocked region + balcony ring stub) participating in scatter/MST/corridors/doors. Legacy `required_stair_positions` path untouched until F. | Sonnet | **DONE 2026-07-11** (reserved_rooms + secret exclusion + theme fields; golden zero-diff gate; suite 547/16 net-zero; review 3 blocked-region latent bugs fixed) |
| **DG-C3D.D** | Vertical composition: stamp bands into one volume, carve connector geometry per contiguous GDD §6, atrium voids + balcony slabs + parapets per §7, zone flood-fill + `zone_index` stamping, floor-integrity pass, `StairwellData` emission. | **Opus for planning + geometry invariants; Sonnet for implementation** | **DONE 2026-07-11** (`dungeon_volume_composer.gd`; parallel path, `generate()` untouched; suite 548/16 net-zero; conventions §119) |
| **DG-C3D.E** | 3D-graph validation + keys/levers: navigability on the real movement graph (shared step-legality predicate with `MovementResolver`), spiral movement clause, key/lever fixpoint on the 3D graph, §10.2 acceptance checks. | **Opus** (movement semantics + fixpoint correctness) | **DONE 2026-07-11** (`movement_rules.gd` shared predicate + spiral clause/support; composed `reach_composed`/`validate_composed_*` + `place_composed` over zones; additive — legacy path stays until F; suite +DungeonComposedNavigation; conventions §120) |
| **DG-C3D.F** | Per-zone stocking + CUTOVER: stocker iterates zones at band tier, zone fields on MonsterGroup/KeyItem, repository persists zones/stairwells, `DungeonGeneratorV1.generate` flips to the new path, version bump activates regeneration, legacy deletion (teleport stairs, anchors, serializer), context-menu Ascend/Descend removal, 80-dungeon stress sweep green. | **Opus** | **DECOMPOSED into F.1–F.4** (Jedidiah 2026-07-11 — the cutover is large + irreversible, so the atomic flip is isolated). **F.1 DONE 2026-07-11** (additive/dormant: `MonsterGroupData.zone_index` + `KeyItemData.placed_in_zone_index` + migration 211 + repository carry; suite 549/16 net-zero). **F.2a DONE 2026-07-11** (per-zone stocking projection + circulation exclusion). **F.2b DONE 2026-07-11** (persistence plumbing: result `zones` slot + transactional zone/stairwell persist). **F.2c DONE 2026-07-12 — THE ATOMIC CUTOVER: `generate()` runs the composed pipeline (plan → per-band layouts → stock → compose → composed keys/levers → per-zone projection → composed solvability), `GENERATOR_VERSION` 0→1, composed payload serialization + hand-authored exemption, hoard cell-z remap + composed z-bridge. Single-band byte-identity: 29/30 sweep seeds byte-identical (normalized — key/lever PLACEMENT re-derives under the 3D walker; **RULED FINE by Jedidiah 2026-07-13**: identical results were never the intent so long as keys/levers stay reachable — reachability is exactly what `validate_composed_solvability` gates).** **F.2d DONE 2026-07-13** (balcony/gallery zone stocking on its own §118 stream (`DungeonStocker.BALCONY_STREAM_OFFSET` 32452843, zero-draw for balcony-less dungeons) at the zone band's tier, attached to the zone's band layout (global room id + zone_index ≥ 1; hoards placed at real walk-z); §11 door-less trap nuance (gate the access door record + volume, else swap within band, else Empty — d100 never re-rolled); zone-aware key finalize (`finalize_key_placements_composed` — a balcony key embeds in the balcony's own content); atrium purpose rollups; `GENERATOR_VERSION` 1→2. Identity: 39/39 balcony-less sweep dungeons FULL-fingerprint byte-identical across the bump; committed 3-floor golden seed 11; atrium seeds 44/66/88 additive-only diffs). **F.3 DONE 2026-07-13 (Opus, suite 548/16 net-zero — 2 removed suites vs F.2d's 550/16; DungeonCutoverIdentity byte-identity golden GREEN across the deletion):** deleted `dungeon_voxel_serializer.gd`+suite (retired at F.2c), `VoxelCell.stair_target_*`+`DungeonMapController.get_stair_target`+`teleport_party_to`+Ascend/Descend menu/handler (composed stairs are ordinary walkable geometry — "Move Here"; only Exit Dungeon survives on transition cells; NO formal action-vocabulary registry existed to deregister), the layout stair-ANCHOR path (`required_stair_positions`/`_validate_stair_anchors`/`_pre_place_anchor_rooms`/`_ANCHOR_ANTECHAMBER_SIZE`/`RoomPlan.is_anchor_room`), legacy `DungeonKeyLeverPlacer.place()`+14 exclusive 2D-BFS helpers, `DungeonNavigabilityValidator.validate_solvability()`+`_expand_stair`/`_can_traverse_solvability`/`_key_for_door`, and the dead `_convert_legacy_to_voxel` "levels"-format converter. **`dungeon_stair_data.gd`/`DungeonStairData` KEPT** — the "audit importers first" caveat + byte-identity gate WIN: the entrance up-stair (`stairs_up=1`→`layout.entrance`→`volume.entry_pos`) is load-bearing on the composed path AND fingerprinted by the golden (record + `FEATURE_STAIRS_UP` terrain); full removal would need a golden re-capture (Jedidiah's call, out of scope). Also KEPT (composed path reuses): `finalize_key_placements` (defensive fallback), `_demote_ungated_trap_rooms`+`_append_key_to_monster_group` (shared), `validate_layout`+`_neighbours`+`_enqueue`+`fallback_seed_cell` (per-band guard), `_ANCHOR_INTERIOR_MARGIN=2` (byte-identity). conventions §122. F.4 = 80-dungeon stress sweep + saved-campaign regen guard (snap-to-entrance at restore) + no-teleport runtime verify. |
| **DG-C3D.G** | Runtime polish + test content: minimap stairwell glyphs + tooltips, re-authored hand-built test dungeon (switchback + two-story hall), integration scenarios (balcony LOS/cover, falling, fog, no-teleport traversal), fall-audit telemetry, placeholder meshes. | Opus | **Done 2026-07-13** — carried item A fixed (atrium degradation 28→0 / balconies 4→32 kept; composer-only §7.2 guarantee: perimeter-aware door detect + forced-stair fallback); `[FALL]` telemetry wired; dead "levels" branches removed (4 files); `test_dungeon.json` re-authored ("Sunken Hall": 2 bands, switchback + atrium/balcony/parapet/internal-stair); scenarios `scenario_balcony_features` + `scenario_composed_volume_determinism` + `test_dg_c3d_g_ui` added; minimap stairwell glyphs/tooltips + main-view stair tooltip + placeholder step/spiral/ramp/parapet meshes. Conventions §123. Visual in-engine screenshot verify DEFERRED (godot-ai MCP unavailable this session); no-teleport + restore-guard covered mechanically by the composed-nav + fixture-service suites. |

**Sequencing:** A → B → C → D → E → F → G, strict. B–E build the new pipeline as a parallel internal path (callable and testable without changing what `generate()` returns), mirroring the voxel migration's keep-old-path-until-cutover discipline. F is the single cutover commit; nothing before F may change the shape of a generated dungeon. G polishes on top of the cut-over reality.

---

## Required reading per session

Per `CLAUDE.md` Build Session Protocol:

1. `CLAUDE.md` itself.
2. `acks-build-log --last 1`, `--next-actions 3`, `--needs-review`, plus `--for-task "DG-C3D"` and `--for-task "dungeon generator"`.
3. `docs/acks_arbiter_design_brief_v11.md`.
4. `docs/document_map.md` and `docs/rule_system_map.md` (when they exist).
5. `acks-conventions --for-task "<sub-phase id>"` — expect §3.3 (rounding + the RAW floori exception), §6.1 (godot-sqlite), §7.4 (extracted data — consumed, not extended here), §8.1 (error logging), §9 (testing), §19 (EventScheduler) to be the frequent hitters.
6. **The controlling design document: `generation/gdd-dungeon-contiguous-3d.md` — read in full every DG-C3D session.** Read the companion-edited sections of the other four GDDs as the sub-phase touches them (layout §6-§11 for B/C; voxel §7/§9-§11/§15 for D/E; generator-v1 §9-§11/§13-§14 for E/F; map-ui §4.2.2/§8/§11.4 for F/G).
7. For ACKS rule references, `acks-raw-lookup` — never read the XML corpus directly. DG-C3D introduces **no new rule extractions**; the DG-V1 dataset under `data/dungeon_generator/` already covers stocking/treasure/monster tables, and the stocking rules are unchanged (zones are an *iteration* change, contiguous GDD §11).

---

## Resolved decisions (apply to all sub-phases)

Nailed down by Jedidiah 2026-07-06 (contiguous GDD §4, §15) plus engineering commitments. Don't re-litigate; escalate contradictions.

**Story bands, hooks reserved.** A band = one ACKS dungeon level = 2 voxel levels (walk + headroom). `walk_level(floor_index) = 2 × direction × (entrance_floor_index − floor_index)`; entrance walk level = 0; subterranean direction = +1 (deeper floors at negative levels), above-ground = −1. `level_offset` / `height_levels` fields exist from A but are asserted at defaults (contiguous GDD §5.1/§5.4).

**One volume, one grid.** All bands share `grid_width × grid_height` and origin; output is one `VoxelMapData`. Solid rock is default fill for uncarved subterranean space (§5.2).

**Zones are the stocking unit.** Zone = maximal contiguous walkable region of one room on one band. Balconies/galleries are zones of the atrium's `room_id`, distinct `zone_index`, stocked at **their own band's tier**. Circulation rooms (stairwells) and corridors are never stocked. Single-zone rooms behave byte-for-byte as rooms do today (§5.3, §11).

**Full connector vocabulary.** Straight runs (2 stepped cells + shaft opening + landings, under-fill solid), switchback stairwell rooms (3×2 / 3×3, both bands), spiral shafts (`stairs_spiral`, ±1 level in-column at normal cost, no throw), ramps for burrow/cavern themes. Patterns and theme weights: contiguous GDD §6/§8.3.

**Atriums.** `height_levels = 4`, base-band main zone, upper-band interior void (`floor_type: none`), perimeter balcony ring zones with parapet `cover_value`, connectivity guarantee (upper-band circulation and/or internal grand stair) with graceful degradation to plain double-height hall. Promotion chances per theme, ≥5×5 rooms only, cap 1 per adjacent band pair (+1 Large) (§7).

**Regenerate, no migration.** Generator version stamp; stored dungeons with an older version are discarded and lazily regenerated on next access (the `DungeonFixtureService` / runtime-consumer seam). No legacy loader survives F. `stair_target_*`, `get_stair_target`, `_apply_stair_overlays`, `_convert_legacy_to_voxel`, `required_stair_positions`/StairAnchor, and `dungeon_stair_data.gd` are all deleted at F (§13).

**Fog: no engine change.** Reveal is light radius + occlusion, room-agnostic — the built `FogRevealEngine` already does this. Do not add room- or zone-scoped reveal anywhere. GDD prose is already aligned (voxel GDD §15.2 v1.2).

**One movement predicate.** Step legality (support, ±1-level via stair/ramp/spiral feature, door passability) must live in ONE place consumed by `MovementResolver`, the navigability validator, and the key/lever placer. The validator must not reimplement movement rules. Record the chosen home in `docs/coding_conventions.md`.

**Solvability method (contiguous GDD §10.3 — added at Jedidiah's direction).** The DG-V1 discovery-order fixpoint (generator-v1 GDD §10.2, post-2026-06-10) carries forward as THE key/lever placement method — its dependency-DAG guarantee is topology-agnostic and makes "key on the inaccessible side" impossible by construction. Do NOT resurrect the retired per-door outside-region BFS. Updates that are mandatory, not optional: doors are the only gates (no door cells inside connector runs — composer emits, validator asserts); reachability counts reversible walk edges only (falls are never edges; symmetry asserted); key candidates are fully-discovered ZONES; every band reachable via ≥1 never-secret path (sole-connector secret exclusion at door-roll time, clear-one repair as backstop); repair ladder rule 3 — unreached content with no frontier door explaining it is a structural composition defect → hard-fail to re-seed, never geometric repair from the key layer; post-hoc carving demoted to near-dead code (per-band, horizontal, opening-respecting, integrity re-checked — prefer re-seed); gate blast-radius telemetry (`[GATE]` warning when one key gates > ~40% of stockable zones, tunable).

**RNG stream discipline.** New pipeline stages (vertical plan, composition) draw from **newly derived, namespaced streams** off the master seed; the existing per-floor layout and stocking seed derivations are byte-preserved. Consequence and test: a single-band dungeon generates **byte-identically** before and after the rework (same seed → same layout, same stocking rolls, same treasure). This is the F regression gate.

**Rounding:** DG-C3D introduces no new rounding (integer cell geometry throughout). The existing `floori()` RAW exception for cross-tier number-appearing (coding_conventions §3.3) is untouched.

**ACKS constraints untouched.** The d100 stocking table, monster/treasure procedures, and placement rules are exactly as DG-V1 implemented them (`rules/acore-setting-construction-rules.xml:573-583, 621-642, 659-663` via the encoded JSON dataset). Per-zone iteration is the RAW-faithful "each room on each dungeon level" reading — contiguous GDD §2/§11.

---

## Sub-phase DG-C3D.A — Shared types + schema (dormant)

### Goal

Land every data shape the rework needs with zero behavior change. Fields exist, defaults hold, nothing reads them yet.

### Files to create / edit

- `engine/shared_types/room_zone.gd` — NEW. `RoomZone` per contiguous GDD §9.2 (`room_id`, `zone_index`, `band`, `zone_type`, `cells`, `level_offset`, stocking fields).
- `engine/shared_types/stairwell_data.gd` — NEW. `StairwellData` per §9.3 (`stairwell_id`, `type`, `lower_band`, `upper_band`, `bottom_cell`, `top_cell`, `run_cells`, `width`, `room_id`, `is_entrance`).
- `engine/shared_types/dungeon_room_data.gd` — EDIT. Add `band: int`, `kind: String = "chamber"`, `height_levels: int = 2`, `level_offset: int = 0`, `zones: Array[RoomZone]`. Existing stocking fields stay for now (they relocate at F; dual presence during B–E is fine because nothing reads zones yet).
- `engine/shared_types/voxel_cell.gd` — EDIT. Add `zone_index: int = -1` (+ to/from-dict). Do NOT touch `stair_target_*` yet (deleted at F).
- `engine/shared_types/dungeon_generator_result_v1.gd` — EDIT. Add optional composed-volume slot (null until F) so B–E tests can inspect new-path output without changing the public result contract.
- `db/migrations/<next>_dungeon_contiguous_3d.sql` — NEW (next free number; 187+ at drafting time). Additive only: `ALTER TABLE voxel_map_cells ADD COLUMN zone_index INTEGER NOT NULL DEFAULT -1`; `CREATE TABLE room_zones (...)`; `CREATE TABLE stairwells (...)`; `ALTER TABLE dungeon_rooms ADD COLUMN band / kind / height_levels / level_offset`. CHECK constraints mirror the type vocabularies (`kind IN ('chamber','circulation')`, `zone_type IN ('main','balcony','gallery','ledge','landing')`, stairwell `type IN ('straight','switchback','spiral','ramp')`). Self-contained, no FKs, per the DG-V1.C pattern.
- Generator version stamp: a `generator_version` value persisted with each dungeon (column on the existing dungeon-floors/metadata table — pick the least invasive home) + a check at the lazy-generation seam (`DungeonFixtureService` / the runtime consumer): version mismatch → delete stored dungeon → regenerate. Wire the check now with the CURRENT version so the mechanism is tested before F flips the number.

### Unit tests

Under `tests/subsystems/generation/dungeon_generator_v1/` and `tests/shared_types/` (follow existing placement):

- RoomZone / StairwellData serialization round-trips (dict + SQLite via repository helpers).
- Migration forward + idempotent re-run; CHECK constraints reject bad vocab values.
- `VoxelCell.zone_index` round-trips through `voxel_map_cells` persistence.
- Version-mismatch regeneration: store a dungeon with a stale version stamp, access it, assert it is discarded and regenerated.

### Acceptance criteria

- Full pre-existing test suite green (no behavior change anywhere).
- New types round-trip; migration clean; regeneration mechanism proven with the current version number.

---

## Sub-phase DG-C3D.B — Vertical plan

### Goal

The whole-dungeon planning stage that runs before any band lays out (contiguous GDD §8 stage A). Pure seeded logic, no voxel output.

### Files to create

Under `engine/subsystems/generation/dungeon_generator_v1/`:

- `vertical_plan.gd` — `static func build(request, theme, rng) -> VerticalPlan`. Derives bands + walk levels (§5.1 formula, direction by `structure_type`), per-band tier (reuse `tier_derivation.gd` — unchanged), connector count per adjacent band pair (1 + Large extras per layout GDD §9.1 counts), connector types from the theme weight table (§8.3), atrium promotions (§7.3 gates: band-above exists, ≥5×5, theme chance, cap), and footprint reservations for every connector/atrium on both affected bands — collision-checked against each other within the interior margin.
- Internal plan types (same file or sibling): `VerticalPlan`, `ConnectorPlan` (type, bands, footprint rects per band, entry/exit cells, width, lanes, **`is_sole_connector: bool`** — true when it is the only connector for its band pair, consumed by C's secret-exclusion rule), `AtriumPlan` (base band, footprint, balcony ring spec, internal-stair flag).

### Unit tests

- Walk-level formula: the §5.1 worked examples (subterranean entrance-on-1 → 0/−2/−4; above-ground → 0/+2/+4; entrance mid-stack).
- Determinism: same seed → identical plan; different seed → different plan; single-band request → **zero** RNG draws from the vertical-plan stream (guards the F byte-identity gate).
- Reservation invariants: no footprint overlap; all within interior margin `[2, grid−3]`; every adjacent band pair has ≥1 connector; atrium cap respected.
- Theme weights: batch-generate plans; connector type distribution within ±5pp of §8.3 table (ramp-only themes produce no switchbacks/spirals).

### Acceptance criteria

- Deterministic, collision-free plans for every dungeon_size × floor_count (1–6) × entrance_floor_index combination in a sweep.
- No changes to any existing code path (new file only, not yet called by `generate()`).

---

## Sub-phase DG-C3D.C — Per-band layout with reservations

### Goal

Teach the rooms-first planner to accept pre-placed reservation rooms (contiguous GDD §8 stage B). The legacy anchor path stays functional until F.

### Files to edit

Under `engine/subsystems/generation/dungeon_layout/`:

- `dungeon_layout_request.gd` — add `reserved_rooms: Array` (each entry: bounds, `kind`, connector/atrium back-reference, door-eligibility flags). Legacy `required_stair_positions` remains side-by-side until F.
- `dungeon_room_composer.gd` — reservation entries become pre-placed `RoomPlan`s before scatter (generalizing the existing `_pre_place_anchor_rooms` §9.3 machinery): circulation rooms and atrium base rooms are MST nodes (connectivity guaranteed by construction); the atrium's **upper-band blocked region** participates in collision only (no MST membership — it is not a room on that band); the **balcony ring stub** is door-eligible so the §8 door placer can connect upper-band corridors to it.
- **Sole-connector secret exclusion (contiguous GDD §10.3):** reservation entries carry `is_sole_connector: bool` (computed by the vertical plan — true when the circulation room is the only connector for its band pair). The door-type roll (`_assign_door_type`) skips the secret-overlay roll for doors on such rooms; locked is permitted (keys handle locked). This is the proactive half; DG-C3D.E owns the clear-one-secret backstop for multi-connector pairs.
- `dungeon_theme.gd` / `dungeon_theme_catalog.gd` — add `connector_weights` and `multi_story_room_chance` theme fields (defaults per contiguous GDD §7.3/§8.3; only Wizard's Dungeon needs real values for now, per the V1 universal-fallback rule).

### Unit tests

Under `tests/subsystems/generation/dungeon_layout/`:

- Reserved rooms survive scatter untouched (no overlap, exact bounds).
- Reserved circulation/atrium rooms are connected to the network (BFS) in every seed of a sweep.
- Blocked regions receive no rooms/corridors; balcony ring stubs receive ≥0 doors and are door-eligible.
- Legacy anchor path still passes its existing coverage unchanged (the anchor/stair assertions inside `test_dungeon_room_composer.gd` and `test_dungeon_layout_generator.gd` — they die at F, not here).

### Acceptance criteria

- A band laid out with reservations passes layout navigability (§9.1) treating reserved rooms as ordinary rooms.
- Zero diff in output for requests with no reservations (RNG stream identity preserved — assert same-seed equality against pre-C output for a sample).

---

## Sub-phase DG-C3D.D — Vertical composition

### Goal

The new heart: per-band plans + vertical plan → one contiguous volume (contiguous GDD §8 stage C). Heaviest geometry work in the plan; get the invariants right here and everything downstream is bookkeeping.

### Files to create

Under `engine/subsystems/generation/dungeon_generator_v1/`:

- `dungeon_volume_composer.gd` — the stage. Steps, in order (§8 C1–C5):
  1. Stamp every band's rasterized cells into `VoxelMapData` at its walk/headroom levels; solid-fill uncarved subterranean space; set ceilings implicitly (band above's floor slab or solid cap).
  2. Carve connectors per §6 patterns: stepped cells with direction suffixes, `floor_type: stone` on steps, under-step solid fill, shaft/floor openings above runs, switchback interiors with mid-landings at walk+1, spiral shafts with per-level openings, landings. Register every opening.
  3. Carve atriums per §7: upper-band interior `floor_type: none` void, balcony ring slabs, parapet `cover_value` on edge cells, optional internal grand stair (a §6.1 straight run inside the room, wider lanes), degradation to double-height hall when connectivity fails (log).
  4. Zone assignment: flood-fill walkable regions per (room, band) → `RoomZone` records + `zone_index` stamped on cells. Disconnected same-band galleries get distinct zones.
  5. **Floor-integrity pass:** every walkable band-k+1 cell above open band-k space has a floor unless its column is a registered opening; every registered opening has none. Violations abort with full context — never ship an undeclared hole.
  6. **No gates in runs (contiguous GDD §10.3):** the composer never emits a door cell inside any connector's `run_cells` (doors live at room boundaries only), and never emits one-way geometry — every carved connector is traversable in both directions. Both are composer emission rules here and validator assertions in E.
- Emits: composed `VoxelMapData`, `Array[StairwellData]`, `Array[RoomZone]`, updated RoomData. Parked on the result's dormant composed-volume slot (A) — `generate()`'s public output is still legacy.

### Unit tests

Under `tests/subsystems/generation/dungeon_generator_v1/`:

- Per-connector-pattern fixtures: hand-built two-band micro-dungeons, one per type; assert the exact cell pattern of §6 tables (step features/suffixes, under-fill, openings, landings) and floor integrity around every opening.
- Atrium fixture: main zone + N balcony zones detected; void cells `floor_type: none` with atrium `room_id`; parapet cover values; disconnected east/west galleries → distinct `zone_index`.
- Walk-level stamping: subterranean 3-floor dungeon has floor 2 at levels −2/−1 and floor 3 at −4/−3; above-ground fixture ascends.
- Floor-integrity property test: seed sweep over composed mediums; zero violations; then deliberately corrupt a slab and assert the pass catches it.
- Zone/band honesty: every walkable cell's level == `walk_level(band) + level_offset` with offsets 0 (§10.2 check 4).

### Acceptance criteria

- Composed volumes for the full size × floor-count sweep pass all composition unit tests.
- Composition perf: < 150ms for a 6-band large dungeon on top of existing layout time (soft target; log it).
- Legacy output path still byte-identical (composition runs in parallel, changes nothing).

---

## Sub-phase DG-C3D.E — 3D-graph validation, movement clause, keys/levers

### Goal

All reachability reasoning moves onto the real movement graph of the composed volume (contiguous GDD §10). One step-legality predicate, shared everywhere.

### Files to edit / create

- **Step-legality predicate** — extract/locate the single source: support rule (voxel GDD §9.2), ±1-level via stair/ramp feature (the existing `MovementResolver` suffix logic near its stair-handling block), door passability model. Add the **spiral clause**: ±1 level within a `stairs_spiral` column at normal cost (voxel GDD §10.5). `MovementResolver`, validator, and placer all consume the shared predicate. Where it lives (VoxelGrid static, a new `movement_rules.gd`, or MovementResolver statics) is Claude Code's call — document it in coding_conventions and the build log **Interfaces** field.
- `navigability_validator.gd` — REWRITE for the composed volume: structural pass (all doors passable → every zone of every room reachable from entrance; every stairwell traversable both directions) and solvability pass (doors at initial state, fixpoint key/lever unlock — logic unchanged, graph honest). Delete per-floor BFS + stair-teleport edges. **Seed every pass from the dungeon entrance only** (never per-stair — the DG-V1 masking lesson). **Falls are never edges**; assert edge symmetry. Add §10.2 checks: stair-geometry walk, balcony reachability (with degradation hook back to composer), band honesty, fall-audit soft count, no-door-in-run assertion, and **gate blast-radius telemetry** (`[GATE]` warning per contiguous GDD §10.3).
- `key_lever_placer.gd` — port the discovery-order fixpoint BFS (generator-v1 GDD §10.2) to the shared predicate/graph. "Rooms fully discovered" becomes "zones fully discovered" (entrance zone + circulation rooms excluded as candidates); floor-weighting (same band 5 / adjacent 2 / distant 1) unchanged. **Repair ladder per contiguous GDD §10.3:** (1) sole-entrance-path downgrade (V1 §10.4, unchanged); (2) clear `is_secret` on a frontier secret+unlocked door that blocks an unreached zone/stairwell — the unreached set now spans bands — plus the clear-one backstop when every connector to a band pair rolled secret; (3) unreached content with NO frontier door explaining it → hard-fail into the whole-dungeon re-seed ladder (structural defect — never geometric repair from here). Post-hoc carving, if retained at all, follows the §10.3 constraints (per-band, horizontal, opening-respecting, integrity re-run) and firing is treated as a bug.
- `engine/subsystems/combat/movement_resolver.gd` — spiral clause + tests; verify combat engagement on spiral cells (3D Chebyshev handles it — smoke test per voxel GDD §20.4's concern).

### Unit tests

- Traversal per connector type: party path from band 0 landing to band −1 landing through each §6 pattern using only legal steps (this is where D's geometry meets movement for real).
- Spiral: up/down in-column movement at normal cost; no climb throw; engagement across adjacent spiral levels.
- Validator fixtures: micro-dungeon with locked door + key behind stairwell (fixpoint crosses bands); balcony-only-via-upper-corridor fixture; balcony-unreachable fixture → degradation fires.
- Placer: keys land only in fully-discovered zones; circular dependency impossible by construction (re-run the DG-V1 §10.2 dependency-DAG assertions on the 3D graph).
- **Adversarial solvability fixtures (contiguous GDD §14.3a):** locked stairwell-room door gating an entire band → key lands on an earlier band and the dungeon solves; sole connector attempts secret roll → exclusion fires; both connectors of a two-connector pair roll secret → one cleared and logged; secret+locked door on a balcony zone → key placed, zone reachable; deliberately disconnected reservation → rule-3 hard fail (no carve, no key repair); door cell injected into `run_cells` → assertion trips.
- Blast-radius telemetry: fixture with one key gating >40% of stockable zones emits `[GATE]`.

### Acceptance criteria

- Every composed dungeon in the sweep passes structural + solvability passes on the 3D graph, with zero rule-3 structural failures and every band reachable through ≥1 never-secret path.
- One predicate: grep proves validator/placer contain no independent stair/support logic.
- Existing movement/combat test suites green (spiral is additive).
- All adversarial solvability fixtures pass; the repair ladder fires only where designed (downgrades and secret-clears logged with position + reason, per the DG-V1 logging discipline).

---

## Sub-phase DG-C3D.F — Per-zone stocking + cutover

### Goal

Flip `DungeonGeneratorV1.generate()` to the new pipeline, stock per zone, persist the new shapes, delete the legacy path. The one session where the game's dungeons actually change.

### Work items

1. **Stocker per zone** (`stocker.gd`): iterate zones of chamber rooms in the current room order (zone 0 first, then upper zones) so single-zone dungeons preserve the RNG draw sequence exactly. Zone's band tier drives monster/treasure rows. Trap-placeholder fallback nuance for door-less balcony zones (re-target access door, else swap within band; d100 never re-rolled — contiguous GDD §11). `current_purpose` rollup on RoomData composed from zone results.
2. **Schema plumbing:** `MonsterGroup.zone_index`, `KeyItem.placed_in_zone_index` populated; stocking fields written to `room_zones`; `dungeon_generator_repository.gd` persists/loads zones + stairwells + composed volume (via existing `voxel_map_cells` CRUD + `zone_index`).
3. **Cutover:** `generate()` returns the composed result; `dungeon_voxel_serializer.gd` retired (composition owns voxel emission); generator version bumped → all stored dungeons regenerate on access (A's mechanism).
4. **Legacy deletion:** `stair_target_*` fields on VoxelCell (+ persistence), `DungeonMapController.get_stair_target` and every stair-transition special case that calls it, `_convert_legacy_to_voxel`, `_apply_stair_overlays` (with `dungeon_voxel_serializer.gd`), `required_stair_positions` + StairAnchor path in the layout generator, `dungeon_stair_data.gd` (audit importers first: grep `StairData`). Delete their tests (incl. `test_dungeon_voxel_serializer.gd`'s overlay coverage).
5. **Context menu:** remove Ascend/Descend from `dungeon_context_menu_builder.gd` + handlers per map-ui GDD §4.2.2 v2.1; Exit Dungeon untouched; deregister any ascend/descend entries in the action vocabulary file (CLAUDE.md step 11).
6. **Stress sweep:** re-run the 80-dungeon sweep (tiers 1–4 × 1–4 floors, generator-v1 GDD §9.2) — 100% structural + solvability + floor-integrity + stair-geometry pass, zero rule-3 structural failures, every band reachable via ≥1 never-secret path, `[GATE]` blast-radius warnings sampled into the build log. Whole-dungeon re-seed ladder retained as outer safety net.

### Regression gates (all must hold)

- **Single-band byte-identity:** fixed-seed single-floor dungeon generates identical layout, stocking rolls, and treasure before vs. after cutover (the RNG-discipline decision made this possible; this test proves it).
- Full test suite green after deletions.
- A saved campaign with a stored old-version dungeon loads cleanly: dungeon regenerates, party enters, walks entrance → band −1 with **zero** teleport calls.
- XP/GP per-band ledgers and `[BALANCE]` warnings still emit (aggregation by band per contiguous GDD §11).

### Build log entry requirements

- Zone counts + atrium/balcony counts from a sample large dungeon; placeholder counts per the DG-V1 discipline; the byte-identity test's seed; every deleted file/symbol listed (this is the entry future sessions grep when something misses a stair).

---

## Sub-phase DG-C3D.G — Runtime polish + test content

### Goal

Make the new dungeons legible and prove the headline scenarios end-to-end (contiguous GDD §14).

### Work items

- **Minimap stairwell glyphs** + hover tooltips from `StairwellData` ("Stairs down to Level 3", "Spiral stair up") per map-ui GDD §11.4 v2.1; stair-cell tooltips in the main view.
- **Hand-authored test dungeon:** re-author the JSON test content (Goblin Warrens successor) as a composed volume: two bands, one switchback stairwell, one two-story hall with a balcony and internal stair. This is the cheap permanent fixture for renderer/UI/fog work.
- **Integration scenarios** under `tests/scenarios/generation/dungeon_generator_v1/` (contiguous GDD §14.5-6): balcony archer LOS + parapet cover vs. atrium floor; step-off-balcony fall = 10' = 1d6 (via the falling resolver; damage per `rules/acore_combat_and_wounds.xml:797` as already encoded); fog on balcony cells follows light+LOS only; fixed-seed whole-volume determinism.
- **Fall-audit telemetry:** log per-band count of walkable cells adjacent to ≥10' drops (§10.2 check 5).
- **Placeholder meshes:** simple primitives for steps / spiral / parapet if the asset pipeline hasn't supplied real ones (flag to `gdd-dungeon-asset-integration-plan.md` for the real meshes; renderer architecture unchanged — per-level MultiMesh groups).

### Acceptance criteria

- All integration scenarios pass deterministically; the hand-authored fixture loads, renders, and is fully traversable with the multi-level camera (Level Strip Widget shows both bands).

---

## Cross-cutting requirements (all sub-phases)

- **Godot hygiene:** after adding new `.gd` files run `--headless --path . --import` once before the test suite (CLAUDE.md). Headless test command per CLAUDE.md. No `class_name` in autoloads. `query_with_bindings` for all parameterized SQL.
- **Conventions maintenance:** the shared movement predicate home, the RNG stream-derivation pattern, and the reservation-room pattern are new conventions — document each in `docs/coding_conventions.md` in the session that creates it.
- **Build log discipline:** every session appends an entry (template via `acks-build-log`), runs `--lint`, and updates this file's Status column. Be exhaustive in **Interfaces defined or changed** — this rework renames load-bearing seams.
- **Determinism:** every random consumer takes the seeded RNG instance for its namespaced stream; no bare `randi()`.

### Escalation triggers

Stop and ask Jedidiah (or flag `[NEEDS-OPUS-REVIEW]`) if:

- Any contradiction between this plan, the contiguous GDD, and the companion-edited GDDs.
- The single-band byte-identity gate proves impossible without disproportionate contortion (the fallback — accepting a one-time content reshuffle on existing seeds — is Jedidiah's call, not Claude Code's).
- The shared movement predicate extraction destabilizes combat movement tests (cross-system contract per CLAUDE.md Layer 3).
- Composition wants to violate a §6/§7 geometry pattern (e.g., a theme needs 15'-tall stories); band math is design-level, not engineering-level.
- Anything suggests reading `rules/*.xml` at runtime.

---

## Out of scope (defer; do not build here)

- Free-elevation content: mezzanines, sloped corridors, non-zero `level_offset` (hooks only — contiguous GDD §5.4).
- Above-ground dungeon *generation* (direction handling is implemented and fixture-tested in D; Tower/Castle/Manor/Cliff-city generation waits for V2 dungeon types).
- Real trap mechanisms, incl. pits opening into the story below (forward hook for the trap GDD — contiguous GDD §12.5).
- Dungeon factions consuming zones/stairwells as territory (§12.6).
- Real stair/parapet art assets (asset integration plan owns them; G ships primitives).
- Multi-level minimap; stocking-density auto-balance (telemetry only, §15).

---

## Document conventions

- Status updates land in this file when work ships; don't renumber sub-phase ids.
- Mid-build resolved decisions land in the Resolved decisions section here; the build log records the conversation.
- Newly discovered scope lands as `DG-C3D.<letter>.<N>` sub-sub-phases, never as renamed phases.

---

## Revision history

- **2026-07-06:** Initial draft. Seven sub-phases (DG-C3D.A–G), parallel-path build with single-session cutover at F, byte-identity regression gate, all 2026-07-06 rulings folded into Resolved decisions.
