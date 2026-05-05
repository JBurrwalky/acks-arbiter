# GDD: Lair and POI Discovery

**Authority:** HYBRID — Lair-search math, +4 Tracking bonus, Land Surveying assessment, and aerial-recon doubling are SACRED from `le_wilderness_lair_rules.xml`. The passive lair-spot on travel_leg, and the Phase 6 Pathfinder bonus pass-through, are PROJECT-DESIGNED.
**Status:** Phase 4 v1 implemented (2026-05-04).
**Depends on ACKS rules:** `le_wilderness_lair_rules.xml` (full file), `acore_proficiencies_rules_and_catalog.xml` (Tracking, Land Surveying entries).
**Depends on project GDDs:** `gdd-realtime-scheduler.md` (wilderness_activity event type), `gdd-poi-generation.md` (broader POI taxonomy; this GDD is the discovery-side counterpart).

---

## 1. Purpose

Reveal placed-but-undiscovered monster lairs (and, in a forthcoming pass, wilderness POIs) on the regional hex map through three discovery paths:

1. **Dedicated full-day lair search** — context-menu activity, runs through `wilderness_activity` with `kind = "search_lair"`.
2. **Passive spotting on travel** — every travel_leg into a hex with undiscovered lairs rolls one passive throw.
3. **Land Surveying assessment** — context-menu activity, estimates the *count* of lairs (without revealing locations).

Aerial reconnaissance (×2 daily movement) is a Phase 7 add-on — the resolver exposes the `is_aerial` flag now so the wiring lands without a signature change.

---

## 2. ACKS Rules Constraints (Sacred)

### 2.1 Abstract search procedure (`le_wilderness_lair_rules.xml` §searching_for_lairs.abstract_search_procedure)

> **Step 1.** "For each hour of searching, equal to six turns, make one secret searching throw on behalf of the party using 1d20."
> **Step 2.** "Determine the target value from the party's daily movement rate through the hex using the lair_search_target_values table." (target 18+ at ≤11 mi → 2+ at ≥192 mi).
> **Step 3.** "If the die roll equals or exceeds the target value, the party discovers a lair if at least one lair is present."
> **Step 4.** "If more than one lair is present, choose one or determine it randomly."

### 2.2 Tracking bonus (`le_wilderness_lair_rules.xml` §searching_for_lairs.tracking)

> "If any party member has the Tracking proficiency, the party receives a +4 bonus on the lair search roll."

Applied to **dedicated search throws only**, not passive spotting.

### 2.3 Aerial reconnaissance (`le_wilderness_lair_rules.xml` §searching_for_lairs.aerial_reconnaissance)

> "If the party is capable of air travel, double its daily wilderness movement rate."
> "When searching clear, grass, scrub, hills, barren, desert, or mountain terrain by air, the party receives one search throw every three turns, or thirty minutes, instead of one per hour."

The doubling lands in `LairSearchResolver.compute_target_value(daily_miles, is_aerial=true)`. The half-hour cadence is Phase 7 work (no flying mounts wired in Phase 4).

### 2.4 Wandering monsters (`le_wilderness_lair_rules.xml` §searching_for_lairs.wandering_monsters)

> "Adventurers searching a hex are subject to one wandering encounter throw per hour while searching."

Phase 4 fires one wandering check per simulated hour during dedicated search. On encounter trigger, the search halts and combat enters via the existing `enter_combat` return contract.

### 2.5 Land Surveying assessment (`le_wilderness_lair_rules.xml` §searching_for_lairs.land_surveying)

> "A character with the Land Surveying proficiency may attempt to assess the total number of lairs in a hex…"
> Procedure step 2: "The base target value is 18+."
> Procedure step 3: "Apply a cumulative +4 bonus for each successful search the party has conducted in that hex up to that point."
> Procedure step 5: "If the throw fails with an unmodified 1, the character makes an incorrect assessment, and the Judge rolls or chooses a false number to reveal."
> Procedure step 6: "On any other failure, the character does not yet have enough information to make or revise an assessment."

