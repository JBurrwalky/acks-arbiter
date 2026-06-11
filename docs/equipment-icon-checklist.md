# Equipment Icon Checklist

Asset-generation checklist for inventory / paper-doll item icons. Covers **every
non-magic item** in the runtime catalog (`base_equipment.json` + `transport.json`
+ foodstuffs from `provisions_services.json`) — **178 items**. Magic items
(`data/treasure/magic_item_catalog.json`, ~153) are deferred: a single shared
placeholder now, a dedicated pass later (see §XII).

## How to use this (three icon tiers)

The outline is nested so you can generate at whatever granularity you want and
fill in detail later:

- **`#` Type** — one icon could stand in for the whole category (cheapest).
- **`##` Subgroup** — one icon per visual family (good middle ground; the cs_tab
  paper-doll falls back to these).
- **`- [ ]` Item** — a unique icon per catalog item (the end goal).

**File-naming:** save each as `res://assets/icons/items/<item_key>.png`
(the `item_key` is in `code font` after each item). Subgroup/type fallbacks:
`res://assets/icons/types/<slug>.png`. Square, ~64×64, transparent background.
The code resolves per-item → subgroup/type → empty-slot placeholder, so partial
coverage degrades gracefully.

---

# I. Weapons (29)

## A. Swords & Daggers
- [ ] Sword — `sword`
- [ ] Short Sword — `short_sword`
- [ ] Two-Handed Sword — `two_handed_sword`
- [ ] Dagger — `dagger`
- [ ] Silver Dagger — `silver_dagger`

## B. Axes
- [ ] Battle Axe — `battle_axe`
- [ ] Hand Axe — `hand_axe`
- [ ] Great Axe — `great_axe`

## C. Hafted & Blunt
- [ ] Club — `club`
- [ ] Mace — `mace`
- [ ] War Hammer — `warhammer`
- [ ] Morning Star — `morning_star`
- [ ] Flail — `flail`
- [ ] Quarterstaff — `quarterstaff`
- [ ] Sap — `sap`

## D. Polearms & Spears
- [ ] Spear — `spear`
- [ ] Javelin — `javelin`
- [ ] Pole Arm — `pole_arm`
- [ ] Lance — `lance`

## E. Bows
- [ ] Shortbow — `shortbow`
- [ ] Longbow — `longbow`
- [ ] Composite Bow — `composite_bow`

## F. Crossbows
- [ ] Crossbow — `crossbow`
- [ ] Arbalest — `arbalest`

## G. Slings, Thrown & Flexible
- [ ] Sling — `sling`
- [ ] Bola — `bola`
- [ ] Net — `net`
- [ ] Whip — `whip`

## H. Improvised
- [ ] Crowbar — `crowbar`  *(catalogued as a weapon)*

# II. Ammunition (6)

## A. Arrows
- [ ] Arrows (20) — `arrows_20`
- [ ] Silver-Tipped Arrow — `silver_arrow`

## B. Bolts
- [ ] Bolts (20) — `bolts_20`

## C. Sling Ammo
- [ ] Sling Bullets (30) — `sling_bullets_30`
- [ ] Sling Stones (20) — `sling_stones_20`

## D. Darts
- [ ] Dart (5) — `dart`

# III. Armor (8)

## A. Light Armor
- [ ] Hide/Fur Armor — `hide_armor`
- [ ] Leather Armor — `leather_armor`

## B. Mail Armor
- [ ] Scale Mail — `ring_mail`
- [ ] Chain Mail — `chain_mail`
- [ ] Banded Armor — `banded_armor`

## C. Plate Armor
- [ ] Plate Armor — `plate_armor`

## D. Helmets
- [ ] Light Helmet — `light_helmet`
- [ ] Heavy Helmet — `heavy_helmet`

# IV. Shields (1)

## A. Shield
- [ ] Shield — `shield`

# V. Clothing (32)

## A. Torso Garments
- [ ] Tunic and Pants (serf) — `tunic_serf`
- [ ] Tunic and Pants (crafter/freeholder) — `tunic_crafter`
- [ ] Tunic and Pants (armiger) — `tunic_armiger`
- [ ] Tunic and Pants (noble) — `tunic_noble`
- [ ] Robe (cleric/mage) — `robe`
- [ ] Cassock (cleric/mage) — `cassock`
- [ ] Chiton (wool/linen) — `chiton_wool`
- [ ] Chiton (silk) — `chiton_silk`
- [ ] Dress (crafter/freeholder) — `dress_crafter`
- [ ] Dress (armiger) — `dress_armiger`
- [ ] Gown (lady-in-waiting/noble) — `gown_noble`
- [ ] Gown (duchess) — `gown_duchess`
- [ ] Breastwrap (wool/linen) — `breastwrap_wool`
- [ ] Breastwrap (silk) — `breastwrap_silk`

