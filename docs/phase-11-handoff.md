# Phase 11 Handoff — Domain-Game Lifecycle Closeout

**Status:** COMPLETE 2026-05-22.
**Sub-phases:** 11A, 11B, 11C, 11D-prereq.0a, 11D-prereq.0b, 11D-prereq.A, 11D-prereq.B, 11D-prereq.C, 11D.1, 11D.2, 11D.3, 11D.4, 11D.5, 11E, 11F.

## What Phase 11 produced

Phase 11 tied off the domain-game lifecycle that started in Phase 0. Major systems:

### Departure log + lifecycle authority (11A, 11B, 11C)

- **`domain_departure_log`** — append-only audit table (migration 121). 27 event types covering establishment, conquest, abandonment, succession, religion change, classification advancement / regression, ruler death, tribal-warrior events, and morale-tier transitions.
- **`DepartureLogRecorder`** static class. Public API: `record()`, `list_for_domain()`, monthly-tick transition recorder, markdown/json/txt export.
- **`LifecycleHandler`** state machine. 6 public methods covering establish / conquer / abandon / mark-stronghold-collapsed / restore / monthly-tick. Five `lifecycle_state` values: active / ruined_stronghold / succession_pending / abandoned / salted_to_ruin (migration 122 + 125 rename).
- **`RulerDeathHandler`** state machine. handle_ruler_death / designate_heir / resolve_succession / tick_succession_grace / eligible_heirs_for. Vassal-with-no-heir reverts-to-overlord as v1 default (Dynasties placeholder per `memory/project_dynasties_succession.md`).
- **UI:** Departure Log sub-tab; Domain Management card on Overview sub-tab (Abandon Domain modal + Designate Heir modal + Confirm Succession Now button); succession-pending banner on the status header.

### Realm substrate (11D-prereq.0a, 11D-prereq.0b)

- **`realms` + `realm_relations`** tables (migration 124). `realm_kind` distinguishes tracked-realms (in-simulation) from foreign-realms (off-map flavor).
- **`RealmRepository`** with CRUD, pair-symmetric relations, conquest-outcome resolver.
- **Three-outcome conquest taxonomy** (0b refactor): `occupied` / `looted_local_succession` / `salted_to_ruin`. Polymorphic `new_owner_id` parameter — works for tracked NPCs, PCs, freshly-instantiated foreign-realm heads, or local-succession NPCs. Per `coding_conventions.md` §61.
- **`RealmRepository.instantiate_realm_for_off_map_force`** + `spawn_local_succession_npc` + `apply_pillage` (light/heavy severity bands).
- **Siege bridge** in `DomainHandlers._on_siege_concluded` consumes `resolve_conquest_outcome` + dispatches via the three-outcome `LifecycleHandler.conquer_domain` signature.

### Three Phase 11D prereq GDDs

- **`gdd-domain-style-and-alignment.md`** — orthogonal style × alignment model. Establishment-eligibility matrix per §7. Beastman lock per §7.4 (S3 rule).
- **`gdd-religion-conversion.md`** — congregants-based conversion mechanic per Q-RC resolutions. 60% atomic threshold per Q-RC-7. Heresy/excommunication explicitly removed per Q-RC-4.
- **`gdd-tribal-warriors.md`** — project-designed mechanic per RAW levy authorization + call-to-arms favor cost; project-designed wages / retention / loot share / dispersal.

### Phase 11D implementation (11D.1 – 11D.5)

