# Setting-gen → Runtime-Handoff: contract deltas since M2a

**Purpose:** Hand-off note for the setting→runtime *materialization* build session. The setting generator's output contract shifted substantially **after** materialization Phase M2a landed (2026-06-16). The realms/titles refactor (Phases 1–5) and the §7.4e consolidation all landed **after** M2a, so the handoff was built against a now-stale world model. This note lists the changed files + contracts so M2b can reground.

**Status:** written 2026-06-18. Controlling gen-side doc: `generation/gdd-realms-titles-refactor.md` §7. Materialization plan: `generation/gdd-setting-runtime-materialization.md` + the `project-setting-runtime-materialization` memory.

---

**TL;DR:** M2a was built against the pre-refactor world. Since then the generator gained a **new `setting_domains` table** (a complete, per-hex feudal vassal ladder), changed what `setting_polities.tier_index` *means*, and now produces **far fewer, larger realms**. The headline for M2b: **consume `setting_domains` instead of inventing the sub-realm hierarchy.** Plus three firm Jedidiah rulings in **§6**: take realm size/tier/title from the sim verbatim; conserve population through the 24→6-mile zoom (children sum to the parent hex); and instantiate orphaned populated land as persistent independent **pocket realms** at the handoff.

## What the materializer reads today (M0/M1/M2a)
`setting_materializer.gd` reads `list_settlements` / `list_hexes` / `list_river_edges` / `list_roads` / `list_polities`. M1 makes **one abstracted domain per polity** (no location), realms = sovereigns (`realm_kind='foreign'`), and `ruler_title_for(p.title)` translates the domain title → ruler title. It does **not** read `setting_domains` (it didn't exist). M2b was planned to "invent located domains + domain_hexes."

## 1. NEW: `setting_domains` (migration 170) — the big one
A deterministic, finalization-built **intra-polity vassal ladder** (Empire→Kingdom→…→Barony). Every alive **civ** polity decomposes its own crownland; beastman/clan polities have **no rows**. Read via `SettingRepository.list_domains(campaign_id)`.

Columns: `id, campaign_id, polity_id, liege_domain_id, tier_index, title, ruler_class, ruler_level, ruler_name, realm_name, seat_q, seat_r, families, hex_count, depth, is_personal_domain`.

Contract for the handoff:
- `polity_id` → the owning polity (the runtime realm it belongs to). `liege_domain_id` → parent domain within that polity; **`''` = directly under the polity ruler** (who lives in `setting_polities`).
- `seat_q/seat_r` → the domain's **24-mile hex** (its ruler's seat). `is_personal_domain=1` = a **leaf** (a real per-hex fief); `=0` = a **synthesized interior node** (Duke/Count grouping; `families`/`hex_count` are *subtree aggregates*, not its own single hex).
- **Leaf seats tile every populated hex.** So the handoff maps `24-mi hex → leaf domain → liege chain → polity → sovereign`, and derives how many **6-mile sub-fiefs to invent** per leaf from its tier (a County leaf ⇒ ~4–6 Marches × 4–6 Baronies of 6-mile sub-hexes).
- `tier_index`/`title` are **domain** titles (Barony…Empire) — reuse `SettingMaterializer.ruler_title_for()` to get the ruler title (Baron…Emperor) for tribute keying. `ruler_class`/`ruler_level`/`ruler_name` are pre-rolled — **honor them** (build via `ClassedNpcBuilder`, don't re-roll), same as M1.
- The hierarchy is **complete by design** (Barons under Marquis under Counts, mostly; some skip-level / over-sizing is intentional and RAW-legal — room for a player to become the missing Count) — the handoff **fills sub-hex detail, never reorganizes or invents the middle tiers.**

**Regrounding impact:** M1's "one abstracted domain per polity" is superseded — the per-polity domain *tree* now comes from `setting_domains`. The dead `setting_polities.internal_vassals` JSON blob is **abandoned** (still written; ignore it).

## 2. `setting_polities` — semantics changed (Option C, 2026-06-17)
- `tier_index` is now the **overall-realm / export tier** = max(own + transitive war-vassal family tier, structural +1-per-ruled-realm, high-water floor) — **not** own-territory tier. A Prince ruling vassal princes reads as King/Emperor even with small own families. `title` derives from it. (`ruler_title_for` translation still works; the values are just Option-C-correct now.)
- **Tier is a floor** — never demoted by population loss alone.
- `liege_id` now also covers **peaceful protectorates** (not just war conquest); `vassalized_by_war` (0/1) distinguishes them.
- **Rumped fallen realms** (2026-06-18 collapse softening): a large sovereign that catastrophically collapses now contracts to its heartland (a "deep rump") and **survives** rather than vanishing. So expect **Principality+/high-tier realms sitting on a tiny territory** with a correspondingly small `setting_domains` tree — title/tier is decoupled from territory size. Size the runtime realm from the actual hexes/domains, not from the title.

## 3. `setting_hexes` — two "no-domain" hex categories
The handoff must NOT assume *populated ⇒ owned ⇒ has-a-domain*. Two kinds of hex carry no `setting_domains` row:
- **Titular wilderness** — `owner_polity_id` set, **pop-0**, wilderness-class. Owned reach, no ruler/tax. Attach to the nearest populated domain at materialization (the "fill the blanks" step). Don't expect a domain for every *owned* hex.
- **Orphaned populated land** — `owner_polity_id == ''` but **`population_band > 0`** (collapse/depopulation remnants: a fallen realm's hexes keep up to the wilderness cap of population). These belong to **no polity and no domain** in the sim output. **Do NOT wipe or silently absorb them** — per the 2026-06-18 ruling (§6c) the handoff instantiates each as an **independent sovereign "pocket polity / point of light"** (sized by its family count, given a ruler) and persists it. Don't expect every *populated* hex to already map to a ruler in the sim output; the handoff is the backstop that supplies one. (On the large review seed: ~52, small/scattered — the rump-only collapse change stopped large realms vanishing into big voids, so these are minor remnants of *smaller* realms' depopulations, not continent-sized holes.)

## 4. Fewer, larger realms (§7.4e consolidation, 2026-06-17)
Polity counts dropped dramatically (e.g. large map ~401 → ~24). M2a's "materialize as many sovereigns as perf tolerates / fall back to a consolidation pass" worry is largely moot — the world is already consolidated.

## 5. New params/events (mostly NOT handoff-consumed)
- **`SettingParameters.vassal_consolidation`** (float, default 1.0) — varies `setting_domains` granularity (more thin vs fewer fat mid-tiers). Handoff just consumes whatever rows exist; no special handling.
- New `setting_events` types `protectorate` (mig 169) + `cultural_shift` (mig 163) — these feed the **Review replay only**; not part of the runtime materialization contract.
- Review-screen + political-map-border changes (this session) are **gen-side display only** — no handoff impact.

## 6. Sizing & population transfer + pocket realms (Jedidiah rulings, 2026-06-18)
Three firm requirements for M2b:

**6a — Size, tier, and title come from the SIM, not re-derivation.** A runtime realm's/domain's tier, ruler title, and size are whatever the sim wrote (`setting_polities` + `setting_domains`: `tier_index` / `title` / `families` / `hex_count`, plus the pre-rolled `ruler_class` / `ruler_level`). Do **not** re-tier from runtime population, re-roll titles, or resize realms — transfer the sim's numbers verbatim. (A rumped fallen Principality on a tiny heartland keeps its Principality title — §2.)

**6b — Population transfers and is CONSERVED through the 24→6-mile zoom.** Each 24-mile parent hex's `population_band` (the sim-end family count) is distributed across its 16 six-mile children when the parent is zoomed in. The per-child split MAY be randomized (deterministically, via the zoom-in's `WorldGenRng` stream), but the 16 children's populations **MUST SUM to the parent hex's total** — no population is created or lost in subdivision. (The 24-mile family caps are exactly 16× the 6-mile caps — civ 12,480 = 16×780 — so a full parent distributes to ≈cap-per-child; partial parents distribute proportionally, under cap.) This is a `gdd-region-zoom-in.md` / `RegionZoomIn` requirement.

**6c — Orphaned populated land → independent POCKET realms (persist them).** The unowned-but-populated remnants (§3) become **appropriately-sized independent sovereign realms** in the runtime — "pocket polities / points of light," desirable play encounters. Cluster adjacent same-culture orphan hexes into one pocket; size its tier by the cluster's total families (Barony…County, the per-hex floor); assign a culture-appropriate ruler; **persist it**. The handoff is the backstop: if the sim's consolidation/cleanup left them orphaned, the handoff gives them a ruler — never leave them rulerless and never delete them. (Eager for the start region; lazy/on-encounter beyond, per the M2a eager-coarse/lazy-fine decision. This lives at the **handoff, not the sim**, on purpose: instantiating a pocket at runtime is cheap — a realm + domain + a ruler character — whereas doing it in the sim blew up Layer-6 settlement/road generation. See `gdd-realms-titles-refactor.md` §7 / build_log 2026-06-18.)

## Changed / new files (producer side)
- **New:** `db/migrations/170_setting_domains.sql`; `db/schema.sql` (+`setting_domains`).
- **`engine/subsystems/generation/world/history_simulator.gd`** — Phases 1–5: tier-floor ratchet, war re-parenting, coagulation/protectorate, titular-wilderness claim, and `_decompose_all` / `_split_realm` / `_emit_leaf` / `_cluster_for_tier` (the ladder → `ctx["sim_domains"]`). Plus the 2026-06-18 collapse softening (`_do_rump` deep-rump for large sovereigns; `SimConstants.collapse_catastrophic_shed`) — affects which realms survive/shrink, not the output schema.
- **`engine/subsystems/generation/world/setting_repository.gd`** — `DOMAIN_COLUMNS`, `save_domains` / `list_domains`, `_DATA_TABLES` / `_SIM_OUTPUT_TABLES`.
- **`engine/subsystems/generation/world/setting_generator.gd`** — saves domains in both orchestrator passes.
- **`engine/subsystems/generation/world/name_generator.gd`** — names domains (Layer 5: `ruler_name` + `realm_name`).
- **`engine/subsystems/generation/world/setting_parameters.gd`** — `vassal_consolidation` field.
- **`engine/autoloads/campaign_repository.gd`** — `setting_domains` in `_SCOPE_DIRECT_CAMPAIGN`.

## Suggested M2b regrounding sequence
1. Read `setting_domains` (+ keep reading `setting_polities` for the realm/war-vassalage layer + `setting_hexes` for terrain/ownership/population).
2. Replace M1's one-abstracted-domain-per-polity with the **per-polity domain tree** from `setting_domains` (leaves + interior nodes), wiring `liege_domain_id` (and `''`→polity ruler) into the runtime domain hierarchy; backfill `realm_id` via the polity's liege chain to the sovereign (as M1 already does at the polity level).
3. For domains whose `seat_q/seat_r` falls in the 6-mile start window: located domains + `domain_hexes`; promote `realm_kind`→`tracked`. Out of window: abstracted (append-located on frontier growth).
4. Per leaf domain in-window: invent the 6-mile Barony/March sub-fiefs from its tier (per `gdd-region-zoom-in.md`). **Transfer the sim's tier/title/size verbatim (§6a), and distribute each parent hex's `population_band` across its 16 children so they sum to the parent total (§6b).**
5. No-domain hexes (§3): **titular wilderness** (owned, pop-0) → attach to the nearest populated domain; **orphaned populated land** (unowned, pop>0 — collapse remnants) → **instantiate as an independent pocket realm (§6c), sized by family count + given a ruler, and persist it** (do not wipe or absorb).
6. Beastman/clan polities have no `setting_domains` rows — keep the M1 flat-clanhold + `BeastmanRulerMaterializer` + `available_tribal_warriors` path unchanged.
