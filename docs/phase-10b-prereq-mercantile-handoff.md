# Phase 10B Prerequisite — Mercantile / Trade Goods System — Session Handoff Prompt

> **Purpose.** This document is a self-contained briefing for the **parallel session** that builds the merchandise / market-price / merchant-pool / mercantile-fees subsystems that Phase 10B.2 (Trade block) and Phase 10B.3 (Syndicate block) consume. It also lands the Crime & Punishment data prerequisites for 10B.3. This session is independent of Phase 10B.1 (Magical Research, nearly complete as of writing) and the parallel monster-data session.
>
> **How to use it.** Paste the contents of this file (or just point at the path) as the opening message of a new session. The session should follow the standard "Build Session Protocol" in `CLAUDE.md` first, then read this document, then begin the grounding investigation described in §3 below.
>
> **Status:** Drafted 2026-05-11. Phase 10B.1 is in UI-polish phase; Phase 10A is complete; the monster-data parallel session is running. This is the third concurrent build track.
>
> **WARNING — this is a HARD build.** Per Jedidiah: "not fully explicated in the RAW and will need project-design gap filling." The RAW gives base tables and a formula but is silent on several critical mechanisms (per-settlement demand seeding, demand drift over time, merchant pool composition, NPC merchant migration). **§5 of this handoff enumerates every gap and proposes a project-design resolution for Jedidiah's approval.** Do NOT just start coding from `phase-10b-subsystem-dependencies.md` — that document is a scope index, not a build plan.

---

## 1. Where this fits in the project

### Locked Phase 10 wave order
- ✅ **Phase 10A.1 / 10A.2 / 10A.3** — shipped (Class-Specific sub-tab shell + Faith block + Bardic Patronage + proficiency-gated training)
- 🟡 **Phase 10B.1** — in UI polish (Magical Research block; nearly done)
- ⏳ **Phase 10B.2** — Trade block (Venturer). **Blocked on this session.**
- ⏳ **Phase 10B.3** — Syndicate block (Thief / Assassin / Elven Nightblade). **Blocked on this session.**
- ⏳ **Phase 10C** — Ritual Magic. Independent of this session. Will also subsume ritual *research* (resolved 2026-05-11: research and casting for rituals land together in 10C, not split across 10B.1 and 10C).

### Why this session exists (not just a 10B.2 sub-phase)
- Per **Q5** in `docs/phase-10-plan.md`, Jedidiah elected to build Trade and Syndicate as *full* implementations (no v1 stubs), but acknowledged that the prerequisite subsystems are large enough to warrant their own session. The scope is detailed in `docs/phase-10b-subsystem-dependencies.md` (eight subsystems).
- This session is the **prerequisite work**. The follow-up Phase 10B.2 and 10B.3 sessions will consume what this session produces.

### What this session DOES build
- Merchandise registries (Common + Precious)
- Market price resolver (4d4 + demand + class adjust + monopolist bonus formula)
- Per-settlement demand modifier system (the biggest project-design gap)
- Per-settlement merchant pool generation (`solicit_merchants` Ongoing-handler core)
- Market fees calculator (customs, moorage, stabling, tolls)
- Vehicle/cargo aggregate stub (recommended per Q5; full vehicle system deferred)
- Profession (attorney) proficiency + prior-crimes character columns (Crime & Punishment data side)
- Spell-cost lookup audit + Henchman Loyalty API audit (mostly verification, possibly small extensions)

### What this session does NOT build
- The Trade block UI (10B.2)
- The Syndicate block UI (10B.3)
- Hijink resolvers (assassinating, carousing, smuggling, etc. — those live in 10B.3)
- The Crime & Punishment resolver itself (10B.3); only its data prerequisites
- Vehicle/cargo full implementation (deferred per Q5)
- NPC venturer rivals (deferred to v1.1+ per Q7)

---

## 2. The scope index already exists

**Read `docs/phase-10b-subsystem-dependencies.md` first.** It enumerates the eight subsystems and is the authoritative scope index. This handoff:

- Adds the project-design gap analysis the dependencies doc doesn't go into
- Provides RAW grounding so the next session can verify the dependency-doc's claims against the actual XML
- Establishes the patterns (mirroring Phase 10A) and the suggested wave-split
- Flags new clarification questions for Jedidiah

Do NOT treat the dependency doc as a build plan — it sketches the API surface and table shapes but leaves the *project-design* questions implicit. This handoff makes them explicit.

---

## 3. Required reading (in priority order)

### 3.1 Project foundation (per `CLAUDE.md`)
- `CLAUDE.md` (project root)
- `build_log.md` (tail; the Phase 10A.3 + 10B.1 + 10B.1-handoff entries are most recent)
- `docs/acks_arbiter_design_brief_v11.md` (Grep relevant sections)
- `docs/document_map.md`, `docs/rule_system_map.md`
- `docs/coding_conventions.md` — read §49 (ClassBucketResolver SSoT), §50 (proficiency-gated activity patterns). This session will likely add §52+ as it establishes new conventions for commerce subsystems.

### 3.2 Phase 10 context (small; read fully)
- `docs/phase-10-plan.md` — read **Q5, Q6, Q7, Q8** in the locked-decisions block. Also read **§Phase 10B.2** and **§Phase 10B.3** to understand what this session unblocks.
- `docs/phase-10b-subsystem-dependencies.md` — the scope index. **Read fully.**
- `docs/phase-10b-1-handoff.md` — sibling handoff for the Magical Research session. Reference for handoff format / patterns. Do not duplicate work.

### 3.3 RAW — mercantile core (Grep, don't load all at once)

