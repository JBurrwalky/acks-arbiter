# Handoff: Party-Context Switching (Option 1) — Dungeon ↔ Hexmap Without Exiting

**Date:** 2026-06-12
**Status:** DEFERRED — build after other queued work, per Jedidiah 2026-06-12. Option 2 (background-party resolution) landed the same day and is the prerequisite layer; this document specifies the remaining UI/architecture half.
**Origin:** Jedidiah's question during the single-timeline rework: *"if the world/other party events still fire during a dungeon delve, how does the player transition back to the overworld/hex map to deal with them? Currently the only way to transition the UI from the dungeon layer to the hexmap layer is to exit the dungeon."*
**Authority note:** the suspend/resume change to the session-state contract (§4.1) and the active-party→context coupling (§5 ruling 1) touch the session-runner state machine — Layer 3 territory; get Jedidiah's sign-off on the §5 rulings before implementing.

---

## 1. The goal in plain language

Two parties: A is mid-delve in a dungeon, B is traveling overland. B arrives somewhere (or gets lost, or halts) — the game pauses and toasts (this already works, Option 2). The player should be able to **jump to B**: the screen switches from the dungeon view to the hexmap with B selected, the player issues B new orders, then **jumps back to A** — who is standing exactly where they were, mid-dungeon, nothing lost. No walking A to an exit node first.

## 2. What already exists (verified 2026-06-12)

| Building block | Where | State |
|---|---|---|
| Background parties' wilderness events resolve in every context | `WildernessHandlers.register_global` (ALL wilderness handlers session-lifetime, owned by SessionRunner) | LANDED (Option 2) |
| Background outcomes pause + toast (arrival / lost / forced-march halt) | `_handle_travel_leg` / `_handle_getting_lost_check` / `_handle_forced_march_check` background branches | LANDED (Option 2) |
| Background encounters halt-and-drop | `WildernessHandlers._is_wilderness_ui_active` + the two encounter branches | LANDED (Option 2) — this is the placeholder Option 1 upgrades (§4.4) |
| Per-member dungeon positions persist continuously | migration 146 `dungeon_entity_positions`, `SessionState.flush_to_db()` (savegame S-1) | LANDED |
| Loading INTO a mid-dungeon session works | context-aware loader branch, `session_load_state.gd` (savegame GDD §5.6) | LANDED |
| Per-party location context persisted | `parties.current_location_type` / map / hex / dungeon fields (savegame S-1; brief §7 "context is entity-level") | LANDED |
| Active-party selection + signal | `GameState.set_active_party` → `EventBus.active_party_changed` | EXISTS — but zero readers re-point UI context |
| HUD party-selector widget | `scenes/.../party_selector_tabs.gd` | BUILT, NEVER INSTANTIATED (dead scene — candidate revival) |

## 3. The blockers (why it doesn't already work)

1. **`DungeonExploreState.exit()` is destructive.** It clears the party's dungeon position AND the per-entity restore rows (`clear_party_dungeon_position` + `clear_dungeon_entity_positions`, dungeon_explore_state.gd ~:262-265) — correct for "the party left the dungeon," fatal for "the player looked away." A context switch must leave with positions intact.
2. **Nothing maps active-party change → state transition.** The session runner's active state is set by gameplay transitions only (enter dungeon, enter settlement). Switching the active party in the Notebook changes which party the wilderness context menu commands — it never changes which UI is on screen.
3. **States schedule and render for the session primary** (`runner.get_party_id()`), not the active party — the 2026-06-11 audit's "four stale pointers" finding (`SessionRunner._party_id`, `_party_data`, `GameState.party_id`, plus the loop's vestigial guard). Watching party B inside the wilderness state while A is primary mostly works today because wilderness handlers are owner-disciplined, but the dungeon/settlement states assume primary == watched.
4. **The encounter-decision modal lives in WildernessExploreState** (listener for `EventBus.encounter_decision_required`, connected on enter / disconnected on exit). A decision arising while another context is active has no presenter — hence Option 2's halt-and-drop.

## 4. Design sketch

### 4.1 Suspend ≠ exit (the load-bearing change)
Split "the UI leaves the state" from "the party leaves the place." Concretely: remove the position-clearing from `DungeonExploreState.exit()` and move it to the explicit leave-the-dungeon flow (the exit-node action path in the dungeon context menu / `_check_exit_queue` completion), which is where "the party left" is actually decided. `exit()` keeps UI teardown only (disconnect signals, hide scene, unregister state-scoped handlers). This matches Brief §7 ("context is a property of the entity"): A's dungeon-ness ends when A leaves, not when the camera does. After this, a plain `transition_to_state("wilderness")` already IS a suspend of the dungeon.

### 4.2 The transition driver
A `go_to_party(party_id)` entry point on SessionRunner:
1. `GameState.set_active_party(party_id)` (if not already).
2. Read the party's persisted context (`current_location_type` + map/hex/dungeon fields).
3. `transition_to_state(<matching state>, <restore context>)` — reusing the context-aware loader's restore branch for dungeon re-entry (it already rebuilds controller, fog, per-member positions from the DB).
Drivers that call it: a **"Go to party" action on the pause notification** (background arrival/halt toasts), and the **Notebook party tab / revived `party_selector_tabs` HUD widget**.

