# Domain Creation, Grant, Conquest & Ownership-Transfer — Deep Audit

**Date:** 2026-07-28
**Scope:** RAW fidelity of domain creation; the avenues by which NPCs grant domains and players acquire them by conquest or establishment; the UI/UX surfaces that expose (or wrongly expose) those avenues; and whether domain ownership actually transfers correctly.
**Method:** Six parallel dimension audits (RAW fidelity · NPC grant avenues · conquest · ownership transfer · UI/UX · wiring/dead-code/tests), each re-checked by an adversarial verifier instructed to refute, then an end-to-end flow tracer and a completeness critic. 91 findings survived refutation (1 critical, 31 high, 39 medium, 20 low). Every claim below was read out of the current working tree on branch `dungeon-refactor`; RAW is quoted from `rules/acore_axioms_strongholds_and_domains.xml`.

---

## Headline

**The mechanical substrate is good; the acquisition layer is a façade.**

The domain *economy* — revenue, expenses, morale, growth, tribute formulas, stronghold sufficiency (including a genuine noncontiguous minimum-spanning-tree solver), succession, siege resolution — is real, RAW-cited, and well-tested. That is not where the problems are.

The problems are in **how a domain comes to be yours, and what happens when it changes hands.** Three of the four RAW acquisition stories cannot be told in the shipped build:

| RAW acquisition story | Status |
|---|---|
| Clear a wilderness hex, build a keep, become a Baron | **Partial** — the domain exists but has no hexes, no peasants, and no location |
| An NPC lord grants you land in exchange for fealty | **Impossible** — no NPC can offer, no player can accept |
| Besiege an NPC baron and take his barony | **Partial** — the pipeline runs, but the prize goes to a phantom NPC, not to you |
| Assign your surplus domains to henchman vassals | **Impossible** — no code anywhere transfers an owned domain to another character |

And the one avenue that *is* fully reachable — the Domain tab's **Establish a Domain** dialog — is the wrong avenue: it lets the player pick "Land grant from a local ruler," "Purchase civilized land at 50gp/acre," or "Conquest" from a dropdown and mint a domain instantly, with no lord, no gold, and no battle.

---

## 1. Is it RAW faithful?

### Faithful (verified correct)

- **Minimum stronghold value table** — `stronghold_repository.gd:32-36` holds 15,000 / 22,500 / 32,000 gp per 6-mile hex, exact. Multiple strongholds correctly SUM. In-progress commissions correctly excluded.
- **Noncontiguous securing rule** — genuinely implemented, not stubbed: `stronghold_repository.gd:123-176` BFS-partitions owned hexes into components and runs a greedy MST over the gaps so the minimum scales with intervening hexes. This is a faithful reading of a rule most implementations skip.
- **The income gate** — `domain_revenue_calculator.gd:57-65` returns zero land, services, taxes *and* tribute when stronghold value is below minimum, exactly as RAW requires.
- **Family caps** (125 / 250 / 780 per 6-mile hex) and the **48/72-mile classification-advancement distances** are exact, and advancement/regression is recomputed monthly against real map geometry.
- **Class and alignment gating on establishment** — Explorer-no-civilized, dwarven/elven wilderness-or-own-race, chaotic-only clanhold methods, and the thief→syndicate / venturer→guildhouse hard blocks are all enforced in both `available_paths` and `validate_establishment`, and well tested.
- **The L9 follower gate** — `follower_arrival_resolver.gd:124-125` blocks followers below 9th level and splits arrival waves ceil(N×0.5) / ceil(N×0.25) / remainder, correct.
- **Titles** — `realm_title_resolver.gd:85-100` correctly implements "highest band whose three thresholds are ALL met," Emperor→Baron.
- **Non-henchman vassal loyalty** — the RAW −2 / −4 trade-range rule is computed and stored.
- **Chieftain vassalage limits** (`ax_domains_of_chaos.xml:51`) correctly block council/loan/monopoly/grant-of-land for clanhold lieges.

