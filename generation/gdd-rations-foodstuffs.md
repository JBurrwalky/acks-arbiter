# GDD: Provisions — Rations, Water & Fodder Consumption System

**Authority:** PROJECT-DESIGNED — consumption bookkeeping, container model, and grazing data are engineering decisions; the daily consumption rates, foraging yields, ration spoilage, and grazing eligibility are RAW and may not be changed.
**Status:** IMPLEMENTED 2026-06-08 (all three phases). §4 decision: **Option B** (inventory is truth; counters are per-tick scratch; SustenanceResolver unchanged), confirmed by Jedidiah. Animal-starvation = HP loss on the PC curve. `coding_conventions.md §28` reversed accordingly. Migrations 149/150; `ProvisionsLedger`/`ProvisionsService` + `GrazingRules` + `AnimalSustenanceResolver`. Deferred: ration spoilage + scurvy (§2/§8), dead-mount load-drop, animal water draw (RAW-silent).
**Depends on ACKS rules:** `rules/acore_adventures_and_encounters.xml:322` + `:546-560` (daily food/water consumption, lack-of-food / lack-of-water penalties, standard-ration spoilage, scurvy); `rules/ax_campaign_play.xml:226-236` (foraging throw 18+ / +4 Survival / 1d6 man-days food); `rules/acore-campaign-hijinks.xml:953-1013` (Animals table — fodder cost per 10-stone load); `rules/le_monster_training_rules.xml:410-420` (creature supply cost; grazing/hunting waives provisions); `rules/acore_equipment.xml:120-126` (ration cost ranges, waterskin/barrel entries).
**Depends on project GDDs:** [`gdd-hunting-foraging.md`](gdd-hunting-foraging.md) (owns the forage/hunt yield mechanics that feed the food pool; this GDD consumes from it); [`gdd-party-tab.md`](gdd-party-tab.md) (already specifies the three-line food/water/fodder readout this system must source); [`gdd-treasure-item-backing.md`](gdd-treasure-item-backing.md) §14 (Decanter of Endless Water refill, a water-source analog).
**Implementing files (current, partial):** `engine/subsystems/exploration/sustenance_resolver.gd`, `engine/subsystems/exploration/foraging_resolver.gd`, `engine/subsystems/exploration/hunting_resolver.gd`, `engine/subsystems/session/handlers/wilderness_handlers.gd`, `engine/subsystems/inventory/decanter_refill_service.gd`, `engine/shared_types/party_data.gd`, `scenes/ui/hud/session_status_bar.gd`, `scenes/ui/notebook/tab_pages/party_tab_page.gd`, `data/equipment/base_equipment.json`.
**Modifiable by Claude Code:** Yes within constraints. The §4 source-of-truth decision changes `docs/coding_conventions.md §28` and is **[NEEDS-JEDIDIAH]** — do not implement it without sign-off. Everything downstream (consumption order, container fill logic, fodder rates, display) is engineering.
**Last updated:** 2026-06-08

---

## 1. Purpose

Make carried provisions — rations, water, and animal fodder — *mechanically real*: consumed day by day from the party's actual inventory, replenished at the right sources, and displayed honestly so the player can plan a journey. Today the party can starve to death with a full pack of rations because carried food never reaches the consumption math; water is an abstract counter that ignores the waterskins and barrels the player bought; and fodder does not exist at all. This GDD unifies food, water, and fodder into one consumption system layered on the existing (tested) starvation/dehydration penalty engine.

