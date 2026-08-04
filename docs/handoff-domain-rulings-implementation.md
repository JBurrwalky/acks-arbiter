# Domain Rulings — Implementation Handoff

**Date:** 2026-07-31
**Companion to:** `docs/domain-acquisition-audit-2026-07-28.md` (the audit; its §5 carries the rulings verbatim)
**Purpose:** Turn Jedidiah's seven rulings into sequenced, implementable work. Scoped by three parallel agents reading the current working tree on `dungeon-refactor`; every file:line below was read, not inferred.

---

## The sequencing is forced, and it is NOT the audit's tier order

```
Tier-0 arithmetic fixes  ──►  R-2 (cp)  ──►  R-4 (ruler promotion)  ──►  R-1 (vassal_assignments)  ──►  R-5 / R-6 / R-7
                                                                              ▲
                                                                              └── MUST ship with the cascade-scoping fix
```

Why each arrow is hard:

- **Tier-0 first.** While `domain_handlers.gd:332`'s double `* 100` keeps the income gate permanently open, *no* stronghold-gated or income-derived behaviour can be observed correctly — including domain XP. Nothing downstream can be tested until this lands.
- **R-2 before R-7.** Domain XP is computed from a cp net income and fed to a gp threshold table, and tribute-in is passed in gp into a parameter named `tribute_in_cp`. R-7's "must include tribute received" is *already structurally true* — the formula needs no change. What it needs is R-2's normalisation, or the tribute line is wrong by 100×.
- **R-4 before R-1 — a total block, not a partial one.** `vassal_assignments.liege_character_id` and `.vassal_character_id` are both `NOT NULL REFERENCES characters(id)` (`db/schema.sql:2151-2152`). Generated domains have `owner_character_id: null` on **both** ends. R-1 can mint **zero** rows until R-4 gives every liege-bearing domain an owning character.
- **R-1 before R-5.** R-5 rolls loyalty on vassal edges. In a generated world there are none.

### R-1 is dangerous to land alone

Turning on `vassal_assignments` makes `LifecycleHandler._cascade_vassals` **live**, and its Case 1 is liege-**wide** by character (`lifecycle_handler.gd:417-421`). Losing one frontier barony would destroy the entire realm of every NPC duke in the world, on the first conquest after the change. **Audit Tier-1 item 6 (scope the cascade to the lost domain) must ship in the same wave**, together with the fix to `tests/test_lifecycle_conquest_outcomes.gd:153-163`, which currently asserts the broken behaviour.

### Two throttling risks that R-1 creates

1. **The Favors & Duties d20 storm.** `_resolve_favors_and_duties` (`domain_handlers.gd:542`) runs inside `_resolve_domain_month`, for every non-terminal domain, keyed on `owner_character_id` rather than on the domain — so a ruler holding N domains rolls the full F&D table for every vassal **N times per month**. Today it returns `[]` and is invisible. After R-1 it fires for every NPC vassal edge in the world, monthly, with real treasury transfers (gift, loan), recurring expenses (scutage) and scheduled events (call to arms) across hundreds of off-camera realms. **Hoist the roll out of the per-domain loop into a per-RULER pass, and gate it on the ruler LOD tier, in the same wave.**
2. **Tribute-in recursion blow-up.** `_compute_tribute_in_for_ruler` (`:1088-1095`) calls `RealmAggregator.aggregate` once per assignment, and `aggregate` runs `_recursive_realm_sum` to depth 8 with one SQL query per node — O(domains × vassals × subtree) per month.

`vassal_obligations` also grows unboundedly (every non-revoke result inserts an ongoing row); it needs a retention policy for backdrop realms.

---

## R-2 — Copper pieces canonical

**Now a standing convention: `docs/coding_conventions.md` §127** (added 2026-07-31). §56 has been annotated to withdraw its gp-native-internal-math allowance.

**Current state: the codebase is already ~80% cp-canonical**, but by convergence rather than by rule — an unfinished refactor (Migrations 110–117, closed as §56) converted character wealth, commerce, troops, henchmen, sieges, faith, syndicate and the domain treasury to integer cp and left the rest gp-native. `db/schema.sql` has **43 `*_cp` INTEGER columns against 11 gp-named monetary columns**, two of which are `REAL`. `Currency.format_cost` is a real canonical helper with 176 call sites across 59 files.

**The damage is not "still in gp" — self-consistent gp islands are harmless once renamed. The damage is at the seams.**

### P0 — four lines in one file, no migration, ships alone

All four live in `engine/subsystems/session/handlers/domain_handlers.gd`. This is where the actual damage is:

| Line | Bug | Effect |
|---|---|---|
| 332 | `_stub_stronghold_value(domain_id) * 100` — the source already returns `SUM(cp_value)` | 100× inflation; every domain with any stronghold reads sufficient; income gate always open; insufficient-stronghold morale penalty never applies |
| 360 | `tribute_aggregate.get("total_received_gp", 0)` passed into a parameter declared `tribute_in_cp` | every liege's tribute income is 100× too small in revenue, ledger, treasury and XP |
| 368 / 1120 | `TributeCalculator.compute_tribute_base_gp` written into `tribute_out_owed` (which the materializer writes in cp) | the column's meaning depends on which subsystem wrote last |
| 660 | `var domain_xp: int = maxi(0, net)` — cp income, never routed through `XPAwardCalculator`, gp threshold never applied | XP 100× too large and the per-level threshold never fires |

Also at 662: `int(round(...))` violates the project's banker's-rounding rule (§12) — use `MathUtils.bankers_round`.

### P1–P4 — the rest of the sweep

- **P1** (~9 files, no migration): display-boundary fixes — `status_header.gd:104-109`, `realm_sub_tab.gd:195-203`, `commission_wizard.gd:307-348`, `overview_sub_tab.gd:502-507`, `hiring_panel.gd:159`, `issue_decree.gd:50-56`, `manage_stronghold.gd` (5 sites), `favors_duties_card.gd`. Delete `EquipmentCatalog.format_cost` and redirect its 5 call sites to `Currency.format_cost`.
- **P2** (1 autoload + ~12 emitters/consumers): rename six gp-named EventBus signal parameters; convert `cache_raided(..., value_lost_gp: float)` (`event_bus.gd:432`) to `value_lost_cp: int` — the only float money on a public contract.
- **P3** (migration 212, 11 columns, ~35 files): gp→cp column conversions. Two self-contained islands do most of the work — `factions.treasury_gp` (~8 files) and the magical-research `gp_cost_*` family (~6 files) — plus `domains.tribute_out_owed`, `domain_grants.stronghold_value`, `settlement_entrances.cumulative_investment_gp`, `domain_extraction_ledger.cumulative_extracted_gp_per_family` (REAL→INTEGER), `quest_rewards.gold_value`/`total_gp_value`, `settlement_pois.gp_value`, `settlement_poi_spell_offers.unit_cost_gp`.
- **P4** (~10 files): the activity action vocabulary (`gp_committed`, `gp_invested`) — a registered cross-system contract per CLAUDE.md step 11, and the only place a unit lives inside a *string-encoded formula* (`"ceil(gp_committed / 500)"`), which no `* 100` grep will find.

**Size:** ~60–80 production files and ~350–450 call sites, plus ~86 test files, plus one migration. Raw upper bound is 124 files / 1,003 `*_gp` occurrences in `engine/` + `scenes/`, but ~40% of those are already-correct boundary conversions, RAW-citation comments, or non-monetary.

**Correction to the audit:** `CampaignRepository.adjust_domain_treasury` already takes `delta_cp` (`campaign_repository.gd:2303`) and is clean. Conventions §31's `delta_gp` signature is stale documentation, not a code bug.

### Subsystems already clean (skip them)

Currency/coins/inventory valuation · PartyWallet + character wealth · shop/market/merchandise pricing · the faith block · crime & punishment · troop and army wages/supply · henchman wages & lifecycle · sieges & supply · ships/cargo/shipping · the domain ledger and treasury mutation path · `data/equipment/*.json` and `data/commerce`.

---

## R-4 — Complete the M2b-2 ruler promotion

**Blocks R-1 entirely.** Must cover **both ends of every edge** — a partial promotion (e.g. only located/on-map domains) leaves the abstract 24-mile ladder unmintable and the realm tree half-recorded.

Sites writing `owner_character_id: null`: `setting_materializer.gd:1581` (`_create_sub_domain`), `:1844` (`_create_sub_clanhold`), `:2623` (`_create_crown_domain`), `:2682` (`_create_ladder_for_polity`). Only sovereign topo-roots get a ruler today (`ruler_by_pid` is populated only inside `if is_sovereign:` at `:417-421`).

**Hard constraint:** `idx_vassal_assignments_unique_active(liege_character_id, vassal_character_id) WHERE status='active'` permits only one active edge per character pair — **promotion must mint a distinct character per domain.** Reusing a character across sibling domains under one liege makes the second `create_assignment` silently return `""`.

**Data conflict to resolve first:** `NpcRulerGenerator.LEVEL_BY_TITLE` (Baron 6, Duke 10, no Marquis) contradicts `DomainTierTable.ruler_level_for_tier` (Barony 4, March 6, Duchy 9), which is the RAW-cited table. Recommend `DomainTierTable`; retire or realign the other.

---

## R-5 — Sub-vassal loyalty rolls on transfer

