# GDD: Real-Time-with-Pause Game Clock & Event Scheduler

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Documentation pass — describes implemented architecture; flags unimplemented design items inline
**Replaces:** Earlier drafts of this document; design brief §8.3 simultaneous-declaration day-cycle scheduling
**Depends on:** `gdd-voxel-tactical-architecture.md` (3D voxel grid spatial substrate for the dungeon and combat layers), Timekeeping autoload (built), EventBus (built), CampaignRepository (built), DiceSystem (built)
**Implementing files:** `engine/subsystems/session/event_scheduler.gd`, `scheduled_event.gd`, `scheduler_loop.gd`, `event_handler_registry.gd`, `session_runner.gd`, `session_state.gd`, `handlers/*`, `states/*`
**Last updated:** 2026-05-27

---

## 1. Overview

The game runs on a continuously advancing in-game world clock that the player can pause, slow, or accelerate. Parties, armies, construction projects, domain ticks, NPC missions, and other long-duration activities operate concurrently as scheduled events on a shared event scheduler. The player issues orders to their entities, the clock advances, and events resolve when their scheduled timestamps arrive. The game auto-pauses when something requires player attention.

The model is inspired by Paradox grand strategy games: a living world clock with queued orders and interrupt-on-event. It replaces the previous simultaneous-declaration turn-based model where all parties declared activities and then resolved in sequence.

### 1.1 Implementation Layers

The architecture has **three cooperating layers**:

1. **EventScheduler** — a priority queue of `ScheduledEvent` entries keyed to absolute game-time timestamps (`fire_time`, in elapsed rounds). Authoritative for all coarse-grain events: travel arrivals, action completions, scheduled checks, domain ticks, light timers, construction milestones. Hex map travel and city node-graph travel resolve entirely in this layer.

2. **SchedulerLoop** — the tick-driven runner that advances Timekeeping toward the next scheduled event, pops it, and dispatches to a registered handler via `EventHandlerRegistry`. Owns clock-speed controls and per-context speed bands (§2.5). Calls `pause()` on combat entry and on auto-pause-flagged event results.

3. **Dungeon movement layer (renderer-tween-driven)** — when a player-controlled entity is exploring a dungeon, movement orders are converted to BFS paths and handed to the renderer (`dungeon_map_renderer_3d.gd`). The renderer animates each token cell-by-cell with tweens whose duration scales with clock speed and the entity's movement rate. As each tween completes, a `movement_cell_reached` signal updates the logical position in `voxel_map.entity_positions`, runs mechanical checks (passability, occupancy, encounter proximity), and starts the next cell tween. This is the "RTS-style continuous movement" — visual smoothness comes from tweens, logical granularity is per-cell.

Combat is a turn-based sub-game. When combat triggers, the SchedulerLoop pauses globally and combat resolves in its own loop. On combat end, `CombatFinalizer` advances the world clock by combat's elapsed rounds rounded up to the next turn boundary (ACKS RAW: combat shorter than a turn consumes a full turn); the scheduler resumes and any past-due scheduled events resolve immediately on the next tick.

### 1.2 Single Shared Timeline (Jedidiah ruling 2026-06-11)

