# GDD: NPC Ruler AI (Behavior Planner)

**Authority:** PROJECT-DESIGNED — the planner, scoring function, situational modifiers, and LOD model are project design. The *action space* and its costs/consequences come from ACKS and are quarantined in §2 (sacred).
**Status:** Draft v0.3 — Regional-LOD (6-mile window + 10-hex buffer, full-tier-gated), manage-and-defend, diplomacy deferred; §10 tables + §11 action-vocabulary approved; backdrop auto-stabilize; `manage_stronghold` (build/upgrade/repair) action added (per Jedidiah, 2026-06-28).
**Depends on ACKS rules:** `rules/ax_campaign_play.xml:3-146` (monthly domain cycle), `:503-732` (ruler activity vocabulary); `rules/acore_axioms_strongholds_and_domains.xml:183-264` (domain economics), `:216-234` (garrison minimums), `:412-628` (domain morale), `:125-215` (growth/investment), `:265-411` (vassals, favors & duties); `rules/acore_equipment.xml:795-840` (henchman/vassal loyalty); `rules/daw_campaigning_armies.xml:729-855` (invasion/occupation/conquest); `rules/daw_vagaries.xml:57-62,168-172,367-372` (the only inter-ruler diplomacy in 1e — random events); `rules/acore_axioms_strongholds_and_domains.xml:84-98` (minimum stronghold value; ruler builds at ACKS prices), `:452-456` (insufficient-stronghold morale penalty); `rules/daw_equipment_and_construction.xml:747-779` (construction cost/rate/engineer); `rules/ax_campaign_play.xml:843-846` (1 day per 500gp), `:661-672`,`:706-716` (oversee/supervise construction); `rules/daw_sieges.xml:196-201`,`:455-462` (siege damage & repair).
**Depends on project GDDs:** [gdd-npc-personality.md](gdd-npc-personality.md) (§8 StrategicDisposition — the producer contract; §9 LLM narration contract), [gdd-army-warfare.md](gdd-army-warfare.md) (§4.3.3 extraction-resistance deferral; battle resolution), [gdd-realtime-scheduler.md](gdd-realtime-scheduler.md) (EventScheduler cadence), [gdd-setting-runtime-materialization.md](gdd-setting-runtime-materialization.md) (eager/named tiers; M5 live-sim deferral), [gdd_combat_behavior_tags.md](gdd_combat_behavior_tags.md) (tactical tags — disambiguation only), [gdd-stronghold-construction.md](gdd-stronghold-construction.md) (the construction engine the `manage_stronghold` action drives).
**Consumed by (forward dependency):** the build agent; future `gdd-ruler-diplomacy.md` (treaties/alliances), future `gdd-dynasties.md` (heirs/bloodline/succession-by-inheritance).
**Modifiable by Claude Code:** Yes within constraints — §2 (ACKS Constraints) is sacred and may not be reinterpreted; all numeric constants in §6/§7 are PROJECT CALL and tunable; the §10 tables and the §11 action-vocabulary entries (including `manage_stronghold`) are approved (Jedidiah, 2026-06-28).
**Last updated:** 2026-06-28

---

## 1. Purpose and Scope

### 1.1 What this document is

This GDD authors the **NPC ruler behavior planner** — the "consumer half" that `gdd-npc-personality.md §8` explicitly does not write. The personality GDD produces a `StrategicDisposition` (eight ruler-action weights + a crisis-response category) and ends there. This document defines **how a deterministic planner turns that disposition into monthly domain decisions**, formalizing the loop sketched in npc-personality §8.5.

It is the keystone of the NPC-domain agent layer: per the 2026-06-28 stock-take, it unblocks the behavior AI (item 4), gives factions and ruler-to-ruler relations a writer (items 6–7), and supplies the determinative-AI→LLM contract for ruler actions (item 11). Today NPC rulers are *simulated objects* — they accrue tribute, pay upkeep, and can die, but they never *decide anything*. This planner makes them *actors*.

### 1.2 The strategic vs. tactical boundary (read this first)

The project already has **tactical** behavior systems. This planner must not collide with them.

- **Tactical (existing, out of scope here):** how a single combatant or troop unit behaves once a fight is joined — `gdd_combat_behavior_tags.md`'s eight tag families (`formation_discipline`, `aggression_posture`, `engagement_profile`, `primary_target_rule`, etc.) and `gdd-army-warfare.md §6.3`'s heroic-foray heuristics.
- **Strategic (this GDD):** which action a ruler *chooses on its monthly turn* — administer, invest, raise garrison, muster a defense, resist an extraction. Expressed through the eight `*_weight` axes + `crisis_response` of `StrategicDisposition`, never through the tactical tag vocabulary.

