# Master Build Plan — The Social/LLM Stack (Faction Framework · Live LLM · NPC Dialogue)

**Status:** Planning draft **v0.3** (2026-07-07). Advisory. No code or schema authored by this document.
**Scope:** A cross-GDD implementation sequence for three interlocking systems and their tightly-coupled satellites, optimized for parallelism and for reusing build/handoff docs that already exist.
**Authority:** This is a Layer-3-adjacent planning doc. It sequences and references; it does not restate rules (Layer 1) or redefine any GDD's internal design (Layer 2). Where it asserts a dependency or build order, the cited GDD/handoff is authoritative on the detail.

**v0.3 changes (2026-07-07):** The quest-rumor build handoff is authored (`docs/handoff-quest-rumor-build.md`, Q-1…Q-6) and all 14 of its open questions are resolved (GDD now **v1.0c**). Its six phases are now **folded into the waves at their optimal times** rather than sitting as a monolithic Wave-2 block: **Q-1 is a Wave-0 foundation**, **Q-2→Q-4 land in Wave 1**, and only the cross-system slices **Q-5 (Dialogue) and Q-6 (Faction) remain in Wave 2** — front-loading the long pole so its core is done before the convergence layer. Sections 1, 2, 4, 5, 6, 8, 9 updated.

**v0.2 changes (2026-07-07):** Jedidiah confirmed the "one more" was **both** `gdd-dungeon-factions.md` and `gdd-npc-personality.md`; **FF-5 is in scope** this pass (dungeon-factions gets its own build track). Five design chips were authored to close gaps: the quest-rumor GDD is now matured to **v1.0**, and new docs exist for NPC agency, session-log/summaries, and the npc-personality generators handoff; a doc-cleanup pass ran. See §9 for the deliverables and the consolidated pending-rulings punch list. Sections 1, 4, 6, 7 updated accordingly.

---

## 0. How to read this

The three headline GDDs are not three separate projects — they are one **social/LLM stack** with a shared spine. Building them in GDD-number order (or one-at-a-time) wastes the fact that their *foundations share no code* and can be built in parallel, while their *top layers converge* on the same few seams. This plan is organized into **waves** (what can run concurrently) rather than a single linear list, plus a **critical-path** call-out so you know what to start first and what to plan ahead for.

Every phase below points at the doc a build session should open. Where a ready-to-run handoff exists, this plan references it by path and does **not** duplicate it. Where a phase has no handoff yet, this plan flags **[HANDOFF TO AUTHOR]** — that is design work for you and me before a build session starts.

---

## 1. Verified build state (grep-checked in `engine/`, 2026-07-07)

| System | Doc | Engine state | Verdict |
|---|---|---|---|
| **Live LLM Integration** | `generation/gdd-live-llm-integration.md` | `llm_manager.gd` autoload exists as a **stub**; `engine/subsystems/llm/` does **not** exist | Unbuilt. Build L-0→L-4. **Zero missing deps** (buildable now). |
| **Faction Framework** | `generation/gdd-faction-framework.md` | `engine/subsystems/factions/` does **not** exist; only `engine/shared_types/faction_data.gd` present | Unbuilt. Build FF-1→FF-5. **§4 schema FULLY APPROVED** (§14.1). |
| **NPC Dialogue** | `generation/gdd-npc-dialogue.md` | `engine/subsystems/dialogue/` does **not** exist | Unbuilt. Build Phases 1→4. |
| **Ruler AI** (satellite) | `generation/gdd-ruler-ai.md` | `engine/subsystems/realm_ai/` **built** (planner, scorer, Seam-A narrator, LOD) | **Done, Phases 0–4.** Seam A live; Seam B built but **caller-less/dormant** (waits on Live LLM). |
| **Dungeon Factions** (satellite / confirmed "one more" ①) | `generation/gdd-dungeon-factions.md` | not built (only the shared type) | Unbuilt. **In scope this pass** — FF-5's target; gets its own build track (§4 Wave 3). |
| **Quest & Rumor** (shared prerequisite) | `generation/gdd-quest-rumor-system.md` (**v1.0c**) + `docs/handoff-quest-rumor-build.md` | not built; seeding is a no-op stub | **GDD v1.0c + handoff authored; all 14 opens resolved (2026-07-07).** Build-ready. Phases **folded into the waves** (Q-1 Wave 0 → Q-2/Q-4/Q-3 Wave 1 → Q-5/Q-6 Wave 2), §4. |
| **NPC-personality relationship/knowledge generators** (confirmed "one more" ②) | `generation/gdd-npc-personality.md` §5/§6 | `relationship_generator.gd` / `knowledge_assigner.gd` never created | Design exists; **build handoff now authored** → `docs/handoff-npc-personality-generators.md` (RG-1…RG-4). Feeds dialogue + quest-rumor (§6). |
| **NPC Agency** (declared sibling) | `generation/gdd-npc-agency.md` | n/a | **GDD now authored, v0.1 (2026-07-07).** Slots after FF-2; not a v1 blocker (§6). |
| **Session log & summaries** (undesigned gap) | `generation/gdd-session-log-and-summaries.md` | GameLog keeps only last 100 entries/party (migration 041) | **GDD now authored (2026-07-07).** Off the critical path; unblocks the `session_summary` LLM task (§6). |

