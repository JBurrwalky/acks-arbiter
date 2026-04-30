# GDD: Real-Time-with-Pause Game Clock & Event Scheduler

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Draft v2 — requires approval before build
**Replaces:** v1 of this document; design brief §8.3 simultaneous-declaration day-cycle scheduling; build plan E-2 session runner state machine concept
**Depends on:** `gdd-voxel-tactical-architecture.md` (3D voxel grid spatial substrate for the dungeon and combat layers), Timekeeping autoload (built), EventBus (built), CampaignRepository (built), DiceSystem (built)
**Blocks:** E-2 session runner implementation, all exploration and domain loop work, dungeon movement simulator implementation
**Last updated:** 2026-04-30

---

## 1. Overview

The game operates on a continuously advancing in-game clock that the player can pause, slow, or accelerate. All entities (parties, armies, construction projects, domain ticks, NPC activities) operate concurrently on this shared clock. The player issues orders to their entities, the clock advances, and events resolve when their scheduled timestamps arrive. The game auto-pauses when something requires player attention.

This replaces the previous simultaneous-declaration turn-based model where all parties declared activities and then resolved in sequence. The new model is inspired by Paradox grand strategy games (Crusader Kings, Europa Universalis): a living world clock with queued orders and interrupt-on-event.

The architecture has **two cooperating simulation layers**:

1. **The EventScheduler** — a discrete-event priority queue. It is the master clock and authoritative for all coarse-grain events: travel arrivals, action completions, scheduled checks, domain ticks, light timers, construction milestones. Hex map travel and city node-graph travel resolve entirely in this layer.
2. **The Movement Simulator** — a fixed-rate continuous-tick layer that runs underneath the scheduler when the dungeon layer is active. It advances unit positions on the voxel grid at a fixed cadence, supports RTS-style group control with marching order and pass-through, and emits events back into the scheduler when its tick produces an event-worthy state change (entering a triggerable cell, crossing a passive-detection radius, falling).

Combat remains a turn-based sub-game. When combat triggers, the master clock pauses globally; combat resolves in its own turn-ordered loop; on combat end, the master clock leaps forward by combat's elapsed duration and resumes.

---

## 2. Core Architecture: The Event Scheduler

### 2.1 Concept

