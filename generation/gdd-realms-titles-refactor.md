# GDD — Realms / Titles / Vassalage / Wars Rebase + Replay & Event-Log Enrichment

**Status:** PLAN (approved direction 2026-06-18; phased execution, approval gates on the deep phases).
**Authority:** PROJECT-DESIGNED refactor plan. Controls a refactor that spans three existing GDDs — it does **not** override their §ACKS-Constraints blocks. Amends, in order of impact: `gdd-history-simulation.md` (the sim), `gdd-campaign-creation-ui.md` (Review/replay UI), `gdd-setting-runtime-materialization.md` (handoff). The RAW tier/title/stronghold numbers in `DomainTierTable` are SACRED (XML wins); this refactor changes how they are *used*, never their values.

---

## 0. Why

Two independent problems, both rooted in the Layer-4 history simulator (`engine/subsystems/generation/world/history_simulator.gd`):

1. **Replay & event log are too coarse.** The replay captures 1 frame / 4 ticks (`replay_cadence = 4`), so the history watch jumps in 100-year steps (4 ticks × 25 yr) though ticks are 25 yr. The event log surfaces a flat prose timeline of top-significance events; it does not let the player read **wars (who won/lost/when)** or **rebellions (when/outcome)** clearly, cannot be filtered **per sovereign**, and cannot be **exported**.

2. **The titles/realms/vassalage system lacks a unifying foundation.** Today a realm is a monolithic flat hex-blob with a single ruler; sub-realms (Counties/Baronies) exist only as an anonymous, **write-only-never-read** geometric `internal_vassals` JSON blob; the materializer builds one domain per polity, a ruler only for sovereigns, and **no seat hex for anyone**. The §7.4e "Duchy floor" (which fixed a 575-polity fragmentation explosion) erased the lower titles entirely.

**The unifying foundation = peasant-family count.** RAW makes title a shorthand for (1) tribute, (2) levy, (3) social standing, (4) vassal count — all derived from realm family count. `setting_hexes.population_band` already stores the raw family count per hex, so the rebase is mostly *using* a number we already have.

---

## 1. ACKS Constraints (SACRED — RAW, do not alter)

**Tier ladder & family thresholds** — `DomainTierTable.TIERS`, sourced from `acore_axioms_strongholds_and_domains.xml:276-284` (titles_of_nobility). Realm-type names (March/County/…) ↔ ruler titles (Marquis/Count/…):

| tier | realm type | ruler | overall-realm families (lower) | ruler level | 24-mi hexes (RAW) |
|---|---|---|---|---|---|
| 0 | Barony | Baron | 160 | 4 | <1 |
| 1 | March | Marquis | 960 | 6 | <1 |
| 2 | County | Count | 4,600 | 8 | 1–2 |
| 3 | Duchy | Duke | 20,000 | 9 | 4–11 |
| 4 | Principality | Prince | 87,000 | 11 | 18–65 |
| 5 | Kingdom | King | 364,000 | 13 | 71–391 |
| 6 | Empire | Emperor | 2,000,000 | 14 | 286+ |

- **Per-hex family caps** (`acore_axioms…:156-161`, project `cap_for`): Wilderness 125 / Borderlands 250 / Civilized 780 per **6-mi** hex → ×16 = **2,000 / 4,000 / 12,480 per 24-mi hex**. ⇒ a single 24-mi civilized hex maxes at 12,480 families = **County** (cannot reach Duchy alone). **County ≈ "one hex"** is therefore the natural per-hex title.
- **Political divisions** (`acore-setting-construction-rules.xml:90-110`): each realm contains **4–6 of the next tier down** (Empire→4-6 Kingdoms→…→4-6 Marches→4-6 Baronies). This is the decomposition spine.
- **Personal domain** (`acore_axioms…:266-269`): "A ruler may only directly manage **one** domain (the personal domain); every other domain must be assigned to a vassal." Canonical personal-domain families by title: Baron 160 / Marquis 320 / Count 780 / Duke 1,500 / Prince 7,500 / King & Emperor 12,500.
- **Tribute** (`acore_axioms…:299`): `tribute_gp/mo = 18 × realm_families^0.6` (diminishing returns built in). Tribute inefficiency by # direct vassals (`:398-409`): ≤8 = 100%, 9–16 = 66%, 17–36 = 50%, …
- **Levy** (`ax_campaign_play.xml:540,616`; `daw_armies_recruitment.xml:315`): conscripts 1/10 families, militia 2/10 families; garrison floor 2gp/family (3 borderlands, 4 wilderness); **standing army ≈ realm_families / 10**.
- **Net income/family** (`acore_axioms…:259-261`): Wilderness ~5 / Borderlands ~6 / Civilized ~7 gp/family.
- Term note: ACKS uses **"personal domain,"** never "demesne." Bottom-tier family count is double-valued in RAW (Baron 160 point vs 120–200 range); **use 160** (matches `DomainTierTable` + the per-family math).

