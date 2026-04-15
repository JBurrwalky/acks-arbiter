# GDD: Settlement Exploration UI

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Draft — requires approval before build
**Depends on:** `gdd-realtime-scheduler.md` §4 (city layer architecture), `gdd-settlement-layout.md` (settlement generation, street graph, POI data), `ax_campaign_play.xml` (activity rules, minor/major activity classifications), `acore-setting-construction-rules.xml` (market class, specialist availability)
**Replaces:** Design brief §6.2 (navigable settlement map with node-to-node click movement), build plan D-5 (settlement map renderer as interactive navigable grid)
**Blocks:** Settlement exploration implementation, urban encounter system, hijinks/mercantile UI

---

## 1. Design Rationale

### 1.1 Problem with the Navigable Map

The previous design had the player clicking intersection nodes on a street graph to move through the city block by block. This has three problems under the real-time-with-pause model:

1. **Tedious at city scale.** A party crossing a Market Class II city might traverse 15-20 blocks. Clicking through each intersection while the world clock ticks at turn granularity is busywork, not gameplay.
2. **Desync pressure.** If city exploration required its own fine-grained navigation, it would need either a time-bubble (breaking the "no desync" principle) or the world would advance in 10-minute jumps per click, making it impossible to react to overworld events during long city stays.
3. **Low mechanical density per click.** Unlike dungeon exploration where every cell might contain a trap, monster, or secret, most city intersections are mechanically empty. The interesting decisions happen at PoIs, not between them.

### 1.2 Solution: Menu-Driven PoI Navigation

The city becomes a **menu panel overlaid on the main game view**, not a full-screen map. The player selects destinations from a PoI list. Travel between PoIs is a scheduled event that consumes time and triggers encounter checks, but the player doesn't manually navigate the route. The world clock ticks normally during travel — other parties, armies, and domains continue operating.

The settlement's street graph and block data still exist under the hood. They drive travel time calculations, encounter check frequency, and district-based modifiers. The player just doesn't click through them manually.

### 1.3 Visual Representation

A **small city overview widget** (not full-screen) shows the settlement's node graph schematically with the party's current position and animated travel. This provides spatial orientation without requiring interactive navigation. Think of it as a minimap for the city — informational, not the primary input method.

---

## 2. Screen Layout

When a party is inside a settlement, the main game screen reorganizes into a split layout:

### 2.1 Primary View (Left ~60% of Screen)

The overworld hex map remains visible, centered on the settlement's hex, at a zoomed-in scale. This keeps the player oriented in the world and allows them to see nearby hex activity (army movements, other parties, etc.) without switching screens. The world is still alive and visible.

Alternatively, for settlements with generated layout data, this space could show a **stylized top-down city overview** — the block/ward/district map from `gdd-settlement-layout.md` rendered as a non-interactive illustration with the party's current position marked and travel routes animated. This is purely decorative/informational. The player does not click on it to navigate.

Which view to show (hex map vs. city overview) can be a toggle, or default to city overview when available and hex map when the settlement is too small (hamlets) to have generated layout data.

### 2.2 Settlement Panel (Right ~40% of Screen)

The primary interaction panel. Contains:

1. **Settlement header:** Name, market class, population, current date/time, current district.
2. **PoI list:** The main navigation menu (§3).
3. **Activity panel:** When at a PoI, shows available activities (§4).
4. **Party status strip:** Compact view of party members, HP, encumbrance, coin purse (PP/EP/GP/SP/CP).
5. **Travel indicator:** When traveling between PoIs, shows progress bar, ETA, blocks remaining.

### 2.3 Persistent Elements

The clock/speed controls, notification log, and entity outliner from the overworld UI remain visible and functional. The player can pause, change speed, and monitor world events exactly as they would on the overworld. The settlement panel is *additional* UI, not a replacement for the base game chrome.

---

## 3. PoI List (Primary Navigation)

### 3.1 Structure

The PoI list is organized by district, with each district as a collapsible section:

```
▼ Market District
    The Red Rooster Tavern          [2 blk — commute ~1 turn | meander ~2 turns]
    Andar's Armory (Weaponsmith)    [3 blk — commute ~1 turn | meander ~3 turns]
    Temple of Ammonar               [4 blk — commute ~1 turn | meander ~4 turns]
    Town Square (Market)            ★ Current location

▼ Dockside
    Harbor Master's Office          [8 blk — commute ~2 turns | meander ~8 turns]
    The Barnacle Inn (Tavern)       [9 blk — commute ~2 turns | meander ~9 turns]
    Fishmonger's Wharf              [7 blk — commute ~2 turns | meander ~7 turns]

▼ Thieves' Quarter
    The Blind Beggar (Tavern)       [12 blk — commute ~3 turns | meander ~12 turns]
    ??? (Unknown POI)               [14 blk — commute ~3 turns | meander ~14 turns]

▼ Castle District
    Lord's Keep                     [6 blk — commute ~1 turn  | meander ~6 turns]
    Garrison Barracks               [5 blk — commute ~1 turn  | meander ~5 turns]

▼ City Infrastructure
    North Gate                      [10 blk — commute ~2 turns | meander ~10 turns]
    River Gate                      [5 blk — commute ~1 turn  | meander ~5 turns]
    South Gate                      [15 blk — commute ~3 turns | meander ~15 turns]
```