---

## 2. The dependency map

```
                         ┌─────────────────────────────────────────────┐
                         │  LIVE LLM  L-0 → L-1  (the linchpin)         │
                         │  types/mock/registry  →  generate()+Ollama  │
                         │  ZERO missing deps — build FIRST, it's cheap │
                         └───────┬───────────────┬──────────────┬──────┘
                                 │ unblocks      │ unblocks     │ unblocks
                                 ▼               ▼              ▼
                    Ruler Seam B wiring   Dialogue Phase 4   Faction FF-2
                    (dormant→live)        (live perform)     FactionActionNarrator
                    small rider           top of dialogue    narration rider

  ── four foundations, no shared code, build in parallel ───────────────────────
   A. LIVE LLM      L-0 → L-1 → L-2 → L-3 → L-4
   B. FACTION       FF-1 ──► FF-3 ──► FF-2 ──► FF-4 ;   FF-5 (needs dungeon-factions)
                     └ ready handoff   └ +Q-6       └ FF-2+FF-3
   C. DIALOGUE      P1 → P2 → P3 → P4
                     mock  +Q-5  ruler✓/army   Live-LLM
   Q. QUEST-RUMOR   Q-1 ──► {Q-2 ∥ Q-4} ──► Q-3 ──► Q-5 ──► Q-6
                    Wave0        Wave1             │        │
                                          needs Dlg P2   needs FF-2

  ── convergence seams (late) ──────────────────────────────────────────────────
   • Faction ↔ Dialogue: faction-context block in dialogue prompts (faction §10.2)
   • Quest-rumor core Q-1→Q-4 is front-loaded (Waves 0–1); only Q-5 (= Dialogue-P2
     quest adapters) and Q-6 (= Faction-FF-2 post_job) remain as Wave-2 seams
   • Ruler-AI (built ✓): consumed by Dialogue-P3 audience and Faction-FF-3 diplomacy
   • Army-warfare: consumed by Dialogue-P3 parley and Faction war traffic
```

**Two facts drive the whole schedule:**

1. **The linchpin is cheap and dependency-free.** Live LLM §18 states the layer's v1 scope is "buildable now" with no missing prerequisites. L-0 and L-1 together are the single highest-leverage build in the stack: they turn Ruler Seam B, Dialogue Phase 4, and the Faction narrator from "blocked" into "wiring." Build them first even though the *value* they unlock lands later.

2. **The long pole is quest-rumor — now planned and front-loaded.** Its GDD (v1.0c) and handoff (Q-1…Q-6) are done with all 14 opens resolved. Rather than a monolithic Wave-2 block, its phases sit at their earliest feasible times: **Q-1 in Wave 0** (no hard deps — `subsystems/quests/` shares no code), **Q-2→Q-4 in Wave 1** (only need Q-1 + already-built systems), leaving only **Q-5** (the Dialogue-P2 quest adapters) and **Q-6** (the Faction-FF-2 `post_job` bridge) as Wave-2 convergence slices. This turns the old bottleneck into a de-risked, early-built core. See §4/§6.

---

## 3. Reusable build assets (reference, don't duplicate)