There is ONE world clock. `Timekeeping.get_total_rounds()` is the canonical "now" for all fire_time computation, gating, display, and persistence; `Timekeeping.advance_rounds(n)` (and its minute/turn/hour/day wrappers) is the only advancement API. Per-party clocks were removed — the 2026-06-11 audit (`docs/handoff_multi_party_time.md`) found the per-party mechanism half-built (the loop only ever advanced one frozen clock, boundary signals fired only on the leader, the time-lock's trigger was mathematically unreachable) and Jedidiah ruled asynchronous per-party timelines permanently out of scope ("async should die").

Multi-party concurrency is a function of event ownership, not clocks: every party's orders are events in the shared queue owned by that `party_id`, and they resolve as the world clock passes their fire_times — PROVIDED a handler for the event type is registered (see the caveat below). There is **no order-lock** (ruled 2026-06-12): a new order supersedes the old one — order surfaces cancel the party's pending travel and activity events (`cancel_all_for_owner`) before scheduling replacements. Time already spent is spent; a cancelled activity yields nothing.

**Background-party resolution (Option 2, landed 2026-06-12):** ALL wilderness handlers (travel, encounters, getting-lost, forced-march, activities, ticks) are globally registered for the session (`WildernessHandlers.register_global`, owned by SessionRunner) — background parties' chains keep resolving while the player is in a dungeon/settlement/camp. Background outcomes auto-pause and surface tap-to-act toasts (arrival, lost, forced-march halt) that focus the party. `test_all_wilderness_handlers_register_globally` pins full wilderness handler coverage (an event type with no registered handler is parked, not destroyed — Batch B — but parked means delayed; wilderness must resolve live).

**Party-context switching (Option 1, landed 2026-06-12 — `docs/handoff_party_context_switching.md`):** active = watched = selected. Switching the active party re-points the session and transitions the UI to that party's persisted context; a dungeon party left behind is SUSPENDED (positions, picked locks, fog, and queued events intact — `DungeonExploreState` suspend ≠ exit) and resumes via the savegame restore path. **Focus-coupled clock (Jedidiah's "Option C"):** while any party is inside a dungeon, the world clock advances ONLY while the dungeon layer has focus — other layers resolve modals and queue orders against a locked clock (`SessionRunner.get_clock_lock_reason`; speed buttons disable via `EventBus.clock_lock_changed`; camp entry is gated). Combat's RAW lump-sum advance is the one piercing case; the resulting past-due burst resolves in (fire_time, priority, FIFO-sequence) order on resume (`test_past_due_burst_resolves_in_order`). **Switch-first encounters:** a background party's triggered encounter is fully formed, persisted (`party_state.pending_encounter`), and presented through the normal EncounterDecisionPrompt when the player focuses that party.

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
- **`sequence: int`** — monotonic FIFO stamp written by `EventScheduler.schedule()`; final tiebreaker for fully-tied events
- **`cancelled: bool`** — soft-delete flag for lazy queue cleanup

Persistence: events serialize to and from `Dictionary` via `to_dict()` / `from_dict()` so the queue survives save/load.

### 2.3 Priority Tiebreaker Rules

When multiple events share the same `fire_time`, resolve in this order (constants on `ScheduledEvent`):

1. `PRIORITY_ENVIRONMENTAL = 0` — weather changes, dawn/dusk, season transitions
2. `PRIORITY_SCHEDULED_CHECK = 10` — wandering monster rolls, encounter checks
3. `PRIORITY_ARRIVAL = 20` — travel arrivals, search/lockpick/listen completions, construction milestones (default)
4. `PRIORITY_CONSEQUENCE = 30` — combat triggers, trap fires, domain encounters

Within the same priority tier, `ScheduledEvent.is_before(other)` resolves by `owner_id` alphabetically, and events still tied after that resolve in scheduling order via the monotonic `sequence` stamp — deterministic, consistent, FIFO. Determinism matters for replay and save/load: tie order also survives persistence round-trips (rows reload in saved queue order and are re-stamped).

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

The dungeon context uses larger multipliers because its base timescale is round-level (~2 real seconds = 1 game round); a 30× multiplier advances ~5 minutes of game time per 2 real seconds. Wilderness and settlement keep 1×/2×/5× because their base timescales (60.0 and 6.0 per `CONTEXT_PROFILES`) already amplify each band.

States declare their context explicitly via `SchedulerLoop.set_context(TimeContext)`; timescale + speed bands come from the single `CONTEXT_PROFILES` table (context-enum refactor 2026-06-12 — the context is never inferred from a timescale value). `get_effective_multiplier()` is the single source of truth for the active multiplier; the dungeon renderer reads the DUNGEON profile row from the same table so tween playback stays synchronized with logical advancement.

Spacebar toggles pause via `toggle_pause(resume_speed)`. The default keybindings 1/2/3 set NORMAL/FAST/VERY_FAST; MAX is bound to a separate key.

### 2.6 Two-Layer Architecture (Discrete Events + Continuous Visuals)

The scheduler handles discrete events with known timestamps: travel arrivals, action completions, scheduled checks, light expiries. These are correctly modeled as priority-queue entries.

The dungeon layer additionally needs continuous-feeling unit movement. The implementation splits this into:

- **Logical state:** voxel-snapped positions in `voxel_map.entity_positions`, updated per cell as the unit traverses its path.
- **Visual state:** renderer tweens (`dungeon_map_renderer_3d.gd._active_movements`) animate tokens smoothly between cells. Tween duration is `SECONDS_PER_ROUND / cells_per_round`, scaled by `_compute_speed_scale()` so the visual pace tracks the dungeon profile's speed bands.

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

