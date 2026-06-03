# GDD: Lair Placement and Discovery

**Authority:** SACRED for the placement trigger (RAW `le_wilderness_lair_rules.xml §dynamic_points_of_interest.placement_procedure`), the per-hex budget cap (RAW §securing_land.lair_generation_procedure / lairs_per_hex), the dedicated search activity (RAW §searching_for_lairs.abstract_search_procedure), and the Land Surveying activity (RAW §searching_for_lairs.land_surveying, plus the Campaign Play Surveying entry). One documented divergence from strict RAW: monster-type commitment for a lair happens at discovery time (lazy) rather than at hex creation (eager) — see §5.3.
**Status:** Redesign in progress (2026-05-27). Supersedes the Phase 4 v1 implementation, which built two project-designed extensions (per-leg passive lair-spot; eager world-gen placement) that are being removed. See §10 for the migration note and the build-agent punch list.
**Depends on ACKS rules:** `le_wilderness_lair_rules.xml` (full file), `acore-monster-stocking-rules.xml §wilderness_wandering_monsters.procedure` (step 3, % In Lair), `acore_proficiencies_rules_and_catalog.xml` (Tracking, Land Surveying entries).
**Depends on project GDDs:** `gdd-realtime-scheduler.md` §4.1 (wilderness encounter check on travel_leg), `gdd-terrain-system.md` (hex terrain tags driving lair_per_hex lookup).
**Pending external dependencies:** Lair Generator GDD (forthcoming — defines the placement service this GDD calls into). The L&E eager pre-rolling workflow for hexes PCs intend to clear for a domain (L&E p.13 "How many monsters?") is deferred; this GDD covers the lazy/dynamic-POI mode only.
**Source material integrated:** L&E pp.12–14 (PDF excerpt provided 2026-05-27) and the Campaign Play "Searching" and "Surveying" entries, which together define the dedicated search activity and Land Surveying mechanics now reflected in §4 and §5.
**Note on POI discovery:** Static (pre-placed) point-of-interest discovery has moved to `gdd-poi-generation.md`. This GDD covers lairs only — they are RAW's "dynamic points of interest," handled by a different lifecycle than static POIs.

---

## 1. Purpose

Place monster lairs into wilderness hexes lazily — only when a RAW-sanctioned discovery event surfaces them — and persist them until the party clears them. Two such events exist in the Arbiter system, both straight from RAW:

1. **Wandering encounter substitution** (§3.2) — a wilderness encounter throw rolls a creature, the creature's % In Lair check succeeds, the Lair Generator places a lair.
2. **Dedicated search activity success** (§5) — a 1d20 search throw vs movement-rate target succeeds, the Lair Generator places a lair drawn from the same per-hex budget.

There is no eager world-gen placement and no project-designed passive per-leg spotting. This is a strict-RAW interpretation of `le_wilderness_lair_rules.xml §dynamic_points_of_interest`: lairs are "dynamic points of interest whose location is not fixed until first encountered in lair" (per the definition at L14).

---

## 2. ACKS Rules Constraints (Sacred)

### 2.1 Lazy placement on wandering encounter

> "When a wilderness encounter throw results in an encounter with a monster in its lair, place that monster's dynamic point of interest in the hex where the encounter occurred."
> "Once placed, the point of interest becomes static and remains fixed in that hex for the rest of the campaign."
> — `le_wilderness_lair_rules.xml §dynamic_points_of_interest.placement_procedure` L20–24

This is the **single placement trigger** in the Arbiter system. Lairs do not exist before this moment.

### 2.2 Wandering check resolves in-lair status

> "Find the creature in the monster chapter and roll against its % In Lair to determine whether it is in its lair."
> — `acore-monster-stocking-rules.xml §wilderness_wandering_monsters.procedure` step 3, L154

The "is this encounter in a lair?" determination is the wandering procedure's step 3, using each creature's published % In Lair. The Arbiter encounter pipeline must perform this check and route to the Lair Generator (§3.3) on success.

### 2.3 Per-hex lair budget (lairs_per_hex)

> "Cross-reference terrain type and hex classification on the lairs_per_hex table and roll to determine the number of lairs present."
> — `le_wilderness_lair_rules.xml §securing_land.lair_generation_procedure` L82

The RAW lairs_per_hex table (L34–78) gives the lair count distribution by terrain and civilization tier. The Arbiter uses this as a **per-hex budget cap** (§3.1) so emergent lair density across the regional map tracks RAW's distribution.

