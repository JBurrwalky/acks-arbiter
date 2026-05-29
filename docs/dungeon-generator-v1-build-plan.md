# Build Plan — Random Dungeon Generator V1

> **Authority:** Implements [`generation/gdd-dungeon-generator-v1.md`](../generation/gdd-dungeon-generator-v1.md) (Draft v1.1 rev 3). Companion edits in [`generation/gdd-dungeon-layout.md`](../generation/gdd-dungeon-layout.md) §5.2 / §5.3 / §8.1 / §8.3 / §9.3 / §11 and [`docs/coding_conventions.md`](coding_conventions.md) §3.3 / §7.4 are already landed; the implementation honors them.
>
> **Status (2026-05-27, drafted):** Not started. Sub-phases A → E are sequential except E (test scenarios) which lands incrementally alongside each preceding sub-phase. Update per-sub-phase Status fields as work lands. Do NOT renumber sub-phase ids — they are stable identifiers for `build_log.md`.
>
> **Why this is "V1":** the user is shipping a single-type "gonzo" generator to system-test the end-to-end stocking pipeline. Wizard's Dungeon serves as the universal fallback for every dungeon on the campaign map until V2 introduces additional types. Traps and unique encounters are deferred but the rooms they would have occupied are **forward-marked** with placeholder tags and fallback content so V2 can find and replace them. The full design rationale is in the V1 GDD §1 and §15.

## Wave split

