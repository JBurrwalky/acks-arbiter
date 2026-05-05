# GDD: Real-Time-with-Pause Game Clock & Event Scheduler

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Documentation pass — describes implemented architecture; flags unimplemented design items inline
**Replaces:** Earlier drafts of this document; design brief §8.3 simultaneous-declaration day-cycle scheduling
**Depends on:** `gdd-voxel-tactical-architecture.md` (3D voxel grid spatial substrate for the dungeon and combat layers), Timekeeping autoload (built), EventBus (built), CampaignRepository (built), DiceSystem (built)
**Implementing files:** `engine/subsystems/session/event_scheduler.gd`, `scheduled_event.gd`, `scheduler_loop.gd`, `event_handler_registry.gd`, `session_runner.gd`, `session_state.gd`, `handlers/*`, `states/*`
**Last updated:** 2026-04-30

---

## 1. Overview

The game runs on a continuously advancing per-party in-game clock that the player can pause, slow, or accelerate. Parties, armies, construction projects, domain ticks, NPC missions, and other long-duration activities operate concurrently as scheduled events on a shared event scheduler. The player issues orders to their entities, the clock advances, and events resolve when their scheduled timestamps arrive. The game auto-pauses when something requires player attention.

The model is inspired by Paradox grand strategy games: a living world clock with queued orders and interrupt-on-event. It replaces the previous simultaneous-declaration turn-based model where all parties declared activities and then resolved in sequence.

### 1.1 Implementation Layers

The architecture has **three cooperating layers**:

1. **EventScheduler** — a priority queue of `ScheduledEvent` entries keyed to absolute game-time timestamps (`fire_time`, in elapsed rounds). Authoritative for all coarse-grain events: travel arrivals, action completions, scheduled checks, domain ticks, light timers, construction milestones. Hex map travel and city node-graph travel resolve entirely in this layer.

2. **SchedulerLoop** — the tick-driven runner that advances Timekeeping toward the next scheduled event, pops it, and dispatches to a registered handler via `EventHandlerRegistry`. Owns clock-speed controls and per-context speed bands (§2.5). Calls `pause()` on combat entry and on auto-pause-flagged event results.

3. **Dungeon movement layer (renderer-tween-driven)** — when a player-controlled entity is exploring a dungeon, movement orders are converted to BFS paths and handed to the renderer (`dungeon_map_renderer_3d.gd`). The renderer animates each token cell-by-cell with tweens whose duration scales with clock speed and the entity's movement rate. As each tween completes, a `movement_cell_reached` signal updates the logical position in `voxel_map.entity_positions`, runs mechanical checks (passability, occupancy, encounter proximity), and starts the next cell tween. This is the "RTS-style continuous movement" — visual smoothness comes from tweens, logical granularity is per-cell.

Combat is a turn-based sub-game. When combat triggers, the SchedulerLoop pauses globally and combat resolves in its own loop. On combat end, `Timekeeping.advance_party_rounds(party_id, rounds_fought)` advances the clock by combat's elapsed duration; the scheduler resumes and any past-due scheduled events resolve immediately on the next tick.

### 1.2 Per-Party Clocks

Time is tracked per-party via `Timekeeping.advance_party_rounds(party_id, n)`. Each party has an independent timestamp. SchedulerLoop is configured for the active party at any moment. Multi-party concurrency is therefore a function of how the session runner switches active context between parties — not a single global clock.

### 1.3 Session Runner Model

The session runner is a state machine, but the states represent *which UI/context is active* (`WildernessExploreState`, `DungeonExploreState`, `SettlementExploreState`, `CombatState`, etc.) rather than a global "what is the game doing right now" mode. The scheduler runs continuously while in any exploration state. Context (wilderness, dungeon, urban) is also a property of each entity for the purposes of which event handlers apply to their scheduled events.

---

## 2. Core Architecture: The Event Scheduler

### 2.1 Concept

The **EventScheduler** (`engine/subsystems/session/event_scheduler.gd`) is a priority queue of `ScheduledEvent` instances. The SchedulerLoop advances the clock toward the next event, pops it, dispatches to its registered handler, and repeats. If resolution creates new events, the handler returns them in its result and SchedulerLoop inserts them into the queue. If resolution requires player input, the loop pauses.

### 2.2 Event Structure

Each `ScheduledEvent` contains:

- **`event_id: String`** — unique hex identifier from `CampaignRepository.generate_id()`
- **`fire_time: int`** — absolute game time in elapsed rounds when this event fires
- **`event_type: String`** — registered vocabulary string (e.g., `"travel_leg"`, `"dungeon_encounter_check"`, `"construction_complete"`, `"domain_month_tick"`)
- **`owner_id: String`** — the entity this event belongs to (party_id, character_id, domain_id, etc.)
- **`data: Dictionary`** — event-specific payload
- **`priority: int`** — tiebreaker for events at the same `fire_time` (lower resolves first)
- **`cancelled: bool`** — soft-delete flag for lazy queue cleanup

Persistence: events serialize to and from `Dictionary` via `to_dict()` / `from_dict()` so the queue survives save/load.

### 2.3 Priority Tiebreaker Rules

When multiple events share the same `fire_time`, resolve in this order (constants on `ScheduledEvent`):

1. `PRIORITY_ENVIRONMENTAL = 0` — weather changes, dawn/dusk, season transitions
2. `PRIORITY_SCHEDULED_CHECK = 10` — wandering monster rolls, encounter checks
3. `PRIORITY_ARRIVAL = 20` — travel arrivals, search/lockpick/listen completions, construction milestones (default)
4. `PRIORITY_CONSEQUENCE = 30` — combat triggers, trap fires, domain encounters

Within the same priority tier, `ScheduledEvent.is_before(other)` resolves by `owner_id` alphabetically — deterministic, arbitrary, consistent. Determinism matters for replay and save/load.

### 2.4 Scheduler Interface

`EventScheduler` exposes (verbatim from `event_scheduler.gd`):