### Not faithful (ranked by play impact)

| # | Defect | RAW violated | Where |
|---|---|---|---|
| R1 | **Stronghold value is multiplied by 100 twice**, so every domain holding any stronghold reads as sufficient — the income gate opens and the −1/−2/−3 morale penalty never applies. `get_stronghold_value_for_domain` returns `SUM(cp_value)` (already copper); `domain_handlers.gd:332` multiplies by 100 again under a comment that wrongly says "Strongholds remain gp-denominated." A 5,000 gp tower satisfies a 128,000 gp wilderness minimum. | §minimum_stronghold_value; §peasants_and_followers income gate | `domain_handlers.gd:332` |
| R2 | **Starting peasant population is never rolled.** 8d6×10 / 3d6×10 / (1d4+1)×10 per hex exists nowhere in the codebase. Every player domain starts and stays at 0 families. | §peasants_and_followers starting_population | `establish_domain_flow.gd:317` |
| R3 | **A player-established domain has no hexes and no map location.** `add_domain_hex` has *zero* production callers. Land revenue — the largest RAW revenue line — is structurally unreachable, and classification can never advance (`hex_count > 0` guard fails forever). | §domain_acquisition sizes; §domain_revenue land | `establish_domain_dialog.gd:186` |
| R4 | **No gold is ever charged.** 50gp/acre is a dropdown label; stronghold commissions are never debited either. A 1st-level, penniless PC can found a civilized domain that RAW prices at 1,024,000 gp. | §acquisition_methods civilized purchase | `establish_domain_flow.gd:317` |
| R5 | **The before-9th-level rule is absent from establishment.** No level is read at all. RAW: a sub-9th character acquiring a *new* domain begins with **no families**; acquiring an *existing* one keeps them. The existing-domain half is satisfied by accident (conquest is a pure owner-column update); the new-domain half is unreachable because no families are ever rolled in the first place (R2). | §before_ninth_level | `establish_domain_flow.gd:194` |
| R6 | **Classification and "own-race area" are player assertions, not map facts.** The dialog offers a Classification dropdown and a default-ticked "Hex is in own-race area" checkbox. A Dwarven Vaultguard can declare any hex dwarven; a player in trackless wilderness can declare it Civilized. *Mitigating:* because the dialog passes no location, a bogus "Civilized" pick regresses to Borderlands on the first monthly tick and Wilderness on the second — but the caps, minimums and morale are wrong for one to two months, and generated NPC domains derive classification correctly. | §domain_acquisition classification | `establish_domain_dialog.gd:37, 95` |
| R7 | **METHOD_CLEAR verifies nothing.** No check that lairs or wandering monsters were cleared, though `HexLairState.is_stronghold_buildable` exists and is used elsewhere. | §acquisition_methods borderlands_or_wilderness | `establish_domain_flow.gd:399` |
| R8 | **`domains_ruled` counts only directly-owned domains**, but RAW's title table counts domains in the whole realm. A ruler with 1 personal domain and 25 vassal domains scores `domains_ruled = 1` and is pinned at Baron forever. | §titles_of_nobility | `realm_aggregator.gd:63` |
| R9 | **"Changing a vassal's tribute ALWAYS triggers a Henchman Loyalty roll" fires zero times per campaign.** Tribute is silently recomputed and rewritten every month as the vassal's realm grows; no roll ever happens. `vassal_loyalty_triggers.gd`'s own header delegates this to `TributeCalculator`'s "change path," which does not exist. There is also no player-facing tribute-setting control at all. | §tribute | `vassal_loyalty_triggers.gd`, `tribute_calculator.gd` |
| R10 | **The one-personal-domain invariant is enforced nowhere** and is *unsatisfiable* — see §4. | §realms_and_vassals core_rules | project-wide |
| R11 | **Growth gate leaks.** The pre-sufficiency gate stops random and morale growth but still lets active-adventuring and investment growth through, contradicting "the domain does NOT grow." | §peasants_and_followers | `domain_growth_resolver.gd:93` |
| R12 | **Land value is a deterministic terrain table, not 3d3**, and Land Surveying is wired to lair counts rather than land value (no natural-1 false-value path). | §land_value | `climate_generator.gd:216` |
| R13 | **Domain XP is never awarded.** `domain_xp_this_month` is written monthly and read by nothing; `XPAwardCalculator.calculate_domain_xp` has no production caller. RAW: "Domain income determines campaign XP." The entire name-level reward loop is absent, which also means acquiring a domain by *any* route confers zero character progression. | §domain_income | `domain_handlers.gd:671` |

