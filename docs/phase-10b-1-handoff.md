# Phase 10B.1 — Magical Research Block — Session Handoff Prompt

> **Purpose.** This document is a self-contained briefing for a fresh build session that will plan and implement Phase 10B.1 (the Magical Research class-bucket block + all of its sub-systems). It survives compaction, lists every file the next session must read, captures every decision already locked in, and flags every ambiguity the planner needs to surface to Jedidiah.
>
> **How to use it.** Paste the contents of this file (or just point at the path) as the opening message of a new session. The session should follow the standard "Build Session Protocol" in `CLAUDE.md` first, then read this document, then begin the grounding investigation described in §3 below.
>
> **Status:** Drafted 2026-05-11 immediately after Phase 10A.3 landed. Phase 10A is complete; suite at 264 passed / 25 failed.

---

## 1. Where the project is

**Phase 10A shipped (2026-05-09 → 2026-05-11):**

- **10A.1** — Class-Specific sub-tab shell + `ClassBucketResolver` (single source of truth for class-bucket detection) + visibility wiring + GDD updates (Lightblessed rename, §12.1 matrix, §12.6/§12.7 rewrites).
- **10A.2** — Faith block (full). 8 RAW divine activities + congregants + character_divine_power + consecrated_altars + pending_divine_effects + monthly tick integration. 21 tests passing.
- **10A.3** — Bardic Patronage class-bucket (Chronicles aura + Solicit Followers) **plus** proficiency-gated training launchers in the Garrison sub-tab (re-architected from class-gated per **Q14**: Manual of Arms proficiency is the canonical gate, not class identity). 16 tests passing.

**Phase 10B.1 (this handoff)** ships the **Magical Research block**: the surface that lets mages, warlocks, witches, elven courtiers/enchanters/spellswords/nightblades, and Lightblessed Wonderworkers conduct research projects (spells, items, monsters), maintain libraries/workshops, and host apprentices and aspirants.

**Phase 10B.2 / 10B.3** (Trade / Syndicate) depend on the parallel "Phase 10B-prerequisite session" that builds the Common/Precious Merchandise registries + MarketPriceResolver + per-settlement merchant pools (see `docs/phase-10b-subsystem-dependencies.md`). **10B.1 is mostly independent** of that prereq session, except for the Lightblessed stacking with the already-shipped Faith block (10A.2).

---

## 2. Why this is a big phase

Magical Research is by far the largest sub-phase in Phase 10. It covers a half-dozen distinct sub-systems that the RAW treats as facets of one mechanic:

1. **Spell research** — invent new spells from scratch
2. **Spell rewriting / replacing / scribing** — manage your repertoire (mages) or spellbooks
3. **Magic item enchanting** — make potions, scrolls, permanent magic items
4. **Construct creation** — golems, animated objects, animate-dead variants
5. **Cross-breeding & monster creation** — create new monster species
6. **Custom spell building** — full PC custom-spell design rules (the variables that determine target, level, cost, time)
7. **Magic experimentation** — alternate mechanic where mages take risks for faster/cheaper progress
8. **Library & workshop infrastructure** — physical sites that gate higher-level work and provide research-throw bonuses
9. **Sanctum apprentices/aspirants** — followers attracted by a mage/Lightblessed stronghold
10. **Wonderworker dual-list** — Lightblessed's ability to research targets on the cleric divine spell list as well as the arcane list
11. **Mage's dungeon-under-tower hook** — Q9-shortcut hook into encounter frequency (flat modifier; full dungeon-stocking deferred)

That's ~6,000 lines of RAW across 7 XML files plus the spell-system GDD (1,804 lines) and domain-tab GDD §12.7 (the Lightblessed prose). **Do not try to load all of it at once.** Use the wave-split in §6 below; load only the RAW for the wave you're currently working on.

---

## 3. Required reading (in priority order)

Read in this order at the start of the session. Most of these are large — use Grep to find sections rather than loading whole files when you can.

### 3.1 Project foundation (always read first per `CLAUDE.md`)
- `CLAUDE.md` (project root)
- `build_log.md` (read tail entries; the Phase 10A.1/10A.2/10A.3 entries are the most recent)
- `docs/acks_arbiter_design_brief_v11.md` (Grep the sections relevant to the work)
- `docs/document_map.md`, `docs/rule_system_map.md`
- `docs/coding_conventions.md` — pay close attention to §49 (class-bucket detection) and §50 (proficiency-gated activity patterns); these were added in Phase 10A.3 and Phase 10B.1 should add §51+ as it establishes new conventions.

