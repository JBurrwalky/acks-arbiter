# GDD: Real-Time-with-Pause Game Clock & Event Scheduler

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Draft — requires approval before build
**Replaces:** Design brief §8.3 simultaneous-declaration day-cycle scheduling; build plan E-2 session runner state machine concept
**Depends on:** Timekeeping autoload (built), EventBus (built), CampaignRepository (built), DiceSystem (built)
**Blocks:** E-2 session runner implementation, all exploration and domain loop work

---

## 1. Overview

The game operates on a continuously advancing in-game clock that the player can pause, slow, or accelerate. All entities (parties, armies, construction projects, domain ticks, NPC activities) operate concurrently on this shared clock. The player issues orders to their entities, the clock advances, and events resolve when their scheduled timestamps arrive. The game auto-pauses when something requires player attention.

This replaces the previous simultaneous-declaration turn-based model where all parties declared activities and then resolved in sequence. The new model is inspired by Paradox grand strategy games (Crusader Kings, Europa Universalis): a living world clock with queued orders and interrupt-on-event.

Combat remains a turn-based sub-game. Dungeon exploration becomes real-time-with-pause at the round/turn granularity, with combat as a nested turn-based mode within it.

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
- **payload:** Dictionary of event-specific data (destination hex, dungeon cell, etc.)
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
    
    # Advance Timekeeping to the next event's timestamp
    rounds_to_advance = next_event.timestamp - Timekeeping.get_elapsed_rounds()
    if rounds_to_advance > 0:
        Timekeeping.advance_rounds(rounds_to_advance)
        # This fires all boundary signals (dawn, dusk, day_changed, etc.)
        # Boundary signal handlers may insert new events into the queue
    
    # Pop and resolve the event
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

At higher speeds, visual entity movement may interpolate or skip. The mechanical resolution is identical regardless of speed — the scheduler doesn't care about real-world time, only game-time timestamps.

---

## 3. Overworld Layer (Wilderness & Domain)

### 3.1 Party Movement

The player selects a party and right-clicks a destination hex (or sets waypoints). The system calculates travel time based on: terrain movement cost, party speed (slowest member), encumbrance, mounts, proficiency modifiers (Navigation, Endurance, Running), and weather.

This produces a sequence of **travel_leg** events — one per hex boundary crossing. Each travel_leg event's timestamp is the arrival time at the next hex. On arrival:

1. Fog of war updates for the new hex.
2. Encounter check fires (1d6 vs. terrain threshold per ACKS rules). If encounter triggers → auto-pause, resolve encounter.
3. If no encounter, the next travel_leg event is already in the queue.

Getting-lost checks fire once per day of travel (scheduled event). If lost, the party's remaining travel_leg events are recalculated with a random deviation.

### 3.2 Forced March

If travel extends past the normal daily travel window, a forced march event fires. CON checks per ACKS rules (with Endurance proficiency modifier). Failure → exhaustion effects. The player can preemptively cancel remaining travel legs to camp instead.

### 3.3 Camping and Watches

The player orders a party to camp. This inserts a sequence of watch events (typically 3 watches of ~8 hours each, configurable by party). Each watch boundary fires an encounter check. Dawn and dusk signals from Timekeeping interact naturally — the party wakes at dawn if they started resting at dusk.

### 3.4 Domain Ticks

Domain monthly resolution is a scheduled event at each month boundary. When it fires, it resolves revenue, population, morale, construction progress, garrison costs, and domain encounters per ACKS rules. The result is presented to the player (auto-pause), then the clock resumes.

### 3.5 Armies and Long-Duration Activities

Armies on the march work identically to party movement — travel_leg events per hex. Construction projects have a `construction_complete` event at their calculated completion date. Henchmen on missions have mission_complete events. Magic research has research_complete events. All just entries in the same scheduler queue.

### 3.6 Cross-Entity Interaction

If a party enters a hex containing a hostile army, or two armies converge, the scheduler detects the spatial collision at travel_leg resolution time and triggers an encounter. No special logic needed — the event resolver checks for entities sharing a hex after each arrival.

---

## 4. City Layer (Settlement as Node Graph)

### 4.1 Concept

Settlements are not rendered as walkable maps. Instead, a settlement is a weighted node graph where:

- **Nodes** = Points of Interest (taverns, temples, markets, guildhalls, NPC residences, city gates, etc.)
- **Edges** = Travel connections between nodes, weighted by travel time in blocks (abstract distance units)

