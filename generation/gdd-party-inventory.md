# Game Design Document — Party Inventory

**Document type:** Game Design Document (project-designed)
**Status:** Draft for review
**Depends on GDDs:** gdd-settlement-exploration-ui, gdd-dungeon-map-ui, gdd-combat-ui, gdd-realtime-scheduler, gdd-calendar-seasons
**Depends on sacred rules:** acore_equipment.xml (encumbrance bands, animal/vehicle loads), ax_campaign_play.xml (activity classification), ax_henchmen_recruitment_expanded.xml (wage rules)
**Depended on by:** acks_arbiter_build_plan.md phases E-1 (Party Management) and F-1 (Combat Loop, for in-combat trade actions)

---

## 1. Scope and Design Principles

### 1.1 Problem

The engine supports a fully implemented strict-carrier inventory model — every `inventory_items` row belongs to exactly one carrier (character, trained creature, or draft vehicle). Transfer methods exist for every carrier-to-carrier direction. What does not exist is a UI surface where the player can see all carriers at once, move items between them, pool gold for purchases, drop items on the ground, or distribute loot. This GDD specifies that surface and the supporting subsystems.

### 1.2 Strict Carrier Model

There is no "party pool" as a storage concept. Every item has exactly one owner at any time. The party-level conveniences described in this GDD are **views and transfer layers** over strictly-owned inventory, not a shared pool.

### 1.3 Three Surfaces

1. **Party Inventory overlay** — primary surface. Keybind-toggled (default F9). Shows all carriers as columns, supports drag-and-drop transfers, filter bar, "Auto-distribute" button, integrated location cache column.
2. **Loot Distribution modal** — triggered automatically by combat end with loot, container opening, and shop delivery of party-scope items. Specialized for distributing queued items in one operation.
3. **"Send to…" context menu** — right-click any item in the Character Sheet equipment tab for quick one-off transfers without opening the overlay.

### 1.4 Support Subsystems

- **PartyWallet** (new) — gold aggregation, auto-deduction, display refactor.
- **LocationCacheManager** (new) — ground-cache subsystem with persistence timers, decay, and monthly raid rolls.
- **Encumbrance color bands** (new) — visualization component over the existing `EncumbranceCalculator`.

### 1.5 Non-Goals

- Mount/rider binding — deferred to Phase C per `pack_animal_state_report.md`.
- Animal training UI — deferred to same phase.
- Shared-inventory-as-pool model — explicitly rejected by the strict-carrier decision.
- Porter/low-level-hireling flows — belong to a future mercenary/hireling build session.

---

## 2. Carrier Taxonomy

Every entity that can hold items is a "carrier." The overlay renders one column per carrier. Columns differ by type.

### 2.1 PC Column

- Portrait, name, class, level
- Gold readout (PartyWallet contributor) — see §3
- Encumbrance bar with ACKS band coloring — see §5
- Equipped slots section (hands, body, head, neck, etc. — matches `cs_tab_equipment.gd` slot layout)
- Containers section (backpacks, sacks, pouches, chest)
- Loose items section (items not in a container, not equipped)

### 2.2 Henchman Column

Structurally identical to PC column with two differences:

- Gold readout shows a lock icon. Tooltip: "Henchmen keep their wages — cannot auto-deduct."
- Gold is excluded from PartyWallet totals.

All non-coin items transfer freely to and from henchmen, regardless of whether the henchman brought them, looted them, or was given them. (Verisimilitude polish — henchman auto-spending on better clothes and wine — is an end-project enhancement; out of scope here.)

### 2.3 Trained Creature Column (pack animal, mount, draft animal)

- Portrait/species icon, name, species, role badge (WM / M / WB / G / H per role map)
- **No equipped slots for hands** (animals have no hands)
- **Tack section** — saddle slot, barding slot, saddlebags/panniers slot, caparison slot. Follows `CreatureEquipmentService` slot vocabulary: `mount`, `body`, `pack`.
- **Cargo section** — loose items carried without containerization
- Encumbrance bar showing current load vs `get_effective_capacity_normal()` / `_max()` (two-tier: normal in green, overload zone in red)
- **Rigging state indicator** above the bar — one of five states per §2.3a saddle taxonomy: *Untacked*, *Rope-lashed*, *Pack saddle*, *Draft saddle*, *Riding saddle*, or *War saddle*. Badge shows capacity multiplier, permitted container types, and restrictions (ride / hitch / dismount-on-damage)
- **Hitched-to-vehicle indicator** (if creature is hitched to a draft vehicle): shows vehicle name with unlink affordance
- **Rider indicator** (riding/war saddle only, future Phase C): shows who is mounted, their +15 stone encumbrance contribution

### 2.3a Saddle Taxonomy (authoritative)

**Project-designed.** This section supersedes any ACKS RAW saddle functionality for code clarity. All saddle effects, container permissions, and encumbrance multipliers derive from this table — nothing else. The engine's `CreatureEquipmentService` and `TrainedCreatureData` must conform to this table; any prior behavior that deviates is incorrect and should be updated during Session 5 cleanup.

| Rigging | Capacity multiplier | Permitted containers | Permits riding? | Permits hitching? | Other effects |
|---|---|---|---|---|---|
| **Untacked** (no saddle, no rope) | 0.0× | None | No | No | Cargo drops rejected by validator |
| **Rope-lashed** (`rope_50ft` equipped as rigging, no saddle) | 0.5× | Large sack, small sack, backpack, barrel, pouch/purse (any count, up to effective capacity) | No | No | Badge: "Rope-lashed ×2 encumbrance" |
| **Draft saddle** (`saddle_draft`) | 1.0× | **None — pure hitching rig** | No | Yes (if valid draft species for vehicle) | Cannot attach containers |
| **Pack saddle** (`saddle_pack`) | 1.0× | Panniers, saddlebags, large sack, small sack, barrel, pouch/purse | No | No | Split-off from ACKS RAW draft saddle for clarity; same cost and encumbrance as draft saddle |
| **Riding saddle** (`saddle_riding`) | 1.0× | Saddlebags only (maximum of 2) | Yes | No | Rider's character counts as 15 stone (15000 units) + rider's own carried encumbrance toward creature load. On damage while mounted, rider must save vs Paralysis or be dismounted |
| **War saddle** (`saddle_war`) | 1.0× | Saddlebags only (maximum of 2) | Yes | No | Same as riding saddle except **no** dismount save required on damage |

**Notes on the taxonomy:**

