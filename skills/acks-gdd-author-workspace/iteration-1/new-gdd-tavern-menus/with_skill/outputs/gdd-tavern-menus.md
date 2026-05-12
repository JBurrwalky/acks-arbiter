# GDD: Tavern Menus

**Document type:** Game Design Document (project-designed, modifiable)
**Authority:** PROJECT-DESIGNED — ACKS 1e does not specify tavern menus or their pricing. The RAW equipment price list provides a foodstuffs/lodging anchor; the settlement economy procedure provides per-settlement demand modifiers and market-class adjustments. This GDD assembles those inputs into a procedural menu generator for tavern and inn PoIs.
**Status:** Draft
**Depends on ACKS rules:**
- `rules/acore_equipment.xml:257-273` (foodstuffs price anchors: ale/beer/wine/cheese/bread/meal/meat at fixed prices and price bands)
- `rules/acore_equipment.xml:275-283` (inn lodging tiers: slum/average/superb at 1sp / 5sp / 2gp — read as the quality-tier signal a tavern subtype should mirror)
- `rules/acore-campaign-hijinks.xml:710-735` (six-step market-price procedure: `4d4 + demand_modifier + class_size_adjust` × base × 0.1; the price formula this GDD adapts for menu items)
- `rules/acore-campaign-hijinks.xml:737-739` (10%/month cumulative re-roll trigger for market prices)
- `rules/acore-setting-construction-rules.xml:24-25` (definitions of `market_class` and `demand_modifier`)
- `rules/acore-setting-construction-rules.xml:199-215` (settlement-size → market-class mapping, Class I–VI)
- `rules/acore-setting-construction-rules.xml:221-367` (six-step demand-modifier generation procedure, including environmental, racial, domain-revenue, and trade-route adjustments)
- `rules/acore-setting-construction-rules.xml:297-353` (environmental adjustments to demand for `Beer, ale` and `Wine, spirits` rows — climate/terrain/age columns)
- `rules/acore-campaign-hijinks.xml:130-149` (Carousing hijink — Hear Noise throw at the tavern; menu prices feed the immersion layer that wraps this throw)
**Depends on project GDDs:**
- [`gdd-settlement-economy.md`](gdd-settlement-economy.md) — provides the per-settlement demand-modifier vector (especially `Beer, ale` and `Wine, spirits`), the `age_years` column, the market-price formula, and the merchandise registry this GDD reads.
- [`gdd-settlement-layout.md`](gdd-settlement-layout.md) §6.3 — defines the `tavern` and `inn` PoI types and their `subtype` ("common", "upscale", "seedy" / "wayfarer", "merchant") that this GDD reads as the quality-tier signal.
- [`gdd-settlement-exploration-ui.md`](gdd-settlement-exploration-ui.md) §6 (PoI activity panel) — the Buy Food/Drink activity panel that consumes the generated menu and renders it to the player.
- [`gdd-cultural-religious-generation.md`](gdd-cultural-religious-generation.md) — culture and religion files carry `dietary_restrictions` and provide the cultural-flavor hook for menu naming and item filtering.
- [`gdd-setting-lore.md`](gdd-setting-lore.md) and [`gdd-terrain-system.md`](gdd-terrain-system.md) — biome/climate/terrain context feeds environmental flavor of menu items (preserved fish at coast, mountain spirits at high elevation, etc.).
**Modifiable by Claude Code:** Yes — all template tables, item catalogs, weighted selection logic, naming patterns, and menu-size formulas are engineering decisions. The RAW citations in §2 are not modifiable; the price formula in §4.3 is a faithful adaptation of the RAW market-price procedure and may not be silently restructured (any change to the formula must be flagged and approved).
**Last updated:** 2026-05-12

---

## 1. Purpose

Procedurally generate a per-tavern (and per-inn) menu of available drinks and meals with priced offerings, such that menus feel:

- **Economically grounded.** Item prices respond to settlement market class, regional demand modifiers, and settlement age in the same way the broader market-price procedure responds — a frontier hamlet's ale costs more relative to a metropolis's, and a coastal town's wine is cheaper than a desert outpost's.
- **Culturally distinct.** A Keshite tavern in a steppe village serves different items, under different names, than a Valonian inn in a coastal city — even when the underlying mechanical categories (cheap ale, good wine, meat dish) are identical.
- **Subtype-differentiated.** A `seedy` tavern offers a narrower, cheaper menu than an `upscale` tavern in the same settlement; a `merchant` inn skews toward portable provisions while a `wayfarer` inn skews toward hot meals.
- **Deterministic and re-openable.** Re-entering the same tavern on the same in-game day yields the same menu and prices. Prices drift on a monthly tick that mirrors the settlement-economy 10% re-roll trigger.

Menus exist to thicken the player-facing fiction of the settlement layer (the Carousing hijink and the Buy Food/Drink activity both surface menu items) and to give the LLM narration layer concrete economic anchors when generating tavern scenes. Mechanically, menu items are a thin wrapper around the existing settlement-economy substrate; this GDD does not introduce a new pricing system, it adapts the existing one.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Foodstuff anchor prices** (`rules/acore_equipment.xml:257-273`): Ale/beer cheap = 3 pints / 1cp; ale/beer good = 1 pint / 2cp; wine cheap = 1 pint / 2cp; wine good = 1 pint / 1sp; wine rare = 1 pint / 5sp; meal (1 person, poor to feast) = 1cp–10gp band; bread = 1sp (per loaf, weight varies by quality); cheese = 5cp/lb; meat = 1sp/lb; eggs = 5cp/dozen; spices (cinnamon/pepper/etc.) = 3gp/lb; saffron = 15gp/lb; dried fruit = 1sp/lb.
- **Inn lodging tiers** (`rules/acore_equipment.xml:275-283`): slum = 1sp/night; average = 5sp/night; superb = 2gp/night. These are PROJECT-INTERPRETED in this GDD as the quality-tier signal a tavern's `subtype` should mirror — the menu generator does not modify these lodging prices, only mirrors their tier structure for non-lodging items.
- **Market price formula** (`rules/acore-campaign-hijinks.xml:710-735`): "Roll 4d4. Add the demand modifier for that merchandise in that market, if any. Add 1 if the market is Class I or II. Subtract 1 if the market is Class V or VI. … Multiply the final result by 10 and apply that percentage to the base price." This GDD adapts this formula for menu items in §4.3.
- **Monthly price drift** (`rules/acore-campaign-hijinks.xml:737-739`): "If adventurers remain in the same market waiting for prices to change, each month there is a cumulative 10% chance that each merchandise type's price changes and is re-rolled." This GDD adopts the same trigger for menu items.
- **Banker's rounding** (project convention, `CLAUDE.md`): All rounding in menu price computation is round-half-to-even. Coin-denomination conversion (e.g., 2.5cp → 2cp or 3cp) follows banker's rounding before display.
- **Demand-modifier inputs** (`rules/acore-setting-construction-rules.xml:227-234`): per-settlement demand modifiers for `Beer, ale` and `Wine, spirits` are generated by the six-step procedure in [`gdd-settlement-economy.md`](gdd-settlement-economy.md). This GDD READS those modifiers; it does not regenerate them.
- **Market class is the same column used for price-tier adjust** (`rules/acore-setting-construction-rules.xml:199-215`): Class I/II = +1; Class III/IV = 0; Class V/VI = -1. No new market-class taxonomy is introduced here.
- **Carousing hijink does not specify a menu** (`rules/acore-campaign-hijinks.xml:130-149`): Carousing requires only the Hear Noise throw and the perpetrator's location. The menu is project-designed flavor that sits beside the throw, not a mechanical prerequisite. The throw resolution is unchanged by this GDD.

---

## 3. Project Decisions

### 3.1 Where menus live in the data model

A tavern menu is **not** persisted as a static table. It is computed on demand from:

1. The tavern PoI record (type, subtype, district_id) per [`gdd-settlement-layout.md`](gdd-settlement-layout.md) §6.2.
2. The settlement economy state (market_class, age_years, demand_modifier vector for `Beer, ale` and `Wine, spirits`, monthly drift state) per [`gdd-settlement-economy.md`](gdd-settlement-economy.md).
3. The dominant culture's culture file (food_staples list, beverage_list, cuisine_register; see §3.4 for the schema additions).
4. The biome / climate / terrain context of the settlement's hex (for environmental flavor in §4.4).
5. A deterministic per-tavern seed: `seed = hash(settlement_id, poi_id, calendar_month_index)`.