| Asset | Path | Covers | Reuse in this plan |
|---|---|---|---|
| **Faction FF-1 handoff** | `docs/handoff-faction-ff1-build.md` | FF-1 split into 4 ready sessions (FF-1.0 schema/CRUD, FF-1.1 realm mirrors, FF-1.2 default-stance+audit, FF-1.3 ledger + `realm_relations` writer + reputation propagation). **Paste-ready prompts + per-session model guidance.** | **Wave 0, Track B — run as-is.** No new authoring needed for FF-1. |
| **Ruler-AI handoff** | `docs/handoff-ruler-ai-build.md` | Ruler AI already built; §10.3 the small Seam-B wiring task; §10.4 army-warfare wiring; §10.5 confirms Seam-B thresholds **RESOLVED 2026-07-06.** | **Wave 1** Seam-B rider (§10.3) fires the moment Live LLM L-1 lands. |
| **Live LLM build plan** | `generation/gdd-live-llm-integration.md` §19 | Self-contained phase plan L-0→L-4 with per-phase create/modify/test lists. **The GDD *is* the build plan** — no separate handoff required. | **Wave 0/1, Track A — build directly from §19.** |
| **Dialogue phasing** | `generation/gdd-npc-dialogue.md` §16 | Phases 1–4 with exit tests. Design-complete; **no session-level handoff exists.** | Needs **[HANDOFF TO AUTHOR]** for Phase 1 before building (§4, Track C). |
| **Faction phasing** | `generation/gdd-faction-framework.md` §13 | FF-1→FF-5 with per-phase deps. Only FF-1 has a handoff. | FF-2/FF-3/FF-4/FF-5 each need **[HANDOFF TO AUTHOR]** (§4). |
| **Task-type registry** | `generation/gdd-live-llm-integration.md` §15 | Normative `data/llm/task_profiles.json` rows for every consumer, incl. `npc_dialogue_reply/_summary` and `faction_action_narration`. | The contract Dialogue-P4 and FF-2's narrator build against — no re-negotiation. |

**Rule of thumb for the build agent:** if a phase below cites a `docs/handoff-*.md`, run it directly. If it cites only a `generation/gdd-*.md §` with **[HANDOFF TO AUTHOR]**, that phase gets a planning session (you + me) to produce the handoff first, in the FF-1 handoff's format.

---

## 4. The wave plan

Each phase lists: **build-from doc**, **hard deps**, **runs on mock?**, **model** (per CLAUDE.md + the handoffs), and **notes**.

### Wave 0 — Foundations (start now; fully parallel; share no files)

These **four** tracks touch disjoint directories (`subsystems/llm/`, `subsystems/factions/`, `subsystems/dialogue/`, `subsystems/quests/`) and have all deps met today. Run concurrently.

| Phase | Build from | Hard deps | Mock? | Model | Notes |
|---|---|---|---|---|---|
| **A · Live LLM L-0** — types, settings, mock, task registry | LLM §19 (Phase L-0) | none | n/a (is the mock) | Sonnet | `is_configured()` stays false → behavior identical to today until a provider is set. Delete the dead `Provider` enum (A2 approved). |
| **A · Live LLM L-1** — transport, queue, `generate()`, Ollama adapter | LLM §19 (Phase L-1) | L-0 | yes (FakeProvider) | Sonnet | **The linchpin completes here.** Run the §8.7 empirical probes with a real key; record results back into the GDD. |
| **B · Faction FF-1** (4 sessions: 1.0→1.3) | `docs/handoff-faction-ff1-build.md` | none (§4 approved) | zero-LLM by design | Sonnet; **Opus for FF-1.3 drift writer** | Ready to run verbatim. Closes stock-take item 7 (`realm_relations` finally has a production writer). |
| **C · Dialogue Phase 1** — the spine | `gdd-npc-dialogue.md` §16 **[HANDOFF TO AUTHOR]** | InteractionResolver (built ✓) | yes (Tier-0 templates) | Sonnet | Reconcile the reaction-router indifferent-disposition drift at build (dialogue §17). Exit test: meet a hermit twice, he remembers, goad him, kill him, dead forever. |
| **Q · Quest-Rumor Q-1** — schema, registries, reward valuator | `docs/handoff-quest-rumor-build.md` §3 | none (FF-1 only *if* enforcing the `questgiver_faction_id` FK — else nullable-no-FK) | yes (zero-LLM) | Sonnet | **A fourth independent foundation** (`subsystems/quests/`) — front-loads the long pole. Migrations from `187_` (reconcile w/ FF-1/npc-personality). Reward valuator: **2× monster-XP bounty + pre-estimated treasure**; reward XP = GP value (ruled). |

