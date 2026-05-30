## Session 2026-05-29 — Magic-item triage: cut + defer flags on the random-roll table

**Task:** Triage the ~80 still-unwired magic items into Cut / Defer / Build buckets. This commit lands the Cut + Defer dispositions for Tier 1 of the triage (Jedidiah-confirmed 2026-05-29). 9 items removed from the random-roll table via a re-roll loop; 4 items kept in the table but flagged as "no in-game activation yet". Tier 2/3/4 (bind / shared resolver / custom resolver) decisions come in subsequent batches.

**Model used:** Opus.

**Completed:**
- **`CUT_FOR_V1` map** added to `tools/extract_magic_item_catalog.py` (9 items + per-item reason). Each item gets `cut_for_v1: true` + a `cut_reason` string stamped into the catalog JSON.
  - **Vehicles (3):** Apparatus of the Crab, Boat/Folding, Flying Carpet — each requires its own travel subsystem for a single-item payoff.
  - **Single-item subsystems (4):** Mirror of Life Trapping, Mirror of Opposition, Cube of Force, Helm of Alignment Changing — each is a one-off mechanic that won't apply elsewhere.
  - **Unmodeled state (2):** Potion of Sweet Water (water purity), Potion of Diminution (size category sub-Small). Age + alignment changes were also in the "unmodeled" bucket but Potion of Longevity moved to DEFER (Jedidiah wants the slot kept findable for the future).
- **`DEFER_BUILD` map** added to the same extractor (4 items + per-item reason). Each item gets `defer_reason: "..."` but stays selectable by the random roller:
  - **Ring of Wishes** — eventually a canned-list resolver (Jedidiah confirmed the future shape).
  - **Potion of Longevity** — kept on the table per Jedidiah; no functional effect until age becomes gameplay-affecting.
  - **Eyes of Petrification** — gaze-attack subsystem confirmed UNWIRED via codebase scan (only data exists on monster_catalog for basilisk / medusa; no resolver code in engine/).
  - **Treasure Map** — kept; quest-hook generation is its own arc.
- **`MagicItemCatalog.random_item_in_category` extended with re-roll loop:** cuts are filtered via a 10-attempt re-roll (vanishingly small failure rate — highest per-category cut share is misc_magic at 6/48 ≈ 12.5%, so 10 misses has probability < 1e-9). Defensive deterministic fallback (first non-cut item in document order) for the edge case of an all-cut category — guarantees a return, never an infinite loop or empty dict.
- **New read-API helpers** on `MagicItemCatalog`: `is_cut(item_key) → bool` and `defer_reason(item_key) → String`. Used by tests; reusable by tooling that wants to enumerate skips (e.g. random-loot debugging).
- **Decanter of Endless Water** flagged for the next session's BUILD work — Jedidiah wants the wilderness loop's water-consumption code to auto-refill containers from an inventoried Decanter, capped at the decanter's output rate (analog of entering a river hex). NOT landed this commit.
- **Oil of Slipperiness** flagged for the next session's BUILD work — Jedidiah wants a reusable surface-coat resolver (oils, grease spells share the pattern). NOT landed this commit.
- **4 new tests** in `tests/test_magic_item_catalog.gd`:
  - `test_cut_items_are_flagged_in_catalog` — every expected cut carries `cut_for_v1=true` + non-empty `cut_reason`.
  - `test_defer_items_are_flagged_with_reason` — every expected defer carries a non-empty `defer_reason` and is NOT cut.
  - `test_random_item_in_category_never_returns_cut_item` — sweeps 200 seeds across every category with at least one cut; the re-roll never produces a cut.
  - `test_defer_items_are_selectable_by_random_roll` — sweeps 500 seeds and confirms each expected defer key is selectable at least once (carriable / sellable / shop-priced; just no activation yet).
- **GDD §16.7** added — "Table-status flags (cut_for_v1, defer_reason)" — documents the flag shape, the re-roll mechanism, and the current V1 cut + defer lists.
- **Memory file `magic_item_bindings_deferred.md`** updated with the final dispositions + the remaining triage buckets (Tier 2/3/4/5) for future sessions.