| File | Lines | Coverage | Priority |
|---|---|---|---|
| `rules/acore-setting-construction-rules.xml` | ~720 | **MASTER demand-modifier generation rules.** §generating_demand_modifiers (L221-367) — the complete six-step procedure with all lookup tables (environmental adjustments, domain land revenue, racial adjustments, range of trade, trade route shift example). Also §placing_villages_towns_and_cities (L161-218) for settlement-on-water placement. **THE foundational read.** | P0 |
| `rules/acore-campaign-hijinks.xml` | 1092 | **Master pricing rules.** Contains: `<market_classes>` (L631), `<demand_modifiers>` (L640), `<market_and_merchants>` table (L656), `<common_merchandise>` table (L915), `<precious_merchandise>` table (L949), arbitrage/smuggling/stealing payout formulas, monthly drift trigger (L737-739). Pairs with the setting-construction file. | P0 |
| `rules/ax_campaign_play.xml` | 1256 | `<category name="mercantile">` block — activity definitions (buy_sell_*, commission_*, enter_market, hire_hirelings, persuade_*, solicit_*). Grep for `<category name="mercantile">`. | P0 |
| `rules/ax_venturer_class.xml` | 485 | Venturer class powers consuming this infrastructure: `trade_route` (L159), `mercantile_network` (L100ish), `monopoly_power` (L203). The Markets and Merchants follow-on table is at L398-422 (market_class column rows for I-VI). | P0 |
| `rules/acore_axioms_strongholds_and_domains.xml` | 707 | Settlement size → market class table (L658-704). `urban_families` mechanics. | P1 |
| `rules/acore_equipment.xml` | — | Base prices for goods (Common Merchandise overlaps; verify cross-references). | P2 |
| `rules/pc_equipment_catalog.xml` | — | Extended equipment + merchandise data. | P2 |
| `rules/daw_equipment_and_construction.xml` | — | Bulk/cargo construction equipment. | P3 |

### 3.4 RAW — Crime & Punishment data prerequisites (§6 of dependency doc)
- `rules/acore-campaign-hijinks.xml` L260-315 — the Crime & Punishment table and modifiers (prior_crimes, Profession (attorney), brands/maims/proscriptions).
- `rules/pc_proficiencies_catalog.xml` — verify Profession (attorney) is in the catalog.