---

## 2. Core architecture — the unlock

**The simulation keeps running at the sovereign + war-vassal scale** (cheap, calibrated, non-fragmenting — preserves the §7.4e fix). **The full per-hex vassal tree is built as a deterministic *finalization* step**, not during the tick loop. The sim's war/collapse/expansion dynamics never see Counties; the present-day output does.

This separates the work cleanly:
- **Sim-tick changes** (small/medium): tier-floor ratchet (E), softer collapse + sovereign-tier-1 shatter (G), war re-parenting + tier-disparity gradient (F), wilderness claiming + auto-coagulation (H + the Q3 mechanic).
- **Finalization decomposition** (additive, low sim-risk): recursively partition each sovereign's territory into the RAW 4–6 hierarchy down to per-hex County/March/Barony, each with a seat hex + ruler + title (A/B/C). Persisted to a **new `setting_domains` table**, read by the Review vassalage tree now; runtime materialization deferred to M2b (per Q2 answer).
- **UI changes**: Realms tab = sovereigns only; Vassalage tab = collapsible per-liege tree, default all collapsed (D); History tab = structured per-sovereign filterable log + markdown export (#1).

---

## 3. Per-requirement design

### A/C — Every realm composed of lesser vassals accounting for all families
Finalization step `_decompose_realm(sovereign)`:
1. Sovereign's ruler keeps a **personal domain** = the capital hex (+ up to RAW personal-domain-families worth of adjacent hexes, capped by `core_max`). (B)
2. Remaining hexes partitioned into **4–6 contiguous vassal groups of tier (sovereign_tier − 1)**, each sized toward the upper end of that tier's RAW family range (E: prefer fewer oversized). Recurse on each group, down to per-hex leaves whose title = `tier_for_families(hex_families)` (Barony/March/County; one hex maxes at County).
3. Below County (March/Barony sub-hex) is **deferred to the 6-mile handoff** (a county hex → 4-6 marches at 6-mi). At 24-mi the decomposition floor is County.
4. Deterministic (WorldGenRng stream `decompose`), contiguous (BFS partition reusing `_partition_contiguous`).

### B — Every ruler in the tree owns ≥1 seat hex
Each decomposition node records `seat_q, seat_r` (its personal-domain anchor hex). Persisted on `setting_domains`. (Runtime seat wiring deferred to M2b per Q2; the data is present at handoff so M2b can pick specific 6-mile child hexes.)

### D — Tidy UI
- **Realms tab**: filter `setting_polities` to sovereigns (`liege_id == ''`).
- **Vassalage tab**: collapsible tree from `setting_domains`, **default all collapsed** — expanding an Emperor shows Kings, expanding a King shows Princes, etc.

### E — Tier is a floor, not a yo-yo
- `setting_polities.tier_floor` (new) ratchets to the highest tier the realm ever reached. `_realm_tier` / title / ruler_level read `max(computed_tier, tier_floor)`. Floor only resets on **total depopulation** (realm death). Gives narrative/quest hooks ("a fallen kingdom clinging to a single county").
- Partition heuristic biases toward filling a vassal to the top of its family band before spawning another (fewer oversized > more undersized).

### F — Wars preserve & re-parent the vassal hierarchy (sovereign-scale)
Rewrite the war-resolution effects (`_annex` / `_resolve_crushing` / `_resolve_decisive`):
- **Annex no longer frees the loser's vassals** — they re-parent to the victor (their `liege_id` → victor, or → a duke within the victor's realm), keeping intact sub-trees ("Duke John's Counts come with him").
- **Orphaned non-contiguous vassals** (a vassal cut off from its new liege by intervening enemy land) re-home to the nearest same-sovereign liege of appropriate tier within reach.
- **Gradient vassalization weighted by tier disparity** (NEW term — none exists today): easier for a higher-tier sovereign to vassalize/annex a lower-tier neighbor; total vassalization of a whole sovereign scales in difficulty with the target's tier **and** the tier gap. Empire-grabs-Barony easy; sovereign-Barony-grabs-Empire near-impossible. Bias outcomes toward **transferring swathes of vassal-realms (liege_id transfer) or annexing border counties** rather than absorbing whole sovereigns — so borders shove back and forth, with occasional Alexandrian total victories that are *possible but not automatic*.