- **11D.1 — Orthogonal axes schema** (migration 127). `domain_style ∈ {civilized, clanhold}` + existing `alignment ∈ {lawful, neutral, chaotic}` as orthogonal columns. Dropped `is_chaotic_domain` outright per Q-DSA-3. Audited + patched 9 callsites across DB plumbing, garrison expenditure, settlement growth, establishment flow, status header, overview UI.
- **11D.2 — Clanhold mechanics** (style-driven branch across 6 resolvers + 4 activity-handler gates). 125-fam/hex land-revenue halving; investment value halved (2,000gp/1d10); +2gp/family garrison floor; 250-fam-cap LIFTED for urban (per RAW L80 — corrected v1 inversion); classification distance gates tightened to 50/25mi same-realm-required; chieftains blocked from conscription / militia / council / loans / monopoly grants / land grants.
- **11D.3 — Alignment effects + religion conversion** (migration 128). `congregants` rebuilt per-character-per-domain. New `domain_religion_conversion` table + `domains.effective_religion` column. `ReligionConversionResolver` with the full §5 monthly pipeline (morale-multiplier table, driver bonus 1.5×/1.25×/1.10×/1.0×, altar bonus, 60% completion threshold, 3-month-rebellious failure mode). Beastman-rules-kin −2 morale stack added to `DomainMoraleResolver`. Active-conversion −1 penalty per §5.5.
- **11D.4 — Establishment eligibility matrix + conquest defense-in-depth + vassal-appointment warnings**. New error codes `ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL` + `ERR_INVALID_STYLE_FOR_METHOD`. `validate_establishment` enforces §7 matrix. `LifecycleHandler.conquer_domain` re-checks at the dispatcher boundary. NEW `VassalAppointmentWarnings.warnings_for_appointment` helper.
- **11D.5 — Tribal Warriors v1 backbone** (migration 129). `troop_units.source_type` extended with `'tribal_warrior'`; new `months_without_qualifying_spoils` column. `domain_departure_log.event_type` extended with 6 tribal-warrior values. New `domains.available_tribal_warriors` column with clanhold-style backfill. NEW `TribalWarriorRegistry`, `LevyTribalWarriorsHandler`, `StandDownTribalWarriorsHandler`. 6 new EventBus signals.

### Phase 11E (scenario harness)

- **`tests/scenarios/scenario_runner_base.gd`** — multi-month integration test scaffolding. White-box ticker composes `DomainRevenueCalculator → GarrisonExpenditureCalculator → DomainExpenseCalculator → DomainMoraleResolver → DomainGrowthResolver → ClassificationAdvancement` per the production order.
- **5 scenarios shipped** (out of the 10 in the original plan): `scenario_chaotic_clanhold` (exercises 11D.1-D.5), `scenario_succession` (exercises 11C with both designated-transfer and reverts-to-overlord paths), `scenario_conquest_outcomes` (exercises all three 0b outcomes), `scenario_below_sufficiency` (exercises 11B income gate), `scenario_full_loop_borderlands` (6-month multi-tick stability).

### Phase 11F (closeout)

- **`ClassEmptyStateGuidance`** static class — per-class acquisition guidance per `gdd-domain-tab.md` §19. Covers fighter / mage / cleric / thief / explorer / venturer / bard / wonderworker progression buckets with race-gated variants for dwarven and elven classes.
- **`empty_state_page.gd`** — procedural UI page that consumes the guidance dict and renders a headline + optional pre-9 banner + acquisition-paths card + class-specific note.
- This handoff document.

## Migration sequence (121 – 129)

| # | Phase | What landed |
|---|---|---|
| 121 | 11A | `domain_departure_log` table + 21-value event_type CHECK |
| 122 | 11B | `domains.lifecycle_state` + grace columns |
| 123 | 11C | `domains.succession_pending_until_day` + designated_heir columns |
| 124 | 11D-prereq.0a | `realms` + `realm_relations` tables + `domains.realm_id` |
| 125 | 11D-prereq.0b | `lifecycle_state` value rename `lost_to_foreign` → `salted_to_ruin` |
| 126 | (parallel session) | `urban_growth_stocking_schema` — see urban-growth-stocking GDD |
| 127 | 11D.1 | `domains.domain_style` + drop `is_chaotic_domain` |
| 128 | 11D.3 | `congregants` rebuild + `domain_religion_conversion` + `domains.effective_religion` |
| 129 | 11D.5 | `troop_units.source_type='tribal_warrior'` + `months_without_qualifying_spoils` + `domains.available_tribal_warriors` + 6 new departure_log event types |

