# Pack Animal & Vehicle State Audit

**Date:** 2026-04-17
**Model:** Opus 4.6
**Purpose:** Read-only investigation to determine current state of pack animal and vehicle support before designing the Party Inventory overlay.

**Executive summary:** Pack animal and vehicle support is **substantially implemented**. The codebase has dedicated DB tables, a first-class `TrainedCreatureData` type, equipment validation services, vehicle capacity/hitch logic, travel speed integration, and character sheet UI for both animals and vehicles. The remaining work for the Party Inventory overlay is primarily a new UI panel and item transfer UX — not foundational engine rewiring.

---

## Section 1: Entity Model

### 1.1 Purchase flow — what happens when the player buys a mule?

**Step 1 — Equipment shop adds an InventoryItem to the cart.**
In `equipment_shop_panel.gd:477` (`_on_buy_item()`), the item's cost is deducted from gold (line 486), and the item is converted to a cart-compatible dictionary via `_catalog_item_to_cart()` (line 531). The mule is stored in `_state["inventory"]` as a dictionary with `item_key: "mule"`, `item_category: "pack_animal"`, `slot: "pack"`, `is_equipped: 0`. At this stage the animal is just an inventory entry — no separate entity row exists.

**Step 2 — Character finalization converts the inventory item to a trained creature.**
When the character is finalized, `CampaignRepository.save_character_inventory_with_creatures()` (line 1346) iterates the inventory. For each item, it looks up the catalog entry via `EquipmentCatalog.get_item()`. If the catalog entry has a `monster_id` AND the category is not `"livestock"` (line 1363), the item is converted to a creature:

- `create_creature_from_purchase()` (line 1298) is called once per quantity.
- The creature's monster stats are fetched from `MonsterRegistry`.
- HP is rolled from the species' hit dice (lines 1312–1320).
- Role is assigned from `_CREATURE_ROLE_MAP` (line 1265): `"mule"` → `"WB"` (Workbeast).
- Default tricks are assigned from `_DEFAULT_TRICKS` (line 1287): `"WB"` → `["come", "heel", "stay", "work"]`.
- Morale is copied from monster data (line 1324).
- A `trained_creatures` row is inserted via `create_trained_creature()` (line 2107).

The original inventory item is **not** saved to `inventory_items` — it is consumed by the creature conversion. Regular (non-animal) items continue to `save_character_inventory()` (line 1372).

### 1.2 Does the purchased animal get an entity row?

**Yes.** The animal gets a row in the `trained_creatures` table (`schema.sql:187`), not in `characters`. Fields populated:

| Column | Value for a mule | Source |
|--------|-------------------|--------|
| `id` | Generated hex string | `generate_id()` |
| `campaign_id` | From caller | Parameter |
| `party_id` | From caller | Parameter |
| `species_id` | `"mule"` | `transport.json` `monster_id` |
| `purchase_item_key` | `"mule"` | `transport.json` `item_key` |
| `role` | `"WB"` | `_CREATURE_ROLE_MAP` |
| `handler_id` | Purchasing character ID | Parameter |
| `hp_current` / `hp_max` | Rolled from monster HD | `create_creature_from_purchase()` |
| `morale` | From monster data | `monster_catalog.json` |
| `tricks_known` | `'["come","heel","stay","work"]'` | `_DEFAULT_TRICKS` |
| `trick_limit` | 9 (5 + 4 default tricks) | Line 1334 |
| `training_complete` | 1 | Default |
| `is_alive` | 1 | Default |

This differs from a PC/henchman row (which lives in `characters` table with ability scores, class, level, XP, etc.). The `trained_creatures` table has no ability scores, no class, no level �� stats come from `monster_catalog.json` at runtime via `species_id`.

### 1.3 If no entity row is created (inventory-only path)

This case applies only to **livestock** (`item_category: "livestock"` — cow, goat, sheep). Livestock items remain in `inventory_items` as regular items. The preserved data is limited to what `InventoryItem` stores: item_key, name, quantity, encumbrance_units, item_category. No capacity, movement rate, or HP are tracked for livestock-as-inventory.