### 3.2 Phase 10 context (small; read fully)
- `docs/phase-10-plan.md` — read **§Phase 10B.1** in full. The Q1-Q14 resolution block at the top is also locked policy.
- `docs/phase-10b-subsystem-dependencies.md` — confirms what 10B.1 does NOT depend on (most of it is for 10B.2/10B.3).

### 3.3 RAW — Magical Research (the big six)
Read these in this order; **do NOT** load all of them in one session. Plan the wave-split (§6) first, then load only the file(s) for the wave you're starting.

| File | Lines | Coverage |
|---|---|---|
| `rules/acore-campaign-general-and-magic-research.xml` | 720 | Master rule: research throw target table, time/cost formulas, library/workshop infrastructure, **enchanting**, **constructs**, **cross-breeding**. **Start here.** |
| `rules/ax_campaign_play.xml` | 1256 | `<category name="magical_research">` block — the activity definitions (research_magic, rewrite_spell, replace_spell, scribe_spell, manage_assistant). Grep for `<category name="magical_research">`. Other categories in this file are out of scope for this phase. |
| `rules/pc_custom_spell_creation_rules.xml` | 978 | PC-side spell-design rules: variables, target/range/duration cost ladders, level estimation, spell-formula validation. |
| `rules/pc_magic_experimentation.xml` | 770 | Alternate mechanic — risk-taking for faster/cheaper research. Separate from the main throw, can layer on top. |
| `rules/le_monster_creation.xml` | 810 | Cross-breeding + monster-from-scratch rules. Ties into `MonsterRegistry`. |
| `rules/acore-campaign-hijinks.xml` | 1092 | **Sanctum** sub-section (L527-617) covers apprentice/aspirant arrival, dungeon-under-tower mechanic (per Q9), and the standard sanctum 1d6-month-promotion rule (per Q13). Grep for `<sanctum>` and `<dungeon>`. |
| `rules/ax_codex_and_scroll_magic.xml` | 583 | Codex + scroll mechanics — scribing rates, scroll prices, codex restrictions. Mostly cross-referenced from §scribe_spell. |
| `rules/acore_treasure_and_magic_items_rules.xml` | 419 | Magic item baseline gp values + the categorization that drives enchanting time/cost. |

### 3.4 RAW — adjacent context (Grep, don't read fully)
- `rules/acore_campaign_classes.xml` — Grep for `<spell_research>`, `<spell_research_and_minor_item_creation>`, `<arcane_casting>`, `<arcane_casting_in_armor>`, `<stronghold_sanctum>`, `<stronghold_tower>`, and each Lightblessed/Witch/Elven entry.
- `rules/acore_proficiencies_rules.xml` — Grep for `Magical Engineering`, `Loremastery`, `Naturalism`, `Healing` (any proficiency that grants research-throw bonuses).

### 3.5 GDDs (read fully or by section)
- `generation/gdd-spell-system.md` (1,804 lines) — Grep for `research`, `custom spell`, `enchanting`, `repertoire`. Sections covering spell formulas + repertoire mechanics are needed for `rewrite_spell` / `replace_spell` / `scribe_spell`.
- `generation/gdd-domain-tab.md` §12 — read fully. §12.4 (Magical Research block UI) and §12.7 (Lightblessed dual-list) are the canonical spec for this phase's UI.
- `generation/gdd-stronghold-construction.md` — sanctum + tower structures (libraries are inside sanctums; workshops are inside towers).
- `generation/gdd-management-notebook.md` — notebook surface architecture (already established; this phase just adds blocks).

### 3.6 Existing engine code (read fully)
- `engine/subsystems/domains/class_bucket_resolver.gd` — magical_research bucket detection is already defined; do NOT redefine the rules. Confirm the existing list covers all classes that need this block.
- `engine/subsystems/activities/handlers/faith/magic_research_throw_util.gd` — the throw helper. **This is shared infrastructure used by Phase 10A.2 already.** Phase 10B.1 will use it for every research / enchanting / construct throw, passing `ability_mod_kind="int"` (RAW default; only divine activities use `"wis"`).
- `engine/subsystems/spells/spell_registry.gd` + `repertoire_engine.gd` — for spell-data lookups. `rewrite_spell`/`replace_spell`/`scribe_spell` will mutate `character_repertoire`/`character_spellbook` rows; the schema for those already exists.
- `engine/subsystems/session/handlers/domain_handlers.gd` — `_resolve_domain_month` is the monthly-tick hub. Magical Research adds:
  - Resolve in-progress `magic_research_projects` (advance days_completed; on completion, apply the effect)
  - Wonderworker-aspirant attrition roll (per Q2)
  - Sanctum apprentice arrival (per the sanctum RAW)
