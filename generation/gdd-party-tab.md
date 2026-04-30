# GDD: Party Tab

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Party tab's content (Party Status header, Composition / Travel / Formation sub-tabs, cross-tab interactions).
**Status:** Draft v1.4 — pending review
**Depends on:** `gdd-management-notebook.md` v1.3+, `gdd-ui-architecture.md` v2.7+, `gdd-ui-shared-services.md` v1.2+, `gdd-character-tab.md` v1.5+, `gdd-inventory-tab.md` v1.4+
**Modifiable:** Yes (project-designed)

**Sibling / interfacing documents:**
- `gdd-management-notebook.md` §3.4 — establishes the Party tab as one of the eight notebook tabs (primary column, position 3).
- `gdd-ui-architecture.md` §6.2 — commits the Party Status header concept and the resolution of party-state-question fragmentation.
- `gdd-character-tab.md` — single-entity views; Party tab cross-activates into Character tab via `notebook_active_entity_requested`.
- `gdd-inventory-tab.md` — owns per-carrier inventory display (encumbrance, item lists, transfers, auto-loot, wilderness-departure prompt). The Party tab owns travel-planning numerics (movement, rations, water) per Phase γ scoping.
- `gdd-henchmen-tab.md` (future) — full henchman lifecycle. Party tab cross-references for hire / dismiss flows.
- `gdd-troops-tab.md` v2.2+ — unit-scale troop roster covering all six army sources per `daw_armies_recruitment.xml` §army_sources (mercenaries, conscripts, militias, followers, slave soldiers, vassal troops). Party tab cross-references for unit management.
- `acore_adventures_and_encounters.xml` §marching_and_mapping — sacred rules for marching order.
- `acore_adventures_and_encounters.xml` §rations_and_foraging — sacred rules for daily consumption (1 stone food + 1 gallon water per character per day) and starvation/dehydration damage models.
- `acore_basics_and_characters.xml` — sacred rules for ability modifiers, reaction rolls, and Wisdom-modifies-all-saves.

**Scope of this document:**
- Party Status header — content, layout, behavior across sub-tabs
- Composition sub-tab — roster table, party-wide summaries, hire / dismiss controls (cross-tab activation)
- Travel sub-tab — movement speeds, rations and water tracking with the `7/210 (30)` headline format, travel proficiencies and effects
- Formation sub-tab — combined exploration marching order and combat starting positions, expressed as two grids (Wilderness 6×12, Dungeon 2×12) with entity-eligibility filtering
- Cross-tab activation rules
- Multi-party scope handling (per `gdd-ui-architecture.md` §3.9)
- Empty-state behavior
- Migration from existing PartyManagementOverlay

**Out of scope:**
- Per-entity character sheet content (Character tab GDD)
- Per-carrier inventory column display, transfers, auto-loot, wilderness departure (Inventory tab GDD)
- Henchman / mercenary lifecycle (their respective tab GDDs)
- Camp / watch / light source mechanics (future Camp surface GDD)
- Combat tactical execution (combat UI GDD); the Formation sub-tab establishes the *deployment template* the combat controller consumes — combat itself is owned elsewhere
- Per-tab notebook scaffolding (Management Notebook GDD)

---

## 1. Purpose and design intent

The Party tab is the canonical surface for "managing the group." Where the Character tab answers "what about this one entity," the Party tab answers "what about us collectively" — composition, travel logistics, and the deployment template for both exploration and combat.

**Design intent:**

- **Group-scope, not entity-scope.** Every Party tab view is about the party as a whole. Per-entity drilldown is one click away (cross-activate to Character tab) but is not the Party tab's primary purpose.
- **Always-visible Party Status.** The header at the top of the Party tab summarizes the active party in a fixed, scannable format. It persists across sub-tabs so that when the player is reordering formation or auditing rations, they always have aggregate composition / encumbrance / location / speed visible.
- **One canonical surface for "who is in the party."** The audit identified party-state-question fragmentation. The Party tab resolves this: a single screen the player can land on and immediately see the full group state.
- **Travel logistics live here, not in inventory.** Rations, water, party speed, terrain modifiers, and travel-relevant proficiencies are *party-level* concerns, not inventory-management concerns. The Inventory tab handles per-carrier item lists and encumbrance; the Party tab handles "can we make it to the next settlement before we starve."
- **Formation is the unified marching-order / combat-deployment surface.** Per project decision, the exploration marching order and the combat-starting-position formation are the same construct. The Formation sub-tab exposes two grids (Wilderness, Dungeon) that capture the party's deployment template in each context. The combat controller consumes the relevant grid when an encounter initializes; the exploration system consumes it for trap exposure, surprise resolution, and front-rank assignments.

**Non-goals:**
- The Party tab is not a hiring storefront. Hire flows belong to the Settlement Panel's HiringPanel and (for henchmen specifically) the future Henchmen tab. The Party tab cross-references those surfaces.
- The Party tab is not a per-carrier inventory editor. The Inventory tab handles items on specific carriers. The Party tab surfaces only aggregate ration / water counts at the party level.
- The Party tab does not handle camp or watch shifts in v1. Those mechanics belong to a future Camp surface GDD; if watch ordering needs UI before that GDD lands, it can be added as a §6 sub-section here in a future revision (see O-P2).

### 1.1 Party-membership model (LLC analogy)

Different categories of party assets have categorically different semantics. The Party tab's UI must reflect this without over-burdening the player with taxonomy. Per project design:

| Category | Examples | Semantics |
|----------|----------|-----------|
| **Members** | PCs | Full agency; the LLC's members. Cannot be dismissed. Receive XP, level up, vote with their feet. |
| **Employees** | Humanoid (human / demi-human) henchmen | Loyal full-time staff. Earn wages, may be reclaimed-and-reissued equipment, advance with XP, can be dismissed alive or promoted to Member (per `gdd-management-notebook.md` §6.5). |
| **Property** | Animal henchmen (war dogs, warhorses serving as henchmen), trained animals, vehicles | LLC-owned assets. No agency. Carry items, occupy positions in formation, take damage. |
| **Contractors** | Mercenaries (units, identified by their officer), other independent specialists | Independent contractors. Carry their own gear and provisions, do not haul party baggage, and do not enter dungeons. Listed in the Party tab and identified by the officer for navigation, but the officer is structurally still a mercenary. |

This model is descriptive of how each category interacts with party systems (inventory, formation, dungeon eligibility, dismissal, advancement). UI surfaces use the player-facing labels (PCs / Henchmen / Animals / Vehicles / Mercenary Units) rather than the LLC labels, but the underlying semantics drive eligibility logic in §7 (Formation) and §5 (Composition).

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §3.4, the Party tab is tab #3 in the primary column ("the band"), positioned between Inventory (#2) and Henchmen (#4).

