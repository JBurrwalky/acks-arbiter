# GDD: Dungeon Map UI & Interaction System

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Draft v2 — Architecture refresh (2026-04-30)
**Authority:** Subordinate to `gdd-ui-architecture.md`. Authoritative on dungeon-context interaction patterns (selection, context menus, action options, queued orders, idle behaviors, multi-level UX). NOT authoritative on the spatial substrate (voxel grid), the event scheduler, the management notebook, the unified log, or party-formation surfaces — those are owned by their respective GDDs and consumed here.
**Depends on:**
- `gdd-voxel-tactical-architecture.md` v1.1 — 5' cube voxel grid, `Vector3i` coordinates, 3D Chebyshev adjacency, multi-level camera/occlusion (focus level, Level Strip Widget, dither/dim/hide), fog-of-war model
- `gdd-realtime-scheduler.md` — EventScheduler, SchedulerLoop, DungeonOrderManager order lifecycle, renderer-tween movement layer, cell-arrival signal, claim-based occupancy
- `gdd-dungeon-layout.md` — `DungeonLayout` / `VoxelMapData` data model, `DoorData` (`door_material`, `is_evil`, `door_state`, `door_type`, `door_detected`)
- `gdd-ui-architecture.md` v2.10 — surface taxonomy, keybind reservations, cross-surface activation
- `gdd-management-notebook.md` v1.5 — Character tab activation seam, Inventory tab as canonical inventory surface
- `gdd-unified-log-panel.md` v2 — replaces the standalone notification log
- `gdd-party-tab.md` v1.4 — marching order and Formation sub-tab (Wilderness 6×12, Dungeon 2×12)
- `gdd-combat-ui.md` — sibling under the One-Grid-Two-Modes framework
- `acore_adventures_and_encounters.xml` — door rules, search rules, encounter rules
- `ax_thief_skill_update.xml` — revised thief skill throws and timings

**Modifiable:** Yes (project-designed)

---

## 1. Purpose and scope

This GDD specifies the **dungeon-context interaction surface**: how the player selects entities, opens context menus on cells, issues queued orders, configures idle behaviors, and moves the camera within the dungeon presentation layer. It is the interaction-pattern complement to the voxel architecture's spatial substrate and the realtime scheduler's event/movement model.

### 1.1 What this GDD owns

- Selection model (left-click, shift-click, control groups)
- Right-click context menu structure and option vocabulary
- Per-cell-feature option families (doors, stairs, traps, interactables, loot)
- Per-entity-target option families (NPC, party member, downed character, self)
- Stealth-move-vs-hide-in-place compound action
- Default Idle Behavior system
- Action queuing semantics (single-slot per entity, cancellation flow)
- Dungeon-context camera controls including multi-level focus interactions

### 1.2 What this GDD points to (no longer owns)

The v1 draft of this GDD owned several surfaces that the current architecture has centralized elsewhere. v2 cuts them and replaces each with a one-line pointer:

| Former v1 scope | Now lives in |
|---|---|
| Unit Info Panel (per-selection portrait/stats) | `gdd-ui-architecture.md` §3.8 (SessionStatusBar portraits) + `gdd-character-tab.md` (full sheet) |
| Notification Log (standalone scrolling panel) | `gdd-unified-log-panel.md` v2 (HUD zone in SessionStatusBar's right column) |
| Group Options Panel — Marching Order section | `gdd-party-tab.md` v1.4 §6 (Formation sub-tab — Wilderness 6×12, Dungeon 2×12 grids) |
| Standalone Loot Panel (dual-pane modal) | `gdd-inventory-tab.md` (carrier-aware inventory; loot interactions surface here) |
| Standalone Trade Panel | `gdd-inventory-tab.md` + the carriers-only adjacency rule from `gdd-voxel-tactical-architecture.md` §5 |
| Spatial model (cells, adjacency, fog, multi-level) | `gdd-voxel-tactical-architecture.md` §6, §15, §16 |
| Movement order lifecycle, scheduling, occupancy | `gdd-realtime-scheduler.md` §3, §6 |

### 1.3 Design principles

- **Diamond grid + isometric, but operating on a 3D voxel substrate.** Every cell coordinate is `Vector3i(col, row, level)`. Every adjacency check uses 3D Chebyshev ≤ 1.
- **Right-click is the action verb.** Left-click is selection only (parity with combat-ui §4 commits this for combat too).
- **The context menu is generated, not authored.** A pure-logic builder consumes game state and emits an option list. UI renders the list. No menu logic in scenes.
- **Action durations come from ACKS rules.** The scheduler holds the canonical durations (`gdd-realtime-scheduler.md` §6.5).
- **One adjacency predicate, one occupancy rule.** Both come from the voxel architecture and the scheduler — the dungeon UI does not redefine them.

---

## 2. Spatial substrate (consumed, not redefined)

This GDD does not specify the spatial model. The relevant authorities and their predicates:

- **Coordinates:** `Vector3i(col, row, level)` per `gdd-voxel-tactical-architecture.md` §6.2. Legacy `Vector2i` callers are deprecated and being migrated.
- **Adjacency:** `VoxelGrid.is_adjacent(a, b)` returns true iff 3D Chebyshev distance ≤ 1 (the 26 cells surrounding any cell). Used uniformly for melee engagement, inventory transfer, door interaction, "must be next to target" gating. Voxel arch §16.9.
- **Pathfinding:** `MovementResolver.path_bfs_3d(start, goal, "ground", max_steps, max_level_jumps, "explore")` for level-spanning paths; same-level BFS via `VoxelGrid.get_neighbors_2d` for short paths. Explore mode permits closed unlocked doors (the executor pauses one round at the door cell to swing it open).
- **Cell occupancy:** Claim-based collision per `gdd-realtime-scheduler.md` §6.4 (settled and smoke-tested 2026-04-30). At most one entity per cell at any time. When two orders target the same cell, the second-claimer's order converts to `wait`.
- **Fog of war:** Three states per cell — `hidden` / `explored` / `visible`. Light-source + LOS based (B5+); NOT room-scoped. Per-cell fog state stored on the `VoxelCell`. Voxel arch §15.

The dungeon UI consumes these. It does not define alternative versions.

---

## 3. Input model

### 3.1 Selection (left-click)

| Action | Behavior |
|--------|----------|
| Left-click on entity | Select that entity. Previous selection cleared. SessionStatusBar portrait reflects the new active entity. |
| Left-click on empty/non-entity cell | Clear current selection. |
| Left-click on cell with multiple stacked entities | Cycle through stacked entities on repeated clicks; if more than two, surface a small disambiguation popup. |
| Shift+left-click on entity | Toggle that entity in the multi-selection without clearing existing selection. |
| Double-left-click on entity | Select all members of that entity's control group (if any). |

**Single-selection vs. multi-selection:** When a single entity is selected, the context menu's self-actions and entity-options refer to that entity. When multiple entities are selected, options that are per-entity (Hide, Light Torch, etc.) apply to all members of the selection that are individually capable; gating is "any selected has the capability" with per-entity execution at issue-time.

**Cross-tab activation seam:** Left-click on an entity in the dungeon view sets the global active entity for the management notebook (via `EventBus.notebook_active_entity_requested(entity_id)` per `gdd-management-notebook.md` §8.4). It does NOT auto-open the notebook — that requires the player's explicit action (clicking a SessionStatusBar portrait, pressing C, etc.).

### 3.2 Control groups

Standard RTS control group bindings, scoped to dungeon and combat contexts:

| Input | Action |
|-------|--------|
| Ctrl+[1–9] | Assign current selection to control group N. Replaces any previous assignment. |
| [1–9] | Select all members of control group N. Centers camera on the group's centroid if off-screen. |
| Double-tap [1–9] | Select and center camera. |
| 0 | Reserved (currently unassigned). |

**Keybind 1-4 collision with clock-speed.** Per `gdd-ui-architecture.md` §4.1, keys 1-4 are reserved for clock-speed (Pause / 1× / 2× / Max) AND 0-9 for control groups. The two are reconciled by gameplay context: in `DUNGEON_EXPLORE`, number keys are control-group recall; clock-speed in dungeon context is exposed via the SessionStatusBar speed cluster (mouse) and `Space` for toggle-pause. This is currently implemented; if usability surfaces a regression, an alternative is binding clock-speed to F1-F4 in dungeon context.

Control group assignments persist for the duration of the dungeon visit only — they are stored in `DungeonSessionState`, not in the campaign repository.

### 3.3 Right-click context menu

Right-click on any cell while at least one entity is selected opens an in-window popup at the click position. The menu auto-pauses the scheduler on open and resumes (at the previously-set speed) when an option is selected or the menu is dismissed. Right-click with no selection is a no-op (or, optionally, opens a cell-inspection tooltip — implementation choice).

The menu is generated by `DungeonContextMenuBuilder.build_menu(selected_ids, target_cell, map, party_data, session_state, light_manager)`. The builder is pure logic — no scene nodes, no signals, no side effects. It returns `Array[Dictionary]` of option entries:

```
{
  id: String,                # stable identifier
  label: String,             # display text
  enabled: bool,             # greyed out when false
  tooltip: String,           # disabled-state explanation or hint
  category: String,          # "universal" | "environment" | "entity" | "self"
  action_data: Dictionary    # { action_type: String, ...payload }
}
```

The UI renders the list, dispatches the chosen option's `action_data` to the corresponding handler, and dismisses the menu. The builder is tested in isolation; the renderer carries no decision logic.

---

## 4. Context menu options

The full menu is the union of the four categories below. Categories appear in display order: universal, then environment, then entity, then self (where applicable).

### 4.1 Universal options (always present)

| Option | Behavior |
|--------|----------|
| **Move Here** | Selected entity/group paths to the target cell. Path computed in mode `"explore"`. Closed unlocked doors are walkable in this mode (the executor pauses one round at the door cell to open it). If the target is impassable or unreachable, the path resolves to the closest reachable cell; the unified log records `"<Name>: Move complete — destination unreachable."` |
| **Search Here** | Selected entity moves to the target cell (Move Here, then) and performs a Search action (1 turn). On completion, `_resolve_search` routes through `ThiefSkillResolver` per `gdd-realtime-scheduler.md` §6.6 — best applicable target across General (18+), Elf active (8+ for hidden/secret doors), Dwarf active (14+ for stonework), thief class throw, or proficiency-equivalent. Per ACKS, each character gets ONE chance per location. |
| **Listen Here** | Selected entity moves to the target cell and performs a Listen check (1 round). Hear Noise throw via `ThiefSkillResolver`. |
| **Cancel** | Close the context menu without taking any action. |

### 4.2 Environment options (cell features)

Built by `_build_door_options`, `_build_stair_options`, `_build_trap_options`, `_build_interactable_options`. Suppressed when the target cell's fog state is `hidden`.

#### 4.2.1 Doors

`DoorData` carries `door_material` ∈ {`wood_simple`, `wood_standard`, `wood_reinforced`, `iron`, `stone`} and `is_evil: bool`. `DungeonSessionState` tracks `is_spiked(cell)`, `is_wedged(cell)`, `is_held_open(cell)`, and `has_failed_pick_lock(entity_id, level)`. The full option set:

| Cell state | Option | Availability | Behavior |
|---|---|---|---|
| Closed (unlocked) | **Open Door** | Always | Move adjacent, open. Updates passable + LOS. |
| Open | **Close Door** | Always | Move adjacent, close. |
| Stuck | **Force Door** | Always | Move adjacent. Strength throw to unstick (1 round per attempt). Cooperating ally adds to the throw per ACKS. Does not destroy the door. |
| Locked | **Unlock** | Matching key in any selected entity's inventory | Move adjacent, unlock with key, open. (Currently surfaced as `enabled=false` placeholder until key inventory is wired.) |
| Locked | **Pick Lock** | Class in `CLASSES_WITH_OPEN_LOCKS` (currently `["thief"]` only — bards are excluded despite thief progression, per ACKS RAW `class_powers`) OR Lockpicking proficiency | Move adjacent. 1 turn standard; 1 round at -10 penalty per `ax_thief_skill_update.xml`. **Failure is permanent per character per lock until they level up** — the option greys with tooltip "Already failed — must gain a level to retry" once all capable selected pickers have failed. Failure tracked in `DungeonSessionState.has_failed_pick_lock(entity_id, level)`. |
| Any closed (wooden) | **Bash Door** | Any selected entity carries an axe (`hand_axe` / `battle_axe` / `great_axe`); door material is wooden | Move adjacent, batter down. **House rule:** all wooden doors take 1 turn to bash regardless of `door_material` (`_bash_door_turns()` returns 1 unconditionally; the per-material 1/3-turn variation in earlier drafts is not implemented). On completion, `door_state = "destroyed"`; the door cannot be closed again. |
| Any closed (iron / stone) | **Bash Door** | *(Greyed)* | Tooltip: "This door is too strong to batter down." |
| Any closed | **Spike Shut** | Any selected entity carries `iron_spikes_12` AND a spike-driving hammer (`hammer_small` or `warhammer`) | Move adjacent, drive a spike. 1 round. Sets `DungeonSessionState.is_spiked(cell) = true`. Spiked doors block opens until the spike is removed. |
| Any open | **Wedge Open** | Either (`iron_spikes_12` + `hammer_small`/`warhammer`) OR (`wooden_stakes_4` + `hammer_small`/`warhammer`/`mallet`) | Move adjacent, drive a wedge. 1 round. Sets `DungeonSessionState.is_wedged(cell) = true`. Critical for evil doors (see below). |
| Spiked (own side) | **Remove Spike** | Always | Move adjacent. 1 round. With a `crowbar` in inventory: spike returns to inventory intact. Without: spike is destroyed. |
| Wedged | **Remove Wedge** | Always | Move adjacent. 1 round. With `crowbar`: iron spike recovers; wooden stake destroyed regardless. Without `crowbar`: item destroyed. |
| Any closed | **Listen at Door** | Always | Move adjacent, Listen check (1 round). Same throw as Listen Here; log specifically says "listens at the door." Available even on spiked doors. |
| Secret (undetected) | *(No door options shown — cell appears as wall)* | — | Player must Search to find. |
| Secret (detected, closed) | **Open Secret Door** | Always | Move adjacent, open the hidden mechanism. Surfaces under "Open Door" once `door_detected = true`. |
| Portcullis (closed) | **Force Portcullis** | Always | Move adjacent. STR throw (18+ with STR mod). Drops when the lifter releases — see Wedge Open for held-up state. |
| Portcullis (closed) | **Spike Shut** | Iron spikes + hammer | Spike a closed portcullis. |
| Portcullis (open, not held) | **Drop Portcullis** | Always | Move adjacent to mechanism, drop it. |
| Portcullis (open) | **Wedge Open** | Iron spikes + hammer OR wooden stakes + tool | Wedge in raised position. |
| Arch | *(No options — always passable)* | — | Archways are always open by definition. |
| Destroyed | *(No options)* | — | Door is gone; cell is permanently passable. |

**Evil doors (`is_evil = true`).** Per ACKS, evil doors auto-close every turn (60-round tick) unless they are wedged open, held by a character, bashed/destroyed, or magically held. They open freely for monsters unless spiked shut, held firm, or magically closed. The scheduler emits an `evil_door_close` event on each turn boundary (per `gdd-realtime-scheduler.md`) for every open evil door not in one of the held-open states. Wedge Open is the player's primary defense; consuming a wedge consumable per evil door visited becomes a real resource cost.

#### 4.2.2 Stairs and transitions

`VoxelCell.feature` for stair cells encodes a direction suffix per voxel arch §10.1: `stairs_up_<DIR>` rises one level in DIR; `stairs_down_<DIR>` descends one level in DIR. Internal stairs vs. dungeon-exit transitions are distinguished by `VoxelMapData.is_transition_cell(pos)`.

| Cell feature | Option | Behavior |
|---|---|---|
| `stairs_up_*`, internal | **Ascend** | Selected entity moves to the stair cell; on arrival, transitions to the destination cell on the level above per `DungeonMapController.get_stair_target(pos)` (explicit pairing or direction-suffix inference). |
| `stairs_down_*` | **Descend** | Same, descending. |
| `stairs_up_*` AND transition cell | **Exit Dungeon** | Queues the entity for exit. Confirmed exit returns the party to the overworld at the dungeon's hex. |
| Non-stair transition cell (cave entrance, etc.) | **Exit Dungeon** | Same as above. |
| Stair feature where entity is already exited or queued for exit | *(No option)* | — |

#### 4.2.3 Traps

| Cell state | Option | Availability | Behavior |
|---|---|---|---|
| Trap detected, not disarmed | **Disarm Trap** | Thief combat_progression OR Find/Remove Traps proficiency | Move adjacent (NOT onto the trap cell). 1 turn standard; 1 round at -10 per `ax_thief_skill_update.xml`. Failure by 10+ or natural 1 triggers the trap. |
| Trap detected, not disarmed | **Trigger Trap (Deliberate)** | Always | Move adjacent. Use a 10-foot pole or thrown object to trigger from safe distance. (Currently surfaces unconditionally; tool-availability gating is a future enhancement.) |

Undetected traps surface NO options — they are invisible to the player until found by Search or by passive detection (currently only Elf casual inspection per `gdd-realtime-scheduler.md` §6.6, not yet implemented in code).

#### 4.2.4 Levers, fountains, altars, statues

| Feature | Option | Behavior |
|---|---|---|
| `lever` | **Use Lever** | Move adjacent, pull/push. Effect depends on what the lever is wired to (door, portcullis, trap, secret room). |
| `fountain` / `altar` / `statue` | **Examine** | Move adjacent, examine. Description, event trigger, or no-op depending on stocking. |

Locked containers are deferred until inventory-on-the-floor is wired (§4.5).

### 4.3 Entity options

Suppressed when the target cell's fog state is not `visible` (you can't see who's there).

#### 4.3.1 NPC / monster (non-party)

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Talk** | Always (including hostile / non-intelligent — currently un-gated; intelligence gating is a future enhancement) | Move adjacent, initiate dialogue. Dialogue system itself is deferred. |
| **Attack** | Always | Move adjacent, initiate combat. Triggers transition per `gdd-realtime-scheduler.md` §6.8. Non-hostile targets surface a confirmation modal: "This will start combat with `<NPC>` and their allies. Proceed?" |
| **Cast Spell** | Caster with prepared spells | *(Currently `enabled=false` — spell system deferred.)* |

**Deferred from earlier draft:** Heal-NPC and Pick Pockets are not currently surfaced. Heal-NPC waits on the healing system; Pick Pockets waits on a thief-action surface that will land alongside the broader thief skill suite.

#### 4.3.2 Party member (other than the selected entity)

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Trade** | Adjacent (3D Chebyshev ≤ 1) per voxel arch §5 | Opens the Inventory tab (notebook tab #2) scoped to the two carriers. Drag-drop transfers between the two entities' inventories. **Note:** the adjacency gate is not yet wired in the menu builder — the option currently surfaces unconditionally; gating is a Phase γ wiring task. |
| **Heal** | Healing spells or Healing proficiency | *(Currently `enabled=false` — healing system deferred.)* |
| **Add to Group** | Always | Adds the target to the selected entity's RTS control group (creates a new group if neither is currently in one). Distinct from party formation, which is per-party and managed in the Party tab Formation sub-tab. |
| **Cast Spell** | Caster with prepared spells | *(Currently `enabled=false` — spell system deferred.)* |

#### 4.3.3 Downed or incapacitated character

When the target cell contains a character at 0 HP or below, paralyzed, or otherwise incapacitated. Applies to friendly AND hostile downed entities. *(Project-designed Arbiter content — preserved from v1.)*

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Check Status** | Always | Move adjacent, examine. Displays current Mortal Wounds result and condition. If the selected entity has Healing proficiency (with kit/herbs), a healing potion, OR healing spells prepared, a modal opens listing available treatment resources with effects and costs. Selecting one consumes the resource and resolves the Mortal Wounds check per `ax_mortal_wounds_and_tampering.xml`. |
| **Carry** | Always | Move adjacent, pick up. The downed character becomes an inventory item on the carrier. **Weight: 15 stone ± CON modifier of the carried character**, plus the carried character's inventory weight. Encumbrance recomputes immediately. A carried character can be transferred to another carrier (including mules and pack animals) via Trade. Drop with the carrier's **Drop Item** to place them back on the ground. |
| **Loot** | Always | Move adjacent. Opens the Inventory tab scoped to the downed character + the looter. Items transfer in either direction. Use case: stripping gear from an incapacitated ally to reduce carry weight before Carry. |
| **Heal** | Healing spells or Healing proficiency (with supplies) | Apply healing directly. Distinct from Check Status, which specifically resolves the Mortal Wounds table. *(Currently `enabled=false`.)* |
| **Cast Spell** | Caster with self-targeting spells | *(Currently `enabled=false`.)* |
| **Attack (Coup de Grâce)** | Always | Move adjacent. Automatic hit against helpless target. Confirmation modal: "This will kill `<name>`. Proceed?" |

**Carried character details.** A carried character is mechanically an inventory item with special properties: cannot act, light sources extinguished, equipment remains on them (unless looted first), conditions continue to tick (bleeding, poison). If the carrier enters combat, the carried character does NOT participate. If the carrier is themselves downed, the carried character drops in the same cell.

#### 4.3.4 Self (right-click own cell)

Built by `_build_self_options`. Recognized by `_is_self_click` — the target cell matches any selected entity's position.

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Hide** | Thief class OR Skulking proficiency (in any selected entity) | All capable members of the selection (or selected entity's group) attempt Hide in Shadows in their current cells. No movement. Successful characters are hidden; failures believe they succeeded until an enemy reacts (per ACKS). Hidden characters remain hidden only while motionless. |
| **Light Torch** | Torch + tinderbox in inventory | Per `DungeonLightManager`: lights or relights a torch. 6 turns burn time. `LIGHT_RADIUS_CELLS = 10` (50' total: 30' bright + 20' dim). On expiry, auto-lights next torch if available. |
| **Light Lantern** | Lantern + tinderbox + (lantern fueled OR oil flask) | Lights or refills+lights a lantern. 24 turns per `oil_flask_common`. Auto-consumes next flask on expiry; extinguishes if none available. |
| **Extinguish Light** | Currently carrying a lit torch or lantern | Puts out the light. Torch consumed (cannot relight). Lantern retains remaining oil. |
| **Heal** | Healing spells or Healing proficiency | Self-heal. *(Currently `enabled=false`.)* |
| **Cast Spell** | Caster with self-target spells | *(Currently `enabled=false`.)* |
| **Use Item** | Consumable items in inventory | Quick-select list (potions, scrolls). 1 round (or per-item duration). |
| **Set Default Idle Behavior** | Always | Opens the idle behavior submenu (§5). |
| **Drop Item** | Items in inventory | Opens inventory selection; chosen item(s) drop on the current cell. Creates a loot pile if one doesn't exist. |

### 4.4 Stealth Move vs. Hide-in-place

A compound action with two forms based on click target:

#### 4.4.1 Stealth Move (right-click distant cell)

| Option | Availability | Behavior |
|--------|-------------|----------|
| **Stealth Move** | At least one selected entity has Move Silently capability (thief class OR Skulking proficiency) | Selected entity paths to the target cell with movement mode set to silent (Move Silently throw at start; half combat speed = no penalty, faster = -5, running = -10). On arrival, automatic Hide in Shadows attempt at the destination cell. **Group behavior:** capable members attempt silent movement; non-capable members move normally and likely break stealth for the group. |

Both throws are hidden from the player per ACKS — the character believes they succeeded until enemies react.

#### 4.4.2 Hide in place (right-click own cell or in-group cell)

When the right-clicked cell IS the selected entity's own cell or contains a member of its control group, **Stealth Move is omitted** and **Hide** appears in the self-actions (§4.3.4).

This split keeps the menu clean: the player never has to manually sequence "move silently then hide"; the system handles the compound action.

### 4.5 Loot and dropped containers

Loot interactions surface through the Inventory tab, NOT through a standalone Loot Panel.

| Cell condition | Option | Behavior |
|---|---|---|
| `cell.has_ground_items == true` | **Loot** | Move adjacent. Opens the Inventory tab (notebook tab #2) scoped to the selected entity + the loot-cell carrier. Drag-drop both directions. |
| `cell.has_ground_items == true` | **Pick Up All** | Move to cell, transfer all items to the selected entity's inventory up to encumbrance. Overflow remains; log: `"<Name>: Cannot carry any more."` |

**Current build status.** `cell.has_ground_items` is hard-coded to `false` in `dungeon_context_menu_builder.gd:53` with TODO comment "wire from location cache." Loot options never surface in production until the location cache is wired through. Resolution sequence: build the floor-carrier registration when items are dropped, expose `LocationCacheManager.has_ground_items(cell) -> bool`, and replace the TODO with the live query. Tracked as **§13 Build Status item L-1**.

---

## 5. Default Idle Behavior System

Each entity has a configurable **default idle behavior** that determines what it does when it has no active orders and is not in combat. Significantly reduces micromanagement for parties with many members.

### 5.1 Available behaviors

| Behavior | Description |
|---|---|
| **Hold Position** (default) | Stay in current cell. Wait for orders. |
| **Follow Group Lead** | If in a control group, follow the unit at marching-order position 1. Maintain formation spacing per the Party tab Formation sub-tab grid. Match lead's movement mode. If not in a group, behaves as Hold Position. |
| **Auto-Listen at Doors** | When idle and adjacent to a closed door, automatically Listen check. Results in the unified log. Does not open the door. |
| **Auto-Search** | When idle on entry to a new room, automatically begin a Search action. Slow (1 turn per 10'×10') and noisy. |
| **Guard** | Hold position. If a hostile enters the entity's awareness radius, auto-pause and flag. Does not auto-attack — alerts only. |
| **Hide** | If the entity has Hide in Shadows capability, attempt to hide in current position. Remain hidden and motionless until orders arrive or hiding breaks. |

### 5.2 Setting idle behavior

Two access paths:
1. **Self-action context menu → Set Default Idle Behavior** (§4.3.4) — opens a submenu listing behaviors. Some grey out per prerequisites.
2. **Group options panel** — set idle for all group members at once. (Group options panel is now a HUD widget on the control group bar, NOT a marching-order surface; see §6.2.)

Idle behavior persists until changed. Stored per-entity in `DungeonSessionState` for the duration of the dungeon visit.

### 5.3 Follow Group Lead detail

The most common idle behavior for henchmen and non-PC party members:
- Entity follows the formation position assigned by the Party tab's Dungeon 2×12 grid (per `gdd-party-tab.md` §7).
- Movement speed matches the group's speed (slowest member rule).
- If the lead stops, followers stop in formation behind it.
- If the lead enters combat, follower idle suspends; they enter combat per their AI / player control.
- If the lead performs a non-movement action (search, listen, pick lock), followers wait in current positions.

---

## 6. HUD widgets and group management

### 6.1 SessionStatusBar handles per-entity status

The per-selection unit info panel from v1 is removed. Its contents are now spread across:
- **SessionStatusBar left zone** — party portraits with HP / encumbrance / marching-order indicator (read-only). Per `gdd-ui-architecture.md` §3.8.
- **SessionStatusBar center zone** — clock, light source indicator, party encumbrance band.
- **Character tab (notebook tab #1)** — full sheet on demand. Reached by clicking a portrait or pressing C.

When the player needs to inspect the active selection's full state, they open the Character tab. The dungeon view does not duplicate this surface.

### 6.2 Control Group Bar

Bottom-of-screen horizontal bar with numbered slots [1] through [9]. Each slot shows:
- Group number
- Compact portrait mosaic (2-4 tiny portraits or a count badge if more)
- Movement-mode pip (green = exploration, yellow = combat speed, red = running)
- Active vs. idle state (brightened vs. dimmed)

Interactions:
- **Left-click slot** → select all group members.
- **Double-click slot** → select and center camera.
- **Right-click slot** → opens the Group Options Panel (below).

#### 6.2.1 Group Options Panel

Right-click on a group slot opens a popup with:
- **Movement Mode** — toggle Exploration / Combat Speed / Running for the entire group.
- **Set All Idle Behavior** — apply an idle behavior to all members.
- **Disband Group** — remove the control group assignment.

**What is NOT here:** marching order. Marching order belongs to the Party tab's Formation sub-tab (Wilderness 6×12 + Dungeon 2×12 grids) per `gdd-party-tab.md` §7. The Group Options Panel does not duplicate it.

### 6.3 Movement speed (slowest-member rule)

Group speed is set by the slowest member, computed from base move rate × encumbrance × movement-mode multiplier × proficiency modifiers. The control group bar surfaces the effective group speed pip so the player sees the impact of their slowest member at a glance. The per-entity calculation lives in `EncumbranceCalculator` and is shared with `gdd-party-tab.md` §6 (Travel sub-tab).

### 6.4 Marching order — pointer only

Marching order is configured exclusively in the Party tab's Formation sub-tab. The dungeon UI consumes it (via `PartyData.formation` / `FormationManager.compute_dungeon_positions_3d`) but does not surface configuration UI. SessionStatusBar shows a read-only marching-order indicator on each portrait per `gdd-ui-architecture.md` §3.8.

---

## 7. Multi-level UX

This section is new in v2. It documents how the dungeon UI integrates with the multi-level voxel architecture from `gdd-voxel-tactical-architecture.md` §16.

### 7.1 Focus level

The camera always has a single **focus level** — the voxel y-layer it is centered on. Per voxel arch §16.1:
- Default on dungeon entry: focus = party leader's level.
- Auto-switch on selection: clicking a party member sets focus = that member's level.
- Manual control: PgUp / PgDn cycles focus up/down.
- Fast jump: clicking a SessionStatusBar portrait jumps focus to that member's level AND sets them as the active selection.

### 7.2 Per-level rendering

`VisibilityManager` drives per-level opacity per voxel arch §16.2:
- `level > focus + 1` — hidden (not rendered)
- `level == focus + 1` — dithered transparency (or hard-clip fallback per voxel arch §16.3)
- `level == focus` — fully opaque
- `level < focus` — opaque, dimmed (×0.6 brightness)

Exceptions:
- Party member tokens on non-focused levels render at full opacity.
- Visible enemies on non-focused levels render at half opacity with a colored outline.

### 7.3 Level Strip Widget

Right-edge HUD widget per voxel arch §16.4. One row per level containing party members, visible enemies, or revealed structure. Each row shows level number, party-member icons, enemy badge, focus indicator. Click to jump focus to that level.

Real and currently shipping: `LevelStripWidget` (instantiated by `DungeonMapRenderer3D`, added to DungeonHUD CanvasLayer, consumes `VisibilityManager` + `EventBus.party_member_levels_snapshot`).

### 7.4 OffscreenPartyIndicators

When a party member is on the focused level but outside the camera viewport, an arrow on the screen edge points toward them. Click the arrow to pan the camera. Real and shipping: `OffscreenPartyIndicators` consumes `DungeonMapRenderer3D.get_party_focus_tokens()`.

### 7.5 Auto-focus on cross-level events

The scheduler emits `EventBus.dungeon_auto_focus_requested(level)` when an auto-pause event fires on a non-focused level (encounter, trap trigger, secret-door reveal, torch expire, etc.). The renderer tweens camera Y to the new focus level over ~0.3s. Per voxel arch §16.5 and `gdd-realtime-scheduler.md` §7.

### 7.6 Multi-level context menus

Right-clicking a cell on a non-focused level surfaces the same context menu as the focused level, but with a confirmation step: first click highlights the cell and shows a "Move here on Level N" tooltip; second click confirms. Prevents misclicks on dimmed/dithered cells per voxel arch §16.5.

### 7.7 Camera horizontal pan

Per voxel arch §16.6: camera horizontal pan is clamped to the bounding box of explored cells plus a 1-cell border. Free Camera mode is a dev-option toggle that disables clamping. Home key recenters on the party leader.

---

## 8. Fog of war (consumed from voxel arch §15)

The dungeon UI consumes the three-state fog model. It does not maintain its own.

### 8.1 States

| State | Rendering | Right-click menu |
|---|---|---|
| **Hidden** | Black / textured void (subtle noise/parchment per voxel arch §16.6 — never pure black) | Universal options only (Move Here paths toward, stops at fog boundary). No environment, entity, or self options. |
| **Explored** | Dimmed / desaturated. Walls, doors, room shapes visible (last-seen state). Entities and items NOT shown — things may have changed. | Universal + environment options (based on remembered cell data — note that remembered data may be stale; an open door you left may now be closed by monsters). Entity options suppressed. |
| **Visible** | Fully lit. Entities, items, real-time status. | Full menu. |

### 8.2 Reveal model (B5+)

Light-source + LOS based, NOT room-scoped. Each party member's light radius (computed per voxel arch §15.2 by `DungeonMapController._get_entity_visible_radius` = `light_radius + darkvision_bonus`) plus 3D LOS bounds the visible cells via `FogRevealEngine.compute_visible_cells`. Cells exit `visible` and demote to `explored` when they leave the union of all members' light + LOS coverage. Multi-level fog is supported per voxel arch §15.3 — different levels of the same room can have different fog states.

Default fallback when no `DungeonLightManager` is wired: `_fallback_light_radius = 10` cells (50'). Production has `DungeonLightManager` wired.

### 8.3 Darkvision

Per-entity bonus added to light radius via `DungeonMapController.set_entity_darkvision(entity_id, cells)`. Elves and dwarves have darkvision per their `acore_demihuman_classes.xml` entries; the bonus is set during character generation. Per voxel arch §15.1, flying creatures see over walls naturally because their cell is elevated — 3D LOS handles this without special cases.

---

## 9. Action queuing and cancellation

### 9.1 Single-slot order model

`DungeonOrderManager` (real, at `engine/subsystems/exploration/dungeon_order_manager.gd`) provides one pending order per entity. Order types in current code:

| Order type | Meaning |
|---|---|
| `move` | Walk to `target_pos` along `path`. |
| `interact_door` | Already adjacent; toggle the door. |
| `move_and_interact_door` | Path to nearest passable cell adjacent to the door, then interact. |
| `move_adjacent` | Generic "path to a cell adjacent to target_pos" — used by force_door, pick_lock, bash_door, lever, listen_at_door, spike/wedge actions. |
| `search` | Search the current/target cell. |
| `listen` | Listen at the cell. |
| `wait` | Hold position (explicit no-op; also the conversion target for collided `move` orders). |

API: `add_order(entity_id, order_type, target_pos, path)` queues; `clear()` flushes all; `execute_orders()` resolves the batch.

### 9.2 New order replaces the old

If the player issues a new order while one is pending:
- **Move orders** redirect immediately. `add_order` overwrites the entry; `renderer.cancel_movement_animation(entity_id)` fires before `start_movement_animation` for the new path (per `gdd-realtime-scheduler.md` §3.3).
- **Non-move actions** (search, lockpick, listen) — current action interrupts, no partial credit. ACKS doesn't have partial-search progress.
- **Queue stacking** — only one pending order is supported. The player issues each order as the previous completes. No multi-step sequencing.

### 9.3 Cancellation flow

| Cancel scope | Mechanism |
|---|---|
| One entity's pending order | `DungeonOrderManager.remove_order(entity_id)` |
| All pending orders | `DungeonOrderManager.clear()` |
| One entity's in-flight movement animation | `renderer.cancel_movement_animation(entity_id)` |
| All in-flight movement animations | `renderer.cancel_all_movement_animations()` (called on combat enter per scheduler §6.8) |
| One entity's scheduled event (search, lockpick, etc.) | `EventScheduler.cancel(event_id)` |
| All of an entity's scheduled events | `EventScheduler.cancel_all_for_owner(owner_id, event_type)` |

The dungeon UI does not advance time directly. It issues orders to the order manager + scheduler, drives the renderer movement layer, and reads back results from completion signals.

### 9.4 Group orders

When a control group is selected and the player issues an order:
- **Move Here:** `DungeonMapController.queue_group_move(target)` — leader paths via `MovementResolver.path_bfs_3d`; followers place via `FormationManager.compute_dungeon_positions_3d` against the active formation preset (collapse chain: full → double column → single column → stack on leader). Headless / no-PartyData fallback uses ring-scatter around the target.
- **Search Here / Listen Here:** the front unit (marching-order position 1) performs the action. Others hold position. To use a specific member, the player selects that individual.
- **Door interactions:** the most appropriate unit performs (thief for Pick Lock, axe-carrier for Bash, etc.). Others hold.

---

## 10. Action durations and scheduler integration

The dungeon UI does not own action durations. It dispatches scheduled events with the durations specified in `gdd-realtime-scheduler.md` §6.5 and `acore_adventures_and_encounters.xml` / `ax_thief_skill_update.xml`.

Action lifecycle for any context-menu action that requires movement before the activity:

1. **Order issued.** Player picks a context-menu option. UI dispatches via `DungeonContextMenuBuilder.build_menu` → action handler.
2. **Path computed.** `MovementResolver.path_bfs_3d(start, near-target, "ground", max_steps, max_level_jumps, "explore")`.
3. **Renderer animation.** `renderer.start_movement_animation(entity_id, path, cells_per_round)` begins per-cell tween chain at game-clock-scaled duration.
4. **Per-cell arrival.** `movement_cell_reached(entity_id, cell)` fires. Handler updates `voxel_map.entity_positions`, runs occupancy/passability/encounter-proximity checks, starts next tween — or stops the chain on failure.
5. **Final cell reached.** Handler dispatches the queued action: `EventScheduler.schedule_at(fire_time, action_event_type, entity_id, data, priority)`.
6. **Activity resolves.** Handler returns its result; SchedulerLoop applies follow-up events, auto-pause, or state transitions per scheduler §11.2.

Per-action movement → scheduled-event mapping:

| Action | Movement | Scheduled event(s) on arrival |
|---|---|---|
| Move Here | path → target cell | (none — movement is the activity) |
| Search Here | path → target cell | `dungeon_search_complete` at +1 turn |
| Listen Here | path → target cell | `dungeon_listen_complete` at +1 round |
| Force Door | path → adjacent cell | `force_door_attempt` at +1 round (repeats on failure) |
| Pick Lock | path → adjacent cell | `pick_lock_complete` at +1 turn (or +1 round at -10) |
| Unlock (key) | path → adjacent cell | Immediate state change on arrival |
| Bash Door | path → adjacent cell | `bash_door_complete` at +1 turn (house rule, all wooden doors) |
| Spike Shut / Wedge Open / Remove Spike / Remove Wedge | path → adjacent cell | `spike_complete` / `wedge_complete` / `remove_spike_complete` / `remove_wedge_complete` at +1 round |
| Stealth Move | path → target cell with mode "stealth" (Move Silently throw at start) | `hide_attempt` on arrival |
| Hide (self) | (none — instantaneous) | `hide_attempt` immediate for all capable group members |
| Light Torch / Lantern | (none) | Immediate state change + `light_source_expired` at +6 / +24 turns |
| Extinguish Light | (none) | Immediate state change + cancel the pending `light_source_expired` |
| Talk | path → adjacent NPC cell | `dialogue_start` immediate on arrival |
| Check Status (downed) | path → adjacent cell | `mortal_wounds_check` immediate; opens treatment modal if resources available |
| Carry (downed) | path → adjacent cell | Immediate: downed becomes inventory item on carrier; encumbrance recalculated |
| Loot (downed or pile) | path → adjacent cell | Immediate: opens Inventory tab scoped to the two carriers |
| Use Lever | path → adjacent cell | `lever_actuated` immediate; effect resolves via wiring |
| *(System)* Evil door auto-close | (n/a — system event) | `evil_door_close` fires on each turn boundary for all open evil doors not held / wedged / spiked / destroyed |

---

## 11. Camera controls

### 11.1 Pan and zoom

| Input | Action |
|---|---|
| Arrow keys / WASD | Pan camera |
| Mouse-to-edge (40px margin) | Pan in that direction |
| Middle mouse drag | Free pan (clamped to explored bounds + 1 per §7.7) |
| Mouse wheel | Zoom |
| Home | Recenter on selected entity (or party leader) and reset zoom |

### 11.2 Level controls (multi-level)

| Input | Action |
|---|---|
| PgUp | Focus level + 1 |
| PgDn | Focus level - 1 |
| Click LevelStripWidget row | Jump focus to that level |
| Click SessionStatusBar portrait | Set active entity AND jump focus to their level |
| Shift+Home | Jump to next party member |

### 11.3 Camera follow

Optional toggle (default: on for single-entity selection, off for multi-selection). The camera tracks the selected entity. Manual pan breaks follow; Home or new selection re-engages.

### 11.4 Minimap

The minimap shows currently-visible cells on the focus level only — a top-down schematic of what party members can see right now. Multi-level minimap is out of scope for v1; the Level Strip Widget covers the multi-level navigation case.

**Automapping (Mapping proficiency).** If at least one party member has the Mapping proficiency AND a journal/parchment AND ink in inventory, the minimap retains explored cells on the focus level after they leave LOS, but only for cells explored in **exploration movement mode** — combat speed and running don't produce automap data. Without a mapper, the minimap is live-only.

**Minimap interaction.** Click jumps the main camera to that location (automapped or currently-visible cells only). Enemies are not shown on the minimap.

---

## 12. Cross-surface integration

### 12.1 Notebook activation seam

Clicking an entity in the dungeon view sets the global notebook active entity via `EventBus.notebook_active_entity_requested(entity_id)`. Notebook does not auto-open; the player invokes it explicitly (C key, SessionStatusBar portrait, etc.). When the notebook IS open while the player clicks an entity in the dungeon view (rare during dungeon exploration, since notebook pauses the world), the Character tab refreshes to the new entity.

### 12.2 Inventory tab routes loot and trade

Trade between adjacent party members and Loot from a downed character or floor pile open the Inventory tab (notebook tab #2) scoped to the two carriers. The Inventory tab handles the carrier-aware drag-drop UX. The dungeon UI does not host its own dual-pane modal.

### 12.3 Unified Log routes notifications

Every dungeon-context notification (movement complete, action result, encounter trigger, resource depletion, etc.) routes to `EventBus` signals consumed by the Unified Log per `gdd-unified-log-panel.md` v2. Entries appear in the appropriate filter tab (All / Combat / Rolls / Narration). The dungeon UI does not maintain its own scrolling text panel.

Toast-class notifications (transient on-screen alerts) continue to use `NotificationDisplay` per `gdd-ui-architecture.md` §2.7.

### 12.4 SessionStatusBar handles at-a-glance

Portraits with HP/encumbrance, location label, time/date, clock-speed cluster, party encumbrance band, light source indicator, current notification — all live in the SessionStatusBar three-zone bar per `gdd-ui-architecture.md` §3.8. The dungeon UI does not duplicate any of these.

### 12.5 Party tab handles formation

Marching order, formation presets, party-state summary — all in `gdd-party-tab.md`. The dungeon UI consumes the active formation but does not surface configuration UI.

---

## 13. Build status and remaining work

Current implementation status, derived from `engine/subsystems/exploration/*` and `current_state_ui_audit.md` (2026-04-27):

### 13.1 Working

- `DungeonContextMenuBuilder.build_menu` — pure-logic menu builder; matches §4 structure.
- `DungeonOrderManager` — single-slot order queue per §9.1.
- `DungeonMapController` — group/individual move queuing, door interaction with adjacency check, fog updates, claim-based collision in `_execute_orders_voxel`.
- `MovementResolver.path_bfs_3d` — stair-aware level-spanning pathfinding.
- `VoxelMapData` / `VoxelGrid` — 3D coordinate substrate, adjacency predicate.
- `DungeonLightManager` — torch (6 turns) / lantern (24 turns) lifecycle + auto-relight + tinderbox/oil tracking.
- `FogRevealEngine.compute_visible_cells` — light + LOS fog computation.
- `VisibilityManager`, `LevelStripWidget`, `OffscreenPartyIndicators` — multi-level UX shipping.
- `DungeonHUD` CanvasLayer with TooltipPanel + ContextMenuLayer.
- Door tooling rules (axe / iron spikes / wooden stakes / hammers / mallet / crowbar) per §4.2.1.
- Pick Lock per-character per-lock failure memory in `DungeonSessionState`.
- Stair direction-suffix inference (`stairs_up_<DIR>` / `stairs_down_<DIR>`) and explicit `stair_target_*` overrides.
- Transition cell distinction (`is_transition_cell`) for Exit Dungeon vs. Ascend.

### 13.2 Stubbed or unwired

| Item | Status | Resolution |
|---|---|---|
| **L-1 Loot / Pick Up All visibility** | `cell.has_ground_items` hard-coded `false` (`dungeon_context_menu_builder.gd:53`) | Wire `LocationCacheManager.has_ground_items(cell)`; replace TODO with live query. |
| **L-2 Trade adjacency check** | Surfaces unconditionally on party-member targets | Add `VoxelGrid.is_adjacent(selected_pos, target_pos)` gate in `_build_entity_options`; tooltip when greyed: "Move adjacent to trade." |
| **L-3 Heal (NPC / party / self / downed)** | All `enabled=false` placeholder | Wire when healing system lands (proficiency throw + spell dispatch). |
| **L-4 Cast Spell (any context)** | All `enabled=false` placeholder | Wire when spell system lands. |
| **L-5 Talk dialogue surface** | Option surfaces; no dialogue system to dispatch to | Wire when dialogue system lands. Until then, `dialogue_start` event resolves to a placeholder log entry. |
| **L-6 Pick Pockets** | Not surfaced | Wire when thief skill suite expands. |
| **L-7 Heal NPC option** | Not surfaced (was in v1) | Wire alongside L-3. |
| **L-8 Trigger Trap (Deliberate) tool gating** | Surfaces unconditionally; should require 10-foot pole or thrown object | Add inventory check; grey when no safe-trigger tool. |
| **L-9 Talk hostility / intelligence gating** | Surfaces unconditionally on any non-party entity | Add `entity.can_communicate` check; grey for non-intelligent creatures. |
| **L-10 Elf casual inspection** | TODO at `dungeon_handlers.gd:642` (also flagged in `gdd-realtime-scheduler.md` §6.6) | Implement per scheduler §6.6 spec: 14+ on 1d20, exploration mode only, 3D Chebyshev ≤ 2 occlusion-bounded trigger volume, one passive check per elf per door. |
| **L-11 Per-level wandering monster checks** | Single-check-per-party (scheduler §6.7) | Straightforward refactor of `_handle_encounter_check`. |
| **L-12 Climb action** | Not present | Add when elevation-aware gameplay needs it: right-click an elevated cell → "Climb Here" (thief Climb Walls throw, 1 round per 10' of height). |
| **L-13 Rest / Short Rest** | Not present | Party-level action (NOT per-entity). Consumes time; wandering monster checks continue. Defer to camp/rest GDD when written. |
| **L-14 Formation-mode in rooms** | Implementation status uncertain | Verify whether `FormationManager` exposes per-group formation modes (column / line / wedge / circle) and wire to the Group Options Panel. |

### 13.3 Phase placement

Per `gdd-ui-architecture.md` §10:

- **Phase α — Foundations.** UiInputController integration for context menus; Theme.tres migration for menu styling. Already mostly landed.
- **Phase β — Notebook scaffolding.** Wire trade/loot menu options to `EventBus.notebook_open_requested(Inventory)` + `notebook_active_entity_requested(target_id)`. (L-2 wiring depends on Phase β.)
- **Phase γ — Tab migration.** Inventory tab fully replaces standalone loot/trade modals once `gdd-inventory-tab.md` Phase γ lands.
- **Phase H+ (gameplay).** L-3 / L-4 / L-5 / L-6 / L-7 wire as the underlying systems (healing, spells, dialogue, thief skills) ship.

---

## 14. Edge cases

- **Selecting an entity in a Hidden cell.** Not possible — entities in hidden cells are invisible to selection.
- **Right-clicking while game is unpaused.** Context menu auto-pauses on open; resumes at the previously-set speed on selection or dismissal.
- **Multiple entities through a single doorway.** Resolves naturally via claim-based occupancy (scheduler §6.4): first entity claims the door cell, others convert to `wait` for one tick, then advance. No explicit queue data structure.
- **Right-clicking a destination already occupied.** Order issuance succeeds; `_execute_orders_voxel` collision pass converts to `wait`. Log: `"<Name>: Move complete — destination occupied, stopped adjacent."`
- **Entity dies during a queued action.** Action abandoned. Entity enters Mortal Wounds flow. Order cleared.
- **Right-clicking while a context menu is open.** Old menu closes, new menu opens at new position.
- **Bash vs. Force on a stuck wooden door.** Both surface. Force = 1 round STR throw, doesn't destroy. Bash = 1 turn (house rule) + axe required, destroys permanently. Player choice.
- **Combat on a staircase.** 3D Chebyshev ≤ 1 handles cross-level engagement automatically (voxel arch §16.9). Two combatants on adjacent stair cells at different levels are engaged.
- **Cross-floor inventory transfer.** Forbidden — adjacency rule per voxel arch §5. Transfers require carriers to be at Chebyshev ≤ 1 in 3D, including level.
- **Carrying a downed character into combat.** Carried character does NOT participate. If carrier is also downed, carried entity drops in the same cell.
- **Node graph keybinds in context.** During `DUNGEON_EXPLORE`, number keys 1-9 are control groups; clock-speed via SessionStatusBar buttons or Space (toggle pause). During `MAIN_MENU` / creation flows, none of these keybinds are active.

---

## 15. Data dependencies

The dungeon UI consumes (does not produce) the following from upstream subsystems. Reproduced here for cross-reference; authoritative definitions live in the cited GDDs.

| Data | Source | Used For |
|---|---|---|
| `VoxelMapData` cells, doors, fog, entity positions | `gdd-voxel-tactical-architecture.md` + `gdd-dungeon-layout.md` | Menu generation, rendering, pathfinding |
| `DoorData.door_material`, `is_evil`, `door_state`, `door_type`, `door_detected` | `gdd-dungeon-layout.md` §11 | Door option availability, evil door auto-close |
| Entity data (class, level, HP, inventory, proficiencies, darkvision) | `CharacterData` | Per-entity option gating |
| `PartyData` (members, formation, marching order) | `gdd-party-tab.md` v1.4 | Formation-aware group movement, slowest-member speed |
| Active light sources + remaining duration | `DungeonLightManager` | Visibility radius, torch/lantern menu options |
| Trap data (detected, disarmed, trap type) | Dungeon stocking | Disarm/Trigger option availability |
| Control group assignments + idle behaviors + spike/wedge state + pick-lock failure memory | `DungeonSessionState` | Group bar, idle execution, door interactions |

The dungeon UI produces (writes back to upstream):

| Action | Data change | Persistence |
|---|---|---|
| Move order | Insert `move` order in `DungeonOrderManager` → consumed on `execute_orders` | Per-tick scheduler state |
| Door interaction (open/close/force/destroy) | `VoxelCell.door_state` | SQLite via CampaignRepository |
| Search result (find secret door, find trap) | `door_detected = true` / trap detected flag | SQLite |
| Disarm trap | Trap disabled flag | SQLite |
| Spike / wedge / remove | `DungeonSessionState` | Per-dungeon-visit only |
| Light source state | Per-entity light state in `DungeonLightManager` | SQLite (entity inventory + active source) |
| Control group assignment | `DungeonSessionState` group dictionary | Per-dungeon-visit only |
| Idle behavior change | `DungeonSessionState` idle dictionary | Per-dungeon-visit only |
| Loot pickup / drop | Entity inventory + cell item list | SQLite (when loot is wired per L-1) |
| Carry downed character | Carried entity becomes inventory item; encumbrance recalc | SQLite |
| Drop carried character | Removes from carrier inventory; places in current cell | SQLite |
| Bash door (destroyed state) | `door_state = "destroyed"`, `passable = true`, `blocks_los = false` permanently | SQLite |

---

## 16. Open questions

- **O-DM-1.** ~~Where does marching order live — dungeon UI or Party tab?~~ **Resolved (v2):** Party tab Formation sub-tab exclusively. Dungeon UI consumes only.
- **O-DM-2.** ~~Should the per-selection unit info panel duplicate Character tab content?~~ **Resolved (v2):** No. Information lives in SessionStatusBar (at-a-glance) and Character tab (full sheet). Dungeon UI does not host a duplicate panel.
- **O-DM-3.** ~~Should Trade and Loot have their own dual-pane modal?~~ **Resolved (v2):** No. Both route through the Inventory tab (notebook tab #2) once Phase γ lands.
- **O-DM-4.** ~~Standalone notification log vs. Unified Log?~~ **Resolved (v2):** Unified Log v2 is canonical. Dungeon UI emits EventBus signals; Unified Log subscribes.
- **O-DM-5.** Trade-adjacency wiring (L-2). Default: gate Trade option on `VoxelGrid.is_adjacent`. Confirm behavior when the player wants to "send" an item across the party — does the Inventory tab support multi-hop transfers when carriers aren't adjacent, or does the player have to physically rearrange? Default proposal: **no multi-hop**; carriers must be adjacent. Aligns with verisimilitude goal in voxel arch §5.
- **O-DM-6.** Loot pile carrier representation (L-1). When items drop on the floor (Drop Item, monster death loot, container open), how are they represented? Default proposal: an invisible "floor carrier" entity per cell, registered in `LocationCacheManager`, with infinite capacity. Adjacency rules apply identically to player carriers. Confirm before wiring.
- **O-DM-7.** Trigger Trap tool gating (L-8). Default proposal: any character carrying a `pole_10ft`, `crossbow_*`, `bow_*`, or any thrown weapon (rocks, daggers) qualifies for safe-trigger. Greyed otherwise.
- **O-DM-8.** Talk gating (L-9). Default proposal: gate on `entity.intelligence >= 3` (animal-level), with a separate gate for hostile-but-intelligent creatures requiring a Diplomacy or Intimidate proficiency to even surface the option. Confirm.
- **O-DM-9.** Number-key collision in `DUNGEON_EXPLORE` (clock-speed vs. control groups). Current resolution: control-group recall wins; clock-speed in dungeon context via mouse + Space. Confirm this stands or specify F1-F4 fallback.
- **O-DM-10.** Group Options Panel formation modes (L-14). Should column / line / wedge / circle be exposed here, OR is formation a per-party concern that lives in the Party tab Formation sub-tab? Default proposal: **per-party in Party tab**; Group Options Panel does not duplicate. The control group is an RTS selection, not a formation unit. Confirm.

---

## 17. Build guidance for Claude Code

### 17.1 Already-shipped components to NOT rebuild

These are the canonical implementations. New work integrates with them rather than replacing:
- `DungeonContextMenuBuilder` (pure-logic option builder — accept it as the contract)
- `DungeonOrderManager` (single-slot order queue)
- `DungeonMapController` (move queuing, door interaction, fog updates, claim-based collision)
- `MovementResolver` (pathfinding)
- `VoxelMapData` / `VoxelGrid` / `VoxelCell` (spatial substrate)
- `DungeonLightManager` (light source lifecycle)
- `FogRevealEngine` (fog computation)
- `VisibilityManager`, `LevelStripWidget`, `OffscreenPartyIndicators` (multi-level UX)
- `DungeonSessionState` (per-visit state)

### 17.2 New work for v2 alignment

1. **Wire L-1 (loot visibility).** Build floor-carrier registration in `LocationCacheManager`; expose `has_ground_items(cell) -> bool`; replace the TODO at `dungeon_context_menu_builder.gd:53`.
2. **Wire L-2 (trade adjacency).** Add `VoxelGrid.is_adjacent(selected_pos, target_pos)` gate to `_build_entity_options` Trade branch. Disabled-tooltip: "Move adjacent to trade."
3. **Wire L-8 (Trigger Trap tool gating).** Inventory check for `pole_10ft` or thrown-weapon items.
4. **Wire L-9 (Talk gating).** Check `entity.intelligence` and `entity.hostility` flags.
5. **Wire context-menu trade/loot opens to Inventory tab.** When Trade or Loot is dispatched, fire `EventBus.notebook_open_requested("Inventory")` + `notebook_active_entity_requested(target_id)` per `gdd-management-notebook.md` §8.4.
6. **Migrate notification routing.** Audit existing dungeon-context log emissions; ensure all route to `EventBus` signals consumed by Unified Log per `gdd-unified-log-panel.md` §3. Deprecate any direct writes to legacy `GameLogPanel`.
7. **Implement L-10 (elf casual inspection).** Per `gdd-realtime-scheduler.md` §6.6 spec.
8. **Refactor L-11 (per-level wandering checks).** Per scheduler §6.7.

### 17.3 What to NOT touch

- The pure-logic menu builder's input contract: `(selected_ids, target_cell, map, party_data, session_state, light_manager) -> Array[Dictionary]`. Stable API.
- The per-visit nature of `DungeonSessionState`. Control groups, idle behaviors, spike/wedge, and pick-lock-failure memory are dungeon-visit-scoped, not campaign-persistent.
- The renderer-tween movement layer and its `movement_cell_reached` signal — that's the single mechanical seam between visual and logical state per scheduler §3.

---

## 18. Revision history

- **v2, 2026-04-30 — Architecture refresh.** Substantial rewrite to align with the management-notebook architecture, voxel-tactical migration, Unified Log v2, and the settled claim-based occupancy model.
  - **Cut:** Standalone Unit Info Panel (§5.1 v1 — now SessionStatusBar + Character tab); Group Options Panel marching-order section (now Party tab Formation sub-tab); Marching Order Behavior section (same); standalone Notification Log (now Unified Log v2); standalone Loot Panel and Trade dual-pane modal (now Inventory tab).
  - **Updated:** Spatial model from 2D (`Vector2i`) to 3D (`Vector3i`) throughout; adjacency to 3D Chebyshev ≤ 1; cell occupancy to claim-based per scheduler §6.4; door tooling to match code (axe required for bash, iron-spikes/wooden-stakes + hammer for spike/wedge, crowbar interaction with remove); bash duration to house-rule 1 turn for all wooden doors per `_bash_door_turns()`; pick-lock to per-character per-lock failure memory; open-locks classes to thief-only per `CLASSES_WITH_OPEN_LOCKS`.
  - **Added:** Multi-level UX section (focus level, Level Strip Widget, dither/dim/hide, auto-focus on cross-level events, multi-level fog, click-confirm on non-focused levels). Cross-surface integration section (notebook/inventory/log/party-tab/SessionStatusBar handoff). Build status section enumerating shipped components and remaining wiring (L-1 through L-14). Phase α/β/γ slotting.
  - **Reframed:** Scope explicitly narrowed to dungeon-context interaction patterns. All structural skeleton handed off to canonical owners with one-line pointers.
  - **Stale references fixed:** `gdd-realtime-scheduler.md §5.8` → §6.8; `DungeonOrderManager` confirmed real (was queried as undefined symbol); section-numbering bugs (§3.3.5 after §3.3.3, §3.4 after §3.5) repaired in the new structure.
- **v1, 2026-04-14 (approx).** Original draft. Owned a wider scope including unit info panel, notification log, marching order, dual-pane loot/trade modals, single-level fog and camera. Predated voxel-tactical migration, management notebook architecture, and Unified Log v2. Flagged for rewrite per `gdd-ui-architecture.md` §9.
