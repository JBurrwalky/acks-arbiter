# GDD: NPC Agency (Personal-Scale Action & AI for Named Non-Ruler NPCs)

**Document type:** Game Design Document (satellite of the faction/ruler/personality agent family)
**Authority:** PROJECT-DESIGNED — the personal action vocabulary, the scoring adaptation, the personal-purse ledger, the LOD attachment, and the NPC-party-as-agent lifecycle are project design filling the gap the faction framework §13 explicitly declares. Everything ACKS *does* say about hijinks, magic research, henchman/specialist wages, living expenses, and NPC-party composition is quarantined in §2 (sacred) and constrains the design. This GDD **reuses** two already-built engine patterns wholesale and re-specifies neither: the personality scorer/derivation ([gdd-npc-personality.md](gdd-npc-personality.md) §8) and the ruler planner loop/LOD ([gdd-ruler-ai.md](gdd-ruler-ai.md)).
**Status:** Draft v0.1 — first authoring, per the faction framework §13 "Declared sibling — `gdd-npc-agency.md`" scope. Slots **after FF-2** and is **not a v1 faction blocker** (org-level agency suffices — faction §13). Cross-references the **concurrently-spec'd** quest-rumor system ([gdd-quest-rumor-system.md](gdd-quest-rumor-system.md)); the coupling is flagged throughout (§10, §12) — this GDD forward-references it and does not assume its final shape. Data model in §5 is **DESIGN ONLY** — Layer-3 tables require Jedidiah's approval before any migration (§13 flag). Nothing here restructures an existing interface, autoload, or cross-system contract.
**Depends on ACKS rules:** `rules/acore-campaign-hijinks.xml:501-524` (Monthly Hijink Income table L0–8; **"Hijinks by 9th level or higher characters should always be rolled individually"** — the L9+ individual-path anchor), `:61-409` (the six core hijinks + Crime & Punishment), `:412-525` (criminal-guild management, change-in-management); `rules/ax_campaign_play.xml:96-123` ("Pay PC and NPC living expenses" — the RAW expense phase the personal purse settles), `:503-732` (the ruler/character monthly activity vocabulary — the reduce-to targets), `:1127-1256` (Axioms plan/perform/lay-low hijink timing + extra hijinks); `rules/rulings_living_expenses_and_social_status.xml` (the Judge ruling: living expenses = level-equivalent monthly wage; optional player fee drives apparent social rank) and `rules/acore_henchmen_monthly_fee_table.xml` (the L0–14 wage table by class level, the purse's unit of account); `rules/acore-campaign-general-and-magic-research.xml:52-106,255-275` (magic research: **1,000gp + 2 weeks per spell level**, throw vs. Magic Research Target by Level, library requirement, +1/10,000gp over minimum to max +3), `:528-608` (congregations/proselytizing — a leader's personal divine-power stream); `rules/pc_magic_experimentation.xml:3-30,274-276` (magic research throw + experimentation bonus + mishap recovery cost); `rules/acore_equipment.xml:663-668` (specialists' flat monthly fee), `:709-728` (specialist availability by market class), `:872-992` (specialist roster + monthly pay: Alchemist 250 / Armorer 75 / Engineer 250 / Sage 500 / Animal Trainer 25–250 / Ruffian carouser 6–spy 125 / Spellcaster "varies"; **Ruffian.advancement: "if they level up, use the Henchmen Monthly Fee table for higher wages"**), `:816-820` (specialists exempt from the henchman cap); `rules/pc_followers_tables_rules.xml` (followers/henchmen tables); `rules/acore_core_classes.xml:311-325` (fighter's castle following), `:1306-1325` (cleric's fortified church following), `:1381-1382` (thieves belong to a guild); `rules/acore_campaign_classes.xml:345-361` (assassin hideout + infiltrator); `rules/ax_venturer_class.xml:158-213` (venturer trade routes, rumormongering, monopoly); `rules/acore-monster-stocking-rules.xml:446-524` (**NPC adventuring party composition** — 1d4+2 members, one 1d6 party-alignment roll, base level = 7 − market class in settlements / nearest-dungeon max in wilderness / dungeon level in dungeon, per-member 1d6 NPC Level roll, members within one alignment step), `:69` (the reserved NPC-party wandering slot); `rules/acore_aging_poisons_high-level-start_optional_rules.xml` (aging — retire/legacy timing); the henchman loyalty engine (`rules/acore_equipment.xml:745-826`) for take-to-adventure recruitment.
**Depends on project GDDs:** [gdd-npc-personality.md](gdd-npc-personality.md) (the twelve axes, Motivation, `StrategicDisposition`, and the §8.3 derivation formulas + §8.5 monthly-loop sketch — this GDD **generalizes §8.5 from rulers to all Tier-A/B NPCs** and reuses the scorer shape verbatim); [gdd-ruler-ai.md](gdd-ruler-ai.md) (the planner loop, the RefCounted service pattern, the monthly-tick hook, Regional-LOD §8, backdrop auto-stabilize, the Seam-A narration contract — the direct precedent this GDD parallels for non-rulers); [gdd-faction-framework.md](gdd-faction-framework.md) (§6.6 org month/ledger — the org-leader personal path attaches at its named-L9+ seam; §8.7 living expenses & apparent social rank — the personal-purse ruling; §2.9 NPC parties / lair society; §13 the scope declaration; membership/stance registry the leader personal actions write to); [gdd-quest-rumor-system.md](gdd-quest-rumor-system.md) (**concurrently spec'd**; questgiver motivation and rumor emission are the two player-facing outputs of this system — coupling flagged); [gdd-npc-dialogue.md](gdd-npc-dialogue.md) (the "what is this NPC up to?" context block consumer; the NPC's `current_activity` and `motivation_hooks` feed its prompt); [gdd-specialists.md](gdd-specialists.md) (the built `SpecialistHireManager.process_monthly_wages` + PartyWallet wage-tick pattern the personal-purse tick mirrors; specialist wage table = occupation-income source); [gdd-realtime-scheduler.md](gdd-realtime-scheduler.md) (EventScheduler monthly cadence + optional self-paced event); [gdd-setting-runtime-materialization.md](gdd-setting-runtime-materialization.md) (named→full promotion tiers the LOD gates on); [gdd-dungeon-factions.md](gdd-dungeon-factions.md) (the rival NPC party that clears "your" dungeon links here for its parent/allegiance metadata via faction §9).
**Consumed by (forward dependency):** the build agent; [gdd-npc-dialogue.md](gdd-npc-dialogue.md) (activity/motivation context); [gdd-quest-rumor-system.md](gdd-quest-rumor-system.md) (questgiver motivation + faction/NPC-sourced rumors); the faction framework (leader personal ambition now expressed beyond org `goal_primary`); future `gdd-dynasties.md` (retire/legacy/heir timing is the natural seam to a succession system).
**Modifiable by Claude Code:** Yes within constraints — §2 (ACKS Constraints) is sacred and may not be reinterpreted; all numeric constants in §4/§6/§7 are PROJECT CALL and tunable; §5 data-model additions are Layer-3 and REQUIRE Jedidiah's approval before migration (flagged); interface names, once approved, follow the naming conventions and may not drift.
**Last updated:** 2026-07-07

---

## 1. Purpose and Scope

### 1.1 What this document is

Three agent layers already exist or are designed in this project:

1. **Rulers** think with `RulerAI` — a deterministic monthly planner over a domain action space, scored by `StrategicDisposition`, gated by Regional-LOD ([gdd-ruler-ai.md](gdd-ruler-ai.md)).
2. **Organizations** think with **faction turns** — a monthly batch where each active-LOD org scores a small goal-driven action vocabulary using its *leader's* disposition, budget-gated by an abstract ledger ([gdd-faction-framework.md](gdd-faction-framework.md) §6).
3. **Everyone else who matters** — the named non-ruler NPC: a mages'-guild archmagist, a temple's high priest, a retired mercenary captain in a tavern, a scholar with a grudge, a rival adventurer — currently thinks with **nothing**. `gdd-npc-personality.md §8.5` scopes its monthly loop to rulers only; the only personal-scale NPC economy in code is the syndicate resolver's L9+ individual path.

This GDD authors the fourth layer: **personal-scale agency for named non-ruler NPCs.** It is the system that answers, mechanically and deterministically, "**what is this NPC up to this month?**" — so that dialogue can say it, quests can spring from it, and the rival party really does empty the dungeon before the players get there. It is the "personal ambitions surface only as org `goal_primary` bias" gap that faction §13 closes.

It is deliberately the **smallest** of the four agent layers. Rulers run domains; orgs run institutions; a named NPC runs *a life* — a handful of monthly choices over work, training, research, scheming, courtship, relocation, retirement, and the occasional expedition. The design reuses the ruler/faction machinery so aggressively that most of this document is *placement and adaptation*, not new invention.

### 1.2 The strategic/organizational/personal boundary (read this first)

This layer must not collide with the three it sits beside.

- **Ruler decisions (existing, out of scope here):** what a *ruler* does with a *domain* on its monthly turn. If an NPC rules a domain, `RulerAI` owns its strategic turn. This GDD never touches domain actions.
- **Faction turns (existing, out of scope here):** what an *organization* does with its *institution* on its monthly turn. If an NPC leads an org, the **org turn** owns the institution's action (recruit, proselytize, raise funds, post a job, run an op). This GDD gives that same leader a **second, personal** turn for actions the org turn does not cover — see §3.2 and the boundary rule in §4.5.
- **Personal turn (this GDD):** what a *named individual* does with *their own month* — advance their own class, fatten their own purse, pursue their own motivation, walk into a tavern with a grudge and a retinue. Expressed through the same twelve axes + Motivation that already drive the ruler and org scorers.

**The one-line boundary:** *the ruler turn moves the realm; the org turn moves the institution; the personal turn moves the person.* An NPC may be all three (a ruler who leads a knightly order and personally researches spells) — they simply take up to one action in each layer per month, each layer scored independently, each reducing to its own RAW-defined operations. §4.5 gives the precedence and de-duplication rule that keeps a leader from "acting twice on the same thing."

### 1.3 v1 scope (the five confirmed deliverables, from faction §13)

The faction §13 declaration pins the scope exactly; this GDD delivers all five:

- **(a) Org leaders' personal actions beyond the org turn** — L9+ individual hijinks per RAW, magic research at RAW prices, and class-endgame moves (§4.3). This is the seam faction §6.6 explicitly reserves: "Named L9+ members resolve individually per RAW — which is precisely the seam where the personal-agency sibling GDD attaches."
- **(b) Tier-A/B named NPCs pursuing motivations** through a small personal action vocabulary — `work`, `train`, `research`, `scheme`, `court`, `relocate`, `retire`, `take_to_adventure` — monthly, **active-LOD only**, scored by the **same** motivation + personality-axes machinery the ruler/faction systems use (§4.2, §7). The scorer is *reused, not reinvented.*
- **(c) Personal purses** — living expenses per the faction §8.7 ruling (level-equivalent monthly wage; apparent-rank spend as personality flavor) plus occupation income from the RAW specialist/wage tables (§6).
- **(d) NPC adventuring parties as spawned agents** — RAW composition (§2.9 of faction / `acore-monster-stocking-rules.xml`); the rival party clearing "your" dungeon becomes a real, moving, persisting agent (§8).
- **(e) Feeds** — to Dialogue ("what is this NPC up to") and to the Quest & Rumor system (questgiver motivation) (§10). **Explicitly NOT Tier C transients** — scenery stays scenery (§1.4).

### 1.4 Non-goals

- **No Tier C agency.** Transient encounter NPCs (three sampled axes, not persisted) get **no** personal turn, no purse, no activity state. Scenery stays scenery (faction §13; personality §2). A Tier C NPC promoted to Tier B (personality §4.2) becomes eligible then, not before.
- **No thousand-agent simulation.** This is faction-style LOD: **active-LOD named NPCs only** — dozens near the player, not the tens of thousands a settlement's full population implies. The scale envelope (§11) is deliberately small. CK-style per-courtier continuous plotting is out of reach and out of genre (faction §11.5 applies verbatim).
- **No new economy.** Personal actions reduce to operations ACKS or existing GDDs already define (hijinks, magic research, the specialist/henchman wage tables, the henchman-loyalty recruitment engine, the NPC-party stocking rules). This GDD chooses *among* them; it invents no new money.
- **No LLM decisions.** Identical to the ruler and faction layers: the engine decides deterministically; the LLM narrates retroactively and colors dialogue. The full loop passes on the mock provider.
- **No dynasty/heir modeling.** `retire` and `legacy`-motivated actions produce the *timing seam* a future `gdd-dynasties.md` consumes; this GDD does not model succession-by-inheritance (consistent with ruler-AI §1.4).
- **No standalone downtime UI for NPCs.** The player never micromanages an NPC's month. Personal turns are engine-internal; their only surfaces are dialogue, rumors, quests, and (for a player-*employed* NPC — henchman/specialist) the existing directed-downtime path, which this GDD does **not** replace (design brief §10.5; henchmen stay player-directed).

---

## 2. ACKS Constraints

These come from the books and may NOT be changed. Every personal action this layer selects must reduce to operations ACKS already defines.

### 2.1 Living expenses and the wage table (the purse's foundation)

- **RAW mandates a monthly expense phase:** "Pay PC and NPC living expenses" is a step in the monthly cycle (`rules/ax_campaign_play.xml:96-123`). The published corpus gives **no per-level amount** for it — the gap the Judge ruling fills.
- **Judge ruling (`rules/rulings_living_expenses_and_social_status.xml`, 2026-07-06):** living expenses in the general case is a **synonym for the character's level-equivalent monthly wage** per the Henchmen Monthly Fee table; **NPCs are assumed to pay their level-equivalent wage by default.** An optional player rule lets a character pay a monthly fee in lieu of itemized upkeep, and that fee feeds **apparent social rank** — underspend your level's wage → treated as lower rank; overspend → treated as higher ("spending like a duke → treated like a duke").
- **The Henchmen Monthly Fee table by class level (`rules/acore_henchmen_monthly_fee_table.xml`):** L0 12 / L1 25 / L2 50 / L3 100 / L4 200 / L5 400 / L6 800 / L7 1,600 / L8 3,000 / L9 7,250 / L10 12,000 / L11 32,000 / L12 50,000 / L13 135,000 / L14 350,000 gp. This is the unit of account for both the expense side (living expenses) and one income side (a leveled NPC's earning power), and it is already carried in `data/equipment/provisions_services.json` (L9–14 mirrored in `NpcSyndicateMonthlyResolver`).

### 2.2 Occupation income — the specialist/wage tables

- **Specialists are hired for a flat monthly fee** (`rules/acore_equipment.xml:663-668`) and their pay is published per role (`:872-992`): Alchemist 250gp, Armorer 75gp (produces 40gp of goods/month), Engineer 250gp, Sage 500gp, Animal Trainer 25–250gp, Healer (see roster), Mariner (see roster), **Ruffian** by type (carouser 6gp/L0, footpad 25gp/L1, reciter 25gp/L1, spy 125gp/L4, thug 25gp/L1), Spellcaster "varies" by market class and spell level. **Specialists are exempt from the henchman cap** (`:816-820`).
- **Availability scales by market class** (`:709-728`) — a Class I city has many alchemists (1d10) where a Class VI hamlet has a 5% chance of one. This is the RAW hook for *whether* an NPC's occupation exists in a given settlement.
- **Ruffian advancement is explicit and load-bearing:** "May gain XP from hijinks; **if they level up, use the Henchmen Monthly Fee table for higher wages**" (`:956`). RAW itself bridges a low-level earner's income onto the wage table as they advance — the exact bridge the personal-purse occupation model uses (§6.3).

### 2.3 Hijinks — the L9+ individual path (deliverable (a))

- **The Monthly Hijink Income table** (`rules/acore-campaign-hijinks.xml:501-518`) nets a syndicate member's monthly take by level: L0 1 / L1 5 / L2 30 / L3 200 / L4 425 / L5 650 / L6 835 / L7 1,500 / L8 2,000 gp — and **"already factors in wages, attorneys, bribes, fines, and healing"** (`:523`).
- **The scope boundary is RAW-drawn:** "the Monthly Hijink Income table may be used instead of rolling hijinks individually for characters of **1st through 8th level**" (`:521`); **"Hijinks by 9th level or higher characters should always be rolled individually"** (`:522`). The abstract table covers the org's rank-and-file (faction §6.6); **the individual roll is the named L9+ leader's personal action** — the exact split this GDD implements.
- **The six core hijinks** (Assassinating, Carousing, Smuggling, Spying, Stealing, Treasure Hunting) each resolve on a thief skill throw; failure by 14+ or natural 1 → caught → the Crime & Punishment 2d6 table (`:61-409`). Axioms adds plan/perform/lay-low timing and extra hijinks whose civilian resolution is otherwise absent from the corpus (`rules/ax_campaign_play.xml:1127-1256`; the gap faction §14.2 flags — v1 uses the six core hijinks + the faction §6.7 op menu only).

### 2.4 Magic research — RAW prices (deliverable (a))

- **The research procedure** (`rules/acore-campaign-general-and-magic-research.xml:52-106`): pay **1,000gp per spell level**, spend **2 weeks per spell level**, make a **magic research throw** (1d20 vs. the Magic Research Target by Level for the caster). An arcane caster may research a spell only if he can still learn spells of that level; a divine caster only with his deity's permission.
- **A library is required** (`:103`); **+1 to the throw per 10,000gp of value above the minimum, to a maximum of +3** (`:106`). Item creation, constructs, and other research forms use the same throw with their own costs (`:255-275` etc.).
- **Experimentation** grants a throw bonus at the risk of a mishap; mishap recovery costs 1 week + 1,000gp per spell level (`rules/pc_magic_experimentation.xml:3-30,274-276`). v1 personal research uses the base (non-experimental) procedure; experimentation is a tunable extension (§13).

### 2.5 Class-endgame following & personal power (deliverable (a))

- A **cleric's fortified church** (9th) draws 5d6×10 soldiers + 1d6 clerics L1–3, unpaid and "completely loyal, morale +4"; **congregation/proselytizing** yields divine power and countable congregants (`rules/acore_core_classes.xml:1306-1325`; `rules/acore-campaign-general-and-magic-research.xml:528-608`). A **fighter's castle** draws mercenaries + 1d6 fighters (`:311-325`). A **mage sanctum** draws apprentices; a **thief's hideout** makes its builder a syndicate boss (§2.3); the **assassin's hideout** draws apprentices including a rival's infiltrator (`rules/acore_campaign_classes.xml:345-361`); the **venturer** gets trade routes, rumormongering (1d4 rumors/settlement/month), and monopoly (`rules/ax_venturer_class.xml:158-213`). These are the **endgame moves** a named leader personally makes — most of which *create* the very org the faction layer then runs. This GDD triggers them for NPCs (the NPC mirror of design brief §8.6 player-founded factions); it does not re-specify the domain systems that execute them.

### 2.6 NPC adventuring party composition (deliverable (d))

- **NPC parties** (`rules/acore-monster-stocking-rules.xml:446-524`): roll **1d4+2** members (1d4+3 at high level per the wandering-table entry `:134`); roll **1d6 once for the whole party's alignment** (1–2 Lawful / 3–5 Neutral / 6 Chaotic per `:475`), members within one step; determine **base level** (settlement: **7 − market class**; wilderness: max level of the nearest dungeon; dungeon: the dungeon level encountered — `:468-471`); roll **1d6 per member on the NPC Level table** for each member's actual level relative to base (`:519-523`: 1→base−2, 2→base−1, 3–4→base, 5→base+1, 6→base+2, min 1). The party occupies a **reserved slot on every men-and-monsters wandering table** (`:69`).
- **Lair society is species-published** (faction §2.9): orc gangs/warbands/villages with champions and chieftains, chieftain morale bonuses, monster ML. When an NPC/monster group persists past one encounter, it becomes a `warband`-scope faction (faction §6.1) and — if in LINK_RANGE of a parent — links via faction §9. This GDD owns the *agent lifecycle* of a persisting NPC party; faction §9 owns its *parent/allegiance metadata*.

### 2.7 The take-to-adventure recruitment engine

- Recruiting a companion for an expedition is the **henchman hiring + loyalty** engine (`rules/acore_equipment.xml:745-826`; `rules/pc_followers_tables_rules.xml`): a reaction/interview, then a loyalty score = 2d6 + morale (base = employer CHA mod), rolled at calamities, level-up, and power-inversion, with the RAW results table (2− Hostility … 12+ Fanatic). An NPC who `take_to_adventure`s another NPC uses this same engine — no parallel system. Ruffians and non-henchman companions have their RAW constraints (ruffians won't adventure "unless recruited as henchmen", `rules/acore_equipment.xml:955`).

---

## 3. Architecture and Integration

### 3.1 Placement (no new autoload)

The design brief restricts autoloads to truly-global systems (`GameState`, `CampaignRepository`, `LLMManager`, `AudioRouter`, `EventBus`); new subsystems are `RefCounted` services (the `realm_ai/` and `factions/` precedent). This layer follows suit:

- New service **`NpcAgencyAI`** (`class_name NpcAgencyAI`, `npc_agency_ai.gd`), recommended under `engine/subsystems/npc_agency/` for cohesion, sitting **beside** `realm_ai/` and `factions/`, not inside them.
- Sub-components (all `RefCounted`, stateless statics where possible, mirroring `RulerAI`'s decomposition):
  - `PersonalActionCatalog` — precondition-gated candidate actions for a given NPC (§4).
  - `PersonalActionScorer` — the reused scorer (§7); reads the NPC's twelve-axis `NpcPersonality` + `StrategicDisposition` exactly as `RulerActionScorer` does.
  - `PersonalPurseResolver` — the monthly income/expense/apparent-rank tick (§6), mirroring `SpecialistHireManager.process_monthly_wages` + `NpcSyndicateMonthlyResolver`.
  - `NpcAgencyLodManager` — thin adapter that **reuses the ruler active-set** (§3.4); it holds no LOD policy of its own.
  - `NpcPartyLifecycle` — spawn/persist/despawn of NPC adventuring parties as agents (§8).
  - `PersonalActionNarrator` — the LLM seam; a **clone** of `RulerActionNarrator` (§9), exactly as faction's `FactionActionNarrator` clones it.
- **Determinism is mandatory.** Every personal decision is reproducible from (NPC state + world state + a seeded RNG). Banker's rounding everywhere a value rounds. The full loop passes with the mock provider (`is_configured()` false).

### 3.2 The monthly-tick hook (one batch, three layers, fixed order)

The personal turn runs inside the **existing** monthly cadence, immediately **after** the org faction turns, which run after the ruler turns, which run after the per-domain economic resolution and the `NpcSyndicateMonthlyResolver` slot. This ordering is deliberate and load-bearing (§4.5):

```
domain_handlers._handle_monthly_tick:
  1. _resolve_domain_month(...)           # economy: revenue/expense/morale/growth (all domains)
  2. NpcSyndicateMonthlyResolver.resolve  # syndicate abstract months (L0–8 table)  [existing]
  3. RulerAI.process_campaign_month(...)   # ruler strategic turns (active set)       [gdd-ruler-ai]
  4. FactionAI.process_campaign_month(...) # org faction turns (active-LOD orgs)      [faction §6.6]
  5. NpcAgencyAI.process_campaign_month(campaign_id, calendar_day, active_set) -> Array   # THIS
```

`NpcAgencyAI.process_campaign_month(...)` has the **same shape** as `RulerAI.process_campaign_month` and `FactionAI.process_campaign_month`. For each **active-LOD named NPC** (§3.4) it runs the personal decide→execute loop (§4, §7): settle the purse first (income → expenses → apparent-rank update, §6), then score candidate actions within means, execute the winner deterministically, emit `npc_agency_action_taken`, and narrate retroactively only when player-relevant (§9). Mutations land before the tick returns. **No `auto_pause`** is emitted for NPC personal turns (the world clock never stops for an off-screen scholar's research throw).

Running personal turns **after** ruler and org turns means the NPC already knows this month's institutional facts (their org posted a job, their liege raised tribute) before choosing a personal response — and lets §4.5's de-duplication suppress a personal action the leader already expressed as an org/ruler action.

### 3.3 Optional self-paced strategic event (alternative cadence)

If a named NPC must act off the monthly boundary — a rival party racing the players to a dungeon needs to *move on the wilderness clock*, not wait for month-end — register the scheduler event pattern ruler-AI §3.4 already defines, keyed to the NPC's `character_id`:

```
scheduler.schedule_at(now + period_rounds, "npc_agency_turn",
                      npc_character_id, {kind: ...}, PRIORITY_ENVIRONMENTAL)
```

Self-reschedule via the handler's `next_events` return; `cancel_all_for_owner(npc_character_id, "npc_agency_turn")` on LOD demotion. **v1 default: monthly batch only** for the personal action vocabulary (§4); the per-agent event is used **specifically** for NPC-party movement/dungeon-race pacing (§8.4), where month-granularity is too coarse to feel like a race.

### 3.4 LOD — inherit the ruler active set wholesale (no new policy)

This layer defines **no LOD policy of its own.** `NpcAgencyLodManager` is a thin adapter over the already-built Regional-LOD (ruler-AI §8), exactly as faction §11.2 inherits it "wholesale." The **active set** for personal turns is:

- **Active:** named NPCs (`persistence_tier == "full"`, i.e., Tier A or fully-materialized Tier B) whose home location lies in the **6-mile play window + 10-six-mile-hex buffer ring**, **plus** any named NPC currently party to a player-relevant interaction/conflict regardless of distance (the questgiver the party is talking to; the rival captain the party is chasing), **plus** any NPC leading an **active-LOD org** or holding a **party-instantiated membership/stance** (the party's guild archmagist stays live wherever the party goes — faction §11.2's "party's guild stays live" rule, extended to that guild's *leader as a person*).
- **Materialization safety (the buffer never forces materialization):** identical to ruler-AI §8.1. A `named`/lazy NPC in the window or buffer stays **inert** (Backdrop) until the existing promote-on-visit path makes it `full`; the personal-agency layer **never** triggers promotion. LOD is strictly downstream of materialization.
- **Backdrop:** every other named NPC. **No personal turns.** Their purse gets a cheap **auto-stabilize** pass (§6.4) — assume income ≈ living expenses, apparent rank unchanged — mirroring ruler-AI §8.4 and faction §11.2's treasury auto-stabilization. Backdrop NPCs do not scheme, relocate, or spawn parties; the world near the player is where personal drama happens, and a freshly-approached NPC is coherent (mid-project, mid-grudge) rather than frozen or spuriously churned.

**Promotion/demotion** reuse the ruler signals' pattern: on promotion, build the NPC's `StrategicDisposition` if not cached (personality §8.3) and, if using §3.3 events, seed its `npc_agency_turn`; on demotion (player left, no active involvement, one-month grace), cancel its scheduled events. Emit `npc_activated_for_agency` / `npc_deactivated_for_agency` for observability and save/load reconciliation.

### 3.5 Determinism and the LLM boundary

Identical world state + seed → identical NPC lives. Banker's rounding wherever a value rounds. Every personal decision, purse settlement, and party spawn works with the mock provider; the LLM only ever (a) retroactively narrates a personal action via the existing `GameLog` → `EventBus.log_entry_added` → UnifiedLog Seam-A pipeline (§9), and (b) colors dialogue with the NPC's activity/motivation context block (§10.1). The LLM never chooses a personal action, never sets a purse, never spawns a party.

---

## 4. The Personal Action Vocabulary (v1)

### 4.1 The eight actions

Faction §13 names them; this GDD gives each its reduce-to target, governing driver, and preconditions. **Every action reduces to an existing mechanic** — like the ruler catalog (ruler-AI §5) and the org catalog (faction §6.5), the scorer chooses *among* these; it invents none. One personal action per NPC per month (large-life NPCs — an archmagist who both runs a guild and researches — still take **one** personal action; their org action is separate, §4.5).

| Action | Reduces to (existing mechanic + citation) | Governing driver (axis / weight / motivation) | Preconditions |
|---|---|---|---|
| `work` | **Occupation income** to the personal purse (§6.3): the RAW specialist/wage-table earning for the NPC's role/level (`acore_equipment.xml:872-992`; leveled earners bridge to the Henchmen Monthly Fee table per `:956`) | `economic_weight`; `wealth`/`duty`/`survival` motivation | has an occupation; occupation viable in current settlement (market-class availability, `:709-728`) |
| `train` | **Advance the NPC's own class** — the level-up sequence run silently (design brief §10.6: "NPCs run the sequence silently"): accrue notional XP toward the next level, or spend gp+time on training where the campaign models it | `military_weight` (martial), `research_weight` (arcane), `religious_weight` (divine); `power`/`legacy`/`duty` | below a level ceiling (§4.4); has means/time |
| `research` | **Magic research at RAW prices** (§2.4): 1,000gp + 2 weeks per spell level, throw vs. Magic Research Target; **or** item/construct creation on the same throw | `research_weight`; `knowledge` motivation | arcane/divine caster who can still learn that spell level; has a library (`acore-campaign-general-and-magic-research.xml:103`); purse ≥ cost |
| `scheme` | **A personal covert operation** — for an L9+ criminal, an **individual hijink** rolled per RAW (§2.3, the L9+ individual path); for anyone else, the faction §6.7 op menu run **as a 1st-level thief** (faction's non-thief ruling) or a hire of a syndicate (faction §6.7 for-hire market) | `oppression_weight`/low `self_interest`; `power`/`revenge`/`freedom` motivation | has a target/grudge (a `rival`/`enemy` relationship, personality §5.2, or a faction grievance); base of operations for hijinks |
| `court` | **An Axioms influence campaign** toward a relationship goal — a patron, a marriage/alliance, a mentor, a superior's favor — resolved on the reaction/influence ladder (`ax_reactions_and_influencing.xml`; faction §2.1) over successive attempts | `diplomatic_weight`; `power`/`pleasure`/`legacy`/`security` motivation; `amorousness` colors romantic courtship | has a courtship target (an NPC or a faction patron) in reach |
| `relocate` | **Move the NPC's home location** — change `home_settlement`/`home_poi`; a survival/opportunity move (mirrors faction §6.5 `relocate` for orgs) | `crisis_response`; `freedom`/`survival`/`wealth`/`security` motivation | a reason (danger, better market for the occupation, following a patron); despawns from old locale's active set, may re-materialize in the new |
| `retire` | **Withdraw from active life** — set a `retired` activity state; stop taking `train`/`scheme`/`take_to_adventure`; optionally convert to a purely social presence (a quest-giving elder). The **timing seam** a future `gdd-dynasties.md` consumes for succession | age (`acore_aging_poisons…`), `legacy`/`security` motivation, low remaining ambition | typically high level + advancing age, or a completed life-goal; PROJECT CALL trigger (§4.4) |
| `take_to_adventure` | **Recruit companions and mount an expedition** — the henchman hiring + loyalty engine (§2.7) to assemble a party, then **spawn an NPC adventuring party agent** (§8) targeting a dungeon/lair/quest | `military_weight`; `wealth`/`power`/`knowledge`/`redemption` motivation; adventurer-type roles | adventurer-class NPC (or a leader with adventuring history); a viable target in range; means to hire |

### 4.2 Scoring — reuse the ruler/faction scorer (do not reinvent)

`PersonalActionScorer` uses the **identical shape** as `RulerActionScorer` (ruler-AI §6) and the org scorer (faction §6.5):

```
utility(a) = base_value(a)                       # PROJECT CALL per-action baseline desirability, 0–1 (§4.3)
           * relevant_weight(a, disposition)     # the action's governing weight/motivation term (§4.1)
           * Π situational_modifier_i(a, npc, world)   # §7.2
```

- **The disposition is the same struct.** `StrategicDisposition` (personality §8.2) is already generatable for any named NPC — it is not ruler-only; ruler-AI §4 builds it from the 12-axis `NpcPersonality` + alignment via the §8.3 formulas, and this GDD calls the **same `StrategicDispositionBuilder`**. The eight weights + `crisis_response` drive personal scoring exactly as they drive ruler scoring; the "HTN-lite" allowance stands — the scorer MAY read raw axis values (e.g., `epistemic_curiosity` nudging `research` over `work`, `amorousness` nudging romantic `court`).
- **Motivation is the primary personal driver.** Because a *person's* month is less constrained than a *domain's*, the Motivation tags (personality §3.3) carry more weight here than in the ruler scorer: a `knowledge`-motivated archmagist scores `research` high; a `revenge`-motivated exile scores `scheme` high; a `pleasure`-motivated noble scores `court`. The `mot(t)` helper (personality §8.3) is reused verbatim.
- **Tie-break + determinism:** a per-(NPC, calendar_month) seeded RNG breaks ties; banker's rounding on any division; reruns are byte-identical (§12).

### 4.3 base_values and the endgame hook (deliverable (a) leaders)

Baseline desirabilities (PROJECT CALL, tunable) anchor the "default life" — most named NPCs mostly `work` and occasionally `train`/`court`:

| Action | base_value | Notes |
|---|---|---|
| `work` | 0.45 | the floor; a named NPC with an occupation defaults to earning |
| `train` | 0.30 | steady self-improvement; rises near a level threshold |
| `court` | 0.25 | ambition/relationship-driven; rises with an open goal |
| `research` | 0.30 | casters only; the archmagist's default alternative to `work` |
| `scheme` | 0.20 | requires a grudge/target; caught-risk suppresses it for the cautious |
| `take_to_adventure` | 0.25 | adventurer-types; a strong pull for `wealth`/`power` at mid-level |
| `relocate` | 0.10 | a survival/opportunity move, normally dominated |
| `retire` | 0.10 floor → spikes on the §4.4 trigger | anti-thrash floor most months |

**Org-leader endgame moves (deliverable (a)).** When a named NPC is an **org leader** *and* their level/means cross an ACKS class-endgame threshold (§2.5), the catalog offers the **founding/expansion action** appropriate to their class — the NPC mirror of design brief §8.6 player-founded factions: a 9th-level cleric builds/extends a fortified church (grows congregants, faction §6.4); a mage extends a sanctum/dungeon (which, per RAW, *lures the rival party* — §8); a thief-boss expands a syndicate into a criminal guild (change-in-management, faction §2.4); a venturer opens a trade route / asserts monopoly (`ax_venturer_class`). **These reduce to the existing domain/org systems that execute them** — this GDD *triggers* them from the personal turn; it does not re-specify stronghold construction, congregation growth, or syndicate management (those are ruler-AI `manage_stronghold`, faction §6, and the syndicate resolver respectively). The personal-turn contribution is: score the endgame move (weighted by `legacy`/`power` + the class's governing weight), and on selection **invoke the owning system's entry point keyed on `character_id`**, exactly as ruler-AI §5.2 invokes construction.

### 4.4 Level ceilings, age, and the retire trigger (PROJECT CALL)

- **`train` ceiling:** a named NPC does not out-train the campaign's power band. PROJECT CALL: cap notional advancement at the NPC's generated level +2, or at the class name-level (9th) for non-adventurer townsfolk, whichever is lower; ceilinged NPCs stop scoring `train` and lean `work`/`court`/`research`. (Prevents a backdrop-promoted blacksmith from becoming a 14th-level fighter through idle ticks.)
- **`retire` trigger:** PROJECT CALL — fires as a *spike* on the `retire` base_value when (age past a class/culture threshold from `acore_aging_poisons…`) **AND** (`legacy` or `security` motivation) **AND** (a completed life-goal *or* low remaining ambition — e.g., at the level ceiling with `power` motivation satisfied). A retired NPC persists as a social/quest presence (§10) and is the natural succession seam (§13). This is intentionally conservative in v1 — retirement should be rare and legible, not a demographic churn.

### 4.5 The three-layer de-duplication rule (prevents "acting twice")

Because a single NPC may be a ruler *and* an org leader *and* an individual, the fixed tick order (§3.2) plus this rule keeps the layers from double-counting:

- **Ruler action pre-empts the equivalent personal action.** If `RulerAI` already had this NPC take a domain action this month, the personal catalog **suppresses** any personal action that would reduce to the *same* underlying operation (a ruler who `manage_stronghold`ed does not also personally "found a castle"; a ruler who administered does not also personally `work`). Detection: the personal catalog reads this tick's `ruler_action_taken` for the NPC and drops overlapping candidates.
- **Org action pre-empts the equivalent personal action.** If the NPC's org already took the institutional version this month (the syndicate ran a hijink *as the org*; the temple proselytized), the personal `scheme`/endgame candidate that would duplicate it is suppressed. The personal turn is for what the org turn did **not** cover — most importantly the **L9+ individual hijink** (which faction §6.6 explicitly excludes from the org's abstract L0–8 table) and purely personal ambitions (`research`, `court`, `retire`, `take_to_adventure`).
- **What always remains personal:** `work` (unless the NPC is a ruler who administered), `train`, `research`, `court`, `relocate`, `retire`, `take_to_adventure`, and the **L9+ individual hijink** form of `scheme`. These have no ruler/org equivalent and are the personal layer's core value.

---

## 5. Data Model (DESIGN ONLY — Layer-3, requires approval before migration)

**Approval status: NOT APPROVED — this section is design-only.** Per CLAUDE.md/design-brief §3.2, Layer-3 data-model additions require Jedidiah's explicit approval before any migration is written (flagged in §13). Existing tables are extended additively; nothing is renamed. SQLite is ground truth; migrations sequential, versioned, non-destructive; banker's rounding wherever a value rounds. The proposal deliberately mirrors the approved `ruler_dispositions` / `ruler_ai_state` shape (ruler-AI §10) so the review is a small delta, not a new pattern.

### 5.1 `characters` — extend (additive columns) OR a sidecar table

Two options; recommend **Option B** (sidecar) to match the ruler precedent's queryability rationale.

- **Option A (columns on `characters`):** add `agency_activity TEXT` (current activity id / `retired` / null), `apparent_rank INTEGER` (the §6.5 treatment tier), `home_settlement_id TEXT`, `home_poi_id TEXT`. Cheap but pollutes the wide character row.
- **Option B (recommended): `npc_agency_state`** (one row per active-agency named NPC, keyed by `character_id`), paralleling `ruler_ai_state`:

```
npc_agency_state(
  campaign_id, character_id,               -- PK (campaign_id, character_id)
  lod_tier            TEXT NOT NULL DEFAULT 'backdrop',   -- 'active' | 'backdrop'
  last_agency_turn_day INTEGER NOT NULL DEFAULT 0,
  current_activity    TEXT NULL,            -- action id from §4.1, or 'retired', or NULL (idle)
  activity_target     TEXT NULL,            -- JSON: research spell/level, court target id, scheme target, dungeon id
  activity_progress   TEXT NULL,            -- JSON: multi-month progress (research weeks done, influence steps, party expedition state)
  home_settlement_id  TEXT NULL,
  home_poi_id         TEXT NULL,
  apparent_rank       INTEGER NOT NULL DEFAULT 0,   -- §6.5 sustained-spend treatment tier (level-equivalent)
  last_action_id      TEXT NULL,            -- for narration de-dup + save/load reconciliation
  narration_cache     TEXT NULL             -- optional small cache (avoid re-narrating), like ruler_ai_state
)
```

`StrategicDisposition` is **not** duplicated here — it is regenerable from `characters.personality` + alignment via `StrategicDispositionBuilder` (ruler-AI §4), and where the NPC is also a ruler it already lives in `ruler_dispositions`. For non-ruler named NPCs that need a cached disposition, reuse `ruler_dispositions` **renamed-in-spirit** is rejected (name says "ruler"); instead cache lazily in memory per active turn, or (if profiling demands persistence) add a general `npc_dispositions` table with the same 7-axis+8-weight+crisis shape. **Flag for Jedidiah (§13):** whether to generalize `ruler_dispositions` → `npc_dispositions` (a rename touching ruler-AI's approved table — needs approval) or keep a parallel table.

### 5.2 `npc_purse_ledger` — new (the personal-purse audit trail, §6)

Append-only monthly settlement rows, so a spend-audit is a legitimate spying finding (faction §8.7) and the apparent-rank derivation is reconstructible:

```
npc_purse_ledger(
  id, campaign_id, character_id, day,
  income_gp          INTEGER NOT NULL DEFAULT 0,   -- occupation/work/hijink/research-sale income this month
  living_expense_gp  INTEGER NOT NULL DEFAULT 0,   -- what was actually paid as living expenses (§6.5)
  discretionary_gp   INTEGER NOT NULL DEFAULT 0,   -- research/training/scheme/court spend this month
  balance_gp         INTEGER NOT NULL DEFAULT 0,   -- running purse after settlement
  spend_bracket_level INTEGER NOT NULL DEFAULT 0,  -- the level bracket the sustained spend maps to (§6.5)
  source_summary     TEXT NOT NULL DEFAULT ''      -- e.g., "work:sage 500; research:-2000; living:-400"
)
```

The purse **balance** itself may live as a single `purse_gp` column on `npc_agency_state` (or on `characters`); the ledger is the *decayed-window* history the §6.5 sustained-spend average reads (suggest a 3-month rolling window). **Alternative considered:** fold the purse into the org treasury for org leaders — rejected; a leader's *personal* purse (which pays *their* living expenses and funds *their* research) is distinct from the org's `treasury_gp` (faction §4.1), exactly as a ruler's personal wealth is distinct from domain revenue.

### 5.3 `npc_parties` + `npc_party_members` — new (deliverable (d), §8)

A persisting NPC adventuring party is an **agent** with a position, a target, and a roster. It reuses the `factions` registry for its *stances/parent* (faction §6.1 `adventuring_party` type, `warband` scope, faction §9 links) but needs its own **agent state** (where it is, what it is doing):

```
npc_parties(
  id, campaign_id,
  faction_id          TEXT NULL,            -- the adventuring_party/warband faction row (faction §6.1); NULL until promoted
  origin              TEXT NOT NULL,        -- 'wandering_slot' | 'mage_dungeon_lure' | 'npc_expedition' | 'lair_society'
  founder_character_id TEXT NULL,           -- set when spawned by a take_to_adventure NPC (§4.1)
  base_level          INTEGER NOT NULL,     -- §2.6 base level
  alignment           TEXT NOT NULL,        -- §2.6 single 1d6 party alignment
  goal                TEXT NOT NULL,        -- JSON: target dungeon/lair id, quest ref, 'clear'|'raid'|'escort'
  posture             TEXT NOT NULL DEFAULT 'traveling',  -- 'traveling'|'delving'|'returning'|'disbanded'|'defeated'
  position_ref        TEXT NULL,            -- hex/dungeon-cell ref (shares the entity position model, design brief §5)
  spawned_day INTEGER NOT NULL, updated_day INTEGER NOT NULL
)
npc_party_members(
  party_id, character_id,                   -- each member is a Tier-B/C character record (§8.2)
  role TEXT NULL,                           -- 'leader'|'fighter'|'cleric'|'mage'|'thief'
  member_level INTEGER NOT NULL             -- §2.6 per-member 1d6 NPC Level roll result
)
```

Rationale for a dedicated table (not just a `factions` row): a wandering rival party is a **moving entity on the map/dungeon grid** with an expedition state machine (§8.3) — that is agent state, not faction registry data. The `faction_id` link (lazily set) is what gives it stances and a parent (the gnoll band's clanhold, faction §9); the `npc_parties` row is what makes it *go somewhere and do something*.

### 5.4 Touched existing systems (no renames)

- `characters.personality` (existing JSON) — read-only source for `StrategicDisposition`; unchanged.
- `factions` / `faction_memberships` / `faction_stances` (faction §4) — the personal `scheme`/endgame/`court`-a-patron actions **write to these** via the existing faction interfaces (a leader's personal op writes the faction ledger; an NPC founding a church creates a `factions` row). This GDD is a **caller**, not a schema-owner, of the faction tables.
- `reputation_entries` (existing) — an NPC's public personal deeds (a famous rival adventurer, a notorious schemer) may write party-facing reputation via the faction §8.3 propagation path when player-relevant. Caller, not owner.
- `settlement_pois` / dungeon `pois` — an NPC party's `delving` posture reads/writes dungeon occupancy through the **existing** dungeon-factions/stocking interfaces (faction §9, `gdd-dungeon-factions.md`); this GDD adds no dungeon schema.
- `quests` / rumor tables (`gdd-quest-rumor-system.md`, **being spec'd concurrently**) — personal activities emit questgiver-motivation and rumor records through **that** system's writer. **Coupling flag (§10, §12):** the exact table shapes are owned by the quest-rumor GDD; this GDD forward-references its writer and must not assume its final schema.

---

## 6. Personal Purses (deliverable (c))

### 6.1 The monthly settlement (mirrors the specialist/syndicate wage tick)

`PersonalPurseResolver` runs **first** in each active NPC's personal turn (§3.2), before action scoring — income first, then choose within means, exactly the ruler/org post-resolution pattern (faction §6.6). It mirrors two **already-built** ticks: `SpecialistHireManager.process_monthly_wages` (specialists §2.2) and `NpcSyndicateMonthlyResolver` (the L0–8 abstract path). The sequence:

```
1. INCOME    = occupation income (§6.3)  + this month's action income
               (work / L9+ hijink take / research-sale / patron stipend / adventure spoils share)
2. EXPENSES  = living expenses (§6.4)     + discretionary spend committed by the chosen action
               (research 1,000gp/spell level, training cost, scheme cost, court gifts)
3. BALANCE   = prior purse + INCOME − EXPENSES        (banker's rounding; purse may not fund an action it can't afford)
4. APPARENT  = update the sustained-spend bracket (§6.5) from the 3-month living-expense window
5. LEDGER    = append an npc_purse_ledger row (§5.2)
```

**Affordability gate (identical to faction §6.6):** an action is a candidate only if its gp cost ≤ purse + expected income; a purse below a few months' living expenses biases toward `work` and away from `research`/`scheme`/`court` gifts (a §7.2 situational modifier).

### 6.2 Living expenses = the level wage (RAW ruling)

Per `rulings_living_expenses_and_social_status.xml` (§2.1): an NPC's **default living expense = their level-equivalent monthly wage** from the Henchmen Monthly Fee table (`acore_henchmen_monthly_fee_table.xml`). A L5 NPC pays 400gp/month; a L9 archmagist pays 7,250gp/month; a L0 townsperson pays 12gp/month. This is **why faction §6.6's ¼-wages org rule already covers member living costs** — members' wages *are* their living expenses, so the org's net-profit ballpark is genuinely "left over after living." For a named NPC modeled *individually* (not as an abstract org member), the purse pays this explicitly.

### 6.3 Occupation income (the RAW specialist/wage tables)

An NPC's `work` action earns their **occupation income**, sourced RAW-first:

- **If the NPC's role maps to a published specialist** (`acore_equipment.xml:872-992`): use that role's monthly pay — Sage 500, Alchemist 250, Engineer 250, Armorer 75, Animal Trainer 25–250, Ruffian by type (6/25/125), Spellcaster "varies" (by market class + spell level). Availability gating (`:709-728`) determines whether the occupation *exists* in the current settlement; a relocate (§4.1) may follow the market.
- **If the NPC is a leveled earner** (a thief, a mercenary, a leveled ruffian): bridge to the **Henchmen Monthly Fee table** as RAW itself directs for ruffian advancement (`:956` — "if they level up, use the Henchmen Monthly Fee table for higher wages"). This is the general rule: a leveled NPC's earning power tracks the wage table.
- **If the NPC is an org leader:** their *personal* `work` income is modest (their level wage as an earner); the org's income is separate (faction §6.6) and flows to the org treasury, not the personal purse — a high priest's church is rich while he personally lives on his level wage (until he draws a stipend, which *is* personal income).
- **Net-not-gross convention (like the hijink table):** occupation income figures are treated as **net** monthly earnings (the specialist wage *is* what they take home), so no separate business-expense modeling on the happy path — the same simplification faction §6.6 uses. Living expenses are the only standing deduction.

**Design honesty:** RAW prices occupation income *exactly* only for the published specialist roster and the two wage tables. For roles outside the roster (a village elder, a minor noble, a scholar-not-hired-as-a-sage), the purse uses the **level-wage as the earning proxy** (income ≈ level wage, so a self-supporting NPC nets ≈ zero — they earn their keep). This is a PROJECT-CALL ballpark, tunable after testing (§13), and it degrades gracefully: an NPC whose income exactly meets living expenses simply holds a flat purse and mostly `work`s — a stable, boring, correct default.

### 6.4 Backdrop auto-stabilize (mirrors ruler-AI §8.4)

Backdrop named NPCs (outside the active set) do **not** run the purse resolver each month. Instead a cheap deterministic pass assumes **income ≈ living expenses** (they earn their keep), leaves the purse flat, and holds `apparent_rank` at its last value. No discretionary spend, no research, no scheming off-camera. **Player-caused effects still apply** — if the player robbed the NPC or destroyed their livelihood, that is a real purse hit recorded when it happened. A freshly-approached NPC has a coherent purse and rank, not a spuriously churned one.

### 6.5 Apparent social rank from sustained spend (faction §8.7)

Per faction §8.7 and the Judge ruling: **apparent rank = the highest class level whose Henchman Monthly Fee is ≤ the NPC's sustained monthly living expenditure** (3-month rolling average, PROJECT CALL; banker's rounding). Mechanics:

- **NPCs default to spending their level wage** → apparent rank = actual level. The common case is a no-op.
- **Personality colors the exception** (faction §8.7): high `epicureanism` NPCs overspend (apparent > actual — the minor noble who lives like a lord); miserly/`survival` NPCs underspend (apparent < actual). A **covert L9 syndicate boss deliberately living at L2 spend** is now mechanically expressible — and a **spend-audit is a legitimate `scheme:spy` finding** (faction §8.7, §7.4): the discrepancy between apparent rank and true level *is* the secret worth stealing.
- **What consumes it:** `apparent_rank` is the treatment tier fed to the dialogue status-differential (`gdd-npc-dialogue.md` §6.5: −1 per tier the NPC outranks the speaker, +1/+2 when outranking), to org petition reactions (faction §8.1), and to any Axioms interaction where standing matters. **Titles/offices/authority remain separate known facts** with their own modifiers (`ax_reactions_and_influencing.xml` authority ±2) — spend governs *perceived station*, not legal rank (faction §8.7).

The player-side per-character living-standard setting (faction §8.7 UI note) is **out of scope here** — it belongs to the party/character tab GDD; until built, PCs itemize per RAW and PC apparent rank defaults to actual level. This GDD owns only the **NPC** side of the purse.

---

## 7. The Scoring Algorithm (generalizing personality §8.5 from rulers to all named NPCs)

### 7.1 The loop (identical to ruler-AI §6.1, non-domain action space)

For each active-LOD named NPC, once per monthly turn, **after** the purse settles (§6):

```
1. candidates = PersonalActionCatalog.available_for(npc, world_state)   # precondition-gated (§4.1)
                minus de-dup suppressions (§4.5: ruler/org pre-emption)
2. for each action a:
     utility(a) = base_value(a) * relevant_weight(a, disposition) * Π situational_modifier_i(a, npc, world)
3. apply crisis bias if the NPC faces a personal threat (danger → relocate/retire/scheme-defense)   # §7.3
4. pick argmax(utility)   # ONE personal action; no top-N (a person does one thing, unlike a large realm)
5. execute deterministically via the mapped mechanic (§4.1); commit purse spend (§6); no LLM call
6. emit npc_agency_action_taken(...); narrate retroactively only if player-relevant (§9)
```

The scorer is `PersonalActionScorer`, structurally the same class family as `RulerActionScorer`; the only differences from ruler scoring are the **action space** (personal, §4.1, not domain) and the **single-pick** (a person takes one action; ruler-AI's top-2/3 for large realms does not apply — §4.1). Tie-break: per-(NPC, calendar_month) seeded RNG. Banker's rounding.

### 7.2 Situational modifier tables (PROJECT CALL — tunable)

Multiplicative modifiers (1.0 = neutral), mirroring ruler-AI §6.2's shape:

**Purse state** (the affordability pressure):

| Purse vs. living expenses | work | research/scheme (costly) | court (gifts) | train | relocate |
|---|---|---|---|---|---|
| < 1 month (broke) | 1.8 | 0.3 | 0.4 | 0.6 | 1.4 |
| 1–3 months (tight) | 1.3 | 0.7 | 0.8 | 0.9 | 1.0 |
| 3–12 months (comfortable) | 1.0 | 1.2 | 1.1 | 1.1 | 0.8 |
| > 12 months (rich) | 0.7 | 1.4 | 1.2 | 1.2 | 0.6 |

**Occupation viability** (market-class availability, `:709-728`): occupation absent in current settlement → `work` ×0.3 and `relocate` ×1.6 (follow the market).

**Open goal present:** an unresolved courtship/patron/mentor target → `court` ×1.5; a `rival`/`enemy` relationship or a live faction grievance → `scheme` ×1.5; a reachable dungeon/lair matching the NPC's motivation → `take_to_adventure` ×1.5.

**Level threshold:** within ~10% of the next level (and below the §4.4 ceiling) → `train` ×1.4; at the ceiling → `train` ×0.2.

**Personal threat** (a `scheme` aimed at this NPC discovered; the player hunting them; their settlement at war): defensive/flight actions (`relocate`, defensive `scheme`, `retire`) ×1.5–2.5 and `crisis_response` bias applies (§7.3); costly self-investment (`research`) ×0.5.

**Age/lifecycle:** past the §4.4 age threshold with `legacy`/`security` motivation → `retire` spikes; young + `power`/`wealth` → `take_to_adventure`/`train` favored.

### 7.3 Personal crisis response (reuse the ruler `crisis_response` category)

The NPC's `crisis_response` (personality §8.4, already in `StrategicDisposition`) biases the response to a **personal** threat, exactly as ruler-AI §7.1 biases the domain response — same four categories, personal-scale expression:

| crisis_response | Personal-threat expression |
|---|---|
| `aggressive` | Strikes first: `scheme` against the threat (hire a syndicate, personal hijink), confronts rather than flees. |
| `defensive` | Fortifies: stays put, draws on faction/patron protection, hoards purse; relocates only from strength. |
| `cautious` | Over-prepares/flees early: `relocate` before the threat lands; hoards; withdraws to a patron's seat. |
| `diplomatic` | Negotiates: `court` the threatening party or a protector; buys off; appeases where survivable (degrades to `cautious` if no diplomacy path). |

### 7.4 Worked example (illustrative, deterministic)

**The archmagist Veyra** — L11 mage, leads the Cyfaraun mages' guild (an active-LOD org); Motivation `knowledge`/`power`; axes: epistemic_curiosity 9, self_interest 4, in_group_loyalty 5, affective_compassion 4, stress_reactivity 3. Her `StrategicDisposition` (via the shared builder) yields high `research_weight`, moderate `diplomatic_weight`, `crisis_response = "diplomatic"` (unflappable + opportunistic). Purse: comfortable (guild stipend + level wage; ~8 months' living expenses of 32,000gp/month).

This month: her **org turn** (FactionAI, §3.2 step 4) already had the guild `raise_funds` (scribing commissions). Her **personal turn** (step 5) then runs:

- De-dup (§4.5): the org's `raise_funds` does not overlap any personal action → nothing suppressed.
- Purse settles (§6): income (stipend + fees) > living expenses → comfortable; `apparent_rank` = 11 (she spends her wage).
- Candidates: `research` (she can still learn L6 spells; has a guild library +2 on the throw), `work`, `court` (no open patron goal), `train` (near L12 threshold), `scheme` (no grudge → precondition fails, dropped).
- Scores: `research` = 0.30 × high research_weight × 1.2 (comfortable purse) × (library-bonus flavor) **dominates**; `train` = 0.30 × military/research weight × 1.4 (threshold) trails; `work` = 0.45 × economic_weight × 1.0 (she doesn't need the money) below.
- **Result:** Veyra commits `research` — 1,000gp × 6 = 6,000gp and 12 weeks toward a L6 spell, throw vs. her Magic Research Target +2 (library). The purse debits 6,000gp; `activity_progress` records 12 weeks (spanning ~3 monthly turns). `npc_agency_action_taken(veyra, "research", {spell_level:6, ...})` fires; if the party is her guild-brother, dialogue can now say "the Archmagist is sequestered with a new working" (§10), and success may seed a rumor/quest ("Veyra seeks a rare reagent" — quest-rumor coupling, §10).

Every beat is a table lookup, a weight product, or a RAW throw — and every beat is narratable. This is the ruler-AI §6.3 worked-example pattern, at personal scale.

---

## 8. NPC Adventuring Parties as Spawned Agents (deliverable (d))

### 8.1 The three origins

A persisting NPC party — "the rival party clearing *your* dungeon" — arises three ways, each RAW-anchored:

1. **The wandering slot persists (§2.6, `:69`).** An NPC-party wandering encounter (1d4+2, one 1d6 alignment, base level by context) that the players do **not** wipe, and that has somewhere to be going, is promoted from a transient encounter to a persisting `npc_parties` agent instead of despawning.
2. **The mage-dungeon lure (RAW).** A mage who builds a dungeon to attract monsters *also* attracts, on the relevant wandering result, **rival adventuring parties that arrive to clear it** (`acore-campaign-hijinks.xml:531-611`; faction §2.6). When a mage's dungeon (NPC-owned, possibly the players' own eventual sanctum's neighbor) rolls that result, spawn an NPC party targeting it. This is the archetypal "someone else is delving the same hole."
3. **An NPC `take_to_adventure`s (§4.1).** A named adventurer-NPC's personal action assembles companions (henchman/loyalty engine, §2.7) and mounts an expedition — spawning a party the NPC **founds and leads** (`founder_character_id` set), targeting a dungeon/lair/quest that matches their motivation.

### 8.2 Composition (RAW, `acore-monster-stocking-rules.xml:446-524`)

On spawn, build the roster per RAW (§2.6): roll **1d4+2** members (or 1d4+3 at high level), roll **1d6 once** for party alignment, set **base level** by context (settlement 7−MC / wilderness nearest-dungeon-max / dungeon level), roll **1d6 per member** on the NPC Level table for each member's level. Members are generated as **Tier-B/C character records** (the `ClassedNpcBuilder` Tier-B path already used by settlement stocking and dungeon-faction leaders, personality §10.1) with class mix appropriate to an adventuring party (a fighter, a cleric, a mage, a thief is the archetypal spread — PROJECT CALL weighting). The **leader** is Tier-B+ (or the founding Tier-A NPC in origin 3) and carries the party's motivation/goal; rank-and-file may stay Tier-C until the players actually fight or parley them (stock-on-contact, design brief §12.4).

### 8.3 The expedition state machine (`posture`)

An NPC party is a **moving entity** on the shared position model (design brief §5), driven by the **self-paced scheduler event** (§3.3) so it moves on the wilderness/dungeon clock, not month-granularity (a dungeon race must *feel* like a race):

```
traveling  → moves toward its goal dungeon/lair (wilderness hex movement; may itself trigger encounters)
delving    → occupies the target dungeon; draws down its stock via the EXISTING dungeon-factions/stocking
             interfaces (faction §9; gdd-dungeon-factions §6) — it clears rooms, fights the residents,
             takes treasure; the dungeon the players arrive at is genuinely emptier
returning  → withdraws with spoils (treasure by RAW party level); may deposit to a home settlement
defeated   → wiped (by the dungeon, by another party, or by the players); roster deaths persist
disbanded  → goal complete or leader lost; members disperse (some may persist as named NPCs — design brief §10.5
             departure pattern; a survivor with a grudge is a future quest hook)
```

**Interaction with the players is the payoff.** The players may **race** it (arrive first), **fight** it (a hostile rival party — reaction roll from the party's alignment/stance, faction §8.5), **parley/ally** with it (a friendly party — shared-dungeon etiquette), **hire** its leader, or **find its aftermath** (an emptied dungeon, a note, corpses if the dungeon won). All of these are existing surfaces (combat, dialogue, dungeon exploration); this GDD only makes the party a real agent that *got there and did something*.

### 8.4 Determinism, LOD, and the director cap

- **Determinism:** the whole lifecycle (spawn roster, movement path, delve draw-down, spoils) is seeded and replayable (§12).
- **LOD:** NPC parties are agents in the active set (§3.4) — spawned/moved only within the active-LOD band + a small buffer so a race is visible; a party that leaves the band is frozen (posture held) until the player nears again, mirroring backdrop auto-stabilize. Backdrop dungeons are not being drained off-camera by phantom parties (drama stays player-proximate).
- **Director cap (PROJECT CALL, mirrors faction §11.3):** ≤ 1–2 active rival parties targeting player-relevant dungeons per region at a time (a second queues). Legibility over noise — one rival party racing you is a story; five is chaos.
- **Faction §9 metadata:** a persisting party's *stances and parent* (the gnoll band answers to a clanhold; the human rivals belong to a syndicate) are set via the **existing** faction §9 link generation (LINK_RANGE 4 six-mile hexes); this GDD's `npc_parties` row carries the *agent* state and points at the `faction_id`. The two are complementary, not duplicative (§5.3).

---

## 9. Determinative-AI → LLM Contract (Seam A only; clone, don't design)

The personal layer is **fully functional with the mock provider** (`LLMManager` is a stub returning `ResponseEnvelope.fallback(...)`; `is_configured()` false). The LLM is optional polish on top of deterministic decisions. There is **one** seam:

### 9.1 Seam A — retroactive personal-action narration

`PersonalActionNarrator` is a **clone of `RulerActionNarrator`** (ruler-AI §9.1), exactly as faction's `FactionActionNarrator` is (faction §10.1) — no new LLM architecture per consumer. When the player observes/interacts with a personal-action outcome (talks to the NPC, witnesses the rival party, hears the rumor), it assembles a context Dictionary and calls the existing narration path against `generate()` + the `task_profiles.json` contract (the master plan §3 task-type registry):

```
{
  task_type: "npc_agency_action_narration",       # a new task-profile row (clone of ruler_action_narration)
  npc_id, realm_name_or_settlement,
  personality_summary, speech_notes,               # cached at creation (personality §9.2)
  disposition_directives: [ ... ],                 # surviving 1-3/8-10 axis directives (personality §9.1 filter)
  action_id, action_outcome: { ... },               # the structured deterministic result
  motivation_primary, motivation_secondary,
  disposition_toward_player, disposition_trend
}
```

If `is_configured()` is false (always, today) the narrator returns the **deterministic template** for that `action_id` (the mock compositional-flavor / fragment-bank path, personality §9.3). The engine has already decided and executed; narration is cosmetic and `is_fallback`-safe. **Relevance gate (the anti-spam rule the ruler seam proved):** only active-LOD NPCs with player awareness (met, same settlement, or party-instantiated stance/membership) reach the log — an off-screen scholar's research throw never spams the UnifiedLog.

### 9.2 No Seam B

Unlike rulers (Seam B strategy reassessment) and factions (bounded reassessment suggestions), the personal layer defines **no** LLM-into-scoring seam in v1. A person's monthly choice is simpler than a realm's strategy; the deterministic scorer suffices and the mock parity is cleaner. (A future Seam-B-style "the NPC reconsiders their life after the players upend it" is a tunable extension, §13 — but v1 keeps the personal scorer purely deterministic.)

---

## 10. Surfacing: Dialogue and Quest/Rumor Feeds (deliverable (e))

This is the payoff — the whole reason the personal layer exists is to make the two player-facing systems richer. **Coupling flag:** the quest-rumor system ([gdd-quest-rumor-system.md](gdd-quest-rumor-system.md)) is **being spec'd concurrently** (master plan §6 gap #1 — the stack's long pole); this GDD forward-references its writer and does **not** assume its final table shapes. Where this GDD says "emit a rumor/quest," it means "call the quest-rumor writer with source_type `npc`/`faction` and a motivation payload," per whatever interface that GDD finalizes. Flagged again in §12.

### 10.1 Dialogue — "what is this NPC up to?"

[gdd-npc-dialogue.md]'s context assembly gains two fields from this layer, populating the NPC context package (personality §9.2 runtime assembly) and the dialogue prompt:

```
agency_context: {
  current_activity: "researching a new spell" | "away on an expedition" | "courting the Countess"
                    | "retired to his vineyard" | null,     # engine-chosen from current_activity (§5.1)
  motivation_hooks: [ "seeks a rare reagent", "wants the guild seat", "hunting the man who killed his brother" ],
                    # what the NPC WANTS that the party could help/hinder (from Motivation + activity_target)
}
```

- `current_activity` is a **plain-language rendering of the NPC's actual chosen action** (§4.1) — so when the players ask the tavernkeeper about the archmagist, dialogue can truthfully say she's sequestered with a new working, because she *is* (`research`, §7.4). This is the literal answer to "what is this NPC up to?"
- `motivation_hooks` are the questgiver seeds (below), surfaced in conversation as the NPC's wants — the exact "motivation hooks" personality §9.2 already reserves, now *populated by real activity* instead of static generation.
- The LLM never invents the activity; it narrates the engine-provided fact (design brief: engine decides, LLM narrates). No secret is leaked — `current_activity` is public-behavior color; a *covert* `scheme` renders as a bland cover activity, and the true scheme is discoverable only through the faction §7.4 secrecy channels (spend-audit, spying, a Grudging leak), never through this block.

### 10.2 Quest & Rumor — questgiver motivation and NPC-sourced news

Personal turns are a **rumor and quest engine** (deliverable (e)):

- **Questgiver motivation (the core value to quest-rumor).** An NPC's Motivation + current activity_target is exactly what quest-rumor needs to make an org/NPC's job offer *mean something*: the `revenge`-motivated exile offers an assassination job because he is *actually* scheming against his enemy (§4.1 `scheme`); the `knowledge`-motivated archmagist offers a fetch-the-reagent quest because she is *actually* mid-research (§7.4). This GDD provides the **motivation + live goal**; quest-rumor turns it into a scaled, tracked quest. This is what faction §13 means by "gives questgivers real motivation."
- **Rumor emission.** Notable personal beats emit rumor records through the quest-rumor pipeline (source_type `npc` or, for org endgame moves, `faction`) with the accuracy tiers that GDD defines (true/exaggerated/misleading/false): "the old captain is hiring for a delve" (`take_to_adventure`), "a rival band beat you to the Barrow" (an NPC party's `delving`, §8), "the priest is building something grand" (a cleric's church endgame, §4.3). Venturer-pattern rumormongering (faction §2.6) makes venturer NPCs premium rumor sources.
- **The NPC party as a quest surface.** A rival party clearing a dungeon (§8) is simultaneously a rumor (news of the race), a potential quest (beat them / recover what they took / rescue their survivors), and an encounter — all through existing systems, seeded by this layer's spawn.

### 10.3 What this layer explicitly does NOT surface

- **No Tier C activity** (§1.4) — a transient guard has no `current_activity` and seeds no motivation quest.
- **No hidden data to the LLM** — covert schemes never enter dialogue/rumor as truth; discovery is the faction §7.4 machinery's job (this GDD *creates* the covert scheme via `scheme`; faction owns its *concealment*).
- **No player micromanagement UI** — the player never sees or sets an NPC's monthly action; they experience it through dialogue, rumors, quests, and encounters only.

---

## 11. Scheduling, LOD, Performance, and Feasibility

### 11.1 Cadences

| What | When | Cost shape |
|---|---|---|
| Personal turns (the 8-action vocabulary) | monthly tick, after the faction-turn slot (§3.2 step 5) | O(active named NPCs) scoring — dozens, not thousands |
| Purse settlement | inside each active NPC's personal turn (income-first) | O(active named NPCs) — arithmetic + one ledger row |
| Backdrop purse auto-stabilize | monthly, cheap pass | O(backdrop named NPCs) but constant-time each (assume income≈expenses) |
| NPC-party movement / delve | self-paced scheduler event (§3.3), active band only | O(active parties) — capped at 1–2 per region (§8.4) |
| Apparent-rank recompute | inside purse settlement (3-month window read) | O(1) per NPC |
| Seam-A narration | on player observation only, relevance-gated | O(player-relevant events) — near-zero off-screen |

### 11.2 LOD inheritance (no new policy — §3.4)

The layer holds **zero** independent LOD policy: `NpcAgencyLodManager` is an adapter over the ruler active set (ruler-AI §8), exactly as faction §11.2 inherits it. Active = named NPCs in the 6-mile window + 10-hex buffer, plus interaction/conflict participants, plus active-org leaders and party-instantiated NPCs. Backdrop = everyone else (no turns, purses auto-stabilized). Promotion-on-approach builds the disposition lazily and resumes from the stable baseline. The M5-style widening is forward-compatible (same scorer, bigger active set) and is the declared v2 path.

### 11.3 Feasibility honesty (what this app will not do)

- **No per-townsperson simulation.** Agency is **named-NPC-level and active-LOD-gated** — dozens of NPCs near the player, not a settlement's full census. A Market Class III city may have 30–50 named NPCs (personality §10.2), of which only those in the active band take personal turns.
- **No LLM-driven lives.** Latency, cost, determinism, and mock-parity forbid it (faction §11.5). The LLM narrates and colors dialogue; it never chooses a life.
- **No off-camera drama churn.** Distant NPCs are stable backdrop (purse flat, no schemes); the design makes that a feature (coherent on approach) rather than a lie (frozen mid-scheme) — the ruler-AI §8.4 stance, applied to persons.
- **Scale envelope:** ~20–60 active named NPCs per region set at any time (the subset of the settlement's 30–50 that are in-band + relevant), ~1–2 active rival parties. Monthly personal-turn cost is comparable to the existing syndicate/ruler/faction resolvers — SQLite rows and arithmetic, one dungeon-draw-down per active party, no new pathfinding beyond the party movement the scheduler already supports. Comfortably within budget.

### 11.4 Audit instrumentation (dev-facing, behind the existing political-audit flag)

Reuse the faction §11.7 `debug_political_audit` infrastructure — no new logging system. Every `PersonalActionScorer` and `PersonalPurseResolver` evaluation writes a term-breakdown record (candidates, each utility term, purse state, RNG seed/draws, chosen action) to the same `political_audit` JSONL log; the Judge-mode audit panel gains a filter for personal turns; tuning counters add per-game-year stats (actions chosen by type, retirements, parties spawned/defeated, apparent-rank deviations). The determinism harness (faction §11.7) extends to cover personal turns: replaying a seed reproduces a byte-identical personal-turn audit stream — the log is the regression oracle.

---

## 12. Test Plan

Hand-authored scenarios before any procedural content (CLAUDE.md). Mock provider only, deterministic seeds.

**Unit:**
- `PersonalActionScorer` reuses `StrategicDispositionBuilder` and reproduces a golden personal-turn choice for a fixed (NPC, world, seed) — and is byte-identical across reruns.
- De-dup rule (§4.5): an NPC who took a ruler action this tick has the overlapping personal candidate suppressed; an org leader whose org ran a hijink has the duplicate `scheme` suppressed but retains the L9+ *individual* hijink; `research`/`court`/`retire` are never suppressed.
- Purse settlement (§6): income (specialist-wage occupation) − living expenses (level wage) → correct balance; banker's rounding on every division; a broke purse gates out `research`/costly `scheme`.
- Apparent rank (§6.5): default spender → apparent = actual; a scripted L9 boss living at L2 spend → apparent rank 2 (the spend-audit target); a high-`epicureanism` minor noble → apparent > actual. 3-month rolling window arithmetic correct.
- L9+ individual hijink (§2.3): a L10 boss `scheme`s → an *individual* hijink throw (not the L0–8 abstract table); caught-by-14+/nat-1 → Crime & Punishment path; the L8 member stays on the abstract table (faction §6.6 boundary preserved).
- Magic research (§2.4): a caster `research`es → 1,000gp + 2 weeks per spell level debited/scheduled; throw vs. the Magic Research Target with the +1/10,000gp library bonus capped at +3; multi-month progress persists in `activity_progress`.
- `train` ceiling (§4.4): a ceilinged NPC stops scoring `train`; a below-threshold one favors it.
- Crisis response (§7.3): the 4-category personal-threat mapping (stress_reactivity × self_interest boundaries) picks the right defensive/flight action.
- LOD (§3.4): a backdrop NPC takes no personal turn and its purse auto-stabilizes flat; a player-robbed backdrop NPC still shows the real purse hit; the buffer never promotes a `named`/lazy NPC (materialization-safety).

**Integration (hand-authored settlement + NPCs + a dungeon):**
- The Veyra scenario (§7.4) as a scripted month sequence: org turn runs, personal turn runs after it, `research` selected, purse debited, `npc_agency_action_taken` fires, dialogue `current_activity` reflects it, a reagent quest seeds via the quest-rumor writer; identical seed twice → byte-identical event stream.
- An NPC `take_to_adventure`s: recruits via the henchman/loyalty engine, spawns an `npc_parties` agent (RAW composition — 1d4+2, 1d6 alignment, base level, per-member 1d6 level), travels to and `delving`s a hand-authored dungeon, draws down its stock via the existing dungeon interfaces; the players arriving later find it emptier; racing the players → arrival-order resolves on the shared clock.
- A rival party from the mage-dungeon lure (§8.1 origin 2): spawns on the RAW wandering result, targets the mage's dungeon, and is discoverable as an encounter, a rumor, and a quest — all through existing systems.
- Three-layer batch over a mixed region: a ruler-who-leads-an-org-and-researches takes exactly one action per layer (domain, org, personal) with correct de-dup; a plain townsperson only `work`s; a schemer runs an individual hijink; no `auto_pause`, no LLM.
- Surfacing (§10): dialogue `agency_context` renders the true activity for a public action and a bland cover for a covert `scheme` (grep-proof: no covert `activity_target` secret ever enters a dialogue prompt payload); rumor/quest emission calls the quest-rumor writer with the right source_type + motivation payload.
- Narration: with the stub, `npc_agency_action_taken` produces a deterministic `is_fallback` template; no crash, no variance; off-screen NPCs never reach the log (relevance gate).

**Coupling regression:** because quest-rumor is spec'd concurrently, the integration tests that touch it (§10.2) run against a **mock quest-rumor writer** with the minimal interface this GDD forward-references (a `seed_quest_from_motivation(npc_id, motivation, target)` and a `emit_rumor(source_type, text, accuracy)` shape); when the real system lands, these swap to the real writer — flagged so the seam is verified, not assumed.

---

## 13. Build Phasing and Dependencies

Slots **after FF-2** (faction §13; master plan §6 gap #2). **Not a v1 faction blocker** — org-level agency suffices for faction v1; this layer is what makes "what is this NPC up to?" answerable and gives questgivers real motivation. Cross-references the **concurrently-spec'd** quest-rumor system; the coupling is a real scheduling constraint (§10, §12).

| Phase | Delivers | Hard deps | Mock? | Model |
|---|---|---|---|---|
| **NA-0 — Disposition reuse + purse foundation** | Confirm `StrategicDispositionBuilder` is callable for non-ruler NPCs (it is — ruler-AI §4 built it); `PersonalPurseResolver` (§6) — occupation income (specialist/wage tables), living expenses (level wage), apparent rank (§6.5), the `npc_purse_ledger`; backdrop auto-stabilize | `StrategicDispositionBuilder` (built, ruler-AI §4); specialist wage data (built, `gdd-specialists.md`); the wage-table JSON (present); **§5 schema approval** | yes | Sonnet |
| **NA-1 — The personal scorer + core vocabulary** | `NpcAgencyAI.process_campaign_month`; `PersonalActionCatalog` + `PersonalActionScorer` (reused shape); the tick hook after the faction slot (§3.2); the de-dup rule (§4.5); `work`/`train`/`research`/`court`/`relocate`/`retire`; LOD adapter over the ruler active set | NA-0; **FF-2 built** (org turns + the leader-personal seam faction §6.6 reserves); ruler-AI (built) | yes | **Opus**-leaning (three-layer de-dup + scorer adaptation is cross-subsystem) |
| **NA-2 — Leader personal actions + `scheme`** | L9+ individual hijink (§2.3); org-leader endgame moves (§4.3, invoking the owning domain/org systems); `scheme` (personal op / for-hire) writing the faction ledger | NA-1; **FF-2** (org registry/ledger); faction §6.7 op menu (FF-4 for the full menu — v1 uses the six core hijinks + spy/sabotage/slander) | yes | Opus (RAW hijink + endgame interactions) then Sonnet |
| **NA-3 — NPC adventuring parties as agents** | `NpcPartyLifecycle`; `npc_parties`/`npc_party_members`; the three origins (§8.1); RAW composition (§8.2); the expedition state machine (§8.3) on the self-paced event; dungeon draw-down via existing interfaces; director cap | NA-1; the dungeon-factions/stocking interfaces (**dungeon-factions is a gap** — master plan §6 gap #4; the draw-down needs it, so NA-3 is gated on dungeon-factions shipping, like FF-5); `gdd-dungeon-contiguous-3d.md` (position model) | yes | Sonnet |
| **NA-4 — Surfacing wiring** | Dialogue `agency_context` block (§10.1); quest-rumor questgiver-motivation + rumor emission (§10.2); Seam-A `PersonalActionNarrator` clone (§9) + its `task_profiles.json` row | NA-1 (activities to surface); **quest-rumor built** (the long pole — master plan §6 gap #1); dialogue Phase 2/3; Live LLM L-1 for the narrator skin (mock-fine without it) | yes (narrator skin needs Live LLM) | Sonnet |

**Dependency notes and the coupling flag:**

- **After FF-2, not before.** NA-1 needs the org-turn slot and the faction §6.6 "named L9+ members resolve individually" seam to exist so the personal turn can attach beside it and the de-dup rule (§4.5) has an org action to de-dup against. Until FF-2, faction leaders act only through org turns (their ambitions surface as org `goal_primary` bias — faction §6.3), which is exactly the interim faction §13 describes.
- **Quest-rumor coupling (flagged, master plan §6 gap #1).** NA-4's *value* (questgiver motivation, rumor emission) hard-depends on the quest-rumor system, which is designed-only, has no build plan, and whose seeding is a no-op stub. NA-0→NA-3 deliver the *engine* (NPCs actually do things, purses settle, parties delve) on the mock with **no** quest-rumor dependency; NA-4 is the thin surfacing rider that lands when quest-rumor lands. **Because quest-rumor is being spec'd concurrently, this GDD forward-references its writer (§10.2, §12) and must not assume its schema** — when both mature, reconcile the `seed_quest_from_motivation` / `emit_rumor` interface in a small joint pass. This is the single scheduling coupling to watch.
- **NA-3 gated on dungeon-factions (gap, master plan §6 gap #4).** The rival party's dungeon draw-down (§8.3) reuses the dungeon-factions/stocking interfaces, which are unbuilt — so NA-3 defers behind dungeon-factions exactly as faction FF-5 does. NA-0→NA-2 (personal turns, purses, leader actions) do **not** need it and can ship first.
- **Live LLM only skins NA-4.** Everything except the Seam-A narration flavor runs on the mock (the faction/ruler pattern); the narrator is a clone against the same `generate()` + task-profile contract, no new LLM design.

---

## 14. Open Questions / Rulings Needed from Jedidiah

1. **§5 data model approval (Layer 3) — NOT YET APPROVED.** This GDD leaves the schema **design-only**. Needed before any migration: (a) confirm the **`npc_agency_state` sidecar** (§5.1 Option B) vs. columns on `characters` (Option A); (b) confirm **`npc_purse_ledger`** (§5.2) and whether the purse balance lives on the sidecar or on `characters`; (c) confirm **`npc_parties` / `npc_party_members`** (§5.3); (d) **the disposition-caching decision** — generalize the approved `ruler_dispositions` → `npc_dispositions` (a rename touching ruler-AI's approved table, needs approval), keep a parallel `npc_dispositions`, or cache in-memory per active turn only. Recommendation: sidecar + ledger + `npc_parties`, and in-memory disposition caching in v1 (no new table) with `npc_dispositions` deferred until profiling demands it.

2. **Occupation-income proxy for non-roster roles (§6.3) — RULING NEEDED.** RAW prices occupation income exactly only for the published specialist roster and the two wage tables. For roles outside the roster (village elder, minor noble, unhired scholar), this GDD proposes **income ≈ level wage** (self-supporting, nets ≈ zero). Confirm this ballpark, or supply a preferred model (e.g., a role→income table you'd author, or a domain-income share for landed-but-not-ruling nobles). This is the one place the purse leans hardest on a PROJECT-CALL proxy.

3. **The `train` level ceiling and `retire` trigger (§4.4) — TUNING RULING.** Both are PROJECT CALL. Confirm: (a) the `train` ceiling (proposed: generated level +2, or class name-level for townsfolk, whichever lower — prevents idle backdrop-promotion inflation); (b) the `retire` trigger conditions (age + `legacy`/`security` + completed-goal/low-ambition) and how *rare* retirement should be in v1. Retirement is also the succession seam — confirm it should merely set a state now and leave heirs to `gdd-dynasties.md`.

4. **`scheme` scope in v1 (§4.1, §2.3) — CONFIRM the boundary.** v1 personal `scheme` = the **six core hijinks** (individual roll for L9+) + the faction §6.7 op menu (spy/sabotage/slander) run as a 1st-level thief or via the for-hire market. The **Axioms extra hijinks** (arson, subversion, disinforming, infiltration…) lack civilian resolution text in the corpus (faction §14.2). Confirm v1 ships the core set only, and that extending it waits on rule extraction or a further ruling (same posture as faction §6.7).

5. **NPC magic research realism (§2.4) — CONFIRM base-only.** v1 personal `research` uses the **base** RAW procedure (1,000gp + 2 weeks/level, throw vs. target, library bonus). Confirm we do **not** model experimentation (the throw-bonus-with-mishap path, `pc_magic_experimentation.xml`) for NPCs in v1 — mishaps that destroy an NPC's repertoire off-screen are drama the player never sees, so it may be noise. Flag if you'd want it later as a rumor source ("the archmage's tower exploded").

6. **NPC-party class mix and Tier assignment (§8.2) — TUNING RULING.** RAW gives party size/alignment/levels but not the class spread. Confirm the archetypal fighter/cleric/mage/thief weighting is fine as a PROJECT-CALL default, and confirm rank-and-file members stay **Tier-C until fought/parleyed** (stock-on-contact) with only the leader Tier-B+ — the cheap path — vs. full Tier-B generation on spawn (richer, costlier).

7. **Director cap on rival parties (§8.4) — CONFIRM the number.** Proposed: ≤ 1–2 active rival parties targeting player-relevant dungeons per region (a second queues), mirroring faction §11.3's legibility-over-noise stance. Confirm the cap and whether a *friendly* shared-dungeon party counts against it.

8. **De-duplication precedence (§4.5) — CONFIRM the rule.** The proposal: ruler action pre-empts the equivalent personal action; org action pre-empts the equivalent personal action; `work`/`train`/`research`/`court`/`relocate`/`retire`/`take_to_adventure`/L9+-individual-hijink always remain personal. Confirm this is the intended "no acting twice" semantics for an NPC who is simultaneously ruler, org leader, and individual, and that **one action per layer per month** (up to three total for a triple-hatted NPC) is acceptable — or whether a triple-hatted NPC should be capped at fewer total actions.

9. **Quest-rumor interface (§10.2, §13) — JOINT DESIGN, flagged not blocking.** The two player-facing outputs (questgiver motivation, rumor emission) depend on the concurrently-spec'd quest-rumor system. This GDD forward-references a minimal writer interface (`seed_quest_from_motivation`, `emit_rumor`). Confirm this coupling is reconciled in a **joint pass** when quest-rumor matures (its GDD owns the schema; this one owns the motivation payload), and that NA-0→NA-3 shipping *without* NA-4 (engine works, surfacing deferred) is acceptable if quest-rumor slips.

10. **Player-employed NPCs and directed downtime (§1.4, §6.5 UI note) — CONFIRM the boundary.** This GDD owns only the **NPC** side of agency/purses. A henchman/specialist the *player* employs stays player-directed (design brief §10.5) — the personal turn does **not** run for an employed henchman (the player chooses their downtime). Confirm: personal agency is suppressed for the duration of player employment, resuming if the NPC deserts/departs (design brief §10.5 departure → persistent world NPC). And confirm the **player-side** living-standard/apparent-rank UI stays out of this GDD (it belongs to the party/character tab GDD).

---

## Revision History

- **2026-07-07 — v0.1 (Draft).** Initial authoring per the faction framework §13 "Declared sibling — `gdd-npc-agency.md`" scope and master-plan §6 gap #2. Delivers all five declared scope items: (a) org-leader personal actions beyond the org turn — L9+ individual hijinks (`acore-campaign-hijinks.xml:522`), magic research at RAW prices (`acore-campaign-general-and-magic-research.xml:74-75`), class-endgame moves (§4.3); (b) the eight-action personal vocabulary (`work`/`train`/`research`/`scheme`/`court`/`relocate`/`retire`/`take_to_adventure`, §4.1) scored by the **reused** personality/ruler scorer (§7, generalizing personality §8.5 from rulers to all named NPCs); (c) personal purses — living expenses = level wage (`rulings_living_expenses_and_social_status.xml`), occupation income from the specialist/wage tables (`acore_equipment.xml:872-992`), apparent social rank from sustained spend (faction §8.7); (d) NPC adventuring parties as spawned agents with RAW composition (`acore-monster-stocking-rules.xml:446-524`) and an expedition state machine (§8); (e) feeds to dialogue ("what is this NPC up to", §10.1) and quest-rumor (questgiver motivation, §10.2), explicitly NOT Tier C transients. Architecture parallels `RulerAI` (RefCounted service, monthly-tick hook after the faction slot, Seam-A narrator clone) and inherits Regional-LOD wholesale (§3.4). Data model §5 is DESIGN ONLY (Layer-3, approval-gated). Build phasing NA-0→NA-4 slots after FF-2, gates NA-3 on dungeon-factions and NA-4 on the concurrently-spec'd quest-rumor system (coupling flagged §10, §12, §13). All ACKS references cited to `rules/*.xml`; §2 quarantines the sacred rules. §14 lists ten rulings for Jedidiah, foremost §5 schema approval and the §6.3 non-roster occupation-income proxy.