### 3.2 Information per PoI Entry

Each entry in the list shows:

- **Name** (or "???" if undiscovered — see §3.6)
- **Type icon** (tavern, temple, shop, gate, guild, etc.)
- **Distance** in blocks from current location (calculated from the street graph shortest path)
- **Estimated travel time** for both commuting and meandering speeds (the currently selected speed mode is highlighted)
- **District name** (via the section header)
- **Status indicators:** Open/closed (based on time of day), "new" badge for unvisited PoIs, quest marker if relevant

### 3.3 Urban Movement Rules (ACKS Sacred)

These rules are sourced from ACKS and are sacred — they cannot be modified by project design.

#### 3.3.1 Movement Speeds

Two movement speeds are available in settlements. The player selects which mode the party uses (toggle in the travel indicator or a persistent setting in the settlement panel):

**Commuting speed** — walking with purpose toward a known destination.
- **90 seconds (15 rounds) per city block.**
- ~1 turn (10 min) between two PoIs in the same district.
- ~2 turns (20 min) between two PoIs in adjacent districts.
- Requires a **Navigation throw of 11+** every turn to avoid getting lost (see §3.3.4).
- Characters who have traveled this specific route before are exempt from the Navigation throw for that route.
- Characters who have visited the destination before but not by this route get +4 to the Navigation throw.

**Meandering speed** — exploring, sightseeing, shopping, taking in the neighborhood.
- **1 turn (10 minutes) per city block.**
- ~6 turns (1 hour) between two PoIs in the same district.
- ~12 turns (2 hours) between two PoIs in adjacent districts.
- **No Navigation throw required.** The slow pace makes it easy to read signs and ask directions.
- Meandering through a district reveals discoverable PoIs in that district (see §3.6).