```gdscript
func schedule(event: ScheduledEvent) -> String                  # returns event_id
func schedule_at(fire_time, event_type, owner_id, data, priority) -> String
func schedule_after(current_time, delay_rounds, event_type, owner_id, data, priority) -> String
func cancel(event_id: String) -> bool                           # soft-delete
func cancel_all_for_owner(owner_id, event_type = "") -> int     # bulk cancel
func peek() -> ScheduledEvent                                   # null if empty
func pop() -> ScheduledEvent
func is_empty() -> bool
func size() -> int
func get_events_for_owner(owner_id) -> Array[ScheduledEvent]
func get_all_events() -> Array[ScheduledEvent]
func clear() -> void
func to_dicts() -> Array[Dictionary]
func load_from_dicts(dicts: Array) -> void
```

Cancellation is soft-delete (sets `cancelled = true`); lazy queue cleanup removes cancelled entries when they reach the head. `O(1)` cancellation by id via internal hash index. Insertion is `O(log n)` binary-search into a sorted array; removal of head is `O(n)` (single `Array.remove_at(0)`). At ACKS-scale queue sizes (tens to low hundreds) this is fast enough; flagged in §12 if profiling later shows otherwise.

### 2.5 Clock Speed Controls

`SchedulerLoop` (`scheduler_loop.gd`) implements clock-speed control with two interacting concepts: **bands** (Pause / Normal / Fast / Very Fast / Max) and **per-context speed multipliers**.

Speed band constants are caller-facing ordinals:

```gdscript
const SPEED_PAUSED   = 0
const SPEED_NORMAL   = 1
const SPEED_FAST     = 2
const SPEED_VERY_FAST = 5
const SPEED_MAX      = -1   # advance instantly to next event
```

These are mapped to actual game-time-per-real-second multipliers via per-context tables (added in C1 work, 2026-04-27):

| Context | Normal | Fast | Very Fast |
|---|---|---|---|
| Dungeon | 1× | **6×** | **30×** |
| Wilderness | 1× | 2× | 5× |
| Settlement | 1× | 2× | 5× |

The dungeon context uses larger multipliers because its base TIMESCALE is round-level (~2 real seconds = 1 game round); a 30× multiplier advances ~5 minutes of game time per 2 real seconds. Wilderness and settlement keep 1×/2×/5× because their base timescales (`TIMESCALE_WILDERNESS = 60.0`, `TIMESCALE_SETTLEMENT = 6.0`) already amplify each band.

`SchedulerLoop.get_effective_multiplier()` is the single source of truth for the active multiplier; the dungeon renderer reads from `DUNGEON_SPEEDS` directly so tween playback stays synchronized with logical advancement.

Spacebar toggles pause via `toggle_pause(resume_speed)`. The default keybindings 1/2/3 set NORMAL/FAST/VERY_FAST; MAX is bound to a separate key.

### 2.6 Two-Layer Architecture (Discrete Events + Continuous Visuals)

The scheduler handles discrete events with known timestamps: travel arrivals, action completions, scheduled checks, light expiries. These are correctly modeled as priority-queue entries.

The dungeon layer additionally needs continuous-feeling unit movement. The implementation splits this into:

- **Logical state:** voxel-snapped positions in `voxel_map.entity_positions`, updated per cell as the unit traverses its path.
- **Visual state:** renderer tweens (`dungeon_map_renderer_3d.gd._active_movements`) animate tokens smoothly between cells. Tween duration is `SECONDS_PER_ROUND / cells_per_round`, scaled by `_compute_speed_scale()` so the visual pace tracks `DUNGEON_SPEEDS`.

The cell-arrival signal (`movement_cell_reached`) is the seam: when a tween finishes a cell-hop, it fires the signal; the mechanical layer (`DungeonExploreState`/`DungeonHandlers`) updates `voxel_map.entity_positions`, runs occupancy/passability/encounter-proximity checks, and starts the next cell tween or stops the path.

**This is the project's "continuous-tick simulator."** It is renderer-driven and per-cell rather than fixed-rate-per-sub-cell, but it provides the RTS-style smooth movement the design wants. There is no separate game-time tick simulator running at a sub-cell rate. Sub-cell logical state is unnecessary: ACKS rules use 5'-cell positioning, and visual smoothness is provided by tween interpolation at the renderer.

---

## 3. Movement & Visual Smoothness in the Dungeon Layer

This section describes how dungeon movement actually works. It is documentation of the implemented model, not a spec for a separate Movement Simulator subsystem (no such subsystem exists or is planned — the renderer tween system is the simulator).

### 3.1 Order → Path → Animation Flow

When the player issues a Move Here order:

1. **Path computation.** `MovementResolver.path_bfs_3d()` finds a 3D voxel path from the unit's current cell to the target. Mode `"explore"` permits closed unlocked doors (the executor pauses to open them); mode `"combat"` rejects all doors except open. Pathfinding is BFS over `VoxelGrid.get_neighbors_3d()` with passability filters. AStar3D is available for longer paths.

2. **Animation start.** `DungeonExploreState`/`DungeonHandlers` calls `renderer.start_movement_animation(entity_id, path, cells_per_round)`. The renderer queues per-cell tweens.

3. **Per-cell tween.** Each tween moves the token from the current cell's world position to the next cell's world position, `tween_property(token, "position", target_world, base_duration)`, with `base_duration = SECONDS_PER_ROUND / cells_per_round`. Speed scaling: `tween.set_speed_scale(_compute_speed_scale())`.

4. **Cell-arrival signal.** When the tween finishes, `_on_continuous_move_finished` emits `movement_cell_reached(entity_id, reached_cell)`.

5. **Mechanical update.** The signal handler updates `voxel_map.set_entity_pos(entity_id, reached_cell)`, then either starts the next tween or stops the animation if a check failed.

### 3.2 Speed Scaling

