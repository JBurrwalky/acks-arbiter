# Roadmap: Domain-Level Gameplay Loop (Full Ruler-with-Vassals) — RAW-Corrected v2

> **Revision note (2026-05-06):** This is `take-a-look-happy-mountain.md` with five RAW errors corrected and four RAW omissions added. All changes are marked with **`[RAW PATCH]`**. The architecture, phasing, citation discipline, and parallelization analysis are unchanged. Source citations have been added inline next to each patched value.
>
> **Revision note (2026-05-06, addendum):** Two open clarification items resolved by Jedidiah and folded into the body: (1) the tribute-inefficiency 17-36/64-216 gap is treated as a digit-transposition typo and read as **17-63 = 50%** (no missing tier); (2) the active-adventuring detector (formerly O-D1) is now defined for the project. Changes are marked with **`[RESOLVED 2026-05-06]`**.
>
> **Revision note (2026-05-06, second addendum):** Five additional clarification items resolved by Jedidiah: (3) treasury manual transfer (O-D2) — money does not teleport in ACKS; treasury gp is freely usable for domain-level activities but cannot fund personal purchases without physical movement; (4) bard activity bucket (O-D3) — bards are RAW core, not Arbiter-specific, and assigned to the Garrison Training bucket; (5) succession grace period (O-D6) — confirmed at 1 game-month; (6) non-conforming strongholds (O-D10) — RAW correction: non-conforming strongholds do NOT block followers or campaign activities; followers arrive on the basis of stronghold gp-value sufficiency only; (7) tick-tolerance heuristic (O-D15) — confirmed. Changes are marked with **`[RESOLVED 2026-05-06]`**.
>
> **Revision note (2026-05-06, third addendum):** Final open clarification item (O-D5) resolved. **Lightblessed Wonderworker** is the project's name for the class published in ACKS Player's Companion as "Nobiran Wonderworker" (renamed for IP reasons; mechanics are unchanged). At root the class plays as a Mage for domain purposes (mage progression family, arcane repertoire, magic-item creation at L9), with three additions: a split mage-and-cleric follower set on stronghold completion, magical research access to both arcane and divine spell lists, and ritual-spell access to both lists at level 11+. The class is implemented as the Magical Research bucket extended with a Faith block, not as a separate hybrid bucket. All references to "Nobiran" in this document have been updated to "Lightblessed". Changes are marked with **`[RESOLVED 2026-05-06]`**.
>
> **Revision note (2026-05-06, fourth addendum — architecture realignment):** Phase 3 was importing a daily-activity-slot-tracker model from the (now stale) `gdd-domain-tab.md` §11.3, which conflicted with the canonical real-time-with-pause architecture in `gdd-realtime-scheduler.md`. Phase 3 has been rewritten to align with the time-cost executor model. Specifically: (a) activities are launched from their location of execution, not from a centralized picker tab; (b) the "Activities" sub-tab on the Domain notebook is renamed and repurposed as **"Decrees & Remote Orders"** for the small set of remote-capable domain activities (administer_domain, issue_decree, manage_henchmen, conscript_troops, levy_militia, solicit_mercenaries, call_to_arms, oversee_investment); (c) tick-tolerance / absence / abandon-and-resume mechanics apply only to Ongoing-frequency activities — Singular and Restricted activities are atomic and must be restarted if interrupted; (d) per-character ongoing-activity status is surfaced via a new "Active Projects" sub-tab on the Character tab. Concurrent updates: `gdd-realtime-scheduler.md` §4.8 (new), `gdd-domain-tab.md` §11 (rewritten) and §15.1.1 (clarified ongoing-only), `gdd-character-tab.md` §3.8 (new). Changes marked with **`[ARCH 2026-05-06]`**.
>
> **Revision note (2026-05-06, sixth addendum — DaW Army Warfare layer inserted):** Following review, sieges and bandits cannot be implemented without an underlying army-warfare layer (army composition, command hierarchy, marching, supply, recruitment vagaries, abstract field-battle resolution). RAW for that layer exists across `daw_armies_recruitment.xml`, `daw_campaigns_troop_tables_summary.xml`, `daw_campaigning_armies.xml`, `daw_axioms_pitching_battle.xml`, and `daw_vagaries.xml`. **A new Phase 6 has been inserted, split into Phase 6A (army composition + marching + supply + recruitment vagaries) and Phase 6B (abstract field-battle resolver + casualties + pursuit + heroic forays).** All subsequent phases renumber: prior Phase 6 (Realm/Vassalage/Tribute) → 7; prior Phase 7 (Favors & Duties) → 8; prior Phase 8 (Encounters/Bandits/Sieges) → 9; prior Phase 9 (Class-Specific) → 10; prior Phase 10 (Departure Log/Polish) → 11. Total phases now 12 (0 through 11). Field-battle resolution uses the no-map abstract procedure per `daw_axioms_pitching_battle.xml` §battle_resolution L233-386 (three-phase missile / skirmish / melee with BR-vs-BR attack throws, BPC-driven phase transitions, terrain advantage, heroic forays, redeployment within Leadership Ability, advance/hold/withdraw choices). Mapped tactical battles per Domains at War: Battles remain out of project scope. The army UI surface extends `gdd-troops-tab.md` rather than adding a new Armies tab. A scaffold for the new `gdd-army-warfare.md` exists for a dedicated drafting session before Phase 6A build begins. Changes marked with **`[ARMY 2026-05-06]`**.

> **Revision note (2026-05-06, fifth addendum — siege resolution scoping):** Phase 8's siege subsystem was previously scoped as a state flag *"consumed by future combat-tactical surface."* That deferral is removed. **Sieges are in v1 scope and resolve abstractly — no battle map required.** Two RAW-supported abstract siege systems are folded in: (i) the **default DaW: Campaigns siege rules** (`daw_sieges.xml` §blockade L65-193, §reduction L195-463, §assault L465-499), used for **player-involved sieges** — the no-map unit_capacity formula at L37-41 (`ceil(shp / 1000)`) replaces per-structure unit_capacity until the grid builder ships in v1.1+; and (ii) the **Sieges Simplified** table (`daw_sieges.xml` §sieges_simplified L813+), used for **NPC-vs-NPC sieges** running off-camera in the world simulation. PCs intervening in an in-progress simplified siege escalate it to the full DaW rules; current stronghold state is reconstructed from elapsed time per `daw_sieges.xml` §off_camera_and_intervention_guidance L838-844 (full duration elapsed → 0 shp; half elapsed → 50% shp). The grid-placement planner specified in `gdd-stronghold-construction.md` §4 is explicitly deferred to v1.1+; v1 strongholds are abstract value-only records with shp, gp_value, and derived unit_capacity. All army-level combat is abstract in v1; mapped tactical battles per Domains at War: Battles are out of project scope. Concurrent updates: `gdd-domain-tab.md` §13 (clarified siege state surfacing for both abstract systems), `gdd-stronghold-construction.md` §1 (v1.1+ deferral note for the grid planner). Changes marked with **`[SIEGE 2026-05-06]`**.

## Context

ACKS Arbiter currently has **foundational domain infrastructure but no playable domain loop**. The `domains` table exists, a monthly-tick handler runs (`engine/subsystems/session/handlers/domain_handlers.gd`), the Domain tab sits as an empty-state placeholder (`scenes/ui/notebook/tab_pages/domain_tab_page.gd`), and supporting systems (henchman lifecycle, reputation, factions, EventScheduler, Timekeeping) are wired. But the monthly tick is heavily simplified (flat 6gp/peasant + 9gp/urban revenue, 12gp/troop garrison, 1-in-6 generic event), there is no stronghold construction, no activity time-cost executor, no vassalage / tribute, no favors-and-duties, no domain encounters, no class-specific surfaces, and no UI beyond the placeholder.

The goal: close the gap between `rules/acore_axioms_strongholds_and_domains.xml` + `rules/ax_campaign_play.xml` + `generation/gdd-domain-tab.md` (and `gdd-stronghold-construction.md` as a hard prerequisite) and a **playable end-to-end loop** where a PC at L9+ can establish a domain, build/claim a stronghold, attract followers and peasants, run monthly cycles (revenue / expenses / morale / growth / encounters), perform class-applicable activities subject to RAW time-cost and (for Ongoing-frequency activities) tick-tolerance semantics per `gdd-realtime-scheduler.md` §4.8, assign humanoid henchmen as vassal rulers, collect tribute, exchange favors and duties, defend against bandits and incursions, and survive classification regression / conquest / death-and-succession.

User-confirmed scope: **full ruler-with-vassals loop**, **stronghold construction folded into this roadmap**.

The GDD's published build sequence (`gdd-domain-tab.md` §23.2, sub-tab order Overview → Stronghold → Garrison → Realm → Treasury → Activities → Class-Specific → Encounters → Departure Log) is preserved as the **internal Domain tab build order**, but the roadmap below is sequenced by **gameplay-loop maturity** so each phase produces something testable and increasingly playable, not nine inert sub-tabs in series.

---

## Phase Summary

| Phase | Theme | Playable outcome |
|---|---|---|
| **0** | Engine RAW-correctness + schema | Monthly tick produces ACKS-correct numbers (no UI yet) |
| **1** | Stronghold construction | A PC can commission a stronghold, watch it build, claim/inherit |
| **2** | Domain tab shell + Overview + Treasury + Establish-Domain | Player can establish a domain and read its full state |
| **3** | Activity time-cost executor + Decrees & Remote Orders sub-tab + per-location launch wiring + Active Projects HUD | Player can launch RAW activities from location surfaces and dispatch remote orders from the Domain tab |
| **4** | Stronghold sub-tab + sufficiency feedback | Stronghold value drives morale; non-conforming flagged |
| **5** | Troops tab + Garrison sub-tab + followers arrival at L9 | Garrison expenditure meter live; troop recruitment activities resolve |
| **6A** | **`[ARMY 2026-05-06]`** DaW Army Warfare Layer: composition + marching + supply + recruitment vagaries | Armies exist as aggregates of troop units with command hierarchy; armies march on the wilderness map with supply consumption and foraging; recruitment vagaries fire on muster |
| **6B** | **`[ARMY 2026-05-06]`** DaW Army Warfare Layer: abstract field-battle resolver + casualties + pursuit + heroic forays | Player-involved and NPC-vs-NPC field battles resolve via the no-map procedure per `daw_axioms_pitching_battle.xml`; PCs may make heroic forays; casualties propagate to unit rosters |
| **7** | Realm sub-tab + vassalage + tribute *(was Phase 6)* | Henchmen become vassal rulers; tribute flows monthly; vassal armies are real entities |
| **8** | Favors & Duties monthly system *(was Phase 7)* | Monthly d20 vassal favor/duty rolls with loyalty consequences; Call to Arms produces a real army |
| **9** | Domain encounters + bandits + sieges *(was Phase 8)* | `ax_domain_level_encounters.xml` events fire; bandits resolve as small armies via Phase 6B; sieges resolve via the dual-path abstract resolvers consuming Phase 6's army layer |
| **10** | Class-Specific sub-tab (5 blocks) *(was Phase 9)* | Class-applicable high-level activities (faith / research / trade / syndicate / training) |
| **11** | Departure Log + lifecycle polish + chaotic-domain branch + tests *(was Phase 10)* | End-to-end establish→succession scenarios pass |

Phases 1 (stronghold), 5 (troops), and 8 (encounters) each build sibling systems with their own tables/UI; phases 2–10 progressively populate the Domain tab. Phases 1, 5, and 9 are partially parallelizable with their consuming Domain-tab phases once interfaces are nailed down.

---

## Phase 0 — Engine RAW-Correctness + Schema Backbone

Fix `_resolve_domain_month` to compute ACKS-correct numbers and lay schema for everything downstream. **No UI changes** — this proves the math headlessly with tests.

**Schema migrations (new):**
- `050_domain_hex_land_values.sql` — `domain_hexes(domain_id, hex_q, hex_r, land_value, surveyed_by, is_littoral, land_improvement_gp)` for per-hex land values (3-9 gp via 3d3 per `acore_axioms` §land_value L43-82). **`[RAW PATCH]`** Added `land_improvement_gp` column to support the +1 land value per 25,000 gp investment rule (`acore_axioms` §land_improvement L207-215, capped at +3 cumulative, never exceeding 9 total).
- `051_domain_economy_extensions.sql` — extend `domains` with `religion`, `alignment`, `tax_rate_gp_per_family`, `liturgy_rate_gp_per_family`, `tithe_rate_gp_per_family`, `tribute_out_owed`, `is_chaotic_domain`, `is_active_adventuring_this_month`, `classification_progress_families`, `liege_domain_id`, `realm_title`, `is_repressed_this_month`, `repression_gp_per_family_this_month`. **`[RAW PATCH]`** Added the two `repression_*` columns to support the repression mechanic (`acore_axioms` §repression L510-516, §monthly_event_modifiers L488-491).
- `052_domain_followers.sql` — `domain_followers(domain_id, follower_class, count, equipped_kit_id, arrival_phase, morale_modifier)` for L9+ followers per `acore_axioms` §before_ninth_level L117-123 (an 8th-level-or-less character does not attract followers or peasants until 9th level).
- `053_ledger_entries.sql` — `ledger_entries(id, domain_id, calendar_day, category, subcategory, gp_amount, description, source_event_id)` for Treasury sub-tab.
- `054_followers_arrival_state.sql` — track `stronghold_completion_pct` thresholds for follower-wave arrival per `acore_axioms` §followers_arrival L111-116: half (rounded up) at half-built, additional quarter (rounded up) at completion, remainder during the first month after completion.

