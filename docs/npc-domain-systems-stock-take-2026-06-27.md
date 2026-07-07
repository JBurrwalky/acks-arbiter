# NPC Domain Systems — Stock-Take & Gap Analysis

**Date:** 2026-06-27
**Author:** Advisor (audit of code + design docs; build log mined via navigator)
**Purpose:** Inventory what is built vs. left to build across the full NPC-domain/ruler system Jedidiah scoped (11 items + unlisted gaps), so we can sequence the remaining design and hand it to the build agent.

---

## How to read this

Every subsystem is rated against three layers:

- **Built** — functional, tested code exists in `engine/` + `db/schema.sql`.
- **Designed** — a GDD specifies it but no/partial code exists.
- **Gap** — neither built nor designed in actionable detail.

All "Built" claims were verified directly against the codebase on 2026-06-27, not taken from the build log alone.

### Vocabulary reconciliation (important)

Your terms map onto the codebase's existing vocabulary as follows. Using the code's terms in future GDDs will prevent naming drift:

| Your term | Codebase reality |
|---|---|
| "Eager upgrade to full NPC" | A ruler materialized as a real `characters` row at `persistence_tier = "full"`. Currently done only for **sovereign rulers**. |
| "Lazy stub" | A `persistence_tier = "named"` stub, or — for off-camera domains — a text-only row in the `setting_domains` table (`ruler_name`/`ruler_class`/`ruler_level` strings, no character row). |
| (implicit) "promote on visit" | **Designed** (materialization GDD §15.5 M4-1: named→full on first contact) but **not wired** — no runtime trigger exists. |

Persistence tiers are literally `"full" | "named" | "transient"` (`engine/shared_types/character_data.gd:15`). There is no "eager/lazy" flag in code.

---

## Headline

The project has a **deep, well-tested mechanical substrate** for NPC domains: generation/materialization, full economic + tribute + morale simulation, troops/armies/supply, NPC-vs-NPC battle and siege resolution, ruler succession, and the liege-vassal Favors & Duties table all work.

What is **consistently missing is the autonomous-agent layer**. NPC rulers are *simulated objects* — they accrue tribute, pay upkeep, and can die — but they are not *actors*. No code makes a ruler decide to administer, recruit, expand, ally, or go to war. They have no behavior data, no decision loop, no relationships, no factions-with-goals, no diplomacy, and no LLM decision→narration contract.

**One missing document is the keystone: `gdd-ruler-ai.md` does not exist.** It is the "consumer" half that items 3, 4, 6, 7, 10, and 11 all depend on. The "producer" half of the data it would consume (`StrategicDisposition`, GDD `gdd-npc-personality.md §8`) is fully designed but not yet built.

---

## Status map

| # | Subsystem | Status | One-line state |
|---|---|---|---|
| 1 | Persistent NPC rulers (eager full / lazy stub) | **Built (partial)** | Sovereigns are full character rows; vassal-tier rulers stay stubs; runtime promote-on-visit designed but unwired |
| 2 | Garrisons & troop models | **Built** | Player troop economy is deep & tested; NPC garrisons are denormalized/placeholder data, not a live economy |
| 2.1 | NPC-vs-NPC battle resolution | **Built** | Silent resolution path works & is tested; nothing autonomously *triggers* NPC wars |
| 3 | Ruler behavior data layer (disposition/tags) | **Designed, not built** | `StrategicDisposition` fully specified (npc-personality §8); deferred in code |
| 4 | Behavior-tag-aware strategic AI | **Gap (keystone)** | `gdd-ruler-ai.md` does not exist; only 2 narrow reactive resolvers |
| 5 | Ruler ↔ player interactions | **Mostly Gap** | Generic reaction rolls + PC-as-liege vassal appointment exist; audiences/visits/quest-giving absent |
| 6 | Faction systems & goals | **Partial (data only)** | `factions` table exists as a reputation scope; zero goal/behavior fields; realm-political factions undesigned |
| 7 | Ruler ↔ ruler relationships | **Partial** | Static realm-pair disposition cache exists but is never mutated by AI; no personal ruler opinions |
| 8 | Ruler ↔ non-ruler NPC relationships | **Gap** | No relationship table; generic §5 relationship system designed but deferred |
| 9 | Heirs / family systems | **Partial** | Succession state machine built (player-centric placeholder); no NPC dynasty/bloodline/family |
| 10 | Alliances/treaties + liege-vassal favors | **Split** | Favors & Duties **built** (player-as-liege); alliances/treaties **absent** (`is_allied()` hard-false) |
| 11 | Determinative-AI → LLM contract | **Gap** | `LLMManager` is a stub; dialogue-narration contract designed (§9); no ruler-action contract |