### G — Soften collapse & shattering
- **Depopulation −20% harsher→milder**: `depopulate_pop_keep 0.10 → 0.28` (loss 90% → 72%). [Interpretation flagged for confirm.] Rump unchanged (already keeps 0.5).
- **Shatter only at sovereign tier-1**: shatter gate becomes `liege_id == '' AND tier ≥ Principality`; produces successors at exactly `tier − 1` (Empire→Kingdoms, Kingdom→Principalities). Sub-Principality realms rump/depopulate instead of shattering. (Today shatters as low as County-with-vassals into 2–6 arbitrary pieces.)

### H — Claim wilderness in borders; anchor on stranded pops; soften same-culture migration
- A realm may claim contiguous **empty wilderness enclosed within / adjacent to its bounded territory** (no tax revenue — purely titular reach, like Imperial Siberia). Gated so not every wilderness hex flips to its biggest neighbor: claim only wilderness that is enclosed or anchored by a **stranded same-culture population**.
- Stranded same-culture pockets become **anchor points** that soften (slow / reduce) the forced migration of non-contiguous same-culture populations.

### Q3 mechanic — Peaceful auto-coagulation (replaces silent consolidation) — IMPLEMENTED (Phase 3a)
Folded into `_consolidate_civ`, **distance-gated, event-emitting**:
- A **sub-Duchy sovereign** S looks within `coagulation_reach_base(2) + S.realm_tier` hexes (Barony 2 / March 3 / County 4) for the best acceptable realm T.
- **Validity** for T: within reach, OUTRANKS S, not beastman, **same civ-type** (civilized↔civilized / clanhold↔clanhold), and **not opposed alignment** (law & chaos refuse protection from each other; neutral seeks/accepts both), no liege cycle.
- **Preference (lexicographic, fragmentation-limiting fallback):** same-culture > same-alignment > same-civ-type > closest > largest realm > lowest id. So same-culture kin win, but if none is in reach S falls back to any same-civ-type non-opposed neighbour (limits fragmentation) rather than staying a lone fragment.
- If found, S **peacefully joins T as a vassal** (`liege_id = T`, `vassalized_by_war = 0`); raises T's realm tier. Emits **`protectorate`** (significance 0.45, migration 169): *"X signed a treaty of protection with Y, joining their realms."*
- With **no acceptable target in reach** S SURVIVES as a viable low-tier sovereign (an enclave). Keeps the Duchy-level seed points; brings the low titles back to the map without the 575-polity explosion (calibration smoke: ~15 realms, ~6.7 independent, ~2.3 empires-with-vassals).

### #1a — Every-tick replay
`replay_cadence: 4 → 1` (`sim_constants.gd:327`). ~4× frames (standard 41 → 161; <1 MB even on huge/deep). The 100-yr jump disappears automatically (each frame = 25 yr). Link `screen_generate_replay._YEARS_PER_TICK` to `SimConstants.tick_years` (kill the unlinked duplicate).