- **Rope as pseudo-saddle, not modifier.** Rope is now a rigging choice equivalent to an untacked-plus-rope state; it does not stack with any saddle. If a saddle is equipped, rope in inventory has no rigging effect (it's just cargo).
- **Saddle mutual exclusivity.** A creature can have exactly one saddle OR rope-rigging at a time. Equipping a second saddle type rejects with a validation error.
- **Pack and draft are intentionally divergent.** In ACKS RAW, "draft saddle" covers both vehicle hitching and cargo hauling. The project split these for clarity so the validator can enforce vehicle-only vs cargo-only unambiguously. Costs and encumbrance are identical.
- **Rider encumbrance (+15 stone).** The rider's flat 15-stone contribution is a project-designed simplification — the ACKS "creature weight / 12 = stone" formula is reserved for combat grappling. Adding their carried encumbrance on top means an encumbered PC makes the mount slower. The 15-stone baseline represents an average humanoid body; halflings and similar would be reduced in Phase C when mount/rider binding is built. For Phase A, the +15 is flat.
- **Dismount save.** The save vs Paralysis trigger is handled by `CombatResolver.apply_damage()` — when a mounted PC takes damage, if their mount has `saddle_riding` equipped (not `saddle_war`), schedule the save. Fails → apply `dismounted` condition + 1d6 falling damage per ACKS RAW knock-off rules. Implementation deferred to combat session; GDD just specifies the hook.

### 2.4 Draft Vehicle Column (cart, wagon)

- Icon, vehicle type
- **Draft team panel** at top: hitched creature slots, per-slot equiv contribution, drag-to-hitch / click-to-unhitch
- **Capacity bar** based on `DraftVehicleService.get_vehicle_capacity(item_key, team_equiv)`:
  - If team equiv insufficient → "Insufficient draft power" warning, vehicle cannot move, cargo can still be loaded
  - Else green up to normal_load, yellow up to max_load, red over max
- **Cargo section** — items with `vehicle_id` set

### 2.5 Location Cache Column

Visible only when the party's current location has a cache:

- **Dungeon cell cache** — items dropped in current cell or in an opened locked container in current cell
- **Hex cache** — items hidden-and-memorized in current hex (wilderness)
- **Settlement node cache** — items dropped at current PoI

Shows:

- Cache type indicator (loose / locked container / hidden-and-memorized)
- Decay readout if applicable: "Decays in 3 days" / "Decays in 2 weeks" / "Permanent (locked)" / "Permanent (hidden, raid risk 4%)"
- Items list with "Pick up" on each row plus "Pick up all" header button

Cache column is the drop target for "drop on ground" actions.

### 2.6 Shared Inventory (deprecated column)

`PartyData.shared_inventory` exists but is not rendered in this overlay. Under strict-carrier, the concept is vestigial. Migration 021's `inventory_items.party_id` column is repurposed for future use (e.g., stronghold storage in Phase H) but not referenced by this UI.

---

## 3. Gold System and PartyWallet

### 3.1 Coin Storage (unchanged data model)

Each denomination remains an `inventory_items` row per carrier:

| item_key | display | encumbrance_units | container fit |
|---|---|---|---|
| `platinum_piece` | PP | 1 | any |
| `gold_piece` | GP | 1 | any |
| `electrum_piece` | EP | 1 | any |
| `silver_piece` | SP | 1 | any |
| `copper_piece` | CP | 1 | any |

Encumbrance stays at 1 unit per coin (1000 coins = 1 stone, ACKS RAW). Coins can live in purses, pouches, chests, saddlebags, or loose.

### 3.2 Display Convention

- **Summary display:** `GP 🪙: 242.35` — converted float with two decimal places representing GP + (SP/10) + (CP/100). PP and EP are pre-converted at ACKS rates (1 PP = 5 GP, 1 EP = 0.5 GP).
- **Detail display (hover, shop screen, loot modal):** `| PP: 4 | EP: 0 | GP: 200 | SP: 20 | CP: 35 |` with colored coin glyphs per denomination.

The breakdown is always authoritative for transactions; the float is display-only.

### 3.3 PartyWallet Subsystem

**File:** `engine/subsystems/commerce/party_wallet.gd` (autoload: `PartyWallet`) — sits alongside the existing `currency.gd` and `shop_service.gd` in the commerce subsystem.

**Eligibility rule — a carrier is "in the wallet" if:**

1. It is a PC (not a henchman, not a creature, not a vehicle, not a mercenary)
2. It is a member of the active character's party
3. It is in the same session-location as the active character, where "same location" means:
   - Same hex in wilderness
   - Same settlement (not same PoI — intra-settlement split is in-wallet since travel time is minutes)
   - Same dungeon level (different rooms on the same level are in-wallet since travel is turns)
   - **Cross-location splits are blocked**: Tripoli vs Rome = not in wallet; dungeon level 1 vs level 3 = not in wallet

**Public API:**

```
PartyWallet.get_party_total_gp(include_henchmen=false) -> float
PartyWallet.get_party_breakdown(include_henchmen=false) -> Dictionary
  # {pp, ep, gp, sp, cp, total_gp_float}
PartyWallet.get_contributors(active_character_id) -> Array[String]
  # Ordered: active character first, then party list order, present PCs only
PartyWallet.can_afford(cost_gp, active_character_id) -> Dictionary
  # {ok: bool, shortfall_gp: float, per_character: {char_id: gp_available}}
PartyWallet.pay(cost_gp, active_character_id) -> Dictionary
  # Deducts in contributor order. Converts larger coins down when needed.
  # {ok, total_paid_gp, per_character_deductions: {char_id: {pp, ep, gp, sp, cp}}}
PartyWallet.pay_from_character(character_id, cost_gp) -> Dictionary
  # Strict single-character deduction for bribes, personal purchases
PartyWallet.deposit_to_character(character_id, amount_gp)
PartyWallet.deposit_to_party_even_split(amount_gp)
  # Banker's rounding, residual CP to poorest PC among recipients
PartyWallet.deposit_to_party_by_shares(shares: Dictionary)
  # shares: {char_id: float_weight}, normalized to 1.0, banker's rounding, residual CP to poorest
```

**Mercenary payments:** If an active mercenary contract is being paid out, `PartyWallet.pay()` logs the transaction but does not create coin items on the mercenary (gold is consumed, not transferred to a carrier). Mercenary contract tracking is future work; the wallet just logs the sink.

**Deduction algorithm:**

1. Compute `cost_cp = round(cost_gp * 100)` to avoid float drift.
2. For each contributor in order:
   - Take as many CP as the contributor has up to remaining cost.
   - Then SP (at 10 CP each), EP (500 CP), GP (100 CP), PP (500 CP).
   - Always consume smallest-denomination-first from each contributor to avoid making change unnecessarily.
3. If the last contributor has the right total value but not in matching denominations, make change: take one larger coin, refund the difference as smaller coins.

### 3.4 Display Integration Points

| Surface | Gold display |
|---|---|
| Character sheet header | Character's personal total (float) with hover breakdown |
| Character sheet equipment tab | Gold items appear as inventory rows (coins are items) |
| Party Inventory overlay PC column | Character's personal total + party-wallet contribution indicator |
| Party Inventory overlay summary footer | Party-wallet total (excluding henchmen) |
| Shop screen | Party-wallet total prominently; breakdown in transaction preview |
| Loot modal | Queued coins shown in breakdown; distribution preview shows per-recipient breakdown |

### 3.5 "Transfer Gold" Modal

Reached by clicking any gold readout in the overlay:

- Source dropdown (any in-wallet PC)
- Target dropdown (any in-wallet PC, any henchman, or "To party" for even-split)
- Amount field in GP float with live conversion breakdown
- "Use smallest change" toggle — prefer CP/SP over GP/PP when possible

Rejection conditions:
- Source doesn't have the amount
- Target's containers full (coins are items and need to fit somewhere — purse, pouch, or loose)

---

## 4. Transfer Rules Matrix

### 4.1 Context-Based Friction

| Context | Transfer permission |
|---|---|
| Settlement (same settlement, any PoI) | Free instant |
| Wilderness (same hex) | Free instant |
| Dungeon, outside combat | Free only if carriers are adjacent cells (note: characters cannot share cells) |
| Dungeon, in combat | One trade action per round between adjacent combatants |
| Across settlements / hexes | Blocked |

"Adjacent" in dungeon: the 8 cells orthogonally and diagonally surrounding the carrier's cell.

### 4.2 Item-Based Locks

| Item class | Transfer rule |
|---|---|
| Coins (PP/EP/GP/SP/CP) | Between PCs: transferable via "Transfer Gold" modal only (strict per-character accounting). To/from henchmen: **locked** (henchman wages). To/from creatures/vehicles: **locked** (non-coin carriers). Exception: coins can be placed in containers carried on creatures/vehicles as containerized cargo — but cannot be in direct carrier ownership. |
| Worn clothing (slot = `body` for clothing items, not armor) | Locked — must be unequipped (become loose) before transfer |
| Ammunition (arrow, bolt, sling stone) | **Auto-share exception**: in combat between adjacent combatants, any PC with matching ammo can donate to another PC as a **free action** once per round. Explicit trade actions are unrestricted count. |
| All other consumables (daggers, darts, holy water, military oil, torches, potions, poisons, scrolls, food, etc.) | Normal trade action rules apply — no free-action auto-share |
| Equipped weapons and armor | Transferable, but auto-unequip on transfer (slot becomes empty, item becomes loose in source, then transfers) |
| Containers | Transferable; all contained items transfer together |
| Everything else | Free swap within context friction rules |

### 4.3 Carrier-Type Restrictions

| Source → Target | Restriction |
|---|---|
| Any → PC/Henchman | Must fit in a container or equipment slot or go loose; loose items contribute to character encumbrance per PC bands |
| Any → Creature with pack saddle | Loose `pack` cargo, panniers, saddlebags, sacks, barrels, purses allowed; restricted by effective capacity |
| Any → Creature with riding/war saddle | Saddlebags only (max 2); all other containers rejected. Rider's carried encumbrance also counts against creature — see §2.3a |
| Any → Creature with draft saddle | **Rejected** — draft saddle permits hitching only, not cargo. Tooltip: "Draft saddle is for vehicle hitching; use a pack saddle for cargo." |
| Any → Creature rope-lashed | Sacks, backpacks, barrels, pouches allowed; saddlebags and panniers rejected. Half capacity applies |
| Any → Creature untacked | Rejected — "Untacked creature cannot carry cargo" |
| Any → Vehicle | Cargo goes to vehicle's cargo list; restricted by effective capacity based on team equiv |
| Any → Location cache | Always allowed (no capacity cap on caches) |
| Location cache → Any | Same rules as above for the target |

Each row's "container rejection" is validated at drop time against the §2.3a table. The service returns a specific rejection reason for UI tooltip display.

### 4.4 Drag-and-Drop UX

- During drag, valid target columns highlight green, invalid red.
- Invalid drop attempts show inline tooltip with rejection reason: `"Coins — cannot transfer directly. Use Transfer Gold."`, `"Would exceed capacity by 3 stone"`, `"Creature is untacked"`, `"Target not adjacent in dungeon"`, etc.
- Over-capacity is **blocked by default**, not allowed-with-warning. Players cannot drop an item that exceeds a target's maximum load. This protects against accidentally grounding a mule.
- Within-capacity-but-overloaded drops (pushing an animal into its overload tier, or a PC into red band) are **allowed with warning** — the warning tooltip mentions the new movement rate consequence.

---

## 5. Encumbrance Visualization

### 5.1 PC/Henchman Bands (ACKS RAW)

| Band | Units | Stone | Exploration | Combat | Running | Color |
|---|---|---|---|---|---|---|
| Unencumbered | 0 – 5000 | 0 – 5 | 120'/turn | 40'/round | 120'/round | Green |
| Lightly encumbered | 5001 – 7000 | 5.001 – 7 | 90'/turn | 30'/round | 90'/round | Yellow |
| Heavily encumbered | 7001 – 10000 | 7.001 – 10 | 60'/turn | 20'/round | 60'/round | Orange |
| Severely encumbered | 10001 – max | 10.001 – (20 + STR) | 30'/turn | 10'/round | 30'/round | Red |
| Over max | > (20000 + STR_mod × 1000) | > 20 + STR | Cannot move | — | — | Red, flashing |

Values confirmed against `acore_equipment.xml` and `EncumbranceCalculator` constants.

### 5.2 Creature Bands (ACKS two-tier)

| Band | Load | Movement multiplier |
|---|---|---|
| Normal load | ≤ `get_effective_capacity_normal()` | Full speed (left-of-slash value) |
| Overloaded | normal < load ≤ `get_effective_capacity_max()` | Half speed (right-of-slash value) |
| Over max | > max | Rejected by `CreatureEquipmentService.validate_cargo_on_creature()` |

Color scheme: green up to normal, red zone from normal to max (with a tick at normal), rejection past max.

### 5.3 Vehicle Bands

Same two-tier model as creatures, using `DraftVehicleService.get_vehicle_capacity(item_key, team_equiv)` for normal and max.

### 5.4 Bar Component Spec

**File:** `scenes/ui/components/encumbrance_bar.gd` (new, reusable)

- Horizontal bar, fixed height ~20px
- Segmented background showing band thresholds (white tick lines at each boundary)
- Fill showing current load, colored by band
- Hover tooltip: exact load / capacity in both units and stone, current movement rate, stone-to-next-band delta
- Used in: all overlay columns, Character Sheet equipment tab, Loot modal previews

---

## 6. Party Inventory Overlay

### 6.1 Invocation and Lifecycle

- Keybind: **F9** (configurable via Settings). Toggle show/hide.
- Available in: wilderness, settlement, dungeon (out of combat). In combat, the overlay is available but transfer validation uses combat rules (§4.1).
- Implemented as a `CanvasLayer` (layer 50, between Character Sheet at 48 and Notification Display at 150).
- Non-modal — game world remains interactive behind the overlay.
- Opens with the active character's party loaded, scrolled so that column is first visible.

### 6.2 Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  PARTY INVENTORY                       [filter ▼] [search]    [X]   │
├─────────────────────────────────────────────────────────────────────┤
│  [◄]  ┌─────────┬─────────┬─────────┬─────────┬─────────┐  [►]     │
│       │ Bran    │ Yara    │ Thor    │ Mule #1 │ Cache   │          │
│       │ Fighter │ Thief   │ Cleric  │ Workbst │ (hex)   │          │
│       │ [bar]   │ [bar]   │ [bar]   │ [bar]   │         │          │
│       │ 42.50gp │ 18.00gp │ 7.25gp  │ —       │         │          │
│       │         │         │         │         │         │          │
│       │ Equipped│ Equipped│ Equipped│ Tack    │ Items   │          │
│       │ - sword │ - daggr │ - mace  │ - drft  │ - chest │          │
│       │ - chain │ - ltha  │ - chain │ - sdbg  │ - rope  │          │
│       │         │         │         │         │         │          │
│       │ Pack    │ Pack    │ Pack    │ Cargo   │ [Pick   │          │
│       │ - backp │ - sack  │ - backp │ - 15st  │  up     │          │
│       │   [...] │   [...] │   [...] │   gear  │  all]   │          │
│       │         │         │         │         │         │          │
│       │ [Prefs] │ [Prefs] │ [Prefs] │ [Prefs] │         │          │
│       └─────────┴─────────┴─────────┴─────────┴─────────┘          │
├─────────────────────────────────────────────────────────────────────┤
│  Party Total: 67.75 GP  │  Rations: 24 days  │  [Auto-distribute]  │
└─────────────────────────────────────────────────────────────────────┘
```

Scroll left/right through carriers if more exist than fit on screen. Columns have fixed width (~200px); a 1920px-wide viewport shows ~7 columns at once.

### 6.3 Filter Bar

Top-right dropdown with preset filters:

- All (default)
- Coins
- Weapons
- Armor & shields
- Ammunition
- Rations & consumables
- Light sources (torches, lanterns, oil)
- Potions
- Scrolls
- Magic items (flagged items)
- Containers
- Tack & barding (creature-relevant only)
- Tools

Applying a filter dims non-matching items across all columns to ~30% opacity. Search box filters by item name (live as you type).

### 6.4 "Prefers to carry" Tags

Each carrier has a `[Prefs]` button opening a small multi-select modal:

- Torch-bearer
- Rations-keeper
- Scroll-keeper
- Gold-purse (PC only)
- Rope-bearer
- Magic-item keeper
- Ammunition-porter
- Healing-kit keeper

Tags persist on the character record (`character_preferences` table, new, keyed by character_id). Consumed by auto-distribute (§6.5).

### 6.5 Auto-Distribute Button

Summary-footer button `[Auto-distribute]`. Opens a preview modal showing proposed moves, with `[Apply]` / `[Cancel]`.

**Algorithm:**

1. Gather all loose items across all carriers (items not equipped, not in specifically-assigned containers). Coins are excluded.
2. Partition by category (rations, torches, scrolls, etc.) to match tags.
3. For each category:
   - If any carrier has a matching preference tag and free capacity, assign to that carrier first (distribute evenly across tag-matching carriers if multiple).
   - Else fall back to generic heuristic:
     - Heavy items (≥ 1 stone) → PC with highest STR and capacity remaining
     - Ammunition → PC with matching ranged weapon equipped
     - Magic items → PCs, round-robin
     - Rations → spread evenly across animals first (their capacity is abundant), then PCs
     - Torches/oil/tools → round-robin among PCs with capacity
4. Respect encumbrance: never push a PC into a worse band than they were. If no valid target, leave the item with its current owner (do not move).
5. Return a list of proposed `{item_id, from_carrier, to_carrier, reason}` tuples.

Preview modal shows:
- Before and after encumbrance bars per carrier
- Proposed moves list
- Count of items that couldn't be redistributed (with tooltip explanation)

### 6.6 Per-Item Actions

Right-click any item row opens a quick context menu:

- **Send to…** → flyout of valid carriers
- **Drop on ground** → moves to location cache (see §8)
- **Split stack** (bundles only) → numeric input
- **View details** → opens the same tooltip the character sheet uses
- **Equip** / **Unequip** (if applicable and target is a PC/henchman)

### 6.7 Integration with Party Management Overlay

Per `pack_animal_state_report.md` Phase A recommendation, the existing Party Management overlay's Travel tab gets a new summary widget:

```
Travel Tab
──────────
Humans: 3    Pace: 60'/turn (heavy load)
Animals: 2   ┌─ Mule (Workbeast, 15/20 stone)
Vehicles: 1  └─ Small Cart (0/80 stone, 1 mule hitched)

          [Open Party Inventory]
```

Clicking the button opens the F9 overlay.

---

## 7. Loot Distribution Modal

### 7.1 Triggers

The modal fires automatically when the party acquires items at the party level rather than as a direct character pickup:

| Trigger | Source |
|---|---|
| Combat victory | `EventBus.combat_ended` with loot payload |
| Container opened | When a chest/sack is searched and contains items |
| Shop delivery | Commissioned purchase arriving (per settlement activity rules) |
| Scripted treasure event | Hand-authored quest reward, etc. |

### 7.2 Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  LOOT FOUND — Goblin Ambush                                 [X]  │
├──────────────────────────────────────────────────────────────────┤
│  Queued Items              │  Recipients                         │
│                            │                                     │
│  - 47 GP                   │  ┌──────────┬──────────┬──────────┐│
│  - 12 SP                   │  │ Bran     │ Yara     │ Thor     ││
│  - Short sword             │  │ [bar]    │ [bar]    │ [bar]    ││
│  - Leather armor           │  │ 0/5 st   │ 0/3 st   │ 0/4 st   ││
│  - 3 rations               │  │          │          │          ││
│  - Iron key                │  │ [drop]   │ [drop]   │ [drop]   ││
│  - Potion of healing       │  └──────────┴──────────┴──────────┘│
│                            │                                     │
│                            │  [+ Include henchmen]               │
│                            │  [+ Include animals/vehicles]       │
├──────────────────────────────────────────────────────────────────┤
│  [Auto-distribute]  [Edit Gold Shares]  [Drop all on ground]     │
│                                                        [Apply]   │
└──────────────────────────────────────────────────────────────────┘
```

### 7.3 Gold Handling

- Gold in the queue is displayed in full breakdown: `47 GP + 12 SP = 48.20 GP`.
- **Default behavior:** even split among present PCs via `PartyWallet.deposit_to_party_even_split()`. Banker's rounding, residual copper to poorest PC.
- **Edit Gold Shares** button opens a share-weighting modal:
  - Each PC row: name + numeric share input (default 1.0)
  - Each henchman row: name + share input (default 0.5 per ACKS henchman half-share rule)
  - Animals and vehicles excluded
  - Preview shows computed per-character amounts with banker's rounding
  - Residual CP always goes to poorest PC recipient

### 7.4 Item Handling

- **Auto-distribute** button runs the same algorithm as overlay auto-distribute (§6.5), scoped to only the queued items and the recipient carriers.
- **Drag-and-drop** from the queue to any recipient column assigns that item.
- **[drop]** button per recipient empties assignments for that recipient back to queue.
- **Drop all on ground** sends everything to the current location's cache (§8).
- Items the player doesn't assign remain in the queue. **Apply** requires the queue to be empty or confirmation that unassigned items go to the ground cache.

### 7.5 Henchman, Animal, Vehicle Inclusion

- **[+ Include henchmen]** toggles henchman columns into the recipient grid. Their gold share uses the 0.5 default.
- **[+ Include animals/vehicles]** toggles those columns in. They receive items only (no gold). Useful when loot is heavy and PC capacity is short.

### 7.6 Integration with PartyWallet

The modal calls `PartyWallet.deposit_to_party_even_split()` or `_by_shares()` for gold. Item assignments call the existing `CampaignRepository` transfer methods.

---

## 8. Location Cache Subsystem

### 8.1 Data Model

**New DB table:** `location_caches`

```sql
CREATE TABLE location_caches (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    location_type TEXT NOT NULL CHECK(location_type IN ('hex', 'dungeon_cell', 'settlement_node')),
    location_key TEXT NOT NULL,  -- "hex:12,7" or "dungeon:dungeon_id:cell:x,y" or "settlement:settlement_id:poi_id"
    cache_variant TEXT NOT NULL CHECK(cache_variant IN ('loose', 'locked_container', 'hidden_wilderness')),
    container_item_id TEXT REFERENCES inventory_items(id),  -- if cache_variant = 'locked_container'
    is_persistent BOOLEAN NOT NULL DEFAULT 0,  -- true if hidden-memorized or locked-container
    decay_check_day INTEGER DEFAULT NULL,  -- game day to check decay, null if persistent
    created_at_day INTEGER NOT NULL,
    raid_monthly_modifier INTEGER NOT NULL DEFAULT 0  -- cumulative +1 per month for hidden caches
);

CREATE INDEX location_caches_by_location ON location_caches(campaign_id, location_type, location_key);
```

**FK addition on `inventory_items`:**

```sql
ALTER TABLE inventory_items ADD COLUMN location_cache_id TEXT REFERENCES location_caches(id) DEFAULT NULL;
```

Items in a cache have `location_cache_id` set and `character_id`, `creature_id`, `vehicle_id`, `container_id`, `party_id` all NULL.

### 8.2 Cache Variants

| Variant | Creation path | Persistence | Decay rule | Raid rule |
|---|---|---|---|---|
| `loose` (dungeon) | Drop in dungeon cell without locked container | Ephemeral | Created with `decay_check_day = current_day + 1d7`. On decay day, 50% per item: delete vs. relocate to nearest pre-existing dungeon treasure cache | None |
| `locked_container` (dungeon) | Drop into a locked chest/container in dungeon cell | Permanent | None | None |
| `loose` (wilderness hex) | Drop in wilderness without hide-and-memorize | Ephemeral | Created with `decay_check_day = current_day + 1d4 × 7`. On decay day, delete all items and cache | None |
| `hidden_wilderness` | "Hide and memorize" activity in wilderness hex (1 hour Timekeeping) | Permanent unless raided | None | Monthly raid roll (see §8.4) |
| `loose` (settlement node) | Drop at settlement PoI | Ephemeral | Same as dungeon loose (1d7 days, 50/50 relocate/delete). Relocation target: any pre-existing settlement cache (e.g., fountain, forgotten alley) — deferred; for v1, always delete on decay | None |

### 8.3 "Hide and Memorize" Flow

When dropping in wilderness, the UI prompts:

```
Drop items here?

○ Drop on ground
  Items decay over 1d4 weeks. After that, lost forever.

○ Hide and memorize location (1 hour)
  Stash is permanent, but monthly risk of raid.
  Current raid risk: 0% (first month), +1% per month.

[Confirm]  [Cancel]
```

Selecting "Hide and memorize" consumes 1 hour via `Timekeeping.advance_turns(6)` (6 turns = 1 hour at 10 min/turn). Creates cache with `cache_variant='hidden_wilderness'`, `is_persistent=true`, `raid_monthly_modifier=0`.

No proficiency or skill check required. Pure time cost.

### 8.4 Monthly Raid Roll (hidden wilderness caches)

**Hook:** `Timekeeping.month_changed` signal

For each hidden wilderness cache in the current campaign:

1. `raid_monthly_modifier += 1`
2. Roll 1d100. If roll ≤ `raid_monthly_modifier`, raid fires.
3. Raid resolution:
   - Compute total value (sum of `cost_cp` across items).
   - Determine loss percentage via 2d4 curve (range 25% – 75%, bell-weighted toward 50%):

     | 2d4 roll | Loss % |
     |---|---|
     | 2 | 25% |
     | 3 | ~31% |
     | 4 | ~38% |
     | 5 | 50% |
     | 6 | ~63% |
     | 7 | ~69% |
     | 8 | 75% |

     Formula: `loss_pct = 25 + (sum - 2) * (50 / 6)`, rounded to nearest integer percent. 2d4 produces a triangular distribution peaked at 5 — so most raids take ~50%, with extreme losses rarer on both ends.
   - Sort items by value (cost_cp) descending.
   - Remove items from the top of the list until removed value ≥ target loss. Remove whole items only.
   - Reset `raid_monthly_modifier` to 0 (raid "resets the hiding place's obscurity" narratively).
4. Emit `EventBus.cache_raided(cache_id, items_lost, value_lost_gp)` for the notification system.

### 8.5 Daily Decay Check (loose caches)

**Hook:** `Timekeeping.day_changed` signal

For each ephemeral cache where `decay_check_day == current_day`:

1. For each item in cache:
   - `cache_variant='loose'` in dungeon: 50% chance to relocate, 50% to delete
     - Relocate target: if dungeon has any other cache (check for pre-existing treasure cache data from stocking, deferred to stocking phase — for v1, always delete)
   - `cache_variant='loose'` in wilderness: always delete
   - `cache_variant='loose'` in settlement: always delete (for v1)
2. Delete the cache row itself after processing.
3. Emit `EventBus.cache_decayed(cache_id, items_lost)`.

### 8.6 LocationCacheManager Subsystem

**File:** `engine/subsystems/inventory/location_cache_manager.gd` (autoload: `LocationCacheManager`)

**Public API:**

```
LocationCacheManager.create_dungeon_loose_cache(dungeon_id, cell_xy) -> cache_id
LocationCacheManager.create_dungeon_container_cache(dungeon_id, cell_xy, container_item_id) -> cache_id
LocationCacheManager.create_wilderness_loose_cache(hex_qr) -> cache_id
LocationCacheManager.create_wilderness_hidden_cache(hex_qr) -> cache_id
LocationCacheManager.create_settlement_cache(settlement_id, poi_id) -> cache_id
LocationCacheManager.get_cache_at_current_location() -> cache or null
LocationCacheManager.drop_item_to_cache(item_id, cache_id) -> bool
LocationCacheManager.pick_up_item(item_id, target_carrier_id) -> bool
LocationCacheManager.resolve_daily_decay(current_day)
LocationCacheManager.resolve_monthly_raids()
```

### 8.7 UI in Overlay

- Cache column visible in overlay when `get_cache_at_current_location()` returns non-null.
- Column header varies by variant: "Ground (loose)" / "Locked chest" / "Hidden stash".
- Decay readout: "Decays in 3 days" / "Permanent" / "Raid risk: 4% this month".
- Drag items from any carrier to the cache column to drop. If wilderness and no existing cache, drop prompts the hide-and-memorize dialog.
- "Pick up all" header button moves everything to the active character (respecting their capacity — items that don't fit stay in cache).

### 8.8 Notifications

- Cache raided: "Your stash at Hex 12,7 was raided. Lost: 200 GP, 1 ruby (total value 450 GP)."
- Cache decayed: "Items you dropped at dungeon level 2 cell (15,22) have disappeared."
- Cache will decay soon: "Items dropped at Hex 12,7 will decay in 3 days unless hidden."

---

## 9. "Send to…" Context Menu

### 9.1 Trigger Points

- Right-click any item row in the Character Sheet equipment tab
- Right-click any item row in the Party Inventory overlay (covered by §6.6)
- Right-click any item row in the Loot modal queue

### 9.2 Menu Layout

```
┌─────────────────────────┐
│ Send to ▶               │
│ Drop on ground          │
│ ─────────────────────   │
│ Split stack             │
│ View details            │
│ Equip / Unequip         │
└─────────────────────────┘
```

The **Send to ▶** sub-menu flyout lists all valid carriers (same filtering as drag-and-drop validation in §4):

```
┌─────────────────────────┐
│ Bran (+ 2 stone)        │  ← active character
│ Yara (+ 2 stone)        │
│ Thor (+ 2 stone)        │
│ ─────────────────────   │
│ Mule #1 (5 of 20 stone) │
│ Small Cart (0 of 80)    │
│ ─────────────────────   │
│ Ground                  │  ← shorthand for drop
└─────────────────────────┘
```

Capacity previews update the target's band after hypothetical transfer. Invalid targets are greyed with hover tooltip explanation.

### 9.3 Gold Items

Right-clicking coin rows shows **Transfer Gold…** instead of Send to…, opening the modal from §3.5.

---

## 10. Catalog Additions and Updates

### 10.1 Pack Saddle (new)

**New entry in `data/equipment/transport.json`:**

```json
{
  "item_key": "saddle_pack",
  "name": "Saddle and Tack (pack)",
  "category": "tack",
  "cost_cp": 500,
  "encumbrance_units": 1000,
  "notes": "Purpose-built for cargo hauling. Supports panniers, saddlebags, sacks, barrels, and purses up to the animal's full capacity. Cannot be used for riding or vehicle hitching."
}
```

**Cost and encumbrance match `saddle_draft`** (5 gp, 1 stone) — this is a split-off from ACKS RAW for code clarity, not a distinct real-world item.

### 10.2 Panniers (new)

**New entry in `data/equipment/transport.json`:**

```json
{
  "item_key": "panniers",
  "name": "Panniers (wicker baskets, pair)",
  "category": "tack",
  "cost_cp": 500,
  "encumbrance_units": 333,
  "container_capacity_units": 5000,
  "notes": "Large wicker baskets hung from a pack saddle. Greater capacity than saddlebags but bulkier."
}
```

Effect: container requiring a pack saddle (`saddle_pack`) to equip. Does NOT work with draft saddle (draft permits no containers), riding saddle (riding permits saddlebags only), or war saddle (same). Takes `pack` slot. 5 stone capacity.

### 10.3 Draft Saddle (clarification, no data change)

`saddle_draft` in `transport.json` remains as-is for cost and encumbrance, but its behavior changes under the taxonomy:

- **Does NOT permit container attachment.** This is a departure from ACKS RAW.
- Permits vehicle hitching only.
- Existing tests that assume draft saddles enable saddlebag attachment must be updated.

### 10.4 Riding Saddle (behavior clarification)

`saddle_riding` in `transport.json` remains as-is for cost and encumbrance. Behavior:

- Permits riding.
- Permits exactly 2 saddlebags attached (no panniers, no sacks, no barrels).
- Rider contributes +15 stone (15000 units) to creature load plus their own carried encumbrance.
- On damage while mounted, rider must save vs Paralysis or be dismounted (per ACKS RAW, preserved here).

### 10.5 War Saddle (behavior clarification)

`saddle_war` in `transport.json` remains as-is. Identical to riding saddle except the dismount save is removed. Rider is stable on damage.

### 10.6 Rope as Pseudo-Saddle (behavior change)

`rope_50ft` in `base_equipment.json` gains new semantics when present on a creature:

- Treated as a rigging state mutually exclusive with saddles.
- Permits attachment of: large sack, small sack, backpack, barrel, pouch/purse (any count).
- Does NOT permit saddlebags (those specifically require a saddle) or panniers.
- Capacity multiplier: 0.5× (implementing the "rope doubles encumbrance" rule via halved capacity — mathematically equivalent, per existing `get_load_multiplier()`).
- Does not permit riding or hitching.

When a saddle is equipped, rope becomes ordinary cargo again (no rigging effect).

### 10.7 CreatureEquipmentService Updates

`validate_equip_on_creature()` (in `engine/subsystems/characters/creature_equipment_service.gd`) must be rewritten to enforce the §2.3a taxonomy. Summary of required changes:

- **Saddle type enum awareness.** The service must distinguish between `saddle_draft`, `saddle_pack`, `saddle_riding`, `saddle_war` — not just "any saddle".
- **Container-to-saddle validation matrix:**
  - `saddle_draft` → rejects all container attachment
  - `saddle_pack` → accepts panniers, saddlebags, large sack, small sack, barrel, pouch/purse
  - `saddle_riding` / `saddle_war` → accepts saddlebags only, maximum 2, rejects all others
  - Rope-lashed (no saddle + `rope_50ft`) → accepts sacks, backpacks, barrels, pouches; rejects saddlebags and panniers
- **Hitching validation:** `DraftVehicleService.validate_hitch()` must check for `saddle_draft` specifically, not any saddle. Creatures with pack/riding/war saddles cannot be hitched.
- **Riding validation (new, for future mount/rider binding):** riding requires `saddle_riding` or `saddle_war`. Other rigging states reject.
- **Rigging mutual exclusivity:** equipping a saddle while rope is equipped as rigging un-rigs the rope (rope becomes cargo). Equipping rope while a saddle is equipped is rejected (unequip saddle first).

`TrainedCreatureData.get_load_multiplier()` (currently line 214) keeps its 0.0 / 0.5 / 1.0 return values but the saddle check must accept `saddle_draft`, `saddle_pack`, `saddle_riding`, and `saddle_war` as 1.0× triggers.

### 10.8 Existing Code Conformance

This taxonomy supersedes any prior saddle behavior in the codebase. During Session 5 implementation, the build agent should:

1. Grep for references to `saddle_` item keys across all GDScript files
2. Audit each call site against the §2.3a table
3. Update any validator, multiplier calculation, or UI label that assumes old ACKS-RAW behavior
4. Update existing tests in `tests/test_creature_equipment_service.gd` and `tests/test_trained_creature_data.gd` to assert the new rules
5. Add new tests covering each saddle type's container permissions, the riding/dismount save hook, and the hitching restriction

---

## 11. Integration Points

### 11.1 Session Runner

Each session state (`WildernessExploreState`, `DungeonExploreState`, `SettlementExploreState`, `CombatState`) exposes a `get_current_location_key()` method returning the string used by the location cache system:

- Wilderness: `"hex:q,r"`
- Dungeon: `"dungeon:<dungeon_id>:cell:<x>,<y>"`
- Settlement: `"settlement:<settlement_id>:poi:<poi_id>"` (or just the settlement for settlement-wide)
- Combat: falls through to parent context (dungeon or wilderness)

The Party Inventory overlay queries the session runner for the active location at open time, and refreshes when session state transitions occur.

### 11.2 Settlement Context

Wallet eligibility in a settlement is settlement-wide, not PoI-specific. A PC carousing at the tavern is still in the wallet when the fighter is buying at the smith. Intra-settlement travel time is minutes.

### 11.3 Dungeon Adjacency

Transfer validation in dungeon-out-of-combat calls a helper: `DungeonMapController.are_adjacent(carrier_a_cell, carrier_b_cell) -> bool`. Returns true if the Chebyshev distance is ≤ 1 and there is no impassable wall between them.

### 11.4 Combat Action Economy

In-combat trade actions are routed through `CombatUIController` as a new action type: `trade_item`. One `trade_item` action per entity per round. Ammunition auto-share uses a separate code path (`transfer_ammo_free_action`) that does not consume the trade action slot and does not advance the turn.

`ActionButtonPanel` adds a "Trade" button, enabled when there's an adjacent friendly combatant.

### 11.5 Shop Integration

Shop transactions already use gold. Replace direct character-gold deduction with `PartyWallet.pay(cost_gp, active_character_id)`. The shop's gold display shows party-wallet total. Insufficient funds modal shows contributor breakdown: "Party has 240 GP (Bran 42, Yara 18, Thor 180)."

### 11.6 Henchman Hiring

`HenchmanLifecycleManager.attempt_hire()` and `process_monthly_wages()` call `PartyWallet.pay()` for search fees and wages. Wages are paid FROM the party wallet TO the henchman's character record (which then shows up in the henchman's personal gold display).

---

## 12. Implementation Phasing

Recommended session breakdown for the build agent. Each session is coherent, independently testable, and roughly equivalent in complexity.

### 12.1 Session 1 — PartyWallet + Gold Refactor

- `PartyWallet` autoload with full public API
- Float display + breakdown popover component (`scenes/ui/components/gold_display.gd`)
- Encumbrance color bands component (`scenes/ui/components/encumbrance_bar.gd`)
- Wire PartyWallet into shop screen, character sheet header, henchman lifecycle
- Test suite: ~20 tests (eligibility, deduction order, denomination conversion, banker's rounding)

**Complexity: 3.** Touches many existing UI sites; shop/shopping regression risk.

### 12.2 Session 2 — Location Cache Subsystem

- Migration for `location_caches` table and `location_cache_id` FK
- `LocationCacheManager` autoload
- Timekeeping signal hooks (daily decay, monthly raid)
- Hide-and-memorize flow (time cost, no proficiency check)
- EventBus signals: `cache_created`, `cache_decayed`, `cache_raided`, `cache_picked_up`
- Test suite: ~25 tests (variant creation, decay math, raid math with deterministic dice, pickup, persistence across save/load)

**Complexity: 3.** New subsystem with time-signal integration and probabilistic logic.

### 12.3 Session 3 — Party Inventory Overlay

- `PartyInventoryOverlay` scene (CanvasLayer, F9 keybind)
- `CarrierColumn` reusable component with 5 variants (PC, henchman, creature, vehicle, cache)
- Filter bar, search box, summary footer
- Drag-and-drop transfer validation layer
- Per-item context menu (§6.6)
- "Prefers to carry" tag system with `character_preferences` table
- Test suite: ~20 tests (transfer validation, filter, preference persistence, column layout)

**Complexity: 3.** Heavy UI work with many variants.

### 12.4 Session 4 — Loot Distribution Modal + Auto-Distribute

- `LootDistributionModal` scene
- Auto-distribute algorithm (shared implementation used by overlay and modal)
- Gold share-weighting modal
- EventBus wiring: `combat_ended` → open modal with loot payload, `container_opened` → same, `shop_commission_delivered` → same
- Test suite: ~15 tests (auto-distribute with/without prefs, even split math, share math, edge cases)

**Complexity: 2.** Well-patterned UI; algorithm is self-contained and testable.

### 12.5 Session 5 — Saddle Taxonomy Cleanup, Catalog, Context Menu, Party Management Integration

- **Saddle taxonomy conformance pass (§2.3a and §10):**
  - Rewrite `CreatureEquipmentService.validate_equip_on_creature()` to enforce per-saddle container matrix
  - Update `DraftVehicleService.validate_hitch()` to accept only `saddle_draft`
  - Update `TrainedCreatureData.get_load_multiplier()` to recognize all four saddle types
  - Grep and audit all existing references to saddle item keys; update any drift
  - Update all existing tests in `test_creature_equipment_service.gd` and `test_trained_creature_data.gd` to assert the taxonomy table
- **Catalog additions:** `saddle_pack`, `panniers` entries in `transport.json`
- **Rider encumbrance hook:** `TrainedCreatureData.get_current_load_units()` accepts an optional rider contribution (+15000 units + rider.encumbrance_units) when riding/war saddle is equipped — stub for Phase C mount/rider binding, return 0 for rider if none bound
- **Dismount save hook:** `CombatResolver` gains a hook point (signal or callable) that fires after damage is applied to a mounted entity; riding saddle triggers save vs Paralysis, war saddle does not. Save resolution deferred to future combat session — the hook just emits the event
- **"Send to…" context menu** on character sheet equipment tab and loot modal
- **Party Management overlay Travel tab:** creature/vehicle summary widget + Open Party Inventory button
- Test suite: ~20 tests (saddle taxonomy table × container types, hitching restriction to draft saddle, rope-vs-saddle mutual exclusivity, rider encumbrance +15 stone, context menu invocation, party mgmt widget data)

**Complexity: 3.** Bumped from 2 because the saddle taxonomy cleanup is a codebase-wide audit plus test rewrite, not just additive work. The `CreatureEquipmentService` rewrite is the critical piece — any drift here breaks the overlay's validation layer from Session 3.

### 12.6 Total Scope

~100 tests added. 5 new autoloads/subsystems or equivalents (PartyWallet, LocationCacheManager, gold display component, encumbrance bar component, auto-distribute helper). ~8 new scene files. 1 new migration. 2 new catalog entries. Saddle taxonomy cleanup touches `CreatureEquipmentService`, `DraftVehicleService`, `TrainedCreatureData`, plus their existing test suites. Estimated 5 build sessions of 3–5 hours each for a focused model.

---

## 13. Open Questions and Explicit Deferrals

### 13.1 Open

- **Relocation target for decayed dungeon caches:** §8.2 and §8.5 reference "pre-existing dungeon treasure cache" as relocation target for 50% of decaying items. Dungeon stocking doesn't yet produce named treasure caches. For v1, decayed items always delete; relocation logic to be added when stocking supports named caches.
- **Settlement loose cache decay target:** Same issue. v1: always delete.
- **Currency exchange:** The system implicitly converts denominations when paying (CP first, then SP, etc.). Should there be an explicit "Exchange Coins" UX for players who want to consolidate 100 CP into 1 GP before carrying? Current answer: no — leave this to manual shop visits or assume moneychangers at markets.

### 13.2 Deferred (explicitly out of scope here)

- Mount/rider binding — Phase C in audit report
- Animal training UI — Phase C
- Elephant catalog entry — Phase C
- Henchman auto-spending on clothes/wine (verisimilitude polish) — end-project polish
- Mercenary contract tracking and payment — future hireling session
- Stronghold storage (uses `party_id` FK) — Phase H (Domain Layer)
- Magic item identification flow (affects "Magic items" filter) — separate magic item system work
- Partial pickups ("pick up 50 of 100 arrows") — v1 supports whole-item and split-stack only

---

## 14. Cross-References

- `gdd-settlement-exploration-ui.md` §4 — activity system that integrates with "Hide and memorize" time cost
- `gdd-dungeon-map-ui.md` §3.1, §3.3 — drop/pickup UX in dungeons, in-combat trade actions
- `gdd-combat-ui.md` §5 — action economy; trade actions, ammo share
- `gdd-realtime-scheduler.md` — settlement block travel (wallet eligibility)
- `pack_animal_state_report.md` — audit informing the catalog additions and integration points
- `acks_arbiter_build_plan.md` — phase E-1 (party management) cross-link; this GDD effectively completes E-1's inventory scope
- `coding_conventions.md` §6 (DB migrations), §3 (subsystem patterns)

---

## 15. Acceptance Criteria

Phase A (sessions 1–5 of §12) is complete when:

1. Player can press F9 at any time, see all party carriers in columns with correct encumbrance/capacity displays.
2. Player can drag any non-locked item between any valid carriers, with rejections showing clear tooltips.
3. Gold displays as float with hover breakdown everywhere relevant; PartyWallet aggregates correctly across PCs, excludes henchmen.
4. Shops deduct from party wallet; henchman wages paid from party wallet.
5. Player can drop items in dungeon cells, wilderness hexes, and settlement PoIs; caches persist or decay per rules.
6. Hide-and-memorize flow works in wilderness with 1-hour time cost; monthly raid rolls resolve correctly.
7. Loot modal fires after combat, offers auto-distribute and gold share-edit, routes to ground on skip.
8. "Send to…" context menu works from character sheet and loot modal.
9. Pack saddle and panniers purchasable and usable on creatures.
10. Party Management Travel tab shows creature/vehicle summary and links to Party Inventory overlay.
11. All ~90 tests pass alongside existing suite with no regression.
