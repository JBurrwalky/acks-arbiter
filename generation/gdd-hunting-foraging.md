# GDD: Hunting and Foraging

**Authority:** HYBRID — Hunting and food-foraging mechanics are SACRED from `acore_adventures_and_encounters.xml` §rations_and_foraging. Per-character roll cadence, water foraging, and weather modifiers are PROJECT-DESIGNED elaborations.
**Status:** Phase 3 v1 implemented (2026-05-04).
**Depends on ACKS rules:** `acore_adventures_and_encounters.xml` (rations_and_foraging tree), `acore_proficiencies_rules_and_catalog.xml` (Survival proficiency).
**Depends on project GDDs:** `gdd-realtime-scheduler.md` (day-tick architecture), `gdd-weather-generation.md` (weather modifiers, atmosphere descriptors).

---

## 1. Purpose

Daily food and water acquisition for a wilderness party, plus the deliberate Hunt activity. Foraging tops up the abstract `ration_units` and `water_units` caches; sustenance consumption + penalty math lives in `SustenanceResolver` (`engine/subsystems/exploration/sustenance_resolver.gd`).

---

## 2. ACKS Rules Constraints (Sacred)

### 2.1 Foraging (`acore_adventures_and_encounters.xml` §rations_and_foraging.foraging)

> **Activity:** Can be done while traveling.
> **Check:** Proficiency throw 18+ on 1d20 per day of travel.
> **Success:** Food for 1d6 man-sized creatures.

### 2.2 Hunting (`acore_adventures_and_encounters.xml` §rations_and_foraging.hunting)

> **Activity:** Must be the only activity for the day; no travel is possible.
> **Check:** Proficiency throw 14+ on 1d20.
> **Success:** Food for 2d6 man-sized creatures.
> **Additional rule:** One wandering monster check is made during the day of hunting using the appropriate terrain table.

### 2.3 Survival proficiency (`acore_adventures_and_encounters.xml` §rations_and_foraging.survival_proficiency_bonus and `acore_proficiencies_rules_and_catalog.xml` Survival entry)

> "Characters with Survival proficiency gain +4 on hunt and forage throws."
>
> "Automatically forage enough food for self while moving in a fairly fertile area. If foraging for more than one person, make the normal proficiency throw with a +4 bonus."

### 2.4 Daily consumption + penalties (`acore_adventures_and_encounters.xml` §rations_and_foraging.daily_consumption / .lack_of_food / .lack_of_water)

* 1 stone of food + 1 gallon water per character per day.
* Food deficit: 2-day grace, then 1 hp/day, no natural healing during deficit.
* Water deficit: 1 day → 1d4 hp + 1d4/day, healing lost when first die rolled.

These curves live in `SustenanceResolver.apply_daily()`.

---

## 3. Project-Designed Elaborations

### 3.1 Per-character forage throws

ACKS RAW reads "Proficiency throw 18+ on 1d20 per day of travel" without explicit per-character qualifier. Phase 3 v1 interprets it as one throw per character per day. Successes stack additively: a 4-character party with 4 successes adds 4d6 person-feeds to `ration_units`. Rationale:

* Every other proficiency throw in ACKS is individual (a proficiency is taken by one character).
* Per-character cadence makes party size matter mechanically — a 6-character party should feed itself more reliably than a solo adventurer.
* Survival's "Auto-self-feed" flag from the proficiency catalog is naturally per-character.

This is a deviation from the strictest reading of RAW. A future Opus review can second-guess and switch to a single party-level throw if play experience suggests it.

### 3.2 Forage cadence on the day-tick (not per travel-leg)

Phase 1 of the closure plan considered per-travel-leg foraging. Phase 3 ships per-day on the `wilderness_day_tick` instead. Reasons:

* Handles non-traveling days uniformly (camp days, days spent on a single hex hunting).
* Matches the SustenanceResolver cadence — both run on the same tick, so the consumption + replenishment math is co-located.
* RAW says "per day of travel" — interpreted as "per day spent in the wilderness", which the day-tick gates correctly.

The handler skips foraging when the party is not in a wilderness hex (`party.current_location_type != "wilderness"`). Settlements abstract food/water; dungeons assume the party brought their own (Phase 3.5 polish may add dungeon-specific foraging).

### 3.3 Survival auto-self-feed

Per the Survival proficiency catalog: "Automatically forage enough food for self while moving in a fairly fertile area." Phase 3 v1 grants Survival characters a free +1 to `ration_units` on every wilderness day, on top of any 1d6 they roll for the group via the regular forage throw. The "fairly fertile area" qualifier is not gated in v1 (every wilderness biome auto-self-feeds for Survival members); Phase 3.5 may add a biome whitelist (clear / woods / hills / scrub) and exclude desert / frigid mountain.

### 3.4 Water foraging (RAW silent)

ACKS RAW has no procedure for finding water. Phase 3 v1 mirrors the food cadence:

| Condition | Result |
|---|---|
| `terrain.has_river()` | Auto-pass — `water_units` topped to `party_size` |
| `terrain.water == "lake"` | Auto-pass — same |
| `weather.atmosphere == ATMO_RAINY` | Auto-pass (rainwater collection) |
| Otherwise | 1d20 per character per day, target 14+ untrained / 10+ with Survival; each success +1d6 |

