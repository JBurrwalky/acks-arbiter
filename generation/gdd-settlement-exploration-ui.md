# GDD: Settlement Exploration UI

**Document type:** Game Design Document (project-designed, modifiable)
**Status:** Approved — V1 implementation
**Version:** v2.0 (2026-05-02 — pure menu overlay; supersedes v1 streetgraph design)
**Depends on:** `gdd-realtime-scheduler.md` §4 (city layer architecture), `gdd-settlement-layout.md` v2 (settlement generation: districts + PoIs only), `gdd-ui-architecture.md` §2.2 (pausing side-overlay surface category), `ax_campaign_play.xml` (activity rules, minor/major activity classifications), `acore-setting-construction-rules.xml` (market class, specialist availability), `acore-monster-stocking-rules.xml` (City terrain encounter throw 6+)
**Replaces:** Prior v1 spec (interactive street graph, navigation throws, per-block movement, time-based encounter intervals, city overview widget)
**Blocks:** Settlement exploration implementation, urban encounter system, hijinks/mercantile UI

---

## 1. Design Rationale

### 1.1 V1 = pure menu overlay

The settlement is a **menu overlay** on the existing world view. The hex map remains visible behind the overlay; the world clock is auto-paused while the menu is open. Travel between PoIs is a single scheduled event; resolution is a flat 1-turn (intra-district) or 1-hour (cross-district) advancement.

There is no settlement map renderer, no street graph navigation, no character/PoI pins, no decorative settlement portrait in V1. Each PoI exposes its activities through a panel that surfaces on PoI selection (current location) or on travel arrival.

### 1.2 What changed from the prior streetgraph design

The previous v1 spec retained an "under-the-hood" street graph used for A* pathfinding between PoIs, per-block travel time calculation (90 sec commuting / 10 min meandering per block), an urban Navigation throw (11+ on 1d20 every turn at commuting speed) with a 1d4+1 block "getting lost" deviation, four time-based urban encounter check intervals (every 1–6 turns depending on day/night × streets/alleys), straggling group commute penalties for parties of 6+, and a non-interactive city overview widget with character pins.

That apparatus has been removed. The remaining mechanical surface is:

- **Same-district travel:** 1 turn (10 minutes), 1 encounter check tagged with the current district.
- **Cross-district travel:** 1 hour (6 turns), 2 encounter checks (one per district at origin and destination), regardless of how many districts the destination is from.
- **No urban Navigation throw, no getting-lost deviation.** Wilderness Navigation rules ([`acore_proficiencies_rules_and_catalog.xml:872`](../rules/acore_proficiencies_rules_and_catalog.xml), [`ax_campaign_play.xml:374`](../rules/ax_campaign_play.xml)) are explicitly wilderness-only; ACKS does not require a parallel urban check, and the prior spec's "ACKS Sacred" tag on §3.3 was misattributed.
- **Encounter threshold 6+ on 1d6** per [`acore-monster-stocking-rules.xml:175`](../rules/acore-monster-stocking-rules.xml) (City terrain row, grouped with Grasslands/Scrub/Settled). The threshold does not vary by street vs alley or day vs night; the only modulation is the per-district `encounter_modifier` from [`gdd-settlement-layout.md`](gdd-settlement-layout.md).

### 1.3 V1 vs future enhancements

| In V1 | Deferred to future |
|---|---|
| Menu overlay at HUD layer 10 over the hex map | Decorative settlement portrait (purely visual; no functional pins or click targets) |
| District-grouped PoI list | Settlement layout regeneration with block polygons, walls, water (re-add when portrait ships) |
| Same-district vs cross-district travel | Time-of-day-driven encounter table swaps (UI flag plumbing exists; tables curated per district) |
| Auto-pause on menu open / settlement entry | NPC view inside the settlement menu (per [`gdd-journal-tab.md`](gdd-journal-tab.md) §6 Notes cross-surfacing) |
| Activity panel surfaces on arrival or PoI selection | Tick-tolerance multi-day activity migration (per [`gdd-domain-tab.md`](gdd-domain-tab.md) §15.1.2, Phase H+) |
| Left-click party token to reopen menu | Multi-character dispatch within the settlement (split-party UX) |

---

## 2. Surface placement and access