The redesign was directed by Jedidiah on 2026-06-08 after a playtest. It is "the same system" for all foodstuffs, so it is specified and built as one piece (in phases), not three disconnected features.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Daily consumption is 1 stone per character per day** — 2 lb of food + 1 gallon of water (`rules/acore_adventures_and_encounters.xml:322`, §rations_and_foraging). The engine already encodes this as 1 ration person-day + 1 water person-day per humanoid per day.
- **Lack of food:** no effect for the first two days; after that, lose 1 hp/day and cannot heal naturally (magic still works); one full-ration day restores natural healing (`rules/acore_adventures_and_encounters.xml:322`, §lack_of_food). **Already implemented and unit-tested in `SustenanceResolver`; preserve unchanged.**
- **Lack of water:** lose 1d4 hp on the first dry day and +1d4/day thereafter; healing is lost the moment the first die is rolled (`rules/acore_adventures_and_encounters.xml:322`, §lack_of_water). **Already implemented and tested; preserve unchanged.**
- **Standard rations are perishable** — inedible after one week; long expeditions rely on iron rations (`rules/acore_adventures_and_encounters.xml:546-560`). Eating only iron rations for one month without fresh food causes **scurvy**: −1 STR and −1 CON per week, death if either hits 0, recovery 3/week on fresh food (same cite). *(Spoilage + scurvy are out of scope for v1 consumption but are recorded here as the eventual home for the perishability rule.)*
- **Foraging** requires a wilderness hex; proficiency throw 18+ on 1d20, +4 with Survival; success yields enough food to feed **1d6 man-sized creatures for one day** (`rules/ax_campaign_play.xml:226-236`). Owned by [`gdd-hunting-foraging.md`](gdd-hunting-foraging.md); this GDD only consumes the result.
- **Fodder** for beasts of burden is sold and measured in **10-stone loads**, costing ~5 gp/week for most animals (warhorse 7 gp/wk, elephant 20 gp/wk) (`rules/acore-campaign-hijinks.xml:953-1013`, Animals table). This anchors fodder weight (10 stone/load) and the weekly upkeep magnitude.
- **Grazing / hunting waives supplied provisions:** "Eggs, herbivores grazing on a pasture, and carnivores hunting on a range require no supplied provisions" (`rules/le_monster_training_rules.xml:410-420`, supply_cost). Grazing eligibility is therefore **per-creature (diet) × terrain**, not a global toggle — confirming Jedidiah's "animals may have unique per-animal grazing rules."
- **Waterskin ≈ 1 quart; barrel ≈ 20 gallons** — the project's `base_equipment.json` uses these (waterskin = 1 water person-day, barrel = 20). The exact RAW capacities should be confirmed against `rules/acore_equipment.xml:120-126`. **[NEEDS-RAW-LOOKUP]** the precise gallon figures and whether RAW gives a per-day animal *water* draw distinct from humans.

---

## 3. Current Implementation Audit

Jedidiah's working hypothesis was that this system "should already have been built" and that something may have rewound the project. **It did not.** A deliberately-simple counter-based MVP was built (and is documented as such in `coding_conventions.md §28`), and the richer inventory-driven model below was always the intended end-state but deferred ("Phase 3.5 polish" in `gdd-hunting-foraging.md`) and never built. Nothing was reverted; the placeholder is simply masquerading as "done."

### 3.1 Built and working

| Piece | Where | Notes |
|---|---|---|
| `ration_units` / `water_units` person-day counters | `PartyData` (migration 047) | **Source of truth per `coding_conventions.md §28`**; inventory declared "purely descriptive." |
| Daily consumption + RAW penalties | `SustenanceResolver.apply_daily` | Consumes both counters by `party_size`; rolls starvation/dehydration HP exactly per RAW. Fully unit-tested (`test_sustenance_resolver.gd`, `test_wilderness_loop_starvation.gd`). Counts **humanoids only** (PCs + henchmen); creatures/mounts excluded. |
| Food found in the field | `ForagingResolver`, `HuntingResolver` | Add to `ration_units` on the noon tick. |
| Water from the environment | `WildernessHandlers._refill_water_at_hex` (`:1623`), `DecanterRefillService` | River/lake/town hexes (and the Decanter) top `water_units` to `party_size`. |
| Tick ordering | `wilderness_handlers` | noon → forage (buffered) → midnight → `SustenanceResolver`, so food found by day offsets that day. |
| Real containers with capacity | container sub-carrier refactor (commit `767f72f`) | `container_capacity_units` enforced; Bag of Holding/Devouring shipped. **Per-container storage exists** — the barrel/waterskin model is unblocked. |
| Catalog tags | `data/equipment/base_equipment.json` | `waterskin` {water, 1, holds_water}; `barrel` {water, 20, holds_water}; `rations_iron_week` / `rations_standard_week` {food, 7, 1 stone}. `holds_water` is UI-only today. |
| Inventory resource display | `party_tab_page._accumulate_resource_items` | Already sums food/water/fodder person-days from inventory tags for the Party tab. |