### 1.4 Can `inventory_items.creature_id` accept an animal entity ID?

**Yes.** `inventory_items` has three nullable FK columns for multi-owner support (`schema.sql:177-181`):

```sql
party_id TEXT REFERENCES parties(id) DEFAULT NULL,          -- line 177
creature_id TEXT REFERENCES trained_creatures(id) DEFAULT NULL,  -- line 179
vehicle_id TEXT REFERENCES draft_vehicles(id) DEFAULT NULL       -- line 181
```

`creature_id` is a FK to `trained_creatures(id)`. Items with `creature_id` set belong to that creature (saddles, barding, saddlebags, loose cargo). The `character_id` column remains `NOT NULL` even for creature-owned items — it appears to reference the handler/originating character.

CampaignRepository provides transfer methods to move items between owners:
- `transfer_item_to_creature()` (line 2254)
- `transfer_item_from_creature_to_character()` (line 2263)
- `transfer_item_from_creature_to_party()` (line 2272)
- `transfer_item_to_vehicle()` (line 2281)
- `transfer_item_from_vehicle_to_character()` (line 2290)
- `transfer_item_from_vehicle_to_party()` (line 2299)
- `equip_creature_item()` (line 2308)
- `unequip_creature_item()` (line 2317)

### 1.5 Are all animal types handled consistently?

**Yes.** All non-livestock animals follow the same `create_creature_from_purchase()` code path. The only variation is role assignment via `_CREATURE_ROLE_MAP` (`campaign_repository.gd:1265`):

| item_key | Role | Meaning |
|----------|------|---------|
| `light_warhorse`, `medium_warhorse`, `heavy_warhorse` | `WM` | War Mount |
| `camel`, `medium_riding_horse`, `light_riding_horse` | `M` | Mount |
| `donkey`, `mule`, `ox`, `heavy_draft_horse`, `medium_draft_horse` | `WB` | Workbeast |
| `war_dog` | `G` | Guard |
| `hunting_dog`, `hawk_trained` | `H` | Hunter |

Livestock (`cow`, `goat`, `sheep`) are the exception — they stay as inventory items per the `cat != "livestock"` check at line 1363.

**Not in catalog:** Elephant. Referenced in `acore_equipment.xml` animal movement table but has no `transport.json` entry and no monster_catalog entry.

### 1.6 Does CharacterData distinguish humanoid from animal?

**No.** `CharacterData` (`engine/shared_types/character_data.gd`) has no `entity_type`, `is_animal`, `has_hands`, `size`, or similar field. It is purely humanoid-oriented (ability scores, class, level, XP, race, alignment).

Animals use `TrainedCreatureData` (`engine/shared_types/trained_creature_data.gd`) — a completely separate class. The two types never cross: characters are always `CharacterData`, creatures are always `TrainedCreatureData`. The consequence for the Party Inventory overlay is **positive**: there is no risk of accidentally treating an animal as a humanoid because the type system enforces the distinction. The overlay must render two different panel layouts — one for `CharacterData` entities (equipped slots, gold purse) and one for `TrainedCreatureData` entities (tack, cargo, capacity bar).

---

## Section 2: Party Association

### 2.1 Party membership table and animal eligibility

The `party_members` table (`schema.sql:97`) links parties to characters only:

```sql
party_id TEXT NOT NULL REFERENCES parties(id),
character_id TEXT NOT NULL REFERENCES characters(id),
PRIMARY KEY (party_id, character_id)
```

**Animals cannot be party members** through this table — the FK constrains to `characters(id)`, and animals live in `trained_creatures`. Instead, animals associate with parties via `trained_creatures.party_id` (`schema.sql:190`), a nullable FK to `parties(id)`.

### 2.2 Does PartyData distinguish humanoid from animal members?

**Yes.** `PartyData` (`engine/shared_types/party_data.gd`) maintains separate runtime arrays:

- `character_data: Array` (line 66) — humanoid members (`CharacterData` instances)
- `creature_data: Array` (line 74) — animals (`TrainedCreatureData` instances)
- `vehicle_data: Array` (line 78) — carts/wagons (Dictionary)
- `shared_inventory: Array` (line 70) — party-level items