**Decisions made:**
- **Re-roll, not filter.** Cuts stay in the catalog file (preserving d100 ranges, value_gp for accounting, identifying numbers for telemetry) and `random_item_in_category` bounces past them. Mathematically equivalent to filtering since selection is uniform-within-category; semantically preserves "the items exist, we just don't include them" — important for a future pass that flips a cut → defer or bound.
- **Cut vs Defer distinction:** Cut items are GONE from the random table; Defer items stay findable. The use cases differ:
  - **Cut** = the project will never implement this in V1; we don't want players to encounter unimplemented items.
  - **Defer** = the project plans to implement this eventually; players can find them as inert carriables now and sell them through ShopService (per `value_gp`) until the subsystem lands.
- **Potion of Longevity stays in the table per Jedidiah.** Despite age being unmodeled, the slot reserved for it should not be re-rolled away — keeps the random-table semantics close to RAW.
- **Eyes of Petrification stays in the table per Jedidiah.** Codebase scan confirmed gaze-attack mechanics ARE catalogued (basilisk, medusa, cockatrice all carry `gaze_petrification`/`petrifying_gaze`/`charm_gaze` ability_id data) but the engine has NO resolver code wiring them into combat. So Eyes of Petrification correctly defers as a "kept findable, blocked on gaze-attack resolver landing" item.
- **Treasure Map stays in the table per Jedidiah.** Its 13 sub-variants (the scrolls d100 table) need quest-hook generation; the deferred-until-quest-system flag preserves the random-table slot.
- **10-attempt re-roll cap + deterministic fallback.** The 10-attempt cap is huge overhead given the actual cut rates (max 13% per category → expected attempts ≈ 1.15), but cheap to maintain and bulletproof. The fallback scan handles the degenerate "all items in a category are cut" case that doesn't exist today but defends against future configuration drift.

**Interfaces defined or changed:**
- Catalog item dict shape: new optional fields `cut_for_v1: bool` (default false) + `cut_reason: String` + `defer_reason: String`.
- `MagicItemCatalog.is_cut(item_key: String) -> bool` (NEW).
- `MagicItemCatalog.defer_reason(item_key: String) -> String` (NEW; "" when not deferred).
- `MagicItemCatalog.random_item_in_category` behavior change: cuts are skipped via re-roll. Defer items selectable as before.
- `tools/extract_magic_item_catalog.py` — `CUT_FOR_V1` + `DEFER_BUILD` maps.

**Database changes:** None.

**Tests added/updated:**
- `tests/test_magic_item_catalog.gd` — 4 new tests; suite extended.
- Suite: 393 passed / 19 failed — same count (extended existing); net-zero NEW failures. Existing assertions (`priced == 142`, treasure_map value_gp -1) still hold — cuts keep their value_gp; defers were already in the catalog.

**Known issues:**
- **The 4 defer items will fail to activate** via `MagicItemActivator.*` (their lookups will say "no spell_binding"). This is the intended V1 behavior — they're carriable / sellable. A polish pass could surface the `defer_reason` in the activation-failure message so the UI can show "Ring of Wishes (not yet implemented in this build)".
- **Random-loot logs may need re-roll telemetry** — if a session generates many cuts, the re-roll loop fires repeatedly. Low priority (max ~13% per category) but worth a counter if balance audits show distortion.

**Next session should:**
1. **(Build) Decanter of Endless Water — wilderness water refill.** Wire into the wilderness loop's water-consumption code: when an inventoried Decanter exists and water containers are below capacity, refill at the decanter's output rate per tick. Mirrors "entering a river hex" but always-on. Need to find the wilderness water-consumption tick + decide cap rate (1d3 gal/round per RAW? — verify in `acks-raw-lookup`).
2. **(Build) Oil of Slipperiness — surface-coat resolver.** Build a reusable resolver: oils that coat self/surface, applies effects per RAW. Cross-applies to future grease spells / other oils.
3. **(Triage) Tier 2 bindings.** ~16 items that bind to existing spells. Cheapest implementation per item; same extractor + activator pattern as the wand/staff pass. Targets: Philter of Love (charm_person), 5 Control potions (charm_monster), 2 Command rings (charm_monster), Dust of Disappearance (invisibility), Dust of Appearance (detect_invisible), Potion of Polymorph (polymorph_self project-default), Wand of Fear + Drums of Panic (cause_fear), 2 Medallions of ESP (esp persistent-worn), Boots of Speed (haste persistent-worn).
4. **(Triage) Tier 3 shared resolvers.** STR override family + Level boost + Detect family + Wards + Persistent-worn stat bonuses (~20 items across 5 mechanisms).
5. **(Triage) Tier 4 customs.** Bag of Holding, Bag of Devouring, Rod of Cancellation, etc. — each its own resolver (~17 items).