Tween playback speed scales with the active `DUNGEON_SPEEDS` multiplier. At Normal (1×), one cell takes ~2 real seconds at exploration speed. At Fast (6×), ~0.33 real seconds. At Very Fast (30×), ~0.067 real seconds — at this speed the visual is rapid but readable. At MAX, the renderer skips animation entirely; logical positions update via direct scheduler-driven advancement.

### 3.3 Cancellation

The renderer kills any in-progress tweens for an entity when:

- The player issues a new order (`start_movement_animation` calls `_kill_entity_tween` first).
- Combat triggers (`cancel_all_movement_animations` is called by `DungeonExploreState._start_dungeon_combat`).
- A mechanical check on cell arrival fails (occupancy, encounter proximity, etc.).

No event-removal is needed because movement isn't scheduled as events; it lives in renderer state.

### 3.4 Group Movement and Marching Order

Groups are issued a coordinated move via the order manager. Members compute their own paths to formation slots near the destination. Marching order determines who is at the front in narrow corridors. `formation_manager.gd` handles slot assignment.

### 3.5 Sub-Cell Visual Polish (Not Implemented)

Sub-cell visual offsets for tightly-packed formations (so 4 PCs on a stair landing don't visually stack) are not implemented. Tokens render at cell center. Worth playtesting whether the visual is acceptable before investing in offsets. **DESIGN ITEM, DEFERRED.**

### 3.6 Continuous Facing (Not Implemented)

Tokens do not rotate to face their movement direction. **DESIGN ITEM, DEFERRED.**

---

## 4. Overworld Layer (Wilderness & Domain)

### 4.1 Party Movement

The player selects a party and right-clicks a destination hex (or sets waypoints). The system calculates travel time based on terrain movement cost, party speed (slowest member), encumbrance, mounts, proficiency modifiers (Navigation, Endurance, Running), and weather.

This produces a sequence of `travel_leg` events in `wilderness_handlers.gd` — one per hex boundary crossing. Each `travel_leg` event's `fire_time` is the arrival time at the next hex. On arrival:

1. Fog of war updates for the new hex.
2. Encounter check fires (`wilderness_encounter_check`, 1d6 vs. terrain threshold per ACKS rules). If an encounter triggers, auto-pause and resolve.
3. If no encounter, the next `travel_leg` event is already in the queue.

Getting-lost checks fire once per day of travel as a scheduled event. If lost, the party's remaining `travel_leg` events are recalculated with random deviation.

**Visual interpolation:** Between two `travel_leg` events at timestamps T1 and T2, the renderer draws the party token at a position interpolated along the path from hex A to hex B based on `(now - T1) / (T2 - T1)`. The logical position remains discrete (hex A until T2). This is purely renderer-side; no scheduler involvement.

### 4.2 Forced March

If travel extends past the normal daily window, a forced march event fires. CON checks per ACKS rules with Endurance proficiency modifier. Failure → exhaustion effects. The player can preemptively cancel remaining travel legs to camp instead.

### 4.3 Camping and Watches

The player orders a party to camp. `camp_handlers.gd` schedules a sequence of `camp_watch` events (typically 3 watches of ~4 hours each, configurable). Each watch boundary fires an encounter check. Dawn and dusk signals from Timekeeping interact naturally — the party wakes at dawn if they started resting at dusk.

### 4.4 Wilderness Day Tick

Per-party midnight rollover housekeeping event (`wilderness_day_tick`, `priority = PRIORITY_ENVIRONMENTAL`). Established in Phase 1 of the wilderness closure roadmap (2026-05-04). Centralizes work that fires once per game-day per party — weather rollover (Phase 2, live), sustenance penalty math (Phase 3, per `acore_adventures_and_encounters.xml`: 2-day food grace then 1 hp/day, 1 day water then 1d4 hp + 1d4/day), and exhaustion accumulation.

**Lifecycle:**

- `WildernessExploreState.enter` calls `WildernessHandlers.schedule_day_tick(scheduler, party_id)` for every party in the campaign. The helper is queue-idempotent — re-entering the wilderness state from combat/dungeon does not double-schedule. Fire time is the next midnight on the party's clock (`party_time + (ROUNDS_PER_DAY - party_time % ROUNDS_PER_DAY)`); a party sitting exactly at midnight schedules 24h out, not 0 rounds out.
- `_handle_wilderness_day_tick` stamps `party_state.last_day_tick_round` (durable idempotency guard against a session reload double-firing the same tick), persists, emits `EventBus.wilderness_day_ticked(party_id, summary)`, **rolls today's weather for the party's hex via `WeatherCache.get_or_generate` and fires `EventBus.weather_changed` + a NotificationManager toast on severe transitions** (Phase 2), and self-reschedules at `event.fire_time + ROUNDS_PER_DAY` via the `next_events` return contract.
- The handler does NOT auto-pause — day-tick is housekeeping. Phase 3 routes threshold-crossing toasts (`sustenance_threshold_crossed`) through `NotificationManager`; only the toast system surfaces it to the player.

### 4.5 Domain Ticks

Domain monthly resolution is a scheduled event at each month boundary (`domain_handlers.gd`). When it fires, it resolves revenue, population, morale, construction progress, garrison costs, and domain encounters per ACKS rules. The result is presented to the player (auto-pause), then the clock resumes.

### 4.6 Armies and Long-Duration Activities

Armies on the march use the same `travel_leg` event pattern as parties. Construction projects have a `construction_complete` event at their calculated completion date. Henchmen on missions have `mission_complete` events. Magic research has `research_complete` events. All entries in the same scheduler queue.

### 4.7 Cross-Entity Interaction

If a party enters a hex containing a hostile army, or two armies converge, the scheduler detects the spatial collision at `travel_leg` resolution time and triggers an encounter. No special logic — the event resolver checks for entities sharing a hex after each arrival.

---

## 5. City Layer (Settlement as Node Graph)

### 5.1 Concept

Settlements are not rendered as walkable maps. A settlement is a weighted node graph where:

- **Nodes** = Points of Interest (taverns, temples, markets, guildhalls, NPC residences, city gates, etc.)
- **Edges** = Travel connections between nodes, weighted by travel time in blocks

The player sees a list of available PoIs (or optionally a node-graph diagram for orientation). They select a destination, and travel time is calculated from edge weights. The system tracks blocks traveled for timekeeping and encounter rolls.

### 5.2 Mechanical Integration

- **Travel time:** Each edge has a weight in blocks. Movement speed in blocks/turn is derived from the party's movement rate. Travel between nodes consumes time via Timekeeping, scheduled as a `node_arrival` event per traversal.
- **Encounter checks:** `city_encounter_check` events per `settlement_handlers.gd`, fired at time-based intervals during travel.
- **District modifiers:** Each node belongs to a district. District properties (encounter tables, law enforcement response, market class) apply at that node.
- **Time-of-day effects:** Dawn/dusk signals from Timekeeping drive PoI availability.

### 5.3 Activities at Nodes

When the party arrives at a PoI, available activities depend on the PoI type: shopping, hiring, information gathering, carousing, spell research access, criminal hijinks, temple services, etc. Each activity has a known duration. The player selects an activity, it becomes a scheduled event, the clock advances, the activity resolves.

### 5.4 Entering and Leaving Settlements

A settlement is attached to a hex. The party enters by arriving at that hex and choosing to enter. From inside, the party can exit to the hex map at any city gate node. No time-bubble or synchronization issues — the settlement is a different spatial context for the same scheduler.

The dungeon movement layer (§3) does not run while in a settlement. Travel between nodes is a single scheduled event per edge.

---

## 6. Dungeon Layer (Real-Time-with-Pause Exploration)

### 6.1 Concept

Dungeon exploration runs the EventScheduler/SchedulerLoop master loop, plus the renderer-tween movement layer (§3) for unit positioning. The spatial substrate is the 3D voxel grid (`gdd-voxel-tactical-architecture.md`) — 5' cube cells, `Vector3i(col, row, level)` coordinates. The player controls individual units (or groups) on the voxel grid. Activities (search, listen, force door, pick lock) are queued actions with deterministic durations resolved as scheduled events.

A dungeon is a single coordinate space spanning all its levels. The party may be split across multiple levels at any time. The camera shows one focus level at a time per the Visibility Manager (`gdd-voxel-tactical-architecture.md` §16); the renderer continues animating unit movement on all levels regardless of focus.

### 6.2 Movement Modes

ACKS movement modes (per `acore_adventures_and_encounters.xml` and `gdd-voxel-tactical-architecture.md` §11) determine speed and passive behavior:

- **Exploration** (default): one-third combat speed. Mapping occurs. Quiet movement.
- **Combat speed**: full movement rate. No mapping. Weapons ready. Normal noise.
- **Running**: double combat speed. No mapping. High noise.
- **Flying / Burrowing / Climbing**: per `gdd-voxel-tactical-architecture.md` §11.2–§11.4 for creatures with those modes.

Mode is per-unit or per-group, toggleable by the player. The mode affects path durations (cells_per_round in §3.1).

### 6.3 Unit Groups (RTS-Style Control)

Standard RTS conventions per `gdd-dungeon-map-ui.md` §2: left-click selects, shift-click multi-selects, Ctrl+[1–9] binds control groups, [1–9] recalls them, right-click issues move/context-menu orders.

**Group movement speed is set by the slowest member.** Members move in marching order through corridors. Marching order determines who encounters traps first, who reaches melee range first when combat triggers, and who makes first contact with doors and NPCs.

A group may span multiple levels. The Level Strip Widget (`gdd-voxel-tactical-architecture.md` §16.4) shows where each member is. Selecting a multi-level control group does not auto-change focus; the player navigates between levels via PgUp/PgDn or by clicking portraits.

### 6.4 Pathing and Cell Occupancy

Pathfinding operates on the voxel grid via BFS or AStar3D. Path is computed once when the order is issued; the renderer-tween layer (§3) walks the unit along the path cell-by-cell.

**Occupancy model (settled 2026-04-30, smoke-tested OK).** `voxel_map_data.gd` provides `is_occupied_by_other(pos, exclude_id)`, which returns true if any other entity occupies the cell. `_execute_orders_voxel` (`dungeon_map_controller.gd:761-832`) uses claim-based collision: each entity claims its target cell up front, and a second order targeting the same cell converts to `wait`. The result is one entity per cell at all times.

This is the project's intended occupancy model. A more permissive 2-unit-transient pass-through rule was considered as a hedge against doorway-piling visual glitches but the smoke test confirmed the claim-based-collision model produces clean serialized passage with no visual issues. No further work is required here.

The current model has known limitations that are accepted as design tradeoffs:

- No friendly/hostile distinction at the occupancy level — all entities block each other equally.
- No incapacitated-doesn't-count rule — a downed party member's cell is impassable until they're moved.
- A unit can wait one extra step rather than swap places with a friend in a 1-cell corridor.

If any of these become felt problems in playtest, revisit; otherwise the simplest model wins.

### 6.5 Queued Actions and Activity Resolution

When a unit reaches an interactive cell (door, chest, suspicious wall), the player right-clicks for a context menu of available actions per `gdd-dungeon-map-ui.md`. Each action has a deterministic duration from ACKS rules:

| Action | Duration | Source |
|--------|----------|--------|
| Search a 10'×10' area | 1 turn (10 min) | `acore_adventures_and_encounters.xml` |
| Listen at door | 1 round (10 sec) | `acore_adventures_and_encounters.xml` |
| Force stuck door | 1 round per attempt | `acore_adventures_and_encounters.xml` |
| Pick lock (thief) | 1 turn | `ax_thief_skill_update.xml` |
| Find/remove traps (thief) | 1 turn | `ax_thief_skill_update.xml` |
| Hide in shadows (thief) | — (instant, lasts until broken) | `ax_thief_skill_update.xml` |
| Move silently (thief) | — (continuous while moving) | `ax_thief_skill_update.xml` |

The action becomes a scheduled event with `fire_time = now + duration`. On completion, the result resolves via `dungeon_handlers.gd` (`_resolve_search`, `_resolve_listen`, etc.) routing through `ThiefSkillResolver` for skill checks. If the action was noisy (bashing a door), it may trigger an immediate encounter check.

A unit's default action when reaching an obstacle can be configured (auto-listen at doors, auto-stop, etc.) — reduces micromanagement.

### 6.6 Detection: Active vs. Passive (Casual Inspection)

ACKS distinguishes two detection modes for hidden features. Active detection is fully implemented; the one ACKS-supported passive case (elf casual inspection) is not.

**Active detection — implemented.** Per `acore_adventures_and_encounters.xml`, the player must declare a Search action; the unit moves to the cell and consumes 1 turn per 10'×10' area; the Judge rolls 1d20 secretly. `_resolve_search` and `_resolve_listen` in `dungeon_handlers.gd` route through `ThiefSkillResolver`, which selects the best applicable target on 1d20:

| Searcher | Secret/hidden door | Traps & dwarven stonework features | Listen at door |
|---|---|---|---|
| General (any class, RAW default) | 18+ | 18+ | 18+ |
| Elf actively searching | 8+ (`acore_demihuman_classes.xml` `detect_hidden_and_secret_doors`) | — | 14+ |
| Dwarf actively searching | — | 14+ (`acore_demihuman_classes.xml` `stonework_detection`: traps, false walls, hidden construction, sloping passages) | 14+ |
| Thief class progression | per `ax_thief_skill_update.xml` `detect_secrets` and `hear_noise` | per `ax_thief_skill_update.xml` `find_traps` | per `ax_thief_skill_update.xml` `hear_noise` |
| Proficiency-equivalent fractional thief level | per relevant proficiency catalog entries | per relevant proficiency catalog entries | per relevant proficiency catalog entries |

`ThiefSkillResolver` picks the best applicable target across these layers per searcher.

**Active search — one chance per character per location.** Per `acore_adventures_and_encounters.xml`: "Each character gets only one chance to find each secret door." Same principle applies to traps. Already enforced in the active-search flow.

**Passive detection — Elf casual inspection only.** The single ACKS-supported movement-passive case is `acore_demihuman_classes.xml` `detect_hidden_and_secret_doors`: "On casual inspection, detects hidden and secret doors with a proficiency throw of 14+ on 1d20." Note this applies **only to elves and only to hidden/secret doors** — there is no analogous passive for dwarves (their `stonework_detection` is explicitly "When actively searching"), and the ACKS rule does not specify a numeric distance for "passing" a door. **NOT YET IMPLEMENTED** (`dungeon_handlers.gd:642`).

**Design intent for elf casual inspection (project-designed where ACKS is silent):**

| Aspect | Rule |
|---|---|
| Who | Elven characters (any class, by race) |
| When | Triggered automatically as the character's `logical_position` updates during movement |
| Movement mode gate | Exploration speed only. Combat speed and Running do not trigger casual inspection (project decision: casual inspection is "grindingly slow careful walking," consistent with the slow-mapping pace of exploration mode). |
| Trigger volume (project-designed) | 3D Chebyshev distance ≤ 2 cells from the hidden/secret door's cell, occlusion-bounded (see below). The door's cell counts (Chebyshev 0 also triggers). |
| Occlusion | Trigger volume is bounded by line-of-passage. Detection cannot pass through `solidity: solid` cells, through closed/locked/stuck doors *other than the target door itself*, or through floors/ceilings whose `floor_type != "none"`. Implementation: 3D BFS from the door's cell through air cells only, max depth 2, terminating at any blocking surface. Cells reachable by this BFS are the qualifying trigger cells. |
| Throw | 14+ on 1d20, rolled secretly per `acore_adventures_and_encounters.xml`. |
| Per-elf-per-door cap | Each elven character gets exactly one passive (casual-inspection) check per hidden/secret door, ever — paralleling the active-search "one chance per character" rule. Independent from the active-search check (an elf who failed a passive may still attempt and pass an active search later, and vice versa). Track per-(door_cell, character_id) state separately for passive vs. active. |
| Resolution on success | Auto-pause, reveal the door (door's `door_detected` becomes true; visible to the player), and present a notification. Camera auto-focuses to the door's level if not already there. |
| Resolution on failure | Nothing happens. Player does not know the check occurred. The check is consumed (no re-rolls on subsequent passes). |

**Mechanical seam.** Implementation hooks into the renderer's `movement_cell_reached` signal in the dungeon movement layer (§3). On each cell-arrival for an elven character at exploration speed, query the dungeon's hidden-feature index for any undetected hidden/secret door whose precomputed trigger volume contains the new cell, and which the character has not yet passively checked. Roll 14+ secretly; on success, set `door_detected = true`, mark the (door_cell, character_id) pair as checked, auto-pause, and emit the reveal notification. On failure, only mark the pair as checked.

**Performance note.** Trigger volumes for hidden features are static within a dungeon (no movement of the door, no change in surrounding solidity during a single dungeon visit) and can be precomputed once on dungeon load. The per-tick query is then a hash lookup keyed by the entered cell. At ACKS dungeon scale (typically a handful of hidden doors per level), this is negligible.

### 6.7 Wandering Monster Checks

**Implemented model.** A `dungeon_encounter_check` scheduled event fires every 2 turns (120 rounds = `ENCOUNTER_CHECK_INTERVAL`) per the active dungeon party (`dungeon_handlers.gd:705-751`). The handler runs `_runner.do_encounter_check(null, local_table)`, which uses the dungeon's `wandering_monster_table` if defined. On a triggered encounter, the spawn occurs at `_controller.get_current_level()` (party leader's level), monsters are placed as roaming entities by `dungeon_encounter_spawner.gd`, and the camera auto-focuses to the spawn level via `EventBus.dungeon_auto_focus_requested`. Always reschedules the next check 120 rounds later.

**Design intent: per-level checks.** When the party is split across multiple levels, fire one check per occupied level instead of one check for the party as a whole. Rationale: a level with party members on it should have its own encounter clock; a party split across two levels means twice as many monsters per turn, which is appropriate to the increased footprint. Distance is measured from the spawning monster's cell to the nearest party member on that level using 3D Chebyshev with LOS-bounding. **NOT YET IMPLEMENTED.**

**Future direction (non-blocking).** Random encounter spawning is a tabletop simulation of what is, in fiction, persistent monster patrols and territorial behavior. A future revision will replace these random spawn-on-roll checks with persistent patrolling monsters and designated patrol spawn-points living in the dungeon's faction graph (`gdd-dungeon-factions.md`). Until that lands, the per-level random check above is the placeholder. Implementation should keep the wandering monster system loosely coupled — a single registered handler for `dungeon_encounter_check` events — so future replacement is a swap-out, not a rewrite.

### 6.8 Combat Transition

**Implemented model.** When `_handle_encounter_check` triggers an encounter, monsters spawn as roaming entities on the dungeon map (not immediate combat). After spawn, `DungeonExploreState._check_roaming_proximity()` runs each tick: for each roaming monster, BFS-path-distance to each PC is computed; if any monster is within `trigger_range = combat_speed_in_cells + 1` of any PC, combat starts.

When combat starts (`_start_dungeon_combat`):

1. **Auto-pause and halt the active party's SchedulerLoop.** `SchedulerLoop.pause()` is called. No scheduler ticking during combat for the active party.
2. **Cancel real-time movement.** `_handlers.cancel_all_moves()` and `_scene.cancel_all_movement_animations()` clear in-progress orders and tweens.
3. **Snapshot positions.** Each combatant's current `voxel_map.entity_positions` entry becomes their starting cell. Roster is built from `party_data` plus the encounter's roaming monster placements.
4. **Combatant scope: entire party.** All party members and trained creatures with combat roles become combatants regardless of level or distance. Distant or upper-level PCs spend their first combat rounds approaching the engagement at combat speed.
5. **Surprise and encounter distance** per `acore_adventures_and_encounters.xml`.
6. **Combat plays out** in the turn-based combat sub-game on the same voxel grid (`combat_state.gd`, `combat_controller.gd`). Initiative, movement, attacks, spells, morale, conditions — all per ACKS combat rules.
7. **Combat ends** when one side is eliminated, flees, or surrenders.
8. **Resume the SchedulerLoop.** `combat_finalizer.gd:50` calls `Timekeeping.advance_party_rounds(party_id, rounds_fought)` — combat duration is added to the party's clock. SchedulerLoop resumes; on its next tick, any past-due scheduled events resolve immediately (`scheduler_loop.gd:258-260` handles `rounds_to_event < 0` by resolving in priority order).

### 6.9 Action Timer Carve-Out

A consequence of the combat resume model in §6.8: **non-combatant scheduled action timers progress through combat naturally.** A search, lockpick, listen, force-door, construction, research, or henchman-mission scheduled event was created with an absolute `fire_time`. When `Timekeeping.advance_party_rounds(party_id, rounds_fought)` advances the clock past that `fire_time` on combat resume, the next scheduler tick sees the event as past-due and resolves it immediately in priority order before normal ticking continues. Player sees the result presented after the combat outcome (e.g., "While combat raged in the next room, Bran finished picking the lock").

What does NOT progress during combat is dungeon unit movement. The renderer tween layer is paused (movement orders cancelled at combat enter, §6.8 step 2). Non-combatant unit positions are unchanged at combat end.

### 6.10 Light Source Tracking

Torches (6 turns), lanterns (24 turns per flask of oil), and other light sources are tracked as duration events. The `DungeonLightManager` is ticked every game turn (`light_tick` event in `dungeon_handlers.gd`); when a light source expires, the handler auto-pauses with a notification. Continual Light spells and other permanent sources don't expire and aren't tracked here.

### 6.11 Dungeon Entry and Exit

A dungeon is attached to a hex or settlement node. The party enters by choosing to enter from the overworld or city layer. From inside, the party can exit at any cell flagged as an entrance/exit (typically a `feature: stairs_up_*` cell connecting to the surface, or any cell flagged as exit by the dungeon generator).

**Time reconciliation on exit.** The dungeon consumes real game time tracked by `Timekeeping` throughout exploration. When the party exits, their per-party timestamp is wherever Timekeeping says. No bubble.

**Multi-party note.** Each party has its own `Timekeeping.party_time`. SchedulerLoop is configured for the active party; switching context to a different party reconfigures the loop. Cross-party time desync can happen (one party in a long dungeon while another travels the wilderness) and is acceptable — the model is "each party advances on its own clock; cross-party physical interactions resolve when their cells align in space and time." Combat pauses the active party's SchedulerLoop (and visually freezes other parties since they're not the active context).