Invocation:
- Toggle key: **P**
- Cross-tab activation:
  - EncounterScreen "view party" link → opens Party tab (per `gdd-management-notebook.md` §8.4)
  - SessionStatusBar Open Notebook button → last-used tab (could be Party)
  - Notification "low rations" / "henchman loyalty critical" / similar party-state alerts → may target Party tab on action click (per future notification system; not in v1)

The Party tab uses the standard notebook page area (vellum) per `gdd-management-notebook.md` §3.2.

---

## 3. Sub-tab structure

The Party tab has internal sub-tabs (TabBar at the top of the content area, below the Party Status header).

### 3.1 Sub-tabs

1. **Composition** (default on first activation) — roster table + party-wide summaries
2. **Travel** — movement speeds, rations / water / fodder tracking, travel-relevant proficiencies and effects
3. **Formation** — exploration marching order and combat starting positions, expressed as two grids (Wilderness 6×12 and Dungeon 2×12)

### 3.2 Sub-tab persistence

Per `gdd-management-notebook.md` §4.1, the Party tab's per-tab substate stores:

```
per_tab_substate[Party] = {
  active_subtab: "composition" | "travel" | "formation",
  composition_sort: String,
  composition_filter: Dictionary,
  formation_active_grid: "wilderness" | "dungeon"
}
```

State persists across notebook open/close and across party switches (per-party state model).

---

## 4. Party Status header

The Party Status header is fixed at the top of the page area, **visible across all Party tab sub-tabs**. It is the architectural commitment from `gdd-ui-architecture.md` §6.2.

### 4.1 Layout

```
+---------------------------------------------------------------------+
| [Party name]                            [Open Inventory] [Camp]     |
| 4 PCs · 2 Henchmen · 3 Animals · 1 Vehicle · 1 Mercenary Unit       |
| Encumbrance: Light (slowest: Bessie, Medium)  |  Total gold: 482 gp |
| Location: Hex 12,7 (Westmark Hills, Borderlands)  |  60'/turn       |
+---------------------------------------------------------------------+
```

Three rows of summary content plus a top action row:

**Action row (top):** Party name (left, editable inline if user clicks); Open Inventory button (jumps to Inventory tab); Camp button (fires `EventBus.camp_requested`, opens camp flow).