**The alignment modifier requires ZERO new code.** `VassalLoyaltyResolver._alignment_mod` (`vassal_loyalty_resolver.gd:238`) already produces exactly R-5's penalties (−1 one step, −2 opposed) and is already applied on every vassal loyalty roll via `project_modifier_breakdown(assignment)["alignment"]` (`:152-153`). The only requirement is that the roll be computed against the **new** liege.

> **The single most likely implementation bug:** adding an alignment term to `extra_modifiers` on top of `project_modifier_breakdown["alignment"]` double-counts it. `SubVassalLoyalty.alignment_steps()` is for **reporting/preview only**.

**Mechanism — the swapped-liege probe:**
```gdscript
var probe: Dictionary = assignment.duplicate()
probe["liege_character_id"] = new_owner_id
if int(assignment.get("is_henchman_vassal", 1)) == 0:
    probe["base_loyalty_modifier"] = TradeRangeResolver.compute_non_henchman_base_loyalty(
        vassal_domain_id, new_owner_id)
var roll := VassalLoyaltyResolver.roll_for_trigger(probe, TRIGGER_NEW_LIEGE, ...)
```

**Acquisition method: pass it as a parameter; add no column.** `domains.establishment_method` cannot carry it — it is written once at founding, its enum is founding-specific, conquest never rewrites it, and it is **load-bearing for the beastman gate** (`lifecycle_handler.gd:449-450` and `DomainMoraleResolver` both infer beastman population from it). Overwriting it on conquest would silently flip that gate. The mode is statically known at every transfer call site, so a parameter never goes stale.

**New file** `engine/subsystems/domains/sub_vassal_loyalty.gd` — `class_name SubVassalLoyalty`:
- `ACQ_CONQUEST/GRANT/PURCHASE/INHERITANCE/ABDICATION`; `CONQUEST_LOYALTY_PENALTY := -2`; `TRIGGER_NEW_LIEGE := "new_liege"`. Define these **here, not in `EstablishDomainFlow.VALID_METHODS`** — that constant is the `establishment_method` column's CHECK domain.
- `roll_for_transfer(domain_id, prior_owner_id, new_owner_id, acquisition_method, calendar_day, dice = null) -> Array`
- `acquisition_penalty(method) -> int` and `alignment_steps(a, b) -> int` (pure, DB-free, unit-testable)
- `preview_modifier(sub_vassal_domain_id, new_owner_id, acquisition_method) -> Dictionary` — no dice, no writes; feeds the pre-commit warning modal `VassalAppointmentWarnings` was built for and never got.

**Outcome mapping** routes through the existing §5.3 compliance ladder rather than inventing a fourth vocabulary — RAW gives the bands (`acore_equipment.xml:795-809`) but says nothing about what a *land-holding* vassal does when he "leaves":

| Band | Result | Action |
|---|---|---|
| 12+ Fanatic | STAYS | re-point edge; `over_compliance`; persist `loyalty_is_fanatic = 1` (RAW: +2 all future rolls) |
| 9–11 Loyalty | STAYS | re-point edge; `full_compliance`; clear grudging |
| 6–8 Grudging | STAYS, resentful | re-point edge; `under_compliance`; `loyalty_grudging_pending = 1` (next roll −1). §5.3 already gives this teeth: half-strength levies |
| 3–5 Resignation | stays on the books, seeks lawful exit | `resignation_seeking` → `ResignationLadder` petition/appeal/exile; path C ends in the domain reverting to the liege |
| 2− Hostility | breaks away | `revolted` + `liege_domain_id = NULL` + `RebelCoalition.seed_rebellion` (RAW: "becomes a rival/enemy") |