### 3.2 Missing / broken (the playtest bugs)

- **BUG 4 — carried rations do nothing.** `rations_*_week` items never feed `ration_units`; the party starves with a full pack. The inventory→counter sync was deferred and never built.
- **BUG 5 — Status Bar shows 0 rations.** `session_status_bar.gd` reads the orphaned `PartyData.rations_days_remaining` field (migration 021), which nothing updates. It is decoupled from the live `ration_units` mechanic.
- **BUG 6 — no fodder.** No fodder item in `base_equipment.json` (the display has only a `fodder_` prefix fallback); no fodder counter; `SustenanceResolver` does not feed animals; no grazing.
- **Granularity.** Rations are week-blocks (1 item = 7 person-days = 1 stone). Jedidiah wants daily-unit granularity ("Standard/Iron Rations × 7").

---

## 4. The Source-of-Truth Decision (central, [NEEDS-JEDIDIAH])

Jedidiah's redesign makes **inventory the source of truth**: rations, water, and fodder are real items consumed from packs; water is physically held in waterskins (liquid only) and barrels (items XOR water). This **reverses `coding_conventions.md §28`**, which states "the counter is the source of truth, and the inventory layer … is purely descriptive. Do not introduce food items as a parallel system." We must pick one model and update §28 accordingly.

**Option A — Inventory-as-truth (full supersede of §28).** Retire the counters as state; rations/water/fodder live only as inventory. Forage/hunt deposit real ration items (or a "foraged food" item); `_refill_water_at_hex` and the Decanter fill real waterskins/barrels; `SustenanceResolver` consumes items directly.
- *Pro:* cleanest match to the player's mental model; one source of truth; encumbrance is automatically correct.
- *Con:* largest blast radius — rewrites the tested forage/hunt/refill/decanter plumbing and the resolver's inputs; foraged food needs an item identity and a perishability story; highest regression risk to a SACRED-RAW-bearing resolver.

**Option B — Inventory-as-truth, counter-as-per-tick-scratch (recommended).** Inventory remains the truth, but each day-tick *derives* the consumable totals from carried inventory into the existing `ration_units` / `water_units` scratch values, runs the **unchanged** `SustenanceResolver`, then writes the consumption back to inventory (decrementing the items actually eaten/drunk). Waterskins/barrels act as **water carrying-capacity caps**: you can only carry as much water as your skins+barrels hold, and "fill at a source" tops those containers up.
- *Pro:* preserves the tested resolver and the forage/hunt/refill/decanter code essentially as-is; smallest change to land the critical fix; honors "rations × 7 / water in skins+barrels / foraged > standard > iron."
- *Con:* two representations exist transiently (inventory + per-tick scratch); the write-back must be carefully ordered so it is idempotent across a missed/duplicated tick.

**Recommendation: Option B.** It ships the starvation fix fastest, keeps the RAW penalty math untouched, and still delivers the player-visible behavior Jedidiah asked for. §28 would be rewritten from "counter is truth, inventory descriptive" to "inventory is truth; the counter is a per-tick derived scratch value." This GDD's §5–§7 assume Option B; if Jedidiah picks A, §5 consumption order and §6 data model stand, but §7 phasing expands.

---

## 5. Project Decisions (target design)

### 5.1 Rations (food)

