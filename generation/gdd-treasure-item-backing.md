# GDD: Treasure Item Backing & Valuables

**Authority:** PROJECT-DESIGNED — the data model and instantiation pipeline that turn generated treasure (coins / gems / jewelry / magic items) into real, encumbrance-tracked, sellable inventory items. The ACKS Constraints in §2 (encumbrance weights, gp values, recovery-XP rules) are sacred and applied verbatim. One genuine RAW gap (jewelry encumbrance) is flagged for Jedidiah in §7 and §13.
**Status:** Draft v1.1 — audit + proposal. Spun off from the 2026-05-28 dungeon-generator runtime-consumer session. No code written; this document specifies the schema additions, the valuables/magic-item catalogs, and the hoard→inventory instantiation contract the runtime-consumer session will implement. v1.1: jewelry-encumbrance decision resolved (§7 — 1 unit, per Jedidiah); migration numbered 134; backward-compat confirmed (§4.1).
**Depends on ACKS rules:** `rules/acore_equipment.xml:582-593` (character encumbrance table — treasure is 1 stone per 1,000 coins or gems; items are 1 stone per 6 items; magic-armor weight reduction); `rules/acore_treasure_and_magic_items_rules.xml:1-7` (treasure scope and XP rules), `:90-118` (gem value table), `:120-145` (jewelry value table), `:147-170` (special-treasure trade goods with per-item gp + stone), `:184-240` (magic-item category/name tables + magic-armor weight rule); `rules/acore_adventures_and_encounters.xml:580-590` (treasure XP: 1 XP per 1 gp recovered to civilization; equipment must be sold to grant XP; magic items grant no XP); `rules/acore_proficiencies_rules_and_catalog.xml:478-488` (Adventuring proficiency — all PCs can roughly value coins, trade goods, gems, jewelry).
**Depends on project GDDs:** [`gdd-dungeon-generator-v1.md`](gdd-dungeon-generator-v1.md) (§13 produces the `TreasureHoardData` this GDD consumes); [`gdd-party-inventory.md`](gdd-party-inventory.md) (defines the loot queue, carrier model, cache value-loss, and the GP/coin display this GDD must feed real valuables into); [`gdd-phase-10b-2-trade-block.md`](gdd-phase-10b-2-trade-block.md) (mercantile/trade-good loads — special treasures (§10) are bulk trade goods that overlap this system).
**Implementing files:** None yet. Proposed: a migration adding `inventory_items.value_cp`; `engine/subsystems/generation/dungeon_generator_v1/` or `engine/subsystems/inventory/` instantiator; `data/treasure/magic_item_catalog.json`. Existing files this touches: `engine/shared_types/inventory_item.gd`, `engine/shared_types/treasure_hoard_data.gd`, `engine/subsystems/commerce/shop_service.gd`, `engine/subsystems/characters/encumbrance_calculator.gd`, `engine/subsystems/commerce/currency.gd`.
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

## 9. Found magic items (catalog — Phase 2)

The biggest gap. The resolver emits placeholders because **no found-magic-item catalog exists** (the `crafted_magic_items` table is for *player-crafted* items only — it has `creator_character_id`, `workshop_id`, crafting costs — and is not a source of found items).

Proposed `data/treasure/magic_item_catalog.json`, extracted at build time from `rules/acore_treasure_and_magic_items_rules.xml:197-264` (and, per the RAW note at `:209`, the APC/Axioms tables for the full d00 distributions):

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