Session loading populates all four arrays (`session_runner.gd:297-322`):
- Characters: `CampaignRepository.list_party_characters()` → `CharacterData.from_dict()` (lines 301-304)
- Creatures: `CampaignRepository.get_trained_creatures_for_party()` → `TrainedCreatureData.from_db()`, with monster_data and creature inventory loaded (lines 311-320)
- Vehicles: `CampaignRepository.get_draft_vehicles_for_party()` (line 322)

`get_slowest_movement()` (`party_data.gd:191`) iterates **all three**: characters (line 195-198), creatures (line 199-202), and vehicles (line 204-206). If a mule is overloaded and moving at 60'/turn, it correctly constrains the party speed.

### 2.3 Is animal movement speed used by the travel speed calculator?

**Yes.** `TravelSpeedCalculator` (`engine/subsystems/exploration/travel_speed_calculator.gd`) calls `PartyData.get_slowest_movement()`, which includes creature movement. Individual creature speed comes from `TrainedCreatureData.get_effective_movement()` (line 143), which reads from `monster_data.movement.land.exploration` — the same values as `acore_equipment.xml` animal movement table (mule 120'/60', horse light 240'/120', etc.).

### 2.4 Two-tier normal/maximum load speed transition

**Implemented.** `TrainedCreatureData` implements the two-tier system:

1. **Normal load → full speed:** `is_overloaded()` (line 210) returns false when `get_current_load_stone() <= get_effective_capacity_normal()`.
2. **Overloaded → half speed:** `get_effective_movement()` (line 143) returns `_bankers_round(base / 2.0)` when overloaded.
3. **Beyond max → rejected:** `CreatureEquipmentService.validate_cargo_on_creature()` (line 62) checks against `get_effective_capacity_max()` and returns an error message if exceeded.

Carrying capacity values come from `monster_data.special_abilities` with `ability_id: "carrying_capacity"`, which stores `load_stone_normal` and `load_stone_max` (lines 153-166).

---

## Section 3: Tack and Inventory

### 3.1 Equipment catalog entries

**Saddles and tack** (all in `data/equipment/transport.json`):

| item_key | name | category | encumbrance_units | notes |
|----------|------|----------|-------------------|-------|
| `saddle_draft` | Saddle and Tack (draft) | tack | 1000 | Cannot be used for riding |
| `saddle_riding` | Saddle and Tack (riding) | tack | 1000 | Standard riding saddle |
| `saddle_war` | Saddle and Tack (war) | tack | 1000 | Combat saddle, knock-off protection |
| `saddlebags` | Saddlebags (leather) | tack | 167 | container_capacity_units: 3000 (3 stone) |
| `caparison` | Caparison (warhorse) | tack | 1000 | Decorative cloth |

**Barding** (5 entries):

| item_key | armor_ac_bonus | encumbrance_units |
|----------|---------------|-------------------|
| `barding_leather` | 1 | 1000 |
| `barding_scale` | 2 | 2000 |
| `barding_chain` | 3 | 3000 |
| `barding_lamellar` | 4 | 4000 |
| `barding_plate` | 5 | 5000 |

**Containers** (in `data/equipment/base_equipment.json`):

| item_key | container_capacity_units |
|----------|------------------------|
| `backpack` | 4000 (4 stone) |
| `sack_small` | 2000 (2 stone) |
| `sack_large` | 6000 (6 stone) |
| `pouch` | 500 (0.5 stone) |
| `chest_ironbound` | 20000 (20 stone) |

**Rope:** `rope_50ft` in `base_equipment.json` — 1gp, bears up to 45 stone.

**Not found:** pack saddle (distinct from draft/riding/war), panniers/pack baskets.

### 3.2 Equipped tack slot concept

**Implemented.** `CreatureEquipmentService` (`engine/subsystems/characters/creature_equipment_service.gd`) defines slot mapping:

| Item type | Slot | is_equipped |
|-----------|------|-------------|
| Barding | `"body"` | true |
| Saddle (any `saddle_*`) | `"mount"` | true |
| Saddlebags | `"pack"` | true |
| Caparison | `"pack"` | true |
| Loose cargo | `"pack"` | false |