| Terrain | Wilderness | Borderlands | Civilized |
|---|---|---|---|
| Clear, grass | 1d2 | — | — |
| Scrub, hills | 1d4 | 1d3-2 | — |
| Barren, desert | 1d6 | 1d2-1 | — |
| Mountains, woods | 2d4 | 1d4-2 | 1d6-5 |
| Swamp | 2d4+1 | 1d3-1 | 1d4-3 |
| Jungle | 2d8 | 1d2 | 1d3-2 |

Results less than 0 are treated as 0. "—" means no random lairs.

### 2.4 Substitution and the budget cap

> "If the party accidentally wanders into a lair, substitute the newly encountered lair for one of the previously generated lairs, or substitute one of the previously generated lairs for the newly encountered lair."
> — `le_wilderness_lair_rules.xml §searching_for_lairs.wandering_monsters` L150

In RAW's eager model, substitution swaps the wandered-into lair for one pre-rolled in the hex. In the Arbiter's lazy model there are no "previously generated" lairs, so substitution collapses to: **when a wandering encounter rolls a monster in its lair, that lair is placed via the Lair Generator, and the hex's remaining budget decrements.** If the budget is already exhausted, the encounter still resolves as a "creature group at home" (lair-population numbers) but no new persistent lair record is created — the budget cap holds.

### 2.5 Land Surveying assessment (RAW-faithful)

RAW Land Surveying assesses "the total number of lairs in a hex" (§land_surveying.assessment_rules L161, Campaign Play Surveying entry, L&E p.14), including unrevealed lairs. The Arbiter system implements this faithfully: a successful Land Surveying throw reveals the hex's full rolled lair budget. See §4 for full mechanics.

### 2.6 Dedicated search activity (RAW-sourced)

The dedicated search activity per RAW `le_wilderness_lair_rules.xml §searching_for_lairs.abstract_search_procedure` (with the Campaign Play "Searching" entry classifying it as a strenuous minor activity) is integrated as the second placement trigger in the Arbiter lazy model. See §5 for the full mechanics.

### 2.7 Eager pre-rolling workflow (deferred)

The L&E book also defines an **eager pre-rolling** procedure ("How many monsters?", L&E p.13) for when PCs intend to clear and secure a hex for a domain. In that workflow the Judge pre-rolls the full lairs_per_hex count AND the monster types AND the specific lair listings up front, then the search activity discovers those pre-rolled lairs in sequence. This eager workflow is **deferred**. For ordinary wilderness exploration — including the search activity as the party uses it — the Arbiter uses the lazy model in §3.

---

## 3. Arbiter Lair Placement Flow

### 3.1 Per-hex lair state (lazy, cached)

Each hex carries three pieces of lair state, all lazy-rolled on first need:

- `lair_budget: int` — the total number of lairs in the hex per `le_wilderness_lair_rules.xml §lair_generation_procedure`.
- `lairs_placed_count: int` — how many of those have been placed and revealed so far (matches the "cleared/in hex" denominator surfaced to the player in §6).
- `unrevealed_lair_types: array[creature_id]` — the FIFO queue of remaining lair monster types waiting to be discovered. Hidden from the player.

**Budget roll** (on first need from Survey, Search, or wandering substitution):

1. Look up the hex's terrain (per `gdd-terrain-system.md`) and civilization tier.
2. Roll the indicated dice from the lairs_per_hex table (e.g., `2d4` for wilderness mountains/woods).
3. Clamp to ≥0. Persist `hex.lair_budget` along with `hex.lair_budget_rolled_at_round`.

Once rolled, the budget is fixed for the campaign's lifetime.

**Type roll** (on first need from Survey or Search):