---

## 7. Auto-Pause Events

The game auto-pauses and requests player attention for:

- **Any encounter** (wandering monster, lair discovery, NPC meeting, urban encounter)
- **Combat trigger** (hostile encounter, trap damage, ambush)
- **Arrival at destination** (hex arrival, dungeon room entry with visible features, PoI arrival)
- **Activity completion** (search complete, lock picked, construction finished)
- **Discovery** (passive detection success once implemented, secret door found, trap detected)
- **Resource depletion** (torch burned out, rations exhausted, spell duration expired)
- **Status change** (party member drops to 0 HP, condition expires, level up)
- **Domain events** (monthly tick, domain encounter, construction complete)
- **Time boundaries** (dawn, dusk — configurable; some players may want these suppressed)
- **Cross-level events** (party member on a non-focused level triggers any of the above; the camera auto-focuses to that level per `gdd-voxel-tactical-architecture.md` §16.5 via `EventBus.dungeon_auto_focus_requested`)

Auto-pause events should be configurable. The player should be able to suppress low-priority pauses (e.g., dawn/dusk, routine travel arrivals) via a settings menu. High-priority events (combat, resource depletion, encounters) should always pause.

---

## 8. Order Interruption and Cancellation

The player can cancel or change orders at any time while paused:

- **Cancel travel (overworld):** `EventScheduler.cancel_all_for_owner(party_id, "travel_leg")` removes remaining travel legs. Party stops at its current hex.
- **Redirect travel (overworld):** Cancel remaining legs, issue new destination. New `travel_leg` events replace the old ones.
- **Cancel movement (dungeon):** `renderer.cancel_movement_animation(entity_id)` clears the unit's tween chain. The unit stops at its current voxel cell. No scheduler-event removal needed — movement isn't scheduled.
- **Cancel activity:** `EventScheduler.cancel(event_id)` soft-deletes the queued action event. Time already elapsed is consumed; partial progress is lost (ACKS doesn't have partial search progress).
- **Change movement mode:** Immediate effect on the unit's `cells_per_round`. Recalculate tween durations for any in-progress movement; recalculate `fire_time` for any queued overworld travel events.

`EventScheduler.cancel_all_for_owner(owner_id, event_type)` is the bulk-cancel API; combined with the per-entity tween cancellation in the renderer, this covers all the cancellation paths.

---

## 9. Documentation State and Implementation Status

This section summarizes the implementation status of design items in this GDD. Use it as a reference when planning new work or revising design.

| Design item | Status | Notes |
|---|---|---|
| EventScheduler (priority queue, soft-delete, persistence) | Implemented | `event_scheduler.gd`, `scheduled_event.gd` |
| SchedulerLoop with pause/resume, per-context speed bands | Implemented | `scheduler_loop.gd` (C1 work landed 2026-04-27) |
| EventHandlerRegistry + per-context handler registration | Implemented | `event_handler_registry.gd`, `handlers/*` |
| Per-party Timekeeping clocks | Implemented | `Timekeeping.advance_party_rounds(party_id, n)` |
| Renderer-tween dungeon movement (§3) | Implemented | `dungeon_map_renderer_3d.gd:402-498` |
| Wilderness `travel_leg` events + per-hex encounter checks | Implemented | `wilderness_handlers.gd` |
| Wilderness `wilderness_day_tick` (per-party midnight rollover) | Implemented (Phase 1, 2026-05-04) | `wilderness_handlers.gd::_handle_wilderness_day_tick`. Self-rescheduling +24hr at `PRIORITY_ENVIRONMENTAL`. Idempotency via `party_state.last_day_tick_round`; queue-level idempotency via `WildernessHandlers.schedule_day_tick`. Phase 2 hooks weather rollover here; Phase 3 hooks SustenanceResolver per `acore_adventures_and_encounters.xml`. |
| Settlement node-graph travel + city encounter checks | Implemented | `settlement_handlers.gd` |
| Dungeon active search/listen via ThiefSkillResolver | Implemented | `dungeon_handlers.gd:923-937` |
| Combat global-pause on entry, advance Timekeeping on exit | Implemented | `combat_state.gd:83-86`, `combat_finalizer.gd:50` |
| Action-timer carve-out (non-combatant events progress through combat) | Implemented | falls out of past-due event handling in `scheduler_loop.gd:258-260` |
| Auto-focus camera on cross-level auto-pause events | Implemented | `EventBus.dungeon_auto_focus_requested` |
| VisibilityManager + Level Strip Widget | Implemented | `visibility_manager.gd`, `level_strip_widget.gd` |
| Cell occupancy: claim-based collision (§6.4) | Implemented | Smoke-tested 2026-04-30; no further work needed. The previously-considered 2-unit-transient pass-through rule was dropped — current model produces clean serialized passage at doorways. |
| Elf casual inspection of hidden/secret doors (§6.6) | **Design item, NOT YET IMPLEMENTED** | TODO at `dungeon_handlers.gd:642`. The only ACKS-supported movement-passive case. Throw 14+ on 1d20, exploration mode only, 3D Chebyshev ≤ 2 occlusion-bounded trigger volume, one passive check per elf per door. |
| Per-level wandering monster checks (§6.7) | **Design item, NOT YET IMPLEMENTED** | Current is single-check-per-party. Per-level check is straightforward to add. |
| Persistent patrolling monsters replacing random encounters | **Future direction** | Will replace §6.7 random checks; keep `dungeon_encounter_check` handler loosely coupled. |
| Sub-cell visual offsets, continuous facing | **Design polish, deferred** | §3.5, §3.6. Tokens render at cell center, no rotation. |

---

## 10. UI Implications

### 10.1 Clock and Speed Controls

A persistent clock display showing current game date and time, with speed control buttons (Pause / 1x / 2x / 5x / Max). Spacebar toggles pause. The clock display should be visible in all contexts (overworld, dungeon, city). Per-context multipliers (§2.5) mean the same band button feels different in different contexts — this is by design.

### 10.2 Entity Roster / Outliner

A sidebar or panel showing all active entities (parties, armies, domain projects, NPC missions) with their current activity, location, and ETA to next event. Click to select and center view on that entity. Standard Paradox "outliner" pattern for managing concurrent activities.

### 10.3 Dungeon Control Bar

When viewing the dungeon layer, a control bar showing control groups (bound unit groups with portraits/icons), current marching order, movement mode toggle, and group status (HP, torch timer, active action). Standard RTS unit selection and control group hotkeys per `gdd-dungeon-map-ui.md`.

When a control group spans multiple levels, the control bar shows level badges next to each portrait. The Level Strip Widget (`gdd-voxel-tactical-architecture.md` §16.4) provides the canonical multi-level view.

### 10.4 Context Menus

Right-click on map cells (dungeon objects, hex map locations, settlement PoIs) opens a context menu of available actions per `gdd-dungeon-map-ui.md` §3. Actions are filtered by what's mechanically possible (thief skills only show for thieves, spell options only for casters, etc.).

### 10.5 Notification Feed

A scrolling notification feed showing resolved events: "Party Alpha arrived at Hex 0305," "Wandering monster check (Level 2): no encounter," "Construction on tower: 3 months remaining," "Torch burned out — Henchman Bran's area is now dark." Provides ambient awareness of the world ticking forward without requiring full attention.

---

## 11. Implementation Reference

This section documents the actual scheduler interface as implemented. New event handlers and consumers should match this contract.

### 11.1 Scheduling and Cancelling Events

```gdscript
# Schedule an event by passing a fully-constructed ScheduledEvent
var event := ScheduledEvent.create(fire_time, event_type, owner_id, data, priority)
var event_id := scheduler.schedule(event)

# Or use the convenience methods:
var event_id := scheduler.schedule_at(fire_time, event_type, owner_id, data, priority)
var event_id := scheduler.schedule_after(current_time, delay_rounds, event_type, owner_id, data, priority)

# Cancel by id (returns true if found):
scheduler.cancel(event_id)

# Bulk cancel by owner (and optionally type):
var n := scheduler.cancel_all_for_owner(party_id)
var n := scheduler.cancel_all_for_owner(party_id, "travel_leg")

# Query:
scheduler.peek()                              # next event without removing
scheduler.pop()                               # remove and return next event
scheduler.is_empty()
scheduler.size()
scheduler.get_events_for_owner(owner_id)      # array of pending events for an entity
scheduler.get_all_events()                    # all pending, sorted by fire_time
```

### 11.2 Registering Event Handlers

Each context's handlers register themselves with `EventHandlerRegistry` on context entry and unregister on exit. Pattern from `dungeon_handlers.gd`:

```gdscript
func register_handlers(registry: EventHandlerRegistry) -> void:
    registry.register("dungeon_encounter_check", _handle_encounter_check)
    registry.register("dungeon_search_complete", _handle_search_complete)
    # ... etc

func unregister_handlers(registry: EventHandlerRegistry) -> void:
    registry.unregister("dungeon_encounter_check")
    registry.unregister("dungeon_search_complete")
    # ... etc
```

A handler returns a `Dictionary` with keys:

- `auto_pause: bool` — set true to pause SchedulerLoop on resolution
- `pause_reason: String` — human-readable reason for the pause notification
- `next_events: Array[Dictionary]` — events to schedule as follow-ups (each dict has `fire_time`, `event_type`, `owner_id`, `data`, `priority`)
- `enter_combat: bool` — set true to request a combat transition; SchedulerLoop reads `combat_data` on the same return
- `transition_to: String` — set to a state-runner key to request a state change
- `presentation: Dictionary` — UI presentation payload (encounter data, modal info, etc.)

`SchedulerLoop._resolve_next_event` (`scheduler_loop.gd:315-361`) reads these fields and acts on them.

### 11.3 Speed Control

```gdscript
# Caller-facing band (the value persists across context changes):
loop.set_speed(SchedulerLoop.SPEED_NORMAL)    # = 1
loop.set_speed(SchedulerLoop.SPEED_FAST)      # = 2
loop.set_speed(SchedulerLoop.SPEED_VERY_FAST) # = 5
loop.set_speed(SchedulerLoop.SPEED_MAX)       # = -1

# Active multiplier (read-only, depends on band + context):
loop.get_effective_multiplier()               # → 1.0, 2.0, 5.0, 6.0, 30.0, etc.

# Set context timescale on state enter:
loop.set_timescale(SchedulerLoop.TIMESCALE_DUNGEON)     # = 1.0
loop.set_timescale(SchedulerLoop.TIMESCALE_SETTLEMENT)  # = 6.0
loop.set_timescale(SchedulerLoop.TIMESCALE_WILDERNESS)  # = 60.0

# Pause/resume:
loop.pause()
loop.resume(SchedulerLoop.SPEED_NORMAL)
loop.toggle_pause(SchedulerLoop.SPEED_NORMAL)
loop.is_paused()
```

### 11.4 What to Build Against This Contract

For new event handlers (e.g., per-level wandering checks, passive detection): use the registration pattern in §11.2 and the scheduling API in §11.1. Do not invent new ID schemes or alternate registries.

For new movement-affecting subsystems: integrate via the existing renderer tween signal flow (§3.1). Cell-arrival is the only mechanical seam — that's where occupancy, encounter proximity, and detection checks already live.

For new UI consumers of clock state: subscribe to `EventBus.scheduler_speed_changed`, `scheduler_paused`, `scheduler_resumed`, `scheduler_event_resolved`. Don't poll the loop directly.

---

## 12. Open Questions

1. **Per-level wandering monster checks.** §6.7 confirmed as design intent (Jedidiah 2026-04-30): one check per occupied level, distance from nearest PC on that level. Straightforward change to `_handle_encounter_check` and the next-check scheduling. Bounded scope.

2. **Elf casual inspection.** §6.6 specifies the only ACKS-supported passive detection case: elf-only, hidden/secret doors only, 14+ on 1d20, exploration mode only, 3D Chebyshev ≤ 2 occlusion-bounded trigger volume, one check per elf per door. TODO already exists at `dungeon_handlers.gd:642`. Note the existing TODO label mentions "dwarf/elf" — the dwarf half should be removed; ACKS dwarves have no movement-passive (their `stonework_detection` is active-search-only).

3. **Persistent patrols replacing random encounters.** Long-term direction in §6.7. Out of scope for any near-term work; flagged so the wandering check handler stays loosely coupled.

4. **Auto-pause granularity settings.** Configurable suppression of low-priority pauses (dawn/dusk, routine travel arrivals) per §7. Not implemented; UI/UX work item.

5. **Co-op clock semantics.** Real-time-with-pause co-op has a known design pattern: any player can pause; clock advances only when all players are unpaused. Combat scoping under co-op (does Player A's combat freeze Player B?) needs further thought. Defer to co-op design phase.

6. **MAX speed during dungeon combat-trigger proximity loop.** The roaming-monster proximity check (`_check_roaming_proximity`) runs every tick. At MAX speed, the scheduler races to the next event without the renderer animating; this should still trigger combat correctly because the proximity check doesn't depend on visual state, but worth verifying under playtest.