Slot determination: `determine_creature_slot()` (line 110). These reuse the existing `inventory_items.slot` CHECK constraint values; the `creature_id` FK distinguishes creature-owned from character-owned items.

Validation rules (`validate_equip_on_creature()`, line 19):
- Barding: creature must be size large+ (`can_equip_barding()`, `trained_creature_data.gd:266`)
- Saddle: only M, WM, WB roles (`can_equip_saddle()`, line 270)
- Saddlebags: require a saddle already equipped (line 44)
- Caparison: require a saddle already equipped (line 52)
- One of each allowed (duplicate checks at lines 30, 39, 47, 55)

### 3.3 Container attachment to tacked animals

**Implemented.** Saddlebags are a container with `container_capacity_units: 3000`. When equipped on a creature (via `equip_creature_item()`, `campaign_repository.gd:2308`), items can be placed into the saddlebags using `validate_into_saddlebags()` (`creature_equipment_service.gd:76`), which checks the saddlebag exists, is equipped, and has remaining capacity. Items inside the saddlebags use the `container_id` FK to reference the saddlebag's `inventory_items.id`.

The creature inventory UI (`cs_tab_creature_inventory.gd`) displays saddlebag contents separately and supports equip/unequip flows.

### 3.4 Rope-lashing x2 encumbrance rule

**Implemented as 0.5x capacity multiplier.** `TrainedCreatureData.get_load_multiplier()` (line 214):

```
Draft saddle equipped → 1.0 (full capacity)
Rope (rope_50ft) in inventory → 0.5 (half capacity)
No rigging → 0.0 (no cargo capacity at all)
```

The `_has_rope_in_inventory()` helper (line 298) checks for `item_key == "rope_50ft"` among the creature's inventory items.

Halving capacity is mathematically equivalent to doubling encumbrance: a mule with rope has effective normal capacity of 10 stone (vs. 20 with draft saddle). This means 10 stone of cargo overloads the mule (half speed), and 20 stone is the absolute maximum — matching the intent of the "doubles encumbrance" project-designed rule.

**Note:** With rope, saddlebags cannot be equipped (saddlebags require a saddle per `validate_equip_on_creature()` line 44). So the rope path supports only loose cargo, not containerized cargo.

**Tests exist:** `test_load_multiplier_with_rope()`, `test_load_multiplier_with_draft_saddle()`, `test_load_multiplier_without_rigging()` in `tests/test_trained_creature_data.gd`.

### 3.5 Encumbrance calculator — animal vs. PC

**Separate systems.** `EncumbranceCalculator` (`engine/subsystems/characters/encumbrance_calculator.gd`) handles the four-band PC system (5/7/10/20 stone thresholds). It has no animal-specific code.

Animals use `TrainedCreatureData` methods directly:
- `get_carrying_capacity_normal()` / `get_carrying_capacity_max()` (lines 153/161) — from monster special_abilities
- `get_effective_capacity_normal()` / `get_effective_capacity_max()` (lines 169/175) — adjusted by load multiplier
- `get_current_load_units()` (line 181) — sums inventory weight, excluding saddlebag contents
- `is_overloaded()` (line 210) — compares current load to effective normal capacity

---

## Section 4: Vehicles and Prime Movers

### 4.1 Vehicle catalog entries

Three vehicles in `data/equipment/transport.json`:

| item_key | name | cost_cp |
|----------|------|---------|
| `cart_small` | Cart (small) | 2500 |
| `cart_large` | Cart (large) | 5000 |
| `wagon` | Wagon | 20000 |

Vehicle movement/load fields are zeroed in the catalog — capacity depends entirely on the draft team composition, calculated at runtime.

### 4.2 Prime mover concept

**Implemented.** `draft_vehicles` table (`schema.sql:214`) has:

```sql
hitched_creatures TEXT NOT NULL DEFAULT '[]'
```

This is a JSON array of `trained_creatures.id` values. The linkage is: `draft_vehicles.hitched_creatures` → array of creature IDs → each creature is a `trained_creatures` row.

