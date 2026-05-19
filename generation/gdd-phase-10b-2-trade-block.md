# GDD — Phase 10B.2 Trade Block

> **2026-05-15 currency-precision note (audit closed 2026-05-19 bucket-B sweep):** This GDD was authored before the cp-precision pass. Identifiers throughout — `entry_toll_cp`, `labor_fee_cp`, `customs_duty_cp`, `stabling_cp_*`, `moorage_cp_*`, `entry_toll_paid_cp`, `fee_cp`, `fee_paid_cp`, `market_value_at_acquisition_cp`, `cp_per_load`, `cp_received`, `total_cp_paid`, `net_cp_received`, `total_purchase_cp`, `grand_total_cp`, `gross_proceeds_cp`, `net_proceeds_cp`, `compute_fee_cp` — were renamed to their `_cp` equivalents in the engine + this GDD's pseudocode + signal signatures during the cp-precision pass and the 2026-05-19 bucket-B audit. cp is the project's base currency (1 gp = 100 cp); banker's rounding fires only on fractional cp (rare).

> **Status:** Drafting (2026-05-13). Section-by-section sign-off in progress with project owner.
>
> **Audience:** The Phase 10B.2 build session (and any parallel Phase 10B.3 work that needs to coordinate signal contracts).
>
> **Companion documents:**
> - `generation/gdd-settlement-economy.md` — the **substrate** GDD whose APIs this block consumes (MerchandiseRegistry, MarketPriceResolver, MarketFeesCalculator, MerchantPoolRepository, CargoHoldRepository, CargoEncumbranceCalculator, ShipRepository, ShippingContractRepository). Phase 10B-prereq mercantile shipped this in full.
> - `docs/phase-10b-subsystem-dependencies.md` — the scoping doc from Phase 10 planning that enumerated what 10B.2 / 10B.3 would need; the substrate GDD is the resolution of that scope.
> - `docs/coding_conventions.md` §32 (Activity Subsystem) + §52 (Conditional-section modal pickers + activity-launcher gating) — the established patterns this block follows.
>
> **What changed since the substrate GDD:** every public API enumerated in `gdd-settlement-economy.md` §4-§9 is now shipped and tested. The integration test at `tests/test_commerce_integration.gd` reproduces the canonical §12 Ashford/Thornwall worked example end-to-end through those APIs. This GDD specifies the **activity handlers + UI surface + trigger wiring** that turn those APIs into a player-facing Trade block.

---

## §0. Document Goals, Scope, and the RAW-vs-Project-Design Ledger

### 0.1 What this GDD covers

This document specifies the **Trade block** — the player-facing mercantile system at Phase 10B.2:

1. **Activity catalog** — five RAW-cited activities encoded in `data/activities/mercantile.json`: `buy_sell_merchandise`, `persuade_merchants`, `solicit_merchants`, `locate_merchandise`, `accept_shipping_contract`. Plus the `enter_market` interaction fold (per project-design decision §1.2 — RAW's separate "enter market" step folds into `buy_sell_merchandise`'s per-visit toll tracking).
2. **Activity handlers** — one `.gd` file per activity in `engine/subsystems/activities/handlers/mercantile/`, following the §32 conventions. Each handler orchestrates the substrate services (MarketPriceResolver, MarketFeesCalculator, MerchantPoolRepository, CargoHoldRepository, ShippingContractRepository).
3. **Trade UI** — block + pickers in the **settlement detail view** (per Q-TB-3 resolution — Trade is settlement-scoped, not domain-scoped). A new `mercantile_block.gd` parallels the existing `magical_research_block.gd` / `faith_block.gd` pattern but lives in the settlement UI surface rather than the Domain tab. Modal pickers follow §52's conditional-section dispatcher pattern.
4. **Monopoly registry** — new `monopoly_holdings` table per RAW (acore-campaign-hijinks.xml's monopolist mechanic), consumed by `MarketPriceResolver` via the existing `monopolist_favor` caller-supplied integer.
5. **Per-visit market entry tracking** — a small new state table or transient column tracking "has this party entered this market on this visit?" so the entry toll fires exactly once per visit.
6. **Trade-route detection triggers** — wiring `TradeRouteDetector.detect_routes_for_campaign` / per-settlement detection into the EventBus signals that the substrate documented (settlement_created, road_overlay_added/removed, settlement_market_class_changed, river_overlay changes, campaign load).
7. **Monthly-tick wiring** — placing the four substrate-shipped campaign-wide drivers (merchant pool refresh, market price drift, ship operating costs, annual customs roll) into the existing monthly-tick infrastructure. Includes year-tick trigger architecture for the annual customs roll.
8. **Partial-load handling** — the careful design for split-load semantics per Q-TB-6 resolution (partial loads allowed; lost-vehicle edge case handled gracefully).
9. **Market POI design** — a new "Market Square" / "Bazaar" point-of-interest in the settlement layout that mercantile activities attach to (per Q-TB-19 brainstorming). Either separate from the existing shop POI or combined; this GDD proposes.

### 0.1.1 LLM-promotion forward-compat anchor (Q-TB-21)

**Constraint added 2026-05-13:** in v1, all merchant interactions are purely transactional — merchants spawn at monthly refresh, sell loads, expire/deplete/get-persuade-failed, and are freely deleted. **But** a future LLM tool-caller layer may "promote" a transactional merchant to a named, persistent NPC who:
- Survives monthly refresh (does not get wiped with the cohort).
- Survives expiration (does not get cleaned by `process_expirations`).
- Survives persuade-fail (the named NPC may refuse this cohort but is not "permanently lost from the world").
- Still has cycling `loads_available` (each new cohort re-rolls their inventory, but the row persists).
- Can be linked to a `characters` row (the bridge to the rest of the NPC system, dialogue, reputation, etc.).

**Architectural commitment.** Every Trade-block design decision that touches merchant lifecycle in this GDD MUST preserve the path to LLM-driven promotion later. Specifically:

1. **A nullable `promoted_npc_id TEXT REFERENCES characters(id)` column ships on `merchant_pool` in Phase 10B.2's migration list** (likely bundled with the monopoly registry migration in §8, or as a standalone migration if §8 doesn't ship one). In v1 the column is always NULL; no caller populates it.
2. **Every lifecycle path checks `promoted_npc_id`:**
   - **Monthly refresh** (`generate_pool_for_settlement`): wipes `source_kind='monthly_refresh' AND promoted_npc_id IS NULL` rows. Promoted rows are PRESERVED and instead UPDATEd with fresh `loads_available` + extended `expires_at_calendar_day` + reset visibility. The cohort's `max_merchant_count(class)` cap counts promoted rows — so generation creates `max_count - existing_promoted_count` new transactional rows. Detailed §11.
   - **Expiration** (`process_expirations`): skip rows where `promoted_npc_id IS NOT NULL`. The next monthly refresh's promoted-row UPDATE path re-cycles them. Detailed §11.
   - **Persuade-fail** (Phase 10B.2 design in §4): rows where `promoted_npc_id IS NULL` get DELETEd (RAW "permanently lost"). Rows where `promoted_npc_id IS NOT NULL` get a "refused this cohort" flag instead (TBD per §4 — possibly a `refused_cohort_id INTEGER` column or a side-table; designed in §4).
3. **No v1 caller populates `promoted_npc_id`.** Phase 10B.2 ships the column + the preservation logic; the LLM promotion procedure itself is later work. The cost in v1 is one nullable TEXT column + a small `WHERE promoted_npc_id IS NULL` filter on three DELETE/UPDATE statements.

**Why this matters.** Without the forward-compat hook, adding LLM-driven persistent merchants later would require either: rewriting the entire `merchant_pool` lifecycle (large refactor + risk to existing tests), OR shadowing it with a parallel `persistent_merchants` table (data-model split + double-bookkeeping). The forward-compat hook keeps the merchant_pool table as the single source of truth for merchant state, with the promoted-vs-transactional distinction encoded as one nullable FK.

`[NEEDS-LLM-PROMOTION-LATER]` flag planted at the relevant code sites (monthly refresh + expiration + persuade-fail) so a future search can find every promotion-aware code path in one pass.

### 0.2 What this GDD does NOT cover

- **Phase 10B.3 (Syndicate block)** — Crime & Punishment resolver, smuggling/stealing/order_hijink handlers, hijink-yield-to-cargo flow. These consume some of the same substrate (CharacterLegalStatusRepository, MarketPriceResolver, CargoHoldRepository.insert_hijink_yield) but the activity handlers + UI are 10B.3's responsibility.
- **The Trade UI's settlement-side framework itself.** Phase 10B.2 adds a block to the settlement view; the underlying settlement view scaffolding (entrance, POI list, transition handlers) is pre-existing Phase 1-9 work and is reused, not redesigned. Reviewing the integration points is a §2.1 deliverable, not a rebuild.
- **`solicit_passengers`** — the passenger half of RAW's passenger-and-cargo-transport table is deferred per Q-TB-2 resolution. Phase 10B.2 ships shipping contracts only; passenger transport is a Phase 10B.2-followup or v1.1.
- **Judge-modifier sourcing** — `MarketPriceResolver.compute_market_price` takes a `judge_modifier: int` param per the substrate GDD §6.1.1. Phase 10B.2 passes 0 to this param in all activity-handler call sites. A future system (settlement_events table? war flag?) that surfaces judge modifiers can wire into the call sites without changing the resolver. Per Q-TB-10 resolution.
- **Real-time price preview UI** — per Q-TB-17 clarification this GDD covers what "preview" can mean and resolves whether to show a pre-roll estimate (with rolled dice not yet consumed) versus post-roll discovery (player clicks Buy, dice roll happens, price appears). See §14.
- **NPC merchant migration / dynamic pool reshaping mid-cohort.** RAW silent; substrate already deferred. Merchants stay where they spawn until expiration / refresh.
- **Caravan-as-aggregate.** A 40-wagon caravan in RAW is one logical unit. The cargo system treats it as 40 individual `draft_vehicles` rows; this GDD doesn't introduce a caravan aggregate.
- **Naval movement / wind / currents.** Ships move at wilderness-movement speed; no naval-specific mechanics in v1.
- **Re-doing the LLM narrative layer.** The per-merchant transaction model (Q-TB-5) leaves room for LLM-driven merchant personas in a future wave; this GDD ships the transaction-only data model that will support that.
- **The LLM merchant-promotion procedure itself.** Per Q-TB-21 / §0.1.1 the forward-compat hook (`promoted_npc_id` nullable column + preservation logic) ships in this GDD. The actual procedure that calls the promotion (LLM tool-caller deciding "this merchant becomes an NPC", creating the `characters` row, linking the FK) is later work. v1 leaves `promoted_npc_id` always NULL.

### 0.3 The RAW-vs-Project-Design ledger format (§5.0 mandatory rule)

Identical to the substrate GDD's §0.3 — every project-designed element in this document MUST carry a four-line ledger entry:

- **RAW citation:** the exact file + line range in `rules/` that the element grounds against. If RAW is silent, cite the closest adjacent rule.
- **What RAW provides:** a one- or two-sentence verbatim summary.
- **What's missing:** the precise gap that requires project-design fill.
- **Project resolution:** the rule this GDD locks in, with rationale.

No silent project-design anywhere in this document. Pure-RAW encodings collapse to one ledger entry ("faithful encoding").

### 0.4 Authority and modification rules