The composition `(poi_id, calendar_month_index)` is the cache key. Re-entering a tavern within the same calendar month yields the same menu and prices; a new month re-rolls per §4.5.

### 3.2 Menu shape

A generated menu is a structured object:

```json
{
  "poi_id": "ashford_tavern",
  "settlement_id": "ashford_village",
  "month_index": 14823,
  "quality_tier": "common",
  "drinks": [
    {
      "item_id": "ale_cheap",
      "display_name": "Steppe-cut ale",
      "category": "ale",
      "quality": "cheap",
      "unit": "3 pints",
      "base_price_cp": 1,
      "market_price_cp": 1,
      "cultural_label": "Common in the village; brewed by the Ashford miller's wife.",
      "available": true
    },
    {
      "item_id": "wine_good",
      "display_name": "Imported grape wine",
      "category": "wine",
      "quality": "good",
      "unit": "1 pint",
      "base_price_cp": 10,
      "market_price_cp": 13,
      "cultural_label": "Brought up from the coastal trade route.",
      "available": true
    }
  ],
  "meals": [
    {
      "item_id": "meal_humble",
      "display_name": "Black bread, hard cheese, onion",
      "category": "meal",
      "quality": "humble",
      "unit": "1 person",
      "base_price_cp": 3,
      "market_price_cp": 3,
      "components": ["bread_coarse", "cheese", "vegetable"],
      "available": true
    }
  ],
  "specials": [ /* see §4.6 */ ]
}
```

Display strings are LLM-templatable; the structured fields are mechanically authoritative.

### 3.3 Quality tiers

Three tiers, mapped from PoI subtype:

| PoI type | Subtype | Quality tier | Drink quality bands available | Meal price band |
|---|---|---|---|---|
| `tavern` | `seedy` | low | cheap ale, cheap wine (sometimes only one); never rare | 1cp–1sp |
| `tavern` | `common` | mid | cheap ale, good ale, cheap wine, good wine; rare wine 10% chance Class III+ | 1cp–5sp |
| `tavern` | `upscale` | high | good ale, good wine, rare wine (Class IV+ only); cheap categories suppressed | 5sp–10gp |
| `inn` | `wayfarer` | mid (food-first) | cheap ale, good ale, cheap wine; meal slate emphasized | 1cp–1sp |
| `inn` | `merchant` | mid-high (provision-first) | good ale, good wine; portable provisions added (§4.7) | 5cp–1gp |

The tier sets the price band and the available-quality filter; it does not directly multiply prices (the market formula does that in §4.3).

### 3.4 Schema additions to culture files

The culture schema in [`gdd-cultural-religious-generation.md`](gdd-cultural-religious-generation.md) §2 is extended with one optional block (proposed for inclusion in that GDD; this GDD flags the dependency):

```json
{
  "food_and_drink": {
    "staple_grain": "string — enum: 'wheat', 'rye', 'barley', 'rice', 'maize', 'millet', 'oats', 'spelt'",
    "preferred_beverage": "string — enum: 'beer', 'ale', 'wine', 'mead', 'kumis', 'cider', 'spirits', 'tea', 'kava'",
    "secondary_beverage": "string — same enum or null",
    "common_protein": "string — enum: 'beef', 'mutton', 'pork', 'goat', 'fish', 'fowl', 'game', 'legumes', 'horse', 'reindeer'",
    "signature_spices": ["string — up to 3 entries from a curated 30-spice list"],
    "cuisine_register": "string — enum: 'rustic', 'spiced', 'preserved', 'fresh', 'fermented', 'smoked', 'sweet', 'austere'",
    "dietary_restrictions_food": "string or null — max 80 chars, e.g. 'no pork', 'no shellfish', 'no meat on holy days'"
  }
}
```

If a culture file lacks `food_and_drink`, the generator falls back to a terrain-derived default (§4.4 default-by-biome table). The block is OPTIONAL on the culture file but REQUIRED for high-fidelity menu output.

**Architectural concern:** This block belongs in `gdd-cultural-religious-generation.md`'s schema, not in this GDD. Recommend amending that GDD in a follow-up session. See §6.