---

## Per-item detail

### 1 — Persistent NPC rulers · Built (partial)
**Built:** `setting_materializer.gd` (`_build_ruler`) and `npc_ruler_generator.gd` (`stock_rulers_and_tribute`) mint full `characters` rows + `realms` rows for **sovereign** rulers, with class weighting, level-by-title, names, and a personality record. Off-camera domains live as text stubs in `setting_domains` (`db/schema.sql:3758`). Tested.
**Left to build:** (a) Persistent ruler *characters* for the vassal-tier domains (currently `owner_character_id` stays NULL — deferred since M1; tribute chains still deferred per M4). (b) The **runtime named→full promotion trigger** ("promote on visit") — designed in materialization §15.5 but no code fires it.

### 2 — Garrisons & troop models · Built
**Built:** `troop_units` table (`schema.sql:1803`) with source/type/tier/counts/wages/supply/morale; `armies` + officer hierarchy + unit assignments + supply state (`:1860+`); recruitment, training, marching, supply, morale, casualty, disease resolvers under `engine/subsystems/troops|armies/`. Heavily tested. Per-domain garrison upkeep ticks at RAW 2/3/4 gp/family.
**Left to build:** NPC-side garrisons are **display data, not a live economy** — `setting_materializer._garrison_composition()` writes a denormalized snapshot, and `domain_stocker.gd` seeds a single "Light Infantry" baseline unit. For NPC rulers to actually recruit/spend/lose troops, the troop economy has to be wired to NPC owners. Also missing from the troops layer: tabulated **recruitment times**, **formation types**, and **per-troop march speeds** (army-warfare has supply/movement; the troop catalog itself is sampled, not fully imported).

### 2.1 — NPC-vs-NPC battle resolution · Built
**Built:** `battle_dispatcher.gd` routes two NPC armies to `resolve_silently()`; `field_battle_resolver.gd` runs the full DaW field-battle math; siege subsystem complete. Tested.
**Left to build:** Nothing in the resolver. But it **never fires in normal play** because nothing autonomously launches NPC campaigns (that's item 4). The NPC heroic-foray sub-path is a v1 placeholder.

### 3 — Ruler behavior data layer · Designed, not built
**Designed:** `gdd-npc-personality.md §8` fully specifies the `StrategicDisposition` struct, eight derived ruler weights (expansion/fortification/economic/military/diplomatic/religious/research/oppression) with exact formulas, and a `crisis_response` mapping. The 12-axis personality *core* it builds on **is built** (`npc_personality.gd`, persisted to `characters.personality`).
**Left to build:** Everything in §8 — no `strategic_disposition` field, table, or class exists (verified: no schema table, no code). This is the data half of the agent layer.

### 4 — Behavior-tag-aware strategic AI · Gap (the keystone)
**Built:** Only two narrow, reactive resolvers — `extraction_resistance_heuristic.gd` (does an NPC resist a requisition? 50% BR threshold) and `npc_challenger_emergence.gd` (RAW probability of a challenger appearing). Neither is tag-driven; neither is a management loop.
**Left to build:** The entire decision engine. **`gdd-ruler-ai.md` does not exist** — the personality GDD explicitly says it "does not author the planner." Needs: an action catalog for rulers, the score-by-weight selection loop (§8.5 sketches the contract: score `base_value × relevant_weight`, apply situational modifiers, pick highest, execute deterministically), situational-modifier tables, and integration with the EventScheduler so a ruler "monthly turn" is a scheduled event.

### 5 — Ruler ↔ player interactions · Mostly Gap
**Built:** `interaction_resolver.gd` (RAW 7-step reaction/influence — generic, not ruler-specific); reputation cascade ruler→domain→settlement; `vassal_appointment_dialog.gd` (the **player** appointing **their own** henchmen as vassals).
**Left to build:** The NPC-ruler-facing surface — request an audience, visit a stronghold/court, receive a quest, **be granted a fief by an NPC liege**, become an NPC's vassal. Quest system is a stub (`gdd-quest-rumor-system.md` unbuilt; quests deferred to materialization Phase M6). "Land grant from a local ruler" is listed as flavor with no mechanism (gap-inventory #64).

### 6 — Faction systems & goals · Partial (data only)
**Built:** `factions` (`schema.sql:1447`) + `faction_memberships` + `FactionData` — used only as a **reputation scope**. Verified: `FactionData` has no goal/agenda/objective/behavior fields. `gdd-dungeon-factions.md` fully designs **dungeon-internal** monster factions (a different scope).
**Left to build:** Realm/political factions with goals and agendas, and any autonomous faction behavior. Undesigned at the realm level (deferred to "Phase 12" in domain-tab).

### 7 — Ruler ↔ ruler relationships · Partial
**Built:** `realm_relations` (`schema.sql:3323`) — a pair-symmetric 6-band disposition cache between **realms** (not individuals). `resolve_conquest_outcome()` reads it.
**Left to build:** (a) A writer — verified that `set_relation()` has **no non-test caller**, so dispositions are static once seeded; nothing evolves them. (b) A **personal** ruler↔ruler opinion model (relations are realm-level only). (c) Alliance edges (`is_allied()` returns false — item 10).

### 8 — Ruler ↔ non-ruler NPC relationships · Gap
**Built:** Nothing relationship-specific. Only structural links (ownership, faction leadership). Verified: no `npc_relationships`/`character_relationships`/opinion/kin table.
**Left to build:** The generic NPC relationship graph is **designed** (`gdd-npc-personality.md §5`: 10 relationship types) but deferred and not built, and it isn't specialized to rulers (a ruler's tie to their garrison commander, court advisor, subjects).

