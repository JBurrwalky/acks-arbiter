# GDD: Inventory Tab

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Inventory tab's content (cross-carrier layout, transfer UX, auto-loot, wilderness-departure prompt, Travel summary widget).
**Status:** Draft v1.6 — pending review
**Depends on:** `gdd-management-notebook.md` v1.2+, `gdd-character-tab.md` v1.2+, `gdd-ui-architecture.md` v2.6+, `gdd-ui-shared-services.md` v1.1+
**Modifiable:** Yes (project-designed)

**Sibling / interfacing documents:**
- `gdd-character-tab.md` §4 — canonical specification of the equipment ↔ inventory data model, strict carrier semantics, currency, death/looting, and carrier-loss rules. This GDD does NOT redefine that model; it references it.
- `gdd-character-tab.md` §5 — canonical specification of item rendering, filter taxonomy, sort taxonomy. This GDD reuses those conventions.
- `gdd-party-inventory.md` — pre-existing GDD; partially current per the audit. **This document supersedes it** as the authoritative Inventory tab spec. The pre-existing GDD becomes a historical layout reference for elements still valid (carrier columns, sub-modals).
- `gdd-party-tab.md` (next document) — Party Status header references inventory aggregates; this GDD defines those aggregates.
- `gdd-management-notebook.md` §6.2 (Party-state question fragmentation resolution) — commits Travel-tab summary widget integration.

**Scope of this document:**
- Cross-carrier layout (multi-column carrier display)
- Carrier column structure (header + inventory list + encumbrance + base movement)
- Cross-carrier transfer UX (drag-drop, modal-assisted, split-stack)
- Auto-loot modal flow (post-combat looting from corpses, dropped items, treasure)
- Wilderness-departure confirmation prompt (per `gdd-character-tab.md` §4.6.1)
- Vehicle / pack-animal carrier handling
- Search across carriers
- Filter and sort within and across carriers
- Migration from existing PartyInventoryOverlay

**Out of scope (moved to other tabs):**
- Travel-planning numerics (party movement speeds, rations, water, fodder, travel-relevant proficiencies) — these moved to the **Party tab's Travel sub-tab** per `gdd-party-tab.md` §6. The Inventory tab is purely about per-carrier item management and encumbrance.

**Out of scope:**
- Per-carrier paper-doll equipment view (lives in Character tab Equipment sub-tab)
- Item rendering and tooltip details (defined in `gdd-character-tab.md` §5)
- Filter / sort dimensions (defined in `gdd-character-tab.md` §5; this GDD references them)
- Carrier-loss random-encounter mechanics (forward-compatibility hook only; future build)
- Mortal Wounds workflow itself (separate system; integration point only)
- Loot cache mechanic (future build)

---

## 1. Purpose and design intent

The Inventory tab is the cross-carrier view of the party's items. Where the Character tab's Equipment sub-tab shows the active character's slot equipment and personal pack, the Inventory tab shows ALL carriers the party controls — every PC, henchman, mercenary officer (and unit), trained animal, and vehicle — with their respective items in side-by-side columns.

**Design intent:**

- **One screen, all carriers visible.** Players manage encumbrance and item allocation by seeing where everything is at once. A scrollable column-grid layout makes "who's carrying what" answerable at a glance.
- **Drag-drop is the primary verb.** Moving items between carriers is the most-frequent operation. Drag-drop must be fast, forgiving, and reversible. Modal-assisted transfer exists for keyboard-only users and edge cases (split stacks, bulk transfers).
- **Strict carrier semantics, never abstracted.** Per `gdd-character-tab.md` §4.1, every item is on exactly one carrier always. The Inventory tab is a *view*, not a *storage* — items have to physically be on a specific carrier. There is no "party stash" abstraction.
- **Decision surfaces live here.** Auto-loot after combat. Wilderness-departure confirmation. Pre-travel encumbrance review. The tab is where the player makes "what comes with us" decisions.
- **Travel summary supports planning.** A dedicated Travel sub-tab surfaces party-level numbers (capacities, speeds, ration days) that inform travel planning without requiring the player to mentally aggregate across columns.

**Non-goals:**

- The Inventory tab does not handle item *acquisition* (buying, looting at point of pickup, treasure rolling). Those happen in their own surfaces (settlement shops, combat-end loot modal, dungeon containers). The Inventory tab is the *post-acquisition* management surface.
- The Inventory tab does not equip items to slots. Equipping is a Character tab Equipment sub-tab operation. Cross-tab activation: dragging an item onto a carrier column representing a character does NOT equip it; it places the item in that character's personal inventory. To equip, the player switches to Character tab.

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §6, the Inventory tab is one of the eight notebook tabs. It is in the primary column ("the band" group) at position 2, between Character and Party.

Invocation:
- Toggle key: I
- Open Notebook button → last-used tab (could be Inventory)
- Cross-tab activation: not currently any external surface that opens directly to Inventory; this could change as features land

The Inventory tab uses the standard notebook page area (vellum) per `gdd-management-notebook.md` §3.2.

---

## 3. Sub-tab structure

The Inventory tab has internal sub-tabs (TabBar at the top of the content area, below the entity strip — wait, no entity strip on this tab; sub-tabs at the top of the content area directly).

### 3.1 Sub-tabs

1. **Carriers** — the cross-carrier column view. Default tab on first activation.
2. **Loot** — appears when auto-loot is pending (post-combat or post-container-open); otherwise hidden.