- `engine/autoloads/campaign_repository.gd` — pattern for adding helpers (see the faith helpers at the bottom from Phase 10A.2). Phase 10B.1 will add a similar block of magical_research helpers.
- `engine/autoloads/event_bus.gd` — pattern for adding signals (the faith block added 6; this phase will add ~8-12).
- `scenes/ui/notebook/domain/blocks/faith_block.gd` — **the canonical UI template.** Mirror its structure (card grid, launcher buttons, status banner) when building `magical_research_block.gd`.
- `engine/subsystems/activities/handlers/faith/faith_handlers_registration.gd` — registration pattern for new handler classes.

### 3.7 Database (always check before adding a migration)
- `db/schema.sql` (canonical current schema, header bumped to migration 091)
- `db/migrations/091_faith_block.sql` (template for the Phase 10B.1 migration — likely `092_magical_research.sql`)

---

## 4. Decisions that are already locked

These came out of Phase 10A's Q1-Q14 resolution; do not re-litigate them.

- **Lightblessed Wonderworker** is the canonical name everywhere (per Q1 — legal reasons). No "Nobiran" anywhere.
- **Lightblessed apprentices/aspirants split 50/50** mage/cleric at sanctum founding (Q2; not INT-vs-WIS dynamic). Mage-intent aspirants get INT floor of 9 at creation; cleric-intent aspirants get WIS floor of 9.
- **Aspirant promotion (Q20 [RESOLVED 2026-05-11]):** universal fixed-4-month timer, then a single d20 + INT (mage intent) or WIS (cleric intent) throw. 14+ promotes to 1st level of intended class; 13 or less leaves the sanctum. NO monthly attrition. Applies to ALL sanctum classes (standard Mage / Witch / Warlock / Elven Enchanter / Lightblessed), not just Lightblessed.
- **The prior 1d6/month-for-6-months attrition mechanic is SCRAPPED.** Any reference to it in older docs is stale; the Q20 universal mechanic supersedes it.
- **Mage/Cleric aspirant throws use INT-modified / WIS-modified** respectively (Q13 — timing superseded by Q20's fixed 4 months; ability-modifier choice unchanged).
- **Witch is a divine caster** that also has `spell_research` → it stacks `[magical_research, faith]` buckets (Q11). **The Witch is in scope for this phase**, on the magical_research side.
- **Bladedancer's** `spell_research_and_minor_item_creation` is restricted and does NOT trigger the magical_research bucket. Bladedancer is faith-only (Q11). **Do not add Bladedancer to this phase.**
- **Darkblood Ruinguard** is an arcane caster (`arcane_casting_in_armor`), classified as `[magical_research]` only (Q12). It IS in scope for this phase.
- **Magic Research Throw uses INT modifier** (RAW); the `magic_research_throw_util.gd` helper already supports `ability_mod_kind="int"` (default) and `"wis"` (divine only).
- **The Mage's dungeon-under-tower hook (Q9)** is a flat encounter-frequency multiplier in v1, NOT full RAW dungeon-stocking. Build log MUST document this shortcut. Full dungeon-stocking-with-monsters is deferred to a dedicated dungeon-system phase.
- **The wave-split for Phase 10** is per `docs/phase-10-plan.md` — granular sub-phases. **Phase 10B.1 may be subdivided further** (see §6 below) if the planner deems it useful.

---

## 5. Open clarification questions to raise with Jedidiah

These are likely to surface during planning. Raise them **before** writing code so the answers are locked in the plan doc.

### Q15. Phase 10B.1 wave-split [RESOLVED 2026-05-11]

Approved as drafted in §6: 10B.1a (schema + shell — shipped) through 10B.1h (UI polish).

### Q16. Scope of "research_magic" handler [RESOLVED 2026-05-11]

UI exposes separate launcher cards per target type (Research New Spell / Research Magic Item / Create Construct / Create Monster) plus rewrite_spell / replace_spell / scribe_spell / manage_assistant. Backend stays unified on a single `research_magic` activity row with project_kind discriminator. 10B.1a ships the cards in disabled state; each becomes live as its wave's handler lands.

### Q17. PC custom-spell creation flow

`pc_custom_spell_creation_rules.xml` is a 978-line ladder of variables (range, duration, target count, damage type, etc.). v1 options:
- **(a)** Full builder UI letting the player assemble a custom spell variable-by-variable, with live level/cost calculation
- **(b)** Constrained picker: choose from pre-authored "research templates" that have known level/cost, hides the underlying ladder
- **(c)** Defer to v1.1: in v1, research-magic targets are limited to existing-spell-list spells of higher level than currently known (RAW `replace_spell` covers this case)

Recommend (c) for v1 with the builder as a flagged backlog item; confirm with Jedidiah.

### Q18. Magic experimentation (pc_magic_experimentation.xml)

This is an alternate mechanic where mages take risks for faster/cheaper progress. Two options for v1:
- **(a)** Implement as a togglable mode on `research_magic` launches with full failure/mishap tables
- **(b)** Defer to v1.1; ship base research only

Recommend (b); confirm.

### Q19. Monster creation / cross-breeding scope

`le_monster_creation.xml` is its own beast (no pun intended). Scope options:
- **(a)** Ship full RAW: cross-breeding, monster-from-template, monster-from-scratch, breed-true requirements
- **(b)** Ship only cross-breeding (the most common case); defer scratch-built monsters
- **(c)** Defer all monster creation to v1.1; in v1, the only research-magic targets are spells + items + simple constructs (skeletons, zombies, animated objects)

This will likely be a large sub-wave of its own. Recommend (c) for the first cut, then a dedicated wave 10B.1f for monster creation if scope allows.

### Q20. Wonderworker aspirant promotion mechanic [RESOLVED 2026-05-11]

The 1d6/month-for-6-months attrition mechanic is **fully scrapped** in favor of a simple RAW-rooted universal rule that should have been canonical from the start:

1. Every 0-level aspirant is created as a Normal Man.
2. For Lightblessed sanctums, the 50/50 mage/cleric split (Q2) determines `intended_class`. Mage aspirants get INT boosted to 9 if rolled lower; cleric aspirants get WIS boosted to 9 if rolled lower.
3. For standard Mage / Witch / Warlock / Elven Enchanter sanctums, all aspirants share the caster's class intent (no ability-floor adjustment).
4. After **exactly 4 months** (joined_calendar_day + 120), each aspirant rolls a single d20 + ability_mod (INT for mage intent, WIS for cleric intent). 14+ promotes to 1st level of intended_class; 13 or less leaves the sanctum.
5. **No monthly attrition rolls.** The 4-month promotion throw is the sole attrition check.

Schema: aspirants live in the `followers` table with source_kind='aspirant', character_class='normal_man', level=0, intended_class set, status='aspirant_in_training', promotion_eligible_day = joined_calendar_day + 120. The monthly-tick resolver in 10B.1d fires the promotion roll for due rows.

### Q21. Library/workshop residency requirement

RAW requires the caster to be present at the library/workshop for the duration of the research. How is "presence" tracked in v1 — explicit player travel + handler eligibility check, or assumed-present-while-active-activity-is-running? See `acore-campaign-general-and-magic-research.xml` for the RAW phrasing.

### Q22. Library/workshop construction surface [RESOLVED 2026-05-11]

Reuse stronghold-construction. Libraries and workshops are sub-structures of sanctums / towers. `libraries` and `workshops` tables reference an existing `stronghold_id` FK; no separate construction activity. Note: future stronghold-system task will expand the abstracted-to-gp-value sub-structure model (Keeps, Curtain Walls, etc. each have distinct SHP and garrison capacity effects).

### Q23. Item enchanting — costs and time

`acore-campaign-general-and-magic-research.xml` §enchanting has detailed time/cost formulas tied to item gp value. v1 should ship the full formula, not a stub. Confirm.

### Q24. Construct creation — necromancy specifically

`animate_dead` (spell) is one source of skeletons/zombies; the magical-research `create_construct` activity is another (with permanent results and higher-tier constructs like golems). Per RAW these are distinct:
- The spell creates temporary undead controlled by the caster
- The research project creates permanent constructs that count toward followers/garrison

Confirm: Phase 10B.1 ships the **research-project flavor only**; the spell side is already in `animate_dead_resolver.gd` (`engine/subsystems/spells/custom_resolvers/`).

### Q25. Apprentice/aspirant data model [RESOLVED 2026-05-11]

NEW `followers` table — distinct from `characters` (henchmen / PCs / NPCs) and from `troop_units` (mass-bookkept hirelings). Encompasses mage/cleric/witch/warlock/elven_enchanter aspirants, 1st-3rd level same-class followers, same-race race followers (elf/dwarf non-casters), bard recruits (retro-migrated from Phase 10A.3), future venturer apprentices (10B.2) and syndicate members (10B.3).

Followers are "almost-henchmen": they gain XP and treasure shares like henchmen when on adventure with the owner, but not when left at the stronghold. The player can promote a follower into the henchmen pool via `CampaignRepository.promote_follower_to_henchman` when slots are available — no hiring reaction roll required.

source_kind enum (extensible): `aspirant | class_follower | race_follower | bardic_recruit | venturer_apprentice | syndicate_member | generic`. status enum: `aspirant_in_training | present | on_adventure | departed | promoted_to_henchman | failed_promotion`. intended_class is set for aspirants (mage / cleric / witch / warlock / elven_enchanter).

Q25a [RESOLVED 2026-05-11]: Phase 10A.3's `solicit_followers` handler rewritten in 10B.1a to insert into `followers` instead of `characters`. No data migration needed (no campaigns had bard-recruit rows yet).

---

## 6. Suggested wave-split for Phase 10B.1 (subject to Q15)

Each wave is one session's worth of work (3-5 hours of focused build time):

| Wave | Scope | Tests target |
|---|---|---|
| **10B.1a** | Schema (`092_magical_research.sql`) + libraries/workshops repository helpers + Magical Research block shell (cards for sub-systems wired but disabled) + monthly-tick stub | 8-10 unit tests on repos |
| **10B.1b** | `research_magic` for spell targets only (existing spells from registry, no custom-builder); `rewrite_spell`, `replace_spell`, `scribe_spell` handlers + repertoire/spellbook mutations | 15-20 tests |
| **10B.1c** | Magic item enchanting (potions, scrolls, permanent items) — full RAW gp/time formulas + research throw on completion | 12-15 tests |
| **10B.1d** | Sanctum apprentices/aspirants — arrival mechanic, 1d6-month promotion, INT/WIS throw, Wonderworker 50/50 split + 1d6/month attrition | 10-12 tests |
| **10B.1e** | Construct creation (skeletons/zombies/animated objects/simple golems; defer higher-tier per Q24) | 8-10 tests |
| **10B.1f** | Cross-breeding / monster creation (per Q19 scope) — likely cross-breeding only in v1, full monster-from-scratch deferred | 6-8 tests |
| **10B.1g** | Lightblessed dual-list polish + Mage's dungeon-under-tower encounter-frequency hook (Q9) | 4-6 tests |
| **10B.1h** | UI polish: full Magical Research block UI per `gdd-domain-tab.md` §12.4 / §12.7; activity launcher cards; in-progress project list with progress bars; library/workshop status | 6-8 UI/integration tests |

**Total estimated test count for Phase 10B.1: 70-90.** Equivalent in size to all of Phase 10A combined.

A planner is welcome to merge or further split waves; the above is a strawman.

---

## 7. Patterns to follow (from Phase 10A — DO mirror these)

### 7.1 Class-bucket eligibility
- `ClassBucketResolver` is the single source of truth. **Do not** introduce ad-hoc class-id checks anywhere in this phase. If you find yourself writing `if class_id in ["mage", "warlock", ...]`, you're doing it wrong; call `ClassBucketResolver.has_bucket(character_id, "magical_research")` instead.
- **One exception:** the Lightblessed dual-list logic needs to know specifically that the active entity is Lightblessed. That's a class-id check (`class_id == "lightblessed_wonderworker"`) and is fine — it's not a bucket check.

### 7.2 Activity registration
- One JSON file per category: `data/activities/magical_research_category.json` (mirrors `divine_category.json`).
- One handler per activity in `engine/subsystems/activities/handlers/magical_research/`.
- One registration class at `engine/subsystems/activities/handlers/magical_research/magical_research_handlers_registration.gd` that registers all handlers with `ActivityHandlerRegistry`.
- Wire the registration into `engine/subsystems/session/session_runner.gd` next to the existing `FaithActivityHandlersRegistration.register_all` and `BardicActivityHandlersRegistration.register_all` calls.

### 7.3 Throw mechanic
- Use `MagicResearchThrowUtil.make_throw(caster_level, ability_modifier, magical_engineering_rank, roll_type)` for every research / enchanting / construct / monster throw.
- Pass `ability_mod_kind` indirectly by computing `MagicResearchThrowUtil.int_mod_for_character(character)` (or `wis_mod_for_character` for Wonderworker cleric-aspirants) and feeding it as `ability_modifier`.
- Magical Engineering proficiency rank should be looked up via the proficiency repository (Grep `engine/subsystems/proficiencies/` for the lookup helper).
- **Banker's rounding everywhere.** Use `RoundingUtil` (Grep for it).

### 7.4 Monthly-tick integration
- Pre-resolve modifiers (things that affect THIS month's resolution): compute in a pure function, return a Dict, the resolver applies.
- Post-resolve effects (things that affect FUTURE months): enqueue rows in a pending-effects table with a status enum lifecycle (`pending` / `applied` / `expired` / `cancelled`).
- For magical_research, the equivalent of `pending_divine_effects` is `magic_research_projects` (in-progress projects with `days_total`/`days_completed` ticking down monthly).
- Status enum lifecycle is the same pattern: `in_progress` / `completed` / `abandoned` / `failed`.

### 7.5 Ledger entries (audit trail, no gp moves)
- Use `category = "other"` with a meaningful `subcategory` like `"magical_research"`, `"enchanting"`, `"construct_creation"`, etc.
- **DO NOT** invent new ledger categories. The `ledger_entries.category` CHECK constraint allows only `'revenue', 'expense', 'tribute_in', 'tribute_out', 'investment', 'other'`. (Phase 10A.3 fixed a pre-existing bug where `train_troops` / `oversee_troop_training` were using `category="garrison"` — disallowed.)
- For actual gp moves (paying for materials, depositing earnings), use the correct revenue/expense category as usual.

### 7.6 Test structure
- One test file per logical surface: `tests/test_magic_research_research_magic.gd`, `tests/test_magic_research_libraries.gd`, etc.
- Per-class matrix coverage for the bucket: confirm magical_research surface is visible for Mage/Warlock/Witch/four Elven classes/Darkblood Ruinguard/Lightblessed; confirm it's hidden for everyone else.
- Cross-pollination guard: when testing pending/in-progress tables, purge between tests (see `_purge_pending_divine_effects()` pattern in `tests/test_faith_block.gd`).

### 7.7 UI block pattern
- One file: `scenes/ui/notebook/domain/blocks/magical_research_block.gd`.
- Mirror `faith_block.gd` structure: card grid, header banner (current research-throw target/INT mod), launcher buttons, in-progress project list, library/workshop status.
- Wire visibility through `class_specific_sub_tab.gd` (already in place from 10A.1).

### 7.8 Coding conventions
- Append `docs/coding_conventions.md` §51 with magical-research-specific conventions discovered during this phase.
- Anything that establishes a new pattern (e.g., how research-project state machines work, how library/workshop residency is tracked) should be documented immediately.

---

## 8. Anti-patterns from Phase 10A (DO NOT repeat)

- **GDScript precedence with typed-array casts.** `buckets == ["x"] as Array[String]` parses as `(buckets == ["x"]) as Array[String]`. Use plain `buckets == ["x"]`.
- **Combat progression as eligibility gate.** Phase 10A.3 (Q14) showed that combat-progression-based gates were wrong for at least one bucket (training is proficiency-gated, not class-gated). Always check whether the RAW gates on a proficiency, a power_id, or a class_id — not on combat_progression.
- **Reading the GDD instead of the JSON.** Phase 10A.3 test fixtures had `combat_progression` values that didn't match the JSON files. Always cross-check fixtures against `data/classes/*.json`.
- **Ledger category invention.** Use only `'revenue', 'expense', 'tribute_in', 'tribute_out', 'investment', 'other'`. New categories require a schema migration AND a CHECK update.
- **Trans-test data pollution.** Tests for monthly-tick resolvers must purge pending tables before each test, not just at suite setup.

---

## 9. Things that should NOT be touched in this phase

- **The Faith block** (Phase 10A.2) is complete. Magical Research stacks alongside it for Witch and Lightblessed; it does NOT modify the Faith block's behavior.
- **The Bardic Patronage block** (Phase 10A.3) is complete.
- **The Garrison sub-tab training launchers** (Phase 10A.3) are complete.
- **Phase 10B.2 (Trade) and 10B.3 (Syndicate)** — those depend on the parallel session and are out of scope here.
- **The spell-casting system** (`engine/subsystems/spells/`) — Magical Research mutates the repertoire/spellbook tables but does NOT modify how spells are cast. Custom spell creation generates new SpellRegistry entries but does NOT modify existing resolvers.
- **The MonsterRegistry** — cross-breeding/monster-creation will produce new entries in the monster catalog, but the registry's own API stays the same. (Note: the parallel monster-data session may also be modifying this; coordinate via build_log.)

---

## 10. Session opening checklist

When the fresh session starts:

1. Read `CLAUDE.md`, `build_log.md`, `docs/acks_arbiter_design_brief_v11.md`.
2. Read this file (`docs/phase-10b-1-handoff.md`) in full.
3. Read `docs/phase-10-plan.md` §Phase 10B.1.
4. Spot-check `db/schema.sql` header (should say "Last migration applied: 091").
5. **DO NOT** start loading magical-research RAW yet.
6. Raise the open questions (Q15-Q25) with Jedidiah. **Wait for answers.**
7. Once Q15 (wave-split) is locked, load ONLY the RAW for the first wave.
8. Plan that wave in detail (schema + handlers + tests). Get Jedidiah's sign-off on the plan.
9. Implement. Run `--headless --path . --import` after adding new `.gd` files, then run `tests/test_runner.tscn`.
10. Update `build_log.md` and `docs/coding_conventions.md` at session end.

---

## 11. Quick file inventory (what already exists vs. what's new)

### Already exists (Phase 10A — do not duplicate)
- `engine/subsystems/domains/class_bucket_resolver.gd` (magical_research bucket already defined)
- `engine/subsystems/activities/handlers/faith/magic_research_throw_util.gd` (the shared throw helper)
- `engine/subsystems/domains/troop_training_eligibility.gd` (Manual of Arms gate; reference pattern for proficiency lookups)
- `engine/subsystems/domains/faith_monthly_resolver.gd` (reference pattern for monthly-tick resolver)
- `engine/subsystems/activities/handlers/faith/faith_handlers_registration.gd` (registration pattern)
- `scenes/ui/notebook/domain/blocks/faith_block.gd` (UI block pattern)
- `data/activities/divine_category.json` (activity JSON pattern)
- `db/migrations/091_faith_block.sql` (migration pattern)
- `engine/autoloads/event_bus.gd` (signal pattern; faith block added 6 signals)
- `tests/test_faith_block.gd` (test pattern)

### To be created in Phase 10B.1
- `db/migrations/092_magical_research.sql`
- `data/activities/magical_research_category.json`
- `engine/subsystems/activities/handlers/magical_research/` (directory + 6-10 handlers)
- `engine/subsystems/activities/handlers/magical_research/magical_research_handlers_registration.gd`
- `engine/subsystems/domains/magical_research_monthly_resolver.gd`
- `engine/subsystems/domains/library_workshop_repository.gd` (or fold into CampaignRepository helpers — TBD by planner)
- `scenes/ui/notebook/domain/blocks/magical_research_block.gd`
- `tests/test_magical_research_*.gd` (~8 test files)

---

## 12. One last note

Phase 10A taught us that the RAW vs. GDD vs. JSON triangle is the most reliable source of mistakes in this codebase. When in doubt:
1. **RAW is sacred** (`rules/*.xml`) — never modify, always cite line numbers in comments.
2. **JSON is current** (`data/classes/*.json`) — the ground truth for class data structure.
3. **GDD is advisory** (`generation/*.md`) — modifiable, but check `acks_arbiter_design_brief_v11.md` for any "ACKS Constraints" sections within each GDD before editing.

If the three disagree, **stop and ask Jedidiah**. Don't try to reconcile silently. Phase 10A surfaced four such discrepancies (Witch divine+MR stacking, Darkblood arcane reclassification, Bladedancer/Assassin combat-progression mismatches, and the Q14 garrison-training-is-not-class-gated revelation). Phase 10B.1 will almost certainly surface more.

Good luck. The handoff is good; the work is large; the patterns from 10A are solid. Lean on them.
