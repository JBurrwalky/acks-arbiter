# GDD — Tavern Menu Generation

> **Status:** Draft v0.1 (2026-05-12). For Jedidiah's review.
>
> **Layer:** 2 — Project-designed. ACKS 1e is silent on tavern menus per se. The relevant RAW substrate is the settlement/market-economy framework in `rules/acore-setting-construction-rules.xml` (market class, environmental and racial demand modifiers, trade routes) and the price/drift formula in `rules/acore-campaign-hijinks.xml`. Those are sacred.
>
> **Companion documents:**
> - `generation/gdd-settlement-economy.md` — settlement-level economic state, demand-modifier generation, market-price computation. **This GDD consumes its outputs; it does not duplicate or reinterpret them.**
> - `generation/gdd-settlement-layout.md` — PoI catalog; defines the `tavern` PoI type and its three flavor variants (`common`, `upscale`, `seedy`).
> - `generation/gdd-settlement-exploration-ui.md` — defines the "Buy Food/Drink" activity on the tavern PoI, which is this GDD's UI consumer.
> - `generation/gdd-cultural-religious-generation.md` — supplies the cultural/regional descriptor tags this GDD reads.
> - `generation/gdd-name-generation.md` — generates tavern names and is the precedent for menu-item flavor-name generation.

---

## §0. Document Goals, Scope, and the RAW-vs-Project-Design Ledger

### 0.1 What this GDD covers

1. The **menu schema** — what a generated tavern menu looks like in SQLite and at runtime.
2. The **drink generator** — which drink categories appear at which market class, how price is anchored to the settlement-economy substrate, and how cultural/regional flavor labels are applied.
3. The **meal generator** — same structure for meals; smaller catalog, tighter price band.
4. The **flavor-name layer** — how a generic "ale, common" line becomes "Brindle Brewer's Stout" or "Goldhop Bitter" in display text without affecting price or mechanics.
5. The **PoI flavor effect** — how the `common` / `upscale` / `seedy` tavern variants modify menu composition and prices.
6. **Persistence and regeneration cadence** — menus are generated once per tavern and re-rolled monthly in step with market-price drift.
7. **UI consumer contract** — the data shape the "Buy Food/Drink" activity reads.

### 0.2 What this GDD does NOT cover

- Tavern *services* other than food and drink — Rest, Gather Information, Carouse, Hire Henchmen, Recruit Mercenaries — those are owned by `gdd-settlement-exploration-ui.md` and the carousing hijink in `acore-campaign-hijinks.xml`.
- Drunkenness mechanics, intoxication encounters, or carousing outcomes (carousing hijink owns those).
- The settlement-economy substrate itself (`gdd-settlement-economy.md` owns demand-mod generation and base price computation; this GDD only *reads* its outputs).
- Generating tavern *names*, *layouts*, or *NPC* keepers (other GDDs).

### 0.3 RAW-vs-Project-Design ledger format

Every project-designed rule below carries a four-line ledger entry:

- **RAW citation** (file + line range, or "RAW is silent")
- **What RAW provides**
- **What's missing**
- **Project resolution**

The ledger is the audit trail. If a future contributor asks "why is the chase mead 8sp at Class III but 12sp at Class V," the trail must lead to either an XML rule or a project-design rationale.

### 0.4 Authority and modification rules

- This GDD is Layer-2 — modifiable with Jedidiah's sign-off.
- The **base prices** and the **demand-modifier-to-price formula** come from RAW (`acore-campaign-hijinks.xml`) and are not modifiable here.
- The **catalog of menu items**, **flavor-naming**, **PoI-flavor adjustments**, and **menu regeneration cadence** are project-designed.

### 0.5 Calendar conventions

Per `engine/autoloads/timekeeping.gd`, the project's month is 28 days. "Monthly menu re-roll" in this document means 28 calendar days.

---

## §1. Conceptual Model

A **tavern menu** is a data object owned by a `tavern` PoI inside a `settlement_entrances` row. It is *derived* — never authored — from three inputs:

1. The **settlement's market state** (market class, urban families, finished demand modifiers for the food/drink merchandise categories: `grain_vegetables`, `meats_preserved`, `fish_preserved`, `beer_ale`, `wine_spirits`, `tea_or_coffee`, `salt`, `spices`).
2. The **regional/cultural descriptors** carried by the settlement (biome, dominant race, dominant cultural tag).
3. The **tavern's PoI flavor** — `common`, `upscale`, or `seedy` per `gdd-settlement-layout.md` §6.3.