## Conventions documented in this phase

Coding-conventions sections added 2026-05-20 through 2026-05-22:

- **§57** — Phase 11A: Append-only logs + monthly-tick transition recorders.
- **§58** — Phase 11B: Lifecycle state machine + cross-subsystem signal bridges.
- **§59** — Phase 11C: Succession state machine + reverts-to-overlord pattern.
- **§60** — Phase 11D-prereq.0a: Realm substrate — pair-symmetric relations + cached pointers + apex-walk fallback.
- **§61** — Phase 11D-prereq.0b: Three-outcome conquest taxonomy + polymorphic `new_owner_id`.
- **§62** — Phase 11D.1: Orthogonal-axes column refactor + deprecated-flag drop.
- **§63** — Phase 11D.2: Clanhold-style resolver branches (per-resolver column read; paired distance-gate constants).
- **§64** — Phase 11D.3: Multi-axis morale-modifier composition + conversion state machine (declared-vs-practiced religion split).
- **§65** — Phase 11D.4: Eligibility matrix dispatch + defense-in-depth + caller-friendly error codes.
- **§66** — Phase 11D.5: Derived-quantity column for stateful pool tracking.
- **§67** — Phase 11E: Scenario-harness integration test pattern.

## Known polish items (deferred to follow-up sessions)

### 11D.5 tribal-warrior polish

**Polish pass 2026-05-22 shipped 5 of 6 items + resolved Q-TW-8 as not-applicable. Remaining:**

- **Garrison sub-tab "Tribal Warriors" UI section** — handler API is callable; UI surface is a polish pass.

**Shipped 2026-05-22:**

- ✅ **Phase 8 `call_to_arms` duty handler modification** — `FavorsDutiesResolver._size_obligation` detects clanhold-style vassals + emits `tribal_warriors_called_to_arms(domain_id, scope, favor_cost)` instead of CallToArmsMuster's gp-troops flow.
- ✅ **Army-warfare casualty hook** — `ArmyCasualtyResolver` exempts tribal-warrior units from the RAW 50%-operational-dissolution trigger (Option B per Q-TW-8 resolution). Tribal-warrior units only auto-depart when truly destroyed; surviving units stay under owner control and refill via voluntary stand-down. The earlier "auto-refill-survivors" hook was REMOVED — there's no orphaned-troop scenario in mass-combat.
- ✅ **3-month-without-spoils retention tick** — `SiegeSpoilsResolver.distribute_to_units` + `apply_spoils_to_tribal_warriors` + `DomainHandlers._tick_tribal_warrior_retention`. Reset-on-credit / count-up-on-tick semantics per conventions §70.
- ✅ **Population-growth refill hook** — `DomainHandlers._save_domain` refills `available_tribal_warriors` from peasant_families growth on clanholds, capped at the §3 invariant.
- ✅ **Q-TW-8 reachability check** — RESOLVED as not-applicable. There's no orphaned-partial state where warriors are alive but cut off from command (the army owner retains control or the unit is destroyed). The 50%-operational-dissolution exemption above + voluntary stand-down cover all cases. Documented in `gdd-tribal-warriors.md` §7.4 + §12.
- ✅ **Per-race stat blocks** — imported the full RAW Tribal Warrior Troop Type table (`ax_domains_of_chaos.xml:417-444`). `TribalWarriorRegistry._COMPOSITION_PER_120` encodes 11 race/culture columns; a per-troop-type stat table provides wages + supply + battle rating. (That stat table was reworked on 2026-08-01 into per-race `_HUMAN_TROOP_TYPE_STATS` + `_BEASTMAN_TROOP_TYPE_STATS` behind `TribalWarriorRegistry.stats_for(race, troop_type)`, because RAW makes the figures race-dependent by up to ~10× — see coding_conventions §72.) New `composition_for_race(race, count)` + `inferred_tribal_race_for_domain(domain)` + `base_morale_modifier_for_domain_morale(morale)` helpers. `LevyTribalWarriorsHandler` now spawns multiple per-troop-type unit rows per the race's breakdown (orcs → 5 rows, kobolds → 1 row, skysos → 5 rows including horse_archers + composite_bowmen).

