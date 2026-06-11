# Handoff — Wilderness Encounter & Lair-Discovery Cleanup

**Authored:** 2026-05-27 (advisor session, Jedidiah + Opus)
**For:** Claude Code (build agent), Sonnet default
**Status: EXECUTED.** Session 1 (camp encounter) landed 2026-05-27 under the revised §4.3 hybrid camp-gate design (see build_log "Hybrid camp encounter gate"); Session 2 (lair rewrite) landed 2026-06-10 with migration 152 (see build_log "Lair placement & discovery rewrite"). As-built deviations are documented in `generation/gdd-lair-discovery.md` §8/§10 — notably per-hex state lives in the `hex_lair_state` table (the schema has no `hexes` table, and `hex_cells` is clobbered by fog saves). The §7 stronghold question was RESOLVED 2026-06-10 (Jedidiah): un-surveyed land also blocks — the gate is now survey + clear-everything-the-survey-revealed (`HexLairState.is_stronghold_buildable`).
**Scope:** Two independent RAW-corrections to the wilderness encounter system. Both touch v1-implemented behavior that diverged from RAW; both have been redesigned in their respective GDDs.

The two sessions can be run in either order. Session 1 (camp encounter) is the smaller and more contained piece; Session 2 (lair discovery) is a larger rewrite. Recommended order: Session 1 first, then Session 2.

A doc-only change also landed today in `generation/gdd-terrain-system.md` §4.3 — an "Intentional divergence from RAW" note on the Borderlands 50/50 encounter-table blend. No build-agent action required for that; it documents existing implementation behavior.

---

## Session 1 prompt — Camp encounter check correction

```
Implement the corrected camp-encounter check design per `generation/gdd-realtime-scheduler.md` §4.3 (last updated 2026-05-27).

Context: the v1 implementation has `camp_handlers.gd` scheduling 3 `camp_watch` events per night and firing an encounter check at each watch boundary. That is a documentation/encoding error — RAW (`acore-monster-stocking-rules.xml §wilderness_wandering_monsters.encounter_check.frequency` L143-145) specifies one encounter throw per stationary day, not one per watch. The corrected design folds the stationary check into `wilderness_day_tick` (which already fires once per day per party), and watches become state/UX events only.

Per the Build Session Protocol in CLAUDE.md, before writing code:
1. Read CLAUDE.md.
2. Run `acks-build-log --last 1`, `--next-actions 3`, `--needs-review`, and `--for-task "camp encounter check stationary day"` to surface relevant prior sessions.
3. Read `docs/acks_arbiter_design_brief_v11.md`.
4. Read `generation/gdd-realtime-scheduler.md` end-to-end, focusing on §4.3 (the corrected design) and §4.4 (wilderness_day_tick — where the new throw lives).
5. Run `acks-conventions --for-task "wilderness encounter scheduling event handler observer state"` for applicable conventions.
6. Use `acks-raw-lookup` for any RAW citations you add to code or tests. Key sections:
   - `acore-monster-stocking-rules.xml §wilderness_wandering_monsters.encounter_check.frequency` (per-day rule for stationary)
   - `acore_adventures_and_encounters.xml §surprise_and_sneaking.observer_state.{actively_watching, passively_watching, distracted_or_not_looking}` (L874-895)
   - `acore_adventures_and_encounters.xml §surprise` (1d6, 2- = surprised)

Implementation work (in dependency order):

1. **Remove per-watch encounter throws.** In `camp_handlers.gd`, the per-watch encounter check fired at each `camp_watch` boundary goes away. The `camp_watch` events still get scheduled — they remain as state/UX boundaries (memorization windows, prayer windows, Rest activity ticks, the awake-vs-asleep lookup) — but they no longer fire `wilderness_encounter_check`.

2. **Fold the stationary check into `wilderness_day_tick`.** Per §4.4, this event already fires once per game-day per party at midnight rollover. Extend its handler to: (a) detect whether the party was stationary for the past day, and (b) if so, roll one encounter check per RAW's terrain-threshold table (`acore-monster-stocking-rules.xml §encounter_frequency_by_terrain` L169-179 — 6+/5+/4+ on 1d6). On positive, proceed to step 3.

3. **Add a `wilderness_encounter` event type** distinct from `wilderness_encounter_check`. The check is the throw; the encounter is the resolution at a specific fire_time. On a positive stationary throw, roll 1d24 for the hour-of-occurrence within the stationary day's 24-hour window, schedule the `wilderness_encounter` event at that absolute fire_time. Register the handler in `event_handler_registry.gd` per §11.2.

4. **Observer-state classifier.** When `wilderness_encounter` fires, compute each party member's observer state at the encounter's fire_time by reading the watch schedule:
   - On watch at that hour → `actively_watching`
   - Off watch, awake (between watches, daytime hours) → `passively_watching`
   - Off watch, asleep (watch schedule says sleeping) → `distracted_or_not_looking`. Each sleeping character gets a Hear Noises throw at 18+ on 1d20 (per RAW L890) to rouse before surprise resolution. On failure, they begin the encounter functionally surprised.

5. **Surprise resolution.** Run the group surprise check per RAW `acore_adventures_and_encounters.xml §surprise` (1d6 per side, 2- = surprised) using the composite observer-state of the party.

6. **Audit and update tests.** Any test that exercises "3 encounter checks per camped night" must be rewritten. Add focused tests for: stationary-day check fires once (not three times); positive throw schedules a `wilderness_encounter` event at a rolled hour; observer-state classifier returns the correct state for on-watch / off-watch-awake / off-watch-asleep characters; sleeping-character Hear Noises throw correctly determines round-one surprise.

Mixed-day edge case [NEEDS-CLARIFICATION per §4.3.3]: travel-then-camp on the same day. Default per the GDD is **Option A — strict RAW**: per-hex checks at travel_leg arrivals handle the day; the camp gets no additional check. Implement Option A unless Jedidiah revises before this session.

Acceptance criteria:
- `camp_handlers.gd` no longer schedules or fires encounter checks at watch boundaries.
- `wilderness_day_tick` fires the stationary check at most once per stationary day per party.
- A positive stationary throw produces one `wilderness_encounter` event whose fire_time is a uniform 1d24 hour within the day.
- At encounter time, observer-state classification is computed from the watch schedule, with the Hear Noises throw applied to sleeping characters.
- All existing wilderness/camp tests pass; new tests cover the four scenarios above.

End the session with a `build_log.md` entry per the template at `.claude/skills/acks-build-log/references/entry_template.md`. Run `acks-build-log --lint` after appending.
```