Tween playback speed scales with the active dungeon-profile band multiplier. At Normal (1×), one cell takes ~2 real seconds at exploration speed. At Fast (6×), ~0.33 real seconds. At Very Fast (30×), ~0.067 real seconds — at this speed the visual is rapid but readable. At MAX, the renderer skips animation entirely; logical positions update via direct scheduler-driven advancement.

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

The player orders a party to camp. `camp_handlers.gd` schedules a sequence of `camp_watch` events (typically 3 watches of ~4 hours each, configurable). **Watch boundaries are state/UX events, not encounter-throw events** — they exist to track who is on duty, to gate mage memorization and cleric prayer windows, to surface notification cues, and to determine who is awake vs. asleep when an encounter resolves (see below). Dawn and dusk signals from Timekeeping interact naturally — the party wakes at dawn if they started resting at dusk.

#### 4.3.1 The camp encounter throw

A camp event receives **one** encounter throw, rolled at camp setup (when the player confirms watch assignments and `CampHandlers.schedule_watches` runs). The throw is **gated by the hybrid rule** described in §4.3.3: it only rolls if no other wilderness encounter has been triggered for this party earlier in the current calendar day.

This is a deliberate, controlled deviation from RAW's literal text per `acore-monster-stocking-rules.xml §wilderness_wandering_monsters.encounter_check.frequency` L143–145 ("If the party is stationary, check once per day"), which treats the day as the unit of accounting. The hybrid rule produces approximately RAW encounter weight (~one effective check per day) while binding the camp's outcome to the camp event rather than the calendar day — a concession to a real-time-with-pause engine that cannot easily fake the GM's retrospective bookkeeping. Reasoning is in §4.3.3.

**Flow when a camp's encounter throw is positive:**

1. The handler picks the **time-of-occurrence** as a uniform roll across the camp window (1d(camp_hours), typically 1d12 for a 12-hour camp). The resulting absolute round-time is scheduled as a new `wilderness_encounter` event (a separate event type from the throw itself). The hour may fall in the same calendar day as camp_setup or in the next day if the camp spans midnight — that is expected.
2. The handler stamps `party_state.last_encounter_trigger_day = day_index_at_camp_setup` so subsequent same-day travel-leg or camp throws are gated. The stamp uses the day at camp setup (the *evening* day for a typical 18:00 → 06:00 camp), not the day the encounter resolves — a cross-day camp's encounter is bookkept against the day it was scheduled from.
3. When the `wilderness_encounter` event fires, the encounter spawner generates creatures per the §4.1 column-selection flow (table column → 1d8 creature type → 1d12 specific creature → distance per `acore_adventures_and_encounters.xml §wilderness_encounters.encounter_distance_table`). The encounter spawner does **not** re-roll the 1-in-6 throw — the camp throw at setup already committed.
4. The handler computes **each party member's observer state at the encounter's fire_time** by reading the watch schedule:
   - On watch at that hour → `actively_watching` per `acore_adventures_and_encounters.xml §surprise_and_sneaking.observer_state.actively_watching` L874–878.
   - Off watch, awake (between watches, day-time rest, before camp start, after camp end) → `passively_watching` per L880–886.
   - Off watch, asleep (the watch schedule has this character sleeping at this hour) → `distracted_or_not_looking` per L888–895. Each sleeping character gets a Hear Noises throw at 18+ on 1d20 to rouse before surprise resolution; on failure, they begin the encounter functionally surprised.
5. Surprise then resolves per RAW (`acore_adventures_and_encounters.xml §surprise`, 1d6 per side, 2- = surprised). The party's effective surprise state is the composite of who roused, who was already alert, and who failed to wake.

If the camp ends before the scheduled `wilderness_encounter` fires (the player aborts via the cancel action, `camp_rest_complete` resolves first because the encounter was scheduled past camp end, or another event transitions the party out of wilderness state), the pending `wilderness_encounter` event is cancelled. The camp is the encounter's binding context; leaving it dissolves the scheduled encounter.

#### 4.3.2 Why the watch schedule still matters

The watch schedule is the mechanical bridge between "the camp gets one encounter throw" and "who is caught sleeping when it resolves." It is a property of the camp, not a sequence of encounter-throw events. Watches determine:

- Who can be wakened by ambient noise (Hear Noises throw at 18+ on 1d20).
- Who is ready vs. surprised when an encounter resolves.
- Who completes mage memorization / cleric prayer / Rest activity ticks at watch boundaries.
- Who accumulates rest toward exhaustion mitigation per §4.4.

