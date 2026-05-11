# Phase 10B Subsystem Dependencies — Build Map for the Parallel Session

> **Purpose:** This document is the Q5 deliverable from the Phase 10 planning conversation (2026-05-10). It enumerates every prerequisite subsystem that the **Trade block (Phase 10B.2)** and **Syndicate block (Phase 10B.3)** will need to consume, so a separate parallel build session can map and execute the subsystem work without colliding with the Phase 10 surface work.
>
> **Audience:** The build agent (likely Claude in a separate worktree) responsible for landing the merchandise / market-price / Crime & Punishment infrastructure that Phase 10B depends on.
>
> **Scope NOT covered here:** UI surfaces (the Trade & Syndicate blocks themselves — those are Phase 10B.2/10B.3 work), Phase 10A handlers (Faith / Garrison Training — they don't depend on these subsystems), and the existing infrastructure that Phase 10B will reuse but not modify (already-shipped Phase 1-9 code).
>
> **Sequencing constraint:** Phase 10B.2 and 10B.3 cannot start until **all** of these subsystems are present. Phase 10A.x can ship independently.

---

## 1. Common & Precious Merchandise data + registry

### Why it's needed
- **Smuggling hijink** ([rules/acore-campaign-hijinks.xml:152-172](rules/acore-campaign-hijinks.xml:152)) — perpetrator smuggles 10 loads/level of a *random* merchandise type → boss receives 12% of market value. Without merchandise tables we cannot determine what gets smuggled or what 12% of its value is.
- **Stealing hijink** ([rules/acore-campaign-hijinks.xml:195-216](rules/acore-campaign-hijinks.xml:195)) — perpetrator steals 2 loads/level → boss receives 60% of market value. Same need.
- **Mercantile arbitrage** ([rules/acore-campaign-hijinks.xml:617-763](rules/acore-campaign-hijinks.xml:617)) — buy_sell_merchandise, persuade_merchants, solicit_merchants. The whole merchant interaction loop is rooted in merchandise types.
- **Carousing/spying/treasure-hunting** also need it (carousing yields rumor-gp from a "rumor about merchandise" flavor; treasure-hunting awards a hoard whose composition uses merchandise tables).

### What to build
- **`data/commerce/common_merchandise.json`** — the Common Merchandise table from ACKS Core. Each row: `merchandise_type` (e.g. `bulk_grain`, `fine_textiles`, `salt`), `base_price_gp_per_load`, `load_weight_stone`, `precious: false`, `notes`. Number of rows: ACKS Core lists about 24 common types — get the exact count from the rulebook.
- **`data/commerce/precious_merchandise.json`** — the Precious Merchandise table. Each row: same shape with `precious: true`. About 8-12 rows.
- **`engine/subsystems/commerce/merchandise_registry.gd`** — autoloaded registry (or non-autoload service, depending on how heavy). Public API:
  ```
  func all_common() -> Array[Dictionary]
  func all_precious() -> Array[Dictionary]
  func get_by_type(merchandise_type: String) -> Dictionary
  func random_common(rng: RandomNumberGenerator) -> Dictionary
  func random_precious(rng: RandomNumberGenerator) -> Dictionary
  func base_price_gp_per_load(merchandise_type: String) -> int
  func load_weight_stone(merchandise_type: String) -> int
  ```
- **Tests:** `tests/test_merchandise_registry.gd` — verify load count matches RAW table size, base prices match RAW values for a few sampled rows, random_common() distribution is uniform.

### Sequencing
- Standalone work; no dependencies on other Phase 10B prerequisites.

---

## 2. Per-settlement merchandise demand modifiers

### Why it's needed
- **Market price formula** ([rules/acore-campaign-hijinks.xml:719-735](rules/acore-campaign-hijinks.xml:719)) — `4d4 + demand_modifier_for_this_merchandise_in_this_market + class_size_adjust`, then ×10% applied to base price. Without per-settlement demand modifiers, all markets price merchandise identically (kills arbitrage).
- **Persuade-merchants** ([rules/acore-campaign-hijinks.xml:707-716](rules/acore-campaign-hijinks.xml:707)) — reaction roll modified by demand: `+demand_mod` when seeking buyers, `-demand_mod` when seeking sellers.
- **Smuggling/stealing payouts** also use market price (12% / 60% of computed market price).

### What to build
- **Schema (new migration):** `settlement_merchandise_demand(settlement_entrance_id, merchandise_type, demand_modifier INTEGER NOT NULL DEFAULT 0, generated_at_calendar_day, source_kind)`. Source kind: `"generated"` (procedurally rolled) or `"manual"` (Judge override).
- **`engine/subsystems/commerce/demand_modifier_generator.gd`** — generates demand modifiers per RAW. Two strategies:
  - **Per-settlement-on-first-visit:** lazy-generate when the merchandise type is first queried for that settlement. Cache the result in the table.
  - **Bulk-on-settlement-creation:** generate all modifiers at settlement spawn time. Heavier upfront cost; simpler reads.
  - Recommendation: lazy-generate, cache.
- **`engine/subsystems/commerce/market_price_resolver.gd`** — the 4d4 procedure:
  ```
  static func compute_market_price(
      merchandise_type: String,
      settlement_id: String,
      monopolist_bonus: bool,
      class_size_adjust: int,  # +1 for class I/II, -1 for V/VI
      special_judge_modifier: int = 0,
      rng: RandomNumberGenerator = null,
  ) -> Dictionary  # { gp_per_load: int, percentage: int, breakdown: Array }
  ```
  - **Price changes over time:** [rules/acore-campaign-hijinks.xml:737-739](rules/acore-campaign-hijinks.xml:737) — 10% cumulative monthly chance of a re-roll while staying in the same market. Implement as a `last_priced_calendar_day` field per (settlement, merchandise) pair, plus a monthly-tick step that rolls per cached price.
- **Tests:** `tests/test_demand_modifier_generator.gd`, `tests/test_market_price_resolver.gd` (verify formula, monopolist bonus, class-size adjust, +/- demand pivot for buy vs sell).

### Sequencing
- Depends on §1 (merchandise registry must exist before per-merchandise modifiers can be generated).

---

## 3. Per-settlement merchant pool

### Why it's needed
- **`solicit_merchants`** ([rules/ax_campaign_play.xml:949-964](rules/ax_campaign_play.xml:949)) — Ongoing 1-3 weeks; uses the Market and Merchants table from [rules/acore-campaign-hijinks.xml:656-672](rules/acore-campaign-hijinks.xml:656) to determine merchant count and loads-per-merchant per market class. Phased availability: half ceil week 1, quarter floor (min 1) week 2, remainder week 3.
- **`persuade_merchants`**, **`buy_sell_merchandise`** — operate on the merchant pool produced by solicit.

### What to build
- **Schema (new migration):** `merchant_pool(id, settlement_entrance_id, merchant_kind, merchandise_type, loads_available, expires_calendar_day, status, source_solicitation_id)`. `expires_calendar_day` reflects merchants leaving over time (project-designed: set to `current_day + 30` since merchants are mobile and don't stay forever).
- **`engine/subsystems/commerce/merchant_solicitor.gd`** — handler-side logic for `solicit_merchants` Ongoing activity. On each weekly tick:
  - Roll merchant count + loads from Market and Merchants table per the settlement's market class
  - Half ceil → `merchant_pool` rows in week 1; quarter floor (min 1) in week 2; remainder in week 3
  - Each merchant's merchandise type via `MerchandiseRegistry.random_common()` (or `random_precious()` per market class — class IV+ can carry precious per RAW)
  - "Domain-owner gets max merchants" rule per [rules/ax_campaign_play.xml:963](rules/ax_campaign_play.xml:963) — bypass roll, use table max
- **`engine/subsystems/commerce/merchant_pool_repository.gd`** — CRUD + queries: list_for_settlement, list_by_merchandise_type, claim_loads (decrement after successful transaction).
- **Tests:** `tests/test_merchant_solicitor_ongoing.gd`, `tests/test_merchant_pool_repository.gd`.

### Sequencing
- Depends on §1 (merchandise types) and §2 (demand modifiers for price computation).

---

## 4. Customs duties + moorage / stabling fees

### Why it's needed
- **`buy_sell_merchandise`** + **`enter_market`** — RAW imposes:
  - Loading/unloading: 1gp per 200 stone of merchandise ([rules/ax_campaign_play.xml:828](rules/ax_campaign_play.xml:828))
  - Customs duty on selling: 2d10% of market price ([rules/ax_campaign_play.xml:829](rules/ax_campaign_play.xml:829))
  - Toll to enter market (varies by class)
  - Moorage: 1gp per 10 SHP per day for ships ([rules/ax_campaign_play.xml:872-875](rules/ax_campaign_play.xml:872))
  - Stabling: 2sp/mule, 5sp/horse, 1gp/cart, 2gp/wagon per day
- **Domain-owner exemption:** PCs trading in their own domain skip moorage/stabling/tolls/customs.

### What to build
- **`engine/subsystems/commerce/market_fees_calculator.gd`** — pure-function helpers:
  ```
  static func loading_fee_gp(merchandise_loads: int, load_weight_stone: int) -> int
  static func customs_duty_gp(market_price_gp: int, rng: RandomNumberGenerator) -> int  # 2d10% of price
  static func entry_toll_gp(settlement_market_class: int, rng: RandomNumberGenerator) -> int
  static func ship_moorage_gp_per_day(ship_shp: int) -> int
  static func stabling_gp_per_day(mounts: Dictionary) -> int  # {mule: n, horse: n, cart: n, wagon: n}
  static func is_domain_owner_in_own_market(character_id: String, settlement_id: String) -> bool
  ```
- **No schema** — fees are computed per transaction/per day, not stored.
- **Tests:** `tests/test_market_fees_calculator.gd`.

### Sequencing
- Standalone (only depends on `MerchandiseRegistry` for load weights, which is §1).

---

## 5. Caravan & Ship vehicle system (or a v1 stub)

### Why it's needed
- **Mercantile flow needs cargo holds:** smuggled/stolen goods from hijinks could plausibly enter cargo for transport; bought merchandise must be transported to another market for arbitrage; passengers/shipping contracts need vessels to carry them.
- The existing `cs_vehicle_detail_panel.gd` hints at a vehicle data model but it's barebones.

### What to build (decision point — full vs. stub)
- **Full implementation:**
  - Schema: `vehicles(id, owner_character_id, vehicle_type, shp_max, shp_current, cargo_capacity_stone, cargo_capacity_used_stone, location_kind, location_ref, crew_assigned, monthly_cost_gp, status)`. Vehicle types: `small_sailing_ship`, `large_sailing_ship`, `caravan_10_wagon`, `caravan_20_wagon`, `caravan_30_wagon`, `caravan_40_wagon` (per [rules/acore-campaign-hijinks.xml:844-906](rules/acore-campaign-hijinks.xml:844)).
  - Schema: `cargo_holds(id, vehicle_id, contents_kind, merchandise_type, loads_carried, market_value_gp, source_acquisition_kind)`. `source_acquisition_kind`: `"purchased"`, `"smuggled"`, `"stolen"`, `"shipping_contract"`, `"passenger"`.
  - `engine/subsystems/commerce/vehicle_repository.gd` — CRUD.
  - `engine/subsystems/commerce/cargo_manager.gd` — load/unload/transport operations.
- **v1 stub (recommended unless full caravans are part of v1 scope):**
  - Schema: a single `vehicle_summary(character_id, has_caravan, has_ship, total_cargo_capacity_stone, current_cargo_value_gp)` — an aggregate view, no per-vehicle tracking.
  - The hijink yield (smuggled goods) becomes pure gp paid to the boss (boss gets 12% of computed market value as gp; the merchandise narrative is logged but does NOT enter cargo). This matches Q5's per-Jedidiah recommendation.
  - For mercantile arbitrage (buy in market A, sell in market B): defer the multi-leg cargo-transport flow to v1.1+. Phase 10B.2 surfaces buy_sell_merchandise as a single-market transaction (immediate gp; no inventory entry).

**Recommendation per Q5:** Build the **stub** for v1. The full vehicle/cargo system is a substantial side-project that doesn't need to block Phase 10B. Document the simplification in the build log.

### Tests (for stub)
- `tests/test_vehicle_summary.gd` — basic CRUD and aggregate view.

### Sequencing
- Standalone if stubbed; depends on §1-3 if full.

---

## 6. Profession (attorney) + prior_crimes proficiency tracking

### Why it's needed
- **Crime & Punishment resolver** ([rules/acore-campaign-hijinks.xml:260-315](rules/acore-campaign-hijinks.xml:260)):
  - "Add the perpetrator's rank in Profession (attorney), if any."
  - Prior crimes apply: Branded (-1), Maimed (-2), Proscribed (-3) — these are permanent character flags from prior verdicts.
- **`hire_attorney`** activity grants +1/+2/+3 modifiers via cost; needs a way to consume these on the C&P throw.

### What to build
- **Schema (new migration):** Add `prior_crimes_marker_count INTEGER NOT NULL DEFAULT 0` and `prior_crimes_modifier INTEGER NOT NULL DEFAULT 0` columns to `characters` table (or to a sibling `character_legal_status` table — separate table is cleaner). Markers are set when a verdict applies a brand/maim/proscription.
- **Profession (attorney) proficiency:** verify the existing proficiency system supports this proficiency name. If not, add it as a row in the proficiency catalog. Lookup in C&P resolver: `ProficiencyRegistry.get_rank(character_id, "profession_attorney")`.
- **No new resolver** — this is data-side support that Phase 10B.3's `crime_and_punishment_resolver.gd` will consume. The parallel session just needs to ensure the column/proficiency exists.

### Sequencing
- Standalone.

---

## 7. Henchman Loyalty integration for syndicate management

### Why it's needed
- **`order_hijink`** ([rules/ax_campaign_play.xml:1213-1214](rules/ax_campaign_play.xml:1213)) — assigning additional hijinks beyond one per month, OR imposing a deadline, triggers a Henchman Loyalty roll by the member.
- **Underboss authority** ([rules/acore-campaign-hijinks.xml:488-494](rules/acore-campaign-hijinks.xml:488)) — boss assigning hijinks to >20% of an underboss's followers triggers underboss Henchman Loyalty roll (cumulative -1 per additional 10%).
- **Caught syndicate members and abandonment** ([rules/acore-campaign-hijinks.xml:407-408](rules/acore-campaign-hijinks.xml:407)) — if boss regularly abandons caught members, the Judge may roll on Henchman Loyalty for remaining members.

### What to build
- **No new infrastructure.** The existing `engine/subsystems/henchmen/henchman_loyalty_resolver.gd` (cited in roadmap §critical-files-inventory as "Reused") already handles loyalty cascades. Phase 10B.3's `order_hijink.gd` + `crime_and_punishment_resolver.gd` will call into it directly.
- **Verify:** the loyalty resolver accepts a `modifier_dict` parameter so Phase 10B.3 can pass in `{"hijink_overload_count": 3}` → cumulative -3 modifier per [rules/acore-campaign-hijinks.xml:492](rules/acore-campaign-hijinks.xml:492). If it doesn't, the parallel session should extend the API.

### Sequencing
- Audit-only (verify the existing API). No new build required unless an API gap is found.

---

## 8. Spell-cost lookup table for Faith block (Phase 10A.2 dependency, but worth flagging)

### Why it's flagged here
- Not a Phase 10B dependency, but Phase 10A.2's `cast_charitable_spells` handler needs to compute the gp value of charitably-cast spells from the "Spell Availability by Market" table. If this table isn't already wired into `SpellRegistry`, it should be — and the parallel session may pick that up if Phase 10A.2 surfaces a gap.
- **Verify:** does `SpellRegistry` (or some other system) already expose `get_spell_cost_gp(spell_key)` per the Spell Availability by Market table?
- If not, the parallel session should add it (or Phase 10A.2 will, in passing).

### Sequencing
- Audit-only.

---

## Suggested build order for the parallel session

1. **§1 Merchandise registry** (foundational; everything else depends on it)
2. **§4 Market fees calculator** (standalone; small)
3. **§6 Profession (attorney) + prior_crimes columns** (standalone; small)
4. **§7 Henchman loyalty audit** (no-build if API is sufficient)
5. **§2 Per-settlement demand modifiers** (depends on §1)
6. **§3 Per-settlement merchant pool** (depends on §1, §2)
7. **§5 Vehicle/cargo stub** (recommended) — small surface
8. **§8 Spell-cost lookup audit**

Total estimated session count: 2-3 sessions for the parallel work, depending on how clean the integration goes. Each subsystem should ship with focused unit tests.

---

## Acceptance criteria

The parallel session is **done** for Phase 10B.2/10B.3 unblocking when:

- [ ] `MerchandiseRegistry.get_by_type("bulk_grain")` returns a fully-populated dict with base price and load weight matching the ACKS Core Common Merchandise table.
- [ ] `MarketPriceResolver.compute_market_price("salt", "<settlement_id>", false, +1, 0, rng)` returns a sensible gp value per the 4d4+demand+class procedure.
- [ ] `MerchantSolicitor.run_weekly_tick(activity_state)` produces correct phased merchant counts (half ceil / quarter floor min 1 / remainder) into the `merchant_pool` table.
- [ ] `MarketFeesCalculator.customs_duty_gp(1000, rng)` returns a value in [20, 200] (2d10% of 1000).
- [ ] A character can be assigned the `profession_attorney` proficiency at rank 1-3, and `ProficiencyRegistry.get_rank` returns the correct value.
- [ ] `prior_crimes_modifier` field exists on `characters` (or sibling table) and is mutable.
- [ ] All new tests pass; existing test suite is not regressed.

When all boxes are checked, Phase 10B.2 (Trade) and 10B.3 (Syndicate) can begin.