Two further RAW-adjacent judgment calls worth Jedidiah's attention rather than a fix:

- **`conquest` is offered as an establishment method for all three classifications, and `grant` for borderlands and wilderness.** RAW's `<acquisition_methods>` lists *grant/purchase* for civilized and *clearing* for borderlands/wilderness only; conquest is covered by the DaW siege rules, not this section. The project's own `gdd-domain-tab.md` §16.1 also omits borderlands/wilderness grant. This is defensible as a project extension into RAW silence, but it is currently undocumented drift.
- **Domain alignment is a free Overview dropdown** (`overview_sub_tab.gd:334`), bypassing RAW's "a domain's apparent alignment is determined by religious practice" and the project's own religion-conversion arc.

---

## 2. Are the NPC-grant and player-acquisition avenues properly built?

### NPC → Player: **no working avenue exists.**

RAW gives two: the civilized-domain **land grant from a local ruler in exchange for fealty**, and **Favors & Duties result 20, Grant of Land**. Neither functions.

- **Favors & Duties roll 20 is inert.** `favors_duties_resolver.gd:81` classifies the d20 correctly and is unit-tested; `_size_obligation` (:455) returns `{magnitude: 0, gp_value: 0}`; `_apply_mechanical_effect` (:465-488) has cases only for `gift` and `loan`; the summary string literally reads *"Grant of Land: vassal receives a new domain (manual setup)."* No domain row, no hex, no realm change. RAW says **"generate the new domain normally."**
- **A PC can never become an NPC's vassal.** `PlayerVassalService.swear_fealty` (`player_vassal_service.gd:24`) is correct code with **no production caller** — one test, nothing else. Upstream, `RulerActionCatalog` contains no action by which an NPC could offer land or vassalage in the first place. So the `vassal_assignments` row that the entire Favors & Duties / tribute / grant chain hangs off can never exist, which makes roll 20 not merely inert but *unreachable*.
- **The quest reward path is half-built.** `QuestRegistry._disburse_domain_grant` (`quest_registry.gd:329-378`) stamps `domain_grants.single_owner_pc_id` and creates a `vassal_assignments` row — then stops. **The PC gets a liege and no land.** It also probes a `save_domain_grant` repository method that does not exist, and six of ten `domain_grants` columns (hex_ids, territory_class, stronghold_present, stronghold_value, vassal_obligations, title_granted) are write-only. Separately, `QuestSeeder` never produces a `domain`-type reward, so the path is dead at both ends.
- **A PC cannot inherit an NPC's domain** — the heir picker is only reachable for domains the party already owns.

### Player → NPC (devolution): **no avenue exists at all.**

The vassal appointment dialog (`vassal_appointment_dialog.gd:156`) can only attach a vassal to a domain the henchman **already owns**. There is no domain picker, and — confirmed by exhaustive grep of every `UPDATE domains SET owner_character_id` writer — **no code anywhere transfers an existing PC-owned domain to another character.** RAW's "EVERY OTHER DOMAIN in the realm MUST BE ASSIGNED TO A VASSAL" is therefore not merely unenforced but *unsatisfiable*.

(There is a workaround the UI permits: select a henchman in the Domain tab entity strip and found a *new* domain under them. That produces a working vassal edge, but it does not devolve anything.)

