# GDD: Treasure Item Backing & Valuables

**Authority:** PROJECT-DESIGNED — the data model and instantiation pipeline that turn generated treasure (coins / gems / jewelry / magic items) into real, encumbrance-tracked, sellable inventory items. The ACKS Constraints in §2 (encumbrance weights, gp values, recovery-XP rules) are sacred and applied verbatim. One genuine RAW gap (jewelry encumbrance) is flagged for Jedidiah in §7 and §13.
**Status:** Draft v1.4 — **Phase 1 + runtime-consumer foundation + Phase 2 (magic-item catalog) implemented and tested** (2026-05-28, Jedidiah approved). Phase 1: migration 134 (`inventory_items.value_cp`), `InventoryItem.effective_value_cp`, the `TreasureInstantiator` hoard→inventory bridge, `ShopService` sell-by-value. Runtime-consumer foundation: migration 135 (`treasure_hoards.is_looted`), `DungeonGeneratorRepository` room-hoard load/mark-looted, `TreasureLootService.claim_room_hoards()` (hoard → lootable cache). Phase 2: `MagicItemCatalog` + `data/treasure/magic_item_catalog.json` (153 items from Core) → magic items resolve to real named items. Full suite green (388 passed / 19 pre-existing failures, net-zero new). Remaining: (a) dungeon-runtime session calls `claim_room_hoards()` from `_resolve_loot` (§5); (b) magic-item **usage session** for effects/charges/identification + a magic-item sale economy (Phase 3). Retained decisions: jewelry = 1 unit (§7); backward-compat confirmed (§4.1).
**Depends on ACKS rules:** `rules/acore_equipment.xml:582-593` (character encumbrance table — treasure is 1 stone per 1,000 coins or gems; items are 1 stone per 6 items; magic-armor weight reduction); `rules/acore_treasure_and_magic_items_rules.xml:1-7` (treasure scope and XP rules), `:90-118` (gem value table), `:120-145` (jewelry value table), `:147-170` (special-treasure trade goods with per-item gp + stone), `:184-240` (magic-item category/name tables + magic-armor weight rule); `rules/acore_adventures_and_encounters.xml:580-590` (treasure XP: 1 XP per 1 gp recovered to civilization; equipment must be sold to grant XP; magic items grant no XP); `rules/acore_proficiencies_rules_and_catalog.xml:478-488` (Adventuring proficiency — all PCs can roughly value coins, trade goods, gems, jewelry).
**Depends on project GDDs:** [`gdd-dungeon-generator-v1.md`](gdd-dungeon-generator-v1.md) (§13 produces the `TreasureHoardData` this GDD consumes); [`gdd-party-inventory.md`](gdd-party-inventory.md) (defines the loot queue, carrier model, cache value-loss, and the GP/coin display this GDD must feed real valuables into); [`gdd-phase-10b-2-trade-block.md`](gdd-phase-10b-2-trade-block.md) (mercantile/trade-good loads — special treasures (§10) are bulk trade goods that overlap this system).
**Implementing files (landed):** Phase 1 — `db/migrations/134_inventory_item_value_cp.sql` (+ `db/schema.sql`); `engine/subsystems/inventory/treasure_instantiator.gd` (`TreasureInstantiator` bridge); `engine/shared_types/inventory_item.gd` (`value_cp` + `effective_value_cp`); `engine/autoloads/campaign_repository.gd` (6 `inventory_items` INSERT paths thread `value_cp`); `engine/subsystems/commerce/shop_service.gd` (sell by `value_cp`). Runtime-consumer foundation — `db/migrations/135_treasure_hoard_is_looted.sql` (+ `db/schema.sql`); `engine/subsystems/inventory/treasure_loot_service.gd` (`TreasureLootService.claim_room_hoards`); `engine/subsystems/generation/dungeon_generator_v1/dungeon_generator_repository.gd` (`get_unlooted_treasure_hoards_for_room` + `mark_hoard_looted`). Phase 2 — `tools/extract_magic_item_catalog.py` → `data/treasure/magic_item_catalog.json` (153 items); `engine/subsystems/inventory/magic_item_catalog.gd` (`MagicItemCatalog`); `TreasureInstantiator` + `TreasureLootService` resolve magic items. Tests: `tests/test_treasure_instantiator.gd`, `tests/test_magic_item_catalog.gd`.
**Modifiable by Claude Code:** Yes within constraints. The `value_cp` column, item_category vocabulary, synthetic item_keys, catalog format, and instantiation algorithm are engineering decisions. The ACKS Constraints in §2 are not. The jewelry-encumbrance decision (§7) and the `inventory_items` schema change (§4.1) require Jedidiah's explicit approval per the design-brief data-model rule.
**Last updated:** 2026-05-28

---

## 1. Purpose and Scope

The dungeon generator's `DungeonTreasureResolver` produces a `TreasureHoardData` containing coin counts, gem dicts (`{value_gp, gem_class}`), jewelry dicts (`{value_gp, jewelry_class}`), and magic-item placeholders. This is correct as a *generation ledger* — it records what a hoard is worth for XP/GP balance. But a hoard is not yet something a player can interact with: a generated gem has a gp value but **no weight, no inventory record, and no way to be carried, weighed, or sold**; jewelry the same; found magic items are pure placeholders with no catalog behind them. `gdd-party-inventory.md` already *assumes* valuables are real (its cache-raid example reads "Lost: 200 GP, 1 ruby (total value 450 GP)") — but nothing in the engine produces that ruby as a weighable, valued, sellable item.

This GDD closes the gap between the generation ledger and the player's pack. It defines (a) the **minimal data-model addition** that lets an inventory item carry an authoritative per-item monetary value, (b) **gems and jewelry as first-class inventory item types** with RAW encumbrance, (c) the **found-magic-item catalog** that replaces placeholders, and (d) the **`TreasureHoardData → inventory_items` instantiation contract** that the dungeon runtime-consumer session will call when a party loots a hoard. The unifying goal: generated treasure becomes real inventory — it weighs the party down per ACKS encumbrance, it can be sold for its rolled value, and it grants the correct recovery XP.

Coins are already fully backed (§8) and require no change; they are documented here only so the instantiation bridge is complete. The audit that motivated this GDD is captured in §3.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed.

### 2.1 Encumbrance (weight)

- **Treasure is 1 stone per 1,000 coins or gems** — i.e. a single coin or a single gem weighs 1/1,000 stone (`rules/acore_equipment.xml:582-588`, `character_encumbrance_table`, row `Treasure`). The project's encumbrance unit is 1/1,000 stone, so a coin or gem = **1 encumbrance unit**.
- **Ordinary items are 1 stone per 6 items**, and "each weapon, scroll, potion, vial, wand, magic item, or similar object counts as one item" (`rules/acore_equipment.xml:582-592`, `character_encumbrance_table` row `Items` + `item_counting_rule`). One item = **~167 encumbrance units** (1,000 ÷ 6). This governs most found magic items (potions, scrolls, wands, rings, miscellaneous).
- **Heavy items are 1 stone each** (8–14 lb objects) (`rules/acore_equipment.xml:582-589`, row `Heavy Item`). = **1,000 units**.
- **Non-cursed magical armor weighs less than normal: after the first +1, reduce magical-armor weight by 1 additional stone per further +1, to a minimum of 0** (`rules/acore_treasure_and_magic_items_rules.xml:238`; also `rules/acore_equipment.xml:591`, `magic_armor_rule`). `EncumbranceCalculator.calculate_item_encumbrance` already implements this for items flagged `is_magical` in categories `armor`/`shield`.
- **The encumbrance table is silent on jewelry.** It enumerates coins/gems, items, heavy items, and worn clothing — jewelry is not named. This is a genuine RAW gap; see §7 and §13.

### 2.2 Value (gp)

- **A gem's value** is rolled on the gem table: average 30 gp (ornamental), 200 gp (gem), 4,000 gp (brilliant), with a detailed sub-table from 10 gp to 10,000 gp (`rules/acore_treasure_and_magic_items_rules.xml:90-118`, `gem_value` table; "Average gem value is 200 gp per stone").
- **A piece of jewelry's value** is rolled on the jewelry table: average 225 gp (trinket), 1,000 gp (jewelry), 11,000 gp (regalia), detailed sub-table to tens of thousands of gp (`rules/acore_treasure_and_magic_items_rules.xml:120-145`, `jewelry_value` table). Conversion: **each regalia = 12 jewelry, each jewelry = 4 trinkets** (`:125`).
- **Special treasures** replace coin/gem/jewelry lots with trade or luxury goods that carry **explicit per-item gp values and per-item stone weights** (`rules/acore_treasure_and_magic_items_rules.xml:147-170`, `special_treasures` `tables_compact` — e.g. "1 rich fur cape, worth 4d6×100gp, 1 stone"; "1d3 rugs or tapestries, 5gp each, 2d6 stone each"). "A lot is 1 piece of jewelry, 1 gem, or 1,000 coins" (`:149`).

### 2.3 XP and sale on recovery

- **Treasure consists of coin, gems, jewelry, special treasures, and magic items** (`rules/acore_treasure_and_magic_items_rules.xml:1-4`).
- **Coins, gems, jewelry, and special treasure grant 1 XP per 1 gp value, only when recovered to civilization** (a friendly town or stronghold) (`rules/acore_treasure_and_magic_items_rules.xml:5`; `rules/acore_adventures_and_encounters.xml:580-588`).
- **Magic items do NOT grant XP for recovery** (`rules/acore_treasure_and_magic_items_rules.xml:6`). The resolver already contributes 0 gp for magic items to `total_gp_value`; this is RAW-correct.
- **Recovered mundane equipment must be sold immediately for coin to grant XP; if kept for later use it grants no XP** (`rules/acore_adventures_and_encounters.xml:585-588`). Implication: the *value* a valuable carries is the basis both for sale proceeds and for recovery XP.

### 2.4 Magic-item identity

- **Magic items fall into eight random categories** — Potions, Rings, Scrolls, Rods/Staffs/Wands, Miscellaneous Magic, Swords, Miscellaneous Weapon, Armor (`rules/acore_treasure_and_magic_items_rules.xml:197-206`, `random_magic_type_table`).
- **Named item tables per category** exist in RAW (`:208-216`, `random_item_tables`), with a note that the Core file preserves "core rows" and that full d00 distributions live in the source tables — i.e. the complete catalog may require the APC / Axioms magic-item tables, not just Core.
- **Most magic items are unlabeled and require identification** (sage, Magical Engineering/Loremastery proficiency, sipping for potions, or Magic Research by a 9th+ arcane caster) (`:184-195`).

---

## 3. Current-State Audit (what motivated this GDD)

Coverage of each treasure output, as built today:

| Output | Value backing | Weight backing | Inventory record | Sellable today | Verdict |
|---|---|---|---|---|---|
| **Coins** (cp/sp/ep/gp/pp) | ✅ `Currency.DENOMINATIONS` cp_value | ✅ `Currency.ENC_PER_COIN = 1` per coin; `_create_coin_item` writes `encumbrance_units=1`, `item_category="treasure"` | ✅ `inventory_items` rows via `add_coins_cp`/`add_specific_coins` | ✅ spent via `PartyWallet`/`Currency.compute_deduction` | **Complete.** No change. |
| **Gems** | ⚠️ value only, as a bare dict `{value_gp, gem_class}` on the hoard | ❌ no weight; never an inventory item | ❌ none | ❌ `ShopService.sell_item` rejects non-catalog items | **Gap: needs item record + weight.** RAW value & weight both known. |
| **Jewelry** | ⚠️ value only, bare dict `{value_gp, jewelry_class}` | ❌ no weight; **RAW also silent on jewelry weight** | ❌ none | ❌ rejected as above | **Gap + RAW gap (weight).** |
| **Magic items** | ❌ all placeholders; `{category, specific_item_id:"", is_placeholder:true}` | ❌ none | ❌ none | ❌ `ShopService` explicitly blocks `is_magical` | **Largest gap: no found-item catalog.** RAW category/name tables exist but are unextracted. |
| **Special treasures** (trade/luxury goods) | n/a | n/a | n/a | n/a | **Not generated at all.** Data model should anticipate (§10); RAW gives gp + stone. |

Key structural findings from the audit:

1. **There is no equipment-catalog DB table.** The catalog is JSON only (`data/equipment/base_equipment.json` + `transport.json` + foodstuffs), loaded by `EquipmentCatalog` (`engine/subsystems/characters/equipment_catalog.gd`), keyed by `item_key`. `base_equipment.json` carries `cost_cp` (value, in copper) and `encumbrance_units` (weight, 1/1,000 stone) per item — but contains **no gems, no jewelry, no magic items**; its only `treasure`-category entry is a single `coins_gp` row.
2. **`inventory_items` has a weight column but no value column.** Columns include `encumbrance_units`, `item_category`, `is_magical`, `magical_bonus`, `material`, `uses_remaining` — but **nothing for monetary value**. Item value is obtained only indirectly, by looking up `item_key` → catalog `cost_cp`. That path fails for gems/jewelry (variable, rolled values that don't belong in a fixed catalog) and for found magic items.
3. **Selling requires catalog membership.** `ShopService.sell_item` / `get_sellable_items` value items at catalog `cost_cp` and **reject any item not in the catalog**, plus all coins and all `is_magical` items. So even if a gem were placed in inventory, it could not be sold.
4. **`LootAutoDistributor` excludes `item_category == "treasure"` (coins) and routes everything else** by preference tag / heuristic, enriching missing fields from the catalog. A gem/jewelry item with a non-`treasure` category and pre-stamped `encumbrance_units` would distribute correctly without needing a catalog entry.
5. **`EncumbranceCalculator` already expects the gem model.** Its header documents "Treasure: 1 stone per 1,000 coins/gems (1 unit per coin/gem)" and sums `encumbrance_units × quantity`. It needs no change — it just needs gem/jewelry rows to *exist* with `encumbrance_units` set.

Conclusion: coins are done; gems/jewelry need an inventory record + a value field + (for jewelry) a weight decision; magic items need a catalog. The minimal schema change is a single column (§4.1).

---

## 4. Data-model additions

### 4.1 `inventory_items.value_cp` (new column — requires approval)

Add one nullable-style column via a new sequential migration:

```sql
-- Migration 134: per-item authoritative value for rolled valuables.
ALTER TABLE inventory_items ADD COLUMN value_cp INTEGER NOT NULL DEFAULT -1;
```

Semantics:

- **`value_cp = -1`** (the default for every existing row) means *"no intrinsic value — value this item by `item_key` → `EquipmentCatalog.cost_cp`."* This preserves today's behavior for all mundane equipment with zero data migration.
- **`value_cp >= 0`** is the **authoritative** per-item value in copper pieces, used for gems, jewelry, special-treasure trade goods, and (later) identified magic items whose value isn't a fixed catalog price.

Why copper, why per-item, why a column rather than a catalog:

- **Copper** matches the project's currency-precision rule (`Currency` and `ShopService` work in cp throughout). Gem/jewelry values are whole gp, so `value_cp = value_gp × 100` is exact — no rounding. Where a future value needs rounding, use `XPAwardCalculator.bankers_round` per the project-wide convention.
- **Per-item, not catalog:** a "ruby" is not a catalog SKU with a fixed price — each rolled gem/jewelry piece has its own value. The value must live on the inventory row, not in a shared catalog.
- **Column, not a side table:** values are 1:1 with inventory rows and queried whenever the row is; a column is the minimal, lowest-friction representation and keeps `value_cp` traveling with the item through transfers, containers, and caches.

**Backward compatibility — no conflict, no rework of existing data.** Verified against the live schema and all call sites:

- **The migration is non-destructive and needs no data backfill.** SQLite `ADD COLUMN` with a `NOT NULL DEFAULT` stamps the default onto every existing row in place (no table rebuild). Every existing `inventory_items` row becomes `value_cp = -1`, which means "value me by catalog `cost_cp`" — *exactly* today's behavior. This is the same pattern that added `encumbrance_units` itself (migration 014) and the migration-108–116 `_cp` value-column rename sweep; `value_cp` follows that established naming convention.
- **No existing INSERT breaks.** All eight `INSERT INTO inventory_items` sites (7 in `CampaignRepository`, 1 in `research_magic.gd`) use **explicit named-column lists** — none is a positional `INSERT … VALUES` without columns. A new trailing column with a default is therefore invisible to them; they keep inserting and the default fills `value_cp`.
- **No existing READ breaks.** `godot-sqlite` returns `query_result` rows as name-keyed Dictionaries, so `SELECT *` callers simply gain an extra `value_cp` key; positional shifting is impossible.
- **The equipment JSON catalog (~130 items) is untouched** — `cost_cp` remains the value source for all mundane equipment. Zero catalog rework.
- **Only two code touches are *required*, both additive:** (1) add `value_cp` (default `-1`) to `InventoryItem.from_dict`/`to_dict` and the **one** insert path the instantiator uses (`add_inventory_item`, `campaign_repository.gd:2751`); (2) make value-reading callers (`ShopService`, cache-raid value-loss) prefer `effective_value_cp`. Threading `value_cp` through the other six insert paths is optional polish, not required — they serve mundane items that correctly default to `-1`.

Companion code changes (all additive):

- `InventoryItem` (`engine/shared_types/inventory_item.gd`): add `var value_cp: int = -1`; carry it in `from_dict`/`to_dict`; add `func effective_value_cp(catalog) -> int` returning `value_cp if value_cp >= 0 else int(catalog.get_item(item_key).get("cost_cp", 0))`.
- All `inventory_items` INSERT paths in `CampaignRepository` gain `value_cp` (default `-1`) in the column list.

### 4.2 `item_category` vocabulary

`inventory_items.item_category` is free `TEXT DEFAULT 'gear'` with no CHECK constraint, so extending the vocabulary needs no migration. Reserve these category strings (convention only):

| Category | Meaning | Weight rule | Coin-style? |
|---|---|---|---|
| `treasure` | coins only (existing; `Currency.COIN_ITEM_CATEGORY`) | 1 unit/coin | handled by `PartyWallet` |
| `gem` | a single gem | 1 unit (§6) | no |
| `jewelry` | a single piece of jewelry | 1 unit (§7) | no |
| `trade_good` | special-treasure bulk good (§10) | per-RAW stone (often heavy) | no |
| `magic` | a found magic item (or keep base category + `is_magical=1`) (§9) | 1 item / base / reduced-armor | no |

**Do not reuse `treasure`** for gems/jewelry — `LootAutoDistributor` and `PartyWallet` treat `treasure` as coins and would mis-handle them. New categories fall through `LootAutoDistributor`'s generic fallback (round-robin to PCs), which is the desired behavior for portable valuables.

### 4.3 Synthetic item_keys

Gems and jewelry are intentionally **not** added to `EquipmentCatalog` (their value is variable). They use synthetic, self-describing `item_key`s so existing key-substring logic stays sane:

- Gems: `gem_ornamental`, `gem_gem`, `gem_brilliant` (class from the resolver's `gem_class`). `name` = a flavor string (e.g. "Ornamental (malachite)") chosen at instantiation; the gp value lives in `value_cp`.
- Jewelry: `jewelry_trinket`, `jewelry_jewelry`, `jewelry_regalia` (from `jewelry_class`).

`EquipmentCatalog.get_item()` returns `{}` for these keys; that is fine because the instantiator stamps `encumbrance_units`, `item_category`, `name`, and `value_cp` directly onto the row, and `effective_value_cp` (§4.1) reads `value_cp` without touching the catalog.

---

## 5. Treasure → inventory instantiation bridge (the runtime-consumer contract)

This is the artifact the **separate runtime-consumer session** needs. It is a pure transformation from a generation ledger (`TreasureHoardData`) into player-facing inventory, with no UI and no XP logic of its own.

**Realized (2026-05-28).** The pure transform below is `TreasureInstantiator.hoard_to_loot()` (landed, Phase 1). A thin runtime adapter, **`TreasureLootService.claim_room_hoards(dungeon_id, floor_id, room_id, cell)`** (`engine/subsystems/inventory/treasure_loot_service.gd`, landed), wraps it for the dungeon runtime: it loads a room's UNLOOTED hoards (`DungeonGeneratorRepository.get_unlooted_treasure_hoards_for_room`), materialises each into a dungeon loose cache (coins as per-denomination coin rows; gems/jewelry/magic as `inventory_items` carrying `value_cp`, via `add_inventory_item` + `transfer_item_to_cache`), marks them looted (`mark_hoard_looted`; migration 135 adds `treasure_hoards.is_looted`), and returns the `cache_id`. It is idempotent and does NOT open UI, deposit coins, or award XP — the existing loot-modal / pick-up-all flow handles that on the returned cache. **The one remaining wiring** (owned by the dungeon-runtime session): call `claim_room_hoards()` from `dungeon_handlers._resolve_loot` when a room with treasure is first looted, then open the loot modal on the returned `cache_id`.

```
TreasureInstantiator.hoard_to_loot(hoard: TreasureHoardData) -> Dictionary
  returns {
    coins_cp:   int,            # aggregate coin value, for PartyWallet.deposit_*
    items:      Array[Dictionary],  # inventory_items-shaped dicts (one per gem/jewelry/trade_good/magic item)
    magic_placeholders: Array,  # unresolved magic-item stubs (catalog gap), carriable but inert
  }
```

Per-output handling:

1. **Coins** → sum to `coins_cp = platinum*500 + gold*100 + electrum*50 + silver*10 + copper` (cp). The caller deposits via the existing `PartyWallet.deposit_to_party_even_split` / `CampaignRepository.add_coins_cp`, which already create weight-tracked coin rows (§8). Coins are **not** emitted as `items`.
2. **Gems** → one item dict per gem: `{item_key:"gem_<class>", name, quantity:1, item_category:"gem", encumbrance_units:1, value_cp: value_gp*100, is_magical:false}`.
3. **Jewelry** → one item dict per piece: `{item_key:"jewelry_<class>", name, quantity:1, item_category:"jewelry", encumbrance_units:1, value_cp: value_gp*100}`.
4. **Magic items** → if the §9 catalog resolves the entry: a real item dict (correct base category, `is_magical:true`, `magical_bonus`, `weapon_damage`/`armor_ac_bonus` for weapons/armor, `encumbrance_units` per §2.1, `value_cp:-1` until a magic-item market exists). If unresolved (catalog gap): emit a **carriable placeholder stub** (`item_category:"magic"`, `is_magical:true`, `encumbrance_units:167`, `value_cp:-1`, `uses_remaining` as appropriate, `notes` describing the indicated category) so the player can at least pick it up and identify it later — rather than the item vanishing.

Design rules for the bridge:

- **Pure and deterministic.** No DB writes, no signals — it returns a plan. The caller (loot modal / auto-loot) executes deposits and inserts, exactly like `LootAutoDistributor` returns a plan the caller applies.
- **Idempotent per hoard.** The hoard's `id` should be recorded as consumed by the caller so a hoard can't be looted twice; the bridge itself is stateless.
- **Stacking:** gems/jewelry are **not** stacked (each has its own `value_cp`); they are distinct rows even when the same class. Identical-value pieces *may* be display-grouped in the UI, but stay distinct rows.

This contract lets the runtime-consumer session attach real items to an instantiated dungeon without re-deriving any ACKS math.

---

## 6. Gems

- **Value:** `value_cp = value_gp × 100`, where `value_gp` is whatever the resolver rolled (today: the class average 30/200/4,000; a future refinement may sub-roll the 10–10,000 gp detail table — that is a resolver concern, not a data-model concern). RAW: `rules/acore_treasure_and_magic_items_rules.xml:90-118`.
- **Weight:** `encumbrance_units = 1` (1/1,000 stone). RAW: `rules/acore_equipment.xml:582-588` ("1 stone per 1,000 coins or gems"). This is unambiguous.
- **Record:** one `inventory_items` row per gem, `item_category="gem"`, synthetic `item_key` (§4.3).
- **Sellable:** yes, once §11 extends the sell path to value by `effective_value_cp` and to accept the `gem` category.

No RAW gap for gems.

---

## 7. Jewelry — value certain; weight is a RAW gap (RESOLVED: 1 unit)

- **Value:** `value_cp = value_gp × 100`. RAW: `rules/acore_treasure_and_magic_items_rules.xml:120-145`.
- **Weight: not specified by RAW.** The encumbrance table (`rules/acore_equipment.xml:582-592`) lists coins/gems, items, heavy items, and clothing — **jewelry is not named.** Three defensible readings:

  | Option | `encumbrance_units` | Argument | Against |
  |---|---|---|---|
  | **(a) Gem-equivalent** *(recommended for V1)* | **1** (1/1,000 stone) | Jewelry is a small valuable; "a lot is 1 piece of jewelry, 1 gem, or 1,000 coins" (`:149`) treats the three as equivalent units; matches `EncumbranceCalculator`'s existing "coins/gems" abstraction; simplest. | A necklace plainly isn't as light as one coin; the encumbrance table says "gems," not "jewelry." |
  | **(b) One item** | **167** (1/6 stone) | The `item_counting_rule` says "or similar object counts as one item" (`:592`); jewelry is a discrete object. | Gems are *also* discrete objects yet get the explicit 1/1,000 rule, so "object = 1 item" clearly has exceptions. |
  | **(c) ~1 stone** | **1,000** | The special-treasure *jewelry-replacement* table gives its analogs 1 stone each (rich fur cape, fur coat, statuettes — `:167`), implying jewelry pieces are roughly 1-stone-scale. | Those are bulky-good *replacements*, not jewelry itself; over-weights a thin gold ring. |

- **Resolved (Jedidiah, 2026-05-28): option (a) — jewelry weighs 1 encumbrance unit (1/1,000 stone), identical to coins and gems.** Internally consistent with the existing encumbrance abstraction, and it keeps a hoard of valuables negligibly light (matching the "Hoarder = high value, ≤10 stone" treasure-category guidance at `:25`). Encode as a single constant (e.g. `JEWELRY_ENC_UNITS = 1`) so a future change is a one-line edit. This is a **project decision filling a RAW gap** (the encumbrance table is silent on jewelry), not a RAW statement — flagged as such per this project's constraint-marking rules.

---

## 8. Coins (already complete — documented for the bridge)

No change required. Recorded here so the instantiation bridge (§5) is fully specified:

- **Value:** `Currency.DENOMINATIONS` (`engine/subsystems/commerce/currency.gd`): pp=500cp, gp=100cp, ep=50cp, sp=10cp, cp=1cp (`rules/acore_treasure_and_magic_items_rules.xml` exchange rates; ACKS Core p.36).
- **Weight:** `Currency.ENC_PER_COIN = 1` per coin; `CampaignRepository._create_coin_item` writes `encumbrance_units = 1`, `item_category = "treasure"`; `EncumbranceCalculator` sums `1 × quantity`. RAW: `rules/acore_equipment.xml:586` ("1 stone per 1,000 coins").
- **Storage:** real `inventory_items` rows per denomination per character; `PartyWallet` aggregates and deducts. Coins flow into the wallet, not the item list.

---

## 9. Found magic items (catalog — Phase 2 ✅ 2026-05-28; prices ✅ 2026-05-29)

Previously the biggest gap (the `crafted_magic_items` table is *player-crafted* only). Now built: **`data/treasure/magic_item_catalog.json`** (153 items across 8 categories), extracted by **`tools/extract_magic_item_catalog.py`** from `rules/acore_treasure_and_magic_items_rules.xml:197-216` (the `random_magic_type_table` d100 categories + the per-category `random_item_tables` name lists; `weapons_table` is prose, hand-coded into sword/misc_weapon/armor entries). Loaded by **`MagicItemCatalog`** (`engine/subsystems/inventory/magic_item_catalog.gd`); `TreasureInstantiator` resolves each hoard magic item to a real named item via `MagicItemCatalog.pick_for_token()`, falling back to a placeholder only when the category can't resolve. `TreasureLootService` passes a per-hoard seeded RNG so the specific item is deterministic.

**Catalog scope:** the catalog carries names + categories + `magical_bonus` + `is_cursed` + a 1-item encumbrance (167 units) + (since 2026-05-29) a sale price `value_gp` and `creation_time_days` (§9.1). It does NOT model per-item **effects, charges, or identification**, nor bind specific named spells to scrolls — those are a dedicated **magic-item usage session**. Found magic items still grant 0 recovery XP (RAW §2.3) but are now **sellable** at their `value_gp`. Category-level selection is **uniform** (Core preserves item NAMES, not full d00 per-item sub-ranges); the only RAW sub-tables we have (Ring of Protection variants, Scroll of Spells contents) are applied via `sub_roll` / `generator` materialization (§9.1).

The original proposed shape (the shipped file uses `type_table` + `items`):

```jsonc
{
  "category_table": [ /* random_magic_type_table d100 → category (:197-206) */ ],
  "items": [
    {
      "item_key": "potion_healing",
      "name": "Potion of Healing",
      "category": "potion",            // potion|ring|scroll|rod_staff_wand|misc_magic|sword|misc_weapon|armor
      "encumbrance_units": 167,        // §2.1: 1 item; weapons/armor use base + magic-armor reduction
      "is_magical": true,
      "magical_bonus": 0,
      "weapon_damage": "",             // for sword/weapon items
      "armor_ac_bonus": 0,             // for armor items
      "uses_remaining": 1,             // potions=1 dose, charged items=N, permanent=-1
      "effect_kind": "one_use",        // align with crafted_magic_items.effect_kind vocabulary
      "value_cp": -1,                  // sale value deferred (see below)
      "requires_identification": true, // :184-195
      "notes": ""
    }
    // ... potions, rings, scrolls, rods/staffs/wands, misc magic, swords, misc weapons, armor
  ]
}
```

Instantiation: when a hoard's `magic_items` entry resolves against this catalog, the bridge (§5) emits a real item; otherwise it emits a carriable placeholder stub. Encumbrance follows §2.1 (most = 167 units; magic armor uses base weight reduced per `magical_bonus`, which `EncumbranceCalculator` already handles).

**Deferred (flag, don't design here):**

- **Sale value / magic-item market — ✅ prices LANDED 2026-05-29 (§9.1).** Found magic items now carry a `value_gp` (the ACKS crafting-cost model) and sell at the mundane shop. Magic items still grant **0 recovery XP** (RAW §2.3), so they never feed `total_gp_value`. Market-class gating for high-value sales remains Phase 3.
- **Identification flow** (sage / Magical Engineering / Loremastery / sip / Magic Research) is its own system; the catalog only needs the `requires_identification` flag so a future identify system has somewhere to hang.
- **Per-item effects / charges + binding specific named spells to scrolls** belong to the magic-item usage session.

### 9.1 Sale prices + creation time (✅ LANDED 2026-05-29)

Every catalog item carries **`value_gp`** (sale value) and **`creation_time_days`** (time to craft, recorded for later economy/crafting use). `TreasureInstantiator` stamps `value_cp = value_gp × 100` onto each instantiated magic item; `ShopService` sells any magic item with an authoritative `value_cp ≥ 0` at full value (§11.1).

**Source + authority.** Prices are the game creator's published list ([forum.autarch.co/t/magical-item-prices/3000/5](http://forum.autarch.co/t/magical-item-prices/3000/5)) — Macris's worked examples of the SACRED `magic_item_creation_table` (`rules/acore-campaign-general-and-magic-research.xml:185-215`), cross-validated against the SACRED `sample_magic_items` table (L238-247: Potion of Healing 500, Sword +1 5,000, **Sword +2 15,000**, Ring of Invisibility 1/turn 33,000, Wand of Fireball 30,000). The same ladder backs player crafting in `magic_item_enchanting.gd`, so a found item's sale value equals what a PC pays to craft it. Times normalized to days (wk×7, mo×30, per the ACKS 30-day month). The curated `PRICE_MAP` lives in `tools/extract_magic_item_catalog.py`, which cross-checks bidirectionally (every catalog key must have a price and vice-versa) so a typo errors loudly.

**Coverage (153 items):** 142 priced from the forum (140 direct + 2 derived below); 8 cursed/trap items → `value_gp 0`, non-sellable (Jedidiah: Macris prices only legitimately-craftable items, so pure curses are worthless); 3 sentinel `-1` (the `ring_of_protection` + `spell_scroll` parents, plus `treasure_map`, a quest hook).

**Two coarse entries materialize to priced variants** at instantiation (`MagicItemCatalog` resolves a `sub_roll` / `generator` on the parent, deterministic per the hoard RNG):
- **Ring of Protection** → a d100 `sub_roll` (RAW Core variant table) → 5 unique variants: +1 (25k / 100d), +2 (50k / 200d), +2 5'-radius (75k / 300d — **DERIVED**: forum unpriced; same formula, the 5' radius adds +1 effective spell level = +25k), +3 (75k / 300d), +3 5'-radius (100k / 400d). **Radius semantics** (Jedidiah 2026-05-29, recorded on the variant for the usage session): the 5'-radius variants apply the **saving-throw bonus to allied creatures within 5'**, but the **AC bonus only to the wearer**.
- **Spell Scroll** → the `scroll_of_spells` generator: roll class (d4: 1-3 arcane / 4 divine, corroborated SACRED `:227`), spell **count** (1-7, weighted by the RAW scrolls-d100 "Spells (N)" sub-band, rows 41-76 — count 1 ≈ 42%, tapering to 7 ≈ 3%), and each spell's level (d100 per the RAW arcane/divine tables); **price = 500 × Σ(spell levels)** (one-use effect, `magic_item_creation_table` L193). Records `scroll_class` + `spell_levels` for the usage session.

**Project rulings recorded:**
- **Vorpal Sword = 160,000 gp / 590 d** (Jedidiah 2026-05-29): Sword +3 base (35,000 gp / 90 d) + vorpal as a **5th-level Permanent/Unlimited effect** (500 × 5 × 50 = 125,000 gp; 100 d × 5 = 500 d). Supersedes an earlier 60,000 gp / 190 d (1st-level-vorpal) derivation.
- **Potion of Sweet Water = 500 gp** (1st-level one-use; absent from the forum).

**Flags / deferred:**
- Spell-scroll **count** is now RAW-weighted (✅ 2026-05-29, rows 41-76 of the scrolls d100 table); the placeholder is gone.
- **Treasure-map subtypes (future feature).** The RAW scrolls d100 table (provided 2026-05-29) has **13 treasure-map variants** (rows 77-100) leading to gp / gems / jewelry / magic-item reward hoards. The catalog collapses them to one non-merchandise `treasure_map` (`value_gp -1`). Generating those reward hoards (a quest/treasure-generation feature) and driving scroll **type** selection off the full d100 (vs. today's uniform category selection) are a deferred enhancement.
- Binding **specific named spells** (vs. just levels) is deferred to the usage session.
- **Market-class gating** for high-value magic sales (e.g. a 275,000 gp Staff of Wizardry at a hamlet) is deferred to Phase 3; V1 sells at full `value_cp` through `ShopService`, exactly like gems/jewelry.

---

## 10. Special treasures (anticipated, not yet generated)

The resolver does not yet roll special treasures (the `special_treasures` replacement step, `rules/acore_treasure_and_magic_items_rules.xml:147-170`). When generation adds them, the data model here already accommodates them: a special-treasure good is an `item_category = "trade_good"` inventory item with `value_cp = value_gp × 100` and `encumbrance_units` taken **directly from RAW** (the tables give per-item stone, e.g. "1d3 rugs or tapestries, 5gp each, 2d6 stone each" → `encumbrance_units = stone × 1000`). No new data-model work is needed for special treasures beyond what §4 provides; they reuse `value_cp` and a category string. Note the overlap with [`gdd-phase-10b-2-trade-block.md`](gdd-phase-10b-2-trade-block.md): special-treasure goods *are* trade goods and may eventually be sold through the mercantile load system rather than the equipment shop — flagged in §13.

---

## 11. Sellability and recovery XP

### 11.1 Selling valuables

`ShopService.sell_item` / `get_sellable_items` must be extended so valuables are sellable:

- **Value by `effective_value_cp`** (§4.1) rather than strictly by catalog `cost_cp`.
- **Accept items whose `item_category` is `gem`, `jewelry`, or `trade_good`** even though they are not in `EquipmentCatalog` (today these are rejected with "This item cannot be sold here").
- Keep the exclusion for coins (`Currency.is_coin`). For `is_magical` items (✅ 2026-05-29): sellable **iff** they carry an authoritative `value_cp ≥ 0` (priced found items from the catalog); crafted/quest magic items (`value_cp -1`) stay non-sellable — this guards against a crafted magic sword being mis-valued at the mundane catalog price. Cursed found items (`value_cp 0`) pass the magic gate but are then dropped by the existing `unit_value_cp ≤ 0` guard.
- ACKS gives all PCs the **Adventuring** proficiency, which covers "rough valuation of common coins, trade goods, gems, and jewelry" (`rules/acore_proficiencies_rules_and_catalog.xml:478-488`, Adventuring) — so the party can always at least estimate a valuable's worth; no special appraisal gate is required for V1. A future Appraisal/merchant-haggling layer can modulate the sale fraction, but base sale = full `value_cp`.

### 11.2 Recovery XP

RAW §2.3: coins/gems/jewelry/special treasure grant 1 XP per 1 gp **when recovered to civilization**, and mundane equipment must be **sold** to grant XP. The instantiated items' `value_cp` is the basis for both. The recovery-XP trigger (party reaches a friendly town/stronghold) is a **separate system** — this GDD only guarantees the value data exists on each item for that system to read. `hoard.total_gp_value` (coins+gems+jewelry, magic excluded) remains the generation-time XP/GP-balance figure; per-item `value_cp` is the runtime basis once items are split across carriers, partially sold, or lost.

---

## 12. Phasing

- **Phase 1 (MVP — unblocks the runtime-consumer): ✅ LANDED 2026-05-28.** Migration 134 (`value_cp`, §4.1); `InventoryItem.value_cp` + `effective_value_cp`; the `TreasureInstantiator.hoard_to_loot()` bridge (§5) producing gem/jewelry items (§6, §7) + carriable magic placeholders; `ShopService` sells by `value_cp` and accepts gem/jewelry (§11.1); `value_cp` threaded through all 6 `inventory_items` INSERT paths so valuables never lose value on insert/copy/transfer. Tested: `tests/test_treasure_instantiator.gd` (8 pure-logic + 1 DB integration) + the existing ShopService suite, all green. Looted coins + gems + jewelry are now real, weighed, and sellable.
- **Runtime-consumer foundation: ✅ LANDED 2026-05-28.** Migration 135 (`treasure_hoards.is_looted`); `DungeonGeneratorRepository.get_unlooted_treasure_hoards_for_room` + `mark_hoard_looted`; `TreasureLootService.claim_room_hoards()` (materialises a room's hoards into a lootable cache; idempotent). Tested (3 DB tests in `tests/test_treasure_instantiator.gd`). Remaining: the dungeon-runtime session calls `claim_room_hoards()` from `_resolve_loot` (§5).
- **Phase 2 (magic items): ✅ LANDED 2026-05-28.** `data/treasure/magic_item_catalog.json` (153 items) extracted from Core by `tools/extract_magic_item_catalog.py`; `MagicItemCatalog` loader; `TreasureInstantiator` + `TreasureLootService` resolve hoard magic items to real named items (placeholder only on a category miss). Per Jedidiah, Core suffices for the V1 catalog (names + categories); per-item **effects / charges / identification** are a separate magic-item usage session, so found magic items stay 0-XP / non-sellable (`value_cp -1`). Tested: `tests/test_magic_item_catalog.gd` + a catalog-resolution test in `tests/test_treasure_instantiator.gd`.
- **Phase 2.5 (magic-item prices): ✅ LANDED 2026-05-29 (§9.1).** Every catalog item gains `value_gp` + `creation_time_days` (forum/SACRED crafting-cost prices); Ring of Protection → 5 priced `sub_roll` variants; Spell Scroll → `scroll_of_spells` generator (price = 500 × Σ levels); cursed=0, vorpal=60,000, sweet_water=500. `TreasureInstantiator` stamps `value_cp`; `ShopService` sells priced magic items. Tested: `tests/test_magic_item_catalog.gd` (12 tests) + `tests/test_treasure_instantiator.gd` (+resolved-price + DB magic-sale tests).
- **Phase 3 (magic-item market + identification + special treasures):** market-class gating for high-value magic sales; identification flow; per-item effects/charges + binding named spells to scrolls; special-treasure generation consuming the `trade_good` category (§10).

---

## 13. Open Questions / Architectural Concerns

- **Jewelry encumbrance (RAW gap — RESOLVED 2026-05-28):** Jedidiah ruled jewelry weighs **1 unit (1/1,000 stone)**, same as coins and gems (§7). No longer blocks Phase 1. Recorded as a project decision filling the RAW gap (the encumbrance table at `rules/acore_equipment.xml:586` names only "coins or gems"); options (b) 1/6 stone and (c) 1 stone were considered and declined.
- **`inventory_items` schema change requires approval:** adding `value_cp` is a data-model change. Per `CLAUDE.md` / the design brief, the build agent "may NOT … change data models … without explicit approval from Jedidiah." This GDD is the approval request; migration 134 should not land until approved. Backward compatibility is confirmed safe in §4.1 (non-destructive `ADD COLUMN` with sentinel default; the same pattern that added `encumbrance_units` in migration 014; naming follows the migration-108–116 `_cp` convention).
- **Value column vs. dual-purpose `cost_cp`:** the proposal keeps catalog `cost_cp` as the mundane-equipment value and adds `value_cp` only for rolled valuables (sentinel `-1` = "use catalog"). The alternative — backfilling `value_cp` for *every* item from the catalog — was rejected as a needless migration with a drift risk (catalog price changes wouldn't propagate). Confirm the sentinel approach is acceptable.
- **`gdd-party-inventory.md` already assumes valued valuables exist** (cache-raid example "1 ruby (total value 450 GP)"; value-loss sorts by `cost_cp`). Once `value_cp` lands, that GDD's value-loss logic should sort by `effective_value_cp`, not raw `cost_cp` — a small companion edit, flagged so it isn't missed.
- **Overlap with `gdd-phase-10b-2-trade-block.md`:** special-treasure goods (§10) are trade goods; whether they sell through the equipment shop (`value_cp`) or the mercantile load system needs a routing decision when Phase 3 lands. Not blocking Phase 1/2.
- **Magic-item sale economy — RESOLVED 2026-05-29 (§9.1).** Found magic items now sell at `value_gp`, sourced from the game creator's price list (the ACKS crafting-cost model) and cross-validated against the SACRED creation formula — NOT an invented flat price, so no XP/GP-balance distortion. Remaining (Phase 3): market-class gating for high-value sales, identification, per-item effects, and binding specific named spells to generated scrolls. Recovery XP for magic items stays 0 by RAW.
- **Spell-scroll count distribution — RESOLVED 2026-05-29:** Jedidiah supplied the RAW scrolls d100 table; the `scroll_of_spells` generator now weights the spell count by its "Spells (N)" sub-band (rows 41-76). The same table's **treasure-map subtypes** (rows 77-100, leading to reward hoards) remain a deferred feature (§9.1), as does driving scroll *type* selection off the full d100.
- **Vorpal Sword — RESOLVED 2026-05-29:** 160,000 gp / 590 d (the vorpal portion is a 5th-level Permanent/Unlimited effect, 125,000 gp / 500 d, atop the Sword +3 base 35,000 gp / 90 d).
- **Magic-item catalog — RESOLVED 2026-05-28 (Jedidiah):** Core's `random_magic_type_table` + `random_item_tables` (`:197-216`) are sufficient for the V1 catalog (item NAMES + categories). The absent "full d00 distributions" only affect per-item *roll probabilities*, which V1 approximates with **uniform within-category selection** (documented in the catalog `_note`). Per-item **effects / charges / identification** are out of scope for the catalog and belong to a dedicated magic-item usage session; until then found magic items are carriable + 0-XP + non-sellable (`value_cp -1`). Built via `tools/extract_magic_item_catalog.py` → `data/treasure/magic_item_catalog.json` (§9).
- **No banker's-rounding hazard in Phase 1:** gem/jewelry gp values are integers, so `value_cp = value_gp × 100` is exact. Any future fractional value (sale fractions, haggling) must use `XPAwardCalculator.bankers_round` per the project-wide convention.

---

## 14. Magic-item combat effects (status board)

Per-item effects are landing incrementally as the magic-item-usage work continues. Status snapshot:

| Effect | Path | Status |
|---|---|---|
| Weapon +N → attack throw | `attack_resolver.gd:67` `get_weapon_magical_bonus()` | ✅ wired (pre-existing); regression-locked 2026-05-29 |
| Weapon +N → damage | `attack_resolver.gd:147/163-165` | ✅ wired (pre-existing); regression-locked 2026-05-29 |
| Armor +N → AC | `CharacterAcCalculator.compute()` — `magical_bonus` term (§75) | ✅ landed 2026-05-29 (AC fix session) |
| Shield +N → AC | same | ✅ landed 2026-05-29 |
| Cursed (negative `magical_bonus`) → penalty | same +N paths above (signed math) — locked by `test_cursed_weapon_negative_bonus_subtracts_from_attack` | ✅ landed 2026-05-29 |
| Cursed item sticky-unequip | `inventory_items.is_cursed` (migration 136) + `CampaignRepository.update_inventory_item_equip_state` pre-check | ✅ landed 2026-05-29. RAW: `:235` "Cursed items cannot be discarded except by dispel evil or remove curse." Catalog flags 6 items: `cursed_sword`/`armor`/`shield` (magical_bonus -1, project default — RAW silent on magnitude) + `cursed_scroll` + `ring_of_delusion` + `ring_of_weakness` (magical_bonus 0; non-numeric curse effects deferred to per-item-effects pass). 2 trap items NOT sticky: `potion_of_delusion` (consumable), `bag_of_devouring` (container). Remove Curse / Dispel Evil interaction is a manual `UPDATE is_cursed = 0` for now — spell wiring is the spell-effects pass. |
| Magic/silver required to harm "invulnerable" monsters | `Combatant.can_harm_invulnerable_target()` + pre-roll check in `attack_resolver` / `ranged_attack_resolver` | ✅ logic landed 2026-05-29. Catalog data flagged 2026-05-29: **25 canonical invulnerable monsters** carry `damaged_only_by_magic_or_silver: true` — wraith, shadow, spectre, gargoyle, mummy, djinni, efreeti, demon_boar, all 5 lycanthropes (silver-or-magic per L&E :297), all 12 elementals (4 types × 3 tiers). Excluded for now (no RAW confirmation found in the corpus): vampire, wight, ghoul. End-to-end test (`test_real_catalog_wraith_is_flagged_invulnerable`) verifies the flag flows from JSON → Combatant → resolver. |
| Magic ammo (e.g. Magic Arrows +1) counts toward magic-to-hit | `Combatant.get_ammo_magical_bonus()` | ✅ landed 2026-05-29 |
| Ranged magic weapon +N → to-hit & damage | `ranged_attack_resolver.gd` (weapon + ammo `magical_bonus` added to both terms) | ✅ landed 2026-05-29 (Jedidiah: apply RAW uniformly — no split). Bow + ammo bonuses stack; thrown weapons see only the weapon's +N (no separate ammo). |
| Ring of Protection — wearer-only AC + saves | `WornMagicEffectResolver` (`engine/subsystems/inventory/worn_magic_effect_resolver.gd`) applies a `worn_magic:<item_id>` modifier on each of `armor_class` (+N) and the 5 save keys (-N, because saves are target numbers — lower is better) when the ring is equipped; refresh fires at `Combatant.wire_equipment` (combat-start safety net). Stacks with Cloak of Protection per RAW `:264`. | ✅ landed 2026-05-29 (7 tests in `test_worn_magic_effect_resolver`). |
| Ring of Protection 5'-radius save bonus to allies | (planned: combat-geometry + save-time modifier; `radius_effect` already recorded on the catalog +2/+3 5'-radius variants) | ⏳ deferred (follow-up; needs ally-targeting at save resolution time) |
| Cloak of Protection — +N AC + saves (cumulative with Ring of Protection) | same `WornMagicEffectResolver` — shares the `_apply_ac_and_saves_bonus` builder with Ring of Protection. Catalog magnitude project-default +1 (stamped via the extractor's `EXPLICIT_BONUS` map). | ✅ landed 2026-05-29; 2 new tests cover the wearer effect + the RAW :264 cumulative stack |
| Ring of Water Walking — wearer-only `can_water_walk` flag | `WornMagicEffectResolver` sets the `can_water_walk` `EntityFlag` with a `worn_magic:<item_id>` source; the prefix-clear in `refresh_for_character` sweeps it on unequip alongside the ModifierContainer entries. | ✅ landed 2026-05-29; 2 new tests cover equip / unequip lifecycle |
| Ring of Fire Resistance — +2 to fire saves | `WornMagicEffectResolver` adds a -2 modifier on `save_blast_breath` (saves are target numbers; lower = better). V1 simplification: applies to all blast/breath saves until the engine models save-by-element. The 1/die fire-damage reduction + ordinary-flame immunity from RAW are deferred to a damage-typing pass. | ✅ landed 2026-05-29 (V1); 1 new test pins the +2 save delta |
| Bracers of Armor — +N flat AC | `WornMagicEffectResolver._add_bracers_of_armor` — flat AC modifier (no save bonus, distinguishing from Ring / Cloak of Protection). Stacks with both per RAW. Project default magnitude +1 (stamped via the extractor's `EXPLICIT_BONUS` map). Future +2/+3 variants land via a sub_roll. | ✅ landed 2026-05-29 (Tier 3 V1); 2 new tests cover the wearer effect + cumulative stack with Cloak + Ring |
| Boots of Speed — set_floor 80'/round (= RAW 240'/turn) | `WornMagicEffectResolver._add_boots_of_speed` — `set_floor` operation on `movement_rate` with `BOOTS_OF_SPEED_MOVEMENT_TARGET = 80`. Clamps effective movement to ≥ 80 regardless of encumbrance; survives Haste's multiply (multiply runs before set_floor in evaluation order). RAW 12-hour duration + post-use exhaustion deferred (no timer/fatigue subsystem). | ✅ landed 2026-05-29 (Tier 3, RAW-corrected); 3 tests cover at-least-80 across all encumbrance tiers, set_floor doesn't clamp down for fast movers, and unequip clear |
| Cursed Bracers of Armor — AC set to 0 | `WornMagicEffectResolver._add_cursed_bracers_of_armor` uses the new `set` operation with `CURSE_PRIORITY = 100`. Replaces armor_class entirely (overrides DEX, Ring/Cloak of Protection, base armor) per RAW "lowers wearer's AC to 0 regardless of DEX modifiers or magical means of lowering AC". The is_cursed flag on the inventory row triggers sticky-equip (remove-curse required) per the existing mechanic. | ✅ landed 2026-05-29 (Tier 3); the d100 sub_roll table's 5% cursed band materializes this variant; 2 tests cover the AC-to-0 effect + curse dominance over Ring + Cloak |
| Gauntlets of Ogre Power — STR set to 18 | `WornMagicEffectResolver._add_gauntlets_of_ogre_power` uses the new `set` op with `GAUNTLETS_OF_OGRE_POWER_STR = 18` (project default; flagged for Jedidiah ruling on exact ACKS Core value). Overrides natural STR regardless of value. | ✅ landed 2026-05-29 (Tier 3); 2 tests cover STR-to-18 across natural STR 8/10/14/16/18 and unequip restore |
| Girdle of Giant Strength — attack as 8 HD monster | `WornMagicEffectResolver._add_girdle_of_giant_strength` applies `set_ceiling: 3` on `attack_throw` (the 8 HD attack-throw value from the ACKS monster table). Wearer's effective attack target is `min(natural, 3)` per RAW "wearer attacks as an 8 HD monster OR own class/level, whichever is better." | ✅ landed 2026-05-29 (Tier 3 V1, partial); 3 tests cover clamp-to-3, no-worsening-better-throws, unequip restore. **Deferred RAW parts:** damage doubling (needs damage-multiplier hook in attack resolver), +16 force-doors bonus (no force-doors stat), 3d6 thrown rocks at 200' (new ability — granted ranged attack option) |
| Wand of Fear — cause_fear | Binds to `cause_fear` (synthesized reverse of `remove_fear`; SpellRegistry auto-redirects). Routes through `MagicItemActivator.activate_charged_item` with 20 default charges, `single_creature` target. Divine L1 reverse → caster level 1. | ✅ landed 2026-05-29 (Tier 3 unblock — Jedidiah confirmed cause_fear is the reverse of Remove Fear); 1 end-to-end test covers binding shape, registry availability, and a target-creature activation with charge decrement |
| Bag of Holding — extradimensional fixed-weight container | Catalog entry stamps `is_extradimensional: true` + `capacity_units: 100,000` (100 stone) + `own_weight_units: 6,000` (6 stone fixed per RAW "regardless of what is put into the bag"). Materialized inventory_items row carries `is_extradimensional=1`. `EncumbranceCalculator` reports the bag's aggregate as 6,000 only, ignoring contents weight. | ✅ landed 2026-05-31 (Tier 4); catalog shape test pinned via `test_catalog_shape_for_both_bags`; runtime behavior verified by the `test_extradimensional_container_*` suite from the sub-carrier refactor |
| Bag of Devouring — extradimensional + 6+1d4 turn timer | Catalog entry identical to Bag of Holding (indistinguishable from outside) plus `is_devouring: true` flag. Runtime is `BagOfDevouringService` with: `start_timer_on_first_item` activates the timer when first item is placed in empty bag (sets `inventory_items.devouring_at_turn = current_turn + 6 + 1d4`); `try_devour_if_expired` deletes all contents + resets timer when current turn ≥ devouring_at_turn; `find_expired_bags` scans the active campaign on every `Timekeeping.turn_advanced` (subscribed by `LocationCacheManager`). Project simplification per Jedidiah 2026-05-31: timer starts on first item into empty bag; additional items mid-cycle don't reset; partial removal mid-cycle doesn't reset; bag goes empty (devour or last-removal) → timer resets for next cycle. | ✅ landed 2026-05-31 (Tier 4); migration 140 adds `devouring_at_turn`; new suite `BagOfDevouringServiceTests` (9 tests) covers activation, non-reset on additional items, non-reset on partial removal, reset on empty, devour at expiration, find_expired_bags filtering, and non-devouring-item guards |
| Container capacity enforcement | Migration 141 adds `capacity_units` to inventory_items. `update_inventory_item_equip_state` calls `_check_container_capacity` when an item is being placed into a container: if `capacity_units > 0`, sums current contents + new item's encumbrance_units and refuses the transfer if it exceeds the cap. `capacity_units = 0` (the mundane default) means unlimited. Stamped on the catalog via `container_behavior.capacity_units` (Bag of Holding/Devouring = 100,000 units = 100 stone). Sub-carrier-aware: uses each item's OWN weight, so a Bag of Holding placed inside a backpack consumes only 6 stone of the backpack's budget regardless of what's in the Bag. | ✅ landed 2026-05-31; 2 new tests in `BagOfDevouringServiceTests` cover refuse-on-overflow + zero-means-unlimited |
| TreasureInstantiator container stamping | `TreasureInstantiator._resolve_magic` reads the catalog's `container_behavior` block when present and overrides `item_category` to `"container"` + propagates `is_extradimensional` + `capacity_units` into the materialized item dict. So a Bag of Holding rolled from a hoard arrives in inventory with all three container fields stamped correctly. | ✅ landed 2026-05-31; 1 new test sweeps 500 seeds to land on a bag and asserts the stamped shape |
| Bag of Devouring transfer-hook timer | `update_inventory_item_equip_state` checks the target container against `BagOfDevouringService.is_bag_of_devouring`; if true, calls `_maybe_start_bag_of_devouring_timer` which invokes `start_timer_on_first_item` (which itself short-circuits if the bag is non-empty). Single integration point — UI drag-drop, programmatic transfers, and any future inventory mutation path all flow through the same gate. Production rolls go through `DiceSystem.roll_digital(4, 1, 6, "bag_of_devouring_timer")` (project deterministic-seed pattern); tests force the rolled offset via `GameState.dice_overrides[BagOfDevouringService.DEVOURING_TIMER_ROLL_TYPE] = N` where N is the final modified_total (7-10). | ✅ landed 2026-05-31; 2 transfer-hook tests + 1 dice-override determinism test |
| Capacity-refusal "Won't fit" notification | When `_check_container_capacity` refuses a transfer, `update_inventory_item_equip_state` emits `EventBus.notification_requested` with `{type:"warning", category:"encumbrance", title:"Won't fit", body:"<item> won't fit in <container>."}` before the engine-log push_warning. NotificationManager surfaces it in the UI so the player sees why their drag-drop didn't land instead of having to read the engine log. | ✅ landed 2026-05-31; 1 new test subscribes a transient listener and asserts shape (category=encumbrance, type=warning, title=Won't fit, body mentions both names) |
| Mundane container capacity via EquipmentCatalog fallback | `_check_container_capacity` resolution order: (1) inventory row's `capacity_units`, (2) EquipmentCatalog `container_capacity_units` keyed by item_key, (3) 0 → unlimited. base_equipment.json already declares mundane caps (backpack 4000, pouch 500, sack_small 2000, sack_large 6000, chest_ironbound 20000); no new authoring needed. CampaignRepository lazy-caches an `EquipmentCatalog` instance to amortize the 3-JSON parse across capacity checks. | ✅ landed 2026-05-31; 1 new test covers backpack 4-stone cap + pouch 1/2-stone cap end-to-end through the transfer path |
| Charged items (wands, staves, rods) — use / depletion | `MagicItemActivator.activate_charged_item` — routes through `CastingResolver` via the catalog's `spell_binding` field (see §16); decrements `uses_remaining` on success; clears `is_magical` at 0 charges (RAW: "useless and non-magical") | ✅ landed 2026-05-29 for 11 wand/staff items; rest deferred until Jedidiah disambiguates the ACKS RAW item descriptions |
| Worn-triggered items (rings, helms, boots, broom, chime) — activate on demand while equipped | `MagicItemActivator.activate_worn_item` — same `spell_binding` pipeline; equipped-state check + no consumption (V1 = unlimited uses). Per-day cooldowns + RAW per-item-charge limits are a follow-up. | ✅ landed 2026-05-29 for 10 items (Ring of Invisibility / Telekinesis / Command Human, Boots of Levitation, Broom of Flying, Chime of Opening, Eyes of Charming, Helm of Comprehending Languages / Telepathy / Teleportation) |
| Per-potion effects (drink → effect) | `MagicItemActivator.drink_potion` — routes through `CastingResolver` via the catalog's `spell_binding` field (see §16) | ✅ landed 2026-05-29 for 13 V1 potions; rest deferred until Jedidiah disambiguates the ACKS RAW potion descriptions |
| Decanter of Endless Water — wilderness water auto-refill | `DecanterRefillService.refill_party_water` (`engine/subsystems/inventory/decanter_refill_service.gd`) — called from `WildernessHandlers._handle_wilderness_noon_tick` after the river-hex refill. Mirrors `_refill_water_at_hex`: tops up `party.water_units` by OUTPUT_PER_TICK_UNITS × decanter_count per tick, clamped at `party_size` (one day's draw). Multiple decanters stack additively. Counts decanters in both per-character inventories AND the party shared pool. RAW project rules XML extract is silent on output rate; project default = 1 person-day per tick per decanter [NEEDS-JEDIDIAH] to confirm. | ✅ landed 2026-05-30 (8 tests in `test_decanter_of_endless_water`) |
| Oil of Slipperiness — applied surface coat (creature OR 10' x 10' patch) | `SurfaceCoatResolver` (`engine/subsystems/inventory/surface_coat_resolver.gd`) — generic over a `coat_spec` Dictionary describing the coat mechanic. `MagicItemActivator.apply_oil(item_id, catalog, tracker, mode, target_creature?, map_id?, anchor_cell?, surface_conditions?)` routes oils (item_key prefix `oil_`) to the resolver. Creature mode sets the `is_slippery_self` `EntityFlag` (RAW: cannot be restrained / grabbed by grasping attacks per `rules/pc_spell_catalog_f-u.xml:1056-1067`). Cell mode applies the `slippery` condition to a 2x2 cell patch via the new `CellSurfaceConditions` runtime registry (RAW: proficiency throw 20+ each round or fall down). Duration 3 turns (matches the Slipperiness spell the oil derives from). Dose consumed on success only; failed application preserves the dose. Multi-source semantics: two oils on the same target keep distinct source_ids and both contribute to the flag boolean. The `coat_spec` shape is REUSABLE: a future Grease spell wires its mechanic by passing a different spec (different `flag_key` / `condition_key`, different duration) — the resolver itself is mechanic-agnostic. | ✅ landed 2026-05-30 (18 tests in `test_oil_of_slipperiness`). Object-mode application (Slipperiness spell's "20 arrows / 2 1H / 1 2H weapons" branch) is wired with a clear "not implemented" failure until the attack-throw consumer reads coat state. Movement-resolver hook for the per-cross save throw + grapple-resistance hook for the creature-mode flag are deferred to consumer integration. |
| Amulet versus Crystal Balls and ESP — anti-scrying flag | `WornMagicEffectResolver._add_amulet_versus_crystal_balls_and_esp` sets the `is_nondetectable` EntityFlag (already declared at `engine/shared_types/entity_flags.gd:26`) while equipped, sourced by the `worn_magic:<item_id>` prefix so unequip clears it via the existing prefix-sweep. RAW source: spell `pc_spell_catalog_f-u.xml:556-571` Nondetection ("Protects the target from crystal balls and any type of ESP. Used to create amulets versus crystal balls and ESP"); + DaW army-scale citation `daw_campaigning_armies.xml:478-488` ("officer is protected by amulet... cannot be scryed upon"). Forward-looking flag — no scrying-system consumer is wired yet; mirrors Ring of Water Walking's flag-set pattern (set now, consumer integration follows). Stamped via `WORN_PASSIVE_FLAGS` map in the extractor. | ✅ landed 2026-06-01 (Tier 4 Cluster A); 3 tests cover catalog shape + equip-sets-flag + unequip-clears-flag |
| Rod of Cancellation — drain magic item on touch | `MagicItemActivator.apply_rod_of_cancellation(rod_id, wielder, target_item_id, catalog)` — dedicated entry point (does NOT route through CastingResolver because the rod doesn't replay a spell). Target item is set to `is_magical=0, magical_bonus=0, uses_remaining=0, is_cursed=0` in a single transaction; rod consumes one charge per successful drain (same accounting as `activate_charged_item`); rod becomes useless and non-magical at 0 charges per RAW. Refuses to drain non-magical items (no charge consumed) and refuses to drain itself. RAW citations: `pc_magic_experimentation.xml:244-246, 327-329` ("Drain one magic item of all power, as if touched by a rod of cancellation" — the explicit functional description used by the mishap tables); `acore_treasure_and_magic_items_rules.xml:213` lists the rod without a dedicated mechanic entry. **Project default magnitude:** `default_charges: 5` (RAW silent; conservative midpoint of the Life Drinker `1d4+4` analog at `acore_treasure_and_magic_items_rules.xml:255`). Stamped via the extractor's `SPECIAL_CHARGED_EFFECTS` map; `TreasureInstantiator` reads top-level `default_charges` (extended this commit to support non-spell-binding charged items). [NEEDS-JEDIDIAH-RULING] on the canonical charge count. | ✅ landed 2026-06-01 (Tier 4 Cluster A); 6 tests cover catalog shape, drain effect, charge decrement, zero-charge gate, becomes-inert-at-zero, non-magical-target refusal, self-drain refusal |
| Potion of Poison — save vs Poison & Death or die | `MagicItemActivator.drink_potion` checks for `direct_potion_effect` BEFORE the spell_binding branch; routes to `_resolve_direct_potion_effect`. `effect_kind = "save_or_die_poison"` rolls `DiceSystem.roll_digital(20, 1, 0, "save_vs_poison_potion")` against the drinker's effective `save_poison_death`; failure sets HP to -max_hp (well below the -10 "instantly killed" floor per `ax_mortal_wounds_and_tampering.xml:396`); emits `EventBus.hp_changed` + `EventBus.damage_dealt`. The bottle is consumed in BOTH outcomes (the drinker already drank it — success means the body resisted, not that the dose was preserved). RAW: `acore_treasure_and_magic_items_rules.xml:253` poison_potion rule "Poison effect resolves according to the source potion description and relevant saves." Standard ACKS "save vs Poison or die" pattern (e.g. `acore_monster_catalog_a-dop.xml:258`). Tests force the save outcome via `GameState.dice_overrides["save_vs_poison_potion"]`. | ✅ landed 2026-06-01 (Tier 4 Cluster A); 4 tests cover catalog shape, save-success-survives, save-failure-dies, consumed-in-both-outcomes |
| Displacer Cloak — +2 AC (no save bonus) | `WornMagicEffectResolver._add_displacer_cloak` applies a flat `+magical_bonus` AC modifier with `worn_magic:<item_id>` source, no save effect. Stamped via `EXPLICIT_BONUS` map at magnitude 2 (project default from the phase tiger analog). RAW: `acore_treasure_and_magic_items_rules.xml:266` says only "Creates displacement effect making wearer harder to hit." Closest in-corpus mechanic: phase tiger `phase_illusion` (`acore_monster_catalog_owl-sco.xml:236-248`, `le_monster_catalog_summary_3.xml:231-233`): "Projects an illusion 3' from where it actually stands. All opponents suffer -2 to attack throws." -2 attack-throw penalty is equivalent to +2 AC (ACKS AC is the modifier added to the attack-throw target). The phase tiger's +2 saves part is NOT applied — that's phase-tiger-specific, not displacement per se. [NEEDS-JEDIDIAH-CONFIRMATION] on the magnitude + saves-vs-no-saves choice. | ✅ landed 2026-06-01 (Tier 4 Cluster A); 4 tests cover catalog shape, AC bonus on equip, no save bonus, AC cleared on unequip |
| Potion of Gaseous Form — bound to gaseous_form spell | (planned: bind once the gaseous_form spell effect block is implemented per RAW `pc_spell_catalog_f-u.xml:90-126` — Arcane L3, sets `is_gaseous` flag, drops carried items, AC 11, movement 30'/round, immune to non-magical weapons). | ⏳ deferred 2026-06-01 — the gaseous_form spell catalog entry has an empty `effect` block (one of 150 such in the catalog); CastingResolver refuses to fire spells without an effect_registry payload. Stamped in DEFER_BUILD; binding is a one-line addition once the spell-effect pass lands. 1 test pins the deferred-message behavior (no spell_binding → fails cleanly without consuming the bottle). |
| Spell-scroll specific-spell binding | (planned: pick named spells from the spell catalog at instantiation) | ⏳ deferred |
| Identification (sage / Magic Research / Loremastery) | (planned: `requires_identification` flag + identify subsystem) | ⏳ deferred (Phase 3) |
| Magic-item market-class gating | (planned: gate high-value sales by settlement class) | ⏳ deferred (Phase 3) |

**RAW anchors:** `acore_treasure_and_magic_items_rules.xml:231-235` (the +N rule); `acore_combat_and_wounds.xml:402-407` (invulnerable monsters); `acore-campaign-general-and-magic-research.xml:185-215` (creation cost formula backing the +N values).

### 14.1 Container-as-sub-carrier architecture (2026-05-31)

**Status: ✅ landed.** Prerequisite refactor for magic containers (Bag of Holding, Bag of Devouring, Portable Hole, future extradimensional items). Jedidiah 2026-05-31 verified that the prior container model was a UI-grouping illusion — every item with `character_id = X` summed flat into the bearer's encumbrance regardless of `container_id` nesting.

**The new model:** containers are sub-carriers. `EncumbranceCalculator.calculate_encumbrance` filters items by `container_id` — loose items (top-level) contribute directly, and each container item contributes its aggregate weight per its own rules:
- **Mundane container aggregate** = own weight + recursive sum of contents' aggregates (nested containers supported).
- **Extradimensional container aggregate** = own weight ONLY (migration-139 `is_extradimensional` flag on `inventory_items`). Contents are weightless to the bearer regardless of how much is inside, matching RAW Bag of Holding semantics ("regardless of what is put into the bag, it weighs a maximum of 6 stone").

**Backward compatibility:** flat inventories with NO containers behave identically to the pre-refactor flat sum. Every existing test in `test_encumbrance.gd` (which all use flat inventories) keeps passing.

**Implementation files:**
- `db/migrations/139_inventory_item_is_extradimensional.sql` — new column on `inventory_items`.
- `engine/shared_types/inventory_item.gd` — `is_extradimensional` field + from_dict/to_dict threading.
- `engine/autoloads/campaign_repository.gd` — `add_inventory_item` accepts the flag in the data dict.
- `engine/subsystems/characters/encumbrance_calculator.gd` — `_sum_with_containers` orchestrator + `_calculate_container_aggregate_weight` recursive helper.

**Tests:** 7 new in `tests/test_encumbrance.gd` covering mundane container + contents, empty container, extradimensional contents-weightless, extradimensional with overweight contents, nested mundane, nested extradimensional in mundane, flat-inventory backward-compat regression.

**Side-effect benefits beyond magic bags:** locked chests can be carried out of a dungeon with known weight (RAW-correct hidden contents); saddlebags / panniers track their own load independently of the mount; pouches inside backpacks no longer get double-counted via the chest's container_id linkage from migration 138.

**Catalog-flag-driven combat rules pattern.** The invulnerable-monster work established the pattern: a boolean field on the monster catalog data → set as a flag in `_apply_monster_catalog_flags` → read via a `Combatant` helper → consumed by a pre-roll check in the resolver. Reusable for any future "this monster property modifies the to-hit/damage path" rule.

---

## 15. Cell-based interactable treasure containers (complete)

**Status (2026-05-29):** ✅ arc complete (5 of 5 commits landed). Pick Lock + Search container action wiring is the natural follow-up; the handler surfaces locked / hidden state via presentation types so the UI can prompt without further handler changes.
- Foundation: migration 137 + `TreasureContainerTypes` catalog + `TreasurePlacementService` (cell + container_type + lock + 25%-split + trap-fallback) + 12 tests.
- **DG-V1 integration (Commit 2):** `DungeonStocker.stock_floor` now runs a **Pass D** that calls `TreasurePlacementService.place_hoard` on every hoard the prior passes accreted (Pass B treasure-type hoards, Pass B special-monster treasure already folded in). The placement service mutates the primary in place and may emit a secondary (the 25% split case) which gets a freshly-generated `id` and is appended to `layout.treasure_hoards`; `room.treasure_hoard_id` is re-pointed at the visible primary. `DungeonGeneratorRepository._insert_treasure_hoards` / `_row_to_treasure_hoard` extended to round-trip the 6 new columns. New tests assert every persisted hoard has a valid cell + container_type, lands on one of its room's cells, trap-room hoards are locked chests, pile hoards never lock/trap, and the V1 trap-fallback (traps_available=false → no is_trapped=true) holds. The placement service now normalizes input `room_cells` to an internal untyped Array of Vector3i at the API boundary, so it accepts the dungeon generator's `Array[Vector2i]` (2D grid) and the service's own `Array[Vector3i]` tests interchangeably.
- **First-visit materialization (Commit 3):** migration 138 adds `is_locked` + `is_trapped` to `inventory_items` so chest/barrel/sack hoards can materialize into a backing inventory_items row that IS the container, carrying lock/trap state forward. `TreasureLootService.materialize_hoard_cell(dungeon_id, floor_id, cell)` is the entry point: idempotent (returns the existing cache if any), no-op when there's no unlooted hoard at the cell, branches to `loose` cache (no container item) for piles and `locked_container` cache (with `container_item_id` linked to the backing chest row) for chests/barrels/sacks. The `locked_container` variant now means "has a backing container item" rather than "is locked" — lock state lives on the container item itself, so an unlocked chest still uses this variant. New `DungeonGeneratorRepository.get_unlooted_treasure_hoard_at_cell(floor_id, cell)` finds the at-most-one hoard per cell. Coins + items materialize into the cache exactly like `claim_room_hoards` does today, scoped to ONE hoard. Hoard `is_looted=1` is set after the cache builds (defense-in-depth on top of the cache-exists idempotency check).
- **Per-cell interaction (Commit 4):** `DungeonHandlers._resolve_loot` reworked into the cell-based path. It now (a) normalizes the action's `cell` to Vector3i (using the dungeon controller's current floor for the z when the cell is 2D), (b) bridges cell.z → `floor_id` via new `DungeonGeneratorRepository.get_floor_id_for_voxel_level`, (c) calls `materialize_hoard_cell` to lazy-promote any placed hoard (the materializer handles existing player-drop caches too), (d) gates on `is_hidden` (returning "Nothing visible here." without materializing — the hoard stays unlooted for a future Search-reveal), (e) gates on `is_locked` (returning a new `open_loot_modal_locked` presentation carrying the container_item_id so the UI can route to a Pick Lock prompt), and (f) opens the loot modal on the cache otherwise. The materializer's return shape gained `is_hidden`. The location_key format upgraded from 2D to 3D (legacy `dungeon:<id>:cell:x,y` → canonical `dungeon:<id>:cell:x,y,z`). A multi-floor z-coordinate bug from Commit 2 (every floor's hoards landed at z=0) was fixed by promoting `room.cells` to Vector3i with `level_number - 1` before passing to the placement service. New `tests/test_dungeon_handlers_resolve_loot.gd` (6 DB-backed tests covering no-cache, no-hoard, unlocked pile, locked chest, hidden hoard non-materialization, and idempotent re-loot).
- **Retirement of `claim_room_hoards` (Commit 5):** the room-level service deprecated by the cell-based flow is gone. `TreasureLootService.claim_room_hoards` deleted along with its 2 tests in `test_treasure_instantiator.gd`; the file's top-of-docstring and the still-relevant private helpers (`_cache_coins`, `_cache_items`, `_magic_catalog`) updated to describe the cell-based contract. No production callers existed at retirement time — `materialize_hoard_cell` had already taken over via `_resolve_loot` (Commit 4).

**Replaces (in progress)** the room-level *"enter Room #4 → claim-all-treasure modal"* model with **per-cell interactable containers** placed at dungeon generation. Each hoard becomes one or two physical objects in the dungeon (a chest, a barrel, a sack, a pile of loose coins, a pile of loose gear) at specific cells; players walk up to them and interact individually.

### 15.1 Container types (V1)

`engine/subsystems/inventory/treasure_container_types.gd` — constants + capability flags.

| Type | can_lock | can_trap | can_hide | Notes |
|---|---|---|---|---|
| `chest` | ✓ | ✓ | ✓ | Sturdy opaque container; the default for valuables. |
| `barrel` | ✓ | ✓ | ✓ | Opaque, bulky; good for big coin piles. |
| `sack` | ✓ | ✗ | ✓ | Small opaque pouch; coins/gems. Locked = tied/sealed. |
| `coin_pile` | ✗ | ✗ | ✓ | Loose coins visible on the floor; nothing to lock or trap. |
| `gear_pile` | ✗ | ✗ | ✓ | Loose gear; same constraints as coin_pile. |

Extensible — future types (urn, weapon_rack, altar, pedestal, bookcase) plug into the same flag schema.

### 15.2 Placement rules (per-hoard, at generation)

For each rolled hoard, `TreasurePlacementService.place_hoard(hoard, room_cells, rng, opts)` returns **1 or 2** placed hoards:

- **Source `unprotected_trap_placeholder`:** the whole hoard → one **trapped chest** (the chest IS the trap). With `opts.traps_available = false` (V1) the chest emits as **locked-only** per the trap-fallback guardrail.
- **Source `lair`:** 40% chance to split per the **25% rule** (the secondary holds ≤ 25% of total gp + optionally one magic item; the primary keeps ≥ 75%). The visible primary picks a container by content profile (magic item → chest/barrel; jewelry/gems → chest/sack; lots of coins → barrel/chest; small coins → coin_pile/sack/chest; mostly gear → gear_pile/chest) and may carry a lock by value (60% if > 1000 gp, else 30%). The secondary prefers chest and rolls one of {hidden / trapped / hidden+trapped} — trapped variants degrade to locked under the trap-fallback.
- **Source `unprotected_empty` / `unprotected_unique_placeholder`:** a single plain visible container, no lock / trap / hide.

### 15.3 The 25% rule (project constraint, Jedidiah 2026-05-29)

> Treasure rolled as part of a monster's hoard must never have more than **25% of its gp value** in hidden and/or trapped containers.

Implementation: when splitting a lair hoard, `_split_25_percent` moves ≤ 25% of the hoard's gp into the secondary by peeling off coins (highest denomination first) and optionally moving one magic item (RAW: 0 gp for XP/recovery, so it doesn't bust the cap). `primary.total_gp_value + secondary.total_gp_value == original.total_gp_value` (banker's rounding). Tests pin this invariant across all split seeds.

### 15.4 Trap-fallback guardrail

When the traps system isn't available (`opts.traps_available = false`, the V1 reality) or trap generation errors, any container that would be trapped is emitted with `is_trapped = false` + `is_locked = true` — the would-be-trapped chest becomes a **locked chest**, and seamlessly re-upgrades to trapped when the traps system lands. This guarantees the dungeon always has well-defined container state regardless of traps system availability.

### 15.5 Trapped room → trapped container (Jedidiah 2026-05-29)

> Treasure in a "trapped" room should be in a trapped container (that is the trap).

Honored: when `hoard.source == SOURCE_UNPROTECTED_TRAP`, the whole hoard goes into ONE chest with `is_trapped = traps_available, is_locked = true`. No split (the trapped chest IS the room's reason for existence).

### 15.6 Schema additions (migration 137)

Added to `treasure_hoards`:
- `cell_x`, `cell_y`, `cell_z INTEGER NOT NULL DEFAULT -1 / -1 / 0` (sentinel = not placed).
- `container_type TEXT` (nullable; CHECK enum = the 5 V1 types).
- `is_locked`, `is_trapped INTEGER NOT NULL DEFAULT 0` with 0/1 CHECK.

`is_hidden` (existed since migration 132) is honored — hidden hoards' containers don't render on the dungeon map until a Search action reveals them.

### 15.7 Open work

- **DG-V1 integration: ✅ LANDED 2026-05-29** — Pass D in `DungeonStocker.stock_floor` calls the placement service on every accreted hoard; persistence round-trips all six new columns.
- **First-visit materialization: ✅ LANDED 2026-05-29** — migration 138 (`inventory_items.is_locked` + `is_trapped`); `TreasureLootService.materialize_hoard_cell(dungeon_id, floor_id, cell)` creates a `loose` cache for piles and a `locked_container` cache for chest/barrel/sack with a backing inventory_items row. Idempotent. Marks the hoard looted on success.
- **Per-cell interaction: ✅ LANDED 2026-05-29** — `DungeonHandlers._resolve_loot` rewritten to call `materialize_hoard_cell` first, gate on `is_hidden` (returns "Nothing visible here.") and `is_locked` (returns the new `open_loot_modal_locked` presentation), and open the loot modal otherwise. Location_key upgraded from 2D to 3D. Bonus fix: Commit 2's multi-floor z=0 bug.
- **Retire `claim_room_hoards`: ✅ LANDED 2026-05-29** — the deprecated room-level service deleted; no production callers were left after Commit 4.
- **(Follow-up, out-of-arc)** Pick Lock + Search container action wiring: Commit 4's handler returns `open_loot_modal_locked` for locked containers and "Nothing visible here." for hidden hoards, so the UI can prompt without further handler changes. A `pick_lock_container` action handler (mirror of `_resolve_pick_lock` for doors) flips `inventory_items.is_locked=0` and re-fires loot. A `search_container` handler flips `treasure_hoards.is_hidden=0`.
- **(Follow-up, out-of-arc)** `_resolve_pick_up_all` still uses the legacy 2D location_key — port to 3D for symmetry with the now-fixed `_resolve_loot`.


---

## 16. Magic-item activation via spell binding

**Status (2026-05-29):** ✅ landed for **38 items** — 14 potions (Philter of Love + Potion of Polymorph added in Tier 2; one-shot consumption) + 11 wand/staff items (charge-per-use) + 12 worn-triggered items (Medallion of ESP + Medallion of ESP 90' added in Tier 2; activate-on-demand while equipped). Each item's ACKS Core description cleanly maps to a spell already implemented in the spell-effect system.

This section defines the **lightweight "item activates spell" bridge**: a magic item carries an optional spell_binding field that tells the runtime which existing spell to cast on its behalf. Coined to re-use the substantial spell-effect work in data/spells/spell_catalog.json + CastingResolver rather than write parallel per-item effect resolvers. V1 covers potions + charged-item wands/staves + worn-triggered rings/helms/boots/etc.; found scrolls + per-day cooldowns join in follow-on passes.

### 16.1 Catalog field — `spell_binding`

Added to data/treasure/magic_item_catalog.json entries (extractor: tools/extract_magic_item_catalog.py's SPELL_BINDING_MAP). Per-binding shape:

```json
"spell_binding": {
  "spell_key":       "cure_light_wounds",  // matches data/spells/spell_catalog.json
  "tradition":       "divine",             // "arcane" or "divine"
  "caster_level":    1,                    // RAW minimum to cast the bound spell
  "target_mode":     "self",               // "self" | "single_creature" | "single_target"
  "default_charges": 20                    // OPTIONAL — present for charged items
                                            // (wand/staff); -1 / missing = one-shot
                                            // (potions) or persistent.
}
```

**Tradition selection:** When a spell carries both arcane and divine classifications, the binding picks the **lower-caster-level** tradition (cheapest to brew — RAW magic_item_creation_table). Divine-only / arcane-only spells take their sole tradition.

**target_mode:**
- `self` — the user (drinker / wielder) is the target.
- `single_creature` — the user designates one creature.
- `single_target` — wand-style hybrid: the user designates a creature OR a cell (the resolver picks based on the spell's `target_spec`). Wand of Magic Missiles → creature; Wand of Fireballs → cell anchor.

**Charged items.** When `default_charges` is set on a binding, the V1 materialization path (`TreasureInstantiator.hoard_to_loot`) stamps it onto the new inventory_items row's `uses_remaining`. The activator's `activate_charged_item` decrements `uses_remaining` on every successful cast. When charges reach 0, the activator clears `is_magical` per RAW `acore_treasure_and_magic_items_rules.xml` identification_and_use: "An item with no charges remaining becomes useless and non-magical."

**target_mode:**
- self — drinker (or future wand wielder) is the target. Most potions.
- single_creature — the activating PC designates one creature as the target (e.g. Potion of Human Control → drinker designates the charmed human).
- Future modes (area / multi-target) join as we wire wands / scrolls.

### 16.2 V1 potion bindings (13 items)

| Potion | Spell | Tradition | Caster Lvl | target_mode |
|---|---|---|---|---|
| Potion of Healing | cure_light_wounds | divine | 1 | self |
| Potion of Extra-Healing | cure_serious_wounds | divine | 7 | self |
| Potion of Invisibility | invisibility | arcane | 3 | self |
| Potion of Levitation | levitate | arcane | 3 | self |
| Potion of Flying | fly | arcane | 5 | self |
| Potion of Clairaudience | clairaudience | arcane | 5 | self |
| Potion of Clairvoyance | clairvoyance | arcane | 5 | self |
| Potion of ESP | esp | arcane | 3 | self |
| Potion of Fire Resistance | resist_fire | divine | 3 | self |
| Potion of Water Breathing | water_breathing | arcane | 5 | self |
| Potion of Climbing | spider_climb | arcane | 1 | self |
| Potion of Speed | haste (custom resolver) | arcane | 5 | self |
| Potion of Human Control | charm_person | arcane | 1 | single_creature |

### 16.2.1 V1 wand / staff bindings (11 items)

All wands ship with **20 charges** at materialization (matches the RAW sample item: "Wand of Fireball (20 charges) 30,000 gp"). All staves ship with **30 charges** as a reasonable V1 default; per-staff overrides land later as rulebook prose surfaces.

| Item | Spell | Tradition | Caster Lvl | target_mode | Charges |
|---|---|---|---|---|---|
| Wand of Cold | cone_of_cold | arcane | 9 | single_target | 20 |
| Wand of Detecting Magic | detect_magic | arcane | 1 | self | 20 |
| Wand of Detecting Traps | find_traps | divine | 3 | self | 20 |
| Wand of Fire Balls | fireball | arcane | 5 | single_target | 20 |
| Wand of Illusion | phantasmal_force (custom resolver) | arcane | 3 | single_target | 20 |
| Wand of Lightning Bolts | lightning_bolt | arcane | 5 | single_target | 20 |
| Wand of Magic Missiles | magic_missile | arcane | 1 | single_target | 20 |
| Wand of Paralyzation | hold_monster | arcane | 9 | single_creature | 20 |
| Wand of Polymorphing | polymorph_other (custom resolver) | arcane | 7 | single_creature | 20 |
| Staff of Striking | striking | divine | 5 | single_target | 30 |
| Staff of Healing | cure_light_wounds | divine | 1 | single_creature | 30 |

### 16.2.2 V1 worn-triggered bindings (10 items)

Activated on demand while equipped. **V1 = unlimited uses** (no `default_charges`; no `uses_remaining` decrement on success). Per-day cooldowns + RAW per-item-charge limits (e.g. Helm of Teleportation's once-per-day) are a follow-on pass — add a `uses_per_day` field + a `cooldown_until_day` column on `inventory_items` + a daily-reset hook.

| Item | Spell | Tradition | Caster Lvl | target_mode |
|---|---|---|---|---|
| Ring of Invisibility | invisibility | arcane | 3 | self |
| Ring of Telekinesis | telekinesis | arcane | 9 | single_target |
| Ring of Command Human | charm_person | arcane | 1 | single_creature |
| Boots of Levitation | levitate | arcane | 3 | self |
| Broom of Flying | fly | arcane | 5 | self |
| Chime of Opening | knock | arcane | 3 | single_target |
| Eyes of Charming | charm_person | arcane | 1 | single_creature |
| Helm of Comprehending Languages | read_languages | arcane | 1 | self |
| Helm of Telepathy | esp | arcane | 3 | self |
| Helm of Teleportation | teleport (custom resolver) | arcane | 9 | single_target |

### 16.3 Deliberately omitted (need a Jedidiah ruling)

The ACKS Core summary XML only carries item NAMES — the mechanical descriptions live in rulebook prose we don't have in the corpus. Per project rule (no importing D&D / Pathfinder conventions without a Jedidiah ruling), these mappings are deferred until disambiguated:

**Potions:**

- **Potion of Polymorph** — Self or Other? (Self is the most-common convention but ACKS RAW summary doesn't say.)
- **Philter of Love** — equivalent to charm_person, a unique romance-flavored mechanic, or something between?
- **Potion of Animal / Dragon / Giant / Plant / Undead Control** — analogous to charm_person for those creature types (works with charm_monster + creature-type filter) or distinct custom-resolver-class mechanics?
- **Potion of Invulnerability** — does it map to protection_from_normal_weapons, or carry its own RAW mechanic?
- Non-spell potions: **Treasure Finding**, **Heroism**, **Super-Heroism**, **Longevity**, **Diminution**, **Gaseous Form**, **Growth**, **Giant Strength**, **Gaseous Form**, **Oil of Sharpness / Slipperiness**, **Sweet Water**, **Delusion** (cursed) — these don't map to known spells and need their own custom resolvers.

**Wands / staves / rods:**

- **Rod of Cancellation, Rod of Resurrection** — no equivalent spells in the catalog (Resurrect is a level 7 divine spell but not yet implemented).
- **Staff of Commanding, Staff of Power, Staff of Wizardry** — multi-effect items; each needs its own custom resolver because a single spell_binding can't capture multiple bound spells.
- **Staff of Withering** — no spell equivalent.
- **Staff of the Serpent** — cleric staff that transforms into a serpent; not the same mechanic as sticks_to_snakes (which targets wooden objects). Needs a custom resolver or ruling.
- **Wand of Detecting Enemies / Metals / Secret Doors** — no exact-match spell (partial overlap with detect_evil / find_traps but distinct mechanics).
- **Wand of Device Negation** — different scope from dispel_magic (targets magic items rather than active spells).
- **Wand of Fear** — RAW Cause Fear is a 1st-level divine spell; verify the spell catalog entry has an effect block before binding.

### 16.4 Runtime path — `MagicItemActivator`

engine/subsystems/inventory/magic_item_activator.gd is a static service that composes existing pieces. Two entry points:

**`drink_potion(item_id, drinker, ...)`** — one-shot consumption:

1. Look up the inventory_items row by id → get item_key.
2. Look up the catalog entry → get spell_binding.
3. Validate (catalog entry exists, category is potion, binding is present, target params match target_mode).
4. Build CasterContext (drinker = caster_id; tradition + caster_level from binding; map_context from caller).
5. Build SpellChoice (spell_key from binding; level 1; is_reversed false; no disjunctive branch).
6. Build TargetDescriptor (target_ids = [drinker.id] for self; [target_id] for single_creature).
7. Call CastingResolver.resolve(ctx, choice, descriptor, drinker, targets_by_id).
8. On success: consume the potion (CampaignRepository.remove_inventory_item(item_id)). On failure: the bottle survives (failure doesn't waste the dose — project interpretation of "item activation may fail without consumption").

**`activate_charged_item(item_id, wielder, ..., target_id?, target_entity?, target_cell?)`** — wand / staff per-charge consumption:

1. Lookup chain (inventory row → catalog entry → spell_binding); category must be `rod_staff_wand`.
2. **Charge gate:** `uses_remaining == 0` → fail "no charges remaining"; the item stays inert. `uses_remaining < 0` AND binding has `default_charges` → materialization bug, fail explicitly.
3. Target validation against `target_mode` (the new `single_target` mode accepts a creature id OR a cell).
4. Build inputs via the shared `_cast_via_binding` helper (same CasterContext / SpellChoice / TargetDescriptor pipeline as potions).
5. Call CastingResolver.resolve.
6. **On success:** `uses_remaining -= 1`. When charges reach 0, **clear `is_magical`** per RAW (`identification_and_use`: "An item with no charges remaining becomes useless and non-magical"). Return `{success, charges_remaining, became_inert, ...}`.
7. **On failure:** no charge decrement (same "failure doesn't waste the dose" rule as potions).

**Charge initialization at materialization.** `TreasureInstantiator.hoard_to_loot` reads `binding.default_charges` off the resolved catalog entry and stamps it onto the inventory_items row's `uses_remaining`. A wand newly looted from a hoard starts at full charge.

**`activate_worn_item(item_id, wielder, ..., target_id?, target_entity?, target_cell?)`** — worn-triggered activation:

1. Lookup chain (inventory row → catalog entry → spell_binding).
2. **Equipped-state gate:** `is_equipped != 1` → fail "not equipped"; no cast.
3. Target validation via the shared `_validate_target` helper.
4. Cast via the shared `_cast_via_binding` helper.
5. **No consumption in V1** — worn-triggered items have unlimited uses. The row, equip state, and `uses_remaining` are unchanged regardless of cast outcome.

The persistent-while-equipped path (`WornMagicEffectResolver`) is a DIFFERENT mechanism — those items apply continuously while worn (no activation event). Persistent (Ring of Protection, Cloak of Protection, Ring of Water Walking, Ring of Fire Resistance) and triggered (Ring of Invisibility, Boots of Levitation, etc.) coexist; an item is one or the other based on its data model entry.

**Why this is cheap to extend.** The activator's only job is the composition step; all the spell behavior lives in the existing pipeline. Adding a new bound potion / wand / worn-triggered item is a one-line change to the extractor's `SPELL_BINDING_MAP`.

### 16.5 Tests

tests/test_magic_item_activator.gd (suite id 400) — 20 DB-backed tests:

**Potion branch (6):**

- test_drink_potion_of_healing_succeeds_and_consumes — happy path end-to-end.
- test_drink_self_targeted_potion_succeeds_for_each_v1_binding — sweeps all 12 self-targeted bindings.
- test_drink_potion_with_no_spell_binding_fails_without_consuming — failure mode: un-bound potion (e.g. Treasure Finding) errors cleanly and the bottle survives.
- test_drink_non_potion_fails — failure mode: drinking a sword.
- test_drink_nonexistent_item_fails — failure mode: bogus item_id.
- test_drink_single_creature_potion_requires_target — Potion of Human Control without/with a designated target.

**Charged-item branch (8):**

- test_materialization_stamps_default_charges_for_wands — TreasureInstantiator pulls the binding's default_charges into uses_remaining.
- test_activate_self_targeted_wand_decrements_charges — Wand of Detecting Magic: 1 cast → 20 charges → 19.
- test_activate_wand_drains_to_zero_and_becomes_inert — drains 3 charges to 0; on the final cast became_inert=true AND is_magical flips to 0.
- test_activate_charged_item_with_no_charges_fails_without_decrementing — uses_remaining=0 fails with "no charges" message; row unchanged.
- test_activate_single_target_wand_requires_creature_or_cell — Wand of Magic Missiles without target_id and without target_cell fails; charges unchanged.
- test_activate_wand_with_target_cell_succeeds — Wand of Fireballs with a target_cell (area anchor).
- test_activate_staff_of_healing_on_ally_succeeds — Staff of Healing on a designated ally (single_creature mode).
- test_activate_charged_item_rejects_non_wand_category — sending a potion through the wand path is rejected; row survives.

**Worn-triggered branch (6):**

- test_activate_worn_item_requires_equipped — `is_equipped=0` fails with "not equipped" message; row unchanged.
- test_activate_ring_of_invisibility_succeeds — happy path; row survives (no consumption).
- test_activate_worn_item_unlimited_uses_does_not_decrement — 5 activations in a row; `uses_remaining` stays at -1; `is_magical` stays 1.
- test_activate_ring_of_command_human_with_target — single_creature without/with a target.
- test_activate_chime_of_opening_with_target_cell — single_target with cell anchor.
- test_activate_worn_item_with_no_binding_fails — Bag of Holding (no spell_binding) fails cleanly; row survives.

### 16.6 Open follow-ups

- **Per-day cooldowns + RAW per-item limits.** V1 worn-triggered items have unlimited uses; RAW for some (Helm of Teleportation 1/day, Chime of Opening 10 total charges, etc.) imposes specific limits. Add a `uses_per_day` field to the binding + a `cooldown_until_day` column on `inventory_items` + a daily-reset hook.

### 16.7 Table-status flags (cut_for_v1, defer_reason)

Catalog-level flags for triaging items whose mechanics aren't going to land in V1. Decided 2026-05-29 (Jedidiah):

- **`cut_for_v1: true` + `cut_reason: "<why>"`** — item is REMOVED from the random-roll table. `MagicItemCatalog.random_item_in_category` re-rolls when it lands on one (10-attempt cap, deterministic fallback to the first non-cut item in the category). The item still exists in the catalog file (preserves d100 ranges + value_gp for accounting); a future pass can flip the flag off when its subsystem lands.
- **`defer_reason: "<why>"`** — item KEPT in the random-roll table (still findable in hoards) but has no working in-game effect. `MagicItemActivator.*` refuses to activate it until the noted dependency lands. Distinguished from cut: a player CAN find, identify, sell a defer item (per its value_gp), they just can't USE it.

V1 cuts (9 items): Apparatus of the Crab, Boat/Folding, Flying Carpet (vehicle subsystems); Mirror of Life Trapping, Mirror of Opposition, Cube of Force, Helm of Alignment Changing (single-item subsystems); Potion of Sweet Water, Potion of Diminution (unmodeled state).

V1 defers (4 items): Ring of Wishes (canned-list Wish resolver), Potion of Longevity (age stat), Eyes of Petrification (gaze-attack subsystem confirmed unwired in catalog data only), Treasure Map (quest-hook generation).

The injection lives in `tools/extract_magic_item_catalog.py`'s `CUT_FOR_V1` / `DEFER_BUILD` dicts; helpers `MagicItemCatalog.is_cut(key)` + `defer_reason(key)` are the canonical read API.
- **Identification flow** (RAW :184-195) — the user doesn't know what a magic item does until tasted (potion), studied (scroll), or used (wand). V1 assumes identified; identification subsystem layers on top with no activator changes. RAW :identification_and_use confirms charge counts are similarly hidden ("Without Magic Research, a character does not know the number of remaining charges").
- **Per-user casting-stat bonus** — `CasterContext.casting_stat_bonus` is set to 0 in V1. The user's own INT (arcane) or WIS (divine) bonus could be folded in if Jedidiah wants it to affect save DCs the item creates.
- **Found scrolls** — spell scrolls already carry a list of bound spell levels (the scroll_of_spells generator); next step binds them to specific named spells from the spell catalog at instantiation, then routes through the same activator. Likely a new `cast_from_scroll` entry point that consumes the scroll like a potion.
- **Recharge mechanic** — RAW prose hints that some items can be recharged through Magic Research. V1 doesn't model recharge; once `is_magical=0`, the row stays inert. A future pass can add a `recharge` API that bumps `uses_remaining` back up.
- **Per-wand variable charges at materialization** — V1 stamps the binding's `default_charges` verbatim. RAW for some items uses rolled charges (e.g. Life Drinker "1d4+4 charges"). A future pass can add `charges_dice` (e.g. "1d10+10") to the binding and roll at materialization time.
- **UI plumbing** — the activator is API-level only. A "Use" inventory action that calls into it (and prompts for the target on single_creature / single_target bindings) is the next UI integration.

---

## 17. Surface-coat resolver (Oil of Slipperiness + future grease/oil items)

`engine/subsystems/inventory/surface_coat_resolver.gd` (`SurfaceCoatResolver`) is the shared service for items / spells that apply a surface coat to either a creature ("anointed with oil") or a 10' x 10' floor patch ("poured out"). Oil of Slipperiness is the first consumer (2026-05-30); future Grease spell, Oil of Sharpness, etc. plug into the same `coat_spec` API.

**Why a shared resolver?** Per Jedidiah 2026-05-29: "there should be other oil items and grease/oil spells that need the same kind of surface coat resolver, so as long as its resolvers are re-usable it is worthwhile to build."

### 17.1 API surface

Three entry points on the resolver (all static):

- `apply_oil_to_creature(item_id, target_creature, coat_spec, effect_tracker) -> Dictionary` — sets the spec's `flag_key` on the target's `EntityFlags` with source_id `"surface_coat:<item_id>:<target_id>"`; registers an entry in the supplied `ActiveEffectTracker` so duration-tick unwind works through the existing CastingResolver cleanup_callback (the `applied_flags` shape matches the spell-effect convention).
- `apply_oil_to_cell(item_id, map_id, anchor_cell, area_size_ft, coat_spec, effect_tracker, surface_conditions) -> Dictionary` — applies the spec's `condition_key` to a (area_size_ft / 5)² patch of cells anchored at `anchor_cell` via the new `CellSurfaceConditions` runtime registry. Each cell gets its own source_id `"surface_coat:<item_id>:cell:x,y,z"` so a prefix-clear sweeps the whole patch.
- `apply_oil_to_object(item_id, target_inventory_item_id, coat_spec, effect_tracker) -> Dictionary` — V1 returns "not implemented" until the attack-throw consumer reads coat state on weapon items.

All three return a uniform result Dict: `{ success, message, consumed, applied_flag_key, applied_condition_key, effect_id, source_id, coated_cells }`.

### 17.2 The `coat_spec` Dictionary

Creature-mode shape:

```gdscript
{
    "flag_key": "is_slippery_self",          # EntityFlag set on the target
    "duration_type": "turns",                # tracker duration bucket
    "duration_remaining": 3,
    "caster_level": 1,                       # dispel-parity (mirrors spell_binding)
    "spell_key": "slipperiness",             # diagnostic label
}
```

Cell-mode shape:

```gdscript
{
    "condition_key": "slippery",             # CellSurfaceConditions key
    "duration_type": "turns",
    "duration_remaining": 3,
    "caster_level": 1,
    "spell_key": "slipperiness",
}
```

Future consumers (Grease spell, Oil of Sharpness on weapons, etc.) pass DIFFERENT specs — the resolver itself doesn't know about the coat mechanic. Tests `test_resolver_accepts_alternate_coat_spec_for_future_grease` + `test_resolver_accepts_alternate_cell_coat_spec_for_future_grease` lock the reusability contract by running the resolver with a mock `greased` spec and asserting the alternate flag / condition is what gets set.

The resolver exposes two canonical-spec factories for Oil of Slipperiness: `oil_of_slipperiness_creature_spec()` and `oil_of_slipperiness_cell_spec()`. New oils add a factory and a one-line case in `MagicItemActivator._select_oil_coat_spec`.

### 17.3 `CellSurfaceConditions`

`engine/subsystems/spells/cell_surface_conditions.gd` (`CellSurfaceConditions`) — runtime registry of cell-level surface coats. Mirrors `EntityFlags`'s multi-source / source_id model, keyed on `(map_id, Vector3i)` pairs. Multiple sources can share the same `condition_key` on the same cell; the condition stays active until every source has been cleared.

V1 scope = in-memory only. Save+reload during an oiled visit drops the coat (deferred). For the live-fire use case (mid-combat or mid-room), this is fine — coats are short-lived (3-turn RAW duration). A future pass can layer a `cell_surface_conditions` table on top with the same set / clear / has contract.

### 17.4 MagicItemActivator dispatch

`MagicItemActivator.apply_oil(item_id, catalog, tracker, mode, ...)` is the public entry point. The router:

1. Looks up the inventory row → `item_key`.
2. **Requires `item_key.begins_with("oil_")`** — guards `drink_potion`'s domain so a Potion of Healing can't be routed through the apply path by mistake. Both RAW oils (Slipperiness, Sharpness) have the `oil_` prefix.
3. Picks the `coat_spec` via `_select_oil_coat_spec(item_key, mode)` (V1 = hard-coded for Oil of Slipperiness; a future catalog `oil_binding` field generalizes after the second consumer arrives).
4. Dispatches to `SurfaceCoatResolver.apply_oil_to_creature` (mode="creature") or `apply_oil_to_cell` (mode="cell").

### 17.5 Open follow-ups

- **Movement-resolver hook for the per-cross save throw** — the cell condition is SET; consuming it for "make a proficiency throw of 20+ or fall down" when an entity moves into a slippery cell is the next integration (mirrors the `protected_from_normal_weapons` consumer in the attack resolver: read flag, compute, branch).
- **Grapple-resistance hook for the creature-mode flag** — the flag is SET; the attack resolver's grapple / restrain branches need to read `is_slippery_self` and refuse to apply the grapple condition (or auto-succeed the slip-escape).
- **Object mode** — `apply_oil_to_object` is wired with a clear failure. The RAW Slipperiness/Oil "20 arrows / 2 1H weapons / 1 two-handed weapon" branch lands when a weapon-attack-throw consumer reads coat state.
- **Duration tick wiring through CastingResolver cleanup_callback** — the resolver registers `applied_flags` (creature mode) properly so the existing tracker → cleanup_callback unwind path will sweep the flag on expiry. For cell mode, the metadata carries `coated_cells` + `source_id_prefix` so a small cleanup_callback addition (detect `metadata["coat_mode"] == "cell"` → call `surface_conditions.clear_all_from_source_prefix`) will close the loop. V1 tests simulate the cleanup manually to lock the contract.
- **Persistence** — coats live in memory only. Mid-visit save-load drops them. A `cell_surface_conditions` table (sparse, keyed by `(map_id, col, row, level, condition_key)` + source_id) would close this.
- **Second oil** — Oil of Sharpness is the obvious second consumer; once Jedidiah disambiguates its mechanic (the deferred list flags it for ruling), the binding-by-prefix shape generalizes to a catalog `oil_binding` field analogous to `spell_binding`.