1. Compute `needed = lair_budget - lairs_placed_count - len(unrevealed_lair_types)`.
2. For each of `needed` slots: roll on the appropriate column of the Wilderness Encounters by Terrain table (per the hex's terrain) to determine the lair's monster type. If the rolled creature has `% In Lair = None` or `0`, re-roll the type. Repeat until a creature with `% In Lair > 0` is rolled.
3. Append the resulting creature IDs to `unrevealed_lair_types`.

Survey success rolls all `needed` slots at once (eager). Search-without-prior-Survey rolls one slot per success (lazy, on the fly). Both paths use the same re-roll rule for `% In Lair = 0/None`.

The roll is **deferred to first need** — there's no world-gen pass that walks every hex and rolls. A hex the party never visits never rolls. This keeps the world-gen pipeline lighter and ensures every campaign feels distinct in lair density.

### 3.2 Wandering substitution as a placement trigger

When a wilderness encounter check fires positive (per `gdd-realtime-scheduler.md §4.1`) and resolves to a creature with a published % In Lair, the encounter pipeline:

1. Rolls % In Lair per `acore-monster-stocking-rules.xml §wilderness_wandering_monsters.procedure` step 3.
2. **On success ("in its lair"):**
   - Lazily roll the hex's lair budget if not already rolled (§3.1).
   - If `hex.lairs_placed_count < hex.lair_budget`:
     - Call `LairGenerator.generate(hex, creature)` to construct the lair record (§3.3) using the **wandered creature's type** (not from `unrevealed_lair_types`).
     - Persist the lair record, increment `hex.lairs_placed_count`.
     - If `unrevealed_lair_types` is non-empty, **pop one entry from the front** — this is RAW's substitution rule (`le_wilderness_lair_rules.xml §searching_for_lairs.wandering_monsters` L150: "substitute the newly-encountered lair for one of the previously generated lairs"). The popped type's slot is consumed by the wandered creature; the displayed total is unchanged.
     - The encounter resolves as the lair occupants (lair-population numbers per RAW step 6).
     - Fire `EventBus.lair_placed` with `via = "wandering_substitution"` (§9). Because the type is revealed by the encounter itself, the UI surfaces the lair as discovered (§6).
   - If `hex.lairs_placed_count == hex.lair_budget`:
     - The encounter still resolves as a "creature group at home" (lair-population numbers) but no new persistent lair record is created.
     - The hex's lair slots are full; further in-lair encounters there will resolve as transient "another nesting group" fights without creating new placed records.
3. **On failure ("not in its lair"):** the encounter resolves normally per the wandering procedure (no lair interaction).

### 3.3 Lair Generator interface (forthcoming subsystem)

The Lair Generator is its own GDD (to be drafted) and its own subsystem. For this GDD's purposes, the interface contract the encounter pipeline calls into is:

```gdscript
LairGenerator.generate(hex: HexData, creature: CreatureTemplate) -> LairRecord
```

The returned `LairRecord` includes at minimum:

- `hex_coordinates`: `(q, r)` of the placement hex
- `occupant_creature_id`: the creature type that triggered placement
- `occupant_count`: lair-population number per RAW
- `treasure_hoard`: rolled per the creature's Treasure Type
- `lair_layout_seed`: seed for the tactical map when the party engages
- `created_at_round`: timestamp for journaling
- `cleared_at_round`: null until cleared (§3.4)
- `discovered`: true on creation (placement IS discovery in the lazy model)

The encounter pipeline calls the generator and receives the record; the spawned encounter uses the `LairRecord`'s occupant data instead of re-rolling wandering numbers.

The Lair Generator subsystem owns the internals of lair-layout generation, hoard composition, and any narrative seed data. This GDD specifies only the call contract.

### 3.4 Persistence and clearing

A placed lair persists indefinitely. The hex retains the lair record until the party clears it.

"Cleared" means: the lair's occupants are reduced to 0 in combat AND the party loots or abandons the lair. On clear:

- Set `lair.cleared_at_round = current_round`.
- The record is retained for journaling and for the Notebook tooltip showing "lairs discovered here."
- Fire `EventBus.lair_cleared` (§9).

**V1 rule: cleared lairs hold their slot permanently.** A cleared lair still counts against `hex.lairs_placed_count`; the budget total does not decrement, and no new lair will emerge to replace the cleared one. Once a hex's `lair_budget` is reached and all placed lairs are cleared, the hex stays cleared for the campaign's lifetime. This keeps the "you cleared this hex" feeling intact and is naturally compatible with the Build Stronghold gating in §7.

Re-occupation of cleared lairs over time — and the broader "refill" rules so the map doesn't become dead and razed domains become true wilderness — exist in RAW but are deferred. V1 functions fully without them.

---

## 4. Land Surveying assessment

The Land Surveying proficiency is a context-menu activity that lets a character with the proficiency assess the **total number of lairs in a hex** and, as a side effect of success, eagerly commit the unrevealed lair types for that hex (without revealing them to the player).

### 4.1 Activity classification

Land Surveying is a **strenuous minor activity** per the Campaign Play Surveying entry (~1 hour, one minor-activity slot). A character searching the same hex (via §5) can survey it as a **trivial activity** instead — the survey piggybacks on the search and consumes no additional time.

### 4.2 Throw mechanics

Per `le_wilderness_lair_rules.xml §land_surveying.procedure` and the Campaign Play Surveying entry:

- **Roll:** 1d20 (rolled secretly on the surveyor's behalf).
- **Base target:** 18+.
- **Cumulative +4 bonus** for each successful **search** (§5) the party has conducted in this hex up to this point. Successful surveys do not stack — only search successes do.
- **Attempt frequency:** one attempt on first arriving in the hex; one additional attempt each time the hex is searched.
- **Unmodified 1 → false reading:** the surveyor incorrectly assesses the count, and the system reveals a deliberately-incorrect value (see §4.4).
- **Other failure (≥2, but below target):** no information; the surveyor cannot make or revise an assessment.
- **Success:** the system performs the Survey sequence (§4.3).

### 4.3 Survey success sequence

A successful Land Surveying throw runs the following sequence (in order):

1. **Roll the budget if not already rolled** (§3.1). Previously-placed lairs (e.g., from wandering substitution before the Survey) already counted against `lair_budget`; no double-counting.
2. **Roll the remaining lair types eagerly.** Compute `needed = lair_budget - lairs_placed_count - len(unrevealed_lair_types)`. For each slot, roll on the appropriate Wilderness Encounters by Terrain column. If the result is a creature with `% In Lair = None` or `0`, re-roll the type until a creature with `% In Lair > 0` is selected. Append each resulting creature_id to `unrevealed_lair_types`.
3. **Hide the types from the player.** The types are persisted in `unrevealed_lair_types` but **never shown via Land Surveying**. Survey reveals only the count, not the contents.
4. **Reveal `lair_budget` to the player** — the total count appears in the hex tooltip and Status Bar as the denominator of "Lairs: X/Y" (§6).
5. Fire `EventBus.survey_completed` with the revealed total (§9).

After Survey: subsequent Search successes (§5) will pop already-rolled types from `unrevealed_lair_types`. Wandering substitution (§3.2) will pop entries from the same queue as the substitution rule fires.

### 4.4 False reading on unmodified 1

On an unmodified 1, the system rolls a deliberately-incorrect value to **reveal to the player as the count**. The existing v1 implementation rolls `actual ± 1d4` clamped to ≥0, with two scripted dice (`land_surveying_false`, `land_surveying_false_sign`) so tests can pin the outcome. Keep this approach.

**Important:** the false reading affects only the displayed count. The internal `lair_budget` is the truth; `unrevealed_lair_types` still gets rolled per §4.3 step 2 against the real budget (not the false number). The player simply sees a wrong "Lairs: X/Y" denominator. They learn it was false only when subsequent surveys or exploration reveal the actual count.

### 4.5 Implementation

- Keep `SurveyingResolver.assess`. On success, call into the budget resolver (§3.1) and the type-roll resolver (§3.1) inline; persist `unrevealed_lair_types`.
- Keep the false-reading dice (`land_surveying_false`, `land_surveying_false_sign`). Use the false value only for the player-facing toast/tooltip; do not corrupt the underlying state.
- The "search same hex as trivial activity" coupling is implemented in `activity_time_cost_executor.gd` as a 0-round trivial when launched concurrent with or immediately after a `search_lair` activity in the same hex.
- The type roll calls into the same wilderness encounter table machinery used by §3.2 wandering substitution; the `% In Lair > 0` re-roll loop is a wrapper around that.

---

## 5. Dedicated search activity

**Source:** `le_wilderness_lair_rules.xml §searching_for_lairs` (mirrored in the L&E book pp.13–14) and the Campaign Play "Searching" entry. Integrated 2026-05-27 from the L&E PDF excerpt.

### 5.1 Activity classification

Searching one 6-mile hex is a **strenuous minor activity** per the Campaign Play Searching rule. In the Arbiter time-cost model (`gdd-realtime-scheduler.md §4.8.1`), a minor activity = ~1 hour of game time and counts as one of the day's minor-activity slots. A character searching a hex can survey the same hex as a **trivial activity** (Land Surveying — see §4).

### 5.2 Search throw mechanics

Each hour the party spends searching, the system makes one secret search throw:

- **Roll:** 1d20.
- **Target value:** looked up from the party's daily wilderness movement rate in this hex, per `le_wilderness_lair_rules.xml §searching_for_lairs.tables.lair_search_target_values` L111–134. Range: 18+ at ≤11 mi/day → 2+ at ≥192 mi/day. Faster parties cover more ground per hour and find lairs more easily.
- **Tracking bonus:** +4 if any party member has the Tracking proficiency (§searching_for_lairs.tracking L137–140).
- **Aerial reconnaissance:** if the party is air-mobile, daily movement is doubled (per ACKS p.94 and §aerial_reconnaissance L142–145), so the target value shifts down the table. In clear / grass / scrub / hills / barren / desert / mountain terrain, the cadence becomes one throw per 30 minutes (3 turns) instead of one per hour.
- **Specialist bonus:** the `optional_specialist_bonus` parameter on `LairSearchResolver.search_hour` carries Pathfinder bonuses when the Phase 6 specialist subsystem lands.

### 5.3 Successful search → reveal a lair

On a successful adjusted throw:

1. Lazily roll the hex's lair budget if not already rolled (§3.1).
2. If `hex.lairs_placed_count == hex.lair_budget`:
   - The throw succeeds but no lair is placed — the hex has been thoroughly searched.
   - Surface a soft notification ("you find no further lairs in this hex").
   - The activity ends; subsequent search activities in the hex can still throw positive but cannot place. Diminishing returns is the intended feel.
3. Otherwise (budget has remaining room), determine the creature type:
   - **If `unrevealed_lair_types` is non-empty** (typically because Survey rolled it eagerly per §4.3, or because Search has rolled it lazily in prior attempts): **pop the front entry** as the creature type.
   - **If `unrevealed_lair_types` is empty** (Search-first, no prior Survey): roll one type on the appropriate Wilderness Encounters by Terrain column, applying the `% In Lair > 0` re-roll rule per §3.1. Use that creature type.
4. Call `LairGenerator.generate(hex, creature)` (§3.3) with the determined type.
5. Persist the lair record; increment `hex.lairs_placed_count`.
6. Reveal the type to the player: the UI surfaces an `Enter {Type} Lair` button on the hex (§6), and the hex tooltip / Status Bar updates the "Lairs: X/Y" display.
7. Fire `EventBus.lair_placed` with `via = "search"`.
8. The search activity halts on success.

**Note on the lazy / eager interplay.** If the player Surveys before Searching, all lair types are pre-rolled at Survey time (§4.3) and Search just pops them in FIFO order — the most RAW-faithful flow. If the player Searches without Surveying first, types are rolled one at a time on each search success. Both produce the same probability distribution; the only difference is when monster-type commitment happens.

### 5.4 Wandering encounters during search

Per `le_wilderness_lair_rules.xml §searching_for_lairs.wandering_monsters` L147–151 ("Adventurers searching a hex are subject to one wandering encounter throw per hour while searching"), the search hour fires an additional `wilderness_encounter_check` (per `gdd-realtime-scheduler.md §4.1`) over and above the search throw itself.

- If the wandering encounter triggers, the search halts and combat enters via the existing `enter_combat` return contract.
- If the wandering encounter rolls a monster in its lair (per §3.2), the substitution path applies — the lair is placed via the Lair Generator, the hex's budget decrements once. The party may then engage or evade.

The wandering check is independent of the search throw: a search hour can produce both a lair-find (search-throw success) AND a wandering encounter (encounter-check trigger). When both occur in the same hour, resolve the wandering encounter first (it interrupts the activity) and surface the lair-find as the activity's deferred result on resume — or, if combat is fatal/long, the lair-find is held over for when the party returns.

### 5.5 Sub-party splitting (deferred)

Per `le_wilderness_lair_rules.xml §searching_for_lairs.splitting_up` L153–157, a party may split into sub-parties for parallel searching. Each sub-party makes its own search throw per hour and is subject to its own wandering encounter checks independently. Sub-party splitting is **deferred** — the current system treats a party as a single search unit.

### 5.6 Implementation notes

- The existing `LairSearchResolver` from the v1 implementation is largely valid — keep the target-value table, Tracking +4, `optional_specialist_bonus` parameter, and aerial flag.
- The activity wiring in `wilderness_handlers.gd::_resolve_lair_search_activity` needs its success path rewritten: from "reveal a pre-existing lair" to "call LairGenerator and place a new lair drawing from the hex budget."
- The activity duration is now **~1 hour (one minor strenuous activity)** per the Campaign Play classification — the v1's 8-hour collapsed block is dropped. Each search activity launch = one hour = one search throw + one wandering check. A party that wants multiple throws launches the activity multiple times (the time-cost model in `gdd-realtime-scheduler.md §4.8` handles serial launches naturally).
- The Land Surveying "search same hex as a trivial activity" rule (Campaign Play Surveying entry) wires through `activity_time_cost_executor.gd` as a 0-round trivial activity when launched concurrently with or immediately after a `search_lair` activity in the same hex.

---

## 6. UI surface

### 6.1 Hex hover tooltip and Session Status Bar

When the cursor hovers over a hex (or the hex is the party's current location and is displayed in the Session Status Bar's hex info box), the UI surfaces a "Lairs:" line:

- **Format:** `Lairs: {cleared} / {in_hex}`
- **`cleared`** = number of placed lairs in the hex whose `cleared_at_round` is set.
- **`in_hex`** = total: either `hex.lair_budget` if it has been revealed by a successful Survey, OR `hex.lairs_placed_count` if not yet Surveyed (i.e., the player sees only what they've encountered).
- **Visibility rules:**
  - Before any Survey or lair placement: the line is **hidden** (the player doesn't know there are lairs).
  - After a wandering-substitution placement but before Survey: `Lairs: 0/1` (the placed lair acts as both the denominator and a discovery — see §6.2).
  - After a successful Survey: the denominator switches to the surveyed total. Subsequent placements increment the numerator (when cleared) but the denominator stays.
  - If the Survey produced a false reading on an unmodified 1, the denominator is the false value; this remains until a subsequent Survey corrects it.

### 6.2 "Enter {Monster Type} Lair" button

When a lair is placed and discovered (via Search success or wandering substitution), the hex's context menu and per-hex action UI gain an `Enter {Monster Type} Lair` button. Treats the lair as a dungeon entry per the Arbiter's dungeon-entry flow (see `gdd-dungeon-map-ui.md`).

**Naming rules:**

- Single lair of a type: `Enter Goblin Lair`
- Multiple lairs of the same type in the same hex: append `1`-based ordinal: `Enter Goblin Lair 1`, `Enter Goblin Lair 2`, ... in creation order
- When one of N same-type lairs is cleared, the remaining buttons retain their original numbers (so `Enter Goblin Lair 2` is still labeled `2` even if `1` is gone) — this avoids button-label thrash that would confuse players returning to the hex

After a lair is cleared, its `Enter` button is replaced by a `Re-enter {Type} Lair (cleared)` affordance (so the player can re-visit the now-empty hideout for navigation, loot inspection, etc.), styled visually distinct from active lairs.

### 6.3 Status updates on clear

When a lair is cleared (per §3.4), the hex tooltip and Status Bar update immediately: the numerator increments. Listeners on `EventBus.lair_cleared` refresh both surfaces.

---

## 7. Stronghold construction gating

Per `le_wilderness_lair_rules.xml §securing_land.hex_definition` L31 ("Before peasants can settle a hex, the hex must be cleared of monster lairs present within it"), stronghold construction is gated on the lair-clear state of the target hex:

- **Rule:** if any lair in the hex has `cleared_at_round == null` (i.e., uncleared), the `Build Stronghold` menu option is **hidden** from the hex's context menu and from any UI surface that would otherwise expose it.
- The hidden option does not appear with a "blocked" tooltip — it is removed entirely, per the user's instruction. The player learns the gating only by clearing lairs and seeing the option appear.
- Once all placed lairs in the hex are cleared, the `Build Stronghold` option becomes available.
- **Open question:** what about unrevealed lairs (`unrevealed_lair_types` non-empty, or `lairs_placed_count < lair_budget` but no Survey has happened)? Strict RAW reading: undiscovered lairs may disrupt settlement (per §judge_guidance L177–179 — "the Judge decides whether an undiscovered lair prevents the hex from being considered secured"). For the Arbiter, **default behavior: only placed/discovered uncleared lairs gate the option.** An unrevealed lair-budget slot does not block stronghold construction. The player can build a stronghold that later "discovers" an angry monster as the lair populates — surfaced narratively or as a stronghold disruption event. This decision is flagged for review in §11.

Implementation: a single helper `HexLairState.has_uncleared_placed_lair(hex_q, hex_r) -> bool` consulted by the context-menu builder. The "Build Stronghold" entry is conditionally appended only when this returns false.

---

## 8. Implementation Map

This map reflects the corrected design. Items marked **CHANGE** require build-agent work to align the implementation with this GDD.

| Concern | File | Action |
|---|---|---|
| Per-hex lair budget roll + cache | (new) `engine/subsystems/exploration/lair_budget_resolver.gd` | **CREATE** — wraps lairs_per_hex table |
| Per-hex unrevealed lair-type queue | (new) `engine/subsystems/exploration/lair_type_resolver.gd` | **CREATE** — wraps the Wilderness Encounters by Terrain roll plus the `% In Lair > 0` re-roll loop |
| Wandering substitution → Lair Generator call | `wilderness_handlers.gd` `_handle_wilderness_encounter_check` (or successor) | **CHANGE** — add in-lair branch that rolls budget if needed, calls LairGenerator with wandered creature, pops one entry from `unrevealed_lair_types` per §3.2 |
| Lair Generator service | (new) `engine/subsystems/exploration/lair_generator.gd` | **CREATE** per the forthcoming Lair Generator GDD |
| Passive 1d20-per-leg lair check | `wilderness_handlers.gd` `_passive_lair_check` | **REMOVE** — no longer part of the model |
| Dedicated search activity wiring | `wilderness_handlers.gd` `_resolve_lair_search_activity`, `wilderness_context_menu_builder.gd` | **REWIRE** per §5 — success pops from `unrevealed_lair_types` (or lazy-rolls one type if empty), calls LairGenerator with that creature; duration drops from 8-hour block to 1-hour minor activity |
| Land Surveying assess | `surveying_resolver.gd` | **CHANGE** — on success, lazily roll `lair_budget` if needed, then eagerly roll all remaining lair types into `unrevealed_lair_types` per §4.3, then reveal `lair_budget` to player. Keep false-reading dice but use false value only for display, not state. |
| Hex tooltip + Status Bar "Lairs: X/Y" | `hex_map_renderer.gd` (tooltip), `session_status_bar.gd` (info box) | **CHANGE** — display `cleared / displayed_total` per §6.1 visibility rules. The `displayed_total` is `hex.lair_budget` if Surveyed (with false-value override on a 1) else `lairs_placed_count`. |
| "Enter {Type} Lair" button | `wilderness_context_menu_builder.gd`, `hex_action_panel.gd` | **NEW** — surface a button per placed lair record. Append `1..N` ordinal when multiple of same type exist in the hex. Stable numbering per §6.2. |
| "Build Stronghold" gating | `wilderness_context_menu_builder.gd` (and any other surface that exposes Build Stronghold) | **NEW** — call `HexLairState.has_uncleared_placed_lair(hex_q, hex_r)`; if true, omit the entry entirely (hidden, not greyed) per §7. |
| Lair persistence | `campaign_repository.gd` — `create_lair`, `count_lairs_in_hex`, `list_lairs_in_hex` (no discovered filter — all placed lairs are discovered), `count_cleared_lairs_in_hex` | Keep most; add `cleared_at_round` writes per §3.4; remove `count_undiscovered_lairs` and `reveal_one_lair` (no longer meaningful — placement IS discovery). |
| Hex lair state persistence | `hexes` table — new columns `lair_budget`, `lair_budget_rolled_at_round`, `lairs_placed_count`, `unrevealed_lair_types` (JSON array of creature_ids), `surveyed_total` (the displayed total — equals `lair_budget` on a true reading or a false value on an unmodified-1) | **MIGRATE** — schema change |
| DB schema | `db/migrations/050_poi_discovery.sql` (review), new migration for the hex columns above | **MIGRATE** |

---

## 9. Signals

| Signal | Emitted from | Payload | Listeners |
|---|---|---|---|
| `lair_placed(party_id, hex, lair_record, via)` | wandering substitution → Lair Generator, OR successful Search → Lair Generator | `via ∈ {"wandering_substitution", "search"}`; `lair_record` per §3.3 | NotificationManager toast, hex map renderer (re-tooltip), Status Bar (re-render), context-menu builder (re-build to surface Enter Lair button), Notebook history panel |
| `lair_cleared(party_id, hex, lair_record)` | combat resolution + party-action handler | `lair_record.cleared_at_round` set | NotificationManager toast, hex map renderer, Status Bar, context-menu builder (re-build — may now expose Build Stronghold), Notebook history panel |
| `survey_completed(party_id, hex, result)` | Land Surveying activity | `result.success`, `result.displayed_total` (true budget or false value), `result.was_false_reading: bool` (used by debug overlays; not surfaced to player) | NotificationManager toast, hex map renderer, Status Bar |
| `lair_discovered(party_id, result)` | **REMOVED** (was: passive check or dedicated search) | — | — |
| `poi_discovered(party_id, result)` | — | — | Moved to `gdd-poi-generation.md` scope |

The previously-implemented `lair_discovered` signal is replaced by `lair_placed`: in the Arbiter lazy model, placement and discovery are the same event, so the signal name should reflect that. `lair_cleared` is new and represents the end-of-life event for a placed lair (and the trigger for Build Stronghold becoming eligible per §7).

`result` payload keys for each signal are documented in `event_bus.gd` immediately above each `signal` declaration.

---

## 10. Migration note (2026-05-27)

This GDD supersedes the Phase 4 v1 lair-discovery implementation. The old design built two project-designed extensions on top of RAW:

1. A **per-leg passive 1d20 lair-spot** rolled at every travel_leg into a hex with undiscovered lairs (§3.1 of the old GDD).
2. An **eager world-gen lair placement** path that pre-populated hexes with lair records before encounters surfaced them (§3.3 of the old GDD).

Both were part of a more complicated hex-clearing workflow that is being dropped. The Arbiter system reverts to strict RAW: lairs are placed lazily by wandering-encounter substitution only, capped per hex by RAW lairs_per_hex.

**Implementation work the build agent must perform to complete this migration:**

- **Remove** the `_passive_lair_check` path from `wilderness_handlers.gd` and any travel_leg call site that invokes it.
- **Remove** all eager world-gen lair placement code paths; the setting-generation pipeline does not place lairs.
- **Add** the per-hex lair state per §3.1 (budget, placed count, unrevealed types queue), including the `hexes` table migration.
- **Create** `LairTypeResolver` per §3.1 — wraps the Wilderness Encounters by Terrain roll plus the `% In Lair > 0` re-roll loop. Reused by Survey (§4.3) and lazy-Search (§5.3).
- **Add** the wandering-substitution → Lair Generator branch per §3.2 (the Lair Generator subsystem itself is forthcoming; the call site can stub with a minimal placeholder until the generator GDD lands). Substitution pops one entry from `unrevealed_lair_types` if non-empty.
- **Rewire** the `search_lair` activity per §5 — on success, pop from `unrevealed_lair_types` (or lazy-roll one type via LairTypeResolver if empty), call LairGenerator with that type, surface the `Enter {Type} Lair` button (§6.2). Duration drops from the v1 8-hour block to a 1-hour minor strenuous activity per the Campaign Play classification.
- **Rewrite** `SurveyingResolver.assess` per §4.3 — on success, roll budget if needed, eagerly roll all remaining types into `unrevealed_lair_types`, reveal `lair_budget` (or false value on an unmodified 1) to the player. The false value is display-only; do not corrupt `lair_budget` or `unrevealed_lair_types`.
- **Add** hex tooltip + Status Bar "Lairs: X/Y" display per §6.1, with the visibility rules (hidden before any placement; shows discovered count denominator pre-Survey; shows surveyed total post-Survey).
- **Add** `Enter {Type} Lair` button surface per §6.2, with stable ordinal numbering for duplicate-type lairs and a `Re-enter {Type} Lair (cleared)` variant for cleared lairs.
- **Add** Build Stronghold gating per §7 — `HexLairState.has_uncleared_placed_lair()` helper; context-menu builder omits the entry when true.
- **Rename** the `lair_discovered` signal to `lair_placed`; add `lair_cleared`. Update payloads per §9. Update all listeners (NotificationManager, hex renderer, Status Bar, context-menu builder, Notebook).
- **Audit tests** — any test that asserts a lair existing before a wandering encounter surfaces it, or that exercises the passive check, must be rewritten or deleted.
- **Schema migration** — add `hex.lair_budget`, `hex.lair_budget_rolled_at_round`, `hex.lairs_placed_count`, `hex.unrevealed_lair_types` (JSON), `hex.surveyed_total` (nullable; the player-displayed total, may be false on an unmodified-1) columns; add `lair.cleared_at_round`; drop `lair.discovered` (in the new model placement IS discovery, so the column is meaningless).

---

## 11. Deferred / open items

- **Stronghold gating against unrevealed lairs** (§7 open question). Default Arbiter behavior is to gate only against placed-and-uncleared lairs; unrevealed budget slots do not block Build Stronghold. Strict RAW (L&E §judge_guidance L177–179) leaves this to Judge discretion. The current default permits player exploits (build a stronghold in a hex with high lair_budget but no Survey, then handle "surprise" lair pop-ups as stronghold events). Reconsider at play-test.
- **Lair re-occupation and refill over time.** RAW includes rules so cleared lairs can be re-occupied and so the regional map doesn't become "dead" — razed domains naturally drift back toward true wilderness, fresh lairs emerge in long-quiet areas. V1 does not model this; cleared lairs stay cleared and slots stay closed per §3.4. Deferred.
- **Specialist bonuses** (Pathfinder, Land Surveyor, Cartographer per `le_wilderness_lair_rules.xml §hirelings`). The `optional_specialist_bonus` parameter on resolvers stays; the Phase 6 specialist subsystem wires actual bonus values.
- **Eager pre-rolling workflow.** L&E p.13's "How many monsters?" procedure for hexes the PCs intend to clear for a domain — pre-roll the full budget AND monster types AND specific lair listings up front — is deferred. The Survey path in §4.3 already eagerly rolls all unrevealed types on first success, which captures most of the same effect; an explicit "eager pre-roll on first hex visit" mode is not currently needed.
- **Sub-party splitting** per RAW §splitting_up. Deferred.
- **Aerial reconnaissance** (×2 movement, half-hour cadence). Deferred (no flying mounts wired yet).
- **Re-stocking**. Long-term world evolution — cleared lairs re-occupied, new lairs migrating in. Deferred.
- **POI discovery** (static points of interest, not lairs). Lives in `gdd-poi-generation.md`.