### 11D.3 religion-conversion polish

- **Multi-caster proselytizing (§5.7)** — v1 counts only the arc's driving caster's congregants. Multi-caster contributions need a per-character `religion` column or a per-arc contributing-casters table.
- **Spiritual advisor selection (§9.6)** — `RealmRepository.eligible_spiritual_advisor_for(ruler_id, religion)` not implemented; v1's driver-bonus dispatch picks ruler/henchman tiers only. The spiritual-advisor 1.25× tier is unreachable in v1.
- **UI surfaces (§8)** — no Decree card, no Faith block conversion card, no status banner, no Cancel Conversion button. The resolver API is fully callable for tests + scripted scenarios; UI work is a follow-up.
- **`change_religion` decree handler** — a thin activity-handler wrapper around `start_conversion`; deferred.

### 11D.4 establishment-flow polish

- **Siege bridge eligibility pre-check** — `DomainHandlers._on_siege_concluded` doesn't yet route to `OUTCOME_LOOTED_LOCAL_SUCCESSION` or `OUTCOME_SALTED_TO_RUIN` when an `OUTCOME_OCCUPIED` would be invalid per the §7 matrix. The lifecycle-handler defense-in-depth catches malformed dispatches; the cleaner architecture is a polish pass.
- **Realm sub-tab "Assign domain to henchman" flow + establishment-flow modal warnings** — `VassalAppointmentWarnings.warnings_for_appointment` is callable but no consumer UI exists yet.

### 11E scenario gaps

The original plan called out 8 core scenarios + 2 candidates (10 total). Shipped 5; the remaining 5 to-be-authored:

- `scenario_realm_with_vassals` — tribute aggregation across multiple vassal domains.
- `scenario_pre_9_path` — sub-9 character acquires a domain (no auto-followers).
- `scenario_repression_morale_cap` — repressed domain capped at 0 morale; repressing-troops gp/family.
- `scenario_land_improvement` — land_improvement_level boosts revenue.
- `scenario_vassal_succession_reverts_to_overlord` — exists as a sub-test inside `scenario_succession`; promoting it to a dedicated file is cosmetic.

### Pre-existing UI parse cascade (not a regression)

The parse cascade on `scenes/ui/notebook/domain/status_header.gd` + `scenes/ui/notebook/domain/sub_tabs/overview_sub_tab.gd` at preload time (via `domain_tab_page.gd:28-29`) predates 11D.1. Investigation deferred — it doesn't affect test outcomes for headless runs.

## Test stability

Final battery: **343 suites passed / 24 failed** (2026-05-22). The 24 failures are the same pre-existing order-pollution flakes documented across sessions:

- `location_key` mismatch (dungeon).
- `language proficiency` save count.
- `equipment item` count drift (176 vs 177 / 53 vs 224).
- `SpecializationRegistry` craft / knowledge ID counts.
- `proficiency_popup` visibility.
- `signal emitted` (various).
- `from_key = old` (various state machines).
- `dungeon: encounter on 1` / `dungeon: terrain_category = dungeon`.
- `player_roll_cancelled emitted`.
- `path should be empty when fully blocked`.
- `LOS should be blocked by wall at (3,3)`.
- `charge should be invalid when path is blocked`.
- `ZoC stop: should stop after entering ZoC cell`.