### 4.3 Watched-party vs session-primary
Decide once (ruling §5.1), then mechanically migrate: the states' `runner.get_party_id()` call sites that mean "the party on screen" should become "the context party" (active party). Inventory the call sites per state before editing — this is the riskiest mechanical step; the 2026-04-23 session and the 2026-06-11 audit both documented mismatches here. `SessionRunner._party_data` reload on switch is already implemented for merges (`_load_party_data_for_session`) and can be reused.

### 4.4 Upgrading background encounters from halt-and-drop to a real decision
Replace the drop in `_handle_travel_leg`/`_handle_encounter_check` background branches with: persist the pending encounter (party_id + encounter_data), auto-pause with a "Go to party" notification action; `go_to_party` lands in the wilderness state, which checks for a pending encounter on enter and raises the existing `EncounterDecisionPrompt`. (Alternative considered: globalize the modal listener — rejected; deciding a wilderness encounter while staring at a dungeon corridor is the wrong frame, and the switch-first flow keeps one presenter.)

### 4.5 Out of scope for v1
- Background parties inside dungeons/settlements/camps (split is wilderness-only — conventions §12); dungeon/settlement/camp handlers stay state-scoped.
- Combat for a background party (encounters still funnel through the switch-first flow; combat only ever starts for the watched party).
- Multiple simultaneous pending decisions: queue them, presenting one per context entry (simplest correct v1).

## 5. Open rulings for Jedidiah (before implementation)

1. **Is "active party" the same as "watched party"?** Recommended: yes — switching the active party switches the UI context (one selector, one concept). The alternative (separate "view" vs "command" selection) doubles the UI surface for little gain.
2. **Approve the suspend/exit split (§4.1)** — Layer 3: changes when dungeon positions are cleared (on leave-the-dungeon, not on state exit).
3. **While the player watches B, does A's delve keep ticking?** A's dungeon recurring events (light ticks — torches burn!) are state-scoped today and would NOT resolve while the dungeon state is suspended; the clock advancing for B means A's absolute-fire-time events go stale-then-burst on return (or get silently eaten if their handlers are unregistered — the same class of bug Option 2 fixed for wilderness). Options: (a) hold A's delve implicitly — dungeon ticks pause while unwatched, torch burn-down computed lazily from elapsed time on resume; (b) globalize dungeon handlers too. Recommended: (a) with lazy light reconciliation — cheaper and matches "the delve waits for the player," but it is a deliberate single-timeline exception that needs Jedidiah's sign-off and a written rule for which event types it covers.
4. **Notification actions:** does NotificationManager support tap-to-act buttons, or is the v1 affordance the Notebook/party-selector only? (Engineering question; check before promising the "Go to party" button.)

## 6. Acceptance checklist

- [ ] §5 rulings recorded (build log + this doc's status line updated).
- [ ] Dungeon suspend: enter dungeon with A, switch to B, switch back — A's per-member positions, fog, light state, session-state (control groups, idle behaviors) all intact; no `clear_*` calls fired.
- [ ] Real exit (walk out via exit node) still clears positions exactly as today.
- [ ] `go_to_party` works from: notification action (if §5.4 yes), Notebook party tab, for all context pairs reachable in v1 (wilderness↔dungeon, wilderness↔settlement, wilderness↔wilderness).
- [ ] Background encounter → switch-first flow → EncounterDecisionPrompt presents with the right party and encounter data; declining/resolving resumes cleanly.
- [ ] Save/load mid-suspension round-trips (a save while watching B with A mid-dungeon restores both).
- [ ] `get_party_id()`-vs-active-party call-site inventory completed per state; each site classified (primary-correct / migrated / unaffected).
- [ ] Net-zero new test failures vs the current baseline (433/19 as of 2026-06-12; second consecutive run; see test-baseline memory).
- [ ] Conventions §19.3/§19.5, gdd-realtime-scheduler.md §1.2/§6.11, gdd-savegame-system.md §9 amended; build log entry appended.

## 7. File map (expected blast radius)

| File | Change |
|---|---|
| `engine/subsystems/session/states/dungeon_explore_state.gd` | exit() loses position-clearing; leave-the-dungeon flow gains it; suspended-state hygiene |
| `engine/subsystems/session/session_runner.gd` | `go_to_party()`; active-party transition driver; watched-party accessor |
| `engine/subsystems/session/states/wilderness_explore_state.gd` | pending-encounter check on enter; presenter wiring |
| `engine/subsystems/session/handlers/wilderness_handlers.gd` | background encounter branches: drop → persist + prompt |
| `engine/subsystems/session/states/session_load_state.gd` | restore branch factored for reuse by go_to_party (it already restores into dungeons) |
| `scenes/.../party_selector_tabs.gd` | revive or replace as the switch affordance |
| NotificationManager | optional action-button support (§5.4) |
| New: pending-decision persistence | small table or `party_state` field for the §4.4 pending encounter |
| Tests | suspend/resume round-trip; switch-first encounter flow; go_to_party context matrix |