### 3.5 GDDs
- `generation/gdd-domain-tab.md` §12.3 (Trade block UI spec; this session doesn't build the UI but the data shapes must support it) and §12.5 (Syndicate block — same reasoning).
- `generation/gdd-settlement-stocking.md` — read fully. This is the closest existing project-design surface for settlement traits. Likely the natural place to anchor the per-settlement demand mean.
- `generation/gdd-settlement-exploration-ui.md` — for understanding how the merchant pool surfaces to the player in v1.1+.

### 3.6 Existing engine code (read fully or grep)
- `db/schema.sql` — already has `urban_families` (settlements row), `market_class` (settlements row), `market_class_modifiers` (Phase 9A — temporary class shifts from sieges/threats; this session may extend it for monopoly-driven price floors).
- `engine/autoloads/campaign_repository.gd` — pattern for adding helpers (see Phase 10A.2's faith helpers at the bottom for the canonical pattern).
- `engine/autoloads/event_bus.gd` — pattern for adding signals.
- `engine/subsystems/spells/spell_registry.gd` — pattern for a static data registry (mirrors what `MerchandiseRegistry` should look like).
- `engine/subsystems/domains/faith_monthly_resolver.gd` — pattern for monthly-tick resolver. The price-drift step in this session will mirror this structure.
- `tests/test_faith_block.gd` — pattern for a focused subsystem test suite (~20 tests; cross-pollination guards).

### 3.7 Database
- `db/schema.sql` — current schema (last migration: 091 from Phase 10A.2).
- `db/migrations/091_faith_block.sql` — template migration with multi-table additions. This session will likely produce **migration 092 or 093** (depending on whether Phase 10B.1 lands 092 first — coordinate via build_log).

---

## 4. Locked decisions from Phase 10 (do not re-litigate)

- **Q5** — Full implementation for Trade and Syndicate. Vehicle/cargo system is **v1-stubbed** (aggregate view, no per-vehicle tracking).
- **Q6** — Full Crime & Punishment resolver. Permanent-wound / amputation / execution outcomes are logged but do NOT mutate character state in v1.
- **Q7** — Single venturer claims monopoly atomically per settlement. NPC venturer rivals **deferred to v1.1+**.
- **Q8** — Per-hijink resolution for PC syndicates; NPC-only syndicates use the simplified `monthly_hijink_income_table` ([rules/acore-campaign-hijinks.xml:501-518](rules/acore-campaign-hijinks.xml:501)) as a perf shortcut.
- Settlement market class is **derived from `urban_families`** per [rules/acore_axioms_strongholds_and_domains.xml:658-704](rules/acore_axioms_strongholds_and_domains.xml:658). Settlements row already stores both columns. Do not duplicate the derivation.
- **Banker's rounding everywhere** (RoundingUtil). Market price math is full of multiplications and percentages; this matters.

---

## 5. RAW ENCODING + PROJECT-DESIGN GAPS

### 5.0 Mandatory rule (per Jedidiah 2026-05-11)

**Every project-designed element in the GDD MUST cite the relevant RAW section and explicitly state what RAW provides versus what is missing.** No silent project-design. No "we'll figure this out as we go." The GDD is the audit trail: if a future contributor asks "why does this work this way," the GDD must point them at the RAW citation (if any) and the project-design rationale (where RAW is silent).

Format for each gap entry:
- **RAW citation:** exact file + line range
- **What RAW provides:** verbatim summary of what's encoded in RAW
- **What's missing:** precise gap that needs project-design fill
- **Proposed resolution:** option + rationale, for Jedidiah review

### 5.A Demand modifier generation — RAW encoding + corrupted-source recovery

**RAW citation:** [rules/acore-setting-construction-rules.xml:221-367](rules/acore-setting-construction-rules.xml:221) §generating_demand_modifiers.

**What RAW provides (complete six-step procedure):**
1. **Base roll:** 1d3-1d3 per merchandise type (range -2 to +2)
2. **Environmental adjustment:** apply modifiers from the environmental_adjustments_to_demand table for the settlement's age, water source, climate, and elevation
3. **Drop fractions** after environmental modifiers applied
4. **Domain land revenue adjustment:** per the domain_land_revenue_to_demand_modifiers table (L237-251), apply +1/-1 to a specified count of merchandise types based on the settlement's domain land revenue per family (3-9gp scale)
5. **Racial adjustment:** Dwarf settlements -2 to beer/ale, common metals, tools, armor/weapons, rare metals, semi-precious stones, gems; Elf settlements -2 to common wood, dyes/pigments, cloth, glassware, porcelain
6. **Trade route shift:** for markets connected by a valid trade route (road/trail/navigable waterway within range-of-trade), shift smaller market's modifiers 2 points toward larger market (or equalize if difference < 2); equal-size markets shift each modifier 1 point toward each other

Plus complete lookup tables:
- **environmental_adjustments_to_demand** (L297-356) — 20 columns × ~25 merchandise rows. Climate columns: rainforest, savanna, desert, steppe, scrub, grasslands, deciduous_forest, taiga, tundra_plains, extra_climate. Plus age (5 buckets), water (sea_coast / lake_shore / river_bank), elevation (hills, mountains).
- **domain_land_revenue_to_demand_modifiers** (L237-251)
- **racial_adjustments_to_demand** (L253-262)
- **range_of_trade** (L264-278) — by market class, road miles vs water miles
- **trade_route_shift_example** (L280-295) — Cyfaraun/Samos worked example

**What's missing — the genuine project-design gaps:**

#### 5.A.1 Corrupted source rows (RAW-flagged) — RESOLVED 2026-05-11

The environmental_adjustments_to_demand table at [L297-356](rules/acore-setting-construction-rules.xml:297) carries a `<source_integrity_note>` flagging 7 corrupted late-luxury rows.

**Resolution:** Jedidiah supplied the canonical table from the source PDF via screenshot 2026-05-11. Full transcription captured in **`docs/phase-10b-prereq-environmental-adjustments-table.md`**. Key findings:
- Two XML column-naming errors discovered: `tundra_plains` should be two columns (`tundra`, `plains`); `extra_climate_or_wrap` is a transcription artifact and doesn't exist.
- Full merchandise list is 31 entries (21 common + 10 precious), not the ~25 the XML transcribed.
- All previously-corrupted rows now have canonical values.

**Action for the mercantile session:** Use the new artifact as the source of truth for encoding `data/commerce/environmental_adjustments.json`. The XML rules file stays as-is (per CLAUDE.md sacred-rules policy) until Jedidiah explicitly approves an update. Re-verify the `?? Verify`-flagged cells in the artifact against the screenshot/PDF when committing JSON.

#### 5.A.2 Settlement age — input not yet in schema

RAW step 2 requires settlement age bucket (0-20 / 21-100 / 101-1000 / 1001-2000 / 2001+ years).

**Project status:** the `settlements` table does NOT currently track age. Setting-generation (when it lands) is the natural source; for now we have placeholder/judge-supplied data.

**Resolution:**
- Add `age_years INTEGER NULL` and/or `age_bucket TEXT` column to `settlements` (new migration).
- For settlements without recorded age, default to "21-100 years" (the most common bucket per ACKS-era assumptions; see L62 §developing_realms "50 people per square mile" baseline).
- Setting-generation phase will populate ages procedurally; this session just adds the column and defaults.

#### 5.A.3 Climate input mapping (project ↔ RAW)

RAW step 2 enumerates 10 climate buckets: rainforest, savanna, desert, steppe, scrub, grasslands, deciduous_forest, taiga, tundra_plains, plus an "extra climate or wrap" catch-all column.

**Project status:** hexes have `biome` (clear / woods / jungle / swamp / desert) + `biome_subtype` (the recently-added fifth orthogonal tag per the 2026-05-11 hex-terrain rewrite; see build_log entry "Phase 9-prep: hex subtype system").

**Resolution:** GDD must author a **deterministic mapping table** from (biome, biome_subtype) → RAW climate bucket. Examples:
- biome=swamp → rainforest (if jungle-adjacent) or scrub
- biome=desert + biome_subtype=badlands → desert (RAW direct)
- biome=woods + biome_subtype=taiga → taiga (RAW direct)
- biome=woods + biome_subtype=deciduous_forest → deciduous_forest (RAW direct)
- biome=clear + biome_subtype=grasslands → grasslands (RAW direct)
- biome=clear + biome_subtype=steppe → steppe (RAW direct)

Most subtype values map cleanly because the project subtype list was authored against the same biogeographical vocabulary RAW uses. Where mapping is ambiguous, GDD must justify with citation.

#### 5.A.4 Water-source proximity detection

RAW step 2 requires sea_coast / lake_shore / river_bank classification.

**Project status:** hex overlay data tracks rivers; biome supports ocean/lake (per the recent hex terrain rewrite). Settlements are placed on hexes per RAW §placing_villages_towns_and_cities step 4 ("preferentially on rivers, lakes, coastlines, and roads") [L170](rules/acore-setting-construction-rules.xml:170).

**Resolution:** GDD authors the lookup query:
- `sea_coast` ← settlement's hex (or adjacent) has biome=ocean
- `lake_shore` ← settlement's hex (or adjacent) has biome=lake
- `river_bank` ← settlement's hex has a river overlay
- Else: no water modifier applies (RAW has no "inland" column; modifier = 0)

Adjacency lookup uses standard hex neighbors; no new schema needed.

#### 5.A.5 Elevation extraction

RAW step 2 enumerates hills and mountains as elevation modifiers.

**Project status:** hexes have elevation data; settlements inherit from their hex.

**Resolution:** GDD documents the existing lookup. Most likely no schema change needed; just confirm the inheritance path.

#### 5.A.6 Race lookup per settlement

RAW step 5 requires Dwarf/Elf identification.

**Project status:** TBD — must inspect schema. If settlements don't have a dominant-race field, this session may need to add one (likely small column addition).

**Resolution:** Audit `settlements` schema. If `dominant_race` or similar is missing, add it in this session's migration; default to "human" (no racial adjustment applies).

#### 5.A.7 Domain land revenue lookup

RAW step 4 requires the settlement's domain land revenue per family.

**Project status:** domain economy is tracked; the per-family revenue is derivable from existing tables (or already exposed via a helper). Audit `engine/subsystems/domains/` for the canonical lookup.

**Resolution:** GDD cites the existing accessor. No new code unless an accessor gap is found.

#### 5.A.8 Trade route detection algorithm

RAW step 6 specifies "two criteria are required for a trade route: a connecting road/trail/navigable waterway, AND both markets must lie within each other's trade range" (L362).

**Project status:** roads/trails should be on hex overlay data; navigable waterways derive from biome (ocean/lake) and river overlays. Hex distance is straightforward.

**Resolution:** GDD authors the trade-route detection algorithm citing RAW step 6 + range_of_trade table:
1. For each pair of settlements within max-range hexes of each other:
2. Check if a connecting path exists via road/trail overlay (road graph traversal) OR navigable waterway (water-hex chain)
3. If both, check the smaller settlement's market class against the range_of_trade table: is the larger settlement within its road range or water range?
4. If yes: emit a trade route between them; processed by step 6 shift mechanic

Algorithm complexity: O(settlements² × hex-distance) worst case; cache results until road or settlement change invalidates.

#### 5.A.9 Processing order — largest market first

RAW step 6 says "When processing a region, begin with the largest market and work outward through direct trade routes, then continue to the next markets" [L365](rules/acore-setting-construction-rules.xml:365).

**Resolution:** GDD specifies a region-walk order:
1. Sort settlements by `urban_families` descending
2. Process each in order, applying step-6 shifts to all reachable trade-route-connected smaller markets
3. Then process the next-largest, etc.
4. Cache final demand modifiers in `settlement_merchandise_demand`

This is project-designed implementation detail; RAW gives the rule, project encodes the algorithm. Cite RAW step 6 + provide pseudocode in the GDD.

### 5.B Monthly drift of the 4d4 component (not the underlying demand modifier)

**RAW citation:** [rules/acore-campaign-hijinks.xml:737-739](rules/acore-campaign-hijinks.xml:737) — "10% cumulative monthly chance" of re-roll while in same market.

**What RAW provides:** the re-roll cadence and trigger.

**What's missing:** RAW says "the price re-rolls" but doesn't separate "the 4d4 dice component re-rolls" from "the underlying demand modifier re-rolls." Given §5.A above, the demand modifier is generated once at setting/settlement construction and is essentially static (only changes when trade routes change or domain land revenue changes). So the cleanest reading is:

**Resolution:** Re-roll only the 4d4 dice component on the 10%/month trigger. The demand modifier itself stays anchored to the settlement's environmental/racial/domain/trade-route profile and recomputes only when one of those underlying inputs changes (e.g., a new trade route opens). Document in GDD; cite both RAW sections.

### 5.C Merchandise distribution in the solicit_merchants pool

**RAW citation:** [rules/acore-campaign-hijinks.xml:656-672](rules/acore-campaign-hijinks.xml:656) (Markets and Merchants table) gives merchant counts per market class.

**What RAW provides:** total merchant counts and loads-per-merchant.

**What's missing:** RAW does NOT specify the merchandise distribution across the pool. Which types do the merchants carry / want?

**Resolution:** Weight merchant merchandise selection by `abs(demand_modifier)` for that settlement — merchants gravitate toward goods with strong demand signals. High positive demand → more sellers offering that good (because they expect profit); high negative demand → more buyers seeking that good (because they expect arbitrage opportunity to bring it from elsewhere). Cite the RAW Markets and Merchants table; explicitly mark the distribution algorithm as project-designed.

### 5.D Merchant pool decay / expiration

**RAW citation:** None — RAW says merchants leave after deals close but is silent on unsold merchant lifecycle.

**What's missing:** Whether and how merchants disappear from the pool over time.

**Resolution:** 30-day fixed expiration per merchant row (project-designed; cite RAW silence). Document rationale: simple, predictable, easy to test, no monthly-roll overhead.

### 5.E Background merchant pool replenishment

**RAW citation:** None — RAW assumes active player solicitation drives pool composition.

**What's missing:** Whether settlements have *any* ambient merchant activity without explicit `solicit_merchants` runs.

**Resolution:** Half-minimum ambient pool per market class, refreshed at the monthly tick. Without ambient merchants, a casual visit to a never-soliciatedmarket finds it empty (game-world feel issue). Cite RAW silence; document rationale.

### 5.F Trade-route arbitrage validation examples

**RAW citation:** [rules/acore-setting-construction-rules.xml:280-295](rules/acore-setting-construction-rules.xml:280) — trade_route_shift_example (Cyfaraun/Samos).

**What RAW provides:** ONE worked example (Cyfaraun is the larger market; Samos shifts its demand modifiers 2 points toward Cyfaraun on six merchandise types). This is sufficient to validate the step-6 shift mechanic implementation.

**What's missing:** The Cyfaraun/Samos example validates the *shift mechanic* but does not validate the *end-to-end arbitrage profit* path (i.e., once shifts are applied, does a player who buys wood at one and sells at the other actually profit?). The math chain is: base price × (4d4 + demand_mod + class_adjust) × 0.1 = market price. Five-plus worked end-to-end examples are needed to demonstrate the system produces playable profit margins.

**Resolution (Q-MERC-3, see below):** Jedidiah will provide canonical trade routes from intended setting lore for validation, OR the build agent drafts candidate routes and Jedidiah spotchecks. **Collaborative deliverable.** Either way the GDD §Validation Examples section must show: pair of settlements with full input data (age, biome, race, domain revenue, road/water connectivity, market class), the resulting demand modifiers per merchandise type, the resulting market prices at each end, and the expected per-load gp profit margin for an arbitrage round-trip.

### 5.G NPC merchant migration between settlements

**RAW citation:** None — RAW does not specify inter-settlement merchant migration.

**Resolution:** Defer to v1.1+ per Q7. v1 merchants are stationary; expire per §5.D; replaced via §5.E. Document in build_log.

### 5.H Monopoly economic effects beyond revenue

**RAW citation:** [rules/ax_venturer_class.xml:203-211](rules/ax_venturer_class.xml:203) — venturer with `monopoly_power` (L12+) earns 1gp/urban_family/month.

**What RAW provides:** the revenue mechanic, the one-monopolist-per-settlement rule, and the "rivals must agree or eliminate each other" prose (project handles "agree" via UI in v1.1; "eliminate" via existing combat).

**What's missing:** RAW is silent on whether the monopolist's presence affects OTHER market participants (price floors, ambient merchant count, reaction-roll modifiers).

**Resolution:** v1 monopoly is revenue-only. Cite RAW silence and Q7. Broader market-disruption effects deferred to v1.1+ alongside NPC venturer rivals.

### 5.I Vehicle/cargo Q5 stub semantics

**RAW citation:** Vehicle prices in [rules/acore-campaign-hijinks.xml:844-906](rules/acore-campaign-hijinks.xml:844) and [rules/daw_equipment_and_construction.xml](rules/daw_equipment_and_construction.xml) (caravan/ship gp values).

**What RAW provides:** complete vehicle type roster + costs + capacities (for the full implementation deferred to v1.1).

**What's missing:** RAW does not define the v1-stub abstraction (the project must define what gets shortcut).

**Resolution per Q5:**
- Stub schema: `vehicle_summary(character_id, has_caravan, has_ship, total_cargo_capacity_stone, current_cargo_value_gp)` — aggregate, not per-vehicle.
- Smuggling/stealing hijink yields are paid as **pure gp** (12%/60% of computed market value).
- `buy_sell_merchandise` is a single-market transaction in v1; multi-leg cargo flow deferred.

### 5.J Class-size adjust calibration

**RAW citation:** [rules/acore-campaign-hijinks.xml:719-735](rules/acore-campaign-hijinks.xml:719) — mentions "class size adjust" in the price formula.

**What RAW provides:** the formula component name.

**What's missing:** RAW phrasing is unclear on the exact integer values per market class. The dependency doc's proposed values (+1 class I/II, 0 III/IV, -1 V/VI) are project-designed.

**Resolution:** Use the dependency-doc values; document in GDD with explicit `[PROJECT-DESIGNED]` annotation. Flag for Jedidiah confirmation; if RAW phrasing is unambiguous on closer reading, switch to RAW values.

---

## 6. Clarification questions for Jedidiah

### Resolved 2026-05-11 (locked into the handoff)

**Q-MERC-1 [RESOLVED]. Settlement-economy GDD scope and ownership.** Authorized to author `generation/gdd-settlement-economy.md`. **Critical constraint:** every project-designed element MUST cite the relevant RAW section and explicitly state what RAW provides versus what is missing. See §5.0 above for the mandatory format. No silent project-design.

**Q-MERC-2 [RESOLVED]. Hex-resource awareness.** No special hex resource data (salt deposits, ore veins, etc.) exists. RAW does not require it either — see [rules/acore-setting-construction-rules.xml:221-367](rules/acore-setting-construction-rules.xml:221) for the full demand-modifier generation procedure, which uses settlement age + water source + climate + elevation + race + domain land revenue + trade routes as inputs. The GDD must map existing project data (biome, biome_subtype, hex overlays, settlement demographics) to those RAW inputs, and add missing fields (e.g. settlement age) where the schema is silent.

**Q-MERC-3 [RESOLVED]. Validation examples — collaborative deliverable.** Jedidiah will provide canonical trade routes for validation, OR the build agent drafts candidate routes and Jedidiah spotchecks. Either path is acceptable; coordinate when the GDD §Validation Examples section is being authored. The Cyfaraun/Samos worked example from [rules/acore-setting-construction-rules.xml:280-295](rules/acore-setting-construction-rules.xml:280) is one starting point.

### Still open — raise at session start

**Q-MERC-1A [RESOLVED 2026-05-11].** Jedidiah supplied the canonical Environmental Adjustments to Demand table via screenshot, then explicitly approved a one-instance correction of the corrupted rows in the rules XML. Both the XML and the supporting docs/ artifact are now updated:

- **`rules/acore-setting-construction-rules.xml:297-353`** — now contains the canonical 31-row table with corrected column schema (`tundra` and `plains` as separate columns; `extra_climate_or_wrap` removed). The `<source_integrity_note>` has been replaced with a `<transcription_note>` documenting the resolution. **XML is the canonical source going forward.**
- **`docs/phase-10b-prereq-environmental-adjustments-table.md`** — retained as the audit trail for the resolution and as the verification-flag register for cells that may benefit from PDF re-check (notably rows 30 Semipr. stones and 31 Gems, which read as identical in transcription — likely a transcription error on my part rather than the PDF).

**Action for the mercantile session:** Encode `data/commerce/environmental_adjustments.json` directly from the corrected XML at `rules/acore-setting-construction-rules.xml:297-353`. Cross-check the `?? Verify`-flagged cells in the docs/ artifact against the PDF if doing the encoding pass with the PDF open; if any discrepancy is found, update BOTH the XML and the docs/ artifact simultaneously.

**Note:** Jedidiah explicitly approved this one rules-XML edit as a transcription-fidelity correction (not a rule change). Future sessions remain under the CLAUDE.md sacred-rules policy — do not modify any rules XML without similar explicit approval.

**Q-MERC-2A. Settlement age schema addition.** RAW step 2 requires settlement age. The schema does not currently track it. This session will add an `age_years` and/or `age_bucket` column to `settlements`, with default value "21-100 years" for un-aged settlements. Confirm the default; confirm whether age is set per-settlement, per-domain, or per-region.

**Q-MERC-2B. Settlement race schema audit.** RAW step 5 requires Dwarf/Elf identification. Schema may or may not track dominant race per settlement. Audit first; if missing, add a `dominant_race` column with default "human" (no racial adjustment).

**Q-MERC-2C. Climate mapping table approval.** §5.A.3 requires authoring a (biome, biome_subtype) → RAW climate bucket mapping. Most rows map cleanly because the project subtype vocabulary was authored against the same biogeographical lexicon. The GDD will propose a complete mapping; Jedidiah reviews before encoding.

**Q-MERC-4. Monopoly v1 minimalism.** Confirm §5.H — monopoly is revenue-only in v1; market-disruption effects (price floors, ambient merchant displacement, rival challenges) deferred to v1.1+ alongside NPC venturer rivals (Q7). RAW silence cited.

**Q-MERC-5. Ambient merchant pool.** Confirm §5.E — half-minimum ambient pool from Markets and Merchants table, refreshed monthly. RAW silence cited.

**Q-MERC-6. Demand drift mode.** Confirm §5.B — re-roll only the 4d4 dice on the 10%/month tick; demand modifier stays anchored to environmental/racial/domain/trade-route inputs (recomputes only when those underlying inputs change).

**Q-MERC-7. Vehicle/cargo Q5 stub re-confirmation.** Confirm §5.I — stub semantics as agreed 2026-05-10. Pure-gp hijink payouts; single-market arbitrage in v1.

**Q-MERC-8. Wave-split.** Suggest multi-wave subdivision per §7 below. Confirm.

**Q-MERC-9. Migration numbering coordination.** Phase 10B.1 is finishing UI polish and will likely consume migration 092. The mercantile session reserves 093+ for its own migrations. Confirm via build_log when 10B.1 lands.

**Q-MERC-10. Spell-cost lookup audit.** Is the Spell Availability by Market table already wired into `SpellRegistry`? Phase 10A.2's `cast_charitable_spells` handler needs it; audit first, build if needed.

**Q-MERC-11. Class-size adjust calibration.** Confirm §5.J — the dependency-doc values (+1 class I/II, 0 III/IV, -1 V/VI) as the v1 project-designed defaults. If a closer reading of [rules/acore-campaign-hijinks.xml:719-735](rules/acore-campaign-hijinks.xml:719) reveals an unambiguous RAW value, use that instead.

---

## 7. Suggested wave-split

Each wave is 3-5 hours of focused build time. Adjust per Q-MERC-8 approval.

| Wave | Scope | New artifacts | Tests target |
|---|---|---|---|
| **Prereq.GDD** | Draft `generation/gdd-settlement-economy.md`. Encode the RAW six-step procedure with citations (§5.A.1-A.9). Address §5.B-J as addenda. Resolve Q-MERC-1A (corrupted rows). Author climate mapping (Q-MERC-2C). Get Jedidiah sign-off section-by-section. **No code yet.** | 1 GDD | n/a (design only) |
| **Prereq.1** | Merchandise registry (§1 of dependency doc) — JSON data, registry singleton, baseline tests. Includes recovery of corrupted late-luxury rows per Q-MERC-1A resolution. | `data/commerce/common_merchandise.json`, `data/commerce/precious_merchandise.json`, `engine/subsystems/commerce/merchandise_registry.gd`, `tests/test_merchandise_registry.gd` | 6-8 |
| **Prereq.2a** | Schema: add `age_years` / `age_bucket` + `dominant_race` columns to `settlements`. Add `settlement_merchandise_demand` table. Encode the RAW six-step demand procedure: base 1d3-1d3 roll → environmental → fractions → domain revenue → racial → trade-route shift. Tests verify each step against the Cyfaraun/Samos worked example (RAW L280-295). | migration 093+ (coord with 10B.1), `engine/subsystems/commerce/demand_modifier_generator.gd` (six-step procedure), `engine/subsystems/commerce/settlement_economy_inputs.gd` (input lookups: age/water/climate/elevation/race/domain-revenue), tests | 12-15 |
| **Prereq.2b** | Trade route detection + processing order. Region-walk algorithm (largest-first). Range-of-trade lookups. | `engine/subsystems/commerce/trade_route_detector.gd`, `engine/subsystems/commerce/region_demand_resolver.gd` (orchestrates the region walk), tests | 8-10 |
| **Prereq.2c** | Market price resolver (§2 of dependency doc) — 4d4 + demand + class adjust formula. Monthly drift on the dice component (§5.B). | `engine/subsystems/commerce/market_price_resolver.gd`, tests | 6-8 |
| **Prereq.3** | Market fees calculator (§4 of dependency doc) — pure-function helpers, no schema. | `engine/subsystems/commerce/market_fees_calculator.gd`, `tests/test_market_fees_calculator.gd` | 6-8 |
| **Prereq.4** | Per-settlement merchant pool (§3) — schema, MerchantSolicitor Ongoing-tick handler, MerchantPoolRepository, ambient-refresh resolver (§5.E), merchandise distribution weighted by `abs(demand_modifier)` (§5.C). | migration N+1, `engine/subsystems/commerce/merchant_pool_repository.gd`, `engine/subsystems/commerce/merchant_solicitor.gd`, `engine/subsystems/commerce/merchant_pool_monthly_resolver.gd`, tests | 12-15 |
| **Prereq.5** | Vehicle/cargo Q5 stub (§5.I) — `vehicle_summary` schema, repository, basic tests. | migration N+2, `engine/subsystems/commerce/vehicle_summary_repository.gd`, tests | 4-6 |
| **Prereq.6** | Profession (attorney) + prior_crimes columns (§6) — schema, proficiency catalog row if missing. | migration N+3, possible proficiency catalog update, tests | 4-6 |
| **Prereq.7** | Spell-cost lookup audit (§8) + Henchman Loyalty API audit (§7) — verify or extend. | audit notes; small code additions if gaps | 2-4 |
| **Prereq.8** | Integration tests + build_log update + coding_conventions update. End-to-end validation: pick the canonical Cyfaraun/Samos pair from RAW + 2-4 Jedidiah-provided routes (Q-MERC-3) and verify the full pipeline produces expected per-load arbitrage gp. | `tests/test_commerce_integration.gd` | 6-10 |

**Total: 65-90 tests across 10 waves.** The wave count grew from 8 to 10 because Prereq.2 split into 2a/2b/2c — encoding the six-step procedure + trade-route detection + price resolver are three distinct chunks of work that should land separately. Roughly three-quarters the size of Phase 10A combined.

---

## 8. Patterns to follow (from Phase 10A — DO mirror)

### 8.1 Static data registry pattern
- Mirror `SpellRegistry` for `MerchandiseRegistry`. Load JSON at autoload init; expose pure-function queries.
- JSON data lives in `data/commerce/` (mirror `data/activities/` from Phase 10A.2).

### 8.2 Monthly-tick resolver pattern
- `MerchantPoolMonthlyResolver` mirrors `FaithMonthlyResolver` from Phase 10A.2. Pre-resolve modifiers (price drift) + post-resolve effects (ambient merchant refresh, expired merchant cleanup).
- Wire into `engine/subsystems/session/handlers/domain_handlers.gd` `_resolve_domain_month` next to existing resolvers.

### 8.3 Ledger entries (audit trail)
- Use `category = "revenue"` for arbitrage profit, `"expense"` for customs/toll/moorage payments. **Never** `category="commerce"` or `"trade"` — the CHECK constraint allows only `'revenue', 'expense', 'tribute_in', 'tribute_out', 'investment', 'other'`. Use `subcategory` for granularity (e.g. `subcategory="customs_duty"`).
- For monopoly revenue: `category="revenue"`, `subcategory="monopoly_revenue"`.

### 8.4 Activity-handler registration
- `solicit_merchants` is the only Ongoing activity this session ships. Handler in `engine/subsystems/activities/handlers/mercantile/solicit_merchants.gd` (new directory). Registration class registers it with `ActivityHandlerRegistry`. Wired into `session_runner.gd` next to existing `FaithActivityHandlersRegistration.register_all` etc.
- All the *other* mercantile activities (buy_sell, persuade, commission, etc.) are Phase 10B.2 work; this session only handles `solicit_merchants`.

### 8.5 EventBus signals
- Add `merchant_pool_refreshed(settlement_id, new_merchant_count)`, `market_price_drifted(settlement_id, merchandise_type, old_gp, new_gp)`, `monopoly_revenue_collected(character_id, settlement_id, gp_amount)`, etc. Past-tense verbs per project convention.

### 8.6 Test fixtures
- One test file per subsystem (mirror `tests/test_faith_block.gd` granularity).
- Cross-subsystem integration test at the end of the session (`test_commerce_integration.gd`) covering an end-to-end "buy in cheap market, settle the price drift, verify customs duty was deducted, monopoly revenue ledgered" scenario.
- Settlement fixtures: create test settlements with explicit archetypes to validate the demand-modifier seeding produces expected gradients.

### 8.7 Coding conventions
- Append `docs/coding_conventions.md` §52 (or next available) with commerce-subsystem conventions: registry-pattern usage, MarketPriceResolver as the SSoT for all price calculations (no ad-hoc 4d4 rolls elsewhere), banker's rounding requirements, settlement-economy-profile read-side semantics.

---

## 9. Anti-patterns from Phase 10A (DO NOT repeat)

- **Ad-hoc class-id checks.** This session probably won't touch ClassBucketResolver, but Profession (attorney) gating should go through ProficiencyRegistry, not ad-hoc proficiency-name string matching.
- **Ledger category invention.** Use only the six allowed categories. Use `subcategory` for granularity.
- **Skipping banker's rounding.** Market price math is now cp-native per the 2026-05-15 currency-precision rule: `cp_per_load = base_price_gp × percentage` (where `percentage = (4d4 + demand_mod + class_adjust + monopolist + judge) × 10`) yields exact integer cp — no rounding fires. Banker's rounding only applies elsewhere when a computation produces a fractional cp (e.g., `labor_fee_cp` on odd stone, `customs_duty_cp` on odd-cp prices). Use `MarketFeesCalculator._bankers_round` for those.
- **Trans-test data pollution.** Demand-modifier cache and merchant-pool rows persist across tests; purge between cases.
- **Reading the GDD instead of the JSON.** Phase 10A.3 hit this — class data in `data/classes/*.json` is the truth. For this session, settlement data in DB rows is the truth — don't infer from setting lore.
- **Inventing new schema columns without a migration.** Every new column needs migration N+x and a schema.sql update.

---

## 10. Things NOT to touch in this session

- **The Faith block / Bardic Patronage / Garrison Training** (Phase 10A — complete).
- **The Magical Research block** (Phase 10B.1 — UI polish in flight). If 10B.1 hasn't merged when this session starts, coordinate migration numbers via build_log.
- **The Magical Research throw util** (`engine/subsystems/activities/handlers/faith/magic_research_throw_util.gd`). Commerce does not use the magic-research throw.
- **The monster catalog / domain_encounter_resolver** (monster-data parallel session).
- **The Trade block UI** (10B.2's job).
- **The Syndicate block UI / hijink resolvers / Crime & Punishment resolver** (10B.3's job). This session only ships their data prerequisites.
- **The henchman-loyalty resolver** (audit only — verify the existing API supports the modifier_dict parameter for 10B.3's needs).

---

## 11. Session opening checklist

1. Read `CLAUDE.md`, `build_log.md` tail, `docs/acks_arbiter_design_brief_v11.md` relevant sections.
2. Read this file (`docs/phase-10b-prereq-mercantile-handoff.md`) in full.
3. Read `docs/phase-10b-subsystem-dependencies.md` in full.
4. Read `docs/phase-10-plan.md` Q5/Q6/Q7/Q8 + §Phase 10B.2 + §Phase 10B.3.
5. Read the canonical demand-modifier RAW: [rules/acore-setting-construction-rules.xml:221-367](rules/acore-setting-construction-rules.xml:221) — the full six-step procedure, all tables, the source-integrity flag on the late-luxury rows. Note Q-MERC-1A.
6. Spot-check `db/schema.sql` for: (a) current migration number (coordinate with Phase 10B.1's pending migration via build_log); (b) presence/absence of `age_years` / `dominant_race` columns on `settlements` (drives Q-MERC-2A/B).
7. **Raise Q-MERC-1A through Q-MERC-11 with Jedidiah.** Wait for answers. Q-MERC-1, 2, and 3 are already resolved (see §6 above) — do NOT re-ask those. **Q-MERC-1A (corrupted-source-row recovery) is the highest-priority new question** because it potentially blocks GDD authoring on Jedidiah's PDF homework.
8. Begin drafting `generation/gdd-settlement-economy.md`. Follow §5.0's mandatory format: every project-designed element gets a RAW citation + explanation of what's missing. Get Jedidiah's review section-by-section, not at the end. **First draft scope:** §5.A (demand modifier procedure encoding + sub-gaps A.1-A.9) is the design core; §5.B-J are addenda.
9. Once the GDD is approved (or approved-in-sections), load the next-wave RAW (`acore-campaign-hijinks.xml` for merchandise tables) and plan Prereq.1 (merchandise registry) in detail. Get plan sign-off.
10. Implement Prereq.1. Run `--headless --path . --import` after adding new `.gd` files, then run `tests/test_runner.tscn`.
11. Iterate through Prereq.2-8.
12. Update `build_log.md` and `docs/coding_conventions.md` at each wave boundary.

---

## 12. File inventory

### Already exists (do not duplicate)
- `db/schema.sql` settlements row (has `urban_families`, `market_class` columns)
- `db/migrations/083_market_class_modifiers.sql` (Phase 9A — temporary class shifts; may need extending for monopoly effects per Gap H, but recommend NOT extending in v1)
- `engine/subsystems/spells/spell_registry.gd` (template for `MerchandiseRegistry`)
- `engine/subsystems/domains/faith_monthly_resolver.gd` (template for `MerchantPoolMonthlyResolver`)
- `engine/autoloads/campaign_repository.gd` (faith helpers section is the canonical pattern for adding commerce helpers)
- `engine/subsystems/proficiencies/` (existing proficiency registry — verify Profession (attorney) is in catalog; add if missing)
- `engine/subsystems/henchmen/henchman_loyalty_resolver.gd` (audit only)

### Already exists from this handoff session
- `docs/phase-10b-prereq-environmental-adjustments-table.md` (Q-MERC-1A resolution; canonical transcription of the Environmental Adjustments to Demand table from the source PDF; supersedes the corrupted rows in `rules/acore-setting-construction-rules.xml:297-356`)

### To be created
- `generation/gdd-settlement-economy.md` (new GDD — the design foundation; RAW-cited per §5.0 mandatory format)
- `data/commerce/common_merchandise.json` (21 entries per Q-MERC-1A canonical list)
- `data/commerce/precious_merchandise.json` (10 entries per Q-MERC-1A canonical list)
- `data/commerce/environmental_adjustments.json` (the 20-column × 31-row table; encoded from `docs/phase-10b-prereq-environmental-adjustments-table.md`)
- `db/migrations/0XX_settlements_age_and_race.sql` (Q-MERC-2A/B)
- `db/migrations/0XY_merchandise_and_demand.sql` (settlement_merchandise_demand table)
- `db/migrations/0XZ_merchant_pool.sql`
- `db/migrations/0XW_vehicle_summary_stub.sql`
- `db/migrations/0XV_attorney_proficiency_and_prior_crimes.sql`
- `engine/subsystems/commerce/` (new directory):
  - `merchandise_registry.gd` (autoload — add to project.godot)
  - `settlement_economy_inputs.gd` (input lookups: age/water/climate/elevation/race/domain-revenue → RAW step inputs)
  - `demand_modifier_generator.gd` (the six-step procedure)
  - `trade_route_detector.gd` (RAW step 6 algorithm — connecting-path + range-of-trade)
  - `region_demand_resolver.gd` (region-walk orchestrator — largest-market-first per RAW L365)
  - `market_price_resolver.gd` (4d4 + demand + class adjust + monthly drift)
  - `market_fees_calculator.gd`
  - `merchant_pool_repository.gd`
  - `merchant_solicitor.gd` (Ongoing activity handler)
  - `merchant_pool_monthly_resolver.gd`
  - `vehicle_summary_repository.gd`
- `engine/subsystems/activities/handlers/mercantile/` (new directory):
  - `solicit_merchants.gd`
  - `mercantile_handlers_registration.gd`
- `tests/test_merchandise_registry.gd`
- `tests/test_settlement_economy_inputs.gd`
- `tests/test_demand_modifier_generator.gd` (validates each of the 6 steps + Cyfaraun/Samos worked example)
- `tests/test_trade_route_detector.gd`
- `tests/test_region_demand_resolver.gd`
- `tests/test_market_price_resolver.gd`
- `tests/test_market_fees_calculator.gd`
- `tests/test_merchant_solicitor_ongoing.gd`
- `tests/test_merchant_pool_repository.gd`
- `tests/test_merchant_pool_monthly_resolver.gd`
- `tests/test_vehicle_summary_repository.gd`
- `tests/test_commerce_integration.gd`

### To be modified
- `project.godot` — register `MerchandiseRegistry` autoload
- `engine/autoloads/campaign_repository.gd` — add commerce helpers section
- `engine/autoloads/event_bus.gd` — add commerce signals (~6 new)
- `engine/subsystems/session/handlers/domain_handlers.gd` — wire `MerchantPoolMonthlyResolver` into `_resolve_domain_month`
- `engine/subsystems/session/session_runner.gd` — add `MercantileActivityHandlersRegistration.register_all` call
- `tests/test_runner.gd` (or scene) — register new test suites
- `db/schema.sql` — append new migrations
- `docs/coding_conventions.md` — append §52
- `build_log.md` — append per-wave entries

---

## 13. The big-picture reminder

Phase 10A taught us: **RAW vs. GDD vs. JSON triangle is the leading source of bugs.** For this session the triangle is:

1. **RAW** (sacred) — TWO key files:
   - `rules/acore-setting-construction-rules.xml` §generating_demand_modifiers (L221-367) is the source of truth for **how demand modifiers are generated** (six-step procedure with full lookup tables). I missed this on the first draft of this handoff; the user corrected it. **DO NOT re-make this mistake** — when faced with a "RAW silent" hypothesis, grep the rules directory exhaustively first.
   - `rules/acore-campaign-hijinks.xml` is the source of truth for **how prices are computed at the market** (4d4 + demand_mod + class_adjust formula), the Markets and Merchants table, smuggling/stealing yield percentages, monthly drift trigger.
2. **GDD** (this session writes a NEW one) — `generation/gdd-settlement-economy.md`. Per Q-MERC-1 [RESOLVED]: every project-designed element must cite the relevant RAW section and explicitly state what RAW provides versus what is missing. No silent project-design.
3. **JSON data** (this session writes new ones) — `data/commerce/common_merchandise.json` etc. must match the RAW tables exactly. The corrupted late-luxury rows (Q-MERC-1A) are the known transcription risk.

If the three disagree, **stop and ask Jedidiah**. The Phase 10A pattern was: when GDD and JSON disagreed, JSON won (because it was already loaded and tested) but only after surfacing the discrepancy.

The **biggest risks** in this session:

- **Misreading RAW silence.** As demonstrated by the v1 of this handoff: I claimed Gap A was RAW-silent when in fact `acore-setting-construction-rules.xml:221-367` contains a complete six-step procedure with all required tables. **Always grep the full rules directory before declaring a gap.** Use patterns like "demand_modifier", "market", "merchandise" across all rules/*.xml.
- **Writing code before the GDD is locked.** The demand-modifier generator implements a six-step RAW procedure with project-design fill-ins at clearly-marked points. Without the GDD documenting which inputs map where (biome → climate, hex overlay → water source, etc.), the implementation drifts.
- **Skipping RAW citation in the GDD.** The mandatory format from §5.0 exists for a reason: every project-design element traceable back to a RAW citation + explicit gap description. Future contributors must be able to audit which decisions were author-discretion vs. RAW-encoded.

**Hard sequence:** Grep RAW exhaustively → identify gaps with citations → draft GDD section by section with Jedidiah review → encode JSON tables (with Q-MERC-1A row recovery) → implement code → integration test. Cyfaraun/Samos worked example from RAW is the first validation target.

Good luck. This is the hardest of the three Phase 10 prereq sessions but it unblocks half the remaining domain-tab content. And per the user's correction on Gap A: RAW gives you more than you might assume on first read. **Read the rules; the answers are often there.**
