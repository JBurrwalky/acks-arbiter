# Build Handoff — Faction Framework, Phase FF-3 (Realm Diplomacy & Rebellion)

**For:** Claude Code (build agent)
**Spec:** `generation/gdd-faction-framework.md` (v0.7) — the authoritative design. This handoff sequences the **§5 realm layer** into a verifiable build; the GDD is the source of truth for any detail not repeated here.
**Depends on:** FF-1 (registry, stances, realm mirrors, default-stance evaluator, ledger, `realm_relations` drift writer — **all landed** in Wave 0, migrations 188/189). Ruler-AI (built, Phases 0–4). Army-warfare (built).
**Author:** Advisor (design), authored for Wave-1 planning per `docs/master-build-plan-social-llm-stack.md` §3. **Date:** 2026-07-07.

---

## 0. Scope and boundary

FF-3 builds the **§5 Realm Layer** end to end. Its neighbors:
- **FF-2 (organizations)** is NOT built yet — so FF-3 does NOT touch org seeding, org turns, temple rivalry, or org membership. Anywhere §5 references "organizations" as actors (e.g. reputational contagion of a broken treaty reaching orgs), scope it to **realm-mirror factions only** for now and leave a `# FF-2:` TODO.
- **FF-4 (allegiance & covert ops)** owns the full `AllegianceEvaluator` (§7.3) + feign/betrayal execution + secrecy/discovery UI surfacing + divided-loyalty events. FF-3 builds ONLY the pieces §5.7 rebellion needs directly: the secret loyalty rolls that recruit coalition members, and the plot secrecy countdown (§7.4's *plot* mechanics, not the org-allegiance mechanics). Do NOT build `AllegianceEvaluator.evaluate` (the third-party org side-picking engine) — that's FF-4 and needs orgs.
- `§7.2` default-stance evaluator and the `realm_relations` one-band-per-cluster drift writer are **already built** (FF-1.3 `DefaultStanceEvaluator`, `RealmRelationsDrift`). Reuse them; do not reimplement.

**In scope (the six §5 pieces):** vassal loyalty state + triggers (§5.2), compliance ladder (§5.3), treaties (§5.5), diplomacy actions (§5.6, the ruler-AI v2 unlock), rebel coalitions (§5.7), player-as-vassal mirror (§5.8), resignation ladder A+B+C (§5.9). The realm-politics step (§5.4) is the sovereign-turn hook that ties treaties/diplomacy/plots together.

---

## 1. Shared preamble

Run the Build Session Protocol (`acks-build-log --for-task "faction realm diplomacy rebellion"`, `--last 1`, `--needs-review`; `acks-conventions --for-task "monthly tick batch, ruler action catalog, migration, EventBus signal"`; `acks-raw-lookup` for every RAW rule — loyalty `ax_reactions`/henchman-loyalty §2.2, DaW conquest `daw_` for war/vassalization, diplomacy modifiers `ax_reactions`).

**Hard constraints:**
- **Determinism** — every loyalty roll, coalition solicitation, treaty renewal, secrecy tick is reproducible from (world state + seeded RNG). No wall-clock. Everything passes on the mock LLM; no LLM call anywhere in FF-3 (narration rides Seam A retroactively, which is L-3's job, not this track's).
- **Banker's rounding** via `MathUtils.bankers_round` (the canonical helper landed in FF-1; conventions §3.3 corrected — do NOT use `roundi()`).
- **No new autoloads.** New services are `RefCounted`/static under `engine/subsystems/factions/` (mirrors FF-1) or `engine/subsystems/realm_ai/` where they extend ruler-AI (diplomacy actions register in `ruler_action_catalog.gd`/`ruler_action_scorer.gd`).
- **Migrations:** use **193** and, if a second file is genuinely needed, **194** — those two numbers ONLY (191 Dialogue, 192 Quest, 195-197 reserved for sibling Wave-1 tracks). Most of §5 rides tables FF-1 already created (`treaties`, `faction_plots`, `faction_plot_members`, `realm_petitions`, `faction_stances`, `faction_events`) and the ruler-AI vassal tables (`vassal_assignments` has `base_loyalty_modifier`/`last_loyalty_roll_day`/`last_loyalty_outcome`; `vassal_obligations`). Add columns only where §5 genuinely needs new state (a compliance-behavior tag on the vassal edge; a rebel-realm-mirror flag; treaty runtime fields the §4.3 schema doesn't already carry — **inspect the FF-1 migrations 188/189 first** to see exactly what `treaties`/`faction_plots` columns already exist before adding any).
- **Shared-file discipline (parallel Wave-1 build).** This track runs in an isolated git worktree concurrently with four siblings. Where you touch a file a sibling also touches, insert your additions as ONE labeled block (`# --- Faction FF-3: realm diplomacy & rebellion ---`) appended after existing content, not interleaved. The shared files for FF-3 are: `engine/autoloads/event_bus.gd` (new realm-politics signals), `engine/autoloads/campaign_repository.gd` (treaty/plot/petition/loyalty CRUD — label your block), `db/schema.sql` (label your appended block), `engine/subsystems/session/handlers/domain_handlers.gd` (the realm-politics monthly step — a sibling Quest track adds a rumor-decay step here too; keep your slot in its own labeled block). Do NOT run the Godot test suite, `--import`, or any Godot process; do NOT edit `build_log.md`/`docs/coding_conventions.md`/`docs/document_map.md` — return a structured report instead (the orchestrator merges + tests + documents centrally).

---

## 2. Build order (one continuous session; internal phases)

**FF-3.a — Vassal loyalty triggers + compliance ladder (§5.2, §5.3).**
- Extend the existing henchman-loyalty roll for vassal edges with the §5.2 PROJECT modifier table (alignment/culture/religion vs. liege, liege-weakness BR ratio, ambition, grievance from `faction_events`, `vassalized_by_war`). Reuse `MathUtils` + the existing loyalty resolver; do not fork a parallel loyalty system (§2.2 / §5.2 are explicit).
- Wire the PROJECT roll triggers (§5.2: liege succession; liege loses a field battle or stronghold; liege breaks a treaty; liege alignment outrage; rebel-coalition solicitation; annual investiture-anniversary if grievance ≤ −3) — subscribe to the existing EventBus signals for these (conquest/battle/succession already emit; find them via `acks-build-log --search`).
- Compliance ladder (§5.3): map the loyalty result band to behavior. **Under-compliance (6–8)** = scalars on the existing muster/tribute resolvers (minimum legal troops, slow march, no volunteer duties) — tribute auto-pay STAYS on the monthly tick (Jedidiah 2026-07-05; do NOT build tribute-withholding). **Resignation (3–5)** → opens the §5.9 lawful-exit ladder. **Hostility (2−)** → seeds a `rebellion` plot (§5.7). Fanatic (12+) → over-compliance (surplus troops, informant).

**FF-3.b — Treaties (§5.5) + diplomacy actions (§5.6).**
- Treaty kinds (`alliance`/`defensive_pact`/`non_aggression`/`protectorate`/`trade_pact`) with their active effects, breach detection, and renewal (2d6 influence-style throw with the §5.6 modifier column; re-check on succession + grievance ≤ −5; fixed-term at expiry). Breaking a treaty writes `treaty_broken` to `faction_events` against the breaker from every realm with `friendly+` stance toward the victim (reputational contagion). `RealmGraph.is_allied()` (currently hard-false until FF-3) now reads active `alliance`/`defensive_pact` treaties.
- Diplomacy actions registered in `ruler_action_catalog.gd` + scored in `ruler_action_scorer.gd`, gated on `diplomatic_weight`/`expansion_weight`, **active-LOD sovereigns only** (§11.2): `propose_treaty(kind)`, `denounce`/`issue_ultimatum`, `declare_war`, `respond_to_call`, `sue_for_peace`. This is the deliberate **war-ceiling raise** for active-LOD sovereigns (§5.6/§11.2, RESOLVED WANTED 2026-07-05) — the ruler-AI v1 "manage-and-defend only" ceiling lifts HERE, for active-LOD sovereigns only; backdrop/regional-LOD rulers keep the defend-only ceiling. `declare_war` emits invasion via army-warfare; `sue_for_peace` produces `non_aggression` or vassalization per DaW (ongoing payment IS vassalage, never tribute-without-fealty).
- Vagaries stay live (§5.6): `alliance_offered` etc. can hand an active-LOD sovereign or the player a ready proposal regardless of AI initiative — don't disable the existing vagary seeds.

**FF-3.c — Realm-politics step (§5.4).** Add a sovereign-only realm-politics step to `RulerAI.process_campaign_month` (sovereigns already take monthly turns): evaluate standing treaties, evaluate received diplomacy proposals, score new diplomatic actions, process plot intelligence (informant reports → counter-plot Favors-&-Duties moves: revoke a plotter's grant, demand hostage duty, pre-emptive tribute relief — arrest is out of v1 scope). Vassals do NOT get a separate step (they act through loyalty/compliance — keeps cost linear).

**FF-3.d — Rebel coalitions (§5.7) + plot secrecy (§7.4 plot half).** The full SEED → SOUND OUT → READY → LAUNCH → RESOLVE machinery on `faction_plots`/`faction_plot_members`:
- SEED on Hostility (2−) or refused-Resignation.
- SOUND OUT: each realm-politics step, solicit ONE candidate co-vassal (lowest loyalty first; border/culture/alignment-affinity candidates only) with a SECRET loyalty roll toward the liege + §5.2 modifiers + momentum (−1 per 2 committed). Outcomes 2−→committed, 3–5→sympathetic, 6–8→silent decline, 9–11→decline + secrecy −1, 12+→INFORMS the liege (exposed).
- READY: coalition power check reusing the §7.3 extraction-resistance formula pattern (rebel_br vs liege federated_br, threshold 0.60 − 0.15×expansion − 0.10×aggressive + 0.15×liege-alliance).
- LAUNCH: on ready + trigger (liege loses battle / succession / tribute hike / 6 months ready) or forced when secrecy hits 0 — committed domains flip to a NEW rebel realm-mirror faction (`FactionRegistry.ensure_realm_mirror` pattern), `realm_relations(rebels, liege) = hostile`, war via army-warfare.
- RESOLVE: victory re-parents vassal chains (the realms-titles re-parenting path); defeat applies DaW conquest at the liege's crisis_response discretion. Ledger entries for every participant + observer.
- Plot secrecy countdown (§7.4): starts 10 + instigator self_interest adj; −1 per solicitation loose-talk / covert op / rumor emitted; −2 on spy-find; at 0 → exposed (force-launch or collapse). A realm whose history log shows ≥3 rebellions gets a small materialization volatility bump (PROJECT CALL, §11.4).

**FF-3.e — Player-as-vassal mirror (§5.8) + resignation ladder A+B+C (§5.9).**
- Player-as-vassal: a PC/party-member who swears fealty gets a `faction_memberships` row (`role='vassal'`) in the liege's realm faction, receives the monthly d20 Favors & Duties roll from the NPC liege (reuse `favors_duties_resolver.gd`, same RAW table), and answers demands through play — refusal writes grievance and may trigger revocation/outlawry through the liege's realm-politics step. Rebellion plots may solicit a player-vassal (solicitation surfaces as content; the player's join/decline/inform writes the same plot-member rows an NPC roll would).
- Resignation ladder on `realm_petitions` (the table exists): **Path A — Petition the liege** (`kind='release'` re-parent within realm / `kind='transfer'` to a named liege; liege resolves on their realm-politics step: grant / buy-off via a Favors-&-Duties office grant / refuse). **Path B — Appeal to sovereign** (`kind='appeal'`, multi-tier realms after refusal — THE FF-3 addition; sovereign adjudicates by loyalty record + culture/alignment affinity + power + disposition; siding-with-vassal re-parents to crown AND hands the intermediate liege a grievance against both; siding-with-liege deepens grievance → path C or rebellion). **Path C — Abdicate into exile** (domain reverts to liege; ex-vassal becomes a landless Tier-A NPC with treasury + retinue — inert-but-present until `gdd-npc-agency.md` lands). Ladder not menu: an NPC tries A before C unless disposition says otherwise (high self_interest + wealth → skip to C; high societal_orthodoxy → exhaust A then B).

---

## 3. Acceptance bar

- A vassal loyalty roll fires on each §5.2 trigger with the full PROJECT modifier stack, deterministic from seed; the compliance ladder maps each result band to the specified behavior (under-compliance scalars visible on muster; 2− seeds a plot; 3–5 opens a petition). Tribute auto-pay is untouched.
- Treaties: each kind's active effect holds; `is_allied()` reads them; breach detection fires; renewal rolls correctly; `treaty_broken` contagion writes to every friendly-toward-victim realm's ledger. Determinism.
- Diplomacy actions score and execute for active-LOD sovereigns only; `declare_war` emits an army-warfare invasion; `sue_for_peace` produces non_aggression-or-vassalization; backdrop/regional rulers still cannot select them (the LOD gate holds).
- The Orso worked example (§7.5) reproduces end to end as an integration fixture: forced loyalty roll → Hostility → plot SEED → multi-turn SOUND OUT with the exact roll outcomes → READY at the computed threshold → LAUNCH on the trigger → rebel realm-mirror created, `realm_relations(rebels, liege)=hostile`. (The org-side "Orso question" allegiance evaluation is FF-4 — assert only the realm-layer beats here.)
- Player-as-vassal receives the monthly Favors-&-Duties roll and a rebellion solicitation writes plot-member rows on a player join/decline/inform. Resignation A → B → C each resolve per §5.9 (A grant/buy-off/refuse; B sovereign adjudication with the intermediate-liege grievance; C revert + landless-NPC record).
- Save/load mid-rebellion (brewing / ready / launched) restores exact plot + coalition + secrecy state. Determinism: identical seed → identical loyalty/coalition/treaty history.
- **Do NOT run the suite** — write + register the test suites (4-edit pattern) but leave execution to the central orchestrator. Report readiness.

---

## 4. Report back (structured — no local build_log/conventions edits)

Return: files created/modified, migrations used (193 and/or 194), completed summary, decisions (esp. any §5 ambiguity you resolved and how the FF-3/FF-4 boundary landed in code), interfaces defined (exact signal signatures, method signatures, new columns), database changes, tests added (registered, unexecuted), known issues + any `[NEEDS-OPUS-REVIEW]`, and proposed `docs/coding_conventions.md` additions (the realm-politics monthly-step pattern; the plot/secrecy state machine; the compliance-ladder scalar pattern; treaty-contagion ledger writes).

## 5. Quick interface index (verify against code before use)

- `engine/subsystems/realm_ai/`: `ruler_action_catalog.gd` (register diplomacy actions), `ruler_action_scorer.gd` (score them, weight-gated), `ruler_ai.gd` (`process_campaign_month` — add the realm-politics step), `favors_duties_resolver.gd` (player-as-liege machinery to mirror for player-as-vassal), `ruler_lod_manager.gd` (active-LOD gate — never bypass), `realm_graph.gd` (`is_allied()` — currently hard-false, now reads treaties), `realm_repository.gd` (`set_relation`/`get_relation` — has FF-1.3's `RealmRelationsDrift` as its writer now).
- `engine/subsystems/factions/`: `faction_registry.gd` (`ensure_realm_mirror` — reuse for rebel realm-mirror), `default_stance_evaluator.gd`, `realm_relations_drift.gd`, `faction_event_ledger.gd` (`record` — write treaty/rebellion ledger entries), `faction_stance_service.gd`.
- Tables (all exist): `treaties`, `faction_plots`, `faction_plot_members`, `realm_petitions`, `faction_stances`, `faction_events`, `vassal_assignments` (`base_loyalty_modifier`/`last_loyalty_roll_day`/`last_loyalty_outcome`), `vassal_obligations`, `faction_memberships` (`role` column for `role='vassal'`).
- Monthly tick host: `engine/subsystems/session/handlers/domain_handlers.gd::_handle_monthly_tick` — commerce → syndicates → venturers → domain resolution → `RulerAI.process_campaign_month` → threat escalation → (FF-1.3) faction/relations maintenance. Add the realm-politics step inside the RulerAI sovereign turn, not as a separate tick pass.
- Migrations 188/189 (FF-1) — **read these first** to see the exact `treaties`/`faction_plots`/`realm_petitions` columns that already exist before adding any.