#### 4.3.3 The hybrid rule for mixed travel-and-camp days (resolved 2026-05-27)

RAW's three frequency rules (L143–145) read as mutually exclusive descriptors of the day's mode: stationary day = 1 check; settled-terrain day = 1 check; "otherwise" = per-hex check. The unambiguous cases are a fully-stationary day (camp the whole 24 hours = one check) and a fully-traveling day (per-hex checks at each travel_leg arrival = those checks only). The ambiguous case is the day that mixes both — travel during the daylight hours, then camp at night — which is the dominant pattern in expedition play.

The project adopts a **hybrid rule** for mixed days, chosen by Jedidiah on 2026-05-27:

- **Travel-leg per-hex checks are RAW (unchanged).** Every hex entered gets its own 1-in-6 throw. A day of three hexes traveled is three throws.
- **The camp event gets one throw, gated on "has any wilderness encounter triggered for this party earlier today?"** If a travel-leg check earlier in the day produced an encounter, the camp gets no throw (the day's "encounter budget" was already spent). If the day's travel was uneventful, the camp's throw fires.
- **The bookkeeping flag** is `party_state.last_encounter_trigger_day`. It is set to the current day_index on any wilderness encounter trigger — travel_leg or camp. The camp throw fires only when `current_day_index > last_encounter_trigger_day`.

**Why hybrid, not strict RAW.** In tabletop play a GM can resolve the day in retrospect or pre-script the night, deciding mid-play whether the camp gets a check. A real-time-with-pause computer game cannot easily look ahead and see if the player will travel later, so it must fake the cap. The hybrid rule produces approximately RAW encounter weight (per-hex travel throws + at most one camp throw per day) while keeping the camp a meaningful site of risk in the common case where the day's travel was uneventful. The strict-RAW alternative — "any travel today means no camp throw at all" — was rejected because it makes camping mechanically free on travel days, which incentivizes degenerate over-camping and trivializes the watch-order mechanics.

**Cross-day camps.** A typical 12-hour camp (e.g., 18:00 to 06:00) spans two calendar days. The throw is rolled once at camp_setup; the stamp on `last_encounter_trigger_day` uses the day-index at camp_setup (the evening day, not the morning). The rolled fire-time can fall on either side of midnight. The day-tick at midnight (§4.4) does NOT roll a separate camp throw — it does its normal sustenance/weather/rest work and self-reschedules. When the party wakes the next morning and travels, per-hex checks for that next day are independent: the previous evening's camp throw stamped the previous day's flag, and the new day's flag starts unset.

**Edge case: same-day double camp.** If a party were to break a camp at, say, 04:00 and immediately start another camp (unusual but legal), the second camp_setup runs on the same day as the first. The gate checks: did the first camp's throw stamp today's flag? If the first camp's throw rolled positive, yes — second camp gets no throw. If the first camp's throw was negative, the gate flag is unstamped and the second camp's throw can fire. This is the intended behavior: the gate tracks triggers, not throws, and a degenerate two-camp pattern is no different from one long camp.

**What this rule does not do.** It does not gate travel-leg per-hex checks against each other (RAW says per-hex, and we keep per-hex). It does not gate the camp throw against the next day's pending travel — at camp_setup we know what has happened, not what will happen. And it does not allow the camp to "absorb" a previously-rolled-but-not-yet-fired travel encounter; a triggered travel encounter stamps the flag at the moment of trigger, before its modal resolution, so the camp gate sees it.

#### 4.3.4 Migration note (revised 2026-05-27)

The earlier text of §4.3 stated "Each watch boundary fires an encounter check." That was a documentation hallucination, not a deliberate design — it ~40% over-shot the RAW encounter rate on stationary days. The first revision of this section (2026-05-27 morning) attempted a strict-RAW design with the throw folded into `wilderness_day_tick` and the hour rolled across the full 24-hour day. After Jedidiah's review that afternoon, the design was revised to the hybrid rule documented above: throw at camp_setup, gated on the per-day trigger flag, hour rolled within the camp window. Implementation work to do (held until current debugging effort lands):

- **Schema.** Migration (next slot, 131 or later) adds to `party_state`: `is_camping INTEGER NOT NULL DEFAULT 0`, `camp_start_round INTEGER NOT NULL DEFAULT -1`, `camp_end_round INTEGER NOT NULL DEFAULT -1`, `camp_watch_assignments_json TEXT NOT NULL DEFAULT '[]'`, `camp_armed_sleepers_json TEXT NOT NULL DEFAULT '[]'`, `last_encounter_trigger_day INTEGER NOT NULL DEFAULT -1`. Mirror the fields on `PartyData` and round-trip via `to_state_dict` / `from_db`.
- **`camp_handlers.gd::_handle_camp_watch`.** Strip the encounter throw and the enter_combat path. Returns a state/UX-only result (presentation: camp_watch_clear with watch_index). Watch boundary remains for memorization windows, prayer windows, Rest accumulation, and as the data source for observer-state lookup later.
- **`camp_manager.gd::check_watch_encounter`.** Deprecated and removed (no remaining callers).
- **`camp_handlers.gd::schedule_watches`.** After scheduling the three watches and rest_complete:
  - Stamp PartyData with `is_camping = true`, `camp_start_round`, `camp_end_round = camp_start_round + TOTAL_REST_HOURS * ROUNDS_PER_HOUR`, the assignments JSON, the armed_sleepers JSON. Persist.
  - Compute `current_day_index = camp_start_round / ROUNDS_PER_DAY`. If `current_day_index > last_encounter_trigger_day`, roll the camp encounter throw (1-in-6 on 1d6, or the terrain-appropriate threshold if/when terrain-varying thresholds land). On positive:
    - Set `last_encounter_trigger_day = current_day_index`. Persist.
    - Roll uniform `1d(camp_hours)` for the hour-within-camp; convert to absolute round.
    - Schedule a `wilderness_encounter` event at that round with `priority = PRIORITY_SCHEDULED_CHECK`.
- **`camp_handlers.gd::_handle_rest_complete` and the cancel-camp action.** Clear `is_camping = false` and the camp_* fields on PartyData. Cancel any pending `wilderness_encounter` events for this party via `scheduler.cancel_all_for_owner(party_id, "wilderness_encounter")`. Persist.
- **`wilderness_handlers.gd::_handle_travel_leg`.** On a positive trigger from the per-hex check, before returning, stamp `last_encounter_trigger_day = (current_round / ROUNDS_PER_DAY)`. Persist as part of the existing party_state save path.
- **`wilderness_encounter` event type.** Register globally by `SessionRunner.load_session` (alongside the day-tick and domain handlers) so it survives state transitions (party may be in camp when it scheduled, but combat or settlement entry mid-camp must not orphan it — though §4.3.1's cancel-on-camp-end rule will normally clean it up first). The handler:
  - Loads the party's camp watch schedule (assignments + camp_start_round + camp_end_round) from PartyData.
  - Spawns creatures via the existing wilderness encounter spawner (terrain column → creature type → specific creature → number → reaction). Skip the 1-in-6 — the camp throw at setup already committed. Factor the spawner out of `SessionRunner.do_encounter_check` (or add a `force_trigger = true` param) so this handler and the existing travel_leg path share the spawn logic.
  - Computes each party member's observer state at `event.fire_time` against the watch schedule: actively_watching (on watch this hour) / passively_watching (off watch and awake — between watches, before camp_start, after camp_end) / distracted_or_not_looking (sleeping during this watch).
  - For each distracted_or_not_looking member, rolls Hear Noises at 18+ on 1d20. Failures begin the encounter functionally surprised.
  - Routes through the existing `encounter_decision_required` modal (per §27 of `docs/coding_conventions.md`) with surprise context attached so the player sees who roused vs. who is caught. The modal/state pair already handles the encounter-decision flow; surprise context is a new field on the encounter_data dict, consumed by the combat transition.
- **`wilderness_day_tick`.** Does NOT roll the camp encounter throw. Continues to do sustenance, weather, exhaustion, and to self-reschedule. (The earlier morning revision wired this in; remove that wiring if it landed in any working branch before this revision.)
- **Tests.** Any test asserting three encounter checks per camped night must assert at most one camp throw per camp event, gated by the hybrid flag. Add tests for: the gate behavior (camp after triggered travel = no throw; camp after uneventful travel = throw eligible), the cross-day fire-time scheduling (a 12-hour camp's wilderness_encounter can fire in either day, watch_index resolves correctly), the observer-state lookup at fire_time, the Hear Noises rouse path, and the cancel-on-camp-end behavior.

### 4.4 Wilderness Day Tick

Per-party midnight rollover housekeeping event (`wilderness_day_tick`, `priority = PRIORITY_ENVIRONMENTAL`). Established in Phase 1 of the wilderness closure roadmap (2026-05-04). Centralizes work that fires once per game-day per party — weather rollover (Phase 2, live), sustenance penalty math (Phase 3, per `acore_adventures_and_encounters.xml`: 2-day food grace then 1 hp/day, 1 day water then 1d4 hp + 1d4/day), and exhaustion accumulation.

**Lifecycle:**

- `WildernessExploreState.enter` calls `WildernessHandlers.schedule_day_tick(scheduler, party_id)` for every party in the campaign; `SessionRunner` also seeds the day/noon ticks for a newly split-off party at split time (`_on_party_split_for_scheduler`, 2026-06-11) so sustenance starts immediately rather than at the next wilderness re-enter. The helper is queue-idempotent — re-entering the wilderness state from combat/dungeon does not double-schedule. Fire time is the next midnight on the world clock (`now + (ROUNDS_PER_DAY - now % ROUNDS_PER_DAY)`); a party sitting exactly at midnight schedules 24h out, not 0 rounds out.
- `_handle_wilderness_day_tick` stamps `party_state.last_day_tick_round` (durable idempotency guard against a session reload double-firing the same tick), persists, emits `EventBus.wilderness_day_ticked(party_id, summary)`, **rolls today's weather for the party's hex via `WeatherCache.get_or_generate` and fires `EventBus.weather_changed` + a NotificationManager toast on severe transitions** (Phase 2), and self-reschedules at `event.fire_time + ROUNDS_PER_DAY` via the `next_events` return contract.
- The handler does NOT auto-pause — day-tick is housekeeping. Phase 3 routes threshold-crossing toasts (`sustenance_threshold_crossed`) through `NotificationManager`; only the toast system surfaces it to the player.

### 4.5 Domain Ticks

Domain monthly resolution is a scheduled event at each month boundary (`domain_handlers.gd`). When it fires, it resolves revenue, population, morale, construction progress, garrison costs, and domain encounters per ACKS rules. The result is presented to the player (auto-pause), then the clock resumes.

### 4.6 Armies and Long-Duration Activities

Armies on the march use the same `travel_leg` event pattern as parties. Construction projects have a `construction_complete` event at their calculated completion date. Henchmen on missions have `mission_complete` events. Magic research has `research_complete` events. All entries in the same scheduler queue.

### 4.7 Cross-Entity Interaction

If a party enters a hex containing a hostile army, or two armies converge, the scheduler detects the spatial collision at `travel_leg` resolution time and triggers an encounter. No special logic — the event resolver checks for entities sharing a hex after each arrival.

### 4.8 Activity Time Costs and Frequency Semantics

This subsection documents how the activity framework in `ax_campaign_play.xml` §activity_framework (L133-192) is realized in the real-time-with-pause engine. **It applies cross-context** — the same model governs activities started in wilderness, dungeon, settlement, and stronghold contexts.

**Last updated:** 2026-05-06 — replaces the deprecated "daily activity-slot picker" UX previously described in `gdd-domain-tab.md` §11.3 (now superseded by `gdd-domain-tab.md` §11 "Decrees & Remote Orders sub-tab" plus the per-location activity-launch pattern in §15).

#### 4.8.1 Time-cost model (vs. slot quotas)

RAW activity slots (1 major + 2 minor or 8 minor per day, plus unlimited trivial; per `ax_campaign_play.xml` §daily_capacity L146-150) are a tabletop simplification that compresses a day's time budget into integer counters. In the engine we do not enforce slot quotas as a UI constraint — we track precise time costs and let the slot rules emerge from cumulative time consumption against a finite daily active-work budget.

Each activity carries a `time_cost_rounds` derived from its RAW frequency tag:

| RAW frequency | Game-time | Engine encoding |
|---|---|---|
| Major | 5–7 hours per `ax_campaign_play.xml` §activity_levels.major L135-137 | `time_cost_rounds ≈ 6 game-hours` (default; per-activity overrides per RAW where stated) |
| Minor | ~1 hour / 6 turns per §activity_levels.minor L138-140 | `time_cost_rounds = 1 game-hour` |
| Trivial | "Virtually no time" per §activity_levels.trivial L141-143 | `time_cost_rounds = 0` (resolves on click; no clock advancement) |
| Rest | Singular unstrenuous major per §rest L277-291 | `time_cost_rounds = 12 game-hours`, broken into 3 watches of 4 hours (per §4.3 Camping and Watches) — covers mage memorization, cleric prayer, ration consumption abstractly |

The day's active-work budget is **8 hours of useful effort**, which naturally accommodates either path (1 major ≈ 6h + 2 minor × 1h = 8h; OR 8 minor × 1h = 8h). Trivial activities are free and do not consume budget. Overtime per `ax_campaign_play.xml` §overtime_rules L173-186 is allowed past the 8-hour budget and accrues strenuous-day penalties as background accounting (see §4.8.5 below).

#### 4.8.2 Frequency type semantics

`ax_campaign_play.xml` §frequency_types L152-164 distinguishes three frequency types. The engine treats each as a different state machine:

- **Singular** (L152-155): atomic. Engine schedules a single `activity_complete` event at `fire_time = now + time_cost_rounds`. If interrupted before fire (combat triggers, player cancels, location lost), the activity **fails entirely and must be restarted from scratch** — no partial credit, no progress preserved. The day's time spent on the failed attempt is gone.
- **Restricted** (L156-158): same atomic behavior as Singular within a day, plus a per-period cooldown the engine tracks via `last_completed_round` and `restricted_period_rounds`.
- **Ongoing** (L159-163): multi-day. Each day the activity is performed for its required time-cost is "banked" as a `daily_tick`. Engine schedules a daily `ongoing_session_complete` event at `fire_time = day_start + time_cost_rounds`. If the session fires uninterrupted while the entity is at the required location, `ticks_accumulated += 1`. After the session fires the entity is free to use the day's remaining active hours for anything else without affecting the banked tick. If the session is interrupted before its fire_time, the day produces no tick (but accumulated ticks from prior days are preserved). Tick-tolerance / absence-accumulation / abandon-and-resume semantics apply only to this frequency type — per `gdd-domain-tab.md` §15.1.

**This distinction is load-bearing.** Singular and Restricted activities are NOT abandonable mid-execution with partial credit; only Ongoing activities have the daily-tick / absence-accumulation model.

#### 4.8.3 Engine encoding

The activity executor (`engine/subsystems/activities/activity_time_cost_executor.gd`) wraps each launched activity as a `ScheduledEvent` per the `EventScheduler` interface in §2:

- **Singular launch:** `schedule_after(now, time_cost_rounds, "activity_complete", entity_id, {activity_def_id, ...})`. Cancellation via `cancel(event_id)` is the abandonment path; it produces a clean failure with no partial credit.
- **Restricted launch:** same as Singular plus a write to `restricted_cooldowns[entity_id][activity_def_id] = now + restricted_period_rounds` on completion.
- **Ongoing daily session launch:** at the start of each day on the activity, `schedule_after(day_start, session_time_cost_rounds, "ongoing_session_complete", entity_id, {activity_state_id})`. On fire (uninterrupted), `ticks_accumulated += 1` and `EventBus.activity_tick_earned` emits. If interrupted (combat, location-loss, player-cancel), the session is cancelled and no tick is banked. The activity_state record itself persists across sessions; absence accumulation runs per the daily-boundary update in `gdd-domain-tab.md` §15.1.2.

Auto-pause flags are set by the activity completion handlers when the result requires player attention (e.g., research outcome, hijink resolution, troop training complete). Routine within-tolerance ticks do not auto-pause.

#### 4.8.4 No centralized "Activities" picker UI

Activities are launched from their **location-of-execution** UI, not from a centralized picker. The Settlement Panel surfaces hire-mercenaries, gambling, library research, etc. The stronghold UI surfaces oversee-construction, train-troops, inspect-troops. Wilderness hex commands surface hunt, forage, search, survey. Dungeon UI surfaces dungeon-delve, harvest-parts. The only centralized surface is `gdd-domain-tab.md` §11 "Decrees & Remote Orders" sub-tab, which houses the small set of activities a ruler can perform without being physically present (administer_domain, issue_decree, manage_henchmen, conscript_troops, levy_militia, oversee_investment-from-distance, etc.).

For visibility into an entity's currently-running ongoing activities, see the per-character "Active Projects" sub-tab in `gdd-character-tab.md`. This is read-only status display, not a launcher.

#### 4.8.5 Strenuous-day and overtime accounting

These are tracked as background state on `character_activity_state(character_id, strenuous_days_in_streak, overtime_days_in_streak, last_rest_day)`. They do not gate activity execution; they apply mechanical penalties per RAW:

- **Strenuous-day rest requirement** per `ax_campaign_play.xml` §effort_rules L168-171: after 6 consecutive game-days of strenuous activity (whether one strenuous activity per day or multiple), the character must rest as the day's primary effort or accumulate −1 cumulative penalty per day to attack throws, damage, and proficiency throws. The engine increments `strenuous_days_in_streak` whenever a strenuous-tagged activity resolves on a day; resets to 0 on a Rest day. Penalties apply automatically once the streak exceeds 6.
- **Overtime** per §overtime_rules L173-186: allowing more activities in a day than the standard budget (e.g., 2 major + 2 minor instead of 1 major + 2 minor) is permitted but counts the day as multiple strenuous-equivalent days for the rest-requirement counter (1×, 2×, 3×, or 6× per the RAW table). The engine tracks `overtime_days_in_streak` and applies the multiplier when incrementing `strenuous_days_in_streak`.

These are calculated and surfaced silently; the player sees the cumulative penalty applied to their throws but is never blocked from "trying to do more" by a quota popup.

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
8. **Resume the SchedulerLoop.** `CombatFinalizer` advances the world clock by `rounds_fought` rounded up to the next turn boundary (ACKS RAW). SchedulerLoop resumes; on its next tick, any past-due scheduled events — including background parties' events that fell due inside the rounded window — resolve immediately (`scheduler_loop.gd` handles `rounds_to_event < 0` by resolving in priority order). Ruling 2026-06-11: the world keeps moving through the combat skip.

### 6.9 Action Timer Carve-Out

A consequence of the combat resume model in §6.8: **non-combatant scheduled action timers progress through combat naturally.** A search, lockpick, listen, force-door, construction, research, or henchman-mission scheduled event was created with an absolute `fire_time`. When the world clock advances past that `fire_time` on combat resume, the next scheduler tick sees the event as past-due and resolves it immediately in priority order before normal ticking continues. Player sees the result presented after the combat outcome (e.g., "While combat raged in the next room, Bran finished picking the lock").

What does NOT progress during combat is dungeon unit movement. The renderer tween layer is paused (movement orders cancelled at combat enter, §6.8 step 2). Non-combatant unit positions are unchanged at combat end.

### 6.10 Light Source Tracking

Torches (6 turns), lanterns (24 turns per flask of oil), and other light sources are tracked as duration events. The `DungeonLightManager` is ticked every game turn (`light_tick` event in `dungeon_handlers.gd`); when a light source expires, the handler auto-pauses with a notification. Continual Light spells and other permanent sources don't expire and aren't tracked here.

### 6.11 Dungeon Entry and Exit

A dungeon is attached to a hex or settlement node. The party enters by choosing to enter from the overworld or city layer. From inside, the party can exit at any cell flagged as an entrance/exit (typically a `feature: stairs_up_*` cell connecting to the surface, or any cell flagged as exit by the dungeon generator).

**Time reconciliation on exit.** The dungeon consumes real game time tracked by `Timekeeping` throughout exploration — dungeon time IS world time. When the party exits, the clock is wherever Timekeeping says. No bubble.

**Multi-party note (amended per ruling 2026-06-11).** All parties live on the single shared timeline; there is no cross-party time desync. While one party delves, the world clock advances for everyone — another party's scheduled events (travel arrivals, day ticks) fire as their times arrive, auto-pausing for player attention as needed. Combat pauses the SchedulerLoop globally for its duration and feeds its elapsed time back as a world-clock advance on exit (§1.2, §6.8). The earlier "each party advances on its own clock" async model was removed; see `docs/handoff_multi_party_time.md` for the audit and ruling.

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
| Single shared timeline, new-order-supersedes (no lock) | Implemented (2026-06-11/12, replaced per-party clocks + time-lock) | `Timekeeping.get_total_rounds()` / `advance_rounds(n)`; order surfaces cancel via `cancel_all_for_owner` |
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

# Declare the exploration context on state enter (sets timescale + speed
# bands together from CONTEXT_PROFILES):
loop.set_context(SchedulerLoop.TimeContext.DUNGEON)     # timescale 1.0
loop.set_context(SchedulerLoop.TimeContext.SETTLEMENT)  # timescale 6.0
loop.set_context(SchedulerLoop.TimeContext.WILDERNESS)  # timescale 60.0

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