`DraftVehicleService` (`engine/subsystems/characters/draft_vehicle_service.gd`) implements the full ACKS draft team system:

**Draft equivalents** (line 33):
| species_id | Equivalents |
|------------|-------------|
| `horse_heavy` | 1.0 |
| `ox` | 1.0 |
| `camel` | 1.0 |
| `horse_medium` | 0.5 |
| `mule` | 0.5 |
| `donkey` | 0.5 |

**Maximum team size** (line 43): cart_small 1.0 equiv, cart_large 2.0, wagon 4.0.

**Hitch validation** (`validate_hitch()`, line 93): creature must be alive, must have draft saddle equipped, must not already be hitched to this vehicle, and team cannot exceed max equiv.

CampaignRepository methods: `update_draft_vehicle_hitch()` (line 2367), `create_draft_vehicle()` (line 2330).

### 4.3 Can a vehicle hold inventory?

**Yes.** `inventory_items.vehicle_id` (`schema.sql:181`) is a nullable FK to `draft_vehicles(id)`. Items with `vehicle_id` set are cargo in that vehicle.

Repository methods:
- `get_items_in_vehicle(vehicle_id)` (line 2409) — fetches all items with that vehicle_id
- `transfer_item_to_vehicle(item_id, vehicle_id)` (line 2281) — moves an item into a vehicle
- `transfer_item_from_vehicle_to_character()` / `transfer_item_from_vehicle_to_party()` (lines 2290/2299) — moves items out

### 4.4 Team size rules

**Implemented.** `DraftVehicleService.VEHICLE_CAPACITY` (`draft_vehicle_service.gd:17`) is the ACKS-sacred capacity table:

| Vehicle | Team equiv | Normal load | Max load | Speed normal | Speed loaded |
|---------|------------|-------------|----------|--------------|--------------|
| cart_small | 1.0 | 80 stone | 160 stone | 60'/turn | 30'/turn |
| cart_small | 0.5 | 35 stone | 70 stone | 60'/turn | 30'/turn |
| cart_large | 2.0 | 120 stone | 240 stone | 60'/turn | 30'/turn |
| cart_large | 1.0 | 80 stone | 160 stone | 60'/turn | 30'/turn |
| wagon | 4.0 | 320 stone | 640 stone | 60'/turn | 30'/turn |
| wagon | 2.0 | 160 stone | 320 stone | 60'/turn | 30'/turn |

`get_vehicle_capacity(item_key, team_equiv)` (line 70) matches the best applicable tier. `is_vehicle_mobile()` (line 84) returns false if no tier matches (insufficient draft power).

### 4.5 Travel speed with wagons and hitched horses

`PartyData.get_slowest_movement()` (`party_data.gd:191`) applies `VEHICLE_SPEED = 60` (line 21) as a cap if any vehicles are present (line 204-206). This means a party with a wagon and 4 heavy horses moves at 60'/turn regardless of the horses' individual speed — matching ACKS rules where all vehicle configurations move at 60'/30'.

`TravelSpeedCalculator` then applies terrain and forced-march modifiers to this base.

---

## Section 5: UI Surface

### 5.1 Mule in Party Management overlay

**Animals do NOT appear.** `party_management_overlay.gd` (line 1) documents itself as showing party composition, formation grid, and travel speed. The Members tab shows characters only (`_party.character_data`). The Formation tab is a 5x12 character grid. The Travel tab displays `get_slowest_movement()` which **does** account for creatures, but no individual creature information is shown.

EventBus creature signals (`creature_added`, `creature_removed`, etc.) are **not connected** in the party management overlay.

### 5.2 Character sheet for animals

**Works correctly — does not crash.** The character sheet overlay (`character_sheet_overlay.gd:166-172`) has five category buttons: Characters, Henchmen, **Animals**, **Vehicles**, Mercenaries.

Selecting "Animals" loads `CampaignRepository.get_trained_creatures_for_party()` and displays the creature list in the sidebar. Selecting a creature shows **two tabs**:

1. **Stats** (`cs_tab_creature_stats.gd`) — identity (name, species, role), combat stats (AC with barding, HD, HP, attacks, movement, morale, save_as), encumbrance (load/capacity, overload warning), handlers, status, tricks.
2. **Inventory** (`cs_tab_creature_inventory.gd`) — equipment slots (barding, saddle, saddlebags, caparison) with equip/unequip buttons, saddlebag contents, loose cargo, encumbrance summary with load multiplier note.

No humanoid-specific tabs render (no proficiency, spell, advancement, or biography tabs). The character sheet detects the active category and swaps the content panels accordingly.

Selecting "Vehicles" shows a single panel (`cs_vehicle_detail_panel.gd`) with: draft team (hitched creatures, equiv values, unhitch buttons), hitch dropdown (eligible creatures with draft saddles), capacity (load/normal/max with speed), and cargo list.

### 5.3 Equipment shop — humanoid vs. animal gear distinction

**No distinction.** The shop categorizes items by tab (`equipment_shop_panel.gd:21`): the "Transport" tab includes `mount`, `pack_animal`, `draft_animal`, `vehicle`, `tack`, `barding`, `livestock`, `companion_animal`. All items within each tab are purchasable by any character — there is no validation that prevents a fighter from buying barding or a mule from being purchased by a mage.

However, the Retainers tab on the character sheet (`cs_tab_retainers.gd:12`) filters inventory items by `ANIMAL_CATEGORIES = ["mount", "pack_animal", "draft_animal", "livestock", "companion_animal"]` to display animals separately. The Equipment tab (`cs_tab_equipment.gd:195`) explicitly **excludes** items in those categories, so animals don't appear in the humanoid gear list.

### 5.4 Existing animal-as-carrier UI elements

**Partial — exists in the character sheet, not as a standalone overlay.**

- `cs_tab_creature_inventory.gd` displays a creature's inventory with capacity bar and equip/unequip flows. This is an animal-as-carrier view but is accessed per-creature through the character sheet, not as a party-wide overview.
- `cs_vehicle_detail_panel.gd` displays vehicle cargo with capacity and draft team. Same limitation — accessed per-vehicle.
- **No party-wide "all carriers at a glance" view exists.** The `shared_inventory` array on `PartyData` (line 70) is populated from DB but has no dedicated UI panel anywhere.

---

## Section 6: Recommended Cleanup Phasing

### Phase A: Must-have for Party Inventory overlay

**Goal:** Pack animals appear as carriers in the new overlay with working tack, inventory, and encumbrance. Vehicles can be included in Phase A since the engine infrastructure is already complete.

**New code:**

| File | Description |
|------|-------------|
| `scenes/ui/party_inventory/party_inventory_overlay.gd` | New overlay showing all carriers: PCs/henchmen (equipped slots + pack), creatures (tack + cargo + saddlebags), vehicles (cargo + draft team), shared party pool. Item drag-and-drop or button-based transfers between carriers. |
| `scenes/ui/party_inventory/party_inventory_overlay.tscn` | Scene tree for above |
| `scenes/ui/party_inventory/carrier_panel.gd` | Reusable panel component for one carrier entity (character, creature, or vehicle) showing contents and capacity |

**Changes to existing code:**

| File | Change |
|------|--------|
| `engine/subsystems/session/states/*.gd` (relevant state) | Wire toggle keybind for party inventory overlay (e.g., Ctrl+I) |
| `engine/autoloads/event_bus.gd` | Add `party_inventory_toggled` signal if needed |
| `scenes/ui/party_management/party_management_overlay.gd` | Add creature/vehicle summary section to Travel tab showing animal count, vehicle count, and their contribution to slowest movement |

**New DB migrations:** None required. The schema already supports all needed FKs (`creature_id`, `vehicle_id`, `party_id`, `container_id` on `inventory_items`).

**Tests to add/modify:**

| File | Scope |
|------|-------|
| `tests/test_party_inventory_transfers.gd` | Integration tests: transfer item character→creature, creature→vehicle, vehicle→party, verify FK state after each transfer |

**Complexity: 3.** Multiple panel types (character, creature, vehicle) with different layouts, transfer validation across carrier types, encumbrance recalculation on transfer. The engine layer is already solid — this is primarily UI integration work, but the variety of carrier types and transfer paths makes it non-trivial.

