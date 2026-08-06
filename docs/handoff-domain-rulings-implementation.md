# Domain Rulings — Implementation Handoff

**Date:** 2026-07-31
**Companion to:** `docs/domain-acquisition-audit-2026-07-28.md` (the audit; its §5 carries the rulings verbatim)
**Purpose:** Turn Jedidiah's seven rulings into sequenced, implementable work. Scoped by three parallel agents reading the current working tree on `dungeon-refactor`; every file:line below was read, not inferred.

---

## STATUS at HEAD `f7e6c98` (re-verified 2026-08-03)

**Landed** (all at suite 572/0): Tier-0/P0 — the four unit bugs, plus `conquer_domain` made all-or-nothing (validation hoisted above `apply_pillage` and `_cascade_vassals`) and the siege bridge now checks its return value · R-2 **P1** (display boundary) and **P2** (8 gp-named EventBus signal params → cp; `cache_raided` float → int) · conventions **§127** · **D-9** (ruler level tables unified into `DomainTierTable.ruler_level_for_title`) · the spun-off battle-rating chips.

**R-4 — ✅ COMPLETE 2026-08-04** (suite 575/0; `SettingMaterializationTests` 221 checks). `RulerStubMinter` (`engine/subsystems/generation/materialization/ruler_stub_minter.gd`) mints the eager-cheap `persistence_tier='named'` ruler, and **all four** materializer sites are wired — the civ vassal ladder, every crown (including war-vassal crowns, which Pass 3 was skipping), and both 6-mile M4-1b leaf sites. **The generated world is no longer ownerless anywhere.**
- *Design correction to D-8:* R-4 is a **PROMOTION, not a generation** — `setting_domains` already carries pre-rolled `ruler_class` / `ruler_level` (D-9-canonical already) / `ruler_name` (a culture-derived dynasty surname). The leaf layer, which has no pre-rolled stub, inherits its class from the parent domain's owner.
- *The R-1 precondition is asserted end to end* by `test_every_liege_bearing_domain_has_an_owner`: the vassal end, the **liege** end, no dangling owner ids, and **no ruler owning two domains under the same liege** (`idx_vassal_assignments_unique_active` permits one active edge per character pair).
- *Still unbuilt by design:* the **lazy-rich half** — nothing yet promotes a stub to a full `ClassedNpcBuilder` character on first contact. The GDD's promote-on-visit path (`gdd-setting-runtime-materialization.md` §15.5) has no runtime caller, so a stub entering combat would fight at schema-default hp 1 / AC 0.

**R-1 — ✅ COMPLETE 2026-08-04** (suite **575/0** on the second consecutive run, both runs exit 0; `SettingMaterializationTests` 221 → **230** checks; **0 `vassal-edge sweep` errors in the log**, so the sweep's ownerless-end hard-fail never fired and R-4's invariant holds across a real generated world). Shipped as ONE wave with the cascade-scoping fix and the Favors & Duties per-ruler hoist, exactly as the "dangerous to land alone" section below required. **The generated world now has a realm tree that other systems can actually read.**

- **World-gen edges: ONE SWEEP, RUN LAST** (`SettingMaterializer._materialize_vassal_edges`), not an INSERT beside each `liege_domain_id` write. Four passes write that column at four different moments, and **Pass 3 assigns crown owners only AFTER Pass 2 has chained each polity's whole ladder to its crown** — so a per-site insert would be minting edges whose liege end has no owner yet. One terminal sweep is correct by construction, covers the civ ladder + the war-vassal crown chain + both 6-mile leaf types + any future pass, and (because it runs after `_materialize_county_settlements`) is the only point where the RAW range-of-trade test can even be evaluated. `_cleanup_partial` now clears `vassal_assignments`/`vassal_obligations` before `domains` and `characters`.
- **RAW `is_henchman_vassal = 0`.** `acore_axioms` §non_henchman_vassals L392-397: a world-generated vassal is his lord's *sworn noble*, not his henchman — base loyalty −2 (or −4 outside the range of trade), and **no free duty** each month. `VassalRepository.create_assignment` DEFAULTS the flag to **true**, so world gen passes it explicitly; otherwise every NPC baron alive would have rolled as his duke's henchman.
- **The −4 refinement is a SECOND pass** (`_apply_range_of_trade_loyalty`), and has to be: `TradeRangeResolver.largest_urban_settlement_for_ruler` resolves settlements *through* `RealmAggregator.aggregate`, which walks the vassal edges — asking during the mint would answer from a half-built tree, giving each liege only the vassals minted before him. It is also restricted to **located** domains with a settlement-holding liege, because `TradeRangeResolver` reads a missing settlement as "no trade range" and would otherwise stamp −4 across the entire off-camera world as an artifact of LOD.
- **Cascade scoped** to the lost domain via the authoritative `liege_domain_id` pointer, and `_cascade_vassals` lost its now-meaningless `prior_owner_id` parameter. Landless personal oaths (`vassal_domain_id` NULL) are deliberately untouched — an oath is sworn to the ruler, not to one of his domains.
- **F&D hoisted** to `_resolve_favors_and_duties_for_rulers`, once per ruler, gated on the same PC-or-active-LOD predicate the domain loop uses, and placed **after** the loop closes — `_save_domain` writes `treasury_cp` as an absolute `prior + net` from a pre-loop read, so an in-loop gift/loan into another domain's treasury was being silently overwritten when that domain's turn came up. `favors_duties` is no longer a per-domain result key (nothing consumed it); the tick returns `favors_duties_reports`.

**Four more R-1-activated defects fixed in the same wave** (each verified in the repo, not inferred):

1. **`RebelCoalition._repoint_domains_to_realm`** cleared `liege_domain_id` without departing the edge — a successful secession would have gone on paying tribute to the lord it just rebelled against, and the cascade could never reach it (it finds vassals *through* the pointer being erased).
2. **`ResignationLadder._reparent_domain_to`** re-pointed the domain but left the assignment on the OLD liege. Now departs the old edge and opens one under the new liege (independence = no new edge).
3. **`RealmAggregator.aggregate` walked every subtree TWICE** — the loop already had the peasant/urban split and threw it away, then re-walked the whole tree for it. Plus **migration 215** indexes `domains(owner_character_id)`, the innermost lookup of every node visit, which was an unindexed full table scan.
4. **`_MAX_DEPTH` 8 → 64** (matching `RealmGraph._MAX_LIEGE_HOPS`). R-1 made the tree genuinely walkable and a generated realm stacks the civ ladder under war-vassal crown chains, so 8 was reachable: it silently under-reported a deep realm's families — corrupting the RAW tribute lookup — while spamming `push_error` monthly. The `visited` set was always the real cycle guard.
5. **The abandonment dialog** counted vassals liege-WIDE while the cascade releases only fiefs held of that domain — an inflated, mislabeled number on an irreversible player action. Now uses the cascade's own predicate.