The menu is a list of **menu lines**, each of which is one purchasable item with a fixed price in copper pieces (cp). Drinks are typically priced per mug/cup; meals are priced per serving. A line has an internal merchandise category (so price can be recomputed deterministically when demand modifiers drift) and a display name (the flavor-naming layer's output).

### 1.1 Design principles

- **Determinism.** Menu generation is a pure function of (settlement state, PoI state, RNG seed). Same inputs → same menu. The RNG seed is `(settlement_id, poi_id, month_of_generation)`.
- **The economy is the price.** Menu prices are anchored to the same demand-modifier outputs the merchandise market uses. A glut of grain in the region lowers the price of bread; a beer-positive racial adjustment makes ale cheap.
- **Flavor is cosmetic.** Cultural and regional tags affect *which catalog entries appear* and *how they are named*, but never affect price independently of the demand-modifier substrate. (Rationale: keeps the price math auditable.)
- **Menu lines are categorical, not unique.** "Ale, common" is one menu line whether it's named "Brindle Stout" or "Goldhop Bitter." Display-name variation is cosmetic. Mechanics never branch on display name.

### 1.2 Why not generate menus per-day or per-visit?

Considered and rejected. Daily regeneration creates churn the player can't act on; per-visit regeneration creates save-scumming for cheap food. The 28-day cadence ties menus to the market-price drift cycle (which `gdd-settlement-economy.md` §6 sets at a 10%-per-month re-roll trigger) so player-facing price stability matches the substrate's stability.

**Project-design ledger:**

- **RAW citation:** RAW is silent on tavern menus. Adjacent RAW is the merchandise price drift mechanic at `rules/acore-campaign-hijinks.xml:737-739` (10%/month re-roll).
- **What RAW provides:** A monthly stability cadence for market prices.
- **What's missing:** A cadence for derived/retail prices like tavern fare.
- **Project resolution:** Tavern menus regenerate on the same 28-day cycle as the market-price re-roll, triggered by the same `monthly_economy_tick` signal `gdd-settlement-economy.md` defines. One source of cadence, one signal.

---

## §2. Data Model

### 2.1 SQLite schema

Two new tables, plus an FK column on the existing `pois` (or whatever `gdd-settlement-layout.md`'s PoI table is named — confirm at implementation time).

```sql
-- The generated menu for one tavern PoI. One row per tavern.
CREATE TABLE tavern_menus (
    id              INTEGER PRIMARY KEY,
    poi_id          INTEGER NOT NULL REFERENCES pois(id) ON DELETE CASCADE,
    settlement_id   INTEGER NOT NULL REFERENCES settlement_entrances(id) ON DELETE CASCADE,
    generation_seed INTEGER NOT NULL,
    generated_at    INTEGER NOT NULL,
    poi_flavor      TEXT    NOT NULL,
    UNIQUE(poi_id)
);
CREATE INDEX idx_tavern_menus_settlement ON tavern_menus(settlement_id);

-- One row per menu line. A menu has 4-12 drinks and 2-8 meals, roughly.
CREATE TABLE tavern_menu_lines (
    id              INTEGER PRIMARY KEY,
    menu_id         INTEGER NOT NULL REFERENCES tavern_menus(id) ON DELETE CASCADE,
    line_kind       TEXT    NOT NULL,
    catalog_id      TEXT    NOT NULL,
    merchandise_cat TEXT    NOT NULL,
    display_name    TEXT    NOT NULL,
    price_cp        INTEGER NOT NULL,
    quality_tier    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_tavern_menu_lines_menu ON tavern_menu_lines(menu_id);
```

**Why `price_cp` rather than gp/sp:** the cheapest item on a Class VI rural menu can be 1 cp (a cup of small beer). Storing copper avoids fractional-coin rounding ambiguity entirely. Display formatting (cp → sp/gp where appropriate) is the UI's job.

**Banker's rounding** is applied at every step of the price computation (per `CLAUDE.md` §Core Principles). The implementation function — call it `MenuPricer.round_to_cp(value: float) -> int` — uses round-half-to-even.

**Project-design ledger (schema choice):**

- **RAW citation:** RAW is silent on storage format.
- **What RAW provides:** N/A.
- **What's missing:** A schema decision.
- **Project resolution:** Two tables, one menu : many lines, copper-piece integer prices, deterministic seed stored so a menu can be re-derived from inputs for audit.

### 2.2 Runtime resource

```gdscript
# engine/data/tavern_menu.gd
class_name TavernMenu  # NOTE: not in an autoload — see CLAUDE.md Godot-constraints
extends Resource

@export var poi_id: int
@export var settlement_id: int
@export var poi_flavor: String           # 'common' | 'upscale' | 'seedy'
@export var drinks: Array[TavernMenuLine]
@export var meals: Array[TavernMenuLine]
@export var generated_on_day: int        # world-day
```

`TavernMenuLine` mirrors the row schema.

---

## §3. Static Catalog of Menu Items

A static GDScript resource defines the universe of possible menu items. The generator selects from this catalog; it never invents new entries at runtime. (Rationale: keeps display-text auditable, keeps localization tractable, keeps the LLM out of the price loop.)

### 3.1 Drink catalog

| catalog_id | merchandise_cat | min_market_class | base_price_cp | qualifiers |
|---|---|---|---|---|
| `small_beer` | beer_ale | VI (any) | 1 | — |
| `ale_common` | beer_ale | VI | 2 | — |
| `ale_strong` | beer_ale | V | 4 | — |
| `cider_common` | beer_ale | V | 3 | requires biome with orchard fruit |
| `mead_common` | beer_ale | IV | 5 | — |
| `mead_fine` | wine_spirits | III | 12 | flavor-eligible |
| `wine_table` | wine_spirits | IV | 6 | requires wine-producing biome OR trade route |
| `wine_fine` | wine_spirits | III | 18 | upscale only |
| `wine_imported` | wine_spirits | II | 30 | trade route to producing region |
| `spirits_local` | wine_spirits | III | 8 | — |
| `spirits_aged` | wine_spirits | II | 25 | upscale |
| `tea_common` | tea_or_coffee | III | 4 | requires trade route OR producing region |
| `coffee_common` | tea_or_coffee | II | 8 | as above |
| `water` | (none) | VI | 0 | always present; free or 1 cp |
| `milk` | (none) | VI | 1 | rural / village |
| `kumiss` | beer_ale | V | 3 | steppe-cultural |
| `palm_wine` | wine_spirits | V | 4 | savanna / rainforest |

The `min_market_class` column means the item only appears at settlements of that class or larger (lower roman-numeral = larger market). The `qualifiers` column gates an item on biome/cultural tags or trade routes.

### 3.2 Meal catalog

| catalog_id | merchandise_cat | min_market_class | base_price_cp | qualifiers |
|---|---|---|---|---|
| `bread_and_cheese` | grain_vegetables | VI | 3 | — |
| `pottage` | grain_vegetables | VI | 2 | — |
| `stew_common` | meats_preserved | VI | 5 | — |
| `roast_fowl` | meats_preserved | V | 12 | — |
| `roast_meat` | meats_preserved | IV | 18 | — |
| `fish_fresh` | fish_preserved | V | 6 | requires sea/lake/river biome |
| `fish_salted` | fish_preserved | VI | 4 | — |
| `game_pie` | meats_preserved | V | 10 | requires forest/hills/mountains |
| `spiced_dish` | spices | III | 20 | trade route OR savanna/rainforest |
| `feast_plate` | meats_preserved | III | 50 | upscale only |
| `traveler_ration` | grain_vegetables | VI | 2 | always present |

### 3.3 Catalog editability

This catalog is project-designed (Layer 2). Jedidiah may add entries, remove entries, or adjust base prices, qualifiers, and min-market-class. The schema and generator must not hard-code item IDs; they read from the catalog resource.

**Project-design ledger:**

- **RAW citation:** RAW is silent on tavern-fare item catalogs.
- **What RAW provides:** Eleven food/drink merchandise categories (`grain_vegetables`, `meats_preserved`, `fish_preserved`, `salt`, `beer_ale`, `wine_spirits`, `tea_or_coffee`, `spices`, etc.) with environmental and racial demand modifiers; market-class price formula.
- **What's missing:** A mapping from those wholesale categories to retail menu items.
- **Project resolution:** A static catalog whose every entry tags its driving merchandise category, so retail prices ride the wholesale-price substrate.

---

## §4. Price Computation

Each menu line's `price_cp` is derived deterministically from the settlement's market state plus a small set of tavern-flavor multipliers.

### 4.1 Inputs (from `gdd-settlement-economy.md`)

For the settlement, the economy substrate provides for each merchandise category `m`:

- `finished_demand_modifier(settlement, m)` — integer (post environmental, racial, domain, and trade-route adjustments).
- `market_price_factor(settlement, m)` — the multiplier RAW derives from `4d4 + demand_mod + class_size_adjust`, divided by the RAW baseline. We do **not** re-implement this; we *consume* it.

Concretely, `gdd-settlement-economy.md` already exposes a function we'll call `Economy.retail_factor(settlement_id, merchandise_cat) -> float`. Default value 1.0 = "this settlement is paying RAW base price."

### 4.2 Formula

For a menu line with catalog entry `c` at tavern with flavor `f`:

```
raw_factor   = Economy.retail_factor(settlement_id, c.merchandise_cat)   # 0.4 .. 2.5 typical
flavor_mult  = FLAVOR_MULT[f]                                             # see §4.3
markup       = TAVERN_MARKUP                                              # see §4.4
price_cp     = round_half_to_even(c.base_price_cp * raw_factor * flavor_mult * markup)
price_cp     = max(price_cp, FLOOR[c.catalog_id])                         # see §4.5
```

Items whose `merchandise_cat` is `(none)` (water, milk) skip `raw_factor` (treated as 1.0) and apply only flavor and markup.

### 4.3 Flavor multipliers

| poi_flavor | drink_mult | meal_mult |
|---|---|---|
| `common` | 1.00 | 1.00 |
| `upscale` | 1.75 | 1.75 |
| `seedy` | 0.70 | 0.70 |

**Project-design ledger:**

- **RAW citation:** RAW is silent on tavern-flavor variance.
- **What RAW provides:** Recognizes establishment quality only via lifestyle/cost-of-living tables (not in scope here).
- **What's missing:** A mechanic for differentiated tavern tiers.
- **Project resolution:** A single multiplier per flavor, applied identically to drinks and meals. ~1.75 / ~0.70 chosen so an upscale meal at 50cp base ≈ 88cp ≈ ~1gp and a seedy version drops to ~35cp; price ladder reads cleanly.

### 4.4 Tavern markup

`TAVERN_MARKUP = 1.5`. This is the constant retail markup over wholesale-anchored base price, representing the keeper's labor, fuel, and overhead.

**Project-design ledger:**

- **RAW citation:** RAW prices in `rules/acore_equipment.xml` are listed at retail; RAW does not separately model retail-vs-wholesale spread.
- **What RAW provides:** Nothing direct.
- **What's missing:** Whether base_price_cp in §3 is intended to be wholesale (and gets marked up) or retail (and rides at raw_factor only).
- **Project resolution:** The §3 catalog is authored *as retail at a 1.0 raw_factor common tavern* (which means `TAVERN_MARKUP = 1.0` and the constant could be removed). I'm preserving the constant in the formula for tunability — Jedidiah may want to tighten or widen retail spreads in playtest without re-authoring the catalog. **Open question for Jedidiah:** confirm `TAVERN_MARKUP = 1.0` or another value before implementation.

### 4.5 Price floors

A line's price never drops below 1 cp (every menu item costs *something*) except `water`, which can be free. The catalog can specify per-item floors via a `FLOOR` map; default floor is 1.

### 4.6 Quality-tier adjustment

A menu line generated at quality tier `+1` (fine) costs ×1.5; tier `−1` (swill) costs ×0.6. Quality tiers are issued sparingly by the generator (§6.3).

---

## §5. Flavor Naming

Each generated menu line gets a display name. The flavor-naming layer is a deterministic seeded template fill.

### 5.1 Templates per cultural tag

A cultural-tag resource (consumed from `gdd-cultural-religious-generation.md`) supplies, per culture:

- A list of **brewer/cook surnames** (e.g., Auran: "Brindle", "Goldhop", "Wreath"; Argollëan: "Sylvaen", "Moonleaf").
- A list of **adjectives** (e.g., Auran: "Old", "Imperial", "Honest"; Argollëan: "Silver", "Singing", "Sunset").
- A list of **place/landmark fragments** (e.g., "Bridge", "Glen", "Hollow").

### 5.2 Templates per catalog entry

Each catalog entry defines 1–3 naming templates with placeholders:

```
ale_common: ["{surname}'s {style}", "The {adj} Ale", "{place} Brown"]
mead_fine:  ["{adj} {flower} Mead", "{surname} {Estate} Mead"]
fish_fresh: ["Fresh {fish_species}", "{place} {fish_species}"]
```

`{fish_species}` and similar biome-derived placeholders pull from the settlement's biome resource (e.g., "trout" in cold rivers, "snapper" on coasts).

### 5.3 Determinism

The flavor-name RNG is seeded from `(menu_id, line_id, catalog_id)`. Same menu → same names forever.

### 5.4 Display-name versus mechanics

The `display_name` column is what the UI shows. The `catalog_id` column is what mechanics branch on. **No game logic anywhere may switch on `display_name`** — that's a hard rule. (If we ever want "Brindle Brewer's Stout" to trigger a special encounter, we add a `tags` column to the catalog and let the encounter logic read tags, not names.)

### 5.5 LLM does NOT generate names at runtime

Per `CLAUDE.md` §Core Principles ("Build mechanically, narrate retroactively"), name generation is mechanical via templates. The LLM may *narrate* what the player sees ("the publican slides over a foaming mug of Brindle Stout") but does not invent the menu or its prices.

---

## §6. The Generator

### 6.1 Algorithm

```
function generate_menu(settlement, poi):
    seed = hash(settlement.id, poi.id, current_month_index)
    rng = RNG(seed)

    market_class = settlement.market_class           # 1..6
    biome_tags   = settlement.biome_tags
    culture_tag  = settlement.dominant_culture
    flavor       = poi.tavern_flavor                 # 'common'|'upscale'|'seedy'

    eligible_drinks = filter(DRINK_CATALOG, fn(c):
        c.min_market_class >= market_class and
        qualifiers_satisfied(c, biome_tags, culture_tag, settlement.trade_routes) and
        not (c.upscale_only and flavor != 'upscale')
    )
    eligible_meals  = filter(MEAL_CATALOG, ...)

    n_drinks = drink_count_for(market_class, flavor, rng)
    n_meals  = meal_count_for(market_class, flavor, rng)

    drinks = weighted_sample(eligible_drinks, n_drinks, rng, weights=demand_weights)
    meals  = weighted_sample(eligible_meals, n_meals, rng, weights=demand_weights)

    for line in drinks + meals:
        line.quality_tier = roll_quality(flavor, rng)

    for line in drinks + meals:
        line.display_name = flavor_name(line.catalog_id, culture_tag, rng_for(line))

    for line in drinks + meals:
        line.price_cp = compute_price(line, settlement, flavor)

    if 'water' not in drinks: drinks.prepend(water_line(...))
    if 'traveler_ration' not in meals and flavor != 'upscale':
        meals.append(traveler_ration_line(...))

    return TavernMenu(...)
```

### 6.2 Menu size by market class and flavor

| market_class | common drinks | common meals | upscale drinks | upscale meals | seedy drinks | seedy meals |
|---|---|---|---|---|---|---|
| VI | 3 | 2 | n/a | n/a | 3 | 2 |
| V | 4 | 3 | 4 | 3 | 4 | 2 |
| IV | 5 | 3 | 6 | 4 | 4 | 2 |
| III | 6 | 4 | 8 | 5 | 5 | 3 |
| II | 7 | 5 | 10 | 6 | 6 | 3 |
| I | 8 | 6 | 12 | 8 | 6 | 3 |

The "n/a" for upscale at Class VI: upscale taverns don't exist at hamlet scale; the PoI generator (`gdd-settlement-layout.md`) shouldn't be placing them there in the first place. If somehow asked, treat as `common`.

### 6.3 Quality-tier roll

For each line, after the catalog draw:

| flavor | P(tier −1) | P(tier 0) | P(tier +1) |
|---|---|---|---|
| `common` | 0.10 | 0.85 | 0.05 |
| `upscale` | 0.00 | 0.40 | 0.60 |
| `seedy` | 0.50 | 0.50 | 0.00 |

### 6.4 Weighted sampling by demand

The `demand_weights` give higher selection probability to merchandise categories with positive finished demand modifiers (the region prefers those goods) and lower probability to categories with negative modifiers. Concretely:

```
weight(item) = max(0.1, 1.0 + 0.3 * demand_mod(item.merchandise_cat))
```

This makes a steppe town (positive beer_ale, low wine_spirits demand) lean ale-heavy on its menu without the catalog hard-coding biome bias.

**Project-design ledger:**

- **RAW citation:** RAW supplies demand modifiers per merchandise category and biome (`rules/acore-setting-construction-rules.xml:297-353`).
- **What RAW provides:** The integer modifier itself.
- **What's missing:** How to turn that modifier into menu *composition* (not just price).
- **Project resolution:** Linear weight `1.0 + 0.3·mod` with a 0.1 floor so even unfavored categories occasionally surface. Coefficient is tunable.

### 6.5 Why a seeded RNG and not stored selections

We store the seed, the generation day, and the resulting lines. The seed lets us audit: if Jedidiah ever asks "why did the Aerendel Tavern get coffee in winter month 3," the seed reproduces the trace. Storing only the lines makes regeneration cheap (one row + N lines per tavern) without burning storage on intermediate state.

---

## §7. Persistence and Regeneration

### 7.1 First generation

A `tavern_menus` row is created lazily the first time a tavern PoI is queried for its menu. Generation runs synchronously on the main thread; it is O(catalog_size) and completes in microseconds.

### 7.2 Monthly re-roll

On the `Economy.monthly_economy_tick` signal (`gdd-settlement-economy.md` §6), every existing `tavern_menus` row whose settlement participated in a market-price re-roll (the 10% drift triggered) is regenerated. The seed advances with the month index, so unchanged settlements still produce stable menus *for that month* but produce different menus next month.

Settlements that did NOT re-roll their market prices that month keep their existing menus untouched.

### 7.3 Schema migration

A single migration file — provisionally `db/migrations/NNN_tavern_menus.sql` (number assigned at implementation time) — creates the two tables in §2.1. Idempotent and non-destructive per `CLAUDE.md` §Architecture Patterns.

### 7.4 Cache invalidation

When a settlement's market class changes (rare; tied to urban_families crossing a threshold) or its dominant culture changes (very rare; conquest event), all tavern menus in that settlement regenerate on the next economy tick. The `settlement_market_class_changed(settlement_id)` signal from `gdd-settlement-economy.md` §detector wires here.

---

## §8. UI Consumer Contract

`gdd-settlement-exploration-ui.md` §"Tavern/Inn" PoI activities list "Buy Food/Drink." That activity is the only consumer.

### 8.1 Read API

```gdscript
# engine/services/tavern_menu_service.gd  (NOT an autoload)
class_name TavernMenuService
extends RefCounted

static func get_menu(poi_id: int) -> TavernMenu:
    # Returns the current menu, generating + persisting if absent.
```

### 8.2 UI panel

The Buy Food/Drink panel reads `get_menu(poi.id)` and renders two columns: drinks on the left, meals on the right, each with display name and price (formatted cp → sp/gp where appropriate). Price-display formatting is a shared UI helper, not this GDD's concern.

### 8.3 Purchase action

Buying a menu item:

1. Deducts `price_cp` from the active wallet (`gdd-party-inventory.md` §wallet-eligibility rules apply: settlement-wide).
2. Applies any consumption effect (most items: none. `traveler_ration`: adds 1 ration to character inventory. Future expansion: hot meals could provide a small recovery buff — flagged for Jedidiah's later decision.)
3. Logs the purchase in the unified log panel.

**The drunkenness / carousing-hijink interaction is NOT here.** Carousing is its own activity with its own resolver. Buying a single mug of ale is a transaction; carousing is a multi-hour activity with social and risk outcomes. They share the tavern PoI but not the resolver.

---

## §9. Tests

Per `CLAUDE.md` §Testing.

### 9.1 Unit tests (synthetic settlements)

- `test_generator_determinism.gd` — same seed → identical menu (line-by-line).
- `test_market_class_gating.gd` — Class VI menu excludes wine_imported, coffee, etc.
- `test_biome_gating.gd` — desert settlement does not surface palm_wine unless culture-tagged; sea-coast surfaces fish_fresh.
- `test_price_anchoring.gd` — `raw_factor=2.0` doubles all prices except water/milk.
- `test_flavor_multiplier.gd` — upscale common ale > common common ale > seedy common ale at identical economy.
- `test_quality_tier_distribution.gd` — over 10,000 generations at common flavor, ±5% of expected tier distribution.
- `test_bankers_rounding.gd` — price of 2.5 cp rounds to 2 cp; 3.5 rounds to 4 cp.

### 9.2 Integration tests

- `test_monthly_reroll.gd` — generate, advance one month, trigger drift signal, confirm menu changed for drifted settlements and is unchanged for non-drifted ones.
- `test_purchase_flow.gd` — wallet deduction integrates with `gdd-party-inventory.md`.
- `test_market_class_change.gd` — bumping urban_families to cross a class boundary triggers menu invalidation.

### 9.3 Sanity / authored-content tests

- Hand-author one tavern in the test hexmap (Aerendel-style). Assert its first generated menu against a snapshot. (This is the "we'd notice immediately if anything regressed visibly" gate.)

---

## §10. Action Vocabulary Registration

Per `CLAUDE.md` §Build Session Protocol step 11, the following entries should be added to the action-vocabulary definition file at implementation time:

| action_id | description |
|---|---|
| `buy_drink` | Purchase one menu line where `line_kind = 'drink'`. |
| `buy_meal` | Purchase one menu line where `line_kind = 'meal'`. |
| `inspect_menu` | UI-only; opens the Buy Food/Drink panel without purchasing. |

---

## §11. Open Questions for Jedidiah

These are items I need a decision on before implementation. Numbered to make sign-off responses concise.

1. **Q-MENU-1 — `TAVERN_MARKUP` value.** §4.4 currently has 1.5 as a placeholder. Should the §3 base prices be considered *wholesale* (markup applies) or *retail* (markup = 1.0)? My preference: retail (markup = 1.0); keep the constant in code for tunability.
2. **Q-MENU-2 — Quality-tier display.** Should "fine" and "swill" tiers be visible to the player in the menu UI (label suffixes like "Brindle Stout (Fine)") or invisible (the higher price tells the story)? My preference: invisible; price is signal enough.
3. **Q-MENU-3 — Recovery effects on hot meals.** §8.3 flags this. Should buying a meal in town heal 1 hp, restore an HD to short-rest, or do nothing? My preference: do nothing in v1; ration mechanics already exist and we don't want a second hp-recovery vector.
4. **Q-MENU-4 — Cultural tag → catalog gating.** §3 qualifiers reference "steppe-cultural" (kumiss). Is this a strict gate (only Telleskan steppes get kumiss) or a probabilistic weighting (more likely on steppe, possible elsewhere via trade)? My preference: strict gate, then let trade-route mechanic widen distribution implicitly via merchandise availability.
5. **Q-MENU-5 — Menu count for upscale at Class VI.** §6.2 says "n/a" because PoI gen shouldn't place upscale taverns in hamlets. Confirm the PoI generator can be trusted to enforce this and the menu generator does not need a defensive fallback. My current draft has a soft fallback (treat as common). OK to keep or remove?
6. **Q-MENU-6 — Catalog expansion.** Should the v1 catalog (§3) cover more regional specialties at draft, or should we ship with the current ~17 drink / ~11 meal list and expand as biomes/cultures get authored? My preference: ship narrow, expand by playtest.
7. **Q-MENU-7 — LLM narration hook.** Should the Buy Food/Drink panel emit a narration request to the LLM ("describe the publican sliding the mug over") on each purchase, or only on first visit per session? My preference: only on first visit and on a `gather_information` activity; per-purchase narration is too chatty.

---

## §12. Out-of-Scope / Future Work

- **Inns (lodging).** Lodging prices for overnight rests at inns belong to a separate "Lodging" GDD. They share the tavern/inn PoI but are mechanically distinct (rest type, time advance, cost-of-living interaction).
- **Specials / events.** A "tavern keeper offers a free meal to anyone who'll listen to a tale" hook is a quest-rumor item; lives in `gdd-quest-rumor-system.md`, not here.
- **Black-market items at seedy taverns.** Belongs to a hijink/fence subsystem, not the menu.
- **Cooking proficiency / homebrew brewing.** Out of scope.

---

## §13. Build Phase Hint

This work was not anchored to the legacy `docs/acks_arbiter_build_plan.md` (which user memory notes is deprecated). Suggested ordering at implementation time:

1. Stub `TavernMenu` / `TavernMenuLine` resource classes.
2. Static catalog resource (drinks + meals).
3. Generator (no economy wiring; uses `raw_factor = 1.0`).
4. Price computation + banker's rounding helper.
5. Economy wiring (consume `Economy.retail_factor`).
6. Flavor-name templates (one culture authored).
7. SQLite tables + persistence.
8. Monthly re-roll signal handler.
9. UI panel.
10. Tests at every step.

Estimated 2–3 build sessions if Jedidiah's §11 questions resolve cleanly.
