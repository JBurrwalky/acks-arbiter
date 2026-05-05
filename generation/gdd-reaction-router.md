# GDD: Wilderness Reaction Router

**Authority:** HYBRID. The 2d6 reaction table and the five-state disposition mapping are SACRED from `acore_adventures_and_encounters.xml` §reactions. The mapping from disposition to session state (combat / encounter / avoid) is PROJECT-DESIGNED.
**Status:** Phase 5 v1 implemented (2026-05-04). Gated behind `WildernessReactionRouter.FEATURE_REACTION_ROUTER_ENABLED` so a regression can be rolled back without code surgery.
**Depends on ACKS rules:** `acore_adventures_and_encounters.xml` §reactions.
**Depends on project GDDs:** `gdd-evasion-pursuit.md` (catch-up routes back through the router for forced combat).

---

## 1. Purpose

When `SessionRunner.do_encounter_check` produces an encounter, the existing reaction-roll value (`behavioral_disposition`) is consulted to decide what state should handle it:

* **combat** — `CombatState.enter` (the legacy default).
* **encounter** — `EncounterState.enter` (parley UI).
* **avoid** — no state transition; travel resumes with a soft toast.

Phase 5 keeps `combat` for the cases that RAW classifies as actively-attacking (Hostile, Unfriendly), routes Neutral and Friendly into the parley path, and uses Indifferent for the silent pass-by.

---

## 2. ACKS Rules Constraints (Sacred)

`acore_adventures_and_encounters.xml` §reactions — Monster Reaction table:

| 2d6 (adjusted) | Result      | RAW notes |
|---|---|---|
| 2 or less      | Hostile     | "Attack immediately." |
| 3-5            | Unfriendly  | "Dislike the adventurers and will attack if it is reasonable to do so." |
| 6-8            | Neutral     | "Will consider letting adventurers live if they parley; not necessarily friendly." |
| 9-11           | Indifferent | "Will ignore adventurers if possible and negotiate if necessary." |
| 12 or more     | Friendly    | "Likes the adventurers and may cooperate in mutually beneficial ways." |

`SessionRunner.do_encounter_check` already rolls 2d6 with Charisma adjustment (sacred from `ax_reactions_and_influencing.xml`) and stamps the `behavioral_disposition` string onto encounter_data. Phase 5 adds the *consultation* step.

---

## 3. Project-Designed Mapping

| Disposition  | Routed action | Rationale |
|---|---|---|
| hostile      | combat        | RAW "Attack immediately." |
| unfriendly   | combat        | RAW "may attack." v1 always engages; future polish may surface a parley option even on unfriendly when Charisma / faction conditions warrant. |
| neutral      | encounter     | RAW "consider letting adventurers live if they parley." |
| indifferent  | avoid         | RAW "ignore adventurers if possible." Travel resumes uninterrupted with a soft toast. |
| friendly     | encounter     | RAW "may cooperate." Surfaces the parley UI for negotiation / recruitment. |

A future Opus review may rewrite the mapping based on monster ecology (carnivores stay aggressive on unfriendly; herbivores avoid; etc.). The router signature accommodates this by reading `encounter_data` as a whole rather than just the disposition string.

---

## 4. Feature Flag

`WildernessReactionRouter.FEATURE_REACTION_ROUTER_ENABLED` is a `const := true`. When set to false:

* All dispositions route to combat (legacy always-engage behavior).
* The flag is checked once per `decide()` call.
* Toggle and rebuild to roll back if Phase 5 introduces regressions in real play.

---

## 5. Handler Contract

`WildernessReactionRouter.decide(encounter_data, feature_enabled = …)` returns:

```
{
    action: "combat" | "encounter" | "avoid",
    disposition: String (pass-through),
    notes: String (toast-ready summary),
    handler_result: Dictionary (ready to spread into the wilderness handler return),
}
```

The `handler_result` is shaped to drop directly into the EventHandlerRegistry contract (see `event_handler_registry.gd`):

* combat → `{enter_combat, encounter_data, auto_pause, pause_reason}`
* encounter → `{transition_to: "encounter", transition_data, auto_pause, pause_reason}`
* avoid → `{auto_pause: false, presentation: {type: "encounter_avoided", ...}}`

The wilderness handler can either spread this directly or override individual fields (e.g., the Hunt activity overrides `pause_reason` to "Hunt interrupted by encounter").

---

## 6. Wired Call Sites

The router consults are wired into all four wilderness encounter dispatch paths in `wilderness_handlers.gd`:

1. `_handle_travel_leg` — encounter on a travel leg.
2. `_handle_encounter_check` — standalone encounter check.
3. `_resolve_hunt_activity` — wandering check during a Hunt.
4. `_resolve_lair_search_activity` — wandering check during a dedicated lair search (loops through 8 hours; `avoid` continues the search loop, `combat`/`encounter` short-circuits).

Forced pursuit catch-up (Phase 5 §pursuit_caught_up) bypasses the router and goes straight to combat — see `gdd-evasion-pursuit.md` §3.4.

---

## 7. Signals

| Signal | Emitted from | Listeners |
|---|---|---|
| `encounter_avoided(party_id, encounter_data)` | wilderness handler when router returns `avoid` | NotificationManager toast, future Notebook history panel |

`combat` and `encounter` actions don't fire a router-specific signal; they ride the existing `combat_started` / state-transition signals.

---

## 8. Deferred (Phase 5.5 / later)

* **Charisma-driven parley invitations on unfriendly.** RAW says "may attack if it is reasonable" — Charisma 13+ characters with the Diplomacy / Mystic Aura proficiency could surface a parley option even on unfriendly. Currently maps unfriendly → combat unconditionally.
* **Monster ecology overrides.** Feed monster-tag data (carnivore / herbivore / undead) into the router so the mapping can be ecology-aware instead of disposition-only.
* **Reaction modifiers from situational context.** Lit torches at night, blood on weapons, party banner of a hated faction — RAW §judge_interpretation lets the Judge alter the rolled reaction. v1 has no hook for this.
* **Per-party-disposition state.** A repeated indifferent encounter with the same monster_group should eventually escalate (the orcs got tired of being ignored). v1 treats each encounter as independent.
