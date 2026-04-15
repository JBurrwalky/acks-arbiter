# GDD: Dungeon Map UI & Interaction System

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Draft — requires approval before build
**Depends on:** `gdd-realtime-scheduler.md` (event scheduler architecture), `gdd-dungeon-layout.md` (cell/room/door data model), `gdd-combat-map-generation.md` (diamond grid geometry), `proficiency_system_map.md` §4 (dungeon proficiency hooks), `ax_thief_skill_update.xml` (revised thief skill throws and timings), `acore_adventures_and_encounters.xml` (door rules, search rules, encounter rules)
**Replaces:** Any existing dungeon UI stubs, hodgepodge triggers, and data wiring from prior iterations
**Blocks:** Dungeon exploration implementation, combat transition UI, dungeon-layer session runner wiring

---

## 1. Purpose

Define the complete interaction model for the dungeon map layer: how the player selects entities, issues orders, interacts with dungeon features, manages groups, and receives feedback. This document is the single authority for dungeon UI behavior. Any existing code that contradicts this document should be reworked to match.

This builds directly on `gdd-realtime-scheduler.md` §5 (Dungeon Layer). That document defines the scheduler mechanics — this document defines how the player *controls* them.

---

## 2. Input Model

### 2.1 Selection (Left Click)

**Left click on an entity (PC, henchman, NPC, monster):** Selects that entity. The entity is highlighted. Its portrait, stats, and status appear in the unit info panel. Any previous selection is cleared.

**Left click on an empty/non-entity cell:** Clears the current selection. No entity is selected. The unit info panel shows nothing (or a default "no selection" state).

**Left click on cell containing multiple entities:** Cycles through stacked entities on repeated clicks, or opens a small selection popup listing all entities in that cell.

**Shift+left click on an entity:** Adds or removes that entity from the current multi-selection without clearing existing selection.

**Double-left-click on an entity:** Selects all members of that entity's control group (if any).

### 2.2 Control Groups (Ctrl+Number)

Standard RTS control group bindings:

- **Ctrl+[1–9]:** Assign the current selection to control group N. Replaces any previous assignment for that group number.
- **[1–9]:** Select all members of control group N. Centers camera on the group's centroid if they are off-screen.
- **Double-tap [1–9]:** Select and center camera on control group N.

Control group assignments persist for the duration of the dungeon visit. They are stored per-dungeon, not globally.

### 2.3 Context Menu (Right Click)

**Right click on any cell** while at least one entity is selected: Opens a context menu at the click position. The menu is an in-window popup that persists until the player clicks an option or clicks elsewhere to dismiss it. The menu contents depend on the clicked cell and what it contains (§3).

**Right click with no selection:** Does nothing (or optionally opens a cell-inspection tooltip showing cell contents and status).

---

## 3. Context Menu System

The context menu is the primary interaction mechanism. Every right-click on a cell produces a context menu whose options are the *union* of all applicable categories: universal options (always present), environment options (based on cell features), and entity options (based on what entities occupy the target cell relative to the selected entity).

### 3.1 Universal Options (Always Present)

These four options appear on every context menu regardless of what was clicked:

| Option | Behavior |
|--------|----------|
| **Move Here** | Selected entity/group paths to the target cell. If the cell is impassable or occupied, path to the nearest reachable adjacent cell. On arrival, if destination was unreachable, log: `"<Name>: Move complete — destination unreachable."` |
| **Search Here** | Selected entity moves to the target cell (as Move Here), then performs a Search action (1 turn duration). On completion, rolls for traps and secret doors. If the character has the Tracking proficiency, also triggers a tracking roll (placeholder until tracking system is built). |
| **Listen Here** | Selected entity moves to the target cell, then performs a Listen check (1 round duration). Hear Noise throw per ACKS rules, modified by class abilities and proficiencies (Alertness: +4, Cat Burglary: +2). Thieves use their class hear noise throw; others use the base 18+ throw. |
| **Cancel** | Closes the context menu without taking any action. |

**Move Here to impassable cells:** If the player right-clicks a wall, solid rock, or otherwise impassable cell, Move Here still works — the entity paths as close as it can get, then stops. This prevents player frustration from "nothing happens" clicks. The system should never silently fail; always log the outcome.

### 3.2 Environment Options (Cell Features)

These appear based on the CellData properties of the right-clicked cell:

#### 3.2.1 Doors (cell has door_state != null)

Five distinct door actions exist. Each applies to specific door states only:

- **Force Door** — Stuck doors only. Strength throw to unstick the door without destroying it.
- **Pick Lock** — Locked doors only. Thief skill or Lockpicking proficiency.
- **Unlock** — Locked doors only. Requires the matching key in inventory.
- **Bash Door** — Any wooden door in any closed state (closed, stuck, locked). Destroys the door permanently — it cannot be closed again. Only works on wooden doors; metal and stone doors cannot be bashed.
- **Spike Shut / Wedge Open** — Any door regardless of state. Spike Shut prevents opening from the other side. Wedge Open prevents the door from closing (critical for "evil doors" that swing shut on their own).