**Litter/wagon travel** — same speed as walking, but affords more privacy. No mechanical speed difference; the distinction matters for encounter flavor (NPCs may not see who's inside) and potentially for hijinks/stealth.

#### 3.3.2 Route Preference: Streets vs. Alleys

The player selects a route preference via a toggle in the settlement panel, in the same UI area as the movement speed toggle:

- **Streets Only** (default): The travel calculator routes exclusively on main roads, secondary avenues, and minor streets. No alley edges are used. Longer routes in blocks, but encounter checks use the less-frequent street encounter schedule (§6.2).
- **Use Alleys**: The travel calculator includes alley edges and will use them when they produce a shorter path. Faster in blocks, but any alley segments on the route use the more-frequent alley encounter schedule (§6.2). The PoI list and travel indicator update to reflect the shorter block count but note the alley usage: e.g., `"8 blk (via alleys) — commute ~2 turns"`.

The toggle affects the Dijkstra/A* pathfinding by including or excluding alley-type edges from the street graph. Both options are always available; the player chooses their risk/speed tradeoff.

#### 3.3.3 Encumbrance and Mounts

Encumbrance and mounts do **NOT** affect city travel speed. The commuting and meandering rates (90 seconds/block and 1 turn/block respectively) are fixed. City movement speed is determined by congestion, crowd density, road conditions, and city layout — not by personal carrying capacity or whether the character is mounted. A mounted character is no faster than a pedestrian in a crowded medieval city street, and a heavily laden porter moves at the same pace as everyone else in the flow of foot traffic.

#### 3.3.4 Navigation and Getting Lost

At commuting speed, the party makes a Navigation throw (11+ on 1d20) every turn:

- **Success:** Party continues on the optimal route.
- **Failure:** Party gets lost and ends up **1d4+1 blocks away** from their intended position that turn. The system recalculates the remaining route from the new (wrong) position, increasing total travel time.
- **Modifiers:** Navigation proficiency (+4), previously visited destination but new route (+4), previously traveled this exact route (no throw required — auto-success).

The system tracks which routes the party has traveled (origin PoI → destination PoI pairs) and which PoIs the party has visited. This data drives Navigation throw exemptions.

Getting lost is invisible to the player until they arrive somewhere unexpected or the travel time exceeds the estimate. The notification log reports: `"<Party> took a wrong turn — lost in the <District> district."` The travel indicator updates with the new ETA.

#### 3.3.5 Straggling Groups (Optional Rule — Enabled by Default)

Large parties are slowed by narrow streets and dense crowds:

- **6–11 characters:** Commuting speed is halved (180 seconds per block instead of 90).
- **12+ characters:** Commuting speed is quartered (360 seconds per block instead of 90).
- **Meandering speed is unaffected** by group size.

The party can **split into smaller groups** to avoid the penalty. Each group travels independently and faces its own encounter throws. The UI handles this via the split-party controls (each sub-group appears as a separate entry in the entity outliner, with its own current PoI and travel state).

This rule is togglable in settings (default: on). When disabled, group size does not affect commuting speed.

### 3.4 Clicking a PoI

Clicking a PoI in the list does one of two things:

**If the party is already at that PoI:** Opens the Activity Panel for that PoI (§4).

**If the party is elsewhere:** Initiates travel. The system:

1. Calculates the shortest path through the street graph from the party's current node to the target PoI's node.
2. Counts blocks traversed along that path.
3. Determines travel time based on the selected movement speed (§3.3.1):
   - **Commuting:** 15 rounds (90 seconds) per block × block count, adjusted for straggling group penalty if applicable.
   - **Meandering:** 1 turn (60 rounds / 10 minutes) per block × block count.
4. Schedules a `city_travel_arrival` event at the appropriate timestamp.
5. For commuting speed: schedules a `navigation_check` event every turn during travel. On failure, inserts a `got_lost` event that recalculates the route with a 1d4+1 block deviation.
6. Schedules encounter checks during travel per the urban encounter frequency rules (§6.2).
7. The travel indicator in the panel shows: current speed mode, blocks remaining, ETA, and (at commuting speed) a Navigation throw result each turn.
8. During travel, the clock ticks normally. The world advances. If an encounter fires during travel, the game auto-pauses and the encounter is resolved before travel continues.

### 3.5 Travel Interruption

While traveling between PoIs, the player can:

- **Cancel travel** (click the "Cancel" button on the travel indicator, or click a different PoI). The party stops at the nearest intersection node along their route. Time already consumed is not refunded.
- **Switch speed** mid-travel (toggle commuting ↔ meandering). Remaining travel time recalculates from the current position.
- **Pause the game** and issue orders to other entities (other parties, armies, etc.) before resuming.

If an encounter triggers during travel, the encounter resolves (possibly including combat on a procedurally generated urban battle map per `gdd-combat-map-generation.md` §2.3). After the encounter, the player can choose to continue to the original destination or redirect.

### 3.6 PoI Discovery

Not all PoIs are known to the party immediately on entering a city:

- **Obvious PoIs** (visible on arrival): Gates, main market/town square, prominent temples, the largest tavern, any PoI on a main road. These are always visible in the list.
- **Discoverable PoIs** (found through exploration): Smaller shops, hidden taverns, guild halls, NPC residences, undercity entrances. These appear as "??? (Unknown location)" in their district section until discovered.
- **Discovery methods:** Visiting a district (traveling through it, even to another PoI in the same district) reveals all obvious PoIs in that district. Asking NPCs for directions (via the Gather Information activity at taverns) can reveal specific hidden PoIs. Thieves' Quarter PoIs require either rumor/NPC introduction or actively searching (Gather Information with a "find the thieves' guild" query).

### 3.7 City Gates as PoIs

Gates are listed under "City Infrastructure" and serve double duty:

- **As travel destinations:** Click a gate to travel there.
- **As exit points:** When at a gate, the Activity Panel offers "Exit Settlement" which returns the party to the overworld hex map.
- **As entry points:** When entering a settlement from the overworld, the party starts at the nearest gate to their approach direction.

---

## 4. Activity Panel

When the party is at a PoI, the right side of the settlement panel shows available activities for that location. Activities are the core gameplay of city exploration — this is where the interesting decisions happen.

### 4.1 Activity Categories by PoI Type

| PoI Type | Available Activities |
|----------|---------------------|
| **Tavern/Inn** | Rest (short/long), Gather Information (rumors), Carouse, Hire Henchmen (post notice), Recruit Mercenaries, Buy Food/Drink |
| **Temple** | Healing (cure disease, remove curse, restore life), Tithe, Commune (divine services), Commission Blessing |
| **Shop (general)** | Buy Equipment, Sell Equipment, Commission Equipment (custom orders, 10× market availability) |
| **Shop (specialist)** | Buy/Sell specialist goods, Commission specialist items |
| **Market/Town Square** | Buy Equipment (full market class availability), Sell Equipment, Hire Hirelings, Post Notices, Gather Information |
| **Guild Hall** | Hire Specialists, Access Guild Services (varies by guild type), Guild Quests |
| **Lord's Keep / Ruler** | Audience with Ruler, Pay Taxes/Tribute, Petition for Land Grant, Report Domain Events |
| **Garrison/Barracks** | Recruit Mercenaries, Military Equipment, Garrison Services |
| **Gate** | Exit Settlement, Enter/Exit Market (mercantile, tolls per ACKS), Guard Interaction |
| **NPC Residence** | Talk, Trade, Quest Interaction |
| **Undercity Entrance** | Enter Undercity (transitions to dungeon exploration on the undercity dungeon map) |

### 4.2 Activity Timing

Per `ax_campaign_play.xml`, ACKS classifies activities as:

- **Minor activities:** Take negligible time. A character can perform multiple minor activities per day. Examples: buying equipment, picking up commissions, entering a market, posting a notice.
- **Major activities:** Take significant time (hours or a full day). A character can typically perform one major activity per day. Examples: gathering information, recruiting henchmen, carousing, spell research, crafting, hijinks.

When the player selects an activity:

1. The system checks if it's minor or major.
2. **Minor activities** resolve immediately with no clock advancement (or a token 1-turn advance for verisimilitude). The result is presented and the player can select another activity.
3. **Major activities** schedule a completion event at the appropriate future time (typically end of day or after the specified duration). The clock advances to that point. If other world events fire during that time, the game auto-pauses to handle them, then returns to the activity result when it completes.

### 4.3 Multi-Character Activities

Some activities can be performed simultaneously by different party members at the same PoI:

- Multiple characters can buy/sell at a market independently (minor activities, no conflict).
- One character gathers information at a tavern (major) while another carouses (major) — both schedule their events and resolve on completion.
- One character commissions equipment at a smith while another hires henchmen at the market.

The party doesn't need to stay together in the city. Individual characters can be dispatched to different PoIs to perform activities concurrently. The system tracks each character's location and activity independently. The clock advances to the next event for any character.

**Split-party in city:** Characters at different PoIs can perform activities simultaneously. This is handled naturally by the scheduler — each character has their own scheduled events. The party "reconvenes" when all characters return to the same PoI or when the player issues a group travel order.

### 4.4 Shopping Interface

When the player selects "Buy Equipment" at a market or shop:

- Opens the shop inventory panel showing available items filtered by market class and shop type.
- Items are listed with name, cost, weight, and availability count (per ACKS market availability rules).
- The player selects items to buy, sees the running total and encumbrance impact.
- Confirming the purchase deducts gold and adds items to the character's inventory.
- This is a minor activity — resolves immediately.

"Commission Equipment" works similarly but shows the full equipment list (10× normal availability), with delivery dates calculated per ACKS rules (1 day per 500gp for buildings/vehicles, 1 day per 5gp for other equipment). A scheduled `commission_complete` event is inserted for pickup.

### 4.5 Henchman Recruitment

At taverns, markets, or guild halls, the player can post a recruitment notice:

1. **Post Notice** (minor activity): Costs gold per ACKS rules. A `recruitment_response` event is scheduled for the next day (or per the recruitment timeline from `ax_henchmen_recruitment_expanded.xml`).
2. When the event fires: the system generates available henchman candidates based on settlement demographics, market class, and the PC's CHA modifier/reputation.
3. The player reviews candidates and interviews them (may involve reaction rolls).
4. Accepted henchmen join the party.

### 4.6 Gathering Information

At taverns and similar social PoIs, the player can spend time gathering rumors and information:

1. **Gather Information** (major activity, takes ~4 hours / half a day).
2. On completion, the system draws from the settlement's rumor table (generated by `gdd-quest-rumor-system.md`).
3. Results may include: quest hooks, NPC locations, dungeon rumors, political information, hidden PoI reveals, warnings about dangers.
4. Repeated gathering at the same tavern yields diminishing returns (tracking which rumors have been heard).

---

## 5. Time of Day and Availability

### 5.1 Business Hours

PoIs have operating hours that affect availability:

| PoI Type | Hours Available | After Hours |
|----------|----------------|-------------|
| Shop | Dawn to dusk (Timekeeping dawn/dusk signals) | Closed — no buying/selling. Can still travel to the location. |
| Market/Town Square | Dawn to ~2 hours before dusk | Closed. |
| Temple | Always (reduced services at night) | Healing always available; other services dawn-to-dusk only. |
| Tavern/Inn | Always | Full services. Some activities (gathering info) are better at night. |
| Guild Hall | Dawn to dusk | Closed. |
| Lord's Keep | Dawn to dusk (audiences by appointment) | Gate closed; emergency audience only. |
| Gate | Always (may close at night in wartime) | Default: open. Wartime/siege: closed dusk-to-dawn. |

### 5.2 Night Travel

Traveling between PoIs at night is possible but:

- Encounter checks use nighttime urban encounter tables (different threat profile — more thieves, fewer merchants).
- Movement speed may be unchanged (city streets are somewhat navigable at night) or slightly reduced (project-designed, tunable).
- PoIs that are closed show a "Closed until dawn" status. The player can still travel there and wait (schedule a `wait_until_dawn` event), but cannot perform activities until the PoI opens.

### 5.3 Dawn/Dusk Integration

Timekeeping's `dawn()` and `dusk()` signals trigger PoI availability updates. If the party is at a shop when dusk fires, a notification appears: "Andar's Armory is closing for the day." The shop's activity panel greys out purchase options. The party can stay (nothing happens — they're just standing outside a closed shop) or travel elsewhere.

---

## 6. Urban Encounters

### 6.1 Encounter Concept (ACKS Sacred)

Urban random encounters are fundamentally different from dungeon/wilderness encounters. A city is packed with people — the party will "encounter" strangers constantly. A random encounter in an urban context represents an **unusual incident or interruption**: an interesting public occurrence, an unexpected development that disrupts the party's plans and forces them to act. Routine pedestrian traffic is not an encounter.

### 6.2 Encounter Check Frequency (ACKS Sacred)

Encounter checks fire on a time basis, not a per-block basis:

| Context | Check Frequency | Roll | Encounter On |
|---------|----------------|------|-------------|
| Wandering streets by **day** | Every **1 hour (6 turns)** | 1d6 | 6+ |
| Wandering streets by **night** | Every **30 minutes (3 turns)** | 1d6 | 6+ |
| Wandering **alleys** by **day** | Every **30 minutes (3 turns)** | 1d6 | 6+ |
| Wandering **alleys** by **night** | Every **10 minutes (1 turn)** | 1d6 | 6+ |

**District modifiers:** Some districts are more dangerous. The Thieves' Quarter and similar high-crime areas may increase the encounter frequency or lower the encounter threshold. Specific modifiers are per-settlement from stocking data.

**Looking for Trouble (optional rule, player-activated):** If the party deliberately loiters, makes noise, approaches strangers, and generally draws attention, encounters occur on **5+ on 1d6** instead of 6+. This is a toggle the player can activate in the settlement panel when they want to provoke encounters (e.g., drawing out thieves' guild contacts, finding mercenary work, or just being reckless).

The system determines which encounter frequency applies based on: time of day (Timekeeping dawn/dusk signals), the route taken (main streets vs. alleys — the street graph edge types from `gdd-settlement-layout.md` §7.2 classify routes as main_road, secondary, minor, or alley), and player choices (Looking for Trouble toggle).

### 6.3 Encounter Scheduling During Travel

When the party begins traveling between PoIs:

1. Calculate total travel time (per §3.3.1 movement speed).
2. Determine the route type: primarily main streets, secondary streets, or alleys (based on the shortest path through the street graph — the edge types along the path determine the encounter context).
3. Schedule `city_encounter_check` events at the appropriate intervals based on the frequency table above. For a 3-turn daytime commute on main streets, no encounter check fires (less than 6 turns). For a 7-turn meandering trip, one check fires at the 6-turn mark.
4. Each check resolves as a 1d6 roll. On 6+ (or 5+ if Looking for Trouble), an encounter occurs.

**When stationary at a PoI:** Encounter checks continue at the applicable frequency if the party is "on the streets" (outside, at a market stall, loitering near a gate). Indoor activities at PoIs (tavern interior, temple sanctuary, shop interior) do NOT trigger street encounter checks — they have their own PoI-specific encounter tables (§6.5).

### 6.4 Encounter Resolution

When an urban encounter fires:

1. Game auto-pauses.
2. Determine encounter type from the district's urban encounter table: NPC encounter (merchant, noble, thief, beggar, patrol, etc.), event (street performance, argument, fire, procession), or hostile encounter (pickpocket, mugger, gang).
3. **Non-hostile encounters:** Present as a notification with interaction options (Talk, Ignore, etc.). Resolve via reaction rolls and player choice. These are quick — a few seconds of paused interaction.
4. **Hostile encounters:** Trigger combat on a procedurally generated urban battle map (per `gdd-combat-map-generation.md` §2.3). After combat, the party can continue to their destination or redirect.

### 6.5 Encounters at PoIs

Some PoIs have their own encounter tables that fire on arrival or during activities:

- **Tavern:** Barroom encounters (drunken brawl, interesting stranger, thieves' guild recruiter).
- **Market:** Pickpocket attempts, merchant disputes, special item availability.
- **Thieves' Quarter:** Shakedowns, guild contact approaches, illicit goods offers.

These are separate from street encounter checks and fire as part of the PoI's activity resolution.

---

## 7. Undercity Transition

When the party accesses an undercity entrance (sewer grate, cellar stairs, crypt entrance, etc.):

1. The settlement panel closes.
2. The dungeon exploration UI (per `gdd-dungeon-map-ui.md`) takes over.
3. The party is now in the undercity dungeon map, operating under dungeon exploration rules (real-time-with-pause on the diamond grid, with all dungeon mechanics — light, traps, encounters, etc.).
4. The world clock continues ticking normally throughout.
5. Exiting the undercity returns the party to the surface at the entrance PoI. The settlement panel reopens.

This is identical to entering a dungeon from the overworld — the transition is just from a city PoI instead of a hex map location.

---

## 8. Multi-Party City Play

Multiple parties can be in the same settlement simultaneously. Each operates independently:

- Each party has its own position in the settlement (tracked as a current PoI node).
- Each party's travel and activities are separate scheduler events.
- If both parties are at the same PoI, they can interact (trade, transfer members, etc.) via the party management UI.
- One party can leave the settlement while another stays.

---

## 9. City Overview Widget

### 9.1 Purpose

A small (roughly 300×300px, scalable) visualization of the settlement's spatial layout. The map itself is non-interactive (no click-to-navigate), but **character pins on the map are interactive** — they show tooltips on hover and open info panels on click. Provides orientation, a sense of place, and at-a-glance status for dispersed party members.

### 9.2 What It Shows

- **Block outlines** from the generated settlement layout, colored by district.
- **Wall perimeter** (if walled).
- **Water features** (river, coastline).
- **PoI markers** (small icons at their street graph positions) — only for discovered PoIs.
- **Character pins** — one pin per party member/henchman currently in the settlement, positioned at their current PoI node. Each pin uses the character's portrait (tiny circular crop) or a class-colored dot if portraits are too small at this scale. Pins animate along routes when characters are traveling.
- **District labels** (text overlays on each district area).

### 9.3 Character Pin Interaction

The map background is not clickable for navigation, but character pins ARE interactive:

**Hover over a pin:** Shows a small tooltip with:
- Character name
- Current location — if at a PoI, shows PoI name. If traveling between PoIs, shows `"<District Name> Streets"` (e.g., "Temple District Streets").
- Current activity (e.g., "Gathering information — 2 hours remaining," "Traveling to North Gate — 3 blocks remaining," "Idle")

**Click a pin:** Opens a **Character Info Panel** (a small floating panel or sidebar detail view) showing:
- Character portrait (256×256)
- Name, class, level
- Current HP (current / max, color-coded)
- Coin purse: PP, EP, GP, SP, CP (all five denominations, zeroes shown)
- Current location — PoI name and district if at a PoI; `"<District Name> Streets"` if traveling
- Current activity and progress/ETA
- Action buttons: "Go Here" (centers the settlement panel PoI list on this character's location), "Recall" (issue a travel order to bring this character to the selected PoI)

If multiple characters are at the same PoI, their pins stack with a count badge. Clicking the stack opens a small popup listing all characters at that location; clicking a character in the list opens their info panel.

### 9.4 What It Does NOT Do

- **No click-to-navigate on the map background.** All navigation is through the PoI list in the settlement panel. Clicking empty space on the map does nothing.
- **No zoom or pan.** It's a fixed overview that fits the entire settlement. For very large cities (Metropolis), it may show a simplified schematic (district blobs rather than individual blocks).
- **No NPC/monster rendering.** Only party members and henchmen appear as pins. NPCs, guards, and other entities exist in the encounter/activity system, not as map tokens.

### 9.5 Placement

The widget sits in the top-left corner of the primary view area (§2.1), overlaying the hex map or serving as the city overview itself. When the player toggles to hex map view, the widget shrinks to a corner overlay. When toggled to city overview, the widget expands to fill the primary view area as a larger, more detailed (but still non-interactive) illustration.

---

## 10. What Changes From Current Design

### 10.1 Settlement Layout GDD

`gdd-settlement-layout.md` is unchanged in its data generation — wards, blocks, streets, POIs, districts, walls, vertical layers all still get generated. What changes is that the generated street graph is consumed by the travel time calculator rather than by a navigable map renderer. The SettlementLayout output structure gains no new fields; the UI just reads it differently.

One adjustment: the street graph's edge weights (§7 of settlement layout GDD) need to be calibrated in "blocks" as a unit the travel time calculator uses. Currently they store `length: float` in map units. Either normalize these to block counts or define the block-to-map-unit conversion.

### 10.2 Build Plan D-5

D-5 was "Settlement Map (Single-District Minimum)" — a 250×250 navigable urban grid. This is replaced by:

- **Settlement panel UI** (the PoI list, activity panel, travel indicator).
- **City overview widget** (non-interactive layout visualization).
- **Travel time calculator** (shortest-path on street graph → blocks → turns).
- **Urban encounter system** (encounter checks during travel, district-based tables).

The isometric diamond grid renderer is NOT needed for the settlement surface layer. The settlement layout data is consumed for travel calculations and the overview widget, not for tile-by-tile rendering. (The undercity IS a dungeon and uses the dungeon renderer as before.)

### 10.3 Design Brief §6.2

Replace "Movement is node-to-node on the street network" with "Navigation is menu-based via the PoI list; travel time is calculated from the street graph but the player does not manually navigate it."

---

## 11. Data Requirements

### 11.1 Data Consumed

| Data | Source | Used For |
|------|--------|----------|
| `SettlementLayout` (blocks, street_graph, districts, pois, walls) | `gdd-settlement-layout.md` output | Overview widget rendering, travel time calculation |
| `StreetGraph` (nodes, edges, weights, edge types) | SettlementLayout | Shortest-path calculation, route type determination (main street vs alley for encounter frequency) |
| `StreetEdge.type` (main_road, secondary, minor, alley) | SettlementLayout | Encounter check frequency selection per §6.2 |
| `POI` data (type, name, district, node_id) | SettlementLayout | PoI list population, activity availability |
| Market class | Settlement data | Equipment availability, specialist availability, service pricing |
| Time of day | Timekeeping autoload | PoI open/close status, encounter frequency (day vs night per §6.2) |
| Party data (members, count, inventory, currency [PP/EP/GP/SP/CP], proficiencies) | CharacterData / PartyData | Travel speed (straggling group check), Navigation throws, activity eligibility, shopping |
| Known routes (origin_poi → destination_poi pairs) | SQLite `known_city_routes` table | Navigation throw exemptions (§3.3.4) |
| Visited PoIs | SQLite `visited_pois` table | Navigation throw modifier (+4 for visited destination, new route), PoI discovery |
| Urban encounter tables | Settlement stocking data | Encounter resolution during travel |
| Rumor tables | `gdd-quest-rumor-system.md` output | Gather Information results |

### 11.2 Data Produced

| Action | Data Change | Persisted? |
|--------|------------|------------|
| Travel between PoIs | Inserts `city_travel_arrival`, `navigation_check`, and `city_encounter_check` events | Scheduler (in-memory) |
| Arrive at PoI | Records route in `known_city_routes`, records PoI in `visited_pois` | Yes (SQLite) |
| Navigation check fails | Party position deviates; route recalculated | Scheduler update (in-memory) |
| Buy/sell equipment | Modifies character inventory and currency | Yes (SQLite) |
| Commission equipment | Inserts `commission_complete` event at future date | Scheduler + SQLite |
| Hire henchman | Adds henchman to party, deducts currency | Yes (SQLite) |
| Gather information | Marks rumor as heard, may reveal PoI | Yes (SQLite) |
| Rest (long) | Advances clock, heals party, triggers encounter checks during rest | Yes (SQLite) |
| Exit settlement | Returns party to overworld hex, closes settlement panel | Yes (SQLite) |
| Enter undercity | Transitions to dungeon exploration mode | Context switch only |
| PoI discovery | Updates PoI visibility state in `visited_pois` | Yes (SQLite) |

---

## 12. Scheduler Integration

| Player Action | Scheduler Event(s) |
|--------------|-------------------|
| Click PoI to travel (commuting) | `city_travel_arrival` at +N turns (15 rounds/block × blocks, adjusted for straggling). `navigation_check` every turn during travel. `city_encounter_check` per §6.2 frequency (every 6 turns daytime streets, 3 turns night/alleys, 1 turn night alleys). |
| Click PoI to travel (meandering) | `city_travel_arrival` at +N turns (1 turn/block × blocks). No navigation checks. `city_encounter_check` per §6.2 frequency. |
| Navigation check fails | `got_lost` — party deviates 1d4+1 blocks. Route recalculated, `city_travel_arrival` rescheduled with new ETA. |
| Cancel travel | Remove pending `city_travel_arrival`, `navigation_check`, and remaining `city_encounter_check` events. Party stops at nearest node. |
| Switch speed mid-travel | Recalculate remaining travel time from current position. Reschedule `city_travel_arrival` and encounter checks. |
| Toggle Looking for Trouble | Adjusts encounter threshold from 6+ to 5+ (or vice versa) for subsequent checks. |
| Buy/Sell (minor) | No scheduler event — resolves immediately. |
| Commission equipment | `commission_complete` at +N days per ACKS rules (1 day/500gp buildings, 1 day/5gp equipment). |
| Gather Information (major) | `gather_info_complete` at +4 hours (~24 turns). |
| Carouse (major) | `carouse_complete` at +1 day. |
| Hire Henchmen (post notice) | `recruitment_response` at +1 day (or per recruitment rules). |
| Rest (long) | `long_rest_complete` at +8 hours. `city_encounter_check` events during rest per §6.2 frequency (if resting outdoors; indoor rest at a tavern/inn uses PoI encounter tables instead). |
| Wait until dawn | `wait_complete` at next dawn (Timekeeping `dawn()` timestamp). |
| Exit settlement | Immediate — party returns to overworld. |

---

## 13. Build Guidance for Claude Code

### 13.1 What to Build

1. **SettlementPanel scene** — the right-side panel with PoI list, activity panel, travel indicator, and party status strip. This is the core new UI.
2. **PoI list component** — collapsible district sections with PoI entries showing distance, dual travel time estimates (commuting/meandering), type icon, and status.
3. **Activity panel component** — dynamic panel that populates based on PoI type (§4.1). Each activity type has its own sub-panel or dialog (shopping, hiring, information, etc.).
4. **Travel time calculator** — takes the street graph, party's current node, and target node. Runs Dijkstra/A* on the street graph. Returns: path (node sequence), block count, route type breakdown (how many blocks on main streets vs. alleys), and turn estimates for both commuting and meandering speed. Must account for straggling group penalties (§3.3.5) based on party size.
5. **Movement speed toggle** — persistent setting in the settlement panel header or travel indicator: Commuting / Meandering. Affects all travel time calculations and PoI list estimates. Can be switched mid-travel (§3.5).
6. **Route preference toggle** — in the same UI area as the speed toggle: Streets Only (default) / Use Alleys. Controls whether alley-type edges are included in pathfinding. When set to Use Alleys, the PoI list shows shorter block counts but notes alley usage. Affects encounter frequency scheduling (alley segments use more-frequent encounter checks per §6.2).
7. **Navigation throw system** — at commuting speed, rolls Navigation 11+ every turn during travel. Checks `known_city_routes` table for route exemptions and `visited_pois` for the +4 modifier. On failure, deviates the party 1d4+1 blocks and recalculates route. Navigation proficiency modifier (+4) applied from party member proficiency data.
8. **Route and PoI memory** — SQLite tables (`known_city_routes`, `visited_pois`) populated automatically on arrival at each PoI. Consumed by the navigation throw system for exemptions and modifiers.
9. **City overview widget with character pins** — renders the settlement layout as a non-interactive schematic. Uses the block polygons, wall path, water features, and PoI markers from SettlementLayout. **Character pins** (one per party member in the settlement) positioned at their current PoI node, animated during travel. Hover pin → tooltip (name, location, activity). Click pin → character info panel (portrait, name, class, level, HP, coin purse [PP/EP/GP/SP/CP], location, activity). Stacked pins at shared PoIs show count badge with click-to-expand.
10. **Urban encounter system** — encounter check scheduling during travel per §6.2 frequency table (time-based, not block-based; varies by day/night and street type). Looking for Trouble toggle adjusts the threshold from 6+ to 5+. Encounter table selection based on district.
11. **Looking for Trouble toggle** — a button in the settlement panel that the player can activate/deactivate. When active, encounter threshold drops from 6+ to 5+ on 1d6. Visual indicator so the player knows it's on.
12. **PoI discovery tracker** — per-settlement tracking of discovered PoI IDs. Obvious PoIs auto-discovered on entry; meandering through a district reveals that district's PoIs; Gather Information can reveal hidden PoIs. Backed by `visited_pois` table.
13. **Straggling group indicator** — if the party has 6+ members, show a warning in the travel indicator: "Large group — commuting speed halved" (or "quartered" for 12+). Suggest splitting into smaller groups.

### 13.2 What to Rework

- **Any existing settlement map renderer** that operates as a navigable interactive map (D-5 or stubs thereof): Replace with the city overview widget (non-interactive).
- **Any existing node-click navigation** for settlement movement: Replace with PoI list click → scheduled travel.
- **Any existing settlement movement code that does not cost time:** Movement between PoIs MUST consume time per §3.3.1. Commuting: 15 rounds per block. Meandering: 1 turn per block. If current code moves the party between nodes with no Timekeeping advancement, this must be fixed.
- **Settlement-related navigation stack entries:** The settlement is no longer a separate navigation layer that replaces the overworld view. It's a panel overlay on the existing view.
- **Database schema:** Add `known_city_routes` and `visited_pois` tables (see §15 open question #2 for schema suggestion). Add migration file.

### 13.3 What Stays the Same

- **Settlement layout generation** (`gdd-settlement-layout.md`): Completely unchanged. Wards, blocks, streets, POIs, walls, vertical layers all generate as before.
- **Settlement stocking** (`gdd-settlement-stocking.md`): Completely unchanged. NPCs, shops, encounter tables all populated as before.
- **Undercity/dungeon rendering**: Undercity levels still use the dungeon diamond grid and `gdd-dungeon-map-ui.md` interaction model.
- **Timekeeping, EventScheduler, EventBus, DiceSystem**: No changes.

---

## 14. Resolved Decisions

These were previously open questions, now resolved:

- **Individual character dispatch:** Each character in the settlement has their own pin on the city overview widget (§9.2–9.3). Hover shows name/location/activity tooltip; click opens a character info panel with portrait, name, level, class, HP, coin purse (PP/EP/GP/SP/CP), location, activity, and action buttons. Multiple characters at the same PoI show as a stacked pin with a count badge. This replaces the need for a multi-character settlement panel — the map pins plus the entity outliner sidebar provide full visibility.

- **Alley routing:** Resolved as a player toggle (§3.3.2). Default is Streets Only. Player can toggle to Use Alleys for shorter but riskier routes. Toggle lives in the same UI area as the commuting/meandering speed toggle. The travel calculator includes or excludes alley-type edges based on this setting.

- **Encumbrance and mounts:** Resolved as NO EFFECT (§3.3.3). City movement speed is fixed at the ACKS rates (90 sec/block commuting, 1 turn/block meandering) regardless of encumbrance, mounts, or any other personal movement modifier. City travel speed is determined by congestion and city layout, not personal carrying capacity.

---

## 15. Open Questions

1. **City overview widget fidelity.** For hamlets and villages (3-25 blocks), the overview widget is simple. For Metropolis-class settlements (250+ blocks), rendering all block polygons may be too dense to be useful. Consider a simplified schematic for large cities: district blobs with labeled PoIs, rather than individual blocks.

2. **Route memory persistence.** The Navigation throw exemption system (§3.3.4) requires tracking which PoI-to-PoI routes the party has traveled and which PoIs they've visited. This data should persist in SQLite per-campaign, per-settlement. Data model: a `known_city_routes` table with (campaign_id, settlement_id, origin_poi_id, destination_poi_id) rows, and a `visited_pois` table with (campaign_id, settlement_id, poi_id) rows. Both populated automatically on arrival.
