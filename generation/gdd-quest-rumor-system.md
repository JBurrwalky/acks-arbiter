# GDD: Quest and Rumor System

**Document type:** Game Design Document (mechanics; PROJECT-DESIGNED, improvable within its ACKS Constraints)
**Authority:** PROJECT-DESIGNED — the quest generation pipeline, the questgiver-minting rule, rumor distribution/decay mechanics, reward-valuation formulas, the truth/reliability model, and completion detection are project design filling ACKS's silence. Everything ACKS *does* say — carousing/spying hijink rumor mechanics, venturer rumormongering, reaction-roll information sharing, treasure→XP conversion, monster XP, domain income/land-grant/vassal economics, the encounter interaction sequence — is quarantined in §2 (sacred) and constrains the design. Where a needed mechanic is not in the corpus it is flagged in §16, never invented from another game.
**Status:** **Draft v1.0** — matured from the v0.x draft (2026-03-28) into a build-ready spec. This is the "long pole" of the social/LLM stack (`docs/master-build-plan-social-llm-stack.md` §6 gap #1): it hard-gates NPC-Dialogue Phase-2 quest adapters and Faction FF-2 `post_job`, and it is the missing consumer behind Live-LLM's reserved `setting_narrative:quest`/`:rumor` blocks (`gdd-live-llm-integration.md` §15, §18.1). v1.0 adds: the modern integration architecture (no new autoload; a `QuestRegistry`/`RumorRegistry` subsystem pair + EventBus contracts), the questgiver-minting prerequisite, DB schema aligned to the existing seeding-stub naming, scheduling/LOD, determinism, a full test plan, and Build Phasing Q-1…Q-6 sequenced for the master plan's Wave 2.
**Depends on ACKS rules:** `rules/acore-campaign-hijinks.xml:75-77,130-172` (carousing hijink — Hear Noise throw, rumor worth **3d12×5gp per level**, "campaign-relevant valuable rumor instead of money", capture), `:85-87,174-180` (spying hijink — secret worth **2d12×100gp per level**, thief-types only); `rules/ax_venturer_class.xml:172-177` (rumormongering — **1d4 rumors** per revisited urban settlement, once/month, 6-hour major activity); `rules/ax_reactions_and_influencing.xml` (reaction rolls, attitude ladder, influence framework, spokesperson — the information-sharing gate); `rules/acore_adventures_and_encounters.xml:749-751` (encounter sequence: reaction check → fight/flee/talk), `:579-599` (**treasure→XP: 1 XP per 1 gp of coin/gems/jewelry/special treasure recovered *to civilization*; wages and business transactions do NOT grant treasure XP** `:596`; magic item sold-unused = 1 XP/gp `:592`), `:601-660` (Monster Experience Points table — the reward-scaling base), `:924-968` (reaction bands & Judge interpretation); `rules/acore_treasure_and_magic_items_rules.xml:5` (recovered-to-civilization 1 XP/gp); `rules/acore_axioms_strongholds_and_domains.xml` (domain income, Tithes 1gp/family/month, vassal duties/Favors & Duties, land grants, stronghold minimums, titles of nobility, level-9 domain requirement); `rules/ax_domain_level_encounters.xml:324-330` (dungeon monster-XP totalling — the lair/dungeon reward base), `:383-528` (domain-encounter reaction bands — how emergent threats behave); `rules/ax_campaign_play.xml:3-146` (monthly domain cycle — the regeneration tick host).
**Depends on project GDDs:** [gdd-npc-personality.md](gdd-npc-personality.md) (12-axis personality, **Motivation** — the questgiver driver; knowledge categories/`willingness_to_share`; three-tier persistence); [gdd-npc-dialogue.md](gdd-npc-dialogue.md) (`quest_ask`/`quest_accept`/`quest_decline`/`quest_turn_in`/`ask_rumor` moves §5.2; knowledge/rumor/quest hooks §9.1–§9.3; reply-planner narration seam §13); [gdd-faction-framework.md](gdd-faction-framework.md) (`post_job` org action §6.5; faction-goal relevance §6.5 status differential; grievance ledger §4.5; `faction_action_taken` narration §6.5, §10.3); [gdd-ruler-ai.md](gdd-ruler-ai.md) (ruler income/tier, `StrategicDisposition`, land-grant authority); [gdd-live-llm-integration.md](gdd-live-llm-integration.md) (§15 task profiles — `setting_narrative:quest`/`:rumor` reserved; the `generate()` contract; §18.1 blocker row); [gdd-setting-generation.md](gdd-setting-generation.md) (Layer-7e rumor seeds, `sim_ruin_seeds`, `sim_events`, `sim_polities` — the setting-gen inputs the seeder already has); [gdd-poi-generation.md](gdd-poi-generation.md) (`rumor_seeds` on every PoI — **already emitted** by `poi_generator.gd:273-303`); [gdd-dungeon-factions.md](gdd-dungeon-factions.md) (dungeon threat/faction data — quest targets); [gdd-settlement-exploration-ui.md](gdd-settlement-exploration-ui.md) (Gather Information / Carouse / Post Notices / Talk / Guild Quests activities — the delivery surfaces); [gdd-quests-tab.md](gdd-quests-tab.md) (the state-surface UI this system feeds); [gdd-journal-tab.md](gdd-journal-tab.md) + [gdd-unified-log-panel.md](gdd-unified-log-panel.md) (narrative log / event feed; `category:"quest"`); [gdd-realtime-scheduler.md](gdd-realtime-scheduler.md) (EventScheduler — expiry/turn-in timing, activity costs); [gdd-terrain-system.md](gdd-terrain-system.md) (territory class — threat frequency & reward geography).
**Consumed by (forward dependency):** the build agent; NPC-Dialogue Phase 2 (quest adapters); Faction FF-2 (`post_job` bridge, faction-goal quests); the Quests-tab UI; the Unified Log (`category:"quest"`); the Journal (quest-note cross-references); Live-LLM (the `quest`/`rumor` narration tasks).
**Modifiable by Claude Code:** Yes within constraints — §2 is sacred and may not be reinterpreted; every generation table, reward formula, distribution rule, decay constant, and quest template is an engineering decision (PROJECT CALL, tunable); interface names (EventBus signals, table/column names, dialogue-move ids, faction-action payload keys) are cross-subsystem contracts and, once approved, follow the naming conventions and may not drift without updating the consumer GDDs.
**Last updated:** 2026-07-07

---

## 1. Purpose and Scope

### 1.1 Purpose

Generate and manage the two information channels through which the player learns what to do next and why anyone cares: **rumors** (unverified information gathered socially, pointing at explorable content) and **quests** (specific tasks offered by specific NPCs or factions with defined rewards and tracked completion). Together they are the connective tissue between the procedurally generated world — dungeons, lairs, PoIs, factions, domain politics — and the player's decision about where to go. **This system is what makes ACKS Arbiter more than a linear town→dungeon→town loop:** it gives the world reasons to pull the party outward, and gives NPCs and factions a voice in the party's itinerary.

### 1.2 Design principle: two views into one world

Rumors and quests are **views into the same underlying world data**. A dungeon two hexes south of a trade road exists whether or not anyone mentions it. The **rumor** system controls *when and how* the player learns about it. The **quest** system controls *whether anyone is paying them to deal with it*. Neither system creates world content; both *reference* it.

**Everything is engine-deterministic; the LLM narrates retroactively.** The engine decides what quests exist, what they pay, whether a rumor is true, who knows it, and when a quest is complete. The LLM (or the mock template provider) only ever writes the *prose*: the quest title/description, the questgiver's offer and thank-you lines, and the NPC-voice phrasing of a rumor. This is "build mechanically, narrate retroactively" (design brief) applied here as everywhere. The entire system is fully playable on the mock provider.

### 1.3 Scope

**In scope:** the quest data model and full lifecycle (seeding → distribution → acquisition → active tracking → turn-in → completion → failure → decay/expiry); the questgiver-minting prerequisite (per-settlement questgivers with Motivation + spendable income); the rumor pool, its RAW-anchored delivery channels, rumor→quest promotion, the truth/reliability model, and propagation/decay; the quest taxonomy grounded in what the engine can actually adjudicate; the integration seams to Dialogue, Faction, Settlement/PoI, Journal/Quests-tab, and LLM narration; EventBus signals; the DB schema (design only) and scheduling/LOD; determinism; and the test plan.

**Out of scope (owned elsewhere; this GDD produces the data they surface):** the Quests-tab UI layout (owned by [gdd-quests-tab.md](gdd-quests-tab.md)); the notice-board/PoI interaction chrome (owned by [gdd-settlement-exploration-ui.md](gdd-settlement-exploration-ui.md)); the dialogue turn loop and move menu (owned by [gdd-npc-dialogue.md](gdd-npc-dialogue.md)); LLM transport (owned by [gdd-live-llm-integration.md](gdd-live-llm-integration.md)); faction turn scheduling and org economics (owned by [gdd-faction-framework.md](gdd-faction-framework.md)); combat/lair-clearing/hex-clearing mechanics whose *outcomes* this system merely observes.

### 1.4 Rumors vs. quests at a glance

| Dimension | Rumor | Quest |
|---|---|---|
| Source | Any qualifying NPC, carousing, notice board, venturer contacts, overheard | A specific questgiver: a named NPC **or** a faction acting through an NPC front |
| Veracity | true / exaggerated / misleading / false — with a source-reliability signal | Always factually accurate about *its own threat* (the questgiver knows the situation) |
| Reward | None — points to content that has its own treasure | Explicit, tracked reward (gold, item, land, political favor, mixed) |
| Obligation | None — ignore freely | Soft — declining is fine; the questgiver *remembers* (dialogue memory + reputation) |
| Completion | Untracked — verified by visiting the source | Tracked — a specific completion condition triggers the reward flow |
| Availability | Passive (reaction-roll share) or active (Gather Information / Carouse / notice board) | At the questgiver's location; some posted publicly on notice boards |
| Persistence | `setting_rumors` seed → `rumors` runtime row on materialization | `setting_quests` seed → `quests` runtime row on materialization |

---

## 2. ACKS Constraints

These come from the books and may NOT be changed. Everything the system builds must reduce to, or stay consistent with, the following. **Where the corpus is silent, §16 flags it.**

### 2.1 Rumors are RAW-anchored in three places (and *only* three)

There is **no generic "Gather Information" skill or table in ACKS 1e** (corpus-verified: the only "gather information" string in `rules/` is army-hijink carousing, `daw_campaigning_armies.xml:683`). The RAW mechanics that *produce rumors* are:

1. **Carousing hijink** (`acore-campaign-hijinks.xml:130-172`): *any* character (including 0-level) may be assigned to carousing; make a **Hear Noise throw**; on success the perpetrator "learns one valuable rumor appropriate to the location," and the boss earns **3d12×5gp per level of the perpetrator** by exploiting it. **"The Judge may provide a campaign-relevant valuable rumor instead of money"** (`:137`) — this is the sacred hook that lets a rumor *be* the reward. Thieves and characters with Eavesdropping are especially effective (`:132`). Fail by 14+ or natural 1 → caught (drunkenness/gambling/vandalism, `:342` line notes the reaction/hear-noise penalties of punishment).
2. **Spying hijink** (`acore-campaign-hijinks.xml:174-180`): assassins, elven nightblades, and thieves only; on success the perpetrator "learns advance intelligence, secret facts, or other valuable information," worth **2d12×100gp per level**; "the Judge may provide a campaign-relevant secret instead of money" (`:180`). This is the high-value, class-gated rumor channel.
3. **Venturer rumormongering** (`ax_venturer_class.xml:172-177`): a level-4+ venturer revisiting an urban settlement where he has previously done business "may automatically learn **1d4 interesting rumors** from old contacts"; requires one day of major activity (6 hours); once per month per settlement.

**Reaction-roll information sharing** is the framework for NPCs volunteering rumors: the attitude ladder and influence framework (`ax_reactions_and_influencing.xml`) govern whether an NPC will talk. A friendly NPC helps; a neutral one is uncertain; an unfriendly/hostile one will not (`acore_adventures_and_encounters.xml:924-968`). ACKS does not print a "rumor per reaction band" table — that mapping is PROJECT-DESIGNED (§4.3), built on the sacred attitude semantics.

### 2.2 Treasure → XP, and the "wages/business" exclusion (critical for quest rewards)

- **Characters gain 1 XP per 1 gp of coin, gems, jewelry, and special treasure recovered on adventures** (`acore_adventures_and_encounters.xml:585`), **but only once brought back to civilization** (nearest friendly town or stronghold, `:581-582`; also `acore_treasure_and_magic_items_rules.xml:5`).
- **Magic items** sold *without being used* grant 1 XP per 1 gp of sale value (`:592`); used items grant none.
- **"Wages and business transactions do not grant treasure XP"** (`:596`). **This is the load-bearing constraint for quest gold rewards.** A quest bounty paid by an NPC looks a great deal like a "business transaction," not treasure recovered from a dungeon. Whether a quest gold reward grants XP is therefore **not settled by RAW and must be ruled** — see §16 O-Q1. This GDD's default (§8.4) treats quest gold as **treasure-equivalent for XP** (it is a reward for adventuring, disbursed to a PC), but the reward record carries an `xp_eligible` flag so the ruling can flip it globally without touching the reward math.
- **Monster XP** is computed from the Monster Experience Points table (base XP by HD + bonus per special ability, `acore_adventures_and_encounters.xml:601-660`); a dungeon/lair's total monster XP is the sum over its monsters (`ax_domain_level_encounters.xml:324`). This total is the **base for reward scaling** (§8.1) — it is the calibrated measure of "how dangerous is this threat."

### 2.3 The treasure economy the reward must not break

ACKS calibrates lair treasure to roughly **4× the total XP value of the lair's monsters** (the standard treasure-to-threat ratio underlying the treasure-type tables, `acore_treasure_and_magic_items_rules.xml`). The player's *primary* reward for clearing a threat is the threat's own treasure; the **quest reward is a premium** for doing it on someone's timetable and reporting back. The reward formula (§8.1) is deliberately calibrated *below* the treasure the party finds on-site, so quests supplement rather than replace the treasure economy.

### 2.4 Domain economics bound what a questgiver can pay

- **Domain income** derives from land revenue and taxes per `acore_axioms_strongholds_and_domains.xml`; a ruler's spendable wealth is a fraction of monthly income. A questgiver cannot post a bounty larger than they can plausibly afford (§8.6 caps gold at a fraction of annual discretionary income for ongoing rulers).
- **Tithes** are a standing domain expense of **1gp/family/month** (`acore_axioms_strongholds_and_domains.xml`), the stream that funds temple factions (faction §6.6) — relevant because temple questgivers pay from that stream.
- **Land grants** (domain rewards) are governed by the vassal ladder: only rulers of sufficient rank (Count+ in practice, since only rulers with vassals grant sub-domains) may grant land; **a domain requires a level-9+ holder** (`acore_axioms_strongholds_and_domains.xml`); accepting a grant makes the recipient a **vassal** with tribute/Favors-&-Duties obligations. Domain-grant quests (§7.7) are constrained by all of this.
- **Titles of nobility** are bound to land — a title is conferred only *with* a domain grant and its vassalage (§2.4 land grants, §8.8), never as a standalone landless rank. (A landless rank/title is deliberately excluded — it confuses the vassalage system; Jedidiah, 2026-07-07.)

### 2.5 The encounter/threat substrate

- The **encounter sequence** is reaction check → fight/flee/talk (`acore_adventures_and_encounters.xml:749-751`); threats the party is sent against behave per their reaction bands.
- **Domain-level encounters** react on 2d6 + domain morale ± alignment (`ax_domain_level_encounters.xml:383-528`): hostile → pillage, unfriendly → opportunism, etc. Emergent threats (bandits from negative domain morale, departed tribal warriors becoming brigands — faction §2.7) are *real world state* a quest can be about.

### 2.6 Where ACKS is silent (the gap register — flagged, never filled from other games)

| Gap | Project answer | Section |
|---|---|---|
| A generic "Gather Information" action/table | Project verb that *reduces to* carousing + reaction-share + venturer rumormongering (§2.1) | §4.3, §5 |
| A "rumor per reaction band" table | PROJECT mapping over the sacred attitude semantics | §4.3 |
| A quest *generation* system (what quests exist, when) | This GDD, §6–§8 | §6–§8 |
| Reward *valuation* for quests | PROJECT formula anchored on monster-XP and the treasure economy | §8 |
| Whether quest gold grants XP (RAW "wages/business" exclusion) | Default treasure-equivalent + `xp_eligible` flag; **Jedidiah ruling needed** | §8.4, §16 O-Q1 |
| Rumor truth/falsity and source reliability | PROJECT accuracy tiers + reliability signal (reuses PoI-seed `accuracy`) | §4.2, §4.4 |
| Rumor propagation/decay | PROJECT freshness lifecycle over settlement-range | §4.5, §4.6 |
| Completion *detection* for tasks | PROJECT engine monitor over existing subsystem signals | §9.4 |

---

## 3. Architecture Overview

### 3.1 Placement — no new autoload

Per project convention (do not proliferate autoloads), the runtime lives as two cooperating **RefCounted repositories** plus a thin **generator** and a **completion watcher**, under `engine/subsystems/quests/`. State is SQLite; there is no global singleton beyond the existing `EventBus`, `GameState`, and the campaign DB handle they already share.

| Class | File | Responsibility |
|---|---|---|
| `QuestRegistry` | `engine/subsystems/quests/quest_registry.gd` | CRUD over `quests`/`quest_rewards`; status transitions; availability queries (by settlement, by questgiver, by hex); reward disbursement orchestration. The one writer of quest state. |
| `RumorRegistry` | `engine/subsystems/quests/rumor_registry.gd` | CRUD over `rumors`; eligible-pool queries (per settlement/NPC/topic); acquisition marking; rumor→quest promotion; freshness decay. The one writer of rumor state. |
| `QuestSeeder` | `engine/subsystems/quests/quest_seeder.gd` | The deterministic generation pipeline (§6): setting-gen seeding (replaces the `_seed_quests_DEFERRED` no-op) and the monthly regeneration pass. Consumes questgiver NPCs, threats, `sim_events`. |
| `QuestCompletionWatcher` | `engine/subsystems/quests/quest_completion_watcher.gd` | Subscribes to EventBus world signals (`lair_cleared`, `combat_ended`, `poi_discovered`, hex-clear, item-acquired, escort-arrival) and flips `is_complete` when a tracked condition is met (§9.4). Emits `quest_completion_ready`. |
| `RewardValuator` | `engine/subsystems/quests/reward_valuator.gd` | Pure, unit-testable reward math (§8): monster-XP → gold, item/domain/political valuation, questgiver-affordability clamp, variance, rounding. No I/O. |

**Rationale for the split:** rumors and quests have different write cadences (rumors churn on decay ticks and acquisition; quests transition on lifecycle events), different query shapes, and different consumers (Dialogue reads both; Faction writes quests via `post_job`; the notice board reads both; the completion watcher writes only quests). Two repositories keep each surface's contract narrow. `RewardValuator` is separated so the reward economy is testable in isolation and tunable without touching persistence.

### 3.2 Setting-gen seed → runtime materialization (the two-phase model, matching the existing pipeline)

Quests and rumors follow the same **seed-then-materialize** pattern the rest of setting generation already uses (verified in `poi_generator.gd`/`setting_materializer.gd`):

```
SETTING GENERATION (deterministic, at world creation)
  Layer 7e:  poi_generator emits rumor_seeds on every PoI            [ALREADY BUILT]
  Layer 6.5: QuestSeeder writes setting_quests + setting_rumors      [this GDD, replaces the no-op]
             (all MECHANICAL facts frozen: threat, reward, distribution, accuracy)
  Layer 7:   NarrativeGenerator._wrap("quest"/"rumor", ...) fills prose  [reserved kinds exist]
        │
        ▼  (on campaign materialization / regional zoom)
RUNTIME (per campaign DB)
  setting_materializer copies seeds → runtime `quests` / `rumors` rows,
  carrying context + reward + accuracy verbatim; resolved at discovery,
  exactly as PoI rumor_seeds already materialize (setting_materializer.gd:1125-1147)
        │
        ▼  (during play, monthly domain tick + live events)
  QuestSeeder regeneration pass + RumorRegistry decay + Faction post_job
```

**This GDD owns the mechanical content of the seeds and the runtime rows.** The LLM only ever fills the `*_placeholder` prose columns; on the mock provider the placeholder templates ship as the final text.

**Naming alignment (do not re-invent):** the deferred seeding stub (`infrastructure_generator.gd:100-117`, since relocated to `engine/subsystems/generation/world/`) already sketched the seed tables as **`setting_quests`** (`id quest_NNNN, questgiver_npc_id, threat_type/source_id, threat_hex, reward JSON, posting_type/range, description_placeholder`) and **`setting_rumors`** (`id rum_NNNN, source_type/id, content_hint, accuracy, knowledge_category, origin_hex, settlement_range, freshness, source_quest_id`), with determinism via `WorldGenRng.stream(seed, "quest"/"rumor", 0, entity_id)`. **§12 adopts these names verbatim** for the seed layer and defines the parallel runtime tables `quests`/`rumors`.

### 3.3 Determinism and the LLM boundary

Identical world state + seed → identical quests, rewards, rumor accuracies, and distribution. Setting-gen seeding uses `WorldGenRng.stream(...)`; runtime generation (the monthly pass, Gather-Information selection) uses the campaign's seeded RNG stream keyed by `(campaign_id, "quest"|"rumor", tick, entity_id)`. **Banker's rounding** wherever a value rounds (reward gp, share splits). The LLM never rolls, never decides truth, never invents a quest or a reward; every LLM output is schema-validated and, on failure or absence, the deterministic placeholder stands (`gdd-live-llm-integration.md` fallback contract).

### 3.4 The end-to-end flow

```
WORLD STATE (dungeon, lair, PoI, domain event, faction agenda)
    │
    ├─► RUMOR seeded/generated (points at the world feature; accuracy assigned)
    │        │
    │        ▼
    │   PLAYER HEARS RUMOR  (Gather Information / Carouse / reaction-share / notice board / venturer)
    │        │
    │        ▼  [optional] rumor→quest PROMOTION if a questgiver responds to the same feature
    │
    └─► QUEST seeded/generated (an NPC/faction authority responds to the feature)
             │
             ▼
        PLAYER DISCOVERS QUEST (notice board, dialogue quest_ask, quest-sourced rumor)
             │
             ▼
        PLAYER ACCEPTS (dialogue quest_accept) — optional; may complete without accepting
             │
             ▼
        PLAYER PURSUES (explores, clears the threat) — treasure kept regardless
             │
             ▼
        COMPLETION DETECTED (QuestCompletionWatcher) → is_complete = true
             │
             ▼
        PLAYER TURNS IN (dialogue quest_turn_in) → reward flow → completion narration
```

---

## 4. Rumor System

### 4.1 Rumor sources and record

Every rumor points at a **real** map feature, NPC, or event — even false rumors are *about* a real thing (they get details wrong; they never reference nonexistent map features). Sources and their generation moment:

| Source (`source_type`) | Content | Generated |
|---|---|---|
| `poi` | PoI description, treasure, hazard, magical effect | Setting gen (Layer 7e — **already emitted** by `poi_generator.gd`) |
| `dungeon` | Dungeon type, approximate danger, notable feature | Setting gen (from `sim_ruin_seeds`) |
| `lair` | Creature type, approximate location, threat level | Setting gen / dynamic lair placement (`lair_placed` signal) |
| `political` | Ruler actions, inter-realm tension, succession, war | `sim_events` at setting gen; domain/faction tick at runtime |
| `settlement` | Crime wave, trade disruption, festival, plague, shortage | Settlement sim tick (runtime) |
| `npc` | NPC schemes, hijink results, faction moves | NPC/faction action resolution (runtime) |
| `quest` | The existence of a quest ("Baron Morson is offering a bounty…") | Quest generation (§6.8) — always `accuracy=true` |
| `historical` | Ancient events, legendary figures, lost treasures | Setting gen (Layer-7 historical timeline) |

**Runtime rumor record** (fields; SQLite shape in §12):

```
Rumor:
  id                  # "rum_NNNN"
  source_type         # enum above
  source_id           # world-feature id this rumor is about
  source_quest_id     # set when source_type = "quest" (FK → quests.id)
  content_hint        # frozen mechanical fact for the LLM to narrate
                      #   (matches the PoI-seed "text_hint"; e.g. "dungeon at 0812: undead, L3-5")
  narrated_text       # LLM/template NPC-voice version (placeholder until Layer-7/live pass)
  accuracy            # "true" | "exaggerated" | "misleading" | "false"   (§4.2)
  accuracy_detail     # what specifically is wrong, when not true
  reliability         # source-reliability signal shown to the player (§4.4)
  knowledge_category  # "local"|"professional"|"political"|"criminal"|"religious"|
                      #   "military"|"dungeon"|"personal"|"historical"   (gdd-npc-personality §6.2)
  origin_hex          # hex where the subject sits
  settlement_range    # max hex distance for NPCs to know it   (reused from PoI seed)
  min_npc_tier        # "C" | "B" | "A"   (who is important enough to know it)
  freshness           # "persistent" | "current" | "stale"   (§4.5)
  # runtime state
  known_to_party      # heard by any PC?
  verified            # party visited the source and learned the truth?
  first_heard_day     # game day acquired (null until heard)
  created_day         # game day the rumor entered the world
  expires_day         # for "current" rumors (null = persistent)
```

### 4.2 Accuracy tiers (assigned at generation)

Not all rumors are true. Accuracy is rolled at generation by source type. **PoI rumors already carry an `accuracy` field from `poi_generator.gd` (`true`/`exaggerated`/`misleading`)** — the runtime layer consumes that verbatim; the table below governs the *other* sources.

| `source_type` | true | exaggerated | misleading | false |
|---|---|---|---|---|
| poi | (as emitted by poi_generator) | | | |
| dungeon | 40% | 30% | 20% | 10% |
| lair | 50% | 25% | 15% | 10% |
| political | 60% | 20% | 15% | 5% |
| settlement | 70% | 15% | 10% | 5% |
| npc | 40% | 20% | 20% | 20% |
| quest | 100% | — | — | — |
| historical | 30% | 30% | 25% | 15% |

Definitions:
- **true** — all material facts correct (location, creature, treasure, danger).
- **exaggerated** — core facts correct, magnitude inflated (treasure ×2, monster stronger, danger overstated). Following it works; expectations are too high.
- **misleading** — location/target correct, a key detail wrong (wrong creature, wrong treasure type, wrong faction). Right place, wrong preparation.
- **false** — fabricated or garbled beyond use (wrong location, threat gone, treasure already taken). Still points at a *real* hex; what the party finds won't match.

**Quest-sourced rumors are always `true`** — they come from the questgiver, who wouldn't post a bounty on a threat they aren't sure exists (§4.1). All PROJECT CALL, tunable.

### 4.3 Acquisition channels (RAW-anchored)

Four channels deliver rumors to the party. Each is a *skin* over the sacred mechanics of §2.1.

**(a) Carousing (RAW hijink — sacred; the "wholesale" channel).** A character assigned to carousing makes a **Hear Noise throw** (`acore-campaign-hijinks.xml:134`, with class/proficiency modifiers per RAW). On success the engine builds the eligible rumor pool for this settlement (§4.7 filters), weights it (§4.3.1), selects one, marks it `known_to_party`, and — per the sacred hook `:137` — **delivers the rumor as the reward** (the "campaign-relevant valuable rumor instead of money" branch). The gp figure `3d12×5×level` (`:136`) is still computed and available if the player instead wants the cash outcome (Judge's/engine's option; the game defaults to the rumor for adventuring value). Failure by 14+ / natural 1 → caught, per the RAW capture table. Carousing lives in the hijink system; this GDD supplies the *pool* it draws from.

**(b) Spying (RAW hijink — sacred; the class-gated, high-value channel).** Assassins/nightblades/thieves only (`:175`). On success the perpetrator learns a **secret** worth `2d12×100gp×level` (`:179`), or, per `:180`, a campaign-relevant secret instead. In this system a spying success draws from the **high-value / low-`min_npc_tier`-restricted** end of the pool: `criminal`, `political`, and `military` category rumors, and rumors pointing at the richest targets, with a strong weight toward `min_npc_tier` A/B secrets a caroused rumor would never surface (plot existence, a questgiver's hidden motive, a dungeon's true depth).

**(c) Reaction-roll share (RAW attitude framework — sacred gate, PROJECT mapping).** In dialogue, the `ask_rumor` move (dialogue §5.2, §9.2) asks an NPC for news. RAW governs *whether they talk* (attitude ≥ Neutral to volunteer anything; Friendly helps freely; Unfriendly/Hostile refuse — `acore_adventures_and_encounters.xml:924-968`). ACKS prints no "how many rumors per band" table, so the delivery mapping is PROJECT CALL:

| NPC attitude toward party | Rumor share on `ask_rumor` |
|---|---|
| Friendly / Cowed | one rumor from the NPC's eligible pool, biased to conversational topic if the player named one |
| Indifferent | one rumor, but only `knowledge_category ∈ {local, and the NPC's professional category}` |
| Neutral | shares only with a successful influence check that turn (roll ≥ 9), else deflects |
| Unfriendly / Hostile / Fearful | never volunteers (may *lie* per dialogue §9.4 if pressed) |

Selection then runs §4.7 (NPC-eligible pool) → §4.3.1 (weighting) → mark `known_to_party` → emit `rumor_heard`. **This is the retail channel; "Gather Information" (the settlement verb) is its menu-level quick-resolve** — a 6-hour major activity (`gdd-settlement-exploration-ui.md:266`) that resolves one reaction-share against a generated Tier-C interlocutor without opening a full dialogue.

**(d) Venturer rumormongering (RAW — sacred).** A level-4+ venturer party member revisiting an urban settlement where they've done business auto-learns **1d4 rumors** (`ax_venturer_class.xml:172-177`), once/month, 6-hour activity. The engine grants 1d4 draws from that settlement's eligible pool, weighted as below, no throw required (RAW says "automatically").

**(e) Notice boards / public postings (project surface; §5).** Passive, throw-free reveal of *posted* content — covered in §5.

#### 4.3.1 Rumor weighting (PROJECT CALL)

When a channel selects "one rumor from the pool," weight by:
- **Unheard** (`known_to_party = false`) → ×3 vs. already-known (avoid repeats).
- **Quest-pointing** (`source_type = quest`) → ×2 (leads to a bonus reward).
- **Target value** — rumors pointing at higher-treasure/higher-XP targets weigh more (proportional to the target's estimated monster-XP, capped).
- **Freshness** — `current` slightly over `persistent` for `political`/`settlement` (topicality), never `stale` (excluded by §4.7).

### 4.4 Truth, falsity, and source reliability

Accuracy (§4.2) is a hidden property until the party **verifies** the rumor by visiting its source. But the player is not flying blind: each rumor carries a **`reliability`** signal derived deterministically from *how it was heard and from whom* — a project-designed proxy for "would I trust this source?" that never reveals the underlying `accuracy`:

```
reliability = base_by_channel + source_credibility + corroboration
  base_by_channel:  spying +2, venturer-contacts +1, notice-board(posted) +1,
                    reaction-share(Friendly) +1, reaction-share(Neutral) 0, carousing 0
  source_credibility: NPC's relevant knowledge_category match +1;
                      NPC Tier A +1; drunk/tavern context −1
  corroboration:    +1 per independent already-heard rumor with the same source_id
band → "dubious" | "plausible" | "credible" | "corroborated"   (display only)
```

Reliability is **shown** (Quests-tab Rumors sub-tab, `gdd-quests-tab.md` §5) as a soft cue; **accuracy** is revealed only on verification. A `false` rumor can be `credible` (a confident, well-placed liar) and a `true` rumor can be `dubious` (a drunk who happens to be right) — the gap between reliability and truth is the deduction game, and it dovetails with the dialogue lie system (`gdd-npc-dialogue.md` §9.4): a rumor traced to an NPC's deliberate lie writes a `deception_suffered` memory and drops that NPC's reliability contribution thereafter.

**Verification** sets `verified = true` when the party enters the source hex and resolves its content (clears/scouts the PoI, fights the lair, learns the political truth). On verification the UI reveals `accuracy` + `accuracy_detail`, and — if the rumor was `false`/`misleading` and sourced to a specific NPC — the discrepancy is available to reputation/dialogue.

### 4.5 Freshness and decay

Three freshness states drive the lifecycle:
- **persistent** — never decays (PoI, dungeon, historical: the mine is still there). Removed only by **invalidation** (§4.6).
- **current** — decays to `stale` after **1d6 months** of game time (`political`, `settlement`, most `npc`, and `quest` rumors while their quest lives). `expires_day` is set at generation.
- **stale** — no longer in NPC pools; already-acquired copies remain in the party's Journal/Quests-tab as history.

Decay runs on the **monthly domain tick** (§10.1): `RumorRegistry.decay_pass(campaign_id, day)` flips `current` rumors past `expires_day` to `stale`, emits `rumor_expired` for any the party had heard (so the UI can grey them), and prunes `stale` rumors from the fast-lookup pool table.

### 4.6 Invalidation and propagation

- **Invalidation:** if a rumor's source is destroyed — dungeon cleared (`lair_cleared`/dungeon-clear), lair eliminated, NPC dead (`characters.day_of_death` written by combat), PoI exhausted, quest completed/expired — the rumor becomes `stale` immediately via the completion watcher's invalidation hook. A quest-sourced rumor goes stale the moment its quest leaves `available`/`accepted`.
- **Propagation (settlement-range model — reused, not re-invented):** a rumor is available to NPCs whose settlement is within its `settlement_range` of `origin_hex`. This range is the *same* value `poi_generator` already stamps on PoI seeds and the one faction/dialogue GDDs reference as the geographic reach of information; **this GDD does not define a new range system**. Special reaches (project convention, tunable):
  - travelers/merchants extend effective range by their trade-route distance;
  - adventurers/mercenaries know `dungeon` rumors at ×2 range;
  - rulers & courts know `political` rumors realm-wide;
  - thieves'-guild members know `criminal` rumors city-wide regardless of range.
- **Gossip spread** (rumor migrating along NPC relationship edges, degrading like a game of telephone) is **v2**, deferred — noted so the `content_hint`/`accuracy` shape stays gossip-compatible (it already mirrors the dialogue-memory `facts` tag format, `gdd-npc-dialogue.md` §8.4).

### 4.7 Distribution filter (who can share which rumor)

```
An NPC can share rumor R iff ALL:
  1. the NPC's settlement is within R.settlement_range of R.origin_hex   (§4.6 reaches apply)
  2. the NPC has a matching knowledge_category  (a guard → "military", a priest → "religious")
       OR R.knowledge_category == "local"       (everyone knows local rumors)
  3. the NPC's persistence tier >= R.min_npc_tier   (C=anyone, B, A)
  4. R.freshness != "stale"
```

A precomputed junction (`rumor_settlement_pool`, §12) caches (rumor_id → settlement_id) at distribution time for fast Gather-Information/reaction-share queries, refreshed by the decay pass.

---

## 5. Notice Boards and Public Postings

Settlements of **Market Class IV or better** carry a public notice board (or equivalent: town crier, temple announcements, guild postings) — gated by the same `market_class ≥ IV` rule the seeding stub already uses for board placement (`infrastructure_generator.gd:103`). The board is a PoI on the settlement street graph (`gdd-settlement-exploration-ui.md`: "Post Notices" at Market/Town Square; "Guild Quests" at Guild Hall). Examining it reveals, **with no throw**:

1. **All `posted`/`broadcast` quests** whose questgiver is in this settlement or whose `posting_range` includes it (§8.7).
2. **1d3 public rumors** from the settlement pool, filtered to `knowledge_category ∈ {local, military, political}` (never `criminal`/`personal`), selected by freshness and value.
3. Content **refreshes monthly** on the domain tick.

Reading the board marks the shown rumors `known_to_party` and makes the shown quests visible in the Quests-tab "Available" sub-tab. Guild Halls surface a **faction-scoped** board (org `post_job` quests, §11.2) filtered to that guild.

---

## 6. Quest Generation

### 6.1 The questgiver prerequisite (the blocker this GDD closes)

The master plan and the seeding stub both name the single missing prerequisite: **per-settlement questgiver NPCs with a Motivation and spendable domain income** (`master-build-plan §6.1`; `infrastructure_generator.gd:105-107`). Quests cannot be minted against an empty world — someone must *have the problem and the means to pay*. §6.2 defines how questgivers are minted; a quest exists only when a real questgiver backs it.

### 6.2 Minting questgivers

A **questgiver** is an NPC (Tier A or B, `gdd-npc-personality.md §2`) who (a) has authority over or interest in a threat, (b) has spendable wealth, and (c) has a Motivation that drives quest-giving. Questgivers are minted at the same moment settlements are stocked, from the population the stock-take already produces:

```
Candidate questgivers per settlement, by market class (the stub's iteration set, :106-107):
  Class III+ : the domain ruler / governor (income = domain income; motivation from StrategicDisposition)
  Class IV-VI: militia captains, prominent merchants, temple priors, guild masters
               (income = personal wealth band by class/level; motivation from personality)
  Any        : a faction acting through a front NPC (§11) — the org is the true questgiver,
               the NPC is the face the player talks to

For each candidate, materialize (or reuse) an NPC record and stamp questgiver fields:
  questgiver_income_monthly   # ruler → domain income; else personal-wealth-band estimate
  questgiver_motivation       # from Motivation (gdd-npc-personality §3.3): the driver
  questgiver_authority_scope  # hexes/domain they can credibly act over (for threat matching)
```

**Motivation drives whether they post at all** (`gdd-npc-personality §3.3`; Motivation "feeds quest hooks, betrayal conditions, and the ruler AI"). PROJECT mapping of Motivation → quest-giving propensity:

| Motivation | Posts quests? | Typical quest flavor |
|---|---|---|
| security / duty | readily | clear threats to their people/land (lair, dungeon, brigand, bounty) |
| faith | readily | recover relics, cleanse desecration, protect the faithful (recovery, dungeon) |
| power / ambition | selectively | domain conquest, reconnaissance, remove rivals (conquest, recon, bounty) |
| revenge | situationally | bounty on a specific enemy; recovery of what was taken |
| wealth | transactionally | protect trade, escort caravans, recover goods (escort, delivery, recovery) |
| knowledge | occasionally | reconnaissance, retrieve lore/artifacts (recon, recovery) |
| pleasure / survival / freedom | rarely | mostly rumor sources, not questgivers |

The questgiver record is the anchor for **turn-in** (where the party returns), **affordability** (§8.6), **reward tone** (a desperate faith-questgiver pays a larger recovery share than a calculating power-questgiver, §8.3), and **dialogue** (the questgiver's personality performs the offer/thank-you lines).

**LOD:** far-from-player settlements mint questgivers **abstractly** (a count and their income/motivation profile, not full NPC records), promoting to full NPCs only when the party approaches — mirroring the ruler named→full pattern (faction §6.2). Backdrop quests still exist as `setting_quests` rows; their questgiver materializes on demand.

### 6.3 What generates a quest

A quest exists when **all** hold (the "problem + authority + inability + motivation" gate):

1. **A threat or need exists** — a monster lair near a route, a dungeon disgorging undead, brigands seizing a settlement, an artifact to recover, a missing person, contested territory, a location to scout, a caravan to escort.
2. **A questgiver is aware of it** — within their intelligence/authority scope (§6.2).
3. **Their own forces are insufficient** — garrison committed elsewhere, threat out of jurisdiction, too dangerous for available troops, political constraints.
4. **Their Motivation aligns with paying** (§6.2 table). An NPC motivated by pleasure/survival rarely posts.

### 6.4 Generation timing

- **Setting generation (Layer 6.5):** scan `sim_ruin_seeds` (dungeon hooks), lair placements, PoIs, `sim_events` (war/conquest/pillage → political threats); for each, find a candidate questgiver (§6.2) meeting §6.3; generate ~1 quest per **4 eligible threats** (not every problem has a bounty); target **3–8 initial quests per standard region**, scaling with map size. Writes `setting_quests` + `setting_rumors` (the quest-sourced rumor, §6.8).
- **During play (monthly domain tick):** new threats emerge (dynamic lairs, domain encounters, faction moves, `sim_events` runtime analogues); questgivers reassess (garrison losses, new intelligence, political shifts); new quests mint when §6.3 is newly met; old quests **expire** when their conditions change (threat eliminated by NPC forces, questgiver dies, situation shifts). Target **1–3 new quests/month**, **0–2 expiring/month** (§13.2 density).
- **On demand (faction `post_job`):** a faction org turn can mint a quest at any faction tick (§11.2), independent of the settlement pass.

### 6.5 Generation procedure (deterministic)

```
1. IDENTIFY ELIGIBLE THREATS within questgiver authority scopes
   (lairs ≤5 hexes of a settlement/road; dungeons flagged active; hostile occupiers;
    dangerous lone creatures; missing items/persons; unsecured border hexes)
2. FILTER BY QUESTGIVER CAPABILITY (§6.2, §6.3): nearest aware questgiver who can pay,
   cannot self-solve, is motivated, and has not already posted for this threat
3. PROBABILITY GATE (prevents a bounty on every lair):
   50% within 3 hexes of the questgiver's seat / 25% at 4-8 / 10% at 9+
4. SELECT QUEST TYPE — match threat → template (§7)
5. VALUE REWARD — RewardValuator (§8): type formula → affordability clamp → variance → round
6. SET DISTRIBUTION — posting_type/range + expiry (§8.7)
7. WRITE seed/row (mechanical facts frozen); queue narration placeholder
8. CREATE quest-sourced rumor (§6.8)
All RNG via WorldGenRng.stream(seed,"quest",0,quest_id) at setting gen,
or campaign RNG keyed (campaign_id,"quest",tick,quest_id) at runtime.
```

### 6.6 Quest record

Fields (SQLite shape in §12):

```
Quest:
  id                      # "quest_NNNN"
  status                  # "available"|"accepted"|"completed"|"failed"|"expired"|"abandoned"
  # questgiver
  questgiver_id           # NPC id (the face)
  questgiver_faction_id   # set when a faction is the true giver (§11); null for personal quests
  questgiver_settlement_id# where to find/return
  questgiver_motivation   # driver (§6.2) — informs reward tone & narration
  # the problem
  threat_type             # taxonomy key (§7)
  threat_source_id        # dungeon/lair/PoI/NPC/hex id
  threat_hex              # primary hex
  threat_description_hint # frozen mechanical summary for narration
  # completion
  completion_type         # "clear_dungeon"|"clear_lair"|"kill_target"|"retrieve_item"|
                          #   "escort_npc"|"deliver_item"|"hold_territory"|"scout_hex"|
                          #   "build_structure"|"faction_goal"
  completion_target_id    # dungeon_id/lair_id/npc_id/item_id/hex/faction_goal_id
  completion_verified_by  # "questgiver_report"|"automatic"|"witness"
  is_complete             # condition met (still needs turn-in)
  progress                # JSON for multi-step ("3 of 5 hexes cleared")
  # reward  → quest_rewards row (§8, §12)
  # narration (LLM/template)
  title, description, questgiver_dialogue, completion_dialogue    # *_placeholder until filled
  # distribution
  posting_type            # "personal"|"posted"|"broadcast"
  posting_range           # hex radius for board visibility
  # timing
  created_day, expires_day, accepted_day, completed_day
  # party tracking
  accepting_pc_id         # who formally accepted (null if unaccepted)
  reward_recipient_pc_id  # who receives the reward (chosen at turn-in)
```

### 6.7 The rumor↔quest coupling

A quest and the rumor(s) about the same feature are distinct rows pointing at the same `threat_source_id`. Key interactions (unchanged in spirit from the original design, tightened here):
- A rumor may point at a quest ("Baron Morson is offering gold…") — a quest-sourced rumor, `accuracy=true` (§6.8).
- A rumor may point at a threat with **no** quest — the party can still explore for treasure; no bonus reward.
- A quest may exist the party hasn't heard of — it sits on a distant board or in dialogue until encountered.
- Completing a quest **invalidates** its quest-sourced rumors (→ stale, §4.6).
- Clearing a threat **without** accepting still earns the reward if the party later visits a satisfied questgiver (§9.5, the "you're the ones who cleared the ogre?" path).
- If a threat is eliminated by *something else* (NPC forces, another faction, nature), the quest **expires** and its rumors go stale.

### 6.8 The quest-sourced rumor

Every generated quest emits one rumor with `source_type=quest`, `source_quest_id=<quest>`, `accuracy=true`, `knowledge_category` matching the quest's public framing (usually `local`, `military`, or `political`), `settlement_range = posting_range`, entering NPC pools so players can hear about the quest even without visiting the board. This is the row that lets carousing/reaction-share surface quests organically.

---

## 7. Quest Taxonomy (grounded in what the engine can adjudicate)

**Design rule: every quest type maps to a completion condition the engine already resolves.** No quest type is defined that the completion watcher (§9.4) cannot detect against a real subsystem signal. The taxonomy below is the v1 closed set; adding a type requires a new resolvable completion condition, not just flavor.

| `threat_type` | Trigger | Questgiver | `completion_type` (resolvable by) | Reward basis (§8) |
|---|---|---|---|---|
| `monster_lair` (A.1) | lair ≤5 hex of settlement causing problems | ruler/governor/merchant | `clear_lair` (`lair_cleared` signal / all lair monsters dead-or-fled) | monster-XP ×0.50 |
| `dungeon` (A.2) | dungeon producing threats to a settlement/route | ruler/temple/guild | `clear_dungeon` (all target-faction leaders dead / dungeon-clear) | monster-XP ×0.25 |
| `brigand` (A.3) | hostile force seized a location | dispossessed ruler / liege / guild | `clear_lair`/`hold_territory` (occupier defeated) | enemy-XP ×0.75 (+optional domain) |
| `creature_bounty` (A.4) | a specific lone dangerous creature | ruler/elder/farmers | `kill_target` (target creature dead) | creature-XP ×1.00 |
| `recovery` (A.5) | item/person lost or stolen | owner / temple / family | `retrieve_item` (item in inventory) / `escort_npc` (person delivered) | item-value ×0.25–0.75 (§8.5) |
| `escort` (A.6) | NPC needs safe passage | the NPC / employer | `escort_npc` (NPC arrives at destination hex) | daily-rate × travel-days ×0.50 |
| `delivery` (A.7) | goods/message must reach a place | merchant / official | `deliver_item` (item reaches destination hex/NPC) | daily-rate × travel-days ×0.50 |
| `domain_conquest` (A.8) | ruler wants territory cleared they can't take | Count+ ruler | `hold_territory` (target hexes clear of hostile lairs 1 month) | **domain grant** (+optional gold) |
| `reconnaissance` (A.9) | authority needs intel on unexplored territory | ruler/commander/mage/guild | `scout_hex` (target hexes entered & explored) | daily-rate × days ×0.25 (+bonus rumor) |
| `faction_goal` (§7.9) | a faction advances an agenda via a job | faction (through a front NPC) | `faction_goal` (the faction's own goal predicate — §11.2) | faction-set (any of the above forms) |

`build_structure`/`construction` is **deferred** (v2): it depends on stronghold-construction resolution not yet wired; when it lands it maps to a `build_structure` completion against the domain-construction system. Flagged §16 O-Q9.

The per-type templates (trigger, questgiver, completion, reward formula, example line) are the calibrated content and are reproduced in **Appendix A** to keep this section readable; each is unchanged in mechanics from the calibrated v0.x draft except that completion is now stated as the resolvable condition above and reward math routes through `RewardValuator` (§8). The one substantive change is **`delivery`** promoted from a sub-case of escort to its own type (it resolves on item-arrival, not NPC-arrival) and **`faction_goal`** added (§7.9).

### 7.9 Faction-goal quests (the faction bridge)

When a faction org turn selects `post_job` (faction §6.5), the faction mints a quest through **this system**, with `questgiver_faction_id` set and a front NPC as `questgiver_id`. The quest's `threat_type`/`completion_type` are chosen from the resolvable set above to match the faction's `goal_primary` (faction §6.3): `grow_membership`→a `recovery`/`escort` errand that recruits; `accumulate_wealth`→`escort`/`delivery`/`recovery` of goods; `suppress_rival`→a `creature_bounty`/`clear_lair` against the rival's assets; `defend_patron`→`hold_territory`/`clear_lair` on the patron's border. The `faction_goal` completion type is used when the job's success is a **faction predicate** (e.g., "a rival's syndicate territory is disrupted") rather than a world-object condition — in that case the completion watcher consults the faction layer's own state (faction §6.6) via a `faction_goal_id`. Rewards may be gold (from the org treasury, faction §6.6), membership/rank (faction §8.2), a political favor (faction patronage), or a hijink-market commission (faction §6.7). **The org's treasury gates the reward** exactly as §8.6 gates a ruler's income.

---

## 8. Reward Valuation

`RewardValuator` (§3.1) is pure and unit-testable. All numbers PROJECT CALL, tunable.

### 8.1 Gold rewards — the core formula

**Principle (from §2.3):** the reward is a *premium on top of* the threat's own treasure, not a replacement. It is calibrated *below* on-site treasure.

```
base_reward = estimated_threat_xp × reward_multiplier
  estimated_threat_xp = Σ monster XP at the threat site (Monster Experience Points table,
                        acore_adventures_and_encounters.xml:601-660; dungeon total per
                        ax_domain_level_encounters.xml:324)
  reward_multiplier by threat_type:
    monster_lair   0.50   dungeon        0.25   brigand   0.75
    creature_bounty1.00   escort/delivery(time-based, below)  recovery (§8.5)
    reconnaissance 0.25   domain_conquest(domain grant, §8.7) faction_goal (§7.9)
variance:  final = base × (0.90 + rand(0,0.20))          # ±10%
round:     nearest 25 gp (<500) or nearest 100 gp (≥500) # NPCs offer round numbers
```

**Party-level daily rate** (time-based types):
```
party_level_gp_rate = average_party_level × 25 gp/day
  # L3 → 75/day, L7 → 175/day — scales with the XP curve so time-quests stay worth it
escort/delivery reward   = party_level_gp_rate × travel_days × 0.50
reconnaissance reward    = party_level_gp_rate × travel_days × 0.25 (+ optional bonus rumor)
```

**Sanity bounds:** `minimum 25 gp` (nothing posts for less); `maximum gold 25,000 gp` (above this, rewards shift to domain grants or political favors).

### 8.2 The `xp_eligible` flag (the RAW tension made explicit)

Because RAW says wages/business transactions grant no treasure XP (§2.2, `acore_adventures_and_encounters.xml:596`), the `quest_rewards` record carries `xp_eligible: bool`, defaulting **true** (the game's design intent is that quest gold *is* adventuring reward and grants 1 XP/gp on disbursement to a PC). If Jedidiah rules that quest gold is "business" (no XP), flip the default — no reward-math change. See §16 O-Q1. Item rewards follow RAW: a magic item grants XP only if **sold unused** (`:592`); the record notes this so the turn-in flow doesn't award XP for a kept item.

### 8.3 Reward tone by questgiver Motivation

The multiplier is nudged by the questgiver's Motivation (§6.2), within ±20%: desperate givers (security/faith) pay toward the high end; calculating givers (power/wealth) toward the low end. This is the single mechanical link that makes *who* is asking matter to *what* they pay.

### 8.4 Reward types and mixed rewards

`reward_type ∈ {gold, item, domain, political, mixed}`; `total_gp_value` is the summed GP-equivalent of all components (for sorting/display only). Mixed examples and the political-favor catalog (guild membership, military alliance, trade rights per the RAW Charter of Monopoly, legal immunity, recruitment access, an intelligence gift = a free high-value true rumor) are reproduced in **Appendix B**.

### 8.5 Recovery item valuation

```
recovery_reward = item_gp_value × 0.25–0.75  (by questgiver Motivation, §8.3)
  magic item:  recovery_reward = item_sale_value × 0.50   (fair vs. finding a buyer)
```

### 8.6 Affordability clamp (RAW-bounded)

```
For ongoing rulers:  gold_reward ≤ 10% × (monthly_domain_income × 12)   # a year's discretionary
For personal givers: gold_reward ≤ questgiver personal-wealth band
For faction givers:  gold_reward ≤ org treasury_gp headroom (faction §6.6)
One-time rewards (domain grants, political favors) have NO income cap.
If gold exceeds means → reduce gold, substitute a political favor or a future promise.
```
`questgiver_income_monthly` comes from `sim_polities` at setting gen (`infrastructure_generator.gd:104`) or the domain economy at runtime.

### 8.7 Distribution and expiry

```
posting_type:  "posted"    (urgent public threat: monster attacks)       range 8 hex
               "personal"  (sensitive: political/criminal/recovery)      range 3 hex
               "broadcast" (domain-level crisis)                         range 15 hex
expires_day = created_day + 3d6 months     (most quests don't wait forever;
                                            domain_conquest & some faction goals: null)
```

### 8.8 Domain-grant valuation (display only; never XP)

```
domain_gp_equivalent = stronghold_value + (estimated_families × monthly_income_per_family × 12)
```
Conditions (RAW-bound, §2.4): the quest must secure the territory; the giver must legitimately hold it; acceptance makes the PC a **vassal** (tribute/Favors-&-Duties); the recipient PC **must be level 9+** or the grant is **held in trust** until one qualifies. Full `DomainGrant` shape in Appendix B.

---

## 9. Quest Lifecycle: Tracking, Completion, Turn-in, Failure

### 9.1 Discovery & acquisition

The player encounters a quest via (a) notice board (§5), (b) dialogue `quest_ask` (§11.1), or (c) a quest-sourced rumor (§6.8). Discovery adds it to the Quests-tab "Available" sub-tab and emits `quest_discovered`.

### 9.2 Acceptance

Formal acceptance is **optional**: `quest_accept` (dialogue) or "Accept" in the UI moves the quest `available→accepted`, stamps `accepting_pc_id` + `accepted_day`, emits `quest_accepted`. The party may pursue and complete *without* accepting and still claim the reward if the questgiver is satisfied (§9.5). Declining (`quest_decline`) is fine but is remembered (dialogue memory; PROJECT CALL whether declined quests reappear — §16 O-Q7).

### 9.3 Active tracking

The Quests-tab "Active" sub-tab shows status, `progress` (multi-step), time-to-expiry, and questgiver location. Each material change emits a `category:"quest"` Unified-Log entry (`gdd-unified-log-panel.md` §4.5) and a Quests-tab refresh.

### 9.4 Completion detection (the watcher)

`QuestCompletionWatcher` subscribes to EventBus and flips `is_complete` when a tracked `completion_type`'s condition is met. Mapping to **existing** signals (no new world mechanics invented):

| completion_type | Detected by |
|---|---|
| `clear_lair` | `lair_cleared(party_id, result)` where `result.lair_id == completion_target_id`; fallback: all lair monsters `day_of_death`/fled |
| `clear_dungeon` | dungeon-clear signal / all target-faction leader NPCs dead (`combat_ended` + `characters.day_of_death`) |
| `kill_target` | `combatant_downed`/`combat_ended` where the target npc/creature id is dead |
| `retrieve_item` | inventory-changed where `completion_target_id` enters party inventory |
| `deliver_item` | item leaves party inventory *at* the destination hex/NPC |
| `escort_npc` | escorted NPC arrives at destination hex (`hex_entered` while the NPC is in the party/attached) |
| `hold_territory` | target hex(es) have no hostile lair for 1 month (checked on the monthly tick) |
| `scout_hex` | `poi_discovered`/`hex_entered` marking the target hex(es) explored |
| `faction_goal` | the faction layer's goal predicate reports satisfied (faction §6.6), keyed by `faction_goal_id` |

On the condition being met: set `is_complete=true`, emit **`quest_completion_ready(quest_id)`** (drives a toast + Quests-tab move). The reward is **not** disbursed yet — the party must turn in (unless `completion_verified_by == "automatic"`, e.g. some faction goals, which disburse immediately).

### 9.5 Turn-in and reward disbursement

```
1. Party returns to the questgiver (or turn-in point). Dialogue quest_turn_in fires (§11.1),
   requiring is_complete (or an on-the-spot completion check for the unaccepted path).
2. completion_dialogue performed (LLM/template).
3. Reward-recipient selection (§9.6): player picks the PC.
4. QuestRegistry.disburse_reward(quest_id, recipient_pc_id):
     gold    → add to PC; if xp_eligible, award 1 XP/gp on disbursement (§8.2)
     item    → to PC inventory; XP only if later sold-unused (RAW, §8.2)
     domain  → vassalage flow (§9.6, level-9 gate); political → recorded on the sheet
5. status → "completed"; completed_day set; quest-sourced rumors → stale (§4.6);
   emit quest_turned_in(quest_id, recipient_pc_id, reward_summary).
```

The **unaccepted-completion path** ("you're the ones who cleared the ogre? here — you've earned it"): if the party never accepted but the threat is resolved and they visit a satisfied questgiver, dialogue offers turn-in directly; the questgiver's attitude gates whether they honor an unpromised deed (Friendly/Indifferent yes; Unfriendly no — PROJECT CALL, §16 O-Q4).

### 9.6 Reward-recipient selection

- **Gold:** player picks one PC to receive it (then may redistribute manually — identical to treasure division; no forced split). XP per §8.2.
- **Item:** player picks one PC; item to inventory; transferable afterward; XP only if sold-unused.
- **Domain:** player picks one PC who **must be level 9+** (else held in trust, §8.8); confirmation dialog states the vassalage terms; **not** freely transferable between PCs.
- **Political favor:** player picks one PC; recorded on the sheet; some favors (guild membership, alliance) benefit the party indirectly; not transferable.

### 9.7 Failure and expiry

- **`expired`** — `expires_day` passed before completion (decay pass, §10.1): status→`expired`, `quest_expired` emitted, quest-sourced rumors→stale. Some may reappear (§16 O-Q7).
- **`failed`** — the objective became impossible: escorted NPC died, retrieval item destroyed, target already eliminated by others, questgiver dead (a dead questgiver's quests fail through the dead-NPC filter — dialogue §12.3 guarantees no session opens with a dead giver). Emits `quest_failed(quest_id, reason)`; possible reputation consequence per the questgiver's personality (dialogue memory).
- **`abandoned`** — the player abandons via the UI (Quests-tab): status→`abandoned`; may cost reputation with the questgiver (PROJECT CALL by their Motivation).

---

## 10. Scheduling, LOD, and Determinism

### 10.1 The monthly domain tick (the regeneration/decay host)

Quest generation (runtime pass, §6.4), rumor decay (§4.5), notice-board refresh (§5), and `hold_territory` checks all batch inside the existing **monthly domain cycle** (`ax_campaign_play.xml:3-146`; the same tick the faction and ruler layers use). Order within the tick: (1) resolve world changes (threats emerged/eliminated by NPC forces, from domain/faction sims) → (2) `RumorRegistry.decay_pass` + invalidation → (3) `QuestSeeder.regenerate_pass` (new quests, expiries) → (4) notice-board refresh. This keeps quest state coherent with the world state the same tick produced.

### 10.2 LOD (level of detail — matches the ruler/faction model)

- **Active LOD (near the player):** full questgiver NPCs, full quest generation, live completion watching, rumor pools materialized.
- **Backdrop LOD (far):** quests/rumors exist as `setting_quests`/`setting_rumors` seed rows with abstract questgivers (§6.2); the completion watcher ignores backdrop quests (nothing there for the party to complete); generation is coarse (counts, not individual mints). On the party's approach, a materialization pass promotes the region's abstract questgivers to NPCs and its seeds to runtime rows — the same on-demand promotion PoIs already use.
- Cost stays linear in *active* settlements, not world size.

### 10.3 Determinism

All generation is seeded (§3.3). The completion watcher is event-driven and idempotent (re-processing the same signal is a no-op once `is_complete`). Reward math uses banker's rounding. A save/load mid-quest restores exact state (all quest/rumor state is SQLite; no in-memory-only quest state). The `SettingDatasetHasher` should treat `setting_quests`/`setting_rumors` **mechanical** columns as canonical (hashable) and the `*_placeholder` prose columns as presentation (excluded) — mirroring the `setting_narrative` lock/hasher treatment (`gdd-live-llm-integration.md` §13.2). Flagged §16 O-Q10.

---

## 11. Integration Seams (explicit contracts)

The consumer GDDs already reference these by name; this section is the authoritative contract they build against.

### 11.1 Dialogue (`gdd-npc-dialogue.md` §5.2, §9.1–§9.3, §13)

Dialogue owns five thin adapter moves over this system's state machine:

| Move | Calls | This system provides |
|---|---|---|
| `quest_ask` | `QuestRegistry.offerable_quests(npc_id, party_id, attitude)` | the list of quests this NPC can offer *now*, attitude-gated: **Friendly** unlocks `personal`-posting quests; **Neutral** only `posted`/`broadcast` (dialogue §9.3, PROJECT CALL). Emits `quest_offered`. |
| `quest_accept` | `QuestRegistry.accept(quest_id, pc_id)` | status→accepted; emits `quest_accepted` |
| `quest_decline` | `QuestRegistry.decline(quest_id, party_id)` | decline memory (no state change beyond a dialogue-memory note) |
| `quest_turn_in` | `QuestRegistry.can_turn_in(quest_id)` then `disburse_reward(...)` | completion verification, reward-recipient selection, `completion_dialogue` text; emits `quest_turned_in` |
| `ask_rumor` | `RumorRegistry.share_for_npc(npc_id, party_id, attitude, topic?)` | one rumor from the NPC-eligible pool per §4.3(c); marks `known_to_party`; emits `rumor_heard` |

The reply planner consumes the quest's `questgiver_dialogue`/`completion_dialogue` and the rumor's `narrated_text` (or their placeholders on mock). **Dialogue never adjudicates a quest** — it initiates; `QuestRegistry`/`RumorRegistry` own the state.

### 11.2 Faction (`gdd-faction-framework.md` §6.5, §6.6, §10.3)

The `post_job` faction action is the **bridge**: `FactionAI` calls `QuestRegistry.create_faction_quest(faction_id, front_npc_id, goal, terms)`, which mints a `faction_goal`-or-typed quest (§7.9) with `questgiver_faction_id` set, reward drawn against the org treasury (faction §6.6 affordability), and — if the goal is a faction predicate — a `faction_goal_id` the completion watcher (§9.4) polls against faction state. The quest surfaces on the org's Guild-Hall board (§5) and via dialogue with the front NPC. On turn-in, `quest_turned_in` fires a faction-side ledger write (a `patronage_granted`/`aided` entry, faction §4.5) and, where narration is wanted, the faction's `FactionActionNarrator` (a Seam-A clone, faction §6.5) decorates it. **Faction-goal relevance for the dialogue status differential** (faction §6.5): a `request_action` whose effect advances a faction's goal is "related" and skips the status penalty — this system exposes `QuestRegistry.advances_faction_goal(issue, faction_id) -> bool` for that check.

### 11.3 Settlement / PoI (`gdd-settlement-exploration-ui.md`)

The notice board (§5), the "Gather Information" and "Carouse" activities (§4.3), "Post Notices" (board read), and Guild-Hall "Guild Quests" (faction board) are settlement-UI surfaces that call `RumorRegistry`/`QuestRegistry` read APIs. The UI owns chrome; this system owns content. `settlement_activity` time costs (6-hour Gather Information, etc.) are the UI's; the rumor/quest results are ours.

### 11.4 Journal / Quests-tab / Unified Log

- **Quests-tab** (`gdd-quests-tab.md`) is the **state surface**: it reads `quests`/`rumors` and renders Active/Available/Completed/Failed/Rumors sub-tabs. It calls no generation; it displays and issues accept/decline/abandon through `QuestRegistry`. Reliability (§4.4) and verification state render on the Rumors sub-tab.
- **Unified Log** consumes every quest/rumor EventBus signal as `category:"quest"` entries (`gdd-unified-log-panel.md` §4.5) via the standard `log_entry_added` path.
- **Journal** (`gdd-journal-tab.md`) hosts player-authored notes that may cross-reference a quest/rumor entity; the player may flag a rumor as "suspected lie" (a note, no mechanical effect) — the multi-session deduction aid the dialogue lie system relies on.

### 11.5 LLM narration (`gdd-live-llm-integration.md` §15, §18.1)

Narration uses the reserved task profiles and block kinds — **no new LLM architecture**:
- **Setting-gen prose:** `NarrativeGenerator._wrap("quest", quest_id, placeholder, ctx)` and `_wrap("rumor", rumor_id, placeholder, ctx)` fill `setting_narrative:quest`/`:rumor` (reserved kinds, migration 159; this GDD is the substrate that unblocks them, §18.1). Batch QoS, 3K/500 token budgets per §15.
- **Runtime prose:** quest `questgiver_dialogue`/`completion_dialogue` and rumor `narrated_text` are produced through the **dialogue** reply planner (the `npc_dialogue_reply` task) when performed in a conversation, or the mock template provider otherwise. There is no separate runtime "quest narration" task — quest text rides the dialogue call that surfaces it.
- **Contract (non-negotiable):** the LLM fills only the `*_placeholder`/`narrated_text` prose columns; on failure/absence, the deterministic placeholder is the final text; all output is schema-validated; the mock provider produces complete, playable prose. Redaction/degradation per the Live-LLM layer.

### 11.6 EventBus signals (past-tense, typed — matching `event_bus.gd` style)

New signals this system emits (design; to be added to `EventBus`):

```gdscript
signal quest_discovered(quest_id: String)
signal quest_offered(quest_id: String, npc_id: String)
signal quest_accepted(quest_id: String, pc_id: String)
signal quest_declined(quest_id: String)
signal quest_completion_ready(quest_id: String)          # is_complete flipped; awaits turn-in
signal quest_turned_in(quest_id: String, recipient_pc_id: String, reward: Dictionary)
signal quest_failed(quest_id: String, reason: String)
signal quest_expired(quest_id: String)
signal quest_abandoned(quest_id: String)
signal rumor_heard(rumor_id: String, source_channel: String)   # channel: carouse|spy|ask|board|venturer
signal rumor_verified(rumor_id: String, accuracy: String)
signal rumor_expired(rumor_id: String)
```

Signals this system **consumes** (existing): `lair_cleared`, `lair_placed`, `poi_discovered`, `combat_ended`, `combatant_downed`, `hex_entered`, `settlement_entered`, `turn_elapsed`, plus the monthly-tick hook and faction goal-state reads. All consumption is via the completion watcher and the monthly pass; no polling of world state outside signals.

---

## 12. Data Model (design only — no migrations authored here)

SQLite is ground truth; migrations are sequential/versioned/non-destructive (authored by the build agent at Q-1). **Seed-layer tables adopt the stub's names verbatim** (§3.2). Runtime tables mirror them with lifecycle state.

**Seed layer (setting-gen DB; frozen after Layer-8 lock except prose):**
- `setting_quests` — `id (quest_NNNN)`, `questgiver_npc_id`, `questgiver_faction_id?`, `threat_type`, `threat_source_id`, `threat_hex`, `completion_type`, `completion_target_id`, `reward` (JSON), `posting_type`, `posting_range`, `expires_day?`, `description_placeholder`, `questgiver_dialogue_placeholder`, `completion_dialogue_placeholder`, `title_placeholder`.
- `setting_rumors` — `id (rum_NNNN)`, `source_type`, `source_id`, `source_quest_id?`, `content_hint`, `accuracy`, `accuracy_detail?`, `reliability_base`, `knowledge_category`, `origin_hex`, `settlement_range`, `min_npc_tier`, `freshness`, `narrated_placeholder`.

**Runtime layer (campaign DB):**
- `quests` — all §6.6 fields + `campaign_id`. Indexed by `status`, `questgiver_settlement_id`, `threat_hex`, `threat_type`, `questgiver_faction_id`.
- `quest_rewards` — `reward_type`, `gold_value`, `item_id?`, `item_description?`, `domain_grant_id?`, `political_favor?`, `total_gp_value`, `xp_eligible`, `variance_applied`; FK `quest_id`.
- `domain_grants` — `hex_ids` (JSON), `territory_class`, `estimated_families`, `stronghold_present`, `stronghold_value`, `vassal_obligations`, `title_granted`, `held_in_trust`; FK `quest_reward_id`.
- `rumors` — all §4.1 runtime fields + `campaign_id`. Indexed by `source_id`, `origin_hex`, `knowledge_category`, `freshness`, `source_quest_id`.
- `rumor_settlement_pool` — junction `(rumor_id, settlement_id)`; precomputed at distribution for fast pool queries; refreshed by the decay pass.

Migration ordering note: `quests.questgiver_faction_id` FKs `factions(id)` (faction §4.1) — the quest migration must land **after** FF-1's faction schema (Wave 0) or declare the column nullable-without-FK until FF-1 exists (Q-1 build note).

---

## 13. Scaling and Balance

### 13.1 Reward vs. treasure economy

Target ratio of quest reward to total session income (§2.3): **10–25%** for dungeon quests (dungeon treasure dominates), **25–50%** for lair quests, **50–100%** for creature bounties (little/no lair treasure), **N/A** for domain grants (transformative). The formula (§8.1) is set to land in these bands; the worked example (Appendix C) verifies one case at ~36%.

### 13.2 Quest density

At any time a standard region carries **3–8 active quests** (from setting gen) + **1–3 new/month** − **0–2 expiring/month** (§6.4). The player should never lack for things to do but never be overwhelmed; quests compete with freeform exploration for attention, and the balance favors player choice over checklist completion.

### 13.3 Level-appropriate targeting (implicit, not enforced)

ACKS expects the party to assess risk (this GDD does **not** filter quests by party level). Scaling is emergent: nearby threats are weaker (placement puts them near start settlements) with smaller rewards; distant threats are stronger with bigger rewards; domain grants only appear at high tier (Count+ giver); the party can take a quest too dangerous for them — that is their problem (ACKS does not protect overcommitment).

---

## 14. Parameter Exposure

No player-facing tuning parameters. Quest density and reward scaling are functions of the generated world (more threats → more quests; richer questgivers → bigger rewards). The PoI-density multiplier (`gdd-poi-generation.md`) indirectly sets rumor volume (more PoIs → more `rumor_seeds`). Internal constants (multipliers, accuracy tables, freshness durations, weighting factors) are tunable in `data/quests/quest_tuning.json`.

---

## 15. Test Plan

Every subsystem gets focused unit tests; boundaries get integration tests; **the entire system must pass on the mock provider**; hand-authored content is tested before procedural generation.

**Unit (deterministic, no I/O):**
- `RewardValuator`: each `threat_type` formula; variance bounds (±10%); rounding (banker's, 25/100 buckets); affordability clamp for ruler/personal/faction givers; Motivation tone nudge; `xp_eligible` default and flip; domain-grant gp-equivalent.
- Accuracy assignment: distribution over 10k seeded rolls per source type matches §4.2 within tolerance; quest-sourced always `true`; PoI rumors pass `accuracy` through verbatim.
- Reliability computation: each channel base; corroboration accrual; reliability⊥accuracy (a `false`-but-`credible` and a `true`-but-`dubious` case).
- Weighting: unheard ×3, quest ×2, target-value proportionality.
- Freshness/decay: `current` → `stale` after 1d6 months (seeded); persistent never decays; invalidation on source destruction.

**Integration:**
- **Seeding:** a fixture region with 2 dungeons + 3 lairs + 1 brigand-held town + N PoIs + minted questgivers → 3–8 quests, each with a valid questgiver who can afford it, a resolvable completion, and a quest-sourced rumor; determinism (same seed → identical set, byte-equal mechanical columns).
- **Seed→materialize:** `setting_quests`/`setting_rumors` copy to runtime `quests`/`rumors` verbatim (mechanical columns), placeholders intact.
- **Completion watcher:** fire each signal (`lair_cleared`, `combat_ended` with dead target, inventory-add, escort-arrival, hex-scout, hold-territory-monthly, faction-goal-satisfied) → `is_complete` flips exactly once; idempotent re-fire; backdrop quests ignored.
- **Turn-in:** accepted path and unaccepted path; reward disbursement per type; XP awarded per `xp_eligible`; domain-grant level-9 gate + held-in-trust; quest-sourced rumor → stale on completion.
- **Dialogue seam (mock):** `quest_ask` attitude gating (Friendly vs. Neutral posting classes); `ask_rumor` per-band share; `quest_turn_in` end-to-end on templates.
- **Faction seam (mock):** `post_job` mints a faction quest against org treasury; `faction_goal` completion polls faction state; `quest_turned_in` writes the faction ledger.
- **Persistence:** save/load mid-quest (accepted, is_complete-but-not-turned-in, expired) restores exact state; dead-questgiver → quest fails via the dead-NPC filter.
- **Full-loop smoke (mock, hand-authored):** hear a caroused quest rumor → read the notice board → travel → clear the lair → return → turn in → reward + XP → rumor stale → Unified-Log `quest` entries present at each beat.

---

## 16. Open Questions / Rulings Needed from Jedidiah

Ordered by build impact. Each is either a design decision deferred to you or a rule I could not cite in the corpus.

1. **O-Q1 — Does quest gold grant XP?** RAW says "wages and business transactions do not grant treasure XP" (`acore_adventures_and_encounters.xml:596`), yet treasure recovered to civilization grants 1 XP/gp (`:585`). A quest bounty is ambiguous — reward for adventuring (treasure-like) or payment for a job (business-like). **Default in this GDD:** `xp_eligible = true` (quest gold grants 1 XP/gp on disbursement). The `xp_eligible` flag lets you flip it globally. **Which is it?** This materially affects levelling pace. *(No RAW citation resolves it.)*
2. **O-Q2 — Reward multipliers and the treasure-ratio target.** The multipliers (lair 0.50 / dungeon 0.25 / brigand 0.75 / bounty 1.00 / time-based 0.50/0.25) and the daily rate (avg-level × 25 gp) are PROJECT CALL, calibrated to the §13.1 bands. Confirm the bands (10–25% dungeon, 25–50% lair, 50–100% bounty) are the feel you want, or retune.
3. **O-Q3 — Accuracy distributions and the reliability signal.** Are the §4.2 tables right (esp. `npc` at 40/20/20/20 and `historical` at 30/30/25/15)? And do you want the **reliability** cue (§4.4) shown to the player at all, or should truth be discoverable only by verification (harder, more paranoid)?
4. **O-Q4 — Unaccepted-completion honoring.** Should a satisfied questgiver pay for a deed the party never formally accepted (the "you're the ones who cleared the ogre?" path, §9.5)? Default: yes if Friendly/Indifferent, no if Unfriendly. Confirm, or require formal acceptance for any reward.
5. **O-Q5 — Gather Information as a distinct verb.** The corpus has **no** generic Gather-Information mechanic (only carousing/spying/venturer). This GDD models the settlement "Gather Information" activity as a project verb reducing to a reaction-share (§4.3c). Confirm that's acceptable, or should "Gather Information" simply *be* carousing (a Hear-Noise throw) with no separate reaction-share path?
6. **O-Q6 — Carousing rumor-vs-gold.** RAW lets carousing yield either 3d12×5gp×level **or** a campaign-relevant rumor (Judge's choice, `acore-campaign-hijinks.xml:137`). This GDD defaults carousing to delivering the **rumor** (adventuring value). Should the player choose per-carouse, or is rumor-always correct?
7. **O-Q7 — Do declined/expired quests reappear?** Default: expired quests may re-mint if their threat persists; declined quests stay declined for that questgiver. Confirm, or make declines re-offerable / expiries permanent.
8. **O-Q8 — Multi-stage quests.** The taxonomy is single-condition. Do you want true multi-stage quests ("find the artifact → return it → then defend the temple") as one quest with sequential `progress`, or as a chain of single quests? Default: single-condition only in v1; chains via quest-sourced follow-ups. *(gdd-quests-tab O-Q lists this too.)*
9. **O-Q9 — `build_structure`/construction quests.** Deferred to v2 (depends on stronghold-construction resolution). Confirm deferral, or specify the completion condition if you want it in v1.
10. **O-Q10 — Determinism-hash treatment.** Should `setting_quests`/`setting_rumors` mechanical columns be included in the `SettingDatasetHasher` (canonical) with prose columns excluded, mirroring the `setting_narrative` lock/hasher ruling (`gdd-live-llm-integration.md` §13.2 A3)? This is the clean parallel; confirm.
11. **O-Q11 — Questgiver abundance vs. sparseness.** The "~1 quest per 4 eligible threats" and probability gate (50/25/10 by distance) target 3–8 initial quests/region. Is that the density you want at world start, or denser/sparser?
12. **O-Q12 — Faction-goal reward forms.** For `post_job` faction quests, which reward forms should factions favor (gold from treasury / membership+rank / political favor / hijink commission)? Default lets the goal type pick (§7.9); confirm or constrain (e.g., syndicates never pay in rank).
13. **O-Q13 — Political-favor GP-equivalents.** Political favors are estimated at 1,000–5,000 gp by giver tier for sorting only (Appendix B). Confirm the band, or supply tier-specific values.
14. **O-Q14 — Domain-grant "held in trust."** When no PC is level-9+, a domain grant is reserved until one qualifies (§8.8). Is "reserved but inert" acceptable, or should a sub-9 party be unable to accept such quests at all (removing them from the pool)?

---

## 17. Revision History

- **v1.0a, 2026-07-07** — Per Jedidiah, removed the landless title/rank political-favor reward (§2.4, Appendix B): titles/ranks are conferred only bound to a domain grant, never awarded landless ("confuses the system too much"). Deduplicated the file (a §6.8–Appendix C block had been written twice). The `title_granted` field on `DomainGrant` — a title that comes *with* the land — is unaffected.
- **v1.0, 2026-07-07** — Matured the 2026-03-28 draft into a build-ready GDD for the social/LLM stack's Wave 2. Added: the modern architecture (`QuestRegistry`/`RumorRegistry`/`QuestSeeder`/`QuestCompletionWatcher`/`RewardValuator`; no new autoload); the seed→materialize two-phase model aligned to the existing pipeline; the questgiver-minting prerequisite (Motivation + income) that closes the `_seed_quests_DEFERRED` blocker; DB schema adopting the stub's `setting_quests`/`setting_rumors` names + runtime `quests`/`rumors`; the RAW-grounded rumor channels (carousing/spying/venturer/reaction-share) with the corpus fact that **no generic Gather-Information mechanic exists**; the source-reliability model; a taxonomy restricted to engine-resolvable completions (+`delivery`, +`faction_goal`); explicit integration contracts and EventBus signals for Dialogue/Faction/Settlement/Journal/Quests-tab/LLM; scheduling/LOD on the monthly tick; determinism (seeded RNG, banker's rounding, hasher treatment); a full test plan; Build Phasing Q-1…Q-6 (§18); and a 14-item Open-Questions section capturing the RAW tension on quest-gold XP (`:596`) and every deferred design call. Reward formulas, quest templates, and the worked example preserved from v0.x (Appendices A–C).
- **v0.x, 2026-03-28** — Initial draft: rumor sources/accuracy/distribution/acquisition/lifecycle; quest generation conditions/timing/record; reward valuation (monster-XP-anchored) incl. recovery/domain/political; quest-type templates; quest–rumor integration; scaling/balance; worked example.

---

## 18. Build Phasing (Q-1 … Q-6)

Sequenced to slot into `docs/master-build-plan-social-llm-stack.md` Wave 2. Each phase lands green on the full suite; all phases run on the mock provider (no LLM needed for correctness). Model guidance per CLAUDE.md.

| Phase | Deliverable | Hard deps | Mock? | Model | Notes |
|---|---|---|---|---|---|
| **Q-1 — Schema + registries** | Migrations for `quests`/`quest_rewards`/`domain_grants`/`rumors`/`rumor_settlement_pool` (+ `setting_quests`/`setting_rumors` seed tables); `QuestRegistry` + `RumorRegistry` CRUD/queries; `RewardValuator` (pure). Unit tests §15. | FF-1 schema *if* `questgiver_faction_id` FK is enforced (else nullable-no-FK) | yes | Sonnet | Foundation; zero LLM. Adopt the stub table names. Land the EventBus signal declarations (§11.6). |
| **Q-2 — Questgiver minting + seeding** | `QuestSeeder` setting-gen pass replacing `_seed_quests_DEFERRED`; questgiver minting (§6.2) over the stock-take population; quest-sourced rumor emission; seed→materialize wiring; PoI-rumor-seed ingestion. | Q-1; settlement stocking (built); PoI rumor_seeds (built); `sim_polities` income (built) | yes | **Opus** (generation calibration, questgiver economics) then Sonnet | Closes the master-plan long-pole blocker. Determinism tests are the gate. |
| **Q-3 — Rumor delivery** | Reaction-share (`RumorRegistry.share_for_npc`), carousing-pool hook, venturer-rumormonger hook, notice-board read, reliability signal, decay pass on the monthly tick, invalidation. | Q-2; hijink system (carousing, built); dialogue P1 for `ask_rumor` (or standalone Gather-Information verb) | yes | Sonnet | The retail + wholesale rumor channels. Gather-Information settlement verb wired here. |
| **Q-4 — Completion + turn-in + lifecycle** | `QuestCompletionWatcher` over existing signals; turn-in + reward disbursement (all types, XP per `xp_eligible`, domain level-9 gate); failure/expiry/abandon; Unified-Log `quest` entries. | Q-1; combat/lair/exploration signals (built) | yes | Sonnet (Opus for the domain-grant/vassalage disbursement path) | The lifecycle spine. Save/load tests mandatory. |
| **Q-5 — Dialogue quest adapters** | Wire the five dialogue moves (§11.1) to the registries; attitude-gated `offerable_quests`; `quest_turn_in` reward-recipient flow in dialogue; performs placeholder text. | Q-2, Q-4; **Dialogue P2** (the adapter slot) | yes | Sonnet | This is the Dialogue-P2 quest-adapter slice the master plan defers until quest-rumor lands. |
| **Q-6 — Faction post_job bridge + LLM narration** | `create_faction_quest` + `faction_goal` completion polling + faction-ledger write on turn-in + `advances_faction_goal` accessor; `NarrativeGenerator._wrap("quest"/"rumor")` prose (setting-gen) + dialogue-performed runtime prose; Quests-tab data binding. | Q-4, Q-5; **Faction FF-2** (`post_job`, org treasury); Live-LLM L-1 (narration, optional — mock suffices) | mostly | Sonnet (Opus for faction-goal predicate mapping) | Completes both downstream slices (FF-2 `post_job`, Dialogue quest prose) and lights the reserved `setting_narrative:quest/rumor` blocks. |

**Critical-path note:** Q-1→Q-2 is the bottleneck the master plan flagged; finishing them before Wave 2's FF-2 and Dialogue-P2 keeps both from stalling. Q-3/Q-4 are parallelizable after Q-1. Q-5 waits on Dialogue P2; Q-6 waits on Faction FF-2 — both are the *last* wiring, exactly as the master plan sequences the partial blockers.

---

## Appendix A — Quest Type Templates (preserved, completion restated as resolvable)

*(Mechanics unchanged from v0.x; completion conditions now match §7's resolvable set; reward math routes through `RewardValuator`.)*

- **A.1 Monster Lair** — trigger: lair ≤5 hex causing raids/kills; giver: ruler/governor/merchant; completion: `clear_lair`; reward: monster-XP ×0.50 ±10%. *"An ogre lair 2 hexes south has been killing livestock. Baron Morson offers 500 gp for its elimination."*
- **A.2 Dungeon** — trigger: dungeon threatening a settlement/route; giver: ruler/temple/guild; completion: `clear_dungeon` (target-faction leaders dead / seal / recover); reward: monster-XP ×0.25 ±10%. *"The old silver mine is disgorging undead. The Temple of Dawn offers 800 gp to cleanse it."*
- **A.3 Brigand/Occupier** — trigger: hostile force seized a location; giver: dispossessed ruler/liege/guild; completion: occupier defeated (`clear_lair`/`hold_territory`); reward: enemy-XP ×0.75 (+domain if a settlement/stronghold). *"Brigands have seized Valetown. Duke Hasfeld offers the Barony to whoever drives them out and swears fealty."*
- **A.4 Creature Bounty** — trigger: a lone dangerous creature; giver: ruler/elder/farmers; completion: `kill_target` (proof); reward: creature-XP ×1.00 ±10%. *"A wyvern takes sheep from the high pastures. Palatine Telpirion offers 600 gp for its head."*
- **A.5 Recovery** — trigger: item/person lost/stolen; giver: owner/temple/family; completion: `retrieve_item`/`escort_npc`; reward: item-value ×0.25–0.75 (§8.5). *"The Codex of Amber Rites was stolen. We offer 1,200 gp for its safe return."*
- **A.6 Escort** — trigger: NPC needs passage; completion: `escort_npc` (arrival); reward: daily-rate × days ×0.50. *"Safe passage to Azen Radokh — 225 gp for three days' protection through the mountains."*
- **A.7 Delivery** — trigger: goods/message must reach a place; completion: `deliver_item` (arrival at destination); reward: daily-rate × days ×0.50.
- **A.8 Domain Conquest** — trigger: ruler wants territory secured they can't take; giver: Count+; completion: `hold_territory` (target hexes clear 1 month); reward: **domain grant** (+optional gold), §8.8. *"Clear the hexes south of my border and the land is yours; I grant you Baron and recognize your claim."*
- **A.9 Reconnaissance** — trigger: authority needs intel; completion: `scout_hex`; reward: daily-rate × days ×0.25 (+ optional bonus true rumor). *"Scout the three hexes beyond the Dark Wall — 150 gp for a reliable account."*

## Appendix B — Reward Component Shapes (preserved)

- **B.1 Political favors** (non-tradeable): guild membership; military alliance; trade rights (RAW Charter of Monopoly); legal immunity; recruitment access; intelligence gift (= a free high-value true rumor). GP-equivalent 1,000–5,000 by giver tier, **display/sort only** (see §16 O-Q13).
- **B.2 Mixed** examples: "500 gp + healing potion" → gold 500, item potion, total ~1,000. "Barony of Valetown + 200 gp" → gold 200, domain, total ~30,000. "A trade charter + 1,000 gp" → gold 1,000, favor, total ~4,000.
- **B.3 `DomainGrant`** — `hex_ids`, `territory_class`, `estimated_families`, `stronghold_present`, `stronghold_value`, `vassal_obligations`, `title_granted`, `held_in_trust`. Conditions per §2.4/§8.8 (secure the territory; legitimate giver; vassalage; level-9+ recipient or held in trust).

## Appendix C — Worked Example (preserved; verifies §13.1 band)

Setup: medium undead dungeon (0812, L3-5, 3 hex S of the Innford–Stonehaven road); ogre lair (0809, 1 creature, 2 hex S); Baron Morson rules Stonehaven (1010, Class V, 120 families, borderlands, income 720 gp/mo, garrison committed to road patrols; Motivation duty+security).

- **Rumors (setting gen):** dungeon rumor `content_hint`="old silver mine 0812 undead L3-5", accuracy `true`, category `dungeon`, range 8. Ogre-lair rumor accuracy `exaggerated` ("a pair of ogres" — actually one), category `local`, range 5.
- **Ogre quest:** lair within 3 hex of Morson → prob 50% pass → `creature_bounty` (lone ogre). Ogre XP = 200 (4+1 HD) → base 200 × 1.00 = 200 → variance → 210 → round → **200 gp**. Affordability: 200 < 10%×(720×12)=864 ✓. `posted`, range 8. Quest-sourced rumor (`true`, `local`, range 8) emitted.
- **Dungeon quest:** 4-8 hex → prob 25% → fails this seed → no dungeon quest at setting gen (may mint later if undead emerge).
- **Play:** party carouses in Innford (Hear Noise success) → weighted pool (quest rumor ×2) selects the quest rumor → *"Baron Morson offers two hundred gold for anyone who deals with an ogre on the south road."* Notice board (Innford, Class V) shows the posted ogre quest + a spring rumor. Party travels, kills the ogre (proof: head), finds its cache 350 gp (rolled from the ogre's treasure type). Returns to Stonehaven → `kill_target` complete → turn in → fighter chosen → 200 gp (+200 XP if `xp_eligible`, §16 O-Q1) + ogre monster XP. **Quest reward = 200 / (350+200) ≈ 36%** — inside the 25–50% lair-quest band (§13.1). ✓