### Conquest: **the pipeline is real; the player cannot win it.**

`siege_resolver.gd:497` → `EventBus.siege_concluded` → `domain_handlers._on_siege_concluded:1374` → `RealmRepository.resolve_conquest_outcome` → `LifecycleHandler.conquer_domain` is a genuine, reachable chain with three coherent outcomes. But:

- **`resolve_conquest_outcome`'s `is_tracked` test requires a `realms` row for the attacker, and no production code path ever creates one for a player character.** `create_domain` never writes `realm_id` at all. So a party-led conquest returns an empty `new_owner_id`, and `domain_handlers.gd:1401-1404` mints a brand-new **"Foreign Warlord" NPC** to receive the prize. The same happens when a player defeats the NPC challenger who emerged from their own domain's low morale: the challenger wins, and a phantom takes the land.
  This is the audit's clearest cross-subsystem seam: the bug is in **establishment**, the symptom is in **conquest**, and fixing the siege bridge alone would not help.
- **A captured stronghold keeps the loser's `owner_character_id` and gets `status='claimed'`**, which the sufficiency query excludes — so the conqueror's new domain reads zero stronghold value, the income gate slams shut, and it takes a permanent −3 morale penalty (`siege_resolver.gd:487`).
- **`SiegeSpoilsResolver` has zero production callers** — RAW siege spoils are never awarded.
- **The siege bridge still bypasses `EstablishDomainFlow`'s eligibility validator** — the deferred issue recorded in the 2026-05-22 Phase 11D.4 build-log entry is *still true*. Worse, `conquer_domain`'s return value is discarded, so a refused conquest fails silently.
- **The beastman gate is inert in real worlds.** `_conquest_eligible` infers beastman population from `establishment_method in ['clanhold_annex','recruit_chieftain']`, but every generated clanhold carries `materialized_subclanhold`.

### Clearing / claiming: **disconnected.**

The only surface that knows *which hex was cleared* — the wilderness context menu's "Build Stronghold" action, correctly gated on `HexLairState.is_stronghold_buildable` — dead-ends in a **"Feature coming soon" notification stub** (`wilderness_handlers.gd:799`). And **"Claim existing structure…"** mints a free, fully-built 25,000 gp fortress with hard-coded archetype and value, without checking that any structure exists (`stronghold_sub_tab.gd:396-412`).

---

## 3. UI/UX: are the right avenues surfaced and the wrong ones not?

**The single most important UI finding:** `establish_domain_dialog.gd` is a free-choice form. Classification is a dropdown, acquisition method is a dropdown (defaulting to the first available item — *"Land grant from a local ruler"* for civilized), own-race is a default-ticked checkbox, and pressing OK calls `EstablishDomainFlow.establish_domain` directly. No lord, no gold, no target domain, no location, no level check. **Grant, purchase and conquest are outcomes of world events; they must not be player menu picks.**

### Wrongly surfaced

| Surface | Problem |
|---|---|
| Establish dialog → "Land grant from a local ruler" | Mints a domain with no granter, no liege link, no fealty, no `vassal_assignments` row |
| Establish dialog → "Purchase … 50gp/acre" | Charges nothing |
| Establish dialog → "Conquest" | Creates a **brand-new empty domain** and leaves the target untouched — a mislabelled second founding path that duplicates and contradicts the real siege pipeline |
| Stronghold → "Claim existing structure…" | Free 25,000 gp fortress, no structure required; flips the domain to sufficient and cancels the morale penalty |
| Overview → Alignment dropdown | Instant alignment flip, bypassing religious practice |

### Missing / not surfaced