**Engine changes:**
- `engine/subsystems/domains/` (new directory):
  - `domain_revenue_calculator.gd` — service rev (4gp/fam) + tax rev (configurable, default 2gp/fam) + per-hex land-value rev (3-9gp/fam by hex, plus any `land_improvement_gp` per hex up to +3) + tribute_in. **`[RAW PATCH] Income gate:` if `stronghold_value < classification_minimum`, peasants generate no income and the domain does not grow** per `acore_axioms` §peasants_and_followers L108-109 ("Peasants begin generating income and incurring costs only once the stronghold is sufficient to secure the domain. Before the stronghold is sufficient, the domain does not generate money and does not grow."). Surface this gate in the resolver as `revenue = 0; growth = 0; expenses = garrison_paid_only` until sufficiency is reached.
  - `domain_expense_calculator.gd` — **`[RAW PATCH]`** garrison cost = max(actual_paid, **2gp/fam universal minimum**) per `acore_axioms` §garrison L218, L226 (the 2gp/fam value is the universal RAW minimum). Liturgy (1gp/fam, configurable; ±1 morale per gp deviation per §monthly_event_modifiers L492-493), maintenance (1gp/fam; each gp unpaid reduces stronghold value by 1gp per §maintenance L240-242), tithes (1gp/fam, including domains ruled by clerics/bladedancers per §tithes L248), tribute_out, plus any additional garrison spent for morale incentive (see morale resolver below) and any `repression_gp_per_family_this_month` × peasant_families.
  - `domain_morale_resolver.gd` — base morale = 0 + CHA mod + Leadership prof (+1) + personal authority matrix (level × income, table per `acore_axioms` §personal_authority L430-450) + alignment match (per §alignment_and_religion L466-471) + classification penalty (Borderlands −1, Wilderness −2, per §classification_modifiers L457-460) + **`[RAW PATCH] tiered insufficient-stronghold penalty: −1 if stronghold_value ≥ ½ minimum, −2 if ≥ ¼, −3 if < ¼`** per `acore_axioms` §insufficient_stronghold L452-456 + **`[RAW PATCH] additional-troops bonus`**: in Borderlands, +1 base morale at 1gp/fam of troops above garrison minimum; in Wilderness, +1 at 1gp/fam additional, +2 at 2gp/fam additional, per §additional_troops L461-464. Current morale = 2d6 monthly with drift toward base, modified by event log: tax/liturgy adjustments (±1 per gp deviation), administer_domain (+1 per §administration L499, L526-529), pillage (−4 next roll), occupation (cumulative −1/month up to −4), tithe-not-paid (−1), religion-change (−4 first month then −2 ongoing), and **`[RAW PATCH] repression bonus`**: if `repression_gp_per_family_this_month ≥ 1`, +1 to morale roll per gp/family of additional repressing troops (militia cannot repress); however **current morale cannot exceed 0 while repressed** per `acore_axioms` §repression L510-516 and §monthly_event_modifiers L488-491.
  - `domain_growth_resolver.gd` — **`[RAW PATCH]`** Random growth per `acore_axioms` §domain_growth §monthly_change L126-131 and `ax_campaign_play` §random_growth L15-17: per 1,000 families (rounded up), roll **two independent 1d10s — one for increase, one for decrease — both exploding on natural 10s; net population change = increase − decrease** (NOT 2d10 added). Plus active-adventuring bonus per the graduated `acore_axioms` §active_adventuring_growth table L138-149: 1-100→+5d20, 101-200→+5d10, 201-300→+4d10, 301-400→+3d10, 401-500→+2d10, 500+→+1d10; elven domains shift +2 categories larger, dwarven +1 category larger. Plus investment bonus: +1d10 families per 1,000 gp agricultural investment, capped at the domain's monthly revenue or 1,000 gp whichever greater per §investments L132-135. Plus morale-tier modifier per §effects_of_morale L538-609 (Loyal +1d10/1000, Dedicated +2d10/1000, Steadfast +3d10/1000, Stalwart +4d10/1000; Demoralized −1d10/1000, Turbulent −2d10/1000, Defiant −3d10/1000, Rebellious −4d10/1000 plus growth halts).
  - `classification_advancement.gd` — Wilderness ≤125, Borderlands ≤250, Civilized ≤780 family caps per 6-mile hex per `acore_axioms` §limits_of_growth L156-161. Advancement to Borderlands requires every 6-mile hex at 125-family wilderness max AND domain encompasses 16 6-mile hexes (2,000 families total), OR every hex at 125 with contiguous expansion blocked AND urban settlement with urban families ≥20% of peasant families, AND within 72 miles of friendly city/large town, per §classification_advancement L165-170. Advancement to Civilized requires same pattern at 250-family borderlands max and within 48 miles per L171-175. Regression triggers when justifying conditions end per §optional_rules.regression L178.
  - **`[RAW PATCH]`** `land_improvement.gd` (new) — 25,000 gp per +1 land value per 6-mile hex; hard caps: total improvements per hex ≤ +3 AND final land_value ≤ 9 per `acore_axioms` §land_improvement L207-215. Improvements lose 1gp value per gp pillaged. During sieges, treat as wooden structures (×8 SHP-to-gp multiplier).
- `engine/subsystems/session/handlers/domain_handlers.gd` — replace `_resolve_domain_month` to delegate into the resolvers above and write `ledger_entries` for every revenue/expense subcategory.
- `engine/autoloads/event_bus.gd` — add `domain_followers_arrived`, `classification_advanced`, `classification_regressed`, `domain_treasury_changed`, `bandit_spawned`, `domain_event_resolved`, **`[RAW PATCH]`** `stronghold_sufficiency_changed`, `land_value_improved`.

**Verification:** new `tests/test_domain_revenue_calculator.gd`, `tests/test_domain_expense_calculator.gd`, `tests/test_domain_morale_resolver.gd`, `tests/test_classification_advancement.gd`, **`[RAW PATCH]`** `tests/test_land_improvement.gd`, `tests/test_repression.gd`, `tests/test_insufficient_stronghold_morale.gd`, `tests/test_income_gate_below_sufficiency.gd`, plus extend `tests/test_session_p3_spawn_roster.gd`-style harness with `tests/test_domain_monthly_tick_raw.gd` running 12-month simulation against hand-computed fixtures from `acore_axioms_strongholds_and_domains.xml` worked examples (target benchmarks per §domain_income L259-263: Wilderness ~5gp/fam net, Borderlands ~6gp, Civilized ~7gp).

---

## Phase 1 — Stronghold Construction

Hard prerequisite for Phase 2's Stronghold sub-tab; also unblocks Phase 0's sufficiency calc (morale needs `stronghold_value` per domain). Driven by `gdd-stronghold-construction.md`.

**Schema migrations:**
- `055_strongholds.sql` — `strongholds(id, domain_id, owner_character_id, archetype, structure_type, gp_value, shp, ac, garrison_capacity, completion_pct, is_conforming_to_class, is_claimed, claimed_from_source, location_hex_q, location_hex_r)`. The `gp_value` column drives sufficiency: civilized minimum = 15,000gp per 6-mile hex, borderlands = 22,500gp, wilderness = 32,000gp, per `acore_axioms` §minimum_stronghold_value L88-94.
- `056_stronghold_commissions.sql` — `stronghold_commissions(id, stronghold_id, gp_committed, daily_construction_rate_gp, supervisor_character_id, magic_assisted, started_calendar_day, completed_calendar_day, status)`.
- `057_stronghold_accessories.sql` — `stronghold_accessories(id, stronghold_id, accessory_type, gp_value, status)` for towers / battlements / civilian additions.