**R-5 — ✅ COMPLETE 2026-08-04** (suite **576/0**, both runs exit 0; new `SubVassalLoyaltyTests` at 32 checks). `SubVassalLoyalty` uses a **swapped-liege probe** — `project_modifier_breakdown` reads the liege off the assignment dict, so copying the edge with the new lord in it re-evaluates alignment/culture/religion/strength/grievance for free, and the alignment term is applied exactly once (`alignment_steps()` is reporting-only, locked by a test). `_cascade_vassals` split into `_detach_upward_edge` (+ the missing `liege_domain_id = NULL`) and `_detach_downward_edges`; downward only detaches when there is NO successor lord. `EventBus.domain_conquered` gained `prior_owner_id`.

- **Succession re-points but does NOT roll; conquest rolls in place.** An adversarial review caught `_apply_heir` double-rolling: it re-pointed the edges onto the heir, then `succession_resolved` fired the §5.2 check over `list_active_for_liege(heir)`, which now contained them — the second roll consuming the one-shot Grudging −1 the first had just written. Conquest is safe only because its trigger fires over the PRIOR owner. Do not "helpfully" symmetrise these.
- **Two pre-existing bugs fixed:** `VassalLoyaltyTriggers` and `RulerSeamBTrigger` both identified the loser by reading the owner back off the domain row — but `reassign_domain_owner` runs before the emit, so both were acting on the CONQUEROR.
- **Known gap:** `office_bonus_for_vassal_roll` takes only the vassal's id and re-reads the liege from the DB, so RAW L369's ±1 is measured against the DEPARTING lord during a transfer roll. Also, the Resignation band re-enters `ResignationLadder.abdicate_into_exile`, which transfers an ARBITRARY domain of the sub-vassal — pre-existing, newly reachable.

**R-7a — ✅ COMPLETE 2026-08-05** (suite **577/0**, both runs exit 0; new `DomainXpAwardTests` at 88 checks). Domain income reaches `characters.xp` for the first time in the project's history. `XPAwardCalculator.calculate_domain_xp_cp` converts the RAW gp threshold **UP** to copper so the comparison stays integer; the trailing `/100` is RAW's gp→XP **rate**, not a currency conversion. NEW `XpAwardService` (atomic `xp = xp + ?`) and NEW `DomainXpResolver`. Migration **216** guards double-awards. See the R-7a section below — three decisions there must not be silently reversed. **The +5% administer_domain XP bonus is RAW (`ax_campaign_play.xml:511`) and is kept**; migration 068's citation for it points at the wrong file, which briefly cost it its life mid-session — see conventions §138.

**D-12 — Phases A + C ✅ 2026-08-05, Phase B ✅ 2026-08-06.** The monthly tick resolves the
CHARACTER'S DOMAIN, not a `domains` row: three passes, one morale roll per ruler mirrored to every
parcel, personal authority on his summed income, sufficiency on his combined strongholds, and
tribute charged once instead of once per liege-bearing parcel. New `DomainUnifiedMonthTests` at 50
checks. See the D-12 STATUS block below; the general shape is conventions **§139**.