- **No UI anywhere assigns a hex to a domain.** Status header reads "0 hexes · 0 fam" permanently.
- **Realm sub-tab has no vassal-appointment control** — `gdd-domain-tab.md` §9.1 item 5 is unimplemented. The only appointment path is buried in a Henchmen-tab context menu.
- **`VassalAppointmentWarnings.warnings_for_appointment` has no UI consumer** — test-only dead code. The stacked alignment/beastman morale penalties are never shown before the player confirms. (This is exactly the surface the 2026-05-22 build-log entry deferred; it is still deferred.)
- **No tribute-setting control anywhere**, so RAW's loyalty-roll warning has nowhere to appear.
- **A PC's state *as* a vassal is completely invisible** — no liege shown, no duties owed, no monthly favors-and-duties outcome surfaced.
- **The 9th-level threshold is never communicated.** `ClassEmptyStateGuidance` — the only place level 9 is mentioned — is dead code (`domain_tab_page.gd:40` preloads it and never calls it), and its elven class ids (`spellsword`) don't match the catalog's (`elven_spellsword`), so all three elven classes would fall through to generic text anyway.

### UI bugs

- **Status header renders copper as gold** (`status_header.gd:104`) — a 5,000 gp treasury displays as "500,000" while the Treasury sub-tab one click away correctly reads "5,000 gp". The stronghold minimum also renders malformed ("3200,000").
- **Status header's garrison indicator reads `domains.garrison_troops`**, a column no player-facing flow writes — permanent "!" warning.
- **Cancelling the vassal appointment dialog emits a non-existent signal** (`emit_signal("cancelled")` where the declared signal is `appointment_cancelled`) — the dialog is never freed.
- **Selecting a clanhold method without also ticking the clanhold checkbox produces a hard validation error the dialog itself caused.**
- **Raw engine error codes are printed to the player** (`"Could not establish domain: [beastman_blocked_for_lawful_neutral]"`).
- **A syndicate/venturer character can be designated heir**, after which the Domain tab hides the inherited domain entirely and it can never be managed again.
- **The humanoid-henchman filter is short-circuited by a trailing `or true`** (`domain_tab_page.gd:331`).

### Correctly surfaced (credit where due)

Class gating for syndicate/venturer classes is correct and defense-in-depth (UI + `available_paths` + `validate_establishment`), with class-accurate empty states. Abandonment is properly gated behind type-the-domain-name confirmation with a full consequence list. The succession surface is complete and correctly conditioned on lifecycle state. Stronghold sufficiency is surfaced in three places with the correct ½ / ¼ / <¼ RAW thresholds and the noncontiguous-aware hex count. The Realm sub-tab genuinely renders title, muster cadence, realm aggregates, tribute-efficiency band and per-vassal Favors & Duties cards.

---

## 4. Does ownership actually transfer correctly?

**No.** `CampaignRepository.reassign_domain_owner` (`campaign_repository.gd:2390`) is a single-column `UPDATE domains SET owner_character_id`. Everything else keyed to ownership is left stale.

### What is left behind on every transfer

| State | What happens | Consequence |
|---|---|---|
| `domains.liege_domain_id` | **Never cleared** | **[CRITICAL]** The conquered domain stays inside the *defender's* realm graph. The apex walk carries it — and its conqueror — back up into the loser's realm. |
| `domains.realm_id` | Never re-pointed | POI contribution and allegiance queries keep counting the domain's settlements and garrison as the loser's assets |
| `strongholds.owner_character_id` | Never re-pointed | The conqueror's stronghold still belongs to the man he deposed |
| `troop_units.owner_character_id` | Never re-pointed (though `assigned_domain_id` follows) | The loser's soldiers defend the winner's domain, and the winner is billed for them, while the loser is still billed too |
| `vassal_assignments` on ruler death | **Never touched by `handle_ruler_death` or `_apply_heir`** | The corpse remains an `active` vassal; Favors & Duties keep rolling against a dead man; the heir gets no fealty edge |
| `ruler_ai_state`, `ruler_dispositions`, `realms.head_character_id` | Three delete paths exist, none has a caller; `EventBus.ruler_died` has no subscribers | Rows accumulate; a landless ex-ruler who re-acquires land resumes with a stale strategic posture |
| Domain treasury on pillage | `apply_pillage` zeroes it and *reports* `looted_cp` | Nobody is ever credited — the money is destroyed, not looted |