### 3.5 What this GDD does NOT cover

- **Tavern NPC generation** — staff, patrons, brawl-trigger NPCs are the settlement stocking GDD's job (`gdd-settlement-stocking.md`).
- **Carousing throw resolution** — the Hear Noise throw, the failure-by-14-or-1 capture, and the rumor delivery are the Carousing hijink resolver's job (RAW citation `rules/acore-campaign-hijinks.xml:130-149`); this GDD does not touch them.
- **Inn lodging prices** — fixed by RAW per §2 above. The lodging line item is a static read of `acore_equipment.xml:275-283`, not a menu generation.
- **Procedural recipes** — items are categorized by `category` + `quality`; the prose description of what's actually served is LLM narration territory and not mechanically tracked.

---

## 4. Generation Pipeline

```
1. RESOLVE INPUTS → load PoI record, settlement economy state, culture file, biome.
2. SELECT QUALITY TIER → derive from PoI subtype (§3.3 mapping).
3. SELECT ITEM CATEGORIES → pick which drink and meal categories appear, biased by tier, market class, and culture.
4. PRICE EACH ITEM → adapt the RAW market-price formula to each item's base price.
5. APPLY CULTURAL OVERLAY → rename items, attach cultural_label, filter by dietary_restrictions.
6. EMIT MENU OBJECT → return the structured object in §3.2.
```

### 4.1 Step 1 — Resolve inputs

Pure data load. Required inputs:

- `poi: { id, type, subtype, district_id }` from `settlement_pois` table (see [`gdd-settlement-layout.md`](gdd-settlement-layout.md)).
- `settlement: { id, market_class, age_years, biome, biome_subtype, culture_id }` from `settlement_entrances` table.
- `economy: { demand_modifiers: { "Beer, ale": int, "Wine, spirits": int, "Grain, vegetables": int, "Meats, preserved": int, ... } }` from the per-settlement demand-modifier vector ([`gdd-settlement-economy.md`](gdd-settlement-economy.md) §3).
- `culture: { food_and_drink: {...} | null }` from the culture file (§3.4).
- `month_index: int` from `Timekeeping` (project calendar; 13 months/year per [`gdd-settlement-economy.md`](gdd-settlement-economy.md) §0.5).

If `culture.food_and_drink` is null, populate a default block from biome via the §4.4 default-by-biome table.

### 4.2 Step 2 — Select quality tier

Table lookup against `(poi.type, poi.subtype)` per §3.3. Returns the tier label and the allowed quality bands.

If a PoI's subtype is missing or unrecognized (defensive case), default to:

- `tavern` → `common`
- `inn` → `wayfarer`

### 4.3 Step 3 — Item categories and Step 4 — Pricing (combined)

#### 4.3.1 Drink slate

Drink slate size by market class:

| Market class | Drinks on the menu |
|---|---|
| Class VI | 1d2+1 (range 2–3) |
| Class V | 1d3+1 (range 2–4) |
| Class IV | 1d4+2 (range 3–6) |
| Class III | 1d4+3 (range 4–7) |
| Class II | 1d6+3 (range 4–9) |
| Class I | 1d6+4 (range 5–10) |

For each slot, draw without replacement from the drink catalog (§4.3.3), filtered by tier (§3.3) and culture (§4.4).

#### 4.3.2 Meal slate

Meal slate size is roughly half the drink slate, rounded with banker's rounding:

| Market class | Meals on the menu |
|---|---|
| Class VI | 1 |
| Class V | 1d2 (range 1–2) |
| Class IV | 1d3 (range 1–3) |
| Class III | 1d3+1 (range 2–4) |
| Class II | 1d4+1 (range 2–5) |
| Class I | 1d4+2 (range 3–6) |

#### 4.3.3 Drink catalog

