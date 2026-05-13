# GDD — Phase 10B.2 Trade Block

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
- **Project resolution:** the **first** mercantile activity launch per visit triggers the entry toll via the `MarketFeesCalculator.entry_toll_gp` call inside that activity's handler. Subsequent activities within the same visit consult the per-visit state (§9) and don't re-charge. The "visit" boundary is defined as "from the time the party enters the settlement-detail view to the time they depart it" — operationally, a per-party per-settlement boolean flag cleared on departure (design detail in §9).
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