**Evil doors (`is_evil = true`):** Evil doors automatically swing shut on every turn tick (every 60 rounds / 10 minutes) unless they are wedged open, spiked open, held by a character, bashed/destroyed, or magically held (Hold Portal, etc.). They also open freely for monsters unless spiked shut, held firm, or magically closed. The scheduler handles this: when the turn boundary event fires, all open evil doors that are not wedged or held revert to closed state. This makes Wedge Open essential for exploration in evil-door-heavy dungeons. The `DoorData` model needs an `is_evil: bool` field (default false); dungeon generation sets this per the ACKS evil door rules.

Full option table:

| Cell State | Option | Availability | Behavior |
|------------|--------|-------------|----------|
| Closed (unlocked) | **Open Door** | Always | Move to door cell, open it. Passable/LOS update. |
| Open | **Close Door** | Always | Move to door cell, close it. |
| Stuck | **Force Door** | Always | Move to door, attempt force throw (18+ modified by STR×4, cooperating ally adds +4). 1 round per attempt. Retry allowed. Does not destroy the door. |
| Locked | **Unlock** | Proper key in inventory | Move to door, unlock with key, open. |
| Locked | **Pick Lock** | Thief class or Lockpicking proficiency | Move to door, pick lock throw. 1 turn standard; 1 round at -10 penalty (-4 with Lockpicking prof). Per Axioms thief update: failure by 10+ or natural 1 breaks thieves' tools. |
| Any closed (wooden) | **Bash Door** | Any character with axe | Move to door, batter it down. Simple wooden door: 1 turn. Standard/reinforced wooden door: 3 turns. Door is destroyed and cannot be closed again. Available regardless of lock/stuck state — the party is destroying it, not opening it. |
| Any closed (metal or stone) | **Bash Door** | *(Greyed out)* | Tooltip: "This door is too strong to batter down." |
| Any closed door | **Spike Shut** | Iron spikes in inventory | Move to door, spike it shut. Spiked doors impose a penalty on force throws from the other side. Consumes 1 iron spike. Multiple spikes can be applied. |
| Spiked (own side) | **Remove Spike** | Always | Move to door, remove spike. Returns the spike to inventory. |
| Any open door | **Wedge Open** | Iron spikes in inventory | Move to door, wedge it open so it cannot swing shut. Critical for evil doors. Consumes 1 iron spike. |
| Wedged open | **Remove Wedge** | Always | Move to door, remove wedge. Returns the spike to inventory. |
| Any closed door | **Listen at Door** | Always | Move to door, listen check (1 round). Same as Listen Here but the log specifically says "listens at the door." |
| Secret (undetected) | *(No door options shown — cell appears as wall)* | — | Player must Search to find the door first. |
| Secret (detected) | **Open Secret Door** | Always | Move to cell, open the hidden mechanism. |
| Portcullis (down) | **Raise Portcullis** | STR-based throw or mechanism | Move to portcullis, attempt to raise. Throw as force door (18+ with STR modifier). Portcullises block movement but NOT line of sight. |
| Portcullis (up) | **Drop Portcullis** | If mechanism accessible | Move to mechanism, drop the portcullis. |

#### 3.2.2 Traps

| Cell State | Option | Availability | Behavior |
|------------|--------|-------------|----------|
| Trap detected (not disarmed) | **Disarm Trap** | Thief class or Find/Remove Traps proficiency | Move adjacent to trapped cell (not onto it), attempt remove traps throw. 1 turn standard; 1 round at -10 penalty. Failure by 10+ or natural 1 triggers the trap (per Axioms). |
| Trap detected (not disarmed) | **Trigger Trap (Deliberate)** | Always | Move adjacent, use a 10-foot pole or thrown object to trigger the trap from a safe distance (if available). If no safe-trigger tool, option is greyed with tooltip "Requires a 10-foot pole or ranged method." |

Undetected traps have no menu options — they are invisible to the player until found by Search or passive detection.

#### 3.2.3 Stairs

| Cell Feature | Option | Behavior |
|-------------|--------|----------|
| Stairs up | **Ascend** | Move to stair cell, transition to the connected level (or to the overworld if this is the dungeon entrance on level 1). |
| Stairs down | **Descend** | Move to stair cell, transition to the connected lower level. |
| Dungeon entrance (level 1) | **Exit Dungeon** | Move to entrance, return party to overworld at the dungeon's hex. |

#### 3.2.4 Levers, Mechanisms, and Interactable Objects

| Cell Feature | Option | Behavior |
|-------------|--------|----------|
| Lever | **Use Lever** | Move to cell, pull/push lever. Effect depends on what the lever is wired to (door, portcullis, trap, secret room, etc.). |
| Fountain, altar, statue, etc. | **Examine** | Move to cell, examine the object. May produce a description, trigger an event, or do nothing depending on stocking. |
| Locked chest/container | **Lock/Unlock** | Only available if the proper key is in inventory. Toggles the lock state. |

### 3.3 Entity Options (Target Cell Contains an Entity)

These options are *added to* the universal and environment options, never replacing them. The specific options depend on the relationship between the selected entity and the entity in the target cell.