**Deferred within Phase 2 (flag, don't design here):**

- **Sale value / magic-item market.** Magic items grant **0 recovery XP** (RAW §2.3), so they never feed `total_gp_value`. Their *sale* price is a separate economy question (ACKS prices found magic items via APC / the crafting-cost model). Until a magic-item market exists, found magic items keep `value_cp = -1` and remain non-sellable at the mundane shop (`ShopService` already blocks `is_magical`). They are *carriable and identifiable*, just not yet *sellable*.
- **Identification flow** (sage / Magical Engineering / Loremastery / sip / Magic Research) is its own system; the catalog only needs the `requires_identification` flag so a future identify system has somewhere to hang.

---

## 10. Special treasures (anticipated, not yet generated)

The resolver does not yet roll special treasures (the `special_treasures` replacement step, `rules/acore_treasure_and_magic_items_rules.xml:147-170`). When generation adds them, the data model here already accommodates them: a special-treasure good is an `item_category = "trade_good"` inventory item with `value_cp = value_gp × 100` and `encumbrance_units` taken **directly from RAW** (the tables give per-item stone, e.g. "1d3 rugs or tapestries, 5gp each, 2d6 stone each" → `encumbrance_units = stone × 1000`). No new data-model work is needed for special treasures beyond what §4 provides; they reuse `value_cp` and a category string. Note the overlap with [`gdd-phase-10b-2-trade-block.md`](gdd-phase-10b-2-trade-block.md): special-treasure goods *are* trade goods and may eventually be sold through the mercantile load system rather than the equipment shop — flagged in §13.

---

## 11. Sellability and recovery XP

### 11.1 Selling valuables

`ShopService.sell_item` / `get_sellable_items` must be extended so valuables are sellable:

- **Value by `effective_value_cp`** (§4.1) rather than strictly by catalog `cost_cp`.
- **Accept items whose `item_category` is `gem`, `jewelry`, or `trade_good`** even though they are not in `EquipmentCatalog` (today these are rejected with "This item cannot be sold here").
- Keep the existing exclusions for coins (`Currency.is_coin`) and `is_magical` items (the latter until a magic-item market exists).
- ACKS gives all PCs the **Adventuring** proficiency, which covers "rough valuation of common coins, trade goods, gems, and jewelry" (`rules/acore_proficiencies_rules_and_catalog.xml:478-488`, Adventuring) — so the party can always at least estimate a valuable's worth; no special appraisal gate is required for V1. A future Appraisal/merchant-haggling layer can modulate the sale fraction, but base sale = full `value_cp`.

### 11.2 Recovery XP

RAW §2.3: coins/gems/jewelry/special treasure grant 1 XP per 1 gp **when recovered to civilization**, and mundane equipment must be **sold** to grant XP. The instantiated items' `value_cp` is the basis for both. The recovery-XP trigger (party reaches a friendly town/stronghold) is a **separate system** — this GDD only guarantees the value data exists on each item for that system to read. `hoard.total_gp_value` (coins+gems+jewelry, magic excluded) remains the generation-time XP/GP-balance figure; per-item `value_cp` is the runtime basis once items are split across carriers, partially sold, or lost.

---

## 12. Phasing

- **Phase 1 (MVP — unblocks the runtime-consumer):** migration for `value_cp` (§4.1); `InventoryItem` field + `effective_value_cp`; gem & jewelry instantiation (§6, §7) via the bridge (§5); extend `ShopService` sell path (§11.1). After this, looted coins + gems + jewelry are real, weighed, and sellable. Requires the §7 jewelry decision.
- **Phase 2 (magic items):** extract `data/treasure/magic_item_catalog.json` (§9); resolve placeholders to real items in the bridge; keep them carriable/identifiable but non-sellable.
- **Phase 3 (special treasures + magic-item market):** add special-treasure generation (resolver) consuming the `trade_good` category (§10); design the magic-item sale economy and identification flow.

---

## 13. Open Questions / Architectural Concerns

- **Jewelry encumbrance (RAW gap — RESOLVED 2026-05-28):** Jedidiah ruled jewelry weighs **1 unit (1/1,000 stone)**, same as coins and gems (§7). No longer blocks Phase 1. Recorded as a project decision filling the RAW gap (the encumbrance table at `rules/acore_equipment.xml:586` names only "coins or gems"); options (b) 1/6 stone and (c) 1 stone were considered and declined.
- **`inventory_items` schema change requires approval:** adding `value_cp` is a data-model change. Per `CLAUDE.md` / the design brief, the build agent "may NOT … change data models … without explicit approval from Jedidiah." This GDD is the approval request; migration 134 should not land until approved. Backward compatibility is confirmed safe in §4.1 (non-destructive `ADD COLUMN` with sentinel default; the same pattern that added `encumbrance_units` in migration 014; naming follows the migration-108–116 `_cp` convention).
- **Value column vs. dual-purpose `cost_cp`:** the proposal keeps catalog `cost_cp` as the mundane-equipment value and adds `value_cp` only for rolled valuables (sentinel `-1` = "use catalog"). The alternative — backfilling `value_cp` for *every* item from the catalog — was rejected as a needless migration with a drift risk (catalog price changes wouldn't propagate). Confirm the sentinel approach is acceptable.
- **`gdd-party-inventory.md` already assumes valued valuables exist** (cache-raid example "1 ruby (total value 450 GP)"; value-loss sorts by `cost_cp`). Once `value_cp` lands, that GDD's value-loss logic should sort by `effective_value_cp`, not raw `cost_cp` — a small companion edit, flagged so it isn't missed.
- **Overlap with `gdd-phase-10b-2-trade-block.md`:** special-treasure goods (§10) are trade goods; whether they sell through the equipment shop (`value_cp`) or the mercantile load system needs a routing decision when Phase 3 lands. Not blocking Phase 1/2.
- **Magic-item sale economy is unspecified by this GDD** (§9). Found magic items are deliberately carriable-but-not-sellable until that economy is designed. Confirm that's acceptable for V1 (the alternative — a placeholder flat price — risks XP/GP-balance distortion and a hard-to-undo precedent).
- **Magic-item catalog completeness:** Core preserves only "core rows" of the d00 item tables (`:209`); the full distributions live in the APC/Axioms magic-item chapters. Phase 2 extraction should pull from those higher-precedence sources, not Core alone — flagged so the extractor doesn't ship a Core-only subset and call it complete.
- **No banker's-rounding hazard in Phase 1:** gem/jewelry gp values are integers, so `value_cp = value_gp × 100` is exact. Any future fractional value (sale fractions, haggling) must use `XPAwardCalculator.bankers_round` per the project-wide convention.