The handoff line: **the planner decides *whether* to go to war / resist / muster; army-warfare resolves the resulting battle tactically.** The planner feeds army-warfare a decision; it never reaches into tactical resolution. (Two pre-existing inconsistencies were noted during research — the `gdd_combat_behavior_tags.md` vs `gdd-combat-behavior-tags.md` filename drift, and army-warfare §6.3 citing foray tags that aren't defined in the combat-tags doc. This GDD does not adopt or fix them; flagged in §13.)

### 1.3 v1 scope (the three confirmed decisions)

1. **Autonomy — Regional LOD.** Only rulers whose domains are in or adjacent to the player's active region take full deterministic monthly turns ("active set"). Distant realms remain the static materialization backdrop and take **no decisions** until the player nears (§8). Their *economy* still ticks — see §3.3.
2. **Aggression ceiling — Manage and defend.** v1 actions cover economic management, internal stability, garrison/fortification, and **defensive** military response (muster, resist extraction, withstand siege). **No proactive war, expansion, or conquest.** The `expansion_weight`, `diplomatic_weight`, and `research_weight` are still computed (the disposition is built whole) but their actions are deferred — see §5.4.
3. **Diplomacy — deferred.** v1 has **no** diplomacy actions; `RealmGraph.is_allied()` stays `false`; treaties/alliances/non-aggression await a future project-designed `gdd-ruler-diplomacy.md`. This keeps v1 grounded in ACKS RAW, which is silent on inter-ruler diplomacy (§2.6).

### 1.4 Non-goals

Offensive warfare and expansion; inter-ruler diplomacy and alliances; dynastic/heir/bloodline modeling and succession-by-inheritance (the existing `RulerDeathHandler` placeholder stands until `gdd-dynasties.md`); ruler↔non-ruler relationship graphs (§5 of npc-personality, deferred); player-facing audiences/quests/visits (a separate interaction GDD). The planner must **degrade gracefully** in the absence of all of these.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed. Every action the planner selects must reduce to operations ACKS already defines; the planner chooses *among* these, it does not invent new domain mechanics.

### 2.1 The monthly domain cycle (the planner's clock)

- The domain runs on a **monthly cycle**: start of month (domain growth → congregant growth → revenue collection), four weeks of campaign activity + random events, end of month (pay expenses → roll domain morale). The ruler's actions are chosen and executed within this cycle. (`rules/ax_campaign_play.xml:3-146`.) Domains are resolved **lowest-morale first** each month (`:125-131`).

### 2.2 The ruler activity vocabulary (the action space)

ACKS enumerates what a ruler does with their month (`rules/ax_campaign_play.xml:503-732`). The v1 catalog (§5) draws only from these:

- **Administer the domain:** +1 to that month's morale roll and +5% domain XP; time cost ½ × [6-mile hexes + vassals + (6 − largest market class)] days (`:503-511`).
- **Oversee investment:** agricultural investment attracts 1d10 new families per 1,000gp (1d10+1 if the ruler personally oversees it) (`:650-660`; growth math `acore_axioms_strongholds_and_domains.xml:132-135`).
- **Solicit/hire mercenaries, conscript, levy militia, call to arms, train/oversee troops** (`:514-732`).

### 2.3 Domain economics and garrison (the resource constraints)

- Per-family monthly revenue (Land 3–9 / Services 4 / Taxes 2 / Tribute) and expenses (Garrison ≥2 / Liturgies 1 / Maintenance 1 / Tithes 1 / Tribute); net ≈ 5/6/7 gp/family for Wilderness/Borderlands/Civilized (`rules/acore_axioms_strongholds_and_domains.xml:183-264`).
- **Garrison minimum:** ≥2gp/family/month; Borderlands commonly 3; **Wilderness must maintain 4gp/family or base morale drops** (`:216-234`). Spending below 2gp/family inflicts −1 to the monthly morale roll per gp short (`:486-487`).

### 2.4 Domain morale (the stability the planner defends)

- **Base morale** (changes when structure changes): personal-authority table (−4..+4), Leadership +1, insufficient stronghold −1/−2/−3, Borderlands −1, Wilderness −2, extra garrison +1/+2, alignment/religion mismatch −1/−2 (`:413-472`).
- **Monthly current-morale roll:** 2d6 on the Domain Morale table with modifiers (incl. **ruler administers → +1**, taxes >2gp → −1/gp, liturgy >1gp → +1/gp, **pillaged → −4**, occupied → −1/mo, repression → +1/+2 but caps current morale at 0) (`:473-502`).
- **Morale levels & consequences** (Rebellious −4 … Stalwart +4): negative tiers cause banditry, lost income, no levies, population loss, and a **cumulative monthly chance an NPC challenger emerges** (10% Rebellious / 5% Defiant / 1% Turbulent) (`:529-628`). These are the conditions the "defend" half of v1 reacts to.

### 2.5 Vassals, favors & duties, loyalty (the liege-vassal substrate)

- A ruler directly manages **one** personal domain; all others go to **vassals** (`:4-13`, `:265-272`).
- **Henchman/vassal loyalty:** 2d6 + morale on the loyalty table (≤2 Hostility … 12+ Fanatic Loyalty); base = employer Cha mod, raised by good treatment, **lowered by cruelty or broken word**; changing a vassal's tribute always triggers a loyalty roll; duties beyond the safe total trigger cumulative −1 loyalty checks; non-henchman vassals start at −2 (`rules/acore_equipment.xml:795-840`; `rules/acore_axioms_strongholds_and_domains.xml:286-397`). The planner must treat loyalty as a constraint on call-to-arms and tribute changes.
- The **Favors & Duties** 1d20 table (`:352-391`) is already implemented (`FavorsDutiesResolver`); the planner *triggers* duties (e.g., defensive Call to Arms) but does not re-implement the table.

### 2.6 Invasion, occupation, conquest — and the silence on diplomacy

- War is **the act of invading**: entering a domain without permission *is* the declaration; it triggers an immediate morale roll (`rules/daw_campaigning_armies.xml:37-39`, `:730-736`). A domain is **occupied** when attacker troop-wages-per-family exceed its garrison cost (`:738-763`) and **conquered** when all its strongholds fall (`:764-776`); pillage yields and "salting the earth" are specified (`:777-855`).
- **ACKS 1e has no player-driven inter-ruler diplomacy.** No treaties, alliances-by-negotiation, non-aggression pacts, formal war declarations, marriage alliances, envoys, or peace negotiation exist in the corpus. Alliances and wars appear **only as random-event vagaries** the Judge rolls *at* a ruler (`alliance_offered` `rules/daw_vagaries.xml:57-62`; `war_declared` `:168-172`; `friendly_lord` `:367-372`), and surrender is only a siege outcome. **Therefore v1 introduces no diplomacy** (§1.3.3); any future diplomacy is project-invention requiring its own GDD and Jedidiah's rulings.
- **ACKS is also silent on succession-by-inheritance** (holdings change hands by conquest/occupation or bandit-emergent challengers, not a death-and-inheritance system) — so the planner does not model heirs; it leaves succession to the existing `RulerDeathHandler` placeholder pending `gdd-dynasties.md`.

### 2.7 Stronghold construction (the fortification lever)

- A ruler **constructs a stronghold using ACKS construction prices** to secure a domain (`rules/acore_axioms_strongholds_and_domains.xml:84-86`). **Minimum stronghold value per 6-mile hex:** Civilized 15,000gp / Borderlands 22,500gp / Wilderness 32,000gp; multiple strongholds add their values; **if total value is insufficient the domain is harder to control and morale suffers** (`:87-98`).
- **Insufficient-stronghold morale penalty:** base morale −1 at ≥½ minimum, −2 at ≥¼, −3 below ¼ (`:452-456`). This is the morale incentive that drives the build/upgrade action.
- **Construction cost = base gp; rate ≈ 500gp/day** baseline (`rules/ax_campaign_play.xml:843-846`), built by workers/engineers (engineer 250gp/month, one per ≤100,000gp project) (`rules/daw_equipment_and_construction.xml:747-779`). Overseeing/supervising construction adds +5%/+10% (`ax_campaign_play.xml:661-672`, `:706-716`).
- **Siege & repair:** reduction damages structural hit points (shp 0 = rubble); during a siege the defender may repair up to **half** the damage (wood 5 shp/gp, stone 1 shp/gp), and **the remainder must be rebuilt after the siege at full construction cost** (`rules/daw_sieges.xml:196-201`, `:455-462`). ACKS has **no separate "upgrade" rule** (build additional value as a fresh project) and **no "restore" rule beyond rebuild-at-full-cost**.

---

## 3. Architecture and Integration

### 3.1 Placement (no new autoload)

The design brief restricts autoloads to truly-global systems (`GameState`, `CampaignRepository`, `LLMManager`, `AudioRouter`, `EventBus`); new subsystems are `RefCounted` services. The planner follows the Phase 7 precedent (`realm_ai/` is all `RefCounted`):

- New service `RulerAI` (`class_name RulerAI`, `ruler_ai.gd`), recommended under `engine/subsystems/realm_ai/` to keep cohesion with the existing realm substrate (final folder is a minor call; see §13).
- Sub-components (all `RefCounted`, stateless statics where possible): `StrategicDispositionBuilder`, `RulerActionCatalog`, `RulerActionScorer`, `RulerCrisisResponder`, `RulerLodManager`, `RulerActionNarrator` (the LLM seam).
- **Determinism is mandatory.** Every decision is reproducible from (ruler state + domain state + a seeded RNG). Banker's rounding (round half to even) everywhere a value is rounded. The full loop must pass with the **mock LLM provider** — the LLM is never a decision-maker (design brief §17: "engine decides, LLM narrates").

### 3.2 The monthly-tick hook

The planner runs inside the existing monthly cadence, mirroring the proven `NpcSyndicateMonthlyResolver` batch pattern (process all NPC entities, no UI interrupt). In `engine/subsystems/session/handlers/domain_handlers.gd::_handle_monthly_tick`, after the per-domain economic resolution (`_resolve_domain_month` → `_save_domain`) and alongside the syndicate/venture fast-paths:

```
RulerAI.process_campaign_month(campaign_id, calendar_day, active_set) -> Array
```

For each **active-set** NPC-owned domain, this runs the decide→execute loop (§6) with the post-resolution `result` dict already in hand (revenue, morale_tier, net_income, threats, challenger_summary) — exactly the inputs the scorer needs. Mutations land before `_save_domain` persists them. No `auto_pause` is emitted for NPC rulers (only the player's domain surfaces the monthly-report modal).

The PC-vs-NPC branch is simply `owner_character_id` ≠ the player character. Backdrop domains are skipped by the planner entirely (their economy still ticks — §3.3).

### 3.3 Regional-LOD model in one paragraph

The economic substrate (`_resolve_domain_month`: revenue, expenses, morale roll, growth, tribute, challenger emergence) **already runs for every domain regardless of owner**. Regional-LOD therefore gates only the **decision layer**, not the economy: `RulerAI.decide()` runs only for active-set rulers; backdrop realms keep their living economy and get a cheap **auto-stabilize** pass (§8.4) instead of the full planner, so they hold steady rather than decay while off-camera. This makes LOD nearly free and avoids the full M5 live-sim build.

### 3.4 Optional self-paced strategic event (alternative cadence)

If a ruler should act off the monthly boundary (e.g., react within days to an invasion), register a global handler for a new event type and seed one event per active ruler keyed to its `character_id`:

```
scheduler.schedule_at(now + period_rounds, "ruler_strategic_turn",
                      ruler_character_id, {domain_id: ...}, PRIORITY_ENVIRONMENTAL)
```

Self-reschedule via the handler's `next_events` return (the domain-tick contract). Use `cancel_all_for_owner(ruler_character_id, "ruler_strategic_turn")` on LOD demotion. **v1 default: monthly batch only** (§3.2); the per-ruler event is the hook for crisis reactivity if playtesting shows monthly is too coarse.

---

## 4. Sub-phase 0 — Build `StrategicDisposition` / `RulerProfile` first

The planner's input is **designed but unbuilt** (npc-personality §8 is on paper; no schema table exists). This GDD co-specifies its build as the planner's first sub-phase, because the planner is meaningless without it and the spec is complete.

### 4.1 Source data (already present)

The 12-axis `NpcPersonality` record is live and persisted in `characters.personality` JSON, carrying the raw `axes` dict and the two `motivation_*` strings — i.e., **all inputs to the §8.3 formulas already exist**. The builder also needs `alignment` from the character record (an implicit dependency surfaced by the `orthodoxy_term`).

### 4.2 The builder (reproduce npc-personality §8.3 exactly — PROJECT CALL)

`StrategicDispositionBuilder.build(npc_personality, alignment) -> StrategicDisposition`, implementing the helpers and formulas verbatim so results are reproducible across engineers (npc-personality §11.3 mandate):

```
u(a)   = (a - 1) / 9          # 1..10 -> 0.0..1.0
inv(a) = 1 - u(a)
mot(t) = 0.7 if primary==t  + 0.3 if secondary==t   # else 0.0
clamp01(x) = clamp(x, 0.0, 1.0)

research_weight     = clamp01(0.10 + 0.45*u(epistemic_curiosity) + 0.35*mot("knowledge"))
religious_weight    = clamp01(0.08 + 0.50*u(mysticism) + 0.35*mot("faith"))
economic_weight     = clamp01(0.12 + 0.40*mot("wealth") + 0.20*mot("legacy") + 0.15*mot("pleasure") + 0.10*u(epistemic_curiosity))
military_weight     = clamp01(0.10 + 0.30*inv(affective_compassion) + 0.25*u(in_group_loyalty) + 0.30*mot("power") + 0.30*mot("revenge") + 0.25*mot("security"))
expansion_weight    = clamp01(0.08 + 0.40*mot("power") + 0.20*inv(affective_compassion) + 0.15*inv(self_interest))
fortification_weight= clamp01(0.12 + 0.40*mot("security") + 0.20*mot("survival") + 0.20*mot("legacy"))
diplomatic_weight   = clamp01(0.10 + 0.30*u(self_interest) + 0.25*u(epistemic_curiosity) + 0.30*mot("knowledge") + 0.25*mot("legacy") - 0.20*inv(affective_compassion))

orthodoxy_term = u(societal_orthodoxy)            if alignment=="Lawful"
               = inv(societal_orthodoxy)          if alignment=="Chaotic"
               = abs((societal_orthodoxy-5.5)/4.5) if alignment=="Neutral"
oppression_weight   = clamp01(0.08 + 0.40*inv(affective_compassion) + 0.25*orthodoxy_term + 0.30*mot("power") - 0.20*u(self_interest) - 0.25*mot("freedom"))

crisis_response:
  if stress_reactivity >= 6:  "aggressive" if self_interest<=5 else "cautious"
  else:                       "diplomatic" if self_interest<=5 else "defensive"
```

The §8.3 worked example (Lawful baron) is the canonical unit test: military 0.846, oppression 0.801, diplomatic 0.078 (§12).

### 4.3 Relational dictionaries (degrade gracefully)

`aggression_toward[realm_id]` and `alliance_preference[realm_id]` lean on inter-realm relationship state (`realm_relations`) and on npc-personality §5 relationships, which is **deferred/unbuilt**. v1 build:

- `aggression_toward`: seed from `RealmRepository.get_relation()` bands (hostile/unfriendly → higher), plus +0.5 when `motivation == "revenge"` and the target is the revenge subject. Absent relations → empty (neutral).
- `alliance_preference`: computed for forward-compat (scaled by `diplomatic_weight` and `u(self_interest)`) but **dormant in v1** (no alliance actions). Absent relations → empty.

### 4.4 `RulerProfile` view

`RulerProfile` = the eight weights + `crisis_response` + the two dicts, computed from `StrategicDisposition` and stored alongside it for systems that only want the weight vector. (Legacy compatibility view per npc-personality §8.2.)

---

## 5. The Ruler Action Catalog (v1)

Each action maps to: the existing handler/resolver it invokes (research-confirmed, keyed on `owner_character_id`), its **governing weight**, a **base_value** (PROJECT CALL baseline desirability, 0–1), its ACKS basis, and its preconditions. The planner sets `state.character_id = ruler_npc_id` and calls the handler's `on_complete(state, _runner)` — no new domain mechanics are written.

### 5.1 Economic actions

| Action | Handler | Weight | base | ACKS | Preconditions |
|---|---|---|---|---|---|
| `administer_domain` | `administer_domain.gd` | economic | 0.45 | `ax_campaign_play.xml:503-511` | ruler of domain; cheap; always available |
| `oversee_investment` (agricultural) | `oversee_investment.gd` | economic | 0.35 | `:650-660`; `acore_…:132-135` | surplus treasury ≥ investment amount |
| `issue_decree(tax)` | `issue_decree.gd` | economic | 0.20 | morale modifiers `acore_…:486-502` | ruler; raising tax >2gp trades revenue for morale |

### 5.2 Stability / fortification actions (the core of "defend")

| Action | Handler | Weight | base | ACKS | Preconditions |
|---|---|---|---|---|---|
| `raise_garrison` (meet 2/3/4 gp/family via conscript/levy/mercenary) | `conscript_troops.gd` / `levy_militia.gd` / `hire_mercenaries.gd` | fortification | 0.40 | garrison min `acore_…:216-234` | under-garrison detected; clanhold blocks militia/conscript |
| `issue_decree(liturgy/tithe)` | `issue_decree.gd` | religious | 0.20 | liturgy morale `acore_…:486-502` | ruler |
| `repress_population` | `repress_population.gd` | oppression | 0.15 | `acore_…:486-502` (caps morale at 0) | ruler; no militia in force; **last-resort** |
| `train_troops` / `oversee_troop_training` | `train_troops.gd` | military | 0.25 | `ax_campaign_play.xml:514-732` | at stronghold; Manual of Arms ≥1 |
| `hold` / bank treasury | (none) | — | 0.10 floor | — | always available; prevents thrashing |
| `manage_stronghold` (build / upgrade / repair) | **new** `manage_stronghold.gd` → `CommissionPipeline.start_commission` or abstract fast path | fortification | 0.45 | construction `daw_equipment_and_construction.xml:747-779`; min value `acore_…:84-98`; repair `daw_sieges.xml:455-462` | stronghold value < required minimum, or ruined / siege-damaged; treasury ≥ cost |

**`manage_stronghold` — build note (this one is net-new engine work).** Unlike every other v1 action, no NPC-usable handler exists today: `CommissionPipeline.start_commission` (`engine/subsystems/strongholds/commission_pipeline.gd`) is reached only by the player commission wizard and is **not** keyed on `state.character_id`, and `LifecycleHandler.restore_from_ruin` only flips lifecycle state (it does **not** rebuild shp/value and has no caller). So the build agent must add a new activity handler `manage_stronghold.gd` — `on_complete(state, _runner)` resolving `owner_character_id → domains.id` like `administer_domain.gd` — exposing three modes:
- **build / upgrade:** because NPC strongholds are **abstract value-only records** (`gdd-stronghold-construction.md §18`), the cheap path is to deduct gp from the domain treasury and `CampaignRepository.update_stronghold(id, {cp_value, shp, garrison_capacity})` toward the required minimum, then `StrongholdRepository.recompute_sufficiency_after_change(domain_id)` to refresh morale/income gating. (Optionally reuse the timed `CommissionPipeline` daily tick if NPC construction should consume in-game time like the player's.)
- **repair / restore:** raise shp/cp_value back above threshold by spending the post-siege rebuild cost (RAW: full construction cost for the un-repaired half), then call `LifecycleHandler.restore_from_ruin(domain_id, stronghold_id, calendar_day)` if the domain sits in `ruined_stronghold`.

### 5.3 Defensive military actions

| Action | Handler/resolver | Weight | base | ACKS | Trigger |
|---|---|---|---|---|---|
| `defensive_resistance` (resist requisition/loot/invasion) | generalizes `ExtractionResistanceHeuristic.evaluate` (§7.3) | military × crisis | 0.50 | resistance `daw_…` ; occupation `:738-763` | hostile army extracting/invading |
| `call_to_arms` (defensive muster) | `call_to_arms_handler.gd::issue_call` | military | 0.40 | favors/duties `acore_…:352-391` | active threat + has vassals within muster range |
| `withstand_siege` / withdraw to stronghold | army-warfare siege path | fortification × crisis | 0.45 | sieges (DaW) | besieged or about to be |

### 5.4 Deferred weights (computed, not exercised in v1)

`expansion_weight` (no offensive campaign/conquest action), `diplomatic_weight` (no diplomacy actions — §1.3.3), `research_weight` (magical research is a personal mage activity, not a ruler domain action in v1). The disposition is still built whole so v2/diplomacy/expansion GDDs can light these up without a rebuild. The planner reads all eight; v1's catalog simply offers no actions bound to these three.

---

## 6. The Scoring Algorithm (formalizing npc-personality §8.5)

### 6.1 The loop

For each active-set NPC ruler, once per monthly turn:

```
1. candidates = RulerActionCatalog.available_for(ruler, domain, world_state)   # precondition-gated
2. for each action a:
     utility(a) = base_value(a)
                * relevant_weight(a, disposition)            # the action's governing weight (§5)
                * Π situational_modifier_i(a, domain, world)  # §6.2
3. apply crisis_response bias if a threat is present          # §7
4. pick argmax(utility); for large realms (≥ N domains/families) pick top-2..3 and act on each
5. execute deterministically via the mapped handler (§5); no LLM call
6. emit ruler_action_taken(...); narrate retroactively only if player-relevant (§9)
```

Tie-breaking uses a per-(ruler, calendar_month) seeded RNG so reruns are identical; any rounding is banker's rounding. The "HTN-lite" allowance (npc-personality §8.5) stands: the scorer MAY read raw axis values from `StrategicDisposition` for finer per-action utility (e.g., `in_group_loyalty` nudging call-to-arms vs. mercenaries) rather than only the eight summary weights.

### 6.2 Situational modifier tables (PROJECT CALL — tunable)

Multiplicative modifiers applied to candidate utilities (1.0 = neutral):

**Domain morale tier** (boosts stability actions as morale falls):

| Tier | administer | raise_garrison | decree(lower tax) | repress | investment |
|---|---|---|---|---|---|
| Loyal+ (≥+1) | 1.0 | 0.8 | 0.7 | 0.2 | 1.3 |
| Apathetic (0) | 1.2 | 1.0 | 1.0 | 0.5 | 1.0 |
| Demoralized/Turbulent (−1/−2) | 1.5 | 1.4 | 1.4 | 1.0 | 0.6 |
| Defiant/Rebellious (−3/−4) | 1.8 | 1.7 | 1.6 | 1.5 (oppressive rulers) | 0.3 |

**Treasury state:** below an upkeep buffer (e.g., < 2 months expenses) → spendy actions ×0.4, `issue_decree(tax)` ×1.5; ample surplus (> 6 months) → `oversee_investment` ×1.4.

**Garrison state:** spending < territory minimum (2/3/4 gp/family) → `raise_garrison` ×2.0 (it's also actively bleeding morale).

**Stronghold state:** value below the territory minimum (`acore_…:87-98`) → `manage_stronghold` ×2.0; domain in `ruined_stronghold` → `manage_stronghold` ×3.0 (outranks economic actions until the 30-day grace window closes).

**Threat present** (hostile/challenger army in or adjacent, or extraction underway): defensive actions ×1.5–2.5 and crisis_response bias applies (§7); economic/investment actions ×0.5.

### 6.3 Worked example (illustrative)

The §4.2 Lawful baron (military 0.846, oppression 0.801, economic ~0.2, fortification depends on motivation) at Turbulent morale (−2) with a challenger accumulating: `raise_garrison` = 0.40 × 0.846(military-ish via fortification path) × 1.4(morale) × 2.0(under-garrison if applicable) dominates; `repress_population` = 0.15 × 0.801 × 1.0 is a strong secondary for this oppressive ruler; `administer_domain` = 0.45 × ~0.2 × 1.5 trails. Result: the baron reinforces the garrison, then represses — a recognizably "iron-fisted" response, emergent from the disposition, not scripted.

---

## 7. Crisis and Threat Response (the "defend" core)

When a threat is detected during the monthly turn, `RulerCrisisResponder` biases action selection by the ruler's `crisis_response` category. The threats v1 recognizes (all already produced by the substrate): **morale collapse / rebellion**, **NPC challenger emergence** (`NPCChallengerEmergence` already fires on the tick), **invasion / extraction by another army**, and **siege**.

### 7.1 crisis_response → defensive posture (PROJECT CALL)

| crisis_response | Posture and action bias |
|---|---|
| `aggressive` | Active defense: resist extraction even at lower BR margin, sortie against challengers, call to arms hard. Lowers the resistance BR threshold (§7.3). |
| `defensive` | Fortify: prioritize `raise_garrison`, hold strongholds, withstand siege; resist only from strength. |
| `cautious` | Over-prepare: muster more than needed, hoard treasury/supplies, withdraw to stronghold rather than meet in the field. |
| `diplomatic` | **No diplomacy in v1** → degrades to appeasement/economic: concede extraction/loot rather than fight where survivable, buy mercenaries; otherwise behave as `cautious`. (Flagged in §13 — the future diplomacy GDD replaces this degradation with real parley.) |

### 7.2 Responding to challenger emergence

`NPCChallengerEmergence.process_monthly_tick` already accumulates and may spawn an NPC challenger (and can materialize it as an army). The planner's response: if a challenger is *accumulating*, prioritize stability actions (administer / lower tax / raise garrison / repress per disposition) to push morale up and bleed the cumulative chance; if a challenger has *materialized as an army*, route to `defensive_resistance` / `call_to_arms`.

### 7.3 Generalizing the extraction-resistance heuristic

`gdd-army-warfare.md §4.3.3` ships a **placeholder** (`ExtractionResistanceHeuristic`): resist iff the owner can bring ≥50% of the offending army's BR from personal garrison + vassal forces in muster range. The planner **replaces this wholesale** (as army-warfare states it will) with a disposition-driven decision while reusing the heuristic's vassal-federation machinery (RealmGraph + VassalRepository + per-vassal loyalty rolls):

```
available_br = personal_garrison_br + federated_vassal_br      # reuse existing federation
threshold_ratio = 0.50                                          # the RAW-placeholder anchor
  - 0.15 * military_weight                                      # martial rulers resist from weaker positions
  - 0.10 * (crisis_response == "aggressive")
  + 0.15 * (crisis_response == "cautious")
  + 0.10 * defending_own_stronghold                             # siege advantage emboldens
resist if available_br >= clamp(threshold_ratio, 0.2, 0.9) * attacker_br
```

At a neutral disposition this reproduces the 50% placeholder (regression anchor); dispositions shift it. Federation, loyalty rolls, and `vassal_revolted` emission are unchanged from the heuristic.

### 7.4 Stronghold loss and ruin

When a siege destroys or ruins the stronghold (`EventBus.stronghold_collapsed`; the domain enters `ruined_stronghold` with a 30-day grace), the planner prioritizes `manage_stronghold` (repair/rebuild) above ordinary economic actions for that ruler — a lost stronghold drives the −1/−2/−3 base-morale penalty (§2.7) and, if the grace lapses without rebuild, `tick_lifecycle_state` auto-abandons the domain. `crisis_response` modulates urgency: `aggressive`/`defensive` rebuild hard and immediately; `cautious` may withdraw forces and hoard before committing the rebuild cost.

---

## 8. Regional-LOD Activation

### 8.1 Tiers

- **Active set:** NPC rulers that are (a) **already materialized to `persistence_tier == "full"`** and (b) whose domain lies within the **6-mile play window** (the `RegionZoomIn` 40×32 six-mile-hex region map) **plus a 10-six-mile-hex buffer ring** around it — **or** who are currently party to a player-relevant conflict/interaction regardless of distance. These take full monthly turns (§6).
- **Materialization safety (the buffer never forces materialization).** The buffer is a hysteresis margin over *already-full* rulers only. Per `gdd-setting-runtime-materialization.md`, the leaf (Marquis/Baron) sub-fief rulers in and around the window are **lazy / names-only** (`persistence_tier == "named"`, `establishment_method='materialized_subfief'`) and promote to `full` **on visit**; eager rulers are **Count+**. The planner **never** triggers that promotion: a `named` or abstract ruler in the window or buffer stays **Backdrop** until the existing promote-on-visit path makes it `full`, at which point it auto-qualifies for Active if still in band. LOD is thus strictly downstream of materialization — no lazy-materialization conflict.
- **Backdrop:** every other ruler (all `named`/abstract rulers, and `full` rulers outside the band). Economy ticks and **auto-stabilize** run (§3.3, §8.4); **no planner decisions**.

### 8.2 Promotion / demotion

- **Promote** a backdrop ruler to active when it is `full`-tier and enters the §8.1 band (the player moves within the window + buffer), or when it becomes party to a player-relevant event. On promotion, build its `StrategicDisposition` if not cached (§4) and (if using §3.4 events) seed its `ruler_strategic_turn`.
- **Demote** when the player leaves and no active involvement remains, after a grace window (e.g., 1 month). Cancel its scheduled events via `cancel_all_for_owner`.
- Emit `ruler_activated_for_lod` / `ruler_deactivated_for_lod` for observability and save/load reconciliation.

### 8.3 Relationship to M5

This LOD model is deliberately *not* the deferred "Phase M5 live realm simulation." M5 would run every realm globally; Regional-LOD runs only the near set and leaves the rest as the static M1 backdrop. The planner is forward-compatible: when M5 lands, the active set simply widens (eventually to "all"), reusing the same decide loop. v1 does not require M5.

### 8.4 Backdrop auto-stabilize

Backdrop NPC domains do not run the planner, but they are **not left to rot** (per Jedidiah: auto-stabilize from v1). Each monthly tick they get a cheap, deterministic **auto-stabilize** pass — no action selection, no LLM (PROJECT CALL constants, tunable):

- **Garrison treated as funded to minimum.** For the off-camera morale roll the domain is treated as meeting its territory garrison minimum (2/3/4 gp/family, `acore_axioms_strongholds_and_domains.xml:216-234`), so the under-garrison penalty (−1 per gp short, `:486-487`) does not accrue while off-camera. This is the dominant neglect-spiral driver, so suppressing it is most of the stabilization.
- **Routine administration assumed.** The ruler is treated as administering the domain (+1 to the monthly morale roll, `:486-502`), so current morale gravitates toward base morale (the 2d6 table's "6–8 → shift toward base" band) rather than drifting down.
- **Neglect morale floor.** Off-camera current morale does not fall below Apathetic (0) from neglect alone. **Player-caused effects still apply in full** — a domain the player pillages still takes −4 and an occupied one −1/month (`daw_campaigning_armies.xml:729-855`). Drama stays player-driven; idle realms do not collapse on their own.
- **No discretionary activity.** Backdrop rulers take no investment, recruitment, expansion, war, or challenger-response actions; revenue / expense / tribute still tick unchanged.

On promotion to Active (§8.2) the real planner takes over from this stable baseline — a freshly-approached realm is coherent, not mid-collapse from having been ignored.

---

## 9. Determinative-AI → LLM Contract

The planner is **fully functional with the mock provider** (`LLMManager` is presently a stub returning `ResponseEnvelope.fallback(...)`; `is_configured()` is `false`). The LLM is optional polish on top of deterministic decisions. Two seams:

### 9.1 Seam A — retroactive action narration (npc-personality §8.5 step 6)

When the player observes/interacts with a ruler-action outcome, `RulerActionNarrator` assembles a context Dictionary and calls `LLMManager.request_narration(context)`. Proposed shape (extends the §9.2 NPC Context Package; `task_type` is the only key the stub reads today):

```
{
  task_type: "ruler_action_narration",
  ruler_npc_id, domain_id, realm_name,
  personality_summary, speech_notes,        # cached at creation (npc-personality §9.2)
  disposition_directives: [ ... ],          # surviving 1-3/8-10 axis directives (§9.1 filter)
  action_id, action_outcome: { ... },        # the structured deterministic result
  motivation_primary, motivation_secondary,
  disposition_toward_player, disposition_trend
}
```

If `is_configured()` is false (always, today) the narrator returns the **deterministic template** for that `action_id` (the mock compositional-flavor / fragment-bank path, npc-personality §9.3). The engine has already decided and executed; narration is cosmetic and `is_fallback`-safe.

### 9.2 Seam B — strategy reassessment (design brief §11.3)

The design brief specifies that when **player actions significantly change a ruler's situation**, "the LLM returns structured strategic updates that feed back into the scoring function." v1 defines this contract but treats it as **optional enhancement**:

- Trigger: a player action crosses a significance threshold (attacks the ruler, takes a vassal, collapses its morale, etc.). Thresholds are PROJECT CALL (§13 tuning).
- The planner MAY call `request_narration({task_type: "ruler_strategy_reassessment", ...})` expecting a **structured** suggestion (e.g., bump `aggression_toward[player_realm]`, choose a posture).
- **Validation (design brief §9.1):** every LLM-returned suggestion is schema-validated against the action vocabulary; unknown, malformed, or rule-violating suggestions are rejected and logged. A valid suggestion enters the scorer only as a **situational modifier** — it never bypasses determinism or executes directly.
- With the stub/mock, reassessment is a no-op; the deterministic scorer already handles the new situation via §6.2/§7. The LLM only adds flavor-of-reasoning and narrative color, never authority.

---

## 10. Persistence and Schema (approved)

New persistent state (SQLite is ground truth; migrations sequential, versioned, non-destructive; banker's rounding). **These are Layer-3 data-model additions, approved by Jedidiah 2026-06-28 — the migration may be written:**

- **`ruler_dispositions`** (one row per NPC ruler, keyed by `character_id`): the 7 strategic axis snapshot, the 8 weights, `crisis_response`, and serialized `aggression_toward` / `alliance_preference`. Per npc-personality §8 ("their own tables keyed by npc_id"). Alternative considered: fold into `characters.personality` JSON — rejected to keep the strategic layer queryable and to match the §8 intent.
- **`ruler_ai_state`** (one row per active ruler): LOD tier, `last_strategic_turn_day`, last-action id, and an optional small decision/narration cache (to avoid re-narrating and to support save/load reconciliation).

Both register in the standard three sites (`SettingRepository`/`CampaignRepository`/`SettingDatasetHasher` per the build-log convention) as applicable. Disposition is regenerable from `NpcPersonality` + alignment, so a migration that drops and rebuilds it is non-destructive in practice.

---

## 11. Action Vocabulary and Signals

- **Register the v1 ruler actions** (§5) in the action vocabulary / activity catalog as the canonical, validated set (design brief §17: "the action vocabulary is the API"). Most already exist as activity ids; `defensive_resistance`, `raise_garrison`, `hold`, and `manage_stronghold` are the new planner-level composite intents and must be registered (and are what the §9.2 LLM suggestions validate against). **These new action-vocabulary entries are approved (Jedidiah, 2026-06-28).** `manage_stronghold` additionally requires a new `manage_stronghold.gd` handler — no NPC-usable construction path exists today (see §5.2).
- **New EventBus signals** (past-tense, snake_case; no collision with Phase 7's `realm_title_changed` / `vassal_revolted` / `vassal_tribute_paid` / `vagary_of_war_resolved`):
  - `ruler_action_taken(ruler_npc_id, domain_id, action_id, outcome)`
  - `ruler_strategy_reassessed(ruler_npc_id, trigger, changes)`
  - `ruler_activated_for_lod(ruler_npc_id)` / `ruler_deactivated_for_lod(ruler_npc_id)`

---

## 12. Test Plan

Hand-authored scenarios before any procedural content (per CLAUDE.md). Mock provider only.

**Unit:**
- `StrategicDispositionBuilder` reproduces the npc-personality §8.3 worked example exactly (military 0.846, oppression 0.801, diplomatic 0.078) — golden test; guards the §11.3 reproducibility mandate.
- Scorer determinism: identical (ruler, domain, seed) → identical choice across runs.
- Precondition gating: `train_troops` blocked without Manual of Arms / not at stronghold; `levy_militia`/`conscript` blocked for clanhold; `repress_population` blocked when militia in force.
- `crisis_response` 4-quadrant mapping (stress_reactivity × self_interest) is correct at the boundaries (5/6 split).
- `defensive_resistance` at neutral disposition reproduces the 50%-BR placeholder (regression anchor); aggressive/cautious shift the threshold as specified (§7.3).
- LOD promote/demote transitions emit the right signals and seed/cancel events correctly; the buffer never promotes a `named`/abstract ruler (materialization-safety, §8.1).
- Backdrop auto-stabilize (§8.4): a neglected off-camera domain holds at/above Apathetic, while a player-pillaged one still takes −4.

**Integration (hand-authored domain + ruler):**
- Turbulent-morale domain with an oppressive ruler → planner raises garrison then represses; morale trends up over a few months.
- Accumulating challenger → planner stabilizes; materialized challenger army → planner resists/musters.
- Hostile army extracting → `defensive_resistance` federates vassals and resolves (replacing the heuristic) — outcome routes to army-warfare battle resolution.
- Full monthly batch over a mixed campaign (PC domain + several NPC domains, some active, some backdrop) runs with no `auto_pause`, no LLM; active rulers act, backdrop rulers only auto-stabilize.
- Narration: with the stub, `ruler_action_taken` produces a deterministic `is_fallback` template; no crash, no variance.
- Stronghold: an under-minimum or `ruined_stronghold` domain → planner selects `manage_stronghold`, raises stronghold value/shp toward the territory minimum (lifting the −1/−2/−3 penalty) and clears ruin before the 30-day grace lapses.

---

## 13. Open Questions / Architectural Concerns

- **StrategicDisposition build ownership (confirm):** this GDD assumes the planner build *includes* sub-phase 0 (§4). If Jedidiah prefers it as a separate prerequisite session, the planner GDD's §4 becomes a dependency instead. (Recommended: keep it here.)
- **New tables — approved (Jedidiah, 2026-06-28):** `ruler_dispositions` and `ruler_ai_state` (§10) are cleared as data-model additions; the build agent may write the migration.
- **Active-region definition — resolved (Jedidiah, 2026-06-28):** 6-mile play window + a 10-six-mile-hex buffer ring, gated to `persistence_tier == "full"` so the buffer never forces lazy materialization (§8.1).
- **Backdrop decay vs. auto-stabilize — resolved (Jedidiah, 2026-06-28):** backdrop realms auto-stabilize from v1 (§8.4) — they hold near base morale and do not collapse from neglect; player-caused effects still apply.
- **Action-vocabulary registration (§11) — approved (Jedidiah, 2026-06-28):** `defensive_resistance`, `raise_garrison`, `hold`, and `manage_stronghold` are cleared for registration.
- **`manage_stronghold` is net-new engine work (build dependency):** no NPC-usable build/upgrade/repair path exists today — `CommissionPipeline.start_commission` is player-wizard-only and not `character_id`-keyed, and `LifecycleHandler.restore_from_ruin` is a state-flip stub with no rebuild logic and no caller. The build agent must add `manage_stronghold.gd` with the abstract-record fast path (§5.2). Flagged so it is scheduled, not assumed.
- **Reassessment significance thresholds (§9.2):** what player actions trigger LLM strategy reassessment, and the cooldown — PROJECT CALL, needs playtest values.
- **`diplomatic` crisis_response degradation (§7.1):** in a no-diplomacy v1 this collapses to appeasement/cautious; the future `gdd-ruler-diplomacy.md` should replace it with real parley.
- **All numeric constants** in §5 (base_values), §6.2 (situational modifiers), and §7 (crisis biases, resistance threshold) are PROJECT CALL and expected to move in playtesting.
- **Pre-existing inconsistencies (noted, not fixed here):** the `gdd_combat_behavior_tags.md` vs `gdd-combat-behavior-tags.md` filename drift, and army-warfare §6.3 citing foray tags (`bold`/`glory_seeking`/`aggressive_when_cornered`/`valor_seeking`) absent from the combat-tags doc. The planner deliberately does not adopt these tactical tags; recommend a separate cleanup.
- **Forward dependencies:** `gdd-ruler-diplomacy.md` (lights up `expansion_weight`/`diplomatic_weight`, the alliance/treaty writer, `is_allied()`); `gdd-dynasties.md` (heirs/bloodline/succession-by-inheritance, replacing the `RulerDeathHandler` placeholder).

---

## Revision History

- **2026-06-28 — v0.1 (Draft).** Initial authoring. Scoped per Jedidiah's three decisions: Regional-LOD autonomy (§8), manage-and-defend action ceiling (§5, no offensive war/expansion), diplomacy deferred (§1.3.3, §2.6). Co-specifies the `StrategicDisposition`/`RulerProfile` build (§4) reproducing npc-personality §8.3. Defines the scoring loop (§6) formalizing npc-personality §8.5, crisis response (§7) including the generalized extraction-resistance decision replacing the army-warfare §4.3.3 placeholder, the determinative-AI→LLM contract (§9, two seams, mock-correct), persistence (§10), and action-vocabulary/signals (§11). All ACKS references cited to `rules/*.xml` and quarantined in §2.
- **2026-06-28 — §10 tables approved.** Jedidiah approved `ruler_dispositions` and `ruler_ai_state` in review; §10, §13, and the front-matter updated to clear the migration. Action-vocabulary registration (§11) remains pending approval.
- **2026-06-28 — v0.2.** Resolved two §13 open items per Jedidiah: Active set = 6-mile play window + 10-six-mile-hex buffer ring, gated to `persistence_tier == "full"` so the buffer never forces lazy materialization (§8.1, §8.2); backdrop realms auto-stabilize from v1 (new §8.4) rather than decay (§3.3, §13). Added §8.4, LOD/auto-stabilize tests (§12), and the pending-approval note for §11 action-vocabulary entries.
- **2026-06-28 — v0.3.** Jedidiah approved the §11 action-vocabulary entries. Added the `manage_stronghold` (build / upgrade / repair) action (§5.2) bound to `fortification_weight`, a stronghold-construction ACKS Constraints section (new §2.7), a stronghold-state situational modifier (§6.2), a stronghold-loss/ruin response (§7.4), and a stronghold test (§12) — the fortification lever Jedidiah flagged as necessary. Flagged that this action is **net-new engine work**: no NPC-usable construction path exists today, so a new `manage_stronghold.gd` handler is required (§5.2, §13).