---

## Session 2 prompt — Lair placement and discovery rewrite

```
Implement the redesigned lair placement and discovery system per `generation/gdd-lair-discovery.md` (last updated 2026-05-27). This is a substantial rewrite — the v1 implementation had a project-designed parallel discovery system and an eager world-gen placement path that are both being removed in favor of strict-RAW lazy placement.

Context: the v1 design built two project-designed extensions on top of RAW — (a) a per-leg passive 1d20 lair-spot rolled at every travel_leg, and (b) eager world-gen lair placement that pre-populated hexes with lair records. Both were part of a hex-clearing workflow that has been dropped. The new design follows RAW strictly: lairs are placed lazily via the Lair Generator (a forthcoming subsystem this session will stub) when either a wandering encounter substitution fires OR a dedicated search activity succeeds, capped per hex by RAW lairs_per_hex.

Per the Build Session Protocol in CLAUDE.md:
1. Read CLAUDE.md.
2. Run `acks-build-log --last 1`, `--next-actions 3`, `--needs-review`, and `--for-task "lair discovery placement wandering substitution search activity surveying"`.
3. Read `docs/acks_arbiter_design_brief_v11.md`.
4. Read `generation/gdd-lair-discovery.md` end-to-end. This GDD is the authoritative spec.
5. Cross-read `generation/gdd-realtime-scheduler.md` §4.1 (wilderness encounter check on travel_leg), §4.8.1 (minor strenuous activity time-cost model). Cross-read `generation/gdd-terrain-system.md` (hex terrain tags that feed lairs_per_hex).
6. Run `acks-conventions --for-task "lair placement resolver lazy roll budget queue schema migration UI tooltip context menu"`.
7. Use `acks-raw-lookup` for citations. Key RAW sources:
   - `le_wilderness_lair_rules.xml §dynamic_points_of_interest.placement_procedure` (L20-24, the placement trigger)
   - `le_wilderness_lair_rules.xml §securing_land.lair_generation_procedure` and `lairs_per_hex` table (L34-87, the budget table)
   - `le_wilderness_lair_rules.xml §searching_for_lairs` (full section — abstract_search_procedure, lair_search_target_values table, tracking, aerial_reconnaissance, wandering_monsters, splitting_up, land_surveying)
   - `acore-monster-stocking-rules.xml §wilderness_wandering_monsters.procedure` step 3 (% In Lair)
   - The Campaign Play "Searching" and "Surveying" entries (quoted in the GDD §4 and §5 source notes) — these classify both activities as strenuous minor activities (~1 hour).

Implementation work, in dependency order:

**Phase A — Schema and resolvers**

A1. **Database migration.** Add to the `hexes` table:
- `lair_budget INTEGER` (nullable; null = unrolled)
- `lair_budget_rolled_at_round INTEGER` (nullable)
- `lairs_placed_count INTEGER NOT NULL DEFAULT 0`
- `unrevealed_lair_types TEXT` (JSON array of creature_ids; nullable, empty array when populated)
- `surveyed_total INTEGER` (nullable; the player-displayed total — equals `lair_budget` on a true reading, or the false value on an unmodified-1 reading)

Add to the `lairs` table (if not already present):
- `cleared_at_round INTEGER` (nullable)

Drop `lairs.discovered` if it exists — in the new model placement IS discovery, so the column is meaningless. Audit all readers first; rewrite them to assume all placed lairs are discovered.

A2. **`LairBudgetResolver`** (new `engine/subsystems/exploration/lair_budget_resolver.gd`). Wraps the RAW `lairs_per_hex` table. Public API: `roll_budget(hex) -> int` — rolls the appropriate dice for the hex's terrain × civilization, clamps to ≥0, persists `hex.lair_budget` + `hex.lair_budget_rolled_at_round`. `get_or_roll(hex) -> int` — returns cached or rolls.

A3. **`LairTypeResolver`** (new `engine/subsystems/exploration/lair_type_resolver.gd`). Wraps the Wilderness Encounters by Terrain roll plus the `% In Lair > 0` re-roll loop. Public API: `roll_type(hex) -> creature_id` — rolls on the hex's terrain column per `gdd-terrain-system.md §4.2` table-selection logic; if the rolled creature has `% In Lair = 0` or `None`, re-roll until a creature with `% In Lair > 0` is selected. `roll_types_for_remaining_slots(hex, n) -> Array[creature_id]` — convenience for Survey-time eager rolling.

A4. **`LairGenerator` stub** (new `engine/subsystems/exploration/lair_generator.gd`). The full generator is a future subsystem with its own GDD. For this session, stub the interface:
```
LairGenerator.generate(hex: HexData, creature: CreatureTemplate) -> LairRecord
```
The stub returns a LairRecord with: `hex_coordinates`, `occupant_creature_id`, `occupant_count` (rolled per the creature catalog's lair entry — use the existing creature catalog lookup), `treasure_hoard` (placeholder; rolled per Treasure Type — can be a basic implementation), `lair_layout_seed` (rng-derived), `created_at_round`, `cleared_at_round` (null), `discovered` (true). Mark the stub clearly with a TODO pointing to the future Lair Generator GDD.

**Phase B — Placement triggers**

B1. **Wandering substitution branch.** In `wilderness_handlers.gd` (the existing wilderness encounter check handler, currently `_handle_wilderness_encounter_check` or its successor): after a wilderness encounter throw resolves to a creature, perform the % In Lair check per RAW step 3. On success, follow §3.2:
- `LairBudgetResolver.get_or_roll(hex)`.
- If `hex.lairs_placed_count < hex.lair_budget`:
  - `LairGenerator.generate(hex, wandered_creature)`.
  - Persist; `hex.lairs_placed_count += 1`.
  - If `hex.unrevealed_lair_types` non-empty, pop one entry from the front (RAW substitution rule consumes one unrevealed slot).
  - Fire `EventBus.lair_placed(party_id, hex, lair_record, via="wandering_substitution")`.
- If `hex.lairs_placed_count == hex.lair_budget`: the encounter resolves as a "creature group at home" (lair-population numbers) but no new persistent lair record is created.

B2. **Remove the per-leg passive lair-spot.** Delete `_passive_lair_check` from `wilderness_handlers.gd` and any travel_leg call site that invokes it. Delete the corresponding tests.

B3. **Remove eager world-gen lair placement.** Delete any setting-generation code paths that pre-populate the `lairs` table at world-gen time. Audit `gdd-poi-generation.md` and `gdd-setting-generation.md` consumers to confirm nothing depends on pre-placed lairs.

**Phase C — Survey and Search rewrite**

C1. **Rewrite `SurveyingResolver.assess`** per §4.3. On success: lazily roll `lair_budget` if needed; compute `needed = lair_budget - lairs_placed_count - len(unrevealed_lair_types)`; call `LairTypeResolver.roll_types_for_remaining_slots(hex, needed)` and append to `unrevealed_lair_types`; persist; reveal `lair_budget` (or false value on an unmodified-1) to the player via `EventBus.survey_completed`. Keep the false-reading dice (`land_surveying_false`, `land_surveying_false_sign`); the false value affects only the player-facing `surveyed_total` display, NOT the internal `lair_budget` or `unrevealed_lair_types`.

C2. **Rewire the `search_lair` activity** per §5. Change the activity classification to a strenuous minor activity (~1 hour) per the Campaign Play Searching rule; drop the v1 8-hour collapsed block. Each launch fires:
- One search throw per the existing `LairSearchResolver` (1d20 vs movement-rate target, +4 Tracking, optional_specialist_bonus param).
- One wandering encounter check per RAW §wandering_monsters L147-151.

On search-throw success (per §5.3):
- `LairBudgetResolver.get_or_roll(hex)`.
- If budget exhausted: surface a soft "no further lairs" notification; activity ends.
- Otherwise:
  - If `unrevealed_lair_types` non-empty: pop the front entry.
  - Else: lazy-roll one type via `LairTypeResolver.roll_type(hex)`.
  - `LairGenerator.generate(hex, popped_creature)`.
  - Persist; `hex.lairs_placed_count += 1`.
  - Fire `EventBus.lair_placed(party_id, hex, lair_record, via="search")`.
- Activity halts on success.

On wandering encounter trigger (during search): halt the search and route to combat via the existing `enter_combat` return contract. If the wandering encounter rolls an in-lair monster, the §3.2 substitution path fires normally.

C3. **`LairSearchResolver` adjustments.** The resolver itself can largely stay — keep the target-value table, Tracking +4, aerial reconnaissance doubling, and `optional_specialist_bonus` parameter. The change is in how its results are consumed (now triggers placement) and how the activity is timed (now 1 hour, not 8).

**Phase D — UI surface**

D1. **Hex tooltip + Session Status Bar "Lairs: X/Y"** per §6.1. In `hex_map_renderer.gd` (tooltip) and the Session Status Bar info box renderer, add a `Lairs: {cleared} / {displayed_total}` line with the visibility rules:
- Hidden before any placement.
- After a wandering-substitution placement but before Survey: denominator = `lairs_placed_count`.
- After a successful Survey: denominator = `surveyed_total` (which is the true budget on a normal success, or the false value on an unmodified-1).
- Numerator: count of placed lairs with `cleared_at_round IS NOT NULL`.

D2. **"Enter {Monster Type} Lair" button** per §6.2. Surface in `wilderness_context_menu_builder.gd` and the per-hex action panel. For each placed lair in the hex, add a button labeled `Enter {Type} Lair`. When multiple lairs of the same type exist in the hex, append a stable 1..N ordinal in creation order (`Enter Goblin Lair 1`, `Enter Goblin Lair 2`). Stable numbering: when one of N same-type lairs is cleared, the remaining buttons retain their original numbers. Cleared lairs get a `Re-enter {Type} Lair (cleared)` variant styled distinctly. The button enters the lair as a dungeon per the existing dungeon-entry flow in `gdd-dungeon-map-ui.md`.

D3. **Build Stronghold gating** per §7. Add `HexLairState.has_uncleared_placed_lair(hex_q, hex_r) -> bool`. In `wilderness_context_menu_builder.gd` and any other UI surface that exposes "Build Stronghold," conditionally append the entry only when `has_uncleared_placed_lair` returns false. When gated, the entry is hidden entirely (not greyed) — the player learns the gate by clearing lairs and seeing the option appear.

**Phase E — Signals and persistence**

E1. **Signal rename.** `EventBus.lair_discovered` → `EventBus.lair_placed`. Add `via` discriminator to the payload (`"wandering_substitution" | "search"`). Update all listeners (NotificationManager, hex renderer, Status Bar, context-menu builder, Notebook).

E2. **New `EventBus.lair_cleared`** signal. Fired when combat resolution + party-action handler set `cleared_at_round` on a lair. Listeners: NotificationManager toast, hex map renderer, Status Bar, context-menu builder (re-build — may now expose Build Stronghold), Notebook history panel.

E3. **`EventBus.survey_completed`** payload update. Add `displayed_total` (the value shown to the player) and `was_false_reading: bool` (used by debug overlays; not surfaced to player).

E4. **Repository changes.** In `campaign_repository.gd`: remove `count_undiscovered_lairs` and `reveal_one_lair` (no longer meaningful). Add `count_cleared_lairs_in_hex`. Keep `create_lair`, `count_lairs_in_hex`, `list_lairs_in_hex`. Add `cleared_at_round` write path.

**Phase F — Test audit**

F1. Audit and rewrite/delete any test that:
- Asserts a lair existing before a wandering encounter surfaces it.
- Exercises the v1 passive lair-spot path.
- Asserts the v1 8-hour search collapsed block.
- Asserts Land Surveying reading from `lairs_placed_count`.

F2. Add focused tests covering:
- Wandering substitution places via Lair Generator and decrements/pops the unrevealed queue.
- Wandering substitution at budget cap places no new lair.
- Survey success rolls budget if needed, rolls remaining types eagerly with `% In Lair > 0` re-roll, hides types, reveals budget.
- Survey unmodified-1 false reading affects display but not internal state.
- Search success pops from queue (post-Survey) or lazy-rolls (Search-first).
- Search at budget cap surfaces "no further lairs" and halts.
- "Lairs: X/Y" display follows the §6.1 visibility rules across (pre-placement, post-substitution-pre-Survey, post-Survey).
- "Enter {Type} Lair" button surfaces with stable 1..N ordinals for same-type duplicates.
- Build Stronghold is hidden when any placed lair is uncleared; appears when all cleared.

Acceptance criteria:
- The passive 1d20-per-leg path and any eager world-gen lair placement code paths are deleted.
- A fresh hex has null `lair_budget` until a wandering encounter / Survey / Search triggers the roll.
- A successful Survey reveals the budget (or false value) and eagerly fills the unrevealed types queue without revealing types.
- A successful Search reveals the next lair from the queue (or lazy-rolls one), placed via the Lair Generator stub.
- Cleared lairs hold their slot permanently in v1 (no decrement of `lairs_placed_count`).
- Build Stronghold is correctly gated by uncleared placed lairs.
- The Lair Generator interface contract is honored by the stub; the full generator is a future session.
- All existing wilderness/lair tests pass; new tests cover the bullet list in F2.

Open question to surface in the build_log entry: §7's "Stronghold gating against unrevealed lairs" — should an un-Surveyed hex with `lairs_placed_count < lair_budget` block Build Stronghold? Default in this implementation is no (only placed-and-uncleared gate). Flag for Jedidiah's play-test review.

End the session with a `build_log.md` entry per the template; run `acks-build-log --lint`.
```