**Sequencing inside Wave 0:** prioritize **A (L-0→L-1)** for earliest unblocking, but B, C, and Q do not wait on it. FF-1's four sessions are internally sequential (1.0→1.3). Dialogue P1 is one arc. **Quest-Rumor Q-1** is the gateway to the whole quest track — landing it in Wave 0 means Q-2→Q-4 can fill Wave 1.

### Wave 1 — Second layer (unlocked by Wave 0)

| Phase | Build from | Hard deps | Mock? | Model | Notes |
|---|---|---|---|---|---|
| **A · Live LLM L-2** — wizard + settings UI | LLM §19 (L-2) | L-1 | n/a | Sonnet | UI not exercised by headless suite — verify in-engine via the godot-ai MCP pass. |
| **A · Live LLM L-3** — consumer wiring: Seam A live + NarrativeUpgrader | LLM §19 (L-3) | L-1 | yes | Sonnet | Lands the A6 ordered-pending-queue for GameLog. |
| **A · Ruler Seam B wiring** (rider) | `docs/handoff-ruler-ai-build.md` §10.3 | Live LLM L-1; thresholds (**resolved** §10.5) | — | Sonnet | Small: call `RulerStrategyReassessor.reassess(...)` from the 3 significance sites. Do **not** relax validation. |
| **B · Faction FF-3** — realm diplomacy & rebellion | `gdd-faction-framework.md` §5, §7.3 **[HANDOFF TO AUTHOR]** | FF-1; ruler-AI (built ✓) | yes | **Opus**-leaning (rules interaction) | **Deliberately before FF-2** — FF-3's deps are all met; FF-2 waits on quest-rumor. Treaties + vassal-loyalty triggers + compliance ladder + plots/coalitions + player-as-vassal mirror + resignation path B. |
| **C · Dialogue Phase 2** — transactions | `gdd-npc-dialogue.md` §16 **[HANDOFF TO AUTHOR]** | Phase 1 | yes | Sonnet | Hiring interview, knowledge disclosure, StatusProfile, slander ledger. The **quest-adapter slice is Quest-Rumor Q-5** (Wave 2) — it wires this phase's moves to the registries once Q-2/Q-4 exist. Knowledge richness leans on the npc-personality knowledge generator (gap, §6). |
| **Q · Quest-Rumor Q-2** — questgiver minting + seeding | `docs/handoff-quest-rumor-build.md` §4 | Q-1; settlement stocking, PoI `rumor_seeds`, `sim_polities` income (all built ✓) | yes | **Opus** (generation calibration) then Sonnet | **Closes the long-pole blocker.** Replaces the `_seed_quests_DEFERRED` no-op; determinism is the acceptance gate. |
| **Q · Quest-Rumor Q-4** — completion, turn-in, lifecycle | `docs/handoff-quest-rumor-build.md` §6 | Q-1; combat/lair/exploration signals (built ✓) | yes | Sonnet (Opus for the domain path) | Runs **parallel with Q-2** (only needs Q-1). XP = reward GP value; domain forces single-owner, **no level gate**; expiries re-mint. |
| **Q · Quest-Rumor Q-3** — rumor delivery | `docs/handoff-quest-rumor-build.md` §5 | Q-2; hijink/carousing (built ✓); Dialogue P1 for `ask_rumor` (or the standalone Gather-Info verb) | yes | Sonnet | After Q-2. Carousing 60/40 cash/rumor + 5%/level accuracy bonus (check `ax_campaign_play` duration); Gather Information = distinct 1-hour activity; **no reliability cue** (verification-only). |

### Wave 2 — Convergence (needs the shared gaps closed)