Implemented exactly. The "false number" is rolled by `SurveyingResolver` as `actual ± 1d4` clamped to ≥0, using two scripted dice (`land_surveying_false`, `land_surveying_false_sign`) so tests can pin the outcome.

---

## 3. Project-Designed Elaborations

### 3.1 Per-leg passive lair-spot

ACKS RAW addresses two ways the party finds a lair: deliberate search, and the §wandering_monsters substitution rule ("If the party accidentally wanders into a lair, substitute the newly encountered lair for one of the previously generated lairs"). Phase 4 introduces a third path — a soft passive throw fired at the end of each travel_leg into a hex with undiscovered lairs.

Mechanics:

* One 1d20 per travel_leg (*not* per hour — passing through is faster than searching).
* Target value pulled from the daily wilderness movement rate the party is making in this hex (so faster parties spot more lairs, matching the RAW table's slope).
* No Tracking bonus (the party isn't deliberately scouting).
* Specialist bonus (Phase 6 Pathfinder) DOES apply.
* Success: reveal one undiscovered lair, fire `lair_discovered` with `via = "passive"`, route a soft toast. Travel does NOT halt.

Rationale:

* RAW's substitution rule gates accidental discovery on a wandering encounter rolling a lair — that's already how the existing encounter pipeline behaves. The passive throw adds a *visible* discovery channel that doesn't require a combat encounter to trigger. Without it, lairs in low-traffic hexes can stay invisible for entire campaigns.
* Per-leg cadence (rather than per-hour or per-day) keeps the touch points local to the existing event flow.
* Suppressing Tracking deliberately leaves the dedicated-search activity meaningfully better — Tracking is for *finding*, the passive throw is for *noticing*.

### 3.2 Specialist bonus pass-through (Phase 6 hook)

Per the closure plan, specialists (Pathfinder, Land Surveyor, Cartographer per `acore_equipment.xml §specialists` and `le_wilderness_lair_rules.xml` §hirelings) are deferred to Phase 6 as their own subsystem. To land the wiring without Phase 4 → 6 signature churn, both `LairSearchResolver.search_hour` and `LairSearchResolver.passive_check` accept an `optional_specialist_bonus: int = 0` parameter. Phase 4 always passes 0; Phase 6 wires `SpecialistBonusResolver.bonus_for(party, "lair_search")` into the call site.

`SurveyingResolver.assess` does not yet have a specialist hook — when Phase 6 lands the Land Surveyor specialist, that signature will gain a similar parameter (additive, no rewrite).

### 3.3 Eager lair / POI placement vs. lazy reveal

Both `lairs` and `pois` tables in migration 050 carry a `discovered: int (0/1)` flag. Phase 4 assumes records exist before they are revealed — placement is the responsibility of the world-gen / setting-generation pipeline (out of scope for this GDD; covered by `gdd-poi-generation.md` for non-lair POIs, and by an upcoming setting-gen pass for lairs).

For Phase 4 v1, lairs are placed by:

1. **Setting generation** (eager, recommended path — not yet wired) — per `le_wilderness_lair_rules.xml` §securing_land.lair_generation_procedure and the `lairs_per_hex` table.
2. **First lair-encounter substitution** (RAW §placement_procedure) — when a wilderness encounter throw resolves to a monster *in its lair*, place a lair record in that hex with `discovered = 1`. This wiring is a Phase 5 follow-up tied to the encounter-resolution rewrite.
3. **Tests** — manually populate `lairs` rows via `CampaignRepository.create_lair`.

### 3.4 Survey activity does not count as a "search"

Per RAW's §land_surveying.assessment_rules, a Land Surveying member "may attempt one assessment on first arriving in the hex, and one additional assessment each time the hex is searched." The cumulative +4 bonus comes from "successful searches the party has conducted." The Survey activity itself does NOT count as a search for the bonus — only `search_lair` activity successes do. Phase 4 enforces this by reading `successful_searches` from `survey_progress` for the bonus and only incrementing it inside `_resolve_lair_search_activity` on a successful throw.

### 3.5 Search activity v1 simplification

RAW models search as N hours of independent throws, each consuming time and rolling its own wandering check. Phase 4 v1 collapses the 8 simulated hours into a synchronous block:

1. Roll one search throw → if `lair_found`, reveal and stop.
2. Roll one wandering encounter check → if triggered, halt and route to combat.
3. Otherwise loop through to hour 8.

The party's clock does NOT advance 8 hours within the handler (mirroring Hunt's deliberate-day model — time-passing is handled at camp). A Phase 4.5 polish may convert this to 8 scheduled events at +1hr cadence so the world ticks during the search.

---

## 4. Implementation Map

| Concern | File |
|---|---|
| Target-value table + Tracking bonus + per-hour throw | [lair_search_resolver.gd](engine/subsystems/exploration/lair_search_resolver.gd) |
| Land Surveying 18+ assessment + cumulative bonus + false reading | [surveying_resolver.gd](engine/subsystems/exploration/surveying_resolver.gd) |
| Survey + Search activity wiring + passive check on travel_leg | [wilderness_handlers.gd](engine/subsystems/session/handlers/wilderness_handlers.gd) `_resolve_survey_activity`, `_resolve_lair_search_activity`, `_passive_lair_check` |
| Context-menu items (Survey, Search for Lairs) | [wilderness_context_menu_builder.gd](engine/subsystems/exploration/wilderness_context_menu_builder.gd) |
| action_type → activity_type mapping | [wilderness_explore_state.gd](engine/subsystems/session/states/wilderness_explore_state.gd) `_activity_type_for_action` |
| Hex hover lines (revealed lair count + survey estimate) | [hex_map_renderer.gd](scenes/maps/hex_map_renderer.gd) `_lair_tooltip_line`, `_survey_estimate_tooltip_line` |
| Lair / POI / survey persistence | [campaign_repository.gd](engine/autoloads/campaign_repository.gd) — `create_lair`, `count_undiscovered_lairs`, `count_lairs_in_hex`, `reveal_one_lair`, `list_discovered_lairs`, `create_poi`, `reveal_poi`, `get_survey_progress`, `upsert_survey_progress` |
| DB schema | [050_poi_discovery.sql](db/migrations/050_poi_discovery.sql), [051_surveying_progress.sql](db/migrations/051_surveying_progress.sql) |

---

## 5. Signals

| Signal | Emitted from | Listeners |
|---|---|---|
| `lair_discovered(party_id, result)` | dedicated search OR passive check | NotificationManager toast, hex map renderer (re-tooltip), future Notebook history panel |
| `poi_discovered(party_id, result)` | (resolver wiring deferred) | hex map renderer |
| `survey_completed(party_id, result)` | survey activity | NotificationManager toast, hex map renderer (re-tooltip) |

`result` payload keys are documented in `event_bus.gd` immediately above each `signal` declaration.

---

## 6. Deferred (Phase 4.5 / later phases)

* **Eager lair placement** during setting generation per `le_wilderness_lair_rules.xml` §lair_generation_procedure. Until this lands, lairs only appear via the §encounter substitution rule (Phase 5 work) or manual world-gen scripts.
* **POI discovery resolver wiring**. `pois` table exists; reveal flow needs the broader `gdd-poi-generation.md` system to generate the rows, which is its own work item.
* **Aerial reconnaissance half-hour cadence**. The 2× daily-movement doubling is wired (the `is_aerial` flag); the per-30-minute search rate isn't.
* **Per-hour scheduled events** for the search activity. v1 collapses 8 hours into one synchronous handler call.
* **Specialist bonuses**. Phase 6 wires Pathfinder / Land Surveyor / Cartographer to the existing `optional_specialist_bonus` parameter.
* **Sub-party splitting** per RAW §splitting_up. Currently a single party makes one throw per hour; sub-parties searching different sub-hexes is not modeled.
* **Tracking-driven trail rules** per `le_wilderness_lair_rules.xml` (none here) and `acore_proficiencies_rules_and_catalog.xml` Tracking entry — distinct from lair search; that's Phase 5 work tied to evasion/pursuit.