- This GDD is **Layer-2** per `CLAUDE.md` §Document Authority — project-designed, modifiable with project-owner sign-off. RAW citations within it are not.
- The sacred-rules policy (`CLAUDE.md`'s "do not modify `rules/*.xml`") remains in force. The Q-MERC-1A correction was a one-instance approved exception and does not generalize.
- If a future RAW spotcheck reveals a discrepancy with this GDD, **the RAW wins**.

### 0.5 Calendar conventions

Inherited from the substrate GDD §0.5. The project uses a 13-month / 28-day / 364-day calendar. `Timekeeping.DAYS_PER_MONTH = 28`, `Timekeeping.MONTHS_PER_YEAR = 13`, `Timekeeping.DAYS_PER_YEAR = 364`.

Every "monthly" window in this GDD uses 28 days (e.g., monthly tick cadence, contract deadline math, merchant cohort lifecycle). The year-tick for the annual customs roll is the 1st day of the 1st month — i.e., day-of-year = 1 in the project's calendar.

### 0.6 Three-corner alignment

This GDD aligns three corners per the substrate GDD's acceptance criteria:

1. **RAW** — `rules/acore-campaign-hijinks.xml` §generating_demand_modifiers + §market_arbitrage (L617-763) + §market_and_merchants (L656-672) + §marketability + §customs_duty + §loading_unloading + §moorage + §stabling, plus `rules/ax_campaign_play.xml` §arbitrage activities.
2. **Substrate GDD** — `gdd-settlement-economy.md` is the API contract. Every Trade block call to a substrate service must use the exact signature the substrate GDD locked in.
3. **Project conventions** — `docs/coding_conventions.md` §32 (Activity Subsystem) + §52 (Conditional-section modal pickers + activity-launcher gating) + §11 (Cross-Subsystem Boundaries) + §4 (Signal Conventions).

### 0.7 Cross-section question index

The 20 open questions surfaced before drafting are resolved in the following sections:

| Question | Resolution location |
|---|---|
| Q-TB-1 (activity catalog name) | §1.1 |
| Q-TB-2 (enter_market fold; solicit_passengers defer) | §1.2 |
| Q-TB-3 (Trade UI location = settlement detail) | §2.1 |
| Q-TB-4 (active character + party wallet) | §3.1 |
| Q-TB-5 (per-merchant transactions) | §3.2 |
| Q-TB-6 (partial loads + split-load semantics) | §13 |
| Q-TB-7 (settlement UI integration discussion) | §2.2 |
| Q-TB-8 (persuade-merchants reaction roll) | §4 |
| Q-TB-9 (monopoly registry) | §8 |
| Q-TB-10 (judge-modifier source — deferred) | §0.2 (out of scope) |
| Q-TB-11 (per-visit entry toll tracking — options) | §9 |
| Q-TB-12 (trade-route detection triggers — all four scenarios + market_class) | §10 |
| Q-TB-13 (monthly-tick wiring architecture) | §11 |
| Q-TB-14 (year-tick architecture) | §12 |
| Q-TB-15 (solicit_merchants polling cadence) | §5 |
| Q-TB-16 (locate_merchandise picker) | §6 |
| Q-TB-17 (price preview clarification) | §14 |
| Q-TB-18 (cargo encumbrance display) | §15 |
| Q-TB-19 (market POI design — brainstorm) | §2.3 |
| Q-TB-20 (test plan) | §18 |
| Q-TB-21 (LLM-promotion forward-compat) | §0.1.1 + §4 (persuade-fail) + §11 (monthly refresh) + §8 or standalone migration |

### 0.8 What §0 does NOT add

- **No activity-handler implementations.** Section §1 specifies the catalog rows; §3-§7 specify the handler designs. §0 is scaffolding only.
- **No schema changes.** The substrate GDD shipped 7 migrations (097-103). Phase 10B.2 introduces at most 2 new migrations (monopoly registry §8, possibly per-visit entry-toll state §9). All other state reuses substrate tables.
- **No production code.** This GDD is design; implementation lands in §19's wave plan.

---

## §1. Activity Catalog — `mercantile_category.json`

### 1.1 File location and structure

Per `docs/coding_conventions.md` §32, every activity category gets a single JSON catalog at `data/activities/<category>_category.json`. Phase 10B.2 ships **`data/activities/mercantile_category.json`** matching the established shape (header `_meta` block + `activities` array). The `_meta` block records:

```json
{
  "_meta": {
    "category": "mercantile",
    "source": "rules/acore-campaign-hijinks.xml §market_arbitrage L617-763; rules/ax_campaign_play.xml §arbitrage activities",
    "schema_version": 1,
    "phase": "10B.2"
  },
  "activities": [ ... ]
}
```

The `ActivityCatalog._load_all` autoload pattern enumerates every `*.json` in `res://data/activities/` at construction; adding a new category is just creating the file. **No engine change required to register the category itself.**

### 1.2 The `enter_market` fold (Q-TB-2 resolution)

RAW conceptually separates "entering a market" (paying the toll) from "buying/selling within it" (the transaction). Per Q-TB-2 [RESOLVED 2026-05-13], the project folds these into a single `buy_sell_merchandise` activity rather than authoring a separate `enter_market` activity.

- **RAW citation:** `rules/acore-campaign-hijinks.xml:647-650, 656-672` (toll + market entry).
- **What RAW provides:** "Each time adventurers enter a market to buy or sell goods, they must pay a toll." Toll is per-entry, not per-stay.
- **What's missing:** RAW doesn't specify whether "entering" is a distinct game-time action (`enter_market` activity) or a side effect of "doing business in the market" (buy/sell/persuade/solicit/locate). The project's existing settlement-entry flow already handles "being at the settlement"; entering the **market specifically** is the gap.
- **Project resolution:** the **first** mercantile activity launch per visit triggers the entry toll via the `MarketFeesCalculator.entry_toll_cp` call inside that activity's handler. Subsequent activities within the same visit consult the per-visit state (§9) and don't re-charge. The "visit" boundary is defined as "from the time the party enters the settlement-detail view to the time they depart it" — operationally, a per-party per-settlement boolean flag cleared on departure (design detail in §9).
- **Why fold-in beats a separate activity:** a standalone `enter_market` would either (a) be invisible to the player (just an autofire on settlement entry — but then it's not really an activity), or (b) require an explicit "enter market" click before any transaction (UX friction with no design benefit). The fold-in keeps the toll deterministic without adding a redundant launcher to the UI.

The first transaction in a visit therefore has a slightly higher gp cost than subsequent ones (it absorbs the toll). The UI surfaces this in the transaction breakdown (§3.3 receipt design) so the cost is transparent to the player.

### 1.3 Activity catalog rows

Five activities, with detailed handler designs deferred to their dedicated sections (§3-§7). The catalog rows below specify the metadata that `ActivityTimeCostExecutor` and the eligibility gates consume.

#### 1.3.1 `buy_sell_merchandise`

```json
{
  "id": "buy_sell_merchandise",
  "category": "mercantile",
  "frequency": "singular",
  "activity_level": "minor",
  "strenuous": false,
  "default_ticks_required": 1,
  "session_time_cost_rounds": "minor_activity",
  "location_kind": "at_settlement",
  "prerequisites": ["at_market_poi"],
  "remote_capable": false,
  "param_schema": {
    "merchant_id": "string",
    "mode": ["buy", "sell"],
    "merchandise_type": "string",
    "loads_count": "int",
    "carrier_id": "string",
    "carrier_kind": ["draft_vehicle", "ship"],
    "cargo_hold_id": "string"
  },
  "effect_summary": "Buys or sells N loads of merchandise. First activity per visit absorbs the entry toll. Adds/removes a cargo_holds row. Debits or credits the party wallet (active character mediates).",
  "raw_citation": "acore-campaign-hijinks.xml §market_arbitrage step 4 (L617-763); ax_campaign_play.xml §buy_sell_merchandise"
}
```

**Param shape notes:**
- `mode`: `"buy"` or `"sell"`. UI picker pre-fills based on which button the player clicked.
- `merchant_id`: required in `"buy"` mode (which merchant's loads do we consume?); ignored in `"sell"` mode (sells flow through the settlement's market price, not a specific merchant).
- `merchandise_type`: required.
- `loads_count`: required, positive integer.
- `carrier_id` + `carrier_kind`: required in `"buy"` mode (which carrier loads the cargo?); in `"sell"` mode, derived from `cargo_hold_id`.
- `cargo_hold_id`: required in `"sell"` mode (which cargo row to deplete/delete?); ignored in `"buy"` mode.

The handler design (§3) validates the param matrix and rejects malformed combinations.

**Prerequisite `"at_market_poi"`:** a new prerequisite tag introduced by this GDD per §2.3's market POI design. The eligibility resolver checks the party's current POI before unlocking the launcher.

#### 1.3.2 `persuade_merchants`

```json
{
  "id": "persuade_merchants",
  "category": "mercantile",
  "frequency": "singular",
  "activity_level": "minor",
  "strenuous": false,
  "default_ticks_required": 1,
  "session_time_cost_rounds": "minor_activity",
  "location_kind": "at_settlement",
  "prerequisites": ["at_market_poi", "visible_merchant_present"],
  "remote_capable": false,
  "param_schema": {
    "merchant_id": "string",
    "target_merchandise_type": "string"
  },
  "effect_summary": "Reaction roll (9+/12+) to convince a visible merchant to deal in target_merchandise_type. Modified by ±demand_modifier and +3 if monopolist. Success: merchant's merchandise_type updates. Failure: merchant DELETEd (or marked refused if promoted_npc_id is set per §0.1.1).",
  "raw_citation": "acore-campaign-hijinks.xml §market_arbitrage step 3 (L707-716)"
}
```

**Prerequisite `"visible_merchant_present"`:** activity rejects launch if `MerchantPoolRepository.list_visible_merchants(settlement_id, current_day)` is empty — the player can't persuade a merchant who isn't there.

Full handler design + reaction-roll modifiers + the success/failure transitions (including the `promoted_npc_id` preservation per §0.1.1) land in **§4**.

#### 1.3.3 `solicit_merchants`

```json
{
  "id": "solicit_merchants",
  "category": "mercantile",
  "frequency": "ongoing",
  "activity_level": "minor",
  "strenuous": false,
  "duration_formula": "21",
  "default_ticks_required": 21,
  "session_time_cost_rounds": "minor_activity",
  "location_kind": "at_settlement",
  "prerequisites": ["at_market_poi", "invisible_merchants_remaining"],
  "remote_capable": false,
  "param_schema": {},
  "effect_summary": "Ongoing 1-3 weeks (RAW); 1 hour of game time per day. At launch, assigns staggered becomes_visible_calendar_day to invisible merchants (half ceil +7, quarter floor min 1 +14, remainder +21). Reveals fire on schedule while activity remains active; forfeiture rolls back unfired reveals (per §5).",
  "raw_citation": "acore-campaign-hijinks.xml §market_arbitrage step 2 (L679-684); ax_campaign_play.xml §solicit_merchants L949-963"
}
```

**Frequency `ongoing`:** consumed by `ActivityTimeCostExecutor` per §32 conventions. The handler's `on_tick` fires daily (one minor-activity hour); the staggered reveal logic runs once at launch (per substrate GDD §7.5.1) plus per-day forfeiture-check logic per Q-TB-15 (§5).

**Prerequisite `"invisible_merchants_remaining"`:** rejects launch if `MerchantPoolRepository.list_invisible_merchants(settlement_id, current_day)` is empty (pool already revealed or PC-owned domain). Mirrors the substrate's `process_solicitation` error path.

**`duration_formula: "21"`:** fixed at 21 days regardless of pool size, per RAW. The reveal schedule may complete earlier if the pool is small (e.g., Class VI N=2 finishes by day +14), but the activity's full game-time commitment is the 3-week ongoing window.

Full handler design + forfeiture semantics + reveal-day rollback land in **§5**.

#### 1.3.4 `locate_merchandise`

```json
{
  "id": "locate_merchandise",
  "category": "mercantile",
  "frequency": "singular",
  "activity_level": "minor",
  "strenuous": false,
  "default_ticks_required": 1,
  "session_time_cost_rounds": "minor_activity",
  "location_kind": "at_settlement",
  "prerequisites": ["at_market_poi"],
  "remote_capable": false,
  "param_schema": {
    "merchandise_type": "string"
  },
  "effect_summary": "1 hour of game time. Surfaces one invisible merchant carrying merchandise_type (visible match → no-op success; invisible match → reveal one; no match → fail with no_merchant_of_type).",
  "raw_citation": "acore-campaign-hijinks.xml §market_arbitrage step 3 sub-clause (L707-715, alter-not-spawn reading)"
}
```

**Singular minor unstrenuous, 1 hour** per substrate §7.5.2 (and Q-MERC-... resolution). The handler delegates to `MerchantPoolRepository.process_locate` from the substrate.

Full handler design + picker UI shape (single-dropdown for merchandise type) lands in **§6**.

#### 1.3.5 `accept_shipping_contract`

```json
{
  "id": "accept_shipping_contract",
  "category": "mercantile",
  "frequency": "singular",
  "activity_level": "minor",
  "strenuous": false,
  "default_ticks_required": 1,
  "session_time_cost_rounds": "minor_activity",
  "location_kind": "at_settlement",
  "prerequisites": ["at_market_poi", "carrier_present", "shipping_offer_present"],
  "remote_capable": false,
  "param_schema": {
    "offer_id": "string",
    "carrier_id": "string",
    "carrier_kind": ["draft_vehicle", "ship"]
  },
  "effect_summary": "Accepts a fresh shipping-contract offer (rolled at market entry, transient). Inserts a shipping_contracts row + linked cargo_holds row on the designated carrier.",
  "raw_citation": "acore-campaign-hijinks.xml §passenger_and_cargo_transport L765-790ish"
}
```

**`offer_id`** points into the transient per-visit available-contracts list (rolled fresh at market entry per substrate §9.7; storage TBD §7). This is NOT a `shipping_contracts.id` (those are post-acceptance) — it's a session-scoped offer identifier.

**Prerequisite `"shipping_offer_present"`:** rejects launch if the visit's rolled offers list is empty (Class VI markets often roll zero offers per RAW).

Full handler design + the offers-roll-at-entry mechanism + the linked cargo_holds insertion via `CargoHoldRepository.insert_shipping_contract_load` land in **§7**.

### 1.4 Handler file layout

Per §32 conventions, one `.gd` file per activity, plus a single registration glue file:

```
engine/subsystems/activities/handlers/mercantile/
├── buy_sell_merchandise.gd
├── persuade_merchants.gd
├── solicit_merchants.gd
├── locate_merchandise.gd
├── accept_shipping_contract.gd
└── mercantile_handlers_registration.gd
```

The registration file exposes `register_all(registry)` that the SessionRunner's `load_session` calls after instantiating the registry — matching the pattern in `domain_handlers_registration.gd`. Phase 10B.2 modifies SessionRunner's load_session call list to add the mercantile registration alongside the existing domain / faith / etc. registrations.

### 1.5 Eligibility prerequisite tags introduced

Three new prerequisite tags ship in Phase 10B.2:

- **`at_market_poi`** — checked by the eligibility resolver against the party's current settlement-detail POI. The market POI design lands in §2.3.
- **`visible_merchant_present`** — checked via `MerchantPoolRepository.list_visible_merchants(settlement_id, current_day).size() > 0`.
- **`invisible_merchants_remaining`** — checked via `MerchantPoolRepository.list_invisible_merchants(settlement_id, current_day).size() > 0`.
- **`carrier_present`** — checked via "does the party own at least one non-destroyed draft_vehicle OR ship?" (the eligibility resolver runs the union of `ShipRepository.list_ships_for_party` + the existing `CampaignRepository.list_draft_vehicles_for_party` count).
- **`shipping_offer_present`** — checked against the visit's transient offers list (storage TBD §7).

These tags wire into the existing eligibility-resolver infrastructure. The resolver dispatches on tag string; mercantile-specific tags get their own `case` branches.

### 1.6 What §1 does NOT add

- **No handler implementations.** Catalog rows specify metadata only. Handler bodies are §3-§7.
- **No picker designs.** UI pickers per §52 conventions land in §3-§7 alongside their handlers.
- **No `effect_summary` exhaustive enumeration.** The summary field is human-readable; complete effect documentation lives in each handler's `.gd` docstring + the dedicated section.
- **No prerequisite-resolver implementation.** The five new tags are listed here; their resolver branches are a §17 (or wave-plan) deliverable.
- **No data validation tests for `mercantile_category.json`.** Catalog-parse tests are a §18 deliverable.

---

## §2. Trade UI — Settlement Detail View Integration + Market POI Design

### 2.0 Overview

Per Q-TB-3 [RESOLVED 2026-05-13], the Trade block lives in the **settlement detail view**, not the Domain tab Notebook. This section grounds in the existing settlement-UI scaffolding (built per `gdd-settlement-exploration-ui.md v2`) and specifies:

1. How the existing settlement-detail surface accommodates Trade (§2.1 audit; §2.2 the equipment-vs-merchandise distinction).
2. The market POI design that hosts mercantile activities (§2.3 — resolution of Q-TB-19 brainstorm).
3. The Trade block UI architecture — what panel(s) ship, how they slot into existing flow (§2.4).
4. Activity-launcher integration — where the five activity launchers live and how they gate (§2.5).
5. Picker patterns per §52 conventions (§2.6).

### 2.1 Existing settlement UI surface (audit per Q-TB-7)

The settlement-detail surface already exists with these components:

- **`SettlementMenu`** (`scenes/ui/settlement/settlement_menu.gd`) — a 40%-wide PanelContainer overlay on the right side of the viewport at layer 10. Shows the settlement's PoIs grouped by district. Emits `poi_clicked(poi: Dictionary)`. Pure menu overlay; the world view remains visible behind it. Per `gdd-settlement-exploration-ui.md v2 §2-3`.
- **`SettlementActivityPanel`** (`scenes/ui/settlement/activity_panel.gd`) — dynamic activity panel rendered when the party arrives at a PoI. Reads from a hard-coded `ACTIVITIES: Dictionary` mapping `poi_type → Array of activity definitions`. Emits `activity_requested(activity_type, poi)`, `shop_requested(poi)`, `hiring_requested(poi)`, `exit_settlement_requested()`.
- **`SettlementExploreState`** (consumer of the menu) — owns the menu lifecycle, routes signals, auto-pauses scheduler while menu is open.
- **`shop_panel.gd`** + **`hiring_panel.gd`** — child panels invoked from the activity panel for specific complex flows (the existing equipment-shop UI + henchman-hire UI).
- **POI type vocabulary** (per the `_icon_for_type` / `ACTIVITIES` enums): `tavern`, `inn`, `temple`, `shrine`, `shop`, `shophouse`, `emporium`, `guild`, `guild_hall`, **`market`**, `town_square`, `lord_keep`, `garrison`, `gate`, `npc_residence`, `undercity_entrance`, `bridge`, `road_junction`.

**Key finding:** the `market` POI type ALREADY exists. Its current activity list is `buy_equipment` / `sell_equipment` / `hire_hirelings` / `gather_info`. The Trade block design therefore EXTENDS the `market` POI's activity list rather than introducing a wholly new POI type.

`town_square` shares the same icon glyph as `market` but currently has no activities defined. The §2.3 resolution treats it as a smaller-scale equivalent.

### 2.2 Mercantile vs equipment — the distinction this GDD honors

The existing settlement shop system handles **equipment** transactions (per-item swords, armor, rations, etc. — driven by `data/equipment/*.json` catalogs). Phase 10B.2 introduces **merchandise** transactions (per-load bulk arbitrage of the 31-merchandise registry — driven by `MerchandiseRegistry` + `MarketPriceResolver`).

- **RAW citation:** `rules/acore-campaign-hijinks.xml §market_arbitrage L617-763` (merchandise/arbitrage) vs `rules/acore_equipment.xml` (equipment).
- **What RAW provides:** ACKS distinguishes "buying gear at the market" from "trading bulk loads at the market." Same physical location; different pricing models (per-item retail vs per-load demand-modified).
- **What's missing:** the project's existing settlement UI has only the equipment retail path (`buy_equipment`/`sell_equipment` against `equipment_catalog`). The merchandise arbitrage path is new.
- **Project resolution:** both paths coexist under the same `market` POI. The activity panel surfaces both — equipment activities (existing) plus merchandise activities (new). Clicking a merchandise activity opens a new `mercantile_panel.gd` (parallel to `shop_panel.gd`), specialized for the cargo-trade UI.

The two paths share NO state. Equipment lives in `inventory_items`; merchandise lives in `cargo_holds`. The party wallet (gold) is shared — both paths debit/credit it via `PartyWallet`. The active-character + party-wallet model from Q-TB-4 applies uniformly.

### 2.3 Market POI design (Q-TB-19 brainstorm resolution)

Q-TB-19 asked whether the mercantile activities should live in:
- (A) the existing `market` POI (combined),
- (B) a new `market_square` / `bazaar` POI separate from `market`, or
- (C) extend `market` AND treat `town_square` as an equivalent for smaller settlements.

**Recommended: (C) — extend `market`; `town_square` as alias for small settlements.**

- **RAW citation:** `rules/acore-campaign-hijinks.xml §market_arbitrage L656-672` (Markets and Merchants table — defines Class I-VI markets without distinguishing "trade square" from "general market").
- **What RAW provides:** every settlement with `market_class I-VI` HAS a market. RAW does not subdivide market into "equipment retail" vs "bulk trade" — same physical place hosts both.
- **What's missing:** the project's POI vocabulary lacks a single canonical "you do trade here" pin. `market` currently exists with equipment activities; `town_square` exists as a visual icon but has no activity list.
- **Project resolution:**
  1. **`market` POI hosts ALL mercantile + equipment activities.** The `ACTIVITIES["market"]` dictionary entry in `scenes/ui/settlement/activity_panel.gd` gains five new activity entries (one per §1.3 catalog row).
  2. **`town_square` is an alias for `market` in smaller settlements.** Class V / VI settlements may not have a formal market building; the town_square IS the trading venue. The eligibility resolver's `at_market_poi` prerequisite matches both POI types.
  3. **The `mercantile_panel.gd` UI (specified in §2.4) renders the full Trade block** when the player clicks a mercantile activity from either `market` or `town_square`.
- **Why combined-and-not-separate:** RAW doesn't separate them; the player's mental model is "the market is where I trade"; the implementation cost of a separate POI is settlement-generation work (every existing settlement-map fixture would need a new POI placed). The combined approach reuses the existing POI placement.
- **Why `town_square` as alias and not its own thing:** Class V/VI settlements lacking a formal "market" still have to support the mercantile activities — RAW's class definitions include all class V/VI settlements as having markets, just smaller ones. Treating `town_square` as a low-end visual is a UX courtesy; the activity logic doesn't branch.

**Settlement-generation note:** Phase 10B.2 does NOT modify settlement-generation logic. Existing settlement maps that already have a `market` or `town_square` POI gain the new activities automatically (data-driven via `mercantile_category.json` + the updated `ACTIVITIES` dict). Settlements that lack BOTH (rare; would represent a class-VII outpost or sub-class-VI hamlet) cannot host mercantile activities until generation places a POI — that's a future concern, not a v1 blocker.

### 2.4 Trade block UI architecture — `mercantile_panel.gd`

A new panel `scenes/ui/settlement/mercantile_panel.gd` (+ `.tscn`) parallels the existing `shop_panel.gd` shape:

- **Container:** PanelContainer; same theming (`UiSurfaceStyles.apply_framed_window_chrome`) as `shop_panel`.
- **Sectioned content** per §52's conditional-section dispatcher pattern. The panel has FIVE conditional sections, one per mercantile activity:
  - `_build_buy_sell_section()` — the buy/sell flow (§3 design)
  - `_build_persuade_section()` — the reaction-roll launcher (§4 design)
  - `_build_solicit_section()` — the 3-week-Ongoing launcher (§5 design)
  - `_build_locate_section()` — merchandise-type picker (§6 design)
  - `_build_shipping_contracts_section()` — the offers list + accept button (§7 design)
- **Activated section** chosen by the activity that opened the panel (one section visible at a time; sibling sections hidden but instantiated).
- **Cancel / Launch buttons** at footer per §52 picker conventions.
- **Live preview + validation labels** per §52 — recompute on every field change; `_launch_btn.disabled = not validation_message.is_empty()`.

#### 2.4.1 Single panel vs five panels

Per §52 ("One picker dispatcher over N kinds beats N per-kind pickers when only fields differ"), the five mercantile activities share enough UI chrome (PanelContainer + header + body + footer + Cancel/Launch + preview/validation) that consolidating into one panel with conditional sections is the right call.

The alternative — five separate panel files — would produce 5× boilerplate with negligible logic divergence. The shared parts (chrome, signal emission, footer behavior) live once in `mercantile_panel.gd`'s base; per-activity divergence lives in the five `_build_X_section()` methods (target: 50-100 lines each).

#### 2.4.2 Panel as launch-request emitter, not executor

Per §52 ("Picker emits a generic `launch_requested(activity_def_id, params, location_kind, location_ref)` signal — the caller turns it into `executor.launch(...)`"), the mercantile panel is **stateless about the executor / scheduler**. It emits:

```gdscript
signal launch_requested(activity_def_id: String, params: Dictionary, location_kind: String, location_ref: String)
signal cancelled()
```

The caller (`SettlementExploreState` — extends its existing routing to handle mercantile launches) resolves the executor + scheduler from `session_runner` and translates the payload into the launch call. Same pattern as the magical-research picker per §52.

### 2.5 Activity-launcher integration

The activity panel (`activity_panel.gd`) renders the activity list for the clicked POI. Phase 10B.2 extends `ACTIVITIES["market"]` (and `ACTIVITIES["town_square"]` — currently empty) with the new entries:

```gdscript
"market": [
    # — existing —
    {"id": "buy_equipment", "label": "Buy Equipment", "major": false, "requires_open": true},
    {"id": "sell_equipment", "label": "Sell Equipment", "major": false, "requires_open": true},
    {"id": "hire_hirelings", "label": "Hire Hirelings", "major": false, "requires_open": true},
    {"id": "gather_info", "label": "Gather Information (4 hours)", "major": true, "requires_open": true},
    # — new (Phase 10B.2) —
    {"id": "buy_sell_merchandise", "label": "Buy/Sell Merchandise", "major": false, "requires_open": true},
    {"id": "persuade_merchants", "label": "Persuade Merchants", "major": false, "requires_open": true},
    {"id": "solicit_merchants", "label": "Solicit Merchants (Ongoing, 1-3 weeks)", "major": true, "requires_open": true},
    {"id": "locate_merchandise", "label": "Locate Merchandise (1 hour)", "major": false, "requires_open": true},
    {"id": "accept_shipping_contract", "label": "Accept Shipping Contract", "major": false, "requires_open": true},
],
"town_square": [
    # Same five mercantile entries (town_square is a market alias per §2.3).
    {"id": "buy_sell_merchandise", "label": "Buy/Sell Merchandise", "major": false, "requires_open": true},
    {"id": "persuade_merchants", "label": "Persuade Merchants", "major": false, "requires_open": true},
    {"id": "solicit_merchants", "label": "Solicit Merchants (Ongoing, 1-3 weeks)", "major": true, "requires_open": true},
    {"id": "locate_merchandise", "label": "Locate Merchandise (1 hour)", "major": false, "requires_open": true},
    {"id": "accept_shipping_contract", "label": "Accept Shipping Contract", "major": false, "requires_open": true},
],
```

**Routing:** when one of the five mercantile activity IDs is clicked, `activity_panel` emits a new signal `mercantile_requested(activity_id, poi)` that `SettlementExploreState` routes to `mercantile_panel.gd` (instantiates the panel with the selected activity's section visible). Mirrors the existing `shop_requested(poi)` → `shop_panel` routing.

**Eligibility coarse-gating (per §52):** the activity panel's launcher buttons consult the five new prerequisite tags from §1.5 (`at_market_poi` is implicitly satisfied since we're at the market POI; the other four are checked at click time and the button is disabled with tooltip on failure). Examples:
- `buy_sell_merchandise` button disabled when party has no visible merchants AND no cargo to sell ("nothing to transact yet").
- `persuade_merchants` button disabled when `list_visible_merchants` is empty ("no merchants present to persuade — solicit first").
- `solicit_merchants` button disabled when `list_invisible_merchants` is empty ("pool fully revealed").
- `locate_merchandise` button always enabled when at_market_poi (the activity gracefully fails when no merchant of the requested type exists).
- `accept_shipping_contract` button disabled when the per-visit offers list is empty.

Per §52 the coarse gate lives at the BLOCK level (here, the activity panel); fine-grained per-field validation lives in the picker (mercantile_panel itself, per §2.4).

### 2.6 Picker pattern application

Per §52 patterns, each conditional section in `mercantile_panel`:

1. **Populates a shared `_fields: Dictionary`** with form controls (OptionButtons, SpinBoxes, Labels).
2. **Validates on every field change** — `_validate_params()` dispatches on `_kind` (the selected activity ID) and returns either an empty string (valid) or a rejection message; `_launch_btn.disabled = not validation_message.is_empty()`.
3. **Collects params via `_collect_params()`** — also dispatches on `_kind` to assemble the activity-specific param dict matching the §1.3 schema for that activity.
4. **Emits `launch_requested(activity_def_id, params, location_kind, location_ref)`** on Launch click, where `location_kind="settlement"` and `location_ref=settlement_id`.
5. **Hides itself + queue_frees before emitting the terminal signal** per §52's "modal owns its own teardown" rule.

The `_dd_id(dd: OptionButton) -> String` helper from §52 is reused for the merchant_id / cargo_hold_id / carrier_id / contract_offer_id dropdowns that appear in the various sections.

### 2.7 Settlement-detail-view changes summary

To make Phase 10B.2 work, the settlement-detail surface gets these targeted changes:

| File | Change |
|---|---|
| `scenes/ui/settlement/activity_panel.gd` | Extend `ACTIVITIES["market"]` and `ACTIVITIES["town_square"]` with 5 new activity rows. Add `mercantile_requested(activity_id, poi)` signal. Wire eligibility coarse-gating per §2.5. |
| `scenes/ui/settlement/mercantile_panel.gd` + `.tscn` | NEW. Conditional-section dispatcher panel hosting the 5 activity flows. Emits `launch_requested(...)` per §52. |
| `scenes/ui/settlement/settlement_menu.gd` | NO CHANGE. Existing POI rendering already handles `market` / `town_square` types. |
| `SettlementExploreState` (wherever it lives — TBD per implementation pass) | Add `_on_mercantile_requested(activity_id, poi)` routing. Mirrors `_on_shop_requested(poi)`. |

**No settlement-generation changes.** Existing settlement-map fixtures with `market` / `town_square` POIs gain the new activities automatically.

**No `SettlementMapData` schema changes.** The POI Dictionary remains `{id, type, name, ...}` — no new fields required for mercantile.

### 2.8 Active character + party wallet integration (Q-TB-4)

Per Q-TB-4 [RESOLVED 2026-05-13], the Trade block mirrors the existing shop-panel pattern:

- **Active character selector** at the top of the `mercantile_panel`. Dropdown lists party PCs (similar to `shop_panel`'s existing active-character logic).
- **Party wallet aggregator** for affordability + payment via `PartyWallet.pay(cost_cp, party_id, active_character_id)` — the active character is the "front" of the contribution chain but funds flow across all PCs at the active character's location.
- **Deposit on sale → active character's wallet** via `CampaignRepository.add_coins_cp(active_character_id, gp * 100)`.

**Why the active character matters for trade specifically:** the demand-modifier / monopolist-favor wiring (§8 monopoly registry) keys on character identity — the monopolist gets the +1 favor only when they're the active transactor. Other PCs in the party can fund the transaction but only the active character's monopoly status affects the price.

**Mirroring shop_panel:** the existing `shop_panel.gd` already has the active-character + party-wallet pattern. The `mercantile_panel` reuses this UX so the player's mental model carries over from equipment retail to merchandise trade.

### 2.9 What §2 does NOT add

- **No new POI types.** `market` and `town_square` already exist; Phase 10B.2 extends their activity lists rather than introducing new POI vocabulary.
- **No settlement-generation work.** If a settlement lacks both `market` and `town_square`, mercantile activities are not available there. Future setting-generation can address this.
- **No section-body designs.** The five `_build_X_section()` method internals are designed in §3-§7.
- **No `requires_open` semantics changes.** The existing `requires_open: true` checks (business hours) still apply per the activity panel's existing rendering logic. Per RAW, markets have business hours; the project's day/night cycle already gates them.
- **No `town_square`-vs-`market` flavor distinction.** Both render the same `mercantile_panel`. If future polish wants to flavor the UI differently (smaller header, fewer dropdowns) for `town_square`, that's a UX iteration, not a v1 blocker.
- **No equipment-vs-merchandise activity reordering.** The new activities are appended after the existing equipment activities in the activity list. UI ordering can be tuned during implementation if the layout becomes cluttered (5 new entries on top of the existing 4 = 9 buttons at a Class III market).

---

## §3. Buy / Sell Merchandise — Handler + UI Design

### 3.0 Overview

This is the central activity of the Trade block. The player buys merchandise (consuming a specific merchant's `loads_available`) or sells merchandise (against a specific merchant of matching type). Substrate APIs do the heavy lifting:

- `MarketPriceResolver.compute_market_price` for per-load pricing
- `MarketFeesCalculator.entry_toll_cp` / `labor_fee_cp` / `customs_duty_cp` for fees (stabling is exit-path, not transaction-path — see §9)
- `CargoHoldRepository.insert_purchase` / `delete_sold` / partial-sell (§13) for cargo persistence
- `MerchantPoolRepository.consume_loads` for merchant inventory tracking
- `PartyWallet.pay` + `CampaignRepository.add_coins_cp` for gp movement
- The §8 monopoly registry for `monopolist_favor` lookup
- The §9 per-visit state for entry-toll first-fire tracking

This section's job: assemble those calls into two handler files, design the UI sections that drive them, and lock in the validation matrix.

### 3.1 Two activities, not one (amends §1.3.1)

§1.3.1 sketched a single `buy_sell_merchandise` activity with a `mode: ["buy", "sell"]` param. On reflection, the cleaner shape is **two separate activity rows + two separate handler files** sharing a common helper:

- `buy_merchandise` (catalog row + `buy_merchandise.gd` handler)
- `sell_merchandise` (catalog row + `sell_merchandise.gd` handler)
- `buy_sell_common.gd` — shared helpers (transaction-receipt builder, per-visit-toll first-fire integration, monopolist-favor lookup, RNG seeding)

**Why two:**
- **UI clarity:** "Buy Merchandise" and "Sell Merchandise" are distinct mental models for the player. Two launchers in the activity panel give a clear single-purpose button rather than a "Buy/Sell" pick-flow.
- **Param schemas diverge enough** that conditional dispatch on `mode` inside one handler would be larger than just splitting into two files. Buy needs `merchant_id` + `carrier_id`; sell needs `merchant_id` + `cargo_hold_id` + (often) `loads_to_sell` < total.
- **Eligibility differs:** Buy gates on `visible_merchant_present` + `carrier_present`; Sell gates on `visible_merchant_present` + the party having ANY cargo (`carrier_has_cargo`).
- **§32 convention favors one-handler-per-activity-id.** Splitting matches the pattern (faith handlers, magical_research handlers, etc. are all one-id-per-file).

**Catalog amendment:** §1.3.1's `buy_sell_merchandise` row is replaced by these two rows in `mercantile_category.json`:

```json
{
  "id": "buy_merchandise",
  "category": "mercantile",
  "frequency": "singular",
  "activity_level": "minor",
  "strenuous": false,
  "default_ticks_required": 1,
  "session_time_cost_rounds": "minor_activity",
  "location_kind": "at_settlement",
  "prerequisites": ["at_market_poi", "visible_merchant_present", "carrier_present"],
  "remote_capable": false,
  "param_schema": {
    "merchant_id": "string",
    "merchandise_type": "string",
    "loads_count": "int",
    "carrier_id": "string",
    "carrier_kind": ["draft_vehicle", "ship"]
  },
  "effect_summary": "Buys loads_count of merchandise_type from merchant_id. Consumes merchant's loads_available. Inserts a cargo_holds row on the designated carrier. Debits party wallet for purchase + labor + (first-of-visit) entry toll.",
  "raw_citation": "acore-campaign-hijinks.xml §market_arbitrage step 4 (L617-763)"
},
{
  "id": "sell_merchandise",
  "category": "mercantile",
  "frequency": "singular",
  "activity_level": "minor",
  "strenuous": false,
  "default_ticks_required": 1,
  "session_time_cost_rounds": "minor_activity",
  "location_kind": "at_settlement",
  "prerequisites": ["at_market_poi", "visible_merchant_present", "carrier_has_cargo"],
  "remote_capable": false,
  "param_schema": {
    "merchant_id": "string",
    "cargo_hold_id": "string",
    "loads_to_sell": "int"
  },
  "effect_summary": "Sells loads_to_sell of cargo_hold_id's contents to merchant_id (whose merchandise_type must match). Deletes cargo row on full sell, decrements on partial (see §13). Credits party wallet for sale proceeds; debits labor + customs duty.",
  "raw_citation": "acore-campaign-hijinks.xml §market_arbitrage step 4 (L617-763)"
}
```

**New prerequisite tag `carrier_has_cargo`:** added to §1.5's eligibility list. Resolver checks via `SELECT EXISTS(SELECT 1 FROM cargo_holds JOIN draft_vehicles ON cargo_holds.draft_vehicle_id = draft_vehicles.id WHERE draft_vehicles.party_id = ?)` OR same for ships.

### 3.2 Buy mode handler — `buy_merchandise.gd`

```gdscript
class_name BuyMerchandiseHandler
extends RefCounted

## buy_merchandise handler (Phase 10B.2 — Trade block).
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §3.2 +
## acore-campaign-hijinks.xml §market_arbitrage step 4 (L617-763).
##
## state.params shape:
##   merchant_id, merchandise_type, loads_count, carrier_id, carrier_kind

static func on_complete(state: Dictionary, _runner) -> Dictionary:
    var character_id: String = String(state.get("character_id", ""))
    var settlement_id: String = String(state.get("location_ref", ""))
    var params: Dictionary = state.get("params", {})

    # 1. Validate params + look up merchant + carrier.
    var merchant_id: String = params.get("merchant_id", "")
    var merchandise_type: String = params.get("merchandise_type", "")
    var loads_count: int = int(params.get("loads_count", 0))
    var carrier_id: String = params.get("carrier_id", "")
    var carrier_kind: String = params.get("carrier_kind", "")

    var merchant: Dictionary = MerchantPoolRepository.get_merchant(merchant_id)
    if merchant.is_empty() or String(merchant.get("status", "")) != "active":
        return {"summary": "buy_merchandise: merchant missing or inactive", "success": false}
    if int(merchant.get("loads_available", 0)) < loads_count:
        return {"summary": "buy_merchandise: insufficient merchant loads", "success": false}
    if String(merchant.get("merchandise_type", "")) != merchandise_type:
        return {"summary": "buy_merchandise: merchant doesn't carry %s" % merchandise_type, "success": false}

    # 2. Active character + party context.
    var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
    if party_id.is_empty():
        return {"summary": "buy_merchandise: no party for active character", "success": false}

    # 3. Compute fees (toll first-fire + price + labor).
    var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
    var toll_charge: int = BuySellCommon.charge_entry_toll_if_first_visit(
        party_id, settlement_id, false, 0, rng)  # buy mode: is_selling=false
    var monopolist_favor: int = MonopolyRegistry.favor_for_buy(character_id, settlement_id, merchandise_type)
    var price_result: Dictionary = MarketPriceResolver.compute_market_price(
        merchandise_type, settlement_id, monopolist_favor, 0, rng,
        Timekeeping.current_calendar_day())
    var cp_per_load: int = int(price_result["cp_per_load"])
    var total_purchase: int = cp_per_load * loads_count
    var load_weight: int = MerchandiseRegistry.load_weight_stone(merchandise_type)
    var labor_fee: int = MarketFeesCalculator.labor_fee_cp(load_weight * loads_count)

    # 4. Carrier capacity check (uses CargoEncumbranceCalculator).
    var capacity_ok: bool = BuySellCommon.carrier_has_capacity(
        carrier_id, carrier_kind, load_weight * loads_count)
    if not capacity_ok:
        return {"summary": "buy_merchandise: carrier capacity exceeded", "success": false}

    # 5. Affordability check + debit.
    var total_cost: int = total_purchase + labor_fee  # toll already debited in step 3
    var pay_result: Dictionary = PartyWallet.pay(total_cost * 100, party_id, character_id)
    if not bool(pay_result.get("ok", false)):
        # Refund toll? (Per RAW, toll is paid on entry regardless of transaction success.
        # v1 keeps the toll charge; the transaction itself fails.)
        return {
            "summary": "buy_merchandise: insufficient funds (need %d gp purchase + %d gp labor)" % [
                total_purchase, labor_fee],
            "success": false,
        }

    # 6. Cargo + merchant state mutation.
    var cargo_id: String = CargoHoldRepository.insert_purchase(
        carrier_id, carrier_kind, merchandise_type, loads_count,
        total_purchase, settlement_id, Timekeeping.current_calendar_day())
    MerchantPoolRepository.consume_loads(merchant_id, loads_count)

    # 7. Build receipt + return.
    var receipt: Dictionary = BuySellCommon.build_buy_receipt(
        merchandise_type, loads_count, cp_per_load, total_purchase,
        toll_charge, labor_fee, monopolist_favor)
    EventBus.merchandise_purchased.emit(cargo_id, settlement_id, merchandise_type, loads_count, total_cost)
    return {
        "summary": "Bought %d × %s @ %d gp/load (total %d gp)" % [
            loads_count, merchandise_type, cp_per_load, total_cost],
        "success": true,
        "receipt": receipt,
        "cargo_hold_id": cargo_id,
    }
```

**Notable design points:**
- **Toll-already-paid even if transaction fails.** Per RAW, the entry toll is paid on entry, not on transaction success. If the buy fails affordability, the toll stays debited — the player "entered the market" and paid for the privilege regardless. The UI's pre-launch validation should make insufficient-funds rare, but the handler is defensive.
- **`BuySellCommon.charge_entry_toll_if_first_visit`** returns the actual gp charged (0 if already paid this visit). The receipt records it for the player's view.
- **`MonopolyRegistry.favor_for_buy`** returns `-1` if the active character holds the monopoly (lower buy price) and `0` otherwise. Symmetric helper `favor_for_sell` returns `+1`. Design lands in §8.
- **Carrier capacity check** uses the substrate's `CargoEncumbranceCalculator`. The check is post-fees-computed but pre-payment — order matters: validate the operation can complete, THEN debit.
- **`Timekeeping.current_calendar_day()`** is the existing autoload accessor — already used elsewhere in the codebase.

### 3.3 Sell mode handler — `sell_merchandise.gd`

```gdscript
class_name SellMerchandiseHandler
extends RefCounted

## sell_merchandise handler (Phase 10B.2 — Trade block).
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §3.3.

static func on_complete(state: Dictionary, _runner) -> Dictionary:
    var character_id: String = String(state.get("character_id", ""))
    var settlement_id: String = String(state.get("location_ref", ""))
    var params: Dictionary = state.get("params", {})

    # 1. Validate params + look up merchant + cargo.
    var merchant_id: String = params.get("merchant_id", "")
    var cargo_hold_id: String = params.get("cargo_hold_id", "")
    var loads_to_sell: int = int(params.get("loads_to_sell", 0))

    var merchant: Dictionary = MerchantPoolRepository.get_merchant(merchant_id)
    var cargo: Dictionary = CargoHoldRepository.get_cargo_hold(cargo_hold_id)
    if merchant.is_empty() or cargo.is_empty():
        return {"summary": "sell_merchandise: merchant or cargo missing", "success": false}
    var merchandise_type: String = String(cargo.get("merchandise_type", ""))
    if String(merchant.get("merchandise_type", "")) != merchandise_type:
        return {"summary": "sell_merchandise: merchant doesn't deal in %s" % merchandise_type, "success": false}
    if int(cargo.get("loads_count", 0)) < loads_to_sell:
        return {"summary": "sell_merchandise: insufficient cargo loads", "success": false}

    # 2. Active character + party context.
    var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
    if party_id.is_empty():
        return {"summary": "sell_merchandise: no party for active character", "success": false}
    var is_domain_owner: bool = MarketFeesCalculator.is_domain_owner_in_own_market(character_id, settlement_id)

    # 3. Compute fees.
    var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
    var toll_charge: int = BuySellCommon.charge_entry_toll_if_first_visit(
        party_id, settlement_id, true, loads_to_sell, rng)  # sell mode: is_selling=true
    var monopolist_favor: int = MonopolyRegistry.favor_for_sell(character_id, settlement_id, merchandise_type)
    var price_result: Dictionary = MarketPriceResolver.compute_market_price(
        merchandise_type, settlement_id, monopolist_favor, 0, rng,
        Timekeeping.current_calendar_day())
    var cp_per_load: int = int(price_result["cp_per_load"])
    var gross_sale: int = cp_per_load * loads_to_sell
    var load_weight: int = MerchandiseRegistry.load_weight_stone(merchandise_type)
    var labor_fee: int = MarketFeesCalculator.labor_fee_cp(load_weight * loads_to_sell)
    var customs: int = MarketFeesCalculator.customs_duty_cp(gross_sale, settlement_id, is_domain_owner)

    # 4. Credit + debit (atomic for the player's view).
    var net_proceeds: int = gross_sale - labor_fee - customs
    if net_proceeds > 0:
        CampaignRepository.add_coins_cp(character_id, net_proceeds * 100)
    elif net_proceeds < 0:
        # Edge case: low-margin transaction where labor + customs exceed gross.
        # Debit the shortfall from party wallet rather than blocking the sale.
        var shortfall_cp: int = (-net_proceeds) * 100
        var shortfall_pay: Dictionary = PartyWallet.pay(shortfall_cp, party_id, character_id)
        if not bool(shortfall_pay.get("ok", false)):
            return {
                "summary": "sell_merchandise: fees exceed proceeds and party cannot cover %d gp shortfall" % (-net_proceeds),
                "success": false,
            }

    # 5. Cargo mutation (full or partial — §13).
    var is_full_sell: bool = (loads_to_sell == int(cargo.get("loads_count", 0)))
    if is_full_sell:
        CargoHoldRepository.delete_sold(cargo_hold_id, gross_sale)
    else:
        CargoHoldRepository.partial_sell(cargo_hold_id, loads_to_sell, gross_sale)  # §13

    # 6. Build receipt + return.
    var receipt: Dictionary = BuySellCommon.build_sell_receipt(
        merchandise_type, loads_to_sell, cp_per_load, gross_sale,
        toll_charge, labor_fee, customs, monopolist_favor, is_domain_owner)
    EventBus.merchandise_sold.emit(cargo_hold_id, settlement_id, merchandise_type, loads_to_sell, net_proceeds)
    return {
        "summary": "Sold %d × %s @ %d gp/load (net %d gp)" % [
            loads_to_sell, merchandise_type, cp_per_load, net_proceeds],
        "success": true,
        "receipt": receipt,
    }
```

**Notable design points:**
- **Net proceeds, not gross, credited to player.** Cleaner than crediting gross then immediately debiting labor + customs as separate transactions.
- **Negative-net edge case** handled defensively. A low-margin sell in a high-customs market (e.g., bulky grain at 10 gp base with 20% customs) could produce labor + customs > gross. The handler tries to absorb the shortfall from party wallet; failure is a hard transaction failure with an informative summary.
- **Partial sell** delegates to `CargoHoldRepository.partial_sell(cargo_hold_id, loads_to_sell, gross_sale)` — designed in §13.
- **`is_domain_owner` resolved via substrate predicate** at top of handler; passed to `customs_duty_cp` for the §8.8 exemption.

### 3.4 Shared helper — `buy_sell_common.gd`

```gdscript
class_name BuySellCommon
extends RefCounted

## Shared helpers for buy_merchandise + sell_merchandise handlers.
## Per gdd-phase-10b-2-trade-block.md §3.4.

# Party resolution
static func resolve_party_for_character(character_id: String) -> String:
    # Existing helper available on CampaignRepository (verify during implementation).
    return CampaignRepository.get_party_for_character(character_id)

# Per-visit entry toll (§9 design)
static func charge_entry_toll_if_first_visit(
        party_id: String, settlement_id: String,
        is_selling: bool, merchandise_loads: int,
        rng: RandomNumberGenerator
) -> int:
    if VisitStateManager.has_paid_entry_toll(party_id, settlement_id):
        return 0
    var market_class: int = CampaignRepository.get_settlement_market_class(settlement_id)
    var toll: int = MarketFeesCalculator.entry_toll_cp(
        market_class, is_selling, merchandise_loads, rng,
        MarketFeesCalculator.is_domain_owner_in_own_market(
            VisitStateManager.active_character_for_visit(party_id, settlement_id),
            settlement_id))
    if toll > 0:
        PartyWallet.pay(toll * 100, party_id,
            VisitStateManager.active_character_for_visit(party_id, settlement_id))
    VisitStateManager.mark_entry_toll_paid(party_id, settlement_id, toll)
    return toll

# Deterministic per-transaction RNG (for entry toll re-rolls; price dice are cached on row)
static func transaction_rng(party_id: String, settlement_id: String) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("%s|%s|%d|trade_transaction" % [
        party_id, settlement_id, Timekeeping.current_calendar_day()])
    return rng

# Carrier capacity check
static func carrier_has_capacity(carrier_id: String, carrier_kind: String, incremental_stone: int) -> bool:
    if carrier_kind == "draft_vehicle":
        var check: Dictionary = CargoEncumbranceCalculator.draft_vehicle_capacity_check(carrier_id)
        if check.is_empty():
            return false
        return (int(check.get("used_stone", 0)) + incremental_stone) <= int(check.get("load_max_stone", 0))
    elif carrier_kind == "ship":
        var check: Dictionary = CargoEncumbranceCalculator.ship_capacity_check(carrier_id)
        if check.is_empty():
            return false
        return (int(check.get("used_stone", 0)) + incremental_stone) <= int(check.get("cargo_capacity_stone", 0))
    return false

# Receipt builders
static func build_buy_receipt(
        merch_type: String, loads: int, cp_per_load: int, total_purchase: int,
        toll: int, labor: int, monopolist_favor: int
) -> Dictionary:
    return {
        "kind": "buy",
        "merchandise_type": merch_type,
        "loads_count": loads,
        "cp_per_load": cp_per_load,
        "total_purchase_cp": total_purchase,
        "entry_toll_cp": toll,
        "labor_fee_cp": labor,
        "monopolist_favor": monopolist_favor,
        "grand_total_cp": total_purchase + toll + labor,
    }

static func build_sell_receipt(
        merch_type: String, loads: int, cp_per_load: int, gross_sale: int,
        toll: int, labor: int, customs: int, monopolist_favor: int,
        is_domain_owner: bool
) -> Dictionary:
    return {
        "kind": "sell",
        "merchandise_type": merch_type,
        "loads_sold": loads,
        "cp_per_load": cp_per_load,
        "gross_proceeds_cp": gross_sale,
        "entry_toll_cp": toll,
        "labor_fee_cp": labor,
        "customs_duty_cp": customs,
        "monopolist_favor": monopolist_favor,
        "domain_owner_exempt": is_domain_owner,
        "net_proceeds_cp": gross_sale - toll - labor - customs,
    }
```

**Notable design points:**
- **`VisitStateManager`** is a new singleton/RefCounted that owns per-visit state. Design lands in §9. The visit-state API used here is: `has_paid_entry_toll`, `mark_entry_toll_paid`, `active_character_for_visit`.
- **`transaction_rng` is deterministic per (party, settlement, day).** Multiple transactions on the same day share the same seed (good — replay reproducibility); transactions on different days reseed.
- **`build_*_receipt`** returns a Dictionary for the UI to render. The `grand_total_cp` (buys) and `net_proceeds_cp` (sells) are precomputed for quick display.

### 3.5 UI section — Buy mode (`mercantile_panel._build_buy_section()`)

The buy section's fields, top-to-bottom:

1. **Active character selector** — shared across the panel, top-level (per §2.8).
2. **Merchant dropdown** — visible merchants at this settlement. Label format: `"<merchant_id_short> — <merchandise_type> (<loads_available> loads available)"`. Stored metadata: the full merchant row.
3. **Loads SpinBox** — 1 to selected merchant's `loads_available`. Default: 1.
4. **Carrier dropdown** — party's non-destroyed draft_vehicles + ships. Label format: `"<carrier_name> — <free_stone> stone free"`. Stored metadata: `{id, kind}`.
5. **Live preview label** — recomputes on every field change:
   ```
   Buy 5 × silk @ 1,600 gp/load = 8,000 gp
   Entry toll (first transaction): 4 gp
   Loading labor: 1 gp
   Grand total: 8,005 gp
   ```
   When `monopolist_favor == -1` (active character is monopolist on buy), insert: "Monopolist favor: -1 (price reduced)" before the labor line.
6. **Validation label** — recomputes on every field change. Empty when valid; populated with rejection messages otherwise.
7. **Launch / Cancel buttons** at the footer.

**Validation cases:**
- "Select a merchant" (no merchant chosen)
- "Select a carrier" (no carrier chosen)
- "Insufficient loads" (`loads_count > merchant.loads_available`)
- "Carrier overflow" (`incremental_stone + used > load_max_stone`)
- "Insufficient party funds" (`total_cost > party.total_gp`)

The validation runs every field change; `Launch.disabled = not validation_message.is_empty()`.

**Section emits** `launch_requested("buy_merchandise", params, "settlement", settlement_id)` per §2.4 picker convention.

### 3.6 UI section — Sell mode (`mercantile_panel._build_sell_section()`)

The sell section's fields, top-to-bottom:

1. **Active character selector** — shared (per §2.8).
2. **Cargo dropdown** — party's cargo_holds rows (across all party carriers — both draft_vehicles and ships). Label format: `"<merchandise_type> × <loads_count> loads — <acquired_at_settlement_id_short> @ <market_value_at_acquisition_cp> gp/load"`. Stored metadata: the full cargo_holds row.
3. **Merchant dropdown** — visible merchants at this settlement whose `merchandise_type` matches the selected cargo. Auto-filters when cargo changes. Label format same as buy mode.
4. **Loads-to-sell SpinBox** — 1 to selected cargo's `loads_count`. Default: cargo's `loads_count` (i.e., "sell all by default"). Player can lower it for partial sell.
5. **Live preview label** — recomputes on every field change:
   ```
   Sell 5 × silk @ 2,600 gp/load = 13,000 gp gross
   Entry toll (first transaction): 10 gp
   Unloading labor: 1 gp
   Customs duty (4%): 520 gp
   Net proceeds: 12,469 gp
   ```
   When `is_domain_owner == true`: insert "Domain owner exemption: toll + customs waived" between gross and labor.
   When `monopolist_favor == +1`: insert "Monopolist favor: +1 (price increased)" before the entry-toll line.
6. **Validation label** + **Launch / Cancel buttons** as in buy mode.

**Validation cases:**
- "Select a cargo to sell"
- "No matching merchant — try locate_merchandise" (cargo selected but no visible merchant of that type)
- "Loads to sell exceeds cargo size"
- "Fees exceed proceeds — would owe X gp shortfall" (handler will try to absorb from party wallet but UI warns)

**Section emits** `launch_requested("sell_merchandise", params, "settlement", settlement_id)`.

### 3.7 Per-visit state integration (§9 forward reference)

The handler's `charge_entry_toll_if_first_visit` consults a new `VisitStateManager`. The state shape (designed fully in §9):

- `(party_id, settlement_id)` keyed: `{entry_calendar_day, entry_toll_paid_cp, active_character_at_entry}`.
- Cleared when party departs the settlement.
- Used by both `buy_merchandise` and `sell_merchandise` (and potentially `persuade_merchants` / `locate_merchandise` if those should also pay an entry toll on first launch per visit — RAW reading TBD §9).

The `mercantile_panel`'s live preview consults `VisitStateManager.has_paid_entry_toll` to decide whether to show "Entry toll (first transaction): X gp" or omit the line.

### 3.8 Monopoly registry integration (§8 forward reference)

The handler calls `MonopolyRegistry.favor_for_buy(character_id, settlement_id, merchandise_type) -> int` and `favor_for_sell(...)`. The full table design lands in §8. For Phase 10B.2 §3:

- `favor_for_buy` returns `-1` when active character holds the monopoly (lower buy price favors the holder); `0` otherwise.
- `favor_for_sell` returns `+1` when held; `0` otherwise.
- These integers feed `MarketPriceResolver.compute_market_price`'s `monopolist_favor` parameter directly.

In v1 with no monopolies granted yet, both helpers return 0 for every call. The plumbing is in place; population is later.

### 3.9 Partial-load handling (§13 forward reference)

Sell mode allows `loads_to_sell < cargo.loads_count`. This triggers `CargoHoldRepository.partial_sell` (new method designed in §13). The partial-sell path:
- Decrements `cargo.loads_count` by `loads_to_sell`
- Emits a `cargo_sold` signal with the partial-sale cp_received
- Does NOT delete the row (the residual cargo remains on the carrier)

The lost-vehicle edge case from Q-TB-6 (a wagon destroyed mid-transit with partial cargo) is handled separately in §13.

### 3.10 EventBus signal additions

Two new signals added to `event_bus.gd` (consolidated in §16):

```gdscript
# Phase 10B.2 trade transaction signals
signal merchandise_purchased(cargo_hold_id: String, settlement_id: String, merchandise_type: String, loads_count: int, total_cp_paid: int)
signal merchandise_sold(cargo_hold_id: String, settlement_id: String, merchandise_type: String, loads_count: int, net_cp_received: int)
```

These are higher-level than the existing `cargo_loaded` / `cargo_sold` signals (which fire from the repository layer). Trade-block signals carry transaction context (settlement, merchandise type, loads, net) for log / UI surfacing without consumers having to re-query the repository.

Existing repository-level signals (`cargo_loaded`, `cargo_sold`, `merchant_loads_consumed`, `merchant_depleted`) continue to fire as before. The new transaction signals are additive.

### 3.11 What §3 does NOT add

- **No transaction history persistence.** Receipts are returned by the handler and displayed in the UI but NOT persisted to the database. Future audit/ledger feature can add a `transaction_log` table; v1 keeps it transient. `[NEEDS-TRANSACTION-LOG-PASS]` flag if desired.
- **No "Buy All" / "Sell All" convenience macros.** The player picks loads per transaction. A future UI iteration can add quick-action buttons.
- **No real-time price ticker.** Prices are pinned for the cohort (cached `dice_4d4_value`); they don't change between visits except via the §6 drift mechanic.
- **No reservation system.** When the UI shows a merchant with 10 loads, two simultaneous players (impossible in single-player ACKS Arbiter but worth noting) would both see the same 10 loads. Single-player makes this moot.
- **No tax-by-purchase-source.** The customs duty applies to the SELL price regardless of how the goods were acquired (purchased / smuggled / stolen / shipping contract). The `source_acquisition_kind` is for audit + hijink-payout math, not customs.
- **No "negotiate price" mechanic.** Prices are formula-driven; the player can't haggle. RAW doesn't provide a haggle mechanic.
- **No multi-merchant batched transactions.** One transaction = one merchant. To buy from multiple merchants the player launches `buy_merchandise` multiple times.
- **No stabling charge** at transaction time. Stabling is per-stay, paid on settlement exit (§9 design).

---

## §4. Persuade Merchants — Reaction Roll + Merchant Lifecycle

### 4.0 Overview

`persuade_merchants` converts a visible merchant currently dealing in type X to deal in target type Y instead. RAW reaction roll: 9+ for Common (12+ for Precious). One roll per merchant; failure = "permanently lost." This section encodes the full mechanic + the LLM-promotion-aware failure handling per §0.1.1.

- **RAW citation:** `rules/acore-campaign-hijinks.xml:707-716` (`<finding_specific_goods>` block within step 3 of the market_arbitrage procedure).
- **What RAW provides:**

```
708: If adventurers want a particular type of merchandise, make a reaction roll for each merchant.
709: A result of 9+ is required to persuade a merchant to transact in a particular type of Common Merchandise.
710: A result of 12+ is required for a particular type of Precious Merchandise.
711: Add the demand modifier when seeking buyers.
712: Subtract the demand modifier when seeking sellers.
713: If the adventurer has a monopoly on that type of merchandise, he gains +3 on the roll.
714: Merchants transacting with a monopolist buy or sell twice the normal number of loads.
715: Only one roll per merchant is allowed; on failure, that merchant will not transact with the adventurer at all.
```

- **What's missing:** RAW's L714 ("twice the normal number of loads" for monopolists) is a **transaction-time** effect that affects `buy_merchandise` / `sell_merchandise` caps — not persuade_merchants itself. §3 didn't account for this; §4.11 documents the amendment to §3's per-transaction load cap. RAW is also silent on what happens to a merchant's `loads_available` when their `merchandise_type` is updated (project resolution in §4.6).
- **Project resolution:** the full reaction-roll mechanic encoded in §4.1-§4.5; success effect in §4.6; failure lifecycle in §4.7 (with the §0.1.1 LLM-promotion preservation path).

### 4.1 Reaction roll formula

```
roll_total = roll_2d6
           + cha_mod
           + proficiency_mods
           + signed_demand_modifier
           + monopolist_bonus
```

Success iff `roll_total >= threshold` where threshold is 9 for Common merchandise, 12 for Precious (§4.2).

- **`roll_2d6`** — 2d6 via the standard `dice` fixture pattern (matches `HenchmanLoyaltyResolver._roll_2d6`).
- **`cha_mod`** — active character's CHA ability modifier. Read via `CampaignRepository.get_character_ability_mod(character_id, "charisma")` (existing helper used by hiring reaction rolls).
- **`proficiency_mods`** — see §4.5.
- **`signed_demand_modifier`** — see §4.3 (sign depends on direction param).
- **`monopolist_bonus`** — see §4.4.

### 4.2 Threshold — common vs precious

- **RAW:** L709 (9+ Common) and L710 (12+ Precious).
- **Project resolution:** `MerchandiseRegistry.is_precious(target_merchandise_type)` returns the bucket (substrate §2.8 — already exported). Threshold lookup is one line:
  ```gdscript
  var threshold: int = 12 if MerchandiseRegistry.is_precious(target_merch_type) else 9
  ```

### 4.3 Direction parameter — signed demand modifier (Q-TB-8 RAW-faithful encoding)

The activity's `direction` param distinguishes "I want to buy this type" from "I want to sell this type." RAW L711-712 flips the sign:

- **`direction = "sell"`** (player wants the merchant to BUY from them; "seeking buyers"): **ADD** the demand modifier. High demand → easier to find a buyer (`+demand_mod` on the roll).
- **`direction = "buy"`** (player wants the merchant to SELL to them; "seeking sellers"): **SUBTRACT** the demand modifier. High demand → harder to find a seller (merchants hoard locally-demanded goods; `-demand_mod` on the roll).

```gdscript
var demand_mod: int = DemandModifierGenerator.get_demand_modifier(settlement_id, target_merch_type)
var signed_demand: int = demand_mod if direction == "sell" else -demand_mod
```

The signed demand modifier reflects RAW's economic intuition: persuading a merchant to deal in goods the LOCAL MARKET WANTS (high demand) makes them MORE eager to buy (push to consumers downstream) but LESS willing to sell (they want to hold their stock).

### 4.4 Monopolist bonus + cross-section impact

- **RAW L713:** monopolist gets +3 on the roll.
- **RAW L714:** monopolist transactions move 2× the normal number of loads (this is a SEPARATE effect on the buy/sell transaction, not on persuade_merchants).

For §4 the monopolist bonus is:
```gdscript
var monopolist_bonus: int = 3 if MonopolyRegistry.has_monopoly(character_id, settlement_id, target_merch_type) else 0
```

`MonopolyRegistry.has_monopoly(character_id, settlement_id, merchandise_type) -> bool` ships from §8 (the new helper). For v1 with no monopolies seeded, this always returns false → +0 bonus.

### 4.5 Charisma + proficiency modifiers

Per ACKS conventions (and the analogous L795-796 passenger reaction roll which explicitly enumerates them), reaction rolls add **Bribery / Diplomacy / Intimidation / Mystic Aura / Seduction** proficiency ranks. Per the lookup helper added in Prereq.6:

```gdscript
var prof_mods: int = 0
for prof_key in ["bribery", "diplomacy", "intimidation", "mystic_aura", "seduction"]:
    prof_mods += CampaignRepository.get_character_proficiency_rank(character_id, prof_key, "")
```

The handler sums all five even if most are 0. `[NEEDS-REACTION-PROFICIENCY-SUITE-PASS]` flag if a future system wants a unified "reaction roll modifier" helper consolidating these five proficiencies — for now, the handler enumerates them locally.

The two `[direction]` modifiers from RAW L711-712 affect the **demand component**, not the proficiency component — proficiencies always ADD regardless of direction.

### 4.6 Success effect — merchant type update

On success, the merchant's `merchandise_type` is updated to `target_merchandise_type`. The merchant's `loads_available` stays unchanged (RAW silent; project resolution: a merchant who agrees to deal in type Y has whatever stock they had before — the conversion is reputational/behavioral, not inventory-replacing).

```gdscript
CampaignRepository.db.query_with_bindings(
    "UPDATE merchant_pool SET merchandise_type = ? WHERE id = ?",
    [target_merchandise_type, merchant_id]
)
EventBus.merchant_persuaded.emit(merchant_id, settlement_id, old_type, target_merchandise_type)
```

**Why loads stay:** changing loads_available on persuasion would create a strange "loads reset on argument success" mechanic that RAW doesn't support. The merchant's loads_available is their per-cohort transaction budget (§3 model), and that budget doesn't increase because the player argued well.

**`old_type` in the signal payload** lets UI / log surface "Merchant X switched from wood_common to silk" for player clarity.

### 4.7 Failure effect — merchant lifecycle (LLM-promotion-aware per §0.1.1)

RAW L715: "on failure, that merchant will not transact with the adventurer at all."

Two paths per §0.1.1:

**Path A: Transactional merchant (`promoted_npc_id IS NULL`):** DELETE the row. The merchant is "permanently lost" per RAW. Next monthly refresh will create new transactional merchants in their place.

```gdscript
CampaignRepository.db.query_with_bindings(
    "DELETE FROM merchant_pool WHERE id = ? AND promoted_npc_id IS NULL",
    [merchant_id]
)
EventBus.merchant_persuasion_failed.emit(merchant_id, settlement_id, target_merchandise_type, "deleted")
```

**Path B: Promoted merchant (`promoted_npc_id IS NOT NULL`):** the merchant is an LLM-promoted NPC and SHOULD survive. Set a new `refused_at_calendar_day` column to the current day so the merchant is treated as "refusing to transact this cohort" without being deleted. Monthly refresh (§11 + §0.1.1) clears `refused_at_calendar_day` back to NULL when re-cycling the promoted row.

```gdscript
CampaignRepository.db.query_with_bindings(
    "UPDATE merchant_pool SET refused_at_calendar_day = ? WHERE id = ? AND promoted_npc_id IS NOT NULL",
    [Timekeeping.current_calendar_day(), merchant_id]
)
EventBus.merchant_persuasion_failed.emit(merchant_id, settlement_id, target_merchandise_type, "refused_cohort")
```

The signal's 4th param distinguishes the two paths so UI / log can render differently ("X left in a huff" for deleted; "X refuses to deal with you this month" for refused).

### 4.8 Schema addition — `refused_at_calendar_day` column on `merchant_pool`

Migration 104 (the first Phase 10B.2 migration) adds two columns to `merchant_pool`:

```sql
ALTER TABLE merchant_pool ADD COLUMN promoted_npc_id TEXT REFERENCES characters(id);
ALTER TABLE merchant_pool ADD COLUMN refused_at_calendar_day INTEGER;
```

- `promoted_npc_id` ships per §0.1.1's forward-compat anchor.
- `refused_at_calendar_day` enables the persuade-fail preservation path. NULL means "not refused this cohort"; a value means "refused as of this day, until cohort refresh clears it."

**Cohort-aware filtering** — the substrate's `MerchantPoolRepository.list_visible_merchants` / `list_visible_merchants_for_merchandise` queries get a new clause to skip refused merchants:

```gdscript
# Existing query gets one new condition appended:
"WHERE settlement_entrance_id = ? AND status = 'active'
   AND becomes_visible_calendar_day <= ?
   AND refused_at_calendar_day IS NULL"
```

The substrate-services patch ships in Phase 10B.2 as a small follow-up to the substrate's existing repository code. The change is additive (only filters refused rows out of the existing visible-pool results); no consumer of the existing API regresses because pre-Phase 10B.2 there are no refused rows.

### 4.9 Handler design — `persuade_merchants.gd`

```gdscript
class_name PersuadeMerchantsHandler
extends RefCounted

## persuade_merchants handler (Phase 10B.2 — Trade block).
## Per gdd-phase-10b-2-trade-block.md §4 + acore-campaign-hijinks.xml:707-716.

static func on_complete(state: Dictionary, _runner) -> Dictionary:
    var character_id: String = String(state.get("character_id", ""))
    var settlement_id: String = String(state.get("location_ref", ""))
    var params: Dictionary = state.get("params", {})

    var merchant_id: String = params.get("merchant_id", "")
    var target_merch_type: String = params.get("target_merchandise_type", "")
    var direction: String = params.get("direction", "buy")

    # 1. Validate.
    var merchant: Dictionary = MerchantPoolRepository.get_merchant(merchant_id)
    if merchant.is_empty() or String(merchant.get("status", "")) != "active":
        return {"summary": "persuade_merchants: merchant missing or inactive", "success": false}
    if String(merchant.get("merchandise_type", "")) == target_merch_type:
        return {"summary": "persuade_merchants: merchant already deals in %s" % target_merch_type, "success": false}
    if not (direction in ["buy", "sell"]):
        return {"summary": "persuade_merchants: invalid direction '%s'" % direction, "success": false}

    # 2. Build reaction-roll inputs.
    var cha_mod: int = CampaignRepository.get_character_ability_mod(character_id, "charisma")
    var prof_mods: int = 0
    for prof_key in ["bribery", "diplomacy", "intimidation", "mystic_aura", "seduction"]:
        prof_mods += CampaignRepository.get_character_proficiency_rank(character_id, prof_key, "")
    var demand_mod: int = DemandModifierGenerator.get_demand_modifier(settlement_id, target_merch_type)
    var signed_demand: int = demand_mod if direction == "sell" else -demand_mod
    var monopolist_bonus: int = 3 if MonopolyRegistry.has_monopoly(character_id, settlement_id, target_merch_type) else 0
    var threshold: int = 12 if MerchandiseRegistry.is_precious(target_merch_type) else 9

    # 3. Roll.
    var rng: RandomNumberGenerator = _persuade_rng(character_id, merchant_id)
    var roll: int = rng.randi_range(1, 6) + rng.randi_range(1, 6)
    var total: int = roll + cha_mod + prof_mods + signed_demand + monopolist_bonus
    var success: bool = total >= threshold

    # 4. Apply outcome.
    var old_type: String = String(merchant.get("merchandise_type", ""))
    if success:
        CampaignRepository.db.query_with_bindings(
            "UPDATE merchant_pool SET merchandise_type = ? WHERE id = ?",
            [target_merch_type, merchant_id])
        EventBus.merchant_persuaded.emit(merchant_id, settlement_id, old_type, target_merch_type)
    else:
        # §0.1.1 + §4.7 fork: DELETE transactional / refused-cohort promoted.
        var is_promoted: bool = merchant.get("promoted_npc_id", null) != null
        if is_promoted:
            CampaignRepository.db.query_with_bindings(
                "UPDATE merchant_pool SET refused_at_calendar_day = ? WHERE id = ?",
                [Timekeeping.current_calendar_day(), merchant_id])
            EventBus.merchant_persuasion_failed.emit(merchant_id, settlement_id, target_merch_type, "refused_cohort")
        else:
            CampaignRepository.db.query_with_bindings(
                "DELETE FROM merchant_pool WHERE id = ?", [merchant_id])
            EventBus.merchant_persuasion_failed.emit(merchant_id, settlement_id, target_merch_type, "deleted")

    return {
        "summary": "persuade_merchants: roll %d + mods %d = %d vs %d → %s" % [
            roll, cha_mod + prof_mods + signed_demand + monopolist_bonus, total, threshold,
            "success" if success else "failure"],
        "success": success,
        "roll_breakdown": {
            "roll_2d6": roll,
            "cha_mod": cha_mod,
            "proficiency_mods": prof_mods,
            "signed_demand_modifier": signed_demand,
            "monopolist_bonus": monopolist_bonus,
            "total": total,
            "threshold": threshold,
        },
    }


static func _persuade_rng(character_id: String, merchant_id: String) -> RandomNumberGenerator:
    # Deterministic per (character, merchant). Replay-safe; same character +
    # same merchant always produces the same persuade roll.
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("%s|%s|persuade" % [character_id, merchant_id])
    return rng
```

### 4.10 UI section — `mercantile_panel._build_persuade_section()`

Fields top-to-bottom:

1. **Active character selector** — shared across the panel (per §2.8).
2. **Merchant dropdown** — visible merchants at this settlement. Label: `"<id_short> — currently dealing in <current_type> (<loads_available> loads)"`.
3. **Target merchandise type dropdown** — all 31 merchandise types from `MerchandiseRegistry.all_merchandise()`. Filter out the currently-selected merchant's existing type (no point persuading them to deal in what they already deal in).
4. **Direction toggle** (two-button RadioButton group): `"Buy from them (seeking sellers)"` / `"Sell to them (seeking buyers)"`.
5. **Live preview** with the full roll breakdown:
   ```
   Reaction roll: 2d6 + CHA mod (+2) + Diplomacy 1 + signed demand mod (+3 for sell, -3 for buy)
                   + monopolist bonus (0) = average ~14 vs threshold 9 (Common: wood_common)
   Likely outcome: success
   ```
   The preview computes the AVERAGE 2d6 (7) + modifiers to show probable success/failure without rolling. RAW-faithful display of the gamble.
6. **Validation label** — "Select a merchant" / "Pick a different target type" etc.
7. **Launch / Cancel** at footer.

**Warning callout in the preview area:** "Failure permanently loses this merchant from the cohort (RAW)." Players should know what they're risking.

### 4.11 Cross-section amendment to §3 — monopolist 2× loads cap

Per RAW L714, monopolist transactions move 2× the normal number of loads. This amends §3's transaction handlers:

**§3.2 buy_merchandise validation update:**
```gdscript
var max_buyable: int = int(merchant.get("loads_available", 0))
if MonopolyRegistry.has_monopoly(character_id, settlement_id, merchandise_type):
    max_buyable *= 2
if loads_count > max_buyable:
    return {"summary": "buy_merchandise: requested %d > max %d (monopolist 2x bonus applied)" % [loads_count, max_buyable], "success": false}
```

The `consume_loads(merchant_id, loads_count)` substrate call still passes the actual `loads_count` (the merchant's stock decrements by the literal load count; the 2× is a cap-relaxation for the monopolist, not a free-loads multiplier).

Actually — wait. RAW L714: "Merchants transacting with a monopolist buy or sell **twice the normal number of loads**." Re-reading carefully:

- Interpretation A (cap-doubling): monopolist can transact UP TO 2× merchant.loads_available; merchant.loads_available depletes at the actual transaction rate.
- Interpretation B (loads-multiplier): each load the monopolist transacts COUNTS AS 1 toward merchant capacity but the player RECEIVES 2× the merchandise (or pays for 1× and gets 2×).
- Interpretation C (effective-doubling): merchant.loads_available is effectively double for this transaction; depletion is at 1× the actual count.

C is structurally identical to A — the cap doubles and depletion is normal. A and C are the same; B is different. RAW's literal phrasing "buy or sell twice the normal number of loads" reads as the QUANTITY transacted, not the cap. So B may be right.

**Project resolution:** Interpretation A/C (cap-doubling). Rationale: B (free loads multiplier) is unbalancing — a monopolist effectively gets +100% returns at zero cost. A is the more restrained reading and matches the "monopoly grants ACCESS to more inventory" intuition rather than "monopoly is a 2× cheat." If playtest reveals A undersells the value of monopoly, revisit per `[NEEDS-MONOPOLY-CAP-CALIBRATION]`.

**§3.3 sell_merchandise validation update:** sell mode has no explicit cap in v1 (per §3 design). Monopolist 2× cap only applies if we ADD a cap to sells. Since selling isn't capped, the L714 effect is buy-only in our implementation. `[NEEDS-MONOPOLY-CAP-CALIBRATION]` flag covers a future "do we cap sells?" decision.

### 4.12 EventBus signal additions

Two new signals added to `event_bus.gd` (consolidated in §16):

```gdscript
# Phase 10B.2 persuade-merchants signals
signal merchant_persuaded(merchant_id: String, settlement_id: String, old_merchandise_type: String, new_merchandise_type: String)
signal merchant_persuasion_failed(merchant_id: String, settlement_id: String, target_merchandise_type: String, outcome: String)
    # outcome ∈ {"deleted", "refused_cohort"}
```

### 4.13 What §4 does NOT add

- **No reaction-roll "twice failed = double penalty" mechanic.** RAW says one roll per merchant; success or failure is terminal. No second-chances.
- **No batched persuade-multiple-merchants flow.** One activity launch = one merchant. The activity panel offers `persuade_merchants` as a button; the player launches it per merchant.
- **No persuasion difficulty by relationship state.** Merchants have no "reputation" or "trust" axis beyond the per-merchant roll. Future LLM layer can layer relationship state on top of `promoted_npc_id` records.
- **No "merchant goes from depleted to active on persuade" recovery.** A `status='depleted'` merchant is not a persuasion target — the activity panel filters them out. Persuasion is only on `status='active'` merchants per §4.9 step 1 validation.
- **No proficiency-discovery UI.** The five proficiencies (Bribery/Diplomacy/etc.) contribute to the modifier silently. A future UI iteration could surface "your Diplomacy 1 helped here." For v1 the receipt's `roll_breakdown.proficiency_mods` is the data; UI rendering is a polish pass.
- **No `[NEEDS-REACTION-PROFICIENCY-SUITE-PASS]` consolidation.** Five inline `get_character_proficiency_rank` calls for v1. If a unified "reaction modifier suite" emerges (henchman loyalty, passenger trust, persuade_merchants, future bribery rolls), refactor then.
- **No "persuasion attempt log" persistence.** The roll_breakdown is returned by the handler for the UI receipt but not written to any history table. `[NEEDS-PERSUASION-LOG-PASS]` if audit/replay needs it.

---

## §5. Solicit Merchants — Ongoing 1-3 Week Reveal Schedule

### 5.0 Overview

`solicit_merchants` is the 3-week Ongoing activity that reveals invisible merchants in the cohort on a staggered schedule. The substrate (`MerchantPoolRepository.process_solicitation`) already ships the schedule-assignment math; this section designs the activity handler shell around it: per-day presence accounting, forfeiture rollback for unfired reveals (resolves the substrate-vs-Q-TB-15 tension), domain-owner edge handling, and the UI section.

- **RAW citation:** `rules/acore-campaign-hijinks.xml:679-684` (the timing-of-availability subsection of arbitrage step 2) + `rules/ax_campaign_play.xml:949-963` (the player-activity definition).
- **What RAW provides:**
  - Ongoing 1-3 week minor unstrenuous activity.
  - Half the merchants (rounded up) become interested in week 1.
  - One quarter (rounded down, minimum 1) in week 2.
  - Remainder in week 3.
  - Domain owner has access to maximum merchants without rolling.
- **What's missing:**
  1. Daily-presence semantics — does the player have to be at the market every day, or can they walk away after launching?
  2. Forfeiture handling — if the player departs early, do already-scheduled-but-unfired reveals still fire on schedule, or roll back?
  3. Early-completion when all reveals fire before day 21.
  4. Edge cases: domain-owned settlement (always visible), tiny pools (Class VI N=2), zero-invisible-pool (the substrate already rejects).
- **Project resolution:** §5.1-§5.6 design each. Substrate's `process_solicitation` is reused for the schedule math; this section adds the activity-lifecycle wrapper.

### 5.1 Daily 1-hour presence requirement (Q-TB-15 resolution)

Per Q-TB-15 [RESOLVED 2026-05-13]: "Ongoing minor activity, it needs to be performed for one hour each day. Probably becomes_visible_calendar_day polling each day."

**Project resolution:** the activity has a per-day-presence requirement enforced by the existing `ActivityTimeCostExecutor` ongoing-activity machinery (per §32 conventions). Each game day:

1. The executor advances the activity's tick count by 1 (consuming `minor_activity` rounds-worth of session time).
2. The executor checks the activity's prerequisites are still met — specifically `at_market_poi`. If the party has departed the market (or the settlement entirely), `at_market_poi` fails and the activity forfeits.
3. If presence holds, the activity continues toward its 21-day completion.

**Reveal-firing is time-driven, not tick-driven.** The substrate's `list_visible_merchants` query reads `becomes_visible_calendar_day <= current_calendar_day` — once the calendar day reaches a scheduled reveal day, the merchant becomes visible regardless of activity state. This means the player sees the merchants as the calendar advances WHILE THE ACTIVITY REMAINS ACTIVE.

**Forfeiture rolls back UNFIRED reveals.** If the player departs before day 21, any `becomes_visible_calendar_day` values strictly greater than the current day (i.e., scheduled but not yet fired) get reset to `INVISIBLE_SENTINEL`. Already-fired reveals stay visible — the player got those merchants and forfeit doesn't undo earned progress.

This resolves the apparent substrate-vs-Q-TB-15 tension: the substrate's `process_solicitation` sets DAYS, not flags. The activity handler enforces the FORFEITURE contract on top — if you walked away, the unspent days "didn't pay out."

### 5.2 Reveal schedule (substrate §7.5.1 recap)

The substrate's `MerchantPoolRepository.process_solicitation(settlement_id, character_id, current_day)` does the schedule math:

| N (invisible pool size) | First half (day +7) | Second quarter (day +14) | Remainder (day +21) |
|---|---|---|---|
| 1 | 1 | 0 (clamped) | 0 |
| 2 (Class VI) | 1 | 1 | 0 |
| 3 (Class V) | 2 | 1 | 0 |
| 4 (Class IV) | 2 | 1 | 1 |
| 8 (Class III) | 4 | 2 | 2 |
| 9 (Class II) | 5 | 2 | 2 |
| 14 (Class I) | 7 | 3 | 4 |

The handler invokes `process_solicitation` ONCE in `on_started`; the substrate writes the `becomes_visible_calendar_day` values and emits the existing `solicitation_started` signal.

### 5.3 Activity entry points

Per §32 ongoing-activity convention, four entry points:

| Entry point | Trigger | Responsibility |
|---|---|---|
| `on_started(state, runner)` | Activity launch (turn 0) | Invoke substrate `process_solicitation`. Record `started_at_calendar_day` in `state.params` for rollback attribution. Reject with summary if substrate returns `success=false` (already-revealed pool). |
| `on_tick(state, runner)` | Every day after `on_started` | No-op for v1 (the executor's per-tick presence check is the load-bearing logic; the handler doesn't need to do anything per-tick). Optionally emits a UI-refresh signal. |
| `on_completed(state, runner)` | After `default_ticks_required` days (21) | Emit `solicit_merchants_completed`. No state cleanup needed — fully-fired reveals are permanent. |
| `on_forfeited(state, runner)` | Prerequisites fail mid-activity (player departed, etc.) | Execute the §5.4 rollback. Emit `solicit_merchants_forfeited`. |

### 5.4 Forfeit rollback algorithm

When the activity is forfeited, any reveals scheduled by THIS solicit instance that haven't fired yet get rolled back to `INVISIBLE_SENTINEL`. The recorded `started_at_calendar_day` (in state.params) provides attribution — reveals scheduled for `started_at_calendar_day + {7, 14, 21}` belong to this solicit.

```gdscript
static func on_forfeited(state: Dictionary, _runner) -> void:
    var settlement_id: String = String(state.get("location_ref", ""))
    var start_day: int = int(state.get("params", {}).get("started_at_calendar_day", 0))
    var current_day: int = Timekeeping.current_calendar_day()

    # Compile the list of scheduled-but-unfired reveal days for THIS solicit.
    var unfired_reveal_days: Array = []
    for offset in [7, 14, 21]:
        var reveal_day: int = start_day + offset
        if reveal_day > current_day:
            unfired_reveal_days.append(reveal_day)

    if unfired_reveal_days.is_empty():
        # All reveals already fired before forfeit — nothing to roll back.
        EventBus.solicit_merchants_forfeited.emit(settlement_id, String(state.get("character_id", "")), 0)
        return

    # Find and roll back merchants whose becomes_visible_calendar_day matches
    # one of this solicit's scheduled reveal days AND hasn't fired yet AND is
    # a transactional row (not promoted/manual — those are exempt from solicit
    # mutation per §0.1.1).
    var sentinel: int = MerchantPoolRepository.INVISIBLE_SENTINEL
    var placeholder_list: String = ", ".join(unfired_reveal_days.map(func(_d): return "?"))
    var sql: String = """
        UPDATE merchant_pool
        SET becomes_visible_calendar_day = ?
        WHERE settlement_entrance_id = ?
          AND status = 'active'
          AND source_kind = 'monthly_refresh'
          AND promoted_npc_id IS NULL
          AND becomes_visible_calendar_day IN (%s)
    """ % placeholder_list
    var bindings: Array = [sentinel, settlement_id] + unfired_reveal_days

    CampaignRepository.db.query_with_bindings(sql, bindings)
    var rolled_back: int = CampaignRepository.db.query_result.size()  # rows affected if backend supports it

    EventBus.solicit_merchants_forfeited.emit(
        settlement_id, String(state.get("character_id", "")), rolled_back)
```

**Why the `source_kind = 'monthly_refresh'` + `promoted_npc_id IS NULL` filters:**
- **`'monthly_refresh'`** — solicit only manipulates the auto-generated cohort, not Judge-authored `'manual'` rows.
- **`promoted_npc_id IS NULL`** — per §0.1.1, promoted NPC merchants are NOT subject to solicit-driven visibility rollback; they're persistent across cohorts and their visibility lifecycle is independent.

**Edge: same reveal day, multiple sources.** If two solicits launched on consecutive cohorts both happen to schedule a reveal for the same future day (rare but possible with month-boundary timing), the rollback could affect both. In single-party ACKS Arbiter only one solicit can be active at a time per party, but if a previous solicit was forfeited and a fresh one launched later, the rollback could touch merchants from the older solicit's residual scheduling. **Project resolution for v1:** the older solicit's residual scheduling would have been rolled back when IT was forfeited. The current solicit only owns its own days. Net effect: no false-positive rollbacks in single-party. Multi-party future is `[NEEDS-MULTI-PARTY-SOLICIT-PASS]`.

### 5.5 Activity duration — always 21 days

`duration_formula: "21"` per §1.3.3. The activity runs the full 3 weeks regardless of pool size.

- **Class VI N=2 case:** all reveals fire by day 14. Player can `cancel` the activity from day 14 onward (manual exit) — the cancel-after-full-reveal-completion is just a forfeit AFTER all unfired-reveal days are past current_day, so the rollback is a no-op. Player keeps the revealed merchants.
- **Class I N=14 case:** the 21-day commit is well-spent; reveals span all three weeks.
- **Why not "early complete when all reveals fire":** would require attribution tracking + a per-tick reveal-counting check. The cancel-after-completion pattern (above) achieves the same UX without the complexity. The activity panel UI surfaces "All reveals fired — you can leave anytime now" status after day 14 (for small pools) to make the option visible.

### 5.6 Domain-owner edge case

Per substrate GDD §7.4: PC-owned domain settlements get instant-visibility merchants at monthly refresh (`becomes_visible_calendar_day = generation_day`). At any time the player visits, `list_invisible_merchants` returns empty.

The `solicit_merchants` activity's `invisible_merchants_remaining` prerequisite (§1.5) catches this BEFORE the activity launches:

- Activity panel renders the `solicit_merchants` button DISABLED with tooltip "Pool fully revealed — your domain status grants immediate access."
- If the player somehow launches it anyway (e.g., race condition with a fresh-cohort timing), the handler's `on_started` rejects via substrate's `process_solicitation` returning `success=false, error='already_revealed'`.

This is the existing substrate behavior — no new logic needed.

### 5.7 Handler design — `solicit_merchants.gd`

```gdscript
class_name SolicitMerchantsHandler
extends RefCounted

## solicit_merchants handler (Phase 10B.2 — Trade block).
## Ongoing 21-day minor activity. Per gdd-phase-10b-2-trade-block.md §5 +
## substrate gdd-settlement-economy.md §7.5.1.

static func on_started(state: Dictionary, _runner) -> Dictionary:
    var character_id: String = String(state.get("character_id", ""))
    var settlement_id: String = String(state.get("location_ref", ""))
    var current_day: int = Timekeeping.current_calendar_day()

    # Delegate the schedule math to the substrate.
    var result: Dictionary = MerchantPoolRepository.process_solicitation(
        settlement_id, character_id, current_day)
    if not bool(result.get("success", false)):
        return {
            "summary": "solicit_merchants rejected: %s" % str(result.get("error", "unknown")),
            "success": false,
        }

    # Record start_day for rollback attribution.
    var params: Dictionary = state.get("params", {})
    params["started_at_calendar_day"] = current_day
    state["params"] = params

    return {
        "summary": "Solicit started: %d merchants will reveal over 3 weeks." % int(result.get("merchants_revealed", 0)),
        "success": true,
    }


static func on_tick(state: Dictionary, _runner) -> Dictionary:
    # Per-day no-op. The executor's prerequisite check handles forfeiture-on-
    # departure; reveals fire time-driven via the substrate's visibility query.
    return {}


static func on_completed(state: Dictionary, _runner) -> Dictionary:
    var settlement_id: String = String(state.get("location_ref", ""))
    var character_id: String = String(state.get("character_id", ""))
    EventBus.solicit_merchants_completed.emit(settlement_id, character_id)
    return {"summary": "Solicit completed: full 3-week pool reveal done."}


static func on_forfeited(state: Dictionary, _runner) -> void:
    # §5.4 rollback algorithm.
    var settlement_id: String = String(state.get("location_ref", ""))
    var start_day: int = int(state.get("params", {}).get("started_at_calendar_day", 0))
    var current_day: int = Timekeeping.current_calendar_day()

    var unfired_reveal_days: Array = []
    for offset in [7, 14, 21]:
        var reveal_day: int = start_day + offset
        if reveal_day > current_day:
            unfired_reveal_days.append(reveal_day)

    var rolled_back: int = 0
    if not unfired_reveal_days.is_empty():
        var sentinel: int = MerchantPoolRepository.INVISIBLE_SENTINEL
        var placeholder_list: String = ", ".join(unfired_reveal_days.map(func(_d): return "?"))
        var bindings: Array = [sentinel, settlement_id] + unfired_reveal_days
        var sql: String = """
            UPDATE merchant_pool
            SET becomes_visible_calendar_day = ?
            WHERE settlement_entrance_id = ?
              AND status = 'active'
              AND source_kind = 'monthly_refresh'
              AND promoted_npc_id IS NULL
              AND becomes_visible_calendar_day IN (%s)
        """ % placeholder_list
        CampaignRepository.db.query_with_bindings(sql, bindings)
        # SQLite via godot-sqlite doesn't return affected-row count directly;
        # if metric is needed, pre-count via SELECT before UPDATE.
        rolled_back = unfired_reveal_days.size()  # approximate (count of reveal-days touched, not rows)

    EventBus.solicit_merchants_forfeited.emit(
        settlement_id, String(state.get("character_id", "")), rolled_back)
```

### 5.8 UI section — `mercantile_panel._build_solicit_section()`

The solicit section is fields-light. The substrate's schedule is deterministic given the invisible pool count and the current day; the UI surfaces this as a preview.

Fields top-to-bottom:

1. **Active character selector** — shared (per §2.8).
2. **Schedule preview panel** (read-only Label, not a field):
   ```
   You will solicit the market for 3 weeks (1 hour each day).
   
   Today: 8 invisible merchants will be revealed on the following schedule:
   • Day 7 (1 week from now): 4 merchants
   • Day 14 (2 weeks from now): 2 merchants  
   • Day 21 (3 weeks from now): 2 merchants
   
   The cohort refreshes on day 28; any merchants not revealed by then
   will be lost.
   
   ⚠ If you depart the market early, the unfired reveals will roll back.
   ```
   The 4/2/2 split is computed live by reading `MerchantPoolRepository.list_invisible_merchants(settlement_id, current_day).size()` and applying the substrate's thirds formula.
3. **Validation label** — typically empty since the prereq gate already filtered the activity. Edge cases:
   - "Pool already fully revealed" (race with monthly refresh — rare)
4. **Launch / Cancel** at footer.

**No merchandise-type filter, no merchant filter:** solicit operates on the whole invisible pool. The player has no per-target control.

### 5.9 EventBus signal additions

Two new signals added to `event_bus.gd` (consolidated in §16). The substrate's `solicitation_started` is reused for the launch event:

```gdscript
# Phase 10B.2 solicit-merchants signals
signal solicit_merchants_completed(settlement_id: String, character_id: String)
signal solicit_merchants_forfeited(settlement_id: String, character_id: String, unfired_reveals_rolled_back: int)
```

The substrate's `solicitation_started(settlement_id, character_id, merchants_revealed_count)` fires from `process_solicitation` during `on_started`. No duplication needed.

### 5.10 Cross-section impacts

- **§4's `refused_at_calendar_day` column does NOT interact with solicit.** Refused merchants are visible-but-non-transactable; solicit only changes invisible → visible. Orthogonal concerns.
- **§0.1.1's `promoted_npc_id` is honored** — promoted NPCs are skipped by the forfeit rollback (the `promoted_npc_id IS NULL` filter on the UPDATE).
- **§7's shipping_contract_offer-rolling at market entry does NOT interact with solicit.** Solicit is about merchant visibility; offers are separate transient state.
- **§9's per-visit entry-toll first-fire** — `solicit_merchants` is one of the activities that triggers the first-fire on launch. Once paid, subsequent buy_sell / persuade / locate activities within the same visit don't re-charge. Same logic as `buy_merchandise`.

### 5.11 What §5 does NOT add

- **No mid-activity progress display.** The UI shows the schedule preview before launch; it doesn't render a daily progress tracker after launch. Future polish.
- **No early-completion detection.** Activity always runs 21 days; player can cancel manually after all reveals fire (which is a forfeit-with-zero-rollback).
- **No batched-solicit-across-multiple-settlements.** One settlement per activity instance. Future polish if multi-domain players want a "solicit my whole realm" macro.
- **No solicit failure modes.** RAW doesn't define a failure case; solicit just runs and reveals on schedule. The only "failure" is forfeit (player walks away early).
- **No cooldown between solicits.** Per substrate §7.5.1, "the next `solicit_merchants` after refresh sees a fresh invisible set and works normally. Within a cohort, a second `solicit_merchants` call finds zero invisible merchants and rejects." Cooldown is implicit via the cohort lifecycle.
- **No merchant-attribution column.** The forfeit rollback uses the start_day + {7,14,21} pattern rather than tagging each merchant with the solicit instance that scheduled them. Simpler; works for single-party. `[NEEDS-MULTI-PARTY-SOLICIT-PASS]` covers the future.

---

## §6. Locate Merchandise — Targeted 1-Hour Reveal

### 6.0 Overview

`locate_merchandise` lets the player target a specific merchandise type and surface ONE invisible merchant carrying it (alter-not-spawn semantics per substrate §7.5.2). Singular minor activity, 1 hour of game time. The substrate's `MerchantPoolRepository.process_locate(settlement_id, merchandise_type, current_calendar_day) -> Dictionary` does the work; this section ships the handler shell + picker UI.

- **RAW citation:** `rules/acore-campaign-hijinks.xml:707-715` (the alter-not-spawn reading of "finding specific goods" — RAW says persuade existing merchants; v1 splits this between `locate_merchandise` for the invisible-pool case and `persuade_merchants` for the wrong-type-merchant case).
- **What RAW provides:** the conceptual basis — "find specific merchandise" is a player action; merchants can be alter (not spawned).
- **What's missing:** RAW doesn't separate the invisible-but-already-carries vs visible-but-wrong-type cases. The substrate split them per §7.5.2.
- **Project resolution:** locate is the invisible-carries case. Reveals one merchant; failure suggests persuade.

### 6.1 Three outcomes (substrate semantics recap)

Per substrate `MerchantPoolRepository.process_locate`:

| Outcome | Trigger | Return |
|---|---|---|
| **No-op success** | Visible match already exists for the requested type | `{success: true, surfaced_now: false, merchant_id: <existing_id>}` |
| **Surface success** | Invisible match exists; one is surfaced | `{success: true, surfaced_now: true, merchant_id: <surfaced_id>}`. Emits `merchant_surfaced_via_locate` signal. |
| **No-match failure** | Neither visible nor invisible match exists for the requested type in this cohort | `{success: false, error: "no_merchant_of_type"}`. The player still spent the 1 hour (game time advances). |

The handler is a thin wrapper around `process_locate` plus the per-visit-toll first-fire logic.

### 6.2 Handler design — `locate_merchandise.gd`

```gdscript
class_name LocateMerchandiseHandler
extends RefCounted

## locate_merchandise handler (Phase 10B.2 — Trade block).
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §6 +
## substrate gdd-settlement-economy.md §7.5.2.

static func on_complete(state: Dictionary, _runner) -> Dictionary:
    var character_id: String = String(state.get("character_id", ""))
    var settlement_id: String = String(state.get("location_ref", ""))
    var params: Dictionary = state.get("params", {})
    var merchandise_type: String = String(params.get("merchandise_type", ""))

    if merchandise_type.is_empty():
        return {"summary": "locate_merchandise: empty merchandise_type param", "success": false}

    # 1. Per-visit entry toll first-fire (§9). Locate is one of the activities
    #    that triggers entry-toll first-fire — player has to enter the market
    #    to ask around even if they don't buy/sell.
    var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
    if party_id.is_empty():
        return {"summary": "locate_merchandise: no party for active character", "success": false}
    var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
    var toll_charge: int = BuySellCommon.charge_entry_toll_if_first_visit(
        party_id, settlement_id, false, 0, rng)  # is_selling=false

    # 2. Delegate to substrate.
    var current_day: int = Timekeeping.current_calendar_day()
    var result: Dictionary = MerchantPoolRepository.process_locate(
        settlement_id, merchandise_type, current_day)

    # 3. Translate substrate outcome to handler return.
    var outcome_summary: String = ""
    if bool(result.get("success", false)):
        if bool(result.get("surfaced_now", false)):
            outcome_summary = "Located a %s merchant — they are now visible at the market." % merchandise_type
        else:
            outcome_summary = "A %s merchant is already visible at the market." % merchandise_type
    else:
        outcome_summary = "No %s merchant in this market's pool. Try persuading another merchant to deal in %s." % [merchandise_type, merchandise_type]

    return {
        "summary": outcome_summary,
        "success": bool(result.get("success", false)),
        "surfaced_now": bool(result.get("surfaced_now", false)),
        "merchant_id": String(result.get("merchant_id", "")),
        "entry_toll_cp": toll_charge,
    }
```

**Notable design points:**
- **Toll fires regardless of outcome.** Per RAW the toll is for entering the market, not for transacting successfully. A locate that fails (no merchant of type) still pays the first-time toll.
- **The "try persuading" hint in the failure summary** surfaces the §7.5.2 fall-through path described in the substrate GDD. The UI's receipt rendering can highlight this as a clickable suggestion that pre-fills the persuade_merchants picker with the same merchandise_type.
- **Game time advances on failure** per substrate §7.5.2: "The action's 1 hour was still spent (game time advances)." The activity-system's standard tick accounting handles this — the handler doesn't need to do anything special.

### 6.3 UI section — `mercantile_panel._build_locate_section()`

Fields top-to-bottom:

1. **Active character selector** — shared (per §2.8).
2. **Merchandise type dropdown** — all 31 merchandise types from `MerchandiseRegistry.all_merchandise()`. Label format: `"<display_name> (<bucket>)"` e.g., `"Silk (Precious, 2,000 gp base)"`. Stored metadata: `merchandise_type` string.
3. **Live preview label** — quick state read on the selected type:
   ```
   Targeting: Silk
   At this market: 0 visible silk merchants, 1 invisible silk merchant
   Outcome estimate: locating will surface the invisible merchant.
   
   Entry toll (first transaction this visit): 4 gp (Class V)
   Game time cost: 1 hour
   ```
   The preview queries `MerchantPoolRepository.list_visible_merchants_for_merchandise(settlement_id, merchandise_type, current_day).size()` and `list_invisible_merchants(...).size()` filtered by type. If both are 0, the preview reads: "Outcome estimate: no merchant of this type in the pool — locating will fail. Consider persuading another merchant to deal in silk instead."
4. **Validation label** — typically empty; the activity gracefully fails on no-match per §6.2, so the player can launch even when the outcome will be a failure (they spend 1 hour finding out). Edge: "Select a merchandise type" if no dropdown selection.
5. **Launch / Cancel** at footer.

**No pre-emptive blocking on no-match outcome.** Per §1.5 the `locate_merchandise` prerequisite is just `at_market_poi` — the activity is always available at a market POI. The player CAN launch a locate they know will fail (e.g., to advance game time intentionally). The UI's preview just informs them.

### 6.4 Fall-through to persuade_merchants

When `locate_merchandise` fails with `no_merchant_of_type`, the receipt's UI rendering surfaces a one-click "Persuade a merchant to deal in <type> instead" link. Clicking it:

1. Closes the locate receipt.
2. Opens the mercantile panel's `persuade_section`.
3. Pre-fills `target_merchandise_type` with the failed locate's type.
4. Leaves merchant + direction empty for the player to choose.

This is a UI polish — not strictly required for v1 functional correctness but valuable for player flow. Implementation lives in the receipt rendering code; design pattern matches existing receipt-with-cta surfaces (e.g., shop failure flows).

`[NEEDS-LOCATE-FALL-THROUGH-CTA-PASS]` flag if v1 ships without this CTA — the manual-navigate path (player closes locate panel, opens persuade panel, types the same merch type) still works.

### 6.5 EventBus signal usage

No new signals. The substrate already emits `merchant_surfaced_via_locate(merchant_id, settlement_id, merchandise_type)` from `process_locate` when a surface happens. The handler returns its receipt; the UI consumes the return value directly.

If a future audit-history pass wants a "locate attempt" signal (including failures), add it then. v1 doesn't need it.

### 6.6 What §6 does NOT add

- **No batched-locate.** One type per launch. To locate multiple types the player launches multiple times (1 hour each).
- **No "search across multiple settlements" flow.** Locate is per-settlement. Multi-settlement search is the player walking to each settlement and locating.
- **No locate-merchandise-then-buy macro.** A separate buy_merchandise launch follows. Future polish if the workflow feels heavy.
- **No locate-failure-spawns-merchant fallback.** The substrate's alter-not-spawn rule holds. `[NEEDS-MERCHANT-SOURCING-PASS]` flag (carried from substrate §7.5.2) covers the future enhancement where a connected trade route could import a missing merchant type.
- **No "locate ALL the merchandise types I want" macro.** Out of scope; players select one type at a time.
- **No precious-merchandise difficulty modifier.** RAW doesn't distinguish for locate (unlike persuade where precious is 12+ vs 9+). Locate is a flat-outcome activity — find or don't.

---

## §7. Accept Shipping Contract — Fresh Offers + Carrier Selection + Delivery Flow

### 7.0 Overview

The shipping-contracts activity lets the player accept a freight-haulage job at a market: a shipper at this settlement offers gp to haul N loads of cargo to a destination settlement by a deadline. The substrate's `ShippingContractRepository` (`accept_contract` / `deliver` / `cancel` / `list_active_for_party`) handles the lifecycle once the player accepts. This section ships the **offer-rolling mechanism that produces accept-able offers** plus the **handler + UI** that wires the player's accept choice into the substrate.

- **RAW citation:** `rules/acore-campaign-hijinks.xml:765-837` (`<passenger_and_cargo_transport>`), specifically:
  - L777-783 — per-class quantity table (offers count + cargo size)
  - L788-791 — destination 1d20 mechanic (19+ distant; otherwise nearest within ±1 size class along route)
  - L811-826 — `<shipping_contracts>` rules (separate from passenger rules)
  - L815 — reaction roll 9+ to secure
  - L816-819 — fee formula (sea vs road)
  - L820-825 — cargo details (typically mixed, ~70 stone/load assumption)
  - L828-832 — staggered 1-3 week interest timing (same mechanism as solicit_merchants)

- **What RAW provides:** complete mechanism for generating contract offers + accepting + paying.
- **What's missing:**
  1. Persistence model — the offers are transient (rolled per visit). Schema is project-design.
  2. Destination resolution depends on the player's "destination" (RAW L791 "along route to adventurer's destination"); the project doesn't track an in-game travel destination concept.
  3. Mixed-cargo "70 stone/load" assumption (L822) requires merchandise_type modeling — project chooses to treat the cargo as `merchandise_type='mixed_cargo'` (a sentinel value outside the 31-type registry) for v1.
  4. The 1-3 week staggered availability (L828-832) parallels solicit_merchants but adds significant complexity (a second cohort with its own visibility tracking). Deferred per `[NEEDS-CONTRACT-STAGGERED-AVAILABILITY-PASS]`.
  5. The 9+ reaction roll per contract (L815) parallels persuade_merchants. For v1 simplification, contracts are offered without a reaction-roll gate. `[NEEDS-CONTRACT-TRUST-ROLL-PASS]` flag for the future RAW-complete pass.
- **Project resolution:** v1 ships a simplified offer-rolling mechanism — per-visit refresh on market entry, no staggered reveal, no trust roll. The RAW-complete enhancements are flagged.

### 7.1 Offer count per market class

The per-class quantity table from RAW L777-783, project-coded directly:

| Market Class | Contracts Dice | Cargo per Contract |
|---|---|---|
| I | 2d6+2 | 6d8 loads |
| II | 2d4+1 | 4d6 loads |
| III | 2d4 | 3d4 loads |
| IV | 1d4 | 2d4 loads |
| V | 1d4-1 | 1d4 loads |
| VI | 1d3-1 | 1d2 loads |

Note Class V and VI can roll 0 contracts (minimum value of `1d4-1` is 0). When this happens, no offers — the activity is unlockable but the activity panel button's `shipping_offer_present` prereq remains false (gate stays disabled).

These tables are encoded in the new `ShippingContractOfferRoller` service (§7.6) as a const dictionary mirroring `MerchantPoolRepository.MARKETS_AND_MERCHANTS`.

### 7.2 Schema — `shipping_contract_offers` table

The new `shipping_contract_offers` table holds transient per-visit offers. Migration 105 (the second Phase 10B.2 migration after §4's 104):

```sql
CREATE TABLE IF NOT EXISTS shipping_contract_offers (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    party_id                        TEXT    NOT NULL REFERENCES parties(id),
    origin_settlement_id            TEXT    NOT NULL REFERENCES settlement_entrances(id),
    destination_settlement_id       TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    loads_count                     INTEGER NOT NULL DEFAULT 0,
    load_weight_stone               INTEGER NOT NULL DEFAULT 0,
    route_mode                      TEXT    NOT NULL DEFAULT 'road'
        CHECK(route_mode IN ('road', 'water')),
    distance_miles                  INTEGER NOT NULL DEFAULT 0,
    fee_cp                          INTEGER NOT NULL DEFAULT 0,
    deadline_calendar_day           INTEGER NOT NULL DEFAULT 0,
    rolled_at_calendar_day          INTEGER NOT NULL DEFAULT 0,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_shipping_contract_offers_party
    ON shipping_contract_offers(party_id, origin_settlement_id);
```

**Field rationale:**
- `id` — UUID. Used as the `offer_id` in the accept handler's param.
- `party_id` — offers are scoped to the party that entered the market. Other parties (multi-party future) get their own rolls.
- `origin_settlement_id` — where the offer was rolled (the player accepted-at settlement).
- `destination_settlement_id` — where the cargo must be delivered.
- `merchandise_type` — `'mixed_cargo'` sentinel for v1 (per RAW L822 "mixed cargo at 70 stone per load" simplification). Future enhancement could roll on the Common Merchandise table per L822 alternative reading.
- `loads_count` — rolled from the per-class cargo dice (§7.1).
- `load_weight_stone` — 70 for mixed_cargo per RAW.
- `route_mode` — `'road'` or `'water'`. Resolved at roll-time via substrate `TradeRouteDetector.compute_road_distance` / `compute_water_distance`. Determines the fee formula AND the carrier-kind constraint at accept time.
- `distance_miles` — used for fee math + display.
- `fee_cp` — rolled fee per §7.4.
- `deadline_calendar_day` — computed deadline per §7.5.
- `rolled_at_calendar_day` — for save/load determinism + cleanup.

**Persistence semantics:** rows are INSERTed when the party enters a market (per §7.6 lifecycle); they're DELETEd when the party departs the settlement (cleanup tied to the per-visit state from §9).

### 7.3 Destination resolution + route mode

For v1, simplified destination logic (full RAW L788-791 deferred per `[NEEDS-CONTRACT-DESTINATION-RAW-COMPLETE-PASS]`):

1. **Enumerate candidate destinations:** every other settlement in the campaign EXCEPT the origin.
2. **Filter by reachability:**
   - For each candidate, compute `road_distance = TradeRouteDetector.compute_road_distance(origin_id, candidate_id)` and `water_distance = compute_water_distance(...)`.
   - Discard candidates with both distances = -1 (unreachable from origin).
3. **Pick destination randomly** from the reachable set (uniform, seeded per `(party_id, origin_id, current_day, offer_index)`).
4. **Pick route mode:**
   - If both road + water valid: prefer the mode whose fee yields HIGHER gp for the shipper-pays-the-player perspective. With RAW fees (1gp/10stone/150mi road vs 1gp/10stone/500mi sea), road pays more per mile, so road is preferred when distance × stone is meaningful.
   - **Project simplification:** always prefer road when both available. Water only when road is -1.
5. **Distance:** convert the chosen mode's hex distance to miles via `Timekeeping.miles_per_hex()` or similar (existing project convention — likely 6 mi/hex for regional maps).

If the candidate set is empty (no reachable settlements at all — rare, e.g., isolated wilderness outpost), no contracts roll. The offers list is empty.

**`[NEEDS-CONTRACT-DESTINATION-RAW-COMPLETE-PASS]` flag** for the full RAW mechanic: 1d20 with 19+ = distant (player-chosen target 2d20×100 miles away) and otherwise nearest within ±1 size class along the player's intended route. This requires tracking player intent (an in-game "travel goal" concept) which the project doesn't model yet.

### 7.4 Fee formula

Per RAW L817-819:

```gdscript
static func compute_fee_cp(total_stone: int, distance_miles: int, route_mode: String) -> int:
    var divisor_miles: int = 150 if route_mode == "road" else 500  # road: 1gp/10stone/150mi; sea: 1gp/10stone/500mi
    var per_stone_units: int = ceili(float(total_stone) / 10.0)
    var distance_units: int = ceili(float(distance_miles) / float(divisor_miles))
    return per_stone_units * distance_units
```

The two `ceili` calls match RAW's "rounded up" semantics literally. For a contract of 10 loads × 70 stone/load = 700 stone over 300 miles by road:
- per_stone_units = ceili(700 / 10) = 70
- distance_units = ceili(300 / 150) = 2
- fee_cp = 70 × 2 × 100 = 14,000 cp (= 140 gp)

Per RAW L824: "Shippers generally pay half in advance and the balance, through an agent, on safe arrival." **Project simplification for v1:** the full fee is paid on delivery, no advance. `[NEEDS-CONTRACT-HALF-ADVANCE-PASS]` flag for the future RAW-complete pass (would require an `advance_paid_cp` column + a credit at accept time + the balance at deliver time).

### 7.5 Deadline calculation

RAW doesn't specify a deadline mechanism — the project introduced this per substrate §9.7. Project rule:

```gdscript
static func compute_deadline_calendar_day(
        current_day: int, distance_miles: int, route_mode: String) -> int:
    # Travel speed assumptions:
    #   road wagon: ~18 mi/day (RAW caravan rate)
    #   sea: ~48 mi/day (RAW small sailing ship rate)
    # Deadline = current_day + (one_way_travel_days × 2 for safety margin) + buffer
    var travel_days: int
    if route_mode == "road":
        travel_days = ceili(float(distance_miles) / 18.0)
    else:
        travel_days = ceili(float(distance_miles) / 48.0)
    var deadline_offset: int = travel_days * 2 + 7  # round-trip estimate + 7-day buffer
    return current_day + deadline_offset
```

The `× 2 + 7` formula is a v1 calibration — provides a comfortable deadline that's still tight enough to make late-delivery a real risk on long routes. `[NEEDS-CONTRACT-DEADLINE-CALIBRATION]` flag for playtest tuning.

### 7.6 Per-visit lifecycle — `ShippingContractOfferRoller`

A new service `engine/subsystems/commerce/shipping_contract_offer_roller.gd` (RefCounted, static-function library) handles roll-on-entry and clear-on-exit:

```gdscript
class_name ShippingContractOfferRoller
extends RefCounted

const CONTRACT_COUNT_DICE := {
    1: "2d6+2", 2: "2d4+1", 3: "2d4",
    4: "1d4",   5: "1d4-1", 6: "1d3-1",
}
const CARGO_LOADS_DICE := {
    1: "6d8", 2: "4d6", 3: "3d4",
    4: "2d4", 5: "1d4", 6: "1d2",
}
const MIXED_CARGO_STONE_PER_LOAD := 70  # RAW L822

# Rolled on market entry by VisitStateManager / SettlementExploreState.
static func roll_for_visit(
        settlement_id: String, party_id: String, current_day: int) -> Array

# Cleared on market departure by VisitStateManager.
static func clear_for_party_at_settlement(party_id: String, settlement_id: String) -> int

# Read by accept handler + UI.
static func list_offers(party_id: String, settlement_id: String) -> Array
static func get_offer(offer_id: String) -> Dictionary
```

**`roll_for_visit` algorithm:**

1. Idempotency check: if offers already exist for `(party_id, settlement_id)`, return them without re-rolling. Save/load and re-entering a settlement within the same visit should not re-roll. The roll is per VISIT (visit boundary cleared on departure per §9).
2. Read settlement market_class.
3. Roll contract count per `CONTRACT_COUNT_DICE[class]` (seeded RNG: `hash("contract_count|%s|%s|%d" % [party_id, settlement_id, current_day])`).
4. For each offer index 0..N-1:
   - Roll destination per §7.3 (seeded per `(party_id, origin, day, offer_index)`).
   - Pick route_mode (road preferred per §7.3).
   - Roll loads_count per `CARGO_LOADS_DICE[class]`.
   - Compute distance_miles (substrate distance × hex_size_miles).
   - Compute fee_cp per §7.4.
   - Compute deadline_calendar_day per §7.5.
   - INSERT row into shipping_contract_offers.
5. Return the inserted offer_ids.

**`clear_for_party_at_settlement`** is invoked from the §9 visit-state-clear path. Just deletes all rows for `(party_id, origin_settlement_id)`.

### 7.7 Handler design — `accept_shipping_contract.gd`

```gdscript
class_name AcceptShippingContractHandler
extends RefCounted

## accept_shipping_contract handler (Phase 10B.2 — Trade block).
## Singular minor activity. Per gdd-phase-10b-2-trade-block.md §7.

static func on_complete(state: Dictionary, _runner) -> Dictionary:
    var character_id: String = String(state.get("character_id", ""))
    var settlement_id: String = String(state.get("location_ref", ""))
    var params: Dictionary = state.get("params", {})

    var offer_id: String = String(params.get("offer_id", ""))
    var carrier_id: String = String(params.get("carrier_id", ""))
    var carrier_kind: String = String(params.get("carrier_kind", ""))

    # 1. Validate offer exists + matches active party + carrier kind matches route mode.
    var offer: Dictionary = ShippingContractOfferRoller.get_offer(offer_id)
    if offer.is_empty():
        return {"summary": "accept_shipping_contract: offer not found (expired or already accepted)", "success": false}

    var party_id: String = BuySellCommon.resolve_party_for_character(character_id)
    if String(offer.get("party_id", "")) != party_id:
        return {"summary": "accept_shipping_contract: offer belongs to a different party", "success": false}

    var route_mode: String = String(offer.get("route_mode", "road"))
    var required_carrier: String = "draft_vehicle" if route_mode == "road" else "ship"
    if carrier_kind != required_carrier:
        return {"summary": "accept_shipping_contract: %s route requires a %s, not %s" % [route_mode, required_carrier, carrier_kind], "success": false}

    # 2. Capacity check.
    var total_stone: int = int(offer.get("loads_count", 0)) * int(offer.get("load_weight_stone", 0))
    if not BuySellCommon.carrier_has_capacity(carrier_id, carrier_kind, total_stone):
        return {"summary": "accept_shipping_contract: carrier lacks capacity (%d stone needed)" % total_stone, "success": false}

    # 3. Per-visit entry toll first-fire (§9).
    var rng: RandomNumberGenerator = BuySellCommon.transaction_rng(party_id, settlement_id)
    var toll_charge: int = BuySellCommon.charge_entry_toll_if_first_visit(
        party_id, settlement_id, false, 0, rng)  # accepting a contract isn't selling

    # 4. Substrate: insert the shipping_contracts row.
    var contract_id: String = ShippingContractRepository.accept_contract(
        party_id,
        String(offer.get("origin_settlement_id", "")),
        String(offer.get("destination_settlement_id", "")),
        String(offer.get("merchandise_type", "mixed_cargo")),
        int(offer.get("loads_count", 0)),
        int(offer.get("fee_cp", 0)),
        int(offer.get("deadline_calendar_day", 0)),
        Timekeeping.current_calendar_day())
    if contract_id.is_empty():
        return {"summary": "accept_shipping_contract: substrate.accept_contract failed", "success": false}

    # 5. Substrate: link the cargo_holds row to the contract.
    var cargo_id: String = CargoHoldRepository.insert_shipping_contract_load(
        carrier_id, carrier_kind,
        String(offer.get("merchandise_type", "mixed_cargo")),
        int(offer.get("loads_count", 0)),
        contract_id,
        String(offer.get("origin_settlement_id", "")),
        Timekeeping.current_calendar_day())

    # 6. Delete the offer (one-shot — accepting consumes the offer).
    CampaignRepository.db.query_with_bindings(
        "DELETE FROM shipping_contract_offers WHERE id = ?", [offer_id])

    # 7. Build receipt.
    return {
        "summary": "Accepted contract: %d loads of %s to <%s> by day %d for %d gp." % [
            int(offer.get("loads_count", 0)),
            String(offer.get("merchandise_type", "mixed_cargo")),
            String(offer.get("destination_settlement_id", "")),
            int(offer.get("deadline_calendar_day", 0)),
            int(offer.get("fee_cp", 0))],
        "success": true,
        "contract_id": contract_id,
        "cargo_hold_id": cargo_id,
        "entry_toll_cp": toll_charge,
    }
```

**Notable design points:**
- **Offer is one-shot.** Accepting deletes it from `shipping_contract_offers`. The contract lives on in `shipping_contracts` until delivery/cancel/deadline-fail.
- **Carrier-kind enforcement at accept time** ensures road contracts go on wagons and water contracts go on ships.
- **Cargo-holds row links via `shipping_contract_id`** per substrate Prereq.5b's `cargo_holds` schema (column added in migration 101).
- **Entry toll** fires first-time per visit like the other mercantile activities.

### 7.8 UI section — `mercantile_panel._build_shipping_contracts_section()`

Fields top-to-bottom:

1. **Active character selector** — shared (per §2.8).
2. **Offers list** (custom ItemList or VBoxContainer of offer rows) — one row per available offer. Each row shows:
   ```
   ★ 50 loads of mixed cargo → Thornwall (45 mi by road)
     Pay: 70 gp on delivery
     Deadline: day 47 (you have 19 days)
     ⚠ Requires a wagon with ≥ 3,500 stone free capacity
   ```
   Player clicks a row to select it. Selection highlights.
3. **Carrier dropdown** — filtered by the selected offer's required `carrier_kind`. Shows carrier name + free capacity.
4. **Live preview**:
   ```
   On accept: contract row inserted; 3,500 stone of cargo loaded onto Hauler #1.
   Fee 70 gp credited on delivery to <destination> by day 47.
   Entry toll (first transaction this visit): 4 gp.
   ```
5. **Validation label** — empty when valid; populated with rejection messages (no offer selected, no compatible carrier, capacity insufficient).
6. **Launch / Cancel** at footer.

**Offers list empty state:** "No shipping contracts available at this market right now. (Class V/VI markets may roll zero offers.)"

### 7.9 Delivery flow — substrate already ships it

The delivery flow uses substrate `ShippingContractRepository.deliver(contract_id, current_calendar_day)` per Prereq.5c. The trade-block UI surfaces an "Active contracts" sub-view (in the same shipping section) listing the party's `list_active_for_party(party_id)` rows with deliver / cancel buttons. The handler-design layer here doesn't ship a new activity for delivery — the existing settlement-detail flow (party arrives at destination → settlement view shows pending contracts → player clicks deliver) is the v1 path.

**Why deliver isn't a separate Trade-block activity:** RAW doesn't require a "Deliver Cargo" activity — arriving at the destination market and informing the shipper-agent is part of the visit, not a separate action. The active-contracts panel offers a deliver button as part of the settlement-entry UI flow.

**Cancel** mirrors deliver — available from the active-contracts panel; calls substrate `ShippingContractRepository.cancel(contract_id)`.

`[NEEDS-DELIVERY-UI-PASS]` flag for the active-contracts panel — likely a small addition to `mercantile_panel` (sixth conditional section?) or a settlement-overview surface. Design left for implementation pass.

### 7.10 Cross-section impacts

- **§9 (per-visit state):** `ShippingContractOfferRoller.roll_for_visit` is invoked by the visit-state-enter path (§9 design). `clear_for_party_at_settlement` is invoked by the visit-state-clear path.
- **§4 (persuade):** persuade_merchants doesn't affect shipping contracts. Orthogonal.
- **§5 (solicit):** likewise orthogonal — solicit reveals merchants from the merchant_pool; shipping offers are a separate pool.
- **§13 (partial loads):** shipping contracts are atomic — players accept the full offer (50 loads or whatever) or none. No partial-accept. If the contract's cargo gets damaged in transit (lost-vehicle case from Q-TB-6), the contract is in a tricky state — the cargo_holds row may need partial-loss semantics. §13 covers this.
- **§17 (eligibility resolver):** the new `shipping_offer_present` prereq tag is resolved via `ShippingContractOfferRoller.list_offers(party_id, settlement_id).size() > 0`.

### 7.11 Migration 105

`db/migrations/105_shipping_contract_offers.sql` adds the `shipping_contract_offers` table per §7.2. Single CREATE TABLE + one index. Atomic transaction.

This is the second Phase 10B.2 migration (after 104 from §4). The `monopoly_holdings` table from §8 lands in a separate migration (106).

### 7.12 EventBus signal additions

```gdscript
# Phase 10B.2 shipping-contract signals (offers + acceptance)
signal shipping_offer_rolled(offer_id: String, party_id: String, settlement_id: String)
signal shipping_offer_accepted(offer_id: String, contract_id: String, cargo_hold_id: String)
signal shipping_offer_cleared(party_id: String, settlement_id: String, cleared_count: int)
```

Substrate signals from Prereq.5c (`shipping_contract_accepted`, `shipping_contract_delivered`, `shipping_contract_failed`) continue to fire from `ShippingContractRepository` and don't need duplicate emission here.

### 7.13 What §7 does NOT add

- **No staggered 3-week availability** per RAW L828-832. All offers are rolled at market entry and available immediately. `[NEEDS-CONTRACT-STAGGERED-AVAILABILITY-PASS]`.
- **No reaction-roll-per-contract** per RAW L815. Offers are accepted without a trust roll. `[NEEDS-CONTRACT-TRUST-ROLL-PASS]`.
- **No half-advance / half-on-delivery split** per RAW L824. v1 pays full fee on delivery. `[NEEDS-CONTRACT-HALF-ADVANCE-PASS]`.
- **No RAW-complete destination logic** per RAW L788-791. v1 picks a random reachable settlement; the 1d20-distant-vs-near mechanic awaits in-game travel-destination tracking. `[NEEDS-CONTRACT-DESTINATION-RAW-COMPLETE-PASS]`.
- **No `solicit_passengers`** — entire passenger system is deferred per Q-TB-2.
- **No "mixed merchandise type" rolling.** All v1 contracts are `merchandise_type='mixed_cargo'` with the RAW L822 70 stone/load simplification. Future enhancement could roll on the Common Merchandise table at offer-creation time.
- **No partial-acceptance.** Player accepts a full offer or none.
- **No fee renegotiation / haggling.** RAW silent on renegotiation; v1 doesn't add it.
- **No "deliver" or "cancel" as Trade-block activities.** Delivery happens via the settlement-entry UI at the destination per §7.9; cancel via the active-contracts panel. Both call existing substrate APIs.
- **No deadline-extension mechanic.** RAW silent; v1 doesn't add it. If a deadline passes during transit the substrate's `deliver` path returns `deadline_missed=true` and the substrate logic handles it (no fee paid).
- **No reputation impact for missed deadlines.** `[NEEDS-LATE-DELIVERY-PENALTY-PASS]` flag carried from substrate §9.7.

---

## §8. Monopoly Registry

### 8.0 Overview

Phase 10B.2 needs a place to record monopoly grants — `(character_id, settlement_id, merchandise_type)` triples that confer the RAW monopolist benefits. §3 and §4 consume this registry; §3 (buy/sell handler) reads `favor_for_buy` / `favor_for_sell` for the `monopolist_favor` integer the substrate `MarketPriceResolver` accepts, and §4 (persuade) reads `has_monopoly` for the +3 reaction-roll bonus.

- **RAW citation:** `rules/acore-campaign-hijinks.xml:713` ("+3 on the roll" for persuade) and `:714` ("twice the normal number of loads"). Substrate `gdd-settlement-economy.md §6.4` describes the `monopolist_favor` integer the price formula consumes.
- **What RAW provides:** the effects of holding a monopoly (favor + cap-doubling + persuade bonus).
- **What's missing:** RAW doesn't enumerate the GRANT mechanism — who issues monopolies, under what circumstances, and with what duration. RAW's L713-714 is purely effect-side.
- **Project resolution:** v1 ships the **plumbing** (table + service + lookups) so consumers can query monopoly status. **Population** (grant + revoke flows) is later work — Phase 10B.3's `issue_decree`-extension, or a future domain-block enhancement, will surface the grant mechanism. v1's `monopoly_holdings` table stays empty by default; every lookup returns false / 0. The price formula and persuade roll still work correctly because both flows handle the 0-favor case as the no-op default.

### 8.1 Schema — `monopoly_holdings` table

Migration 106 (the third Phase 10B.2 migration, after 104 = §4's columns, 105 = §7's offers):

```sql
CREATE TABLE IF NOT EXISTS monopoly_holdings (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    character_id                    TEXT    NOT NULL REFERENCES characters(id),
    settlement_id                   TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    granted_at_calendar_day         INTEGER NOT NULL DEFAULT 0,
    granted_by_character_id         TEXT    REFERENCES characters(id),
    granted_by_authority            TEXT    NOT NULL DEFAULT 'domain_ruler'
        CHECK(granted_by_authority IN ('domain_ruler', 'judge', 'inherited', 'purchased')),
    expires_at_calendar_day         INTEGER,
    notes                           TEXT    NOT NULL DEFAULT '',
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(character_id, settlement_id, merchandise_type)
);
CREATE INDEX IF NOT EXISTS idx_monopoly_holdings_character
    ON monopoly_holdings(character_id);
CREATE INDEX IF NOT EXISTS idx_monopoly_holdings_settlement_merch
    ON monopoly_holdings(settlement_id, merchandise_type);
```

**Field rationale:**
- **`UNIQUE(character_id, settlement_id, merchandise_type)`** — a character can hold at most one monopoly per (settlement, merchandise) triple. Re-granting requires revoking first.
- **`granted_by_authority`** enum lists the canonical grant paths. `'domain_ruler'` (the player who rules the settlement's parent domain issues the monopoly), `'judge'` (Judge-authored), `'inherited'` (story event / heritable grant), `'purchased'` (future market for monopolies). v1 doesn't ship grant logic — the enum is forward-compat for future grant mechanisms.
- **`expires_at_calendar_day`** is nullable — NULL means perpetual. Time-bound monopolies (e.g., "5-year salt monopoly") use a non-null value.
- **`notes`** for audit/narrative ("Granted to <name> by Duke X for service at the Battle of Y").

### 8.2 `MonopolyRegistry` service API

`engine/subsystems/commerce/monopoly_registry.gd` — `RefCounted` static-function library, no autoload.

```gdscript
class_name MonopolyRegistry
extends RefCounted

# ---------------------------------------------------------------------------
# Read API — primary consumers: §3 buy/sell, §4 persuade
# ---------------------------------------------------------------------------

## Returns true iff [param character_id] holds an unexpired monopoly on
## [param merchandise_type] at [param settlement_id].
static func has_monopoly(character_id: String, settlement_id: String, merchandise_type: String) -> bool

## Returns -1 if the character is the monopolist (the buyer wants a lower
## price, and the monopolist's favor flows their way), else 0. Fed directly
## to MarketPriceResolver.compute_market_price's monopolist_favor param.
static func favor_for_buy(character_id: String, settlement_id: String, merchandise_type: String) -> int

## Returns +1 if the character is the monopolist (the seller wants a higher
## price), else 0. Fed to MarketPriceResolver.
static func favor_for_sell(character_id: String, settlement_id: String, merchandise_type: String) -> int

## Returns full row dict, or {} if not found / expired.
static func get_monopoly_row(character_id: String, settlement_id: String, merchandise_type: String) -> Dictionary

## Returns all unexpired monopolies held by character_id. Used for the
## "your monopolies" UI surface (future polish; not in v1 critical path).
static func list_monopolies_for_character(character_id: String) -> Array

## Returns all unexpired monopolies at settlement_id. Used for "who holds
## monopolies here" reverse-lookup (future polish).
static func list_monopolies_at_settlement(settlement_id: String) -> Array

# ---------------------------------------------------------------------------
# Write API — populated by future grant systems (Phase 10B.3 decree
# extension, etc.). v1 has no caller for these but ships the API.
# ---------------------------------------------------------------------------

## Grants a monopoly. Returns the new holding's id, or "" on UNIQUE violation
## (the character already holds this monopoly at this settlement).
static func grant_monopoly(
        character_id: String,
        settlement_id: String,
        merchandise_type: String,
        granted_at_calendar_day: int,
        granted_by_character_id: String = "",
        granted_by_authority: String = "domain_ruler",
        expires_at_calendar_day = null,
        notes: String = ""
) -> String

## Revokes by holding_id. Returns false if not found.
static func revoke_monopoly(holding_id: String) -> bool

## Revokes by triple (convenience for callers who don't track holding_id).
static func revoke_monopoly_by_triple(character_id: String, settlement_id: String, merchandise_type: String) -> bool
```

**`has_monopoly` reference implementation:**

```gdscript
static func has_monopoly(character_id: String, settlement_id: String, merchandise_type: String) -> bool:
    if character_id.is_empty() or settlement_id.is_empty() or merchandise_type.is_empty():
        return false
    var current_day: int = Timekeeping.current_calendar_day()
    if not CampaignRepository.db.query_with_bindings("""
        SELECT 1 FROM monopoly_holdings
        WHERE character_id = ?
          AND settlement_id = ?
          AND merchandise_type = ?
          AND (expires_at_calendar_day IS NULL OR expires_at_calendar_day > ?)
        LIMIT 1
    """, [character_id, settlement_id, merchandise_type, current_day]):
        return false
    return not CampaignRepository.db.query_result.is_empty()


static func favor_for_buy(character_id: String, settlement_id: String, merchandise_type: String) -> int:
    return -1 if has_monopoly(character_id, settlement_id, merchandise_type) else 0


static func favor_for_sell(character_id: String, settlement_id: String, merchandise_type: String) -> int:
    return 1 if has_monopoly(character_id, settlement_id, merchandise_type) else 0
```

### 8.3 Sign convention (substrate alignment)

The substrate's `MarketPriceResolver.compute_market_price(merchandise_type, settlement_id, monopolist_favor: int, judge_modifier: int, ...)` takes `monopolist_favor` as a signed integer per substrate §6.4:

| Caller context | Favor value | Effect on price |
|---|---|---|
| Non-monopolist buying | 0 | No change |
| Monopolist buying | -1 | Price reduced by 10% (formula: `(dice + demand + class_adj + monopolist_favor + judge) × 10` percentage) |
| Non-monopolist selling | 0 | No change |
| Monopolist selling | +1 | Price increased by 10% |

The `favor_for_buy` / `favor_for_sell` helpers match this convention exactly. `§3.2` and `§3.3` handler pseudocode calls them with the correct active character + settlement + merchandise.

### 8.4 Persuade bonus integration (§4 cross-reference)

`§4.4` reads `MonopolyRegistry.has_monopoly` to determine the +3 persuade reaction-roll bonus. The check is per-target-merchandise:

```gdscript
var monopolist_bonus: int = 3 if MonopolyRegistry.has_monopoly(character_id, settlement_id, target_merch_type) else 0
```

The bonus applies when the active character holds a monopoly on the merchandise type they're trying to persuade a merchant to deal in. This is per RAW L713 — "If the adventurer has a monopoly on that type of merchandise, he gains +3 on the roll."

### 8.5 Monopolist 2× cap integration (§4.11 cross-reference)

§4.11 amends §3 to apply the RAW L714 "twice the normal number of loads" effect via the same `has_monopoly` check:

```gdscript
var max_buyable: int = int(merchant.get("loads_available", 0))
if MonopolyRegistry.has_monopoly(character_id, settlement_id, merchandise_type):
    max_buyable *= 2
```

Single registry; single helper; three call sites (§3 favor, §4 reaction bonus, §4.11 cap doubling).

### 8.6 EventBus signal additions

```gdscript
# Phase 10B.2 monopoly signals
signal monopoly_granted(holding_id: String, character_id: String, settlement_id: String, merchandise_type: String)
signal monopoly_revoked(holding_id: String, character_id: String, settlement_id: String, merchandise_type: String)
```

These fire from `grant_monopoly` and `revoke_monopoly`. v1 has no callers, but the signals exist so future grant systems (Phase 10B.3 decree extension, domain-block monopoly UI, scripted plot events) can wire UI / log surfacing without retroactive plumbing.

### 8.7 Migration 106

`db/migrations/106_monopoly_holdings.sql` ships the table + two indexes per §8.1. Single CREATE TABLE + two CREATE INDEX statements wrapped in BEGIN TRANSACTION / COMMIT. Atomic.

### 8.8 Cross-section dependencies

| Consumer | API call | Section |
|---|---|---|
| `buy_merchandise.gd` (active character price) | `favor_for_buy(char, sett, type)` | §3.2 |
| `sell_merchandise.gd` (active character price) | `favor_for_sell(char, sett, type)` | §3.3 |
| `buy_merchandise.gd` (max-buyable cap) | `has_monopoly(char, sett, type)` | §3.2 + §4.11 |
| `persuade_merchants.gd` (reaction bonus) | `has_monopoly(char, sett, target_type)` | §4.4 |

All other Trade-block handlers (`solicit_merchants`, `locate_merchandise`, `accept_shipping_contract`) do NOT consume the registry. Solicit is a visibility action; locate is a search action; shipping contracts are transport jobs — none are price-formula or persuade-roll consumers.

### 8.9 What §8 does NOT add

- **No grant logic.** Phase 10B.2 ships the API; population is later work. v1 starts with an empty `monopoly_holdings` table; every `has_monopoly` returns false.
- **No revoke logic.** Same as grant — API exists, no callers in v1.
- **No conflict resolution** for two characters trying to hold the same (settlement, merchandise) monopoly. The UNIQUE constraint enforces "one holder per triple"; the grant API's UNIQUE-violation handling returns "" so callers know the grant failed.
- **No monopoly UI.** Future "your monopolies" panel can read `list_monopolies_for_character`. v1 doesn't render it.
- **No automatic expiration sweep.** Expired monopolies are filtered by the `has_monopoly` query's `expires_at_calendar_day > current_day` clause. The expired row stays in the table (audit trail). A future cleanup pass could DELETE genuinely-expired rows, but it's not needed for correctness.
- **No transferable monopolies** (sale / inheritance flows). The `granted_by_authority='purchased'` enum value reserves space for this; the mechanism is later work.
- **No partial monopoly** (e.g., "monopoly on 80% of silk sales"). v1 is all-or-nothing per (character, settlement, merchandise).
- **No multi-settlement monopolies** (e.g., "all of Duchy X"). Each monopoly is per-settlement. A character can hold monopolies at multiple settlements simultaneously by having multiple rows.
- **No monopoly on `mixed_cargo`** (the §7 shipping-contract sentinel merchandise type). Monopolies are on registry-cataloged merchandise types only. The `merchandise_type` column has no FK to the registry (it's a TEXT field), but application-level callers should only grant monopolies on the 31 RAW merchandise types.

---

## §9. Per-Visit State — `VisitStateManager` + Entry/Departure Triggers

### 9.0 Overview + Q-TB-11 resolution

Phase 10B.2 needs per-visit state for:

1. **Entry-toll first-fire tracking** — toll fires once per visit, not per transaction. Subsequent buy/sell/persuade/solicit/locate/accept_shipping_contract activities within the same visit consult this state and skip the toll.
2. **Active-character-at-entry** — for toll attribution + domain-owner exemption + monopolist favor at toll time.
3. **Entry calendar day** — for stabling computation at departure (`days_at_settlement = current_day - entry_day`).
4. **Triggers** — entry triggers `ShippingContractOfferRoller.roll_for_visit` (§7); departure triggers stabling + moorage debits, `clear_for_party_at_settlement`, and state cleanup.

Q-TB-11 [RESOLVED 2026-05-13] asked for storage options with tradeoffs. §9.2 evaluates four options and recommends Option A (dedicated DB table).

### 9.1 What state is tracked

A single row per `(party_id, settlement_id)` while the party is at the settlement:

| Field | Purpose |
|---|---|
| `entry_calendar_day` | Days-at-settlement math at departure (stabling + moorage). |
| `entry_toll_paid_cp` | The toll amount actually charged on first transaction (0 if domain-owner). UI display + receipt history. |
| `entry_toll_paid_flag` | Whether the toll has been charged yet this visit (boolean derived from `entry_toll_paid_cp >= 0` post-charge, but represented as a separate column for clarity). |
| `active_character_at_entry` | Who paid the toll + whose monopoly status applied. |
| `created_at` | ISO timestamp for audit. |

This is small state — five fields. Cleanup on departure is one DELETE.

### 9.2 Storage options — analysis + recommendation

**Option A: Dedicated DB table `party_visit_state`** ★ RECOMMENDED

- **Schema:** new table with the five fields above. Composite UNIQUE on `(party_id, settlement_id)`.
- **Lifecycle:** INSERT on entry (idempotent — re-entry into the same settlement without departure is a no-op). DELETE on departure.
- **Pros:**
  - Survives save/load automatically — the state is part of the DB snapshot.
  - Cleanup is one SQL statement.
  - Easy to audit (`SELECT * FROM party_visit_state` shows the current state).
  - Cross-handler queries are trivial — every mercantile handler reads the same row.
  - Scales naturally to multi-party future (one row per party at a settlement).
- **Cons:**
  - One more table in the schema. (Phase 10B.2 now adds 4 migrations: 104 §4 columns, 105 §7 offers, 106 §8 monopolies, 107 §9 visits.)
  - Cleanup must fire reliably on departure — orphan rows (party closed game without leaving the settlement) would mistakenly skip the toll on next entry. Mitigation: cleanup on session load OR add `created_at` TTL.

**Option B: JSON column on `parties` table**

- **Schema:** add `current_visit_state TEXT NOT NULL DEFAULT '{}'` to existing parties table.
- **Pros:** no new table; small migration.
- **Cons:**
  - JSON-in-column anti-pattern per coding conventions §6 (SQLite SQL features can't index into JSON cleanly without `json_*` functions, which require careful escaping).
  - Encoded JSON queries are noisier than column reads — `SELECT json_extract(current_visit_state, '$.entry_toll_paid_flag')` vs `SELECT entry_toll_paid_flag`.
  - Cleanup is `UPDATE parties SET current_visit_state = '{}'` — easy but blurs schema documentation.
- **Verdict:** Rejected. Project convention favors typed columns.

**Option C: In-memory on `SettlementExploreState`**

- **Schema:** none.
- **Pros:** zero migration cost; cleanup is implicit (state dies with screen).
- **Cons:**
  - Save/load support requires the SettlementExploreState to serialize/deserialize the state — adds save-format coupling that's brittle when fields evolve.
  - The state is needed across handlers that don't have a direct reference to SettlementExploreState — they'd have to query a singleton, which is essentially an autoload.
- **Verdict:** Rejected. Save/load brittleness is the deal-breaker.

**Option D: Hybrid (Option A + in-memory cache)**

- **Schema:** Option A's table, plus an autoload caching layer.
- **Pros:** Best of both — persistent + fast lookups.
- **Cons:** Two layers of state to keep in sync. Over-engineering for the access frequency (a handler calls this 1-2 times per launch, not per frame).
- **Verdict:** Rejected. Not enough access volume to justify the cache.

**Recommendation: Option A.** Clean DB-backed state, single source of truth, save/load just works. §9.3 schema below.

### 9.3 Schema — `party_visit_state` table

Migration 107 (the fourth and final Phase 10B.2 migration):

```sql
CREATE TABLE IF NOT EXISTS party_visit_state (
    party_id                        TEXT    NOT NULL REFERENCES parties(id),
    settlement_id                   TEXT    NOT NULL REFERENCES settlement_entrances(id),
    entry_calendar_day              INTEGER NOT NULL DEFAULT 0,
    entry_toll_paid_flag            INTEGER NOT NULL DEFAULT 0
        CHECK(entry_toll_paid_flag IN (0, 1)),
    entry_toll_paid_cp              INTEGER NOT NULL DEFAULT 0,
    active_character_at_entry       TEXT    REFERENCES characters(id),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (party_id, settlement_id)
);
```

**Composite primary key** = `(party_id, settlement_id)`. INSERT-OR-IGNORE semantics make re-entry idempotent without explicit existence checks.

**No `id` UUID** — the (party_id, settlement_id) composite key is sufficient. Avoids generating UUIDs we don't need elsewhere.

### 9.4 `VisitStateManager` service API

`engine/subsystems/commerce/visit_state_manager.gd` — `RefCounted` static-function library. NOT an autoload (per coding conventions §5 — autoloads are for truly global services; this is a domain-specific helper).

```gdscript
class_name VisitStateManager
extends RefCounted

# ---------------------------------------------------------------------------
# Entry / departure triggers
# ---------------------------------------------------------------------------

## Called by SettlementExploreState (or equivalent) when the party enters
## the settlement detail view. Inserts a party_visit_state row (idempotent
## if one already exists for this (party, settlement) pair — re-entry
## without departure is a no-op). Triggers offer-rolling per §7.
static func on_party_entered_settlement(
        party_id: String,
        settlement_id: String,
        active_character_id: String,
        current_calendar_day: int
) -> void

## Called when the party departs. Computes + debits stabling + moorage,
## clears shipping offers, DELETEs the visit row. Emits departure signals.
static func on_party_departed_settlement(
        party_id: String,
        settlement_id: String,
        current_calendar_day: int
) -> Dictionary    # returns {stabling_cp, moorage_cp, days_at_settlement, unpaid_gp}

# ---------------------------------------------------------------------------
# Toll first-fire (consumed by all mercantile handlers via BuySellCommon)
# ---------------------------------------------------------------------------

## True iff the party has already paid the entry toll at this settlement
## this visit. False if no visit row OR toll not yet paid.
static func has_paid_entry_toll(party_id: String, settlement_id: String) -> bool

## Records that the toll has been paid + the amount + which character was
## active at toll time. Called by BuySellCommon.charge_entry_toll_if_first_visit.
static func mark_entry_toll_paid(party_id: String, settlement_id: String, toll_gp: int) -> void

## Returns the active character recorded at entry. Used by toll-first-fire
## to know who's the domain-owner-status reference at toll time + by
## stabling/moorage to know who pays at departure.
static func active_character_for_visit(party_id: String, settlement_id: String) -> String

# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

static func get_visit_row(party_id: String, settlement_id: String) -> Dictionary
static func has_active_visit(party_id: String, settlement_id: String) -> bool
```

### 9.5 Entry trigger — `on_party_entered_settlement`

```gdscript
static func on_party_entered_settlement(
        party_id: String,
        settlement_id: String,
        active_character_id: String,
        current_calendar_day: int
) -> void:
    if party_id.is_empty() or settlement_id.is_empty():
        return

    # INSERT-OR-IGNORE: re-entry without departure is a no-op.
    CampaignRepository.db.query_with_bindings("""
        INSERT OR IGNORE INTO party_visit_state
            (party_id, settlement_id, entry_calendar_day,
             entry_toll_paid_flag, entry_toll_paid_cp,
             active_character_at_entry)
        VALUES (?, ?, ?, 0, 0, ?)
    """, [party_id, settlement_id, current_calendar_day, active_character_id])

    # Roll fresh shipping-contract offers per §7. Idempotent on re-entry per
    # ShippingContractOfferRoller.roll_for_visit's own idempotency check.
    ShippingContractOfferRoller.roll_for_visit(settlement_id, party_id, current_calendar_day)

    EventBus.party_entered_settlement.emit(party_id, settlement_id, current_calendar_day)
```

**Caller:** `SettlementExploreState` (or whatever owns the settlement-detail-view lifecycle) invokes this when transitioning the party into the settlement detail view. Existing settlement-flow code in `scenes/ui/settlement/*` has a clear entry point — implementation pass identifies and wires.

### 9.6 Departure trigger — `on_party_departed_settlement`

```gdscript
static func on_party_departed_settlement(
        party_id: String,
        settlement_id: String,
        current_calendar_day: int
) -> Dictionary:
    var visit: Dictionary = get_visit_row(party_id, settlement_id)
    if visit.is_empty():
        return {"stabling_cp": 0, "moorage_cp": 0, "days_at_settlement": 0, "unpaid_gp": 0}

    var entry_day: int = int(visit.get("entry_calendar_day", current_calendar_day))
    var days_at_settlement: int = maxi(1, current_calendar_day - entry_day)
    var active_char_id: String = String(visit.get("active_character_at_entry", ""))
    var is_domain_owner: bool = MarketFeesCalculator.is_domain_owner_in_own_market(active_char_id, settlement_id)

    # 1. Stabling — enumerate party carriers at this settlement.
    var mounts: Dictionary = _compile_mounts_at_settlement(party_id, settlement_id)
    var stabling_cp: int = MarketFeesCalculator.stabling_cp_total(mounts, days_at_settlement, is_domain_owner)

    # 2. Moorage — enumerate party ships moored here.
    var moorage_cp: int = 0
    for ship in ShipRepository.list_ships_for_party(party_id):
        if String((ship as Dictionary).get("moored_at_settlement_id", "")) == settlement_id:
            moorage_cp += MarketFeesCalculator.moorage_cp_total(
                int((ship as Dictionary).get("shp_max", 0)),
                days_at_settlement,
                is_domain_owner)

    # 3. Debit (atomic from the player's view).
    var total_fees: int = stabling_cp + moorage_cp
    var unpaid_gp: int = 0
    if total_fees > 0:
        var pay_result: Dictionary = PartyWallet.pay(total_fees * 100, party_id, active_char_id)
        if not bool(pay_result.get("ok", false)):
            # Insufficient funds — emit unpaid signal but DON'T block departure.
            # Matches the §9.6.1-style "log and continue" pattern from ship
            # operating costs. Future enhancement could track debt.
            unpaid_gp = total_fees
            EventBus.visit_fees_unpaid.emit(party_id, settlement_id, total_fees)

    # 4. Clear shipping-contract offers (§7 lifecycle).
    var cleared: int = ShippingContractOfferRoller.clear_for_party_at_settlement(party_id, settlement_id)

    # 5. DELETE the visit row.
    CampaignRepository.db.query_with_bindings(
        "DELETE FROM party_visit_state WHERE party_id = ? AND settlement_id = ?",
        [party_id, settlement_id])

    EventBus.party_departed_settlement.emit(
        party_id, settlement_id, stabling_cp, moorage_cp, days_at_settlement)

    return {
        "stabling_cp": stabling_cp,
        "moorage_cp": moorage_cp,
        "days_at_settlement": days_at_settlement,
        "unpaid_gp": unpaid_gp,
        "offers_cleared": cleared,
    }
```

### 9.7 Mount enumeration for stabling — `_compile_mounts_at_settlement`

Enumerates the party's carriers at this settlement and builds the dict that `MarketFeesCalculator.stabling_cp_total` consumes. Maps draft-vehicle item_keys + hitched-creature species to the substrate's canonical stabling keys.

```gdscript
static func _compile_mounts_at_settlement(party_id: String, settlement_id: String) -> Dictionary:
    var mounts: Dictionary = {}

    # Enumerate draft_vehicles at the settlement. v1 assumes draft_vehicles
    # are AT the party's current location — there's no per-vehicle settlement
    # tracking column, so all non-destroyed draft_vehicles owned by the party
    # are considered "at the settlement during this visit." If future enhancement
    # adds per-vehicle location, this filter tightens.
    if CampaignRepository.db.query_with_bindings("""
        SELECT item_key, hitched_creatures FROM draft_vehicles
        WHERE party_id = ? AND is_destroyed = 0
    """, [party_id]):
        for row in CampaignRepository.db.query_result:
            var item_key: String = String((row as Dictionary).get("item_key", ""))
            # Vehicle slot — cart_small / cart_large → "cart"; wagon → "wagon"
            var vehicle_key: String = _vehicle_item_to_stabling_key(item_key)
            if not vehicle_key.is_empty():
                mounts[vehicle_key] = int(mounts.get(vehicle_key, 0)) + 1
            # Hitched team — parse the JSON array.
            var hitched: String = String((row as Dictionary).get("hitched_creatures", "[]"))
            var team: Variant = JSON.parse_string(hitched)
            if team is Array:
                for creature in team as Array:
                    if creature is Dictionary:
                        var species: String = String((creature as Dictionary).get("species_id", ""))
                        var stable_key: String = _species_to_stabling_key(species)
                        if not stable_key.is_empty():
                            mounts[stable_key] = int(mounts.get(stable_key, 0)) + 1
    return mounts


static func _vehicle_item_to_stabling_key(item_key: String) -> String:
    if item_key in ["cart_small", "cart_large"]:
        return "cart"
    if item_key == "wagon":
        return "wagon"
    return ""


static func _species_to_stabling_key(species_id: String) -> String:
    if species_id in ["horse_heavy", "horse_medium", "horse_light", "warhorse"]:
        return "horse"
    if species_id == "mule":
        return "mule"
    if species_id == "donkey":
        return "donkey"
    if species_id == "camel":
        return "camel"
    if species_id == "ox":
        return "ox"
    return ""
```

**`[NEEDS-VEHICLE-SETTLEMENT-LOCATION-PASS]` flag:** v1 assumes a party's `draft_vehicles` are co-located with the party. A future enhancement could track per-vehicle location (e.g., wagon left at one settlement while party travels elsewhere) by adding a `current_settlement_id` column to `draft_vehicles`. Ships already have `moored_at_settlement_id` for the same purpose.

### 9.8 Days-at-settlement calculation

`days_at_settlement = max(1, current_calendar_day - entry_calendar_day)`:
- Same-day entry/exit charges 1 day stabling.
- Entry day 10, exit day 12 → 2 days stabling.
- Entry day 10, exit day 10 → 1 day (the max(1, 0) = 1 clamp).

`[NEEDS-VISIT-DURATION-CALIBRATION]` flag: this is project-design fill (RAW silent on exact day-counting). If playtest reveals 1-day-charge feels punitive for quick stop-ins (e.g., player enters market, buys 1 silk, leaves on same day), revisit. Possible alternative: "first hour is free; subsequent days charge from when the calendar advances."

### 9.9 Insufficient funds at departure

If `PartyWallet.pay` fails (party doesn't have enough gold for stabling + moorage), the handler:
- Emits `EventBus.visit_fees_unpaid(party_id, settlement_id, owed_gp)`.
- **Does NOT block the departure.** Player still leaves.
- **Does NOT track the debt** in v1. The unpaid signal is the audit trail; no consequences flow from it yet.

`[NEEDS-VISIT-FEE-DEBT-PASS]` flag: a future enhancement could:
- Persist the debt in a `party_debts(party_id, settlement_id, gp_owed, created_at)` table.
- Block re-entry until paid, or apply a reputation penalty, or accrue interest.
- Mirror the existing `ship_operating_cost_unpaid` signal pattern from substrate §9.6.1.

For v1 the simplest "log it and move on" path matches the established substrate convention.

### 9.10 Integration with existing settlement-flow (Q-TB-7 reference)

Per §2.1 audit of the existing settlement UI:
- **Entry point:** `SettlementMenu.setup(settlement, current_poi_id)` is called when the menu opens. The owning `SettlementExploreState` is the natural place to invoke `VisitStateManager.on_party_entered_settlement` — likely in the same code path that pauses the scheduler on settlement entry.
- **Departure point:** `SettlementMenu.close_requested` signal (line 20-ish of `settlement_menu.gd`) — the close handler should invoke `VisitStateManager.on_party_departed_settlement` BEFORE the menu queue_frees + the scheduler resumes.

The exact integration line numbers + the precise hook (`SettlementExploreState._on_close_requested` or equivalent) are an implementation-pass deliverable. The contract this section ships: VisitStateManager exposes the two trigger methods; the settlement-flow caller invokes them at entry/departure.

**`[NEEDS-SETTLEMENT-FLOW-WIRING]` flag** for the implementation pass: find the exact entry/exit hooks in `SettlementExploreState` (or wherever the settlement-detail lifecycle lives) and wire the two VisitStateManager calls.

### 9.11 Migration 107

`db/migrations/107_party_visit_state.sql` ships the table per §9.3. Single CREATE TABLE in atomic transaction. No indexes needed beyond the PRIMARY KEY.

**Phase 10B.2 final migration count:** 4 (104, 105, 106, 107). All four are additive — no existing schema modified, no existing data migration needed.

### 9.12 EventBus signal additions

```gdscript
# Phase 10B.2 visit-lifecycle signals
signal party_entered_settlement(party_id: String, settlement_id: String, calendar_day: int)
signal party_departed_settlement(party_id: String, settlement_id: String, stabling_cp: int, moorage_cp: int, days_at_settlement: int)
signal visit_fees_unpaid(party_id: String, settlement_id: String, owed_gp: int)
```

Three new signals. `party_entered_settlement` fires once per entry; `party_departed_settlement` once per departure (with the computed fees); `visit_fees_unpaid` fires only on the insufficient-funds path.

### 9.13 What §9 does NOT add

- **No multi-character active-character switching mid-visit.** The active character is recorded at entry and used for all subsequent toll attribution + departure-fee debit. If the player changes the active character mid-visit (via the mercantile_panel's selector or settlement_menu), the recorded value DOES NOT update — the toll already paid stays attributed; the departure debit still flows through the entry-time active character. `[NEEDS-MID-VISIT-ACTIVE-CHARACTER-RECONCILE-PASS]` flag for the future enhancement.
- **No fractional-day stabling.** Days are integer; max(1, current - entry).
- **No per-vehicle settlement tracking.** v1 assumes all party draft_vehicles are co-located with the party. `[NEEDS-VEHICLE-SETTLEMENT-LOCATION-PASS]` for future enhancement.
- **No debt tracking** for unpaid visit fees. `[NEEDS-VISIT-FEE-DEBT-PASS]`.
- **No visit history.** Each departure DELETEs the visit row. A future audit/log feature could archive these instead. `[NEEDS-VISIT-HISTORY-PASS]`.
- **No automatic recovery from orphan rows.** If a save happens mid-visit and the campaign is reloaded, the row stays in place. Subsequent entry into the same settlement is treated as continuing the visit (INSERT OR IGNORE). If the player has departed via some path that didn't fire the cleanup (e.g., world-state-mutation events), the row stays and the next entry skips the toll. `[NEEDS-VISIT-ORPHAN-CLEANUP-PASS]` if this becomes a UX issue.
- **No moorage for ships NOT at this settlement.** Only ships with `moored_at_settlement_id = current_settlement_id` are charged. Ships at sea or at other ports are charged moorage at their respective ports during their respective visits.
- **No stabling for combat creatures / mounts** that aren't hitched to a vehicle. PC mounts (e.g., a rider's warhorse not pulling a wagon) might need stabling too — currently they don't show up in the enumeration. `[NEEDS-PC-MOUNT-STABLING-PASS]` if playtest reveals this matters.

---

## §10. Trade-Route Detection — Trigger Wiring

### 10.0 Overview

The substrate ships `TradeRouteDetector` (detects road/water paths between settlement pairs + writes to `trade_routes`) and `RegionDemandResolver` (region walk + step-6 demand shifts) per Prereq.2b. Both are passive — they need to be INVOKED on specific events. Phase 10B.2 ships the trigger wiring.

Per Q-TB-12 [RESOLVED 2026-05-13]: all five substrate-enumerated triggers (substrate GDD §5.6) AND a sixth one for settlement market-class changes. Plus the campaign-load full sweep.

### 10.1 Trigger inventory

Seven trigger scenarios, six event-driven plus one lifecycle-driven:

| Trigger | When it fires | Scope of action |
|---|---|---|
| **Campaign load** | After session load completes | Full sweep — `detect_routes_for_campaign(campaign_id)` if `trade_routes` is empty for the campaign, then `RegionDemandResolver.resolve_all_regions(campaign_id)`. |
| **Settlement created** | A new `settlement_entrances` row is inserted | Run `detect_routes_for_settlement(new_settlement_id)` to find connections to existing settlements within range; re-run region resolver for the region containing the new settlement. |
| **Settlement destroyed** | A `settlement_entrances` row is deleted (or soft-deleted) | DELETE all `trade_routes` rows referencing this settlement; re-run region resolver for the formerly-connected region(s). |
| **Settlement market_class changed** (Q-TB-12 addition) | `settlement_entrances.market_class` is updated | Re-run `detect_routes_for_settlement(settlement_id)` — the new market class changes `range_of_trade`, so routes that were valid may no longer be, and vice versa. Re-run region resolver. |
| **Road overlay added** | A `hex_overlays` row with `overlay_type='road'` is inserted | Find settlements within MAX_ROAD_RANGE (28 hexes) of (q, r). For each, re-detect routes. Re-run region resolver. |
| **Road overlay removed** | A road overlay row is deleted | Same scope as added. Routes that depended on this segment may invalidate; some may need re-detection if alternate paths now exist. |
| **River/water overlay added/removed** | `hex_overlays` row with `overlay_type='river'` changes, or `hex_cells.water` changes between '', 'ocean', 'lake' | Same pattern as road overlay; uses MAX_WATER_RANGE (80 hexes) for the proximity filter. |

### 10.2 EventBus signals

**Signals that need to be added to `event_bus.gd`** (consolidated in §16) — Phase 10B.2 ships the contracts; the emitters (the code that actually fires the signal when the underlying state changes) are wired in implementation-pass per `[NEEDS-EMITTER-WIRING-<signal>-PASS]` flags:

```gdscript
# Phase 10B.2 trade-route trigger signals
signal settlement_created(settlement_id: String)
signal settlement_destroyed(settlement_id: String)
signal settlement_market_class_changed(settlement_id: String, old_class: int, new_class: int)
signal road_overlay_added(map_id: String, q: int, r: int)
signal road_overlay_removed(map_id: String, q: int, r: int)
signal river_overlay_added(map_id: String, q: int, r: int)
signal river_overlay_removed(map_id: String, q: int, r: int)
signal hex_water_tag_changed(map_id: String, q: int, r: int, old_water: String, new_water: String)
```

**Existing signals NOT to re-emit:**
- The substrate's `merchant_pool_refreshed`, `solicitation_started`, etc. are unrelated to trade-route detection.
- The substrate's `trade_route_detected(route_id, settlement_a_id, settlement_b_id)` and `trade_route_invalidated(route_id)` already exist on the EventBus per substrate GDD §13.5. The trigger handlers in §10.3 may emit these via the detector's existing internal emission points.

**Emitter responsibility:** any code that mutates the underlying state must fire the corresponding signal:
- `CampaignRepository.insert_settlement_entrance` → emit `settlement_created`
- Settlement deletion path (TBD location) → emit `settlement_destroyed`
- `UPDATE settlement_entrances SET market_class = ?` paths → emit `settlement_market_class_changed`
- Road / river overlay inserts and deletes → emit corresponding signals
- `hex_cells.water` updates → emit `hex_water_tag_changed`

Implementation pass identifies the current call sites for each state mutation and adds the signal emission. None of these signals exist today (per Prereq.2b's known issues: "EventBus listener wiring for `road_overlay_added/removed`, `settlement_created/destroyed`, etc. is not wired in this wave — those signals don't yet exist in the codebase").

### 10.3 Handler design — `TradeRouteTriggerHandlers`

`engine/subsystems/commerce/trade_route_trigger_handlers.gd` — a `Node` autoload (NEW autoload registration in `project.godot`) that subscribes to the EventBus signals at `_ready` and dispatches to the substrate.

**Why an autoload:** The handlers need to be always-on across the campaign lifecycle (signals can fire any time a settlement is created, an overlay changes, etc.). Per coding conventions §5, autoloads are reserved for "truly global systems" — and a system that listens for ANY map-state-changing signal qualifies.

```gdscript
extends Node

## TradeRouteTriggerHandlers (autoload — per gdd-phase-10b-2-trade-block.md §10).
##
## Subscribes to map-state-mutation signals and invokes TradeRouteDetector +
## RegionDemandResolver in the appropriate scope. Designed to be idempotent
## under signal-flood conditions (e.g., setting-generation creating many
## settlements in rapid succession; see §10.7).

const ROAD_PROXIMITY_HEXES := TradeRouteDetector._MAX_ROAD_RANGE  # 28
const WATER_PROXIMITY_HEXES := TradeRouteDetector._MAX_WATER_RANGE  # 80


func _ready() -> void:
    EventBus.settlement_created.connect(_on_settlement_created)
    EventBus.settlement_destroyed.connect(_on_settlement_destroyed)
    EventBus.settlement_market_class_changed.connect(_on_settlement_market_class_changed)
    EventBus.road_overlay_added.connect(_on_road_overlay_changed)
    EventBus.road_overlay_removed.connect(_on_road_overlay_changed)
    EventBus.river_overlay_added.connect(_on_water_geometry_changed)
    EventBus.river_overlay_removed.connect(_on_water_geometry_changed)
    EventBus.hex_water_tag_changed.connect(_on_water_geometry_changed_tag)


func _on_settlement_created(settlement_id: String) -> void:
    # New settlement → detect routes to all existing settlements in campaign.
    TradeRouteDetector.detect_routes_for_settlement(settlement_id)
    # Re-run region resolver for whatever region contains this settlement.
    RegionDemandResolver.resolve_region(settlement_id)


func _on_settlement_destroyed(settlement_id: String) -> void:
    # Delete all routes referencing this settlement.
    if not CampaignRepository.db.query_with_bindings("""
        SELECT DISTINCT
            CASE WHEN settlement_a_id = ? THEN settlement_b_id ELSE settlement_a_id END AS counterpart
        FROM trade_routes
        WHERE settlement_a_id = ? OR settlement_b_id = ?
    """, [settlement_id, settlement_id, settlement_id]):
        return
    var former_counterparts: Array = []
    for row in CampaignRepository.db.query_result:
        former_counterparts.append(str((row as Dictionary).get("counterpart", "")))
    # DELETE the routes.
    CampaignRepository.db.query_with_bindings("""
        DELETE FROM trade_routes
        WHERE settlement_a_id = ? OR settlement_b_id = ?
    """, [settlement_id, settlement_id])
    # Re-run region resolver for each formerly-connected counterpart (their
    # region topology has changed).
    for counterpart_id in former_counterparts:
        if not counterpart_id.is_empty():
            RegionDemandResolver.resolve_region(counterpart_id)


func _on_settlement_market_class_changed(settlement_id: String, _old_class: int, _new_class: int) -> void:
    # Re-detect from this settlement — range_of_trade may now include or
    # exclude counterparts that were valid under the old class.
    TradeRouteDetector.detect_routes_for_settlement(settlement_id)
    RegionDemandResolver.resolve_region(settlement_id)


func _on_road_overlay_changed(map_id: String, q: int, r: int) -> void:
    _redetect_settlements_near_hex(map_id, q, r, ROAD_PROXIMITY_HEXES)


func _on_water_geometry_changed(map_id: String, q: int, r: int) -> void:
    _redetect_settlements_near_hex(map_id, q, r, WATER_PROXIMITY_HEXES)


func _on_water_geometry_changed_tag(map_id: String, q: int, r: int, _old: String, _new: String) -> void:
    _redetect_settlements_near_hex(map_id, q, r, WATER_PROXIMITY_HEXES)


func _redetect_settlements_near_hex(map_id: String, q: int, r: int, range_hexes: int) -> void:
    # Find settlements on this map within range_hexes of (q, r).
    # v1: scan all settlements and check distance to (q, r). Per substrate §5.6
    # this is "small subset of campaign settlements unless (q, r) is in a
    # dense urban region; v1: optimize later if profiling shows hot path."
    if not CampaignRepository.db.query_with_bindings("""
        SELECT id, hex_q, hex_r FROM settlement_entrances WHERE map_id = ?
    """, [map_id]):
        return
    var affected: Array = []
    for row in CampaignRepository.db.query_result:
        var sett: Dictionary = row
        var dq: int = int(sett.get("hex_q", 0)) - q
        var dr: int = int(sett.get("hex_r", 0)) - r
        var dist: int = _hex_distance(dq, dr)
        if dist <= range_hexes:
            affected.append(str(sett.get("id", "")))
    for sid in affected:
        TradeRouteDetector.detect_routes_for_settlement(sid)
    # Re-run region resolver once per affected settlement (the resolver itself
    # deduplicates settlements that share a region — see §10.7 idempotency).
    for sid in affected:
        RegionDemandResolver.resolve_region(sid)


static func _hex_distance(dq: int, dr: int) -> int:
    # Standard hex distance formula (axial coordinates).
    return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
```

### 10.4 Re-detection scope — proximity filtering

For overlay-change signals (road / river / water tag), only settlements within the maximum trade range of the affected hex need re-detection. The 28-hex (road) and 80-hex (water) bounds come from the substrate's `RANGE_OF_TRADE` table.

**Why filter rather than re-detecting all settlements:**
- For a fresh-cohort campaign with 50 settlements, a single road tile change could trigger O(50²) detection without filtering. With filtering, typically O(K²) where K is the few settlements actually within range — usually 1-5.
- The substrate's `detect_routes_for_settlement` is O(N) per call (compares one settlement to all others); filtering caps the OUTER loop, not the inner.

**v1 limitation:** the proximity filter uses straight hex distance, not actual road/water path distance. This may FALSE-POSITIVE include settlements that are within 28 hexes straight-line but unreachable by road (no road path). The substrate's per-pair pathfinding then catches the actual unreachability — it just runs more pair-detections than strictly necessary. `[NEEDS-PROXIMITY-FILTER-OPTIMIZATION]` flag if profiling shows this is a hot path.

### 10.5 Region resolver re-run wiring

After any detection change, the affected region's demand modifiers may have shifted (step 6 of the substrate procedure). `RegionDemandResolver.resolve_region(anchor_settlement_id)` re-walks the connected region and applies step-6 shifts.

The handlers in §10.3 invoke `resolve_region` per affected settlement. The resolver internally:
- Walks the trade-route graph from the anchor → identifies the connected region
- Sorts by urban_families desc → processes largest-first
- Applies step-6 shifts to every settlement's demand modifiers
- Writes back to `settlement_merchandise_demand`

**Idempotency:** if two settlements in the same region are both affected (e.g., a road segment between them is added), the handler calls `resolve_region` twice — once for each. The two calls produce identical output because they walk the same region with the same input data. v1 accepts the redundant work; if profiling shows it's costly, the handler can dedupe by tracking which regions have been resolved this signal-burst.

### 10.6 Campaign-load full sweep

When a campaign loads, the trigger handlers above can't fire because they need a running session. The campaign-load path must explicitly invoke the full sweep:

```gdscript
# Called from SessionRunner.load_session after schema migrations + data
# autoloads complete. Detects whether the campaign's trade_routes cache is
# populated; if empty, runs the full O(N²) sweep + region resolution.
static func full_sweep_for_campaign(campaign_id: String) -> void:
    if not CampaignRepository.db.query_with_bindings(
            "SELECT COUNT(*) AS n FROM trade_routes WHERE campaign_id = ?", [campaign_id]):
        return
    var existing: int = int(CampaignRepository.db.query_result[0].get("n", 0))
    if existing > 0:
        return  # Cache already populated — no need to re-sweep on every load.
    var count: int = TradeRouteDetector.detect_routes_for_campaign(campaign_id)
    RegionDemandResolver.resolve_all_regions(campaign_id)
    print("TradeRouteTriggerHandlers: full sweep detected %d trade routes for campaign %s" % [count, campaign_id])
```

**Idempotency on load:** the `existing > 0` short-circuit ensures the sweep runs ONCE per campaign (on first load after migration 098 introduces the table) rather than every time the player loads the game. Subsequent loads skip the sweep.

**`[NEEDS-CAMPAIGN-LOAD-WIRING]` flag** for the implementation-pass to find `SessionRunner.load_session` and add the `full_sweep_for_campaign(campaign_id)` call.

### 10.7 Idempotency / signal-flood handling

Several scenarios could fire multiple signals in close succession:
- Setting-generation creates 10 settlements → 10 `settlement_created` signals → 10 `detect_routes_for_settlement` calls (each O(N) pair detection) → potentially 10 region-resolver invocations.
- World-state-mutation event re-tiles a region → multiple `road_overlay_changed` + `hex_water_tag_changed` signals.
- A single road segment added → only one signal, but it triggers `_redetect_settlements_near_hex` which calls `detect_routes_for_settlement` for K affected settlements (1 to maybe 5).

**v1 approach: idempotent + tolerant.** Each handler call is internally correct; redundant calls are wasteful but not buggy. No batching, no deduplication.

**`[NEEDS-SIGNAL-FLOOD-BATCHING-PASS]` flag** for future enhancement:
- During setting-generation, defer trigger handlers via a `defer_trade_route_recompute()` / `flush_deferred_trade_route_recompute()` pair. The generator sets the flag, fires all signals, then flushes once at end.
- During world-state-mutation events, similar deferral.
- For v1, accept the redundant work — setting-generation happens once per campaign creation; world-state mutations are rare.

### 10.8 Autoload registration

`TradeRouteTriggerHandlers` is a NEW autoload. `project.godot` `[autoload]` section gets one new line:

```
TradeRouteTriggerHandlers="*res://engine/subsystems/commerce/trade_route_trigger_handlers.gd"
```

This is the FIRST commerce-subsystem autoload Phase 10B.2 introduces (substrate Phase 10B-prereq introduced `MerchandiseRegistry` as the first commerce autoload; this is the second). The autoload starts listening at session startup; signal subscriptions fire immediately.

### 10.9 What §10 does NOT add

- **No new substrate APIs.** All detection + resolution is via the existing Prereq.2b APIs. This section is wiring only.
- **No emitter-side implementation.** The eight signals listed in §10.2 are CONTRACTS. The places in the codebase that actually FIRE them need to be located + extended. Each is flagged `[NEEDS-EMITTER-WIRING-<signal>-PASS]`.
- **No batching / deferred-execution layer.** Per §10.7 deferred to `[NEEDS-SIGNAL-FLOOD-BATCHING-PASS]`.
- **No proximity-filter optimization.** Per §10.4 straight-line hex distance is the v1 filter; pathfinding-aware filtering deferred to `[NEEDS-PROXIMITY-FILTER-OPTIMIZATION]`.
- **No incremental detection.** Each `detect_routes_for_settlement` call wipes-and-replaces routes for that settlement. A more sophisticated implementation might diff old-vs-new sets to fire `trade_route_invalidated` only for routes that genuinely changed. v1 is fire-and-forget.
- **No multi-map detection.** Routes only consider settlements on the SAME `map_id` (per substrate `TradeRouteDetector.compute_*_distance` which validates `a.map_id == b.map_id`). Cross-map trade is a future feature.
- **No campaign-load forced re-sweep.** The `existing > 0` short-circuit means the sweep runs once-ever per campaign. If a future schema change requires a fresh sweep, that migration's job is to clear `trade_routes` first.

---

## §11. Monthly Tick Wiring — Architecture Options + Recommendation

### 11.0 Overview + Q-TB-13 resolution

The substrate Phase 10B-prereq ships **four campaign-wide monthly drivers**:

| Driver | Purpose | Substrate location |
|---|---|---|
| `MerchantPoolRepository.process_monthly_refresh_for_campaign(campaign_id, current_calendar_day, rng)` | Wipes prior cohort (preserves manual + promoted), generates fresh max-count merchants per settlement | Prereq.4 |
| `MarketPriceResolver.process_monthly_drift_for_campaign(campaign_id, current_calendar_day, rng)` | Re-rolls cached 4d4 dice with cumulative 10%/month probability per settlement-merchandise pair | Prereq.2c |
| `ShipRepository.process_monthly_operating_costs_for_campaign(campaign_id, current_calendar_day)` | Debits crew/maintenance from party wallets per non-destroyed ship | Prereq.5a |
| `MarketFeesCalculator.process_annual_customs_roll_for_campaign(campaign_id, current_year)` | Year-boundary only — rolls new `customs_duty_rate_pct` per settlement (1d10+1d10) | Prereq.3 |

None of them are wired into the monthly-tick infrastructure yet. Per substrate Prereq.5a + Prereq.5c known issues: "The monthly-tick wiring point (`DomainMonthlyResolver` invoking the substrate-shipped drivers) is not yet activated. Phase 10B.2's monthly tick handler adds all calls in one wave."

Q-TB-13 [RESOLVED 2026-05-13]: architecture decision is mine to recommend. §11.3 evaluates four options + recommends Option D.

### 11.1 Existing monthly-tick infrastructure (audit)

Per the substrate's repeated references to `DomainMonthlyResolver`, the existing infrastructure is presumed to be:

- A `DomainMonthlyResolver` (likely `engine/subsystems/domain/domain_monthly_resolver.gd` or similar) that fires per-month per-campaign.
- Called from the session-runner's calendar-advancement code on month-boundary detection (`new_calendar_day % Timekeeping.DAYS_PER_MONTH == 1` or equivalent).
- Already processes Phase 9 + Phase 10A.2 monthly logic (domain revenue, congregant_pending_gp updates, follower lifecycle, etc.).

The implementation pass identifies the exact call site + signature of `DomainMonthlyResolver.process_month_for_campaign(...)` (or whatever it's called) and adds Phase 10B.2's commerce drivers to it per §11.4's recommended option.

### 11.2 Driver dependencies + ordering

The four drivers operate on different tables/columns with NO transactional dependencies between them. Ordering is functionally irrelevant; however, narrative ordering aids debugging and log readability:

| Order | Driver | Rationale |
|---|---|---|
| 1 | Annual customs roll (year-boundary only) | Start-of-year fiscal decisions before merchants set up shop. |
| 2 | Ship operating costs | Regular monthly bills paid before new cohort arrives. |
| 3 | Merchant pool refresh | New month, new merchants. |
| 4 | Market price drift | Prices may shift in the new cohort's wake. |

This ordering is canonical for Phase 10B.2's implementation. If a future system introduces a dependency (e.g., "customs rate affects merchant arrival probability"), the order is re-evaluated then.

### 11.3 Architecture options — analysis

**Option A: Extend `DomainMonthlyResolver` directly with commerce calls**

- **Shape:** add four function calls (or three + a year-tick check) directly to `DomainMonthlyResolver.process_month_for_campaign`.
- **Pros:** One coordinator. No new files. Consistent with how Phase 10A.2 added congregant ticks (presumably also extended the same resolver).
- **Cons:** `DomainMonthlyResolver` accumulates non-domain concerns (commerce, faith, magical research, ...). The file grows; "domain" becomes a misnomer.

**Option B: New `CommerceMonthlyResolver` autoload listening to a `month_advanced` EventBus signal**

- **Shape:** new autoload subscribes to `EventBus.month_advanced(campaign_id, new_month, new_year)`. `DomainMonthlyResolver` emits this signal when its own monthly logic completes.
- **Pros:** Maximum separation. Commerce ticks live in commerce land.
- **Cons:** Yet another autoload. Requires the `month_advanced` signal to exist (likely needs to be added). Signal ordering between subscribers becomes a coordination concern.

**Option C: One autoload per driver (extreme separation)**

- **Shape:** four separate `<DriverName>MonthlyHandler` autoloads, each subscribed to `month_advanced`.
- **Pros:** Maximum modularity.
- **Cons:** Four autoloads for what's conceptually one wave of work. Excessive for v1.

**Option D: `CommerceMonthlyResolver` static dispatcher called from `DomainMonthlyResolver`** ★ RECOMMENDED

- **Shape:** new `engine/subsystems/commerce/commerce_monthly_resolver.gd` (RefCounted static-function library, not an autoload). Single entry point: `CommerceMonthlyResolver.process_for_campaign(campaign_id, current_calendar_day, current_year, rng) -> Dictionary`. `DomainMonthlyResolver` adds ONE line invoking it.
- **Pros:**
  - Preserves the single-coordinator pattern (`DomainMonthlyResolver` is the canonical "monthly things happen here" entry point).
  - Commerce-specific logic lives in a commerce file (modular).
  - No new autoload (lower system overhead).
  - No EventBus signal coordination needed.
  - Implementation-pass change to `DomainMonthlyResolver` is minimal — one function call.
  - Easy to test in isolation (the dispatcher takes campaign_id + day + year + rng as parameters; can be invoked directly from a test).
- **Cons:**
  - The order-of-operations between domain ticks and commerce ticks is locked into wherever `DomainMonthlyResolver` invokes commerce. v1 puts commerce AFTER domain (revenue accrues before market refresh consumes party wallet). If a future system wants different ordering, the line moves.
- **Verdict:** ★ Recommended. The static-function library + thin call-site pattern is the cleanest extension of the existing infrastructure.

### 11.4 Recommended design — `CommerceMonthlyResolver`

`engine/subsystems/commerce/commerce_monthly_resolver.gd`:

```gdscript
class_name CommerceMonthlyResolver
extends RefCounted

## Commerce-side monthly tick dispatcher (Phase 10B.2 — Trade block).
## Per gdd-phase-10b-2-trade-block.md §11. Static-function library; not an
## autoload. Invoked from DomainMonthlyResolver.process_month_for_campaign
## (or equivalent existing coordinator) once per month per campaign.
##
## Drivers fire in narrative order:
##   1. Annual customs roll (year-boundary only, de-dup'd via campaigns.last_customs_roll_year)
##   2. Ship operating costs
##   3. Merchant pool refresh
##   4. Market price drift

static func process_for_campaign(
        campaign_id: String,
        current_calendar_day: int,
        current_year: int,
        rng: RandomNumberGenerator
) -> Dictionary:
    if campaign_id.is_empty() or rng == null:
        return {"summary": "skipped: empty campaign_id or null rng"}

    var results: Dictionary = {
        "campaign_id": campaign_id,
        "calendar_day": current_calendar_day,
        "year": current_year,
    }

    # 1. Annual customs roll (year-boundary; per §12 architecture).
    var customs_rolled: int = _maybe_roll_annual_customs(campaign_id, current_year)
    results["customs_rolled"] = customs_rolled

    # 2. Ship operating costs.
    var ship_gp_debited: int = ShipRepository.process_monthly_operating_costs_for_campaign(
        campaign_id, current_calendar_day)
    results["ship_gp_debited"] = ship_gp_debited

    # 3. Merchant pool refresh.
    var merchants_generated: int = MerchantPoolRepository.process_monthly_refresh_for_campaign(
        campaign_id, current_calendar_day, rng)
    results["merchants_generated"] = merchants_generated

    # 4. Market price drift.
    var prices_drifted: int = MarketPriceResolver.process_monthly_drift_for_campaign(
        campaign_id, current_calendar_day, rng)
    results["prices_drifted"] = prices_drifted

    EventBus.commerce_monthly_tick_completed.emit(campaign_id, results)
    return results


static func _maybe_roll_annual_customs(campaign_id: String, current_year: int) -> int:
    # Read campaigns.last_customs_roll_year. If current_year is strictly
    # greater, fire the customs roll. The substrate helper updates
    # campaigns.last_customs_roll_year as part of its work.
    if not CampaignRepository.db.query_with_bindings(
            "SELECT last_customs_roll_year FROM campaigns WHERE id = ?", [campaign_id]):
        return 0
    if CampaignRepository.db.query_result.is_empty():
        return 0
    var last_year: int = int(CampaignRepository.db.query_result[0].get("last_customs_roll_year", 0))
    if current_year <= last_year:
        return 0
    # Fire the roll. The substrate helper handles its own DB updates
    # (campaigns.last_customs_roll_year + settlement_entrances.customs_duty_rate_pct).
    return MarketFeesCalculator.process_annual_customs_roll_for_campaign(campaign_id, current_year)
```

**DomainMonthlyResolver delta** (implementation-pass change):

```gdscript
# In DomainMonthlyResolver.process_month_for_campaign(campaign_id, day, ...)
# AFTER existing domain logic completes:
var current_year: int = Timekeeping.year_for_calendar_day(day)
var rng: RandomNumberGenerator = _seeded_monthly_rng(campaign_id, day)
CommerceMonthlyResolver.process_for_campaign(campaign_id, day, current_year, rng)
```

**Single point of change** to `DomainMonthlyResolver`. Minimal coupling.

### 11.5 Driver ordering (narrative + safety)

Per §11.2: customs → ships → merchants → prices. The implementation pseudocode in §11.4 follows this order verbatim. If a future system introduces a dependency that requires re-ordering, the dispatcher's body is the single point of change.

**Safety note:** the four drivers all guard against empty inputs (verified during substrate review):
- `process_monthly_refresh_for_campaign` returns 0 on empty campaign_id
- `process_monthly_drift_for_campaign` skips settlements with no demand cache rows
- `process_monthly_operating_costs_for_campaign` skips destroyed ships + orphan ships (no party_id)
- `process_annual_customs_roll_for_campaign` short-circuits if no settlement rows

So a freshly-created campaign with zero settlements / ships / etc. is handled gracefully.

### 11.6 RNG seeding for determinism

For replay safety, the rng passed into `CommerceMonthlyResolver.process_for_campaign` must be seeded deterministically per `(campaign_id, calendar_day)`. The caller (`DomainMonthlyResolver`) computes:

```gdscript
static func _seeded_monthly_rng(campaign_id: String, calendar_day: int) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("monthly|%s|%d" % [campaign_id, calendar_day])
    return rng
```

Same campaign on the same calendar_day produces the same dice sequence — drift outcomes, merchant generation rolls, etc. are reproducible across save/load.

**Note on substrate's `process_monthly_refresh_for_campaign`:** the merchant pool generator consumes the rng for both merchandise-type roll and loads_dice per merchant. Order of consumption determines outcomes, so iteration over settlements must be deterministic (ORDER BY id ASC — verify in substrate or add). Same for `process_monthly_drift_for_campaign` per-pair processing. Implementation-pass verifies the substrate iterators are ordered.

### 11.7 LLM-promotion-aware merchant refresh (§0.1.1 cross-reference)

Per §0.1.1, the merchant pool's monthly refresh must preserve `promoted_npc_id IS NOT NULL` rows (re-cycling them in-place with fresh `loads_available` + extended `expires_at_calendar_day`). This is the SUBSTRATE's responsibility — `process_monthly_refresh_for_campaign` (per Prereq.4) must be updated in implementation-pass to:

1. Wipe `source_kind='monthly_refresh' AND promoted_npc_id IS NULL` rows (current behavior is `source_kind='monthly_refresh'` only — needs the additional clause per §0.1.1).
2. UPDATE rows where `promoted_npc_id IS NOT NULL`: re-roll `loads_available` from the class's loads_dice; extend `expires_at_calendar_day` by 28 days; reset `becomes_visible_calendar_day` (immediately visible at PC-owned domain; INVISIBLE_SENTINEL otherwise); CLEAR `refused_at_calendar_day` (§4's persuade-fail flag) back to NULL.
3. Generate `max_merchant_count(class) - existing_promoted_count` new transactional rows.

This is a Phase 10B.2 **modification of substrate code** (not a new substrate addition). The substrate's `process_monthly_refresh_for_campaign` and `process_expirations` need the §0.1.1 preservation clauses added. The §17 implementation-pass wave plan covers this in its "substrate amendments" deliverable.

**`[NEEDS-SUBSTRATE-AMENDMENT-LLM-PROMOTION-PASS]`** flag at the substrate-call sites.

### 11.8 Year-tick handling (defers to §12)

Per §11.4, the year-boundary detection lives inside `_maybe_roll_annual_customs` — reads `campaigns.last_customs_roll_year` and short-circuits if not advanced. This is **Y-Option 3** per §12's architecture analysis. Full discussion of why this approach beats "month==1 check" in §12.

### 11.9 EventBus signal additions

```gdscript
# Phase 10B.2 monthly-tick observability
signal commerce_monthly_tick_completed(campaign_id: String, results: Dictionary)
```

The results dict carries the four drivers' return values for UI / log / test consumption. A single signal-per-tick (rather than four per-driver signals) keeps the observability surface small; consumers that care about specific drivers can read `results["merchants_generated"]` etc.

The substrate's per-driver signals (`merchant_pool_refreshed`, `market_price_drifted`, `ship_operating_cost_paid/unpaid`) continue to fire from inside the substrate calls. The new aggregate signal is additive.

### 11.10 Implementation-pass deliverables

The §17 wave plan (TBD) ships these:

1. Author `engine/subsystems/commerce/commerce_monthly_resolver.gd` per §11.4.
2. Locate `DomainMonthlyResolver.process_month_for_campaign` (or equivalent) and add the `CommerceMonthlyResolver.process_for_campaign(...)` call after the existing domain logic.
3. Locate the substrate's `MerchantPoolRepository.process_monthly_refresh_for_campaign` + `process_expirations` and add the §0.1.1 LLM-promotion preservation clauses (`AND promoted_npc_id IS NULL` filters + the promoted-row UPDATE path).
4. Verify the substrate iterators in `process_monthly_refresh_for_campaign` + `process_monthly_drift_for_campaign` use deterministic ordering (`ORDER BY id ASC` or equivalent).
5. Add `commerce_monthly_tick_completed` to `event_bus.gd` per §16.
6. Add unit tests per §18 (mocking the four substrate drivers; verifying call order + parameter forwarding).

### 11.11 What §11 does NOT add

- **No new monthly drivers.** The four substrate-shipped drivers cover all Phase 10B.2 monthly state. If a future system (e.g., Phase 10B.3 syndicate) needs its own monthly tick, it gets a `SyndicateMonthlyResolver.process_for_campaign(...)` call added to `DomainMonthlyResolver` (or a similar central coordinator).
- **No batched / deferred execution.** The four drivers fire in sequence on the same call. If profiling shows any one is a hot path that should run async, refactor then.
- **No retry / failure-recovery logic.** If a driver fails (e.g., DB error mid-merchant-generation), v1 swallows the error and continues to the next driver. Logging is per-driver's responsibility. Future enhancement: explicit transaction-per-driver with rollback on failure.
- **No mid-month tick.** Drivers fire ONCE per month. The merchant refresh wipes-and-replaces; drift checks per pair; ship costs debit once; customs roll once per year. No more frequent cadence.
- **No PC-driven manual monthly trigger.** Players can't manually advance the month or fire commerce ticks. The session calendar runs the show.
- **No retroactive monthly catch-up.** If the player loads a campaign saved mid-month and the new calendar_day implies missed monthly boundaries, the catch-up logic is the SessionRunner's responsibility (likely already-existing for Phase 9 / 10A.2 ticks). Phase 10B.2's commerce drivers join the same catch-up path.

---

## §12. Year-Tick Trigger Architecture

### 12.0 Overview + Q-TB-14 resolution

Phase 10B.2 has ONE year-bound driver: `MarketFeesCalculator.process_annual_customs_roll_for_campaign(campaign_id, current_year)`. It re-rolls customs_duty_rate_pct per settlement on the year boundary (project rule per substrate §8.4). The substrate guards with `campaigns.last_customs_roll_year` so the helper is idempotent if called repeatedly within the same year.

Q-TB-14 [RESOLVED 2026-05-13]: architecture choice for "where does the year-tick happen" is mine to recommend. §12.1 evaluates three options + recommends Y-Option 3 (already adopted in §11.4).

### 12.1 Year-tick options — analysis

**Y-Option 1: Month-boundary explicit check in `DomainMonthlyResolver`**

- **Shape:** the monthly resolver checks `if current_month == 1 and current_year > last_customs_roll_year: invoke_customs_roll()`.
- **Pros:**
  - Year-tick logic visible at the monthly call site; reader sees "month 1 = year start = customs."
  - No reliance on the substrate's column-based de-dup.
- **Cons:**
  - Month-detection arithmetic (`day % DAYS_PER_MONTH == 1`?) bleeds into the resolver; couples year-tick to month-tick.
  - Brittle if calendar conventions ever change (e.g., a future system shifts year boundary).
  - Year-tick code lives in a domain file rather than a commerce file.
- **Verdict:** Rejected. Calendar coupling is fragile.

**Y-Option 2: Separate `year_advanced` EventBus signal subscribed by a new year-tick autoload / handler**

- **Shape:** `EventBus.year_advanced(campaign_id, old_year, new_year)` fires when the SessionRunner's calendar-advancement detects a year boundary. A new handler / autoload subscribes and invokes `process_annual_customs_roll_for_campaign(campaign_id, new_year)`.
- **Pros:**
  - Clean separation — year-tick logic is its own concern.
  - Multiple subscribers possible (Phase 10B.3 syndicate could need a year-tick too).
- **Cons:**
  - Requires the SessionRunner to detect year boundaries explicitly (not currently a thing).
  - Yet another autoload or signal handler.
  - Signal-ordering between `month_advanced` and `year_advanced` (when both fire at the same boundary) needs coordination.
- **Verdict:** Rejected for v1. Over-engineering when only one year-bound driver exists. Reconsider if Phase 10B.3+ adds multiple year-bound drivers (see §12.4).

**Y-Option 3: Idempotent check inside `CommerceMonthlyResolver` (data-driven de-dup)** ★ RECOMMENDED + ADOPTED IN §11.4

- **Shape:** `CommerceMonthlyResolver._maybe_roll_annual_customs` reads `campaigns.last_customs_roll_year`; if `current_year > last_year`, invokes `process_annual_customs_roll_for_campaign(campaign_id, current_year)`. The substrate helper updates `last_customs_roll_year` itself as part of its work.
- **Pros:**
  - Idempotent — safe to call every month. The de-dup is data-driven (a DB column), not control-flow-driven.
  - No new infrastructure (signal, autoload, handler) beyond the existing commerce monthly dispatcher.
  - Self-healing — if a year-tick is somehow missed (e.g., player saved before the boundary and loaded after a year had passed), the very next monthly tick catches it.
  - The substrate's `process_annual_customs_roll_for_campaign` was designed for exactly this pattern per Prereq.3 build_log.
- **Cons:**
  - Customs-roll logic lives in the commerce monthly dispatcher rather than a year-tick file.
  - If Phase 10B.3+ adds multiple year-bound drivers, each would need its own `_maybe_<roll_X>` helper inside its own monthly dispatcher.
- **Verdict:** ★ Recommended. Already adopted in §11.4. v1's simplest robust path.

### 12.2 Adopted design — Y-Option 3 (recap)

Per §11.4's `CommerceMonthlyResolver._maybe_roll_annual_customs`:

```gdscript
static func _maybe_roll_annual_customs(campaign_id: String, current_year: int) -> int:
    if not CampaignRepository.db.query_with_bindings(
            "SELECT last_customs_roll_year FROM campaigns WHERE id = ?", [campaign_id]):
        return 0
    if CampaignRepository.db.query_result.is_empty():
        return 0
    var last_year: int = int(CampaignRepository.db.query_result[0].get("last_customs_roll_year", 0))
    if current_year <= last_year:
        return 0  # Already rolled this year — no-op.
    return MarketFeesCalculator.process_annual_customs_roll_for_campaign(campaign_id, current_year)
```

Called every month from `CommerceMonthlyResolver.process_for_campaign`. Fires the customs roll exactly once per year. Idempotent across save/load + retroactive monthly catch-up scenarios.

### 12.3 Missed-years semantics

**Scenario:** player saves at end of year 1233 (last_customs_roll_year = 1233). They don't load the campaign for a while. When they next load, the calendar advances to year 1235 in a single catch-up pass.

The first monthly tick after load sees `current_year = 1235 > last_year = 1233`. `_maybe_roll_annual_customs` fires `process_annual_customs_roll_for_campaign(campaign_id, 1235)`. The substrate rolls fresh customs rates for 1235 and sets `last_customs_roll_year = 1235`.

**Year 1234 was skipped.** No customs rates for 1234 are stored anywhere. **Project resolution:** missed years have no in-world effect; the substrate's deterministic seeded roll formula (`hash("settlement_id|year|customs")`) means each year's rates are derivable on demand if a future audit / replay system ever needs them. v1 doesn't need them.

Per RAW silent on missed-years semantics. Project rule: **only the CURRENT year's customs rate is in force.** No catch-up rolls; the in-world flavor is "tax policy was set at start of this year; previous years' policies are historical and unrecorded."

`[NEEDS-MISSED-YEAR-AUDIT-PASS]` flag if a future system wants to log every year's customs rate for audit / narrative purposes.

### 12.4 Future systems needing year-tick — extensibility

If Phase 10B.3 (or a later wave) introduces additional year-bound drivers (e.g., "annual treasury audit," "annual realm tier classification," "annual tax filing"), the recommended extension follows Option 3's pattern:

1. Each subsystem gets its own `_maybe_<roll_X>` helper inside its own monthly dispatcher (or a new domain-specific dispatcher).
2. Each helper uses a data-driven de-dup column (e.g., `campaigns.last_X_roll_year` for each).
3. No central year-tick coordinator needed.

If the count of year-bound drivers grows past ~3-4, revisit and consider promoting to Y-Option 2 (centralized `year_advanced` signal). `[NEEDS-YEAR-TICK-CENTRALIZATION-PASS]` flag for the future.

### 12.5 Cross-section impacts

- **§8 monopoly registry:** `monopoly_holdings.expires_at_calendar_day` is a per-row column; expiration is filter-on-read, not a year-tick. No year-tick wiring needed for monopolies.
- **§11 monthly dispatcher:** the `_maybe_roll_annual_customs` helper lives inside `CommerceMonthlyResolver`. Already specified.
- **§7 shipping contracts:** offers / deadlines are calendar-day based, not year-based. No year-tick interaction.

The only year-bound state in Phase 10B.2 is customs duty rate. Everything else is monthly or per-day.

### 12.6 What §12 does NOT add

- **No new file.** §11 already specified `CommerceMonthlyResolver` and the `_maybe_roll_annual_customs` helper. §12's role is to FORMALIZE the architecture choice + document the alternatives considered + reserve the future extensibility pattern.
- **No retroactive customs-rate-history.** Missed years (per §12.3) leave no in-DB trace. Audit could reproduce them from the deterministic seed if needed.
- **No mid-year customs change.** Once rolled at year start, the customs rate is fixed for the year. Per substrate §8.4 explicit rule.
- **No multiple-customs-tier-per-settlement.** One rate per settlement per year. Class differences are reflected via the roll values, not stratified rates.
- **No PC-driven manual customs reroll.** A Judge could mutate `settlement_entrances.customs_duty_rate_pct` directly via debug tooling if needed. v1 doesn't expose a "reroll customs" UI.

---

## §13. Partial-Load Handling — Split Semantics + Lost-Vehicle Edge Case

### 13.0 Overview + Q-TB-6 resolution

Q-TB-6 [RESOLVED 2026-05-13]: "Both options: per row and sell-all, but we ned to be careful about selling split loads, as the RAW rules track whole loads for available buy/sell... I would opt for forcing whole-load selling, but that introduces the edge case of a lost vehicle taking a partial load of merchandise with it (one wagon out of 10 burns on the way, now what with the rest of the load?) Maybe we should handle partial loads after all?"

**The clarification that resolves the tension:** the substrate's `cargo_holds.loads_count` is always INTEGER. "Partial loads" in this GDD's sense means "fewer-than-original loads in the same cargo row" — each remaining load is still WHOLE. RAW-faithful: loads are whole; counts decrement; no fractional units appear anywhere.

The user's "10 wagons, 1 burns" concern is also resolved by the substrate's per-carrier cargo aggregation — each wagon already has its OWN `cargo_holds` row. Losing one wagon loses one row's cargo; the other 9 rows are unaffected. No "split a load across vehicles" complication because loads aren't split below the row level.

§13 ships:
1. **`CargoHoldRepository.partial_sell` helper** (§13.2) — the missing API §3.3's sell handler calls.
2. **Destroyed-carrier cargo filtering** (§13.4-§13.5) — UI helpers that hide cargo on `is_destroyed=1` carriers without immediately deleting the row.
3. **FK-enforcement / CASCADE story** (§13.6) — when hard-delete is appropriate vs soft-delete.

### 13.1 Whole-load semantics (no fractional loads anywhere)

`cargo_holds.loads_count` is `INTEGER NOT NULL`. Every Phase 10B.2 operation that mutates it preserves integer-ness:
- **Buy:** INSERT with positive integer `loads_count`.
- **Sell (full):** DELETE row (loads_count goes to 0 via row removal, not in-place).
- **Sell (partial):** UPDATE `loads_count = loads_count - loads_to_sell` where both operands are positive integers; if `loads_to_sell == loads_count`, fall through to full sell.
- **Transfer:** moves integer-count loads between rows.
- **Hijink yield (substrate):** INSERT with positive integer `loads_count`.

No fractional-load codepath exists. RAW-faithful: "a load is a load."

### 13.2 `CargoHoldRepository.partial_sell` — new substrate method

§3.3's sell handler calls `CargoHoldRepository.partial_sell(cargo_hold_id, loads_to_sell, cp_received)`. The substrate ships `delete_sold` (full sell) and `transfer_loads` (between carriers) but NOT a partial-sell helper. Phase 10B.2 adds it as a substrate amendment.

```gdscript
## Decrements [param loads_count] by [param loads_to_sell]. If the decrement
## reaches 0, delegates to delete_sold for atomic row removal. Emits
## cargo_sold signal with [param cp_received] regardless of path.
static func partial_sell(cargo_hold_id: String, loads_to_sell: int, cp_received: int) -> bool:
    if cargo_hold_id.is_empty() or loads_to_sell <= 0:
        return false
    var row: Dictionary = get_cargo_hold(cargo_hold_id)
    if row.is_empty():
        return false
    var current_loads: int = int(row.get("loads_count", 0))
    if loads_to_sell > current_loads:
        return false
    if loads_to_sell == current_loads:
        # Full sell — delegate.
        return delete_sold(cargo_hold_id, cp_received)
    # Partial — decrement loads_count.
    if not CampaignRepository.db.query_with_bindings(
            "UPDATE cargo_holds SET loads_count = loads_count - ? WHERE id = ?",
            [loads_to_sell, cargo_hold_id]):
        return false
    EventBus.cargo_sold.emit(cargo_hold_id, cp_received)
    return true
```

**Why emit `cargo_sold` on partial too:** the signal's listeners (UI, transaction log) don't need to distinguish full vs partial — both events represent "merchandise moved off this row for cp_received gp." If a future system needs the distinction, add a `loads_sold` param to the signal payload. v1's signal is sufficient.

**Implementation pass deliverable:** add `partial_sell` to `engine/subsystems/commerce/cargo_hold_repository.gd`. `[NEEDS-SUBSTRATE-AMENDMENT-PARTIAL-SELL]` flag.

### 13.3 Multi-carrier contracts — single-carrier limitation

The substrate's `CargoHoldRepository.insert_shipping_contract_load(carrier_id, carrier_kind, ...)` takes ONE carrier_id. A shipping contract's full `loads_count` lands on ONE carrier. Phase 10B.2's `accept_shipping_contract` handler (§7.7) enforces this via the capacity check — contracts whose `loads_count × load_weight_stone` exceeds the selected carrier's `load_max_stone` (for wagons) or `cargo_capacity_stone` (for ships) are rejected.

**v1 limitation:** large contracts that need a multi-wagon caravan to fulfill cannot be accepted with a single wagon. The player either:
- Owns a wagon big enough (load_max_stone ≥ required).
- Doesn't accept the contract.

For RAW-cited 6d8-loads Class I contracts (up to 48 loads × 70 stone = 3,360 stone), a single wagon (load_max 640 stone) is INSUFFICIENT. A small sailing ship (cargo_capacity_stone = 10,000 from substrate maritime catalog) fits comfortably. So large Class I contracts effectively require ship transport.

**`[NEEDS-MULTI-CARRIER-CONTRACT-PASS]` flag** for the future multi-wagon distribution UX. The substrate's per-vehicle aggregation supports it data-model-wise — Phase 10B.2 just doesn't ship the UI flow that distributes a contract's loads across multiple carriers.

### 13.4 Lost-vehicle edge case — per-carrier cargo aggregation

The user's example: "one wagon out of 10 burns on the way, now what with the rest of the load?"

**Resolution via substrate per-carrier aggregation:**
- Each wagon's cargo is its OWN `cargo_holds` row (substrate §9.4).
- Wagon #3 burning destroys the row(s) attached to wagon #3 only.
- Wagons #1-2 and #4-10's rows are unaffected.
- The player continues with the remaining cargo.

**No "split load across vehicles" problem** because cargo isn't split below the row level. A 50-load grain shipment distributed across 6 wagons would already be in 6 cargo_holds rows (one per wagon), inserted via 6 transfer_loads calls from an initial single-wagon buy.

**v1 carrier destruction paths:**
- **Soft destroy (`is_destroyed = 1`):** the carrier row stays in the DB; cargo rows still reference it. Player can't access the cargo (it's on a destroyed carrier). UI filters via §13.5. v1's default — destroy_ship (substrate Prereq.5a) sets `is_destroyed=1` without DELETEing the ship row.
- **Hard destroy (`DELETE FROM ships WHERE id = ?` or equivalent):** if FK enforcement is enabled, CASCADE wipes the cargo rows. v1 has FK enforcement OFF (substrate Prereq.5b known issue), so manual hard-delete leaves orphan cargo rows. Phase 10B.2 doesn't enable FK enforcement — that's `[NEEDS-FK-ENFORCEMENT-PASS]` for future hardening.

### 13.5 UI filtering — destroyed-carrier cargo hidden from sell/transfer UIs

The mercantile_panel's sell section (§3.6) lists "party cargo." If a wagon has been soft-destroyed, its cargo rows are orphan from the player's perspective — they shouldn't appear in the dropdown.

**New substrate read helper** for the active-cargo case:

```gdscript
## Returns all cargo_holds rows owned by [param party_id] whose carriers are
## NOT destroyed. Joined view across draft_vehicles + ships.
static func list_for_party_active_carriers(party_id: String) -> Array:
    if party_id.is_empty():
        return []
    if not CampaignRepository.db.query_with_bindings("""
        SELECT ch.* FROM cargo_holds ch
        LEFT JOIN draft_vehicles dv ON ch.draft_vehicle_id = dv.id
        LEFT JOIN ships s ON ch.ship_id = s.id
        WHERE ((dv.id IS NOT NULL AND dv.party_id = ? AND dv.is_destroyed = 0)
            OR (s.id IS NOT NULL AND s.party_id = ? AND s.is_destroyed = 0))
        ORDER BY ch.created_at ASC
    """, [party_id, party_id]):
        return []
    return CampaignRepository.db.query_result.duplicate()
```

The sell-section UI calls `list_for_party_active_carriers(party_id)` instead of `list_for_draft_vehicle` / `list_for_ship` individually. The existing per-carrier helpers stay unchanged for callers that care about a SPECIFIC carrier (e.g., the cargo manifest in a vehicle detail panel).

**Implementation pass deliverable:** add `list_for_party_active_carriers` to `cargo_hold_repository.gd`. `[NEEDS-SUBSTRATE-AMENDMENT-LIST-ACTIVE]` flag.

### 13.6 FK-enforcement + CASCADE story

Per substrate Prereq.5b known issues:
> "ON DELETE CASCADE on carrier FKs is documented defensive metadata; not actively exercised by v1 carrier destruction (soft-delete path). If a future system enables FK enforcement and DELETEs parent ships/vehicles, cargo cleanup will fire automatically."

Phase 10B.2 does NOT change this. Soft-delete remains the canonical destruction path; orphan cargo rows are filtered out at the read layer (§13.5).

**When hard-delete is appropriate:**
- Administrative cleanup (a cleanup wave / Judge tooling)
- After all gameplay references are confirmed gone

**When soft-delete is appropriate:**
- In-game destruction (combat, encounter, weather damage to ships)
- Player-initiated decommission (sell or scrap a wagon — but keep audit trail of past transactions)

Both paths are RAW-acceptable. Phase 10B.2 ships the soft-delete-friendly UI filter; future hardening can flip FK enforcement when ready.

### 13.7 Cargo-loss accounting at destruction

When a carrier is destroyed (soft or hard), the cargo on it is lost from the player's perspective. The player may want to see "you lost 10 silk loads when Wagon Hauler #3 burned."

**v1 approach:** no explicit destruction-event signaling for cargo loss. The cargo rows sit orphan; the player's NEXT visit to a mercantile UI shows their cargo list shrunk. The UI can compute "I had 50 loads before; I have 40 now" via list comparison if it wants.

**`[NEEDS-CARGO-LOSS-DESTRUCTION-SIGNAL-PASS]` flag** for the future enhancement:
- ShipRepository.destroy_ship (and the equivalent draft_vehicle destroy path) emits a signal `carrier_destroyed_with_cargo(carrier_id, carrier_kind, cargo_holds_ids: Array, total_market_value_gp: int)`.
- UI / log surface "Lost X loads of Y worth Z gp."
- For v1, the destruction is silent on cargo specifics.

### 13.8 Lost-vehicle within a shipping contract

If the player accepts a shipping contract and the carrier with the contract cargo is destroyed mid-transit:
- The cargo_holds row (with `source_acquisition_kind='shipping_contract'` + `shipping_contract_id` set) is orphaned on the destroyed carrier.
- The `shipping_contracts` row remains `status='accepted'` (or `'in_transit'`).
- The player can't deliver the cargo (it's lost).
- The deadline eventually passes → substrate's `deliver(contract_id, current_day)` returns `deadline_missed=true` and the substrate flips status to `'failed_deadline'`.
- The player gets nothing; future system can layer a reputation penalty.

**No explicit "contract failed due to lost cargo" handling in v1.** The deadline-failure path subsumes it (player can't deliver → deadline missed → contract failed). `[NEEDS-CONTRACT-CARGO-LOSS-EXPLICIT-PASS]` flag if a future enhancement wants to surface the cargo-loss event as a distinct contract failure reason (with potentially different reputation penalties).

### 13.9 Cross-section impacts

- **§3.3 sell handler** invokes `CargoHoldRepository.partial_sell` for partial sells (§13.2).
- **§3.6 sell UI** invokes `CargoHoldRepository.list_for_party_active_carriers` (§13.5) for the cargo dropdown.
- **§7 shipping contracts** are single-carrier per §13.3 limitation; capacity check at accept time enforces.
- **Substrate ShipRepository / draft_vehicle destruction paths** — v1 stays on soft-delete; CASCADE remains dormant.

### 13.10 EventBus signal additions

None for v1. The new substrate helpers (`partial_sell`, `list_for_party_active_carriers`) reuse existing signals (`cargo_sold` per Prereq.5b). The optional `carrier_destroyed_with_cargo` signal is flagged for future per §13.7.

### 13.11 What §13 does NOT add

- **No fractional loads.** `loads_count` stays integer everywhere.
- **No multi-carrier shipping contracts.** v1 limits contracts to single-carrier shipments per §13.3.
- **No cargo redistribution UI** for the "wagon #3 burns" case. Player must pre-transfer cargo with `transfer_loads` if they want to spread risk; once a wagon dies, its cargo is lost.
- **No salvage / partial-recovery flow.** A destroyed carrier loses 100% of its cargo. No "salvage roll" to recover some.
- **No FK enforcement.** Carriers stay on the soft-delete path; CASCADE is documented but dormant.
- **No explicit cargo-loss signaling on destruction.** `[NEEDS-CARGO-LOSS-DESTRUCTION-SIGNAL-PASS]` for future enhancement.
- **No explicit contract-cargo-loss signaling.** The deadline-failure path subsumes it. `[NEEDS-CONTRACT-CARGO-LOSS-EXPLICIT-PASS]` for future enhancement.
- **No `list_for_party` aggregating across BOTH active AND destroyed carriers.** v1 only ships `list_for_party_active_carriers` — the soft-deleted carrier's cargo is hidden everywhere except the audit table dump. If a future audit UI needs to show "what cargo did you have when Wagon X burned," it'd need a `list_all_for_party_including_orphans` helper.

---

## §14. Price Preview — What "Preview" Means

### 14.0 Q-TB-17 clarification

Q-TB-17 asked "Pricing for what exactly?" — a fair clarification request. The original framing ("pre-roll estimate vs post-roll discovery") was vague. §14 disambiguates: what does the player see in the mercantile_panel BEFORE they commit a transaction?

**The TL;DR:** the player sees the EXACT per-load price for the merchandise + merchant they've selected. There's no separate "estimate" mode. The substrate's lazy-roll-on-first-call (substrate §6.2) makes price preview and transaction commitment identical at the data layer — the moment the player asks for a price, the dice rolls (if uncached) and the price locks for the visit per RAW L722-723 ("market price is calculated once per type of merchandise for each visit").

### 14.1 What "preview" can mean — three scenarios

The price formula has these components:
- **base_price** (RAW; static): `MerchandiseRegistry.base_price_gp(type)`
- **dice (4d4)** (per-visit cached): from `settlement_merchandise_demand.dice_4d4_value`
- **demand_modifier** (cached, post-step-6): from `settlement_merchandise_demand.demand_modifier`
- **class_size_adjust** (pure function): from settlement's `market_class`
- **monopolist_favor** (active-character-dependent): from §8's `MonopolyRegistry`
- **judge_modifier** (caller-supplied): v1 always 0

| Scenario | Components knowable? | Preview shows |
|---|---|---|
| **A. Cached visit** — dice already rolled this visit | All components knowable | Exact price |
| **B. First visit to a cohort** — dice is sentinel (0) | Dice unknown until rolled | Roll the dice now → exact price (no separate "estimate") |
| **C. Active character switches mid-preview** — different monopolist status | Monopolist favor changes; dice unchanged | Recompute + display exact price for new active character |

In all three scenarios the player ends up looking at an exact number. No "estimated price: somewhere between X and Y" UI surface exists.

### 14.2 Lazy-roll semantics for the first-visit case

Per substrate §6.2, `MarketPriceResolver.compute_market_price(merchandise_type, settlement_id, ...)` runs `_ensure_dice_row` as its first internal step:
- If the cache row exists with `dice_4d4_value > 0`: read cached.
- If the cache row exists with `dice_4d4_value = 0` (sentinel): roll fresh dice, write cache, return rolled value.
- If no cache row at all: create one with rolled dice + default 0 demand_modifier, return.

So the FIRST call to `compute_market_price` for a (settlement, merchandise) pair on a given visit rolls the dice. Subsequent calls return the cached value. **The first call is whichever happens first — UI preview, buy click, or sell click — they all go through the same path.**

This means the live-preview panel in §3.5/§3.6 displays exact prices via the same substrate call the transaction will use. No price drift between preview and commit (modulo cross-monthly-tick drift, which would have to happen MID-VISIT and is rare).

### 14.3 Post-roll consistency within a visit

Once the dice is rolled and cached on `settlement_merchandise_demand`, **the price for that merchandise stays constant for the rest of the visit** (per RAW L722-723). The UI's live-preview number for silk @ Ashford remains 2,600 gp/load whether the player looks at it once, ten times, or commits a transaction at any of those moments.

**Cross-section guarantee:** §3.5 buy UI's preview computes via `MarketPriceResolver.compute_market_price(merchandise_type, settlement_id, monopolist_favor, 0)`. §3.2 buy handler computes via the SAME function with the SAME params. The values match exactly.

### 14.4 Drift between visits

Between visits, the monthly drift mechanic (substrate §6.6) may re-roll the dice. So:
- Visit 1, day 0: silk dice rolls to 10 → price = (10 + demand + class + monopoly + judge) × 10. Cached.
- Visit 2, day 35: drift check fires (cumulative 30% chance for 1 month elapsed × 1 month). If drift fires, new dice; new price.
- Player sees the new price in Visit 2's preview.

No discovery surprise — the player who returns to a market on a later visit sees whatever the dice has drifted to. The substrate's mechanic is the source of truth.

### 14.5 What the UI shows for each price-preview surface

**Buy section live preview (§3.5):** shows for the selected merchant's merchandise type:
```
Silk: 2,600 gp/load × 5 loads = 13,000 gp
Entry toll (first transaction): 4 gp
Loading labor: 1 gp
Grand total: 13,005 gp
```

All numbers are exact, post-roll. The "first transaction" annotation only appears if `VisitStateManager.has_paid_entry_toll(party_id, settlement_id)` returns false.

**Sell section live preview (§3.6):** shows for the selected cargo's merchandise type:
```
Silk: 2,600 gp/load × 10 loads = 26,000 gp gross
Entry toll (first transaction): 10 gp
Unloading labor: 1 gp
Customs duty (4% of 26,000): 1,040 gp
Net proceeds: 24,949 gp
```

Same exactness guarantee.

**Solicit / locate sections:** no per-merchandise price preview (those activities aren't transactions). The mercantile_panel's solicit_section (§5.8) shows the reveal schedule; locate_section (§6.3) shows pool-membership-state ("outcome estimate: locating will surface the invisible merchant").

**Persuade section (§4.10):** shows the reaction-roll breakdown with the AVERAGE 2d6 (= 7) plus modifiers vs threshold. This IS an "estimate" (because the 2d6 will roll fresh per the deterministic per-merchant seed), but it's the closest thing to a preview that activity can offer. The player sees "average roll vs threshold" to gauge their odds.

**Accept-shipping-contract section (§7.8):** offer fees are fixed at offer-roll time (§7.6); no preview-vs-commit ambiguity. The offer card shows the exact fee.

### 14.6 Edge: rolling many merchants' prices

Opening the buy section and switching between merchants in the dropdown causes price computation for each merchant's merchandise type. The substrate's lazy-roll fires on the FIRST query for each type per visit.

**Practical effect:** the player who opens the panel and switches through every visible merchant has "looked at" every merchandise type's price. Each price's dice is rolled and cached for the rest of the visit.

This is fine. RAW-faithful: a visitor walking through a market sees all the merchants' prices; each is determined "once per visit" the moment they're observed.

**No "I didn't mean to roll those" recovery:** once the dice is rolled, it's committed. The substrate's drift mechanic governs when it re-rolls (monthly, cumulative). There's no "rewind to before I looked at the price."

`[NEEDS-PRICE-ROLL-DEFERRAL-PASS]` flag if a future enhancement wants to defer the roll until actual commit (e.g., to support "browsing the market without committing" semantics where browsing doesn't lock prices). v1 follows substrate semantics.

### 14.7 Cross-section impacts

- **§3.5 / §3.6 UI sections** invoke `MarketPriceResolver.compute_market_price` for the live preview. Same as §3.2 / §3.3 handler. No new substrate calls.
- **§3.2 / §3.3 handlers** invoke `MarketPriceResolver.compute_market_price` for the actual transaction. Identical inputs; identical outputs.
- **§4 persuade section** displays the average-roll preview, not a price preview. Distinct surface.
- **§7 shipping-contracts section** displays fixed fees from the rolled-at-entry offers. No preview-vs-commit ambiguity.

### 14.8 What §14 does NOT add

- **No new "estimate" UI surface.** Preview = actual price. Single surface, single substrate call.
- **No price-roll deferral.** Looking at a price commits the dice for the visit. `[NEEDS-PRICE-ROLL-DEFERRAL-PASS]` for future.
- **No multi-merchant price-batch view** ("show me all prices at this market in a table"). The dropdown switching pattern achieves the same effect at the cost of one drop-toggle per type. A "market price overview" UI could be added as polish.
- **No price history.** The live preview shows TODAY's exact price. The substrate has no per-day price log; if a future system wants "price was 2,500 last week," it needs a new history table. `[NEEDS-PRICE-HISTORY-PASS]`.
- **No "preview vs final" delta indication.** Since they're always identical, no UI element compares them. If a future drift event happened mid-preview-mid-commit (extreme edge), the player would see one preview number and one transaction number — distinguishable in receipts but not pre-flagged in UI.

---

## §15. Cargo Encumbrance Display

### 15.0 Overview + Q-TB-18 confirmation

Q-TB-18 [RESOLVED 2026-05-13]: "Yes" — `CargoEncumbranceCalculator` (substrate Prereq.5b) should be surfaced in the Trade UI. The calculator's per-carrier capacity-check helpers give the UI everything it needs to render free-capacity numbers, over-load warnings, and speed-degradation indicators.

This section locks in:
1. Which Trade-block UI surfaces show encumbrance (§15.1).
2. The exact label format for each surface (§15.2-§15.4).
3. Refresh cadence — when the displayed numbers update (§15.5).

### 15.1 Surfaces that show encumbrance

Three Trade-block surfaces consume `CargoEncumbranceCalculator`:

| Surface | Read | Display intent |
|---|---|---|
| **§3.5 Buy section — carrier dropdown** | `draft_vehicle_capacity_check` / `ship_capacity_check` | Show free capacity per carrier so player picks one with room. |
| **§3.5 Buy section — live preview** | Same | Show "incremental load > free capacity" validation message + post-buy capacity projection. |
| **§7.8 Shipping-contract — carrier dropdown** | Same | Show free capacity filtered by contract's required carrier kind. |

**Two additional surfaces outside the Trade panel** (existing or modified):
- **Vehicle detail panel** (`scenes/ui/character_sheet/tabs/cs_vehicle_detail_panel.gd` per substrate Prereq.5a note) — existing UI may benefit from a cargo section showing both `inventory_items` and `cargo_holds` against the unified capacity. `[NEEDS-VEHICLE-DETAIL-PANEL-CARGO-PASS]` flag for the implementation pass; small change.
- **Sell section cargo dropdown (§3.6)** — shows cargo rows themselves; the carrier's free capacity is incidental (selling REDUCES load, never overflows).

§15 focuses on the buy + shipping-contract paths where the encumbrance is decision-critical.

### 15.2 Carrier dropdown — free-capacity label

Both buy section's carrier dropdown (§3.5) and shipping-contract section's carrier dropdown (§7.8) use the same label format:

```
"<carrier_name> — <free_stone> / <max_stone> stone free"
```

Examples:
- `"Merchant Wagon — 440 / 640 stone free"`  (wagon with 200 stone already loaded)
- `"Hauler #1 — 640 / 640 stone free"`        (empty wagon)
- `"Sea Wraith — 9,880 / 10,000 stone free"`  (small sailing ship with 120 stone loaded)

When over capacity (existing cargo exceeds max — possible if a future system lets cargo accumulate past load_max via debug tooling):
- `"Merchant Wagon — 0 / 640 stone free (overloaded by 50 stone)"` — uses red tint per `UiSurfaceStyles` convention.

**Source data** — each dropdown option's metadata stores `{id, kind, free_stone, load_max_stone, is_over_max, current_speed}`. The label is derived on dropdown build; the metadata is what `_collect_params` references.

### 15.3 Live preview — post-buy capacity projection

The buy section's live preview (§3.5) extends with an encumbrance row:

```
Buy 5 × silk @ 1,600 gp/load = 8,000 gp
Entry toll (first transaction): 4 gp
Loading labor: 1 gp
Grand total: 8,005 gp

Cargo: 100 stone (5 silk loads × 20 stone)
Carrier after buy: 340 / 640 stone (free: 300 stone)
```

The projection shows the carrier's POST-transaction state. If the selected carrier can't fit the cargo:

```
Cargo: 100 stone (5 silk loads × 20 stone)
Carrier after buy: 740 / 640 stone (OVERLOADED by 100 stone — speed reduced)
⚠ Reduce loads to fit, or select a larger carrier.
```

The OVERLOADED message in red tint; the Launch button disabled.

For Class-V/VI markets with small wagons, this projection is often the decision-driver — "can I fit one more silk load?"

### 15.4 Speed indicator — over_normal threshold

`draft_vehicle_capacity_check` returns `is_over_normal: bool` AND `speed: int` (which equals `speed_loaded` if `is_over_normal` else `speed_normal`). When the projection shows the carrier transitioning from normal-load to over-normal (but still under max), the preview surfaces the speed drop:

```
Cargo: 100 stone
Carrier after buy: 340 / 640 stone (over normal load 80 — speed reduced to 30 ft/turn)
```

This is informational, not blocking. The player can buy and travel slower. Useful for trade-route economics — "is the slower speed worth the per-load profit?"

`speed_normal` and `speed_loaded` come from `DraftVehicleService.VEHICLE_CAPACITY` (substrate's pre-existing table). v1 surfaces them as feet-per-turn. UI flavor wraps:

```
60 ft/turn  →  "Normal speed"
30 ft/turn  →  "Reduced speed"
0 ft/turn   →  "Unable to move (over max)" — Launch disabled
```

Ships have no `speed_loaded` distinct from `speed_normal` in v1 (substrate's maritime catalog doesn't track them). So the ship preview omits the speed indicator. `[NEEDS-SHIP-SPEED-MODEL-PASS]` flag for the future naval-movement enhancement.

### 15.5 Refresh cadence — when displayed numbers update

The mercantile_panel's live preview recomputes on every field change (per §52 picker pattern). Specifically for encumbrance:

| Trigger | What recomputes |
|---|---|
| Player selects a different carrier from the dropdown | `draft_vehicle_capacity_check(selected.id)` → free_stone + post-buy projection |
| Player changes the loads SpinBox value | post-buy projection (same carrier; new `incremental_stone`) |
| Player selects a different merchant (different merchandise_type) | `load_weight_stone` changes via `MerchandiseRegistry.load_weight_stone(merch_type)` → re-projection |
| Player switches active character | No encumbrance change (capacity is carrier-bound, not character-bound) |

Outside the panel:
- The dropdown options themselves rebuild whenever the panel opens — initial `free_stone` reflects current carrier state.
- If the player closes the panel, transacts via a different surface, and reopens, the dropdown rebuilds with fresh numbers.

No real-time push from EventBus — the substrate's `cargo_loaded` / `cargo_sold` signals could in principle update an open panel, but v1 doesn't bother. The player closes-and-reopens for clean state.

### 15.6 Domain-owner-status integration

§15 surfaces are READ-ONLY for capacity. Domain-owner status doesn't affect capacity (it only affects fees per §8.8 + entry toll per §9). So the encumbrance display doesn't change based on active character's domain-owner flag.

This is a non-issue for §15 design; just noting that capacity is a physical property of the carrier, not a character-state-dependent one.

### 15.7 Cross-section impacts

- **§3.5 buy section live preview** extends with encumbrance projection (§15.3).
- **§3.5 + §7.8 carrier dropdowns** use the label format from §15.2.
- **§3.6 sell section** doesn't need encumbrance display (selling reduces load).
- **Substrate `CargoEncumbranceCalculator`** consumed as-is; no new API needed.
- **`cs_vehicle_detail_panel.gd`** (existing) may want extension; flagged for follow-up.

### 15.8 What §15 does NOT add

- **No new substrate API.** The `CargoEncumbranceCalculator` helpers from Prereq.5b are sufficient.
- **No ship-speed model.** Substrate's maritime catalog doesn't differentiate `speed_normal` from `speed_loaded`. `[NEEDS-SHIP-SPEED-MODEL-PASS]` for future.
- **No real-time encumbrance push.** Panel reads on open + on field change. Closed-and-reopened panels get fresh data. No EventBus subscription pattern in v1.
- **No "auto-pick smallest carrier that fits" macro.** Player picks manually. Future UX could add an auto-select button.
- **No mid-transit encumbrance display.** Wilderness movement UI is outside Trade-block scope. If it needs encumbrance, it reads the same substrate helpers.
- **No per-load weight override.** Substrate's `MerchandiseRegistry.load_weight_stone(merch_type)` is the source of truth; no per-cargo-row override mechanism. If a future system wants "exceptional silk shipment weighs 30 stone/load instead of 20" handling, that's a new field on `cargo_holds`.
- **No `cs_vehicle_detail_panel` redesign.** v1 extends the existing panel minimally if at all; the cargo-section addition is `[NEEDS-VEHICLE-DETAIL-PANEL-CARGO-PASS]` and is OUT OF SCOPE for the Phase 10B.2 critical path.

---

## §16. EventBus Signals — Consolidated Reference

### 16.0 Overview

Phase 10B.2 introduces **21 new EventBus signals** across the eight signal categories below. This section is the canonical reference for implementation-pass wiring: every new signal listed here MUST be added to `engine/autoloads/event_bus.gd` with the exact name + parameter shape + docstring referencing the originating GDD section.

Signal names follow project convention §4 (past-tense verbs, snake_case). Cross-boundary payloads carry IDs (String) rather than object references.

### 16.1 New signals by category

#### 16.1.1 Transaction signals (§3.10)

```gdscript
## Emitted when buy_merchandise.gd successfully completes a purchase.
## Per gdd-phase-10b-2-trade-block.md §3.10.
signal merchandise_purchased(cargo_hold_id: String, settlement_id: String, merchandise_type: String, loads_count: int, total_cp_paid: int)

## Emitted when sell_merchandise.gd successfully completes a sale.
## net_cp_received is the gp credited AFTER labor + customs.
signal merchandise_sold(cargo_hold_id: String, settlement_id: String, merchandise_type: String, loads_count: int, net_cp_received: int)
```

#### 16.1.2 Persuade-merchants signals (§4.12)

```gdscript
## Emitted when persuade_merchants.gd succeeds — merchant's merchandise_type
## is updated. Per gdd-phase-10b-2-trade-block.md §4.6.
signal merchant_persuaded(merchant_id: String, settlement_id: String, old_merchandise_type: String, new_merchandise_type: String)

## Emitted when persuade_merchants.gd fails. outcome ∈ {"deleted", "refused_cohort"}
## per gdd-phase-10b-2-trade-block.md §4.7 (deleted = transactional merchant
## "permanently lost" per RAW; refused_cohort = promoted NPC refuses this cohort
## but persists per §0.1.1).
signal merchant_persuasion_failed(merchant_id: String, settlement_id: String, target_merchandise_type: String, outcome: String)
```

#### 16.1.3 Solicit-merchants lifecycle signals (§5.9)

```gdscript
## Emitted when solicit_merchants completes its 21-day duration. Substrate's
## solicitation_started (Prereq.4) is reused for the launch event.
signal solicit_merchants_completed(settlement_id: String, character_id: String)

## Emitted when solicit_merchants is forfeited (player departs the market
## or otherwise breaks the per-day presence requirement). unfired_reveals_rolled_back
## is the count of reveal-days that were reset to INVISIBLE_SENTINEL.
signal solicit_merchants_forfeited(settlement_id: String, character_id: String, unfired_reveals_rolled_back: int)
```

#### 16.1.4 Shipping-contract offer signals (§7.12)

```gdscript
## Emitted when ShippingContractOfferRoller rolls a fresh offer at market entry.
## One signal per offer rolled (a Class I entry may emit 4-14 of these).
signal shipping_offer_rolled(offer_id: String, party_id: String, settlement_id: String)

## Emitted when accept_shipping_contract.gd accepts an offer. The substrate's
## shipping_contract_accepted (Prereq.5c) also fires from ShippingContractRepository.
signal shipping_offer_accepted(offer_id: String, contract_id: String, cargo_hold_id: String)

## Emitted when VisitStateManager.on_party_departed_settlement clears the
## per-visit offers. cleared_count is the number of offer rows DELETEd.
signal shipping_offer_cleared(party_id: String, settlement_id: String, cleared_count: int)
```

#### 16.1.5 Monopoly registry signals (§8.6)

```gdscript
## Emitted when MonopolyRegistry.grant_monopoly inserts a new holding row.
## v1 has no emitters — the API ships for future grant systems.
signal monopoly_granted(holding_id: String, character_id: String, settlement_id: String, merchandise_type: String)

## Emitted when MonopolyRegistry.revoke_monopoly* deletes a holding row.
signal monopoly_revoked(holding_id: String, character_id: String, settlement_id: String, merchandise_type: String)
```

#### 16.1.6 Visit lifecycle signals (§9.12)

```gdscript
## Emitted when VisitStateManager.on_party_entered_settlement creates a visit row.
signal party_entered_settlement(party_id: String, settlement_id: String, calendar_day: int)

## Emitted when VisitStateManager.on_party_departed_settlement clears the visit
## row. stabling_cp + moorage_cp are the actual gp debited; days_at_settlement
## is the visit duration.
signal party_departed_settlement(party_id: String, settlement_id: String, stabling_cp: int, moorage_cp: int, days_at_settlement: int)

## Emitted when the departure debit fails (insufficient party funds for
## stabling + moorage). owed_gp is the unpaid amount. v1 doesn't track debt;
## signal is audit-trail only. Per gdd-phase-10b-2-trade-block.md §9.9.
signal visit_fees_unpaid(party_id: String, settlement_id: String, owed_gp: int)
```

#### 16.1.7 Trade-route trigger signals (§10.2)

These eight signals are CONTRACTS that Phase 10B.2 ships. The EMITTERS — the actual code paths that mutate the underlying state and fire the signal — need to be located + extended in implementation pass. Each carries a `[NEEDS-EMITTER-WIRING-<signal>]` flag.

```gdscript
## Emitted when a new settlement_entrances row is inserted.
## [NEEDS-EMITTER-WIRING-settlement_created]
signal settlement_created(settlement_id: String)

## Emitted when a settlement_entrances row is deleted (or soft-deleted).
## [NEEDS-EMITTER-WIRING-settlement_destroyed]
signal settlement_destroyed(settlement_id: String)

## Emitted when settlement_entrances.market_class is updated.
## [NEEDS-EMITTER-WIRING-settlement_market_class_changed]
signal settlement_market_class_changed(settlement_id: String, old_class: int, new_class: int)

## Emitted when a hex_overlays row with overlay_type='road' is inserted.
## [NEEDS-EMITTER-WIRING-road_overlay_added]
signal road_overlay_added(map_id: String, q: int, r: int)

## Emitted when a hex_overlays row with overlay_type='road' is deleted.
## [NEEDS-EMITTER-WIRING-road_overlay_removed]
signal road_overlay_removed(map_id: String, q: int, r: int)

## Emitted when a hex_overlays row with overlay_type='river' is inserted.
## [NEEDS-EMITTER-WIRING-river_overlay_added]
signal river_overlay_added(map_id: String, q: int, r: int)

## Emitted when a hex_overlays row with overlay_type='river' is deleted.
## [NEEDS-EMITTER-WIRING-river_overlay_removed]
signal river_overlay_removed(map_id: String, q: int, r: int)

## Emitted when hex_cells.water changes value (e.g., '' → 'ocean').
## [NEEDS-EMITTER-WIRING-hex_water_tag_changed]
signal hex_water_tag_changed(map_id: String, q: int, r: int, old_water: String, new_water: String)
```

#### 16.1.8 Monthly tick observability (§11.9)

```gdscript
## Emitted when CommerceMonthlyResolver.process_for_campaign completes. results
## carries the per-driver return values: customs_rolled, ship_gp_debited,
## merchants_generated, prices_drifted. Per gdd-phase-10b-2-trade-block.md §11.9.
signal commerce_monthly_tick_completed(campaign_id: String, results: Dictionary)
```

### 16.2 Substrate-shipped signals reused by Phase 10B.2 (reference)

Phase 10B.2 consumes these existing signals from Phase 10B-prereq (already on EventBus). No additions needed; listed for the implementation pass to know which signals the new handlers may listen for:

| Signal | Origin (substrate section) | Phase 10B.2 consumer |
|---|---|---|
| `merchant_pool_refreshed(settlement_id, new_merchant_count)` | Prereq.4 §7.11 | UI refresh; log |
| `solicitation_started(settlement_id, character_id, merchants_revealed_count)` | Prereq.4 §7.11 | §5 solicit_merchants handler emits this via `process_solicitation`; UI refresh |
| `merchant_surfaced_via_locate(merchant_id, settlement_id, merchandise_type)` | Prereq.4 §7.11 | §6 locate_merchandise; UI refresh |
| `merchant_loads_consumed(merchant_id, loads_consumed, loads_remaining)` | Prereq.4 §7.11 | §3 buy/sell; UI refresh |
| `merchant_depleted(merchant_id, settlement_id)` | Prereq.4 §7.11 | UI refresh; log |
| `merchant_expired(merchant_id, settlement_id)` | Prereq.4 §7.11 | UI refresh; log |
| `cargo_loaded(cargo_hold_id, carrier_id, merchandise_type, loads_count)` | Prereq.5b §9.11 | §3 buy handler emits; §15 encumbrance refresh trigger (if real-time push lands later) |
| `cargo_sold(cargo_hold_id, cp_received)` | Prereq.5b §9.11 | §3.3 sell + §13.2 partial_sell emit; UI refresh |
| `shipping_contract_accepted(contract_id, party_id, fee_cp)` | Prereq.5c §9.11 | §7 accept handler triggers via `ShippingContractRepository.accept_contract` |
| `shipping_contract_delivered(contract_id, fee_paid_cp, deadline_missed)` | Prereq.5c §9.11 | Substrate delivery path |
| `shipping_contract_failed(contract_id, reason)` | Prereq.5c §9.11 | Substrate cancel path |
| `ship_created/destroyed/location_changed/operating_cost_paid/unpaid` | Prereq.5a §9.11 | §11 monthly tick + future destruction events |
| `trade_route_detected(route_id, settlement_a_id, settlement_b_id)` | Prereq.2b §5.7 | §10 trigger handlers; UI |
| `trade_route_invalidated(route_id)` | Prereq.2b §5.7 | §10 trigger handlers |
| `region_demand_resolved(anchor_settlement_id)` | Prereq.2b | §10 trigger handlers; demand-driven UI refresh |
| `market_price_drifted(settlement_id, merchandise_type, old_dice, new_dice)` | Prereq.2c §6.6 | §11 monthly tick (drift driver); UI cache invalidation |

### 16.3 Emitter-side wiring responsibilities

Phase 10B.2 ships:

**New emitters that ARE the responsibility of Phase 10B.2's own handlers:**
- §3 buy/sell handlers fire `merchandise_purchased` / `merchandise_sold`.
- §4 persuade handler fires `merchant_persuaded` / `merchant_persuasion_failed`.
- §5 solicit handler fires `solicit_merchants_completed` / `solicit_merchants_forfeited`.
- §7 accept handler + ShippingContractOfferRoller fire `shipping_offer_*` signals.
- §8 MonopolyRegistry's `grant_monopoly` / `revoke_monopoly` fire `monopoly_*` signals (v1 no callers).
- §9 VisitStateManager fires `party_entered_settlement` / `party_departed_settlement` / `visit_fees_unpaid`.
- §11 CommerceMonthlyResolver fires `commerce_monthly_tick_completed`.

**Existing-code-paths that need extension to emit (§16.1.7 + scattered):**
- `CampaignRepository.insert_settlement_entrance` → emit `settlement_created`. `[NEEDS-EMITTER-WIRING-settlement_created]`.
- Settlement deletion path (TBD location) → emit `settlement_destroyed`. `[NEEDS-EMITTER-WIRING-settlement_destroyed]`.
- `UPDATE settlement_entrances SET market_class = ?` paths → emit `settlement_market_class_changed`. `[NEEDS-EMITTER-WIRING-settlement_market_class_changed]`.
- `INSERT INTO hex_overlays (overlay_type='road')` paths → emit `road_overlay_added`. Mirror for removal.
- `INSERT INTO hex_overlays (overlay_type='river')` paths → emit `river_overlay_added`. Mirror for removal.
- `UPDATE hex_cells SET water = ?` paths → emit `hex_water_tag_changed`.

The implementation pass identifies each call site (likely `engine/autoloads/campaign_repository.gd` + map/overlay editors + setting-generation code) and adds the corresponding `EventBus.<signal>.emit(...)` call right after the DB mutation.

### 16.4 What §16 does NOT add

- **No EventBus refactoring.** Existing signals stay where they are. New signals are appended at the end of `event_bus.gd` following the existing per-section comment-header pattern.
- **No signal consolidation.** Each scoped signal stays specific. There's no "umbrella" `trade_event` signal carrying a polymorphic dict — multiple specific signals are easier to subscribe to.
- **No retroactive emission.** If a state change happened before the emitter wiring landed, the signal isn't retroactively fired. The implementation-pass wiring covers go-forward behavior only.
- **No emitter testing in §16.** Each handler's tests verify the signals fire correctly per §18; §16 just lists the contracts.
- **No signal-flood debouncing.** Per §10.7, signal-flood handling is `[NEEDS-SIGNAL-FLOOD-BATCHING-PASS]`. The 21 new signals all fire eagerly per their emit-site.
- **No backward-compatibility concerns.** All signals are new; no existing subscribers are broken.

---

## §17. Migration Plan + Substrate Amendments

### 17.0 Overview

Phase 10B.2 ships **4 new migrations** (104-107) and **5 substrate-code amendments** (no schema change). All migrations are additive — no existing columns are dropped or retyped; no existing data needs migration; existing tests against the substrate schema do not regress.

### 17.1 Migration 104 — `merchant_pool` extensions (§4.8)

`db/migrations/104_merchant_pool_extensions.sql`:

```sql
BEGIN TRANSACTION;

ALTER TABLE merchant_pool ADD COLUMN promoted_npc_id TEXT REFERENCES characters(id);
ALTER TABLE merchant_pool ADD COLUMN refused_at_calendar_day INTEGER;

COMMIT;
```

- `promoted_npc_id` (nullable TEXT, FK to `characters(id)`) — per §0.1.1 LLM-promotion forward-compat anchor.
- `refused_at_calendar_day` (nullable INTEGER) — per §4.7 persuade-fail preservation path for promoted merchants.

Both nullable; both default NULL. v1 has no caller populating either column.

### 17.2 Migration 105 — `shipping_contract_offers` table (§7.2)

`db/migrations/105_shipping_contract_offers.sql`:

```sql
BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS shipping_contract_offers (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    party_id                        TEXT    NOT NULL REFERENCES parties(id),
    origin_settlement_id            TEXT    NOT NULL REFERENCES settlement_entrances(id),
    destination_settlement_id       TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    loads_count                     INTEGER NOT NULL DEFAULT 0,
    load_weight_stone               INTEGER NOT NULL DEFAULT 0,
    route_mode                      TEXT    NOT NULL DEFAULT 'road'
        CHECK(route_mode IN ('road', 'water')),
    distance_miles                  INTEGER NOT NULL DEFAULT 0,
    fee_cp                          INTEGER NOT NULL DEFAULT 0,
    deadline_calendar_day           INTEGER NOT NULL DEFAULT 0,
    rolled_at_calendar_day          INTEGER NOT NULL DEFAULT 0,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_shipping_contract_offers_party
    ON shipping_contract_offers(party_id, origin_settlement_id);

COMMIT;
```

Per-visit transient offers. INSERTed on market entry (§7.6 `ShippingContractOfferRoller.roll_for_visit`); DELETEd on departure (§9.6 `VisitStateManager.on_party_departed_settlement` → `ShippingContractOfferRoller.clear_for_party_at_settlement`).

### 17.3 Migration 106 — `monopoly_holdings` table (§8.1)

`db/migrations/106_monopoly_holdings.sql`:

```sql
BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS monopoly_holdings (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    character_id                    TEXT    NOT NULL REFERENCES characters(id),
    settlement_id                   TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    granted_at_calendar_day         INTEGER NOT NULL DEFAULT 0,
    granted_by_character_id         TEXT    REFERENCES characters(id),
    granted_by_authority            TEXT    NOT NULL DEFAULT 'domain_ruler'
        CHECK(granted_by_authority IN ('domain_ruler', 'judge', 'inherited', 'purchased')),
    expires_at_calendar_day         INTEGER,
    notes                           TEXT    NOT NULL DEFAULT '',
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(character_id, settlement_id, merchandise_type)
);

CREATE INDEX IF NOT EXISTS idx_monopoly_holdings_character
    ON monopoly_holdings(character_id);
CREATE INDEX IF NOT EXISTS idx_monopoly_holdings_settlement_merch
    ON monopoly_holdings(settlement_id, merchandise_type);

COMMIT;
```

Empty by default in v1. Plumbing for `MonopolyRegistry` (§8.2); population is later work (Phase 10B.3 decree extension or future domain-block enhancement).

### 17.4 Migration 107 — `party_visit_state` table (§9.3)

`db/migrations/107_party_visit_state.sql`:

```sql
BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS party_visit_state (
    party_id                        TEXT    NOT NULL REFERENCES parties(id),
    settlement_id                   TEXT    NOT NULL REFERENCES settlement_entrances(id),
    entry_calendar_day              INTEGER NOT NULL DEFAULT 0,
    entry_toll_paid_flag            INTEGER NOT NULL DEFAULT 0
        CHECK(entry_toll_paid_flag IN (0, 1)),
    entry_toll_paid_cp              INTEGER NOT NULL DEFAULT 0,
    active_character_at_entry       TEXT    REFERENCES characters(id),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (party_id, settlement_id)
);

COMMIT;
```

Composite PK; no separate `id` UUID needed. INSERTed on `VisitStateManager.on_party_entered_settlement` (§9.5); DELETEd on `on_party_departed_settlement` (§9.6).

### 17.5 Substrate amendments (code-only, no migration)

Five amendments to existing Phase 10B-prereq services. No schema change.

| Section | Amendment | Target file | Effort |
|---|---|---|---|
| §13.2 | Add `partial_sell(cargo_hold_id, loads_to_sell, cp_received) -> bool` | `engine/subsystems/commerce/cargo_hold_repository.gd` | ~15 lines + 2 tests |
| §13.5 | Add `list_for_party_active_carriers(party_id) -> Array` | Same | ~15 lines + 2 tests |
| §11.7 | `process_monthly_refresh_for_campaign` — filter `promoted_npc_id IS NULL` in wipe step; add UPDATE-and-re-cycle path for promoted rows | `engine/subsystems/commerce/merchant_pool_repository.gd` | ~25 lines + 3 tests |
| §11.7 | `process_expirations` — skip rows where `promoted_npc_id IS NOT NULL` | Same | ~5 lines + 1 test |
| §4.8 | `list_visible_merchants*` queries add `AND refused_at_calendar_day IS NULL` clause | Same | ~3 lines (one clause per of three list queries) + 2 tests |

`[NEEDS-SUBSTRATE-AMENDMENT-*]` flags scattered across §4, §11, §13 cover these. Implementation pass ships them alongside the new Phase 10B.2 code.

### 17.6 Migration ordering + dependency notes

**Migrations 104-107 are independent** — none depends on another's columns or tables. The implementation pass can ship them as separate atomic migrations in any order (104→107 numerical ordering recommended for build_log clarity).

**Substrate amendments depend on migration 104** (which adds `promoted_npc_id` and `refused_at_calendar_day` to merchant_pool). Order:

1. Apply migration 104.
2. Ship substrate amendments to `merchant_pool_repository.gd` (the `process_monthly_refresh_for_campaign` rewrite + `process_expirations` skip + visible-merchant filter).
3. Apply migrations 105, 106, 107.
4. Ship new Phase 10B.2 handlers + UI + autoload.
5. Update `db/schema.sql` to reflect post-107 state.

Each migration is a single `BEGIN TRANSACTION; ... COMMIT;` block. All four follow the established pattern from Phase 10B-prereq (no schema redesign, no data-move steps).

### 17.7 `db/schema.sql` update

After migration 107 lands, `db/schema.sql` updates:

- `-- Last migration applied: 107` header bump.
- `merchant_pool` table extended with `promoted_npc_id` + `refused_at_calendar_day` columns.
- Three new table definitions appended (after the existing Phase 10B-prereq tables): `shipping_contract_offers`, `monopoly_holdings`, `party_visit_state`.
- All new indexes added.

Single batch update per the project convention. The substrate-prereq pattern (Prereq.2a / Prereq.5b) is followed.

### 17.8 Cross-section migration map

| Migration | Source section | Schema delta |
|---|---|---|
| 104 | §4.8 (`promoted_npc_id` + `refused_at_calendar_day`) | 2 columns on `merchant_pool` |
| 105 | §7.2 (`shipping_contract_offers`) | 1 new table + 1 index |
| 106 | §8.1 (`monopoly_holdings`) | 1 new table + 2 indexes + UNIQUE composite |
| 107 | §9.3 (`party_visit_state`) | 1 new table + composite PK |

Total: 2 column additions, 3 new tables, 4 indexes, 1 UNIQUE composite constraint, 1 composite PK. All additive, all backward-compatible with existing Phase 10B-prereq tables.

### 17.9 What §17 does NOT add

- **No data migration / backfill.** All new columns / tables start empty (or with NULL defaults). No existing data needs transformation.
- **No DROP COLUMN / ALTER COLUMN.** Pure additive migration set. No schema rewrites.
- **No FK enforcement enablement.** Phase 10B.2 stays on the substrate's "soft-delete with FK enforcement OFF" pattern. `[NEEDS-FK-ENFORCEMENT-PASS]` for future hardening.
- **No data-validation tests for migration application.** Migration tests verify columns exist after migration runs (`PRAGMA table_info` + expected-column-list assertion). Per §18.
- **No rollback path.** Project convention is forward-only migrations. A bad migration is fixed by a follow-up migration that corrects, not by reverting.

---

## §18. Test Plan

### 18.0 Overview + budget

Phase 10B.2 ships an estimated **~14 new test files + ~3 extensions of existing substrate suites = ~120-150 individual `check()` assertions** total. Coverage spans:

- **Per-handler unit tests** for each of the 5 mercantile activities + shared helper
- **Per-service unit tests** for the 5 new services (MonopolyRegistry, ShippingContractOfferRoller, VisitStateManager, TradeRouteTriggerHandlers, CommerceMonthlyResolver)
- **Substrate amendment extensions** for the 5 substrate code changes from §17.5
- **Integration tests** for end-to-end Trade-block flows (handler-driven; replaces the direct-substrate-call Prereq.8 integration test)
- **UI picker tests** for the mercantile_panel sections

Per coding conventions §9, every new subsystem gets focused unit tests; cross-subsystem boundaries get integration tests; the entire game must work with the mock LLM provider (irrelevant for Phase 10B.2 since trade is purely mechanical).

### 18.1 Unit test files

| Test file | Coverage | Estimated assertions |
|---|---|---|
| `tests/test_mercantile_category_parse.gd` | `data/activities/mercantile_category.json` parses; 5 activity IDs present; param_schemas match §1.3 (§1) | ~6 |
| `tests/test_buy_merchandise_handler.gd` | Happy path; insufficient funds; carrier overflow; merchant insufficient loads; toll first-fire; monopolist 2x cap; emits signals (§3.2) | ~10 |
| `tests/test_sell_merchandise_handler.gd` | Happy path; partial sell; full sell deletes; negative-net edge case; domain-owner customs exempt; merchant type mismatch (§3.3) | ~10 |
| `tests/test_buy_sell_common.gd` | `resolve_party_for_character`; `charge_entry_toll_if_first_visit` (first + subsequent); `transaction_rng` determinism; `carrier_has_capacity`; receipt builders (§3.4) | ~6 |
| `tests/test_persuade_merchants_handler.gd` | Success updates merchandise_type; failure deletes transactional; failure marks promoted refused; reaction roll formula (CHA + proficiencies + signed demand + monopolist bonus); threshold (9 common, 12 precious); `_persuade_rng` determinism (§4.9) | ~8 |
| `tests/test_solicit_merchants_handler.gd` | on_started invokes substrate; rejection on already-revealed; forfeit rollback resets unfired reveals; promoted/manual rows untouched by rollback; completion emits signal (§5.7) | ~6 |
| `tests/test_locate_merchandise_handler.gd` | Visible match → no-op success; invisible match → surface one; no match → failure; toll first-fire (§6.2) | ~5 |
| `tests/test_accept_shipping_contract_handler.gd` | Happy path inserts contract + cargo_holds; offer→contract→cargo linkage; carrier kind mismatch rejection; capacity rejection; offer deleted on accept (§7.7) | ~7 |
| `tests/test_shipping_contract_offer_roller.gd` | `roll_for_visit` deterministic seed; idempotency (re-entry doesn't re-roll); per-class quantity dice; destination + route mode resolution; fee formula; deadline computation; `clear_for_party_at_settlement` (§7.6) | ~10 |
| `tests/test_monopoly_registry.gd` | `has_monopoly` finds + expiry filter; `favor_for_buy` / `favor_for_sell` signs; `grant_monopoly` insert; UNIQUE violation returns ""; `revoke_monopoly` + by_triple; signal emission (§8.2) | ~8 |
| `tests/test_visit_state_manager.gd` | `on_party_entered_settlement` INSERT-OR-IGNORE idempotent; toll first-fire via `charge_entry_toll_if_first_visit` records via `mark_entry_toll_paid`; `on_party_departed_settlement` computes stabling + moorage + clears offers + DELETEs row; insufficient funds → `visit_fees_unpaid` signal without blocking departure; domain-owner exemption (§9.4) | ~10 |
| `tests/test_trade_route_trigger_handlers.gd` | Autoload subscribes at `_ready`; settlement_created → detect_routes + resolve_region; settlement_destroyed → DELETE routes + resolve_region for each former counterpart; market_class_changed → re-detect; overlay-change proximity filter (28 / 80 hexes); idempotent under signal flood (§10.3) | ~8 |
| `tests/test_commerce_monthly_resolver.gd` | `process_for_campaign` dispatches all 4 drivers in canonical order; `_maybe_roll_annual_customs` year-boundary detection (current_year > last_customs_roll_year); deterministic seeded RNG; emits `commerce_monthly_tick_completed` with results dict (§11.4) | ~6 |

**Subtotal:** ~100 assertions across 13 new unit-test files.

### 18.2 Substrate amendment test extensions

Three existing substrate test suites get assertions added (per §17.5):

| Existing suite | New assertions |
|---|---|
| `tests/test_cargo_hold_repository.gd` | `partial_sell` partial decrement; `partial_sell` full path delegates to delete_sold; `list_for_party_active_carriers` filters destroyed carriers; same helper aggregates across draft_vehicles + ships | ~6 |
| `tests/test_merchant_pool_repository.gd` | Monthly refresh preserves `promoted_npc_id IS NOT NULL` rows + UPDATEs them in place; `process_expirations` skips promoted rows; `list_visible_merchants*` queries filter `refused_at_calendar_day IS NULL`; refused-cohort flag cleared at monthly refresh | ~8 |
| `tests/test_event_bus.gd` (if exists; or per-handler suite) | All 21 new signals exist on EventBus with correct parameter names | ~2 |

**Subtotal:** ~16 assertions across 2-3 existing suites.

### 18.3 Integration tests

| Test file | Coverage | Estimated assertions |
|---|---|---|
| `tests/test_trade_block_integration.gd` | End-to-end mercantile workflow THROUGH the handlers (not direct substrate calls). Same three Ashford/Thornwall scenarios as Prereq.8 (`+8,940` baseline / `+5,820` 16% customs / `+9,992` PC-owned) reproduced via `buy_merchandise.on_complete` → travel → `sell_merchandise.on_complete`. Includes per-visit toll first-fire across multiple transactions per visit; departure stabling/moorage charge; cargo lifecycle (insert via buy → delete via sell). | ~12 |
| `tests/test_shipping_contract_workflow.gd` | Offer roll → accept → travel → deliver. Substrate `ShippingContractRepository.deliver` already tested at Prereq.5c; this integration verifies the FULL flow including `ShippingContractOfferRoller` + `accept_shipping_contract.on_complete` + linked cargo_holds row + visit-departure cleanup of unaccepted offers. | ~8 |
| `tests/test_persuade_solicit_locate_workflow.gd` | Solicit reveals over 21 days (with calendar-day advancing fixture); locate surfaces a target type from invisible pool; persuade converts a merchant from type A to type B with success/failure both exercised. Includes the §0.1.1 LLM-promotion preservation case (test fixture seeds a promoted merchant; verifies it survives persuade-fail + monthly refresh). | ~10 |

**Subtotal:** ~30 assertions across 3 integration test files.

### 18.4 UI picker tests

Per §52 conventions, modal pickers get tests for: validation logic; param collection; section dispatch; signal emission. Phase 10B.2's `mercantile_panel` ships with one test file:

| Test file | Coverage | Estimated assertions |
|---|---|---|
| `tests/test_mercantile_panel.gd` | Section dispatch: opening the panel with each of the 5 activity IDs renders the correct section; field validation per section (buy: select merchant + carrier + valid loads; sell: select cargo + matching-type merchant; persuade: target type ≠ current; solicit: invisible_merchants_remaining; locate: merchandise selected; accept: offer + matching carrier kind); `launch_requested` signal payload matches catalog param_schema for each activity. | ~10 |

**Subtotal:** ~10 assertions in 1 UI test file.

### 18.5 Total test budget summary

| Bucket | Files | Assertions |
|---|---|---|
| §18.1 New handler / service unit tests | 13 | ~100 |
| §18.2 Substrate amendment extensions | 2-3 (extend existing) | ~16 |
| §18.3 Integration tests | 3 | ~30 |
| §18.4 UI picker tests | 1 | ~10 |
| **Total** | **~14 new + ~3 extensions** | **~156** |

### 18.6 Test ordering + dependencies

Per §17.6, substrate amendments depend on migration 104. Test ordering mirrors:

1. Migration tests (one per migration; verify columns/tables exist via `PRAGMA table_info`).
2. Substrate amendment extensions to existing suites.
3. New service unit tests (MonopolyRegistry, ShippingContractOfferRoller, VisitStateManager).
4. New handler unit tests (all 5 mercantile handlers).
5. UI picker tests.
6. Integration tests (consumes all the above).

The test runner already handles ordering via `tests/test_runner.tscn` registration. Per the substrate's test registration pattern, each test suite registers as an ExtResource.

### 18.7 Test fixture patterns

Three fixture patterns appear repeatedly across Phase 10B.2 tests:

1. **Bare-minimum trade fixture** — campaign + map + settlement (with market_class) + party + PC + active character. Used by handler tests that focus on a single activity's logic.
2. **Two-settlement trade-route fixture** — bare-minimum × 2 + connecting road overlay + trade_routes row + demand modifiers seeded for one merchandise type. Used by §18.3's Ashford/Thornwall replay test.
3. **Stocked-cohort fixture** — full visible merchant pool + cached dice + initial customs rate. Used by persuade/locate/solicit handler tests.

Each pattern factors into a helper in `tests/helpers/trade_fixtures.gd` (new file) so the per-test boilerplate stays minimal. Per coding conventions §9 testing patterns.

### 18.8 What §18 does NOT add

- **No load / performance tests.** Phase 10B.2 doesn't introduce performance-critical paths; the substrate's monthly tick + trade-route detection are O(N²) per their respective sections but at v1 campaign scales (tens of settlements) the actual cost is microseconds. Profiling-driven optimization is `[NEEDS-PERFORMANCE-PROFILING-PASS]`.
- **No fuzz testing.** Per coding conventions, project doesn't currently run fuzz tests.
- **No save/load round-trip tests.** SQLite-backed state automatically survives save/load (per substrate's pattern). Per-table integrity is verified by the migration tests; cross-table consistency is implicit.
- **No multi-party tests.** v1 is single-party per project assumption. The substrate's table designs support multi-party (party_id is a key on every Phase 10B.2 table) but tests don't exercise the multi-party paths. `[NEEDS-MULTI-PARTY-TESTS]` flag for the future.
- **No LLM-promotion-active-path tests.** §0.1.1's forward-compat ships the columns + preservation logic. v1 has no caller that promotes a merchant. Tests verify the PRESERVATION (a row with `promoted_npc_id` set is handled correctly by monthly refresh + persuade failure + expiration), but the PROMOTION action itself is untested because it doesn't exist in v1. `[NEEDS-LLM-PROMOTION-TESTS]` flag covers when the promotion API ships.
- **No mocking of substrate APIs.** Tests use the real substrate services against the real DB. Heavier than pure-unit testing but matches the project's test-against-the-real-thing convention.

---

## §19. Wave Plan — Implementation Sequencing

### 19.0 Overview + total scope

Phase 10B.2 ships across **6 build waves**, each a single coherent build session producing tangible end-to-end progress. The waves are organized by FEATURE (not by horizontal layer) so each wave delivers a usable slice rather than a half-built foundation.

**Total scope estimate:**
- 4 migrations (104-107)
- 5 substrate code amendments (no schema change)
- 21 new EventBus signals
- 1 new autoload (`TradeRouteTriggerHandlers`)
- 5 new services + 1 shared helper (`MonopolyRegistry`, `VisitStateManager`, `ShippingContractOfferRoller`, `CommerceMonthlyResolver`, `TradeRouteTriggerHandlers`, `BuySellCommon`)
- 6 new handlers (5 mercantile + 1 registration)
- 1 new UI panel (`mercantile_panel`) + extensions to existing settlement UI
- ~156 test assertions across ~14 new test files
- ~9 existing-code-path emitter wirings

**Wave cadence pattern** matches Phase 10B-prereq (one build session per wave; each wave produces a passing test suite + a build_log entry).

### 19.1 Wave 10B.2.1 — Foundation

**Theme:** schema + substrate amendments + foundational services that have no UI consumers yet.

**Deliverables:**
- Migrations 104, 105, 106, 107 (all 4 — additive, independent per §17.6).
- Substrate amendments per §17.5: `CargoHoldRepository.partial_sell` + `list_for_party_active_carriers`; `MerchantPoolRepository.process_monthly_refresh_for_campaign` LLM-promotion preservation; `process_expirations` skip; `list_visible_merchants*` refused filter.
- All 21 EventBus signals appended to `event_bus.gd` (consolidated per §16).
- New services without UI dependencies:
  - `BuySellCommon` shared helper (§3.4)
  - `MonopolyRegistry` (§8.2) — empty population
  - `VisitStateManager` (§9.4) — entry/departure WITHOUT the shipping-offer-roll call (deferred to Wave 4)
- Test fixture helpers: `tests/helpers/trade_fixtures.gd` with the three patterns from §18.7.
- Tests: substrate amendment extensions + new service unit tests.

**Acceptance:**
- Schema reflects post-107 state (`PRAGMA table_info` confirms columns / tables).
- All substrate amendment tests pass (`partial_sell`, `list_for_party_active_carriers`, refused filter).
- `MonopolyRegistry.has_monopoly` returns false for empty table; signal-emission helpers exist but no v1 caller.
- `VisitStateManager.on_party_entered_settlement` + `on_party_departed_settlement` work without crashing; stabling + moorage debit fires per §9.6 (shipping-offer-roll call STUBBED — left as a TODO comment with `[WAVE-10B.2.4-WIRES-OFFER-ROLL]` flag).
- No regressions in pre-existing test suite.

**Estimated assertions:** ~50.
**Test suite count delta:** +3 new test files + 2 extensions.

### 19.2 Wave 10B.2.2 — Buy / Sell Merchandise + Trade UI Scaffold

**Theme:** the central activity. Player can enter a market, buy merchandise, sell merchandise.

**Deliverables:**
- `data/activities/mercantile_category.json` with all 5 activity rows per §1.3 (catalog ships full; non-Wave-2 handlers will be wired in later waves).
- `buy_merchandise.gd` handler per §3.2.
- `sell_merchandise.gd` handler per §3.3.
- `mercantile_handlers_registration.gd` per §1.4 — registers ALL 5 handlers but the 3 not-yet-implemented ones (`persuade_merchants` / `solicit_merchants` / `locate_merchandise`) point to stub handler files that return `"summary": "not yet implemented"` on `on_complete`. Same for `accept_shipping_contract`. Wave 2 ships the registration glue + 2 real handlers + 3 stubs.
- `mercantile_panel.gd` + `.tscn` — single panel with the 5 conditional sections. Wave 2 implements only the buy + sell sections; the other 3 sections render placeholder "Coming in Wave 10B.2.X" labels.
- `activity_panel.gd` extensions per §2.5 (add 5 new activities to `ACTIVITIES["market"]` and `ACTIVITIES["town_square"]`; add `mercantile_requested(activity_id, poi)` signal).
- `SettlementExploreState` routing per §2.7 — `_on_mercantile_requested` opens the mercantile_panel with the requested section active.
- `VisitStateManager` entry/departure hook wiring — `SettlementExploreState` invokes the two trigger methods at entry / departure per §9.10. `[NEEDS-SETTLEMENT-FLOW-WIRING]` from §9.10 closes here.
- Tests: `test_buy_merchandise_handler.gd`, `test_sell_merchandise_handler.gd`, `test_buy_sell_common.gd`, `test_mercantile_panel.gd` (buy + sell sections only), `test_mercantile_category_parse.gd`.

**Acceptance:**
- Player can click `market` POI → click `buy_sell_merchandise` → mercantile_panel opens with buy section → select merchant + carrier + loads → click Launch → handler fires → wallet debited + cargo inserted.
- Player can launch `sell_merchandise` → select cargo + merchant + loads → handler fires → wallet credited + cargo deleted (or decremented for partial).
- Entry toll fires first transaction per visit; subsequent transactions in same visit don't re-charge.
- Departure debit fires at settlement exit (stabling + moorage).
- The §12 Ashford/Thornwall workflow runs end-to-end through the handlers (manual smoke test; full integration test lands Wave 6).

**Estimated assertions:** ~50.
**Test suite count delta:** +5 new test files.

### 19.3 Wave 10B.2.3 — Persuade / Solicit / Locate

**Theme:** the three merchant-interaction activities besides buy/sell.

**Deliverables:**
- `persuade_merchants.gd` handler per §4.9 — replaces the Wave 2 stub.
- `solicit_merchants.gd` handler per §5.7 — replaces Wave 2 stub.
- `locate_merchandise.gd` handler per §6.2 — replaces Wave 2 stub.
- mercantile_panel sections for the three replace their Wave 2 placeholders: `_build_persuade_section`, `_build_solicit_section`, `_build_locate_section`.
- Tests: `test_persuade_merchants_handler.gd`, `test_solicit_merchants_handler.gd`, `test_locate_merchandise_handler.gd`.

**Acceptance:**
- Persuade: select merchant + target type + direction → roll fires → success updates merchandise_type / failure DELETEs transactional merchant / failure marks promoted refused.
- Solicit: launch 21-day ongoing → reveal schedule set on launch → reveals fire on calendar advancing → forfeit (departing market) rolls back unfired reveals.
- Locate: select merchandise type → outcomes (no-op success / surface invisible / no-match failure) per §6.1.
- The 3 picker sections render + validate + emit `launch_requested`.

**Estimated assertions:** ~30.
**Test suite count delta:** +3 new test files.

### 19.4 Wave 10B.2.4 — Shipping Contracts

**Theme:** the freight-haulage activity. Adds offer-rolling + accept flow.

**Deliverables:**
- `ShippingContractOfferRoller` service per §7.6 (`engine/subsystems/commerce/shipping_contract_offer_roller.gd`).
- `accept_shipping_contract.gd` handler per §7.7 — replaces Wave 2 stub.
- mercantile_panel shipping section replaces its placeholder: `_build_shipping_contracts_section`.
- `VisitStateManager` extension — `on_party_entered_settlement` adds `ShippingContractOfferRoller.roll_for_visit(...)` call (Wave 1's TODO comment closes); `on_party_departed_settlement` adds `clear_for_party_at_settlement(...)` call.
- Tests: `test_shipping_contract_offer_roller.gd`, `test_accept_shipping_contract_handler.gd`.
- Integration: `test_shipping_contract_workflow.gd` exercising offer roll → accept → deliver (via substrate `ShippingContractRepository.deliver`).

**Acceptance:**
- Market entry rolls fresh offers per class table; offers visible in shipping section.
- Player accepts an offer → shipping_contracts row inserted + cargo_holds row linked + offer DELETEd.
- Departure clears all unaccepted offers.
- Deadline-missed path covered by existing substrate test (Prereq.5c) + new integration test.

**Estimated assertions:** ~25.
**Test suite count delta:** +3 new test files.

### 19.5 Wave 10B.2.5 — Trade-Route Triggers + Monthly Tick

**Theme:** background signal-driven maintenance + monthly tick wiring.

**Deliverables:**
- `TradeRouteTriggerHandlers` autoload per §10.3 (`engine/subsystems/commerce/trade_route_trigger_handlers.gd`).
- New autoload registration in `project.godot`.
- 8 emitter wirings (per §16.3): `settlement_created`, `settlement_destroyed`, `settlement_market_class_changed`, `road_overlay_added/removed`, `river_overlay_added/removed`, `hex_water_tag_changed`. Implementation pass locates each state-mutation call site and adds the corresponding `EventBus.<signal>.emit(...)` call. `[NEEDS-EMITTER-WIRING-<signal>]` flags close here.
- `CommerceMonthlyResolver` static dispatcher per §11.4 (`engine/subsystems/commerce/commerce_monthly_resolver.gd`).
- `DomainMonthlyResolver` extension — invoke `CommerceMonthlyResolver.process_for_campaign(...)` per §11.4. `[NEEDS-MONTHLY-TICK-WIRING]` closes.
- `SessionRunner.load_session` extension — invoke `TradeRouteTriggerHandlers.full_sweep_for_campaign(campaign_id)` per §10.6. `[NEEDS-CAMPAIGN-LOAD-WIRING]` closes.
- Tests: `test_trade_route_trigger_handlers.gd`, `test_commerce_monthly_resolver.gd`.

**Acceptance:**
- Creating a settlement fires `settlement_created` → autoload detects routes for it → region resolver runs.
- Adding a road overlay fires `road_overlay_added` → autoload re-detects nearby settlements → routes updated.
- Monthly tick fires the 4 commerce drivers in canonical order (customs → ships → merchants → drift).
- Year boundary triggers customs roll exactly once (verified via `last_customs_roll_year` advancement).
- Campaign load with empty `trade_routes` table triggers the full sweep.

**Estimated assertions:** ~20.
**Test suite count delta:** +2 new test files.

### 19.6 Wave 10B.2.6 — Integration + Close-out

**Theme:** end-to-end verification + Phase 10B.2 sign-off.

**Deliverables:**
- `test_trade_block_integration.gd` reproducing the Ashford/Thornwall +8,940 / +5,820 / +9,992 scenarios THROUGH the new handlers (not direct substrate calls). Matches Prereq.8's regression anchor with handler-routed equivalence.
- `test_persuade_solicit_locate_workflow.gd` — multi-activity workflow including LLM-promotion preservation case.
- Any deferred bug fixes from Waves 1-5.
- build_log close-out entry — "Phase 10B.2 complete; Phase 10B.3 (Syndicate) and any UI polish are unblocked."
- `docs/coding_conventions.md` update — new section "§N. Phase 10B.2 — Trade Block conventions" appended per CLAUDE.md's update-on-new-pattern rule. Captures: the conditional-section dispatcher in `mercantile_panel`, the `BuySellCommon` shared-helper pattern, the active-character + party-wallet pattern (already established by shop_panel; this just cross-references), the §0.1.1 LLM-promotion forward-compat pattern, the visit-state lifecycle, the monthly-tick dispatcher pattern.
- Updates to `docs/document_map.md` (if exists) — index this GDD.

**Acceptance:**
- All 6 wave's tests pass (cumulative).
- The §12 worked-example assertions match through the handler-routed integration test.
- No regressions in pre-existing test suite.
- build_log entry archives the full Phase 10B.2 scope (mirroring substrate Phase 10B-prereq's closing entry).

**Estimated assertions:** ~15.
**Test suite count delta:** +2 new test files (the 2 integration tests).

### 19.7 Wave dependency graph

```
Wave 1 (Foundation)
  ├─→ Wave 2 (Buy/Sell + UI scaffold)
  │     ├─→ Wave 3 (Persuade/Solicit/Locate)
  │     └─→ Wave 4 (Shipping Contracts)
  │           └─→ Wave 5 (Triggers + Monthly Tick)
  └─→ Wave 5 (also via VisitStateManager)
        └─→ Wave 6 (Integration + Close-out)
```

Waves 2, 3, 4 have soft dependencies on each other (they all consume Wave 1's foundation and can technically be interleaved); the recommended order matches above for build-log coherence.

### 19.8 Cumulative test budget per wave

| Wave | New files | Assertions | Running total |
|---|---|---|---|
| 1 — Foundation | 3 + 2 extensions | ~50 | ~50 |
| 2 — Buy/Sell | 5 | ~50 | ~100 |
| 3 — Persuade/Solicit/Locate | 3 | ~30 | ~130 |
| 4 — Shipping Contracts | 3 | ~25 | ~155 |
| 5 — Triggers + Monthly | 2 | ~20 | ~175 |
| 6 — Integration | 2 | ~15 | **~190** |

Phase 10B.2 ends with ~190 new assertions across ~14 new test files + ~3 substrate extensions.

### 19.9 Acceptance criteria — Phase 10B.2 complete

When Wave 6 closes, the following must hold:

1. **All 4 migrations applied + schema.sql updated** to reflect post-107 state.
2. **All 21 new EventBus signals exist** + 8 emitter wirings landed.
3. **All 5 mercantile activities work end-to-end:** player launches from market POI → handler fires → DB mutates → signal emits → UI refreshes.
4. **Trade UI is fully functional** — `mercantile_panel` renders all 5 sections with validation + live preview + signal emission.
5. **Monthly tick fires the 4 commerce drivers** with deterministic seeded RNG.
6. **Year-tick customs roll** fires exactly once per year per campaign.
7. **Trade-route triggers re-detect + resolve** on the 8 trigger scenarios.
8. **VisitStateManager** correctly tracks entry-toll first-fire + stabling/moorage at departure + shipping-offer roll/clear lifecycle.
9. **LLM-promotion forward-compat** preserved — `promoted_npc_id IS NOT NULL` rows survive monthly refresh, expiration, and persuade-fail per §0.1.1.
10. **§12 Ashford/Thornwall regression** — `+8,940` / `+5,820` / `+9,992` scenarios reproducible through the new handlers.
11. **All `[NEEDS-...-PASS]` flags from substrate Phase 10B-prereq that this GDD inherits** are EITHER closed (per the wave plan) OR explicitly carried forward in the close-out build_log entry.
12. **No regressions** in the pre-Phase-10B.2 test suite (test count grows; pass count grows; fail count unchanged or shrinks).

### 19.10 Phase 10B.3 (Syndicate) unblocking

After Wave 6, Phase 10B.3 (Syndicate block) can begin. Phase 10B.3 consumes:
- `MarketPriceResolver` (for hijink-yield notional values)
- `MonopolyRegistry` (for hijink targets)
- `CharacterLegalStatusRepository` (substrate Prereq.6)
- `HenchmanLoyaltyResolver` with `extra_modifiers` (substrate Prereq.7)
- `CargoHoldRepository.insert_hijink_yield` (substrate Prereq.5b)
- `VisitStateManager` (for hijink staging at settlements — entry-toll logic may extend here)
- The new `EventBus` signals (e.g., `monopoly_granted` for the `issue_decree`-extension grant flow)

Phase 10B.3 may also add a `grant_monopoly` UX (decree extension) and the Crime & Punishment resolver. Both are independent of Phase 10B.2's UI surface.

### 19.11 What §19 does NOT add

- **No fixed calendar dates per wave.** Each wave is "one build session" — the actual calendar duration depends on session pacing.
- **No model assignment per wave** (Opus vs Sonnet). Per CLAUDE.md model usage guidelines, default to Sonnet; escalate to Opus for design / RAW interpretation as needed. The GDD itself was Opus-authored; implementation can be Sonnet.
- **No risk-of-failure analysis.** Each wave's deliverables are atomic — a wave either passes its tests or rolls back. The wave plan doesn't enumerate "what if Wave 3's persuade handler hits a substrate edge case" — that's an implementation-pass discovery + adapt loop.
- **No cross-wave refactoring budget.** If Wave 3 reveals a Wave 2 design issue, the fix happens in Wave 3 with an explicit build_log note. No "Wave 7 to clean up earlier waves" pre-scheduled.
- **No staging branch / merge process** — the project's git workflow is the same forward-only convention used for Phase 10B-prereq.
- **No external dependencies.** All work is in-tree; no waiting on third-party libraries, asset commissions, or external review.

---

## §20. Cumulative Non-Goals + Carry-Forward Flags

### 20.0 Overview

This section consolidates **every `[NEEDS-...-PASS]` / `[NEEDS-...-CALIBRATION]` flag** planted across §0-§19, plus a cumulative list of Phase 10B.2's explicit non-goals. The intent: a future contributor opening this GDD knows exactly which flags Phase 10B.2 closes vs carries forward, and which downstream phases own each carry.

### 20.1 Flags closed by the wave plan

The wave plan from §19 closes these flags at well-defined waves:

| Flag | Source | Closed by |
|---|---|---|
| `[NEEDS-SETTLEMENT-FLOW-WIRING]` | §9.10 | Wave 2 (VisitStateManager entry/departure hooks in SettlementExploreState) |
| `[NEEDS-SUBSTRATE-AMENDMENT-PARTIAL-SELL]` | §13.2 | Wave 1 |
| `[NEEDS-SUBSTRATE-AMENDMENT-LIST-ACTIVE]` | §13.5 | Wave 1 |
| `[NEEDS-SUBSTRATE-AMENDMENT-LLM-PROMOTION-PASS]` | §11.7 | Wave 1 |
| `[NEEDS-EMITTER-WIRING-settlement_created]` | §16.3 | Wave 5 |
| `[NEEDS-EMITTER-WIRING-settlement_destroyed]` | §16.3 | Wave 5 |
| `[NEEDS-EMITTER-WIRING-settlement_market_class_changed]` | §16.3 | Wave 5 |
| `[NEEDS-EMITTER-WIRING-road_overlay_added]` + `_removed` | §16.3 | Wave 5 |
| `[NEEDS-EMITTER-WIRING-river_overlay_added]` + `_removed` | §16.3 | Wave 5 |
| `[NEEDS-EMITTER-WIRING-hex_water_tag_changed]` | §16.3 | Wave 5 |
| `[NEEDS-CAMPAIGN-LOAD-WIRING]` | §10.6 | Wave 5 |
| `[NEEDS-MONTHLY-TICK-WIRING]` | §19.5 | Wave 5 |

**12 flags closed.** All wired during normal Phase 10B.2 implementation.

### 20.2 Carry-forward flags by theme

#### 20.2.1 Mercantile gameplay refinement

| Flag | Source | Purpose |
|---|---|---|
| `[NEEDS-TRANSACTION-LOG-PASS]` | §3.11 | Persist buy/sell receipts to a transaction_log table for audit/replay |
| `[NEEDS-PERSUASION-LOG-PASS]` | §4.13 | Persist persuade attempts (success/fail + roll breakdown) for audit |
| `[NEEDS-REACTION-PROFICIENCY-SUITE-PASS]` | §4.5, §4.13 | Unify the Bribery/Diplomacy/Intimidation/Mystic Aura/Seduction reaction-modifier suite into a single helper consumed by henchman loyalty + persuade + passenger trust + future bribery |
| `[NEEDS-MONOPOLY-CAP-CALIBRATION]` | §4.11 | Tune the monopolist 2× loads cap interpretation (cap-doubling vs free-multiplier) if playtest reveals imbalance |
| `[NEEDS-MERCHANT-SOURCING-PASS]` | §6.6 (carried from substrate §7.5.2) | Spawn a missing-type merchant via connected trade routes when locate fails |
| `[NEEDS-LOCATE-FALL-THROUGH-CTA-PASS]` | §6.4 | One-click "Persuade a merchant to deal in <type>" CTA on locate-fail receipt |

#### 20.2.2 Shipping contracts RAW-complete

| Flag | Source | RAW-completion target |
|---|---|---|
| `[NEEDS-CONTRACT-STAGGERED-AVAILABILITY-PASS]` | §7.0, §7.13 | RAW L828-832 1-3 week staggered reveal for contracts (mirrors solicit_merchants) |
| `[NEEDS-CONTRACT-TRUST-ROLL-PASS]` | §7.0, §7.13 | RAW L815 9+ reaction-roll-per-contract gating |
| `[NEEDS-CONTRACT-HALF-ADVANCE-PASS]` | §7.4, §7.13 | RAW L824 half-on-acceptance + half-on-delivery split |
| `[NEEDS-CONTRACT-DESTINATION-RAW-COMPLETE-PASS]` | §7.3, §7.13 | RAW L788-791 1d20 destination logic (distant 19+ / closest within ±1 class along route) |
| `[NEEDS-CONTRACT-DEADLINE-CALIBRATION]` | §7.5 | Tune the `(travel_days × 2 + 7)` deadline formula post-playtest |
| `[NEEDS-DELIVERY-UI-PASS]` | §7.9 | Active-contracts UI panel at the destination market for deliver/cancel actions |
| `[NEEDS-LATE-DELIVERY-PENALTY-PASS]` | §7.13 (carried from substrate §9.7) | Partial-fee + reputation-penalty on missed deadlines |
| `[NEEDS-MULTI-CARRIER-CONTRACT-PASS]` | §13.3 | Distribute a single large contract across multiple carriers |
| `[NEEDS-CONTRACT-CARGO-LOSS-EXPLICIT-PASS]` | §13.8 | Distinct contract-failure path for "cargo destroyed in transit" vs generic deadline-missed |

#### 20.2.3 Per-visit + lifecycle hardening

| Flag | Source | Concern |
|---|---|---|
| `[NEEDS-MID-VISIT-ACTIVE-CHARACTER-RECONCILE-PASS]` | §9.13 | Update entry-toll attribution + monopoly-favor key when active character changes mid-visit |
| `[NEEDS-VEHICLE-SETTLEMENT-LOCATION-PASS]` | §9.7, §9.13 | Per-vehicle settlement_id tracking so wagons left at one settlement don't follow the party |
| `[NEEDS-VISIT-FEE-DEBT-PASS]` | §9.9, §9.13 | Persist unpaid stabling/moorage as a debt; apply consequences (re-entry block, reputation, interest) |
| `[NEEDS-VISIT-HISTORY-PASS]` | §9.13 | Archive completed visits to a history table for audit/log |
| `[NEEDS-VISIT-ORPHAN-CLEANUP-PASS]` | §9.13 | Periodic sweep of orphan party_visit_state rows (mid-visit-save edge case) |
| `[NEEDS-PC-MOUNT-STABLING-PASS]` | §9.13 | PC personal mounts (warhorses not pulling wagons) need stabling too |
| `[NEEDS-VISIT-DURATION-CALIBRATION]` | §9.8 | Tune the `max(1, current - entry)` minimum-1-day rule post-playtest |

#### 20.2.4 Optimization / scaling

| Flag | Source | Concern |
|---|---|---|
| `[NEEDS-PROXIMITY-FILTER-OPTIMIZATION]` | §10.4 | Trade-route trigger handlers use straight-line hex distance; path-aware filter cuts false positives |
| `[NEEDS-SIGNAL-FLOOD-BATCHING-PASS]` | §10.7 | Defer trade-route recompute during setting-generation / world-state-mutation events; flush once at end |
| `[NEEDS-PERFORMANCE-PROFILING-PASS]` | §18.8 | Profile-driven optimization of monthly tick + trade-route detection at larger campaign scales |

#### 20.2.5 Multi-party + LLM future

| Flag | Source | Concern |
|---|---|---|
| `[NEEDS-MULTI-PARTY-SOLICIT-PASS]` | §5.4, §5.11 | Solicit attribution + rollback when multiple parties solicit at overlapping settlements |
| `[NEEDS-MULTI-PARTY-TESTS]` | §18.8 | Test coverage for multi-party paths (Phase 10B.2 tables are party_id-scoped but tests don't exercise) |
| `[NEEDS-LLM-PROMOTION-LATER]` | §0.1.1 | Build the actual LLM-driven promotion procedure (this GDD ships forward-compat plumbing only) |
| `[NEEDS-LLM-PROMOTION-TESTS]` | §18.8 | Test the LLM promotion API once it ships |

#### 20.2.6 Year-tick / archival

| Flag | Source | Concern |
|---|---|---|
| `[NEEDS-MISSED-YEAR-AUDIT-PASS]` | §12.3 | Log every year's customs rate for narrative / audit (v1 only stores current year) |
| `[NEEDS-YEAR-TICK-CENTRALIZATION-PASS]` | §12.4 | Promote to centralized year_advanced signal if year-bound driver count grows past ~3-4 |

#### 20.2.7 UI / display polish

| Flag | Source | Concern |
|---|---|---|
| `[NEEDS-VEHICLE-DETAIL-PANEL-CARGO-PASS]` | §2.7, §15.8 | Extend `cs_vehicle_detail_panel` with a cargo_holds section alongside inventory_items |
| `[NEEDS-PRICE-ROLL-DEFERRAL-PASS]` | §14.6 | Defer dice-roll-on-preview so browsing doesn't lock prices for the visit |
| `[NEEDS-PRICE-HISTORY-PASS]` | §14.8 | Persist historical prices for "silk was 2,500 last week" UI |
| `[NEEDS-SHIP-SPEED-MODEL-PASS]` | §15.4 | Add `speed_normal` / `speed_loaded` to maritime catalog for sea-vehicle encumbrance display |

#### 20.2.8 Cargo accounting

| Flag | Source | Concern |
|---|---|---|
| `[NEEDS-CARGO-LOSS-DESTRUCTION-SIGNAL-PASS]` | §13.7 | Emit explicit cargo-loss signals when carriers are destroyed |
| `[NEEDS-FK-ENFORCEMENT-PASS]` | §13.6 + §17.9 | Enable `PRAGMA foreign_keys = ON` campaign-wide; activates CASCADE behavior throughout the schema |

**Total carry-forward flags: 34.** All explicitly documented + named so future contributors can find them via grep.

### 20.3 Substrate-inherited flags (reference)

The following flags exist in the substrate (`gdd-settlement-economy.md`) but are NOT Phase 10B.2's responsibility to close. Listed here for cross-reference:

- `[NEEDS-TERRAIN-CANON-REWORK]` — §3.4 climate mapping; awaits terrain canon harmonization session
- `[NEEDS-FLAVOR-PASS]` — §4.4 demand-shuffle semantic categorization
- `[NEEDS-DRIFT-PRECISION-PASS]` — §6.6.4 event-time fidelity in monthly drift
- `[NEEDS-OTHER-PACK-ANIMAL-PASS]` — §8.7 future species beyond donkey/camel/ox
- `[NEEDS-DISTRIBUTION-CALIBRATION]` — §7.6.1 demand-modifier-weighted distribution
- `[NEEDS-PRECIOUS-RATE-PASS]` — §7.13 15% precious dispatch tuning
- `[NEEDS-FEE-OVERRIDE-PASS]` / `[NEEDS-FEE-AUDIT-TRAIL-PASS]` — §8.11 Judge-authored fees + audit
- `[NEEDS-REPUTATION-FEES-PASS]` — §8.11 reputation-driven discounts
- `[NEEDS-CREW-MORALE-PASS]` / `[NEEDS-NAVIGATOR-SEPARATE-ROLE-PASS]` — §9.6 crew model expansion
- `[NEEDS-CARAVAN-MONTHLY-COST-PASS]` — §9.6.2 caravan operating costs
- `[NEEDS-NAVAL-MOVEMENT-PASS]` / `[NEEDS-CREW-INDIVIDUATION-PASS]` — §9.13 naval enhancements
- `[NEEDS-PERMANENT-WOUND-COMBAT-PASS]` — §10.3.1 Maimed combat effects
- `[NEEDS-SPELL-COST-LOOKUP-PASS]` — §11.1 Spell Availability by Market table encoding
- `[NEEDS-MARITIME-CATALOG-VERIFICATION]` — §9.3 maritime.json audit
- `[NEEDS-CARRIER-FALLBACK-PASS]` — §9.8 hijink yield when no carrier available
- `[NEEDS-ADDITIONAL-CANONICAL-ROUTES]` — §12.8 additional validation routes

Phase 10B.2's carry-forward flags do NOT replace these — they're additive.

### 20.4 Phase 10B.2 cumulative non-goals (summary)

Aggregated from each section's "What §X does NOT add" subsection:

**Out of scope for Phase 10B.2 entirely:**
- Phase 10B.3 (Syndicate block) — separate phase
- `solicit_passengers` (Q-TB-2 deferred) — future enhancement
- Judge-modifier sourcing (Q-TB-10) — caller-side; v1 handlers pass 0
- LLM merchant-promotion procedure itself — only forward-compat plumbing ships
- Monopoly grant/revoke logic — API ships; no v1 callers
- Multi-carrier shipping contracts — single-carrier limitation
- Multi-party trade flows — tables support but tests don't exercise
- Save/load round-trip tests — substrate pattern handles automatically
- Performance / load tests
- Real-time encumbrance push via signals
- Mid-transit cargo redistribution UI
- "Buy All" / "Sell All" macros
- Haggling / negotiation
- Reputation-driven fee discounts
- Naval movement / wind / currents
- LLM narrative layer integration
- Settlement-generation work for missing market POIs

**Functional but partial / RAW-incomplete in v1:**
- Shipping contracts: 4 RAW mechanics deferred (staggered availability, trust roll, half-advance, destination-RAW)
- Persuade: full RAW math present but reaction-modifier-suite consolidation deferred
- Solicit: forfeit rollback covered; multi-party attribution deferred
- Year-tick: customs only; future year-bound drivers each handle their own
- Trade-route triggers: 8 signals ship as contracts; emitters wired in Wave 5

### 20.5 GDD sign-off + acceptance

When this GDD is signed off section-by-section (§0 through §20):

1. **Locked design** — implementation pass uses these sections as authoritative spec.
2. **Wave plan ready** — §19's 6 waves are the build-session sequence.
3. **Acceptance criteria scoped** — §19.9's 12-point checklist gates Phase 10B.2 closure.
4. **Carry-forward flags catalogued** — §20.2's 34 flags + §20.3's substrate-inherited flags are the post-10B.2 backlog.
5. **Phase 10B.3 unblocked at Wave 6 completion** — §19.10 documents what 10B.3 consumes from Phase 10B.2.

This GDD becomes Layer-2 authoritative per CLAUDE.md. Future amendments require project-owner sign-off, mirroring the substrate GDD's modification rules.

### 20.6 What §20 does NOT add

- **No new flags.** §20 is a consolidated reference; every flag was planted in its originating section.
- **No flag-prioritization.** All 34 carry-forward flags are listed without rank. A future "post-10B.2 backlog grooming" session can prioritize.
- **No flag-to-section back-references for substrate-inherited flags.** §20.3 lists them; the substrate GDD is the canonical source.
- **No closing the substrate-inherited flags.** Those are outside Phase 10B.2's scope.
- **No "follow-on phase" enumeration beyond Phase 10B.3.** Phase 10B.2's deliverables unblock Phase 10B.3; what comes after Phase 10B.3 is out of scope for this GDD.

---

## End of GDD

`generation/gdd-phase-10b-2-trade-block.md` is complete with 20 sections + a 6-wave implementation plan. Per Q-TB-1 through Q-TB-21 all resolved with explicit sign-off captured in §0.7's cross-section index.

**Next step:** Wave 10B.2.1 (Foundation) — implementation can begin once this GDD is signed off in full.




