| Phase | Build from | Hard deps | Mock? | Model | Notes |
|---|---|---|---|---|---|
| **B · Faction FF-2** — organizations | `gdd-faction-framework.md` §6 **[HANDOFF TO AUTHOR]** | FF-1; quest-rumor **Q-1→Q-4** (done in Waves 0–1); Live LLM L-1 (narrator rider) | mostly (turns are deterministic) | Opus (temple-rivalry/tithe economics) + Sonnet | Org seeding (promote syndicate seeds), org turns + action vocabulary, temple rivalry + tithe apportionment + **player-ruler apportionment UI** (§6.4 → `gdd-domain-tab.md`), membership/ranks/services, faction journal. `FactionActionNarrator` = Seam-A clone against `generate()`. Its **`post_job` quest bridge is Q-6** (build alongside). |
| **Q · Quest-Rumor Q-5** — dialogue quest adapters | `docs/handoff-quest-rumor-build.md` §7 | Q-2, Q-4; **Dialogue P2** (the adapter slot) | yes | Sonnet | **This is the Dialogue-P2 quest-adapter slice** the plan used to defer. Wires the five dialogue moves (`quest_ask`/`_accept`/`_decline`/`_turn_in`/`ask_rumor`) to the registries. |
| **Q · Quest-Rumor Q-6** — faction `post_job` bridge + narration | `docs/handoff-quest-rumor-build.md` §8 | Q-4, Q-5; **Faction FF-2** (org treasury); Live-LLM L-1 (optional — mock suffices) | mostly | Sonnet (Opus for faction-goal predicate) | **This IS FF-2's `post_job` bridge.** `create_faction_quest` + `faction_goal` polling; faction rewards **gold-only for now, never membership** (O-Q12/13); `_wrap("quest"/"rumor")` prose. |
| **C · Dialogue Phase 3** — the world stage | `gdd-npc-dialogue.md` §16 **[HANDOFF TO AUTHOR]** | ruler-AI (built ✓); army-warfare; Faction (for faction-goal asks) | yes | Opus-leaning | `request_action` matrix; ruler audience + Seam-B packet; army pre-battle parley (coordinate w/ `docs/handoff-army-warfare-seams.md`); post-combat surrender; lying; NPC-side intent + charm defection (flag combat-roster side-switching to the build agent). |

### Wave 3 — Performance & allegiance (tops of the stacks)

| Phase | Build from | Hard deps | Mock? | Model | Notes |
|---|---|---|---|---|---|
| **C · Dialogue Phase 4** — performance layer | `gdd-npc-dialogue.md` §16; LLM §15 profiles | Live LLM L-1 (done Wave 0); Dialogue P3 | n/a (this is the live layer) | Sonnet + model-eval | Live provider wiring, prompt assembly + validators, henchman interjections, LLM summarization, the §13.8 capability harness (needs a live provider — this layer is its prerequisite). |
| **B · Faction FF-4** — allegiance & covert ops | `gdd-faction-framework.md` §7 **[HANDOFF TO AUTHOR]** | FF-2 + FF-3 | yes | **Opus** (allegiance engine) | Feign/betrayal engine, covert-op menu, secrecy/discovery, divided-loyalty events. §11.7 audit instrumentation is mandatory (no feign cap → must be auditable). |
| **D · Dungeon Factions build** (prerequisite for FF-5) | `gdd-dungeon-factions.md` **[HANDOFF TO AUTHOR]** | dungeon-generation systems (built); intersects `gdd-dungeon-contiguous-3d.md` (v0.1, companion edits pending) | yes | Sonnet | **Now in scope.** Independent of the social stack — can build in parallel from Wave 1. Ships `DungeonFaction` generation/territory/relationships so FF-5 has something to link. |
| **B · Faction FF-5** — dungeon tie-in | `gdd-faction-framework.md` §9 (amends `gdd-dungeon-factions.md`) **[HANDOFF TO AUTHOR]** | FF-1; **Dungeon Factions build (Track D)** | yes | Sonnet | Additive: parent links, replenishment draw-down, retaliation, conflict pass. Follows Track D. |
| **Seam · Faction ↔ Dialogue** | faction §10.2 + dialogue §4.3 hooks | FF-1/FF-2; Dialogue P2 | yes | Sonnet | Faction-context block into dialogue prompts; `true_stance` accessor isolation before any prompt sees it. Small integration pass once both sides exist. |

---

## 5. Critical path & what to start first

**Longest hard chain to a fully-live stack:**