### Active corruption (not just staleness)

- **`_cascade_vassals` is liege-wide, not domain-scoped.** Losing *one* frontier domain marks **every** vassal assignment of the prior owner `departed` across their whole realm. A Duke with 3 domains and 8 vassals who loses one border holding instantly loses his entire realm, is demoted, and stops collecting tribute. The same function runs on *voluntary abandonment*. (`lifecycle_handler.gd:417`. Note `test_lifecycle_conquest_outcomes.gd:153-163` currently asserts the broad behavior — the test must change with the fix.)
- **A *refused* conquest still cascades.** `_cascade_vassals` runs at line 150, *before* the `_conquest_eligible` check at line 167. When the gate refuses, the domain survives — but its realm has already been destroyed. On the `LOOTED_LOCAL_SUCCESSION` empty-`new_owner_id` refusal path, pillage is irreversibly applied too.
- **The cascade contradicts itself.** It writes `vassal_assignments.status='departed'` but leaves the sub-vassals' `domains.liege_domain_id` pointing at the conquered domain — two sources of truth, permanently disagreeing.
- **No lifecycle guard on `conquer_domain`.** A ruler killed in the field battle preceding his own siege puts the domain into `succession_pending`; the siege then conquers it; then the succession grace expires and **silently hands it to the dead man's heir** — un-conquering it.
- **Two `domain_conquered` listeners act on the winner while believing they have the loser.** `RulerSeamBTrigger` and `VassalLoyaltyTriggers` both re-read `owner_character_id` *after* the write. The signal carries no `prior_owner_id`, though `LifecycleHandler` has it in hand at line 143.
- **Realm-wide economics run inside a per-domain loop keyed on owner.** A PC owning three domains has each vassal roll Favors & Duties **three times a month** and credits the same tribute into three different treasuries — the realm's tribute income is tripled out of thin air.

### The world-generation seam (largest single blind spot)

Two facts, each verified directly, that together undercut most of the above in *generated* campaigns:

1. **World-gen builds the realm tree only in `domains.liege_domain_id` and creates ZERO `vassal_assignments` rows** (22 `liege_domain_id` writes, 0 `vassal_assignments` writes under `engine/subsystems/generation/`). But `RealmAggregator`, `TributeCalculator` and `FavorsDutiesResolver` all read `vassal_assignments`. So **no generated realm has a single vassal**: tribute is deducted from every vassal and credited to nobody — destroyed, every month, in every realm — the Favors & Duties d20 never rolls for any NPC, and every King's realm aggregate equals his own personal families.
2. **Nearly every generated NPC domain is permanently ownerless** (`owner_character_id: null` at `setting_materializer.gd:1581, 1844, 2623, 2682`; the lazy-ruler promotion path has no production caller). There is nobody to swear fealty to, nobody to petition for a grant, nobody to negotiate with — and no defending ruler when you besiege them. Combined with `DomainStocker` never running in a generated campaign (no garrison `troop_units`), taking an NPC barony degrades to walking up to an undefended, unowned keep.

Also: `domains.tribute_out_owed` carries **three different unit conventions across four subsystems** (materializer and `AbstractTributeResolver` write cp; the monthly tick writes gp; the Realm sub-tab reads cp), and the first monthly tick silently redenominates and then **erases** the world-gen tribute bootstrap for every ownerless domain.

---

## 5. Rulings — RESOLVED by Jedidiah, 2026-07-28

All seven open questions have been ruled on. These are binding design decisions; the build agent implements them.

**R-1 — `domains.liege_domain_id` is AUTHORITATIVE for realm structure.**
`vassal_assignments` is the *appointment and loyalty record*, not the structural truth. World-gen must be fixed to write **both** properly. Consumers that need structure (apex walks, hostility classification, tribute chains) read `liege_domain_id`; consumers that need the relationship's state (loyalty, status, favors & duties eligibility) read `vassal_assignments`.
*Blocked on R-4* — a `vassal_assignments` row needs character ids on both ends, and generated domains are currently ownerless.