### #1b — Wars & rebellions in the event log, per-sovereign, exportable
- **Wars**: already emit a `war` event ([attacker, defender], margin in `severity`) but `summary_key` is always `"war.declared"`. Enrich `_resolve_war` to set `summary_key` to the resolved outcome band (`war.defender_held` / `war.border` / `war.decisive` / `war.crushing`), so winner/loser is unambiguous (winner = attacker unless defender_held). The existing downstream `conquest`/`vassalage`/`pillage`/`razing` events carry the territorial result. **No migration** (no new type, `severity` already carries margin).
- **Rebellions**: already fully outcome-typed (`rebellion` / `_won` / `_concession` / `_crushed` / `_extinguished`). No sim change.
- **Founding** (optional): `founding` is in the CHECK enum but never emitted — emit it at the 4 polity-creation points so the log shows realm births. No migration.
- **Per-sovereign grouping** is done in the UI by resolving each event's `polity_ids` → sovereign via the liege map already passed to the screen (`set_polity_meta`). An event belongs to every involved sovereign's log. No schema column needed for v1.
- **History tab rework** (Review screen): replace/augment the flat prose timeline with a structured, scrollable event log — a **sovereign filter** (dropdown: "All realms" + each sovereign) + a **master log**, each row `~Nyr ago — <sentence>`. A **⧉ Export to Markdown** button copies the currently-viewed (filtered) log to the clipboard as markdown.

---

## 4. Phasing (replay/log first, per approval)

- **Phase 1 — Replay & event log** (contained, low-risk, high-value):
  - P1a: `replay_cadence → 1`; link `_YEARS_PER_TICK`.
  - P1b: enrich `war` `summary_key` with outcome band; (optional) emit `founding`.
  - P1c: History-tab rework — per-sovereign filter + master log + markdown export. **godot-ai MCP verified.**
- **Phase 2 — Sim tuning** (E + G): tier-floor ratchet; depopulation −20%; shatter-only-at-sovereign-tier-1.
- **Phase 3 — Sim social/territorial** (H + Q3): wilderness claiming + stranded-pop anchors; peaceful auto-coagulation (`protectorate` event → migration 169 for the new type).
- **Phase 4 — War re-parenting** (F): annex re-parents vassals; tier-disparity gradient; orphan re-homing. (Deepest sim change; approval gate.)
- **Phase 5 — Finalization decomposition + UI** (A/B/C/D) — **IMPLEMENTED 2026-06-18**: `_decompose_all` → new `setting_domains` table (+ repo + `_SCOPE_DIRECT_CAMPAIGN`/`_DATA_TABLES`/`_SIM_OUTPUT_TABLES` registration); Review Vassalage tab → collapsible `Tree` from `setting_domains`; Realms tab → sovereigns only. Runtime materialization of seats deferred to M2b. See §7 for the as-built record.

Each phase: focused build → `--check-only` on touched scene scripts → `tools/run_tests.ps1` (baseline 461/17 net-zero, measured run 2) → MCP visual verify for UI → build_log entry.

---

## 5. Risks & guardrails
- **Determinism spine**: every sim change must keep `SettingDatasetHasher` byte-identical for same-seed and route all RNG through `WorldGenRng` (no `hash()`, no unsorted Dict iteration). New streams: `decompose`, `coagulate`. The rectangle refactor already means old seeds won't reproduce historic worlds — acceptable.
- **Phase-order is load-bearing** (expansion/war/migration before stability/collapse; substrate diffusion after political change). New phases (coagulation) slot deliberately.
- **New event type** (`protectorate`, Phase 3) = a CHECK-rebuild migration (169+) following the 161/162/163 pattern; `setting_events` has an outbound FK to `campaigns` — verify `PRAGMA foreign_key_check` after rebuild.
- **New `setting_domains` table** (Phase 5) must join `CampaignRepository._SCOPE_DIRECT_CAMPAIGN` + `SettingRepository._DATA_TABLES` (+ `_SIM_OUTPUT_TABLES` if Layer-4 re-persists), with `*_COLUMNS` const + `save_*`/`list_*`.
- **Scene scripts (UI) are NOT loaded by the headless suite** — `--check-only -s` each + godot-ai MCP verify (the `var x := untyped_helper()` parse-error trap).
- **All calibration constants live on `SimConstants`** (one balance-pass file); tested as invariants, not pinned equalities. New: `coagulation_reach_base`, `coagulation_reach_per_tier`, `depopulate_pop_keep` (retune), shatter tier gate.
- **Stale docs to reconcile** as phases land: `gdd-history-simulation.md` §11.1 event-type enum + §18 history; `gdd-campaign-creation-ui.md` §6/§9 (per-sovereign log + export not yet specced).

