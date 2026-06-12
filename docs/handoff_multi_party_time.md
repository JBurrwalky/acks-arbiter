# Handoff: Multi-Party Time — Audit, Design History, and Decision Brief

**Date:** 2026-06-11
**Status:** RESOLVED 2026-06-11, amended 2026-06-12 — Jedidiah ruled **Option A (single shared timeline)** with the async vision killed outright (ruling #5: "Async should die" — no dormant async GDD, no preserved per-party seams beyond event `owner_id` discipline). Combat round-up advances the world (ruling #3). Implemented 2026-06-11: per-party clock API + `party_clocks` table removed (migration 154), §7 point fixes landed, Brief §8.3/§10.3/§16.1 + scheduler/savegame GDDs + conventions §6.8/§19.5 amended. **2026-06-12 follow-up ruling:** the order-lock (ruling #2) was rescinded entirely — its rationale belonged to the abandoned catch-up-time model; under one timeline nothing needs locking. New orders supersede old ones (order surfaces cancel pending travel/activity events). The open design item this surfaced: state-scoped handlers mean background parties' travel/activity events are silently consumed while another context is active, and no UI exists to switch contexts between parties — see the 2026-06-12 build log entry. This document is retained as the audit record.
**Origin:** Event-scheduler code review (2026-06-11) flagged the per-party clock mechanism as a "half-mechanism that will generate bugs for as long as it exists." Jedidiah directed a full audit before any change: *"The party clock might be a holdover from an earlier architecture, or it might be related to the asynchronous dungeon time frame. Before we rip it up or change it we need to know exactly what systems are currently trying to use it to ensure the replacement covers all the bases."*

This document is that audit. It contains: a plain-language explanation of the problem (§1), the precise technical mechanics (§2), the complete consumer inventory (§3), the design-history verdict on the holdover question (§4), the authoritative-document promises that constrain any change (§5), the design options with trade-offs (§6), point fixes valid under any option (§7), and the open rulings (§8).

---

## 1. The Problem in Plain Language

Imagine the campaign world has a **wall clock** — the official time of the world. Now imagine every adventuring party also carries its own **wristwatch**. The wristwatches exist so that, someday, two split parties could each live through their own day at their own pace: Party A spends six hours in a dungeon while Party B spends two hours riding to town, and the game keeps both stories straight.

Three rules govern these clocks today:

1. **The wall clock always shows whatever the most-advanced wristwatch shows.** It is not an independent clock; it is defined as "the furthest-ahead party's time."
2. **All the world's "alarms" (scheduled events — a traveler arriving, a torch burning out, rent coming due) sit in one shared alarm queue**, each stamped with a fire-time.
3. **The game's heartbeat (the real-time loop) only ever winds ONE party's wristwatch** — the party that happened to be loaded first when the session started. It never switches, even when you select a different party on the map.

Here is what goes wrong:

- **The alarms and the wristwatches disagree about what the numbers mean.** When Party B's travel order is created, its arrival alarm is stamped using *B's wristwatch*. But the heartbeat checks alarms against *A's wristwatch* (the frozen, loaded-first party). If B's watch is behind A's, B's "six-hour journey" alarm looks like it's already in the past — and the whole journey resolves instantly, in zero time. If B's watch is ahead, A's watch gets dragged forward through hours A never lived.
- **Daily-life events only happen on the wall clock.** Dawn, dusk, spell durations ticking down, monthly paydays — these all fire only when the *wall clock* (= the leader's watch) moves. A party whose watch is behind the leader experiences no sunrises and its spells never expire while it "catches up."
- **The safety mechanism is broken in a way that can never work.** There is a "party lock" that was supposed to freeze a party that got ahead of the world (e.g., after a long dungeon delve) until the world caught up. But because the wall clock is *defined* as the furthest-ahead watch, no party can ever be "ahead of the world" — the lock's trigger condition is logically impossible. It has never locked anyone, has no tests, and its unlock function is never called.

**Why hasn't this exploded already?** Because in normal single-party play, there is one wristwatch and it IS the wall clock — everything agrees. The bugs only surface when a second party exists (party splitting is live in the Notebook UI today) or when something advances the wrong clock (three such bugs already exist in shipped code — see §7).

**The decision needed:** either commit to genuinely separate per-party timelines (a significant build), or simplify to one shared timeline with a different mechanism for "this party is busy" (a moderate cleanup that deletes a whole bug family). The half-built middle ground is the worst of both. The audit below shows the surprising fact that makes this decision easier than it looks: **almost nothing in the codebase actually uses the wristwatches as independent timelines — 95% of consumers just ask "what time is it now?"** Only four code paths exploit clock *divergence*, and three of them are dead code.

---

## 2. The Problem in Technical Terms

### 2.1 The mechanism

- `engine/autoloads/timekeeping.gd:127` — `_party_clocks: Dictionary` (party_id → elapsed_rounds), persisted eagerly to the `party_clocks` table (schema.sql:1066-1073, migration 004).
- `timekeeping.gd:24-27` (header contract): *"`_elapsed_rounds` always equals the leading party's time. Boundary signals fire against the global clock only."* Implemented by `_sync_global_to_leader()` (timekeeping.gd:517-526): global = max(party clocks); boundary signals (round/turn/hour/day/month/year/dawn/dusk/season) emit only for the delta past the previous max.
- `engine/subsystems/session/scheduler_loop.gd` — the real-time loop. `_party_id` is injected once via `setup()` (session_runner.gd:642, from `load_session`) and never updated; `set_party_id()` (scheduler_loop.gd:120) has **zero callers**. All clock reads/advances in the tick loop (lines 251, 255, 266, 272, 298, 302) use this frozen `_party_id`.
- The primary party itself is arbitrary: `session_load_state.gd:156-163` selects `SELECT id FROM parties WHERE campaign_id = ? LIMIT 1` — **no ORDER BY**, so for a multi-party save the "primary" is whichever row SQLite returns first.

### 2.2 The core incoherence

The event queue is a **single number line** of fire_times, but each scheduling site interprets that number line through a **different party's clock**:

- Scheduling sites stamp fire_times from the *owning* party's clock — e.g. `wilderness_handlers.gd:179` (`travel_leg` from `get_party_time(party.id)` where party = the **active** party, via `wilderness_explore_state.gd:357-361`).
- The loop resolves the queue against the *primary* party's clock and advances only that clock (`scheduler_loop.gd:255-272`).
- When the owning party's clock ≠ the primary's clock: lagging-owner events have `fire_time < primary_time` and resolve instantly (`scheduler_loop.gd:258-260` clamps to "resolve now"); leading-owner events drag the primary's clock through time it never played.

### 2.3 The dead safety mechanism

`session_runner.gd:1386-1400` `check_party_time_lock`:

```gdscript
var leading: String = Timekeeping.get_leading_party()
if leading.is_empty() or leading == _party_id:
    _locked_parties.erase(_party_id)
    return
var leader_time: int = Timekeeping.get_party_time(leading)
if party_time > leader_time:
    _locked_parties[_party_id] = true   # UNREACHABLE
```

`get_leading_party()` returns the max-clock party. If the checked party is strictly ahead, it IS the leader → early-return unlocks. If it ties or trails, `party_time > leader_time` is false. The lock-set line is mathematically unreachable. Corroboration: `unlock_party()` (session_runner.gd:1409) has zero callers; no test exercises the lock; the 2026-04-23 build-log session already flagged it as primary-party-only with no follow-up; **the current scheduler GDD doesn't mention the lock at all** — it declares desync "acceptable" instead (gdd-realtime-scheduler.md §6.11).

### 2.4 Who actually produces clock divergence today

Only four production sites advance a *specific* party's clock outside the loop:

| Site | Push | Notes |
|---|---|---|
| `combat_finalizer.gd:49-59` | `rounds_fought`, then round UP to next turn boundary | ACKS RAW-derived (combat < 1 turn consumes a full turn). Pushes the **primary** party even if the active/fighting party differs. |
| `camp_state.gd:101-103` | 12 hours (town rest) | Wilderness camp instead schedules watch events resolved at MAX speed. |
| `location_cache_manager.gd:278-281` | 1 hour (hide-and-memorize cache) | Sole caller passes the **active** party. |
| `campaign_repository.gd:1063` (`merge_parties`) | `sync_parties()` — snaps **every** registered party to the leader | The only production `sync_parties` caller. |

And two production sites advance the **global** clock directly, silently desyncing it from all party clocks:

- `out_of_combat_cast_flow.gd:237` — `advance_rounds(1)` after scheduling cast events on the **party** clock (confirmed bug; should be `advance_party_rounds`).
- `override_panel.gd:1428-1434` — the GM/debug time-advance tool moves only the global clock; party clocks stay behind forever (nothing re-syncs outside merge).

---

## 3. Complete Consumer Inventory

> Method: exhaustive grep of `engine/`, `scenes/`, `tests/`, `tools/`, `db/` for every multi-party API symbol, 2026-06-11. `tools/` has zero hits. This is the "cover all the bases" checklist — any redesign must account for every row.

### 3.1 `get_party_time` — production call sites, classified by purpose

Purpose codes: **(a)** fire_time computation for scheduling · **(b)** gating/duration comparison · **(c)** display/ETA · **(d)** persistence timestamp · **(e)** other (weather/julian-day lookups).

| Site | party_id passed | Purpose |
|---|---|---|
| scheduler_loop.gd:255, 298 | `_party_id` (frozen primary) | (b) core loop: rounds-to-event |
| combat_finalizer.gd:55 | primary | (b) turn-boundary remainder |
| commission_pipeline.gd:56 | primary (via load_session) | (a) construction tick seed |
| out_of_combat_cast_flow.gd:214 | primary | (a) cast sentinel fire_times |
| settlement_explore_state.gd:321 | primary | (b/d) shop restock staleness |
| settlement_explore_state.gd:546 | primary | (b) `_is_nighttime` (note: hardcodes 18:00/06:00 — separate confirmed bug) |
| dungeon_explore_state.gd:405, 794, 809 | primary | (a) light action / loot / pick-up-all completions |
| dungeon_explore_state.gd:1391 | primary | (d) abandoned-character timestamp |
| camp_state.gd:105 | primary | (a) town-rest completion |
| session_runner.gd:906 | **every party** (payday loop) | (d) specialist wage timestamps |
| session_runner.gd:1389, 1395 | primary + leader | (b) the dead time-lock |
| wilderness_handlers.gd:171, 179 | **active** party (PartyData arg) | (a) travel-leg fire_times |
| wilderness_handlers.gd:241, 264 | **every party** (day/noon tick seeding) | (a) per-party midnight/noon |
| wilderness_handlers.gd:375, 382, 450, 455 | **event.owner_id** | (e/d) weather lookup + encounter-gate day stamp |
| wilderness_handlers.gd:587, 653 | **event.owner_id** | (a) activity-hour follow-ups |
| wilderness_handlers.gd:1324, 1328, 1385, 1502, 1689, 1746 | **event.owner_id** (activity resolvers) | (d/e) hunt/survey/lair stamps |
| wilderness_handlers.gd:2273 | **event's party** (`_pending_encounter_party`) | (a+d) pursuit catch-up scheduling + stamps |
| settlement_handlers.gd:99, 188 | primary (threaded) | (a) PoI travel / activity fire_times |
| dungeon_handlers.gd:154, 563, 1737 | primary (threaded) | (a) dungeon cadence/action/movement fire_times |
| dungeon_handlers.gd:1701 | **primary — ignores event.owner_id** (inconsistency) | (a) light burn-out |
| domain_handlers.gd:70 | primary | (a) monthly tick seed (owner is `"domain_global"`!) |
| camp_handlers.gd:63 | primary (threaded) | (a) watch chain fire_times |
| activity_time_cost_executor.gd:511 | threaded from UI; **`""` falls through to private `Timekeeping._elapsed_rounds` read** (line 513, behind a `has_method("get_total_rounds")` guard for a method that doesn't exist) | (b+a) cooldown gate + session scheduling |
| shop_panel.gd:329, 528, 545 | primary | (c/b/a/d) commission UI + creation + pickup gate |
| specialist_hire_panel.gd:194, 208, 229 | primary (panel field) | (d/a/b) hire/commission stamps + availability |
| specialists_tab_page.gd:105, 255 | **GameState.active_party_id** | (b/c/d) readiness display + collect |
| entity_outliner.gd:241 | **GameState.party_id (primary, NOT active)** | (c) ETA strings |

**Reading of this table:** every row uses the value as "now" in that party's frame. No production site measures or depends on the *difference* between two party clocks except the dead lock (session_runner.gd:1389/1395).

### 3.2 Clock advancement — production sites

| API | Sites |
|---|---|
| `advance_party_rounds/_turns/_hours` | scheduler_loop.gd:251, 266, 272, 302 (loop, frozen primary); combat_finalizer.gd:53, 59; camp_state.gd:101; location_cache_manager.gd:280 |
| Global `advance_rounds/_turns/...` in production | out_of_combat_cast_flow.gd:237 (**bug**); out_of_combat_cast_flow.gd:211 (test-fallback branch, acceptable); combat_finalizer.gd:62 (empty-party fallback, unreachable in a loaded session); session_runner.gd:1206-1209 `advance_exploration_time` (**zero production callers — dead**); override_panel.gd:1428-1434 (GM tool, **divergence vector**) |
| `advance_to_hour` / `advance_to_next_day` | test-only |
| Handlers advancing clocks during event resolution | **none** (grep of handlers/ = zero hits) — handlers only return next_events |

### 3.3 Registration, sync, lock, and lifecycle

| Symbol | Production sites |
|---|---|
| `register_party` | session_runner.gd:628 (primary only, at load); wilderness_explore_state.gd:66 (ALL parties, on wilderness enter); campaign_repository.gd:1034 (split — new party registered **at global time, not the source party's time**) |
| `unregister_party` | campaign_repository.gd:1109 (merge source) |
| `sync_parties` | campaign_repository.gd:1063 (merge — snaps ALL parties, not just the two merging) |
| `get_leading_party` | session_runner.gd:1390 (dead lock) — only caller |
| `get_time_gap` | **zero production callers** (timekeeping.gd:409; tests only) |
| `check_party_time_lock` | called from wilderness_explore_state.gd:88, settlement_explore_state.gd:103, dungeon_explore_state.gd:268 (state enter/exit) |
| `is_party_locked` | wilderness_explore_state.gd:184 (gates orders for the **active** party — but the lock dict is keyed by the **primary**: a second mismatch); settlement_explore_state.gd:219 |
| `unlock_party` | **zero callers** |
| `SchedulerLoop.set_party_id` | **zero callers** |
| `party_clocks` table readers | Timekeeping.load_state (timekeeping.gd:453); the savegame snapshot system (campaign_repository.gd:5169 scope map — generic DELETE + INSERT…SELECT, never interprets values); deletes in delete_campaign (:435) and unregister. Nothing else reads it. |

### 3.4 Party lifecycle (split / merge / active-switch)

- **Split** (campaign_repository.gd:865-1036; UI: party_tab_page.gd:1377-1390 → party_split_dialog.gd:226; reachable from the Notebook in ANY context, including mid-dungeon): registers the new party's clock **at global time** (not the source's), emits `party_split`. **No scheduler interaction**: the new party gets **no `wilderness_day_tick`/`wilderness_noon_tick`** until wilderness is next re-entered — no sustenance/foraging ticks meanwhile.
- **Merge** (campaign_repository.gd:1042-1111; UI: party_tab_page.gd:1359-1374): `sync_parties()` first, then transactional member/asset moves, then `unregister_party(source)`. **Queued events owned by the dissolved party are orphaned** — not cancelled, not re-owned; they fire later, `_party_data_for_event` returns null, handlers silently no-op. **Hazard:** the merge dropdown does not exclude the session primary — merging the primary INTO a detachment leaves `SessionRunner._party_id`/`SchedulerLoop._party_id` pointing at a deleted party: every tick then calls `advance_party_rounds(<deleted id>)` → push_error spam and a **permanently frozen clock**.
- **Active-party switch** (writers: wilderness token click wilderness_explore_state.gd:170-173; Notebook dropdown party_tab_page.gd:1350-1356, available in any context): exactly **one** gameplay reader assumes active-party semantics for scheduling (the wilderness context menu → travel orders owned by the active party); **zero** readers re-point any clock. The HUD party-selector widget (`party_selector_tabs.gd`) is built but **never instantiated** — dead scene.
- **Load:** `load_session` registers only the primary. Other parties' clocks come back via `Timekeeping.load_state` (if they have rows) or wilderness enter. **A save loaded directly into dungeon/settlement leaves second parties unregistered** — `get_party_time` for them push_errors and falls back to global.

### 3.5 Tests encoding multi-party expectations (must be updated by any redesign)

| Suite | What it asserts |
|---|---|
| test_timekeeping.gd:80, 370-416 | The per-party API itself: divergence, leader, sync, gap |
| test_scheduler_loop.gd:38-52, 132, 174, 242 | Loop advances TEST_PARTY's clock (pokes `_party_clocks` directly) |
| test_party_split_merge.gd; test_party_membership_invariants.gd | Split/merge contracts incl. clock register/unregister |
| test_wilderness_day_tick.gd | Day-tick fire-time math off the party clock (register-to-global semantics relied on at :178) |
| test_camp_encounter_gate.gd | Camp scheduling off `get_party_time(pid)` |
| test_out_of_combat_casting.gd:163-239, 384-385 | Cast fire_times off the party clock |
| test_settlement_handlers_v2.gd:76-124; test_location_cache_manager.gd:520-534; test_lair_placement.gd:121/157; test_session_runner.gd:117 | Fixture-level party-clock plumbing |
| test_savegame_snapshot.gd:42-49 | `party_clocks` must stay in the snapshot scope map — renaming/dropping the table fails this until the scope map is updated |

No test exercises CombatFinalizer's time push, the time-lock, or `set_party_id`.

---

## 4. Design History — Is It a Holdover?

**Split verdict, mechanism by mechanism** (sources: build_log.md sessions 2026-03-27, 2026-04-13/14, 2026-04-18, 2026-04-23; gdd-realtime-scheduler.md; coding_conventions.md §6.8/§19.5):

1. **Per-party timestamps: a pre-scheduler artifact that was deliberately re-adopted and is now load-bearing.** Built 2026-03-27 under the OLD session-runner state-machine architecture, "for split-party play" (migration 004 comment). The `sync_parties()` doc comment — *"Call at end-of-day reconciliation (session runner responsibility)"* — is a fossil of the abandoned simultaneous-declaration day-cycle model (the day planner was built the morning of 2026-04-13 and deleted that same day when the EventScheduler replaced it). BUT the scheduler build consciously kept party clocks (combat turn-rounding "uses party clock + rounds up per ACKS RAW" is a recorded Decision), and the 2026-05-27 GDD pass canonized them (§1.2, §6.11). Today they carry: combat turn-rounding, per-party day/noon ticks (sustenance, foraging, weather, encounter budget), split/merge, and the savegame contract. **Not a pure holdover — but the surrounding architecture it was designed for is gone.**
2. **The party time-lock: stillborn.** Designed in the same session that killed the day planner, against a mental model where a "world clock" could trail a party. The Timekeeping implementation (global ≡ leader) makes the trigger condition impossible. Never worked, never tested, unlock never wired, dropped from the current scheduler GDD (which declares desync "acceptable" instead). Only conventions §19.5 and the savegame GDD still describe it as real. **Holdover of the architecture transition itself.**
3. **`sync_parties()` as end-of-day reconciliation: pure holdover.** Its promised caller belongs to the deleted day-cycle model; it survives only as merge-time sync.
4. **The dungeon-async connection** (Jedidiah's second hypothesis): partially confirmed. The asynchronous-dungeon design is real and current — gdd-realtime-scheduler.md §6.11: *"No bubble… Cross-party time desync can happen (one party in a long dungeon while another travels the wilderness) and is acceptable — each party advances on its own clock; cross-party physical interactions resolve when their cells align in space and time."* Per-party clocks are the intended substrate for that. What's missing is the other half: the loop never switches which clock it advances, signals/effects never went per-party, and the lock that was supposed to police the gap never worked. **The vision is real; the mechanism is half-built.**

---

## 5. Authoritative-Document Constraints

Any redesign must honor these or get explicit sign-off to amend them:

**Layer 3 — Design Brief (ARCHITECTURAL; Jedidiah sign-off required to change):**
- §8.3: *"Each party has an independent timestamp via `Timekeeping.advance_party_rounds(party_id, n)` — there is no single global clock. Cross-party interactions resolve naturally when entities share a spatial location at the same timestamp… Combat pauses the active party's SchedulerLoop… on resume, advance_party_rounds(party_id, rounds_fought)…"*
- §10.3: split/regroup *"with time synchronization via the EventScheduler — each party… on its own clock."*
- §16.1 Tier 1: "Timekeeping (… multi-party sync)."
- §7: "Context is entity-level, not a global game state."

**Layer 2 — GDDs (modifiable, but cross-referenced):**
- gdd-realtime-scheduler.md §1.2 (per-party timestamps; "SchedulerLoop is configured for the active party at any moment" — **note: this sentence describes intent, not the implementation; the loop is configured once**), §6.8-6.9 (combat advance + past-due carve-out), §6.11 (no-bubble, desync acceptable).
- gdd-savegame-system.md:8, 63-64, 280-281 — *"a save inside a dungeon must restore the party's advanced clock and the pending time-lock relationship."* **This GDD promises the time-lock works; it cannot. Must be amended regardless of the chosen option.**
- gdd-settlement-exploration-ui.md:278, 326; gdd-spell-system.md:195 (party-clock references).

**Conventions (living doc; update, don't silently break):** §6.8 (global = leader; signals global-only; sync example), §19.5 (party clock always; combat turn-rounding; party locking; dungeon time independence), §15.5 (merge syncs; wilderness-only v1).

**Sacred (cannot change):** ACKS RAW turn-rounding — combat shorter than a turn consumes a full turn. *Some* clock must absorb `rounds_fought` rounded up to the turn boundary, whatever happens to the rest.

---

## 6. Options

### Option A — Single shared timeline (recommended for the current game's scope)

One clock. `get_party_time(x)` returns it for any x; `advance_party_*` advances it; party_clocks rows become vestigial (keep the table for save-compat or drop it with a migration + scope-map update). "Party is busy" is modeled by an **order lock** keyed on pending committed events (party locked while it owns an unresolved `travel_leg`/`camp_rest_complete`/`dungeon_action_complete` chain), replacing the impossible time-lock with something that actually expresses the design intent ("this party is committed to an activity").

- **Fixes for free:** the §2.2 incoherence (instant-resolve/clock-drag), the merge-primary frozen-clock hazard, the cast-flow drift, the override-panel divergence, the split-at-global-time jump, the unregistered-party fallback errors.
- **Behavior change:** combat turn-rounding and the camp/cache pushes advance the *world*, so background parties' queued events inside the rounded window fire during the skip (arguably the correct semantics of a shared timeline; magnitudes are minutes-to-hours).
- **Costs:** amends Brief §8.3 ("no single global clock" sentence) and §10.3 — **requires Jedidiah sign-off**; amends gdd-savegame-system time-lock language; rewrites test_timekeeping.gd:370-416 and re-fixtures ~9 other suites (§3.5); conventions §6.8/§19.5 updates.
- **What it does NOT preclude:** the §6.11 "cells align in space and time" vision can still be honored later by re-introducing per-party clocks behind a designed interface (Option C) when split-party async play is actually built. The audit shows consumers treat `get_party_time` as "now()", so the API surface survives unchanged.

### Option B — Wire the active party through (NOT recommended as a standalone fix)

Connect `GameState.active_party_changed` → `SchedulerLoop.set_party_id` so the loop advances the selected party.

The lifecycle audit shows this is a half-measure that makes some things worse: it fixes only one of **four** stale pointers (`SchedulerLoop._party_id`, `SessionRunner._party_id`, `SessionRunner._party_data`, `GameState.party_id`). Combat fought by active party B would advance B's clock via the loop but `CombatFinalizer` still pushes A's (combat_finalizer.gd:51 uses `runner.get_party_id()`). Switching to a leading party makes every laggard-scheduled event past-due → burst-fire with auto-pause spam; switching to a laggard replays the leader's world events in the laggard's frame. Dungeon/settlement states schedule exclusively off the primary, so a Notebook party-switch mid-dungeon decouples clock from context. Done *completely* (all four pointers + switch-time reconciliation + per-owner event gating), Option B converges on Option C — at which point do C deliberately.

### Option C — True per-party timelines (the full §6.11 vision; defer until split-party play is a designed feature)

Each party advances independently; the loop gates each event against **its owner's** clock (per-owner queues or owner-aware peek); boundary signals, effect durations, dawn/dusk, paydays become per-party (or explicitly world-owned on a world clock); world-owner events (`domain_global`, sieges, strongholds) get an explicit world timeline instead of borrowing the primary's. Requires design answers: whose clock do domain ticks live on; what does the player see when watching party A while party B's clock runs; how do per-party effect durations interact with the shared ActiveEffectTracker; what does MAX speed mean with N clocks. This is a real feature build (GDD first), not a refactor.

**Recommendation:** Option A now, with the order-lock replacing the time-lock; keep Option C on the Future Direction list tied to a future split-party GDD. The deciding facts: (1) only dead code consumes divergence today; (2) the four divergence *producers* are small and re-scopable; (3) the single live multi-party behavior players can reach (split/merge + wilderness orders to the active party) is currently **broken** under the half-mechanism and **works** under Option A.

### If Option A is chosen: build it as "A+" — async-readiness deliberately preserved (PROPOSED, not yet ruled)

Jedidiah's review note flagged that the party clock "might be related to the asynchronous dungeon time frame" — and the archaeology (§4) confirms the async vision is real and current (GDD §6.11). So if Option A is chosen, it should be implemented on the assumption that **asynchronous timeframes (Option C) may well be where the game design ends up long-term.** Two requirements follow:

1. **Build A as a stepping stone, not a dead end.** Implementation must avoid demolishing anything that genuine async play will need. Concretely:
   - **Do not rip out the `get_party_time(party_id)` / `advance_party_rounds(party_id, n)` API shape.** Keep party-aware signatures everywhere; in Option A they all resolve to the single timeline, but every call site keeps threading the correct party_id (per-owner discipline stays mandatory — see the wilderness handlers' `event.owner_id` pattern, §3.1). When C arrives, the plumbing is already party-correct.
   - **Keep the `party_clocks` table and its snapshot-scope classification.** Vestigial under A (all rows equal the global clock), but dropping it forces a migration now and another migration back later.
   - **Keep `ScheduledEvent.owner_id` semantics and the per-party day/noon tick structure** (wilderness_handlers.gd:241/264). Under A these ticks all compute from the same clock; under C they diverge naturally. Do not collapse them into a single world tick.
   - **The order-lock should be keyed per-party** (party_id → blocking event ids), not a global busy flag — that is the C-compatible shape.
   - **Document in conventions §19.5** that the single timeline is a deliberate interim posture and which seams are reserved for per-party reactivation.
2. **A dormant GDD for the async model should be drafted** (gdd-async-party-time.md, marked DEFERRED) capturing the §6.11 vision and the open design questions from Option C (domain-tick ownership, per-party effect durations, multi-clock MAX speed, spectator semantics), so the eventual build starts from a design document rather than archaeology. Brief §8.3 should be amended to say "single shared timeline at present; per-party timelines are the planned end-state for split-party play" rather than deleting the async language outright.

---

## 7. Point Fixes Valid Under ANY Option (can land before/with the ruling)

1. `out_of_combat_cast_flow.gd:237` — `advance_rounds` → `advance_party_rounds(party_id, …)` (confirmed bug).
2. `override_panel.gd:1428-1434` — GM time-advance must advance party clocks too (or call `sync_parties()` after).
3. Merge guard — forbid merging away the session primary (or re-point `SessionRunner._party_id`/`_party_data`/`SchedulerLoop` to the survivor) (frozen-clock hazard, §3.4).
4. Split — seed the new party's day/noon ticks immediately (don't wait for wilderness re-enter); under any per-party posture also inherit the source party's clock instead of registering at global.
5. Merge — cancel or re-own queued events owned by the dissolved party (`cancel_all_for_owner(source_party_id)` at minimum).
6. `dungeon_handlers.gd:1701` `_handle_light_action` — use `event.owner_id`, not the runner primary (consistency with the wilderness handlers' owner discipline).
7. Delete dead API: `SessionRunner.advance_exploration_time`, `unlock_party`, `Timekeeping.get_time_gap` (test-only), and either fix or delete `check_party_time_lock`/`is_party_locked` per the chosen option.
8. `activity_time_cost_executor.gd:511-513` — add `Timekeeping.get_total_rounds()` and delete the nonexistent-method guard + private `_elapsed_rounds` read.
9. `entity_outliner.gd:241` — decide primary vs active party for ETA display (cosmetic; pick one and note it).

---

## 8. Open Rulings for Jedidiah

1. **Posture:** Option A (single timeline now, per-party later behind a designed feature — recommended, implemented as "A+" per §6 so the C-shaped seams survive), B (not recommended), or C (build the full async model now)?
2. **If A:** approve amending Brief §8.3/§10.3 wording per the A+ proviso ("single shared timeline at present; per-party timelines planned for split-party play") and the savegame GDD's time-lock clauses; approve replacing the time-lock with a per-party order-lock ("party is committed until its blocking events resolve") — does the order-lock gate ALL orders, or only travel/exploration orders (can a committed party still trade inventory, cast, etc.)?
3. **Combat rounding under A:** when combat ends and the clock rounds up to the turn boundary, the *world* advances — confirm that background parties' due events firing during that skip is acceptable (it matches "the world keeps moving" but differs from today's frozen-background behavior).
4. **Specialist paydays / domain ticks:** these currently stamp per-party times (session_runner.gd:906) and borrow the primary's clock for world-owned events (domain_handlers.gd:70). Under A both naturally land on the single timeline — confirm.
5. **Effect durations and dawn/dusk** were flagged in the original review as "should they ever be party-relative?" Under A the question dissolves (one timeline). It returns if/when C is built — record the preference now for the future GDD: per-party subjective durations, or world-clock durations?

---

## 9. Acceptance Checklist for the Implementing Session

- [ ] Every row of §3.1-3.4 accounted for (changed, shimmed, or explicitly unaffected).
- [ ] All §3.5 test suites green or consciously rewritten; `test_savegame_snapshot` scope map updated if the table changes.
- [ ] Conventions §6.8, §15.5, §19.5 updated; gdd-realtime-scheduler §1.2/§6.11 and gdd-savegame-system §63-64/§280 amended to match the ruling.
- [ ] Brief §8.3/§10.3 amended (Jedidiah-approved text).
- [ ] The §7 point fixes landed.
- [ ] Net-zero new failures vs the 433/19 baseline (measure on the second consecutive run; beware zombie-Godot DB locks).
- [ ] Build log entry appended (template per acks-build-log skill; run `--lint`).