The **EventScheduler** is a priority queue of future events, each keyed to a game-time timestamp (in elapsed rounds, matching Timekeeping's internal representation). The game loop advances the clock toward the next event in the queue, pops it, resolves it, and repeats. If resolution creates new events, those are inserted into the queue. If resolution requires player input, the game pauses.

This is the single replacement for the session runner state machine. Instead of discrete states (WILDERNESS_EXPLORE, DUNGEON_EXPLORE, SETTLEMENT_EXPLORE), the game is always in one mode: **clock is running, events are resolving.** Context (wilderness, dungeon, city) is a property of each entity, not a global game state.

### 2.2 Event Structure

Each scheduled event contains at minimum:

- **timestamp:** Absolute game time (in elapsed rounds) when this event fires
- **event_type:** String identifier from a registered vocabulary (e.g., `"travel_arrival"`, `"wandering_monster_check"`, `"construction_complete"`, `"domain_month_tick"`)
- **entity_id:** The entity this event belongs to (party ID, army ID, domain ID, etc.)
- **payload:** Dictionary of event-specific data (destination hex, target voxel cell, etc.)
- **priority:** Tiebreaker for events sharing the same timestamp (lower = resolves first)

### 2.3 Priority Tiebreaker Rules

When multiple events share the same timestamp, resolve in this order:

1. **Environmental/world events** (weather changes, dawn/dusk, season) — priority 0
2. **Scheduled checks** (wandering monster rolls, encounter checks) — priority 10
3. **Entity arrivals and completions** (travel arrival, search complete, construction done) — priority 20
4. **Triggered consequences** (combat start, trap trigger, domain event) — priority 30

Within the same priority tier, resolve by entity_id alphabetically (deterministic, arbitrary, consistent).

### 2.4 Clock Advancement

The game loop operates as follows:

```
while clock_is_running:
    next_event = scheduler.peek()
    if next_event is null:
        # Nothing scheduled — wait for player input
        pause()
        continue

    # Compute how far to advance
    rounds_to_advance = next_event.timestamp - Timekeeping.get_elapsed_rounds()

    # If the movement simulator is active, advance it in tick-sized
    # increments up to rounds_to_advance, with each tick possibly
    # injecting new events into the scheduler.
    if movement_simulator.is_active():
        movement_simulator.advance_to(next_event.timestamp)
        # The simulator may have inserted earlier events; re-peek.
        next_event = scheduler.peek()
        rounds_to_advance = next_event.timestamp - Timekeeping.get_elapsed_rounds()

    if rounds_to_advance > 0:
        Timekeeping.advance_rounds(rounds_to_advance)
        # Boundary signals (dawn, dusk, day_changed) fire naturally;
        # their handlers may insert new events into the queue.

    # Pop and resolve
    event = scheduler.pop()
    result = resolve_event(event)

    if result.requires_player_attention:
        pause()
        present_event_to_player(result)
```

The player can also pause at any time manually. While paused, the player can issue new orders, which insert/replace events in the queue.

### 2.5 Clock Speed Controls

The player controls clock speed via UI buttons or hotkeys:

- **Pause** (spacebar): Clock stops. Player issues orders freely.
- **1x**: Real-time tick (1 game round per ~2 seconds — tunable)
- **2x**: Double speed
- **5x**: Fast forward (useful for long travel, construction, downtime)
- **Max**: Advance instantly to next event (skip visual interpolation)

At higher speeds, the renderer's visual interpolation can run faster (skip frames) or compress, but the mechanical resolution is identical regardless of speed — the scheduler doesn't care about real-world time, only game-time timestamps. The movement simulator's logical tick rate is in *game time* (§3.2), so it produces the same logical state at any clock speed.

### 2.6 Two-Layer Architecture (Scheduler + Simulator)

The EventScheduler handles discrete events: things that happen at a known timestamp. Travel arrivals, action completions, domain ticks, scheduled rolls. These are correctly modeled as priority-queue entries.

Continuous-grain phenomena — unit movement on the voxel grid, group pathing through narrow corridors, real-time pass-through and congestion — fight the discrete-event model. They are correctly modeled as a **fixed-rate simulation tick**.

The two layers cooperate:

- **The scheduler is the master clock.** Game time advances only via `Timekeeping.advance_rounds(N)`, called from inside the scheduler loop.
- **The simulator runs underneath the scheduler when active.** Between the current clock position and the next scheduled event's timestamp, the scheduler asks the simulator to advance by tick-sized increments.
- **Simulator ticks may emit events.** When a tick produces an event-worthy state change (a unit reaches a cell with a passive-detection trigger, a unit falls off a ledge, two units' positions become adjacent for an interrupt purpose), the simulator inserts a scheduled event back into the queue. The scheduler then re-evaluates `peek()` and may resolve the simulator's event before the originally-targeted one.
- **Movement is not pre-scheduled.** Per-cell unit movement does NOT generate `cell_arrival` events at queue time. The simulator computes positions tick by tick. Only event-worthy boundary crossings become events.
- **Action durations remain scheduled.** Searching a cell, picking a lock, listening at a door — these have known durations from ACKS rules and remain scheduled events. The simulator does not handle them.

This split keeps the scheduler queue small and bounded (typical case: dozens of events, never per-cell-arrival explosions), and keeps the simulator simple (just position advancement; no time bookkeeping).

The simulator activates when the player has an entity in a context that requires per-tick movement — primarily the dungeon layer. It deactivates when no such context is active (pure overworld or city play). See §3.5.

---

## 3. Movement Simulator (Continuous-Tick Layer)

### 3.1 Concept and Rationale

The Movement Simulator is a fixed-rate game-time tick that advances unit positions on the voxel grid (`gdd-voxel-tactical-architecture.md`) when the dungeon layer is active. It is the engine that makes RTS-style real-time-with-pause control feel responsive while preserving the deterministic, voxel-aligned simulation the rest of the engine depends on.

It exists because:

- ACKS-relevant queries (3D Chebyshev adjacency, voxel LOS, fog of war, engagement, passive detection, inventory adjacency) all require discrete voxel positions per `gdd-voxel-tactical-architecture.md` §16.9. We must NOT abandon voxel-snapped logical state.
- RTS-style movement (continuous response to right-click orders, group pathing, interrupt-on-trigger) does not map cleanly to discrete pre-scheduled cell-arrival events. Trying to express it that way produces constant cancellation/re-scheduling under congestion and intersecting paths.
- The cleanest solution is the textbook RTS pattern: logical state ticks at a fixed cadence; visual state interpolates between ticks for smooth animation.

### 3.2 Tick Rate and Clock Integration

The simulator runs at **10 logical ticks per game round** = 1 tick per game-second (since an ACKS round is 10 seconds per `acore_combat_and_wounds.xml`). At 1× clock speed (1 game round ≈ 2 real-time seconds), each tick is ≈ 200 ms of real time. At 5× speed, each tick is ≈ 40 ms.

The tick rate is in **game time**, not real time. This means clock speed affects how many ticks happen per real-world second, but produces identical logical state at any speed. A unit moving 60' in combat speed (12 cells) takes 1 round = 10 ticks = 1.2 cells per tick on average; pathing produces a deterministic sequence of cell occupancies regardless of clock speed.

The scheduler advances the simulator via `movement_simulator.advance_to(target_timestamp)`. The simulator runs ticks until either:

1. It reaches `target_timestamp` (no event to inject); or
2. A tick produces an event-worthy state change, in which case it inserts the event into the scheduler and returns control. The scheduler re-peeks and may resolve that event next.

### 3.3 Logical vs. Visual Position

Each unit has two position representations:

- **`logical_position: Vector3i(col, row, level)`** — voxel-snapped, updated only on tick boundaries. All ACKS queries use this. Adjacency, LOS, fog reveal, engagement, passive detection radii, inventory adjacency — all of these consult the logical position.
- **`visual_position: Vector3`** — interpolated at render time between the unit's previous tick logical position and current tick logical position, based on real-time elapsed within the tick interval. This is what the renderer uses to draw the token.

At 60 FPS rendering with 200 ms ticks, the renderer produces 12 interpolated frames per cell-step, yielding smooth gliding motion. Logical state remains voxel-aligned at all times.

### 3.4 Sub-Cell Visual Offsets and Continuous Facing

Two further visual refinements that do NOT affect logical state:

- **Sub-cell offset** — when multiple units occupy adjacent cells in a tight formation (e.g., a group on a stair landing or in a small room), each unit's visual_position can be offset within its own cell by a small amount (≤ 0.4 world units = 2') based on its formation slot index. This prevents the visual stacking that the voxel grid's 5' resolution would otherwise produce. Logical position remains the cell center.
- **Continuous facing** — a unit's facing is a float radian (0 to 2π), interpolated smoothly when the unit changes direction. Cardinal-direction-snapping is not required at the logical level; ACKS combat does not depend on facing.

### 3.5 Active Scope (When the Simulator Runs)

The simulator activates when the camera is on the dungeon layer AND at least one player-controlled entity is operating in that dungeon. Specifically:

- **Active:** Player's party (or any group) is exploring a dungeon — simulator runs each tick to advance unit positions.
- **Inactive:** Player is on the hex map (overworld). Travel resolves as scheduled `travel_leg` events; visual interpolation of party tokens between hex arrivals is the renderer's job and does not require the simulator.
- **Inactive:** Player is in a city/settlement (node-graph). Travel resolves as scheduled edge-traversal events.
- **Inactive (paused):** Combat is in progress. The simulator pauses for the duration of combat (§6.8); combat is fully serialized.

When the simulator is inactive, the scheduler's clock advancement is purely event-driven (no per-tick work). When it activates, it begins ticking from the current Timekeeping timestamp and advances in lockstep with the scheduler thereafter.

If multiple parties are simultaneously in different dungeons or different levels of the same dungeon, only the one currently in camera focus runs the simulator visibly. The others have their dungeon-context activity tracked at coarser resolution: they emit and consume scheduled events (action completions, encounter checks) without per-tick position updates. When the player switches camera focus to a different party, that party's simulator state is reconstructed from its current logical positions and ticking resumes for the focused entity.

### 3.6 Performance Budget

A typical dungeon scene has ≤ 25 player-controlled units plus ≤ 25 monsters per encounter. Per tick: each unit performs an O(1) position update plus O(neighbors) pathing-progress check. At 10 ticks/round, this is 50 units × 10 ticks = 500 unit-ticks per game round, each doing a handful of voxel grid lookups. Performance is never the bottleneck at ACKS scale.

Pathfinding (BFS or AStar3D per `gdd-voxel-tactical-architecture.md` §17.2) runs only on path computation, not on every tick. Once a path is computed, the simulator just walks the unit through the path's cells one tick at a time.

### 3.7 Order Cancellation Under the Simulator

When the player cancels a unit's movement order, the simulator clears that unit's target and current path. The unit stops at its current `logical_position` at the next tick boundary. No event removal is needed (movement was never scheduled as events). This is structurally simpler than the v1 model that required scheduler cancellation for movement.

Action cancellation (search, lock pick, etc.) still works through the scheduler — those remain scheduled events with timestamps, and `EventScheduler.cancel(event_id)` removes them.

---

## 4. Overworld Layer (Wilderness & Domain)

### 4.1 Party Movement

The player selects a party and right-clicks a destination hex (or sets waypoints). The system calculates travel time based on: terrain movement cost, party speed (slowest member), encumbrance, mounts, proficiency modifiers (Navigation, Endurance, Running), and weather.

This produces a sequence of **travel_leg** events — one per hex boundary crossing. Each travel_leg event's timestamp is the arrival time at the next hex. On arrival:

1. Fog of war updates for the new hex.
2. Encounter check fires (1d6 vs. terrain threshold per ACKS rules). If encounter triggers → auto-pause, resolve encounter.
3. If no encounter, the next travel_leg event is already in the queue.

Getting-lost checks fire once per day of travel (scheduled event). If lost, the party's remaining travel_leg events are recalculated with a random deviation.

**Visual interpolation:** between two travel_leg events at timestamps T1 and T2, the renderer draws the party token at a position interpolated along the path from hex A to hex B based on `(now - T1) / (T2 - T1)`. The logical position remains discrete (hex A until T2, then hex B) — only the rendered token slides smoothly. This is the same logical/visual split the dungeon simulator uses (§3.3), applied at hex resolution. No scheduler or simulator changes are required for it; it is purely a rendering concern.

### 4.2 Forced March

If travel extends past the normal daily travel window, a forced march event fires. CON checks per ACKS rules (with Endurance proficiency modifier). Failure → exhaustion effects. The player can preemptively cancel remaining travel legs to camp instead.

### 4.3 Camping and Watches

The player orders a party to camp. This inserts a sequence of watch events (typically 3 watches of ~8 hours each, configurable by party). Each watch boundary fires an encounter check. Dawn and dusk signals from Timekeeping interact naturally — the party wakes at dawn if they started resting at dusk.

### 4.4 Domain Ticks

Domain monthly resolution is a scheduled event at each month boundary. When it fires, it resolves revenue, population, morale, construction progress, garrison costs, and domain encounters per ACKS rules. The result is presented to the player (auto-pause), then the clock resumes.

### 4.5 Armies and Long-Duration Activities

Armies on the march work identically to party movement — travel_leg events per hex. Construction projects have a `construction_complete` event at their calculated completion date. Henchmen on missions have mission_complete events. Magic research has research_complete events. All just entries in the same scheduler queue.

### 4.6 Cross-Entity Interaction

If a party enters a hex containing a hostile army, or two armies converge, the scheduler detects the spatial collision at travel_leg resolution time and triggers an encounter. No special logic needed — the event resolver checks for entities sharing a hex after each arrival.

---

## 5. City Layer (Settlement as Node Graph)

### 5.1 Concept

Settlements are not rendered as walkable maps. Instead, a settlement is a weighted node graph where:

- **Nodes** = Points of Interest (taverns, temples, markets, guildhalls, NPC residences, city gates, etc.)
- **Edges** = Travel connections between nodes, weighted by travel time in blocks (abstract distance units)

The player sees a list of available PoIs (or optionally a simple node-graph diagram for orientation). They select a destination, and the party's travel time is calculated from edge weights. The system tracks blocks traveled for timekeeping and encounter rolls.

### 5.2 Mechanical Integration

- **Travel time:** Each edge has a weight in blocks. Movement speed in blocks/turn is derived from the party's movement rate. Travel between nodes consumes time via Timekeeping, scheduled as a single `node_arrival` event per traversal.
- **Encounter checks:** Urban encounter checks per ACKS rules fire based on blocks traveled (or per the district's encounter frequency).
- **District modifiers:** Each node belongs to a district. District properties (encounter tables, law enforcement response, market class) apply at that node.
- **Time-of-day effects:** Certain PoIs are only available during business hours. Taverns have different encounter tables at night. Dawn/dusk signals from Timekeeping drive this naturally.

### 5.3 Activities at Nodes

When the party arrives at a PoI, the available activities depend on the PoI type: shopping, hiring, information gathering, carousing, spell research access, criminal hijinks, temple services, etc. Each activity has a known duration. The player selects an activity, it becomes a scheduled event, the clock advances, the activity resolves.

### 5.4 Entering and Leaving Settlements

A settlement is attached to a hex. The party enters the settlement by arriving at that hex and choosing to enter. From inside the settlement, the party can exit to the hex map at any city gate node. No time-bubble or synchronization issues — the settlement is just a different spatial context for the same clock.

The Movement Simulator does not run while a party is in a settlement. Travel between nodes is a single scheduled event per edge.

---

## 6. Dungeon Layer (Real-Time-with-Pause Exploration)

### 6.1 Concept

Dungeon exploration operates on the same event scheduler as the overworld, but with two additions: per-cell unit positions advance via the Movement Simulator (§3) at fine-grained ticks, and the spatial substrate is the 3D voxel grid defined in `gdd-voxel-tactical-architecture.md` (5' cube cells, `Vector3i(col, row, level)` coordinates). The player controls individual units (or groups of units) on the voxel grid. Units move in real-time as the simulator ticks. Activities (searching, listening, forcing doors, picking locks) are queued actions with known durations that resolve when their timer completes — these are scheduled events, not simulator state.

A dungeon is a single coordinate space spanning all its levels (per `gdd-voxel-tactical-architecture.md` §12). The party may be split across multiple levels at any time. The camera shows one focus level at a time per the Visibility Manager (`gdd-voxel-tactical-architecture.md` §16); the simulator advances all party members on all levels every tick regardless of focus.

### 6.2 Movement Modes

ACKS movement modes (per `acore_adventures_and_encounters.xml` and `gdd-voxel-tactical-architecture.md` §11) determine speed and passive behavior. Each unit (or group) has a current movement mode:

- **Exploration** (default): Movement at exploration rate (one-third combat speed). Passive detection checks active for eligible classes (dwarf construction detection, elf secret door sensing). Mapping occurs. Quiet movement.
- **Combat speed**: Full movement rate. No passive detection. No mapping. Weapons ready. Normal noise.
- **Running**: Double combat speed. No detection. No mapping. High noise (may trigger additional encounter checks or alert nearby monsters).
- **Flying / Burrowing / Climbing:** Apply per `gdd-voxel-tactical-architecture.md` §11.2–§11.4 for creatures with those modes.

The player can toggle movement mode per unit or per group. Mode affects which scheduled events the system generates — exploration mode generates periodic passive detection checks; combat speed and running do not.

### 6.3 Unit Groups (RTS-Style Control)

Units are controlled with standard RTS conventions per `gdd-dungeon-map-ui.md` §2:

- **Click** to select a single unit.
- **Shift+click** to add/remove units from selection.
- **Ctrl+[1–9]** to bind selected units to a control group.
- **[1–9]** to recall a control group.
- **Right-click** on a map cell to issue a move order (or bring up a context menu if the cell has an interactive object).

When a group moves, all members path toward the destination. **Group movement speed is always set by the slowest member.** Members move in a column through corridors, following the group's designated **marching order** (not a "leader" — just front-to-back ordering). The player sets marching order per group, typically with the thief or highest-AC member at the front.

Marching order determines:

- Who encounters traps first.
- Who is in melee range first when combat triggers.
- Who makes first contact with doors, obstacles, and NPCs.

A group may span multiple levels (e.g., a thief scouting a floor below the rest of the party). The Level Strip Widget (`gdd-voxel-tactical-architecture.md` §16.4) shows where each member is. Selecting a control group whose members are on different levels does not auto-change camera focus; the player navigates between levels via PgUp/PgDn or by clicking portraits.

### 6.4 Pathing, Unit Cell Occupancy, and Pass-Through

Pathfinding operates on the voxel grid via BFS or AStar3D over `VoxelGrid.get_neighbors_3d()` (per `gdd-voxel-tactical-architecture.md` §17.2). The path is computed once when the move order is issued; the simulator walks the unit along the path tick by tick.

**Cell occupancy rule (project-designed):**

The exploration simulator enforces strict per-cell occupancy limits. The rule serves two purposes simultaneously: it prevents visual stacking glitches (10 units ghosting into a single doorway cell) and it enforces a deliberate physical-space constraint that matches the game's verisimilitude goals.

The rule, in priority order:

1. **A cell may contain at most two living non-incapacitated units at any tick boundary.** The cap is two; never more.
2. **A cell may contain at most one living non-incapacitated unit at end-of-tick** (i.e., once movement is fully resolved). The two-unit case is transient — it exists only when one unit is mid-pass-through.
3. **Pass-through is allowed only one unit at a time per cell.** A moving unit may enter a cell containing one other friendly unit; that constitutes a pass-through. The moving unit must exit that cell to its next path step by the next tick (cannot remain in a shared cell across tick boundaries).
4. **A unit cannot pass through a cell that already contains two units.** If the moving unit's next path step contains two living units, the moving unit stops in its current cell and re-evaluates next tick.
5. **Hostile units block passage entirely.** A unit attempting to enter a cell containing any living non-incapacitated hostile unit stops in the cell before. Combat may trigger (§6.8).
6. **Incapacitated units (unconscious, dead, paralyzed, restrained, etc.) do not count.** They contribute nothing to occupancy or pass-through limits. Other units may freely pass through and end a tick on a cell containing only incapacitated units. Visually, the moving unit is rendered on top of the incapacitated unit.

The "one pass-through at a time" rule (3) directly prevents conga-line glitches: at most two units occupy any cell, so traffic through a doorway naturally serializes — the third unit waits one tick at the cell before the doorway, then advances when the first has cleared. This serialization is intentional both for visual quality and for preserving the spatial feel that the voxel grid is meant to represent.

Combat-specific pass-through rules (e.g., per-round limits, friendly-fire risk) are enforced by the combat system per ACKS combat rules during turn-based combat, not by the exploration simulator.

**Group movement and congestion:**

In narrow corridors (1-2 cells wide), a group automatically forms a single-file column ordered by marching order. Each member targets the cell currently occupied by the member ahead of them; the front-of-column member targets the destination. As the front advances, the column follows naturally.

In open rooms or wide corridors, a group can spread to a wider formation if space allows. Exact formation logic (column, wedge, line) can be a later refinement — the simple "follow the unit ahead" pattern is sufficient for initial build.

If two groups must pass each other in a narrow corridor, both groups treat each other as friendly for pass-through purposes (assuming they are friendly). One group may need to step into adjacent cells to clear the corridor. The simulator does not auto-resolve this; the player can issue a manual "step aside" order or wait for the simulator to find equilibrium.

### 6.5 Queued Actions and Activity Resolution

When a unit (or group) reaches an interactive cell (door, chest, suspicious wall, etc.), the player right-clicks to open a context menu of available actions per `gdd-dungeon-map-ui.md`. Each action has a deterministic duration from ACKS rules:

| Action | Duration | Source |
|--------|----------|--------|
| Search a 10'×10' area | 1 turn (10 min) | `acore_adventures_and_encounters.xml` |
| Listen at door | 1 round (10 sec) | `acore_adventures_and_encounters.xml` |
| Force stuck door | 1 round per attempt | `acore_adventures_and_encounters.xml` |
| Pick lock (thief) | 1 turn | `ax_thief_skill_update.xml` |
| Find/remove traps (thief) | 1 turn | `ax_thief_skill_update.xml` |
| Hide in shadows (thief) | — (instant, lasts until broken) | `ax_thief_skill_update.xml` |
| Move silently (thief) | — (continuous while moving) | `ax_thief_skill_update.xml` |

When the player selects an action, it becomes a scheduled event with a timestamp = now + duration. The clock advances, and on completion the result resolves (success/fail roll). If the action was noisy (bashing a door), it may trigger an immediate encounter check.

A unit's **default action** when reaching an obstacle can be configured: e.g., the lead unit in a group can be set to "auto-listen at doors" or "auto-stop and wait for orders." This reduces micromanagement.

### 6.6 Detection: Passive vs. Active

**Active detection** (the default for most situations): The player must explicitly order a unit to search. Searching takes 1 turn per 10'×10' area per `acore_adventures_and_encounters.xml`. Results are revealed on completion. No automatic searching occurs.

**Passive detection** (class features only): These fire automatically when an eligible unit's logical position enters a trigger volume of a hidden feature, without consuming extra time:

- **Dwarves:** Detect construction tricks, sloping passages, shifting walls — 2-in-6 chance when passing within 10' (per `acore_basics_and_characters.xml` / `acore_demihuman_classes.xml`)
- **Elves:** Detect secret/hidden doors — 2-in-6 chance when passing within 10' (per `acore_demihuman_classes.xml`)
- Other class-specific passives as defined in the ACKS source XML.

**Trigger volume definition:** A "within 10 feet" radius converts to **3D Chebyshev distance ≤ 2 cells** from the hidden feature's cell (each cell is 5'). This forms a 5×5×5 voxel volume centered on the feature, totaling up to 124 cells (excluding the feature's own cell). A passive detection check fires when a qualifying unit's logical_position enters any cell in that volume on a tick boundary.

**Occlusion by walls, floors, ceilings, and doors:** The trigger volume is bounded by line-of-passage. Detection cannot occur through solid voxels (`solidity: solid`), through closed/locked/stuck doors, or through floors/ceilings whose `floor_type` is not `"none"`. The implementation is a 3D BFS from the feature's cell, expanding only through air cells with no blocking face between them, terminating at depth 2 OR at any blocking surface. Cells reachable by this BFS are the qualifying trigger cells.

This means a dwarf walking on Level 1 cannot detect construction tricks above on Level 2 if there is a stone floor between — the floor blocks detection. A dwarf in a room with an open archway can detect tricks in the adjacent room if the trick is within 2 cells. A dwarf cannot detect through a closed door even if the trick is within 2 cells through the door.

**Resolution:** On trigger, roll the detection check. On success, auto-pause and reveal the discovery. On failure, nothing happens — the player does not know the check occurred. Information stays hidden.

### 6.7 Wandering Monster Checks

Per `acore_adventures_and_encounters.xml`, dungeon wandering monster checks occur every 2 turns (120 rounds = 1,200 game-seconds).

**Future direction (non-blocking):** Random encounter spawning is a tabletop simulation of what is, in fiction, persistent monster patrols and territorial behavior. A future revision of the dungeon engine will replace these random spawn-on-roll checks with **persistent patrolling monsters and designated patrol spawn-points** living in the dungeon's faction graph (`gdd-dungeon-factions.md`). Until that lands, the per-level random check described below is the placeholder. The implementation should keep the wandering monster system loosely coupled — a single registered handler for `wandering_monster_check` events — so that future replacement is a swap-out, not a rewrite.

**Per-level scheduling:** A wandering monster check fires for **every dungeon level that contains at least one party member**, independently. If the party is split across two levels, two checks fire per 2-turn cycle (one per level). If a party member moves to a third level, that level begins generating its own checks.

The scheduler maintains a `wandering_monster_check` event per occupied level, each scheduled 120 rounds from the moment a party member first entered that level (or 120 rounds since the last check on that level). When the last party member leaves a level, that level's pending check is canceled.

**Resolution:**

1. Roll 1d6 per level being checked. On 6+ for a level, a wandering monster is indicated on that level.
2. If indicated, determine the monster type from the dungeon level's wandering monster table.
3. Determine encounter distance and direction relative to the **nearest party member on that level** (not the party leader, not the centroid). Distance is measured from the spawning monster's cell to the nearest party member's cell on that level using 3D Chebyshev distance with LOS-bounding (per `gdd-voxel-tactical-architecture.md` §15).
4. Auto-pause. Present the encounter to the player.
5. If combat results, transition to turn-based combat (§6.8).

Modifiers apply: loud activities (bashing doors, fighting) may trigger additional ad-hoc encounter checks on the level where the noise occurred. Quiet or stealthy groups may receive a modifier. These are resolved as they arise, not pre-scheduled.

### 6.8 Combat Transition

When combat triggers in a dungeon (wandering monster, room encounter, trap, or hostile NPC):

1. **Auto-pause and globally halt the master clock.** All scheduler advancement stops. The Movement Simulator deactivates. No other entities tick. This is a stop-the-world transition: combat is fully serialized.
2. **Determine combatant scope (engagement zone).** Combatants are: all hostile entities involved in the encounter, plus all friendly party members on the trigger level who are EITHER within line-of-sight of any hostile entity OR within 12 cells (60' Chebyshev) of any hostile entity. Friendly entities outside this scope are NOT combatants. They remain at their current logical positions in their current activities, paused until combat ends. If they wish to join the fight, they must physically move into the engagement zone after combat ends and roll into a fresh encounter (which may or may not still exist depending on combat outcome).
3. **Snapshot positions.** Every combatant's current `logical_position` (Vector3i) becomes their starting position for combat.
4. **Determine surprise and encounter distance** per `acore_adventures_and_encounters.xml`.
5. **Enter turn-based combat mode.** The combat system operates on the same voxel grid. Initiative, movement, attacks, spells, morale — all per ACKS combat rules, resolved round by round.
6. **Combat ends** when one side is eliminated, flees, or surrenders.
7. **Resume the master clock.** Timekeeping advances by `(combat_rounds × 1 round)` to account for elapsed game time. The Movement Simulator reactivates.

   **Non-combatant action timers progress through combat.** Any scheduled action event (search, lockpick, listen, force door, construction, research, henchman mission, etc.) belonging to a non-combatant entity was scheduled with an absolute timestamp. When the master clock advances by combat duration on resume, those timestamps are crossed naturally. Specifically:
   - If a non-combatant's action timer would have completed *during* the combat window, the scheduler resolves that event immediately on combat-end, before normal ticking continues. The player sees the result presented after the combat outcome (e.g., "While combat raged in the next room, Bran finished picking the lock").
   - If a non-combatant's action timer is still in progress when combat ends, it remains scheduled at its original timestamp; the unit's progress simply ticked down by the combat duration.

   **Non-combatant movement does not progress through combat.** The Movement Simulator paused entirely during combat. A non-combatant who was walking from cell A to B at combat start is still in cell A (or wherever they last had a logical_position) at combat end, and the simulator resumes their motion from that cell. This is a simplification accepted for clarity — non-combatants don't drift while you're not watching them.

   Multiple overdue events are resolved in priority order (per §2.3) before normal ticking continues.

**Implication for v1 §5.10 multi-party time independence:** This is a change from v1 of this document. v1 said "the dungeon party's time advances independently" of an overworld party, implying separate clocks. v2 has a single master clock that pauses globally during combat — but the carve-out for scheduled events means non-combatant entities effectively continue *through* combat for any activity expressed as a scheduled event:

- Overworld travel (scheduled travel_leg events) — progresses; an overworld party may even arrive at their destination during another party's combat, and the arrival resolves immediately on combat-end.
- Construction, research, henchman missions, domain ticks — all scheduled events; all progress through combat.
- Action timers (search, lockpick, listen, etc.) for non-combatant party members — progress through combat.

What does NOT progress during combat is anything held in Movement Simulator state — i.e., non-combatant unit-level positions inside a dungeon. Those resume from where they paused. In practice this is invisible to the player: a non-combatant in a dungeon was sitting somewhere doing something, and they're still sitting there when combat ends.

The net effect: the multi-party world keeps ticking through combat almost everywhere it matters, with combat itself appearing as a brief stop-the-world moment from the perspective of parties not involved.

### 6.9 Light Source Tracking

Torches (6 turns), lanterns (24 turns per flask of oil), and other light sources are tracked as duration events in the scheduler. When a light source is lit, a `light_source_expired` event is inserted at the appropriate future timestamp. When it fires, the light goes out — auto-pause, notify player.

Continual Light spells and other permanent sources don't expire (no event needed; they just persist until dismissed or dispelled).

### 6.10 Dungeon Entry and Exit

A dungeon is attached to a hex or a settlement node. The party enters by choosing to enter from the overworld or city layer. From inside the dungeon, the party can exit at any entrance/exit cell (typically a `feature: stairs_up_*` cell that connects to the surface, or any cell flagged as an exit by the dungeon generator).

**Time reconciliation on exit:** The dungeon consumes real game time tracked by Timekeeping throughout the exploration. When the party exits, their timestamp is already correct — no time-bubble needed. The overworld clock is simply wherever Timekeeping says it is.

**Multi-party note:** If a different party is operating on the overworld while one party is in a dungeon, the dungeon party's time advances on the same master clock as the overworld party. Combat in either location pauses the master clock globally for the combat's duration; non-combat ticking is shared. The Movement Simulator may activate or deactivate as the camera focus changes between parties (per §3.5).

---

## 7. Auto-Pause Events

The game auto-pauses and requests player attention for:

- **Any encounter** (wandering monster, lair discovery, NPC meeting, urban encounter)
- **Combat trigger** (hostile encounter, trap damage, ambush)
- **Arrival at destination** (hex arrival, dungeon room entry with visible features, PoI arrival)
- **Activity completion** (search complete, lock picked, construction finished)
- **Discovery** (passive detection success, secret door found, trap detected)
- **Resource depletion** (torch burned out, rations exhausted, spell duration expired)
- **Status change** (party member drops to 0 HP, condition expires, level up)
- **Domain events** (monthly tick, domain encounter, construction complete)
- **Time boundaries** (dawn, dusk — configurable; some players may want these suppressed)
- **Cross-level events** (party member on a non-focused level triggers any of the above; the camera auto-focuses to that level per `gdd-voxel-tactical-architecture.md` §16.5)

Auto-pause events should be configurable. The player should be able to suppress low-priority pauses (e.g., "don't pause at dawn/dusk," "don't pause on routine travel arrivals") via a settings menu. High-priority events (combat, resource depletion, encounters) should always pause.

---

## 8. Order Interruption and Cancellation

The player can cancel or change orders at any time while paused:

- **Cancel travel (overworld):** Remove remaining travel_leg events for a party. The party stops at its current hex.
- **Redirect travel (overworld):** Cancel remaining legs, issue new destination. New travel_leg events replace the old ones.
- **Cancel movement (dungeon):** Clear the unit's target and current path in the Movement Simulator. The unit stops at its current logical_position at the next tick. No event removal — movement was never scheduled as events.
- **Cancel activity:** Remove a queued action event (e.g., cancel a search in progress). The time already elapsed is consumed; partial progress is lost (ACKS doesn't have partial search progress — you either complete the search or you don't).
- **Change movement mode:** Immediate effect on the unit's speed. Recalculate path timing for any in-progress simulator movement. Recalculate arrival times for any queued overworld movement events.

Implementation: Each entity tracks which events in the scheduler belong to it. Cancellation is: remove all events for entity X of type Y, then optionally insert new ones. Movement Simulator state is tracked per-unit and cleared by a direct `simulator.clear_target(unit_id)` call.

---

## 9. What Changes From Current Design

### 9.1 Design Brief §8.1–8.3

The session runner concept shifts from a state machine with discrete exploration modes to a unified clock-and-scheduler. The design brief's session states (Wilderness Exploration, Urban Exploration, Dungeon Exploration, etc.) become *contexts* that an entity is operating in, not global game states. Multiple entities can be in different contexts simultaneously.

**§8.3 Timekeeping** revision: Replace "Each game day, all active parties declare intended activities simultaneously, then each party's day resolves in sequence" with the real-time-with-pause model described in this document.

### 9.2 Build Plan E-2

The session runner is no longer a state machine with states CAMPAIGN_SELECT → WILDERNESS_EXPLORE → DUNGEON_EXPLORE → etc. It becomes:

- **CAMPAIGN_SELECT** → still exists as a pre-session menu
- **SESSION_ACTIVE** → the single in-game state, running the event scheduler loop (and the Movement Simulator when the dungeon layer is active)
- **SESSION_END** → save and return to campaign select

All other "states" are entity-level contexts, not session-level states.

### 9.3 Timekeeping Autoload

The existing Timekeeping autoload is architecturally compatible with this design. It's already a passive clock advanced by external callers with multi-party support. The change is: instead of the session runner calling `advance_hours()` or `advance_turns()` directly after each player action, the event scheduler loop calls `advance_rounds(delta)` to reach the next event's timestamp, and Timekeeping's boundary signals fire naturally. The Movement Simulator does not directly call Timekeeping; it observes the timestamp via the scheduler.

No changes to Timekeeping's public API are anticipated.

### 9.4 Settlement Maps

The settlement layout system (`gdd-settlement-layout.md`) described walkable polygon-block maps with street-graph movement. This is replaced by the node-graph model described in §5. The GDD for settlement layout should be updated to reflect this simplification. Settlement *generation* (districts, PoI placement, NPC population) is unchanged — only the spatial representation and movement model changes.

### 9.5 Dungeon Exploration

The previous model was room-by-room turn-based exploration. v1 of this document replaced it with continuous real-time movement on the diamond grid. v2 (this revision) makes that explicit: dungeon movement is not pre-scheduled cell-arrival events but continuous-tick advancement via the Movement Simulator (§3) on the 3D voxel grid (`gdd-voxel-tactical-architecture.md`). The mechanical rules (search duration, encounter frequency, trap detection) are identical — only the engine architecture and pacing change.

### 9.6 Combat

Turn-based combat sequence is unchanged from ACKS rules. The new wrinkles introduced in v2:

- Combat globally pauses the master clock (§6.8). v1 left this implicit; v2 makes it explicit and accepts the multi-party time-independence trade-off.
- Combatant scope is defined by line-of-sight or 60' Chebyshev from any hostile, on the trigger level only. v1 had "all units in the dungeon enter combat" as an open question; v2 resolves it with the engagement zone definition.

### 9.7 Multi-Level Spatial Model

v1 referred to a "diamond grid" without an explicit 3D model. v2 consumes the 3D voxel grid from `gdd-voxel-tactical-architecture.md` for all dungeon and combat geometry. Detection radii are 3D Chebyshev with occlusion, wandering monster checks fire per occupied level, and the camera shows one focus level at a time per the Visibility Manager.

---

## 10. UI Implications

### 10.1 Clock and Speed Controls

A persistent clock display showing current game date and time, with speed control buttons (Pause / 1x / 2x / 5x / Max). Spacebar toggles pause. The clock display should be visible in all contexts (overworld, dungeon, city).

### 10.2 Entity Roster / Outliner

A sidebar or panel showing all active entities (parties, armies, domain projects, NPC missions) with their current activity, location, and ETA to next event. Click to select and center view on that entity. This is the Paradox "outliner" concept — essential for managing a living world with multiple concurrent activities.

### 10.3 Dungeon Control Bar

When viewing the dungeon layer, a control bar showing control groups (bound unit groups with portraits/icons), current marching order, movement mode toggle, and group status (HP, torch timer, active action). Standard RTS unit selection and control group hotkeys per `gdd-dungeon-map-ui.md`.

When a control group spans multiple levels, the control bar shows level badges next to each portrait so the player can see at a glance who is where. The Level Strip Widget (`gdd-voxel-tactical-architecture.md` §16.4) provides the canonical multi-level view.

### 10.4 Context Menus

Right-click on map cells (dungeon objects, hex map locations, settlement PoIs) opens a context menu of available actions per `gdd-dungeon-map-ui.md` §3. Actions are filtered by what's mechanically possible (thief skills only show for thieves, spell options only for casters, etc.).

### 10.5 Notification Feed

A scrolling notification feed showing resolved events: "Party Alpha arrived at Hex 0305," "Wandering monster check (Level 2): no encounter," "Construction on tower: 3 months remaining," "Torch burned out — Henchman Bran's area is now dark." This provides ambient awareness of the world ticking forward without requiring full attention to every event.

---

## 11. Build Guidance for Claude Code

### 11.1 What to Build First

The EventScheduler is the master clock backbone. It should be built as a standalone class (not an autoload — the session runner owns it) with a clean interface:

- `schedule(event) → event_id` — insert an event
- `cancel(event_id)` — remove an event
- `cancel_all_for_entity(entity_id, event_type?)` — bulk cancellation
- `peek() → Event or null` — inspect next event without removing
- `pop() → Event` — remove and return next event
- `get_events_for_entity(entity_id) → Array` — query scheduled events

### 11.2 Movement Simulator

The Movement Simulator is a separate buildable from the EventScheduler. Its interface:

- `activate(map_data: VoxelMapData, units: Array)` — bring the simulator online for a dungeon context
- `deactivate()` — release simulator state when exiting the dungeon
- `set_target(unit_id, target_pos: Vector3i)` — issue a move order; computes a path and stores it
- `set_group_target(group_id, target_pos: Vector3i)` — issue a group move with marching order
- `clear_target(unit_id)` — cancel an in-progress move
- `advance_to(target_timestamp)` — advance ticks toward target_timestamp; may inject events into the scheduler and return early
- `get_logical_position(unit_id) → Vector3i`
- `get_visual_position(unit_id, render_time) → Vector3` — interpolated for rendering

The simulator's tick loop checks each moving unit's next path step for occupancy (per §6.4), advances or waits accordingly, and detects passive-detection trigger entries, falling, and other event-worthy state changes. On detecting one, it schedules the event and returns to the scheduler.

### 11.3 What to Rework

- **Session runner (E-2):** Replace state machine concept with scheduler + simulator loop. If any session runner code exists, rework it.
- **Wilderness movement:** Calculate travel legs → schedule events → let the clock tick. No simulator.
- **Settlement spatial model:** Build as node graph from the start (per §5). No simulator.
- **Dungeon exploration:** Rework to scheduler + simulator architecture per §6. Movement is simulated per tick on `Vector3i` positions; actions are scheduled events.

### 11.4 What Stays the Same

- **Timekeeping autoload:** No API changes.
- **DiceSystem:** Unchanged.
- **CampaignRepository:** Unchanged interface; underlying schema gets `voxel_map_cells` per the voxel migration.
- **EventBus:** May gain new signals for scheduler and simulator events, but existing signals are stable.
- **Combat system (F-1):** Turn-based combat is unchanged. The only new interfaces are: combat receives the engagement-zone unit list and starting positions, and returns combat duration in rounds on completion.
- **Character data, generation, inventory:** All unchanged.
- **Voxel grid and Visibility Manager:** Defined in `gdd-voxel-tactical-architecture.md`. This GDD consumes them; it does not redefine them.

### 11.5 Loose Coupling Guidance

The scheduler should not know about the specifics of any event type. Event resolution should be handled by **registered event handlers** — subsystems register themselves as handlers for specific event_type strings. The scheduler pops an event, dispatches it to the registered handler, and receives back a result indicating: events to schedule next, whether to auto-pause, and what to present to the player.

The Movement Simulator should not know about the specifics of any event type either. When it detects an event-worthy state change, it constructs an event object with a registered event_type and inserts it via `EventScheduler.schedule()`. The handler for that event_type does the work.

This keeps both layers generic and allows new event types and movement triggers to be added without modifying scheduler or simulator code.

---

## 12. Open Questions

These do not block implementation, but should be resolved during build or playtest:

1. **Tick rate calibration.** §3.2 specifies 10 ticks/round as the starting value. If simulator-driven motion feels choppy, increase to 20 ticks/round (200 ms tick at 1× speed → 100 ms tick). If it feels too fast/expensive, decrease to 5 ticks/round. Re-evaluate after first dungeon playtest.

2. **Engagement zone radius.** §6.8 specifies LOS OR 12 cells (60' Chebyshev) as the combat scoping radius. Approved by Jedidiah 2026-04-30 as the starting value; will be revisited if playtest reveals problems. ACKS encounter distance is 2d6 × 10' = 20'-120' per `acore_adventures_and_encounters.xml`; the 60' Chebyshev value sits roughly mid-range.

3. **Multi-party time during combat — RESOLVED.** §6.8 globally pauses the master clock during combat, with the explicit carve-out that non-combatant action timers progress through the combat window (search, lockpick, construction, research, missions, etc. all complete on schedule). Non-combatant movement does not progress. Approved by Jedidiah 2026-04-30. This is a change from v1 §5.10's multi-party time-independence claim; design brief §8.3 should be updated to match.

4. **City node graph generation.** How are settlement node graphs generated from the existing settlement generation pipeline? The simplest path: each generated PoI becomes a node, edges are auto-generated within and between districts with weights derived from district size. Detail TBD in a settlement layout GDD revision.

5. **Co-op implications.** The design brief mentions online co-op with shared campaigns. Real-time-with-pause co-op is a solved problem (Paradox does it) but adds complexity: who controls the clock? Simplest answer: any player can pause, clock only advances when all players are unpaused. Combat scoping under co-op needs further thought (does Player A's combat freeze Player B? Probably yes, given the global-pause model). Defer to co-op design phase.

6. **Auto-pause granularity settings.** Which events should be player-configurable for auto-pause? Propose a tiered system (always pause / pause by default / never pause) with sensible defaults. Detail in a UI/UX revision.

7. **Sub-cell visual offsets and group rendering.** §3.4 proposes sub-cell visual offsets for tightly-packed formations. Validate during the renderer build that these don't fight the cel-shaded art direction or introduce z-fighting on stair landings.

8. **Group splitting in narrow corridors.** §6.4 says two groups passing in a narrow corridor "step into adjacent cells" but doesn't define the simulator's auto-resolution behavior. If the player issues conflicting orders that would deadlock the simulator (group A blocks group B who blocks group A), the simulator should detect deadlock and halt with an auto-pause prompt. Specifics TBD during simulator implementation.