## B. Headwear
- [ ] Hat (armiger) — `hat_armiger`
- [ ] Skullcap (metal) — `skullcap_metal`
- [ ] Veil (silk) — `veil_silk`

## C. Cloaks
- [ ] Cloak (long, hooded) — `cloak_hooded`
- [ ] Cloak (fur-lined, winter) — `cloak_fur`
- [ ] Cloak (leather, hooded) — `cloak_leather`
- [ ] Cloak (silk, hooded) — `cloak_silk`
- [ ] Cloak (embroidered, hooded) — `cloak_embroidered`

## D. Footwear
- [ ] Boots (leather, low) — `boots_low`
- [ ] Boots (leather, high) — `boots_high`
- [ ] Sandals/Shoes (leather) — `sandals`
- [ ] Sandals (high) — `sandals_high`

## E. Handwear
- [ ] Gloves — `gloves`
- [ ] Gloves (long, leather) — `gloves_long`

## F. Belts & Sashes
- [ ] Belt/Sash (leather) — `belt_leather`
- [ ] Belt/Sash (embossed leather) — `belt_embossed`
- [ ] Belt/Sash (silk) — `belt_silk`

## G. Legwear
- [ ] Loincloth — `loincloth`

# VI. Textiles & Raw Materials (5)

## A. Cloth by the Yard
- [ ] Linen (cheap, 1 yard) — `linen_cheap`
- [ ] Linen (fine, 1 yard) — `linen_fine`
- [ ] Wool (cheap, 1 yard) — `wool_cheap`
- [ ] Wool (fine, 1 yard) — `wool_fine`
- [ ] Silk (1 yard) — `silk_yard`

# VII. Gear & Adventuring Equipment (50)

## A. Containers
- [ ] Backpack — `backpack`
- [ ] Sack (large) — `sack_large`
- [ ] Sack (small) — `sack_small`
- [ ] Pouch/Purse — `pouch`
- [ ] Barrel (20 gallon) — `barrel`
- [ ] Chest (ironbound) — `chest_ironbound`

## B. Light & Fire
- [ ] Torch — `torch`
- [ ] Lantern — `lantern`
- [ ] Candle, Tallow — `candle_tallow`
- [ ] Candle, Wax — `candle_wax`
- [ ] Tinderbox (flint and steel) — `tinderbox`
- [ ] Oil Flask, Common — `oil_flask_common`
- [ ] Oil Flask, Military — `oil_flask_military`