**Not started:** D-12 **D**/**E**/**F** · R-2 **P3**/**P4** (take migration **217**) · **R-6** ·
**R-7b** (rides with D-12 Phase F) · **D-5** · the remaining audit **Tier-1** ownership-transfer fixes.

**Next stage: D-12 Phase D** (directed investment), then E, then F. Then D-11.

### D-10 — Tribute scope: the penalty is per CHARACTER, the credit is per SEAT (Jedidiah ruling 2026-08-04)

**The question asked:** which domain is a multi-domain ruler's *seat* for receiving tribute?

**The answer: it is not a seat question.** A lord "gets the tribute from all vassals of both domains", and the RAW §tribute_inefficiency penalty keys on "the sum-total of ALL vassals paying tribute to a single character, **regardless of which domain seat they are paying to** so long as it goes to the same character."

So the two halves have different scopes, and keeping them apart is the whole design:

| | scope | why |
|---|---|---|
| **Inefficiency factor** | the **CHARACTER** | a lord with two seats of six vassals each is a *twelve*-vassal lord, taking the 9–16 band's 66% — not two six-vassal lords at 100% |
| **Credit** | the **DOMAIN** | each vassal's tribute lands in the seat his fief is actually held of (`vassal domain → liege_domain_id`, R-1's authoritative pointer) |

The seats therefore **partition** the realm intake instead of each banking all of it.

**Already correct before the fix:** `TributeCalculator._EFFICIENCY_TABLE` implements all eight RAW bands, and `direct_count` already came from `list_active_for_liege(ruler_character_id)` — character-keyed, summing every vassal across every seat. **No new table was needed.** (Note the standing RAW patch: source L406 reads "17-36 = 50%", leaving an algebraic gap 37–63 before the next band's 64. A prior session read that as a digit-transposition typo and implemented "17–63"; the XML is unchanged per the sacred-rules constraint. Flagged for Jedidiah's eye — it is an interpretation, not a mechanical reading.)

**What changed:** `_compute_tribute_in_for_ruler(ruler_id)` → **`_compute_tribute_in_for_domain(domain_data)`**, plus `_tribute_destinations(ruler_id)` mapping each assignment to the payer's liege seat. The summary gained `realm_total_received_cp` (the lord's whole intake, for display) beside the now seat-scoped `total_received_cp`. Unresolvable destinations — a landless oath with a NULL `vassal_domain_id`, or a liege pointer that has drifted off this ruler's holdings — fall back to the lord's lowest-id domain, so the realm total stays conserved rather than a payment vanishing.

**Why it mattered more than "rulers usually hold one domain" suggests.** Four production paths hand a domain to a character who may already hold one: conquest (`lifecycle_handler.gd:191`/`:194`), escheat to the liege (`ruler_death_handler.gd:393`), **heir inheritance by an already-landed vassal** (`:363` — the likeliest of the three in a dynastic game), and RAW's Favors & Duties roll 20 *Grant of Land*, which is still signal-only but by design makes this routine: a 1-in-20 monthly roll for every vassal in the world.

### Jedidiah's revisit list (raised 2026-08-04, to be taken up after R-5)

1. **Leaf rulers inheriting the parent lord's class.** R-4's `SettingMaterializer._owner_class_for_domain` gives a 6-mile leaf sub-fief's ruler the `character_class` of the PARENT domain's owner. The rationale was to avoid a second class distribution drifting from `HistorySimulator._domain_ruler_class`, and to keep a sub-chieftain the same beastman kind as his crown. **Review whether that is right for populated civ leaves**, where a vassal has no particular reason to share his lord's class.
2. **The multi-domain ownership accounting method** — i.e. D-10 above. Open sub-questions: is the lowest-id fallback for unresolvable tribute destinations acceptable, and should **domain XP** follow the same seat-partition as the treasury credit does?
3. ~~Gate the Grant of Land favor.~~ **RULED — see D-11 below.**

---

## D-11 — Grant of Land (F&D roll 20): LAND IS CONSERVED (Jedidiah ruling 2026-08-05)

**The correction that drives everything else.** RAW's "generate the new domain normally" does **NOT** mean generate *land*. Land is a fixed resource tied to the map's hexes; we cannot create new land and we cannot create overlapping domains. "Generate the domain" means **stat it out** — build (or stat an implied existing) stronghold, determine peasant/urban population, settlement presence and size, land value, and gross/expenses/net income — and **it requires a specific named territory to do so: a hex number.**

The data model already enforces conservation: a hex is owned **iff** a `domain_hexes` row exists for it (`domain_id`, `map_id`, `hex_q`, `hex_r`, `land_value`, `families`), and `release_domain_hexes` deletes rows to return land to the unowned pool. What does NOT exist yet: any unclaimed-hex query, any adjacency helper, and any hex-transfer path. `EstablishDomainFlow` already lists `grant` as a valid acquisition method — the hex SELECTION is the hole.

**RAW's two clauses are two different mechanics** (`acore_axioms` §favors_and_duties row 20):
- *no sub-vassals* → **one specific adjacent unclaimed hex**: create a domain + one `domain_hexes` row, then stat it.
- *has sub-vassals* → a grant **at least as large as the smallest of his own vassal domains**: normally a TRANSFER of an existing domain, not a new one.

### The rulings

1. **Source ladder, in priority order:** (i) an ownerless / escheated domain in the realm → transfer it; (ii) unclaimed hexes adjacent to the vassal's holdings → enfeoff; (iii) carve from the liege's own domain.
   - **A granted EMPTY hex obliges the NPC to SPEND MONEY building his stronghold there.** The grant is not free value. Until built, the new domain is stronghold-deficient and takes the RAW insufficient-stronghold morale penalty. Reuse the F&D "Construction" duty's monthly-expenditure pattern (RAW row 1) rather than inventing a second one.
2. **The liege's own domain IS a valid source, but he will NOT grant a hex when doing so would:**
   - **(a)** give away the hex containing his settlement;
   - **(b)** reduce his own domain to a **hex count** smaller than ANY of his vassals' domains;
   - **(c)** reduce his total population below **(i)** any of his vassals' current domain populations, or **(ii)** push his income below his **XP-from-income threshold for his level** — *unless he is already below it*, in which case (c)(ii) simply does not apply. "He won't curtail his own advancement for his vassal."
   - **(c)(ii) IS A PURE GATE — it is NOT a propensity term** (Jedidiah, 2026-08-05, correcting an earlier over-reading of "more likely to grant" as illustrative rather than mechanical). **The d20 roll is never re-weighted by circumstance.** Above threshold the gate blocks; already below, it is simply inert.
3. **No land available anywhere on the ladder → RE-ROLL** the favor.
4. **"As large as" is measured in HEX COUNT** — the only basis.
5. **An abstract vassal cannot receive a grant.** Gate the favor on the vassal's domain having `domain_hexes` rows; only in-window domains have any (`_materialize_domain_hexes` runs solely over the region map, so off-window realms own zero hexes and have nothing to be adjacent to).

### Implementation notes

- **(2)(c)(ii) — dependency SATISFIED by R-7a (2026-08-05).** The gate needs "would this grant drop my income below my level's XP threshold?", which is now answerable: `XPAwardCalculator.calculate_domain_xp_cp(net_income_cp, level, is_henchman)` returns 0 at or below the threshold, and `GP_THRESHOLD_TABLE[level] * 100` is the threshold in copper directly. No stub or TODO is needed.
- **Volume is NOT the concern it looked like.** After the R-1c hoist, F&D rolls only for PC-side and active-LOD lieges (`domain_handlers.gd` — `pc_ids.has(owner) or active_ruler_ids.has(owner)`), so this is bounded by the play window, not by the ~1,000 domains in the world.
- **Clanholds are already excluded** — `favors_duties_resolver.gd:128` blocks `grant_of_land` per RAW L51 ("Chieftains cannot offer grants of title").
- **DO NOT add a deliberate land-grant action to the ruler-AI vocabulary** (Jedidiah, 2026-08-05). Granting land to hold a wavering vassal is a reasonable idea, but adding it now would **double up on Favors & Duties** and start policy-weighting favors piecemeal across two dozen sessions and as many `.gd` files. **Everything stays on the d20 roll for now, unmodified by circumstance beyond the hard gates above.** If policy-weighted favors are ever built, they get built all at once, as one coherent pass.

## D-12 — The unified personal domain: one character, one domain (Jedidiah ruling 2026-08-05)

### STATUS — Phases A + B + C COMPLETE (A/C 2026-08-05, B 2026-08-06)

**Phase B landed 2026-08-06.** The monthly tick now resolves a CHARACTER'S DOMAIN in three passes:
pass 0 groups the non-terminal parcels by owner and builds each owner's `PersonalDomain` union
**before anything is written** (the union re-reads `domains` while `_save_domain` UPDATEs it, so a
lazily-built union would see some parcels on last month's numbers and some on this month's); pass 1
builds each parcel's month context and accumulates the owner's total revenue; pass 2 resolves,
rolling morale ONCE per character and mirroring it to every parcel.

What moved onto the union: **personal authority** (level × Σ revenue — the oversize exploit is
closed), **stronghold sufficiency** (combined value vs. Σ per-hex minimum, so one keep can secure
two parcels and one copper short gates them both), **classification** (worst hex, via the new
`resolve_base_morale(..., classification_override)` parameter), **garrison** and **levy** (both
RATIOS — re-derived from summed numerator and denominator by the new
`GarrisonExpenditureCalculator.combine`, never averaged), **event modifiers** (`_union_event_modifiers_sum`
replaced the per-parcel `_event_modifiers_sum`: rates from the seat, garrison from the combined
summary, administration from ANY parcel, challenger and settled-lair penalties summed), and
**tribute + scutage** (charged once, on `PersonalDomain.tribute_seat_id`).

**Every reader of stronghold sufficiency moved with the tick.** Deleting the two per-parcel helpers
surfaced **eight** other call sites asking the same question per parcel — the Domain status header,
the Overview / Stronghold / Treasury sub-tabs, `manage_stronghold`, `RulerActionCatalog._stronghold_below_minimum`
and `RulerAI._scoring_context`. NEW `PersonalDomain.sufficiency_for_domain(domain_id)` (and
`.sufficiency(union)` for callers that already hold one) is now the single answer for all of them:
`{value_cp, minimum_cp, shortfall_cp, is_sufficient, owned/intervening/effective_hex_count,
parcel_count, is_materialized, character_id}`. Left half-moved, the UI would have contradicted the
income gate it was explaining and the ruler AI would have kept buying keeps for land his other
strongholds already secured.

Carrier design as specified: the **lowest-id parcel** (`PersonalDomain.seat_parcel_id`) holds prior
morale and the categorical inputs that cannot be summed — alignment, population kind, tax/liturgy
rates. Ordering by `id` rather than by the tick's own order matters: `list_campaign_domains` is
`ORDER BY created_at`, which has second resolution and is unstable for rows created together. No
`characters.domain_morale` column was added; the result is mirrored to every parcel row so every
existing reader of `domains.morale` keeps working. Repression ORs the flag across parcels and takes
the harshest rate. Dead code removed: `_event_modifiers_sum`, `_stub_stronghold_value`,
`_classification_minimum_cp`.

New in Phase B: `tests/test_domain_unified_month.gd` (suite 613, 50 checks) — one roll mirrored,
authority on the summed income (with an explicit assertion that splitting WOULD have been worth
morale), tribute charged once and not twice, sufficiency across the holding both ways, worst
classification, administration from a non-seat parcel, the garrison combine (including a mixed
clanhold/civilized blend), and a levy diluted by the whole population. A single-parcel ruler is
regression-locked to be unaffected.

**Known scope limits carried out of B:** domain XP is still awarded per parcel (that is R-7b /
Phase F), so the administer flag is character-wide for morale but per-parcel for the +5% XP;
settlement investment is still routed to the first settlement row (Phase D); `domains.liege_domain_id`
is still the allegiance pointer (Phase E).

### Phases A + C — as landed 2026-08-05 (suite 578/0)

- **A — `PersonalDomain` (`engine/subsystems/domains/personal_domain.gd`).** The union: families,
  income, hexes joined to `hex_cells.civilization`, worst classification, per-hex stronghold minimum,
  per-hex garrison rate, and effective hex count including intervening hexes. The **two-tier rule is
  enforced** — abstract domains (zero `domain_hexes` rows) fall back to the per-domain aggregate and
  `is_materialized` reports which regime produced the numbers. **Terminal parcels are excluded**
  (an abandoned holding would otherwise charge its former lord oversize and tribute). The contiguity
  walk groups by **`map_id`**, which is a NAMESPACE GUARD and not multi-map support — see the
  correction below. `StrongholdRepository.connecting_hexes_for_set` was split out of
  `get_effective_hex_count_for_domain` (behaviour unchanged) because the per-hex minimum needs the
  intervening hexes' COORDINATES, not just their count.
- **C — `ClassificationAdvancement.propagate_to_hexes`**, wired into `_save_domain` where
  classification is actually persisted. Without it, per-hex costs would quote each domain's ORIGINAL
  classification forever. A test locks the regression end to end.
- **Found and fixed in passing:** `CampaignRepository.add_domain_hex` silently dropped `families`.
  Migration 173 added the column; world gen inserts `domain_hexes` with raw SQL
  (`setting_materializer.gd:1614`), so the repository writer's omission never surfaced — D-12's
  per-hex garrison cost is the first consumer to read it.
- **CORRECTION (Jedidiah, 2026-08-05) — `domain_hexes.map_id` is effectively a CONSTANT.** Phase A
  shipped with a comment claiming the per-`map_id` grouping protected "holdings on separate maps".
  That world does not exist. A campaign has **one rolling 6-mile map**: `RegionZoomIn` inserts a
  single `regional_6mi` row (`region_zoom_in.gd:211`) and `grow_frontier` GROWS THAT SAME ROW — new
  `hex_cells` plus an extended `parent_hex_footprint` — rather than minting another. Both
  `SettingMaterializer` (`:192`) and `RulerLodManager` (`:176`) resolve it with `LIMIT 1`, and world
  gen stamps every `domain_hexes` row with that one id (`setting_materializer.gd:1615`). The column
  is a **migration-119 holdover** from the older 24-mile-map-plus-discrete-insets model, which the
  rolling frontier replaced. The grouping is kept only as a namespace guard against
  `CampaignRepository.add_domain_hex`'s empty-`map_id` sentinel; it is inert in production. **Phase B
  may therefore assume a single coordinate space** — which also means intervening hexes are always
  resolvable, since the whole materialized region is one contiguous footprint.
- **Not started: D, E, F.**

### The ruling

**RAW does not permit a character to hold multiple domains.** Any land a character personally rules
is *his domain*, one record — "each character sheet has one domain record page." He may hold many
strongholds within it (so long as their combined value secures the land), non-contiguous hexes, and
secured-but-unpopulated hexes. It is all one domain no matter how far apart the pieces lie. So when a
vassal dies heirless, or a lord conquers without appointing a vassal, or secures a distant hex with
its own stronghold, **it all merges: JOHN'S DOMAIN.** The RAW penalties for an oversized or
non-contiguous domain are what price that.

**Allegiance is SINGULAR and PERSONAL, not multiple and territorial.** Vassals are sworn *to the
person*, not to the land. If John holds a barony of Duke A and conquers a barony of Duke B, John is
already Duke A's vassal, so **he pays all his tribute to Duke A and Duke B loses the barony
altogether.** This is deliberately not the historical norm. The historical alternative — allegiance
following the land — has a fatal consequence: a Duke could never grow his realm through his own
barons' conquests, because conquered territory would stay sworn to its former liege, making John a
potential **enemy of himself**. Singular personal allegiance is the ACKS norm and the tractable one.

**Chosen model: PATH 2 — aggregate-on-read.** `domains` rows are retained as *parcels* for identity
and history; the **character** is the domain. Every RAW-relevant quantity is computed on the union of
a character's owned parcels. Rejected: **Path 1** (verbatim merge to one row — high cascade risk
across a dozen FK tables, destroys parcel identity and history) and **Path 3** (forbid the state at
the acquisition boundary — *less* RAW-faithful, since RAW permits holding it all and taxes you for
it).

**Unify: income, morale, garrison, tribute, allegiance. Keep per-hex: territory classification.**

### Why the current model is wrong — three quantified divergences

1. **The oversize penalty is completely defeated by splitting.** RAW's oversize mechanic *is*
   personal authority (`acore_axioms` §personal_authority L430-449): class level cross-referenced
   against **domain income**, down to −4 base morale. `DomainMoraleResolver._personal_authority_modifier(level, monthly_revenue_cp)`
   is called with **that row's** revenue. A 6th-level lord with one 600 gp domain takes the harsh
   band; split into three 200 gp parcels he gets three lookups in a mild band — a straight morale
   *bonus* for holding land in pieces, and the RAW ceiling on how much land a level can rule never
   binds.
2. **Tribute-out is overcharged — and the real defect is worse than the concave-sum argument.**
   *Corrected 2026-08-05 by reading the code rather than the spec.* `_compute_tribute_out_for_vassal_domain`
   (`domain_handlers.gd:1265`) does **not** use the parcel's families: it calls
   `RealmAggregator.aggregate(owner_id)` and passes `all_realm_families` — already the whole
   CHARACTER's realm — into `TributeCalculator.compute_tribute_base_cp`. But it is invoked **once per
   parcel**, gated only on that parcel having a `liege_domain_id`, and the full figure is written to
   each parcel's `tribute_out_owed`. So a lord holding two liege-bearing parcels owes his **entire
   realm's tribute TWICE** — a clean N× multiplication, not a ~55% concavity error. (`idx_vassal_assignments_unique_active`
   forbids two parcels under the *same* liege, but two parcels under *different* lieges is exactly the
   escheat/conquest case D-12 exists for.) The fix under Path 2 is therefore not "sum the families
   first" — the families are already right — it is **compute tribute once per character and charge it
   once**, which falls out of resolving parcels together.
3. **Non-contiguity stops biting.** RAW §noncontiguous_domains L95-98 has no standalone penalty — it
   works *through* stronghold sufficiency: the stronghold must secure owned **plus intervening**
   hexes, else it counts insufficient and morale suffers (−1/−2/−3). Separate parcels are each
   internally contiguous, so intervening hexes are never counted and the penalty never fires.
4. *(after R-7)* the per-level gp XP threshold is subtracted once **per parcel**, so splitting
   subtracts it N times.

### What already works — do not rebuild these

- **`RealmAggregator._list_owned_domains` already unions a character's owned domains** into
  `personal_families` / `personal_peasant_families` / `personal_urban_families` / `personal_revenue_cp`
  / `personal_expenses_cp` / `personal_garrison_units`. **Path 2's foundation exists** — it is simply
  never used for the per-domain RAW math.
- **Per-hex classification is already persisted at runtime, at BOTH scales.** `hex_cells.civilization`
  (`CHECK IN ('civilized','borderlands','wilderness')`, keyed `(map_id, q, r)`), and
  `RegionZoomIn` propagates each 24-mile parent's value to all sixteen 6-mile children
  (`region_zoom_in.gd:226` `p_civ`, `:250`). **No migration is required** — `domain_hexes` already
  carries `map_id, hex_q, hex_r`, which joins straight to `hex_cells(map_id, q, r)`.
- **Encounter tables already read per-hex classification** via `HexTerrainData.civilization`
  (city → `{city:100}`, civilized → `{inhabited:100}`, borderlands → `{inhabited:50,_natural:50}`,
  wilderness → natural tags). That path is correct today.
- **Market class needs NO unification.** In RAW it is a property of a **settlement**, not a domain —
  a domain with two towns has two markets, and merging holdings does not merge towns. The derived
  value we depend on is already unified correctly:
  `TradeRangeResolver.largest_urban_settlement_for_ruler` already walks the ruler's owned domains AND
  vassals, so R-1's non-henchman −2/−4 range-of-trade base is already right under Path 2.

### INVARIANT — settlements are locality-scoped and STABLE (Jedidiah 2026-08-05)

**Unification applies to the RULER's economics. It must never reach a settlement's own state.**
Urban settlements are generated from realm population at generation time and 6-mile zoom-in/fill, and
**once generated they do not re-factor on a change of ownership.** They change only through normal
population growth/decline and war/siege. If John holds a settlement on day 90 and conquers a domain
with a second settlement on day 98, **no population moves from the conquered settlement to his
first.**

*Verified already safe:* `urban_families` lives on **`settlement_entrances`** (schema :1256), keyed to
the settlement's own row and its own `map_id/hex_q/hex_r` — **migration 097 deliberately relocated it
off `domains`** (:788). Conquest re-points `domains.owner_character_id` and leaves settlement rows
untouched, so population cannot migrate between settlements. `market_class` is likewise per-settlement
(:1248). *Also already safe:* `SettlementGrowthResolver` reads only **`peasant_families`** (clanhold
cap math) and **`domain_style`** from the domain — not morale, not income, not territory — so growth is
already driven by the settlement's own state.

**Two rules this imposes on the D-12 build:**

1. **The settlement growth tick receives its PARCEL's data, never the union.** The one input that
   would distort is `peasant_families` feeding the clanhold cap: realm-wide, it would inflate the cap
   for every settlement the character owns.
2. **Fix the investment routing as part of D-12, not after** (see open question 2 below). It does not
   move existing population, but concentrating the whole pool in one arbitrary settlement produces
   exactly the forbidden symptom over time — one settlement balloons while its neighbours stagnate,
   from a row-ordering artifact rather than from anything in the fiction. Unification widens the pool
   from one domain's to the whole character's, so it gets worse, not better.

### Directed investment (Jedidiah ruling 2026-08-05) — REQUIRED part of D-12

**Investment allocation is player/AI DIRECTED, never auto-split.** The ruler decides which settlement
his money develops; growth follows intent, not row order or a formula.

**Both actors already have the action — what is missing is a TARGET.**
- **Player:** `engine/subsystems/activities/handlers/oversee_investment.gd` commits cp into
  `domains.pending_investment_cp`, consumed by the next monthly tick.
- **Ruler AI:** `oversee_investment` is already in `RulerActionCatalog` (`:34`), with a 1,000 gp
  tranche per action ("the RAW granularity of agricultural investment", `:72-73`) gated on surplus
  treasury (`:110-113`).

Neither names a settlement, so `_resolve_settlement_growth_for_domain` dumps the whole pool into the
first row returned. The change is therefore **aim the existing actions**, not build new surfaces:

1. **Store the pending investment ON THE SETTLEMENT, not the domain** — add
   `pending_investment_cp` to `settlement_entrances` (next free migration; **216 is reserved for R-2
   P3**). This matches the locality invariant (investment is directed *at* a settlement), lets a
   ruler split across several, and removes the domain-level pool that unification would otherwise
   widen to the whole character.
2. **`oversee_investment` (activity) takes a target settlement id.** The UI surfaces the ruler's
   settlements to choose from.
3. **The ruler-AI candidate chooses a target**, scored by disposition — an economically-minded ruler
   develops his best market, a defensive one his seat. Keep the existing tranche and treasury gate.
4. **Default when nobody directed it** (backdrop/LOD rulers, or a player who committed without
   choosing): the ruler's **largest urban settlement**, via the existing
   `TradeRangeResolver.largest_urban_settlement_for_ruler`. Deterministic, defensible, and reuses
   machinery already in place — never "the first row".

### The seams to change

| Quantity | Was | Under D-12 | Status |
|---|---|---|---|
| Personal authority (oversize) | `_personal_authority_modifier(level, this row's revenue)` | level × **total income across all his parcels**, one lookup | ✅ B |
| Tribute-out | charged once per liege-bearing parcel | computed and charged **once per character**, on `tribute_seat_id` | ✅ B |
| Scutage | same per-parcel charge as tribute | rides the same seat gate | ✅ B |
| Stronghold minimum | `stronghold_min_gp_per_hex(domain.territory_type) × hex_count` | **Σ over hexes** of that hex's own minimum, via `domain_hexes → hex_cells.civilization` | ✅ A + B |
| Garrison morale signals | `garrison_gp_per_family` per parcel | ratio re-derived from summed spend / summed families (`GarrisonExpenditureCalculator.combine`) | ✅ B |
| Levy morale penalty | density over the parcel's families | density over the character's families | ✅ B |
| Stronghold sufficiency | effective hex count **within one row**, asked separately by 9 call sites | owned **+ intervening** across ALL his parcels (RAW §noncontiguous_domains), one shared `PersonalDomain.sufficiency_for_domain` | ✅ A + B |
| Morale | one roll per parcel | **one roll for the character's domain**, mirrored | ✅ B |
| Morale classification modifier | this parcel's `territory_type` | the union's **worst** classification | ✅ B |
| Domain XP | per parcel, threshold subtracted N times | once per character, none from vassal-managed land | ⬜ F (R-7b) |
| Settlement investment | whole pool to the first settlement row | directed at a named settlement | ⬜ D |
| Allegiance | `domains.liege_domain_id` per parcel | **`vassal_assignments.liege_character_id`** — one liege per character | ⬜ E |

### Phase B's ordering problem — found 2026-08-05 while building Phase A, SOLVED as built 2026-08-06

*(Kept as the rationale for the three-pass shape now in `DomainHandlers._handle_monthly_tick`. The
general form is conventions §139.)*

**Exactly one unified quantity needs THIS month's numbers, and that one forces a restructuring.**
The monthly tick resolves one `domains` row at a time. Of the quantities D-12 unifies:

- **families** (tribute-out), **hexes + classification** (stronghold minimum, garrison rate, worst
  classification), **stronghold value** — all read PERSISTED state, so a per-owner union computed at
  any point in the tick is correct. These need no reordering at all.
- **Personal authority** does not. RAW cross-references class level against domain **income**, and
  `DomainMoraleResolver.resolve_base_morale` is handed `revenue["total"]` — *this month's* figure,
  computed inside the parcel's own resolution. Summing across a character's parcels therefore
  requires every parcel's revenue to exist **before** any parcel's morale is rolled.

So Phase B is genuinely two passes, and "one morale roll per character" needs the same shape anyway:

1. **Pass 1 — revenue/expenses per parcel.** `DomainRevenueCalculator.calculate_monthly_revenue` is
   pure and safe to run in a pre-pass; note that the surrounding `_resolve_domain_month` is NOT
   (it mutates `domain_data["tribute_out_owed"]` and calls
   `FaithMonthlyResolver.apply_pending_consecrate_fields`, a write), so do not re-run the whole
   function to get a revenue total.
2. **Pass 2 — per owner:** sum revenue → one personal-authority lookup → **one morale roll** → mirror
   the result to every parcel, then per-parcel growth/classification/settlements.

**Morale needs a carrier, not a migration.** The character's domain morale is one value, but it is
stored per parcel. Designate the owner's **lowest-`id` parcel** as the carrier of *prior* morale (the
order `PersonalDomain._list_parcels` already returns) and write the resulting value to every parcel,
so each row stays a readable mirror and every existing reader of `domains.morale` keeps working. Do
NOT add `characters.domain_morale` — that widens the change for no gain.

**Cache the union per tick.** `PersonalDomain.for_character` runs ~3 queries; the tick can touch
~1,000 domains. One dictionary keyed by owner id, built once per tick, keeps this proportional to
owners rather than parcels.

Known sites: `DomainStocker.stronghold_min_gp_per_hex` / `.garrison_gp_per_family` /
`.compute_stronghold_value_gp`, `DomainMoraleResolver`, `DomainHandlers._resolve_domain_month` and
its stronghold-sufficiency block, `TributeCalculator` callers, `_compute_tribute_in_for_domain` /
`_tribute_destinations` (D-10 — the seat-partition becomes moot once the parcels are one domain).

**AS BUILT (2026-08-06), one correction to the plan above:** it turned out to be THREE passes, not
two. Pass 0 exists because `PersonalDomain.for_character` re-reads `domains` while `_save_domain` is
writing to it — a union built during pass 1 or 2 would read a half-updated table and answer
differently for each parcel. Pass 0 (group + union) runs before any write; pass 1 (context + revenue)
is the mutating prologue, split out of `_resolve_domain_month` into `_build_month_context` and cached
so pass 2 can never re-run it. `_tribute_destinations` (D-10) is unchanged and still correct — it
partitions the tribute a lord RECEIVES across his seats, which is a different question from the one
Phase B fixed (how many times he PAYS).

### What demotes to DERIVED

- **`domains.liege_domain_id`** — was made authoritative by R-1; under personal allegiance the truth
  is character-to-character, so this becomes a derived **seat pointer**. R-1's work is not wasted (the
  edges and the sweep stand), but the authority ordering flips: `vassal_assignments.liege_character_id`
  is the source of truth.
- **`domains.territory_type`** — a derived summary for display and `ClassificationAdvancement`; no
  longer the basis of RAW math.

### Two-tier rule (mandatory)

**Per-hex math is only available for MATERIALIZED domains.** Only in-window domains have
`domain_hexes` rows at all (`_materialize_domain_hexes` runs solely over the region map), so abstract
off-map domains must keep using the per-domain aggregate. Every per-hex computation needs a
documented aggregate fallback. This is consistent with D-11 ruling 5 (abstract vassals cannot receive
a land grant).

### Consequences for already-built work

- **R-5's cascade must be reworked.** `_cascade_vassals` was scoped to "fiefs held **of** the lost
  domain" — correct under *territorial* allegiance. Under **personal** allegiance the right question
  is *"did the lord lose his domain, or just some hexes?"* His vassals swore to **him**: losing one
  frontier parcel should shake nobody, losing his last hex should shake everyone. That is neither the
  old liege-wide behaviour nor the current per-parcel scoping. Fold this into D-12 rather than leaving
  two models fighting.
- **D-10's seat-partition becomes moot** — once a character's parcels are one domain, "which seat
  receives the tribute" stops being a question. Keep the character-wide inefficiency factor (already
  correct); the per-seat credit collapses into the union.

### Open — still needs Jedidiah's ruling

1. ~~Morale's classification modifier under unification.~~ **RULED 2026-08-05: the WORST
   classification among the character's hexes applies** (Borderlands −1 / Wilderness −2) — the
   ruler's authority is strained by his roughest holding. Marked by Jedidiah as correct **"for the
   time being"**, i.e. deliberately provisional: revisit if a far-flung domain's single worst hex
   proves to punish an otherwise civilized realm too hard.
2. ~~Settlement investment allocation.~~ **RULED 2026-08-05: allocation is PLAYER/AI DIRECTED.** No
   automatic split — the ruler chooses which settlement his investment develops. See "Directed
   investment" below.
3. **Naming drift.** Three names for one concept — `setting_hexes.territory_class` (generation),
   `hex_cells.civilization` (runtime map), `domains.territory_type` (domain aggregate). This is *why*
   the domain layer never joined to the per-hex truth: it does not look like the same field. Normalize,
   or at minimum add a conventions entry.

### GOTCHA — classification advancement would go INERT under per-hex costs

**Nothing updates `hex_cells.civilization` after generation.** The only runtime `UPDATE hex_cells`
statements are `fog_state` (×3) plus the generic dev/override field-setter
(`campaign_repository.gd:4114`). And `ClassificationAdvancement` reads and writes **only**
`domains.territory_type` — it never touches the hexes.

So the moment D-12 moves stronghold minimum and garrison cost onto per-hex `hex_cells.civilization`,
**classification advancement stops affecting them**: a domain that grows Wilderness → Borderlands →
Civilized keeps paying wilderness-rate stronghold minimums forever, because its hexes still say
`wilderness`. This would surface days into the build as "why does advancement do nothing?"

**Required fix, part of D-12:** when `ClassificationAdvancement` advances (or regresses) a domain, it
must **propagate the new classification to that domain's hexes** (`domain_hexes → hex_cells.civilization`).
Domain-level decision, per-hex consequence. *(Recommended; needs Jedidiah's nod — the alternative,
per-hex independent advancement, is a much larger design.)*

### Ordering

**R-7a → D-12 (incl. R-7b) → D-11.**

R-7 **must split**, because its two halves have opposite dependencies:

- **R-7a — PLUMBING. ✅ COMPLETE 2026-08-05.** See the R-7a section below for what shipped and for
  the three decisions not to reverse.
- **R-7b — SCOPE (depends on D-12; land it WITH D-12).** RAW `acore-campaign-hijinks.xml`
  §experience_from_campaigns requires the activity be *personally managed* and says **"No XP is earned
  from domains managed by vassals."** The handoff's own R-7 note says this makes per-personally-owned-domain
  awarding RAW-correct *"once the one-personal-domain invariant is enforced. It is not, and is
  currently unsatisfiable."* **D-12 is what enforces that invariant** — so R-7b cannot be correct
  before D-12, while D-11's income gate needs R-7a. Splitting removes the circularity.

**D-12 is unblocked.** R-7a landed, so `calculate_domain_xp_cp` is called, the units are right, and
domain XP reaches `characters.xp`. **D-12 is the next stage**, and it carries R-7b.

---

### Deferred out of the R-1 wave — read this before R-5

- ~~**Tribute-in is multiplied for a multi-domain ruler.**~~ **FIXED 2026-08-04 — see the ruling below.**
- **The tribute/title path is not LOD-gated** and does full realm-subtree walks per domain. Halved by the double-walk fix and made cheap per-query by migration 215, but still ungated. A naive LOD gate is **NOT safe**: `tribute_out_owed` is persisted while `tribute_in` is recomputed, so skipping backdrop lieges would have backdrop vassals keep paying into nothing and drain the off-camera world. Needs a paired design.
- **`TestContentSeeder` (the Avalon fixture) writes `liege_domain_id` but no `vassal_assignments`** (`test_content_seeder.gd:427`), so the hand-authored world still has the gap the generated world just lost. Left alone deliberately — R-1's ruling is about world generation, and filling it would perturb dozens of unrelated tests.
- **`VassalLoyaltyTriggers`** is a globally-registered EventBus listener with no LOD gate that can mint permanent faction/plot rows on any loyalty roll. The F&D pass is gated, but `_resolve_vassal_tribute_payment` is still per-domain and ungated.
- **`realm_sub_tab.display()`** recomputes the full realm aggregate 3 + 2V times per render, synchronously on the UI thread.

**D-5 is gated on R-4 too** — `DomainStocker.stock_garrison` bails when the domain owner is empty, and it has exactly ONE production caller (`test_content_seeder.gd:153`, the Avalon test campaign). Generated domains have no garrison to mix until the leaf sites land.

### Corrections a reader must apply to the text below

1. **`setting_materializer.gd` has MOVED** from `engine/subsystems/generation/world/` to **`engine/subsystems/generation/materialization/`**, and the four R-4 null-owner sites have drifted to **`:1583, :1846, :2625, :2684`**. Use those, not the line numbers in §R-4.
2. **Migrations 212–215 are taken** (212 tribal-warrior unit loyalty, 213, 214, and **215 `215_domain_owner_index.sql`, added by the R-1 wave**). **Next free is 216 — R-2 P3's gp→cp column sweep must use 216, not the 215 named in §R-2 below.** Do NOT backfill the pre-existing gaps (187, 190, 195–197, 199, 200, 202–205).
3. **D-6 needs amending — see the ⚠ block in "The even split cannot be even".** Its RAW proposition still holds; its "no engine change is needed" claim is now false.
4. Line numbers in the P0 table and elsewhere predate the Tier-0 edits and have shifted by a few lines. The *identities* are correct.
5. Two items in §5 of the garrison analysis are now **fixed** by unrelated sessions: `DomainStocker`'s hardcoded garrison morale 0 (now `TroopBattleRatingTable.base_morale`), and the per-soldier battle-rating overstatements in `solicit_followers` and `tribal_warrior_registry`.

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
| ~~660~~ | ~~`var domain_xp: int = maxi(0, net)` — cp income, never routed through `XPAwardCalculator`, gp threshold never applied~~ | ✅ **FIXED by R-7a 2026-08-05** — `DomainXpResolver` now routes cp income through `calculate_domain_xp_cp` |

~~Also at 662: `int(round(...))` violates the project's banker's-rounding rule (§12)~~ — ✅ **FIXED by R-7a**: that line was the RAW administer-domain +5%, which moved into `DomainXpResolver` and now composes with the prime-requisite adjustment under one banker's rounding (see R-7a decision 1).

### P1–P4 — the rest of the sweep

- **P1** (~9 files, no migration): display-boundary fixes — `status_header.gd:104-109`, `realm_sub_tab.gd:195-203`, `commission_wizard.gd:307-348`, `overview_sub_tab.gd:502-507`, `hiring_panel.gd:159`, `issue_decree.gd:50-56`, `manage_stronghold.gd` (5 sites), `favors_duties_card.gd`. Delete `EquipmentCatalog.format_cost` and redirect its 5 call sites to `Currency.format_cost`.
- **P2** (1 autoload + ~12 emitters/consumers): rename six gp-named EventBus signal parameters; convert `cache_raided(..., value_lost_gp: float)` (`event_bus.gd:432`) to `value_lost_cp: int` — the only float money on a public contract.
- **P3** (migration **216** — 215 was taken by the R-1 wave's `domains(owner_character_id)` index; 11 columns, ~35 files): gp→cp column conversions. Two self-contained islands do most of the work — `factions.treasury_gp` (~8 files) and the magical-research `gp_cost_*` family (~6 files) — plus `domains.tribute_out_owed`, `domain_grants.stronghold_value`, `settlement_entrances.cumulative_investment_gp`, `domain_extraction_ledger.cumulative_extracted_gp_per_family` (REAL→INTEGER), `quest_rewards.gold_value`/`total_gp_value`, `settlement_pois.gp_value`, `settlement_poi_spell_offers.unit_cost_gp`.
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

### R-7a — ✅ COMPLETE 2026-08-05

All four defects closed; the plumbing is live and no longer depends on anything unbuilt. What shipped:

- **`XPAwardCalculator.calculate_domain_xp_cp(net_income_cp, level, is_henchman)`** — the cp-native entry point, and the one production calls. The RAW threshold is converted **UP** to cp so the comparison happens in integer copper; §127 forbids a `cp_to_gp` helper and none was added. The trailing `/ 100.0` is RAW's **gp→XP rate**, not a currency conversion, and the henchman half-rate folds into the same expression so the value rounds exactly once, on `bankers_round`. The gp-native `calculate_domain_xp` is kept as the readable place to pin the RAW table in tests; a test asserts the two agree at exactly 100:1 across four levels, which is the 100× regression lock.
- **NEW `engine/subsystems/characters/xp_award_service.gd`** (`XpAwardService.award(character_id, amount, source_key)`) — the atomic `UPDATE characters SET xp = xp + ?` form, emitting `EventBus.xp_awarded`. The three pre-existing award sites (`CombatFinalizer`, `QuestRegistry._award_xp`, `BattleXpDistributor`) were **left alone** — converting them is a combat/quest change with its own blast radius, not R-7a's. Do that as its own pass.
- **NEW `engine/subsystems/domains/domain_xp_resolver.gd`** (`DomainXpResolver.resolve(domain_data, month_result, calendar_day)`) — threshold → henchman rate → prime-req (RAW L1010) → one-level cap (RAW L1011) → award → auto-level. Called from the `DomainHandlers` domain loop **before** `_save_domain`.
- **Migration 216** `domains.domain_xp_awarded_through_day INTEGER NOT NULL DEFAULT -1` (**not** 215, which R-1 took; **217 is now the next free number, and R-2 P3 should take it**). `_save_domain` writes the guard and `domain_xp_this_month` in one UPDATE. `-1` rather than `0` because day 0 is a legitimate calendar day.
- **`domain_xp_this_month` now holds RAW's figure**, not `maxi(0, net_income_cp)`. Safe to redefine precisely because nothing read it.

**Three decisions a future session must not silently reverse:**

1. **The +5% administer_domain XP bonus is RAW and is KEPT — `rules/ax_campaign_play.xml:511`.** Migration 068's citation (`acore_axioms §administration L499`) is **wrong**: the block it names grants the morale **+1** and defines administration *time*. R-7a's first pass followed that pointer, found nothing, and deleted the bonus as fabricated; Jedidiah supplied the Axioms text and it was restored the same session. **Axioms is the highest-precedence source**, so "not in ACore" proves nothing. The corrected citation now lives in `domain_xp_resolver.gd`'s header — do not re-derive it from migration 068. Conventions **§138** records the general rule: a citation names one location, RAW is a corpus, and removing a player-facing behaviour needs a higher bar than one failed lookup. It composes with the prime-requisite adjustment under **one** banker's rounding via the new `XPAwardCalculator.prime_req_factor()`.
2. **No `ledger_entries` row per award**, contrary to the note this section used to carry. That table's `cp_amount` is money with a CHECK-constrained category list; writing XP into it violates §127's unit contract and would corrupt any treasury audit that sums the ledger. `EventBus.xp_awarded` → `GameLog._on_xp_awarded` is the existing, honest audit surface and it already fires.
3. **`persistence_tier='named'` ruler stubs BANK the XP without levelling.** `apply_level_up_auto` auto-selects and persists proficiency, power and spell rows — for every backdrop domain in the world that is exactly the eager cost D-8 rejected, and it half-promotes the stub behind the promotion engine's back. Stubs accrue `characters.xp` (one integer) and advance once the play window promotes them to `'full'`. This still delivers D-4: a rival the player can *see* is by definition active-LOD, hence `'full'`, hence levelling. **Open gap:** nothing yet reconciles banked XP into levels at promotion time — a stub promoted after two years of income arrives at its old level with a large XP balance. That belongs with the lazy-rich half of R-4.

**Still open (R-7b, ships with D-12):** the RAW scope rule below.

### R-7b — SCOPE (blocked on D-12)

**Tribute is already inside the formula.** `net_income = revenue.total − expenses.total`, revenue already includes `tribute_in` and expenses already include `tribute_out`. R-7 needs **no formula change**.

**RAW constraints** (`acore-campaign-hijinks.xml` §experience_from_campaigns — the operative section, threshold table matches `GP_THRESHOLD_TABLE` exactly):
- "To earn XP, the activity must be **personally managed** by the character" / "**No XP is earned from domains managed by vassals**" — which makes per-personally-owned-domain awarding RAW-correct *once the one-personal-domain invariant is enforced*. It is not, and is currently unsatisfiable.
- "A character can never earn enough campaign XP in one month to **advance 2 or more levels**."
- Prime-requisite XP bonuses apply as for adventuring XP.
- "A follower or henchman **managing a domain** earns 50% of normal domain XP" — this is a per-manager **rate**, not a share of one pot. So `is_henchman` **stays**, redefined as `characters.character_type == 'henchman'` for the domain's owner. It must never become a distribution key.
- **Two carve-outs not yet modelled:** scutage receipts must be *excluded* from the XP base (`acore_axioms:362`) but are not modelled as revenue at all; a Gift must increase the recipient's and decrease the grantor's XP base (`acore_axioms:368`) but `FavorsDutiesResolver` moves only treasuries.

**Award path:** ✅ `XpAwardService.award(character_id, amount, source_key)` shipped in R-7a. The three legacy sites (`BattleXpDistributor._credit_character`, `QuestRegistry._award_xp`, `CombatFinalizer`) still roll their own six lines and are a separate conversion pass. Level-up is a **notification** for PCs (they advance interactively via `LevelUpEngine.begin_interactive_level_up`; the resolver reports `pending_level_up`) and an **automatic apply** for non-PCs per D-4.

**Double-award guard:** ✅ shipped in R-7a as migration **216**. The `ledger_entries` audit row was deliberately NOT added — see R-7a decision 2 above.

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

> ### ⚠ AMENDED 2026-08-03 — the "no engine change needed" claim is now FALSE
>
> The paragraph below was true when written. Convention **§133** ("Peasants under arms are a standing domain cost, not a free action", Jedidiah 2026-08-03) has since landed and made the militia slice unbuildable as specified.
>
> **The conflict, verified at HEAD.** `LevyPenaltyCalculator.levied_peasants_for_domain` (`levy_penalty_calculator.gd:113-127`) charges the levy penalty from a LIVE query that filters only on `assigned_domain_id`, `status='active'` and `source_type` — **no `assignment_kind`, no `is_trained`, no called-up flag.** Meanwhile `GarrisonExpenditureCalculator` credits `unpaid_value_cp` only when the row is `status='active'` AND `assignment_kind='garrison'` AND `monthly_cost_cp == 0`. Those two conditions are **mutually exclusive by construction**: to earn the RAW §230 garrison credit a militia row must be active-and-garrisoned, and *any* active militia row is charged the §133 penalty (−1 family of revenue each, −1/−2 base morale, fed live into `DomainRevenueCalculator` and `DomainMoraleResolver`). **There is no way to represent "trained, equipped, sent home."** Confirmed: no `is_called_up` / `is_sent_home` column exists anywhere.
>
> So a D-5 stocker minting the militia third of a 780-family civilized domain (~87 trained LI) would, on the first monthly tick, permanently cost 87 families of revenue and −1 base morale — exactly the trap this section already flagged, but which the engine now actually implements.
>
> **D-6's RAW reading survives** (RAW §230 and the §133 basis are consistent — a sent-home militiaman is legally both garrison value and penalty-free). **D-6's engineering corollary does not.** Two honest options for whoever builds D-5:
> 1. **Build the flag as part of D-5** — add `troop_units.is_called_up INTEGER NOT NULL DEFAULT 1 CHECK(is_called_up IN (0,1))` (a cheap ALTER, mirroring what migration 213 did for `is_excess_levy`), add `AND is_called_up = 1` to the levy-penalty query, and additionally gate the `unpaid_value_cp` branch on `is_trained = 1` (RAW §230 says "trained *and equipped*"; the calculator credits any cost-0 unit today). Widening `assignment_kind` instead is the expensive route — its CHECK (`db/schema.sql:1880`) would need a `legacy_alter_table` rebuild, and per §130 any mirroring constant then owes a set-equality test.
> 2. **Drop the militia slice** and let conscripts + mercenaries carry the split. Conscripts are NOT counted by §133 at all — the penalty query covers militia and excess-levy tribal warriors only, matching RAW's placement of `daw:429-431` inside the militia section.
>
> **Also stale in this section:** the recorded consequence "a generated NPC domain's actual monthly cash bill is ~two-thirds of its nominal garrison figure" assumes generated domains have garrisons. They do not — `DomainStocker` has exactly ONE production caller (`test_content_seeder.gd:153`, the Avalon test campaign), nothing under `generation/` mints a `troop_units` row, and `stock_garrison` bails at `domain_stocker.gd:235` when the owner is empty. **D-5 is therefore gated on R-4 too.**

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