The Inventory tab no longer has a Travel sub-tab as of v1.5. Travel-planning numerics (party movement speeds, rations, water, fodder, travel-relevant proficiencies) live in the Party tab's Travel sub-tab per `gdd-party-tab.md` §6. The Inventory tab focuses exclusively on per-carrier item management.

The Loot sub-tab is conditional — it appears only when the auto-loot system has pending loot to distribute. When it appears, the loot trigger force-opens the notebook to the Inventory tab on its Loot sub-tab, replacing the previous auto-loot modal flow.

**LootDistributionModal removal is required.** The existing standalone LootDistributionModal must be deleted as part of Phase γ. The Loot sub-tab is the single canonical loot surface. The trigger logic (combat-end, container-opened, MW-confirmed-corpse) remains; only the player-facing surface changes. Build agent must:
- Delete the LootDistributionModal scene and script files
- Remove all callers' direct invocations of the modal
- Replace those invocations with a `notebook_open_requested(Inventory)` signal that opens to the Loot sub-tab when a `loot_pending` event is active
- Verify no other surface still references LootDistributionModal

### 3.2 Sub-tab persistence

Per `gdd-management-notebook.md` §4.1, the Inventory tab's per-tab substate stores the active sub-tab:

```
per_tab_substate[Inventory] = {
  active_subtab: "carriers" | "loot",
  carrier_scroll_position: int,
  filter_state: Dictionary,
  sort_state: String,
  search_text: String
}
```

State persists across notebook open/close and across party switches (per-party state model).

---

## 4. Carriers sub-tab

The default and primary sub-tab. Shows all party carriers in a multi-column horizontal layout.

### 4.1 Layout structure

```
+--------------------------------------------------------------+
| [Search] [Filter ▼] [Sort ▼] [Density ▼]      [Total: 234s]  |  <- header
+----------+----------+----------+----------+----------+--------+
| Aldric   | Brigid   | Caelum   | Skadi    | Bessie   | Cart   |
| (PC)     | (PC)     | (PC)     | (Hench)  | (Animal) | (Vehic)|
| HP/Enc   | HP/Enc   | HP/Enc   | HP/Enc   | Enc      | Enc    |
+----------+----------+----------+----------+----------+--------+
| 🗡 sword | 📜 scrll | ⚒ ham   | 🏹 bow   | 📦 bdrll | 🪙 ches|
| 🛡 shld  | 🪄 wand  | 📿 amul | 📜 mp    | 📦 ratn  | 📦 oil |
| 🪙 12gp | 🪙 28gp  | 🪙 5gp  | 📦 rope  |          |        |
| ...      | ...      | ...      | ...      | ...      | ...    |
| (scroll) | (scroll) | (scroll) | (scroll) | (scroll) | (scroll)|
+----------+----------+----------+----------+----------+--------+
```

The layout is a horizontal `HBoxContainer` of carrier columns, wrapped in a `ScrollContainer` for horizontal scroll when carrier count exceeds visible width. Each column scrolls vertically internally.

### 4.2 Header strip

Top of the content area, fixed:

- **Search field** — free-text matches against item name across all carriers (results highlight in their respective columns)
- **Filter dropdown** — opens filter panel (filters apply globally across all carrier columns; see §6)
- **Sort dropdown** — sort dimension selector (applies to within-column sorting; see §6)
- **Density dropdown** — Compact / Default / Detailed per `gdd-character-tab.md` §5.1.3
- **Total stone indicator** — sum of stone across all carriers (right-aligned). Color-coded by aggregate band — green if every carrier is unencumbered, amber if any heavy, red if any overloaded.

### 4.3 Carrier column

Each column represents one carrier entity. Width: approximately 220px at default density; scales with density mode.

#### 4.3.1 Column header

Top portion, fixed within the column:

- Portrait (PortraitWithBadge component, scaled to ~48×48)
- Name + entity type label below name (e.g., "Aldric" / "PC, Cleric 4" or "Bessie" / "Pack mule")
- HP indicator for character carriers (StatReadout, compact mode) — shows current/max HP or "OK" / "Hurt" / "Bloodied" / "Down" abbreviated
- Encumbrance bar (EncumbranceBar component, horizontal compact)
- Base movement readout — the carrier's unencumbered exploration movement rate in feet per turn (e.g., "120 ft/turn"). This is the base value from which the carrier's encumbered speeds and the party's slowest-member speed are derived. Per-carrier base speed is the canonical quick-reference here; all party-level speed calculations live in the Party tab's Travel sub-tab.
- Wallet (GoldDisplay component) — shows the carrier's coin total

Click on the portrait or name → set global active entity to this carrier AND switch to Character tab. (Cross-tab activation per `gdd-management-notebook.md` §4.4.)

#### 4.3.2 Column body

Scrollable item list below the header:

- One item per row in Default and Detailed density modes
- Grid in Compact density mode (icon-only cells)
- Items rendered per `gdd-character-tab.md` §5.1: icon + name + key stats; tooltip on hover
- Equipped items render with a small "equipped" indicator (icon overlay or border accent) — they cannot be transferred without being unequipped first; transfer attempt prompts "Unequip first?"
- Currency rows render as GoldDisplay items (each carrier's coin entries appear as items in their inventory list)

Items are sorted within the column per the global sort selection (§6.3).

#### 4.3.3 Column footer

Optional small footer at column bottom showing:
- Item count (e.g., "12 items")
- Stone load detail if not visible elsewhere

In compact density, footer may be omitted to save vertical space.

### 4.4 Carrier ordering

Default left-to-right order:
1. PCs (in their party-roster order)
2. Henchmen (in hire-date order)
3. Trained animals (in acquisition-date order)
4. Vehicles (in acquisition-date order)

Within each category, sub-ordering is by date or roster position. This default ordering is fixed in v1.

**Mercenaries are NOT carriers in the Inventory tab.** Per the abstracted mercenary model: mercenaries carry their own gear and provisions independently of the party. They do not consume party rations, do not contribute to party encumbrance, and do not participate in cross-carrier transfers. The party pays a monthly wage and/or upkeep cost; mercenary equipment management is handled at the unit level (in the Troops notebook tab, not here). Mercenaries are independent contractors, not party members for inventory purposes.

Mercenary officers and their units therefore do not appear as carrier columns in the Carriers sub-tab. Their status, advancement, and contract terms live in the Troops tab (covered by `gdd-troops-tab.md` v2.2+).

(Open question O-I1: should the player be able to reorder carrier columns via drag-drop? Default proposal: no in v1; defer to v2.)

### 4.5 Empty carrier

A carrier with zero items still shows its column with a "No items" message in the body. Pack animals and vehicles often start empty; their columns are placeholders waiting for items.

The exception: a carrier whose existence the player has not yet "earned" (no pack mule purchased yet, no cart owned) is NOT shown. Only carriers actually present in the active party appear.

### 4.6 Active-party scope

Per `gdd-management-notebook.md` §3.9, the Inventory tab reflects only the active party's carriers. When the player switches parties via PartySelectorTabs, the carrier set refreshes to the new party's carriers.

In dungeon contexts, only the in-dungeon party's carriers are visible (PartySelectorTabs is disabled per notebook GDD §3.9).

---

## 5. Cross-carrier transfer UX

### 5.1 Drag-drop primary path

Player drags an item from carrier A's column to carrier B's column. On drop:
- If the item is not equipped: transfer attempts immediately.
- If the item is equipped on A: prompt "Unequip and transfer?" with yes/no. On yes, item is unequipped (slot becomes empty) and the transfer attempt proceeds. On no, transfer is cancelled.
- If the destination carrier (B) cannot physically bear the item due to its hard maximum encumbrance limit: **transfer is BLOCKED**. The item remains on A. The UI surfaces an inline error: "[Carrier name] cannot carry this — maximum load exceeded." Players must lighten the destination first (transfer something off, or drop something) before retrying.

#### 5.1.1 Hard-cap encumbrance limits

Per ACKS rules (verify against `acore_basics_and_characters.xml` encumbrance section):

- **Humans / demihumans (PCs, henchmen):** maximum carry is 20 stone, modified by Strength bonus or penalty (e.g., STR 13–15 = +1 stone, STR 16–17 = +2 stone, etc., per ACKS RAW). This is a hard cap — characters physically cannot carry more.
- **Animals:** each animal has a Maximum Load stat from its catalog entry (e.g., a pack mule's maximum load). Hard cap.
- **Vehicles:** each vehicle has a cargo capacity from its catalog entry. Hard cap. Note that an animal hitched to a vehicle changes the operative cap — the animal is now drawing the vehicle, and the vehicle's cargo capacity governs items loaded onto the vehicle (animal still has its own carry limit for any items strapped directly to it via barding/saddlebags).

The hard-cap rule applies to:
- Cross-carrier drag-drop transfers (this section)
- Modal-assisted transfers (§5.5)
- Right-click "Transfer to..." context menu actions (§5.4)
- Item pickups from cell carriers (looting, recovery from cells, picking items off the ground)
- Auto-distribution heuristics in the Loot sub-tab — must respect caps; auto-distribute cannot push any recipient over their cap

The hard-cap is computed by querying the carrier's `max_load_stone` value. The current load (sum of stone weight across all items currently on the carrier) plus the prospective transfer weight must be ≤ max_load_stone for the transfer to succeed.

#### 5.1.2 Soft-cap (encumbrance bands) within the hard-cap

Within the hard-cap (20 stone + STR modifier per `acore_equipment.xml`), characters move through four encumbrance bands defined by stone load. Per the ACKS character movement and encumbrance table (`acore_equipment.xml` §character_movement_and_encumbrance):

- **Unencumbered** — up to 5 stone — full movement (120'/turn exploration, 40'/round combat, 120'/round running)
- **Light** — up to 7 stone — reduced (90'/turn exploration, 30'/round combat, 90'/round running)
- **Medium** — up to 10 stone — further reduced (60'/turn exploration, 20'/round combat, 60'/round running)
- **Heavy** — up to maximum capacity — severely reduced (30'/turn exploration, 10'/round combat, 30'/round running)

Crossing into the Heavy band is permitted (it's within the hard-cap by definition); only crossing past the hard-cap is blocked. Players are warned via UI color-coding when entering the Heavy band but the action proceeds.

This separates two distinct concerns:
- **Encumbrance bands** (movement penalty) — soft consequences per ACKS RAW; player accepts them
- **Hard-cap** (physical impossibility) — hard block; player must rearrange

The previous v1 design conflated these as "warn but don't block"; v1.1 corrects this: Heavy band is a warning, hard-cap is a block. Band names were renamed to Unencumbered / Light / Medium / Heavy in v1.4 to match the ACKS load-threshold structure directly.

### 5.2 Stack splitting on drag

When dragging a stackable item (e.g., 24 arrows), holding `Shift` during drag opens a quantity picker on drop:
- Modal with quantity slider + number input
- Default: half the stack, rounded down (e.g., 24 arrows → default split 12)
- Confirm transfers the chosen quantity; remaining stays on source

Without `Shift`, the entire stack transfers.

### 5.3 Bulk selection

Click an item to select; ctrl-click or shift-click to add to selection. Drag any selected item to transfer all selected. The selection set highlights visually until cleared.

### 5.4 Right-click context menu

Right-click on an item in any carrier column opens a context menu:
- **Transfer to...** — opens carrier picker modal listing all party carriers (with disabled state for incompatible — e.g., can't transfer a magic ring to a wagon as a sensible action; though the system permits any carrier-to-carrier transfer)
- **Equip** — switches to Character tab and equips on active character (or this column's character if applicable)
- **Drop** — removes from carrier; creates an item on the carrier's current floor cell (or destroys it if in wilderness per `gdd-character-tab.md` §4.5.3 / §4.6.1)
- **Split stack** — opens quantity picker; creates two stacks on the same carrier
- **Inspect** — opens detailed item view modal
- **Use** — for consumables (potions, scrolls) — invokes the use action

### 5.5 Modal-assisted transfer

For accessibility (keyboard-only users) or bulk operations, a "Transfer items" button in the header opens a transfer modal:
- Source carrier dropdown
- Destination carrier dropdown
- Multi-select item list filtered to source's contents
- Quantity inputs for stackable items
- Confirm executes all transfers atomically

### 5.6 Equipped-item transfer

Per §5.1, transferring an equipped item prompts to unequip. The unequip + transfer is logically two operations but executes atomically — either both succeed or both fail. Failure cases are rare (database errors, pre-condition checks).

### 5.7 Henchman gift behavior (one-way coin transfers)

**Coins transferred TO a henchman become permanent gifts.** Henchmen do not return coins to the party. Once given, coins are theirs to keep.

**Non-coin items transferred TO a henchman are loaned, NOT gifted.** Equipment, weapons, armor, consumables, magic items, and other gear given to a henchman remain party-owned and can be reclaimed. Henchmen serve as carriers for loaned gear (which is useful for offloading encumbrance from PCs, equipping a henchman fighter with party-owned weapons, etc.) but do not own the items.

**Rationale:** Henchmen are loyal-but-independent NPCs, not free pack mules — but they ARE willing carriers and combatants for the party's cause. The split between coins (gifted) and items (loaned) reflects ACKS's social model: coins are personal payment; gear is logistical. A henchman receives wages (in coin) plus optional bonus payments (in coin) and is issued equipment to do their job (which the party retains rights to).

**UX implications for coin transfers:**
- When a player drags coins onto a henchman's carrier column, a confirmation prompt surfaces: "Give coins to [henchman name]? Once given, they cannot be taken back. Bonus payments may improve loyalty over time."
- The player confirms to complete the transfer. The transfer is logged with `world` category and severity `info`, with metadata noting "bonus payment" semantics.
- Drag-drop attempts to transfer coins FROM a henchman's column to another carrier are BLOCKED. The UI surfaces an inline message: "Cannot reclaim coins given to a henchman."
- Right-click context menu on a henchman's coin entries shows only Inspect; Transfer to..., Drop, etc. are unavailable.

**UX implications for non-coin items:**
- Drag-drop transfers TO and FROM a henchman work normally per the standard rules in §5.1 through §5.6.
- No gift confirmation prompt; this is routine equipment management.
- Players can reclaim issued items at any time via standard transfer flow.
- An issued-but-not-equipped item shows in the henchman's inventory list normally; an equipped item shows with the equipped indicator and prompts to unequip on transfer per §5.6.

**Future build:** Coin gifts to humanoid henchmen contribute to henchman loyalty and morale. Bonus payments may improve loyalty over time; insufficient bonus payments after major loot events may reduce loyalty. The current GDD only specifies the inventory behavior; the loyalty hooks are a future-build concern (deferred to `gdd-henchmen-tab.md`).

#### 5.7.1 Animal henchmen

Animal henchmen (war dogs, war horses, riding wolves, etc. serving as henchmen rather than mounts/pack animals) function as normal carriers for both coins and items. Animals do not have personal agency over coins or possessions in the way humanoids do — anything they carry (including any coins, though that's an unusual case) is genuinely the player's gear that the animal happens to be carrying. All transfers in and out of an animal henchman's column work normally per §5.1 through §5.6. The "gift becomes permanent" coin rule does NOT apply to animal henchmen.

The distinction is governed by the henchman entity's species/type — humanoid (human/demihuman) henchman = coin-gift behavior applies; animal henchman = normal transfer behavior for everything. The build agent must consult the henchman entity's type when constructing carrier column UI behaviors.

---

## 6. Filter, sort, search, density

Per `gdd-character-tab.md` §5, the Inventory tab uses the same filter / sort / density taxonomies as the Character tab's personal inventory list.

### 6.1 Filter scope

Filters apply globally — when active, they hide non-matching items in EVERY carrier column. A "Type: weapons" filter shows only weapons across all columns; carriers with no weapons show empty columns.

The Equippable-by-active-character filter behaves slightly differently in the Inventory tab since there's no single "active character" the way there is on the Character tab. Two interpretations:

- **By active entity (cross-tab):** uses whichever entity is the global active entity (set by Character tab). Shows items equippable by THAT character.
- **Per-column:** each column filters independently based on its own carrier.

Default proposal: by global active entity. The filter is meaningful when the player is asking "what does my fighter need?" — they set active entity to the fighter, switch to Inventory tab, enable Equippable filter, and see only items the fighter could equip across all carriers.

### 6.2 Filter UI

Same UI as Character tab Equipment sub-tab (per `gdd-character-tab.md` §5.2.2): collapsible header above the carrier columns with type/subtype dropdowns, equippable/magical/in-slot toggles, and a clear-filters button.

### 6.3 Sort within columns

Sort applies within each column independently. The selected sort dimension (Alpha / Weight / Value / Date / Type-then-alpha — per `gdd-character-tab.md` §5.3) governs each column's internal ordering. Default sort is Type-then-alpha.

### 6.4 Search across columns

Search field in the header. Free-text substring match (case-insensitive) against item name. Matching items are highlighted (border accent or background tint via Theme variant — `search_match` to be declared in `gdd-ui-shared-services.md` §4.3); non-matching items remain visible but de-emphasized.

Pressing Enter in the search field jumps to the first match (auto-scrolls the column horizontally if needed).

### 6.5 Density modes

Three modes (Compact / Default / Detailed), per `gdd-character-tab.md` §5.1.3. Density preference persists per-session and per-tab (Inventory tab and Character tab Equipment sub-tab maintain independent preferences).

---

## 7. Travel content — moved to Party tab

**As of v1.5, the Inventory tab does NOT have a Travel sub-tab.** All travel-planning numerics — party movement speeds, rations, water, fodder, travel-relevant proficiencies, Forage / Hunt actions — live in the **Party tab's Travel sub-tab** per `gdd-party-tab.md` §6.

Rationale: travel planning is a party-level concern (how fast can WE move, when does OUR food run out), not an inventory-management concern (where is THIS item, who is carrying it). Folding the travel widget into the Inventory tab created friction with the rest of the inventory experience and duplicated information that more naturally belongs alongside party composition and formation. The Inventory tab is now exclusively about per-carrier item management.

The previously-spec'd content from this section (party composition counts, carrying capacity table, movement speeds breakdown, rations / fodder tracking, travel proficiencies and effects, Open Inventory button) was migrated into the Party tab GDD's Travel sub-tab. The headline `daily / total / days` rations and water format was added there; all per-carrier capacity information remains visible in the Carriers sub-tab here via the per-column encumbrance bar and base-movement readout (see §4.3.1).

Migration callout for the build agent: when implementing Phase γ, do NOT build a Travel sub-tab in the Inventory tab. Build the Travel sub-tab in the Party tab per `gdd-party-tab.md` §6, and ensure the Inventory tab's sub-tab structure matches §3.1 (Carriers + conditional Loot only).

---

## 8. Loot sub-tab (auto-loot flow)

### 8.1 When the Loot sub-tab appears

Per `gdd-character-tab.md` §4.5 (death/looting flow) and per the audit (LootDistributionModal exists for combat-end / container-opened triggers):

The Loot sub-tab is conditionally visible. It appears when:
- Combat ends with confirmed-dead-corpse loot per Mortal Wounds resolution (§4.5.2)
- A container is opened in the world (chest, sarcophagus, body of a fallen enemy with confirmed loot)
- A treasure pile is generated by the encounter system

In all cases, the underlying mechanism is: a `loot_pending(loot_id)` event fires; the Inventory tab shows the Loot sub-tab and (if the notebook is currently closed) also surfaces a notification toast inviting the player to open it.

The Loot sub-tab is hidden when no loot is pending.

### 8.2 Loot session model

A "loot session" is a discrete event — a single combat's aftermath, a single container, a single treasure cache. Multiple loot sessions can stack: if the player ignores one and another fires, both are pending. The Loot sub-tab shows them as a list of sessions; the player resolves each.

### 8.3 Layout

Two-region layout per loot session:

- **Top:** session header — what was looted from (e.g., "Goblin Scout's body", "Wooden Chest", "Aldric's remains"). Optional brief flavor text from the LLM narration system.
- **Middle:** the loot items as a list (icon rows per `gdd-character-tab.md` §5.1).
- **Bottom:** distribution controls.

### 8.4 Distribution controls

For each item in the loot list:
- "Take" button → opens carrier picker (which party member should receive it)
- "Leave" button → item remains where it was (corpse, container, or wilderness ground per location rules)
- "Inspect" button → opens detailed item view (for unidentified items, this still shows unidentified-form name per O-C9)

Bulk controls at the bottom:
- "Take all" → opens carrier picker; assigns all items to chosen carrier (warns if encumbrance exceeded)
- "Distribute equitably" → auto-assigns to party members balancing encumbrance (heuristic; player can adjust afterward)
- "Leave all" → all items remain at source; loot session resolves; sub-tab moves on

### 8.5 Coin handling in loot

Coins in loot follow strict carrier semantics — they're items with a quantity. Auto-distribution heuristic for coins: split equally among PCs only by default. Henchmen are NOT default recipients of loot coins.

Henchmen receive their share of party earnings through the wage payment system (separate flow, paid on return to a settlement plus monthly wage ticks). Loot coins distributed at the moment of looting go to PCs; the wage system reconciles on the back end.

Players can override the default distribution to manually transfer coins to a specific henchman. **Coins (and ONLY coins) transferred to a henchman become a permanent gift / bonus payment.** See §5.7 for the bonus-payment behavior.

Non-coin loot items (weapons, armor, gear, magic items, consumables) distributed via the Loot sub-tab to a henchman recipient are issued equipment, not gifts. The party retains ownership; items can be reclaimed via standard transfer flow at any time. Players issuing non-coin loot to henchmen for tactical purposes (e.g., giving a henchman fighter a magic sword to use during the next battle) is normal and expected behavior.

### 8.6 Resolution

A loot session is resolved when all items are either taken or explicitly left. Once resolved, the session disappears from the Loot sub-tab. If no more sessions remain, the Loot sub-tab hides itself; the next time the Inventory tab is opened, it defaults to Carriers.

### 8.7 Skipped loot

If the player chooses "Leave all" on a wilderness loot session, the items are immediately destroyed (per wilderness rules in `gdd-character-tab.md` §4.6.1).

If the player chooses "Leave all" in a dungeon, the items remain on the floor cell carrier and are recoverable on return.

### 8.8 Mortal Wounds integration

When the source of loot is a party-member's confirmed-dead-corpse (per `gdd-character-tab.md` §4.5.2), the loot session is sourced from the corpse carrier. The session header includes the dead character's name, and the LLM narration may provide a brief eulogistic flavor entry.

If the source was death-with-no-corpse in a dungeon, the items are on the floor cell carrier; the loot session is sourced from that cell. In wilderness, no loot session triggers — items are simply destroyed per §4.6.1 (the wilderness-departure prompt §9 provides the player one final chance to recover).

---

## 9. Wilderness-departure confirmation

### 9.1 When it triggers

Per `gdd-character-tab.md` §4.6.1: when a party attempts to leave a wilderness hex, the system enumerates all items on floor-cell carriers within that hex (excluding loot caches when that mechanic lands). If any uncached items exist, a confirmation modal surfaces.

This modal is NOT a sub-tab of the Inventory tab — it's a separate confirmation dialog that pops up at the moment of attempted hex departure (probably triggered by the wilderness map controller, not the notebook). Listed here because it interacts with the inventory data model and because the player may use the modal to navigate to the Inventory tab to recover items.

### 9.2 Layout

A modal dialog:

- Header: "Items will be lost"
- Body: list of items currently on uncached floor cells in this hex, grouped by cell location
- Buttons:
  - "Leave anyway" — confirms departure; items destroyed
  - "Cancel" — abort departure; party stays in hex
  - "Open inventory to recover" — abort departure AND open notebook to Inventory > Carriers, with a hint pointing at the cell carriers (when cell carriers are visible — see §9.3)

### 9.3 Cell carriers in the Inventory tab

Cell carriers (floor cells holding items) are NOT auto-visible in the Carriers sub-tab. The Carriers sub-tab default scope is the party's controlled carriers (PCs, henchmen, animals, vehicles); floor-cell content is a separate concept and surfaces only when the player has explicitly engaged with it.

#### 9.3.1 Dungeon contexts

Dungeon floor-cell items remain hidden from the Inventory tab. Loot in dungeons surfaces through:
- A **Loot action command** in the dungeon UI when the party is adjacent to or on a cell containing items. The Loot action opens the auto-loot flow (Loot sub-tab) for that specific cell.
- The Loot sub-tab when triggered by combat-end on a cell that received dropped items.
- The auto-loot trigger when a container is opened.

The Carriers sub-tab in dungeon contexts shows only party carriers. Floor-cell items are reachable via deliberate Loot interaction in the world, not via passive inventory browsing.

#### 9.3.2 Wilderness contexts

In wilderness, the same principle applies — the Carriers sub-tab does not auto-show cell carriers. The auto-loot Loot sub-tab is the canonical surface for cell content (post-combat loot, dropped items, etc.).

The wilderness-departure modal (§9.1) surfaces cell content only at the moment of departure attempt, listing what will be lost if the party leaves. From that modal, the player can cancel and return to the world to deliberately Loot the cells (which routes through the Loot sub-tab).

In other words: the Inventory tab does NOT show "uncollected items on the ground" anywhere. That information lives in:
- The world (3D voxel scene) — items are visible on cells
- The Loot sub-tab — when auto-loot fires for a specific source
- The wilderness-departure modal — when departure is being attempted with items still on cells

This keeps the Carriers sub-tab focused on what the party is *carrying*, not what's *near them*. Surfacing every nearby item in the inventory grid would be both cluttered and confusing.

#### 9.3.3 Recovery flow

When a player wants to recover a specific item from a floor cell (e.g., picked up a coin during exploration that ended up on a cell carrier rather than a character), the path is:
1. In the world, navigate the party to the cell
2. Invoke Loot action on the cell
3. Loot sub-tab surfaces with the cell's content as the loot source
4. Player takes items, distributes to carriers
5. Sub-tab resolves; cell carrier becomes empty

This is the standard interaction; the Inventory tab does not provide an alternate path.

---

## 10. Vehicles and pack animals as carriers

Vehicles and pack animals are first-class carriers per `gdd-character-tab.md` §4.1. They appear in the carrier grid alongside characters, with the following adaptations:

### 10.1 Header differences

- No HP indicator (animals have HP, but the carrier-column header focuses on travel-relevant info; HP shown only for character carriers)
- For animals: a "loyalty" indicator if the animal type tracks loyalty
- For vehicles: an SHP indicator (Structural Hit Points — current / max). SHP is the ACKS / Domains at War construct for vehicle, vessel, and siege-equipment structural integrity; it functions differently from creature HP (damage sources, scaling, and repair rules differ per `daw_equipment_and_construction.xml` and related Domains at War rules).
- Wallet still shown (animals and vehicles can carry coin items just like characters)

### 10.2 Body differences

The item list works identically. Vehicles often have larger item counts and may benefit from the Compact density mode by default. (Open question O-I4: should density default differ per carrier-type? Per-column density override is appealing but adds UI complexity. Default proposal: global density only in v1; per-column override is v2 enhancement.)

### 10.3 Trained-animal equipment

Trained animals have a small slot set per `gdd-character-tab.md` §3.4 (barding, saddle if applicable). The Character tab is where these are equipped. The Inventory tab shows barding in the trained animal's column as an "equipped" item, drag-droppable like any equipped item (with the unequip-first prompt).

### 10.4 Vehicles cannot equip

Vehicles have no equipment slots (the audit confirms this; Character tab Vehicle Detail sub-tab handles vehicle stats, not slot equipment). Items on vehicles are pure cargo — never "equipped". The "equipped" indicator never appears on vehicle column items.

---

## 11. Migration from existing PartyInventoryOverlay

Per the audit, the existing PartyInventoryOverlay implements much of `gdd-party-inventory.md` already. Migration work for Phase γ:

### 11.1 Scene migration

- The existing PartyInventoryOverlay scene becomes the basis for the Inventory tab's content scene
- Surface category changes from "side overlay" to "notebook tab content"
- Modal dialogs (CharacterPreferencesModal, GoldShareModal, etc.) keep their modal status; they continue to function from within the Inventory tab as they did from the overlay
- The standalone overlay is deleted; only the migrated tab content remains

### 11.2 Travel-tab summary widget

Per audit: the original Travel-tab summary widget (Humans/Animals/Vehicles count, per-vehicle capacity rows, Open Inventory button) is missing. This GDD's §7 specifies it; build agent adds it during migration.

### 11.3 Loot integration

The existing LootDistributionModal (per audit) was triggered by combat-end with loot OR container-opened. Its content distributes loot but is currently a standalone modal. Migration: the underlying logic remains, but the player-facing surface becomes the Loot sub-tab. The modal itself may persist for cases where the notebook isn't open and a quick distribution is needed; design TBD during implementation.

(Open question O-I5: should LootDistributionModal still exist as a quick-prompt option, OR should all loot flow through the Loot sub-tab? Default proposal: Loot sub-tab is the canonical surface; LootDistributionModal is removed; players who want quick loot distribution use the toast notification's "Take all" action. Simpler = better.)

### 11.4 Wilderness-departure modal

New surface; not currently in the project. Build during Phase γ.

### 11.5 Cell-carrier visibility

New behavior; not currently in the project. The existing PartyInventoryOverlay does not show floor-cell carriers in its column grid. Build during Phase γ.

---

## 12. Performance considerations

- Carrier column rendering: typically ≤10 carriers; trivial node count
- Item list per column: typically <50 items per character carrier, up to ~200 on vehicles
- Across-carrier filter / search: O(N) where N is total item count across all columns; typically <1000 items per party; sub-millisecond
- Drag-drop hit-testing: standard Godot Control behavior; no performance concern
- Density mode switching: re-renders each column; may briefly hitch on column count > 8 with vehicles full of items; acceptable

The Inventory tab as a whole should open in <100ms on first activation per session and <16ms on subsequent activations (cached scene tree per `gdd-management-notebook.md` §2.3.2).

---

## 13. Open questions

- **O-I1.** Should the player be able to reorder carrier columns via drag-drop on the column header? Default proposal: no in v1; defer to v2.
- **O-I2.** ~~Encumbrance overload on transfer: block or warn?~~ **Resolved (v1.1, band names updated v1.4):** Hard cap is BLOCKED (per ACKS RAW: humans/demihumans 20 stone ± STR mod, animals per Maximum Load stat, vehicles per cargo capacity). Encumbrance bands within the hard-cap (Unencumbered → Light → Medium → Heavy) are warnings only; the action proceeds. Per §5.1.1.
- **O-I3.** ~~Cell carriers in the Carriers sub-tab.~~ **Resolved (v1.1):** Cell carriers are NOT auto-shown in the Carriers sub-tab in any context. Floor-cell content surfaces only through the Loot sub-tab (when an auto-loot trigger fires) or through the wilderness-departure modal (at the moment of departure attempt). The Carriers sub-tab remains focused on what the party is carrying. Recovery of items from cells routes through the Loot action command in the world. Per §9.3.
- **O-I4.** Density default per carrier type (Compact for vehicles, Default for characters)? Default proposal: global density only in v1; per-column override is v2 enhancement.
- **O-I5.** ~~Retain LootDistributionModal as a quick-prompt option, or remove in favor of Loot sub-tab?~~ **Resolved (v1.1):** Remove. The Loot sub-tab is the canonical loot surface. LootDistributionModal scene and script files are deleted in Phase γ. All callers are migrated to the new flow. Per §3.1 and §11.3.
- **O-I6.** "Distribute equitably" auto-assignment heuristic for bulk loot — how is "equitably" defined? Default proposal: minimize maximum encumbrance band across PC recipients; secondary: round-robin among PCs (henchmen are excluded from default auto-distribution per O-I7). Auto-distribute must respect hard-cap encumbrance limits (§5.1.1).
- **O-I7.** ~~Coin distribution heuristic in loot.~~ **Resolved (v1.1, refined v1.2):** Equally among PCs by default. Henchmen are NOT default recipients; they receive their share through the wage payment system. Coins manually transferred to humanoid henchmen become permanent gifts (bonus payments) per §5.7. Non-coin items transferred to henchmen are loaned equipment and remain party-owned. Animal henchmen exempt from coin-gift rule (no agency over coins). Per §8.5 and §5.7.
- **O-I8.** ~~When transferring an equipped item, the prompt is "Unequip and transfer?"~~ **Resolved (v1.1):** Prompt confirmed. Equipped items are often equipped intentionally; silent unequip would be surprising.

---

## 14. Build sequencing

Per `gdd-management-notebook.md` §14.2, the Inventory tab is part of Phase γ alongside the Character tab and Party tab. Phase γ depends on Phase α (Theme.tres, UiInputController, shared components) and Phase β (notebook scaffolding).

### 14.1 Phase γ scope for Inventory tab

1. Build the Inventory tab content scene (`scenes/ui/notebook/inventory_tab.tscn`).
2. Migrate PartyInventoryOverlay's carrier column logic into the Carriers sub-tab; add base-movement readout to the column header per §4.3.1.
3. Build the Loot sub-tab and integrate with existing loot triggers (combat end, container open). Decide on LootDistributionModal retention or removal per O-I5.
4. Build the wilderness-departure confirmation modal (separate from the Inventory tab; lives in the wilderness map controller's flow; cross-references the Inventory tab for navigation).
5. Add cell-carrier visibility per §9.3.
6. Wire global active-entity changes to refresh the Equippable filter when applicable.
7. Wire UiInputController for the I keybind.
8. Verify auto-loot flow integrates with Mortal Wounds resolution per `gdd-character-tab.md` §4.5.
9. Coordinate with the Party tab build (`gdd-party-tab.md` §14.1) to ensure Travel content lands there, not here. The previously-planned Travel sub-tab in the Inventory tab is removed.

### 14.2 Dependencies on other GDDs

- `gdd-character-tab.md` §4 — canonical data model; this GDD references not redefines.
- `gdd-character-tab.md` §5 — item rendering, filter, sort taxonomies.
- `gdd-ui-shared-services.md` — Theme variants, EventBus signals, shared components.
- The future Mortal Wounds workflow GDD — auto-loot integration contract.
- The future stronghold / downtime UI GDD — Loot sub-tab handling for downtime treasure rolls (if those produce loot through the same mechanism).

---

## 15. Revision history

- **v1.6, 2026-04-30** — Mercenaries → Troops cleanup pass. §4.4 carrier-ordering note retargeted: "the Mercenaries notebook tab" → "the Troops notebook tab"; the deferred GDD pointer (`gdd-mercenaries-tab.md` when authored) replaced with the now-authored `gdd-troops-tab.md` v2.2+. The §4.4 substantive rule that mercenaries are not Inventory-tab carriers (independent-contractor abstraction) is unchanged.
- **v1.5, 2026-04-29** — Travel sub-tab removed from the Inventory tab. Travel-planning numerics (party movement speeds, rations, water, fodder, travel-relevant proficiencies, Forage / Hunt actions) moved to the Party tab's Travel sub-tab per `gdd-party-tab.md` §6. Rationale: travel planning is a party-level concern, not an inventory-management concern. §3.1 sub-tab list reduced to Carriers + conditional Loot. §3.2 sub-tab persistence updated. §4.3.1 column header gains a base-movement readout (the carrier's unencumbered exploration movement rate per `acore_basics_and_characters.xml`) so per-carrier movement context is visible without requiring tab-switching. §7 replaced with a redirect note explaining the migration. §14.1 build sequencing updated to remove Travel sub-tab construction; coordination point with Party tab build added.
- **v1.4, 2026-04-29** — ACKS rules audit corrections. §5.1.2 encumbrance bands renamed Unencumbered / Light / Medium / Heavy and tied directly to the ACKS character movement and encumbrance table thresholds (5 / 7 / 10 / max stone) and movement rates per `acore_equipment.xml` §character_movement_and_encumbrance. O-I2 disposition updated to reference the new band names.
- **v1.3, 2026-04-27** — §10.1 corrected to use Structural Hit Points (SHP) for vehicle durability, not HP. SHP is a distinct ACKS / Domains at War construct with different damage source rules, scaling, and repair semantics from creature HP.
- **v1.2, 2026-04-27** — §5.7 refined: only COINS transferred to humanoid henchmen become permanent gifts. Non-coin items (equipment, weapons, armor, magic items, consumables) are loaned and remain party-owned; transfers in and out of henchmen for non-coin items work normally. Section title updated from "one-way transfers" to "one-way coin transfers." §8.5 loot coin distribution updated to reflect coin-only gift rule. O-I7 disposition refined.
- **v1.1, 2026-04-27** — Major refinements per design clarifications. §3.1 explicitly requires LootDistributionModal removal during Phase γ migration. §4.4 carrier ordering removes mercenaries; mercenaries are abstracted contractors and do NOT carry party inventory. §5.1 hard-cap encumbrance: ACKS RAW maximums (20 stone ± STR mod for humans/demihumans, animal Maximum Load stat, vehicle cargo capacity) are HARD-BLOCKED on transfer. Encumbrance bands within the cap are warnings. New §5.7 documents henchman gift behavior. §9.3 clarified: cell carriers never auto-show in Carriers sub-tab. §8.5 coin distribution updated. O-I2, O-I3, O-I5, O-I7, O-I8 resolved.
- **v1, 2026-04-27** — Initial draft.
