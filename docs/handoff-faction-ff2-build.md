# Build Handoff — Faction FF-2 (Organizations) + Quest-Rumor Q-6 (faction bridge)

**Authoring session:** 2026-07-08 (Opus recon). **Track A of Wave 2** in `docs/master-build-plan-social-llm-stack.md` §4.
**Model guidance:** Opus for the tithe-apportionment economics (§6.4) and the Q-6 faction-goal predicate; Sonnet-grade for the CRUD/seeding/journal plumbing. One build agent runs the whole track sequentially (FF-2.0 → FF-2.3 → Q-6) because FF-2 and Q-6 are tightly coupled (`post_job` produces what `create_faction_quest` mints).

> **CRITICAL — do NOT run tests.** This is a parallel-wave build. Do not launch Godot headless, the godot-ai MCP, or any test runner — concurrent Godot runs crash on the shared `user://` DB. Use `--check-only -s res://<file>` for syntax verification ONLY (single-shot, no scene tree). The orchestrating session runs the full suite centrally after all Wave-2 agents finish. **Commit your work at the end and report the commit SHA.**

---

## 0. Shared preamble (read before writing code)

1. `CLAUDE.md` (document authority; Godot/SQLite constraints; banker's rounding via `MathUtils.bankers_round`, NOT `roundi()`).
2. `acks-conventions --for-task "faction organizations org turns tithe apportionment"` and `--section 89` through `100` (ruler-AI + army-warfare monthly-batch + Seam-A narrator conventions this build mirrors).
3. `generation/gdd-faction-framework.md` — the authority. Sections you will implement: **§6 (the whole Organization Layer)**, §7.2 (default-stance function — already built by FF-1; reuse), §10.1/§10.3/§10.4 (surfacing), §11.1–§11.6 (scheduling/LOD/signals). Read §13 (phasing) to hold the FF-2/FF-4 line (below).
4. `docs/handoff-quest-rumor-build.md` §8 (Q-6) + §10 (interface index).
5. RAW via `acks-raw-lookup`: tithe expense `acore_axioms_strongholds_and_domains.xml:183-264`; congregant/proselytize math `ax_reactions`/religion refs in §2.5; henchman monthly fee table `acore_henchmen_monthly_fee_table.xml:20-36`; criminal-guild level pyramid `acore-setting-construction-rules.xml:523-561`.

### Authority line — what is FF-2 vs FF-4 (do NOT overreach)

FF-2 delivers (per §13): **org seeding, org turns + action vocabulary, temple rivalry incl. tithe apportionment + the player-ruler UI contract, `post_job` quest bridge, membership/ranks/services, faction journal data contract.**

**FF-4 (NOT this build)** owns: the allegiance engine + feign/betrayal, the covert-op menu (§6.7), secrecy/discovery, divided-loyalty events. Therefore in the §6.5 action vocabulary, the two actions that reduce to FF-4 machinery — **`undermine_rival`** (a §6.7 covert op) and **`declare_stance`** (runs the §7 allegiance evaluator) — are **registered in the vocabulary but their handlers are inert stubs** in FF-2 (log "deferred to FF-4", take no effect, never selected by the scorer because their goal-relevance is 0 until FF-4). Everything else in §6.5 reduces to already-built mechanics and is fully implemented here.

### Schema is already built

FF-1 (migrations 188/189) + FF-3 (193) created the **entire §4 data model**: `factions` carries `scope/treasury_gp/member_count_abstract/power_rating/goal_primary/goal_secondary/status/volatility/seat_poi_id/seat_settlement_id/religion_id/culture_id/personality_weight_biases`; `faction_memberships` carries `rank/loyalty_mod/standing/is_secret/joined_day/status`; `faction_stances`, `faction_events`, `faction_plots`, `domain_tithe_shares`, `treaties`, `realm_petitions` all exist. **`quests` already carries `questgiver_faction_id` + `faction_goal_id` (migration 192).**

**Therefore FF-2 + Q-6 should add ZERO new migrations on the happy path.** Add a migration (assigned range **195–197**) ONLY if you discover a genuinely missing column while building; prefer reusing existing tables and a data-defined JSON for the service/rank menus. If you add one, doc-sync `db/schema.sql` and register any new table in `CampaignRepository._SCOPE_DIRECT_CAMPAIGN` + purge cascade.

### Reuse, don't reinvent (FF-1/FF-3 built these)

- `engine/subsystems/factions/faction_registry.gd` — realm-mirror lifecycle (`ensure_realm_mirror`, `is_realm_mirror`). **Extend it (or add `org_registry.gd`) for org seeding/accessors.**
- `default_stance_evaluator.gd` — the §7.2 default-stance function (temple rivalry bias, nemesis-family hostility). **Reuse for org-pair stances; do not re-derive.**
- `faction_event_ledger.gd` — the §4.5 grievance/favor ledger writer. **Reuse for `patronage_granted`/`congregants_poached`/`aided` writes.**
- `faction_stance_service.gd`, `political_audit.gd` — stance accessors + audit.
- `NpcSyndicateMonthlyResolver.process_campaign_month(campaign_id)` — the exact monthly-batch shape to mirror for `FactionAI`; syndicate income is already resolved here (do NOT double-resolve syndicate treasuries — orgs of `type='syndicate'` read their treasury from the syndicate resolver, per §6.6).
- `RulerActionNarrator` (`engine/subsystems/realm_ai/ruler_action_narrator.gd`) — clone verbatim for `FactionActionNarrator`.
- `RulerAI.process_campaign_month(...)` scorer shape (`utility = base_value × goal_relevance × leader_weight × situational_modifiers`, seeded tiebreak) — mirror for org action selection.

---

## 1. Session map

| Session | Delivers | Key GDD |
|---|---|---|
| **FF-2.0** Seeding | promote syndicate seeds → org factions; temple seeding per religion presence; other-type presence gating; goal assignment; leader/officer materialization (Tier-B); parent chains; tithe-share defaults at materialization | §6.1, §6.2, §6.3, §6.4 (defaults), §4.9 |
| **FF-2.1** Membership, ranks, services, journal | rank ladders per type; join/rank/standing lifecycle; service menu (data-defined); faction-journal data contract (met-only, public knowledge) | §8.2, §8.5, §10.4, §4.4 |
| **FF-2.2** The org month | `FactionAI.process_campaign_month`; the §6.6 abstract ledger (¼-wages rule; syndicate = RAW resolver passthrough); the §6.5 action vocabulary (buildable subset); affordability gate; `faction_action_taken` + Seam-A narration | §6.5, §6.6, §11.1–§11.3, §10.1 |
| **FF-2.3** Temple rivalry + tithe | proselytize poaching math; the tithe-apportionment engine (`issue_decree(tithe_apportionment)` decree kind, shared player/NPC path); the `court_patron` tithe-lobbying loop; `FactionActionNarrator`; the player-ruler Tithe panel **data contract** (→ `gdd-domain-tab.md`) | §6.4, §6.5 (`court_patron`, `proselytize`), §4.9 |
| **Q-6** Faction bridge | `create_faction_quest`; `faction_goal` completion polling in `QuestCompletionWatcher`; turn-in `faction_events` ledger write; `advances_faction_goal`; `_wrap("quest"/"rumor")` prose; Quests-tab data binding | quest-rumor §11.2/§7.9/§11.5/§11.4; faction §6.5(`post_job`)/§6.6/§4.5 |

---

## 2. Session FF-2.0 — Seeding

**Goal.** Bring organizations into existence at settlement materialization, extending settlement stocking.

**Build (§6.2 procedure, verbatim order):**
1. **Syndicate-seed promotion.** Existing settlement-stocking syndicate seeds (name/territory/leader/style) → `factions` rows with `scope='organization'`, `faction_type='syndicate'`; size/boss level per the market-class table (`rules/acore-setting-construction-rules.xml:496-561`). These orgs' treasuries are resolved by `NpcSyndicateMonthlyResolver` (do not add a second income path).
2. **Temples.** For each religion with a conversion-state presence in the domain (religion GDD state), one `temple` faction per deity actually worshipped; the **dominant** temple gets the settlement's temple PoI as `seat_poi_id` (reuse `settlement_pois.owner_faction_id` per §4.7 errata — do NOT add a column).
3. **Other types** (`mage_guild`/`mercenary_company`/`knightly_order`/`merchant_guild`/`holy_order`): gate by the §6.1 presence column (market class), then roll `1d6 ≥ threshold` per type (PROJECT CALL constant, seeded RNG) so not every qualifying market has every org.
4. **Leadership.** Reuse the `ClassedNpcBuilder` Tier-B path (settlement stocking §13) for a leader + one officer; rank-and-file stay `member_count_abstract` until proximity forces materialization.
5. **Stances.** NOT pre-computed. Same-settlement org pairs instantiate lazily on first faction turn via `DefaultStanceEvaluator` (§7.2 — already handles the co-aligned-temple rivalry bias and nemesis-family hostility). Do not pre-seed stance rows.
6. **Parent chains.** Temples of the same deity within one realm link to a realm-church parent faction (culture-flavored name); MC I–II syndicates may roll into a criminal-guild parent (§2.4). Parent linkage via a `parent_faction_id` — **check if the column exists**; if not and you need it for orgs, that is the one candidate migration (195).
7. **Goals** (§6.3). Assign `goal_primary`/`goal_secondary` from type + leader `StrategicDisposition` (already generatable) per the §6.3 table.
8. **Tithe-share defaults** (§6.4/§4.9). At materialization, seed `domain_tithe_shares` for the domain's temple factions: congregant share, biased **+10 points** (PROJECT CALL) toward the ruler's own deity's temple, normalized to sum 100, banker's rounding.

**Backfill.** The same procedure runs once for already-materialized settlements, keyed to a migration/backfill flag (mirror the ruler-AI backfill precedent).

**Determinism** is the acceptance gate: same seed → identical org roster, identical goals, identical tithe defaults.

---

## 3. Session FF-2.1 — Membership, ranks, services, journal

**Ranks (§8.2).** Each org type has a small rank ladder (index → title). Store as a **data-defined JSON** (`data/factions/org_types.json` or similar) keyed by type: rank titles, join criteria (class families per §6.1), and the service menu. `faction_memberships.rank` indexes it; `role` keeps named posts (`leader`/`officer`/…).

**Lifecycle.** Join → `status='petitioner'`→`'member'`; `standing` is the merit ledger (dues/jobs/offenses); `loyalty_mod` is the henchman-loyalty-style modifier (NOT a score) resolved at trigger events via the existing henchman-loyalty machinery (one mechanic — do not invent a faction loyalty roll). Expel/suspend/leave transitions write the ledger.

**Services (§8.5).** The service menu is what membership *feeds*: e.g., temple → healing/consecration access; mage_guild → spell/identify service; syndicate → fence/hijink hire; merchant_guild → loan/trade terms. FF-2 registers the menu data contract and the eligibility check (`is_member(character_id, faction_id) && rank >= service.min_rank`); the actual service resolutions already live in their subsystems — wire the gate, don't rebuild the service.

**Faction journal (§10.4) — DATA CONTRACT ONLY.** A read model over the party's **knowledge store** for factions the party has **met**: name, type, seat, leader-if-known, public stance toward the party's affiliations, per-member membership/rank/standing, treaties/postures the party has *learned* (event-sourced from log entries + revealed secrets). **Never reads `faction_stances.true_stance`.** Expose `FactionJournal.entries_for_party(party_id) -> Array` returning only met-and-public data. UI layout belongs to the journal-tab GDD; ship the accessor + a headless test that proves no `true_stance` leaks.

---

## 4. Session FF-2.2 — The org month

**`FactionAI.process_campaign_month(campaign_id, calendar_day, active_settlements) -> Array`** — same signature shape as `RulerAI.process_campaign_month`. Slots into `domain_handlers.gd::_handle_monthly_tick` **immediately after** the `NpcSyndicateMonthlyResolver` call (`domain_handlers.gd:106`) and before RulerAI. Gated to **active-LOD** settlements (§11.2 — inherits ruler-AI LOD wholesale; backdrop orgs take no turns and auto-stabilize).

**Order within the pass (§6.6):** resolve the ledger (income first), THEN select one action within means.

**The abstract ledger (§6.6).**
- `syndicate` + `merchant_guild` (Venturer-class syndicate, 2026-07-05 ruling): treasury already resolved by `NpcSyndicateMonthlyResolver`/`VentureMonthlyResolver` — **passthrough, do not re-resolve.**
- Every other type: **monthly net profit = ¼ × Σ(members' monthly wages)**, banker's rounding, accumulating in `treasury_gp`. Wages come from the Henchman Monthly Fee table (`acore_henchmen_monthly_fee_table.xml:20-36`; values already in `data/equipment/provisions_services.json`): L0 12 / L1 25 / L2 50 / L3 100 / L4 200 / L5 400 / L6 800 / L7 1600 / L8 3000 / L9 7250 / L10 12000 / L11 32000 / L12 50000 / L13 135000 / L14 350000 gp. `member_count_abstract` prices through the RAW criminal-guild pyramid mix (45% L0 / 35% L1 / 12.5% L2 / 7.5% L3+). The faithful (holy_order/knightly_order unpaid members, §2.5) contribute 0.
- Temples add the **tithe apportionment share** on top (built in FF-2.3).
- **Failure mode preserves RAW:** negative treasury → congregants depart 1d10/1,000gp unpaid (§2.5), unpaid members roll loyalty, `survive` goal activates. **Affordability gate:** an action is a candidate only if `cost_gp ≤ treasury + expected_net`; treasury under 3 months' expenses auto-activates `survive`.

**The action vocabulary (§6.5) — one action/turn (large parent/MC I-II orgs may take two):**

| Action | FF-2 status | Reduces to |
|---|---|---|
| `recruit_members` | BUILD | +1d(size-tier) `member_count_abstract`; costs recruiting gp; caps per §2.4 market-class table for syndicates |
| `raise_funds` | BUILD | the type income model; syndicate hijink month uses the RAW resolver + the §2.3 spy penalty when domain morale ≥ +1 |
| `proselytize` | BUILD (FF-2.3) | RAW congregant math (§2.5); temples/orders only |
| `court_patron` | BUILD (FF-2.3) | influence attempt on the local ruler; temples petition tithe-share points |
| `post_job` | BUILD (Q-6) | `QuestRegistry.create_faction_quest(...)`; **the main player-facing surface** |
| `aid_faction` | BUILD | gp/troops/intel transfer to a friendly+ faction; writes `aided` ledger |
| `go_underground` / `relocate` | BUILD | status flip; seat change (survival moves) |
| `hold` | BUILD | nothing; banks treasury (anti-thrash floor) |
| `undermine_rival` | **STUB → FF-4** | §6.7 covert op — inert handler, goal-relevance 0 |
| `declare_stance` | **STUB → FF-4** | §7 allegiance evaluator — inert handler, goal-relevance 0 |

**Scoring** mirrors the ruler planner: `utility = base_value × goal_relevance × leader_weight × situational_modifiers`; seeded RNG tiebreak; deterministic execution; emit `faction_action_taken(faction_id, action_id, outcome)`; retroactive Seam-A narration when player-relevant (FF-2.3 narrator).

**Director caps (§11.3):** org covert ops ≤ 1/month each (moot until FF-4); keep the scorer legible.

---

## 5. Session FF-2.3 — Temple rivalry + tithe apportionment

This is the Opus-weight session. Read §6.4 in full before coding.

**Proselytize poaching (§6.4).** `proselytize` yields `1d10+CHA` congregants per 1,000gp spent; when a same-alignment-family rival temple is present, **50/50** of new congregants come from unconverted pool vs. the rival's roster (poaching writes `congregants_poached` to the ledger against the rival). Unpaid upkeep bleeds `1d10` per 1,000 (§2.5).

**The tithe apportionment engine (§6.4/§4.9) — the central prize.**
- The domain's RAW tithe expense (1gp/family/month) is divided among the domain's temple factions by `domain_tithe_shares.share_pct` (integer points summing to 100). **Paying the tithe at all stays RAW** (unpaid → −1 domain-morale roll); apportionment divides only the *paid* stream — a ruler can lawfully starve one temple to feed another.
- Re-apportionment is a **decree**: `issue_decree(tithe_apportionment)` — a **new decree *kind* riding the existing `issue_decree` handler** (additive, exactly the `decree_kind` pattern the Seam-A wiring already uses; grep the ruler-AI decree handler and add the kind, do not fork it). The decree logs to the event log like any other.
- **ONE shared engine path** for player and NPC rulers. NPC rulers re-apportion in response to lobbying, on succession (favor own deity), on religion/advisor change, or when a temple is destroyed/underground.
- Every shift writes the ledger: `patronage_granted` to the winner; grievance to the losers against **both** the winner and the ruler.

**Player-ruler Tithe panel — DATA CONTRACT (this GDD owns it; layout → `gdd-domain-tab.md`).** For any domain the player rules, expose the contract the panel binds to: the temple factions present, each one's **congregant share** (the fairness reference), current `share_pct`, a gp/month preview per temple at a candidate apportionment, and a Confirm that constrains points to sum to 100 and issues the **same** `issue_decree(tithe_apportionment)` path. Add the required section stub to `gdd-domain-tab.md` (a short "Tithe Apportionment panel" section citing this contract). Ship the engine accessor `TitheApportionment.panel_model(domain_id) -> Dictionary` + the `apply(domain_id, {faction_id: pct})` validator (sum-100, temple-present, banker's-rounded gp preview). Temple reactions (ledger, lobbying) fire identically regardless of who decreed.

**The lobbying loop (`court_patron` tithe payload).** A temple petitions for +X points. Resolution is an Axioms influence attempt (§2.1) on the ruler, modified by: congregant-share-vs-current-share (fairness), ruler religion/alignment match, consecration/spiritual-advisor standing, gifts (bribery pattern), grievance history, and rival counter-lobbying (a rival's same-season `court_patron` imposes −2). Success → the ruler decrees the shift on their next turn.

**`FactionActionNarrator` (§10.3).** Clone `RulerActionNarrator` verbatim: deterministic `template_narration(action_id, context)` first, LLM flavor via `generate()` when `LLMManager.is_configured()`, `is_fallback`-safe, cache-keyed per (faction, day, action). Add narration templates for the org actions (`data/templates/faction_action_templates.json`, mirroring `ruler_action_templates.json`). **Relevance gate:** only active-LOD factions with player awareness (met / same settlement / instantiated party stance) reach the log — the anti-spam rule the ruler seam proved. Wire it into `GameLog` on `faction_action_taken` exactly as `RulerActionNarrator` wires on `ruler_action_taken`.

---

## 6. Session Q-6 — Faction post_job bridge + narration

Build against `docs/handoff-quest-rumor-build.md` §8 + `generation/gdd-quest-rumor-system.md` §11.2/§7.9/§11.5/§11.4. **The linkage columns already exist** (`quests.questgiver_faction_id`, `quests.faction_goal_id`, migration 192); the stubs `QuestRegistry.create_faction_quest`/`advances_faction_goal` exist (quest_registry.gd:428/436) — fill them.

- **`create_faction_quest(faction_id, front_npc_id, goal, terms) -> String`** — mints a `faction_goal`-or-typed quest with `questgiver_faction_id` set, reward drawn **against the org treasury** (faction §6.6 affordability — reject if insolvent), and `faction_goal_id` set when success is a faction predicate. **Reward forms (O-Q12/O-Q13): gold only for now; NEVER membership/rank** (per-character, level/class-gated) — guard the impossible (no party-wide membership; a domain reward still forces a single owner, §9.6). Improved faction standing is the separate ledger side-effect, additive to the reward. Use **Opus** for the `goal` → quest-shape predicate mapping (§7.9).
- **`faction_goal` completion polling** in `QuestCompletionWatcher` (from Q-4) — poll the faction layer's goal state keyed by `faction_goal_id`; fire **once** (idempotent).
- **Turn-in ledger write** — on `quest_turned_in` for a faction quest, write a `patronage_granted`/`aided` `faction_events` row (§4.5); optionally decorate via the faction's `FactionActionNarrator`.
- **`advances_faction_goal(issue, faction_id) -> bool`** — the dialogue status-differential relevance check (faction §6.5); returns true when the issue advances the faction's `goal_primary`.
- **Narration** — `narrative_generator.gd::_wrap(kind, subject_id, template_body, context)` (verified at `narrative_generator.gd:371`) with `kind="quest"`/`"rumor"` to fill `setting_narrative:quest`/`:rumor` (reserved, migration 159). **Contract:** LLM fills only prose columns; the deterministic placeholder is the final text on failure/absence.
- **Quests-tab data binding** (`gdd-quests-tab.md`): the tab reads `quests`/`rumors` and renders Active/Available/Completed/Failed/Rumors sub-tabs (display only; no generation).

---

## 7. Acceptance bar (verify by reading code + `--check-only`, NOT by running tests)

Write these tests (the orchestrator runs them). Register each new suite in `tests/test_runner.tscn` + `test_runner.gd` using **ext_resource ids starting at 529** (Track A's reserved block, to avoid colliding with Track B at 540).

- **Seeding determinism:** same seed → identical org roster/goals/tithe defaults over a 3-settlement region; syndicate seeds promoted; dominant temple owns the temple PoI; tithe shares sum to 100 with the +10 ruler-deity bias.
- **Org month:** ¼-wages ledger correct (banker's rounding) for a non-syndicate org; syndicate passthrough (no double-resolve); affordability gate blocks an unaffordable action; `hold` banks; `faction_action_taken` fires; negative-treasury failure fires the RAW consequences.
- **Temple rivalry:** proselytize poaches 50/50 with `congregants_poached` ledger; `court_patron` tithe lobbying resolves an influence attempt and (on success) the ruler's decree shifts points with `patronage_granted` + grievance writes.
- **Tithe engine:** `issue_decree(tithe_apportionment)` (shared path) re-apportions, sums to 100, logs to the event log; `TitheApportionment.apply` rejects a non-100 sum and a non-present temple; gp preview banker's-rounded.
- **Narrator:** `FactionActionNarrator` `is_fallback`-safe; relevance gate suppresses non-player-relevant factions; no `true_stance` in any payload (grep-proof).
- **Membership/journal:** join→member→rank/standing transitions; service eligibility gate; `FactionJournal.entries_for_party` returns met-only, public-only (no `true_stance`).
- **Q-6:** `post_job` mints a solvent faction quest against the treasury (insolvent → rejected); `faction_goal` completion fires once; `quest_turned_in` writes the faction ledger; `advances_faction_goal` correct; `_wrap` fills prose on mock with placeholder fallback; Quests-tab binds.
- **FF-4 line held:** `undermine_rival`/`declare_stance` are inert (never selected, no effect).

---

## 8. Interfaces to record in the build-log entry (so Dialogue/FF-4/Q consumers wire against real shapes)

`FactionAI.process_campaign_month(campaign_id, calendar_day, active_settlements) -> Array`; `OrgSeeder.*` (or `FactionRegistry.*`) seeding entry points; `TitheApportionment.panel_model(domain_id)` / `.apply(domain_id, shares)`; `FactionJournal.entries_for_party(party_id)`; `FactionActionNarrator.narrate_action(...)` (Seam-A clone); the `issue_decree` new `decree_kind='tithe_apportionment'`; `QuestRegistry.create_faction_quest(faction_id, front_npc_id, goal, terms)` + `advances_faction_goal(issue, faction_id)`; new signals `faction_action_taken`, `faction_membership_changed` (declare in `event_bus.gd` — a clearly-labeled `# --- Wave 2 FF-2 ---` block). Record any migration you added (195–197) and any new data file.

**Commit** all work at the end (`git add -A && git commit -m "Wave 2 FF-2 + Q-6 (worktree build)"`) and report the commit SHA + this interface list.
