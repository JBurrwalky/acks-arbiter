# Setting-gen → Runtime-Handoff: contract deltas since M2a

**Purpose:** Hand-off note for the setting→runtime *materialization* build session. The setting generator's output contract shifted substantially **after** materialization Phase M2a landed (2026-06-16). The realms/titles refactor (Phases 1–5) and the §7.4e consolidation all landed **after** M2a, so the handoff was built against a now-stale world model. This note lists the changed files + contracts so M2b can reground.

**Status:** written 2026-06-18. Controlling gen-side doc: `generation/gdd-realms-titles-refactor.md` §7. Materialization plan: `generation/gdd-setting-runtime-materialization.md` + the `project-setting-runtime-materialization` memory.

---

**TL;DR:** M2a was built against the pre-refactor world. Since then the generator gained a **new `setting_domains` table** (a complete, per-hex feudal vassal ladder), changed what `setting_polities.tier_index` *means*, and now produces **far fewer, larger realms**. The headline for M2b: **consume `setting_domains` instead of inventing the sub-realm hierarchy.**

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

## 3. `setting_hexes` — titular wilderness
A hex can be **owned (`owner_polity_id` set) but pop-0 and wilderness-class**, with **no `setting_domains` row**. Treat as titular reach (no ruler, no tax) — **attach to the nearest populated domain** at materialization (the M2b "fill the blanks" step). Don't expect a domain for every owned hex.

## 4. Fewer, larger realms (§7.4e consolidation, 2026-06-17)
Polity counts dropped dramatically (e.g. large map ~401 → ~24). M2a's "materialize as many sovereigns as perf tolerates / fall back to a consolidation pass" worry is largely moot — the world is already consolidated.

## 5. New params/events (mostly NOT handoff-consumed)
- **`SettingParameters.vassal_consolidation`** (float, default 1.0) — varies `setting_domains` granularity (more thin vs fewer fat mid-tiers). Handoff just consumes whatever rows exist; no special handling.
- New `setting_events` types `protectorate` (mig 169) + `cultural_shift` (mig 163) — these feed the **Review replay only**; not part of the runtime materialization contract.
- Review-screen + political-map-border changes (this session) are **gen-side display only** — no handoff impact.

## Changed / new files (producer side)
- **New:** `db/migrations/170_setting_domains.sql`; `db/schema.sql` (+`setting_domains`).
- **`engine/subsystems/generation/world/history_simulator.gd`** — Phases 1–5: tier-floor ratchet, war re-parenting, coagulation/protectorate, titular-wilderness claim, and `_decompose_all` / `_split_realm` / `_emit_leaf` / `_cluster_for_tier` (the ladder → `ctx["sim_domains"]`).
- **`engine/subsystems/generation/world/setting_repository.gd`** — `DOMAIN_COLUMNS`, `save_domains` / `list_domains`, `_DATA_TABLES` / `_SIM_OUTPUT_TABLES`.
- **`engine/subsystems/generation/world/setting_generator.gd`** — saves domains in both orchestrator passes.
- **`engine/subsystems/generation/world/name_generator.gd`** — names domains (Layer 5: `ruler_name` + `realm_name`).
- **`engine/subsystems/generation/world/setting_parameters.gd`** — `vassal_consolidation` field.
- **`engine/autoloads/campaign_repository.gd`** — `setting_domains` in `_SCOPE_DIRECT_CAMPAIGN`.

## Suggested M2b regrounding sequence
1. Read `setting_domains` (+ keep reading `setting_polities` for the realm/war-vassalage layer + `setting_hexes` for terrain/ownership/population).
2. Replace M1's one-abstracted-domain-per-polity with the **per-polity domain tree** from `setting_domains` (leaves + interior nodes), wiring `liege_domain_id` (and `''`→polity ruler) into the runtime domain hierarchy; backfill `realm_id` via the polity's liege chain to the sovereign (as M1 already does at the polity level).
3. For domains whose `seat_q/seat_r` falls in the 6-mile start window: located domains + `domain_hexes`; promote `realm_kind`→`tracked`. Out of window: abstracted (append-located on frontier growth).
4. Per leaf domain in-window: invent the 6-mile Barony/March sub-fiefs from its tier (per `gdd-region-zoom-in.md`).
5. Titular wilderness (owned, pop-0, no domain): attach to the nearest populated domain.
6. Beastman/clan polities have no `setting_domains` rows — keep the M1 flat-clanhold + `BeastmanRulerMaterializer` + `available_tribal_warriors` path unchanged.