**Cross-reference:** Overlaps with E-1 (Party Management) in `acks_arbiter_build_plan.md` — the party inventory overlay could be a tab within the party management UI or a separate overlay. The party management overlay's Travel tab already calls `get_slowest_movement()` which accounts for creatures; adding a creature/vehicle summary there is natural.

---

### Phase B: Should-have

**Goal:** Vehicle terrain restrictions, catalog completions, and polish.

**New code:**

| File | Description |
|------|-------------|
| `data/equipment/transport.json` | Add `pack_saddle` entry (distinct from draft saddle — optimized for cargo, not riding or pulling), add `panniers` entry (container, attaches to pack saddle) |

**Changes to existing code:**

| File | Change |
|------|--------|
| `engine/subsystems/exploration/travel_speed_calculator.gd` | Add vehicle terrain restriction check: carts/wagons require roads through desert, mountains, forest, swamp (per `acore_equipment.xml` cart notes). Currently not enforced. |
| `engine/subsystems/characters/creature_equipment_service.gd` | Add `pack_saddle` to saddle validation, add `panniers` to saddlebag-like validation |
| `engine/shared_types/trained_creature_data.gd` | If pack saddle is added: adjust `get_load_multiplier()` to recognize it (1.0× like draft saddle, or a distinct multiplier if design differs) |

**New DB migrations:** None.

**Tests:**

| File | Scope |
|------|-------|
| `tests/test_travel_speed_calculator.gd` | Vehicle terrain restriction tests |
| `tests/test_creature_equipment_service.gd` | Pack saddle and pannier validation |

**Complexity: 2.** Well-patterned work extending existing systems.

---

### Phase C: Nice-to-have, defer if needed

**Goal:** Mount/rider binding, animal training UI, edge cases.

**New code:**

| File | Description |
|------|-------------|
| Schema migration (e.g., `032_mount_rider.sql`) | Add `riding_creature_id TEXT REFERENCES trained_creatures(id) DEFAULT NULL` to `characters` table, tracking who is riding what |
| `scenes/ui/animal_training/animal_training_panel.gd` | UI for teaching tricks, managing trainer hirelings |
| `data/equipment/transport.json` | Add `elephant` entry (requires corresponding monster_catalog entry) |
| `data/monsters/monster_catalog.json` | Add elephant monster entry with carrying capacity special_ability |

**Changes to existing code:**

| File | Change |
|------|--------|
| `engine/shared_types/character_data.gd` | Add `riding_creature_id` field; adjust `get_effective_movement()` to use mount speed when riding |
| `engine/subsystems/characters/encumbrance_calculator.gd` | When character is riding, their carried weight counts against mount's capacity instead of their own movement bands |
| `scenes/ui/party_management/party_management_overlay.gd` | Add creature formation slots (separate from character grid, or interleaved), vehicle placement |
| `cs_tab_creature_stats.gd` | Wire rider display (currently deferred — code comment at line 155 notes "Rider lookup deferred — data model for who is riding whom not yet implemented") |

**New DB migrations:** `032_mount_rider.sql` — `ALTER TABLE characters ADD COLUMN riding_creature_id TEXT REFERENCES trained_creatures(id) DEFAULT NULL`.

**Tests:**

| File | Scope |
|------|-------|
| `tests/test_mount_rider.gd` | Mount/rider binding, movement override, encumbrance transfer |
| `tests/test_animal_training.gd` | Trick teaching, trainer hireling interaction |

**Complexity: 3.** Mount/rider binding touches movement calculation, encumbrance, combat (mounted combat rules), and UI across multiple systems.

---

### Summary Matrix

| Phase | Scope | New files | Modified files | Migrations | Complexity |
|-------|-------|-----------|----------------|------------|------------|
| **A** | Party Inventory overlay + transfers | 3 | 3 | 0 | 3 |
| **B** | Vehicle terrain rules + catalog items | 0 | 4 + transport.json | 0 | 2 |
| **C** | Mount/rider + training + elephant | 4 | 4 | 1 | 3 |