---

## 6. Open tuning items (defaults proposed; confirm during the relevant phase)
- Depopulation softening exact value (`0.28` keep ⇒ −20% loss) — confirm interpretation.
- Shatter floor tier (Principality vs Kingdom) and successor count.
- `coagulation_reach(tier)` curve and whether coagulation can cross alignment lines (proposed: same-majority-culture only, any alignment).
- Tier-disparity war weighting curve (how steep the Empire-vs-Barony asymmetry is).
- Whether founding events are worth the log noise (proposed: emit, let the UI significance filter manage volume).

---

## 7. Phase 5 as-built (IMPLEMENTED 2026-06-18)

**Data model — `setting_domains`** (migration 170): one row per vassal domain *within* a polity's own territory. `polity_id` = owning polity (sovereign OR war-vassal — every alive civ polity decomposes its own crownland, so the union accounts for all families). `liege_domain_id` = parent domain (`''` = directly under the polity ruler). `id` is `dom_<q>_<r>` (per-hex leaf) or `idom_<q>_<r>_<depth>` (interior grouping node). Columns: `tier_index, title, ruler_class, ruler_level, ruler_name, realm_name, seat_q, seat_r, families, hex_count, depth, is_personal_domain`. Registered in `SettingRepository._DATA_TABLES`/`_SIM_OUTPUT_TABLES` + `DOMAIN_COLUMNS` + `save_domains`/`list_domains`, and `CampaignRepository._SCOPE_DIRECT_CAMPAIGN`. Saved in BOTH orchestrator passes (`_run_history_sim` + `_run_naming`).

**Decomposition — `HistorySimulator._decompose_all`** (runs in `_finalize` after handoff; `ctx["sim_domains"]`): for each alive **civ** polity (beastman/clan skipped — no feudal ladder, req H), if `_export_tier > Barony` and it owns >1 populated hex, build a **complete feudal ladder** over its populated hexes (Jedidiah 2026-06-18 rework — the flat per-hex-sibling version made the handoff invent every Count/Marquis):
- **`_split_realm(hexes, node_tier, liege, depth)`** — builds the children (one rank down) of a realm. **Peel** the hexes already big enough to stand as a `(node_tier−1)` realm by their own families → each a **leaf** at its family rank, directly under the lord (a real County-hex stays a County, not pushed down). **Cluster** the smaller remainder (`_cluster_for_tier`, ≈ one child-tier family-floor each) into synthesized `(node_tier−1)` **nodes** that recurse — so a Marquis sits under a Count, a Baron under a Marquis, *for the most part*. Single-hex clusters skip a level (acceptable). `_emit_leaf` clamps a leaf's title to ≤ its slot (a vassal never out-ranks its lord). Down to Barony.
- **Why (req A/C):** every settled hex is a leaf realm at its own rank (req C); the intermediate Counts/Marquis are **synthesized so the tree is complete** and the runtime handoff only fills sub-hex (6-mile) detail — it never reorganises or invents the middle tiers. Some over-sizing / under-fill / skip-level is expected and RAW-legal (room for a player to become the missing Count). Branching is *not* hard-capped at 4–6 — a sparse realm yields fewer, fuller children; a dense one more — geography + family floors drive it.
- **Handoff contract:** every domain (leaf or node) carries `seat_q/seat_r` (its 24-mile hex, req B) + `liege_domain_id` (its direct tribute lord; `''` = the polity ruler in `setting_polities`, whose own liege chain is the inter-realm war-vassalage). The union of leaf seats tiles every populated hex; interior nodes' seats coincide with a leaf in their subtree. So the handoff maps `24-mi hex → leaf → liege chain → polity → sovereign`, and derives the count of sub-hex (6-mile) realms to invent from each leaf's tier. Calibration on seed 30641663: 211 flat → 295 nested domains, `max_depth` 0 → 4, tiers now span Barony→Principality.
- **User knob — `vassal_consolidation`** (`SettingParameters`, default 1.0; Advanced → History slider 1.0–3.0): `_cluster_for_tier` targets `tier_floor × vassal_consolidation` families per synthesized vassal. 1.0 = granular (more, thinner vassals); higher = fewer, fuller mid-tier realms (a Duke with 3–4 big Counts, not 6 thin ones), leaving more vacant seats for a player to claim. Finalization-only (re-partitions the sim result, never the history); rides the share code (default stays out of the token). Verified: higher value → fewer intermediate nodes, per-hex leaves unchanged.
- **Seats** (`_seat_of`): each node's highest-population hex (canonical tiebreak) — req B. Deterministic: contiguous BFS + integer family math; the only RNG is per-domain ruler-class (`decompose_class` stream).
- **Accounting invariant** (tested): a decomposed polity's leaf seats tile *exactly* its hexes (disjoint, exhaustive); interior `families`/`hex_count` are subtree aggregates (display only — sum LEAVES for accounting).