```
Live LLM  L-0 ─► L-1 ─► L-2 ─► L-3                ← linchpin done at L-1
Faction   FF-1 ─► FF-3 ─► FF-2 ─► FF-4            ← faction spine
Dialogue  P1 ─► P2 ─► P3 ─► P4                    ← P4 needs Live LLM L-1 (early)
Quest     Q-1 ─► {Q-2 ∥ Q-4} ─► Q-3 ─► Q-5 ─► Q-6 ← core front-loaded:
          Q-1 W0 · Q-2/Q-4/Q-3 W1 · Q-5,Q-6 W2 (Q-5 needs Dlg-P2, Q-6 needs FF-2)
```
The two co-longest chains are the **faction spine** (FF-1→FF-3→FF-2→FF-4) and the **quest chain** (Q-1→Q-2/Q-4→Q-5→Q-6). They interleave at Wave 2: Q-6 needs FF-2, and FF-2's `post_job` bridge *is* Q-6 — build them together.

**Start-first priorities (in order):**

1. **Live LLM L-0 → L-1.** Cheap, dependency-free, unblocks three separate top layers. Highest leverage in the stack.
2. **Faction FF-1** (in parallel). The handoff is ready; nothing gates it; it closes a long-standing stock-take gap.
3. **Dialogue Phase 1** (in parallel). Delivers the single most visible "world comes alive" beat on pure mock.
4. **Quest-Rumor Q-1, in Wave 0** (handoff authored, all opens resolved). Q-1 is a fourth dependency-free foundation; landing it early lets Q-2 (the long-pole closer) and Q-4 fill Wave 1, so by Wave 2 only the cross-system slices Q-5/Q-6 remain. Sequencing note: the quest migration lands *after* FF-1 (FK to `factions`) or ships nullable-no-FK.

**Efficiency wins baked into this ordering:**

- **FF-3 before FF-2.** Inverts the numeric order because FF-3's only dependency (ruler-AI) is already built, while FF-2 waits on quest-rumor. Keeps the faction track moving instead of idling.
- **Mock-first everywhere.** Dialogue P1–P3 and Faction FF-1/FF-3/FF-4 all deliver on the mock provider. Live LLM only gates the *performance/narration* skins (Dialogue P4, FF-2 narrator, Seam B), which are thin riders once L-1 exists.
- **The narrator is a clone, not a new design.** FF-2's `FactionActionNarrator` is explicitly a Seam-A clone against the same `generate()` + task-profile contract (LLM §15, §21). No new LLM architecture per consumer.
- **The long pole is front-loaded, not deferred.** Quest-rumor's core (Q-1→Q-4) builds in Waves 0–1 off already-built systems; only its two convergence slices — Q-5 (Dialogue-P2 adapter) and Q-6 (Faction-FF-2 `post_job`) — sit in Wave 2, landing exactly when their cross-system deps are ready. No phase ever waits on an unbuilt quest system.

---

## 6. System gaps found while planning (flagged, not chased)

Ordered by how much they gate this stack. **Status updated 2026-07-07** — the design chips (§9) closed the design side of gaps 1–3 and 5; what remains is build handoffs, rulings, and one true blocker.

1. **Quest & Rumor system — DESIGN + HANDOFF COMPLETE; folded into the waves.** `gdd-quest-rumor-system.md` **v1.0c** + `docs/handoff-quest-rumor-build.md` (Q-1…Q-6), all 14 opens resolved (incl. the O-Q1 quest-gold-XP ruling: rewards grant XP = GP value, domains exempt; bounties pay 2× monster XP; no reliability cue; no domain level gate). Its phases are now scheduled at their optimal times (§4): **Q-1 Wave 0**, **Q-2/Q-4/Q-3 Wave 1**, **Q-5/Q-6 Wave 2**. It no longer gates Wave 2 wholesale — the core is front-loaded, and only Q-5 (Dialogue-P2 adapter) and Q-6 (FF-2 `post_job`) converge late. Migration lands *after* FF-1 (FK) or nullable-no-FK. **No longer the schedule risk it was.**

2. **`gdd-npc-agency.md` — NOW AUTHORED (v0.1, §9).** Non-ruler NPC personal agency: reuses the ruler/faction scorer + LOD, an 8-action vocabulary, personal purses (§8.7 living-expenses ruling), NPC adventuring parties that draw down dungeons. **Not a v1 faction blocker.** Its surfacing layer (NA-4) hard-depends on quest-rumor; NA-3 depends on the Dungeon Factions build (like FF-5). Slots after FF-2. Needs §5 schema approval before any migration.