## C. Climbing & Exploration
- [ ] Rope (50') — `rope_50ft`
- [ ] Grappling Hook — `grappling_hook`
- [ ] Iron Spikes (12) — `iron_spikes_12`
- [ ] Pole, Wooden (10') — `pole_wooden_10ft`
- [ ] Mallet — `mallet`

## D. Tools
- [ ] Craftsman's Tools — `craftsmans_tools`
- [ ] Machinist's Tools — `machinists_tools`
- [ ] Thieves' Tools — `thieves_tools`
- [ ] Hammer (small) — `hammer_small`
- [ ] Lock — `lock`
- [ ] Manacles — `manacles`
- [ ] Mirror (hand-sized, steel) — `mirror_small`

## E. Camp & Survival
- [ ] Tent — `tent`
- [ ] Blanket (wool, thick) — `blanket`
- [ ] Water/Wine Skin — `waterskin`
- [ ] Standard Rations (1 week) — `rations_standard_week`
- [ ] Iron Rations (1 week) — `rations_iron_week`
- [ ] Fodder (1 load) — `fodder`

## F. Religious & Ritual
- [ ] Holy Symbol — `holy_symbol`
- [ ] Holy Book — `holy_book`
- [ ] Holy Water (1 pint) — `holy_water`
- [ ] Stakes, Wooden (4) — `wooden_stakes_4`

## G. Herbs & Reagents
- [ ] Belladonna (1lb) — `belladonna`
- [ ] Birthwort (1lb) — `birthwort`
- [ ] Comfrey (1lb) — `comfrey`
- [ ] Garlic (1lb) — `garlic`
- [ ] Goldenrod (1lb) — `goldenrod`
- [ ] Wolfsbane (1lb) — `wolfsbane`
- [ ] Woundwart (1lb) — `woundwart`

## H. Writing & Scholarly
- [ ] Ink (1 oz.) — `ink`
- [ ] Journal — `journal`
- [ ] Spell Book (blank) — `spell_book_blank`
- [ ] Spell Component Pouch — `spell_component_pouch`

## I. Entertainment & Misc
- [ ] Dice (pair) — `dice`
- [ ] Musical Instrument (common) — `musical_instrument_common`
- [ ] Musical Instrument (fine) — `musical_instrument_fine`
- [ ] Musical Instrument (masterwork) — `musical_instrument_masterwork`

# VIII. Provisions & Foodstuffs (14)

## A. Staple Foods
- [ ] Bread, White (2 lb ration) — `bread_white`
- [ ] Bread, Wheat (2 lb ration) — `bread_wheat`
- [ ] Bread, Coarse (2 lb ration) — `bread_coarse`
- [ ] Cheese (2 lb ration) — `cheese`
- [ ] Meat (2 lb ration) — `meat_1lb`
- [ ] Eggs (1 dozen) — `eggs_dozen`
- [ ] Dried Fruit (2 lb ration) — `dried_fruit`

## B. Drink
- [ ] Ale/Beer (cheap, 3 pints) — `ale_cheap`
- [ ] Ale/Beer (good, 1 pint) — `ale_good`
- [ ] Wine (cheap, 1 pint) — `wine_cheap`
- [ ] Wine (good, 1 pint) — `wine_good`
- [ ] Wine (rare, 1 pint) — `wine_rare`

## C. Spices & Luxury
- [ ] Spices (1lb) — `spices_common`
- [ ] Saffron (1lb) — `saffron`

# IX. Transport, Mounts & Animals (32)

## A. Riding Mounts
- [ ] Light Riding Horse — `light_riding_horse`
- [ ] Medium Riding Horse — `medium_riding_horse`
- [ ] Light Warhorse — `light_warhorse`
- [ ] Medium Warhorse — `medium_warhorse`
- [ ] Heavy Warhorse — `heavy_warhorse`
- [ ] Camel — `camel`

## B. Draft Animals
- [ ] Medium Draft Horse — `medium_draft_horse`
- [ ] Heavy Draft Horse — `heavy_draft_horse`
- [ ] Ox (2,000lb) — `ox`

## C. Pack Animals
- [ ] Donkey — `donkey`
- [ ] Mule — `mule`

## D. Livestock
- [ ] Cow (550lb) — `cow`
- [ ] Goat (125lb) — `goat`
- [ ] Sheep (80lb) — `sheep`

## E. Companion Animals
- [ ] Dog (hunting) — `hunting_dog`
- [ ] Dog (war) — `war_dog`
- [ ] Hawk (trained) — `hawk_trained`

## F. Tack & Harness
- [ ] Saddle and Tack (riding) — `saddle_riding`
- [ ] Saddle and Tack (war) — `saddle_war`
- [ ] Saddle and Tack (draft) — `saddle_draft`
- [ ] Saddle and Tack (pack) — `saddle_pack`
- [ ] Saddlebags (leather) — `saddlebags`
- [ ] Panniers (wicker baskets, pair) — `panniers`
- [ ] Caparison (warhorse) — `caparison`

## G. Barding (creature armor)
- [ ] Leather Barding — `barding_leather`
- [ ] Scale Barding — `barding_scale`
- [ ] Chain Barding — `barding_chain`
- [ ] Lamellar Barding — `barding_lamellar`
- [ ] Plate Barding — `barding_plate`

## H. Vehicles
- [ ] Cart (small) — `cart_small`
- [ ] Cart (large) — `cart_large`
- [ ] Wagon — `wagon`

# X. Treasure & Currency (1 in catalog)

## A. Coins
- [ ] Gold Coins — `coins_gp`

> Note: only `coins_gp` is a catalog item. At runtime, other coin denominations
> (cp/sp/ep/pp) and gems/jewelry are generated as inventory rows; a shared coin
> icon (recolored per metal) and a gem icon will likely cover them. Flag if you
> want those enumerated once the treasure-item pass is scoped.

# XI. Magic Items — PLACEHOLDER (deferred pass)

**Do not generate per-item icons yet.** ~153 entries in
`data/treasure/magic_item_catalog.json` get **one shared placeholder icon** for
now (suggested: a generic "✦ magic item" sigil). A later pass will subdivide.
For planning, the magic families are: Potions, Scrolls, Rings, Rods/Staves/Wands,
Armor & Shields (magic), Swords & Weapons (magic), and Miscellaneous/Wondrous
(amulets, cloaks, boots, bracers, helms, bags, etc.). When that pass lands, most
magic weapons/armor can reuse their mundane base icon with a "magic" overlay.

- [ ] Shared magic-item placeholder icon — `__magic_placeholder`

---

## Totals
| Section | Items |
|---|---|
| I. Weapons | 29 |
| II. Ammunition | 6 |
| III. Armor | 8 |
| IV. Shields | 1 |
| V. Clothing | 32 |
| VI. Textiles & Materials | 5 |
| VII. Gear | 50 |
| VIII. Provisions & Foodstuffs | 14 |
| IX. Transport, Mounts & Animals | 32 |
| X. Treasure & Currency | 1 |
| **Non-magic total** | **178** |
| XI. Magic items | placeholder (×1 now; ~153 later) |