| Sub-phase | Scope | Recommended model | Status |
|---|---|---|---|
| **DG-V1.A** | Build-time data extraction: `tools/extract_dungeon_generator_data.py` + `data/dungeon_generator/*.json` + CI diff test under `tests/data_integrity/`. Implements coding_conventions §7.4 for the dungeon generator dataset. Zero game logic. | Sonnet | **Complete 2026-05-27 (Opus 4.7).** 12 JSON files (120 rows total), extraction script idempotent, freshness test green. Test suite 360/20 (+1 vs. baseline). |
| **DG-V1.B-base** | Implement the dungeon layout generator from scratch per `gdd-dungeon-layout.md` §§4–11. Scope: bitmask grid (§4.2), grid sizing (§4.3), room placement (§6), corridor generation (§7), door placement (§8.1 baseline), stair placement (§9.1), cell finalization (§10), room detection (§10.2), DungeonLayout output (§11). Wizard's Dungeon theme only (other themes can be stubs per V1 GDD §7.1). No §8.3 / §9.3 / §11 companion-edit additions yet — those land in DG-V1.B-edits. | **Opus for planning + algorithm design; Sonnet for mechanical implementation.** | **Complete 2026-05-27 (Opus 4.7); REWRITTEN clean-room 2026-05-27 (Opus 4.7).** First impl was donjon-derived (CC BY-NC 3.0 — incompatible with commercial release); replaced with rooms-first scatter + Prim's MST + L/S corridor router + rasterizer per `gdd-dungeon-layout.md` §§4-10 (rev 2026-05-27). 7 active files / ~1900 LOC (5 shared types + 4 subsystem modules + 4 test suites). Test suite 365/19 (no regressions; same suite count as before, 2 old test suites swapped for 2 new). Generation times: lair=3ms, small=6ms, medium=18ms, large=56ms — all under §13.3 100ms target. Door density ~1/room (closer to ACKS published) vs ~5/room in the donjon-derived version. Supports adjacent rooms with shared walls (matches Sakkara published-dungeon style). |
| **DG-V1.B-edits** | Companion edits on top of DG-V1.B-base: §8.3 door material rule, §8.1 secret-as-overlay refactor, §9.3 constraint-aware stair API, §11 DoorData `is_secret` + `door_material` field plumbing. | Sonnet (Opus if §9.3's constraint-aware reordering surfaces tricky bitmask invariants). | **Complete 2026-05-27 (Opus 4.7).** Schema: `DungeonDoorData.is_secret: bool` + `door_material` populated; `TYPE_SECRET` removed from `VALID_TYPES`, replaced with `ROLL_CATEGORY_SECRET` as a roll-key the composer expands. Composer: `_assign_door_type` handles secret-as-overlay sub-weight (50/40/10), `_apply_door_materials` runs the §8.3 tier-scaled portcullis-override + metal-vs-wood roll, `_pre_place_anchor_rooms` reserves 3×3 antechambers from `required_stair_positions`, `_plan_stairs` skips anchor rooms, `_ensure_anchor_connectivity` is the §9.3.3 safety net. Generator wires `floor_tier` + anchors through. Test suite 365/19 (no regressions). Generation perf at tier 6: lair=2ms, small=6ms, medium=19ms, large=64ms (still well under §13.3 100ms target). Material distribution at tier 6 matches §8.3.2 expected (large dungeon: ~27 wood / ~10 metal / ~44 bars out of 110 non-arch non-secret doors). |
| **DG-V1.B (combined original)** | ~~Layout-generator companion edits: implement `gdd-dungeon-layout.md` §8.3 door material rule, §8.1 secret-as-overlay refactor, §9.3 constraint-aware stair API, §11 DoorData `is_secret` + `door_material` field plumbing.~~ | ~~Sonnet (Opus if the existing layout generator's bitmask code is unfamiliar)~~ | **Split 2026-05-27** into DG-V1.B-base + DG-V1.B-edits because the layout generator was discovered to not exist yet (grep confirmed during DG-V1.A); the build plan had presumed it existed. See build_log.md 2026-05-27 DG-V1.A entry. |
| **DG-V1.C** | Schema migrations + repositories: 6 new SQLite tables (`dungeon_floors`, `dungeon_rooms`, `dungeon_doors`, `monster_groups`, `treasure_hoards`, `key_items`) + DungeonGeneratorRepository CRUD. | Sonnet | **Complete 2026-05-28 (Opus 4.7).** Migration `132_dungeon_generator_v1.sql` (6 self-contained tables + indexes, no FK to `dungeons`). `DungeonGeneratorRepository` (RefCounted, static; uses `CampaignRepository.db`): `insert_dungeon_layout` (multi-floor, transactional, idempotent re-save), `get_dungeon_layout`→`Array[DungeonLayout]`, `get_floor`, `list_floors`, `delete_dungeon_layout` (cascade). Cells persist as positional `cells_json`; stairs as `stairs_json`; rooms/doors structured. Test suite 368/19 (+3 suites: roundtrip, cascade-delete, check-constraints). **Folded in:** `is_flammable` derived property (+`FLAMMABLE_MATERIALS`, `is_bashable`/`is_flammable`/`is_curtain` static helpers on DungeonDoorData) and the §8.4 curtain runtime-semantics reservation. **Deviations from plan (noted):** added `cells_json`/`stairs_json`/metadata columns to `dungeon_floors` for exact round-trip; `get_dungeon_layout` returns an Array (multi-floor) not a singular DungeonLayout; monster_groups/treasure_hoards/key_items CRUD deferred to DG-V1.D (tables + CHECK constraints created + tested now). |
| **DG-V1.D** | Generator orchestration: `DungeonGeneratorV1.generate(request)` — tier derivation, multi-floor layout calls with stair anchors, navigability validation, cross-floor key/lever placement, stocking, treasure resolution, acceptance tests, emit + persist. | **Opus for planning + ACKS rules integration; Sonnet for implementation** | Not started |
| **DG-V1.E** | End-to-end test scenarios: 6 scenarios covering 1-floor, 6-floor, entrance-in-middle, tier-clamping, fallback paths, and the trap/unique placeholder roundtrip. | Sonnet | Not started |

**Sequencing:** DG-V1.A → DG-V1.B-base → DG-V1.B-edits → DG-V1.C → DG-V1.D, with DG-V1.E landing incrementally per sub-phase (each preceding sub-phase ships its own unit tests; DG-V1.E adds *cross-sub-phase integration* scenarios). DG-V1.B-base must land before DG-V1.B-edits because the edits modify code DG-V1.B-base creates. DG-V1.C is independent of DG-V1.B-* (it adds schema only — no game logic) and could be interleaved if useful, but the listed order keeps the layout generator's interface stable before any persistence code lands.

---

## Required reading per session

Per `CLAUDE.md` Build Session Protocol:

1. `CLAUDE.md` itself.
2. `acks-build-log --last 1`, `--next-actions 3`, `--needs-review`. If today's task is in DG-V1.B/C/D, also `--for-task "dungeon generator"` and `--for-task "<sub-phase id>"`.
3. `docs/acks_arbiter_design_brief_v11.md`.
4. `docs/document_map.md` and `docs/rule_system_map.md` (when they exist).
5. `acks-conventions --for-task "<today's work>"` — particularly §3.3 (banker's rounding + the new RAW exception), §7.4 (runtime data extraction), §19 (EventScheduler) for DG-V1.D.
6. The V1 GDD and the layout GDD: **read both in full** at session start. `gdd-dungeon-generator-v1.md` and `gdd-dungeon-layout.md` are the controlling design documents.
7. For ACKS rule references encountered mid-session, use `acks-raw-lookup` (don't read XML directly). The build-time extraction in DG-V1.A is the ONLY session that touches the XML directly.

---

## Resolved decisions (apply to all sub-phases)

These are nailed down. Don't re-litigate during build; if you find a contradiction with these, escalate to Jedidiah rather than choosing.

**Tier API:** `(entrance_tier: int 1–6, floor_count: int ≥ 1, entrance_floor_index: int ≥ 1)`. Per-floor tier = `clamp(entrance_tier + |floor_index − entrance_floor_index|, 1, 6)`. Formula examples in V1 GDD §6.

**Single dungeon type:** Wizard's Dungeon. Any other `dungeon_type` value → log warning + fall back to wizards_dungeon. See V1 GDD §7.1.

**Lair coalescing:** OFF. Each rolled monster group is its own independent lair. Documented RAW deviation per V1 GDD §2 and §11.7.

**Trap rooms (d100 61–75):** `contents_kind = "trap_placeholder"`, one bordering door upgraded to `is_secret=true` AND `type="locked"` (the room's chosen door — random pick), treasure chance 30%. See V1 GDD §11.4.

**Unique rooms (d100 76–00):** `contents_kind = "unique_placeholder"`, re-roll on the §11.3 Monster procedure for fallback content, treasure follows lair rules. See V1 GDD §11.5.

**Trapped doors (door type from layout §8.1):** keep `type = "trapped"` (encoded), `door_state = "locked"` initially, behave as Locked at runtime. See V1 GDD §10.5.

**Door material rule:** layout GDD §8.3 — for each non-arch, non-portcullis, non-secret-overlay door: roll d100, if ≤ `5 × tier` → portcullis override (drop other type flags, `door_material = "metal_bars"`); else roll d100, if ≤ `5 × tier` → metal (50% iron / 50% stone); else `door_material = "wood_standard"`.

**Secret-as-overlay:** layout GDD §11 — `is_secret: bool` is an orthogonal overlay on DoorData. The `type` enum no longer includes `"secret"`. A "Secret door" roll on §8.1 produces underlying_type + `is_secret=true`.

**Stair placement:** constraint-aware via layout GDD §9.3 `required_stair_positions`. Post-hoc carving demoted to catastrophic-failure safety net (log loudly if it fires).

**Round-down for cross-tier number appearing:** per coding_conventions.md §3.3 RAW exception. Use `floori()`, not `roundi()`. Cite the convention section inline at the call site.

**NPC party tier-to-level:** lower end of each range — tier 1→1, tier 2→2, tier 3→4, tier 4→6, tier 5→8, tier 6→10. Randomization deferred.

**No runtime XML reads.** Anywhere. Per coding_conventions §7.4.

**Treasure resolved to specific items at generation time** (not deferred). Magic item placeholders only when the magic item catalog itself is incomplete.

**Key/lever placement is cross-floor** with the floor-weighting in V1 GDD §10.3 (weight 5 same-floor, 2 adjacent, 1 distant).

**Wizard's Dungeon as universal fallback:** any unknown `dungeon_type` returns a Wizard's Dungeon (V1 GDD §7.1). Downstream systems can pass any string; they get a Wizard's Dungeon back.

---

## Sub-phase DG-V1.A — Build-time data extraction

### Goal

Encode every ACKS table the V1 generator needs into `data/dungeon_generator/*.json` per coding_conventions §7.4. Build the idempotent extraction script and the CI diff test. **No game logic in this sub-phase.**

### Files to create

- `tools/extract_dungeon_generator_data.py` — single-purpose Python script. Header docs list input XML files, output JSON files, and invocation command. Idempotent (re-running produces byte-identical output for identical input). Includes a `--check` mode that does a dry run and exits non-zero if output would differ from on-disk JSON.
- `data/dungeon_generator/dungeon_stocking.json` — extracted from `rules/acore-setting-construction-rules.xml:629-641` (`dungeon_stocking` table).
- `data/dungeon_generator/dungeon_wandering_monster_level.json` — extracted from `rules/acore-monster-stocking-rules.xml:76-94`.
- `data/dungeon_generator/random_monsters_by_level.json` — extracted from `rules/acore-monster-stocking-rules.xml:112-136`.
- `data/dungeon_generator/wandering_monster_table_guidelines.json` — extracted from `rules/acore-monster-stocking-rules.xml:96-110`.
- `data/dungeon_generator/unprotected_treasure.json` — extracted from `rules/acore-setting-construction-rules.xml:760-778`.
- `data/dungeon_generator/treasure_type_table.json` — extracted from `rules/acore_treasure_and_magic_items_rules.xml:56-87`.
- `data/dungeon_generator/gem_values.json` and `data/dungeon_generator/jewelry_values.json` — extracted from `rules/acore_treasure_and_magic_items_rules.xml` gems and jewelry sections (read the full XML to find exact line ranges; they are below the treasure_type_table).
- `data/dungeon_generator/npc_class.json`, `npc_alignment.json`, `npc_level.json`, `npc_treasure_type_by_level.json` — extracted from `rules/acore-monster-stocking-rules.xml:479-548`.
- `tests/data_integrity/test_dungeon_generator_data_freshness.gd` (or `.py` if the project's existing data-integrity tests are Python). Mirror whatever pattern `tests/data_integrity/` already uses; if it doesn't exist yet, GDScript using the project's existing GUT or in-house test harness. The test re-runs the extraction script into a temp directory and diffs against the committed JSON.

### Per-file structure

Each JSON file MUST include the `_source` field per coding_conventions §7.4.2:

```json
{
  "_source": "rules/acore-monster-stocking-rules.xml:76-94 dungeon_wandering_monster_level",
  "_extracted_by": "tools/extract_dungeon_generator_data.py",
  "_extracted_at": "<UTC ISO timestamp>",
  "rows": [ ... ]
}
```

The shape of the body (`rows`, `table`, etc.) should mirror the XML structurally — preserve column names verbatim from the XML, preserve row order, preserve cell values verbatim (including dice notation strings like "2d4" — they are runtime parsed, not pre-resolved).

### Acceptance criteria

- The extraction script runs cleanly from the project root: `python tools/extract_dungeon_generator_data.py`.
- Re-running produces byte-identical output.
- The CI diff test runs cleanly and fails if any JSON file differs from what the script produces.
- Every JSON file has a `_source` field citing the originating XML and section/table name.
- All cell values in `random_monsters_by_level.json` parse cleanly (a follow-on validation test would tokenize each cell into `{monster_name: string, number_appearing_dice: string}` — write this validation as part of the integrity test).

### Out of scope

- The monster catalog extraction. Monsters are handled by their own existing extraction pipeline; this sub-phase consumes the monster catalog by name lookup only.
- Any runtime loader. DG-V1.D builds the loader and consumes these files.

### Build log entry requirements

In addition to the standard template (per `acks-build-log` `references/entry_template.md`):

- List every JSON file created with line count.
- Note the total row count extracted per table for sanity-checking.
- Flag any XML cells the extraction had to massage (the wilderness tables in acore-monster-stocking-rules.xml have `source_format_note` attributes indicating merged-cell artifacts — record any encountered, even though the V1 dungeon generator doesn't consume the wilderness tables).

---

## Sub-phase DG-V1.B-base — Build the dungeon layout generator (first implementation)

### Goal

Implement the dungeon layout generator from scratch per `gdd-dungeon-layout.md` §§4–11 baseline (NOT the §8.3 / §9.3 / §11-overlay companion edits — those land in DG-V1.B-edits). The output must conform to the DungeonLayout schema in layout GDD §11 (the BASELINE schema, without `is_secret` and without `door_material` populated by §8.3 — those come in DG-V1.B-edits).

### Background — why this sub-phase exists

Discovered during DG-V1.A: the layout generator described in `gdd-dungeon-layout.md` has never been implemented. Grep confirms no GDScript file references bitmask flag names (`PERIMETER`, `ROOM_ID`, `STAIR_DN`, donjon, bitmask) outside the design documents. The build plan originally presumed the generator existed and only needed companion edits; that assumption is wrong. DG-V1.B-base fills the gap; DG-V1.B-edits then adds the companion edits on top.

### Files to create

Under `engine/subsystems/generation/dungeon_layout/`:

- `dungeon_generator.gd` — main entry: `static func generate(request: DungeonLayoutRequest) -> DungeonLayout`. RefCounted; no autoload (no `class_name` conflict risk).
- `dungeon_theme.gd` + `dungeon_theme_data.json` — theme parameters per §5.1. For V1, Wizard's Dungeon is the only fully-populated theme; other themes can be skeleton entries with sensible defaults.
- `grid_operations.gd` — bitmask grid helpers (§4.2): set/clear flags, room placement (§6), corridor carving (§7), door placement (§8.1 BASELINE — types only, no §8.3 material rule yet).
- `cell_finalizer.gd` — bitmask grid → CellData grid (§10.1).
- `room_detector.gd` — flood-fill room detection + room metadata (§10.2).
- (Optional, defer to V2) `encounter_table_builder.gd` — out of scope for V1 per V1 GDD §7.3 (Wizard's Dungeon uses raw `random_monsters_by_level`).

Shared data types:

- `engine/shared_types/dungeon_layout_data.gd` (or extend an existing shared_types file if appropriate) — `DungeonLayout`, `RoomData`, `DoorData`, `StairData`, `CellData` per the layout GDD §11 schema. NOTE: the baseline schema; DG-V1.B-edits will add `is_secret` to `DoorData` and populate `door_material`.
- `DungeonLayoutRequest` — `{dungeon_type, dungeon_size, level_number, seed, regional_context}` per layout GDD §12.1.

### New unit tests

Under `tests/subsystems/generation/dungeon_layout/` (create the directory):

- `test_dungeon_generator_basic.gd` — generate a Wizard's Dungeon at each of the 4 sizes (lair / small / medium / large), assert room count is within the GDD §3 expected range.
- `test_grid_operations_room_placement.gd` — focused unit tests for room scatter: collisions are detected, perimeter buffers are respected, target room count is approached.
- `test_corridor_carving.gd` — for each `corridor_style` (`straight`, `bent`, `labyrinth`) and `corridor_width` (`narrow`, `standard`, `wide`, `mixed`), generate a small dungeon and assert the corridor cells satisfy basic invariants (no isolated corridors, 2-wide carving where standard).
- `test_room_detector.gd` — hand-build a small bitmask grid with known rooms, run flood-fill, assert the room IDs and metadata match expectations.
- `test_cell_finalizer.gd` — feed known bitmask grids in and assert the corresponding CellData grids have correct passable / blocks_los / door_state values for each flag combination.
- `test_dungeon_layout_navigability.gd` — for a large set of generated dungeons (seeded), assert every room is reachable from the entrance with all doors treated as passable (the layout-navigability test the V1 GDD §9.1 requires).

### Acceptance criteria

- `DungeonGenerator.generate(request)` returns a fully-populated `DungeonLayout` for the four size categories.
- Generation is reproducible for a given seed.
- Every generated dungeon passes the layout-navigability test (§9.1 — every room reachable with doors treated as passable). The post-hoc carving fallback (§9.1) is the recovery mechanism if connectivity fails.
- The DungeonLayout output matches the schema in `gdd-dungeon-layout.md` §11 BASELINE (no `is_secret` field on DoorData yet; `door_material` may be unset or a single default value — DG-V1.B-edits handles material rolling).
- All new unit tests pass.
- The pre-existing test suite continues to pass (no regressions).

### Out of scope (defer to DG-V1.B-edits or V2)

- §8.3 door material rule (DG-V1.B-edits).
- §8.1 step 5 secret-as-overlay refactor (DG-V1.B-edits).
- §9.3 constraint-aware stair placement (DG-V1.B-edits).
- §11 DoorData `is_secret` field (DG-V1.B-edits).
- Cellular automata for cavern-type dungeons (V2 — not needed for Wizard's Dungeon).
- Tag-filtered encounter table construction (V2 per layout GDD §5.3 — Wizard's Dungeon uses raw tables per V1 GDD §7.3).
- Multi-level spatial coherence for above-ground structures (V2 — Wizard's Dungeon is subterranean).
- Room purpose tables for every dungeon type (V2 — V1 only needs Wizard's Dungeon's table from layout GDD §6.3).

### Build log entry requirements

- List every file created.
- Note any places where the layout GDD's spec was ambiguous and which interpretation was picked.
- Track approximate generation time for each dungeon size (the §13.3 performance target is < 100ms even for large grids).

---

## Sub-phase DG-V1.B-edits — Companion edits to the new layout generator

### Goal

Apply the companion edits Jedidiah authorized to the DG-V1.B-base layout generator: §8.3 door material rule, §8.1 secret-as-overlay refactor, §9.3 constraint-aware stair API, §11 DoorData schema with `is_secret` overlay and `door_material` always populated.

### Files to edit

The files created in DG-V1.B-base under `engine/subsystems/generation/dungeon_layout/`:

- `dungeon_generator.gd` — accept new `required_stair_positions: Array` parameter on the generate signature.
- `grid_operations.gd` — implement the §9.3.2 reordered pipeline: pre-place anchor cells in the bitmask grid as `ROOM | ENTRANCE | STAIR_<dir>` before room scatter; mark 1-cell perimeter around each anchor as `PERIMETER`; pre-carve anchor landings.
- `cell_finalizer.gd` — emit `door_material` per the new §8.3 rule. Emit `is_secret: bool` on DoorData. The `type` enum no longer accepts `"secret"`; convert any legacy "secret" type values to `(underlying_type, is_secret=true)` per §8.1 step 5.
- Wherever the door-type weighted roll lives — implement §8.1 step 5: a "Secret door" roll triggers a sub-weight roll (50% unlocked / 40% locked / 10% trapped) for `underlying_type`, then sets `is_secret = true`.
- Wherever post-§8.1 door processing happens — add the §8.3 material/portcullis-override pass.
- `engine/shared_types/dungeon_layout_data.gd` (or wherever the DoorData type was created in B-base) — add `is_secret: bool` field; ensure `door_material` is always populated.

### New unit tests

Under `tests/subsystems/generation/dungeon_layout/`:

- `test_door_material_rule.gd` — for each tier 1–6, generate a batch of doors and assert the resulting material distribution is statistically within ±5pp of the §8.3.2 expected table (use ~1000 doors per tier for stable means).
- `test_is_secret_overlay.gd` — generate a batch of doors; assert no door has `type == "secret"`; assert that doors with `is_secret == true` have `type ∈ {"unlocked", "locked", "trapped"}`; assert the sub-weight (50/40/10) holds within ±5pp.
- `test_constrained_stair_placement.gd` — for a set of pre-chosen anchor positions on a small grid, call the generator and assert every anchor cell ends up with `STAIR_<dir>` AND is connected to the room/corridor network (BFS reachability check).
- `test_layout_navigability_with_anchors.gd` — for a stack of anchor positions that would naturally be hard for a free-placement layout to satisfy (e.g., two anchors near opposite corners), assert generation still succeeds and produces a connected layout.

### Acceptance criteria

- `gdd-dungeon-layout.md` §8.1, §8.3, §9.3, §11 are all reflected in code.
- The layout GDD's existing tests (any pre-existing layout tests) continue to pass.
- New tests pass.
- No code path emits `type == "secret"` anywhere.
- Every emitted DoorData has both `door_material` and `is_secret` populated (no nulls).
- The post-hoc carving fallback in `DungeonGeneratorV1.§8.1` is never triggered by a normal generation request (the constraint-aware path always succeeds for legal anchor inputs).

### Build log entry requirements

- List the layout generator file paths actually touched (the V1 GDD's file map is illustrative; verify).
- Note any places where the existing layout code's assumptions about door types conflict with the new is_secret overlay model — patch them and call them out.
- Flag any tests in the existing layout test suite that needed updates because of the schema changes (DoorData additions).

---

## Sub-phase DG-V1.C — Schema migrations + repositories

### Goal

Create the SQLite tables that persist V1 dungeons. Build the repository CRUD. **No generation logic.**

### Migration

`db/migrations/<next_migration_number>_dungeon_generator_v1.sql`:

- `dungeon_floors` — `(id, dungeon_id, floor_index, floor_tier, is_entrance_floor, total_monster_xp, total_treasure_gp_value, xp_to_gp_ratio, encounter_table_row, grid_width, grid_height)`.
- `dungeon_rooms` — `(id, floor_id, room_id_in_floor, bounds_x, bounds_y, bounds_w, bounds_h, area_sqft, center_x, center_y, original_purpose, current_purpose, contents_kind, monster_group_id, treasure_hoard_id)`. `contents_kind` CHECK: `IN ('empty', 'monster', 'monster_lair', 'trap_placeholder', 'unique_placeholder')`.
- `dungeon_doors` — `(id, floor_id, position_x, position_y, type, is_secret, door_state, door_material, is_evil, connects_room_ids, required_key_id, wired_lever_position_x, wired_lever_position_y)`. `type` CHECK: `IN ('arch', 'unlocked', 'locked', 'trapped', 'portcullis')` (note: `'secret'` is NOT a type — it is an `is_secret BOOLEAN` overlay column per the §8.1 step-5 refactor). `door_material` CHECK: `IN ('', 'curtain_cloth', 'curtain_leather', 'wood_standard', 'wood_thick', 'stone', 'metal')` (the canonical 6-material vocabulary + the empty-string none/arch sentinel; mirrors `DungeonDoorData.VALID_MATERIALS`). `is_secret` is a `BOOLEAN NOT NULL DEFAULT 0` column.
- `monster_groups` — `(id, room_id, floor_id, monster_name, monster_xp_each, number_appearing, hd, associated_creatures, is_lair, morale, alignment, treasure_type_letter, initial_inventory)`. `associated_creatures` and `initial_inventory` are JSON blobs.
- `treasure_hoards` — `(id, room_id, floor_id, source, treasure_type_letter, copper, silver, electrum, gold, platinum, gems, jewelry, magic_items, total_gp_value, is_hidden)`. `gems` / `jewelry` / `magic_items` are JSON blobs. `source` CHECK: `IN ('lair', 'unprotected_empty', 'unprotected_trap_placeholder', 'unprotected_unique_placeholder')`.
- `key_items` — `(id, opens_door_floor_id, opens_door_position_x, opens_door_position_y, placed_in, placed_in_room_id, placed_on_floor_id)`. `placed_in` CHECK: `IN ('monster_group_inventory', 'treasure_hoard', 'loose_in_room')`.
- Indexes: `(dungeon_id)` and `(floor_id)` on every child table for fast lookup; `(floor_id, room_id_in_floor)` on `dungeon_rooms`.
- No FK constraints to the existing `dungeons` table — keep the dungeon-generator tables self-contained per the existing pattern in `domain_departure_log` (per coding_conventions §57).

### Repository

`engine/subsystems/generation/dungeon_generator_v1/dungeon_repository.gd`:

- `insert_dungeon_layout(dungeon_id, layout: DungeonLayout) -> bool`
- `get_dungeon_layout(dungeon_id) -> DungeonLayout`
- `list_floors(dungeon_id) -> Array[DungeonFloorMeta]`
- `get_floor(floor_id) -> DungeonFloorData` (rooms + doors + monster_groups + treasure_hoards + key_items denormalized into the existing in-memory `DungeonLayout` shape from `gdd-dungeon-layout.md` §11 + the V1 additions per V1 GDD §4.2).
- `delete_dungeon_layout(dungeon_id) -> bool` (cascading delete across all six tables).

Use parameterized `query_with_bindings` everywhere per the godot-sqlite usage notes in CLAUDE.md. Transactional inserts for the multi-table layout persistence (one transaction per `insert_dungeon_layout` call).

### Unit tests

Under `tests/subsystems/generation/dungeon_generator_v1/`:

- `test_dungeon_repository_roundtrip.gd` — insert a hand-built DungeonLayout, get it back, assert structural equality.
- `test_dungeon_repository_cascade_delete.gd` — insert, delete, assert all child tables are empty for that dungeon_id.
- `test_dungeon_repository_check_constraints.gd` — attempt inserts with invalid `contents_kind`, `door type`, `door_material`, `source`, `placed_in` values; assert all rejected.

### Acceptance criteria

- Migration runs cleanly (forward + idempotent re-run with `IF NOT EXISTS`).
- Repository roundtrip preserves every field of every record.
- All CHECK constraints are enforced (verified by tests).
- No autoload-singleton conflicts (per CLAUDE.md: `class_name` must NOT appear in autoload scripts; the repository should be a regular RefCounted, not an autoload).

### Build log entry requirements

- Record the assigned migration number.
- Record any CHECK constraints that needed adjustment after schema design conversations.
- Confirm the JSON-blob columns (`associated_creatures`, `initial_inventory`, `gems`, `jewelry`, `magic_items`) are stored as TEXT and parsed at retrieval; document the JSON schema for each in the repository docstring.

---

## Sub-phase DG-V1.D — Generator orchestration

### Goal

The V1 generator itself. Implements the full V1 GDD §5 pipeline.

### File structure

```
engine/subsystems/generation/dungeon_generator_v1/
  dungeon_generator_v1.gd               # Main entry: DungeonGeneratorV1.generate(request)
  tier_derivation.gd                    # Per-floor tier formula (V1 GDD §6)
  encounter_roller.gd                   # The two-stage monster roll (V1 GDD §11.3)
  treasure_resolver.gd                  # Treasure type → coins/gems/jewelry/magic items (V1 GDD §13)
  key_lever_placer.gd                   # Cross-floor outside-region BFS + placement (V1 GDD §10)
  stocker.gd                            # d100 per room + trap/unique fallbacks (V1 GDD §11)
  navigability_validator.gd             # Both passes (V1 GDD §9)
  acceptance_tests.gd                   # Hard + soft tests (V1 GDD §14)
  loaders/
    dungeon_data_loader.gd              # Loads data/dungeon_generator/*.json once at startup
                                        # NOTE: not an autoload; called by the generator
```

### Entry signature

```gdscript
# dungeon_generator_v1.gd
static func generate(request: DungeonGeneratorRequestV1) -> DungeonGeneratorResultV1:
    # request fields per V1 GDD §4.1
    # returns result with: layout (Array[DungeonLayout], one per floor), key_items, success bool, errors Array
```

### Implementation order within DG-V1.D

This sub-phase is the largest. Implement in this order to keep each piece testable:

1. **`tier_derivation.gd`** — pure function, no dependencies. Unit-test with the worked examples table from V1 GDD §6.
2. **`dungeon_data_loader.gd`** — loads the DG-V1.A JSON files into typed in-memory dicts. Unit-test that every file loads and the expected shape is present.
3. **`encounter_roller.gd`** — consumes the loader's tables. Two-stage roll per V1 GDD §11.3. Cross-tier number-appearing adjustment with `floori()` per the §2 RAW exception + coding_conventions §3.3. Unit-test the tier-1 through tier-6 distributions and the cross-tier adjustment edge cases (tier_diff = 0, 1, 2, -1, -2).
4. **`treasure_resolver.gd`** — consumes the loader's treasure tables. Per V1 GDD §13.1 — for a given treasure type letter, roll each column, materialize coins / gems / jewelry / magic items. For magic items, query the magic item catalog if it exists; emit a placeholder per §13.4 if the category is empty. Unit-test type A and type R (lightest and heaviest); spot-check 2-3 middle types.
5. **`stocker.gd`** — d100 per room. Empty / Monster / Trap-placeholder / Unique-placeholder branches per V1 GDD §11.2–§11.5. Honors §11.7 no-coalescing. Calls `encounter_roller.gd` and `treasure_resolver.gd`. Sets `current_purpose` per §11.6 table.
6. **`navigability_validator.gd`** — layout pass (§9.1) and solvability pass (§9.2). The solvability pass is the fixed-point BFS with key-discovery / lever-discovery expansion. Unit-test with hand-built minimal layouts (a 2-room dungeon with one locked door + key).
7. **`key_lever_placer.gd`** — per V1 GDD §10. Door inventory → outside-region BFS per door → weighted room selection → KeyItem / lever creation. §10.4 "no outside region" downgrade logic. Unit-test the weighted selection distribution and the no-outside-region downgrade.
8. **`acceptance_tests.gd`** — runs §14 hard tests + §14 soft tests after stocking. Returns a structured report.
9. **`dungeon_generator_v1.gd`** — the orchestrator. Calls layout generator (with stair anchors from DG-V1.B), runs key/lever placement, runs stocker, runs treasure resolution, runs acceptance tests. Persists via the DG-V1.C repository. Returns the result.

### Action vocabulary registrations (per CLAUDE.md step 11)

V1 generator emits the following new action vocabulary entries (for the runtime to handle):

- `lever_actuate` — already exists per `gdd-dungeon-map-ui.md`. Verify the V1-emitted `lever_portcullis_<door_position>` terrain_feature naming convention matches what the existing lever action expects.
- No new actions needed; V1 produces data, not actions. Confirm with a grep of the action vocabulary file at session start.

### Cross-cutting requirements

- **Round-down for cross-tier number appearing:** every call site uses `floori()` with the inline comment `# RAW: rules/acore-monster-stocking-rules.xml:42-46 — round DOWN. Exception per coding_conventions.md §3.3.`
- **No autoload conflicts:** no `class_name` in any file that ends up autoloaded. The `dungeon_data_loader.gd` is intentionally NOT an autoload — it's called explicitly so the generator's data dependencies are visible at the call site.
- **SQLite usage:** `query_with_bindings` for all parameterized writes; one transaction wrapping the full `insert_dungeon_layout` per the DG-V1.C repository.
- **Logging:** per coding_conventions §8.1, every error includes what was attempted + what failed + relevant state. `[BALANCE]` warnings for XP/GP ratio drift per V1 GDD §13.3.
- **The build log entry must track placeholder counts** (per V1 GDD §16): trap_placeholder count, unique_placeholder count, trapped_door count per generated dungeon. The DG-V1.D acceptance tests should record these in the result and the build log entry should sample them.

### Acceptance criteria

For a single `(entrance_tier=1, floor_count=3, entrance_floor_index=1)` generation:

- Generation succeeds.
- 3 floors produced.
- Per-floor tiers are [1, 2, 3].
- Every locked door (any material) has either a placed key OR is wooden (bashable).
- Every portcullis has either a placed lever OR is forceable.
- Every Trap-placeholder room has exactly one bordering door with `is_secret=true` AND `type ∈ {"locked", "trapped"}`.
- Every Unique-placeholder room has a non-null `monster_group_id`.
- Global solvability test passes: BFS from entrance reaches every stair on every floor.
- Persistence roundtrip: generate, persist, re-load, structural equality.
- All V1 GDD §14.1 hard tests pass.

### Build log entry requirements

- Per-sub-phase implementation order list with which pieces shipped + which deferred to follow-on sessions if scope splits.
- Placeholder counts from a sample generation (per the cross-cutting requirement above).
- Any magic-item-catalog gaps encountered + the categories needed (per V1 GDD §13.4).
- Any spots where the layout generator's behavior surprised the orchestration (so the layout GDD can be patched if needed).
- The XP/GP ratio for a sample generation, with a note whether `[BALANCE]` warnings fired.

---

## Sub-phase DG-V1.E — End-to-end test scenarios

### Goal

Integration tests that exercise the full pipeline across realistic input variations. Land incrementally — write the scenario for the input space DG-V1.D just enabled.

### Scenarios

Under `tests/scenarios/generation/dungeon_generator_v1/`:

1. **`scenario_lair_single_floor_tier1.gd`** — `(entrance_tier=1, floor_count=1, entrance_floor_index=1, dungeon_size="lair")`. Smallest possible dungeon. Validates the basic path with minimal complexity.
2. **`scenario_medium_three_floor_subterranean.gd`** — `(entrance_tier=1, floor_count=3, entrance_floor_index=1, dungeon_size="medium")`. The canonical test case from DG-V1.D acceptance criteria.
3. **`scenario_six_floor_tier_clamp.gd`** — `(entrance_tier=3, floor_count=6, entrance_floor_index=1, dungeon_size="large")`. Per-floor tiers should be [3, 4, 5, 6, 6, 6] (last two clamped to 6). Validates the clamp + tier 6 stocking. Should produce a high portcullis/metal-door fraction per §8.3.2.
4. **`scenario_entrance_in_middle.gd`** — `(entrance_tier=2, floor_count=5, entrance_floor_index=3, dungeon_size="medium")`. Per-floor tiers should be [4, 3, 2, 3, 4]. Validates the bidirectional tier formula and stair-anchor placement across non-adjacent floors.
5. **`scenario_placeholder_fallbacks_active.gd`** — repeat the medium-three-floor generation with a fixed seed chosen so the stocking d100 produces several Trap and Unique results. Assert every Trap-placeholder room has a Locked+Secret door fallback and every Unique-placeholder room has a monster_group_id fallback. Validates the encode-and-fallback pattern.
6. **`scenario_invalid_dungeon_type_fallback.gd`** — call with `dungeon_type = "tomb"` (a known type that V1 doesn't yet support) and `dungeon_type = "garbage"` (an unknown string). Both should produce a Wizard's Dungeon with the warning logged. Validates the §7.1 fallback.

Each scenario:

- Generates with a fixed seed (deterministic for CI).
- Asserts the V1 GDD §14.1 hard tests pass.
- Asserts the per-scenario expected outputs (tier list, monster groups present, treasure present, etc.).
- Logs the placeholder counts + XP/GP ratio for traceability.

### Acceptance criteria

- All 6 scenarios pass deterministically.
- Coverage report (if the project has one): every public method in `dungeon_generator_v1.gd` is exercised by at least one scenario.
- The scenario runner output is human-readable enough that a regression failure points to which assertion broke.

### Build log entry requirements

- Per-scenario fixed seed + the generated dungeon's headline numbers (floor count, total monster count, total GP value, placeholder counts).
- Any flaky-seed cases where a seed that worked one day failed another → root-cause to the RNG (every random consumer must take the seeded RandomNumberGenerator instance, not call `randi()` directly).

---

## Cross-cutting requirements (all sub-phases)

### Coding conventions

Consult `acks-conventions --for-task "<sub-phase id>"` before writing. The conventions most likely to bite:

- **§3.3** banker's rounding + the new RAW exception for cross-tier number-appearing.
- **§3.7** `class_name` rules (no `class_name` in autoload scripts).
- **§4** signal conventions (past-tense, snake_case).
- **§6.1** godot-sqlite API (parameterized via `query_with_bindings`, not string concatenation).
- **§7.4** runtime data extraction (DG-V1.A is the canonical second instance).
- **§8.1** error logging format.
- **§9** testing patterns.

If you find yourself making a judgment call about style or structure during a sub-phase, document it in coding_conventions.md per the maintenance procedure in CLAUDE.md.

### Build log discipline

Per CLAUDE.md every session ends with an appended entry to `build_log.md` using `acks-build-log` `references/entry_template.md`. Lint with `acks-build-log --lint` after appending. The Status field for the affected sub-phase in this build plan should be updated in the same session.

### Escalation triggers

Stop and ask Jedidiah (do not choose unilaterally) if you encounter:

- A RAW citation that contradicts a decision in this plan.
- A coding convention that contradicts a decision in this plan.
- A schema design choice that would require changing a cross-subsystem interface defined outside this plan.
- A magic item category gap that suggests the magic item catalog needs urgent attention before DG-V1.D's treasure resolution can complete.
- A spot where the layout GDD's existing code structure makes the §8.3 / §9.3 / §11 companion edits significantly harder than expected (e.g., the cell finalizer's door processing is intertwined with rendering in a way that resists refactor).
- Any place where you'd otherwise mark `[NEEDS-OPUS-REVIEW]` in the build log.

---

## Out of scope (V1 → defer to V2)

These appear in the V1 GDD §15 and are NOT to be built in this plan. If a sub-phase ends up adjacent to one of these, leave a placeholder + a TODO + a note in the build log.

- Trap mechanisms (V2 trap GDD owns this).
- Unique encounter content (V2 unique-encounter system).
- Non-Wizard's-Dungeon dungeon types.
- Dungeon factions (`gdd-dungeon-factions.md`).
- Tag-filtered encounter table construction.
- LLM narrative pass on rooms.
- Auto-balancing of XP/GP ratio.
- Overstocking + patrols + respawn (the eventual replacement for wandering monster tables).
- Hidden treasure mechanics (runtime Search-check rules).
- Cellular automata for cave-type dungeons.
- Above-ground tier-direction redesign.
- Magic item catalog backfill (catalogs are an independent stream of work; V1 emits placeholders).

---

## Document conventions

- **Status updates land in this file** when work ships. Don't renumber sub-phase ids.
- **Resolved decisions land in this file's "Resolved decisions" section** if they emerge mid-build. The build log records the conversation; this file is the durable summary.
- **Per-sub-phase newly-discovered scope** lands in this file as a new "DG-V1.<letter>.<N>" sub-sub-phase, NOT as a renamed existing sub-phase.

---

## Revision history

- **2026-05-27:** Initial draft. Five sub-phases (DG-V1.A through DG-V1.E). All resolved decisions from the V1 GDD draft v1.1 rev 3 folded in.