**R-2 — COPPER PIECES (cp) is the canonical monetary unit for the entire codebase.**
Rationale: cp is the lowest base unit, so every monetary value stays an **integer** and never a float. Any gp figure taken from RAW is converted to cp at the point of entry, stored and computed in cp, and converted back to gp **only for display**. This is a standing project-wide convention, not a domain-system-local rule — it is being written into `docs/coding_conventions.md`.
Immediate consequences for this audit: `tribute_out_owed` is **cp**; the monthly tick that writes it in gp is the bug; `adjust_domain_treasury(domain_id, delta_gp)` is misnamed; `status_header.gd` must convert for display rather than print raw cp; and `domain_handlers.gd:332`'s `* 100` is a straightforward double-conversion to delete.

**R-3 — The Establish-Domain dialog was a development shortcut and is to be replaced with a map-first acquisition approach.**
This resolves ~10 findings from "fix the dialog" to "delete the dialog." Acquisition becomes an act performed **on the map, against a specific hex**, which supplies the location, the classification, the own-race fact, the cleared-lair state and the target domain that the dialog invented from dropdowns. The abandoned "Build Stronghold" wilderness context-menu action (`wilderness_handlers.gd:799`, currently a "Feature coming soon" stub) is the seed of the correct surface. A GDD should be authored before this is built.

**R-4 — The ownerless generated-NPC-domain state is an UNFINISHED M2b-2 step**, missed while it waited on the NPC personality build-out. It is not an intentional supported state. The named→full ruler promotion must be completed.

**R-5 — Sub-vassals of a domain that changes hands MAKE LOYALTY ROLLS.**
Modifiers: **−1 per step of alignment difference** between the sub-vassal and the new liege (so Lawful↔Neutral or Neutral↔Chaotic = −1; Lawful↔Chaotic = −2), **plus an additional −2 if the new liege acquired the domain by conquest**. Acquisition by grant or purchase carries no such penalty.
This replaces today's unconditional cascade-to-`departed`. Note the plumbing problem: a conquered domain's `establishment_method` column still describes how the *defender* got it, so the acquisition mode must be passed to the loyalty check rather than read from the row.