### 2.1 Surface category

The settlement menu is a **pausing side overlay** per [`gdd-ui-architecture.md`](gdd-ui-architecture.md) §2.2. It:

- Lives on a `CanvasLayer` at layer 10.
- Occupies the right ~40% of the viewport. The hex map and HUD chrome (clock, speed controls, entity outliner, party selector tabs, unified log) remain visible to the left.
- Auto-pauses the world while open. (This is an exception to §2.2's default that side overlays do not pause; called out in `gdd-ui-architecture.md` §2.2.)
- Can be dismissed by Esc (per §5.1 modal-cancel convention) or by an X button in its header. Dismissal does NOT resume the scheduler — the player resumes via the existing speed controls.
- Is covered (not closed) when the Management Notebook opens (notebook layer 30–49 per [`gdd-ui-architecture.md`](gdd-ui-architecture.md) §3). When the notebook closes, the settlement menu becomes visible again.

### 2.2 When the menu opens

Two triggers, both explicit:

1. **Settlement entry from the hex map.** Player clicks the "Enter Settlement" button (or selects an entry/exit PoI from the modal if multiple exist). The wilderness state transitions to the settlement state; the menu opens automatically with the entry PoI highlighted as `current_poi`.
2. **Left-click on the party token while in a settlement.** [`hex_map_renderer.gd`](../scenes/maps/hex_map_renderer.gd) emits `party_token_clicked(party_id, coord)`; the active settlement state opens the menu and pauses the scheduler. (Outside a settlement, the signal has no listeners and is a no-op.)

The menu does **not** auto-reopen on travel arrival or on mid-travel encounter checks. When those events auto-pause the scheduler, the appropriate UI surfaces independently: the activity panel for arrivals (§4), the encounter UI for encounters (§6.4). The player explicitly reopens the menu via party-token click when they want to issue a new travel order.

### 2.3 Active-party scoping

The menu always reflects exactly one active party. Switching parties via PartySelectorTabs (`EventBus.active_party_changed`) refreshes the menu; if the new active party is not in this settlement, the menu hides itself. This matches the [`gdd-ui-architecture.md`](gdd-ui-architecture.md) §3.5 active-party-scoping pattern used by the Management Notebook.

---

## 3. Menu layout

```
┌─────────────────────────────────────────────────────────────────┐
│  Hex map (zoomed on settlement hex)   │   Settlement menu        │
│  + standard HUD chrome                │   ├─ Header (name,       │
│                                       │   │   market class,      │
│                                       │   │   current district,  │
│                                       │   │   current PoI, ✕)    │
│                                       │   ├─ District sections   │
│                                       │   │   (collapsible)      │
│                                       │   │   ├─ PoI button rows │
│                                       │   │       [Name] [icon]  │
│                                       │   │       [10 min/1 hr]  │
│                                       │   │       [Open/Closed]  │
│                                       │   └─ Party status strip  │
│                                       │       (HP, currency)     │
└─────────────────────────────────────────────────────────────────┘

Activity Panel (separate CanvasLayer 10 sibling, surfaces on
PoI selection at current location or on travel arrival)
```

### 3.1 Header

| Element | Source |
|---|---|
| Settlement name | `SettlementData.name` |
| Market class | `SettlementData.market_class` (rendered as e.g. "Class VI") |
| Current district | `SettlementContext.current_district.name` |
| Current PoI | `SettlementContext.current_poi.name` |
| Close button | Emits `close_requested` |

### 3.2 PoI list

Vertical stack of district sections. Each section is a collapsible header showing the district name; the section containing `current_poi` is auto-expanded on menu open. Other sections start collapsed.

Each PoI row inside a section shows:

| Cell | Content |
|---|---|
| PoI name | "The Red Rooster Tavern" |
| Type icon | tavern / temple / shop / market / gate / etc. |
| Travel cost tag | "10 min" if same district as current PoI; "1 hr" if cross-district |
| Status | "Open" / "Closed" based on PoI hours and current time of day |
| Marker | "★" on the row that matches `current_poi` |

There are no "???" placeholders. **All PoIs are visible from entry.** The `visited_pois` table is retained (see §11) for narrative tracking only — quests and dialogue can ask "has the party ever been to the Temple of Ammonar?" — but visit state does not gate menu visibility.

Clicking a PoI:

- If it equals `current_poi` → open the activity panel (§4) for that PoI.
- Otherwise → schedule travel (§5), close the menu, resume the scheduler at SPEED_NORMAL.

### 3.3 Party status strip

Compact row at the bottom of the menu: portraits, HP, party currency (PP/EP/GP/SP/CP), encumbrance summary. Same component pattern as the rest of the chrome; not specific to the settlement menu.

---

## 4. Activity panel

When the player is at a PoI (either `current_poi` is selected in the menu or a travel arrival just auto-paused), an activity panel surfaces on a sibling CanvasLayer (layer 10) showing the activities available at that PoI.

The activity panel is a **peer of the settlement menu**, not a child of it, so it can surface on auto-pause without requiring the menu to be open.

### 4.1 Activity categories by PoI type

Same as the prior spec — unchanged. Reproduced here for completeness:

| PoI type | Available activities |
|---|---|
| Tavern/Inn | Rest (short/long), Gather Information, Carouse, Hire Henchmen, Recruit Mercenaries, Buy Food/Drink |
| Temple | Healing, Tithe, Commune, Commission Blessing |
| Shop (general) | Buy Equipment, Sell Equipment, Commission Equipment |
| Shop (specialist) | Buy/Sell specialist goods, Commission specialist items |
| Market/Town Square | Buy Equipment, Sell Equipment, Hire Hirelings, Post Notices, Gather Information |
| Guild Hall | Hire Specialists, Access Guild Services, Guild Quests |
| Lord's Keep | Audience with Ruler, Pay Taxes, Petition for Land Grant, Report Domain Events |
| Garrison | Recruit Mercenaries, Military Equipment, Garrison Services |
| Gate / entry-exit PoI | **Exit Settlement**, Guard Interaction |
| NPC Residence | Talk, Trade, Quest Interaction |
| Undercity Entrance | Enter Undercity (transitions to dungeon exploration) |

**Exit Settlement availability** is gated by the PoI's `is_entry_exit` boolean flag, NOT by `type == "gate"`. Any PoI can be an entry/exit point — taverns, market squares, road junctions, formal gates, any combination, in any subset of districts. Not every district must have an entry/exit PoI.

### 4.2 Activity timing

Per [`ax_campaign_play.xml`](../rules/ax_campaign_play.xml), activities are minor (negligible time, multiple per day, resolve immediately) or major (hours-to-day, schedule a completion event).

V1 keeps the existing simple model: completion events are one-shot scheduler events that fire and emit a notification. The tick-tolerance ongoing-activity model from [`gdd-domain-tab.md`](gdd-domain-tab.md) §15.1.2 is forward-looking Phase H+ work; settlement-initiated multi-day activities (carouse @ 1 day; future longer-running variants) will migrate to that model when it lands. Until then, settlement activities are autonomous-after-start with no absence forfeit semantics.

### 4.3 Multi-character activities

Same as prior spec. Each character in the settlement has their own scheduled events; characters can perform activities concurrently. Tracked per-character; clock advances to the next event for any character.

### 4.4 Embedded sub-panels

Three activity sub-flows have their own embedded panels, hosted inside the activity area:

- **ShopPanel** ([`scenes/ui/settlement/shop_panel.gd`](../scenes/ui/settlement/shop_panel.gd)) — buy/sell/commission, market-class-filtered inventory.
- **HiringPanel** ([`scenes/ui/settlement/hiring_panel.gd`](../scenes/ui/settlement/hiring_panel.gd)) — henchman pool, search fee, candidate interview.
- **SettlementActivityPanel** ([`scenes/ui/settlement/activity_panel.gd`](../scenes/ui/settlement/activity_panel.gd)) — generic activity picker, dispatches to the above when the player picks Buy/Sell or Hire.

These panels are unchanged in V1 except for the `is_entry_exit` flag swap in `activity_panel.gd`.

---

## 5. Travel mechanics

### 5.1 Cost rules (project-designed; not ACKS Sacred)

| Condition | Time cost | Encounter checks |
|---|---|---|
| Same district as current PoI | 1 turn (60 rounds = 10 minutes) | 1 check tagged with current district |
| Different district from current PoI | 1 hour (6 turns = 360 rounds) — flat | 2 checks: one tagged with origin district, one tagged with destination district |

Notes:

- Encumbrance, mounts, party size, and the prior commute/meander split do **not** affect settlement travel time. Settlement movement is fixed by the rule above.
- The cross-district cost is flat regardless of how many districts the destination is from. There is no district adjacency graph.
- The 10-minute and 1-hour buckets align with ACKS standard exploration time granularity; the per-district encounter check approximates [`acore-monster-stocking-rules.xml`](../rules/acore-monster-stocking-rules.xml)'s "City: 6+" terrain throw frequency without per-block bookkeeping.

### 5.2 Scheduled events

Travel commit schedules:

| Event | Fire time | Data |
|---|---|---|
| `city_travel_arrival` | `now + total_rounds` | `dest_poi`, `origin_poi`, `settlement_id`, `campaign_id` |
| `city_encounter_check` (intra-district) | `now + ROUNDS_PER_TURN/2` (midpoint) | `district_id` (current), `is_night`, `settlement_id` |
| `city_encounter_check` (cross-district, 2 events) | `now + 2 × ROUNDS_PER_TURN` (origin district) and `now + 4 × ROUNDS_PER_TURN` (destination district) | `district_id` (origin or destination), `is_night`, `settlement_id` |

Cancellation is supported: `cancel_travel(scheduler, party_id)` removes the arrival event and any pending encounter checks. The party stops at its current PoI (no in-between position is tracked).

### 5.3 Travel interruption

While traveling:

- Player can re-open the menu (party-token click), pick a new destination → travel cancels and reschedules.
- An encounter check that fires during travel auto-pauses the scheduler. After the encounter resolves, travel continues to the original arrival event (which was scheduled at travel commit time and is still in the queue).

There is no manual cancel button in V1 (the travel indicator is removed). To cancel, the player reopens the menu and picks a different destination, or picks the current PoI.

---

## 6. Urban encounters

### 6.1 Encounter concept

Routine pedestrian traffic is not an encounter. An urban encounter represents an unusual incident or interruption — a public event, an unexpected interaction, a hostile approach.

### 6.2 Encounter check resolution

| Step | Action |
|---|---|
| 1 | `city_encounter_check` event fires at its scheduled time. |
| 2 | Roll 1d6. Threshold 6+ per [`acore-monster-stocking-rules.xml:175`](../rules/acore-monster-stocking-rules.xml). District `encounter_modifier` may shift the threshold (high-crime districts: 5+; safe districts: 7+). |
| 3 | If failed: no-op (no auto-pause, no notification). |
| 4 | If succeeded: handler returns `auto_pause: true`, `presentation: {type: "city_encounter_check", district_id, is_night, settlement_id}`. |
| 5 | Encounter UI fires; combat or non-hostile encounter resolves per the district's encounter table (`gdd-settlement-stocking.md`). |
| 6 | Travel continues from the still-queued `city_travel_arrival` event. |

### 6.3 Encounter table selection

The encounter table selector consumes:

- `district_id` — district this check is tagged for (drives table pick from settlement stocking data).
- `is_night` — set by `_is_nighttime()` in the settlement state from current Timekeeping.
- `settlement_id` — for stocking-table lookup.

V1 has no streets-vs-alleys distinction, no Looking-for-Trouble toggle. These were dropped with the rest of §3.3 of the prior spec.

### 6.4 PoI-specific encounters

Some PoIs have their own encounter tables that fire on activity selection (tavern brawls, market pickpockets, Thieves' Quarter shakedowns). These are driven by the activity panel, not the travel-time encounter check, and are unchanged from the prior spec.

---

## 7. Undercity transition

When the party selects an undercity entrance PoI's "Enter Undercity" activity, the settlement state transitions to the dungeon exploration state per [`gdd-dungeon-map-ui.md`](gdd-dungeon-map-ui.md). The settlement menu and activity panel close. Exiting the undercity returns the party to the surface PoI; the settlement state re-mounts the menu (closed; player reopens via party-token click).

---

## 8. Scheduler integration

| Player action | Scheduler events |
|---|---|
| Click PoI in same district | `city_travel_arrival` at +1 turn; 1 `city_encounter_check` at +30 rounds (midpoint) |
| Click PoI in different district | `city_travel_arrival` at +6 turns; 2 `city_encounter_check` at +2 turns and +4 turns |
| Click current PoI | No scheduler events; opens activity panel |
| Cancel travel (re-pick destination or pick current) | Remove pending `city_travel_arrival` and `city_encounter_check` events for this party |
| Buy/Sell at shop | No scheduler event (minor activity, immediate) |
| Commission equipment | `commission_ready` at +N days per ACKS |
| Gather Information (major) | `settlement_activity` at +24 turns (~4 hours) |
| Carouse (major) | `settlement_activity` at +144 turns (~1 day) |
| Hire Henchmen (post notice) | `settlement_activity` for response time per recruitment rules |
| Long Rest | `settlement_activity` at +48 turns (~8 hours) |
| Exit Settlement (at entry/exit PoI) | Immediate state transition to wilderness |

Removed in V1 (vs prior spec): `navigation_check`, `got_lost`. Both deleted from [`settlement_handlers.gd`](../engine/subsystems/session/handlers/settlement_handlers.gd) registrations.

---

## 9. Multi-party

Multiple parties can be in the same settlement simultaneously. Each has its own `SettlementContext` keyed by `party_id`. Travel and activity scheduling use the existing per-party `_active_travel` and per-party scheduler ownership. Switching parties via PartySelectorTabs refreshes the menu to the newly-active party (or hides it if that party is not in this settlement).

Split-party-within-settlement (individual character dispatch to different PoIs) is deferred to a future enhancement.

---

## 10. Time of day and PoI availability

Same as prior spec, unchanged.

| PoI type | Hours | After hours |
|---|---|---|
| Shop | Dawn to dusk | Closed (status "Closed until dawn"; no buy/sell options) |
| Market/Town Square | Dawn to ~2 hrs before dusk | Closed |
| Temple | Always (reduced services at night) | Healing always; other services dawn-to-dusk |
| Tavern/Inn | Always | Full services |
| Guild Hall | Dawn to dusk | Closed |
| Lord's Keep | Dawn to dusk | Emergency audience only |
| Gate / entry-exit | Always (may close at night in wartime) | Default open |

The PoI list shows Open/Closed status. Travel to a closed PoI is allowed; the activity panel on arrival shows reduced or no options.

---

## 11. Data model

### 11.1 Data consumed

| Data | Source | Used for |
|---|---|---|
| `SettlementData` (id, name, market_class, population_families, culture_id, terrain_context, districts, pois) | [`gdd-settlement-layout.md`](gdd-settlement-layout.md) generator output, persisted in `settlement_entrances.settlement_data` (JSON) | Menu population, district lookup, travel cost calc, activity availability |
| `SettlementContext` (current_poi_id, current_district_id) | Per-party in-memory state owned by SettlementExploreState | Travel cost calc, "current location" header, exit-settlement gating |
| Time of day | Timekeeping autoload | PoI Open/Closed status, encounter table day/night flag |
| Party data | CharacterData / PartyData | Status strip rendering, activity eligibility |
| Visited PoIs | SQLite `visited_pois` (narrative tracking only — does NOT gate menu visibility) | Quest/dialogue references ("you've been here before") |
| Urban encounter tables | Settlement stocking data per district | Encounter resolution |
| Rumor tables | [`gdd-quest-rumor-system.md`](gdd-quest-rumor-system.md) output | Gather Information results |

### 11.2 Data produced

| Action | Data change | Persisted? |
|---|---|---|
| Travel between PoIs | Schedule arrival + 1 or 2 encounter checks | Scheduler (in-memory) |
| Arrive at PoI | Insert into `visited_pois` if not already present (narrative tracking) | Yes (SQLite) |
| Buy/Sell equipment | Modify character inventory + currency | Yes (SQLite) |
| Commission equipment | Insert `commission_ready` event | Scheduler + SQLite |
| Hire henchman | Add henchman, deduct currency | Yes (SQLite) |
| Gather information | Mark rumor as heard | Yes (SQLite) |
| Long Rest | Advance party clock, heal | Yes (SQLite) |
| Exit Settlement | Transition state, close menu/activity panel | Yes (SQLite) |

### 11.3 Removed in V1

The following were retired with the prior spec:

- `known_city_routes` SQLite table — supported the urban Navigation throw exemption, which is gone. Drop via migration.
- `street_graph`, `blocks`, `walls`, `water_features` fields on `SettlementMapData` — no longer generated or consumed. Slim the type.
- `settlement_navigation.gd`, `settlement_travel_calculator.gd`, `settlement_encounter_scheduler.gd` — orphaned helpers.
- `settlement_map.tscn`, `settlement_map_renderer.gd` — interactive top-down map renderer.
- `city_overview_widget.gd` — non-interactive minimap with character pins.

`visited_pois` is retained but its consumer renames from "discovery gating" to "narrative tracking." `record_visited_poi(...)` and a renamed `get_visited_poi_ids(...)` (was `get_discovered_poi_ids`) survive in [`campaign_repository.gd`](../engine/autoloads/campaign_repository.gd).

---

## 12. Build guidance

### 12.1 What to build

1. **`SettlementData`** ([`engine/shared_types/settlement_map_data.gd`](../engine/shared_types/settlement_map_data.gd) — gut and replace) — slim type with id, name, market_class, population_families, culture_id, terrain_context, districts, pois, and lookup helpers (`get_poi`, `get_district`, `get_pois_in_district`, `get_entry_exit_pois`, `same_district`).
2. **`SettlementContext`** ([`engine/subsystems/exploration/settlement_map_controller.gd`](../engine/subsystems/exploration/settlement_map_controller.gd) — replace) — thin Node tracking `current_poi_id` and `current_district_id` per party.
3. **`SettlementMenu`** ([`scenes/ui/settlement/settlement_menu.tscn`](../scenes/ui/settlement/settlement_menu.tscn) + `.gd`) — right-side overlay panel: header, district-grouped PoI list, status strip, close button.
4. **Travel scheduling** in [`settlement_handlers.gd`](../engine/subsystems/session/handlers/settlement_handlers.gd) — `schedule_travel(settlement, current_poi_id, dest_poi_id, scheduler, party_id, campaign_id, settlement_id, is_night)`; emits 1 arrival + 1-or-2 encounter check events.
5. **Settlement state** ([`settlement_explore_state.gd`](../engine/subsystems/session/states/settlement_explore_state.gd) — rewrite) — auto-pause on enter, mount menu + activity panel as peer CanvasLayers, route signals, party-token-click reopen.
6. **Hex map party-token click** ([`hex_map_renderer.gd`](../scenes/maps/hex_map_renderer.gd)) — wire `party_token_clicked` signal emission on left-click; entry/exit PoI selection modal replaces gate selection modal.

### 12.2 What to delete

- `settlement_navigation.gd`, `settlement_travel_calculator.gd`, `settlement_encounter_scheduler.gd`
- `settlement_map.tscn`, `settlement_map_renderer.gd`
- `city_overview_widget.gd`
- Obsolete tests: `test_settlement_navigation.gd`, `test_settlement_travel_calculator.gd`, `test_settlement_map_data.gd` (replaced by `test_settlement_data.gd`), `test_settlement_map_controller.gd` (replaced by `test_settlement_context.gd`)
- DB migration: `DROP TABLE IF EXISTS known_city_routes`

### 12.3 What stays unchanged

- `shop_panel.gd`, `hiring_panel.gd`, `activity_panel.gd` (except entry/exit flag swap)
- `shop_inventory`, `commissions`, `henchman_pools`, `henchman_state` SQLite tables
- `settlement_entrances` SQLite table (settlement_data JSON shape simplifies in step with [`gdd-settlement-layout.md`](gdd-settlement-layout.md) v2)
- Timekeeping, EventScheduler, EventHandlerRegistry, SchedulerLoop, EventBus, DiceSystem
- `EventBus.settlement_entered`, `commission_ready`, `encounter_triggered` signals

---

## 13. Open questions

None. All prior open questions resolved by V1 simplification:

- City overview widget fidelity for large cities → widget removed in V1, deferred to future decorative-portrait enhancement.
- Route memory persistence → urban Navigation throw removed; `known_city_routes` table dropped.