3. **NPC-personality relationship/knowledge generators — HANDOFF NOW AUTHORED (§9).** `docs/handoff-npc-personality-generators.md` (RG-1…RG-4). Chip surfaced three facts that affect sequencing: (a) `StrategicDisposition` is already built and its docstring names the missing relationship generator as an **active blocker** for a dormant revenge-bump term — so RG-1 has real value beyond dialogue; (b) latest migration is **186**, so this arc starts at `187_` (the FF-1 handoff's "185" reference is now stale — reconcile migration numbers at build time); (c) **naming collision** — dialogue §4.3 already reserves `NpcRelationship` for PC↔NPC attitude, so the NPC↔NPC social type must be renamed (`NpcNpcRelationship` proposed). RG-2's rumor-pool step couples to the quest-rumor rumor interface.

4. **Dungeon Factions — unbuilt; now IN SCOPE (Track D, §4 Wave 3).** `gdd-dungeon-factions.md` is design-complete but has no engine implementation, and it gates **FF-5**. Now that FF-5 is in scope it gets its own build track (needs a handoff; intersects `gdd-dungeon-contiguous-3d.md`, v0.1 with companion edits pending). This is the one gap in this list that is still a genuine *build* prerequisite with no doc yet beyond its GDD.

5. **Session-log store + session summaries — NOW DESIGNED (§9).** `generation/gdd-session-log-and-summaries.md`: a durable log *additive* to GameLog (no change to the 100-entry cap path), a `session_summaries` table, the SESSION_END hook, and the `session_summary` LLM task contract (mock-first). Build phasing S-0…S-3; **off the critical path.** Unblocks the `session_summary` consumer and gives dialogue-memory summarization (§8.2) a reusable home.

6. **Free-text input (`interpret_player_input`, build-plan "J-5") — undesigned.** The dialogue free-text rider (§5.4) works without it (free text is passed to the performer, not parsed to actions), but a true parse-to-ActionPayload path needs the finalized action vocabulary + a validation layer. Defer past this stack. (Not chipped — genuinely out of scope for now.)

7. **Documentation drift — CLEANUP RAN 2026-07-07 (§9).** Fixed: Live-LLM Seam-B status updated to RESOLVED in 4 places (citing ruler-AI handoff §10.5); build-plan filename typo corrected in 4 files (incl. CLAUDE.md). Confirmed still-open (not doc fixes): `game_log_entries` is genuinely absent from `db/schema.sql` despite migration 041 + active use — a real schema/code drift for a **build** session to fix (do not hand-edit schema.sql casually). Boss-tactical-AI was already scrubbed in a prior session (2026-07-06) — this plan's earlier claim of "stale references remain" was itself stale.

---

## 7. Open decisions for Jedidiah

Sequencing decisions 1–3 from v0.1 are **now settled** (2026-07-07): the "one more" was **both** dungeon-factions and npc-personality (both folded in); **FF-5 is in scope** (Track D added); quest-rumor is a **full build this pass** (GDD now v1.0). What remains are content rulings the design chips surfaced — consolidated as the punch list in **§9**. The highest-impact one:

1. **Quest-rumor opens — ALL RESOLVED (2026-07-07).** O-Q1 (quest-gold XP) ruled *yes* — rewards grant XP = GP value, domains exempt — and O-Q2–O-Q14 are folded into GDD v1.0c and the handoff (bounty 2× monster XP, `understated` accuracy tier, verification-only rumors, no domain level gate, faction rewards gold-only, etc.). Nothing here gates the quest-rumor build any longer. *(No open decision remains in this item — retained for the audit trail.)*

2. **Schema approvals gating migrations:** npc-agency §5 (sidecar tables, purse ledger, `npc_parties`) and the `NpcNpcRelationship` naming/uniqueness question in the npc-personality handoff. Neither blocks *authoring* the handoffs, but both block the *migration* step of their build.

3. **Dialogue §17 residuals** (low priority, Phase-1/3 build-time): charm-awareness-on-save defaults; the offense/enticement trigger list for your review; seduction performance register. None block sequencing.

4. **The rest of the chip open-questions (§9):** 14 for quest-rumor, 10 for npc-agency, 7 each for session-log and the npc-personality handoff. Most are tunable PROJECT-CALL constants that can wait for build/playtest; a handful (flagged in §9) are worth an early ruling.

---

## 8. One-paragraph summary

Build **Live LLM L-0→L-1 first** — it is cheap, has no dependencies, and single-handedly unblocks Ruler Seam B, Dialogue Phase 4, and the Faction narrator. In parallel, run **Faction FF-1** (the handoff at `docs/handoff-faction-ff1-build.md` is ready to go), **Dialogue Phase 1** (mock spine), and **Quest-Rumor Q-1** (a fourth dependency-free foundation). Then **FF-3 before FF-2**, Dialogue P2, and the quest core **Q-2/Q-4/Q-3** all fill Wave 1, and finish Live LLM L-2/L-3. The quest system — once the stack's bottleneck — is now front-loaded: only its two convergence slices remain late, **Q-5** (the Dialogue-P2 quest adapter) and **Q-6** (the Faction-FF-2 `post_job` bridge), each landing exactly when its cross-system dep is ready. Everything except the live-performance skins runs on the mock provider, so most of the "world comes alive" value lands before a single real LLM call.

---

## 9. Design chips authored 2026-07-07 — deliverables & pending rulings

Five design/authoring sessions ran to close the gaps in §6. All are **design docs only** (no engine code, no migration files, no build-log entries), each build-ready pending the rulings below.

| Deliverable | Path | Status | Phases | Open Qs |
|---|---|---|---|---|
| Quest & Rumor GDD **+ build handoff** | `generation/gdd-quest-rumor-system.md` (**v1.0c**) + `docs/handoff-quest-rumor-build.md` | matured + handoff authored; **all 14 opens resolved**; phases folded into §4 waves | Q-1…Q-6 | **0 open** |
| NPC Agency GDD | `generation/gdd-npc-agency.md` | new, **v0.1** | NA-0…NA-4 | 10 |
| Session Log & Summaries GDD | `generation/gdd-session-log-and-summaries.md` | new | S-0…S-3 | 7 |
| NPC-personality generators handoff | `docs/handoff-npc-personality-generators.md` | new | RG-1…RG-4 | 7 |
| Doc-drift cleanup | edits to `gdd-live-llm-integration.md`, `CLAUDE.md`, +3 files | done | — | — |

**Rulings worth making early** (the remaining ~35 open questions are tunable PROJECT-CALL constants that can wait for build/playtest):

- ~~**Quest-gold XP** (quest-rumor O-Q1)~~ — **RESOLVED (2026-07-07):** rewards grant XP = their GP value (domains exempt). All 14 quest-rumor opens are now closed (GDD v1.0c + handoff); none remain to rule.
- **npc-agency §5 schema approval** — sidecar tables / purse ledger / `npc_parties`; and whether to generalize the approved `ruler_dispositions` into `npc_dispositions` (chip recommends in-memory caching, no new table, for v1).
- **`NpcNpcRelationship` naming + pair-uniqueness** (npc-personality handoff) — dialogue §4.3 already owns the identifier `NpcRelationship` for a different (PC↔NPC) concept; confirm the rename before RG-1's migration.
- **Gather-Information framing** (quest-rumor O-Q5) — ACKS 1e has no generic "Gather Information"; confirm it reduces to carousing / spying / venturer rumormongering as the GDD designed.

**Cross-cutting sequencing notes the chips surfaced (fold into the handoffs when authored):**

- Quest migration lands **after FF-1** (`quests.questgiver_faction_id` FK → `factions`) or ships nullable-no-FK.
- Migration numbering: latest on disk is **186**; new arcs start at `187_`. The FF-1 handoff still cites "185" — reconcile at build time.
- npc-agency **NA-4** (surfacing) couples to quest-rumor; **NA-3** (NPC parties) couples to the Dungeon Factions build (Track D) — same dependency family as FF-5.
- npc-personality **RG-2** (knowledge assigner) rumor-pool step couples to quest-rumor's rumor interface — build RG-2 after, or alongside with a stubbed interface.
- RG-1 also unblocks a **dormant revenge-bump** term already shipped in `StrategicDisposition` — a small bonus beyond dialogue.
