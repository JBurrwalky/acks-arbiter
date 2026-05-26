# GDD: Urban Growth Stocking

**Document type:** Game Design Document (Architecture / Umbrella)
**Authority:** PROJECT-DESIGNED — all per-class POI budgets, emergence weights, stocking algorithms, contribution shapes, and data schemas in §4–§11 are engineering decisions. The RAW anchors in §2 (urban-family thresholds, investment-driven family attraction, market-class table, congregant contributions from temples, clanhold settlement caps) are fixed and may not be changed.
**Status:** Draft v1.14 — §13 Implementation Roadmap rewritten as a **build-ready handoff** per Jedidiah 2026-06-02. Each of the 8 stages (A–H) now lists concrete file paths under `engine/`, migration SQL components, EventBus signal signatures with parameter types, dependency ordering, and specific test cases with expected results. Closes Q-UGS-57 (7-day spell offer retention confirmed). All v1.0–v1.13 design decisions remain locked. The GDD is now ready to hand to a build agent — every remaining open Q-UGS item is either an implementation-time calibration knob, a v2 deferral, or a cross-GDD coordination flag, none of which block v1 build.
**Depends on ACKS rules:**
- [`rules/acore_axioms_strongholds_and_domains.xml:633-706`](../rules/acore_axioms_strongholds_and_domains.xml) — urban settlement founding, maximum population by total investment, growing-the-settlement, urban-revenue table (market class by family count), urban-expenses, urban-morale, dissolution, benchmarks.
- [`rules/acore-campaign-hijinks.xml:631-672`](../rules/acore-campaign-hijinks.xml) — market classes I–VI keyed to settlement family count; market-and-merchants table.
- [`rules/acore-campaign-general-and-magic-research.xml:554-578`](../rules/acore-campaign-general-and-magic-research.xml) — congregant sources (charitable deeds, missionaries, **temple construction**); monthly proselytizing procedure that sums "gp value of religious structures erected in the realm".
- [`rules/acore_campaign_classes.xml:978-994,1136-1146,1299-1318`](../rules/acore_campaign_classes.xml) — Cleric/Bladedancer class power "temple" at L9 (build a temple as a stronghold; followers arrive).
- [`rules/acore-setting-construction-rules.xml:486-559`](../rules/acore-setting-construction-rules.xml) — **Starting Cities table** (leveled NPC counts of Fighters / Clerics / Mages / Thieves per market class) and **starting-city criminal guilds** procedure (the splitting-pattern template extended to non-criminal classes by §5 of this GDD).
- [`rules/acore-setting-construction-rules.xml:404-434`](../rules/acore-setting-construction-rules.xml) — region-construction constants (~45 static POIs per regional map; 15 settlements / 30 dungeons-and-lairs split) and the maximum-NPC-population-by-realm-type table.
- [`rules/acore-monster-stocking-rules.xml:471`](../rules/acore-monster-stocking-rules.xml) — base settlement NPC level = `7 - market_class`. **NOTE in v1.3:** this rule governs the *base level of randomly-encountered NPC adventuring parties* in a settlement, NOT the level distribution of stocked resident NPCs. v1.2 incorrectly applied this rule as a cap on resident NPC levels in §5.2; v1.3 removes that misuse. The rule is cited here only to document the v1.2 → v1.3 correction.
- [`rules/ax_campaign_play.xml:411-421`](../rules/ax_campaign_play.xml) — **`consecrate_altar` activity** (RAW): divine spellcaster L5+, 1 day per 500gp, aura 100sq.ft per 100gp, pinnacle-of-good (Lawful) / sinkhole-of-evil (Chaotic). This is the RAW mechanism by which a shrine is promoted to a temple per §4.1 of this GDD.
(v1.4: library and magic-research workshop RAW dependencies removed — those subsystems are owned by `gdd-stronghold-construction.md` for player-built strongholds and a future `gdd-magical-research` GDD for itinerant-caster access, NOT by this GDD.)
- [`rules/ax_domains_of_chaos.xml:27-35,46`](../rules/ax_domains_of_chaos.xml) — clanhold settlement limits (max class VI, urban investment cannot grow size or class, 12.5% urban-of-peasant cap).
- [`rules/ax_campaign_play.xml:3-23`](../rules/ax_campaign_play.xml) — monthly cycle: domain-growth → investment subphase → congregant-growth → revenue-collection.
**Depends on project GDDs:**
- [`gdd-settlement-economy.md`](gdd-settlement-economy.md) — provides settlement economic state (`urban_families`, `market_class`, demand modifiers) that this GDD reads and mutates.
- [`gdd-settlement-layout.md`](gdd-settlement-layout.md) — provides the spatial PoI skeleton (districts + slots) at world-gen; this GDD adds the temporal layer (emergence of new POIs as the settlement grows). Explicitly fills the seam flagged at `gdd-settlement-layout.md:365` ("Settlement growth: still numeric-only. … the generator does not regenerate the layout").
- [`gdd-settlement-stocking.md`](gdd-settlement-stocking.md) — owns the on-contact occupant generation; this GDD reuses its occupant-generation pipelines when emergent POIs are first visited.
- [`gdd-stronghold-construction.md`](gdd-stronghold-construction.md) — player-built strongholds (Cleric L9 temple, Mage sanctum, etc.) are registered into the POI table this GDD defines, so they participate in the contribution registry.
- [`gdd-religion-conversion.md`](gdd-religion-conversion.md) — the first consumer of this GDD's contribution registry; §9.8 of that document names the contract this GDD implements.
- [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) — the orthogonal style×alignment model that determines whether clanhold exceptions apply.
- [`gdd-specialists.md`](gdd-specialists.md) — emergent `mercenary_guild_hall` and `workshop` POIs unlock the broader specialist taxonomy (alchemist, healer, sage, mercenary officers, quartermasters, etc.) that GDD's §6 lists as future expansion.
- [`gdd-poi-generation.md`](gdd-poi-generation.md) — explicitly **NOT** this GDD's scope. That GDD covers static wilderness POIs (shrines, ruins, barrows) on the 6-mile hex map. This GDD covers settlement-interior POIs that emerge over time.
**Modifiable by Claude Code:** Yes — the per-class budgets in §5, the emergence weights in §6.3, the stocking-NPC level tables in §7.3, and the contribution-shape definitions in §8.3 are all engineering decisions. The schema in §11 is normative once approved.
**Last updated:** 2026-06-02

---

## 1. Purpose and Scope

Urban settlements in ACKS Arbiter currently have a market class at world-gen time and never advance past it. The Phase 10B trade block consumes market class but does not mutate it; `DomainGrowthResolver` grows population (peasant and urban families) but never re-evaluates the settlement's class. The settlement-layout GDD produces a fixed PoI skeleton at generation time and explicitly does not regenerate; the settlement-stocking GDD populates that skeleton on contact and explicitly does not add new PoIs as the settlement grows. The gap between "the settlement grew from 200 to 300 urban families" and "the settlement now has a Class V profile with one temple and one tavern that didn't exist before" is uncovered.

This GDD defines:

1. **The growth → market-class advancement loop.** The missing piece of the monthly investment subphase: when urban-family thresholds are crossed (per RAW), the settlement's `market_class` advances and a *growth event* fires.
2. **The POI emergence pipeline.** When a growth event fires, new interior POIs (religious sites of shrine or temple tier, mercenary guild halls, mages' guild halls, named taverns, specialist workshops) appear in the settlement according to per-class budgets reverse-engineered from the Starting Cities NPC demographics in `acore-setting-construction-rules.xml:496-519`.
3. **NPC stocking of emergent POIs.** A baseline-automatic stocking pass assigns generic placeholder NPCs (1st-level cleric of the dominant religion for a new temple, etc.); a player-driven enhancement pass (the "Stock POI" decree) lets the ruler bind a specific henchman or named NPC to a POI for amplified mechanical effect.
4. **The POI contribution registry.** A generic interface by which any consumer system (religion conversion, magical research, mercantile, future faction work) can query "what POIs of type X with attribute Y exist in domain Z, and what is their total contribution?". This makes the GDD an umbrella: it owns the cross-cutting POI infrastructure, but individual consumer systems own their own consumption logic.

**In scope:**

- Settlement-interior POIs that emerge as urban settlements grow (religious sites at shrine or temple tier, mercenary guild halls, mages' guild halls, named taverns, specialist workshops — see §4).
- The market-class advancement logic (currently missing from the codebase).
- Stocking of emergent POIs with placeholder NPCs.
- A "Stock POI" decree (player-driven NPC assignment).
- The contribution-registry contract that consumer systems (religion conversion, magical research, etc.) call.
- Clanhold settlement exceptions per RAW.
- Forward-compatibility hooks for the eventual faction system (Phase 12+).

**Out of scope (v1 — deferred):**

- The full faction system. Each emergent POI has an `owner_faction_id` column reserved (nullable, defaults to NULL = "the realm"); the faction-ownership semantics are deferred to Phase 12+.
- Generation of richly-named NPCs from a cultural-lore system that doesn't yet exist. v1 stocking produces placeholder NPCs (deterministically named per the existing `gdd-name-generation.md` cultural name banks) but does not yet wire in personality, knowledge, or backstory beyond what `gdd-settlement-stocking.md` already supplies on contact.
- Dungeon stocking. The `acore-monster-stocking-rules.xml` and `gdd-trap-generation.md` already cover this for explorable dungeons; emergent settlement POIs are buildings, not dungeons.
- Combat / encounter generation inside settlements. Handled by `gdd-settlement-stocking.md` §11 encounter tables.
- Settlement-downgrade dissolution edge cases (urban_families drops, market class falls). The RAW dissolution rule at `acore_axioms_strongholds_and_domains.xml:686-689` is honored, but a granular "POI X becomes derelict when class falls" mechanic is flagged Q-UGS-4 and deferred to v2.
- Player demolition of existing POIs. Flagged Q-UGS-10.
- POI-to-POI faction politics (a temple of Religion A vs. a temple of Religion B in the same settlement). Phase 12 faction work.

**What this GDD is NOT:**

It is not a re-design of the settlement-layout GDD. The layout GDD remains authoritative for how a settlement is *spatially* organized at world-gen. This GDD adds a *temporal* layer on top: how the inventory of POIs changes over campaign time. It is also not a re-design of stronghold construction — when a Cleric reaches L9 and builds a temple-as-stronghold per `acore_campaign_classes.xml:978-994`, that temple is registered into this GDD's POI table but flows through `gdd-stronghold-construction.md` for its construction cost, time, and follower attraction.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Settlement founding requires 10000gp + 75–249 transferred peasant families** (`rules/acore_axioms_strongholds_and_domains.xml:634-640`).
- **Maximum urban population by total investment** (the "settlement size cap" table at `rules/acore_axioms_strongholds_and_domains.xml:641-648`): 10000gp → 249 families; 25000gp → 624; 75000gp → 2499; 200000gp → 4999; 625000gp → 19999; 2500000gp → 100000.
- **Urban investment attracts 1d10 new urban families per 1000gp spent each month** (`rules/acore_axioms_strongholds_and_domains.xml:653`).
- **Monthly urban investment may not exceed the domain's revenue** (`rules/acore_axioms_strongholds_and_domains.xml:654`).
- **Market class is determined by urban-family count** (`rules/acore_axioms_strongholds_and_domains.xml:656-664`, cross-cited with `rules/acore-campaign-hijinks.xml:631-638`):
  - Class VI: 75–249 families.
  - Class V: 250–624 families.
  - Class IV: 625–2499 families.
  - Class III: 2500–4999 families.
  - Class II: 5000–19999 families.
  - Class I: 20000+ families.
- **Class VI hamlets (≤74 families) exist** with 0gp monthly income and effectively no market function (`rules/acore_axioms_strongholds_and_domains.xml:691`). Hamlets are not "founded" settlements in the urban-settlement sense — they are domain peasant clusters. v1 does not emerge POIs in hamlets.
- **A settlement dissolves if it ever falls below 75 urban families** (`rules/acore_axioms_strongholds_and_domains.xml:686-689`); remaining urban families return to nearby hexes as peasant families.
- **Religious structures count toward proselytizing** (`rules/acore-campaign-general-and-magic-research.xml:562`): "Add the gp value of religious structures erected in the realm" is step 3 of the monthly proselytizing procedure. Additional congregants may be recruited through "charitable deeds, missionaries, and temple construction" (`rules/acore-campaign-general-and-magic-research.xml:556`).
- **Cleric L9 unlocks "construct a temple as a stronghold"** (`rules/acore_campaign_classes.xml:1299-1318`) with class-driven follower attraction (5d6×10 0th-level faithful + 1d6 1st–3rd level same-class characters for Bladedancers; equivalent for other divine classes per their class entries). Construction cost is half normal "if the bladedancer has not lost the favor of her deity" for divine classes.
- **`consecrate_altar` activity** (`rules/ax_campaign_play.xml:411-421`): major activity, ongoing, 1 day per 500gp spent on the altar; requires a divine spellcaster of level 5 or higher. Aura: 100 sq.ft. per 100gp. A Lawful altar creates a pinnacle of good; a Chaotic altar creates a sinkhole of evil. Aura persists until dispelled or the altar is physically broken and blessed. Divine power may be substituted for gp if a humbler-looking altar is desired. **This GDD treats consecrate_altar as the RAW mechanism by which a shrine becomes a temple** (§4.1).
- **Starting Cities NPC demographics** (`rules/acore-setting-construction-rules.xml:496-519`) — verbatim totals of leveled NPCs per class per market class:

  | Pop | Type | Min ruler lvl (in realm) | Class | Fighters | Thieves | Clerics | Mages |
  |---|---|---|---|---|---|---|---|
  | 74- | Hamlet | 2 (6) | — | 6- | 3- | 3- | 2- |
  | 75–99 | Small village | 2 (7) | VI | 12 | 6 | 6 | 3 |
  | 100–249 | Village | 3 (8) | VI | 16 | 8 | 8 | 4 |
  | 250–449 | Large village | 4 (8) | V | 40 | 20 | 20 | 10 |
  | 450–624 | Small town | 5 (9) | V | 72 | 36 | 36 | 18 |
  | 625–1240 | Large town | 6 (9) | IV | 100 | 50 | 50 | 25 |
  | 1250–2499 | Small city | 7 (10) | IV | 200 | 100 | 100 | 50 |
  | 2500–4999 | City | 8 (10) | III | 400 | 200 | 200 | 100 |
  | 5000–19999 | Large city | 9 (12) | II | 800 | 400 | 400 | 200 |
  | 20000+ | Metropolis | 10 (14) | I | 3200+ | 1600+ | 1600+ | 800+ |

  These are the **total leveled NPC counts** (Fighters / Clerics / Mages / Thieves) that this GDD's §5 reverse-engineers per-class POI budgets from.

- **Base NPC level for random encounters in a settlement = 7 - market_class** (`rules/acore-monster-stocking-rules.xml:471`). **This rule does NOT apply to resident-NPC stocking** in this GDD. It is a rule for generating the levels of NPC adventuring parties the PCs randomly encounter in a settlement. Resident NPC levels (the ones who staff temples, sanctums, guild halls, etc.) are determined by the criminal-guild distribution analogue per §5.2 applied to the Starting Cities counts, with no market-class-derived level cap. The minimum_ruler_level column of the Starting Cities table establishes the floor for the highest-level resident NPC (the ruler); other residents distribute per §5.2.

- **Criminal-guild membership level distribution** (`rules/acore-setting-construction-rules.xml:531-534`): 45% are 0-level ruffians, 35% are 1st level, 12.5% are 2nd level, 7.5% are 3rd level or higher. **This GDD extends the same distribution shape to Fighters / Clerics / Mages by analogy** (§5.2), recognizing that RAW provides this curve only for criminal classes and treating it as a project-designed proxy.

- **Splitting-pattern template — criminal guilds may divide into multiple** (`rules/acore-setting-construction-rules.xml:540-541`): "Optionally divide criminals into multiple competing or complementary guilds instead of one unified guild. … base boss level and revenues on the membership of each separate guild rather than settlement market class." **This GDD adopts the same pattern for non-criminal classes** (§5.3): a settlement's L5+ Fighter / Cleric / Mage population may be distributed across 1-to-N POIs of the matching type, with the high roll producing many small POIs and the low roll producing one massive POI.

- **Region POI density target** (`rules/acore-setting-construction-rules.xml:411-413`): 45 static POIs per 30×40 regional map, broken into ~15 settlements + ~30 dungeons/lairs. This GDD does not change region POI counts; it only adds **interior** POIs to existing settlements as they grow.

(v1.4: library / workshop RAW constraints removed — magical-research infrastructure is no longer part of this GDD's scope.)

- **Spellcaster specialist hiring rules** (`rules/acore_equipment.xml:967-976`):
  - "Arcane or divine casters may be hired to cast spells for adventurers." Monthly pay varies.
  - "Availability is determined by market class and spell level" (the table cited below).
  - "Each available spellcaster can cast a spell of the listed level **once per day**." This is the per-day-limit invariant the §8.5.5 daily-refresh model encodes.
  - "Availability does not guarantee cooperation; the caster must still be successfully hired through negotiation." v1.9 abstracts negotiation to a binary "pay or not" — successful payment = successful hire. A future reputation/faction system (Q-UGS-46 noted as out-of-scope) may add negotiation friction.
  - **Cleric restriction (RAW):** "Clerics never cast spells for adventurers of opposite alignment." This is the alignment gate implemented in §8.5.3 — with the v1.9 refinement per Jedidiah 2026-05-28 that Neutral characters can transact with Lawful or Chaotic casters, and Neutral casters serve anyone.
  - **Cleric surcharge (RAW, deferred):** "Clerics may charge double if adventurers do not belong to their faith." v1 IGNORES this surcharge per Jedidiah — surcharge is a later implementation pass after the full loop works (Q-UGS-53).

- **Spell Availability by Market table** (`rules/acore_equipment.xml:979-991`):

  | Spell Type | Cost | Class I | Class II | Class III | Class IV | Class V | Class VI |
  |---|---|---|---|---|---|---|---|
  | Divine 1st level | 10gp | 2d3×100 | 4d4×10 | 5d10 | 4d6 | 2d6 | 1d6 |
  | Divine 2nd level | 40gp | 8d10 | 4d6 | 2d6 | 2d3 | 1d3 | 1d2 |
  | Divine 3rd level | 150gp | 2d6 | 2d3 | 2d3 | 1d2 | 1d2−1 | — |
  | Divine 4th level | 325gp | 2d6 | 2d3 | 2d3 | 1d2 | 1d2−1 | — |
  | Divine 5th level | 500gp | 1d6 | 1d4 | 1d4 | 1d2−1 | — | — |
  | Arcane 1st level | 5gp | 2d4×100 | 2d10×10 | 2d4×10 | 3d10 | 2d6 | 1d4 |
  | Arcane 2nd level | 20gp | 2d6×10 | 6d6 | 2d6 | 2d4 | 1d4 | 1d2 |
  | Arcane 3rd level | 75gp | 4d6 | 2d6 | 2d3 | 1d4 | 1d2 | — |
  | Arcane 4th level | 325gp | 2d4 | 2d3 | 1d4 | 1d2 | 1d2−1 | — |
  | Arcane 5th level | 1,250gp | 1d4 | 1d4 | 1d2 | — | — | — |
  | Arcane 6th level | 4,500gp | 1d3 | 1d3 | 1d2−1 | — | — | — |

  The dice rolls produce the number of castings of that spell type available in the settlement per day. The cost is per casting. **1d2−1** means "roll d2 and subtract 1" (yields 0 or 1, so a 50% chance of one available). A dash (—) means unavailable in that market class. v1 implementation: at the first POI visit each calendar day, roll the dice for the settlement's market class across all rows and persist the result in `settlement_poi_spell_offers` per §11.1. The rolls are settlement-wide (one roll per settlement per day per spell type), but the offers are split between the settlement's religious_sites (divine spells) and mages_guild_halls (arcane spells) per §8.5.2.
- **Clanhold settlement caps** (`rules/ax_domains_of_chaos.xml:27-35`):
  - Urban population must remain below 250 urban families.
  - Maximum market class is VI.
  - **Urban investment cannot increase settlement size or market class.**
  - Urban families cannot exceed 12.5% of the clanhold's peasant population.
- **Beastman clanhold urban revenue is halved** (`rules/acore-campaign-general-and-magic-research.xml:646`); halving applies to urban revenue, not POI count, but emergent-POI density should reflect the reduced economic scale (Q-UGS-7).
- **Settlement growth happens in the monthly investment subphase** (`rules/ax_campaign_play.xml:9-12`), which is part of the start-of-month domain-growth phase that fires before the congregant-growth phase. POI emergence triggered by class advancement therefore takes effect *before* religion-conversion proselytizing for that month — a temple that emerges in a January growth event contributes to the January proselytizing sum.

---

## 3. Subordinate / Sibling GDDs and Where the Seams Sit

This GDD is an umbrella; it intersects multiple sibling GDDs. The seams are documented here so future readers and Phase 12+ extensions know which GDD owns what.

### 3.1 Sibling GDDs and ownership boundaries

| GDD | Owns | Seam with this GDD |
|---|---|---|
| `gdd-settlement-layout.md` | Spatial PoI skeleton at world-gen (districts, named slots). | Emergence at growth events adds new entries to the `settlement_pois` table this GDD defines. The layout GDD does NOT regenerate when class advances; this GDD's emergent POIs are non-spatial in v1 (they have a district affinity but no rendered location). |
| `gdd-settlement-stocking.md` | On-contact occupant generation, on-contact building generation, encounter framing, district crime levels. | Emergent POIs from this GDD reuse the stocking GDD's occupant pipelines when the party first visits. The baseline NPC stocking in §7 happens at emergence time; the rich on-contact stocking (specific named occupants beyond the baseline staffer, encounter tables, treasure) happens on first visit per the stocking GDD's existing rules. |
| `gdd-settlement-economy.md` | Demand modifiers, prices, merchant pool, trade routes, urban-family count, market class as state. | This GDD reads `settlement_entrances.urban_families` and writes `settlement_entrances.market_class`. It does NOT change the economic state fields the economy GDD owns. The market-class-advancement step §6.1 emits a `market_class_advanced` signal which the economy GDD's downstream consumers (merchant-pool refresh, demand-modifier seed, etc.) listen for. |
| `gdd-stronghold-construction.md` | Player-built strongholds (fortress, sanctum, hideout, fastness, vault, temple-as-stronghold, clanhold). | A stronghold sited in a settlement hex is registered into the `settlement_pois` table with `(builder_kind='character', builder_character_id=<id>)`. Its `gp_value` flows through the contribution registry. Construction time, cost, archetype rules, follower-attraction-on-completion remain owned by the stronghold GDD. |
| `gdd-religion-conversion.md` | Monthly proselytizing math, congregant accounting, conversion state machine, Change Religion decree. | The first consumer of §8's contribution registry. The verbatim contract in `gdd-religion-conversion.md` §9.8 is satisfied by §11's `settlement_pois.attached_religion` + `settlement_pois.stocked_character_id` columns (renamed from v1.2's `stocked_cleric_character_id` per Q-UGS-3 resolution) and §8.3.1's `religious_structures_gp_value_for_domain(domain_id, religion) -> int` helper. |
| `gdd-specialists.md` | Specialist hire mechanic (pathfinder, surveyor in v1; alchemist/healer/sage/mercenary officers/etc. as future). | Emergent `mercenary_guild_hall` (military specialists) and `workshop` (non-military specialists) POIs provide the settlement-availability gating that `gdd-specialists.md` §6 flags as future work. A specialist of a given kind can be hired from a settlement iff a matching POI exists. |
| `gdd-magical-research` | (To be authored as part of Phase 10B.1 wrap.) Magical research costs, library/workshop bonuses, spell research and magic item creation procedures. | **No direct dependency in v1.4.** This GDD does NOT model libraries or magic-research workshops as POI-level infrastructure. Itinerant casters access library/workshop bonuses through their own player-built strongholds (per `gdd-stronghold-construction.md`) or via a separate visiting-researcher mechanism the magical-research GDD will define. The mages_guild_hall POI exists for resident-Mage housing and Mages' Guild presence, but its gp_value is NOT readable as a library or workshop value by magical research. |
| `gdd-poi-generation.md` | **Wilderness** POIs (sacred sites, ancient ruins, burial sites, etc.) on the 6-mile hex map. | Disjoint scope. Settlement-interior POIs (this GDD) and wilderness POIs (that GDD) share no data tables and have separate runtime systems. The naming collision on "POI" is unavoidable; the project uses `settlement_pois` for this GDD's table and `pois` for the existing wilderness table. |

### 3.2 Subordinate work this GDD assumes will land

The following implementation work is not part of this GDD itself but is required for the system to operate. Each is currently absent from the codebase.

1. **A market-class advancement step** in the monthly tick. Currently `DomainGrowthResolver` grows `urban_families` but never re-evaluates `market_class`. The settlement-growth resolver this GDD calls for either lives inside `DomainGrowthResolver` (as a new subphase) or is its own `SettlementGrowthResolver`. §6.1 specifies the math; the placement decision is flagged Q-UGS-15.
2. **A POI emergence handler** that fires on `market_class_advanced` signals. §6 specifies its algorithm.
3. **A "Stock POI" decree** (analogous to the existing Change Religion decree from `gdd-religion-conversion.md` §6.1). §7.2 specifies its UX and validation.
4. **A POI contribution registry** in a centralized location (likely `engine/subsystems/settlements/poi_contribution_registry.gd`). §8 specifies the contract.
5. **Migration adding `settlement_pois` table.** §11 specifies the schema.

---

## 4. POI Taxonomy

This GDD defines a closed v1 vocabulary of five settlement-interior POI types (reduced from seven in v1.0 after the §4.1 refactor: `library` folded into `sanctum`; `shrine` and `temple` collapsed into a single `religious_site` type with a `tier` enum). The vocabulary is project-designed — RAW does not enumerate POIs at this granularity — but each is grounded in a RAW concept.

### 4.1 Vocabulary

| Type ID | Display Name | Role | RAW grounding |
|---|---|---|---|
| `religious_site` | Religious Site (tier: shrine \| temple) | A site of public worship. Three roles in v1.5: (a) two tiers — **shrine** = religious_site with no consecrated altar, **temple** = religious_site with at least one consecrated altar (per `rules/ax_campaign_play.xml:411-421` `consecrate_altar` activity). A shrine is promoted to a temple via the existing Faith block `consecrate_altar` activity (divine spellcaster L5+). (b) Temples contribute their `gp_value` *plus* attached altar gp_invested to proselytizing per §8.3.1; shrines contribute `gp_value` only. (c) **Sells divine spellcasting services to the public** per §8.5 / §9.x — the resident divine caster casts spells from their repertoire for visiting characters at prices set by the Spell Availability by Market table (`ax_campaign_play.xml:405`, table not yet in rules corpus per Q-UGS-26). Shrines sell low-level services (cure light wounds, bless, purify food and water, etc., per the resident L1–L2 cleric's repertoire); temples sell higher-level services per the L3+ head priest's repertoire. **v1.4:** library/workshop allocations removed; this GDD does not model magical-research infrastructure. | `acore-campaign-general-and-magic-research.xml:556,562` (temple construction + religious structures erected in the realm); `ax_campaign_play.xml:411-421` (consecrate_altar RAW); `ax_campaign_play.xml:405` (Spell Availability by Market reference); `acore_campaign_classes.xml:1299-1318` (Cleric L9 temple-as-stronghold). |
| `mercenary_guild_hall` | Mercenary Guild Hall | The institutional home of a leveled-Fighter cohort that is not itself a stronghold-owning ruler. Provides mercenary recruitment (per `daw_armies_recruitment.xml:892-953` market-class availability), mercenary-officer hiring, and military specialist access. | `acore-setting-construction-rules.xml:496-519` Starting Cities table Fighter counts; `daw_armies_recruitment.xml:892-953` military-specialist-availability-by-market-class table. |
| `mages_guild_hall` | Mages' Guild Hall (Mages' Guild) | The institutional home of a leveled-Mage cohort. Serves two roles in v1.5: (a) Mages' Guild equivalent of a guild hall for resident mages; (b) **sells arcane spellcasting services to the public** per §8.5 / §9.x — the resident mage cohort casts arcane spells from their repertoire for visiting characters at prices set by the Spell Availability by Market table (`ax_campaign_play.xml:405`, table not yet in rules corpus per Q-UGS-26). Smaller sanctums (K_local=1, L3 mage) sell only 1st–2nd level arcane services (charm person, detect magic, sleep, etc.); larger sanctums sell up to the head mage's maximum spell level. **v1.4:** library and magic-research workshop attachments removed — sanctums do not provide magical-research bonuses to visiting characters; that's the magical-research GDD's problem to model differently. | `acore-campaign-general-and-magic-research.xml:556` (temple construction is the cleric analogue; sanctums fill the mage analogue); `acore_campaign_classes.xml:696-713` (Mage L9 sanctum stronghold); `acore-campaign-hijinks.xml:534+` (Sanctums and Dungeons rules — mages who build sanctums attract apprentices); `ax_campaign_play.xml:405` (Spell Availability by Market table reference, not yet in corpus). |
| `named_tavern` | Named Tavern (Settlement Landmark) | A named public house large enough to be a settlement landmark. Hosts rumor exchange, hireling recruitment, NPC encounters. Generic taverns and inns remain on-contact stocked per `gdd-settlement-stocking.md`; a named tavern is one elevated to settlement-POI status. | `gdd-settlement-stocking.md` §3 lists named taverns as always-created major POIs. |
| `workshop` | Specialist Workshop | The lair of a single non-military, non-Mariner, non-Ruffian specialist (alchemist's lab, healer's clinic, sage's study, animal trainer's pens). v1.8 narrows the kinds: Alchemist, Healer (General / Physicker / Chirurgeon), Animal Trainer (Common / Exotic), Sage with topical specialization. Mariners are in `port` POIs (see below); Ruffians are hireable from `named_tavern` POIs and the criminal-guild substrate; Armorer / Engineer / mercenary military specialists are hireable via management-notebook panels (per `gdd-management-notebook.md`) or mercenary_guild_hall POIs respectively, with no separate workshop. | `acore_equipment.xml §specialists.specialist_details` per `gdd-specialists.md` §6 future expansion. The RAW Hiring Availability by Market Class table provides per-class availability for each specialist kind. |
| `port` | Port | A waterfront POI hosting Mariner specialists (Captain, Navigator, Sailor / Rower per the RAW Hiring Availability table). Provides ship moorage per `acore-campaign-hijinks.xml:686-695`. **Geographic gate (v1.12, same-hex-only):** a port only emerges when the settlement's hex carries a water-access tag in `gdd-terrain-system.md` — specifically `river` or `coastal` (a land hex bordering ocean / sea / lake). **Adjacency does NOT qualify** — a settlement on a land hex next to a river hex still has no port (hexes are large abstract swathes; if the settlement isn't on the river hex itself it doesn't have river access for trade-scale moorage). Landlocked settlements do not emerge ports regardless of market class. **All recorded rivers are navigable** — unnavigable small streams are not represented on the regional map data per `gdd-terrain-system.md`, so any `river`-tagged hex implies trade-capable water access. The §6.3 emergence pipeline checks the same-hex predicate before rolling a port; if the predicate fails, the port slot is skipped (it does NOT roll on the workshop table as a substitute — a riverless mining town has no port and no mariner availability, full stop). | `acore-campaign-hijinks.xml:686-695` (moorage and stabling costs); `acore_equipment.xml §specialists.specialist_details` Mariner entries; `gdd-terrain-system.md` (water-tag predicates for the hex gate). |

### 4.2 Notes on the vocabulary

- **Shrine vs. temple.** Both are the `religious_site` type. The `tier` is derived state: a religious_site is a `temple` iff a `consecrated_altars` row exists with `location_kind = 'settlement_poi'` and `location_ref = <this religious_site's id>` and `status = 'completed'`. Otherwise it is a `shrine`. The `religious_sites` POI table caches the current tier as a denormalized column (§11.1) for query speed; the cache is recomputed when a `consecrate_altar` activity completes (insertion) or the altar's status changes (e.g., dispel, physical destruction).
- **Promotion = `consecrate_altar`.** RAW: `ax_campaign_play.xml:411-421` requires a divine spellcaster L5+ to consecrate an altar. The activity takes 1 day per 500gp spent on the altar (so a 5000gp altar takes 10 days). When the activity completes inside a shrine POI, the shrine is promoted to a temple. The temple's `gp_value` for proselytizing is now `religious_site.gp_value + altar.gp_invested` (sum across all attached altars).
- **What a shrine mechanically DOES.** A shrine *is* a religious POI but with three mechanical effects, all lighter than a temple's:
  1. Contributes its `gp_value` (small — see §6.4) to proselytizing for its attached_religion. RAW step "Add the gp value of religious structures erected in the realm" per `acore-campaign-general-and-magic-research.xml:562` does not distinguish between shrines and temples; both count.
  2. Provides a worship venue for the attached_religion's congregants in the settlement. The presence of any religious_site of religion X in a settlement is the precondition for the religion-conversion congregant-placement step per `gdd-religion-conversion.md` §6.4. Without a shrine or temple, NPC congregants of that religion exist but have nowhere to publicly assemble (no domain-morale effect; v1 narrative texture only).
  3. Slot-counts toward the §5 per-class religious-POI target. A Class IV city with target = 3 religious_sites is satisfied by any mix of shrines and temples totalling 3, not specifically by temples.
- **Why shrines are NOT deleted.** They (a) provide the upgrade target for the `consecrate_altar` activity (without shrines pre-existing, a divine caster who wants to build a temple in a settlement must FIRST commission a religious_site stub, which adds friction and delay), (b) populate settlements where no L5+ divine caster exists to consecrate altars (the RAW `ax_campaign_play.xml:411-421` `consecrate_altar` requirement), and (c) preserve narrative texture (small towns have chapels even if no L5+ cleric has yet visited).
- **`mages_guild_hall` vs. `sanctum` — naming disambiguation (v1.6).** v1.0–v1.5 named this POI type `arcane_sanctum`, which collided with the Mage L9 stronghold archetype `sanctum` (per `acore_campaign_classes.xml:696-713`). v1.6 renamed the POI type to `mages_guild_hall` to eliminate the collision and parallel `mercenary_guild_hall`. The disambiguation is sharp:
  - **`sanctum`** = the Mage L9 stronghold archetype, owned by `gdd-stronghold-construction.md`. A player-built construction with class-driven follower attraction (1d6 apprentices L1–L3 + 2d6 0-level seekers). Lives in the `strongholds` table.
  - **`mages_guild_hall`** = the institutional POI emerged by this GDD's growth pipeline. Owned by `settlement_pois` table. Hosts the leveled-Mage cohort of a settlement, sells arcane spellcasting services, anchors the Mages' Guild presence in the settlement.
  - When a player Mage builds a sanctum sited in a settlement hex, §12.4 registers a `mages_guild_hall` row with `(builder_kind='character', builder_character_id=<id>)` so the stronghold appears in the Settlement Exploration UI as the local Mages' Guild presence. The stronghold and the POI are paired entities, not the same row — the stronghold has follower attraction and other class-power mechanics that the POI doesn't model.
- **Libraries and magic-research workshops are NOT modeled by this GDD (v1.4).** v1.2 and v1.3 attempted to allocate library_value and workshop_value as derived subsets of POI gp_value. Per Jedidiah 2026-05-22: "Lets just nuke the POI-with-library/workshop at this point. Not worth the hassle of sorting out a rental system." Characters who want a magical-research library or magic-item workshop bonus access it via their own player-built stronghold (per `gdd-stronghold-construction.md` — the player explicitly allocates gp for library construction during stronghold design) or via a future visiting-researcher mechanism the `gdd-magical-research` GDD will design. The settlement-POI system this GDD owns has no library or magic-research workshop infrastructure.
- **Mercenary guild hall houses military specialists.** Per `daw_armies_recruitment.xml:892-953`, mercenary officers (lieutenants, captains, colonels, generals), quartermasters, and siege engineers have specific market-class availability tables. The emergent mercenary_guild_hall is the institutional anchor that makes those specialists hireable in the settlement.
- **Specialist distribution across POI types (v1.8 design lock).** The RAW Hiring Availability by Market Class table (`acore_equipment.xml §specialists.specialist_details`) enumerates ~17 specialist sub-kinds. Not all need their own POI surface — some belong in other POI types, some in management-notebook panels. v1.8 design:

  | Specialist kind (RAW) | v1 POI / UI surface |
  |---|---|
  | Alchemist | `workshop` (chemical lab) |
  | Healer — General | `workshop` (clinic) |
  | Healer — Physicker | `workshop` (clinic) |
  | Healer — Chirurgeon | `workshop` (surgery) |
  | Animal Trainer — Common | `workshop` (pens / training yard) |
  | Animal Trainer — Exotic | `workshop` (specialist pens) |
  | Sage | `workshop` (study; with topical specialization per `acore_proficiencies.xml` topic list — Loremastery, Theology, Naturalism, etc.) |
  | Mariner — Captain | `port` (new POI in v1.8) |
  | Mariner — Navigator | `port` |
  | Mariner — Sailor / Rower | `port` |
  | Ruffian — Carouser | `named_tavern` (extended §7.3 stocking provides this hire pool) |
  | Ruffian — Footpad | `named_tavern` + criminal-guild substrate (`acore-campaign-hijinks.xml:1-51`) |
  | Ruffian — Reciter | `named_tavern` |
  | Ruffian — Spy | criminal-guild substrate primarily; `named_tavern` secondary |
  | Ruffian — Thug | `named_tavern` + criminal-guild substrate |
  | Armorer | **Management-notebook hiring panel** (no POI surface in v1; `gdd-management-notebook.md` lists market-class availability per RAW; Q-UGS-50 coordinates with that GDD) |
  | Engineer | **Management-notebook hiring panel** (same model) |
  | Mercenary Officers / Quartermaster / Siege Engineer | `mercenary_guild_hall` (per §11.3 lookup; unchanged from v1.4) |

- **Why split across POI types and notebook.** The user observation in v1.8 review (Jedidiah, 2026-05-27): "It is also unclear whether all of those are intended to be resident vs itinerant. Also, obviously some of them don't need their own workshops/POIs." Some specialists (alchemists, sages, healers) have visible permanent installations a player can visit and inspect — they get POI surfaces. Others (armorers, engineers) are essentially hire-list entries with no permanent installation worth visiting; they belong in a notebook hiring panel where the player can scan availability across market classes without a per-POI UI. Mariners need waterfront access, so they get their own `port` POI type. Ruffians fit naturally into tavern and syndicate flavor without a separate POI.

- **Resident vs itinerant.** RAW does not gate any specialist as strictly resident — most are presumed resident-but-replaceable (a Class III city has ~4 healers; if hired, replaced next monthly tick). v1 treats all hireable specialists as resident, available for hire each month based on the RAW availability table. A future v2 may add "itinerant specialist visits" (a famous Sage passes through for a season, available only during a window); flagged Q-UGS-51.

- **Port emergence — same-hex predicate (v1.12).** A settlement emerges a port only if its own hex carries a `river` or `coastal` tag per `gdd-terrain-system.md`'s water-tag system. **Adjacency does NOT qualify** per Jedidiah 2026-05-31: "Must be in the same hex as the river, hexes are large swathes of abstract land, if the settlement is not on the same hex, it doesn't have a river port." All recorded rivers are navigable — the terrain system does not represent small unnavigable streams in the map data, so any river-tagged hex is trade-capable. The §6.3 emergence pipeline checks the predicate at port-slot computation; if the predicate fails, no port emerges and Mariner specialists are unavailable in the settlement regardless of market class. RAW Mariner availability table presumes coastal access; this GDD makes that presumption explicit via the same-hex predicate.
- **Named tavern remains.** Generic taverns are on-contact stocked per the existing settlement-stocking GDD; this GDD only adds named-tavern emergence at higher market classes for settlement-landmark status. Mechanical effect: contributes to a future rumor/hireling-pool consumer (`tavern_count_for_settlement` per §8.4).

### 4.3 What this GDD does NOT enumerate as POIs

The following are owned by other GDDs and **are not** members of the settlement-POI vocabulary. **Critically, "not in this GDD's vocabulary" does NOT mean "invisible in the Settlement UI."** All of the below DO still surface in the Settlement Exploration UI per `gdd-settlement-exploration-ui.md` as visitable locations; they just live in other tables and are not subject to this GDD's emergence pipeline or contribution registry. The Settlement UI assembles a unified visitable-locations list by querying both `settlement_pois` (this GDD) and the other tables below.

- **Strongholds** (fortress, sanctum-as-stronghold, hideout, fastness, vault, fortified-church-as-stronghold, clanhold). Registered into `settlement_pois` for queryability (`(builder_kind='character', builder_character_id=<id>)` per §11) but their lifecycle is owned by `gdd-stronghold-construction.md`. Visitable through both UIs.
- **Generic buildings** (cots, townhouses, villas, shophouses, manufactories, depots, bawdyhouses, cantinas, generic inns, bathhouses, public latrines, stables) per `gdd-settlement-stocking.md` §3. These are on-contact stocked into settlement_data JSON; not tracked in `settlement_pois`. Visitable as on-contact-generated content.
- **Criminal-syndicate hideouts** per `gdd-settlement-stocking.md` §6 and migration 118. Syndicates own their own tables. Visitable when discovered.
- **Marketplace stalls / shops** per `gdd-settlement-stocking.md` §5. Per-shop instances live in shop_inventory (migration 029). Visitable as on-contact content.
- **Government / authority buildings** (the ruler's keep or palace, the law courts, the militia barracks, the tax collector's office). v1 treats these as flavor extensions of the ruler's stronghold (when the ruler resides in the settlement) or as on-contact stocked content (when the ruler is absent). Not in `settlement_pois` v1; deferred Q-UGS-27 to a future "civic POIs" extension.
- **Wilderness POIs** (`pois` table per migration 050). These are 6-mile-hex external POIs, not interior to any settlement. Distinct system per `gdd-poi-generation.md`.

---

## 5. Per-Market-Class POI Budgets — Reverse-Engineered from RAW Demographics

The per-class POI count for a settlement is not asserted from intuition; it is **derived** from the Starting Cities NPC demographics in `acore-setting-construction-rules.xml:496-519` by the following four-step procedure:

1. **Look up total leveled NPCs** of each class for the settlement's market class.
2. **Estimate the L3+ subset** of those NPCs using a project-designed level-distribution curve calibrated against the criminal-guild distribution in `acore-setting-construction-rules.xml:531-534` (the only RAW level-distribution curve provided). v1.3 lowered the anchor threshold from L5+ to L3+ per Q-UGS-8 resolution.
3. **Subtract the one or zero stronghold-owning NPC** of each class (one if NPC-ruled domain — i.e., the NPC ruler holds the stronghold; zero if PC- or henchman-ruled domain).
4. **Distribute the L3+ NPCs across N POIs** of the matching type, where N is rolled on a project-designed split table (per the criminal-guild splitting pattern at `acore-setting-construction-rules.xml:540-541`) to produce varied settlement layouts (one massive POI, many small POIs, or a mix).

The procedure produces a *range* of POI counts, not a fixed number — which is the design goal (settlement variety). The §5.1–§5.5 substeps specify the procedure in implementable detail.

### 5.1 Step 1 — Total leveled NPCs (RAW)

| Market Class | Settlement size band | Fighters | Clerics | Mages |
|---|---|---|---|---|
| Class VI | 75–99 (small village) | 12 | 6 | 3 |
| Class VI | 100–249 (village) | 16 | 8 | 4 |
| Class V | 250–449 (large village) | 40 | 20 | 10 |
| Class V | 450–624 (small town) | 72 | 36 | 18 |
| Class IV | 625–1249 (large town) | 100 | 50 | 25 |
| Class IV | 1250–2499 (small city) | 200 | 100 | 50 |
| Class III | 2500–4999 (city) | 400 | 200 | 100 |
| Class II | 5000–19999 (large city) | 800 | 400 | 200 |
| Class I | 20000+ (metropolis) | 3200+ | 1600+ | 800+ |

Source: `rules/acore-setting-construction-rules.xml:496-519`. Thieves and 0-level civilians are handled by other systems (criminal guilds per the same RAW section; civilians per `gdd-settlement-stocking.md`).

### 5.2 Step 2 — POI anchor threshold (L3+) and level distribution

RAW provides a level-distribution curve only for criminal-guild members (`acore-setting-construction-rules.xml:531-534`):

> 45% are 0-level ruffians; 35% are 1st level; 12.5% are 2nd level; 7.5% are 3rd level or higher.

This GDD adopts the same shape as a project-designed proxy for Fighters / Clerics / Mages, with the caveat that the Starting Cities totals (per `acore-setting-construction-rules.xml:496-519`) list LEVELED NPCs only (excluding 0-level townsfolk). Removing the 45% L0 floor and renormalizing yields a distribution within the *leveled* population:

| Level | Share of leveled population |
|---|---|
| 1st | 63.6% (= 35 / 55) |
| 2nd | 22.7% (= 12.5 / 55) |
| 3rd+ | 13.6% (= 7.5 / 55) |

Within the L3+ tail, this GDD applies recursive halving (project-designed; flagged Q-UGS-21 for review):

| Level | Share of leveled population |
|---|---|
| 3rd | 6.82% |
| 4th | 3.41% |
| 5th | 1.70% |
| 6th | 0.85% |
| 7th | 0.43% |
| 8th | 0.21% |
| 9th+ | 0.21% (remaining tail) |

**L3+ NPCs anchor POIs.** A POI of a given type emerges to host one or more L3+ NPCs of the matching class:
- L3+ Clerics anchor religious_sites (the head priest of each temple or shrine).
- L3+ Mages anchor mages_guild_halls (the head mage of each Mages' Guild branch).
- L3+ Fighters anchor mercenary_guild_halls (the head captain of each mercenary company).

**Why L3+ (not L5+ as in v1.0–v1.2).** Published ACKS modules consistently show small sanctums and small temples in Class IV cities. The v1.2 L5+ threshold yielded zero L5+ mages at Class IV large town (0.85, rounds down to 0), preventing sanctum emergence at that scale. L3+ moves the threshold to "any meaningfully-trained mage" — a 3rd-level mage can cast 2nd-level spells and is plausibly the senior figure of a small Mages' Guild branch. Higher-level mages (L5+) still exist and become the heads of larger or more prestigious sanctums via §5.4's splitting roll, but they are not gating for sanctum existence.

**L3+ fraction = 13.6%** of leveled-NPC population.

**L1–L2 NPCs distribute as adherents — on-demand materialization (v1.10 per Q-UGS-42).** Once L3+ NPCs are split into POIs via §5.4, the remaining L1–L2 NPCs (86.4% of the leveled population) distribute proportionally to the POI gp_values as adherents. Each POI's K_local in §5.4 is its L3+ anchor count; the §7.3 stocker generates the head NPC at the highest L3+ level assigned and K_local − 1 L3 adherents as full character rows (`npc_role = 'baseline_placeholder'` per §11.4). The L1–L2 cohort is **NOT** persisted as character records at emergence time — instead, the POI carries a count attribute `l1_l2_adherent_count` (an integer estimate of how many L1–L2 adherents nominally live there), and individual L1–L2 NPCs are materialized **on demand** when the player interacts with them. The materialization path:

1. Player explicitly interacts with a low-level NPC at a POI — e.g., requests to talk to "one of the temple's junior priests," recruits a 1st-level cleric as a henchman, or asks the head priest "who else lives here?"
2. The `gdd-settlement-stocking.md` on-contact occupant generator is invoked with the POI's context (type, attached_religion, head NPC's level/alignment/culture).
3. A new `characters` row is created with `npc_role = 'on_demand'`, `home_poi_id = <this POI's id>`, a rolled level (L1–L2 per the §5.2 distribution), name from the cultural bank, and standard stats.
4. The POI's `l1_l2_adherent_count` is decremented by 1 (representing that this adherent is now "named" instead of "background").
5. If the player retains the interaction state — hires the NPC as henchman, ongoing party-aware relationship, etc. — the NPC's `npc_role` upgrades to `'henchman'` or `'named_npc'` and they persist.
6. If the interaction ends without retention (player chats briefly, no hire, no quest), the `'on_demand'` row remains for the current play session but is eligible for cleanup at a later session-boundary tick if no relationship state references it.

This avoids the v1.0–v1.9 save-weight problem (Class III city with 200 leveled clerics would have created ~165 L1–L2 character rows per emergent religious_site cohort, even though the player would never interact with most of them) while preserving the user's ability to dig as deep as they want into any POI.

Cleanup of stale `'on_demand'` rows is flagged Q-UGS-58 (new) — recommend per-session-boundary, scanning for `npc_role = 'on_demand'` rows with no party-interaction state.

**Banker's rounding** applies when computing the integer L3+ count.

The L3+ counts derived from §5.1 × 13.6% (with banker's rounding):

| Market Class | Settlement size band | L3+ Fighters | L3+ Clerics | L3+ Mages |
|---|---|---|---|---|
| Class VI | 75–99 | 2 | 1 | 0 |
| Class VI | 100–249 | 2 | 1 | 1 |
| Class V | 250–449 | 5 | 3 | 1 |
| Class V | 450–624 | 10 | 5 | 2 |
| Class IV | 625–1249 | 14 | 7 | 3 |
| Class IV | 1250–2499 | 27 | 14 | 7 |
| Class III | 2500–4999 | 54 | 27 | 14 |
| Class II | 5000–19999 | 109 | 54 | 27 |
| Class I | 20000+ | 435+ | 218+ | 109+ |

**Class VI single-cleric edge case.** A Class VI small village has 1 L3+ cleric, who becomes the head NPC of either (a) the village's single shrine (per §5.5 baseline) if the cleric has not consecrated an altar, or (b) the single temple (promoted from the shrine) if a consecrated altar is attached. The shrine/temple is one and the same POI; tier flips per §11.4 trigger.

**No market-class cap on individual NPC levels.** v1.2's "Class VI base-level cap" paragraph (which mis-applied the `7 - market_class` rule from `acore-monster-stocking-rules.xml:471`) is removed in v1.3. The recursive-halving distribution alone determines how many high-level NPCs exist at each market class — and the math correctly shows that even a Class VI small village's 1 L3+ cleric may be a L5+ or L7+ figure (the village priest of a long-standing parish), just rarely. The Starting Cities table's `minimum_ruler_level` column provides the floor for the highest-level NPC in the settlement; the rest distribute statistically per the criminal-guild proxy.

#### 5.2.1 Cross-class demographic ratio is 4:2:2:1 (RAW)

The Starting Cities table at `acore-setting-construction-rules.xml:496-519` establishes a fixed ratio between class populations that holds across all market classes:

> **Fighters : Thieves : Clerics : Mages = 4 : 2 : 2 : 1**

Verification across every row of the table:

| Pop band | F | T | C | M | F:T:C:M |
|---|---|---|---|---|---|
| 75–99 | 12 | 6 | 6 | 3 | 4:2:2:1 ✓ |
| 100–249 | 16 | 8 | 8 | 4 | 4:2:2:1 ✓ |
| 250–449 | 40 | 20 | 20 | 10 | 4:2:2:1 ✓ |
| 450–624 | 72 | 36 | 36 | 18 | 4:2:2:1 ✓ |
| 625–1240 | 100 | 50 | 50 | 25 | 4:2:2:1 ✓ |
| 1250–2499 | 200 | 100 | 100 | 50 | 4:2:2:1 ✓ |
| 2500–4999 | 400 | 200 | 200 | 100 | 4:2:2:1 ✓ |
| 5000–19999 | 800 | 400 | 400 | 200 | 4:2:2:1 ✓ |
| 20000+ | 3200+ | 1600+ | 1600+ | 800+ | 4:2:2:1 ✓ |

**Implication for §5.2's L3+ count math.** The L3+ subset percentage (13.6% of leveled NPCs per the criminal-guild distribution analogue) is the same across all classes; therefore the L3+ counts inherit the same 4:2:2:1 ratio. A Class IV large town has 14 L3+ Fighters, 7 L3+ Clerics, 3 L3+ Mages — exactly the 4:2:1 ratio (Thieves are tracked by the criminal guild substrate, not this GDD).

**Why this matters.** v1.6 onward implicitly already produces 4:2:2:1 through proportional math; v1.7 elevates the observation to a documented invariant so future calibration adjustments can verify they preserve the ratio. If a future Q-UGS proposes a per-class adjustment (e.g., "Mage-ruled domains have +50% mages"), that adjustment is a deviation from the RAW baseline and should be explicit.

**Cross-class predictions per class type** (v1.7's framing of the criminal-syndicate workflow):
- **Mages** are the rarest leveled cohort by a factor of 2 vs. clerics/thieves and 4 vs. fighters. A settlement at Class V small town (450–624 pop) has only 18 leveled mages total, ~2 of whom are L3+. Mages' Guild halls are correspondingly rare at low market classes.
- **Clerics** are twice as common as mages. Class V small town has 36 leveled clerics, ~5 L3+. Religious sites (shrines and temples) emerge readily even at small towns.
- **Fighters** are the most common leveled cohort, 4x mages. Class V small town has 72 leveled fighters, ~10 L3+. Mercenary guild halls emerge prolifically.
- **Thieves** (not modeled as POIs by this GDD; modeled by the existing criminal-guild substrate) follow the same count as clerics — the substrate's hideout/syndicate count per `acore-campaign-hijinks.xml:1-51` consumes the thieves cohort.

#### 5.2.2 Within-band level elevation (project-designed)

The Starting Cities table uses **discrete sub-bands** — most market classes have two sub-bands defined (e.g., Class IV has band 625–1240 with 100 leveled fighters and band 1250–2499 with 200 leveled fighters). The transition between sub-bands roughly doubles the leveled-NPC count and (implicitly) doubles the L3+ count.

The transitions are sharp: a settlement at 1240 families has 100 leveled fighters; at 1241 families, suddenly 200. The user observation in v1.7 review (Jedidiah, 2026-05-26): "Maybe with some %chance of a higher levelled NPCs that correlates to how close the settlement population is to the next-highest market class (and that % could follow the same recursive halving/thirding/quartering or whatever it ends up being)?"

v1.7 implements this as a **per-L3+-NPC level-elevation roll** during §6.1 stocking, keyed to the settlement's progress within its current sub-band:

```
band_progress = (urban_families - band_min) / (band_max - band_min)
                clamped to [0.0, 1.0]
                
                where band_min and band_max are the population band the settlement
                currently falls in per the Starting Cities table at
                acore-setting-construction-rules.xml:496-519.
                Example: settlement at 932 pop is in band 625–1240, so
                  band_progress = (932 - 625) / (1240 - 625) = 0.499 ≈ 0.50.
                Settlements in the top sub-band of a market class (with no
                further sub-band above before the next class threshold) use
                the next CLASS's lower threshold as band_max.
```

For each L3+ NPC after the §5.2 base-level assignment, apply a recursive-halving elevation roll:

```
elevation_pool = list of (level_delta, chance):
  +1 level:  band_progress × 50%
  +2 level:  band_progress × 25%   (only checked if +1 succeeded)
  +3 level:  band_progress × 12.5% (only checked if +2 succeeded)
  +4 level:  band_progress × 6.25%
  +N level:  band_progress × (50% × 0.5^(N-1))

procedure:
  total_boost = 0
  for tier in [1, 2, 3, 4, ...]:
    chance = band_progress × 0.5^tier × 100%
    roll d100
    if d100 ≤ chance:
      total_boost += 1
    else:
      break  # first failed roll stops the chain
  NPC.level += total_boost
```

#### 5.2.2.1 Worked examples for the elevation roll

**Settlement at the start of its sub-band (band_progress ≈ 0.0):**
- L3+ NPC stays at base level. No boost.
- Class IV large town just-entered (625 pop): all L3+ NPCs use the recursive-halving curve directly. Highest-level NPC is typically L5–L7 across the cohort.

**Settlement at the middle of its sub-band (band_progress = 0.50):**
- +1 level chance: 25%
- +2 level chance: 12.5%
- +3 level chance: 6.25%
- Expected level boost ≈ 0.25 + 0.0625 + 0.0078 + ... ≈ 0.32 levels average per L3+ NPC.
- Class IV large town at 932 pop: each of the 3 L3+ Mages has a small chance of being a level or two higher than the base distribution.

**Settlement at the top of its sub-band (band_progress = 1.0):**
- +1 level chance: 50%
- +2 level chance: 25%
- +3 level chance: 12.5%
- Expected level boost ≈ 0.5 + 0.125 + 0.0156 + ... ≈ 0.65 levels average per L3+ NPC.
- Class IV large town at 1240 pop: each of the 3 L3+ Mages has a 50% chance of +1 level (so a base-L4 mage becomes an L5 mage at p=0.50, conferring 3rd-level-spell access on the head of the local Mages' Guild branch). This is the "ripe for advancement" effect — settlements ABOUT to cross into the next market class already have noticeably more capable leveled NPCs, making the eventual advancement (per §6.2's growth resolver) feel earned rather than discontinuous.

#### 5.2.2.2 Design rationale

The recursive halving on the elevation chance was suggested by Jedidiah ("the % could follow the same recursive halving/thirding/quartering or whatever it ends up being"). Specifically the halving curve matches the recursive halving already in use for the L3+ tail in §5.2's level distribution — keeping a single mathematical motif throughout the system. The 50% × band_progress base rate at +1 is a project-designed lever; alternative curves are possible (e.g., 60% × progress at +1, 30% × progress at +2 for a slower decay) but the 50/25/12.5% halving is the most internally consistent with the rest of §5.2.

The expected-boost integral converges to band_progress × 1.0 (= the limit of `Σ progress × 0.5^n` for n=1 to ∞), so a settlement at the absolute top of its band has on average +1 level of elevation per L3+ NPC. That's a meaningful but not overwhelming buff — equivalent to "one NPC tier of advancement is borrowed from the next sub-band." Settlements that linger at the cusp of advancement become a bit more capable until they finally tip over.

#### 5.2.2.3 Where the elevation roll lives in the pipeline

The elevation roll is part of §7.3 baseline NPC stocking. When the stocker generates a head NPC for a new POI:
1. Look up the POI's K_local (number of L3+ NPCs assigned) per §5.4.
2. Generate K_local NPCs at decreasing levels per the §5.2 base distribution (head at the highest, adherents at sequentially lower).
3. **For each NPC, apply the elevation roll per §5.2.2 using the settlement's current band_progress.** The boost stacks on top of the base level.
4. Persist the final levels as character rows per the §7.3 stocking rules.

When the settlement's population grows mid-life and band_progress changes, **existing POI NPCs are NOT re-elevated.** Their levels are locked at stocking time. New POIs that emerge later use the current band_progress. This avoids retroactive level changes that would disturb player-NPC relationships and quest state.

A future v2 enhancement could add periodic "leveling-up" of existing NPCs as the settlement grows; v1 keeps it static (Q-UGS-47 new).

### 5.3 Step 3 — Strongholds do NOT subtract or suppress

Per Q-UGS-5 resolution (Jedidiah, 2026-05-22): **player-built and NPC-ruler strongholds do NOT count toward the §5.4 K_split and do NOT suppress emergent POI emergence.** A stronghold sited in a settlement adds POI infrastructure in *parallel* to the settlement's emergent POIs.

The mechanical consequence — and design intent — is that a Cleric-ruled domain's capital settlement visibly hosts MORE clerics than the same-class non-Cleric-ruled settlement: the Cleric ruler's fortified-church-stronghold (with 1d6 L1–L3 cleric followers + 5d6×10 0-level soldiers per `acore_campaign_classes.xml:1299-1318`) exists *on top of* the §5.4-split emergent temples (which host the city's other L3+ clerics per §5.2). Similarly, a Mage ruler's sanctum-stronghold (with 1d6 L1–L3 mage apprentices + 2d6 0-level seekers per `acore_campaign_classes.xml:696-713`) sits alongside the emergent mages_guild_halls. This makes the ruler's class *visibly affect* the settlement's character — a feature, not a balance flaw.

Step 3 therefore reduces to: **no subtraction.** Proceed directly to Step 4 with the full L3+ count from §5.2 for each class.

### 5.4 Step 4 — Distribute L3+ NPCs across POIs (the splitting roll)

The criminal-guild RAW procedure offers `acore-setting-construction-rules.xml:540-541`:

> Optionally divide criminals into multiple competing or complementary guilds instead of one unified guild. … base boss level and revenues on the membership of each separate guild rather than settlement market class.

This GDD extends the same template to Fighter / Cleric / Mage. For each class, the L3+ count `K` from §5.2 (with no stronghold subtraction per §5.3) feeds the **POI split table** to determine how many POIs `N` are produced of the matching type, and how `K` is split among them.

#### 5.4.1 POI split table (project-designed)

The split table is indexed by `K`. For each `K`, the d6 column gives the count of POIs `N` and the distribution of the highest-level NPCs.

| K (L3+ count) | d6 roll | N (POIs) | NPC split into POIs (highest-level NPC per POI) |
|---|---|---|---|
| 0 | — | 0 | (no POI of this type; only shrines/lower-tier remain — §5.5) |
| 1 | — | 1 | [1] (the one NPC anchors a single POI) |
| 2 | 1–3 | 1 | [2] (one POI with both NPCs; the higher-level NPC is the master, the other is a senior adherent) |
| 2 | 4–6 | 2 | [1, 1] (two small POIs each with one NPC) |
| 3 | 1–2 | 1 | [3] (one large POI) |
| 3 | 3–4 | 2 | [2, 1] (one mid + one small) |
| 3 | 5–6 | 3 | [1, 1, 1] (three small POIs) |
| 4–6 | 1 | 1 | [K] (one massive POI) |
| 4–6 | 2 | 2 | [⌈K/2⌉, ⌊K/2⌋] (two POIs, banker's rounding on splits) |
| 4–6 | 3 | banker(K/2) | even split |
| 4–6 | 4 | 3 | varied — banker(K/3) per POI with remainder to highest |
| 4–6 | 5 | banker(K×0.6) | mostly small POIs |
| 4–6 | 6 | K | [1] × K (all small) |
| 7–13 | 1 | 1 | [K] (one massive POI — rare; "the cathedral of the realm") |
| 7–13 | 2 | 2 | [⌈K/2⌉, ⌊K/2⌋] |
| 7–13 | 3 | 3 | even split with banker's rounding |
| 7–13 | 4 | banker(K/3) | even split |
| 7–13 | 5 | banker(K/2) | even split |
| 7–13 | 6 | K | [1] × K (all small) |
| 14+ | 1 | banker(K/8) | huge POIs (rare; "the great temple") |
| 14+ | 2–3 | banker(K/4) | mid POIs (typical metropolis pattern) |
| 14+ | 4–5 | banker(K/2) | mostly small POIs |
| 14+ | 6 | K | many small POIs (rare; "100 chapels city") |

When `K >= 4` and the rolled `N` produces non-integer splits, banker's rounding distributes the remainder to the highest-level POI first. Example: K=7 with N=3 → 7/3 = 2.33 → [3, 2, 2]; the +1 remainder goes to the first POI.

#### 5.4.2 Worked example — Class IV large town (1240 families), PC-ruled

Step 1: 100 Fighters, 50 Clerics, 25 Mages (per `acore-setting-construction-rules.xml:513`).
Step 2: L3+ counts at 13.6%: 14 Fighters, 7 Clerics, 3 Mages.
Step 3: No stronghold subtraction (per §5.3).
Step 4: roll d6 per class:
- Clerics: K=7. d6=3 → row "K=7–13", N=3 → even split with banker's rounding → [3, 2, 2]. **3 temples** (or temple-or-shrine mix depending on consecrate_altar history), heads at L3-L5 distributed per the recursive-halving curve.
- Mages: K=3. d6=4 → row "K=3", N=2 → [2, 1]. **2 sanctums** — one with K_local=2 (head mage L3 or higher + 1 L3 adherent), one with K_local=1 (lone L3 mage). This matches the published-module "Class IV city has small sanctums" pattern.
- Fighters: K=14. d6=3 → row "K=14+", N=banker(14/4)=4 (banker rounds to 4, not 3) → roughly even split [4, 4, 3, 3]. **4 mercenary guild halls**.

In addition, per §5.5 baselines: 3 shrines, 2 named taverns, 2 workshops.

**Total POI count: 3 + 2 + 4 + 3 + 2 + 2 = 16 POIs** in a Class IV large town. This is the "city has a lot of institutions" effect of the L3+ threshold; high-class settlements have many small POIs unless the split roll consolidates into a few big ones.

#### 5.4.3 Worked example — Class IV large town, NPC-ruled by a 9th-level Cleric

Same Starting Cities counts. Same L3+ counts: 14 Fighters, 7 Clerics, 3 Mages.

Per §5.3 (Q-UGS-5 resolution): the Cleric ruler's fortified-church-stronghold is registered separately and does NOT subtract from the §5.4 K count.

Step 4 splits identically to §5.4.2 — 3 emergent temples, 2 emergent sanctums, 4 emergent mercenary guild halls.

**Plus** the Cleric ruler's fortified-church-stronghold (registered as a `religious_site` per §12.4 with `(builder_kind='character', builder_character_id=<id>)`), which brings 1d6 L1–L3 cleric followers + 5d6×10 0-level soldiers per `acore_campaign_classes.xml:1299-1318`.

**Net effect:** this Cleric-ruled Class IV town has **4 temples** (3 emergent + 1 stronghold) and visibly more religious infrastructure than a comparable PC-ruled or Fighter-ruled town. This is the design intent per Q-UGS-5: the ruler's class shapes the settlement's religious / arcane / military profile.

The "splitting roll" is performed ONCE per (settlement, class) pair on first POI emergence at the market class. When a settlement advances to a new market class and L3+ counts rise, the **newly-added** L3+ NPCs are absorbed into existing POIs by default (the highest-level POI takes priority), with a 20% chance per advancement to roll a fresh split per §5.4.1 (Q-UGS-24). Newly-added L3+ NPCs that exceed the highest existing POI's capacity spawn a new POI by default.

### 5.5 Baseline POIs that emerge regardless of §5.4 split outcome

The §5.4 split distributes L3+ NPCs into POIs that those NPCs anchor. Some POI types exist in settlements regardless of L3+ presence — small shrines tended by L1–L2 clerics, named taverns run by 0-level innkeepers, workshops housing 0-level specialists. v1.3 retains the v1.2 baseline tables for these:

| Market Class | Baseline shrines (religious_site, tier=shrine) | Baseline named taverns | Baseline workshops | Baseline ports (only if hex-predicate satisfied; else 0) |
|---|---|---|---|---|
| Class VI (75–99) | 1 (the village chapel — minimum-of-1 ensures a Shaman has somewhere to be found per Q-UGS-7 resolution, even in beastman clanholds; see §10) | 1 | 0 | 0 |
| Class VI (100–249) | 1 | 1 | 0 | 1 (a single fishing dock or river landing) |
| Class V (250–449) | 2 | 1 | 1 | 1 |
| Class V (450–624) | 2 | 2 | 1 | 1 |
| Class IV (625–1249) | 3 (in addition to any §5.4 temples) | 2 | 2 | 1 |
| Class IV (1250–2499) | 4 | 3 | 2 | 1–2 |
| Class III (2500–4999) | 5 | 4 | 4 | 2 |
| Class II (5000–19999) | 7 | 6 | 8 | 3–4 |
| Class I (20000+) | 10 | 10 | 16 | 6–8 |

These baselines are independent of §5.4. They are stocked with L1–L2 NPCs (shrines, baseline taverns at workshops with 0-level proprietors) drawn from the non-L3+ portion of the Starting Cities totals. A shrine's `attached_religion` is rolled per §5.6.

When a §5.4 temple emerges, it does NOT replace shrines — the city has both temples and shrines in parallel. A shrine may be promoted to a temple via `consecrate_altar` (§4.2), which converts a shrine row to a temple row (via the §11.4 trigger) but does not decrement the shrine baseline.

The v1.3 baseline shrine increase to Class VI = 1 (from v1.2's 0–1) is the Q-UGS-7 resolution: every settlement at or above the founding threshold (75 families) has at least one shrine, ensuring the Shaman / village priest has a venue. Class VI hamlets (<75 families) below the founding threshold are not "settlements" in the urban-settlement sense and do not get POI emergence at all.

The same baseline pattern applies to **named taverns** (§4.1):

| Market Class | Baseline named taverns |
|---|---|
| Class VI | 1 |
| Class V | 1–2 (large village = 1, small town = 2) |
| Class IV | 2–3 |
| Class III | 4 |
| Class II | 6 |
| Class I | 10 |

Named-tavern emergence is independent of L3+ Fighter counts — taverns don't house leveled NPCs of a class; they're 0-level innkeepers with named-landmark status.

**Workshops and ports** are emerged independently of the §5.4 split. Each workshop holds one specialist of a kind rolled on §6.3.1's d20 table (alchemist, healer of three sub-types, animal trainer of two sub-types, sage). The workshop counts in the baseline table above include all workshop kinds together; the §6.3.1 roll determines which kind each emerges as.

Each port holds 1–3 Mariner sub-types (Captain, Navigator, Sailor) per the RAW availability counts at the settlement's market class — a Class III port hosts ~1 Captain, 1d6 Navigator, and 5d10 Sailors per `acore_equipment.xml §specialists.specialist_details`. Port presence is hex-gated per §4.2.

Ruffian sub-types (Carouser, Footpad, Reciter, Spy, Thug) are hireable from `named_tavern` POIs per the extended §7.3 stocking — taverns expose a "hire ruffian" sub-action whose availability is driven by the RAW Hiring Availability table at the settlement's market class. Spies additionally route through the criminal-guild substrate (`acore-campaign-hijinks.xml:1-51`).

Armorer and Engineer specialists are hireable from the management notebook's hiring panel (per `gdd-management-notebook.md` — Q-UGS-50 coordinates with that GDD), gated by market class per RAW. No POI surface in v1.

### 5.6 Religion attribution for emergent religious_sites

When the emergence system creates a religious_site (shrine or temple), the `attached_religion` is chosen as follows:

```
1. If domain has effective_religion set (per gdd-religion-conversion.md migration 127):
     - The largest religious_site of the split (the one with the highest-level
       cleric per §5.4) matches effective_religion (probability 100%).
     - Each remaining religious_site of the split, and each baseline shrine
       per §5.5: 80% effective_religion, 20% rolled from minority religions
       on the realm's religion roster (cultural-religious-generation output).
2. If effective_religion is unset (newly-conquered domain mid-conversion):
     50% pre-conversion religion / 50% conversion's to_religion per POI roll.
     The choice is recorded.
3. If the realm has no religion roster yet (campaign-start placeholder):
     attached_religion = '' (empty string sentinel).
     POI does not contribute to proselytizing.
```

The 80/20 split for non-primary POIs makes religious minorities visible without overwhelming the dominant religion's presence.

### 5.7 What "target" means

- **Existing player-built strongholds count.** A Cleric L9 fortified-church-as-stronghold in this settlement counts as one religious_site (tier=temple, since strongholds always have at least one consecrated altar implicitly) and reduces the §5.4 K count for clerics by 1 (per §5.3). Similarly Mage L9 sanctum-strongholds count as one mages_guild_hall POI.
- **Existing emergent POIs count.** A previously-emerged temple from a prior class advancement counts toward the splitting roll's history; it is not re-rolled when the settlement advances further (per §5.4 absorption rule).
- **The emergence system fills the delta when class advances.** The new L3+ NPCs added by the advancement absorb into existing POIs or spawn new ones per §5.4.
- **Targets are not enforced retroactively below current class.** If a settlement is Class III and drops to Class IV, POIs above the Class IV expected count are NOT demolished. They go inactive (Q-UGS-4) or remain (the simpler v1 default).

### 5.8 Clanhold reduced scale

Per `ax_domains_of_chaos.xml:30-32`, clanholds cannot grow urban size or market class via investment. v1 implementation:

- A clanhold settlement starts at the class determined by its founding urban family count (per RAW: max Class VI, since urban_families < 250) and stays there.
- The Starting Cities table is halved for clanholds (banker's rounding), reflecting halved urban revenue per `acore-campaign-general-and-magic-research.xml:646`. A Class VI clanhold's leveled-NPC counts are: 6 Fighters, 3 Thieves, 3 Clerics, 2 Mages (banker(12÷2) etc.). After §5.2's 3.4% L5+ filter, almost no L5+ NPCs exist in clanholds — the entire religious-site / sanctum / mercenary-guild-hall apparatus is replaced by 1 shrine (cultural cornerstone, minimum-of-1 per Q-UGS-7) and 1 named tavern (the lodge / hearthkeep / clanhall).
- Beastman clanhold religious_sites have `attached_religion` drawn from the beastman religion roster (Shaman-led); kin (human/demi-human) clanholds per the post-RAW reading in `gdd-domain-style-and-alignment.md` draw from kin religion rosters.

---

## 6. POI Emergence Pipeline

The pipeline runs in the start-of-month tick, immediately after the investment subphase per `ax_campaign_play.xml:9-12`. It evaluates each settlement, advances market class if a threshold has been crossed, and emerges new POIs to fill the per-class budget.

### 6.1 Pipeline outline

```
For each settlement in the realm:
  1. EVALUATE_GROWTH      → apply RAW family-attraction (1d10/1000gp) +
                            population-dice (2×1d10/1000 families) + random
                            growth (±1d10 - 1d10). Mutate urban_families.
                            (This step is the missing settlement-growth step
                            §3.2 calls for; it is part of this GDD's scope.)
  2. EVALUATE_CLASS       → derive new market_class from urban_families
                            per the RAW table. If different from current
                            market_class, fire MARKET_CLASS_ADVANCED.
  3. COMPUTE_L3_DELTA     → for Fighter, Cleric, Mage classes, recompute
                            the L3+ count per §5.1–§5.2. (No stronghold
                            subtraction per §5.3 / Q-UGS-5 resolution.)
                            Delta = new_count - existing_NPCs_placed.
  4. ROLL_SPLIT_OR_ABSORB → per §5.4, for each class with delta > 0:
                            - 80%: absorb new NPCs into existing POIs of
                              that type (assigned to the highest-level POI
                              first) without spawning new POIs.
                            - 20%: roll a fresh §5.4.1 split, which may
                              spawn additional POIs.
                            - If delta exceeds existing POI capacity (per a
                              project-designed cap of K_local + 5 per POI),
                              spawn a new POI.
                            For shrines, named taverns, workshops, recompute
                            the §5.5 baseline counts and spawn the delta.
  5. EMERGE_POIS          → for each new POI: create settlement_pois row;
                            choose attached_religion, gp_value, district
                            affinity per §6.3.
  6. STOCK_NEW_POIS       → for each new POI, run baseline NPC stocking
                            per §7.3. Persist stocked NPC character records.
                            For new religious_sites: tier='shrine' by default
                            (no consecrated altar yet); promotion to 'temple'
                            requires a subsequent consecrate_altar activity.
  7. EMIT_SIGNALS         → fire poi_emerged for each new POI. Consumer
                            systems (religion conversion, etc.) re-read
                            contribution registry on the next tick.
```

### 6.2 Step 1 — EVALUATE_GROWTH (settlement growth resolver)

Currently absent from the codebase. The implementation lives either inside `DomainGrowthResolver` as a new subphase or as a separate `SettlementGrowthResolver` (Q-UGS-15). The math, per `acore_axioms_strongholds_and_domains.xml:649-654`:

```
1. From the prior month's investment subphase, the domain owner committed
   investment_cp to this settlement. Compute investment_gp = investment_cp / 100.
2. New families from investment: roll 1d10 per full 1000gp of investment.
   Sum the rolls. Add to urban_families.
3. Population growth dice: 2 × (1d10 per full 1000 urban_families, rounded up).
   The first roll is a population increase; the second is a population decrease.
   Both use the exploding-10 rule (on a 10, roll again and add).
   Apply net delta (increase - decrease) to urban_families.
4. Random growth: +1d10 - 1d10 (per ax_campaign_play.xml:14, the "fortune
   and misfortune" subphase). Apply to urban_families.
5. Cap urban_families at the maximum-population-by-total-investment table
   per acore_axioms:641-648, using the settlement's cumulative_investment_gp.
   Excess families emigrate (lost from the settlement).
6. If urban_families < 75 after all of the above:
     Dissolve the settlement per acore_axioms:686-689. Return urban_families
     to nearby hexes as peasant_families. Mark settlement_entrances.status =
     'dissolved'. Emit settlement_dissolved signal. Stop processing this
     settlement for the month.
7. Clanhold exception per ax_domains_of_chaos:32:
     Skip steps 1–2 for clanhold settlements (urban investment cannot grow
     urban_families). Still apply step 3 (natural growth) and step 4 (random
     growth), but cap urban_families at 250 per ax_domains_of_chaos:29
     (clanhold urban-population cap). Also cap urban_families at
     0.125 × peasant_families per ax_domains_of_chaos:33.
```

### 6.3 Step 5 — EMERGE_POIS

For each new POI to emerge:

```
1. DETERMINE district affinity:
     Each POI type has a preferred district class (per gdd-settlement-stocking.md
     §4 district types). Religious_sites prefer religious districts;
     mercenary_guild_halls prefer commercial/militia; mages_guild_halls
     prefer high-wealth or civic; workshops prefer industrial; named
     taverns prefer entertainment / mixed-residential. If multiple matching
     districts exist, weighted-random by district size. If no matching
     district exists, place in the wealthiest available district.

2. SET attached_religion (for religious_site):
     Per §5.6 algorithm.

3. SET attached_specialist_kind (for workshop POIs only):
     Roll on §6.3.1 workshop type table.

4. SET gp_value:
     Per §6.4 formula.

5. (v1.4: library/workshop derivation step removed entirely.)

6. CREATE settlement_pois row:
     Persist (id, settlement_id, type, tier, attached_religion, gp_value,
              attached_specialist_kind, etc.).
     For religious_sites: tier='shrine'.
     Set status = 'emerging' (changes to 'active' after stocking).
     Set established_at_calendar_day = current_day.
     Set builder_kind = 'emergent', builder_character_id = NULL.
     Set owner_faction_id = NULL.

7. CONTINUE to next POI in delta.
```

#### 6.3.1 Workshop type table (when emerging a `workshop`)

v1.8 revised — Mariners moved to `port`, Ruffians to `named_tavern`, Armorer/Engineer to management notebook, Spellcaster removed (was not in RAW Specialists list):

| d20 Roll | Specialist Kind |
|---|---|
| 1–4 | Alchemist |
| 5–7 | Healer — General (1st-aid + minor injury treatment) |
| 8–10 | Healer — Physicker (diagnosis, disease, long-term care) |
| 11–12 | Healer — Chirurgeon (surgery, mortal-wound stabilization) |
| 13–15 | Animal Trainer — Common (horses, dogs, hawks, livestock) |
| 16–17 | Animal Trainer — Exotic (war beasts, wyverns, dire animals — typically Class III+ availability per RAW) |
| 18–20 | Sage (with topical specialization rolled per §6.3.1.1) |

The taxonomy aligns with `acore_equipment.xml §specialists.specialist_details` and the RAW Hiring Availability by Market Class table. **v1.13 (Q-UGS-52 resolution):** rolls are kept as-is. If a Class V or VI settlement rolls a Chirurgeon or Exotic Animal Trainer workshop, that workshop exists in the settlement — narratively explained as a rare specialist who chose to live in a smaller settlement for personal reasons (retirement, family ties, low-cost premises). The RAW availability percentages already make these rare; making them rarer still by reroll over-corrects. Per Jedidiah: "if it rolls high it rolls high, keep it."

##### 6.3.1.1 Sage topic table (when a workshop emerges as a Sage)

Per `acore_proficiencies.xml` topical-knowledge list and `gdd-proficiency-specializations.md`, Sage workshops are keyed to a specific topic. Roll d10:

| d10 | Sage Topic |
|---|---|
| 1 | Loremastery (history, lore, ancient civilizations) |
| 2 | Theology (religions, divine traditions, sacred texts) |
| 3 | Naturalism (flora, fauna, ecology, monsters) |
| 4 | Engineering (architecture, siege machinery, infrastructure) |
| 5 | Diplomacy (court protocol, diplomacy history, etiquette) |
| 6 | Mapmaking (cartography, regional geography) |
| 7 | Heraldry / Genealogy (noble lineages, family lore) |
| 8 | Magical Lore (magical history, identifying enchantments, magic-item lore — distinct from active spellcasting) |
| 9 | Languages (linguistics, ancient tongues, scripts) |
| 10 | Tactics / Strategy (military theory, historical battles) |

A settlement may have multiple Sage workshops with the same or different topics. The Sage's hiring price and proficiency rank scale with their level per the existing specialist hire rules.

Mercenary-class military specialists (Mercenary Officers, Quartermaster, Siege Engineer per `daw_armies_recruitment.xml:892-953`) remain in `mercenary_guild_hall` POIs per §11.3 lookup. Mariners are in `port` POIs per §4.1 / §4.2. Ruffians and Armorers/Engineers do not get workshop POIs in v1 per the §4.2 distribution table.

### 6.4 Step 4 — gp_value formula

The emergent POI's `gp_value` determines its contribution to proselytizing (for religious_sites) and is the proxy for "how impressive this institution is in the settlement." The formula is project-designed; RAW does not specify the cost of constructing non-stronghold settlement POIs.

**Important calibration note (v1.3, Q-UGS-9 resolution):** A religious_site's gp_value is the value of the building itself — its walls, statuary, vestries, residence quarters, public hall — NOT the religious aura or mechanical power of the temple. The aura comes from one or more `consecrated_altars` rows attached to the religious_site (per RAW `ax_campaign_play.xml:411-421` — divine spellcaster L5+ consecrates an altar at 100sq.ft per 100gp). The temple-building's gp_value and the consecrated-altar's gp_invested are tracked separately; they sum for proselytizing purposes (§8.3.1) but are conceptually distinct. The v1.2 base_value[temple]=2500 was inflated under the assumption that the building included an implicit altar; v1.3 separates them.

```
gp_value = base_value[type] × market_class_multiplier × poi_size_multiplier

where
  base_value[religious_site, tier='shrine']        =  200   # roadside chapel scale
  base_value[religious_site, tier='temple']        = 1000   # parish-church scale
  base_value[mercenary_guild_hall]                 =  800   # commercial building
  base_value[mages_guild_hall]                       = 1500   # stone tower / scholar hall
  base_value[named_tavern]                         =  300   # named-landmark public house
  base_value[workshop]                             =  500   # specialist's lab / studio
  base_value[port]                                 =  600   # docks, jetties, harbormaster's office

  market_class_multiplier = {VI: 0.5, V: 0.75, IV: 1.0, III: 1.5, II: 2.5, I: 4.0}

  poi_size_multiplier =
    if K_local <= 1: 1.0
    if K_local == 2: 1.5
    if K_local == 3: 2.0
    if K_local == 4: 2.5
    if K_local >= 5: 3.0    # rare "great temple" / "grand sanctum" sites
    (K_local is the count of L3+ NPCs assigned to THIS POI per §5.4 split;
     for shrines, named taverns, workshops K_local=1 always — these are
     anchored by L1-L2 or 0-level NPCs only, with no size scaling beyond
     1.0×)

All multiplications use banker's rounding (round half to even) per project convention.
```

v1.4 removes the library/workshop derivation entirely from this GDD. Settlement POIs do not carry magical-research infrastructure values.

#### Worked examples (v1.3)

| POI | Class | K_local | gp_value | Notes |
|---|---|---|---|---|
| Shrine (baseline per §5.5) | VI | 1 | 200 × 0.5 × 1.0 = **100** | Village chapel; a 100gp roadside shrine |
| Shrine | III | 1 | 200 × 1.5 × 1.0 = **300** | City corner-shrine |
| Small temple | III | 1 | 1000 × 1.5 × 1.0 = **1,500** | Parish church, single resident priest |
| Mid temple | III | 3 | 1000 × 1.5 × 2.0 = **3,000** | Town temple with 3 priests |
| Cathedral | III | 5 | 1000 × 1.5 × 3.0 = **4,500** | Small cathedral, 5 resident priests + adherents |
| Grand cathedral | I | 5 | 1000 × 4.0 × 3.0 = **12,000** | Major-city cathedral, 5 senior priests |
| Small sanctum | IV | 1 | 1500 × 1.0 × 1.0 = **1,500** | Town mage's stone tower, 1 resident mage (published-module pattern; matches "small sanctum in Class IV cities") |
| Mid sanctum | III | 2 | 1500 × 1.5 × 1.5 = **3,375** | City mages' guild hall, 2 resident mages |
| Grand sanctum | I | 5 | 1500 × 4.0 × 3.0 = **18,000** | Metropolis grand sanctum, 5 senior mages |
| Mercenary guild hall | III | 3 | 800 × 1.5 × 2.0 = **2,400** | Captain + 2 lieutenants |
| Named tavern | III | 1 | 300 × 1.5 × 1.0 = **450** | Innkeeper-run named landmark |
| Workshop (alchemist) | III | 1 | 500 × 1.5 × 1.0 = **750** | Alchemist's lab |
| Consecrated altar in a temple (RAW gp_invested at 1000gp scale) | n/a | n/a | **+1,000gp** added to attached temple's proselytizing contribution per §8.3.1 | This is the altar's `consecrated_altars.gp_invested`, NOT the temple's gp_value |

**Two observations:**
1. **Emergent POI gp_values are modest** — even the grand cathedral at Class I tops out at 12,000gp. This is the user's intent: settlement POIs are abstracted infrastructure, not stronghold-scale investments.
2. **Religious mechanical power comes from consecrated altars, not buildings.** A 1,500gp parish church with a 5,000gp consecrated altar attached contributes (1500 + 5000) = 6,500gp toward proselytizing per §8.3.1. The altar dominates the math; the building is the venue.

These numbers remain first-draft and flagged Q-UGS-9 for further calibration. The user said "These numbers will need rework" — this v1.3 pass moves the temple base from 2500 to 1000 to separate building from aura, but further tuning is welcome. The relevant levers are the `base_value` table, the `market_class_multiplier` curve, and the `poi_size_multiplier` curve.

### 6.5 Step 5 — STOCK_NEW_POIS

See §7. Each new POI receives baseline NPC stocking immediately on emergence.

### 6.5 POI funding source

The user flagged in v1.3 review: "We also haven't sorted out just how these POIs get their money." This subsection addresses the funding model conceptually.

**RAW anchor.** Urban settlements grow via the monthly investment subphase (`acore_axioms_strongholds_and_domains.xml:649-654`): each 1000gp of urban_investment spent that month attracts 1d10 new urban_families. Maximum population is bounded by cumulative total_investment per the table at `acore_axioms_strongholds_and_domains.xml:641-648` (10,000gp → 249 families, 25,000gp → 624, 75,000gp → 2499, 200,000gp → 4999, 625,000gp → 19,999, 2,500,000gp → 100,000).

**Implicit model.** The settlement's total cumulative urban_investment is the conceptual "pool" from which all infrastructure — housing, roads, sewers, walls, AND the institutional POIs covered by this GDD — is funded. RAW does not partition this pool explicitly; it tracks only total_investment for population-cap purposes. This GDD's emergent-POI gp_values are conceptually a subset of total_investment that "manifests as" institutional buildings, but v1 does NOT bookkeep this allocation against the settlement's total_investment cap.

**v1.3 funding model — abstracted.** Each emergent POI's gp_value per §6.4 is a *descriptive* number, not an *accounted* one. It tells the system "how impressive this temple is" for §8.3.1 proselytizing and §6.4 NPC-count-based size scaling, but it does not draw from any tracked balance. The settlement's `total_investment` (per `acore_axioms_strongholds_and_domains.xml:641-648`) remains the population-cap proxy; emergent POIs are byproducts of growth, not line items.

**Why this is fine for v1.** The settlement is run by NPCs (or by the PC via the urban_investment activity that RAW models at the gp level, not the line-item level). NPC realms don't surface line items for "how much did the local Mages' Guild raise from tithes this year"; that's all abstracted into urban_revenue and urban_expenses per `acore_axioms_strongholds_and_domains.xml:669-685`. Treating POI gp_values as descriptive numbers keeps the v1 system simple while preserving the proselytizing math the religion-conversion consumer needs.

**v2 enhancement (Q-UGS-41 flagged).** A future patronage mechanism could turn POI gp_values into accounted line items: the player invests N gp into the cathedral, which (1) subtracts N gp from the player's treasury, (2) adds N gp to the religious_site's gp_value, and (3) increases the proselytizing contribution by N gp. This would let a wealthy ruler boost a flagship temple's religious-structure value beyond the §6.4 default. For v1 this is OUT OF SCOPE; v1 emergent POIs use the deterministic §6.4 formula and the player has no per-POI investment lever.

**NPC-realm POI funding.** NPC realms grow their settlements via the same monthly urban_investment subphase (the realm-AI substrate per Phase 11 issues this implicitly when computing realm growth). NPC realms do NOT explicitly allocate gp to POIs in v1 — emergent POIs come into existence based on the §5.4 L3+ NPC counts, not based on NPC-spend decisions. A more sophisticated v2 realm-AI could allocate gp to specific POI types (a Cleric-ruled realm preferentially funds temples; flagged Q-UGS-18 from v1.0). For v1, all realms use the same §5.4 procedure regardless of ruler class — the ruler's class affects the stronghold (per §5.3) and thus the visible religious / arcane / military profile of the realm's capital, but doesn't bias emergent-POI distribution.

### 6.6 Step 6 — EMIT_SIGNALS

Two signals fire:

- `market_class_advanced(settlement_id, old_class, new_class)` — fired once per settlement per month if class changed.
- `poi_emerged(settlement_poi_id, type, settlement_id)` — fired once per emerged POI.

The religion-conversion consumer per `gdd-religion-conversion.md` §10's pluggable helper `religious_structures_gp_value_for_domain(domain_id, religion) -> int` reads the registry the next time it runs; it does not subscribe to `poi_emerged` directly.

---

## 7. NPC Stocking

### 7.1 Two-layer model

POI stocking has two layers:

- **Baseline (automatic).** Every emergent POI is stocked at emergence time with a head NPC (and, for multi-level POIs, K_local - 1 adherents) of the appropriate role: a low-level cleric for a shrine, a leveled-cleric cohort for a temple, a leveled-mage cohort for an mages_guild_hall, a fighter cohort for a mercenary_guild_hall, etc. The placeholder NPCs are real `characters` records with names from the cultural name banks per `gdd-name-generation.md`, levels per §7.3, alignment matching the POI's attached_religion or domain alignment, and standard stats. They are not henchmen of any PC.
- **Player-driven (Stock POI decree).** A ruler can issue a "Stock POI" decree to assign one of their henchmen or a named NPC to a specific POI. The assigned character replaces the baseline placeholder for mechanical-effect purposes (e.g., a 7th-level Cleric stocked into a temple amplifies the religion-conversion driver bonus per `gdd-religion-conversion.md` §5.3 if the ruler is also driving the conversion).

### 7.2 Stock POI decree

A new decree handler `stock_poi_decree` (analogous to `change_religion_decree` per `gdd-religion-conversion.md` §6.1):

```
PRECONDITIONS:
  - Issuer is the ruler of the domain containing the settlement.
  - Target settlement_poi exists, status = 'active'.
  - Candidate character is one of:
      - A henchman of the ruler (henchman_lifecycle.status = 'active').
      - A specialist hired by the ruler's party (specialists.closed = 0).
      - A named NPC (Phase 12+ extension; flagged Q-UGS-3 for v1 stub).
  - Candidate character's class is appropriate for the POI type:
      - temple, shrine: divine spellcaster (Cleric, Bladedancer, Priestess,
        Shaman, Dwarven Craftpriest, Lightblessed Wonderworker, etc.).
        NOT Paladin or Anti-Paladin per the kin-terminology / divine-caster
        memory feedback_paladin_anti_paladin_not_divine_casters.md.
      - workshop: matches the workshop's attached_specialist_kind.
      - mages_guild_hall: arcane-caster class (Mage, Elven Spellsword,
        Warlock, Zaharan Ruinguard, Wonderworker — any arcane tradition).
      - mercenary_guild_hall: martial class (Fighter, Barbarian, Dwarven
        Vaultguard, Explorer, etc. — any martial tradition).
      - workshop: matches the workshop's attached_specialist_kind
        (e.g., an Alchemist workshop accepts an Alchemist specialist).
      - named_tavern: any character (per Q-UGS-3 — v1 may allow any
        character, deferring class-fit validation to v2).
  - One-character-per-POI: a character can be stocked into at most one
    POI at a time. Re-stocking another POI silently unassigns the prior one.

EFFECTS:
  - settlement_pois.stocked_character_id = candidate.id
    (the column name is "cleric" for historical religion-conversion reasons
    per gdd-religion-conversion.md §9.8; in v2 it may be renamed
    stocked_character_id — flagged Q-UGS-3.)
  - The baseline placeholder NPC remains as a fallback but its mechanical
    contribution is suppressed while a stocked character is assigned.
  - Emit signal poi_stocked(settlement_poi_id, character_id).

COST: 0gp (it's a decree, not an investment). Issuing the decree consumes
the ruler's monthly decree allowance per ax_campaign_play.xml:589-604.
```

### 7.3 Baseline NPC stocking tables

When a POI emerges, the stocker runs the table appropriate to the POI type to generate the placeholder NPC(s). For POIs that hold multiple L3+ NPCs per the §5.4 split (K_local > 1), the stocker generates the head NPC at the highest level allocated to that POI plus K_local - 1 additional adherent NPCs at sequentially lower levels.

#### religious_site (tier=shrine)

| Setting | Value |
|---|---|
| Head NPC class | Cleric (default) or the realm's predominant divine-caster class. Beastman clanholds: Shaman. Elven realms: Priestess. Dwarven realms: Dwarven Craftpriest. NEVER Paladin/Anti-Paladin per `feedback_paladin_anti_paladin_not_divine_casters.md`. |
| Head NPC level | 1–2 (shrines are anchored by non-L3+ NPCs since L3+ clerics anchor temples per §5.2). A shrine with no resident cleric at all gets head_npc=NULL and Q-UGS-4 "no one here" UI; this happens only after settlement downgrade or NPC death without backfill. |
| Adherents | 0 in v1 (shrines have one resident cleric and a flock of 0-level lay worshippers — the lay worshippers are not stocked as character records). |
| Alignment | Matches POI.attached_religion's alignment per cultural-religious-generation roster. |
| Name | Cultural name bank per `gdd-name-generation.md`. |

#### religious_site (tier=temple)

A temple is a religious_site that has been promoted by a consecrated altar (§4.2). Stocked at the §5.4 K_local count:

| Setting | Value |
|---|---|
| Head NPC class | Cleric / Bladedancer / Priestess / Shaman / Dwarven Craftpriest / etc. — the same divine-caster taxonomy as shrines. |
| Head NPC level | K_local + (market_class_at_emergence offset): a temple with K_local=4 in a Class III city → head priest level 4 + 3 = 7. The offset uses {VI: 0, V: 0, IV: 1, III: 3, II: 4, I: 5} to anchor the highest-level NPC to the settlement's expected ruler-class level. Banker's rounding throughout. |
| Adherents | K_local - 1 adherent NPCs, each at (head_level - 1, head_level - 2, ...), floor at level 3 (per the §5.2 L3+ filter — sub-L3 NPCs are tracked as a count attribute per Q-UGS-42, not as separate character records). |
| Alignment | Matches POI.attached_religion. |

When the temple is the **player-built fortified-church-as-stronghold** (per `acore_campaign_classes.xml:1299-1318`), the head NPC is the PC (Cleric L9+); adherents are the RAW-specified followers (5d6×10 0-level soldiers + 1d6 L1-L3 clerics). v1's baseline stocker is bypassed for stronghold-temples; the stronghold's follower rules apply per `gdd-stronghold-construction.md`.

#### mages_guild_hall

| Setting | Value |
|---|---|
| Head NPC class | Mage (default) or culturally appropriate arcane class (Elven Spellsword, Zaharan Ruinguard, Warlock, etc.). |
| Head NPC level | K_local + (market_class offset), same scheme as temples. |
| Adherents | K_local - 1 lower-level mages (each at head_level - 1, head_level - 2, ...). Plus 1d6 apprentices (L1-L3) + 2d6 seekers (0-level normal men) per `acore-campaign-hijinks.xml` Sanctums and Dungeons rules — note these are NPC followers attracted to the sanctum, not stocked as full character records in v1 (they're a count attribute on the POI for narrative texture, similar to how strongholds' follower counts are tracked aggregate). |

#### mercenary_guild_hall

| Setting | Value |
|---|---|
| Head NPC class | Fighter (or culturally appropriate martial class: Barbarian, Dwarven Vaultguard, etc.). |
| Head NPC level | K_local + (market_class offset), same scheme. |
| Adherents | K_local - 1 lower-level Fighters. Plus military-specialist NPCs (lieutenants, captains, quartermasters, siege engineers) per the `daw_armies_recruitment.xml:929-953` market-class availability rolls — these are hireable from the guild hall, not residents per se. v1 stocks the head NPC + adherents as character records; specialists are rolled on-contact per the existing market-class availability rules. |

#### named_tavern

| Setting | Value |
|---|---|
| Head NPC class | 0-level civilian: Innkeeper. |
| Head NPC level | 0. |
| Adherents | None at v1. |
| Notes | Generic; rich stocking (rumor tables, hireling pool, etc.) is left to `gdd-settlement-stocking.md` on-contact stocking. |

#### workshop

| Setting | Value |
|---|---|
| Head NPC class | Matches workshop.attached_specialist_kind (e.g., Alchemist workshop → Alchemist specialist). |
| Head NPC level | 1 (specialists are 0-level civilian NPCs in v1). |
| Adherents | None. |

### 7.4 NPC persistence and turnover

- All baseline NPCs are written to the `characters` table with a flag distinguishing them from PC-aligned characters (Q-UGS-3 — design the flag).
- NPC death, dismissal, or departure (e.g., the temple's stocked cleric dies in a war) leaves the POI in `stocked_character_id = NULL` and `status = 'understaffed'`. The next monthly tick re-runs baseline stocking to backfill.
- Player-stocked characters who die / dismiss / depart return the POI to its baseline placeholder.

---

## 8. POI Contribution Registry

This is the umbrella's central architectural pattern. The registry is the contract by which consumer systems read POI state without coupling to POI internals.

### 8.1 Registry pattern

A centralized helper class (proposed: `engine/subsystems/settlements/poi_contribution_registry.gd`) exposes per-consumer query helpers. Each consumer system defines exactly one query signature; the registry routes the query through SQL against the `settlement_pois` table and returns the aggregated result.

This is preferable to making each consumer directly grep the table because:

1. It centralizes the joins (settlement → domain → realm) that consumers don't want to re-derive.
2. It allows contribution shapes to evolve without touching every consumer (e.g., adding a `weather_state` factor to temple proselytizing later).
3. It makes the v1 deferral pattern clean: the registry returns 0 (or empty) for unwired consumer hooks, and they wire in when their owning GDD authors implement them.

### 8.2 Consumer interface conventions

Each consumer system declares its query in its own GDD's data-contract section. This GDD only enumerates the v1 consumers and their query shapes.

```
For each consumer system C and contribution shape S:
  C declares: a query name, signature, and return type.
  Registry implements: a static method matching the signature, with the SQL.
  C calls: registry.<query_name>(args) → returns aggregated value.
```

### 8.3 v1 consumer queries

#### 8.3.1 `religious_structures_gp_value_for_domain(domain_id, religion) -> int`

The first consumer, per `gdd-religion-conversion.md` §9.8 verbatim contract. Counts both shrines and temples (RAW step "Add the gp value of religious structures erected in the realm" per `acore-campaign-general-and-magic-research.xml:562` does not distinguish):

```
SELECT
  COALESCE(SUM(p.gp_value), 0)
+ COALESCE((
    SELECT SUM(ca.gp_invested)
    FROM consecrated_altars ca
    WHERE ca.location_kind = 'settlement_poi'
      AND ca.location_ref IN (
        SELECT CAST(p2.id AS TEXT)
        FROM settlement_pois p2
        JOIN settlement_entrances s2 ON p2.settlement_id = s2.id
        WHERE s2.parent_domain_id = :domain_id
          AND p2.type = 'religious_site'
          AND p2.attached_religion = :religion
          AND p2.status = 'active'
      )
      AND ca.status = 'completed'
  ), 0)
AS total_gp_value
FROM settlement_pois p
JOIN settlement_entrances s ON p.settlement_id = s.id
WHERE s.parent_domain_id = :domain_id
  AND p.type = 'religious_site'
  AND p.attached_religion = :religion
  AND p.status = 'active'
```

Returns the sum of (a) all religious_site `gp_value` of the religion (shrines + temples) and (b) all consecrated_altars `gp_invested` attached to temples of the religion. The two contributions are additive — a temple with a 5000gp altar in it contributes `temple.gp_value + 5000`.

When a religion conversion's monthly tick runs (per `gdd-religion-conversion.md` §5.2 step 3), it calls this helper with (`conversion.domain_id`, `conversion.to_religion`). v1 stub: per `gdd-religion-conversion.md` §9.8, the helper is pluggable — the religion-conversion resolver ships in Phase 11D.3 reading consecrated_altars only; once this GDD lands, the helper is implemented as above and the resolver calls it without code change.

#### 8.3.2 `specialist_availability_for_settlement(settlement_id, kind) -> bool`

For `gdd-specialists.md` §6 future "settlement availability" gating. v1.8 expanded routing per §4.2 specialist distribution table — specialist availability depends on POI type:

```sql
SELECT EXISTS(
  SELECT 1
  FROM settlement_pois p
  WHERE p.settlement_id = :settlement_id
    AND p.status = 'active'
    AND (
      -- Workshop POI for alchemist / healer / animal trainer / sage
      (p.type = 'workshop' AND p.attached_specialist_kind = :kind)
      OR
      -- Mercenary Guild Hall for mercenary officers + quartermaster + siege engineer
      (p.type = 'mercenary_guild_hall' AND :kind IN (
        'mercenary_officer_lieutenant', 'mercenary_officer_captain',
        'mercenary_officer_colonel', 'mercenary_officer_general',
        'quartermaster', 'siege_engineer'
      ))
      OR
      -- Port POI for Mariner sub-types (only available if a port exists in this settlement)
      (p.type = 'port' AND :kind IN (
        'mariner_captain', 'mariner_navigator', 'mariner_sailor'
      ))
      OR
      -- Named Tavern for Ruffian sub-types (extended §7.3 stocking provides this hire pool)
      (p.type = 'named_tavern' AND :kind IN (
        'ruffian_carouser', 'ruffian_footpad', 'ruffian_reciter',
        'ruffian_spy', 'ruffian_thug'
      ))
    )
)
```

Specialists not represented by any POI (Armorer, Engineer) return availability from a different code path that consults the management-notebook hiring panel directly (per `gdd-management-notebook.md` — Q-UGS-50). The registry's `specialist_availability_for_settlement` returns false for those kinds; the notebook UI separately checks RAW market-class availability and renders the hire panel.

The boolean return represents "is the underlying POI / hiring surface present"; the per-monthly-tick **availability probability** (e.g., Class IV Healer-Chirurgeon at 33%) is applied at the hire-attempt level by the consumer, not the registry. That keeps this query a static structural check, with the random availability roll happening when the player attempts to hire.

The mercenary-officer kinds are taken from `daw_armies_recruitment.xml:929-953`. The market-class availability *percentages* in that RAW table apply on top of guild-hall presence: e.g., a Class IV settlement with a mercenary_guild_hall has a 33% chance of a Lieutenant being available in a given month per the RAW table. The guild hall is a precondition; the percentage is the encounter roll.

#### 8.3.3 (Reserved — v1.4 removed the magical-research helpers)

v1.2/v1.3 specified library and workshop query helpers here. Per Jedidiah 2026-05-22, this GDD no longer models magical-research infrastructure at the POI level. The `gdd-magical-research` GDD will define its own access mechanism (likely tied to player strongholds and itinerant-visit rules), independent of this GDD's settlement POI table.

#### 8.3.4 `mages_guild_hall_count_for_realm(realm_id) -> int`

For future magical-research access. Counts both emergent and player-built sanctums in a realm.

```sql
SELECT COUNT(*)
FROM settlement_pois p
JOIN settlement_entrances s ON p.settlement_id = s.id
JOIN domains d ON s.parent_domain_id = d.id
WHERE d.realm_id = :realm_id
  AND p.type = 'mages_guild_hall'
  AND p.status = 'active'
```

### 8.4 Forward-compatibility helpers (no v1 consumer)

These are shape-defined but have no consumer in v1. They are stubbed as registry methods returning 0 / empty so future consumers can wire in without backfilling the registry.

```
tavern_count_for_settlement(settlement_id) -> int          # future rumor system
poi_factional_alignment(settlement_poi_id) -> string       # Phase 12+ factions
mercenary_guild_halls_for_domain(domain_id) -> int         # future army-recruitment
```

### 8.5 Spellcasting services contract

This GDD owns the spellcasting-services purchase mechanic. v1.5 stubbed the UI; v1.9 implements it against the RAW Spell Availability by Market table at `acore_equipment.xml:979-991` (the location was found in v1.8 review per Jedidiah 2026-05-28 — earlier versions had cited `ax_campaign_play.xml:405`, which is the cross-reference; the table itself lives in the equipment file).

#### 8.5.1 Service types

Two distinct service flavors, gated by POI type:

- **Divine spellcasting services** — sold by `religious_site` POIs (both tier='shrine' and tier='temple'). Provided by the resident divine caster cohort (Cleric, Bladedancer, Priestess, Shaman, Dwarven Craftpriest, Lightblessed Wonderworker, etc. — never Paladin/Anti-Paladin per `feedback_paladin_anti_paladin_not_divine_casters.md`). RAW spell levels per ACKS divine progression: 1–7. The Spell Availability table covers levels 1–5; levels 6–7 are project-designed unavailable for casual hire (Q-UGS-54 new).
- **Arcane spellcasting services** — sold by `mages_guild_hall` POIs. Provided by the resident arcane caster cohort (Mage, Elven Spellsword, Zaharan Ruinguard, Warlock, Wonderworker arcane stack, etc.). RAW spell levels per ACKS arcane progression: 1–9. The Spell Availability table covers levels 1–6; levels 7–9 are project-designed unavailable for casual hire.

A `mercenary_guild_hall`, `named_tavern`, `workshop`, or `port` POI does NOT sell spellcasting services — those services are tradition-gated to religious_sites and mages_guild_halls.

#### 8.5.2 `available_spellcasting_services_at_poi(poi_id) -> List[SpellOffer]`

Returns the spellcasting offers available at the POI today. Each `SpellOffer` is `(tradition, spell_level, count_remaining, unit_cost_gp)` — the player picks any spell of the matching `tradition` and `spell_level` from the spell catalog (per `gdd-spell-system.md`) when purchasing, and the system resolves whether a resident NPC or a scroll / magic item delivers the cast (§8.5.6).

```
SpellOffer:
  tradition:        'arcane' | 'divine'
  spell_level:      int       # 1–5 for divine; 1–6 for arcane
  count_remaining:  int       # daily-rolled, decremented on each purchase
  unit_cost_gp:     int       # from the RAW table (Divine 1st = 10gp; Arcane 6th = 4500gp; etc.)
```

**Implementation (lazy daily roll):**

```sql
-- Step 1: ensure today's offers exist for this settlement's spell-offering POIs.
-- This is idempotent — multiple visits to the same settlement on the same day
-- find existing rows and don't re-roll.
SELECT 1 FROM settlement_poi_spell_offers
WHERE poi_id = :poi_id AND calendar_day = :today
LIMIT 1;

-- If empty, roll the RAW dice for this POI's tradition × all eligible spell levels:
--   For religious_site (any tier): roll Divine 1st through Divine 5th rows.
--   For mages_guild_hall:           roll Arcane 1st through Arcane 6th rows.
-- INSERT one row per (poi_id, today, tradition, spell_level) with rolled count.
-- The roll uses the settlement's CURRENT market_class for the dice formula.

-- Step 2: return today's still-available offers.
SELECT tradition, spell_level, count_remaining, unit_cost_gp
FROM settlement_poi_spell_offers
WHERE poi_id = :poi_id
  AND calendar_day = :today
  AND count_remaining > 0
ORDER BY tradition, spell_level;
```

The settlement-wide rolls are split across POIs of the matching tradition: if a settlement has 3 religious_sites and the RAW table rolls 10 Divine 1st-level castings, those 10 castings divide among the 3 religious_sites — proportionally by gp_value (the bigger temple gets more offers), banker's-rounded, minimum 1 per POI. (Q-UGS-55 flags the exact split formula for review.) Multiple mages_guild_halls split arcane rolls the same way.

For a settlement with one religious_site only, that POI gets the full settlement-wide divine roll. Same for one mages_guild_hall and arcane.

**Status filter.** Only POIs with `status = 'active'` get offers rolled. Abandoned POIs (per Q-UGS-4 — "no one here, leave") return empty.

#### 8.5.3 Eligibility gates — alignment

Per RAW (`acore_equipment.xml:973`): "Clerics never cast spells for adventurers of opposite alignment." Per Jedidiah 2026-05-28 v1.9 refinement: the gate is one-step strict — Neutral characters can transact with anyone, Lawful and Chaotic characters cannot transact with each other's casters.

**Divine services (religious_site):**

| Buyer alignment | Caster alignment | Outcome |
|---|---|---|
| Lawful | Lawful | ✓ allowed |
| Lawful | Neutral | ✓ allowed (Neutral caster serves anyone) |
| Lawful | Chaotic | ✗ REJECTED |
| Neutral | Lawful | ✓ allowed (Lawful caster serves Neutral) |
| Neutral | Neutral | ✓ allowed |
| Neutral | Chaotic | ✓ allowed (Chaotic caster serves Neutral) |
| Chaotic | Lawful | ✗ REJECTED |
| Chaotic | Neutral | ✓ allowed |
| Chaotic | Chaotic | ✓ allowed |

The caster's alignment is the religious_site's `attached_religion`'s alignment per the cultural-religious-generation roster. The buyer's alignment is the purchasing character's `alignment` field.

**Arcane services (mages_guild_hall):** No alignment gate. Any alignment of buyer can purchase from any alignment of caster. RAW does not restrict mages this way; the alignment field of the mages_guild_hall's resident NPCs is informational only.

**Cleric surcharge (RAW, deferred).** RAW (`acore_equipment.xml:974`): "Clerics may charge double if adventurers do not belong to their faith." Per Jedidiah 2026-05-28: "Ignore the line about clerics charging double. Surcharges will be a later implementation after the full loop is confirmed working." v1.9 does NOT implement the surcharge — `unit_cost_gp` is the RAW base cost regardless of buyer's religion. Q-UGS-53 flags this for the post-loop pass.

#### 8.5.4 Pricing — direct from RAW

Costs are the RAW values from `acore_equipment.xml:980-990` directly:

| Tradition | Level | Cost per casting |
|---|---|---|
| Divine | 1 | 10gp |
| Divine | 2 | 40gp |
| Divine | 3 | 150gp |
| Divine | 4 | 325gp |
| Divine | 5 | 500gp |
| Arcane | 1 | 5gp |
| Arcane | 2 | 20gp |
| Arcane | 3 | 75gp |
| Arcane | 4 | 325gp |
| Arcane | 5 | 1,250gp |
| Arcane | 6 | 4,500gp |

No market-class price scaling beyond what the RAW table already encodes (the availability dice fluctuate by market class, but per-casting price is flat). No buyer-side discount in the ruler's own domain — v1 ships pure RAW. Q-UGS-56 flags whether discounts in the ruler's domain should be added later (the merchant-pool system per `gdd-phase-10b-2-trade-block.md` does grant the ruler privileges; whether spellcasting services follow that pattern is open).

#### 8.5.5 Daily roll and midnight refresh

The dice for each (settlement, calendar_day, tradition, spell_level) row are rolled **once per day**, on first POI visit by the player party. Subsequent visits to the same settlement on the same day see the same offers (with decremented `count_remaining` after any purchases).

**Refresh model — lazy at query time.** The query filters by `calendar_day = :today`. At midnight tick, the calendar day increments. Yesterday's offers stop matching the filter. A new visit triggers a new lazy-init of today's offers. This avoids a midnight-tick scan to rebuild every settlement's offers.

**Cleanup.** Old `settlement_poi_spell_offers` rows accumulate. A periodic cleanup (daily or weekly) deletes rows where `calendar_day < today - 7` to bound table size. Q-UGS-57 flags the exact retention policy; recommend 7 days to support a "what was available last week" debug surface.

**NPC-level mismatch (the scroll assumption).** RAW's availability roll does NOT depend on resident NPC level. A Class III city's table can roll Arcane 6th-level availability (1d2−1 castings per day) even when the resident mages are only L5–L6 (which cap at 3rd-level casting). v1.9 does NOT gate by NPC level — if the dice roll says it's available, the offer exists. The narrative explanation is that the Mages' Guild has scrolls, magic items, or trade arrangements with traveling high-level casters to fulfill the rare offer. Per Jedidiah 2026-05-28: "If a spell of a level higher than the resident NPCs can cast is rolled as 'available' we can assume it is performed via a magic item or scroll rather than gating it by NPC level."

This is intentionally lossy with respect to RAW's "each available spellcaster can cast a spell of the listed level once per day" framing — RAW assumes the availability count IS the number of casters. v1.9 reframes it as "number of castings available," with the source being whatever combination of casters and scrolls the guild has. The mechanical outcome is the same; the narrative flexibility is gained.

#### 8.5.6 Eligibility flow — full procedure

When the Settlement Exploration UI calls `available_spellcasting_services_at_poi(poi_id)`:

```
1. Look up the POI's type.
   - religious_site or mages_guild_hall: continue.
   - Other types: return empty list.

2. Check POI.status:
   - 'active': continue.
   - 'abandoned', 'understaffed', 'dormant', 'emerging': return empty list.

3. Lazy-init today's offers per §8.5.2:
   - If no settlement_poi_spell_offers row exists for (poi_id, today),
     compute the settlement-wide rolls per the RAW table and split
     across POIs of the matching tradition per §8.5.2's split formula.

4. Return all rows with count_remaining > 0 for (poi_id, today).
   The caller (UI) then applies the alignment filter per §8.5.3 for
   divine services when displaying to a particular buyer character.
```

The alignment filter at step 4 is NOT applied in the query; the same list is shown to all viewers, but the UI grays out forbidden offers when the buyer's alignment forbids transaction. This keeps the query cacheable and avoids re-rolling per buyer.

---

## 9. Player Actions on POIs

### 9.1 Action vocabulary

The following new action vocabulary entries are registered per the action-vocabulary convention (per `docs/coding_conventions.md` action-vocabulary section). Snake_case verbs only:

- `stock_poi` — issue the Stock POI decree per §7.2.
- `unstock_poi` — release a stocked character from a POI (returns POI to placeholder baseline).
- `purchase_spellcasting` — purchase a spellcasting service from a religious_site (divine) or mages_guild_hall (arcane) per §8.5 / §9.4.
- `commission_poi` — player-initiated construction of a non-stronghold POI (Q-UGS-10 / Q-UGS-16; deferred in v1).
- `demolish_poi` — player-initiated demolition (Q-UGS-10; deferred in v1).

### 9.2 What the player CAN do in v1

- Issue `stock_poi` to bind one of their characters to a POI.
- Issue `unstock_poi` to release a binding.
- Issue `purchase_spellcasting` at a religious_site or mages_guild_hall (v1 stub returns "no services available" until the Spell Availability by Market table is extracted per Q-UGS-26 — but the UI surface and action handler exist from v1).
- Build a stronghold (Cleric L9 temple, Mage sanctum, etc.) per `gdd-stronghold-construction.md`. The stronghold is registered into `settlement_pois` with `(builder_kind='character', builder_character_id=<id>)` and counts toward §5.1 budgets.
- Consecrate altars within a temple POI (Phase 10A.2 Faith block — already implemented). The altar's `location_kind = 'settlement_poi'` and `location_ref = <temple_id>`.

### 9.4 purchase_spellcasting action

When the player visits a religious_site or mages_guild_hall via the Settlement Exploration UI, the POI's interaction menu includes a **Purchase Spellcasting Services** option. The flow:

```
1. UI calls available_spellcasting_services_at_poi(poi_id) per §8.5.2 (lazy-rolls
   today's offers on first visit; returns cached offers on later same-day visits).
2. Result list is presented as a menu of (tradition, spell_level, count_remaining,
   unit_cost_gp). For divine services, the alignment filter from §8.5.3 visually
   grays out (or hides) offers the buyer's alignment forbids.
3. Player selects an offer. UI prompts the player to pick a specific spell from
   the spell catalog (per gdd-spell-system.md) matching the offer's tradition
   and spell_level. (Player has full catalog access; system doesn't restrict by
   resident-NPC repertoire per §8.5.6.)
4. Player confirms target(s) — same UI as the normal spell-casting target picker.
5. Action handler:
   a. Validates alignment eligibility per §8.5.3 (rejects with error if forbidden).
   b. Validates settlement_poi_spell_offers.count_remaining > 0 (rejects if another
      party member purchased the last casting between menu open and confirm).
   c. Deducts unit_cost_gp from the party wallet.
   d. UPDATE settlement_poi_spell_offers SET count_remaining = count_remaining - 1
      WHERE poi_id = :poi AND calendar_day = :today AND tradition = :trad
      AND spell_level = :lvl.
   e. Resolves the spell effect via the existing spell system per gdd-spell-system.md.
      The caster is narratively the POI's stocked head NPC if their level supports
      the spell; otherwise narratively a scroll / magic item from the guild's
      reserves (per the §8.5.6 mismatch rule). Mechanically the resolution is
      identical — only the flavor text differs.
   f. Emits signal: spellcasting_service_purchased(poi_id, tradition, spell_level,
      spell_name, payer_character_id, unit_cost_gp).
6. If any validation fails, UI shows an error (alignment mismatch / insufficient
   funds / no longer available) without spending gp or consuming an offer.
```

The action handler lives in `engine/subsystems/spellcasting_services/purchase_spellcasting_handler.gd` (proposed location; final placement TBD with `docs/coding_conventions.md` review).

**No NPC-level gating, no surcharge in v1.** Per §8.5.5 and §8.5.3 v1.9 implementation: scroll/magic-item assumption handles NPC-level mismatch; cleric "double charge for outside faith" is deferred (Q-UGS-53).

**Daily limit enforcement.** Each `SpellOffer` row's `count_remaining` is the daily cap. When it hits 0, the offer disappears from the menu until midnight tick rolls a fresh count.

### 9.3 What the player CANNOT do in v1

- Demolish or replace an emergent temple of a different religion (Q-UGS-6 — religion conversion resolves the question differently: a converted domain's existing temples become "abandoned" and stop contributing to the *prior* religion's proselytizing, but they do NOT auto-convert to the new religion's roster; the player either accepts the empty-religion contribution or builds new structures).
- Commission a non-stronghold POI directly (Q-UGS-16). For now, POIs emerge from growth events only, or arrive as strongholds.
- Issue domain-wide stocking decrees ("stock all my temples with my acolytes"). Each `stock_poi` is per-POI.

---

## 10. Clanhold and Alignment Exceptions

### 10.1 Clanhold settlements

- **Cannot grow class** per `ax_domains_of_chaos.xml:30-32`. The §6.2 settlement-growth resolver respects this.
- **POI budget halved** per §5.4 with a minimum of 1 shrine (the cultural cornerstone) and 1 named tavern (the public house / hearthkeep).
- **Beastman clanhold POI roster** draws from beastman religion / culture (per the kin terminology memory). Religious_sites become Shaman-led; mercenary_guild_halls become war-band or hunt-band lodges (flavor; mechanical effect identical). Arcane_sanctums are rare-to-absent (beastmen rarely produce trained mages); rolled per §5.4 only if K_mages > 0 after the §5.8 clanhold-halving filter, which is generally never.
- **Human/demi-human clanholds** (per the post-RAW reading in `gdd-domain-style-and-alignment.md`) use the standard POI vocabulary but with the halved scale.

### 10.2 Alignment-mismatched temples

Per the existing alignment-penalty model in `gdd-domain-style-and-alignment.md` and `acore_axioms_strongholds_and_domains.xml:461-475`, a chaotic-aligned ruler in a lawful-aligned domain (or vice versa) suffers domain morale penalties. Emergent temples follow the §5.3 religion-bias rule: 90% of new temples match the domain's effective_religion, 10% are minority religions. This means:

- A newly-conquered domain in mid-conversion sees a balanced spread of pre-conversion and post-conversion temples emerging during the conversion arc.
- The pre-conversion temples gradually become "abandoned" as the conversion completes (their attached_religion is no longer the domain's effective_religion); they remain in the table with `status = 'active'` but their proselytizing contribution accrues to a religion the domain no longer recognizes. This is intentional flavor — old gods linger.

### 10.3 Religion-conversion interaction

When the religion conversion completes per `gdd-religion-conversion.md` §5.6, an atomic alignment shift occurs at the 60% congregant threshold. After the shift, existing temples of the *prior* religion remain (Q-UGS-6); their `gp_value` continues to contribute to a `religious_structures_gp_value_for_domain(domain_id, prior_religion)` query, but the domain's effective_religion is now `new_religion` and any new emergent temples will (90%) be of the new religion. Over many growth events, the new religion accumulates dominance.

This is intentional — it gives a "religious landscape changes slowly" texture without requiring per-temple conversion mechanics in v1.

---

## 11. Data Model

### 11.1 New table: `settlement_pois`

Migration ordinal TBD (next available: 126 if Phase 11D-prereq.B's 127 lands first; otherwise 126 itself).

```sql
CREATE TABLE settlement_pois (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  settlement_id INTEGER NOT NULL REFERENCES settlement_entrances(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN (
    'religious_site', 'mercenary_guild_hall', 'mages_guild_hall',
    'named_tavern', 'workshop', 'port'
  )),
  tier TEXT NOT NULL DEFAULT '' CHECK (tier IN ('', 'shrine', 'temple')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN (
    'emerging', 'active', 'understaffed', 'dormant', 'abandoned'
  )),
  -- v1.10 (Q-UGS-17): split from v1.0–v1.9 string `builder` field into two
  -- typed columns. builder_kind is the discriminator; builder_character_id
  -- is the FK for stronghold-registered POIs.
  builder_kind TEXT NOT NULL DEFAULT 'emergent'
    CHECK (builder_kind IN ('emergent', 'character')),
  builder_character_id INTEGER REFERENCES characters(id) ON DELETE SET NULL,
  CHECK (
    (builder_kind = 'emergent' AND builder_character_id IS NULL)
    OR
    (builder_kind = 'character' AND builder_character_id IS NOT NULL)
  ),
  emerged_via TEXT NOT NULL DEFAULT '' CHECK (emerged_via IN (
    '', 'class_advancement', 'player_commission', 'stronghold_register',
    'baseline_emergence'
  )),
  established_at_calendar_day INTEGER NOT NULL,
  gp_value INTEGER NOT NULL DEFAULT 0,

  -- L3+ NPC count at this specific POI per §5.4 split outcome (v1.3
  -- lowered the anchor threshold from L5+ to L3+ per Q-UGS-8 resolution).
  -- 0 for shrines, baseline taverns, baseline workshops; > 0 for temples,
  -- mages_guild_halls, mercenary_guild_halls hosting one or more L3+ NPCs.
  l3_plus_npc_count INTEGER NOT NULL DEFAULT 0,

  -- v1.10 (Q-UGS-42): count of L1–L2 adherents nominally living here.
  -- These NPCs are NOT persisted as character rows at emergence time;
  -- they materialize on-demand per the on-demand materialization path
  -- in §5.2. The count decrements when an adherent is materialized
  -- (the materialized NPC becomes a real characters row); the count
  -- may be restocked when a player-interacted on_demand NPC departs
  -- without being kept.
  l1_l2_adherent_count INTEGER NOT NULL DEFAULT 0
    CHECK (l1_l2_adherent_count >= 0),

  -- Religion attribution (religious_site only; '' empty-string sentinel otherwise)
  attached_religion TEXT NOT NULL DEFAULT '',

  -- Specialist attribution (workshop only)
  attached_specialist_kind TEXT NOT NULL DEFAULT '',

  -- (v1.4: library_value and workshop_value columns removed — magical-
  -- research infrastructure is no longer modeled by this GDD.)

  -- Stocking. v1.3: renamed from v1.2's stocked_cleric_character_id per
  -- Q-UGS-3 resolution — the column is now used for mage / fighter /
  -- specialist stocking too, so the cleric-specific name was misleading.
  stocked_character_id INTEGER REFERENCES characters(id) ON DELETE SET NULL,
  baseline_head_npc_character_id INTEGER REFERENCES characters(id) ON DELETE SET NULL,

  -- District affinity (per gdd-settlement-stocking.md district types)
  preferred_district_class TEXT NOT NULL DEFAULT '',

  -- Forward-compatibility with Phase 12 factions
  owner_faction_id INTEGER,  -- nullable; v1 always NULL = "the realm"

  -- Tier-cache invariant: tier = '' for non-religious_site;
  -- tier = 'shrine' or 'temple' for religious_site.
  CHECK (
    (type = 'religious_site' AND tier IN ('shrine', 'temple'))
    OR (type <> 'religious_site' AND tier = '')
  ),

  -- (v1.4: library_value / workshop_value CHECK removed — columns no
  -- longer exist.)

  -- Indexing
  UNIQUE (settlement_id, id)
);

CREATE INDEX idx_settlement_pois_settlement ON settlement_pois(settlement_id);
CREATE INDEX idx_settlement_pois_type ON settlement_pois(type);
CREATE INDEX idx_settlement_pois_religion ON settlement_pois(attached_religion)
  WHERE attached_religion <> '';
CREATE INDEX idx_settlement_pois_specialist_kind ON settlement_pois(attached_specialist_kind)
  WHERE attached_specialist_kind <> '';
CREATE INDEX idx_settlement_pois_tier ON settlement_pois(tier)
  WHERE tier <> '';
```

The `tier` column is a **denormalized cache** of "does this religious_site have a completed consecrated_altars row attached?" — recomputed by a trigger or by application logic on insert/update of `consecrated_altars`. The cache eliminates a JOIN in the §8.3.1 hot-path query.

### 11.2 Field semantics

| Column | Semantics |
|---|---|
| `settlement_id` | FK to settlement_entrances. ON DELETE CASCADE — if a settlement dissolves, its POIs delete. |
| `type` | One of the §4.1 vocabulary (5 types). CHECK-constrained. |
| `tier` | For `religious_site` only: 'shrine' (no completed consecrated altar) or 'temple' (at least one completed consecrated altar attached). For non-religious_site types: '' (empty-string sentinel). Recomputed on consecrated_altars insert/update. |
| `status` | `emerging` (between steps 5 and 6 of §6.1, transient); `active` (default normal state); `understaffed` (stocked character died/departed, awaiting backfill); `dormant` (workshop whose specialist departed, sanctum temporarily without a head mage); `abandoned` (religious_site whose religion is no longer the domain's effective_religion AND no stocked character — still contributes to its religion's proselytizing if queried, but is structurally inactive). |
| `builder_kind` | Discriminator (v1.10 per Q-UGS-17 resolution): `emergent` for growth-emerged POIs; `character` for player-built / stronghold-registered POIs. Future kinds (`faction`, `bestowed_by_grant`, etc.) may extend the CHECK constraint. |
| `builder_character_id` | FK to characters.id when `builder_kind = 'character'`; NULL otherwise. CHECK constraint enforces the (kind, id) consistency. ON DELETE SET NULL — when the building character is removed (death, removal-by-cleanup), the POI persists but loses attribution; the §6.x growth pipeline may eventually classify it as emergent retroactively if needed. |
| `emerged_via` | Audit field. `class_advancement` for §5.4-split emergence; `baseline_emergence` for §5.5 shrines/taverns/workshops; `player_commission` (deferred); `stronghold_register` when a stronghold is registered as a POI. |
| `gp_value` | Per §6.4 formula. For player-built strongholds: matches stronghold gp_value. Read by consumer queries. |
| `l3_plus_npc_count` | The K_local from §5.4 — count of L3+ NPCs assigned to this specific POI (renamed in v1.3 from v1.0–v1.2's `l5_plus_npc_count` per Q-UGS-8 anchor-threshold change). Used by §6.4's poi_size_multiplier and by the §7.3 stocking pipeline. |
| `attached_religion` | Religion ID matching the cultural-religious-generation roster. Empty string `''` if not applicable (non-religious_site) or unassigned (religion roster not yet established). |
| `attached_specialist_kind` | For workshops only — one of the §6.3.1 kinds. Empty string for non-workshops. |
(v1.4: `library_value` and `workshop_value` columns removed from the schema. Magical-research infrastructure is no longer modeled by this GDD; characters access libraries/workshops via their own player-built strongholds per `gdd-stronghold-construction.md` or via a future visiting-researcher mechanism the `gdd-magical-research` GDD will define.)
| `stocked_character_id` | The player-assigned character (per §7.2 Stock POI decree). NULL if no decree active. **v1.3 rename:** v1.0/v1.1/v1.2 named this column `stocked_cleric_character_id` after the religion-conversion contract; the rename per Q-UGS-3 resolution reflects that this column also stocks mages, fighters, and specialists. The `gdd-religion-conversion.md` §9.8 contract needs a one-line update to use the new name. |
| `baseline_head_npc_character_id` | The auto-stocked head NPC (highest-level resident). Persistent — represents the actual head occupant when no player-stocked character is bound. Renamed from v1.0 `baseline_npc_character_id` to clarify "head" status. Additional adherent NPCs at multi-level POIs (per §7.3) are persisted as character records but linked via a child relation, NOT via additional columns here (Q-UGS-28 — confirm child-relation shape: separate `settlement_poi_adherents` table vs. JSON list on the POI row). |
| `preferred_district_class` | District class hint (per `gdd-settlement-stocking.md` district types) for layout consumption later. v1 uses this only for narrative / on-contact stocking. |
| `owner_faction_id` | Nullable. v1 = NULL (the realm). Phase 12+ assigns. |

### 11.3 Mercenary guild hall → specialist-kind lookup

A static, project-designed lookup (replaces v1.0's guildhouse table since guildhouses no longer exist as a separate type). The `specialist_availability_for_settlement` query (§8.3.2) uses this lookup to determine which mercenary specialist kinds a `mercenary_guild_hall` provides:

| Specialist kind (from `daw_armies_recruitment.xml`) | Provided by mercenary_guild_hall? |
|---|---|
| Mercenary Officer — Lieutenant | Yes (any market class with a guild hall) |
| Mercenary Officer — Captain | Yes |
| Mercenary Officer — Colonel | Yes |
| Mercenary Officer — General | Yes (Class I/II only per RAW table) |
| Quartermaster | Yes |
| Siege Engineer | Yes |

Non-military specialists (alchemist, healer, sage, etc.) are NOT provided by mercenary guild halls; they require a matching `workshop` POI (§8.3.2).

### 11.4 Religious-site tier-cache trigger

The `tier` denormalized cache is maintained by a trigger on `consecrated_altars` (proposed SQLite syntax):

```sql
CREATE TRIGGER trg_consecrated_altars_promote_religious_site
AFTER UPDATE OF status ON consecrated_altars
WHEN NEW.status = 'completed' AND NEW.location_kind = 'settlement_poi'
BEGIN
  UPDATE settlement_pois
  SET tier = 'temple'
  WHERE id = CAST(NEW.location_ref AS INTEGER)
    AND type = 'religious_site';
END;

CREATE TRIGGER trg_consecrated_altars_demote_religious_site
AFTER UPDATE OF status ON consecrated_altars
WHEN NEW.status = 'broken_unblessed' AND NEW.location_kind = 'settlement_poi'
BEGIN
  UPDATE settlement_pois
  SET tier = CASE
    WHEN EXISTS (
      SELECT 1 FROM consecrated_altars ca
      WHERE ca.location_kind = 'settlement_poi'
        AND CAST(ca.location_ref AS INTEGER) = settlement_pois.id
        AND ca.status = 'completed'
    ) THEN 'temple'
    ELSE 'shrine'
  END
  WHERE id = CAST(NEW.location_ref AS INTEGER)
    AND type = 'religious_site';
END;
```

The demotion trigger reverts tier to 'shrine' only when no other completed altars remain attached. Multiple altars can stack inside a single temple (each contributing its `gp_invested` to proselytizing per §8.3.1); the temple downgrades to shrine only when ALL of its altars are broken/unblessed.

### 11.4 Schema migrations to other tables

Four ancillary updates land in the same migration:

```sql
-- 1. Allow consecrated_altars to point at a settlement_poi as its location.
-- The location_kind = 'settlement_poi' value already exists; this is
-- documentation that location_ref for that kind is a settlement_pois.id.
-- No schema change; documented in §4.2.

-- 2. Allow strongholds to register a settlement_poi when sited in a settlement.
ALTER TABLE strongholds ADD COLUMN registered_settlement_poi_id INTEGER
  REFERENCES settlement_pois(id) ON DELETE SET NULL;

-- 3. v1.10 (Q-UGS-28): adherent NPCs and other POI-resident characters carry
-- a foreign-key pointer to their home POI. Used by §7.3 stocking, §5.2
-- adherent distribution, and Q-UGS-42's on-demand materialization path.
-- Nullable: PC characters and itinerant NPCs have home_poi_id = NULL.
ALTER TABLE characters ADD COLUMN home_poi_id INTEGER
  REFERENCES settlement_pois(id) ON DELETE SET NULL;

CREATE INDEX idx_characters_home_poi
  ON characters(home_poi_id) WHERE home_poi_id IS NOT NULL;

-- 4. v1.10 (Q-UGS-29): npc_role enum disambiguates the NPC classifications
-- this GDD and other systems need to filter on. The set is open to extension
-- by future faction work, but v1 enumerates the cases listed below.
ALTER TABLE characters ADD COLUMN npc_role TEXT NOT NULL DEFAULT 'player'
  CHECK (npc_role IN (
    'player',              -- PC-controlled character
    'henchman',            -- bound to a PC via henchman_lifecycle
    'specialist',          -- hired specialist per migration 053
    'baseline_placeholder',-- auto-stocked by §7.3 emergence; replaceable
    'stocked',             -- player-assigned via stock_poi decree per §7.2
    'named_npc',           -- world-significant NPC (rulers, quest-givers, etc.)
    'on_demand'            -- materialized on contact per Q-UGS-42; not yet
                           --   "kept" by any player; may be cleaned up if
                           --   no party member retained interaction state
  ));

CREATE INDEX idx_characters_npc_role
  ON characters(npc_role) WHERE npc_role <> 'player';
```

The `strongholds.registered_settlement_poi_id` is set by the stronghold completion handler when the stronghold is sited in a settlement hex; the corresponding settlement_pois row has `(builder_kind='character', builder_character_id=<character_id>)` and the same `gp_value` as the stronghold.

**Q-UGS-28 / Q-UGS-29 semantics.** The `home_poi_id` column ties a character to a POI for narrative-and-data purposes — the temple's head priest has `home_poi_id = <temple's settlement_pois.id>`. When the POI is removed, the character persists (`ON DELETE SET NULL`) but loses their home — they become unanchored. The `npc_role` column lets queries quickly filter "all baseline_placeholder NPCs in this domain" (for cleanup), "all named_npc rows" (for the Settlement UI's notable-persons list), etc. The `on_demand` role tracks NPCs materialized by §7.3.x lazy stocking (per Q-UGS-42) that have not yet been "kept" — these are eligible for cleanup if no party member has hired, befriended, or otherwise retained them.

### 11.4a New table: `settlement_poi_spell_offers` (v1.9)

Backs the §8.5 spellcasting services contract — one row per (POI, calendar_day, tradition, spell_level) capturing the rolled daily availability from the RAW Spell Availability table (`acore_equipment.xml:979-991`).

```sql
CREATE TABLE settlement_poi_spell_offers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  poi_id INTEGER NOT NULL REFERENCES settlement_pois(id) ON DELETE CASCADE,
  calendar_day INTEGER NOT NULL,
  tradition TEXT NOT NULL CHECK (tradition IN ('divine', 'arcane')),
  spell_level INTEGER NOT NULL CHECK (spell_level BETWEEN 1 AND 6),
  count_initial INTEGER NOT NULL CHECK (count_initial >= 0),
  count_remaining INTEGER NOT NULL CHECK (count_remaining >= 0
    AND count_remaining <= count_initial),
  unit_cost_gp INTEGER NOT NULL CHECK (unit_cost_gp >= 0),

  UNIQUE (poi_id, calendar_day, tradition, spell_level)
);

CREATE INDEX idx_settlement_poi_spell_offers_lookup
  ON settlement_poi_spell_offers (poi_id, calendar_day);
```

**Field semantics:**

| Column | Purpose |
|---|---|
| `poi_id` | FK to settlement_pois. ON DELETE CASCADE — if a POI is removed, its offers go too. |
| `calendar_day` | The calendar day (per the game's daily-tick system) on which this offer is valid. Filter `WHERE calendar_day = :today` to get current offers; old rows are stale until cleanup. |
| `tradition` | 'divine' for religious_sites; 'arcane' for mages_guild_halls. |
| `spell_level` | 1–5 for divine; 1–6 for arcane. Other levels are not represented (unavailable per §8.5.1). |
| `count_initial` | The dice-rolled count from the RAW table at the time of the daily roll. Immutable after initial INSERT for audit. |
| `count_remaining` | Decremented by 1 on each successful purchase. Hits 0 when the daily allotment is consumed. |
| `unit_cost_gp` | RAW per-casting price (Divine 1st = 10gp; Arcane 6th = 4500gp; etc.). Same as RAW table; no buyer-side modifiers in v1 (Q-UGS-56). |

**Lazy-init by the §8.5.2 query.** No background process pre-populates this table. The first time a player queries a POI for spellcasting offers on a given day, the §8.5.2 query rolls the dice and INSERTs the day's offers. Subsequent queries that day use the existing rows.

**Cleanup (Q-UGS-57).** Old rows accumulate at ~10 rows per POI per day. A settlement with 5 spell-offering POIs accumulates 50 rows per day; over a year that's 18,000 rows per settlement. Recommend a daily-tick cleanup that deletes rows where `calendar_day < today - 7` (7-day retention). The retention window supports "what was available recently" debug queries; tune as needed.

### 11.5 EventBus signals

New EventBus signals (per `engine/autoloads/event_bus.gd`):

```
signal market_class_advanced(settlement_id: int, old_class: int, new_class: int)
signal market_class_regressed(settlement_id: int, old_class: int, new_class: int)
signal settlement_dissolved(settlement_id: int)
signal poi_emerged(settlement_poi_id: int, type: String, settlement_id: int)
signal poi_stocked(settlement_poi_id: int, character_id: int)
signal poi_unstocked(settlement_poi_id: int, prior_character_id: int)
signal poi_status_changed(settlement_poi_id: int, old_status: String, new_status: String)
signal spellcasting_service_purchased(settlement_poi_id: int, tradition: String, spell_level: int, spell_name: String, payer_character_id: int, unit_cost_gp: int)
```

Past-tense verbs per convention. The `market_class_regressed` signal is emitted but largely unconsumed in v1 (downgrade POI demolition deferred per Q-UGS-4).

---

## 12. Cross-System Integration

### 12.1 Religion conversion (Phase 11D.3)

Per `gdd-religion-conversion.md` §9.8, §10. When this GDD lands, the religion-conversion resolver's pluggable helper `ReligionConversionResolver.religious_structures_gp_value_for_domain(domain_id, religion)` becomes:

```
return PoiContributionRegistry.religious_structures_gp_value_for_domain(
  domain_id, religion
) + ConsecratedAltarRepository.altar_gp_value_for_domain(domain_id, religion)
```

The altar contribution remains (Phase 10A.2 infrastructure); the temple/shrine contribution adds on top.

### 12.2 Magical research (future)

When the magical-research GDD authors its access/discount rules, it can call:

```
PoiContributionRegistry.mages_guild_hall_count_for_realm(realm_id)
```

The other v1.2/v1.3-era helpers (`mages_guild_hall_research_value_for_domain`, `domain_has_research_library`) were removed in v1.4 when the library/workshop subsystem was nuked. The magical-research GDD will need its own mechanism for library/workshop access — settlement POIs do not provide it in v1.

### 12.3 Specialists (Phase 6.5 expansion per `gdd-specialists.md` §6)

When the specialist GDD lands settlement-availability gating, the hire panel calls:

```
PoiContributionRegistry.specialist_availability_for_settlement(settlement_id, kind)
```

A specialist of kind X is only hireable from a settlement where this returns true. Pathfinder + Land Surveyor (the v1 kinds shipped per `gdd-specialists.md`) ship without this gating; the gating applies to the future kinds (Alchemist, Healer, etc.).

### 12.4 Stronghold construction

When a stronghold of an archetype that maps to a settlement-POI type is completed in a settlement hex:

| Stronghold archetype | Maps to POI type | Tier / attributes |
|---|---|---|
| Cleric / Bladedancer / Shaman / etc. fortified-church-as-stronghold (per `acore_campaign_classes.xml:1299-1318`) | `religious_site` | **v1.10 (Q-UGS-30 resolution — option b):** `tier = 'shrine'` initially. No implicit consecrated altar is created at stronghold completion. To promote the new fortified-church-stronghold to `tier = 'temple'`, the player must explicitly run the `consecrate_altar` activity per RAW (`ax_campaign_play.xml:411-421` — requires divine spellcaster L5+; 1 day per 500gp; gp must be paid). Once the altar's `status = 'completed'`, the §11.4 trigger flips the religious_site's tier to 'temple'. **Exception — grant or purchase:** if the stronghold is acquired by grant from a higher authority OR by purchase from a prior owner (per `gdd-stronghold-construction.md`'s grant/purchase rules), the prior owner's consecrated_altars come with the stronghold. Specifically, the migration script reassigns existing `consecrated_altars` rows whose `location_kind = 'settlement_poi'` and `location_ref = <prior religious_site's id>` to point at the new religious_site row (or, if the stronghold acquisition replaces the prior settlement_pois row, updates the reference accordingly). The §11.4 tier-cache trigger then resolves the tier correctly post-reassignment. **No free altars under any other circumstance** — a player who builds a brand-new fortified church from scratch starts at shrine tier and pays for the altar separately. `gp_value = stronghold.gp_value`. Library and magic-research workshop infrastructure (if the player wants any) is an internal matter for `gdd-stronghold-construction.md`; this GDD does not track those values. |
| Mage L9 sanctum sited in a settlement (per `acore_campaign_classes.xml:696-713`) | `mages_guild_hall` | `(builder_kind='character', builder_character_id=<id>)`; `gp_value = stronghold.gp_value`. Same as above — library / magic-research workshop allocation is `gdd-stronghold-construction.md`'s domain. |
| Fighter L9 castle / Dwarf L9 vault sited in a settlement | NOT mapped to a settlement_pois row. Fighters' castles are domain-scale strongholds, not interior settlement POIs. The settlement's mercenary_guild_hall remains separate (the Fighter ruler's castle may HOUSE the guild hall, but the guild hall is its own entity). |
| Thief / Assassin / Nightblade hideout | NOT mapped. Hideouts are owned by the syndicate system per migration 118. |
| Fastness (Elf), Vault (Dwarf, non-settlement) | NOT mapped to settlement POIs. These are wilderness or domain-scale strongholds. |
| Clanhold (per `ax_domains_of_chaos.xml`) | NOT mapped to settlement POIs at the stronghold scale. Clanhold settlements still get §5.8-scale POIs of their own. |

### 12.5 Faith block (Phase 10A.2)

Existing `consecrate_altar` activity gains a target-POI parameter: the player may consecrate an altar *within* a specific temple POI. The altar's `location_kind = 'settlement_poi'` and `location_ref = <temple.id>`. Aura applies to the temple's footprint; aura-of-influence calculations for proselytizing are not affected (the altar's gp_value contributes as before; the temple's gp_value contributes independently).

### 12.6 Mercantile (Phase 10B.2)

v1.1 has no Merchants' Guild POI type — merchant infrastructure is owned by `MerchantPoolRepository` (Phase 10B.2) and not duplicated as a POI. A future enhancement could add a `merchant_guild_hall` POI type to extend the §5.4 splitting pattern to Thieves and Venturers; flagged Q-UGS-12.

### 12.7 Realm AI / NPC realms

NPC-ruled realms (per the Phase 11 realm substrate) also experience urban growth. The settlement-growth pipeline runs for ALL settlements regardless of PC/NPC ruler. NPC realms do NOT issue Stock POI decrees in v1 (their temples remain with baseline-placeholder clerics). Flagged Q-UGS-18 for a future NPC AI extension where rival realms compete via temple stocking.

### 12.8a Management notebook (specialist hiring panels)

Per v1.8's specialist distribution model (§4.2), Armorer and Engineer specialists do NOT get POI surfaces in v1. They are hireable from a management-notebook hiring panel per `gdd-management-notebook.md`, gated by market class per the RAW Hiring Availability by Market Class table.

The integration contract:
- Management notebook hire panel queries the RAW availability table (whose extraction is Q-UGS-26's sibling concern) for Armorer / Engineer at the settlement's market class.
- It does NOT call `specialist_availability_for_settlement` per §8.3.2 (which returns false for these kinds, by design — Armorers and Engineers have no POI to gate against).
- Successful hire creates a `specialists` row (per migration 053 / `gdd-specialists.md`) tied to the hiring party. No `settlement_pois` row is mutated.

If the user later decides Armorer/Engineer SHOULD have POI surfaces, the §4.1 vocabulary and §6.3.1 workshop table can be amended to include them, and this §12.8a entry becomes obsolete. Flagged Q-UGS-50.

### 12.8 Spell system (Phase 5+)

The `purchase_spellcasting` action handler (§9.4) consumes the existing spell-system infrastructure per `gdd-spell-system.md` to resolve the cast effect. When a service is rendered, the resident NPC's spell-repertoire row provides the spell definition; the existing `cast_spell` resolution pipeline handles target selection, save throws (if any), and effect application. The player character paying for the service is the **target** (or designator of the target, for area / multi-target spells); the resident NPC is the **caster**, but the resident's XP / spell-slot tracking is abstracted away (we don't track stocked-NPC spell slots in v1 — the resident is assumed to have practical-unlimited daily preparation capacity for any spell in their repertoire, per Q-UGS-45).

When the Spell Availability by Market table from `ax_campaign_play.xml:405` lands, the §8.5.2 query consumes that table to filter the resident's repertoire by market-class availability and apply pricing.

---

## 13. Implementation Roadmap (build-ready, v1.14)

This section is the build-agent handoff. It maps every v1 commitment in this GDD to a concrete stage with file paths, schema migration components, signal signatures, test cases, and cross-system patches. Stages are sequenced by dependency — earlier stages must land before later ones can be tested end-to-end.

### 13.0 Migration ordinal and prerequisites

**Migration number:** Reserve the next available migration ordinal at implementation start. As of the latest build-log entry, migrations through 125 have landed. If `gdd-religion-conversion.md` Phase 11D.3 ships migration 127 first, this GDD's migration becomes 126 (lands before religion-conversion) or 128 (lands after). The implementation decides ordinal at branch-creation time.

**Prerequisites (must be in place before this GDD's implementation starts):**
- Phase 11D.3 schema changes per `gdd-religion-conversion.md` if landing after religion-conversion. If landing before, the religion-conversion resolver works with consecrated_altars only until this GDD's §8.3.1 helper is in place — `gdd-religion-conversion.md` §10 explicitly designs for this pluggable helper.
- Existing infrastructure: `engine/autoloads/event_bus.gd`, `engine/autoloads/campaign_repository.gd`, `engine/subsystems/domains/domain_growth_resolver.gd`, `engine/subsystems/hex_map_controller.gd`, `engine/shared_types/CharacterData.gd`. None of these need pre-modification.
- `gdd-terrain-system.md` must expose the `terrain_hex_has_water_access(map_id, hex_q, hex_r) -> bool` predicate per Q-UGS-49. If not yet implemented, Stage C's port emergence is stubbed to return false (no ports anywhere) until the predicate lands.

### 13.1 Stage A — Schema migration + EventBus signal declarations

**Goal:** All tables, columns, indexes, triggers, and signal declarations land. No runtime code yet.

**Files to create:**
- `db/migrations/NNN_urban_growth_stocking_schema.sql` — full migration script per §11
- `engine/shared_types/SpellOffer.gd` — Resource class for (tradition, spell_level, count_remaining, unit_cost_gp) tuples per §8.5.2

**Files to edit:**
- `db/schema.sql` — apply the migration's effects to the canonical current schema (per project convention `CLAUDE.md`: "schema.sql canonical current schema")
- `engine/autoloads/event_bus.gd` — declare the eight new signals per §11.5:
  ```gdscript
  signal market_class_advanced(settlement_id: int, old_class: int, new_class: int)
  signal market_class_regressed(settlement_id: int, old_class: int, new_class: int)
  signal settlement_dissolved(settlement_id: int)
  signal poi_emerged(settlement_poi_id: int, type: String, settlement_id: int)
  signal poi_stocked(settlement_poi_id: int, character_id: int)
  signal poi_unstocked(settlement_poi_id: int, prior_character_id: int)
  signal poi_status_changed(settlement_poi_id: int, old_status: String, new_status: String)
  signal spellcasting_service_purchased(settlement_poi_id: int, tradition: String, spell_level: int, spell_name: String, payer_character_id: int, unit_cost_gp: int)
  ```

**Migration SQL components (per §11):**
1. `CREATE TABLE settlement_pois` per §11.1 (with all v1.10/v1.13 column additions: builder_kind, builder_character_id, l1_l2_adherent_count).
2. `CREATE TABLE settlement_poi_spell_offers` per §11.4a.
3. `CREATE TRIGGER trg_consecrated_altars_promote_religious_site` per §11.4.
4. `CREATE TRIGGER trg_consecrated_altars_demote_religious_site` per §11.4.
5. `ALTER TABLE strongholds ADD COLUMN registered_settlement_poi_id INTEGER REFERENCES settlement_pois(id) ON DELETE SET NULL` per §11.4.
6. `ALTER TABLE characters ADD COLUMN home_poi_id INTEGER REFERENCES settlement_pois(id) ON DELETE SET NULL` per Q-UGS-28.
7. `ALTER TABLE characters ADD COLUMN npc_role TEXT NOT NULL DEFAULT 'player' CHECK (...)` per Q-UGS-29.
8. All indexes per §11.1 / §11.4a / Q-UGS-28 / Q-UGS-29.

**Tests:**
- `tests/test_settlement_pois_schema.gd` — verifies the table, indexes, triggers exist after migration. INSERT/UPDATE round-trip for each POI type. Trigger fires correctly on consecrated_altars status change (insert a completed altar with location_kind='settlement_poi'; verify the linked religious_site flips tier to 'temple').
- `tests/test_event_bus_new_signals.gd` — verifies signal declarations match the contract (signal-emit-and-receive sanity check).

**Acceptance criteria:** Migration applies cleanly, all CHECK constraints reject invalid inserts, triggers fire correctly, EventBus emits and receives all eight signals with correct parameter types.

### 13.2 Stage B — SettlementGrowthResolver + monthly tick wiring

**Goal:** Settlements grow in `urban_families` from urban_investment; market_class re-derives; the new resolver fires once per month. POIs do NOT emerge yet (Stage C).

**Files to create:**
- `engine/subsystems/settlements/settlement_growth_resolver.gd` — implements §6.2 EVALUATE_GROWTH + EVALUATE_CLASS. Per Q-UGS-15, this is a **separate resolver** (sibling of `DomainGrowthResolver`), NOT a subphase of it. Public method `process_monthly_tick(settlement_id: int) -> Dictionary` returning {urban_families_delta, market_class_old, market_class_new, dissolved: bool}.
- `engine/subsystems/settlements/settlement_repository.gd` — thin CRUD wrapper over `settlement_entrances` if one doesn't already exist; otherwise extend the existing wrapper.

**Files to edit:**
- Whichever monthly-tick orchestrator exists (per `gdd-realtime-scheduler.md` / `docs/coding_conventions.md` §19) — register `SettlementGrowthResolver.process_monthly_tick` to fire during the start-of-month investment subphase per `ax_campaign_play.xml:9-12`, AFTER `DomainGrowthResolver` (so the domain's investment_cp is consumed first, then the settlement growth uses what's allocated to it). Cross-coordinate with the existing `OverseeInvestmentHandler` to ensure settlement-level urban_investment_cp is read correctly.

**Math per §6.2:**
1. Read `domains.pending_investment_cp` allocated to this settlement (or `settlement_entrances.investment_cp` field if added).
2. Convert to gp; roll 1d10 per 1000gp; sum and add to `urban_families` per `acore_axioms_strongholds_and_domains.xml:653`.
3. Population growth dice: 2 × (1d10 per 1000 urban_families, rounded up), with exploding-10s. Net delta to urban_families per `acore_axioms:650`.
4. Random growth: +1d10 − 1d10 per `ax_campaign_play.xml:14`.
5. Cap urban_families per the maximum-population-by-total-investment table at `acore_axioms:641-648`.
6. Dissolution check per `acore_axioms:686-689`: if urban_families < 75, dissolve.
7. Clanhold exception per `ax_domains_of_chaos.xml:32`: skip steps 1–2 for clanholds; cap at 250 urban_families and 0.125 × peasant_families.
8. Re-derive `market_class` from `urban_families` per `acore_axioms:658-664`. If changed from current `settlement_entrances.market_class`, write new value and fire `market_class_advanced` (or `_regressed`).

**Tests:**
- `tests/test_settlement_growth_resolver.gd`:
  - **Class VI → V advancement:** start with 200-family Class VI settlement, 5000gp/month urban_investment for several months; verify market_class advances to V exactly when urban_families crosses 250.
  - **Population growth dice:** mock RNG, verify the 2×1d10/1000 formula applies correctly across multiple months.
  - **Random growth:** mock RNG, verify ±1d10 applies.
  - **Dissolution:** start with 80-family settlement, force urban_families to drop below 75 (negative random growth + pillage event), verify dissolution + `settlement_dissolved` signal + urban_families returned to peasant_families in adjacent hexes.
  - **Clanhold exception:** settlement on a clanhold-style domain receives 10000gp/month investment but urban_families does NOT grow (steps 1–2 skipped); cap at 250 enforced.

**Acceptance criteria:** Settlements grow, advance class, and (rarely) dissolve correctly per RAW math. Monthly tick orchestration fires the resolver in the right order. Signals fire on class changes.

### 13.3 Stage C — POI emergence pipeline + religion attribution + port hex predicate

**Goal:** When `market_class_advanced` fires, new POIs emerge per §6.1 pipeline.

**Files to create:**
- `engine/subsystems/settlements/poi_emergence_handler.gd` — implements §6.1 / §5.4 split / §5.5 baselines / §5.6 religion attribution / §6.3 port hex check / §6.4 gp_value formula. Subscribes to `market_class_advanced` and `settlement_dissolved` (the latter to suppress emergence).
- `engine/subsystems/settlements/poi_split_roller.gd` — pure-function implementation of the §5.4.1 split table. Public method `roll_split(K_l3_plus: int, rng: RandomNumberGenerator) -> Array[int]` returning the K_local distribution.

**Files to edit:**
- None at this stage; the handler is self-contained.

**Per-stage acceptance:**

For each `market_class_advanced` signal received:

1. Compute L3+ counts for Fighters, Clerics, Mages per §5.2 (13.6% of leveled per the Starting Cities table × class ratios per §5.2.1).
2. For each class with delta > 0 in L3+ count vs. existing POIs, roll the §5.4 split.
3. For each new POI in the split:
   - Compute K_local from split.
   - For religious_sites: attached_religion per §5.6 algorithm.
   - For workshops: roll §6.3.1 d20 table.
   - For ports: call `gdd-terrain-system.md`'s `terrain_hex_has_water_access(map_id, hex_q, hex_r)` predicate (Q-UGS-49 same-hex-only); skip port if false. If true, no further sub-roll; just create the port row.
   - Compute gp_value per §6.4 formula.
   - INSERT settlement_pois row with builder_kind='emergent', emerged_via='class_advancement'.
4. For baseline shrines / named taverns / workshops / ports per §5.5: compute delta against existing baseline counts, emerge missing POIs.
5. Fire `poi_emerged` per row.

**Tests:**
- `tests/test_poi_emergence.gd`:
  - **Class VI → V emerges baseline:** advancement triggers emergence of §5.5 baselines (shrines, named tavern, etc.); verify exact count matches the §5.5 table.
  - **Class IV split rolls produce K_local distribution:** mock RNG, advance to Class IV with 14 L3+ Fighters; verify the d6 roll produces N mercenary_guild_halls with the expected K_local split per §5.4.1.
  - **Religion attribution:** advance a domain with `effective_religion='lawful_silver_lady'`; verify 90% of emergent religious_sites have attached_religion='lawful_silver_lady' (sample size 100 rolls).
  - **Port hex predicate:** mock `terrain_hex_has_water_access` to return true for hex (5,5) and false for hex (6,6); advance two settlements (one in each hex) past the baseline-port threshold; verify only (5,5) emerges a port.
  - **No re-emergence when class doesn't change:** trigger `market_class_advanced` with old_class == new_class; verify no POIs emerge.
  - **§6.4 gp_value math:** Class III mid temple (K_local=3) → 1000 × 1.5 × 2.0 = 3000gp; verify the row's gp_value matches.

### 13.4 Stage D — BaselineNpcStocker + within-band level elevation

**Goal:** Newly-emerged POIs get baseline NPC stocking. L3+ NPC head + adherents are real character rows with `npc_role='baseline_placeholder'` and `home_poi_id` set. Within-band level elevation per §5.2.2 applies.

**Files to create:**
- `engine/subsystems/settlements/baseline_npc_stocker.gd` — subscribes to `poi_emerged`. For each new POI, generates the head NPC + K_local-1 adherents per §7.3 stocking tables. Applies §5.2.2 elevation roll. Writes to `characters` table.
- `engine/subsystems/settlements/level_elevation_roller.gd` — pure function implementing §5.2.2 recursive-halving level-up roll. Public method `apply_elevation(base_level: int, band_progress: float, rng: RNG) -> int`.

**Files to edit:**
- None at this stage.

**Per-stage acceptance:**

1. Subscribe to `poi_emerged`.
2. For each new POI, read K_local from the row.
3. Generate head NPC + K_local-1 adherents per §7.3:
   - Class per POI type (Cleric for religious_site, Mage for mages_guild_hall, etc.).
   - Alignment per attached_religion or default.
   - Name from cultural name bank.
   - Standard rolled stats.
   - `npc_role = 'baseline_placeholder'`, `home_poi_id = <this POI>`.
4. For each generated NPC, apply §5.2.2 elevation roll using the settlement's current `band_progress`.
5. Persist all character rows. Update POI's `baseline_head_npc_character_id` to the head's id.
6. Fire `poi_stocked` per POI.

**Tests:**
- `tests/test_baseline_npc_stocker.gd`:
  - **K_local=1 stocks one head NPC:** advance Class V settlement; emergent religious_site at K_local=1 gets one Cleric, no adherents.
  - **K_local=3 stocks head + 2 adherents:** emergent temple at K_local=3 gets head Cleric at base_level + 2 adherent Clerics at decreasing levels (floor L3).
  - **Within-band elevation at band_progress=1.0:** mock RNG to always succeed; verify NPCs get +1, +2, +3 levels (recursive halving stops at first fail; full chain at all-success).
  - **Within-band elevation at band_progress=0.0:** verify no NPCs get elevation.
  - **home_poi_id set correctly:** all generated character rows have home_poi_id pointing at the POI.
  - **npc_role correct:** all generated rows have npc_role='baseline_placeholder'.

### 13.5 Stage E — PoiContributionRegistry + religion-conversion wire-up

**Goal:** The §8 registry is implemented; religion-conversion consumes §8.3.1 helper.

**Files to create:**
- `engine/subsystems/settlements/poi_contribution_registry.gd` — static class with all §8.3 / §8.4 / §8.5 helpers. Per Q-UGS architecture concern: this is a static class (not autoload) hosted in the settlements subsystem directory.

**Files to edit:**
- `engine/subsystems/domains/religion_conversion_resolver.gd` (assuming this name from `gdd-religion-conversion.md` Phase 11D.3 work) — replace the consecrated-altars-only `religious_structures_gp_value_for_domain` body with a call into `PoiContributionRegistry.religious_structures_gp_value_for_domain(domain_id, religion)`. The registry's SQL per §8.3.1 sums temple+shrine gp_values + attached altar gp_invested.

**Per-stage acceptance:**

Implement these methods per §8.3 / §8.4 / §8.5:

- `religious_structures_gp_value_for_domain(domain_id: int, religion: String) -> int` per §8.3.1.
- `specialist_availability_for_settlement(settlement_id: int, kind: String) -> bool` per §8.3.2 (extended with port + tavern routing per v1.8).
- `mages_guild_hall_count_for_realm(realm_id: int) -> int` per §8.3.4.
- `available_spellcasting_services_at_poi(poi_id: int) -> Array[SpellOffer]` per §8.5.2 (defer to Stage G for the body; stub returns empty list here).
- Forward-compat stubs per §8.4 (all return 0 / empty).

**Tests:**
- `tests/test_poi_contribution_registry.gd`:
  - **Empty domain returns 0:** `religious_structures_gp_value_for_domain` on a domain with no temples returns 0.
  - **Temple + altar sum:** create a domain with 1 temple (gp_value=3000, attached_religion='X') and 1 attached consecrated_altar (gp_invested=2000); registry returns 5000 for religion='X' and 0 for religion='Y'.
  - **Shrine counts too:** create a domain with 1 temple (gp_value=3000) + 1 shrine (gp_value=300), both religion='X'; registry returns 3300.
  - **Specialist routing:** workshop hosts alchemist → `specialist_availability_for_settlement(s, 'alchemist')` returns true; mercenary_guild_hall hosts → query for 'mercenary_officer_captain' returns true; port hosts → query for 'mariner_navigator' returns true.
- `tests/test_religion_conversion_wire_up.gd`:
  - **Pre-this-GDD vs post:** religion_conversion_resolver's monthly tick produces the same congregant growth as before when no temples exist; produces additional growth when temples are added.

### 13.6 Stage F — Stronghold registration + Q-UGS-30 altar handling

**Goal:** Player-built strongholds register settlement_pois rows; grant/purchase exception transfers existing altars.

**Files to edit:**
- `engine/subsystems/strongholds/stronghold_completion_handler.gd` (or equivalent, per `gdd-stronghold-construction.md`) — on stronghold completion sited in a settlement hex, INSERT a settlement_pois row with:
  - `type` mapped per §12.4: Cleric/Bladedancer/Shaman fortified-church → `religious_site` with `tier='shrine'` (Q-UGS-30: NO implicit altar); Mage L9 sanctum → `mages_guild_hall`.
  - `builder_kind='character'`, `builder_character_id = <PC's character_id>`.
  - `gp_value = stronghold.gp_value`.
  - `emerged_via = 'stronghold_register'`.
  - Update `strongholds.registered_settlement_poi_id` to the new POI's id.
- **Grant/purchase path** (per `gdd-stronghold-construction.md` grant/purchase mechanics, if those exist): when a stronghold is transferred from a prior owner, the prior `consecrated_altars` rows whose `location_kind='settlement_poi'` and `location_ref=<prior owner's settlement_pois.id>` are reassigned to the new settlement_pois.id. The §11.4 trigger then flips tier='temple' automatically.

**Tests:**
- `tests/test_stronghold_registration.gd`:
  - **New fortified-church stocks as shrine:** Cleric L9 builds a 75000gp fortified church in a Class IV settlement; verify settlement_pois row created with type='religious_site', tier='shrine', gp_value=75000, builder_kind='character', no consecrated_altars row auto-created.
  - **Consecrate altar promotes:** Cleric L5+ runs `consecrate_altar` activity targeting the new fortified-church POI; verify consecrated_altars row inserted; verify §11.4 trigger fires; verify POI's tier flips to 'temple'.
  - **Grant transfer:** simulate stronghold transfer (the test scaffolds the grant directly via SQL since stronghold-construction's grant flow may not exist yet); verify consecrated_altars location_ref reassigned; verify new POI's tier becomes 'temple' if the altar's status='completed'.
  - **No L3+ count subtraction:** Cleric-ruled Class IV town with the stronghold-registered fortified-church still emerges its full §5.4-distributed religious_sites cohort (per Q-UGS-5 / Q-UGS-22).

### 13.7 Stage G — Spellcasting services full implementation

**Goal:** §8.5 daily-roll mechanic works end-to-end. Players can purchase castings.

**Files to create:**
- `engine/subsystems/spellcasting_services/spell_offer_roller.gd` — pure-function implementation of the RAW dice rolls per `acore_equipment.xml:980-990`. Public method `roll_offers_for_settlement(market_class: int, has_religious_sites: bool, has_mages_guild_halls: bool, rng: RNG) -> Dictionary` returning per-(tradition, spell_level) counts.
- `engine/subsystems/spellcasting_services/spell_offer_repository.gd` — CRUD wrapper for `settlement_poi_spell_offers`. Lazy-init `get_or_roll_offers_for_poi(poi_id, calendar_day)` per §8.5.2 / §8.5.5.
- `engine/subsystems/spellcasting_services/purchase_spellcasting_handler.gd` — implements §9.4 action flow. Public method `try_purchase(poi_id, tradition, spell_level, spell_name, payer_character_id) -> Dictionary` returning {success, error_code, …}.
- `engine/subsystems/spellcasting_services/spell_alignment_gate.gd` — pure-function implementation of §8.5.3 alignment table.

**Files to edit:**
- `engine/subsystems/settlements/poi_contribution_registry.gd` — flesh out `available_spellcasting_services_at_poi(poi_id)` per §8.5.2 (calls spell_offer_repository.get_or_roll).
- Settlement Exploration UI (per `gdd-settlement-exploration-ui.md`) — add "Purchase Spellcasting Services" menu item to religious_site and mages_guild_hall POI menus. On selection, query offers, render menu with alignment grey-out, dispatch purchase_spellcasting_handler.try_purchase on confirm.
- `engine/autoloads/party_wallet.gd` (or equivalent) — purchase deducts gp.
- Existing spell system (`gdd-spell-system.md` infrastructure) — resolve the actual cast.

**Per-stage acceptance:**

1. First visit to a POI on a new calendar day triggers `spell_offer_repository.get_or_roll_offers_for_poi`, which checks for existing rows; if none, rolls RAW dice and INSERTs.
2. Same-day re-visits use existing rows.
3. UI displays offers; alignment grey-out applies per §8.5.3.
4. Player selects offer + specific spell from spell catalog → handler validates alignment, checks count_remaining > 0, deducts gp, decrements count_remaining, resolves spell, emits `spellcasting_service_purchased`.

**Tests:**
- `tests/test_spell_offer_roller.gd`:
  - **Class III city rolls:** mock RNG to specific values, verify Divine 1st = 5d10 produces the expected count, Arcane 6th = 1d2-1 produces 0 or 1, etc.
  - **Class VI excludes high levels:** Class VI village rolls produce 0 for Divine 3rd+ and Arcane 3rd+ (RAW dashes).
- `tests/test_spell_alignment_gate.gd`:
  - **Each cell in the §8.5.3 table:** 9 buyer/caster alignment combinations, verify allow/reject per the table.
  - **Arcane is unconditional:** any alignment combo for arcane returns allow.
- `tests/test_purchase_spellcasting.gd`:
  - **Successful purchase:** Class III city, lawful party visits a lawful religious_site, buys Divine 1st @ 10gp; verify gp deducted, count_remaining decremented, signal emitted.
  - **Alignment rejection:** chaotic party tries to buy from lawful religious_site; verify rejection, no gp deduction.
  - **Sold-out rejection:** the only Divine 5th casting is purchased; second attempt rejected with `count_remaining == 0`.
  - **Multi-POI split:** Class III city with 2 religious_sites at gp_value 4500 and 9000 rolls 25 Divine 1st castings; verify 17 at the big temple and 8 at the small.
  - **Daily refresh:** advance calendar_day by 1; first visit triggers new roll; counts reset.
  - **High-level scroll assumption:** Class III city rolls 1 Arcane 6th-level available; resident mage is L6 (can't cast 6th); purchase still succeeds (system assumes scroll/item).

### 13.8 Stage H — stock_poi / unstock_poi decrees + cleanup paths + Settlement UI integration

**Goal:** Player can bind/release characters to POIs. Cleanup runs for on_demand NPCs and old spell-offer rows. Abandoned POIs show "No one here, leave."

**Files to create:**
- `engine/subsystems/activities/handlers/decrees/stock_poi_decree.gd` — implements §7.2 Stock POI decree.
- `engine/subsystems/activities/handlers/decrees/unstock_poi_decree.gd` — releases stocked character; reverts POI to baseline.
- `engine/subsystems/settlements/poi_cleanup.gd` — implements Q-UGS-58 (party-departure + session-boundary on_demand cleanup) and Q-UGS-57 (settlement_poi_spell_offers 7-day retention).
- `engine/subsystems/settlements/character_retention_helper.gd` — implements `is_character_retained(character_id) -> bool` consulting henchman_lifecycle, quest_rumors, etc. per Q-UGS-58.

**Files to edit:**
- Settlement Exploration UI — wire stock_poi action; show "No one here, leave" for POIs where stocked_character_id AND baseline_head_npc_character_id are both NULL (Q-UGS-4); add decree picker for Stock POI / Unstock POI on appropriate POIs.
- Some session-boundary hook (per `gdd-realtime-scheduler.md`) — fire `poi_cleanup.session_boundary_sweep()`.
- Some party-departure hook (per `gdd-settlement-exploration-ui.md` exit-settlement flow) — fire `poi_cleanup.party_departure_sweep(settlement_id)`.
- Daily-tick hook — fire `poi_cleanup.spell_offers_retention_sweep()` (7-day delete).

**Tests:**
- `tests/test_stock_poi_decree.gd`:
  - **Stock cleric into temple:** PC ruler has a L7 Cleric henchman; issues stock_poi targeting a temple in their domain; verify `stocked_character_id` set, `poi_stocked` signal fires.
  - **Validation rejects non-divine for temple:** PC tries to stock a Fighter henchman into a temple; verify rejection with appropriate error.
  - **One character per POI:** PC stocks character A into temple X, then character A into temple Y; verify temple X's stocked_character_id becomes NULL.
- `tests/test_poi_cleanup.gd`:
  - **on_demand cleanup at party departure:** generate an on_demand NPC via `gdd-settlement-stocking.md` on-contact; party leaves settlement without retaining; verify the row is deleted on next departure-sweep.
  - **Retained on_demand survives:** generate on_demand NPC, hire as henchman (creates henchman_lifecycle row), party leaves; verify the character row persists with `npc_role='henchman'`.
  - **session-boundary fallback:** simulate a save/crash mid-visit with on_demand NPCs lingering; trigger session-boundary sweep; verify cleanup.
  - **Spell offers 7-day retention:** create offers with calendar_day = today-8; run retention sweep; verify deletion. Offers with calendar_day = today-6 preserved.
- `tests/test_abandoned_poi_ui.gd`:
  - **No-one-here:** POI with both stocked_character_id and baseline_head_npc_character_id NULL renders the "No one here, leave" menu.

### 13.9 Cross-cutting validation

**Banker's rounding audit (Q-UGS-19):** at implementation time, sweep §5.4, §5.5, §5.6, §5.8, §6.4, §8.5.2 for any rounding calls; ensure they use banker's rounding (`stepify(x, 1.0)` with custom half-to-even, or a project utility per `docs/coding_conventions.md`). Failure mode is silent — a wrong rounding mode produces subtly biased emergence counts.

**Integration test — full month tick:**
- `tests/test_full_month_tick_urban_growth.gd`:
  - Set up a Class V settlement, 250 urban_families, 5000gp/month urban_investment, lawful domain with `effective_religion='lawful_silver_lady'`.
  - Run 12 monthly ticks.
  - Verify: urban_families grows roughly linearly; market_class advances to IV when crossing 625 families; on advancement, religious_sites and mercenary_guild_halls and possibly mages_guild_halls emerge per §5.4; baseline shrines and named taverns appear per §5.5; all newly-emerged POIs have head NPCs stocked with home_poi_id pointing back; religious_structures_gp_value_for_domain reports the expected sum for the religion.

### 13.10 Stage sequencing summary

```
A (schema + signals) ── must complete first
   │
   ├──> B (growth resolver)         ── needs schema, fires market_class_advanced
   │       │
   │       └──> C (emergence)        ── subscribes to market_class_advanced
   │              │
   │              └──> D (stocking)  ── subscribes to poi_emerged
   │
   ├──> E (registry + religion wire-up)  ── independent of B/C/D for read; full test needs C/D done
   │
   ├──> F (stronghold registration)  ── needs schema, can land anytime after A
   │
   ├──> G (spellcasting services)    ── needs E for the registry helper + schema for spell_offers
   │
   └──> H (decrees + cleanup + UI)   ── needs A through G

A typical session-or-two scope: A + B + C + D for the growth/emergence/stocking core.
The remaining stages (E + F + G + H) are smaller follow-up sessions.
Total: 4–6 build sessions depending on test depth.
```

---

## 14. Open Questions / Architectural Concerns

### Resolved in v1.1 refactor

- ~~**Q-UGS-1: Per-class POI budget calibration.**~~ **RESOLVED.** Replaced the project-designed budget table with the §5.1–§5.5 reverse-engineered procedure based on the Starting Cities table at `acore-setting-construction-rules.xml:496-519`. Calibration anchors are now RAW, not intuition.

- ~~**Q-UGS-8: Public sanctum emergence at Class II / I.**~~ **RESOLVED FURTHER in v1.3** per Jedidiah 2026-05-22: "In most published modules, class IV cities have small sanctums, I am not sure where the class II and better restriction comes from. It needs to be relaxed. … Get [the `7 - market_class` rule] out of our stocking rules." v1.3 actions taken: (1) removed the v1.2 paragraph "Class VI base-level cap" from §5.2 that mis-applied `acore-monster-stocking-rules.xml:471` (which governs random NPC-party encounters, not resident NPC stocking). (2) Changed the POI-anchor threshold from L5+ to L3+ in §5.2 so Class IV cities now have 3 L3+ mages → 1–3 sanctums per the §5.4 split. (3) Updated the §5.4.2 worked example to show Class IV large town has small sanctums by default. (4) Acknowledged in §5.2 that the level distribution applies regardless of market class — a Class VI village can have a high-level cleric or mage, just rarely, per the recursive-halving curve. Q-UGS-8 is closed.

- ~~**Q-UGS-11: Library access for itinerant casters.**~~ **OBSOLETE in v1.4.** v1.2/v1.3 tried to model library access via POI library_value allocations; v1.4 removes that entirely. Itinerant-caster library access is now `gdd-magical-research`'s problem to design from scratch — likely via player-stronghold libraries plus some visiting-researcher mechanism not specified here.

- ~~**Q-UGS-20: Filename.**~~ **CONFIRMED** as `gdd-urban-growth-stocking.md` per the user's original suggestion.

- ~~**Q-UGS-25: Has-library probability for sanctums.**~~ **OBSOLETE in v1.4.** Library/workshop allocations removed entirely from this GDD.

- ~~**Q-UGS-31: Mage stronghold-sanctum library default.**~~ **OBSOLETE in v1.4.** `gdd-stronghold-construction.md` owns the question.

### Active Q-UGS items

- ~~**Q-UGS-2: Hostile temples in conquered domains.**~~ **RESOLVED (option b)** per Jedidiah 2026-05-22. When a chaotic conqueror takes a lawful domain, existing lawful-religion religious_sites remain `status = 'active'` until the religion conversion completes and the ruler decides what to do with them. No immediate auto-abandonment. The ruler may later issue a player action (deferred to v2 per Q-UGS-6) to demolish or convert; in v1 the sites persist contributing to their original religion's proselytizing pool, which creates intentional friction during the religion-conversion arc.

- ~~**Q-UGS-3: Baseline NPC character record granularity.**~~ **RESOLVED (full rows + rename)** per Jedidiah 2026-05-22. Baseline-stocked NPCs are full `characters` rows with class, level, stats, alignment, charisma — preserving forward-compatibility with the faction system and rich NPC interactions. Save-data weight is acceptable. The `stocked_cleric_character_id` column is renamed to `stocked_character_id` in v1.3 (§11.1, §11.2, §7.2). The `gdd-religion-conversion.md` §9.8 contract needs a one-line update to use the new name when this GDD's schema lands.

- ~~**Q-UGS-4: Settlement downgrade POI handling.**~~ **RESOLVED (POI remains, NPCs leave)** per Jedidiah 2026-05-22. When `urban_families` drops and the POI's L3+ NPC anchors leave (no remaining matching-class NPCs at the L3+ threshold), the POI row remains in `settlement_pois` with `status = 'abandoned'` and `stocked_character_id = NULL` and `baseline_head_npc_character_id = NULL`. The Settlement Exploration UI replaces the POI's normal menu with a single option: **"There is no one here: leave."** This preserves the POI's historical presence (the building still stands) without forcing demolition. POIs do not auto-demolish; they simply become uninhabited venues. Future v2 work may add a "reclaim abandoned POI" player action.

- ~~**Q-UGS-5: Player strongholds counting toward target.**~~ **RESOLVED (no count, no suppress)** per Jedidiah 2026-05-22. Strongholds do NOT count toward the §5.4 K split and do NOT suppress emergent POIs. A Cleric-ruled domain visibly has MORE clerics than the same-class non-Cleric-ruled domain: the stronghold's clerics are in *addition to* the emergent temples' clerics. This makes the ruler's class visibly shape the settlement's character — a feature, not a balance flaw. §5.3 and §12.4 are updated in v1.3 to reflect this resolution.

- **Q-UGS-6: Player-driven temple replacement.** *Deferred per Jedidiah 2026-05-22: "defer for now, but it will be wanted before product launch."* No v1 mechanic to convert an existing emergent religious_site of religion A to religion B; the conversion arc resolves it implicitly via the §5.6 80/20 attached-religion bias over many growth events. A "Re-consecrate Religious_Site" or "Reclaim Abandoned POI" decree is on the v2 punch-list (between v1 and product launch) per Jedidiah's note. Q-UGS-2's option-(b) resolution depends on this being delivered eventually — a chaotic conqueror should ultimately be able to clear out the prior religion's sites rather than waiting for them to attrite naturally.

- ~~**Q-UGS-7: Clanhold POI scale and minimum shrine.**~~ **RESOLVED (keep the shrine for Shaman)** per Jedidiah 2026-05-22. Every settlement above the 75-family founding threshold retains at least 1 baseline shrine (§5.5) so a Shaman has a venue. Beastman clanholds at Class VI still have a shamanic ritual ground modeled as a religious_site (shrine tier). §5.5's Class VI = 1 minimum is the implementation. The shrine IS the shamanic ritual ground in mechanical terms; in narrative terms it can be an open-air stone circle or a chieftain's hut altar rather than a building, but the row exists in the schema regardless.

- **Q-UGS-8: Public sanctum emergence at Class II / I.** §5.1 lists 1 sanctum at Class II and 2 at Class I. Should v1 ship without sanctum emergence at all, deferring all sanctum work to player-built Mage strongholds? Counterpoint: a non-Mage Class II city without an mages' guild hall feels under-furnished. Recommend keep §5.1 as drafted; the sanctum's mechanical effect (registry helper §8.3.4) is stubbed and harmless.

- **Q-UGS-9: gp_value formula calibration.** *Further considered in v1.8* per Jedidiah 2026-05-27: "I am wondering if there is any other reason to track GP value of other POIs? If not, then I would propose reworking the religious conversion mechanic ... from a GP-based driver to an NPC cleric-level based driver, which would serve as a rough correlation." Status: gp_value remains in v1 because (a) §8.3.1 religion-conversion contract already consumes it, (b) it serves as a useful narrative-description scale ("the cathedral is worth 4,500gp" → LLM can render "a substantial city church with a marble facade and bronze doors"), and (c) the §6.4 size_multiplier from K_local already encodes the "rough correlation" with NPC cleric levels the user describes. The v1.3 recalibration (temple base 1000, building-only framing) stands. **The cleric-level-based driver alternative is flagged as Q-UGS-48 (new) for v2 consideration** — a post-playtesting decision to make once we see whether the gp-based driver produces sensible conversion timelines or feels disconnected from the visible cleric roster.

- **Q-UGS-10: Player commission / demolition of POIs.** *Deferred per Jedidiah 2026-05-22 ("defer these till we have the rest working").* Growth events and player strongholds remain the v1 levers for adding POIs to a settlement; the POI Patronage system (Q-UGS-35) is the eventual customization vehicle. Demolition is not in v1. Revisit after end-to-end basic systems work.

- **Q-UGS-11: Library access for itinerant casters.** A character researching magic in a city visits the library. RAW per `acore_campaign_classes.xml`'s research rules ties libraries to the *character's* sanctum (a personal asset). The public library in this GDD is a settlement asset. Does the public library provide a discount or assistance to any character researching in the settlement, or only to the stocked character? Recommend: public library provides a flat 10% discount (project-designed) to any character researching in the settlement, capped at 1 per domain to prevent stacking. Flagged for the magical-research GDD author.

- **Q-UGS-12: Future `merchant_guild_hall` POI type.** v1.1 removed the v1.0 `guildhouse` type. A future extension could introduce a `merchant_guild_hall` POI driven by Thief / Venturer demographics (extending the §5.4 splitting pattern). If added, it would interact with merchant-pool sizing (e.g., +1 merchant slot per merchant_guild_hall). Defer to a v1.2 scope decision.

- ~~**Q-UGS-13: Faction forward-compatibility column placement.**~~ **RESOLVED in v1.11** per Jedidiah 2026-05-30 ("keep"). `settlement_pois.owner_faction_id` ships in the v1 migration as a nullable INTEGER. v1 sets it to NULL on all rows (= "the realm"); Phase 12 faction work assigns non-NULL values without a follow-up migration.

- ~~**Q-UGS-14: Table naming — `settlement_pois` vs. extending `pois`.**~~ **RESOLVED in v1.11** per Jedidiah 2026-05-30 ("Keep it separate, do not mix with the wilderness POI table"). `settlement_pois` is its own table, distinct from the existing `pois` table (migration 050). The two tables share a conceptual word ("POI") but have different lifecycles, different consumers (settlement-interior growth events vs. wilderness discovery), and different columns. The Settlement Exploration UI may UNION both when assembling a visitable-locations list per §4.3, but the underlying storage stays disjoint.

- ~~**Q-UGS-15: Settlement growth resolver placement.**~~ **RESOLVED in v1.11** per Jedidiah 2026-05-30 ("separate resolver"). The §6.2 growth math (urban_families mutation, market_class re-derivation, dissolution check, clanhold exceptions) lives in a dedicated `SettlementGrowthResolver` at `engine/subsystems/settlements/settlement_growth_resolver.gd`. It runs as a sibling of `DomainGrowthResolver` in the monthly tick (`docs/coding_conventions.md` §19 EventScheduler pattern), invoked by the same start-of-month phase but with its own resolver class so the file doesn't bloat the domain resolver. Confirmed for implementation.

- **Q-UGS-16: Player commission of POIs.** Related to Q-UGS-10. Should a ruler be able to spend gp during the ax_campaign_play.xml:589-604 "Order construction" decree to commission a POI directly (a temple at Class V cost = the §6.4 gp_value = 1875gp)? Counterpoint: this duplicates the stronghold-construction flow and creates a balance question (can a player short-circuit class advancement by buying enough emergent POIs to make a Class VI settlement "feel" like Class V?). Recommend defer to v2.

- ~~**Q-UGS-17: `builder` field format.**~~ **RESOLVED in v1.10** per Jedidiah 2026-05-29 (chose recommendation). §11.1 splits the v1.0–v1.9 string `builder` field into two typed columns: `builder_kind TEXT CHECK ('emergent', 'character')` and `builder_character_id INTEGER REFERENCES characters(id)`. CHECK constraint enforces (kind, id) consistency. All in-text references updated to the new format.

- **Q-UGS-18: NPC realm AI stocking.** §12.7 notes NPC realms do not issue Stock POI decrees. Future Phase 12+ work may add a "realm AI ranks its temples and stocks the best with named clerics" behavior so rival realms compete with PCs. Document only; no v1 implementation.

- **Q-UGS-19: Banker's rounding placement.** §6.4 specifies banker's rounding for multiplication; §5.4 specifies banker's rounding for halving in clanholds. Both follow project convention. The §7.3 "1 + class offset" level calculation is integer arithmetic (no rounding needed). Confirm no other rounding sites missed.

- **Q-UGS-20: Naming the file.** Filename is `gdd-urban-growth-stocking.md` per the user's suggestion. Alternative: `gdd-settlement-poi-emergence.md` (more accurately scoped — the GDD covers more than stocking; emergence is the core mechanic). Confirm naming.

- **Architectural concern — interface ownership for `PoiContributionRegistry`.** This GDD asserts the registry as a centralized helper. The architectural alternative is per-consumer JOIN (each consumer GDD writes its own SQL against `settlement_pois`). Centralized is preferred (§8.1 rationale) but creates an autoload / static-class question. The autoload approach risks proliferating autoloads against `CLAUDE.md`'s "do not proliferate autoloads" rule. Recommend static class (non-autoload) hosted in `engine/subsystems/settlements/poi_contribution_registry.gd` and called via class name like the existing `RealmRepository` pattern.

- **Architectural concern — overlap with `gdd-settlement-stocking.md`.** The existing settlement-stocking GDD says "growth creates the spatial POI slots; stocking-GDD fills them on contact." This new GDD adds non-spatial POI emergence — POIs that have a district affinity but no rendered spatial location. The seam is clean for v1 but creates a v2 question: when the settlement-layout GDD's v2 (spatial regeneration on class advance) lands, this GDD's POIs need to be assigned to spatial slots. Flag for the layout-v2 work.

- **Architectural concern — `feedback_paladin_anti_paladin_not_divine_casters.md` compliance.** §7.2 explicitly excludes Paladin / Anti-Paladin from divine-caster validation for temple stocking. Document confirms compliance.

- **Architectural concern — `feedback_acks_kin_terminology.md` compliance.** §10.1 distinguishes beastman clanholds (Shaman-led temples) from kin clanholds (standard temple roster). The vocabulary throughout uses "beastman" and "kin" per the memory.

### New Q-UGS items from v1.1 refactor

- ~~**Q-UGS-21: Level-distribution curve calibration.**~~ **RESOLVED in v1.7** per Jedidiah 2026-05-26. The criminal-guild distribution analogue with recursive halving in the L3+ tail is confirmed as the v1 baseline curve, applied uniformly across all four leveled-NPC classes (Fighter / Thief / Cleric / Mage). Cross-class variance is captured by the RAW 4:2:2:1 ratio (documented in new §5.2.1), not by per-class curve differences. Within-band variance is captured by the new §5.2.2 elevation roll (per L3+ NPC level-up rolls keyed to band_progress with recursive-halving chance). The two new sections fully address the original Q-UGS-21 concern about whether the curve is right; the curve plus 4:2:2:1 plus elevation roll yields a distribution that matches the user's stated intuition ("more leveled fighters in a town than thieves, as many thieves as there are clerics, and fewer mages than clerics or thieves") and produces meaningful between-settlement variance.

- ~~**Q-UGS-22: NPC ruler stronghold consumption of L3+ slots.**~~ **RESOLVED in v1.11** per Jedidiah 2026-05-30 ("Do whatever is cleaner, 1 character won't make or break anything"). The cleaner answer is **no subtraction** — the NPC ruler exists in PARALLEL to the §5.4-distributed L3+ NPCs. This is consistent with the v1.3 Q-UGS-5 resolution (strongholds don't subtract or suppress) and produces the intended "ruler's class visibly affects settlement character" effect: a Cleric-ruled Class III city has its L10 cleric ruler PLUS the full §5.4-distributed cleric cohort. The 1-character delta the v1.0 design worried about is acceptable.

- ~~**Q-UGS-23: Baseline shrine counts at low classes.**~~ **RESOLVED** per Jedidiah 2026-05-27: "we don't need 64 shrines in a Class I, that is no longer a POI that's just scenery." Confirmed the §5.5 sub-linear baseline (Class I = 10 shrines, with v1.7's Q-UGS-7 bump making Class VI = 1). The "1 shrine per 25 clerics" alternative (which would yield 64 shrines at Class I) is rejected — at that density shrines stop being individually addressable POIs and become urban scenery. The Q-UGS-7-driven minimum-of-1 at Class VI (so a Shaman has somewhere to be found) is the floor; the top end at Class I = 10 named-landmark shrines is the cap. Background non-POI religious-flavor presence (corner shrines, household altars, statues in marketplaces) is settlement-stocking-on-contact content per `gdd-settlement-stocking.md`, not this GDD's responsibility.

- ~~**Q-UGS-24: Class advancement absorb vs. re-split.**~~ **RESOLVED** per Jedidiah 2026-05-27: "80/20 is a good starting point to test it out. We can recalibrate after playtesting. The exact balance is flavor and taste, and we may end up having different rates for different POI types per culture." Confirmed v1 default. v2 candidate: per-culture absorb/re-split rates (a stable-society culture biases toward absorb; an entrepreneurial-society culture biases toward re-split). Flagged as part of the broader cultural-variance work, no separate Q-UGS needed.

- ~~**Q-UGS-25: Has-library probability for sanctums.**~~ **OBSOLETE in v1.4** — library subsystem removed.

- ~~**Q-UGS-26: Spell Availability by Market table is missing.**~~ **RESOLVED in v1.9** per Jedidiah 2026-05-28. The table was located at `acore_equipment.xml:979-991` (not at the `ax_campaign_play.xml:405` cross-reference earlier-version citations pointed at — that's just the pointer). v1.9 §8.5 implements the full query against the RAW table; §11.4a adds the `settlement_poi_spell_offers` schema; the surface is no longer a stub.

- **Q-UGS-27: Civic POIs.** §4.3 excludes government / authority buildings (the ruler's keep, law courts, militia barracks, tax collector's office) from settlement_pois v1, treating them as flavor extensions of the ruler's stronghold OR as on-contact stocked content. Is this the right scope, or should civic POIs land in v1.2 as a distinct type? Recommend defer to v1.2 — the religion-conversion consumer doesn't need them, and they don't fit the "leveled-NPC cohort" pattern that drives §5.

- ~~**Q-UGS-28: Adherent NPC storage shape.**~~ **RESOLVED in v1.10** per Jedidiah 2026-05-29 (chose recommendation). §11.4 migration adds `characters.home_poi_id INTEGER REFERENCES settlement_pois(id) ON DELETE SET NULL` with `idx_characters_home_poi` index for lookups. No separate adherents table; each character row knows its home POI. When the POI is deleted, the character persists with home_poi_id=NULL (becomes unanchored).

- ~~**Q-UGS-29: Existing characters table extension for placeholder NPCs.**~~ **RESOLVED in v1.10** per Jedidiah 2026-05-29 (chose recommendation — enum form). §11.4 migration adds `characters.npc_role TEXT NOT NULL DEFAULT 'player' CHECK (npc_role IN ('player', 'henchman', 'specialist', 'baseline_placeholder', 'stocked', 'named_npc', 'on_demand'))`. The enum is extensible by future faction / dynasty work without schema rewrite. `idx_characters_npc_role` partial index supports cleanup queries filtering on non-player roles.

- ~~**Q-UGS-30: Stronghold-temple implicit altar contribution.**~~ **RESOLVED in v1.10** per Jedidiah 2026-05-29 (chose option b): "No free consecrated altars unless the Stronghold already has one and is received by grant/purchase." §12.4 updated: brand-new fortified-church-strongholds register as `religious_site tier='shrine'`; player must run `consecrate_altar` explicitly to promote to temple, paying RAW costs (`ax_campaign_play.xml:411-421` — divine spellcaster L5+, 1 day per 500gp). Exception: when a stronghold is acquired by grant or purchase from a prior owner with existing consecrated_altars, those altars come with the stronghold (the §11.4 trigger handles tier reassignment when the consecrated_altars rows are reassigned to the new religious_site location_ref). This makes consecration a meaningful follow-up activity for new builds while preserving fairness for inherited/acquired strongholds.

- ~~**Q-UGS-31: Mage stronghold-sanctum library default.**~~ **OBSOLETE in v1.4** — `gdd-stronghold-construction.md` owns library decisions for strongholds; this GDD does not.

- ~~**Q-UGS-32: Workshop count vs. specialist demographics.**~~ **SUBSTANTIALLY RESOLVED in v1.8** per Jedidiah 2026-05-27. The RAW Hiring Availability by Market Class table (`acore_equipment.xml §specialists.specialist_details`, image attachment provided) enumerates 17 specialist sub-kinds with per-market-class availability dice. v1.8 redistributes these across POI types per the §4.2 specialist distribution table: workshops host alchemist/healer/animal trainer/sage; ports host mariners; named taverns host ruffians; mercenary guild halls house mercenary officers + quartermaster + siege engineer; armorer and engineer are abstracted to the management notebook hiring panel (no POI surface). The §5.5 workshop baseline counts (Class VI: 0; V: 1; IV: 2; III: 4; II: 8; I: 16) are preserved — they remain the project-designed cap on workshop POI density independent of RAW specialist counts; multiple same-type or different-type specialists may bundle into a single workshop POI at higher classes. v1.8 also introduces the `port` POI type (Q-UGS-49 flags hex-predicate implementation) and the §12.8a coordination with `gdd-management-notebook.md` (Q-UGS-50). Sub-questions about resident-vs-itinerant and per-month availability dice remain (Q-UGS-51, Q-UGS-52).

- **Q-UGS-33: Shrine promotion via 'completed' consecrated altar gp_invested threshold.** §11.4's trigger promotes shrine→temple on the FIRST `consecrated_altars` row reaching `status = 'completed'` for the POI. Should there be a minimum gp_invested threshold (e.g., 1000gp) below which the altar counts as "domestic" rather than "templar"? RAW silent. Recommend no threshold (any consecrated altar promotes) for simplicity. The §6.4 gp_value formula already weights small altars proportionally less.

- **Q-UGS-34: Adherent stocking for stronghold-temples.** §7.3's "religious_site (tier=temple)" stocker is bypassed for player-built fortified-church-strongholds — the stronghold's own follower rules apply per `gdd-stronghold-construction.md`. The RAW followers (5d6×10 0-level soldiers + 1d6 L1-L3 clerics per `acore_campaign_classes.xml:1299-1318`) are exclusive to player strongholds. Should an emergent temple with K_local=4 in a Class III city also attract a small follower cohort (1d6 L1 clerics) on emergence to mirror this? Recommend no (the §5.4 adherent count is the v1 model; RAW followers are a stronghold-only mechanism); revisit if temples feel mechanically thin.

### New Q-UGS items from v1.2 refactor

- ~~**Q-UGS-35: POI Patronage System.**~~ **OBSOLETE in v1.4** — the patronage system was justified by the library/workshop subsystem; with that subsystem removed, no v2 patronage hook is needed for this GDD. (A future GDD may still want a patronage mechanism for other reasons — e.g., letting a ruler invest in a specific religious_site's `gp_value` to boost proselytizing — but that's a separate design question not part of this GDD's scope.)

- ~~**Q-UGS-36: Workshop minimum gp value.**~~ **OBSOLETE in v1.4** — workshop subsystem removed.

- ~~**Q-UGS-37: Library-grows-from-research-success.**~~ **OBSOLETE in v1.4** — library subsystem removed.

- ~~**Q-UGS-38: Divine vs arcane access gating.**~~ **OBSOLETE in v1.4** — library/workshop subsystem removed.

- ~~**Q-UGS-39: 60,000gp librarian requirement.**~~ **OBSOLETE in v1.4** — library subsystem removed; the librarian-stocking rule is moot for this GDD. (`gdd-stronghold-construction.md` may need to handle this for stronghold libraries large enough to trigger the RAW librarian requirement.)

### New Q-UGS items from v1.3 refactor

- ~~**Q-UGS-40: Stronghold library/workshop allocation rules.**~~ **OBSOLETE in v1.4** — this GDD no longer carries library_value or workshop_value columns. Stronghold library/workshop decisions are entirely internal to `gdd-stronghold-construction.md` and the future `gdd-magical-research`; no cross-GDD coordination required at the settlement-POI layer.

- **Q-UGS-41: POI funding bookkeeping vs. abstraction.** v1.3 §6.5 explicitly states that emergent POI gp_values are *descriptive* numbers, not *accounted* line items against the settlement's `total_investment` (per `acore_axioms_strongholds_and_domains.xml:641-648`). A future v2 enhancement could change this — make POI gp_values a tracked subset of total_investment, so building a temple visibly reduces the population-cap headroom. This would require careful interaction with the urban_investment monthly subphase and the population-growth math. Recommend defer to v2 unless the religion-conversion arc requires it for balance (e.g., a chaotic conqueror "demolishing" hostile temples to free up urban_investment for new lawful temples).

- ~~**Q-UGS-42: L1–L2 NPC cohort persistence.**~~ **RESOLVED in v1.10** per Jedidiah 2026-05-29 (chose option a). §5.2 updated: L1–L2 adherents are NOT persisted as character rows at emergence time. The POI carries a `l1_l2_adherent_count` column (new in §11.1) tracking how many such adherents nominally live there. When the player interacts with a specific low-level NPC, `gdd-settlement-stocking.md`'s on-contact occupant generator materializes a character row with `npc_role = 'on_demand'` and `home_poi_id = <this POI>`, decrementing the count. If the player retains the relationship (hires, befriends, ongoing-state), the role upgrades to `'henchman'` or `'named_npc'`. If not retained, the on_demand row is eligible for session-boundary cleanup (Q-UGS-58 new).

- **Q-UGS-43: §5.4 split table tuning at high K.** The L3+ threshold change in v1.3 produces much higher K values than v1.2's L5+ threshold. A Class III city with 200 clerics now has 27 L3+ clerics (K=27) for the split, where v1.2 had K=7. The current §5.4.1 split table handles K=14+ with a single row that produces 1 to K POIs based on d6. Should the table have more granularity at K > 25 (e.g., separate rows for K=14-25, K=26-50, K=51+) to better tune the "few huge POIs vs many small" distribution at metropolitan scale? Defer to playtesting; the v1.3 single K=14+ row is a workable starting point.

### New Q-UGS items from v1.5 refactor

- ~~**Q-UGS-44: Spellcasting-services eligibility gates.**~~ **RESOLVED in v1.9** per Jedidiah 2026-05-28: "Assumptions are correct, but neutral caster will cast for anyone who pays, and lawful AND chaotic casters will cast for neutral characters." Codified in §8.5.3 alignment table: Neutral on either side allows transaction; opposite alignments (Lawful↔Chaotic) reject; same alignment allows. Arcane services have no alignment gate. RAW basis: `acore_equipment.xml:973` ("Clerics never cast spells for adventurers of opposite alignment") with the v1.9 refinement on Neutral middle-ground transactions.

- ~~**Q-UGS-45: Divine-spell preparation gating.**~~ **RESOLVED in v1.9** per Jedidiah 2026-05-28: "This is D&D assumption imports. It is also resolved by the spellcasting services rules cited above. The system will need to quietly roll which arcane spells are available on a given day when the POI is entered, refresh on Midnight tick. If a spell of a level higher than the resident NPCs can cast is rolled as 'available' we can assume it is performed via a magic item or scroll rather than gating it by NPC level." The v1.5 `immediate / next_day / unavailable_today` availability tier is dropped entirely in v1.9. Replaced by the daily-roll model in §8.5.2 + §8.5.5: roll the RAW dice once per calendar day on first POI visit, persist as `settlement_poi_spell_offers` rows; the `count_remaining` decrements on purchase. NPC-level mismatch is handled by the §8.5.6 scroll/magic-item assumption — if the dice roll a 6th-level arcane spell available in a Class III city, the offer exists regardless of resident-mage levels; the narrative explanation is scroll/item delivery.

- ~~**Q-UGS-46: Spellcasting service refusals.**~~ **OBSOLETE in v1.9** per Jedidiah 2026-05-28: "Yes but that is out of scope for now." v1 has no refusal mechanic beyond the alignment gate; if alignment matches and gp is paid, the service is rendered. Faction/reputation-driven refusals are deferred to a future system, no Q-UGS tracking needed at this layer.

### New Q-UGS items from v1.7 refactor

- **Q-UGS-47: Retroactive level elevation as the settlement grows.** §5.2.2.3 specifies that the within-band elevation roll is applied AT STOCKING TIME and locked thereafter — when the settlement's population grows and band_progress changes, existing POI NPCs are NOT re-elevated. Their levels are locked. Future v2 enhancement: periodic level-up checks for resident NPCs as the settlement crosses sub-band or class thresholds (the L4 head priest of a temple slowly becomes a L5 head priest as the city grows around the temple). v1 keeps it static to avoid retroactive disruption to player-NPC relationships, henchman state, and quest dependencies. Flagged for v2.

### New Q-UGS items from v1.8 refactor

- **Q-UGS-48: Religion-conversion driver — gp-based vs. cleric-level-based.** v1.8 retains the gp_value-based proselytizing driver in `gdd-religion-conversion.md` §5.4 and the §8.3.1 contract here. Jedidiah floated an alternative (2026-05-27): switch the driver to a function of NPC cleric levels (sum of cleric-levels at temples of the target religion in the domain), which the §6.4 size_multiplier already roughly correlates with. **The two approaches:**
  - **gp_value driver (current):** RAW-shaped per `acore-campaign-general-and-magic-research.xml:562` ("gp value of religious structures erected in the realm"). Requires this GDD to maintain gp_value as a column. Consumes §6.4's `base × market_class_multiplier × poi_size_multiplier`.
  - **cleric-level driver (alternative):** Replace the gp-based contribution with `Σ cleric_levels` across temples of the target religion. Each temple's contribution = sum of its head NPC and adherent levels (e.g., a K_local=3 temple with head L5, adherents L4 and L3 contributes 12 cleric-levels). Multiply by a project-designed gp-equivalent (e.g., 200gp per cleric-level) for the proselytizing pool integration. This GDD could then drop gp_value as a column entirely.
  - **Decision deferred to post-playtest.** Keeping gp_value in v1 is the conservative choice — it preserves the existing religion-conversion contract and provides a narrative-description scale. Switching to cleric-level-based is a v2 candidate if the gp-based driver feels disconnected from the visible cleric roster during play.

- ~~**Q-UGS-49: Port hex-predicate implementation.**~~ **RESOLVED in v1.12** per Jedidiah 2026-05-31. The predicate is **same-hex-only**: `is_river_hex(this_hex) OR is_coastal_hex(this_hex)`. Adjacency does NOT qualify ("hexes are large swathes of abstract land, if the settlement is not on the same hex, it doesn't have a river port"). All recorded rivers are navigable; small unnavigable streams are not represented on the regional map data ("if the hex has a river it is navigable"). Implementation: a single `terrain_hex_has_water_access(map_id, hex_q, hex_r) -> bool` predicate function in `gdd-terrain-system.md`'s domain, returning true iff the hex carries a `river` or `coastal` water tag. No adjacency checks. No navigability subdivision. The §6.3 emergence pipeline calls this predicate at the port-slot computation; if false, the port slot is skipped with no fallback. **Island-hex edge case:** an island hex (land hex fully surrounded by ocean) presumably carries the `coastal` tag in the terrain system; that's a `gdd-terrain-system.md` semantic, not this GDD's. If the terrain system tags it coastal, port emerges; if not, no port.

- **Q-UGS-50: Coordinate with `gdd-management-notebook.md` for Armorer / Engineer hire panel.** v1.8 routes Armorer and Engineer specialists to the management notebook (no POI surface) per §4.2 / §12.8a. The management-notebook GDD needs to add a hire-panel section that: (a) consults the RAW Hiring Availability by Market Class table for Armorer/Engineer at the settlement's market class; (b) presents a hire list with prices per `acore_equipment.xml §specialists.specialist_details`; (c) on hire-confirm, creates a `specialists` row per migration 053. This GDD does NOT define the panel — that's the management-notebook GDD's responsibility — but the coordination is flagged here so neither side ships without the other.

- **Q-UGS-51: Resident vs itinerant specialists.** v1 treats all hireable specialists per the RAW availability table as **resident** (available for hire each month, regenerated each monthly tick). A future v2 may add "itinerant specialist visits" — a famous Sage of Loremastery passes through the city for one season only, hireable during that window. Implementation would require a `specialist_visit_schedule` table tracking when notable itinerants arrive and depart, with random-rolls or LLM-driven flavor for the named visitors. Defer to v2 + cultural-variance work.

- ~~**Q-UGS-52: Lower-class settlements rolling rare workshop kinds.**~~ **RESOLVED in v1.13** per Jedidiah 2026-06-01 ("if it rolls high it rolls high, keep it"). No reroll, no downscale, no suppress. The §6.3.1 d20 roll is taken as-is regardless of market class. Rare specialist workshops in small settlements are narratively explained as outliers (the retired city Chirurgeon who moved to the village for the quiet life, etc.). The RAW availability percentages already keep these rare; further reroll over-corrects.

### New Q-UGS items from v1.9 refactor

- **Q-UGS-53: Cleric surcharge for outside-faith adventurers (RAW, deferred).** RAW (`acore_equipment.xml:974`): "Clerics may charge double if adventurers do not belong to their faith." v1.9 IGNORES this surcharge per Jedidiah 2026-05-28 — "Surcharges will be a later implementation after the full loop is confirmed working." When implemented, the §8.5.4 pricing table would expand: `unit_cost_gp × (2 if buyer.religion != religious_site.attached_religion else 1)` for divine services. This requires the buyer's character record to carry a `religion` field (per `gdd-religion-conversion.md`'s congregant model). v1.9 reads RAW base price uniformly; surcharge layers on later without schema impact (the multiplier is computed at query time from existing data).

- **Q-UGS-54: Spell levels 6+ (divine) and 7+ (arcane) availability.** The RAW Spell Availability table covers Divine 1–5 and Arcane 1–6. ACKS divine progression maxes at 7th level (Cleric L11+ ritual access); arcane progression at 9th level (Mage L11+ ritual access). v1.9 ships with high-level spells unavailable for casual hire (the table doesn't extend that far, and the implied scarcity matches in-fiction expectations — you don't walk into the Mages' Guild and pay for Disintegrate at the counter). Confirm: high-level spells are bespoke-only (player must befriend / hire an NPC of sufficient level for a specific quest); they never appear in §8.5.2's offer list. Recommend keep v1 behavior; revisit when ritual-spell infrastructure lands.

- ~~**Q-UGS-55: Settlement-wide split of rolled offers across multiple POIs.**~~ **RESOLVED in v1.13** per Jedidiah 2026-06-01 ("that formula works fine"). The §8.5.2 proportional-by-gp_value split with banker's rounding and minimum-1 per POI is confirmed as the v1 implementation. Worked example: Class III city with 2 temples (gp_values 4,500gp and 9,000gp) rolls 5d10 Divine 1st = 25 castings → 17 at the big temple, 8 at the small. Class VI village with 4 temples and 1d6 = 4 Divine 1st → 1 each via banker's distribution.

- ~~**Q-UGS-56: Ruler-domain discounts on spellcasting services.**~~ **RESOLVED in v1.13** per Jedidiah 2026-06-01 ("no ruler discount for v1"). §8.5.4 ships flat-RAW pricing for everyone — no buyer-side discount for purchasing in the ruler's own domain. The mercantile system's ruler privileges (per `gdd-phase-10b-2-trade-block.md`) do not extend to spellcasting purchases. A future v2 pass may reconsider if playtest reveals a clear need.

- ~~**Q-UGS-57: `settlement_poi_spell_offers` retention policy.**~~ **RESOLVED in v1.13** per Jedidiah 2026-06-01 ("a 7 day log is fine"). §11.4a's 7-day retention is the v1 default and is locked in. Cleanup deletes rows where `calendar_day < today - 7`.

### New Q-UGS items from v1.10 refactor

- ~~**Q-UGS-58: `on_demand` NPC cleanup policy.**~~ **RESOLVED in v1.13** per Jedidiah 2026-06-01: "a + c is fine. unnamed NPCs don't need to be kept around." Cleanup uses BOTH triggers combined:
  - **(c) Party-departure** (primary cleanup) — when the party leaves the settlement (transitions to wilderness exploration or another settlement per `gdd-settlement-exploration-ui.md`), scan `characters` for rows with `npc_role = 'on_demand'` and `home_poi_id` in this settlement's POIs, and delete any without retained-relationship state (no henchman_lifecycle row, no quest binding, no ongoing party party-membership-state). This is the tight per-visit cleanup.
  - **(a) Session-boundary** (safety net) — at session end, scan `characters` globally for `npc_role = 'on_demand'` rows with no retained state, and delete them. This catches any rows that escaped the party-departure trigger (edge cases like the game saving mid-settlement-visit, or session crashes before clean departure).
  - **Time-based** (option b) is NOT used; the trigger-based approach is sharper.
  - **Retention check** — a row is "retained" if any of: henchman_lifecycle.character_id = this.id; quest_rumor_system has a Rumor with `source_id` pointing at this character; or any other consumer system has registered interest. Future v2 may add additional retention paths (faction membership, etc.); the cleanup procedure consults a project-designed `is_character_retained(character_id) -> bool` helper that future systems extend.