The player sees a list of available PoIs (or optionally a simple node-graph diagram for orientation). They select a destination, and the party's travel time is calculated from edge weights. The system tracks blocks traveled for timekeeping and encounter rolls.

### 4.2 Mechanical Integration

- **Travel time:** Each edge has a weight in blocks. Movement speed in blocks/turn is derived from the party's movement rate. Travel between nodes consumes time via Timekeeping.
- **Encounter checks:** Urban encounter checks per ACKS rules fire based on blocks traveled (or per the district's encounter frequency).
- **District modifiers:** Each node belongs to a district. District properties (encounter tables, law enforcement response, market class) apply at that node.
- **Time-of-day effects:** Certain PoIs are only available during business hours. Taverns have different encounter tables at night. Dawn/dusk signals from Timekeeping drive this naturally.

### 4.3 Activities at Nodes

When the party arrives at a PoI, the available activities depend on the PoI type: shopping, hiring, information gathering, carousing, spell research access, criminal hijinks, temple services, etc. Each activity has a known duration. The player selects an activity, it becomes a scheduled event, the clock advances, the activity resolves.

### 4.4 Entering and Leaving Settlements

A settlement is attached to a hex. The party enters the settlement by arriving at that hex and choosing to enter. From inside the settlement, the party can exit to the hex map at any city gate node. No time-bubble or synchronization issues — the settlement is just a different spatial context for the same clock.

---

## 5. Dungeon Layer (Real-Time-with-Pause Exploration)

### 5.1 Concept

Dungeon exploration operates on the same event scheduler as the overworld, but at a finer time granularity (rounds and turns instead of hours and days). The player controls individual units (or groups of units) on the dungeon's diamond grid. Units move in real-time as the clock ticks. Activities (searching, listening, forcing doors, picking locks) are queued actions with known durations that resolve when their timer completes.

### 5.2 Movement Modes

Each unit (or group) is set to a movement mode that governs speed and passive behavior:

- **Exploration** (default): Movement at exploration rate (one-third combat speed). Passive detection checks active for eligible classes (dwarf construction detection, elf secret door sensing). Mapping occurs. Quiet movement.
- **Combat speed**: Full movement rate. No passive detection. No mapping. Weapons ready. Normal noise.
- **Running**: Double combat speed. No detection. No mapping. High noise (may trigger additional encounter checks or alert nearby monsters).

The player can toggle movement mode per unit or per group. Mode affects which scheduled events the system generates — exploration mode generates periodic passive detection checks; combat speed and running do not.

### 5.3 Unit Groups (RTS-Style Control)

Units are controlled with standard RTS conventions:

- **Click** to select a single unit.
- **Shift+click** to add/remove units from selection.
- **Ctrl+[1-9]** to bind selected units to a control group.
- **[1-9]** to recall a control group.
- **Right-click** on a map cell to issue a move order (or bring up a context menu if the cell has an interactive object).

When a group moves, all members path toward the destination. **Group movement speed is always set by the slowest member.** Members move in a column through corridors, following the group's designated **marching order** (not a "leader" — just front-to-back ordering). The player sets marching order per group, typically with the thief or highest-AC member at the front.

Marching order determines:

- Who encounters traps first.
- Who is in melee range first when combat triggers.
- Who makes first contact with doors, obstacles, and NPCs.

### 5.4 Pathing and Congestion

Dungeon corridors are often 1-2 cells wide. The system must handle column movement gracefully:

- Groups moving through narrow spaces automatically form a single-file column ordered by marching order.
- In open rooms, groups can spread to a wider formation if space allows.
- If two groups need to pass each other in a narrow corridor, they must have enough room to swap positions — or one group must wait.

Implementation note: The pathfinding system should operate on the group's front unit for routing purposes, with trailing units following cell-by-cell in sequence. Exact formation logic (column, wedge, line) can be a later refinement — a simple "follow in order" queue is sufficient for initial build.

### 5.5 Queued Actions and Activity Resolution

When a unit (or group) reaches an interactive cell (door, chest, suspicious wall, etc.), the player right-clicks to open a context menu of available actions:

- **Door:** Open, Listen, Force, Pick Lock (if thief), Bash, Spike Shut
- **Searchable area:** Search (1 turn), Detect Traps (thief skill)
- **Chest/container:** Open, Check for Traps, Pick Lock, Force
- **Generic cell:** Search, Listen, Hide in Shadows (if thief)
- **Unit self-actions:** Change movement mode, use item, cast spell (out of combat)

Each action has a deterministic duration from ACKS rules:

| Action | Duration | Source |
|--------|----------|--------|
| Search a 10'×10' area | 1 turn (10 min) | ACKS core |
| Listen at door | 1 round (10 sec) | ACKS core |
| Force stuck door | 1 round per attempt | ACKS core |
| Pick lock (thief) | 1 turn | ACKS core |
| Find/remove traps (thief) | 1 turn | ACKS core |
| Hide in shadows (thief) | — (instant, lasts until broken) | ACKS core |
| Move silently (thief) | — (continuous while moving) | ACKS core |

When the player selects an action, it becomes a scheduled event. The clock advances. On completion, the result resolves (success/fail roll). If the action was noisy (bashing a door), it may trigger an immediate encounter check.

A unit's **default action** when reaching an obstacle can be configured: e.g., the lead unit in a group can be set to "auto-listen at doors" or "auto-stop and wait for orders." This reduces micromanagement.

### 5.6 Detection: Passive vs. Active

**Active detection** (the default for most situations): The player must explicitly order a unit to search. Searching takes 1 turn per 10'×10' area. Results are revealed on completion. No automatic searching occurs.

**Passive detection** (class features only): These fire automatically when an eligible unit enters a trigger cell, without consuming extra time:

- **Dwarves:** Detect construction tricks, sloping passages, shifting walls — 2-in-6 chance when passing within 10 feet (ACKS core).
- **Elves:** Detect secret/hidden doors — 2-in-6 chance when passing within 10 feet (ACKS core).
- Other class-specific passives as defined in the ACKS source XML.

Implementation: Each cell that contains a secret or concealed feature has a trigger radius. When a unit with a relevant passive enters that radius, the system rolls the detection check. On success, the game auto-pauses and reveals the discovery. On failure, nothing happens (the player doesn't know the check occurred — information stays hidden).

### 5.7 Wandering Monster Checks

Per ACKS rules, a dungeon wandering monster check occurs every 2 turns. The scheduler inserts a `wandering_monster_check` event every 120 rounds (2 turns × 60 rounds/turn) from the moment the party enters the dungeon. When this event fires:

1. Roll 1d6. On 6+, a wandering monster is indicated.
2. If indicated, determine the monster type from the dungeon level's wandering monster table.
3. Determine encounter distance and direction relative to the nearest party unit.
4. Auto-pause. Present the encounter to the player.
5. If combat results, transition to turn-based combat (§5.8).

Modifiers apply: loud activities (bashing doors, fighting) may trigger additional ad-hoc encounter checks. Quiet or stealthy groups may receive a modifier. These are resolved as they arise, not pre-scheduled.

### 5.8 Combat Transition

When combat triggers in a dungeon (wandering monster, room encounter, trap, or hostile NPC):

1. **Auto-pause.** All dungeon activity stops.
2. **Snapshot positions.** Every unit's current cell position becomes their starting position for combat.
3. **Determine surprise and encounter distance** per ACKS rules.
4. **Enter turn-based combat mode.** The combat system operates on the same diamond grid. Initiative, movement, attacks, spells, morale — all per ACKS combat rules, resolved round by round.
5. **All units in the dungeon enter the combat encounter.** Units distant from the fight spend their combat turns moving toward the engagement at combat speed. They are mechanically "in" the encounter; they just aren't adjacent yet.
6. **Combat ends** when one side is eliminated, flees, or surrenders.
7. **Return to real-time-with-pause.** The clock resumes from the timestamp at which combat ended. The time consumed by combat rounds is already tracked by the combat system and applied to Timekeeping.

### 5.9 Light Source Tracking

Torches (6 turns), lanterns (24 turns per flask of oil), and other light sources are tracked as duration events in the scheduler. When a light source is lit, a `light_source_expired` event is inserted at the appropriate future timestamp. When it fires, the light goes out — auto-pause, notify player.

Continual Light spells and other permanent sources don't expire (no event needed; they just persist until dismissed or dispelled).

### 5.10 Dungeon Entry and Exit

A dungeon is attached to a hex or a settlement node. The party enters by choosing to enter from the overworld or city layer. From inside the dungeon, the party can exit at any entrance/exit cell.

**Time reconciliation on exit:** The dungeon consumes real game time tracked by Timekeeping throughout the exploration. When the party exits, their timestamp is already correct — no time-bubble needed. The overworld clock is simply wherever Timekeeping says it is.

**Multi-party note:** If a *different* party is operating on the overworld while one party is in a dungeon, the dungeon party's time advances independently (Timekeeping's multi-party support). When the dungeon party exits, they may be ahead of or behind the overworld party's timestamp. The party that is behind is "locked" (no new orders) until the global clock catches up to their position. In practice, the overworld party keeps acting while the dungeon party's clock was consumed by dungeon exploration.

---

## 6. Auto-Pause Events

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

Auto-pause events should be configurable. The player should be able to suppress low-priority pauses (e.g., "don't pause at dawn/dusk," "don't pause on routine travel arrivals") via a settings menu. High-priority events (combat, resource depletion, encounters) should always pause.

---

## 7. Order Interruption and Cancellation

The player can cancel or change orders at any time while paused:

- **Cancel travel:** Remove remaining travel_leg events for a party. The party stops at its current position.
- **Redirect travel:** Cancel remaining legs, issue new destination. New travel_leg events replace the old ones.
- **Cancel activity:** Remove a queued action (e.g., cancel a search in progress). The time already elapsed is consumed; partial progress is lost (ACKS doesn't have partial search progress — you either complete the search or you don't).
- **Change movement mode:** Immediate effect on the unit's speed. Recalculate arrival times for any queued movement events.

Implementation: Each entity tracks which events in the scheduler belong to it. Cancellation is: remove all events for entity X of type Y, then optionally insert new ones.

---

## 8. What Changes From Current Design

### 8.1 Design Brief §8.1–8.3

The session runner concept shifts from a state machine with discrete exploration modes to a unified clock-and-scheduler. The design brief's session states (Wilderness Exploration, Urban Exploration, Dungeon Exploration, etc.) become *contexts* that an entity is operating in, not global game states. Multiple entities can be in different contexts simultaneously.

**§8.3 Timekeeping** revision: Replace "Each game day, all active parties declare intended activities simultaneously, then each party's day resolves in sequence" with the real-time-with-pause model described in this document.

### 8.2 Build Plan E-2

The session runner is no longer a state machine with states CAMPAIGN_SELECT → WILDERNESS_EXPLORE → DUNGEON_EXPLORE → etc. It becomes:

- **CAMPAIGN_SELECT** → still exists as a pre-session menu
- **SESSION_ACTIVE** → the single in-game state, running the event scheduler loop
- **SESSION_END** → save and return to campaign select

All other "states" are entity-level contexts, not session-level states.

### 8.3 Timekeeping Autoload

The existing Timekeeping autoload is architecturally compatible with this design. It's already a passive clock advanced by external callers with multi-party support. The change is: instead of the session runner calling `advance_hours()` or `advance_turns()` directly after each player action, the event scheduler loop calls `advance_rounds(delta)` to reach the next event's timestamp, and Timekeeping's boundary signals fire naturally.

No changes to Timekeeping's public API are anticipated. The scheduler is a new consumer of the existing API.

### 8.4 Settlement Maps

The settlement layout system (gdd-settlement-layout.md) described walkable polygon-block maps with street-graph movement. This is replaced by the node-graph model described in §4. The GDD for settlement layout should be updated to reflect this simplification. Settlement *generation* (districts, PoI placement, NPC population) is unchanged — only the spatial representation and movement model changes.

### 8.5 Dungeon Exploration

The previous model was room-by-room turn-based exploration (move to room → resolve → repeat). The new model is continuous real-time movement on the diamond grid with queued actions. The mechanical rules (search duration, encounter frequency, trap detection) are identical — only the pacing and control model changes.

### 8.6 Combat

No change. Combat remains a turn-based sub-game with the full ACKS combat sequence.

---

## 9. UI Implications

### 9.1 Clock and Speed Controls

A persistent clock display showing current game date and time, with speed control buttons (Pause / 1x / 2x / 5x / Max). Spacebar toggles pause. The clock display should be visible in all contexts (overworld, dungeon, city).

### 9.2 Entity Roster / Outliner

A sidebar or panel showing all active entities (parties, armies, domain projects, NPC missions) with their current activity, location, and ETA to next event. Click to select and center view on that entity. This is the Paradox "outliner" concept — essential for managing a living world with multiple concurrent activities.

### 9.3 Dungeon Control Bar

When viewing the dungeon layer, a control bar showing control groups (bound unit groups with portraits/icons), current marching order, movement mode toggle, and group status (HP, torch timer, active action). Standard RTS unit selection and control group hotkeys.

### 9.4 Context Menus

Right-click on map cells (dungeon objects, hex map locations, settlement PoIs) opens a context menu of available actions. Actions are filtered by what's mechanically possible (thief skills only show for thieves, spell options only for casters, etc.).

### 9.5 Notification Feed

A scrolling notification feed showing resolved events: "Party Alpha arrived at Hex 0305," "Wandering monster check: no encounter," "Construction on tower: 3 months remaining," "Torch burned out — Henchman Bran's area is now dark." This provides ambient awareness of the world ticking forward without requiring full attention to every event.

---

## 10. Build Guidance for Claude Code

### 10.1 What to Build First

The EventScheduler is the new backbone. It should be built as a standalone class (not an autoload — the session runner owns it) with a clean interface:

- `schedule(event) → event_id` — insert an event
- `cancel(event_id)` — remove an event
- `cancel_all_for_entity(entity_id, event_type?)` — bulk cancellation
- `peek() → Event or null` — inspect next event without removing
- `pop() → Event` — remove and return next event
- `get_events_for_entity(entity_id) → Array` — query scheduled events

The session runner becomes thin: campaign load → create scheduler → enter the clock loop → present results → save on exit.

### 10.2 What to Rework

- **Session runner (E-2):** Replace state machine concept with scheduler loop. If any session runner code exists, rework it to the scheduler model.
- **Wilderness movement:** Currently (if implemented) is a hex-entered → resolve → repeat loop. Rework to: calculate travel legs → schedule events → let the clock tick.
- **Timekeeping integration:** Instead of `advance_hours(8)` after a player declaration, the scheduler calls `advance_rounds(N)` to reach the next event.
- **Settlement spatial model:** If any walkable settlement map code exists, replace with node-graph model. If not yet built, build as node graph from the start.
- **Dungeon exploration:** If any turn-based dungeon loop exists, rework to real-time movement with action queuing. If not yet built, build as described in §5.

### 10.3 What Stays the Same

- **Timekeeping autoload:** No API changes. New consumer pattern (scheduler-driven), but the autoload itself is stable.
- **DiceSystem:** Unchanged. Events that need dice rolls call DiceSystem as they always would.
- **CampaignRepository:** Unchanged. The scheduler is in-memory; persistence is still via CampaignRepository.
- **EventBus:** May gain new signals for scheduler events, but existing signals are stable.
- **Combat system (F-1):** Turn-based combat is unchanged. The only new interface is: combat receives starting positions and returns time elapsed.
- **Character data, generation, inventory:** All unchanged.
- **All procedural generation GDDs:** Unchanged — they produce content; the scheduler consumes it.

### 10.4 Loose Coupling Guidance

The scheduler should not know about the specifics of any event type. Event resolution should be handled by **registered event handlers** — subsystems register themselves as handlers for specific event_type strings. The scheduler pops an event, dispatches it to the registered handler, and receives back a result indicating: events to schedule next, whether to auto-pause, and what to present to the player.

This keeps the scheduler generic and allows new event types to be added without modifying scheduler code.

---

## 11. Open Questions

1. **Dungeon unit count and performance:** With 25+ units in a dungeon, pathfinding and movement interpolation need to be efficient. The diamond grid is small enough that A* per unit is fine computationally, but visual interpolation of 25 simultaneous movements may need optimization. Profile before optimizing.

2. **Split-party dungeon exploration:** If the player splits units into two groups and sends them different directions in a dungeon, both groups share the same dungeon clock. This works naturally with the scheduler. But if one group triggers combat, §5.8 says ALL units enter combat. This means the distant group's combat turns are spent running toward the fight. Is this the right call for groups that are very far apart (e.g., on different dungeon levels)? Current ruling: yes, combat pulls everyone. Revisit if it feels bad in playtesting.

3. **City node graph generation:** How are settlement node graphs generated from the existing settlement generation pipeline? The gdd-settlement-layout.md produces districts and PoI types. The simplest path: each generated PoI becomes a node, edges are auto-generated within and between districts with weights derived from district size. Detail TBD in a settlement layout GDD revision.

4. **Co-op implications:** The design brief mentions online co-op with shared campaigns. Real-time-with-pause co-op is a solved problem (Paradox does it) but adds complexity: who controls the clock? Simplest answer: any player can pause, clock only advances when all players are unpaused. Defer to co-op design phase.

5. **Auto-pause granularity settings:** Which events should be player-configurable for auto-pause? Propose a tiered system (always pause / pause by default / never pause) with sensible defaults. Detail in a UI/UX revision.