**R-6 — On conquest, MERCENARY troop units do NOT transfer to the new owner. All other troop types do.**
(Militia, conscripts, tribal warriors, faithful followers and lord-favor troops follow the land; mercenaries do not follow a deposed employer's conqueror.)

Scoping these seven rulings raised nine follow-up questions; four were ruled on the same day (R-5 fires on any change of liege; direct sub-vassals only; faithful followers do not transfer either; NPC rulers **do** level from domain XP, because the per-level gp threshold is itself the throttle). See `docs/handoff-domain-rulings-implementation.md` for those and the five still outstanding.

**R-7 — Domain XP accrues to the RULER ONLY** — no share model — **and the calculation must include tribute received**, not only direct domain income. The `is_henchman` parameter on `calculate_domain_xp` needs re-purposing or removal accordingly, and the XP must actually reach `characters.xp`, which today it never does.

---

## 6. Recommended fix sequence

> **Superseded in part, 2026-07-31.** Scoping the rulings (see `docs/handoff-domain-rulings-implementation.md`) established that the real dependency order is **Tier-0 arithmetic → R-2 (cp) → R-4 (ruler promotion) → R-1 (vassal_assignments) → R-5/R-6/R-7**, which cuts across the tiers below. Two hard constraints the tier list did not capture: R-1 can mint **zero** `vassal_assignments` rows until R-4 lands (both FK ends are `NOT NULL REFERENCES characters(id)` and generated domains are ownerless), and **R-1 must not ship without Tier-1 item 6** — turning on `vassal_assignments` makes the liege-wide `_cascade_vassals` live and would destroy every NPC duke's realm on the first conquest. Use the tiers below for *what* to fix; use the handoff for *in what order*.

Ordered by dependency, not effort.

**Tier 0 — cheap, unblocks measurement**
1. Delete the `* 100` at `domain_handlers.gd:332` and fix its comment. Add a test asserting a 5,000 gp tower fails a 4-hex wilderness domain. *(Until this is fixed, no stronghold-gated behavior can be observed correctly.)*
2. Fix `status_header.gd` to use `Currency.format_cost` for the three money values.
3. Fix `emit_signal("cancelled")` → `appointment_cancelled` in the vassal dialog.
4. Move all validation in `conquer_domain` above `apply_pillage` and `_cascade_vassals`; check its return value at the siege bridge.

**Tier 1 — make ownership transfer correct**
5. Extend `reassign_domain_owner` (or the conquest/succession callers) to write `liege_domain_id`, `realm_id`, `strongholds.owner_character_id` and `troop_units.owner_character_id` in one transaction. Add `prior_owner_id` to the `domain_conquered` signal payload.
6. Scope `_cascade_vassals` Case 1 to the domain actually lost (and update `test_lifecycle_conquest_outcomes.gd:153-163`).
7. Add a lifecycle guard to `conquer_domain`; clear succession columns on a successful conquest.
8. Terminate/replace `vassal_assignments` on ruler death and heir succession.
9. Fix `domains_ruled` to count the whole realm recursively.

**Tier 2 — make the player a real political actor**
10. **Mint a `realms` row for the player at first domain establishment** and add `realm_id` to `create_domain`'s INSERT. This single change fixes the Foreign-Warlord theft, `_derive_attacker_intent`, faction realm-mirroring and conquest drift.
11. Have establishment claim the party's actual hex: write `location_map_id`/`hex_q`/`hex_r`, insert a `domain_hexes` row, roll the RAW starting population (gated by the before-9th-level rule), and derive classification and own-race from the hex rather than from dropdowns.
12. Charge gold: 50gp/acre for purchase, and debit stronghold commissions.

**Tier 3 — build the missing avenues**
13. Remove `grant` / `purchase` / `conquest` from the player-initiated dialog. Route `conquest` to `LifecycleHandler.conquer_domain` when a target is supplied; reject it otherwise.
14. Implement the `grant_of_land` mechanical effect per RAW sizing, and wire `PlayerVassalService.swear_fealty` to a reachable surface (a `petition_for_land` / `offer_fealty` move on `RulerAudience` is the natural home). Give `RulerActionCatalog` an offer action.
15. Build a **domain devolution** path (assign an owned domain to a henchman vassal) and surface it on the Realm sub-tab, consuming `VassalAppointmentWarnings`.
16. Finish the wilderness "Build Stronghold" action so clearing a hex leads to founding a domain there.

**Tier 4 — world-gen contract**
17. Have world-gen write `vassal_assignments` alongside `liege_domain_id` (or switch the consumers), declare the `tribute_out_owed` unit, promote on-map NPC domain rulers, and run `DomainStocker` so besieging a barony is a contest.
18. Wire domain XP to `characters.xp`.

---

## Appendix — audit provenance

14 agents, 756 tool calls, ~2.4M tokens. Findings that failed adversarial refutation were dropped; five confirmed findings were downgraded or corrected by the verifier and those corrections are reflected above. Notable corrections: the classification-dropdown defect is self-healing within two months (regression works); the `refused-conquest` pillage claim holds only on the `LOOTED_LOCAL_SUCCESSION` path; `RulerSeamBTrigger`'s half of the stale-listener bug is currently inert because it early-returns unless the LLM is configured; and `docs/npc-domain-systems-stock-take-2026-06-27.md` is now a month stale — at least four of its "Gap" verdicts are false (the ruler-AI planner, `StrategicDisposition`, the `realm_relations` writer and alliance edges have all since been built).
