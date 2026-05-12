# GDD — Settlement Economy

> **Status:** Drafting (2026-05-12). Section-by-section sign-off in progress with project owner.
>
> **Audience:** The Phase 10B-prerequisite mercantile build session and the downstream Phase 10B.2 (Trade) / 10B.3 (Syndicate) sessions that consume it.
>
> **Companion documents:**
> - `docs/phase-10b-prereq-mercantile-handoff.md` — the session brief that authorized this GDD (Q-MERC-1 [RESOLVED] approval).
> - `docs/phase-10b-subsystem-dependencies.md` — Phase 10B subsystem scope index.
> - `docs/phase-10b-prereq-environmental-adjustments-table.md` — canonical transcription of the Environmental Adjustments to Demand table (audit trail for Q-MERC-1A; the XML at `rules/acore-setting-construction-rules.xml:297-353` is now authoritative).

---

## §0. Document Goals, Scope, and the RAW-vs-Project-Design Ledger

### 0.1 What this GDD covers

This document specifies the settlement-economy substrate that the mercantile and syndicate game loops sit on top of:

1. **Settlement-level economic state** — schema additions to `settlement_entrances` and adjacent tables so that per-settlement demand modifiers, market prices, and merchant pools can be computed deterministically.
2. **The RAW six-step demand-modifier generation procedure** — encoded from `rules/acore-setting-construction-rules.xml:221-367` §generating_demand_modifiers, with every input wiring resolved against the project's current schema (biome/biome_subtype/water/elevation/race/age/domain land revenue/trade routes).
3. **Market price computation and monthly drift** — encoded from the formula at `rules/acore-campaign-hijinks.xml:719-735` (`4d4 + demand_modifier + class_size_adjust`, then ×base_price×0.1) plus the 10%/month re-roll trigger at L737-739.
4. **Trade-route detection and regional demand propagation** — encoded from the trade-route rules at `rules/acore-setting-construction-rules.xml:358-365` and the `range_of_trade` table at L264-278.
5. **Merchant-pool model** — the permanent-pool design that resolves Q-MERC-5 (Markets and Merchants table at `rules/acore-campaign-hijinks.xml:656`).
6. **Market fees** — customs, moorage, stabling, tolls, loading/unloading, with the domain-owner exemption (RAW citations in §9).
7. **Ships and cargo holds** — full vehicle/cargo build for merchandise transit (Q-MERC-7 upgraded from stub to full RAW).
8. **Crime & Punishment data prerequisites** — Profession (attorney) proficiency and `prior_crimes` character columns the Phase 10B.3 resolver will consume.

### 0.2 What this GDD does NOT cover