**Data files:**
- `data/strongholds/structure_catalog.json` — keeps, towers, walls, halls, gatehouses, etc. with cost / SHP / AC / dimensions / construction-rate / personnel-capacity per `daw_equipment_and_construction.xml`.
- `data/strongholds/archetype_presets.json` — fighter castle, mage tower, cleric cathedral, assassin hideout, venturer trading post, dwarven hold, elven fastness, halfling moot, beastman clanhold (chaotic), **`[RESOLVED 2026-05-06]`** Lightblessed Wonderworker sanctum (project name for the ACKS Player's Companion "Nobiran Wonderworker" class, renamed for IP per `pc_classes_5.xml` L2-7; archetype is a great tower / sanctum per `pc_classes_5.xml` §stronghold_sanctum L127-134) per per-class follower table.
- `data/strongholds/npc_generation_templates.json` — for setting-gen NPC stronghold creation per `acore-setting-construction-rules.xml`.

**Engine changes:**
- `engine/subsystems/strongholds/` (new):
  - `stronghold_cost_calculator.gd` — per-class archetype rules, magic-assisted discount (Wall of Stone, Move Earth, etc.), divine-favor cleric discount.
  - `commission_pipeline.gd` — start commission, monthly progress tick, supervisor-bonus +5% / +10%, worker-hire integration.
  - `stronghold_repository.gd` — CRUD; sufficiency calc per domain (sum of stronghold gp_value vs. per-hex minimum from `acore_axioms` §minimum_stronghold_value L88-94, summed across all owned 6-mile hexes; for noncontiguous territory, the combined value must secure both noncontiguous hexes and intervening hexes per §noncontiguous_domains L95-98). On every change, emit `EventBus.stronghold_sufficiency_changed` so morale resolver can re-base.
  - `claiming_resolver.gd` — claim ruined / inherited / conquered structures. **`[RESOLVED 2026-05-06]`** A `is_conforming_to_class` flag is computed for **display-only** purposes (so the UI can show e.g. "fighter ruling from a converted mage tower"), but per RAW it has **no mechanical effect**: followers, garrison, morale, and campaign activities are all gated by stronghold gp-value sufficiency only (per `acore_axioms` §minimum_stronghold_value L88-94 and §insufficient_stronghold L452-456), not by archetype match. The previously proposed "non-conforming blocks followers" gate is removed.
- `engine/autoloads/campaign_repository.gd` — add `create_stronghold`, `list_domain_strongholds`, `get_stronghold_value_for_domain`.
- `engine/autoloads/event_bus.gd` — `stronghold_commission_started`, `stronghold_construction_progressed`, `stronghold_completed` (already declared — wire emitter), `stronghold_claimed`, `stronghold_destroyed`.

**UI (separate from Domain tab):**
- `scenes/ui/strongholds/commission_wizard.tscn` + `.gd` — structure picker, archetype filter, supervisor selection, gp commit, magic-assist toggle, worker-count input. Cross-activated from Domain tab Phase 4.
- `scenes/ui/strongholds/claim_modal.tscn` — claim existing structure dialog.

**Verification:** `tests/test_stronghold_cost_calculator.gd`, `tests/test_commission_pipeline.gd`, `tests/test_claiming_resolver.gd`. Manual: launch via `Godot_v4.6.1-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn` after `--import` to refresh `.uid`.

---

## Phase 2 — Domain Tab Shell + Overview + Treasury + Establish-Domain

First **player-facing** milestone. Boots the tab off its empty-state placeholder.

**Engine changes:**
- `engine/subsystems/domains/establish_domain_flow.gd` — branches for civilized (grant + purchase + conquest), borderlands (clear + conquest + grant), wilderness (clear + conquest + clanhold-annex), with class restrictions (Explorer = borderlands/wilderness only; dwarven = dwarven hold; elven = elven fastness/halfling = moot per `acore_demihuman_classes.xml`); chaotic-aligned PC opt-in toggle per O-D6.
- `engine/subsystems/domains/treasury.gd` — domain treasury data model: gp held in stronghold vault, distinct from `characters.coin`. **`[RESOLVED 2026-05-06]`** Treasury access rules (formerly O-D2; implied by RAW that money does not teleport in ACKS): (a) **Domain-level uses are free regardless of ruler location** — the engine deducts directly from the domain treasury for investments, commissioning structures, paying garrison/liturgies/maintenance/tithes, executing tribute, and other domain-scoped expenditures, even when the ruler is elsewhere; (b) **personal purchases cannot be funded directly from the domain treasury** — the gp must first be moved into `characters.coin`, which requires the PC to be physically present at one of the domain's strongholds (the ruler picks up the coin in person); (c) **inter-settlement transfers are not free** — moving treasury gp to another settlement requires the PC or a trusted carrier to physically transport it, which is a travel-with-treasure event subject to wilderness encounters and theft. The UI exposes "Withdraw to personal coin" only when the active PC is at a stronghold belonging to the domain; the action greys out elsewhere with a tooltip explaining the rule. **`[RAW PATCH]`** Treasury sub-tab also exposes a "Land Improvement" investment line that consumes 25,000 gp and increments `domain_hexes.land_improvement_gp` for the selected hex by 1, blocked if the hex is already at +3 or if final land value would exceed 9, per `acore_axioms` §land_improvement L207-215.
- `engine/subsystems/domains/active_adventuring_detector.gd` — **`[RESOLVED 2026-05-06]`** Active-adventuring is defined for the project as: **the ruler left the stronghold during the prior game month AND any of: (a) wilderness encounter resolved, (b) lair entered, (c) hex cleared, (d) dungeon entered, (e) battle resolved, (f) siege participated in (attacker or defender), or (g) returned to any friendly settlement with 1,000 gp or more in new treasure/loot since departure.** This satisfies the RAW phrase "the character actively adventures at least once per month and keeps the domain secure" (`acore_axioms` §active_adventuring_growth L137, §domain_growth.investments L132-135, `ax_campaign_play` §start_of_month.adventuring L9-11) which the rulebook does not define mechanically. The detector listens to `EventBus` for these triggers (`combat_resolved`, `lair_entered`, `hex_cleared`, `dungeon_entered`, `siege_event`, `treasure_acquired`, plus the ruler's `entity_position_changed` to detect stronghold-departure) and, at start-of-month, sets `domains.is_active_adventuring_this_month = true` if any qualifying trigger fired during the prior month and the ruler was away from the stronghold for at least one game day. The 1,000 gp threshold is computed as new treasure acquired and physically returned to a settlement, not gold spent or earned from passive sources (revenue, tribute, hireling income).

**UI:**
- `scenes/ui/notebook/tab_pages/domain_tab_page.gd` — replace empty-state with full nine-sub-tab strip **`[ARCH 2026-05-06]`** (Overview / Stronghold / Garrison / Realm / Treasury / **Decrees & Remote Orders** / Class-Specific / Encounters / Departure Log) keyed to active entity. The 6th sub-tab — formerly "Activities" — is renamed and repurposed per `gdd-domain-tab.md` §11 (rewritten 2026-05-06). Implement entity strip filter (PCs + Humanoid Henchmen only) per `gdd-management-notebook.md` §6.1.
- `scenes/ui/notebook/domain/status_header.tscn` — domain name (editable, default "Untitled Domain"), classification + sufficiency, population, treasury, garrison meter, morale band. Visible across all sub-tabs.
- `scenes/ui/notebook/domain/sub_tabs/overview.tscn` — identity card, demographic composition, growth/decline history, land-value summary (with **`[RAW PATCH]`** per-hex breakdown showing base 3d3 value plus any land_improvement_gp), classification progress, morale, editable tax/liturgy/tithe steppers (each dispatches an `issue_decree` activity per `gdd-realtime-scheduler.md` §4.8).
- `scenes/ui/notebook/domain/sub_tabs/treasury_ledger.tscn` — treasury display, monthly income/expense forecast, **`[RAW PATCH] insufficient-stronghold income-gate banner` (yellow if revenue is currently zeroed because stronghold_value < classification_minimum, per `acore_axioms` §peasants_and_followers L108-109)**, unpaid-expense alerts, auto-pay policy toggles, virtualized ledger list (filterable / searchable / exportable), Land Improvement investment button.
- `scenes/ui/notebook/domain/establish_domain_dialog.tscn` — branches per classification + class + chaotic-toggle.
- D-key keybind via `UiInputController` per `gdd-ui-shared-services.md` §3.

**Verification:** boot game, establish a civilized domain via grant, advance one month via scheduler, see treasury / ledger / morale numbers match a hand-computed fixture; switch active entity; verify per-entity-per-tab state persists across switches per `gdd-management-notebook.md`. **`[RAW PATCH]`** Boot a wilderness domain with stronghold_value below 32,000gp/hex, advance one month, verify revenue=0 and growth=0 and that the income-gate banner is visible. **`[RESOLVED 2026-05-06]`** `tests/test_active_adventuring_detector.gd` — exercise each of the seven trigger conditions in isolation (wilderness encounter, lair entry, hex cleared, dungeon entry, battle, siege, treasure-return ≥1,000 gp), verify each sets `is_active_adventuring_this_month`; verify a ruler who never leaves the stronghold returns false even when treasure or combat events fire elsewhere; verify the 1,000 gp treasure threshold is computed from new acquisitions returned to a settlement, not from accumulated revenue, tribute, or hireling-paid wages.

---

## Phase 3 — Activity Time-Cost Executor + Decrees & Remote Orders + Per-Location Launch Wiring

**`[ARCH 2026-05-06]`** Phase 3 was rewritten on 2026-05-06 to remove a regression to the deprecated daily-slot-picker UX. The replacement model is canonical per `gdd-realtime-scheduler.md` §4.8: activities carry RAW-derived time costs and execute through the `EventScheduler`; the day's slot quotas (1 major + 2 minor / 8 minor) emerge naturally from a finite ~8-hour active-work budget rather than being enforced as UI constraints; activities launch from their location of execution, not from a centralized picker; tick-tolerance applies only to Ongoing-frequency activities. See `gdd-realtime-scheduler.md` §4.8 for the canonical engine model and `gdd-domain-tab.md` §11 for the Decrees & Remote Orders sub-tab spec.

**Engine changes:**

- `engine/subsystems/activities/activity_catalog.gd` — registry of activity definitions (id, frequency, time_cost_rounds, strenuous flag, location requirement, prerequisites). Activity definitions are loaded from `data/activities/*.json` keyed off `ax_campaign_play.xml` activity entries.
- `engine/subsystems/activities/activity_time_cost_executor.gd` — wraps each launched activity as a `ScheduledEvent` per the canonical model in `gdd-realtime-scheduler.md` §4.8.3:
  - **Singular launch:** schedules one `activity_complete` event at `fire_time = now + time_cost_rounds`. Cancellation (combat trigger, location loss, player cancel) is the abandonment path and produces clean failure with no partial credit. Atomic per `ax_campaign_play` §frequency_types.singular L152-155.
  - **Restricted launch:** same as Singular plus a per-period cooldown write to `restricted_cooldowns[entity_id][activity_def_id] = now + restricted_period_rounds` on completion.
  - **Ongoing daily-session launch:** at the start of each day, schedules an `ongoing_session_complete` event at `fire_time = day_start + session_time_cost_rounds`. On uninterrupted fire, `ticks_accumulated += 1` and `EventBus.activity_tick_earned` emits; the entity is then free for the rest of the day. On interruption before fire (combat, location loss, player cancel), the day's session is cancelled and no tick is banked, but prior accumulated ticks are preserved. Tick-tolerance per `gdd-domain-tab.md` §15.1 applies.
- `engine/subsystems/activities/strenuous_accountant.gd` — background tracker for `character_activity_state(character_id, strenuous_days_in_streak, overtime_days_in_streak, last_rest_day)` per `ax_campaign_play` §effort_rules L166-172 and §overtime_rules L173-186. Increments on strenuous-tagged activities; resets on Rest. Applies cumulative −1 penalty to attack throws, damage, and proficiency throws once the streak exceeds 6 days. **Does NOT gate activity launches** — it accrues consequences silently per `gdd-realtime-scheduler.md` §4.8.5.
- `engine/subsystems/activities/handlers/` — one handler per RAW activity. Domain-category handlers from `ax_campaign_play.xml` §domain: `administer_domain.gd`, `issue_decree.gd`, `call_to_arms.gd`, `conscript_troops.gd`, `levy_militia.gd`, `hire_mercenaries.gd`, `inspect_troops.gd`, `train_troops.gd`, `oversee_troop_training.gd`, `oversee_construction.gd`, `oversee_investment.gd`, `manage_henchmen.gd`, `military_campaign.gd`, `solicit_mercenaries.gd`, `supervise_construction.gd`, **`[RAW PATCH]`** `repress_population.gd` (sets `domains.is_repressed_this_month=true` and `repression_gp_per_family_this_month` based on troops assigned; militia troops are not eligible per `acore_axioms` §repression L511).
- **`[ARCH 2026-05-06]`** Adventuring-, settlement-, and stronghold-category handlers are scaffolded here in a separate folder (`handlers/adventuring/`, `handlers/settlement/`, `handlers/stronghold/`) with stubs and acceptance contracts so location-launch wiring can hook them in subsequent phases. Filling them in is incremental work spread across Phases 4-9; Phase 3 lands the executor + the domain handlers + the contracts.
- `data/activities/domain_category.json` — RAW spec for every activity in `ax_campaign_play.xml` §domain. Each entry: `id`, `frequency` (singular / restricted / ongoing), `time_cost_rounds`, `strenuous` flag, `location_kind` (e.g., "anywhere", "in_domain", "at_stronghold", "at_settlement", "at_construction_site"), `prerequisites`, `effect_summary`. Duration formulas where RAW provides them (e.g., `administer_domain_days = 0.5 × (hex_count + vassal_count + (6 − market_class))` per `acore_axioms` §administration L526-529).

**Schema:**

- `058_activity_state.sql` — `activity_state(id, character_id, activity_id, status, ticks_accumulated, absence_accumulated, started_calendar_day, location_required, gp_committed)` — used only for Ongoing-frequency activities. Singular and Restricted activities resolve atomically through the EventScheduler and don't persist state between days.
- `058a_character_activity_state.sql` — **`[ARCH 2026-05-06]`** `character_activity_state(character_id, strenuous_days_in_streak, overtime_days_in_streak, last_rest_day)` for the strenuous accountant.

**UI:**

- **`[ARCH 2026-05-06]`** `scenes/ui/notebook/domain/sub_tabs/decrees_and_remote_orders.tscn` — replaces the prior Activities sub-tab. Renders only the small set of remote-capable activities per `gdd-domain-tab.md` §11.1: administer_domain (ongoing remote), issue_decree (singular remote, with decree-type sub-flow), manage_henchmen (trivial ongoing, no location), conscript_troops (ongoing remote), levy_militia (ongoing remote), solicit_mercenaries (ongoing), call_to_arms (ongoing remote, ruler of realm only), oversee_investment (ongoing remote). Each card uses the layout from `gdd-domain-tab.md` §11.2.
- `scenes/ui/notebook/domain/decree_card.tscn` — compact card for singular decrees and remote ongoing activities.
- **`[ARCH 2026-05-06]`** Per-location activity launch wiring — Phase 3 lands the **integration contracts** between the activity executor and the location surfaces; the location surfaces themselves are filled by their owning phases (settlement panel → existing/future Settlement Panel work; stronghold UI → Phase 4; wilderness/dungeon → existing exploration UI). Phase 3 deliverable: a documented `ActivityLaunchContext` data shape (`{entity_id, activity_def_id, location_ref, params}`) consumed by the executor, plus stub launch buttons in the existing UI surfaces that already have activity-relevant UX (e.g., the Settlement Panel HiringPanel for hire_mercenaries — already exists; just needs wiring to the executor).
- **`[ARCH 2026-05-06]`** `scenes/ui/notebook/character/sub_tabs/active_projects.tscn` — new Character-tab sub-tab per `gdd-character-tab.md` §3.8. Read-only project list showing every Ongoing activity for the active character with progress / absence / tolerance / status, and Inspect-math + Abandon affordances. Subscribes to `EventBus.activity_tick_earned`, `activity_completed`, `activity_forfeited`, plus entity-presence events.
- Pre-9 entities see all Decrees & Remote Orders normally per `acore_axioms` §before_ninth_level L121 ("the character may still make investments to attract peasants or hire mercenaries"); only follower auto-attraction is gated by L9.

**Verification:**

- `tests/test_activity_time_cost_executor.gd` — schedule a Singular activity, advance time to fire, verify `activity_complete` event handler runs; cancel mid-execution, verify no partial credit and clean failure.
- `tests/test_activity_executor_ongoing_tick_accrual.gd` — schedule an Ongoing activity, advance one game-day with no interruption, verify `ticks_accumulated += 1`; advance another day with interruption before fire_time, verify no tick is banked and prior tick is preserved.
- `tests/test_activity_executor_singular_no_partial_credit.gd` — **`[ARCH 2026-05-06]`** verify that interrupting a Singular or Restricted activity produces total failure with no `ticks_accumulated` or partial-credit field set; ensure the engine does not invoke tick-tolerance logic for these frequency types.
- `tests/test_activity_executor_tick_tolerance.gd` — multi-day Ongoing scenario: 5 days at location, 4 days absence, return for 1 day, etc. — verify tick / absence math from `gdd-domain-tab.md` §15.1.2.1 worked example.
- `tests/test_strenuous_accountant.gd` — 6 strenuous-day streak applies −1 penalty starting day 7; Rest day on day 7 resets the streak.
- **`[RAW PATCH]`** `tests/test_repress_population_morale_cap.gd` — verify current morale cannot exceed 0 while repressed even with high repression bonus, per `acore_axioms` §repression L515.
- Manual: queue `administer_domain` from Decrees & Remote Orders, advance days, verify daily ticks accumulate against the formula-derived target; travel away, verify absence accumulates and the canonical pre-departure warning modal fires when `(absence + projected_trip_days) > ticks_accumulated` per `gdd-domain-tab.md` §15.1.5.

---

## Phase 4 — Stronghold Sub-Tab + Sufficiency Feedback

Surfaces Phase 1's data inside the Domain tab and closes the morale-feedback loop.

**UI:**
- `scenes/ui/notebook/domain/sub_tabs/stronghold.tscn` — structure list per domain (name / type / value / sufficiency contribution), in-progress construction with progress bar, **`[RESOLVED 2026-05-06]`** non-conforming-archetype indicator (display-only, no mechanical effect; per the O-D10 resolution, conforming-vs-non-conforming is a UI flavor flag and does not gate followers, garrison, morale, or activities), divine-favor discount indicator (Cleric/Bladedancer), multi-stronghold combined-value card. **`[RAW PATCH]`** Sufficiency gauge shows three threshold ticks: ≥½ minimum (−1 morale), ≥¼ minimum (−2 morale), <¼ minimum (−3 morale), per `acore_axioms` §insufficient_stronghold L452-456; plus an "income-gated" red badge when stronghold_value < classification_minimum (per §peasants_and_followers L108-109). "Commission new structure" cross-activates Phase 1's `commission_wizard.tscn`. "Claim existing structure" cross-activates `claim_modal.tscn`.

**Engine wiring:**
- `domain_morale_resolver.gd` (Phase 0) consumes `stronghold_repository.get_stronghold_value_for_domain` for sufficiency calculation. **`[RESOLVED 2026-05-06]`** No conforming/non-conforming gate on followers; per the O-D10 resolution, follower attraction is gated by stronghold gp-value sufficiency only, per `acore_axioms` §minimum_stronghold_value L88-94 and §followers_arrival L111-116.
- Subscribe to `EventBus.stronghold_completed` → highlight new structure + reroll morale base. **`[RAW PATCH]`** Subscribe to `EventBus.stronghold_sufficiency_changed` → refresh sufficiency gauge and income-gate badge.

**Verification:** commission a stronghold, advance time until it completes, verify domain morale base bumps from "−2 insufficient" to "0 sufficient" per `acore_axioms` §insufficient_stronghold L452-456; **`[RAW PATCH]`** verify the income gate releases the moment sufficiency is reached (revenue and growth resume on the next monthly tick).

---

## Phase 5 — Troops Tab + Garrison Sub-Tab + L9 Follower Arrival

Parallelizable with Phase 4. Driven by `gdd-troops-tab.md` v2.3+.

**Schema:**
- `059_troop_units.sql` — `troop_units(id, campaign_id, owner_character_id, assigned_domain_id, source_type, troop_type, count, battle_rating, monthly_cost_gp, morale, is_veteran, is_trained)` per `daw_armies_recruitment.xml` six sources (mercenaries / conscripts / militia / followers / slave_soldiers / vassal_troops).
- `060_followers_arrival_log.sql` — `follower_arrivals(id, domain_id, calendar_day, wave_pct, follower_count_total, equipment_kit)` for the **`[RAW PATCH]` half-rounded-up / additional-quarter-rounded-up / remainder** wave schedule per `acore_axioms` §followers_arrival L111-116 (NOT a flat 50/25/25; if total followers = N, wave 1 = ceil(N×0.5), wave 2 = ceil(N×0.25), wave 3 = N − wave 1 − wave 2).

**Data:**
- `data/troops/unit_templates.json` — per-source unit specs (cost, BR, morale base, training requirements).
- `data/followers/per_class_tables.json` — extracted from `pc_followers_tables_rules.xml` per-class structure (e.g., fighter L9 stronghold attracts 5d6×10 0th-level soldiers + 1d6 lieutenants; cleric attracts congregation + acolytes; etc.).

**Engine:**
- `engine/subsystems/troops/troop_unit_repository.gd`.
- `engine/subsystems/troops/follower_arrival_resolver.gd` — fires at 50% stronghold completion, 100% completion, +1 month after completion; only L9+ per `acore_axioms` §before_ninth_level L117-123. **`[RESOLVED 2026-05-06]`** No conforming-archetype gate (per O-D10 resolution): follower arrival is gated only by L9+ status and stronghold gp-value reaching the per-hex classification minimum (15k civilized / 22.5k borderlands / 32k wilderness per `acore_axioms` §minimum_stronghold_value L88-94). Generates troop_units + writes `follower_arrivals`.
- `engine/subsystems/troops/garrison_expenditure_calculator.gd` — sum of troop_units monthly_cost_gp assigned to domain; **`[RAW PATCH]`** comparison vs. **2gp/family universal minimum** per `acore_axioms` §garrison L218, L226-227. Surface a separate "morale-incentive band" indicator: in Borderlands, paying 3gp/fam (1gp above minimum) earns +1 base morale per §additional_troops L462; in Wilderness, paying 4gp/fam earns +1 (note: §garrison L233 also says wilderness "must maintain 4gp per family or base morale is reduced" — implementation should treat the wilderness-3gp-only state as a base morale reduction, not a hard expense floor); paying 5gp+/fam in Wilderness earns +2 per §additional_troops L463-464. Chaotic domains add +2gp to garrison cost per `ax_domains_of_chaos` §exceptions_from_clanholds L86.

**UI:**
- `scenes/ui/notebook/tab_pages/troops_tab_page.gd` — full troops tab roster per `gdd-troops-tab.md` (cross-cuts beyond domain).
- `scenes/ui/notebook/domain/sub_tabs/garrison.tscn` — assigned units, **`[RAW PATCH]`** expenditure meter showing two reference lines: solid line at 2gp/fam minimum (red below), dashed line at the morale-incentive threshold for the current classification (green at or above), recruitment buttons (Call to Arms / Conscript / Levy Militia / Hire Mercenaries — all cross-activate Phase 3 activity executor), **`[RAW PATCH]`** "Repress" toggle (assigns N gp/family above minimum to repression; militia troops greyed out as ineligible per `acore_axioms` §repression L511; warning that current morale cannot exceed 0 while active).

**Verification:** complete a fighter castle at L9, verify follower waves arrive on schedule, verify garrison expenditure reduces dungeon-incursion encounter penalty per `ax_domain_level_encounters.xml` (becomes Phase 9's hook). **`[RAW PATCH]`** `tests/test_follower_arrival_rounding.gd` verifying the ceil(N×0.5) / ceil(N×0.25) / remainder math, including the edge case where ceil(N×0.5) + ceil(N×0.25) > N×0.75.

---

## Phase 6A — DaW Army Warfare Layer: Composition + Marching + Supply + Vagaries

**`[ARMY 2026-05-06]`** First half of the new Phase 6. Builds armies as aggregates of troop_units (from Phase 5), with command hierarchy, marching across the wilderness map, supply consumption, foraging, and recruitment vagaries. **No battle resolution yet** — that's Phase 6B. The split lets bandits-without-sieges potentially be playable in Phase 9 if Phase 6B slips, since bandit "armies" can exist (and march and consume supply) before they have to fight.

Drafting authority: this phase's design lives in the new `gdd-army-warfare.md` (scaffold checked in; needs a dedicated drafting session before build starts). All RAW citations route through `daw_armies_recruitment.xml`, `daw_campaigns_troop_tables_summary.xml`, `daw_campaigning_armies.xml`, and `daw_vagaries.xml`.

**Schema migrations:**

- `065_armies.sql` — `armies(id, campaign_id, owner_character_id, command_character_id, army_name, current_hex_q, current_hex_r, current_map_id, current_state, formed_calendar_day, disbanded_calendar_day)`. `current_state ∈ {assembling, encamped, marching, foraging, besieging, battling, withdrawing, disbanded}`. Owner is the political owner (PC ruler or NPC); command_character_id is the leading officer (often the same, but vassals may command on behalf of their liege).
- `066_army_unit_assignments.sql` — `army_unit_assignments(id, army_id, troop_unit_id, assigned_calendar_day, command_role)`. `command_role ∈ {line, reserve, baggage, scout}`. A troop_unit can be in at most one army at a time; enforced by unique constraint on `troop_unit_id` where `army_id IS NOT NULL`.
- `067_army_officer_assignments.sql` — `army_officer_assignments(id, army_id, officer_character_id, rank, commands_units_csv)` per the four-tier hierarchy in `daw_campaigns_troop_tables_summary.xml`: Lieutenants (≤3 units), Captains (≤3 lieutenants), Colonels (≤3 captains), Generals (≤3 colonels). Each rank has a market-class availability + monthly wage from the troop tables. `commands_units_csv` is the list of troop_unit_ids or sub-officer_ids this officer commands.
- `068_army_supply_state.sql` — `army_supply_state(army_id PRIMARY KEY, current_supply_gp, daily_consumption_gp, supply_line_status, last_resupply_day, foraged_gp_this_week)`. `supply_line_status ∈ {intact, threatened, cut}`.
- `069_army_movement_log.sql` — `army_movement_log(id, army_id, calendar_day, from_hex_q, from_hex_r, to_hex_q, to_hex_r, distance_miles, encounter_rolled, foraging_rolled, weather)` for after-action review.

**Engine subsystems:**

- `engine/subsystems/armies/army_repository.gd` — CRUD; query "all armies in hex H," "armies belonging to character C," "armies under command of officer O."
- `engine/subsystems/armies/army_composer.gd` — form army from selected troop_units; add/remove units; assign officers to ranks; validate command-hierarchy completeness (every unit must be commanded by a Lieutenant; every Lieutenant by a Captain; etc.); compute `aggregate_battle_rating` and `Leadership Ability` (caps redeploy units per turn) and `Strategic Ability` (initiative bonus) from the commanding officer's profile per `daw_campaigns_troop_tables_summary.xml` officer ability tables.
- `engine/subsystems/armies/army_marcher.gd` — extends the `travel_leg` event pattern from `gdd-realtime-scheduler.md` §4.1 for armies. Per-leg fire_time = travel time at army speed (= slowest unit's speed). On each leg arrival: army-encounter check (different table than party encounters per `daw_campaigning_armies.xml`), army-army collision check (if hex contains another army, trigger battle dispatcher), supply consumption, foraging opportunity. Weather effects per `daw_campaigning_armies.xml`. Forced marches per the same.
- `engine/subsystems/armies/army_supply_tracker.gd` — daily supply_gp consumption from current_supply_gp; per-day foraging roll if commanded to forage (yields 1d6 × army-size-tier gp food per `daw_campaigning_armies.xml`); supply-line status calculation (intact = within X miles of friendly settlement / waterway / supply train; threatened/cut induce attrition per the campaigning RAW); resupply on entering a friendly settlement.
- `engine/subsystems/armies/army_collision_detector.gd` — when two armies share a hex, emits `EventBus.armies_collided`; consumed by Phase 6B's battle dispatcher to start a field battle.
- `engine/subsystems/armies/recruitment_vagaries_resolver.gd` — recruitment vagaries per `daw_vagaries.xml`. Triggered on Conscript / Levy Militia / Hire Mercenaries / Solicit Mercenaries / Call to Arms. Outcomes per the vagaries tables (delays, deserters, surge availability, leader applicants, etc.). Hooks the existing `EventBus.vagaries_of_recruitment` signal already fired in the campaign-activities phase per `ax_campaign_play.xml` §random_events.vagaries_of_recruitment.
- `engine/subsystems/armies/army_disbander.gd` — disband army on owner command, on commander death without designated successor, or on supply-attrition collapse. Returns mercenary units to the pool (less casualties); discharges conscripts/militia (return to peasant population); followers persist as faithful followers per `acore_axioms` §garrison L228-230.

**EventBus signals (additions):**

- `army_formed(army_id, owner_id, command_officer_id)`
- `army_disbanded(army_id, reason)`
- `army_arrived_at_hex(army_id, hex_q, hex_r, map_id)`
- `armies_collided(army_a_id, army_b_id, hex_q, hex_r)` — consumed by Phase 6B
- `army_supply_consumed(army_id, gp, remaining_gp)`
- `army_supply_threatened(army_id, cause)`
- `army_supply_cut(army_id, cause)`
- `recruitment_vagary_resolved(activity_id, outcome_type, payload)`

**Activity handlers (extend Phase 3's `handlers/`):**

- Update `engine/subsystems/activities/handlers/conscript_troops.gd`, `levy_militia.gd`, `hire_mercenaries.gd`, `solicit_mercenaries.gd`, `call_to_arms.gd` to fire through `recruitment_vagaries_resolver.gd` and to optionally form / supplement an army on completion if the player elects.
- New `engine/subsystems/activities/handlers/form_army.gd` — Singular activity (1 game-hour) that takes a list of troop_units and an officer assignment plan, validates, creates the army record. Launched from the extended Troops tab Armies section.
- New `engine/subsystems/activities/handlers/march_army.gd` — Ongoing activity. Player issues a destination order; the army_marcher schedules per-leg events; the Ongoing-frequency state on the activity is "until destination reached or commander cancels." Heavy reuse of existing `travel_leg` infrastructure.

**UI (extend Troops tab; no new tab):**

- `gdd-troops-tab.md` extension — add an "Armies" section to the Troops tab. Vertical list of armies the active entity owns or commands; each card shows: name, command officer + rank, unit composition summary (e.g., "12 units · 850 BR"), current state (assembling / marching / etc.), current location, supply remaining (% bar with daily-burn projection). Click → expands into army detail panel with full unit roster, officer hierarchy tree, supply log, movement log.
- New `scenes/ui/troops/army_form_dialog.tscn` — pick troop_units from the unaligned pool, assign officers to fill the command hierarchy, name the army, confirm.
- New `scenes/ui/troops/army_march_overlay.tscn` — when an army is marching, the wilderness hex map renders the army token with a path overlay (similar to the existing party-token movement renderer). Right-click on a hex with the army selected → "March here" / "March cautiously here (slower, +foraging)" / "Forced march here (faster, fatigue)" / "Encamp here" / "Foreage at current hex."

**Verification:**

- `tests/test_army_composer.gd` — form army, validate command-hierarchy completeness, compute aggregate BR.
- `tests/test_army_marcher.gd` — march an army across 5 hexes, verify supply consumption, encounter checks, weather effects.
- `tests/test_army_supply_tracker.gd` — supply-line status transitions, foraging yields, attrition under "cut" status.
- `tests/test_army_collision_detector.gd` — two armies arrive in the same hex on the same scheduler tick → `armies_collided` fires once with deterministic ordering.
- `tests/test_recruitment_vagaries_raw.gd` — verify each vagaries-table outcome from `daw_vagaries.xml` fires with correct payload.
- Manual: PC at L9 hires 5 mercenary units, forms an army with a Lieutenant + Captain, marches it 4 hexes through wilderness, verify supply dwindles, foraging supplements, weather slows on a rainy day, and the army arrives at the destination hex with the expected remaining supply.

---

## Phase 6B — DaW Army Warfare Layer: Abstract Field-Battle Resolver + Casualties + Pursuit + Heroic Forays

**`[ARMY 2026-05-06]`** Second half of the new Phase 6. Builds the abstract field-battle resolver per `daw_axioms_pitching_battle.xml` §battle_resolution L233-386 (no map; three-phase missile / skirmish / melee with BPC-driven transitions and BR-vs-BR attack throws). This unblocks Phase 9's bandits (small armies that fight) and the assault phase of sieges (army-on-army within the siege-resolver's assault step).

Drafting authority: design lives in `gdd-army-warfare.md` §6 (per the scaffold).

**Schema migrations:**

- `070_field_battles.sql` — `field_battles(id, attacker_army_id, defender_army_id, hex_q, hex_r, terrain, battle_phase, bpc_current, started_calendar_day, ended_calendar_day, end_state, end_state_details_json)`. `battle_phase ∈ {missile, skirmish, melee, ended}`. `end_state ∈ {attacker_routed, defender_routed, voluntary_withdrawal, mutual_withdrawal, draw}`.
- `071_battle_unit_states.sql` — `battle_unit_states(id, battle_id, troop_unit_id, current_zone, casualties_taken, morale_state)` per-unit per-battle state. `current_zone ∈ {missile, skirmish, melee, reserve}`. `morale_state ∈ {steady, shaken, broken, fled, destroyed}`.
- `072_battle_log.sql` — `battle_log(id, battle_id, sequence, phase, event_type, actor_id, target_id, payload_json)` for after-action review and replay.

**Engine subsystems:**

- `engine/subsystems/armies/battle_dispatcher.gd` — when `EventBus.armies_collided` fires (or when a siege assault step is triggered), the dispatcher routes to the field-battle resolver. If any participant army is owned/commanded by a PC or PC's henchman, route to the **interactive** path (auto-pause, present field-battle UI for player decisions); otherwise resolve **silently** (engine plays both sides, logs results to world log, emits notifications).
- `engine/subsystems/armies/field_battle_resolver.gd` — implements the procedure per `daw_axioms_pitching_battle.xml` §battle_resolution L233-386:
  - **Setup**: each side assigns units to zones (missile / skirmish / melee / reserve); set BPC starting count from terrain per §battlefield_phase_count_starting_values; resolve surprise per §surprise.
  - **Per-phase loop** (missile → skirmish → melee, transitioning when BPC ≤ 0):
    1. Determine participating units per phase (zone-bound).
    2. Each side totals participating BR.
    3. Heroic forays: PCs and named NPCs may declare; resolved simultaneously per §heroic_forays.
    4. Each side rolls `attack_throws = remaining_BR`; targets per-phase (missile 18+, skirmish 16+, melee 14+ per the table at L208-224); each success = 1 hit.
    5. Apply hits simultaneously; defender removes participating units with combined BR ≥ hits; overflow hits cascade to next zone (skirmish → melee → reserve).
    6. Morale check per phase end; broken/fled units leave the battle.
    7. Redeployment: each side may move units between zones up to Leadership Ability units per turn (officer-derived).
    8. Each side secretly chooses advance / hold / withdraw; reveal simultaneously; resolve BPC adjustment per L255-285.
    9. If BPC transitions cross threshold, advance to next phase or end battle.
  - **End states**: capture (defender army routed), liberation/withdrawal (attacker army routed), voluntary withdrawal (per §post_choice_outcomes), mutual withdrawal → draw.
- `engine/subsystems/armies/heroic_foray_resolver.gd` — PCs and named NPCs can declare heroic forays each phase per `daw_axioms_pitching_battle.xml` §heroic_forays. Player-controlled heroes get a decision modal; NPC heroes use behavior-tag heuristics per `gdd_combat_behavior_tags.md`. Resolves attack vs. target unit; success can route the target unit single-handedly; failure can wound or kill the hero.
- `engine/subsystems/armies/army_morale_resolver.gd` — army-level morale per `daw_axioms_pitching_battle.xml` §morale (distinct from individual combat morale; uses commander's Leadership + per-unit morale + battle situation). Triggers at end of each phase; cascading panic if multiple units route in one phase.
- `engine/subsystems/armies/army_casualty_resolver.gd` — apply unit losses to underlying troop_units (decrement count, mark veteran-status changes, mark destroyed if reduced below operational threshold per `daw_armies_recruitment.xml`). Persistent: the battle outcome modifies the source troop_unit records permanently.
- `engine/subsystems/armies/pursuit_resolver.gd` — winning side may pursue per the end-state rules at `daw_axioms_pitching_battle.xml` §pursuit. Pursuit is itself a brief mini-battle (attacker uses missile/skirmish targets; defender attempts to disengage); converts withdrawals into routs if pursuer wins.
- `engine/subsystems/armies/terrain_advantage_resolver.gd` — initial terrain assignment (advantageous / highly advantageous / neutral) per `daw_axioms_pitching_battle.xml` §advantageous_terrain L226-231 plus the terrain table; lost terrain advantage cannot be regained per the same.

**EventBus signals (additions):**

- `field_battle_started(battle_id, attacker_id, defender_id, hex_q, hex_r, terrain, is_player_involved)`
- `field_battle_phase_started(battle_id, phase, bpc)`
- `field_battle_phase_ended(battle_id, phase, hits_dealt_attacker, hits_dealt_defender, casualties_attacker, casualties_defender)`
- `field_battle_heroic_foray_resolved(battle_id, hero_id, target_unit_id, outcome)`
- `field_battle_ended(battle_id, end_state, surviving_units_attacker, surviving_units_defender)`
- `army_unit_destroyed(army_id, troop_unit_id, casualty_count)`

**UI:**

- New `scenes/ui/battle/field_battle_panel.tscn` — interactive field-battle UI for player-involved battles. Auto-pauses the scheduler. Shows: zone-by-zone unit display for both armies, BPC counter, current phase, heroic-foray hero list (with declare-foray buttons for PC heroes), redeployment dropdowns (within Leadership Ability cap), advance/hold/withdraw secret-choice control. Resolves one phase at a time on player Confirm.
- World log entries for NPC-vs-NPC battles per `gdd-unified-log-panel.md`. Notification toast on PC's allies' battles even when not directly involved (per `gdd-ui-architecture.md` §2.7).
- Troops tab Armies section adds post-battle review: most recent battle outcome card on each army row; click → opens `battle_log` viewer.

**Verification:**

- `tests/test_field_battle_resolver_missile_phase.gd` — set up a battle with both armies in missile zone; verify BR-vs-BR attack throws at 18+; correct hit application and casualty math; correct BPC transitions for each advance/hold/withdraw outcome combination per `daw_axioms_pitching_battle.xml` §post_choice_outcomes L255-285.
- `tests/test_field_battle_resolver_phase_transitions.gd` — verify missile → skirmish triggered when BPC ≤ 0 from "both advance" outcomes; verify withdraw-out-of-skirmish back to missile per §post_choice_outcomes L304-310.
- `tests/test_field_battle_resolver_terrain_advantage.gd` — army in advantageous terrain; verify forced "hold or lose advantage"; verify advantage is lost permanently if the army moves.
- `tests/test_field_battle_resolver_heroic_foray.gd` — PC hero declares foray on enemy unit; verify simultaneous resolution with other forays; verify successful foray can single-handedly route a unit per §heroic_forays.
- `tests/test_field_battle_resolver_morale_cascade.gd` — multiple units route in one phase; verify cascading morale check per §morale.
- `tests/test_field_battle_dispatcher_routing.gd` — PC-involved battle → interactive path with auto-pause; NPC-vs-NPC → silent resolve with world-log entry.
- `tests/test_pursuit_resolver.gd` — voluntary withdrawal → pursuer rolls; if pursuer wins, withdrawal becomes rout.
- `tests/test_army_casualty_persistence.gd` — battle ends; verify source troop_units' counts are decremented; verify destroyed-below-threshold units are marked destroyed.
- Manual: PC's L11 fighter army (10 units, 600 BR) attacks a wilderness bandit horde (15 units, 450 BR); battle resolves through all three phases; PC declares a heroic foray during melee and routes a bandit unit; battle ends in defender rout; pursuit converts the rout into a 50% casualty inflict; surviving bandits flee the hex.

---

## Phase 7 — Realm Sub-Tab + Vassalage + Tribute *(was Phase 6)*

**Schema:**
- `061_vassal_assignments.sql` — `vassal_assignments(id, liege_character_id, vassal_character_id, vassal_domain_id, assigned_calendar_day, status, is_henchman_vassal)` (vassal_character_id is a humanoid henchman per O-D resolution; **`[RAW PATCH]`** `is_henchman_vassal` distinguishes henchman vassals from non-henchman vassals, who have base loyalty −2 normally and −4 if outside the trade range of the ruler's largest urban settlement, per `acore_axioms` §non_henchman_vassals L392-397).
- Use existing `domains.liege_domain_id` (Phase 0) for the inverse pointer.

**Engine:**
- `engine/subsystems/domains/realm_aggregator.gd` — sum personal + vassal-domain families / revenue / expenses / garrison; cache per `EventBus.domain_state_changed`.
- `engine/subsystems/domains/tribute_calculator.gd` — `tribute_per_month = round(18 × realm_families^0.6)` per `acore_axioms` §tribute precise_optional_formula L299, or lookup table per `acore_axioms` §tribute_by_realm_families L300-350. **`[RAW PATCH] Tribute-efficiency factor by direct-vassal count, replacing the prior fabricated tiers, per `acore_axioms` §tribute_inefficiency L398-409:** ≤8 = 100%, 9-16 = 66%, **`[RESOLVED 2026-05-06]`** 17-63 = 50%, 64-216 = 33%, 217-1024 = 20%, 1025-4095 = 10%, 4096-16384 = 5%, 16384+ = 1%. The source XML at L405 reads "17-36 = 50%" leaving an algebraic gap from 37 through 63; per logarithmic-scaling and lower-bound-continuity analysis this is treated as a digit-transposition typo (3 ↔ 6) and read as 17-63. Implementation MUST encode the corrected reading in code constants while leaving the source XML unchanged per the sacred-rules constraint, with a code comment citing both the source line and this clarification.
- `engine/subsystems/domains/realm_title_resolver.gd` — Baron / Marquis / Count / Duke / Prince / King / Emperor by personal-domain-families × domains-ruled × overall-realm-families bands per `acore_axioms` §titles_of_nobility L273-285; sets muster-delay cadence per §muster_delay L373-382 (Baron-Count = Week, Prince-Duke = Month, King-Emperor = Season).
- Phase 0's monthly tick now writes a `tribute_in` ledger entry on the liege's domain and a `tribute_out` ledger entry on each vassal's domain; if vassal can't pay, triggers loyalty roll.

**UI:**
- `scenes/ui/notebook/domain/sub_tabs/realm.tscn` — title display, realm-family count + tribute calc, **`[RAW PATCH]` efficiency factor display showing direct-vassal count and corresponding RAW-table percentage**, vassal table (vassal name [click → switch active entity], domain families, loyalty band, tribute, active favors, **`[RAW PATCH]`** is-henchman vs. non-henchman badge), realm aggregates collapsible card. Empty-state when no vassals.
- Cross-activation: `Henchmen tab → right-click humanoid henchman → Manage Domain` per GDD §2 (wire on existing Henchmen tab).

**Verification:** assign two henchmen as vassals, advance one month, verify tribute flows liege-ward with the right efficiency factor, verify ruler title updates as realm grows past Marquis threshold. **`[RAW PATCH]`** `tests/test_tribute_inefficiency_raw.gd` checking the eight RAW tiers, with explicit cases at 36 vassals (50% per `[RESOLVED 2026-05-06]` 17-63 reading), 63 vassals (50%), and 64 vassals (33%) to lock in the digit-transposition correction; `tests/test_non_henchman_vassal_loyalty.gd` checking −2 base loyalty and −4 outside trade range.

---

## Phase 8 — Favors & Duties Monthly System *(was Phase 7)*

**Schema:**
- `062_vassal_favors_duties.sql` — `vassal_obligations(id, vassal_assignment_id, kind, type, magnitude, issued_calendar_day, due_calendar_day, status, loyalty_modifier, gp_value)`; `kind ∈ {favor, duty}`; types per `acore_axioms` §favors_and_duties L352-372 (Charter of Monopoly / Gift / Office / Troops / Grant of Land for favors; Construction / Scutage / Call to Council / Call to Arms / Loan for duties).

**Engine:**
- `engine/subsystems/domains/favors_duties_resolver.gd` — monthly d20 per vassal per `acore_axioms` §favors_and_duties.table L360-372: roll + loyalty modifier + active-favor count → favor / duty / revocation / no-action; safe-duty threshold (each vassal can safely be asked one ongoing duty plus one additional ongoing duty per ongoing favor and per one-time favor given that month, per L353-358; if duties exceed safe total, make a Henchman Loyalty check for each extra duty with cumulative −1 per additional duty); non-henchman vassals get base loyalty −2 (or −4 if outside trade range per L392-397) and only one duty per favor (no free duty per L395).
- Wires into existing `henchman_loyalty_resolver.gd` for cascading loyalty rolls when duty exceeds threshold or scutage payment fails.

**UI:**
- Embed in `realm.tscn` (Phase 7): per-vassal Favors/Duties card showing this month's roll + recent history; player can Approve/Veto/Modify on monthly tick.

**Verification:** stack four duties on a vassal, verify cumulative −4 loyalty modifier, verify failed loyalty roll triggers vassal departure / revolt path.

---

## Phase 9 — Domain Encounters + Bandits + Sieges *(was Phase 8)*

**Data:**
- `data/domain_events/encounter_table.json` — extract every encounter row from `ax_domain_level_encounters.xml` (dangerous-border raid, dungeon-monster incursion, harvest failure, brigand wave, plague, religious strife, political intrigue, revolt, conquest threat) with hex/classification/season filters, severity, response options, mechanical consequences.
- `data/domain_events/bandit_scaling.json` — morale-tier → bandits-per-family table per `acore_axioms` §effects_of_morale L538-609: Rebellious one able-bodied man per family; Defiant one per two families; Turbulent one per five families.
- **`[RAW PATCH]`** `data/domain_events/encounter_frequency_table.json` — full RAW frequency table from `ax_domain_level_encounters.xml` §domain_encounter_frequency_by_territory_size_and_terrain L70-120 (1 hex = 1d100 with 100+/99+/98+ targets by terrain band; 2 hex = 1d100 with 99+/97+/95+; 3 hex = 1d100 with 98+/95+/92+; 4-6 hex = 1d20 with 20+/19+/18+; 7-8 hex = 1d12 with 12+/11+/10+; 9-10 hex = 1d10 with 10+/9+/8+; etc.).

**Engine:**
- `engine/subsystems/domains/domain_encounter_resolver.gd` — **`[RAW PATCH]`** Encounter throws follow `ax_domain_level_encounters` §classification_rules L13-29: **civilized = monthly throws, borderlands = weekly throws, wilderness = daily throws** (NOT a flat probability per classification). The throw die and target value for each throw come from the territory-size × terrain table loaded from `encounter_frequency_table.json`; civilized domains use the "city/grass/scrub/settled" terrain column with the "inhabited" wilderness encounter sub-table; borderlands and wilderness use the column matching their predominant terrain. On a passing throw, roll on the wilderness encounters by terrain table per L42-120, then resolve reaction (hostile / unfriendly / neutral / mercantilist / friendly).
- `engine/subsystems/domains/bandit_spawner.gd` — domain morale ≤ −2 → spawn bandits as enemy "army" per `acore_axioms` §bandits L611-630; counts scale by morale tier from `bandit_scaling.json`; defeating restores +1 morale and reduces population by bandits killed (prisoners returned to work return as families per L617-620, but if morale still below −1 when freed, the appropriate proportion reverts to banditry next month per L620); raising morale instead of fighting removes bandits without population loss per L622-625.
- `engine/subsystems/domains/npc_challenger_emergence.gd` — cumulative monthly chance from bandits per morale tier (Rebellious 10%, Defiant 5%, Turbulent 1% per `acore_axioms` §effects_of_morale L559, L569, L577); on emergence, the challenger has experience level sufficient for personal authority +0 per L560; if the ruler refuses battle, the NPC begins pillaging, imposing −4 on morale rolls per L627-630.
- **`[SIEGE 2026-05-06]`** Siege resolution subsystem — **fully abstract, in v1 scope, no battle map required**. Two RAW-supported resolution paths, dispatched by who's involved:

  - `engine/subsystems/domains/siege_state.gd` — domain `is_besieged` flag, current siege phase (blockade / reduction / assault), besieging-army composition, defender garrison, current shp / max shp, breach count, supplies remaining, `siege_started_calendar_day`, `expected_resolution_date`. Source of truth for the Encounters & Threats sub-tab's siege card per `gdd-domain-tab.md` §13.
  - `engine/subsystems/domains/unit_capacity_calculator.gd` — single source of truth for stronghold unit_capacity. v1 implementation uses the no-map formula per `daw_sieges.xml` §siege_mechanics.unit_capacity L37-41: `unit_capacity = ceil(shp / 1000)`. Exposes a stable interface so the grid-builder swap-in for v1.1+ ("If mapped, calculate unit capacity by summing the unit capacity of all structures") is a one-method replacement, not a cross-cutting change.
  - `engine/subsystems/domains/siege_resolver.gd` — **full DaW: Campaigns siege rules** for **player-involved sieges** (PC besieger, PC defender, or PC henchman commanding either army). Implements the three-phase procedure per `daw_sieges.xml`:
    - **Blockade** (§blockade L65-193): encirclement units required = 2 per unit_capacity (minimum 20); circumvallation reduces requirement by 2 per 250'; naval blockade required if water-facing; un-blockaded prep adds 600 gp/point/week to stored supplies (cap 3,000 gp/point per L121-127); blockaded defenders lose supply line.
    - **Reduction** (§reduction L195-463): siege engines + magic + siege-mining + hijinks deal shp damage; each 1,000 shp = 1 breach (per §siege_mechanics.breaches L42-46); siege-mining excludes solid-rock or moat-girdled strongholds (L418-420); defender repair per L455-461 (wood: 5 shp per gp construction rate, stone: 1 shp per gp; cap at 50% of damage taken during siege).
    - **Assault** (§assault L465-499): the 24-step procedure resolves via attack throws and battle-rating math; max assaulting units = 1 per unit_capacity + 1 per breach; max defending units = 1 per unit_capacity; assault attack throws at −2 (artillery / siege equipment / flyers / breach-assaulters exempt); defender +2; defending infantry +1 BR for stronghold protection; assaulting cavalry not using a breach drop to BR/4. End states: defenders defeated → captured; assaulters defeated → liberated; voluntary surrender → captured; otherwise besieger may renew or call off.
  - `engine/subsystems/domains/siege_resolver_simplified.gd` — **Sieges Simplified table** per `daw_sieges.xml` §sieges_simplified L813-846+. Used for **NPC-vs-NPC sieges** that resolve off-camera in the world simulation. Procedure: cross-reference stronghold shp × `unit_advantage = besieging_units − defending_units` (with artillery/siege engines as bonus units per L823-825) on the duration table at L847+; result is days-to-capture (0 = no fight, "−" = besieger too weak to capture and limited to starvation blockade). Site duration modifiers per L827-829.
  - `engine/subsystems/domains/siege_intervention_handler.gd` — when a PC arrives at an in-progress simplified siege, **escalate to full DaW rules**. Per `daw_sieges.xml` §off_camera_and_intervention_guidance L838-844: reconstruct current stronghold shp proportionally from elapsed time (full duration elapsed → 0 shp; half elapsed → 50% shp; etc.). Recompute breaches from the reconstructed shp delta. Hand off `siege_state` to `siege_resolver.gd` for the rest.
  - `engine/subsystems/domains/siege_supply_tracker.gd` — stored supplies tracking per `daw_sieges.xml` §effects_of_blockade L116-136: default 600 gp/point of unit_capacity (≈10 weeks at full garrison); consumed at full-garrison rate during blockade; +600/point/week for un-blockaded preparation time, capped at 3,000/point.
  - `engine/subsystems/domains/siege_dispatcher.gd` — routes a new siege event to the right resolver based on participants. If any participant is a PC, a PC's henchman, or a PC's named NPC vassal commanding an army, route to `siege_resolver.gd` (full rules). Otherwise route to `siege_resolver_simplified.gd`. Promotes a simplified siege to the full resolver via `siege_intervention_handler.gd` whenever a PC subsequently joins.
  - **`[ARCH 2026-05-06]`** All siege-resolution actions launch through the `ActivityLauncher` API per `gdd-realtime-scheduler.md` §4.8.3, with siege turns scheduled as `ScheduledEvent`s on the master scheduler.

**Note on grid placement:** Per `gdd-stronghold-construction.md` §4 the project specifies a future grid-placement planner that would compute per-structure unit_capacity (more accurate than the no-map ceil(shp / 1000) formula). That planner is **deferred to v1.1+**. v1 strongholds are abstract value-only records with shp, gp_value, and derived unit_capacity. All army-level combat in v1 is abstract; mapped tactical battles per Domains at War: Battles are out of project scope.

**UI:**
- `scenes/ui/notebook/domain/sub_tabs/encounters_threats.tscn` — threat list (type / source-hex / creature / severity), garrison-mitigation budget, monthly encounter-throw summary, bandit count + repress/defeat options, occupation/pillage status, active-siege card. Action buttons: Deploy Garrison / Repress / Defend / Negotiate / Retreat. HUD toast on high-severity events with cross-activation per GDD §17.

**Verification:** drive morale to −3 via taxation spike, verify bandits spawn at correct count (one per two families per `acore_axioms` §effects_of_morale.Defiant L568), verify resolving them via garrison action restores morale by +1; **`[RAW PATCH]`** `tests/test_encounter_throw_frequency_by_territory_size.gd` verifying that a 1-hex civilized domain throws monthly with 100+ on 1d100 (i.e., effectively never absent special modifiers), while a 6-hex wilderness domain throws daily with 18+ on 1d20 in harsh terrain. **`[SIEGE 2026-05-06]`** Siege verification:

- `tests/test_unit_capacity_no_map_formula.gd` — verify `unit_capacity = ceil(shp / 1000)` per `daw_sieges.xml` L37-41 across boundary cases (1 shp → 1, 999 shp → 1, 1000 shp → 1, 1001 shp → 2, 32000 shp wilderness minimum → 32).
- `tests/test_siege_dispatcher_routing.gd` — PC-defended stronghold besieged by NPC army → routes to full `siege_resolver.gd`; NPC vs NPC siege → routes to `siege_resolver_simplified.gd`; PC arrives mid-simplified → escalates to full resolver via `siege_intervention_handler.gd`.
- `tests/test_siege_resolver_full_blockade.gd` — verify required encirclement units (2 per unit_capacity, min 20), circumvallation reduction (−2 per 250'), naval-blockade requirement when water-facing, supply consumption rate (default 600 gp/point ≈ 10 weeks at full garrison).
- `tests/test_siege_resolver_full_reduction.gd` — verify shp damage from artillery / siege-mining / magic / hijinks; breach generation at 1,000 shp intervals; defender repair (wood 5 shp/gp, stone 1 shp/gp; capped at 50% of damage taken).
- `tests/test_siege_resolver_full_assault.gd` — 24-step assault procedure end-to-end; max assaulting units = unit_capacity + breaches; max defending units = unit_capacity; assault −2 / defender +2 attack throw modifiers; defending infantry +1 BR; cavalry-not-using-breach BR/4; capture / liberation / surrender end states.
- `tests/test_siege_resolver_simplified.gd` — duration table lookup for stronghold shp × unit_advantage; "−" result when besieger too weak; site duration modifiers; NPC-vs-NPC end-to-end with deterministic outcome based on inputs.
- `tests/test_siege_intervention_proportional_state.gd` — PC arrives at day 5 of a 10-day simplified siege → reconstructed state has 50% remaining shp (per `daw_sieges.xml` §off_camera_and_intervention_guidance L838-844); breach count derived from shp delta; supplies at 50%; full-resolver picks up cleanly from this state.
- `tests/test_siege_supply_tracker.gd` — un-blockaded prep adds 600 gp/point/week to stored supplies, capped at 3,000 gp/point; consumption rate matches rated weeks at full garrison.
- Manual end-to-end: PC's L9 fighter defends a 32,000-gp wilderness stronghold (32 unit_capacity) against an NPC bandit army; verify full-rules path fires, blockade requires 64 enemy units (or 20 minimum), reduction over multiple weeks creates breaches, assault resolves with the 24-step procedure, and the Encounters & Threats sub-tab surfaces the active siege card with phase / breaches / supplies / expected resolution.

---

## Phase 10 — Class-Specific Sub-Tab (Faith / Magical Research / Trade / Syndicate / Garrison Training) *(was Phase 9)*

Five blocks, stacked for multi-bucket classes (e.g., Bladedancer = Faith + Garrison Training; **`[RESOLVED 2026-05-06]`** Lightblessed Wonderworker = Magical Research + Faith stacked, per the O-D5 resolution: the class plays as a Mage at root for domain purposes, with the Faith block layered on for its cleric-list divine casting and split follower set; not a separate hybrid bucket).

**Engine (one handler module per block):**
- `engine/subsystems/activities/handlers/faith/` — `dispatch_missionaries.gd`, `cast_charitable_spells.gd`, `consecrate_altar.gd`, `extract_divine_power.gd`, `perform_blood_sacrifice.gd` (Chaotic), `perform_ceremonial_sacrifice.gd` (Lawful). All activity names per `ax_campaign_play.xml` §faith_activities. Congregant growth: **`[RAW PATCH]`** `1d10 + Charisma bonus congregants per 1,000 gp spent proselytizing during the prior month`, per `ax_campaign_play` §congregant_growth L20-22, written to a new `congregants(domain_id, count, monthly_growth)` table (migration 063); congregant upkeep is 1gp per congregant per month, and if unpaid, 1d10 congregants depart per 1,000 gp left unpaid per `ax_campaign_play` §end_of_month.congregants L109-112. Divine power: **`[RAW PATCH]`** `extract_divine_power.gd` extracts **10 gp of divine power per 50 congregants weekly** (i.e., congregants ÷ 5 per extraction, requiring the activity to be taken each week per campaign play rules), plus 0-8 divine power per 10 families if the caster is the ruler or spiritual advisor, per `ax_campaign_play` §extract_divine_power L460-472.
- `engine/subsystems/activities/handlers/magical/` — `research_magic.gd`, `rewrite_spell.gd`, `replace_spell.gd`, `scribe_spell.gd`, `manage_assistant.gd`. Uses `acore-campaign-general-and-magic-research.xml` rules.
- `engine/subsystems/activities/handlers/mercantile/` — `buy_sell_merchandise.gd`, `commission_equipment.gd`, `commission_magic_items.gd`, `solicit_merchants.gd`, `enter_market.gd`, `persuade_*`, etc. Many cross-activate Settlement Panel. **`[RAW PATCH]`** Venturer monopoly handler (level 12+ ability per `ax_venturer_class.xml` §monopoly_power L203-211): `1 gp per month per urban family in the urban settlement`, in addition to domain revenue if the venturer is also the domain ruler; only one venturer per urban family.
- `engine/subsystems/activities/handlers/syndicate/` — `order_hijink.gd`, `plan_hijink.gd`, `perform_hijink.gd`, `lay_low.gd`, `await_trial.gd`, `bribe_magistrate.gd`, `hire_attorney.gd`, `interplead.gd`. **`[RAW PATCH]`** Hijink revenue is per-hijink-type from the per-hijink resolution tables in `acore-campaign-hijinks.xml` (assassinating / carousing / smuggling / spying / stealing / treasure_hunting), NOT a flat formula by urban family. Each syndicate member, eligible henchman, or ruffian on payroll may be assigned one hijink per month per §hijinks L48-58. Syndicate size is capped by urban-settlement market class per §syndicate_size_rules L24-28. Revenue → ledger `hijink_revenue` category.
- `engine/subsystems/activities/handlers/training/` — `train_troops.gd`, `oversee_troop_training.gd`, `inspect_troops.gd` (these may be implemented earlier in Phase 3 if needed for Garrison sub-tab; here they get full Class-Specific UI surfaces).

**Data:**
- `data/activities/divine_category.json`, `data/activities/magical_category.json`, `data/activities/mercantile_category.json`, `data/activities/syndicate_category.json` — full RAW per `ax_campaign_play.xml`.
- `data/strongholds/lightblessed_wonderworker_aspirant_table.json` — **`[RESOLVED 2026-05-06]`** Lightblessed Wonderworker follower rules per `pc_classes_5.xml` §stronghold_sanctum L127-134 ("Attracts 1d6 mages or clerics of 1st-3rd level plus 2d6 normal men seeking to become mages or clerics"). Project interpretation of the OR-clause: roll 1d6 for total 1st-3rd-level apprentices, then split that count between mages and clerics (default 50/50, rounded toward mage given the mage-rooted progression; the player may rebalance the split at sanctum founding to reflect their leanings). The 2d6 normal men similarly split between mage-aspirants and cleric-aspirants. Apprentices need food and lodging but no wages per L132.

**UI:**
- `scenes/ui/notebook/domain/sub_tabs/class_specific.tscn` — class-bucket dispatcher per §12.1 matrix. Each block in its own `.tscn`:
  - `blocks/faith_block.tscn` — Cleric/Bladedancer/Priestess/Shaman/Druid/**`[RESOLVED 2026-05-06]`** Lightblessed Wonderworker (secondary stack — uses cleric divine-spell list per `pc_classes_5.xml` §divine_casting L87-93); congregant counter, divine-power tracker (showing congregants ÷ 5 per weekly extraction), altar consecration timer, sacrifice flow.
  - `blocks/magical_research_block.tscn` — Mage/Elf Mage/Dwarven Delver/**`[RESOLVED 2026-05-06]`** Lightblessed Wonderworker (primary stack — mage progression per `pc_classes_5.xml` L46, spell research from L5 per §spell_research L121-123, magic-item creation from L9 per §magic_item_creation L124-126; research-project list MUST allow project targets on either the arcane spell list OR the cleric divine spell list, since the class can research and scribe in both schools; at level 11+ the dual-list access extends to ritual spells per §ritual_magic_and_advanced_creation L135-137); research-project list with progress, repertoire/spellbook integration, assistant slots.
  - `blocks/trade_block.tscn` — Venturer; merchant network, monopoly charters (level-12+ income line at 1gp/urban-family), caravan/ship roster (cross-link Settlement Panel).
  - `blocks/syndicate_block.tscn` — Thief/Assassin/Nightblade; hijink queue (one per syndicate member per month), lay-low timer, crime-and-punishment dashboard, hijink revenue accumulator.
  - `blocks/garrison_training_block.tscn` — Fighter/Barbarian/Ranger/Paladin/Bladedancer/**`[RESOLVED 2026-05-06]` Bard** (RAW core class per `acore_campaign_classes.xml` L369 — combat progression family is thief per L403-409, but bards are NOT eligible for hijinks per `acore-campaign-hijinks.xml` §hijinks-eligibility list which restricts hijinks to assassins, elven nightblades, and thieves; assigned to Garrison Training on the basis of `chronicles_of_battle` L569-573 which grants +1 morale to hired henchmen and mercenaries when the bard is present, plus `solicit_followers` L576-583 which recruits 1d4+1×10 0th-level mercenaries plus 1d6 1st-3rd-level bards into the ruler's service)/Dwarf Fighter/Elf Fighter; training projects, veteran promotion, inspection.
- Stacked-block rendering: collapsible cards within single sub-tab for Bladedancer (Faith + Training), **`[RESOLVED 2026-05-06]`** Lightblessed Wonderworker (Magical Research + Faith stacked, with the Magical Research block as the primary/expanded card and the Faith block secondary/collapsed by default given the mage-rooted progression).

**Verification:** for each class-bucket, smoke-test one canonical activity end-to-end (e.g., Cleric `consecrate_altar` → divine power expended → magic research throw → +1 morale on success). **`[RAW PATCH]`** `tests/test_congregant_growth_raw.gd` verifying 1d10+CHA per 1,000gp proselytized; `tests/test_divine_power_extraction_raw.gd` verifying 10gp per 50 congregants per weekly extraction.

---

## Phase 11 — Departure Log + Lifecycle Polish + Chaotic Branch + End-to-End Tests *(was Phase 10)*

**Schema:**
- `064_departure_log.sql` — `domain_departure_log(id, domain_id, calendar_day, event_type, summary, full_details_json)` for permanent loss record.

**Engine:**
- `engine/subsystems/domains/lifecycle_handler.gd` — establishment / classification advancement / classification regression / conquest / abandonment / ruler death / succession. **`[RESOLVED 2026-05-06]`** Succession grace period (formerly O-D6) confirmed at **1 game-month**: when a ruler dies, the domain enters a succession-pending state for 1 game-month; if no successor is appointed before the grace period lapses, default abandonment / regression rules trigger. Successor candidates: PC, henchman, or NPC-generator-populated non-henchman (the latter inherits at base loyalty −2 per `acore_axioms` §non_henchman_vassals L392-397).
- `engine/subsystems/domains/chaotic_domain_branch.gd` — **`[RAW PATCH]`** chaotic-domain modifiers per `ax_domains_of_chaos` §exceptions_from_clanholds L76-87: beastman followers and families per §followers L69-74; tribal warrior levy per `ax_domains_of_chaos` §military L37-40 (up to 1 tribal warrior per family); investment value halved per L82; +2gp garrison cost per L86; **chaotic urban revenue is capped at 7gp per family regardless of settlement population per L85** (the prior version's claim that chaotic urban could not reach class V was incorrect — chaotic urban CAN reach market class V at 50,000 gp investment per L84, but per-family revenue does not scale upward as it does in normal urban settlements); each 1d10 new families costs 2,000 gp per L83 (vs. 1,000 gp in normal domains); class V costs 50,000 gp per L84; once population exceeds 125 peasant families per 6-mile hex, excess peasant families provide only half normal land revenue per L79; urban settlements are not limited to 250 families or 12.5% of peasant population per L80; additional restrictions on conscription, militia, council, loans, monopoly, and grants of title per `ax_domains_of_chaos` §vassalage_limits L47-53. Foundational hooks were laid in Phase 0's schema (`is_chaotic_domain`); this phase wires the branch logic into every resolver.

**UI:**
- `scenes/ui/notebook/domain/sub_tabs/departure_log.tscn` — virtualized chronological list, per-entry Inspect modal with full details + ledger / encounter cross-references; export markdown/JSON/TXT.
- Empty-state class-tailored guidance polish per GDD §19.

**End-to-end test scenarios (`tests/scenarios/`):**
- `domain_full_loop_fighter_borderlands.gd` — L9 fighter clears wilderness hexes, builds keep, attracts followers (with ceil-rounded wave schedule), runs 12 monthly cycles with bandit incursion, advances to Borderlands, all numbers RAW-correct.
- `domain_realm_with_vassals.gd` — L11 ruler with 3 humanoid-henchman vassals, monthly tribute with **`[RAW PATCH]` 100% efficiency at 3 vassals per `acore_axioms` §tribute_inefficiency**, favors/duties cycle, one vassal failed loyalty → revolt.
- `domain_chaotic_clanhold.gd` — chaotic-aligned PC annexes beastman clanhold, runs monthly with chaotic-domain modifiers; **`[RAW PATCH]`** verifies urban revenue stays at 7gp/family even after settlement reaches class V via 50,000gp investment.
- `domain_pre_9_path.gd` — L7 PC purchases existing stronghold, hires mercenaries, invests gp, no follower auto-attraction per `acore_axioms` §before_ninth_level L117-123; verifies investment-to-attract-peasants and mercenary-hiring still work pre-9 per L121.
- `domain_succession.gd` — ruling PC dies, grace-period countdown, henchman succession appointed before lapse.
- **`[RAW PATCH]`** `domain_below_sufficiency.gd` — wilderness domain with stronghold_value < 32,000gp/hex: revenue and growth zeroed, garrison still must be paid, sufficiency reached mid-year via construction completion, revenue and growth resume on next monthly tick.
- **`[RAW PATCH]`** `domain_repression_morale_cap.gd` — domain at Defiant (−3) morale, ruler assigns 4gp/family of mercenary repression: morale roll bonus +4 verified, but current morale capped at 0 while repression is active.
- **`[RAW PATCH]`** `domain_land_improvement.gd` — borderlands domain spends 75,000gp over three months to improve one hex from 5gp land value to 8gp; verifies +3 cap; verifies fourth attempt is rejected.

---

## Critical Files Inventory

**To modify:**
- `db/schema.sql` (after each migration)
- `db/migrations/050_*.sql` through `064_*.sql` (new)
- `engine/subsystems/session/handlers/domain_handlers.gd` (rewrite Phase 0)
- `engine/autoloads/event_bus.gd` (signals across phases)
- `engine/autoloads/campaign_repository.gd` (CRUD additions)
- `scenes/ui/notebook/tab_pages/domain_tab_page.gd` (Phase 2 rewrite)
- `scenes/ui/notebook/tab_pages/troops_tab_page.gd` (Phase 5 rewrite)
- `docs/document_map.md`, `docs/rule_system_map.md`, `docs/coding_conventions.md` (each phase)
- `build_log.md` (every session)

**To create (new directories):**
- `engine/subsystems/domains/` — Phase 0, 2, 6, 7, 8, 10
- `engine/subsystems/strongholds/` — Phase 1
- `engine/subsystems/activities/` + `engine/subsystems/activities/handlers/{faith,magical,mercantile,syndicate,training}/` — Phases 3, 9
- `engine/subsystems/troops/` — Phase 5
- `scenes/ui/notebook/domain/{status_header,sub_tabs,activity_card,establish_domain_dialog}/` — Phase 2+
- `scenes/ui/strongholds/` — Phase 1
- `data/{strongholds,activities,domain_events,followers,troops}/` — Phases 1, 3, 5, 8, 9
- `tests/test_domain_*.gd`, `tests/scenarios/` — every phase

**Reused (existing, do not duplicate):**
- `engine/autoloads/timekeeping.gd` — `month_changed`, `day_changed`, `advance_*`
- `engine/subsystems/session/scheduler/event_scheduler.gd` — monthly tick scheduling
- `engine/subsystems/henchmen/henchman_loyalty_resolver.gd` — vassal loyalty cascade in Phase 7, 8
- `engine/subsystems/henchmen/henchman_lifecycle_manager.gd` — vassal succession path in Phase 11
- `engine/subsystems/combat/morale_resolver.gd` — combat-side morale already implemented
- `engine/subsystems/reputation/*` — `reputation_entries.scope_type='domain'` already defined; cascade math from `build_log.md` line 4430+
- Existing `data/henchmen/equipment_kits.json` — follower equipment in Phase 5

---

## End-to-End Verification Strategy

Per phase, run focused tests + integration test. Per major milestone (after Phase 2, Phase 5, Phase 6B, Phase 8, Phase 11), run a full scenario suite:

1. After Phase 2: launch game, establish a domain by grant, advance a month, read full Overview + Treasury data, ledger entries match hand-computed numbers; **`[RAW PATCH]`** verify income-gate banner displays when stronghold below sufficiency.
2. After Phase 5: complete fighter castle commission at L9, follower waves arrive on schedule using the RAW-correct ceil-rounded math, garrison expenditure meter live with both reference lines visible, recruitment activities resolve.
3. After Phase 6B: hire mercenary units, form an army with officers, march to a target hex, encounter and defeat an NPC bandit horde via the field-battle resolver; verify RAW-correct phase transitions, casualties, and pursuit.
4. After Phase 8: assign vassals, run 3 monthly cycles, verify tribute + favors/duties + loyalty rolls + cascades work end-to-end with RAW-correct efficiency tiers.
5. After Phase 11: run all `tests/scenarios/` end-to-end scenarios headlessly; visual smoke-test all nine sub-tabs across PC + humanoid-henchman entity types and across all classes in the §12.1 matrix.

**Headless test command** (from `CLAUDE.md`):
```
/c/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path . --import   # once after new .gd files
/c/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn
```

**Manual verification:** GUI build for visual sub-tab smoke-test:
```
/c/godot/Godot_v4.6.1-stable_win64.exe --path .
```

**Data integrity:** every monthly tick writes a complete set of ledger entries; reading the Treasury sub-tab back should reconstruct the month's net income from the ledger alone (no derived-state drift). The Departure Log is append-only; nothing in the codebase should DELETE from it.

---

## Estimated Effort & Sequencing Notes

- Phases 0 + 1 are the heaviest engine work and should not be parallelized (Phase 1's morale-feedback hook depends on Phase 0's resolver shapes).
- Phases 2 + 3 can overlap once Phase 0 schema is settled; Phase 2 builds the shell, Phase 3 lands the activity time-cost executor + the Decrees & Remote Orders sub-tab + per-location launch contracts + the Active Projects sub-tab on the Character tab.
- Phase 5 (Troops tab + Garrison) can start as soon as Phase 4 closes the stronghold-followers-attraction prerequisite.
- **`[ARMY 2026-05-06]`** Phases 6A and 6B are sequential — Phase 6B's field-battle resolver consumes Phase 6A's army composition, marching, and supply state. Both depend on Phase 5 troop_units. Drafting `gdd-army-warfare.md` is a prerequisite for the Phase 6A build (scaffold lives in the GDD; flesh out in a dedicated drafting session).
- Phases 7 + 8 are tightly coupled (Realm before Favors/Duties) and best done back-to-back. Phase 8's Call to Arms duty produces an army via the Phase 6 layer.
- Phase 9 (Encounters / Bandits / Sieges) is unblocked once Phase 6B lands. Bandits resolve as small armies via the field-battle resolver; sieges resolve via the dual-path siege resolvers, with the assault step calling into the field-battle resolver. UI slot-in waits for Phase 2 shell.
- Phase 10 is a long tail — five class blocks × multiple activities each. Consider shipping faith + training first (covers most classes) and mercantile + syndicate + magical-research second.
- Phase 11 is end-to-end polish; do not start until Phases 0–10 functional acceptance passes.

If the roadmap needs to be cut, a defensible v1-shippable subset is **Phases 0, 1, 2, 3, 4, 5, 6A, 6B, 9, 11** (defer Realm/Vassalage/Favors/Class-Specific to v1.1). But per user direction, the target is the full ruler-with-vassals loop, so all twelve phases are in scope.

---

## Appendix A — Summary of RAW Patches Applied

| # | Location | Original | Corrected | RAW source |
|---|---|---|---|---|
| 1 | Phase 0 growth resolver | "2d10 exploding per 1000 families" | "Two independent 1d10s per 1,000 families (rounded up): one increase, one decrease, both exploding on 10s; net = increase − decrease" | `acore_axioms` §domain_growth.monthly_change L126-131; `ax_campaign_play` §random_growth L15-17 |
| 2 | Phase 7 tribute calculator *(was Phase 6)* | "37–80: 33%, 81–176: 16%, 177–384: 8%, 385–832: 4%, 833+: 1%" | "64-216: 33%, 217-1024: 20%, 1025-4095: 10%, 4096-16384: 5%, 16384+: 1%" | `acore_axioms` §tribute_inefficiency L398-409 |
| 3 | Phase 9 encounter resolver *(was Phase 8)* | "civilized 1-in-12, borderlands 1-in-8, wilderness 1-in-6 per `acore_axioms` §encounters" | "Civilized = monthly throws, borderlands = weekly throws, wilderness = daily throws; throw die scales by territory size and terrain per the RAW frequency table" | `ax_domain_level_encounters` §classification_rules L13-29; §domain_encounter_frequency_by_territory_size_and_terrain L70-120 |
| 4 | Phase 11 chaotic branch *(was Phase 10)* | "no class-V-via-investment" | "Chaotic urban CAN reach market class V at 50,000 gp investment, but per-family urban revenue stays capped at 7 gp regardless" | `ax_domains_of_chaos` §exceptions_from_clanholds L84-85 |
| 5 | Phase 0 expense calculator + Phase 5 garrison | "garrison min (2gp/fam civilized, 3gp borderlands, 4gp wilderness)" presented as a hard floor | "2 gp/family universal minimum; the 3 gp (borderlands) and 4 gp (wilderness) values are morale incentives via the additional-troops table, not hard expense floors. Wilderness specifically must reach 4 gp or take a base morale reduction." | `acore_axioms` §garrison L218, L226-234; §additional_troops L461-464 |
| A1 | Phase 0 morale resolver | omitted | Insufficient-stronghold tiered morale: −1 if ≥½ minimum, −2 if ≥¼, −3 if <¼ | `acore_axioms` §insufficient_stronghold L452-456 |
| A2 | Phase 0 + Phase 2 + Phase 11 | omitted | Land improvement: 25,000 gp per +1 land value, capped +3 / max 9; lost 1gp value per gp pillaged; treated as wooden in siege | `acore_axioms` §land_improvement L207-215 |
| A3 | Phase 0 morale + Phase 3 activities + Phase 5 garrison | omitted | Repression engine: militia ineligible; +1 morale roll per gp/family additional repressing troops; current morale capped at 0 while repressed | `acore_axioms` §repression L488-491, L510-516 |
| A4 | Phase 0 revenue calculator + Phase 4 sufficiency | omitted | Income-and-growth gate: domain generates no revenue and does not grow until stronghold value meets classification minimum | `acore_axioms` §peasants_and_followers L108-109 |
| A5 | Phase 5 followers arrival | "50%/25%/25%" simplified | "ceil(N×0.5) at half-built, ceil(N×0.25) at completion, remainder at +1 month" | `acore_axioms` §followers_arrival L111-116 |
| A6 | Phase 7 vassals *(was Phase 6)* | omitted | Non-henchman vassal base loyalty −2, or −4 if outside trade range; only one duty per favor (no free duty) | `acore_axioms` §non_henchman_vassals L392-397 |
| A7 | Phase 10 faith handlers *(was Phase 9)* | "2d6 × 10 congregants per month" / "congregants / 10 divine power" (from earlier plans) | Congregant growth: 1d10 + CHA per 1,000gp proselytized; 1gp/congregant upkeep; 1d10/1,000gp unpaid depart. Divine power: 10gp per 50 congregants per weekly extraction (= congregants/5) | `ax_campaign_play` §congregant_growth L20-22, §end_of_month.congregants L109-112, §extract_divine_power L460-472 |
| A8 | Phase 9 syndicate handlers | (no specific formula in original Plan D — corrected by exclusion) | Confirmation that hijink revenue is per-hijink-type from RAW resolution tables, NOT a flat per-urban-family d6; one hijink per syndicate member per month; size capped by market class | `acore-campaign-hijinks.xml` §hijinks L48-58, §syndicate_size_rules L24-28 |
| A9 | Phase 9 mercantile | omitted | Venturer monopoly (level 12+): 1gp/month per urban family in the urban settlement, in addition to domain revenue if ruler | `ax_venturer_class.xml` §monopoly_power L203-211 |

## Appendix B — Items Flagged for Jedidiah's Clarification

These are points where the RAW is either ambiguous or where Plan D made an internal design decision (`O-D*`) that should be confirmed before implementation.

### Resolved (2026-05-06)

- **`[RESOLVED]` Tribute inefficiency table gap (37-63 direct vassals):** Source XML at `acore_axioms_strongholds_and_domains.xml` L405 reads "17-36 = 50%", leaving an algebraic gap from 37-63. Per logarithmic-scale and lower-bound-continuity analysis (the upper-bound progression elsewhere is roughly ×4, and the next tier's lower bound at 64 implies the previous tier's upper bound is 63, not 36), this is treated as a digit-transposition typo (3 ↔ 6) and the band is read as **17-63 = 50%**. Implementation encodes the corrected reading in engine constants; the source XML is preserved unchanged per the sacred-rules constraint. The code comment at the constant declaration MUST cite both the source line and this resolution.

- **`[RESOLVED]` Active-adventuring detector (formerly O-D1):** Defined for the project as: ruler left the stronghold during the prior game month AND any of (a) wilderness encounter resolved, (b) lair entered, (c) hex cleared, (d) dungeon entered, (e) battle resolved, (f) siege participated in (attacker or defender), or (g) returned to any friendly settlement with 1,000 gp or more in new treasure/loot since departure. Implementation per Phase 2 `active_adventuring_detector.gd`. The 1,000 gp threshold counts only new acquired treasure physically returned to a settlement, not passive income.

- **`[RESOLVED]` Treasury manual transfer (formerly O-D2):** Implied by RAW (money does not teleport in ACKS). Domain treasury gp is freely usable for domain-level activities (investments, commissioning structures, paying garrison/liturgies/maintenance/tithes, executing tribute) regardless of ruler location; personal purchases require the gp to first be moved into `characters.coin`, which only happens when the PC is physically at one of the domain's strongholds; inter-settlement transfers require physical transport (a travel-with-treasure event). Implementation per Phase 2 `treasury.gd`.

- **`[RESOLVED]` Bard activity bucket (formerly O-D3):** Bards are a RAW core campaign class per `acore_campaign_classes.xml` L369-393 (the prior plan's "Arbiter-specific" tag was incorrect). Combat progression is thief family (L403-409). However, per `acore-campaign-hijinks.xml` §hijinks-eligibility, hijink assignment is restricted to assassins, elven nightblades, and thieves — bards are NOT hijink-eligible. Bards are therefore assigned to the **Garrison Training** bucket on the basis of `chronicles_of_battle` L569-573 (+1 morale to hired henchmen and mercenaries when the bard is present) and `solicit_followers` L576-583 (recruits 1d4+1×10 0th-level mercenaries plus 1d6 1st-3rd-level bards). Implementation per Phase 9 `blocks/garrison_training_block.tscn`.

- **`[RESOLVED]` Succession grace period (formerly O-D6):** Confirmed at **1 game-month**. On ruler death, the domain enters succession-pending state for 1 game-month; if no successor is appointed before the grace period lapses, default abandonment / regression rules apply. Implementation per Phase 10 `lifecycle_handler.gd`.

- **`[RESOLVED]` Stronghold conforming/non-conforming (formerly O-D10):** RAW correction per Jedidiah — the prior plan's "non-conforming structures attract no followers" gate was an error. Per `acore_axioms` §minimum_stronghold_value L88-94 and §followers_arrival L111-116, follower attraction and all other domain mechanics are gated by stronghold gp-value sufficiency only, not by archetype match. The `is_conforming_to_class` flag is preserved as a UI display indicator (so the player can see e.g. "fighter ruling from a converted mage tower") but has NO mechanical effect. Implementation gates removed in Phase 4 stronghold sub-tab and Phase 5 `follower_arrival_resolver.gd`.

- **`[RESOLVED]` Tick-tolerance heuristic (formerly O-D15):** Confirmed. Each ongoing activity tracks `ticks_accumulated` and `absence_accumulated`; activity is forfeit when `absence_accumulated > ticks_accumulated` at any daily boundary. This is an internal-design proxy for RAW's narrative "must be performed throughout the listed time period" (`ax_campaign_play` §frequency_types.ongoing L159-163), not a direct rule formula. Implementation per Phase 3 `activity_executor.gd`.

- **`[RESOLVED]` Lightblessed Wonderworker (formerly O-D5, "Nobiran Wonderworker"):** Class is renamed to **Lightblessed Wonderworker** in Arbiter for IP reasons; mechanics are unchanged from `pc_classes_5.xml` L2-153. For domain play the class is, at root, a Mage: mage progression family (L46), arcane repertoire casting (§arcane_casting L79-86), magic-item creation at L9 (§magic_item_creation L124-126). Three additions: (i) **stronghold sanctum at L9** attracts a split mage-and-cleric apprentice set per §stronghold_sanctum L127-134 (1d6 1st-3rd-level apprentices distributed between mages and clerics, plus 2d6 normal men aspiring to become mages or clerics; the player may rebalance the split at sanctum founding); (ii) **magical research access to both spell lists** — the class may research, scribe, and brew on the arcane list AND the cleric divine list per §arcane_casting and §divine_casting (L79-93) plus §spell_research L121-123; (iii) **dual-list ritual spell access at L11+** per §ritual_magic_and_advanced_creation L135-137. Implementation: NOT a separate hybrid bucket. The Magical Research bucket is the primary class-specific block; the Faith block is layered as a secondary stacked card (collapsed by default) for the divine-list access, congregant tracking, and divine-power extraction. Research-project list in the Magical Research block must accept targets on either spell list. Per Phase 9 `blocks/magical_research_block.tscn` and `blocks/faith_block.tscn`, plus `data/strongholds/lightblessed_wonderworker_aspirant_table.json`.

### Open

(none — all O-D items resolved as of 2026-05-06)