### 9 — Heirs / family systems · Partial
**Built:** `ruler_death_handler.gd` — full succession state machine (`handle_ruler_death`, `designate_heir`, `resolve_succession`, 30-day grace, heir kinds pc/henchman/non-henchman). Schema columns on `domains` (migrations 122–123). Tested.
**Left to build:** This is **player-centric and a self-described placeholder for the eventual "Dynasties bloodline model."** No NPC family/dynasty/bloodline/marriage tables (verified absent). Non-henchman heir generation is blocked on the setting generator. For NPC rulers to have continuity, a dynasty/family layer is needed.

### 10 — Alliances/treaties + liege-vassal favors · Split
**Built (favors/demands):** `favors_duties_resolver.gd` — full RAW monthly d20 Favors & Duties table (construction, scutage, call to council/arms, loan, revoke, charter of monopoly, gift, office, troops, grant of land), safe-duty thresholds, cumulative loyalty penalties → revolt. `vassal_obligations` (`:2128`), `call_to_arms_state` (`:2160`), `call_to_arms_handler.gd`. Tested. **Caveat:** several results are signal-only/deferred, and the whole system is **player-as-liege** — there's no NPC-liege↔NPC-vassal (or NPC-liege↔player) demand exchange.
**Left to build (alliances/treaties):** Absent. Verified: no `treaties`/`alliances` tables; `realm_graph.is_allied()` hard-returns false. The only treaty-like construct (`protectorate`, realms-titles refactor) is generation-time only.

### 11 — Determinative-AI → LLM contract · Gap
**Built:** `LLMManager` is a **stub** (`is_configured()` false; `request_narration()` returns a template fallback) — verified. The general NPC dialogue→LLM narration contract is **designed** (`gdd-npc-personality.md §9`: deviation filter, caching, mock modes) and the per-NPC summary/speech fields are cached.
**Left to build:** The ruler-action→narration contract — the structured payload a ruler *decision* (war declaration, decree, diplomacy) emits for retroactive narration. Can't be specified until item 4 defines what those decisions are.

---

## The keystone and the dependency order

The agent layer is gated on two things, in order:

1. **Data half — `StrategicDisposition` (item 3).** Fully designed (npc-personality §8). Needs a table + generator wiring. Low-risk: it's spec-complete.
2. **Consumer half — `gdd-ruler-ai.md` (item 4).** Does not exist. This is the document to author next. It defines the ruler action catalog, the weighted decision loop, situational modifiers, and the EventScheduler cadence.

Once those exist, the rest unlock in a natural chain:

```
StrategicDisposition (3, designed→build)
        │
        ▼
gdd-ruler-ai.md  ── the planner (4, AUTHOR THIS)
        │
        ├── consumes ▶ realm_relations writer (7) ─── enables ▶ alliances/treaties (10)
        ├── consumes ▶ faction goals (6)
        ├── triggers ▶ NPC-vs-NPC battles (2.1 already built, finally fires)
        ├── needs ▶ NPC troop economy wired to owners (2 hardening)
        └── emits ▶ ruler-action→LLM contract (11)

Live off-camera realm tick (M5, unbuilt) ── the heartbeat that calls the planner on a schedule
```

**`StrategicDisposition` + `gdd-ruler-ai.md` + an M5 tick loop are the three pieces that turn rulers from objects into actors.** Almost every remaining item hangs off them.

---

## Gaps you didn't list (the "anything else")

These fill holes the 11 items don't cover, surfaced during the audit:

1. **The planner GDD itself.** `gdd-ruler-ai.md` is the single highest-leverage missing artifact. Listed under item 4 but worth naming as its own deliverable.
2. **A "heartbeat" — live off-camera realm simulation (Phase M5).** Designed-deferred everywhere. Without a scheduled tick that calls the ruler planner, items 4/6/7/10 have logic but never run. Needs `domains` provenance columns and EventScheduler integration.
3. **A `realm_relations` writer / diplomacy-mutation loop.** The disposition table exists but is inert (no AI caller). Even before full diplomacy, *something* must move relations in response to events (raids, broken obligations, conquests).
4. **NPC troop economy wired to NPC owners.** Garrisons are display snapshots today. For NPC recruitment/spending/attrition to matter, the existing (excellent) troop economy must be driven by NPC owners, not just the PC.
5. **NPC dynasty/family/bloodline layer.** Succession works but has no family to draw heirs from; non-henchman heir generation is blocked. This is the "Dynasties" model the death handler is a placeholder for.
6. **Player-as-vassal-of-NPC (the mirror of Favors & Duties).** An NPC liege demanding favors of the player, and the path by which the player becomes a vassal, are undesigned.
7. **Off-map / abstract ruler representation.** `instantiate_realm_for_off_map_force` and `spawn_local_succession_npc` are referenced but deferred — how realms beyond the play map act, and how conquest mints a successor.
8. **Save/load + migrations for all new state.** Every new system (disposition, relationships, treaties, dynasties) needs schema migrations and savegame integration — the project is SQLite-as-ground-truth with sequential non-destructive migrations.
9. **Mock-provider parity for ruler narration.** Per CLAUDE.md the game must run fully on the mock LLM; the ruler-action contract (item 11) needs a deterministic template path from day one.
10. **A dangling decision on ruler title display.** `gdd-ruler-title-chains.md` has open questions (ruler `sex`/`gender` field name, non-binary handling, 65-culture backfill) — small, but it touches every ruler record.

---

## Recommended sequence (for discussion)

Roughly dependency-ordered, not yet estimated:

1. **Author `gdd-ruler-ai.md`** — the planner design (action catalog, weighted selection, situational modifiers, scheduler cadence, mock/LLM seam). *Design only; highest leverage.*
2. **Build `StrategicDisposition`** (item 3) — table + generator, since it's spec-complete and the planner needs it.
3. **Stand up the M5 tick + a minimal `realm_relations` writer** (heartbeat + item 7 dynamics) so the planner can actually run and relations can move.
4. **Wire the NPC troop economy to owners** (item 2 hardening) and let the planner trigger campaigns → NPC-vs-NPC battles (2.1) finally fire in play.
5. **Faction goals (6)** and **alliances/treaties (10b)** on top of the relations writer.
6. **Dynasty/family layer (5/9)** to make succession and heirs real for NPCs.
7. **Player-facing interactions (item 5)** + the **ruler-action→LLM contract (item 11)** — the surfaces that expose all of the above to the player.

---

## Verification notes

Confirmed by direct inspection on 2026-06-27: `gdd-ruler-ai.md` absent; `llm_manager.gd` stub (`is_configured` false, fallback-only); `realm_graph.gd:139` `is_allied()` returns false; no `strategic_disposition`/`ruler_profile`/treaty/alliance/dynasty/family tables in `db/schema.sql`; `set_relation()` (`realm_repository.gd:211`) has no non-test caller; `FactionData` carries no goal fields; `persistence_tier` vocabulary is `full|named|transient`. No ACKS rule is asserted in this document that is not already implemented-and-cited in code.