The 14+ target matches the hunting target — finding hidden water on dry land is harder than gathering plants. Container-fill UI (waterskins / barrels) is deferred to Phase 3.5 polish; v1 abstracts containers as the `water_units` cache.

### 3.5 Hunt as a deliberate full-day activity

Per the SACRED hunt rules ("must be the only activity for the day; no travel is possible"), Hunt is wired through the existing `wilderness_activity` event with `kind = "hunt"`, surfaced via the wilderness right-click context menu. The activity:

1. Halts travel for the day.
2. Picks the best available hunter — prefers a Survival member; falls back to the first member.
3. Rolls 1d20 + Survival bonus vs target 14.
4. On success: rolls 2d6 person-feeds, adds to `ration_units`.
5. Rolls one wandering monster check using the appropriate terrain table.
6. Auto-pauses on completion so the player sees the result and any encounter at once.

### 3.6 Weather modifiers (food forage)

Per `gdd-weather-generation.md` §7.3, the food forage throw takes weather penalties:

| Atmosphere / temperature | Modifier |
|---|---|
| Frigid (temp band 0) | −4 (nothing grows) |
| Heavy rain or snow (precip level 3) | −2 |
| Steady rain or snow (precip level 2) | −1 |
| Storm or blizzard (precip level 4) | Foraging impossible — 0 rolls |

Phase 2 v1 only generates precipitation levels 0 (calm) and 2 (steady); the level-3/4 hooks remain live for Phase 2.5.

Water foraging is not weather-modified — rainy auto-passes; otherwise the throw target is fixed at 14.

---

## 4. Implementation Map

| Concern | File |
|---|---|
| Daily consumption + penalty curves | [sustenance_resolver.gd](engine/subsystems/exploration/sustenance_resolver.gd) |
| Per-character forage rolls (food + water) | [foraging_resolver.gd](engine/subsystems/exploration/foraging_resolver.gd) |
| Hunt activity resolution | [hunting_resolver.gd](engine/subsystems/exploration/hunting_resolver.gd) |
| Day-tick wiring + signal routing | [wilderness_handlers.gd](engine/subsystems/session/handlers/wilderness_handlers.gd) `_handle_wilderness_day_tick`, `_resolve_hunt_activity` |
| Hunt context-menu item | [wilderness_context_menu_builder.gd](engine/subsystems/exploration/wilderness_context_menu_builder.gd) |
| Notebook Party-tab status row | [party_tab_page.gd](scenes/ui/notebook/tab_pages/party_tab_page.gd) `_refresh_travel_subtab` |
| Camp full-rest exhaustion clear | [camp_handlers.gd](engine/subsystems/session/handlers/camp_handlers.gd) `_handle_rest_complete` |
| DB schema | [049_party_sustenance_log.sql](db/migrations/049_party_sustenance_log.sql) |

---

## 5. Signals

| Signal | Emitted from | Listeners |
|---|---|---|
| `forage_resolved(party_id, result)` | day-tick handler (food + water separately) | NotificationManager toast, future Notebook history panel |
| `hunt_resolved(party_id, result)` | hunt activity handler | NotificationManager toast |
| `starvation_tick(character_id, hp_lost)` | day-tick handler | unified log, mortal-wound watcher |
| `dehydration_tick(character_id, hp_lost)` | day-tick handler | unified log, mortal-wound watcher |
| `sustenance_threshold_crossed(party_id, kind, threshold)` | day-tick handler | NotificationManager toast |

Toast tiers:

* `food_grace_expired` → warning ("Hungry").
* `starvation_first_hp_loss` → danger ("Starvation").
* `water_first_loss` → danger ("Dehydration").
* `starvation_recovery` / `dehydration_recovery` → success ("Sustenance Restored").

---

## 6. Deferred (Phase 3.5 / later)

* Inventory ↔ `ration_units` sync. Iron rations in inventory currently exist as a parallel system. Phase 3.5 polish ties `inventory_changed` to a one-way sync that adjusts `ration_units` when iron rations are bought / sold / dropped.
* Container fill UI. Waterskins and barrels currently abstract into `water_units`. A future polish surfaces a "fill containers" prompt at river/lake hexes when the player has empty inventory containers.
* Trained creatures and mounts in the consumption count. Phase 3 v1 counts only `character_data` (PCs + henchmen). Animals are not part of `party_size`. The existing Notebook Travel sub-tab DOES show fodder/water for animals from inventory items; that is decoupled from the abstract caches.
* Biome whitelist for Survival auto-self-feed. Currently every wilderness biome auto-self-feeds; RAW says "fairly fertile area".
* Hunter picker UI. v1 picks the first Survival member or first character; a future picker lets the player choose.
* Settlement ration purchase flow that adds to `ration_units` directly.
* Dungeon sustenance — currently the day-tick is gated to wilderness; a multi-day dungeon trip silently doesn't consume rations.
* Rest-day accumulation per `acore_adventures_and_encounters.xml` rest rules ("1 day per 6 days; cumulative −1 attack/damage"). The `exhaustion_days` counter is wired and CampManager clears it; the consumption and penalty side need a future tick.