#### 3.3.1 Target Is a Non-Hostile NPC

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Talk** | Always | Move to adjacent cell, initiate dialogue. Auto-pause. Dialogue system presents NPC reaction and conversation options. |
| **Attack** | Always | Move to adjacent cell, initiate combat with this NPC and its faction allies as hostiles. Triggers combat transition per `gdd-realtime-scheduler.md` §5.8. Warning confirmation dialog: "This will start combat with <NPC> and their allies. Proceed?" |
| **Cast Spell** | If selected entity is a caster with prepared spells | Placeholder — opens spell selection UI (deferred until spell system is built). The selected spell determines range, targeting, and whether movement is needed. |
| **Heal** | If selected entity has healing spells prepared or Healing proficiency | Move to adjacent cell, apply healing. If Healing proficiency: use the proficiency throw rules (non-magical, out-of-combat only). If healing spell: cast the spell targeting the NPC. |
| **Pick Pockets** | Thief class | Move to adjacent cell, attempt pick pockets throw. Modified by level difference per ACKS rules. On failure by half or more, the NPC notices — reaction roll at -3. May trigger combat. |

#### 3.3.2 Target Is a Hostile/Monster

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Attack** | Always | Move toward target. If in melee range, initiates combat. If combat is already active, queue attack against this target. |
| **Cast Spell** | Caster with prepared spells | Placeholder — as above. |
| **Talk** | Always (even hostiles) | Attempt to communicate. May trigger reaction roll if the creature hasn't already entered combat. Useless for non-intelligent creatures (greyed with tooltip "This creature cannot communicate"). |

#### 3.3.3 Target Is a Party Member (Not the Selected Entity)

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Cast Spell** | Caster with prepared spells | Placeholder — target the party member with a spell. |
| **Heal** | Healing spells or Healing proficiency | As §3.3.1 Heal, targeting party member. |
| **Trade** | Always | Opens a dual-inventory panel showing both characters' inventories side by side. Drag and drop items between them. Encumbrance updates in real time. Both characters must be adjacent (move together first if not). |
| **Add to Group** | Always | Adds the target character to the selected entity's control group. If the selected entity is not in a group, creates a new group containing both. |

#### 3.3.5 Target Is a Downed or Incapacitated Character

When the target cell contains a character at 0 HP or otherwise incapacitated (paralyzed, unconscious, dying from mortal wounds), these options appear in addition to the universal options. These apply to friendly AND hostile downed entities.

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Check Status** | Always | Move to adjacent cell, examine the downed character. Displays their current mortal wounds result and condition. If the selected entity has any of the following — Healing proficiency (+ healing kit/herbs), a healing potion, or healing spells prepared — a modal dialog appears asking which resource to use for a Mortal Wounds treatment. The modal lists all available options with their effects and costs. Selecting one consumes the resource and resolves the Mortal Wounds check per ACKS rules (`ax_mortal_wounds_and_tampering.xml`). If no healing resources are available, the status is displayed but no treatment can be attempted. |
| **Carry** | Always | Move to adjacent cell, pick up the downed character. The carried character becomes an **inventory item** on the carrying entity. Weight: **15 stone ± CON modifier of the carried character**, plus the weight of the carried character's inventory. The carrier's encumbrance updates immediately — this will likely reduce their movement rate significantly. A carried character can be transferred to another entity via Trade, including mounts and pack animals (mules, donkeys, horses) for exfiltration. Drop the carried character with **Drop Item** from the carrier's inventory to place them back on the ground in the current cell. |
| **Loot** | Always | Move to adjacent cell. Opens the Loot Panel (same as §3.4) showing the downed character's inventory and the selected entity's inventory side by side. Items can be transferred in either direction. This works on friendly downed characters — the primary use case is stripping gear from an incapacitated ally to reduce their carry weight before picking them up with Carry. Also works on downed enemies for standard looting. |
| **Heal** | Healing spells or Healing proficiency (with supplies) | As §3.3.1 Heal. For a downed character, this may stabilize them or restore HP depending on the healing method. Distinct from Check Status in that Heal applies healing directly, while Check Status specifically resolves the Mortal Wounds table. |
| **Cast Spell** | Caster with prepared spells | Placeholder — target the downed character with a spell (healing or otherwise). |
| **Attack** | Always | Coup de grâce. Move to adjacent cell, automatically hit the helpless target. Confirmation dialog: "This will kill `<name>`. Proceed?" For hostile downed creatures this is routine cleanup; for friendly characters it's a mercy kill or betrayal. |