- The Trade block UI (Phase 10B.2's job).
- The Syndicate block UI, hijink resolvers, or the Crime & Punishment resolver (Phase 10B.3's job; this GDD ships only their data prerequisites).
- NPC venturer rivals, monopoly market-disruption effects, NPC merchant migration between settlements (all deferred to v1.1+ per Q-MERC-4 / Q7).
- Settlement *generation* — when settings are procedurally generated, where settlement age and dominant race get rolled — that is a setting-generation system that consumes this GDD's schema, not part of this GDD's scope.

### 0.3 The RAW-vs-Project-Design ledger format (§5.0 mandatory rule)

Every project-designed element in this document MUST carry a four-line ledger entry:

- **RAW citation:** the exact file + line range in `rules/` that the element grounds against. If the element exists because RAW is silent, the citation is the closest adjacent rule (e.g. "RAW gives us X but is silent on Y, so we project-design Y").
- **What RAW provides:** a one- or two-sentence verbatim summary of the RAW rule.
- **What's missing:** the precise gap that requires project-design fill.
- **Project resolution:** the rule this GDD locks in, with rationale.

The ledger is the audit trail. A future contributor asking "why does the demand-modifier generator do X" must be able to follow the trail to either a RAW citation (X is rules-encoded) or a project-design rationale (X is author-discretion, here is why). **No silent project-design anywhere in this document.**

A worked example of the format appears in every subsequent section. Where a section is pure RAW encoding (e.g. the six-step procedure), the ledger collapses to one entry: "RAW citation X, what RAW provides, nothing missing, resolution = faithful encoding."

### 0.4 Authority and modification rules

- This GDD is Layer-2 per `CLAUDE.md` §Document Authority — **project-designed, modifiable** with project-owner sign-off. The RAW citations within it are not.
- The sacred-rules policy in `CLAUDE.md` (do not modify `rules/*.xml`) remains in force. The Q-MERC-1A correction of the environmental-adjustments table was a one-instance approved exception (2026-05-11) and does not generalize.
- If a future RAW spotcheck reveals a discrepancy with this GDD, **the RAW wins**. Update this document, do not change the rules.

### 0.5 Calendar conventions

The project uses a **custom 13-month / 28-day / 364-day calendar** (no leap year) per `engine/autoloads/timekeeping.gd:9-10,52-59`. Constants:

- `Timekeeping.DAYS_PER_MONTH := 28`
- `Timekeeping.MONTHS_PER_YEAR := 13`
- `Timekeeping.DAYS_PER_YEAR := 364`

**Every "monthly" window in this GDD — merchant pool expiration, the §6 drift mechanic's cumulative probability calculation, the once-per-month solicit cooldown, monthly tick cadence — uses 28 days, not 30.** All code samples reference `Timekeeping.DAYS_PER_MONTH` rather than hard-coding the number, so a future calendar change (e.g., switching to a real-Earth 30-day approximation) is a one-place fix.

Where this GDD writes "monthly" in prose, the duration meant is 28 calendar days. RAW prose that says "each month" maps to the project's 28-day month: RAW assumes a roughly-30-day month but the rules are agnostic to exact length, and the project's calendar is the source of truth.

---

## §1. Settlement Schema Additions and `urban_families` Relocation

### 1.1 Migration overview (097)

This section adds four columns to `settlement_entrances` (age, age bucket, dominant race, urban families) and *removes* `urban_families` from `domains` (Q-MERC-15 Option A — full relocation, not denormalization). It also re-points every existing caller that reads `domains.urban_families` to the new SoT.

Migration 097 lands as a single SQL file (`db/migrations/097_settlement_economy_inputs.sql`) and a paired GDScript caller-audit pass.

**Why all in one migration:** the four columns are interlocked. Demand-modifier generation reads all four together. Splitting the migration risks an in-flight schema where age exists but race doesn't, etc. The caller-audit pass touches a measurable set of files and is a single coherent refactor.

### 1.2 New columns on `settlement_entrances`

#### `age_years INTEGER NOT NULL DEFAULT 500`

- **RAW citation:** `rules/acore-setting-construction-rules.xml:227-234` step 2 of the six-step procedure references the `environmental_adjustments_to_demand` table, whose age-bucket columns are 0-20 / 21-100 / 101-1000 / 1001-2000 / 2001+ years.
- **What RAW provides:** discrete age buckets used as a lookup key into the environmental adjustments table.
- **What's missing:** RAW operates in buckets but doesn't say at what *integer year* a settlement is considered. The schema doesn't currently track age at all.
- **Project resolution:** store the integer age in years; derive the bucket in code via a pure function `SettlementEconomyInputs.age_bucket_for(age_years)`. Storing the integer (not the bucket) means we don't have to migrate values across the schema as the settlement ages in calendar time. Default 500 places un-aged settlements in the **101-1000 years** bucket — per Jedidiah 2026-05-12, "most towns on earth are over 100 years old," and 500 sits mid-bucket so settlements remain in the same bucket through several centuries of calendar drift before promotion.

**Boundary convention** (project-designed; RAW silent on inclusivity):
- `age_years <= 20` → bucket `0_20_years`
- `21 <= age_years <= 100` → bucket `21_100_years`
- `101 <= age_years <= 1000` → bucket `101_1000_years`
- `1001 <= age_years <= 2000` → bucket `1001_2000_years`
- `age_years >= 2001` → bucket `2001_plus_years`

#### `age_bucket TEXT` — **NOT ADDED**

- **Resolution:** do *not* persist the bucket. Derive it. Storing both creates an invariant ("bucket matches age") that must be maintained on every update.

#### `dominant_race TEXT NOT NULL DEFAULT 'human'`

- **RAW citation:** `rules/acore-setting-construction-rules.xml:253-262` `racial_adjustments_to_demand` table — Dwarf and Elf settlements receive specific -2 modifiers to listed merchandise types.
- **What RAW provides:** racial adjustment rule keyed on Dwarf / Elf identity.
- **What's missing:** schema had no dominant-race column on settlements.
- **Project resolution:** TEXT column. Accepted values match the project's existing race vocabulary (`human`, `dwarf`, `elf`, plus whatever other races the campaign defines). Only `dwarf` and `elf` trigger RAW step 5; all others contribute zero racial adjustment. Default `human` — RAW racial adjustment is opt-in and the no-modifier case is the safe default for un-classified settlements.
- **Conquest invariant** (per Q-MERC-13 [RESOLVED 2026-05-12]): settlement.dominant_race is independent of the parent domain's ruler. A human settlement conquered by an elven duchy keeps `dominant_race='human'` and continues to receive zero racial adjustment. Future system for population displacement / cultural drift over time is **out of scope**.

#### `urban_families INTEGER NOT NULL DEFAULT 0`

- **RAW citation:** `rules/acore_axioms_strongholds_and_domains.xml:658-704` (settlement size → market class derivation) + `rules/acore-setting-construction-rules.xml:362` (trade-route processing order uses market size — i.e. urban_families).
- **What RAW provides:** urban_families is the population metric that maps to market class, monopoly revenue (1gp/urban_family/month per `rules/ax_venturer_class.xml:207`), and trade-route processing order.
- **What's missing:** urban_families lived on `domains` historically, which conflates "people in the rural countryside" with "people in the chief settlement of the domain." Per Jedidiah 2026-05-12: settlements have market classes; domains do not; urban_families belongs on the settlement that contains those urban dwellers.
- **Project resolution:** add to `settlement_entrances`. The RAW-canonical relationship is settlement→urban_families→market_class. Default 0 means "no urban population yet recorded"; setting-generation populates this when settlements are created.
- **Backward-compatibility note:** existing `settlement_entrances` rows generated before this migration will have `urban_families = 0` (the column default). The migration's data-move step (1.4 below) backfills these from the parent domain's previous `urban_families` value.

### 1.3 `domains.urban_families` removal

Per Q-MERC-15 Option A (resolved 2026-05-12, full relocation, not denormalization):

- The column `domains.urban_families` is **dropped** as the schema's source of truth.
- Every caller that read `domains.urban_families` is migrated to read either:
  - `settlement_entrances.urban_families` directly (when one settlement is the focus, e.g., market-class derivation), or
  - `SUM(settlement_entrances.urban_families) WHERE parent_domain_id = X` (when domain-wide aggregation is needed, e.g., realm-tier classification).

**Multi-settlement domain handling:** a domain may contain multiple `settlement_entrances` (chief town + outlying villages). The aggregation query is the canonical way to derive the domain's total urban population. Until setting-generation supports multi-settlement domains, the practical case is one-settlement-per-domain and the aggregation query returns a single row.

**Why Option A and not B (derived column):** a derived column on `domains` would require an invariant — "`domains.urban_families = SUM(settlements.urban_families) WHERE parent_domain_id = domains.id`" — maintained on every settlement insert/update/delete. Dropping the column eliminates that invariant entirely. Existing callers move to one-line SQL queries; the cost is a one-time refactor against a measurable file count.

### 1.4 Migration script structure

`db/migrations/097_settlement_economy_inputs.sql` is **non-trivial** — it does an `ALTER TABLE ADD COLUMN` (additive), then a data-move (read existing `domains.urban_families`, write into `settlement_entrances.urban_families` via parent_domain_id join), then drops the old column. SQLite's restrictions on `DROP COLUMN` (added in SQLite 3.35; godot-sqlite version verification needed) means we may have to do a table-rewrite for the drop step.

Migration sub-steps (in order):

1. **`ALTER TABLE settlement_entrances ADD COLUMN age_years INTEGER NOT NULL DEFAULT 500;`**
2. **`ALTER TABLE settlement_entrances ADD COLUMN dominant_race TEXT NOT NULL DEFAULT 'human';`**
3. **`ALTER TABLE settlement_entrances ADD COLUMN urban_families INTEGER NOT NULL DEFAULT 0;`**
4. **Data-move:** `UPDATE settlement_entrances SET urban_families = (SELECT urban_families FROM domains WHERE id = settlement_entrances.parent_domain_id) WHERE parent_domain_id IS NOT NULL;`
   - Settlements without a parent domain remain at urban_families = 0. They will be populated when setting-generation lands or when a domain is later assigned.
5. **Drop the old column.** Two paths depending on SQLite version:
   - SQLite 3.35+: `ALTER TABLE domains DROP COLUMN urban_families;`
   - Older: table-rewrite (create temp, copy data, drop original, rename). Wrap in a transaction; the godot-sqlite binding requires a guard.

The migration must complete atomically — partial application leaves an inconsistent schema. Migration runner wraps all five steps in a single transaction.

### 1.5 Caller-audit checklist (Prereq.2a deliverable)

Every file referencing `domains.urban_families` (read or write) must be updated. Grep target: `\burban_families\b` across `engine/**/*.gd` and `scenes/**/*.gd`.

The audit pass:

1. **Read sites** (`SELECT urban_families FROM domains`) → migrate to one of:
   - direct read on `settlement_entrances.urban_families` when the call is settlement-scoped, OR
   - aggregation `SUM(settlement_entrances.urban_families) WHERE parent_domain_id = ?` when domain-scoped.
2. **Write sites** (`UPDATE domains SET urban_families = ?`) → migrate to `UPDATE settlement_entrances SET urban_families = ? WHERE id = ?` (i.e., the write moves from the domain to the specific settlement). Setting-generation, follower-arrival, and tax/revenue resolvers may need their own per-call audit to decide which settlement is the recipient.
3. **Existing tests** that assert against `domains.urban_families` → migrate to the new column path. Test data fixtures that seed `urban_families` need their seeding path updated.

The audit's deliverable is a build_log entry listing every changed file and the migration path chosen for each call site. This becomes the audit trail for the Option-A decision.

### 1.6 Indexes added by migration 097

- `CREATE INDEX idx_settlement_entrances_parent_domain ON settlement_entrances(parent_domain_id);` — speeds the SUM-aggregation query.
- `CREATE INDEX idx_settlement_entrances_dominant_race ON settlement_entrances(dominant_race);` — speeds racial-adjustment lookups, though selectivity is low (most settlements are human). Probably not load-bearing at v1 scale; can be revisited.

### 1.7 What §1 does NOT add

- **No `settlement_age_history`** — RAW step 2's age bucket is point-in-time; there's no need to track historical ages. Calendar time advances `age_years` via a monthly tick (Prereq.2a wires this in).
- **No `domain_dominant_race`** — per Q-MERC-13, the domain ruler and the settlement population are tracked independently. Domain doesn't need a "race-of-rulers" column; that's already derivable from `ruler_npc_id → characters.race`.
- **No settlement-economy cache table** — the demand-modifier cache table (`settlement_merchandise_demand`) lands in §4 with the demand-modifier procedure, not here.

### 1.8 Test coverage for §1 (Prereq.2a allocation)

The schema-side tests:

1. **Column existence and defaults.** After running migration 097, `PRAGMA table_info(settlement_entrances)` includes all three new columns with the declared defaults.
2. **`domains.urban_families` removed.** `PRAGMA table_info(domains)` does NOT include `urban_families`.
3. **Data-move correctness.** A fixture with two domains (one settlement each, urban_families = {1500, 800} on the old schema) → after migration, settlement_entrances.urban_families values are {1500, 800} keyed by parent_domain_id.
4. **Default-row safety.** A settlement_entrance with `parent_domain_id IS NULL` after migration has `urban_families = 0` (the default), not NULL.
5. **`age_bucket_for()` boundary cases.** age=20 → `0_20_years`; age=21 → `21_100_years`; age=100 → `21_100_years`; age=101 → `101_1000_years`; age=2001 → `2001_plus_years`. Five tests.
6. **Aggregation query.** Test fixture: domain D with three settlements (urban_families = {500, 200, 100}) → SUM aggregation returns 800.

Estimated test count for §1: **~10 tests**, all in `tests/test_settlement_economy_inputs.gd` (which will also house tests for §3 input lookups).

---

## §2. Merchandise Registry (Common + Precious)

### 2.1 Sources of truth

Three RAW sources feed this section, in priority order:

1. **`rules/acore-campaign-hijinks.xml:915-947`** — the `common_merchandise` table. **Canonical for** base prices, load definitions, encumbrance-per-load, and d100 roll ranges.
2. **`rules/acore-campaign-hijinks.xml:949-974`** — the `precious_merchandise` table. Same canonical fields, plus the Monster Parts footnote.
3. **`rules/acore-setting-construction-rules.xml:297-353`** — the `environmental_adjustments_to_demand` table (corrected 2026-05-11 per Q-MERC-1A). **Canonical for** the per-merchandise environmental modifier vectors that feed RAW step 2 of the demand-modifier procedure. Lives separately because it's an *input to demand modifier generation*, not a merchandise property per se. Encoded in §3.

The averages box at `rules/acore-campaign-hijinks.xml:997-1001` is **not encoded** by this system — see §2.10.

### 2.2 Categorization: 20 common + 11 precious

| Category | Count | Members |
|---|---|---|
| Common | 20 | Grain & vegetables, Fish (preserved), Wood (common), Animals, Salt, Beer & ale, Oil (lamp), Textiles, Hides & furs, Tea or coffee, Metals (common), Meats (preserved), Cloth, Wine & spirits, Pottery, Tools, Armor & weapons, Dye & pigments, Glassware, Mounts |
| Precious | 11 | **Monster parts**, Wood (rare), Furs (rare), Metals (precious), Ivory, Spices, Porcelain (fine), Books (rare), Silk, Semiprecious stones, Gems |

**Boundary-case clarification (project-design ledger entry):**

- **RAW citation:** `rules/acore-campaign-hijinks.xml:959` (Monster parts as the first precious_merchandise row, 01-10) vs. `rules/acore-setting-construction-rules.xml:343` (Monster parts in row 21 of the env adjustments table, immediately before the precious entries).
- **What RAW provides:** the canonical merchandise-table categorization (precious) and an environmental modifier vector at the boundary position.
- **What's missing:** my prior transcription artifact `docs/phase-10b-prereq-environmental-adjustments-table.md` grouped Monster parts as a "common" entry (row 21 of the "Common 1-21" header), which is a transcription header error on my part — RAW does not group by row position, it groups by table membership.
- **Project resolution:** Monster parts is **precious**. The merchandise registry's `precious` flag is `true` for it. The environmental-adjustments lookup keyed by `merchandise_type` resolves to row 21 of the env table irrespective of categorization. **Action:** also correct the section headers in `docs/phase-10b-prereq-environmental-adjustments-table.md` to "Common (rows 1-20)" + "Precious (rows 21-31, beginning with Monster parts)" when next touched. Will batch with §2's actual data encoding.

### 2.3 Common merchandise table (faithful RAW encoding, L915-947)

20 rows. Each carries a d100 roll range, a load description (sometimes a sub-table dispatcher), encumbrance per load in stone, and a base price in gp.

| Merchandise type | Roll | 1 Load | Stone | Base price |
|---|---|---|---|---|
| `grain_vegetables` | 01-04 | 20 bags | 80 | 10 gp |
| `fish_preserved` | 05-08 | 10 barrels | 80 | 50 gp |
| `wood_common` | 09-12 | 1 cord of logs | 80 | 50 gp |
| `animals` | 13-16 | Roll 1d6 on Animals | by animal | by animal |
| `salt` | 17-20 | 150 bricks | 80 | 100 gp |
| `beer_ale` | 21-25 | 10 barrels | 80 | 100 gp |
| `oil_lamp` | 26-30 | 5 jars | 30 | 100 gp |
| `textiles` | 31-35 | 4 bags | 20 | 100 gp |
| `hides_furs` | 36-39 | 10 bundles | 30 | 150 gp |
| `tea_coffee` | 40-43 | 2 bags | 10 | 150 gp |
| `metals_common` | 44-47 | 200 ingots | 100 | 200 gp |
| `meats_preserved` | 48-51 | 10 barrels | 80 | 200 gp |
| `cloth` | 52-54 | 20 rolls | 80 | 200 gp |
| `wine_spirits` | 55-60 | 1 barrel | 16 | 200 gp |
| `pottery` | 61-63 | 2 crates | 10 | 200 gp |
| `tools` | 64-68 | 1 crate | 10 | 200 gp |
| `armor_weapons` | 69-73 | 1 crate | 10 | 225 gp |
| `dye_pigments` | 74-75 | 5 jars | 25 | 250 gp |
| `glassware` | 76-80 | 2 crates | 10 | 400 gp |
| `mounts` | 81-85 | Roll 1d4+4 on Animals | by animal | by animal |

The d100 range `86-100` on the common table dispatches to the precious merchandise table. The registry does not store this as a merchandise type — it is consumed by the random-roll path (see §2.7).

### 2.4 Precious merchandise table (faithful RAW encoding, L949-974)

11 rows.

| Merchandise type | Roll | 1 Load | Stone | Base price | Notes |
|---|---|---|---|---|---|
| `monster_parts` | 01-10 | 1 crate | 5 | 300 gp | * See 2.5 |
| `wood_rare` | 11-25 | 1 cord | 16 | 500 gp | |
| `furs_rare` | 26-35 | 1 bundle | 5 | 500 gp | |
| `metals_precious` | 36-45 | 2 ingots | 4 | 600 gp | |
| `ivory` | 46-60 | 1 tusk | 8 | 800 gp | |
| `spices` | 61-65 | 1 jar | 1 | 800 gp | |
| `porcelain_fine` | 66-70 | 2 crates | 10 | 1,000 gp | |
| `books_rare` | 71-75 | 1 box | 3 | 1,000 gp | |
| `silk` | 76-90 | 5 rolls | 20 | 2,000 gp | |
| `semiprecious_stones` | 91-95 | 1 box | 1 | 1,000 gp | |
| `gems` | 96-100 | 1 box | 1 | 3,000 gp | |

### 2.5 Edge cases

#### 2.5.1 Animals and Mounts (dispatcher rows)

- **RAW citation:** `rules/acore-campaign-hijinks.xml:925,944` (the Animals and Mounts entries) + L976-995 (the Animals sub-table).
- **What RAW provides:** the Animals merchandise type rolls 1d6 on the Animals sub-table; Mounts rolls 1d4+4 on the same sub-table. The Animals sub-table has 7 rows (rabbit/hen, sheep, pig/goat, cattle, horse/yak, warhorse, elephant) with stone-per-animal, animals-per-load, fodder-cost, and per-load price.
- **What's missing:** the registry needs to know that `animals` and `mounts` are dispatcher types whose load weight and base price are not constants — they resolve only after a sub-roll.
- **Project resolution:** in the JSON, encode `animals` and `mounts` rows with `dispatcher: "animals_subtable"` and a `subroll: "1d6"` (or `"1d4+4"`). Their `load_weight_stone` and `base_price_gp` fields are `null` (sentinel for "not constant"). The Animals sub-table is encoded as a sibling JSON file `data/commerce/animals_subtable.json`. The merchandise registry's `random_common(rng)` resolution returns either a concrete row (load + stone + price) or, when a dispatcher row is rolled, recurses into the sub-table.

#### 2.5.2 Monster parts (per-monster XP derivation)

- **RAW citation:** `rules/acore-campaign-hijinks.xml:971-972` (the precious-merchandise note).
- **What RAW provides:** "Each monster part has gp value equal to the monster's XP value, so the number of parts in the load equals base price divided by monster XP." Base price 300 gp; stone 5.
- **What's missing:** the source monster determines per-part XP, so a 300 gp load of monster parts might be 30 parts (XP 10), 12 parts (XP 25), 6 parts (XP 50), etc. The registry needs to either (a) treat 300 gp as the canonical fixed base price and let the parts-count be a presentation detail, or (b) expose a helper that takes the monster row and computes the parts-count.
- **Project resolution:** the **base price stays 300 gp** for the demand-modifier and market-price formulas — `MarketPriceResolver` does not care which specific monster the parts come from. The parts-count detail is exposed via a helper `MerchandiseRegistry.monster_parts_count(monster_xp) -> int` that returns `floor(300 / monster_xp)`. Smuggling/stealing hijink resolvers that need to roll the source monster consume the helper; the rest of the pipeline doesn't.
- **Wandering-monster roll source:** RAW says "the region's wandering monster table." Project resolution: use the existing wilderness encounter resolver's monster-rolling helper, scoped to the settlement's parent hex's biome.

### 2.6 JSON schema

Two flat files in `data/commerce/`:

**`data/commerce/common_merchandise.json`** (20 entries):

```json
{
  "version": 1,
  "source": "rules/acore-campaign-hijinks.xml:915-947 (Common Merchandise)",
  "category": "common",
  "entries": [
    {
      "merchandise_type": "grain_vegetables",
      "display_name": "Grain, vegetables",
      "roll_range": [1, 4],
      "load_description": "20 bags",
      "load_weight_stone": 80,
      "base_price_gp": 10,
      "precious": false,
      "dispatcher": null
    },
    ...
    {
      "merchandise_type": "animals",
      "display_name": "Animals",
      "roll_range": [13, 16],
      "load_description": "Roll 1d6 on Animals",
      "load_weight_stone": null,
      "base_price_gp": null,
      "precious": false,
      "dispatcher": "animals_subtable",
      "subroll": "1d6"
    }
  ]
}
```

**`data/commerce/precious_merchandise.json`** (11 entries) — same shape with `"category": "precious"` and `"precious": true` on every row.

**`data/commerce/animals_subtable.json`** (7 entries) — the Animals sub-table for dispatcher resolution. Schema:

```json
{
  "version": 1,
  "source": "rules/acore-campaign-hijinks.xml:976-995 (Animals)",
  "entries": [
    {
      "animal_type": "rabbit_hen",
      "display_name": "Rabbit, hen",
      "roll_range": [1, 1],
      "stone_per_animal": 0.5,
      "animals_per_load": 200,
      "stone_per_load": 100,
      "fodder_gp_per_week": 5,
      "price_per_load_gp": 60
    },
    ...
  ]
}
```

`stone_per_animal` is a float because the rabbit/hen row reads "1 stone per 2" (= 0.5 stone per animal). The other rows are integers but the float type accommodates both.

### 2.7 `MerchandiseRegistry` API

Autoloaded singleton. Loads all three JSON files at init. No `class_name` (autoload constraint per CLAUDE.md).

**Public methods:**

```gdscript
# Lookups — exact-match
func all_common() -> Array  # Array of dicts
func all_precious() -> Array
func all_merchandise() -> Array  # both, in roll-order
func get_by_type(merchandise_type: String) -> Dictionary  # empty {} if not found
func is_precious(merchandise_type: String) -> bool

# Price / weight
func base_price_gp(merchandise_type: String) -> int  # 0 if dispatcher row (animals/mounts)
func load_weight_stone(merchandise_type: String) -> int  # 0 if dispatcher row

# Random roll (per RAW d100 tables)
func random_common(rng: RandomNumberGenerator) -> Dictionary
    # Rolls d100; resolves the row. If 86-100 (Roll on Precious), recurses
    # into precious. If "animals" or "mounts" dispatcher, resolves via
    # animals_subtable. Returns a fully-resolved merchandise dict with
    # concrete load_weight_stone and base_price_gp.
func random_precious(rng: RandomNumberGenerator) -> Dictionary
    # Rolls d100 on the precious table only. Returns concrete dict.

# Monster parts helper (RAW L971-972)
func monster_parts_count(monster_xp_value: int) -> int
    # Returns floor(300 / monster_xp_value); 0 if monster_xp <= 0.
```

**Why expose `random_common` and `random_precious` here, not at call sites:** centralized random resolution means smuggling, stealing, treasure-hunting, and (eventually) carousing-rumor-flavor all share the same RAW-compliant roll logic. Per CLAUDE.md the rule is "build mechanically" — the random merchandise pick is mechanical, not narrative.

### 2.8 Demand-modifier-key alignment

The 31 merchandise types in §2.3 and §2.4 must match the `merchandise` keys in the env-adjustments table at `rules/acore-setting-construction-rules.xml:297-353`. Concretely:

| env-table merchandise name | registry `merchandise_type` key |
|---|---|
| Grain, vegetables | `grain_vegetables` |
| Fish, preserved | `fish_preserved` |
| Wood, common | `wood_common` |
| Animals | `animals` |
| Salt | `salt` |
| Beer, ale | `beer_ale` |
| Oil, lamp | `oil_lamp` |
| Textiles | `textiles` |
| Hides, furs | `hides_furs` |
| Tea or coffee | `tea_coffee` |
| Metals, common | `metals_common` |
| Meats, preserved | `meats_preserved` |
| Cloth | `cloth` |
| Wine, spirits | `wine_spirits` |
| Pottery | `pottery` |
| Tools | `tools` |
| Armor, weapons | `armor_weapons` |
| Dye & pigments | `dye_pigments` |
| Glassware | `glassware` |
| Mounts | `mounts` |
| Monster parts | `monster_parts` |
| Wood, rare | `wood_rare` |
| Furs, rare | `furs_rare` |
| Metals, precious | `metals_precious` |
| Ivory | `ivory` |
| Spices | `spices` |
| Porcelain, fine | `porcelain_fine` |
| Books, rare | `books_rare` |
| Silk | `silk` |
| Semipr. stones (env table) / Semiprecious stones (merchandise table) | `semiprecious_stones` |
| Gems | `gems` |

The "Semipr. stones" abbreviation in the env table at `rules/acore-setting-construction-rules.xml:352` is RAW's own abbreviation; the canonical full form "Semiprecious stones" from the merchandise table at `rules/acore-campaign-hijinks.xml:968` is the basis for the registry key. A startup-time test asserts both tables resolve to the same key set (no orphans on either side).

### 2.9 Tests

`tests/test_merchandise_registry.gd` budget: **8 tests.**

1. **Common count = 20.** `MerchandiseRegistry.all_common().size() == 20`.
2. **Precious count = 11.** `MerchandiseRegistry.all_precious().size() == 11`.
3. **Total count = 31** and matches env-adjustments keys. `MerchandiseRegistry.all_merchandise().size() == 31`; every `merchandise_type` key resolves in the env-adjustments lookup.
4. **Spot-check base prices.** `grain_vegetables` = 10 gp; `silk` = 2,000 gp; `gems` = 3,000 gp.
5. **Spot-check load weights.** `grain_vegetables` = 80 stone; `spices` = 1 stone; `metals_common` = 100 stone.
6. **Dispatcher rows return null.** `base_price_gp("animals") == 0`; `load_weight_stone("mounts") == 0`. The "null sentinel = 0" pattern is documented in §6 alongside the price resolver.
7. **Roll-range coverage = 100.** Sum of `roll_range[1] - roll_range[0] + 1` over common entries (counting 86-100 dispatch) = 100; same for precious.
8. **`monster_parts_count`.** XP=10 → 30 parts; XP=25 → 12 parts; XP=300 → 1 part; XP=0 → 0 parts (safety).

### 2.10 What §2 does NOT add

- **No averages helpers.** RAW L997-1001 publishes summary averages (all = 300 gp / 70 stone; common = 180 gp / 80 stone; precious = 1,000 gp / 10 stone) as a quick-math convenience for human Judges resolving long-haul caravans without rolling on the full table. **No engine mechanic consumes them.** Smuggling, stealing, and arbitrage all sample concrete merchandise types via `random_common` / `random_precious` and price against real entries; the demand-modifier procedure does not read averages. If a downstream consumer ever did need an average (e.g., a UI tooltip showing "average gp/load in this market"), it can compute it from the loaded data in one line. **Resolution:** the averages are cited in §2.1 as context but are not exposed by the registry API. *(Project-design ledger: RAW L997-1001 = GM convenience; what's missing = mechanic that needs it; resolution = don't encode.)*
- **No catalog of specific creature/monster XP values** — the monster catalog is the source of truth; the merchandise registry only exposes the helper.
- **No automatic encoding of `monster_parts.base_price = 300 / monster_xp * parts_count`** — RAW's stated invariant is "value = XP × parts," which is read-only from the player's perspective. The 300 gp base stays fixed in the registry; per-load resolution is the consumer's job.
- **No "merchandise quality" tier (poor / standard / fine)** — RAW does not introduce this dimension for common/precious merchandise; price modifiers come from market_class, demand modifiers, and class_size_adjust, not quality grades.
- **No regional / cultural variant merchandise types** (e.g., "exotic spices from the eastern continent") — the RAW 31 types cover the system. Setting flavor can be applied via display strings, not new types.

---

## §3. Settlement Economy Inputs — Mapping Project Schema to the RAW Six-Step Procedure

### 3.1 Overview

The six-step demand-modifier procedure at `rules/acore-setting-construction-rules.xml:227-234` reads six categories of input per settlement. This section enumerates each, identifies the source of truth in the existing project schema, and locks the project-design mappings where RAW vocabulary doesn't match project vocabulary 1:1.

| RAW step | Input | Source of truth in project | Mapping required |
|---|---|---|---|
| 2 | Age bucket | `settlement_entrances.age_years` (§1) | Bucket derivation (boundary convention in §1.2) |
| 2 | Water source | `hex_cells.water` + `hex_terrain_overlays` (overlay_type='river') | §3.3 derivation |
| 2 | Climate bucket | `hex_cells.biome` + `hex_cells.biome_subtype` | §3.4 mapping table (Q-MERC-2C) |
| 2 | Elevation | `hex_cells.elevation` | §3.5 (trivial) |
| 4 | Domain land revenue | `domain_hexes.land_value` (3-9 gp) | §3.7 aggregation |
| 5 | Dominant race | `settlement_entrances.dominant_race` (§1) | Trivial (direct read) |

Step 1 (base 1d3-1d3 roll), step 3 (drop fractions), and step 6 (trade-route shifts) operate on derived numbers, not raw inputs — they live in §4 (procedure) and §5 (trade routes).

All input-resolution lives behind one read-side service: `engine/subsystems/commerce/settlement_economy_inputs.gd`. It is a pure-function `RefCounted` (not an autoload — too narrow a surface to merit a singleton).

### 3.2 Age bucket derivation

Defined in §1.2. Pure function `SettlementEconomyInputs.age_bucket_for(age_years: int) -> String`. Returns one of `0_20_years`, `21_100_years`, `101_1000_years`, `1001_2000_years`, `2001_plus_years`. Already specified; not repeated here.

### 3.3 Water-source detection

- **RAW citation:** `rules/acore-setting-construction-rules.xml:297-353` env table columns `sea_coast`, `lake_shore`, `river_bank`.
- **What RAW provides:** three water-source columns plus implicit "no water modifier" for landlocked-and-no-river settlements (the column is absent from the table when no water source applies).
- **What's missing:** RAW does not specify what counts as "adjacent" to a sea/lake (one hex away? two?) and does not specify what to do when a settlement is on multiple water sources (coastal river-mouth town).
- **Project resolution:**
  - **`sea_coast`** is `true` if the settlement's hex has `water = 'ocean'` OR any of the six neighboring hexes has `water = 'ocean'`. A 1-hex adjacency rule (`HexMapController.get_neighbors()`).
  - **`lake_shore`** is `true` if any of the following holds:
    - the settlement's hex has `water = 'lake'`, OR
    - any of the six neighboring hexes has `water = 'lake'`, OR
    - the settlement's hex biome is `swamp` (project-design rule per §3.4: swamps act as lake-shore for water-source purposes regardless of actual lake adjacency).
  - **`river_bank`** is `true` if there exists a row in `hex_terrain_overlays` with `overlay_type='river'` AND `(map_id, q, r)` matching the settlement's hex. Rivers are settlement-on-hex only — adjacency does not propagate (a town one hex away from a river is not "on" the river).
  - **Multi-source rule (project-designed; RAW silent):** apply all applicable water modifiers additively. A coastal river-mouth town that meets both `sea_coast` and `river_bank` sums the two columns' per-merchandise modifiers. Rationale: a port at a river mouth realistically benefits from both ocean trade and inland river access; RAW's env-modifier values are not large enough to cause double-counting absurdities.
  - **Settlement with no qualifying water source:** all three flags `false`; water modifier contribution = 0 to every merchandise.

API surface:

```gdscript
class WaterSources:
    var sea_coast: bool
    var lake_shore: bool
    var river_bank: bool

static func resolve_water_sources(settlement_id: String) -> WaterSources
```

### 3.4 Climate bucket mapping (Q-MERC-2C deliverable)

- **RAW citation:** `rules/acore-setting-construction-rules.xml:297-353` env table columns `rainforest`, `savanna`, `desert`, `steppe`, `scrub`, `grasslands`, `deciduous_forest`, `taiga`, `tundra`, `plains` (10 climate buckets).
- **What RAW provides:** 10 distinct climate columns, each contributing per-merchandise modifiers.
- **What's missing:** the project's terrain vocabulary is (biome, biome_subtype) per `engine/shared_types/hex_terrain_data.gd:30-44`. After this GDD lands, the subtype vocabulary extends with `clear_steppe` and `clear_scrub` (project resolution below). The mapping is not 1:1 — some project terrain states map to **multiple** RAW climate columns simultaneously (composite climate), and the resulting per-merchandise modifier is the **sum** of all mapped columns.
- **Project resolution:**
  - The mapping table below. A pure function `SettlementEconomyInputs.climate_columns_for(biome, biome_subtype) -> Array` returns an array of RAW climate column names. The array may have 0, 1, or 2 entries.
  - **Subtypes never change climate columns when they are elevation-rooted.** Per Jedidiah 2026-05-12, all mountain subtypes (`mountains_volcanic`, `mountains_glacial`) inherit climate from the parent biome — the subtype refines elevation/encounter behavior, not climate. The mountains elevation column (§3.5) applies separately and uniformly to all mountain subtypes.
  - **Subtypes that narrow vegetation (`clear_grassland`, `clear_savanna`, `clear_tundra`, `clear_steppe`, `clear_scrub`, `forest_dense`, `forest_taiga`, `desert_badlands`) override the parent biome's default composite with a single, more-specific climate.**
  - **Swamp is a project-design composite.** Per Jedidiah 2026-05-12, swamp = RAW `scrub` climate column PLUS implicit `lake_shore` water-source (the latter handled in §3.3). Together they reproduce the modifier profile RAW would assign to a "wet shrubland" biome that RAW itself does not enumerate.

#### Mapping table

| biome | biome_subtype | → RAW climate column(s) | Rationale |
|---|---|---|---|
| `clear` | (none) | `grasslands` + `plains` | Composite — default temperate open land carries both grassland-like (less-fertile, more nomadic) and plains-like (settled-agricultural) modifiers. Subtypes narrow this. |
| `clear` | `clear_grassland` | `grasslands` | Subtype narrows to dry/nomadic temperate prairie. |
| `clear` | `clear_savanna` | `savanna` | Direct match. |
| `clear` | `clear_tundra` | `tundra` | Direct match. |
| `clear` | `clear_steppe` *(new project subtype)* | `steppe` | Direct match. New subtype added by this GDD; see §3.4.1. |
| `clear` | `clear_scrub` *(new project subtype)* | `scrub` | Direct match. New subtype added by this GDD; see §3.4.1. |
| `clear` | `mountains_volcanic` | `grasslands` + `plains` | Inherit climate from clear (mountain subtype refines elevation/encounter only). |
| `clear` | `mountains_glacial` | `grasslands` + `plains` | Inherit climate from clear. |
| `woods` | (none) | `deciduous_forest` | Default temperate woodland — single column. |
| `woods` | `forest_dense` | `deciduous_forest` | Density refines encounters, not climate. |
| `woods` | `forest_taiga` | `taiga` | Direct match. |
| `woods` | `mountains_volcanic` | `deciduous_forest` | Inherit from woods. |
| `jungle` | (none) | `rainforest` | Direct match (confirmed Jedidiah 2026-05-12). |
| `jungle` | `mountains_volcanic` | `rainforest` | Inherit from jungle. |
| `swamp` | (none) | `scrub` | Project composite — see §3.4.2. Also implies `lake_shore` water source (§3.3). |
| `swamp` | `mountains_volcanic` | `scrub` | Inherit from swamp; lake_shore implication preserved. |
| `desert` | (none) | `desert` | Direct match — hot arid. |
| `desert` | `desert_badlands` | `desert` | Badlands subtype refines movement/encounters, not climate. |
| `desert` | `mountains_volcanic` | `desert` | Inherit. |
| `desert` | `mountains_glacial` | `desert` | Inherit. (A Judge wanting a cold-high-desert to behave climatically as tundra may use `climate_override`.) |

#### 3.4.1 Adding `clear_steppe` and `clear_scrub` to the biome_subtype vocabulary

Per Jedidiah 2026-05-12: the RAW climate buckets `steppe` and `scrub` need procedural sources in the project terrain vocabulary. Two new subtypes are added: `clear_steppe` and `clear_scrub`. Both have:

- `parent_biome`: `clear`
- `allowed_elevations`: `[flat, hills]` (steppe and scrub are open lowlands/hill country, not mountainous)
- `allowed_biomes`: `[clear]`

**Migration impact (amends §1.4 migration plan):** the `biome_subtype` CHECK constraint on `hex_cells` (per `db/migrations/092_hex_biome_subtype.sql`) must be extended to include the two new values. SQLite cannot ALTER an existing CHECK constraint in place; the migration uses the standard table-rewrite pattern (create temp, copy, drop, rename, restore indexes) wrapped in a transaction. Migration 097's sub-step list (originally three ADD COLUMN + one DROP COLUMN) extends to include this CHECK-constraint rewrite.

**Out-of-scope follow-up tasks** (not part of this GDD but required for the new subtypes to be fully usable):

1. **`engine/shared_types/hex_terrain_data.gd`** — add `SUBTYPE_CLEAR_STEPPE := "clear_steppe"` and `SUBTYPE_CLEAR_SCRUB := "clear_scrub"` constants, plus their entries in `SUBTYPE_PROFILES` (with the constraints above), plus appropriate refinement behavior in `movement_cost_category()`, `encounter_distance_dice()`, `creature_type_tilt()`, etc.
2. **`generation/gdd-terrain-system.md` §3.4** — document the two new subtypes (paired flavor description, parent biome, elevation constraints, RAW column mapping back to this GDD).
3. **Encounter tables** — the wilderness encounter table system needs steppe and scrub coverage. Whichever phase ships the next encounter-table extension picks this up.

The mercantile prereq session executes the migration's CHECK-constraint rewrite. The HexTerrainData / terrain-GDD / encounter-table updates are documented as deferred follow-ups; the **demand-modifier system functions correctly without those updates being shipped first** because climate lookup is data-driven by the (biome, biome_subtype) pair, and the lookup returns `[steppe]` or `[scrub]` whether or not the HexTerrainData class knows about the new subtype.

#### 3.4.2 Swamp climate composite

- **What RAW provides:** no `swamp` column in the env-adjustments table. RAW treats swamps as a hex-encounter-table concern, not an environmental-economy concern.
- **What's missing:** swamp settlements need *some* climate modifier profile that captures their distinctive economic character (wet, vegetation-rich, hostile-to-agriculture but rich in monster parts and hides).
- **Project resolution:** swamp climate = `scrub` column modifiers + `lake_shore` water-source modifiers. The two together approximate "wet shrubland" — a derived bucket RAW would have authored if it had needed one.
- **No literal new column is added to any data file.** The env-adjustments JSON keeps the 20 RAW columns verbatim per §2 sign-off. The composite is computed at runtime by (a) returning `scrub` from `climate_columns_for(swamp, ...)`, and (b) forcing `lake_shore=true` in the water-source resolution (§3.3).

The same approach (composite via runtime sum, not via data-file extension) keeps the rules data files untouched — preserving the sacred-rules policy and Q-MERC-1A's XML-as-canonical guarantee.

#### 3.4.3 What §3.4 stops short of

The mapping above resolves the eight straightforward cases plus the swamp composite, plus the new clear_steppe / clear_scrub direct matches. **All 10 RAW climate columns are now procedurally reachable.** The `climate_override` column (§3.9) remains useful for Judge overrides where setting-flavor demands a non-default mapping (e.g., a specific tropical port that should behave climatically as `savanna` despite sitting on a `clear` hex).

Jedidiah's note 2026-05-12: "we may need to do more in-depth sorting of demand modifiers vs project biomes." This GDD acknowledges that the composite-mapping rule is a v1 calibration; if playtest reveals that `clear → grasslands + plains` produces unrealistic modifier sums, the mapping can be revisited without changing this section's structure (just retune which columns are listed).

### 3.5 Elevation extraction

- **RAW citation:** `rules/acore-setting-construction-rules.xml:297-353` env table columns `hills` and `mountains`.
- **What RAW provides:** two elevation columns. The implicit third state ("flat") contributes no modifier.
- **What's missing:** nothing — the project's elevation vocabulary (`flat | hills | mountains`) is a 1:1 match.
- **Project resolution:** pure function `SettlementEconomyInputs.elevation_bucket_for(elevation: String) -> String`. Returns `"hills"`, `"mountains"`, or `""` (sentinel for flat = no modifier).

### 3.6 Dominant race lookup

Trivial direct read of `settlement_entrances.dominant_race` (§1). The racial-adjustment table at `rules/acore-setting-construction-rules.xml:253-262` applies fixed -2 modifiers to specific merchandise types when the value is `dwarf` or `elf`; all other values (including the default `human`) contribute zero racial adjustment.

```gdscript
static func resolve_dominant_race(settlement_id: String) -> String
    # Returns 'human', 'dwarf', 'elf', or whatever campaign-specific value is stored.
```

The racial-adjustment table itself is encoded in §4 (with the procedure that consumes it), not here. This section just exposes the input.

### 3.7 Domain land revenue lookup

- **RAW citation:** `rules/acore-setting-construction-rules.xml:237-251` `domain_land_revenue_to_demand_modifiers` table, indexed by gp 3-9.
- **What RAW provides:** lookup table indexed by single integer 3-9 specifying how many merchandise types receive +1 or -1 modifiers. RAW treats "domain land revenue" as a single-number property of the domain (not the settlement).
- **What's missing:** the project stores `land_value` per hex (`domain_hexes.land_value`, with CHECK 3-9). A domain spans multiple hexes; a single domain-level land revenue must be derived.
- **Project resolution:**
  - For each settlement with a non-null `parent_domain_id`, the domain's effective land revenue per family is `round_banker(AVG(land_value))` across all `domain_hexes` rows where the `domain_id` matches. The result is clamped to `[3, 9]` (defensive — should already be in range per the column CHECK).
  - For settlements with `parent_domain_id IS NULL`: default to 5 (mid-scale). This is the "wilderness settlement, no domain context" fallback. Setting-generation should be giving every settlement a parent_domain, but the fallback prevents crashes.
  - Caching: this average changes only when domain hexes change (surveys, improvements). Compute on-demand for v1; if the procedure becomes a hot path, add a cached column to `domains` later.

API surface:

```gdscript
static func resolve_domain_land_revenue(settlement_id: String) -> int
    # Returns integer in [3, 9].
```

#### Project-design ledger — peasant_families vs urban_families

RAW's domain_land_revenue mechanic operates on a per-peasant-family basis (since urban families don't farm). This GDD does NOT change how peasant_families are tracked — they remain on `domains.peasant_families` (per current schema). Land revenue × peasant_families = the gross domain land revenue; the *per-family* number is what RAW's step 4 lookup uses, and that is the `domain_hexes.land_value` average above. The urban_families relocation in §1 does not affect this calculation.

### 3.8 The `SettlementEconomyInputs` service

`engine/subsystems/commerce/settlement_economy_inputs.gd` — a `RefCounted` aggregator (not autoloaded; instantiated by the demand-modifier procedure when it runs).

**Public surface:**

```gdscript
class_name SettlementEconomyInputs
extends RefCounted

# Per-input pure-function lookups
static func age_bucket_for(age_years: int) -> String
static func climate_columns_for(biome: String, biome_subtype: String) -> Array
    # Returns an Array[String] of RAW climate column names. May be:
    #   []  → no climate contribution (e.g., unmapped exotic biome)
    #   [name]  → single column (e.g., ["taiga"], ["rainforest"])
    #   [name1, name2]  → composite (e.g., ["grasslands", "plains"] for clear default)
    # Procedure sums per-merchandise modifiers across all returned columns.
static func elevation_bucket_for(elevation: String) -> String

# Per-settlement database-backed lookups
static func resolve_water_sources(settlement_id: String) -> Dictionary
    # Returns {"sea_coast": bool, "lake_shore": bool, "river_bank": bool}
    # Note: swamp-biome settlements have lake_shore forced true per §3.3.
static func resolve_dominant_race(settlement_id: String) -> String
static func resolve_domain_land_revenue(settlement_id: String) -> int

# Aggregator (called by the demand-modifier procedure in §4)
static func resolve_all(settlement_id: String) -> Dictionary
    # Returns a single dict containing every input field:
    # {
    #   "age_bucket": String,
    #   "water_sources": Dictionary,  # see resolve_water_sources
    #   "climate_columns": Array,     # see climate_columns_for; may be [], 1, or 2 entries
    #   "climate_override": String,   # non-empty wins; replaces climate_columns with [override]
    #   "elevation_bucket": String,
    #   "dominant_race": String,
    #   "domain_land_revenue": int,
    # }
```

The aggregator `resolve_all()` is the canonical entry point. The demand-modifier procedure (§4) calls it once per settlement per generation pass; the procedure does not query the database for individual inputs.

### 3.9 `climate_override` schema addition (amends §1's migration plan)

A 4th column is added to `settlement_entrances` in migration 097:

```sql
ALTER TABLE settlement_entrances ADD COLUMN climate_override TEXT NOT NULL DEFAULT '';
```

- **Why a 4th column:** all 10 RAW climate buckets are now procedurally reachable via the §3.4 mapping (after the `clear_steppe` and `clear_scrub` subtypes are added). The override is still useful for:
  - Judge-authored setting flavor where the derived climate isn't the desired one (e.g., a magical jungle-island that should behave climatically as `savanna` per setting lore).
  - Future-proofing: if RAW or a Player's Companion adds new climate vocabulary, an override column means we don't have to migrate the schema again.
- **Allowed values:** any of the 10 RAW climate names: `rainforest`, `savanna`, `desert`, `steppe`, `scrub`, `grasslands`, `deciduous_forest`, `taiga`, `tundra`, `plains`. Or `""` (default — derive from biome+subtype).
- **No CHECK constraint at SQL layer.** The string must validate at write time in GDScript (similar pattern to `biome_subtype`'s in-GD validation per migration 092). Future tightening to a CHECK is straightforward.
- **Default:** empty string. Existing rows post-migration have `climate_override = ''` and continue to derive climate from biome+subtype.
- **Resolution order in `resolve_all()`:** if `climate_override` is non-empty, the returned `climate_columns` array becomes exactly `[climate_override]` (single-column, replacing any composite the biome+subtype mapping would have produced); otherwise it's `climate_columns_for(biome, biome_subtype)`.

The aggregator collapses the override + derivation so consumers (§4) don't have to know which path was used. The override value is also exposed separately for audit / UI purposes.

**Amendment to §1.4 migration steps:**

The original §1.4 plan had 5 sub-steps. With §3.4's `biome_subtype` CHECK extension and this section's `climate_override` column, the revised migration 097 sub-step list is:

1. `ALTER TABLE settlement_entrances ADD COLUMN age_years INTEGER NOT NULL DEFAULT 500;`
2. `ALTER TABLE settlement_entrances ADD COLUMN dominant_race TEXT NOT NULL DEFAULT 'human';`
3. `ALTER TABLE settlement_entrances ADD COLUMN urban_families INTEGER NOT NULL DEFAULT 0;`
4. `ALTER TABLE settlement_entrances ADD COLUMN climate_override TEXT NOT NULL DEFAULT '';`
5. Data-move: `UPDATE settlement_entrances SET urban_families = (SELECT urban_families FROM domains WHERE id = settlement_entrances.parent_domain_id) WHERE parent_domain_id IS NOT NULL;`
6. Drop `domains.urban_families` (table-rewrite or `DROP COLUMN` per SQLite version, per §1.4).
7. **Table-rewrite on `hex_cells`** to extend the `biome_subtype` CHECK constraint to include `clear_steppe` and `clear_scrub`. Standard pattern: create `hex_cells_new` with the new CHECK, `INSERT INTO hex_cells_new SELECT ... FROM hex_cells`, `DROP TABLE hex_cells`, `ALTER TABLE hex_cells_new RENAME TO hex_cells`, recreate indexes.

All seven steps wrap in a single transaction. The migration runner rolls back if any step fails.

### 3.10 Tests

`tests/test_settlement_economy_inputs.gd` budget: **~15 tests** (in addition to §1's ~10 schema tests, which live in the same file).

1. **Age bucket boundaries** — already counted in §1.8 (5 tests there).
2. **Climate columns: single-column cases.** `climate_columns_for("woods", "")` → `["deciduous_forest"]`; `("jungle", "")` → `["rainforest"]`; `("desert", "")` → `["desert"]`; `("woods", "forest_taiga")` → `["taiga"]`.
3. **Climate columns: composite `clear` default.** `climate_columns_for("clear", "")` → `["grasslands", "plains"]` (order-insensitive assert).
4. **Climate columns: narrowing subtypes.** `("clear", "clear_grassland")` → `["grasslands"]`; `("clear", "clear_steppe")` → `["steppe"]`; `("clear", "clear_scrub")` → `["scrub"]`.
5. **Climate columns: swamp composite.** `("swamp", "")` → `["scrub"]` (the implicit `lake_shore` water source is verified separately in test 9).
6. **Climate columns: mountain-subtype inheritance.** `("clear", "mountains_volcanic")` → `["grasslands", "plains"]`; `("desert", "mountains_glacial")` → `["desert"]`; `("jungle", "mountains_volcanic")` → `["rainforest"]`. (Climate inheritance through mountain subtypes per §3.4.)
7. **Climate override replaces composite.** Settlement with biome=clear, subtype=none (would yield `[grasslands, plains]`), `climate_override='steppe'` → `resolve_all()` returns `climate_columns = ["steppe"]`.
8. **Water source: ocean-on-hex and adjacency.** Hex with `water='ocean'` → `sea_coast=true`. Adjacent-hex with ocean neighbor → `sea_coast=true`. Two-away from ocean → `sea_coast=false`.
9. **Water source: swamp implies lake_shore.** Swamp-biome settlement with no actual lake adjacent → `lake_shore=true`. Same swamp with an adjacent lake → still `lake_shore=true` (no double-counting; boolean union).
10. **Water source: river overlay.** Settlement on a hex with a river overlay → `river_bank=true`. Adjacent-to-river-but-not-on → `river_bank=false`.
11. **Water source: multi-source.** Coastal river-mouth (ocean hex + river overlay) → `sea_coast=true, river_bank=true`.
12. **Elevation: flat → empty sentinel.** `elevation_bucket_for('flat') == ''`; `'hills'` → `'hills'`; `'mountains'` → `'mountains'`.
13. **Domain land revenue averaging.** Fixture: domain with three hexes (land_value 3, 5, 7) → resolve returns 5. Banker's rounding: domain with hexes (3, 4) → average 3.5 → 4 (rounds to even). Domain with hexes (4, 5) → 4.5 → 4 (rounds to even).
14. **Domain land revenue: no parent domain.** Settlement with `parent_domain_id IS NULL` → 5 (fallback).
15. **`resolve_all()` aggregator end-to-end.** Build a settlement (biome=clear, subtype=clear_grassland, age=750, race=dwarf, parent_domain with land_values [4, 5, 6], adjacent ocean hex, no climate_override) → `resolve_all()` returns the expected dict: age_bucket='101_1000_years', climate_columns=['grasslands'], climate_override='', elevation_bucket='', water_sources={sea_coast: true, lake_shore: false, river_bank: false}, dominant_race='dwarf', domain_land_revenue=5.

### 3.11 What §3 does NOT add

- **No water_source schema column.** The three flags are computed on demand from existing `hex_cells` + `hex_terrain_overlays` data (plus the swamp-implies-lake_shore rule). No caching column is added because the inputs change so rarely (rivers don't reroute, coastlines don't shift mid-campaign) that on-demand resolution is fine. If profiling shows it's a hot path, add a cached column later.
- **No `domain_land_revenue` cached column on settlements.** Same reasoning: changes only when hex land_values change (surveys / improvements). Compute on-demand.
- **No `peasant_families` relocation.** Peasant families stay on `domains` — they are domain-level (the rural population is distributed across the domain's hexes, not concentrated in a settlement), unlike urban_families which we moved to settlements in §1.
- **No encounter-table additions for `clear_steppe` / `clear_scrub`.** The new subtypes are added to the terrain *vocabulary* (CHECK constraint + climate mapping) by this GDD, but the encounter tables that the wilderness encounter resolver consults are not extended here. Whichever phase ships the next encounter-table update picks this up; until then, steppe/scrub hexes fall back to their parent biome's encounter table (clear).
- **No `HexTerrainData.SUBTYPE_PROFILES` extension.** Listed as an out-of-scope follow-up in §3.4.1. The demand-modifier system works without it (since climate lookup is data-driven by the (biome, biome_subtype) tuple); the HexTerrainData extension is needed for the new subtypes to fully participate in encounter resolution, movement cost calculation, and navigation TN logic.

---

## §4. The RAW Six-Step Demand-Modifier Generation Procedure

### 4.0 Overview

This section encodes the six-step procedure at `rules/acore-setting-construction-rules.xml:227-234` that generates per-settlement, per-merchandise-type demand modifiers. The output is one integer per (settlement, merchandise_type) pair — 31 entries per settlement, cached in the new `settlement_merchandise_demand` table.

The procedure runs once per settlement at generation time and again only when an input parameter changes (Q-MERC-6 [RESOLVED 2026-05-12]). It is NOT a per-transaction step. The market-price formula in §6 reads the cached demand modifier; nothing else touches it.

Step 6 (trade-route shifts) is operationally distinct because it requires *multi-settlement* awareness (the regional walk in §5). Steps 1-5 produce a *raw* demand modifier per settlement; §5 then performs the region-wide shift pass that finalizes the values. The cache table records the post-shift values.

#### 4.0.1 Terrain-canon defer note

Per the 2026-05-12 decision to defer terrain harmonization, the demand-modifier generator anchors on §3.4's v1 climate mapping. **Wherever §4's logic commits to a semantic interpretation of a §3.4 mapping decision (the `clear → [grasslands, plains]` composite, the swamp `[scrub] + lake_shore` composite, mountain-subtype climate inheritance), the implementation will carry a `# [NEEDS-TERRAIN-CANON-REWORK]` source-code comment.** The terrain-canon session can grep these flags and audit them in one pass when it runs. The generator itself is data-driven through §3's `SettlementEconomyInputs`, so a future remapping requires no code changes here.

### 4.1 Step 1 — Base 1d3-1d3 roll

- **RAW citation:** `rules/acore-setting-construction-rules.xml:228` step 1.
- **What RAW provides:** "For each merchandise type, roll 1d3-1d3 to generate a base demand modifier from -2 to +2."
- **Project resolution:** for each of the 31 merchandise types, roll `(1d3) - (1d3)`. Range: -2 to +2 (5 outcomes; probability distribution centered on 0). RNG is seeded — see §4.9 for determinism.

Pure-function shape:

```gdscript
static func step_1_base_roll(rng: RandomNumberGenerator) -> int:
    return rng.randi_range(1, 3) - rng.randi_range(1, 3)
```

### 4.2 Step 2 — Environmental adjustments

- **RAW citation:** `rules/acore-setting-construction-rules.xml:229` step 2 + the env-adjustments table at L297-353.
- **What RAW provides:** for each merchandise type at this settlement, sum the modifier values from the env-adjustments table for every applicable column. Columns come from four input groups (one age column, zero or more water-source columns, one or more climate columns, zero or one elevation columns).
- **What's missing (already resolved in §3):** the mapping from project terrain vocabulary to RAW columns. §3 produces the `climate_columns` array and water-source booleans.
- **Project resolution:** for each merchandise type, the contribution from step 2 is the **sum** of:
  1. The age-bucket column value (exactly one column applies — age buckets are mutually exclusive).
  2. The water-source column values (zero, one, two, or three of `sea_coast`, `lake_shore`, `river_bank` may apply — sum them all). Per §3.3's multi-source rule and swamp's lake_shore implication.
  3. The climate-column values (one or two columns from the §3.4 composite mapping — sum them all).
  4. The elevation-column value (exactly one of `hills`, `mountains`, or none — sum it if present).

Modifier values are halves (multiples of 0.5). The intermediate sum is a float; fraction-dropping happens in step 3.

```gdscript
static func step_2_environmental(
    base: int,
    inputs: Dictionary,       # from SettlementEconomyInputs.resolve_all()
    merchandise_type: String,
    env_table: Dictionary,    # loaded from data/commerce/environmental_adjustments.json
) -> float:
    var total: float = float(base)
    var row: Dictionary = env_table.get(merchandise_type, {})
    if row.is_empty():
        return total
    # Age (one column)
    total += row.get("age", {}).get(inputs["age_bucket"], 0.0)
    # Water (zero to three columns)
    var water: Dictionary = inputs["water_sources"]
    if water["sea_coast"]:
        total += row.get("water_source", {}).get("sea_coast", 0.0)
    if water["lake_shore"]:
        total += row.get("water_source", {}).get("lake_shore", 0.0)
    if water["river_bank"]:
        total += row.get("water_source", {}).get("river_bank", 0.0)
    # Climate (one or two columns from the §3.4 composite)
    for column in inputs["climate_columns"]:  # [NEEDS-TERRAIN-CANON-REWORK]
        total += row.get("climate", {}).get(column, 0.0)
    # Elevation (zero or one column)
    var elev: String = inputs["elevation_bucket"]
    if elev != "":
        total += row.get("elevation", {}).get(elev, 0.0)
    return total
```

#### 4.2.1 `data/commerce/environmental_adjustments.json` schema

The JSON is encoded directly from the canonical XML at `rules/acore-setting-construction-rules.xml:297-353` (corrected via Q-MERC-1A). One entry per merchandise type:

```json
{
  "version": 1,
  "source": "rules/acore-setting-construction-rules.xml:297-353 (Environmental Adjustments to Demand, post-Q-MERC-1A correction)",
  "entries": {
    "grain_vegetables": {
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
    },
    ...
  }
}
```

31 entries (matching §2.8 alignment). The encoding pass cross-checks every value against `rules/acore-setting-construction-rules.xml:297-353`; the `?? Verify` flags in `docs/phase-10b-prereq-environmental-adjustments-table.md` get a final PDF re-check before committing.

### 4.3 Step 3 — Drop fractions

- **RAW citation:** `rules/acore-setting-construction-rules.xml:230` step 3.
- **What RAW provides:** "After applying environmental modifiers, drop any fractions."
- **What's missing:** RAW says "drop" not "round." The two are different operations for negative numbers (drop -1.5 → -1; round -1.5 → -2 banker's, or -2 half-up).
- **Project resolution:** **truncate toward zero** (drop the fractional part). `int(1.5) → 1`; `int(-1.5) → -1`; `int(0.5) → 0`; `int(-0.5) → 0`. **This is a deliberate exception to CLAUDE.md's banker's-rounding rule** — RAW prescribes a specific operation ("drop fractions") and we honor it. The exception is narrowly scoped to this step; all other RAW-silent rounding decisions in this GDD use banker's rounding.

```gdscript
static func step_3_drop_fractions(value: float) -> int:
    return int(value)  # Godot int() truncates toward zero
```

#### 4.3.1 Why this isn't a banker's-rounding bug

The semantic of "drop fractions" in RAW is "convert to integer by discarding the decimal." A negative-value example: a merchandise with summed environmental modifier -0.5 has a *small* negative environmental influence. Truncating to 0 yields "no environmental adjustment from this source" — which matches the RAW intuition that "drop the fraction" zeros out small fractional pressures. Banker's rounding would push -0.5 to 0 also (since -0 is the even neighbor), but +0.5 would push to 0 too, so for this specific operation the two are nearly identical in effect. The deviation only matters at 1.5 / -1.5 / 2.5 / -2.5: truncation gives 1 / -1 / 2 / -2; banker's gives 2 / -2 / 2 / -2. For our purposes the truncation reading is RAW-faithful.

### 4.4 Step 4 — Domain land-revenue adjustment

- **RAW citation:** `rules/acore-setting-construction-rules.xml:231` step 4 + the `domain_land_revenue_to_demand_modifiers` table at L237-251.
- **What RAW provides:** at land revenue X gp/family (range 3-9), apply +1 to N merchandise types and -1 to M merchandise types, per the table:

| land_revenue | +1 count | -1 count |
|---|---|---|
| 3 | 6 | 1 |
| 4 | 4 | 1 |
| 5 | 2 | 1 |
| 6 | 1 | 1 |
| 7 | 1 | 2 |
| 8 | 1 | 4 |
| 9 | 1 | 6 |

- **What's missing:** RAW gives the *counts* but does not specify *which* merchandise types receive the +1 / -1. This is the most consequential project-design gap in the entire procedure.
- **Project resolution:** deterministic seeded shuffle. Each settlement's land-revenue distribution is computed once with a stable seed (`settlement.id` hashed with `land_revenue` as a salt) and stored on the cache row. The distribution stays stable until land_revenue or settlement.id changes; then it's re-rolled deterministically.

Algorithm:

```gdscript
static func step_4_apply_domain_land_revenue(
    base_modifiers: Dictionary,     # {merchandise_type: int}
    land_revenue: int,              # 3-9 (clamped per §3.7)
    settlement_id: String,          # for seed derivation
) -> Dictionary:
    var table := {
        3: {"plus": 6, "minus": 1},
        4: {"plus": 4, "minus": 1},
        5: {"plus": 2, "minus": 1},
        6: {"plus": 1, "minus": 1},
        7: {"plus": 1, "minus": 2},
        8: {"plus": 1, "minus": 4},
        9: {"plus": 1, "minus": 6},
    }
    var counts: Dictionary = table.get(land_revenue, {"plus": 0, "minus": 0})
    var all_types: Array = base_modifiers.keys()  # 31 entries
    var rng := RandomNumberGenerator.new()
    rng.seed = _hash_seed(settlement_id, land_revenue, "land_revenue_dist")
    _deterministic_shuffle(all_types, rng)
    # Apply +1 to first N types in the shuffled list; -1 to next M.
    for i in counts["plus"]:
        base_modifiers[all_types[i]] += 1
    for i in counts["minus"]:
        base_modifiers[all_types[counts["plus"] + i]] -= 1
    return base_modifiers
```

#### 4.4.1 Why deterministic shuffle vs. semantic selection

Two alternatives were considered:

- **Semantic selection:** categorize merchandise as `agricultural_staple`, `manufactured_good`, `luxury`, `exotic` and weight the +1/-1 picks based on what makes economic sense at each land-revenue level (e.g., at 3 gp the +1s favor staples since the domain is import-dependent for basic goods; at 9 gp the -1s favor staples since the productive land oversupplies them). More flavorful but introduces another project-designed categorization on top of the 31 RAW merchandise types.
- **Pure random per generation:** different result every time the procedure runs. Breaks Q-MERC-6's "regenerate only when inputs change" invariant — a settlement's demand modifiers would shift every time the cache invalidated, even if inputs didn't actually move.

Deterministic shuffle hits the sweet spot: stable, no semantic claims, simple to test. If playtest reveals the random distribution produces consistently weird results (e.g., a desert domain at 5 gp gets +1 on "fish, preserved" by accident, which feels narratively wrong), the semantic-selection upgrade can be retrofitted without changing the cache schema or the procedure signature — just swap the implementation of step 4.

`[NEEDS-FLAVOR-PASS]` source-code flag added at step_4 implementation. Future polish.

#### 4.4.2 Seed derivation

```gdscript
static func _hash_seed(settlement_id: String, salt_int: int, salt_str: String) -> int:
    # Combines settlement_id (TEXT PK) with an integer salt and a string-tag
    # salt to produce a stable int seed. Using Godot's hash().
    return hash(settlement_id + "|" + str(salt_int) + "|" + salt_str)
```

This way, the same step using the same inputs in different `RandomNumberGenerator` instances reproduces. Tests can pin specific seeds and verify expected distributions.

### 4.5 Step 5 — Racial adjustment

- **RAW citation:** `rules/acore-setting-construction-rules.xml:232` step 5 + the `racial_adjustments_to_demand` table at L253-262.
- **What RAW provides:** Dwarf settlements receive -2 to specific merchandise types; Elf settlements receive -2 to specific merchandise types. The lists are fixed.
- **What's missing:** nothing — the table is a flat lookup.
- **Project resolution:** flat application of the table values.

```gdscript
const RACIAL_ADJUSTMENT_TABLE := {
    "dwarf": {
        "beer_ale": -2,
        "metals_common": -2,
        "tools": -2,
        "armor_weapons": -2,
        "metals_precious": -2,
        "semiprecious_stones": -2,
        "gems": -2,
    },
    "elf": {
        "wood_common": -2,
        "dye_pigments": -2,
        "cloth": -2,
        "glassware": -2,
        "porcelain_fine": -2,
    },
}

static func step_5_apply_racial_adjustment(
    base_modifiers: Dictionary,
    dominant_race: String,
) -> Dictionary:
    var adjustments: Dictionary = RACIAL_ADJUSTMENT_TABLE.get(dominant_race, {})
    for merch_type in adjustments:
        if base_modifiers.has(merch_type):
            base_modifiers[merch_type] += adjustments[merch_type]
    return base_modifiers
```

Settlements with `dominant_race='human'` (or any value not in the table) receive zero racial adjustment.

**Why hard-coded vs. JSON:** the racial adjustment table is fixed by RAW (5-7 entries per race, two races). It is small enough and stable enough that an in-code constant is more readable than yet another JSON file. If future Player's Companion releases add racial adjustment for halflings / gnomes / etc., they get appended here.

### 4.6 Step 6 — Trade-route shifts

Deferred to **§5** (Trade Route Detection and Regional Demand Resolution). Step 6 requires multi-settlement awareness and a region-walk algorithm that doesn't fit inside the per-settlement generator. §4's output is the *pre-shift* demand modifier; §5's region resolver applies the shifts and writes the final values to the cache.

### 4.7 The `settlement_merchandise_demand` cache table

New table, migration 097 (final sub-step):

```sql
CREATE TABLE IF NOT EXISTS settlement_merchandise_demand (
    settlement_entrance_id        TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type              TEXT    NOT NULL,
    demand_modifier               INTEGER NOT NULL DEFAULT 0,
    generated_at_calendar_day     INTEGER NOT NULL DEFAULT 0,
    source_kind                   TEXT    NOT NULL DEFAULT 'generated'
        CHECK(source_kind IN ('generated', 'manual')),
    pre_trade_route_shift_value   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (settlement_entrance_id, merchandise_type)
);
CREATE INDEX idx_smd_settlement ON settlement_merchandise_demand(settlement_entrance_id);
```

**Field rationale:**

- `(settlement_entrance_id, merchandise_type)` composite PK — 31 rows per settlement.
- `demand_modifier`: the FINAL value after all six steps (including §5's trade-route shifts).
- `pre_trade_route_shift_value`: the value after steps 1-5 but BEFORE step 6. Stored so §5's region walk can be re-run on trade-route topology change without re-running steps 1-5.
- `source_kind`: `'generated'` for procedural output; `'manual'` if a Judge has manually overridden a specific (settlement, merchandise) pair via tooling. Manual rows are NOT touched by regeneration — they stick until explicitly reset to `'generated'`.
- `generated_at_calendar_day`: when this row was last computed. Used for debug / audit — not consulted by the procedure itself.

Migration 097 adds this table as its 8th sub-step (after the `hex_cells` CHECK rewrite from §3.4.1).

### 4.8 Cache regeneration triggers

The cache is *passive*: it stores precomputed values and is read by the price resolver, fee calculator, and persuade-merchants reaction-roll. Regeneration happens at explicit trigger points only.

**Trigger 1 — settlement creation.** When a new settlement_entrance row is INSERTed, generate all 31 demand-modifier rows. EventBus signal: `settlement_created(settlement_id)`. Listener: `DemandModifierGenerator.generate_for_settlement(settlement_id)`.

**Trigger 2 — settlement input change.** Any of the following emit `settlement_economy_inputs_changed(settlement_id, reason)`:
- `age_years` updated (typically on the monthly tick when calendar drift advances age; the listener checks whether the *bucket* actually changed before regenerating).
- `dominant_race` updated (rare; setting-generation or specific scripted events).
- `climate_override` updated (Judge action).
- `parent_domain_id` updated (rare; domain conquest).
- Any of the settlement's hex tags change (biome / biome_subtype / water / elevation — extremely rare; world-changing events).
- The river overlay on the settlement's hex changes (extremely rare).

**Trigger 3 — domain land revenue change.** When `domain_hexes.land_value` changes (surveys, improvements) for a hex within a domain that contains settlements, all settlements in that domain regenerate. EventBus signal: `domain_land_value_changed(domain_id)`.

**Trigger 4 — trade route topology change.** When a road overlay is added/removed or a settlement is created/destroyed near existing trade routes, the regional demand resolver in §5 re-runs (not just step 6 — it touches all settlements in the affected region). EventBus signal: `trade_route_topology_changed(region_anchor_settlement_id)`. Listener invokes §5's region walk.

**Manual overrides preserved.** Any row with `source_kind='manual'` is skipped on regeneration. A Judge who has authored a specific demand modifier keeps it.

### 4.9 RNG seeding and determinism

The procedure is deterministic given (settlement_id, inputs). The same inputs always yield the same demand modifiers. This is essential for:

- **Save / load.** A loaded campaign sees the same prices as when it was saved.
- **Testing.** Test fixtures with pinned inputs produce predictable outputs.
- **Audit.** A Judge investigating "why does this settlement have +2 silk demand?" can re-run the procedure and trace the contributions.

**Master seed derivation per generation:**

```gdscript
master_seed = hash(settlement_id + "|" + str(generation_calendar_day))
```

Where `generation_calendar_day` is read from a `last_input_change_calendar_day` field that's bumped whenever a trigger fires (so the seed shifts when inputs change). Storage: a single `INTEGER NOT NULL DEFAULT 0` column on `settlement_entrances` named `economy_inputs_changed_day`. Added as the 9th migration-097 sub-step.

Wait — re-stating the migration sub-step count: §1 had 5, §3 added 2 more (climate_override + biome_subtype CHECK rewrite), §4 adds 2 more (settlement_merchandise_demand table + economy_inputs_changed_day column on settlement_entrances). Migration 097 now has **9 sub-steps** wrapped in a single transaction. If at any point the transaction becomes unwieldy, §14's migration plan can split it across 097a / 097b / 097c, but the dependency graph allows a single transaction.

Inside each step, an RNG instance is initialized from the master seed plus a step-specific salt:

```gdscript
var step_1_rng := RandomNumberGenerator.new()
step_1_rng.seed = hash(master_seed_str + "|step_1_base_roll")

var step_4_rng := RandomNumberGenerator.new()
step_4_rng.seed = hash(master_seed_str + "|step_4_land_revenue_distribution")
```

Step-specific salts prevent correlation: an RNG advanced for step 1's rolls would otherwise consume entropy that step 4's shuffle depends on, making the two steps non-independent in subtle ways.

### 4.10 `DemandModifierGenerator` service API

`engine/subsystems/commerce/demand_modifier_generator.gd` — `RefCounted` static-function library (not autoloaded).

```gdscript
class_name DemandModifierGenerator
extends RefCounted

# Main entry point — runs steps 1-5; the region resolver (§5) calls this then
# applies step 6 across the affected region.
static func generate_for_settlement(settlement_id: String) -> Dictionary
    # Returns {merchandise_type: int} for all 31 types (PRE-trade-route-shift).
    # Writes the result into settlement_merchandise_demand with source_kind='generated'
    # and pre_trade_route_shift_value = the value. Caller (region resolver) updates
    # demand_modifier after step 6.

# Pure-function step implementations (each accepting an RNG for testability)
static func step_1_base_roll(rng: RandomNumberGenerator) -> int
static func step_2_environmental(base: int, inputs: Dictionary, merch: String, env_table: Dictionary) -> float
static func step_3_drop_fractions(value: float) -> int
static func step_4_apply_domain_land_revenue(base: Dictionary, land_revenue: int, settlement_id: String) -> Dictionary
static func step_5_apply_racial_adjustment(base: Dictionary, dominant_race: String) -> Dictionary

# Cache reads (consumed by §6 market_price_resolver, §9 fees, etc.)
static func get_demand_modifier(settlement_id: String, merchandise_type: String) -> int
static func get_all_demand_modifiers(settlement_id: String) -> Dictionary

# Cache writes (manual override path)
static func set_manual_demand_modifier(settlement_id: String, merchandise_type: String, value: int) -> bool

# Regeneration trigger entrypoint
static func regenerate(settlement_id: String) -> void
    # Wraps generate_for_settlement + invokes §5's region resolver.
```

### 4.11 Tests

`tests/test_demand_modifier_generator.gd` budget: **~18 tests.**

**Step-isolation tests (pure functions):**

1. **Step 1 distribution.** Run `step_1_base_roll` 10000 times with a fixed RNG; assert the histogram has ~5/9 zeros, ~3/9 ±1s, ~1/9 ±2s (1d3-1d3 probabilities).
2. **Step 2 single-column.** Fixture: settlement with biome=woods/subtype=forest_taiga (climate=[taiga]), age=500, no water, elevation=flat. For merchandise=grain_vegetables, step 2 returns `base + age_modifier + taiga_modifier`.
3. **Step 2 composite-climate.** Fixture: clear-default settlement (climate=[grasslands, plains]). For merchandise=grain_vegetables, step 2 sums BOTH grasslands and plains contributions on top of base + age.
4. **Step 2 swamp composite.** Fixture: swamp biome, no lake adjacent. Step 2 applies scrub climate column AND lake_shore water column (per §3.3 swamp-implies-lake_shore).
5. **Step 2 multi-water-source.** Fixture: hex with water=ocean AND a river overlay. Step 2 applies sea_coast + river_bank water columns additively.
6. **Step 3 truncation.** `step_3_drop_fractions(1.5) == 1`; `(-1.5) == -1`; `(2.5) == 2`; `(0.5) == 0`; `(-0.5) == 0`; `(1.0) == 1`.
7. **Step 4 count fidelity at each land_revenue.** For each land_revenue in 3..9, assert that the number of +1 deltas applied matches the table, and the number of -1 deltas matches.
8. **Step 4 determinism.** Same settlement_id + same land_revenue → same +/- distribution every call.
9. **Step 4 cross-settlement variation.** Two different settlements at the same land_revenue produce different distributions (seed includes settlement_id).
10. **Step 4 transition.** Same settlement at land_revenue=3 vs land_revenue=4 produce different distributions (seed includes land_revenue).
11. **Step 5 Dwarf.** Fixture: dominant_race=dwarf, base modifiers all zero. After step_5, beer_ale, metals_common, tools, armor_weapons, metals_precious, semiprecious_stones, gems are all -2; other types unchanged.
12. **Step 5 Elf.** Same pattern with wood_common, dye_pigments, cloth, glassware, porcelain_fine.
13. **Step 5 Human (no-op).** dominant_race=human, base all zeros → after step_5, all still zero.

**End-to-end tests:**

14. **Full-procedure determinism.** Same settlement_id + same inputs → `generate_for_settlement` returns the same dictionary on repeat calls.
15. **Full-procedure input sensitivity — land revenue.** Same settlement at land_revenue=4 vs 7 produces different outputs (step 4 distribution shifts).
16. **Full-procedure input sensitivity — race.** Same settlement, race=human vs race=dwarf → dwarf has 7 merchandise types shifted -2.
17. **Cache write.** After `generate_for_settlement(settlement_id)`, `settlement_merchandise_demand` has 31 rows for that settlement, all with `source_kind='generated'`.
18. **Manual-override preservation.** Set one row to source_kind='manual' with value=+5. Run `regenerate`. That row is unchanged; the other 30 rows are regenerated.

### 4.12 What §4 does NOT add

- **No step-6 logic.** Trade-route shifts live in §5.
- **No price calculation.** Prices are §6 (market_price_resolver). §4 produces the demand_modifier integer that §6 consumes.
- **No transaction-time hooks.** Demand modifiers are not consulted on every buy/sell; they're consulted by the price resolver, which caches its own 4d4 dice rolls per the monthly-drift rule (§7).
- **No demand-modifier history.** The cache stores only the current value. If a future audit / replay system needs historical demand modifiers, add a history table later.
- **No semantic-flavored land-revenue distribution.** The §4.4 deterministic shuffle is intentionally agnostic about which merchandise types get hit. `[NEEDS-FLAVOR-PASS]` is the future enhancement hook.

---

## §5. Trade-Route Detection and Regional Demand Resolution (RAW Step 6)

### 5.0 Overview

RAW step 6 (`rules/acore-setting-construction-rules.xml:233` + the trade-route rules at L358-365 + the range_of_trade table at L264-278 + the worked example at L280-295) is operationally distinct from steps 1-5 because it requires *multi-settlement* awareness. Steps 1-5 yield per-settlement modifiers in isolation; step 6 reaches across settlements via valid trade routes and shifts demand modifiers toward one another.

This section ships three concerns:

1. **Trade-route detection.** For every pair of settlements, determine whether a valid trade route exists. Cache the result in a new `trade_routes` table.
2. **Region walk.** Identify the connected-via-trade-routes region around an anchor settlement, sort by market size, and apply step-6 shifts in the canonical "largest-first" order.
3. **The shift mechanic itself.** Equal-size markets shift each modifier 1 point toward the other; different-size markets shift the smaller's modifiers 2 points toward the larger's (or equalize if difference < 2).

§4 wrote `pre_trade_route_shift_value` to the cache; §5 reads those values, applies step 6 across the region, and writes the final `demand_modifier`.

### 5.1 Trade-route detection algorithm

- **RAW citation:** `rules/acore-setting-construction-rules.xml:359` (rule 1).
- **What RAW provides:** "Two criteria are required for a trade route: a connecting road/trail/navigable waterway, AND both markets must lie within each other's trade range."
- **Project resolution:** for each ordered pair of settlements `(A, B)` with `A.id < B.id` (canonical ordering — one pair processed once, not twice):

```
1. Pathfind from A's hex to B's hex via the ROAD graph.
   - Road graph: nodes are hexes with hex_terrain_overlays.overlay_type='road';
     edges between adjacent road-bearing hexes.
   - If a path exists, record road_distance_hexes = shortest path length.
2. Pathfind from A's hex to B's hex via the WATER graph.
   - Water graph: nodes are hexes where (water='ocean') OR (water='lake') OR
     (hex_terrain_overlays.overlay_type='river' on this hex).
     Edges between adjacent water-bearing hexes.
   - The settlement's own hex may not be a water hex (most settlements are on
     land adjacent to water). Special rule: a settlement enters the water graph
     via the §3.3 water-source check — if sea_coast/lake_shore/river_bank is
     true, the settlement can pathfind via the water hex it's adjacent to.
   - If a water path exists, record water_distance_hexes = shortest path length.
3. Read A and B's market_class. Look up range_of_trade for each:
     Class I  → 28 road / 80 water
     Class II → 24 road / 60 water
     Class III→ 18 road / 40 water
     Class IV → 12 road / 20 water
     Class V  → 8 road / 16 water
     Class VI → 4 road / 8 water
   The BINDING range is min(A_range, B_range) — both markets must lie within
   each other's range, so the smaller's range is the constraint.
4. Determine if any path satisfies the range:
   - If road_distance_hexes <= min(A_road_range, B_road_range): road route valid.
   - If water_distance_hexes <= min(A_water_range, B_water_range): water route valid.
5. If either is valid, A-B is a trade route. Record path_kind:
   - 'road' if only road is valid
   - 'water' if only water is valid
   - 'mixed' if both are valid (use the shorter distance as the canonical one)
   Store distance_hexes = the shorter valid distance.
```

#### 5.1.1 Range_of_trade table — RAW values

Encoded as an in-code constant in `engine/subsystems/commerce/trade_route_detector.gd`:

```gdscript
const RANGE_OF_TRADE := {
    1: {"road": 28, "water": 80},   # Class I
    2: {"road": 24, "water": 60},   # Class II
    3: {"road": 18, "water": 40},   # Class III
    4: {"road": 12, "water": 20},   # Class IV
    5: {"road": 8,  "water": 16},   # Class V
    6: {"road": 4,  "water": 8},    # Class VI
}
```

**Why in-code constant vs. JSON:** the table is 6 entries × 2 columns, fixed by RAW, never modified by gameplay. Hard-coding makes the code self-contained and traceable. Citation in the code: `# Source: rules/acore-setting-construction-rules.xml:264-278`.

#### 5.1.2 Special rule — settlement adjacency to water graph

A settlement on a land hex adjacent to an ocean/lake/river still participates in water trade. Per §3.3, the water-source flags (`sea_coast`, `lake_shore`, `river_bank`) capture this adjacency. For water pathfinding:

- If `sea_coast=true`: the settlement's "water graph entry node" is any adjacent ocean hex (pick the one closest to the destination, or any if equidistant).
- If `lake_shore=true`: entry node is any adjacent lake hex.
- If `river_bank=true`: entry node is the settlement's own hex (which has a river overlay).
- If all three are false: settlement has no water trade access.

When pathfinding A→B via water: A enters via its entry node, B enters via its entry node. The water graph BFS connects them.

#### 5.1.3 Project-design ledger — "navigable" waterway

- **What RAW provides:** "navigable waterway" as a connection type. RAW does not enumerate which water bodies count as navigable.
- **What's missing:** definition of "navigable."
- **Project resolution:** in v1, all ocean / lake / river hexes are navigable. RAW provides no granularity (small lakes vs. great lakes, small streams vs. great rivers), and the project's hex overlay system does not distinguish stream sizes either. Future enhancement: if a "minor stream" overlay type is added, it can be excluded from the water graph for trade-route purposes.

### 5.2 The step-6 shift mechanic

- **RAW citation:** `rules/acore-setting-construction-rules.xml:360-361`.
- **What RAW provides:**
  - Different-size markets: smaller market shifts ALL its demand modifiers 2 points toward the larger market's, or sets them equal if the difference is less than 2.
  - Equal-size markets: each shifts each demand modifier 1 point toward the other.
- **Worked example reference:** L280-295 Cyfaraun/Samos — captured in §5.5 as a validation target.

Algorithm for a single pair `(A, B)` and a single merchandise type:

```gdscript
static func apply_shift_for_merchandise(
    a_modifier: int,
    b_modifier: int,
    a_size: int,           # urban_families
    b_size: int,           # urban_families
) -> Array:                # [new_a_modifier, new_b_modifier]
    var diff: int = b_modifier - a_modifier
    if a_size > b_size:
        # B is smaller; shifts toward A. A unchanged.
        return [a_modifier, _shift_toward(b_modifier, a_modifier, 2)]
    elif b_size > a_size:
        # A is smaller; shifts toward B. B unchanged.
        return [_shift_toward(a_modifier, b_modifier, 2), b_modifier]
    else:
        # Equal size; both shift 1 point toward the other simultaneously.
        return [
            _shift_toward(a_modifier, b_modifier, 1),
            _shift_toward(b_modifier, a_modifier, 1),
        ]

static func _shift_toward(source: int, target: int, max_step: int) -> int:
    var diff: int = target - source
    if abs(diff) < max_step:
        return target  # Equalize per RAW rule "set them equal if difference is less than [max_step]"
    elif diff > 0:
        return source + max_step
    elif diff < 0:
        return source - max_step
    else:
        return source  # already equal
```

**Note on the equalize-on-difference<max_step rule.** RAW spells out this rule for the 2-point shift case (different-size markets); it doesn't explicitly state it for the 1-point equal-size case. My reading: the same logic applies — if A=0 and B=0 already, no shift needed, no harm in returning the same value. If A=+1 and B=0 with max_step=1, shifting A toward B by 1 produces B (=0), which is the equalize result; shifting B toward A by 1 produces A (=+1). Result: A=0, B=+1 — both shifted to their target. This matches the equal-size rule without special-casing.

**Symmetric simultaneous application is essential for equal-size pairs.** If we shifted A first then computed B's shift using A's *new* value, we'd be using stale information. The algorithm uses both ORIGINAL values to compute both NEW values, then returns the pair.

### 5.3 Region walk algorithm

- **RAW citation:** `rules/acore-setting-construction-rules.xml:362` rule 4.
- **What RAW provides:** "When processing a region, begin with the largest market and work outward through direct trade routes, then continue to the next markets."
- **Project resolution:** the algorithm below. Each trade-route pair is processed exactly once in a stable order driven by descending urban_families.

```gdscript
static func resolve_region(anchor_settlement_id: String) -> void:
    # Step 1: Identify the connected region.
    var region: Array = bfs_connected_settlements(anchor_settlement_id)
    # bfs_connected_settlements walks the trade_routes table from anchor,
    # collecting all settlements reachable via trade routes.

    # Step 2: Sort by urban_families desc, tie-break by settlement_id.
    region.sort_custom(func(a, b):
        if a["urban_families"] != b["urban_families"]:
            return a["urban_families"] > b["urban_families"]
        return a["id"] < b["id"]
    )

    # Step 3: Initialize per-settlement working state with pre-shift values.
    var working: Dictionary = {}  # settlement_id → {merchandise_type: modifier}
    for s in region:
        working[s["id"]] = DemandModifierGenerator.get_all_pre_shift_demand_modifiers(s["id"])

    # Step 4: Apply step-6 shifts in largest-first order, each pair once.
    var processed_pairs: Dictionary = {}  # "a_id|b_id" → true
    for s in region:
        var trade_neighbors: Array = trade_routes_for(s["id"])
        for neighbor_id in trade_neighbors:
            var pair_key: String = _canonical_pair_key(s["id"], neighbor_id)
            if processed_pairs.has(pair_key):
                continue
            processed_pairs[pair_key] = true

            var a_id: String = s["id"]
            var b_id: String = neighbor_id
            var a_size: int = working_size(a_id)
            var b_size: int = working_size(b_id)

            # Apply shift across every merchandise type.
            for merchandise_type in working[a_id]:
                var result: Array = apply_shift_for_merchandise(
                    working[a_id][merchandise_type],
                    working[b_id][merchandise_type],
                    a_size,
                    b_size,
                )
                working[a_id][merchandise_type] = result[0]
                working[b_id][merchandise_type] = result[1]

    # Step 5: Write back to the cache.
    for s_id in working:
        for merchandise_type in working[s_id]:
            _update_demand_modifier(s_id, merchandise_type, working[s_id][merchandise_type])
```

#### 5.3.1 Why "largest-first" ordering matters

The shift mechanic is not commutative across chains. Consider A(III) - B(IV) - C(V), all connected pairwise:

- **Largest-first (A, then B):**
  1. Process A. A-B pair: B (smaller) shifts toward A. B's modifiers move toward A's.
  2. Process B. B-C pair: C (smaller) shifts toward B's *post-A-shift* values.
  - Result: A unchanged; B partially toward A; C toward modified B (which is itself partially toward A).

- **Smallest-first (C, then B):**
  1. Process C. C-B pair: C (smaller) shifts toward B's *original* values.
  2. Process B. B-A pair: B (smaller) shifts toward A's original values. C's already-shifted modifier doesn't propagate back.
  - Result: B toward A; C toward B's *original* values (which differ from B's final values).

Different final modifiers. RAW's canonical order is largest-first, so that's what this GDD encodes. Project-design ledger entry: not a gap — RAW is explicit on order.

#### 5.3.2 Tie-breaking on urban_families

When two settlements have identical `urban_families` (and therefore identical market class), the algorithm tie-breaks by `settlement_id` ascending. This is project-designed for determinism — RAW doesn't address ties. Stable ordering means the same region produces the same shift sequence on every regeneration.

#### 5.3.3 Disconnected regions

A campaign can have multiple disconnected regions (no trade route between them). Each region resolves independently. `resolve_region` is called per region anchor; the caller (event listener) figures out which regions need resolving when topology changes.

`resolve_all_regions(campaign_id)` is a convenience that BFS-partitions all settlements into disjoint regions and calls `resolve_region` for each. Used at campaign-load time after migration 097 lands, to populate the cache for existing campaigns.

### 5.4 Worked example — Ashford / Thornwall validation target

- **RAW citation:** `rules/acore-setting-construction-rules.xml:280-295` (the canonical Cyfaraun/Samos shift example from the RAW PDF's implied setting). The arithmetic below is reused verbatim from that table; the market names are mapped onto project-canonical test-hexmap settlements (`test_settlement_ashford` and `test_settlement_thornwall` from `data/test_hex_map.json`) for naming consistency with the rest of the project. The RAW values do not depend on which markets we name; only their relative sizes and pre-shift modifiers matter.

**Fixture setup:**
- Ashford (LARGER market): `urban_families` set such that it is at least 2 market-class steps above Thornwall (specific synthetic values in the test fixture).
- Thornwall (SMALLER market): smaller `urban_families`; specific synthetic value in the test fixture.
- A direct trade route exists between them (test inserts a `trade_routes` row manually rather than relying on the hexmap's actual road/water topology).

**Pre-shift and post-shift modifiers:**

| Merchandise | Ashford (larger) | Thornwall (smaller, pre-shift) | Thornwall (post-shift) | Operation |
|---|---|---|---|---|
| `wood_common` | -3 | -2 | **-3** | diff=1 < 2 → equalize |
| `hides_furs` | -3 | -1 | **-3** | diff=2 → shift 2 toward → -1-2=-3 |
| `metals_common` | -2 | -3 | **-2** | diff=1 < 2 → equalize |
| `grain_vegetables` | +1 | -2 | **0** | diff=3 ≥ 2 → shift 2 toward → -2+2=0 |
| `spices` | +1 | 0 | **+1** | diff=1 < 2 → equalize |
| `silk` | +1 | 0 | **+1** | diff=1 < 2 → equalize |

This is the canonical validation target. A unit-test fixture creates two settlements with these merchandise modifier values, runs `RegionDemandResolver.resolve_region`, and asserts the post-shift values exactly match the right column. Ashford's modifiers are unchanged (it is the larger market and does not shift).

**Why the test fixture is synthetic rather than reading from `test_hex_map.json`:** the test hexmap's settlements were authored before this GDD; they have default `urban_families = 0` and `market_class = 6` (per migration 097's defaults). The unit test populates specific `urban_families` and pre-shift modifier values for the fixture to drive deterministic arithmetic. The test_hex_map.json is consumed by *scene* tests (rendering, interaction); demand-modifier *unit* tests use their own synthetic data, which is the standard pattern for ACKS Arbiter test suites (see `tests/test_faith_block.gd` as a precedent).

### 5.5 `trade_routes` schema

New table, migration 097 (10th sub-step):

```sql
CREATE TABLE IF NOT EXISTS trade_routes (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_a_id             TEXT    NOT NULL REFERENCES settlement_entrances(id),
    settlement_b_id             TEXT    NOT NULL REFERENCES settlement_entrances(id),
    path_kind                   TEXT    NOT NULL
        CHECK(path_kind IN ('road', 'water', 'mixed')),
    distance_hexes              INTEGER NOT NULL,
    discovered_at_calendar_day  INTEGER NOT NULL DEFAULT 0,
    invalidated                 INTEGER NOT NULL DEFAULT 0
        CHECK(invalidated IN (0, 1)),
    -- Canonical pair ordering: settlement_a_id < settlement_b_id ensures
    -- one row per pair regardless of detection direction.
    CHECK(settlement_a_id < settlement_b_id),
    UNIQUE(settlement_a_id, settlement_b_id)
);
CREATE INDEX idx_trade_routes_a ON trade_routes(settlement_a_id, invalidated);
CREATE INDEX idx_trade_routes_b ON trade_routes(settlement_b_id, invalidated);
CREATE INDEX idx_trade_routes_campaign ON trade_routes(campaign_id, invalidated);
```

**Field rationale:**

- `id` — UUID, generated by `CampaignRepository.generate_id()`.
- Canonical pair order (`a_id < b_id`) enforced via CHECK. Detector code always orders the pair this way before inserting.
- `path_kind` — `'road'`, `'water'`, or `'mixed'`. Audit/UI use; not consumed by the shift algorithm itself.
- `distance_hexes` — the shorter of the road/water distances (whichever path was used). Audit value.
- `discovered_at_calendar_day` — when the route was last detected. Useful for "this route is N days old" UI.
- `invalidated` — soft-delete flag. When topology changes, affected routes get marked `invalidated=1` rather than deleted; the next detector run either confirms them (sets back to 0) or actually deletes. Soft-delete is gentler if an in-flight transaction is mid-region-walk when topology shifts.

### 5.6 Cache invalidation triggers

`TradeRouteDetector` and `RegionDemandResolver` listen for the following EventBus signals and invalidate / re-run accordingly:

| Signal | Trigger | Detector / Resolver action |
|---|---|---|
| `road_overlay_added(map_id, q, r)` | New road overlay segment | Mark all trade routes whose paths pass near `(q, r)` as `invalidated=1`. Re-detect for nearby settlements; then re-run region resolver. |
| `road_overlay_removed(map_id, q, r)` | Road segment removed | Same as above. |
| `river_overlay_added/removed` | River overlay changed | Same pattern; water-path-bearing trade routes affected. |
| `settlement_created(settlement_id)` | New settlement | Run detector for the new settlement against all other settlements in the campaign within max range. Insert new routes. Re-run region resolver for the region containing the new settlement. |
| `settlement_destroyed(settlement_id)` | Settlement removed | Delete all trade routes referencing this settlement. Re-run region resolver for the formerly-connected region. |
| `settlement_market_class_changed(settlement_id)` | Market class change (rare; tied to urban_families change) | Re-run detector for this settlement (range may now include/exclude different counterparts). Re-run region resolver. |
| `hex_water_tag_changed(map_id, q, r)` | Hex's water tag changes (extremely rare; world-changing events) | Same as road overlay add/remove. |

**Nearby-settlement scope for "passes near" detection:** for an added road segment at `(q, r)`, the affected settlements are those whose existing trade routes' paths include `(q, r)` OR settlements within the maximum trade range (28 hexes road, 80 hexes water) of `(q, r)`. In practice, this is a small subset of campaign settlements unless `(q, r)` is in a dense urban region. v1: scan all settlements and check distance to `(q, r)`; optimize later if profiling shows hot path.

### 5.7 Service APIs

#### 5.7.1 `TradeRouteDetector`

`engine/subsystems/commerce/trade_route_detector.gd` — `RefCounted` static-function library.

```gdscript
class_name TradeRouteDetector
extends RefCounted

# Public API
static func detect_routes_for_settlement(settlement_id: String) -> Array
    # Returns array of newly-detected trade_routes rows (also written to DB).
    # Invalidates and replaces existing routes for this settlement.
static func detect_routes_for_campaign(campaign_id: String) -> int
    # Full sweep — O(N²) detection across all settlements. Returns count of routes.
    # Used at campaign-load when settlement_merchandise_demand is empty.

# Pure-function helpers (testable)
static func compute_road_distance(settlement_a_id: String, settlement_b_id: String) -> int
    # Returns hexes, or -1 if no path.
static func compute_water_distance(settlement_a_id: String, settlement_b_id: String) -> int
    # Returns hexes, or -1 if no path.
static func is_within_mutual_range(a_market_class: int, b_market_class: int, distance: int, kind: String) -> bool
    # kind = 'road' or 'water'.
```

#### 5.7.2 `RegionDemandResolver`

`engine/subsystems/commerce/region_demand_resolver.gd` — `RefCounted` static-function library.

```gdscript
class_name RegionDemandResolver
extends RefCounted

# Public API
static func resolve_region(anchor_settlement_id: String) -> void
    # BFS the region, apply step-6 shifts in largest-first order, write final
    # demand_modifier values back to settlement_merchandise_demand.
static func resolve_all_regions(campaign_id: String) -> void
    # Partition campaign settlements into disjoint regions; resolve each.
    # Used at campaign-load and after major topology changes.

# Pure-function helper
static func apply_shift_for_merchandise(
    a_modifier: int, b_modifier: int, a_size: int, b_size: int
) -> Array
    # Returns [new_a, new_b]. The core shift mechanic from §5.2.
```

### 5.8 Tests

`tests/test_trade_route_detector.gd` budget: **~10 tests.**

1. **Road path: direct adjacent.** Two settlements on adjacent hexes connected by a one-edge road → road_distance = 1.
2. **Road path: extended chain.** Two settlements separated by 5 road-bearing hexes → road_distance = 5.
3. **Road path: no path.** Two settlements with no road between → road_distance = -1.
4. **Water path: ocean-coast pair.** Two settlements both sea_coast=true with adjacent ocean hexes connected → water_distance = 1 + 1 (through one shared ocean hex) or similar.
5. **Water path: river chain.** Settlements on a river that flows continuously → water_distance via river hexes.
6. **Range constraint binds smaller market.** Class III + Class V on a 10-hex road → invalid (Class V's road range is 8). Class III + Class III on same → valid.
7. **Mixed path: both road and water valid.** Returns whichever is shorter; path_kind='mixed'.
8. **Pair canonical ordering.** `detect_routes_for_settlement(A)` and `detect_routes_for_settlement(B)` for the same pair yield exactly one row with `settlement_a_id < settlement_b_id`.
9. **Range constraint: water range > road range.** Class V settlements at 14 hexes apart via water (within 16-hex water range) → valid water route, even though they exceed 8-hex road range.
10. **Detection persistence.** `detect_routes_for_settlement` writes correct rows to `trade_routes`.

`tests/test_region_demand_resolver.gd` budget: **~12 tests.**

1. **Single pair, equal size.** A=class III (uf=1000) and B=class III (uf=1000) with one merchandise modifier each (A.silk=+2, B.silk=0). Apply shift: A.silk=+1, B.silk=+1. (Both meet in middle.)
2. **Single pair, different size — diff ≥ 2.** A=class III (larger), B=class V. A.grain=+1, B.grain=-2. After shift: A unchanged at +1; B = -2+2 = 0.
3. **Single pair, different size — diff < 2.** A=class III, B=class V. A.spices=+1, B.spices=0. After shift: A unchanged; B=+1 (equalized).
4. **Ashford/Thornwall worked example (RAW arithmetic, project-canonical names).** Fixture two settlements with the exact merchandise modifiers from §5.4. After region resolve, post-shift values match the RAW arithmetic verbatim. (Math sourced from `rules/acore-setting-construction-rules.xml:280-295`; names mapped to project-canonical settlements per §5.4 fixture-setup rationale.)
5. **Three-settlement chain, largest-first.** A(III)-B(IV)-C(V) chain. After resolve: A processed first, B-A shift applied first; then B processes its other trade routes (B-C); C shifts toward B's already-modified value.
6. **Disconnected regions.** Two settlements with no trade route between → `resolve_region(A)` does not affect B's modifiers.
7. **Equal-size symmetric shift.** Verify that for two equal settlements with mirror modifiers (A.silk=+2, B.silk=-2), both shift toward each other by 1: A=+1, B=-1. Diff is 4 > 1 max_step, so no equalize.
8. **No-op shift.** A.salt=0, B.salt=0 → after shift, both still 0.
9. **All 31 merchandise types shift independently.** Verify that the resolver applies the shift across every merchandise type per pair, not just one.
10. **Manual override preserved.** Settlement with one merchandise row source_kind='manual' → after region resolve, that row is unchanged; the other 30 are shifted normally.
11. **Stable tie-breaking on urban_families.** Two settlements with identical urban_families produce a stable shift order; same input always produces same output.
12. **Region partition.** Three settlements: A↔B (connected), C (isolated). `resolve_all_regions` runs resolve_region twice (once for the AB region, once for the C-singleton region; the singleton is a no-op since C has no trade routes).

### 5.9 What §5 does NOT add

- **No step-6 hooks at transaction time.** Demand modifiers are static between cache invalidations. The price resolver in §6 reads `demand_modifier` from the cache; it never re-invokes step 6.
- **No road graph caching layer.** Road overlay queries hit the existing `hex_terrain_overlays` table directly. If profiling shows pathfinding is too slow at campaign scale, add a precomputed road graph cache later.
- **No advanced "navigability" semantics.** Per §5.1.3, all water hexes are equally navigable in v1. Small streams vs. great rivers is a future enhancement.
- **No trade route weighting.** RAW treats every trade route as equally valid; this GDD does the same. No "premium trade route" or "primary vs. secondary route" distinctions.
- **No multi-step propagation.** Each pair is processed exactly once. A long chain A-B-C-D-E does NOT propagate A's influence to E in one pass; each link applies its own shift in sequence per the largest-first ordering. RAW does not specify a transitive influence model.

---

## §6. Market Price Resolver and Monthly Drift

### 6.0 Overview

This section encodes the market-price formula from `rules/acore-campaign-hijinks.xml:719-735` (the "Determine Market Price of Merchandise" step within the arbitrage-trading procedure) and the monthly drift mechanic at L737-739. The resolver consumes the cached demand modifier (§4-5 output) plus a fresh 4d4 dice roll, plus a few constants, and produces a gp-per-load market price.

The 4d4 dice value is **cached per (settlement, merchandise) pair** so that prices remain stable between visits. The monthly drift mechanic re-rolls the dice at a cumulative 10%/month rate (Q-MERC-6 resolution: only the dice re-rolls, never the demand modifier).

### 6.1 The RAW formula

- **RAW citation:** `rules/acore-campaign-hijinks.xml:725-734` step-by-step procedure.
- **What RAW provides:** an ordered 8-step procedure:

```
1. Find the merchandise's base price (Common or Precious table).
2. Roll 4d4.
3. Add the demand modifier for that merchandise in that market, if any.
4. Add 1 if the market is Class I or II.
5. Subtract 1 if the market is Class V or VI.
6. Modify by 1 in the adventurer's favor if he has a monopoly in that merchandise.
7. Apply any special Judge modifiers, such as war or calamity.
8. Multiply the final result by 10 and apply that percentage to the base price.
```

- **Project resolution:** the formula encodes as:

```
percentage = (dice_4d4 + demand_modifier + class_size_adjust
             + monopolist_favor + judge_modifier) * 10
gp_per_load = banker_round(base_price_gp * percentage / 100)
```

All inputs are integers; intermediate arithmetic stays integer until the final percentage-to-gp conversion where banker's rounding handles fractional results.

#### 6.1.1 RAW step 4 — Market price is per-merchandise, per-visit

RAW L722-723 specifies: "Market price is calculated once per type of merchandise for each visit to a market. Different merchants in the same market do not buy or sell the same goods at different prices during the same visit."

This drives the dice-cache design: one 4d4 value per (settlement, merchandise) pair. All merchants in that settlement transact at the same price for that merchandise during a visit. The dice value persists across visits until the monthly drift mechanic re-rolls it (§6.6).

### 6.2 Inputs and their sources

| Input | Source | §-of-this-GDD |
|---|---|---|
| `base_price_gp` | `MerchandiseRegistry.base_price_gp(merchandise_type)` | §2 |
| `dice_4d4` | Cached on `settlement_merchandise_demand.dice_4d4_value`; rolled fresh on first read | §6.5 |
| `demand_modifier` | `DemandModifierGenerator.get_demand_modifier(settlement, merchandise)` (post-shift value) | §4-5 |
| `class_size_adjust` | Derived from `settlement_entrances.market_class` via §6.3 table | §6.3 |
| `monopolist_favor` | Caller-supplied: +1 if monopolist selling, -1 if monopolist buying, 0 otherwise | §6.4 |
| `judge_modifier` | Caller-supplied integer (war, calamity, scripted event); default 0 | §6.1 |

### 6.3 Class-size adjustment

- **RAW citation:** `rules/acore-campaign-hijinks.xml:729-730`.
- **What RAW provides:** "Add 1 if the market is Class I or II. Subtract 1 if the market is Class V or VI."
- **What's missing:** nothing — RAW is explicit; no project-design fill needed. Q-MERC-11 [RESOLVED 2026-05-12]: these values are RAW, not project-designed.
- **Project resolution:** in-code constant:

```gdscript
static func class_size_adjust(market_class: int) -> int:
    match market_class:
        1, 2: return 1
        3, 4: return 0
        5, 6: return -1
        _:    return 0   # Defensive — out-of-range market_class should never happen.
```

### 6.4 Monopolist favor — direction-aware

- **RAW citation:** `rules/acore-campaign-hijinks.xml:731`.
- **What RAW provides:** "Modify by 1 in the adventurer's favor if he has a monopoly in that merchandise."
- **What's missing:** RAW's phrasing "in the adventurer's favor" implies direction-awareness — when selling, the favor is +1 (higher price); when buying, -1 (lower price). RAW does not write the formula in those terms.
- **Project resolution:** caller responsibility. `MarketPriceResolver.compute_market_price` takes a `monopolist_favor: int` parameter — caller passes `+1` when the adventurer is the monopolist AND selling, `-1` when monopolist AND buying, `0` otherwise. This keeps the resolver direction-agnostic; the transaction layer (Phase 10B.2's buy_sell_merchandise handler) knows which direction the player is transacting in.

For non-monopolist transactions, the same merchandise has the same price for buying and selling. RAW L722-723's "different merchants in the same market do not buy or sell the same goods at different prices during the same visit" implies a single market price; the monopolist favor is the sole direction-dependent modifier.

#### 6.4.1 Why caller-supplied vs. resolver-derived

`MarketPriceResolver` does not know the campaign's monopoly state. The monopolist registry lives in Phase 10B.2 (the Trade block), which writes/reads `monopoly_holdings` rows. The resolver is consumed by both Phase 10B.2's buy/sell flow AND by Phase 10B.3's hijink-payout flow (smuggling/stealing pay 12%/60% of market price). Making the favor caller-supplied keeps the resolver decoupled from the monopoly state machine — each caller resolves monopoly status as it sees fit and passes the integer.

### 6.5 Dice cache — extending `settlement_merchandise_demand`

The cached 4d4 value lives on the existing `settlement_merchandise_demand` table (§4.7) rather than a sibling table. Same PK, same query patterns, fewer joins. The schema gets two new columns (amending §4.7's `CREATE TABLE`):

```sql
ALTER TABLE settlement_merchandise_demand
    ADD COLUMN dice_4d4_value INTEGER NOT NULL DEFAULT 0;
ALTER TABLE settlement_merchandise_demand
    ADD COLUMN dice_last_rolled_calendar_day INTEGER NOT NULL DEFAULT 0;
```

**Sentinel:** `dice_4d4_value = 0` means "not yet rolled" (the minimum natural value of 4d4 is 4). On first price read, the resolver rolls fresh, caches, returns. Subsequent reads return the cached value until the monthly drift trigger re-rolls it.

**Why on the same table:** the dice cache is structurally tied to (settlement, merchandise) and to the demand modifier — they're read together by every price computation. A separate table would multiply join cost. The dice cache is *temporal* state (random fluctuation) and the demand modifier is *structural* state (long-term anchor), but they share the same PK and read pattern; mixing them in one table is the right factoring.

**Migration 097 sub-step count update:** §4 had this table as sub-step 8 (creating it with `demand_modifier`, `pre_trade_route_shift_value`, `generated_at_calendar_day`, `source_kind`). §6 amends the CREATE to also include the two dice columns, so the migration sub-step count does NOT grow — the columns are present at table creation, not added via ALTER. Updated `CREATE TABLE` in §14's consolidated migration plan.

### 6.6 Monthly drift mechanic

- **RAW citation:** `rules/acore-campaign-hijinks.xml:737-739`.
- **What RAW provides:** "If adventurers remain in the same market waiting for prices to change, each month there is a cumulative 10% chance that each merchandise type's price changes and is re-rolled."
- **Project resolution:** lazy-evaluation algorithm. The drift check fires when a price is read (or at the monthly domain tick — whichever happens first), computes months-since-last-roll, applies the cumulative probability check, re-rolls if triggered. Per Q-MERC-6 [RESOLVED 2026-05-12], **only the 4d4 dice value re-rolls** — the demand modifier stays anchored to its structural inputs.

#### 6.6.1 Cumulative probability interpretation

RAW's "cumulative 10% chance" reads as: each month-without-re-roll adds 10% to the chance of re-roll on the next check. By month 10, re-roll is forced (probability 100%). When re-roll fires, the cumulative chance resets to 10% for the next month.

| Months since last re-roll | Cumulative re-roll chance |
|---|---|
| 0 | 0% (no time has passed) |
| 1 | 10% |
| 2 | 20% |
| 3 | 30% |
| ... | ... |
| 9 | 90% |
| 10+ | 100% (forced) |

#### 6.6.2 Implementation — single-check shortcut

For v1, the drift check evaluates the *current* cumulative probability and rolls once. This is mathematically equivalent to "what's the probability re-roll has happened by month N?" but is NOT bit-exact equivalent to "for each of the past N months, did re-roll happen?" The two differ only in the *when* of the re-roll, not the *whether*. For v1, we don't need event-time precision.

```gdscript
static func check_and_apply_drift(
    settlement_id: String,
    merchandise_type: String,
    current_calendar_day: int,
    rng: RandomNumberGenerator,
) -> bool:
    var row: Dictionary = _read_cache_row(settlement_id, merchandise_type)
    var days_since: int = current_calendar_day - row["dice_last_rolled_calendar_day"]
    var months_since: int = floori(float(days_since) / float(Timekeeping.DAYS_PER_MONTH))
    if months_since <= 0:
        return false
    var cumulative_pct: int = mini(months_since * 10, 100)
    if rng.randi_range(1, 100) <= cumulative_pct:
        var new_dice: int = _roll_4d4(rng)
        _write_dice(settlement_id, merchandise_type, new_dice, current_calendar_day)
        EventBus.market_price_drifted.emit(
            settlement_id, merchandise_type, row["dice_4d4_value"], new_dice
        )
        return true
    return false
```

#### 6.6.3 Trigger points

The drift check fires at two points:

1. **Lazy on read.** When `MarketPriceResolver.compute_market_price(...)` is called, it first invokes `check_and_apply_drift` for that (settlement, merchandise) pair. If drift happens, the new dice value is used in the same call.
2. **Monthly tick.** The `DomainMonthlyResolver` (existing infrastructure from Phase 10A.2) invokes `check_and_apply_drift` for every settlement-merchandise pair in every settlement on the monthly tick. This ensures drift happens even at markets the player doesn't visit, so when they eventually arrive at an unvisited market, the dice reflect months of accumulated drift events rather than appearing frozen.

**Performance note:** the monthly tick processes 31 merchandise × N settlements per campaign. At 100 settlements, that's 3,100 drift checks per month. Cheap (just an RNG call + conditional update). If this becomes a profiling hot path at much larger campaign scales, batch into a single SQL query.

#### 6.6.4 Future enhancement — per-month iteration

The shortcut in §6.6.2 produces correct probabilities for "did re-roll happen?" but loses event-time fidelity (we record the re-roll as happening on the current day, even if probabilistically it "should" have happened some months earlier). A future enhancement iterates per-month and records the actual re-roll month for audit / ledger purposes. Tagged `[NEEDS-DRIFT-PRECISION-PASS]` in the source.

### 6.7 Banker's rounding for the final gp_per_load

Per CLAUDE.md: "Banker's rounding (round half to even) everywhere. No exceptions." Step 3's `int(value)` truncation (§4.3) is explicitly RAW-prescribed and narrow-scoped; everywhere else, including §6.1's `base_price_gp * percentage / 100` conversion, uses `RoundingUtil.banker_round`.

Examples:

| base | percentage | raw gp | banker-rounded |
|---|---|---|---|
| 100 | 100 | 100.0 | 100 |
| 100 | 125 | 125.0 | 125 |
| 33 | 105 | 34.65 | 35 |
| 33 | 110 | 36.3 | 36 |
| 50 | 105 | 52.5 | 52 (rounds to even) |
| 50 | 115 | 57.5 | 58 (rounds to even) |
| 200 | 105 | 210.0 | 210 |

### 6.8 `MarketPriceResolver` service API

`engine/subsystems/commerce/market_price_resolver.gd` — `RefCounted` static-function library.

```gdscript
class_name MarketPriceResolver
extends RefCounted

# Main entry point.
static func compute_market_price(
    merchandise_type: String,
    settlement_id: String,
    monopolist_favor: int = 0,    # +1, -1, or 0
    judge_modifier: int = 0,
    rng: RandomNumberGenerator = null,  # if null, uses a shared default
    current_calendar_day: int = -1,     # if -1, uses CampaignRepository's current day
) -> Dictionary
    # Returns:
    # {
    #   "gp_per_load": int,           # banker-rounded
    #   "percentage": int,            # the post-formula percentage applied
    #   "drift_occurred": bool,       # true if check_and_apply_drift re-rolled
    #   "breakdown": {
    #     "base_price_gp": int,
    #     "dice_4d4": int,
    #     "demand_modifier": int,
    #     "class_size_adjust": int,
    #     "monopolist_favor": int,
    #     "judge_modifier": int,
    #   }
    # }

# Drift-related helpers
static func check_and_apply_drift(
    settlement_id: String,
    merchandise_type: String,
    current_calendar_day: int,
    rng: RandomNumberGenerator,
) -> bool
    # Returns true if dice were re-rolled.

static func process_monthly_drift_for_campaign(
    campaign_id: String,
    current_calendar_day: int,
    rng: RandomNumberGenerator,
) -> int
    # Called by DomainMonthlyResolver. Returns count of dice that re-rolled.

# Pure-function step helpers (testable)
static func class_size_adjust(market_class: int) -> int  # §6.3 table
static func roll_4d4(rng: RandomNumberGenerator) -> int
static func compute_percentage(
    dice_4d4: int,
    demand_modifier: int,
    class_size_adjust: int,
    monopolist_favor: int,
    judge_modifier: int,
) -> int
    # Returns (sum) * 10. No banker rounding; pure integer arithmetic.

# EventBus signals emitted (added to event_bus.gd in §14):
# - market_price_drifted(settlement_id, merchandise_type, old_dice, new_dice)
```

### 6.9 Worked examples

#### Example A — neutral market, no monopoly, no drift

- Merchandise: `wood_common` (base 50 gp, common)
- Settlement: Ashford (class III, demand_modifier for wood = -1 per §5 fixture)
- Dice: 10 (sum of 4d4 close to average)
- Modifiers: class_size = 0; monopolist_favor = 0; judge = 0

```
percentage = (10 + (-1) + 0 + 0 + 0) * 10 = 90
gp_per_load = 50 * 90 / 100 = 45
```

A 50 gp base good in a slightly-low-demand class-III market sells at 45 gp.

#### Example B — class-II monopolist selling spices in a high-demand market

- Merchandise: `spices` (base 800 gp, precious)
- Settlement: hypothetical class-II market with demand_modifier for spices = +2
- Dice: 12
- Modifiers: class_size = +1 (Class II); monopolist_favor = +1 (selling monopolist); judge = 0

```
percentage = (12 + 2 + 1 + 1 + 0) * 10 = 160
gp_per_load = 800 * 160 / 100 = 1280
```

A monopolist selling spices in a class-II market with +2 demand and average dice gets 1,280 gp per load — 60% over base.

#### Example C — class-VI subsistence market, war modifier

- Merchandise: `grain_vegetables` (base 10 gp, common)
- Settlement: class-VI hamlet, demand_modifier for grain = +2 (poor land, demand for staples)
- Dice: 14 (good roll)
- Modifiers: class_size = -1 (Class VI); monopolist_favor = 0; judge = -2 (war disruption suppressing trade)

```
percentage = (14 + 2 + (-1) + 0 + (-2)) * 10 = 130
gp_per_load = 10 * 130 / 100 = 13
```

Even with war disruption, the hamlet's high demand for grain plus a good dice roll keeps the price at 13 gp/load — 30% over base.

### 6.10 Tests

`tests/test_market_price_resolver.gd` budget: **~14 tests.**

**Pure-function step tests:**

1. **`class_size_adjust` table.** Class 1 → +1; Class 2 → +1; Class 3 → 0; Class 4 → 0; Class 5 → -1; Class 6 → -1.
2. **`roll_4d4` range.** Run 10000 times; assert every result is in [4, 16] inclusive.
3. **`compute_percentage` arithmetic.** Pin all inputs (dice=10, demand=+1, class_adj=0, monopoly=0, judge=0) → percentage = 110. Verify multiple combinations.
4. **Banker rounding edge cases.** `compute_market_price` for (base=50, percentage=115) → 57.5 → 58 (even). For (base=50, percentage=105) → 52.5 → 52 (even). For (base=33, percentage=105) → 34.65 → 35.

**Cache and dice behavior:**

5. **First-read rolls fresh.** Compute price for settlement-merchandise pair with no cache row → row inserted with rolled dice; same call again returns same dice (no re-roll).
6. **Dice persistence across calls.** Two `compute_market_price` calls with identical inputs return identical dice and identical price.
7. **Monopolist favor direction.** Same fixture, monopolist_favor=+1 → percentage 10 higher than monopolist_favor=0; monopolist_favor=-1 → percentage 10 lower.
8. **Judge modifier passes through.** judge_modifier=-3 reduces percentage by 30; judge_modifier=+5 increases by 50.

**Drift behavior:**

9. **No drift within month.** `compute_market_price` called twice on the same day → drift_occurred=false both times.
10. **Drift triggered at month 1 with 10% probability.** With seeded RNG that rolls 5 (under 10), drift fires at month 1; with seeded RNG that rolls 50 (above 10), drift does not fire at month 1.
11. **Drift forced at month 10.** With ANY RNG state, drift fires at month 10 (cumulative_pct = 100).
12. **Drift resets cumulative.** After drift fires at month 5, the next drift check uses month-1 cumulative (10%), not month-6 (60%).
13. **Drift emits signal.** Monitor `EventBus.market_price_drifted`; assert it emits with correct settlement_id, merchandise_type, old_dice, new_dice.

**End-to-end:**

14. **Worked-example reproducibility.** Pin a settlement with known demand_modifier and market_class, seed RNG to produce a specific 4d4 value, call `compute_market_price` → assert gp_per_load matches a hand-calculated expected value. Run for each of §6.9's three worked examples.

### 6.11 What §6 does NOT add

- **No buy-vs-sell split price.** Per RAW L722-723, a single market price applies to both directions of transaction in a single visit. Direction-awareness is captured only by `monopolist_favor`.
- **No transaction-time gp deduction or treasury adjustment.** The resolver is read-only — it computes a price. The buy_sell_merchandise handler (Phase 10B.2) and the hijink resolvers (Phase 10B.3) are responsible for actually moving gp / merchandise.
- **No mass / bulk discount.** RAW prices are per-load, full stop. Caravans of 40 loads pay 40× per-load price (modulo customs duty discounts, which live in §9).
- **No spell-cost lookup.** The "Spell Availability by Market" table (Phase 10A.2 dependency) is unrelated to merchandise prices; audit lives in §12.
- **No persuade-merchants reaction roll.** Phase 10B.2 ships that — it consumes the demand_modifier (with sign depending on direction per RAW L711-712) but does not call the price resolver.
- **No automatic "market closed for war" override.** The Phase 9A `market_class_modifiers` table (already shipped) temporarily shifts market class via Vagary events; §6 reads `market_class` from `settlement_entrances` and is unaware of the modifiers table. The downstream consumer (buy_sell handler) is responsible for resolving the effective class via the modifiers layer before passing it in. **Note:** an alternative is for the resolver to consult `market_class_modifiers` directly. Decision deferred to Phase 10B.2 author per CLAUDE.md scope-boundaries; surfaced here for visibility.

---

## §7. Merchant Pool Model

### 7.0 Overview

This section encodes the merchant pool — the set of merchants present at a settlement and willing to transact. The pool is the data structure that `persuade_merchants`, `buy_sell_merchandise`, smuggling-target selection, and stealing-target selection all consume.

Per Q-MERC-5 [RESOLVED 2026-05-12 + 2026-05-12 refinement], the model is:

- **Monthly tick always generates pool at MAX count.** Every settlement with `market_class I-VI` gets a full max-count cohort on each monthly tick. No average/max distinction at generation time. Loads per merchant rolled fresh per the RAW dice formula.
- **Visibility is the gameplay lever, not pool size.** Each merchant row carries a `becomes_visible_calendar_day` field. Merchants exist in the database the moment they spawn; whether the player *sees* them depends on this field.
- **PC-owned domain settlements: instant visibility.** When the parent domain's `owner_character_id` is a PC, all generated merchants get `becomes_visible_calendar_day = generation_day`. Players see the full pool immediately on arrival.
- **Non-PC-owned settlements: invisible until solicited.** Generated merchants get `becomes_visible_calendar_day = INT_MAX` sentinel. Pool exists but is invisible to the UI.
- **`solicit_merchants` action triggers staggered reveal** per RAW's half/quarter/remainder cadence (RAW `acore-campaign-hijinks.xml:679-684` + `ax_campaign_play.xml:958-962`). The 1-3 week Ongoing activity reveals half the pool at week 1, quarter at week 2, remainder at week 3.
- **`locate_merchandise` action targets a specific merchandise type.** Minor singular unstrenuous 1-hour activity. Searches the invisible pool for a merchant carrying the requested type; surfaces them if found. RAW-faithful (alters existing merchants only — no spawn).
- **28-day expiration.** Project-designed (RAW silent on merchant lifecycle). Each merchant row carries `expires_at_calendar_day = created_at + Timekeeping.DAYS_PER_MONTH` (28 days — the project calendar has 13-month / 28-day / 364-day years per `engine/autoloads/timekeeping.gd`). Monthly refresh wipes the previous cohort and generates a new one.

The model retires the original §5.E "ambient pool + solicit pool" double-roll and the v0 attempt at "average ambient + max solicit." One pool generation path (always max), one visibility mechanic (per-merchant `becomes_visible_calendar_day`), two player actions that flip visibility bits.

**Cohort lifecycle alignment** creates a meaningful strategic cadence: the player who solicits early in a 28-day cohort sees the full reveal before the pool refreshes (week-1 reveal at solicit_day+7, week-2 at +14, week-3 at +21). A player who solicits late (say day 14 of the cohort) sees only the first two reveals before the pool wipes at day 28. **Early solicit is rewarded.**

### 7.1 Markets and Merchants — RAW encoding

- **RAW citation:** `rules/acore-campaign-hijinks.xml:656-672`.
- **What RAW provides:** per-class toll, merchant count formula, loads-per-merchant formula:

| Market Class | Toll | Merchants | Loads per Merchant |
|---|---|---|---|
| I | 1d6+15 gp | 2d6+2 | 6d8 |
| II | 1d10+10 gp | 2d4+1 | 4d6 |
| III | 1d8+5 gp | 2d4 | 3d4 |
| IV | 1d6+3 gp | 1d4 | 2d4 |
| V | 1d6 gp | 1d4-1 | 1d4 |
| VI | 1d3 gp | 1d3-1 | 1d2 |

- **Encoded as in-code constant** in `engine/subsystems/commerce/merchant_pool_repository.gd`:

```gdscript
const MARKETS_AND_MERCHANTS := {
    1: {"toll_dice": "1d6+15", "merchants_dice": "2d6+2", "loads_dice": "6d8"},
    2: {"toll_dice": "1d10+10", "merchants_dice": "2d4+1", "loads_dice": "4d6"},
    3: {"toll_dice": "1d8+5",  "merchants_dice": "2d4",   "loads_dice": "3d4"},
    4: {"toll_dice": "1d6+3",  "merchants_dice": "1d4",   "loads_dice": "2d4"},
    5: {"toll_dice": "1d6",    "merchants_dice": "1d4-1", "loads_dice": "1d4"},
    6: {"toll_dice": "1d3",    "merchants_dice": "1d3-1", "loads_dice": "1d2"},
}
```

**Why in-code constant:** the table is six rows × three columns, fixed by RAW, never modified by gameplay. Same rationale as §6.3 (class_size_adjust) and §5.1.1 (range_of_trade). Citation comment in source.

**Toll values not consumed here.** The toll column is consumed by §9 (market fees calculator), not §7. Same in-code constant exposes `toll_dice_for_class(market_class)` for §9's use.

### 7.2 Pool size — always max

The merchant count at monthly tick is **always the maximum possible value** per the RAW Markets and Merchants dice formula. The previous draft's average/max distinction is dropped; one path, one count.

```gdscript
static func max_merchant_count(market_class: int) -> int:
    var dice_spec: String = MARKETS_AND_MERCHANTS[market_class]["merchants_dice"]
    return DiceUtil.max_value(dice_spec)
```

| Class | Dice | Max merchants |
|---|---|---|
| I | 2d6+2 | 14 |
| II | 2d4+1 | 9 |
| III | 2d4 | 8 |
| IV | 1d4 | 4 |
| V | 1d4-1 | 3 |
| VI | 1d3-1 | 2 |

Pool size is settled by the maximum. The gameplay lever is *visibility*, not count.

### 7.3 Loads per merchant — random per row

For each merchant generated, the `loads_available` is rolled fresh from the RAW dice formula. Both average-count and max-count generation paths roll loads — only the merchant count is averaged/maxed, not the per-merchant loads. This preserves variability across merchants within the same pool.

(Optional v1.1 enhancement: solicit could max loads too. v1 keeps loads random for narrative variety even when the player solicits.)

### 7.4 Monthly refresh — pool generation

`MerchantPoolRepository.process_monthly_refresh_for_campaign` runs at the monthly domain tick and rebuilds the pool for every settlement:

```
For each settlement with market_class in [1..6]:
    1. Determine initial visibility based on domain ownership:
       - If parent_domain_id maps to a domain whose owner is a PC:
            visibility_default = current_calendar_day   (immediate)
       - Else:
            visibility_default = INT_MAX_SENTINEL       (invisible)
    2. Expire/delete all 'active' rows for this settlement (preserve 'manual' source_kind).
    3. Generate N = max_merchant_count(class) merchant rows:
       - merchandise_type     = random roll on Common Merchandise table (§7.7)
       - loads_available      = roll loads_dice for this market class
       - loads_initial        = same value
       - created_at_calendar_day = current_calendar_day
       - expires_at_calendar_day = current_calendar_day + Timekeeping.DAYS_PER_MONTH
       - becomes_visible_calendar_day = visibility_default
       - source_kind          = 'monthly_refresh'
    4. Emit EventBus.merchant_pool_refreshed(settlement_id, new_count).
```

**`INT_MAX_SENTINEL`** is a deliberately-large integer (e.g., 2147483647 or a `Timekeeping`-derived "never" constant) — any value the active campaign's calendar will never reach. Visibility queries filter `WHERE becomes_visible_calendar_day <= current_calendar_day`, so sentinel-valued rows are correctly hidden.

The "expire/delete previous" step ensures the pool has exactly one cohort per settlement. Combined with the 28-day expiration, the pool is fully replaced every monthly tick. No accumulation of stale merchants; no carryover of last-cohort visibility state.

### 7.5 Visibility actions — `solicit_merchants` and `locate_merchandise`

Both actions live in Phase 10B.2 as activity handlers. §7 ships the data paths they invoke.

#### 7.5.1 `solicit_merchants` — staggered reveal of the invisible pool

- **RAW citations:** `rules/acore-campaign-hijinks.xml:679-684` (timing of availability inside the arbitrage step 2) + `rules/ax_campaign_play.xml:949-963` (the player-activity definition).
- **What RAW provides:** Ongoing 1-3 week minor unstrenuous activity. Half the merchants (rounded up) become interested in the first week; one quarter (rounded down, minimum 1) in the second week; the remainder in the third week. Domain owner has access to maximum merchants without rolling.
- **Project resolution:** in the revised model, the pool is already generated at max count by the monthly tick. `solicit_merchants` doesn't generate merchants — it sets their `becomes_visible_calendar_day` on a staggered schedule:

```
On solicit_merchants activity start (Phase 10B.2 invokes):
    1. Verify the character has entered the market.
    2. Read all 'active' merchants for this settlement where
       becomes_visible_calendar_day = INT_MAX_SENTINEL (invisible).
    3. If no invisible merchants exist: reject the action
       ("Pool already revealed — nothing to solicit").
    4. Compute the RAW thirds across the invisible set N:
       - first_half     = ceili(N / 2.0)
       - second_quarter = maxi(floori(N / 4.0), 1)
       - remainder      = N - first_half - second_quarter   (may be 0 if N is small)
    5. Sort the invisible merchants by id (deterministic).
    6. Assign becomes_visible_calendar_day:
       - merchants[0 .. first_half - 1]:                    solicit_day + 7
       - merchants[first_half .. first_half + second_quarter - 1]: solicit_day + 14
       - merchants[first_half + second_quarter .. end]:     solicit_day + 21
    7. Emit EventBus.solicitation_started(settlement_id, character_id, merchant_count: N).
```

**Edge case: tiny pools.** For market class VI (max=2), the thirds calculation gives first_half=1, second_quarter=1, remainder=0. Both merchants get assigned reveal weeks (1 and 2). Math holds without special-casing.

**Edge case: N=1.** first_half=1, second_quarter=max(0,1)=1 BUT second_quarter index would exceed N. Implementation must clamp — if first_half consumes all merchants, skip the rest. Pseudocode handles this naturally by sorting and assigning by index range.

**Re-solicit handling.** Because monthly refresh wipes the cohort and resets all merchants to invisible, the next `solicit_merchants` after refresh sees a fresh invisible set and works normally. Within a cohort, a second `solicit_merchants` call finds zero invisible merchants and rejects. No explicit `last_solicit_calendar_day` tracking column needed — the visibility state of the cohort IS the solicit state.

**Cohort lifecycle implication.** A solicit at day 7 of a cohort completes its full reveal by day 28 (= same day the cohort expires and refreshes). A solicit at day 21 has only week-1 reveal (day 28) before the cohort wipes. The early-solicit advantage is intrinsic to the cohort lifecycle.

#### 7.5.2 `locate_merchandise` — targeted reveal of an invisible X-carrier

- **RAW grounding:** `rules/acore-campaign-hijinks.xml:707-715` (the "finding specific goods" subsection of arbitrage step 3) provides the conceptual basis — RAW says merchants can be persuaded to deal in specific merchandise. v1 splits this: `locate_merchandise` surfaces invisible merchants who already carry the type; `persuade_merchants` (Phase 10B.2) handles reaction rolls on visible merchants of other types. Both actions cover RAW's "find specific goods" intent without overlap. Neither spawns new merchants — alter-not-spawn is the RAW-faithful read.
- **Activity shape:** minor singular unstrenuous, 1 hour of game time (per Jedidiah 2026-05-12; the time represents asking around the market for a specific merchandise type).
- **Data path:**

```
On locate_merchandise(settlement_id, merchandise_type, current_calendar_day):
    1. Search the active pool at this settlement:
       - Visible matches: rows with merchandise_type=X AND becomes_visible_calendar_day <= current_calendar_day
       - Invisible matches: rows with merchandise_type=X AND becomes_visible_calendar_day > current_calendar_day
    2. If any visible match exists:
       - Return {success: true, merchant_id: <first_visible_id>, surfaced_now: false}
       - No-op effect; the player already knew about this merchant.
    3. Else if any invisible match exists:
       - Surface ONE: set becomes_visible_calendar_day = current_calendar_day on the first invisible row.
       - Emit EventBus.merchant_surfaced_via_locate(merchant_id, settlement_id, merchandise_type).
       - Return {success: true, merchant_id: <surfaced_id>, surfaced_now: true}
    4. Else (no merchant of type X exists in the pool):
       - Return {success: false, error: "no_merchant_of_type", merchant_id: ""}
       - The action's 1 hour was still spent (game time advances).
```

**Surfacing one merchant per call.** If the pool has multiple invisible merchants carrying X (rare but possible — e.g., Class I might roll 2 silk merchants), each call surfaces ONE additional. Player can chain calls (cost: 1 hour each) to surface more. This is consistent with the "spend time asking around" framing.

**No spawn in v1.** If the pool has no merchant of type X at all (visible or invisible), the action fails. RAW does not provide a mechanism to spawn a new merchant; we don't either. `[NEEDS-MERCHANT-SOURCING-PASS]` source flag for the future enhancement (e.g., import a merchant via a connected trade route).

**Fall-through to persuade_merchants.** When `locate_merchandise` fails, the UI should suggest `persuade_merchants` as the next option: the player can attempt to convince a visible merchant of a *different* type to broker X via reaction roll (Phase 10B.2's responsibility).

### 7.6 Merchandise distribution per merchant

- **RAW citation:** `rules/acore-campaign-hijinks.xml:704-705`. "Each merchant buys and sells only one type of merchandise. Roll on the Common Merchandise table to determine each merchant's merchandise category."
- **What RAW provides:** for each merchant generated, roll d100 on the Common Merchandise table (`acore-campaign-hijinks.xml:915-947`); a 86-100 result dispatches to the Precious Merchandise table.
- **Project resolution:** `MerchandiseRegistry.random_common(rng)` (§2.7) handles this in one call, including the precious dispatch and the dispatcher-row resolution for `animals` / `mounts`. Each merchant's `merchandise_type` is the result of that call.

#### 7.6.1 Project-design tension — demand-modifier weighting

The handoff doc's §5.C originally proposed weighting merchandise distribution by `abs(demand_modifier)`: merchants gravitate toward goods with strong demand signals. I considered this for v1 but rejected it.

**Reasoning.** The demand modifier already prices in local-economy flavor — a vineyard town's -3 demand for wine produces low wine *prices* (via §6's formula), which is the realistic effect. A vineyard town doesn't need a higher *probability* of merchants carrying wine; it just needs anyone buying wine to pay less for it. Uniform d100 distribution + demand-modifier-driven pricing is internally consistent.

**Resolution.** Use pure RAW d100 distribution per `MerchandiseRegistry.random_common`. If playtest reveals settlements have weird merchandise availability gaps (e.g., a salt-mining domain happens to roll zero salt-carrying merchants), revisit. `[NEEDS-DISTRIBUTION-CALIBRATION]` flag in source.

### 7.7 Merchant expiration

- **RAW citation:** None — RAW is silent on merchant lifecycle. Q-MERC-5 [RESOLVED] confirms project-design call.
- **Resolution.** Each merchant row carries `expires_at_calendar_day = created_at_calendar_day + Timekeeping.DAYS_PER_MONTH` (28 days). Expiration is processed by `MerchantPoolRepository.process_expirations` on the monthly tick (just before fresh generation) and on any solicit_merchants completion. Expired rows are deleted (not just status-flagged) since the pool's data integrity doesn't need their preservation.

#### 7.7.1 Within-month transactional depletion

A merchant row can also reach `loads_available = 0` mid-month if a player transacts heavily. `MerchantPoolRepository.consume_loads(merchant_id, loads_count)` decrements the row; if it reaches zero, status flips to `'depleted'`. Depleted merchants no longer participate in `list_merchants_for_merchandise` but stay in the table until expiration / refresh — preserving the audit trail of "what did this merchant carry, and was it bought out?" for ledger / UI surfacing.

### 7.8 Schema — `merchant_pool` table

New table, migration 097 sub-step 11:

```sql
CREATE TABLE IF NOT EXISTS merchant_pool (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_entrance_id          TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    loads_available                 INTEGER NOT NULL DEFAULT 0,
    loads_initial                   INTEGER NOT NULL DEFAULT 0,
    created_at_calendar_day         INTEGER NOT NULL DEFAULT 0,
    expires_at_calendar_day         INTEGER NOT NULL DEFAULT 0,
    becomes_visible_calendar_day    INTEGER NOT NULL DEFAULT 2147483647,
    status                          TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'depleted', 'expired')),
    source_kind                     TEXT    NOT NULL DEFAULT 'monthly_refresh'
        CHECK(source_kind IN ('monthly_refresh', 'manual')),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_merchant_pool_settlement_status ON merchant_pool(settlement_entrance_id, status);
CREATE INDEX idx_merchant_pool_settlement_merchandise ON merchant_pool(settlement_entrance_id, merchandise_type, status);
CREATE INDEX idx_merchant_pool_expiration ON merchant_pool(expires_at_calendar_day, status);
CREATE INDEX idx_merchant_pool_visibility ON merchant_pool(settlement_entrance_id, becomes_visible_calendar_day);
```

**Field rationale:**

- `id` — UUID generated by CampaignRepository.
- `merchandise_type` — the snake_case key from MerchandiseRegistry; one merchant carries one type per RAW.
- `loads_available` — decrements as the player transacts; reaches 0 → status='depleted'.
- `loads_initial` — the original rolled value at generation; preserved for audit/UI display ("merchant arrived with 12 loads, has 4 left").
- `created_at_calendar_day` + `expires_at_calendar_day` — 28-day window (`Timekeeping.DAYS_PER_MONTH`) enforced by the expiration processor.
- `becomes_visible_calendar_day` — the visibility gate. Default `2147483647` (INT32_MAX, the sentinel for "invisible until something reveals me"). PC-owned-domain monthly refresh writes `current_calendar_day` here at generation. `solicit_merchants` writes `solicit_day + 7 / +14 / +21` per the staggered reveal. `locate_merchandise` writes `current_calendar_day` to a single surfaced row.
- `status` — three terminal states. `'active'` is consumable; `'depleted'` and `'expired'` are non-consumable but preserved for audit.
- `source_kind` — provenance. The previous `'solicit_merchants'` value is removed (solicit no longer creates rows, only flips visibility). `'manual'` reserved for Judge-authored merchants (e.g., a scripted plot merchant that doesn't get wiped on monthly refresh).

**No `last_solicit_calendar_day` column on `settlement_entrances`** — dropped from the previous draft. The per-merchant visibility state captures solicit state directly: if any merchant in the active cohort has `becomes_visible_calendar_day != 2147483647`, that cohort has been solicited. The previous migration 097 sub-step 12 (adding this column) is removed. **Migration 097 sub-step count returns to 11** (down from 12).

### 7.9 `MerchantPoolRepository` API

`engine/subsystems/commerce/merchant_pool_repository.gd` — `RefCounted` static-function library.

```gdscript
class_name MerchantPoolRepository
extends RefCounted

const INVISIBLE_SENTINEL := 2147483647   # becomes_visible_calendar_day for invisible

# Read API — VISIBILITY-AWARE
static func list_visible_merchants(settlement_id: String, current_calendar_day: int) -> Array
    # Returns 'active' merchants with becomes_visible_calendar_day <= current_calendar_day.
static func list_visible_merchants_for_merchandise(
    settlement_id: String, merchandise_type: String, current_calendar_day: int
) -> Array
    # Filtered by merchandise_type AND visibility.
static func list_invisible_merchants(settlement_id: String, current_calendar_day: int) -> Array
    # 'active' merchants with becomes_visible_calendar_day > current_calendar_day.
    # Used by solicit_merchants and locate_merchandise to find candidates.
static func get_merchant(merchant_id: String) -> Dictionary

# Write API — pool generation
static func generate_pool_for_settlement(
    settlement_id: String,
    current_calendar_day: int,
    rng: RandomNumberGenerator,
    pc_owned: bool,                # if true, all new merchants are immediately visible
) -> int
    # Wipes existing 'active' rows (preserves source_kind='manual'); generates
    # max_merchant_count(class) merchants with random merchandise and rolled loads.
    # Visibility set per pc_owned. Returns count of merchants generated.
static func consume_loads(merchant_id: String, loads_count: int) -> bool
    # Decrements loads_available; flips status to 'depleted' at 0.

# Monthly tick driver
static func process_monthly_refresh_for_campaign(
    campaign_id: String,
    current_calendar_day: int,
    rng: RandomNumberGenerator,
) -> int
    # For each settlement in campaign:
    #   1. Resolve pc_owned via the parent domain's owner_character_id.
    #   2. Call process_expirations.
    #   3. Call generate_pool_for_settlement(settlement_id, day, rng, pc_owned).
    # Returns total merchants generated.

# Expiration processor
static func process_expirations(settlement_id: String, current_calendar_day: int) -> int
    # Deletes rows with expires_at_calendar_day < current_calendar_day and status='active'.

# Visibility actions (Phase 10B.2 handlers invoke these)
static func process_solicitation(
    settlement_id: String,
    character_id: String,
    current_calendar_day: int,
) -> Dictionary
    # Returns {success: bool, error: String, merchants_revealed: int}
    # Reads invisible merchants; assigns becomes_visible_calendar_day per the
    # half/quarter/remainder schedule (solicit_day + 7/+14/+21). Per §7.5.1.
    # Rejects if no invisible merchants exist (already solicited or PC-owned).

static func process_locate(
    settlement_id: String,
    merchandise_type: String,
    current_calendar_day: int,
) -> Dictionary
    # Returns {success: bool, error: String, merchant_id: String, surfaced_now: bool}
    # Per §7.5.2 algorithm: visible match → no-op success; invisible match →
    # surface ONE; no match → fail.

# Helpers
static func max_merchant_count(market_class: int) -> int       # §7.2
static func toll_dice_for_class(market_class: int) -> String   # consumed by §9
```

The previous `average_merchant_count` helper is dropped (no longer used).

### 7.10 Activity handler interfaces (Phase 10B.2 implements)

The Phase 10B.2 Trade block ships the activity handlers at:
- `engine/subsystems/activities/handlers/mercantile/solicit_merchants.gd`
- `engine/subsystems/activities/handlers/mercantile/locate_merchandise.gd`

§7 specifies the data-layer interface those handlers consume:

```gdscript
# solicit_merchants.gd (Phase 10B.2):
func on_started(activity_state: Dictionary, current_calendar_day: int) -> void:
    # Note: solicit's staggered reveal is set at START (so week-1 reveal at
    # solicit_day+7 is honored even if the activity completes earlier than
    # planned). ActivityTimeCostExecutor still tracks the 3-week duration
    # for follower wages, time costs, etc.
    var settlement_id: String = activity_state.get("settlement_id", "")
    var character_id: String = activity_state.get("character_id", "")
    var result: Dictionary = MerchantPoolRepository.process_solicitation(
        settlement_id, character_id, current_calendar_day
    )
    if not result["success"]:
        push_warning("solicit_merchants rejected: %s" % result["error"])

# locate_merchandise.gd (Phase 10B.2):
func on_completed(activity_state: Dictionary, current_calendar_day: int) -> void:
    var settlement_id: String = activity_state.get("settlement_id", "")
    var merchandise_type: String = activity_state.get("merchandise_type", "")
    var result: Dictionary = MerchantPoolRepository.process_locate(
        settlement_id, merchandise_type, current_calendar_day
    )
    # UI displays result.success / surfaced_now to the player.
```

This GDD's responsibility ends at the repository functions. Activity registration, eligibility checks, time costs, and UI live in Phase 10B.2.

### 7.11 EventBus signals

Added to `engine/autoloads/event_bus.gd` (in §14's consolidated additions):

```gdscript
signal merchant_pool_refreshed(settlement_id: String, new_merchant_count: int)
signal solicitation_started(settlement_id: String, character_id: String, merchants_revealed_count: int)
signal merchant_surfaced_via_locate(merchant_id: String, settlement_id: String, merchandise_type: String)
signal merchant_loads_consumed(merchant_id: String, loads_consumed: int, loads_remaining: int)
signal merchant_depleted(merchant_id: String, settlement_id: String)
signal merchant_expired(merchant_id: String, settlement_id: String)
```

Previous `solicitation_completed` is replaced by `solicitation_started` because the reveal schedule is set at the action's *start* (not completion). The week-1/2/3 boundaries are driven by `becomes_visible_calendar_day` reaching `current_calendar_day`, not by activity-completion events.

### 7.12 Tests

`tests/test_merchant_pool_repository.gd` budget: **~16 tests.**

1. **`max_merchant_count` table.** Class I → 14; II → 9; III → 8; IV → 4; V → 3; VI → 2.
2. **`generate_pool_for_settlement` pc_owned=true.** Class III fixture. After call: 8 merchants generated, all with `becomes_visible_calendar_day == current_calendar_day` (immediately visible).
3. **`generate_pool_for_settlement` pc_owned=false.** Class III fixture. 8 merchants generated, all with `becomes_visible_calendar_day == 2147483647` (invisible sentinel).
4. **`list_visible_merchants` filters correctly.** Mixed pool with some visible, some invisible. `list_visible_merchants` returns only the visible subset; `list_invisible_merchants` returns only the invisible.
5. **Merchandise distribution.** Generate a pool of 100 merchants (Class I × max + repeated runs). Histogram of merchandise types roughly matches `MerchandiseRegistry.random_common` (uniform d100).
6. **`consume_loads` decrement.** Merchant with `loads_available=10`. consume_loads(3) → loads_available=7, status='active'.
7. **`consume_loads` depletion.** loads_available=5. consume_loads(5) → loads_available=0, status='depleted'.
8. **`consume_loads` insufficient.** loads_available=3. consume_loads(5) → returns false; row unchanged.
9. **Generation wipes previous active rows.** Generate twice in succession → second generation has only the latest cohort's rows in 'active'; previous rows deleted.
10. **Generation preserves manual rows.** Insert a row with source_kind='manual'. Generate → manual row is unaffected; other 'active' rows replaced.
11. **`process_expirations` deletes overdue.** Row with `expires_at_calendar_day=10`, current=15 → deleted. Row with `expires_at_calendar_day=20`, current=15 → preserved.
12. **`process_solicitation` staggered reveal.** Class III pool (8 invisible). After solicit at day 0: 4 merchants have `becomes_visible_calendar_day=7`, 2 have `=14`, 2 have `=21`. (4 = ceil(8/2); 2 = max(floor(8/4), 1); remainder = 2.)
13. **`process_solicitation` rejects when nothing invisible.** Pool fully visible (e.g., PC-owned domain). Solicit → success=false, error mentioning "already revealed."
14. **`process_solicitation` small pool (Class VI, N=2).** Both merchants get assigned: 1 at day+7, 1 at day+14, 0 at day+21. No crash on tiny pool.
15. **`process_locate` finds visible match.** Pool has a visible silk merchant. `process_locate(settlement, 'silk', day)` → success=true, surfaced_now=false, merchant_id set.
16. **`process_locate` surfaces invisible match.** Pool has only invisible silk merchants. `process_locate(settlement, 'silk', day)` → success=true, surfaced_now=true; that merchant's `becomes_visible_calendar_day` is now `day`.
17. **`process_locate` fails when no match.** Pool has no silk merchant. `process_locate(settlement, 'silk', day)` → success=false, error mentioning "no_merchant_of_type."
18. **Monthly refresh — pc_owned detection.** Fixture: settlement A with PC-owned parent domain; settlement B with NPC-owner parent domain. `process_monthly_refresh_for_campaign` → A's merchants all immediately visible; B's all invisible.

### 7.13 What §7 does NOT add

- **No persuade_merchants reaction-roll logic.** That's Phase 10B.2 (the Trade block's persuade-merchants activity). RAW step 3's reaction-roll mechanism (9+/12+, ±demand, +3 monopolist, one roll per merchant, fail = merchant permanently lost) operates on visible merchants of OTHER types and is complementary to `locate_merchandise` (which targets invisible merchants of the desired type). §7 ships the visible-pool data; 10B.2 ships the reaction-roll handler.
- **No merchant spawning via `locate_merchandise`.** Per §7.5.2, RAW alters existing merchants only; we honor that. If no merchant of the desired type exists in the pool, the action fails. `[NEEDS-MERCHANT-SOURCING-PASS]` flag if a future enhancement wants to import merchants via connected trade routes (§5).
- **No price calculation per merchant.** Per §6.1.1, all merchants in a settlement transact at the same market price for the same merchandise. The merchant pool doesn't carry per-merchant prices.
- **No demand-modifier-weighted distribution.** §7.6.1 explains the design choice. `[NEEDS-DISTRIBUTION-CALIBRATION]` flag for revisit if playtest shows availability gaps.
- **No NPC merchant migration between settlements.** Per Q-MERC handoff §5.G, this is deferred to v1.1+. Merchants in v1 are stationary; they spawn at one settlement, sell loads or expire, vanish.
- **No precious-merchandise probability tuning.** Per RAW, 15% of merchant rolls (86-100 on d100) go to precious. This is the RAW value; we don't alter it. If precious access feels too rare or too common, revisit with a `[NEEDS-PRECIOUS-RATE-PASS]` flag.
- **No per-character or per-party visibility tracking.** Visibility state is per-merchant, settlement-wide. If two parties visit the same settlement (rare in single-PC ACKS Arbiter campaigns), they see the same merchant visibility. v1.1+ could add per-party state if needed.
- **No `solicit_merchants` cooldown column.** The previous draft added `last_solicit_calendar_day` to `settlement_entrances`; removed in this revision because the per-merchant `becomes_visible_calendar_day` state captures solicit progress. Migration 097 sub-step count returns to 11.

---

## §8. Market Fees Calculator

### 8.0 Overview

This section encodes the per-transaction and per-day fees the player pays at a market: entry toll, customs duty on selling, loading/unloading labor, ship moorage, stabling, and the domain-owner exemption from all of them. The fees calculator is a stateless pure-function library — no schema, no persistence. Consumers (Phase 10B.2's buy_sell_merchandise handler, plus any caller that simulates a market visit) invoke the helpers with the relevant inputs and get gp totals back.

The fee math is deliberately separated from the price formula (§6) and the merchant pool (§7) because fees have a different cadence and a different exemption rule — they vary by transaction or by stay duration, not by demand modifier.

### 8.1 RAW citations

| Fee | RAW source |
|---|---|
| Entry toll | `rules/acore-campaign-hijinks.xml:647-650, 660` (Markets and Merchants toll column) |
| Toll minimum when selling | `rules/acore-campaign-hijinks.xml:649` ("Characters entering to sell always pay a minimum toll of 1gp per load") |
| Customs duty (on selling) | `rules/acore-campaign-hijinks.xml:751-754` (2d10% of market price) |
| Loading / unloading labor | `rules/acore-campaign-hijinks.xml:746-750` (1gp per 200 stone) |
| Ship moorage | `rules/acore-campaign-hijinks.xml:687-689` (1gp per 10 SHP per day) |
| Mule stabling | `rules/acore-campaign-hijinks.xml:690` (2sp per mule per day) |
| Horse stabling | `rules/acore-campaign-hijinks.xml:691` (5sp per horse per day) |
| Cart stabling | `rules/acore-campaign-hijinks.xml:692` (1gp per cart per day) |
| Wagon stabling | `rules/acore-campaign-hijinks.xml:693` (2gp per wagon per day) |
| Domain-owner exemption | `rules/acore-campaign-hijinks.xml:697-699` (no toll / moorage / stabling for owner in own domain) |

### 8.2 Currency convention

All fee helpers return integer **gp** values. Internally, computations that produce fractional gp (loading fee where total_stone is not a multiple of 200; mule stabling at 2sp = 0.2 gp; etc.) **aggregate before rounding** — banker's rounding (`RoundingUtil.banker_round`) applied once at the end of the call.

Aggregation-then-round vs. per-unit-round example: 5 mules × 5 days at 2sp/day = 25 mule-days × 0.2 gp = 5.0 gp (exact). Per-unit-round at 0.2 gp → 0 gp per mule-day → 0 gp total (catastrophic underbilling). The calculator never rounds per-unit; it rounds the aggregate.

Where fees are inherently integer (cart at 1gp/day, wagon at 2gp/day), no rounding is involved.

### 8.3 Entry toll

- **RAW citation:** `rules/acore-campaign-hijinks.xml:647-650` plus the per-class toll dice in the Markets and Merchants table at L660 (already encoded in §7.1's `MARKETS_AND_MERCHANTS` constant).
- **What RAW provides:** per-class dice toll (e.g., 1d6+15 gp for Class I, 1d3 gp for Class VI). Plus a minimum-1gp-per-load floor when selling.
- **Implementation:**

```gdscript
static func entry_toll_gp(
    market_class: int,
    is_selling: bool,
    merchandise_loads: int,        # total loads being sold (0 if buying-only or visit-only)
    rng: RandomNumberGenerator,
) -> int:
    var dice_spec: String = MerchantPoolRepository.toll_dice_for_class(market_class)
    var rolled: int = DiceUtil.roll(dice_spec, rng)   # e.g. rolls 1d6+15 → 16..21
    if is_selling:
        var minimum: int = maxi(merchandise_loads, 0)  # 1gp × loads
        return maxi(rolled, minimum)
    return rolled
```

**Per-entry, not per-stay.** RAW: "Each time adventurers enter a market to buy or sell goods, they must pay a toll." If the player exits and re-enters, the toll fires again. The activity layer (Phase 10B.2's buy_sell handler) is responsible for tracking entry events.

### 8.4 Customs duty (selling only)

- **RAW citation:** `rules/acore-campaign-hijinks.xml:751-754`.
- **What RAW provides:** "Adventurers selling goods also pay customs duty equal to 2d10% of the market price."
- **What's missing:** RAW's plain reading is "roll 2d10% per sell transaction." Per Jedidiah 2026-05-12, the project resolves this as a **once-per-year-per-settlement** roll instead — the customs rate is a stable annual property of the settlement, not a per-transaction variable. Rationale: customs rates reflect long-term tariff policy (set by the settlement's governing authority for fiscal year planning), not transaction-by-transaction caprice. The 2-20% range stays.
- **Project resolution:**
  - Each `settlement_entrances` row carries a `customs_duty_rate_pct INTEGER NOT NULL DEFAULT 0` column (added by migration 097 sub-step 12).
  - The rate is rolled on **day 1 of month 1 of each year** (the calendar's year-start). Roll is `1d10 + 1d10` (range 2-20).
  - Roll is deterministic — seeded RNG keyed on `(settlement_id, current_year, "customs")`. Same year + same settlement → same rate. Replayability and audit are preserved.
  - On settlement creation mid-year, the initial rate is rolled with the same seeding logic against the current year.
  - On migration 097 application, every existing settlement gets a backfilled rate using `(settlement_id, current_year)` seeding (one-time upgrade pass; subsequent year-rolls follow the normal cadence).
  - **Smuggling still bypasses customs entirely** (RAW L753); Phase 10B.3's smuggling handler doesn't query this calculator.

- **Implementation:**

```gdscript
static func customs_duty_gp(
    market_price_gp: int,
    settlement_id: String,
    is_domain_owner: bool = false,
) -> int:
    if is_domain_owner:
        return 0   # Per §8.8 — customs IS in the exemption set
    var rate_pct: int = CampaignRepository.get_settlement_customs_rate_pct(settlement_id)
    return RoundingUtil.banker_round(float(market_price_gp) * float(rate_pct) / 100.0)

static func roll_annual_customs_rate(settlement_id: String, year: int) -> int:
    # Deterministic 1d10 + 1d10, seeded on settlement + year.
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(settlement_id + "|" + str(year) + "|customs")
    return rng.randi_range(1, 10) + rng.randi_range(1, 10)

static func process_annual_customs_roll_for_campaign(
    campaign_id: String,
    current_year: int,
) -> int:
    # For each settlement in campaign, re-rolls customs_duty_rate_pct via
    # roll_annual_customs_rate(settlement_id, current_year). Returns count
    # of settlements updated. Called at calendar year boundary by the
    # DomainMonthlyResolver when current_month==1 and the year has advanced
    # since last invocation (de-dup guard against re-firing within the same
    # year).
```

**Year-roll trigger point:** `DomainMonthlyResolver` (existing infrastructure) fires every monthly tick. When that tick lands on month 1 of a year not yet processed, the resolver invokes `process_annual_customs_roll_for_campaign`. A `last_customs_roll_year INTEGER NOT NULL DEFAULT 0` column on `campaigns` (migration 097 sub-step 13) prevents double-firing in the same year if the player advances time across month boundaries multiple times.

**Why deterministic seeding.** A campaign-load reproduces the same customs rates the campaign-save knew. A future Judge auditing "why is silk so cheap to ship out of Ashford?" can reproduce the rate from settlement_id + year + "customs" string and verify the value. No surprise drift across save/load.

**Charged on each sell transaction**, not per load — `market_price_gp` is the total (= loads × gp_per_load from §6) and the rate applies to that aggregate.

### 8.5 Loading and unloading labor

- **RAW citation:** `rules/acore-campaign-hijinks.xml:746-750`.
- **What RAW provides:** "When buying goods, adventurers pay labor fees to load them. When selling goods, adventurers pay labor fees to unload them. 1gp per 200 stone of merchandise."
- **Implementation:**

```gdscript
static func labor_fee_gp(total_stone: int) -> int:
    # 1gp per 200 stone. Aggregate-then-round.
    return RoundingUtil.banker_round(float(total_stone) / 200.0)
```

Examples:
- 80 stone (one Class-I-grain load) → 0.4 gp → 0 gp (banker rounds 0.4 toward 0).
- 200 stone (one salt load) → 1.0 gp → 1 gp.
- 400 stone → 2.0 gp → 2 gp.
- 3,760 stone (47 grain loads) → 18.8 gp → 19 gp.

Charged once on buying (loading) AND once on selling (unloading); the same call serves both directions. The activity-layer caller decides which event triggers the fee.

**Note on small loads.** Below 100 stone, banker rounds the result to 0 — the labor cost is "below threshold." This matches RAW's per-200-stone granularity: a single 30-stone hides load incurs no labor fee. The caller can choose to display "<1 gp" rather than "0 gp" in UI if desired, but the gp-debit value is 0.

### 8.6 Ship moorage

- **RAW citation:** `rules/acore-campaign-hijinks.xml:687-689`.
- **What RAW provides:** "1gp per 10 structural hit points per day."
- **Implementation:**

```gdscript
static func moorage_gp_per_day(ship_shp: int) -> int:
    # 1gp per 10 SHP. Aggregate-then-round per-day.
    return RoundingUtil.banker_round(float(ship_shp) / 10.0)

static func moorage_gp_total(ship_shp: int, days: int) -> int:
    # Multi-day total. Roundsthe per-day rate then multiplies, OR
    # multiplies first then rounds — RAW is silent. Project resolution:
    # multiply first, round once.
    return RoundingUtil.banker_round(float(ship_shp) * float(days) / 10.0)
```

Examples:
- 5 SHP ship × 7 days = 35 SHP-days → 3.5 gp → 4 gp.
- 30 SHP ship × 14 days = 420 SHP-days → 42 gp.

§9-companion note: ship persistence (Q-MERC-16) is in scope for §10 (vehicles). Once ships are persisted, the moorage calculator reads `ships.shp_current` and iterates active berthing periods.

### 8.7 Stabling

- **RAW citation:** `rules/acore-campaign-hijinks.xml:690-693`.
- **Rates** (RAW where cited; project-design fill for animals RAW is silent on, per Jedidiah 2026-05-12):

| Animal/Vehicle | Daily fee | Source |
|---|---|---|
| Mule | 2 sp = 0.2 gp | RAW L690 |
| Donkey | 2 sp = 0.2 gp | Project (donkey ≈ mule, per Jedidiah) |
| Horse | 5 sp = 0.5 gp | RAW L691 |
| Camel | 5 sp = 0.5 gp | Project (camel ≈ horse, per Jedidiah) |
| Ox | 8 sp = 0.8 gp | Project (distinct rate per Jedidiah — between horse and cart, reflecting bulkier accommodation) |
| Cart | 1 gp | RAW L692 |
| Wagon | 2 gp | RAW L693 |

- **Implementation:**

```gdscript
const STABLING_RATES_GP_PER_DAY := {
    "mule":   0.2,
    "donkey": 0.2,
    "horse":  0.5,
    "camel":  0.5,
    "ox":     0.8,
    "cart":   1.0,
    "wagon":  2.0,
}

static func stabling_gp_per_day(mounts: Dictionary) -> int:
    # mounts = {"mule": n, "horse": n, "ox": n, "cart": n, ...}
    var total: float = 0.0
    for key in mounts:
        var rate: float = STABLING_RATES_GP_PER_DAY.get(key, 0.0)
        total += float(mounts[key]) * rate
    return RoundingUtil.banker_round(total)

static func stabling_gp_total(mounts: Dictionary, days: int) -> int:
    # Multiply totals first, round once.
    var per_day_raw: float = 0.0
    for key in mounts:
        var rate: float = STABLING_RATES_GP_PER_DAY.get(key, 0.0)
        per_day_raw += float(mounts[key]) * rate
    return RoundingUtil.banker_round(per_day_raw * float(days))
```

Examples:
- `{"mule": 5, "horse": 2}` for 1 day → 5×0.2 + 2×0.5 = 2.0 gp → 2 gp.
- `{"horse": 1}` for 1 day → 0.5 gp → 0 gp (banker — 0.5 rounds to even 0).
- `{"horse": 1}` for 2 days → 1.0 gp → 1 gp.
- `{"horse": 1}` for 7 days → 3.5 gp → 4 gp.
- `{"ox": 4}` for 7 days → 4×0.8×7 = 22.4 gp → 22 gp.
- `{"wagon": 3}` for 14 days → 84.0 gp → 84 gp.

**Unknown mount keys default to 0 cost.** A caller passing `{"warhorse": 2}` against this lookup table would get 0 — the key isn't recognized. This is defensive (no crash on unrecognized keys) but means the caller is responsible for mapping their domain vocabulary (e.g., `heavy_warhorse` from `data/equipment/transport.json`) to one of the seven stabling keys. The mapping convention: warhorses stable as horses (`"horse"`), draft horses as horses, riding horses as horses. If a future ACKS supplement adds a specialty stable rate (e.g., griffon roost), add the row here.

### 8.8 Domain-owner exemption

- **RAW citation:** `rules/acore-campaign-hijinks.xml:697-699`.
- **What RAW provides:** "An adventurer buying and selling in a domain he controls always has access to the maximum number of merchants and pays no moorage, stabling fees, or tolls."
- **Project extension** (per Jedidiah 2026-05-12): customs duty is **also** included in the domain-owner exemption. RAW's literal enumeration is narrower, but the project rule treats customs as part of the same "owner doesn't pay fees in their own domain" principle.
- **Note:** the "maximum merchants" portion is encoded in §7.4 (PC-owned-domain settlements get immediate-visibility max-count pool). §8 handles the fee-exemption portion.

The exemption applies to:
- Entry toll (yes)
- Customs duty (yes — project extension)
- Moorage (yes)
- Stabling (yes)

The exemption does **NOT** apply to:
- Loading/unloading labor (labor is paid to workers, not to the settlement's authority — the domain owner pays his own labor force just like anyone else)

**Implementation pattern.** Each exempt-fee helper accepts an `is_domain_owner: bool` parameter and returns 0 when applicable:

```gdscript
static func entry_toll_gp(
    market_class: int,
    is_selling: bool,
    merchandise_loads: int,
    rng: RandomNumberGenerator,
    is_domain_owner: bool = false,
) -> int:
    if is_domain_owner:
        return 0
    # ... rest of the formula
```

Same pattern for `customs_duty_gp`, `moorage_gp_per_day`, `moorage_gp_total`, `stabling_gp_per_day`, and `stabling_gp_total`. The labor fee helper does not accept the flag.

A convenience helper for the caller's monopoly/domain check:

```gdscript
static func is_domain_owner_in_own_market(character_id: String, settlement_id: String) -> bool:
    # Returns true iff:
    #   - settlement.parent_domain_id is not null
    #   - domains.owner_character_id == character_id
    # Otherwise false.
    var settlement: Dictionary = CampaignRepository.get_settlement_entrance(settlement_id)
    var domain_id: String = settlement.get("parent_domain_id", "")
    if domain_id == "":
        return false
    var domain: Dictionary = CampaignRepository.get_domain(domain_id)
    return domain.get("owner_character_id", "") == character_id
```

### 8.9 `MarketFeesCalculator` service API

`engine/subsystems/commerce/market_fees_calculator.gd` — `RefCounted` static-function library. No state, no schema.

```gdscript
class_name MarketFeesCalculator
extends RefCounted

# Per-transaction fees
static func entry_toll_gp(
    market_class: int,
    is_selling: bool,
    merchandise_loads: int,
    rng: RandomNumberGenerator,
    is_domain_owner: bool = false,
) -> int

static func customs_duty_gp(
    market_price_gp: int,
    settlement_id: String,
    is_domain_owner: bool = false,
) -> int

static func labor_fee_gp(total_stone: int) -> int   # No domain-owner exemption per §8.8

# Per-day fees
static func moorage_gp_per_day(ship_shp: int, is_domain_owner: bool = false) -> int
static func moorage_gp_total(ship_shp: int, days: int, is_domain_owner: bool = false) -> int
static func stabling_gp_per_day(mounts: Dictionary, is_domain_owner: bool = false) -> int
static func stabling_gp_total(mounts: Dictionary, days: int, is_domain_owner: bool = false) -> int

# Annual customs roll (per §8.4)
static func roll_annual_customs_rate(settlement_id: String, year: int) -> int
static func process_annual_customs_roll_for_campaign(campaign_id: String, current_year: int) -> int

# Domain-owner predicate
static func is_domain_owner_in_own_market(character_id: String, settlement_id: String) -> bool
```

### 8.10 Tests

`tests/test_market_fees_calculator.gd` budget: **~14 tests.**

1. **Entry toll: dice range.** `entry_toll_gp(1, false, 0, rng)` returns value in [16, 21] (1d6+15).
2. **Entry toll: selling minimum kicks in.** `entry_toll_gp(6, true, 10, seeded_rng_that_rolls_1)` returns 10 (= 1gp × 10 loads), not 1 (the dice roll).
3. **Entry toll: selling dice exceeds minimum.** `entry_toll_gp(1, true, 5, seeded_rng_that_rolls_16)` returns 16, not 5.
4. **Entry toll: domain-owner exemption.** Same fixture as test 1 but `is_domain_owner=true` → returns 0.
5. **Customs duty: uses cached annual rate.** Fixture: settlement with `customs_duty_rate_pct=15`. `customs_duty_gp(1000, settlement_id)` returns 150 (1000 × 15% = 150).
6. **Customs duty: zero price.** `customs_duty_gp(0, settlement_id)` returns 0 regardless of rate.
7. **Customs duty: domain-owner exemption.** Same fixture as test 5 but `is_domain_owner=true` → returns 0.
7b. **Annual customs roll determinism.** `roll_annual_customs_rate("settle_abc", 1234)` returns the same value on repeat calls. Different settlements at the same year yield different rates; same settlement at different years yields different rates. Range always in [2, 20].
7c. **Annual customs roll: year-trigger.** Fixture: campaign with three settlements, `campaigns.last_customs_roll_year = 1233`. Invoke `process_annual_customs_roll_for_campaign(campaign_id, 1234)` → all three settlement_entrances rows updated to new rates; `last_customs_roll_year` advanced to 1234.
8. **Labor fee: exact multiples.** `labor_fee_gp(200) == 1`; `labor_fee_gp(400) == 2`; `labor_fee_gp(2000) == 10`.
9. **Labor fee: aggregate-then-round.** `labor_fee_gp(100) == 0` (0.5 rounds to even 0); `labor_fee_gp(300) == 2` (1.5 rounds to even 2); `labor_fee_gp(3760) == 19`.
10. **Moorage: per-day formula.** `moorage_gp_per_day(30) == 3`; `moorage_gp_per_day(5) == 0` (banker 0.5 → 0); `moorage_gp_per_day(15) == 2` (banker 1.5 → 2).
11. **Moorage: multi-day aggregate.** `moorage_gp_total(5, 7) == 4` (5×7/10 = 3.5 → 4).
12. **Moorage: domain-owner exemption.** `moorage_gp_total(30, 14, is_domain_owner=true) == 0`.
13. **Stabling: mixed-mount totals.** `stabling_gp_total({"mule": 5, "horse": 2, "wagon": 1}, 7) == ?` (calculate: 5×0.2 + 2×0.5 + 1×2 = 1 + 1 + 2 = 4/day × 7 = 28).
14. **`is_domain_owner_in_own_market` predicate.** Fixture: settlement S has parent_domain D; D.owner = character C. `is_domain_owner_in_own_market(C, S)` → true; `is_domain_owner_in_own_market(other_char, S)` → false; `is_domain_owner_in_own_market(C, settlement_without_parent_domain)` → false.

### 8.11 What §8 does NOT add

- **Minimal schema.** §8 adds two columns (`customs_duty_rate_pct` on settlement_entrances, `last_customs_roll_year` on campaigns) — migration 097 sub-steps 12 and 13. No fee history, no audit table, no per-settlement fee overrides. If a Judge wants to author special fees for a specific settlement, that's currently a manual GP transaction outside this calculator (or a `[NEEDS-FEE-OVERRIDE-PASS]` flag for the future).
- **No labor domain-owner exemption.** Per §8.8 — labor is paid to workers, not to the settlement's authority. Domain owner pays it like everyone else.
- **No buy/sell transaction integration.** Phase 10B.2's buy_sell_merchandise handler calls these helpers; §8 doesn't ship the handler.
- **No smuggling integration.** Phase 10B.3's smuggling hijink bypasses customs/labor; §8 isn't aware.
- **No "negotiate fees" mechanic.** RAW doesn't provide one; v1 doesn't either. The dice-rolled entry toll is paid as rolled, and the annual customs rate is the annual customs rate.
- **No fee variation by reputation or faction.** v1 has uniform fees regardless of player standing with the settlement's faction. `[NEEDS-REPUTATION-FEES-PASS]` if you want reputation-driven discounts.
- **No mid-year customs adjustment.** Once rolled for a year, the rate is fixed for that year. RAW silent on intra-year fluctuation; the annual model is the project's deliberate simplification.

---

## §9. Ships, Cargo Holds, and Cargo Flow

### 9.0 Overview

Per Q-MERC-7 [RESOLVED 2026-05-12], the v1-stub `vehicle_summary` plan is **rescinded** in favor of full vehicle/cargo build. This section ships:

1. **Ships persistence** — a new `ships` table to track per-vessel state (SHP, location, crew, ownership). Land vehicles (carts/wagons) already exist in `draft_vehicles` (migration 024) — this section does NOT rebuild them, it adds the parallel sea vehicle.
2. **Cargo holds** — a new `cargo_holds` table per Q-MERC-17 Option B (sibling-table semantics, not extension-of-inventory_items). Each row = one merchandise-load shipment with provenance, market value at acquisition, and a foreign key to its carrier (either a draft_vehicle or a ship).
3. **Encumbrance integration** — a `CargoEncumbranceCalculator` service computing total carrier load from BOTH `inventory_items` AND `cargo_holds` against the SAME capacity limit (per Jedidiah's Q-MERC-17 requirement: a single wagon cannot track two separate encumbrance limits).
4. **Crew & monthly operating costs** — RAW-cited via the Merchant Ships and Caravans table at `acore-campaign-hijinks.xml:844-911`.
5. **Shipping contracts** — a new `shipping_contracts` table for the RAW passenger-and-cargo-transport mechanic (a separate income stream Phase 10B.2 builds on top).
6. **Hijink → cargo flow data path** — smuggling/stealing hijink yields write to `cargo_holds` with the appropriate `source_acquisition_kind`. Phase 10B.3 handles the activity logic; §9 ships the schema and write helpers.
7. **Multi-leg arbitrage flow data path** — buy at market A, transport (wilderness adventure), sell at market B. The cargo row persists across legs.

What §9 does NOT cover: ship combat (Phase 9 territory), naval movement / wind / weather (deferred — basic wilderness movement covers travel for now), per-crew-member wage disbursement (RAW aggregates this into the monthly cost line; we treat it as a single number).

### 9.1 Existing land-vehicle infrastructure (recap, no changes)

For reference (already shipped as of this session's start):

- **`draft_vehicles` table** (`db/migrations/024_draft_vehicles.sql`) — per-vehicle persistence for carts/wagons. Fields: `id, campaign_id, party_id, item_key, name, hitched_creatures (JSON), is_destroyed`. Item_key references `data/equipment/transport.json` catalog entries (`cart_small`, `cart_large`, `wagon`).
- **`DraftVehicleService`** (`engine/subsystems/characters/draft_vehicle_service.gd`) — capacity calculator. Given (vehicle item_key, draft team of TrainedCreatureData), returns `{load_normal, load_max, speed_normal, speed_loaded}` in stone and feet-per-turn. The capacity is RAW-canonical from `acore_equipment.xml:623-628`.
- **`inventory_items.vehicle_id` FK** — items can be stowed in a draft_vehicle. Existing encumbrance computation sums these by vehicle.
- **`data/equipment/transport.json`** — catalog. Cart-small, cart-large, wagon entries (plus mounts, pack animals, tack, barding).
- **`scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd`** — UI for viewing/managing a vehicle's inventory.

**Mercantile integration:** §9.5's `CargoEncumbranceCalculator` extends the existing encumbrance logic to include cargo_holds in the capacity sum, so a wagon carrying both inventory_items AND cargo_holds is gated by the same `load_normal`/`load_max` cap.

### 9.2 `ships` table — new persistence

Migration 097 sub-step 14:

```sql
CREATE TABLE IF NOT EXISTS ships (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    party_id                        TEXT    REFERENCES parties(id),     -- canonical owner (mirrors draft_vehicles)
    vessel_key                      TEXT    NOT NULL,                   -- references maritime.json catalog
    name                            TEXT    NOT NULL DEFAULT 'Unnamed Vessel',
    shp_max                         INTEGER NOT NULL DEFAULT 0,
    shp_current                     INTEGER NOT NULL DEFAULT 0,
    cargo_capacity_stone            INTEGER NOT NULL DEFAULT 0,
    crew_captain                    INTEGER NOT NULL DEFAULT 0,
    crew_sailors                    INTEGER NOT NULL DEFAULT 0,
    crew_rowers                     INTEGER NOT NULL DEFAULT 0,
    crew_marines                    INTEGER NOT NULL DEFAULT 0,
    monthly_operating_cost_gp       INTEGER NOT NULL DEFAULT 0,         -- from RAW table; see §9.6
    current_location_kind           TEXT    NOT NULL DEFAULT 'moored'
        CHECK(current_location_kind IN ('moored', 'at_sea', 'wrecked')),
    moored_at_settlement_id         TEXT    REFERENCES settlement_entrances(id),
    is_destroyed                    INTEGER NOT NULL DEFAULT 0 CHECK(is_destroyed IN (0, 1)),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_ships_party ON ships(party_id, is_destroyed);
CREATE INDEX idx_ships_moored ON ships(moored_at_settlement_id) WHERE current_location_kind = 'moored';
```

**Field rationale:**

- `party_id` — mirrors `draft_vehicles.party_id` for consistency. The party that owns/operates the ship. If a future system needs per-character ship ownership, add `owner_character_id` as a separate column later.
- `vessel_key` — references a row in `data/equipment/maritime.json` (existing catalog). The catalog defines starting cargo capacity, crew minimums, vessel cost in cp.
- `shp_max`, `shp_current` — structural hit points (max and current). Read by §8.6's moorage calculator. Used by Phase 9C/D ship combat (not this session's scope).
- `cargo_capacity_stone` — total cargo capacity in stone. Comes from the catalog at ship creation; persisted so it can be modified by later in-game events (refits, damage, etc.).
- Crew columns — counts per role. Initial values from the catalog; can be adjusted by hiring/firing.
- `monthly_operating_cost_gp` — cached RAW value (§9.6). Read by the monthly tick to debit the party treasury.
- `current_location_kind` + `moored_at_settlement_id` — where the ship is. `'moored'` (at a settlement, paying moorage), `'at_sea'` (traveling), `'wrecked'` (destroyed but not yet cleaned up — preserved for cargo recovery).

**Initialization** at ship purchase (Phase 10B.2 territory): load the catalog row, copy values into the ships row, set `current_location_kind='moored'` and `moored_at_settlement_id` to the purchase point.

### 9.3 Maritime catalog updates

`data/equipment/maritime.json` already exists with `barge_raft, canoe` etc. RAW's commercial vessels (small sailing ship, large sailing ship — from `acore-campaign-hijinks.xml:844-911`) need to be added to this catalog if not already present. Audit pass:

```
For each entry in maritime.json:
    Check that the following fields exist and align with RAW:
    - vessel_key (snake_case canonical identifier)
    - name (display string)
    - cost_cp (purchase price in copper pieces; RAW gp × 100)
    - crew_captain, crew_sailors, crew_rowers, marines (RAW Ship Crew column)
    - cargo_stone_min, cargo_stone_max (cargo capacity range)
    - shp_max (structural hit points)
    - monthly_operating_cost_gp (RAW Average Monthly Costs column)
    - notes (RAW prose)

For RAW Merchant Ships table entries missing from maritime.json:
    Add small_sailing_ship and large_sailing_ship entries with values per RAW L856-873.
```

This audit pass is Prereq.1's responsibility (the merchandise registry session — same data-loading wave). If RAW has SHP values for the ship types they're cited; otherwise project-design fill from comparable RAW combat references. `[NEEDS-MARITIME-CATALOG-VERIFICATION]` flag for the encoding pass.

### 9.4 `cargo_holds` table — Option B per Q-MERC-17

Migration 097 sub-step 15. **One row per cargo acquisition** (not per individual load). The `loads_count` column aggregates identical fungible loads from the same acquisition; loads from different sources/markets/days stay in separate rows.

```sql
CREATE TABLE IF NOT EXISTS cargo_holds (
    id                                  TEXT    PRIMARY KEY,
    campaign_id                         TEXT    NOT NULL REFERENCES campaigns(id),
    -- Carrier: exactly one of these is non-null; the CHECK constraint enforces.
    draft_vehicle_id                    TEXT    REFERENCES draft_vehicles(id) ON DELETE CASCADE,
    ship_id                             TEXT    REFERENCES ships(id) ON DELETE CASCADE,
    merchandise_type                    TEXT    NOT NULL,
    loads_count                         INTEGER NOT NULL DEFAULT 0,
    load_weight_stone                   INTEGER NOT NULL DEFAULT 0,   -- cached from MerchandiseRegistry at acquisition
    market_value_at_acquisition_gp      INTEGER NOT NULL DEFAULT 0,   -- gp paid (purchase) or notional value (smuggle/steal)
    source_acquisition_kind             TEXT    NOT NULL DEFAULT 'purchased'
        CHECK(source_acquisition_kind IN ('purchased', 'smuggled', 'stolen', 'shipping_contract')),
    acquired_at_settlement_id           TEXT    REFERENCES settlement_entrances(id),
    acquired_at_calendar_day            INTEGER NOT NULL DEFAULT 0,
    notes                               TEXT    NOT NULL DEFAULT '',
    created_at                          TEXT    NOT NULL DEFAULT (datetime('now')),
    CHECK ((draft_vehicle_id IS NOT NULL) <> (ship_id IS NOT NULL))   -- XOR: exactly one carrier
);
CREATE INDEX idx_cargo_holds_draft_vehicle ON cargo_holds(draft_vehicle_id) WHERE draft_vehicle_id IS NOT NULL;
CREATE INDEX idx_cargo_holds_ship ON cargo_holds(ship_id) WHERE ship_id IS NOT NULL;
CREATE INDEX idx_cargo_holds_merchandise ON cargo_holds(merchandise_type);
```

**Field rationale:**

- Two nullable carrier FKs with XOR CHECK — exactly one is set per row. Cleaner than a polymorphic carrier_kind/carrier_id pattern in SQLite (typed FKs preserve referential integrity).
- `ON DELETE CASCADE` on both carriers — destroying the carrier (sunk ship, scrapped wagon) destroys its cargo. Phase 10B.2 / UI is responsible for prompting "unload first?" before player-initiated destruction. Combat-driven destruction (ship sunk) loses cargo naturally.
- `load_weight_stone` cached at acquisition — `MerchandiseRegistry.load_weight_stone(merchandise_type)` is RAW-stable, but caching avoids a registry lookup on every encumbrance query.
- `market_value_at_acquisition_gp` — the gp value at the time of acquisition. For purchased cargo, this is the gp PAID. For smuggled/stolen cargo, it's the notional gp value at the acquisition market (used by Phase 10B.3's smuggling/stealing yield formulas: 12% of market value to boss for smuggling, 60% for stealing — multiplied against this column).
- `source_acquisition_kind` — provenance. Four values:
  - `'purchased'` — legitimate buy at market
  - `'smuggled'` — Phase 10B.3 hijink output
  - `'stolen'` — Phase 10B.3 hijink output
  - `'shipping_contract'` — accepted shipping contract (§9.7)
- `acquired_at_settlement_id` + `acquired_at_calendar_day` — origin tracking, for audit and for shipping-contract deadline math.

**No stacking semantic at insert time.** If a player buys 5 loads of grain at Ashford day 10, then 5 more loads of grain at Ashford day 12, two cargo_holds rows result (different acquired_at_calendar_day). This is intentional — each shipment retains its own provenance and market_value snapshot, which is essential for tracking arbitrage profit per acquisition. UI can sum loads_count by merchandise_type for display.

### 9.5 Encumbrance integration — single limit, two sources

Per Jedidiah's Q-MERC-17 requirement: a wagon must track a SINGLE encumbrance limit, with cargo_holds and inventory_items both counting against it.

```gdscript
class_name CargoEncumbranceCalculator
extends RefCounted

# For draft vehicles
static func draft_vehicle_used_stone(draft_vehicle_id: String) -> int:
    var inv_stone: int = _sum_inventory_stone_for_vehicle(draft_vehicle_id)
    var cargo_stone: int = _sum_cargo_stone_for_draft_vehicle(draft_vehicle_id)
    return inv_stone + cargo_stone

static func draft_vehicle_capacity_check(draft_vehicle_id: String) -> Dictionary:
    var used: int = draft_vehicle_used_stone(draft_vehicle_id)
    var vehicle: Dictionary = CampaignRepository.get_draft_vehicle(draft_vehicle_id)
    var team: Array = _resolve_hitched_team(vehicle.get("hitched_creatures", "[]"))
    var capacity: Dictionary = DraftVehicleService.get_vehicle_capacity(
        vehicle["item_key"], DraftVehicleService.calculate_team_equivalents(team)
    )
    return {
        "used_stone": used,
        "load_normal_stone": capacity.get("load_normal", 0),
        "load_max_stone": capacity.get("load_max", 0),
        "is_over_normal": used > capacity.get("load_normal", 0),
        "is_over_max":    used > capacity.get("load_max", 0),
        "speed": capacity.get("speed_loaded" if used > capacity.get("load_normal", 0) else "speed_normal", 0),
    }

# For ships
static func ship_used_stone(ship_id: String) -> int:
    return _sum_cargo_stone_for_ship(ship_id)
    # NOTE: ships don't carry inventory_items in v1; personal gear stays on characters.

static func ship_capacity_check(ship_id: String) -> Dictionary:
    var used: int = ship_used_stone(ship_id)
    var ship: Dictionary = CampaignRepository.get_ship(ship_id)
    return {
        "used_stone": used,
        "cargo_capacity_stone": ship["cargo_capacity_stone"],
        "is_over_capacity": used > ship["cargo_capacity_stone"],
        "free_stone": maxi(0, ship["cargo_capacity_stone"] - used),
    }
```

**Why the existing `DraftVehicleService` is unchanged:** it computes raw capacity from item_key + team. It doesn't query used capacity. The new `CargoEncumbranceCalculator` is the higher-level abstraction that combines `DraftVehicleService.get_vehicle_capacity` with the SQL sums.

**Ships don't carry `inventory_items` in v1.** Personal gear stays on character inventories. Future v1.1 can add `inventory_items.ship_id` FK if needed, but for v1 ships are merchandise-cargo-only. The Q-MERC-17 "single limit, two sources" rule still holds — for ships the second source happens to be absent. Documented at §9.4 schema rationale.

### 9.6 Crew & monthly operating costs

- **RAW citation:** `rules/acore-campaign-hijinks.xml:844-911` (Merchant Ships and Caravans table).
- **What RAW provides:** per-vessel-type aggregate values for upfront cost, crew composition, average cargo capacity, average monthly operating cost, average monthly profit.

| Vessel | Upfront | Crew | Cargo (stone) | Monthly cost (gp) | Monthly profit (gp) |
|---|---|---|---|---|---|
| Small sailing ship | 10,000 gp | 10 sailors + 1 navigator + 1 captain | 10,000 | 325 | 875 |
| Large sailing ship | 20,000 gp | 17 sailors + 2 navigators + 1 captain | 30,000 | 525 | 2,600 |
| 10 wagons | 3,600 gp | 20 guards + 2 sergeants + 1 leader | 6,400 | 515 | 120 |
| 20 wagons | 7,200 gp | 40 guards + 4 sergeants + 1 leader | 12,800 | 825 | 600 |
| 30 wagons | 10,800 gp | 60 guards + 6 sergeants + 1 leader | 19,200 | 1,150 | 1,050 |
| 40 wagons | 14,500 gp | 80 guards + 8 sergeants + 1 leader | 25,600 | 1,450 | 1,475 |

- **Project resolution:**
  - The "Monthly cost" column populates `ships.monthly_operating_cost_gp` at ship creation. Caravan-side equivalent for `draft_vehicles` requires a similar column if Phase 10B.2 wants per-month caravan cost tracking — flagged below.
  - The "Crew" column maps to `ships.crew_captain` / `crew_sailors` / `crew_rowers` / `crew_marines`. RAW says "navigators" for sailing ships, which is project-mapped to **crew_sailors** for v1 simplicity (navigators are skilled sailors; we don't need a separate slot). `[NEEDS-NAVIGATOR-SEPARATE-ROLE-PASS]` if you want them tracked distinctly.
  - The "Monthly profit" column is **informational only**, not stored. Profit is an emergent property of actual trade activity. RAW's "average profit" is a Judge-convenience for hand-waving NPC merchant fortunes; for player characters, profit is whatever they actually earn through buy/sell/transport.

#### 9.6.1 Monthly tick: debit operating cost

`DomainMonthlyResolver` (existing) extends to debit ship operating costs:

```
For each ship in campaign:
    1. If is_destroyed = 1: skip
    2. cost = ship.monthly_operating_cost_gp
    3. Debit cost from party treasury (party_id → parties.treasury_gp).
    4. If party treasury insufficient: emit EventBus.ship_operating_cost_unpaid(ship_id, owed_gp).
       (Project-design call: ship not destroyed for non-payment in v1, but crew morale could decay — defer to future.)
    5. Emit EventBus.ship_operating_cost_paid(ship_id, gp_amount).
```

`[NEEDS-CREW-MORALE-PASS]` for non-payment consequences. For v1, just log and continue.

#### 9.6.2 Caravan monthly cost (draft_vehicles extension)

For caravans (groups of wagons), RAW gives the same monthly cost pattern. The existing `draft_vehicles` table has no `monthly_operating_cost_gp` column. Two options:

- **(A)** Add the column to `draft_vehicles` via migration 097 sub-step 14a (alongside the ships table). Aligns the two carrier tables.
- **(B)** Compute on-the-fly from item_key (cart vs wagon) and quantity. No persistence; recomputed each tick.

I lean **(A)** for consistency, but it requires editing `draft_vehicles` schema which has been stable since migration 024. Phase 10B.2 may want this; tagging as a question. **For v1, defer caravan monthly cost** — ships only. `[NEEDS-CARAVAN-MONTHLY-COST-PASS]` flag.

### 9.7 `shipping_contracts` table

Migration 097 sub-step 16:

```sql
CREATE TABLE IF NOT EXISTS shipping_contracts (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    accepted_by_party_id            TEXT    NOT NULL REFERENCES parties(id),
    origin_settlement_id            TEXT    NOT NULL REFERENCES settlement_entrances(id),
    destination_settlement_id       TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    loads_count                     INTEGER NOT NULL DEFAULT 0,
    fee_gp                          INTEGER NOT NULL DEFAULT 0,
    deadline_calendar_day           INTEGER NOT NULL DEFAULT 0,
    status                          TEXT    NOT NULL DEFAULT 'accepted'
        CHECK(status IN ('accepted', 'in_transit', 'delivered', 'failed_deadline', 'cancelled')),
    accepted_at_calendar_day        INTEGER NOT NULL DEFAULT 0,
    delivered_at_calendar_day       INTEGER,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_shipping_contracts_party ON shipping_contracts(accepted_by_party_id, status);
CREATE INDEX idx_shipping_contracts_destination ON shipping_contracts(destination_settlement_id, status);
```

- **RAW citation:** `rules/acore-campaign-hijinks.xml:765-790ish` (passenger and shipping contracts table — six rows by market class).
- **What RAW provides:** at each market, roll counts of available passengers (2d4+1 for class I, ..., none for class VI) and shipping contracts (similar). Cargo to be shipped per contract is rolled in loads.
- **Project resolution:** the `shipping_contracts` table tracks contracts the player has *accepted*. Available contracts (not yet accepted) are rolled fresh at each market visit — they don't persist between visits. The activity handler for `solicit_passengers` / accept-shipping-contract (Phase 10B.2) rolls fresh contracts on each market entry and writes accepted ones to this table.
- **Cargo flow.** Accepted shipping contracts spawn `cargo_holds` rows with `source_acquisition_kind='shipping_contract'`. The merchandise (or stand-in for passenger fares) is loaded onto a carrier. Delivery at destination zeros out the cargo_hold row and credits `fee_gp` to the party treasury.
- **Deadline mechanic.** RAW silent on deadlines; project-design: contracts carry an explicit `deadline_calendar_day`. Late delivery → `status='failed_deadline'`, no fee paid (or partial fee with reputation penalty — `[NEEDS-LATE-DELIVERY-PENALTY-PASS]`).

### 9.8 Hijink → cargo flow (data path)

Phase 10B.3's smuggling and stealing hijinks yield merchandise loads. The data path:

```
On smuggling_hijink_success (Phase 10B.3 invokes):
    1. Identify the source merchandise: rolled via MerchandiseRegistry.random_common()
       (or context-specific source per RAW).
    2. Compute loads_count = 10 × syndicate_member_level (per RAW for smuggling).
    3. Compute notional market value: MarketPriceResolver.compute_market_price(merch_type, settlement_id, ...)
       returns gp_per_load; market_value = gp_per_load × loads_count.
    4. Identify a recipient carrier (Phase 10B.3 responsibility — defaults to boss's available
       draft_vehicle or ship). If none has capacity, hijink yield converts to pure gp at a
       project-design loss factor (`[NEEDS-CARRIER-FALLBACK-PASS]`).
    5. Insert cargo_holds row:
       - draft_vehicle_id or ship_id = chosen recipient
       - merchandise_type = identified type
       - loads_count = as computed
       - load_weight_stone = MerchandiseRegistry.load_weight_stone(...)
       - market_value_at_acquisition_gp = computed market value (basis for the eventual 12% boss payout)
       - source_acquisition_kind = 'smuggled'
       - acquired_at_settlement_id = settlement where the hijink occurred
       - acquired_at_calendar_day = current_calendar_day

On stealing_hijink_success: identical flow with loads_count = 2 × level and source_acquisition_kind = 'stolen'.
```

§9 ships the `CargoHoldRepository.insert_hijink_yield(...)` helper. Phase 10B.3 invokes it.

### 9.9 Multi-leg arbitrage flow (data path)

Buy-at-A / transport / sell-at-B is the core mercantile loop:

```
1. Player at market A buys N loads of merchandise type X.
   - Phase 10B.2's buy_sell_merchandise handler computes price (§6) and fees (§8).
   - Debits gp from party treasury.
   - Calls CargoHoldRepository.insert_purchase(...)
     → new cargo_holds row, draft_vehicle_id or ship_id set, source='purchased',
       market_value_at_acquisition_gp = gp_paid.
   - CargoEncumbranceCalculator validates carrier has capacity (§9.5).
2. Player travels A → B via wilderness adventure (existing systems handle).
   - Cargo persists in cargo_holds rows.
3. Player at market B sells the cargo.
   - Phase 10B.2's buy_sell_merchandise handler in "sell" mode.
   - Reads the cargo_holds row, computes price at B (§6 reads B's demand modifier).
   - Credits gp to party treasury (minus customs duty per §8.4 — using B's annual rate).
   - Calls CargoHoldRepository.delete_sold(...)
     → cargo_holds row deleted (or status='sold' if preserving audit; v1 deletes).
4. Profit = (sell_gp - acquisition_gp - fees).
   Phase 10B.2 surfaces this in transaction-history UI.
```

§9's data path is just the insert/delete on cargo_holds. The transaction-level orchestration is Phase 10B.2.

### 9.10 Service APIs

`engine/subsystems/commerce/ship_repository.gd`:

```gdscript
class_name ShipRepository
extends RefCounted

# CRUD
static func create_ship(party_id: String, vessel_key: String, settlement_id: String) -> String
    # Creates a ship from the maritime.json catalog, mored at settlement_id.
    # Returns new ship_id.
static func get_ship(ship_id: String) -> Dictionary
static func list_ships_for_party(party_id: String) -> Array

# State changes
static func set_ship_location(ship_id: String, location_kind: String, settlement_id: String) -> bool
static func damage_ship(ship_id: String, shp_lost: int) -> bool   # destroys if shp_current <= 0
static func destroy_ship(ship_id: String) -> bool                 # explicit destruction; cascades cargo

# Monthly tick
static func process_monthly_operating_costs_for_campaign(
    campaign_id: String, current_calendar_day: int
) -> int
    # For each non-destroyed ship: debit monthly_operating_cost_gp from party treasury.
    # Returns total gp debited.
```

`engine/subsystems/commerce/cargo_hold_repository.gd`:

```gdscript
class_name CargoHoldRepository
extends RefCounted

# Reads
static func list_for_draft_vehicle(draft_vehicle_id: String) -> Array
static func list_for_ship(ship_id: String) -> Array
static func get_cargo_hold(cargo_hold_id: String) -> Dictionary

# Writes — typed per acquisition kind
static func insert_purchase(
    carrier_id: String, carrier_kind: String,  # 'draft_vehicle' | 'ship'
    merchandise_type: String, loads_count: int, gp_paid: int,
    settlement_id: String, current_calendar_day: int
) -> String

static func insert_hijink_yield(
    carrier_id: String, carrier_kind: String,
    merchandise_type: String, loads_count: int, market_value_gp: int,
    settlement_id: String, current_calendar_day: int,
    kind: String  # 'smuggled' | 'stolen'
) -> String

static func insert_shipping_contract_load(
    carrier_id: String, carrier_kind: String,
    merchandise_type: String, loads_count: int,
    contract_id: String, settlement_id: String, current_calendar_day: int
) -> String

# Transfer / split
static func transfer_loads(
    source_cargo_hold_id: String,
    target_carrier_id: String, target_carrier_kind: String,
    loads_count: int
) -> Dictionary    # Returns {success, source_remaining, target_new_id_or_merged}

# Delete on sale
static func delete_sold(cargo_hold_id: String) -> bool

# Encumbrance support (delegated to CargoEncumbranceCalculator)
```

`engine/subsystems/commerce/shipping_contract_repository.gd`:

```gdscript
class_name ShippingContractRepository
extends RefCounted

static func accept_contract(
    party_id: String, origin_settlement_id: String, destination_settlement_id: String,
    merchandise_type: String, loads_count: int, fee_gp: int,
    deadline_calendar_day: int, current_calendar_day: int
) -> String

static func mark_in_transit(contract_id: String) -> bool
static func deliver(contract_id: String, current_calendar_day: int) -> Dictionary
    # Returns {success: bool, fee_paid_gp: int, deadline_missed: bool}
static func cancel(contract_id: String) -> bool
static func list_active_for_party(party_id: String) -> Array
```

`engine/subsystems/commerce/cargo_encumbrance_calculator.gd`: see §9.5 for the API surface.

### 9.11 EventBus signals

Added to event_bus.gd in §14's consolidated additions:

```gdscript
signal ship_created(ship_id: String, party_id: String, vessel_key: String)
signal ship_destroyed(ship_id: String, party_id: String)
signal ship_location_changed(ship_id: String, new_kind: String, settlement_id: String)
signal ship_operating_cost_paid(ship_id: String, gp_amount: int)
signal ship_operating_cost_unpaid(ship_id: String, owed_gp: int)
signal cargo_loaded(cargo_hold_id: String, carrier_id: String, merchandise_type: String, loads_count: int)
signal cargo_sold(cargo_hold_id: String, gp_received: int)
signal shipping_contract_accepted(contract_id: String, party_id: String, fee_gp: int)
signal shipping_contract_delivered(contract_id: String, fee_paid_gp: int, deadline_missed: bool)
signal shipping_contract_failed(contract_id: String, reason: String)
```

### 9.12 Tests

Tests split across four test files to keep each focused. Budget: **~30 tests total.**

`tests/test_ship_repository.gd` (~8):
1. Create ship from catalog → row inserted with catalog-derived fields (shp_max, cargo_capacity_stone, crew counts, monthly_operating_cost_gp).
2. `list_ships_for_party` returns only non-destroyed ships for that party.
3. `set_ship_location` transitions valid (moored → at_sea, at_sea → moored).
4. `damage_ship` destroys when shp_current reaches 0 (status='wrecked' or is_destroyed=1).
5. `destroy_ship` cascades to cargo_holds (referencing rows deleted via ON DELETE CASCADE).
6. `process_monthly_operating_costs_for_campaign` debits correct gp from party treasury.
7. Monthly cost unpaid emits signal; ship is NOT destroyed in v1.
8. Destroyed ships skipped in monthly cost processing.

`tests/test_cargo_hold_repository.gd` (~10):
1. `insert_purchase` creates row with source='purchased', correct fields.
2. `insert_hijink_yield` with kind='smuggled' / 'stolen' sets source_acquisition_kind correctly.
3. Carrier XOR constraint: row with both draft_vehicle_id AND ship_id rejected.
4. Carrier XOR constraint: row with neither rejected.
5. `list_for_draft_vehicle` returns only rows for that vehicle; filters out ship-cargo.
6. ON DELETE CASCADE: deleting parent draft_vehicle deletes its cargo_holds rows.
7. `transfer_loads` partial transfer: source.loads_count decremented, target.loads_count incremented (new row or merged).
8. `transfer_loads` full transfer: source row deleted, target row created/updated.
9. `delete_sold` removes the row.
10. Multiple acquisitions of same merchandise type at same vehicle remain separate rows (different `acquired_at_calendar_day` distinguishes).

`tests/test_cargo_encumbrance_calculator.gd` (~7):
1. Empty cart → used_stone == 0.
2. Cart with inventory_items only → used_stone == sum of inv stone.
3. Cart with cargo_holds only → used_stone == sum of cargo (loads_count × load_weight_stone).
4. Cart with both inventory AND cargo → used_stone == sum of both.
5. `is_over_normal` / `is_over_max` correctly detect.
6. Ship capacity check returns correct free_stone.
7. Banker rounding NOT applied (all values are integer-stone).

`tests/test_shipping_contract_repository.gd` (~5):
1. `accept_contract` creates row with status='accepted'.
2. `deliver` on time → status='delivered', fee paid.
3. `deliver` after deadline → status='failed_deadline', no fee paid (v1).
4. `list_active_for_party` returns 'accepted' and 'in_transit' rows.
5. `cancel` sets status='cancelled'.

### 9.13 What §9 does NOT add

- **No ship combat.** SHP damage applied from external systems (Phase 9C/D siege artillery, naval encounters). §9 supports the damage_ship API but doesn't generate the damage.
- **No naval movement / wind / currents.** Travel A→B uses existing wilderness movement systems. Ships move as fast as a wilderness party for v1. `[NEEDS-NAVAL-MOVEMENT-PASS]` if you want sea-specific travel mechanics later.
- **No per-crew-member tracking.** Crew counts are aggregate per-role columns. The 17 sailors on a large sailing ship are not 17 individual NPCs — they're a single integer. Individual crew tracking (names, morale, mutiny) is deferred. `[NEEDS-CREW-INDIVIDUATION-PASS]`.
- **No crew morale or mutiny.** Operating cost unpaid emits a signal but doesn't degrade ship operation in v1.
- **No ship combat-aware crew loss.** SHP damage doesn't reduce crew counts in v1.
- **No caravan-as-aggregate.** A 40-wagon caravan in RAW is one logical unit; in our model it's 40 `draft_vehicles` rows. Phase 10B.2 may add a `caravans` table that groups draft_vehicles into named units. v1 leaves them ungrouped.
- **No caravan monthly operating cost.** Per §9.6.2 deferred. `[NEEDS-CARAVAN-MONTHLY-COST-PASS]`.
- **No passenger transport.** RAW's passenger-and-cargo-transport table includes passengers; v1 ships shipping cargo only. Passengers are a Phase 10B.2 follow-up.
- **No ship-to-ship cargo transfer.** `transfer_loads` only moves between carriers if the carriers are co-located (caller responsibility to verify). For v1, this is the player manually triggering a transfer in port.

---

## §10. Crime & Punishment Data Prerequisites

### 10.0 Overview

Phase 10B.3 (Syndicate block) ships a full Crime & Punishment resolver per RAW `acore-campaign-hijinks.xml:260-315`. The resolver consumes proficiency state and per-character prior-crimes flags. This section ships only the **data prerequisites** — the resolver logic is Phase 10B.3's job.

Two data deliverables:

1. **Attorney specialization** added to the `profession` proficiency's specialization list in `data/proficiencies/proficiency_specializations.json`. The proficiency itself (with its 3-rank scale and 25/50/100 gp/month earnings) already exists in `data/proficiencies/proficiency_catalog.json:2649`; this is just adding "attorney" to the list of valid civil professions.
2. **`character_legal_status` table** for tracking the three permanent flags (Branded / Maimed / Proscribed) that contribute to RAW's prior-crimes modifier (-1 / -2 / -3 respectively). New migration 097 sub-step.

### 10.1 RAW citations

- **Crime & Punishment procedure:** `rules/acore-campaign-hijinks.xml:260-266`. Procedure: 2d6 + Charisma mod + relevant proficiency mods (Diplomacy / Mystic Aura / Seduction) + attorney + bribery + evidence + interpleader + prior crimes + severity. Result mapped to the Crime & Punishment table.
- **Attorney rule:** `rules/acore-campaign-hijinks.xml:269-277`. "Add the perpetrator's rank in Profession (attorney), if any. If the perpetrator lacks the proficiency, the syndicate may hire an attorney." Hired-attorney costs: 25 gp (rank 1), 50 gp (rank 2), 100 gp (rank 3). **These match the existing `profession` proficiency's earnings column** in `data/proficiencies/proficiency_catalog.json:2654` — same scale.
- **Prior crimes modifiers:** `rules/acore-campaign-hijinks.xml:300-304`.
  - Branded: -1
  - Maimed (loss of tongue or hands): -2
  - Proscribed: -3

A character may carry multiple prior-crime flags simultaneously (e.g., Branded AND Maimed for a -3 total). The flags **stack additively**.

### 10.2 Attorney proficiency specialization

Add one entry to the `profession.specializations` array in `data/proficiencies/proficiency_specializations.json`:

```json
{ "id": "attorney", "display_name": "Attorney", "layer": "base", "prerequisite_ids": [], "metadata": {} }
```

Alphabetical position: between `actuary` and `banker` (top of the list). The existing schema for these entries is established at `proficiency_specializations.json:128-130+`; the new entry follows the existing pattern exactly.

**No catalog change required.** The `profession` proficiency entry at `proficiency_catalog.json:2649` already supports any specialization. Adding "attorney" to the specialization list makes it selectable at character creation / level-up.

**Why this is a one-line data edit, not a code change.** The `ProficiencyRegistry` already handles arbitrary `profession` specializations via the specializations file. Phase 10B.3's resolver will query:

```gdscript
ProficiencyRegistry.get_proficiency_rank(character_id, "profession", "attorney") -> int
```

This call works the moment the specialization is added. No registry code touched.

#### 10.2.1 Verify the existing registry surface

The ProficiencyRegistry API needs to support `get_proficiency_rank(character_id, proficiency_key, specialization_id)` returning an integer rank (0 if the character doesn't have it). **Audit task:** verify this method exists on the existing registry. If only `get_proficiency_rank(character_id, proficiency_key)` (without specialization) is exposed, extend the API. This audit is one of Prereq.6's deliverables (per §14's wave plan). `[NEEDS-PROFICIENCY-API-VERIFICATION]` flag for the encoding pass.

### 10.3 `character_legal_status` table

Migration 097 sub-step 17:

```sql
CREATE TABLE IF NOT EXISTS character_legal_status (
    character_id                    TEXT    PRIMARY KEY REFERENCES characters(id),
    is_branded                      INTEGER NOT NULL DEFAULT 0 CHECK(is_branded IN (0, 1)),
    is_maimed                       INTEGER NOT NULL DEFAULT 0 CHECK(is_maimed IN (0, 1)),
    is_proscribed                   INTEGER NOT NULL DEFAULT 0 CHECK(is_proscribed IN (0, 1)),
    prior_crimes_modifier_cache     INTEGER NOT NULL DEFAULT 0,
    branded_at_calendar_day         INTEGER,
    maimed_at_calendar_day          INTEGER,
    proscribed_at_calendar_day      INTEGER,
    notes                           TEXT    NOT NULL DEFAULT '',
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);
```

**Field rationale:**

- `character_id` as PRIMARY KEY — at most one row per character. A character without legal-status history simply has no row (or a row with all flags = 0).
- Three boolean flags — matches RAW's three discrete categories. Multiple flags can be true simultaneously (Branded + Maimed = -3 total).
- `prior_crimes_modifier_cache` — the running total `(-1 × is_branded) + (-2 × is_maimed) + (-3 × is_proscribed)`. Maintained by application logic (CharacterLegalStatusRepository) on flag updates, not by SQL trigger. Caching avoids recomputing on every C&P resolver call.
- `*_at_calendar_day` columns — timestamps for when each verdict was applied. Optional (NULL if not applicable). Useful for UI display ("Branded 47 days ago at Ashford") and for any future amnesty / expungement system.
- `notes` — free-text reason ("Branded for theft at Thornwall, 1234-3-15"). Audit-trail support.

**Why a sibling table and not columns on `characters`:** characters is a high-traffic table already with many columns. Legal status is a narrow concern that most characters won't have any data for. The sibling-table pattern keeps `characters` lean and means non-legal-status code never SELECTs unused columns.

#### 10.3.1 No combat-state mutation in v1 (per Phase 10 Q6)

Per Phase 10 plan Q6 [RESOLVED 2026-05-10]: "Permanent-wound / amputation / execution outcomes are logged but do NOT mutate combat-affecting character state in v1." A Maimed character has `is_maimed=1` in the legal status table; their HP, attack rolls, and inventory are unaffected. The flag affects C&P proceedings only.

When the future combat-state-mutation system lands, it will:
- Read `character_legal_status.is_maimed`
- Look up "loss of tongue or hands" → apply concrete combat effects (no speech-based spells, no two-handed weapons, etc.)
- Possibly write to a new `character_permanent_effects` table

That future work is `[NEEDS-PERMANENT-WOUND-COMBAT-PASS]` and out of scope for this GDD.

### 10.4 Service API

`engine/subsystems/syndicate/character_legal_status_repository.gd`:

```gdscript
class_name CharacterLegalStatusRepository
extends RefCounted

# Read
static func get_status(character_id: String) -> Dictionary
    # Returns the row as a dict, or a zeroed default if no row exists:
    # {character_id, is_branded: 0, is_maimed: 0, is_proscribed: 0,
    #  prior_crimes_modifier_cache: 0, ...}
static func get_prior_crimes_modifier(character_id: String) -> int
    # Convenience: returns prior_crimes_modifier_cache, or 0 if no row.
    # Phase 10B.3's C&P resolver calls this.

# Write — flag toggles
static func apply_branded(character_id: String, calendar_day: int, notes: String = "") -> bool
static func apply_maimed(character_id: String, calendar_day: int, notes: String = "") -> bool
static func apply_proscribed(character_id: String, calendar_day: int, notes: String = "") -> bool
    # Each setter:
    #   1. INSERTs or UPDATEs the row.
    #   2. Sets the corresponding boolean to 1.
    #   3. Recomputes prior_crimes_modifier_cache.
    #   4. Emits EventBus.character_legal_status_changed.

static func clear_flag(character_id: String, flag: String) -> bool
    # flag = 'branded' | 'maimed' | 'proscribed'. Used for future amnesty
    # / expungement; not consumed by Phase 10B.3's v1 resolver.

# Maintenance
static func recompute_modifier_cache(character_id: String) -> int
    # Recomputes prior_crimes_modifier_cache from the boolean flags.
    # Safety helper if external code mutates the booleans directly.
```

The repository is a `RefCounted` static-function library — no autoload. Phase 10B.3's resolver invokes `get_prior_crimes_modifier(character_id)` once per C&P throw.

### 10.5 EventBus signals

Added to event_bus.gd (consolidated in §14):

```gdscript
signal character_legal_status_changed(character_id: String, flag: String, new_value: int, modifier_total: int)
    # flag = 'branded' | 'maimed' | 'proscribed'
    # Emitted on apply_*/clear_flag. Phase 10B.3 / UI listens for log surfacing.
```

### 10.6 Tests

`tests/test_character_legal_status_repository.gd` budget: **~7 tests.**

1. **No row → defaults.** `get_status(unseen_character_id)` returns dict with all flags 0 and modifier 0.
2. **`apply_branded` creates row.** After call, `is_branded == 1`, modifier == -1, `branded_at_calendar_day` set.
3. **`apply_branded` then `apply_maimed`.** After both, `is_branded == 1`, `is_maimed == 1`, modifier == -3 (sum).
4. **`apply_proscribed` to fresh row.** `is_proscribed == 1`, modifier == -3.
5. **All three applied.** Branded + Maimed + Proscribed → modifier == -6.
6. **`clear_flag('maimed')`.** Modifier recomputes (e.g. from -3 to -1 if was Branded + Maimed).
7. **`recompute_modifier_cache` safety.** Manually mutate the booleans via raw SQL, then call recompute → cache reflects current booleans.

`tests/test_attorney_specialization.gd` budget: **~3 tests.**

1. **Specialization list includes "attorney".** Load `proficiency_specializations.json`; the `profession.specializations` array contains an entry with `id == "attorney"`.
2. **`ProficiencyRegistry.get_proficiency_rank(character_id, "profession", "attorney")` returns 0 for a character without the proficiency.**
3. **`ProficiencyRegistry.get_proficiency_rank(character_id, "profession", "attorney")` returns N for a character who has Profession (attorney) at rank N** (fixture: assign character rank 2 in profession-attorney, verify lookup returns 2).

### 10.7 What §10 does NOT add

- **No C&P resolver.** That's Phase 10B.3 (`engine/subsystems/syndicate/crime_and_punishment_resolver.gd`). §10 only provides the data prereqs.
- **No verdict-application logic.** The flow "C&P resolver outputs verdict → verdict applies brand/maim/proscribed → CharacterLegalStatusRepository.apply_*" is Phase 10B.3 territory. §10 ships the apply_* API for Phase 10B.3 to call.
- **No combat-state mutation for Maimed.** Per Phase 10 Q6 — logged but not mutated in v1. `[NEEDS-PERMANENT-WOUND-COMBAT-PASS]`.
- **No bribery proficiency check.** RAW step at L279-285 references a "Bribery proficiency" for syndicate corruption bonuses. Phase 10B.3's resolver consults bribery; §10 doesn't ship Bribery proficiency data (likely already in the proficiency catalog — Phase 10B.3 audits).
- **No interpleader logic.** RAW step at L293-298 lets a domain ruler plead. Phase 10B.3's resolver wires this; §10 doesn't.
- **No severity-of-crime table encoding.** RAW step at L306-313 has the severity bands; Phase 10B.3 encodes them when shipping the resolver. §10 doesn't pre-encode (the resolver wave is where it belongs alongside the rest of the C&P table).
- **No amnesty / expungement.** Future enhancement; `clear_flag` exists for the underlying mechanic but no game-loop trigger fires it in v1.

---

## §11. Audit-Only Sections — Spell-Cost Lookup and Henchman Loyalty

### 11.0 Overview

Two integrations need to be audited rather than built from scratch:

1. **Spell-cost lookup** for Phase 10A.2's `cast_charitable_spells` handler. RAW's Spell Availability by Market table associates each spell with a gp cost; the Faith block needs that lookup. **Audit finding:** the lookup is not yet wired into `SpellRegistry`. Per Jedidiah Q-MERC-10 [RESOLVED 2026-05-12], audit-when-relevant — the gap is documented for a future session, not closed this session.
2. **Henchman Loyalty API** that Phase 10B.3's `order_hijink` handler needs to call with a generic modifier dict (e.g., `{"hijink_overload": -3}` per RAW). **Audit finding:** the current resolver hardcodes the modifier path through `is_grudging` / `is_fanatic` flags only — no general modifier dict parameter. **Small API extension shipped this session** so 10B.3 has the hook it needs.

### 11.1 Spell-cost lookup — audit finding (NOT shipped this session)

#### Current state

- [`engine/subsystems/activities/handlers/faith/cast_charitable_spells.gd:18-22`](engine/subsystems/activities/handlers/faith/cast_charitable_spells.gd:18) explicitly defers the spell-cost lookup to the caller: "v1 takes `gp_value_total` from params. The spell-cost lookup (mapping each spell_key to its gp value per the Spell Availability by Market table) is deferred to the caller."
- The Faith block UI computes the gp value heuristically (or hand-authored) before launching the activity. No data-driven RAW-cited lookup exists.
- A grep across `engine/` finds zero references to `get_spell_cost_gp`, `spell_availability`, or `Spell Availability by Market`. The RAW table at the relevant `acore-campaign-hijinks.xml` location is not encoded as data.

#### Gap

A proper `SpellRegistry.get_spell_cost_gp(spell_key: String) -> int` helper consulting the RAW Spell Availability by Market table is missing. Until that helper exists:

- Faith block: relies on Judge/UI heuristic for charitable-spell gp value.
- Mercantile: no integration affected — mercantile doesn't consume spell costs.
- Smuggling / stealing: no integration affected.

The gap **is not blocking** this session's deliverables. Phase 10B.2 / 10B.3 don't depend on spell-cost lookup either.

#### Project resolution — defer

Per Q-MERC-10 [RESOLVED 2026-05-12], the lookup is **not built this session.** It's a Phase 10A.2-domain follow-up to be picked up when "spellcasting as a purchasable service" becomes a real need. The gap is documented here as the audit-trail entry so a future session can find it.

`[NEEDS-SPELL-COST-LOOKUP-PASS]` flag for the future enhancement. Expected scope when picked up:
- Encode the Spell Availability by Market table from RAW into `data/spells/spell_availability_by_market.json`.
- Add `SpellRegistry.get_spell_cost_gp(spell_key) -> int` reading the JSON.
- Update `cast_charitable_spells.gd` to compute `gp_value_total` from the spell list instead of taking it as a param.

#### Migration impact

None. §11.1 is documentation only.

### 11.2 Henchman Loyalty API — extension shipped this session

#### Current state

[`engine/subsystems/henchmen/henchman_loyalty_resolver.gd:41-72`](engine/subsystems/henchmen/henchman_loyalty_resolver.gd:41) signature:

```gdscript
static func resolve_loyalty_check(
    morale_score: int,
    is_grudging: bool = false,
    is_fanatic: bool = false,
    dice = null,
) -> Dictionary
```

The total modifier comes from `loyalty_modifier(morale_score, is_grudging, is_fanatic)` which only handles the grudging (-1) and fanatic (+2) cases. **No path exists** for an arbitrary modifier from another subsystem.

#### Phase 10B.3's requirement

Per `acore-campaign-hijinks.xml:488-494` (underboss authority) + `ax_campaign_play.xml:1213-1214` (order_hijink): when a boss assigns hijinks beyond one per month (or imposes a deadline), the syndicate member rolls a loyalty check with `hijink_overload_count × -1` modifier. The boss assigning hijinks to >20% of an underboss's followers triggers an underboss loyalty roll with cumulative -1 per additional 10%.

Phase 10B.3's `order_hijink.gd` handler needs to call:

```gdscript
HenchmanLoyaltyResolver.resolve_loyalty_check(
    morale_score, is_grudging, is_fanatic, dice,
    {"hijink_overload": -3, "underboss_strain": -2}
)
```

with the extra-modifier dict producing a `-5` adjustment on top of the existing morale/grudging/fanatic math.

#### API extension (shipped this session)

Add an optional `extra_modifiers: Dictionary` parameter to `resolve_loyalty_check`:

```gdscript
static func resolve_loyalty_check(
    morale_score: int,
    is_grudging: bool = false,
    is_fanatic: bool = false,
    dice = null,
    extra_modifiers: Dictionary = {},   # NEW: {source_label: int_modifier}
) -> Dictionary:
    var mod := loyalty_modifier(morale_score, is_grudging, is_fanatic)
    for source in extra_modifiers:
        mod += int(extra_modifiers[source])
    var roll := _roll_2d6(dice)
    var total := roll + mod
    var outcome: String = HenchmanTables.loyalty_result(total)
    var result := {
        "roll": roll,
        "modifier": mod,
        "extra_modifier_breakdown": extra_modifiers.duplicate(),   # NEW: audit trail
        "total": total,
        "outcome": outcome,
        # ... rest unchanged
    }
    # ... rest of match block unchanged
    return result
```

**Two changes:**

1. **`extra_modifiers` parameter** with default `{}`. Existing callers (Phase G-2 henchman lifecycle + any other consumer) are unaffected because the default is empty — they continue to call the function with positional args and get identical behavior.
2. **`extra_modifier_breakdown` field** added to the return dict. Echoes the input dict for audit / UI surfacing. Existing consumers that read the return dict's other fields are unaffected.

The `loyalty_modifier` helper at `henchman_loyalty_resolver.gd:28` stays unchanged. The new modifier path is summed inside `resolve_loyalty_check` after the call to `loyalty_modifier`, not inside it — keeps the helper's existing semantic (morale + grudging + fanatic) intact.

#### Migration impact

None. Code-only change. No schema modification.

#### Test additions

`tests/test_henchman_loyalty_resolver.gd` (existing file — extends with new assertions):

1. **Default extra_modifiers behavior.** Calling `resolve_loyalty_check(5, false, false, fixed_dice)` without the new param produces the same result as before this change (regression guard for existing callers).
2. **Single extra modifier.** `resolve_loyalty_check(5, false, false, fixed_dice, {"hijink_overload": -3})` → total reduced by 3 vs default.
3. **Multiple extra modifiers sum.** `{"a": -1, "b": +2, "c": -5}` → net -4 added to the modifier.
4. **`extra_modifier_breakdown` in return dict.** The breakdown dict equals the input dict; mutation of the returned dict doesn't affect the input (verifies the `.duplicate()` is in place).

### 11.3 What §11 does NOT add

- **No Spell Availability by Market data encoding.** Per §11.1, deferred. `[NEEDS-SPELL-COST-LOOKUP-PASS]` for the future session.
- **No `cast_charitable_spells.gd` rewiring.** That handler stays as-is until the lookup is added.
- **No `loyalty_modifier(...)` extension.** The new modifier path is added *outside* the helper, in `resolve_loyalty_check`'s body. Existing direct callers of `loyalty_modifier` (which compute modifier-only without rolling) keep the same behavior.
- **No Phase 10B.3 order_hijink handler.** That's Phase 10B.3's responsibility. §11 ships the API hook the handler will call.

---

## §12. Validation Examples — Ashford / Thornwall Round-Trip

### 12.0 Purpose

Per Q-MERC-3 [RESOLVED 2026-05-11]: validation examples are a **collaborative deliverable**. This section ships an end-to-end worked example using the project-canonical test settlements (Ashford and Thornwall from `data/test_hex_map.json`) to demonstrate:

1. The pipeline produces deterministic outputs given pinned inputs.
2. The demand-modifier procedure (§4) and trade-route shift (§5) combine to produce useful arbitrage gradients.
3. Market prices (§6) plus fees (§8) yield **playable** per-load profit margins under reasonable conditions.
4. Domain-owner exemption (§8.8) and customs-rate variation (§8.4) meaningfully affect profitability — design levers exist.

A second purpose: §12 functions as the integration-test fixture spec. `tests/test_commerce_integration.gd` (per §14's wave plan) reproduces these numbers and asserts them as a regression guard.

**Limits.** The dice components and the §4.4 deterministic-shuffle output for the domain-land-revenue distribution would vary in practice. For this worked example, I pin them at canonical values to make the arithmetic traceable; the test fixture pins the RNG seeds accordingly.

**Additional routes you may want.** §12 ships one route (Ashford ↔ Thornwall). If you want additional canonical routes for v1 validation, surface them and I'll add §12.A / §12.B / etc. Either name candidates from a setting you have in mind, or accept candidate routes I'd derive once I've seen the rest of the campaign map.

### 12.1 Fixture inputs

**Ashford** (`test_settlement_ashford` at hex (0,0), `data/test_hex_map.json:24`):

| Field | Value |
|---|---|
| market_class | 3 |
| urban_families | 2,400 (synthetic for fixture; class III range per `acore_axioms`) |
| age_years | 500 (default per §1.2) |
| dominant_race | human |
| parent_domain land revenue (avg `domain_hexes.land_value`) | 5 gp/family |
| customs_duty_rate_pct (year-rolled) | 4% (low end; we'll vary this in §12.6) |
| biome | clear |
| biome_subtype | (none) |
| elevation | flat |
| Adjacent water (sea / lake) | none |
| River overlay on hex | NO (test_hex_map has the river on the adjacent (0,1), not on (0,0)) |
| Derived water_sources | `{sea_coast: false, lake_shore: false, river_bank: false}` |
| Derived climate_columns | `[grasslands, plains]` (clear-default composite per §3.4) |
| Derived elevation_bucket | `""` (flat → no elevation modifier) |
| Derived age_bucket | `101_1000_years` |

**Thornwall** (`test_settlement_thornwall` at hex (2,1), `data/test_hex_map.json:37`):

| Field | Value |
|---|---|
| market_class | 5 |
| urban_families | 400 (synthetic; class V range) |
| age_years | 200 (synthetic) |
| dominant_race | human |
| parent_domain land revenue (avg) | 4 gp/family |
| customs_duty_rate_pct | 8% (mid-range) |
| biome | desert |
| biome_subtype | (none) |
| elevation | flat |
| Adjacent water | none |
| Derived water_sources | `{false, false, false}` |
| Derived climate_columns | `[desert]` |
| Derived elevation_bucket | `""` |
| Derived age_bucket | `101_1000_years` |

**Trade-route connectivity:** synthetic road overlay between Ashford and Thornwall (the test_hex_map has road overlays at (0,0) and (1,0); the fixture extends the road through (2,0)→(2,1) so a road path Ashford→Thornwall exists). Hex distance = 3. Range check: Class V's road range = 8 hex, Class III's = 18 hex. Binding = min(18, 8) = 8. Distance 3 ≤ 8 ✓. **Trade route valid, path_kind = 'road'.**

### 12.2 Demand-modifier walkthrough — silk at both settlements

This trace runs RAW's six-step procedure (§4) for one merchandise type with all inputs pinned. The §4.4 deterministic-shuffle outcome for land-revenue distribution is also pinned — in the test fixture, the seeded RNG produces the trace below.

**Silk at Ashford:**

| Step | Operation | Δ | Running total |
|---|---|---|---|
| 1 | Base 1d3-1d3 (pinned roll: +1) | +1 | +1 |
| 2 | Environmental — age 101_1000 (silk row, env table) | -1/2 | +1/2 |
| 2 | Environmental — water (none applicable) | 0 | +1/2 |
| 2 | Environmental — climate (composite grasslands + plains) | +1 + +1 | +2.5 |
| 2 | Environmental — elevation (flat, no modifier) | 0 | +2.5 |
| 3 | Drop fractions (truncate toward zero, §4.3) | — | +2 |
| 4 | Domain land revenue 5 gp: +1 to 2 types, -1 to 1 type. Pinned shuffle: silk is one of the +1 types | +1 | +3 |
| 5 | Racial adjustment (human → no change) | 0 | +3 |
| **Pre-shift modifier** | | | **+3** |

**Silk at Thornwall:**

| Step | Operation | Δ | Running total |
|---|---|---|---|
| 1 | Base 1d3-1d3 (pinned roll: -1) | -1 | -1 |
| 2 | Environmental — age 101_1000 (silk row) | -1/2 | -3/2 |
| 2 | Environmental — water (none) | 0 | -3/2 |
| 2 | Environmental — climate desert | -1 | -5/2 |
| 2 | Environmental — elevation flat | 0 | -5/2 |
| 3 | Drop fractions | — | -2 |
| 4 | Domain land revenue 4: +1 to 4 types, -1 to 1 type. Pinned shuffle: silk is the -1 type | -1 | -3 |
| 5 | Racial (human) | 0 | -3 |
| **Pre-shift modifier** | | | **-3** |

(Env-table values used in the walkthrough are the silk row at `rules/acore-setting-construction-rules.xml:351` — verify against `docs/phase-10b-prereq-environmental-adjustments-table.md` line 71 when implementing.)

### 12.3 Trade-route shift (§5 step 6)

Ashford (urban_families 2,400) is larger than Thornwall (400). Per §5.2, Thornwall shifts toward Ashford.

Silk: Ashford +3, Thornwall pre-shift -3. Diff = 6 ≥ 2 → shift 2 toward larger. Thornwall post = -3 + 2 = **-1**.

(For the §5.4 worked-example merchandise — wood_common, hides_furs, etc. — the post-shift values match RAW arithmetic verbatim. The §5.4 table already documents those; this section adds silk to the mix.)

**Final post-shift demand modifiers (silk):**
- Ashford: **+3** (unchanged — Ashford is the larger market)
- Thornwall: **-1** (was -3, shifted +2)

### 12.4 Market prices

Silk base price: 2,000 gp/load (per §2.4 RAW table). Load weight: 20 stone.

Pinned 4d4 roll at both markets: 10 (the expected value of 4d4 ≈ 10).

**Ashford silk:**
```
percentage = (10 + (+3) + class_III_adjust(0) + monopolist(0) + judge(0)) × 10
           = (10 + 3 + 0) × 10 = 130
gp_per_load = 2000 × 130 / 100 = 2,600 gp
```

**Thornwall silk:**
```
percentage = (10 + (-1) + class_V_adjust(-1) + 0 + 0) × 10
           = (10 - 1 - 1) × 10 = 80
gp_per_load = 2000 × 80 / 100 = 1,600 gp
```

**Gross arbitrage margin: 2,600 - 1,600 = 1,000 gp/load** (selling in Ashford after buying in Thornwall). Direction: **buy in Thornwall (low demand → cheap), sell in Ashford (high demand → expensive).**

### 12.5 Full round-trip P&L — 10 loads of silk

Player buys 10 loads of silk in Thornwall, transports to Ashford, sells.

**Cargo specs:**
- 10 loads × 20 stone/load = 200 stone total cargo
- Carrier: assume the party owns a wagon (cart_small wouldn't fit 200 stone; wagon's normal capacity is 320 stone with a heavy draft team). One wagon suffices.

**Phase 1 — Buy at Thornwall:**

| Item | Amount |
|---|---|
| Silk purchase: 10 × 1,600 | -16,000 gp |
| Entry toll Class V (pinned roll: 1d6=4) | -4 gp |
| Loading labor: 200 stone ÷ 200 = 1.0 → 1 gp | -1 gp |
| Customs duty (only on selling — not applicable) | 0 gp |
| **Phase 1 total** | **-16,005 gp** |

**Phase 2 — Transport Thornwall → Ashford (3 hex via road):**

| Item | Amount |
|---|---|
| Stabling at Thornwall during loading (assume 1 day, 1 wagon) | -2 gp |
| Wilderness movement to Ashford (existing system handles — no commerce fee) | 0 gp |
| Stabling en-route (camped, not stabled — 0 gp) | 0 gp |
| **Phase 2 total** | **-2 gp** |

**Phase 3 — Sell at Ashford:**

| Item | Amount |
|---|---|
| Silk sale: 10 × 2,600 | +26,000 gp |
| Entry toll Class III: max(rolled 1d8+5=10, minimum 1gp/load × 10 = 10) | -10 gp |
| Unloading labor: 200 stone ÷ 200 = 1 gp | -1 gp |
| Customs duty Ashford rate 4%: 4% × 26,000 = 1,040 gp | -1,040 gp |
| Stabling at Ashford during sale (assume 1 day) | -2 gp |
| **Phase 3 total** | **+24,947 gp** |

**Net profit on round-trip:** -16,005 + -2 + 24,947 = **+8,940 gp**

That's a **56% return on the 16,000 gp capital outlay**, achieved over ~5 game days (1 day load + 3 days travel + 1 day unload/sell). Strong arbitrage; consistent with RAW's intent that mercantile is a real income path for adventurers.

### 12.6 Sensitivity — customs rate and domain ownership

The §12.5 baseline uses Ashford's customs at 4% (the low end of the 2-20% annual roll). Two variant scenarios:

**Scenario B — Ashford customs at 16% (rolled high):**

| Item | Amount |
|---|---|
| Phase 3 customs: 16% × 26,000 = 4,160 gp | -4,160 gp |
| Phase 3 net: +26,000 - 10 - 1 - 4,160 - 2 = | **+21,827 gp** |
| Net round-trip: -16,005 - 2 + 21,827 = | **+5,820 gp** |

Still profitable (36% return) but margin reduced by ~3,000 gp. The annual customs roll has a meaningful gameplay impact — a high-customs year at the destination cuts arbitrage profit by ~⅓.

**Scenario C — Ashford is PC-owned domain (domain-owner exemption per §8.8):**

| Item | Amount |
|---|---|
| Phase 3 entry toll: exempt | 0 gp |
| Phase 3 customs: exempt | 0 gp |
| Phase 3 stabling: exempt | 0 gp |
| Phase 3 unloading labor: still 1 gp (per §8.8 labor NOT exempt) | -1 gp |
| Phase 3 net: +26,000 - 1 = | **+25,999 gp** |
| Net round-trip: -16,005 - 2 + 25,999 = | **+9,992 gp** |

PC-domain-owner status converts an already-profitable trip into a maximum-margin trip (62.4% return). Combined with Scenario B's variation, the design has clear levers: domain ownership matters, and annual customs roll matters.

### 12.7 Integration test target

`tests/test_commerce_integration.gd` (Prereq.8, per §14's wave plan):

1. **Pinned-RNG fixture.** Seeds for: §4.1 base roll, §4.4 land-revenue shuffle, §6 4d4 roll, §8.3 entry toll, §8.4 customs annual roll. Reproduces the numbers in §12.2-§12.5 exactly.
2. **End-to-end assertion.** After running:
   - Generate demand modifiers at both settlements (§4)
   - Detect Ashford↔Thornwall trade route (§5.1) and apply shift (§5.3)
   - Compute silk price at each market (§6)
   - Execute a 10-load buy-at-Thornwall / sell-at-Ashford transaction
   - Apply fees per §8
   
   Final party treasury delta = **+8,940 gp** (baseline scenario; Scenario B/C as separate assertions).
3. **Scenario B regression.** Customs at 16%: delta = +5,820 gp.
4. **Scenario C regression.** PC-owned Ashford: delta = +9,992 gp.

These three numbers form the integration test's anchor — if any later refactor produces different outputs, the test fails and the diff points to the broken stage.

### 12.8 Additional canonical routes (collaborative deliverable — TBD)

Per Q-MERC-3 [RESOLVED]: you may provide additional setting-canonical trade routes for v1 validation, or accept candidates I'd derive after seeing the broader campaign map. Format proposal for each additional route:

- Pair of settlement names + hex coords (or settlement_ids if existing fixtures)
- Market classes and rough urban_families
- Biome / biome_subtype / elevation / water context for each end
- Domain land revenue (optional — defaults can apply)
- Expected dominant merchandise pattern (e.g., "mountain town exports rare metals to coastal port that imports them at premium")

Each route adds a §12.A / §12.B / etc. subsection mirroring the §12.1-§12.5 structure. Integration tests pin each route's expected P&L.

`[NEEDS-ADDITIONAL-CANONICAL-ROUTES]` flag if more validation breadth is desired post-MVP.

### 12.9 What §12 does NOT add

- **No multi-trip optimization.** The example is a single round-trip. Multi-leg routes (A→B→C→A profit chains) are emergent; not pre-modeled.
- **No competing-trader simulation.** RAW's "another trader has met his needs" mechanic (§10.1 reference, RAW L715) applies to merchant reaction rolls but not to the price formula. Multiple PCs trading the same merchandise at the same market don't affect each other's prices.
- **No risk model.** Wilderness travel can involve encounters, weather, vehicle damage. §12 assumes a clean trip. Phase 9's wilderness systems are the source of trip-risk modeling; §12's P&L is the upside scenario.
- **No automated balance-tuning loop.** If playtest reveals these margins are too generous or too thin, the levers to adjust are: base prices (§2 — don't touch, RAW), customs rate distribution (§8.4 — could tune 2-20% to 5-15%), demand-modifier amplification (§4 — could scale post-shift values), or fees (§8). All are touchable without schema changes.

---

## §13. Consolidated Migration Plan and Code Inventory

### 13.0 Migration 097 — full sub-step list

Accumulated across §1-§10. Recommended **single atomic transaction** with rollback safety; alternative 3-way split documented in §13.2 if the transaction proves unwieldy in practice.

| # | Operation | Target | Section |
|---|---|---|---|
| 1 | `ALTER TABLE settlement_entrances ADD COLUMN age_years INTEGER NOT NULL DEFAULT 500` | settlement_entrances | §1 |
| 2 | `ALTER TABLE settlement_entrances ADD COLUMN dominant_race TEXT NOT NULL DEFAULT 'human'` | settlement_entrances | §1 |
| 3 | `ALTER TABLE settlement_entrances ADD COLUMN urban_families INTEGER NOT NULL DEFAULT 0` | settlement_entrances | §1 |
| 4 | `ALTER TABLE settlement_entrances ADD COLUMN climate_override TEXT NOT NULL DEFAULT ''` | settlement_entrances | §3.9 |
| 5 | Data-move: `UPDATE settlement_entrances SET urban_families = (SELECT urban_families FROM domains WHERE id = settlement_entrances.parent_domain_id) WHERE parent_domain_id IS NOT NULL` | settlement_entrances | §1.4 |
| 6 | DROP `domains.urban_families` (table-rewrite if SQLite < 3.35; direct DROP if >=3.35) | domains | §1.4 |
| 7 | Table-rewrite `hex_cells.biome_subtype` CHECK to add `clear_steppe`, `clear_scrub` | hex_cells | §3.4.1 |
| 8 | `CREATE TABLE settlement_merchandise_demand` (with `dice_4d4_value` and `dice_last_rolled_calendar_day` columns per §6.5) | new | §4.7 |
| 9 | `ALTER TABLE settlement_entrances ADD COLUMN economy_inputs_changed_day INTEGER NOT NULL DEFAULT 0` | settlement_entrances | §4.9 |
| 10 | `CREATE TABLE trade_routes` | new | §5.5 |
| 11 | `CREATE TABLE merchant_pool` (with `becomes_visible_calendar_day` per §7.8) | new | §7.8 |
| 12 | `ALTER TABLE settlement_entrances ADD COLUMN customs_duty_rate_pct INTEGER NOT NULL DEFAULT 0` + initial backfill (roll for each settlement using `(settlement_id, current_year)` seed) | settlement_entrances | §8.4 |
| 13 | `ALTER TABLE campaigns ADD COLUMN last_customs_roll_year INTEGER NOT NULL DEFAULT 0` | campaigns | §8.4 |
| 14 | `CREATE TABLE ships` | new | §9.2 |
| 15 | `CREATE TABLE cargo_holds` (XOR check on draft_vehicle_id / ship_id) | new | §9.4 |
| 16 | `CREATE TABLE shipping_contracts` | new | §9.7 |
| 17 | `CREATE TABLE character_legal_status` | new | §10.3 |

**17 sub-steps. Wrap all in `BEGIN TRANSACTION; ... COMMIT;` with rollback on error.**

### 13.1 Sub-step ordering constraints

A few sub-steps have ordering dependencies. The migration runner must honor:

- **Sub-step 5 (data-move) requires 3 (urban_families column add) and depends on existing `domains.urban_families`.** Order: 3 before 5 before 6.
- **Sub-step 6 (drop) requires 5 (data move) completion.** No reads from `domains.urban_families` between 5 and 6.
- **Sub-step 12 (customs backfill) requires 4 (climate_override) and existing `settlement_entrances`.** The backfill iterates `settlement_entrances` to set initial rates; the column addition must precede.
- **Sub-step 8 (settlement_merchandise_demand) references `settlement_entrances`** — already exists pre-migration. Standalone.
- **Sub-step 15 (cargo_holds) references `draft_vehicles` and `ships`.** Both must exist; `draft_vehicles` exists pre-migration; `ships` added in 14. Order: 14 before 15.

The order in §13.0's table above satisfies all constraints.

### 13.2 Recommended split — 097a / 097b / 097c (fallback if atomic transaction is unwieldy)

If the single 097 transaction proves problematic (e.g., godot-sqlite memory limits on large table rewrites, or partial-rollback edge cases), split into three migrations:

**Migration 097a — Settlement schema transformation** (sub-steps 1-7, 9, 12-13):
- Settlement column adds + drop
- hex_cells CHECK rewrite
- Customs columns + backfill
- All settlement-side schema changes

**Migration 097b — Commerce data tables** (sub-steps 8, 10, 11):
- settlement_merchandise_demand
- trade_routes
- merchant_pool

**Migration 097c — Cargo and legal tables** (sub-steps 14-17):
- ships, cargo_holds, shipping_contracts
- character_legal_status

Each migration is independently atomic. Apply 097a first, 097b second, 097c third. The waves in §14 ship code corresponding to each migration's tables.

**Recommendation: single 097 transaction first.** Reserve the split as fallback. Most projects' SQLite migration runners handle multi-table transactions cleanly; godot-sqlite specifically has been tested with `query_with_bindings` chains.

### 13.3 Data file additions

New files (relative to repo root):

- `data/commerce/common_merchandise.json` — 20 entries (§2.3)
- `data/commerce/precious_merchandise.json` — 11 entries (§2.4)
- `data/commerce/animals_subtable.json` — 7 entries (§2.5.1)
- `data/commerce/environmental_adjustments.json` — 31 entries × 20 columns (§4.2.1)

Modified files:

- `data/proficiencies/proficiency_specializations.json` — add `attorney` specialization to `profession` array (§10.2)
- `data/equipment/maritime.json` — audit + add `small_sailing_ship` / `large_sailing_ship` entries per RAW Merchant Ships and Caravans table (§9.3)

### 13.4 Code file inventory

#### New files (commerce subsystem)

```
engine/subsystems/commerce/
├── merchandise_registry.gd                          (§2.7 — autoloaded)
├── settlement_economy_inputs.gd                     (§3.8)
├── demand_modifier_generator.gd                     (§4.10)
├── trade_route_detector.gd                          (§5.7.1)
├── region_demand_resolver.gd                        (§5.7.2)
├── market_price_resolver.gd                         (§6.8)
├── merchant_pool_repository.gd                      (§7.9)
├── market_fees_calculator.gd                        (§8.9)
├── ship_repository.gd                               (§9.10)
├── cargo_hold_repository.gd                         (§9.10)
├── shipping_contract_repository.gd                  (§9.10)
└── cargo_encumbrance_calculator.gd                  (§9.5)

engine/subsystems/syndicate/
└── character_legal_status_repository.gd             (§10.4)
```

#### Modified files

- `project.godot` — register `MerchandiseRegistry` autoload (§2.7).
- `engine/autoloads/event_bus.gd` — add ~22 new signals (consolidated in §13.5).
- `engine/autoloads/campaign_repository.gd` — add helpers consumed by the commerce subsystems (settlement-economy-inputs getters, customs-rate accessor, ship/cargo CRUD wrappers if needed).
- `engine/subsystems/session/handlers/domain_handlers.gd` — wire monthly tick callbacks:
  - `MerchantPoolRepository.process_monthly_refresh_for_campaign`
  - `MarketPriceResolver.process_monthly_drift_for_campaign`
  - `ShipRepository.process_monthly_operating_costs_for_campaign`
  - `MarketFeesCalculator.process_annual_customs_roll_for_campaign` (year boundary only)
  - `MerchantPoolRepository.process_expirations` (per settlement, just before monthly refresh)
- `engine/subsystems/session/session_runner.gd` — no changes if monthly tick already routes through DomainMonthlyResolver. Verify during Prereq.2a.
- `engine/subsystems/henchmen/henchman_loyalty_resolver.gd` — extend `resolve_loyalty_check` per §11.2.
- `db/schema.sql` — append migration 097's full schema (the source of truth for the post-migration shape).
- `docs/coding_conventions.md` — add §52 commerce-subsystem conventions (per CLAUDE.md update-on-new-pattern rule).
- `build_log.md` — append per-wave entries.
- `tests/test_runner.gd` + `tests/test_runner.tscn` — register all new test suites.

### 13.5 EventBus signal additions (consolidated)

```gdscript
# §4 — demand modifier
signal demand_modifiers_regenerated(settlement_id: String)
signal settlement_economy_inputs_changed(settlement_id: String, reason: String)

# §5 — trade routes
signal trade_route_detected(route_id: String, settlement_a_id: String, settlement_b_id: String)
signal trade_route_invalidated(route_id: String)
signal region_demand_resolved(anchor_settlement_id: String)

# §6 — market price
signal market_price_drifted(settlement_id: String, merchandise_type: String, old_dice: int, new_dice: int)

# §7 — merchant pool
signal merchant_pool_refreshed(settlement_id: String, new_merchant_count: int)
signal solicitation_started(settlement_id: String, character_id: String, merchants_revealed_count: int)
signal merchant_surfaced_via_locate(merchant_id: String, settlement_id: String, merchandise_type: String)
signal merchant_loads_consumed(merchant_id: String, loads_consumed: int, loads_remaining: int)
signal merchant_depleted(merchant_id: String, settlement_id: String)
signal merchant_expired(merchant_id: String, settlement_id: String)

# §9 — ships and cargo
signal ship_created(ship_id: String, party_id: String, vessel_key: String)
signal ship_destroyed(ship_id: String, party_id: String)
signal ship_location_changed(ship_id: String, new_kind: String, settlement_id: String)
signal ship_operating_cost_paid(ship_id: String, gp_amount: int)
signal ship_operating_cost_unpaid(ship_id: String, owed_gp: int)
signal cargo_loaded(cargo_hold_id: String, carrier_id: String, merchandise_type: String, loads_count: int)
signal cargo_sold(cargo_hold_id: String, gp_received: int)
signal shipping_contract_accepted(contract_id: String, party_id: String, fee_gp: int)
signal shipping_contract_delivered(contract_id: String, fee_paid_gp: int, deadline_missed: bool)
signal shipping_contract_failed(contract_id: String, reason: String)

# §10 — legal status
signal character_legal_status_changed(character_id: String, flag: String, new_value: int, modifier_total: int)
```

22 new signals total.

### 13.6 Coding-conventions update (`docs/coding_conventions.md` §52)

Per CLAUDE.md's "update on new pattern" rule. Section to append:

```
## §52. Commerce subsystem conventions

### 52.1 Registry pattern
- MerchandiseRegistry is the autoloaded source of truth for merchandise data.
- All other commerce subsystems are RefCounted static-function libraries (not autoloaded).
- Data files live in data/commerce/ with version+source headers.

### 52.2 Price resolver as SSoT for prices
- MarketPriceResolver.compute_market_price is the only place 4d4 dice get rolled for prices.
- Ad-hoc 4d4 elsewhere = drift; forbid.

### 52.3 Banker's rounding for gp math
- All gp math uses RoundingUtil.banker_round at aggregate boundaries.
- Exception: §4.3 "drop fractions" (env-modifier sum) uses truncate-toward-zero per RAW.

### 52.4 Settlement-economy read-side semantics
- Reads route through SettlementEconomyInputs.resolve_all(settlement_id).
- Direct DB reads of settlement economy fields = bypassing the cache + override layer; forbid.

### 52.5 Per-merchant vs aggregate semantics
- merchant_pool rows are per-merchant (one row, one merchant).
- cargo_holds rows are per-acquisition (one row, one shipment of one merchandise type from one source).
- Don't mix.

### 52.6 Calendar-time references
- Use Timekeeping.DAYS_PER_MONTH (= 28) for all monthly windows. Never hard-code 30.
- For year-aligned events (annual customs roll), use Timekeeping.MONTHS_PER_YEAR.
```

### 13.7 build_log.md per-wave entries

Each wave (per §14's wave plan) gets a build_log entry following CLAUDE.md's template: task / model used / completed / decisions made / interfaces defined or changed / database changes / tests added/updated / known issues / next session should.

**Special build_log entry at end of Prereq.GDD wave:** "Settlement-Economy GDD locked. All 14 sections signed off by Jedidiah. Ready for Prereq.1."

---

## §14. Wave Plan, Test Budget, and Acceptance Criteria

### 14.0 Wave order

The handoff doc's §7 8-wave plan expanded to **12 waves** as scope was refined (Prereq.5 split into 5a/5b/5c per Q-MERC-7; Prereq.2 already split into 2a/2b/2c per the earlier handoff revision).

| Wave | Scope | Migration impact | GDD sections |
|---|---|---|---|
| **Prereq.GDD** | This document. Section-by-section sign-off. | None | §0-§14 |
| **Prereq.1** | Merchandise registry + JSON data + autoload registration | None (data only) | §2 |
| **Prereq.2a** | Migration 097 applies. Settlement schema additions (`age_years` / `dominant_race` / `urban_families` / `climate_override` / `customs_duty_rate_pct` / `economy_inputs_changed_day`, plus the urban_families relocation). hex_cells CHECK rewrite. customs_duty backfill. SettlementEconomyInputs service + tests. DemandModifierGenerator steps 1-5 + cache writes. | 097 sub-steps 1-9, 12-13 (or 097a if split) | §1, §3, §4 |
| **Prereq.2b** | Trade route detection + region walk. trade_routes table. Cyfaraun/Samos worked-example test (renamed to Ashford/Thornwall per §5.4). | 097 sub-step 10 (or 097b) | §5 |
| **Prereq.2c** | Market price resolver + monthly drift mechanic + 4d4 cache integration. | None (extends settlement_merchandise_demand from 2a) | §6 |
| **Prereq.3** | Market fees calculator — pure-function helpers + annual customs roll trigger wired into DomainMonthlyResolver. | None (uses 2a's customs columns) | §8 |
| **Prereq.4** | Merchant pool: merchant_pool table + MerchantPoolRepository + monthly refresh logic + solicit/locate data paths. | 097 sub-step 11 (or 097b) | §7 |
| **Prereq.5a** | Ships persistence: ships table + ShipRepository + monthly operating-cost integration into DomainMonthlyResolver. Maritime catalog audit + small/large sailing ship entries. | 097 sub-step 14 (or 097c start) | §9.2-§9.3, §9.6, §9.10 |
| **Prereq.5b** | Cargo holds: cargo_holds table + CargoHoldRepository + CargoEncumbranceCalculator. Hijink-yield data-path helpers. | 097 sub-step 15 (or 097c cont.) | §9.4-§9.5, §9.8, §9.10 |
| **Prereq.5c** | Shipping contracts: shipping_contracts table + ShippingContractRepository. Multi-leg arbitrage data path. | 097 sub-step 16 (or 097c cont.) | §9.7, §9.9, §9.10 |
| **Prereq.6** | Crime & Punishment data prereqs: attorney specialization addition + character_legal_status table + CharacterLegalStatusRepository. ProficiencyRegistry API verification. | 097 sub-step 17 (or 097c end) | §10 |
| **Prereq.7** | Audits: Spell-cost lookup gap documented (no code shipped). HenchmanLoyaltyResolver `extra_modifiers` parameter extension. | None (code only) | §11 |
| **Prereq.8** | Integration tests: `tests/test_commerce_integration.gd` reproducing §12's worked example. End-to-end fixture with pinned RNG. Scenario B/C regression tests. Cross-subsystem integration check. build_log close-out + coding_conventions §52 commit. | None | §12 |

**Migration timing.** If using single atomic 097: applies at the **start of Prereq.2a**. All subsequent waves write against the post-migration schema.

If using 097a/b/c split: 097a applies at start of Prereq.2a; 097b applies during Prereq.2a (settlement_merchandise_demand needed before procedure runs); 097c applies at start of Prereq.5a.

### 14.1 Test budget per file

| Test file | Tests | Section(s) |
|---|---|---|
| `tests/test_settlement_economy_inputs.gd` | ~25 (§1 schema + §3 inputs) | §1.8, §3.10 |
| `tests/test_merchandise_registry.gd` | 8 | §2.9 |
| `tests/test_demand_modifier_generator.gd` | ~18 | §4.11 |
| `tests/test_trade_route_detector.gd` | ~10 | §5.8 |
| `tests/test_region_demand_resolver.gd` | ~12 | §5.8 |
| `tests/test_market_price_resolver.gd` | 14 | §6.10 |
| `tests/test_merchant_pool_repository.gd` | ~18 | §7.12 |
| `tests/test_market_fees_calculator.gd` | 16 | §8.10 |
| `tests/test_ship_repository.gd` | ~8 | §9.12 |
| `tests/test_cargo_hold_repository.gd` | ~10 | §9.12 |
| `tests/test_cargo_encumbrance_calculator.gd` | ~7 | §9.12 |
| `tests/test_shipping_contract_repository.gd` | ~5 | §9.12 |
| `tests/test_character_legal_status_repository.gd` | ~7 | §10.6 |
| `tests/test_attorney_specialization.gd` | ~3 | §10.6 |
| `tests/test_henchman_loyalty_resolver.gd` (existing — extend) | +4 | §11.2 |
| `tests/test_commerce_integration.gd` | ~5 + scenario regressions | §12.7 |

**Total: ~170 tests across 15 files.**

(Handoff §7 estimated 65-90 tests across 10 waves. Actual scope landed higher — the Q-MERC-7 full vehicle/cargo build alone added ~30 tests beyond the original stub plan, and §3/§4 grew with the composite-climate rewrite.)

### 14.2 Acceptance criteria

Per the handoff §13's three-corner alignment principle:

1. **RAW citations every project-design element.** Every section's project-design ledger entry must cite an XML file + line range and explain what RAW provides vs. what's missing. Verified: ✓ across §0-§12.
2. **JSON data matches RAW tables exactly.** `data/commerce/*.json` cross-checks against `rules/acore-campaign-hijinks.xml:915-947, 949-974` (merchandise) and `rules/acore-setting-construction-rules.xml:297-353` (environmental adjustments). The `?? Verify`-flagged cells in `docs/phase-10b-prereq-environmental-adjustments-table.md` get final PDF re-check during Prereq.1 encoding.
3. **GDD matches code matches schema.** Every wave's build_log entry confirms the alignment.

**Acceptance check at end of Prereq.8 (full session):**
- [ ] `MerchandiseRegistry.get_by_type("silk")` returns `{base_price_gp: 2000, load_weight_stone: 20, precious: true}`.
- [ ] `MarketPriceResolver.compute_market_price("silk", ashford_settlement_id, ...)` returns the 2,600 gp/load value from §12.4 (with pinned RNG).
- [ ] `MerchantSolicitor.process_solicitation(ashford_settlement_id, ...)` reveals the pool's invisible merchants on the half/quarter/remainder schedule per §7.5.1.
- [ ] `MarketFeesCalculator.customs_duty_gp(26000, ashford_settlement_id, false)` returns 1,040 gp (4% × 26000).
- [ ] `CargoHoldRepository.insert_purchase(...)` writes a row with `source_acquisition_kind='purchased'`; cascade behavior verified on parent vehicle destruction.
- [ ] `CharacterLegalStatusRepository.get_prior_crimes_modifier(branded_maimed_character_id)` returns -3.
- [ ] `HenchmanLoyaltyResolver.resolve_loyalty_check(5, false, false, fixed_dice, {"hijink_overload": -3})` returns a result with `modifier` 3 less than the no-extras case.
- [ ] `tests/test_commerce_integration.gd` passes — full §12 round-trip P&L matches +8,940 gp / +5,820 gp / +9,992 gp for the three scenarios.

When all boxes are checked, Phase 10B.2 (Trade) and 10B.3 (Syndicate) are unblocked.

### 14.3 Coordination notes

- **No `monster_catalog.json` or `domain_encounter_resolver.gd` modifications** — the parallel monster-data session owns those (per handoff §10).
- **No Phase 10B.1 magical-research files** — that session's UI polish is in flight; coordinate via build_log if migration numbering shifts again. Current confirmed: Phase 10B.1 consumed migrations 092-096; this session reserves 097+.
- **No XML rules edits.** The 2026-05-11 environmental-adjustments correction was explicitly approved as a one-instance transcription-fidelity fix. CLAUDE.md sacred-rules policy remains in force.
- **Terrain canon harmonization deferred** per the 2026-05-12 decision. The `[NEEDS-TERRAIN-CANON-REWORK]` source-code flags are placed at the §3.4 mapping commitment points so a future terrain-canon session can grep them and audit in one pass.

### 14.4 Open follow-up flags planted during the GDD

A consolidated list of `[NEEDS-...-PASS]` source-code flags that this session deliberately leaves for future enhancement:

- `[NEEDS-TERRAIN-CANON-REWORK]` — §3.4 climate mapping commitments
- `[NEEDS-FLAVOR-PASS]` — §4.4 deterministic-shuffle land-revenue distribution (could become semantic-categorized)
- `[NEEDS-DRIFT-PRECISION-PASS]` — §6.6.4 monthly drift's event-time fidelity
- `[NEEDS-DOMAIN-OWNER-EXEMPTION-CLARIFY]` — §8.8 (now resolved per Jedidiah 2026-05-12 to include customs; flag remains for labor inclusion if you change your mind)
- `[NEEDS-OTHER-PACK-ANIMAL-PASS]` — §8.7 (resolved for donkey/camel/ox; flag remains for future species)
- `[NEEDS-PHASED-AVAILABILITY-PASS]` — §7.5 solicit_merchants (now resolved with the staggered model per Jedidiah 2026-05-12; flag removed)
- `[NEEDS-DISTRIBUTION-CALIBRATION]` — §7.6.1 merchandise distribution per merchant
- `[NEEDS-PRECIOUS-RATE-PASS]` — §7.13 if 15% precious feels wrong
- `[NEEDS-MERCHANT-SOURCING-PASS]` — §7.13 spawn-via-trade-route enhancement
- `[NEEDS-FEE-OVERRIDE-PASS]` — §8.11 Judge-authored special fees
- `[NEEDS-FEE-AUDIT-TRAIL-PASS]` — §8.11 fee history
- `[NEEDS-REPUTATION-FEES-PASS]` — §8.11 reputation-driven discounts
- `[NEEDS-CREW-MORALE-PASS]` — §9.6.1 non-payment consequences
- `[NEEDS-NAVIGATOR-SEPARATE-ROLE-PASS]` — §9.6 navigators distinct from sailors
- `[NEEDS-CARAVAN-MONTHLY-COST-PASS]` — §9.6.2 caravan operating costs
- `[NEEDS-LATE-DELIVERY-PENALTY-PASS]` — §9.7 partial-fee/reputation for missed deadlines
- `[NEEDS-NAVAL-MOVEMENT-PASS]` — §9.13 sea-specific travel mechanics
- `[NEEDS-CREW-INDIVIDUATION-PASS]` — §9.13 individual crew tracking
- `[NEEDS-PERMANENT-WOUND-COMBAT-PASS]` — §10.3.1 Maimed combat effects
- `[NEEDS-PROFICIENCY-API-VERIFICATION]` — §10.2.1 verify specialization-aware proficiency lookup
- `[NEEDS-SPELL-COST-LOOKUP-PASS]` — §11.1 Spell Availability by Market table encoding
- `[NEEDS-MARITIME-CATALOG-VERIFICATION]` — §9.3 maritime.json audit
- `[NEEDS-CARRIER-FALLBACK-PASS]` — §9.8 hijink yield when no carrier available
- `[NEEDS-ADDITIONAL-CANONICAL-ROUTES]` — §12.8 additional validation routes

Most are quality-of-life or v1.1+ enhancements. The two most impactful for v1 are likely `[NEEDS-SPELL-COST-LOOKUP-PASS]` (for Phase 10A.2 polish) and `[NEEDS-PROFICIENCY-API-VERIFICATION]` (Prereq.6 verifies before §10 ships).

---

## End of GDD

`generation/gdd-settlement-economy.md` is complete with 14 sections. Per Q-MERC-1 [RESOLVED]: every project-designed element has a RAW citation and an explicit gap explanation. The mandatory §5.0 format has been followed throughout. No silent project-design.

**Next step:** Prereq.1 (merchandise registry) — encode `data/commerce/*.json` from the RAW Common Merchandise / Precious Merchandise / Environmental Adjustments tables, build `engine/subsystems/commerce/merchandise_registry.gd`, register as autoload, ship 8 tests.