- **Daily-unit model.** A "week" purchase yields **7 person-days**. The catalog gains daily-unit ration items (`rations_standard` / `rations_iron`, `consumable_person_days: 1`, encumbrance = 1 stone ÷ 7 ≈ 143 units each) **or** retains the week item with a per-row `units_remaining` counter. *Engineering choice; daily-quantity items are simpler to reason about and match the "× 7" framing, but multiply row counts — see §6.*
- **Consumption priority (perishable-first):** foraged food → **Standard** rations → **Iron** rations. Foraged food is the existing `ration_units` deposit and is consumed first; among carried items, perishable standard rations are eaten before shelf-stable iron rations.
- **Aggregation:** food is pooled across the **whole party's** inventories (any member's rations feed any member); consumption is `party_size` person-days/day (humanoids only, per §2).
- **Shortfall** flows into the existing `SustenanceResolver` starvation path unchanged.

### 5.2 Water

- **Containers, not free counter.** Water is held in **waterskins** (liquid only — never general items) and **barrels** (general items **OR** water, never both at once). A barrel currently holding items is not a water container until emptied.
- **Capacities (RAW-anchored):** waterskin = 1 person-day; barrel = 20 person-days (`base_equipment.json`; confirm gallons vs `acore_equipment.xml`). Total carry-cap = Σ container capacities.
- **Fill at a source:** on entering/holding at a **river hex, lake coast, town, or a successful foraging water roll**, fill **all** waterskins and **all** barrels that are empty *or* already partially holding water (skip barrels holding items). This generalizes the existing `_refill_water_at_hex` cap-to-`party_size` behavior into "cap-to-container-capacity." The Decanter (`DecanterRefillService`) becomes a portable source using the same fill routine.
- **Consumption:** `party_size` person-days/day drawn from carried water; shortfall → `SustenanceResolver` dehydration path unchanged. **[NEEDS-RAW-LOOKUP]** whether animals add to the daily water draw (§5.3).

### 5.3 Fodder + grazing

- **Fodder is a real item**, tracked separately from human rations. Add `fodder` to `base_equipment.json` (`consumable_kind: fodder`; 1 load = 10 stone per RAW; pick a daily person-day-equivalent granularity mirroring rations).
- **Consumption rate by animal size.** Each trained creature/mount consumes fodder per day scaled by size; use the catalog `normal_load` / `unencumbered_load` as the size proxy (the Party tab already does this). Calibrate against the RAW 10-stone-load weekly cost so a horse's daily fodder ≈ its share of a load/week. **[NEEDS-RAW-LOOKUP]** the exact per-animal daily fodder quantity (the hijinks table gives cost/week, not stones/day directly).
- **Grazing (per-creature × terrain).** A creature that can graze/hunt in the current terrain needs **no fodder that day** (`le_monster_training_rules.xml:410-420`). Eligibility is a **per-species datum** (diet = herbivore/carnivore/omnivore) gated by terrain (pasture/grassland/forest range vs barren/dungeon/winter). Store grazing diet + eligible-terrain on the monster/creature record so individual animals can carry unique rules. Animals that cannot graze and have no fodder take a starvation analog (or are lost) — **[NEEDS-JEDIDIAH]** the animal-starvation consequence (HP loss like PCs? morale/loss check?).
- **Animals counted in the tick:** extend `SustenanceResolver` (or a sibling `AnimalSustenanceResolver`) to iterate the party's trained creatures for fodder (and possibly water) the way it iterates humanoids for rations.

### 5.4 Display

- **Status Bar:** replace the dead `rations_days_remaining` read with **real remaining-days** for food (and water), computed from the unified model: `floor(total carried person-days ÷ party_size)`.
- **Inventory-tab footer** (`inventory_tab_page._count_rations`): same real food-days figure, plus water and fodder days.
- **Party tab** already renders the three-line food/water/fodder display (`_accumulate_resource_items`) — make the Status Bar/footer agree with it; this GDD makes all three read from one helper.

---

## 6. Data Model

Option B (recommended) requires **no new persistent state** beyond what exists, plus optionally a fodder field set:

- **No schema change for food/water** if rations/water are pure inventory items decremented in place. The `ration_units`/`water_units` columns survive as the per-tick scratch values (or are demoted to transient `PartyData` members).
- **Fodder:** add `fodder` catalog item(s) to `base_equipment.json`. If animal grazing-diet is not already on the monster catalog, add `graze_diet` ("herbivore"|"carnivore"|"omnivore"|"none") and `graze_terrains` (array) to the creature/monster record. **[NEEDS-RAW-LOOKUP / data audit]** whether `le_monster_catalog_*` already carries a diet field.
- **Ration granularity:** if daily-unit items are chosen, a one-time migration/conversion turns existing `rations_*_week` ×N rows into `rations_*` ×(7N) rows (and updates premade-party JSON). If `units_remaining` is chosen instead, add that column to `inventory_items`.
- **Retire `rations_days_remaining`** (migration 021) once the Status Bar no longer reads it — leave the column (non-destructive) but mark it dead in `schema.sql`.

---

## 7. Phasing

Each phase keeps the `SustenanceResolver` penalty math intact and ships an independently-testable slice.

```
Phase 1  FOOD  — the critical fix
Phase 2  WATER — containers + fill-at-source
Phase 3  FODDER + GRAZING — animals join the tick
```

1. **Phase 1 — Food (fixes the starvation bug).** Decide the daily-unit representation (§5.1/§6). In the day-tick, before `SustenanceResolver`, top the food pool from carried rations (foraged → standard → iron), decrementing real inventory; write the eaten amount back. Fix the Status Bar + footer food readout. Net result: a party with rations in the pack stops starving. Tests: a fed party loses no HP; foraged-before-carried ordering; standard-before-iron ordering; empty packs still starve on the RAW curve.
2. **Phase 2 — Water.** Implement waterskin/barrel carry-caps + fill-at-source (generalize `_refill_water_at_hex` and the Decanter to fill containers), barrel items-XOR-water exclusivity, daily water draw from containers, §4 §28 rewrite. Tests: fill at river/lake/town/forage; barrels-with-items skipped; dehydrate only when containers empty.
3. **Phase 3 — Fodder + grazing.** Add fodder item(s); per-animal daily fodder by size; per-species × terrain grazing waiver; animals counted in the tick; animal-starvation consequence (pending §5.3 ruling). Tests: grazing herbivore in grassland needs no fodder; same animal in a dungeon/desert consumes fodder; out-of-fodder non-grazer triggers the chosen consequence.

---

## 8. Open Questions / Architectural Concerns

- **[NEEDS-JEDIDIAH] §28 reversal (the gate).** Option A vs B in §4. Recommended B. This rewrites a documented convention; do not implement before sign-off.
- **[NEEDS-JEDIDIAH] Animal-starvation consequence.** What happens to an animal with no fodder and no grazing — HP loss like a PC, a morale/loss check, or simply "the animal is lost"? RAW covers upkeep cost, not field starvation of an adventuring mount.
- **[NEEDS-RAW-LOOKUP] Exact figures.** Waterskin/barrel gallon capacities (`acore_equipment.xml:120-126`); whether animals add to the daily *water* draw and at what rate; the per-animal daily *fodder* quantity (derive from the 10-stone-load weekly cost in `acore-campaign-hijinks.xml`).
- **Data audit.** Does `le_monster_catalog_*` already carry an animal diet/grazing field? If so, reuse it for §5.3 rather than adding `graze_diet`.
- **Ration granularity choice.** Daily-quantity items (simple, matches "× 7", more rows) vs a `units_remaining` column on the week item (fewer rows, new column, must update all display sites). Engineering call to settle in Phase 1.
- **Perishability + scurvy (deferred).** Standard-ration 1-week spoilage and iron-ration scurvy (§2) are RAW but out of v1 scope. This GDD is their eventual home; flag so they are not forgotten.
- **Encumbrance interaction.** Whichever model is chosen, eating/drinking must keep encumbrance correct as provisions deplete — straightforward under Option B (inventory is decremented) but must be verified against the container sub-carrier weight rollup.
- **Overlap with [`gdd-hunting-foraging.md`](gdd-hunting-foraging.md).** That GDD owns forage/hunt *yields*; this one owns *consumption*. Keep the boundary clean: forage/hunt deposit into the food pool; this GDD never re-rolls yields.