**Other changes:**
- `_cascade_vassals` **splits in two**: `_detach_upward_edge(domain_id, calendar_day)` (today's Case 2, plus the missing `UPDATE domains SET liege_domain_id = NULL` that closes the two-sources-of-truth bug) and a downward path that rolls per R-5. The liege-wide Case 1 is deleted.
- `VassalRepository` gains `repoint_liege(...)` — **requires adding `liege_character_id` to `_UPDATE_FIELDS`** (`vassal_repository.gd:23-34`); it is not whitelisted today, so `update()` would push_error and no-op. Must guard the partial unique index.
- `RealmGraph` gains `direct_vassal_domains(liege_domain_id)` — it currently walks only **upward**; no downward helper exists anywhere.
- `EventBus.domain_conquered` gains `prior_owner_id`; three subscribers update in the same commit (`vassal_loyalty_triggers.gd:54`, `realm_relations_drift.gd:76`, `ruler_seam_b_trigger.gd:81`).
- **Do not consolidate** `DomainMoraleResolver`'s and `VassalAppointmentWarnings`' −1/−2 alignment rules with this one. They compare a ruler's alignment to a **domain's** alignment for RAW base domain morale (`acore_axioms:420-424`) — Layer-1 sacred, different mechanic, coincidentally the same numbers. R-5 compares character to character. A conquered domain's `domains.alignment` still describes the *defender's* religious practice.

**Tests that break:** `test_lifecycle_conquest_outcomes.gd:153-163` (breaks twice over — asserts `departed`, and its fixture sets no `liege_domain_id`), `test_lifecycle_handler.gd:163-179` (same fixture reason). `scenario_conquest_outcomes.gd` survives but should be extended.

---

## R-6 — Mercenaries do not transfer

`DomainStocker` stocks garrisons **100% `source_type='mercenary'`** (`domain_stocker.gd:233`) — so as written, R-6 means **conquering a generated NPC domain transfers zero troops**. See open decisions.

**Placement matters.** `_dispose_mercenaries` must run **after** the `_conquest_eligible` gate and **after** a successful `reassign_domain_owner` — i.e. inside the OCCUPIED and LOOTED branches only. Putting it earlier reproduces exactly the bug the audit found with `_cascade_vassals` running before the gate. For SALTED_TO_RUIN, depart *all* units.

Mercenaries depart via `TroopUnitRepository.depart_unit(id, "employer_deposed", calendar_day)`; no severance is paid (conquest is not a voluntary discharge). Counts go into the departure-log payload `conquer_domain` already builds. Define the disposition as a named constant beside `ArmyDisbander._release_data_for_source` so the two per-source tables cannot drift.

**Caveat:** `ThreatForceComposer` writes brigands as `source_type='mercenary'` as a CHECK-valid stand-in — a literal source_type test mis-classifies them.

---

## R-7 — Domain XP, ruler only, tribute included

**Tribute is already inside the formula.** `net_income = revenue.total − expenses.total`, revenue already includes `tribute_in` and expenses already include `tribute_out`. R-7 needs **no formula change** — it needs R-2's unit fix, plus R-1/R-4 so tribute-in is non-zero at all.

**Four defects at the implementation site** (`domain_handlers.gd:658-671`): `XPAwardCalculator.calculate_domain_xp` is never called, so the RAW per-level gp threshold is never subtracted; units are cp fed to a gp table; `domain_xp_this_month` is read by nothing, so no character ever gains a point; and `int(round(...))` violates banker's rounding.

**RAW constraints** (`acore-campaign-hijinks.xml` §experience_from_campaigns — the operative section, threshold table matches `GP_THRESHOLD_TABLE` exactly):
- "To earn XP, the activity must be **personally managed** by the character" / "**No XP is earned from domains managed by vassals**" — which makes per-personally-owned-domain awarding RAW-correct *once the one-personal-domain invariant is enforced*. It is not, and is currently unsatisfiable.
- "A character can never earn enough campaign XP in one month to **advance 2 or more levels**."
- Prime-requisite XP bonuses apply as for adventuring XP.
- "A follower or henchman **managing a domain** earns 50% of normal domain XP" — this is a per-manager **rate**, not a share of one pot. So `is_henchman` **stays**, redefined as `characters.character_type == 'henchman'` for the domain's owner. It must never become a distribution key.
- **Two carve-outs not yet modelled:** scutage receipts must be *excluded* from the XP base (`acore_axioms:362`) but are not modelled as revenue at all; a Gift must increase the recipient's and decrease the grantor's XP base (`acore_axioms:368`) but `FavorsDutiesResolver` moves only treasuries.

**Award path:** there is **no shared XP award function** today — `BattleXpDistributor._credit_character`, `QuestRegistry._award_xp` and `CombatFinalizer` each roll their own six lines. Extract `XpAwardService.award(character_id, amount, source_key)` using the atomic `UPDATE characters SET xp = xp + ?` form. Level-up stays a **notification**, not an automatic apply (PCs level interactively via `LevelUpEngine.begin_interactive_level_up`).

**Double-award guard:** migration 212 adds `domains.domain_xp_awarded_through_day INTEGER NOT NULL DEFAULT -1`; award only when `calendar_day > domain_xp_awarded_through_day`, set in the same `update_domain_monthly_state` call so guard and record commit together. Plus a `ledger_entries` audit row per award.

**Sibling gap, logged not scoped:** RAW `experience_from_construction` — 1 XP per 2 gp spent on a domain-securing stronghold (1 per 4 for a henchman), awarded at completion and **clawed back if the stronghold is lost**, possibly costing class levels. Entirely unimplemented.

---

## Follow-up decisions — RESOLVED by Jedidiah, 2026-07-31

**D-1 — R-5 fires on ANY change of liege.** Conquest, grant, purchase, inheritance and abdication all trigger the sub-vassal loyalty roll. A new lord is a new lord; only the −2 conquest penalty distinguishes them. So `ACQ_INHERITANCE` and `ACQ_ABDICATION` are live members of the vocabulary, and `RulerDeathHandler.resolve_succession` / `ResignationLadder.abdicate_into_exile` each become `SubVassalLoyalty.roll_for_transfer` call sites alongside the two in `conquer_domain`.

**D-2 — Direct sub-vassals only.** One hop of `liege_domain_id`. A Baron under a Count under the conquered Duke deals with his Count, not with the conqueror. `RealmGraph.direct_vassal_domains` is therefore non-recursive by design — do not "improve" it into a subtree walk.

**D-3 — Faithful followers do NOT transfer either.** `source_type='follower'` joins `'mercenary'` on the no-transfer side: class followers serve the ruler's person, not the castle. So `TRANSFERS_ON_CONQUEST := {mercenary: false, follower: false, conscript: true, militia: true, tribal_warrior: true, slave_soldier: true}`. Note this compounds the `DomainStocker` problem below — see the remaining open item.

**D-4 — NPC rulers DO level from domain XP, automatically.**
Jedidiah's rationale, which resolves the drift concern rather than accepting it: *"per-level domain XP thresholds exist specifically to block a baron from levelling beyond his station, and it is what drives the motivation to gain more land, population, and tribute, or to crush an under-powered rival before he levels up from his domain income."* The RAW threshold table **is** the throttle — a Baron on a 160-family domain simply never clears his level's gp threshold, so he cannot drift. This also makes the NPC nobility's power a live, legible consequence of its territory, and gives the player a real reason to act against a growing rival early.
**Implementation note:** no stub is needed — `LevelUpEngine.apply_level_up_auto(character: CharacterData)` already exists (`level_up_engine.gd:88`), is silent, and persists to DB. But it has **zero production callers** outside its own file, so a caller must be wired, and it takes a `CharacterData` object rather than a character id — the monthly domain tick will need to load one. Record in the build log that this is the first production use of the auto-level-up path.

**D-5 — `DomainStocker` mixes unit types: an even split BY COST (not by unit count) across conscripts / militia / mercenaries, or clanhold equivalents where needed.** Nuanced distribution is a later pass; the split ratio must therefore be a named, tunable constant rather than a literal.

> **A literal even-thirds split is RAW-infeasible** — see "The even split cannot be even" below. **APPROVED 2026-07-31:** implement the cap-clamped form — `min(even_third, RAW-legal maximum)` for conscripts and militia, with the uncapped mercenary slice absorbing the remainder — and the RAW findings it rests on. Target splits: wilderness 7/29/64%, borderlands 10/33/57%, civilized 15/33/52% (conscript / militia / mercenary).

**D-6 — The split is by garrison-credit gp value, not treasury outflow.** Sent-home trained militia credit full wage value toward the garrison minimum at **zero** cash outflow (`acore_axioms:230`), so the two readings are mutually exclusive. Value is the quantity RAW's 2/3/4-gp-per-family minimum is denominated in, and the one `GarrisonExpenditureCalculator.total_value_cp` already computes — so no engine change is needed. Consequence to record: a generated NPC domain's actual monthly cash bill is ~two-thirds of its nominal garrison figure, and the world is assumed to have paid the militia training capital (94.5 gp/troop for Light Infantry) at some point in its history.

**D-8 — R-4 promotion is a HYBRID: eager-cheap stub + lazy-rich detail.** Mint a `persistence_tier='named'` character row for **every** ownerless domain at materialization — one INSERT carrying name, class, level, race, alignment, culture_id and a rolled CHA, and nothing else. Defer the full `ClassedNpcBuilder` / `PromotionEngine.promote_b_to_a` bundle and `StrategicDispositionBuilder` to first contact / LOD activation, per the GDD's promote-on-visit path (`gdd-setting-runtime-materialization.md` §15.5).
Rejected alternatives and why: **pure-lazy cannot satisfy R-1** — `vassal_assignments` needs character ids on both ends of every edge, so the realm tree would stay half-recorded and a King's tribute/aggregate/title would flicker as the player wanders; **pure-eager is exactly what the GDD rejected on perf grounds** (`gdd-region-zoom-in.md` §5.6a: 750–1,100 domains per eager window × a full builder = multi-second-to-minute materialization).

**D-9 — `DomainTierTable` governs NPC ruler level** (Barony 4 / March 6 / Duchy 9). It is the RAW-cited table (`acore_axioms` §titles_of_nobility) and the world generator already uses it. `NpcRulerGenerator.LEVEL_BY_TITLE` (Baron 6 / Duke 10, no Marquis entry) is to be retired or realigned to match — two tables that can drift is the problem being fixed.

**D-7 — No backfill.** Existing saves are all test worlds and may be deleted with nothing of value lost. R-1 and R-4 therefore ship as forward-only changes: no migration-time repair, no on-load reconciliation, no dev tool. **This is a significant simplification** — it removes the hardest part of both rulings. Note it explicitly in the build log so a future session does not "helpfully" add a backfill.

## Open decisions still outstanding

All three are R-5 detail. Each has a stated default that the build agent should proceed on; each is one line to reverse.

**O-1 — The same-alignment +1.** `VassalLoyaltyResolver.MOD_ALIGN_SAME := 1` gives a co-aligned vassal +1 (project's own `gdd-faction-framework.md` §5.2, shipped and tested). R-5 names only penalties. *Proceeding on: keep it*, reading R-5 as specifying the penalty side of an existing row.

**O-2 — Does the −2 attach to how the domain was taken, or to who the new liege is?** *Proceeding on: how it was taken* — a sub-vassal resents the sword that took his lord's seat regardless of the taker's history. (Under the other reading, a warlord who later receives a domain by grant would still carry −2 from his past.)

**O-3 — `OUTCOME_LOOTED_LOCAL_SUCCESSION`'s acquisition method.** The local heir spawned by `spawn_local_succession_npc` did not conquer anything — the attacker looted and left. *Proceeding on: `ACQ_INHERITANCE`* (no −2). Reversible if you'd rather the sub-vassals resent the sacking either way.

---

## RAW finding: can followers count toward a garrison?

Jedidiah asked, correctly suspecting followers are closer to free henchmen than to troops. RAW's answer is **yes, but narrowly, and only for two classes** — which vindicates the instinct and confirms D-3 and D-5.

`acore_axioms_strongholds_and_domains.xml:229` — *"Faithful followers of clerics and bladedancers may count by gp value toward garrison cost even though unpaid."* The class tables show why only those two are named:

| Class | Followers at 9th level | Cost rule |
|---|---|---|
| **Cleric** (fortified church) | 5d6×10 **0-level soldiers** + 1d6 clerics | *"need not be paid wages"*; **morale +4, completely loyal** |
| **Bladedancer** (temple) | 5d6×10 **faithful 0-level soldiers** + 1d6 bladedancers | *"Followers in service need not be paid wages"* |
| Fighter (castle) | 1d4+1×100 0-level **mercenaries** + 1d6 fighters | *"If hired, followers must be paid standard mercenary rates"* |
| Bard (hall), Explorer (border fort) | 1d4+1×10 0-level **mercenaries** + 1d6 of class | same — standard mercenary rates |
| Mage (sanctum) | apprentices + normal men seeking to become mages | not troops; food and lodging only |
| Thief / Assassin (hideout) | apprentices | ruffian rates if hired |

So "follower" is not one thing. Only the cleric's and bladedancer's faithful soldiers are the *unpaid* garrison RAW lets you count — and they count **"by gp value toward garrison cost"**, i.e. as an accounting offset against the 2/3/4 gp-per-family minimum, not as a wage the ruler pays. Everyone else's followers are either paid mercenaries (economically identical to `source_type='mercenary'`) or non-combatant apprentices.

**Consequences:**
- **D-3 stands, and is now over-determined.** Faithful followers are religious devotees sworn to a specific cleric or bladedancer (morale +4, completely loyal *to that person*) — they plainly do not pass to a conqueror. Fighter/bard/explorer followers are paid mercenaries and are already excluded by R-6. Mage/thief apprentices are not garrison at all. `source_type='follower'` not transferring is correct in every case.
- **D-5's exclusion of followers from the generic stocker is correct**, because followers are class-conditional — only a cleric- or bladedancer-ruled domain has any. A later refinement could add them for exactly those rulers.
- **The engine needs a distinction it may not have:** a unit that contributes to the garrison *minimum* without contributing to *cash expense*. RAW applies this to faithful followers (`:229`), to trained militia not called up (`:230`), and to lord-favour troops (`:231`). Whether `troop_units` can express it today is being checked.

## The even split cannot be even — RAW findings for D-5

### 1. The conscript third overflows the cap in every benchmark domain

`daw_armies_recruitment.xml:315` caps conscripts at 1 per 10 peasant families. Working the RAW benchmark domains (one 6-mile hex at max density, at the 4/3/2 gp-per-family garrison rates):

| Classification | Families | Garrison target | Even third | Conscript cap | Best untrained (3gp) | Best trained LI (6gp) |
|---|---|---|---|---|---|---|
| Wilderness | 125 | 500 gp | 166.67 gp | 12 | 36 gp (22%) | 72 gp (43%) |
| Borderlands | 250 | 750 gp | 250.00 gp | 25 | 75 gp (30%) | 150 gp (60%) |
| Civilized | 780 | 1,560 gp | 520.00 gp | 78 | 234 gp (45%) | 468 gp (90%) |

**Closed form** (family count cancels — target and cap both scale linearly, so feasibility depends only on the gp-per-family rate `g`): a conscript must be worth `≥ 10g/3` gp/month to fill an even third — 6.67 / 10.00 / 13.33 gp/head for civilized / borderlands / wilderness. Militia need `≥ 5g/3` (3.33 / 5.00 / 6.67).

And you cannot fix it by promoting everyone to expensive troop types: `daw:333-343` caps training eligibility (100% light infantry, 50% heavy infantry or bowmen/crossbowmen, 25% longbowmen or light cavalry, 8.5% heavy cavalry). The best RAW-legal wilderness mix from 12 conscripts is 6 crossbowmen + 6 light infantry = 144 gp, still 22.67 gp short. Closing it requires a wilderness peasant levy that is one-quarter cavalry. `engine/subsystems/domains/troop_training_eligibility.gd` already implements this table and should gate the mix.

**Militia** are feasible at Light Infantry rates in borderlands and civilized, and marginally infeasible in wilderness (needs bowmen at 9 gp for some units).

### 2. "By cost" is ambiguous, and the two readings are mutually exclusive

`acore_axioms:230` — *"Trained and equipped militia may count by gp value toward garrison cost **even when not called up**."* Militia are a **one-time capital investment that then credits full wage value forever at zero cash outflow**: 94.5 gp/troop to train and equip Light Infantry (`daw:393-421`), then 6 gp/month of permanent garrison credit. Payback 15.75 months; equipment is kept and even passed to heirs (`daw:442-445`). Recurring cost while sent home is **zero** (`daw:437` and `:444` both condition cost on being called up).

So an even split by **garrison-credit gp value** and an even split by **treasury outflow** cannot both hold. Under the former, the domain's actual monthly cash bill is only two-thirds of the nominal garrison figure. **This is O-6.**

Critically, **the engine can already express this** — no change needed. `GarrisonExpenditureCalculator` (`garrison_expenditure_calculator.gd:100-109`) branches: `if monthly_cost_cp > 0: total_paid += cost` else `unpaid_value += monthly_wage_cp`, and reports `total_value_cp = total_paid_cp + unpaid_value_cp`. Sent-home trained militia are minted with `monthly_cost_cp = 0`, `monthly_wage_cp = per-type wage × count`, `is_trained = 1`, `tier != 'untrained'`.

Two traps: **untrained militia do not qualify** for the `:230` concession (it says "trained *and equipped*"), and today's `LevyMilitiaHandler` output is `tier='untrained'`; and **called-up militia cost −1 family of revenue each and −1/−2 base morale** (`daw:429-431`) until sent home — a 780-family civilized domain stocked with 156 called-up militia would lose 156 families of revenue and 2 base morale.

### 3. Clanholds are a two-way split, not three

`ax_domains_of_chaos.xml:36` — *"Clanhold chieftains **cannot conscript peasants or levy militia**."* `:37` allows 1 tribal warrior per family; `:38-39` allows beastman mercenaries, and human/demi-human mercenaries only if chaotic. So the clanhold recipe is **tribal_warrior + beastman mercenary**. `levy_militia.gd:32` already hard-blocks clanholds citing the same line — the stocker must branch identically or it will mint RAW-illegal rows.

`tribal_warrior` is a faithful RAW concept (`ax_domains_of_chaos.xml:390-464`), arrives already trained and equipped at **zero capital cost** (`:408`), and is paid standard mercenary wages by troop type (`:411`). Cost per warrior varies enormously by race: kobold 2.00 gp → ogre 56.67 gp.

**Kobold and goblin clanholds cannot self-fund their garrison.** A maximum levy (125 warriors) yields 250 gp (kobold) or 450 gp (goblin) against a 500 gp wilderness minimum. Orc and above clear it from tribal warriors alone. The mix must be feasibility-checked per race, not applied uniformly.

### 4. The workable form

For each of conscripts and militia take `min(even_third, RAW-legal maximum)`; let the uncapped mercenary slice absorb the remainder. Resulting splits (untrained conscripts, trained sent-home LI militia):

| Classification | Conscript | Militia | Mercenary |
|---|---|---|---|
| Wilderness | 36 gp (7%) | 144 gp (29%) | 320 gp (64%) |
| Borderlands | 75 gp (10%) | 250 gp (33%) | 425 gp (57%) |
| Civilized | 234 gp (15%) | 520 gp (33%) | 806 gp (52%) |

Mercenaries remain the majority in every case — which is the RAW-honest answer, and matches `daw:710`: *"Leaders relying on vassals usually field conscripts from domains; leaders relying on standing armies usually hire mercenaries."*

### 5. Bug found in passing — battle rating is 3× overstated [SPUN OFF — FIXED 2026-07-31]

> Spun off as its own task on 2026-07-31 (chip `task_b9d5936a`, "Fix 3x-overstated garrison battle rating") because it is independent of D-5 and should land regardless. Do not fix it inside the D-5 work; do make the D-5 stocker consume whatever per-type/per-tier lookup that task introduces.


`domain_stocker.gd:239` writes `battle_rating = 0.025 * count` for `'Light Infantry'`. Per `daw_campaigns_troop_tables_summary.xml:298`, a 120-man Light Infantry unit is BR 1 = **0.00833** per soldier; **0.025 is line :299, VETERAN Light Infantry at BR 3**. Untrained conscripts and militia are 0.5 per 120 = 0.004167. Every generated NPC garrison is currently three times as strong in battle as RAW allows. `TribalWarriorRegistry._TROOP_TYPE_STATS` already carries the correct 0.008 figure. **This is independent of D-5 and should be fixed regardless.**

**Resolved 2026-07-31.** Fixed via a new shared lookup, `TroopBattleRatingTable` (`engine/subsystems/troops/troop_battle_rating_table.gd`) — `per_soldier(troop_type, tier)` / `for_unit(troop_type, tier, count)`. **D-5's stocker must mint every slice of its mix through `for_unit`, not through a literal.**

Two corrections to the figures above, found while verifying:

- **The per-soldier source is the per-CREATURE table, not the per-unit table.** RAW publishes Battle Rating twice. §troop_tables L101-186 is per creature (L9: *"Battle Rating is listed per creature"*); §unit_characteristics_summary L296-333 is per unit (L278; unit = 120 infantry / 60 cavalry per L273). The per-unit values are the per-creature ones re-rounded to convenient halves, so dividing them out gives a *different* number than RAW's own row: Light Infantry A is **0.008** (L105), not 1 ÷ 120 = 0.00833. The magnitude of the bug is unchanged (0.025 is ≈3×), and 0.008 is what `TribalWarriorRegistry` and `data/troops/unit_templates.json` already carry.
- **Untrained conscripts/militia are 0.003 per creature (L102), not 0.004167.** So `conscript_troops.gd:90` and `levy_militia.gd:98`, which both write `0.003 * unit_count`, are **RAW-correct as they stand** — D-5 must not "fix" them to 0.004167. Use `TroopBattleRatingTable.per_soldier(type, 'untrained')`, which returns 0.003 for any untrained unit regardless of troop-type label.

Veterans are the one case that *does* come from the per-unit table, because the per-creature table has no veteran rows; those entries are derived (unit BR ÷ unit size) and labelled as such. Rationale and the full RAW map are in `docs/coding_conventions.md` §128.

Two further per-soldier-BR bugs surfaced by the same audit are **out of scope for D-5** and have their own chips: `solicit_followers.gd:76` (`0.5 * merc_count`, ≈167× RAW — the per-unit 0.5 applied per soldier) and `tribal_warrior_registry.gd:73` (`beast_riders` 0.025 vs RAW Wolf Riders 0.107 / Boar Riders 0.131).

### 6. Other constraints the spec must honour

- **Which cost field is being split must be named.** The three minting paths disagree today: `DomainStocker` sets `monthly_supply_cp = 0`; `LevyMilitiaHandler` sets 4 gp/month; `TribalWarriorRegistry` sets 200 cp infantry / 1600 cp cavalry. *Recommend splitting on `monthly_wage_cp`* (the RAW garrison-value quantity) and deriving the cost fields from it.
- **Race and alignment gate the wage table.** `daw:26-28` — mercenaries are of the settlement's prevailing race; humanoid troops only in Chaotic settlements. `DomainStocker` hard-codes `race = 'human'`, but beastman LI ranges 2 gp (kobold) to 40 gp (ogre) — **the cost arithmetic is wrong by up to 20× for a non-human domain.**
- **The clanhold +2 gp garrison offset** (`GarrisonExpenditureCalculator.CLANHOLD_GARRISON_OFFSET_CP_PER_FAMILY = 200`) must be applied to the stocker's target too, or `meets_minimum` flips false on the first tick for every stocked clanhold.
- **Seed conscripts slightly under the cap.** `daw:317-319` — if families decrease, conscripts must be released, and killed conscripts can only be replaced by population growth. Stocking exactly at the cap means the domain drops below its garrison minimum on the first negative growth roll.
- **`slave_soldier` and `vassal` must NOT appear in a generic stocker.** `daw:563` makes slave soldiers a Judge-discretion setting flag and `:586` forbids enslavement in Lawful/Neutral realms; `vassal` would double-count troops already represented in the vassal's own domain (`daw:658-661`). RAW's own enumeration is *"some mix of followers, mercenaries, conscripts, and militia"* (`daw:663`).