**Carried character details:** A carried character is mechanically an inventory item with special properties. It occupies no specific inventory slot (it's a "carried entity" category). While carried: the character cannot act, their light sources are extinguished, their equipment remains on them (unless looted first), and their conditions continue to tick (bleeding, poison, etc.). If the carrier enters combat, the carried character does NOT participate — they remain inert inventory. If the carrier is themselves downed, the carried character is dropped in the same cell.

#### 3.3.6 Target Is the Selected Entity Itself (Self-Actions)

Right-clicking the cell occupied by the currently selected entity produces self-targeting options:

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Hide** | Thief class, Hide in Shadows proficiency, or equivalent class ability | All selected entities (and all members of the selected entity's group) that are capable of hiding attempt a Hide in Shadows throw in their current cells. No movement occurs. Characters that succeed are hidden; those that fail believe they succeeded until an enemy reacts (per ACKS rules). Hidden characters remain hidden only while motionless. |
| **Light Torch** | Torch AND tinderbox in inventory | Lights a torch. Creates a `light_source_expired` event in the scheduler at +6 turns. Updates light radius around entity. Consumes 1 torch from inventory (the lit torch is now tracked as "equipped light source"). |
| **Light Lantern** | (Charged lantern + tinderbox) OR (empty lantern + oil flask + tinderbox) | Lights or refills and lights a lantern. Creates `light_source_expired` event at +24 turns per flask. If lantern was empty, consumes 1 oil flask. |
| **Extinguish Light** | Currently carrying a lit torch or lantern | Puts out the current light source. Torch is consumed (cannot be relit). Lantern retains remaining oil for relighting. |
| **Heal** | Healing spells prepared or Healing proficiency | Self-heal. |
| **Cast Spell** | Caster with prepared spells and self-targeting spells available | Placeholder — self-targeted spell selection. |
| **Use Item** | Consumable items in inventory (potions, scrolls) | Opens a quick-select list of usable items from inventory. Using an item takes 1 round (or as specified by the item). |
| **Set Default Idle Behavior** | Always | Opens the Default Idle Behavior submenu (§4). |
| **Drop Item** | Items in inventory | Opens inventory panel, select item(s) to drop on the current cell. Creates a loot pile if one doesn't exist. |

**Note:** Right-clicking a cell containing an in-group entity (a member of the selected entity's control group) also shows **Hide** at the top of the entity options. This triggers the same group-wide hide behavior — all capable group members attempt to hide in their current cells, no movement.

### 3.5 Stealth Move and Hide

Stealth is a compound action with two forms depending on what cell is right-clicked:

#### 3.5.1 Stealth Move (Right-Click Distant Cell)

When the right-clicked cell is NOT the selected entity's cell and NOT occupied by an in-group member:

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Stealth Move** | At least one selected entity has Move Silently capability (thief class, Skulking proficiency, or equivalent) | Selected entity moves to the target cell using Move Silently (throw per ACKS rules; half combat speed = no penalty, faster = -5, running = -10). On arrival, the entity automatically attempts a Hide in Shadows throw at the destination cell. **Group behavior:** If a control group is selected, all members with Move Silently capability attempt silent movement; members without it move normally (and likely break stealth for the group). The group leader arrives at the target cell; other members occupy adjacent cells. On arrival, all capable members attempt Hide in Shadows in their respective cells. |

The Move Silently throw is made at the start of movement. The character always believes they succeeded until enemies react (per ACKS rules — the result is hidden from the player). The Hide in Shadows throw at the destination is also hidden — the character believes they are hidden until proven otherwise.

#### 3.5.2 Hide in Place (Right-Click Own Cell or In-Group Cell)

When the right-clicked cell is the selected entity's own cell or contains a member of the selected entity's control group:

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Hide** | At least one group member has Hide in Shadows capability | All members of the group that are capable of hiding attempt a Hide in Shadows throw in their current cells. No movement occurs. Non-capable members simply hold position. |

This distinction — Stealth Move for distant targets, Hide for current position — keeps the context menu clean. The player never has to manually sequence "move silently then hide"; the system handles the compound action.

### 3.4 Loot and Containers

When the right-clicked cell contains items on the ground or an opened/unlocked container:

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Loot** | Always | Move to cell if not adjacent. Opens the Loot Panel: two-pane view showing the loot pile or container contents on the left and the selected character's inventory on the right. Drag and drop items between them. Encumbrance updates live. The player can also deposit character items into the container/pile. Close the panel when done. |
| **Pick Up All** | Items on ground | Move to cell, automatically transfer all items to selected character's inventory (up to encumbrance limit). Overflow items remain on the ground with a log message: `"<Name>: Cannot carry any more."` |

---

## 4. Default Idle Behavior System

Each entity has a configurable **default idle behavior** that determines what it does when it has no active orders and is not in combat. This significantly reduces micromanagement for parties with many members.

### 4.1 Available Idle Behaviors

| Behavior | Description |
|----------|-------------|
| **Hold Position** (default) | Stay in current cell. Do nothing. Wait for orders. |
| **Follow Group Lead** | If in a control group, follow the unit at position 1 in the marching order. Maintain formation spacing. Match the lead unit's movement mode. If not in a group, behaves as Hold Position. |
| **Auto-Listen at Doors** | When adjacent to a closed door (and idle), automatically perform a Listen check. Results appear in the log. Does not open the door. |
| **Auto-Search** | When entering a new room (and idle), automatically begin a Search action on the room. Warning: this is slow (1 turn per 10'×10') and loud — not recommended for stealth-oriented play. |
| **Guard** | Hold position. If a hostile enters the entity's awareness radius (based on light and line of sight), auto-pause and flag the threat. Does not auto-attack — just alerts. |
| **Hide** | If the entity has Hide in Shadows capability, attempt to hide in the current position. Remain hidden and motionless until given orders or until hiding is broken. |

### 4.2 Setting Idle Behavior

Idle behavior is set via:

1. **Context menu → Set Default Idle Behavior** (self-action, §3.3.6) — opens a submenu listing the available behaviors. Some are greyed out if the entity lacks prerequisites (e.g., Hide requires thief class or relevant proficiency).
2. **Group options panel** (right-click the control group icon in the control bar, §5.2) — set idle behavior for all members of a group simultaneously.

Idle behavior persists until changed. It is stored per-entity for the duration of the dungeon visit.

### 4.3 Follow Group Lead (Detail)

This is the most common idle behavior for henchmen and non-PC party members. When set:

- The entity follows the group's marching order position behind the entity ahead of it.
- Movement speed matches the group's speed (slowest member, per §5.3).
- If the lead unit stops, followers stop in column formation behind it.
- If the lead unit enters combat, the follower's idle behavior is suspended — they enter combat and act per their combat AI or player control.
- If the lead unit performs a non-movement action (search, listen, pick lock), followers wait in their current positions until the lead resumes moving.

---

## 5. Control Bar and Group Management UI

### 5.1 Unit Info Panel

A panel (bottom-left or left sidebar) showing details for the currently selected entity:

- Portrait (from the character portrait system: 256×256 PNG)
- Name
- Class and level
- HP (current / max, with color coding: green > 50%, yellow 25-50%, red < 25%)
- AC
- Current action and progress (e.g., "Searching... 4/10 min" or "Moving" or "Idle")
- Movement mode indicator (Exploration / Combat Speed / Running)
- Active light source and remaining duration
- Active conditions (poisoned, paralyzed, blessed, etc.)
- Encumbrance tier indicator

When multiple entities are selected, show a compact multi-portrait view with HP bars only. Click any portrait to drill into that entity's full detail.

### 5.2 Control Group Bar

A horizontal bar (bottom of screen) showing numbered slots [1] through [9]. Each slot shows:

- The group number
- A compact portrait mosaic of group members (2-4 tiny portraits, or a count badge if more than 4)
- A colored pip for the group's movement mode (green = exploration, yellow = combat speed, red = running)
- A dimmed/brightened state for idle vs. active

**Left click a group slot:** Selects all group members.
**Double-click a group slot:** Selects and centers camera.
**Right-click a group slot:** Opens the Group Options Panel:

- **Marching Order** — opens a drag-and-drop reorderable list of group members. Top = front, bottom = rear. Drag to rearrange. The front unit encounters traps, doors, and enemies first. Typical arrangements: thief-front (for trap detection), highest-AC-front (for combat), caster-rear.
- **Movement Mode** — toggle between Exploration / Combat Speed / Running for the entire group.
- **Set All Idle Behavior** — set the default idle behavior for all group members at once.
- **Disband Group** — remove the control group assignment. Members become ungrouped individuals.

### 5.3 Movement Speed Rules

Group movement speed is **always set by the slowest member.** This is calculated from:

- Base movement rate (class/race dependent)
- Encumbrance tier (per the existing EncumbranceCalculator)
- Movement mode multiplier:
  - Exploration: ×1/3 of combat speed
  - Combat speed: ×1 (the base movement rate)
  - Running: ×2 combat speed
- Proficiency modifiers: Running proficiency adds +30' to base movement (only in combat speed or running mode)

The control group bar shows the effective group speed so the player can see the impact of their slowest member.

### 5.4 Marching Order Behavior

Marching order is per-group and determines:

- **Column formation in corridors:** In 5'-wide corridors, units line up single-file in marching order. In 10'-wide corridors, they can travel two abreast (positions 1-2 side by side, then 3-4, etc.).
- **First contact:** The unit at position 1 in the marching order is the first to encounter traps, doors, and enemies when the group moves into unexplored space.
- **Split responsibility:** If the first unit has a passive detection ability (e.g., dwarf), those checks fire as the group advances. If the second unit has a different passive (e.g., elf), both passives fire for cells within their detection radius.

---

## 6. Fog of War and Visibility

### 6.1 Visibility States

Each cell has one of three visibility states:

| State | Rendering | Information |
|-------|-----------|-------------|
| **Hidden** | Black / fully obscured | Player cannot see or interact with this cell. No context menu except the universal options (Move Here will path toward it but stop at the fog boundary). |
| **Explored** | Dimmed / desaturated | Previously visited. Walls, doors, and room shapes visible. Entities and items NOT visible (things may have changed since last visit). |
| **Visible** | Fully lit/rendered | Currently within a party member's line of sight AND within their light source radius (or darkvision range). Entities, items, and real-time status visible. |

### 6.2 Revelation Rules

- **Room-scoped reveal:** When any party member enters a room (crosses a door threshold or enters from a corridor), the entire room becomes Visible (per existing design from `gdd-dungeon-layout.md`). When all party members leave the room, it transitions to Explored.
- **Corridor reveal:** Corridors reveal cell-by-cell based on line of sight and light radius. A character with a torch reveals cells within 30' (6 cells) in their LOS cone. A character with a lantern reveals within 30' (same radius, but 360° instead of directional).
- **Darkvision:** Characters with darkvision (elves, dwarves, etc.) reveal cells within 60' (12 cells) even without a light source, rendered in a distinct grayscale/monochrome visual style to indicate darkvision rather than true light.

### 6.3 Context Menu Interaction with Fog

- **Hidden cells:** Right-click produces only Move Here, Search Here, Listen Here, and Cancel. The entity will path toward the cell and stop at the boundary of explored/visible space.
- **Explored cells:** Right-click shows universal options plus any environment options based on remembered cell data (doors, stairs). But entity options are suppressed — you can't see who's there, so no Talk/Attack/etc. Warning: remembered data may be stale (a door you left open might now be closed by monsters).
- **Visible cells:** Full context menu with all applicable options.

---

## 7. Notification Log

### 7.1 Purpose

A scrolling text log (bottom-right or dedicated panel) that shows all mechanical events and outcomes during dungeon exploration. This is the player's primary feedback channel for actions that resolve in the background (while the clock is ticking).

### 7.2 Log Entry Types

| Category | Example | Color/Styling |
|----------|---------|---------------|
| **Movement** | "Bran moves to (15, 22)." | Default/white |
| **Action result (success)** | "Yara: Search complete — found a hidden door!" | Green |
| **Action result (failure)** | "Bran: Force door — failed (rolled 8 vs. target 18)." | Yellow |
| **Detection (passive)** | "Thorgrim senses a sloping passage ahead." | Cyan |
| **Trap trigger** | "Bran triggers a pit trap! (Save vs. Blast — failed, 6 damage)" | Red |
| **Encounter** | "Wandering monster check: 3 goblins appear 40' to the south!" | Red, bold |
| **Resource depletion** | "Yara's torch has burned out." | Orange |
| **Combat transition** | "Combat begins! All units enter turn-based mode." | Red, bold |
| **Unreachable** | "Bran: Move complete — destination unreachable." | Grey |
| **Item** | "Yara picks up: Potion of Healing." | White |

### 7.3 Log Behavior

- Auto-scrolls to newest entry.
- Player can scroll up to review history.
- Clicking a log entry that references a location centers the camera on that cell.
- Log persists for the duration of the dungeon visit. Saved to the session log for post-session review.
- Log entries with associated dice rolls show the full roll detail on hover/click (die type, raw result, modifiers with sources, final result, outcome).

---

## 8. Camera Controls

### 8.1 Movement

- **Arrow keys / WASD:** Pan the camera across the dungeon map.
- **Mouse-to-edge:** When the mouse cursor reaches the screen edge (within 40px margin), the camera pans in that direction (matching existing hex map behavior from the hex map renderer).
- **Middle mouse drag:** Click and drag to pan freely.
- **Click minimap:** Jump to the clicked location. See §8.4 for minimap rules.

### 8.2 Zoom

- **Mouse scroll wheel:** Zoom in/out. Zoom range TBD per the diamond grid tile size, but should support close enough to see individual cell detail and far enough to see a large room or corridor complex.
- **Home key:** Reset zoom and center on the selected entity (or the first PC if nothing is selected).

### 8.3 Camera Follow

An optional toggle (default: on for single-entity selection, off for multi-selection): the camera automatically pans to follow the selected entity or group as they move. The player can break follow mode by manually panning; it re-engages when a new selection is made or when the player presses the Home key.

### 8.4 Minimap

The minimap is a small overlay (top-right corner, toggleable with **M** key) showing a top-down schematic of the dungeon.

**What the minimap always shows:** Currently visible cells (cells within LOS and light radius of any party member right now). These appear as lit floor/wall shapes on the minimap in real time.

**Automapping (requires Mapping proficiency + supplies):** If at least one party member has the Mapping proficiency AND has a journal (or parchment) AND ink in their inventory, the minimap retains explored cells even after they leave LOS. The automap fills in as the party moves in **exploration movement mode only** — combat speed and running mode do not produce automap data (the mapper can't draw while sprinting). Cells explored without a mapper present, or explored while not in exploration mode, are NOT retained on the minimap once they leave LOS.

**Without a mapper:** The minimap is live-only. It shows what party members can see right now and nothing else. Previously visited areas disappear from the minimap when the party moves away. The main viewport's fog of war still shows explored cells in their dimmed "Explored" state (§6.1), but the minimap does not.

**Minimap interaction:** Click on the minimap to jump the main camera to that location (automapped areas only). The minimap does not show entity positions other than the player's party (no enemy tracking on the map).

---

## 9. Action Queuing and Interruption

### 9.1 Single Action Queue

Each entity has a single-slot action queue: one current action (in progress) and one pending next action. If the player issues a new order while an action is in progress:

- **Move orders:** The entity immediately redirects. Current movement is abandoned; new pathfinding begins.
- **Non-move actions (search, pick lock, listen, etc.):** The current action is interrupted and lost (no partial credit — ACKS doesn't have partial search progress). The new action begins.
- **Queue stacking:** Only one pending action is supported. More complex sequences (e.g., "move here, then search, then move there") are not queued — the player issues each order as the previous one completes. This keeps the system simple and predictable.

### 9.2 Group Orders

When a control group is selected and the player issues an order:

- **Move Here:** All group members path to the target area, maintaining marching order. The front unit paths to the target cell; others queue behind in formation.
- **Search Here / Listen Here:** The front unit (position 1 in marching order) performs the action. Others hold position and wait. If the player wants a specific member to search, they must select that individual.
- **Door interactions:** The front unit (or the most appropriate unit — thief for Pick Lock) performs the interaction. Others hold position.

---

## 10. Data Requirements

### 10.1 Data the Dungeon Map UI Consumes

| Data | Source | Used For |
|------|--------|----------|
| `DungeonLayout` (grid, cells, rooms, doors, stairs) | `gdd-dungeon-layout.md` output | Rendering the map, determining valid context menu options |
| `CellData.door_state` | DungeonLayout cells | Door option availability |
| `CellData.door_detected` | DungeonLayout cells | Whether secret doors show as walls or doors |
| `DoorData.type` and door material | DungeonLayout doors | Bash availability (wooden only), force/pick lock availability, visual style |
| `CellData.passable` | DungeonLayout cells | Pathfinding, move validity |
| `CellData.terrain_feature` | DungeonLayout cells | Visual rendering, action availability |
| `CellData.blocks_los` | DungeonLayout cells | Line-of-sight and fog of war calculations |
| Entity positions (Array of entity_id → Vector2i) | Game state | Where to draw entities, what options to show |
| Entity data (class, level, HP, inventory, proficiencies) | CharacterData / shared types | What context menu options are available per entity |
| Trap data (detected traps, trap type, trap location) | Dungeon stocking data | Disarm Trap option availability, trigger trap option |
| Light sources (who has what lit, remaining duration) | Scheduler events + entity state | Visibility radius, torch/lantern menu options |
| Control group assignments | In-memory Dictionary (group_number → Array[entity_id]) | Group bar display, group selection |
| Marching order per group | In-memory Dictionary (group_number → Array[entity_id]) | Formation movement, first-contact determination |
| Idle behavior per entity | In-memory Dictionary (entity_id → IdleBehavior enum) | Idle behavior execution |

**Note on door material and evil doors:** The Bash Door action requires knowing whether a door is wooden, metal, or stone. The existing `DoorData.type` in `gdd-dungeon-layout.md` §11 tracks door *function* (arch, unlocked, locked, trapped, secret, portcullis) but not *material*. A `door_material` field (values: `"wood_simple"`, `"wood_standard"`, `"wood_reinforced"`, `"iron"`, `"stone"`) should be added to `DoorData` or to the cell's terrain_feature encoding. This determines: whether Bash is available, how many turns Bash takes (1 for simple wood, 3 for standard/reinforced wood, unavailable for iron/stone), and the visual style of the door. Additionally, an `is_evil: bool` field (default false) is needed on `DoorData` to drive the evil door auto-close scheduler event (§3.2.1).

### 10.2 Data the Dungeon Map UI Produces / Modifies

| Action | Data Change | Persisted? |
|--------|------------|------------|
| Move order | Inserts movement events into scheduler | Scheduler (in-memory) |
| Open/close/force door | Modifies `CellData.door_state`, `CellData.passable`, `CellData.blocks_los` | Yes (SQLite via CampaignRepository) |
| Search result (find secret door) | Modifies `CellData.door_detected` to true | Yes |
| Search result (find trap) | Updates trap detection state | Yes |
| Disarm trap | Removes or disables trap data on cell | Yes |
| Spike door | Adds spike state to door cell | Yes |
| Light torch/lantern | Inserts `light_source_expired` event, updates entity light state | Scheduler + entity state |
| Control group assignment | Updates group dictionary | Per-dungeon session (not persisted to DB) |
| Marching order change | Updates marching order dictionary | Per-dungeon session |
| Idle behavior change | Updates idle behavior dictionary | Per-dungeon session |
| Loot pickup/drop | Modifies entity inventory and cell item list | Yes (SQLite) |
| Trade between characters | Modifies both entities' inventories | Yes (SQLite) |
| Item use (potion, scroll) | Modifies inventory, applies effect | Yes (SQLite) |
| Carry downed character | Adds carried entity as inventory item on carrier; recalculates encumbrance | Yes (SQLite) |
| Drop carried character | Removes carried entity from carrier inventory; places entity in current cell | Yes (SQLite) |
| Check Status / Mortal Wounds treatment | Consumes healing resource; resolves mortal wounds table; updates downed entity condition | Yes (SQLite) |
| Bash door (destroy) | Sets door cell to permanently open/destroyed state; `passable = true`, `blocks_los = false`, door cannot be closed | Yes (SQLite) |

---

## 11. Flagged Missing or Deferred Items

Items I've identified as potentially missing from the spec or deferred for future systems:

### 11.1 Present but Deferred

- **Cast Spell:** Placeholder throughout. The full spell system interaction (spell selection UI, targeting, range checking, component consumption) is deferred until the spell system is built. The context menu shows the option and opens a "not yet implemented" placeholder.
- **Tracking proficiency in Search:** Search Here includes a tracking roll trigger, but the tracking system is not yet built. Placeholder hook only.
- **NPC Dialogue system:** Talk opens a dialogue — but the dialogue system itself is a separate GDD/build item. The context menu just triggers the entry point.

### 11.2 Additions Worth Considering

- **Climb Walls (thief):** Thieves and characters with Climbing proficiency can climb walls to reach elevated areas (balconies, ledges). This requires an elevation-aware context menu option: right-click an elevated cell → "Climb Here" (thief climb walls throw, 1 round per 10' of height). Deferred until elevation gameplay is implemented in the dungeon layer. Placeholder hook recommended.
- **Rest / Short Rest:** The party may want to rest inside the dungeon. Add a self-action **Rest** that consumes time (1 turn for a short break, or hours for actual sleep). Risk: wandering monster checks continue during rest. This is a party-level action, not individual.
- **Formation selection per group:** Formation options (column, line, wedge, circle) for groups in open rooms are part of the intended design and should be present — not deferred. Column is the default and only option in corridors. In rooms wide enough to support it, line and wedge become available. The group options panel (§5.2) already specifies a formation submenu. If formation code exists in the codebase but isn't exposed in the UI, it needs to be wired up. If it doesn't exist yet, it should be built with the group management system.

### 11.3 Edge Cases to Handle

- **Selecting an entity in a Hidden cell:** Not possible — entities in hidden cells are invisible. The player can't left-click what they can't see.
- **Right-clicking while the game is unpaused:** The context menu auto-pauses the game when it opens, and unpauses (at the current speed setting) when it closes or an action is selected. This prevents the world from ticking while the player is reading options.
- **Multiple entities want to use the same door simultaneously:** Queue them. The first entity in the group's marching order interacts with the door; others wait in adjacent cells. Once the door is open, they pass through in order.
- **Entity dies during an action:** If an entity dies (HP reaches 0) while performing a queued action (e.g., disarming a trap and it triggers), the action is abandoned. The entity enters the mortal wounds flow. The action queue is cleared.
- **Right-clicking while a context menu is already open:** Closes the old menu and opens a new one at the new click position.
- **Bash vs. Force — distinct actions, distinct rules:** Force Door is a strength throw that unsticks a stuck door without destroying it. Bash Door destroys any wooden door regardless of its state (closed, stuck, locked) but takes longer and permanently removes the door. Both may be available on the same stuck wooden door — let the player choose. Force is faster (1 round) but may fail; Bash is guaranteed but takes 1-3 turns and is noisy. Pick Lock and Unlock are locked-door-only options and never appear on stuck or ordinary closed doors.

---

## 12. Build Guidance for Claude Code

### 12.1 What to Build

1. **Context menu scene** — a Godot PopupMenu or custom PanelContainer that appears at right-click position, populated dynamically from cell and entity data. Must be its own scene for reuse.
2. **Context menu builder** — a function that takes (selected_entity, target_cell, dungeon_data) and returns a list of menu options. Each option has: label, icon (optional), enabled/disabled state, tooltip for disabled items, and a callback or action identifier.
3. **Selection system** — left-click selection, shift-click multi-select, control group hotkeys. Stores current selection as an Array of entity IDs.
4. **Control group bar scene** — the horizontal bar at the bottom showing group slots.
5. **Group options panel** — the right-click popup for group configuration (marching order, movement mode, idle behavior).
6. **Unit info panel scene** — the detail view for the selected entity.
7. **Loot panel scene** — dual-pane inventory view for looting and trading.
8. **Notification log** — scrolling text panel with categorized, colored entries.
9. **Idle behavior system** — per-entity behavior state machine that ticks each scheduler cycle when the entity has no active orders.

### 12.2 What to Rework

- **Any existing dungeon UI stubs:** Remove or gut them. This document is the new authority. If code exists for a different interaction model (e.g., click-to-move with no context menu, or turn-based action panels), it should be replaced.
- **Any existing data stubs that don't match §10:** Ensure CellData has all required fields (`door_state`, `door_detected`, `passable`, `blocks_los`, `terrain_feature`). The DungeonLayout schema from `gdd-dungeon-layout.md` §11 already defines these — verify they're implemented as specified.
- **Fog of war:** If an existing fog system exists, verify it matches §6 (three-state: Hidden/Explored/Visible, room-scoped reveal). Rework if it uses a different model.

### 12.3 What Stays the Same

- **Diamond grid geometry:** `gdd-combat-map-generation.md` §3. No changes.
- **DungeonLayout data model:** `gdd-dungeon-layout.md` §11. No structural changes. The UI *reads* this data; it doesn't change the schema.
- **Pathfinding:** Godot's `AStarGrid2D` or equivalent. The context menu issues pathfinding requests; the pathfinding implementation is not this document's concern.
- **EventScheduler:** `gdd-realtime-scheduler.md`. The UI creates scheduled events by calling the scheduler API. The scheduler is not modified.
- **Timekeeping autoload:** No changes. Actions that consume time (search, pick lock, etc.) call the scheduler, which calls Timekeeping.

### 12.4 Integration with the Event Scheduler

Every player action from the context menu translates to one or more scheduled events:

| Player Action | Scheduler Event(s) |
|--------------|-------------------|
| Move Here | `travel_step` events per cell along the path |
| Search Here | `travel_step` to destination + `search_complete` at +1 turn |
| Listen Here | `travel_step` to destination + `listen_complete` at +1 round |
| Force Door | `travel_step` to door + `force_door_attempt` at +1 round (repeat on failure) |
| Pick Lock | `travel_step` to door + `pick_lock_complete` at +1 turn (or +1 round with rapid attempt) |
| Unlock (key) | `travel_step` to door + immediate state change (no time cost beyond movement) |
| Bash Door | `travel_step` to door + `bash_door_complete` at +1 or +3 turns based on door material |
| Spike Shut / Wedge Open | `travel_step` to door + `spike_complete` at +1 round |
| Stealth Move | `stealth_travel_step` events per cell (Move Silently throw at start) + `hide_attempt` on arrival |
| Hide | `hide_attempt` immediate for all capable group members (no movement events) |
| Light Torch | Immediate state change + `light_source_expired` at +6 turns |
| Talk | `travel_step` to adjacent cell + `dialogue_start` (immediate on arrival) |
| Check Status | `travel_step` to adjacent cell + `mortal_wounds_check` (immediate, opens modal if resources available) |
| Carry | `travel_step` to adjacent cell + immediate: downed entity becomes inventory item on carrier, encumbrance recalculated |
| Loot (downed) | `travel_step` to adjacent cell + immediate: opens loot panel (same as §3.4) |
| *(System)* Evil door auto-close | `evil_door_close` fires on every turn boundary (60-round tick) for all open evil doors not wedged/held |

The UI never directly advances time or modifies game state — it always goes through the scheduler.