**Row 1 — Composition counts:** Per-category breakdown using player-facing labels:
- **PCs** — count of player characters (Members)
- **Henchmen** — count of all henchmen (Employees + Property-class animal henchmen aggregated for header brevity; the Composition sub-tab breaks them apart)
- **Animals** — count of trained animals not serving as henchmen
- **Vehicles** — count of carts / wagons / ships / etc.
- **Mercenary Units** — count of contracted mercenary units (each represented by its officer; the unit's rank-and-file are NOT counted as individual members)

Each label is clickable: click jumps the Composition sub-tab to that category filter and switches to the Composition sub-tab if not already there.

**Row 2 — Aggregate encumbrance and gold:**
- Encumbrance band — the **slowest member's** encumbrance band (per ACKS, party speed = slowest-member speed). Display the band name (Unencumbered / Light / Medium / Heavy per `gdd-character-tab.md` §3.4.8) with a color cue from `UiPalette.encumbrance_color_for_band`. Append the slowest member's name in parentheses so the player knows who's holding them up.
- Total gold — Party Wallet aggregate (sum of all PC + owned-animal + vehicle wallets per `gdd-character-tab.md` §4.8). Rendered via the GoldDisplay shared component. Henchman / mercenary personal coin is excluded (humanoid henchman coin is a permanent gift per `gdd-inventory-tab.md` §5.7; mercenaries are independent contractors).

**Row 3 — Location and speed:**
- Current location — derived from the party's hex / settlement / dungeon context (e.g., "Hex 12,7 (Westmark Hills, Borderlands)" in wilderness; "Settlement: Aerendel Crossing" in town; "Dungeon: The Sunken Vault, Level 2" in dungeon)
- Party speed — exploration speed in the current context (e.g., 60'/turn in dungeon, 24 miles/day in wilderness on a road). Derived from slowest-member encumbered movement rate. Tooltip: full breakdown by terrain class (the headline number; the Travel sub-tab has the full breakdown).

### 4.2 Behavior across sub-tabs

The header does not change based on which sub-tab is active. It is a fixed band at the top of the page area, with the sub-tab strip immediately below.

When `EventBus.encumbrance_changed`, `wallet_changed`, `rations_changed`, `location_changed`, or `active_party_changed` fires, the header refreshes from the new state.

### 4.3 Edge cases

- **Empty party (defensive case):** If the active party has zero members, the header shows the party name plus "No members" and the rest of the rows render with placeholder dashes. The Composition sub-tab renders the empty-state page (see §10).
- **Single-PC party:** Row 1 collapses zero-count categories ("1 PC" without "0 Henchmen / 0 Animals / 0 Vehicles" — only show categories with at least 1 entry).
- **Mercenary units in count:** Each unit appears as one count regardless of unit size. A 60-soldier Heavy Infantry unit shows as "1 Mercenary Unit" — the unit's headcount appears in the Composition sub-tab and the Troops tab, not the header.

---

## 5. Composition sub-tab

The default sub-tab on first activation. Shows the party roster as a sortable, filterable table with party-wide summaries.

### 5.1 Layout

Two-region vertical layout:

- **Top:** roster table (most space)
- **Bottom:** party-wide summary panel (compact)

### 5.2 Roster table

A scrollable table with one row per party entity (with mercenary units appearing as a single row identified by the officer). Columns (left to right):

| Column | Source | Notes |
|--------|--------|-------|
| Portrait | `PortraitWithBadge` shared component | Click → cross-activate to Character tab |
| Name | character display name | Click → same as portrait |
| Category | PC / Henchman (humanoid) / Henchman (animal) / Mercenary Unit / Trained Animal / Vehicle | The full categorization; header collapses some of these for brevity |
| Class & level | "Fighter 4" / "Cleric 2" / "Pack mule" / "Cart" / "60 Heavy Infantry, Veteran" | Mercenary rows show unit type and tier (Average / Veteran per `daw_armies_recruitment.xml`) |
| HP | StatReadout (HP type) | Compact: "42/85" with band coloring. For mercenary units: the unit's aggregate or representative HP per the mercenaries-tab GDD when authored. |
| AC | StatReadout (AC type) | Numeric only |
| Encumbrance | EncumbranceBar (compact horizontal) | Band color coding. Mercenary units show "—" (their gear is not party-tracked). |
| Conditions | inline icon strip | Active conditions/effects per character (`gdd-character-tab.md` §3.2.3) |

Row interactions:
- **Single click on row:** select (highlight) — does NOT activate Character tab. Selection state powers contextual buttons (Dismiss, etc.) below.
- **Click on portrait or name:** cross-activate to Character tab (set global active entity + switch tab) per `gdd-management-notebook.md` §4.4.
- **Right-click on row:** context menu — Inspect (cross-activate Character tab), Dismiss (with confirmation modal; PCs cannot be dismissed; mercenary units use "Cancel contract" framing), Manage in Henchmen tab (cross-activate Henchmen tab — only for Henchman rows; future), Manage in Troops tab (cross-activate Troops tab — for Mercenary Unit rows and other unit-scale entities), Reposition in Formation (jumps to Formation sub-tab with this entity selected).

### 5.3 Sort and filter

Sort dropdown above the table with options:
- Default — category group then party-roster order (PCs first, then Humanoid Henchmen by hire date, then Animal Henchmen by acquisition date, then Trained Animals, then Vehicles, then Mercenary Units)
- Alphabetical
- Class & level (high to low)
- HP (low to high — surfaces wounded members)
- Category only (groups by category with no within-group sort)

Filter dropdown:
- Category — show only PCs / Humanoid Henchmen / Animal Henchmen / Trained Animals / Vehicles / Mercenary Units
- Status — show only entities with any active condition / effect (useful for triage)

Filters compose multiplicatively. Selection persists per session per party.

### 5.4 Party-wide summary panel (bottom)

A compact panel below the roster with three groups of derived statistics:

**Class composition (PCs and humanoid henchmen):**
- Class mix as a horizontal bar chart or icon strip ("1 Fighter, 1 Cleric, 1 Mage, 1 Thief")
- Caster count (arcane / divine breakdown)
- Average class level (PCs only)

**Alignment composition:**
- Alignment counts (Lawful / Neutral / Chaotic per ACKS three-axis alignment)
- A "Mixed alignment" indicator when Lawful and Chaotic are both present, *informational only within the party*. Note: in late-game domain and troop play, mixed alignment may carry morale effects (per future ax / DaW rule modeling); the indicator is the surface those rules will hook into when modeled. Within the party itself, no mechanical penalty applies.

**Reaction modifier:**
- Best CHA modifier in the party (since reaction rolls in social encounters use the spokesperson's CHA per `acore_basics_and_characters.xml` Charisma effects and `ax_reactions_and_influencing.xml`)
- Tooltip explaining: "Reaction rolls use the spokesperson's CHA modifier. The displayed value is the highest CHA bonus among PCs and humanoid henchmen — the player elects who speaks during social encounters. Future revisions will model language barriers and contextual exceptions where a different speaker is required."

### 5.5 Action buttons

Below the summary panel, a row of action buttons:

- **Hire Henchman** — opens HiringPanel via the Settlement Panel cross-surface activation. Disabled outside settlements with appropriate tooltip ("Available in settlements with hireling markets").
- **Add Mercenary Unit** — opens mercenary hire flow (future; per `daw_armies_recruitment.xml` §hiring_procedure, hiring is settlement-mediated and ongoing-wage rather than fixed-contract). Disabled until the Troops tab hire flow is implemented.
- **Buy / Sell Vehicle, Animal** — opens shop flow at appropriate settlements (future cross-surface).
- **Dismiss selected** — context-sensitive: enabled when a Henchman or Mercenary Unit is selected in the roster; opens dismissal / contract-cancel confirmation modal. Greyed when no row is selected, or when a PC / Animal / Vehicle is selected (PCs can't be dismissed; animals are sold or set free via separate flow; vehicles are sold).

The action buttons may grow as additional gameplay systems land (e.g., "Distribute XP" if XP banking has UI presence here, etc.). Future additions register in this section.

---

## 6. Travel sub-tab

The Travel sub-tab consolidates all travel-planning numerics for the active party. This is the canonical surface for "how fast can we move, how long until we run out of food and water, what proficiencies and effects help us in this terrain."

### 6.1 Layout

Vertical scrollable layout, sections stacked top to bottom:

1. Movement speeds
2. Rations and water
3. Active travel proficiencies and effects

### 6.2 Movement speeds section

Per `acore_basics_and_characters.xml` movement rules and `acore_adventures_and_encounters.xml` time-and-movement rules:

- **Combat movement** (per round) — derived from slowest member's combat movement under current encumbrance band (10/20/30/40 ft per round per the ACKS bands)
- **Exploration movement** (per turn) — three times combat movement; 30/60/90/120 ft per turn per band
- **Wilderness movement** (per day, by terrain class) — derived per `acore_adventures_and_encounters.xml` Wilderness Movement by Exploration Rate table; multiple terrain rows displayed (clear, road, forest, hills, mountains, swamp, jungle, desert, etc.)
- **Forced march variants** if applicable per the rules

The slowest-member rule governs party speed. The widget displays whose movement is governing (e.g., "Slowest: Bessie the pack mule, 60 ft/turn") so the player knows which member to lighten if they want more speed. Click the slowest-member name to cross-activate Character tab to that entity.

### 6.3 Rations and water section

The headline format (per design):

```
Rations: 7 / 210 (30 days)
Water:   8 / 96  (12 days)
Fodder:  18 / 540 (30 days)
```

Where each line is `{daily consumption (stone)} / {total on hand (stone)} ({days remaining})`.

#### 6.3.1 Daily consumption — humans and demi-humans

Per `acore_adventures_and_encounters.xml` §rations_and_foraging combined with the ACKS in-game encumbrance abstraction (`acore_equipment.xml` §encumbrance):

- **Food per day per humanoid** = **1/6 stone**. This reflects the ACKS items-per-stone abstraction (6 items = 1 stone, where one day's ration is treated as one item).
- **Water per day per humanoid** = **5/6 stone**. Reflects 1 gallon of drinking water per day in stone terms.

These constants apply to PCs and humanoid henchmen (human and demi-human). Mercenaries are NOT included in the party's ration / water totals — they are independent contractors and provision themselves (per `gdd-inventory-tab.md` §4.4 and the LLC analogy in §1.1 of this GDD).

#### 6.3.2 Daily consumption — animals

Animals (animal henchmen and trained animals) have larger consumption needs scaled to their size and metabolism. Per Arbiter design (filling a gap where ACKS RAW does not provide a per-animal daily consumption rate):

- **Fodder per day per animal** = `unencumbered_load / 10` (in stone), where `unencumbered_load` is the animal's "normal load" capacity from `acore_equipment.xml` §animal_vehicle_movement_and_encumbrance.
- **Water per day per animal** = `unencumbered_load / 5` (in stone).

Worked example (Heavy Horse, normal_load = 40 stone): fodder = 4 stone/day, water = 8 stone/day. Mule (normal_load = 40 stone): same numbers. War dog (smaller normal_load) consumes proportionally less.

The build agent must read `unencumbered_load` from each animal's catalog entry and compute fodder / water automatically. No hand-authored per-animal consumption rates required.

#### 6.3.3 Daily consumption — vehicles

Vehicles do not consume food, water, or fodder. They have no metabolism. (A vehicle's *draft animals* consume per §6.3.2; the vehicle itself is inert.)

#### 6.3.4 Aggregate computation

The Travel sub-tab computes three independent daily totals across the active party:

- **Total food (stone/day)** = sum of `1/6` across humanoid PCs and humanoid henchmen
- **Total water (stone/day)** = sum of `5/6` across humanoid PCs and humanoid henchmen + sum of `unencumbered_load / 5` across animal henchmen and trained animals
- **Total fodder (stone/day)** = sum of `unencumbered_load / 10` across animal henchmen and trained animals

Note that water consumption combines humanoid and animal totals, but rations (food for humanoids) and fodder (food for animals) are tracked as separate resources — they are not interchangeable. A wagon stocked with hay does not feed a hungry PC.

#### 6.3.5 On-hand totals

For each resource:

- **Total food on hand** = sum of stone weight of all "Standard Rations" / "Iron Rations" / equivalent food items across all carriers in the active party
- **Total water on hand** = sum of liquid stone weight in waterskins / wineskins / barrels / etc. across all carriers
- **Total fodder on hand** = sum of fodder-item stone weight across all carriers

The catalog must distinguish food / water / fodder item categories so the aggregator can sum each cleanly. Build agent must verify the catalog tagging during implementation.

#### 6.3.6 Days remaining

For each resource: `days_remaining = floor(total_on_hand / total_daily_consumption)`.

Color-coded: green if ≥7 days, amber if 3–6 days, red if ≤2 days. When `daily_consumption` is zero (e.g., a party with no animals showing zero fodder need), days_remaining displays as "—" or "n/a" instead of dividing by zero.

#### 6.3.7 Tooltip math breakdown

Hover on the Rations / Water / Fodder line opens a tooltip with the full breakdown. Example (Rations):

```
Daily food consumption (humanoids only):
  4 PCs × 1/6 stone     = 4/6 stone
  2 Henchmen × 1/6      = 2/6 stone
  Total: 6/6 = 1 stone/day  →  rounded display: 1 stone/day

Carriers holding rations:
  Aldric (PC):           2 stone
  Bessie (mule):        24 stone
  Cart:                  4 stone
  Total:                30 stone

Days remaining: floor(30 / 1) = 30 days
```

For the Fodder tooltip, the per-animal breakdown shows each animal's normal_load and derived fodder/day:

```
Daily fodder consumption (animals):
  Bessie (mule, normal_load 40): 40/10 = 4 stone/day
  Trusty (warhorse, normal_load 40): 40/10 = 4 stone/day
  Total: 8 stone/day

[carriers holding fodder ...]
Days remaining: ...
```

#### 6.3.8 Spoilage and provisioning notes

Per `acore_equipment.xml` §rations:
- Standard Rations last 1 week in wilderness; spoil overnight in dank dungeons
- Iron Rations last 2 months in wilderness, 1 week in dungeon conditions

The Travel sub-tab's ration count does NOT auto-decay for spoilage in v1 (spoilage tracking is deferred per O-P9). Players who carry standard rations into dungeons must manually account for spoilage; the GDD flags the rule in tooltips so players can plan.

### 6.4 Active travel proficiencies and effects

Travel-relevant proficiencies and ongoing effects across the party:
- Pathfinding, Survival, Riding, Caving, Mountaineering, Mapping, Naturalist, and other selected proficiencies relevant to wilderness travel — verify against `acore_proficiencies_rules_and_catalog.xml` and `pc_proficiencies_catalog.xml` during implementation
- Active spells affecting travel (e.g., Endure Element, Pass Without Trace, Wind Walk — verify against spell catalog)
- Beast bonds, mount training, or other class abilities affecting travel speed

Each entry shows the effect summary and which character provides it (with cross-tab activation on click).

### 6.5 Quick actions

Below the proficiencies section, a small action row:
- **Forage** — invokes the foraging flow (proficiency throw 18+, +4 with Survival proficiency, food for 1d6 man-sized creatures per day of travel; per `acore_adventures_and_encounters.xml` §foraging). Available only in wilderness contexts.
- **Hunt** — invokes the hunting flow (full-day commitment, no travel possible, 14+ throw, food for 2d6 man-sized creatures, +1 wandering monster check per `acore_adventures_and_encounters.xml` §hunting). Available only in wilderness contexts.
- **Refill water** — at water sources (river, lake, well per terrain). Stub in v1 if water-source identification isn't modeled; the action button is reserved.

---

## 7. Formation sub-tab

The Formation sub-tab is the unified surface for the party's deployment template — used as the marching order during exploration AND as the starting positions during combat. Per project decision, marching order and combat formation are the same construct.

### 7.1 Two grids: Wilderness and Dungeon

The party maintains two separate formation grids:

- **Wilderness Formation** — 6 wide × 12 deep (max 72 entities). Used in overworld and wilderness travel, settlement movement (where applicable), and combat encounters that initialize from a wilderness-context deployment.
- **Dungeon Formation** — 2 wide × 12 deep (max 24 entities). Used in dungeon exploration (mirrors the ACKS "pairs side by side" rule per `acore_adventures_and_encounters.xml` §marching_order) and combat encounters that initialize from a dungeon-context deployment.

The 24-entity dungeon cap is an Arbiter design choice — ACKS in principle permits up to 7 henchmen per PC (per `acore_basics_and_characters.xml` Charisma effects allowing max 7 henchmen) plus animals, which can yield 40+ in a dungeon at the high end. Arbiter caps at 24 to keep dungeon UI legible and combat tractable. Beyond that scale, gameplay is approaching mass-combat territory and is properly handled by Domains at War rules in a different surface.

### 7.2 Layout

```
+-----------------------------------------------------------+
| [ Wilderness Formation | Dungeon Formation ]              |
+-----------------------------------------------------------+
|                                                           |
|              [front edge — direction of travel]           |
|                                                           |
|  R1: [Aldric] [Brigid] [---]  [---]  [---]  [---]         |
|  R2: [Caelum] [Skadi]  [---]  [---]  [---]  [---]         |
|  R3: [Bessie] [Cart]   [---]  [---]  [---]  [---]         |
|  R4: [Vala]   [---]    [---]  [---]  [---]  [---]         |
|  ... up to R12 ...                                        |
|                                                           |
|              [rear edge]                                  |
|                                                           |
|  Pool (ineligible for this grid): [60 Heavy Inf · Cart]   |
|  Pool (eligible, unassigned):     [Hawk · Donkey]         |
+-----------------------------------------------------------+
| [Reset to default]  [Save as default]  [Apply preset ▼]   |
+-----------------------------------------------------------+
```

(The illustration above shows the Wilderness grid at 6 wide. Dungeon grid is identical structure but 2 wide.)

### 7.3 View toggle (top of sub-tab)

A segmented control at the top of the Formation sub-tab toggles between Wilderness and Dungeon views. Each view shows its grid, its eligible-but-unassigned pool, and its ineligible pool. The persisted formation data is independent per grid — assignments in Wilderness do NOT affect Dungeon and vice versa.

The default view on first activation is Wilderness. The active view persists in `per_tab_substate[Party].formation_active_grid` per §3.2.

### 7.4 Grid orientation

Both grids share the same orientation conventions:
- **Front edge** is at the top of the screen — direction of travel during exploration; closest to enemies during combat encounter init.
- **Rear edge** is at the bottom.
- **Width** runs left to right.
- **Rank 1** is the front-most rank; **Rank N** is the rear.

### 7.5 Eligibility model

Each entity in the party has an **eligibility flag** for each grid based on its category and (for animals/creatures) size/type:

| Entity category | Wilderness eligible | Dungeon eligible |
|-----------------|---------------------|------------------|
| PC | Yes | Yes |
| Humanoid Henchman (Employee) | Yes | Yes |
| Animal Henchman, dungeon-class (mules, donkeys, dogs, hawks, owls, monkeys, ferrets, similar small/medium servant creatures) | Yes | Yes |
| Animal Henchman, wilderness-only (horses, oxen, large beasts of burden, war elephants, etc.) | Yes | No |
| Trained Animal, dungeon-class | Yes | Yes |
| Trained Animal, wilderness-only | Yes | No |
| Vehicle | Yes | No |
| Mercenary Unit (and its officer) | Yes | No — mercenaries do not enter dungeons |

The "dungeon-class vs. wilderness-only" distinction for animals is determined by a **per-creature flag in the catalog**, NOT by size category. The distinction is temperament- and training-based: a war dog and a hawk are dungeon-eligible because they are trained to navigate confined spaces and follow commands; a horse and an ox are wilderness-only because their temperament and bulk make them poor dungeon companions regardless of their precise size category.

Some animals already carry this flag in the existing catalog. The build agent must (a) verify which creatures already have the flag set, (b) extend the flag to creatures that lack it, and (c) consult the catalog at runtime — the flag is the single source of truth. Schema: `dungeon_eligible: bool` on each animal / creature catalog entry. Default for new creatures must be set deliberately during catalog authoring rather than inferred from any heuristic.

#### 7.5.1 Pool rendering

Each grid view shows TWO pools below the grid:
- **Eligible, unassigned pool** — entities of the active grid's eligibility set that are not currently placed in the grid. Drag-droppable into grid cells.
- **Ineligible pool** — entities NOT eligible for the active grid. Rendered with greyed visual treatment and a tooltip explaining ineligibility ("Mercenary units do not enter dungeons" / "Vehicles cannot navigate dungeon corridors" / etc.). Cannot be dragged into the grid; serves as a roster reminder only.

The two pools keep the player aware of the full party while making clear what's available for placement in the active context.

### 7.6 Grid cell behavior

Each grid cell either:
- Holds an entity entry (portrait + name) — drag-drop source / target
- Is empty — drag-drop target

Entity entries are draggable. Drag an entity from its current cell to another cell to swap positions. Drag from a grid cell to the eligible pool to remove from the grid; drag from pool to a grid cell to add.

Empty cells have no functional impact — gaps in formation are permitted (a 4-PC party need not fill all 24 dungeon cells). Empty cells display as subtle outlines.

### 7.7 Defaults and presets

**Save as default** persists the current grid as the party's default for this grid type (Wilderness or Dungeon — saved independently). Default is restored automatically on session start or "Reset to default" click.

**Apply preset** dropdown offers heuristic presets per grid:

For **Wilderness**:
- *Caravan defense:* fighters at front and rear; vehicles, animals, casters in protected mid-line; mercenary units flanking.
- *Forced march:* tightest single-column formation (uses only the central two columns of the 6-wide grid) for fast travel.
- *Scouting:* lone DEX-high entity at the very front (R1, single cell), main party at R3+.
- *Combat-ready:* fighters and front-line at R1–R2, casters R3–R4, ranged R4–R5, vulnerable assets and mercenaries R5+.

For **Dungeon**:
- *Combat-focused:* fighters R1, support R2, casters R3, scouts/thieves at R4+ (or R1 if scouting).
- *Stealth:* highest-DEX entity solo at R1 (left cell only; right cell empty), main body at R3.
- *Protective escort:* fighters at R1 AND R12 (front and rear), vulnerable members in middle.

Presets are heuristic templates; applying one rebuilds the assignments per the heuristic and doesn't lock the order. The player can adjust freely after applying.

### 7.8 Cross-grid transfer

Adding a new party member or equipping a previously-pooled entity into a grid does NOT auto-place them in the other grid. Each grid is independently configured. Players who add a new humanoid henchman, for example, must place them in both Wilderness and Dungeon grids if they want them in both (or accept that they'll appear in the eligible pool until manually placed).

A small convenience: when an entity is moved in one grid, a button "Mirror placement to [other grid]" can copy the same row/cell offset to the other grid where geometry permits. (Disabled if the other grid is narrower and the column doesn't exist.) This is a v1.1 enhancement — v1 keeps the grids fully independent.

### 7.9 Cross-tab behavior

- Click portrait → cross-activate Character tab (set global active entity + switch tab)
- Right-click on grid cell → context menu: Inspect, Remove from grid (move to eligible pool), Dismiss (Henchmen / Mercenaries only — opens dismissal confirmation), View in Composition (jumps to Composition sub-tab)
- Right-click on pool entity → context menu: Inspect, Place at first empty cell, View in Composition

### 7.10 Combat / exploration consumption

The combat controller and exploration system query the active formation grid when initializing:

- **Dungeon exploration:** the Dungeon Formation determines marching ranks per the ACKS marching-order rules. Front-rank entities are first to encounter traps, ambushes, and front-facing combat. Rear-rank entities are last. Per `acore_adventures_and_encounters.xml` §marching_order: "*Marching order should be written down so position is always clear*" — the saved grid IS that written-down order.
- **Wilderness exploration:** the Wilderness Formation is consulted similarly for trap exposure (rare in wilderness), surprise resolution, and any front-facing encounters from the direction of travel.
- **Combat encounter init:** when combat starts, the combat controller deploys entities at cells on the combat grid based on their formation grid position and the encounter geometry.

#### 7.10.1 Strong-preference rule with centroid-reachability constraint

The Formation grid is a **strong preference**, not a strict cell map. The combat controller honors the player's positioning as closely as the encounter geometry allows, subject to the following hard constraint:

> **Every party entity must be able to reach the party centroid within one round of running movement via legal terrain pathfinding, ignoring enemy zones of control.**

This constraint exists to prevent isolation pathologies — a placement that strands a party member on an unreachable ledge, in a hole, behind impassable terrain, or on the far side of an unbridgeable gap. The combat controller resolves the constraint as follows:

1. **Compute the party centroid** — the average position of all deploying entities under the preferred placement.
2. **For each entity, run a pathfinding check** from its preferred cell to the centroid using only legal terrain (walls, pits, lava, water for non-aquatic entities, etc. are blocking; enemy zones of control are NOT blocking for this check, as combat will resolve those positionally).
3. **If the path length exceeds one round of running movement** for that entity, the placement is invalid; the controller relocates the entity to a nearer legal cell that satisfies the constraint while staying as close to the preferred row / column as possible.
4. **If multiple entities fail the constraint**, resolve them in order of entity priority (PCs before henchmen, henchmen before animals, animals before vehicles) so that the most-important members get the closest-to-preferred cells.
5. **Terrain that prevents any legal placement** (e.g., a narrow corridor that cannot fit the full party) compresses the formation toward the centroid — entities that cannot fit at preferred positions stack tighter rather than being stranded.

The combat controller reports any non-preferred placements to the player via a brief notification ("Formation adjusted: terrain prevented Bessie from deploying at rear-mid; placed at rear-left instead.") so the player understands what happened.

The contract between Party tab Formation and the combat controller is owned by `gdd-voxel-tactical-architecture-v1.1.md` and the combat-tactical surface GDDs. This GDD specifies the constraint that combat must honor; the combat system implements the resolution.

---

## 8. Cross-tab interactions (consolidated)

For clarity, all cross-tab interactions originating in the Party tab:

| Source | Action | Target tab |
|--------|--------|-----------|
| Composition row portrait/name click | Set active entity, switch tab | Character |
| Composition right-click → Inspect | Same | Character |
| Composition right-click → Manage in Henchmen tab | Switch tab | Henchmen (future) |
| Composition right-click → Manage in Troops tab | Switch tab | Troops tab per `gdd-troops-tab.md` v2.2+ |
| Composition Hire Henchman button | Cross-surface (settlement-only) | Settlement Panel HiringPanel |
| Header Open Inventory button | Switch tab | Inventory |
| Header Camp button | Cross-surface | Camp flow (future) |
| Travel sub-tab proficiency-provider name click | Set active entity, switch tab | Character |
| Travel sub-tab Forage / Hunt buttons | Cross-surface | Wilderness exploration system |
| Formation grid cell portrait click | Set active entity, switch tab | Character |
| Right-click → Reposition in Formation | Switch sub-tab within Party | Party → Formation |
| Right-click → View in Composition | Switch sub-tab within Party | Party → Composition |

All cross-tab activations use `EventBus.notebook_active_entity_requested(entity_id)` and/or `EventBus.notebook_open_requested(tab_id)` per `gdd-management-notebook.md` §8.4.

---

## 9. Multi-party scope

Per `gdd-ui-architecture.md` §3.9 and `gdd-management-notebook.md` §9, the Party tab reflects only the active party. PartySelectorTabs (HUD) is the switching mechanism.

### 9.1 Overworld / wilderness / settlement contexts

- Party tab content refreshes on `EventBus.active_party_changed`
- Outer-tab-and-sub-tab persistence per the notebook's per-party substate model: when the player switches to party B, they land on party B's last-active sub-tab within the Party tab (likely Composition by default if no prior state)
- The Party Status header refreshes to the new party's aggregates
- Formation grids are per-party; switching parties brings up the new party's saved Wilderness and Dungeon grids

### 9.2 Dungeon and combat contexts

- PartySelectorTabs disabled
- Party tab is scoped to the in-context party only
- All sub-tabs operate normally — the player can review composition, inspect rations between encounters, and revise the Dungeon Formation (the active grid in dungeon contexts) mid-dungeon

### 9.3 Inter-party visibility

The Party tab does NOT show information about parties other than the active one. If the player wants to check on another party, they switch via PartySelectorTabs (when not in dungeon/combat). This is a deliberate scoping decision: the Party tab is fully focused on managing one group.

---

## 10. Empty-state pages

### 10.1 When empty-state is shown

Per `gdd-management-notebook.md` §7.1, the Party tab shows an empty-state page when the active party has zero members. This is a defensive case — during normal play, a party always has at least one PC. The empty-state can manifest if the player just created a new campaign and hasn't built characters yet, or as a degenerate case after total party kill in a non-permadeath campaign mode.

### 10.2 Empty-state content

```
[Icon: portrait silhouettes]

No party members.

A party is the group of player characters and their loyal followers
that explores the world together. Without members, no adventure can
begin.

To populate this party:
- Create one or more PCs through the Character Creation flow.
- (Optional) Hire henchmen at settlements with hireling markets.
- (Optional) Acquire trained animals or vehicles through
  appropriate vendors or quests.
- (Optional) Contract mercenary units at settlements with
  mercenary markets per Domains at War recruitment rules.
```

(Acquisition guidance text is illustrative; per `gdd-management-notebook.md` §3.6, empty-state copy must use ACKS-correct terminology and cite the relevant XML files. The build agent revises the actual copy during implementation.)

### 10.3 Sub-tab empty-states

Within the Party tab, the sub-tabs themselves do NOT have separate empty-states beyond the tab-wide one above. If the Composition sub-tab is showing zero rows because of an aggressive filter, the table area shows "No entities match current filter" inline rather than the full empty-state page (filters are user-applied and easily cleared).

The Travel and Formation sub-tabs always render their structure even with zero entities — empty cells, empty pool, dashes for ration counts. They become useful as soon as members exist.

---

## 11. Migration from existing PartyManagementOverlay

Per the audit, the existing PartyManagementOverlay implements composition / travel / marching order / formation tabs. Migration work for Phase γ:

### 11.1 Scene migration

- The existing PartyManagementOverlay scene becomes the basis for the Party tab content scene
- Surface category changes from "side overlay" to "notebook tab content"
- The standalone overlay is deleted; only the migrated tab content remains

### 11.2 Travel content migration

The existing PartyManagementOverlay's Travel tab content migrates DIRECTLY into this Party tab's Travel sub-tab (§6). Movement / terrain speeds / rest / rations / proficiencies content carries forward; the headline `daily / total / days` rations and water format and the math-breakdown tooltips are new constructions. The Inventory tab does NOT receive a Travel sub-tab — travel-planning numerics are exclusively a Party tab concern per Phase γ scoping.

### 11.3 Marching Order and Formation tab consolidation

The existing PartyManagementOverlay has separate Marching Order and Formation tabs. These collapse into the single Formation sub-tab in §7, with two grids (Wilderness, Dungeon) replacing the previous two-tab structure. Migration:
- Existing Marching Order tab content informs the Dungeon Formation grid build
- Existing Formation tab content (if any was different) informs the Wilderness Formation grid build
- The Formation sub-tab is mostly new construction given the grid sizes (6×12, 2×12) and eligibility model

### 11.4 Party Status header — new

The Party Status header is a new construction. It does not exist in PartyManagementOverlay. Build during Phase γ.

### 11.5 Composition tab content

The existing PartyManagementOverlay Composition tab is the closest match to this GDD's Composition sub-tab. Content carries forward; the table and summary panel are new constructions per §5 unless the existing content already implements them (audit indicates partial coverage). The mercenary-unit row representation (one row per unit, identified by officer) is new behavior to align with the Independent Contractor model.

---

## 12. Performance considerations

- Roster table: typically ≤15 rows (PCs + henchmen + animals + vehicles + a few mercenary units); trivial node count
- Party Status header: 4–6 simple Label / shared-component nodes; sub-millisecond refresh on signal
- Travel sub-tab: O(N) over party members for ration / water aggregation; N is small; no concern
- Formation grid: 24 cells (Dungeon) or 72 cells (Wilderness). At 72 cells, the grid is ~7KB of node memory at default rendering; trivial drag-drop hit-testing.
- Header refresh on `EventBus.encumbrance_changed` and `wallet_changed`: O(N) over party members; no concern

The Party tab as a whole should open in <100ms on first activation per session and <16ms on subsequent activations (cached scene tree per `gdd-management-notebook.md` §2.3.2).

---

## 13. Open questions

- **O-P1.** ~~Formation sub-tab semantics — three-line model or finer-grained?~~ **Resolved (v1.1):** Formation and Marching Order are the same construct (project decision). Single Formation sub-tab with two grids: Wilderness 6×12 and Dungeon 2×12. Eligibility flags per entity category determine grid availability. Per §7.
- **O-P2.** Watch order during camping — should there be a Watch sub-tab in v1, or defer entirely to a future Camp surface? **Default proposal:** defer. The Camp button in the Party Status header opens the camp flow, which has its own UI for watch shifts when that GDD lands.
- **O-P3.** ~~Named Formation presets — should the player be able to save / name custom presets?~~ **Resolved (v1.2): deferred to v1.1+ as a definite future need.** v1 ships built-in presets only (Caravan defense / Forced march / Scouting / Combat-ready / Stealth / Protective escort). Custom-named preset save (e.g., "My Goblin Hunt order") is committed for v1.1+ — this is a confirmed future feature, not a "maybe." Build agent should not design v1 in a way that precludes the v1.1+ custom-preset addition; reserve schema slots for `user_named_presets: Dictionary<String, FormationGrid>` per grid type.
- **O-P4.** Mirror placement between Wilderness and Dungeon grids — should v1 ship the "Mirror placement" convenience button in §7.8, or defer to v1.1? **Default proposal:** defer to v1.1; v1 keeps grids fully independent.
- **O-P5.** Mixed-alignment indicator in Composition summary — within the party, no mechanical penalty applies in v1 per Jedidiah's note. The indicator is the surface for late-game domain / troop morale rules when those land. Keep informational only in v1; the hook exists for future morale modeling.
- **O-P6.** Reaction modifier displayed — best CHA modifier for now per Jedidiah; future revisions will model language barriers and character-specific contextual exceptions (e.g., a Bard cannot speak on behalf of a Barbarian in some encounters). Tooltip text already flags this. No v1 work; flag for later.
- **O-P7.** Hiring storefront integration — should the "Hire Henchman" button in §5.5 cross-activate to the settlement HiringPanel, or open a new in-notebook hire flow? **Default proposal:** cross-activate. The HiringPanel exists; reuse it. Notebook closes; settlement view comes forward; HiringPanel opens.
- **O-P8.** ~~Animal fodder tracking — full daily-consumption model.~~ **Resolved (v1.2):** ACKS RAW does not specify per-animal daily consumption; Arbiter design fills the gap. **Humanoid food = 1/6 stone/day; humanoid water = 5/6 stone/day. Animal fodder = unencumbered_load / 10 stone/day; animal water = unencumbered_load / 5 stone/day.** Vehicles consume nothing. Aggregation rules and tooltip math breakdown in §6.3.
- **O-P9.** ~~Ration spoilage auto-decay.~~ **Resolved (v1.2): deferred to v1.1+ as a definite future need.** v1 does not auto-decay rations despite the ACKS spoilage rules (Standard rations spoil overnight in dank dungeons; Iron Rations last 1 week in dungeon conditions per `acore_equipment.xml` §rations). Spoilage tooltips flag the rule so players can manually account during v1 play. v1.1+ will implement automatic spoilage decay tied to in-game time and current context (wilderness vs. dungeon, dank vs. dry). This is a confirmed future feature. Build agent should not design v1 in a way that precludes v1.1+ spoilage addition; the items schema's existing `acquired_at` timestamp (per `gdd-character-tab.md` §4.3) and the catalog's per-item-type spoilage rules give the implementation the data it needs when the feature lands.
- **O-P10.** ~~Dungeon-eligibility classification for animals.~~ **Resolved (v1.2):** Per-creature catalog flag (`dungeon_eligible: bool`), NOT derived from size or any other rule. The distinction is temperament- and training-based, so a discrete authored flag is the only correct model. Some creatures already carry the flag; build agent verifies and extends as needed. Per §7.5.
- **O-P11.** ~~Combat consumption of Formation grids — preference template or strict cell map?~~ **Resolved (v1.2):** Strong preference with a hard constraint. Combat controller honors the player's preferred placement as closely as encounter geometry allows. Hard constraint: **every party entity must be able to reach the party centroid within one round of running movement via legal terrain pathfinding (enemy zones of control don't block this check)**. Resolution algorithm and entity priority order specified in §7.10.1.

---

## 14. Build sequencing

Per `gdd-management-notebook.md` §14.2, the Party tab is part of Phase γ alongside the Character tab and Inventory tab. Phase γ depends on Phase α (Theme.tres, UiInputController, shared components) and Phase β (notebook scaffolding).

### 14.1 Phase γ scope for Party tab

1. Build the Party tab content scene (`scenes/ui/notebook/party_tab.tscn`).
2. Build the Party Status header (new construction; not in current PartyManagementOverlay).
3. Migrate PartyManagementOverlay's Composition tab content into the Composition sub-tab; add party-wide summary panel per §5.4.
4. Migrate PartyManagementOverlay's Travel tab content into the Travel sub-tab; build the headline rations / water `daily / total / days` widget with math-breakdown tooltips per §6.3.
5. Build the Formation sub-tab with two grids (Wilderness 6×12, Dungeon 2×12), view toggle, eligible / ineligible pool rendering, drag-drop, and built-in presets per §7.
6. Implement entity eligibility flags (`dungeon_eligible: bool` on animals; categorical eligibility for mercenaries, vehicles, etc.) per §7.5.
7. Wire UiInputController for the P keybind.
8. Wire `EventBus.active_party_changed`, `encumbrance_changed`, `wallet_changed`, `rations_changed`, `location_changed` to refresh the Party Status header.
9. Wire cross-tab activation signals per §8.
10. Verify the Inventory tab does NOT keep its previously-spec'd Travel sub-tab; confirm the Inventory tab GDD is updated to reflect Travel migration here.
11. Coordinate with the combat controller to consume Formation grids on encounter init per §7.10.
12. Deprecate and delete PartyManagementOverlay; the standalone overlay is no longer needed.

### 14.2 Dependencies on other GDDs

- `gdd-character-tab.md` — cross-tab activation contract; share `PortraitWithBadge` shared component conventions.
- `gdd-inventory-tab.md` — Travel sub-tab MUST be removed from the Inventory tab in coordination with this build (per `gdd-inventory-tab.md` v1.5+).
- `gdd-management-notebook.md` §6.5 — Promote to Full Member control referenced from Composition right-click context (cross-references the Henchmen entity's Status sub-tab in Character tab; not duplicated here).
- `gdd-ui-shared-services.md` — Theme variants, EventBus signals, shared components (PortraitWithBadge, GoldDisplay, EncumbranceBar, StatReadout).
- `gdd-voxel-tactical-architecture-v1.1.md` — combat consumption contract for Formation grids; coordinate during Phase γ.
- `gdd-henchmen-tab.md`, `gdd-troops-tab.md` v2.2+ — cross-tab activation targets for Composition right-click context.

### 14.3 Phase γ exit criteria for Party tab

- Party tab opens to Composition sub-tab on first activation per session
- Party Status header renders correctly across all three sub-tabs
- Roster table sorts and filters; row click cross-activates Character tab; mercenary units render as single rows identified by officer
- Travel sub-tab renders rations and water in the `daily / total / days` headline format with math-breakdown tooltips
- Formation sub-tab renders both grids; drag-drop assignment works at both grid sizes; eligibility filtering correctly excludes ineligible entities from grid placement; view toggle persists per-party
- All cross-tab activations route through EventBus and reach the correct target tab
- Party Status header refreshes on each documented EventBus signal
- PartyManagementOverlay is deleted; no dangling references in codebase
- Inventory tab Travel sub-tab is removed (verified against `gdd-inventory-tab.md` v1.5+)

---

## 15. Revision history

- **v1.4, 2026-04-30** — Mercenaries → Troops cleanup pass. Five stale references to the old "Mercenaries tab" / `gdd-mercenaries-tab.md` updated: front-matter sibling-doc list (entry replaced with `gdd-troops-tab.md` v2.2+ pointer and broadened-scope note); §5.2 Roster table right-click context ("Manage in Mercenaries tab" → "Manage in Troops tab"); §5.4 action button ("Disabled until Mercenaries tab lands" rewritten with citation to `daw_armies_recruitment.xml` §hiring_procedure and pointer to the Troops tab hire flow); §10 cross-tab actions table; §13 dependent GDDs list. The substantive Composition / Formation / Travel content of this GDD is unchanged: "Mercenary Unit" remains the user-facing UI category label per the Party Status header (consistent with the LLC analogy in §1.1, where Mercenaries are Independent Contractors), and "mercenary" / "mercenaries" as a category of hireling is retained throughout the eligibility, formation-preset, and consumption rules.
- **v1.3, 2026-04-29** — O-P3 and O-P9 disposition locked. Both deferred to v1.1+ as **definite future needs** (committed features, not "maybe" enhancements). O-P3 (custom-named Formation presets): build agent must reserve schema slots for `user_named_presets: Dictionary<String, FormationGrid>` per grid type so v1.1+ can add the feature without schema migration. O-P9 (ration spoilage auto-decay): items schema's `acquired_at` timestamp plus catalog spoilage metadata supply the data the feature will need; v1 ships with manual accounting and spoilage rules surfaced in tooltips. With these locked, all open questions in this GDD are now resolved (O-P1 through O-P11).
- **v1.2, 2026-04-29** — Three open questions resolved with concrete formulas and rules per Jedidiah. **O-P8 (consumption rates):** humanoid food = 1/6 stone/day, humanoid water = 5/6 stone/day, animal fodder = `unencumbered_load / 10` stone/day, animal water = `unencumbered_load / 5` stone/day, vehicles consume nothing. §6.3 fully rewritten with consumption formulas, aggregation rules (food / water / fodder are independent resources), and per-line tooltip math breakdowns. The "v1.1+ deferred" fodder placeholder is removed — fodder is fully implementable now. **O-P10 (dungeon eligibility):** per-creature catalog flag (`dungeon_eligible: bool`); not size-derived. Distinction is temperament- and training-based; some creatures already carry the flag. §7.5 updated. **O-P11 (combat consumption):** strong preference with hard constraint — every party entity must be able to reach the party centroid within one round of running movement via legal terrain pathfinding (enemy ZoC ignored for the check). New §7.10.1 specifies the resolution algorithm and entity priority ordering. Mercenaries excluded from rations / water totals (independent contractors per §1.1).
- **v1.1, 2026-04-29** — Substantial revision per Jedidiah's review. Travel sub-tab moved from Inventory tab into the Party tab as §6, with full movement/rations/water/proficiencies content and the headline `daily / total / days` rations format with math-breakdown tooltips. Marching Order and Formation collapsed into a single Formation sub-tab (§7) with two grids: Wilderness 6×12 and Dungeon 2×12. Entity eligibility model added per §7.5 (PCs and humanoid henchmen are both-eligible; small animal henchmen / trained animals are both-eligible; large animals, vehicles, and mercenary units are wilderness-only). LLC-style party-membership analogy added in §1.1 to formalize Members / Employees / Property / Contractors semantics; mercenary officers reframed as Independent Contractors (the unit appears in composition identified by officer, but officer is structurally still a mercenary — won't haul baggage, won't enter dungeons). Composition sub-tab updated to show mercenary units as one row per unit. Party Status header composition counts revised (zero-count categories collapsed; mercenary units listed as a category). Open questions revised (O-P1 resolved; new O-P8 / O-P9 / O-P10 / O-P11 added).
- **v1, 2026-04-29** — Initial draft. Specified Party Status header (composition counts / encumbrance band / total gold / location / party speed); three sub-tabs (Composition / Marching Order / Formation); roster table with sort, filter, and cross-tab activation; passage-width-aware marching order with built-in presets; three-line formation model with built-in presets; multi-party scope handling (per `gdd-ui-architecture.md` §3.9); empty-state for zero-member defensive case; migration plan from existing PartyManagementOverlay (Travel content moves to Inventory tab per architecture commitment); eight open questions covering formation granularity, watch order, named presets, per-context marching orders, alignment mix, reaction modifier surface, hire integration, and vehicle-in-narrow-passage handling.