| item_id | Category | Quality | Unit | Base price (cp) | RAW anchor |
|---|---|---|---|---:|---|
| `ale_cheap` | ale | cheap | 3 pints | 1 | `acore_equipment.xml:258` |
| `ale_good` | ale | good | 1 pint | 2 | `acore_equipment.xml:259` |
| `wine_cheap` | wine | cheap | 1 pint | 2 | `acore_equipment.xml:271` |
| `wine_good` | wine | good | 1 pint | 10 | `acore_equipment.xml:272` |
| `wine_rare` | wine | rare | 1 pint | 50 | `acore_equipment.xml:273` |
| `spirits_local` | spirits | cheap | 1 dram (¼ pint) | 3 | derived from wine cheap × 1.5 (project-design, no direct RAW anchor) |
| `spirits_imported` | spirits | good | 1 dram | 12 | derived from wine good × 1.2 (project-design) |
| `cider` | cider | cheap | 1 pint | 2 | derived from wine cheap (project-design) |
| `mead` | mead | good | 1 pint | 8 | derived from wine good × 0.8 (project-design) |

Items below `spirits_local` are project-designed extensions with no direct RAW anchor; they are flagged in the catalog with `derived: true`. They appear only when the culture's `preferred_beverage` or `secondary_beverage` selects them.

**Project-design note:** The five RAW items (cheap/good ale, cheap/good/rare wine) cover the mechanical range. The four derived items exist solely for cultural variety. If Jedidiah prefers no project-design extensions, drop the bottom four rows and rely purely on cultural relabeling of the RAW items.

#### 4.3.4 Meal catalog

Meals are categorized by `quality` band, with components driving the base price:

| item_id | Quality | Base price (cp) | Components | RAW anchor |
|---|---|---:|---|---|
| `meal_pauper` | poor | 1 | bread_coarse | `acore_equipment.xml:266` (1cp end of band) |
| `meal_humble` | humble | 3 | bread_wheat (5cp prorated), cheese (5cp/lb @ small portion) | derived from `acore_equipment.xml:260-263` |
| `meal_common` | common | 10 (1sp) | bread + meat (1sp/lb @ ⅓ lb), small ale | derived from `acore_equipment.xml:264, 270` |
| `meal_hearty` | hearty | 30 (3sp) | bread + meat + cheese + vegetable | derived |
| `meal_fine` | fine | 100 (1gp) | spiced meat, fresh bread, wine measure | derived; spices anchor `acore_equipment.xml:265` |
| `meal_feast` | feast | 1000 (10gp) | multi-course, rare spices, rare wine | `acore_equipment.xml:266` (10gp end of band) |

Meal quality bands are filtered by quality tier (§3.3). A `seedy` tavern offers only `meal_pauper` and `meal_humble`. An `upscale` tavern offers `meal_common` through `meal_feast`. A `common` tavern offers `meal_humble` through `meal_hearty`.

#### 4.3.5 Pricing formula

For each selected item, the market price is computed by the RAW-adapted formula:

```
market_price = base_price × (4d4 + DM + class_adjust + tier_adjust + judge_adjust) × 0.1
```

Where:

- **base_price** is the catalog base price in copper.
- **4d4** is rolled per item per tavern per month with the deterministic seed `(poi_id, item_id, month_index)`. The 4d4 distribution (range 4–16, mean 10) ensures that the typical case yields exactly base_price × 1.0 (10 × 0.1).
- **DM (demand modifier)** is the per-settlement demand modifier from `economy.demand_modifiers`:
  - For ale/beer items: `economy.demand_modifiers["Beer, ale"]`.
  - For wine/spirits/cider/mead items: `economy.demand_modifiers["Wine, spirits"]`.
  - For meals containing meat: average of `"Meats, preserved"` and `"Grain, vegetables"` (banker's rounding).
  - For meals containing only bread/cheese/vegetable: `"Grain, vegetables"`.
- **class_adjust** is +1 for Class I/II, 0 for Class III/IV, -1 for Class V/VI. Note that this is the OPPOSITE direction in feel from a player's expectation (big cities have HIGHER market multipliers because demand is broader); this matches RAW exactly per `rules/acore-campaign-hijinks.xml:717-718`. Cheaper items in small towns is a SIDE EFFECT of small towns having FEWER drink categories and lower-tier quality bands, not of price-per-item.
- **tier_adjust** is the PROJECT-DESIGNED adjust for tavern quality tier:
  - `seedy` / low tier → -1
  - `common` / mid tier → 0
  - `upscale` / high tier → +1
  - `wayfarer` / `merchant` inn → 0
  This is the only project-designed addition to the RAW formula. **Architectural concern:** flagged in §6.
- **judge_adjust** is reserved for war/calamity events (currently 0; future GDDs may set it).

After the multiplication, the result is rounded with banker's rounding to the nearest copper. If the result is ≥ 10cp, display in silver; if ≥ 100cp, display in gold (preserve copper precision in storage).

**Worked example (Ashford Village, Class VI, 500-year settlement, plains, no trade route):**

- DM for `Beer, ale` in plains/grasslands/age-101-1000 = +1 (from environmental table) + 0 base roll (assume) = +1.
- class_adjust = -1 (Class VI).
- For `ale_cheap` at base 1cp in `common` tavern:
  - market_price = 1 × (4d4 mean 10 + 1 + (-1) + 0) × 0.1 = 1 × 10 × 0.1 = 1cp.
- For `wine_good` at base 10cp:
  - market_price = 10 × (10 + 1 + (-1) + 0) × 0.1 = 10 × 10 × 0.1 = 10cp (1sp).
- For `wine_rare` at base 50cp in same tavern: would be 50cp (5sp) — but `wine_rare` is filtered out by the `common` tier band, so it does not appear on the menu.

**Worked example (Cyfaraun, Class III, coastal, age-101-1000, upscale tavern):**

- DM for `Wine, spirits` coast/age-101-1000 base = 0 environmental + +1 demand base = +1 (illustrative).
- class_adjust = 0 (Class III).
- tier_adjust = +1 (upscale).
- For `wine_good` at base 10cp: market_price = 10 × (10 + 1 + 0 + 1) × 0.1 = 10 × 12 × 0.1 = 12cp.
- For `wine_rare` at base 50cp: market_price = 50 × 12 × 0.1 = 60cp (6sp).

### 4.4 Step 5 — Cultural overlay

After items are selected and priced, the cultural overlay renames items and may filter them by dietary restriction.

#### 4.4.1 Renaming

The display_name field is generated from a small template that consumes:

- `culture.food_and_drink.staple_grain` (renames "bread" → "rye loaf", "barley flatbread", "wheat trencher", etc.).
- `culture.food_and_drink.preferred_beverage` (signals which beverage category gets the "named local variant" — Keshite `kumis` if `preferred_beverage == "kumis"` even though the mechanical item is `spirits_local`).
- `culture.food_and_drink.signature_spices` (for `meal_fine` and `meal_feast` items, the spice list contributes to the display_name).
- `culture.food_and_drink.cuisine_register` (rustic / spiced / preserved / fresh / fermented / smoked / sweet / austere — modifies adjective choice).

Concrete renaming examples:

| Mechanical item | Culture | display_name |
|---|---|---|
| `ale_cheap` | Valonian (wheat / ale / rustic) | "Common Valonian ale" |
| `ale_cheap` | Keshite (millet / kumis / fermented) | "Sour millet beer" |
| `spirits_local` | Keshite | "Steppe kumis" (categorically distinct; explicit mapping) |
| `meal_hearty` | Valonian | "Roast mutton with onions, wheat trencher" |
| `meal_hearty` | Keshite (mutton, spiced register, cumin/coriander/sumac) | "Spiced mutton with sumac, flatbread" |

The display_name is the only field affected; `item_id`, `category`, `quality`, `base_price_cp`, and `market_price_cp` remain mechanically identical.

#### 4.4.2 Dietary filter

If `culture.food_and_drink.dietary_restrictions_food` or `religion.practices.dietary_restrictions` contains a substring that matches an item's components list (e.g., `"no pork"` filters `meal_hearty` when its meat is pork), the item is excluded from the menu. If the filter empties a slate (e.g., all meal slots collapse), the generator re-rolls the empty slate without the filtered component before bailing to a fallback `meal_humble`-only option.

#### 4.4.3 Default-by-biome fallback (when `culture.food_and_drink` is null)

| Biome (`gdd-terrain-system.md`) | staple_grain | preferred_beverage | common_protein | cuisine_register |
|---|---|---|---|---|
| `plains` / `grasslands` | wheat | ale | beef | rustic |
| `steppe` | millet | kumis | mutton | fermented |
| `forest_deciduous` / `taiga` | rye | mead | game | smoked |
| `mountains` / `hills` | barley | cider | goat | rustic |
| `coast` / `sea_coast` | wheat | wine | fish | preserved |
| `river_valley` | wheat | wine | fish | fresh |
| `desert` | millet | tea | goat | spiced |
| `jungle` / `rainforest` | rice | spirits | fowl | spiced |
| `swamp` | rice | cider | fish | preserved |
| `tundra` | oats | spirits | reindeer | smoked |
| `island` | wheat | wine | fish | fresh |

Used only as a fallback. When a culture file exists, the culture file wins.

### 4.5 Step 6 — Monthly drift

Per RAW `rules/acore-campaign-hijinks.xml:737-739`, prices in a held market have a cumulative 10% chance per month of being re-rolled. The menu generator implements this by:

1. Storing the menu generation's `month_index` in the cache.
2. On each settlement-month tick, for each cached menu, rolling 1d100 with seed `(poi_id, month_index)`. On result ≤ 10 × months_since_generation (cumulative), the cached menu is invalidated and the next entry triggers a full re-generation with the new month's seed.
3. Demand-modifier drift propagates automatically — the settlement-economy substrate already drifts DMs on a similar schedule, and the price formula reads the current DM at generation time.

The cache key remains `(poi_id, calendar_month_index)`. A player re-entering the same tavern in the same month sees the same menu; entering in a later month MAY see new prices if the drift triggered.

### 4.6 Specials

Each menu has a 1d3-1 chance (range 0–2) of including one "special" — a non-catalog item that overrides the standard slate:

- A `meal_feast`-tier item in an `upscale` tavern: 25% chance.
- A festival-day item if the calendar month contains a religious holy day for the dominant religion: 100% chance.
- A "stranger's tab" item flagged with `cost_in_kind: "story"` — represents the offer Carousing characters get for a rumor in lieu of payment. 5% chance in any tavern.

Specials are project-designed flavor and have no RAW anchor.

### 4.7 Provision slate (inns only, `merchant` subtype)

`merchant` inn subtype adds a small portable-provisions slate:

| item_id | Base price (cp) | Unit | RAW anchor |
|---|---:|---|---|
| `bread_coarse_loaf` | 10 (1sp) | 12 lb | `acore_equipment.xml:262` |
| `cheese_wedge` | 5 | 1 lb | `acore_equipment.xml:263` |
| `meat_dried` | 10 (1sp) | 1 lb | `acore_equipment.xml:268` |
| `dried_fruit_pack` | 10 (1sp) | 1 lb | `acore_equipment.xml:267` |
| `wine_skin` | 100 (1gp) | 1 gallon | derived from `acore_equipment.xml:272` × 8 |

These are priced via the same formula in §4.3.5 with the `Grain, vegetables` demand modifier (for non-meat items) or `Meats, preserved` (for `meat_dried`).

---

## 5. Data Model

### 5.1 Persistent state

The generator stores cached menus in a single table:

```sql
CREATE TABLE tavern_menus (
  poi_id TEXT NOT NULL,
  month_index INTEGER NOT NULL,
  menu_json TEXT NOT NULL,        -- the structured object from §3.2
  generated_at_tick INTEGER NOT NULL,
  invalidated INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (poi_id, month_index)
);
```

The `menu_json` field is the serialized §3.2 object. Cache invalidation per §4.5 sets `invalidated = 1`; the next menu request regenerates and inserts a new row with the current `month_index`. Old rows are kept for history/save-state replay; a separate housekeeping job (out of scope) can prune rows older than 12 months.

### 5.2 Read path

```gdscript
# Pseudocode
func get_tavern_menu(poi_id: String) -> Dictionary:
    var month := Timekeeping.current_month_index()
    var cached := DB.query_with_bindings(
        "SELECT menu_json, invalidated FROM tavern_menus WHERE poi_id = ? AND month_index = ?",
        [poi_id, month])
    if cached and cached.size() > 0 and not cached[0].invalidated:
        return JSON.parse_string(cached[0].menu_json)
    var menu := generate_menu(poi_id, month)
    DB.query_with_bindings(
        "INSERT OR REPLACE INTO tavern_menus (poi_id, month_index, menu_json, generated_at_tick) VALUES (?, ?, ?, ?)",
        [poi_id, month, JSON.stringify(menu), Timekeeping.current_tick()])
    return menu
```

The `DB` autoload wraps godot-sqlite; `query_with_bindings` is the parameterized form per `CLAUDE.md`.

### 5.3 Read dependencies

The generator reads from (it does NOT write to):

- `settlement_pois` (PoI record).
- `settlement_entrances` (settlement state, age, biome).
- `settlement_demand_modifiers` (per [`gdd-settlement-economy.md`](gdd-settlement-economy.md) §3 schema).
- The culture file JSON registry (loaded at session start by `CampaignRepository`).
- The religion file JSON registry (for dietary restrictions overlay).

---

## 6. Open Questions / Architectural Concerns

- **Tier-adjust is a project-designed extension to the RAW formula.** §4.3.5 introduces `tier_adjust ∈ {-1, 0, +1}` keyed off PoI subtype. RAW does not contain this term. The alternative is to make the tier_adjust 0 and rely purely on slate filtering (a `seedy` tavern offers cheap quality only, so its meal prices are anchored to cheap base prices). Either approach is defensible; the current draft uses tier_adjust because it produces a more visible price spread between `seedy` and `upscale` taverns in the same settlement, which is the player-visible effect the system is for. Confirm with Jedidiah.

- **`food_and_drink` block in culture files belongs in `gdd-cultural-religious-generation.md`, not here.** §3.4 of this GDD proposes a schema addition to the culture file. The clean refactor is to amend `gdd-cultural-religious-generation.md` to include the block, then drop §3.4 from this GDD and reference the parent instead. Recommend amending the cultural GDD in a follow-up session; in the interim, this GDD treats the block as a project-design proposal it depends on.

- **Overlap with `gdd-settlement-economy.md` on the pricing formula.** Both that GDD and §4.3.5 here adapt the RAW market-price formula. They are not in conflict — settlement-economy applies the formula to merchandise loads (large-scale trade); this GDD applies it to single-serving menu items (retail flavor). However, future readers may wonder why the formula is restated. Recommend a one-line cross-reference comment in the menu generator code pointing at the settlement-economy module's implementation of the same formula. **Do not duplicate the implementation** — the menu generator should call into the settlement-economy pricing function, not re-implement the 4d4 roll.

- **Derived drink categories without RAW anchor.** §4.3.3 includes `spirits_local`, `spirits_imported`, `cider`, and `mead`. These are project-designed. The conservative version of this GDD drops them and relies purely on cultural relabeling of RAW items (a Keshite `ale_cheap` is "sour millet beer" but is mechanically still `ale_cheap`). Pick a position.

- **Banker's rounding in the price formula.** §2 commits to banker's rounding for the final copper result. The intermediate 4d4 + DM + class_adjust + tier_adjust math is integer, so no rounding happens until the × 0.1 step. Banker's rounding at that step is correct per project convention.

- **Drift implementation needs settlement-economy hookup.** §4.5 says "the settlement-economy substrate already drifts DMs." Verify against `gdd-settlement-economy.md` §monthly_drift (or equivalent) that DMs are in fact drifted on the project's settlement-month tick. If not, this GDD's drift is decoupled and will read stale DMs.

- **Religion-derived dietary restrictions overlap with culture-derived restrictions.** §4.4.2 reads from both `culture.food_and_drink.dietary_restrictions_food` and `religion.practices.dietary_restrictions`. If a settlement has a dominant culture AND a dominant religion with conflicting rules (e.g., culture says "pork is staple," religion says "no pork"), the religion wins by default in the current draft. Confirm.

- **No tavern menu for `npc_residence`, `shrine`, `market`, or other PoI types.** Out of scope by design — the activity panel for Buy Food/Drink is only offered by `tavern` and `inn` per [`gdd-settlement-layout.md`](gdd-settlement-layout.md) §6.3. Mention here so future readers don't accidentally extend this generator to all PoI types.

- **No mechanical effect of consuming menu items.** A cheap ale costs 1cp and that's the entire mechanical interaction; the menu does not trigger drunkenness, poison, charm, or stat changes. If Jedidiah wants drunkenness or hangover mechanics tied to consumption count, that is a separate GDD (probably under `gdd-condition-effects.md` if such a file existed).