**Naming — `NameGenerator._name_domains`** (Layer 5): fills `ruler_name` (a dynasty house) + `realm_name` for every domain, in id order after the sovereigns so the per-culture dedup set carries over. The sim leaves both empty.

**UI — `screen_review.gd`**: Realms tab filters to `liege_id == ''` sovereigns (`_refresh_realms`, re-run by `bind_map` once the liege map is known). Vassalage tab is a native collapsible `Tree` (`_tree_tab`, `hide_root`, every item `collapsed=true`) that **fuses** the war-vassal polity nesting with each polity's `setting_domains` decomposition: a sovereign expands to its crownland domains (Dukes→Counts→county-hexes) **and** its war-vassal/protectorate polities (each recursing). `set_domains()` wired into the REVIEW phase of `campaign_creation_flow.gd`.

**Verification:** suite 463/17 net-zero (SettingBeastmanTests +6 decomposition tests, SettingStage7Tests + round-trip + end-to-end `test_domains_valid`). Scene scripts `--check-only` clean (autoload false-positive aside) + `game_eval`-verified in the running engine (sovereign-only Realms = 1 row; unified collapsible tree with correct nesting + labels). Pixel screenshot was blocked by an unfocused-window capture-staleness quirk in the MCP session (not a code defect).

**Follow-up fixes (2026-06-18, post-review of seed 30641663):**
- **Empty baronies dropped** — `_decompose_polity` partitions only POPULATED hexes (`population_band > 0`). Titular-claimed wilderness (pop-0, §H Phase 3b) no longer becomes rulerless 0-family Baronies; it stays polity-titular land with no domain (M2b attaches it to the nearest populated domain). The export tier (title) still counts the whole realm. On the review seed: map-wide empty baronies 41→0.
- **Tier-graded map borders** — `political_map_view._realm_border` / `_border_style` weight each realm's outline by its owner's RANK: Empire 3.0px → Kingdom 2.6 → Principality 2.1 → Duchy 1.6 (solid), County 1.2 and March/Barony 1.0 (DOTTED via `draw_dashed_line`), interior the faint per-hex grid. (Replaced the first-pass binary sovereign/vassal border, which made the many small low-tier realms' frontiers drown out the big realms.) `set_polity_meta` gained a `tiers` map (threaded from `screen_review` + `screen_generate_replay`). The `setting_domains` decomposition itself is still not painted on the map (the map keys on `hex → owner_polity_id`).
- **Kept as-is** (RAW-faithful, Jedidiah's call): a Duchy holding its counties directly (no tier between Duchy and County); a sovereign holding a couple of direct counties when the contiguous-BFS partition isolates single hexes and the would-be Dukes are near their family cap.

**Deferred to M2b:** runtime seat materialization (`domains.location_*`, per-hex 6-mile child seats); attaching titular wilderness to the nearest populated domain; sub-County (March/Barony) splitting; whether large clanholds / multi-hex County-tier realms should get internal structure (currently held directly / skipped); cleanup of the now-dead `internal_vassals` JSON blob (`_internal_vassals_json` still written to `setting_polities` — superseded by `setting_domains`, safe to retire when the materializer stops reading polity rows).