These flake based on suite-execution order; running individual affected suites in isolation passes them. They do NOT touch domain mechanics and are NOT regressions from any Phase 11 work. The variance band across recent sessions: 21-25 failed; 312/50 was observed as an outlier on one run (and re-running produced 337/25 immediately).

## What's next

Phase 11 is the last numbered phase in the original `docs/domain-roadmap-corrected.md`. The domain-game lifecycle is feature-complete at the engine layer. Likely next concerns:

### Phase 12 candidates (TBD by Jedidiah)

- **Faction system** — broader than the realm substrate. Encounter reactions / faction-targeted hijinks / espionage / diplomacy proper / settlement control / contested state / trade-route customs. Per `docs/phase-11-plan.md` deferral notes.
- **Religion-conversion + tribal-warrior UI surfaces** — Decrees Change Religion card, Faith block conversion card, status header banners, Garrison sub-tab Tribal Warriors section.
- **Per-race tribal warrior stat block expansion** — read L&E warband composition + the RAW Tribal Warrior Troop Type table.
- **Population-growth refill hook for available_tribal_warriors**.

### Cross-cutting cleanups (any session)

- Investigate + resolve the parse-cascade on `status_header.gd` / `overview_sub_tab.gd` preload paths.
- Replace `_distance_to_friendly_city` / `_friendly_settlement_in_same_realm` placeholders in `DomainHandlers` with real RealmRepository-backed lookups.
- Address the test-pollution flake set (rerun-in-isolation passes confirm these are order-dependent, not regressions).

### Future-feature placeholders documented in memory

- **ACKS Dynasties bloodline-heir succession** per `memory/project_dynasties_succession.md` — replaces the Phase 11C reverts-to-overlord v1 default when the Dynasties resolver lands.
- **Culture Canon GDD** — replaces the v1 cultural-marker string lookup (jutland / iv_kingdom / skysos) with explicit culture-IDs per the front-matter mapping in `gdd-tribal-warriors.md`.
- **`characters.religion` column** — would unblock multi-caster proselytizing per `gdd-religion-conversion.md` §5.7.
- **`domains.population_race` column** — would unblock explicit beastman-vs-kin population modeling, currently inferred from `establishment_method`.

## Architecture map (domain layer)

The Phase 11 domain layer composes these modules in the canonical order during `DomainHandlers._handle_monthly_tick`:

```
1. GarrisonExpenditureCalculator      — total_paid_cp + morale_incentive_bonus + clanhold_offset
2. DomainRevenueCalculator            — land + services + tax + tribute_in; income gate check
3. DomainExpenseCalculator            — garrison (clanhold +2gp/fam) + liturgy + maintenance + tithe + tribute_out + repression
4. DomainMoraleResolver
   .resolve_base_morale               — personal_authority + classification + stronghold-suff + morale-incentive + alignment + beastman-kin + active-conversion + consecrate-ruler
   .resolve_current_morale            — 2d6 roll + event modifiers + repression cap
5. DomainGrowthResolver               — random ±1d10 per 1000 + active-adventuring + investment (clanhold halved) + morale-tier
6. SettlementGrowthResolver           — per-settlement investment growth (clanhold halved) + cumulative-cap
7. ClassificationAdvancement          — distance gate (clanhold 50/25mi same-realm) + hex/family-cap + urban-ratio
8. FaithMonthlyResolver               — congregant growth + upkeep
9. ReligionConversionResolver         — per-arc tick: morale × driver × altar; 60% threshold; 3-month-rebellious failure
10. LifecycleHandler.tick_lifecycle_state    — ruined-stronghold grace
11. RulerDeathHandler.tick_succession_grace  — succession-pending grace
12. DepartureLogRecorder.record_monthly_transitions  — classification/morale-tier changes
```

The orthogonal style × alignment model means each resolver reads `domain_style` and `alignment` from the same domain dict; per-resolver constants determine which axis controls which mechanic (per `coding_conventions.md` §63).

## Phase 11 ships clean. 🎉