---

## Notes common to both sessions

**Model guidance per CLAUDE.md:** Sonnet is the default for implementation. If during Session 2 you hit cross-subsystem integration questions or RAW interpretation gaps not covered by the GDD, flag with `[NEEDS-OPUS-REVIEW]` in the build_log rather than guessing.

**Schema migrations:** these sessions add schema. Use sequential migration numbers per project convention; do not destructively rewrite existing migrations. Both sessions can land in the same migration file or separate ones — Session 1 (camp encounter) may not need a migration if observer-state is computed from the existing watch schedule data; Session 2 (lair) definitely needs one.

**No Lair Generator GDD yet.** The Session 2 work stubs the Lair Generator interface. The full subsystem will get its own GDD and its own implementation session. Don't try to flesh out lair-layout generation, treasure hoard composition, or narrative seed data beyond the stub.

**RAW citations in code.** Per project convention, any new code that implements a RAW rule should carry a comment citing the XML path (e.g., `# Per acore-monster-stocking-rules.xml §wilderness_wandering_monsters.encounter_check.frequency L143-145`). Use `acks-raw-lookup` to get the exact citation.

**Conventions updates.** If either session establishes a new pattern that future sessions will face — a new resolver shape, a new event-type registration pattern, a new lazy-roll-on-need idiom — update `docs/coding_conventions.md` per the maintenance section in CLAUDE.md.

**Doc-only change today (no action required):** `generation/gdd-terrain-system.md` §4.3 gained an "Intentional divergence from RAW" note documenting the Borderlands 50/50 encounter-table blend as deliberate project design. No code change is needed; the existing implementation already does the 50/50 split.
